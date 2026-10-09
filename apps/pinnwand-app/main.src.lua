-- Pinnwand (Paket pinnwand-app, Skript-Variante der Anzeige der eingebauten App "pinnwand"): die zuletzt empfangene
-- Familien-Nachricht als angeheftete Notiz. Skript-API Level 17 (inbox.latest()).
--
-- Der Nachrichtendienst bleibt in der Firmware (Senden aus dem Studio, ESP-NOW, Ablage auf dem NAS, Raum-Ziel, Nachtruhe,
-- Unterbrechungs-Anzeige beim Eintreffen): das Paket zeichnet NUR die Seite. Es holt nichts (kein on_fetch) und liest die Nachricht
-- bei jedem Zeichnen frisch aus inbox.latest(); neu gezeichnet wird, wie bei der eingebauten App, durch den Aktualisierungs-Takt
-- (refreshMinutes 1) und nach der Unterbrechungs-Anzeige. Eine Stilauswahl gibt es bewusst nicht (wie das Original), ein Widget
-- ebenfalls nicht.
--
-- Zeichnung 1:1 nach drawPinnwandApp() (teil14): Zettel mit Akzentleiste (drawAccentCard), Stecknadel auf der Oberkante,
-- Absender als Avatar-Chip mit Anfangsbuchstabe, Uhrzeit rechts, Trennlinie, Text linksbuendig. Bis 4 Zeilen grosse fette
-- Schrift, bei mehr Text die kleinere Schrift mit bis zu 8 Zeilen; was darueber hinausgeht, entfaellt ohne Auslassungszeichen.

local MAX_AGE = 3 * 3600 -- Sekunden
local DAYS_DE = {"Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"}
local DAYS_EN = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Letztes UTF-8-Zeichen entfernen
local function cutOne(s)
  local i = #s
  while i > 1 and (s:byte(i) & 0xC0) == 0x80 do i = i - 1 end
  return s:sub(1, i - 1)
end

-- Text auf hoechstens maxLines Zeilen umbrechen wie wrapUtf8ToLines() der Firmware: bevorzugt an Leerzeichen (so viele Woerter
-- wie in die Breite passen), ein zu langes Wort wird zeichenweise getrennt, der Rest ueber maxLines hinaus entfaellt.
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
      -- ein am Puffer-Ende halb abgeschnittenes Zeichen verwerfen
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

-- Uhrzeit der Nachricht fuers Zettel-Eck: "HH:MM" fuer heute, sonst "Mo, HH:MM" (Ortszeit der Nachricht kommt aus inbox.latest().at)
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

-- Anfangsbuchstabe des Absenders (ganzes UTF-8-Zeichen, ASCII gross)
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
  -- Zettel (drawAccentCard): weiss, schwarzer Rand, Akzentleiste links
  draw.rect(cardX, cardY, cardW, cardH, color.WHITE, true, 18)
  draw.rect(cardX, cardY, cardW, cardH, color.BLACK, false, 18)
  draw.rect(cardX + 6, cardY + 6, 5, cardH - 12, color.ACCENT, true, 2)

  -- Stecknadel: Kopf zur Haelfte auf der Zettel-Oberkante
  draw.circle(cx, cardY, 10, color.ACCENT, true)
  draw.circle(cx, cardY, 10, color.BLACK, false)
  draw.circle(cx, cardY, 3, color.WHITE, true)

  local pad = 28
  local left = cardX + pad
  local right = cardX + cardW - pad
  local width = right - left

  -- Kopfzeile des Zettels: Avatar-Chip + Name links, Uhrzeit rechts
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

  -- Nachricht: bis 4 Zeilen grosse fette Schrift (Zeilenabstand 34), sonst kleinere Schrift mit bis zu 8 Zeilen (24)
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

-- Nachricht anpinnen (Einstellungsknopf "send"): die Felder Absender/Nachricht/Anzeigen auf hat das Formular vorher gespeichert.
-- inbox.send() nutzt dieselbe Firmware-Routine wie der Studio-Knopf: Anzeige hier, Funk (ESP-NOW) und Ablage auf dem NAS.
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
