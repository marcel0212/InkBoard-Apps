local CATS = { "general", "business", "sports", "tech" }
local PER_CAT = 14
local PER_CHUNK = 7
local MAX_CALLS = 6
local function trim(s)
return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
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
local function clean(s, n)
s = tostring(s or ""):gsub("%c", " ")
return cut(trim(s), n)
end
local function fit(s, w, font)
while #s > 1 and draw.measure(s, font) > w do
s = s:sub(1, #s - 1)
while #s > 1 and (s:byte(#s) & 0xC0) == 0x80 do s = s:sub(1, #s - 1) end
end
return s
end
local function num(x, digits, en)
local s = string.format("%." .. digits .. "f", x)
if not en then s = s:gsub("%.", ",") end
return s
end
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
local function dfc(y, m, d)
if m <= 2 then y = y - 1 end
local era = y // 400
local yoe = y - era * 400
local mp = (m + 9) % 12
local doy = (153 * mp + 2) // 5 + d - 1
local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
return era * 146097 + doe - 719468
end
local function cfd(z)
z = z + 719468
local era = z // 146097
local doe = z - era * 146097
local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
local y = yoe + era * 400
local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
local mp = (5 * doy + 2) // 153
local d = doy - (153 * mp + 2) // 5 + 1
local m = mp < 10 and mp + 3 or mp - 9
if m <= 2 then y = y + 1 end
return y, m, d
end
local MON3 = { jan = 1, feb = 2, mar = 3, apr = 4, may = 5, jun = 6, jul = 7, aug = 8, sep = 9, oct = 10, nov = 11, dec = 12 }
local ZONES = { gmt = 0, utc = 0, ut = 0, z = 0, est = -5, edt = -4, cst = -6, cdt = -5, mst = -7, mdt = -6, pst = -8, pdt = -7, cet = 1, cest = 2 }
local function zoneSeconds(z)
if z == nil or z == "" then return 0 end
local sign, hh, mm = z:match("^([+-])(%d%d):?(%d%d)$")
if sign then
local v = tonumber(hh) * 3600 + tonumber(mm) * 60
return sign == "-" and -v or v
end
local h = ZONES[z:lower()]
return h and h * 3600 or 0
end
local function parseRfc822(s)
if type(s) ~= "string" then return nil end
local d, mon, y, hh, mi, ss, zone = s:match("(%d%d?)%s+(%a%a%a)%a*%s+(%d%d%d?%d?)%s+(%d%d):(%d%d):?(%d*)%s*(%S*)")
if d == nil then return nil end
local m = MON3[mon:lower()]
if m == nil then return nil end
y = tonumber(y)
if y < 100 then y = y + (y < 70 and 2000 or 1900) end
return dfc(y, m, tonumber(d)) * 86400 + tonumber(hh) * 3600 + tonumber(mi) * 60 + (tonumber(ss) or 0) - zoneSeconds(zone)
end
local function parseIso(s)
if type(s) ~= "string" then return nil end
local y, m, d, hh, mi, ss, rest = s:match("(%d%d%d%d)%-(%d%d)%-(%d%d)[T ](%d%d):(%d%d):?(%d*)(.*)")
if y == nil then return nil end
local zone = rest:match("([+-]%d%d:?%d%d)") or (rest:find("Z", 1, true) and "Z") or ""
return dfc(tonumber(y), tonumber(m), tonumber(d)) * 86400 + tonumber(hh) * 3600 + tonumber(mi) * 60 + (tonumber(ss) or 0) - zoneSeconds(zone)
end
local function notice(icon, line1, line2)
local cx = draw.width // 2
draw.icon(icon, cx - 24, 170, 48, color.ACCENT)
draw.text(cx, 260, line1, "normal", color.BLACK, "center")
if line2 ~= nil then draw.text(cx, 290, line2, "small", color.BLACK, "center") end
end
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
local function card(x, y, w, h, c, r)
r = r or 10
draw.rect(x, y, w, h, color.WHITE, true, r)
draw.rect(x, y, w, h, color.BLACK, false, r)
draw.rect(x + 6, y + 6, 5, h - 12, c or color.ACCENT, true, 2)
end
local function columns(widths, rightEdge)
local total = 0
for _, w in ipairs(widths) do total = total + w end
local xs, x = {}, rightEdge - total
for i, w in ipairs(widths) do xs[i] = x; x = x + w end
return xs
end
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
local PRESETS = {
tagesschau = { "Tagesschau", "https://www.tagesschau.de/xml/rss2" },
zeit = { "ZEIT ONLINE", "https://newsfeed.zeit.de/index" },
tagesschau_wirtschaft = { "Tagesschau Wirtschaft", "https://www.tagesschau.de/wirtschaft/index~rss2.xml" },
kicker = { "Kicker", "https://newsfeed.kicker.de/news/aktuell" },
heise = { "Heise", "https://www.heise.de/rss/heise-atom.xml" },
golem = { "Golem", "https://rss.golem.de/rss.php?feed=RSS2.0" },
}
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
for ci = 1, #CATS do
if fresh[ci] then
local merged = {}
for _, it in ipairs(readCat(ctx, ci)) do
if fresh[ci][it.src] == nil then merged[#merged + 1] = it end
end
for _, list in pairs(fresh[ci]) do
for _, it in ipairs(list) do merged[#merged + 1] = it end
end
local wanted = {}
for _, f in ipairs(feeds) do if f.cat == ci then wanted[f.label] = true end end
local kept = {}
for _, it in ipairs(merged) do if wanted[it.src] then kept[#kept + 1] = it end end
writeCat(ctx, ci, kept)
end
end
local has = {}
for _, f in ipairs(feeds) do has[f.cat] = true end
local st = {}
for ci = 1, #CATS do
if not has[ci] then st[ci] = "-"
elseif failed[ci] and not fresh[ci] then st[ci] = "e:" .. failed[ci]
else st[ci] = "ok" end
end
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
