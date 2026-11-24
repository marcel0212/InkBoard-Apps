-- Weltzeit-Uhr: bis zu sechs Staedte mit Uhrzeit, Datum und Zeitunterschied. Ohne Internet.
-- Skript-API Level 2 (time.now, time.localtime). Sommerzeit wird selbst berechnet (EU, USA, Australien, Neuseeland).
--#include theme
--#include text
--#include ui

-- id, Name de, Name en, Normalzeit in Minuten zu UTC, Sommerzeitregel
local CITIES = {
  { "local", "Lokalzeit", "Local time", 0, "local" },
  { "honolulu", "Honolulu", "Honolulu", -600, "none" },
  { "anchorage", "Anchorage", "Anchorage", -540, "us" },
  { "losangeles", "Los Angeles", "Los Angeles", -480, "us" },
  { "vancouver", "Vancouver", "Vancouver", -480, "us" },
  { "phoenix", "Phoenix", "Phoenix", -420, "none" },
  { "denver", "Denver", "Denver", -420, "us" },
  { "mexiko", "Mexiko-Stadt", "Mexico City", -360, "none" },
  { "chicago", "Chicago", "Chicago", -360, "us" },
  { "houston", "Houston", "Houston", -360, "us" },
  { "newyork", "New York", "New York", -300, "us" },
  { "toronto", "Toronto", "Toronto", -300, "us" },
  { "miami", "Miami", "Miami", -300, "us" },
  { "bogota", "Bogotá", "Bogotá", -300, "none" },
  { "lima", "Lima", "Lima", -300, "none" },
  { "caracas", "Caracas", "Caracas", -240, "none" },
  { "santiago", "Santiago de Chile", "Santiago", -240, "cl" },
  { "saopaulo", "São Paulo", "São Paulo", -180, "none" },
  { "buenosaires", "Buenos Aires", "Buenos Aires", -180, "none" },
  { "reykjavik", "Reykjavik", "Reykjavik", 0, "none" },
  { "accra", "Accra", "Accra", 0, "none" },
  { "lissabon", "Lissabon", "Lisbon", 0, "eu" },
  { "london", "London", "London", 0, "eu" },
  { "dublin", "Dublin", "Dublin", 0, "eu" },
  { "madrid", "Madrid", "Madrid", 60, "eu" },
  { "paris", "Paris", "Paris", 60, "eu" },
  { "brussel", "Brüssel", "Brussels", 60, "eu" },
  { "amsterdam", "Amsterdam", "Amsterdam", 60, "eu" },
  { "berlin", "Berlin", "Berlin", 60, "eu" },
  { "zuerich", "Zürich", "Zurich", 60, "eu" },
  { "wien", "Wien", "Vienna", 60, "eu" },
  { "rom", "Rom", "Rome", 60, "eu" },
  { "kopenhagen", "Kopenhagen", "Copenhagen", 60, "eu" },
  { "oslo", "Oslo", "Oslo", 60, "eu" },
  { "stockholm", "Stockholm", "Stockholm", 60, "eu" },
  { "prag", "Prag", "Prague", 60, "eu" },
  { "warschau", "Warschau", "Warsaw", 60, "eu" },
  { "budapest", "Budapest", "Budapest", 60, "eu" },
  { "lagos", "Lagos", "Lagos", 60, "none" },
  { "algier", "Algier", "Algiers", 60, "none" },
  { "athen", "Athen", "Athens", 120, "eu" },
  { "helsinki", "Helsinki", "Helsinki", 120, "eu" },
  { "bukarest", "Bukarest", "Bucharest", 120, "eu" },
  { "kiew", "Kiew", "Kyiv", 120, "eu" },
  { "kairo", "Kairo", "Cairo", 120, "eg" },
  { "telaviv", "Tel Aviv", "Tel Aviv", 120, "il" },
  { "johannesburg", "Johannesburg", "Johannesburg", 120, "none" },
  { "istanbul", "Istanbul", "Istanbul", 180, "none" },
  { "moskau", "Moskau", "Moscow", 180, "none" },
  { "riad", "Riad", "Riyadh", 180, "none" },
  { "doha", "Doha", "Doha", 180, "none" },
  { "nairobi", "Nairobi", "Nairobi", 180, "none" },
  { "addis", "Addis Abeba", "Addis Ababa", 180, "none" },
  { "teheran", "Teheran", "Tehran", 210, "none" },
  { "dubai", "Dubai", "Dubai", 240, "none" },
  { "karatschi", "Karatschi", "Karachi", 300, "none" },
  { "delhi", "Neu-Delhi", "New Delhi", 330, "none" },
  { "mumbai", "Mumbai", "Mumbai", 330, "none" },
  { "colombo", "Colombo", "Colombo", 330, "none" },
  { "kathmandu", "Kathmandu", "Kathmandu", 345, "none" },
  { "dhaka", "Dhaka", "Dhaka", 360, "none" },
  { "almaty", "Almaty", "Almaty", 360, "none" },
  { "bangkok", "Bangkok", "Bangkok", 420, "none" },
  { "jakarta", "Jakarta", "Jakarta", 420, "none" },
  { "hochiminh", "Ho-Chi-Minh-Stadt", "Ho Chi Minh City", 420, "none" },
  { "singapur", "Singapur", "Singapore", 480, "none" },
  { "kualalumpur", "Kuala Lumpur", "Kuala Lumpur", 480, "none" },
  { "hongkong", "Hongkong", "Hong Kong", 480, "none" },
  { "peking", "Peking", "Beijing", 480, "none" },
  { "shanghai", "Shanghai", "Shanghai", 480, "none" },
  { "taipeh", "Taipeh", "Taipei", 480, "none" },
  { "manila", "Manila", "Manila", 480, "none" },
  { "perth", "Perth", "Perth", 480, "none" },
  { "tokio", "Tokio", "Tokyo", 540, "none" },
  { "seoul", "Seoul", "Seoul", 540, "none" },
  { "adelaide", "Adelaide", "Adelaide", 570, "au" },
  { "brisbane", "Brisbane", "Brisbane", 600, "none" },
  { "sydney", "Sydney", "Sydney", 600, "au" },
  { "melbourne", "Melbourne", "Melbourne", 600, "au" },
  { "auckland", "Auckland", "Auckland", 720, "nz" },
}
local BYID = {}
for _, c in ipairs(CITIES) do BYID[c[1]] = c end

local WD_DE = { "So", "Mo", "Di", "Mi", "Do", "Fr", "Sa" }
local WD_EN = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }

-- Tage seit 1970-01-01 <-> Datum (proleptisch gregorianisch)
local function daysFromCivil(y, m, d)
  if m <= 2 then y = y - 1 end
  local era = y // 400
  local yoe = y - era * 400
  local mp = (m + 9) % 12
  local doy = (153 * mp + 2) // 5 + d - 1
  local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
  return era * 146097 + doe - 719468
end

local function civilFromDays(z)
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

local function weekday(days) return (days + 4) % 7 end -- 0 = Sonntag

-- n-ter Sonntag eines Monats (n = 1..4) und letzter Sonntag, als Tageszahl
local function nthSunday(y, m, n)
  local first = daysFromCivil(y, m, 1)
  local add = (7 - weekday(first)) % 7
  return first + add + 7 * (n - 1)
end
local function lastSunday(y, m)
  local ny, nm = y, m + 1
  if nm > 12 then ny, nm = y + 1, 1 end
  local last = daysFromCivil(ny, nm, 1) - 1
  return last - weekday(last)
end

-- Sonntag am oder nach Tag d; letzter Wochentag wd (0 = So) eines Monats
local function sunOnOrAfter(y, m, d)
  local z = daysFromCivil(y, m, d)
  return z + (7 - weekday(z)) % 7
end
local function lastWeekday(y, m, wd)
  local ny, nm = y, m + 1
  if nm > 12 then ny, nm = y + 1, 1 end
  local last = daysFromCivil(ny, nm, 1) - 1
  return last - (weekday(last) - wd) % 7
end

-- Gilt zur UTC-Zeit t (Sekunden) Sommerzeit? std = Normalzeit in Minuten
local function isDst(rule, t, std)
  if rule == "none" or rule == "local" then return false end
  local y = civilFromDays((t + std * 60) // 86400)
  if rule == "eu" then
    return t >= lastSunday(y, 3) * 86400 + 3600 and t < lastSunday(y, 10) * 86400 + 3600
  elseif rule == "us" then
    local s = nthSunday(y, 3, 2) * 86400 + 7200 - std * 60
    local e = nthSunday(y, 11, 1) * 86400 + 7200 - (std + 60) * 60
    return t >= s and t < e
  elseif rule == "au" then -- Suedhalbkugel: Sommerzeit ueber den Jahreswechsel
    local s = nthSunday(y, 10, 1) * 86400 + 7200 - std * 60
    local e = nthSunday(y, 4, 1) * 86400 + 10800 - (std + 60) * 60
    return t >= s or t < e
  elseif rule == "nz" then
    local s = lastSunday(y, 9) * 86400 + 7200 - std * 60
    local e = nthSunday(y, 4, 1) * 86400 + 10800 - (std + 60) * 60
    return t >= s or t < e
  elseif rule == "cl" then -- Chile: ab Sonntag 2.-8. September 0 Uhr bis Sonntag 2.-8. April 0 Uhr
    local st = sunOnOrAfter(y, 9, 2) * 86400 - std * 60
    local e = sunOnOrAfter(y, 4, 2) * 86400 - (std + 60) * 60
    return t >= st or t < e
  elseif rule == "eg" then -- Aegypten: letzter Freitag im April bis letzter Donnerstag im Oktober
    local st = lastWeekday(y, 4, 5) * 86400 - std * 60
    local e = (lastWeekday(y, 10, 4) + 1) * 86400 - (std + 60) * 60
    return t >= st and t < e
  elseif rule == "il" then -- Israel: Freitag vor dem letzten Maerz-Sonntag bis letzter Oktober-Sonntag, je 2 Uhr
    local st = (lastSunday(y, 3) - 2) * 86400 + 7200 - std * 60
    local e = lastSunday(y, 10) * 86400 + 7200 - (std + 60) * 60
    return t >= st and t < e
  end
  return false
end

-- UTC-Sekunden jetzt; ohne Uhr ein fester Beispielzeitpunkt (Vorschau)
local function nowUtc()
  local n = time.now()
  if n and n > 1600000000 then return n end
  return daysFromCivil(2026, 11, 22) * 86400 + 11 * 3600 + 30 * 60
end

-- Abweichung der Stadt zu UTC in Sekunden und Sommerzeit-Kennzeichen
local function offsetOf(city, utc)
  if city[5] == "extra" then
    local r = city.rec -- {Versatz, Sommerzeit-Zuschlag, Sommerzeit jetzt (0/1), Beginn, Ende} in Sekunden
    local off = r[1]
    if r[3] == 1 and not (r[5] > 0 and utc >= r[5]) then off = r[1] + r[2] end
    return off, off ~= r[1]
  end
  if city[5] == "local" then
    local lt = time.localtime()
    if not lt then return 0, false end
    local ls = daysFromCivil(lt.year, lt.month, lt.day) * 86400 + lt.hour * 3600 + lt.min * 60 + lt.sec
    local off = ls - utc
    off = ((off + 900) // 1800) * 1800 -- auf halbe Stunden runden (Sekundenversatz der Uhr)
    return off, false
  end
  local dst = isDst(city[5], utc, city[4])
  return (city[4] + (dst and 60 or 0)) * 60, dst
end

local function fmtTime(h, m, clock24)
  if clock24 then return string.format("%02d:%02d", h, m) end
  local suf = h >= 12 and " pm" or " am"
  local hh = h % 12
  if hh == 0 then hh = 12 end
  return string.format("%d:%02d", hh, m) .. suf
end

-- Zeitunterschied zur ersten Stadt als Text: "+6 Std", "-9 Std", "+5:30 Std"
local function fmtDiff(sec, en)
  local mins = sec // 60
  local sign = mins < 0 and "-" or "+"
  mins = math.abs(mins)
  local h, m = mins // 60, mins % 60
  local u = en and " h" or " Std"
  if mins == 0 then return en and "same time" or "gleiche Zeit" end
  if m == 0 then return sign .. h .. u end
  return string.format("%s%d:%02d%s", sign, h, m, u)
end

-- Eintrag fuer Stadt c zum Zeitpunkt utc: Zeit, Datum, Wochentag, Tagesnummer
local function entry(city, utc, base, en, clock24)
  local off, dst = offsetOf(city, utc)
  local t = utc + off
  local days, secs = t // 86400, t % 86400
  local y, mo, d = civilFromDays(days)
  local e = {
    name = en and city[3] or city[2],
    id = city[1],
    h = secs // 3600, m = (secs % 3600) // 60,
    days = days, off = off, dst = dst,
    wd = (en and WD_EN or WD_DE)[weekday(days) + 1],
  }
  e.time = fmtTime(e.h, e.m, clock24)
  e.date = en and string.format("%02d/%02d", mo, d) or string.format("%02d.%02d.", d, mo)
  if base then
    e.dd = days - base.days
    e.diff = fmtDiff(off - base.off, en)
  else
    e.dd = 0
  end
  return e
end

local function dayWord(dd, en)
  if dd == 0 then return en and "today" or "heute" end
  if dd > 0 then return en and "tomorrow" or "morgen" end
  return en and "yesterday" or "gestern"
end

local DEMO_CITIES = { "Lokalzeit", "New York", "Tokio", "Sydney" }

-- ISO-Zeit "2026-03-29T01:00:00+00:00" (UTC) -> Unix-Sekunden
local function parseIso(str)
  local y, mo, d, h, mi, se = tostring(str or ""):match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return 0 end
  return daysFromCivil(tonumber(y), tonumber(mo), tonumber(d)) * 86400 + tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(se)
end

local FOLD = { ["ä"] = "a", ["ö"] = "o", ["ü"] = "u", ["ß"] = "ss", ["é"] = "e", ["á"] = "a", ["ã"] = "a", ["í"] = "i", ["ó"] = "o", ["ç"] = "c" }
-- Namen vergleichbar machen: klein, ohne Umlaute, Leerzeichen und Bindestriche
local function norm(str)
  str = tostring(str or ""):lower()
  str = str:gsub("[\195][\128-\191]", function(ch) return FOLD[ch] or ch end)
  return (str:gsub("[%s%-%.]", ""))
end

local BYNAME = {}
for _, c in ipairs(CITIES) do
  BYNAME[norm(c[1])] = c
  BYNAME[norm(c[2])] = c
  BYNAME[norm(c[3])] = c
end
BYNAME[norm("Local")] = BYID["local"]
BYNAME[norm("Lokal")] = BYID["local"]

-- Eintraege der Liste "Staedte": Name aus der eingebauten Liste, oder "Name=Region/Stadt" fuer eine eigene Zone
local function entries(cfg)
  local out = {}
  local raw = type(cfg.cities) == "table" and cfg.cities or nil
  if raw == nil then
    raw = {}
    for i, n in ipairs(DEMO_CITIES) do raw[i] = n end -- Vorschau ohne Einstellungen
  end
  local nExtra = 0
  for _, ln in ipairs(raw) do
    if #out >= 6 then break end
    ln = tostring(ln)
    local name, zone = ln:match("^%s*(.-)%s*=%s*([%w_%-]+/[%w_%-/]+)%s*$")
    if not zone then zone = ln:match("^%s*([%w_%-]+/[%w_%-/]+)%s*$") end
    if zone then
      if nExtra < 3 then
        nExtra = nExtra + 1
        if not name or name == "" then name = (zone:match("([^/]+)$") or zone):gsub("_", " ") end
        out[#out + 1] = { zone = zone, name = clean(name, 24), idx = nExtra }
      end
    else
      local c = BYNAME[norm(ln)]
      if c then out[#out + 1] = { city = c } end
    end
  end
  if #out == 0 then out[1] = { city = BYID["local"] } end
  return out
end

local function cityList(ctx)
  local list = {}
  for _, e in ipairs(entries(ctx.cfg)) do
    if e.city then
      list[#list + 1] = e.city
    else
      local rec = ctx.data.get("z" .. e.idx)
      local zone, nums = tostring(rec or ""):match("^([^|]+)|(.+)$")
      if zone == e.zone then
        local r = {}
        for v in nums:gmatch("%-?%d+") do r[#r + 1] = tonumber(v) end
        if #r == 5 then list[#list + 1] = { "x" .. e.idx, e.name, e.name, 0, "extra", rec = r } end
      end
    end
  end
  if #list == 0 then list[1] = BYID["local"] end
  return list
end

-- Abruf der eigenen Zonen (worldtimeapi.org: Versatz und Sommerzeit der Zone)
function on_fetch(ctx)
  local ex = {}
  for _, e in ipairs(entries(ctx.cfg)) do if e.zone then ex[#ex + 1] = e end end
  if #ex == 0 then return true end
  local okAny = false
  for i, e in ipairs(ex) do
    if i > 1 then time.sleep(300) end
    local body, err = http.get("https://worldtimeapi.org/api/timezone/" .. e.zone, 4096)
    local d = body and json.decode(body)
    if type(d) == "table" and tonumber(d.raw_offset) then
      local dst = d.dst == true
      local rec = table.concat({ math.floor(tonumber(d.raw_offset)), dst and math.floor(tonumber(d.dst_offset) or 3600) or 0,
        dst and 1 or 0, parseIso(d.dst_from), parseIso(d.dst_until) }, ",")
      ctx.data.set("z" .. e.idx, e.zone .. "|" .. rec)
      okAny = true
    else
      log("Weltzeit: " .. e.zone .. ": " .. tostring(err or "ungueltige Antwort"))
    end
  end
  return okAny
end

local function build(ctx)
  local en = (ctx.lang == "en")
  local utc = nowUtc()
  local list = cityList(ctx)
  local out, base = {}, nil
  for i, c in ipairs(list) do
    local e = entry(c, utc, base, en, ctx.clock24 ~= false)
    if i == 1 then base = e end
    out[i] = e
  end
  return out, en
end

-- Gross -> kleiner, bis der Text in w passt
local function pickFont(s, w, fonts)
  for _, f in ipairs(fonts) do
    if draw.measure(s, f) <= w then return f end
  end
  return fonts[#fonts]
end

local function drawTiles(list, en)
  local n = #list
  local cols = (n <= 2) and n or ((n == 4) and 2 or 3)
  local at, tw, th = gridLayout(n, cols, draw.top + 16, draw.height - 18, 24, 16, 230)
  for i, e in ipairs(list) do
    local x, y, w, h = at(i)
    card(x, y, w, h, color.ACCENT, theme.s == "relief" and 14 or 20)
    local pad = 24
    local small = h < 150
    draw.text(x + pad, y + 40, fit(e.name, w - pad * 2 - (i > 1 and 74 or 0), "normal"), "normal", color.BLACK, "left")
    local tf = pickFont(e.time, w - pad * 2, small and { "large", "medium", "normal" } or { "huge", "large", "medium" })
    draw.text(x + w // 2, y + h // 2 + (small and 24 or 34), e.time, tf, color.BLACK, "center")
    local sub = e.wd .. " " .. e.date
    if e.dd ~= 0 then sub = sub .. ", " .. dayWord(e.dd, en) end
    draw.text(x + pad, y + h - 26, fit(sub, w - pad * 2, "small"), "small", color.BLACK, "left")
    if i > 1 then
      local dw = pillW(e.diff, "small", 26, 0)
      if dw <= w // 2 then pill(x + w - dw - 16, y + 14, dw, 26, color.ACCENT, e.diff, "small") end
    end
  end
end

local function drawRows(list, en)
  local n = #list
  local compact = theme.s == "compact"
  local top, bottom = draw.top + 10, draw.height - 12
  local shown, rowH = rowLayout(n, top, bottom, compact and 44 or 56, compact and 64 or 78)
  local startY = top + ((bottom - top) - rowH * shown) // 2
  for i = 1, shown do
    local e = list[i]
    local y = startY + (i - 1) * rowH
    if theme.s == "flat" then
      draw.line(40, y + rowH - 1, draw.width - 40, y + rowH - 1, color.BLACK)
    else
      draw.rect(24, y + 6, 5, rowH - 12, color.ACCENT, true)
    end
    local nf = rowH >= 64 and "medium" or "normal"
    draw.text(48, y + rowH // 2 - 2, e.name, nf, color.BLACK, "left")
    local sub = e.wd .. " " .. e.date
    if e.dd ~= 0 then sub = sub .. ", " .. dayWord(e.dd, en) end
    if i > 1 then sub = sub .. "  (" .. e.diff .. ")" end
    draw.text(48, y + rowH // 2 + 22, fit(sub, 430, "small"), "small", color.ACCENT_TEXT, "left")
    draw.text(draw.width - 40, y + rowH // 2 + 14, e.time, rowH >= 64 and "large" or "medium", color.BLACK, "right")
  end
end

-- ===== Weitere Layouts (Einstellung "design"): heim, analog, tabelle, sonne, typo =====
local DESIGNS = { "karten", "heim", "analog", "tabelle", "sonne", "typo" }

local function designOf(cfg)
  local d = cfg.design
  if d == nil then d = DESIGNS[((tonumber(cfg.opt) or 0) % 10) + 1] end -- Vorschau-Werkzeug: opt waehlt das Layout
  return d or "karten"
end

local function subLine(e, en)
  local t = e.wd .. " " .. e.date
  if e.dd ~= 0 then t = t .. ", " .. dayWord(e.dd, en) end
  return t
end

local function isNight(e) return e.h < 6 or e.h >= 20 end

local function bigScale(t, w)
  for k = 3, 2, -1 do if draw.measure(t, "huge", k) <= w then return k end end
  return 1
end

local function thick(x1, y1, x2, y2, col, t)
  local dx, dy = x2 - x1, y2 - y1
  local len = math.sqrt(dx * dx + dy * dy)
  if len == 0 then return end
  local nx, ny = -dy / len, dx / len
  for k = -(t // 2), t // 2 do
    draw.line(math.floor(x1 + nx * k + 0.5), math.floor(y1 + ny * k + 0.5), math.floor(x2 + nx * k + 0.5), math.floor(y2 + ny * k + 0.5), col)
  end
end

local DIALS = { "klassisch", "ziffern", "punkte", "minuten", "schlicht" }
local function dialOf(cfg)
  local d = cfg.dial
  if d == nil then d = DIALS[((tonumber(cfg.opt) or 0) // 10) + 1] end
  for _, k in ipairs(DIALS) do if k == d then return d end end
  return "klassisch"
end

local function polar(cx, cy, a, len)
  return cx + math.cos(a) * len, cy + math.sin(a) * len
end

-- Zeiger als schmales Vieleck: Schwanz hinter der Mitte, Spitze vorn
local function hand(cx, cy, a, len, wid, tail, col)
  local tx, ty = polar(cx, cy, a, len)
  local bx, by = polar(cx, cy, a + math.pi, tail)
  local lx, ly = polar(cx, cy, a - math.pi / 2, wid / 2)
  local rx, ry = polar(cx, cy, a + math.pi / 2, wid / 2)
  local function f(v) return math.floor(v + 0.5) end
  draw.polygon({ f(lx), f(ly), f(tx), f(ty), f(rx), f(ry), f(bx), f(by) }, col, true)
end

local function tick(cx, cy, a, r0, r1)
  local x0, y0 = polar(cx, cy, a, r0)
  local x1, y1 = polar(cx, cy, a, r1)
  draw.line(math.floor(x0 + 0.5), math.floor(y0 + 0.5), math.floor(x1 + 0.5), math.floor(y1 + 0.5), color.BLACK)
end

local function clockFace(cx, cy, r, e, dial)
  dial = dial or "klassisch"
  if dial ~= "schlicht" then
    draw.circle(cx, cy, r, color.WHITE, true)
    draw.circle(cx, cy, r, color.BLACK, false)
    if dial == "ziffern" then draw.circle(cx, cy, r - 1, color.BLACK, false) end
  end
  if dial == "klassisch" then
    for i = 0, 11 do
      tick(cx, cy, math.rad(i * 30 - 90), r - 3, r - ((i % 3 == 0) and 13 or 8))
    end
  elseif dial == "ziffern" then
    if r >= 40 then
      for i = 0, 3 do
        local nx, ny = polar(cx, cy, math.rad(i * 90 - 90), r - 17)
        local t = tostring(i == 0 and 12 or i * 3)
        draw.text(math.floor(nx + 0.5), math.floor(ny + 0.5) + 6, t, "small", color.BLACK, "center")
      end
      for i = 0, 11 do
        if i % 3 ~= 0 then tick(cx, cy, math.rad(i * 30 - 90), r - 3, r - 8) end
      end
    else
      for i = 0, 11 do tick(cx, cy, math.rad(i * 30 - 90), r - 3, r - ((i % 3 == 0) and 13 or 8)) end
    end
  elseif dial == "punkte" then
    for i = 0, 11 do
      local x, y = polar(cx, cy, math.rad(i * 30 - 90), r - 9)
      local pr = (i % 3 == 0) and 4 or 2
      draw.circle(math.floor(x + 0.5), math.floor(y + 0.5), pr, i == 0 and color.ACCENT or color.BLACK, true)
    end
  elseif dial == "minuten" then
    for i = 0, 59 do
      local big = i % 5 == 0
      tick(cx, cy, math.rad(i * 6 - 90), r - 2, r - (big and 11 or 6))
    end
  else
    for i = 0, 3 do
      tick(cx, cy, math.rad(i * 90 - 90), r - 2, r - 12)
    end
  end
  local ha = math.rad((e.h % 12 + e.m / 60) * 30 - 90)
  local ma = math.rad(e.m * 6 - 90)
  if dial == "schlicht" then
    hand(cx, cy, ha, r * 0.52, 4, 0, color.BLACK)
    hand(cx, cy, ma, r * 0.82, 3, 0, color.BLACK)
    draw.circle(cx, cy, 3, color.ACCENT, true)
  elseif dial == "punkte" then
    hand(cx, cy, ha, r * 0.45, 7, 0, color.BLACK)
    hand(cx, cy, ma, r * 0.68, 5, 0, color.ACCENT)
    draw.circle(cx, cy, 5, color.BLACK, true)
  else
    hand(cx, cy, ha, r * 0.52, 8, 6, color.BLACK)
    hand(cx, cy, ma, r * 0.8, 5, 8, color.ACCENT)
    draw.circle(cx, cy, 4, color.BLACK, true)
  end
end

local function sunMoon(cx, cy, r, night)
  if night then
    draw.rect(cx - r, cy - r, 2 * r, 2 * r, color.BLUE, true, r)
    draw.rect(cx - r + r // 2, cy - r - r // 4, 2 * r - r // 4, 2 * r - r // 4, color.WHITE, true, r)
    draw.rect(cx - r, cy - r, 2 * r, 2 * r, color.BLACK, false, r)
  else
    draw.rect(cx - r, cy - r, 2 * r, 2 * r, color.YELLOW, true, r)
    draw.rect(cx - r, cy - r, 2 * r, 2 * r, color.BLACK, false, r)
    for k = 0, 7 do
      local a = math.rad(k * 45)
      draw.line(cx + math.floor(math.cos(a) * (r + 4) + 0.5), cy + math.floor(math.sin(a) * (r + 4) + 0.5),
        cx + math.floor(math.cos(a) * (r + 9) + 0.5), cy + math.floor(math.sin(a) * (r + 9) + 0.5), color.BLACK)
    end
  end
end

local function isFancyStyle() return theme.s == "relief" or theme.s == "klar" or theme.s == "cards" end

local function gridFor(n)
  local cols = (n <= 2) and n or ((n == 4) and 2 or 3)
  return gridLayout(n, cols, draw.top + 16, draw.height - 18, 24, 16, 230)
end

local function frameBox(x, y, w, h)
  if isFancyStyle() then card(x, y, w, h, color.ACCENT, theme.s == "relief" and 14 or 20)
  else
    draw.rect(x, y, w, h, color.WHITE, true, 8)
    draw.rect(x, y, w, h, color.BLACK, false, 8)
  end
end

-- Design 2: Bezugszeit gross, die anderen als Reihe darunter
local function drawHeim(list, en)
  local top, bottom = draw.top + 14, draw.height - 16
  local n = #list
  local e = list[1]
  local mainH = n > 1 and 220 or (bottom - top)
  frameBox(24, top, 752, mainH)
  draw.text(54, top + 46, e.name, "medium", color.BLACK, "left")
  draw.text(400, top + mainH // 2 + 40, e.time, "huge", color.BLACK, "center", bigScale(e.time, 680))
  draw.text(54, top + mainH - 22, subLine(e, en), "small", color.BLACK, "left")
  local m = math.min(n - 1, 5)
  if m < 1 then return end
  local gap = 14
  local cw = (752 - (m - 1) * gap) // m
  local y0 = top + mainH + 18
  local h = bottom - y0
  for i = 1, m do
    local c = list[i + 1]
    local x = 24 + (i - 1) * (cw + gap)
    frameBox(x, y0, cw, h)
    draw.text(x + cw // 2, y0 + 30, fit(c.name, cw - 16, "small"), "small", color.BLACK, "center")
    draw.text(x + cw // 2, y0 + h // 2 + 14, c.time, pickFont(c.time, cw - 12, { "large", "medium", "normal" }), color.BLACK, "center")
    draw.text(x + cw // 2, y0 + h - 14, fit(c.diff .. (c.dd ~= 0 and (", " .. dayWord(c.dd, en)) or ""), cw - 10, "small"), "small", color.ACCENT_TEXT, "center")
  end
end

-- Design 4: Analoguhr in jeder Karte
local function drawAnalog(list, en, dial)
  local n = #list
  local at, tw, th = gridFor(n)
  for i, e in ipairs(list) do
    local x, y, w, h = at(i)
    frameBox(x, y, w, h)
    if w >= 330 then
      local r = math.min(h // 2 - 18, 74)
      clockFace(x + r + 24, y + h // 2, r, e, dial)
      local tx = x + 2 * r + 48
      draw.text(tx, y + 44, fit(e.name, w - (tx - x) - 14, "normal"), "normal", color.BLACK, "left")
      draw.text(tx, y + h // 2 + 22, e.time, pickFont(e.time, w - (tx - x) - 14, { "large", "medium", "normal" }), color.BLACK, "left")
      draw.text(tx, y + h - 22, fit(subLine(e, en), w - (tx - x) - 14, "small"), "small", color.BLACK, "left")
    else
      local r = math.min(h // 2 - 52, w // 2 - 22, 60)
      if r < 24 then r = 24 end
      clockFace(x + w // 2, y + r + 14, r, e, dial)
      draw.text(x + w // 2, y + 2 * r + 40, fit(e.name, w - 16, "small"), "small", color.BLACK, "center")
      draw.text(x + w // 2, y + h - 34, e.time, pickFont(e.time, w - 20, { "large", "medium", "normal" }), color.BLACK, "center")
    end
  end
end

-- Design 17: Tabelle mit Tag-/Nacht-Punkt
local function drawTable(list, en)
  local n = #list
  local top, bottom = draw.top + 10, draw.height - 12
  local shown, rowH = rowLayout(n, top, bottom, 52, 74)
  local startY = top + ((bottom - top) - rowH * shown) // 2
  for i = 1, shown do
    local e = list[i]
    local y = startY + (i - 1) * rowH
    if i % 2 == 1 and isFancyStyle() then draw.rect(24, y, draw.width - 48, rowH - 2, color.WHITE, true, 8); draw.rect(24, y, draw.width - 48, rowH - 2, color.BLACK, false, 8)
    else draw.line(40, y + rowH - 1, draw.width - 40, y + rowH - 1, color.BLACK) end
    local cy = y + rowH // 2
    draw.rect(44, cy - 10, 20, 20, isNight(e) and color.BLACK or color.YELLOW, true, 10)
    draw.rect(44, cy - 10, 20, 20, color.BLACK, false, 10)
    draw.text(84, cy + 8, fit(e.name, 250, "medium"), "medium", color.BLACK, "left")
    draw.text(360, cy + 6, fit(subLine(e, en), 200, "small"), "small", color.BLACK, "left")
    if i > 1 then draw.text(590, cy + 6, fit(e.diff, 100, "small"), "small", color.ACCENT_TEXT, "left") end
    draw.text(draw.width - 40, cy + 14, e.time, "large", color.BLACK, "right")
  end
end

-- Design 14: Sonne oder Mond je Stadt
local function drawSonne(list, en)
  local n = #list
  local at, tw, th = gridFor(n)
  for i, e in ipairs(list) do
    local x, y, w, h = at(i)
    frameBox(x, y, w, h)
    draw.text(x + 22, y + 40, fit(e.name, w - 90, "normal"), "normal", color.BLACK, "left")
    sunMoon(x + w - 40, y + 38, 16, isNight(e))
    draw.text(x + w // 2, y + h // 2 + 30, e.time, pickFont(e.time, w - 40, { "huge", "large", "medium" }), color.BLACK, "center")
    local note = (i == 1) and (en and "home" or "Heimat") or e.diff
    draw.text(x + 22, y + h - 20, fit(note .. (e.dd ~= 0 and (", " .. dayWord(e.dd, en)) or ""), w - 44, "small"), "small", color.ACCENT_TEXT, "left")
  end
end

-- Design 10: typografisch, Bezugszeit riesig, Rest als schlichte Zeilen
local function drawTypo(list, en)
  local top, bottom = draw.top + 10, draw.height - 12
  local e = list[1]
  local n = #list
  local bigH = n > 1 and 230 or (bottom - top)
  draw.text(40, top + bigH // 2 + 40, e.time, "huge", color.BLACK, "left", bigScale(e.time, 700))
  draw.text(44, top + 40, e.name, "medium", color.ACCENT_TEXT, "left")
  draw.text(draw.width - 40, top + 40, subLine(e, en), "small", color.BLACK, "right")
  if n < 2 then return end
  local m = math.min(n - 1, 5)
  local y0 = top + bigH + 6
  local rh = math.min(46, (bottom - y0) // m)
  for i = 1, m do
    local c = list[i + 1]
    local y = y0 + (i - 1) * rh
    draw.line(40, y, draw.width - 40, y, color.BLACK)
    local cy = y + rh // 2 + 8
    draw.text(44, cy, fit(c.name, 230, "normal"), "normal", color.BLACK, "left")
    draw.text(300, cy, c.time, "medium", color.BLACK, "left")
    draw.text(430, cy, fit(subLine(c, en), 240, "small"), "small", color.BLACK, "left")
    draw.text(draw.width - 40, cy, c.diff, "small", color.ACCENT_TEXT, "right")
  end
end

function on_draw(ctx, page)
  setStyle(ctx.cfg.style)
  draw.clear(color.WHITE)
  local list, en = build(ctx)
  local design = designOf(ctx.cfg)
  if design == "heim" then return drawHeim(list, en) end
  if design == "analog" then return drawAnalog(list, en, dialOf(ctx.cfg)) end
  if design == "tabelle" then return drawTable(list, en) end
  if design == "sonne" then return drawSonne(list, en) end
  if design == "typo" then return drawTypo(list, en) end
  if theme.s == "relief" or theme.s == "klar" or theme.s == "cards" then
    drawTiles(list, en)
  else
    drawRows(list, en)
  end
end

function on_widget(ctx, box)
  setStyle(ctx.cfg.style)
  box = widgetFrame(box)
  local list = build(ctx)
  local n = math.min(#list, math.max(1, box.h // 30))
  if n == 1 and box.h >= 56 then
    local e = list[1]
    draw.text(box.x + 12, box.y + 20, fit(e.name, box.w - 20, "small"), "small", color.BLACK, "left")
    draw.text(box.x + 12, box.y + box.h // 2 + 24, e.time, pickFont(e.time, box.w - 24, { "large", "medium", "normal" }), color.ACCENT_TEXT, "left")
    return
  end
  local rh = box.h // n
  for i = 1, n do
    local e = list[i]
    local y = box.y + (i - 1) * rh + rh // 2 + 6
    local tw = draw.measure(e.time, "normal")
    draw.text(box.x + box.w - 6, y, e.time, "normal", i == 1 and color.ACCENT_TEXT or color.BLACK, "right")
    draw.text(box.x + 12, y, fit(e.name, box.w - tw - 30, "small"), "small", color.BLACK, "left")
  end
end
