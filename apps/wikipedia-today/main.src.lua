-- Was geschah heute (Skript-Variante der eingebauten Wikipedia-App): sechs Ereignisse zum heutigen Kalendertag,
-- redaktionell nach Bedeutung sortiert (das erste ist das wichtigste). Drei Stile (Bento/Slate/Nano), Ticker-Widget.
-- Skript-API Level 8 (http.get mit Groessengrenze, time.localtime). Siehe docs/SKRIPT_APPS.md.
--
-- Quelle 1: Wikimedia-REST "feed/onthisday/selected/MM/DD" der Wikipedia in der Display-Sprache (de/en).
-- Quelle 2 (nur wenn Wikimedia ablehnt, z. B. HTTP 429): byabbe.se/on-this-day (Inhalte der englischen Wikipedia,
--   chronologisch). Daraus werden gleichmaessig verteilte Ereignisse gewaehlt, neuestes zuerst; bei deutscher
--   Display-Sprache uebersetzt MyMemory (hoechstens 4 Ereignisse, wegen der 6 Abrufe je Lauf).
-- Beide Antworten sind groesser als das 24-KB-Standardlimit von http.get; es wird mit 60 KB abgerufen (API-Stufe 8) und mit
-- Textmustern gelesen, bis zum letzten vollstaendigen Eintrag.
-- ctx.data: "n" Anzahl, "y1".."y6" Jahr, "t1".."t6" Text, "day" Tag der Daten (JJJJMMTT), "lang" Sprache der Daten,
-- "ok" = "1" wenn die Texte in der Display-Sprache stehen (sonst Englisch als Ersatz).

local MAX_EVENTS = 6
local MAX_TRANSLATE = 4

--#include text
--#include ui

local function en_(ctx) return ctx.lang == "en" end

-- Weiche Trennstriche (U+00AD) stehen in deutschen Texten bei langen Woertern; die Anzeige wuerde sie als Strich zeigen.
local function clean_text(s)
  s = tostring(s or ""):gsub("\xC2\xAD", "")
  s = s:gsub("%s+", " ")
  return (trim(s))
end

local function decodeEntities(s)
  s = s:gsub("&#(%d+);", function(d)
    local n = tonumber(d)
    if n < 128 then return string.char(n) end
    if n < 2048 then return string.char(192 + n // 64, 128 + n % 64) end
    return string.char(224 + n // 4096, 128 + (n // 64) % 64, 128 + n % 64)
  end)
  return (s:gsub("&quot;", '"'):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&"))
end

-- Uebersetzt Englisch -> Deutsch (MyMemory). Gibt Text oder nil zurueck.
local function translate(s)
  local body = http.get("https://api.mymemory.translated.net/get?langpair=en%7Cde&q=" .. text.url_encode(s))
  if body == nil then return nil end
  local doc = json.decode(body)
  if type(doc) ~= "table" or type(doc.responseData) ~= "table" then return nil end
  local t = doc.responseData.translatedText
  if type(t) ~= "string" or t:find("MYMEMORY WARNING", 1, true) == 1 then return nil end
  t = trim(decodeEntities(t))
  if t == "" then return nil end
  return t
end

-- Die Antworten sind gross (Wikimedia liefert je Ereignis mehrere Seiten mit Vorschaubild und Zusammenfassung, rund 8 KB),
-- deshalb http.get mit 60 KB Grenze und Textmuster statt json.decode (das nimmt hoechstens 24 KB).
local BIG = 60 * 1024

-- Text eines JSON-Strings, der bei Position i (nach dem oeffnenden ") beginnt: gibt Inhalt und Position des schliessenden " zurueck.
local function jsonString(body, i)
  local q = i
  while true do
    q = body:find('"', q, true)
    if q == nil then return nil end
    local k, bs = q - 1, 0
    while k >= i and body:byte(k) == 92 do bs = bs + 1; k = k - 1 end
    if bs % 2 == 0 then return body:sub(i, q - 1), q end
    q = q + 1
  end
end

local function unescape(raw)
  local d = json.decode('{"t":"' .. raw .. '"}')
  if type(d) == "table" and type(d.t) == "string" then return d.t end
  return raw
end

-- Wikimedia: {"selected":[{"text":"..","pages":[..],"year":1912}, ...]}. Gelesen werden nur die vollstaendigen Eintraege
-- (Text bis zur naechsten Eintragsgrenze plus Jahr); der abgeschnittene letzte Eintrag faellt weg.
local function fromWikimedia(body)
  local list, pos = {}, 1
  while #list < MAX_EVENTS do
    local a, b = body:find('{"text":"', pos, true)
    if a == nil then break end
    local raw, e = jsonString(body, b + 1)
    if raw == nil then break end
    local nxt = body:find('{"text":"', e, true)
    local chunk = body:sub(e, (nxt or #body + 1) - 1)
    local year = chunk:match('"year":%s*(-?%d+)')
    if year ~= nil then
      local t = clean_text(cut(unescape(raw), 300))
      if t ~= "" then list[#list + 1] = { year = math.tointeger(tonumber(year)) or 0, text = t } end
    end
    pos = e
  end
  if #list == 0 then return nil end
  return list
end

-- byabbe.se: {"events":[{"year":"1912","description":"..","wikipedia":[..]}, ...]} aelteste zuerst. Gleichmaessig verteilt,
-- neuestes zuerst, Eintraege vor Christus werden uebersprungen. want = gewuenschte Anzahl.
local function fromByabbe(body, want)
  local ev, pos = {}, 1
  while true do
    local a, b, y = body:find('{"year":"([^"]*)","description":"', pos)
    if a == nil then break end
    local raw, e = jsonString(body, b + 1)
    if raw == nil then break end
    if not y:find("BC", 1, true) and not y:find("-", 1, true) then
      local t = clean_text(cut(unescape(raw), 300))
      if t ~= "" then ev[#ev + 1] = { year = math.tointeger(tonumber(y)) or 0, text = t } end
    end
    pos = e
  end
  local total = #ev
  if total == 0 then return nil end
  local n = math.min(total, want)
  local list, last = {}, -1
  for k = 0, n - 1 do
    local idx = (n > 1) and (total - 1) - (k * (total - 1)) // (n - 1) or total - 1
    if idx ~= last then list[#list + 1] = ev[idx + 1]; last = idx end
  end
  return list
end

function on_fetch(ctx)
  local t = time.localtime()
  if t == nil then
    log("Uhrzeit noch nicht synchronisiert")
    return false
  end
  local today = t.year * 10000 + t.month * 100 + t.day
  local lang = en_(ctx) and "en" or "de"
  -- Heutige Ereignisse in dieser Sprache sind schon da: kein Abruf (die Auswahl aendert sich nur mit dem Kalendertag).
  if ctx.data.get("day") == today and ctx.data.get("lang") == lang and ctx.data.get("ok") == "1" and (ctx.data.get("n") or 0) > 0 then
    return true
  end

  local list, translated = nil, true
  local body, err = http.get(string.format("https://%s.wikipedia.org/api/rest_v1/feed/onthisday/selected/%02d/%02d", lang, t.month, t.day), BIG)
  if body ~= nil then
    list = fromWikimedia(body)
  else
    log("Wikimedia: " .. tostring(err))
  end

  if list == nil then
    -- Ausweichquelle
    time.sleep(300)
    local want = (lang == "de") and MAX_TRANSLATE or MAX_EVENTS
    local b2, err2 = http.get(string.format("https://byabbe.se/on-this-day/%d/%d/events.json", t.month, t.day), BIG)
    if b2 == nil then
      log("Ausweichquelle: " .. tostring(err2))
      return false
    end
    list = fromByabbe(b2, want)
    if list == nil then return false end
    if lang == "de" then
      local done = 0
      for i, e in ipairs(list) do
        if i > 1 then time.sleep(400) end
        local de = translate(e.text)
        if de ~= nil then e.text = clean_text(cut(de, 300)); done = done + 1 end
      end
      translated = done == #list
    end
  end

  for i = 1, MAX_EVENTS do
    local e = list[i]
    ctx.data.set("y" .. i, e and e.year or nil)
    ctx.data.set("t" .. i, e and e.text or nil)
  end
  ctx.data.set("n", #list)
  ctx.data.set("day", today)
  ctx.data.set("lang", lang)
  ctx.data.set("ok", translated and "1" or "0")
  return true
end

-- ---------------------------------------------------------------------------

local function loadEvents(ctx)
  local n = ctx.data.get("n") or 0
  local list = {}
  for i = 1, math.min(n, MAX_EVENTS) do
    local tx = ctx.data.get("t" .. i)
    if tx ~= nil and tx ~= "" then list[#list + 1] = { year = ctx.data.get("y" .. i) or 0, text = tx } end
  end
  return list
end

local SAMPLE_DE = {
  { year = 1912, text = "Die Titanic läuft zu ihrer Jungfernfahrt von Southampton aus." },
  { year = 1969, text = "Mit Apollo 11 landen die ersten Menschen auf dem Mond." },
  { year = 1989, text = "Die Berliner Mauer wird geöffnet; Tausende strömen in den Westteil der Stadt." },
  { year = 1815, text = "Die Schlacht bei Waterloo beendet die Herrschaft Napoleons." },
  { year = 2001, text = "Wikipedia geht in der englischsprachigen Version online." },
  { year = 1990, text = "Das Hubble-Weltraumteleskop wird in die Erdumlaufbahn gebracht." },
}
local SAMPLE_EN = {
  { year = 1912, text = "The Titanic leaves Southampton on her maiden voyage." },
  { year = 1969, text = "Apollo 11 lands the first humans on the Moon." },
  { year = 1989, text = "The Berlin Wall is opened; thousands stream into West Berlin." },
  { year = 1815, text = "The Battle of Waterloo ends Napoleon's rule." },
  { year = 2001, text = "Wikipedia goes online in its English edition." },
  { year = 1990, text = "The Hubble Space Telescope is placed in Earth orbit." },
}

local function yearStr(y)
  if y == nil or y == 0 then return "" end
  return tostring(y)
end

local function emptyState(ctx, list)
  if #list > 0 then return false end
  local en = en_(ctx)
  if ctx.data.get("n") == nil then
    notice("clock", en and "Loading ..." or "Wird geladen ...")
  else
    notice("warning", en and "Fetch failed." or "Abruf fehlgeschlagen.", en and "Retrying shortly." or "Nächster Versuch in Kürze.")
  end
  return true
end

-- Bento: Hero-Karte mit dem wichtigsten Ereignis, darunter bis zu zwei Kacheln.
local function drawCards(ctx, list, en)
  local W, H = draw.width, draw.height
  local accent = color.ACCENT
  local marginX = 20
  local heroTop = draw.top + 14
  local heroH = 216
  local heroBottom = heroTop + heroH
  local heroW = W - 2 * marginX
  draw.rect(marginX, heroTop, heroW, heroH, color.BLACK, false, 16)
  local hero = list[1]
  local cy = heroTop + 54
  local ys = yearStr(hero.year)
  if ys ~= "" then
    draw.text(W // 2, cy, ys, "large", color.BLACK, "center")
    draw.rect(W // 2 - 28, cy + 18, 56, 4, accent, true, 2)
    cy = cy + 46
  else
    cy = cy + 6
  end
  local lines = wrapLines(hero.text, heroW - 80, "normal", 4)
  local block = #lines * 26
  local ty = cy + 12
  local avail = heroBottom - 16 - ty
  if avail > block then ty = ty + (avail - block) // 2 end
  for _, l in ipairs(lines) do
    draw.text(W // 2, ty, l, "normal", color.BLACK, "center")
    ty = ty + 26
  end

  if #list > 1 then
    draw.text(24, heroBottom + 24, en and "ALSO ON THIS DAY" or "AUCH AN DIESEM TAG", "small", color.ACCENT_TEXT, "left")
    local tilesTop = heroBottom + 34
    local tilesBottom = H - 20
    local tilesH = tilesBottom - tilesTop
    local gap = 14
    local count = (#list > 2) and 2 or 1
    local tileW = (heroW - (count - 1) * gap) // count
    for i = 1, count do
      local e = list[1 + i]
      local tx = marginX + (i - 1) * (tileW + gap)
      draw.rect(tx, tilesTop, tileW, tilesH, color.BLACK, false, 12)
      local padX, yearCol = 16, 60
      local cyT = tilesTop + tilesH // 2
      local y2 = yearStr(e.year)
      if y2 ~= "" then draw.text(tx + padX, cyT + 4, y2, "normal", color.BLACK, "left") end
      local maxLines = math.max(1, (tilesH - 20) // 17)
      local tl = wrapLines(e.text, tileW - padX * 2 - yearCol, "small", math.min(maxLines, 5))
      local ty2 = cyT - (#tl * 17) // 2 + 12
      for _, l in ipairs(tl) do
        draw.text(tx + padX + yearCol, ty2, l, "small", color.BLACK, "left")
        ty2 = ty2 + 17
      end
    end
  end
end

-- Slate: durchgehende Liste aller Ereignisse, Akzentstreifen am ersten.
local function drawFlat(ctx, list)
  local marginX, yearCol = 20, 62
  local listW = draw.width - 2 * marginX
  local top = draw.top + 4
  local shown, rowH = rowLayout(#list, top, draw.height - 14, 36, 70)
  for i = 1, shown do
    local e = list[i]
    local rowTop = top + (i - 1) * rowH
    local rowCy = rowTop + rowH // 2
    if i == 1 then draw.rect(marginX, rowTop + 4, 5, rowH - 8, color.ACCENT, true, 2) end
    local ys = yearStr(e.year)
    if ys ~= "" then draw.text(marginX + yearCol, rowCy + 6, ys, "normal", color.BLACK, "right") end
    local tl = wrapLines(e.text, listW - yearCol - 16, "small", 2)
    local ty = rowCy - (#tl * 15) // 2 + 11
    for _, l in ipairs(tl) do
      draw.text(marginX + yearCol + 16, ty, l, "small", color.BLACK, "left")
      ty = ty + 15
    end
    if i < shown then draw.line(marginX, rowTop + rowH - 1, marginX + listW, rowTop + rowH - 1, color.BLACK) end
  end
end

-- Nano: eine Zeile je Ereignis, abgeschnitten.
local function drawCompact(ctx, list)
  local marginX, yearCol = 16, 44
  local listW = draw.width - 2 * marginX
  local top = draw.top + 4
  local shown, rowH = rowLayout(#list, top, draw.height - 10, 18, 26)
  for i = 1, shown do
    local e = list[i]
    local rowTop = top + (i - 1) * rowH
    local base = rowTop + rowH // 2 + 5
    local ys = yearStr(e.year)
    if ys ~= "" then draw.text(marginX + yearCol, base, ys, "small", color.BLACK, "right") end
    local tx = marginX + yearCol + 12
    draw.text(tx, base, fit(e.text, listW - yearCol - 12, "small"), "small", color.BLACK, "left")
    if i < shown then draw.line(marginX, rowTop + rowH - 1, marginX + listW, rowTop + rowH - 1, color.BLACK) end
  end
end

function on_draw(ctx, page)
  draw.clear(color.WHITE)
  local list = loadEvents(ctx)
  if emptyState(ctx, list) then return end
  local style = ctx.cfg.style
  if style == "flat" then drawFlat(ctx, list)
  elseif style == "compact" then drawCompact(ctx, list)
  else drawCards(ctx, list, en_(ctx)) end
end

-- Widget "Ticker": Beschriftung oben links, grosse zentrierte Jahreszahl, darunter der Satz (ab 130 px Hoehe).
function on_widget(ctx, box)
  local en = en_(ctx)
  local list = loadEvents(ctx)
  if ctx.sample then list = en and SAMPLE_EN or SAMPLE_DE end
  if #list == 0 then
    draw.text(box.x + 12, box.y + 16, en and "No data yet" or "Noch keine Daten", "small", color.BLACK, "left")
    return
  end
  local e = list[1]
  local textW = math.max(box.w - 24, 20)
  local top = box.y
  local maxY = box.y + box.h - 4
  draw.text(box.x + 12, top + 12, fit(en and "ON THIS DAY" or "WAS GESCHAH HEUTE", textW, "small"), "small", color.ACCENT_TEXT, "left")
  local showLine = box.fh >= 130
  local ys = yearStr(e.year)
  local cx = box.x + box.w // 2
  local yf = (box.font == -1) and "normal" or "large"
  local yearY = showLine and (top + 46) or (top + (maxY - top) // 2 + 8)
  if ys ~= "" then
    draw.text(cx, yearY, ys, yf, color.BLACK, "center")
  else
    showLine = true
  end
  if showLine and yearY + 16 <= maxY then
    local lines = wrapLines(e.text, textW, "small", 3)
    local lineY = ys ~= "" and (yearY + 24) or (top + (maxY - top) // 2 - (#lines - 1) * 8)
    for _, l in ipairs(lines) do
      if lineY > maxY then break end
      draw.text(cx, lineY, l, "small", color.BLACK, "center")
      lineY = lineY + 16
    end
  end
end
