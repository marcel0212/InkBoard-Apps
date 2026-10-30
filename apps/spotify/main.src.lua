-- Spotify (Paket spotify, Skript-Variante der frueheren eingebauten App): zeigt den aktuell gespielten Titel des verknuepften
-- Spotify-Kontos in drei Stilen (Bento, Slate, Nano) und als Dashboard-Widget. Skript-API Level 21.
--
-- Anmeldung (OAuth), Zugangsdaten, Token, Abfrage-Takt und Cover-Download bleiben Dienste der Firmware: das Paket zeichnet NUR die
-- Anzeige. spotify.now() liefert Titel/Interpret/Album/Position (nur mit permissions.spotify), das Cover zeichnet
-- draw.image("spotify-cover", ...). Es holt nichts selbst (kein on_fetch); neu gezeichnet wird nach der Abfrage der Firmware
-- (Liedwechsel, Wiedergabe/Pause) und im Heartbeat-Takt der Firmware.
--
-- Zeichnung 1:1 nach den frueheren drawSpotifyAppCards()/-Flat()/-Compact() (teil14) und dwDrawSpotifyNow() (teil16).

local function cutOne(s)
  local i = #s
  while i > 1 and (s:byte(i) & 0xC0) == 0x80 do i = i - 1 end
  return s:sub(1, i - 1)
end

-- Text auf hoechstens maxW Pixel kuerzen (ohne Auslassungszeichen, wie utf8TruncateToWidth() der Firmware)
local function fit(s, maxW, font)
  s = s or ""
  while s ~= "" and draw.measure(s, font) > maxW do s = cutOne(s) end
  return s
end

-- Text mit Zusatzabstand je Zeichen (Grossbuchstaben-Etiketten)
local function spaced(x, y, text, font, col, extra)
  local i, n = 1, #text
  while i <= n do
    local b = text:byte(i)
    local len = b >= 0xF0 and 4 or (b >= 0xE0 and 3 or (b >= 0xC0 and 2 or 1))
    local ch = text:sub(i, i + len - 1)
    draw.text(x, y, ch, font, col, "left")
    x = x + draw.measure(ch, font) + extra
    i = i + len
  end
end

local function fmtMs(ms)
  local s = (ms or 0) // 1000
  return string.format("%d:%02d", s // 60, s % 60)
end

-- Position auf die Laenge begrenzt
local function progOf(n)
  local p = n.progress_ms or 0
  local d = n.duration_ms or 0
  if d > 0 and p > d then p = d end
  return p, d
end

-- Symbole (Groesse = Hoehe)
local function playIcon(cx, cy, size, col)
  local h = size
  local w = (size * 7) // 8
  local x0 = cx - w // 2 + size // 8
  draw.triangle(x0, cy - h // 2, x0, cy + h // 2, x0 + w, cy, col, true)
end
local function pauseIcon(cx, cy, size, col)
  local h = size
  local barW = size // 3
  local gap = size // 4
  draw.rect(cx - gap // 2 - barW, cy - h // 2, barW, h, col, true)
  draw.rect(cx + gap // 2, cy - h // 2, barW, h, col, true)
end
local function prevIcon(cx, cy, size, col)
  local h = size
  local w = (size * 3) // 4
  draw.rect(cx - w // 2 - 3, cy - h // 2, 3, h, col, true)
  draw.triangle(cx + w // 2, cy - h // 2, cx + w // 2, cy + h // 2, cx - w // 2, cy, col, true)
end
local function nextIcon(cx, cy, size, col)
  local h = size
  local w = (size * 3) // 4
  draw.rect(cx + w // 2, cy - h // 2, 3, h, col, true)
  draw.triangle(cx - w // 2, cy - h // 2, cx - w // 2, cy + h // 2, cx + w // 2, cy, col, true)
end
local function playOrPause(playing, cx, cy, size, col)
  if playing then pauseIcon(cx, cy, size, col) else playIcon(cx, cy, size, col) end
end

-- Cover in px x px, sonst die Platzhalterflaeche mit Text
local function cover(x, y, px, border, en)
  if draw.image("spotify-cover", x, y, px, px) then
    if border then draw.rect(x, y, px, px, color.BLACK, false) end
  else
    draw.rect(x, y, px, px, color.WHITE, true)
    draw.rect(x, y, px, px, color.BLACK, false)
    draw.text(x + px // 2, y + px // 2 + 4, en and "No cover" or "Kein Cover", "small", color.BLACK, "center")
  end
end

-- Titel: grosse fette Schrift, passt sie nicht, die naechstkleinere, zuletzt gekuerzt
local function titleFit(title, x, baseline, maxW)
  local f = "large"
  if draw.measure(title, f) > maxW then
    f = "medium"
    if draw.measure(title, f) > maxW then
      f = "normal"
      title = fit(title, maxW, f)
    end
  end
  draw.text(x, baseline, title, f, color.BLACK, "left")
end

local function statusText(n, en)
  if n.playing then return en and "Playing" or "Wird abgespielt" end
  return en and "Paused" or "Pausiert"
end

-- Leerzustaende (drawSpotifyEmptyStateIfNeeded()/drawStateNotice()): nil = es gibt einen Titel zu zeigen
local function notice(kind, line1, line2, y)
  local cx = draw.width // 2
  local r = 22
  local cy = y + r
  if kind == "loading" then
    for i = 0, 2 do draw.circle(cx, cy, r - i, color.BLACK, false) end
    for i = -1, 1 do draw.circle(cx + i * 12, cy, 3, color.BLACK, true) end
  else
    local fill, glyph = color.BLACK, "-"
    if kind == "error" then fill, glyph = color.RED, "!" end
    if kind == "setup" then fill, glyph = color.BLUE, "?" end
    draw.circle(cx, cy, r, fill, true)
    draw.text(cx, cy + 7, glyph, "large", color.WHITE, "center")
  end
  local l1 = cy + r + 32
  local f1 = "large"
  if draw.measure and draw.measure(line1, "large") > draw.width - 24 then f1 = "normal" end
  draw.text(cx, l1, line1, f1, color.BLACK, "center")
  if line2 then draw.text(cx, l1 + 26, line2, "normal", color.BLACK, "center") end
end

local function emptyState(n, en, y)
  y = y + 14
  if not n then
    notice("error", en and "Spotify not available." or "Spotify nicht verfügbar.", nil, y)
  elseif not n.connected then
    notice("setup", en and "Not connected to Spotify." or "Nicht mit Spotify verbunden.", "Studio -> Store -> Spotify", y)
  elseif not n.fetched then
    notice("loading", en and "Loading ..." or "Wird geladen ...", nil, y)
  elseif not n.fetch_ok then
    notice("error", en and "Fetch failed." or "Abruf fehlgeschlagen.", en and "Retrying shortly." or "Nächster Versuch in Kürze.", y)
  elseif not n.track then
    notice("empty", en and "Nothing is playing right now." or "Gerade wird nichts abgespielt.", nil, y)
  else
    return false
  end
  return true
end

-- Bento: grosses Cover mit Steuer-Kacheln links, Titel/Status/Fortschritt in Karten rechts
-- Hochformat: Texte umbrechen statt abkuerzen (die Karten wachsen, das Cover schrumpft entsprechend)
local function wrapN(s, w, font, n)
  local ls, l = {}, ""
  for word in s:gmatch("%S+") do
    local t = l == "" and word or (l .. " " .. word)
    if l == "" or draw.measure(t, font) <= w then l = t
    elseif #ls + 1 < n then ls[#ls + 1] = l; l = word
    else l = t end
  end
  ls[#ls + 1] = fit(l, w, font)
  return ls
end

local function titleBlock(title, w)
  for _, f in ipairs({ "large", "medium" }) do
    if draw.measure(title, f) <= w then return f, { title } end
  end
  return "normal", wrapN(title, w, "normal", 4)
end

local function putLines(x, y, ls, font, lh, align)
  for i, l in ipairs(ls) do draw.text(x, y + (i - 1) * lh, l, font, color.BLACK, align or "left") end
end

-- Hochformat (480x800) - Cover oben mittig, darunter Karten untereinander
local function drawCardsTall(n, en, topY)
  local accent, onAccent = color.ACCENT, color.ACCENT_INK
  local W = draw.width
  local margin, cardR = 20, 16
  local cw = W - 2 * margin
  local tf, tl = titleBlock(n.title, cw - 40)
  local al = wrapN(n.artist, cw - 40, "normal", 3)
  local alb = wrapN(n.album, 272, "normal", 3)
  local xt = (#tl - 1) * 24 + (#al - 1) * 24
  local xa = (#alb - 1) * 22
  local coverPx = math.max(140, 300 - xt - xa)
  local coverX = (W - coverPx) // 2
  cover(coverX, topY, coverPx, true, en)
  local pillH = 38 + xa
  local pillY = topY + coverPx + 12
  draw.rect((W - 300) // 2, pillY, 300, pillH, color.BLACK, false, 19)
  putLines(W // 2, pillY + 26, alb, "normal", 22, "center")

  local y = pillY + pillH + 14
  local card1H = 118 + xt
  draw.rect(margin, y, cw, card1H, color.BLACK, false, cardR)
  spaced(margin + 20, y + 26, en and "NOW PLAYING" or "JETZT LÄUFT", "small", color.BLACK, 3)
  putLines(margin + 20, y + 66, tl, tf, 24)
  putLines(margin + 20, y + 94 + (#tl - 1) * 24, al, "normal", 24)

  y = y + card1H + 12
  local row2H, gap2 = 62, 12
  local halfW = (cw - gap2) // 2
  draw.rect(margin, y, halfW, row2H, accent, true, cardR)
  playOrPause(n.playing, margin + 30, y + row2H // 2, 22, onAccent)
  draw.text(margin + 54, y + row2H // 2 + 7, statusText(n, en), "normal", onAccent, "left")
  local p, d = progOf(n)
  local restX = margin + halfW + gap2
  draw.rect(restX, y, halfW, row2H, color.BLACK, false, cardR)
  local remain = d > p and (d - p) or 0
  draw.text(restX + halfW // 2, y + 30, "-" .. fmtMs(remain), "large", color.BLACK, "center")
  draw.text(restX + halfW // 2, y + row2H - 10, en and "remaining" or "verbleibend", "small", color.BLACK, "center")

  y = y + row2H + 12
  local row3H = 78
  draw.rect(margin, y, cw, row3H, color.BLACK, false, cardR)
  local segCount, segGap = 18, 3
  local segAreaW = cw - 40
  local segW = (segAreaW - (segCount - 1) * segGap) // segCount
  local segY = y + 16
  local filled = 0
  if d > 0 then filled = math.min(segCount, segCount * p // d) end
  local segX = margin + 20
  for s = 0, segCount - 1 do
    if s < filled then draw.rect(segX, segY, segW, 18, accent, true, 4) else draw.rect(segX, segY, segW, 18, color.BLACK, false, 4) end
    segX = segX + segW + segGap
  end
  draw.text(margin + 20, segY + 18 + 22, fmtMs(p), "normal", color.BLACK, "left")
  draw.text(margin + cw - 20, segY + 18 + 22, fmtMs(d), "normal", color.BLACK, "right")

  y = y + row3H + 12
  local tileGap = 12
  local tileW = (cw - 2 * tileGap) // 3
  local tileH = 62
  draw.rect(margin, y, tileW, tileH, color.BLACK, false, 14)
  draw.rect(margin + 1, y + 1, tileW - 2, tileH - 2, color.BLACK, false, 13)
  prevIcon(margin + tileW // 2, y + tileH // 2, 20, color.BLACK)
  local txm = margin + tileW + tileGap
  draw.rect(txm, y, tileW, tileH, accent, true, 14)
  playOrPause(n.playing, txm + tileW // 2, y + tileH // 2, 24, onAccent)
  local txr = txm + tileW + tileGap
  draw.rect(txr, y, tileW, tileH, color.BLACK, false, 14)
  draw.rect(txr + 1, y + 1, tileW - 2, tileH - 2, color.BLACK, false, 13)
  nextIcon(txr + tileW // 2, y + tileH // 2, 20, color.BLACK)
end

local function drawCards(n, en, topY)
  if draw.height > draw.width then return drawCardsTall(n, en, topY) end
  local accent, onAccent = color.ACCENT, color.ACCENT_INK
  local margin, cardR = 14, 16
  local coverPx, coverX, coverY = 250, margin, topY
  cover(coverX, coverY, coverPx, true, en)

  local pillH = 40
  local pillY = coverY + coverPx + 14
  if n.album ~= "" then draw.rect(coverX, pillY, coverPx, pillH, color.BLACK, false, pillH // 2) end
  draw.text(coverX + coverPx // 2, pillY + pillH - 13, fit(n.album, coverPx - 28, "normal"), "normal", color.BLACK, "center")

  local tileGap = 10
  local tileW = (coverPx - 2 * tileGap) // 3
  local tileH = 64
  local tileY = pillY + pillH + 14
  local tx0 = coverX
  draw.rect(tx0, tileY, tileW, tileH, color.BLACK, false, 14)
  draw.rect(tx0 + 1, tileY + 1, tileW - 2, tileH - 2, color.BLACK, false, 13)
  prevIcon(tx0 + tileW // 2, tileY + tileH // 2, 20, color.BLACK)
  local txm = tx0 + tileW + tileGap
  draw.rect(txm, tileY, tileW, tileH, accent, true, 14)
  playOrPause(n.playing, txm + tileW // 2, tileY + tileH // 2, 24, onAccent)
  local txr = txm + tileW + tileGap
  draw.rect(txr, tileY, tileW, tileH, color.BLACK, false, 14)
  draw.rect(txr + 1, tileY + 1, tileW - 2, tileH - 2, color.BLACK, false, 13)
  nextIcon(txr + tileW // 2, tileY + tileH // 2, 20, color.BLACK)

  local rightX = coverX + coverPx + 24
  local rightW = draw.width - margin - rightX

  local card1H = 130
  draw.rect(rightX, topY, rightW, card1H, color.BLACK, false, cardR)
  spaced(rightX + 20, topY + 26, en and "NOW PLAYING" or "JETZT LÄUFT", "small", color.BLACK, 3)
  titleFit(n.title, rightX + 20, topY + 66, rightW - 40)
  draw.text(rightX + 20, topY + 96, fit(n.artist, rightW - 40, "normal"), "normal", color.BLACK, "left")

  local row2Y = topY + card1H + 14
  local row2H, gap2 = 70, 14
  local halfW = (rightW - gap2) // 2
  draw.rect(rightX, row2Y, halfW, row2H, accent, true, cardR)
  local st = statusText(n, en)
  local l1, l2 = st, ""
  local sp = st:find(" ", 1, true)
  if sp then l1, l2 = st:sub(1, sp - 1), st:sub(sp + 1) end
  playOrPause(n.playing, rightX + 30, row2Y + row2H // 2, 22, onAccent)
  local stX = rightX + 54
  if l2 ~= "" then
    draw.text(stX, row2Y + row2H // 2 - 4, l1, "normal", onAccent, "left")
    draw.text(stX, row2Y + row2H // 2 + 16, l2, "normal", onAccent, "left")
  else
    draw.text(stX, row2Y + row2H // 2 + 6, l1, "normal", onAccent, "left")
  end

  local p, d = progOf(n)
  local restX = rightX + halfW + gap2
  draw.rect(restX, row2Y, halfW, row2H, color.BLACK, false, cardR)
  local remain = d > p and (d - p) or 0
  draw.text(restX + halfW // 2, row2Y + 34, "-" .. fmtMs(remain), "large", color.BLACK, "center")
  draw.text(restX + halfW // 2, row2Y + row2H - 12, en and "remaining" or "verbleibend", "small", color.BLACK, "center")

  local row3Y = row2Y + row2H + 14
  local row3H = 90
  draw.rect(rightX, row3Y, rightW, row3H, color.BLACK, false, cardR)
  local segCount, segGap = 14, 3
  local segAreaW = rightW - 40
  local segW = (segAreaW - (segCount - 1) * segGap) // segCount
  local segH = 18
  local segY = row3Y + 20
  local filled = 0
  if d > 0 then filled = math.min(segCount, segCount * p // d) end
  local segX = rightX + 20
  for s = 0, segCount - 1 do
    if s < filled then
      draw.rect(segX, segY, segW, segH, accent, true, 4)
    else
      draw.rect(segX, segY, segW, segH, color.BLACK, false, 4)
    end
    segX = segX + segW + segGap
  end
  local timesY = segY + segH + 24
  draw.text(rightX + 20, timesY, fmtMs(p), "normal", color.BLACK, "left")
  draw.text(rightX + rightW - 20, timesY, fmtMs(d), "normal", color.BLACK, "right")
end

-- Slate: schlichte zweispaltige Ansicht, links Cover ohne Rahmen, rechts Texte
local function drawFlat(n, en, topY)
  local accent = color.ACCENT
  if draw.height > draw.width then
    local W = draw.width
    local x0, x1 = 24, W - 24
    local tf, tl = titleBlock(n.title, x1 - x0)
    local al = wrapN(n.artist, x1 - x0, "normal", 3)
    local alb = wrapN(n.album, W - 60, "normal", 3)
    local xt = (#tl - 1) * 24 + (#al - 1) * 24
    local xa = (#alb - 1) * 22
    local coverPx = math.max(140, 300 - xt - xa)
    local coverX = (W - coverPx) // 2
    cover(coverX, topY + 10, coverPx, false, en)
    putLines(W // 2, topY + 10 + coverPx + 28, alb, "normal", 22, "center")
    local y = topY + 10 + coverPx + 50 + xa
    draw.line(x0, y, x1, y, color.BLACK)
    spaced(x0, y + 34, en and "NOW PLAYING" or "JETZT LÄUFT", "small", color.BLACK, 3)
    putLines(x0, y + 78, tl, tf, 24)
    putLines(x0, y + 108 + (#tl - 1) * 24, al, "normal", 24)
    y = y + (#tl - 1) * 24 + (#al - 1) * 24
    draw.line(x0, y + 128, x1, y + 128, color.BLACK)
    draw.circle(x0 + 5, y + 156, 5, n.playing and accent or color.BLACK, true)
    draw.text(x0 + 18, y + 160, statusText(n, en), "normal", color.BLACK, "left")
    local p, d = progOf(n)
    local barY = y + 190
    if d > 0 then
      draw.line(x0, barY, x1, barY, color.BLACK)
      local fw = math.min(x1 - x0, (x1 - x0) * p // d)
      if fw > 0 then draw.rect(x0, barY - 2, fw, 4, accent, true) end
      draw.text(x0, barY + 26, fmtMs(p), "small", color.BLACK, "left")
      draw.text(x1, barY + 26, fmtMs(d), "small", color.BLACK, "right")
    end
    local ctrlY = barY + 70
    prevIcon(W // 2 - 70, ctrlY, 18, color.BLACK)
    playOrPause(n.playing, W // 2, ctrlY, 22, color.BLACK)
    nextIcon(W // 2 + 70, ctrlY, 18, color.BLACK)
    return
  end
  local coverPx, coverX, coverY = 200, 108, topY + 20
  cover(coverX, coverY, coverPx, false, en)
  draw.text(coverX + coverPx // 2, coverY + coverPx + 26, fit(n.album, 380, "normal"), "normal", color.BLACK, "center")

  draw.line(396, topY + 4, 396, 400, color.BLACK)
  local textX = 416
  local rightEdge = draw.width - 24
  local maxTextW = rightEdge - textX

  spaced(textX, topY + 34, en and "NOW PLAYING" or "JETZT LÄUFT", "small", color.BLACK, 3)
  titleFit(n.title, textX, topY + 76, maxTextW)
  draw.text(textX, topY + 104, fit(n.artist, maxTextW, "normal"), "normal", color.BLACK, "left")

  local hLineY = topY + 122
  draw.line(textX, hLineY, rightEdge, hLineY, color.BLACK)

  local statusY = topY + 154
  draw.circle(textX + 5, statusY - 4, 5, n.playing and accent or color.BLACK, true)
  draw.text(textX + 18, statusY, statusText(n, en), "normal", color.BLACK, "left")

  local p, d = progOf(n)
  local hasBar = d > 0
  local barY = topY + 194
  local barX, barW = textX, rightEdge - textX
  local timesY = barY + 26
  if hasBar then
    draw.line(barX, barY, barX + barW, barY, color.BLACK)
    local fw = math.min(barW, barW * p // d)
    if fw > 0 then draw.rect(barX, barY - 2, fw, 4, accent, true) end
    draw.text(barX, timesY, fmtMs(p), "small", color.BLACK, "left")
    draw.text(barX + barW, timesY, fmtMs(d), "small", color.BLACK, "right")
  end

  local ctrlY = (hasBar and timesY or statusY) + 40
  prevIcon(textX + 10, ctrlY, 16, color.BLACK)
  playOrPause(n.playing, textX + 44, ctrlY, 18, color.BLACK)
  nextIcon(textX + 78, ctrlY, 16, color.BLACK)
end

-- Nano: Datenblatt kompakt - sieben Zeilen Etikett/Wert, kleines Cover rechts, Fortschrittsbalken und Steuer-Pille unten
local function drawCompact(n, en, topY)
  local accent = color.ACCENT
  local tall = draw.height > draw.width
  local coverPx = tall and 190 or 132
  local labelX, valueX = 16, 170
  local lineRight = tall and (draw.width - 16) or (draw.width - 16 - coverPx - 16)
  local maxValueW = lineRight - valueX
  local wrapped = {} -- Hochformat: Titel/Interpret/Album umbrechen, Zeilen wachsen, Cover schrumpft
  local xtra = 0
  if tall then
    for i, t in ipairs({ n.title, n.artist, n.album }) do
      wrapped[i] = wrapN(t, maxValueW, "normal", 3)
      xtra = xtra + (#wrapped[i] - 1) * 22
    end
    coverPx = math.max(90, coverPx - xtra)
  end
  local coverX = tall and (draw.width - coverPx) // 2 or (draw.width - 16 - coverPx)
  cover(coverX, topY, coverPx, true, en)
  local rowH = tall and 52 or 44
  local rowTop0 = topY + (tall and coverPx + 24 or 20)

  local p, d = progOf(n)
  local remain = d > p and (d - p) or 0
  local pct = d > 0 and math.min(100, p * 100 // d) or 0
  local labels = {
    en and "TITLE" or "TITEL", en and "ARTIST" or "INTERPRET", n.album ~= "" and "ALBUM" or "", "STATUS",
    en and "POSITION" or "POSITION", en and "REMAINING" or "VERBLEIBEND", en and "PROGRESS" or "FORTSCHRITT",
  }
  local values = {
    fit(n.title, maxValueW, "normal"), fit(n.artist, maxValueW, "normal"), fit(n.album, maxValueW, "normal"),
    statusText(n, en), fmtMs(p) .. " / " .. fmtMs(d), fmtMs(remain) .. (en and " min" or " Min."), pct .. " %",
  }
  local rowTop = rowTop0
  for i = 1, 7 do
    local wl = wrapped[i]
    local rh = rowH + (wl and (#wl - 1) * 22 or 0)
    spaced(labelX, rowTop + 24, labels[i], "small", color.BLACK, 2)
    if i == 4 then
      draw.circle(valueX + 4, rowTop + 22, 4, n.playing and accent or color.BLACK, true)
      draw.text(valueX + 16, rowTop + 27, values[i], "normal", color.BLACK, "left")
    elseif wl then
      putLines(valueX, rowTop + 27, wl, "normal", 22)
    else
      draw.text(valueX, rowTop + 27, values[i], "normal", color.BLACK, "left")
    end
    draw.line(labelX, rowTop + rh - 6, lineRight, rowTop + rh - 6, color.BLACK)
    rowTop = rowTop + rh
  end

  local footerY = rowTop + 16
  local pillW, pillH = 90, 40
  local pillX = draw.width - 16 - pillW
  if tall then footerY = footerY + 14 end
  local barX = labelX
  local barY = footerY + (pillH - 10) // 2
  local barW = pillX - 20 - barX
  local barH = 10
  draw.rect(barX, barY, barW, barH, color.BLACK, false)
  if d > 0 then
    local fw = math.min(barW, barW * p // d)
    if fw > 0 then draw.rect(barX, barY, fw, barH, accent, true) end
  end
  draw.rect(pillX, footerY, pillW, pillH, color.BLACK, false, pillH // 2)
  local pcx, pcy = pillX + pillW // 2, footerY + pillH // 2
  prevIcon(pillX + 18, pcy, 12, color.BLACK)
  playOrPause(n.playing, pcx, pcy, 14, color.BLACK)
  nextIcon(pillX + pillW - 18, pcy, 12, color.BLACK)
end

function on_draw(ctx, page)
  local en = (ctx.lang == "en")
  draw.clear(color.WHITE)
  local y = draw.top + 14
  local n = spotify.now()
  if emptyState(n, en, y) then return end
  -- Zusatzinfos (Albumname): Einstellung "details"; in der Vorschau (ctx.preview) immer
  if ctx.cfg.details == false and ctx.preview ~= true then
    local c = {}
    for k2, v2 in pairs(n) do c[k2] = v2 end
    c.album = ""
    n = c
  end
  local style = ctx.cfg.style
  if style == "compact" then
    drawCompact(n, en, y)
  elseif style == "flat" then
    drawFlat(n, en, y)
  else
    drawCards(n, en, y)
  end
end

-- Widget "Gerade laeuft" (frueher dwDrawSpotifyNow()): Noten-Symbol im Akzentkreis + Titel/Interpret, optional Album und Fortschrittsbalken;
-- die Kompakt-Variante zeigt nur Titel und Interpret in zwei Zeilen. Ein Widget loest keinen Abruf aus (zeigt den letzten Stand).
local function on(v) return v == true end

function on_widget(ctx, box)
  local en = (ctx.lang == "en")
  local n = spotify.now()
  if ctx.sample then
    n = { connected = true, track = true, playing = true, title = en and "Sample Title" or "Titel-Beispiel",
          artist = en and "Sample Artist" or "Interpret-Beispiel", album = en and "Sample Album" or "Album-Beispiel",
          progress_ms = 95000, duration_ms = 210000 }
  end
  if n == nil or not n.track then
    draw.text(box.x + 12, box.y + 16, fit(en and "Nothing playing" or "Gerade keine Wiedergabe", box.w - 20, "small"), "small", color.BLACK, "left")
    return
  end
  local maxY = box.y + box.fh - 4
  local pause = n.playing and "" or (en and "(paused) " or "(Pause) ")
  local font = box.font < 0 and "small" or "normal"
  if on(ctx.cfg.wCompact) then
    draw.text(box.x + 12, box.y + 16, fit(pause .. n.title, box.w - 20, font), font, color.BLACK, "left")
    draw.text(box.x + 12, box.y + 34, fit(n.artist, box.w - 20, "small"), "small", color.ACCENT_TEXT, "left")
    if on(ctx.cfg.wAlbum) and n.album ~= "" and maxY >= box.y + 50 then
      draw.text(box.x + 12, box.y + 50, fit(n.album, box.w - 20, "small"), "small", color.BLACK, "left")
    end
    return
  end
  local cy = box.y + 22
  draw.circle(box.x + 28, cy, 16, color.ACCENT, true)
  draw.icon("music", box.x + 28 - 9, cy - 9, 18, color.ACCENT_INK)
  local textX = box.x + 54
  local maxW = box.x + box.w - textX - 6
  draw.text(textX, cy - 2, fit(pause .. n.title, maxW, font), font, color.BLACK, "left")
  draw.text(textX, cy + 16, fit(n.artist, maxW, "small"), "small", color.BLACK, "left")
  local after = cy + 16
  if on(ctx.cfg.wAlbum) and n.album ~= "" and cy + 30 <= maxY then
    draw.text(textX, cy + 30, fit(n.album, maxW, "small"), "small", color.BLACK, "left")
    after = cy + 30
  end
  local d = n.duration_ms or 0
  if on(ctx.cfg.wProgress) and d > 0 and after + 14 <= maxY then
    local barX, barW, barY = box.x + 14, box.w - 28, after + 10
    draw.rect(barX, barY, barW, 5, color.WHITE, true, 2)
    draw.rect(barX, barY, barW, 5, color.BLACK, false, 2)
    local fw = math.min(barW - 2, (barW - 2) * (n.progress_ms or 0) // d)
    if fw > 0 then draw.rect(barX + 1, barY + 1, fw, 3, color.ACCENT, true, 1) end
  end
end
