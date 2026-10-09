-- Aktien & Krypto (Skript-Variante der eingebauten Aktien-App): Kurse und Tagesverlauf ueber Twelve Data,
-- zwei Seiten (Aktien/Krypto), drei Stile (Bento/Slate/Nano), Dashboard-Widget. Skript-API Level 7.
--
-- Ablauf: on_fetch holt je Lauf nur so viele Symbole, wie der Tarif an Abrufen je Minute erlaubt (kostenlos: 8,
-- jedes Symbol kostet je Kurs und je Verlauf einen), und geht bei jedem Lauf ein Stueck in der Liste weiter
-- ("cur"). Die Datensaetze liegen je Seite in einem Textblock "q1" (Aktien) / "q2" (Krypto), eine Zeile je
-- Symbol: "SYMBOL<TAB>Kurs<TAB>Aenderung %<TAB>Waehrung<TAB>Verlauf". Der Verlauf steht als 24 Zeichen (0-9, a-z):
-- jeder Punkt auf 36 Stufen zwischen Tiefst- und Hoechstwert umgerechnet (die Form genuegt fuer die Sparkline).

local MAX_PER_PAGE = 9
local HIST_N = 24
local QUOTE_CHUNK = 9
local HIST_CHUNK = 5
local CHARS = "0123456789abcdefghijklmnopqrstuvwxyz"

--#include text
--#include ui

-- Bekannte Symbole mit schoenem Namen (wie der feste Katalog der eingebauten App)
local CATALOG = {
  DAX = "DAX", SPX = "S&P 500", DJI = "Dow Jones", IXIC = "Nasdaq",
  AAPL = "Apple", MSFT = "Microsoft", GOOGL = "Alphabet", AMZN = "Amazon", TSLA = "Tesla", NVDA = "Nvidia",
  META = "Meta", SAP = "SAP", SIE = "Siemens", VOW3 = "Volkswagen", ALV = "Allianz", BMW = "BMW",
  ["BTC/EUR"] = "Bitcoin", ["ETH/EUR"] = "Ethereum", ["SOL/EUR"] = "Solana", ["BNB/EUR"] = "BNB", ["XRP/EUR"] = "XRP",
  ["ADA/EUR"] = "Cardano", ["DOGE/EUR"] = "Dogecoin", ["DOT/EUR"] = "Polkadot", ["LINK/EUR"] = "Chainlink",
  ["LTC/EUR"] = "Litecoin",
}

-- Ohne eigene Eintraege laufen diese Listen (damit nach dem Eintragen des API-Keys sofort etwas erscheint)
local DEFAULTS = {
  { "DAX", "SPX", "AAPL", "MSFT", "SAP" },
  { "BTC/EUR", "ETH/EUR", "SOL/EUR" },
}

-- ---------------------------------------------------------------------------
-- Symbollisten aus den Einstellungen
-- ---------------------------------------------------------------------------

-- "SYMBOL" oder "Name=SYMBOL" -> { sym, label } (nil bei ungueltigen Eintraegen). Krypto ohne "/" bekommt "/EUR".
local function parseEntry(raw, crypto)
  if type(raw) ~= "string" then return nil end
  local name, sym = raw:match("^(.-)=(.+)$")
  if not sym then sym = raw end
  sym = trim(sym):upper()
  if sym == "" or #sym > 15 or not sym:match("^[A-Z0-9%./:_%-]+$") then return nil end
  if crypto and not sym:find("/", 1, true) then sym = sym .. "/EUR" end
  name = name and clean(name, 23) or ""
  local label = name ~= "" and name or (CATALOG[sym] or sym)
  return { sym = sym, label = label }
end

-- Symbole einer Seite (1 = Aktien, 2 = Krypto): Fokus-Symbol zuerst, dann die Liste, ohne Doppelte, hoechstens 9.
local function symbolsFor(ctx, p)
  local out, seen = {}, {}
  local function add(e)
    if e and not seen[e.sym] and #out < MAX_PER_PAGE then
      seen[e.sym] = true
      out[#out + 1] = e
    end
  end
  local focus = ctx.cfg[p == 1 and "focusStock" or "focusCrypto"]
  local hasFocus = type(focus) == "string" and trim(focus) ~= ""
  if hasFocus then add(parseEntry(focus, p == 2)) end
  local list = ctx.cfg[p == 1 and "stocks" or "crypto"]
  if type(list) ~= "table" or #list == 0 then
    if hasFocus then return out end
    list = DEFAULTS[p]
  end
  for _, raw in ipairs(list) do add(parseEntry(raw, p == 2)) end
  return out
end

-- ---------------------------------------------------------------------------
-- Gespeicherte Datensaetze
-- ---------------------------------------------------------------------------

local function readPage(ctx, p)
  local map = {}
  local raw = ctx.data.get("q" .. p)
  if type(raw) ~= "string" then return map end
  for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
    local sym, price, pct, cur, hist = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
    local pr = tonumber(price)
    if sym and pr then
      map[sym] = { price = pr, pct = tonumber(pct) or 0, cur = cur, hist = hist }
    end
  end
  return map
end

local function writePage(ctx, p, order, recs)
  local lines = {}
  for _, s in ipairs(order) do
    local r = recs[s.sym]
    if r then
      lines[#lines + 1] = s.sym .. "\t" .. string.format("%.8g", r.price) .. "\t" .. string.format("%.4f", r.pct)
        .. "\t" .. r.cur .. "\t" .. r.hist
    end
  end
  local text = table.concat(lines, "\n")
  while #text > 1000 and #lines > 1 do
    lines[#lines] = nil
    text = table.concat(lines, "\n")
  end
  ctx.data.set("q" .. p, text)
end

-- Verlaufswerte (aelteste zuerst) -> 24 Zeichen auf 36 Stufen
local function encodeHist(vals)
  local n = #vals
  if n < 2 then return "" end
  local lo, hi = vals[1], vals[1]
  for i = 2, n do
    if vals[i] < lo then lo = vals[i] end
    if vals[i] > hi then hi = vals[i] end
  end
  local out = {}
  for i = 1, n do
    local k = 17
    if hi - lo > 1e-9 then k = math.floor((vals[i] - lo) / (hi - lo) * 35 + 0.5) end
    out[i] = CHARS:sub(k + 1, k + 1)
  end
  return table.concat(out)
end

local function decodeHist(s)
  local vals = {}
  for i = 1, #s do
    local k = CHARS:find(s:sub(i, i), 1, true)
    if k then vals[#vals + 1] = k - 1 end
  end
  return vals
end

-- ---------------------------------------------------------------------------
-- Abruf
-- ---------------------------------------------------------------------------

-- Gibt das JSON-Objekt zurueck oder nil + Grund: badkey | limit | net | http | parse | api
local function apiGet(url)
  local r = http.request{ url = url, headers = { Accept = "application/json" } }
  if r == nil then return nil, "net" end
  if r.status == 401 or r.status == 403 then return nil, "badkey" end
  if r.status == 429 then return nil, "limit" end
  if r.status ~= 200 then return nil, "http" end
  local doc = decodeCut(r.body, 1)
  if type(doc) ~= "table" then return nil, "parse" end
  -- Fehlerobjekt ueber der ganzen Antwort (bei nur einem Symbol auch "Symbol unbekannt")
  if doc.status == "error" and doc.close == nil and doc.values == nil then
    local c = tonumber(doc.code)
    if c == 401 or c == 403 then return nil, "badkey" end
    if c == 429 then return nil, "limit" end
    return nil, "api"
  end
  return doc
end

local function symbolParam(chunk)
  local parts = {}
  for i, s in ipairs(chunk) do parts[i] = text.url_encode(s.sym) end
  return table.concat(parts, ",")
end

-- Antwort fuer ein Symbol: bei genau einem angefragten Symbol steht es direkt in der Antwort, sonst unter dem Symbol
local function entryOf(doc, chunk, sym)
  if #chunk == 1 then return doc end
  local e = doc[sym]
  if type(e) == "table" then return e end
  return nil
end

local RANK = { badkey = 5, limit = 4, net = 3, http = 3, parse = 2, api = 1 }

function on_fetch(ctx)
  local key = ctx.cfg.apiKey
  if type(key) ~= "string" or trim(key) == "" then
    ctx.data.set("st", "nokey")
    return
  end
  key = text.url_encode(trim(key))
  -- alle Symbole beider Seiten: { page, sym, label }
  local pages, all = { symbolsFor(ctx, 1), symbolsFor(ctx, 2) }, {}
  -- abwechselnd Aktie/Krypto, damit beide Seiten schon im ersten Lauf Daten bekommen (sonst fuellen bei
  -- kleinem Abrufbudget erst die Aktien die ganze Liste, die Krypto-Seite bliebe lange leer)
  for i = 1, math.max(#pages[1], #pages[2]) do
    for p = 1, 2 do
      local s = pages[p][i]
      if s then all[#all + 1] = { page = p, sym = s.sym, label = s.label } end
    end
  end
  if #all == 0 then
    ctx.data.set("st", "none")
    return
  end
  local spark = ctx.cfg.spark ~= false
  local budget = ctx.cfg.plan == "paid" and 60 or 8
  local k = math.max(1, math.min(#all, budget // (spark and 2 or 1)))
  local cursor = tonumber(ctx.data.get("cur")) or 0
  if cursor >= #all then cursor = 0 end
  local batch = {}
  for i = 0, k - 1 do batch[#batch + 1] = all[(cursor + i) % #all + 1] end

  local recs = { readPage(ctx, 1), readPage(ctx, 2) }
  local worst, worstRank, okAny = nil, 0, false
  local calls = 0
  local function note(why)
    if why and (RANK[why] or 0) > worstRank then worst, worstRank = why, RANK[why] end
  end
  local function pause()
    calls = calls + 1
    if calls > 1 then time.sleep(250) end
  end

  -- Kurse in Gruppen zu je 9 Symbolen
  local quoted = {}
  for from = 1, #batch, QUOTE_CHUNK do
    local chunk = {}
    for i = from, math.min(from + QUOTE_CHUNK - 1, #batch) do chunk[#chunk + 1] = batch[i] end
    pause()
    local doc, why = apiGet("https://api.twelvedata.com/quote?symbol=" .. symbolParam(chunk) .. "&apikey=" .. key)
    if doc then
      for _, s in ipairs(chunk) do
        local q = entryOf(doc, chunk, s.sym)
        local price = q and tonumber(q.close)
        if price then
          local cur = type(q.currency) == "string" and q.currency or ""
          if cur == "" then cur = s.sym:match("/(%u+)$") or "" end
          local old = recs[s.page][s.sym]
          recs[s.page][s.sym] = {
            price = price,
            pct = tonumber(q.percent_change) or 0,
            cur = clean(cur, 3),
            hist = old and old.hist or "",
          }
          quoted[#quoted + 1] = s
          okAny = true
        end
      end
    else
      note(why)
    end
  end

  -- Verlauf in Gruppen zu je 5 Symbolen (nur fuer Symbole, deren Kurs gerade ankam)
  if spark and #quoted > 0 and worstRank < RANK.limit then
    for from = 1, #quoted, HIST_CHUNK do
      local chunk = {}
      for i = from, math.min(from + HIST_CHUNK - 1, #quoted) do chunk[#chunk + 1] = quoted[i] end
      pause()
      local doc, why = apiGet("https://api.twelvedata.com/time_series?symbol=" .. symbolParam(chunk)
        .. "&interval=1h&outputsize=" .. HIST_N .. "&apikey=" .. key)
      if doc then
        for _, s in ipairs(chunk) do
          local e = entryOf(doc, chunk, s.sym)
          local values = e and e.values
          if type(values) == "table" then
            local vals = {}
            for idx = #values, 1, -1 do   -- Twelve Data liefert die neuesten zuerst
              local c = type(values[idx]) == "table" and tonumber(values[idx].close)
              if c then vals[#vals + 1] = c end
            end
            if #vals >= 2 then recs[s.page][s.sym].hist = encodeHist(vals) end
          end
        end
      else
        note(why)   -- Kurse bleiben gueltig, nur ohne neuen Verlauf
      end
    end
  end

  -- Nicht mehr eingerichtete Symbole fallen weg, die Reihenfolge ist die der Einstellungen
  for p = 1, 2 do writePage(ctx, p, pages[p], recs[p]) end
  ctx.data.set("cur", tostring((cursor + k) % #all))
  ctx.data.set("st", okAny and "ok" or (worst or "api"))
  if not okAny and (ctx.data.get("q1") or "") == "" and (ctx.data.get("q2") or "") == "" then return end
  if not okAny then return false end
end

-- ---------------------------------------------------------------------------
-- Formatierung und Bausteine
-- ---------------------------------------------------------------------------

-- Kurs mit Tausenderpunkt: unter 1 vier, sonst zwei Nachkommastellen
local function fmtPrice(x, en)
  local s = (x < 1 and x > -1) and string.format("%.4f", x) or string.format("%.2f", x)
  local int, frac = s:match("^(-?%d+)%.(%d+)$")
  local sign = ""
  if int:sub(1, 1) == "-" then sign, int = "-", int:sub(2) end
  local sep = en and "," or "."
  local g = int:reverse():gsub("(%d%d%d)", "%1" .. sep)
  g = g:reverse()
  if g:sub(1, 1) == sep then g = g:sub(2) end
  return sign .. g .. (en and "." or ",") .. frac
end

local function pctText(pct, en)
  return (pct >= 0 and "+" or "-") .. num(math.abs(pct), 2, en) .. " %"
end

local function badgeWidth(pct, font, en)
  return (font == "small" and 6 or 8) + 4 + draw.measure(pctText(pct, en), font)
end

-- Dreieck + farbiger Prozentwert; y = Grundlinie, gibt die Breite zurueck
local function drawBadge(x, y, pct, font, en)
  local col = pct >= 0 and color.GREEN or color.RED
  local tri = font == "small" and 6 or 8
  local cy = y - tri // 2 - 1
  if pct >= 0 then
    draw.triangle(x, cy + tri // 2, x + tri, cy + tri // 2, x + tri // 2, cy - tri // 2, col, true)
  else
    draw.triangle(x, cy - tri // 2, x + tri, cy - tri // 2, x + tri // 2, cy + tri // 2, col, true)
  end
  local t = pctText(pct, en)
  draw.text(x + tri + 4, y, t, font, col, "left")
  return tri + 4 + draw.measure(t, font)
end

-- Verlaufslinie (zwei Pixel stark)
local function sparkline(x, y, w, h, vals, col)
  local n = #vals
  if n < 2 or w < 8 then return end
  local px, py
  for i = 1, n do
    local cx = x + (i - 1) * (w - 1) // (n - 1)
    local cy = y + h - 1 - math.floor(vals[i] / 35 * (h - 1) + 0.5)
    if px then
      draw.line(px, py, cx, cy, col)
      draw.line(px, py + 1, cx, cy + 1, col)
    end
    px, py = cx, cy
  end
end

local function trendColor(pct) return pct >= 0 and color.GREEN or color.RED end

-- Datensaetze einer Seite in der Reihenfolge der Einstellungen
local function pageItems(ctx, p)
  if ctx.sample then -- Beispieldaten fuer die Widget-Vorschau im Dashboard-Editor (CHANGELOG 559)
    local H = { "89abcdefghijkjihgfghijklm", "mlkjihgfeddefghijklmnopq", "5678abcdefghijklmnopqrstu" }
    if p == 2 then
      return {
        { label = "Bitcoin", sym = "BTC/EUR", price = 61250.5, pct = 1.8, cur = "EUR", hist = H[1]:sub(1, 24) },
        { label = "Ethereum", sym = "ETH/EUR", price = 2410.2, pct = -0.7, cur = "EUR", hist = H[2]:sub(1, 24) },
        { label = "Solana", sym = "SOL/EUR", price = 142.35, pct = 3.1, cur = "EUR", hist = H[3]:sub(1, 24) },
      }
    end
    return {
      { label = "DAX", sym = "DAX", price = 18432.5, pct = 0.8, cur = "EUR", hist = H[1]:sub(1, 24) },
      { label = "Apple", sym = "AAPL", price = 227.1, pct = -0.4, cur = "USD", hist = H[2]:sub(1, 24) },
      { label = "SAP", sym = "SAP", price = 198.4, pct = 1.2, cur = "EUR", hist = H[3]:sub(1, 24) },
    }
  end
  local recs = readPage(ctx, p)
  local out = {}
  for _, s in ipairs(symbolsFor(ctx, p)) do
    local r = recs[s.sym]
    if r then
      r.label, r.sym = s.label, s.sym
      out[#out + 1] = r
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Anzeige
-- ---------------------------------------------------------------------------

-- Leerzustand: true, wenn schon ein Hinweis gezeichnet wurde
local function emptyState(ctx, p, items)
  local en = ctx.lang == "en"
  local where = en and "Store -> Stocks & Crypto -> Settings" or "Store -> Aktien & Krypto -> Einstellungen"
  local key = ctx.cfg.apiKey
  if type(key) ~= "string" or trim(key) == "" then
    notice("gear", en and "No Twelve Data API key set." or "Kein Twelve-Data-API-Key hinterlegt.", where)
    return true
  end
  if #items > 0 then return false end
  if #symbolsFor(ctx, p) == 0 then
    notice("gear", p == 1 and (en and "No stock selected." or "Keine Aktie ausgewählt.")
      or (en and "No cryptocurrency selected." or "Keine Kryptowährung ausgewählt."), where)
    return true
  end
  local st = ctx.data.get("st")
  if st == nil then
    notice("clock", en and "Loading ..." or "Wird geladen ...")
  elseif st == "badkey" then
    notice("warning", en and "API key rejected." or "API-Key abgelehnt.", where)
  elseif st == "limit" then
    notice("warning", en and "Request limit reached." or "Abruflimit erreicht.", en and "Retrying shortly." or "Nächster Versuch in Kürze.")
  elseif st == "ok" then
    notice("clock", en and "Loading ..." or "Wird geladen ...", en and "More symbols follow with the next update." or "Weitere Symbole folgen beim nächsten Abruf.")
  else
    notice("warning", en and "Fetch failed." or "Abruf fehlgeschlagen.", en and "Retrying shortly." or "Nächster Versuch in Kürze.")
  end
  return true
end

-- "Bento": Kacheln mit Symbol, Aenderung, Kurs und Verlauf (3 Spalten)
local function drawCards(ctx, items)
  local en = ctx.lang == "en"
  local pos, tileW, tileH = gridLayout(#items, 3, draw.top + 2, draw.height - 16, 20, 12, 140)
  for i, r in ipairs(items) do
    local tx, ty = pos(i)
    card(tx, ty, tileW, tileH, color.ACCENT, 10)
    local bw = badgeWidth(r.pct, "small", en)
    draw.text(tx + 14, ty + 24, fit(r.label, tileW - 28 - bw - 8, "normal"), "normal", color.BLACK, "left")
    drawBadge(tx + tileW - 14 - bw, ty + 22, r.pct, "small", en)
    local price = fmtPrice(r.price, en)
    local priceY = ty + tileH - (tileH > 100 and 46 or 20)
    draw.text(tx + 14, priceY, price, "large", color.BLACK, "left")
    if r.cur ~= "" then
      draw.text(tx + 14 + draw.measure(price, "large") + 6, priceY, r.cur, "small", color.BLACK, "left")
    end
    if tileH > 100 then
      local vals = decodeHist(r.hist)
      if #vals >= 2 then sparkline(tx + 14, ty + tileH - 36, tileW - 28, 28, vals, trendColor(r.pct)) end
    end
  end
end

-- "Slate": eine Zeile je Symbol, Name + Aenderung links, Verlauf in der Mitte, Kurs rechts
local function drawFlat(ctx, items)
  local en = ctx.lang == "en"
  local W = draw.width
  local y, bottom = draw.top + 6, draw.height - 16
  local shown, rowH, truncated = rowLayout(#items, y, bottom, 50, 74, 16)
  local sparkX = 190
  for i = 1, shown do
    local r = items[i]
    local rowY = y + (i - 1) * rowH
    draw.text(24, rowY + 22, fit(r.label, sparkX - 24 - 8, "normal"), "normal", color.BLACK, "left")
    drawBadge(24, rowY + 38, r.pct, "small", en)
    local price = fmtPrice(r.price, en)
    local priceW = draw.measure(price, "large")
    local curW = r.cur ~= "" and (4 + draw.measure(r.cur, "small")) or 0
    local priceX = W - 26 - priceW - curW
    local vals = decodeHist(r.hist)
    if #vals >= 2 then
      local sparkW = priceX - 20 - sparkX
      if sparkW > 40 then sparkline(sparkX, rowY + 6, sparkW, 32, vals, trendColor(r.pct)) end
    end
    draw.text(priceX, rowY + 26, price, "large", color.BLACK, "left")
    if r.cur ~= "" then draw.text(priceX + priceW + 4, rowY + 26, r.cur, "small", color.BLACK, "left") end
    if i < shown then draw.line(24, rowY + rowH - 6, W - 24, rowY + rowH - 6, color.BLACK) end
  end
  if truncated then
    draw.text(W // 2, y + shown * rowH + 12,
      en and ("+" .. (#items - shown) .. " more (see Nano)") or ("+" .. (#items - shown) .. " weitere (siehe Nano-Stil)"),
      "small", color.BLACK, "center")
  end
end

-- "Nano": dichte Tabelle in kleiner Schrift
local function drawCompact(ctx, items)
  local en = ctx.lang == "en"
  local W = draw.width
  local y = draw.top + 4
  local rowH = (draw.height - 12 - y) // #items
  if rowH > 30 then rowH = 30 end
  local maxPrice, maxBadge = 0, 0
  for _, r in ipairs(items) do
    local w = draw.measure(fmtPrice(r.price, en), "small")
    if r.cur ~= "" then w = w + 4 + draw.measure(r.cur, "small") end
    if w > maxPrice then maxPrice = w end
    local bw = badgeWidth(r.pct, "small", en)
    if bw > maxBadge then maxBadge = bw end
  end
  local badgeX = W - 24 - maxBadge
  local priceX = badgeX - 16 - maxPrice
  for i, r in ipairs(items) do
    local rowY = y + (i - 1) * rowH
    local base = rowY + rowH // 2 + 4
    draw.text(24, base, fit(r.label, priceX - 8 - 24, "small"), "small", color.BLACK, "left")
    local price = fmtPrice(r.price, en)
    draw.text(priceX, base, price, "small", color.BLACK, "left")
    if r.cur ~= "" then draw.text(priceX + draw.measure(price, "small") + 4, base, r.cur, "small", color.BLACK, "left") end
    drawBadge(badgeX, base, r.pct, "small", en)
    if i < #items then draw.line(20, rowY + rowH - 1, W - 20, rowY + rowH - 1, color.BLACK) end
  end
end

function on_draw(ctx, page)
  draw.clear(color.WHITE)
  local p = math.max(1, math.min(page or 1, 2))
  local items = pageItems(ctx, p)
  if emptyState(ctx, p, items) then return end
  local style = ctx.cfg.style
  if style == "flat" then drawFlat(ctx, items)
  elseif style == "compact" then drawCompact(ctx, items)
  else drawCards(ctx, items) end
end

-- ---------------------------------------------------------------------------
-- Widget: Kursliste der gewaehlten Seite
-- ---------------------------------------------------------------------------

function on_widget(ctx, box)
  local en = ctx.lang == "en"
  local items = pageItems(ctx, ctx.cfg.wKind == "crypto" and 2 or 1)
  local font = ((box.font or 0) > 0) and "normal" or "small"
  if (box.font or 0) < 0 then font = "small" end
  local compact = ctx.cfg.wCompact == true
  local withSpark = not compact and ctx.cfg.wSpark ~= false
  local lineH = compact and 19 or 24
  local y = box.y + 17
  local maxY = box.y + box.h - 4
  local nameW = box.w * 34 // 100
  local function valueOf(r)
    return fmtPrice(r.price, en) .. " " .. (string.format("%+.1f", r.pct):gsub("%.", en and "." or ",")) .. "%"
  end
  -- Platz fuer die Werte zuerst, die Sparkline bekommt den Rest (hoechstens 20 % der Breite)
  local maxValue = 0
  for _, r in ipairs(items) do maxValue = math.max(maxValue, draw.measure(valueOf(r), font)) end
  local sparkX = box.x + 14 + nameW
  local sparkW = math.min(box.w * 20 // 100, box.x + box.w - 8 - maxValue - 8 - sparkX)
  local shown = 0
  for _, r in ipairs(items) do
    if y > maxY then break end
    local col = trendColor(r.pct)
    draw.text(box.x + 12, y, fit(r.label, nameW, font), font, color.BLACK, "left")
    if withSpark and sparkW >= 24 then
      local vals = decodeHist(r.hist)
      if #vals >= 2 then sparkline(sparkX, y - 13, sparkW, 12, vals, col) end
    end
    local vx = sparkX + math.max(sparkW, 0) + 4
    draw.text(box.x + box.w - 8, y, fit(valueOf(r), box.x + box.w - 8 - vx, font), font, col, "right")
    y = y + lineH
    shown = shown + 1
  end
  if shown == 0 then
    draw.text(box.x + 12, box.y + 16, ctx.data.get("st") == nil and (en and "No data yet" or "Noch keine Daten") or (en and "No quotes" or "Keine Kurse"), "small", color.BLACK, "left")
  end
end
