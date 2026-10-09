-- Uhr: Digitaluhr mit Datum und Kalenderwoche in drei Stilen (Bento, Slate, Nano) und passendes
-- Dashboard-Widget. Standard-App: steht nur zur Verfuegung, solange in den Einstellungen die
-- Uhrzeit-Anzeige aktiv ist. Skript-API Level 2 (time.localtime(), ctx.clock24).

local DAYS_DE = {"Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"}
local DAYS_EN = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"}
local MONTHS_DE = {"Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"}
local MONTHS_EN = {"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"}

-- Bitmaske je Ziffer: Bit0=A(oben), 1=B(rechts oben), 2=C(rechts unten), 3=D(unten), 4=E(links unten), 5=F(links oben), 6=G(Mitte)
local MASK = {0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F}

local function digit(x, y, w, h, t, d, col)
  local m = MASK[d + 1]
  if m == nil then return end
  local half = (h - 3 * t) // 2
  if m & 0x01 ~= 0 then draw.rect(x + t, y, w - 2 * t, t, col, true) end
  if m & 0x02 ~= 0 then draw.rect(x + w - t, y + t, t, half, col, true) end
  if m & 0x04 ~= 0 then draw.rect(x + w - t, y + 2 * t + half, t, half, col, true) end
  if m & 0x08 ~= 0 then draw.rect(x + t, y + h - t, w - 2 * t, t, col, true) end
  if m & 0x10 ~= 0 then draw.rect(x, y + 2 * t + half, t, half, col, true) end
  if m & 0x20 ~= 0 then draw.rect(x, y + t, t, half, col, true) end
  if m & 0x40 ~= 0 then draw.rect(x + t, y + t + half, w - 2 * t, t, col, true) end
end

local function timeWidth(w, t)
  return 4 * w + 2 * t + 3 * t
end

-- Zeichnet "HH:MM" (5 Zeichen) zentriert um cx mit Oberkante y; gibt die Unterkante zurueck.
local function drawTime(str, cx, y, w, h, t, col, colonCol)
  local gap = t
  local colonSpace = 3 * t
  local x = cx - timeWidth(w, t) // 2
  for i = 1, 5 do
    local c = str:sub(i, i)
    if i == 3 then
      local ccx = x + (colonSpace - t) // 2
      draw.rect(ccx, y + h // 3 - t // 2, t, t, colonCol, true)
      draw.rect(ccx, y + (2 * h) // 3 - t // 2, t, t, colonCol, true)
      x = x + colonSpace
    else
      local d = tonumber(c)
      if d then digit(x, y, w, h, t, d, col) end
      x = x + w + gap
    end
  end
  return y + h
end

-- "HH:MM" (immer zwei Ziffern) und AM/PM; im 12-h-Modus 12 statt 0.
local function clockStrings(ctx, lt)
  local h = lt.hour
  local ampm = ""
  if not ctx.clock24 then
    ampm = h >= 12 and "PM" or "AM"
    h = h % 12
    if h == 0 then h = 12 end
  end
  return string.format("%02d:%02d", h, lt.min), ampm
end

local function names(ctx)
  if ctx.lang == "en" then return DAYS_EN, MONTHS_EN end
  return DAYS_DE, MONTHS_DE
end

function on_draw(ctx, page)
  local en = (ctx.lang == "en")
  draw.clear(color.WHITE)
  local lt = time.localtime()
  local cx = draw.width // 2
  local y = draw.top + 14
  if lt == nil then
    draw.text(cx, 260, en and "Time is still syncing ..." or "Zeit synchronisiert sich noch ...", "medium", color.BLACK, "center")
    return
  end
  local days, months = names(ctx)
  local accent = color.ACCENT
  local str, ampm = clockStrings(ctx, lt)
  local dateLong = string.format("%s, %02d.%02d.%04d", days[lt.wday + 1], lt.day, lt.month, lt.year)
  local kw = (en and "Week " or "KW ") .. lt.week
  local style = ctx.cfg.style

  if style == "slate" then
    -- Slate: reduziert - riesige schwarze Ziffern, Haarlinie, Datum.
    local w, h, t = 110, 210, 26
    local bottom = drawTime(str, cx, y + 40, w, h, t, color.BLACK, accent)
    if ampm ~= "" then
      draw.text(cx + timeWidth(w, t) // 2 + 12, bottom - 4, ampm, "normal", color.BLACK, "left")
    end
    draw.line(cx - 240, bottom + 34, cx + 240, bottom + 34, color.BLACK)
    draw.text(cx, bottom + 80, dateLong, "large", color.BLACK, "center")
    draw.text(cx, bottom + 112, kw, "normal", color.BLACK, "center")
  elseif style == "nano" then
    -- Nano: kleinere Uhr, Datum/KW-Zeile und Tagesfortschritt (00:00-24:00).
    local w, h, t = 72, 132, 16
    local bottom = drawTime(str, cx, y + 28, w, h, t, color.BLACK, accent)
    if ampm ~= "" then
      draw.text(cx + timeWidth(w, t) // 2 + 10, bottom - 4, ampm, "normal", color.BLACK, "left")
    end
    draw.text(cx, bottom + 40, dateLong .. " · " .. kw, "normal", color.BLACK, "center")
    local barW, barH = 520, 14
    local barX = cx - barW // 2
    local barY = bottom + 70
    local minutes = lt.hour * 60 + lt.min
    local fillW = barW * minutes // 1440
    draw.rect(barX, barY, barW, barH, color.BLACK, false)
    if fillW > 2 then draw.rect(barX + 1, barY + 1, fillW - 2, barH - 2, accent, true) end
    draw.text(barX, barY + barH + 18, "0", "small", color.BLACK, "left")
    draw.text(barX + barW - 14, barY + barH + 18, "24", "small", color.BLACK, "left")
  else
    -- Bento: grosse Uhr-Kachel plus zwei Info-Kacheln (Datum / Monat mit Kalenderwoche).
    local cardX, cardW = 70, draw.width - 140
    local cardY, cardH = y + 12, 252
    draw.rect(cardX, cardY, cardW, cardH, color.BLACK, false, 16)
    draw.rect(cardX + 1, cardY + 1, cardW - 2, cardH - 2, color.BLACK, false, 15)
    local w, h, t = 96, 180, 22
    local bottom = drawTime(str, cx, cardY + (cardH - h) // 2, w, h, t, color.BLACK, accent)
    if ampm ~= "" then
      draw.text(cx + timeWidth(w, t) // 2 + 12, bottom - 4, ampm, "normal", color.BLACK, "left")
    end
    local tileY, tileH, gap = cardY + cardH + 18, 118, 18
    local tileW = (cardW - gap) // 2
    draw.rect(cardX, tileY, tileW, tileH, color.BLACK, false, 16)
    draw.rect(cardX + 1, tileY + 1, tileW - 2, 8, accent, true)
    draw.text(cardX + tileW // 2, tileY + 58, days[lt.wday + 1], "large", color.BLACK, "center")
    draw.text(cardX + tileW // 2, tileY + 92, string.format("%02d.%02d.%04d", lt.day, lt.month, lt.year), "normal", color.BLACK, "center")
    local tile2X = cardX + tileW + gap
    draw.rect(tile2X, tileY, tileW, tileH, color.BLACK, false, 16)
    draw.rect(tile2X + 1, tileY + 1, tileW - 2, 8, accent, true)
    draw.text(tile2X + tileW // 2, tileY + 58, months[lt.month], "large", color.BLACK, "center")
    draw.text(tile2X + tileW // 2, tileY + 92, kw, "normal", color.BLACK, "center")
  end
end

-- Dashboard-Widget: 7-Segment-Uhr, auf die Groesse skaliert; optional mit Datumszeile.
-- CHANGELOG 506: Schriftgroesse des Widgets (box.font: -1 klein, 0 normal, +1 gross) fuer die Datumszeile
local function fnt(b, base)
  local t = b and b.font or 0
  if t < 0 and base == "normal" then return "small" end
  if t > 0 and base == "small" then return "normal" end
  return base
end

function on_widget(ctx, box)
  local lt = time.localtime()
  if lt == nil then
    draw.text(box.x + box.w // 2, box.y + box.h // 2, ctx.lang == "en" and "No data yet" or "Noch keine Daten", "small", color.BLACK, "center")
    return
  end
  local days = names(ctx)
  local str, ampm = clockStrings(ctx, lt)
  local showDate = ctx.cfg.showDate
  local cx = box.x + box.w // 2
  local maxY = box.y + box.h - 6
  local hAvail = (maxY - box.y) - (showDate and 26 or 0)
  local h = hAvail - 6
  if h > 210 then h = 210 end
  local dateLong = string.format("%s, %02d.%02d.%04d", days[lt.wday + 1], lt.day, lt.month, lt.year)
  if h >= 44 then
    local w = h * 11 // 21
    local t = h // 8
    if t < 6 then t = 6 end
    -- schrumpfen, bis "HH:MM" in die Widget-Breite passt
    while w > 22 and timeWidth(w, t) > box.w - 16 do
      w = w - 4
      h = w * 21 // 11
      t = h // 8
      if t < 6 then t = 6 end
    end
    local bottom = drawTime(str, cx, box.y + 4, w, h, t, color.BLACK, color.ACCENT)
    if ampm ~= "" then
      draw.text(cx + timeWidth(w, t) // 2 + 6, bottom - 2, ampm, fnt(box, "small"), color.BLACK, "left")
    end
    if showDate and bottom + 20 <= maxY then
      draw.text(cx, bottom + 18, dateLong, fnt(box, "small"), color.BLACK, "center")
    end
  else
    -- zu flach fuer Segmente: Schrift als Rueckfallebene
    local txt = ampm ~= "" and (str .. " " .. ampm) or str
    local ty = box.y + (maxY - box.y) // 2 + 12
    draw.text(cx, showDate and ty - 8 or ty, txt, "large", color.BLACK, "center")
    if showDate and ty + 14 <= maxY then
      draw.text(cx, ty + 14, dateLong, fnt(box, "small"), color.BLACK, "center")
    end
  end
end
