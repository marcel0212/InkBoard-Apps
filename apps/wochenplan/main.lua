-- Wochenplan (Paket wochenplan): wiederkehrender Plan fuer die Woche - je Wochentag beliebige Eintraege, optional mit Person
-- (Essen, Training, Aufgaben, Termine). Eingabe per Handy-Seite (QR-Code). Skript-API Level 23.
-- Eintraege: Datei "items" (lokal) und optional "wochenplan.txt" auf dem externen Speicher (storagePath-Feld "dir"),
-- pro Zeile "id TAB zeit TAB status TAB tag TAB person TAB text" (status 0 aktiv, 2 geloescht = Grabstein; tag 1 = Montag ... 7 = Sonntag).
-- Das Feld "tag" traegt optional eine Kalenderwoche: tag = KW-Schluessel * 10 + Wochentag (KW-Schluessel = ISO-Jahr * 100 + KW, z. B. 2026421
-- = Montag in KW 42/2026); 0 als Schluessel = wiederkehrend jede Woche (Wert 1..7). Aeltere Staende ignorieren Wochen-Eintraege einfach.
-- Abgleich in on_fetch: je Eintrag gewinnt die neuere Zeit - mehrere Geraete und Handys bleiben konfliktfrei.
-- Ohne externen Speicher arbeitet der Plan lokal ("nicht synchronisiert").

local NAS_FILE = "wochenplan.txt"
local TOMB_SEC = 7 * 86400
local MAX_BYTES = 20000
local DOT = { color.BLUE, color.RED, color.GREEN, color.YELLOW }

local function T(ctx, de, en) return (ctx.lang == "en") and en or de end
local DAYS_DE = { "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag" }
local DAYS_EN = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" }
local SHORT_DE = { "Mo", "Di", "Mi", "Do", "Fr", "Sa", "So" }
local SHORT_EN = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
local function day_name(ctx, d) return (ctx.lang == "en" and DAYS_EN or DAYS_DE)[d] end
local function day_short(ctx, d) return (ctx.lang == "en" and SHORT_EN or SHORT_DE)[d] end

-- ===== Daten =====

-- Kalenderwoche der Gegenwart als Schluessel ISO-Jahr * 100 + KW (nil ohne Uhr)
local function cur_wk()
  local lt = time.localtime()
  if not lt or not lt.week then return nil end
  local y = lt.year
  if lt.week >= 52 and lt.month == 1 then y = y - 1
  elseif lt.week == 1 and lt.month == 12 then y = y + 1 end
  return y * 100 + lt.week
end

local function parse(text)
  local m = {}
  if text then
    for id, ts, st, dy, pe, tx in text:gmatch("([^\t\n]+)\t(%d+)\t(%d)\t(%d)\t([^\t\n]*)\t([^\n]*)") do
      local v = tonumber(dy)
      m[id] = { id = id, ts = tonumber(ts), st = tonumber(st), day = v % 10, wk = v // 10, person = pe, text = tx }
    end
  end
  return m
end

local function serialize(m, now)
  local list = {}
  local cw = cur_wk()
  for _, e in pairs(m) do
    local old = cw ~= nil and e.wk > 0 and e.wk < cw - 2 -- abgelaufene Wochen-Eintraege fallen weg
    if not (e.st == 2 and now - e.ts > TOMB_SEC) and not old then list[#list + 1] = e end
  end
  table.sort(list, function(a, b) if a.ts ~= b.ts then return a.ts < b.ts end return a.id < b.id end)
  local function join()
    local out = {}
    for i = 1, #list do
      local e = list[i]
      out[i] = string.format("%s\t%d\t%d\t%d\t%s\t%s", e.id, e.ts, e.st, e.wk * 10 + e.day, e.person, e.text)
    end
    return table.concat(out, "\n")
  end
  local s = join()
  local i = 1
  while #s > MAX_BYTES and i <= #list do
    if list[i].st == 2 then table.remove(list, i); s = join() else i = i + 1 end
  end
  return s
end

local function merge(a, b)
  for id, e in pairs(b) do
    local x = a[id]
    if x == nil or e.ts > x.ts then a[id] = e end
  end
end

local function load_local() return parse(file.read("items")) end
local function now_ts() return time.now() or 0 end

-- aktive Eintraege je Tag (1..7), sortiert nach Person, dann Eingabezeit
local function by_day(m, all)
  local days = { {}, {}, {}, {}, {}, {}, {} }
  local cw = cur_wk()
  for _, e in pairs(m) do
    if e.st == 0 and e.day >= 1 and e.day <= 7 and (all or e.wk == 0 or e.wk == cw) then
      local t = days[e.day]
      t[#t + 1] = e
    end
  end
  for d = 1, 7 do
    table.sort(days[d], function(a, b)
      if a.person ~= b.person then return a.person < b.person end
      if a.ts ~= b.ts then return a.ts < b.ts end
      return a.id < b.id
    end)
  end
  return days
end

-- Personen alphabetisch -> Farbpunkt
local function person_colors(m)
  local set, names = {}, {}
  for _, e in pairs(m) do
    if e.st == 0 and e.person ~= "" and not set[e.person] then set[e.person] = true; names[#names + 1] = e.person end
  end
  table.sort(names)
  local map = {}
  for i = 1, #names do map[names[i]] = DOT[(i - 1) % #DOT + 1] end
  return map, names
end

local function today_index()
  local lt = time.localtime()
  if not lt then return nil end
  return (lt.wday + 6) % 7 + 1
end

local function new_id(ctx)
  local s = system.get()
  local room = (s and s.room or "x"):sub(1, 2)
  local c = (tonumber(ctx.data.get("seq")) or 0) + 1
  ctx.data.set("seq", c % 4096)
  return string.format("%s%x%x", room, now_ts(), c)
end

local function clean(t, maxlen)
  t = tostring(t or ""):gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if #t > maxlen then
    local i = maxlen
    while i > 1 and (t:byte(i + 1) or 0) & 0xC0 == 0x80 do i = i - 1 end
    t = t:sub(1, i)
  end
  return t
end

-- ===== Abruf: Abgleich mit dem externen Speicher =====

function on_fetch(ctx)
  local now = now_ts()
  local m = load_local()
  local sync = "local"
  if storage.ready() then
    local remote, err = storage.read("dir", NAS_FILE)
    if remote == nil and err == "nicht gefunden" then remote = "" end
    if remote ~= nil then
      merge(m, parse(remote))
      local s = serialize(m, now)
      if s ~= remote then
        sync = storage.write("dir", NAS_FILE, s) and "ok" or "error"
      else
        sync = "ok"
      end
    else
      sync = "error"
    end
  end
  file.write("items", serialize(m, now))
  ctx.data.set("sync", sync)
  if sync == "ok" then ctx.data.set("syncAt", now) end
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

local function list_json(ctx, m)
  local days = by_day(m, true)
  local parts = {}
  for d = 1, 7 do
    for _, e in ipairs(days[d]) do
      parts[#parts + 1] = string.format('{"id":"%s","day":%d,"wk":%d,"person":"%s","text":"%s"}', esc(e.id), e.day, e.wk, esc(e.person), esc(e.text))
    end
  end
  local _, names = person_colors(m)
  local pn = {}
  for i = 1, #names do pn[i] = '"' .. esc(names[i]) .. '"' end
  local sync = ctx.data.get("sync") or "local"
  return string.format('{"items":[%s],"persons":[%s],"today":%d,"week":%d,"sync":"%s"}', table.concat(parts, ","), table.concat(pn, ","), today_index() or 0, cur_wk() or 0, esc(sync))
end

function on_http(ctx, req)
  local q = json.decode(req.body or "")
  if type(q) ~= "table" then return reply(400, '{"error":"JSON"}') end
  local op = tostring(q.op or "list")
  local m = load_local()
  local now = now_ts()
  local changed = false
  if op == "add" then
    local t = clean(q.text, 50)
    local d = math.floor(tonumber(q.day) or 0)
    if t == "" or d < 1 or d > 7 then return reply(400, '{"error":"leer"}') end
    local id = new_id(ctx)
    local wk = math.floor(tonumber(q.wk) or 0)
    if wk ~= 0 and (wk < 200001 or wk > 209953 or wk % 100 < 1 or wk % 100 > 53) then wk = 0 end
    m[id] = { id = id, ts = now, st = 0, day = d, wk = wk, person = clean(q.person, 12), text = t }
    changed = true
  elseif op == "del" then
    local e = m[tostring(q.id or "")]
    if e then e.st = 2; e.ts = now; changed = true end
  end
  if changed then
    file.write("items", serialize(m, now))
    ctx.data.set("rev", (tonumber(ctx.data.get("rev")) or 0) + 1)
    local r = reply(200, list_json(ctx, m))
    r.fetch = true
    r.redraw = true
    return r
  end
  return reply(200, list_json(ctx, m))
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

local function sync_text(ctx)
  local s = ctx.data.get("sync")
  if s == "ok" then return T(ctx, "synchronisiert", "synced") end
  if s == "error" then return T(ctx, "Sync-Fehler", "sync error") end
  return T(ctx, "nicht synchronisiert", "not synced")
end

-- Eintraege eines Tages in einer Zeile: Farbpunkt + "Person: Text", getrennt durch Abstand; schneidet am Zeilenende ab
local function inline_entries(entries, colors, x, baseline, maxx, font)
  local cx = x
  local shown = 0
  for i = 1, #entries do
    local e = entries[i]
    local label = (e.person ~= "") and (e.person .. ": " .. e.text) or e.text
    local dot = (e.person ~= "") and (colors[e.person] or color.BLACK) or nil
    local w = draw.measure(label, font) + (dot and 18 or 0)
    if cx + w > maxx then
      local rest = #entries - shown
      if rest > 0 then
        local more = "+" .. rest
        local mw = draw.measure(more, font)
        if cx + mw > maxx then cx = maxx - mw end
        draw.text(cx, baseline, more, font, color.BLACK, "left")
      end
      return
    end
    if dot then
      draw.circle(cx + 6, baseline - 7, 6, dot, true)
      draw.circle(cx + 6, baseline - 7, 6, color.BLACK, false)
      cx = cx + 18
    end
    draw.text(cx, baseline, label, font, color.BLACK, "left")
    cx = cx + w - (dot and 18 or 0) + 22
    shown = shown + 1
  end
end

local function page_week(ctx)
  local style = ctx.cfg.style or "cards"
  draw.clear(color.WHITE)
  local m = load_local()
  local days = by_day(m)
  local colors = person_colors(m)
  local today = today_index()
  local y0 = draw.top
  local total = 0
  for d = 1, 7 do total = total + #days[d] end
  if total == 0 then
    if device.qrscreen and device.qrscreen(T(ctx, "Wochenplan ist leer", "Weekly plan is empty"), T(ctx, "QR-Code scannen und Einträge hinzufügen:", "Scan the QR code to add entries:")) then return end
    draw.text(draw.width // 2, y0 + 150, T(ctx, "Wochenplan ist leer", "Weekly plan is empty"), "large", color.BLACK, "center")
    return
  end
  if style == "compact" then
    -- Nano: nur heute und morgen gross
    local base = today or 1
    local ty = y0 + 8
    for k = 0, 1 do
      local d = (base - 1 + k) % 7 + 1
      draw.text(28, ty + 40, (k == 0 and T(ctx, "Heute", "Today") or T(ctx, "Morgen", "Tomorrow")) .. " · " .. day_name(ctx, d), "large", color.BLACK, "left")
      local e = days[d]
      local yy = ty + 50
      if #e == 0 then
        draw.text(40, yy + 34, T(ctx, "nichts geplant", "nothing planned"), "normal", color.BLACK, "left")
        yy = yy + 44
      end
      for i = 1, math.min(4, #e) do
        local dot = e[i].person ~= "" and colors[e[i].person] or nil
        local x = 40
        if dot then draw.circle(x + 8, yy + 24, 8, dot, true); draw.circle(x + 8, yy + 24, 8, color.BLACK, false); x = x + 26 end
        local label = e[i].person ~= "" and (e[i].person .. ": " .. e[i].text) or e[i].text
        draw.text(x, yy + 32, cut(label, draw.width - x - 40, "large"), "large", color.BLACK, "left")
        yy = yy + 44
      end
      if #e > 4 then draw.text(draw.width - 40, yy + 20, string.format(T(ctx, "+ %d weitere", "+ %d more"), #e - 4), "small", color.BLACK, "right") end
      ty = math.max(yy + 12, ty + 200)
      if k == 0 then draw.line(28, ty - 6, draw.width - 28, ty - 6, color.BLACK) end
    end
    return
  end
  local rowH = (draw.height - y0 - 34) // 7
  for d = 1, 7 do
    local y = y0 + (d - 1) * rowH
    local isToday = (d == today)
    if style == "cards" then
      if isToday then draw.rect(20, y + 2, draw.width - 40, rowH - 6, color.YELLOW, true, 10) end
      draw.rect(20, y + 2, draw.width - 40, rowH - 6, color.BLACK, false, 10)
    else
      if isToday then draw.rect(20, y + 2, draw.width - 40, rowH - 4, color.YELLOW, true, 4) end
      draw.line(24, y + rowH - 2, draw.width - 24, y + rowH - 2, color.BLACK)
    end
    draw.text(36, y + rowH // 2 + 7, day_short(ctx, d), "large", color.BLACK, "left")
    if #days[d] == 0 then
      draw.text(110, y + rowH // 2 + 6, "-", "normal", color.BLACK, "left")
    else
      inline_entries(days[d], colors, 110, y + rowH // 2 + 7, draw.width - 36, "normal")
    end
  end
  local foot = sync_text(ctx)
  local cwk = cur_wk()
  if cwk then foot = T(ctx, "KW ", "Wk ") .. (cwk % 100) .. "   ·   " .. foot end
  local u = device.url and device.url() or nil
  if u then foot = foot .. "   ·   " .. T(ctx, "Handy: ", "Phone: ") .. u end
  draw.text(28, draw.height - 10, cut(foot, draw.width - 56, "small"), "small", color.BLACK, "left")
end

local function page_today(ctx)
  local style = ctx.cfg.style or "cards"
  draw.clear(color.WHITE)
  local m = load_local()
  local days = by_day(m)
  local colors = person_colors(m)
  local today = today_index()
  local y0 = draw.top
  if not today then
    draw.text(draw.width // 2, y0 + 150, T(ctx, "Uhr nicht gestellt", "Clock not set"), "large", color.BLACK, "center")
    return
  end
  local e = days[today]
  draw.text(28, y0 + 40, T(ctx, "Heute", "Today") .. " · " .. day_name(ctx, today), "large", color.BLACK, "left")
  draw.line(28, y0 + 54, draw.width - 28, y0 + 54, color.BLACK)
  if #e == 0 then
    draw.text(draw.width // 2, y0 + 170, T(ctx, "Heute ist nichts geplant", "Nothing planned today"), "large", color.GREEN, "center")
    return
  end
  local rowH = 58
  local rows = (draw.height - y0 - 70) // rowH
  for i = 1, math.min(rows, #e) do
    local y = y0 + 64 + (i - 1) * rowH
    if style ~= "flat" then draw.rect(24, y, draw.width - 48, rowH - 8, color.BLACK, false, 10) else draw.line(28, y + rowH - 4, draw.width - 28, y + rowH - 4, color.BLACK) end
    local x = 44
    if e[i].person ~= "" then
      local col = colors[e[i].person] or color.BLACK
      draw.circle(x + 10, y + rowH // 2 - 4, 10, col, true)
      draw.circle(x + 10, y + rowH // 2 - 4, 10, color.BLACK, false)
      draw.text(x + 30, y + rowH // 2 + 6, e[i].person, "normal", color.BLACK, "left")
      x = x + 40 + math.max(60, draw.measure(e[i].person, "normal"))
    end
    draw.text(x, y + rowH // 2 + 8, cut(e[i].text, draw.width - x - 44, "large"), "large", color.BLACK, "left")
  end
  if #e > rows then draw.text(draw.width - 28, draw.height - 10, string.format(T(ctx, "+ %d weitere", "+ %d more"), #e - rows), "small", color.BLACK, "right") end
end

function on_draw(ctx, page)
  if page == 2 then return page_today(ctx) end
  return page_week(ctx)
end

function on_widget(ctx, box)
  local style = ctx.cfg.style or "cards"
  local m = load_local()
  local days = by_day(m)
  local colors = person_colors(m)
  local today = today_index()
  local cx = box.x + box.w // 2
  if not today then
    draw.text(cx, box.y + box.h // 2 + 6, T(ctx, "Uhr nicht gestellt", "Clock not set"), "normal", color.BLACK, "center")
    return
  end
  local e = days[today]
  if box.h < 70 or style == "compact" then
    draw.text(cx, box.y + box.h // 2 + 10, tostring(#e), "huge", #e > 0 and color.BLACK or color.GREEN, "center")
    draw.text(cx, box.y + box.h - 6, T(ctx, "heute", "today"), "small", color.BLACK, "center")
    return
  end
  draw.text(box.x + 10, box.y + 22, day_name(ctx, today), "normal", color.BLACK, "left")
  if #e == 0 then
    draw.text(cx, box.y + box.h // 2 + 14, T(ctx, "nichts geplant", "nothing planned"), "normal", color.GREEN, "center")
    return
  end
  local lh = 26
  local rows = (box.h - 34) // lh
  for i = 1, math.min(rows, #e) do
    local y = box.y + 30 + (i - 1) * lh
    local x = box.x + 12
    if e[i].person ~= "" then
      draw.circle(x + 6, y + 12, 6, colors[e[i].person] or color.BLACK, true)
      draw.circle(x + 6, y + 12, 6, color.BLACK, false)
      x = x + 20
    end
    draw.text(x, y + 18, cut(e[i].text, box.x + box.w - x - 8, "normal"), "normal", color.BLACK, "left")
  end
  if #e > rows then draw.text(box.x + box.w - 8, box.y + box.h - 4, "+" .. (#e - rows), "small", color.BLACK, "right") end
end
