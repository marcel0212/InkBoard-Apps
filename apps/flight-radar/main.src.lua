-- Flight Radar (Paket flight-radar 1.2.4, Skript-Variante der eingebauten App "flightradar"): das naechstgelegene Flugzeug am
-- Himmel ueber dem Standort des Geraets. Seite 1 "Flug": links im Bildkasten (430 x 296) das freigestellte Renderbild vom NAS
-- (dieselbe Datei- und Lackierungsregel wie auf der Himmel-Seite), darin in der Ecke das Airline-Logo (NAS, 85 x 20); nur wenn
-- auf dem NAS nichts passendes liegt (oder kein NAS eingerichtet ist), das Foto genau dieser Maschine von planespotters.net
-- (gedithert) mit Fotografen-Credit, sonst "Kein Bild verfuegbar". Rechts Rufzeichen, Airline, Route, Maschine, Kennung,
-- Hoehe/Tempo, Entfernung/Richtung (kein Logo-Kaestchen mehr neben dem Rufzeichen).
-- Seite 2 "Himmel" (Vollbild ohne Kopfzeile): bis zu drei nahe Flugzeuge als freigestellte Renderbilder vom NAS in gestaffelter
-- Formation auf waehlbarer Hintergrundfarbe (ohne Renderbild wird ein Flugzeug nicht gezeichnet, kein Ersatzbild).
-- Dashboard-Widget "Naechster Flug" (Rufzeichen, Route/Typ, Hoehe, Entfernung). Dazu: airlines.json vom NAS (Knoepfe "Von NAS neu laden",
-- Import/Export als Datei, Aenderungsliste der letzten Uebernahme) und die Abdeckungsauswertung (CSV im Schema der Mac-App auf dem NAS,
-- auch als Datei-Download vom Geraet).
-- Hauptflugzeug: Flug-Seite, Route, Logo und Widget gelten dem naechsten Flugzeug, zu dem auf dem NAS ein Bild liegt (nicht stur dem
-- allernaechsten); ohne jedes NAS-Bild das allernaechste mit planespotters-Foto.
-- Skript-API Level 18 (storage.exists/image, http.image mit ram, Vollbild-Seite, storage.* und file.write in on_action).
--
-- Datenquellen:
--   Positionen  GET  https://api.adsb.lol/v2/point/<lat>/<lon>/<Seemeilen>      (readsb/tar1090-JSON, "ac"-Liste)
--   Route       POST https://api.adsb.lol/api/0/routeset  {"planes":[{"callsign":..,"lat":..,"lng":..}]} -> "_airport_codes_iata"
--   Foto        GET  https://api.planespotters.net/pub/photos/hex/<hex>  -> photos[1].thumbnail_large.src + photographer
--               (Fotografen-Credit ist Pflicht); das Bild selbst per http.image von *.plnspttrs.net
--   NAS         Renderbilder <gruppe>.png / <gruppe>_<iata>.png (Paket "inkboard-flugzeuge"), Logos logos/<ICAO>.bmp (85 x 20),
--               airlines.json, Abdeckungs-CSV (Feld "dir" bzw. "cov" der Einstellungen)
-- Der Standort ist kein Paket-Feld, sondern die Adresse des Geraets (weather.location()), wie bei der eingebauten App.
--
-- Auswertung wie fetchFlightRadar(): Antwort beim Empfang auf elf Felder verschlankt (keep), jedes Flugzeug einzeln gelesen, hart auf
-- den km-Radius nachgefiltert, die POOL = 16 naechsten behalten; Route nur fuer das naechste Flugzeug bei geaendertem Rufzeichen;
-- Flug-Bild, Foto, Himmel, Logo und Auswertung nur, wenn die App angezeigt wird (ctx.view) - ohne zusaetzlichen Positionsabruf.
--
-- Dateien (file.*, hoechstens 8 Zugriffe je Aufruf - deshalb wenige, gebuendelte Dateien):
--   "ac"   letzter Stand, Tab-getrennt: H Schluessel,Zeit,Gesamtzahl / A hex,cs,reg,typ,typname,airline,lat,lon,boden,hoehe,tempo,
--          kurs,entfernung,richtung,gruppe,lackierungen(1/0),iata,leitwerksfarbe / E Schluessel,Zeit,Text (letzter Fehlversuch)
--   "st"   Zustand: M = fehlende NAS-Dateien (Negativ-Cache), S = Kennung des komponierten Himmels, T = letzter airlines.json-Abruf,
--          D = Zeilen der Aenderungsliste der letzten airlines.json-Uebernahme, C/X/E/B = Abdeckungs-Sitzung (Kopf, gesehene hex,
--          Existenz-Cache, Eimer)
--   "airl" airlines.json-Ueberlagerung (A = Airline, G = Lackierungs-Gruppe, T = Typcode-Zuordnung), geht den Tabellen vor
-- ctx.data: "rt" Rufzeichen|von|nach, "fi" Bilddatei|1/0|Zeit (Renderbild der Flug-Seite, Name "fplane"), "ph" hex|Fotograf|1/0
--           (Ersatzfoto), "lg" ICAO|1/0 (Logo), "sk" Kennung~Eintraege (Himmel-Layout).
-- assets/tables.txt = Typ-Gruppen und Airlines (Quelle der Wahrheit; tools/flightradar_tables.py --check vergleicht sie mit dem Mac-Werkzeug).

local EN = false
local function T(de, en) if EN then return en end return de end

local ADSB = "https://api.adsb.lol"
local PLANESPOTTERS = "https://api.planespotters.net/pub/photos/hex/"
local MIN_GAP = 120      -- Untergrenze zwischen zwei erfolgreichen Abrufen (adsb.lol ist eine kostenlose Community-API)
local RETRY = 120        -- Wartezeit nach einem Fehlversuch (FLIGHTRADAR_RETRY_MS)
local POOL = 16          -- behaltene Flugzeuge (Himmel sucht darin ein Bild; Firmware-Pool war 8)
local COVPOOL = 8        -- Abdeckungsauswertung: wie die Firmware nur die 8 naechsten
local KEEP = { "hex", "flight", "r", "t", "desc", "ownOp", "lat", "lon", "alt_baro", "gs", "track" }
local PHOTO_W, PHOTO_H = 430, 296 -- FR_PHOTO_BOX_W/H: Ersatzfoto als Arbeitsspeicher-Bild (ram), gedithert wie in der eingebauten App
local FI_W, FI_H = 406, 244 -- Renderbild der Flug-Seite: Bildkasten 430 x 296 minus 12 Pixel Rand, unten Platz fuer die Logo-Zeile
local MISS_TTL, MISS_MAX = 1800, 16 -- Negativ-Cache fuer fehlende NAS-Dateien (FR_ASSET_MISS_TTL_MS / FR_ASSET_MISS_CACHE)
local AIR_GAP = 1800     -- airlines.json hoechstens alle 30 Minuten vom NAS (FR_AIRLINES_JSON_INTERVAL_MS)
local COV_FLUSH = 600    -- Abdeckung alle 10 Minuten auf das NAS (FR_COV_FLUSH_INTERVAL_MS)
local COV_PROBES = 4     -- FR_COV_PROBES_PER_TICK
local PROBES = 16        -- storage.exists + storage.image je Lauf (Firmware-Grenze)
local SKY_VER = "r50"    -- FR_SKY_ASSET_VERSION

--#include text
--#include ui

-- ---------------------------------------------------------------------------
-- Einstellungen und Hilfen
-- ---------------------------------------------------------------------------

local function radiusOf(cfg)
  local r = tonumber(cfg.radius)
  if r == nil then return 25 end
  r = math.floor(r + 0.5)
  if r < 5 or r > 100 then return 25 end
  return r
end

local SKY = { white = color.WHITE, blue = color.BLUE, yellow = color.YELLOW, green = color.GREEN, black = color.BLACK }
local function skyOf(cfg)
  local s = cfg.sky
  if SKY[s] == nil then return "white" end
  return s
end

local function rnd(x) return math.floor(x + 0.5) end

local function keyOf(loc, radius) return string.format("%.4f,%.4f,%d", loc.lat, loc.lon, radius) end

local function split(s)
  local t, i = {}, 1
  while true do
    local j = s:find("\t", i, true)
    if not j then t[#t + 1] = s:sub(i); break end
    t[#t + 1] = s:sub(i, j - 1)
    i = j + 1
  end
  return t
end

local function icaoOf(cs)
  if #cs >= 3 and cs:sub(1, 3):find("^%u%u%u$") then return cs:sub(1, 3) end
  return nil
end

local DIRS_DE = { "N", "NO", "O", "SO", "S", "SW", "W", "NW" }
local DIRS_EN = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
local function compass(b) return (EN and DIRS_EN or DIRS_DE)[((b + 22) // 45) % 8 + 1] end

-- Grosskreis-Entfernung (km) und Richtung vom Standort zum Flugzeug (0 = Nord, 90 = Ost)
local RAD = math.pi / 180
local function distKm(la1, lo1, la2, lo2)
  local dLa, dLo = (la2 - la1) * RAD, (lo2 - lo1) * RAD
  local s1, s2 = math.sin(dLa / 2), math.sin(dLo / 2)
  local a = s1 * s1 + math.cos(la1 * RAD) * math.cos(la2 * RAD) * s2 * s2
  return 6371.0 * 2 * math.atan(math.sqrt(a), math.sqrt(1 - a))
end
local function bearing(la1, lo1, la2, lo2)
  local dLo = (lo2 - lo1) * RAD
  local y = math.sin(dLo) * math.cos(la2 * RAD)
  local x = math.cos(la1 * RAD) * math.sin(la2 * RAD) - math.sin(la1 * RAD) * math.cos(la2 * RAD) * math.cos(dLo)
  local d = rnd(math.atan(y, x) / RAD)
  if d < 0 then d = d + 360 end
  return d % 360
end

-- ---------------------------------------------------------------------------
-- Tabellen: assets/tables.txt (fest) und die airlines.json-Ueberlagerung "airl" (geht vor, wie in der Firmware)
-- ---------------------------------------------------------------------------

local TB -- Inhalt von assets/tables.txt mit fuehrendem Zeilenumbruch (je Lauf einmal gelesen)
local function tables()
  if TB == nil then TB = "\n" .. (asset.read("tables") or "") end
  return TB
end

local OV -- Ueberlagerung: air[ICAO] = {i, n, c}, airN = Reihenfolge, grp[Gruppe] = true, typ = {{Praefix, Gruppe, Lackierungen}}
local function overlay()
  if OV then return OV end
  OV = { air = {}, airN = {}, grp = {}, typ = {} }
  local txt = file.read("airl")
  if txt then
    for line in txt:gmatch("[^\n]+") do
      local f = split(line)
      if f[1] == "A" and f[2] then
        OV.air[f[2]] = { i = f[3] or "", n = f[4] or "", c = f[5] or "" }
        OV.airN[#OV.airN + 1] = f[2]
      elseif f[1] == "G" and f[2] then
        OV.grp[f[2]] = true
      elseif f[1] == "T" and f[2] and f[3] then
        OV.typ[#OV.typ + 1] = { f[2], f[3], f[4] == "1" }
      end
    end
  end
  return OV
end

-- IATA-Kuerzel, Klartext-Name und Leitwerksfarbe einer Airline: airlines.json je Eigenschaft vor der festen Tabelle
local function airInfo(icao)
  local o = overlay().air[icao]
  local bi, bn, bc = "", "", ""
  local s = tables():find("\nA;" .. icao .. ";", 1, true)
  if s then
    local e = TB:find("\n", s + 1, true) or (#TB + 1)
    bi, bn, bc = TB:sub(s + 3, e - 1):match("^[^;]*;([^;]*);([^;]*);([^;]*)")
    bi, bn, bc = bi or "", bn or "", bc or ""
  end
  return (o and o.i ~= "") and o.i or bi, (o and o.n ~= "") and o.n or bn, (o and o.c ~= "") and o.c or bc
end

-- Bild-Gruppe und "hat Lackierungen" zu einem ICAO-Typcode (Praefix-Vergleich, airlines.json zuerst); nil = unbekannter Typ
local function typeAsset(tc)
  if tc == nil or tc == "" then return nil end
  local ov = overlay()
  local g, base
  for _, e in ipairs(ov.typ) do
    if tc:sub(1, #e[1]) == e[1] then g, base = e[2], e[3]; break end
  end
  if not g then
    for p, grp, l in tables():gmatch("\nT;([^;]*);([^;]*);(%d)") do
      if tc:sub(1, #p) == p then g, base = grp, l == "1"; break end
    end
  end
  if not g then return nil end
  return g, base or ov.grp[g] == true
end

-- ---------------------------------------------------------------------------
-- Speicher: letzter Stand ("ac", mit letztem Fehlversuch) und Zustand ("st")
-- ---------------------------------------------------------------------------

local ACRAW = "" -- "ac" ohne E-Zeile (zum Anfuegen eines Fehlers)

local function saveAc(key, at, total, list)
  local out = { "H\t" .. key .. "\t" .. at .. "\t" .. total }
  for _, a in ipairs(list) do
    out[#out + 1] = table.concat({ "A", a.hex, a.cs, a.reg, a.tc, a.desc, a.air, string.format("%.4f", a.lat), string.format("%.4f", a.lon),
      a.gnd and 1 or 0, a.alt, a.gs, a.trk, string.format("%.2f", a.dist), a.brg, a.grp, a.lv and 1 or 0, a.ia, a.tl }, "\t")
  end
  return file.write("ac", table.concat(out, "\n"))
end

-- Stand und letzter Fehlversuch: ac (nil ohne gueltigen Stand), fail ({key, at, msg} oder nil)
local function loadAc()
  local txt = file.read("ac")
  if not txt then return nil, nil end
  local ac, fail, raw = { list = {} }, nil, {}
  for line in txt:gmatch("[^\n]+") do
    local f = split(line)
    if f[1] == "H" then
      ac.key, ac.at, ac.total = f[2], tonumber(f[3]) or 0, tonumber(f[4]) or 0
      raw[#raw + 1] = line
    elseif f[1] == "A" and #f >= 15 then
      ac.list[#ac.list + 1] = { hex = f[2], cs = f[3], reg = f[4], tc = f[5], desc = f[6], air = f[7], lat = tonumber(f[8]) or 0,
        lon = tonumber(f[9]) or 0, gnd = f[10] == "1", alt = tonumber(f[11]) or -1, gs = tonumber(f[12]) or -1,
        trk = tonumber(f[13]) or -1, dist = tonumber(f[14]) or 0, brg = tonumber(f[15]) or 0,
        grp = f[16] or "", lv = f[17] == "1", ia = f[18] or "", tl = f[19] or "" }
      raw[#raw + 1] = line
    elseif f[1] == "E" then
      fail = { key = f[2], at = tonumber(f[3]) or 0, msg = f[4] or "" }
    end
  end
  ACRAW = table.concat(raw, "\n")
  if ac.key == nil then ac = nil end
  return ac, fail
end

-- "Hauptflugzeug": das naechste Flugzeug, zu dem auf dem NAS ein passendes Bild liegt (ctx.data "ft" = hex). Es steht fuer Flug-Seite,
-- Route, Logo und Widget an erster Stelle der Liste; ohne Treffer bleibt die Reihenfolge nach Entfernung.
local function applyFeature(ctx, ac)
  local ft = ctx.data.get("ft")
  if type(ft) ~= "string" or ft == "" or not ac or not ac.list or (ac.list[1] and ac.list[1].hex == ft) then return end
  for i = 2, #ac.list do
    if ac.list[i].hex == ft then
      local a = table.remove(ac.list, i)
      table.insert(ac.list, 1, a)
      return
    end
  end
end

local function saveFail(key, now, msg)
  local line = "E\t" .. key .. "\t" .. now .. "\t" .. clean(msg, 100)
  return file.write("ac", ACRAW == "" and line or (ACRAW .. "\n" .. line))
end

local S -- Zustand aus "st" (je Lauf einmal gelesen, am Ende des Abrufs geschrieben)
local sDirty = false

local function stLoad()
  if S then return S end
  S = { miss = {}, sig = "", air = 0, seen = {}, seenSet = {}, ex = {}, exN = {}, bk = {}, dl = {} }
  local txt = file.read("st")
  if not txt then return S end
  for line in txt:gmatch("[^\n]+") do
    local f = split(line)
    local k = f[1]
    if k == "M" and f[2] then S.miss[#S.miss + 1] = { f[2], tonumber(f[3]) or 0 }
    elseif k == "S" then S.sig = f[2] or ""
    elseif k == "T" then S.air = tonumber(f[2]) or 0
    elseif k == "D" then S.dl[#S.dl + 1] = f[2] or ""
    elseif k == "C" then
      S.cv = { date = f[2] or "", time = f[3] or "", fn = f[4] or "fr_inkboard.csv", start = tonumber(f[5]) or 0, flush = tonumber(f[6]) or 0,
        pend = f[7] == "1", dirty = f[8] == "1", last = tonumber(f[9]) or 0, closed = f[10] == "1" }
    elseif k == "X" and f[2] then S.seen[#S.seen + 1] = f[2]; S.seenSet[f[2]] = true
    elseif k == "E" and f[2] then S.ex[f[2]] = tonumber(f[3]) or 0; S.exN[#S.exN + 1] = f[2]
    elseif k == "B" and #f >= 13 then
      local smp = {}
      for x in (f[14] or ""):gmatch("[^|]+") do smp[#smp + 1] = x end
      S.bk[#S.bk + 1] = { cat = tonumber(f[2]) or 0, grp = f[3], tc = f[4], tn = f[5], icao = f[6], ia = f[7], air = f[8], n = tonumber(f[9]) or 0,
        amin = tonumber(f[10]) or 0, amax = tonumber(f[11]) or 0, have = f[12] == "1", gnd = f[13] == "1", smp = smp }
    end
  end
  return S
end

local function stText(slim)
  local o = {}
  for _, m in ipairs(S.miss) do o[#o + 1] = "M\t" .. m[1] .. "\t" .. m[2] end
  o[#o + 1] = "S\t" .. S.sig
  o[#o + 1] = "T\t" .. S.air
  for _, l in ipairs(S.dl) do o[#o + 1] = "D\t" .. l end
  local cv = S.cv
  if cv then
    o[#o + 1] = table.concat({ "C", cv.date, cv.time, cv.fn, cv.start, cv.flush, cv.pend and 1 or 0, cv.dirty and 1 or 0, cv.last, cv.closed and 1 or 0 }, "\t")
    if not slim then
      for _, h in ipairs(S.seen) do o[#o + 1] = "X\t" .. h end
      for _, n in ipairs(S.exN) do o[#o + 1] = "E\t" .. n .. "\t" .. S.ex[n] end
    end
    for _, b in ipairs(S.bk) do
      o[#o + 1] = table.concat({ "B", b.cat, b.grp, b.tc, b.tn, b.icao, b.ia, b.air, b.n, b.amin, b.amax, b.have and 1 or 0, b.gnd and 1 or 0,
        table.concat(b.smp, "|") }, "\t")
    end
  end
  return table.concat(o, "\n")
end

local function stFlush()
  if not S or not sDirty then return end
  local txt = stText(false)
  if #txt > 23000 then txt = stText(true) end -- file.write nimmt hoechstens 24 KB
  local ok, err = file.write("st", txt)
  if not ok then log("Flight Radar: Zustand nicht gespeichert (" .. tostring(err) .. ")") end
  sDirty = false
end

local function missHas(name, now)
  for _, m in ipairs(S.miss) do
    if m[1] == name then return now - m[2] < MISS_TTL end
  end
  return false
end

local function missAdd(name, now)
  for _, m in ipairs(S.miss) do
    if m[1] == name then m[2] = now; sDirty = true; return end
  end
  if #S.miss >= MISS_MAX then table.remove(S.miss, 1) end
  S.miss[#S.miss + 1] = { name, now }
  sDirty = true
end

-- ---------------------------------------------------------------------------
-- NAS-Proben (storage.exists / storage.image): hoechstens 16 je Lauf, je Name einmal
-- ---------------------------------------------------------------------------

local probes = 0
local EXM = {} -- Ergebnisse dieses Laufs

-- true / false (fehlt auf dem NAS) / nil (nicht feststellbar); Treffer "fehlt" landen im Negativ-Cache
local function fileExists(name, now)
  if EXM[name] ~= nil then return EXM[name] end
  if missHas(name, now) then return false end
  if probes >= PROBES then return nil end
  probes = probes + 1
  local r, err = storage.exists("dir", name)
  if r == nil then log("Flight Radar: " .. name .. ": " .. tostring(err)); return nil end
  EXM[name] = r
  if not r then missAdd(name, now) end
  return r
end

-- Renderbild (<gruppe>.png bzw. <gruppe>_<iata>.png): bei Gruppen mit Lackierungen NUR das Lackierungsbild, kein Ersatzbild
local function skyFile(a)
  if a.grp == "" then return nil end
  if a.lv then
    if a.ia == "" then return nil end
    return a.grp .. "_" .. a.ia .. ".png"
  end
  return a.grp .. ".png"
end

-- ---------------------------------------------------------------------------
-- airlines.json (NAS) -> Ueberlagerung "airl"; Export des wirksamen Stands
-- ---------------------------------------------------------------------------

local CNAME = { black = "K", schwarz = "K", white = "W", weiss = "W", ["weiß"] = "W", red = "R", rot = "R", green = "G", gruen = "G",
  ["grün"] = "G", blue = "B", blau = "B", yellow = "Y", gelb = "Y" }
local CEXP = { K = "schwarz", W = "weiss", R = "rot", G = "gruen", B = "blau", Y = "gelb" }

local function oneLine(s, n)
  s = tostring(s):gsub("%c", " ")
  return s:sub(1, n)
end

-- airlines.json -> neue Ueberlagerung (gleiche Regeln und Grenzen wie frAirlinesJsonApplyBuffer: 64 Airlines, 16 Gruppen, 32 Typen)
local function parseAirlines(doc)
  local n = { air = {}, airN = {}, grp = {}, grpN = {}, typ = {} }
  local skipped = 0
  if type(doc.airlines) == "table" then
    for _, o in ipairs(doc.airlines) do
      if #n.airN >= 64 then
        skipped = skipped + 1
      elseif type(o) == "table" and type(o.icao) == "string" and #o.icao == 3 then
        local icao = o.icao:upper()
        local iata = type(o.iata) == "string" and #o.iata == 2 and o.iata:lower() or ""
        local name = type(o.name) == "string" and oneLine(o.name, 31) or ""
        local c = type(o.color) == "string" and CNAME[o.color:lower()] or ""
        n.air[icao] = { i = iata, n = name, c = c }
        n.airN[#n.airN + 1] = icao
      else
        skipped = skipped + 1
      end
    end
  end
  if type(doc.enableLiveryGroups) == "table" then
    for _, g in ipairs(doc.enableLiveryGroups) do
      if #n.grpN >= 16 then break end
      if type(g) == "string" and g ~= "" then
        n.grp[g:sub(1, 15)] = true
        n.grpN[#n.grpN + 1] = g:sub(1, 15)
      end
    end
  end
  if type(doc.aircraftTypes) == "table" then
    for _, o in ipairs(doc.aircraftTypes) do
      local p, g = type(o) == "table" and o.prefix, type(o) == "table" and o.group
      if #n.typ >= 32 then
        skipped = skipped + 1
      elseif type(p) == "string" and type(g) == "string" and #p >= 1 and #p <= 7 and #g >= 1 and #g <= 15 then
        local l = o.hasLiveries
        if type(l) ~= "boolean" then l = true end
        n.typ[#n.typ + 1] = { p:upper(), g, l }
      else
        skipped = skipped + 1
      end
    end
  end
  return n, skipped
end

local function overlayText(n)
  local o = {}
  for _, k in ipairs(n.airN) do
    local a = n.air[k]
    o[#o + 1] = "A\t" .. k .. "\t" .. a.i .. "\t" .. a.n .. "\t" .. a.c
  end
  for _, g in ipairs(n.grpN) do o[#o + 1] = "G\t" .. g end
  for _, t in ipairs(n.typ) do o[#o + 1] = "T\t" .. t[1] .. "\t" .. t[2] .. "\t" .. (t[3] and 1 or 0) end
  return table.concat(o, "\n")
end

-- Vorher/Nachher wie frAirlinesJsonBuildDiff(): Zeilen fuer das Geraete-Log, Zaehler fuer die Meldung
local function diffOverlay(old, new)
  local lines, plus, tilde, minus = {}, 0, 0, 0
  local function dash(s) return s ~= "" and s or "-" end
  for _, k in ipairs(new.airN) do
    local b, a = old.air[k], new.air[k]
    if not b then
      plus = plus + 1
      lines[#lines + 1] = "+ " .. k .. (a.n ~= "" and (" (" .. a.n .. ")") or "")
    else
      local ch = ""
      if b.i ~= a.i then ch = ch .. "IATA " .. dash(b.i) .. "->" .. dash(a.i) .. "; " end
      if b.n ~= a.n then ch = ch .. "Name " .. dash(b.n) .. "->" .. dash(a.n) .. "; " end
      if b.c ~= a.c then ch = ch .. "Farbe geaendert; " end
      if ch ~= "" then tilde = tilde + 1; lines[#lines + 1] = "~ " .. k .. ": " .. ch end
    end
  end
  for _, k in ipairs(old.airN) do
    if not new.air[k] then minus = minus + 1; lines[#lines + 1] = "- " .. k .. " (nicht mehr in airlines.json enthalten)" end
  end
  for g in pairs(new.grp) do
    if not old.grp[g] then plus = plus + 1; lines[#lines + 1] = '+ Baugruppe "' .. g .. '" freigeschaltet' end
  end
  for g in pairs(old.grp) do
    if not new.grp[g] then minus = minus + 1; lines[#lines + 1] = '- Baugruppe "' .. g .. '" nicht mehr freigeschaltet' end
  end
  local oldT = {}
  for _, t in ipairs(old.typ) do oldT[t[1]] = t end
  local newT = {}
  for _, t in ipairs(new.typ) do
    newT[t[1]] = true
    local b = oldT[t[1]]
    if not b then
      plus = plus + 1
      lines[#lines + 1] = '+ Typcode "' .. t[1] .. '" -> Gruppe "' .. t[2] .. '"' .. (t[3] and "" or " (ohne Lackierungen)")
    else
      local ch = ""
      if b[2] ~= t[2] then ch = ch .. "Gruppe " .. b[2] .. "->" .. t[2] .. "; " end
      if b[3] ~= t[3] then ch = ch .. "Lackierungen " .. (b[3] and "an" or "aus") .. "->" .. (t[3] and "an" or "aus") .. "; " end
      if ch ~= "" then tilde = tilde + 1; lines[#lines + 1] = '~ Typcode "' .. t[1] .. '": ' .. ch end
    end
  end
  for _, t in ipairs(old.typ) do
    if not newT[t[1]] then minus = minus + 1; lines[#lines + 1] = '- Typcode "' .. t[1] .. '" (nicht mehr in airlines.json enthalten)' end
  end
  return lines, plus, tilde, minus
end

-- Nimmt den Text einer airlines.json an: true, Meldung (Ueberlagerung "airl" und Himmel-Kennung werden erneuert)
local function applyAirlines(txt)
  local doc, derr = json.decode(txt)
  if type(doc) ~= "table" then
    log("Flight Radar: airlines.json nicht lesbar (" .. tostring(derr) .. ") - bisheriger Stand bleibt aktiv.")
    return false, T("airlines.json nicht lesbar - bisheriger Stand bleibt aktiv.", "airlines.json not readable - the previous state stays active.")
  end
  local new, skipped = parseAirlines(doc)
  local lines, plus, tilde, minus = diffOverlay(overlay(), new)
  local ok, err = file.write("airl", overlayText(new))
  if not ok then return false, "file: " .. tostring(err) end
  OV = new -- gleiche Form wie von overlay() gelesen
  stLoad().sig = ""
  -- Aenderungsliste der letzten Uebernahme (im Zustand "st", Zeilen "D"): wie frDiffAppendLine() nach 1800 Zeichen mit "..." abgeschnitten;
  -- die Einstellung "airDiff" laedt sie als Datei herunter (die Meldung selbst fasst nur 160 Byte)
  S.dl = {}
  local used = 0
  for _, l in ipairs(lines) do
    if used > 1800 then S.dl[#S.dl + 1] = "..."; break end
    S.dl[#S.dl + 1] = l
    used = used + #l + 1
  end
  if #S.dl == 0 then S.dl[1] = "(keine Aenderungen gegenueber dem vorherigen Stand)" end
  sDirty = true
  for _, l in ipairs(lines) do log("Flight Radar: airlines.json " .. l) end
  local msg = string.format(T("airlines.json geladen: %d Airlines, %d Liverei-Gruppen, %d Flugzeugtypen. Änderungen: +%d ~%d -%d.", "airlines.json loaded: %d airlines, %d livery groups, %d aircraft types. Changes: +%d ~%d -%d."),
    #new.airN, #new.grpN, #new.typ, plus, tilde, minus)
  if skipped > 0 then msg = msg .. string.format(T(" %d ungültige übersprungen.", " %d invalid skipped."), skipped) end
  if lines[1] then msg = msg .. " " .. cut(lines[1], 36) end
  return true, msg
end

-- Wirksamer Gesamtstand im airlines.json-Format (frAirlinesJsonBuildExport): Tabellen und Ueberlagerung zusammengefuehrt
local function exportJson()
  local ov = overlay()
  local order, seen = {}, {}
  for icao in tables():gmatch("\nA;(%u+);") do
    if not seen[icao] then seen[icao] = true; order[#order + 1] = icao end
  end
  for _, k in ipairs(ov.airN) do
    if not seen[k] then seen[k] = true; order[#order + 1] = k end
  end
  local out = { '{\n  "airlines": [\n' }
  for i, icao in ipairs(order) do
    local ia, nm, c = airInfo(icao)
    local row = '    {"icao": "' .. icao .. '"'
    if ia ~= "" then row = row .. ', "iata": "' .. ia .. '"' end
    if nm ~= "" then row = row .. ', "name": "' .. nm:gsub('"', "'") .. '"' end
    if c ~= "" then row = row .. ', "color": "' .. CEXP[c] .. '"' end
    out[#out + 1] = row .. "}" .. (i < #order and "," or "") .. "\n"
  end
  out[#out + 1] = '  ],\n  "enableLiveryGroups": [\n'
  local groups, gseen, types, over = {}, {}, {}, {}
  for _, e in ipairs(ov.typ) do over[e[1]] = true end
  local tbl = {}
  for p, g, l in tables():gmatch("\nT;([^;]*);([^;]*);(%d)") do tbl[#tbl + 1] = { p, g, l == "1" } end
  for _, e in ipairs(tbl) do
    if (e[3] or ov.grp[e[2]]) and not gseen[e[2]] then gseen[e[2]] = true; groups[#groups + 1] = e[2] end
  end
  local gk = {}
  for g in pairs(ov.grp) do gk[#gk + 1] = g end
  table.sort(gk)
  for _, g in ipairs(gk) do
    if not gseen[g] then gseen[g] = true; groups[#groups + 1] = g end
  end
  for i, g in ipairs(groups) do out[#out + 1] = '    "' .. g .. '"' .. (i < #groups and "," or "") .. "\n" end
  for _, e in ipairs(ov.typ) do types[#types + 1] = { e[1], e[2], e[3] } end
  for _, e in ipairs(tbl) do
    if not over[e[1]] then types[#types + 1] = { e[1], e[2], e[3] or ov.grp[e[2]] == true } end
  end
  out[#out + 1] = '  ],\n  "aircraftTypes": [\n'
  for i, e in ipairs(types) do
    out[#out + 1] = '    {"prefix": "' .. e[1] .. '", "group": "' .. e[2] .. '", "hasLiveries": ' .. (e[3] and "true" or "false") .. "}" ..
      (i < #types and "," or "") .. "\n"
  end
  out[#out + 1] = "  ]\n}\n"
  return table.concat(out)
end

-- ---------------------------------------------------------------------------
-- Abdeckungsauswertung (frCoverage*, CHANGELOG 409): CSV im Schema der Mac-App auf dem NAS
-- ---------------------------------------------------------------------------

local CATS = { [0] = "Fehlendes Lackierungsbild", "Fehlendes Basisbild", "Airline ohne IATA-Zuordnung", "Unbekannter Flugzeugtyp" }
local CHEAD = { "Scan-Datum", "Scan-Uhrzeit", "Kategorie", "Flugzeugtyp", "Typ-Code", "Flugzeuggruppe", "Airline", "Airline-ICAO", "Airline-IATA",
  "Anzahl Sichtungen", "Reisehöhe", "Beispiele (Callsign/Registrierung)", "Route (Linienflug?)", "Historie (fruehere Scans)", "Hinweis" }

local function csvField(s)
  s = tostring(s)
  if s:find('[;"\r\n]') then return '"' .. (s:gsub('"', '""')) .. '"' end
  return s
end

-- 12345 -> "12.345"
local function fmtInt(v)
  local s = tostring(math.abs(v))
  local o = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
  if o:sub(1, 1) == "." then o = o:sub(2) end
  return (v < 0 and "-" or "") .. o
end

local function covCsv()
  local out = { "\xEF\xBB\xBF" }
  local row = {}
  for i, h in ipairs(CHEAD) do row[i] = csvField(h) end
  out[#out + 1] = table.concat(row, ";") .. "\r\n"
  local ord = {}
  for i = 1, #S.bk do ord[i] = S.bk[i] end
  for i = 2, #ord do -- stabil: Kategorie aufsteigend, Anzahl absteigend (reportCSV)
    local key, j = ord[i], i - 1
    while j >= 1 and (ord[j].cat > key.cat or (ord[j].cat == key.cat and ord[j].n < key.n)) do ord[j + 1] = ord[j]; j = j - 1 end
    ord[j + 1] = key
  end
  for _, b in ipairs(ord) do
    local alt
    if b.have then
      alt = b.amin == b.amax and (fmtInt(b.amin) .. " ft") or (fmtInt(b.amin) .. "-" .. fmtInt(b.amax) .. " ft")
    else
      alt = b.gnd and "Boden" or "?"
    end
    local hint
    if b.cat == 0 then hint = string.format("Datei %s_%s.png im Asset-Paket ergaenzen", b.grp, b.ia)
    elseif b.cat == 1 then hint = string.format("Basisdatei %s.png im Asset-Paket ergaenzen", b.grp)
    elseif b.cat == 2 then hint = string.format('FR_ICAO_IATA um "%s" erweitern - UND danach vermutlich auch die Lackierung %s_??.png ergaenzen', b.icao, b.grp)
    else hint = string.format('FR_TYPE_ASSETS um "%s" (%s) erweitern', b.tc, b.tn) end
    local f = { S.cv.date, S.cv.time, CATS[b.cat], b.tn, b.tc, b.grp, b.air, b.icao, b.ia, tostring(b.n), alt, table.concat(b.smp, ", "), "", "", hint }
    for i = 1, #f do f[i] = csvField(f[i]) end
    out[#out + 1] = table.concat(f, ";") .. "\r\n"
  end
  return table.concat(out)
end

-- Schreibt den Stand auf das NAS (Feld "cov"): true / false, Fehler / nil (kein NAS)
local function covFlush(now)
  local cv = S.cv
  if not cv then return nil end
  cv.flush, cv.dirty = now, false
  sDirty = true
  if not storage.ready() then return nil end
  local ok, err = storage.write("cov", cv.fn, covCsv())
  cv.pend = not ok
  log(string.format("Flight Radar: Auswertung %s (%d Punkte) %s.", cv.fn, #S.bk, ok and "auf dem NAS abgelegt" or ("NICHT auf das NAS geschrieben: " .. tostring(err))))
  return ok, err
end

local function covStart(now)
  stLoad()
  if S.cv and (S.cv.pend or S.cv.dirty) then covFlush(now) end -- letzte Auswertung noch aufs NAS, bevor sie ersetzt wird
  local t = time.localtime()
  local cv = { date = "", time = "", fn = "fr_inkboard.csv", start = now, flush = now, pend = false, dirty = false, last = now, closed = false }
  if t then
    cv.date = string.format("%02d.%02d.%04d", t.day, t.month, t.year % 10000)
    cv.time = string.format("%02d:%02d", t.hour, t.min)
    cv.fn = string.format("fr_inkboard_%04d%02d%02d_%02d%02d.csv", t.year, t.month, t.day, t.hour, t.min)
  end
  S.cv, S.seen, S.seenSet, S.ex, S.exN, S.bk = cv, {}, {}, {}, {}, {}
  sDirty = true
end

-- Eimer anlegen bzw. hochzaehlen (Schluessel je Kategorie wie in der Mac-App)
local function covAdd(cat, grp, ia, a, icao)
  local b
  for _, e in ipairs(S.bk) do
    if e.cat == cat and ((cat == 0 and e.grp == grp and e.ia == ia) or (cat == 1 and e.grp == grp) or (cat == 2 and e.icao == icao and e.grp == grp)
        or (cat == 3 and e.tc == a.tc)) then b = e; break end
  end
  if not b then
    if #S.bk >= 48 then return end -- voll: weitere NEUE Kombinationen dieser Sitzung entfallen
    b = { cat = cat, grp = grp, tc = a.tc, tn = a.desc, icao = icao, ia = ia, air = a.air, n = 0, amin = 0, amax = 0, have = false, gnd = false, smp = {} }
    S.bk[#S.bk + 1] = b
  end
  if b.n < 65535 then b.n = b.n + 1 end
  if b.tn == "" then b.tn = a.desc end
  if b.air == "" then b.air = a.air end
  local smp = (a.cs ~= "" and a.cs or "?") .. "/" .. (a.reg ~= "" and a.reg or "?")
  local known = false
  for _, x in ipairs(b.smp) do if x == smp then known = true end end
  if not known and #b.smp < 6 then b.smp[#b.smp + 1] = smp end
  if a.gnd then b.gnd = true
  elseif not b.have then b.amin, b.amax, b.have = a.alt, a.alt, true
  else
    if a.alt < b.amin then b.amin = a.alt end
    if a.alt > b.amax then b.amax = a.alt end
  end
  S.cv.dirty = true
  sDirty = true
end

-- Existiert <name> auf dem NAS? 1 / 0 / -1 (nicht feststellbar) / -2 (Sondier-Budget dieses Laufs leer, spaeter erneut)
local function covExists(name, now, left)
  if S.ex[name] ~= nil then return S.ex[name], left end
  local v = EXM[name]
  if v == nil and missHas(name, now) then v = false end
  if v == nil then
    if left <= 0 or probes >= PROBES then return -2, left end
    left = left - 1
    v = fileExists(name, now)
    if v == nil then return -1, left end
  end
  local r = v and 1 or 0
  if #S.exN < 48 then S.exN[#S.exN + 1] = name; S.ex[name] = r; sDirty = true end
  return r, left
end

-- Wertet EIN Flugzeug aus (frCovClassify): true = abschliessend, false = spaeter noch einmal
local function covClassify(a, now, left)
  if a.tc == "" then return true, left end
  local icao = icaoOf(a.cs) or ""
  if a.grp == "" then covAdd(3, "", "", a, icao); return true, left end
  local nasOk = storage.ready()
  local base = a.grp .. ".png"
  local e, b
  if not a.lv then
    if not nasOk then return true, left end
    e, left = covExists(base, now, left)
    if e == 0 then covAdd(1, a.grp, "", a, icao) end
    return e >= 0, left
  end
  if a.ia == "" then covAdd(2, a.grp, "", a, icao); return true, left end
  if not nasOk then return true, left end
  e, left = covExists(a.grp .. "_" .. a.ia .. ".png", now, left)
  if e < 0 then return false, left end
  if e == 1 then return true, left end
  b, left = covExists(base, now, left)
  if b < 0 then return false, left end
  if b == 0 then covAdd(1, a.grp, "", a, icao) else covAdd(0, a.grp, a.ia, a, icao) end
  return true, left
end

local function covStep(ac, now)
  stLoad()
  -- neue Sitzung, wenn die App verlassen wurde (on_close setzt "closed"); Rueckfall ohne on_close (Neustart, Tiefschlaf ohne Hook): ueber 15 Minuten Luecke
  if not S.cv or S.cv.closed or now - S.cv.last > 900 then covStart(now) end
  S.cv.last = now
  local left = COV_PROBES
  for i = 1, math.min(#ac.list, COVPOOL) do
    local a = ac.list[i]
    if a.hex ~= "" and not S.seenSet[a.hex] then
      local done
      done, left = covClassify(a, now, left)
      if done then
        if #S.seen >= 96 then S.seenSet[table.remove(S.seen, 1)] = nil end
        S.seen[#S.seen + 1] = a.hex
        S.seenSet[a.hex] = true
        sDirty = true
      end
    end
  end
  if S.cv.dirty and now - S.cv.flush >= COV_FLUSH then covFlush(now) end
end

local function covSummary()
  local c = { [0] = 0, 0, 0, 0 }
  for _, b in ipairs(S.bk) do c[b.cat] = c[b.cat] + 1 end
  return string.format(T("%d Punkte: %d Lackierung fehlt, %d Basisbild fehlt, %d Airline ohne IATA, %d unbekannter Typ.",
    "%d items: %d livery missing, %d base image missing, %d airline without IATA, %d unknown type."), #S.bk, c[0], c[1], c[2], c[3])
end

-- ---------------------------------------------------------------------------
-- Abruf
-- ---------------------------------------------------------------------------

local function visible(ctx)
  if ctx.view == nil or ctx.view == "app" then return true end -- ohne ctx.view (aeltere Firmware): wie frueher
  return ctx.view == "dashboard" and #(ctx.widgets or {}) > 0
end

local function fld(v, n)
  if type(v) ~= "string" then return "" end
  return clean(v, n)
end

-- Ein Flugzeug aus dem adsb.lol-Objekt (Feldlaengen wie FlightAircraft)
local function makeAc(a, d, loc)
  local cs = fld(a.flight, 9)
  local icao = icaoOf(cs)
  local ia, nm, tl = "", "", ""
  if icao then ia, nm, tl = airInfo(icao) end
  local air = fld(a.ownOp, 35)
  if air == "" then air = nm end
  local tc = fld(a.t, 5)
  local grp, lv = typeAsset(tc)
  local ab = a.alt_baro
  local gnd = type(ab) == "string"
  local trk = type(a.track) == "number" and rnd(a.track) % 360 or -1
  return { hex = fld(a.hex, 7), cs = cs, reg = fld(a.r, 11), tc = tc, desc = fld(a.desc, 39), air = air,
    lat = a.lat, lon = a.lon, gnd = gnd, alt = gnd and 0 or (type(ab) == "number" and rnd(ab) or -1),
    gs = type(a.gs) == "number" and rnd(a.gs) or -1, trk = trk, dist = d, brg = bearing(loc.lat, loc.lon, a.lat, a.lon),
    grp = grp or "", lv = lv == true, ia = ia, tl = tl }
end

-- Antwort -> naechste Flugzeuge (hoechstens POOL) und Gesamtzahl im Radius; nil = keine "ac"-Liste
local function parseAc(body, loc, radius)
  local p = body:find('"ac":[', 1, true)
  if not p then return nil end
  local pool, total = {}, 0
  for obj in body:gmatch("%b{}", p + 6) do
    local a = json.decode(obj)
    if type(a) == "table" and type(a.lat) == "number" and type(a.lon) == "number" then
      local d = distKm(loc.lat, loc.lon, a.lat, a.lon)
      if d <= radius + 0.5 then -- der Radius wird in Seemeilen (aufgerundet) angefragt: hart auf den km-Radius nachfiltern
        total = total + 1
        local slot
        if #pool < POOL then
          slot = #pool + 1
        else
          local worst, wi = -1, nil
          for i = 1, #pool do
            if pool[i].dist > worst then worst, wi = pool[i].dist, i end
          end
          if wi and d < worst then slot = wi end
        end
        if slot then pool[slot] = makeAc(a, d, loc) end
      end
    end
  end
  table.sort(pool, function(x, y) return x.dist < y.dist end)
  return pool, total
end

-- Route des naechsten Flugzeugs (best effort, nur bei geaendertem Rufzeichen) -> ctx.data "rt" = Rufzeichen|von|nach
local function routeStep(ctx, first)
  local cs = first.cs:gsub("[^%w]", "")
  if cs == "" then ctx.data.set("rt", nil); return end
  local rt = ctx.data.get("rt")
  if type(rt) == "string" and rt:match("^([^|]*)") == cs then return end
  local from, to = "", ""
  local body = '{"planes":[{"callsign":"' .. cs .. '","lat":' .. string.format("%.4f", first.lat) .. ',"lng":' .. string.format("%.4f", first.lon) .. "}]}"
  local r = http.request{ url = ADSB .. "/api/0/routeset", method = "POST", body = body, maxBytes = 8192,
    headers = { ["Content-Type"] = "application/json", Accept = "application/json" } }
  if r and r.status == 200 then
    local doc = json.decode(r.body)
    local codes = type(doc) == "table" and type(doc[1]) == "table" and doc[1]._airport_codes_iata
    -- "HAM-PMI" (bei mehreren Etappen "AAA-BBB-CCC": erster und letzter Code); "unknown" = keine verlaessliche Route
    if type(codes) == "string" and codes ~= "" and not codes:find("unknown", 1, true) then
      local a, b = codes:match("^([^-]+).*%-([^-]+)$")
      if a and #a >= 3 and #b >= 3 then from, to = a:sub(1, 4), b:sub(1, 4) end
    end
  else
    log("Flight Radar: Route nicht abrufbar")
  end
  ctx.data.set("rt", cs .. "|" .. from .. "|" .. to)
end

-- Ersatzfoto des naechsten Flugzeugs (nur wenn die App angezeigt wird, einmal je Maschine, und nur wenn auf dem NAS kein Renderbild
-- fuer die Flug-Seite liegt, siehe flightImgStep) -> ctx.data "ph" = hex|Fotograf|1/0
local function photoStep(ctx, first)
  local hex = first.hex:gsub("[^%w]", "")
  if hex == "" then return end
  local ph = ctx.data.get("ph")
  if type(ph) == "string" and ph:match("^([^|]*)") == hex then
    if not ph:match("|1$") or draw.image_size("photo") then return end -- Bild nach einem Neustart weg: neu laden
  end
  ctx.data.set("ph", hex .. "||0") -- geprueft: auch bei "kein Foto" kein Dauer-Retry fuer dieselbe Maschine
  local r = http.request{ url = PLANESPOTTERS .. hex, maxBytes = 8192, keep = { "src", "photographer" }, headers = { Accept = "application/json" } }
  if not r or r.status ~= 200 then log("Flight Radar: Foto-Suche fehlgeschlagen"); return end
  local doc = json.decode(r.body)
  local p = type(doc) == "table" and type(doc.photos) == "table" and doc.photos[1]
  if type(p) ~= "table" then log("Flight Radar: kein Foto fuer " .. hex); return end
  local src = (type(p.thumbnail_large) == "table" and p.thumbnail_large.src) or (type(p.thumbnail) == "table" and p.thumbnail.src)
  if type(src) ~= "string" or src == "" then return end
  local who = fld(p.photographer, 39):gsub("|", "/")
  local ok, err = http.image(src, "photo", PHOTO_W, PHOTO_H, { ram = true })
  if ok then ctx.data.set("ph", hex .. "|" .. who .. "|1") else log("Flight Radar: Foto " .. tostring(err)) end
end

-- Airline-Logo (VRS-Operator-Flag logos/<ICAO>.bmp, 85 x 20) des naechsten Flugzeugs -> ctx.data "lg" = ICAO|1/0
local function logoStep(ctx, first, now)
  if not storage.ready() then return end
  local icao = icaoOf(first.cs)
  local lg = ctx.data.get("lg")
  local cur, okc = "", "0"
  if type(lg) == "string" then cur, okc = lg:match("^([^|]*)|(%d)$") end
  if not icao then
    if cur ~= "" or lg == nil then ctx.data.set("lg", "|0") end
    return
  end
  if cur == icao and (okc ~= "1" or draw.image_size("logo")) then return end
  ctx.data.set("lg", icao .. "|0") -- geprueft: auch bei "kein Logo" kein Dauer-Retry
  local name = "logos/" .. icao .. ".bmp"
  if missHas(name, now) or probes >= PROBES then return end
  probes = probes + 1
  local w, h = storage.image("dir", name, "logo", { w = 85, h = 20 })
  if w == 85 and h == 20 then
    ctx.data.set("lg", icao .. "|1")
  elseif w then
    log(string.format("Flight Radar: Logo %s hat unerwartete Groesse (%dx%d).", name, w, h))
  else
    if tostring(h):find("nicht gefunden", 1, true) then missAdd(name, now) end
    log("Flight Radar: Logo " .. name .. ": " .. tostring(h))
  end
end

-- Gibt es <name> auf dem NAS? true / false / nil (nicht feststellbar oder Probenbudget bis cap erreicht).
-- Bekannte Treffer/Fehlen (Abdeckungs-Cache S.ex, Lauf-Ergebnis EXM, Negativ-Cache) kosten keine Probe.
local function nasKnown(name, now, cap)
  stLoad()
  local v = S.ex[name]
  if v ~= nil then return v == 1 end
  if EXM[name] == nil and not missHas(name, now) and probes >= cap then return nil end
  return fileExists(name, now)
end

-- Waehlt das Hauptflugzeug: das erste der Liste mit passendem NAS-Bild (Lackierung bzw. Gruppenbild); danach wird die Liste umsortiert.
-- Ist das Probenbudget leer, bevor etwas gefunden wurde, bleibt die bisherige Wahl; sonst ohne Treffer keine Wahl (Reihenfolge nach Entfernung).
local function featureStep(ctx, ac, now)
  if not storage.ready() then return end
  local pick, partial, gone = nil, false, false
  local old = ctx.data.get("ft")
  for i = 1, #ac.list do
    local name = skyFile(ac.list[i])
    if name then
      local r = nasKnown(name, now, 9)
      if r then pick = ac.list[i].hex; break end
      if r == nil then partial = true elseif ac.list[i].hex == old then gone = true end
    end
  end
  if pick then
    ctx.data.set("ft", pick)
  elseif not partial or gone then
    ctx.data.set("ft", nil)
  end
  applyFeature(ctx, ac)
end

-- Renderbild der Flug-Seite fuer das NAECHSTE Flugzeug: dieselbe Datei wie auf der Himmel-Seite (skyFile: <gruppe>.png bzw.
-- <gruppe>_<iata>.png), Freisteller mit schwarzer Kontur, Arbeitsspeicher-Name "fplane". Ohne Vorab-Probe (ein storage.image-Aufruf statt
-- zwei): "nicht gefunden" landet im Negativ-Cache, ein Treffer ersetzt die Probe der Himmel-Seite (EXM) - zusammen hoechstens
-- 16 Proben je Lauf. ctx.data "fi" = Datei|1/0|Zeit:
-- 1 = geladen, 0 = auf dem NAS nichts Passendes (kein NAS, unbekannter Typ, Datei fehlt); 0 wird nach MISS_TTL neu geprueft.
-- Rueckgabe: true = Bild da, false = nichts Passendes (Ersatzfoto), nil = noch nicht entscheidbar (Probenbudget leer)
local function flightImgStep(ctx, first, now)
  local name = skyFile(first) or "-"
  local cur, st, at
  local fi = ctx.data.get("fi")
  if type(fi) == "string" then cur, st, at = fi:match("^([^|]*)|(%d)|(%d+)$") end
  if cur == name then
    if st == "1" and draw.image_size("fplane") then return true end -- nach einem Neustart weg: neu laden
    if st == "0" and now - (tonumber(at) or 0) < MISS_TTL then return false end
  end
  local function done(ok)
    ctx.data.set("fi", name .. "|" .. (ok and 1 or 0) .. "|" .. now)
    return ok
  end
  if name == "-" or not storage.ready() then return done(false) end
  stLoad()
  if missHas(name, now) then return done(false) end
  if probes >= PROBES then return nil end
  probes = probes + 1
  local w, h = storage.image("dir", name, "fplane", { w = FI_W, h = FI_H, up = 133, style = "cutout", outline = color.BLACK })
  if w and w >= 8 and h >= 8 then
    EXM[name] = true
    return done(true)
  end
  if not w and tostring(h):find("nicht gefunden", 1, true) then
    missAdd(name, now)
    return done(false)
  end
  log("Flight Radar: Flug-Bild " .. name .. ": " .. tostring(h)) -- Fehler (z. B. Verbindung) ist kein Fehlen: nichts merken, naechster Lauf probiert erneut
  return false
end

-- Formation (FR_SKY_SLOTS_1/2/3): Leader gross unten rechts, weitere versetzt darueber, disjunkte Zeilenbaender -> keine Ueberlappung.
-- Je Eintrag: x0, x1, y0, y1, Mittelpunkt x, Label unter dem Bild
local SLOTS = {
  { { 20, 780, 20, 414, 400, true } },
  { { 200, 785, 168, 414, 520, true }, { 15, 520, 24, 160, 250, false } },
  { { 230, 785, 230, 414, 520, true }, { 110, 500, 122, 222, 290, false }, { 15, 320, 24, 114, 160, false } },
}

local function skySig(ctx, ac)
  local p = { SKY_VER, skyOf(ctx.cfg) }
  for i = 1, math.min(#ac.list, POOL) do
    local a = ac.list[i]
    p[#p + 1] = (a.grp ~= "" and a.grp or "-") .. ":" .. ((a.lv and a.ia ~= "") and a.ia or "-")
  end
  return table.concat(p, "|")
end

-- Sind alle im Layout verzeichneten Bilder noch im Arbeitsspeicher (nach einem Neustart nicht)?
local function skyImagesThere(sk)
  for _, e in ipairs(sk) do
    if not draw.image_size("sky" .. e.idx) then return false end
  end
  return true
end

local function skyParse(v)
  if type(v) ~= "string" then return nil, {} end
  local sig, rest = v:match("^([^~]*)~(.*)$")
  if not sig then return nil, {} end
  local list = {}
  for ent in rest:gmatch("[^;]+") do
    local f = {}
    for n in ent:gmatch("[^,]+") do f[#f + 1] = n end
    if #f >= 9 then
      list[#list + 1] = { hex = f[1], idx = tonumber(f[2]), x = tonumber(f[3]), y = tonumber(f[4]), lx = tonumber(f[5]), ly = tonumber(f[6]),
        lw = tonumber(f[7]) }
    end
  end
  return sig, list
end

-- Komponiert den Himmel (frComposeSkyIfNeeded): Phase A Dateien suchen, Phase B Formation nach Trefferzahl, Phase C Bilder laden
local function skyStep(ctx, ac, now)
  if not storage.ready() then return end
  stLoad()
  local sig = skySig(ctx, ac)
  local _, cur = skyParse(ctx.data.get("sk"))
  if S.sig == sig and skyImagesThere(cur) then return end
  -- Phase A: ueber den ganzen Pool (nach Entfernung) Dateien suchen. Erst Lackierungsbilder (<gruppe>_<iata>.png); gibt es im ganzen Pool
  -- keines, das Gruppenbild (<gruppe>.png) des Typs - so ist die Seite nie leer, solange irgendein Bild passt. Bekannte Treffer/Fehlen
  -- (Abdeckungs-Cache S.ex, Negativ-Cache) kosten keine Probe; fuer das Laden der Bilder bleibt Budget reserviert.
  local cands, partial, generic = {}, false, false
  local function known(name)
    local r = nasKnown(name, now, PROBES - #cands - 1)
    if r == nil then partial = true; return false end
    return r
  end
  for i = 1, math.min(#ac.list, POOL) do
    if #cands >= 3 then break end
    local a = ac.list[i]
    local name = skyFile(a)
    if name and known(name) then cands[#cands + 1] = { a = a, name = name } end
  end
  if #cands == 0 then
    local seen = {}
    for i = 1, math.min(#ac.list, POOL) do
      if #cands >= 3 then break end
      local a = ac.list[i]
      if a.grp ~= "" and a.lv and not seen[a.grp] then
        seen[a.grp] = true
        local name = a.grp .. ".png"
        if known(name) then cands[#cands + 1] = { a = a, name = name }; generic = true end
      end
    end
  end
  if #cands == 0 and partial then return end -- Budget leer: naechster Lauf sucht mit Negativ-Cache weiter
  local slots = SLOTS[#cands]
  local ent = {}
  local ol = (skyOf(ctx.cfg) == "blue" or skyOf(ctx.cfg) == "black") and color.WHITE or color.BLACK -- Kontur: Weiss auf Blau/Schwarz
  for c, cand in ipairs(cands) do
    local s = slots[c]
    local x0, x1, y0, y1, scx, below = s[1], s[2], s[3], s[4], s[5], s[6]
    local slotW, slotH = x1 - x0, y1 - y0 - (below and 26 or 0)
    if probes >= PROBES then break end
    probes = probes + 1
    local w, h = storage.image("dir", cand.name, "sky" .. c, { w = math.min(slotW - 8, 600), h = slotH, up = 133, style = "cutout", outline = ol })
    if w and w >= 8 and h >= 8 then
      local x = math.max(x0, math.min(x1 - w, scx - w // 2))
      local y = math.max(y0, math.min(y0 + slotH - h, y0 + slotH // 2 - h // 2))
      local lx, ly, lw
      if below then
        lx, ly, lw = x + w // 2, math.min(474, y + h + 16), math.min(slotW - 16, 380)
      else
        local rightFree, leftFree = 790 - (x + w), x - 10
        if rightFree >= leftFree then lx = x + w + math.min(rightFree, 190) // 2 + 4 else lx = x - math.min(leftFree, 190) // 2 - 4 end
        lx = math.max(75, math.min(725, lx))
        ly = y + h // 2 + 5
        lw = math.max(60, math.min(math.max(rightFree, leftFree), 190) - 10)
      end
      ent[#ent + 1] = table.concat({ cand.a.hex, c, x, y, lx, ly, lw, w, h }, ",")
    else
      if w == nil and tostring(h):find("nicht gefunden", 1, true) then missAdd(cand.name, now) end
      log("Flight Radar: Himmel " .. cand.name .. ": " .. tostring(h))
    end
  end
  if #ent == 0 and partial then return end
  S.sig = sig
  sDirty = true
  ctx.data.set("sk", sig .. "~" .. table.concat(ent, ";"))
  log(string.format("Flight Radar: Himmel komponiert (%d von %d Flugzeugen als Render%s).", #ent, math.min(#ac.list, POOL), generic and ", Gruppenbild ohne Lackierung" or ""))
end

-- Alles, was nur bei angezeigter App und vorhandenen Flugzeugen laeuft (Flug-Bild, Ersatzfoto, Himmel, Logo, Auswertung)
local function extras(ctx, ac, now)
  featureStep(ctx, ac, now)
  if flightImgStep(ctx, ac.list[1], now) == false then photoStep(ctx, ac.list[1]) end
  skyStep(ctx, ac, now)
  logoStep(ctx, ac.list[1], now)
  covStep(ac, now)
end

-- airlines.json alle 30 Minuten vom NAS (still: fehlt die Datei, bleibt der bisherige Stand)
local function airlinesPeriodic(now)
  stLoad()
  if now - S.air < AIR_GAP or not storage.ready() then return end
  S.air = now
  sDirty = true
  local txt, err = storage.read("dir", "airlines.json")
  if txt then applyAirlines(txt) elseif err ~= "nicht gefunden" then log("Flight Radar: airlines.json: " .. tostring(err)) end
end

local function fetchMain(ctx)
  EN = ctx.lang == "en"
  probes, EXM = 0, {}
  if not visible(ctx) then return true end
  local loc = weather.location()
  if not loc then return true end -- kein Standort: die Seiten zeigen den Hinweis
  local radius = radiusOf(ctx.cfg)
  local key = keyOf(loc, radius)
  local now = time.now()
  if now == nil then log("Flight Radar: Uhr nicht synchron"); return false end
  local shown = ctx.view == nil or ctx.view == "app"
  local ac, fail = loadAc()
  if ac then applyFeature(ctx, ac) end
  local have = ac and ac.key == key
  airlinesPeriodic(now)
  if ctx.opened then -- App gerade geoeffnet (fetchOnOpen): Positionen nicht neu abrufen, nur Foto, Himmel, Logo nachladen
    if shown then covStart(now) end
    if shown and have and not (fail and fail.key == key) and #ac.list > 0 then extras(ctx, ac, now) end
    return true
  end
  if fail and fail.key == key then
    if now - fail.at < RETRY then return false end
  elseif have and now >= ac.at and now - ac.at < MIN_GAP then
    if shown and #ac.list > 0 then extras(ctx, ac, now) end
    return true
  end
  local nm = rnd(radius / 1.852)
  if nm < 3 then nm = 3 elseif nm > 250 then nm = 250 end
  local r, err = http.request{ url = string.format(ADSB .. "/v2/point/%.4f/%.4f/%d", loc.lat, loc.lon, nm), keep = KEEP, maxBytes = 65536,
    headers = { Accept = "application/json" } }
  local msg
  if not r then
    log("Flight Radar: " .. tostring(err))
    msg = T("Verbindung fehlgeschlagen", "Connection failed")
  elseif r.status ~= 200 then
    log("Flight Radar: HTTP-Status " .. tostring(r.status))
    msg = T("Quelle nicht erreichbar", "Source unreachable")
  elseif r.body == "" then
    msg = T("Leere Antwort", "Empty response")
  else
    local pool, total = parseAc(r.body, loc, radius)
    r = nil
    if pool == nil then
      log("Flight Radar: Antwort ohne ac-Liste")
      msg = T("Antwort nicht erkannt", "Response not recognized")
    else
      local ok, werr = saveAc(key, now, total, pool)
      if not ok then
        msg = "file: " .. tostring(werr)
      else
        log(string.format("Flight Radar: %d Flugzeug(e) im Umkreis (%d uebernommen).", total, #pool))
        if #pool > 0 then
          local acn = { list = pool, total = total }
          applyFeature(ctx, acn)
          routeStep(ctx, acn.list[1])
          if shown then
            local before = acn.list[1]
            extras(ctx, acn, now)
            if acn.list[1] ~= before then routeStep(ctx, acn.list[1]) end -- Hauptflugzeug gewechselt: Route dafuer
          end
        else
          ctx.data.set("rt", nil)
        end
        return true
      end
    end
  end
  saveFail(key, now, msg)
  return false
end

function on_fetch(ctx)
  local ok = fetchMain(ctx)
  stFlush()
  return ok
end

-- ---------------------------------------------------------------------------
-- Knoepfe der Einstellungen: airlines.json laden/exportieren/zuruecksetzen, Abdeckung schreiben
-- ---------------------------------------------------------------------------

-- App verlassen ("leave") bzw. Tiefschlaf ("sleep"): Auswertung abschliessen (frCovFlush(true) bei !visible && wasVisible bzw. frCoverageSleepFlush)
function on_close(ctx)
  EN = ctx.lang == "en"
  probes = 0
  stLoad()
  local now = time.now() or 0
  if S.cv then
    if S.cv.pend or S.cv.dirty then covFlush(now) end
    S.cv.closed = true
    sDirty = true
  end
  stFlush()
end

function on_action(ctx, name)
  EN = ctx.lang == "en"
  probes = 0
  if name == "coverage" then
    stLoad()
    local now = time.now() or 0
    if not S.cv then return { ok = false, message = T("Noch keine Auswertung: erst die App öffnen und Flugzeuge abwarten.", "No coverage data yet: open the app and wait for aircraft.") } end
    local ok, err = covFlush(now)
    stFlush()
    local msg = covSummary()
    if ok then return { ok = true, message = cut(msg .. " " .. S.cv.fn, 150) } end
    if ok == nil then return { ok = true, message = cut(msg .. " " .. T("Kein NAS eingerichtet.", "No storage set up."), 150) } end
    return { ok = false, message = cut(msg .. " " .. tostring(err), 150) }
  end
  if name == "airlines_import" then -- Datei aus dem Browser/der App (Manifest action.upload = "airin")
    local txt = file.read("airin")
    if not txt then return { ok = false, message = T("Keine Datei empfangen.", "No file received.") } end
    file.write("airin", "")
    stLoad().air = time.now() or 0
    local ok, msg = applyAirlines(txt)
    stFlush()
    return { ok = ok, message = cut(msg, 150) }
  end
  if name == "airlines_diff" then -- Aenderungsliste der letzten Uebernahme fuer den Download (Manifest action.download = "airdiff")
    stLoad()
    if #S.dl == 0 then return { ok = false, message = T("Noch keine airlines.json übernommen.", "No airlines.json applied yet.") } end
    local ok, err = file.write("airdiff", T("Änderungen der letzten airlines.json-Übernahme", "Changes of the last airlines.json import") .. "\n\n" .. table.concat(S.dl, "\n") .. "\n")
    if not ok then return { ok = false, message = tostring(err) } end
    return { ok = true, message = T("Änderungsliste bereit.", "Change list ready.") }
  end
  if name == "coverage_download" then -- Abdeckungs-CSV fuer den Download, auch ohne NAS (Manifest action.download = "covout")
    stLoad()
    if not S.cv then return { ok = false, message = T("Noch keine Auswertung: erst die App öffnen und Flugzeuge abwarten.", "No coverage data yet: open the app and wait for aircraft.") } end
    local ok, err = file.write("covout", covCsv())
    if not ok then return { ok = false, message = T("Auswertung zu gross oder nicht speicherbar: ", "Report too large or not storable: ") .. tostring(err) } end
    return { ok = true, message = cut(covSummary(), 150) }
  end
  if name == "airlines_download" then -- Gesamtstand fuer den Download (Manifest action.download = "airout")
    local ok, err = file.write("airout", exportJson())
    if not ok then return { ok = false, message = T("Export zu gross oder nicht speicherbar: ", "Export too large or not storable: ") .. tostring(err) } end
    return { ok = true, message = T("Gesamtstand bereit.", "Overall state ready.") }
  end
  if name ~= "airlines_run" and name ~= "airlines_reload" then return { ok = false, message = T("Unbekannte Aktion.", "Unknown action.") } end
  -- "Von NAS neu laden" (airlines_reload) ist der Knopf der alten Mac/iOS-Karte; "Ausfuehren" (airlines_run) macht Export/Zuruecksetzen und
  -- laedt bei einem alten, nicht mehr angebotenen Wert "reload" weiterhin neu
  local mode = name == "airlines_reload" and "reload" or ctx.cfg.airMode
  if mode == "export" then
    if not storage.ready() then return { ok = false, message = T("Kein externer Speicher eingerichtet.", "No external storage set up.") } end
    local ok, err = storage.write("dir", "airlines_export.json", exportJson())
    if not ok then return { ok = false, message = tostring(err) } end
    return { ok = true, message = T("airlines_export.json liegt im NAS-Ordner (als airlines.json umbenennen und ergänzen).", "airlines_export.json is in the NAS folder (rename to airlines.json and extend).") }
  elseif mode == "reset" then
    file.write("airl", "")
    stLoad().sig = ""
    S.dl = { "(alle eigenen Eintraege verworfen)" }
    sDirty = true
    stFlush()
    return { ok = true, message = T("Eigene Einträge verworfen, es gilt wieder der eingebaute Stand.", "Own entries discarded, the built-in state applies again.") }
  end
  if not storage.ready() then return { ok = false, message = T("Kein externer Speicher eingerichtet.", "No external storage set up.") } end
  local txt, err = storage.read("dir", "airlines.json")
  if not txt then
    if err == "nicht gefunden" then return { ok = false, message = T("Keine airlines.json im NAS-Ordner gefunden.", "No airlines.json found in the NAS folder.") } end
    return { ok = false, message = tostring(err) }
  end
  stLoad().air = time.now() or 0
  local ok, msg = applyAirlines(txt)
  stFlush()
  return { ok = ok, message = cut(msg, 150) }
end

-- ---------------------------------------------------------------------------
-- Seite 1: Flug
-- ---------------------------------------------------------------------------

local PX, PW, PH = 20, 430, 296 -- Fotokarte (FR_PHOTO_BOX_W/H)

local function infoRow(x, y, maxW, label, value)
  draw.text(x, y, label, "small", color.ACCENT_TEXT)
  draw.text(x, y + 20, fit(value, maxW, "normal"), "normal", color.BLACK)
  return y + 44
end

local function nameOf(a) return a.cs ~= "" and a.cs or (a.reg ~= "" and a.reg or a.hex) end

local function routeOf(ctx, a)
  local rt = ctx.data.get("rt")
  if type(rt) ~= "string" or a.cs == "" then return nil end
  local cs, from, to = rt:match("^([^|]*)|([^|]*)|([^|]*)$")
  if cs == a.cs:gsub("[^%w]", "") and #from >= 3 and #to >= 3 then return from, to end
  return nil
end

-- Pfeil "von -> nach" (die Geraetefonts haben kein Pfeilzeichen)
local function arrowRoute(x, baseY, from, to, font, gap, aw, hh, limitX)
  draw.text(x, baseY, from, font, color.BLACK)
  local ax = x + draw.measure(from, font) + gap
  local ay = baseY - (aw > 30 and 10 or 8)
  if limitX and ax + aw + gap + draw.measure(to, font) > limitX then return end
  draw.rect(ax, ay - 1, aw - (aw > 30 and 8 or 7), 3, color.ACCENT, true)
  draw.triangle(ax + aw - (aw > 30 and 9 or 8), ay - hh, ax + aw - (aw > 30 and 9 or 8), ay + hh, ax + aw, ay, color.ACCENT, true)
  draw.text(ax + aw + gap, baseY, to, font, color.BLACK)
end

local function flightPage(ctx, ac)
  local top = draw.top
  local a = ac.list[1]
  -- Bildkasten links: Renderbild vom NAS (Name "fplane", zur Datei des aktuellen Flugzeugs passend), sonst das planespotters-Foto dieser
  -- Maschine, sonst nur der Rahmen mit Hinweis. Das Airline-Logo sitzt in der Ecke des Kastens (nur wenn es zum Rufzeichen passt).
  local py = top + 10
  local want = skyFile(a) or "-"
  local fi = ctx.data.get("fi")
  local fn, fs = (type(fi) == "string" and fi or ""):match("^([^|]*)|(%d)|")
  local fw, fh = draw.image_size("fplane")
  local ph = ctx.data.get("ph")
  local phHex, phWho, phOk = "", "", "0"
  if type(ph) == "string" then phHex, phWho, phOk = ph:match("^([^|]*)|([^|]*)|(%d)$") end
  local iw, ih = draw.image_size("photo")
  local bx, by = PX, py -- obere linke Ecke des Bildes (fuer die Logo-Marke)
  if fn == want and fs == "1" and fw then
    draw.rect(PX, py, PW, PH, color.BLACK, false, 12)
    draw.image("fplane", PX + (PW - fw) // 2, py + 40 + (FI_H - fh) // 2)
  elseif phOk == "1" and phHex == a.hex and iw and not (fn == want and fs == "1") then
    bx, by = PX + (PW - iw) // 2, py + (PH - ih) // 2
    draw.image("photo", bx, by)
    draw.rect(bx - 1, by - 1, iw + 2, ih + 2, color.BLACK, false)
    draw.text(PX, py + PH + 18, fit(string.format("%s: %s · planespotters.net", T("Foto", "Photo"), phWho), PW, "small"), "small", color.BLACK)
  else
    draw.rect(PX, py, PW, PH, color.BLACK, false, 12)
    local loading = fn ~= want or fs == "1" or (phHex ~= a.hex or phOk == "1")
    draw.text(PX + PW // 2, py + PH // 2 + 6, loading and T("Bild wird geladen ...", "Loading image ...") or T("Kein Bild verfügbar", "No image available"),
      "small", color.BLACK, "center")
  end
  local lg = ctx.data.get("lg")
  if type(lg) == "string" and lg == (icaoOf(a.cs) or "") .. "|1" then
    local lx, ly = bx + 12, by + 12
    if draw.image("logo", lx, ly) then draw.rect(lx - 1, ly - 1, 87, 22, color.BLACK, false) end
  end
  -- Daten rechts
  local rx = 472
  local maxW = draw.width - rx - 20
  local y = top + 38 -- ohne Logo-Kaestchen daneben: Rufzeichen ueber die ganze Spaltenbreite, Airline in der Normalschrift
  draw.text(rx, y, fit(nameOf(a), maxW, "large"), "large", color.BLACK)
  y = y + 8
  if a.air ~= "" then
    draw.text(rx, y + 16, fit(a.air, maxW, "normal"), "normal", color.BLACK)
    y = y + 22
  end
  y = y + 14
  local from, to = routeOf(ctx, a)
  if from then
    arrowRoute(rx, y + 22, from, to, "large", 10, 34, 6)
    y = y + 46
  else
    y = y + 4
  end
  y = infoRow(rx, y + 12, maxW, T("MASCHINE", "AIRCRAFT"), a.desc ~= "" and a.desc or (a.tc ~= "" and a.tc or "-"))
  local reg = a.reg ~= "" and (a.reg .. " · " .. (a.tc ~= "" and a.tc or a.hex)) or a.hex
  y = infoRow(rx, y, maxW, T("KENNUNG", "REGISTRATION"), reg)
  local alt
  if a.gnd then alt = T("am Boden", "on ground")
  elseif a.alt >= 0 then
    alt = rnd(a.alt * 0.3048) .. " m"
    if a.gs >= 0 then alt = alt .. " · " .. rnd(a.gs * 1.852) .. " km/h" end
  else alt = "-" end
  y = infoRow(rx, y, maxW, T("HÖHE · TEMPO", "ALTITUDE · SPEED"), alt)
  local dist = a.dist < 10 and string.format("%.1f km", a.dist) or (rnd(a.dist) .. " km")
  infoRow(rx, y, maxW, T("ENTFERNUNG", "DISTANCE"), string.format(T("%s · aus %s", "%s · from %s"), dist, compass(a.brg)))
  if ac.total > 1 then
    draw.text(rx, draw.height - 18, fit(string.format(T("+%d weitere im Umkreis von %d km", "+%d more within %d km"), ac.total - 1, ac.radius), maxW, "small"), "small", color.BLACK)
  end
end

-- ---------------------------------------------------------------------------
-- Seite 2: Himmel (Vollbild, draw.top = 0): nur Renderbilder vom NAS, Label an der beim Komponieren gemerkten Stelle
-- ---------------------------------------------------------------------------

local function skyPage(ctx, st, ac, radius)
  local W, H = draw.width, draw.height
  local id = skyOf(ctx.cfg)
  local dark = id == "blue" or id == "black"
  local fg = dark and color.WHITE or color.BLACK
  if id ~= "white" then draw.rect(0, 0, W, H, SKY[id], true) end
  if st ~= "ok" then
    local line
    if st == "noloc" then line = T("Kein Standort hinterlegt.", "No location set.")
    elseif st == "loading" then line = T("Wird geladen ...", "Loading ...")
    elseif st == "error" then line = T("Abruf fehlgeschlagen.", "Fetch failed.")
    else line = string.format(T("Gerade kein Flugzeug im Umkreis von %d km.", "No aircraft within %d km right now."), radius) end
    draw.text(W // 2, H // 2 - 8, line, "normal", fg, "center")
    return
  end
  local _, ent = skyParse(ctx.data.get("sk"))
  for _, e in ipairs(ent) do
    local a
    for _, x in ipairs(ac.list) do
      if x.hex == e.hex then a = x; break end
    end
    if a and draw.image("sky" .. e.idx, e.x, e.y) then
      local lab = a.dist < 10 and string.format("%s · %.1f km", nameOf(a), a.dist) or string.format("%s · %d km", nameOf(a), rnd(a.dist))
      local typ = a.desc ~= "" and a.desc or a.tc
      local line2 = ""
      if a.air ~= "" and typ ~= "" then line2 = a.air .. " · " .. typ elseif a.air ~= "" then line2 = a.air elseif typ ~= "" then line2 = typ end
      local ly = math.min(e.ly, H - 6)
      if line2 ~= "" then
        draw.text(e.lx, math.max(8, ly - 7), lab, "small", fg, "center")
        draw.text(e.lx, math.min(H - 2, ly + 7), fit(line2, e.lw > 0 and e.lw or 150, "small"), "small", fg, "center")
      else
        draw.text(e.lx, ly, lab, "small", fg, "center")
      end
    end
  end
  if #ent == 0 then
    local a1 = ac.list[1]
    local want = skyFile(a1) or (a1.grp ~= "" and a1.grp .. ".png") or nil
    draw.text(W // 2, H // 2 - 8, T("Noch kein passendes Flugzeugbild auf dem NAS.", "No matching aircraft image on the NAS yet."), "normal", fg, "center")
    if want then draw.text(W // 2, H // 2 + 16, "z. B. " .. want, "small", fg, "center") end
  end
  local foot
  if ac.total == 1 then foot = string.format(T("1 Flugzeug im Umkreis von %d km", "1 aircraft within %d km"), radius)
  else foot = string.format(T("%d Flugzeuge im Umkreis von %d km", "%d aircraft within %d km"), ac.total, radius) end
  draw.text(14, H - 10, foot, "small", fg)
end

-- ---------------------------------------------------------------------------
-- Einstieg Seiten
-- ---------------------------------------------------------------------------

-- Zustand wie drawFlightRadarEmptyStateIfNeeded(): kein Standort -> noch nicht geladen -> Fehler -> leer -> ok
local function state(ctx)
  local loc = weather.location()
  if not loc then return "noloc", nil, 0 end
  local radius = radiusOf(ctx.cfg)
  local key = keyOf(loc, radius)
  local ac, fail = loadAc()
  if ac then applyFeature(ctx, ac) end
  if fail and fail.key == key then return "error", { msg = fail.msg }, radius end
  if not ac or ac.key ~= key then return "loading", nil, radius end
  ac.radius = radius
  if #ac.list == 0 then return "empty", ac, radius end
  return "ok", ac, radius
end

function on_draw(ctx, page)
  EN = ctx.lang == "en"
  SHP = nil
  draw.clear(color.WHITE)
  local st, ac, radius = state(ctx)
  if page == 2 then
    skyPage(ctx, st, ac, radius)
    return
  end
  if st == "noloc" then
    notice("gear", T("Kein Standort hinterlegt.", "No location set."), T("Studio -> Einstellungen -> Adresse", "Studio -> Settings -> Address"))
  elseif st == "loading" then
    notice("clock", T("Wird geladen ...", "Loading ..."))
  elseif st == "error" then
    notice("warning", T("Abruf fehlgeschlagen.", "Fetch failed."), ac.msg ~= "" and ac.msg or T("Nächster Versuch in Kürze.", "Retrying shortly."))
  elseif st == "empty" then
    notice("info", string.format(T("Gerade kein Flugzeug im Umkreis von %d km.", "No aircraft within %d km right now."), radius))
  else
    flightPage(ctx, ac)
  end
end

-- ---------------------------------------------------------------------------
-- Widget "Naechster Flug" (dwDrawFlightradarNext): Kopf "FLUG · DLH123", gross die Route bzw. der Typ; ab 92 Pixeln Typ + Hoehe,
-- ab 140 Pixeln Entfernung/Richtung/Tempo; Option "Airline & Registrierung" als weitere Zeile. Leerer Himmel: "Freier Himmel".
-- Die Schriftstufe hat hier wie in der eingebauten App keine Wirkung. Wie dort zeigt das Widget kein Foto.
-- ---------------------------------------------------------------------------

local function sampleAc()
  return { total = 3, radius = 25, list = { { hex = "3c6444", cs = "DLH123", reg = "D-AIZZ", tc = "A20N", desc = "AIRBUS A-320neo",
    air = "Lufthansa", lat = 53.6, lon = 10.0, gnd = false, alt = 11000, gs = 430, trk = 70, dist = 7.4, brg = 225, grp = "a320neo", lv = true,
    ia = "lh", tl = "Y" } } }
end

function on_widget(ctx, box)
  EN = ctx.lang == "en"
  local st, ac, radius = state(ctx)
  local sample = false
  if st ~= "ok" and st ~= "empty" and ctx.sample then st, ac, radius, sample = "ok", sampleAc(), 25, true end
  local textX, textW, top = box.x + 12, math.max(20, box.w - 24), box.y
  if st ~= "ok" and st ~= "empty" then
    draw.text(box.x + 12, top + 16, fit(T("Noch keine Daten", "No data yet"), box.w - 20, "small"), "small", color.BLACK)
    return
  end
  local maxY = box.y + box.h - 4
  if st == "empty" then -- leerer Himmel: Kopfzeile und gruener Status
    draw.text(textX, top + 12, T("FLUGRADAR", "FLIGHT RADAR"), "small", color.ACCENT_TEXT)
    draw.text(textX, top + 44, fit(T("Freier Himmel", "Clear skies"), textW, "large"), "large", color.GREEN)
    if top + 44 + 16 <= maxY then
      draw.text(textX, top + 60, fit(string.format(T("im Umkreis von %d km", "within %d km"), radius), textW, "small"), "small", color.BLACK)
    end
    return
  end
  local a = ac.list[1]
  local fh = box.fh or box.h
  draw.text(textX, top + 12, fit(T("FLUG", "FLIGHT") .. " · " .. nameOf(a), textW, "small"), "small", color.ACCENT_TEXT)
  local from, to
  if sample then from, to = "HAM", "PMI" else from, to = routeOf(ctx, a) end
  local statusY = top + 44
  if from then
    arrowRoute(textX, statusY, from, to, "large", 8, 26, 5, box.x + box.w - 12)
  else
    draw.text(textX, statusY, fit(a.desc ~= "" and a.desc or (a.tc ~= "" and a.tc or "-"), textW, "large"), "large", color.BLACK)
  end
  local y = statusY + 19 + 2
  if fh >= 92 and y <= maxY then
    local altPart
    if a.gnd then altPart = T("am Boden", "on ground") elseif a.alt >= 0 then altPart = rnd(a.alt * 0.3048) .. " m" else altPart = "-" end
    local detail = altPart
    if from then detail = (a.desc ~= "" and a.desc or (a.tc ~= "" and a.tc or "-")) .. " · " .. altPart end
    draw.text(textX, y, fit(detail, textW, "small"), "small", color.BLACK)
    y = y + 19
  end
  if fh >= 140 and y <= maxY then
    local dist = a.dist < 10 and string.format("%.1f km", a.dist) or (rnd(a.dist) .. " km")
    local line
    if a.gs >= 0 then line = string.format(T("%s · aus %s · %d km/h", "%s · from %s · %d km/h"), dist, compass(a.brg), rnd(a.gs * 1.852))
    else line = string.format(T("%s · aus %s", "%s · from %s"), dist, compass(a.brg)) end
    draw.text(textX, y, fit(line, textW, "small"), "small", color.BLACK)
    y = y + 19
    if ctx.cfg.wAirline == true and y <= maxY and (a.air ~= "" or a.reg ~= "") then
      local op = a.air ~= "" and a.reg ~= "" and (a.air .. " · " .. a.reg) or (a.air ~= "" and a.air or a.reg)
      draw.text(textX, y, fit(op, textW, "small"), "small", color.BLACK)
    end
  end
end
