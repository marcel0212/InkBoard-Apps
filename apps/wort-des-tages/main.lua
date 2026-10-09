-- Wort des Tages (Skript-Variante): holt das Tageswort von Merriam-Webster,
-- uebersetzt Wort, Bedeutung und Beispielsatz per MyMemory ins Deutsche und
-- zeigt je nach Display-Sprache (ctx.lang) Original oder Uebersetzung.
-- Skript-API Level 1 (docs/V2_APPSTORE.md). Netzzugriff nur auf die im
-- Manifest unter permissions.net erlaubten Hosts.

local FEED = "https://www.merriam-webster.com/wotd/feed/rss2"
local TRANSLATE = "https://api.mymemory.translated.net/get?langpair=en%7Cde&q="

-- Farben: die Akzentfarbe ist die globale Einstellung des Geraets (color.ACCENT*), wie bei allen Apps.

-- Erster Buchstabe gross (ASCII und deutsche Umlaute).
local function capFirst(s)
  if s == nil or s == "" then return "" end
  local b = s:byte(1)
  if b >= 97 and b <= 122 then
    return string.char(b - 32) .. s:sub(2)
  end
  if b == 0xC3 then
    local c = s:byte(2)
    if c == 0xA4 or c == 0xB6 or c == 0xBC then
      return "\xC3" .. string.char(c - 0x20) .. s:sub(3)
    end
  end
  return s
end

local function utf8Char(n)
  if n < 128 then return string.char(n) end
  if n < 2048 then
    return string.char(192 + n // 64, 128 + n % 64)
  end
  return string.char(224 + n // 4096, 128 + (n // 64) % 64, 128 + n % 64)
end

local function decodeEntities(s)
  s = s:gsub("&#(%d+);", function(d) return utf8Char(tonumber(d)) end)
  s = s:gsub("&quot;", '"'):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")
  return s
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Uebersetzt Englisch -> Deutsch. Gibt Text oder nil, "quota" | "fail" zurueck.
local function translate(s)
  if s == nil or s == "" then return "" end
  local body = http.get(TRANSLATE .. text.url_encode(s))
  if body == nil then return nil, "fail" end
  local doc = json.decode(body)
  if type(doc) ~= "table" or type(doc.responseData) ~= "table" then return nil, "fail" end
  local t = doc.responseData.translatedText
  if type(t) ~= "string" then return nil, "fail" end
  if t:find("MYMEMORY WARNING", 1, true) == 1 then return nil, "quota" end
  t = trim(decodeEntities(t))
  if t == "" then return nil, "fail" end
  return t
end

-- Beispielsatz: Text nach "// " bis zum Ende des Absatzes.
local function extractExample(html)
  local a = html:find("// ", 1, true)
  if a == nil then return "" end
  local rest = html:sub(a + 3)
  local e = rest:find("</p>", 1, true)
  if e then rest = rest:sub(1, e - 1) end
  return trim(text.strip_html(rest))
end

function on_fetch(ctx)
  local body, err = http.get(FEED)
  if body == nil then
    log("Abruf fehlgeschlagen: " .. tostring(err))
    return false
  end
  local item = rss.parse(body)[1]
  if item == nil or item.title == nil then return false end

  local word = capFirst((item.title:gsub("[%. ]+$", "")))
  local def = capFirst(trim(item.merriam_shortdef or ""))
  local example = extractExample(item.description or "")

    -- Bereits uebersetztes Wort von heute: gespeicherte Uebersetzung behalten (spart Abrufe und
  -- verhindert, dass ein kurzer Fehler beim naechsten Auffrischen die gute Uebersetzung durch
  -- Englisch ersetzt).
  if ctx.data.get("wordEn") == word and ctx.data.get("tr") == "1" and ctx.data.get("wordDe") ~= nil then
    ctx.data.set("defEn", def)
    ctx.data.set("exEn", example)
    return true
  end

  -- Uebersetzung: Fehler sind nicht fatal, dann bleibt das Original (Englisch).
  -- Zwischen den Abrufen kurz warten, sonst lehnt der Server schnelle TLS-Verbindungen ab.
  -- Ein voruebergehender Fehler ("fail") wird einmal wiederholt; ein erreichtes Tageslimit ("quota") nicht.
  local function tryTranslate(s)
    local r, kind = translate(s)
    if r == nil and kind == "fail" then
      time.sleep(600)
      r, kind = translate(s)
    end
    return r, kind
  end
  local wordDe, defDe, exDe, failKind
  wordDe, failKind = tryTranslate(word)
  if wordDe and failKind == nil then
    time.sleep(400)
    defDe, failKind = tryTranslate(def)
    if defDe and example ~= "" then
      time.sleep(400)
      exDe, failKind = tryTranslate(example)
    end
  end
  local ok = wordDe ~= nil and defDe ~= nil and (example == "" or exDe ~= nil)
  if not ok then
    log("Uebersetzung nicht moeglich: " .. tostring(failKind))
    wordDe, defDe, exDe = nil, nil, nil
  end

  ctx.data.set("wordEn", word)
  ctx.data.set("defEn", def)
  ctx.data.set("exEn", example)
  ctx.data.set("wordDe", wordDe and capFirst(wordDe) or word)
  ctx.data.set("defDe", defDe and capFirst(defDe) or def)
  ctx.data.set("exDe", exDe or example)
  ctx.data.set("tr", ok and "1" or "0")
  return true
end

-- Aufgeschlagenes Buch aus Linien (wie das Symbol der eingebauten App).
local function bookIcon(x, y, size, col)
  local cx = x + size // 2
  local top = y + size // 4
  local bottom = y + size - size // 4
  local left = x + size // 6
  local right = x + size - size // 6
  local notch = size // 6
  draw.line(left, bottom, cx, bottom - notch, col)
  draw.line(cx, bottom - notch, right, bottom, col)
  draw.line(left, bottom, left, top, col)
  draw.line(right, bottom, right, top, col)
  draw.line(left, top, cx, top - notch, col)
  draw.line(cx, top - notch, right, top, col)
end

function on_draw(ctx, page)
  local en = (ctx.lang == "en")
  local accent = color.ACCENT

  -- Den Kopf (App-Name, Status, Uhrzeit) zeichnet die Firmware; clear gilt nur darunter.
  draw.clear(color.WHITE)

  local wordEn = ctx.data.get("wordEn")
  if wordEn == nil then
    draw.text(draw.width // 2, 250, en and "Loading..." or "Wird geladen...", "large", color.BLACK, "center")
    return
  end

  local word = en and wordEn or (ctx.data.get("wordDe") or wordEn)
  local def = en and (ctx.data.get("defEn") or "") or (ctx.data.get("defDe") or "")
  local example = en and (ctx.data.get("exEn") or "") or (ctx.data.get("exDe") or "")
  local translated = ctx.data.get("tr") == "1"

  local areaTop = draw.top + 14
  local areaBottom = draw.height - 20

  -- Linke Spalte: Akzentflaeche mit Buch, grossem Wort, Original-Hinweis.
  local panelX, panelW = 40, 240
  draw.rect(panelX, areaTop, panelW, areaBottom - areaTop, accent, true, 18)
  local tx, tw = panelX + 24, panelW - 48
  bookIcon(tx, areaTop + 26, 40, color.WHITE)
  draw.wrap(tx, areaTop + 26 + 40 + 38, tw, word, "large", color.WHITE)
  if not en then
    local metaY = areaBottom - 40
    if translated and word:lower() ~= wordEn:lower() then
      draw.text(tx, metaY, wordEn, "small", color.WHITE, "left")
      draw.text(tx, metaY + 16, "EN -> DE", "small", color.WHITE, "left")
    elseif not translated then
      draw.text(tx, metaY, "Original (Englisch)", "small", color.WHITE, "left")
    end
  end

  -- Rechte Spalte: Bedeutung und Beispiel.
  local cl = panelX + panelW + 32
  local cw = draw.width - 40 - cl
  -- Dekoratives Anfuehrungszeichen ueber der Bedeutung (wie die eingebaute App)
  draw.text(cl - 4, areaTop + 42, '"', "large", color.ACCENT_TEXT, "left")
  local cy = areaTop + 58
  draw.text(cl, cy, en and "MEANING" or "BEDEUTUNG", "small", color.ACCENT_TEXT, "left")
  cy = cy + 22
  local lines = draw.wrap(cl, cy, cw, def, "normal", color.BLACK)
  cy = cy + lines * 24

  if ctx.cfg.showExample and example ~= "" and cy < areaBottom - 60 then
    cy = cy + 14
    draw.line(cl, cy, cl + cw, cy, color.BLACK)
    cy = cy + 24
    draw.text(cl, cy, en and "EXAMPLE" or "BEISPIEL", "small", color.ACCENT_TEXT, "left")
    cy = cy + 22
    if #example > 240 then example = example:sub(1, 237) .. "..." end
    draw.wrap(cl, cy, cw, '"' .. example .. '"', "normal", color.BLACK)
  end
end

-- Widget: gleiche Stufen wie das eingebaute Widget (Wort; ab 90 px Hoehe Bedeutung,
-- ab 170 px Beispielsatz; Buch-Badge ab 170 px Breite). box = Inhaltsbereich unter dem Widget-Titel,
-- box.fh = volle Widget-Hoehe (daraus ergeben sich die Stufen). Rahmen/Titel/"Noch keine Daten" zeichnet die Firmware.
local function fit(s, w, font)
  while #s > 1 and draw.measure(s, font) > w do
    s = s:sub(1, #s - 1)
    while #s > 1 and (s:byte(#s) & 0xC0) == 0x80 do s = s:sub(1, #s - 1) end
  end
  return s
end

function on_widget(ctx, box)
  local en = (ctx.lang == "en")
  local wordEn = ctx.data.get("wordEn")
  if ctx.sample then -- Beispieldaten fuer die Widget-Vorschau im Dashboard-Editor (CHANGELOG 559)
    wordEn = "serendipity"
  elseif wordEn == nil then
    draw.text(box.x + 12, box.y + 16, en and "No data yet" or "Noch keine Daten", "small", color.BLACK, "left")
    return
  end
  local accent = color.ACCENT
  local word = en and wordEn or (ctx.data.get("wordDe") or wordEn)
  local def = en and (ctx.data.get("defEn") or "") or (ctx.data.get("defDe") or "")
  local example = en and (ctx.data.get("exEn") or "") or (ctx.data.get("exDe") or "")
  if ctx.sample then
    word = en and "serendipity" or "Zufallsglück"
    def = en and "A pleasant surprise found by chance." or "Eine angenehme Überraschung durch Zufall."
    example = en and "Meeting her was pure serendipity." or "Sie zu treffen war reines Zufallsglück."
  end
  local maxY = box.y + box.h - 4
  local top = box.y
  local textX = box.x + 12
  if box.w >= 170 and (maxY - top) >= 34 then
    local by = top + 2
    if by + 34 > maxY then by = maxY - 34 end
    draw.rect(textX, by, 34, 34, accent, true, 8)
    bookIcon(textX, by, 34, color.WHITE)
    textX = textX + 34 + 10
  end
  local textW = math.max(box.x + box.w - textX - 6, 20)
  -- Schriftgroesse aus den Widget-Einstellungen (wie dashFontTier(): "klein" = 7 pt, sonst 9 pt)
  local wf = (box.font == -1) and "small" or "normal"
  draw.text(textX, top + 16, fit(word, textW, wf), wf, color.BLACK, "left")
  local y = top + 34
  if box.fh >= 90 then
    draw.text(textX, y, fit(def, textW, "small"), "small", color.ACCENT_TEXT, "left")
  end
  if box.fh >= 170 and example ~= "" and y + 18 <= maxY then
    draw.text(textX, y + 18, fit('"' .. example .. '"', textW, "small"), "small", color.BLACK, "left")
  end
end
