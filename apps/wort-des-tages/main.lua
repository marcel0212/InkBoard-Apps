-- Wort des Tages (Skript-Variante): holt das Tageswort von Merriam-Webster,
-- uebersetzt Wort, Bedeutung und Beispielsatz per Google (Ersatz: MyMemory) ins Deutsche und
-- zeigt je nach Display-Sprache (ctx.lang) Original oder Uebersetzung.
-- Skript-API Level 1 (docs/V2_APPSTORE.md). Netzzugriff nur auf die im
-- Manifest unter permissions.net erlaubten Hosts.

local FEED = "https://www.merriam-webster.com/wotd/feed/rss2"
-- >>> store/lib/translate.lua (erzeugt, dort aendern)
-- Uebersetzer-Baustein (store/lib/translate.lua): Google Translate zuerst, MyMemory als Ersatz.
-- Im Manifest unter permissions.net eintragen: "translate.googleapis.com" und "api.mymemory.translated.net".
-- Je on_fetch gelten hoechstens 6 Abrufe: translateUse(n) meldet schon verbrauchte Abrufe (z. B. den Datenabruf).
-- Benutzung: local de = translateText("Hello", "en", "de")  -- Text oder nil, "quota" | "budget" | "fail"

local TL = { used = 0, max = 6, mm = false, err = "" }

-- Letzter Fehlertext (fuer Protokoll/Anzeige): translateLastError()
local function translateLastError()
  return TL.err
end

local function translateUse(n)
  TL.used = TL.used + n
end

local function tlClean(t)
  t = t:gsub("&#(%d+);", function(d)
    local n = tonumber(d)
    if n < 128 then return string.char(n) end
    if n < 2048 then return string.char(192 + n // 64, 128 + n % 64) end
    return string.char(224 + n // 4096, 128 + (n // 64) % 64, 128 + n % 64)
  end)
  t = t:gsub("&quot;", '"'):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")
  return (t:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Google: Antwort ist [[["Hallo","hello",...],...],...]; die Teilstuecke werden aneinandergehaengt.
local function tlGoogle(s, from, to)
  local body, herr = http.get("https://translate.googleapis.com/translate_a/single?client=gtx&sl=" .. from .. "&tl=" .. to .. "&dt=t&q=" .. text.url_encode(s))
  if body == nil then TL.err = "Google: " .. tostring(herr); return nil, "fail" end
  local doc = json.decode(body)
  if type(doc) ~= "table" or type(doc[1]) ~= "table" then TL.err = "Google: Antwort unlesbar (" .. body:sub(1, 40) .. ")"; return nil, "fail" end
  local parts = {}
  for _, seg in ipairs(doc[1]) do
    if type(seg) == "table" and type(seg[1]) == "string" then parts[#parts + 1] = seg[1] end
  end
  local t = tlClean(table.concat(parts))
  if t == "" then TL.err = "Google: leere Antwort"; return nil, "fail" end
  if #s > 12 and t:lower() == s:lower() then TL.err = "Google: Text unveraendert"; return nil, "fail" end
  return t
end

local function tlMyMemory(s, from, to)
  local body, herr = http.get("https://api.mymemory.translated.net/get?langpair=" .. from .. "%7C" .. to .. "&q=" .. text.url_encode(s))
  if body == nil then TL.err = "MyMemory: " .. tostring(herr); return nil, "fail" end
  local doc = json.decode(body)
  if type(doc) ~= "table" or type(doc.responseData) ~= "table" then TL.err = "MyMemory: Antwort unlesbar"; return nil, "fail" end
  local t = doc.responseData.translatedText
  if type(t) ~= "string" then TL.err = "MyMemory: Antwort unlesbar"; return nil, "fail" end
  if t:find("MYMEMORY WARNING", 1, true) == 1 then TL.err = "MyMemory: Tageslimit erreicht"; return nil, "quota" end
  t = tlClean(t)
  if t == "" then TL.err = "MyMemory: leere Antwort"; return nil, "fail" end
  return t
end

local function translateText(s, from, to)
  from = from or "en"
  to = to or "de"
  if s == nil or s == "" then return "" end
  for _ = 1, 2 do
    if TL.used >= TL.max then TL.err = "keine Abrufe mehr uebrig"; return nil, "budget" end
    TL.used = TL.used + 1
    local t, kind
    if TL.mm then t, kind = tlMyMemory(s, from, to) else t, kind = tlGoogle(s, from, to) end
    if t ~= nil then
      TL.err = ""
      log("Uebersetzer " .. (TL.mm and "MyMemory" or "Google") .. ": ok (" .. s:sub(1, 24) .. " -> " .. t:sub(1, 24) .. ")")
      return t
    end
    log("Uebersetzer: " .. TL.err)
    if TL.mm then return nil, kind end
    TL.mm = true -- Google fehlgeschlagen: ab jetzt MyMemory als Ersatz
  end
  return nil, "fail"
end
-- <<< store/lib/translate.lua
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
  if txt then draw.text(x + w // 2, y + h // 2 + 8, txt, font or "small", tc or (c == color.ACCENT and color.ACCENT_INK or color.WHITE), "center") end
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
  -- Uebersetzung ueber den Baustein translate: Google zuerst, bei Fehler MyMemory; hoechstens 6 Abrufe je Lauf (1 ist der Feed).
  translateUse(1)
  local function tryTranslate(s)
    return translateText(s, "en", "de")
  end
  local wordDe, defDe, exDe, failKind
  -- Kleingeschrieben uebersetzen: "Jilt" mit grossem Anfangsbuchstaben hielt Google fuer einen Namen und liess es stehen.
  local wordLow = word:lower()
  wordDe, failKind = tryTranslate(wordLow)
  -- Ein einzelnes Wort ohne Zusammenhang kommt oft unveraendert zurueck ("jilt" -> "Jilt"). Dann mit Wortart fragen:
  -- Verben beginnen bei Merriam-Webster mit "to ..." ("to jilt" -> "zu verlassen" -> "verlassen"), Nomen mit "a/an ...".
  if wordDe and wordDe:lower() == word:lower() and #word > 2 then
    local dl = def:lower()
    local prefix, strip
    if dl:sub(1, 3) == "to " then
      prefix, strip = "to ", { "zu " }
    elseif dl:sub(1, 2) == "a " or dl:sub(1, 3) == "an " then
      prefix, strip = "a ", { "ein ", "eine ", "einen " }
    end
    if prefix then
      local alt = translateText(prefix .. wordLow, "en", "de")
      if alt then
        local low = alt:lower()
        for _, st in ipairs(strip) do
          if low:sub(1, #st) == st then alt = alt:sub(#st + 1); break end
        end
        if alt ~= "" and alt:lower() ~= word:lower() then wordDe = alt end
      end
    end
  end
  if wordDe then
    time.sleep(300)
    defDe, failKind = tryTranslate(def)
    if defDe and example ~= "" then
      time.sleep(300)
      exDe, failKind = tryTranslate(example)
    end
  end
  local ok = wordDe ~= nil and defDe ~= nil and (example == "" or exDe ~= nil)
  if not ok then
    log("Uebersetzung nicht moeglich: " .. tostring(failKind) .. " / " .. translateLastError())
    ctx.data.set("trErr", translateLastError())
    wordDe, defDe, exDe = nil, nil, nil
  end

  ctx.data.set("wordEn", word)
  ctx.data.set("defEn", def)
  ctx.data.set("exEn", example)
  ctx.data.set("wordDe", wordDe and capFirst(wordDe) or word)
  ctx.data.set("defDe", defDe and capFirst(defDe) or def)
  ctx.data.set("exDe", exDe or example)
  ctx.data.set("tr", ok and "1" or "0")
  if ok then ctx.data.set("trErr", "") end
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
  setStyle(ctx.cfg.style)
  local fancy = theme.s == "relief" or theme.s == "klar"

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
  local tall = draw.height > draw.width
  local panelX, panelW = 40, 240
  local panelH = areaBottom - areaTop
  if tall then panelX, panelW, panelH = 20, draw.width - 40, 230 end
  if theme.s == "relief" then -- Akzentflaeche mit hartem Schatten
    panelH = panelH - 6
    draw.rect(panelX + 6, areaTop + 6, panelW, panelH, color.BLACK, true, 18)
  end
  draw.rect(panelX, areaTop, panelW, panelH, accent, true, fancy and 22 or 18)
  local tx, tw = panelX + 24, panelW - 48
  bookIcon(tx, areaTop + 26, 40, color.WHITE)
  draw.wrap(tx, areaTop + 26 + 40 + 38, tw, word, "large", color.WHITE)
  if not en then
    local metaY = areaTop + panelH - 40
    if translated and word:lower() ~= wordEn:lower() then
      draw.text(tx, metaY, wordEn, "small", color.WHITE, "left")
      draw.text(tx, metaY + 16, "EN -> DE", "small", color.WHITE, "left")
    elseif not translated then
      draw.text(tx, metaY, "Original (Englisch)", "small", color.WHITE, "left")
      local terr = ctx.data.get("trErr") or ""
      if terr ~= "" then draw.text(tx, metaY + 16, terr:sub(1, 26), "small", color.WHITE, "left") end
    end
  end

  -- Rechte Spalte: Bedeutung und Beispiel.
  local cl = panelX + panelW + 32
  local cw = draw.width - 40 - cl
  local top2 = areaTop
  if tall then cl, cw, top2 = 28, draw.width - 56, areaTop + panelH + 20 end
  if fancy then -- Bedeutung und Beispiel auf einer Karte
    local kx = cl - 8
    local kw = draw.width - 46 - kx
    card(kx, top2, kw, areaBottom - top2 - 6, accent, theme.s == "relief" and 16 or 22)
    cl, cw = kx + 26, kw - 46
  end
  -- Dekoratives Anfuehrungszeichen ueber der Bedeutung (wie die eingebaute App)
  if not tall then draw.text(cl - 4, areaTop + 42, '"', "large", color.ACCENT_TEXT, "left") end
  local cy = top2 + (tall and 24 or 58)
  draw.text(cl, cy, en and "MEANING" or "BEDEUTUNG", "small", color.ACCENT_TEXT, "left")
  cy = cy + 22
  local lines = draw.wrap(cl, cy, cw, def, "normal", color.BLACK)
  cy = cy + lines * 24

  if (ctx.cfg.showExample or ctx.preview == true) and example ~= "" and cy < areaBottom - 60 then -- Vorschau zeigt den Beispielsatz immer
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
    local n = #s -- ganzes Zeichen entfernen (UTF-8: Folgebytes und Startbyte)
    while n > 1 and (s:byte(n) & 0xC0) == 0x80 do n = n - 1 end
    s = s:sub(1, n - 1)
  end
  return s
end

function on_widget(ctx, box)
  setStyle(ctx.cfg.style)
  box = widgetFrame(box)
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
  -- Buch-Symbol links: auch im schmalen Hochformat-Widget (ab 110 px, kleiner ab 80 px), nicht nur ab 170 px
  if box.w >= 80 and (maxY - top) >= 28 then
    local isz = box.w >= 110 and 34 or 26
    local by = top + 2
    if by + isz > maxY then by = maxY - isz end
    draw.rect(textX, by, isz, isz, accent, true, 8)
    bookIcon(textX, by, isz, color.WHITE)
    textX = textX + isz + 10
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
