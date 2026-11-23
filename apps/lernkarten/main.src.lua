-- Lernkarten: Karteikarten zum Durchblaettern. Fertige Listen per API (Tatoeba-Saetze, Open-Trivia-Quiz) oder eigene Karten.
-- Seite 1 zeigt die Vorderseite, Seite 2 die Rueckseite. Die Karte wechselt im eingestellten Takt.
-- Skript-API Level 12 (http.request mit keep, file.read/write).
--#include theme
--#include text
--#include ui

local LANG_NAME = {
  eng = { "Englisch", "English" }, spa = { "Spanisch", "Spanish" }, fra = { "Französisch", "French" },
  ita = { "Italienisch", "Italian" }, por = { "Portugiesisch", "Portuguese" }, nld = { "Niederländisch", "Dutch" },
  swe = { "Schwedisch", "Swedish" }, dan = { "Dänisch", "Danish" }, deu = { "Deutsch", "German" },
}

local SAMPLE_SENT = { { f = "Where is the train station?", b = "Wo ist der Bahnhof?" }, { f = "I would like a coffee, please.", b = "Ich hätte gern einen Kaffee, bitte." } }
local SAMPLE_QUIZ = { { f = "Which planet is known as the Red Planet?", b = "Mars", o = { "Venus", "Mars", "Jupiter", "Saturn" } } }

local function deckKey(ctx)
  local c = ctx.cfg
  return table.concat({ c.deck or "sentences", c.learn or "eng", c.native or "deu", c.category or "any", c.difficulty or "any" }, "|")
end

local function pct(s)
  return (tostring(s or ""):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- einfache, wiederholbare Mischung (Karten brauchen keine echte Zufallszahl)
local function shuffled(list, seed)
  local out = { table.unpack(list) }
  local s = seed
  for i = #out, 2, -1 do
    s = (s * 75 + 74) % 65537
    local j = s % i + 1
    out[i], out[j] = out[j], out[i]
  end
  return out
end

local function fetchTrivia(ctx)
  local c = ctx.cfg
  local url = "https://opentdb.com/api.php?amount=10&type=multiple&encode=url3986"
  if c.category and c.category ~= "any" then url = url .. "&category=" .. c.category end
  if c.difficulty and c.difficulty ~= "any" then url = url .. "&difficulty=" .. c.difficulty end
  local body, err = http.get(url, 16384)
  if not body then return nil, "Open Trivia DB: " .. tostring(err) end
  local doc = json.decode(body)
  if type(doc) ~= "table" then return nil, "Open Trivia DB: keine Antwort" end
  if doc.response_code == 5 then return nil, "Zu viele Anfragen, später erneut" end
  local out = {}
  for i, q in ipairs(doc.results or {}) do
    local opts = { pct(q.correct_answer) }
    for _, w in ipairs(q.incorrect_answers or {}) do opts[#opts + 1] = pct(w) end
    local f = clean(pct(q.question), 200)
    for k, o in ipairs(opts) do opts[k] = clean(o:gsub("|", "/"), 60) end
    local right = opts[1]
    opts = shuffled(opts, i * 7919 + #f)
    out[#out + 1] = f .. "\t" .. right .. "\t" .. table.concat(opts, "|")
  end
  if #out == 0 then return nil, "Keine Fragen erhalten" end
  return out
end

local function fetchSentences(ctx)
  local c = ctx.cfg
  local from, to = c.learn or "eng", c.native or "deu"
  if from == to then return nil, "Lernsprache und Muttersprache sind gleich" end
  local url = "https://tatoeba.org/en/api_v0/search?from=" .. from .. "&to=" .. to
    .. "&trans_filter=limit&trans_to=" .. to .. "&sort=random&limit=12"
  local r, err = http.request{ url = url, maxBytes = 65536, keep = { "text", "lang" },
    skip = { "audios", "transcriptions", "user", "permissions", "current_user_review", "paging" }, headers = { Accept = "application/json" } }
  if not r then return nil, "Tatoeba: " .. tostring(err) end
  if r.status and r.status ~= 200 then return nil, "Tatoeba: Status " .. tostring(r.status) end
  local doc = json.decode(r.body or "")
  if type(doc) ~= "table" or type(doc.results) ~= "table" then return nil, "Tatoeba: keine Antwort" end
  local out = {}
  for _, s in ipairs(doc.results) do
    local f, b = clean(s.text, 160), nil
    for _, grp in ipairs(s.translations or {}) do
      for _, t in ipairs(grp) do
        if not b and t.lang == to and t.text then b = clean(t.text, 160) end
      end
    end
    if b and f ~= "" and #f <= 110 and #b <= 110 then out[#out + 1] = f .. "\t" .. b end
  end
  if #out == 0 then return nil, "Keine Sätze erhalten" end
  return out
end

function on_fetch(ctx)
  local deck = ctx.cfg.deck or "sentences"
  if deck == "own" then return true end
  local lines, err
  if deck == "trivia" then lines, err = fetchTrivia(ctx) else lines, err = fetchSentences(ctx) end
  if not lines then
    log("Lernkarten: " .. tostring(err))
    ctx.data.set("err", clean(err, 120))
    return false
  end
  local ok, werr = file.write("deck", table.concat(lines, "\n"))
  if not ok then
    ctx.data.set("err", clean(werr, 120))
    return false
  end
  ctx.data.set("key", deckKey(ctx))
  ctx.data.set("n", #lines)
  ctx.data.set("err", "")
  return true
end

-- Karten holen: { f = Vorderseite, b = Rueckseite, o = Antwortliste (nur Quiz) }
local function loadDeck(ctx)
  local deck = ctx.cfg.deck or "sentences"
  local cards = {}
  if deck == "own" then
    local list = type(ctx.cfg.cards) == "table" and ctx.cfg.cards or {}
    for _, ln in ipairs(list) do
      local f, b = tostring(ln):match("^(.-)%s*[=;]%s*(.+)$")
      if f and f ~= "" then cards[#cards + 1] = { f = clean(f, 160), b = clean(b, 160) } end
    end
  elseif ctx.data.get("key") == deckKey(ctx) then
    local raw = file.read("deck") or ""
    for ln in raw:gmatch("[^\n]+") do
      local f, b, o = ln:match("^([^\t]*)\t([^\t]*)\t?(.*)$")
      if f and b then
        local card = { f = f, b = b }
        if o and o ~= "" then
          card.o = {}
          for part in o:gmatch("[^|]+") do card.o[#card.o + 1] = part end
        end
        cards[#cards + 1] = card
      end
    end
  end
  if #cards == 0 and (ctx.preview == true or ctx.sample or ctx.data.get("demo") == "1") then
    cards = (deck == "trivia") and SAMPLE_QUIZ or SAMPLE_SENT
  end
  return cards
end

local function pickIndex(ctx, n)
  if ctx.preview == true or ctx.data.get("demo") == "1" then return 1 end
  local iv = (tonumber(ctx.cfg.minutes) or 30) * 60
  if iv < 60 then iv = 60 end
  local now = time.now() or 0
  return (now // iv) % n + 1
end

-- Satz auf Breite w umbrechen (alle Zeilen)
local function wrapAll(s, w, font)
  local lines, line = {}, ""
  for word in tostring(s):gmatch("%S+") do
    local try = line == "" and word or (line .. " " .. word)
    if draw.measure(try, font) <= w or line == "" then
      line = try
    else
      lines[#lines + 1] = line
      line = word
    end
  end
  if line ~= "" then lines[#lines + 1] = line end
  for i, l in ipairs(lines) do lines[i] = fit(l, w, font) end
  return lines
end

local LH = { large = 46, medium = 36, normal = 28, small = 22 }

-- groesste Schrift waehlen, bei der der Text in die Hoehe passt
local function layoutText(s, w, availH, fonts)
  fonts = fonts or { "large", "medium", "normal" }
  local last = fonts[#fonts]
  for _, f in ipairs(fonts) do
    local lines = wrapAll(s, w, f)
    if #lines * LH[f] <= availH or f == last then
      local maxl = math.max(1, availH // LH[f])
      while #lines > maxl do table.remove(lines) end
      return f, lines
    end
  end
end

local function drawLines(x, y, lines, font, col, align)
  for i, l in ipairs(lines) do draw.text(x, y + (i - 1) * LH[font], l, font, col, align or "left") end
  return #lines * LH[font]
end

-- Rahmen je nach Stil; gibt den Innenbereich zurueck
local function frame(ctx)
  local top, bottom = draw.top + 14, draw.height - 16
  local x, y, w, h = 40, top, draw.width - 80, bottom - top
  local st = theme.s
  if st == "relief" or st == "klar" or st == "cards" then
    card(x, y, w, h, color.ACCENT, st == "relief" and 16 or 22)
    return x + 34, y + 20, w - 68, h - 40
  elseif st == "flat" then
    draw.line(x, y, x + w, y, color.BLACK)
    draw.line(x, y + h, x + w, y + h, color.BLACK)
    return x + 6, y + 14, w - 12, h - 28
  end
  draw.rect(x - 16, y, 5, h, color.ACCENT, true)
  return x + 6, y + 10, w - 12, h - 20
end

local function deckLabel(ctx, en)
  local c = ctx.cfg
  if c.deck == "trivia" then return en and "Quiz" or "Quiz" end
  if c.deck == "own" then return en and "My cards" or "Eigene Karten" end
  local l = LANG_NAME[c.learn or "eng"] or LANG_NAME.eng
  local n = LANG_NAME[c.native or "deu"] or LANG_NAME.deu
  local a, b = l[en and 2 or 1], n[en and 2 or 1]
  if c.reverse then a, b = b, a end
  return a .. " - " .. b
end

local function pillRow(x, y, w, ctx, en, idx, n)
  local label = deckLabel(ctx, en)
  pill(x, y, 0, 30, color.ACCENT, fit(label, w - 140, "small"), "small")
  local cnt = idx .. "/" .. n
  local cw = pillW(cnt, "small", 30, 0)
  pill(x + w - cw, y, cw, 30, color.ACCENT, cnt, "small")
end

function on_draw(ctx, page)
  local en = (ctx.lang == "en")
  setStyle(ctx.cfg.style)
  draw.clear(color.WHITE)
  local cards = loadDeck(ctx)
  if #cards == 0 then
    local err = ctx.data.get("err") or ""
    if (ctx.cfg.deck or "sentences") == "own" then
      notice("info", en and "No cards yet" or "Noch keine Karten", en and "Add cards in the settings (front = back)" or "Karten in den Einstellungen eintragen (Vorderseite = Rückseite)")
    elseif err ~= "" then
      notice("error", en and "Cards not loaded" or "Karten nicht geladen", err)
    else
      notice("loading", en and "Loading cards ..." or "Karten werden geladen ...")
    end
    return
  end
  local idx = pickIndex(ctx, #cards)
  local c = cards[idx]
  local front, back = c.f, c.b
  if c.o == nil and ctx.cfg.reverse then front, back = back, front end
  local x, y, w, h = frame(ctx)
  pillRow(x, y, w, ctx, en, idx, #cards)
  local ty = y + 52
  local th = h - 52
  local backPage = (page == 2)

  if c.o then
    -- Quiz: Frage oben, Antworten als Liste; Rueckseite markiert die richtige
    local f, lines = layoutText(front, w, 110, { "medium", "normal" })
    local used = drawLines(x, ty + LH[f] - 8, lines, f, color.BLACK)
    local oy = ty + used + 14
    local rowH = math.min(52, (y + h - oy) // math.max(#c.o, 1))
    for i, o in ipairs(c.o) do
      local ry = oy + (i - 1) * rowH
      local label = string.char(64 + i) .. "   " .. fit(o, w - 70, "normal")
      if backPage and o == back then
        pill(x - 6, ry, w + 12, rowH - 8, color.ACCENT, label, "normal")
      else
        draw.text(x + 6, ry + rowH // 2 + 4, label, "normal", (backPage and color.BLACK) or color.BLACK, "left")
      end
    end
    return
  end

  if not backPage then
    local f, lines = layoutText(front, w, th - 10)
    local total = #lines * LH[f]
    drawLines(x + w // 2, ty + (th - total) // 2 + LH[f] - 10, lines, f, color.BLACK, "center")
  else
    local f1, l1 = layoutText(front, w, 60, { "normal", "small" })
    drawLines(x, ty + LH[f1] - 6, l1, f1, color.ACCENT_TEXT)
    local ly = ty + math.max(#l1, 1) * LH[f1] + 10
    draw.line(x, ly, x + w, ly, color.BLACK)
    local room = y + h - (ly + 16)
    local f, lines = layoutText(back, w, room)
    local total = #lines * LH[f]
    drawLines(x + w // 2, ly + 16 + (room - total) // 2 + LH[f] - 10, lines, f, color.BLACK, "center")
  end
end

function on_widget(ctx, box)
  setStyle(ctx.cfg.style)
  box = widgetFrame(box)
  local en = (ctx.lang == "en")
  local cards = loadDeck(ctx)
  if #cards == 0 then
    draw.text(box.x + 12, box.y + 22, en and "No cards yet" or "Noch keine Karten", "small", color.BLACK, "left")
    return
  end
  local c = cards[pickIndex(ctx, #cards)]
  local front, back = c.f, c.b
  if c.o == nil and ctx.cfg.reverse then front, back = back, front end
  local w = box.w - 20
  local showBack = box.h >= 96
  local maxFront = showBack and math.max(1, (box.h - 52) // 22) or math.max(1, (box.h - 8) // 22)
  local lines = wrapAll(front, w, "small")
  while #lines > maxFront do table.remove(lines) end
  local used = drawLines(box.x + 12, box.y + 20, lines, "small", color.BLACK)
  if showBack then
    local bl = wrapAll(back, w, "small")
    local room = math.max(1, (box.y + box.h - (box.y + used + 30)) // 22)
    while #bl > room do table.remove(bl) end
    drawLines(box.x + 12, box.y + used + 30, bl, "small", color.ACCENT_TEXT)
  end
end
