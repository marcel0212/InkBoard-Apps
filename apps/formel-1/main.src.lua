-- Formel 1 (Skript-Variante der eingebauten App), Skript-API Level 11.
-- Seiten: naechstes Rennen (Streckenlayout, Zeitplan in Ortszeit, Countdown), WM-Wertung (Fahrer/Konstrukteure),
-- letzte Session (Rennergebnis, am Rennwochenende die zuletzt beendete Session). Stile Bento/Slate/Nano, Dashboard-Widget.
-- Quellen: Jolpica-F1 (Kalender, Ergebnis, Wertung) und OpenF1 (Training/Qualifying/Sprint am Rennwochenende).
-- on_fetch legt die Daten als kleine Textdateien ab (cal, last, drv, con, sess, err); ctx.data haelt nur Zeitmarken.
-- Kalender hoechstens alle 12 h, Ergebnis/Wertung nur nach einem neuen Rennen, OpenF1 nur im Wochenendfenster.
-- Ortszeit: aus time.localtime() abgeleiteter UTC-Abstand plus EU-Sommerzeitregel (offsetAt).
-- Streckenlayouts: assets/tracks.txt (Punktlisten aus der eingebauten App), beim Zeichnen per asset.read gelesen.

local EN = false
local function T(de, en) if EN then return en end return de end

local JOLPICA = "https://api.jolpi.ca/ergast/f1/"
local OPENF1 = "https://api.openf1.org/v1/"
local RESULT_MAX, DRV_MAX, TEAM_MAX = 10, 8, 6

--#include text
--#include ui
--#include dates

-- Streckendaten (Schluessel = circuitId der Jolpica-API): Namen, Laenge in m, Runden, Kurven, Rundenrekord
local CIRCUITS = {
	albert_park = { de = "GP von Australien", en = "Australian GP", len = 5278, laps = 58, corners = 14, rec = "1:19,813" },
	shanghai = { de = "GP von China", en = "Chinese GP", len = 5451, laps = 56, corners = 16, rec = "1:32,238" },
	suzuka = { de = "GP von Japan", en = "Japanese GP", len = 5807, laps = 53, corners = 18, rec = "1:30,983" },
	bahrain = { de = "GP von Bahrain", en = "Bahrain GP", len = 5412, laps = 57, corners = 15, rec = "1:31,447" },
	sepang = { de = "GP von Malaysia", en = "Malaysian GP", len = 5543, laps = 56, corners = 15, rec = "1:34,080" },
	jeddah = { de = "GP von Saudi-Arabien", en = "Saudi Arabian GP", len = 6174, laps = 50, corners = 27, rec = "1:30,734" },
	miami = { de = "GP von Miami", en = "Miami GP", len = 5412, laps = 57, corners = 19, rec = "1:29,708" },
	villeneuve = { de = "GP von Kanada", en = "Canadian GP", len = 4361, laps = 70, corners = 14, rec = "1:13,078" },
	monaco = { de = "GP von Monaco", en = "Monaco GP", len = 3337, laps = 78, corners = 19, rec = "1:12,909" },
	catalunya = { de = "GP von Spanien", en = "Spanish GP", len = 4657, laps = 66, corners = 14, rec = "1:16,330" },
	red_bull_ring = { de = "GP von Österreich", en = "Austrian GP", len = 4318, laps = 71, corners = 10, rec = "1:05,619" },
	silverstone = { de = "GP von Großbritannien", en = "British GP", len = 5891, laps = 52, corners = 18, rec = "1:27,097" },
	spa = { de = "GP von Belgien", en = "Belgian GP", len = 7004, laps = 44, corners = 19, rec = "1:44,701" },
	hungaroring = { de = "GP von Ungarn", en = "Hungarian GP", len = 4381, laps = 70, corners = 14, rec = "1:16,627" },
	zandvoort = { de = "GP der Niederlande", en = "Dutch GP", len = 4259, laps = 72, corners = 14, rec = "1:11,097" },
	monza = { de = "GP von Italien", en = "Italian GP", len = 5793, laps = 53, corners = 11, rec = "1:21,046" },
	madring = { de = "GP von Madrid", en = "Madrid GP", len = 5474, laps = 57, corners = 22, rec = nil },
	baku = { de = "GP von Aserbaidschan", en = "Azerbaijan GP", len = 6003, laps = 51, corners = 20, rec = "1:43,009" },
	marina_bay = { de = "GP von Singapur", en = "Singapore GP", len = 4940, laps = 62, corners = 19, rec = "1:34,486" },
	americas = { de = "GP der USA", en = "United States GP", len = 5513, laps = 56, corners = 20, rec = "1:36,169" },
	rodriguez = { de = "GP von Mexiko", en = "Mexico City GP", len = 4304, laps = 71, corners = 17, rec = "1:17,774" },
	interlagos = { de = "GP von Brasilien", en = "Sao Paulo GP", len = 4309, laps = 71, corners = 15, rec = "1:10,540" },
	vegas = { de = "GP von Las Vegas", en = "Las Vegas GP", len = 6201, laps = 50, corners = 17, rec = "1:34,876" },
	losail = { de = "GP von Katar", en = "Qatar GP", len = 5419, laps = 57, corners = 16, rec = "1:22,384" },
	yas_marina = { de = "GP von Abu Dhabi", en = "Abu Dhabi GP", len = 5281, laps = 58, corners = 16, rec = "1:25,637" },
	portimao = { de = "GP von Portugal", en = "Portuguese GP", len = 4653, laps = 66, corners = 15, rec = "1:18,750" },
	istanbul = { de = "GP der Türkei", en = "Turkish GP", len = 5338, laps = 58, corners = 14, rec = "1:24,770" },
}

local TEAM_CODES = {
	mclaren = "MCL", red_bull = "RBR", ferrari = "FER", mercedes = "MER", aston_martin = "AMR", williams = "WIL",
	alpine = "ALP", haas = "HAA", rb = "RB", sauber = "SAU", audi = "AUD", cadillac = "CAD",
}

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

local function wdName(p) return (EN and WD_EN or WD_DE)[p.wday + 1] end

local function fmtDate(e)
	local p = localParts(e)
	return string.format("%s %02d.%02d.", wdName(p), p.day, p.month)
end

local function fmtTime(e)
	local p = localParts(e)
	return string.format("%02d:%02d", p.hour, p.min)
end

local function fmtTimeDevice(ctx, e)
	if ctx.clock24 ~= false then return fmtTime(e) end
	local p = localParts(e)
	local h = p.hour % 12
	if h == 0 then h = 12 end
	return string.format("%02d:%02d %s", h, p.min, p.hour < 12 and "AM" or "PM")
end

local function dsp(s) return (s:gsub("[,.]", EN and "." or ",")) end

local function fmtKm(m) return dsp(string.format("%d.%03d km", m // 1000, m % 1000)) end

local function fmtPoints(p)
	local r = math.floor(p + 0.5)
	if math.abs(p - r) < 0.05 then return tostring(r) end
	return dsp(string.format("%.1f", p))
end

local function countdown(startE, long)
	local now, lt = time.now(), time.localtime()
	local mid = now
	if lt then mid = now - (lt.hour * 3600 + lt.min * 60 + lt.sec) end
	local days = (startE - mid) // 86400
	if days < 0 then days = 0 end
	if days == 0 then return T("heute", "today") end
	if days == 1 then return T("morgen", "tomorrow") end
	if long then return T("in " .. days .. " Tagen", "in " .. days .. " days") end
	return days .. T(" Tage", " days")
end

local function gpName(cid, apiName)
	local ci = CIRCUITS[cid]
	if ci then return EN and ci.en or ci.de end
	return (apiName ~= nil and apiName ~= "") and apiName or "Formel 1"
end

local SES_LABEL = {
	p1 = { "1. Training", "Practice 1" }, p2 = { "2. Training", "Practice 2" }, p3 = { "3. Training", "Practice 3" },
	sq = { "Sprint-Quali", "Sprint quali" }, s = { "Sprint", "Sprint" }, q = { "Qualifying", "Qualifying" }, r = { "Rennen", "Race" },
}
local SES_SHORT = {
	p1 = { "FP1", "FP1" }, p2 = { "FP2", "FP2" }, p3 = { "FP3", "FP3" }, sq = { "SQ", "SQ" }, s = { "Sprint", "Sprint" },
	q = { "Quali", "Quali" }, r = { "Rennen", "Race" },
}
local LAST_LABEL = {
	p1 = { "Training 1", "Practice 1" }, p2 = { "Training 2", "Practice 2" }, p3 = { "Training 3", "Practice 3" },
	sq = { "Sprint-Qualifying", "Sprint qualifying" }, s = { "Sprint", "Sprint" }, q = { "Qualifying", "Qualifying" },
	race = { "Letztes Rennen", "Last race" },
}
local function lab(tbl, k) local v = tbl[k] or tbl.r or tbl.race; return EN and v[2] or v[1] end

local function splitTabs(line)
	local out = {}
	for f in (line .. "\t"):gmatch("([^\t]*)\t") do out[#out + 1] = f end
	return out
end

local function parseCal(text)
	local out = {}
	if type(text) ~= "string" then return out end
	for line in text:gmatch("[^\n]+") do
		local rnd, cid, name, circuit, loc, country, st, ss =
			line:match("^(%d+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(%d+)\t?(.*)$")
		if rnd then
			local r = { round = tonumber(rnd), cid = cid, name = name, circuit = circuit, loc = loc, country = country,
				start = tonumber(st), sess = {} }
			for code, e in ss:gmatch("(%a+%d?)=(%d+)") do r.sess[#r.sess + 1] = { t = code, s = tonumber(e) } end
			table.sort(r.sess, function(a, b) return a.s < b.s end)
			out[#out + 1] = r
		end
	end
	return out
end

local function pickNext(cal, now)
	for _, r in ipairs(cal) do
		if r.start + 4 * 3600 > now then return r end
	end
	return nil
end

local D = {}   -- je Hook zwischengespeicherte Daten
local function resetData()
	D = {}
	OFF_NOW = nil
end

local function getCal()
	if D.cal == nil then D.cal = parseCal(file.read("cal")) end
	return D.cal
end

local function totalRounds(cal)
	local n = 0
	for _, r in ipairs(cal) do if r.round > n then n = r.round end end
	return n
end

local function getLast()
	if D.last == nil then
		D.last = false
		local text = file.read("last")
		if text then
			local rows, head = {}, nil
			for line in text:gmatch("[^\n]+") do
				local f = splitTabs(line)
				if f[1] == "H" then
					head = { round = tonumber(f[2]) or 0, cid = f[3] or "", name = f[4] or "", date = tonumber(f[5]) or 0,
						flDriver = f[6] or "", flTime = f[7] or "", pole = f[8] or "", dnf = f[9] or "" }
				elseif f[1] == "R" then
					rows[#rows + 1] = { pos = tonumber(f[2]) or 0, driver = f[3] or "", team = f[4] or "", gap = f[5] or "" }
				end
			end
			if head and #rows > 0 then head.rows = rows; D.last = head end
		end
	end
	return D.last
end

local function getStand(name)
	local key = "st_" .. name
	if D[key] == nil then
		D[key] = { rows = {}, round = 0 }
		local text = file.read(name)
		if text then
			for line in text:gmatch("[^\n]+") do
				local f = splitTabs(line)
				if f[1] == "R" then D[key].round = tonumber(f[2]) or 0
				elseif f[1] == "D" then D[key].rows[#D[key].rows + 1] = { pos = tonumber(f[2]) or 0, name = f[3] or "", code = f[4] or "", points = tonumber(f[5]) or 0 }
				elseif f[1] == "T" then D[key].rows[#D[key].rows + 1] = { pos = tonumber(f[2]) or 0, name = f[3] or "", code = "", points = tonumber(f[4]) or 0 }
				end
			end
		end
	end
	return D[key]
end

local function getSess(kind)
	if D.sess == nil then
		D.sess = false
		local text = file.read("sess")
		if text then
			local rows, k = {}, nil
			for line in text:gmatch("[^\n]+") do
				local f = splitTabs(line)
				if f[1] == "H" then k = f[2]
				elseif f[1] == "R" then rows[#rows + 1] = { code = f[2] or "", team = f[3] or "", time = f[4] or "" } end
			end
			if k == kind and #rows > 0 then D.sess = rows end
		end
	end
	return D.sess
end

local function sessKind(ctx)
	local k = ctx.data.get("sk")
	if type(k) ~= "string" or k == "" then return "race" end
	return k
end

local NET = { n = 0 }

local function get(url, maxBytes)
	if NET.n >= 6 then return nil end
	if NET.n > 0 then time.sleep(250) end
	NET.n = NET.n + 1
	local body, err = http.get(url, maxBytes)
	if body == nil then log("Formel 1: " .. tostring(err)) end
	return body
end

local function decodeObj(s)
	for _ = 0, 14 do
		local v = json.decode(s)
		if type(v) == "table" then return v end
		s = s:sub(1, -2)
		if s == "" then return nil end
	end
	return nil
end

local function chunks(body, pat)
	local s = body:find(pat)
	return function()
		if not s then return nil end
		local nxt = body:find(pat, s + 1)
		local part = body:sub(s, nxt and (nxt - 2) or #body)
		s = nxt
		return part
	end
end

local function str(v, n) if type(v) ~= "string" then return "" end return clean(v, n) end

local function shortTeam(name)
	return (name:gsub(" F1 Team$", ""))
end

local function teamCode(cid, name)
	if type(cid) == "string" and TEAM_CODES[cid] then return TEAM_CODES[cid] end
	local code = (name or ""):gsub("[^%w]", ""):sub(1, 3):upper()
	if code == "" then return "?" end
	return code
end

local SES_KEYS = { { "FirstPractice", "p1" }, { "SecondPractice", "p2" }, { "ThirdPractice", "p3" },
	{ "SprintQualifying", "sq" }, { "Sprint", "s" }, { "Qualifying", "q" } }

local function fetchCalendar(ctx)
	local body = get(JOLPICA .. "current.json?limit=30", 65536)
	if not body then return nil end
	local pat = '{"season":"%d+","round":"%d+","url"'
	if not body:find(pat) then pat = '{"season":"%d+","round":"%d+","raceName"' end
	local lines = {}
	for part in chunks(body, pat) do
		local r = decodeObj(part)
		local rnd = r and tonumber(r.round)
		if rnd and type(r.date) == "string" then
			local start = parseIso(r.date .. "T" .. (type(r.time) == "string" and r.time or "12:00:00Z"))
			if start then
				local cir = type(r.Circuit) == "table" and r.Circuit or {}
				local loc = type(cir.Location) == "table" and cir.Location or {}
				local ss = {}
				for _, k in ipairs(SES_KEYS) do
					local s = r[k[1]]
					if type(s) == "table" and type(s.date) == "string" then
						local e = parseIso(s.date .. "T" .. (type(s.time) == "string" and s.time or "12:00:00Z"))
						if e then ss[#ss + 1] = k[2] .. "=" .. e end
					end
				end
				lines[#lines + 1] = table.concat({ rnd, str(cir.circuitId, 28), str(r.raceName, 40), str(cir.circuitName, 40),
					str(loc.locality, 24), str(loc.country, 24), start, table.concat(ss, ",") }, "\t")
			end
		end
	end
	if #lines == 0 then return nil end
	local text = table.concat(lines, "\n")
	file.write("cal", text)
	ctx.data.set("cal_t", time.now())
	return text
end

local function fetchLast(ctx)
	local body = get(JOLPICA .. "current/last/results.json", 48000)
	if not body then return false end
	local rs = body:find('{"season":"%d+","round":"%d+","url"')
	local he = body:find('"Results":[', 1, true)
	if not rs or not he then   -- noch kein Rennen in dieser Saison
		file.write("last", "")
		ctx.data.set("res_r", 0)
		ctx.data.set("res_t", time.now())
		return true
	end
	local hd = decodeObj(body:sub(rs, he + 10) .. "]}") or {}
	local cir = type(hd.Circuit) == "table" and hd.Circuit or {}
	local round = tonumber(hd.round) or 0
	local dateE = 0
	if type(hd.date) == "string" then dateE = parseIso(hd.date .. "T12:00:00Z") or 0 end
	local pat = '{"number":"%d+","position":"'
	if not body:find(pat) then pat = '{"position":"%d+"' end
	local rows, fl, flTime, pole, dnf, dnfN = {}, "", "", "", {}, 0
	for part in chunks(body, pat) do
		local r = decodeObj(part)
		if r then
			local drv = type(r.Driver) == "table" and r.Driver or {}
			local con = type(r.Constructor) == "table" and r.Constructor or {}
			local family = str(drv.familyName, 19)
			local status = type(r.status) == "string" and r.status or ""
			local ft = type(r.FastestLap) == "table" and r.FastestLap or nil
			if ft and ft.rank == "1" then
				fl = family
				flTime = ft.Time and str(ft.Time.time, 11) or ""
			end
			if r.grid == "1" then pole = family end
			local finished = status == "Finished" or status:sub(1, 1) == "+"
			if not finished and dnfN < 2 then
				dnf[#dnf + 1] = family .. ":" .. (tonumber(r.laps) or 0)
				dnfN = dnfN + 1
			end
			if #rows < RESULT_MAX then
				local gap
				if type(r.Time) == "table" and type(r.Time.time) == "string" and r.Time.time ~= "" then gap = str(r.Time.time, 15)
				elseif status:sub(1, 1) == "+" then gap = "+" .. (tonumber(status:match("^%+(%d+)")) or 1) .. "L"
				else gap = "DNF" end
				rows[#rows + 1] = table.concat({ "R", tonumber(r.position) or (#rows + 1), family, shortTeam(str(con.name, 30)):sub(1, 21), gap }, "\t")
			end
		end
	end
	if #rows == 0 then return false end
	local head = table.concat({ "H", round, str(cir.circuitId, 28), str(hd.raceName, 40), dateE, fl, flTime, pole, table.concat(dnf, ";") }, "\t")
	file.write("last", head .. "\n" .. table.concat(rows, "\n"))
	ctx.data.set("res_r", round)
	ctx.data.set("res_t", time.now())
	return true
end

local function fetchStandings(ctx, drivers)
	local body = get(JOLPICA .. (drivers and "current/driverstandings.json" or "current/constructorstandings.json"), 40000)
	if not body then return false end
	local round = tonumber(body:match('"StandingsLists":%[{"season":"%d+","round":"(%d+)"')) or 0
	local rows = {}
	for part in chunks(body, '{"position":"%d+","positionText"') do
		local r = decodeObj(part)
		if r then
			local pos = tonumber(r.position) or (#rows + 1)
			local pts = tonumber(r.points) or 0
			if drivers and #rows < DRV_MAX then
				local d = type(r.Driver) == "table" and r.Driver or {}
				local c = type(r.Constructors) == "table" and type(r.Constructors[1]) == "table" and r.Constructors[1] or {}
				rows[#rows + 1] = table.concat({ "D", pos, str(d.familyName, 19), teamCode(c.constructorId, c.name), string.format("%.1f", pts) }, "\t")
			elseif not drivers and #rows < TEAM_MAX then
				local c = type(r.Constructor) == "table" and r.Constructor or {}
				rows[#rows + 1] = table.concat({ "T", pos, shortTeam(str(c.name, 30)):sub(1, 21), string.format("%.1f", pts) }, "\t")
			end
		end
	end
	if #rows == 0 then return false end
	file.write(drivers and "drv" or "con", "R\t" .. round .. "\n" .. table.concat(rows, "\n"))
	if drivers then
		ctx.data.set("std_r", round)
		ctx.data.set("std_t", time.now())
	end
	return true
end

local function lapText(secs)
	if secs == nil or secs <= 0 then return "-" end
	local m = math.floor(secs / 60)
	local rem = secs - m * 60
	if m > 0 then return string.format("%d:%06.3f", m, rem) end
	return string.format("%.3f", rem)
end

local function pickSession(list, now)
	local best, bestEnd = nil, 0
	for _, s in ipairs(list) do
		if type(s) == "table" then
			local e = parseIso(s.date_end)
			if e and e <= now and e > bestEnd then best, bestEnd = s, e end
		end
	end
	if not best then return "race" end
	local ty = type(best.session_type) == "string" and best.session_type or ""
	local nm = type(best.session_name) == "string" and best.session_name or ""
	if ty == "Race" then return "race" end
	local kind
	if nm:find("Sprint Qualifying", 1, true) or nm:find("Sprint Shootout", 1, true) then kind = "sq"
	elseif ty == "Sprint" then kind = "s"
	elseif ty == "Qualifying" then kind = "q"
	elseif nm:find("Practice 1", 1, true) then kind = "p1"
	elseif nm:find("Practice 2", 1, true) then kind = "p2"
	elseif nm:find("Practice 3", 1, true) then kind = "p3"
	else return "race" end
	return kind, tonumber(best.session_key)
end

local function fetchSessionTable(ctx, kind, key, lapRecord)
	local body = get(OPENF1 .. "drivers?session_key=" .. key)
	local list = body and json.decode(body)
	if type(list) ~= "table" then return false end
	local drivers = {}
	for _, d in ipairs(list) do
		if type(d) == "table" and d.driver_number then
			drivers[d.driver_number] = { code = str(d.name_acronym, 3), team = shortTeam(str(d.team_name, 30)):sub(1, 21) }
		end
	end

	local practice = kind == "p1" or kind == "p2" or kind == "p3"
	local entries = {}   -- { num, pos, dur, dnf, dsq, dns }
	body = get(OPENF1 .. "session_result?session_key=" .. key)
	local res = body and json.decode(body)
	if type(res) == "table" then
		for _, r in ipairs(res) do
			if type(r) == "table" and r.driver_number then
				local dur = 0
				if type(r.duration) == "table" then
					for i = 1, 3 do if type(r.duration[i]) == "number" then dur = r.duration[i] end end
				elseif type(r.duration) == "number" then dur = r.duration end
				entries[#entries + 1] = { num = r.driver_number, pos = tonumber(r.position) or 99, dur = dur,
					dnf = r.dnf == true, dsq = r.dsq == true, dns = r.dns == true }
			end
		end
	elseif body == nil and not practice then
		return false
	end
	table.sort(entries, function(a, b) return a.pos < b.pos end)

	if practice and (#entries == 0 or entries[1].dur <= 0) then
		local url = OPENF1 .. "laps?session_key=" .. key
		if lapRecord then url = url .. "&lap_duration<" .. string.format("%d", math.floor(lapRecord * 1.12)) end
		body = get(url, 65536)
		if not body then return false end
		local best, order = {}, {}
		for obj in body:gmatch("%b{}") do
			local num = tonumber(obj:match('"driver_number":%s*(%d+)'))
			local dur = tonumber(obj:match('"lap_duration":%s*(%d+%.?%d*)'))
			if num and dur and dur > 0 then
				if best[num] == nil then best[num] = dur; order[#order + 1] = num
				elseif dur < best[num] then best[num] = dur end
			end
		end
		entries = {}
		for _, num in ipairs(order) do entries[#entries + 1] = { num = num, pos = 0, dur = best[num], dnf = false, dsq = false, dns = false } end
		table.sort(entries, function(a, b) return a.dur < b.dur end)
		for i, e in ipairs(entries) do e.pos = i end
	end
	if #entries == 0 then return false end

	local fastest = entries[1].dur
	local rows = {}
	for i, e in ipairs(entries) do
		if #rows >= RESULT_MAX then break end
		local d = drivers[e.num]
		local t
		if e.dsq then t = "DSQ"
		elseif e.dns then t = "DNS"
		elseif e.dnf then t = "DNF"
		elseif i == 1 or fastest <= 0 or e.dur <= 0 then t = lapText(e.dur)
		else t = string.format("+%.3f", e.dur - fastest) end
		rows[#rows + 1] = table.concat({ "R", d and d.code or "?", d and d.team or "", t }, "\t")
	end
	file.write("sess", "H\t" .. kind .. "\t" .. key .. "\n" .. table.concat(rows, "\n"))
	return true
end

local ERR_TEXT = {
	cal = { "Rennkalender-Abruf fehlgeschlagen.", "Schedule fetch failed." },
	res = { "Ergebnis-Abruf fehlgeschlagen.", "Result fetch failed." },
	drv = { "Fahrerwertung-Abruf fehlgeschlagen.", "Driver standings fetch failed." },
	con = { "Konstrukteurswertung-Abruf fehlgeschlagen.", "Constructor standings fetch failed." },
}

function on_fetch(ctx)
	EN = ctx.lang == "en"
	resetData()
	NET.n = 0
	local now = time.now()
	if now == nil or now < 1700000000 then return false end   -- Uhr noch nicht synchron
	local progressed, firstErr = false, nil
	local function fail(code) if firstErr == nil then firstErr = code end end

	local calText = file.read("cal")
	local calT = tonumber(ctx.data.get("cal_t")) or 0
	if calText == nil or calText == "" or now - calT >= 12 * 3600 or now < calT then
		local fresh = fetchCalendar(ctx)
		if fresh then progressed = true; calText = fresh else fail("cal") end
	end
	local cal = parseCal(calText)
	local nxt = pickNext(cal, now)
	local total = totalRounds(cal)
	local expected = nxt and (nxt.round - 1) or total   -- Rennen, die schon gefahren sein muessen

	local function due(roundKey, timeKey)
		local r, t = tonumber(ctx.data.get(roundKey)), tonumber(ctx.data.get(timeKey))
		if r == nil or t == nil or now < t or now - t >= 24 * 3600 then return true end
		return r < expected and now - t >= 55 * 60
	end
	if #cal > 0 then
		if due("res_r", "res_t") then
			if fetchLast(ctx) then progressed = true else fail("res") end
		end
		if due("std_r", "std_t") then
			if fetchStandings(ctx, true) then progressed = true else fail("drv") end
			if fetchStandings(ctx, false) then progressed = true else fail("con") end
		end
	end

	local kind = ctx.data.get("sk")
	if nxt then
		local first = nxt.sess[1] and nxt.sess[1].s or (nxt.start - 3 * 86400)
		if now >= first - 3600 and NET.n < 6 then
			local body = get(OPENF1 .. "sessions?meeting_key=latest")
			local list = body and json.decode(body)
			if type(list) == "table" then
				local k, key = pickSession(list, now)
				if k == "race" then
					ctx.data.set("sk", "race")
				elseif ctx.data.get("sk") == k and tonumber(ctx.data.get("sk_key")) == key and file.read("sess") then
				elseif NET.n <= 3 then
					local ci = CIRCUITS[nxt.cid]
					local rec = nil
					if ci and ci.rec then
						local m, s = ci.rec:match("^(%d+):(%d+)")
						if m then rec = tonumber(m) * 60 + tonumber(s) end
					end
					if fetchSessionTable(ctx, k, key, rec) then
						ctx.data.set("sk", k)
						ctx.data.set("sk_key", key)
						progressed = true
					end
				end
			end
		elseif now < first - 3600 then
			if kind ~= "race" then ctx.data.set("sk", "race") end
		end
	elseif kind ~= "race" then
		ctx.data.set("sk", "race")
	end

	if progressed then return true end
	if firstErr ~= nil then
		if #cal == 0 then file.write("err", firstErr) end
		return false
	end
	return true
end

local function errText(code)
	local e = ERR_TEXT[code]
	if e then return EN and e[2] or e[1] end
	return T("Nächster Versuch in Kürze.", "Retrying shortly.")
end

local OFFS = { { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- Zeile "cid|ok|x,y,..." aus assets/tracks.txt: Punktliste und ob Start/Ziel-Markierung und Richtung geprueft sind
local function trackOf(cid)
	local txt = asset.read("tracks")
	local a = txt and cid and txt:find("\n" .. cid .. "|", 1, true)
	if not a then return nil end
	local ok, pts = txt:match("^|(%d)|([%d,]+)", a + #cid + 1)
	if not pts then return nil end
	local t = {}
	for v in pts:gmatch("%d+") do t[#t + 1] = tonumber(v) end
	return t, ok == "1"
end

local function drawTrack(x, y, w, h, cid)
	local t, verified = trackOf(cid)
	if t == nil then
		local rx, ry, rw, rh = x + w // 6, y + h // 5, w * 2 // 3, h * 3 // 5
		for off = 0, 2 do draw.rect(rx + off, ry + off, rw - 2 * off, rh - 2 * off, color.BLACK, false, rh // 3) end
		draw.circle(rx + rw // 2, ry + rh, 5, color.ACCENT, true)
		return
	end
	local n = #t // 2
	local minX, maxX, minY, maxY = 255, 0, 255, 0
	for i = 1, n do
		local px, py = t[2 * i - 1], t[2 * i]
		if px < minX then minX = px end
		if px > maxX then maxX = px end
		if py < minY then minY = py end
		if py > maxY then maxY = py end
	end
	local spanX = math.max(maxX - minX, 1)
	local spanY = math.max(maxY - minY, 1)
	local scale = math.min((w - 12) / spanX, (h - 12) / spanY)
	local drawW, drawH = math.floor(spanX * scale), math.floor(spanY * scale)
	local ox, oy = x + (w - drawW) // 2, y + (h - drawH) // 2
	local rawX, rawY = {}, {}
	for i = 1, n do
		rawX[i] = ox + (t[2 * i - 1] - minX) * scale
		rawY[i] = oy + (t[2 * i] - minY) * scale
	end
	local cx, cy = {}, {}
	for i = 1, n do cx[i] = rawX[i]; cy[i] = rawY[i] end
	for _ = 1, 3 do
		local nx, ny = {}, {}
		local m = #cx
		for i = 1, m do
			local j = i % m + 1
			local dx, dy = cx[j] - cx[i], cy[j] - cy[i]
			nx[#nx + 1] = cx[i] + dx * 0.25
			ny[#ny + 1] = cy[i] + dy * 0.25
			nx[#nx + 1] = cx[i] + dx * 0.75
			ny[#ny + 1] = cy[i] + dy * 0.75
		end
		cx, cy = nx, ny
	end
	local m = #cx
	for i = 1, m do
		local j = i % m + 1
		local x0, y0, x1, y1 = math.floor(cx[i]), math.floor(cy[i]), math.floor(cx[j]), math.floor(cy[j])
		for o = 1, 5 do
			draw.line(x0 + OFFS[o][1], y0 + OFFS[o][2], x1 + OFFS[o][1], y1 + OFFS[o][2], color.BLACK)
		end
	end

	local sx, sy = math.floor(rawX[1]), math.floor(rawY[1])
	if verified then
		local tdx, tdy = rawX[2] - rawX[1], rawY[2] - rawY[1]
		local tlen = math.sqrt(tdx * tdx + tdy * tdy)
		if tlen < 0.001 then tlen = 1 end
		tdx, tdy = tdx / tlen, tdy / tlen
		local pdx, pdy = -tdy, tdx   -- quer zur Strecke
		local tick = 7
		local lx0, ly0 = math.floor(sx - pdx * tick), math.floor(sy - pdy * tick)
		local lx1, ly1 = math.floor(sx + pdx * tick), math.floor(sy + pdy * tick)
		draw.line(lx0, ly0, lx1, ly1, color.BLACK)
		draw.line(lx0 + 1, ly0, lx1 + 1, ly1, color.BLACK)
		local ax, ay = math.floor(sx + tdx * 12), math.floor(sy + tdy * 12)
		draw.triangle(math.floor(ax + tdx * 6), math.floor(ay + tdy * 6),
			math.floor(ax - tdx * 4 - pdx * 4), math.floor(ay - tdy * 4 - pdy * 4),
			math.floor(ax - tdx * 4 + pdx * 4), math.floor(ay - tdy * 4 + pdy * 4), color.BLACK, true)
	end
	draw.circle(sx, sy, 6, color.ACCENT, true)
	draw.circle(sx, sy, 2, color.WHITE, true)
end

local function pill(x, y, text, big)
	local font = big and "normal" or "small"
	local tw = draw.measure(text, font)
	local h = big and 30 or 24
	local w = tw + (big and 26 or 20)
	draw.rect(x, y, w, h, color.ACCENT, true, h // 2)
	draw.text(x + (w - tw) // 2, y + h - (big and 9 or 7), text, font, color.ACCENT_INK, "left")
	return w
end

local function posBadge(x, y, size, r, pos, podium, font)
	if podium then
		draw.rect(x, y, size, size, color.ACCENT, true, r)
		draw.text(x + size // 2, y + size - 5, tostring(pos), font, color.ACCENT_INK, "center")
	else
		draw.rect(x, y, size, size, color.BLACK, false, r)
		draw.text(x + size // 2, y + size - 5, tostring(pos), font, color.BLACK, "center")
	end
end

local function gapText(g)
	local n = g:match("^%+(%d+)L$")
	if n then return string.format(T("+%d Rd.", "+%d lap"), tonumber(n)) end
	return dsp(g)
end

local function dnfText(s)
	local out = {}
	for name, laps in s:gmatch("([^;:]+):(%d+)") do
		out[#out + 1] = string.format(T("%s (Rd. %d)", "%s (lap %d)"), name, tonumber(laps))
	end
	return table.concat(out, ", ")
end

local function allSessions(n)
	local out = {}
	for _, s in ipairs(n.sess) do out[#out + 1] = s end
	out[#out + 1] = { t = "r", s = n.start }
	return out
end

local function emptyState()
	if #getCal() > 0 or getLast() or #getStand("drv").rows > 0 then return false end
	local err = file.read("err")
	if err and err ~= "" then
		notice("warning", T("Abruf fehlgeschlagen.", "Fetch failed."), errText(err))
	else
		notice("clock", T("Wird geladen ...", "Loading ..."))
	end
	return true
end

local function nextOrNotice(ctx)
	local cal = getCal()
	local n = pickNext(cal, time.now())
	if ctx.sample and n == nil then
		local ci = CIRCUITS.monza
		n = { round = 15, cid = "monza", name = "Italian Grand Prix", circuit = "Autodromo Nazionale di Monza", loc = "Monza", country = "Italy",
			start = time.now() + 6 * 86400 + 3600, sess = {} }
		n.sess = { { t = "p1", s = n.start - 2 * 86400 }, { t = "p2", s = n.start - 2 * 86400 + 4 * 3600 }, { t = "p3", s = n.start - 86400 }, { t = "q", s = n.start - 86400 + 4 * 3600 } }
		return n, 24
	end
	if n == nil then
		if #cal > 0 then
			notice("flag", T("Saison beendet.", "Season finished."), T("Kein weiteres Rennen im Kalender.", "No more races on the calendar."))
		else
			notice("flag", T("Kein Rennen im Kalender gefunden.", "No race found on the calendar."))
		end
		return nil
	end
	return n, totalRounds(cal)
end

local function raceLine(n)
	return string.format(T("%s · %s Uhr", "%s · %s"), fmtDate(n.start), fmtTime(n.start))
end

local function statLine(ci, long)
	if long then
		return string.format(T("%s · %d Runden · %d Kurven", "%s · %d laps · %d corners"), fmtKm(ci.len), ci.laps, ci.corners)
	end
	return string.format(T("%s · %d Rd. · %d Kv.", "%s · %d laps · %d corners"), fmtKm(ci.len), ci.laps, ci.corners)
end

local function nextBento(n, total)
	local y = draw.top + 2
	local bottom = draw.height - 14
	local ci = CIRCUITS[n.cid]
	local leftX, leftW, rightX = 20, 460, 492
	local rightW = draw.width - rightX - 20
	local cardH = 232

	card(leftX, y, leftW, cardH, color.ACCENT, 12)
	local cx = leftX + 24
	pill(cx, y + 16, string.format(T("RUNDE %d/%d", "ROUND %d/%d"), n.round, total), false)
	draw.text(cx, y + 84, fit(gpName(n.cid, n.name), leftW - 48, "large"), "large", color.BLACK, "left")
	draw.text(cx, y + 114, fit(n.circuit, leftW - 48, "normal"), "normal", color.BLACK, "left")
	draw.text(cx, y + 138, fit(n.loc .. ", " .. n.country, leftW - 48, "normal"), "normal", color.BLACK, "left")
	draw.text(cx, y + 168, raceLine(n), "normal", color.BLACK, "left")
	pill(cx, y + 186, countdown(n.start, true), true)

	draw.rect(rightX, y, rightW, cardH, color.BLACK, false, 12)
	drawTrack(rightX + 16, y + 12, rightW - 32, 140, n.cid)
	local mid = rightX + rightW // 2
	if ci then
		draw.text(mid, y + 176, fit(statLine(ci, true), rightW - 24, "small"), "small", color.BLACK, "center")
		local rec = ci.rec and string.format(T("Rundenrekord %s", "Lap record %s"), dsp(ci.rec)) or T("Noch kein Rundenrekord", "No lap record yet")
		draw.text(mid, y + 200, fit(rec, rightW - 24, "small"), "small", color.BLACK, "center")
	else
		draw.text(mid, y + 188, fit(n.loc .. ", " .. n.country, rightW - 24, "small"), "small", color.BLACK, "center")
	end

	local schedY = y + cardH + 14
	local schedH = bottom - schedY
	if schedH < 90 then return end
	draw.rect(leftX, schedY, draw.width - 2 * leftX, schedH, color.BLACK, false, 12)
	draw.text(leftX + 22, schedY + 26, T("ZEITPLAN", "SCHEDULE"), "small", color.BLACK, "left")
	local sess = allSessions(n)
	local cnt = #sess
	local colsX = leftX + 22
	local colW = (draw.width - 2 * leftX - 44) // cnt
	for i, s in ipairs(sess) do
		local cc = colsX + (i - 1) * colW + colW // 2
		draw.text(cc, schedY + 56, fit(lab(SES_LABEL, s.t), colW - 10, "small"), "small", color.BLACK, "center")
		draw.text(cc, schedY + 82, fmtDate(s.s), "small", color.BLACK, "center")
		local tt = fmtTime(s.s)
		if s.t == "r" then
			local pw = draw.measure(tt, "normal") + 26
			pill(cc - pw // 2, schedY + 94, tt, true)
		else
			draw.text(cc, schedY + 116, tt, "normal", color.BLACK, "center")
		end
	end
end

local function nextSlate(n, total)
	local y = draw.top + 2
	local bottom = draw.height - 14
	local W = draw.width
	local cx = W // 2
	local ci = CIRCUITS[n.cid]
	draw.text(cx, y + 44, fit(gpName(n.cid, n.name), W - 48, "large"), "large", color.BLACK, "center")
	local info = string.format(T("Runde %d/%d · %s · %s, %s", "Round %d/%d · %s · %s, %s"), n.round, total, n.circuit, n.loc, n.country)
	draw.text(cx, y + 74, fit(info, W - 48, "normal"), "normal", color.BLACK, "center")
	if ci then
		local s
		if ci.rec then
			s = string.format(T("%s · %d Runden · %d Kurven · Rekord %s", "%s · %d laps · %d corners · Record %s"), fmtKm(ci.len), ci.laps, ci.corners, dsp(ci.rec))
		else
			s = statLine(ci, true)
		end
		draw.text(cx, y + 98, fit(s, W - 48, "small"), "small", color.BLACK, "center")
	end
	draw.text(cx, y + 128, raceLine(n), "normal", color.BLACK, "center")
	local cd = countdown(n.start, true)
	local pw = draw.measure(cd, "normal") + 26
	pill(cx - pw // 2, y + 142, cd, true)

	local trackTop, trackBottom = y + 186, bottom - 52
	if trackBottom - trackTop > 60 then drawTrack(cx - 190, trackTop, 380, trackBottom - trackTop, n.cid) end

	draw.line(40, bottom - 40, W - 40, bottom - 40, color.BLACK)
	local parts = {}
	for _, s in ipairs(allSessions(n)) do
		parts[#parts + 1] = lab(SES_SHORT, s.t) .. " " .. wdName(localParts(s.s)) .. " " .. fmtTime(s.s)
	end
	draw.text(cx, bottom - 14, fit(table.concat(parts, " · "), W - 48, "small"), "small", color.BLACK, "center")
end

local function nextNano(n, total)
	local y = draw.top + 6
	local bottom = draw.height - 14
	local leftX, rightX = 24, draw.width - 24
	local ci = CIRCUITS[n.cid]

	local rd = string.format(T("Lauf %d/%d", "Rd %d/%d"), n.round, total)
	local rdW = draw.measure(rd, "normal")
	draw.text(rightX, y + 22, rd, "normal", color.BLACK, "right")
	draw.text(leftX, y + 22, fit(gpName(n.cid, n.name), rightX - rdW - 16 - leftX, "normal"), "normal", color.BLACK, "left")

	local right = ci and statLine(ci, false) or ""
	local rW = draw.measure(right, "small")
	draw.text(rightX, y + 48, right, "small", color.BLACK, "right")
	draw.text(leftX, y + 48, fit(n.circuit .. ", " .. n.country, rightX - rW - 16 - leftX, "small"), "small", color.BLACK, "left")
	if ci and ci.rec then
		draw.text(leftX, y + 70, string.format(T("Rundenrekord %s", "Lap record %s"), dsp(ci.rec)), "small", color.BLACK, "left")
	end
	draw.line(leftX, y + 84, rightX, y + 84, color.BLACK)

	local sess = allSessions(n)
	local cnt = #sess
	local rowTop = y + 86
	local rowH = (bottom - 44 - rowTop) // cnt
	if rowH > 34 then rowH = 34 end
	if rowH < 22 then rowH = 22 end
	local whens, maxWhenW = {}, 0
	for i, s in ipairs(sess) do
		whens[i] = fmtDate(s.s) .. " " .. fmtTime(s.s)
		maxWhenW = math.max(maxWhenW, draw.measure(whens[i], "small"))
	end
	for i, s in ipairs(sess) do
		local base = rowTop + (i - 1) * rowH + rowH - 8
		if s.t == "r" then draw.circle(leftX + 5, base - 5, 5, color.ACCENT, true) end
		draw.text(leftX + 18, base, fit(lab(SES_LABEL, s.t), rightX - maxWhenW - 20 - (leftX + 18), "small"), "small", color.BLACK, "left")
		draw.text(rightX, base, whens[i], "small", color.BLACK, "right")
		if i < cnt then draw.line(leftX, rowTop + i * rowH, rightX, rowTop + i * rowH, color.BLACK) end
	end

	local cdY = rowTop + cnt * rowH + 8
	draw.line(leftX, cdY, rightX, cdY, color.BLACK)
	draw.text(leftX, cdY + 28, "Countdown", "normal", color.BLACK, "left")
	local cd = countdown(n.start, false)
	local cdW = draw.measure(cd, "normal")
	draw.circle(rightX - cdW - 16, cdY + 22, 5, color.ACCENT, true)
	draw.text(rightX, cdY + 28, cd, "normal", color.BLACK, "right")
end

local function maxPtsWidth(rows)
	local w = 0
	for _, r in ipairs(rows) do w = math.max(w, draw.measure(fmtPoints(r.points), "normal")) end
	return w
end

local function standRow(x, baseline, r, ptsRight, maxPtsW)
	posBadge(x, baseline - 18, 24, 6, r.pos, r.pos >= 1 and r.pos <= 3, "small")
	draw.text(ptsRight, baseline, fmtPoints(r.points), "normal", color.BLACK, "right")
	local codeRight = ptsRight - maxPtsW - 18
	local codeW = 0
	if r.code ~= "" then
		draw.text(codeRight, baseline, r.code, "small", color.BLACK, "right")
		codeW = draw.measure(r.code, "small") + 14
	end
	draw.text(x + 36, baseline, fit(r.name, codeRight - codeW - (x + 36), "normal"), "normal", color.BLACK, "left")
end

local function standBento(drv, con)
	local y = draw.top + 2
	local bottom = draw.height - 14
	local cardH = bottom - y
	local cardW, leftX = 372, 20
	local rightX = draw.width - 20 - cardW
	card(leftX, y, cardW, cardH, color.ACCENT, 12)
	card(rightX, y, cardW, cardH, color.ACCENT, 12)
	draw.text(leftX + 24, y + 26, T("FAHRERWERTUNG", "DRIVER STANDINGS"), "small", color.BLACK, "left")
	draw.text(rightX + 24, y + 26, T("KONSTRUKTEURSWERTUNG", "CONSTRUCTOR STANDINGS"), "small", color.BLACK, "left")
	local rowsTop, rowsH = y + 40, cardH - 54
	local dH = #drv.rows > 0 and rowsH // #drv.rows or rowsH
	local mD = maxPtsWidth(drv.rows)
	for i, r in ipairs(drv.rows) do
		standRow(leftX + 24, rowsTop + (i - 1) * dH + dH // 2 + 8, r, leftX + cardW - 24, mD)
	end
	local tH = #con.rows > 0 and rowsH // #con.rows or rowsH
	local mT = maxPtsWidth(con.rows)
	for i, r in ipairs(con.rows) do
		standRow(rightX + 24, rowsTop + (i - 1) * tH + tH // 2 + 8, r, rightX + cardW - 24, mT)
	end
end

local function standSlate(drv, con)
	local y = draw.top + 2
	local bottom = draw.height - 14
	local cx = draw.width // 2
	draw.line(cx, y + 6, cx, bottom - 6, color.BLACK)
	local leftX, leftRight, rightX, rightRight = 28, cx - 28, cx + 28, draw.width - 28
	draw.text(leftX, y + 22, T("FAHRERWERTUNG", "DRIVER STANDINGS"), "small", color.BLACK, "left")
	draw.text(rightX, y + 22, T("KONSTRUKTEURSWERTUNG", "CONSTRUCTOR STANDINGS"), "small", color.BLACK, "left")
	local rowsTop = y + 36
	local rowsH = bottom - rowsTop - 6
	local dH = #drv.rows > 0 and rowsH // #drv.rows or rowsH
	local mD = maxPtsWidth(drv.rows)
	for i, r in ipairs(drv.rows) do
		standRow(leftX, rowsTop + (i - 1) * dH + dH // 2 + 8, r, leftRight, mD)
		if i < #drv.rows then draw.line(leftX, rowsTop + i * dH, leftRight, rowsTop + i * dH, color.BLACK) end
	end
	local tH = #con.rows > 0 and rowsH // #con.rows or rowsH
	local mT = maxPtsWidth(con.rows)
	for i, r in ipairs(con.rows) do
		standRow(rightX, rowsTop + (i - 1) * tH + tH // 2 + 8, r, rightRight, mT)
		if i < #con.rows then draw.line(rightX, rowsTop + i * tH, rightRight, rowsTop + i * tH, color.BLACK) end
	end
end

local function standNano(drv, con, total)
	local y = draw.top + 2
	local bottom = draw.height - 14
	local leftX = 24
	local totalRows = 2 + #drv.rows + #con.rows
	local rowH = (bottom - y - 8) // totalRows
	if rowH > 28 then rowH = 28 end
	if rowH < 20 then rowH = 20 end
	local cur = y + 4
	local head
	if drv.round > 0 then
		head = string.format(T("FAHRERWERTUNG NACH RD %d/%d", "DRIVER STANDINGS AFTER RD %d/%d"), drv.round, total)
	else
		head = T("FAHRERWERTUNG", "DRIVER STANDINGS")
	end
	draw.text(leftX, cur + rowH - 6, head, "small", color.BLACK, "left")
	cur = cur + rowH
	for _, r in ipairs(drv.rows) do
		local s = string.format(T("P%d %s (%s) - %s Pkt.", "P%d %s (%s) - %s pts"), r.pos, r.name, r.code, fmtPoints(r.points))
		draw.text(leftX, cur + rowH - 6, fit(s, draw.width - 2 * leftX, "small"), "small", color.BLACK, "left")
		cur = cur + rowH
	end
	draw.text(leftX, cur + rowH - 6, T("KONSTRUKTEURSWERTUNG", "CONSTRUCTOR STANDINGS"), "small", color.BLACK, "left")
	cur = cur + rowH
	for _, r in ipairs(con.rows) do
		local s = string.format(T("P%d %s - %s Pkt.", "P%d %s - %s pts"), r.pos, r.name, fmtPoints(r.points))
		draw.text(leftX, cur + rowH - 6, fit(s, draw.width - 2 * leftX, "small"), "small", color.BLACK, "left")
		cur = cur + rowH
	end
end

local function drawStandings(ctx, style)
	if emptyState() then return end
	local drv, con = getStand("drv"), getStand("con")
	if #drv.rows == 0 and #con.rows == 0 then
		notice("flag", T("Noch keine Wertung verfügbar.", "No standings available yet."))
		return
	end
	if style == "flat" then standSlate(drv, con)
	elseif style == "compact" then standNano(drv, con, totalRounds(getCal()))
	else standBento(drv, con) end
end

local function maxGapWidth(rows, count, font)
	local w = 0
	for i = 1, math.min(count, #rows) do w = math.max(w, draw.measure(gapText(rows[i].gap), font)) end
	return w
end

local function lastBento(L)
	local y = draw.top + 2
	local bottom = draw.height - 14
	local headX = 20
	local headW = draw.width - 2 * headX
	local headH = 84
	card(headX, y, headW, headH, color.ACCENT, 12)
	draw.text(headX + 24, y + 26, string.format(T("RUNDE %d · %s", "ROUND %d · %s"), L.round, fmtDate(L.date)), "small", color.BLACK, "left")

	local win = L.rows[1]
	local winnerLine = win.driver .. " · " .. win.team
	local winnerW = draw.measure(winnerLine, "normal")
	local siegerW = draw.measure(T("SIEGER", "WINNER"), "small")
	local winnerBlockW = math.max(winnerW, siegerW)
	local winnerRight = headX + headW - 24
	draw.text(winnerRight, y + 26, T("SIEGER", "WINNER"), "small", color.BLACK, "right")
	draw.text(winnerRight, y + 56, winnerLine, "normal", color.BLACK, "right")
	draw.text(headX + 24, y + 68, fit(gpName(L.cid, L.name), winnerRight - winnerBlockW - 24 - (headX + 24), "large"), "large", color.BLACK, "left")

	local y2 = y + headH + 14
	local mainH = bottom - y2
	local listW = 460
	draw.rect(headX, y2, listW, mainH, color.BLACK, false, 12)
	local rows = math.min(#L.rows, 8)
	local rowH = (mainH - 24) // math.max(rows, 1)
	local maxGapW = maxGapWidth(L.rows, rows, "normal")
	local gapRight = headX + listW - 20
	for i = 1, rows do
		local r = L.rows[i]
		local base = y2 + 12 + (i - 1) * rowH + rowH // 2 + 6
		local b = 22
		local by = base - 16
		if r.pos <= 3 then
			draw.rect(headX + 18, by, b, b, color.ACCENT, true, 5)
			draw.text(headX + 18 + b // 2, by + 16, tostring(r.pos), "small", color.ACCENT_INK, "center")
		else
			draw.rect(headX + 18, by, b, b, color.BLACK, false, 5)
			draw.text(headX + 18 + b // 2, by + 16, tostring(r.pos), "small", color.BLACK, "center")
		end
		draw.text(gapRight, base, gapText(r.gap), "normal", color.BLACK, "right")
		draw.text(headX + 52, base, fit(r.driver, 128, "normal"), "normal", color.BLACK, "left")
		draw.text(headX + 190, base, fit(r.team, gapRight - maxGapW - 14 - (headX + 190), "small"), "small", color.BLACK, "left")
	end

	local infoX = headX + listW + 12
	local infoW = draw.width - 20 - infoX
	local infoH = (mainH - 20) // 3
	local labels = { T("SCHN. RUNDE", "FASTEST LAP"), T("AUSFÄLLE", "RETIREMENTS"), T("POLE-POSITION", "POLE POSITION") }
	for c = 1, 3 do
		local cy = y2 + (c - 1) * (infoH + 10)
		draw.rect(infoX, cy, infoW, infoH, color.BLACK, false, 10)
		draw.text(infoX + 16, cy + 24, labels[c], "small", color.BLACK, "left")
		local v
		if c == 1 then
			v = L.flDriver ~= "" and (L.flDriver .. " · " .. dsp(L.flTime)) or "-"
		elseif c == 2 then
			v = L.dnf ~= "" and dnfText(L.dnf) or T("keine", "none")
		else
			v = L.pole ~= "" and L.pole or "-"
		end
		local lines = wrapLines(v, infoW - 32, "normal", 2)
		for l, line in ipairs(lines) do
			draw.text(infoX + 16, cy + 52 + (l - 1) * 24, line, "normal", color.BLACK, "left")
		end
	end
end

local function lastSlate(L)
	local y = draw.top + 2
	local bottom = draw.height - 14
	local leftX, rightX = 28, draw.width - 28
	local head = string.format(T("%s · Lauf %d · %s", "%s · Rd %d · %s"), gpName(L.cid, L.name), L.round, fmtDate(L.date))
	draw.text(leftX, y + 24, fit(head, rightX - leftX, "normal"), "normal", color.BLACK, "left")
	local rows = math.min(#L.rows, RESULT_MAX)
	local rowsTop = y + 40
	local rowH = (bottom - rowsTop) // math.max(rows, 1)
	local maxGapW = maxGapWidth(L.rows, rows, "normal")
	local lineX = rightX - maxGapW - 18
	draw.line(lineX, rowsTop, lineX, rowsTop + rows * rowH, color.BLACK)
	for i = 1, rows do
		local r = L.rows[i]
		local base = rowsTop + (i - 1) * rowH + rowH // 2 + 6
		if r.pos <= 3 then
			draw.circle(leftX + 10, base - 6, 11, color.ACCENT, true)
			draw.text(leftX + 10, base, tostring(r.pos), "normal", color.ACCENT_INK, "center")
		else
			draw.text(leftX + 10, base, tostring(r.pos), "normal", color.BLACK, "center")
		end
		draw.text(leftX + 40, base, fit(r.driver, 170, "normal"), "normal", color.BLACK, "left")
		draw.text(leftX + 224, base, fit(r.team, lineX - 16 - (leftX + 224), "small"), "small", color.BLACK, "left")
		draw.text(rightX, base, gapText(r.gap), "normal", color.BLACK, "right")
		if i < rows then draw.line(leftX, rowsTop + i * rowH, rightX, rowsTop + i * rowH, color.BLACK) end
	end
end

local function lastNano(L)
	local y = draw.top + 2
	local bottom = draw.height - 14
	local leftX, rightX = 24, draw.width - 24
	local dateS = fmtDate(L.date)
	local dW = draw.measure(dateS, "small")
	draw.text(rightX, y + 18, dateS, "small", color.BLACK, "right")
	local head = string.format(T("%s · Lauf %d", "%s · Rd %d"), gpName(L.cid, L.name), L.round)
	draw.text(leftX, y + 18, fit(head, rightX - dW - 16 - leftX, "small"), "small", color.BLACK, "left")

	local rows = math.min(#L.rows, RESULT_MAX)
	local rowsTop = y + 30
	local footerH = 30
	local rowH = (bottom - footerH - rowsTop) // math.max(rows, 1)
	local maxGapW = maxGapWidth(L.rows, rows, "small")
	for i = 1, rows do
		local r = L.rows[i]
		local base = rowsTop + (i - 1) * rowH + rowH // 2 + 5
		local b = 18
		local by = base - 14
		if r.pos <= 3 then
			draw.rect(leftX, by, b, b, color.ACCENT, true, 4)
			draw.text(leftX + b // 2, by + 14, tostring(r.pos), "small", color.ACCENT_INK, "center")
		else
			draw.rect(leftX, by, b, b, color.BLACK, false, 4)
			draw.text(leftX + b // 2, by + 14, tostring(r.pos), "small", color.BLACK, "center")
		end
		draw.text(leftX + 30, base, fit(r.driver, 150, "small"), "small", color.BLACK, "left")
		draw.text(leftX + 190, base, fit(r.team, rightX - maxGapW - 14 - (leftX + 190), "small"), "small", color.BLACK, "left")
		draw.text(rightX, base, gapText(r.gap), "small", color.BLACK, "right")
		if i < rows then draw.line(leftX, rowsTop + i * rowH, rightX, rowsTop + i * rowH, color.BLACK) end
	end
	draw.line(leftX, bottom - footerH + 4, rightX, bottom - footerH + 4, color.BLACK)
	local parts = {}
	if L.flDriver ~= "" then parts[#parts + 1] = T("SR ", "FL ") .. L.flDriver .. " " .. dsp(L.flTime) end
	if L.dnf ~= "" then parts[#parts + 1] = "DNF " .. dnfText(L.dnf) end
	if L.pole ~= "" then parts[#parts + 1] = "Pole " .. L.pole end
	draw.text(leftX, bottom - 8, fit(table.concat(parts, " · "), rightX - leftX, "small"), "small", color.BLACK, "left")
end

local function sessionTable(ctx, kind)
	local rowsAll = getSess(kind)
	if not rowsAll then
		notice("flag", T("Noch kein Session-Ergebnis verfügbar.", "No session result available yet."))
		return
	end
	local y = draw.top + 2
	local bottom = draw.height - 14
	local headX = 20
	local headW = draw.width - 2 * headX
	local n = pickNext(getCal(), time.now())
	local head
	if n then
		head = string.format(T("RUNDE %d · %s", "ROUND %d · %s"), n.round, gpName(n.cid, n.name))
	else
		head = lab(LAST_LABEL, kind)
	end
	draw.text(headX, y + 16, fit(head, headW, "small"), "small", color.BLACK, "left")
	draw.text(headX, y + 46, lab(LAST_LABEL, kind), "large", color.BLACK, "left")

	local y2 = y + 62
	local mainH = bottom - y2
	draw.rect(headX, y2, headW, mainH, color.BLACK, false, 12)
	local rows = math.min(#rowsAll, RESULT_MAX)
	local rowH = (mainH - 20) // math.max(rows, 1)
	local maxTimeW = 0
	for i = 1, rows do maxTimeW = math.max(maxTimeW, draw.measure(dsp(rowsAll[i].time), "normal")) end
	local timeRight = headX + headW - 20
	for i = 1, rows do
		local r = rowsAll[i]
		local base = y2 + 10 + (i - 1) * rowH + rowH // 2 + 6
		posBadge(headX + 16, base - 16, 22, 5, i, i <= 3, "small")
		draw.text(timeRight, base, dsp(r.time), "normal", color.BLACK, "right")
		draw.text(headX + 50, base, r.code, "normal", color.BLACK, "left")
		draw.text(headX + 110, base, fit(r.team, timeRight - maxTimeW - 14 - (headX + 110), "small"), "small", color.BLACK, "left")
	end
end

local function drawLast(ctx, style)
	if emptyState() then return end
	local kind = sessKind(ctx)
	if kind ~= "race" then
		sessionTable(ctx, kind)
		return
	end
	local L = getLast()
	if not L then
		notice("flag", T("Noch kein Rennergebnis in dieser Saison.", "No race result yet this season."))
		return
	end
	if style == "flat" then lastSlate(L)
	elseif style == "compact" then lastNano(L)
	else lastBento(L) end
end

function on_draw(ctx, page)
	EN = ctx.lang == "en"
	resetData()
	draw.clear(color.WHITE)
	local p = page or 1
	if tonumber(ctx.cfg.page) then p = tonumber(ctx.cfg.page) + 1 end
	local style = ctx.cfg.style
	if p == 2 then
		drawStandings(ctx, style)
	elseif p == 3 then
		drawLast(ctx, style)
	else
		if emptyState() then return end
		local n, total = nextOrNotice(ctx)
		if n == nil then return end
		if style == "flat" then nextSlate(n, total)
		elseif style == "compact" then nextNano(n, total)
		else nextBento(n, total) end
	end
end

local function checkerFlag(x, y, s)
	local q = s // 4
	for ry = 0, 2 do
		for rx = 0, 3 do
			if (rx + ry) % 2 == 0 then draw.rect(x + 2 + rx * q, y + ry * q, q, q, color.BLACK, true) end
		end
	end
	draw.rect(x + 2, y, 4 * q, 3 * q, color.BLACK, false)
	draw.rect(x, y, 2, s + q, color.BLACK, true)
end

function on_widget(ctx, box)
	EN = ctx.lang == "en"
	resetData()
	local cal = getCal()
	local n = pickNext(cal, time.now())
	if n == nil and ctx.sample then
		n = { round = 15, cid = "monza", name = "Italian Grand Prix", circuit = "Autodromo Nazionale di Monza", loc = "Monza", country = "Italy",
			start = time.now() + 6 * 86400 + 3600, sess = {} }
	end
	if n == nil then
		local msg = #cal > 0 and T("Saison beendet", "Season finished") or T("Noch keine Daten", "No data yet")
		draw.text(box.x + 12, box.y + 16, msg, "small", color.BLACK, "left")
		return
	end
	local compact = ctx.cfg.wCompact == true
	local withLoc = ctx.cfg.wLocality ~= false
	local withTrack = ctx.cfg.wTrack ~= false and box.w >= 220
	local withLast = ctx.cfg.wLast == true
	local top = box.y
	local maxY = box.y + box.h - 4
	local cy = top + (maxY - top) // 2
	local textX
	if withTrack and not compact then
		local trackH = maxY - top - 8
		if trackH > 60 then trackH = 60 end
		if trackH < 26 then trackH = 26 end
		local trackW = trackH + 16
		drawTrack(box.x + 14, cy - trackH // 2, trackW, trackH, n.cid)
		textX = box.x + 30 + trackW
	else
		local flag = compact and 16 or 24
		checkerFlag(box.x + 14, cy - flag // 2, flag)
		textX = box.x + (compact and 40 or 52)
	end
	local f1, f2 = "normal", "small"
	if (box.font or 0) < 0 then f1 = "small" elseif (box.font or 0) > 0 then f2 = "normal" end
	local w = box.x + box.w - textX - 6
	local name = n.circuit ~= "" and n.circuit or n.name
	draw.text(textX, cy - 2, fit(name, w, f1), f1, color.BLACK, "left")
	local when = wdName(localParts(n.start)) .. string.format(" %02d.%02d. ", localParts(n.start).day, localParts(n.start).month) .. fmtTimeDevice(ctx, n.start)
	if withLoc and n.loc ~= "" then when = when .. " · " .. n.loc end
	draw.text(textX, cy + 17, fit(when, w, f2), f2, color.ACCENT_TEXT, "left")
	local L = withLast and getLast() or nil
	if L and cy + 34 <= maxY then
		local line
		if L.flDriver ~= "" then
			line = string.format(T("Zuletzt: %s (schn. Runde %s)", "Last: %s (fastest %s)"), L.rows[1].driver, L.flDriver)
		else
			line = string.format(T("Zuletzt: %s", "Last: %s"), L.rows[1].driver)
		end
		draw.text(textX, cy + 34, fit(line, w, f2), f2, color.BLACK, "left")
	end
end
