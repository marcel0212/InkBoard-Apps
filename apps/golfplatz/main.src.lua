-- Golfplatz (Paket golfplatz, Skript-Variante der eingebauten App "golf"): Platzbelegung eines Golfclubs vom oeffentlichen
-- PC-CADDIE-Belegungsplan https://www.pccaddie.net/clubs/<Clubnummer>/app.php?cat=occupancy (serverseitig gerendertes
-- HTML ohne Login, ~50 KB, 14 Tage Vorschau; das JSON-Format liefert ohne Sitzung 403). Seiten Heute / Woche / 14 Tage,
-- je drei Stile (Bento/Slate/Nano) wie die eingebaute App, Dashboard-Widget "Platzbelegung heute" (Status gross).
-- Skript-API Level 14 (http.get mit maxBytes, file.*, ctx.view/ctx.widgets).
--
-- Auswertung wie der Streaming-Parser der eingebauten App (teil02 golfHandleTag): ab der Tabelle class="... pcco-occupancy"
-- werden die Tags der Reihe nach gelesen; stabile CSS-Klassen markieren alles Noetige:
--   tr.pcco-occupancy-content            -> neue Tageszeile
--   td.pcco-occupancy-date               -> "Do." + "20.08.2026"
--   td.pcco-occupancy-info data-title=.. -> Bereich (Tee 1 / Greenkeeping / Kurse & Events / Information)
--   div.pcco-occupancy-entry-resource    -> Turnier/Event (verlinkt), div.pcco-occupancy-entry-manual -> manueller Eintrag
--   div.pcco-occupancy-time/-event/-text -> Zeit / Titel / Hinweis
-- Hoechstens 14 Tage und 48 Eintraege, Titel 63 / Hinweis 47 Bytes (wie GOLF_EVENT_LEN/GOLF_NOTE_LEN).
--
-- Rueckficht auf den Betreiber (pccaddie.net ist eine geteilte Club-Plattform ohne API-Angebot): erfolgreiche Abrufe
-- hoechstens alle 60 Minuten (auch wenn ein kuerzerer Takt eingestellt ist), nach einem Fehler fruehestens nach 10 Minuten
-- erneut (GOLF_RETRY_MS der eingebauten App). Abgerufen wird nur, wenn die App angezeigt wird oder ein Widget von ihr auf
-- dem aktiven Dashboard liegt (ctx.view/ctx.widgets).
--
-- Dateien: "plan" = letzter erfolgreicher Stand, Tab-getrennte Zeilen
--   H Club, Abrufzeit (Unix)        D Jahr, Monat, Tag        E Bereich (1-4), von, bis (Minuten, -1 = keine Angabe), Turnier(1/0), Titel, Hinweis
-- "err" = letzter Fehlversuch: Zeit, Club, Text (leer nach Erfolg). Bewusst Dateien statt ctx.data: on_fetch gibt nach einem
-- Fehler false zurueck (die Firmware versucht es dann nach ~5 Minuten erneut), ctx.data wuerde dabei nicht gespeichert.

local EN = false
local function T(de, en) if EN then return en end return de end

local URL = "https://www.pccaddie.net/clubs/%s/app.php?cat=occupancy"
local DEFAULT_CLUB = "0492201" -- GC Hamburg-Ahrensburg e.V.
local MAX_BYTES = 65536
local MIN_GAP = 60 * 60     -- Untergrenze zwischen zwei erfolgreichen Abrufen
local RETRY = 10 * 60       -- Wartezeit nach einem Fehlversuch
local MAX_DAYS, MAX_ENTRIES = 14, 48
local EVENT_LEN, NOTE_LEN = 63, 47

--#include text
--#include ui
--#include dates

-- ---------------------------------------------------------------------------
-- Hilfen
-- ---------------------------------------------------------------------------

-- Clubnummer aus der Einstellung (nur Buchstaben/Ziffern, damit nichts Fremdes in die Adresse gelangt)
local function clubOf(cfg)
  local c = cfg.club
  if c == nil then c = DEFAULT_CLUB end -- Feld fehlt (Manifest-Standard nicht gesetzt): Werks-Default wie die eingebaute App
  c = tostring(c):gsub("[^%w]", "")
  return c:sub(1, 16)
end

-- UTF-8-sicher auf hoechstens n Bytes kuerzen
local function cutBytes(s, n)
  if #s <= n then return s end
  s = s:sub(1, n)
  local i = #s
  while i > 0 and (s:byte(i) & 0xC0) == 0x80 do i = i - 1 end
  if i > 0 then
    local b, need = s:byte(i), 1
    if b >= 0xF0 then need = 4 elseif b >= 0xE0 then need = 3 elseif b >= 0xC0 then need = 2 end
    if #s - i + 1 < need then s = s:sub(1, i - 1) end
  end
  return s
end

local ENT = {
  auml = "\195\164", ouml = "\195\182", uuml = "\195\188", Auml = "\195\132", Ouml = "\195\150", Uuml = "\195\156",
  szlig = "\195\159", amp = "&", nbsp = " ", ndash = "-", mdash = "-", quot = '"', apos = "'", eacute = "\195\169",
  egrave = "\195\168", lt = "<", gt = ">",
}
-- Zeichen-Code -> darstellbarer Text (Latin-1/Latin Extended als UTF-8, typografische Zeichen als ASCII, Rest entfaellt)
local function cpText(cp)
  if cp == 8211 or cp == 8212 or (cp >= 8208 and cp <= 8213) then return "-" end
  if cp >= 8216 and cp <= 8218 then return "'" end
  if cp >= 8220 and cp <= 8222 then return '"' end
  if cp == 8230 then return "..." end
  if cp == 160 then return " " end
  if cp < 32 then return " " end
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then return string.char(0xC0 | (cp >> 6), 0x80 | (cp & 0x3F)) end
  return ""
end

-- Entities aufloesen, 3-/4-Byte-UTF-8 entschaerfen (das Display kennt nur 1-/2-Byte-Zeichen), Leerraum zusammenfassen
local function cleanText(s)
  s = s:gsub("&(#?[xX]?%w+);", function(e)
    local r = ENT[e]
    if r then return r end
    local n = e:match("^#(%d+)$")
    if n then return cpText(tonumber(n)) end
    n = e:match("^#[xX](%x+)$")
    if n then return cpText(tonumber(n, 16)) end
    return nil
  end)
  s = s:gsub("[\224-\239][\128-\191][\128-\191]", function(c)
    local a, b, d = c:byte(1, 3)
    return cpText(((a & 0x0F) << 12) | ((b & 0x3F) << 6) | (d & 0x3F))
  end)
  s = s:gsub("[\240-\247][\128-\191][\128-\191][\128-\191]", "")
  s = s:gsub("%s+", " ")
  return (s:gsub("^ ", ""):gsub(" $", ""))
end

-- "06:00 - 09:00 Uhr:" / "10:00 Uhr" / "9:00" -> Minuten seit Mitternacht (bis zu zwei Angaben), sonst -1
local function parseTimes(s)
  local out, i = {}, 1
  while #out < 2 do
    local a, b, h, m = s:find("(%d%d?):(%d%d)", i)
    if not a then break end
    h, m = tonumber(h), tonumber(m)
    if h <= 23 and m <= 59 then out[#out + 1] = h * 60 + m end
    i = b + 1
  end
  local from, to = out[1] or -1, out[2] or -1
  -- PC-CADDIE-Konvention: ganztaegige Kalender-Eintraege tragen "00:01 Uhr" als Pseudo-Startzeit -> "ganztaegig"
  if from >= 0 and from <= 1 and to < 0 then from = -1 end
  return from, to
end

local function colOfTitle(tag)
  if tag:find("Tee 1", 1, true) then return 1 end
  if tag:find("Greenkeeping", 1, true) then return 2 end
  if tag:find("Kurse", 1, true) then return 3 end
  if tag:find("Information", 1, true) then return 4 end
  return nil
end

-- ---------------------------------------------------------------------------
-- Belegungstabelle auswerten (Zustandsmaschine wie golfHandleTag() der eingebauten App)
-- ---------------------------------------------------------------------------

local function parsePlan(body)
  local p = body:find('pcco-occupancy"', 1, true)
  if not p then return nil end
  p = body:find(">", p, true)
  if not p then return nil end
  local days, nEnt = {}, 0
  local cap, buf, col = nil, {}, nil
  local pend = { active = false, res = false, from = -1, to = -1, ev = nil, note = "" }
  local function pendReset() pend.ev, pend.note, pend.from, pend.to = nil, "", -1, -1 end
  local function flush()
    local d = days[#days]
    if pend.active and pend.ev and col and d and nEnt < MAX_ENTRIES then
      local prev = d.es[#d.es]
      if not (prev and prev.col == col and prev.from == pend.from and prev.to == pend.to and prev.ev == pend.ev) then
        d.es[#d.es + 1] = { col = col, from = pend.from, to = pend.to, res = pend.res, ev = pend.ev, note = pend.note }
        nEnt = nEnt + 1
      end
    end
    pendReset()
  end
  local function capEnd()
    local txt = cleanText(table.concat(buf))
    buf = {}
    if cap == "date" then
      local dd, mm, yy = txt:match("(%d%d?)%.(%d%d?)%.(%d%d%d%d)")
      dd, mm, yy = tonumber(dd), tonumber(mm), tonumber(yy)
      if dd and #days < MAX_DAYS and dd >= 1 and dd <= 31 and mm >= 1 and mm <= 12 and yy >= 2000 and yy <= 2100 then
        days[#days + 1] = { y = yy, m = mm, d = dd, es = {} }
      end
    elseif cap == "time" then
      pend.from, pend.to = parseTimes(txt)
    elseif cap == "event" then
      if txt ~= "" then pend.ev = cutBytes(txt, EVENT_LEN) end
    elseif cap == "note" then
      pend.note = cutBytes(txt, NOTE_LEN)
    end
    cap = nil
  end
  local function has(tag, s) return tag:find(s, 1, true) ~= nil end
  local pos, n, bufLen = p + 1, #body, 0
  while pos <= n do
    local lt = body:find("<", pos, true)
    if not lt then break end
    if cap and lt > pos and bufLen < 192 then
      buf[#buf + 1] = body:sub(pos, lt - 1)
      bufLen = bufLen + lt - pos
    end
    local gt = body:find(">", lt + 1, true)
    if not gt then break end
    pos = gt + 1
    if cap then
      -- im Erfassungsbereich beendet nur </td> (Datum) bzw. </div> die Sammlung, jedes andere Tag wird zu einem Leerzeichen
      if body:find(cap == "date" and "^/td" or "^/div", lt + 1) then
        capEnd()
        bufLen = 0
      else
        buf[#buf + 1] = " "
      end
    elseif body:find("^/table", lt + 1) then
      flush()
      break
    elseif body:find("^t[dr]", lt + 1) or body:find("^div", lt + 1) then -- nur <tr>/<td>/<div> tragen die Klassen; <span>, <a>, <br> ... ohne Teilzeichenkette
      local tag = body:sub(lt + 1, math.min(gt - 1, lt + 159)) -- wie GOLF_TAG_BUF: die Klassen stehen am Tag-Anfang
      if not has(tag, "pcco-occupancy-") then
        -- uninteressant
      elseif has(tag, "pcco-occupancy-content") then
        flush(); col = nil
      elseif has(tag, "pcco-occupancy-date") then
        cap, buf, bufLen = "date", {}, 0
      elseif has(tag, "pcco-occupancy-info") then
        flush(); col = colOfTitle(tag)
      elseif has(tag, "pcco-occupancy-entry-resource") then
        flush(); pend.active, pend.res = true, true
      elseif has(tag, "pcco-occupancy-entry-manual") then
        flush(); pend.active, pend.res = true, false
      elseif has(tag, "pcco-occupancy-time") or has(tag, "pcco-occupancy-event") then
        -- neue Zeit-/Titelangabe, obwohl der Eintrag schon einen Titel hat = naechster Block im selben Container
        if pend.ev then flush() end
        cap, buf, bufLen = has(tag, "pcco-occupancy-time") and "time" or "event", {}, 0
      elseif has(tag, "pcco-occupancy-text") then
        cap, buf, bufLen = "note", {}, 0
      end
    end
  end
  if cap then capEnd() end
  flush()
  return days
end

-- ---------------------------------------------------------------------------
-- Speichern / Laden
-- ---------------------------------------------------------------------------

local function savePlan(club, at, days)
  local out = { "H\t" .. club .. "\t" .. at }
  for _, d in ipairs(days) do
    out[#out + 1] = "D\t" .. d.y .. "\t" .. d.m .. "\t" .. d.d
    for _, e in ipairs(d.es) do
      out[#out + 1] = table.concat({ "E", e.col, e.from, e.to, e.res and 1 or 0, e.ev, e.note }, "\t")
    end
  end
  return file.write("plan", table.concat(out, "\n"))
end

local function loadPlan()
  local txt = file.read("plan")
  if not txt then return nil end
  local m = { days = {} }
  for line in txt:gmatch("[^\n]+") do
    local f = {}
    for v in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = v end
    if f[1] == "H" then
      m.club, m.at = f[2], tonumber(f[3]) or 0
    elseif f[1] == "D" then
      local y, mo, d = tonumber(f[2]) or 2000, tonumber(f[3]) or 1, tonumber(f[4]) or 1
      m.days[#m.days + 1] = { y = y, m = mo, d = d, z = dfc(y, mo, d), es = {} }
    elseif f[1] == "E" and #m.days > 0 then
      local es = m.days[#m.days].es
      es[#es + 1] = { col = tonumber(f[2]) or 4, from = tonumber(f[3]) or -1, to = tonumber(f[4]) or -1, res = f[5] == "1", ev = f[6] or "", note = f[7] or "" }
    end
  end
  if m.club == nil then return nil end
  return m
end

-- letzter Fehlversuch: at, club, Text (nil, wenn keiner vermerkt ist)
local function loadErr()
  local txt = file.read("err")
  if not txt or txt == "" then return nil end
  local at, club, msg = txt:match("^(%d+)\t([^\t]*)\t(.*)$")
  if not at then return nil end
  return { at = tonumber(at), club = club, msg = msg }
end

-- ---------------------------------------------------------------------------
-- Abruf
-- ---------------------------------------------------------------------------

local function visible(ctx)
  if ctx.view == nil or ctx.view == "app" then return true end -- ohne ctx.view (aeltere Firmware): wie frueher
  return ctx.view == "dashboard" and #(ctx.widgets or {}) > 0
end

function on_fetch(ctx)
  EN = ctx.lang == "en"
  if not visible(ctx) then return true end
  local club = clubOf(ctx.cfg)
  if #club < 4 then return true end -- nicht eingerichtet: die Seiten zeigen den Hinweis
  local now = time.now()
  if now == nil then log("Golfplatz: Uhr nicht synchron"); return false end
  local plan = loadPlan()
  local fail = loadErr()
  if fail and fail.club == club then
    if now - fail.at < RETRY then return false end -- Fehlversuch liegt keine 10 Minuten zurueck: spaeter erneut
  elseif plan and plan.club == club and now - plan.at < MIN_GAP and now >= plan.at then
    return true -- Stand juenger als 60 Minuten: kein neuer Abruf
  end
  local body, err = http.get(string.format(URL, club), MAX_BYTES)
  local msg
  if not body then
    err = tostring(err)
    log("Golfplatz: " .. err)
    if err:find("404", 1, true) then msg = T("Clubnummer unbekannt (404)", "Club number unknown (404)")
    elseif err:find("HTTP", 1, true) then msg = T("Quelle nicht erreichbar", "Source unreachable") .. " (" .. err .. ")"
    else msg = T("Verbindung fehlgeschlagen", "Connection failed") end
  else
    local days = parsePlan(body)
    body = nil
    if days == nil or #days == 0 then
      log("Golfplatz: Belegungstabelle nicht im Dokument gefunden.")
      msg = T("Antwort nicht erkannt", "Response not recognized")
    else
      local ok, werr = savePlan(club, now, days)
      if not ok then
        msg = "file: " .. tostring(werr)
      else
        local ne = 0
        for _, d in ipairs(days) do ne = ne + #d.es end
        log(string.format("Golfplatz: %d Tage / %d Belegungen geladen.", #days, ne))
        if fail then file.write("err", "") end
        return true
      end
    end
  end
  file.write("err", now .. "\t" .. club .. "\t" .. clean(msg, 100))
  return false
end

-- ---------------------------------------------------------------------------
-- Modell fuer das Zeichnen
-- ---------------------------------------------------------------------------

local WD_DE = { "So", "Mo", "Di", "Mi", "Do", "Fr", "Sa" }
local WD_EN = { "Su", "Mo", "Tu", "We", "Th", "Fr", "Sa" }

local function wdOf(d) return (EN and WD_EN or WD_DE)[(d.z + 4) % 7 + 1] end
-- "Do 21.08."
local function dayShort(d) return string.format("%s %02d.%02d.", wdOf(d), d.d, d.m) end

local function hm(v) return string.format("%02d:%02d", v // 60, v % 60) end
-- "06:00-09:00" / "06:00" / "ganztaegig"
local function timeRange(e)
  if e.from < 0 then return T("ganztägig", "all day") end
  if e.to < 0 then return hm(e.from) end
  return hm(e.from) .. "-" .. hm(e.to)
end
local function startOrAllDay(e)
  if e.from >= 0 then return hm(e.from) end
  return T("ganzt.", "all d.")
end

-- Bereichsfarben fest ueber alle Seiten/Stile/Widget: Tee 1 blau, Greenkeeping gruen, Kurse & Events rot, Information gelb
local function colColor(c)
  if c == 1 then return color.BLUE elseif c == 2 then return color.GREEN elseif c == 3 then return color.RED end
  return color.YELLOW
end
local function colLabel(c)
  if c == 1 then return "Tee 1" elseif c == 2 then return "Greenkeeping" elseif c == 3 then return T("Kurse & Events", "Courses & Events") end
  return "Information"
end
local SHORT = { "T1", "GK", "KE", "IN" }
-- Schrift auf der Bereichsfarbe: auf Gelb schwarz, sonst weiss; als Textfarbe auf Weiss ist Gelb unlesbar -> schwarz
local function inkOn(c) return c == 4 and color.BLACK or color.WHITE end
local function textCol(c) return c == 4 and color.BLACK or colColor(c) end

-- farbiger Punkt / Quadrat; Gelb bekommt einen schwarzen Rand
local function dot(cx, cy, r, c)
  draw.circle(cx, cy, r, colColor(c), true)
  if c == 4 then draw.circle(cx, cy, r, color.BLACK, false) end
end
local function square(x, y, s, c)
  draw.rect(x, y, s, s, colColor(c), true)
  if c == 4 then draw.rect(x, y, s, s, color.BLACK, false) end
end

-- Kuerzel-Chip (T1/GK/KE/IN) wie golfDrawColChip()
local function chip(x, y, c)
  draw.rect(x, y, 26, 15, colColor(c), true, 4)
  draw.text(x + 13, y + 11, SHORT[c], "small", inkOn(c), "center")
end

-- gestrichelter Rahmen (4 Pixel Strich, 4 Pixel Luecke)
local function dashed(x, y, w, h)
  for i = 0, w - 1, 8 do
    draw.line(x + i, y, x + math.min(i + 3, w - 1), y, color.BLACK)
    draw.line(x + i, y + h - 1, x + math.min(i + 3, w - 1), y + h - 1, color.BLACK)
  end
  for i = 0, h - 1, 8 do
    draw.line(x, y + i, x, y + math.min(i + 3, h - 1), color.BLACK)
    draw.line(x + w - 1, y + i, x + w - 1, y + math.min(i + 3, h - 1), color.BLACK)
  end
end

-- Fahnen-Glyph (Mast + Wimpel + Fuss) wie golfDrawFlagGlyph(); size = Gesamthoehe inkl. Mast
local function flag(x, y, size, c)
  local poleX = x + size // 4
  draw.rect(poleX, y, 2, size, c, true)
  local flagW = size - size // 4 - 1
  draw.triangle(poleX + 2, y, poleX + 2, y + size // 2, poleX + 2 + flagW, y + size // 4, c, true)
  draw.line(x, y + size, x + size - 1, y + size, c)
end

local function centerBounded(s, x, y, font, minX, maxX)
  s = fit(s, maxX - minX, font)
  local w = draw.measure(s, font)
  local left = x - w // 2
  if left + w > maxX then left = maxX - w end
  if left < minX then left = minX end
  draw.text(left, y, s, font, color.BLACK, "left")
end

local function nowLocal()
  local t = time.localtime()
  if t == nil then return nil end
  return t, dfc(t.year, t.month, t.day), t.hour * 60 + t.min
end

-- Index des heutigen Tages (Fallback 1: die Tabelle beginnt beim Abruftag)
local function todayIndex(m)
  local _, z = nowLocal()
  if z then
    for i, d in ipairs(m.days) do if d.z == z then return i, true end end
  end
  return 1, false
end

-- ISO-Kalenderwoche eines Tages (Tage seit 1970)
local function isoWeek(z)
  local wd = (z + 3) % 7          -- 0 = Montag
  local thu = z - wd + 3
  local y = cfd(thu)
  return (thu - dfc(y, 1, 1)) // 7 + 1
end

-- Status jetzt/naechste windowMin Minuten (golfComputeNowStatus): Information blockiert nichts
local function nowStatus(d, nowMin, windowMin)
  local st = { busyNow = false, unknownEnd = false, untilMin = -1, freeWindow = true, nextBusy = -1 }
  for _, e in ipairs(d.es) do
    if e.col ~= 4 then
      local ongoing = e.from < 0 or (e.from <= nowMin and (e.to < 0 or e.to > nowMin))
      if ongoing then
        st.busyNow = true
        if e.to < 0 then st.unknownEnd = true elseif e.to > st.untilMin then st.untilMin = e.to end
      elseif e.from > nowMin then
        if e.from < nowMin + windowMin then st.freeWindow = false end
        if st.nextBusy < 0 or e.from < st.nextBusy then st.nextBusy = e.from end
      end
    end
  end
  if st.busyNow then st.freeWindow = false end
  return st
end

-- ---------------------------------------------------------------------------
-- Seite HEUTE
-- ---------------------------------------------------------------------------

-- Bento ("Fokuskarte"): erste Belegung mit Uhrzeit gross in Bereichsfarbe, darunter naechster Eintrag + FREI-Feld
local function todayBento(m, di, top)
  local margin, contentW = 24, draw.width - 48
  local d = m.days[di]
  draw.text(margin, top + 20, T("HEUTE · ", "TODAY · ") .. dayShort(d), "normal", color.BLACK)
  local y = top + 34
  if #d.es == 0 then
    local cardH = 200
    dashed(margin, y, contentW, cardH + 1)
    draw.text(draw.width // 2, y + cardH // 2 + 4, T("Platz frei", "Course free"), "large", color.GREEN, "center")
    draw.text(draw.width // 2, y + cardH // 2 + 34, T("Heute keine Belegung auf dem Platz", "No bookings on the course today"), "normal", color.BLACK, "center")
    return
  end
  local hi = 1
  for i, e in ipairs(d.es) do if e.from >= 0 then hi = i; break end end
  local hero = d.es[hi]
  local hc = colColor(hero.col)
  local cardH = 168
  draw.rect(margin, y, contentW, cardH, hc, false, 16)
  draw.rect(margin + 1, y + 1, contentW - 2, cardH - 2, hc, false, 15)
  local lab = colLabel(hero.col)
  local chipW = draw.measure(lab, "small") + 18
  draw.rect(margin + 16, y + 12, chipW, 20, hc, true, 10)
  draw.text(margin + 16 + chipW // 2, y + 26, lab, "small", inkOn(hero.col), "center")
  draw.text(margin + 18, y + 74, timeRange(hero), "large", color.BLACK)
  local ty = y + 100
  for _, l in ipairs(wrapLines(hero.ev, contentW - 40, "normal", 2)) do
    draw.text(margin + 18, ty, l, "normal", color.BLACK)
    ty = ty + 22
  end
  if hero.note ~= "" then
    draw.text(margin + 18, y + cardH - 14, fit("> " .. hero.note, contentW - 40, "small"), "small", color.BLACK)
  end

  local rowY = y + cardH + 14
  local rowH = math.max(60, draw.height - 16 - rowY)
  local boxW = (contentW - 14) // 2
  draw.rect(margin, rowY, boxW, rowH, color.BLACK, false, 12)
  if #d.es > 1 then
    local e2 = d.es[hi == 1 and 2 or 1]
    dot(margin + 20, rowY + 22, 6, e2.col)
    draw.text(margin + 34, rowY + 28, timeRange(e2), "normal", color.BLACK)
    draw.text(margin + 14, rowY + 50, fit(e2.ev, boxW - 28, "small"), "small", color.BLACK)
    if #d.es > 2 then
      draw.text(margin + boxW - 12, rowY + rowH - 10, string.format(T("+%d weitere", "+%d more"), #d.es - 2), "small", color.BLACK, "right")
    end
  else
    centerBounded(T("keine weiteren Belegungen", "no further bookings"), margin + boxW // 2, rowY + rowH // 2 + 4, "small", margin + 6, margin + boxW - 6)
  end
  local fx = margin + boxW + 14
  dashed(fx, rowY, boxW, rowH)
  draw.text(fx + boxW // 2, rowY + rowH // 2 + 2, T("FREI", "FREE"), "large", color.GREEN, "center")
  local sub = T("außerhalb der Belegung", "outside the booking")
  if hero.to >= 0 then sub = string.format(T("ab %s · Tee 1", "from %s · Tee 1"), hm(hero.to)) end
  draw.text(fx + boxW // 2, rowY + rowH // 2 + 24, sub, "small", color.BLACK, "center")
end

-- Slate ("Zeitleiste"): senkrechte Linie mit farbigen Zeitpunkten, gruener "Platz frei"-Punkt nach der letzten Belegung
local function todaySlate(m, di, top)
  local margin = 30
  local d = m.days[di]
  draw.text(margin, top + 20, T("Heute · ", "Today · ") .. dayShort(d), "normal", color.BLACK)
  local lineX, y0, yMax = margin + 150, top + 44, draw.height - 26
  local items, lastEnd = {}, -1
  for i = 1, math.min(#d.es, 4) do
    local e = d.es[i]
    items[#items + 1] = { at = e.from, e = e }
    if e.to > lastEnd then lastEnd = e.to end
  end
  if #items == 0 then items[1] = { at = -1, free = true }
  elseif lastEnd >= 0 then items[#items + 1] = { at = lastEnd, free = true } end
  local step = math.min(118, (yMax - y0) // #items)
  draw.rect(lineX, y0, 2, (#items - 1) * step + 20, color.BLACK, true)
  for i, it in ipairs(items) do
    local iy = y0 + (i - 1) * step + 10
    draw.circle(lineX, iy, 9, it.free and color.GREEN or colColor(it.e.col), true)
    draw.circle(lineX, iy, 9, color.BLACK, false)
    draw.circle(lineX, iy, 3, color.WHITE, true)
    draw.text(lineX - 22, iy + 10, it.at >= 0 and hm(it.at) or T("ganzt.", "all d."), "large", color.BLACK, "right")
    local tx = lineX + 24
    local tw = draw.width - margin - tx
    if it.free then
      draw.text(tx, iy + 4, T("Platz frei spielbar", "Course free to play"), "normal", color.GREEN)
      draw.text(tx, iy + 24, T("Start auf Tee 1 möglich", "Start on tee 1 possible"), "small", color.BLACK)
    else
      local e = it.e
      draw.text(tx, iy + 4, fit(e.ev, tw, "normal"), "normal", color.BLACK)
      local meta = colLabel(e.col) .. " · " .. timeRange(e)
      if e.note ~= "" then meta = meta .. " · " .. e.note end
      draw.text(tx, iy + 24, fit(meta, tw, "small"), "small", textCol(e.col))
    end
  end
end

-- Nano ("Zwei-Spalten Platz/Betrieb"): links Tee 1 + Greenkeeping, rechts Kurse & Events + Information
local function todayNano(m, di, top)
  local margin = 18
  local d = m.days[di]
  draw.text(margin, top + 18, dayShort(d) .. T(" · Platzbelegung", " · Occupancy"), "normal", color.BLACK)
  local colW = (draw.width - 2 * margin - 20) // 2
  local titles = { T("PLATZ", "COURSE"), T("BETRIEB", "OPERATIONS") }
  local groups = { { 1, 2 }, { 3, 4 } }
  for c = 1, 2 do
    local x = margin + (c - 1) * (colW + 20)
    local y = top + 34
    draw.rect(x, y, colW, 3, color.BLACK, true)
    y = y + 18
    draw.text(x, y, titles[c], "small", color.BLACK)
    y = y + 12
    for _, col in ipairs(groups[c]) do
      y = y + 18
      dot(x + 5, y - 4, 5, col)
      draw.text(x + 16, y, colLabel(col), "small", textCol(col))
      y = y + 6
      local shown = 0
      for _, e in ipairs(d.es) do
        if e.col == col then
          y = y + 18
          draw.text(x + 2, y, fit(timeRange(e) .. "  " .. e.ev, colW - 4, "small"), "small", color.BLACK)
          if e.note ~= "" and shown == 0 then
            y = y + 15
            draw.text(x + 8, y, fit("> " .. e.note, colW - 10, "small"), "small", color.BLACK)
          end
          y = y + 3
          draw.line(x, y, x + colW - 1, y, color.BLACK)
          shown = shown + 1
          if y > draw.height - 60 then break end
        end
      end
      if shown == 0 then
        y = y + 18
        draw.text(x + 2, y, T("frei", "free"), "small", color.GREEN)
        y = y + 3
        draw.line(x, y, x + colW - 1, y, color.BLACK)
      end
      y = y + 4
    end
  end
end

-- ---------------------------------------------------------------------------
-- Seite WOCHE
-- ---------------------------------------------------------------------------

-- Bento ("Zeilenkarten"): je Tag eine Karte mit schwarzem Tagesblock, bis zu zwei Eintraege
local function weekBento(m, si, top)
  local margin, contentW = 22, draw.width - 44
  local days = math.min(7, #m.days - si + 1)
  local areaTop, areaBottom = top + 8, draw.height - 12
  local cardH = math.min(54, (areaBottom - areaTop - (days - 1) * 6) // math.max(days, 1))
  for i = 0, days - 1 do
    local d = m.days[si + i]
    local y = areaTop + i * (cardH + 6)
    draw.rect(margin, y, contentW, cardH, color.BLACK, false, 10)
    draw.rect(margin, y, 96, cardH, color.BLACK, true, 10)
    draw.rect(margin + 86, y, 10, cardH, color.BLACK, true)
    draw.text(margin + 10, y + cardH // 2 - 2, wdOf(d), "normal", color.WHITE)
    draw.text(margin + 10, y + cardH // 2 + 15, string.format("%02d.%02d.", d.d, d.m), "small", color.WHITE)
    local tx = margin + 110
    local tw = margin + contentW - 12 - tx
    if #d.es == 0 then
      draw.text(tx, y + cardH // 2 + 6, T("frei", "free"), "normal", color.GREEN)
    else
      local show = math.min(2, #d.es)
      for k = 1, show do
        local e = d.es[k]
        local ly = show == 1 and (y + cardH // 2 + 5) or (y + 21 + (k - 1) * 22)
        square(tx, ly - 10, 12, e.col)
        local w = tw - 20 - ((k == 1 and #d.es > 2) and 34 or 0)
        draw.text(tx + 20, ly, fit(timeRange(e) .. "  " .. e.ev, w, "small"), "small", color.BLACK)
      end
      if #d.es > 2 then
        draw.text(margin + contentW - 10, y + 21, "+" .. (#d.es - 2), "small", color.BLACK, "right")
      end
    end
  end
end

-- Slate ("Flache Wochenliste"): Haarlinien, heute fett
local function weekSlate(m, si, top)
  local margin, contentW = 28, draw.width - 56
  local days = math.min(7, #m.days - si + 1)
  local y = top + 10
  draw.rect(margin, y, contentW, 2, color.BLACK, true)
  local rowH = math.min(56, (draw.height - 14 - y) // math.max(days, 1))
  local ti, isToday = todayIndex(m)
  -- Eintragsspalte ab 170 Pixel; die fette Heute-Zeile ("Do 20.08." in large) ist breiter, dann ruecken alle Zeilen mit
  local tx = margin + 170
  if isToday and ti >= si and ti < si + days then tx = math.max(tx, margin + draw.measure(dayShort(m.days[ti]), "large") + 14) end
  for i = 0, days - 1 do
    local d = m.days[si + i]
    local ry = y + i * rowH
    local today = isToday and (si + i) == ti
    draw.text(margin, ry + (today and 34 or 28), dayShort(d), today and "large" or "normal", color.BLACK)
    local tw = margin + contentW - tx
    if #d.es == 0 then
      draw.text(tx, ry + 28, T("frei", "free"), "normal", color.GREEN)
    else
      local show = math.min(2, #d.es)
      for k = 1, show do
        local e = d.es[k]
        local ly = show == 1 and (ry + 28) or (ry + 20 + (k - 1) * 20)
        square(tx, ly - 9, 11, e.col)
        draw.text(tx + 18, ly, fit(timeRange(e) .. " · " .. e.ev, tw - 20, "small"), "small", color.BLACK)
      end
    end
    draw.line(margin, ry + rowH - 1, margin + contentW - 1, ry + rowH - 1, color.BLACK)
  end
end

-- Nano-Volltabelle (Woche: bis zu zwei Eintraege je Tag; 14 Tage: ein Eintrag + Hinweisspalte) mit Legende
local function nanoTable(m, top, si, dayLimit, withNote)
  local margin, contentW = 16, draw.width - 32
  local y = top + 8
  draw.rect(margin, y, contentW, 20, color.BLACK, true)
  local cTag, cZeit, cBer, cEv, cNote = margin + 6, margin + 86, margin + 196, margin + 236, margin + contentW - 150
  draw.text(cTag, y + 14, T("TAG", "DAY"), "small", color.WHITE)
  draw.text(cZeit, y + 14, T("ZEIT", "TIME"), "small", color.WHITE)
  draw.text(cBer, y + 14, T("BER.", "AREA"), "small", color.WHITE)
  draw.text(cEv, y + 14, T("EREIGNIS", "EVENT"), "small", color.WHITE)
  if withNote then draw.text(cNote, y + 14, T("HINWEIS", "NOTE"), "small", color.WHITE) end
  y = y + 20
  local days = math.min(dayLimit, #m.days - si + 1)
  local maxRows = withNote and 14 or 16
  local rowH = math.max(19, math.min(24, (draw.height - 30 - y) // maxRows))
  local rows = 0
  for i = 0, days - 1 do
    if rows >= maxRows then break end
    local d = m.days[si + i]
    local perDay = withNote and 1 or math.min(2, #d.es)
    if perDay == 0 then perDay = 1 end
    for k = 1, perDay do
      if rows >= maxRows then break end
      local ry = y + rows * rowH
      local base = ry + rowH - 6
      if k == 1 then draw.text(cTag, base, dayShort(d), "small", color.BLACK) end
      if #d.es == 0 then
        draw.text(cZeit, base, T("frei", "free"), "small", color.GREEN)
      else
        local e = d.es[k]
        draw.text(cZeit, base, timeRange(e), "small", color.BLACK)
        chip(cBer, ry + rowH - 17, e.col)
        local evW = (withNote and cNote - 8 or margin + contentW) - cEv
        if k == perDay and #d.es > perDay then evW = evW - (withNote and 0 or 26) end
        draw.text(cEv, base, fit(e.ev, evW, "small"), "small", color.BLACK)
        if withNote and e.note ~= "" then
          draw.text(cNote, base, fit(e.note, margin + contentW - cNote - (#d.es > perDay and 26 or 0), "small"), "small", color.BLACK)
        end
        if k == perDay and #d.es > perDay then
          draw.text(margin + contentW - 2, base, "+" .. (#d.es - perDay), "small", color.BLACK, "right")
        end
      end
      draw.line(margin, ry + rowH, margin + contentW - 1, ry + rowH, color.BLACK)
      rows = rows + 1
    end
  end
  local ly, lx = draw.height - 10, margin
  for c = 1, 4 do
    chip(lx, ly - 13, c)
    lx = lx + 32
    draw.text(lx, ly - 2, colLabel(c), "small", color.BLACK)
    lx = lx + draw.measure(colLabel(c), "small") + 16
  end
end

-- ---------------------------------------------------------------------------
-- Seite 14 TAGE
-- ---------------------------------------------------------------------------

-- Bento: Wochenkarte mit Kopfband "KW 34 · 20.08.-26.08." und sieben kompakten Tageszeilen
local function fortnightCard(m, x, w, top, si, count)
  local cardTop = top + 8
  local cardH = draw.height - 14 - cardTop
  draw.rect(x, cardTop, w, cardH, color.BLACK, false, 12)
  draw.rect(x, cardTop, w, 24, color.BLACK, true, 12)
  draw.rect(x, cardTop + 12, w, 12, color.BLACK, true)
  local head = "-"
  if count > 0 then
    local f, l = m.days[si], m.days[si + count - 1]
    head = string.format(T("KW %d · %02d.%02d.-%02d.%02d.", "Wk %d · %02d.%02d.-%02d.%02d."), isoWeek(f.z), f.d, f.m, l.d, l.m)
  end
  draw.text(x + 10, cardTop + 17, head, "small", color.WHITE)
  local rowTop = cardTop + 30
  local rowH = (cardTop + cardH - 6 - rowTop) // 7
  for i = 0, count - 1 do
    local d = m.days[si + i]
    local ry = rowTop + i * rowH
    local base = ry + rowH - 9
    draw.text(x + 10, base, dayShort(d), "small", color.BLACK)
    local tx = x + 84
    if #d.es == 0 then
      draw.text(tx + 16, base, T("frei", "free"), "small", color.GREEN)
    else
      local e = d.es[1]
      dot(tx + 5, ry + rowH - 13, 5, e.col)
      local lw = x + w - 12 - (tx + 16) - (#d.es > 1 and 26 or 0)
      draw.text(tx + 16, base, fit(startOrAllDay(e) .. " " .. e.ev, lw, "small"), "small", color.BLACK)
      if #d.es > 1 then draw.text(x + w - 10, base, "+" .. (#d.es - 1), "small", color.BLACK, "right") end
    end
    if i < count - 1 then draw.line(x + 8, ry + rowH, x + w - 9, ry + rowH, color.BLACK) end
  end
end

local function fortnightBento(m, top)
  local margin = 20
  local cardW = (draw.width - 2 * margin - 14) // 2
  local n = #m.days
  fortnightCard(m, margin, cardW, top, 1, math.min(7, n))
  local second = math.max(0, math.min(7, n - 7))
  if second > 0 then fortnightCard(m, margin + cardW + 14, cardW, top, 8, second) end
end

-- Slate: zwei flache Wochenspalten "WOCHE 1"/"WOCHE 2"
local function fortnightSlate(m, top)
  local margin = 26
  local colW = (draw.width - 2 * margin - 40) // 2
  for c = 0, 1 do
    local x = margin + c * (colW + 40)
    local si = c * 7 + 1
    local count = math.min(7, #m.days - si + 1)
    if count > 0 then
      local y = top + 10
      draw.text(x, y + 10, c == 0 and T("WOCHE 1", "WEEK 1") or T("WOCHE 2", "WEEK 2"), "small", color.BLACK)
      draw.rect(x, y + 16, colW, 3, color.BLACK, true)
      local rowTop = y + 24
      local rowH = math.min(52, (draw.height - 14 - rowTop) // 7)
      for i = 0, count - 1 do
        local d = m.days[si + i]
        local ry = rowTop + i * rowH
        draw.text(x, ry + rowH - 16, dayShort(d), "normal", color.BLACK)
        local tx = x + 94
        if #d.es == 0 then
          draw.text(tx + 17, ry + rowH - 16, T("frei", "free"), "small", color.GREEN)
        else
          local e = d.es[1]
          square(tx, ry + rowH - 26, 11, e.col)
          local tw = x + colW - (tx + 17)
          draw.text(tx + 17, ry + rowH - 22, fit(e.ev, tw, "small"), "small", color.BLACK)
          local sub = timeRange(e)
          if #d.es > 1 then sub = string.format(T("%s · +%d weitere", "%s · +%d more"), sub, #d.es - 1) end
          draw.text(tx + 17, ry + rowH - 7, fit(sub, tw, "small"), "small", color.BLACK)
        end
        draw.line(x, ry + rowH, x + colW - 1, ry + rowH, color.BLACK)
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Einstieg Seiten
-- ---------------------------------------------------------------------------

-- Leerzustaende wie drawGolfEmptyStateIfNeeded(): nicht eingerichtet -> Fehler/laedt -> Tabelle leer. Liegt fuer die
-- eingestellte Clubnummer ein aelterer Stand vor, wird er trotz eines spaeteren Fehlversuchs gezeigt.
local function model(ctx)
  local club = clubOf(ctx.cfg)
  if #club < 4 then
    notice("gear", T("Noch nicht eingerichtet.", "Not set up yet."), T("Einstellungen der App: PC-CADDIE-Clubnummer", "App settings: PC CADDIE club number"))
    return nil
  end
  local m = loadPlan()
  if m and m.club ~= club then m = nil end
  if m == nil then
    local fail = loadErr()
    if fail and fail.club == club then
      notice("warning", T("Abruf fehlgeschlagen.", "Fetch failed."), fail.msg ~= "" and fail.msg or T("Nächster Versuch in Kürze.", "Retrying shortly."))
    else
      notice("clock", T("Wird geladen ...", "Loading ..."))
    end
    return nil
  end
  if #m.days == 0 then
    notice("info", T("Keine Belegungsdaten gefunden.", "No occupancy data found."))
    return nil
  end
  return m
end

function on_draw(ctx, page)
  EN = ctx.lang == "en"
  draw.clear(color.WHITE)
  local m = model(ctx)
  if m == nil then return end
  local top = draw.top
  local style = ctx.cfg.style
  if page == 2 then
    local si = todayIndex(m)
    if style == "flat" then weekSlate(m, si, top)
    elseif style == "compact" then nanoTable(m, top, si, 7, false)
    else weekBento(m, si, top) end
  elseif page == 3 then
    if style == "flat" then fortnightSlate(m, top)
    elseif style == "compact" then nanoTable(m, top, 1, MAX_DAYS, true)
    else fortnightBento(m, top) end
  else
    local di = todayIndex(m)
    if style == "flat" then todaySlate(m, di, top)
    elseif style == "compact" then todayNano(m, di, top)
    else todayBento(m, di, top) end
  end
end

-- ---------------------------------------------------------------------------
-- Widget "Platzbelegung heute" (dwDrawGolfToday): Fahne + grosser Status in Statusfarbe, Caption mit Zeit und Zahl der
-- Belegungen, ab 70 Pixel Widget-Hoehe die Eintraege des Tages; freier Tag: "Platz frei" + naechste Belegung als Ausblick.
-- Keine Widget-Optionen (die eingebaute App hatte keine; die Schriftstufe hat hier wie dort keine Wirkung).
-- ---------------------------------------------------------------------------

local function sampleModel()
  local z = dfc(2026, 8, 20)
  return { club = "", at = 0, days = {
    { y = 2026, m = 8, d = 20, z = z, es = {
      { col = 2, from = 360, to = 540, res = false, ev = "Platz gesperrt - Pflanzenschutz", note = "" },
      { col = 4, from = -1, to = -1, res = true, ev = "Damennachmittag im LTGK", note = "" } } },
  }, sample = true }
end

function on_widget(ctx, box)
  EN = ctx.lang == "en"
  local m = loadPlan()
  if m and m.club ~= clubOf(ctx.cfg) then m = nil end
  if (m == nil or #m.days == 0) and ctx.sample then m = sampleModel() end
  if m == nil or #m.days == 0 then
    draw.text(box.x + 12, box.y + 16, fit(T("Noch keine Daten", "No data yet"), box.w - 20, "small"), "small", color.BLACK)
    return
  end
  local maxY = box.y + box.h - 4
  local textX = box.x + 12
  local textW = math.max(20, box.w - 24)
  local tier = box.font or 0 -- Widget-Einstellung Schriftgroesse: -1 klein, 0 normal, 1 gross
  local cmp = (box.style or ctx.cfg.style) == "compact" -- Widget-Design "Kompakt"
  local fBig = tier < 0 and "normal" or "large"
  local fSm = tier > 0 and "normal" or "small"
  local lineH = (tier > 0 and 23 or 19) - (cmp and 4 or 0)
  local G = cmp and 0 or 18
  local roomForLines = (box.fh or box.h) >= 70
  local statusY = box.y + 22
  local gap = cmp and 0 or 8
  local bigX, bigW = textX + G + gap, math.max(20, textW - G - gap)
  local di = m.sample and 1 or todayIndex(m)
  local d = m.days[di]

  if #d.es == 0 then
    draw.text(bigX, statusY, fit(T("Platz frei", "Course free"), bigW, fBig), fBig, color.GREEN)
    if not cmp then flag(textX, statusY - G - 2, G, color.GREEN) end
    if roomForLines and statusY + lineH <= maxY then
      local y = statusY + lineH + 2
      local line = T("keine Belegung in Sicht", "no bookings ahead")
      for i = di + 1, #m.days do
        local n = m.days[i]
        if #n.es > 0 then
          line = string.format(T("Nächste: %s %s %s", "Next: %s %s %s"), dayShort(n), startOrAllDay(n.es[1]), n.es[1].ev)
          break
        end
      end
      draw.text(textX, y, fit(line, textW, fSm), fSm, color.BLACK)
    end
    return
  end

  local nowMin = 12 * 60
  if not m.sample then
    local _, _, nm = nowLocal()
    nowMin = nm or 0
  end
  local st = nowStatus(d, nowMin, 180)
  local sc = st.busyNow and color.RED or color.GREEN
  local big, cap
  if st.busyNow then
    big = T("Jetzt belegt", "Busy now")
    if st.unknownEnd then cap = T("Ende unbekannt", "end unknown")
    else cap = string.format(T("bis %s Uhr", "until %s"), hm(st.untilMin)) end
  else
    big = T("Jetzt frei", "Free now")
    if st.freeWindow then cap = T("mind. 3 Std. frei", "free for 3+ h")
    else cap = string.format(T("frei bis %s Uhr", "free until %s"), hm(st.nextBusy)) end
  end
  draw.text(bigX, statusY, fit(big, bigW, fBig), fBig, sc)
  if not cmp then flag(textX, statusY - G - 2, G, sc) end
  if statusY + 16 <= maxY then
    statusY = statusY + (cmp and 14 or 16)
    local n = #d.es
    local cnt = EN and string.format("%d booking%s today", n, n == 1 and "" or "s") or string.format("%d Belegung%s heute", n, n == 1 and "" or "en")
    draw.text(textX, statusY, fit(cap .. " · " .. cnt, textW, fSm), fSm, sc)
  end
  if roomForLines then
    local y = statusY + lineH
    for _, e in ipairs(d.es) do
      if y > maxY then break end
      dot(textX + 4, y - 4, 4, e.col)
      draw.text(textX + 14, y, fit(timeRange(e) .. "  " .. e.ev, textW - 14, fSm), fSm, color.BLACK)
      y = y + lineH
    end
  end
end
