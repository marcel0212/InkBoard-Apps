local function cutOne(s)
local i = #s
while i > 1 and (s:byte(i) & 0xC0) == 0x80 do i = i - 1 end
return s:sub(1, i - 1)
end
local function fit(s, maxW, font)
s = s or ""
while s ~= "" and draw.measure(s, font) > maxW do s = cutOne(s) end
return s
end
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
local function progOf(n)
local p = n.progress_ms or 0
local d = n.duration_ms or 0
if d > 0 and p > d then p = d end
return p, d
end
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
local function cover(x, y, px, border, en)
if draw.image("spotify-cover", x, y, px, px) then
if border then draw.rect(x, y, px, px, color.BLACK, false) end
else
draw.rect(x, y, px, px, color.WHITE, true)
draw.rect(x, y, px, px, color.BLACK, false)
draw.text(x + px // 2, y + px // 2 + 4, en and "No cover" or "Kein Cover", "small", color.BLACK, "center")
end
end
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
draw.text(cx, l1, line1, "large", color.BLACK, "center")
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
local function drawCards(n, en, topY)
local accent, onAccent = color.ACCENT, color.ACCENT_INK
local margin, cardR = 14, 16
local coverPx, coverX, coverY = 250, margin, topY
cover(coverX, coverY, coverPx, true, en)
local pillH = 40
local pillY = coverY + coverPx + 14
draw.rect(coverX, pillY, coverPx, pillH, color.BLACK, false, pillH // 2)
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
local function drawFlat(n, en, topY)
local accent = color.ACCENT
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
local function drawCompact(n, en, topY)
local accent = color.ACCENT
local coverPx = 132
local coverX = draw.width - 16 - coverPx
cover(coverX, topY, coverPx, true, en)
local lineRight = coverX - 16
local labelX, valueX = 16, 170
local maxValueW = lineRight - valueX
local rowH = 44
local rowTop0 = topY + 20
local p, d = progOf(n)
local remain = d > p and (d - p) or 0
local pct = d > 0 and math.min(100, p * 100 // d) or 0
local labels = {
en and "TITLE" or "TITEL", en and "ARTIST" or "INTERPRET", "ALBUM", "STATUS",
en and "POSITION" or "POSITION", en and "REMAINING" or "VERBLEIBEND", en and "PROGRESS" or "FORTSCHRITT",
}
local values = {
fit(n.title, maxValueW, "normal"), fit(n.artist, maxValueW, "normal"), fit(n.album, maxValueW, "normal"),
statusText(n, en), fmtMs(p) .. " / " .. fmtMs(d), fmtMs(remain) .. (en and " min" or " Min."), pct .. " %",
}
for i = 1, 7 do
local rowTop = rowTop0 + (i - 1) * rowH
spaced(labelX, rowTop + 24, labels[i], "small", color.BLACK, 2)
if i == 4 then
draw.circle(valueX + 4, rowTop + 22, 4, n.playing and accent or color.BLACK, true)
draw.text(valueX + 16, rowTop + 27, values[i], "normal", color.BLACK, "left")
else
draw.text(valueX, rowTop + 27, values[i], "normal", color.BLACK, "left")
end
draw.line(labelX, rowTop + rowH - 6, lineRight, rowTop + rowH - 6, color.BLACK)
end
local footerY = rowTop0 + 7 * rowH + 16
local pillW, pillH = 90, 40
local pillX = draw.width - 16 - pillW
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
local style = ctx.cfg.style
if style == "compact" then
drawCompact(n, en, y)
elseif style == "flat" then
drawFlat(n, en, y)
else
drawCards(n, en, y)
end
end
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
