local MAX_AGE = 3 * 3600 -- Sekunden
local DAYS_DE = {"Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"}
local DAYS_EN = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}
local function trim(s)
return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
local function cutOne(s)
local i = #s
while i > 1 and (s:byte(i) & 0xC0) == 0x80 do i = i - 1 end
return s:sub(1, i - 1)
end
local function wrap(text, width, font, maxLines)
local lines = {}
local rem = trim(text)
while rem ~= "" and #lines < maxLines do
if draw.measure(rem, font) <= width then
lines[#lines + 1] = rem
break
end
local best, from = nil, 1
while true do
local sp = rem:find(" ", from, true)
if sp == nil then break end
if draw.measure(rem:sub(1, sp - 1), font) <= width then
best = sp
from = sp + 1
else
break
end
end
if best ~= nil and best > 1 then
lines[#lines + 1] = rem:sub(1, best - 1)
rem = trim(rem:sub(best + 1))
else
local buf = rem:sub(1, 79)
local last = #buf
while last > 1 and (buf:byte(last) & 0xC0) == 0x80 do last = last - 1 end
if last >= 1 and buf:byte(last) >= 0xC0 then
local b = buf:byte(last)
local need = b >= 0xF0 and 4 or (b >= 0xE0 and 3 or 2)
if #buf - last + 1 < need then buf = buf:sub(1, last - 1) end
end
while buf ~= "" and draw.measure(buf, font) > width do buf = cutOne(buf) end
if buf == "" then break end
lines[#lines + 1] = rem:sub(1, #buf)
rem = trim(rem:sub(#buf + 1))
end
end
return lines
end
local function stamp(m, en)
local at = m.at
if at == nil then return "" end
local now = time.localtime()
if now ~= nil and now.year == at.year and now.month == at.month and now.day == at.day then
return string.format("%02d:%02d", at.hour, at.min)
end
local days = en and DAYS_EN or DAYS_DE
return string.format("%s, %02d:%02d", days[(at.wday + 6) % 7 + 1], at.hour, at.min)
end
local function initial(name)
local c = name:match("^[\0-\127\194-\244][\128-\191]*") or "?"
if #c == 1 and c >= "a" and c <= "z" then c = c:upper() end
return c
end
local function emptyState(en, y)
local cx = draw.width // 2
local cy = y + 14 + 22
draw.circle(cx, cy, 22, color.BLACK, true)
draw.text(cx, cy + 7, "-", "large", color.WHITE, "center")
draw.text(cx, cy + 22 + 32, en and "No message yet" or "Noch keine Nachricht", "large", color.BLACK, "center")
draw.text(cx, cy + 22 + 32 + 26, en and "Studio -> Store -> Family Board" or "Studio -> Store -> Pinnwand", "normal", color.BLACK, "center")
end
function on_draw(ctx, page)
local en = (ctx.lang == "en")
draw.clear(color.WHITE)
local y = draw.top + 14
local m = inbox.latest(MAX_AGE) -- CHANGELOG 662: nach 3 Stunden gilt die Nachricht als abgelaufen (nil = leere Pinnwand)
if m == nil or m.text == nil or m.text == "" then
emptyState(en, y)
return
end
local cx = draw.width // 2
local cardX = 40
local cardW = draw.width - 2 * cardX
local cardY = y + 6
local cardBottom = draw.height - 30
local cardH = cardBottom - cardY
draw.rect(cardX, cardY, cardW, cardH, color.WHITE, true, 18)
draw.rect(cardX, cardY, cardW, cardH, color.BLACK, false, 18)
draw.rect(cardX + 6, cardY + 6, 5, cardH - 12, color.ACCENT, true, 2)
draw.circle(cx, cardY, 10, color.ACCENT, true)
draw.circle(cx, cardY, 10, color.BLACK, false)
draw.circle(cx, cardY, 3, color.WHITE, true)
local pad = 28
local left = cardX + pad
local right = cardX + cardW - pad
local width = right - left
local avatarR = 24
local rowCy = cardY + pad + avatarR
local avatarCx = left + avatarR
draw.circle(avatarCx, rowCy, avatarR, color.ACCENT, true)
draw.circle(avatarCx, rowCy, avatarR, color.BLACK, false)
local sender = trim(m.sender or "")
if sender == "" then sender = en and "Family" or "Familie" end
draw.text(avatarCx, rowCy + 8, initial(sender), "large", color.ACCENT_INK, "center")
draw.text(avatarCx + avatarR + 14, rowCy + 8, sender, "large", color.BLACK, "left")
local ts = stamp(m, en)
if ts ~= "" then draw.text(right, rowCy + 8, ts, "normal", color.BLACK, "right") end
local dividerY = rowCy + avatarR + 16
draw.line(left, dividerY, left + width - 1, dividerY, color.BLACK)
local lines = wrap(m.text, width, "large", 5)
local font, lineH, textTop = "large", 34, dividerY + 40
if #lines > 4 then
font, lineH, textTop = "normal", 24, dividerY + 24
lines = wrap(m.text, width, "normal", 8)
end
for i = 1, #lines do
local ly = textTop + (i - 1) * lineH
if ly >= cardBottom - 16 then break end
draw.text(left, ly, lines[i], font, color.BLACK, "left")
end
end
function on_action(ctx, name)
local en = (ctx.lang == "en")
if name ~= "send" then return { ok = false, message = en and "Unknown action." or "Unbekannte Aktion." } end
local cfg = ctx.cfg or {}
local text = trim(cfg.message or "")
if text == "" then
return { ok = false, message = en and "Please enter a message first." or "Bitte zuerst eine Nachricht eingeben." }
end
local room = cfg.room
if room == "all" then room = "" end
local ok, err = inbox.send(trim(cfg.sender or ""), text, room or "")
if not ok then
return { ok = false, message = (en and "Not sent: " or "Nicht gesendet: ") .. tostring(err) }
end
return { ok = true, message = en and "Sent." or "Gesendet." }
end
