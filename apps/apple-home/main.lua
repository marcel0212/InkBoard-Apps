-- Apple Home (Paket apple-home): Werte aus Apple Home (HomeKit) als Kacheln auf dem Display - Temperatur, Luftfeuchte, Tuer-/Fensterkontakte,
-- Lichter, Schloesser, Bewegung, Leistung. Skript-API Level 23 (on_http, storage; Abgleich mit dem externen Speicher, siehe unten).
--
-- HomeKit laesst sich nur von Apple-Geraeten aus lesen: die iOS-/iPadOS-App (Werkzeug "Apple Home") liest die Zubehoerwerte und schickt sie
-- an dieses Paket; das Gerät zeichnet nur. Die Werte bleiben auf dem Display stehen, bis die naechsten kommen, und ein Alter ("vor 12 Min")
-- zeigt, wie aktuell sie sind. Jedes andere Programm kann dieselbe Schnittstelle nutzen (Node-RED, Kurzbefehle).
--
-- Anfrage (JSON): {"op":"set","items":[{"n":"Wohnzimmer","r":"EG","k":"temp","v":21.4,"u":"°C","a":0}, ...]}  op "get" liefert den Stand.
-- a = 1: Zubehoer gerade nicht erreichbar (wird gekennzeichnet). group: v = Zahl der eingeschalteten Mitglieder, u = Zahl aller Mitglieder.
-- f = 1: Favorit (steht auf den ersten Seiten "Favoriten"). scene (Aktion/Szene): v = Zeitpunkt der letzten Ausfuehrung (Unix-Sekunden, 0 = nie).
-- k (Art): temp, hum, co2, contact (1 = offen), light (1 = an), lock (1 = verriegelt), motion (1 = Bewegung), power (Watt), switch (1 = an), group, scene, number.

local MAXI = 40
local PER_PAGE = 8      -- Zeilenstile (flat/compact)
local TILE_COLS, TILE_ROWS = 5, 3
local PER_TILES = TILE_COLS * TILE_ROWS   -- Kachelstile (apple/cards): 15 je Seite

-- Eintraege je Seite: Kacheln sind klein genug fuer 5 x 3, die Zeilenstile zeigen weiter 8
local function perPage(ctx)
  local st = ctx.cfg.style or "apple"
  if st == "flat" or st == "compact" then return PER_PAGE end
  return PER_TILES
end

local function T(ctx, de, en) return (ctx.lang == "en") and en or de end

local function clean(t, max)
  t = tostring(t or ""):gsub("[%c|]", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if #t > max then
    local i = max
    while i > 1 and (t:byte(i + 1) or 0) & 0xC0 == 0x80 do i = i - 1 end
    t = t:sub(1, i)
  end
  return t
end

local KINDS = { temp = 1, hum = 1, co2 = 1, contact = 1, light = 1, lock = 1, motion = 1, power = 1, switch = 1, group = 1, scene = 1, number = 1 }

-- ===== Daten =====

local function load(ctx)
  local items = {}
  local raw = tostring(ctx.data.get("items") or "")
  for line in raw:gmatch("[^\n]+") do
    local f = {}
    for x in (line .. "|"):gmatch("([^|]*)|") do f[#f + 1] = x end
    if #f >= 4 then items[#items + 1] = { k = f[1], n = f[2], r = f[3], v = tonumber(f[4]) or 0, u = f[5] or "", a = (tonumber(f[6]) or 0) ~= 0, f = (tonumber(f[7]) or 0) ~= 0 } end
  end
  return items
end

local function age(ctx)
  local ts = tonumber(ctx.data.get("ts")) or 0
  local now = time.now() or 0
  if ts <= 0 or now <= 0 then return nil end
  local m = (now - ts) // 60
  if m < 0 then m = 0 end
  return m
end

local function ageText(ctx)
  local m = age(ctx)
  if m == nil then return "" end
  if m < 1 then return T(ctx, "gerade eben", "just now") end
  if m < 60 then return T(ctx, "vor ", "") .. m .. T(ctx, " Min", " min ago") end
  local h = m // 60
  if h < 48 then return T(ctx, "vor ", "") .. h .. T(ctx, " Std", " h ago") end
  return T(ctx, "vor ", "") .. (h // 24) .. T(ctx, " Tagen", " d ago")
end

local function relText(ctx, ts)
  if ts <= 0 then return T(ctx, "Nie", "Never") end
  local now = time.now() or 0
  if now <= 0 then return "" end
  local m = (now - ts) // 60
  if m < 1 then return T(ctx, "Gerade eben", "Just now") end
  if m < 60 then return T(ctx, "vor ", "") .. m .. T(ctx, " Min", " min ago") end
  local h = m // 60
  if h < 48 then return T(ctx, "vor ", "") .. h .. T(ctx, " Std", " h ago") end
  return T(ctx, "vor ", "") .. (h // 24) .. T(ctx, " Tagen", " d ago")
end

local function stale(ctx)
  local m = age(ctx)
  local lim = tonumber(ctx.cfg.staleMin) or 90
  return m ~= nil and m > lim
end

-- Anzeige-Wert und Ampelfarbe einer Kachel
local function fmt(ctx, it)
  local k, v = it.k, it.v
  if k == "temp" then return string.format("%.1f", v) .. (it.u ~= "" and it.u or "°"), nil end
  if k == "hum" then return string.format("%d%%", math.floor(v + 0.5)), nil end
  if k == "co2" then
    return string.format("%d", math.floor(v + 0.5)), (v >= 1400 and color.RED) or (v >= 1000 and color.YELLOW) or color.GREEN
  end
  if k == "contact" then return v ~= 0 and T(ctx, "Offen", "Open") or T(ctx, "Zu", "Closed"), v ~= 0 and color.RED or color.GREEN end
  if k == "light" or k == "switch" then return v ~= 0 and T(ctx, "An", "On") or T(ctx, "Aus", "Off"), v ~= 0 and color.YELLOW or nil end
  if k == "lock" then return v ~= 0 and T(ctx, "Verriegelt", "Locked") or T(ctx, "Offen", "Unlocked"), v ~= 0 and color.GREEN or color.RED end
  if k == "motion" then return v ~= 0 and T(ctx, "Bewegung", "Motion") or T(ctx, "Ruhig", "Clear"), v ~= 0 and color.YELLOW or nil end
  if k == "power" then return string.format("%d W", math.floor(v + 0.5)), nil end
  if k == "group" then
    local total = tonumber(it.u) or 0
    return string.format("%d/%d", math.floor(v + 0.5), total), v > 0 and color.YELLOW or nil
  end
  if k == "scene" then return relText(ctx, v), nil end
  local s = (v == math.floor(v)) and string.format("%d", v) or string.format("%.1f", v)
  return s .. (it.u ~= "" and (" " .. it.u) or ""), nil
end

-- "huge" kann nur Ziffern und Punkt: die Zahl gross, den Rest (Einheit, Woerter) in lesbarer Schrift daneben.
local function bigValue(x, y, txt, maxW, col, align, maxScale, small)
  maxScale = maxScale or 1
  local num, rest = txt:match("^(%-?[%d%.]+)(.*)$")
  if num ~= nil and not small then   -- small: kleine Kacheln ohne die sehr hohe Ziffernschrift
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

local function fit(text, maxW, fonts)
  for i = 1, #fonts do if draw.measure(text, fonts[i]) <= maxW then return fonts[i] end end
  return fonts[#fonts]
end

-- ===== Symbole (Apple-Home-Stil) =====

-- Zeichnet das Symbol der Art in die Box s x s ab (x, y); ink = Strichfarbe. Eigene Formen fuer Tuer, Licht, Schalter und Blitz.
local D = draw
local function glyph(it, x, y, s, ink)
  local absent = it.a
  local fl = math.floor
  local draw = { rect = function(a, b, c, d, e, f, r) return D.rect(fl(a), fl(b), fl(c), fl(d), e, f, r and fl(r) or nil) end,
                 circle = function(a, b, c, d, e) return D.circle(fl(a), fl(b), fl(c), d, e) end,
                 line = function(a, b, c, d, e) return D.line(fl(a), fl(b), fl(c), fl(d), e) end,
                 icon = function(n, a, b, c, d) return D.icon(n, fl(a), fl(b), fl(c), d) end,
                 polygon = function(t, c, f) local o = {} for i = 1, #t do o[i] = fl(t[i]) end return D.polygon(o, c, f) end }
  local k, on = it.k, (it.v ~= 0)
  local lw = s >= 36 and 3 or 2
  if k == "temp" then draw.icon("thermometer", x, y, s, ink)
  elseif k == "hum" then draw.icon("drop", x, y, s, ink)
  elseif k == "co2" then draw.icon("cloud", x, y, s, ink)
  elseif k == "lock" then draw.icon("lock", x, y, s, ink)
  elseif k == "motion" then draw.icon("user", x, y, s, ink)
  elseif k == "contact" then
    local dx, dy, dw, dh = x + s * 0.2, y + s * 0.06, s * 0.6, s * 0.88
    if on then -- offene Tuer: Blatt schraeg nach innen geklappt
      draw.rect(dx, dy, dw, dh, ink, false, 2)
      draw.polygon({ dx + 3, dy + 3, dx + dw * 0.55, dy + dh * 0.12, dx + dw * 0.55, dy + dh * 0.9, dx + 3, dy + dh - 3 }, ink, true)
    else
      draw.rect(dx, dy, dw, dh, ink, false, 2)
      draw.rect(dx + 2, dy + 2, dw - 4, dh - 4, ink, false, 1)
      draw.circle(dx + dw - 8, dy + dh * 0.55, math.max(2, s // 14), ink, true)
    end
  elseif k == "light" then
    local r = s * 0.3
    draw.circle(x + s / 2, y + s * 0.4, r, ink, on)
    if not on then draw.circle(x + s / 2, y + s * 0.4, r - 1, ink, false) end
    draw.rect(x + s * 0.36, y + s * 0.74, s * 0.28, s * 0.16, ink, true, 2)
    if on then
      draw.line(x + s * 0.5, y, x + s * 0.5, y + s * 0.04, ink)
      draw.line(x + s * 0.08, y + s * 0.4, x + s * 0.14, y + s * 0.4, ink)
      draw.line(x + s * 0.86, y + s * 0.4, x + s * 0.92, y + s * 0.4, ink)
    end
  elseif k == "switch" then
    -- Schieberegler: nur ganze Pixel, gerade Hoehe, Knopf exakt im Rund der Pille (sonst sitzt er schief und ragt ueber den Rand)
    -- feste Masse (44 x 24, Knopf 14, im Aus-Zustand 3 px Luft zur Kontur), nur in kleinen Symbolfeldern verkleinert: in jeder Kachel exakt gleich
    local w = math.min(44, fl(s * 0.95))
    local h = fl(w * 6 / 11 / 2) * 2
    local px, py = fl(x + (s - w) / 2), fl(y + (s - h) / 2)
    local r = h // 2
    -- Pille aus zwei Kreisen und einem Rechteck (statt Rundrechteck mit Radius: das zeichnet das Display je nach Groesse unterschiedlich)
    local function stadium(sx, sy, sw, sh, c)
      local sr = sh // 2
      draw.circle(sx + sr, sy + sr, sr, c, true)
      draw.circle(sx + sw - sr - 1, sy + sr, sr, c, true)
      draw.rect(sx + sr, sy, sw - 2 * sr, sh, c, true)
    end
    stadium(px, py, w, h, ink)
    if not on then stadium(px + 2, py + 2, w - 4, h - 4, color.WHITE) end
    local kr = r - (h >= 20 and 5 or 3)
    local kx = on and (px + w - r - 1) or (px + r)
    draw.circle(kx, py + r, kr, on and color.WHITE or ink, true)
  elseif k == "group" then -- Gruppe: drei Kreise
    local r = s * 0.2
    draw.circle(x + s * 0.3, y + s * 0.35, r, ink, on)
    draw.circle(x + s * 0.7, y + s * 0.35, r, ink, on)
    draw.circle(x + s * 0.5, y + s * 0.72, r, ink, on)
    if not on then
      draw.circle(x + s * 0.3, y + s * 0.35, r - 1, ink, false)
      draw.circle(x + s * 0.7, y + s * 0.35, r - 1, ink, false)
      draw.circle(x + s * 0.5, y + s * 0.72, r - 1, ink, false)
    end
  elseif k == "scene" then draw.icon("play", x, y, s, ink)
  elseif k == "power" then
    draw.polygon({ x + s * 0.58, y + s * 0.02, x + s * 0.2, y + s * 0.55, x + s * 0.47, y + s * 0.55, x + s * 0.4, y + s * 0.98,
                   x + s * 0.8, y + s * 0.42, x + s * 0.53, y + s * 0.42 }, ink, true)
  else draw.icon("chart", x, y, s, ink) end
  if absent then -- durchgestrichen: Zubehoer nicht erreichbar
    draw.line(x + s * 0.05, y + s * 0.92, x + s * 0.95, y + s * 0.08, ink)
    draw.line(x + s * 0.05, y + s * 0.92 - 1, x + s * 0.95, y + s * 0.08 - 1, ink)
  end
end

-- Kachel-Zustand: Fuellfarbe (aktive Kacheln wie in Apple Home hervorgehoben), Schriftfarbe darauf, gruener Punkt fuer "in Ordnung"
local function tileLook(ctx, it, long)
  if it.a then
    if long then return T(ctx, "Nicht erreichbar", "Unreachable"), nil, color.BLACK, nil end
    return T(ctx, "Offline", "Offline"), nil, color.BLACK, nil
  end
  local txt, col = fmt(ctx, it)
  local fill, ink = nil, color.BLACK
  if col == color.RED then fill, ink = color.RED, color.WHITE
  elseif col == color.YELLOW then fill = color.YELLOW end
  return txt, fill, ink, (col == color.GREEN) and color.GREEN or nil
end

-- ===== Seiten =====

local function header(ctx, items)
  local a = ageText(ctx)
  if a ~= "" then
    draw.text(draw.width - 28, draw.top + 22, (stale(ctx) and "! " or "") .. T(ctx, "Stand ", "Updated ") .. a, "small", stale(ctx) and color.RED or color.BLACK, "right")
  end
end

local function empty(ctx)
  draw.clear(color.WHITE)
  local cx = draw.width // 2
  draw.circle(cx, 170, 34, color.ACCENT, true)
  draw.circle(cx, 170, 34, color.BLACK, false)
  draw.text(cx, 176, "?", "large", color.ACCENT_INK, "center")
  draw.text(cx, 270, T(ctx, "Noch keine Werte", "No values yet"), "large", color.BLACK, "center")
  draw.text(cx, 312, T(ctx, "Nur mit der iPhone-/iPad-App nutzbar", "Only usable with the iPhone/iPad app"), "normal", color.BLACK, "center")
  draw.text(cx, 342, T(ctx, "In der App: Werkzeuge > Apple Home", "In the app: Tools > Apple Home"), "small", color.BLACK, "center")
  local u = device.url()
  if u ~= nil then draw.text(cx, 372, (u:gsub("/app/.*", "")), "small", color.BLACK, "center") end
end

local function tileBento(ctx, it, x, y, w, h, dim)
  local txt, col = fmt(ctx, it)
  if it.a then txt, col = T(ctx, "Offline", "Offline"), color.RED end
  draw.rect(x, y, w, h, color.WHITE, true, 16)
  draw.rect(x, y, w, h, color.BLACK, false, 16)
  draw.text(x + 14, y + 30, cut(it.n, w - 52, "normal"), "normal", color.BLACK, "left")
  if it.r ~= "" then draw.text(x + 14, y + 54, cut(it.r, w - 28, "small"), "small", color.BLACK, "left") end
  if col ~= nil then
    draw.circle(x + w - 20, y + 22, 8, col, true)
    draw.circle(x + w - 20, y + 22, 8, color.BLACK, false)
  end
  bigValue(x + w // 2, y + h - (h < 150 and 22 or 34), txt, w - 24, (not dim and col == color.RED) and color.RED or color.BLACK, "center", 1, h < 150)
end

local function drawBento(ctx, items, first)
  draw.clear(color.WHITE)
  local mx, gap = 20, 8
  local top = draw.top + 36
  local w = (draw.width - 2 * mx - (TILE_COLS - 1) * gap) // TILE_COLS
  local h = (draw.height - top - 14 - (TILE_ROWS - 1) * gap) // TILE_ROWS
  for i = 0, PER_TILES - 1 do
    local it = items[first + i]
    if it == nil then break end
    local col, row = i % TILE_COLS, i // TILE_COLS
    tileBento(ctx, it, mx + col * (w + gap), top + row * (h + gap), w, h, stale(ctx))
  end
end

local function tileApple(ctx, it, x, y, w, h, dim)
  local txt, fill, ink, ok = tileLook(ctx, it, h >= 150)
  local small = h < 150
  local pad = small and 12 or 16
  draw.rect(x, y, w, h, fill or color.WHITE, true, small and 18 or 24)
  draw.rect(x, y, w, h, color.BLACK, false, small and 18 or 24)
  local is = small and 28 or math.min(46, h // 4)
  glyph(it, x + pad, y + (small and 10 or 16), is, ink)
  if it.a then draw.icon("warning", x + w - (small and 34 or 40), y + (small and 8 or 12), small and 22 or 26, color.RED)
  elseif ok ~= nil then
    draw.circle(x + w - (small and 18 or 22), y + (small and 20 or 24), small and 6 or 8, ok, true)
    draw.circle(x + w - (small and 18 or 22), y + (small and 20 or 24), small and 6 or 8, color.BLACK, false)
  end
  local vy, ny, ry = h - 64, h - 34, h - 12
  if small then vy, ny, ry = h - 50, h - 29, h - 9 end
  if it.a or it.k == "scene" then draw.text(x + pad, y + vy, cut(txt, w - 2 * pad, small and "small" or "normal"), small and "small" or "normal", ink, "left")
  else bigValue(x + pad, y + vy, txt, w - 2 * pad, ink, "left", 1, small) end
  draw.text(x + pad, y + ny, cut(it.n, w - 2 * pad, small and "small" or "normal"), small and "small" or "normal", ink, "left")
  if it.r ~= "" then draw.text(x + pad, y + ry, cut(it.r, w - 2 * pad, "small"), "small", ink, "left") end
end

local function drawApple(ctx, items, first)
  draw.clear(color.WHITE)
  local mx, gap = 20, 8
  local top = draw.top + 36
  local w = (draw.width - 2 * mx - (TILE_COLS - 1) * gap) // TILE_COLS
  local h = (draw.height - top - 14 - (TILE_ROWS - 1) * gap) // TILE_ROWS
  for i = 0, PER_TILES - 1 do
    local it = items[first + i]
    if it == nil then break end
    local col, row = i % TILE_COLS, i // TILE_COLS
    tileApple(ctx, it, mx + col * (w + gap), top + row * (h + gap), w, h, stale(ctx))
  end
end

local function drawSlate(ctx, items, first)
  draw.clear(color.WHITE)
  local mx = 28
  local top = draw.top + 34
  local colW = (draw.width - 2 * mx - 24) // 2
  local rowH = (draw.height - top - 12) // 4
  for i = 0, PER_PAGE - 1 do
    local it = items[first + i]
    if it == nil then break end
    local col, row = i // 4, i % 4
    local x, y = mx + col * (colW + 24), top + row * rowH
    local txt, c = fmt(ctx, it)
    if it.a then txt, c = T(ctx, "Offline", "Offline"), nil end
    draw.line(x, y + rowH - 1, x + colW, y + rowH - 1, color.BLACK)
    local cy = y + rowH // 2
    draw.circle(x + 18, cy, 17, c or color.WHITE, true)
    draw.circle(x + 18, cy, 17, color.BLACK, false)
    glyph(it, x + 6, cy - 12, 24, (c == color.RED) and color.WHITE or color.BLACK)
    draw.text(x + 44, y + rowH // 2 + 4, cut(it.n, colW - 44 - 130, "normal"), "normal", color.BLACK, "left")
    if it.r ~= "" then draw.text(x + 44, y + rowH // 2 + 24, cut(it.r, colW - 44 - 130, "small"), "small", color.BLACK, "left") end
    draw.text(x + colW - 4, y + rowH // 2 + 10, txt, fit(txt, 124, { "large", "medium", "normal" }), color.BLACK, "right")
  end
end

local function drawNano(ctx, items, first)
  draw.clear(color.WHITE)
  local mx = 40
  local top = draw.top + 34
  local rowH = (draw.height - top - 10) // 8
  for i = 0, PER_PAGE - 1 do
    local it = items[first + i]
    if it == nil then break end
    local y = top + i * rowH
    local txt, c = fmt(ctx, it)
    if it.a then txt, c = T(ctx, "Offline", "Offline"), nil end
    local cy = y + rowH // 2
    if c ~= nil then draw.circle(mx + 12, cy, 13, c, true) end
    glyph(it, mx + 2, cy - 10, 20, (c == color.RED) and color.WHITE or color.BLACK)
    local label = it.r ~= "" and (it.n .. " · " .. it.r) or it.n
    draw.text(mx + 36, y + rowH // 2 + 6, cut(label, draw.width - 2 * mx - 220, "normal"), "normal", color.BLACK, "left")
    draw.text(draw.width - mx, y + rowH // 2 + 6, txt, "normal", color.BLACK, "right")
  end
end

-- Seitenplan: "rooms" = ein Raum je Seite (kleine Raeume teilen sich eine Seite, grosse laufen auf eine Folgeseite), "blocks" = je 8 Werte.
local function planOf(ctx, items, pages)
  local PP = perPage(ctx)
  if (ctx.cfg.grouping or "rooms") == "blocks" then
    for i = 1, #items, PP do
      local p = { items = {}, label = "" }
      for j = i, math.min(i + PP - 1, #items) do p.items[#p.items + 1] = items[j] end
      pages[#pages + 1] = p
    end
    return pages
  end
  local order, by = {}, {}
  for _, it in ipairs(items) do
    local r = it.r ~= "" and it.r or T(ctx, "Ohne Raum", "No room")
    if by[r] == nil then by[r] = {}; order[#order + 1] = r end
    by[r][#by[r] + 1] = it
  end
  local cur
  for _, r in ipairs(order) do
    local list = by[r]
    -- Szenen und Gruppen teilen sich nie eine Seite mit echten Raeumen (sonst steht "Szenen · Wohnzimmer" auf einer Seite)
    local cls = list[1].k == "scene" and "s" or (list[1].k == "group" and "g" or "r")
    local chunks = (#list + PP - 1) // PP
    for c = 1, chunks do
      local part = {}
      for j = (c - 1) * PP + 1, math.min(c * PP, #list) do part[#part + 1] = list[j] end
      local lbl = (chunks > 1) and (r .. " (" .. c .. "/" .. chunks .. ")") or r
      if cur ~= nil and cur.cls == cls and #cur.items + #part <= PP and chunks == 1 and not cur.split then
        for _, it in ipairs(part) do cur.items[#cur.items + 1] = it end
        cur.label = cur.label .. " · " .. lbl
      else
        cur = { items = part, label = lbl, split = chunks > 1, cls = cls }
        pages[#pages + 1] = cur
      end
    end
  end
  return pages
end

-- Favoriten (in der iPhone-App mit dem Stern gewaehlt) stehen immer auf den ersten Seiten, danach der Rest nach Raum bzw. in Bloecken.
local function pagePlan(ctx, items)
  local PP = perPage(ctx)
  local favs, rest = {}, {}
  for _, it in ipairs(items) do if it.f then favs[#favs + 1] = it else rest[#rest + 1] = it end end
  local pages = {}
  if #favs > 0 then
    local n = (#favs + PP - 1) // PP
    for c = 1, n do
      local part = {}
      for j = (c - 1) * PP + 1, math.min(c * PP, #favs) do part[#part + 1] = favs[j] end
      local lbl = T(ctx, "Favoriten", "Favourites")
      if n > 1 then lbl = lbl .. " (" .. c .. "/" .. n .. ")" end
      pages[#pages + 1] = { items = part, label = lbl, split = true }
    end
  end
  return planOf(ctx, rest, pages)
end

local function endPage(ctx)
  draw.clear(color.WHITE)
  local cx = draw.width // 2
  draw.text(cx, 220, T(ctx, "Keine weiteren Werte", "No more values"), "large", color.BLACK, "center")
  draw.text(cx, 262, T(ctx, "Diese Seite lässt sich im Studio ausblenden.", "This page can be hidden in Studio."), "normal", color.BLACK, "center")
end

function on_header(ctx, page)
  local pg = pagePlan(ctx, load(ctx))[page]
  if pg == nil or pg.label == "" then return nil end
  return pg.label
end

-- Tab-Reihe der Kopfzeile: Raumname abgekuerzt (2 Grossbuchstaben, z. B. "Wohnzimmer" -> "WO", "Kueche" -> "KU"), Favoriten als "F" statt "Seite N".
-- Die Firmware macht aus zwei Grossbuchstaben am Anfang eine breitere Pille; der volle Raumname steht in der Mitte der Kopfzeile (on_header).
local UML = { ["ä"] = "A", ["ö"] = "O", ["ü"] = "U", ["Ä"] = "A", ["Ö"] = "O", ["Ü"] = "U", ["ß"] = "S" }
local function abbrev(name)
  local out = ""
  for ch in name:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    local c = UML[ch] or ch
    if #c == 1 and c:match("%a") then out = out .. c:upper() end
    if #out >= 2 then break end
  end
  return out
end

function on_tab(ctx, page)
  local pg = pagePlan(ctx, load(ctx))[page]
  if pg == nil then return false end   -- ungenutzte Seite: kein Tab, wird beim Drehen uebersprungen
  if pg.label == "" then return tostring(page) end
  if pg.label:sub(1, #T(ctx, "Favoriten", "Favourites")) == T(ctx, "Favoriten", "Favourites") then return "F" end
  local first = (pg.label:match("^([^·(]+)") or pg.label):gsub("%s+$", "")
  local ab = abbrev(first)
  if ab == "" then return "-" end
  if #ab == 1 then return ab:upper() .. "." end
  return ab
end

function on_draw(ctx, page)
  local items = load(ctx)
  if #items == 0 then empty(ctx); return end
  local pg = pagePlan(ctx, items)[page]
  if pg == nil then endPage(ctx); header(ctx, items); return end
  local style = ctx.cfg.style or "apple"
  if style == "flat" then drawSlate(ctx, pg.items, 1)
  elseif style == "compact" then drawNano(ctx, pg.items, 1)
  elseif style == "cards" then drawBento(ctx, pg.items, 1)
  else drawApple(ctx, pg.items, 1) end
  header(ctx, items)
end

-- Widget: bevorzugt die Eintraege aus "pin" (Namen, mit Komma getrennt), sonst die ersten
function on_widget(ctx, box)
  local items = load(ctx)
  if #items == 0 then
    draw.text(box.x + box.w // 2, box.y + box.h // 2 + 6, T(ctx, "Noch keine Werte", "No values yet"), "normal", color.BLACK, "center")
    return
  end
  local pick = {}
  local pin = tostring(ctx.cfg.pin or "")
  for name in pin:gmatch("[^,]+") do
    name = name:gsub("^%s+", ""):gsub("%s+$", ""):lower()
    for _, it in ipairs(items) do if it.n:lower() == name then pick[#pick + 1] = it end end
  end
  if #pick == 0 then for _, it in ipairs(items) do if it.f and #pick < 6 then pick[#pick + 1] = it end end end
  if #pick == 0 then for i = 1, math.min(#items, 6) do pick[i] = items[i] end end
  local rows = math.max(1, math.min(#pick, box.h // 32))
  local lh = box.h // rows
  local dim = stale(ctx)
  for i = 1, rows do
    local it = pick[i]
    local y = box.y + (i - 1) * lh
    local txt, fill, ink = tileLook(ctx, it)
    local cy = y + lh // 2
    if fill ~= nil then draw.rect(box.x + 4, y + 2, box.w - 8, lh - 4, fill, true, 12) end
    local isz = math.min(24, lh - 8)
    glyph(it, box.x + 12, cy - isz // 2, isz, ink)
    local tx = box.x + 12 + isz + 10
    draw.text(tx, cy + 6, cut(it.n, box.w - (tx - box.x) - 100, "normal"), "normal", ink, "left")
    draw.text(box.x + box.w - 12, cy + 6, txt, "normal", ink, "right")
  end
  if dim then draw.text(box.x + box.w - 8, box.y + box.h - 3, ageText(ctx), "small", color.RED, "right") end
end

-- ===== Schnittstelle fuer die iOS-App =====

local function esc(s) return (tostring(s or ""):gsub('[%c"\\]', function(c) if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" end return " " end)) end

local function stateJson(ctx)
  local items = load(ctx)
  local parts = {}
  for i, it in ipairs(items) do
    parts[i] = string.format('{"k":"%s","n":"%s","r":"%s","v":%s,"u":"%s","a":%d,"f":%d}', esc(it.k), esc(it.n), esc(it.r), tostring(it.v), esc(it.u), it.a and 1 or 0, it.f and 1 or 0)
  end
  return string.format('{"ts":%d,"count":%d,"items":[%s]}', tonumber(ctx.data.get("ts")) or 0, #items, table.concat(parts, ","))
end

function on_http(ctx, req)
  local q = json.decode(req.body or "")
  if type(q) ~= "table" then return { status = 400, body = '{"error":"JSON"}' } end
  local op = tostring(q.op or "get")
  if op == "set" and type(q.items) == "table" then
    local lines = {}
    for i = 1, #q.items do
      local x = q.items[i]
      if type(x) == "table" and #lines < MAXI then
        local k = tostring(x.k or "number")
        if KINDS[k] == nil then k = "number" end
        local v = tonumber(x.v)
        local n = clean(x.n, 28)
        if v ~= nil and n ~= "" then
          lines[#lines + 1] = string.format("%s|%s|%s|%s|%s|%d|%d", k, n, clean(x.r, 20), tostring(v), clean(x.u, 6), (tonumber(x.a) or 0) ~= 0 and 1 or 0, (tonumber(x.f) or 0) ~= 0 and 1 or 0)
        end
      end
    end
    -- Nur neu zeichnen, wenn sich etwas geaendert hat: die iPhone-App sendet alle 30 Sekunden, ein Voll-Refresh des e-Papers dauert ~30 s und flackert.
    -- Auch ohne Aenderung wird neu gezeichnet, wenn der letzte Stand aelter als 10 Minuten war (die Altersanzeige "Stand vor ..." soll nicht haengen bleiben).
    local joined = table.concat(lines, "\n")
    local changed = joined ~= tostring(ctx.data.get("items") or "")
    local prev = tonumber(ctx.data.get("ts")) or 0
    local now = time.now() or 1
    if changed then ctx.data.set("items", joined) end
    ctx.data.set("ts", now)
    return { status = 200, body = stateJson(ctx), redraw = changed or (now - prev > 600) }
  end
  return { status = 200, body = stateJson(ctx) }
end

-- ===== Abgleich mit dem externen Speicher (von unterwegs) =====
-- Die iOS-App legt die Werte zusaetzlich als home.txt im Ordner "dir" des externen Speichers ab (erste Zeile = Zeitstempel, dann je Wert
-- "Art|Name|Raum|Wert|Einheit"). Ist die Datei neuer als der Stand auf dem Geraet, wird sie uebernommen; ist das Geraet neuer
-- (z. B. per WLAN gesendet), wird sie ueberschrieben. So kommen die Werte auch an, wenn das Handy nicht im Heimnetz ist.

local NAS_FILE = "home.txt"

local function cleanLines(raw)
  local out = {}
  for line in tostring(raw or ""):gmatch("[^\n]+") do
    local f = {}
    for x in (line .. "|"):gmatch("([^|]*)|") do f[#f + 1] = x end
    local v = tonumber(f[4])
    if #f >= 4 and KINDS[f[1]] ~= nil and v ~= nil and #out < MAXI then
      local n = clean(f[2], 28)
      if n ~= "" then out[#out + 1] = string.format("%s|%s|%s|%s|%s|%d|%d", f[1], n, clean(f[3], 20), tostring(v), clean(f[5] or "", 6), (tonumber(f[6]) or 0) ~= 0 and 1 or 0, (tonumber(f[7]) or 0) ~= 0 and 1 or 0) end
    end
  end
  return table.concat(out, "\n")
end

function on_fetch(ctx)
  if storage == nil or not storage.ready() then return true end
  local remote, err = storage.read("dir", NAS_FILE)
  local lts = tonumber(ctx.data.get("ts")) or 0
  local items = tostring(ctx.data.get("items") or "")
  if remote == nil then
    if err ~= "nicht gefunden" then return true end
    remote = ""
  end
  local first, rest = tostring(remote):match("^(%d+)\n?(.*)$")
  local rts = tonumber(first) or 0
  if rts > lts then
    local lines = cleanLines(rest)
    if lines ~= "" then
      -- unveraendert: Zeitstempel nur nachziehen, wenn der Stand >= 10 Minuten abweicht (sonst zaehlt jeder Abruf als "neue Daten" und zeichnet neu)
      if lines ~= items then
        ctx.data.set("items", lines)
        ctx.data.set("ts", rts)
      elseif rts - lts >= 600 then
        ctx.data.set("ts", rts)
      end
    end
  elseif lts > rts and items ~= "" then
    storage.write("dir", NAS_FILE, tostring(lts) .. "\n" .. items)
  end
  return true
end
