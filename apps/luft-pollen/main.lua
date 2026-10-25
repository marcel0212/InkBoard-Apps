-- Luft & Pollen (Paket luft-pollen): Luftqualitaet (europaeischer Index), Feinstaub, UV-Index und Pollenflug am Standort des
-- Geraets (Open-Meteo, CAMS) plus ein "Fenster-auf-Entscheider": vergleicht den CO2-Wert drinnen (eigener Raum und andere
-- InkBoards) mit der Luft draussen und sagt, ob jetzt gelueftet werden soll. Skript-API Level 22 (tlsVerify).
-- Standort: weather.location() (Wetter-Ort der Geraeteeinstellungen). Werte liegen in ctx.data (kein Speicher noetig).

local HOST_URL = "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=%.4f&longitude=%.4f"
  .. "&current=european_aqi,pm10,pm2_5,uv_index,alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen&timezone=auto"

local function T(ctx, de, en) return (ctx.lang == "en") and en or de end

-- Felder (ctx.data-Schluessel, Open-Meteo-Feld)
local FIELDS = { { "aqi", "european_aqi" }, { "pm10", "pm10" }, { "pm25", "pm2_5" }, { "uv", "uv_index" },
  { "alder", "alder_pollen" }, { "birch", "birch_pollen" }, { "grass", "grass_pollen" },
  { "mugwort", "mugwort_pollen" }, { "olive", "olive_pollen" }, { "ragweed", "ragweed_pollen" } }

-- Pollenarten: Schluessel, Name de/en, Schwellen (Koerner/m3) fuer gering / maessig / hoch
local POLLEN = {
  { "alder", "Erle", "Alder", { 10, 50, 200 } }, { "birch", "Birke", "Birch", { 10, 50, 200 } },
  { "grass", "Gräser", "Grasses", { 5, 25, 75 } }, { "mugwort", "Beifuß", "Mugwort", { 5, 20, 50 } },
  { "ragweed", "Ambrosia", "Ragweed", { 5, 20, 50 } }, { "olive", "Olive", "Olive", { 10, 50, 200 } },
}
local LEVEL_COLORS = { color.GREEN, color.GREEN, color.YELLOW, color.RED, color.RED }

local function num(ctx, k)
  local v = ctx.data.get(k)
  if v == nil then return nil end
  return tonumber(v)
end

-- ===== Stufen =====

local function aqi_level(v)
  local steps = { 20, 40, 60, 80 }
  for i = 1, #steps do if v < steps[i] then return i end end
  return 5
end

local function aqi_label(ctx, lv)
  local de = { "Sehr gut", "Gut", "Mäßig", "Schlecht", "Sehr schlecht" }
  local en = { "Very good", "Good", "Moderate", "Poor", "Very poor" }
  return (ctx.lang == "en" and en or de)[lv]
end

local function uv_level(v)
  if v < 3 then return 1 elseif v < 6 then return 2 elseif v < 8 then return 3 elseif v < 11 then return 4 end
  return 5
end

local function uv_label(ctx, lv)
  local de = { "niedrig", "mäßig", "hoch", "sehr hoch", "extrem" }
  local en = { "low", "moderate", "high", "very high", "extreme" }
  return (ctx.lang == "en" and en or de)[lv]
end

-- 0 keine, 1 gering, 2 maessig, 3 hoch, 4 sehr hoch
local function pollen_level(v, th)
  if v == nil or v < 1 then return 0 end
  if v < th[1] then return 1 elseif v < th[2] then return 2 elseif v < th[3] then return 3 end
  return 4
end

local function pollen_label(ctx, lv)
  local de = { "keine", "gering", "mäßig", "hoch", "sehr hoch" }
  local en = { "none", "low", "moderate", "high", "very high" }
  return (ctx.lang == "en" and en or de)[lv + 1]
end

-- Pollen mit Stufe, absteigend nach Stufe (nur vorhandene Werte)
local function pollen_list(ctx)
  local list = {}
  local any = false
  for i = 1, #POLLEN do
    local p = POLLEN[i]
    local v = num(ctx, p[1])
    if v ~= nil then
      any = true
      list[#list + 1] = { key = p[1], name = (ctx.lang == "en") and p[3] or p[2], v = v, lv = pollen_level(v, p[4]) }
    end
  end
  table.sort(list, function(a, b) if a.lv ~= b.lv then return a.lv > b.lv end return a.v > b.v end)
  return list, any
end

-- ===== Abruf =====

function on_fetch(ctx)
  local loc, why = weather.location()
  if not loc then
    ctx.data.set("err", why or "nolocation")
    return true
  end
  local body, err = http.get(string.format(HOST_URL, loc.lat, loc.lon))
  if body == nil then
    log("Luftdaten: " .. tostring(err))
    ctx.data.set("err", "net")
    return false
  end
  local doc = json.decode(body)
  local c = type(doc) == "table" and doc.current or nil
  if type(c) ~= "table" then
    ctx.data.set("err", "data")
    return false
  end
  for i = 1, #FIELDS do ctx.data.set(FIELDS[i][1], tonumber(c[FIELDS[i][2]])) end
  ctx.data.set("err", nil)
  ctx.data.set("place", loc.name)
  ctx.data.set("at", time.now())
  return true
end

-- ===== Fenster-Entscheider =====

-- Belastung draussen: 0 gut, 1 leicht, 2 stark; Grund als Text
local function outdoor_burden(ctx)
  local burden, why = 0, {}
  local a = num(ctx, "aqi")
  if a then
    local lv = aqi_level(a)
    if lv >= 4 then burden = 2; why[#why + 1] = T(ctx, "Luftqualität schlecht", "poor air quality")
    elseif lv == 3 then burden = math.max(burden, 1); why[#why + 1] = T(ctx, "Luftqualität mäßig", "moderate air quality") end
  end
  if ctx.cfg.allergy then
    local list = pollen_list(ctx)
    local top = list[1]
    if top and top.lv >= 3 then burden = 2; why[#why + 1] = top.name .. " " .. pollen_label(ctx, top.lv)
    elseif top and top.lv == 2 then burden = math.max(burden, 1); why[#why + 1] = top.name .. " " .. pollen_label(ctx, top.lv) end
  end
  return burden, why
end

-- Raeume mit CO2: eigener Raum + andere InkBoards. need = Wert ab 85 % der Warnschwelle
local function rooms(ctx)
  local out = {}
  local s = sensor.get()
  local thr = 1000
  if s then
    thr = (s.co2_warn_ppm or 1200) * 0.85
    if s.co2 then out[#out + 1] = { name = s.room or "", co2 = s.co2, own = true, need = s.co2 >= thr } end
  end
  local peers = sensor.peers()
  if peers then
    for i = 1, #peers do
      local p = peers[i]
      if p.valid and p.co2 then out[#out + 1] = { name = p.room or "", co2 = p.co2, need = p.co2 >= thr } end
    end
  end
  return out, thr
end

-- Raum-ID -> Anzeigename mit Umlauten (die Firmware liefert die ID, z. B. "kueche")
local ROOM_DE = { wohnzimmer = "Wohnzimmer", flur = "Flur", kueche = "Küche", bad = "Bad", schlafzimmer = "Schlafzimmer",
  buero = "Büro", gaestezimmer = "Gästezimmer", waschkueche = "Waschküche", kinderzimmer = "Kinderzimmer", arbeitszimmer = "Arbeitszimmer",
  esszimmer = "Esszimmer", keller = "Keller", garage = "Garage", dachboden = "Dachboden", balkon = "Balkon", terrasse = "Terrasse", diele = "Diele" }
local ROOM_EN = { wohnzimmer = "Living room", flur = "Hallway", kueche = "Kitchen", bad = "Bathroom", schlafzimmer = "Bedroom",
  buero = "Office", gaestezimmer = "Guest room", waschkueche = "Laundry room", kinderzimmer = "Kids' room", arbeitszimmer = "Study",
  esszimmer = "Dining room", keller = "Basement", garage = "Garage", dachboden = "Attic", balkon = "Balcony", terrasse = "Terrace", diele = "Hall" }
local function room_label(r, en)
  r = tostring(r or "")
  if r == "" then return r end
  local m = (en and ROOM_EN or ROOM_DE)[r:lower()]
  if m then return m end
  return r:sub(1, 1):upper() .. r:sub(2)
end

local function nice_room(r, ctx)
  return room_label(r, ctx ~= nil and ctx.lang == "en")
end

-- Ergebnis: { code, col, title, sub, rooms, why }
local function verdict(ctx)
  local list = rooms(ctx)
  local burden, why = outdoor_burden(ctx)
  local need = false
  for i = 1, #list do if list[i].need then need = true end end
  local v = { rooms = list, why = why, burden = burden }
  if #list == 0 then
    v.code, v.col = "unknown", color.BLACK
    v.title = T(ctx, "Kein CO2-Wert", "No CO2 reading")
    v.sub = T(ctx, "Der Raumsensor liefert noch keine Messung.", "The room sensor has no reading yet.")
  elseif need and burden == 0 then
    v.code, v.col = "open", color.GREEN
    v.title = T(ctx, "Jetzt lüften", "Ventilate now")
    v.sub = T(ctx, "Drinnen ist die Luft verbraucht, draußen ist sie gut.", "Indoor air is stale, outdoor air is good.")
  elseif need and burden == 1 then
    v.code, v.col = "short", color.YELLOW
    v.title = T(ctx, "Kurz stoßlüften", "Short burst of fresh air")
    v.sub = T(ctx, "3 bis 5 Minuten, draußen ist die Luft leicht belastet.", "3 to 5 minutes, outdoor air is slightly burdened.")
  elseif need then
    v.code, v.col = "short2", color.RED
    v.title = T(ctx, "Nur ganz kurz lüften", "Ventilate very briefly")
    v.sub = T(ctx, "Draußen stark belastet - 2 Minuten Durchzug reichen.", "Heavily burdened outside - 2 minutes of draught is enough.")
  elseif burden >= 1 then
    v.code, v.col = "closed", burden == 2 and color.RED or color.YELLOW
    v.title = T(ctx, "Fenster zu lassen", "Keep windows closed")
    v.sub = T(ctx, "Drinnen ist die Luft gut, draußen belastet.", "Indoor air is fine, outdoor air is burdened.")
  else
    v.code, v.col = "ok", color.GREEN
    v.title = T(ctx, "Alles in Ordnung", "All good")
    v.sub = T(ctx, "Drinnen und draußen ist die Luft gut.", "Air is good indoors and outdoors.")
  end
  return v
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

local function status_screen(ctx)
  draw.clear(color.WHITE)
  local err = ctx.data.get("err")
  local y = draw.top + 140
  if err == "nolocation" then
    draw.text(draw.width // 2, y, T(ctx, "Kein Standort eingerichtet", "No location set"), "large", color.BLACK, "center")
    draw.text(draw.width // 2, y + 40, T(ctx, "Wetter-Ort in den Geräteeinstellungen wählen", "Choose the weather location in the device settings"), "normal", color.BLACK, "center")
  elseif err then
    draw.text(draw.width // 2, y, T(ctx, "Luftdaten nicht erreichbar", "Air data unavailable"), "large", color.BLACK, "center")
    draw.text(draw.width // 2, y + 40, T(ctx, "Wird beim nächsten Abruf erneut versucht", "Will retry on the next update"), "normal", color.BLACK, "center")
  else
    draw.text(draw.width // 2, y, T(ctx, "Lade Luftdaten …", "Loading air data …"), "large", color.BLACK, "center")
  end
end

-- Segmentbalken: n von total Segmenten gefuellt (Farbe der Stufe)
local function seg_bar(x, y, w, h, total, n, col)
  local gap = 6
  local sw = (w - gap * (total - 1)) // total
  for i = 1, total do
    local sx = x + (i - 1) * (sw + gap)
    if i <= n then draw.rect(sx, y, sw, h, col, true, 4) end
    draw.rect(sx, y, sw, h, color.BLACK, false, 4)
  end
end

local function frame(style, x, y, w, h)
  if style == "cards" then draw.rect(x, y, w, h, color.BLACK, false, 14) end
end

local function footer(ctx)
  local place = ctx.data.get("place")
  local txt = "Open-Meteo" .. ((place and place ~= "") and (" · " .. place) or "")
  draw.text(28, draw.height - 10, cut(txt, draw.width - 56, "small"), "small", color.BLACK, "left")
end

local function page_air(ctx)
  local style = ctx.cfg.style or "cards"
  local aqi = num(ctx, "aqi")
  if aqi == nil then return status_screen(ctx) end
  draw.clear(color.WHITE)
  local W, H, y0 = draw.width, draw.height, draw.top
  local lv = aqi_level(aqi)
  local col = LEVEL_COLORS[lv]
  local pm25, pm10, uv = num(ctx, "pm25"), num(ctx, "pm10"), num(ctx, "uv")
  local function f1(v) return v and string.format("%.0f", v) or "-" end
  local tall = H > W
  if style == "compact" then
    if tall then y0 = y0 + 150 end
    draw.text(W // 2, y0 + 150, string.format("%.0f", aqi), "huge", color.BLACK, "center")
    draw.text(W // 2, y0 + 192, T(ctx, "Luftqualität", "Air quality") .. ": " .. aqi_label(ctx, lv), "large", color.BLACK, "center")
    seg_bar(W // 2 - 160, y0 + 214, 320, 22, 5, lv, col)
    local line = {}
    if uv then line[#line + 1] = "UV " .. string.format("%.0f", uv) .. " (" .. uv_label(ctx, uv_level(uv)) .. ")" end
    if pm25 then line[#line + 1] = "PM2.5 " .. f1(pm25) end
    if tall then
      for i = 1, #line do draw.text(W // 2, y0 + 276 + (i - 1) * 40, line[i], "large", color.BLACK, "center") end
    else
      draw.text(W // 2, y0 + 276, table.concat(line, "   ·   "), "large", color.BLACK, "center")
    end
    footer(ctx)
    return
  end
  draw.text(28, y0 + 34, T(ctx, "Luftqualität", "Air quality"), "large", color.BLACK, "left")
  local top = y0 + 52
  local ch = H - top - 40
  local lw = W // 2 - 30
  if tall then lw, ch = W - 48, 330 end
  frame(style, 24, top, lw, ch)
  if style == "flat" and not tall then draw.line(24 + lw + 14, top, 24 + lw + 14, top + ch, color.BLACK) end
  draw.circle(24 + 36, top + 38, 12, col, true)
  draw.circle(24 + 36, top + 38, 12, color.BLACK, false)
  draw.text(24 + 58, top + 46, aqi_label(ctx, lv), "large", color.BLACK, "left")
  draw.text(24 + lw // 2, top + 160, string.format("%.0f", aqi), "huge", color.BLACK, "center")
  draw.text(24 + lw // 2, top + 190, T(ctx, "Europäischer Index (EAQI)", "European index (EAQI)"), "small", color.BLACK, "center")
  seg_bar(24 + 30, top + ch - 50, lw - 60, 22, 5, lv, col)
  local rx = 24 + lw + 28
  local rw = W - rx - 24
  local hh = (ch - 14) // 2
  local ptop, uy = top, top + hh + 14
  local uhh = hh
  if tall then
    rx, rw, hh, uhh = 38, W - 76, 130, 150
    ptop = top + ch + 14
    uy = ptop + hh + 14
  end
  frame(style, rx - 14, ptop, rw + 14, hh)
  if tall and style == "flat" then draw.line(24, ptop - 7, W - 24, ptop - 7, color.BLACK) end
  draw.text(rx, ptop + 30, T(ctx, "Feinstaub", "Particulates"), "small", color.BLACK, "left")
  draw.text(rx, ptop + 72, "PM2.5  " .. f1(pm25), "large", color.BLACK, "left")
  draw.text(rx, ptop + 108, "PM10   " .. f1(pm10) .. "  µg/m³", "normal", color.BLACK, "left")
  frame(style, rx - 14, uy, rw + 14, uhh)
  if style == "flat" then draw.line(rx - 14, uy - 7, W - 24, uy - 7, color.BLACK) end
  draw.text(rx, uy + 30, T(ctx, "UV-Index", "UV index"), "small", color.BLACK, "left")
  if uv then
    local ul = uv_level(uv)
    draw.text(rx, uy + 76, string.format("%.0f", uv), "huge", color.BLACK, "left")
    draw.text(rx + 70, uy + 72, uv_label(ctx, ul), "large", color.BLACK, "left")
    if uv >= 3 then draw.text(rx, uy + uhh - 14, T(ctx, "Sonnenschutz nutzen", "Use sun protection"), "small", color.BLACK, "left") end
  else
    draw.text(rx, uy + 72, "-", "large", color.BLACK, "left")
  end
  footer(ctx)
end

local function page_pollen(ctx)
  local style = ctx.cfg.style or "cards"
  if num(ctx, "aqi") == nil then return status_screen(ctx) end
  draw.clear(color.WHITE)
  local W, H, y0 = draw.width, draw.height, draw.top
  local list, any = pollen_list(ctx)
  draw.text(28, y0 + 34, T(ctx, "Pollenflug", "Pollen"), "large", color.BLACK, "left")
  draw.line(28, y0 + 48, W - 28, y0 + 48, color.BLACK)
  local top3 = list[1] and list[1].lv or 0
  if not any or top3 == 0 then
    draw.text(W // 2, y0 + 170, any and T(ctx, "Keine Pollenbelastung", "No pollen load") or T(ctx, "Keine Pollendaten für diesen Ort", "No pollen data for this location"), "large", top3 == 0 and any and color.GREEN or color.BLACK, "center")
    draw.text(W // 2, y0 + 210, T(ctx, "Pollendaten gibt es nur in Europa und während der Saison", "Pollen data covers Europe during the season only"), "small", color.BLACK, "center")
    footer(ctx)
    return
  end
  local rows = (style == "compact") and math.min(3, #list) or #list
  local rowH = math.min(style == "compact" and 90 or 56, (H - y0 - 100) // rows)
  local font = (style == "compact") and "large" or "normal"
  for i = 1, rows do
    local p = list[i]
    local y = y0 + 60 + (i - 1) * rowH
    if style == "cards" then draw.rect(24, y, W - 48, rowH - 8, color.BLACK, false, 12)
    elseif style == "flat" then draw.line(28, y + rowH - 4, W - 28, y + rowH - 4, color.BLACK) end
    local cy = y + (rowH - 8) // 2
    draw.text(44, cy + 8, p.name, font, color.BLACK, "left")
    local bx = W // 2 - 60
    local bw = W - bx - 190
    seg_bar(bx, cy - 10, bw, 20, 4, p.lv, LEVEL_COLORS[p.lv + 1])
    draw.text(W - 40, cy + 8, pollen_label(ctx, p.lv), font, color.BLACK, "right")
  end
  footer(ctx)
end

local function page_vent(ctx)
  local style = ctx.cfg.style or "cards"
  draw.clear(color.WHITE)
  local W, H, y0 = draw.width, draw.height, draw.top
  local v = verdict(ctx)
  if num(ctx, "aqi") == nil and #v.rooms == 0 then return status_screen(ctx) end
  local tall = H > W
  if style == "compact" then
    if tall then y0 = y0 + 160 end
    draw.circle(W // 2, y0 + 90, 40, v.col, true)
    draw.circle(W // 2, y0 + 90, 40, color.BLACK, false)
    draw.text(W // 2, y0 + 190, cut(v.title, W - 60, "large"), "large", color.BLACK, "center")
    draw.text(W // 2, y0 + 228, cut(v.sub, W - 60, "normal"), "normal", color.BLACK, "center")
    return
  end
  draw.text(28, y0 + 34, T(ctx, "Lüften?", "Ventilate?"), "large", color.BLACK, "left")
  local top = y0 + 52
  local bh = 96
  if style == "cards" then draw.rect(24, top, W - 48, bh, color.BLACK, false, 14) else draw.line(28, top + bh + 6, W - 28, top + bh + 6, color.BLACK) end
  draw.circle(24 + 48, top + bh // 2, 26, v.col, true)
  draw.circle(24 + 48, top + bh // 2, 26, color.BLACK, false)
  local tf = draw.measure(v.title, "large") <= W - 170 and "large" or "normal"
  draw.text(24 + 96, top + 40, cut(v.title, W - 170, tf), tf, color.BLACK, "left")
  draw.text(24 + 96, top + 74, cut(v.sub, W - 170, "small"), "small", color.BLACK, "left")
  local y = top + bh + 34
  draw.text(28, y, T(ctx, "Drinnen", "Indoors"), "small", color.BLACK, "left")
  for i = 1, math.min(4, #v.rooms) do
    local r = v.rooms[i]
    y = y + 30
    draw.circle(40, y - 7, 7, r.need and color.RED or color.GREEN, true)
    draw.circle(40, y - 7, 7, color.BLACK, false)
    local rv = string.format("%d ppm", r.co2)
    local rvx = tall and W - 40 or W // 2 - 20
    draw.text(58, y, cut(nice_room(r.name, ctx) .. (r.own and T(ctx, " (hier)", " (here)") or ""), rvx - 58 - draw.measure(rv, "normal") - 12, "normal"), "normal", color.BLACK, "left")
    draw.text(rvx, y, rv, "normal", color.BLACK, "right")
  end
  local ox = W // 2 + 20
  local oy = top + bh + 34
  if tall then ox, oy = 28, y + 50 end
  draw.text(ox, oy, T(ctx, "Draußen", "Outdoors"), "small", color.BLACK, "left")
  local a = num(ctx, "aqi")
  if a then
    local lv = aqi_level(a)
    oy = oy + 30
    draw.circle(ox + 12, oy - 7, 7, LEVEL_COLORS[lv], true)
    draw.circle(ox + 12, oy - 7, 7, color.BLACK, false)
    draw.text(ox + 30, oy, T(ctx, "Luft: ", "Air: ") .. aqi_label(ctx, lv), "normal", color.BLACK, "left")
  end
  local list = pollen_list(ctx)
  if list[1] then
    oy = oy + 30
    local lv = list[1].lv
    draw.circle(ox + 12, oy - 7, 7, LEVEL_COLORS[lv + 1], true)
    draw.circle(ox + 12, oy - 7, 7, color.BLACK, false)
    draw.text(ox + 30, oy, cut(list[1].name .. ": " .. pollen_label(ctx, lv), W - ox - 40, "normal"), "normal", color.BLACK, "left")
  end
  local ok, w = pcall(weather.get)
  if ok and type(w) == "table" and w.temp then
    oy = oy + 30
    draw.text(ox + 30, oy, string.format("%.0f °C", w.temp), "normal", color.BLACK, "left")
  end
  if not ctx.cfg.allergy then
    draw.text(W - 28, H - 10, T(ctx, "Pollen zählen nur mit „Ich reagiere auf Pollen“", "Pollen only count with “I react to pollen”"), "small", color.BLACK, "right")
  end
end

function on_draw(ctx, page)
  if page == 2 then return page_pollen(ctx) end
  if page == 3 then return page_vent(ctx) end
  return page_air(ctx)
end

function on_widget(ctx, box)
  local style = ctx.cfg.style or "cards"
  local cx = box.x + box.w // 2
  local aqi = num(ctx, "aqi")
  if aqi == nil then
    draw.text(cx, box.y + box.h // 2 + 6, T(ctx, "Luftdaten laden …", "Loading air data …"), "normal", color.BLACK, "center")
    return
  end
  local lv = aqi_level(aqi)
  local v = verdict(ctx)
  if box.h < 80 or style == "compact" then
    draw.circle(box.x + 22, box.y + box.h // 2, 12, v.col, true)
    draw.circle(box.x + 22, box.y + box.h // 2, 12, color.BLACK, false)
    draw.text(box.x + 44, box.y + box.h // 2 + 8, cut(v.title, box.w - 56, "normal"), "normal", color.BLACK, "left")
    return
  end
  draw.text(box.x + 10, box.y + 22, T(ctx, "Luft", "Air"), "small", color.BLACK, "left")
  draw.text(box.x + 10, box.y + 66, string.format("%.0f", aqi), "huge", color.BLACK, "left")
  draw.text(box.x + 100, box.y + 62, cut(aqi_label(ctx, lv), box.w - 90, "normal"), "normal", color.BLACK, "left")
  local uv = num(ctx, "uv")
  local list = pollen_list(ctx)
  local y = box.y + 88
  if uv then draw.text(box.x + 10, y, "UV " .. string.format("%.0f", uv) .. " · " .. uv_label(ctx, uv_level(uv)), "small", color.BLACK, "left") end
  if list[1] and list[1].lv > 0 then draw.text(box.x + box.w - 10, y, cut(list[1].name .. " " .. pollen_label(ctx, list[1].lv), box.w // 2 - 6, "small"), "small", color.BLACK, "right") end
  y = y + 26
  draw.circle(box.x + 20, y - 6, 8, v.col, true)
  draw.circle(box.x + 20, y - 6, 8, color.BLACK, false)
  draw.text(box.x + 38, y, cut(v.title, box.w - 50, "normal"), "normal", color.BLACK, "left")
end
