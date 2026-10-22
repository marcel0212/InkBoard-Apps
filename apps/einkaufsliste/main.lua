-- Einkaufsliste (Paket einkaufsliste): gemeinsame Liste fuer alle InkBoards im Netzwerk. Eingabe per Handy-Seite (QR-Code),
-- Abhaken per Drehrad. Skript-API Level 20. Eintraege: Datei "items" (lokal) und optional "einkauf.txt" auf dem externen Speicher
-- (storagePath-Feld "dir"), pro Zeile "id TAB zeit TAB status TAB text" (status 0 offen, 1 erledigt, 2 geloescht = Grabstein).
-- Abgleich in on_fetch: je Eintrag gewinnt die neuere Zeit - so bleiben mehrere Geraete und Handys konfliktfrei.
-- Ohne externen Speicher arbeitet die Liste lokal ("nicht synchronisiert").

local NAS_FILE = "einkauf.txt"
local TOMB_SEC = 7 * 86400
local MAX_BYTES = 20000

local function T(ctx, de, en) return (ctx.lang == "en") and en or de end

-- ===== Daten =====

local function parse(text)
  local m = {}
  if text then
    for id, ts, st, tx in text:gmatch("([^\t\n]+)\t(%d+)\t(%d)\t([^\n]*)") do
      m[id] = { id = id, ts = tonumber(ts), st = tonumber(st), text = tx }
    end
  end
  return m
end

local function serialize(m, now, cleanup)
  local list = {}
  for _, e in pairs(m) do
    if e.st == 1 and cleanup > 0 and now - e.ts > cleanup then e.st = 2; e.ts = now end
    if not (e.st == 2 and now - e.ts > TOMB_SEC) then list[#list + 1] = e end
  end
  table.sort(list, function(a, b) if a.ts ~= b.ts then return a.ts < b.ts end return a.id < b.id end)
  -- zu gross: aelteste erledigte/geloeschte Eintraege zuerst weglassen
  local function join()
    local out = {}
    for i = 1, #list do out[i] = string.format("%s\t%d\t%d\t%s", list[i].id, list[i].ts, list[i].st, list[i].text) end
    return table.concat(out, "\n")
  end
  local s = join()
  local i = 1
  while #s > MAX_BYTES and i <= #list do
    if list[i].st ~= 0 then table.remove(list, i); s = join() else i = i + 1 end
  end
  return s
end

local function merge(a, b)
  for id, e in pairs(b) do
    local x = a[id]
    if x == nil or e.ts > x.ts then a[id] = e end
  end
end

-- sichtbare Liste: erst offene (Eingabereihenfolge), dann erledigte
local function visible(m)
  local open, done = {}, {}
  for _, e in pairs(m) do
    if e.st == 0 then open[#open + 1] = e elseif e.st == 1 then done[#done + 1] = e end
  end
  local f = function(a, b) if a.ts ~= b.ts then return a.ts < b.ts end return a.id < b.id end
  table.sort(open, f)
  table.sort(done, function(a, b) if a.ts ~= b.ts then return a.ts > b.ts end return a.id < b.id end)
  for i = 1, #done do open[#open + 1] = done[i] end
  return open, #open - #done, #done
end

local function load_local() return parse(file.read("items")) end

local function now_ts()
  local n = time.now()
  return n or 0
end

local function new_id(ctx)
  local s = system.get()
  local room = (s and s.room or "x"):sub(1, 2)
  local c = (tonumber(ctx.data.get("seq")) or 0) + 1
  ctx.data.set("seq", c % 4096)
  return string.format("%s%x%x", room, now_ts(), c)
end

local function cleanup_sec(ctx)
  local h = tonumber(ctx.cfg and ctx.cfg.cleanup) or 24
  return h * 3600
end

local function clean_text(t)
  t = tostring(t or ""):gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if #t > 60 then
    local i = 60
    while i > 1 and (t:byte(i + 1) or 0) & 0xC0 == 0x80 do i = i - 1 end
    t = t:sub(1, i)
  end
  return t
end

-- ===== Abruf: Abgleich mit dem externen Speicher =====

function on_fetch(ctx)
  local now = now_ts()
  local m = load_local()
  local pend = ctx.data.get("pend")
  if pend and pend ~= "" then
    for id in tostring(pend):gmatch("[^;]+") do
      local e = m[id]
      if e and e.st ~= 2 then e.st = (e.st == 0) and 1 or 0; e.ts = now end
    end
    ctx.data.set("pend", "")
  end
  local sync = "local"
  local cl = cleanup_sec(ctx)
  if storage.ready() then
    local remote, err = storage.read("dir", NAS_FILE)
    local rm
    if remote == nil and err == "nicht gefunden" then remote = ""; end
    if remote ~= nil then
      rm = parse(remote)
      merge(m, rm)
      local s = serialize(m, now, cl)
      if s ~= remote then
        local ok = storage.write("dir", NAS_FILE, s)
        sync = ok and "ok" or "error"
      else
        sync = "ok"
      end
    else
      sync = "error"
    end
  end
  local s = serialize(m, now, cl)
  file.write("items", s)
  ctx.data.set("sync", sync)
  if sync == "ok" then ctx.data.set("syncAt", now) end
  local _, open, done = visible(m)
  ctx.data.set("open", open)
  ctx.data.set("done", done)
  ctx.data.set("rev", (tonumber(ctx.data.get("rev")) or 0) + 1)
  return true
end

-- ===== Handy-Seite =====

local function esc(t)
  return (tostring(t):gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" end
    return " "
  end))
end

local function reply(status, body) return { status = status, body = body } end

-- Antwort der Handy-Seite als JSON-Text (es gibt kein json.encode)
local function list_json(ctx, m, full)
  local v, open, done = visible(m)
  local parts = {}
  for i = 1, #v do
    parts[i] = string.format('{"id":"%s","text":"%s","done":%s}', esc(v[i].id), esc(v[i].text), v[i].st == 1 and "true" or "false")
  end
  local sync = ctx.data.get("sync") or "local"
  local extra = ""
  if full then
    -- alle Eintraege inkl. Grabsteine (Mac-/iOS-App haelt eine eigene Kopie und gleicht sie ueber "sync" ab)
    local ents = {}
    for _, e in pairs(m) do
      ents[#ents + 1] = string.format('{"id":"%s","ts":%d,"st":%d,"text":"%s"}', esc(e.id), e.ts, e.st, esc(e.text))
    end
    extra = ',"entries":[' .. table.concat(ents, ",") .. ']'
  end
  return string.format('{"items":[%s],"open":%d,"done":%d,"sync":"%s","nas":%s%s}', table.concat(parts, ","), open, done, esc(sync), sync ~= "local" and "true" or "false", extra)
end

function on_http(ctx, req)
  local q = json.decode(req.body or "")
  if type(q) ~= "table" then return reply(400, '{"error":"JSON"}') end
  local op = tostring(q.op or "list")
  local m = load_local()
  local now = now_ts()
  local changed = false
  if op == "add" then
    local t = clean_text(q.text)
    if t == "" then return reply(400, '{"error":"leer"}') end
    -- mehrere Eintraege mit Komma/Zeilenumbruch? nein: ein Eintrag je Aufruf
    local id = new_id(ctx)
    m[id] = { id = id, ts = now, st = 0, text = t }
    changed = true
  elseif op == "toggle" then
    local e = m[tostring(q.id or "")]
    if e and e.st ~= 2 then e.st = (e.st == 0) and 1 or 0; e.ts = now; changed = true end
  elseif op == "del" then
    local e = m[tostring(q.id or "")]
    if e then e.st = 2; e.ts = now; changed = true end
  elseif op == "clear" then
    for _, e in pairs(m) do if e.st == 1 then e.st = 2; e.ts = now; changed = true end end
  elseif op == "sync" then
    -- Abgleich mit der lokalen Kopie der App: je Eintrag gewinnt die neuere Zeit (offline gepflegte Aenderungen kommen so nach).
    -- Zeitstempel aus der Zukunft (falsche Uhr am Client) werden auf "jetzt" gesetzt.
    local inc = q.entries
    if type(inc) == "table" then
      for i = 1, #inc do
        local x = inc[i]
        if type(x) == "table" and x.id ~= nil then
          local id = tostring(x.id):gsub("[%c]", "")
          local ts = tonumber(x.ts) or 0
          local st = tonumber(x.st) or 0
          if now > 0 and ts > now + 86400 then ts = now end
          local tx = clean_text(x.text)
          if id ~= "" and #id <= 24 and (st == 0 or st == 1 or st == 2) and (tx ~= "" or st == 2) then
            local cur = m[id]
            if cur == nil or ts > cur.ts then
              m[id] = { id = id, ts = ts, st = st, text = tx }
              changed = true
            end
          end
        end
      end
    end
  end
  if changed then
    file.write("items", serialize(m, now, cleanup_sec(ctx)))
    local _, open, done = visible(m)
    ctx.data.set("open", open)
    ctx.data.set("done", done)
    ctx.data.set("rev", (tonumber(ctx.data.get("rev")) or 0) + 1)
    local r = reply(200, list_json(ctx, m, op == "sync"))
    r.fetch = true
    r.redraw = true
    return r
  end
  return reply(200, list_json(ctx, m, op == "sync"))
end

-- ===== Drehrad =====

function on_input(ctx, kind, n)
  local m = load_local()
  local v = visible(m)
  local total = #v + 1 -- letzte Zeile = "Fertig"
  if #v == 0 then return false end
  local sel = tonumber(ctx.data.get("sel")) or 0
  if kind == "click" then
    if ctx.data.get("browse") ~= 1 then return false end
    if sel >= #v then
      ctx.data.set("browse", 0)
      return true
    end
    local e = v[sel + 1]
    if e then
      local p = tostring(ctx.data.get("pend") or "")
      ctx.data.set("pend", p .. e.id .. ";")
      return "fetch"
    end
    return true
  end
  if ctx.data.get("browse") ~= 1 then sel = 0 end
  ctx.data.set("browse", 1)
  ctx.data.set("sel", (sel + math.floor(n)) % total)
  return true
end

-- ===== Zeichnen =====

local function cut(text, maxw, font)
  while #text > 1 and draw.measure(text, font) > maxw do
    local i = #text
    while i > 1 and (text:byte(i) & 0xC0) == 0x80 do i = i - 1 end
    text = text:sub(1, i - 1)
  end
  return text
end

local function tick(x, y, s, col)
  draw.line(x + s // 5, y + s // 2, x + s * 2 // 5, y + s * 4 // 5, col)
  draw.line(x + s * 2 // 5, y + s * 4 // 5, x + s * 4 // 5, y + s // 5, col)
  draw.line(x + s // 5, y + s // 2 + 1, x + s * 2 // 5, y + s * 4 // 5 + 1, col)
  draw.line(x + s * 2 // 5, y + s * 4 // 5 + 1, x + s * 4 // 5, y + s // 5 + 1, col)
end

local function checkbox(x, y, s, done)
  if done then
    draw.rect(x, y, s, s, color.GREEN, true, 5)
    draw.rect(x, y, s, s, color.BLACK, false, 5)
    tick(x, y, s, color.BLACK)
  else
    draw.rect(x, y, s, s, color.BLACK, false, 5)
  end
end

local function sync_text(ctx)
  local s = ctx.data.get("sync")
  if s == "ok" then return T(ctx, "synchronisiert", "synced") end
  if s == "error" then return T(ctx, "Sync-Fehler", "sync error") end
  return T(ctx, "nicht synchronisiert", "not synced")
end

function on_draw(ctx, page)
  local style = ctx.cfg.style or "cards"
  draw.clear(color.WHITE)
  local m = load_local()
  local v, open, done = visible(m)
  local y0 = draw.top
  if #v == 0 then
    if device.qrscreen and device.qrscreen(T(ctx, "Einkaufsliste ist leer", "Shopping list is empty"), T(ctx, "QR-Code scannen und Dinge hinzufügen:", "Scan the QR code to add items:")) then return end
    draw.text(draw.width // 2, y0 + 150, T(ctx, "Einkaufsliste ist leer", "Shopping list is empty"), "large", color.BLACK, "center")
    return
  end
  local compact = (style == "compact")
  if compact then
    local keep = {}
    for i = 1, #v do if v[i].st == 0 then keep[#keep + 1] = v[i] end end
    if #keep > 0 then v = keep end
  end
  -- Kopf
  draw.text(28, y0 + 36, T(ctx, "Einkaufsliste", "Shopping list"), "large", color.BLACK, "left")
  draw.text(draw.width - 28, y0 + 22, string.format(T(ctx, "%d offen", "%d open"), open) .. (done > 0 and string.format(T(ctx, ", %d erledigt", ", %d done"), done) or ""), "normal", color.BLACK, "right")
  draw.text(draw.width - 28, y0 + 42, sync_text(ctx), "small", color.BLACK, "right")
  local rowH = compact and 56 or 46
  local top = y0 + 56
  local browse = ctx.data.get("browse") == 1
  local sel = browse and (tonumber(ctx.data.get("sel")) or 0) or -1
  local bottom = draw.height - 30
  local rows = (bottom - top) // rowH
  local total = #v + (browse and 1 or 0)
  local start = 0
  if sel >= rows then start = sel - rows + 1 end
  if sel < 0 and total > rows then rows = rows end
  local font = compact and "large" or "normal"
  for r = 0, rows - 1 do
    local i = start + r + 1
    if i > total then break end
    local y = top + r * rowH
    local isSel = (i - 1 == sel)
    if browse and i == #v + 1 then
      draw.rect(24, y + 2, draw.width - 48, rowH - 6, color.BLACK, false, 10)
      if isSel then draw.rect(24, y + 2, draw.width - 48, rowH - 6, color.YELLOW, true, 10) ; draw.rect(24, y + 2, draw.width - 48, rowH - 6, color.BLACK, false, 10) end
      draw.text(draw.width // 2, y + rowH // 2 + 6, T(ctx, "Fertig", "Done"), "normal", color.BLACK, "center")
    else
      local e = v[i]
      local isDone = e.st == 1
      if style == "cards" or isSel then
        if isSel then draw.rect(24, y + 2, draw.width - 48, rowH - 6, color.YELLOW, true, 10) end
        draw.rect(24, y + 2, draw.width - 48, rowH - 6, color.BLACK, false, 10)
      elseif style == "flat" then
        draw.line(28, y + rowH - 2, draw.width - 28, y + rowH - 2, color.BLACK)
      end
      local bs = compact and 32 or 26
      checkbox(42, y + (rowH - bs) // 2, bs, isDone)
      local tx = 42 + bs + 16
      local text = cut(e.text, draw.width - tx - 44, font)
      draw.text(tx, y + rowH // 2 + (compact and 9 or 7), text, font, color.BLACK, "left")
      if isDone then
        local w = draw.measure(text, font)
        draw.line(tx, y + rowH // 2 + 1, tx + w, y + rowH // 2 + 1, color.BLACK)
      end
    end
  end
  -- Fuss
  local more = total - (start + rows)
  local foot
  if browse then foot = T(ctx, "Drehen: wählen   Klick: abhaken", "Turn: select   Click: tick off")
  elseif more > 0 then foot = string.format(T(ctx, "+ %d weitere", "+ %d more"), more)
  else
    local u = device.url and device.url() or nil
    foot = u and (T(ctx, "Handy: ", "Phone: ") .. u) or ""
  end
  draw.text(28, draw.height - 10, cut(foot, draw.width - 56, "small"), "small", color.BLACK, "left")
end

function on_widget(ctx, box)
  local style = ctx.cfg.style or "cards"
  local m = load_local()
  local v, open, done = visible(m)
  local cx = box.x + box.w // 2
  if #v == 0 then
    draw.text(cx, box.y + box.h // 2 + 6, T(ctx, "Liste leer", "List empty"), "normal", color.BLACK, "center")
    return
  end
  -- CHANGELOG 854: Eintraege immer lesbar zeigen (vorher nur "2 offen" in kleinen/kompakten Widgets). Kleine Boxen: 9pt-Schrift in
  -- engeren Zeilen; Stil "Kompakt" (und breite Boxen): grosse Zahl links, Eintraege rechts daneben.
  local small = box.h < 90
  local lh = small and 19 or 26
  local font = small and "small" or "normal"
  local bs = small and 12 or 18
  local left = 0
  if style == "compact" and box.w >= 150 and box.h >= 44 then
    left = 52
    draw.text(box.x + left // 2, box.y + box.h // 2 + 6, tostring(open), "large", open > 0 and color.BLACK or color.GREEN, "center")
    draw.text(box.x + left // 2, box.y + box.h // 2 + 22, T(ctx, "offen", "open"), "small", color.BLACK, "center")
    draw.line(box.x + left + 2, box.y + 8, box.x + left + 2, box.y + box.h - 8, color.BLACK)
  end
  local rows = (box.h - 6) // lh
  if rows < 1 then
    draw.text(cx, box.y + box.h // 2 + 10, tostring(open), "huge", open > 0 and color.BLACK or color.GREEN, "center")
    draw.text(cx, box.y + box.h - 6, T(ctx, "offen", "open"), "small", color.BLACK, "center")
    return
  end
  local shown = 0
  local tx = box.x + left + 8 + bs + 8
  for i = 1, #v do
    if shown >= rows then break end
    if v[i].st == 0 then
      local y = box.y + 4 + shown * lh
      checkbox(box.x + left + 8, y + (lh - bs) // 2, bs, false)
      draw.text(tx, y + lh // 2 + (small and 4 or 6), cut(v[i].text, box.x + box.w - tx - 8, font), font, color.BLACK, "left")
      shown = shown + 1
    end
  end
  if open > shown and shown > 0 then
    draw.text(box.x + box.w - 8, box.y + box.h - 4, string.format("+%d", open - shown), "small", color.BLACK, "right")
  end
  if open == 0 then draw.text(cx, box.y + box.h // 2 + 6, T(ctx, "Alles erledigt", "All done"), "large", color.GREEN, "center") end
end
