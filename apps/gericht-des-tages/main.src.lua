-- Gericht des Tages (Skript-Variante der eingebauten App "Gericht des Tages"): jeden Tag ein zufaelliges Chefkoch-Rezept
-- mit Uebersicht (Ernaehrungsart, Portionen, Zeit, QR-Code zur Rezeptseite), Zutaten, Naehrwerten und Zubereitung sowie
-- einem Dashboard-Widget. Skript-API Level 10 (recipe.fetch, draw.qr). Siehe docs/SKRIPT_APPS.md.
--
-- Abruf: recipe.fetch("https://www.chefkoch.de/rezepte/zufallsrezept/", portionen) - die Firmware folgt der Weiterleitung auf ein
-- Einzelrezept, liest das schema.org/Recipe der Seite und rechnet die Zutaten auf die gewaehlten Portionen um.
-- Neu gelost wird einmal pro Kalendertag oder auf Wunsch am Geraet (Taster zweimal innerhalb von 3 s); sind Tag und Gericht gleich,
-- aber die Portionen geaendert, wird dasselbe Rezept (gespeicherter Link) neu auf die Portionen umgerechnet.
-- Das ganze Rezept liegt in der App-Datei "recipe" (file.write, bis 40 Zutaten, 24 Schritte, beliebig lang); ctx.data haelt nur
-- das Kleine: "d" Tag der Ziehung (JJJJMMTT), "sv" Portionen der gespeicherten Zutaten, "v" aktuelle Ansicht, "arm" Zeitpunkt des
-- ersten Klicks, "rq" Neu-Losen angefordert. Titel, Link und Meta stehen NUR in der Datei: Seiten und Widget lesen dieselbe Quelle und
-- zeigen so immer dasselbe Gericht.
-- Bedienung (Manifest "input": true): Drehen blaettert durch Uebersicht, Zutaten, Naehrwerte und Zubereitung; Taster zweimal
-- hintereinander (3 s) lost ein neues Gericht.
-- Datei "recipe": je Zeile ein Eintrag, erstes Zeichen = Art (T Titel, U Link, M Meta, I Zutat, S Schritt, N Naehrwert "Name=Wert").

local RANDOM_URL = "https://www.chefkoch.de/rezepte/zufallsrezept/"
local ARM_SECONDS = 3

--#include text
--#include ui

local function en_(ctx) return ctx.lang == "en" end

-- ---------------------------------------------------------------------------------------------------------------------
-- Ernaehrungsart (wie in der eingebauten App): Stichworte der Quelle, dann Zutaten-Scan. 'V' vegan, 'v' vegetarisch,
-- 'f' Fisch, 'm' Fleisch, '' unbekannt.
local MEAT = { "hähnchen", "haehnchen", "huhn", "hühner", "huehner", "pute", "puten", "rind", "schwein", "speck", "schinken",
  "wurst", "hack", "lamm", "ente", "kalb", "salami", "mett", "gans", "bacon", "chorizo", "leber", "bratwurst", "kassler",
  "gulasch", "steak", "filet vom rind", "hirsch", "reh", "wild" }
local FISH = { "fisch", "lachs", "thunfisch", "garnele", "forelle", "kabeljau", "shrimp", "scampi", "seelachs", "zander",
  "dorade", "hering", "matjes", "sardelle", "anchovis", "krabben", "muschel", "tintenfisch", "calamari" }

local function classify(r)
  local kw = tostring(r.keywords or ""):lower()
  if kw:find("vegan", 1, true) then return "V" end
  if kw:find("vegetarisch", 1, true) or kw:find("vegetarian", 1, true) then return "v" end
  local fish = false
  for _, ing in ipairs(r.ingredients or {}) do
    local l = ing:lower()
    for _, w in ipairs(MEAT) do
      if l:find(w, 1, true) then return "m" end
    end
    for _, w in ipairs(FISH) do
      if l:find(w, 1, true) then fish = true end
    end
  end
  if fish then return "f" end
  if #(r.ingredients or {}) > 0 then return "v" end
  return ""
end

local function dietLabel(d, en)
  if d == "V" then return "Vegan" end
  if d == "v" then return en and "Vegetarian" or "Vegetarisch" end
  if d == "f" then return en and "Fish" or "Fisch" end
  if d == "m" then return en and "Meat" or "Fleisch" end
  return ""
end

-- Kleines Ernaehrungs-Symbol in einer Box von etwa 22 x 22 Pixeln (Blatt, Fisch, Keule), Ecke oben links (x, y).
local function dietGlyph(d, x, y, c)
  local cx, cy = x + 11, y + 11
  if d == "v" or d == "V" then
    draw.polygon({ cx - 7, cy + 7, cx + 6, cy - 8, cx + 7, cy + 2 }, c, true)
    draw.line(cx - 7, cy + 7, cx - 2, cy + 1, c)
  elseif d == "f" then
    draw.circle(cx + 1, cy, 6, c, true)
    draw.triangle(cx - 5, cy, cx - 10, cy - 5, cx - 10, cy + 5, c, true)
  elseif d == "m" then
    draw.circle(cx + 3, cy - 3, 6, c, true)
    draw.line(cx - 1, cy + 1, cx - 7, cy + 7, c)
    draw.line(cx, cy + 2, cx - 6, cy + 8, c)
    draw.circle(cx - 8, cy + 8, 2, c, true)
  end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Speichern
local function cutBytes(s, n)
  if #s <= n then return s end
  s = s:sub(1, n)
  while #s > 0 and (s:byte(#s) & 0xC0) == 0x80 do s = s:sub(1, #s - 1) end
  if #s > 0 and s:byte(#s) >= 0xC0 then s = s:sub(1, #s - 1) end
  return s
end

local function nosep(s) return (tostring(s or ""):gsub("|", "/")) end

local function store(ctx, r, today, servings, newDay)
  local title = cutBytes(clean(r.title, 95), 300)
  local meta = cutBytes(table.concat({ classify(r), nosep(r.time), nosep(r.yield), nosep(r.source) }, "|"), 300)
  local url = r.url ~= "" and cutBytes(r.url, 190) or ""
  local out = { "T" .. title, "U" .. url, "M" .. meta }
  for _, ing in ipairs(r.ingredients or {}) do out[#out + 1] = "I" .. cutBytes(clean(ing, 150), 250) end
  for _, st in ipairs(r.steps or {}) do out[#out + 1] = "S" .. cutBytes(clean(st, 400), 600) end
  for _, p in ipairs(r.nutrition or {}) do out[#out + 1] = "N" .. clean(tostring(p[1]), 20) .. "=" .. clean(tostring(p[2]), 28) end
  local ok, err = file.write("recipe", table.concat(out, "\n"))
  if not ok then
    log("Rezeptdatei: " .. tostring(err))
    return false
  end
  ctx.data.set("sv", servings)
  if newDay then
    ctx.data.set("d", today)
    ctx.data.set("v", 1)
  end
  return true
end

function on_fetch(ctx)
  local t = time.localtime()
  if t == nil then
    log("Uhrzeit noch nicht synchronisiert")
    return false
  end
  local today = t.year * 10000 + t.month * 100 + t.day
  local servings = math.floor(tonumber(ctx.cfg.servings) or 2)
  if servings < 1 then servings = 1 elseif servings > 12 then servings = 12 end
  local reroll = ctx.data.get("rq") == 1
  local saved = file.read("recipe")
  local have = type(saved) == "string" and saved ~= ""

  if have and not reroll and ctx.data.get("d") == today then
    if ctx.data.get("sv") == servings then return true end
    -- Portionen geaendert: dasselbe Rezept noch einmal laden und neu umrechnen
    local url = have and saved:match("\nU([^\n]+)") or nil
    if type(url) == "string" and url ~= "" then
      local r, err = recipe.fetch(url, servings)
      if r ~= nil and #r.ingredients > 0 and store(ctx, r, today, servings, false) then return true end
      log("Neu umrechnen: " .. tostring(err))
      return false
    end
    ctx.data.set("sv", servings)
    return true
  end

  -- neues Gericht losen (zwei Versuche: selten hat eine Seite kein lesbares Rezept)
  local r, err
  for attempt = 1, 2 do
    r, err = recipe.fetch(RANDOM_URL, servings)
    if r ~= nil and #r.ingredients > 0 then break end
    if r ~= nil then err = "keine Zutaten" end
    r = nil
    log("Los " .. attempt .. ": " .. tostring(err))
    if attempt < 2 then time.sleep(600) end
  end
  if r == nil then return false end
  if not store(ctx, r, today, servings, true) then return false end
  ctx.data.set("rq", nil)
  ctx.data.set("arm", nil)
  log("Gericht gelost: " .. tostring(r.title))
  return true
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Lesen

local function lines(s)
  local list = {}
  if type(s) ~= "string" then return list end
  for l in s:gmatch("[^\n]+") do list[#list + 1] = l end
  return list
end

-- Liest das gespeicherte Rezept aus der Datei "recipe". full = false: nur Titel, Link, Meta (Widget; die Datei beginnt damit).
local function loadRecipe(ctx, full)
  local raw = file.read("recipe")
  if type(raw) ~= "string" or raw == "" then return nil end
  local d = { title = "", url = "", day = ctx.data.get("d") or 0, ing = {}, steps = {}, nutri = {}, diet = "", time = "", yield = "", source = "" }
  for l in raw:gmatch("[^\n]+") do
    local kind, body = l:sub(1, 1), l:sub(2)
    if kind == "T" then d.title = body
    elseif kind == "U" then d.url = body
    elseif kind == "M" then
      local parts = {}
      for p in (body .. "|"):gmatch("([^|]*)|") do parts[#parts + 1] = p end
      d.diet, d.time, d.yield, d.source = parts[1] or "", parts[2] or "", parts[3] or "", parts[4] or ""
      if not full then break end
    elseif kind == "I" then d.ing[#d.ing + 1] = body
    elseif kind == "S" then d.steps[#d.steps + 1] = body
    elseif kind == "N" then
      local k, v = body:match("^(.-)=(.*)$")
      if k ~= nil then d.nutri[#d.nutri + 1] = { k, v } end
    end
  end
  if d.title == "" then return nil end
  return d
end

local SAMPLE = {
  title = "Linsen-Dal mit Spinat und Naan", url = "https://www.chefkoch.de/rezepte/1234567890/Linsen-Dal.html", day = 20261005,
  diet = "V", time = "35 Min", yield = "2 Portionen", source = "www.chefkoch.de",
  ing = { "200 g rote Linsen", "1 Zwiebel", "2 Zehen Knoblauch", "1 Stück Ingwer", "250 g Blattspinat", "400 ml Kokosmilch", "2 EL Currypulver", "1 TL Salz", "2 Naan-Brote" },
  steps = { "Zwiebel, Knoblauch und Ingwer fein hacken und in Öl glasig anbraten.", "Currypulver und Linsen zugeben, mit Kokosmilch und 300 ml Wasser ablöschen und 15 Minuten köcheln lassen.", "Spinat unterheben, mit Salz abschmecken und mit Naan servieren." },
  nutri = { { "Kalorien", "520 kcal" }, { "Eiweiß", "22 g" }, { "Fett", "21 g" }, { "Kohlenhydrate", "58 g" } },
}
local SAMPLE_EN = {
  title = "Lentil dal with spinach and naan", url = SAMPLE.url, day = 20261005, diet = "V", time = "35 min", yield = "2 servings", source = "www.chefkoch.de",
  ing = SAMPLE.ing, steps = SAMPLE.steps, nutri = SAMPLE.nutri,
}

local function dateText(day, en)
  local y, m, d = day // 10000, (day // 100) % 100, day % 100
  if en then return string.format("%04d-%02d-%02d", y, m, d) end
  return string.format("%02d.%02d.%04d", d, m, y)
end

local function isToday(day)
  local t = time.localtime()
  return t ~= nil and (t.year * 10000 + t.month * 100 + t.day) == day
end

local function emptyState(ctx)
  local en = en_(ctx)
  notice("info", en and "No meal drawn yet" or "Noch kein Gericht gelost",
    en and "The next Wi-Fi window draws one automatically." or "Beim nächsten WLAN-Fenster wird automatisch gelost.")
end

-- Seitenlaenge des QR-Codes, die die Firmware fuer diesen Text bei maxSize Pixeln zeichnet (gleiche Tabelle wie draw.qr).
local QR_CAPS = { 53, 78, 106, 134, 154, 192 }
local function qrSize(s, maxSize)
  for i, cap in ipairs(QR_CAPS) do
    if #s <= cap then
      local modules = 4 * (i + 2) + 17
      local scale = math.min(6, maxSize // modules)
      if scale < 2 then return 0 end
      return modules * scale
    end
  end
  return 0
end

-- Seite 1: Uebersicht
local function drawOverview(ctx, d)
  local en = en_(ctx)
  local W = draw.width
  local x0 = 28
  local qrBox = 210
  local textW = W - 2 * x0 - qrBox - 24
  local y = draw.top + 78
  local tl = wrapLines(d.title, textW, "large", 3)
  for _, l in ipairs(tl) do
    draw.text(x0, y, l, "large", color.BLACK, "left")
    y = y + 40
  end
  y = y + 4
  local label = dietLabel(d.diet, en)
  if label ~= "" then
    local bw = 22 + 8 + draw.measure(label, "normal") + 28
    draw.rect(x0, y, bw, 36, color.ACCENT, true, 10)
    dietGlyph(d.diet, x0 + 10, y + 7, color.ACCENT_INK)
    draw.text(x0 + 40, y + 25, label, "normal", color.ACCENT_INK, "left")
    y = y + 56
  end
  local meta = {}
  for _, p in ipairs({ d.source, d.yield, d.time }) do if p ~= "" then meta[#meta + 1] = p end end
  if #meta > 0 then
    draw.text(x0, y + 8, fit(table.concat(meta, " · "), textW, "normal"), "normal", color.BLACK, "left")
    y = y + 34
  end
  if d.day > 0 then
    local txt = isToday(d.day) and (en and "Drawn today" or "Heute gelost") or ((en and "Drawn on " or "Gelost am ") .. dateText(d.day, en))
    draw.text(x0, y + 8, txt, "small", color.BLACK, "left")
  end
  -- QR-Code zur echten Rezeptseite, rechts
  if d.url ~= "" then
    local size = qrSize(d.url, qrBox)
    if size > 0 then
      local qx = W - x0 - qrBox + (qrBox - size) // 2
      local qy = draw.top + 96
      draw.text(W - x0 - qrBox // 2, qy - 14, en and "Open recipe online:" or "Rezept online öffnen:", "small", color.BLACK, "center")
      draw.rect(qx - 8, qy - 4, size + 16, size + 16, color.BLACK, false, 10)
      draw.qr(d.url, qx, qy + 4, qrBox)
    end
  end
end

-- Ansichten (Drehen blaettert): Uebersicht, Zutaten-Seiten, Schritte-Seiten, Naehrwerte. Die Aufteilung haengt nur von den Daten ab
-- (nicht von Schriftmassen), damit on_input (ohne Display) und on_draw dieselbe Anzahl sehen.
local ING_LINES_PER_PAGE = 30 -- geschaetzte Zeilen je Seite (2 Spalten)
local STEP_CHARS_PER_PAGE = 650

local function buildViews(d)
  local v = { { k = "o" } }
  local from, lines = 1, 0
  for i, ing in ipairs(d.ing) do
    local need = math.max(1, (#ing + 33) // 34)
    if lines + need > ING_LINES_PER_PAGE and i > from then
      v[#v + 1] = { k = "i", from = from, to = i - 1 }
      from, lines = i, 0
    end
    lines = lines + need
  end
  if #d.ing >= from then v[#v + 1] = { k = "i", from = from, to = #d.ing } end
  -- Reihenfolge beim Blaettern: Uebersicht, Zutaten, Naehrwerte, Zubereitung
  if #d.nutri > 0 then v[#v + 1] = { k = "n" } end
  from = 1
  local chars = 0
  for i, st in ipairs(d.steps) do
    if chars + #st > STEP_CHARS_PER_PAGE and i > from then
      v[#v + 1] = { k = "s", from = from, to = i - 1 }
      from, chars = i, 0
    end
    chars = chars + #st
  end
  if #d.steps >= from then v[#v + 1] = { k = "s", from = from, to = #d.steps } end
  return v
end

local function viewIndex(ctx, count)
  local i = math.floor(tonumber(ctx.data.get("v")) or 1)
  if i < 1 or i > count then i = 1 end
  return i
end

local function footer(ctx, idx, count, hint)
  local W, H = draw.width, draw.height
  draw.text(W - 28, H - 10, idx .. " / " .. count, "small", color.BLACK, "right")
  if hint then draw.text(28, H - 10, hint, "small", color.BLACK, "left") end
end

-- Zutaten in zwei Spalten; die groesste Schrift waehlen, in die alles passt (sonst die kleinste, abgeschnitten).
local function drawIngredients(ctx, d, view)
  local W, H = draw.width, draw.height
  local x0, gap = 28, 28
  local colW = (W - 2 * x0 - gap) // 2
  local top, bottom = draw.top + 22, H - 34
  local sets = { { "normal", 24, 22 }, { "small", 18, 15 } }
  local chosen
  for idx, s in ipairs(sets) do
    local font, lh = s[1], s[2]
    local col, y = 1, top
    local items, ok = {}, true
    for i = view.from, view.to do
      local wl = wrapLines(d.ing[i], colW - 22, font, 3)
      local need = #wl * lh + 6
      if y + need > bottom then
        col = col + 1
        y = top
        if col > 2 then ok = false; break end
      end
      items[#items + 1] = { col = col, y = y, lines = wl }
      y = y + need
    end
    if ok or idx == #sets then chosen = { font = font, lh = lh, items = items }; break end
  end
  for _, it in ipairs(chosen.items) do
    local x = x0 + (it.col - 1) * (colW + gap)
    draw.circle(x + 5, it.y + chosen.lh // 2 - 3, 3, color.ACCENT, true)
    for k, l in ipairs(it.lines) do
      draw.text(x + 20, it.y + k * chosen.lh - 5, l, chosen.font, color.BLACK, "left")
    end
  end
end

local function drawSteps(ctx, d, view)
  local W, H = draw.width, draw.height
  local x0 = 28
  local textW = W - 2 * x0 - 36
  local top, bottom = draw.top + 22, H - 34
  local sets = { { "normal", 25 }, { "small", 18 } }
  local chosen
  for idx, s in ipairs(sets) do
    local font, lh = s[1], s[2]
    local y, ok, blocks = top, true, {}
    for i = view.from, view.to do
      local wl = wrapLines(d.steps[i], textW, font, 60)
      local need = #wl * lh + 8
      if y + need > bottom and #blocks > 0 then ok = false; break end
      blocks[#blocks + 1] = { n = i, y = y, lines = wl }
      y = y + need
    end
    if ok or idx == #sets then chosen = { font = font, lh = lh, blocks = blocks }; break end
  end
  for _, b in ipairs(chosen.blocks) do
    draw.text(x0 + 24, b.y + chosen.lh - 5, tostring(b.n) .. ".", chosen.font, color.ACCENT_TEXT, "right")
    for k, l in ipairs(b.lines) do
      if b.y + k * chosen.lh - 5 <= bottom + 6 then
        draw.text(x0 + 36, b.y + k * chosen.lh - 5, l, chosen.font, color.BLACK, "left")
      end
    end
  end
end

local function drawNutrition(ctx, d)
  local W = draw.width
  local x0 = 80
  local y = draw.top + 70
  for _, p in ipairs(d.nutri) do
    draw.text(x0, y, p[1], "normal", color.BLACK, "left")
    draw.text(W - x0, y, p[2], "normal", color.BLACK, "right")
    draw.line(x0, y + 12, W - x0, y + 12, color.BLACK)
    y = y + 44
    if y > draw.height - 40 then break end
  end
end

function on_draw(ctx, page)
  draw.clear(color.WHITE)
  local d = loadRecipe(ctx, true)
  if d == nil then emptyState(ctx); return end
  local en = en_(ctx)
  local views = buildViews(d)
  local idx = viewIndex(ctx, #views)
  local view = views[idx]
  local hint
  if view.k == "i" then drawIngredients(ctx, d, view)
  elseif view.k == "s" then drawSteps(ctx, d, view)
  elseif view.k == "n" then drawNutrition(ctx, d)
  else
    drawOverview(ctx, d)
    hint = en and "Turn: browse · button twice: new meal" or "Drehen: blättern · Taster 2x: neues Gericht"
  end
  if view.k == "i" then draw.text(28, draw.height - 10, en and "Ingredients" or "Zutaten", "small", color.ACCENT_TEXT, "left")
  elseif view.k == "s" then draw.text(28, draw.height - 10, en and "Instructions" or "Zubereitung", "small", color.ACCENT_TEXT, "left")
  elseif view.k == "n" then draw.text(28, draw.height - 10, en and "Nutrition" or "Nährwerte", "small", color.ACCENT_TEXT, "left") end
  footer(ctx, idx, #views, hint)
end

-- Drehen: durch die Ansichten blaettern. Klick: erster Klick scharf schalten (LED), zweiter innerhalb von 3 s lost neu.
function on_input(ctx, kind, n)
  if kind == "turn" then
    local d = loadRecipe(ctx, true)
    if d == nil then return false end
    local count = #buildViews(d)
    if count < 2 then return false end
    local idx = viewIndex(ctx, count)
    idx = ((idx - 1 + n) % count) + 1
    ctx.data.set("v", idx)
    return true
  end
  local now = time.now()
  local armed = ctx.data.get("arm")
  if type(armed) == "number" and now - armed >= 0 and now - armed <= ARM_SECONDS then
    ctx.data.set("arm", nil)
    ctx.data.set("rq", 1)
    return "fetch"
  end
  ctx.data.set("arm", now)
  return "blip"
end

-- Widget: Name des Gerichts (bis zu 2 Zeilen), darunter Ernaehrungs-Symbol, Art und Zeit.
function on_widget(ctx, box)
  local en = en_(ctx)
  local d = loadRecipe(ctx, false)
  if ctx.sample then d = en and SAMPLE_EN or SAMPLE end
  if d == nil then
    draw.text(box.x + 12, box.y + 22, en and "No meal drawn yet" or "Noch kein Gericht gelost", "normal", color.BLACK, "left")
    return
  end
  local font = (box.font == -1) and "small" or "normal"
  local lh = (font == "small") and 15 or 18
  local textW = math.max(box.w - 24, 20)
  local maxY = box.y + box.h - 4
  local tl = wrapLines(d.title, textW, font, 2)
  local y = box.y + 18
  for _, l in ipairs(tl) do
    draw.text(box.x + 12, y, l, font, color.BLACK, "left")
    y = y + lh
  end
  local rowTop = y + 2
  if rowTop + 22 <= maxY then
    local label = dietLabel(d.diet, en)
    local lx = box.x + 12
    if label ~= "" then
      dietGlyph(d.diet, lx, rowTop, color.ACCENT)
      lx = lx + 26
      draw.text(lx, rowTop + 17, label, "small", color.BLACK, "left")
      lx = lx + draw.measure(label, "small") + 12
    end
    if d.time ~= "" then
      draw.text(lx, rowTop + 17, fit((label ~= "" and "· " or "") .. d.time, box.x + box.w - 8 - lx, "small"), "small", color.BLACK, "left")
    end
  end
end
