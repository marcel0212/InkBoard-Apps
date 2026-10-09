-- Nachrichten (Skript-Variante der eingebauten News-App): RSS-/Atom-Feeds in vier Kategorien
-- (Allgemein, Wirtschaft, Sport, Technik), je Kategorie zwei Feeds aus einer Auswahl plus eine eigene
-- Feed-Adresse, drei Stile (Bento/Slate/Nano), Dashboard-Widget. Skript-API Level 7.
--
-- Ablauf: on_fetch holt hoechstens 6 Feeds je Lauf (Rotation "rot", wenn mehr eingerichtet sind), mischt die
-- neuen Schlagzeilen mit den schon gespeicherten Schlagzeilen der anderen Feeds derselben Kategorie und
-- legt je Kategorie zwei Textbloecke "n<k>a"/"n<k>b" ab (Zeile = "Unix-Zeit<TAB>Quelle<TAB>Titel").

local CATS = { "general", "business", "sports", "tech" }
local PER_CAT = 14
local PER_CHUNK = 7
local MAX_CALLS = 6

--#include text
--#include dates
--#include ui

-- Feed-Auswahl: id -> Anzeigename + Adresse
local PRESETS = {
  tagesschau = { "Tagesschau", "https://www.tagesschau.de/xml/rss2" },
  zeit = { "ZEIT ONLINE", "https://newsfeed.zeit.de/index" },
  tagesschau_wirtschaft = { "Tagesschau Wirtschaft", "https://www.tagesschau.de/wirtschaft/index~rss2.xml" },
  kicker = { "Kicker", "https://newsfeed.kicker.de/news/aktuell" },
  heise = { "Heise", "https://www.heise.de/rss/heise-atom.xml" },
  golem = { "Golem", "https://rss.golem.de/rss.php?feed=RSS2.0" },
}

-- Eingerichtete Feeds in fester Reihenfolge: { cat = 1..4, label, url }
local function feedList(ctx)
  local out = {}
  for ci, c in ipairs(CATS) do
    for _, slot in ipairs({ "a", "b" }) do
      local p = PRESETS[ctx.cfg[c .. "_" .. slot] or "off"]
      if p then out[#out + 1] = { cat = ci, label = p[1], url = p[2] } end
    end
    local u = ctx.cfg[c .. "_url"]
    if type(u) == "string" and u:sub(1, 8) == "https://" then
      local host = u:match("^https://([^/:]+)") or "Feed"
      host = host:gsub("^www%.", "")
      out[#out + 1] = { cat = ci, label = cut(host, 22), url = u }
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Gespeicherte Schlagzeilen lesen/schreiben
-- ---------------------------------------------------------------------------

local function readCat(ctx, ci)
  local items = {}
  if ctx.sample then -- Beispieldaten fuer die Widget-Vorschau im Dashboard-Editor (CHANGELOG 559)
    local en = ctx.lang == "en"
    return {
      { t = 0, src = "Tagesschau", title = en and "Sample headline: the most important news of the day" or "Beispiel: Die wichtigsten Nachrichten des Tages" },
      { t = 0, src = "Spiegel", title = en and "Sample headline: weather turns mild this week" or "Beispiel: Das Wetter wird in dieser Woche mild" },
      { t = 0, src = "Heise", title = en and "Sample headline: new gadget announced" or "Beispiel: Neues Gadget vorgestellt" },
      { t = 0, src = "Zeit", title = en and "Sample headline: city plans new cycle paths" or "Beispiel: Stadt plant neue Radwege" },
      { t = 0, src = "FAZ", title = en and "Sample headline: markets close higher" or "Beispiel: Märkte schließen im Plus" },
    }
  end
  for _, part in ipairs({ "a", "b" }) do
    local raw = ctx.data.get("n" .. ci .. part)
    if type(raw) == "string" and raw ~= "" then
      for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
        local t, src, title = line:match("^(%d*)\t([^\t]*)\t(.*)$")
        if title then items[#items + 1] = { t = tonumber(t) or 0, src = src, title = title } end
      end
    end
  end
  return items
end

local function writeCat(ctx, ci, items)
  table.sort(items, function(a, b)
    if (a.t > 0) ~= (b.t > 0) then return a.t > 0 end
    return a.t > b.t
  end)
  local parts = { {}, {} }
  for i = 1, math.min(#items, PER_CAT) do
    local it = items[i]
    local k = i <= PER_CHUNK and 1 or 2
    parts[k][#parts[k] + 1] = it.t .. "\t" .. it.src .. "\t" .. it.title
  end
  ctx.data.set("n" .. ci .. "a", table.concat(parts[1], "\n"))
  ctx.data.set("n" .. ci .. "b", table.concat(parts[2], "\n"))
end

-- ---------------------------------------------------------------------------
-- Abruf
-- ---------------------------------------------------------------------------

local function fetchFeed(feed)
  local r, err = http.request{ url = feed.url, headers = { Accept = "application/rss+xml, application/atom+xml, application/xml, text/xml" } }
  if r == nil then return nil, "net", clean(tostring(err or ""), 40) end
  if r.status ~= 200 then return nil, "http", tostring(r.status) end
  local entries = rss.parse(r.body)
  if type(entries) ~= "table" or #entries == 0 then return nil, "parse" end
  local out = {}
  for _, e in ipairs(entries) do
    local title = e.title
    if type(title) == "string" and title ~= "" then
      title = clean(text.strip_html(title), 90)
      local t = parseRfc822(e.pubDate) or parseIso(e.updated) or parseIso(e.published) or parseIso(e.dc_date) or 0
      if title ~= "" then out[#out + 1] = { t = t, src = feed.label, title = title } end
    end
  end
  return out
end

function on_fetch(ctx)
  local feeds = feedList(ctx)
  if #feeds == 0 then
    ctx.data.set("st", "none")
    return
  end
  local rot = tonumber(ctx.data.get("rot")) or 0
  if rot >= #feeds then rot = 0 end
  local todo = math.min(#feeds, MAX_CALLS)
  local fresh = {}   -- Kategorie -> { label -> Schlagzeilen }
  local failed = {}
  local okAny = false
  for n = 0, todo - 1 do
    local feed = feeds[(rot + n) % #feeds + 1]
    local items, why, detail = fetchFeed(feed)
    if items then
      fresh[feed.cat] = fresh[feed.cat] or {}
      fresh[feed.cat][feed.label] = items
      okAny = true
    else
      failed[feed.cat] = why .. ((detail and detail ~= "") and (" " .. detail:gsub("[,\n]", " ")) or "")
      log("Nachrichten " .. feed.label .. ": " .. tostring(why) .. " " .. tostring(detail or ""))
    end
    if n < todo - 1 then time.sleep(250) end
  end
  -- je Kategorie: Schlagzeilen der frisch geladenen Feeds ersetzen, die der anderen behalten
  for ci = 1, #CATS do
    if fresh[ci] then
      local merged = {}
      for _, it in ipairs(readCat(ctx, ci)) do
        if fresh[ci][it.src] == nil then merged[#merged + 1] = it end
      end
      for _, list in pairs(fresh[ci]) do
        for _, it in ipairs(list) do merged[#merged + 1] = it end
      end
      -- Schlagzeilen von Feeds, die nicht mehr eingerichtet sind, entfernen
      local wanted = {}
      for _, f in ipairs(feeds) do if f.cat == ci then wanted[f.label] = true end end
      local kept = {}
      for _, it in ipairs(merged) do if wanted[it.src] then kept[#kept + 1] = it end end
      writeCat(ctx, ci, kept)
    end
  end
  -- Status je Kategorie: "-" kein Feed, "ok", "e:<Grund>" nur Fehler
  local has = {}
  for _, f in ipairs(feeds) do has[f.cat] = true end
  local st = {}
  for ci = 1, #CATS do
    if not has[ci] then st[ci] = "-"
    elseif failed[ci] and not fresh[ci] then st[ci] = "e:" .. failed[ci]
    else st[ci] = "ok" end
  end
  -- Kategorien ohne eigenen Abruf in diesem Lauf behalten ihren alten Status
  local old = ctx.data.get("st")
  if type(old) == "string" then
    local prev = {}
    for s in (old .. ","):gmatch("([^,]*),") do prev[#prev + 1] = s end
    local touched = {}
    for n = 0, todo - 1 do touched[feeds[(rot + n) % #feeds + 1].cat] = true end
    for ci = 1, #CATS do
      if has[ci] and not touched[ci] and prev[ci] and prev[ci] ~= "-" then st[ci] = prev[ci] end
    end
  end
  ctx.data.set("st", table.concat(st, ","))
  ctx.data.set("rot", tostring((rot + todo) % #feeds))
  if not okAny then return false end
end

-- ---------------------------------------------------------------------------
-- Anzeige
-- ---------------------------------------------------------------------------

local function relTime(ctx, t)
  if t == nil or t <= 0 then return "" end
  local diff = time.now() - t
  if diff < 0 then diff = 0 end
  local min = diff // 60
  local en = ctx.lang == "en"
  if min < 1 then return en and "just now" or "gerade eben" end
  if min < 60 then return en and (min .. " min ago") or ("vor " .. min .. " Min.") end
  if min < 1440 then return en and ((min // 60) .. " h ago") or ("vor " .. (min // 60) .. " Std.") end
  return en and ((min // 1440) .. " d ago") or ("vor " .. (min // 1440) .. " Tagen")
end

local function statusOf(ctx, ci)
  local st = ctx.data.get("st")
  if type(st) ~= "string" then return nil end
  local i = 0
  for s in (st .. ","):gmatch("([^,]*),") do
    i = i + 1
    if i == ci then return s end
  end
  return nil
end

-- Leerzustand fuer Kategorie ci: true, wenn schon ein Hinweis gezeichnet wurde
local function emptyState(ctx, ci, items)
  local en = ctx.lang == "en"
  local st = ctx.data.get("st")
  if st == "none" or (st == nil and #feedList(ctx) == 0) then
    notice("gear", en and "No news source configured." or "Keine Nachrichtenquelle eingerichtet.",
      en and "Store -> News -> Settings" or "Store -> Nachrichten -> Einstellungen")
    return true
  end
  if #items > 0 then return false end
  if st == nil then
    notice("clock", en and "Loading headlines ..." or "Lade Schlagzeilen ...")
    return true
  end
  local s = statusOf(ctx, ci)
  if s == "-" then
    notice("gear", en and "No source for this category." or "Keine Quelle für diese Kategorie.",
      en and "Store -> News -> Settings" or "Store -> Nachrichten -> Einstellungen")
    return true
  end
  if s ~= nil and s:sub(1, 2) == "e:" then
    notice("warning", en and "Fetch failed." or "Abruf fehlgeschlagen.", cut(s:sub(3), 60))
    return true
  end
  if s == nil then
    notice("clock", en and "Loading headlines ..." or "Lade Schlagzeilen ...")
    return true
  end
  notice("check", en and "No headlines in this category." or "Keine Schlagzeilen in dieser Kategorie.")
  return true
end

-- "Slate": Zeilen mit Trennlinie, Quelle + Zeit, Titel auf bis zu zwei Zeilen (bis 8)
local function drawFlat(ctx, items)
  local W, margin = draw.width, 26
  local top, bottom = draw.top + 10, draw.height - 20
  local shown = math.min(#items, 8)
  local rowH = (bottom - top) // shown
  if rowH > 100 then rowH = 100 end
  if rowH < 60 then rowH = 60 end
  local rowY = top
  for i = 1, #items do
    if rowY + rowH > bottom + 4 then break end
    local it = items[i]
    draw.line(margin, rowY, W - margin, rowY, color.BLACK)
    draw.circle(margin + 5, rowY + 15, 5, color.ACCENT, true)
    draw.text(margin + 16, rowY + 20, it.src, "small", color.BLACK, "left")
    local rel = relTime(ctx, it.t)
    if rel ~= "" then draw.text(W - margin, rowY + 20, rel, "small", color.BLACK, "right") end
    local ty = rowY + 40
    for _, l in ipairs(wrapLines(it.title, W - 2 * margin, "normal", 2)) do
      draw.text(margin, ty, l, "normal", color.BLACK, "left")
      ty = ty + 22
    end
    rowY = rowY + rowH
  end
end

-- "Bento": Karten mit Quellen-Pille (bis 6)
local function drawCards(ctx, items)
  local W, margin = draw.width, 20
  local top, bottom = draw.top + 8, draw.height - 18
  local shown = math.min(#items, 6)
  local gap = 10
  local cardH = ((bottom - top) - (shown - 1) * gap) // shown
  if cardH > 110 then cardH = 110 end
  if cardH < 68 then cardH = 68 end
  local cardY = top
  for i = 1, #items do
    if cardY + cardH > bottom + 4 then break end
    local it = items[i]
    local cardW = W - 2 * margin
    card(margin, cardY, cardW, cardH, color.ACCENT, 14)
    local innerX, innerW = margin + 14, cardW - 28
    local pillW = draw.measure(it.src, "small") + 20
    local pillY = cardY + 12
    draw.rect(innerX, pillY, pillW, 22, color.ACCENT, true, 11)
    draw.text(innerX + pillW // 2, pillY + 15, it.src, "small", color.ACCENT_INK, "center")
    local rel = relTime(ctx, it.t)
    if rel ~= "" then draw.text(margin + cardW - 14, pillY + 15, rel, "small", color.BLACK, "right") end
    local ty = pillY + 22 + 20
    for _, l in ipairs(wrapLines(it.title, innerW, "normal", 2)) do
      draw.text(innerX, ty, l, "normal", color.BLACK, "left")
      ty = ty + 22
    end
    cardY = cardY + cardH + gap
  end
end

-- "Nano": eine Zeile je Schlagzeile (bis 16)
local function drawCompact(ctx, items)
  local W, margin = draw.width, 24
  local top, bottom = draw.top + 6, draw.height - 16
  local shown = math.min(#items, 16)
  local rowH = (bottom - top) // shown
  if rowH > 40 then rowH = 40 end
  if rowH < 24 then rowH = 24 end
  local rowY = top
  for i = 1, #items do
    if rowY + rowH > bottom + 2 then break end
    local it = items[i]
    draw.circle(margin + 4, rowY + rowH // 2, 3, color.ACCENT, true)
    local rel = relTime(ctx, it.t)
    local relW = rel ~= "" and (draw.measure(rel, "small") + 10) or 0
    local title = fit(it.title, W - 2 * margin - 14 - relW, "small")
    draw.text(margin + 14, rowY + rowH // 2 + 5, title, "small", color.BLACK, "left")
    if rel ~= "" then draw.text(W - margin, rowY + rowH // 2 + 5, rel, "small", color.BLACK, "right") end
    rowY = rowY + rowH
  end
end

function on_draw(ctx, page)
  draw.clear(color.WHITE)
  local ci = math.max(1, math.min(page or 1, #CATS))
  local items = readCat(ctx, ci)
  if emptyState(ctx, ci, items) then return end
  local style = ctx.cfg.style
  if style == "cards" then drawCards(ctx, items)
  elseif style == "compact" then drawCompact(ctx, items)
  else drawFlat(ctx, items) end
end

-- ---------------------------------------------------------------------------
-- Widget: Schlagzeilen der gewaehlten Kategorie
-- ---------------------------------------------------------------------------

function on_widget(ctx, box)
  local ci = 1
  for i, c in ipairs(CATS) do if c == ctx.cfg.wCat then ci = i end end
  local items = readCat(ctx, ci)
  local font = ((box.font or 0) > 0) and "normal" or "small"
  if (box.font or 0) < 0 then font = "small" end
  local compact = ctx.cfg.wCompact == true
  local lineH = compact and 17 or 22
  local y = box.y + 16
  local maxY = box.y + box.h - 4
  local showSrc = ctx.cfg.wSource == true
  local shown = 0
  for _, it in ipairs(items) do
    if y > maxY then break end
    draw.rect(box.x + 12, y - 8, 5, 5, color.ACCENT, true)
    local tx = box.x + 24
    if showSrc then
      draw.text(tx, y, fit(it.src, 78, font), font, color.ACCENT_TEXT, "left")
      tx = tx + 84
    end
    draw.text(tx, y, fit(it.title, box.w - (tx - box.x) - 6, font), font, color.BLACK, "left")
    y = y + lineH
    shown = shown + 1
  end
  if shown == 0 then
    local en = ctx.lang == "en"
    draw.text(box.x + 12, box.y + 16, ctx.data.get("st") == nil and (en and "No data yet" or "Noch keine Daten") or (en and "No headlines" or "Keine Schlagzeilen"), "small", color.BLACK, "left")
  end
end
