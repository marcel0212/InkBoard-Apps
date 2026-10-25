-- Eigene Daten (Paket datenquelle): "No-Code-Plugin" - eine eigene Datenquelle ohne eine Zeile Lua auf dem Display zeigen.
-- Entspricht den Private Plugins von TRMNL: eine Datenquelle (Adresse, die das Geraet regelmaessig abfragt, ODER ein Webhook, an den
-- ein anderes Programm Daten schickt) plus eine Vorlage. Das Rendern passiert auf dem Geraet selbst, es gibt keinen Server dazwischen.
-- Skript-API Level 20 (on_http), Abruf mit http.request (permissions.netFrom auf das Adressfeld).
--
-- Felder: bis zu 4 Werte (Beschriftung, Pfad im JSON, Einheit). Pfade: "temp", "main.temp", "data.0.name" (Zaehlung ab 0), "$.a.b" geht auch.
-- Vorlagen: tiles (bis 4 Kacheln), big (ein grosser Wert + Nebenwerte), list (Liste aus einem JSON-Array), text (Satz mit {1}..{4}), signal (Ampel).
-- Ampelfarben aus Schwellen: "Warnung ab" / "Alarm ab" (oder darunter) fuer den ersten Wert.
-- Webhook-Modus: POST /app/datenquelle/api mit Header X-Requested-With: InkBoardStudio und beliebigem JSON-Objekt als Body.

local MAXROWS = 8

local function T(ctx, de, en) return (ctx.lang == "en") and en or de end

-- ===== Pfade =====

local function walk(doc, path)
  path = tostring(path or ""):gsub("^%$%.?", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if path == "" then return doc end
  local cur = doc
  for key in path:gmatch("[^%.]+") do
    if type(cur) ~= "table" then return nil end
    local n = tonumber(key)
    if n ~= nil and cur[n + 1] ~= nil then cur = cur[n + 1]
    elseif cur[key] ~= nil then cur = cur[key]
    elseif n ~= nil then return nil
    else return nil end
  end
  return cur
end

local function scalar(v)
  if type(v) == "number" then return v end
  if type(v) == "string" then return v end
  if type(v) == "boolean" then return v and "ja" or "nein" end
  return nil
end

local function clean(s, max)
  s = tostring(s or ""):gsub("[%c|]", " ")
  if #s > max then
    local i = max
    while i > 1 and (s:byte(i + 1) or 0) & 0xC0 == 0x80 do i = i - 1 end
    s = s:sub(1, i)
  end
  return s
end

-- ===== Einlesen (Abruf und Webhook) =====

local function ingest(ctx, doc)
  local ok = false
  for i = 1, 4 do
    local p = tostring(ctx.cfg["p" .. i] or "")
    if p ~= "" then
      local v = scalar(walk(doc, p))
      if v ~= nil then ctx.data.set("v" .. i, tostring(v)); ok = true else ctx.data.set("v" .. i, "") end
    end
  end
  local lp = tostring(ctx.cfg.listPath or "")
  if lp ~= "" or ctx.cfg.template == "list" then
    local arr = walk(doc, lp)
    local rows = {}
    if type(arr) == "table" then
      local fieldN, fieldV = tostring(ctx.cfg.listField or ""), tostring(ctx.cfg.listValue or "")
      local max = math.min(tonumber(ctx.cfg.maxRows) or 6, MAXROWS)
      for i = 1, #arr do
        if #rows >= max then break end
        local it = arr[i]
        local n, v
        if type(it) == "table" then
          n = scalar(walk(it, fieldN)); v = fieldV ~= "" and scalar(walk(it, fieldV)) or nil
        else n = scalar(it) end
        if n ~= nil then rows[#rows + 1] = clean(n, 40) .. "|" .. clean(v or "", 24) end
      end
      if #rows > 0 then ok = true end
    end
    ctx.data.set("rows", table.concat(rows, "\n"))
  end
  if ok then
    ctx.data.set("ts", time.now() or 1)
    ctx.data.set("err", "")
  else
    ctx.data.set("err", T(ctx, "Pfade nicht gefunden", "Paths not found"))
  end
  return ok
end

function on_fetch(ctx)
  if (ctx.cfg.mode or "poll") ~= "poll" then return true end
  local url = tostring(ctx.cfg.url or "")
  if url == "" then ctx.data.set("err", T(ctx, "Keine Adresse eingetragen", "No address entered")); return false end
  local req = { url = url, method = "GET", headers = { Accept = "application/json" }, maxBytes = 24576 }
  local tok = tostring(ctx.cfg.token or "")
  if tok ~= "" then req.bearer = tok end
  local r, e = http.request(req)
  if r == nil then ctx.data.set("err", clean(e or "Netz", 60)); return false end
  if r.status < 200 or r.status >= 300 then ctx.data.set("err", "HTTP " .. tostring(r.status)); return false end
  local doc = json.decode(r.body or "")
  if type(doc) ~= "table" then ctx.data.set("err", T(ctx, "Antwort ist kein JSON", "Response is not JSON")); return false end
  return ingest(ctx, doc)
end

function on_http(ctx, req)
  local doc = json.decode(req.body or "")
  if type(doc) ~= "table" then return { status = 400, body = '{"error":"JSON"}' } end
  if doc.op == "get" then return { status = 200, body = string.format('{"ts":%d}', tonumber(ctx.data.get("ts")) or 0) } end
  if type(doc.data) == "table" and doc.op == "push" then doc = doc.data end
  local ok = ingest(ctx, doc)
  return { status = ok and 200 or 422, body = ok and '{"ok":true}' or '{"error":"paths"}', redraw = ok }
end

-- ===== Werte aufbereiten =====

local function num(v) return tonumber(v) end

local function fmtVal(ctx, i)
  local raw = tostring(ctx.data.get("v" .. i) or "")
  if raw == "" then return "–" end
  local n = tonumber(raw)
  local u = tostring(ctx.cfg["u" .. i] or "")
  if n ~= nil then
    local dec = tonumber(ctx.cfg.decimals)
    if dec == nil then dec = (n == math.floor(n)) and 0 or 1 end
    raw = string.format("%." .. math.max(0, math.min(3, math.floor(dec))) .. "f", n)
  end
  if u ~= "" then
    if u == "%" or u == "°" or u == "°C" or u == "°F" then return raw .. u end
    return raw .. " " .. u
  end
  return raw
end

local function label(ctx, i)
  local l = tostring(ctx.cfg["l" .. i] or "")
  return l
end

-- Ampelfarbe fuer Wert 1: nil = keine Schwellen eingestellt
local function signal(ctx)
  local warn, alarm = tonumber(ctx.cfg.warn) or 0, tonumber(ctx.cfg.alarm) or 0
  if warn == 0 and alarm == 0 then return nil end
  local v = tonumber(ctx.data.get("v1"))
  if v == nil then return nil end
  local below = ctx.cfg.dir == "below"
  local function hit(limit) if limit == 0 then return false end if below then return v <= limit end return v >= limit end
  if hit(alarm) then return color.RED end
  if hit(warn) then return color.YELLOW end
  return color.GREEN
end

local function ageText(ctx)
  local ts = tonumber(ctx.data.get("ts")) or 0
  local t = time.now() or 0
  if ts <= 0 or t <= 0 then return "" end
  local m = (t - ts) // 60
  if m < 1 then return T(ctx, "gerade eben", "just now") end
  if m < 60 then return T(ctx, "vor ", "") .. m .. T(ctx, " Min", " min ago") end
  local h = m // 60
  if h < 48 then return T(ctx, "vor ", "") .. h .. T(ctx, " Std", " h ago") end
  return T(ctx, "vor ", "") .. (h // 24) .. T(ctx, " Tagen", " d ago")
end

local function fit(text, maxW, fonts)
  for i = 1, #fonts do if draw.measure(text, fonts[i]) <= maxW then return fonts[i] end end
  return fonts[#fonts]
end

-- "huge" kann nur Ziffern und Punkt: die Zahl gross, den Rest (Einheit, Woerter) in lesbarer Schrift daneben.
local function bigValue(x, y, txt, maxW, col, align, maxScale)
  maxScale = maxScale or 1
  local num, rest = txt:match("^(%-?[%d%.]+)(.*)$")
  if num ~= nil then
    for sc = maxScale, 1, -1 do
      local wn = draw.measure(num, "huge", sc)
      local wr = (rest ~= "") and draw.measure(rest, "large") or 0
      if wn + wr <= maxW then
        local x0 = (align == "center") and (x - (wn + wr) // 2) or x
        draw.text(x0, y, num, "huge", col, "left", sc)
        if rest ~= "" then draw.text(x0 + wn + 2, y, rest, "large", col, "left") end
        return
      end
    end
  end
  for sc = math.min(maxScale, 2), 2, -1 do
    if draw.measure(txt, "large", sc) <= maxW then draw.text(x, y, txt, "large", col, align, sc); return end
  end
  for _, f in ipairs({ "large", "medium", "normal" }) do
    if draw.measure(txt, f) <= maxW then draw.text(x, y, txt, f, col, align); return end
  end
  draw.text(x, y, txt, "normal", col, align)
end

local function cut(text, maxW, font)
  text = tostring(text or "")
  if draw.measure(text, font) <= maxW then return text end
  while #text > 1 do
    local i = #text
    while i > 1 and (text:byte(i) & 0xC0) == 0x80 do i = i - 1 end
    text = text:sub(1, i - 1)
    if draw.measure(text .. "..", font) <= maxW then return text .. ".." end
  end
  return text
end

-- Platzhalter {1}..{4} und {l1}..{l4} im Satz
local function fill(ctx, tpl)
  tpl = tostring(tpl or "")
  tpl = tpl:gsub("{l(%d)}", function(d) return label(ctx, tonumber(d)) end)
  tpl = tpl:gsub("{(%d)}", function(d) return fmtVal(ctx, tonumber(d)) end)
  return tpl
end

local function configured(ctx)
  for i = 1, 4 do if tostring(ctx.cfg["p" .. i] or "") ~= "" then return true end end
  return tostring(ctx.cfg.listPath or "") ~= "" or ctx.cfg.template == "list"
end

local function hasData(ctx) return (tonumber(ctx.data.get("ts")) or 0) > 0 end

-- ===== Rahmen je Stil =====

local function frame(ctx)
  local style = ctx.cfg.style or "cards"
  local title = tostring(ctx.cfg.title or "")
  draw.clear(color.WHITE)
  local x, y, w, h = 28, draw.top + 10, draw.width - 56, draw.height - draw.top - 30
  if style == "flat" then
    draw.rect(0, draw.top, draw.width, 54, color.ACCENT, true)
    draw.text(28, draw.top + 36, cut(title ~= "" and title or T(ctx, "Eigene Daten", "Custom data"), draw.width - 240, "large"), "large", color.ACCENT_INK, "left")
    draw.text(draw.width - 28, draw.top + 34, ageText(ctx), "small", color.ACCENT_INK, "right")
    return 28, draw.top + 70, draw.width - 56, draw.height - draw.top - 90
  elseif style == "compact" then
    if title ~= "" then draw.text(28, draw.top + 26, cut(title, draw.width - 240, "normal"), "normal", color.BLACK, "left") end
    draw.text(draw.width - 28, draw.top + 24, ageText(ctx), "small", color.BLACK, "right")
    return 28, draw.top + 40, draw.width - 56, draw.height - draw.top - 60
  end
  draw.rect(x, y, w, h, color.WHITE, true, 20)
  draw.rect(x, y, w, h, color.BLACK, false, 20)
  draw.rect(x + 10, y + 10, 10, h - 20, color.ACCENT, true, 5)
  if title ~= "" then draw.text(x + 34, y + 36, cut(title, w - 250, "normal"), "normal", color.BLACK, "left") end
  draw.text(x + w - 22, y + 34, ageText(ctx), "small", color.BLACK, "right")
  return x + 34, y + 54, w - 56, h - 70
end

-- ===== Vorlagen =====

local function drawTiles(ctx, x, y, w, h)
  local n = 0
  for i = 1, 4 do if tostring(ctx.cfg["p" .. i] or "") ~= "" then n = n + 1 end end
  if n == 0 then return end
  local cols = (n == 1) and 1 or ((n == 2) and 2 or 2)
  local rows = math.ceil(n / cols)
  local gap = 14
  local tw = (w - gap * (cols - 1)) // cols
  local th = (h - gap * (rows - 1)) // rows
  local k = 0
  local sig = signal(ctx)
  for i = 1, 4 do
    if tostring(ctx.cfg["p" .. i] or "") ~= "" then
      local cx, cy = x + (k % cols) * (tw + gap), y + (k // cols) * (th + gap)
      draw.rect(cx, cy, tw, th, color.WHITE, true, 14)
      draw.rect(cx, cy, tw, th, color.BLACK, false, 14)
      if label(ctx, i) ~= "" then draw.text(cx + 14, cy + 28, cut(label(ctx, i), tw - 28, "normal"), "normal", color.BLACK, "left") end
      local txt = fmtVal(ctx, i)
      bigValue(cx + tw // 2, cy + th - 26, txt, tw - 28, (i == 1 and sig == color.RED) and color.RED or color.BLACK, "center", 1)
      if i == 1 and sig then draw.circle(cx + tw - 22, cy + 22, 9, sig, true); draw.circle(cx + tw - 22, cy + 22, 9, color.BLACK, false) end
      k = k + 1
    end
  end
end

local function drawBig(ctx, x, y, w, h)
  local sig = signal(ctx)
  local txt = fmtVal(ctx, 1)
  local others = {}
  for i = 2, 4 do if tostring(ctx.cfg["p" .. i] or "") ~= "" then others[#others + 1] = i end end
  local bigH = (#others > 0) and (h - 90) or h
  bigValue(x + w // 2, y + bigH // 2 + 36, txt, w - 20, sig == color.RED and color.RED or color.BLACK, "center", 3)
  if label(ctx, 1) ~= "" then draw.text(x + w // 2, y + 24, label(ctx, 1), "normal", color.BLACK, "center") end
  if sig then draw.rect(x, y + bigH - 8, w, 8, sig, true, 4) end
  if #others > 0 then
    local cw = w // #others
    for k, i in ipairs(others) do
      local cx = x + (k - 1) * cw + cw // 2
      draw.text(cx, y + h - 46, fmtVal(ctx, i), "large", color.BLACK, "center")
      if label(ctx, i) ~= "" then draw.text(cx, y + h - 14, cut(label(ctx, i), cw - 10, "small"), "small", color.BLACK, "center") end
    end
  end
end

local function drawList(ctx, x, y, w, h)
  local rows = {}
  for l in tostring(ctx.data.get("rows") or ""):gmatch("[^\n]+") do
    local n, v = l:match("^(.-)|(.*)$")
    if n then rows[#rows + 1] = { n = n, v = v } end
  end
  if #rows == 0 then draw.text(x + w // 2, y + h // 2, T(ctx, "Keine Einträge", "No entries"), "normal", color.BLACK, "center"); return end
  local rh = math.min(52, h // #rows)
  for i, r in ipairs(rows) do
    local ry = y + (i - 1) * rh
    if i > 1 then draw.line(x, ry, x + w, ry, color.BLACK) end
    local vw = (r.v ~= "") and (draw.measure(r.v, "normal") + 16) or 0
    draw.text(x + 4, ry + rh // 2 + 7, cut(r.n, w - vw - 16, "normal"), "normal", color.BLACK, "left")
    if r.v ~= "" then draw.text(x + w - 4, ry + rh // 2 + 7, r.v, "normal", color.BLACK, "right") end
  end
end

local function drawText(ctx, x, y, w, h)
  local tpl = tostring(ctx.cfg.textTpl or "")
  if tpl == "" then tpl = "{1}" end
  local s = fill(ctx, tpl)
  draw.wrap(x, y + 34, w, s, "large", color.BLACK)
end

local function drawSignal(ctx, x, y, w, h)
  local sig = signal(ctx) or color.GREEN
  local r = math.min(h // 2 - 8, 90)
  draw.circle(x + r + 10, y + h // 2, r, sig, true)
  draw.circle(x + r + 10, y + h // 2, r, color.BLACK, false)
  local tx = x + 2 * r + 40
  local txt = fmtVal(ctx, 1)
  bigValue(tx, y + h // 2 + 18, txt, x + w - tx, color.BLACK, "left", 2)
  if label(ctx, 1) ~= "" then draw.text(tx, y + h // 2 - 50, label(ctx, 1), "normal", color.BLACK, "left") end
end

local TEMPLATES = { tiles = drawTiles, big = drawBig, list = drawList, text = drawText, signal = drawSignal }

local function empty(ctx)
  draw.clear(color.WHITE)
  local cx = draw.width // 2
  draw.text(cx, 150, T(ctx, "Noch keine Daten", "No data yet"), "large", color.BLACK, "center")
  local err = tostring(ctx.data.get("err") or "")
  local lines
  if not configured(ctx) then
    lines = T(ctx, "In den Einstellungen die Datenquelle und mindestens einen Pfad (z. B. main.temp) eintragen.", "In the settings enter the data source and at least one path (e.g. main.temp).")
  elseif (ctx.cfg.mode or "poll") == "push" then
    local u = device.url("/api")
    lines = T(ctx, "Warte auf Daten per POST an:\n", "Waiting for data by POST to:\n") .. (u or "/app/datenquelle/api") .. "\nHeader X-Requested-With: InkBoardStudio"
  else
    lines = err ~= "" and (T(ctx, "Abruf fehlgeschlagen: ", "Fetch failed: ") .. err) or T(ctx, "Der erste Abruf läuft gleich.", "The first fetch is about to run.")
  end
  draw.wrap(80, 205, draw.width - 160, lines, "normal", color.BLACK)
end

function on_draw(ctx, page)
  if not hasData(ctx) then empty(ctx); return end
  local x, y, w, h = frame(ctx)
  local f = TEMPLATES[ctx.cfg.template or "tiles"] or drawTiles
  f(ctx, x, y, w, h)
  local err = tostring(ctx.data.get("err") or "")
  if err ~= "" then draw.text(draw.width - 30, draw.height - 8, cut(err, 300, "small"), "small", color.RED, "right") end
end

function on_widget(ctx, box)
  if not hasData(ctx) then
    draw.text(box.x + box.w // 2, box.y + box.h // 2 + 6, T(ctx, "Noch keine Daten", "No data yet"), "normal", color.BLACK, "center")
    return
  end
  local t = ctx.cfg.template or "tiles"
  local sig = signal(ctx)
  if t == "list" then
    local rh, i = 26, 0
    for l in tostring(ctx.data.get("rows") or ""):gmatch("[^\n]+") do
      local n, v = l:match("^(.-)|(.*)$")
      if n and (i + 1) * rh <= box.h then
        draw.text(box.x + 10, box.y + i * rh + 19, cut(n, box.w - 100, "normal"), "normal", color.BLACK, "left")
        if v ~= "" then draw.text(box.x + box.w - 10, box.y + i * rh + 19, v, "normal", color.BLACK, "right") end
        i = i + 1
      end
    end
    return
  end
  if t == "text" then
    draw.wrap(box.x + 10, box.y + 26, box.w - 20, fill(ctx, (tostring(ctx.cfg.textTpl or "") ~= "") and ctx.cfg.textTpl or "{1}"), "normal", color.BLACK)
    return
  end
  local txt = fmtVal(ctx, 1)
  local lx = box.x + 12
  if sig then draw.circle(box.x + 22, box.y + box.h // 2, 10, sig, true); draw.circle(box.x + 22, box.y + box.h // 2, 10, color.BLACK, false); lx = box.x + 42 end
  if label(ctx, 1) ~= "" then draw.text(lx, box.y + 24, cut(label(ctx, 1), box.x + box.w - lx - 8, "small"), "small", color.BLACK, "left") end
  draw.text(lx, box.y + box.h // 2 + 22, txt, fit(txt, box.x + box.w - lx - 8, { "large", "medium", "normal" }), (sig == color.RED) and color.RED or color.BLACK, "left")
end
