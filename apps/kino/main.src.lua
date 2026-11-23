-- Kino: aktuelle und kommende Filme aus The Movie Database (TMDB). Jeder Nutzer traegt seinen eigenen kostenlosen
-- TMDB-Schluessel ein. Dieses Produkt nutzt die TMDB-API, wird aber von TMDB weder unterstuetzt noch zertifiziert.
-- Skript-API Level 18 (http.request mit keep, http.image mit ram, file.read/write).
--#include theme
--#include text
--#include ui

local API = "https://api.themoviedb.org/3/movie/"
local IMG = "https://image.tmdb.org/t/p/w185"

local GENRE_DE = { [28] = "Action", [12] = "Abenteuer", [16] = "Animation", [35] = "Komödie", [80] = "Krimi", [99] = "Dokumentarfilm",
  [18] = "Drama", [10751] = "Familie", [14] = "Fantasy", [36] = "Historie", [27] = "Horror", [10402] = "Musik", [9648] = "Mystery",
  [10749] = "Liebesfilm", [878] = "Science-Fiction", [10770] = "TV-Film", [53] = "Thriller", [10752] = "Kriegsfilm", [37] = "Western" }
local GENRE_EN = { [28] = "Action", [12] = "Adventure", [16] = "Animation", [35] = "Comedy", [80] = "Crime", [99] = "Documentary",
  [18] = "Drama", [10751] = "Family", [14] = "Fantasy", [36] = "History", [27] = "Horror", [10402] = "Music", [9648] = "Mystery",
  [10749] = "Romance", [878] = "Sci-Fi", [10770] = "TV movie", [53] = "Thriller", [10752] = "War", [37] = "Western" }

local SAMPLE = {
  { "Der Wilde Roboter 2", "2026-11-27", 7.8, "Animation" }, { "Wicked: Teil drei", "2026-11-20", 7.1, "Fantasy" },
  { "Die Gaunerbande", "2026-11-13", 6.9, "Komödie" }, { "Stille im Wald", "2026-11-06", 6.4, "Thriller" },
  { "Mondschein", "2026-10-30", 7.5, "Drama" }, { "Last Stop Berlin", "2026-10-23", 6.2, "Krimi" },
}

local function dateShort(d, en)
  local y, m, dd = tostring(d or ""):match("^(%d+)-(%d+)-(%d+)$")
  if not y then return "" end
  if en then return string.format("%s/%s", m, dd) end
  return string.format("%d.%d.", tonumber(dd), tonumber(m))
end

local function fetchList(ctx, kind, today, en)
  local key = ctx.cfg.apiKey
  local lang = en and "en-US" or "de-DE"
  local region = ctx.cfg.region or "DE"
  local url = API .. kind .. "?api_key=" .. text.url_encode(key) .. "&language=" .. lang .. "&region=" .. region .. "&page=1"
  local r, err = http.request{ url = url, maxBytes = 65536, keep = { "title", "release_date", "vote_average", "poster_path", "genre_ids" }, headers = { Accept = "application/json" } }
  if not r then return nil, "TMDB: " .. tostring(err) end
  if r.status == 401 then return nil, en and "TMDB key invalid" or "TMDB-Schlüssel ungültig" end
  if r.status and r.status ~= 200 then return nil, "TMDB: Status " .. tostring(r.status) end
  local doc = json.decode(r.body or "")
  if type(doc) ~= "table" or type(doc.results) ~= "table" then return nil, "TMDB: keine Antwort" end
  local genres = en and GENRE_EN or GENRE_DE
  local rows = {}
  for _, m in ipairs(doc.results) do
    local d = m.release_date or ""
    local keep = true
    if kind == "upcoming" and d ~= "" and d < today then keep = false end
    if m.title and m.title ~= "" and keep then
      local g = ""
      if type(m.genre_ids) == "table" and m.genre_ids[1] then g = genres[m.genre_ids[1]] or "" end
      rows[#rows + 1] = { clean(m.title, 60), d, tonumber(m.vote_average) or 0, g, m.poster_path or "" }
    end
  end
  if kind == "upcoming" then table.sort(rows, function(a, b) return a[2] < b[2] end) end
  return rows
end

local function store(ctx, n, rows)
  local lines = {}
  for i = 1, math.min(#rows, 8) do
    local r = rows[i]
    lines[#lines + 1] = table.concat({ r[1], r[2], string.format("%.1f", r[3]), r[4] }, "\t")
  end
  file.write("k" .. n, table.concat(lines, "\n"))
end

function on_fetch(ctx)
  local key = ctx.cfg.apiKey
  if key == nil or key == "" then
    ctx.data.set("err", "nokey")
    return false
  end
  local today = time.today()
  if not today then return false end
  local en = (ctx.lang == "en")
  ctx.data.set("err", "")
  local first = true
  for n, kind in ipairs({ "now_playing", "upcoming" }) do
    if not first then time.sleep(300) end
    first = false
    local rows, err = fetchList(ctx, kind, today, en)
    if not rows then
      log("Kino: " .. tostring(err))
      ctx.data.set("err", clean(err, 120))
      return false
    end
    store(ctx, n, rows)
    ctx.data.set("n" .. n, math.min(#rows, 8))
    if ctx.cfg.posters ~= false and rows[1] and rows[1][5] ~= "" then
      time.sleep(300)
      local ok = http.image(IMG .. rows[1][5], "poster" .. n, 185, 278, { ram = true })
      ctx.data.set("p" .. n, ok and "1" or "0")
    else
      ctx.data.set("p" .. n, "0")
    end
  end
  ctx.data.set("day", today)
  return true
end

local function loadRows(ctx, n)
  local rows = {}
  local raw = file.read("k" .. n) or ""
  for ln in raw:gmatch("[^\n]+") do
    local t, d, v, g = ln:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t?(.*)$")
    if t then rows[#rows + 1] = { t, d, tonumber(v) or 0, g } end
  end
  if #rows == 0 and (ctx.preview == true or ctx.sample or ctx.data.get("demo") == "1") then rows = SAMPLE end
  return rows
end

local function rating(v, en)
  if not v or v <= 0 then return "" end
  return num(v, 1, en)
end

local function drawRow(x, y, w, h, r, en, upcoming)
  local sub = r[4]
  local right = upcoming and dateShort(r[2], en) or rating(r[3], en)
  if right == "" then right = dateShort(r[2], en) end
  local rw = draw.measure(right, "normal")
  draw.text(x + w, y + h // 2 + 6, right, "normal", color.ACCENT_TEXT, "right")
  local tw = w - rw - 20
  if sub ~= "" and h >= 52 then
    draw.text(x, y + h // 2 - 2, fit(r[1], tw, "normal"), "normal", color.BLACK, "left")
    draw.text(x, y + h // 2 + 20, fit(sub, tw, "small"), "small", color.BLACK, "left")
  else
    draw.text(x, y + h // 2 + 6, fit(r[1], tw, "normal"), "normal", color.BLACK, "left")
  end
end

function on_draw(ctx, page)
  local en = (ctx.lang == "en")
  setStyle(ctx.cfg.style)
  draw.clear(color.WHITE)
  local n = (page == 2) and 2 or 1
  local upcoming = n == 2
  if (ctx.cfg.apiKey == nil or ctx.cfg.apiKey == "") and not ctx.preview and ctx.data.get("demo") ~= "1" then
    notice("gear", en and "TMDB key missing" or "TMDB-Schlüssel fehlt", en and "Enter your free key in the app settings" or "Kostenlosen Schlüssel in den App-Einstellungen eintragen")
    return
  end
  local rows = loadRows(ctx, n)
  if #rows == 0 then
    local err = ctx.data.get("err") or ""
    if err ~= "" and err ~= "nokey" then notice("error", en and "Not loaded" or "Nicht geladen", err)
    else notice("loading", en and "Loading ..." or "Wird geladen ...") end
    return
  end
  local fancy = theme.s == "relief" or theme.s == "klar" or theme.s == "cards"
  local top, bottom = draw.top + 14, draw.height - 16
  local hasPoster = ctx.data.get("p" .. n) == "1" and draw.image_size("poster" .. n) ~= nil
  local first = rows[1]
  local px = 40

  -- Links: Poster und Hauptfilm
  local colW = hasPoster and 220 or 0
  if hasPoster then
    local iw, ih = draw.image_size("poster" .. n)
    if fancy then card(px, top, colW, bottom - top, color.ACCENT, theme.s == "relief" and 16 or 22) end
    local ix = px + (colW - iw) // 2
    local iy = top + 16
    if theme.s == "relief" then draw.rect(ix + 4, iy + 4, iw, ih, color.BLACK, true) end
    draw.image("poster" .. n, ix, iy)
    draw.rect(ix, iy, iw, ih, color.BLACK, false)
  end

  -- Rechts: Titelliste (der erste Eintrag ist der Hauptfilm mit dem Poster)
  local lx = px + (hasPoster and colW + 26 or 0)
  local lw = draw.width - 40 - lx
  local head = upcoming and (en and "Coming soon" or "Demnächst") or (en and "In cinemas" or "Im Kino")
  if fancy then
    card(lx, top, lw, bottom - top, color.ACCENT, theme.s == "relief" and 16 or 22)
    lx, lw = lx + 28, lw - 56
  else
    draw.rect(lx - 14, top, 5, bottom - top, color.ACCENT, true)
  end
  draw.text(lx, top + 38, head, "medium", color.BLACK, "left")
  -- TMDB-Logo (assets/tmdb.ibm, falls vorhanden), sonst der Schriftzug
  local lw0, lh0 = draw.image_size("tmdb")
  if lw0 then
    draw.image("tmdb", lx + lw - lw0, top + 24 - lh0 // 2)
  else
    draw.text(lx + lw, top + 36, "TMDB", "small", color.ACCENT_TEXT, "right")
  end
  local note = en and "Uses the TMDB API, not endorsed or certified by TMDB." or "Nutzt die TMDB-API, von TMDB nicht unterstützt oder zertifiziert."
  draw.text(lx, bottom - 10, fit(note, lw, "small"), "small", color.ACCENT_TEXT, "left")
  local ry = top + 58
  local shown, rowH = rowLayout(#rows, ry, bottom - 40, 48, 70)
  for i = 1, shown do
    local y = ry + (i - 1) * rowH
    if i > 1 then draw.line(lx, y, lx + lw, y, color.BLACK) end
    drawRow(lx, y, lw, rowH, rows[i], en, upcoming)
  end
end

function on_widget(ctx, box)
  setStyle(ctx.cfg.style)
  box = widgetFrame(box)
  local en = (ctx.lang == "en")
  local rows = loadRows(ctx, 1)
  if #rows == 0 then
    local nokey = ctx.cfg.apiKey == nil or ctx.cfg.apiKey == ""
    draw.text(box.x + 12, box.y + 22, nokey and (en and "TMDB key missing" or "TMDB-Schlüssel fehlt") or (en and "No data yet" or "Noch keine Daten"), "small", color.BLACK, "left")
    return
  end
  local n = math.min(#rows, math.max(1, (box.h - 4) // 28))
  local rh = box.h // n
  for i = 1, n do
    local r = rows[i]
    local y = box.y + (i - 1) * rh + rh // 2 + 6
    local rt = rating(r[3], en)
    local rw = rt ~= "" and draw.measure(rt, "small") + 10 or 0
    if rt ~= "" then draw.text(box.x + box.w - 6, y, rt, "small", color.ACCENT_TEXT, "right") end
    draw.text(box.x + 12, y, fit(r[1], box.w - rw - 28, "small"), "small", color.BLACK, "left")
  end
end
