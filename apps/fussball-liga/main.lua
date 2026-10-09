local EN = false
local function T(de, en) if EN then return en end return de end
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
local OLDB = "https://api.openligadb.de/"
local FDB = "https://api.football-data.org/v4/"
local LIVE_SEC = 130 * 60 -- laenger als 90 Min. + Pause + Nachspielzeit gilt ein offenes Spiel nicht mehr als live
local CL = { "Champions League", "Champions League" }
local EU = { "Europa-Plätze", "Europe spots" }
local UP = { "Aufstieg", "Promotion" }
local RELE = { "Relegation", "Relegation" }
local LEAGUES = {
BL1 = { n = "Bundesliga", o = "bl1", z = { 4, 2, 3 }, l1 = CL, l2 = EU },
BL2 = { n = "2. Bundesliga", o = "bl2", z = { 2, 1, 2 }, l1 = UP, l2 = RELE },
BL3 = { n = "3. Liga", o = "bl3", z = { 2, 1, 4 }, l1 = UP, l2 = RELE },
DFB = { n = "DFB-Pokal", o = "dfb", c = true, z = { 0, 0, 0 } },
PL = { n = "Premier League", z = { 4, 2, 3 }, l1 = CL, l2 = EU },
PD = { n = "La Liga", z = { 4, 2, 3 }, l1 = CL, l2 = EU },
SA = { n = "Serie A", z = { 4, 2, 3 }, l1 = CL, l2 = EU },
FL1 = { n = "Ligue 1", z = { 3, 2, 3 }, l1 = CL, l2 = EU },
DED = { n = "Eredivisie", z = { 2, 2, 2 }, l1 = CL, l2 = EU },
PPL = { n = "Primeira Liga", z = { 2, 2, 2 }, l1 = CL, l2 = EU },
ELC = { n = "Championship", z = { 2, 4, 3 }, l1 = UP, l2 = { "Playoffs", "Playoffs" } },
BSA = { n = "Série A (Brasilien)", z = { 4, 2, 4 }, l1 = { "Libertadores", "Libertadores" }, l2 = { "Sudamericana", "Sudamericana" } },
}
local COLS = { r = color.RED, b = color.BLUE, g = color.GREEN, y = color.YELLOW, k = color.BLACK }
local FOLD = {
["\195\164"] = "a", ["\195\132"] = "a", ["\195\182"] = "o", ["\195\150"] = "o", ["\195\188"] = "u", ["\195\156"] = "u",
["\195\159"] = "ss", ["\195\169"] = "e", ["\195\168"] = "e", ["\195\170"] = "e", ["\195\161"] = "a", ["\195\160"] = "a",
["\195\173"] = "i", ["\195\179"] = "o", ["\195\186"] = "u", ["\195\167"] = "c", ["\195\177"] = "n",
}
local function nk(s)
s = tostring(s or ""):lower():gsub("\195.", FOLD)
return (s:gsub("[^%w]", ""))
end
local function cname(full, short) return (full ~= nil and full ~= "") and full or short end
local function splitTabs(line)
local out = {}
for f in (line .. "\t"):gmatch("([^\t]*)\t") do out[#out + 1] = f end
return out
end
local function eachObj(body, f)
for obj in body:gmatch("%b{}") do
local t = json.decode(obj)
if type(t) == "table" then f(t) end
end
end
local function n0(v) return tonumber(v) or 0 end
local function euDst(e)
local y = cfd(e // 86400)
local function lastSunday(m)
local d31 = dfc(y, m, 31)
return d31 - ((d31 + 4) % 7)
end
return e >= lastSunday(3) * 86400 + 3600 and e < lastSunday(10) * 86400 + 3600
end
local OFF_NOW = nil
local function offsetNow()
if OFF_NOW ~= nil then return OFF_NOW end
local lt, now = time.localtime(), time.now()
if lt == nil or now == nil then OFF_NOW = false; return false end
local ls = dfc(lt.year, lt.month, lt.day) * 86400 + lt.hour * 3600 + lt.min * 60 + lt.sec
local off = math.floor((ls - now) / 900 + 0.5) * 900
if off < -14 * 3600 or off > 14 * 3600 then off = 0 end
OFF_NOW = off
return off
end
local function offsetAt(e)
local off = offsetNow()
if off == false then return 0 end
local std = off - (euDst(time.now()) and 3600 or 0)
if std == 0 or std == 3600 or std == 7200 then return std + (euDst(e) and 3600 or 0) end
return off
end
local WD_DE = { "So", "Mo", "Di", "Mi", "Do", "Fr", "Sa" }
local WD_EN = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local function localParts(e)
local le = e + offsetAt(e)
local days = le // 86400
local sod = le - days * 86400
local y, m, d = cfd(days)
return { year = y, month = m, day = d, hour = sod // 3600, min = (sod % 3600) // 60, wday = (days + 4) % 7 }
end
local function fmtDate(e)
local p = localParts(e)
return string.format("%s %02d.%02d.", (EN and WD_EN or WD_DE)[p.wday + 1], p.day, p.month)
end
local function fmtDateTime(e)
local p = localParts(e)
return fmtDate(e) .. string.format(" · %02d:%02d", p.hour, p.min)
end
local function whenOf(m)
local e = parseIso(m.matchDateTimeUTC)
if e then return e end
e = parseIso(m.matchDateTime)
if e then return e - (euDst(e) and 7200 or 3600) end
return nil
end
local ASSET = nil
local function deriveTla(name)
local t, n = {}, 0
for w in name:gmatch("[^%s%.%-]+") do
n = n + 1
if n <= 3 then t[#t + 1] = w:sub(1, 1):upper() end
end
if n == 1 then return nk(name):sub(1, 3):upper() end
local s = table.concat(t)
return s ~= "" and s or "?"
end
local function hashColor(tla)
local sum = 0
for i = 1, #tla do sum = sum + tla:byte(i) end
return ({ "b", "g", "r", "k" })[sum % 4 + 1]
end
local function crestOf(code, name, full, apiTla)
if ASSET == nil then ASSET = asset.read("crests") or "" end
local tla, col
if apiTla and apiTla ~= "" then
tla = apiTla
col = ASSET:match("\nt|" .. code .. "|" .. tla:gsub("%W", "%%%0") .. "|(%a)")
else
for _, k in ipairs({ nk(name), nk(full) }) do
if k ~= "" then
local _, e = ASSET:find("\nn|[^\n]-," .. k .. ",")
if e then
tla, col = ASSET:match("^[^|\n]*|(%w+)|(%a)", e + 1)
if tla then break end
end
end
end
if not tla then tla = deriveTla(name ~= "" and name or full) end
end
return tla, col or hashColor(tla)
end
local function crestUrl(url, px)
if type(url) ~= "string" or not url:find("^https://upload%.wikimedia%.org/") then return nil end
if url:find("%.svg$") then
local base, rest = url:match("^(https://upload%.wikimedia%.org/wikipedia/%a+)/(%w/%w%w/[^/]+)$")
if not base then return nil end
return base .. "/thumb/" .. rest .. "/" .. px .. "px-" .. rest:match("[^/]+$") .. ".png"
end
if url:find("%.png$") or url:find("%.jpe?g$") then return url end
return nil
end
local function cfgOf(ctx)
local cfg = ctx.cfg
local code = LEAGUES[cfg.league] and cfg.league or "BL1"
local team = clean(cfg.team or "", 60)
return code, LEAGUES[code], team, code .. "|" .. team
end
local function mrec(f)
return { when = n0(f[2]), home = f[3] == "1", opp = f[4] or "", tla = f[5] or "", col = COLS[f[6]] or color.BLUE,
gf = n0(f[7]), ga = n0(f[8]), res = f[9] or "", live = f[10] == "1", oppFull = f[11] or "", oppIcon = f[12] or "" }
end
local D = nil -- Daten der aktuellen Auswahl, false = keine
local function readData(ctx)
if D ~= nil then return D end
D = false
local _, _, _, sig = cfgOf(ctx)
local text = file.read("d")
if not text then return D end
local d = { tab = {}, last = {}, nxt = {} }
for line in text:gmatch("[^\n]+") do
local f = splitTabs(line)
local k = f[1]
if k == "H" then
if f[2] ~= sig then return D end
d.at = n0(f[3])
d.own = { id = n0(f[4]), name = f[5] or "", tla = f[6] or "", col = COLS[f[7]] or color.BLUE, venue = f[8] or "",
pos = n0(f[9]), pts = n0(f[10]), full = f[11] or "", icon = f[12] or "" }
elseif k == "T" then
d.tab[#d.tab + 1] = { id = n0(f[2]), pos = #d.tab + 1, name = f[3] or "", tla = f[4] or "", col = COLS[f[5]] or color.BLUE,
pl = n0(f[6]), w = n0(f[7]), d = n0(f[8]), l = n0(f[9]), gf = n0(f[10]), ga = n0(f[11]), pts = n0(f[12]) }
elseif k == "L" then d.last[#d.last + 1] = mrec(f)
elseif k == "N" then d.nxt[#d.nxt + 1] = mrec(f)
elseif k == "W" then d.wnext = mrec(f)
end
end
if d.own then D = d end
return D
end
local NET = 0
local function sleepGap()
NET = NET + 1
if NET > 1 then time.sleep(250) end
end
local KEEP_T = { "teamInfoId", "teamName", "shortName", "teamIconUrl", "matches", "won", "draw", "lost", "points", "goals", "opponentGoals" }
local KEEP_M = { "matchDateTimeUTC", "matchDateTime", "matchIsFinished", "leagueShortcut", "teamId", "teamName", "shortName", "teamIconUrl",
"resultTypeID", "pointsTeam1", "pointsTeam2", "locationStadium" }
local SKIP_M = { "goals" }
local KEEP_FS = { "type", "position", "id", "name", "shortName", "tla", "crest", "playedGames", "won", "draw", "lost", "points", "goalsFor", "goalsAgainst" }
local SKIP_FS = { "area", "competition", "season", "filters" }
local KEEP_FM = { "utcDate", "status", "code", "id", "name", "shortName", "tla", "crest", "winner", "home", "away" }
local SKIP_FM = { "area", "season", "referees", "odds", "halfTime", "regularTime", "extraTime", "penalties", "filters", "resultSet" }
local function oGet(path, maxBytes, keep, skip)
sleepGap()
local r, err = http.request{ url = OLDB .. path, keep = keep, skip = skip, maxBytes = maxBytes }
if r == nil then log("Fussball: " .. tostring(err)); return nil, "net" end
if r.status ~= 200 then log("Fussball: HTTP " .. tostring(r.status)); return nil, "net" end
return r.body
end
local function fdGet(path, key, maxBytes, keep, skip)
sleepGap()
local r, err = http.request{ url = FDB .. path, headers = { ["X-Auth-Token"] = key }, keep = keep, skip = skip, maxBytes = maxBytes }
if r == nil then
log("Fussball: " .. tostring(err))
return nil, "net"
end
if r.status == 401 or r.status == 403 then return nil, "key" end
if r.status == 429 then return nil, "rate" end
if r.status ~= 200 then log("Fussball: HTTP " .. tostring(r.status)); return nil, "net" end
return r.body
end
local function seasonOf(now)
local y, m = cfd(now // 86400)
return m >= 7 and y or y - 1
end
local function isoDay(e)
local y, m, d = cfd(e // 86400)
return string.format("%04d-%02d-%02d", y, m, d)
end
local function oScore(m, fin)
local fin2, ext, other, half, last, pen
for _, r in ipairs(type(m.matchResults) == "table" and m.matchResults or {}) do
if type(r) == "table" then
local t, a, b = n0(r.resultTypeID), n0(r.pointsTeam1), n0(r.pointsTeam2)
if t == 5 then
pen = { a, b }
else
last = { a, b }
if t == 3 then ext = { a, b } elseif t == 2 then fin2 = { a, b } elseif t == 1 then half = { a, b } else other = other or { a, b } end
end
end
end
if fin then
local s = ext or fin2 or other or half or { 0, 0 }
return s[1], s[2], pen and pen[1], pen and pen[2]
end
local s = last or { 0, 0 }
return s[1], s[2]
end
local function resultOf(home, a, b, s1, s2)
if a == b and s1 and s2 and s1 ~= s2 then a, b = s1, s2 end -- Elfmeterschiessen entscheidet bei Gleichstand
local own, opp = a, b
if not home then own, opp = b, a end
if own > opp then return "W" elseif own < opp then return "L" end
return "D"
end
local function tName(t)
local n = clean(t.shortName or "", 25)
if n == "" then n = clean(t.teamName or "", 25) end
return n
end
local function oMatch(code, m, id, now)
local t1, t2 = m.team1, m.team2
if type(t1) ~= "table" or type(t2) ~= "table" then return nil end
local home
if n0(t1.teamId) == id then home = true elseif n0(t2.teamId) == id then home = false else return nil end
local when = whenOf(m)
if not when then return nil end
local opp, own = home and t2 or t1, home and t1 or t2
local fin = m.matchIsFinished == true
local g1, g2, s1, s2 = oScore(m, fin)
local live = (not fin) and when <= now and now - when < LIVE_SEC
local oppName = tName(opp)
local tla, col = crestOf(code, oppName, opp.teamName or "")
local gf, ga = g1, g2
if not home then gf, ga = g2, g1 end
local r = { when = when, home = home, opp = oppName, tla = tla, col = col, gf = gf, ga = ga, fin = fin, live = live,
res = fin and resultOf(home, g1, g2, s1, s2) or "", lg = tostring(m.leagueShortcut or ""):lower(),
stale = (not fin) and when < now - LIVE_SEC, oppIcon = opp.teamIconUrl, ownIcon = own.teamIconUrl, ownName = tName(own),
ownFull = own.teamName or "", oppFull = clean(opp.teamName or "", 60) }
if home and type(m.location) == "table" then r.venue = clean(m.location.locationStadium or "", 35) end
if not live then r.gf, r.ga = fin and gf or 0, fin and ga or 0 end
return r
end
local function pickMatches(ms, inLg)
table.sort(ms, function(a, b) return a.when < b.when end)
local last, nxt, wn = {}, {}, nil
for _, r in ipairs(ms) do
if not r.fin and not r.stale and wn == nil then wn = r end
if inLg(r) then
if r.fin then
last[#last + 1] = r
if #last > 5 then table.remove(last, 1) end
elseif not r.stale and #nxt < 3 then
nxt[#nxt + 1] = r
end
end
end
return last, nxt, wn
end
local function teamMatcher(team)
local id = tonumber(team)
local want = nk(team)
local function score(a, b)
local ka, kb = nk(a), nk(b)
if want == ka or want == kb then return 2 end
if #want >= 4 then
for _, k in ipairs({ ka, kb }) do
if k ~= "" and (k:find(want, 1, true) or want:find(k, 1, true)) then return 1 end
end
end
return 0
end
return id, score
end
local function colLetter(c)
if type(c) == "string" then return c end
for k, v in pairs(COLS) do if v == c then return k end end
return "b"
end
local function mline(k, m)
return table.concat({ k, m.when, m.home and 1 or 0, m.opp, m.tla, colLetter(m.col), m.gf or 0, m.ga or 0, m.res or "",
m.live and 1 or 0, m.oppFull or "", m.oppIcon or "" }, "\t")
end
local function saveData(sig, now, own, tab, last, nxt, wn)
local out = { table.concat({ "H", sig, now, own.id, own.name, own.tla, colLetter(own.col), own.venue or "", own.pos or 0,
own.pts or 0, own.full or "", own.icon or "" }, "\t") }
for _, r in ipairs(tab) do
out[#out + 1] = table.concat({ "T", r.id, r.name, r.tla, colLetter(r.col), r.pl, r.w, r.d, r.l, r.gf, r.ga, r.pts }, "\t")
end
for _, m in ipairs(last) do out[#out + 1] = mline("L", m) end
for _, m in ipairs(nxt) do out[#out + 1] = mline("N", m) end
if wn then out[#out + 1] = mline("W", wn) end
return file.write("d", table.concat(out, "\n"))
end
local function previous(ctx, sig)
D = nil
local d = readData(ctx)
D = nil
return d
end
local WIKI = "https://en.wikipedia.org/w/api.php?action=query&format=json&redirects=1&prop=pageimages&piprop=thumbnail&pilicense=any&pithumbsize=250"
local STOPW = { club = 1, football = 1, verein = 1, team = 1, city = 1, united = 1, sport = 1 }
local function urlEnc(t)
return (t:gsub("[^%w ]", function(c) return string.format("%%%02X", c:byte()) end):gsub(" ", "+"))
end
local function wikiPick(body, words, longest)
local d = json.decode(body)
local pages = type(d) == "table" and type(d.query) == "table" and d.query.pages
if type(pages) ~= "table" then return nil end
local best, bi = nil, 1000
for _, p in pairs(pages) do
local th = type(p.thumbnail) == "table" and p.thumbnail.source
if type(th) == "string" and type(p.title) == "string" then
local lt, hits = nk(p.title), 0
for _, w in ipairs(words) do if lt:find(w, 1, true) then hits = hits + 1 end end
local idx = tonumber(p.index) or 0
if lt:find(longest, 1, true) and hits >= math.min(2, #words) and idx < bi then best, bi = th, idx end
end
end
return best
end
local function wikiThumb(name)
local words, longest = {}, ""
for w in name:gmatch("[^%s%-%./]+") do
local l = nk(w)
if #l >= 4 and not STOPW[l] then
words[#words + 1] = l
if #l > #longest then longest = l end
end
end
if longest == "" then return nil, "kein Suchwort" end
NET = NET + 1
local body, err = http.get(WIKI .. "&titles=" .. urlEnc(name), 24000)
local th = body and wikiPick(body, words, longest)
if th then return th end
if NET + 2 > 6 then return nil, "Abrufbudget", true end
NET = NET + 1
body, err = http.get(WIKI .. "&generator=search&gsrlimit=8&gsrsearch=" .. urlEnc(name .. " football club"), 24000)
if not body then return nil, err end
th = wikiPick(body, words, longest)
if not th then return nil, "kein passender Artikel" end
return th
end
local function providerPng(url)
if type(url) ~= "string" then return nil end
local l = url:lower()
if l:find("^https://") and (l:find("%.png$") or l:find("%.png%?")) and not l:find("wikimedia", 1, true) then return url end
return nil
end
local function loadCrest(ctx, slot, url, full, short, w, h, today)
local name = (full ~= nil and full ~= "") and full or short
local key = nk(name)
if key == "" then return end
local tok = key .. w
if ctx.data.get("im_" .. slot) == tok then return end
local fk = ctx.data.get("imf")
if type(fk) ~= "string" or fk:sub(1, 5) ~= today or #fk > 700 then fk = today end
if fk:find("|" .. slot .. tok .. "|", 1, true) then return end
local ok, err = false, nil
local function try(u)
if NET + 1 > 6 then return "budget" end
NET = NET + 1
local good, e = http.image(u, slot, w, h)
ok = good == true
if not ok then err = e end
end
local u = crestUrl(url, 250)
if u and try(u) == "budget" then return end
if not ok then
local wu, werr, partial = wikiThumb(name)
if partial then return end
if wu then
if try(wu) == "budget" then return end
else
err = werr or err
end
end
if not ok then
local pu = providerPng(url)
if pu then
if try(pu) == "budget" then return end
end
end
if ok then
ctx.data.set("im_" .. slot, tok)
ctx.data.set("ie", "")
else
log("Fussball: Wappen " .. slot .. " (" .. name .. "): " .. tostring(err))
ctx.data.set("ie", name:sub(1, 24) .. ": " .. tostring(err):sub(1, 70)) -- im Display sichtbar (Diagnose, CHANGELOG 602)
ctx.data.set("imf", fk .. "|" .. slot .. tok .. "|")
end
end
local function loadCrests(ctx, now)
if ctx.cfg.crests == false or now == nil then return end
D = nil
local d = readData(ctx)
if not d or not d.own then return end
local today = ("00000" .. tostring(now // 86400)):sub(-5)
local own = d.own
if ctx.view == "dashboard" then -- Widget: kleine Wappen des Widget-Spiels (kann ein anderer Wettbewerb sein)
local m = d.wnext or d.nxt[1]
if m then
loadCrest(ctx, "wown", own.icon, own.full, own.name, 60, 40, today)
loadCrest(ctx, "wopp", m.oppIcon, m.oppFull, m.opp, 60, 40, today)
end
return
end
local m = d.nxt[1]
if ctx.cfg.style == "compact" then
loadCrest(ctx, "owns", own.icon, own.full, own.name, 44, 26, today)
elseif (ctx.cfg.style or "cards") == "cards" then
loadCrest(ctx, "own", own.icon, own.full, own.name, 203, 135, today)
if m then loadCrest(ctx, "opp", m.oppIcon, m.oppFull, m.opp, 203, 135, today) end
end
local wm = d.wnext
if wm and cname(wm.oppFull, wm.opp) ~= (m and cname(m.oppFull, m.opp) or "") then
loadCrest(ctx, "wopp", wm.oppIcon, wm.oppFull, wm.opp, 60, 40, today)
end
end
local function fetchOLeague(ctx, code, lg, team, now, sig)
local season = seasonOf(now)
local body, err = oGet("getbltable/" .. lg.o .. "/" .. season, 40000, KEEP_T)
if not body then return false, "tab" end
local rows, id, score = {}, teamMatcher(team)
local best, bestScore = nil, 0
eachObj(body, function(r)
if n0(r.teamInfoId) > 0 then
local nm = clean(r.shortName or "", 25)
if nm == "" then nm = clean(r.teamName or "", 25) end
local tla, col = crestOf(code, nm, r.teamName or "")
local row = { id = n0(r.teamInfoId), pos = #rows + 1, name = nm, full = clean(r.teamName or "", 60), tla = tla, col = col, pl = n0(r.matches), w = n0(r.won),
d = n0(r.draw), l = n0(r.lost), gf = n0(r.goals), ga = n0(r.opponentGoals), pts = n0(r.points), icon = r.teamIconUrl }
rows[#rows + 1] = row
if not id then
local s = score(r.teamName, r.shortName)
if s > bestScore then best, bestScore = row, s end
end
end
end)
if #rows == 0 then return false, "notab" end
local own
if id then
for _, r in ipairs(rows) do if r.id == id then own = r end end
else
own = best
id = own and own.id
end
if not id then return false, "noteam" end
local old = previous(ctx, sig)
local ownInfo = own and { id = id, name = own.name, tla = own.tla, col = own.col, pos = own.pos, pts = own.pts, full = own.full, icon = own.icon }
or { id = id, name = "", tla = "", col = "b", pos = 0, pts = 0 }
local last, nxt, wn
local mbody = oGet("getmatchesbyteamid/" .. id .. "/16/6", 48000, KEEP_M, SKIP_M)
local oppIcon, ownIcon
if mbody then
local ms = {}
eachObj(mbody, function(m)
local r = oMatch(code, m, id, now)
if r then ms[#ms + 1] = r end
end)
local want = lg.o
last, nxt, wn = pickMatches(ms, function(r) return r.lg == want end)
for _, r in ipairs(ms) do
if r.venue and r.venue ~= "" and ownInfo.venue == nil then ownInfo.venue = r.venue end
if ownInfo.name == "" then ownInfo.name = r.ownName; ownInfo.tla, ownInfo.col = crestOf(code, r.ownName, r.ownFull) end
if (ownInfo.full or "") == "" then ownInfo.full = clean(r.ownFull or "", 60) end
ownIcon = ownIcon or r.ownIcon
end
if nxt[1] then oppIcon = nxt[1].oppIcon end
elseif old then
last, nxt, wn = old.last, old.nxt, old.wnext
if old.own.venue ~= "" then ownInfo.venue = old.own.venue end
else
last, nxt = {}, {}
end
ownInfo.icon = own and own.icon or ownIcon
local ok = saveData(sig, now, ownInfo, rows, last, nxt, wn)
if ok ~= true then return false, "net" end
return true
end
local function fetchOCup(ctx, code, lg, team, now, sig)
local season = seasonOf(now)
local body = oGet("getmatchdata/" .. lg.o .. "/" .. season, 60000, KEEP_M, SKIP_M)
if not body then return false, "mat" end
local id, score = teamMatcher(team)
if not id then
local best, bestScore = nil, 0
eachObj(body, function(m)
for _, t in ipairs({ m.team1 or {}, m.team2 or {} }) do
local s = score(t.teamName, t.shortName)
if s > bestScore then best, bestScore = n0(t.teamId), s end
end
end)
id = best
end
if not id or id == 0 then
if body:find("%b{}") then return false, "noteam" end
return false, "nomatch"
end
local ms = {}
eachObj(body, function(m)
local r = oMatch(code, m, id, now)
if r then ms[#ms + 1] = r end
end)
if #ms == 0 and not body:find("%b{}") then return false, "nomatch" end
local wbody = oGet("getmatchesbyteamid/" .. id .. "/1/8", 48000, KEEP_M, SKIP_M)
local all = {}
for _, r in ipairs(ms) do all[#all + 1] = r end
if wbody then
eachObj(wbody, function(m)
local r = oMatch(code, m, id, now)
if r then all[#all + 1] = r end
end)
end
local last, nxt = pickMatches(ms, function() return true end)
local _, _, wn = pickMatches(all, function() return false end)
local ownInfo = { id = id, name = "", tla = "", col = "b", pos = 0, pts = 0 }
local ownIcon
for _, r in ipairs(ms) do
if ownInfo.name == "" then ownInfo.name = r.ownName; ownInfo.tla, ownInfo.col = crestOf(code, r.ownName, r.ownFull); ownInfo.full = clean(r.ownFull or "", 60) end
if r.venue and r.venue ~= "" and ownInfo.venue == nil then ownInfo.venue = r.venue end
ownIcon = ownIcon or r.ownIcon
end
if ownInfo.name == "" then return false, "nomatch" end
ownInfo.icon = ownIcon
if saveData(sig, now, ownInfo, {}, last, nxt, wn) ~= true then return false, "net" end
return true
end
local function fetchF(ctx, code, lg, team, now, sig)
local key = clean(ctx.cfg.apiKey or "", 80)
if key == "" then return false, "nokey" end
local body, err = fdGet("competitions/" .. code .. "/standings", key, 60000, KEEP_FS, SKIP_FS)
if not body then return false, err end
local at = body:find('"type":"TOTAL"', 1, true) or 1
local arr = body:match('"table":(%b[])', at)
if not arr then return false, "notab" end
local rows, id, score = {}, teamMatcher(team)
local best, bestScore = nil, 0
eachObj(arr, function(r)
local t = type(r.team) == "table" and r.team or {}
if n0(t.id) > 0 then
local nm = clean(t.shortName or "", 25)
if nm == "" then nm = clean(t.name or "", 25) end
local tla, col = crestOf(code, nm, t.name or "", clean(t.tla or "", 3))
local row = { id = n0(t.id), pos = n0(r.position) > 0 and n0(r.position) or #rows + 1, name = nm, tla = tla, col = col,
full = clean(t.name or "", 60), icon = type(t.crest) == "string" and t.crest or nil,
pl = n0(r.playedGames), w = n0(r.won), d = n0(r.draw), l = n0(r.lost), gf = n0(r.goalsFor), ga = n0(r.goalsAgainst),
pts = n0(r.points) }
rows[#rows + 1] = row
if not id then
local s = score(t.name, t.shortName)
if s > bestScore then best, bestScore = row, s end
end
end
end)
if #rows == 0 then return false, "notab" end
local own
if id then
for _, r in ipairs(rows) do if r.id == id then own = r end end
else
own = best
id = own and own.id
end
if not id then return false, "noteam" end
local ownInfo = own and { id = id, name = own.name, tla = own.tla, col = own.col, pos = own.pos, pts = own.pts, full = own.full, icon = own.icon }
or { id = id, name = "", tla = "", col = "b", pos = 0, pts = 0 }
local old = previous(ctx, sig)
local last, nxt, wn
local url = "teams/" .. id .. "/matches?dateFrom=" .. isoDay(now - 60 * 86400) .. "&dateTo=" .. isoDay(now + 90 * 86400)
local mbody = fdGet(url, key, 64000, KEEP_FM, SKIP_FM)
local marr = mbody and mbody:match('"matches":(%b[])')
if marr then
local ms = {}
eachObj(marr, function(m)
local ht, at2 = type(m.homeTeam) == "table" and m.homeTeam or {}, type(m.awayTeam) == "table" and m.awayTeam or {}
local when = parseIso(m.utcDate)
local st = tostring(m.status or "")
local fin = st == "FINISHED"
local live = st == "IN_PLAY" or st == "PAUSED"
if when and (fin or live or st == "SCHEDULED" or st == "TIMED") then
local home = n0(ht.id) == id
local opp = home and at2 or ht
local oppName = clean(opp.shortName or "", 25)
if oppName == "" then oppName = clean(opp.name or "", 25) end
local tla, col = crestOf(code, oppName, opp.name or "", clean(opp.tla or "", 3))
local sc = type(m.score) == "table" and m.score or {}
local ft = type(sc.fullTime) == "table" and sc.fullTime or {}
local gh, ga = n0(ft.home), n0(ft.away)
local gf, gaa = gh, ga
if not home then gf, gaa = ga, gh end
local res = ""
if fin then
local w = tostring(sc.winner or "")
if w == "DRAW" then res = "D"
elseif w == "HOME_TEAM" or w == "AWAY_TEAM" then res = ((w == "HOME_TEAM") == home) and "W" or "L"
else res = gf > gaa and "W" or (gf < gaa and "L" or "D") end
end
local comp = type(m.competition) == "table" and tostring(m.competition.code or "") or ""
ms[#ms + 1] = { when = when, home = home, opp = oppName, tla = tla, col = col, gf = (fin or live) and gf or 0,
oppFull = clean(opp.name or "", 60), oppIcon = type(opp.crest) == "string" and opp.crest or nil,
ga = (fin or live) and gaa or 0, fin = fin, live = live, res = res, comp = comp, stale = false }
end
end)
last, nxt, wn = pickMatches(ms, function(r) return r.comp == "" or r.comp == code end)
elseif old then
last, nxt, wn = old.last, old.nxt, old.wnext
else
last, nxt = {}, {}
end
if saveData(sig, now, ownInfo, rows, last, nxt, wn) ~= true then return false, "net" end
return true
end
function on_fetch(ctx)
EN = ctx.lang == "en"
NET = 0
D, OFF_NOW = nil, nil
if ctx.opened then
local now = time.now()
if now and now > 1700000000 then loadCrests(ctx, now) end
return true
end
local code, lg, team, sig = cfgOf(ctx)
if team == "" then return true end -- noch kein Verein gewaehlt: nichts zu holen
local now = time.now()
local ok, err
if now == nil or now < 1700000000 then
ok, err = false, "time" -- Uhr noch nicht synchron
elseif lg.o then
if lg.c then ok, err = fetchOCup(ctx, code, lg, team, now, sig) else ok, err = fetchOLeague(ctx, code, lg, team, now, sig) end
else
ok, err = fetchF(ctx, code, lg, team, now, sig)
end
if not ok then
file.write("e", err or "net")
return false
end
file.write("e", "")
ctx.data.set("t", now)
loadCrests(ctx, now) -- CHANGELOG 606: nach JEDEM Abruf (auch football-data.org), wie die eingebaute App
return true
end
function on_action(ctx, name)
EN = ctx.lang == "en"
NET = 0
local code, lg = cfgOf(ctx)
local now = time.now()
local function fail(de, en) return { ok = false, message = T(de, en) } end
if now == nil or now < 1700000000 then return fail("Uhrzeit noch nicht synchronisiert.", "Time not synced yet.") end
local list = {}
if lg.o then
local body = oGet("getavailableteams/" .. lg.o .. "/" .. seasonOf(now), 30000, { "teamId", "teamName", "shortName" })
if not body then return fail("Vereinsliste konnte nicht geladen werden.", "Club list could not be loaded.") end
ASSET = asset.read("crests") or ""
eachObj(body, function(t)
local nm = tName(t)
if n0(t.teamId) > 0 and nm ~= "" then
local known = ASSET:find("\nn|[^\n]-," .. nk(nm) .. ",") or ASSET:find("\nn|[^\n]-," .. nk(t.teamName) .. ",")
list[#list + 1] = { id = tostring(n0(t.teamId)), name = nm, known = known ~= nil }
end
end)
else
local key = clean(ctx.cfg.apiKey or "", 80)
if key == "" then return fail("Zuerst den football-data.org-API-Key eintragen.", "Enter the football-data.org API key first.") end
local body, err = fdGet("competitions/" .. code .. "/teams", key, 40000, { "id", "name", "shortName" }, { "area", "season", "competition", "filters" })
if not body then
if err == "key" then return fail("API-Key ungültig oder Liga nicht im Tarif.", "API key invalid or league not in your plan.") end
return fail("Vereinsliste konnte nicht geladen werden.", "Club list could not be loaded.")
end
local arr = body:match('"teams":(%b[])')
if arr then
eachObj(arr, function(t)
local nm = clean(t.shortName or "", 25)
if nm == "" then nm = clean(t.name or "", 25) end
if n0(t.id) > 0 and nm ~= "" then list[#list + 1] = { id = tostring(n0(t.id)), name = nm, known = true } end
end)
end
end
if #list == 0 then return fail("Die Datenquelle hat keine Vereine geliefert.", "The data source returned no clubs.") end
table.sort(list, function(a, b)
if a.known ~= b.known then return a.known end
return a.name:lower() < b.name:lower()
end)
local total, options = #list, {}
for i = 1, math.min(total, 40) do options[i] = { value = list[i].id, label = list[i].name } end
table.sort(options, function(a, b) return a.label:lower() < b.label:lower() end)
local msg = T(total .. " Vereine geladen.", total .. " clubs loaded.")
if total > 40 then msg = T("40 von " .. total .. " Vereinen angezeigt.", "Showing 40 of " .. total .. " clubs.") end
return { ok = true, message = msg, options = options }
end
local function bg(c) return c == color.YELLOW and color.BLACK or color.WHITE end
local function badge(x, y, w, h, tla, col, size)
draw.rect(x, y, w, h, col, true, math.min(h // 4, 10))
local f, off = "small", 5
if size >= 18 then f, off = "large", 9 elseif size >= 9 then f, off = "normal", 6 end
draw.text(x + w // 2, y + h // 2 + off, (tla ~= nil and tla ~= "") and tla or "?", f, bg(col), "center")
end
local function crestBig(ctx, x, y, w, h, tla, col, slot, name, size)
local iw, ih = draw.image_size(slot)
if iw and ctx.data.get("im_" .. slot) == nk(name) .. (slot == "owns" and 44 or 203) then
draw.image(slot, x + (w - iw) // 2, y + (h - ih) // 2)
return
end
badge(x, y, w, h, tla, col, size)
end
local function resColor(r)
if r == "W" then return color.GREEN elseif r == "D" then return color.YELLOW elseif r == "L" then return color.RED end
return color.BLACK
end
local function zoneColor(z)
if z == 1 then return color.BLUE elseif z == 2 then return color.GREEN elseif z == 3 then return color.RED end
return color.BLACK
end
local function hline(x, y, w, c) draw.rect(x, y, w, 1, c or color.BLACK, true) end
local function centerBounded(s, x, y, minX, maxX, font)
local w = draw.measure(s, font)
local l = x - w // 2
if l + w > maxX then l = maxX - w end
if l < minX then l = minX end
draw.text(l, y, s, font, color.BLACK, "left")
end
local function notice(icon, line1, line2)
local cx = draw.width // 2
draw.icon(icon, cx - 24, 170, 48, color.ACCENT)
draw.text(cx, 260, line1, "normal", color.BLACK, "center")
if line2 ~= nil then draw.text(cx, 290, line2, "small", color.BLACK, "center") end
end
local function noticeCompact(cx, y, glyph, text)
local r = 10
local tw = draw.measure(text, "normal")
local cluster = tw + 2 * r + 10
local ccx = cx - cluster // 2 + r
draw.circle(ccx, y, r, color.ACCENT, true)
if glyph == "..." then
for i = -1, 1 do draw.circle(ccx + i * 5, y, 1, color.WHITE, true) end
else
draw.text(ccx, y + 4, glyph, "normal", color.WHITE, "center")
end
draw.text(ccx + r + 5 + tw // 2, y + 4, text, "normal", color.BLACK, "center")
end
local ERR = {
net = { "Nächster Versuch in Kürze.", "Retrying shortly." },
tab = { "Tabellen-Abruf fehlgeschlagen.", "Standings fetch failed." },
notab = { "Keine Tabelle in der Antwort.", "No standings in response." },
mat = { "Spiele-Abruf fehlgeschlagen.", "Matches fetch failed." },
nomatch = { "Noch keine Spiele für diese Saison.", "No matches for this season yet." },
time = { "Uhrzeit noch nicht synchronisiert.", "Time not synced yet." },
noteam = { "Verein nicht gefunden (Liga gewechselt?).", "Club not found (league changed?)." },
key = { "API-Key ungültig oder Liga nicht im Tarif?", "API key invalid or league not in your plan?" },
nokey = { "Kein API-Key hinterlegt.", "No API key set." },
rate = { "Anfragelimit erreicht.", "Rate limit reached." },
}
local function emptyState(ctx, lg)
local hint = T("Einstellungen der App „Fußball-Liga“", "Settings of the “Football league” app")
if not lg.o and clean(ctx.cfg.apiKey or "", 80) == "" then
notice("gear", T("Kein football-data.org-API-Key hinterlegt.", "No football-data.org API key set."), hint)
return true
end
if clean(ctx.cfg.team or "", 60) == "" then
notice("gear", T("Noch kein Verein/Team gewählt.", "No club/team selected yet."), hint)
return true
end
local d = readData(ctx)
if not d then
local e = file.read("e")
if e and e ~= "" then
local m = ERR[e] or ERR.net
notice("warning", T("Abruf fehlgeschlagen.", "Fetch failed."), EN and m[2] or m[1])
else
notice("clock", T("Wird geladen ...", "Loading ..."))
end
return true
end
if #d.tab == 0 and not lg.c then
notice("info", T("Keine Ligadaten gefunden.", "No league data found."))
return true
end
return false
end
local function noTableNotice(lg)
if not lg.c then return false end
notice("info", T("Dieser Wettbewerb hat keine Tabelle.", "This competition has no table."),
T("Spiele siehe Seite „Team“.", "See the Team page for matches."))
return true
end
local function scoreText(m) return m.gf .. ":" .. m.ga end
local function ownOf(d) return d.own.name, d.own.tla, d.own.col end
local function teamBento(ctx, lg, d, top)
local y = top + 2
local cx = draw.width // 2
local bottom = draw.height - 14
local heroX = 20
local heroW = draw.width - 2 * heroX
local heroH = 256
draw.rect(heroX, y, heroW, heroH, color.BLACK, false, 12)
local oname, otla, ocol = ownOf(d)
local nx = d.nxt[1]
if nx then
local line = fmtDateTime(nx.when)
draw.text(cx, y + 28, T(line .. " Uhr", line), "normal", color.BLACK, "center")
local crestW, crestH = 203, 135
local crestY = y + 44
local lt, lc, ls, ln = otla, ocol, "own", cname(d.own.full, oname)
local rt, rc, rs, rn = nx.tla, nx.col, "opp", cname(nx.oppFull, nx.opp)
if not nx.home then lt, lc, ls, ln, rt, rc, rs, rn = rt, rc, rs, rn, lt, lc, ls, ln end
crestBig(ctx, cx - 150 - crestW, crestY, crestW, crestH, lt, lc, ls, ln, 18)
crestBig(ctx, cx + 150, crestY, crestW, crestH, rt, rc, rs, rn, 18)
draw.text(cx, crestY + crestH // 2 + 10, "vs", "large", color.BLACK, "center")
draw.text(cx - 150 - crestW // 2, crestY + crestH + 16, fit(ln, 280, "small"), "small", color.BLACK, "center")
draw.text(cx + 150 + crestW // 2, crestY + crestH + 16, fit(rn, 280, "small"), "small", color.BLACK, "center")
draw.text(cx, y + 205, nx.home and T("Heim", "Home") or T("Auswärts", "Away"), "small", color.BLACK, "center")
local venue = ""
if nx.home and d.own.venue ~= "" then venue = d.own.venue
elseif not nx.home then venue = T("bei ", "at ") .. nx.opp end
if venue ~= "" then draw.text(cx, y + 225, venue, "small", color.BLACK, "center") end
else
noticeCompact(cx, y + heroH // 2, "-", T("Kein anstehendes Spiel gefunden.", "No upcoming match found."))
end
local labelY = y + heroH + 22
draw.text(heroX, labelY, T("LETZTE 5 SPIELE", "LAST 5 MATCHES"), "small", color.BLACK, "left")
local tilesTop = labelY + 8
local tileH = math.min(bottom - tilesTop, 128)
if #d.last == 0 then
noticeCompact(cx, tilesTop + tileH // 2, "-", T("Noch keine Ergebnisse in dieser Saison.", "No results yet this season."))
return
end
local gap = 10
local tileW = (heroW - 4 * gap) // 5
for i = 0, #d.last - 1 do
local m = d.last[#d.last - i]
local tx = heroX + i * (tileW + gap)
local rc = resColor(m.res)
draw.rect(tx, tilesTop, tileW, tileH, rc, false, 10)
draw.circle(tx + 18, tilesTop + 19, 9, rc, true)
draw.text(tx + 18, tilesTop + 24, m.res, "small", rc == color.YELLOW and color.BLACK or color.WHITE, "center")
draw.text(tx + 32, tilesTop + 24, fit(m.opp, tileW - 40, "small"), "small", color.BLACK, "left")
draw.text(tx + tileW // 2, tilesTop + tileH // 2 + 16, scoreText(m), "large", color.BLACK, "center")
badge(tx + tileW // 2 - 21, tilesTop + tileH - 30, 42, 22, m.tla, m.col, 7)
end
end
local function teamSlate(ctx, lg, d, top)
local y = top + 6
local cx = draw.width // 2
local bottom = draw.height - 14
draw.rect(cx, y + 4, 1, bottom - y - 8, color.BLACK, true)
draw.text(24, y + 18, T("Letzte Spiele", "Last matches"), "normal", color.BLACK, "left")
draw.text(cx + 20, y + 18, T("Nächste Spiele", "Next matches"), "normal", color.BLACK, "left")
hline(24, y + 28, cx - 48)
hline(cx + 20, y + 28, cx - 44)
local listTop = y + 40
local rowH = math.min((bottom - listTop) // 5, 76)
if #d.last == 0 then
draw.text(24, listTop + 16, T("Noch keine Ergebnisse.", "No results yet."), "small", color.BLACK, "left")
end
for i = 0, #d.last - 1 do
local m = d.last[#d.last - i]
local rowY = listTop + i * rowH
local base = rowY + rowH // 2 + 6
local rc = resColor(m.res)
draw.circle(24 + 8, base - 6, 8, rc, true)
draw.text(24 + 8, base - 1, m.res, "small", rc == color.YELLOW and color.BLACK or color.WHITE, "center")
badge(24 + 26, base - 16, 36, 20, m.tla, m.col, 7)
local sc = scoreText(m)
local scoreX = cx - 22 - draw.measure(sc, "normal")
local nameX = 24 + 26 + 36 + 8
local maxW = scoreX - nameX - 10
draw.text(nameX, base, maxW > 0 and fit(m.opp, maxW, "normal") or m.opp, "normal", color.BLACK, "left")
draw.text(scoreX, base, sc, "normal", color.BLACK, "left")
if i < #d.last - 1 then hline(24, rowY + rowH - 2, cx - 48) end
end
if #d.nxt == 0 then
draw.text(cx + 20, listTop + 16, T("Keine anstehenden Spiele.", "No upcoming matches."), "small", color.BLACK, "left")
end
for i, m in ipairs(d.nxt) do
local rowY = listTop + (i - 1) * rowH
local base = rowY + rowH // 2 - 2
badge(cx + 20, base - 16, 36, 20, m.tla, m.col, 7)
local ds = fmtDate(m.when)
local dateX = draw.width - 26 - draw.measure(ds, "normal")
local nameX = cx + 20 + 36 + 8
local maxW = dateX - nameX - 10
draw.text(nameX, base, maxW > 0 and fit(m.opp, maxW, "normal") or m.opp, "normal", color.BLACK, "left")
draw.text(dateX, base, ds, "normal", color.BLACK, "left")
local p = localParts(m.when)
local ha = m.home and T("Heim", "Home") or T("Auswärts", "Away")
draw.text(nameX, base + 18, string.format(T("%02d:%02d Uhr · %s", "%02d:%02d · %s"), p.hour, p.min, ha), "small", color.BLACK, "left")
if i < #d.nxt then hline(cx + 20, rowY + rowH - 2, cx - 44) end
end
end
local function teamNano(ctx, lg, d, top)
local y = top + 4
local cx = draw.width // 2
local oname, otla, ocol = ownOf(d)
crestBig(ctx, 24, y + 2, 44, 26, otla, ocol, "owns", cname(d.own.full, oname), 9)
local head = oname
if d.own.pos > 0 then head = string.format(T("%s · Platz %d · %d Pkt", "%s · Place %d · %d pts"), oname, d.own.pos, d.own.pts) end
draw.text(24 + 44 + 12, y + 21, head, "normal", color.BLACK, "left")
local nl, nn = #d.last, #d.nxt
local count = nl + 1 + nn
if count < 2 then
noticeCompact(cx, y + 180, "-", T("Noch keine Spiele gefunden.", "No matches found yet."))
return
end
local lineY = 268
local marginX = 56
local usable = draw.width - 2 * marginX
hline(marginX, lineY, usable)
for i = 0, count - 1 do
local x = marginX + usable * i // (count - 1)
local above = i % 2 == 0
local slotW = usable // (count - 1) + 8
local inner, name, tla, col = "", "", nil, nil
if i < nl then
local m = d.last[i + 1]
draw.circle(x, lineY, 8, resColor(m.res), true)
inner, name, tla, col = scoreText(m), m.opp, m.tla, m.col
elseif i == nl then
draw.circle(x, lineY, 8, color.BLACK, true)
inner = T("heute", "today")
else
local m = d.nxt[i - nl]
draw.circle(x, lineY, 8, color.BLACK)
draw.circle(x, lineY, 7, color.BLACK)
inner, name, tla, col = fmtDate(m.when), m.opp, m.tla, m.col
end
if name ~= "" then name = fit(name, slotW, "small") end
local minX, maxX = 4, draw.width - 4
if above then
centerBounded(inner, x, lineY - 26, minX, maxX, "small")
if name ~= "" then centerBounded(name, x, lineY - 46, minX, maxX, "small") end
if tla then badge(x - 17, lineY - 84, 34, 18, tla, col, 7) end
else
centerBounded(inner, x, lineY + 32, minX, maxX, "small")
if name ~= "" then centerBounded(name, x, lineY + 52, minX, maxX, "small") end
if tla then badge(x - 17, lineY + 64, 34, 18, tla, col, 7) end
end
end
end
local function zoneOf(lg, n, pos)
local z1, z2, rel = lg.z[1], lg.z[2], lg.z[3]
if n == 0 or (z1 == 0 and z2 == 0 and rel == 0) then return 0 end
if pos <= z1 then return 1 end
if pos <= z1 + z2 then return 2 end
if pos > n - rel then return 3 end
return 0
end
local function zoneLabel(lg, z)
if z == 1 then return lg.l1 and (EN and lg.l1[2] or lg.l1[1]) or "" end
if z == 2 then return lg.l2 and (EN and lg.l2[2] or lg.l2[1]) or "" end
if z == 3 then return T("Abstieg", "Relegation") end
return ""
end
local function windowStart(d, maxRows)
local n = #d.tab
if n <= maxRows then return 0 end
local own = -1
for i, r in ipairs(d.tab) do if r.id == d.own.id then own = i - 1; break end end
if own < 0 or own < maxRows then return 0 end
local start = own - maxRows // 2
if start + maxRows > n then start = n - maxRows end
if start < 0 then start = 0 end
return start
end
local function tableCols(d, font)
local right = draw.width - 24
local dW = draw.measure("88", font)
local toreW = dW
for _, r in ipairs(d.tab) do toreW = math.max(toreW, draw.measure(r.gf .. ":" .. r.ga, font)) end
local c = {}
c.pkt = right
c.tore = c.pkt - draw.measure("888", font) - 26
c.n = c.tore - toreW - 24
c.u = c.n - dW - 12
c.s = c.u - dW - 12
c.nameRight = c.s - dW - 16
return c
end
local function headerRow(c, base)
draw.text(c.s, base, T("S", "W"), "small", color.BLACK, "right")
draw.text(c.u, base, T("U", "D"), "small", color.BLACK, "right")
draw.text(c.n, base, T("N", "L"), "small", color.BLACK, "right")
draw.text(c.tore, base, T("TORE", "GOALS"), "small", color.BLACK, "right")
draw.text(c.pkt, base, T("PKT", "PTS"), "small", color.BLACK, "right")
end
local function rowNumbers(r, c, base, font)
draw.text(c.s, base, tostring(r.w), font, color.BLACK, "right")
draw.text(c.u, base, tostring(r.d), font, color.BLACK, "right")
draw.text(c.n, base, tostring(r.l), font, color.BLACK, "right")
draw.text(c.tore, base, r.gf .. ":" .. r.ga, font, color.BLACK, "right")
draw.text(c.pkt, base, tostring(r.pts), font, color.BLACK, "right")
end
local function windowHint(d, cx, y, start, shown)
if start == 0 and shown >= #d.tab then return end
draw.text(cx, y, string.format(T("Plätze %d-%d von %d", "Places %d-%d of %d"), start + 1, start + shown, #d.tab), "small", color.BLACK, "center")
end
local function tableBento(ctx, lg, d, top)
if noTableNotice(lg) then return end
local y = top + 2
local cx = draw.width // 2
local bottom = draw.height - 14
local c = tableCols(d, "normal")
headerRow(c, y + 12)
y = y + 20
local rowH, labelH = 26, 20
local maxRows = math.max(1, (bottom - y - 3 * labelH) // rowH)
local start = windowStart(d, maxRows)
local shown = math.min(#d.tab - start, maxRows)
local prev, yy = -1, y
for i = 1, shown do
local r = d.tab[start + i]
local z = zoneOf(lg, #d.tab, r.pos)
if z ~= prev and z ~= 0 then
draw.text(24, yy + 13, zoneLabel(lg, z), "small", zoneColor(z), "left")
yy = yy + labelH
end
prev = z
local base = yy + rowH // 2 + 6
if r.id == d.own.id then draw.rect(16, yy, draw.width - 32, rowH, color.BLACK, false, 8) end
draw.text(52, base, r.pos .. ".", "normal", color.BLACK, "right")
badge(60, base - 16, 36, 20, r.tla, r.col, 7)
local nameX = 60 + 36 + 10
draw.text(nameX, base, fit(r.name, c.nameRight - nameX, "normal"), "normal", color.BLACK, "left")
rowNumbers(r, c, base, "normal")
yy = yy + rowH
end
windowHint(d, cx, yy + 12, start, shown)
end
local function tableSlate(ctx, lg, d, top)
if noTableNotice(lg) then return end
local y = top + 4
local cx = draw.width // 2
local bottom = draw.height - 12
local c = tableCols(d, "normal")
headerRow(c, y + 12)
y = y + 18
local availH = bottom - y - 20
local maxRows = math.max(1, availH // 20)
local start = windowStart(d, maxRows)
local shown = math.min(#d.tab - start, maxRows)
local rowH = math.min(availH // math.max(shown, 1), 26)
for i = 1, shown do
local r = d.tab[start + i]
local rowY = y + (i - 1) * rowH
local base = rowY + rowH // 2 + 6
local z = zoneOf(lg, #d.tab, r.pos)
if z ~= 0 then draw.rect(16, rowY + 3, 5, rowH - 6, zoneColor(z), true, 2) end
if r.id == d.own.id then draw.rect(26, rowY, draw.width - 42, rowH, color.BLACK, false, 6) end
draw.text(58, base, r.pos .. ".", "normal", color.BLACK, "right")
badge(66, base - 15, 34, 19, r.tla, r.col, 7)
local nameX = 66 + 34 + 10
draw.text(nameX, base, fit(r.name, c.nameRight - nameX, "normal"), "normal", color.BLACK, "left")
rowNumbers(r, c, base, "normal")
end
local legendY = y + shown * rowH + 12
local lx = 24
for z = 1, 3 do
local label = zoneLabel(lg, z)
if label ~= "" then
draw.circle(lx + 5, legendY - 4, 5, zoneColor(z), true)
draw.text(lx + 15, legendY, label, "small", color.BLACK, "left")
lx = lx + 15 + draw.measure(label, "small") + 24
end
end
windowHint(d, cx, legendY, start, shown)
end
local function tableNano(ctx, lg, d, top)
if noTableNotice(lg) then return end
local y = top + 2
local cx = draw.width // 2
local bottom = draw.height - 10
local c = tableCols(d, "small")
headerRow(c, y + 11)
y = y + 16
local availH = bottom - y
local maxRows = math.max(1, availH // 16)
local start = windowStart(d, maxRows)
local shown = math.min(#d.tab - start, maxRows)
local rowH = math.min(availH // math.max(shown, 1), 24)
for i = 1, shown do
local r = d.tab[start + i]
local rowY = y + (i - 1) * rowH
local base = rowY + rowH // 2 + 5
if r.id == d.own.id then draw.rect(14, rowY, draw.width - 28, rowH, color.BLACK, false, 5) end
draw.text(40, base, tostring(r.pos), "small", color.BLACK, "right")
local chipH = math.max(12, math.min(rowH - 3, 18))
badge(48, rowY + (rowH - chipH) // 2, 34, chipH, r.tla, r.col, 7)
local nameX = 48 + 34 + 8
draw.text(nameX, base, fit(r.name, c.nameRight - nameX, "small"), "small", color.BLACK, "left")
rowNumbers(r, c, base, "small")
if i < shown then hline(20, rowY + rowH - 1, draw.width - 40) end
end
windowHint(d, cx, y + shown * rowH + 10, start, shown)
end
function on_draw(ctx, page)
EN = ctx.lang == "en"
D, OFF_NOW = nil, nil
draw.clear(color.WHITE)
local p = page or 1
if tonumber(ctx.cfg.page) then p = tonumber(ctx.cfg.page) + 1 end
local code, lg = cfgOf(ctx)
if emptyState(ctx, lg) then return end
local d = readData(ctx)
local style = ctx.cfg.style
local top = draw.top
if p == 2 then
if style == "flat" then tableSlate(ctx, lg, d, top) elseif style == "compact" then tableNano(ctx, lg, d, top) else tableBento(ctx, lg, d, top) end
else
if style == "flat" then teamSlate(ctx, lg, d, top) elseif style == "compact" then teamNano(ctx, lg, d, top) else teamBento(ctx, lg, d, top) end
local ie = ctx.data.get("ie")
if type(ie) ~= "string" or ie == "" then ie = T("noch kein Wappenabruf", "no crest fetch yet") end
if ctx.cfg.crests ~= false and style ~= "flat" and (ctx.data.get("im_own") == nil or ctx.data.get("im_opp") == nil) then
draw.text(790, 474, "Wappen: " .. ie, "small", color.BLACK, "right")
end
end
end
local function sampleData()
local t = time.now() or 1790000000
return { own = { name = "FC Bayern München", tla = "FCB", col = color.RED, pos = 2, pts = 13, id = 0, venue = "" }, tab = {}, last = {},
nxt = {}, wnext = { when = t + 3 * 86400 + 4 * 3600, home = true, opp = "Borussia Dortmund", tla = "BVB", col = color.YELLOW,
gf = 0, ga = 0, res = "", live = false } }
end
function on_widget(ctx, box)
EN = ctx.lang == "en"
D, OFF_NOW = nil, nil
local d = readData(ctx)
if not d and ctx.sample then d = sampleData() end
local m = d and (d.wnext or d.nxt[1])
if not m then
draw.text(box.x + 12, box.y + 16, T("Noch keine Daten", "No data yet"), "small", color.BLACK, "left")
return
end
local compact = ctx.cfg.wCompact == true
local withHA = ctx.cfg.wHomeAway == true
local withPos = ctx.cfg.wTablePos == true
local top = box.y
local maxY = box.y + box.h - 4
local areaH = maxY - top
local cx = box.x + box.w // 2
local crestH = compact and 22 or (areaH >= 110 and 40 or (areaH >= 80 and 32 or 24))
local crestW = crestH * 3 // 2
local vsGap = compact and 18 or 22
local crestY = top + 4
local leftX = cx - crestW - vsGap // 2
local rightX = cx + vsGap // 2
local cf = compact and 7 or 9
local own = d.own
local lt, lc, rt, rc = own.tla, own.col, m.tla, m.col
if not m.home then lt, lc, rt, rc = rt, rc, lt, lc end
local function wbadge(x, tla, col, slot, name)
if ctx.cfg.crests ~= false then
local key = nk(name)
local big = slot == "wown" and "own" or "opp"
for _, c in ipairs({ { slot, key .. 60 }, { big, key .. 203 }, { "owns", key .. 44 } }) do
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
badge(x, crestY, crestW, crestH, tla, col, cf)
end
local ln, rn, ls, rs = cname(own.full, own.name), cname(m.oppFull, m.opp), "wown", "wopp"
if not m.home then ln, rn, ls, rs = rn, ln, rs, ls end
wbadge(leftX, lt, lc, ls, ln)
wbadge(rightX, rt, rc, rs, rn)
draw.text(cx, crestY + crestH // 2 + 4, "vs", "small", color.BLACK, "center")
local lineY = crestY + crestH + (compact and 16 or 22)
if lineY > maxY then return end
local font = "normal"
if (box.font or 0) < 0 then font = "small" elseif (box.font or 0) > 0 then font = "medium" end
if m.live then
local hg, ag = m.home and m.gf or m.ga, m.home and m.ga or m.gf
local s = string.format("LIVE  %d:%d", hg, ag)
local w = draw.measure(s, font)
local tx = cx + 6
draw.circle(tx - w // 2 - 8, lineY - 5, 4, color.RED, true)
draw.text(tx, lineY, s, font, color.RED, "center")
else
local p = localParts(m.when)
local ds = fmtDate(m.when)
local s = ds .. string.format(" %02d:%02d", p.hour, p.min)
if withHA then s = (m.home and T("Heim", "Home") or T("Auswärts", "Away")) .. " · " .. s end
draw.text(cx, lineY, fit(s, box.w - 16, font), font, color.ACCENT_TEXT, "center")
end
if withPos and own.pos > 0 then
local posY = lineY + (compact and 14 or 17)
if posY <= maxY then
draw.text(cx, posY, string.format(T("Platz %d · %d Pkt.", "Rank %d · %d pts"), own.pos, own.pts), "small", color.BLACK, "center")
end
end
end
