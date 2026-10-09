-- Kalender (Skript-Variante der frueheren eingebauten Kalender-App): Tag / Woche / Monat, je drei Stile
-- (Slate = flat, Bento = cards, Nano = compact), bis zu vier ICS-Quellen, Widget "Naechste Termine".
-- Skript-API Level 20: ics.fetch (Stream-Parser mit Wiederholungen, EXDATE, TZID), time.date / time.mktime,
-- on_header (Kopfzeilen-Text) und pages[].ownDate. Siehe docs/SKRIPT_APPS.md und CHANGELOG 634 / 637.
-- Ab 637: Zeitfenster, Tageskarten (letzte Karte angeschnitten), Zustandssymbole, Widget-Glyphen und "Quellen pruefen"
-- wie die frueher eingebaute App; "lastEnd" in ctx.data fuer das bedingte Widget (Manifest widget.relevantWhen).
--
-- Ablauf: on_fetch holt alle aktiven Quellen mit EINEM Aufruf ics.fetch (Fenster Wochen-/Monatsanfang bis +45 Tage,
-- hoechstens 160 Termine) und legt sie als Textzeilen in file ev1 / ev2 ab ("Start Ende Ganztag Quelle Titel Ort Notiz",
-- mit Tabulator getrennt). Faellt eine Quelle aus, bleiben ihre alten Zeilen erhalten. on_draw / on_widget lesen nur.

--#include text
--#include ui

local function en_(ctx) return ctx.lang == "en" end

local COLS = { blue = color.BLUE, green = color.GREEN, yellow = color.YELLOW, red = color.RED }
local CIDX = { blue = 1, green = 2, yellow = 3, red = 4 }
local DOTS = { color.BLUE, color.GREEN, color.YELLOW, color.RED }
local DEFC = { "blue", "green", "yellow", "red" }

local MON_DE = { "Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember" }
local MON_EN = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" }
-- Monatskuerzel im Datumsblock des Widgets: Grossbuchstaben wie dashMonthShort() der eingebauten App
local MON_S_DE = { "JAN", "FEB", "MÄR", "APR", "MAI", "JUN", "JUL", "AUG", "SEP", "OKT", "NOV", "DEZ" }
local MON_S_EN = { "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" }
local WDS_DE = { "Mo", "Di", "Mi", "Do", "Fr", "Sa", "So" }
local WDS_EN = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
local WDF_DE = { "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag" }
local WDF_EN = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" }

local W, H = 800, 480
local FILE_MAX = 23000
local MAX_EVENTS = 160
local FAR = 2147000000 -- "kein Ende" fuer Einzeltermine (wie die eingebaute App: nur die fruehesten 160 bleiben)

-- Schriftfarbe auf einer Terminfarbe (Gelb -> Schwarz, sonst Weiss)
local function ink(c)
  if c == color.YELLOW then return color.BLACK end
  return color.WHITE
end

-- Montag = 1 .. Sonntag = 7 aus wday (0 = Sonntag)
local function isoWd(wday) return wday == 0 and 7 or wday end

local function monthName(m, en) return (en and MON_EN or MON_DE)[m] end

local function daysIn(y, m)
  if m == 2 then
    if (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0 then return 29 end
    return 28
  end
  if m == 4 or m == 6 or m == 9 or m == 11 then return 30 end
  return 31
end

local function fmtTime(h, m, c24)
  if c24 ~= false then return string.format("%02d:%02d", h, m) end
  local hh = h % 12
  if hh == 0 then hh = 12 end
  return string.format("%02d:%02d %s", hh, m, h < 12 and "AM" or "PM")
end

-- ---------------------------------------------------------------------------
-- Quellen und Daten
-- ---------------------------------------------------------------------------

-- aktive Quellen mit Adresse: Liste {url, tag, color, cidx}
local function sources(cfg)
  local out = {}
  for i = 1, 4 do
    local u = cfg["src" .. i .. "Url"]
    if type(u) == "string" and u ~= "" and cfg["src" .. i .. "On"] ~= false then
      local cn = cfg["src" .. i .. "Color"]
      if COLS[cn] == nil then cn = DEFC[i] end
      out[#out + 1] = { url = u, tag = tostring(i), color = COLS[cn], cidx = CIDX[cn] }
    end
  end
  return out
end

-- Quelle eingerichtet = Link vorhanden (auch abgeschaltet): wie "calendarSourceCount" der eingebauten App
local function configured(cfg)
  for i = 1, 4 do
    local u = cfg["src" .. i .. "Url"]
    if type(u) == "string" and u ~= "" then return true end
  end
  return false
end

local function decorate(e, c, ci)
  local d, d2 = time.date(e.s), time.date(e.e)
  e.c, e.ci = c, ci
  e.k = d.year * 10000 + d.month * 100 + d.day
  e.wd = d.wday
  e.hh, e.mi = d.hour, d.min
  e.h = d.hour + d.min / 60
  e.eh = d2.hour + d2.min / 60
  e.ehh, e.emi = d2.hour, d2.min
  e.bd = (e.title:find("Geburtstag", 1, true) or e.title:find("Birthday", 1, true)) ~= nil
  return e
end

-- Beispieltermine (Dashboard-Editor)
local function demo(now)
  local t = time.date(now)
  local out = {}
  local function add(dd, h, m, len, title, loc, ci, ad)
    local s = time.mktime({ year = t.year, month = t.month, day = t.day + dd, hour = ad and 0 or h, min = m })
    local e = { s = s, e = ad and (s + 86400) or (s + len * 60), ad = ad, title = title, loc = loc, notes = "" }
    out[#out + 1] = decorate(e, DOTS[ci], ci)
  end
  add(0, 9, 30, 60, "Team-Meeting", "Raum 2", 1, false)
  add(0, 14, 0, 90, "Zahnarzt", "Hauptstraße 5", 4, false)
  add(1, 0, 0, 0, "Geburtstag Anna", "", 3, true)
  add(2, 18, 30, 120, "Chor", "Gemeindehaus", 2, false)
  return out
end

-- Termine aus den Dateien, die im Fenster [lo, hi) liegen oder hineinreichen (Quelle muss noch aktiv sein); hoechstens cap Stueck.
-- Nur das Fenster der gezeigten Seite wird als Tabellen angelegt: spart Lua-Speicher (160 Termine waeren ueber 250 KB).
local function loadEvents(ctx, now, lo, hi, cap)
  if ctx.sample then return demo(now) end
  local by = {}
  for _, s in ipairs(sources(ctx.cfg)) do by[s.tag] = s end
  local out = {}
  for f = 1, 2 do
    local raw = file.read("ev" .. f)
    if raw == nil or raw == "" then break end
    for line in raw:gmatch("[^\n]+") do
      local s, e, fl, tag, title, loc, notes = line:match("^(%d+)\t(%d+)\t(%d)\t(%w+)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
      local sr = tag and by[tag]
      if sr then
        s, e = tonumber(s), tonumber(e)
        if e >= lo and s < hi then
          out[#out + 1] = decorate({ s = s, e = e, ad = fl == "1", title = title, loc = loc, notes = notes }, sr.color, sr.cidx)
          if #out >= cap then return out end
        end
      end
    end
  end
  return out
end

local function serialize(e)
  local function c(s) return (tostring(s or ""):gsub("%c", " ")) end
  return string.format("%d\t%d\t%d\t%s\t%s\t%s\t%s", e.start, e["end"], e.allDay and 1 or 0, e.src, c(e.title), c(e.location), c(e.notes))
end

function on_fetch(ctx)
  local srcs = sources(ctx.cfg)
  if #srcs == 0 then
    -- wie die eingebaute App: Quellen eingetragen, aber alle abgeschaltet = leerer Kalender; ohne Eintraege "nicht eingerichtet"
    ctx.data.set("st", configured(ctx.cfg) and "ok" or "none")
    ctx.data.set("lastEnd", 0)
    file.write("ev1", "")
    file.write("ev2", "")
    return true
  end
  local now = time.now()
  local t = time.date(now)
  local wdn = isoWd(t.wday) - 1
  -- Fenster wie die eingebaute App: Termine, die nach dem Monatsanfang enden; Einzeltermine ohne Obergrenze (nur die
  -- fruehesten 160 bleiben), Wiederholungen werden bis +45 Tage aufgeloest.
  local mstart = time.mktime({ year = t.year, month = t.month, day = 1 })
  local nextMon = time.mktime({ year = t.year, month = t.month, day = t.day - wdn + 7 })
  local req = {}
  for i, s in ipairs(srcs) do req[i] = { url = s.url, tag = s.tag } end
  local list, info = ics.fetch({
    sources = req, from = mstart, to = FAR, recurTo = now + 45 * 86400, max = MAX_EVENTS,
    limits = { title = 39, location = 31, notes = 55 }, notesUntil = nextMon,
  })
  local function fail() -- nichts erreichbar: ohne alte Termine als Fehler melden, mit alten Terminen unveraendert weiter anzeigen
    local old = file.read("ev1")
    if old == nil or old == "" then ctx.data.set("st", "e") end
    return true
  end
  if list == nil then return fail() end
  local failed, anyFail, allFail = {}, false, true
  for _, s in ipairs(srcs) do
    if info.ok[s.tag] then allFail = false else failed[s.tag] = true; anyFail = true end
  end
  if allFail then return fail() end
  -- alte Zeilen ausgefallener Quellen (nur Zeichenketten und Zahlen, keine Tabellen je Zeile: spart Lua-Speicher)
  local oldL, oldS, oldE = {}, {}, {}
  if anyFail then
    for f = 1, 2 do
      local raw = file.read("ev" .. f)
      if raw == nil or raw == "" then break end
      for line in raw:gmatch("[^\n]+") do
        local s, e, tag = line:match("^(%d+)\t(%d+)\t%d\t(%w+)\t")
        if tag and failed[tag] then oldL[#oldL + 1] = line; oldS[#oldS + 1] = tonumber(s); oldE[#oldE + 1] = tonumber(e) end
      end
    end
  end
  -- beide Folgen sind nach Beginn sortiert: zusammenfuehren, dabei auf zwei Dateien zu je hoechstens FILE_MAX Bytes verteilen
  local parts, cur, size, n, lastEnd = { {} }, 1, 0, 0, 0
  local function put(l, e)
    if n >= MAX_EVENTS or cur > 2 then return end
    if size + #l + 1 > FILE_MAX then
      cur = cur + 1
      size = 0
      if cur > 2 then return end
      parts[cur] = {}
    end
    parts[cur][#parts[cur] + 1] = l
    size = size + #l + 1
    n = n + 1
    if e > lastEnd then lastEnd = e end
  end
  local i, j = 1, 1
  while i <= #list or j <= #oldL do
    if j > #oldL or (i <= #list and list[i].start <= oldS[j]) then
      put(serialize(list[i]), list[i]["end"])
      i = i + 1
    else
      put(oldL[j], oldE[j])
      j = j + 1
    end
  end
  for f = 1, 2 do
    file.write("ev" .. f, parts[f] and table.concat(parts[f], "\n") or "")
  end
  ctx.data.set("st", "ok")
  ctx.data.set("lastEnd", lastEnd) -- Ende des spaetesten Termins: die Firmware zeigt das Widget "nur wenn Termine anstehen" daran (Manifest widget.relevantWhen)
  return true
end

-- ---------------------------------------------------------------------------
-- "Quellen pruefen" (Knoepfe im Einstellungsformular): ruft die Links ab und meldet je Quelle OK/Fehler, Anzahl Termine, gekuerzt
-- ---------------------------------------------------------------------------

local function checkSources(ctx, only)
  local en = en_(ctx)
  local req, idx = {}, {}
  for i = 1, 4 do
    local u = ctx.cfg["src" .. i .. "Url"]
    if (only == nil or only == i) and type(u) == "string" and u ~= "" then
      req[#req + 1] = { url = u, tag = tostring(i) }
      idx[#idx + 1] = i
    end
  end
  if #req == 0 then
    return { ok = false, message = en and "No calendar link entered." or "Kein Kalender-Link eingetragen." }
  end
  local now = time.now()
  if now == nil then return { ok = false, message = en and "Waiting for the clock ..." or "Warte auf die Uhrzeit ..." } end
  local t = time.date(now)
  local list, info = ics.fetch({
    sources = req, from = time.mktime({ year = t.year, month = t.month, day = 1 }), to = FAR, recurTo = now + 45 * 86400, max = 200,
    limits = { title = 0, location = 0, notes = 0 },
  })
  if list == nil then return { ok = false, message = tostring(info) } end
  local cnt = {}
  for _, e in ipairs(list) do cnt[e.src] = (cnt[e.src] or 0) + 1 end
  local out, allOk = {}, true
  for _, i in ipairs(idx) do
    local tag = tostring(i)
    local part
    if info.ok[tag] then
      part = string.format(en and "%d: OK, %d events" or "%d: OK, %d Termine", i, cnt[tag] or 0)
      if info.truncated[tag] then part = part .. (en and " (cut off)" or " (gekürzt)") end
    else
      allOk = false
      part = string.format(en and "%d: error (%s)" or "%d: Fehler (%s)", i, cut(tostring(info.err[tag] or "?"), 40))
    end
    if ctx.cfg["src" .. i .. "On"] == false then part = part .. (en and " - off" or " - aus") end
    out[#out + 1] = part
  end
  return { ok = allOk, message = table.concat(out, "; ") }
end

function on_action(ctx, name)
  if name == "check_all" then return checkSources(ctx, nil) end
  local n = tonumber(name:match("^check_(%d)$"))
  if n ~= nil and n >= 1 and n <= 4 then return checkSources(ctx, n) end
  return { ok = false, message = "?" }
end

-- ---------------------------------------------------------------------------
-- Kopfzeile
-- ---------------------------------------------------------------------------

local function weekLabel(y, m, week, en)
  return string.format(en and "%s %d - Week %d" or "%s %d - KW %d", monthName(m, en), y, week)
end

function on_header(ctx, page)
  local en = en_(ctx)
  local now = time.now()
  if now == nil then return nil end
  local t = time.date(now)
  if page == 2 then
    local mon = time.date(time.mktime({ year = t.year, month = t.month, day = t.day - (isoWd(t.wday) - 1), hour = 12 }))
    return weekLabel(mon.year, mon.month, mon.week, en)
  elseif page == 3 then
    return weekLabel(t.year, t.month, t.week, en)
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Zeichenbausteine
-- ---------------------------------------------------------------------------

local function thick(x, y, w, h, r, c)
  draw.rect(x, y, w, h, c, false, r)
  draw.rect(x + 1, y + 1, w - 2, h - 2, c, false, r > 1 and r - 1 or 0)
end

local function cake(cx, cy, c)
  draw.circle(cx, cy - 11, 2, c, true)
  draw.rect(cx - 1, cy - 9, 3, 6, c, false)
  draw.line(cx - 1, cy - 5, cx + 1, cy - 7, c)
  draw.line(cx - 9, cy - 1, cx - 5, cy - 3, c)
  draw.line(cx - 5, cy - 3, cx - 1, cy - 1, c)
  draw.line(cx - 1, cy - 1, cx + 3, cy - 3, c)
  draw.line(cx + 3, cy - 3, cx + 7, cy - 1, c)
  draw.circle(cx - 5, cy - 2, 1, c, true)
  draw.circle(cx - 1, cy - 2, 1, c, true)
  draw.circle(cx + 3, cy - 2, 1, c, true)
  draw.rect(cx - 9, cy - 1, 18, 8, c, false, 3)
  draw.line(cx - 6, cy + 2, cx - 4, cy + 2, c)
  draw.line(cx + 1, cy + 2, cx + 3, cy + 2, c)
  draw.line(cx - 6, cy + 4, cx - 4, cy + 4, c)
  draw.line(cx + 1, cy + 4, cx + 3, cy + 4, c)
  draw.rect(cx - 11, cy + 8, 22, 3, c, false, 1)
end

local function durText(e, en)
  if e.ad then return en and "All day" or "Ganztägig" end
  local mins = (e.e - e.s) // 60
  if mins < 1 then mins = 1 end
  local h, m = mins // 60, mins % 60
  if h > 0 and m > 0 then return string.format("%dh %dmin", h, m) end
  if h > 0 then return string.format("%dh", h) end
  return string.format("%dmin", m)
end

-- Zustandsanzeigen wie drawStateNotice / drawStateNoticeCompact der eingebauten App (Kreis mit Zeichen + Text):
-- Fehler = roter Kreis "!", Einrichtung = blauer Kreis "?", leer = schwarzer Kreis "-", laedt = Ring mit drei Punkten.
local GLYPH = { setup = "?", error = "!", empty = "-" }

local function stateNotice(kind, line1, line2)
  local cx = W // 2
  local r = 22
  local cy = draw.top + 14 + r
  if kind == "loading" then
    for i = 0, 2 do draw.circle(cx, cy, r - i, color.BLACK, false) end
    for i = -1, 1 do draw.circle(cx + i * 12, cy, 3, color.BLACK, true) end
  else
    local fill = kind == "error" and color.RED or (kind == "setup" and color.BLUE or color.BLACK)
    draw.circle(cx, cy, r, fill, true)
    draw.text(cx, cy + 7, GLYPH[kind], "large", color.WHITE, "center")
  end
  local y1 = cy + r + 32
  draw.text(cx, y1, line1, "large", color.BLACK, "center")
  if line2 ~= nil then draw.text(cx, y1 + 26, line2, "normal", color.BLACK, "center") end
end

local function stateNoticeCompact(cx, y, kind, line1)
  local r = 10
  local tw = draw.measure(line1, "normal")
  local ccx = cx - (tw + 2 * r + 10) // 2 + r
  draw.circle(ccx, y, r, color.ACCENT, true)
  if kind == "loading" then
    for i = -1, 1 do draw.circle(ccx + i * 5, y, 1, color.WHITE, true) end
  else
    draw.text(ccx, y + 4, GLYPH[kind], "normal", color.WHITE, "center")
  end
  draw.text(ccx + r + 5 + tw // 2, y + 4, line1, "normal", color.BLACK, "center")
end

-- ---------------------------------------------------------------------------
-- Tagesseite
-- ---------------------------------------------------------------------------

local function dayPage(ctx, evs, st, en, t, topY)
  local cfg = ctx.cfg
  local cp = st == "compact"
  local bx, bs = cp and 20 or 26, cp and 52 or 64
  draw.rect(bx, topY, bs, bs, color.ACCENT, true, cp and 14 or 16)
  if cp then
    draw.text(bx + bs // 2, topY + 34, tostring(t.day), "normal", color.ACCENT_INK, "center")
  else
    draw.text(bx + bs // 2, topY + bs - 14, tostring(t.day), "large", color.ACCENT_INK, "center")
  end
  local tx = bx + bs + (cp and 12 or 16)
  draw.text(tx, topY + (cp and 22 or 26), (en and WDF_EN or WDF_DE)[isoWd(t.wday)], "normal", color.BLACK, "left")
  draw.text(tx, topY + (cp and 42 or 48), weekLabel(t.year, t.month, t.week, en), "normal", color.BLACK, "left")

  local y = topY + bs + (cp and 12 or 18)
  local cardX = cp and 20 or 26
  local cardW = W - 2 * cardX
  local gap = cp and 7 or 12
  local chipX = cardX + (cp and 8 or 10)
  local chipW = cp and 54 or 66
  local chipH = cp and 24 or 30
  local titleX = chipX + chipW + (cp and 12 or 16)
  local textMaxW = cardX + cardW - (cp and 8 or 10) - titleX
  local key = t.year * 10000 + t.month * 100 + t.day
  local shown = 0
  for _, e in ipairs(evs) do
    if e.k == key then
      local isB = cfg.bdaySep == true and e.bd
      local hasLoc = e.loc ~= ""
      local hasNotes = e.notes ~= ""
      local detail = not isB and (cfg.dayDur ~= false or (cfg.dayLoc ~= false and hasLoc))
      local notesRow = not isB and cfg.dayNotes ~= false and hasNotes
      local extra = (detail and 1 or 0) + (notesRow and 1 or 0)
      local cardH
      if cp then cardH = extra == 0 and 40 or (extra == 1 and 50 or 64)
      else cardH = extra == 0 and 50 or (extra == 1 and 62 or 80) end
      if y >= H then break end -- wie die eingebaute App: die letzte Karte wird am unteren Rand angeschnitten (Anzeigebereich schneidet ab)
      if st == "cards" then card(cardX, y, cardW, cardH, e.c, 14) else thick(cardX, y, cardW, cardH, cp and 10 or 14, color.BLACK) end
      local chipY = y + (cp and 6 or 10)
      draw.rect(chipX, chipY, chipW, chipH, e.c, true, cp and 8 or 10)
      local cf = cp and "small" or "normal"
      local cb = chipY + chipH - (cp and 8 or 11)
      if isB then
        cake(chipX + chipW // 2, chipY + chipH // 2, ink(e.c))
      elseif e.ad then
        draw.text(chipX + chipW // 2, cb, en and "All day" or "Ganztag", cf, ink(e.c), "center")
      else
        draw.text(chipX + chipW // 2, cb, string.format("%02d:%02d", e.hh, e.mi), cf, ink(e.c), "center")
      end
      if cfg.dayName ~= false then
        local tf = cp and "normal" or "medium"
        draw.text(titleX, y + (cp and 22 or 30), fit(e.title, textMaxW, tf), tf, color.BLACK, "left")
      end
      local lineY = y + (cp and 38 or 49)
      local lf = cp and "small" or "normal"
      local step = cp and 14 or 18
      if detail then
        local inclD, inclL = cfg.dayDur ~= false, cfg.dayLoc ~= false and hasLoc
        local s
        if inclD and inclL then
          s = string.format(en and "Duration: %s · Location: %s" or "Dauer: %s · Ort: %s", durText(e, en), e.loc)
        elseif inclD then
          s = string.format(en and "Duration: %s" or "Dauer: %s", durText(e, en))
        else
          s = string.format(en and "Location: %s" or "Ort: %s", e.loc)
        end
        draw.text(titleX, lineY, fit(s, textMaxW, lf), lf, color.BLACK, "left")
        lineY = lineY + step
      end
      if notesRow then
        draw.text(titleX, lineY, fit(e.notes, textMaxW, lf), lf, color.BLACK, "left")
      end
      y = y + cardH + gap
      shown = shown + 1
    end
  end
  if shown == 0 then
    local h = cp and 40 or 50
    if st == "cards" then card(cardX, y, cardW, h, color.ACCENT, 14) else thick(cardX, y, cardW, h, cp and 10 or 14, color.BLACK) end
    stateNoticeCompact(W // 2, y + (cp and 22 or 27), "empty", en and "No events today." or "Heute keine Termine.")
  end
end

-- ---------------------------------------------------------------------------
-- Wochenseite
-- ---------------------------------------------------------------------------

local function weekPage(ctx, evs, st, en, t, topY, now)
  local cfg = ctx.cfg
  local cards, cp = st == "cards", st == "compact"
  local axisW = cp and 44 or 52
  local gridLeft = 12 + axisW
  local gridWidth = (W - 12) - gridLeft
  local colEdge = {}
  for c = 0, 7 do colEdge[c] = gridLeft + gridWidth * c // 7 end
  local headerH = cp and 40 or 50
  local headerY = topY
  local sepY = headerY + headerH + 2
  local gridTop = sepY + 3 + 10
  local tsh = cp and 5 or 6
  local teh = cp and 23 or 22
  local range = teh - tsh
  local gridBottom = H - 16
  local gridHeight = gridBottom - gridTop
  local pxh = gridHeight / range
  local bands = range // 2
  local rowEdge = {}
  for r = 0, bands do rowEdge[r] = gridTop + gridHeight * r // bands end
  local pad = cp and 6 or 10
  local fx, fy, fw, fh = gridLeft - 6, headerY - pad, gridWidth + 12, gridBottom - headerY + 2 * pad
  if cards then card(fx, fy, fw, fh, color.ACCENT, 16) else thick(fx, fy, fw, fh, 16, color.BLACK) end
  for c = 1, 6 do draw.line(colEdge[c], headerY, colEdge[c], gridBottom, color.BLACK) end
  draw.rect(gridLeft - 6, sepY, gridWidth + 12, 3, color.ACCENT, true)
  for r = 0, bands do
    local ly = rowEdge[r]
    draw.line(gridLeft, ly, gridLeft + gridWidth, ly, color.BLACK)
    draw.text(gridLeft - 8, ly + 4, tostring(tsh + r * 2), "normal", color.BLACK, "right")
  end

  local wdn = isoWd(t.wday) - 1
  local ds = {}
  for d = 0, 7 do ds[d] = time.mktime({ year = t.year, month = t.month, day = t.day - wdn + d }) end
  local bdSep = cfg.bdaySep == true
  for d = 0, 6 do
    local dd = time.date(ds[d])
    local isToday = dd.year == t.year and dd.month == t.month and dd.day == t.day
    local colX, colW = colEdge[d], colEdge[d + 1] - colEdge[d]
    local ccx = colX + colW // 2
    local hc = color.BLACK
    if isToday then
      draw.rect(colX + 3, headerY + 2, colW - 6, headerH - 4, color.ACCENT, true, 10)
      hc = color.ACCENT_INK
    end
    draw.text(ccx, headerY + 13, (en and WDS_EN or WDS_DE)[d + 1], "normal", hc, "center")
    draw.text(ccx, headerY + headerH - 6, tostring(dd.day), "large", hc, "center")

    local adCount, adFirst = 0, nil
    for _, e in ipairs(evs) do
      if e.ad and not (bdSep and e.bd) and e.s >= ds[d] and e.s < ds[d + 1] then
        adFirst = adFirst or e
        adCount = adCount + 1
      end
    end
    local adTop, adH = gridTop + 2, gridBottom - gridTop - 4
    local adBuf, adLines = nil, nil
    if adFirst then
      thick(colX + 3, adTop, colW - 6, adH, 10, adFirst.c)
      adBuf = adCount > 1 and string.format(en and "+%d all-day" or "+%d ganzt.", adCount) or adFirst.title
      local adMaxW = colW - 16
      if draw.measure(adBuf, "normal") > adMaxW then
        local n = (adH - 18) // 14
        if n < 1 then n = 1 elseif n > 6 then n = 6 end
        adLines = wrapLines(adBuf, adMaxW, "small", n)
      end
    end

    local abt, abb = {}, {}
    for _, e in ipairs(evs) do
      if not e.ad and not (bdSep and e.bd) and e.s < ds[d + 1] and e.e > ds[d] then
        local sH = e.s < ds[d] and tsh or e.h
        local eH = e.e > ds[d + 1] and teh or e.eh
        if sH < tsh then sH = tsh end
        if eH > teh then eH = teh end
        if eH <= sH then eH = sH + 0.4 end
        local bt = gridTop + math.floor((sH - tsh) * pxh)
        local bb = gridTop + math.floor((eH - tsh) * pxh)
        local bh = bb - bt
        if bh < 14 then bh = 14 end
        if #abt < 16 then abt[#abt + 1] = bt; abb[#abb + 1] = bb end
        local bx2, bw = colX + 3, colW - 6
        draw.rect(bx2, bt, bw, bh, e.c, true, 6)
        thick(bx2, bt, bw, bh, 6, color.BLACK)
        local fc = ink(e.c)
        local ly, used = bt + 16, 0
        if cfg.wkName ~= false and bh >= 16 + used * 14 then
          local maxW = bw - 14
          if draw.measure(e.title, "normal") <= maxW then
            draw.text(bx2 + 7, ly, e.title, "normal", fc, "left")
            ly = ly + 14
            used = used + 1
          else
            local n = (bh - (ly - bt) - 2) // 14
            if n < 1 then n = 1 elseif n > 4 then n = 4 end
            for _, ln in ipairs(wrapLines(e.title, maxW, "small", n)) do
              draw.text(bx2 + 7, ly, ln, "small", fc, "left")
              ly = ly + 14
              used = used + 1
            end
          end
        end
        if cfg.wkLoc == true and e.loc ~= "" and bh >= 16 + used * 14 then
          draw.text(bx2 + 7, ly, fit(e.loc, bw - 14, "small"), "small", fc, "left")
          ly = ly + 14
          used = used + 1
        end
        if cfg.wkNotes == true and e.notes ~= "" and bh >= 16 + used * 14 then
          draw.text(bx2 + 7, ly, fit(e.notes, bw - 14, "small"), "small", fc, "left")
        end
      end
    end

    if adBuf then
      local nl = adLines and math.max(#adLines, 1) or 1
      local cy = adTop + 20
      local moved, guard = true, 0
      while moved and guard < 20 do
        moved = false
        guard = guard + 1
        local tt, tb = cy - 12, cy + (nl - 1) * 14 + 4
        for i = 1, #abt do
          if tt < abb[i] + 3 and tb > abt[i] - 3 then
            cy = abb[i] + 17
            moved = true
          end
        end
      end
      if cy + (nl - 1) * 14 > adTop + adH - 6 then cy = adTop + 20 end
      if adLines then
        for _, ln in ipairs(adLines) do
          draw.text(colX + 8, cy, ln, "small", color.BLACK, "left")
          cy = cy + 14
        end
      else
        draw.text(colX + 8, cy, adBuf, "normal", color.BLACK, "left")
      end
    end
  end

  local nowH = t.hour + t.min / 60
  if nowH >= tsh and nowH <= teh then
    local ny = gridTop + math.floor((nowH - tsh) * pxh)
    draw.line(gridLeft, ny, gridLeft + gridWidth - 1, ny, color.ACCENT)
    draw.line(gridLeft, ny + 1, gridLeft + gridWidth - 1, ny + 1, color.ACCENT)
    local s = string.format("%02d:%02d", t.hour, t.min)
    local bw = draw.measure(s, "normal") + 12
    local bx2 = (gridLeft - 10) - bw
    if bx2 < 2 then bx2 = 2 end
    draw.rect(bx2, ny - 9, bw, 18, color.ACCENT, true, 8)
    draw.text(bx2 + 6, ny - 9 + 18 - 5, s, "normal", color.ACCENT_INK, "left")
  end
end

-- ---------------------------------------------------------------------------
-- Monatsseite
-- ---------------------------------------------------------------------------

local function monthPage(ctx, evs, st, en, t, topY)
  local cards, cp = st == "cards", st == "compact"
  local mask = {}
  local ym = t.year * 100 + t.month
  for _, e in ipairs(evs) do
    if not (ctx.cfg.bdaySep == true and e.bd) and e.k // 100 == ym then
      local dn = e.k % 100
      mask[dn] = mask[dn] or {}
      mask[dn][e.ci] = true
    end
  end
  local gridLeft = 16
  local gridWidth = W - 2 * gridLeft
  local colW = gridWidth // 7
  local headerY = topY + 6
  for c = 0, 6 do
    draw.text(gridLeft + c * colW + colW // 2, headerY, (en and WDS_EN or WDS_DE)[c + 1], "normal", color.BLACK, "center")
  end
  local gridTop = headerY + 16
  local bandH = cp and 44 or 54
  local bandGap = cp and 4 or 6
  local first = time.date(time.mktime({ year = t.year, month = t.month, day = 1 }))
  local fw = isoWd(first.wday)
  local nDays = daysIn(t.year, t.month)
  local rows = (fw - 1 + nDays + 6) // 7
  local curRow = (fw - 1 + t.day - 1) // 7
  for row = 0, rows - 1 do
    local by = gridTop + row * (bandH + bandGap)
    local isCur = row == curRow
    if isCur then
      draw.rect(gridLeft, by, gridWidth, bandH, color.ACCENT, true, 14)
    elseif cards then
      card(gridLeft, by, gridWidth, bandH, color.ACCENT, 14)
    else
      thick(gridLeft, by, gridWidth, bandH, 14, color.BLACK)
    end
    local cy = by + bandH // 2
    local tc = isCur and color.ACCENT_INK or color.BLACK
    for col = 0, 6 do
      local day = row * 7 + col - (fw - 1) + 1
      if day >= 1 and day <= nDays then
        local cx = gridLeft + col * colW + colW // 2
        if day == t.day then
          draw.circle(cx, cy - 6, 15, color.WHITE, true)
          draw.text(cx, cy - 2, tostring(day), "normal", color.BLACK, "center")
        else
          draw.text(cx, cy - 2, tostring(day), "normal", tc, "center")
        end
        local m = mask[day]
        if m then
          local n = 0
          for b = 1, 4 do if m[b] then n = n + 1 end end
          local dx = cx - (n - 1) * 9 // 2
          for b = 1, 4 do
            if m[b] then
              draw.circle(dx, cy + 16, 4, tc, true)
              draw.circle(dx, cy + 16, 3, DOTS[b], true)
              dx = dx + 9
            end
          end
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Vollbild-Seiten
-- ---------------------------------------------------------------------------

local function styleOf(cfg, key)
  local s = cfg[key]
  if s == "cards" or s == "compact" then return s end
  return "flat"
end

function on_draw(ctx, page)
  local en = en_(ctx)
  local top = draw.top
  if not configured(ctx.cfg) and not ctx.sample then
    stateNotice("setup", en and "No calendar configured." or "Kein Kalender eingerichtet.",
      en and "Studio -> Store -> Calendar" or "Studio -> Store -> Kalender")
    return
  end
  local stt = ctx.data.get("st")
  if stt == nil and not ctx.sample then
    stateNotice("loading", en and "Loading events ..." or "Lade Termine ...")
    return
  end
  local now = time.now()
  if now == nil then
    stateNotice("loading", en and "Waiting for the clock ..." or "Warte auf die Uhrzeit ...")
    return
  end
  local t = time.date(now)
  local lo, hi
  if page == 2 then
    lo = time.mktime({ year = t.year, month = t.month, day = t.day - (isoWd(t.wday) - 1) })
    hi = time.mktime({ year = t.year, month = t.month, day = t.day - (isoWd(t.wday) - 1) + 7 })
  elseif page == 3 then
    lo = time.mktime({ year = t.year, month = t.month, day = 1 })
    hi = time.mktime({ year = t.year, month = t.month + 1, day = 1 })
  else
    lo = time.mktime({ year = t.year, month = t.month, day = t.day })
    hi = time.mktime({ year = t.year, month = t.month, day = t.day + 1 })
  end
  local evs = loadEvents(ctx, now, lo, hi, MAX_EVENTS)
  if stt == "e" and #evs == 0 and not ctx.sample then
    stateNotice("error", en and "Calendar not reachable." or "Kalender nicht erreichbar.",
      en and "Check the calendar links in the settings" or "Links in den Einstellungen prüfen")
    return
  end
  if page == 2 then
    weekPage(ctx, evs, styleOf(ctx.cfg, "styleWeek"), en, t, top, now)
  elseif page == 3 then
    monthPage(ctx, evs, styleOf(ctx.cfg, "styleMonth"), en, t, top)
  else
    dayPage(ctx, evs, styleOf(ctx.cfg, "styleDay"), en, t, top)
  end
end

-- ---------------------------------------------------------------------------
-- Widget "Naechste Termine"
-- ---------------------------------------------------------------------------

-- Schriftstufen wie dashFontTier() der eingebauten App: "klein" macht aus der 9pt-Schrift die 7pt-Schrift, "gross" aus der 7pt-
-- Schrift die 9pt-Schrift; alles andere bleibt.
local function tier(base, shift)
  if base == "normal" and (shift or 0) < 0 then return "small" end
  if base == "small" and (shift or 0) > 0 then return "normal" end
  return base
end

-- Mini-Uhr und Ortsmarke (Zeit- und Ortzeile) wie dashGlyphClockSmall / dashGlyphLocationPin
local function glyphClock(cx, cy)
  draw.circle(cx, cy, 5, color.BLACK, false)
  draw.line(cx, cy - 3, cx, cy - 1, color.BLACK)
  draw.line(cx, cy, cx + 2, cy, color.BLACK)
end

local function glyphPin(cx, cy)
  draw.circle(cx, cy - 2, 4, color.BLACK, true)
  draw.triangle(cx - 3, cy, cx + 3, cy, cx, cy + 6, color.BLACK, true)
  draw.circle(cx, cy - 2, 1, color.WHITE, true)
end

local function dateText(e, en)
  local d, m = e.k % 100, (e.k // 100) % 100
  return string.format("%s %02d.%02d.", (en and WDS_EN or WDS_DE)[isoWd(e.wd)], d, m)
end

function on_widget(ctx, box)
  local en = en_(ctx)
  local cfg = ctx.cfg
  local now = time.now()
  local c24 = ctx.clock24
  local list = {}
  if now ~= nil then
    for _, e in ipairs(loadEvents(ctx, now, now, now + 400 * 86400, 24)) do
      if e.e >= now then list[#list + 1] = e end
    end
  end
  local x, top = box.x, box.y
  local maxY = box.y + box.h - 4
  local shift = box.font or 0
  local shown = 0
  if cfg.wCompact == true then
    local y = top + 14
    for _, e in ipairs(list) do
      if y > maxY then break end
      draw.circle(x + 12, y - 4, 4, e.c, true)
      local prefix = dateText(e, en)
      if not e.ad then prefix = prefix .. " " .. fmtTime(e.hh, e.mi, c24) end
      local pf = tier("small", shift)
      draw.text(x + 22, y, prefix, pf, color.ACCENT_TEXT, "left")
      local tX = x + 90
      local pw = draw.measure(prefix, pf)
      if x + 22 + pw + 8 > tX then tX = x + 22 + pw + 8 end
      if box.w >= 300 then
        local mw = x + box.w - tX - 6
        if mw < 20 then mw = 20 end
        draw.text(tX, y, fit(e.title, mw, "small"), "small", color.BLACK, "left")
        y = y + 18
      else
        y = y + 14
        if y <= maxY then
          draw.text(x + 22, y, fit(e.title, box.w - 30, "small"), "small", color.BLACK, "left")
          y = y + 18
        end
      end
      shown = shown + 1
    end
    if shown == 0 then
      draw.text(x + 12, top + 16, en and "No data yet" or "Noch keine Daten", "small", color.BLACK, "left")
    end
    return
  end
  local y = top + 4
  local i = 1
  while i <= #list and y + 56 <= maxY do
    local e0 = list[i]
    local dayK = e0.k
    local bt = y
    draw.text(x + 34, bt + 12, (en and WDS_EN or WDS_DE)[isoWd(e0.wd)], "small", color.BLACK, "center")
    draw.text(x + 34, bt + 40, tostring(dayK % 100), "large", color.BLACK, "center")
    draw.text(x + 34, bt + 55, (en and MON_S_EN or MON_S_DE)[(dayK // 100) % 100], "small", color.BLACK, "center")
    local tX = x + 78
    local ey = bt + 14
    local lineC = e0.c
    local tf = tier("normal", shift)
    while i <= #list and list[i].k == dayK and ey <= maxY do
      local e = list[i]
      draw.text(tX, ey, fit(e.title, x + box.w - tX - 6, tf), tf, color.BLACK, "left")
      ey = ey + 8
      if cfg.wTime == true and not e.ad and ey + 12 <= maxY then
        glyphClock(tX + 6, ey + 5)
        draw.text(tX + 16, ey + 9, fmtTime(e.hh, e.mi, c24) .. " - " .. fmtTime(e.ehh, e.emi, c24), "small", color.BLACK, "left")
        ey = ey + 17
      end
      if cfg.wLocation == true and e.loc ~= "" and ey + 12 <= maxY then
        glyphPin(tX + 6, ey + 5)
        draw.text(tX + 16, ey + 9, fit(e.loc, x + box.w - tX - 22, "small"), "small", color.BLACK, "left")
        ey = ey + 17
      end
      ey = ey + 12
      shown = shown + 1
      i = i + 1
    end
    while i <= #list and list[i].k == dayK do i = i + 1 end
    local bb = ey - 8
    if bb < bt + 58 then bb = bt + 58 end
    draw.rect(x + 66, bt + 2, 3, bb - bt - 2, lineC, true)
    y = bb + 12
  end
  if shown == 0 then
    local cy = top + 18
    draw.line(x + 14, cy - 2, x + 18, cy + 3, color.ACCENT)
    draw.line(x + 18, cy + 3, x + 26, cy - 6, color.ACCENT)
    draw.line(x + 14, cy - 1, x + 18, cy + 4, color.ACCENT)
    draw.line(x + 18, cy + 4, x + 26, cy - 5, color.ACCENT)
    draw.text(x + 34, cy + 3, fit(en and "No upcoming events" or "Keine anstehenden Termine", box.w - 44, "small"), "small", color.BLACK, "left")
  end
end
