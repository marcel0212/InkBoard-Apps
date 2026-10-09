-- Muellabfuhr (Skript-Variante der eingebauten Muellabfuhr-App): Abfuhrtermine aus einem ICS-Kalenderlink des
-- Entsorgers ODER per Adresse ueber die AbfallNavi-Schnittstelle (regioit.de, feste Liste von Kommunen).
-- Drei Stile (Bento = Tonnen-Kacheln, Slate = Headline + Liste, Nano = Mini-Monatskalender), Dashboard-Widget.
-- Skript-API Level 9 (http.request mit maxBytes). Siehe docs/SKRIPT_APPS.md.
--
-- Ablauf: on_fetch holt die Termine und legt die naechsten 16 sortiert in ctx.data ab ("ev": eine Zeile je Termin
-- "TTTTTT<Typ><Text>", TTTTTT = Tage seit 1970 sechsstellig, Typ R/P/G/B/S). "st" = "ok" oder ein Fehlercode,
-- "hid" merkt die aufgeloeste AbfallNavi-Hausnummer (spart beim naechsten Lauf drei Abrufe).
-- Antworten koennen groesser als 24 KB sein; es wird mit 60 KB abgerufen und mit Textmustern gelesen.

local MAX_EVENTS = 16
local BIG = 60 * 1024

--#include text
--#include ui
--#include dates

local function en_(ctx) return ctx.lang == "en" end

-- Dienste mit gemeinsamer Domain (abfallapp.regioit.de/abfall-app-<code>), alle anderen <code>-abfallapp.regioit.de
local SHARED = { unna = true, frankenthal = true, awvlippe = true, kranenburg = true }

-- Tonnenarten: Farbe, Namen
local KIND = {
  R = { color.BLACK, "Restmüll", "General waste" },
  P = { color.BLUE, "Papiertonne", "Paper" },
  G = { color.YELLOW, "Gelbe Tonne", "Recycling" },
  B = { color.GREEN, "Biotonne", "Bio waste" },
  S = { color.RED, "Sonstige Abholung", "Other collection" },
}

-- Tonnenart aus dem Freitext (ICS-SUMMARY bzw. AbfallNavi-Fraktion)
local function kindOf(label)
  local l = label:lower()
  if l:find("bio", 1, true) then return "B" end
  if l:find("papier", 1, true) or l:find("papptonne", 1, true) then return "P" end
  if l:find("gelb", 1, true) or l:find("wertstoff", 1, true) or l:find("verpackung", 1, true) or l:find("lvp", 1, true) or l:find("dsd", 1, true) then return "G" end
  if l:find("rest", 1, true) or l:find("hausmüll", 1, true) or l:find("hausmuell", 1, true) then return "R" end
  return "S"
end

local function kindName(k, en) return en and KIND[k][3] or KIND[k][2] end

-- ---------------------------------------------------------------------------
-- Datum
-- ---------------------------------------------------------------------------

-- heutiger Tag als "Tage seit 1970" oder nil (Uhr nicht synchron)
local function todayDays()
  local t = time.today()
  if t == nil then return nil end
  local y, m, d = t:match("(%d+)-(%d+)-(%d+)")
  if y == nil then return nil end
  return dfc(tonumber(y), tonumber(m), tonumber(d))
end

-- Abweichung der Lokalzeit von UTC in Sekunden (auf Viertelstunden gerundet), fuer ICS-Zeiten mit "Z"
local function utcOffset()
  local t = time.localtime()
  if t == nil then return 0 end
  local localSecs = dfc(t.year, t.month, t.day) * 86400 + t.hour * 3600 + t.min * 60 + t.sec
  return ((localSecs - time.now() + 450) // 900) * 900
end

local WD_DE = { "Mo", "Di", "Mi", "Do", "Fr", "Sa", "So" }
local WD_EN = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }

-- "Mi 19.08."
local function dayText(day, en)
  local _, m, d = cfd(day)
  local wd = ((day + 3) % 7) + 1 -- 1970-01-01 war ein Donnerstag; 1 = Montag
  return string.format("%s %02d.%02d.", (en and WD_EN or WD_DE)[wd], d, m)
end

-- "heute" / "morgen" / "in 5 Tagen"
local function relText(day, today, en)
  local n = day - today
  if n <= 0 then return en and "today" or "heute" end
  if n == 1 then return en and "tomorrow" or "morgen" end
  return string.format(en and "in %d days" or "in %d Tagen", n)
end

-- ---------------------------------------------------------------------------
-- Abruf: ICS-Kalender
-- ---------------------------------------------------------------------------

-- Liest VEVENT-Bloecke (Zeilenfaltung, ganztaegig oder mit Uhrzeit) und gibt Eintraege "TTTTTT<Typ><Text>" zurueck.
local function parseIcs(body, fromDay)
  local out, pos, off = {}, 1, nil
  while true do
    local a = body:find("BEGIN:VEVENT", pos, true)
    if a == nil then break end
    local b = body:find("END:VEVENT", a, true)
    if b == nil then break end -- abgeschnittener Rest
    pos = b + 10
    local blk = body:sub(a, b)
    if blk:find("\n[ \t]") then blk = blk:gsub("\r?\n[ \t]", "") end
    local sum = blk:match("\nSUMMARY[^:\r\n]*:([^\r\n]*)")
    local ds = blk:match("\nDTSTART([^\r\n]*)")
    if sum ~= nil and ds ~= nil then
      local y, m, d, rest = ds:match(":(%d%d%d%d)(%d%d)(%d%d)(.*)")
      if y ~= nil then
        local day = dfc(tonumber(y), tonumber(m), tonumber(d))
        local hh, mi, ss = rest:match("^T(%d%d)(%d%d)(%d%d)Z")
        if hh ~= nil then -- UTC-Zeit: in Lokalzeit umrechnen (Abfuhr um 22:00 UTC = naechster Morgen)
          off = off or utcOffset()
          local secs = day * 86400 + tonumber(hh) * 3600 + tonumber(mi) * 60 + tonumber(ss) + off
          day = secs // 86400
        end
        if day >= fromDay then
          sum = sum:gsub("\\([,;nN\\])", function(c) if c == "n" or c == "N" then return " " end return c end)
          sum = clean(sum, 27)
          if sum ~= "" then out[#out + 1] = string.format("%06d%s%s", day, kindOf(sum), sum) end
        end
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Abruf: AbfallNavi (regioit.de)
-- ---------------------------------------------------------------------------

-- erste Zahl hinter einem JSON-Schluessel in einem kleinen Objekttext
local function numField(chunk, key)
  return chunk:match('"' .. key .. '"%s*:%s*(%d+)')
end

local function strField(chunk, key)
  local raw = chunk:match('"' .. key .. '"%s*:%s*"(.-)"')
  if raw == nil then return nil end
  if raw:find("\\", 1, true) then
    local d = json.decode('{"t":"' .. raw .. '"}')
    if type(d) == "table" and type(d.t) == "string" then return d.t end
  end
  return raw
end

-- Alle flachen Objekte {...} der Antwort: f(chunk) wird fuer jedes aufgerufen, true beendet die Suche.
local function eachFlat(body, f)
  for chunk in body:gmatch("{[^{}]*}") do
    if f(chunk) then return end
  end
end

-- Objekte der obersten Listenebene (auch mit verschachtelten Objekten wie "bezirk")
local function eachTop(body, f)
  local depth, start, pos = 0, nil, 1
  while true do
    local i = body:find("[{}]", pos)
    if i == nil then return end
    if body:byte(i) == 123 then
      if depth == 0 then start = i end
      depth = depth + 1
    else
      depth = depth - 1
      if depth == 0 and start ~= nil then
        if f(body:sub(start, i)) then return end
        start = nil
      end
      if depth < 0 then depth = 0 end
    end
    pos = i + 1
  end
end

local function lower(s) return tostring(s or ""):lower() end

local function baseUrl(code)
  if SHARED[code] then return "https://abfallapp.regioit.de/abfall-app-" .. code .. "/rest" end
  return "https://" .. code .. "-abfallapp.regioit.de/abfall-app-" .. code .. "/rest"
end

-- Ort -> Strasse -> Hausnummer aufloesen. Gibt die Hausnummern-ID oder nil, Fehlercode zurueck.
local function resolveAddress(ctx, base)
  local street = lower(ctx.cfg.street)
  local houseNo = tostring(ctx.cfg.houseNo or "")
  local want = lower(ctx.cfg.city)

  local body = http.get(base .. "/orte")
  if body == nil then return nil, "net" end
  local ortId, firstOrt
  eachFlat(body, function(chunk)
    local id = numField(chunk, "id")
    if id == nil then return false end
    firstOrt = firstOrt or id
    if want ~= "" and lower(strField(chunk, "name")):find(want, 1, true) then ortId = id; return true end
    return false
  end)
  ortId = ortId or firstOrt
  if ortId == nil then return nil, "orte" end

  time.sleep(300)
  body = http.get(base .. "/orte/" .. ortId .. "/strassen", BIG)
  if body == nil then return nil, "net" end
  local strasseId
  eachFlat(body, function(chunk)
    local name = strField(chunk, "name")
    if name ~= nil and lower(name):find(street, 1, true) then strasseId = numField(chunk, "id"); return strasseId ~= nil end
    return false
  end)
  if strasseId == nil then return nil, "street" end

  -- Hausnummer: exakter Treffer, sonst der erste Eintrag; ohne Liste gilt die Strassen-ID
  local hid = strasseId
  time.sleep(300)
  body = http.get(base .. "/strassen/" .. strasseId, BIG)
  if body ~= nil then
    local first
    eachFlat(body, function(chunk)
      local nr, id = strField(chunk, "nr"), numField(chunk, "id")
      if nr == nil or id == nil then return false end
      first = first or id
      if houseNo ~= "" and nr == houseNo then first = id; return true end
      return false
    end)
    if first ~= nil then hid = first end
  end
  return hid
end

local function fetchAuto(ctx, today)
  local code = tostring(ctx.cfg.service or "")
  local street = tostring(ctx.cfg.street or "")
  if code == "" or street == "" then return nil, "cfg" end
  local base = baseUrl(code)
  local sig = code .. "|" .. street .. "|" .. tostring(ctx.cfg.houseNo or "") .. "|" .. tostring(ctx.cfg.city or "") .. "|"
  local hid
  local cached = ctx.data.get("hid")
  if type(cached) == "string" and cached:sub(1, #sig) == sig then hid = cached:sub(#sig + 1) end
  if hid == nil or hid == "" then
    local why
    hid, why = resolveAddress(ctx, base)
    if hid == nil then return nil, why end
    ctx.data.set("hid", sig .. hid)
    time.sleep(300)
  end

  -- Fraktionen (ID -> Tonnenname)
  local names = {}
  local fb = http.get(base .. "/hausnummern/" .. hid .. "/fraktionen", BIG)
  if fb ~= nil then
    eachFlat(fb, function(chunk)
      local id, name = numField(chunk, "id"), strField(chunk, "name")
      if id ~= nil and name ~= nil then names[id] = name end
      return false
    end)
  end
  time.sleep(300)
  local tb = http.get(base .. "/hausnummern/" .. hid .. "/termine", BIG)
  if tb == nil then
    ctx.data.set("hid", nil)
    return nil, "net"
  end
  local out = {}
  eachTop(tb, function(chunk)
    local y, m, d = chunk:match('"datum"%s*:%s*"(%d%d%d%d)%-(%d%d)%-(%d%d)')
    if y == nil then return false end
    local day = dfc(tonumber(y), tonumber(m), tonumber(d))
    if day < today - 1 then return false end
    local fid = numField(chunk, "fraktionId")
    local name = fid and names[fid] or nil
    if name == nil or name == "" then name = strField(chunk, "fraktion") or strField(chunk, "art") end
    if name == nil or name == "" then name = "Abholung" end
    name = clean(name, 27)
    out[#out + 1] = string.format("%06d%s%s", day, kindOf(name), name)
    return false
  end)
  return out
end

local function fetchIcs(ctx, today)
  local url = ctx.cfg.icsUrl
  if type(url) ~= "string" or url == "" then return nil, "cfg" end
  local r, err = http.request({ url = url, maxBytes = BIG })
  if r == nil then
    log("Muellabfuhr: " .. tostring(err))
    return nil, "net"
  end
  if r.status ~= 200 then
    log("Muellabfuhr: ICS-Abruf HTTP " .. tostring(r.status))
    return nil, "http" .. tostring(r.status)
  end
  return parseIcs(r.body, today - 1)
end

function on_fetch(ctx)
  local today = todayDays()
  if today == nil then return false end
  local list, why
  if ctx.cfg.mode == "auto" then list, why = fetchAuto(ctx, today)
  else list, why = fetchIcs(ctx, today) end
  if list == nil then
    if why == "net" then return false end -- vorruebergehend: nach 5 Minuten erneut
    ctx.data.set("st", "e:" .. why)
    return
  end
  if #list == 0 then
    ctx.data.set("st", "e:none")
    return
  end
  table.sort(list)
  local keep = {}
  for i = 1, math.min(#list, MAX_EVENTS) do keep[i] = list[i] end
  ctx.data.set("ev", table.concat(keep, "\n"))
  ctx.data.set("st", "ok")
end

-- ---------------------------------------------------------------------------
-- Daten lesen
-- ---------------------------------------------------------------------------

-- Liste {day, kind, label} der Termine ab heute
local function loadEvents(ctx, today)
  local out = {}
  if ctx.sample and today then -- Beispieldaten fuer die Widget-Vorschau im Dashboard-Editor
    local demo = { { 2, "R" }, { 3, "B" }, { 9, "P" }, { 10, "G" }, { 16, "R" }, { 17, "B" } }
    for _, e in ipairs(demo) do out[#out + 1] = { day = today + e[1], kind = e[2], label = KIND[e[2]][2] } end
    return out
  end
  local raw = ctx.data.get("ev")
  if type(raw) ~= "string" or raw == "" or today == nil then return out end
  for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
    local day, kind, label = line:match("^(%d+)(%a)(.*)$")
    if day ~= nil and KIND[kind] ~= nil and tonumber(day) >= today then
      out[#out + 1] = { day = tonumber(day), kind = kind, label = label }
    end
  end
  return out
end

-- Anzeigename: bei "Sonstige" der Originaltext des Entsorgers
local function eventName(ev, en)
  if ev.kind == "S" and ev.label ~= "" then return ev.label end
  return kindName(ev.kind, en)
end

local function configured(ctx)
  if ctx.cfg.mode == "auto" then
    return type(ctx.cfg.service) == "string" and ctx.cfg.service ~= "" and type(ctx.cfg.street) == "string" and ctx.cfg.street ~= ""
  end
  return type(ctx.cfg.icsUrl) == "string" and ctx.cfg.icsUrl ~= ""
end

local function emptyState(ctx, events, today)
  local en = en_(ctx)
  local st = ctx.data.get("st")
  if not configured(ctx) then
    notice("gear", en and "Not set up yet." or "Noch nicht eingerichtet.",
      en and "Store -> Waste collection -> Settings" or "Store -> Müllabfuhr -> Einstellungen")
    return true
  end
  if today == nil then
    notice("clock", en and "Waiting for the clock ..." or "Warte auf die Uhrzeit ...")
    return true
  end
  if st == nil then
    notice("clock", en and "Loading ..." or "Wird geladen ...")
    return true
  end
  if st ~= "ok" and #events == 0 then
    local code = st:sub(3)
    local l1, l2 = en and "Fetch failed." or "Abruf fehlgeschlagen.", nil
    if code == "street" then
      l1 = en and "Street not found." or "Straße nicht gefunden."
      l2 = en and "Check the spelling in the Store" or "Schreibweise im Store prüfen"
    elseif code == "orte" then
      l1 = en and "Provider returned no places." or "Entsorger liefert keine Orte."
    elseif code == "none" then
      l1 = en and "No upcoming dates found." or "Keine Termine gefunden."
    elseif code:sub(1, 4) == "http" then
      l2 = (en and "HTTP error " or "HTTP-Fehler ") .. code:sub(5)
    end
    notice("warning", l1, l2)
    return true
  end
  if #events == 0 then
    notice("search", en and "No upcoming dates." or "Keine anstehenden Termine.")
    return true
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Zeichnen
-- ---------------------------------------------------------------------------

-- Tonnen-Symbol: farbiges Quadrat mit weissem Deckel und Korpus
local function binIcon(x, y, size, kind)
  draw.rect(x, y, size, size, KIND[kind][1], true, size // 6)
  local lidW, lidH = (size * 6) // 10, math.max(2, size // 10)
  draw.rect(x + (size - lidW) // 2, y + (size * 22) // 100, lidW, lidH, color.WHITE, true, 1)
  local bodyW, bodyH = (size * 48) // 100, (size * 42) // 100
  draw.rect(x + (size - bodyW) // 2, y + (size * 38) // 100, bodyW, bodyH, color.WHITE, true, bodyW // 8)
end

local function nextOfKind(events, kind)
  for _, e in ipairs(events) do
    if e.kind == kind then return e end
  end
  return nil
end

-- "Bento": vier Tonnen-Kacheln, die mit dem naechsten Termin ist hervorgehoben
local function drawCards(ctx, events, today)
  local en = en_(ctx)
  local order = { "R", "B", "P", "G" }
  local margin, gap = 20, 12
  local areaTop = draw.top + 10
  local areaH = draw.height - 16 - areaTop
  local tileW = (draw.width - 2 * margin - 3 * gap) // 4
  local tileH = math.min(areaH, 290)
  local hot, hotDay = nil, nil
  local nexts = {}
  for i, k in ipairs(order) do
    nexts[i] = nextOfKind(events, k)
    if nexts[i] and (hotDay == nil or nexts[i].day < hotDay) then hot, hotDay = i, nexts[i].day end
  end
  for i, k in ipairs(order) do
    local tx = margin + (i - 1) * (tileW + gap)
    local ty = areaTop
    local col = KIND[k][1]
    local isHot = (i == hot)
    draw.rect(tx, ty, tileW, tileH, isHot and col or color.BLACK, false, 8)
    local iconY = ty + 34
    if isHot then
      draw.rect(tx, ty, tileW, 26, col, true, 8)
      draw.rect(tx, ty + 14, tileW, 12, col, true)
      draw.text(tx + tileW // 2, ty + 18, en and "NEXT" or "NÄCHSTE", "small", col == color.YELLOW and color.BLACK or color.WHITE, "center")
      iconY = ty + 52
    end
    local iconSize = 80
    binIcon(tx + (tileW - iconSize) // 2, iconY, iconSize, k)
    draw.text(tx + tileW // 2, ty + tileH - 56, fit(kindName(k, en), tileW - 12, "normal"), "normal", color.BLACK, "center")
    local e = nexts[i]
    if e then
      draw.text(tx + tileW // 2, ty + tileH - 32, dayText(e.day, en), "small", color.BLACK, "center")
      draw.text(tx + tileW // 2, ty + tileH - 12, relText(e.day, today, en), "small", col == color.YELLOW and color.BLACK or col, "center")
    else
      draw.text(tx + tileW // 2, ty + tileH - 22, en and "no dates" or "keine Termine", "small", color.RED, "center")
    end
  end
end

-- "Slate": grosse Ueberschrift fuer die naechste Abfuhr, darunter die folgenden Termine
local function drawFlat(ctx, events, today)
  local en = en_(ctx)
  local margin = 24
  local W = draw.width
  local y = draw.top + 10
  local nxt = events[1]
  local col = KIND[nxt.kind][1]
  draw.text(margin, y + 30, (en and "Next collection: " or "Nächste Abfuhr: ") .. eventName(nxt, en), "large", color.BLACK, "left")
  draw.text(margin, y + 56, relText(nxt.day, today, en) .. " - " .. dayText(nxt.day, en), "normal", color.BLACK, "left")
  local barY = y + 70
  draw.rect(margin, barY, W - 2 * margin, 3, col, true)
  local ly = barY + 34
  local rowH = 32
  local shown = math.min(#events - 1, 6, (draw.height - 16 - ly) // rowH + 1)
  for i = 1, shown do
    local e = events[i + 1]
    draw.rect(margin, ly - 12, 12, 12, KIND[e.kind][1], true)
    draw.text(margin + 22, ly, fit(dayText(e.day, en) .. " - " .. eventName(e, en), W - 2 * margin - 180, "normal"), "normal", color.BLACK, "left")
    draw.text(W - margin, ly, relText(e.day, today, en), "normal", color.BLACK, "right")
    if i < shown then draw.line(margin, ly + 10, W - margin, ly + 10, color.BLACK) end
    ly = ly + rowH
  end
end

-- "Nano": rollende 4-Wochen-Ansicht ab dem Montag der aktuellen Woche
local function drawCompact(ctx, events, today)
  local en = en_(ctx)
  local margin = 24
  local contentW = draw.width - 2 * margin
  local y = draw.top + 8
  local cellW = contentW // 7
  for i = 1, 7 do
    draw.text(margin + (i - 1) * cellW + cellW // 2, y + 12, (en and WD_EN or WD_DE)[i], "small", color.BLACK, "center")
  end
  local iso = (today + 3) % 7
  local gridStart = today - iso
  local rows = 4
  local gridY0 = y + 24
  local cellH = math.min(72, (draw.height - 16 - 50 - gridY0) // rows)
  local byDay = {}
  for _, e in ipairs(events) do
    if byDay[e.day] == nil then byDay[e.day] = e end
  end
  for r = 0, rows - 1 do
    for c = 0, 6 do
      local day = gridStart + r * 7 + c
      local gx, gy = margin + c * cellW, gridY0 + r * cellH
      if day == today then draw.rect(gx + 2, gy + 2, cellW - 4, cellH - 4, color.BLACK, false, 4) end
      local _, _, d = cfd(day)
      draw.text(gx + cellW // 2, gy + 20, tostring(d), "normal", color.BLACK, "center")
      local e = byDay[day]
      if e then draw.circle(gx + cellW // 2, gy + 34, 5, KIND[e.kind][1], true) end
    end
  end
  local nxt = events[1]
  local sy = math.min(draw.height - 18, gridY0 + rows * cellH + 34)
  draw.circle(margin + 6, sy - 5, 5, KIND[nxt.kind][1], true)
  draw.text(margin + 20, sy, (en and "Next: " or "Nächste: ") .. eventName(nxt, en) .. ", " .. relText(nxt.day, today, en), "normal", color.BLACK, "left")
end

function on_draw(ctx, page)
  draw.clear(color.WHITE)
  local today = todayDays()
  local events = loadEvents(ctx, today)
  if emptyState(ctx, events, today) then return end
  local style = ctx.cfg.style
  if style == "cards" then drawCards(ctx, events, today)
  elseif style == "compact" then drawCompact(ctx, events, today)
  else drawFlat(ctx, events, today) end
end

-- ---------------------------------------------------------------------------
-- Widget: Tonnen-Symbol, Name und Datum; Tonnenarten und "weitere Termine" stellt der Nutzer ein
-- ---------------------------------------------------------------------------

function on_widget(ctx, box)
  local en = en_(ctx)
  local today = todayDays()
  local events = loadEvents(ctx, today)
  if #events == 0 then
    local msg = ctx.data.get("ev") == nil and (en and "No data yet" or "Noch keine Daten") or (en and "No upcoming dates" or "Keine anstehenden Termine")
    draw.text(box.x + 12, box.y + 16, msg, "small", color.BLACK, "left")
    return
  end
  local allow = { R = ctx.cfg.wRest ~= false, B = ctx.cfg.wBio ~= false, P = ctx.cfg.wPaper ~= false, G = ctx.cfg.wYellow ~= false, S = true }
  if not (allow.R or allow.B or allow.P or allow.G) then allow = { R = true, B = true, P = true, G = true, S = true } end
  local font = (box.font or 0) < 0 and "small" or "normal"
  local tileH = 44
  local cols = box.w >= 300 and 2 or 1
  local tileW = (box.w - 16) // cols
  local maxY = box.y + box.h - 4
  local topY = box.y - 2
  local maxTiles = ((maxY - topY) // tileH) * cols
  if ctx.cfg.wMore ~= true then maxTiles = 1 end
  local shown = 0
  for _, e in ipairs(events) do
    if shown >= maxTiles then break end
    if allow[e.kind] then
      local col, row = shown % cols, shown // cols
      local tx = box.x + 10 + col * tileW
      local cy = topY + row * tileH + tileH // 2 + 4
      binIcon(tx + 1, cy - 14, 28, e.kind)
      draw.text(tx + 38, cy - 1, fit(eventName(e, en), tileW - 44, font), font, color.BLACK, "left")
      draw.text(tx + 38, cy + 15, dayText(e.day, en), "small", color.BLACK, "left")
      shown = shown + 1
    end
  end
  if shown == 0 then draw.text(box.x + 12, box.y + 16, en and "No upcoming dates" or "Keine anstehenden Termine", "small", color.BLACK, "left") end
end
