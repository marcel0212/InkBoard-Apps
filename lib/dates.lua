-- Datumsbausteine (store/lib/dates.lua): Tage seit 1970-01-01, Feed-Zeitstempel -> Unix-Zeit

-- Tage seit 1970-01-01 aus Datum (proleptisch gregorianisch) und zurueck.
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

-- Zeitzonenangabe ("+0200", "-05:00", "GMT", "Z") -> Sekunden Abweichung von UTC
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

-- RSS-Datum "Mon, 05 Oct 2026 14:30:00 +0200" -> Unix-Zeit oder nil
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

-- Atom/ISO-Datum "2026-10-05T14:30:00+02:00" / "...Z" -> Unix-Zeit oder nil
local function parseIso(s)
  if type(s) ~= "string" then return nil end
  local y, m, d, hh, mi, ss, rest = s:match("(%d%d%d%d)%-(%d%d)%-(%d%d)[T ](%d%d):(%d%d):?(%d*)(.*)")
  if y == nil then return nil end
  local zone = rest:match("([+-]%d%d:?%d%d)") or (rest:find("Z", 1, true) and "Z") or ""
  return dfc(tonumber(y), tonumber(m), tonumber(d)) * 86400 + tonumber(hh) * 3600 + tonumber(mi) * 60 + (tonumber(ss) or 0) - zoneSeconds(zone)
end
