-- Bild des Tages: Wikimedia Commons "Bild des Tages" (ohne Schluessel) oder NASA "Astronomy Picture of the Day".
-- Skript-API Level 18 (http.image mit ram = true). Das Bild liegt im Arbeitsspeicher und wird nach einem Neustart neu geladen.
-- >>> store/lib/theme.lua (erzeugt, dort aendern)
-- Stil-Bausteine (store/lib/theme.lua): setStyle(), card(), panel(), widgetFrame(), pill(), pbar()
-- Fuenf Stile: Relief (erhaben, Hartschatten), Klar (Apple: farbige Kacheln ohne Rand), Bento ("cards": Akzentbalken),
-- Slate ("flat") und Nano ("compact"). Relief und Klar nutzen das Kartenlayout der App, aber mit eigener Optik.
local theme = { s = "cards" }
local function light(c) return c == color.YELLOW or c == color.WHITE end
local function inkOf(c)
  if c == color.ACCENT then return color.ACCENT_INK elseif c == color.ACCENT_INK then return color.ACCENT end
  return light(c) and color.BLACK or color.WHITE
end

-- Klar: gefuellte Flaechen werden gemerkt. Schwarz (auf dunkler Flaeche) und die Flaechenfarbe selbst zeichnen darin
-- in der passenden Schriftfarbe (weiss auf Blau, schwarz auf Gelb), damit jede App ohne Umbau lesbar bleibt.
local tiles, raw, pts = {}, nil, {}
local function tileInk(x, y, c, fill)
  if theme.s ~= "klar" then return c end
  if (not fill or c ~= color.WHITE) and #pts < 400 then pts[#pts + 1] = x; pts[#pts + 1] = y end -- schon gezeichneter Inhalt (panel() fuellt nur leere Flaechen)
  for i = #tiles, 1, -1 do
    local t = tiles[i]
    if x >= t[1] and x < t[3] and y >= t[2] and y < t[4] then
      local f, i = t[5], t[6]
      if c == f or (f == color.ACCENT and c == color.ACCENT_TEXT) then return i end
      if c == color.BLACK and not fill and not light(f) and f ~= color.ACCENT_INK then return i end -- Schrift/Linien, keine schwarzen Flaechen
      if c == color.ACCENT_INK and f ~= color.ACCENT then return light(f) and color.BLACK or color.WHITE end
      if not fill and not light(f) and not light(c) and c ~= color.ACCENT_INK then return i end -- bunte Schrift auf farbiger Kachel waere kaum lesbar
      return c
    end
  end
  return c
end
local function klarHook()
  if raw then return end
  raw = { text = draw.text, wrap = draw.wrap, line = draw.line, rect = draw.rect, circle = draw.circle, triangle = draw.triangle, icon = draw.icon }
  draw.text = function(x, y, s, f, c, ...) return raw.text(x, y, s, f, tileInk(x, y - 4, c), ...) end
  draw.wrap = function(x, y, w, s, f, c, ...) return raw.wrap(x, y, w, s, f, tileInk(x, y, c), ...) end
  draw.line = function(a, b, c2, d, c) return raw.line(a, b, c2, d, tileInk((a + c2) // 2, (b + d) // 2, c)) end
  draw.circle = function(x, y, r, c, f)
    c = tileInk(x, y, c, f)
    if f and theme.s == "klar" and r >= 8 and #tiles < 120 then tiles[#tiles + 1] = { x - r, y - r, x + r, y + r, c, inkOf(c) } end
    return raw.circle(x, y, r, c, f)
  end
  draw.triangle = function(a, b, c2, d, e, f, c, fl) return raw.triangle(a, b, c2, d, e, f, tileInk((a + c2 + e) // 3, (b + d + f) // 3, c), fl) end
  draw.icon = function(n, x, y, z, c) return raw.icon(n, x, y, z, tileInk(x + z // 2, y + z // 2, c)) end
  draw.rect = function(x, y, w, h, c, fill, r)
    c = tileInk(x + w // 2, y + h // 2, c, fill)
    if fill and theme.s == "klar" and w >= 16 and h >= 12 and #tiles < 120 then tiles[#tiles + 1] = { x, y, x + w, y + h, c, inkOf(c) } end
    return raw.rect(x, y, w, h, c, fill, r)
  end
end

-- Stil-Weiche: setStyle(ctx.cfg.style) vor dem Zeichnen.
local function setStyle(s)
  theme.s = ({ bento = "cards", slate = "flat", nano = "compact" })[s] or s or "cards"
  tiles, pts = {}, {}
  if theme.s == "klar" then klarHook() end
  if theme.s == "relief" or theme.s == "klar" then return "cards" end
  return s
end

-- Karte: Bento = weisse Karte, duenner Rand, Akzentbalken links. Relief = erhaben (harter Schatten, kraeftiger Rand,
-- kein Balken). Klar = farbige Kachel ohne Rand (Farbe c, sonst Akzent); Schrift darin passt sich an.
local function card(x, y, w, h, c, r, nobar)
  if theme.s == "relief" then
    r = r or 12
    draw.rect(x + 6, y + 6, w, h, color.BLACK, true, r)
    draw.rect(x, y, w, h, color.WHITE, true, r)
    draw.rect(x, y, w, h, color.BLACK, false, r)
    draw.rect(x + 1, y + 1, w - 2, h - 2, color.BLACK, false, r)
    return
  elseif theme.s == "klar" then
    if not c or c == color.BLACK then c = color.ACCENT end
    draw.rect(x, y, w, h, c, true, math.min((r or 18) + 8, 30))
    return
  end
  r = r or 10
  draw.rect(x, y, w, h, color.WHITE, true, r)
  draw.rect(x, y, w, h, color.BLACK, false, r)
  if not nobar then draw.rect(x + 6, y + 6, 5, h - 12, c or color.ACCENT, true, 2) end
end

-- Umrandete Flaeche (auch nach dem Inhalt aufrufbar): Relief = Schatten an Unter- und Rechtskante, Klar = kraeftiger farbiger Rand.
-- Kleine Flaechen (Haekchen, Punkte) bekommen weder Schatten noch Doppelrahmen.
local function panel(x, y, w, h, r, c)
  c = c or color.BLACK
  local big = w >= 60 and h >= 30
  if theme.s == "relief" and big then
    -- Schatten folgt der Rundung der Kachel (wie bei card): Geraden plus Eck-Sicheln aus Vierecken, nichts ueberdeckt den Inhalt
    local s = 5
    local rr = math.max(2, math.min(r or 12, 40, w // 2, h // 2))
    local function sichel(cx, cy, a0, a1)
      local n = 5
      for i = 0, n - 1 do
        local u, v = math.rad(a0 + (a1 - a0) * i / n), math.rad(a0 + (a1 - a0) * (i + 1) / n)
        local c1, s1, c2, s2 = math.cos(u) * rr, math.sin(u) * rr, math.cos(v) * rr, math.sin(v) * rr
        local function f(v) return math.floor(v + 0.5) end
        draw.polygon({f(cx + c1), f(cy + s1), f(cx + c1 + s), f(cy + s1 + s), f(cx + c2 + s), f(cy + s2 + s), f(cx + c2), f(cy + s2)}, color.BLACK, true)
      end
    end
    draw.rect(x + w, y + rr, s, h - 2 * rr + s, color.BLACK, true)
    draw.rect(x + rr, y + h, w - 2 * rr + s, s, color.BLACK, true)
    sichel(x + w - rr, y + h - rr, 0, 90)      -- unten rechts
    sichel(x + w - rr, y + rr, -45, 0)         -- oben rechts
    sichel(x + rr, y + h - rr, 90, 135)        -- unten links
  end
  if theme.s == "klar" and big then
    c = c == color.BLACK and color.ACCENT or c
    for i = 1, #pts, 2 do -- schon Inhalt in der Flaeche: nur farbiger Rand, sonst farbige Kachel
      if pts[i] > x and pts[i] < x + w and pts[i + 1] > y and pts[i + 1] < y + h then
        for k = 0, 2 do draw.rect(x + k, y + k, w - 2 * k, h - 2 * k, c, false, r) end
        return
      end
    end
    draw.rect(x, y, w, h, c, true, math.min((r or 12) + 8, 30))
    return
  end
  draw.rect(x, y, w, h, c, false, r)
end

-- Widget-Rahmen je Stil; gibt die Box fuer den Inhalt zurueck. Bump = Karte mit Schatten, Gamut = farbige Kachel, Tile = duenne Karte
-- mit Akzentbalken, Ledger = Linie oben und unten, Nibble = schmaler Akzentstrich links und eine Schriftstufe kleiner.
local function widgetFrame(box)
  local st = theme.s
  local inner = {}
  for k, v in pairs(box) do inner[k] = v end
  if st == "flat" then
    draw.line(box.x + 6, box.y + 1, box.x + box.w - 6, box.y + 1, color.BLACK)
    draw.line(box.x + 6, box.y + box.h - 2, box.x + box.w - 6, box.y + box.h - 2, color.BLACK)
    inner.y, inner.h = box.y + 2, box.h - 4
    return inner
  elseif st == "compact" then
    draw.rect(box.x + 3, box.y + 4, 2, box.h - 8, color.ACCENT, true)
    inner.font = math.max(-1, (box.font or 0) - 1)
    return inner
  elseif st ~= "relief" and st ~= "klar" and st ~= "cards" then
    return box
  end
  if st == "cards" then -- duenne Karte fast randlos, damit der Inhalt seinen Platz behaelt
    card(box.x + 1, box.y, box.w - 2, box.h - 1, color.ACCENT, 10)
    inner.x, inner.y, inner.w, inner.h = box.x + 10, box.y + 2, box.w - 14, box.h - 4
    return inner
  end
  local x, y, w, h = box.x + 4, box.y + 2, box.w - 14, box.h - 12
  card(x, y, w, h, color.ACCENT, st == "relief" and 12 or 18)
  local pad = st == "relief" and 14 or 8
  if box.h < 60 then -- niedriges Widget: Innenabstand oben/unten klein halten, sonst bleibt fuer den Inhalt kaum Hoehe
    inner.x, inner.y, inner.w, inner.h = box.x + pad, box.y + 3, box.w - pad - 16, box.h - 13
  else
    inner.x, inner.y, inner.w, inner.h = box.x + pad, box.y + 8, box.w - pad - 16, box.h - 20
  end
  return inner
end

-- Erhabene Pille (Relief: harter Schatten, Klar: flach gefuellt, sonst nur Rahmen); Text optional, zentriert.
local function pillW(txt, font, h, minw)
  return math.max(minw or 0, draw.measure(txt, font or "small") + h)
end
local FOFF = { small = 5, s8 = 6, normal = 6, n10 = 7, medium = 9, large = 13 } -- halbe Ziffernhoehe je Schrift: Text mittig in Pillen
local function pill(x, y, w, h, c, txt, font, tc)
  if txt then w = pillW(txt, font, h, w) end   -- variable Breite: waechst mit dem Text
  local r = h // 2
  c = c or color.ACCENT
  if theme.s == "relief" then
    draw.rect(x + 3, y + 3, w, h, color.BLACK, true, r)
    draw.rect(x, y, w, h, c, true, r)
    draw.rect(x, y, w, h, color.BLACK, false, r)
  elseif theme.s == "klar" then
    draw.rect(x, y, w, h, c, true, r)
  else
    draw.rect(x, y, w, h, c, false, r)
    tc = tc or (c == color.ACCENT and color.ACCENT_TEXT or c)
  end
  if txt then draw.text(x + w // 2, y + h // 2 + (FOFF[font or "small"] or 6), txt, font or "small", tc or (c == color.ACCENT and color.ACCENT_INK or color.WHITE), "center") end
  return w
end

-- Fortschrittsbalken; Relief mit Schatten unter der Rinne, Klar als schmale runde Rinne.
local function pbar(x, y, w, h, frac, c)
  frac = math.max(0, math.min(1, frac or 0))
  c = c or color.ACCENT
  local r = h // 2
  if theme.s == "relief" then draw.rect(x + 3, y + 3, w, h, color.BLACK, true, r) ; draw.rect(x, y, w, h, color.WHITE, true, r) end
  draw.rect(x, y, w, h, color.BLACK, false, r)
  local fw = math.floor((w - 4) * frac)
  if fw > h - 4 then draw.rect(x + 2, y + 2, fw, h - 4, c, true, (h - 4) // 2)
  elseif fw > 2 then draw.rect(x + 2, y + 2, fw, h - 4, c, true) end
end

-- Markierte Tabellenzeile (eigener Verein): Relief = Rahmen mit hartem Schatten, Klar = kraeftiger Akzentrahmen, sonst duenner Rahmen.
local function mark(x, y, w, h, r)
  if theme.s == "relief" then
    draw.rect(x + 3, y + 3, w, h, color.BLACK, true, r)
    draw.rect(x, y, w, h, color.WHITE, true, r)
    draw.rect(x, y, w, h, color.BLACK, false, r)
    draw.rect(x + 1, y + 1, w - 2, h - 2, color.BLACK, false, r)
  elseif theme.s == "klar" then
    for k = 0, 2 do draw.rect(x + k, y + k, w - 2 * k, h - 2 * k, color.ACCENT, false, r) end
  else
    draw.rect(x, y, w, h, color.BLACK, false, r)
  end
end
-- <<< store/lib/theme.lua
-- >>> store/lib/text.lua (erzeugt, dort aendern)
-- Textbausteine fuer Pakete (store/lib/text.lua)

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Auf n Zeichen (UTF-8) kuerzen.
local function cut(s, n)
  if #s <= n then return s end
  local count, i = 0, 1
  while i <= #s do
    local b = s:byte(i)
    if b < 0x80 then i = i + 1 elseif b >= 0xF0 then i = i + 4 elseif b >= 0xE0 then i = i + 3 else i = i + 2 end
    count = count + 1
    if count >= n then break end
  end
  return s:sub(1, i - 1)
end

-- Steuerzeichen (Tab/Zeilenumbruch trennen oft die Felder) raus, auf n Zeichen kuerzen.
local function clean(s, n)
  s = tostring(s or ""):gsub("%c", " ")
  return cut(trim(s), n)
end

-- Auf Pixelbreite w kuerzen (kein Auslassungszeichen: das Display kennt es nicht).
local function fit(s, w, font)
  while #s > 1 and draw.measure(s, font) > w do
    s = s:sub(1, #s - 1)
    while #s > 1 and (s:byte(#s) & 0xC0) == 0x80 do s = s:sub(1, #s - 1) end
    if #s > 1 and s:byte(#s) >= 0xC0 then s = s:sub(1, #s - 1) end -- halb abgeschnittenes Zeichen (z.B. ss) nicht als ? zeigen
  end
  return s
end

-- Zahl mit Komma statt Punkt (deutsche Schreibweise), digits Nachkommastellen.
local function num(x, digits, en)
  local s = string.format("%." .. digits .. "f", x)
  if not en then s = s:gsub("%.", ",") end
  return s
end

-- Antwort-JSON, das beim 24-KB-Limit abgeschnitten wurde: behaelt alle vollstaendigen Listenelemente und
-- schliesst die offenen Klammern. level = Verschachtelungstiefe der Liste, in der abgeschnitten sein darf
-- (Standard 1: ein Element der obersten Liste/des obersten Objekts, z. B. {"stations":[{..},{..}] hat Tiefe 2).
local function decodeCut(body, level)
  local doc = json.decode(body)
  if type(doc) == "table" then return doc end
  level = level or 2
  local open, inStr, esc, safe, safeOpen = {}, false, false, nil, nil
  for i = 1, #body do
    local c = body:byte(i)
    if inStr then
      if esc then esc = false elseif c == 92 then esc = true elseif c == 34 then inStr = false end
    elseif c == 34 then inStr = true
    elseif c == 123 or c == 91 then open[#open + 1] = c
    elseif c == 125 or c == 93 then
      open[#open] = nil
      if #open == level then
        safe = i
        safeOpen = { table.unpack(open) }
      end
    end
  end
  if safe == nil then return nil end
  local head = body:sub(1, safe)
  for i = #safeOpen, 1, -1 do head = head .. (safeOpen[i] == 123 and "}" or "]") end
  doc = json.decode(head)
  if type(doc) == "table" then return doc end
  return nil
end
-- <<< store/lib/text.lua
-- >>> store/lib/ui.lua (erzeugt, dort aendern)
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
        if #l > 1 and l:byte(#l) >= 0xC0 then l = l:sub(1, #l - 1) end
      end
      lines[i] = l
    end
  end
  return lines
end
-- <<< store/lib/ui.lua

local PIC = "potd"

-- Wikitext -> Klartext (Verweise [[a|b]] -> b, Vorlagen und Formatierung raus)
local function wiki(s)
  s = tostring(s or "")
  for _ = 1, 3 do s = s:gsub("{{[^{}]*}}", "") end
  s = s:gsub("%[%[[^%]|]*|([^%]]*)%]%]", "%1")
  s = s:gsub("%[%[:?([^%]]*)%]%]", "%1")
  s = s:gsub("%[https?://%S+ ([^%]]*)%]", "%1")
  s = s:gsub("'''?", "")
  s = s:gsub("<[^>]*>", "")
  s = s:gsub("&nbsp;", " "):gsub("&amp;", "&"):gsub("&quot;", '"'):gsub("&#039;", "'")
  s = s:gsub("%s+", " ")
  return clean(s, 700)
end

local function stripTags(s)
  s = tostring(s or ""):gsub("<[^>]*>", ""):gsub("&nbsp;", " "):gsub("&amp;", "&"):gsub("&quot;", '"'):gsub("&#039;", "'")
  return clean(s, 120)
end

local function fileTitle(name)
  local t = name:gsub("^[Ff]ile:", ""):gsub("%.%w+$", ""):gsub("_", " ")
  return clean(t, 90)
end

local function loadImage(url, w, h)
  local ok, err = http.image(url, PIC, w, h, { ram = true })
  if ok then return true end
  -- Zu gross fuer den Download (300 KB)? Wikimedia-Vorschaubild in kleinerer Breite nochmal versuchen.
  local small = url:gsub("/(%d+)px%-", "/360px-")
  if small ~= url then
    ok, err = http.image(small, PIC, w, h, { ram = true })
    if ok then return true end
  end
  return false, err
end

local function setCommon(ctx, title, desc, credit, src, day, hasImg, err)
  ctx.data.set("title", title)
  ctx.data.set("desc", desc)
  ctx.data.set("credit", credit)
  ctx.data.set("src", src)
  ctx.data.set("day", day)
  ctx.data.set("img", hasImg and "1" or "0")
  ctx.data.set("err", err or "")
end

-- Quelle 1: Wikimedia Commons
local function fetchCommons(ctx, day, en)
  local ex = "{{Potd/" .. day .. "}}@@{{Potd/" .. day .. " (en)}}@@{{Potd/" .. day .. " (de)}}"
  local body, err = http.get("https://commons.wikimedia.org/w/api.php?action=expandtemplates&format=json&prop=wikitext&text=" .. text.url_encode(ex), 12288)
  if not body then return nil, "Commons: " .. tostring(err) end
  local doc = json.decode(body)
  local wt = doc and doc.expandtemplates and doc.expandtemplates.wikitext
  if not wt then return nil, "Commons: keine Antwort" end
  local file, d_en, d_de = wt:match("^(.-)@@(.-)@@(.*)$")
  if not file then return nil, "Commons: unbekanntes Format" end
  file = clean(file, 200)
  if file == "" or file:find("Template:", 1, true) then return nil, "Heute noch kein Bild" end
  if not file:lower():match("^file:") then file = "File:" .. file end
  local desc = en and d_en or d_de
  if desc:find("Template:", 1, true) or #wiki(desc) < 3 then desc = d_en end
  desc = wiki(desc)

  time.sleep(300)
  local url = "https://commons.wikimedia.org/w/api.php?action=query&format=json&prop=imageinfo&iiprop=url%7Cextmetadata&iiurlwidth=560"
    .. "&iiextmetadatafilter=Artist%7CLicenseShortName%7CObjectName&titles=" .. text.url_encode(file)
  local b2, e2 = http.get(url, 12288)
  if not b2 then return nil, "Commons: " .. tostring(e2) end
  local d2 = json.decode(b2)
  local page = d2 and d2.query and d2.query.pages
  local info
  if page then for _, p in pairs(page) do info = p.imageinfo and p.imageinfo[1] end end
  if not info or not info.thumburl then return nil, "Commons: kein Bild" end
  local md = info.extmetadata or {}
  local title = md.ObjectName and stripTags(md.ObjectName.value) or ""
  if title == "" or #title > 90 then title = fileTitle(file) end
  local artist = md.Artist and stripTags(md.Artist.value) or ""
  local lic = md.LicenseShortName and stripTags(md.LicenseShortName.value) or ""
  local credit = cut(artist, 50)
  if lic ~= "" then credit = (credit ~= "" and (credit .. ", ") or "") .. cut(lic, 24) end
  time.sleep(300)
  local ok, ierr = loadImage(info.thumburl, 520, 396)
  return { title = title, desc = desc, credit = credit, img = ok, err = ok and "" or ("Bild: " .. tostring(ierr)) }
end

-- Quelle 2: NASA APOD (eigener Schluessel, sonst DEMO_KEY mit Tageslimit); Texte nur auf Englisch
local function fetchApod(ctx, day)
  local key = ctx.cfg.apodKey
  if key == nil or key == "" then key = "DEMO_KEY" end
  local body, err = http.get("https://api.nasa.gov/planetary/apod?thumbs=true&api_key=" .. text.url_encode(key), 12288)
  if not body then return nil, "NASA: " .. tostring(err) end
  local d = json.decode(body)
  if type(d) ~= "table" or not d.title then return nil, "NASA: Antwort ohne Bild (Limit erreicht?)" end
  local src = d.media_type == "image" and d.url or d.thumbnail_url
  local ok, ierr = false, "kein Bild (Video)"
  if src then
    time.sleep(300)
    ok, ierr = loadImage(src, 520, 396)
  end
  local credit = d.copyright and ("(c) " .. clean(d.copyright, 50)) or "NASA"
  return { title = clean(d.title, 90), desc = clean(d.explanation, 700), credit = credit, img = ok, err = ok and "" or ("Bild: " .. tostring(ierr)) }
end

function on_fetch(ctx)
  local day = time.today()
  if not day then return false end
  local src = ctx.cfg.source == "apod" and "apod" or "commons"
  if ctx.data.get("day") == day and ctx.data.get("src") == src and ctx.data.get("img") == "1" and draw.image_size(PIC) then
    return true -- schon geladen
  end
  local en = (ctx.lang == "en")
  local r, err
  if src == "apod" then r, err = fetchApod(ctx, day) else r, err = fetchCommons(ctx, day, en) end
  if not r then
    log("Bild des Tages: " .. tostring(err))
    ctx.data.set("err", clean(err, 120))
    return false
  end
  setCommon(ctx, r.title, r.desc, r.credit, src, day, r.img, r.err)
  return true
end

local SAMPLE = false -- Vorschau (ohne Netz): gezeichnetes Beispielbild statt Foto
local smp = {}
local function dget(ctx, k)
  if SAMPLE and smp[k] ~= nil then return smp[k] end
  return ctx.data.get(k)
end

local function imgBox()
  if SAMPLE then return 520, 360 end
  local w, h = draw.image_size(PIC)
  return w, h
end

local function blit(x, y)
  if not SAMPLE then draw.image(PIC, x, y); return end
  local w, h = 520, 360
  draw.rect(x, y, w, h, color.BLUE, true)
  draw.rect(x, y + h * 6 // 10, w, h * 4 // 10, color.GREEN, true)
  draw.rect(x + 360, y + 50, 70, 70, color.YELLOW, true, 35)
  draw.rect(x + 40, y + h * 6 // 10 - 50, 150, 100, color.WHITE, true, 50)
end

local function drawText(x, y, w, ctx, en, full)
  local title = dget(ctx, "title") or ""
  local lines = draw.wrap(x, y, w, title, "medium", color.BLACK)
  y = y + lines * 32 + 6
  local desc = dget(ctx, "desc") or ""
  if desc ~= "" then
    local room = (draw.height - 70 - y) // 24
    if not full then room = math.min(room, 6) end
    local shown = wrapLines(desc, w, "normal", math.max(room, 1))
    for _, ln in ipairs(shown) do
      draw.text(x, y + 20, ln, "normal", color.BLACK, "left")
      y = y + 24
    end
  end
end

function on_draw(ctx, page)
  local en = (ctx.lang == "en")
  setStyle(ctx.cfg.style)
  draw.clear(color.WHITE)
  SAMPLE = false
  local title = ctx.data.get("title")
  if ctx.data.get("demo") == "1" or (title == nil and ctx.preview == true) then
    SAMPLE = true
    smp.title = en and "Sunrise over the lake" or "Sonnenaufgang am See"
    smp.desc = en and "A calm morning at the lake: mist rises over the water while the first light reaches the hills on the far shore." or "Ein ruhiger Morgen am See: Nebel steigt über dem Wasser auf, während das erste Licht die Hügel am anderen Ufer erreicht."
    smp.credit = "Beispiel, CC BY-SA 4.0"
    smp.src = "commons"
    title = smp.title
  end
  if title == nil then
    local err = dget(ctx, "err") or ""
    if err ~= "" then
      notice("error", en and "Picture not loaded" or "Bild nicht geladen", err)
    else
      notice("loading", en and "Loading ..." or "Wird geladen ...")
    end
    return
  end
  local fancy = theme.s == "relief" or theme.s == "klar" or theme.s == "cards"
  local credit = dget(ctx, "credit") or ""
  local srcName = dget(ctx, "src") == "apod" and "NASA APOD" or "Wikimedia Commons"
  local hasImg = SAMPLE or (dget(ctx, "img") == "1" and draw.image_size(PIC) ~= nil)
  local tall = draw.height > draw.width
  local top, bottom = draw.top + 14, draw.height - 16

  if page == 2 or not hasImg then
    -- Textseite: Titel, ganze Beschreibung, Quelle
    local x, y, w, h = 40, top, draw.width - 80, bottom - top
    if fancy then card(x, y, w, h, color.ACCENT, theme.s == "relief" and 16 or 22) end
    drawText(x + 28, y + 40, w - 56, ctx, en, true)
    draw.text(x + 28, y + h - 18, fit(srcName .. (credit ~= "" and (" - " .. credit) or ""), w - 56, "small"), "small", color.ACCENT_TEXT, "left")
    if not hasImg then
      local e = dget(ctx, "err") or ""
      if e ~= "" then draw.text(x + w - 28, y + 24, fit(e, w // 2, "small"), "small", color.RED, "right") end
    end
    return
  end

  local iw, ih = imgBox()
  if tall then
    local ix = (draw.width - iw) // 2
    if fancy and theme.s == "relief" then draw.rect(ix + 5, top + 5, iw, ih, color.BLACK, true) end
    blit(ix, top)
    draw.rect(ix, top, iw, ih, color.BLACK, false)
    local ty = top + ih + 26
    local lines = draw.wrap(24, ty, draw.width - 48, dget(ctx, "title") or "", "medium", color.BLACK)
    draw.text(24, bottom - 8, fit(srcName .. (credit ~= "" and (" - " .. credit) or ""), draw.width - 48, "small"), "small", color.ACCENT_TEXT, "left")
    return
  end
  -- Querformat: Bild links (hoechstens 520 x 396), Titel und Kurztext rechts
  local bx, bw, bh = 36, 520, bottom - top
  local ix = bx + (bw - iw) // 2
  local iy = top + (bh - ih) // 2
  if theme.s == "relief" then draw.rect(ix + 5, iy + 5, iw, ih, color.BLACK, true) end
  blit(ix, iy)
  if theme.s ~= "klar" then draw.rect(ix, iy, iw, ih, color.BLACK, false) end
  local tx = bx + bw + 26
  local tw = draw.width - tx - 28
  if tw < 100 then return end
  if fancy then card(tx - 14, top, tw + 28 - 4, bh, color.ACCENT, theme.s == "relief" and 16 or 22); tx = tx + 8; tw = tw - 16 end
  drawText(tx, top + 40, tw, ctx, en, false)
  draw.text(tx, bottom - 14, fit(credit, tw, "small"), "small", color.ACCENT_TEXT, "left")
end

function on_widget(ctx, box)
  setStyle(ctx.cfg.style)
  box = widgetFrame(box)
  local en = (ctx.lang == "en")
  local title = ctx.data.get("title")
  if ctx.sample or ctx.data.get("demo") == "1" then title = en and "Sunrise over the lake" or "Sonnenaufgang am See" end
  if title == nil then
    draw.text(box.x + 12, box.y + 22, en and "No data yet" or "Noch keine Daten", "small", color.BLACK, "left")
    return
  end
  local hasImg = ctx.data.get("img") == "1" and draw.image_size(PIC) ~= nil and not ctx.sample and ctx.data.get("demo") ~= "1"
  if hasImg and box.h >= 70 and box.w >= 120 then
    local iw, ih = draw.image_size(PIC)
    local maxW = box.w >= 220 and (box.w * 55 // 100) or (box.w - 12)
    local maxH = box.w >= 220 and (box.h - 8) or (box.h * 60 // 100)
    local s = math.min(maxW / iw, maxH / ih)
    local dw, dh = math.floor(iw * s), math.floor(ih * s)
    draw.image(PIC, box.x + 6, box.y + 4, dw, dh)
    if box.w >= 220 then
      draw.wrap(box.x + dw + 16, box.y + 22, box.w - dw - 22, title, "small", color.BLACK)
    else
      draw.text(box.x + 6, box.y + box.h - 6, fit(title, box.w - 12, "small"), "small", color.BLACK, "left")
    end
    return
  end
  draw.wrap(box.x + 12, box.y + 22, box.w - 20, title, box.h >= 60 and "normal" or "small", color.BLACK)
end
