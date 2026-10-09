-- Layout-Bausteine fuer die drei Stile (store/lib/ui.lua)

-- Hinweis mittig (Leerzustand, Fehler, "Wird geladen ...").
local function notice(icon, line1, line2)
  local cx = draw.width // 2
  draw.icon(icon, cx - 24, 170, 48, color.ACCENT)
  draw.text(cx, 260, line1, "normal", color.BLACK, "center")
  if line2 ~= nil then draw.text(cx, 290, line2, "small", color.BLACK, "center") end
end

-- Zeilenliste (Slate/Nano): wie viele Zeilen passen, mit Mindest- und Hoechsthoehe je Zeile.
-- Gibt shown, rowH, truncated zurueck. hint = Platz fuer die Zeile "+n weitere" (nur bei truncated).
local function rowLayout(n, top, bottom, minH, maxH, hint)
  local avail = bottom - top
  local fit = math.max(1, avail // minH)
  local shown = math.min(n, fit)
  local truncated = shown < n
  if truncated and hint then avail = avail - hint end
  local rowH = avail // math.max(shown, 1)
  if rowH > maxH then rowH = maxH end
  return shown, rowH, truncated
end

-- Kachelraster (Bento): gibt eine Funktion zurueck, die fuer Kachel i (1..n) x, y, w, h liefert.
local function gridLayout(n, cols, top, bottom, margin, gap, maxTileH)
  local rows = (n + cols - 1) // cols
  local tileW = (draw.width - 2 * margin - (cols - 1) * gap) // cols
  local tileH = ((bottom - top) - (rows - 1) * gap) // math.max(rows, 1)
  if maxTileH and tileH > maxTileH then tileH = maxTileH end
  return function(i)
    local col, row = (i - 1) % cols, (i - 1) // cols
    return margin + col * (tileW + gap), top + row * (tileH + gap), tileW, tileH
  end, tileW, tileH
end

-- Karte mit Akzentbalken links (wie drawAccentCard() der eingebauten Apps); c = Farbe des Balkens.
local function card(x, y, w, h, c, r)
  r = r or 10
  draw.rect(x, y, w, h, color.WHITE, true, r)
  draw.rect(x, y, w, h, color.BLACK, false, r)
  draw.rect(x + 6, y + 6, 5, h - 12, c or color.ACCENT, true, 2)
end

-- Rechtsbuendige Spalten fuer Tabellen (Nano): gibt die linke Kante jeder Spalte zurueck.
-- widths = Liste der Spaltenbreiten (inkl. Abstand), rightEdge = rechte Kante der letzten Spalte.
local function columns(widths, rightEdge)
  local total = 0
  for _, w in ipairs(widths) do total = total + w end
  local xs, x = {}, rightEdge - total
  for i, w in ipairs(widths) do xs[i] = x; x = x + w end
  return xs
end

-- Text auf hoechstens maxLines Zeilen umbrechen (an Leerzeichen, letzte Zeile wird gekuerzt).
local function wrapLines(s, width, font, maxLines)
  local lines, line = {}, ""
  for word in s:gmatch("%S+") do
    local try = line == "" and word or (line .. " " .. word)
    if draw.measure(try, font) <= width or line == "" then
      line = try
    else
      lines[#lines + 1] = line
      line = word
      if #lines == maxLines then break end
    end
  end
  if #lines < maxLines and line ~= "" then lines[#lines + 1] = line end
  -- einzelne zu lange Woerter hart kuerzen
  for i = 1, #lines do
    if draw.measure(lines[i], font) > width then
      local l = lines[i]
      while #l > 1 and draw.measure(l, font) > width do
        l = l:sub(1, #l - 1)
        while #l > 1 and (l:byte(#l) & 0xC0) == 0x80 do l = l:sub(1, #l - 1) end
      end
      lines[i] = l
    end
  end
  return lines
end
