local MAX_STATIONS = 10
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
local function en_(ctx) return ctx.lang == "en" end
local BRANDS = {
{ "ARAL", color.BLUE, false, "Aral Tankstelle" },
{ "SHELL", color.YELLOW, color.RED, "Shell plc" },
{ "ESSO", color.RED, color.BLUE, "Esso Marke" },
{ "TOTALENERGIES", color.RED, false, "TotalEnergies" },
{ "TOTAL", color.RED, false, "TotalEnergies" },
{ "JET", color.YELLOW, color.RED, "Jet Tankstellen" },
{ "STAR", color.BLUE, color.YELLOW, "Star Tankstelle Orlen" },
{ "AVIA", color.BLUE, color.RED, "AVIA International" },
{ "HEM", color.BLUE, color.RED, "HEM Tankstelle" },
{ "AGIP", color.YELLOW, color.BLACK, "Agip" },
{ "ENI", color.YELLOW, color.BLACK, "Eni" },
{ "OMV", color.BLUE, false, "OMV" },
{ "AGROLA", color.GREEN, false, "Agrola" },
}
local function brandEntry(brand)
if brand == nil or brand == "" then return nil end
local up = brand:upper()
for _, b in ipairs(BRANDS) do
if up:find(b[1], 1, true) then return b end
end
return nil
end
local function brandColor(brand)
local e = brandEntry(brand)
if e then return e[2] end
if brand == nil or brand == "" then return color.BLACK end
local h = 5381
for i = 1, #brand do h = ((h << 5) + h + brand:byte(i)) & 0xFFFFFFFF end
local palette = { color.BLUE, color.RED, color.GREEN, color.BLACK }
return palette[h % 4 + 1]
end
local function brandInitials(brand)
if brand == nil or brand == "" then return "?" end
return brand:sub(1, 2):upper()
end
local function logoKey(brand)
local e = brandEntry(brand)
local k = e and e[1]:lower() or brand:lower():gsub("[^a-z0-9]", "")
if k == "" then return nil end
if k == "totalenergies" then k = "total" end
return "logo_" .. k:sub(1, 20)
end
local function logoQuery(brand)
local e = brandEntry(brand)
if e then return e[4] end
return brand .. " Tankstelle"
end
local LOGO_W, LOGO_H = 26, 18 -- Platz im grossen Badge (28 x 20 mit 1 px Rand)
local function fetchLogos(ctx, stations, calls)
if ctx.cfg.logos == false then return end
local state = {}
local raw = ctx.data.get("lg")
if type(raw) == "string" then
for item in (raw .. ","):gmatch("([^,]*),") do
local k, v, d = item:match("^([a-z0-9_]+):(%d):?(%d*)$")
if k then state[k] = { v, tonumber(d) or 0 } end
end
end
local today = time.now() // 86400
local done, changed = 0, false
for _, st in ipairs(stations) do
if calls + done * 2 + 2 > 6 or done >= 2 then break end
local key = st.brand ~= "" and logoKey(st.brand) or nil
local cur = key and state[key]
if key and (cur == nil or (cur[1] == "0" and today - cur[2] >= 7)) then
done = done + 1
local url = "https://de.wikipedia.org/w/api.php?action=query&generator=search&gsrlimit=1&prop=pageimages"
.. "&piprop=thumbnail&pithumbsize=96&format=json&gsrsearch=" .. text.url_encode(logoQuery(st.brand))
local body = http.get(url)
if body == nil then
log("Tankpreise: Wikipedia nicht erreichbar")
else
local src = nil
local doc = json.decode(body)
if type(doc) == "table" and type(doc.query) == "table" and type(doc.query.pages) == "table" then
for _, page in pairs(doc.query.pages) do
if type(page) == "table" and type(page.thumbnail) == "table" and type(page.thumbnail.source) == "string" then
src = page.thumbnail.source
break
end
end
end
if src ~= nil and src:sub(1, 8) == "https://" then
local imgOk, imgWhy = http.image(src, key, LOGO_W, LOGO_H)
if imgOk == true then
state[key] = { "1", 0 }
changed = true
else
log("Tankpreise: Logo fuer " .. st.brand .. " nicht ladbar: " .. tostring(imgWhy)) -- Netz-/Bildfehler: nichts merken, naechster Lauf versucht es erneut
end
else
log("Tankpreise: kein Logo fuer " .. st.brand)
state[key] = { "0", today } -- Seite gefunden, aber ohne Seitenbild: erst nach 7 Tagen erneut
changed = true
end
end
end
end
if changed then
local out = {}
for k, v in pairs(state) do
out[#out + 1] = v[1] == "1" and (k .. ":1") or (k .. ":0:" .. v[2])
end
table.sort(out)
ctx.data.set("lg", table.concat(out, ","))
end
end
local TYPE_LABEL = { e5 = "E5", e10 = "E10", diesel = "Diesel" }
local TYPE_COLOR = { e5 = color.GREEN, e10 = color.BLUE, diesel = color.BLACK }
local TYPES = { "e5", "e10", "diesel" }
local function typeOf(ctx)
local t = ctx.cfg.primary
if TYPE_LABEL[t] == nil then t = "e5" end
return t
end
local function price(v)
if type(v) == "number" then return v end
return -1
end
local function shortAddress(street, house)
local a = street or ""
if a ~= "" and house ~= nil and house ~= "" then a = a .. " " .. house end
return a
end
function on_fetch(ctx)
local key = ctx.cfg.apiKey
if type(key) ~= "string" or key == "" then
ctx.data.set("st", "e:key")
return
end
local loc = weather.location()
if loc == nil then
ctx.data.set("st", "e:loc")
return
end
local radius = tonumber(ctx.cfg.radius) or 5
if radius < 1 then radius = 1 elseif radius > 25 then radius = 25 end
local url = string.format(
"https://creativecommons.tankerkoenig.de/json/list.php?lat=%.6f&lng=%.6f&rad=%d&sort=dist&type=all&apikey=%s",
loc.lat, loc.lon, radius, text.url_encode(key))
local body, err = http.get(url)
if body == nil then
log("Tankpreise: " .. tostring(err))
return false
end
local doc = decodeCut(body, 2)
if doc == nil then
log("Tankpreise: Antwort nicht lesbar")
return false
end
if doc.ok ~= true then
local msg = tostring(doc.message or "")
log("Tankpreise: API meldet Fehler: " .. msg)
ctx.data.set("st", "e:api")
return
end
local list = doc.stations
if type(list) ~= "table" then return false end
local maxN = tonumber(ctx.cfg.maxStations) or 5
if maxN < 1 then maxN = 1 elseif maxN > MAX_STATIONS then maxN = MAX_STATIONS end
local lines, size, brands = {}, 0, {}
for _, s in ipairs(list) do
if #lines >= maxN then break end
local place = clean(s.place or "", 18)
local zip = tonumber(s.postCode)
local city = zip and zip > 0 and string.format("%05d %s", zip, place) or place
local line = table.concat({
clean(s.name or "?", 30),
clean(s.brand or "", 16),
string.format("%.1f", tonumber(s.dist) or 0),
s.isOpen == true and "1" or "0",
string.format("%.3f", price(s.e5)),
string.format("%.3f", price(s.e10)),
string.format("%.3f", price(s.diesel)),
clean(shortAddress(s.street, s.houseNumber), 24),
}, "\t")
if size + #line + 1 > 1000 then break end
lines[#lines + 1] = line
brands[#brands + 1] = { brand = clean(s.brand or "", 16) }
size = size + #line + 1
end
ctx.data.set("s", table.concat(lines, "\n"))
ctx.data.set("st", "ok")
fetchLogos(ctx, brands, 1)
end
local function loadStations(ctx)
local out = {}
if ctx.sample then -- Beispieldaten fuer die Widget-Vorschau im Dashboard-Editor (CHANGELOG 559)
return {
{ name = "Aral Hauptstr.", brand = "Aral", dist = 0.8, open = true, e5 = 1.789, e10 = 1.729, diesel = 1.659, addr = "Hauptstr. 12" },
{ name = "Shell Ringstr.", brand = "Shell", dist = 1.4, open = true, e5 = 1.799, e10 = 1.739, diesel = 1.669, addr = "Ringstr. 3" },
{ name = "JET Industrieweg", brand = "JET", dist = 2.1, open = true, e5 = 1.769, e10 = 1.709, diesel = 1.639, addr = "Industrieweg 8" },
}
end
local raw = ctx.data.get("s")
if type(raw) ~= "string" or raw == "" then return out end
local maxN = tonumber(ctx.cfg.maxStations) or 5
for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
local f = {}
for part in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = part end
if #f >= 7 then
out[#out + 1] = {
name = f[1], brand = f[2], dist = tonumber(f[3]) or 0, open = f[4] == "1",
e5 = tonumber(f[5]) or -1, e10 = tonumber(f[6]) or -1, diesel = tonumber(f[7]) or -1,
addr = f[8] or "",
}
end
if #out >= maxN then break end
end
return out
end
local function priceText(p)
if p >= 0 then return (string.format("%.3f", p):gsub("%.", ",")) .. " EUR" end
return "-"
end
local function isOn(ctx, key) return ctx.cfg[key] ~= false end
local function secondaries(ctx, primary)
local out = {}
local flags = { e5 = isOn(ctx, "showE5"), e10 = isOn(ctx, "showE10"), diesel = isOn(ctx, "showDiesel") }
for _, t in ipairs(TYPES) do
if t ~= primary and flags[t] then out[#out + 1] = t end
end
return out
end
local function swatch(x, y, t, size)
draw.rect(x, y - size, size, size, TYPE_COLOR[t], true)
end
local function typeLabel(x, y, t)
swatch(x, y, t, 8)
draw.text(x + 12, y, TYPE_LABEL[t], "small", color.BLACK, "left")
return 12 + draw.measure(TYPE_LABEL[t], "small")
end
local function segmentWidth(t, p)
return 12 + draw.measure(TYPE_LABEL[t], "small") + 4 + draw.measure(priceText(p), "small")
end
local function segment(x, y, t, p)
local w = typeLabel(x, y, t)
draw.text(x + w + 4, y, priceText(p), "small", color.BLACK, "left")
return w + 4 + draw.measure(priceText(p), "small")
end
local function badge(x, y, brand, big, useLogo)
local w, h = 18, 13
if big then w, h = 28, 20 end
local key = useLogo and brand ~= "" and logoKey(brand) or nil
local iw, ih
if key then iw, ih = draw.image_size(key) end
if iw then
draw.rect(x, y, w, h, color.WHITE, true, big and 5 or 3)
draw.rect(x, y, w, h, color.BLACK, false, big and 5 or 3)
local bw, bh = w - 4, h - 4
local sw, sh = iw, ih
if sw > bw or sh > bh then
local f = math.min(bw / sw, bh / sh)
sw, sh = math.max(1, math.floor(sw * f)), math.max(1, math.floor(sh * f))
end
draw.image(key, x + (w - sw) // 2, y + (h - sh) // 2, sw, sh)
return
end
local e = brandEntry(brand)
draw.rect(x, y, w, h, brandColor(brand), true, big and 5 or 3)
if e and e[3] then draw.rect(x, y, w, big and 5 or 3, e[3], true) end
draw.text(x + w // 2, y + h - (big and 6 or 3), brandInitials(brand), "small", color.WHITE, "center")
end
local function emptyState(ctx, stations)
local en = en_(ctx)
local st = ctx.data.get("st")
if st == "e:key" or (st == nil and (ctx.cfg.apiKey == nil or ctx.cfg.apiKey == "")) then
notice("gear", en and "No Tankerkoenig API key set." or "Kein Tankerkönig-API-Key hinterlegt.",
en and "Store -> Fuel prices -> Settings" or "Store -> Tankpreise -> Einstellungen")
return true
end
if st == "e:loc" then
notice("gear", en and "Location not set." or "Standort nicht eingerichtet.",
en and "Studio -> Settings -> Weather location" or "Studio -> Einstellungen -> Standort für Wetterdaten")
return true
end
if st == "e:api" then
notice("warning", en and "Tankerkoenig reports an error." or "Tankerkönig meldet einen Fehler.",
en and "Check the API key in the Store" or "API-Key im Store prüfen")
return true
end
if #stations > 0 then return false end
if st == nil then
notice("clock", en and "Loading ..." or "Wird geladen ...")
return true
end
notice("search", en and "No fuel stations found nearby." or "Keine Tankstellen im Umkreis gefunden.",
en and "Widen the radius in the Store" or "Umkreis im Store vergrößern")
return true
end
local function drawCards(ctx, st)
local primary = typeOf(ctx)
local sec = secondaries(ctx, primary)
local shown = #st
local top = draw.top + 6
local at, tileW, tileH = gridLayout(shown, 2, top, draw.height - 16, 20, 14, 130)
for i = 1, shown do
local s = st[i]
local tx, ty = at(i)
card(tx, ty, tileW, tileH, s.open and color.ACCENT or color.BLACK)
badge(tx + 14, ty + 8, s.brand, true, ctx.cfg.logos ~= false)
local dist = string.format("%.1f km", s.dist)
local distW = draw.measure(dist, "small")
local distX = tx + tileW - 16 - distW
local nameX = tx + 14 + 28 + 6
draw.text(nameX, ty + 24, fit(s.name, distX - 8 - nameX, "normal"), "normal", color.BLACK, "left")
draw.text(distX, ty + 22, dist, "small", color.BLACK, "left")
if tileH > 100 and s.addr ~= "" then
draw.text(tx + 18, ty + 40, fit(s.addr, tileW - 36, "small"), "small", color.BLACK, "left")
end
local lift = tileH > 90 and 42 or 18
draw.text(tx + 18, ty + tileH - lift, priceText(s[primary]), "large", color.BLACK, "left")
typeLabel(tx + 18, ty + tileH - (tileH > 90 and 24 or 4), primary)
if tileH > 90 then
local sx = tx + 18
for _, t in ipairs(sec) do
sx = sx + segment(sx, ty + tileH - 8, t, s[t]) + 12
end
end
end
end
local function drawFlat(ctx, st, en)
local primary = typeOf(ctx)
local sec = secondaries(ctx, primary)
local W = draw.width
local y = draw.top + 10
local shown, rowH, truncated = rowLayout(#st, y, draw.height - 16, 54, 64, 16)
for i = 1, shown do
local s = st[i]
local rowY = y + (i - 1) * rowH
badge(24, rowY + 4, s.brand, true, ctx.cfg.logos ~= false)
local textX = 24 + 28 + 8
draw.text(textX, rowY + 22, s.name, "normal", color.BLACK, "left")
draw.text(textX, rowY + 40, (s.brand ~= "" and (s.brand .. " · ") or "") .. string.format("%.1f km", s.dist), "small", color.BLACK, "left")
if rowH >= 60 and s.addr ~= "" then
draw.text(textX, rowY + 56, s.addr, "small", color.BLACK, "left")
end
local pt = priceText(s[primary])
local pw = draw.measure(pt, "large")
local px = W - 26 - pw
swatch(px - 6 - 12, rowY + 26, primary, 12)
draw.text(px, rowY + 26, pt, "large", color.BLACK, "left")
if #sec > 0 then
local total = 0
for k, t in ipairs(sec) do
if k > 1 then total = total + 14 end
total = total + segmentWidth(t, s[t])
end
local sx = W - 26 - total
for _, t in ipairs(sec) do sx = sx + segment(sx, rowY + 42, t, s[t]) + 14 end
end
if i < shown then draw.line(24, rowY + rowH - 6, W - 24, rowY + rowH - 6, color.BLACK) end
end
if truncated then
local hint = string.format(en and "+%d more stations ('Nano' style)" or "+%d weitere Tankstellen (Stil 'Nano')", #st - shown)
draw.text(W // 2, y + shown * rowH + 12, hint, "small", color.BLACK, "center")
end
end
local function drawCompact(ctx, st)
local primary = typeOf(ctx)
local W = draw.width
local y = draw.top + 8
local shown = #st
local rowH = (draw.height - 12 - y) // math.max(shown, 1)
if rowH > 34 then rowH = 34 end
local cols = { primary }
for _, t in ipairs(secondaries(ctx, primary)) do cols[#cols + 1] = t end
local widths = {}
for c, t in ipairs(cols) do
local maxW = 0
for i = 1, shown do maxW = math.max(maxW, segmentWidth(t, st[i][t])) end
widths[c] = maxW + 18
end
local xs = columns(widths, W - 26)
local distColX = xs[1]
for i = 1, shown do
local s = st[i]
local rowY = y + (i - 1) * rowH
badge(24, rowY + (rowH - 13) // 2, s.brand, false, ctx.cfg.logos ~= false)
local base = rowY + rowH // 2 + 4
local dist = string.format("%.1f km", s.dist)
local distW = draw.measure(dist, "small")
local distX = distColX - 10 - distW
local nameX = 24 + 18 + 5
draw.text(nameX, base, fit(s.name, distX - 8 - nameX, "small"), "small", color.BLACK, "left")
draw.text(distX, base, dist, "small", color.BLACK, "left")
for c, t in ipairs(cols) do
local w = segmentWidth(t, s[t])
segment(xs[c] + widths[c] - 10 - w, base, t, s[t])
end
if i < shown then draw.line(24, rowY + rowH - 2, W - 24, rowY + rowH - 2, color.BLACK) end
end
end
function on_draw(ctx, page)
draw.clear(color.WHITE)
local st = loadStations(ctx)
if emptyState(ctx, st) then return end
local style = ctx.cfg.style
if style == "flat" then drawFlat(ctx, st, en_(ctx))
elseif style == "compact" then drawCompact(ctx, st)
else drawCards(ctx, st) end
end
local function pump(x, y, w, h, c)
draw.rect(x, y, w, h, c, true, 4)
draw.rect(x + w // 2 - 5, y + 3, 10, 6, color.WHITE, true, 1)
draw.rect(x + w // 2 - 2, y + h - 6, 4, 3, color.WHITE, true)
end
function on_widget(ctx, box)
local st = loadStations(ctx)
local compact = ctx.cfg.wCompact == true
local font = (box.font or 0) < 0 and "small" or "normal"
if compact then font = "small" end
if #st == 0 then
local en = en_(ctx)
local msg = ctx.data.get("st") == nil and (en and "No data yet" or "Noch keine Daten") or (en and "No stations" or "Keine Tankstellen")
draw.text(box.x + 12, box.y + 16, msg, "small", color.BLACK, "left")
return
end
local grades = {}
local mainT = typeOf(ctx)
local function avail(t, flag) return t == mainT or isOn(ctx, flag) end
if ctx.cfg.wE5 == true and avail("e5", "showE5") then grades[#grades + 1] = { "e5", "E5" } end
if ctx.cfg.wE10 ~= false and avail("e10", "showE10") then grades[#grades + 1] = { "e10", "E10" } end
if ctx.cfg.wDiesel == true and avail("diesel", "showDiesel") then grades[#grades + 1] = { "diesel", "D" } end
if #grades == 0 then
local g = ({ e5 = "E5", e10 = "E10", diesel = "D" })[mainT] or "E10"
grades[1] = { mainT, g }
end
local showDist = ctx.cfg.wDist ~= false
local tileH = compact and 30 or 44
local badgeW = compact and 28 or 36
local cols = box.w >= 320 and 2 or 1
local tileW = (box.w - 16) // cols
local maxY = box.y + box.h - 4
local topY = box.y - 2
local maxTiles = ((maxY - topY) // tileH) * cols
for i = 1, math.min(#st, maxTiles) do
local s = st[i]
local col, row = (i - 1) % cols, (i - 1) // cols
local tx = box.x + 10 + col * tileW
local ty = topY + row * tileH + 4
pump(tx, ty, badgeW, 18, color.ACCENT)
local parts = {}
for _, g in ipairs(grades) do
parts[#parts + 1] = g[2] .. " " .. (s[g[1]] >= 0 and string.format("%.3f", s[g[1]]) or "-")
end
local line = table.concat(parts, " · ")
draw.text(tx + badgeW + 10, ty + 14, fit(line, tileW - badgeW - 16, font), font, color.BLACK, "left")
if not compact then
local sub = s.brand ~= "" and s.brand or s.name
if showDist and s.dist > 0 then sub = sub .. string.format(" · %.1f km", s.dist) end
draw.text(tx + 46, ty + 31, fit(sub, tileW - 50, "small"), "small", color.BLACK, "left")
end
end
end
