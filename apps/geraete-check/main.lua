-- Geräte-Check (Paket geraete-check): Zustand dieses InkBoards auf einen Blick - Uhr, WLAN, Akku, externer Speicher,
-- Arbeitsspeicher, Firmware. Skript-API Level 24 (system.get(), nur lesend). Kein on_fetch, kein Netzabruf: on_draw liest den
-- Zustand bei jedem Zeichnen frisch. Jede Zeile hat eine Ampel (gruen ok, gelb Hinweis, rot Problem, Ring = nicht eingerichtet).

local OK, WARN, BAD, NONE = 0, 1, 2, 3

local function ago(sec, en)
  if sec < 0 then sec = 0 end
  if sec < 90 then return en and "just now" or "gerade eben" end
  if sec < 5400 then return string.format(en and "%d min ago" or "vor %d Min.", math.floor(sec / 60 + 0.5)) end
  if sec < 172800 then return string.format(en and "%d h ago" or "vor %d Std.", math.floor(sec / 3600 + 0.5)) end
  return string.format(en and "%d d ago" or "vor %d Tg.", math.floor(sec / 86400 + 0.5))
end

local function span(sec, en)
  if sec < 3600 then return string.format("%d min", math.floor(sec / 60)) end
  if sec < 86400 then return string.format(en and "%d h %d min" or "%d Std. %d Min.", sec // 3600, (sec % 3600) // 60) end
  return string.format(en and "%d d %d h" or "%d Tg. %d Std.", sec // 86400, (sec % 86400) // 3600)
end

local function cut(text, maxw, font)
  while #text > 1 and draw.measure(text, font) > maxw do
    local i = #text
    while i > 1 and (text:byte(i) & 0xC0) == 0x80 do i = i - 1 end
    text = text:sub(1, i - 1)
  end
  return text
end

-- Zeilen aus dem Geraetezustand: { label, value, state }
local function rows(s, en)
  local r = {}
  -- Uhr
  if s.clock_ok then
    local t = time.localtime()
    local v = t and string.format("%02d:%02d  %02d.%02d.%04d", t.hour, t.min, t.day, t.month, t.year) or "ok"
    r[#r + 1] = { en and "Clock" or "Uhr", v, OK }
  else
    r[#r + 1] = { en and "Clock" or "Uhr", en and "Not set (no NTP)" or "Nicht gestellt (kein NTP)", BAD }
  end
  -- WLAN
  if s.wifi then
    local q, st = en and "good" or "gut", OK
    if s.rssi <= -80 then q, st = en and "weak" or "schwach", BAD
    elseif s.rssi <= -70 then q, st = en and "fair" or "mittel", WARN end
    r[#r + 1] = { "WLAN", string.format("%d dBm  (%s)", s.rssi, q), st }
  else
    r[#r + 1] = { "WLAN", en and "Not connected" or "Nicht verbunden", BAD }
  end
  -- Akku
  if s.battery ~= nil then
    local st = OK
    if s.battery <= 10 then st = BAD elseif s.battery <= 25 then st = WARN end
    r[#r + 1] = { en and "Battery" or "Akku", string.format("%d %%  (%s)", math.floor(s.battery + 0.5), s.on_battery and (en and "battery mode" or "Akkubetrieb") or (en and "mains" or "Netzbetrieb")), st }
  else
    r[#r + 1] = { en and "Battery" or "Akku", s.on_battery and (en and "No reading" or "Kein Messwert") or (en and "Mains powered" or "Netzbetrieb"), NONE }
  end
  -- Externer Speicher (NAS)
  local nas = en and "Storage" or "Ext. Speicher"
  if not s.nas_ready then
    r[#r + 1] = { nas, en and "Not set up" or "Nicht eingerichtet", NONE }
  elseif s.nas_fail_since ~= nil and s.clock_ok then
    r[#r + 1] = { nas, (en and "Upload failing for " or "Upload scheitert seit ") .. span(s.now - s.nas_fail_since, en), BAD }
  elseif s.nas_error ~= nil and s.nas_error ~= "" then
    r[#r + 1] = { nas, (en and "Error: " or "Fehler: ") .. s.nas_error, BAD }
  elseif s.nas_ok ~= nil and s.clock_ok then
    local age = s.now - s.nas_ok
    r[#r + 1] = { nas, (en and "Last upload " or "Letzter Upload ") .. ago(age, en), age > 3 * 3600 and WARN or OK }
  else
    r[#r + 1] = { nas, en and "No upload since start" or "Noch kein Upload seit dem Start", (s.uptime > 3600) and WARN or NONE }
  end
  -- Arbeitsspeicher
  local st = OK
  if s.free_kb < 40 then st = BAD elseif s.free_kb < 80 then st = WARN end
  r[#r + 1] = { en and "Memory" or "Arbeitsspeicher", string.format(en and "%d KB free" or "%d KB frei", s.free_kb), st }
  -- Firmware
  r[#r + 1] = { "Firmware", string.format("%s  -  %s", s.version, (en and "up " or "läuft ") .. span(s.uptime, en)), OK }
  return r
end

local function light(cx, cy, r, st)
  if st == NONE then
    draw.circle(cx, cy, r, color.BLACK, false)
    draw.circle(cx, cy, r - 1, color.BLACK, false)
  else
    local c = st == OK and color.GREEN or (st == WARN and color.YELLOW or color.RED)
    draw.circle(cx, cy, r, c, true)
    draw.circle(cx, cy, r, color.BLACK, false)
  end
end

local function summary(list, en)
  local bad, warn = 0, 0
  for i = 1, #list do
    if list[i][3] == BAD then bad = bad + 1 elseif list[i][3] == WARN then warn = warn + 1 end
  end
  local fill, ink, msg = color.GREEN, color.BLACK, en and "All good" or "Alles in Ordnung"
  if bad > 0 then
    fill, ink = color.RED, color.WHITE
    msg = bad == 1 and (en and "1 problem" or "1 Problem") or string.format(en and "%d problems" or "%d Probleme", bad)
    if warn > 0 then msg = msg .. (warn == 1 and (en and ", 1 notice" or ", 1 Hinweis") or string.format(en and ", %d notices" or ", %d Hinweise", warn)) end
  elseif warn > 0 then
    fill, ink = color.YELLOW, color.BLACK
    msg = warn == 1 and (en and "1 notice" or "1 Hinweis") or string.format(en and "%d notices" or "%d Hinweise", warn)
  end
  return fill, ink, msg, bad, warn
end

local function who_of(s)
  return (s.room ~= nil and s.room ~= "") and s.room:sub(1, 1):upper() .. s.room:sub(2) or "InkBoard"
end

function on_draw(ctx, page)
  local en = (ctx.lang == "en")
  local style = ctx.cfg.style or "flat"
  draw.clear(color.WHITE)
  local s = system.get()
  if s == nil then
    draw.text(draw.width // 2, draw.top + 160, en and "Device state not available" or "Gerätezustand nicht verfügbar", "large", color.BLACK, "center")
    draw.text(draw.width // 2, draw.top + 196, en and "Firmware update needed (API 24)" or "Firmware-Update nötig (API 24)", "normal", color.BLACK, "center")
    return
  end
  local list = rows(s, en)
  local fill, ink, msg = summary(list, en)
  local top = draw.top + 10
  if style == "compact" then
    -- Nano: grosses Ergebnis, darunter eine Reihe Ampeln mit Namen
    draw.rect(60, top + 20, draw.width - 120, 130, fill, true, 20)
    draw.text(draw.width // 2, top + 100, cut(msg, draw.width - 160, "large"), "large", ink, "center")
    local n = #list
    local colw = (draw.width - 80) // n
    for i = 1, n do
      local cx = 40 + colw * (i - 1) + colw // 2
      light(cx, top + 210, 20, list[i][3])
      draw.text(cx, top + 270, cut(list[i][1], colw - 6, "small"), "small", color.BLACK, "center")
    end
    draw.text(draw.width // 2, top + 340, who_of(s) .. "  -  " .. s.version, "normal", color.BLACK, "center")
    return
  end
  draw.rect(24, top, draw.width - 48, 50, fill, true, 14)
  draw.text(48, top + 34, msg, "large", ink, "left")
  draw.text(draw.width - 48, top + 33, who_of(s), "normal", ink, "right")
  if style == "cards" then
    -- Bento: Kacheln in zwei Spalten
    local tw = (draw.width - 48 - 12) // 2
    local th = 104
    for i = 1, #list do
      local col, row = (i - 1) % 2, (i - 1) // 2
      local x = 24 + col * (tw + 12)
      local y = top + 62 + row * (th + 10)
      draw.rect(x, y, tw, th, color.BLACK, false, 14)
      light(x + 28, y + 30, 13, list[i][3])
      draw.text(x + 52, y + 36, list[i][1], "normal", color.BLACK, "left")
      local v = list[i][2]
      local font = "normal"
      if draw.measure(v, "large") <= tw - 24 then font = "large" end
      draw.text(x + 16, y + 84, cut(v, tw - 24, font), font, color.BLACK, "left")
    end
    return
  end
  -- Slate: Liste
  local y = top + 62
  local rowH = 54
  for i = 1, #list do
    local label, value, st = list[i][1], list[i][2], list[i][3]
    local cy = y + rowH // 2
    light(50, cy, 13, st)
    draw.text(84, cy + 8, label, "normal", color.BLACK, "left")
    local maxw = draw.width - 24 - 270
    local font = "large"
    if draw.measure(value, font) > maxw then font = "normal" end
    draw.text(draw.width - 40, cy + 9, cut(value, maxw, font), font, color.BLACK, "right")
    if i < #list then draw.line(84, y + rowH, draw.width - 40, y + rowH, color.BLACK) end
    y = y + rowH
  end
end

function on_widget(ctx, box)
  local en = (ctx.lang == "en")
  local s = system.get()
  local cx = box.x + box.w // 2
  if s == nil then
    draw.text(cx, box.y + box.h // 2, en and "No data yet" or "Noch keine Daten", "small", color.BLACK, "center")
    return
  end
  local list = rows(s, en)
  local fill, ink, msg = summary(list, en)
  local bh = math.min(box.h, 52)
  if box.h < 70 then bh = box.h end
  draw.rect(box.x + 4, box.y + 2, box.w - 8, bh - 4, fill, true, 10)
  local mf = draw.measure(msg, "large") <= box.w - 24 and "large" or "normal"
  draw.text(cx, box.y + bh // 2 + 8, cut(msg, box.w - 24, mf), mf, ink, "center")
  if box.h >= 70 then
    local n = #list
    local colw = (box.w - 8) // n
    local r = math.max(5, math.min(11, colw // 2 - 3))
    for i = 1, n do
      local x = box.x + 4 + colw * (i - 1) + colw // 2
      light(x, box.y + bh + r + 8, r, list[i][3])
      if box.h >= 110 and colw >= 56 and ctx.cfg.style ~= "compact" then
        draw.text(x, box.y + bh + 2 * r + 30, cut(list[i][1], colw - 2, "small"), "small", color.BLACK, "center")
      end
    end
  end
end
