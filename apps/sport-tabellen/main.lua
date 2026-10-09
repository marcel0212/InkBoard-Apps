local EN = false
local function T(de, en) if EN then return en end return de end
local BASE = "https://sportal.de/"
local MAX_BYTES = 65536
local DUE_SEC = 25 * 60           -- ab diesem Alter eines Stands wird die Sportart neu geladen
local RETRY_SEC = 5 * 60          -- nach einem Fehler nach etwa so langer Zeit erneut
local LAST_MAX, NEXT_MAX, TABLE_MAX = 5, 3, 24
local NAME_LEN = 25               -- Bytes (UTF-8-sicher gekuerzt), wie SPORT_NAME_LEN der eingebauten App
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
local CODE = { "eh", "hb", "bb", "af" }
local TEAMKEY = { "teamEh", "teamHb", "teamBb", "teamAf" }
local KIND_ID = { eishockey = 1, handball = 2, basketball = 3, americanfootball = 4 }
local function kindLabel(k)
if k == 1 then return T("Eishockey", "Ice hockey") end
if k == 2 then return "Handball" end
if k == 3 then return "Basketball" end
return "American Football"
end
local function leaguePath(cfg, k)
if k == 1 then return "eishockey/del" end
if k == 2 then return cfg.leagueHb == "champions-league" and "handball/champions-league" or "handball/bundesliga" end
if k == 3 then return cfg.leagueBb == "euroleague" and "basketball/euroleague" or "basketball/bundesliga" end
return "us-sport/nfl"
end
local LEAGUE_NAME = {
["eishockey/del"] = "DEL", ["handball/bundesliga"] = "Bundesliga", ["handball/champions-league"] = "Champions League",
["basketball/bundesliga"] = "BBL", ["basketball/euroleague"] = "EuroLeague", ["us-sport/nfl"] = "NFL",
}
local function liveWindow(k)
if k == 2 then return 7200 end
if k == 3 then return 8100 end
if k == 1 then return 9900 end
return 12600
end
local function teamOf(cfg, k) return clean(cfg[TEAMKEY[k]] or "", 40) end
local function sigOf(cfg, k) return teamOf(cfg, k) .. "|" .. leaguePath(cfg, k) end
local ENT = {
nbsp = " ", amp = "&", gt = ">", lt = "<", quot = '"', apos = "'", auml = "ä", ouml = "ö", uuml = "ü", Auml = "Ä",
Ouml = "Ö", Uuml = "Ü", szlig = "ß", eacute = "é", egrave = "è", ndash = "-", mdash = "-",
}
local function u8(cp)
if cp == 160 then return " " end
if cp < 0x80 then return string.char(cp) end
if cp < 0x800 then return string.char(0xC0 | (cp >> 6), 0x80 | (cp & 0x3F)) end
if cp < 0x10000 then return string.char(0xE0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F)) end
return "?"
end
local function plain(s)
if not s then return "" end
s = s:gsub("<[^>]*>", " ")
if s:find("&", 1, true) then
s = s:gsub("&#[xX](%x+);", function(h) return u8(tonumber(h, 16)) end)
s = s:gsub("&#(%d+);", function(d) return u8(tonumber(d)) end)
s = s:gsub("&(%a+);", function(n) return ENT[n] or "" end)
end
s = s:gsub("%s+", " ")
return (s:gsub("^ ", ""):gsub(" $", ""))
end
local function nameCut(s)
if #s > NAME_LEN then
local n = NAME_LEN
while n > 0 and (s:byte(n + 1) & 0xC0) == 0x80 do n = n - 1 end
s = s:sub(1, n)
end
return (s:gsub(" +$", ""))
end
local function loose(s)
s = s:gsub("\xC3[\xA4\x84]", "a"):gsub("\xC3[\xB6\x96]", "o"):gsub("\xC3[\xBC\x9C]", "u")
s = s:gsub("\xC3\x9F", "ss"):gsub("\xC3[\xA9\xA8]", "e")
return (s:lower():gsub("[^a-z0-9]", ""))
end
local function sameLoose(la, oa, lb, ob)
local na, nb = #la, #lb
if na < 3 or nb < 3 then return false end
if na == nb then return la == lb end
local ls, ll, os, ol = la, lb, oa, ob
if na > nb then ls, ll, os, ol = lb, la, ob, oa end
local ns, nl = #ls, #ll
if ns >= 4 and ll:sub(nl - ns + 1) == ls then
local lo, lol = #os, #ol
if lol > lo and ol:sub(lol - lo, lol - lo) == " " and ol:sub(lol - lo + 1):lower() == os:lower() then return true end
end
if ns >= 6 and ll:sub(1, ns) == ls then return true end
return false
end
local function findTeam(rows, name)
for i, r in ipairs(rows) do if r.name == name then return i end end
local ln, hit = loose(name), nil
for i, r in ipairs(rows) do
if sameLoose(loose(r.name), r.name, ln, name) then
if hit then return nil end
hit = i
end
end
return hit
end
local function deriveTla(name)
local a = {}
local i, n = 1, #name
while i <= n do
local c = name:byte(i)
if c < 0x80 then a[#a + 1] = string.char(c)
elseif c == 0xC3 and i < n then
local d = name:byte(i + 1)
i = i + 1
if d == 0x84 or d == 0xA4 then a[#a + 1] = "A"
elseif d == 0x96 or d == 0xB6 then a[#a + 1] = "O"
elseif d == 0x9C or d == 0xBC then a[#a + 1] = "U"
else a[#a + 1] = "X" end
elseif c >= 0xC0 then a[#a + 1] = "X" end
i = i + 1
end
local out, start = "", true
for _, ch in ipairs(a) do
if ch == " " or ch == "." or ch == "-" then start = true
elseif start then
out = out .. ch:upper()
start = false
if #out >= 3 then break end
end
end
if out == "" then out = "?" end
return out
end
local function nameHash(name)
local h = 5381
for i = 1, #name do h = (h * 31 + name:byte(i)) % 8388593 end
return h
end
local function assignTlas(rows)
local order, hash = {}, {}
for i, r in ipairs(rows) do order[i] = i; hash[i] = nameHash(loose(r.name)); r.tla = "" end
table.sort(order, function(a, b)
if hash[a] ~= hash[b] then return hash[a] < hash[b] end
return a < b
end)
for oi, idx in ipairs(order) do
local tla = deriveTla(rows[idx].name)
for attempt = 2, 99 do
local clash = false
for j = 1, oi - 1 do
if rows[order[j]].tla == tla then clash = true; break end
end
if not clash then break end
local base = tla:sub(1, 2)
tla = base .. tostring(attempt % 10)
if attempt >= 10 then tla = base:sub(1, 1) .. tostring(attempt) end
end
rows[idx].tla = tla:sub(1, 3)
end
end
local function lastSunday(y, m)
local z = dfc(y, m, 31)
return z - (z + 4) % 7
end
local function berlinOff(t)
local y = cfd(t // 86400)
if t >= lastSunday(y, 3) * 86400 + 3600 and t < lastSunday(y, 10) * 86400 + 3600 then return 7200 end
return 3600
end
local function toEpoch(y, mo, d, h, mi, s)
local L = dfc(y, mo, d) * 86400 + h * 3600 + mi * 60 + s
return L - berlinOff(L - 3600)
end
local function locParts(t)
local L = t + berlinOff(t)
local z = L // 86400
local y, m, d = cfd(z)
local sec = L % 86400
return y, m, d, sec // 3600, sec % 3600 // 60, (z + 3) % 7 + 1
end
local WD_DE = { "Mo", "Di", "Mi", "Do", "Fr", "Sa", "So" }
local WD_EN = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
local function timeKnown(t) return t % 60 ~= 59 end -- Sekunde 59 = Uhrzeit unbekannt (NFL nennt nur das Datum)
local function fmtDate(t)
local _, mo, d, _, _, wd = locParts(t)
return string.format("%s %02d.%02d.", (EN and WD_EN or WD_DE)[wd], d, mo)
end
local function fmtTime(t, clock24)
local _, _, _, h, mi = locParts(t)
if clock24 == false then
return string.format("%02d:%02d %s", h % 12 == 0 and 12 or h % 12, mi, h < 12 and "AM" or "PM")
end
return string.format("%02d:%02d", h, mi)
end
local function seasonStart()
local t = time.localtime()
if t == nil then return nil end
return t.month >= 7 and t.year or t.year - 1
end
local function slug(sy) return "saison-" .. sy .. "-" .. (sy + 1) end
local function clsBase(c, base)
if c:sub(1, #base) ~= base then return false end
local nx = c:byte(#base + 1)
if nx == nil then return true end
if nx < 65 or nx > 90 then return false end
return c:find("^%a*$", #base + 1) ~= nil
end
local function cell(body, pos)
return plain(body:match(">(.-)</li>", pos))
end
local function pair(s)
local a, b = s:match("^[^%d]*(%d+)%s*:%s*(%d+)")
if a then return tonumber(a), tonumber(b) end
return nil
end
local function parseTable(body)
local rows, group, lastPos, cur = {}, 0, 0, nil
local from = body:find("moduleResultContentTable", 1, true) or 1
for pos, cls in body:gmatch('()class="([^"]*)"', from) do
if cls == "text" or cls:sub(1, 5) == "text " then
group = group + 1 -- NFL: Division
lastPos = 0
cur = nil
elseif cls:sub(1, 11) == "first platz" then
cur = nil
local t = cell(body, pos)
local p
if t:find("^%d") then p = tonumber(t:match("^%d+"))
elseif t == "" and lastPos > 0 then p = lastPos end -- leere Platz-Zelle bei Punktgleichheit
if p then
if p < lastPos then group = group + 1 end -- Gruppen ohne Ueberschrift: der Platz springt zurueck
lastPos = p
if #rows < 40 then cur = { pos = p, group = group, name = "", sp = 0, w = 0, d = 0, l = 0, gf = 0, ga = 0, pts = 0 } end
end
elseif cur then
local c = cls:match("^%S+") or ""
if c:sub(1, 6) == "verein" then
cur.name = nameCut(cell(body, pos))
elseif clsBase(c, "sp") then cur.sp = tonumber(cell(body, pos):match("^%d+")) or 0
elseif clsBase(c, "s") then cur.w = tonumber(cell(body, pos):match("^%d+")) or 0
elseif clsBase(c, "u") then cur.d = tonumber(cell(body, pos):match("^%d+")) or 0
elseif clsBase(c, "n") then cur.l = tonumber(cell(body, pos):match("^%d+")) or 0
elseif c:sub(1, 4) == "tore" then
local a, b = pair(cell(body, pos))
if a then cur.gf, cur.ga = a, b end
elseif c:sub(1, 3) == "pkt" then
cur.pts = c:find("Ussport", 1, true) and cur.w or (tonumber(cell(body, pos):match("^%d+")) or 0)
if cur.name ~= "" then rows[#rows + 1] = cur end
cur = nil
end
end
end
return rows
end
local function parseRound(body, sy, want)
local out = {}
local from = body:find("moduleResultContentResultateList", 1, true) or 1
local nh, hv = 0, nil
for v in body:gmatch("(%d+)%.%s*Spieltag", from) do nh = nh + 1; hv = tonumber(v) end
if nh == 1 and want and hv ~= want then return out end
local day, mon, yr, hh, mm, tk, inRow, dateOk, cur = 0, 0, 0, 0, 0, false, false, false, nil
for pos, cls in body:gmatch('()class="([^"]*)"', from) do
local c = cls:match("^%S+") or ""
if c == "date" then
local t = body:match(">([^<]*)", pos) or ""
local d, mo, y = t:match("(%d+)%.(%d+)%.?(%d*)")
d, mo = tonumber(d), tonumber(mo)
if d and d >= 1 and d <= 31 and mo >= 1 and mo <= 12 then
day, mon = d, mo
y = tonumber(y) or 0
yr = y >= 2000 and y or (mo >= 7 and sy or sy + 1)
dateOk = true
end
inRow, tk, cur = dateOk, false, { home = "", away = "", scored = false, hs = 0, as = 0 }
elseif inRow then
if c == "time" then
local h, mi = (body:match(">([^<]*)", pos) or ""):match("(%d+):(%d+)")
h, mi = tonumber(h), tonumber(mi)
if h and h <= 23 and mi <= 59 then hh, mm, tk = h, mi, true end
elseif c == "heim" then cur.home = nameCut(cell(body, pos))
elseif c == "score" then
local a, b = pair(cell(body, pos))
if a then cur.scored, cur.hs, cur.as = true, a, b end
elseif c == "auswaerts" then
cur.away = nameCut(cell(body, pos))
inRow = false
if cur.home ~= "" and cur.away ~= "" then
cur.t = tk and toEpoch(yr, mon, day, hh, mm, 0) or toEpoch(yr, mon, day, 23, 59, 59)
out[#out + 1] = cur
end
cur = nil
end
end
end
return out
end
local function tablePath(path, sy) return path .. "/tabelle/tabelle-" .. slug(sy) end
local function roundPath(k, path, n, sy)
if k == 4 then return path .. "/ergebnisse/spieltag-" .. n .. "-" .. slug(sy) end
return path .. "/spielplan/spielplan-spieltag-" .. n .. "-" .. slug(sy)
end
local function readStore(k)
local txt = file.read("sp_" .. CODE[k])
if not txt then return nil end
local m = { rows = {}, matches = {} }
for line in txt:gmatch("[^\n]+") do
local f = {}
for v in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = v end
local c = f[1]
if c == "H" then
m.fetched, m.sig, m.sy = tonumber(f[2]), f[3], tonumber(f[4])
m.ownName, m.ownTla, m.ownPos, m.ownPts = f[5], f[6], tonumber(f[7]) or 0, tonumber(f[8]) or 0
m.lo, m.found, m.path = tonumber(f[9]), f[10] == "1", f[11]
elseif c == "T" then
m.rows[#m.rows + 1] = {
pos = tonumber(f[2]) or 0, name = f[3], tla = f[4], sp = tonumber(f[5]) or 0, w = tonumber(f[6]) or 0,
d = tonumber(f[7]) or 0, l = tonumber(f[8]) or 0, gf = tonumber(f[9]) or 0, ga = tonumber(f[10]) or 0,
pts = tonumber(f[11]) or 0,
}
elseif c == "M" then
m.matches[#m.matches + 1] = {
t = tonumber(f[2]) or 0, home = f[3] == "1", opp = f[4], tla = f[5], scored = f[6] == "1",
gf = tonumber(f[7]) or 0, ga = tonumber(f[8]) or 0, round = tonumber(f[9]) or 0,
}
end
end
if m.sig == nil then return nil end
return m
end
local function writeStore(k, m)
local out = {
table.concat({ "H", m.fetched, m.sig, m.sy, m.ownName, m.ownTla, m.ownPos, m.ownPts, m.lo or 0, m.found and 1 or 0, m.path }, "\t"),
}
for _, r in ipairs(m.rows) do
out[#out + 1] = table.concat({ "T", r.pos, r.name, r.tla, r.sp, r.w, r.d, r.l, r.gf, r.ga, r.pts }, "\t")
end
for _, x in ipairs(m.matches) do
out[#out + 1] = table.concat({ "M", x.t, x.home and 1 or 0, x.opp, x.tla, x.scored and 1 or 0, x.gf, x.ga, x.round }, "\t")
end
return file.write("sp_" .. CODE[k], table.concat(out, "\n"))
end
local function loadTable(path, sy, get)
local body, err = get(tablePath(path, sy))
if not body then return nil, sy, err end
local rows = parseTable(body)
body = nil
if #rows == 0 then
local b2 = get(tablePath(path, sy - 1))
if b2 then
local r2 = parseTable(b2)
if #r2 > 0 then rows, sy = r2, sy - 1 end
end
end
if #rows == 0 then return nil, sy, "sportal: " .. T("keine Tabelle", "no table") end
assignTlas(rows)
return rows, sy
end
local RESERVE, NETN = 0, 0 -- RESERVE: fuer Wappen freigehaltene Netzabrufe, NETN: bisherige Abrufe dieses Laufs
local function netGet()
local calls = 0
return function(p)
calls = calls + 1
NETN = calls
if calls > 1 then time.sleep(120) end
local body, err = http.get(BASE .. p, MAX_BYTES)
if not body and calls < 5 and tostring(err):find("unvollst", 1, true) then
time.sleep(500)
calls = calls + 1
NETN = calls
body, err = http.get(BASE .. p, MAX_BYTES)
end
if not body then return nil, "sportal: " .. tostring(err) end
if #body < 200 then return nil, "sportal: " .. T("leere Antwort", "empty response") end
return body
end, function() return calls end
end
local function isFinal(x, now, k)
return x.scored and (not timeKnown(x.t) or now - x.t >= liveWindow(k))
end
local function fetchKind(ctx, k, now)
local cfg = ctx.cfg
local team = teamOf(cfg, k)
local path = leaguePath(cfg, k)
local sig = sigOf(cfg, k)
local sy0 = seasonStart()
if sy0 == nil then return false, T("Uhrzeit noch nicht gestellt.", "Clock not set yet.") end
local get, calls = netGet()
local rows, sy, err = loadTable(path, sy0, get)
if not rows then return false, err end
local old = readStore(k)
if old and (old.sig ~= sig or old.sy ~= sy) then old = nil end
local own = findTeam(rows, team)
local grp = own and rows[own].group or rows[1].group
local m = {
fetched = now, sig = sig, sy = sy, path = path, rows = {}, matches = {},
ownName = "", ownTla = "", ownPos = 0, ownPts = 0, found = own ~= nil, lo = old and old.lo or 0,
}
for _, r in ipairs(rows) do
if r.group == grp and #m.rows < TABLE_MAX then m.rows[#m.rows + 1] = r end
end
if own then
local o = rows[own]
m.ownName, m.ownTla, m.ownPos, m.ownPts = o.name, o.tla, o.pos, o.pts
local ownLoose = loose(o.name)
local kept = old and old.matches or {}
local finalRound, nFinal = {}, 0
for _, x in ipairs(kept) do
if isFinal(x, now, k) then finalRound[x.round] = true; nFinal = nFinal + 1 end
end
local first = o.sp < 1 and 1 or o.sp
local maxRound = k == 4 and 22 or 60
local budget = 6 - (nFinal < LAST_MAX and 0 or RESERVE) - calls()
local want = {}
local fwd = nFinal < LAST_MAX and 2 or 4
for n = first, first + fwd - 1 do
if n <= maxRound and not finalRound[n] and #want < budget then want[#want + 1] = n end
end
if nFinal < LAST_MAX and #want >= budget and budget >= 2 then table.remove(want) end -- mindestens ein Spieltag zurueck
local backList = {}
local n = first - 1
while nFinal < LAST_MAX and #want < budget and n >= 1 and n >= first - 15 do
if not finalRound[n] then want[#want + 1] = n; backList[#backList + 1] = n end
n = n - 1
end
local fresh, okRound, got = {}, {}, 0
for _, n in ipairs(want) do
local body = get(roundPath(k, path, n, sy))
if body then
got = got + 1
okRound[n] = true
for _, g in ipairs(parseRound(body, sy, n)) do
local home = g.home == o.name or sameLoose(loose(g.home), g.home, ownLoose, o.name)
local away = not home and (g.away == o.name or sameLoose(loose(g.away), g.away, ownLoose, o.name))
if home or away then
local raw = home and g.away or g.home
local oi = findTeam(rows, raw)
local mine, theirs = g.hs, g.as
if away then mine, theirs = g.as, g.hs end
fresh[#fresh + 1] = {
t = g.t, home = home, opp = oi and rows[oi].name or raw, tla = oi and rows[oi].tla or deriveTla(raw),
scored = g.scored, gf = mine, ga = theirs, round = n,
}
end
end
body = nil
end
end
if #want > 0 and got == 0 then
m.matches = kept -- kein Spieltag geladen: die bisherigen Spiele bleiben
else
local all = {}
for _, x in ipairs(kept) do
if not okRound[x.round] then all[#all + 1] = x end
end
for _, x in ipairs(fresh) do all[#all + 1] = x end
table.sort(all, function(a, b) return a.t < b.t end)
local done, open = {}, {}
for _, x in ipairs(all) do
if isFinal(x, now, k) then done[#done + 1] = x
elseif now - x.t < 30 * 3600 then open[#open + 1] = x end
end
while #done > LAST_MAX + 1 do table.remove(done, 1) end
while #open > NEXT_MAX + 3 do table.remove(open) end
for _, x in ipairs(done) do m.matches[#m.matches + 1] = x end
for _, x in ipairs(open) do m.matches[#m.matches + 1] = x end
end
end
local ok, werr = writeStore(k, m)
if not ok then return false, "file: " .. tostring(werr) end
return true
end
local function wantedKinds(ctx)
local cfg, w = ctx.cfg, {}
if ctx.view == "dashboard" then
for _, o in ipairs(ctx.widgets or {}) do
local k = 1
if type(o) == "number" and (o & 0x3E) ~= 0 then
if o & 0x02 ~= 0 then k = 2 elseif o & 0x04 ~= 0 then k = 3 elseif o & 0x08 ~= 0 then k = 4 end
elseif cfg.wHandball == true then k = 2
elseif cfg.wBasketball == true then k = 3
elseif cfg.wFootball == true then k = 4 end
w[k] = true
end
return w
elseif ctx.view == "app" then
local k = KIND_ID[cfg.kind] or 1
if teamOf(cfg, k) == "" then
for i = 1, 4 do
if teamOf(cfg, i) ~= "" then k = i; break end
end
end
w[k] = true
return w
elseif ctx.view ~= nil then
return w
end
return nil
end
local function fetchData(ctx)
EN = ctx.lang == "en"
local now = time.now()
if now == nil then log("Sport: Uhr nicht synchron"); return false end
local cfg = ctx.cfg
local wanted = wantedKinds(ctx)
local shown = KIND_ID[cfg.kind] or 1
local pick, pickAt = nil, nil
for k = 1, 4 do
if teamOf(cfg, k) ~= "" and (wanted == nil or wanted[k]) then
local at = ctx.data.get("a" .. CODE[k]) or 0
if ctx.data.get("g" .. CODE[k]) ~= sigOf(cfg, k) then at = 0 end
local due = now - at >= DUE_SEC
if due and (pick == nil or (k == shown) or (pick ~= shown and at < pickAt)) then pick, pickAt = k, at end
end
end
if pick == nil then return true, false end
local code = CODE[pick]
local ok, err = fetchKind(ctx, pick, now)
ctx.data.set("g" .. code, sigOf(cfg, pick))
if ok then
ctx.data.set("a" .. code, now)
ctx.data.set("e" .. code, "")
else
log("Sport (" .. code .. "): " .. tostring(err))
ctx.data.set("a" .. code, now - (DUE_SEC - RETRY_SEC))
ctx.data.set("e" .. code, clean(err or "", 120))
end
return true, true
end
function on_action(ctx, name)
EN = ctx.lang == "en"
local k = ({ teams_eh = 1, teams_hb = 2, teams_bb = 3, teams_af = 4 })[name]
if not k then return { ok = false, message = "?" } end
local sy0 = seasonStart()
if sy0 == nil then return { ok = false, message = T("Uhrzeit noch nicht gestellt.", "Clock not set yet.") } end
local get = netGet()
local rows, _, err = loadTable(leaguePath(ctx.cfg, k), sy0, get)
if not rows then return { ok = false, message = err } end
table.sort(rows, function(a, b) return loose(a.name) < loose(b.name) end)
local opts = {}
for i, r in ipairs(rows) do
if i > 40 then break end
opts[#opts + 1] = { value = r.name, label = r.name }
end
return { ok = true, message = string.format(T("%d Teams geladen.", "%d teams loaded."), #opts), options = opts }
end
local function classify(m, now, k)
local last, nxt = {}, {}
local win = liveWindow(k)
for _, x in ipairs(m.matches) do
local since = now - x.t
local known = timeKnown(x.t)
local openW = known and win or 30 * 3600 -- ohne Uhrzeit (NFL) bis Datum + 30 h offen
if x.scored and since >= 0 then
if known and since < win then
x.live = true
nxt[#nxt + 1] = x
else
x.res = x.gf > x.ga and "W" or (x.gf < x.ga and "L" or "D")
last[#last + 1] = x
end
elseif since < openW then
x.live = false
nxt[#nxt + 1] = x
end
end
local byTime = function(a, b) return a.t < b.t end
table.sort(last, byTime)
table.sort(nxt, byTime)
while #last > LAST_MAX do table.remove(last, 1) end
while #nxt > NEXT_MAX do table.remove(nxt) end
return last, nxt
end
local function pageKind(cfg)
local k = KIND_ID[cfg.kind] or 1
if teamOf(cfg, k) == "" then
for i = 1, 4 do
if teamOf(cfg, i) ~= "" then return i end
end
end
return k
end
local function model(ctx, k)
local m = readStore(k)
if m == nil or m.sig ~= sigOf(ctx.cfg, k) then return nil end
local now = time.now() or m.fetched
m.last, m.nxt = classify(m, now, k)
m.now = now
return m
end
local SPORT_EN = { "ice hockey", "handball", "basketball", "american football" }
local STOP = { city = 1, club = 1, sport = 1, sports = 1, team = 1, united = 1, verein = 1, handball = 1, basketball = 1, hockey = 1, football = 1 }
local function urlEnc(t)
return (t:gsub("[^%w ]", function(c) return string.format("%%%02X", c:byte()) end):gsub(" ", "+"))
end
local function pickThumb(body, words, longest)
local d = json.decode(body)
local pages = type(d) == "table" and type(d.query) == "table" and d.query.pages
if type(pages) ~= "table" then return nil end
local best, bi = nil, 1000
for _, p in pairs(pages) do
local th = type(p.thumbnail) == "table" and p.thumbnail.source
if type(th) == "string" and type(p.title) == "string" then
local lt, hits = loose(p.title), 0
for _, w in ipairs(words) do if lt:find(w, 1, true) then hits = hits + 1 end end
local idx = tonumber(p.index) or 0
if lt:find(longest, 1, true) and hits >= math.min(2, #words) and idx < bi then best, bi = th, idx end
end
end
return best
end
local WIKI = "https://en.wikipedia.org/w/api.php?action=query&format=json&redirects=1&prop=pageimages&piprop=thumbnail&pilicense=any&pithumbsize=250"
local function wikiThumb(name, k)
local words, longest = {}, ""
for w in name:gmatch("[^%s%-%./]+") do
local l = loose(w)
if #l >= 4 and not STOP[l] then
words[#words + 1] = l
if #l > #longest then longest = l end
end
end
if longest == "" then return nil, "kein Suchwort" end
NETN = NETN + 1
local body, err = http.get(WIKI .. "&titles=" .. urlEnc(name), 24000)
local th = body and pickThumb(body, words, longest)
if th then return th end
if NETN + 2 > 6 then return nil, "Abrufbudget", true end
NETN = NETN + 1
body, err = http.get(WIKI .. "&generator=search&gsrlimit=8&gsrsearch=" .. urlEnc(name .. " " .. SPORT_EN[k]), 24000)
if not body then return nil, err end
th = pickThumb(body, words, longest)
if not th then return nil, "kein passender Artikel" end
return th
end
local function crestToken(k, name) return CODE[k] .. loose(name or "") end
local function loadCrest(ctx, k, slot, name, today, iw, ih)
iw, ih = iw or 203, ih or 135
local tok = crestToken(k, name) .. (iw ~= 203 and "w" or "")
if ctx.data.get("im_" .. slot) == tok then return false end
local fk = ctx.data.get("cf")
if type(fk) ~= "string" or fk:sub(1, 5) ~= today or #fk > 700 then fk = today end
local mark = "|" .. slot .. tok .. "|"
if fk:find(mark, 1, true) then return false end
local url, err, partial = wikiThumb(name, k)
if partial then return true end
local ok = false
if url then
NETN = NETN + 1
local good, ierr = http.image(url, slot, iw, ih)
ok = good == true
if not ok then err = ierr end
end
if ok then
ctx.data.set("im_" .. slot, tok)
ctx.data.set("ie", "")
else
log("Sport: Wappen " .. name .. ": " .. tostring(err))
ctx.data.set("ie", name:sub(1, 24) .. ": " .. tostring(err):sub(1, 70)) -- im Display sichtbar (Diagnose, CHANGELOG 602)
ctx.data.set("cf", fk .. mark)
end
return true
end
local function loadCrests(ctx, now)
local cfg = ctx.cfg
if cfg.crests == false or (cfg.style or "cards") ~= "cards" then return end
local k = pageKind(cfg)
local m = model(ctx, k)
local nx = m and m.found and m.nxt[1]
if not nx then return end
local today = ("00000" .. tostring(now // 86400)):sub(-5)
loadCrest(ctx, k, "own", m.ownName, today)
if NETN + 2 <= 6 then loadCrest(ctx, k, "opp", nx.opp, today) end
end
local function loadWidgetCrests(ctx, now)
local cfg = ctx.cfg
local today = ("00000" .. tostring(now // 86400)):sub(-5)
for k in pairs(wantedKinds(ctx) or {}) do
local m = teamOf(cfg, k) ~= "" and model(ctx, k) or nil
local nx = m and m.found and m.nxt[1]
if nx then
if NETN + 3 <= 6 then loadCrest(ctx, k, "w" .. k .. "o", m.ownName, today, 60, 40) end
if NETN + 3 <= 6 then loadCrest(ctx, k, "w" .. k .. "p", nx.opp, today, 60, 40) end
end
end
end
function on_fetch(ctx)
local cfg = ctx.cfg
local dash = ctx.view == "dashboard"
local want = cfg.crests ~= false and ctx.view ~= "other" and (dash or (cfg.style or "cards") == "cards")
RESERVE, NETN = 0, 0
local nowT = time.now()
local cf = ctx.data.get("cf")
local failedToday = nowT ~= nil and type(cf) == "string" and cf:sub(1, 5) == ("00000" .. tostring(nowT // 86400)):sub(-5)
if want and not failedToday then
if dash then
for k in pairs(wantedKinds(ctx) or {}) do
if teamOf(cfg, k) ~= "" and (ctx.data.get("im_w" .. k .. "o") == nil or ctx.data.get("im_w" .. k .. "p") == nil) then RESERVE = 3 end
end
elseif ctx.data.get("im_own") == nil or ctx.data.get("im_opp") == nil then RESERVE = 2 end
end
local ok, fetched = fetchData(ctx)
if ok and want and NETN + 2 <= 6 then
local now = time.now()
if now ~= nil then
if dash then loadWidgetCrests(ctx, now) else loadCrests(ctx, now) end
end
end
return ok
end
local function sportLine(ctx, k)
return kindLabel(k) .. " · " .. (LEAGUE_NAME[leaguePath(ctx.cfg, k)] or "")
end
local function emptyState(ctx, k, m)
if teamOf(ctx.cfg, k) == "" then
notice("gear", T("Noch kein Verein/Team gewählt.", "No club/team selected yet."), T("Einstellungen der App: Team wählen", "App settings: choose a team"))
return true
end
if m == nil then
local err = ctx.data.get("e" .. CODE[k])
if err and err ~= "" then
notice("warning", T("Abruf fehlgeschlagen.", "Fetch failed."), err)
else
notice("clock", T("Wird geladen ...", "Loading ..."))
end
return true
end
if #m.rows == 0 then
notice("info", T("Keine Ligadaten gefunden.", "No league data found."))
return true
end
return false
end
local function resColor(res)
if res == "W" then return color.GREEN end
if res == "D" then return color.YELLOW end
if res == "L" then return color.RED end
return color.BLACK
end
local function crestColor(sum)
local i = sum % 4
if i == 0 then return color.BLUE elseif i == 1 then return color.GREEN elseif i == 2 then return color.RED end
return color.BLACK
end
local function crest(x, y, w, h, code, size)
if code == nil or code == "" then code = "?" end
local sum = 0
for i = 1, #code do sum = sum + code:byte(i) end
local r = h // 4
if r > 10 then r = 10 end
draw.rect(x, y, w, h, crestColor(sum), true, r)
local font, off = "small", 5
if size >= 18 then font, off = "large", 9 elseif size >= 9 then font, off = "normal", 6 end
draw.text(x + w // 2, y + h // 2 + off, code, font, color.WHITE, "center")
end
local function bigCrest(ctx, k, x, y, w, h, tla, slot, name)
if ctx.cfg.crests ~= false and ctx.data.get("im_" .. slot) == crestToken(k, name) then
local iw, ih = draw.image_size(slot)
if iw and iw > 0 then
draw.image(slot, x + (w - iw) // 2, y + (h - ih) // 2)
return
end
end
crest(x, y, w, h, tla, 18)
end
local function resBadge(cx, cy, r, res)
local c = resColor(res)
draw.circle(cx, cy, r, c, true)
draw.text(cx, cy + 5, res, "small", res == "D" and color.BLACK or color.WHITE, "center")
end
local function centerBounded(s, x, y, font, minX, maxX)
local w = draw.measure(s, font)
local left = x - w // 2
if left + w > maxX then left = maxX - w end
if left < minX then left = minX end
draw.text(left, y, s, font, color.BLACK, "left")
end
local function compactNotice(cx, cy, icon, text)
draw.icon(icon, cx - 16, cy - 34, 32, color.ACCENT)
draw.text(cx, cy + 16, text, "small", color.BLACK, "center")
end
local function score(x) return x.gf .. ":" .. x.ga end
local function whenText(t)
if not timeKnown(t) then return fmtDate(t) end
return fmtDate(t) .. " · " .. fmtTime(t) .. (EN and "" or " Uhr")
end
local function homeAway(x) return x.home and T("Heim", "Home") or T("Auswärts", "Away") end
local function teamBento(ctx, k, m)
local W = draw.width
local cx = W // 2
local y = draw.top + 6
local bottom = draw.height - 14
local heroX, heroH = 20, 256
local heroW = W - 2 * heroX
draw.rect(heroX, y, heroW, heroH, color.BLACK, false, 12)
draw.text(heroX + 16, y + 22, sportLine(ctx, k), "small", color.BLACK, "left")
local nx = m.nxt[1]
if nx then
local head = whenText(nx.t)
if nx.live then
head = "LIVE  " .. (nx.home and score(nx) or (nx.ga .. ":" .. nx.gf))
draw.text(cx, y + 28, head, "normal", color.RED, "center")
else
draw.text(cx, y + 28, head, "normal", color.BLACK, "center")
end
local crestW, crestH = 203, 135
local crestY = y + 44
local own, opp = nx.home and "own" or "opp", nx.home and "opp" or "own"
local ownN, oppN = m.ownName, nx.opp
bigCrest(ctx, k, cx - 150 - crestW, crestY, crestW, crestH, nx.home and m.ownTla or nx.tla, own, nx.home and ownN or oppN)
bigCrest(ctx, k, cx + 150, crestY, crestW, crestH, nx.home and nx.tla or m.ownTla, opp, nx.home and oppN or ownN)
draw.text(cx, crestY + crestH // 2 + 10, "vs", "large", color.BLACK, "center")
draw.text(cx, y + 205, homeAway(nx), "small", color.BLACK, "center")
if not nx.home then draw.text(cx, y + 225, T("bei ", "at ") .. nx.opp, "small", color.BLACK, "center") end
else
compactNotice(cx, y + heroH // 2, "info", T("Kein anstehendes Spiel gefunden.", "No upcoming match found."))
end
local labelY = y + heroH + 22
draw.text(heroX, labelY, T("LETZTE 5 SPIELE", "LAST 5 MATCHES"), "small", color.BLACK, "left")
local tilesTop = labelY + 8
local tileH = bottom - tilesTop
if tileH > 128 then tileH = 128 end
if #m.last == 0 then
compactNotice(cx, tilesTop + tileH // 2, "info", T("Noch keine Ergebnisse in dieser Saison.", "No results yet this season."))
return
end
local gap = 10
local tileW = (heroW - (LAST_MAX - 1) * gap) // LAST_MAX
for i = 1, #m.last do
local x = m.last[#m.last + 1 - i]
local tx = heroX + (i - 1) * (tileW + gap)
draw.rect(tx, tilesTop, tileW, tileH, resColor(x.res), false, 10)
resBadge(tx + 18, tilesTop + 19, 9, x.res)
draw.text(tx + 32, tilesTop + 24, fit(x.opp, tileW - 40, "small"), "small", color.BLACK, "left")
draw.text(tx + tileW // 2, tilesTop + tileH // 2 + 16, score(x), "large", color.BLACK, "center")
crest(tx + tileW // 2 - 21, tilesTop + tileH - 30, 42, 22, x.tla, 7)
end
end
local function teamSlate(ctx, k, m)
local W = draw.width
local cx = W // 2
local y = draw.top + 10
local bottom = draw.height - 14
draw.line(cx, y + 4, cx, bottom - 4, color.BLACK)
draw.text(24, y + 18, T("Letzte Spiele", "Last matches"), "normal", color.BLACK, "left")
draw.text(cx + 20, y + 18, T("Nächste Spiele", "Next matches"), "normal", color.BLACK, "left")
draw.line(24, y + 28, cx - 24, y + 28, color.BLACK)
draw.line(cx + 20, y + 28, W - 24, y + 28, color.BLACK)
local listTop = y + 40
local rowH = (bottom - listTop) // LAST_MAX
if rowH > 76 then rowH = 76 end
if #m.last == 0 then draw.text(24, listTop + 16, T("Noch keine Ergebnisse.", "No results yet."), "small", color.BLACK, "left") end
for i = 1, #m.last do
local x = m.last[#m.last + 1 - i]
local rowY = listTop + (i - 1) * rowH
local base = rowY + rowH // 2 + 6
resBadge(24 + 8, base - 6, 8, x.res)
crest(24 + 26, base - 16, 36, 20, x.tla, 7)
local sc = score(x)
local scoreX = cx - 22 - draw.measure(sc, "normal")
local nameX = 24 + 26 + 36 + 8
draw.text(nameX, base, fit(x.opp, scoreX - nameX - 10, "normal"), "normal", color.BLACK, "left")
draw.text(scoreX, base, sc, "normal", color.BLACK, "left")
if i < #m.last then draw.line(24, rowY + rowH - 2, cx - 24, rowY + rowH - 2, color.BLACK) end
end
if #m.nxt == 0 then draw.text(cx + 20, listTop + 16, T("Keine anstehenden Spiele.", "No upcoming matches."), "small", color.BLACK, "left") end
for i, x in ipairs(m.nxt) do
local rowY = listTop + (i - 1) * rowH
local base = rowY + rowH // 2 - 2
crest(cx + 20, base - 16, 36, 20, x.tla, 7)
local d = fmtDate(x.t)
local dateX = W - 26 - draw.measure(d, "normal")
local nameX = cx + 20 + 36 + 8
draw.text(nameX, base, fit(x.opp, dateX - nameX - 10, "normal"), "normal", color.BLACK, "left")
draw.text(dateX, base, d, "normal", color.BLACK, "left")
local sub = homeAway(x)
if x.live then sub = "LIVE " .. (x.home and score(x) or (x.ga .. ":" .. x.gf)) .. " · " .. sub
elseif timeKnown(x.t) then sub = fmtTime(x.t) .. (EN and "" or " Uhr") .. " · " .. sub end
draw.text(nameX, base + 18, sub, "small", x.live and color.RED or color.BLACK, "left")
if i < #m.nxt then draw.line(cx + 20, rowY + rowH - 2, W - 24, rowY + rowH - 2, color.BLACK) end
end
end
local function teamNano(ctx, k, m)
local W = draw.width
local y = draw.top + 8
crest(24, y + 2, 44, 26, m.ownTla, 9)
local head = m.ownName
if m.ownPos > 0 then
head = string.format(T("%s · Platz %d · %d Pkt", "%s · Place %d · %d pts"), m.ownName, m.ownPos, m.ownPts)
end
draw.text(24 + 44 + 12, y + 21, fit(head, W - 24 - 56 - 24, "normal"), "normal", color.BLACK, "left")
local n = #m.last + 1 + #m.nxt
if n < 2 then
compactNotice(W // 2, y + 180, "info", T("Noch keine Spiele gefunden.", "No matches found yet."))
return
end
local lineY, marginX = 268, 56
local usable = W - 2 * marginX
draw.line(marginX, lineY, marginX + usable, lineY, color.BLACK)
for i = 0, n - 1 do
local x = marginX + usable * i // (n - 1)
local above = i % 2 == 0
local slotW = usable // (n - 1) + 8
local inner, name, tla = "", "", nil
if i < #m.last then
local g = m.last[i + 1]
draw.circle(x, lineY, 8, resColor(g.res), true)
inner, name, tla = score(g), g.opp, g.tla
elseif i == #m.last then
draw.circle(x, lineY, 8, color.BLACK, true)
inner = T("heute", "today")
else
local g = m.nxt[i - #m.last]
draw.circle(x, lineY, 8, color.BLACK)
draw.circle(x, lineY, 7, color.BLACK) -- doppelter Ring bleibt auf dem Panel sichtbar "leer"
inner, name, tla = fmtDate(g.t), g.opp, g.tla
end
if name ~= "" then name = fit(name, slotW, "small") end
if above then
centerBounded(inner, x, lineY - 26, "small", 4, W - 4)
if name ~= "" then centerBounded(name, x, lineY - 46, "small", 4, W - 4) end
if tla then crest(x - 17, lineY - 84, 34, 18, tla, 7) end
else
centerBounded(inner, x, lineY + 32, "small", 4, W - 4)
if name ~= "" then centerBounded(name, x, lineY + 52, "small", 4, W - 4) end
if tla then crest(x - 17, lineY + 64, 34, 18, tla, 7) end
end
end
end
local function tableCols(m, font)
local rightEdge = draw.width - 24
local dW = draw.measure("88", font)
local toreW, hasTore = dW, false
for _, r in ipairs(m.rows) do
local w = draw.measure(r.gf .. ":" .. r.ga, font)
if w > toreW then toreW = w end
if r.gf ~= 0 or r.ga ~= 0 then hasTore = true end
end
local c = {}
c.pktR = rightEdge
c.toreR = c.pktR - draw.measure("888", font) - 26
c.nR = c.toreR - toreW - 24
if not hasTore then c.toreR, c.nR = nil, c.pktR - draw.measure("888", font) - 26 end -- NFL: keine Punktedifferenz in der Tabelle
c.uR = c.nR - dW - 12
c.sR = c.uR - dW - 12
c.nameRight = c.sR - dW - 16
return c
end
local function tableHeader(ctx, k, m, c, base)
draw.text(24, base, sportLine(ctx, k), "small", color.BLACK, "left")
draw.text(c.sR, base, T("S", "W"), "small", color.BLACK, "right")
draw.text(c.uR, base, T("U", "D"), "small", color.BLACK, "right")
draw.text(c.nR, base, T("N", "L"), "small", color.BLACK, "right")
if c.toreR then draw.text(c.toreR, base, T("TORE", "GOALS"), "small", color.BLACK, "right") end
draw.text(c.pktR, base, T("PKT", "PTS"), "small", color.BLACK, "right")
end
local function tableNumbers(r, c, base, font)
draw.text(c.sR, base, tostring(r.w), font, color.BLACK, "right")
draw.text(c.uR, base, tostring(r.d), font, color.BLACK, "right")
draw.text(c.nR, base, tostring(r.l), font, color.BLACK, "right")
if c.toreR then draw.text(c.toreR, base, r.gf .. ":" .. r.ga, font, color.BLACK, "right") end
draw.text(c.pktR, base, tostring(r.pts), font, color.BLACK, "right")
end
local function windowStart(m, maxRows)
local n = #m.rows
if n <= maxRows then return 0 end
local own = -1
for i, r in ipairs(m.rows) do
if r.name == m.ownName then own = i - 1; break end
end
if own < 0 or own < maxRows then return 0 end
local start = own - maxRows // 2
if start + maxRows > n then start = n - maxRows end
if start < 0 then start = 0 end
return start
end
local function windowHint(m, cx, y, start, shown)
if start == 0 and shown >= #m.rows then return end
draw.text(cx, y, string.format(T("Plätze %d-%d von %d", "Places %d-%d of %d"), start + 1, start + shown, #m.rows), "small", color.BLACK, "center")
end
local function tableBento(ctx, k, m)
local cx = draw.width // 2
local y = draw.top + 6
local bottom = draw.height - 14
local c = tableCols(m, "normal")
tableHeader(ctx, k, m, c, y + 12)
y = y + 20
local rowH = 26
local maxRows = (bottom - y - 60) // rowH -- Platz fuer drei Zonen-Ueberschriften, wie die eingebaute App
if maxRows < 1 then maxRows = 1 end
local start = windowStart(m, maxRows)
local shown = math.min(#m.rows - start, maxRows)
local yy = y
for i = 1, shown do
local r = m.rows[start + i]
local base = yy + rowH // 2 + 6
if r.name == m.ownName then draw.rect(16, yy, draw.width - 32, rowH, color.BLACK, false, 8) end
draw.text(52, base, r.pos .. ".", "normal", color.BLACK, "right")
crest(60, base - 16, 36, 20, r.tla, 7)
local nameX = 60 + 36 + 10
draw.text(nameX, base, fit(r.name, c.nameRight - nameX, "normal"), "normal", color.BLACK, "left")
tableNumbers(r, c, base, "normal")
yy = yy + rowH
end
windowHint(m, cx, yy + 12, start, shown)
end
local function tableSlate(ctx, k, m)
local cx = draw.width // 2
local y = draw.top + 8
local bottom = draw.height - 12
local c = tableCols(m, "normal")
tableHeader(ctx, k, m, c, y + 12)
y = y + 18
local legendH = 20
local availH = bottom - y - legendH
local maxRows = availH // 20
if maxRows < 1 then maxRows = 1 end
local start = windowStart(m, maxRows)
local shown = math.min(#m.rows - start, maxRows)
local rowH = availH // (shown > 0 and shown or 1)
if rowH > 26 then rowH = 26 end
for i = 1, shown do
local r = m.rows[start + i]
local rowY = y + (i - 1) * rowH
local base = rowY + rowH // 2 + 6
if r.name == m.ownName then draw.rect(26, rowY, draw.width - 42, rowH, color.BLACK, false, 6) end
draw.text(58, base, r.pos .. ".", "normal", color.BLACK, "right")
crest(66, base - 15, 34, 19, r.tla, 7)
local nameX = 66 + 34 + 10
draw.text(nameX, base, fit(r.name, c.nameRight - nameX, "normal"), "normal", color.BLACK, "left")
tableNumbers(r, c, base, "normal")
end
windowHint(m, cx, y + shown * rowH + 12, start, shown)
end
local function tableNano(ctx, k, m)
local cx = draw.width // 2
local y = draw.top + 4
local bottom = draw.height - 10
local c = tableCols(m, "small")
tableHeader(ctx, k, m, c, y + 11)
y = y + 16
local availH = bottom - y
local maxRows = availH // 16
if maxRows < 1 then maxRows = 1 end
local start = windowStart(m, maxRows)
local shown = math.min(#m.rows - start, maxRows)
local rowH = availH // (shown > 0 and shown or 1)
if rowH > 24 then rowH = 24 end
for i = 1, shown do
local r = m.rows[start + i]
local rowY = y + (i - 1) * rowH
local base = rowY + rowH // 2 + 5
if r.name == m.ownName then draw.rect(14, rowY, draw.width - 28, rowH, color.BLACK, false, 5) end
draw.text(40, base, tostring(r.pos), "small", color.BLACK, "right")
local chipH = rowH - 3
if chipH > 18 then chipH = 18 end
if chipH < 12 then chipH = 12 end
crest(48, rowY + (rowH - chipH) // 2, 34, chipH, r.tla, 7)
local nameX = 48 + 34 + 8
draw.text(nameX, base, fit(r.name, c.nameRight - nameX, "small"), "small", color.BLACK, "left")
tableNumbers(r, c, base, "small")
if i < shown then draw.line(20, rowY + rowH - 1, draw.width - 20, rowY + rowH - 1, color.BLACK) end
end
windowHint(m, cx, y + shown * rowH + 10, start, shown)
end
function on_draw(ctx, page)
EN = ctx.lang == "en"
draw.clear(color.WHITE)
local k = pageKind(ctx.cfg)
local m = model(ctx, k)
if emptyState(ctx, k, m) then return end
local style = ctx.cfg.style
if page == 2 then
if style == "flat" then tableSlate(ctx, k, m)
elseif style == "compact" then tableNano(ctx, k, m)
else tableBento(ctx, k, m) end
return
end
if not m.found then
notice("search", T("Team nicht in der Tabelle gefunden.", "Team not found in the table."), T("Bitte in den Einstellungen neu wählen.", "Please choose it again in the settings."))
return
end
if style == "flat" then teamSlate(ctx, k, m)
elseif style == "compact" then teamNano(ctx, k, m)
else
teamBento(ctx, k, m)
local ie = ctx.data.get("ie")
if type(ie) ~= "string" or ie == "" then ie = T("noch kein Wappenabruf", "no crest fetch yet") end
if ctx.cfg.crests ~= false and (ctx.data.get("im_own") == nil or ctx.data.get("im_opp") == nil) then
draw.text(790, 474, "Wappen: " .. ie, "small", color.BLACK, "right") -- Diagnose (CHANGELOG 602)
end
end
end
function on_widget(ctx, box)
EN = ctx.lang == "en"
local cfg = ctx.cfg
local k, withHA, withPos = 1, cfg.wHomeAway == true, cfg.wTablePos == true
if cfg.widget == "sport_next" and type(cfg.opt) == "number" then
k = ((cfg.opt & 6) >> 1) + 1
withHA, withPos = cfg.opt & 1 ~= 0, cfg.opt & 8 ~= 0
elseif cfg.wHandball == true then k = 2
elseif cfg.wBasketball == true then k = 3
elseif cfg.wFootball == true then k = 4 end
local m = teamOf(cfg, k) ~= "" and model(ctx, k) or nil
local nx = m and m.nxt[1]
if nx == nil then
draw.text(box.x + 12, box.y + 16, T("Noch keine Daten", "No data yet"), "small", color.BLACK, "left")
return
end
local compact = cfg.style == "compact"
local tier = box.font or 0
local font = tier < 0 and "small" or (tier > 0 and "medium" or "normal")
local maxY = box.y + box.h - 4
local areaH = maxY - box.y
local cx = box.x + box.w // 2
local crestH = compact and 22 or (areaH >= 110 and 40 or (areaH >= 80 and 32 or 24))
local crestW = crestH * 3 // 2
local vsGap = compact and 18 or 22
local crestY = box.y + 4
local leftX, rightX = cx - crestW - vsGap // 2, cx + vsGap // 2
local cfont = compact and 7 or 9
local function wcrest(x, tla, slot, name)
if ctx.cfg.crests ~= false then
local tok = crestToken(k, name)
local big = slot:sub(-1) == "o" and "own" or "opp"
for _, c in ipairs({ { slot, tok .. "w" }, { big, tok } }) do
if ctx.data.get("im_" .. c[1]) == c[2] then
local iw, ih = draw.image_size(c[1])
if iw and iw > 0 and ih > 0 then
local dw, dh = crestW, crestW * ih // iw
if dh > crestH then dh, dw = crestH, crestH * iw // ih end
if dw > iw then dw, dh = iw, ih end
draw.image(c[1], x + (crestW - dw) // 2, crestY + (crestH - dh) // 2, dw, dh)
return
end
end
end
end
crest(x, crestY, crestW, crestH, tla, cfont)
end
wcrest(leftX, nx.home and m.ownTla or nx.tla, nx.home and "w" .. k .. "o" or "w" .. k .. "p", nx.home and m.ownName or nx.opp)
wcrest(rightX, nx.home and nx.tla or m.ownTla, nx.home and "w" .. k .. "p" or "w" .. k .. "o", nx.home and nx.opp or m.ownName)
draw.text(cx, crestY + crestH // 2 + 4, "vs", "small", color.BLACK, "center")
local lineY = crestY + crestH + (compact and 16 or 22)
if lineY > maxY then return end
local text, col
if nx.live then
local hg, ag = nx.home and nx.gf or nx.ga, nx.home and nx.ga or nx.gf
text, col = string.format("LIVE  %d:%d", hg, ag), color.RED
draw.circle(cx - draw.measure(text, font) // 2 - 10, lineY - 5, 4, color.RED, true)
else
local d = fmtDate(nx.t)
local ha = nx.home and T("Heim", "Home") or T("Auswärts", "Away")
local known = timeKnown(nx.t)
local tt = known and fmtTime(nx.t, ctx.clock24) or ""
if withHA and known then text = ha .. " · " .. d .. " " .. tt
elseif withHA then text = ha .. " · " .. d
elseif known then text = d .. " " .. tt
else text = d end
col = color.ACCENT_TEXT
end
text = fit(text, box.w - 16, font)
draw.text(cx, lineY, text, font, col, "center")
if withPos and m.ownPos > 0 then
local posY = lineY + (compact and 14 or 17)
if posY <= maxY then
draw.text(cx, posY, string.format(T("Platz %d · %d Pkt.", "Rank %d · %d pts"), m.ownPos, m.ownPts), "small", color.BLACK, "center")
end
end
end
