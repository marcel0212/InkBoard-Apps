-- Wetter: die Wetter-App mit allen Seiten (Innen, Außen, Netzwerk) und den Dashboard-Widgets "Wetter Innen" und
-- "Wetter Außen" als EIN Standard-Paket. Seit Paketversion 1.1.0 ist das eine ganz normale Skript-App mit drei Seiten
-- (Innen, Außen, Netzwerk; Seitenwahl und Reihenfolge wie bei jeder App). Stil (ctx.cfg.style: cards/flat/compact = Bento/
-- Slate/Nano) steht in den Paket-Einstellungen; für die Widgets gilt deren eigener Stil. Die Seite kommt aus dem
-- draw-Argument (1 Innen, 2 Außen, 3 Netzwerk), das Widget aus ctx.cfg.widget.
-- Außen: weather.get() (Stufe 3). Innen/Netzwerk: sensor.* (Stufe 4). Alle Paket-Einstellungen (Fokuswert, Zusatzwerte,
-- Warnschwellen, Verlaufszeitraum, Stil) stehen im Manifest.

local outdoor = {}
local indoor = {}

-- ====================================================================================== Seite/Widget Außen
do

local DAYS_DE = {"Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"}
local DAYS_EN = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"}
local SHORT_DE = {"Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"} -- Montag zuerst
local SHORT_EN = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}
local MONTHS_DE = {"Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"}
local MONTHS_EN = {"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"}

local W = 800
local CARD_MARGIN = 14
local CARD_RADIUS = 8

local function tr(en, de, ctx) if ctx.lang == "en" then return en end return de end

-- Karte mit seitlicher Akzent-Leiste
local function accentCard(x, y, w, h)
  draw.rect(x, y, w, h, color.WHITE, true, CARD_RADIUS)
  draw.rect(x, y, w, h, color.BLACK, false, CARD_RADIUS)
  draw.rect(x + 6, y + 6, 5, h - 12, color.ACCENT, true, 2)
end

local function hline(x, y, w)
  draw.rect(x, y, w, 1, color.BLACK, true)
end

local function thickLine(x0, y0, x1, y1, col)
  draw.line(x0, y0, x1, y1, col)
  draw.line(x0, y0 + 1, x1, y1 + 1, col)
  draw.line(x0 + 1, y0, x1 + 1, y1, col)
  draw.line(x0, y0 - 1, x1, y1 - 1, col)
  draw.line(x0 - 1, y0, x1 - 1, y1, col)
end

local function catmull(p0, p1, p2, p3, t)
  local t2, t3 = t * t, t * t * t
  return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end

local function round(v) return math.floor(v + 0.5) end

-- Stundenverlauf als weich geglättete Linie (Catmull-Rom, 4 Schritte je Abschnitt)
local function sparkline(x, y, w, h, vals, col)
  local n = #vals
  if n < 2 then return end
  local minV, maxV = vals[1], vals[1]
  for i = 2, n do
    if vals[i] < minV then minV = vals[i] end
    if vals[i] > maxV then maxV = vals[i] end
  end
  local range = maxV - minV
  if range < 0.5 then range = 0.5 end
  local function xAt(idx) return x + idx * (w - 1) / (n - 1) end
  local function yAt(v) return y + h - 1 - (v - minV) / range * (h - 1) end
  local px, py = xAt(0), yAt(vals[1])
  for i = 1, n - 1 do
    local p0 = vals[i > 1 and i - 1 or i]
    local p1 = vals[i]
    local p2 = vals[i + 1]
    local p3 = vals[i + 2 <= n and i + 2 or i + 1]
    for s = 1, 4 do
      local t = s / 4
      local nx, ny = xAt(i - 1 + t), yAt(catmull(p0, p1, p2, p3, t))
      thickLine(round(px), round(py), round(nx), round(ny), col)
      px, py = nx, ny
    end
  end
end

-- Hinweis mit Symbol (Standort fehlt / wird geladen), mittig ab Oberkante y
local function notice(cx, y, kind, line1, line2)
  local r = 22
  local cy = y + r
  if kind == "loading" then
    for i = 0, 2 do draw.circle(cx, cy, r - i, color.BLACK, false) end
    for i = -1, 1 do draw.circle(cx + i * 12, cy, 3, color.BLACK, true) end
  else
    draw.circle(cx, cy, r, color.BLUE, true)
    draw.text(cx, cy + 7, "?", "large", color.WHITE, "center")
  end
  local y1 = cy + r + 32
  draw.text(cx, y1, line1, "large", color.BLACK, "center")
  if line2 and line2 ~= "" then draw.text(cx, y1 + 26, line2, "normal", color.BLACK, "center") end
end

local function aqColor(aqi)
  if aqi == 1 then return color.GREEN end
  if aqi == 2 or aqi == 3 then return color.YELLOW end
  if aqi == 4 or aqi == 5 then return color.RED end
  return color.BLACK
end

local function fmtTime(min)
  return string.format("%02d:%02d", min // 60, min % 60)
end

-- Werte für das Zusatzraster; fehlende Felder zeigen "–"
local function facts(w, ctx)
  local dash = "-" -- die Skript-Laufzeit ersetzt Gedankenstriche ohnehin durch "-"
  local vis = dash
  if w.visibility then
    vis = (w.visibility >= 10) and ">10.0 km" or string.format("%.1f km", w.visibility)
  end
  return {
    sunrise = w.sunrise and fmtTime(w.sunrise) or dash,
    sunset = w.sunset and fmtTime(w.sunset) or dash,
    wind = w.wind and string.format("%.0f km/h", w.wind) or dash,
    hum = string.format("%d %%", w.humidity or 0),
    press = w.pressure and string.format("%d hPa", w.pressure) or dash,
    uv = w.uv and string.format("%.1f", w.uv) or dash,
    vis = vis,
  }
end

local function factCell(x, y, label, value)
  draw.text(x, y, label, "small", color.BLACK)
  draw.text(x, y + 18, value, "normal", color.BLACK)
end

local function factGrid(w, ctx, x0, colGap, right, rowH, y0, aqDy)
  local f = facts(w, ctx)
  local colW = (W - right - x0 - colGap) // 2
  local x1 = x0 + colW + colGap
  factCell(x0, y0, tr("Sunrise", "Sonnenaufgang", ctx), f.sunrise)
  factCell(x1, y0, tr("Sunset", "Sonnenuntergang", ctx), f.sunset)
  factCell(x0, y0 + rowH, "Wind", f.wind)
  factCell(x1, y0 + rowH, tr("Humidity", "Feuchte", ctx), f.hum)
  factCell(x0, y0 + rowH * 2, tr("Pressure", "Luftdruck", ctx), f.press)
  factCell(x1, y0 + rowH * 2, tr("UV index", "UV-Index", ctx), f.uv)
  factCell(x0, y0 + rowH * 3, tr("Visibility", "Sichtweite", ctx), f.vis)
  draw.text(x1, y0 + rowH * 3, tr("Air quality", "Luftqualität", ctx), "small", color.BLACK)
  draw.text(x1, y0 + rowH * 3 + aqDy, w.aqi_label or "-", "small", aqColor(w.aqi))
end

local function boundsOf(hourly)
  local minV, maxV = hourly[1].temp, hourly[1].temp
  for i = 2, #hourly do
    if hourly[i].temp < minV then minV = hourly[i].temp end
    if hourly[i].temp > maxV then maxV = hourly[i].temp end
  end
  return minV, maxV
end

-- Stundenverlauf: Linie, Min/Max links, Symbol + Stunde je zweiter/vierter Stützstelle
local function hourlyBlock(w, y, sparkXL, sparkXR, sparkH, labelX, maxDy, iconSize, iconDy, hourDy)
  local n = #w.hourly
  local sw = W - sparkXL - sparkXR
  local temps = {}
  for i = 1, n do temps[i] = w.hourly[i].temp end
  sparkline(sparkXL, y, sw, sparkH, temps, color.ACCENT)
  local minV, maxV = boundsOf(w.hourly)
  draw.text(labelX, y + maxDy, string.format("%.0f°", maxV), "small", color.BLACK)
  draw.text(labelX, y + sparkH, string.format("%.0f°", minV), "small", color.BLACK)
  local step = n > 12 and 4 or 2
  local i = 0
  while i < n do
    local px = sparkXL + (i * (sw - 1)) // (n - 1)
    draw.weather_icon(w.hourly[i + 1].cond, px, y + sparkH + iconDy, iconSize)
    draw.text(px, y + sparkH + hourDy, string.format("%dh", w.hourly[i + 1].hour), "normal", color.BLACK, "center")
    i = i + step
  end
end

-- Mehrtagesvorschau: Wochentag, Symbol, Max/Min je Spalte
local function dailyBlock(w, ctx, y, cardX, wdDy, iconSize, iconDy, tempDy)
  local count = #w.daily
  local rowW = W - 2 * cardX
  local gap = 6
  local colW = (rowW - (count - 1) * gap) // count
  local short = (ctx.lang == "en") and SHORT_EN or SHORT_DE
  for i = 1, count do
    local d = w.daily[i]
    local cx = cardX + (i - 1) * (colW + gap) + colW // 2
    draw.text(cx, y + wdDy, short[((d.wday + 6) % 7) + 1], "normal", color.BLACK, "center")
    draw.weather_icon(d.cond, cx, y + iconDy, iconSize)
    draw.text(cx, y + tempDy, string.format("%.0f°/%.0f°", d.max, d.min), "normal", color.BLACK, "center")
  end
end

local function titleBlock(w, ctx, y, titleDy, dateDy)
  local loc = (w.location and w.location ~= "") and w.location or tr("Location", "Standort", ctx)
  draw.text(W // 2, y + titleDy, loc, "large", color.BLACK, "center")
  local lt = time.localtime()
  if lt then
    local days = (ctx.lang == "en") and DAYS_EN or DAYS_DE
    local months = (ctx.lang == "en") and MONTHS_EN or MONTHS_DE
    draw.text(W // 2, y + dateDy, string.format("%s, %s %d", days[lt.wday + 1], months[lt.month], lt.day), "normal", color.BLACK, "center")
  end
end

local function bigTemp(x, baseline, temp)
  local digits = string.format("%.0f", temp)
  draw.text(x, baseline, digits, "huge", color.BLACK)
  local ux = x + draw.measure(digits, "huge") + 4
  draw.text(ux, baseline, "°C", "large", color.BLACK)
end

local function feelsText(w, ctx)
  return string.format(tr("feels like %.0f °C", "gefühlt %.0f °C", ctx), w.feels)
end

-- Bento (cards) und Slate (flat): gleiche Positionen, Slate ohne Karten (dünne Trennlinien)
local function drawBigStyle(w, ctx, flat)
  local y = draw.top + 2
  titleBlock(w, ctx, y, 20, 38)
  y = y + 54
  local factY = y
  local factRowH = 140
  local cardW = W - 2 * CARD_MARGIN
  local function section(top, h)
    if flat then hline(CARD_MARGIN, top, cardW) else accentCard(CARD_MARGIN, top, cardW, h) end
  end
  section(factY - 10, factRowH + 20)
  draw.weather_icon(w.cond, 110, factY + factRowH // 2, 92)
  bigTemp(190, factY + 69, w.temp)
  draw.text(190, factY + 90, feelsText(w, ctx), "normal", color.BLACK)
  factGrid(w, ctx, 345, 20, 26, 34, factY + 6, 18)
  y = factY + factRowH + 26
  if #w.hourly >= 2 then
    section(y - 10, 102)
    hourlyBlock(w, y, 60, 28, 40, CARD_MARGIN + (flat and 8 or 18), 8, 18, 15, 34)
    y = y + 40 + 68
  end
  if #w.daily > 0 then
    section(y - 10, 106)
    dailyBlock(w, ctx, y, 26, 14, 34, 46, 78)
  else
    notice(W // 2, y, "loading", tr("Forecast is loading ...", "Vorhersage wird geladen ...", ctx))
  end
end

-- Nano (compact): engere Abstände, kleineres Symbol
local function drawCompact(w, ctx)
  local y = draw.top + 2
  titleBlock(w, ctx, y, 18, 34)
  y = y + 46
  local factY = y
  local factRowH = 108
  local cardW = W - 2 * CARD_MARGIN
  accentCard(CARD_MARGIN, factY - 8, cardW, factRowH + 14)
  draw.weather_icon(w.cond, 96, factY + factRowH // 2, 60)
  draw.text(160, factY + 50, string.format("%.0f °C", w.temp), "large", color.BLACK)
  draw.text(160, factY + 72, feelsText(w, ctx), "normal", color.BLACK)
  factGrid(w, ctx, 320, 16, 22, 26, factY + 4, 16)
  y = factY + factRowH + 16
  if #w.hourly >= 2 then
    accentCard(CARD_MARGIN, y - 8, cardW, 30 + 46)
    hourlyBlock(w, y, 56, 24, 30, CARD_MARGIN + 16, 6, 14, 12, 28)
    y = y + 30 + 52
  end
  if #w.daily > 0 then
    accentCard(CARD_MARGIN, y - 8, cardW, 84)
    dailyBlock(w, ctx, y, 22, 12, 26, 38, 64)
  else
    notice(W // 2, y, "loading", tr("Forecast is loading ...", "Vorhersage wird geladen ...", ctx))
  end
end

-- ---------------------------------------------------------------------------------------------
-- Dashboard-Widget "Wetter Außen" (on_widget). Optionsbits wie bisher im Studio: 1 = "gefühlt"/Feuchte und
-- Bereichsbalken, 2 = Vorhersage, 4 = Regen-Countdown. Stil (ctx.cfg.style): "compact" = ohne Wetterlage-Text
-- und ohne Tages-Symbole. Gestapelt von oben nach unten: AKTUELL, VORHERSAGE, REGEN, jeweils nur wenn Platz bleibt.
-- ---------------------------------------------------------------------------------------------
local COND_DE = {clear = "Klar", partly = "Teils bewölkt", cloudy = "Bewölkt", fog = "Nebel", drizzle = "Nieselregen",
                 rain = "Regen", snow = "Schnee", thunder = "Gewitter", unknown = "Wetter"}
local COND_EN = {clear = "Clear", partly = "Partly cloudy", cloudy = "Cloudy", fog = "Fog", drizzle = "Drizzle",
                 rain = "Rain", snow = "Snow", thunder = "Thunderstorm", unknown = "Weather"}

-- kürzt s, bis es in maxw Pixel passt
local function fit(s, font, maxw)
  if draw.measure(s, font) <= maxw then return s end
  while #s > 1 and draw.measure(s .. "...", font) > maxw do
    local n = #s
    repeat n = n - 1 until n <= 1 or (s:byte(n) < 128 or s:byte(n) >= 192) -- nicht mitten im UTF-8-Zeichen schneiden
    s = s:sub(1, n)
  end
  return s .. "..."
end

-- Textzeile an Mittelpunkt cx, auf [lo, hi] begrenzt
local function centered(cx, y, s, font, col, lo, hi)
  s = fit(s, font, hi - lo)
  draw.text(cx, y, s, font, col, "center")
end

-- CHANGELOG 506: Schriftgroesse des Dashboard-Widgets (ctx font = b.font: -1 klein, 0 normal, +1 gross) - eine Stufe auf der
-- Leiter small/normal, wie dashFontTier() der eingebauten Widgets (die Temperaturzahl "large" bleibt).
local function fnt(b, base)
  local t = b and b.font or 0
  if t < 0 and base == "normal" then return "small" end
  if t > 0 and base == "small" then return "normal" end
  return base
end

local function widgetCurrent(w, ctx, b, top, maxY, compact, extra)
  local areaH = maxY - top
  local cx = b.x + b.w // 2
  local temp = string.format("%.0f°C", w.temp)
  local feelsLine = string.format(tr("feels %.0f° · %d %%", "gefühlt %.0f° · %d %%", ctx), w.feels or w.temp, w.humidity or 0)
  if b.w < 190 then
    local cap = compact and 50 or 72
    local size = areaH - 46
    if size > cap then size = cap end
    if size < 26 then size = 26 end
    if size > b.w - 16 then size = b.w - 16 end
    local icy = top + 6 + size // 2
    draw.weather_icon(w.cond, cx, icy, size)
    local ty = icy + size // 2 + 26
    if ty > maxY - 4 then ty = maxY - 4 end
    centered(cx, ty, temp, "large", color.BLACK, b.x + 4, b.x + b.w - 4)
    local after = ty
    if extra and not compact and ty + 22 <= maxY then
      centered(cx, ty + 21, feelsLine, fnt(b, "small"), color.BLACK, b.x + 4, b.x + b.w - 4)
      after = ty + 21
    end
    local bottom = icy + size // 2
    return bottom > after and bottom or after
  end
  local size = areaH - 4
  local cap = compact and 60 or 88
  if size > cap then size = cap end
  if size < 30 then size = 30 end
  if b.w < 200 and size > 56 then size = 56 end
  local icy = top + areaH // 2
  draw.weather_icon(w.cond, b.x + 16 + size // 2, icy, size)
  local tx = b.x + 34 + size
  local withLabel = areaH >= 56 and not compact
  local ty
  if withLabel then
    local names = (ctx.lang == "en") and COND_EN or COND_DE
    draw.text(tx, top + 17, fit(names[w.cond] or names.unknown, fnt(b, "small"), b.x + b.w - tx - 6), fnt(b, "small"), color.BLACK)
    ty = top + 52
  else
    ty = top + areaH // 2 + 12
  end
  draw.text(tx, ty, temp, "large", color.BLACK)
  local after = ty
  if extra and withLabel and ty + 24 <= maxY then
    draw.text(tx, ty + 23, fit(feelsLine, fnt(b, "small"), b.x + b.w - tx - 6), fnt(b, "small"), color.BLACK)
    after = ty + 23
  end
  local bottom = icy + size // 2
  return bottom > after and bottom or after
end

-- Mehrtagesvorschau: je Tag eine Zeile (Wochentag, Symbol, Min, Bereichsbalken, Max)
local function widgetForecast(w, ctx, b, top, maxY, compact, withBarOpt)
  if #w.daily == 0 or maxY - top < 18 then return top end
  local withBar = withBarOpt and b.w >= 250
  local rowH = compact and 20 or 36
  local n = (maxY - top) // rowH
  if n > #w.daily then n = #w.daily end
  if n < 1 then n = 1 end
  local weekMin, weekMax = w.daily[1].min, w.daily[1].max
  for i = 2, n do
    if w.daily[i].min < weekMin then weekMin = w.daily[i].min end
    if w.daily[i].max > weekMax then weekMax = w.daily[i].max end
  end
  local range = (weekMax - weekMin) > 0.5 and (weekMax - weekMin) or 1
  local iconCol = compact and 0 or 44
  local short = (ctx.lang == "en") and SHORT_EN or SHORT_DE
  for i = 1, n do
    local d = w.daily[i]
    local cy = top + (i - 1) * rowH + rowH // 2
    draw.text(b.x + 12, cy + 5, short[((d.wday + 6) % 7) + 1], fnt(b, "small"), i == 1 and color.ACCENT or color.BLACK)
    if not compact then draw.weather_icon(d.cond, b.x + 56, cy, 24) end
    if withBar then
      local minX = b.x + 32 + iconCol
      draw.text(minX + 18, cy + 5, string.format("%.0f°", d.min), fnt(b, "small"), color.BLACK, "center")
      local bx = minX + 42
      local bw = b.x + b.w - 44 - bx
      draw.rect(bx, cy - 6, bw, 13, color.BLACK, false, 6)
      local s0 = math.floor((d.min - weekMin) / range * (bw - 6))
      local e0 = math.floor((d.max - weekMin) / range * (bw - 6))
      local fw = e0 - s0
      if fw < 8 then fw = 8 end
      if s0 + fw > bw - 6 then s0 = bw - 6 - fw end
      if s0 < 0 then s0 = 0 end
      draw.rect(bx + 3 + s0, cy - 3, fw, 7, color.ACCENT, true, 3)
      draw.text(b.x + b.w - 24, cy + 5, string.format("%.0f°", d.max), fnt(b, "small"), color.BLACK, "center")
    else
      centered(b.x + b.w - 44, cy + 5, string.format("%.0f° / %.0f°", d.max, d.min), fnt(b, "small"), color.BLACK, b.x + 32 + iconCol, b.x + b.w - 4)
    end
  end
  return top + n * rowH
end

-- Regen-Countdown: Kopfzeile + Balken für die nächsten zwei Stunden (15-Minuten-Schritte)
local function widgetRain(w, ctx, b, top, maxY)
  if not w.rain or #w.rain == 0 or maxY - top < 16 then return top end
  local first
  for i = 1, #w.rain do
    if w.rain[i].mm > 0.1 then first = i break end
  end
  local headline
  if not first then
    headline = tr("No rain in the next 2 h", "Kein Regen in den nächsten 2 Std.", ctx)
  else
    local mins = (w.rain[first].t - time.now()) // 60
    if mins <= 1 then headline = tr("Rain now", "Regen jetzt", ctx)
    else headline = string.format(tr("Rain in ~%d min", "Regen in ca. %d Min", ctx), mins) end
  end
  -- Umbruch an Wortgrenzen auf höchstens zwei Zeilen. CHANGELOG 508: Kopfzeile in "small" (7 pt) wie beim eingebauten Widget; mit
  -- groesserer Schrift, die nicht in zwei Zeilen passt, faellt sie auf "small" zurueck, statt mit "..." abgeschnitten zu werden.
  local function wrapLines(font)
    local ls, cur = {}, ""
    for word in headline:gmatch("%S+") do
      local try = (cur == "") and word or (cur .. " " .. word)
      if draw.measure(try, font) <= b.w - 24 or cur == "" then cur = try
      else ls[#ls + 1] = cur cur = word end
    end
    ls[#ls + 1] = cur
    return ls
  end
  local font = fnt(b, "small")
  local lines = wrapLines(font)
  if #lines > 2 and font ~= "small" then
    font = "small"
    lines = wrapLines(font)
  end
  while #lines > 2 do lines[2] = lines[2] .. " " .. table.remove(lines, 3) end
  local step = (font == "small") and 12 or 14
  local col = first and color.ACCENT or color.BLACK
  for i, l in ipairs(lines) do
    draw.text(b.x + 12, top + 13 + (i - 1) * step, fit(l, font, b.w - 24), font, col)
  end
  local headBottom = top + 13 + (#lines - 1) * step + 7
  local labelsH = (b.w >= 220) and 14 or 0
  local barsH = maxY - headBottom - labelsH
  local n = #w.rain
  if barsH < 12 or b.w < 140 or n < 2 then return headBottom end
  local marginX, gap = 12, 4
  local barW = (b.w - 2 * marginX - (n - 1) * gap) // n
  if barW < 4 then barW = 4 end
  local maxP = 1
  for i = 1, n do if w.rain[i].mm > maxP then maxP = w.rain[i].mm end end
  local baseY = headBottom + barsH
  for i = 1, n do
    local bx = b.x + marginX + (i - 1) * (barW + gap)
    local mm = w.rain[i].mm
    if mm > 0.05 then
      local bh = math.floor(math.min(mm / maxP, 1) * barsH)
      if bh < 5 then bh = 5 end
      draw.rect(bx, baseY - bh, barW, bh, color.ACCENT, true, 2)
    else
      draw.rect(bx, baseY - 4, barW, 4, color.BLACK, false, 2)
    end
  end
  if labelsH > 0 then
    draw.text(b.x + marginX, baseY + 12, tr("now", "jetzt", ctx), fnt(b, "small"), color.BLACK)
    local midX = b.x + marginX + (n // 2) * (barW + gap) + barW // 2
    draw.text(midX, baseY + 12, "+1h", fnt(b, "small"), color.BLACK, "center")
    local lastRight = b.x + marginX + (n - 1) * (barW + gap) + barW
    draw.text(lastRight - barW // 2, baseY + 12, "+2h", fnt(b, "small"), color.BLACK, "center")
  end
  return baseY + labelsH
end

function outdoor.on_widget(ctx, b)
  local w, why = weather.get()
  if not w then
    local msg = (why == "nolocation") and tr("Location not set", "Standort nicht eingerichtet", ctx) or tr("Loading ...", "Wird geladen ...", ctx)
    draw.text(b.x + b.w // 2, b.y + b.h // 2, fit(msg, "small", b.w - 16), "small", color.BLACK, "center")
    return
  end
  local opt = ctx.cfg.opt or 0
  local extra = (opt & 1) ~= 0
  local showForecast = (opt & 2) ~= 0
  local showRain = (opt & 4) ~= 0 and w.rain ~= nil and #w.rain > 0
  local compact = (ctx.cfg.style == "compact")
  local top = b.y
  local maxY = b.y + b.h - 4
  local rainH = showRain and (compact and 40 or 56) or 0
  local belowMax = showRain and (maxY - rainH - 14) or maxY
  if belowMax < top + 20 then belowMax = maxY end
  local blockMax = belowMax
  if showForecast then
    local cur = compact and 78 or 108
    blockMax = top + cur
    if blockMax > belowMax then blockMax = belowMax end
  end
  local y = widgetCurrent(w, ctx, b, top, blockMax, compact, extra)
  if showForecast and belowMax - (y + 14) >= 18 then
    hline(b.x + 12, y + 7, b.w - 24)
    y = widgetForecast(w, ctx, b, y + 14, belowMax, compact, extra)
  end
  if showRain and maxY - (y + 14) >= 18 then
    hline(b.x + 12, y + 7, b.w - 24)
    widgetRain(w, ctx, b, y + 14, maxY)
  end
end

function outdoor.on_draw(ctx, page)
  draw.clear(color.WHITE)
  local w, why = weather.get()
  if not w then
    local y = draw.top + 16
    if why == "nolocation" then
      notice(W // 2, y, "setup", tr("Location not set.", "Standort nicht eingerichtet.", ctx), tr("Studio -> Apps -> Weather", "Studio -> Apps -> Wetter", ctx))
    else
      notice(W // 2, y, "loading", tr("Loading ...", "Wird geladen ...", ctx))
    end
    return true
  end
  local style = ctx.cfg.style
  if style == "compact" then
    drawCompact(w, ctx)
  else
    drawBigStyle(w, ctx, style == "flat")
  end
  return true
end

end

-- ====================================================================================== Seiten/Widget Innen + Netzwerk
do

local W = 800
local CARD_MARGIN = 14
local CARD_RADIUS = 8
local HISTORY_DAYS = 1 -- lokal ist der Verlauf fest auf 1 Tag begrenzt

local TEMP_COLOR = color.BLUE   -- feste Identitätsfarben je Sensor
local CO2_COLOR = color.BLACK
local HUM_COLOR = color.BLUE

local function tr(en, de, ctx) if ctx.lang == "en" then return en end return de end
local function round(v) if v >= 0 then return math.floor(v + 0.5) end return -math.floor(-v + 0.5) end

local function fit(s, font, maxw)
  if draw.measure(s, font) <= maxw then return s end
  while #s > 1 and draw.measure(s .. "...", font) > maxw do s = s:sub(1, #s - 1) end
  return s .. "..."
end

-- ---------------------------------------------------------------------------------------------- Bausteine

local function accentCard(x, y, w, h, accent)
  draw.rect(x, y, w, h, color.WHITE, true, CARD_RADIUS)
  draw.rect(x, y, w, h, color.BLACK, false, CARD_RADIUS)
  draw.rect(x + 6, y + 6, 5, h - 12, accent or color.ACCENT, true, 2)
end

local function hline(x, y, w, col) draw.rect(x, y, w, 1, col or color.BLACK, true) end
local function vline(x, y, h) draw.rect(x, y, 1, h, color.BLACK, true) end

local function thickLine(x0, y0, x1, y1, col)
  draw.line(x0, y0, x1, y1, col)
  draw.line(x0, y0 + 1, x1, y1 + 1, col)
  draw.line(x0 + 1, y0, x1 + 1, y1, col)
  draw.line(x0, y0 - 1, x1, y1 - 1, col)
  draw.line(x0 - 1, y0, x1 - 1, y1, col)
end

local function catmull(p0, p1, p2, p3, t)
  local t2, t3 = t * t, t * t * t
  return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end

-- Weich geglättete Linie (Catmull-Rom, 4 Schritte je Abschnitt) in das Feld (x, y, w, h); [lo, hi] ist die Wertespanne.
local function curve(vals, n, xAt, yAt, col)
  local px, py = xAt(0), yAt(vals[1])
  for i = 1, n - 1 do
    local p0 = vals[i > 1 and i - 1 or i]
    local p1 = vals[i]
    local p2 = vals[i + 1]
    local p3 = vals[i + 2 <= n and i + 2 or i + 1]
    for s = 1, 4 do
      local t = s / 4
      local nx, ny = xAt(i - 1 + t), yAt(catmull(p0, p1, p2, p3, t))
      thickLine(round(px), round(py), round(nx), round(ny), col)
      px, py = nx, ny
    end
  end
end

local function fmtNum(v, decimals)
  if decimals == 0 then return string.format("%d", round(v)) end
  return string.format("%.1f", v)
end

-- Kleiner Verlauf mit Min/Max-Beschriftung links
local function sparkline(x, y, w, h, vals, n, col, axis, decimals)
  if n < 2 then return end
  local minV, maxV = vals[1], vals[1]
  for i = 2, n do
    if vals[i] < minV then minV = vals[i] end
    if vals[i] > maxV then maxV = vals[i] end
  end
  local range = maxV - minV
  if range < 0.5 then range = 0.5 end
  local lineX, lineW = x, w
  if axis then
    draw.text(x, y + 7, fmtNum(maxV, decimals), "small", color.BLACK)
    draw.text(x, y + h - 1, fmtNum(minV, decimals), "small", color.BLACK)
    lineX, lineW = x + 26, w - 26
  end
  curve(vals, n,
    function(idx) return lineX + idx * (lineW - 1) / (n - 1) end,
    function(v) return y + h - 1 - (v - minV) / range * (h - 1) end, col)
end

-- Lokale Uhrzeit (Minuten seit Mitternacht) eines Zeitstempels: Versatz aus time.localtime() gegen time.now()
local function localOffset()
  local lt = time.localtime()
  if not lt then return 0 end
  local sod = lt.hour * 3600 + lt.min * 60 + lt.sec
  return (sod - (time.now() % 86400)) % 86400
end

-- Großer Achsen-Graph: 5 Gitterlinien mit Werten, Zeitbeschriftung unten
local function axisChart(x, y, w, h, vals, epochs, n, col, decimals)
  if n < 2 then return end
  local minV, maxV = vals[1], vals[1]
  for i = 2, n do
    if vals[i] < minV then minV = vals[i] end
    if vals[i] > maxV then maxV = vals[i] end
  end
  local range = maxV - minV
  if range < 1 then range = 1 end
  minV = minV - range * 0.12
  maxV = maxV + range * 0.12
  range = maxV - minV
  local yAxisW, xAxisH, xRight = 44, 18, 24
  local plotX = x + yAxisW
  local plotW = w - yAxisW - xRight
  local plotH = h - xAxisH
  for i = 0, 4 do
    local v = maxV - (range * i) / 4
    local ly = y + (i * (plotH - 1)) // 4
    hline(plotX, ly, plotW)
    draw.text(x, ly + 4, fmtNum(v, decimals), "small", color.BLACK)
  end
  curve(vals, n,
    function(idx) return plotX + idx * (plotW - 1) / (n - 1) end,
    function(v) return y + plotH - 1 - (v - minV) / range * (plotH - 1) end, col)
  local off = localOffset()
  local labels = n < 5 and n or 5
  for i = 0, labels - 1 do
    local idx = labels > 1 and ((n - 1) * i) // (labels - 1) or 0
    local sec = ((epochs[idx + 1] or 0) + off) % 86400
    local lbl = string.format("%02d:%02d", sec // 3600, (sec % 3600) // 60)
    local lx = plotX + (idx * (plotW - 1)) // (n - 1)
    draw.text(lx, y + h - 2, lbl, "small", color.BLACK, "center")
  end
end

-- Symbole aus Grundformen
local function thermometerIcon(x, y, col, s)
  s = s or 1
  local sw, sh, sr = round(6 * s), round(13 * s), round(3 * s)
  draw.rect(x + round(5 * s), y, sw, sh, col, true, sr)
  draw.circle(x + round(8 * s), y + round(14 * s), round(6 * s), col, true)
  draw.circle(x + round(8 * s), y + round(14 * s), round(3 * s), color.WHITE, true)
end

local function co2Icon(x, y, col, s)
  s = s or 1
  draw.circle(x + round(4 * s), y + round(9 * s), round(4 * s), col, true)
  draw.circle(x + round(12 * s), y + round(5 * s), round(3 * s), col, true)
  draw.circle(x + round(12 * s), y + round(13 * s), round(3 * s), col, true)
end

local function dropletIcon(x, y, col, s)
  s = s or 1
  draw.triangle(x + round(7 * s), y, x + round(1 * s), y + round(11 * s), x + round(13 * s), y + round(11 * s), col, true)
  draw.circle(x + round(7 * s), y + round(11 * s), round(6 * s), col, true)
end

local ICONS = { temp = thermometerIcon, co2 = co2Icon, hum = dropletIcon }

-- Abgerundete Pille mit Fettschrift (Breite nach Text, mindestens 280)
local function pillBadge(text, cx, y, fill)
  local pillW = draw.measure(text, "large") + 48
  if pillW < 280 then pillW = 280 end
  local maxW = 2 * math.min(cx, W - cx) - 16
  if pillW > maxW then pillW = maxW end
  draw.rect(cx - pillW // 2, y, pillW, 48, fill, true, 20)
  draw.text(cx, y + 48 - 14, text, "large", color.WHITE, "center")
  return y + 48
end

-- Warnbanner mit bis zu zwei Zeilen
local function warningBanner(cx, y, width, text, col)
  local lines, cur = {}, ""
  for word in text:gmatch("%S+") do
    local try = (cur == "") and word or (cur .. " " .. word)
    if draw.measure(try, "small") <= width - 30 or cur == "" then cur = try
    else lines[#lines + 1] = cur cur = word end
  end
  lines[#lines + 1] = cur
  while #lines > 2 do lines[2] = lines[2] .. " " .. table.remove(lines, 3) end
  local bannerH = 14 + #lines * 16
  draw.rect(cx - width // 2, y, width, bannerH, col, true, 8)
  for i, l in ipairs(lines) do draw.text(cx, y + 20 + (i - 1) * 16, l, "small", color.WHITE, "center") end
  return y + bannerH
end

-- Hinweis mit großem Symbol (Seiten-Ebene)
local function notice(cx, y, kind, line1)
  local r = 22
  local cy = y + r
  draw.rect(cx - r, cy - r, 2 * r, 2 * r, color.ACCENT, true, r)
  if kind == "loading" then
    for i = -1, 1 do draw.circle(cx + i * 12, cy, 3, color.WHITE, true) end
  else
    draw.text(cx, cy + 7, "-", "large", color.WHITE, "center")
  end
  draw.text(cx, cy + r + 32, line1, "large", color.BLACK, "center")
end

-- Kleiner Hinweis (Kreis + eine Zeile)
local function noticeCompact(cx, y, kind, line1)
  local r = 10
  local textW = draw.measure(line1, "normal")
  local clusterW = textW + 2 * r + 10
  local circleCx = cx - clusterW // 2 + r
  local textCx = circleCx + r + 5 + textW // 2
  draw.circle(circleCx, y, r, color.ACCENT, true)
  if kind == "loading" then
    for i = -1, 1 do draw.circle(circleCx + i * 5, y, 1, color.WHITE, true) end
  else
    draw.text(circleCx, y + 4, "-", "normal", color.WHITE, "center")
  end
  draw.text(textCx, y + 4, line1, "normal", color.BLACK, "center")
end

-- Akku-Symbol; pct = nil -> durchgestrichen
local function batteryIcon(x, y, col, pct)
  local bodyW, bodyH = 22, 12
  draw.rect(x, y, bodyW, bodyH, col, false, 2)
  draw.rect(x + bodyW, y + 3, 3, 6, col, true)
  if not pct then
    draw.line(x - 2, y - 2, x + bodyW + 5, y + bodyH + 2, col)
    draw.line(x - 2, y - 1, x + bodyW + 5, y + bodyH + 3, col)
    return
  end
  if pct < 0 then pct = 0 end
  if pct > 100 then pct = 100 end
  local fillW = round((bodyW - 4) * pct / 100)
  if fillW > 0 then draw.rect(x + 2, y + 2, fillW, bodyH - 4, pct < 20 and color.RED or col, true) end
end

local ROOMS_DE = { wohnzimmer = "Wohnzimmer", flur = "Flur", kueche = "Küche", bad = "Bad", schlafzimmer = "Schlafzimmer" }
local ROOMS_EN = { wohnzimmer = "Living room", flur = "Hallway", kueche = "Kitchen", bad = "Bathroom", schlafzimmer = "Bedroom" }
local function roomName(id, ctx)
  local map = (ctx.lang == "en") and ROOMS_EN or ROOMS_DE
  return map[id] or id
end

local function relTime(epoch, ctx)
  if not epoch or epoch <= 0 then return "" end
  local diff = time.now() - epoch
  if diff < 0 then diff = 0 end
  local min = diff // 60
  if min < 1 then return tr("just now", "gerade eben", ctx) end
  if min < 60 then return string.format(tr("%d min ago", "vor %d Min.", ctx), min) end
  if min < 1440 then return string.format(tr("%d h ago", "vor %d Std.", ctx), min // 60) end
  return string.format(tr("%d d ago", "vor %d Tagen", ctx), min // 1440)
end

-- ---------------------------------------------------------------------------------------------- Ampeln

local function co2Zone(s) -- 0 rot, 1 gelb, 2 grün
  if s.co2 < 800 then return 2 end
  if s.co2 < s.co2_warn_ppm then return 1 end
  return 0
end
local CO2_COLORS = { [0] = color.RED, [1] = color.YELLOW, [2] = color.GREEN }
local function humZone(s) -- 0 gelb (trocken), 1 grün, 2 blau (feucht)
  if s.humidity < s.hum_low then return 0 end
  if s.humidity > s.hum_high then return 2 end
  return 1
end
local HUM_COLORS = { [0] = color.YELLOW, [1] = color.GREEN, [2] = color.BLUE }

local function histTitle(hours, ctx)
  if hours < 48 then return string.format(tr("Trend (%dh)", "Verlauf (%d Std.)", ctx), hours) end
  return string.format(tr("Trend (%d days)", "Verlauf (%d Tage)", ctx), hours // 24)
end

-- Verlauf auf den eingestellten Zeitraum (6/12/24 Stunden) kürzen
local RANGE_HOURS = 24
local function trimRange(h)
  if RANGE_HOURS >= 24 or h.n < 2 then return h end
  local cutoff = h.time[h.n] - RANGE_HOURS * 3600
  local first = 1
  while first < h.n and h.time[first] < cutoff do first = first + 1 end
  if first == 1 then return h end
  local out = { temp = {}, humidity = {}, co2 = {}, time = {}, n = h.n - first + 1 }
  for i = first, h.n do
    local j = i - first + 1
    out.temp[j], out.humidity[j], out.co2[j], out.time[j] = h.temp[i], h.humidity[i], h.co2[i], h.time[i]
  end
  out.hours = math.min(h.hours, RANGE_HOURS)
  return out
end

local function loadHistory(peer)
  local h = sensor.history(peer, HISTORY_DAYS)
  if h and h.n >= 2 then
    h = trimRange(h)
    if h.n >= 2 then return h end
  end
  return nil
end

-- ---------------------------------------------------------------------------------------------- Seite Innen

local function statCell(x, y, w, h, kind, idColor, label, value, mode, statusText, statusColor)
  draw.rect(x, y, w, h, color.BLACK, false, CARD_RADIUS)
  local iconX, iconY = x + 10, y + 8
  ICONS[kind](iconX, iconY, idColor, 1)
  draw.text(iconX + 22, iconY + 13, label, "small", idColor)
  draw.text(x + 10, y + 56, value, "large", color.BLACK)
  if mode == 1 then
    local pillH, pillY, pillW = 22, y + h - 22 - 8, w - 20
    draw.rect(x + 10, pillY, pillW, pillH, statusColor, true, 6)
    draw.text(x + 10 + pillW // 2, pillY + pillH - 6, statusText, "small", color.WHITE, "center")
  elseif mode == 2 then
    draw.text(x + w // 2, y + h - 10, statusText, "small", idColor, "center")
  end
end

local function average(vals, n)
  if n <= 0 then return 0 end
  local sum = 0
  for i = 1, n do sum = sum + vals[i] end
  return sum / n
end

local function co2Status(s, ctx)
  local z = co2Zone(s)
  if z == 2 then return tr("very good air", "sehr gute Luft", ctx) end
  if z == 1 then return tr("air okay", "Luft okay", ctx) end
  return tr("please ventilate", "bitte lüften", ctx)
end
local function humStatus(s, ctx)
  local z = humZone(s)
  if z == 0 then return tr("too dry", "zu trocken", ctx) end
  if z == 2 then return tr("too humid", "zu feucht", ctx) end
  return tr("optimal", "optimal", ctx)
end

local function pageCards(s, ctx)
  local top = draw.top
  local cardW = W - 2 * CARD_MARGIN
  local h = loadHistory(0)
  local statGap = 12
  local statW = (cardW - 2 * statGap) // 3
  local statH = 90
  local statY = top + 6
  local x1 = CARD_MARGIN
  local x2 = x1 + statW + statGap
  local x3 = x2 + statW + statGap
  local tempStatus = s.temp < 18 and tr("cool", "kühl", ctx) or (s.temp > 24 and tr("warm", "warm", ctx) or tr("comfortable", "angenehm", ctx))
  statCell(x1, statY, statW, statH, "temp", TEMP_COLOR, tr("Temperature", "Temperatur", ctx),
    string.format(tr("%.1f°C", "%.1f °C", ctx), s.temp), 2, tempStatus, color.BLACK)
  statCell(x2, statY, statW, statH, "co2", CO2_COLOR, "CO2", string.format("%d ppm", s.co2),
    s.co2_warn and 1 or 0, co2Status(s, ctx), CO2_COLORS[co2Zone(s)])
  statCell(x3, statY, statW, statH, "hum", HUM_COLOR, tr("Humidity", "Luftfeuchtigkeit", ctx), string.format("%.0f %%", s.humidity),
    s.hum_warn and 1 or 0, humStatus(s, ctx), HUM_COLORS[humZone(s)])

  local divider1 = statY + statH + 10
  hline(CARD_MARGIN, divider1, cardW)
  if not h then
    noticeCompact(W // 2, divider1 + 50, "empty", tr("Not enough trend data yet", "Noch nicht genug Verlaufsdaten", ctx))
    return
  end

  local focus = ctx.cfg.focus or "co2"
  local series, fcol, fname, fdec, fval = h.co2, CO2_COLOR, "CO2", 0, string.format("%d ppm", s.co2)
  if focus == "temperature" then
    series, fcol, fname, fdec, fval = h.temp, TEMP_COLOR, tr("TEMPERATURE", "TEMPERATUR", ctx), 1, string.format("%.1f °C", s.temp)
  elseif focus == "humidity" then
    series, fcol, fname, fdec, fval = h.humidity, HUM_COLOR, tr("HUMIDITY", "LUFTFEUCHTIGKEIT", ctx), 0, string.format("%.0f %%", s.humidity)
  end
  local focusY = divider1 + 14
  local title
  if h.hours < 48 then title = string.format(tr("%s TREND - LAST %dH", "%s-VERLAUF - LETZTE %d STD.", ctx), fname, h.hours)
  else title = string.format(tr("%s TREND - LAST %d DAYS", "%s-VERLAUF - LETZTE %d TAGE", ctx), fname, h.hours // 24) end
  draw.text(CARD_MARGIN, focusY + 14, title, "normal", color.BLACK)
  draw.text(CARD_MARGIN + cardW, focusY + 14, fval, "normal", color.BLACK, "right")
  local chartY = focusY + 26
  local chartH = 140
  axisChart(CARD_MARGIN, chartY, cardW, chartH, series, h.time, h.n, fcol, fdec)
  local divider2 = chartY + chartH + 12

  local showT = focus ~= "temperature" and ctx.cfg.showTemp ~= false
  local showH = focus ~= "humidity" and ctx.cfg.showHum ~= false
  local showC = focus ~= "co2" and ctx.cfg.showCo2 ~= false
  local count = (showT and 1 or 0) + (showH and 1 or 0) + (showC and 1 or 0)
  if count == 0 then return end
  hline(CARD_MARGIN, divider2, cardW)
  local miniGap = 12
  local miniW = count == 1 and cardW or (cardW - miniGap) // 2
  local miniH = 100
  local miniY = divider2 + 14
  local sx = CARD_MARGIN
  local function secondary(label, value, col, vals, dec)
    vline(sx, miniY, miniH)
    draw.text(sx + 14, miniY + 18, label, "normal", color.BLACK)
    draw.text(sx + 14, miniY + 50, value, "large", color.BLACK)
    sparkline(sx + 14, miniY + 60, miniW - 28, miniH - 70, vals, h.n, col, true, dec)
    sx = sx + miniW + miniGap
  end
  if showT then secondary(tr("Temperature", "Temperatur", ctx), string.format(tr("Ø %.1f°C", "Ø %.1f °C", ctx), average(h.temp, h.n)), TEMP_COLOR, h.temp, 1) end
  if showH then secondary(tr("Humidity", "Luftfeuchtigkeit", ctx), string.format("Ø %.0f %%", average(h.humidity, h.n)), HUM_COLOR, h.humidity, 0) end
  if showC then secondary("CO2", string.format("Ø %.0f ppm", average(h.co2, h.n)), CO2_COLOR, h.co2, 0) end
  vline(sx - miniGap, miniY, miniH)
end

-- gemeinsame Warnbanner der Stile Slate/Nano; liefert die neue y-Position
local function banners(s, ctx, cx, y, width, step)
  if s.co2_warn and s.co2 >= s.co2_warn_ppm then
    y = warningBanner(cx, y, width, tr("CO2 too high - please ventilate!", "CO2 zu hoch - bitte lüften!", ctx), color.RED) + step
  end
  if s.hum_warn and s.humidity < s.hum_low then
    y = warningBanner(cx, y, width, tr("Air too dry - humidifier recommended", "Luft zu trocken - Luftbefeuchter empfohlen", ctx), color.YELLOW) + step
  elseif s.hum_warn and s.humidity > s.hum_high then
    y = warningBanner(cx, y, width, tr("Air too humid - please ventilate", "Luft zu feucht - bitte lüften", ctx), color.BLUE) + step
  end
  return y
end

local function threeSparks(h, ctx, x0, totalW, y, graphH, titleY)
  local colGap = 20
  local colW = (totalW - 2 * colGap) // 3
  local c1 = x0
  local c2 = c1 + colW + colGap
  local c3 = c2 + colW + colGap
  draw.text(c1 + colW // 2, titleY, tr("Temperature", "Temperatur", ctx), "normal", color.BLACK, "center")
  draw.text(c2 + colW // 2, titleY, tr("Humidity", "Feuchte", ctx), "normal", color.BLACK, "center")
  draw.text(c3 + colW // 2, titleY, "CO2", "normal", color.BLACK, "center")
  sparkline(c1, y, colW, graphH, h.temp, h.n, TEMP_COLOR, true, 1)
  sparkline(c2, y, colW, graphH, h.humidity, h.n, HUM_COLOR, true, 0)
  sparkline(c3, y, colW, graphH, h.co2, h.n, CO2_COLOR, true, 0)
end

local function pageCompact(s, ctx)
  local top = draw.top
  local cx = W // 2
  local cardW = W - 2 * CARD_MARGIN
  local valuesY = top + 6
  local valuesCardH = 200
  accentCard(CARD_MARGIN, valuesY, cardW, valuesCardH)
  local contentY = valuesY + 16
  local zc = s.co2 < 800 and color.GREEN or (s.co2 < s.co2_warn_ppm and color.YELLOW or color.RED)
  pillBadge(string.format("%d ppm CO2", s.co2), cx, contentY, zc)
  draw.text(cx, contentY + 58, string.format(tr("%.1f°C", "%.1f °C", ctx), s.temp), "normal", color.BLACK, "center")
  draw.text(cx, contentY + 80, string.format(tr("%.0f%% humidity", "%.0f %% Feuchte", ctx), s.humidity), "normal", color.BLACK, "center")
  -- Nano setzt die beiden Banner an feste Positionen (CO2 bei +98, Feuchte 38 px darunter)
  local bannerY = contentY + 98
  if s.co2_warn and s.co2 >= s.co2_warn_ppm then
    warningBanner(cx, bannerY, cardW - 60, tr("CO2 too high - please ventilate!", "CO2 zu hoch - bitte lüften!", ctx), color.RED)
  end
  if s.hum_warn and s.humidity < s.hum_low then
    warningBanner(cx, bannerY + 38, cardW - 60, tr("Air too dry - humidifier recommended", "Luft zu trocken - Luftbefeuchter empfohlen", ctx), color.YELLOW)
  elseif s.hum_warn and s.humidity > s.hum_high then
    warningBanner(cx, bannerY + 38, cardW - 60, tr("Air too humid - please ventilate", "Luft zu feucht - bitte lüften", ctx), color.BLUE)
  end
  local h = loadHistory(0)
  if h then
    local histY = valuesY + valuesCardH + 10
    accentCard(CARD_MARGIN, histY, cardW, 118)
    draw.text(cx, histY + 20, histTitle(h.hours, ctx), "normal", color.BLACK, "center")
    local graphY = histY + 34
    local colGap = 20
    local colW = (cardW - 40 - 2 * colGap) // 3
    local c1 = CARD_MARGIN + 20
    local c2 = c1 + colW + colGap
    local c3 = c2 + colW + colGap
    draw.text(c1 + colW // 2, graphY + 10, tr("Temperature", "Temperatur", ctx), "normal", color.BLACK, "center")
    sparkline(c1, graphY + 16, colW, 56, h.temp, h.n, TEMP_COLOR, true, 1)
    draw.text(c2 + colW // 2, graphY + 10, tr("Humidity", "Feuchte", ctx), "normal", color.BLACK, "center")
    sparkline(c2, graphY + 16, colW, 56, h.humidity, h.n, HUM_COLOR, true, 0)
    draw.text(c3 + colW // 2, graphY + 10, "CO2", "normal", color.BLACK, "center")
    sparkline(c3, graphY + 16, colW, 56, h.co2, h.n, CO2_COLOR, true, 0)
  end
end

local function pageFlat(s, ctx)
  local top = draw.top
  local cx = W // 2
  local lineY = top + 6 + 25
  local zc = s.co2 < 800 and color.GREEN or (s.co2 < s.co2_warn_ppm and color.YELLOW or color.RED)
  lineY = pillBadge(string.format("%d ppm CO2", s.co2), cx, lineY, zc) + 30
  if s.co2_warn and s.co2 >= s.co2_warn_ppm then
    lineY = warningBanner(cx, lineY, W - 80, tr("CO2 too high - please ventilate!", "CO2 zu hoch - bitte lüften!", ctx), color.RED) + 16
  end
  draw.text(cx, lineY, string.format(tr("%.1f°C", "%.1f °C", ctx), s.temp), "normal", color.BLACK, "center")
  lineY = lineY + 26
  draw.text(cx, lineY, string.format(tr("%.0f%% humidity", "%.0f %% Feuchte", ctx), s.humidity), "normal", color.BLACK, "center")
  lineY = lineY + 26
  if s.hum_warn and s.humidity < s.hum_low then
    lineY = warningBanner(cx, lineY, W - 80, tr("Air too dry - humidifier recommended", "Luft zu trocken - Luftbefeuchter empfohlen", ctx), color.YELLOW) + 16
  elseif s.hum_warn and s.humidity > s.hum_high then
    lineY = warningBanner(cx, lineY, W - 80, tr("Air too humid - please ventilate", "Luft zu feucht - bitte lüften", ctx), color.BLUE) + 16
  end
  local h = loadHistory(0)
  if h then
    lineY = lineY + 10
    hline(40, lineY, W - 80)
    lineY = lineY + 22
    draw.text(cx, lineY, histTitle(h.hours, ctx), "normal", color.BLACK, "center")
    lineY = lineY + 18
    local graphY = lineY
    local colGap = 20
    local colW = (W - 80 - 2 * colGap) // 3
    local c1 = 40
    local c2 = c1 + colW + colGap
    local c3 = c2 + colW + colGap
    draw.text(c1 + colW // 2, graphY + 10, tr("Temperature", "Temperatur", ctx), "normal", color.BLACK, "center")
    sparkline(c1, graphY + 16, colW, 70, h.temp, h.n, TEMP_COLOR, true, 1)
    draw.text(c2 + colW // 2, graphY + 10, tr("Humidity", "Feuchte", ctx), "normal", color.BLACK, "center")
    sparkline(c2, graphY + 16, colW, 70, h.humidity, h.n, HUM_COLOR, true, 0)
    draw.text(c3 + colW // 2, graphY + 10, "CO2", "normal", color.BLACK, "center")
    sparkline(c3, graphY + 16, colW, 70, h.co2, h.n, CO2_COLOR, true, 0)
  end
end

-- ---------------------------------------------------------------------------------------------- Seite Netzwerk

local function pageNetwork(ctx)
  local top = draw.top
  local cx = W // 2
  local compact = (ctx.cfg.style == "compact")
  local s = sensor.get()
  local tiles = {}
  local nowE = time.now()
  local warnPpm, warnOn = 1200, false
  if s then warnPpm, warnOn = s.co2_warn_ppm, s.co2_warn end
  local selfHist = loadHistory(0)
  local room = s and s.room or ""
  tiles[1] = {
    room = room, isSelf = true, valid = s ~= nil,
    co2 = s and s.co2 or 0, temp = s and s.temp or 0, hum = s and s.humidity or 0,
    hist = selfHist, seen = nowE, battery = s and s.battery or nil,
  }
  local peers = sensor.peers()
  for i, p in ipairs(peers) do
    tiles[#tiles + 1] = {
      room = p.room, isSelf = false, valid = p.valid, co2 = p.co2, temp = p.temp, hum = p.humidity,
      hist = loadHistory(i), seen = p.seen, battery = p.battery,
    }
  end
  if #tiles <= 1 then
    notice(cx, top + 20, "empty", tr("No other InkBoard found on the network.", "Kein anderes InkBoard im Netzwerk gefunden.", ctx))
    return
  end

  -- Ranking über alle gültigen Kacheln (erst ab zwei gültigen)
  local warmest, coldest, highest = nil, nil, nil
  local valid, sumT, sumH = 0, 0, 0
  for i, t in ipairs(tiles) do
    if t.valid then
      valid = valid + 1
      sumT = sumT + t.temp
      sumH = sumH + t.hum
      if not warmest or t.temp > tiles[warmest].temp then warmest = i end
      if not coldest or t.temp < tiles[coldest].temp then coldest = i end
      if not highest or t.co2 > tiles[highest].co2 then highest = i end
    end
  end
  local showRanking = valid >= 2

  local cardW = W - 2 * CARD_MARGIN
  local gridGap = 12
  local tileW = (cardW - gridGap) // 2
  local headerOffset = 0
  if valid >= 1 then
    draw.text(cx, top + 14, string.format(tr("Avg %.1f°C · %.0f%% humidity across %d rooms", "Ø %.1f°C · %.0f%% Feuchte über %d Räume", ctx),
      sumT / valid, sumH / valid, valid), "normal", color.BLACK, "center")
    headerOffset = 24
  end
  local tileH = (compact and 108 or 124) + 18
  local col1X = CARD_MARGIN
  local col2X = CARD_MARGIN + tileW + gridGap

  for i, t in ipairs(tiles) do
    local row, col = (i - 1) // 2, (i - 1) % 2
    local tx = (col == 0) and col1X or col2X
    local ty = top + 6 + headerOffset + row * (tileH + gridGap)
    local alarm = warnOn and t.valid and t.co2 >= warnPpm
    accentCard(tx, ty, tileW, tileH, alarm and color.RED or color.ACCENT)
    local title = roomName(t.room, ctx)
    if t.isSelf then title = title .. " (" .. tr("this device", "dieses Gerät", ctx) .. ")" end
    draw.text(tx + 16, ty + 20, title, "normal", color.BLACK)
    if not t.valid then
      noticeCompact(tx + tileW // 2, ty + tileH // 2 + 2, "loading", tr("No reading yet", "Noch keine Messung", ctx))
    else
      draw.text(tx + 16, ty + 42, string.format("%.1f°C · %.0f%% · %d ppm", t.temp, t.hum, t.co2), "normal", alarm and color.RED or color.BLACK)
      local statusY = ty + 58
      local battX, battY = tx + tileW - 16 - 25, ty + 50
      local rel, relCol
      if alarm and t.hist and t.hist.n >= 1 then
        -- seit wann liegt der Raum ununterbrochen über der Schwelle?
        local n = t.hist.n
        local since = t.hist.time[n]
        local ranOut = true
        for p = n, 1, -1 do
          if t.hist.co2[p] < warnPpm then ranOut = false break end
          since = t.hist.time[p]
        end
        local durMin = (nowE > since) and ((nowE - since) // 60) or 0
        if durMin < 1 then rel = tr("since just now", "seit gerade eben", ctx)
        elseif durMin < 60 then
          rel = string.format(ranOut and tr("for %d+ min", "seit mind. %d Min.", ctx) or tr("for %d min", "seit %d Min.", ctx), durMin)
        else
          rel = string.format(ranOut and tr("for %d+ h", "seit mind. %d Std.", ctx) or tr("for %d h", "seit %d Std.", ctx), durMin // 60)
        end
        relCol = color.RED
      else
        rel = relTime(t.seen, ctx)
        relCol = color.BLACK
      end
      draw.text(tx + 16, statusY, rel, "small", relCol)
      if showRanking then
        local badge, bcol
        if i == highest then badge, bcol = "CO2 max", CO2_COLOR
        elseif i == warmest then badge, bcol = tr("warmest", "wärmste", ctx), TEMP_COLOR
        elseif i == coldest then badge, bcol = tr("coldest", "kälteste", ctx), color.BLUE end
        if badge then draw.text(battX - 6, statusY, badge, "small", bcol, "right") end
      end
      batteryIcon(battX, battY, color.BLACK, t.battery)
      if t.hist and t.hist.n >= 2 then
        local graphX, graphY = tx + 16, ty + 68
        local graphW = tileW - 32
        local colGap = 6
        local colW = (graphW - 2 * colGap) // 3
        local g1 = graphX
        local g2 = g1 + colW + colGap
        local g3 = g2 + colW + colGap
        local titleY = graphY + 7
        local sparkY = graphY + 13
        local sparkH = (ty + tileH - 8) - sparkY
        draw.text(g1 + colW // 2, titleY, "Temp", "small", TEMP_COLOR, "center")
        draw.text(g2 + colW // 2, titleY, tr("Humid.", "Feuchte", ctx), "small", HUM_COLOR, "center")
        draw.text(g3 + colW // 2, titleY, "CO2", "small", CO2_COLOR, "center")
        sparkline(g1, sparkY, colW, sparkH, t.hist.temp, t.hist.n, TEMP_COLOR, true, 1)
        sparkline(g2, sparkY, colW, sparkH, t.hist.humidity, t.hist.n, HUM_COLOR, true, 0)
        sparkline(g3, sparkY, colW, sparkH, t.hist.co2, t.hist.n, CO2_COLOR, true, 0)
      end
    end
  end
end

-- ---------------------------------------------------------------------------------------------- Einstiegspunkte

local function applyCfg(ctx)
  RANGE_HOURS = tonumber(ctx.cfg.range) or 24
end

function indoor.on_draw(ctx, page, nativePage)
  applyCfg(ctx)
  draw.clear(color.WHITE)
  if nativePage == 2 then
    pageNetwork(ctx)
    return true
  end
  local s = sensor.get()
  if not s then
    notice(W // 2, draw.top + 20, "loading", tr("No reading available yet.", "Noch keine Messung verfügbar.", ctx))
    return true
  end
  local style = ctx.cfg.style
  if style == "compact" then pageCompact(s, ctx)
  elseif style == "flat" then pageFlat(s, ctx)
  else pageCards(s, ctx) end
  return true
end

-- Dashboard-Widget: Symbole mit Werten in Ampelfarben; Optionsbits wie beim eingebauten Widget
-- (0x01 Verläufe, 0x02/0x04/0x10 = Temperatur/Feuchte/CO2 auswählen)
function indoor.on_widget(ctx, b)
  applyCfg(ctx)
  local s = sensor.get()
  if not s then
    draw.text(b.x + b.w // 2, b.y + b.h // 2, tr("No reading yet", "Noch keine Messung", ctx), "small", color.BLACK, "center")
    return
  end
  local opt = ctx.cfg.opt or 0
  local compact = (ctx.cfg.style == "compact")
  local font = (b.font < 0) and "small" or ((b.font > 0) and "medium" or "normal")
  local iconScale = 1.35
  local maxY = b.y + b.h - 6
  local x = b.x + 16
  local showCurves = (not compact) and (opt & 1) ~= 0
  local h = showCurves and loadHistory(0) or nil

  local selectMode = (opt & (2 | 4 | 16)) ~= 0
  local showT = selectMode and (opt & 2) ~= 0 or not selectMode
  local showH = selectMode and (opt & 4) ~= 0 or not selectMode
  local showC = selectMode and (opt & 16) ~= 0 or not selectMode
  if not showT and not showH and not showC then showT = true end
  local order = {}
  if showT then order[#order + 1] = 0 end
  if showH then order[#order + 1] = 1 end
  if showC then order[#order + 1] = 2 end

  local humCol = s.hum_warn and HUM_COLORS[humZone(s)] or color.BLACK
  local co2Col = s.co2_warn and CO2_COLORS[co2Zone(s)] or color.BLACK
  local tBuf = string.format("%.1f°C", s.temp)
  local hBuf = string.format("%.0f %%", s.humidity)
  local cBuf = string.format("%d ppm", s.co2)

  local function item(idx, px, py, spark, sx, sw)
    if idx == 0 then
      thermometerIcon(px, py, TEMP_COLOR, iconScale)
      draw.text(px + 28, py + 16, tBuf, font, color.BLACK)
      if spark and h then sparkline(sx, py - 4, sw, 28, h.temp, h.n, TEMP_COLOR, false, 1) end
    elseif idx == 1 then
      dropletIcon(px, py, humCol, iconScale)
      draw.text(px + 28, py + 16, hBuf, font, color.BLACK)
      if spark and h then sparkline(sx, py - 4, sw, 28, h.humidity, h.n, HUM_COLOR, false, 0) end
    else
      co2Icon(px, py, co2Col, iconScale)
      draw.text(px + 28, py + 16, cBuf, font, color.BLACK)
      if spark and h then sparkline(sx, py - 4, sw, 28, h.co2, h.n, CO2_COLOR, false, 0) end
    end
  end

  if compact then
    local y = b.y + 6
    for i, idx in ipairs(order) do
      if i > 1 and y + 20 > maxY then break end
      item(idx, x, y, false, 0, 0)
      y = y + 29
    end
    return
  end
  if showCurves then
    local sparkX = x + 92
    local sparkW = b.x + b.w - 12 - sparkX
    local sparkOk = sparkW >= 40 and h ~= nil
    local y = b.y + 10
    for i, idx in ipairs(order) do
      if i > 1 and y + 20 > maxY then break end
      item(idx, x, y, sparkOk, sparkX, sparkW)
      y = y + 38
    end
    return
  end
  local rowY = b.y + 10
  local x2 = b.x + b.w // 2 + 8
  for i, idx in ipairs(order) do
    local col = (i - 1) % 2
    local row = (i - 1) // 2
    local py = rowY + row * 40
    if row > 0 and py + 20 > maxY then break end
    item(idx, col == 0 and x or x2, py, false, 0, 0)
  end
end

end

-- Seite 1 = Innen, 2 = Außen, 3 = Netzwerk (nativer Index = page - 1; ctx.cfg.page darf ihn für Tests überschreiben)
function on_draw(ctx, page)
  local p = ctx.cfg.page
  if p == nil then p = (page or 1) - 1 end
  if p == 1 then return outdoor.on_draw(ctx, page) end
  return indoor.on_draw(ctx, page, p)
end

function on_widget(ctx, b)
  if ctx.cfg.widget == "weather_outdoor" then return outdoor.on_widget(ctx, b) end
  return indoor.on_widget(ctx, b)
end
