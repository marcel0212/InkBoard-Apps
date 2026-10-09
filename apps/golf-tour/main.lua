local TOURS = { pga = "pga", liv = "liv", dpworld = "eur" } -- Tour -> ESPN-Slug
local BASE = "https://site.api.espn.com/apis/site/v2/sports/golf/"
local ROWS_MAX = 15                  -- Podium (Platz 1-3) + Liste darunter (4-15)
local PRE_SEC, POST_SEC = 2 * 86400, 6 * 86400 -- Zeitfenster um den Turnierstart fuer den grossen Abruf
local MAX_BYTES = 65536
local MAX_COMPETITORS = 200          -- so viele Spieler hoechstens auswerten; die Liste ist NICHT nach Rang sortiert (Sortierung nach sortOrder)
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
local function unesc(s)
if not s:find("\\", 1, true) then return s end
s = s:gsub("\\u(%x%x%x%x)", function(h)
local cp = tonumber(h, 16)
if cp < 0x80 then return string.char(cp) end
if cp < 0x800 then return string.char(0xC0 | (cp >> 6), 0x80 | (cp & 0x3F)) end
return string.char(0xE0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F))
end)
s = s:gsub("\\(.)", { n = " ", t = " ", r = " ", b = "", f = "", ["\\"] = "\\", ['"'] = '"', ["/"] = "/" })
return s
end
local function skipTo(body, i)
local depth = 1
while true do
local j = body:find('["{}%[%]]', i)
if not j then return nil end
local c = body:byte(j)
if c == 34 then
local k = j + 1
while true do
local q = body:find('["\\]', k)
if not q then return nil end
if body:byte(q) == 34 then k = q + 1; break end
k = q + 2
end
i = k
elseif c == 123 or c == 91 then
depth = depth + 1
i = j + 1
else
depth = depth - 1
i = j + 1
if depth == 0 then return i end
end
end
end
local function scan(body, i, enter, scalar, leave)
local find, byte, sub = string.find, string.byte, string.sub
local ks, isArr, depth, key = {}, {}, 0, nil
while true do
local j = find(body, '["{}%[%]]', i)
if not j then return end
local c = byte(body, j)
if c == 34 then
local k, e = j + 1, nil
while true do
local q = find(body, '["\\]', k)
if not q then return end
if byte(body, q) == 34 then e = q; break end
k = q + 2
end
local s = sub(body, j + 1, e - 1)
local n = find(body, "%S", e + 1)
i = e + 1
if n and byte(body, n) == 58 then -- ":" -> s ist ein Schluessel
key = s
i = n + 1
local v = find(body, "%S", i)
if v then
local vc = byte(body, v)
if vc == 45 or (vc >= 48 and vc <= 57) then
local raw = body:match("^-?[%d.eE+-]+", v) or "0"
i = v + #raw
if scalar(depth, key, tonumber(raw), raw, ks) == "stop" then return end
elseif vc == 116 or vc == 102 then -- true / false
i = v + (vc == 116 and 4 or 5)
if scalar(depth, key, vc == 116, nil, ks) == "stop" then return end
elseif vc == 110 then -- null
i = v + 4
end
end
else
local kk = (depth > 0 and isArr[depth]) and "#" or key
if scalar(depth, kk, unesc(s), nil, ks) == "stop" then return end
end
elseif c == 123 or c == 91 then
depth = depth + 1
if depth == 1 then ks[1] = "" elseif isArr[depth - 1] then ks[depth] = "#" else ks[depth] = key end
isArr[depth] = (c == 91)
key = nil
i = j + 1
local r = enter(depth, ks[depth], ks)
if r == "stop" then return end
if r then
local nx = skipTo(body, i)
if not nx then return end
i = nx
depth = depth - 1
end
else
if leave and leave(depth, ks) == "stop" then return end
depth = depth - 1
key = nil
i = j + 1
end
end
end
local function parseScoreboard(body)
local ev, saw, n = {}, false, 0
scan(body, 1,
function(d, k)
if d == 1 then return false end
if d == 2 then
if k == "events" then saw = true; return false end
return true
end
if d == 3 then
n = n + 1
if n > 1 then return "stop" end
return false
end
if d == 4 then return not (k == "status" or k == "competitions") end
return d >= 8 or (d == 6 and k ~= "status")
end,
function(d, k, v, raw, ks)
if d == 3 then
if k == "id" then ev.id = raw or tostring(v)
elseif k == "name" and type(v) == "string" then ev.name = v
elseif k == "date" and type(v) == "string" then ev.date = v end
elseif d == 5 and ks[4] == "status" and ks[5] == "type" then
if k == "state" then ev.state = v elseif k == "completed" then ev.completed = v end
elseif d == 7 and ks[4] == "competitions" and ks[6] == "status" and ks[7] == "type" then
if k == "state" and ev.state2 == nil then ev.state2 = v elseif k == "completed" and ev.completed2 == nil then ev.completed2 = v end
end
end,
function(d)
if d == 3 then return "stop" end
end)
return ev, saw
end
local function parseLeaderboard(body)
local comps, cur, compDepth = {}, nil, nil
scan(body, 1,
function(d, k, ks)
if compDepth == nil then
if d == 1 then return false end
if k == "competitors" then compDepth = d + 1; return false end
return not (k == "events" or k == "competitions" or k == "#")
end
if d == compDepth then
cur = { so = 9999, pos = "-", player = "?", score = "-", state = "", detail = "", seq = #comps + 1 }
return false
end
if d < compDepth then return false end
local rel = d - compDepth
if rel == 1 then return not (k == "athlete" or k == "score" or k == "status") end
if rel == 2 then return not (ks[d - 1] == "status" and (k == "position" or k == "type")) end
return true
end,
function(d, k, v, raw, ks)
if compDepth == nil or cur == nil then return end
local rel = d - compDepth
if rel == 0 then
if k == "sortOrder" and type(v) == "number" then cur.so = v
elseif k == "score" and type(v) == "string" then cur.score = v end
elseif rel == 1 then
local p = ks[d]
if p == "athlete" and k == "displayName" then cur.player = v
elseif p == "score" and k == "displayValue" then cur.score = v end
elseif rel == 2 then
local p = ks[d]
if p == "position" and k == "displayName" then cur.pos = v
elseif p == "type" and k == "state" then cur.state = v
elseif p == "type" and k == "shortDetail" then cur.detail = v end
end
end,
function(d)
if compDepth == nil then return end
if d == compDepth and cur then
comps[#comps + 1] = cur
cur = nil
if #comps >= MAX_COMPETITORS then return "stop" end
elseif d == compDepth - 1 then
return "stop" -- Spielerliste zu Ende
end
end)
table.sort(comps, function(a, b)
if a.so ~= b.so then return a.so < b.so end
return a.seq < b.seq
end)
local rows = {}
for i = 1, math.min(#comps, ROWS_MAX) do
local c = comps[i]
rows[i] = {
pos = clean(c.pos, 4), player = clean(c.player, 25), score = clean(c.score, 5),
status = c.state == "post" and clean(c.detail, 4) or "",
}
end
return rows
end
local function tourOf(ctx)
local t = ctx.cfg.tour
if TOURS[t] then return t end
return "pga"
end
function on_fetch(ctx)
local tour = tourOf(ctx)
local body, err = http.get(BASE .. TOURS[tour] .. "/scoreboard", MAX_BYTES)
if body == nil then log("Golf Tour: Turnierkalender: " .. tostring(err)); return false end
local ev, saw = parseScoreboard(body)
body = nil
if not saw then log("Golf Tour: Antwort ohne Turnierliste"); return false end
local name, start, lv, rows = "", 0, 0, {}
if ev.id and ev.id:match("^%w+$") then
name = clean(ev.name or "", 48)
start = parseIso(ev.date) or 0
local state = ev.state or ev.state2
if state == "in" then lv = 1
elseif state == "post" and (ev.completed or ev.completed2) then lv = 2 end
local now = time.now()
if start > 0 and now ~= nil and now >= start - PRE_SEC and now <= start + POST_SEC then
time.sleep(150)
local lb, lerr = http.request{
url = BASE .. "leaderboard?event=" .. ev.id, maxBytes = MAX_BYTES,
keep = { "sortOrder", "displayName", "displayValue", "score", "state", "shortDetail" },
skip = { "linescores", "statistics", "holes", "courses", "links", "logos", "headshot", "flag", "odds", "leaders" },
}
if lb == nil then log("Golf Tour: Leaderboard: " .. tostring(lerr)); return false end
if lb.status ~= 200 then log("Golf Tour: Leaderboard: HTTP " .. tostring(lb.status)); return false end
rows = parseLeaderboard(lb.body)
lb = nil
end
end
local lines = {}
for i, r in ipairs(rows) do
lines[i] = r.pos .. "\t" .. r.player .. "\t" .. r.score .. "\t" .. r.status
end
while #lines > 0 and #table.concat(lines, "\n") > 1000 do lines[#lines] = nil end -- ctx.data: Text hoechstens 1024 Bytes
ctx.data.set("tr", tour)
ctx.data.set("en", name)
ctx.data.set("st", start)
ctx.data.set("lv", lv)
ctx.data.set("r", table.concat(lines, "\n"))
return true
end
local function model(ctx)
if ctx.data.get("tr") ~= tourOf(ctx) then return nil end
local m = {
name = ctx.data.get("en") or "", start = ctx.data.get("st") or 0, lv = ctx.data.get("lv") or 0, rows = {},
}
for line in (ctx.data.get("r") or ""):gmatch("[^\n]+") do
local pos, player, score, status = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t?([^\t]*)$")
if pos then m.rows[#m.rows + 1] = { pos = pos, player = player, score = score, status = status } end
end
return m
end
local function statusLabel(m, en)
if m.lv == 1 then return en and "In progress" or "Läuft" end
if m.lv == 2 then return en and "Final" or "Beendet" end
return ""
end
local function utcOffset()
local t = time.localtime()
local now = time.now()
if t == nil or now == nil then return 0 end
local localSecs = dfc(t.year, t.month, t.day) * 86400 + t.hour * 3600 + t.min * 60 + t.sec
local off = ((localSecs - now + 450) // 900) * 900
if off < -14 * 3600 or off > 14 * 3600 then return 0 end
return off
end
local WD_DE = { "Mo", "Di", "Mi", "Do", "Fr", "Sa", "So" }
local WD_EN = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
local function dateText(epoch, en)
local day = (epoch + utcOffset()) // 86400
local _, mo, d = cfd(day)
local wd = ((day + 3) % 7) + 1 -- 1970-01-01 war ein Donnerstag; 1 = Montag
return string.format("%s %02d.%02d.", (en and WD_EN or WD_DE)[wd], d, mo)
end
local function emptyState(ctx, m)
local en = ctx.lang == "en"
if m == nil then
notice("clock", en and "Loading ..." or "Wird geladen ...")
return true
end
if m.name == "" then
notice("flag", en and "No tournament right now." or "Aktuell kein Turnier.")
return true
end
if #m.rows == 0 then
notice("flag", m.name, m.start > 0 and ((en and "from " or "ab ") .. dateText(m.start, en)) or nil)
return true
end
return false
end
local function compactNotice(cx, cy, text)
draw.icon("flag", cx - 16, cy - 30, 32, color.ACCENT)
draw.text(cx, cy + 22, text, "small", color.BLACK, "center")
end
local function posBadge(cx, cy, r, pos, filled)
if filled then
draw.circle(cx, cy, r, color.ACCENT, true)
draw.text(cx, cy + 6, pos, "normal", color.ACCENT_INK, "center")
else
draw.circle(cx, cy, r, color.BLACK)
draw.text(cx, cy + 6, pos, "normal", color.BLACK, "center")
end
end
local function scoreText(row)
if row.status ~= "" then return row.score .. " (" .. row.status .. ")" end
return row.score
end
local function drawCards(ctx, m)
local en = ctx.lang == "en"
local W, cx = draw.width, draw.width // 2
local y = draw.top + 10
local bottom = draw.height - 14
local marginX = 20
local heroW = W - 2 * marginX
draw.text(cx, y + 14, fit(m.name, heroW, "normal"), "normal", color.BLACK, "center")
local st = statusLabel(m, en)
if st ~= "" then draw.text(cx, y + 30, st, "small", color.BLACK, "center") end
local gap, podiumTop, podiumH = 14, y + 42, 152
local count = math.min(#m.rows, 3)
local tileW = (heroW - 2 * gap) // 3
for i = 1, count do
local row = m.rows[i]
local tx = marginX + (i - 1) * (tileW + gap)
local mid = tx + tileW // 2
draw.rect(tx, podiumTop, tileW, podiumH, i == 1 and color.ACCENT or color.BLACK, false, 12)
posBadge(mid, podiumTop + 30, 20, row.pos, i == 1)
draw.text(mid, podiumTop + 70, fit(row.player, tileW - 20, "small"), "small", color.BLACK, "center")
draw.text(mid, podiumTop + 112, row.score, "large", color.BLACK, "center")
if row.status ~= "" then draw.text(mid, podiumTop + 136, row.status, "small", color.BLACK, "center") end
end
if count == 0 then compactNotice(cx, podiumTop + podiumH // 2, en and "No standings yet." or "Noch keine Platzierungen.") end
local listTop = podiumTop + podiumH + 26
if #m.rows > 3 and listTop < bottom - 20 then
draw.text(marginX, listTop, en and "FURTHER STANDINGS" or "WEITERE PLATZIERUNGEN", "small", color.BLACK, "left")
listTop = listTop + 10
local rowsShown = #m.rows - 3
local rowH = (bottom - listTop) // rowsShown
if rowH > 26 then rowH = 26 end
if rowH < 16 then rowH = 16 end
for i = 4, #m.rows do
local idx = i - 4
local rowTop = listTop + idx * rowH
if rowTop + rowH > bottom then break end
local f = rowH < 20 and "small" or "normal" -- bei knappen Zeilen kleine Schrift, damit nichts in die Trennlinie ragt
local base = rowTop + rowH // 2 + (rowH < 20 and 4 or 6)
local row = m.rows[i]
draw.text(marginX + 46, base, row.pos, f, color.BLACK, "right")
local sc = scoreText(row)
local scoreX = W - marginX - draw.measure(sc, f)
local nameX = marginX + 60
draw.text(nameX, base, fit(row.player, scoreX - nameX - 10, f), f, color.BLACK, "left")
draw.text(scoreX, base, sc, f, color.BLACK, "left")
if i < #m.rows and idx < rowsShown - 1 then draw.line(marginX, rowTop + rowH - 1, marginX + heroW, rowTop + rowH - 1, color.BLACK) end
end
end
end
local function drawFlat(ctx, m)
local en = ctx.lang == "en"
local W, cx = draw.width, draw.width // 2
local y = draw.top + 12
local bottom = draw.height - 12
local marginX = 20
draw.text(cx, y + 12, fit(m.name, W - 2 * marginX, "normal"), "normal", color.BLACK, "center")
local st = statusLabel(m, en)
if st ~= "" then draw.text(cx, y + 27, st, "small", color.BLACK, "center") end
local listTop = y + 40
local availH = bottom - listTop
if #m.rows < 1 or availH < 18 then
compactNotice(cx, listTop + availH // 2, en and "No standings yet." or "Noch keine Platzierungen.")
return
end
local rowH = availH // #m.rows
if rowH > 30 then rowH = 30 end
if rowH < 18 then rowH = 18 end
local shown = math.min(#m.rows, availH // rowH)
for i = 1, shown do
local row = m.rows[i]
local rowTop = listTop + (i - 1) * rowH
local base = rowTop + rowH // 2 + 6
if i == 1 then draw.rect(marginX, rowTop + 3, 5, rowH - 6, color.ACCENT, true, 2)
elseif i <= 3 then draw.rect(marginX, rowTop + 4, 5, rowH - 8, color.BLACK, true, 2) end
draw.text(marginX + 46, base, row.pos, "normal", color.BLACK, "right")
local sc = scoreText(row)
local scoreX = W - marginX - draw.measure(sc, "normal")
local nameX = marginX + 60
draw.text(nameX, base, fit(row.player, scoreX - nameX - 10, "normal"), "normal", color.BLACK, "left")
draw.text(scoreX, base, sc, "normal", color.BLACK, "left")
end
end
local function drawCompact(ctx, m)
local en = ctx.lang == "en"
local W, cx = draw.width, draw.width // 2
local y = draw.top + 10
local bottom = draw.height - 10
local marginX = 16
local name = fit(m.name, W - 2 * marginX, "small")
draw.text(cx, y + 10, name, "small", color.BLACK, "center")
local st = statusLabel(m, en)
if st ~= "" then
local x = cx + draw.measure(name, "small") // 2 + 10
if x + draw.measure(st, "small") < W - marginX then draw.text(x, y + 10, st, "small", color.BLACK, "left") end
end
local listTop = y + 18
local availH = bottom - listTop
if #m.rows < 1 or availH < 15 then
compactNotice(cx, listTop + availH // 2, en and "No standings yet." or "Noch keine Platzierungen.")
return
end
local shown = math.min(#m.rows, math.max(1, availH // 15))
local rowH = availH // shown
if rowH > 20 then rowH = 20 end
for i = 1, shown do
local row = m.rows[i]
local rowTop = listTop + (i - 1) * rowH
local base = rowTop + rowH // 2 + 5
draw.text(marginX + 34, base, row.pos, "small", color.BLACK, "right")
local sc = scoreText(row)
local scoreX = W - marginX - draw.measure(sc, "small")
local nameX = marginX + 42
draw.text(nameX, base, fit(row.player, scoreX - nameX - 8, "small"), "small", color.BLACK, "left")
draw.text(scoreX, base, sc, "small", color.BLACK, "left")
if i < shown then draw.line(marginX, rowTop + rowH - 1, W - marginX, rowTop + rowH - 1, color.BLACK) end
end
end
function on_draw(ctx, page)
draw.clear(color.WHITE)
local m = model(ctx)
if emptyState(ctx, m) then return end
local style = ctx.cfg.style
if style == "flat" then drawFlat(ctx, m)
elseif style == "compact" then drawCompact(ctx, m)
else drawCards(ctx, m) end
end
function on_widget(ctx, box)
local en = ctx.lang == "en"
local m = model(ctx)
if m == nil or #m.rows == 0 then
local text = m == nil and (en and "No data yet" or "Noch keine Daten") or (en and "No standings yet" or "Noch keine Platzierungen")
draw.text(box.x + 12, box.y + 16, text, "small", color.BLACK, "left")
return
end
local font = (box.font or 0) > 0 and "normal" or "small"
local y = box.y + 17
local maxY = box.y + box.h - 4
local shown = math.min(#m.rows, 3)
local posW = 0
for i = 1, shown do posW = math.max(posW, draw.measure(m.rows[i].pos, font)) end
for i = 1, shown do
if y > maxY then break end
local row = m.rows[i]
draw.text(box.x + 12, y, row.pos, font, color.BLACK, "left")
local scoreX = box.x + box.w - 12 - draw.measure(row.score, font)
local nameX = box.x + 12 + posW + 12
draw.text(nameX, y, fit(row.player, scoreX - nameX - 8, font), font, color.BLACK, "left")
draw.text(scoreX, y, row.score, font, color.BLACK, "left")
y = y + 26
end
end
