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
local function dfc(y, m, d)
if m <= 2 then y = y - 1 end
local era = y // 400
local yoe = y - era * 400
local doy = (153 * ((m + 9) % 12) + 2) // 5 + d - 1
return era * 146097 + yoe * 365 + yoe // 4 - yoe // 100 + doy - 719468
end
local function parseIso(s)
if type(s) ~= "string" then return nil end
local y, m, d, hh, mi, ss, rest = s:match("(%d%d%d%d)%-(%d%d)%-(%d%d)[T ](%d%d):(%d%d):?(%d*)(.*)")
if y == nil then return nil end
local off = 0
local sg, zh, zm = rest:match("([+-])(%d%d):?(%d%d)")
if sg then off = (tonumber(zh) * 3600 + tonumber(zm) * 60) * (sg == "-" and -1 or 1) end
return dfc(tonumber(y), tonumber(m), tonumber(d)) * 86400 + tonumber(hh) * 3600 + tonumber(mi) * 60 + (tonumber(ss) or 0) - off
end
local function notice(icon, l1, l2)
draw.icon(icon, draw.width // 2 - 24, 170, 48, color.ACCENT)
draw.text(draw.width // 2, 260, l1, "normal", color.BLACK, "center")
if l2 ~= nil then draw.text(draw.width // 2, 290, l2, "small", color.BLACK, "center") end
end
local HVV = "https://gti.geofox.de/gti/public/"
local DBR = "https://v6.db.transport.rest/"
local TRS = "https://api.transitous.org/api/"
local MAXDEP, MAXRES, MAXLEGS, NROUTES = 12, 3, 6, 6
local RES = MAXRES -- Verbindungen je Route; ist nur eine Route aktiv, 6 (Einzel-Ansicht "naechste 10 Minuten")
local SUB, SUBWAY, OTHER = 0, 1, 2
local MODECOL = { [0] = color.GREEN, color.RED, color.BLUE }
local PK = { hvv = "h", transitous = "t", db = "d" }
local MX = 24 -- Seitenrand (TRANSIT_MARGIN_X)
local NET = 0
local WROTE = {} -- in diesem Abruf geschriebene Dateien (fuer die Pruefsumme "v", spart Dateizugriffe)
local OFF = 0 -- Abstand Ortszeit - UTC in Sekunden
local function n0(v) return tonumber(v) or 0 end
local function s0(v) if v == nil then return "" end return tostring(v) end
local function on(v) return v == true or v == "true" or v == 1 or v == "1" end
local function split(line)
local out = {}
for f in (line .. "\t"):gmatch("([^\t]*)\t") do out[#out + 1] = f end
return out
end
local function tf(s, n) return clean(s0(s), n or 48) end
local function cutBytes(s, n)
if #s <= n then return s end
s = s:sub(1, n)
while #s > 0 and (s:byte(#s) & 0xC0) == 0x80 do s = s:sub(1, #s - 1) end
if #s > 0 and s:byte(#s) >= 0xC0 then s = s:sub(1, #s - 1) end
return s
end
local function js(s)
s = s0(s):gsub('[%c"\\]', function(c)
if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" end
return string.format("\\u%04x", c:byte())
end)
return '"' .. s .. '"'
end
local function tzOff()
local t, n = time.localtime(), time.now()
if t == nil or n == nil then return 0 end
local loc = dfc(t.year, t.month, t.day) * 86400 + t.hour * 3600 + t.min * 60 + t.sec
return ((loc - n + 450) // 900) * 900
end
local function clock(e)
if e == nil or e <= 0 then return "" end
local s = (e + OFF) % 86400
return string.format("%02d:%02d", s // 3600, s % 3600 // 60)
end
local function gtiTime(t)
if type(t) ~= "table" then return nil end
local d, m, y = s0(t.date):match("^(%d%d)%.(%d%d)%.(%d%d%d%d)")
local hh, mi = s0(t.time):match("^(%d%d?):(%d%d)")
if d == nil or hh == nil then return nil end
return dfc(tonumber(y), tonumber(m), tonumber(d)) * 86400 + tonumber(hh) * 3600 + tonumber(mi) * 60 - OFF
end
local function short(s) return (s0(s):match("^([^,]*)") or "") end
local function walkMin(ctx) local w = math.floor(n0(ctx.cfg.walk)); if w < 0 then w = 0 elseif w > 60 then w = 60 end return w end
local WALK, NOW = 0, 0
local function leave(when)
if WALK <= 0 then return when end
local l = when - WALK * 60
if l < NOW then return NOW end
return l
end
local function minsTo(e) local m = (e - NOW) // 60; if m < 0 then m = 0 end return m end
local function modeDb(p)
if p == "suburban" or p == "regional" or p == "regionalExpress" or p == "national" or p == "nationalExpress" then return SUB end
if p == "subway" then return SUBWAY end
return OTHER
end
local function modeHvv(simple, shortInfo)
if simple == "TRAIN" then return s0(shortInfo):sub(1, 1) == "U" and SUBWAY or SUB end
return OTHER
end
local function modeTr(m)
if m == "SUBWAY" or m == "METRO" then return SUBWAY end
if m == "RAIL" or m == "HIGHSPEED_RAIL" or m == "LONG_DISTANCE" or m == "NIGHT_RAIL" or m == "REGIONAL_FAST_RAIL"
or m == "REGIONAL_RAIL" or m == "SUBURBAN" then return SUB end
return OTHER
end
local function lineColor(line, mode)
line = s0(line)
local mc = MODECOL[n0(mode)] or color.BLUE
if line == "" then return mc end
local c0, d1 = line:sub(1, 1), line:sub(2, 2):match("%d") ~= nil
local p2 = line:sub(1, 2)
if c0 == "U" and d1 then
if p2 == "U1" then return color.BLUE elseif p2 == "U2" then return color.RED elseif p2 == "U3" then return color.YELLOW
elseif p2 == "U4" then return color.GREEN end
return mc
end
if c0 == "S" and d1 then
if p2 == "S1" then return color.GREEN elseif p2 == "S2" or p2 == "S5" then return color.BLUE elseif p2 == "S3" then return color.RED end
return mc
end
if line:find("AST", 1, true) or line:find("ASM", 1, true) then return color.BLACK end
if d1 and c0 == "N" then return color.BLACK end
if d1 and c0 == "E" then return color.GREEN end
if d1 and (c0 == "M" or c0 == "X") then return color.RED end
if c0:match("%d") then return color.RED end
return mc
end
local function inkOn(c) if c == color.YELLOW then return color.BLACK end return color.WHITE end
local function parseSel(raw)
raw = clean(s0(raw), 100)
local lab, p, id, la, lo = raw:match("^(.-)%s*%[(%a):(.-)@([%-%d%.]*),([%-%d%.]*)%]$")
if lab then
local sel = { label = lab, prov = p, id = id, lat = tonumber(la), lon = tonumber(lo) }
if sel.lat == 0 and sel.lon == 0 then sel.lat, sel.lon = nil, nil end
return sel
end
return { label = raw }
end
local function mkSel(prov, label, id, lat, lon)
local tail = string.format(" [%s:%s@%.5f,%.5f]", PK[prov] or "t", s0(id), n0(lat), n0(lon))
return cutBytes(clean(label, 60), math.max(10, 100 - #tail)) .. tail
end
local function slim(body)
if body:find('"realtimeSchedules":[{', 1, true) then body = body:gsub('"schedules":%b[]', '"schedules":[]') end
if not body:find('"intermediateStops":[', 1, true) and not body:find('"stopovers":[', 1, true) then return body end
for _, k in ipairs({ "intermediateStops", "stopovers" }) do
body = body:gsub('"' .. k .. '":(%b[])', function(arr)
local n, depth = 0, 0
for c in arr:gmatch("[{}]") do
if c == "{" then depth = depth + 1; if depth == 1 then n = n + 1 end else depth = depth - 1 end
end
return '"' .. k .. '":' .. n
end)
end
return body
end
local function cnt(v) if type(v) == "number" then return v end return #(v or {}) end
local function req(t)
if NET >= 6 then return nil, "budget" end
NET = NET + 1
local r, e = http.request(t)
if r == nil then return nil, "net", e end
return r
end
local function getJson(url, keep, skip, maxBytes)
local r, code = req { url = url, headers = { Accept = "application/json" }, keep = keep, skip = skip, maxBytes = maxBytes }
if not r then return nil, code end
if r.status ~= 200 then log("OePNV: HTTP " .. r.status .. " " .. url:match("^https://([^/]+)")); return nil, "net" end
local d = json.decode(slim(r.body))
if type(d) ~= "table" then return nil, "data" end
return d
end
local function hvvPost(ctx, method, body, keep, skip, maxBytes)
local u, p = clean(s0(ctx.cfg.hvvUser), 80), s0(ctx.cfg.hvvPass)
if u == "" or p == "" then return nil, "creds" end
local k = { "returnCode", "errorText", "errorDevInfo" }
for _, x in ipairs(keep or {}) do k[#k + 1] = x end
local r, code = req { url = HVV .. method, method = "POST", body = body, keep = k, skip = skip, maxBytes = maxBytes,
headers = { ["Content-Type"] = "application/json;charset=UTF-8", Accept = "application/json",
["geofox-auth-type"] = "HmacSHA1", ["geofox-auth-user"] = u, ["geofox-auth-signature"] = crypto.base64(crypto.hmac_sha1(p, body)) } }
if not r then return nil, code end
local d = json.decode(slim(r.body))
if r.status == 401 or r.status == 403 then return nil, "auth" end
if type(d) ~= "table" then log("OePNV (HVV): HTTP " .. r.status .. " bei " .. method .. ", Antwort unlesbar (" .. #r.body .. " Byte)"); return nil, r.status == 200 and "data" or "net" end
if d.returnCode ~= "OK" then
log("OePNV (HVV): returnCode=" .. s0(d.returnCode) .. " bei " .. method .. " " .. s0(d.errorDevInfo))
if s0(d.errorDevInfo):find("uthenti") then return nil, "auth" end
return nil, "fail"
end
return d
end
local function search(ctx, prov, q, places)
local out = {}
if prov == "hvv" then
local body = '{"language":"de","maxList":8,"coordinateType":"EPSG_4326","theName":{"name":' .. js(q) .. ',"type":"' .. (places and "UNKNOWN" or "STATION") .. '"}}'
local d, e = hvvPost(ctx, "checkName", body, { "name", "city", "combinedName", "id", "type", "x", "y" }, { "tariffDetails", "serviceTypes" })
if not d then return nil, e end
for _, r in ipairs(d.results or {}) do
local c = r.coordinate or {}
local lab = s0(r.combinedName); if lab == "" then lab = s0(r.name) end
if s0(r.id) ~= "" or places then out[#out + 1] = { label = lab, id = s0(r.id), lat = n0(c.y), lon = n0(c.x) } end
end
elseif prov == "db" then
local d, e = getJson(DBR .. "locations?poi=false&addresses=" .. (places and "true" or "false") .. "&fuzzy=true&results=8&query=" .. text.url_encode(q),
{ "type", "id", "name", "address", "latitude", "longitude" }, { "products" })
if not d then return nil, e end
for _, r in ipairs(d) do
local loc = r.location or r
if (r.type == "stop" or r.type == "station") and s0(r.id) ~= "" then
out[#out + 1] = { label = s0(r.name), id = s0(r.id), lat = n0(loc.latitude), lon = n0(loc.longitude) }
elseif places and r.type == "location" and r.latitude then
out[#out + 1] = { label = s0(r.address or r.name), id = "", lat = n0(r.latitude), lon = n0(r.longitude) }
end
end
else
local d, e = getJson(TRS .. "v1/geocode?text=" .. text.url_encode(q) .. (places and "" or "&type=STOP") .. "&numResults=8",
{ "type", "name", "id", "lat", "lon", "default" }, { "tokens" })
if not d then return nil, e end
for _, r in ipairs(d) do
if (r.type == "STOP" or places) and r.lat then
local lab, city = s0(r.name), nil
for _, a in ipairs(r.areas or {}) do if a.default == true then city = s0(a.name) end end
if city and city ~= "" and city ~= lab and not lab:find(city, 1, true) then lab = lab .. ", " .. city end
out[#out + 1] = { label = lab, id = r.type == "STOP" and s0(r.id) or "", lat = n0(r.lat), lon = n0(r.lon) }
end
end
end
return out
end
local CACHE, CACHE_DIRTY = nil, false
local function cacheLoad()
CACHE = {}
local raw = file.read("s") or ""
for line in raw:gmatch("[^\n]+") do
local f = split(line)
if #f >= 7 then CACHE[#CACHE + 1] = f end
end
end
local function cacheGet(prov, kind, q)
if CACHE == nil then cacheLoad() end
for _, f in ipairs(CACHE) do
if f[1] == prov and f[2] == kind and f[3] == q then return { label = f[4], id = f[5], lat = tonumber(f[6]), lon = tonumber(f[7]) } end
end
end
local function cachePut(prov, kind, q, s)
if CACHE == nil then cacheLoad() end
table.insert(CACHE, 1, { prov, kind, q, tf(s.label, 60), tf(s.id, 80), string.format("%.5f", n0(s.lat)), string.format("%.5f", n0(s.lon)) })
while #CACHE > 16 do table.remove(CACHE) end
CACHE_DIRTY = true
end
local function cacheSave()
if not CACHE_DIRTY then return end
local t = {}
for _, f in ipairs(CACHE) do t[#t + 1] = table.concat(f, "\t") end
file.write("s", table.concat(t, "\n") .. "\n")
CACHE_DIRTY = false
end
local function stopFor(ctx, prov)
local sel = parseSel(ctx.cfg.stop)
if sel.label == "" and (sel.id == nil or sel.id == "") then return nil, "nostop" end
if sel.prov == PK[prov] and s0(sel.id) ~= "" then return sel end
local q = sel.label
local c = cacheGet(prov, "S", q)
if c and c.id ~= "" then return c end
local list, e = search(ctx, prov, q, false)
if not list then return nil, e end
if #list == 0 or list[1].id == "" then return nil, "nostopfound" end
cachePut(prov, "S", q, list[1])
return list[1]
end
local function pointFor(ctx, prov, raw)
local sel = parseSel(raw)
if sel.lat and sel.lon then return sel end
if sel.label == "" then return nil, "noroute" end
local c = cacheGet(prov, "P", sel.label)
if c then return c end
local list, e = search(ctx, prov, sel.label, true)
if not list then return nil, e end
if #list == 0 then return nil, "noplace" end
cachePut(prov, "P", sel.label, list[1])
return list[1]
end
local function depsHvv(ctx, stop)
local function attempt(rt)
local body = '{"language":"de","maxList":' .. MAXDEP .. ',"station":{"id":' .. js(stop.id) .. ',"type":"STATION"},'
.. '"time":{"date":"heute","time":"jetzt"},"useRealtime":' .. (rt and "true" or "false") .. ',"departure":true,"returnFilters":true,"maxTimeOffset":120}'
local d, e = hvvPost(ctx, "departureList", body,
{ "date", "time", "name", "direction", "simpleType", "shortInfo", "timeOffset", "delay", "cancelled" },
{ "filter", "station", "serviceTypes", "attributes", "stopPoints" })
if not d then return nil, e end
local anchor = gtiTime(d.time) or NOW
local out = {}
for _, x in ipairs(d.departures or {}) do
if #out >= MAXDEP then break end
local ln = x.line or {}
local ty = ln.type or {}
if x.cancelled ~= true then
out[#out + 1] = { line = s0(ln.name ~= nil and ln.name or "?"), dest = s0(ln.direction), when = anchor + n0(x.timeOffset) * 60,
delay = math.floor(n0(x.delay) / 60), mode = modeHvv(ty.simpleType, ty.shortInfo) }
end
end
return out
end
local out, e = attempt(false)
if out and #out == 0 and NET < 6 then
log("OePNV (HVV): 0 Abfahrten ohne Echtzeit - zweiter Versuch mit useRealtime=true")
out, e = attempt(true)
end
return out, e
end
local function depsTr(ctx, stop)
local d, e = getJson(TRS .. "v6/stoptimes?stopId=" .. text.url_encode(stop.id) .. "&n=" .. MAXDEP,
{ "departure", "scheduledDeparture", "mode", "headsign", "displayName", "routeShortName", "cancelled", "tripCancelled" },
{ "tripFrom", "tripTo", "modes" }, 30000)
if not d then return nil, e end
local out = {}
for _, x in ipairs(d.stopTimes or {}) do
if #out >= MAXDEP then break end
local pl = x.place or {}
local real, plan = parseIso(pl.departure or pl.scheduledDeparture), parseIso(pl.scheduledDeparture)
if real and x.cancelled ~= true and x.tripCancelled ~= true and pl.cancelled ~= true then
local dl = 0
if plan and real > plan then dl = (real - plan) // 60 end
out[#out + 1] = { line = s0(x.displayName or x.routeShortName or "?"), dest = s0(x.headsign), when = real, delay = dl, mode = modeTr(x.mode) }
end
end
return out
end
local function depsDb(ctx, stop)
local d, e = getJson(DBR .. "stops/" .. text.url_encode(stop.id) .. "/departures?results=" .. MAXDEP .. "&duration=90",
{ "when", "plannedWhen", "delay", "direction", "name", "product", "cancelled" },
{ "stop", "remarks", "origin", "destination", "currentTripPosition", "operator", "products" })
if not d then return nil, e end
local list = d.departures or d
local out = {}
for _, x in ipairs(list) do
if #out >= MAXDEP then break end
local w = parseIso(x.when or x.plannedWhen)
local ln = x.line or {}
if w and x.cancelled ~= true then
out[#out + 1] = { line = s0(ln.name or "?"), dest = s0(x.direction), when = w, delay = math.floor(n0(x.delay) / 60), mode = modeDb(ln.product) }
end
end
return out
end
local DEPS = { hvv = depsHvv, transitous = depsTr, db = depsDb }
local function depSig(ctx, prov) return prov .. "|" .. clean(s0(ctx.cfg.stop), 100) end
local function readDeps()
local raw = file.read("d")
if raw == nil or raw == "" then return nil end
local d = { list = {} }
for line in raw:gmatch("[^\n]+") do
local f = split(line)
if f[1] == "H" then d.sig, d.at, d.prov, d.stop = f[2], n0(f[3]), f[4], f[5]
elseif f[1] == "D" and #f >= 6 then d.list[#d.list + 1] = { line = f[2], mode = n0(f[3]), dest = f[4], when = n0(f[5]), delay = n0(f[6]) } end
end
return d
end
local function fetchDeps(ctx, prov)
local stop, e = stopFor(ctx, prov)
if not stop then ctx.data.set("ed", e); return false end
local list, e2 = DEPS[prov](ctx, stop)
if not list then ctx.data.set("ed", e2); return false end
local sig = depSig(ctx, prov)
if #list == 0 then
local old = readDeps()
if old and old.sig == sig and #old.list > 0 then ctx.data.set("ed", nil); return true end
end
table.sort(list, function(a, b) return a.when < b.when end)
local t = { table.concat({ "H", sig, tostring(NOW), prov, tf(stop.label, 60) }, "\t") }
for _, x in ipairs(list) do
t[#t + 1] = table.concat({ "D", tf(x.line, 9), tostring(x.mode), tf(x.dest, 39), tostring(math.floor(x.when)), tostring(math.floor(x.delay)) }, "\t")
end
WROTE.d = table.concat(t, "\n") .. "\n"
file.write("d", WROTE.d)
ctx.data.set("ed", nil)
return true
end
local ICONS = { home = true, work = true, school = true, family = true, shopping = true, train = true, plane = true, star = true }
local function routeCfg(ctx)
local out = {}
for i = 1, NROUTES do
local from, to = clean(s0(ctx.cfg["r" .. i .. "From"]), 100), clean(s0(ctx.cfg["r" .. i .. "To"]), 100)
local icon = s0(ctx.cfg["r" .. i .. "Icon"])
if not ICONS[icon] then icon = "" end
out[i] = { idx = i, name = clean(s0(ctx.cfg["r" .. i .. "Name"]), 24), from = from, to = to, icon = icon,
enabled = from ~= "" and to ~= "", toLabel = parseSel(to).label }
if out[i].name == "" and icon == "" then out[i].name = T("Route ", "Route ") .. i end
end
return out
end
local function routeSig(ctx, prov, r) return prov .. "|" .. r.from .. "|" .. r.to .. "|" .. (walkMin(ctx) > 0 and "w" or "") end
local function finalize(c, originLabel, toLabel)
for _, l in ipairs(c.legs) do if l.t == "T" and l.line == "" then l.t = "W" end end
if #c.legs == 0 then return end
local function ph(n) return n == "" or n == "END" or n == "START" or n == "UNKNOWN" end
if c.legs[1].t == "W" then c.legs[1].origin = short(originLabel) end
if c.legs[#c.legs].t == "W" then c.dest = short(toLabel) end
if ph(c.dest) then c.dest = short(toLabel) end
if ph(c.legs[1].origin) then c.legs[1].origin = short(originLabel) end
end
local function conn(when, arr, delay, dest, plat, legsIn, disrupt, dtext)
local c = { when = when, arr = arr or 0, delay = delay or 0, xfer = 0, dis = disrupt and 1 or 0, dtext = dtext or "", dest = dest or "", plat = plat or "", legs = {} }
local hasT, all = false, {}
for i, l in ipairs(legsIn) do
local dur = 0
if l.dep and l.arr and l.arr > l.dep then dur = (l.arr - l.dep) // 60 end
if l.walk and i > 1 and i < #legsIn then c.xfer = c.xfer + dur end
local prev = all[#all]
if l.walk and prev and prev.t == "W" then
prev.dur = prev.dur + dur
if prev.dep == 0 then prev.dep = l.dep or 0 end
else
all[#all + 1] = { t = l.walk and "W" or "T", line = l.walk and "" or s0(l.line), mode = l.walk and OTHER or l.mode,
origin = s0(l.origin), dep = l.dep or 0, plat = s0(l.plat), dur = dur, stops = l.walk and 0 or (l.stops or 0) }
end
if not l.walk then hasT = true end
if l.arr and l.arr > c.arr then c.arr = l.arr end
end
if not hasT then return nil end
for k = 1, #all do
if k < MAXLEGS or k == #all then c.legs[#c.legs + 1] = all[k] end
end
return c
end
local function routeHvv(ctx, o, d)
local body = '{"language":"de","coordinateType":"EPSG_4326","start":{"name":' .. js(o.label) .. ',"type":"COORDINATE","coordinate":{"x":'
.. string.format("%.6f", o.lon) .. ',"y":' .. string.format("%.6f", o.lat) .. '}},"dest":{"name":' .. js(d.label)
.. ',"type":"COORDINATE","coordinate":{"x":' .. string.format("%.6f", d.lon) .. ',"y":' .. string.format("%.6f", d.lat)
.. '}},"time":{"date":"heute","time":"jetzt"},"timeIsDeparture":true,"numberOfSchedules":' .. RES
.. ',"realtime":"AUTO","intermediateStops":true}'
local r, e = hvvPost(ctx, "getRoute", body,
{ "plannedDepartureTime", "realDepartureTime", "plannedArrivalTime", "realArrivalTime", "name", "simpleType", "shortInfo",
"platform", "realtimePlatform", "date", "time" },
{ "paths", "path", "attributes", "tariffInfos", "coordinate", "serviceTypes", "ticketInfos", "extraInfos", "individualRoute", "tariffDetails" }, 64000)
if not r then return nil, e end
local scheds = r.realtimeSchedules
if type(scheds) ~= "table" or #scheds == 0 then scheds = r.schedules end
local out = {}
for _, s in ipairs(scheds or {}) do
if #out >= RES then break end
local plan = parseIso(s.plannedDepartureTime)
local dep = parseIso(s.realDepartureTime) or plan
if dep then
local delay = 0
if plan and dep > plan then delay = (dep - plan) // 60 end
local arr = parseIso(s.realArrivalTime) or parseIso(s.plannedArrivalTime)
local legs, lastTo = {}, ""
for _, el in ipairs(s.scheduleElements or {}) do
local ln, f, t = el.line, el.from or {}, el.to or {}
local lname = type(ln) == "table" and s0(ln.name) or ""
local ty = type(ln) == "table" and (ln.type or {}) or {}
local st = s0(ty.simpleType)
local walk = type(ln) ~= "table" or st == "FOOTPATH" or st == "CHANGE" or st == "CHANGE_SAME_PLATFORM" or lname:find("Fu\195\159weg", 1, true) ~= nil or lname:find("Fussweg", 1, true) ~= nil
legs[#legs + 1] = { walk = walk, line = lname, mode = modeHvv(ty.simpleType, ty.shortInfo), origin = f.name, dep = gtiTime(f.depTime),
arr = gtiTime(t.arrTime), plat = f.realtimePlatform or f.platform, stops = cnt(el.intermediateStops) }
lastTo = s0(t.name)
end
local destName = (type(s.dest) == "table" and s0(s.dest.name)) or ""
if destName == "" then destName = lastTo end
local c = conn(dep, arr, delay, destName, "", legs)
if c then out[#out + 1] = c end
end
end
return out
end
local function routeTr(ctx, o, d)
local url = TRS .. "v6/plan?fromPlace=" .. text.url_encode(string.format("%.6f,%.6f", o.lat, o.lon)) .. "&toPlace="
.. text.url_encode(string.format("%.6f,%.6f", d.lat, d.lon)) .. "&numItineraries=" .. RES .. "&detailedLegs=false"
local r, e = getJson(url, { "startTime", "scheduledStartTime", "endTime", "scheduledEndTime", "displayName", "routeShortName", "mode",
"name", "track", "headerText", "description" },
{ "legGeometry", "steps", "fareTransfers", "requestParameters", "debugOutput", "direct", "rental", "modes", "tokens" }, 60000)
if not r then return nil, e end
local out = {}
for _, it in ipairs(r.itineraries or {}) do
if #out >= RES then break end
local legsJ = it.legs or {}
local first = legsJ[1]
if first then
local dep = parseIso(first.startTime or first.scheduledStartTime)
local plan = parseIso(first.scheduledStartTime)
if dep then
local delay = 0
if plan and dep > plan then delay = (dep - plan) // 60 end
local arr = parseIso(it.endTime or it.scheduledEndTime)
local legs, dis, dtext = {}, false, ""
for _, l in ipairs(legsJ) do
if not dis and type(l.alerts) == "table" and #l.alerts > 0 then
dis = true
dtext = s0(l.alerts[1].headerText or l.alerts[1].description)
end
local nm = s0(l.displayName or l.routeShortName)
local walk = l.mode == "WALK" or nm == ""
local fr = l.from or {}
legs[#legs + 1] = { walk = walk, line = nm, mode = modeTr(l.mode), origin = fr.name, dep = parseIso(l.startTime or l.scheduledStartTime),
arr = parseIso(l.endTime or l.scheduledEndTime), plat = fr.track, stops = cnt(l.intermediateStops) }
end
local last = legsJ[#legsJ]
local lt = last.to or {}
local c = conn(dep, arr, delay, lt.name, lt.track, legs, dis, dtext)
if c then out[#out + 1] = c end
end
end
end
return out
end
local function routeDb(ctx, o, d)
local url = DBR .. "journeys?from.latitude=" .. string.format("%.6f", o.lat) .. "&from.longitude=" .. string.format("%.6f", o.lon)
.. "&from.address=" .. text.url_encode(o.label) .. "&to.latitude=" .. string.format("%.6f", d.lat) .. "&to.longitude="
.. string.format("%.6f", d.lon) .. "&to.address=" .. text.url_encode(d.label) .. "&results=" .. RES .. "&stopovers=true"
local r, e = getJson(url, { "departure", "plannedDeparture", "departureDelay", "arrival", "plannedArrival", "walking", "departurePlatform",
"plannedDeparturePlatform", "arrivalPlatform", "plannedArrivalPlatform", "name", "product", "type", "text", "summary" },
{ "polyline", "tickets", "price", "refreshToken", "location", "products", "stop", "cycle", "alternatives", "scheduledDays", "operator" }, 60000)
if not r then return nil, e end
local out = {}
for _, j in ipairs(r.journeys or {}) do
if #out >= RES then break end
local legsJ = j.legs or {}
local first, last = legsJ[1], legsJ[#legsJ]
local dep = first and parseIso(first.departure or first.plannedDeparture)
if dep then
local arr = parseIso(last.arrival or last.plannedArrival)
local legs, dis, dtext = {}, false, ""
for _, l in ipairs(legsJ) do
if not dis then
for _, rm in ipairs(l.remarks or {}) do
if rm.type == "warning" then dis = true; dtext = s0(rm.text or rm.summary); break end
end
end
local ln = l.line
local walk = l.walking == true or type(ln) ~= "table"
legs[#legs + 1] = { walk = walk, line = type(ln) == "table" and s0(ln.name) or "", mode = type(ln) == "table" and modeDb(ln.product) or OTHER,
origin = type(l.origin) == "table" and l.origin.name or "", dep = parseIso(l.departure or l.plannedDeparture),
arr = parseIso(l.arrival or l.plannedArrival), plat = l.departurePlatform or l.plannedDeparturePlatform, stops = cnt(l.stopovers) }
end
local c = conn(dep, arr, math.floor(n0(first.departureDelay) / 60), type(last.destination) == "table" and last.destination.name or "",
last.arrivalPlatform or last.plannedArrivalPlatform, legs, dis, dtext)
if c then out[#out + 1] = c end
end
end
return out
end
local ROUTE = { hvv = routeHvv, transitous = routeTr, db = routeDb }
local function readRoutes()
local res = {}
local raw = file.read("r") or ""
local cur, cc
for line in raw:gmatch("[^\n]+") do
local f = split(line)
if f[1] == "R" then
cur = { idx = n0(f[2]), sig = f[3], at = n0(f[4]), err = f[5] or "", conns = {} }
res[cur.idx] = cur
cc = nil
elseif f[1] == "C" and cur then
cc = { when = n0(f[2]), arr = n0(f[3]), delay = n0(f[4]), xfer = n0(f[5]), dis = n0(f[6]), dtext = f[7] or "", dest = f[8] or "", plat = f[9] or "", legs = {} }
cur.conns[#cur.conns + 1] = cc
elseif f[1] == "L" and cc then
cc.legs[#cc.legs + 1] = { t = f[2], line = f[3], mode = n0(f[4]), origin = f[5] or "", dep = n0(f[6]), plat = f[7] or "", dur = n0(f[8]), stops = n0(f[9]) }
end
end
return res
end
local function writeRoutes(res)
local t = {}
for i = 1, NROUTES do
local r = res[i]
if r then
t[#t + 1] = table.concat({ "R", tostring(i), r.sig, tostring(r.at), r.err or "" }, "\t")
for _, c in ipairs(r.conns) do
t[#t + 1] = table.concat({ "C", tostring(math.floor(c.when)), tostring(math.floor(c.arr)), tostring(math.floor(c.delay)), tostring(c.xfer), tostring(c.dis),
tf(c.dtext, 47), tf(c.dest, 23), tf(c.plat, 7) }, "\t")
for _, l in ipairs(c.legs) do
t[#t + 1] = table.concat({ "L", l.t, tf(l.line, 9), tostring(l.mode), tf(l.origin, 23), tostring(math.floor(l.dep)), tf(l.plat, 7),
tostring(math.floor(l.dur)), tostring(math.floor(l.stops)) }, "\t")
end
end
end
end
WROTE.r = #t > 0 and (table.concat(t, "\n") .. "\n") or ""
file.write("r", WROTE.r)
end
local function fetchRoutes(ctx, prov)
local cfg = routeCfg(ctx)
local res = readRoutes()
local act = {}
for i = 1, NROUTES do
if cfg[i].enabled then
local old, sig = res[i], routeSig(ctx, prov, cfg[i])
local age = 0
if old and old.sig == sig then
local fut = false
for _, c in ipairs(old.conns) do if c.when >= NOW + 60 then fut = true end end
age = fut and old.at or 0
end
act[#act + 1] = { i = i, age = age }
end
end
if #act == 0 then return false end
RES = #act == 1 and 6 or MAXRES
table.sort(act, function(a, b) if a.age ~= b.age then return a.age < b.age end return a.i < b.i end)
local origin
if walkMin(ctx) > 0 then
local loc = weather.location()
if loc and loc.lat then origin = { label = s0(loc.name), lat = n0(loc.lat), lon = n0(loc.lon) } end
end
local ok = false
for _, a in ipairs(act) do
if NET >= 6 then break end
local i = a.i
local r = cfg[i]
local sig = routeSig(ctx, prov, r)
local o, e = origin, nil
if not o then o, e = pointFor(ctx, prov, r.from) end
local d
if o then d, e = pointFor(ctx, prov, r.to) end
local conns
if o and d then conns, e = ROUTE[prov](ctx, o, d) end
if e == "budget" then break end
local old = res[i]
if old and old.sig ~= sig then old = nil end
if conns and #conns > 0 then
for _, c in ipairs(conns) do finalize(c, o.label, d.label) end
res[i] = { sig = sig, at = NOW, err = "", conns = conns }
ok = true
else
e = conns and "none" or (e or "fail")
log("OePNV: Route " .. i .. " ohne neue Verbindungen (" .. e .. ")" .. (old and #old.conns > 0 and ", alte bleiben" or ""))
if old then old.err = e else res[i] = { sig = sig, at = 0, err = e, conns = {} } end
end
end
for i = 1, NROUTES do if not cfg[i].enabled then res[i] = nil end end
writeRoutes(res)
return ok
end
local function provOf(ctx)
local p = s0(ctx.cfg.provider)
if p ~= "hvv" and p ~= "db" and p ~= "transitous" then p = "transitous" end
return p
end
function on_fetch(ctx)
EN = ctx.lang == "en"
OFF, NOW, NET, WALK = tzOff(), time.now() or 0, 0, walkMin(ctx)
CACHE, CACHE_DIRTY, WROTE = nil, false, {}
local prov = provOf(ctx)
local wantD, wantR = true, true
if ctx.view == "dashboard" then
wantD, wantR = false, false
for _, o in ipairs(ctx.widgets or {}) do
if (math.floor(n0(o)) & 8) ~= 0 then wantR = true else wantD = true end
end
end
local ok = false
if wantD then ok = fetchDeps(ctx, prov) or ok end
if wantR then ok = fetchRoutes(ctx, prov) or ok end
cacheSave()
local h = 7
for _, f in ipairs({ "d", "r" }) do
local t = ("\n" .. (WROTE[f] or file.read(f) or "")):gsub("(\nH\t[^\t\n]*\t)%d+", "%1"):gsub("(\nR\t%d+\t[^\t\n]*\t)%d+", "%1")
for k = 1, #t, 3 do h = (h * 31 + t:byte(k)) % 8388593 end
h = (h * 31 + #t) % 8388593
end
ctx.data.set("v", h)
if ok then log("OePNV (" .. prov .. "): aktualisiert, " .. NET .. " Abruf(e)") end
return ok
end
local ERRS = {
creds = { "HVV-Zugangsdaten fehlen.", "HVV access data missing." },
auth = { "HVV-Zugangsdaten ungültig.", "HVV access data invalid." },
nostop = { "Keine Haltestelle eingerichtet.", "No stop configured." },
nostopfound = { "Haltestelle nicht gefunden.", "Stop not found." },
noplace = { "Start oder Ziel nicht gefunden.", "Start or destination not found." },
fail = { "Der Anbieter meldet einen Fehler.", "The provider reports an error." },
data = { "Antwort des Anbieters unlesbar.", "Provider response unreadable." },
net = { "Abruf fehlgeschlagen.", "Fetch failed." },
budget = { "Abruf fehlgeschlagen.", "Fetch failed." },
}
local function errText(code) local e = ERRS[code] or ERRS.net; return T(e[1], e[2]) end
function on_action(ctx, name)
EN = ctx.lang == "en"
OFF, NOW, NET = tzOff(), time.now() or 0, 0
local prov = provOf(ctx)
local function fail(code) return { ok = false, message = errText(code) } end
if name == "hvv_check" then
if prov ~= "hvv" then return { ok = false, message = T("Zuerst den Anbieter HVV wählen und speichern.", "Choose and save the HVV provider first.") } end
local d, e = hvvPost(ctx, "init", '{"language":"de"}', { "beginOfService", "endOfService", "dataId" })
if not d then return fail(e) end
return { ok = true, message = T("Zugang in Ordnung", "Access OK") .. (d.dataId and (" (" .. T("Fahrplan ", "timetable ") .. s0(d.dataId) .. ")") or "") }
end
local field
if name == "find_stop" then field = "stop" else
local i, part = name:match("^find_r(%d)(%a+)$")
if i and (part == "from" or part == "to") then field = "r" .. i .. (part == "from" and "From" or "To") end
end
if field == nil then return { ok = false, message = T("Unbekannte Aktion.", "Unknown action.") } end
local q = parseSel(ctx.cfg[field]).label
if q == "" then return { ok = false, message = T("Zuerst einen Namen eintippen.", "Type a name first.") } end
local list, e = search(ctx, prov, q, field ~= "stop")
if not list then return fail(e) end
local opts = {}
for _, s in ipairs(list) do
if field ~= "stop" or s.id ~= "" then opts[#opts + 1] = { value = mkSel(prov, s.label, s.id, s.lat, s.lon), label = cutBytes(clean(s.label, 90), 96) } end
end
if #opts == 0 then return { ok = false, message = T("Nichts gefunden.", "Nothing found.") } end
return { ok = true, message = T(#opts .. " Treffer - bitte wählen.", #opts .. " matches - please choose."), options = opts }
end
local function thickRR(x, y, w, h, r, c)
draw.rect(x, y, w, h, c, false, r)
draw.rect(x + 1, y + 1, w - 2, h - 2, c, false, math.max(r - 1, 0))
end
local function thickLine(x0, y0, x1, y1, c)
draw.line(x0, y0, x1, y1, c); draw.line(x0 + 1, y0, x1 + 1, y1, c); draw.line(x0, y0 + 1, x1, y1 + 1, c)
end
local function hline(x, y, w, c) draw.rect(x, y, w, 1, c or color.BLACK, true) end
local function vline(x, y, h, c) draw.rect(x, y, 1, h, c or color.BLACK, true) end
local function textR(x, y, s, f, c) draw.text(x, y, s, f, c or color.BLACK, "right") end
local function textC(x, y, s, f, c) draw.text(x, y, s, f, c or color.BLACK, "center") end
local function textCB(cx, y, s, f, lo, hi, c)
local w = draw.measure(s, f)
local x = cx - w // 2
if x + w > hi then x = hi - w end
if x < lo then x = lo end
draw.text(x, y, s, f, c or color.BLACK)
end
local function badge(x, y, line, mode, big)
local w, h = big and 46 or 32, big and 26 or 20
local c = lineColor(line, mode)
draw.rect(x, y, w, h, c, true, 5)
local f = big and "normal" or "small"
textCB(x + w // 2, y + h - (big and 8 or 6), fit(s0(line), w - 4, f), f, x + 1, x + w - 1, inkOn(c))
end
local function walkIcon(x, y, s)
local hr = math.floor(s * 0.2)
local cx = x + s // 2
local hy = y + hr
draw.circle(cx, hy, hr, color.BLACK, true)
local hipX, hipY = cx - math.floor(s * 0.06), y + math.floor(s * 0.55)
thickLine(cx, hy + hr, hipX, hipY, color.BLACK)
thickLine(hipX, hipY, x + math.floor(s * 0.78), y + s, color.BLACK)
thickLine(hipX, hipY, x + math.floor(s * 0.18), y + s, color.BLACK)
thickLine(cx, hy + hr + math.floor(s * 0.08), x, y + math.floor(s * 0.55), color.BLACK)
end
local function routeIcon(x, y, s, id)
local B = color.BLACK
local function p(f) return math.floor(s * f) end
if id == "home" then
local rh = p(0.45)
draw.triangle(x, y + rh, x + s // 2, y, x + s, y + rh, B, true)
draw.rect(x + p(0.15), y + rh, p(0.7), s - rh, B, true)
elseif id == "work" then
local hw, hh = p(0.36), p(0.2)
draw.rect(x + (s - hw) // 2, y, hw, hh, B, false, 2)
draw.rect(x, y + hh, s, s - hh, B, true, 2)
hline(x, y + hh + (s - hh) // 2, s, color.WHITE)
elseif id == "school" then
local my = y + p(0.35)
draw.triangle(x, my, x + s // 2, y, x + s, my, B, true)
draw.triangle(x, my, x + s // 2, y + p(0.7), x + s, my, B, true)
draw.rect(x + p(0.35), my, p(0.3), p(0.35), B, true)
elseif id == "family" then
local r = p(0.28)
draw.circle(x + p(0.3), y + r, r, B, true)
draw.circle(x + p(0.7), y + r, r, B, true)
draw.triangle(x, y + math.floor(r * 0.7), x + s, y + math.floor(r * 0.7), x + s // 2, y + s, B, true)
elseif id == "shopping" then
draw.rect(x + p(0.1), y + p(0.35), p(0.8), p(0.55), B, true, 2)
vline(x + p(0.3), y, p(0.35)); vline(x + p(0.7), y, p(0.35)); hline(x + p(0.3), y, p(0.4) + 1)
elseif id == "train" then
draw.rect(x + p(0.1), y, p(0.8), p(0.65), B, true, 3)
draw.circle(x + p(0.3), y + p(0.8), p(0.14), B, true)
draw.circle(x + p(0.7), y + p(0.8), p(0.14), B, true)
elseif id == "plane" then
draw.triangle(x, y + p(0.6), x + s, y + p(0.3), x + p(0.55), y + p(0.75), B, true)
draw.triangle(x + p(0.55), y + p(0.75), x + p(0.75), y + s, x + p(0.4), y + p(0.85), B, true)
elseif id == "star" then
draw.triangle(x, y + p(0.65), x + s, y + p(0.65), x + s // 2, y, B, true)
draw.triangle(x + p(0.15), y + p(0.35), x + p(0.85), y + p(0.35), x + s // 2, y + s, B, true)
end
end
local function routeLabel(x, base, r, font, maxW)
local tx = x
if r.icon ~= "" then
routeIcon(x, base - 18, 20, r.icon)
tx = x + 28
if r.name == "" then return tx end
end
local s = fit(r.name, maxW - (tx - x), font)
draw.text(tx, base, s, font, color.BLACK)
return tx + draw.measure(s, font)
end
local function disruptTag(x, base, has)
if not has then return 0 end
local cy = base - 6
draw.circle(x + 8, cy, 8, color.RED, true)
textC(x + 8, cy + 3, "!", "small", color.WHITE)
return 22
end
local function footer(shown, total, de, en, prov)
local y = 480 - 30
hline(MX, y, 800 - 2 * MX)
local unit = T(de, en)
local l = total > shown and (shown .. " " .. T("von", "of") .. " " .. total .. " " .. unit) or (shown .. " " .. unit)
draw.text(MX, y + 20, l, "small", color.BLACK)
if total > shown then textR(800 - MX, y + 20, "+" .. (total - shown) .. " " .. T("weitere", "more"), "small") end
if prov == "hvv" then textC(400, y + 20, T("Daten: hvv.de", "Data: hvv.de"), "small") end
end
local function headway(times)
if #times < 2 then return "" end
local mn, mx = 0, 0
for i = 2, #times do
local g = (times[i] - times[i - 1]) // 60
if g > 0 then
if mn == 0 or g < mn then mn = g end
if g > mx then mx = g end
end
end
if mn == 0 then return "" end
if mn == mx then return T("alle ", "every ") .. mn .. T(" Minuten", " minutes") end
return T("alle ", "every ") .. mn .. "-" .. mx .. T(" Minuten", " minutes")
end
local function metaText(c, noArr)
local parts = {}
if c.arr > 0 and not noArr then parts[#parts + 1] = T("an ", "arr ") .. clock(c.arr) end
if WALK > 0 then parts[#parts + 1] = T("Losgehen: ", "Leave: ") .. WALK .. T(" Min Fußweg", " min walk") end
if c.xfer > 0 then parts[#parts + 1] = T("Umstieg: ", "Transfer: ") .. c.xfer .. T(" Min Fußweg", " min walk") end
return table.concat(parts, " \194\183 ")
end
local function disruptLine(c)
if c.dis ~= 1 then return nil end
if c.dtext ~= "" then return T("Störung", "Disruption") .. ": " .. c.dtext end
return T("Störung gemeldet", "Disruption reported")
end
local function firstTransit(c)
for _, l in ipairs(c.legs) do if l.t == "T" then return l end end
end
local function wrapChars(txt, w, maxLines)
local lines, line = {}, ""
for word in txt:gmatch("%S+") do
local try = line == "" and word or (line .. " " .. word)
if draw.measure(try, "small") <= w then line = try
else
if line ~= "" then lines[#lines + 1] = line; line = "" end
while draw.measure(word, "small") > w and #lines < maxLines do
local n = #word
while n > 1 and draw.measure(word:sub(1, n), "small") > w do
n = n - 1
while n > 1 and (word:byte(n + 1) or 0) & 0xC0 == 0x80 do n = n - 1 end
end
lines[#lines + 1] = word:sub(1, n)
word = word:sub(n + 1)
end
line = word
end
end
if line ~= "" then lines[#lines + 1] = line end
while #lines > maxLines do table.remove(lines) end
return lines
end
local function timeline(x, y, c, maxW)
local dotR = 5
local function empty(l) return l.t == "W" and l.dur <= 0 end
local si, ei = 1, #c.legs
while si < ei and empty(c.legs[si]) do si = si + 1 end
while ei > si and empty(c.legs[ei]) do ei = ei - 1 end
if ei < si then ei = si end
local seq = {}
for i = si, ei do if c.legs[i].t == "T" or i == si or i == ei then seq[#seq + 1] = i end end
local total = #seq
local ws, sum = {}, 0
for _, i in ipairs(seq) do ws[i] = c.legs[i].t == "W" and 90 or 130; sum = sum + ws[i] end
local avail = maxW - 2 * dotR - 8
if sum > avail then
local f = math.max(70, avail * 100 // sum)
for _, i in ipairs(seq) do ws[i] = ws[i] * f // 100 end
end
local labels = {}
local curX, drawn = x, 0
for k, i in ipairs(seq) do
local segW = ws[i]
if curX - x + segW > maxW then break end
local l = c.legs[i]
local sc = l.t == "W" and color.BLACK or lineColor(l.line, l.mode)
draw.rect(curX, y, segW, 2, sc, true)
draw.circle(curX, y, dotR, color.BLACK, true)
if l.dep > 0 then textCB(curX, y - 20, clock(l.dep), "normal", x, x + maxW) end
if l.origin ~= "" then labels[#labels + 1] = { cx = curX, s = k == 1 and (T("Start: ", "Start: ") .. l.origin) or l.origin, p = k == 1 and 2 or 3 + k } end
local icx = curX + segW // 2
if l.t == "W" then walkIcon(icx - 13, y - 13, 26) else badge(icx - 23, y - 13, l.line, l.mode, true) end
local sub = ""
if l.dur > 0 then sub = l.dur .. T(" Min", " min") end
if l.t == "T" and l.stops > 0 then
local long = l.stops .. T(" Stationen (", " stops (") .. l.dur .. T(" Min)", " min)")
if draw.measure(long, "small") <= segW - 4 then sub = long end
end
if sub ~= "" then textC(icx, y + 66, fit(sub, segW - 4, "small"), "small") end
curX = curX + segW
drawn = drawn + 1
end
local fits = drawn == total
if not fits and curX - x + dotR * 2 <= maxW then
local gw = math.min(46, maxW - (curX - x) - dotR * 2 - 4)
if gw >= 12 then
for dx = 0, gw - 1, 6 do hline(curX + dx, y, 3) end
textC(curX + gw // 2, y - 6, "+" .. (total - drawn), "small")
curX = curX + gw
fits = true
end
end
if fits and curX - x + dotR * 2 <= maxW then
draw.circle(curX, y, dotR + 3, color.BLACK, false)
draw.circle(curX, y, dotR, color.BLACK, true)
local arrE, dn, dp = c.arr, c.dest, c.plat
local nxt = c.legs[ei + 1]
if nxt and nxt.t == "W" then
if nxt.dep > 0 then arrE = nxt.dep end
if nxt.origin ~= "" then dn, dp = nxt.origin, "" end
end
if arrE > 0 then textCB(curX, y - 20, clock(arrE), "normal", x, x + maxW) end
if dn ~= "" then labels[#labels + 1] = { cx = curX, s = T("Ziel: ", "Dest: ") .. dn .. (dp ~= "" and (" Gl." .. dp) or ""), p = 1 } end
curX = curX + dotR * 2 + 4
end
table.sort(labels, function(a, b) return a.p < b.p end)
local boxes = {}
for _, lb in ipairs(labels) do
local lines = wrapChars(lb.s, 112, 3)
local w = 0
for _, ln in ipairs(lines) do w = math.max(w, draw.measure(ln, "small")) end
local l0 = math.max(x, math.min(lb.cx - w // 2, x + maxW - w))
local free = true
for _, b in ipairs(boxes) do if l0 < b[2] + 6 and l0 + w + 6 > b[1] then free = false end end
if free then
boxes[#boxes + 1] = { l0, l0 + w }
for ln = 1, #lines do draw.text(l0 + (w - draw.measure(lines[ln], "small")) // 2, y + 24 + (ln - 1) * 13, lines[ln], "small", color.BLACK) end
end
end
return curX - x
end
local function strand(x, yTop, c, maxW, big, withTimes)
local bw, bh, is, lw = big and 46 or 32, big and 26 or 20, big and 24 or 20, big and 18 or 12
local cy = yTop + bh // 2
local function ew(l) if l.t == "W" then return is + 5 + draw.measure(l.dur .. T(" Min", " min"), "small") end return bw end
local need, n = 0, 0
for _, l in ipairs(c.legs) do if not (l.t == "W" and l.dur <= 0) then need = need + ew(l) + (n > 0 and lw or 0); n = n + 1 end end
local dropMid = need > maxW
local curX, drawn = x, 0
for i, l in ipairs(c.legs) do
local isW = l.t == "W"
local skip = isW and (l.dur <= 0 or (dropMid and i > 1 and i < #c.legs))
if not skip then
local wb = isW and (l.dur .. T(" Min", " min")) or ""
local ew = isW and (is + 5 + draw.measure(wb, "small")) or bw
local need = ew + (drawn > 0 and lw or 0)
if curX - x + need > maxW then break end
if drawn > 0 then draw.rect(curX, cy, lw, 2, color.BLACK, true); curX = curX + lw end
if isW then
walkIcon(curX, yTop + (bh - is) // 2, is)
draw.text(curX + is + 5, cy + 5, wb, "small", color.BLACK)
else
if withTimes and l.dep > 0 then textC(curX + bw // 2, yTop - 6, clock(l.dep), "small") end
badge(curX, yTop, l.line, l.mode, big)
end
curX = curX + ew
drawn = drawn + 1
end
end
return curX - x
end
local function chips(x, y, conns, maxChips, cw, ch, gap, bigFirst, maxRight, startIdx)
local cx = x
local c = startIdx
while c <= #conns and c < startIdx + maxChips and cx + cw <= maxRight do
local k = conns[c]
local t = clock(leave(k.when))
local stc = k.delay > 0 and color.RED or (k.delay < 0 and color.GREEN or color.BLACK)
local base = y + ch - (ch >= 26 and 9 or 6)
if c == startIdx and bigFirst then
local ft = firstTransit(k)
local fc = k.delay > 0 and color.RED or (k.delay < 0 and color.GREEN or (ft and lineColor(ft.line, ft.mode) or color.BLUE))
draw.rect(cx, y, cw, ch, fc, true, ch >= 26 and 8 or 5)
textC(cx + cw // 2, base, t, ch >= 26 and "normal" or "small", inkOn(fc))
else
thickRR(cx, y, cw, ch, ch >= 26 and 8 or 5, stc)
textC(cx + cw // 2, base, t, "small", stc)
end
cx = cx + cw + gap
c = c + 1
end
return cx
end
local function stopSubline(top, d)
local stand = (d and d.at and d.at > 0) and (T("Stand ", "as of ") .. clock(d.at)) or ""
local sw = stand ~= "" and draw.measure(stand, "small") or 0
local name = short(d and d.stop ~= "" and d.stop or T("Haltestelle", "Stop"))
draw.text(MX, top + 18, fit(name, 800 - 2 * MX - sw - 20, "normal"), "normal", color.BLACK)
if stand ~= "" then textR(800 - MX, top + 18, stand, "small") end
return top + 30
end
local function depsState(ctx, prov)
local cfgStop = clean(s0(ctx.cfg.stop), 100)
if cfgStop == "" then notice("gear", T("Keine Haltestelle eingerichtet.", "No stop configured."), T("App-Einstellungen: Haltestelle suchen", "App settings: search stop")); return nil end
local d = readDeps()
local e = ctx.data.get("ed")
if d == nil or d.sig ~= depSig(ctx, prov) then
if e then notice("warning", errText(e), e == "creds" and T("App-Einstellungen: Anwendername und Passwort", "App settings: user name and password") or nil)
else notice("clock", T("Wird geladen ...", "Loading ...")) end
return nil
end
local live = {}
for _, x in ipairs(d.list) do if x.when >= NOW then live[#live + 1] = x end end
d.list = live
return d
end
local function depsCards(top, d, prov)
local ct = stopSubline(top, d)
if #d.list == 0 then notice("info", T("Keine Abfahrten gefunden.", "No departures found.")); return end
local groups, byLine = {}, {}
for _, x in ipairs(d.list) do
local g = byLine[x.line]
if g == nil then g = { line = x.line, dest = x.dest, mode = x.mode, times = {}, delays = {} }; byLine[x.line] = g; groups[#groups + 1] = g end
if #g.times < 4 then g.times[#g.times + 1] = x.when; g.delays[#g.delays + 1] = x.delay end
end
local tw, th, gap = 370, 176, 12
local gx = (800 - (2 * tw + gap)) // 2
local cw, chh, cg = 79, 34, 8
local drawnT = 0
for gi = 1, #groups do
if drawnT >= 4 then break end
local g = groups[gi]
local tx, ty = gx + (drawnT % 2) * (tw + gap), ct + (drawnT // 2) * (th + gap)
if ty + th > 450 then break end
thickRR(tx, ty, tw, th, 12, color.BLACK)
badge(tx + 14, ty + 12, g.line, g.mode, true)
draw.text(tx + 72, ty + 32, fit(g.dest, tw - 86, "normal"), "normal", color.BLACK)
local hw = headway(g.times)
if hw ~= "" then draw.text(tx + 14, ty + 58, hw, "small", color.BLACK) end
hline(tx + 14, ty + 70, tw - 28)
draw.text(tx + 14, ty + 90, T("NÄCHSTE ABFAHRTEN", "NEXT DEPARTURES"), "small", color.BLACK)
for t = 1, #g.times do
local cx, cy = tx + 14 + (t - 1) * (cw + cg), ty + 100
local clk = clock(leave(g.times[t]))
if t == 1 then
draw.rect(cx, cy, cw, chh, color.ACCENT, true, 8)
textC(cx + cw // 2, cy + 23, clk, "normal", color.ACCENT_INK)
else
thickRR(cx, cy, cw, chh, 8, color.BLACK)
textC(cx + cw // 2, cy + 23, clk, "normal")
end
local dl = g.delays[t]
if dl ~= 0 then textC(cx + cw // 2, ty + 154, string.format("%+d", dl), "normal", dl > 0 and color.RED or color.GREEN) end
end
drawnT = drawnT + 1
end
footer(drawnT, #groups, "Linien", "lines", prov)
end
local function depsFlat(top, d, prov)
local ct = stopSubline(top, d)
if #d.list == 0 then notice("info", T("Keine Abfahrten gefunden.", "No departures found.")); return end
local rowH, splitX, cntR, bx = 60, 168, 152, 192
local dx, re = bx + 60, 800 - MX
local cap = math.max(1, (450 - ct) // rowH)
local shown = math.min(#d.list, cap)
vline(splitX, ct, shown * rowH)
for i = 1, shown do
local x = d.list[i]
local ry = ct + (i - 1) * rowH
if i > 1 then hline(MX, ry, re - MX) end
local le = leave(x.when)
textR(cntR, ry + 34, tostring(minsTo(le)), "large")
textR(cntR, ry + 52, T("Minuten", "minutes"), "small")
badge(bx, ry + 17, x.line, x.mode, true)
draw.text(dx, ry + 39, fit(x.dest, re - 130 - dx, "medium"), "medium", color.BLACK)
textR(re, ry + 34, T("ab ", "at ") .. clock(le), "normal")
if x.delay ~= 0 then textR(re, ry + 54, string.format("%+d", x.delay), "normal", x.delay > 0 and color.RED or color.GREEN) end
end
footer(shown, #d.list, "Abfahrten", "departures", prov)
end
local function depsCompact(top, d, prov)
local ct = stopSubline(top, d)
if #d.list == 0 then notice("info", T("Keine Abfahrten gefunden.", "No departures found.")); return end
local rowH, re = 36, 800 - MX
local cap = math.max(1, math.min(10, (450 - ct) // rowH))
local shown = math.min(#d.list, cap)
for i = 1, shown do
local x = d.list[i]
local ry = ct + (i - 1) * rowH
local base = ry + 24
hline(MX, ry, re - MX)
badge(MX, ry + 8, x.line, x.mode, false)
draw.text(74, base, fit(x.dest, 420, "normal"), "normal", color.BLACK)
local le = leave(x.when)
textR(re - 216, base, clock(le), "normal")
if x.delay ~= 0 then textR(re - 150, base, string.format("%+d", x.delay), "normal", x.delay > 0 and color.RED or color.GREEN) end
textR(re, base, minsTo(le) .. " min", "normal")
end
footer(shown, #d.list, "Abfahrten", "departures", prov)
end
local function routesData(ctx, prov)
local cfg = routeCfg(ctx)
local res = readRoutes()
local list, urgent, urgentLeave = {}, nil, 0
for i = 1, NROUTES do
local r = cfg[i]
if r.enabled then
local rr = res[i]
r.conns, r.err = {}, nil
if rr and rr.sig == routeSig(ctx, prov, r) then
for _, c in ipairs(rr.conns) do if c.when >= NOW - 60 then r.conns[#r.conns + 1] = c end end
r.err = rr.err ~= "" and rr.err or nil
r.fetched = true
end
list[#list + 1] = r
if #r.conns > 0 then
local le = leave(r.conns[1].when)
if urgent == nil or le < urgentLeave then urgent, urgentLeave = #list, le end
end
end
end
return list, urgent
end
local function noConn(r)
if r.fetched == nil then return T("Wird geladen ...", "Loading ...") end
if r.err and r.err ~= "" and #r.conns == 0 and r.err ~= "fail" and r.err ~= "none" then return errText(r.err) end
return T("Keine Verbindung gefunden.", "No connection found.")
end
local function routesEmpty(list)
if #list > 0 then return false end
notice("gear", T("Keine Routen eingerichtet.", "No routes configured."), T("App-Einstellungen: Route 1 bis 6, Start und Ziel", "App settings: route 1 to 6, start and destination"))
return true
end
local function routesCards(top, list, urgent, prov)
if routesEmpty(list) then return end
urgent = urgent or 1
local ct, heroH, cardH, gap = top + 4, 228, 76, 10
local bx, bw = MX, 800 - 2 * MX
local re = bx + bw
local hero = list[urgent]
local hy = ct
thickRR(bx, hy, bw, heroH, 12, color.BLACK)
local boxW, boxH = 212, 88
local boxX, boxY, tx = re - 22 - boxW, hy + 22, bx + 22
draw.text(tx, hy + 26, T("JETZT LOSGEHEN", "LEAVE NOW"), "small", color.BLACK)
local ne = routeLabel(tx, hy + 62, hero, "large", boxX - 16 - tx)
if #hero.conns > 0 then
local f = hero.conns[1]
if f.dis == 1 then disruptTag(ne + 10, hy + 62, true) end
local m = minsTo(leave(f.when))
draw.rect(boxX, boxY, boxW, boxH, color.ACCENT, true, 12)
textC(boxX + boxW // 2, boxY + 56, tostring(m), "large", color.ACCENT_INK)
local sub = T("Minuten", "minutes")
if f.delay ~= 0 then sub = sub .. " \194\183 " .. string.format("%+d", f.delay) end
textC(boxX + boxW // 2, boxY + 76, sub, "small", color.ACCENT_INK)
if #hero.conns > 1 then chips(boxX, boxY + boxH + 8, hero.conns, 2, 100, 32, 12, false, re - 22, 2) end
timeline(tx, hy + 120, f, boxX - 16 - tx)
local meta = metaText(f)
if meta ~= "" then draw.text(tx, hy + 200, fit(meta, bw - 44, "small"), "small", color.BLACK) end
local dl = disruptLine(f)
if dl then draw.text(tx, hy + 220, fit(dl, bw - 44, "small"), "small", color.RED) end
else
draw.text(tx, hy + 120, noConn(hero), "normal", color.BLACK)
end
local cw, chh, cg = 76, 28, 8
local chipsW = 3 * cw + 2 * cg
local cy, drawnR = hy + heroH + gap, 1
for s = 1, #list do
if s ~= urgent then
if cy + cardH > 450 then break end
local r = list[s]
thickRR(bx, cy, bw, cardH, 10, color.BLACK)
local ctx_ = bx + 16
local cne = routeLabel(ctx_, cy + 30, r, "normal", bw - 200)
if #r.conns > 0 then
local c = r.conns[1]
if c.dis == 1 then disruptTag(cne + 10, cy + 30, true) end
textR(re - 16, cy + 32, T("in ", "in ") .. minsTo(leave(c.when)) .. " min", "large", c.delay > 0 and color.RED or color.BLACK)
local chipsX = re - 16 - chipsW
chips(chipsX, cy + 40, r.conns, 3, cw, chh, cg, true, re - 16, 1)
strand(ctx_, cy + 42, c, chipsX - 14 - ctx_, false, false)
else
draw.text(ctx_, cy + 56, noConn(r), "small", color.BLACK)
end
cy = cy + cardH + gap
drawnR = drawnR + 1
end
end
footer(drawnR, #list, "Routen", "routes", prov)
end
local function nextTimes(r, sep, prefix)
if #r.conns < 2 then return nil end
local t = {}
for c = 2, math.min(#r.conns, MAXRES) do t[#t + 1] = clock(leave(r.conns[c].when)) end
return (prefix or "") .. table.concat(t, sep)
end
local function routesFlat(top, list, prov)
if routesEmpty(list) then return end
local ct, bh, splitX = top + 4, 130, 556
local tx, re = splitX + 16, 800 - MX
local cap = math.max(1, (450 - ct) // bh)
local shown = math.min(#list, cap)
vline(splitX, ct, shown * bh)
for s = 1, shown do
local r = list[s]
local by = ct + (s - 1) * bh
if s > 1 then hline(MX, by, re - MX) end
local ne = routeLabel(MX, by + 34, r, "large", splitX - 24 - MX)
if #r.conns == 0 then
draw.text(MX, by + 72, noConn(r), "small", color.BLACK)
textR(re, by + 34, "--:--", "normal")
else
local c = r.conns[1]
if c.dis == 1 then disruptTag(ne + 10, by + 34, true) end
strand(MX, by + 62, c, splitX - 24 - MX, true, true)
local meta = metaText(c)
if meta ~= "" then draw.text(MX, by + 110, fit(meta, splitX - 24 - MX, "small"), "small", color.BLACK) end
local le = leave(c.when)
local cnt = minsTo(le) .. " min"
draw.text(tx, by + 34, cnt, "large", color.BLACK)
if c.delay ~= 0 then draw.text(tx + draw.measure(cnt, "large") + 10, by + 34, string.format("%+d", c.delay), "normal", c.delay > 0 and color.RED or color.GREEN) end
draw.text(tx, by + 60, T("ab ", "at ") .. clock(le), "normal", color.BLACK)
local nx = nextTimes(r, " \194\183 ", T("dann ", "then "))
if nx then draw.text(tx, by + 84, fit(nx, re - tx, "small"), "small", color.BLACK) end
if c.dis == 1 then draw.text(tx, by + 108, fit("! " .. T("Störung auf der Strecke", "Disruption en route"), re - tx, "small"), "small", color.RED) end
end
end
footer(shown, #list, "Routen", "routes", prov)
end
local function routesCompact(top, list, prov)
if routesEmpty(list) then return end
local stripH, sx0, sw, lz = 72, 310, 310, 276
local re = 800 - MX
draw.text(MX, top + 18, T("ZEIT BIS LOSGEHEN", "TIME UNTIL DEPARTURE"), "small", color.BLACK)
for m = 0, 30, 10 do textC(sx0 + m * sw // 30, top + 18, tostring(m), "small") end
hline(MX, top + 28, re - MX)
local st = top + 34
local cap = math.max(1, math.min(5, (450 - st) // stripH))
local shown = math.min(#list, cap)
for s = 1, shown do
local r = list[s]
local sy = st + (s - 1) * stripH
if s > 1 then hline(MX, sy, re - MX) end
local ne = routeLabel(MX, sy + 26, r, "normal", lz)
if #r.conns == 0 then
draw.text(MX, sy + 46, noConn(r), "small", color.BLACK)
textR(re, sy + 30, "--:--", "normal")
else
local c = r.conns[1]
if c.dis == 1 then disruptTag(ne + 8, sy + 26, true) end
local meta = metaText(c)
if meta ~= "" then draw.text(MX, sy + 46, fit(meta, lz, "small"), "small", color.BLACK) end
local le = leave(c.when)
local m = minsTo(le)
local mx = sx0 + math.min(m, 30) * sw // 30
local mc = m < 5 and color.RED or color.ACCENT
local ay = sy + 30
if mx > sx0 then draw.rect(sx0, ay - 1, mx - sx0, 3, mc, true) end
if mx < sx0 + sw then hline(mx, ay, sx0 + sw - mx) end
draw.circle(mx, ay, 8, color.WHITE, true)
draw.circle(mx, ay, 8, mc, false)
draw.circle(mx, ay, 7, mc, false)
textC(mx, sy + 16, tostring(m), "small")
strand(sx0, sy + 42, c, sw, false, false)
textR(re, sy + 30, clock(le), "large", c.delay > 0 and color.RED or color.BLACK)
local nx = nextTimes(r, " \194\183 ")
if nx then textR(re, sy + 52, nx, "small") end
end
end
footer(shown, #list, "Routen", "routes", prov)
end
local function routeSingle(top, r, style, prov)
local cs = {}
for _, c in ipairs(r.conns) do if #cs < 3 or leave(c.when) <= NOW + 600 then cs[#cs + 1] = c end end
local re = 800 - MX
local ne = routeLabel(MX, top + 30, r, "large", 500)
if #cs > 0 and cs[1].dis == 1 then disruptTag(ne + 10, top + 30, true) end
textR(re, top + 30, T("Losgehen in den n\195\164chsten 10 Min.", "Leave within the next 10 min"), "small")
if #cs == 0 then draw.text(MX, top + 80, noConn(r), "normal", color.BLACK); return end
local cards, flat = style ~= "flat" and style ~= "compact", style == "flat"
local rowH = cards and 118 or (flat and 96 or 60)
local y0 = top + 44
local shown = math.min(#cs, math.max(1, (450 - y0) // rowH))
for k = 1, shown do
local c = cs[k]
local y = y0 + (k - 1) * rowH
local le = leave(c.when)
local m = minsTo(le)
local dur = c.arr > c.when and (c.arr - c.when) // 60 or 0
local info = T("ab ", "dep ") .. clock(le) .. (c.arr > 0 and (" - " .. T("an ", "arr ") .. clock(c.arr)) or "") .. (dur > 0 and (" \194\183 " .. dur .. T(" Min", " min")) or "")
local dl = c.delay ~= 0 and string.format("%+d", c.delay) or nil
local dc = c.delay > 0 and color.RED or color.GREEN
local meta, dis = metaText(c, true), disruptLine(c)
if c.dest ~= "" then meta = T("Ziel: ", "Dest: ") .. c.dest .. (meta ~= "" and (" \194\183 " .. meta) or "") end
if cards then
thickRR(MX, y, re - MX, rowH - 10, 10, color.BLACK)
local bx, tx = MX + 10, MX + 136
if k == 1 then draw.rect(bx, y + 10, 112, rowH - 30, color.ACCENT, true, 10) else thickRR(bx, y + 10, 112, rowH - 30, 10, color.BLACK) end
local ink = k == 1 and color.ACCENT_INK or color.BLACK
textC(bx + 56, y + 54, tostring(m), "large", ink)
textC(bx + 56, y + 74, T("Minuten", "minutes"), "small", ink)
draw.text(tx, y + 24, info, "normal", color.BLACK)
if dl then draw.text(tx + draw.measure(info, "normal") + 10, y + 24, dl, "normal", dc) end
strand(tx, y + 46, c, re - 12 - tx, true, true)
if meta ~= "" then draw.text(tx, y + 87, fit(meta, re - 12 - tx, "small"), "small", color.BLACK) end
if dis then draw.text(tx, y + 101, fit(dis, re - 12 - tx, "small"), "small", color.RED) end
elseif flat then
if k > 1 then hline(MX, y, re - MX) end
vline(200, y + 6, rowH - 12)
draw.text(MX, y + 38, m .. " min", "large", color.BLACK)
draw.text(MX, y + 64, T("ab ", "at ") .. clock(le), "normal", color.BLACK)
if dl then draw.text(MX + 90, y + 64, dl, "normal", dc) end
draw.text(216, y + 24, info, "normal", color.BLACK)
strand(216, y + 34, c, re - 216, true, false)
local ln = dis or meta
if ln ~= "" then draw.text(216, y + 84, fit(ln, re - 216, "small"), "small", dis and color.RED or color.BLACK) end
else
if k > 1 then hline(MX, y, re - MX) end
textR(MX + 112, y + 32, clock(le), "large", c.delay > 0 and color.RED or color.BLACK)
textR(MX + 112, y + 50, T("in ", "in ") .. m .. " min", "small")
strand(152, y + 8, c, re - 152 - 60, false, false)
draw.text(152, y + 48, fit(info .. (meta ~= "" and (" \194\183 " .. meta) or ""), re - 152 - 60, "small"), "small", color.BLACK)
if dl then textR(re, y + 32, dl, "normal", dc) end
if c.dis == 1 then disruptTag(re - 20, y + 52, true) end
end
end
footer(shown, #cs, "Verbindungen", "connections", prov)
end
function on_draw(ctx, page)
EN = ctx.lang == "en"
OFF, NOW, WALK = tzOff(), time.now() or 0, walkMin(ctx)
draw.clear(color.WHITE)
local prov = provOf(ctx)
local style = s0(ctx.cfg.style)
local top = draw.top + 4
if n0(page) == 2 then
local list, urgent = routesData(ctx, prov)
if #list == 1 then routeSingle(top, list[1], style, prov)
elseif style == "flat" then routesFlat(top, list, prov)
elseif style == "compact" then routesCompact(top, list, prov)
else routesCards(top, list, urgent, prov) end
return
end
local d = depsState(ctx, prov)
if d == nil then return end
if style == "flat" then depsFlat(top, d, prov)
elseif style == "compact" then depsCompact(top, d, prov)
else depsCards(top, d, prov) end
end
local function sampleDeps()
local n = NOW - NOW % 60
return { { line = "U1", mode = SUBWAY, dest = "Ohlstedt", when = n + 4 * 60, delay = 0 }, { line = "275", mode = OTHER, dest = "Wildschwanbrook", when = n + 7 * 60, delay = 2 },
{ line = "U1", mode = SUBWAY, dest = "Norderstedt Mitte", when = n + 9 * 60, delay = 0 }, { line = "S1", mode = SUB, dest = "Wedel", when = n + 12 * 60, delay = 1 },
{ line = "M8", mode = OTHER, dest = "Hauptbahnhof", when = n + 15 * 60, delay = 0 }, { line = "U1", mode = SUBWAY, dest = "Ohlstedt", when = n + 19 * 60, delay = 0 } }
end
local function widgetDeps(ctx, box, list)
local withDest, withDelay = on(ctx.cfg.wDest), on(ctx.cfg.wDelay)
local tileH = withDest and 44 or 26
local cols = box.w >= 300 and 2 or 1
local tileW = (box.w - 16) // cols
local maxY = box.y + box.h - 4
local maxTiles = math.max(1, (maxY - box.y) // tileH) * cols
local tf_ = box.font < 0 and "small" or (box.font > 0 and "medium" or "normal")
local shown = 0
for _, x in ipairs(list) do
if shown >= maxTiles then break end
if x.when >= NOW then
local col, row = shown % cols, shown // cols
local tx, ty = box.x + 10 + col * tileW, box.y + row * tileH + 4
local lc = lineColor(x.line, x.mode)
draw.rect(tx, ty, 40, 18, lc, true, 9)
textCB(tx + 20, ty + 13, fit(x.line, 36, "small"), "small", tx + 2, tx + 38, inkOn(lc))
local tm = clock(leave(x.when))
draw.text(tx + 50, ty + 14, tm, tf_, color.BLACK)
if withDelay and x.delay > 0 then
local dxp = math.max(tx + 100, tx + 56 + draw.measure(tm, tf_))
draw.text(dxp, ty + 14, "+" .. x.delay, "normal", color.RED)
end
if withDest then draw.text(tx + 50, ty + 31, fit(x.dest, tileW - 54, "small"), "small", color.BLACK) end
shown = shown + 1
end
end
return shown
end
local function widgetRoutes(ctx, box, list)
local withDest, withDelay = on(ctx.cfg.wDest), on(ctx.cfg.wDelay)
local rowH = withDest and 44 or 26
local maxRows = math.max(1, (box.y + box.h - 4 - box.y) // rowH)
local rz = 108
local bxp = box.x + box.w - rz
local lmax = math.max(40, bxp - (box.x + 10) - 10)
local lf = box.font > 0 and "normal" or "small"
local tf_ = box.font < 0 and "small" or (box.font > 0 and "medium" or "normal")
local rows = {}
for _, r in ipairs(list) do
for k, c in ipairs(r.conns) do if k == 1 or #list == 1 then rows[#rows + 1] = { r, c, k } end end
end
local shown = 0
for _, row in ipairs(rows) do
if shown >= maxRows then break end
local r, c = row[1], row[2]
do
local ty = box.y + shown * rowH + 4
if row[3] == 1 then routeLabel(box.x + 10, ty + 14, r, lf, lmax) else draw.text(box.x + 10, ty + 14, T("danach", "then"), lf, color.BLACK) end
local ft = firstTransit(c)
local lc = ft and lineColor(ft.line, ft.mode) or color.BLUE
draw.rect(bxp, ty, 36, 18, lc, true, 9)
textCB(bxp + 18, ty + 13, fit(ft and ft.line or "?", 32, "small"), "small", bxp + 2, bxp + 34, inkOn(lc))
draw.text(bxp + 44, ty + 14, clock(leave(c.when)), tf_, color.BLACK)
if c.dis == 1 then draw.circle(bxp - 8, ty + 6, 3, color.RED, true) end
if withDelay and withDest and c.delay > 0 then draw.text(bxp + 44, ty + 31, "+" .. c.delay, "small", color.RED) end
if withDest then
local dest = c.dest ~= "" and c.dest or r.toLabel
draw.text(box.x + 10, ty + 31, fit(dest, lmax, "small"), "small", color.BLACK)
end
shown = shown + 1
end
end
return shown
end
local function sampleRoutes()
local n = NOW - NOW % 60
local function mk(line, mode, dep, dest, dl)
return { when = dep, arr = dep + 25 * 60, delay = dl, xfer = 0, dis = 0, dtext = "", dest = dest, plat = "",
legs = { { t = "T", line = line, mode = mode, origin = "Berne", dep = dep, plat = "", dur = 25, stops = 12 } } }
end
return { { idx = 1, name = T("Zur Arbeit", "To work"), icon = "work", toLabel = "Hauptbahnhof", conns = { mk("U1", SUBWAY, n + 6 * 60, "Hauptbahnhof Süd", 2) } },
{ idx = 2, name = T("Zum Sport", "To the gym"), icon = "star", toLabel = "Farmsen", conns = { mk("275", OTHER, n + 11 * 60, "Farmsen", 0) } } }
end
function on_widget(ctx, box)
EN = ctx.lang == "en"
OFF, NOW, WALK = tzOff(), time.now() or 0, walkMin(ctx)
local prov = provOf(ctx)
local shown = 0
if on(ctx.cfg.wRoutes) then
local list = routesData(ctx, prov)
if #list == 0 and ctx.sample then list = sampleRoutes() end
shown = widgetRoutes(ctx, box, list)
else
local d = readDeps()
local list = (d and d.sig == depSig(ctx, prov)) and d.list or {}
if #list == 0 and ctx.sample then list = sampleDeps() end
shown = widgetDeps(ctx, box, list)
end
if shown == 0 then
local msg = T("Noch keine Daten", "No data yet")
local e = ctx.data.get("ed")
if e and not on(ctx.cfg.wRoutes) then msg = errText(e) end
textC(box.x + box.w // 2, box.y + math.min(box.h // 2 + 6, 40), fit(msg, box.w - 16, "small"), "small")
end
end
