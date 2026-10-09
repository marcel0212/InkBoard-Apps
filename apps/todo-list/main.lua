-- Aufgaben (Skript-Variante der eingebauten Todo-App): Todoist und CalDAV (iCloud-Erinnerungen,
-- Nextcloud, andere Server), bis zu drei Quellen, drei Stile (Bento/Slate/Nano), Dashboard-Widget.
-- Skript-API Level 6 (http.request, permissions.netFrom). Siehe docs/SKRIPT_APPS.md.
--
-- Ablauf: on_fetch holt je Quelle die Aufgaben und legt sie kompakt in ctx.data ab (je Quelle zwei
-- Textbloecke "d<n>a"/"d<n>b", Zeilen = Aufgaben, Felder durch Tab getrennt). on_draw/on_widget lesen
-- sie, mischen und sortieren (offen mit Datum zuerst, dann ohne Datum, Erledigte zuletzt).
-- Pro on_fetch sind nur 6 Netzabrufe erlaubt: ist eine CalDAV-Liste einmal gefunden, merkt sich die App
-- ihre Adresse ("u<n>") und braucht danach nur noch EINEN Abruf je Quelle. Quellen, die in einem Lauf
-- nicht mehr drankommen, werden beim naechsten Lauf zuerst bedient (Rotation "rot").

local SLOTS = { "a", "b", "c" }
local MAX_CALLS = 6
local MAX_PER_SLOT = 14
local CHUNK_BYTES = 980
local ICLOUD = "https://caldav.icloud.com"

local MONTHS_DE = { "Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember" }
local MONTHS_EN = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" }
local WDAY_DE = { "So", "Mo", "Di", "Mi", "Do", "Fr", "Sa" }
local WDAY_EN = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }

-- ---------------------------------------------------------------------------
-- Allgemeine Helfer
-- ---------------------------------------------------------------------------

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Auf n Zeichen (UTF-8) kuerzen.
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

-- Steuerzeichen (Tab/Zeilenumbruch trennen unsere Felder) raus, auf n Zeichen kuerzen.
local function clean(s, n)
  s = s:gsub("%c", " ")
  return cut(trim(s), n)
end

local function colorOf(name)
  if name == "green" then return color.GREEN end
  if name == "yellow" then return color.YELLOW end
  if name == "red" then return color.RED end
  return color.BLUE
end

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

-- Abweichung der Geraetezeit von UTC in Sekunden (auf Viertelstunden gerundet); 0, solange die Uhr nicht laeuft.
local function utcOffset()
  local lt = time.localtime()
  if lt == nil then return 0 end
  local localSecs = dfc(lt.year, lt.month, lt.day) * 86400 + lt.hour * 3600 + lt.min * 60 + lt.sec
  local off = localSecs - time.now()
  return ((off + 450) // 900) * 900
end

-- Faelligkeit als Text: "JJJJMMTT" (ganztaegig) oder "JJJJMMTThhmm" (mit Uhrzeit), Wandzeit des Geraets.
local function dueString(y, m, d, hh, mm)
  local s = string.format("%04d%02d%02d", y, m, d)
  if hh ~= nil then s = s .. string.format("%02d%02d", hh, mm) end
  return s
end

-- Tag als Zahl JJJJMMTT, "hat Uhrzeit" und Uhrzeit als hhmm. Bewusst KEIN kombinierter Schluessel (Datum * 10000 + Uhrzeit): auf dem
-- Geraet ist Lua mit 32-Bit-Ganzzahlen gebaut, 202609181800 laeuft dort ueber (Anzeige "71" / "88:88").
local function dueKey(s)
  if s == nil or #s < 8 then return nil, false, 0 end
  local day = tonumber(s:sub(1, 8))
  if day == nil then return nil, false, 0 end
  local hasTime = #s >= 12
  return day, hasTime, (hasTime and tonumber(s:sub(9, 12)) or 0)
end

-- ---------------------------------------------------------------------------
-- XML (nur das Noetigste fuer CalDAV; Namensraum-Praefixe werden ignoriert)
-- ---------------------------------------------------------------------------

local function esc(name)
  return (name:gsub("%-", "%%-"))
end

-- Inhalt des ersten Tags `name` ab `init`; liefert Inhalt und die Position hinter dem schliessenden Tag.
local function xmlTag(s, name, init)
  local pat = "<[%w_]*:?" .. esc(name) .. "([%s/>])"
  local close = "</[%w_]*:?" .. esc(name) .. ">"
  local a, b, ch = s:find(pat, init or 1)
  if a == nil then return nil end
  local openEnd = b
  if ch ~= ">" then
    local gt = s:find(">", b, true)
    if gt == nil then return nil end
    if s:sub(gt - 1, gt - 1) == "/" then return "", gt + 1 end -- selbstschliessend
    openEnd = gt
  end
  local c, d = s:find(close, openEnd + 1)
  if c == nil then return nil end
  return s:sub(openEnd + 1, c - 1), d + 1
end

local function xmlHas(s, name)
  return s:find("<[%w_]*:?" .. esc(name) .. "[%s/>]") ~= nil
end

local function xmlText(s)
  s = s:gsub("<!%[CDATA%[(.-)%]%]>", "%1")
  s = s:gsub("&#13;", "\r"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&amp;", "&")
  return s
end

local function originOf(url)
  return url:match("^(https?://[^/]+)")
end

local function absUrl(href, origin)
  href = xmlText(trim(href))
  if href:find("^https?://") then return href end
  if href:sub(1, 1) == "/" then return origin .. href end
  return origin .. "/" .. href
end

-- ---------------------------------------------------------------------------
-- VTODO lesen
-- ---------------------------------------------------------------------------

local function icsUnescape(s)
  return (s:gsub("\\(.)", function(c)
    if c == "n" or c == "N" then return "\n" end
    if c == "," or c == ";" or c == "\\" then return c end
    return "\\" .. c
  end))
end

-- VTODO-PRIORITY (1-4 hoch ... 9 niedrig, 0 keine) auf 0 (keine) bis 3 (hoch).
local function icsPriority(p)
  p = tonumber(p) or 0
  if p <= 0 then return 0 end
  if p <= 4 then return 3 end
  if p == 5 then return 2 end
  return 1
end

local function parseIcsDue(f, off)
  if f == nil then return nil end
  local y, m, d = f.val:match("^(%d%d%d%d)(%d%d)(%d%d)")
  if y == nil then return nil end
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  local hh, mi = f.val:match("^%d%d%d%d%d%d%d%dT(%d%d)(%d%d)")
  if hh == nil then return dueString(y, m, d) end
  hh, mi = tonumber(hh), tonumber(mi)
  if f.val:sub(-1) == "Z" then
    local secs = dfc(y, m, d) * 86400 + hh * 3600 + mi * 60 + off
    local days = secs // 86400
    local rem = secs - days * 86400
    y, m, d = cfd(days)
    hh, mi = rem // 3600, (rem % 3600) // 60
  end
  return dueString(y, m, d, hh, mi)
end

-- Ein VTODO-Block (Text zwischen BEGIN:VTODO und END:VTODO) -> Aufgabe oder nil.
local function parseVtodo(ics, off, project, en)
  ics = ics:gsub("\r\n", "\n"):gsub("\r", "\n")
  local a = ics:find("BEGIN:VTODO", 1, true)
  local b = ics:find("END:VTODO", 1, true)
  if a == nil or b == nil then return nil end -- abgeschnittene Antwort: unvollstaendigen Block auslassen
  ics = ics:sub(a, b)
  ics = ics:gsub("\n[ \t]", "")
  ics = ics:gsub("BEGIN:VALARM.-END:VALARM", "")
  local f = {}
  for line in ics:gmatch("[^\n]+") do
    local name, params, val = line:match("^([%w%-]+)([^:]*):(.*)$")
    if name ~= nil then
      name = name:upper()
      if f[name] == nil then f[name] = { params = params, val = val } end
    end
  end
  local summary = f.SUMMARY and clean(icsUnescape(f.SUMMARY.val), 64) or ""
  if summary == "" then summary = en and "(Untitled)" or "(Ohne Titel)" end
  local desc = f.DESCRIPTION and icsUnescape(f.DESCRIPTION.val) or ""
  desc = clean(desc:match("^[^\n]*"), 80)
  local labels = f.CATEGORIES and clean(icsUnescape(f.CATEGORIES.val):gsub(",", ", "), 40) or ""
  return {
    title = summary,
    done = f.STATUS ~= nil and f.STATUS.val:upper() == "COMPLETED",
    due = parseIcsDue(f.DUE, off),
    prio = icsPriority(f.PRIORITY and f.PRIORITY.val),
    project = project,
    labels = labels,
    desc = desc,
  }
end

-- ---------------------------------------------------------------------------
-- Sortierung (offen mit Datum nach Datum, offen ohne Datum, Erledigte; sonst Reihenfolge der Quelle)
-- ---------------------------------------------------------------------------

local function sortItems(items)
  for i, it in ipairs(items) do
    it.seq = it.seq or i
    local k, _, tm = dueKey(it.due)
    it.key = k
    it.tm = tm or 0
    it.rank = it.done and 2 or (k and 0 or 1)
  end
  table.sort(items, function(x, y)
    if x.rank ~= y.rank then return x.rank < y.rank end
    if x.rank == 0 and x.key ~= y.key then return x.key < y.key end
    if x.rank == 0 and x.tm ~= y.tm then return x.tm < y.tm end
    return x.seq < y.seq
  end)
end

-- ---------------------------------------------------------------------------
-- Abruf
-- ---------------------------------------------------------------------------

local BODY_PRINCIPAL = '<?xml version="1.0" encoding="utf-8"?><D:propfind xmlns:D="DAV:"><D:prop><D:current-user-principal/></D:prop></D:propfind>'
local BODY_HOMESET = '<?xml version="1.0" encoding="utf-8"?><D:propfind xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav"><D:prop><C:calendar-home-set/></D:prop></D:propfind>'
local BODY_LISTS = '<?xml version="1.0" encoding="utf-8"?><D:propfind xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav"><D:prop><D:displayname/><D:resourcetype/><C:supported-calendar-component-set/></D:prop></D:propfind>'
local REPORT_HEAD = '<?xml version="1.0" encoding="utf-8"?><C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav"><D:prop><C:calendar-data><C:comp name="VCALENDAR"><C:comp name="VTODO"><C:prop name="SUMMARY"/><C:prop name="STATUS"/><C:prop name="DUE"/><C:prop name="PRIORITY"/><C:prop name="CATEGORIES"/><C:prop name="DESCRIPTION"/></C:comp></C:comp></C:calendar-data></D:prop><C:filter><C:comp-filter name="VCALENDAR"><C:comp-filter name="VTODO">'
local REPORT_TAIL = '</C:comp-filter></C:comp-filter></C:filter></C:calendar-query>'
local REPORT_NOT_DONE = '<C:prop-filter name="STATUS"><C:text-match negate-condition="yes">COMPLETED</C:text-match></C:prop-filter>'

local calls = 0

-- Netzabruf mit Zaehler (hoechstens MAX_CALLS) und kleiner Pause zwischen den Abrufen.
local lastNetErr = ""   -- Grund des letzten Netzfehlers (Text der Firmware), erscheint hinter "Server nicht erreichbar"
local function req(t)
  if calls >= MAX_CALLS then return nil, "budget" end
  if calls > 0 then time.sleep(250) end
  calls = calls + 1
  local r, err = http.request(t)
  if r == nil then lastNetErr = clean(tostring(err or ""), 60) end
  return r, err
end

-- Fehlerkennung aus dem HTTP-Status.
local function statusErr(r, err)
  if r == nil then return "net" end
  if r.status == 401 or r.status == 403 then return "auth" end
  if r.status == 404 or r.status == 410 then return "notfound" end
  return "srv" .. tostring(r.status)
end

local function dav(method, url, body, depth, user, pass)
  local r, err = req({
    url = url, method = method, body = body, user = user, pass = pass,
    headers = { ["Content-Type"] = "application/xml; charset=utf-8", Depth = depth },
  })
  if r == nil then return nil, (err == "budget") and "budget" or "net" end
  if r.status >= 400 then return nil, statusErr(r) end
  return r.body
end

-- Alle Kalender/Aufgabenlisten des Kontos: Liste {name=, url=, capable=} oder nil, Fehlerkennung.
local function listCalendars(kind, base, user, pass)
  local origin = originOf(base)
  if origin == nil then return nil, "cfg" end
  local home
  if kind == "nextcloud" then
    -- Nextcloud: Heimat der Kalender steht fest (spart zwei Abrufe); klappt das nicht, laeuft die volle Suche.
    home = base:gsub("/+$", "") .. "/calendars/" .. text.url_encode(user) .. "/"
  end
  local listing
  if home ~= nil then
    local body = dav("PROPFIND", home, BODY_LISTS, "1", user, pass)
    if body ~= nil and xmlHas(body, "resourcetype") then listing = body end
  end
  if listing == nil then
    local body, err = dav("PROPFIND", base, BODY_PRINCIPAL, "0", user, pass)
    if body == nil then return nil, err end
    local pin = xmlTag(body, "current-user-principal")
    local ph = pin and xmlTag(pin, "href")
    if ph == nil or trim(ph) == "" then return nil, "nocaldav" end
    body, err = dav("PROPFIND", absUrl(ph, origin), BODY_HOMESET, "0", user, pass)
    if body == nil then return nil, err end
    local hin = xmlTag(body, "calendar-home-set")
    local hh = hin and xmlTag(hin, "href")
    if hh == nil or trim(hh) == "" then return nil, "nocaldav" end
    local homeUrl = absUrl(hh, origin)
    body, err = dav("PROPFIND", homeUrl, BODY_LISTS, "1", user, pass)
    if body == nil then return nil, err end
    listing = body
    home = homeUrl
  end
  local homeOrigin = originOf(home) or origin
  local cals = {}
  local pos = 1
  while true do
    local block, nxt = xmlTag(listing, "response", pos)
    if block == nil then break end
    pos = nxt
    local rt = xmlTag(block, "resourcetype")
    if rt ~= nil and xmlHas(rt, "calendar") then
      local href = xmlTag(block, "href")
      if href ~= nil and trim(href) ~= "" then
        local name = trim(xmlText(xmlTag(block, "displayname") or ""))
        if name == "" then name = trim(href) end
        local hasSet = block:find("supported%-calendar%-component%-set") ~= nil
        local hasComp = block:find("<[%w_]*:?comp[%s/>]") ~= nil
        local capable = (not hasSet) or (not hasComp) or block:find('name="VTODO"', 1, true) ~= nil or block:find("name='VTODO'", 1, true) ~= nil
        cals[#cals + 1] = { name = name, url = absUrl(href, homeOrigin), capable = capable }
      end
    end
  end
  return cals
end

-- Findet die Aufgabenliste: liefert (Listenadresse, Anzeigename) oder nil, Fehlerkennung.
local function discover(kind, base, user, pass, wantName)
  local cals, err = listCalendars(kind, base, user, pass)
  if cals == nil then return nil, err end
  local want = wantName ~= "" and wantName:lower() or nil
  local names = {}
  for _, c in ipairs(cals) do
    names[#names + 1] = c.name
    if want ~= nil then
      if c.name:lower() == want then return c.url, c.name end
    elseif c.capable then
      return c.url, c.name
    end
  end
  if want ~= nil then
    log("Aufgaben: Liste \"" .. wantName .. "\" nicht gefunden. Gefunden: " .. table.concat(names, ", "))
  end
  return nil, "list"
end

-- Holt die offenen (und, falls gewuenscht, erledigten) Aufgaben einer CalDAV-Liste.
local function reportList(listUrl, user, pass, showDone, name, off, en)
  local filter = showDone and "" or REPORT_NOT_DONE
  local body, err = dav("REPORT", listUrl, REPORT_HEAD .. filter .. REPORT_TAIL, "1", user, pass)
  if body == nil then return nil, err end
  local items = {}
  local pos = 1
  while #items < 80 do
    local inner, nxt = xmlTag(body, "calendar-data", pos)
    if inner == nil then break end
    pos = nxt
    local it = parseVtodo(xmlText(inner), off, name, en)
    if it ~= nil and (showDone or not it.done) then items[#items + 1] = it end
  end
  return items
end

-- Antwort-Text eines Todoist-Abrufs lesen; bei abgeschnittener Antwort (24 KB) die vollstaendigen Eintraege retten.
local function decodeResults(body)
  local doc = json.decode(body)
  if type(doc) == "table" then return doc end
  local cutAt
  local pos = 1
  while true do
    local a = body:find("},{", pos, true)
    if a == nil then break end
    cutAt = a
    pos = a + 1
  end
  if cutAt == nil then return nil end
  doc = json.decode(body:sub(1, cutAt) .. "]}")
  if type(doc) == "table" then return doc end
  doc = json.decode(body:sub(1, cutAt) .. "]")
  if type(doc) == "table" then return doc end
  return nil
end

local function resultList(doc)
  if doc == nil then return nil end
  if doc.results ~= nil then return doc.results, doc.next_cursor end
  return doc, nil
end

local function todoistGet(url, token)
  local r, err = req({ url = url, bearer = token, headers = { Accept = "application/json" } })
  if r == nil then return nil, (err == "budget") and "budget" or "net" end
  if r.status ~= 200 then return nil, statusErr(r) end
  local doc = decodeResults(r.body)
  if doc == nil then return nil, "data" end
  return doc
end

local function todoistDue(due)
  if type(due) ~= "table" then return nil end
  local s = due.datetime
  if type(s) ~= "string" or #s < 10 then s = due.date end
  if type(s) ~= "string" or #s < 10 then return nil end
  local y, m, d = tonumber(s:sub(1, 4)), tonumber(s:sub(6, 7)), tonumber(s:sub(9, 10))
  if y == nil or m == nil or d == nil or y < 2000 or m < 1 or m > 12 or d < 1 or d > 31 then return nil end
  if #s >= 19 and s:sub(11, 11) == "T" then
    return dueString(y, m, d, tonumber(s:sub(12, 13)) or 0, tonumber(s:sub(15, 16)) or 0)
  end
  return dueString(y, m, d)
end

local function fetchTodoist(token, wantName, en)
  local doc, err = todoistGet("https://api.todoist.com/api/v1/projects", token)
  if doc == nil then return nil, err end
  local plist = resultList(doc)
  local names = {}
  local wantId, wantLabel
  local want = wantName ~= "" and wantName:lower() or nil
  for _, p in ipairs(plist or {}) do
    local id, nm = tostring(p.id or ""), tostring(p.name or "")
    names[id] = nm
    if want ~= nil and nm:lower() == want then wantId, wantLabel = id, nm end
  end
  if want ~= nil and wantId == nil then
    log("Aufgaben: Todoist-Projekt \"" .. wantName .. "\" nicht gefunden.")
    return nil, "list"
  end
  local items = {}
  local url = "https://api.todoist.com/api/v1/tasks?limit=30" .. (wantId and ("&project_id=" .. wantId) or "")
  local cursor
  for page = 1, 2 do
    local u = url
    if cursor ~= nil then u = url .. "&cursor=" .. text.url_encode(tostring(cursor)) end
    local tdoc, terr = todoistGet(u, token)
    if tdoc == nil then
      if page == 1 then return nil, terr end
      break
    end
    local list, nextCursor = resultList(tdoc)
    for _, t in ipairs(list or {}) do
      local title = clean(tostring(t.content or ""), 64)
      if title == "" then title = en and "(Untitled)" or "(Ohne Titel)" end
      local labels = ""
      if type(t.labels) == "table" then
        local parts = {}
        for _, l in ipairs(t.labels) do parts[#parts + 1] = tostring(l) end
        labels = clean(table.concat(parts, ", "), 40)
      end
      local prio = (tonumber(t.priority) or 1) - 1
      if prio < 0 then prio = 0 elseif prio > 3 then prio = 3 end
      items[#items + 1] = {
        title = title,
        done = false,
        due = todoistDue(t.due),
        prio = prio,
        project = clean(wantLabel or names[tostring(t.project_id or "")] or "", 24),
        labels = labels,
        desc = clean(tostring(t.description or ""):match("^[^\n]*"), 80),
      }
    end
    cursor = nextCursor
    if cursor == nil or calls >= MAX_CALLS then break end
  end
  return items
end

-- Aufgaben einer Quelle in zwei Textbloecke packen (sortiert, hoechstens MAX_PER_SLOT).
local function packItems(items)
  sortItems(items)
  local chunks, cur = {}, ""
  local n = 0
  for _, it in ipairs(items) do
    if n >= MAX_PER_SLOT then break end
    local line = table.concat({
      it.title, it.due or "", it.done and "1" or "0", tostring(it.prio),
      it.project or "", it.labels or "", it.desc or "",
    }, "\t")
    if #line > CHUNK_BYTES then line = it.title .. "\t" .. (it.due or "") .. "\t" .. (it.done and "1" or "0") .. "\t" .. tostring(it.prio) .. "\t\t\t" end
    if #cur + #line + 1 > CHUNK_BYTES then
      chunks[#chunks + 1] = cur
      cur = ""
      if #chunks >= 2 then break end
    end
    cur = cur .. (cur == "" and "" or "\n") .. line
    n = n + 1
  end
  if cur ~= "" and #chunks < 2 then chunks[#chunks + 1] = cur end
  return chunks[1], chunks[2]
end

-- Basisadresse des CalDAV-Servers je Dienst (iCloud fest; Nextcloud ohne Pfad bekommt /remote.php/dav).
local function slotBase(kind, url)
  if kind == "icloud" then return ICLOUD end
  if kind == "nextcloud" and not url:find("/remote%.php") and not url:find("/dav") then
    return (url:gsub("/+$", "")) .. "/remote.php/dav"
  end
  return url
end

-- Eine Quelle abrufen. Liefert Status: "ok", "e:<Kennung>" oder "p" (Abruf-Budget reicht in diesem Lauf nicht).
local function fetchSlot(ctx, idx, off, en)
  local p = SLOTS[idx]
  local cfg = ctx.cfg
  local kind = cfg[p .. "_type"] or "off"
  if kind == "off" then return "-" end
  local url = trim(cfg[p .. "_url"] or "")
  local user = trim(cfg[p .. "_user"] or "")
  local secret = trim(tostring(cfg[p .. "_secret"] or ""))
  local list = trim(cfg[p .. "_list"] or "")
  local showDone = cfg.showDone == true

  local items, err
  if kind == "todoist" then
    if secret == "" then return "e:cfg" end
    if calls + 2 > MAX_CALLS then return "p" end
    items, err = fetchTodoist(secret, list, en)
  else
    if user == "" or secret == "" or (kind ~= "icloud" and url == "") then return "e:cfg" end
    local base = slotBase(kind, url)
    local sig = kind .. "|" .. base .. "|" .. user .. "|" .. list
    local cached = ctx.data.get("u" .. idx)
    local listUrl, name
    if type(cached) == "string" then
      local csig, curl, cname = cached:match("^([^\n]*)\n([^\n]*)\n?(.*)$")
      if csig == sig and curl ~= "" then listUrl, name = curl, cname end
    end
    if listUrl == nil then
      if calls + 4 > MAX_CALLS then return "p" end
      listUrl, name = discover(kind, base, user, secret, list)
      if listUrl == nil then
        ctx.data.set("u" .. idx, nil)
        if name == "budget" then return "p" end
        return "e:" .. tostring(name)
      end
      ctx.data.set("u" .. idx, sig .. "\n" .. listUrl .. "\n" .. name)
    elseif calls + 1 > MAX_CALLS then
      return "p"
    end
    items, err = reportList(listUrl, user, secret, showDone, clean(name or "", 24), off, en)
    if items == nil and (err == "notfound") then
      ctx.data.set("u" .. idx, nil) -- Adresse veraltet: beim naechsten Lauf neu suchen
    end
  end
  if items == nil then
    if err == "budget" then return "p" end
    return "e:" .. tostring(err)
  end
  local a, b = packItems(items)
  ctx.data.set("d" .. idx .. "a", a)
  ctx.data.set("d" .. idx .. "b", b)
  return "ok"
end

function on_fetch(ctx)
  calls = 0
  local en = (ctx.lang == "en")
  local off = utcOffset()
  local oldSt = {}
  local stStr = ctx.data.get("st")
  if type(stStr) == "string" then
    for s in (stStr .. ","):gmatch("([^,]*),") do oldSt[#oldSt + 1] = s end
  end
  local rot = tonumber(ctx.data.get("rot")) or 0
  local st = { oldSt[1] or "-", oldSt[2] or "-", oldSt[3] or "-" }
  local nextRot
  for k = 0, #SLOTS - 1 do
    local i = (rot + k) % #SLOTS + 1
    local s = fetchSlot(ctx, i, off, en)
    if s == "p" then
      nextRot = nextRot or (i - 1)
      if st[i] == "-" then st[i] = "p" end -- noch nie abgerufen
    else
      st[i] = s
    end
  end
  ctx.data.set("rot", nextRot or 0)
  ctx.data.set("st", table.concat(st, ","))
  local anyOk, anyErr = false, false
  for i = 1, #SLOTS do
    if st[i] == "ok" then anyOk = true elseif st[i]:sub(1, 2) == "e:" then anyErr = true end
  end
  for i = 1, #SLOTS do
    if st[i]:sub(1, 2) == "e:" then log("Aufgaben Quelle " .. i .. ": " .. st[i]:sub(3)) end
  end
  if anyErr and not anyOk then return false end
  return true
end

local ERR_DE = {
  cfg = "Angaben unvollständig", auth = "Anmeldung fehlgeschlagen", notfound = "Adresse nicht gefunden",
  net = "Server nicht erreichbar", list = "Liste nicht gefunden", nocaldav = "Kein CalDAV-Server",
  data = "Antwort nicht lesbar",
}
local ERR_EN = {
  cfg = "Settings incomplete", auth = "Sign-in failed", notfound = "Address not found",
  net = "Server not reachable", list = "List not found", nocaldav = "Not a CalDAV server",
  data = "Response not readable",
}

local function errText(code, en)
  local t = en and ERR_EN or ERR_DE
  if code == "net" and lastNetErr ~= "" then return t.net .. " (" .. lastNetErr .. ")" end
  return t[code] or ((en and "Server error " or "Serverfehler ") .. code:gsub("^srv", ""))
end

-- Knopf "Verbinden" im Einstellungsformular (manifest settings[].action): prueft die Zugangsdaten und liefert die
-- vorhandenen Listen/Projekte zur Auswahl. Antwort: {ok=, message=, options={{value=, label=}, ...}}.
function on_action(ctx, name)
  calls = 0
  local en = (ctx.lang == "en")
  local p = name:match("^connect_(%a)$")
  local idx
  for i, s in ipairs(SLOTS) do if s == p then idx = i end end
  if idx == nil then return { ok = false, message = en and "Unknown action" or "Unbekannte Aktion" } end
  local kind = ctx.cfg[p .. "_type"] or "off"
  local url = trim(ctx.cfg[p .. "_url"] or "")
  local user = trim(ctx.cfg[p .. "_user"] or "")
  local secret = trim(tostring(ctx.cfg[p .. "_secret"] or ""))
  local function fail(code)
    return { ok = false, message = errText(code, en) }
  end
  if kind == "off" then return fail("cfg") end
  local options = {}
  local noun
  if kind == "todoist" then
    if secret == "" then return fail("cfg") end
    local doc, err = todoistGet("https://api.todoist.com/api/v1/projects", secret)
    if doc == nil then return fail(err) end
    for _, pr in ipairs(resultList(doc) or {}) do
      local nm = clean(tostring(pr.name or ""), 60)
      if nm ~= "" then options[#options + 1] = { value = nm, label = nm } end
    end
    options[#options + 1] = nil
    table.insert(options, 1, { value = "", label = en and "(all projects)" or "(alle Projekte)" })
    noun = en and "projects" or "Projekte"
  else
    if user == "" or secret == "" or (kind ~= "icloud" and url == "") then return fail("cfg") end
    local cals, err = listCalendars(kind, slotBase(kind, url), user, secret)
    if cals == nil then return fail(err) end
    for _, c in ipairs(cals) do
      if c.capable then options[#options + 1] = { value = c.name, label = c.name } end
    end
    if #options == 0 then return fail("list") end
    table.insert(options, 1, { value = "", label = en and "(first list)" or "(erste Liste)" })
    noun = en and "lists" or "Listen"
  end
  local n = #options - 1
  local msg = en and ("Connected. " .. n .. " " .. noun .. " found.") or ("Verbunden. " .. n .. " " .. noun .. " gefunden.")
  return { ok = true, message = msg, options = options }
end

-- ---------------------------------------------------------------------------
-- Daten lesen und Faelligkeit anzeigen
-- ---------------------------------------------------------------------------

local function splitTabs(line)
  local out, pos = {}, 1
  while true do
    local a = line:find("\t", pos, true)
    if a == nil then out[#out + 1] = line:sub(pos) break end
    out[#out + 1] = line:sub(pos, a - 1)
    pos = a + 1
  end
  return out
end

local function loadItems(ctx)
  local items = {}
  if ctx.sample then -- Beispieldaten fuer die Widget-Vorschau im Dashboard-Editor (CHANGELOG 559)
    local en = ctx.lang == "en"
    local lt = time.localtime()
    local today = lt and (lt.year * 10000 + lt.month * 100 + lt.day) or 20260101
    local function mk(title, due, prio, seq)
      return { title = title, due = due, done = false, prio = prio, project = "", labels = "", desc = "", col = color.BLUE, seq = seq }
    end
    return {
      mk(en and "Sample: buy groceries" or "Beispiel: Einkaufen gehen", tostring(today), 3, 1),
      mk(en and "Sample: call the plumber" or "Beispiel: Installateur anrufen", tostring(today), 2, 2),
      mk(en and "Sample: water the plants" or "Beispiel: Pflanzen gießen", nil, 0, 3),
      mk(en and "Sample: plan weekend trip" or "Beispiel: Wochenendausflug planen", nil, 0, 4),
    }
  end
  local showDone = ctx.cfg.showDone == true
  local seq = 0
  for i = 1, #SLOTS do
    local col = colorOf(ctx.cfg[SLOTS[i] .. "_color"])
    for _, suffix in ipairs({ "a", "b" }) do
      if (ctx.cfg[SLOTS[i] .. "_type"] or "off") == "off" then break end
      local c = ctx.data.get("d" .. i .. suffix)
      if type(c) == "string" then
        for line in c:gmatch("[^\n]+") do
          local f = splitTabs(line)
          local done = f[3] == "1"
          if showDone or not done then
            seq = seq + 1
            items[#items + 1] = {
              title = f[1] or "", due = (f[2] ~= "" and f[2] or nil), done = done,
              prio = tonumber(f[4]) or 0, project = f[5] or "", labels = f[6] or "", desc = f[7] or "",
              col = col, seq = seq,
            }
          end
        end
      end
    end
  end
  sortItems(items)
  return items
end

local function todayKey()
  local lt = time.localtime()
  if lt == nil then return nil end
  return lt.year * 10000 + lt.month * 100 + lt.day
end

local function timeLabel(ctx, tm)
  local hh, mm = tm // 100, tm % 100
  if ctx.clock24 == false then
    local suffix = hh >= 12 and "PM" or "AM"
    local h12 = hh % 12
    if h12 == 0 then h12 = 12 end
    return string.format("%d:%02d %s", h12, mm, suffix)
  end
  return string.format("%02d:%02d", hh, mm)
end

-- "Heute" bzw. "5. Oktober" / "5 October"; Uhrzeit getrennt (oder nil). overdue = Tag liegt vor heute.
local function dueParts(ctx, it, today)
  local day, hasTime, tm = dueKey(it.due)
  if day == nil then return nil end
  local en = (ctx.lang == "en")
  local overdue = today ~= nil and day < today
  local label
  if today ~= nil and day == today then
    label = en and "Today" or "Heute"
  else
    local m, d = (day // 100) % 100, day % 100
    label = en and (d .. " " .. (MONTHS_EN[m] or "")) or (d .. ". " .. (MONTHS_DE[m] or ""))
  end
  return label, hasTime and timeLabel(ctx, tm) or nil, overdue
end

-- ---------------------------------------------------------------------------
-- Zeichnen
-- ---------------------------------------------------------------------------

local function fit(s, w, font)
  while #s > 1 and draw.measure(s, font) > w do
    s = s:sub(1, #s - 1)
    while #s > 1 and (s:byte(#s) & 0xC0) == 0x80 do s = s:sub(1, #s - 1) end
  end
  return s
end

local function notice(icon, line1, line2)
  local cx = draw.width // 2
  draw.icon(icon, cx - 24, 170, 48, color.ACCENT)
  draw.text(cx, 260, line1, "normal", color.BLACK, "center")
  if line2 ~= nil then draw.text(cx, 290, line2, "small", color.BLACK, "center") end
end

-- Leerzustand: gibt true zurueck, wenn schon ein Hinweis gezeichnet wurde.
local function emptyState(ctx, items)
  local en = (ctx.lang == "en")
  local st = {}
  local stStr = ctx.data.get("st")
  if type(stStr) == "string" then
    for s in (stStr .. ","):gmatch("([^,]*),") do st[#st + 1] = s end
  end
  local configured, errCode, errSlot = 0, nil, nil
  for i = 1, #SLOTS do
    if (ctx.cfg[SLOTS[i] .. "_type"] or "off") ~= "off" then
      configured = configured + 1
      local s = st[i] or "-"
      if s:sub(1, 2) == "e:" and errCode == nil then errCode, errSlot = s:sub(3), i end
    end
  end
  if configured == 0 then
    notice("gear", en and "No task list connected." or "Keine Aufgabenliste verbunden.",
      en and "Store -> Tasks -> Settings" or "Store -> Aufgaben -> Einstellungen")
    return true
  end
  if #items > 0 then return false end
  if stStr == nil then
    notice("clock", en and "Loading ..." or "Wird geladen ...")
    return true
  end
  if errCode ~= nil then
    local where = (en and "Source " or "Quelle ") .. errSlot .. ": " .. errText(errCode, en)
    notice("warning", en and "Fetch failed." or "Abruf fehlgeschlagen.", where)
    return true
  end
  local anyOk = false
  for i = 1, #SLOTS do if st[i] == "ok" then anyOk = true end end
  if not anyOk then
    notice("clock", en and "Loading ..." or "Wird geladen ...")
    return true
  end
  notice("check", en and "No tasks in the connected lists." or "Keine Aufgaben in den verbundenen Listen.")
  return true
end

local function strike(x, y, w) draw.line(x, y, x + w, y, color.BLACK) end

local function statusMark(it, cx, cy, r)
  if it.done then draw.circle(cx, cy, r, it.col, true) else draw.circle(cx, cy, r, it.col) end
end

-- "Bento": Detailkarten mit Projekt/Labels und Beschreibung (3 bis 4 Aufgaben).
local function drawCards(ctx, items, today)
  local W = draw.width
  local marginX = 26
  local contentTop = draw.top + 10
  local contentBottom = draw.height - 20
  local shown = math.min(#items, 4)
  local rowH = (contentBottom - contentTop) // shown
  if rowH > 132 then rowH = 132 end
  if rowH < 92 then rowH = 92 end
  local textX = marginX + 34
  local rowY = contentTop
  for n = 1, #items do
    if rowY + rowH > contentBottom + 4 then break end
    local it = items[n]
    draw.line(marginX, rowY, W - marginX, rowY, color.BLACK)
    local cy = rowY + 26
    statusMark(it, marginX + 10, cy, 7)
    if not it.done and it.prio >= 2 then
      draw.circle(marginX + 24, cy - 9, 4, it.prio >= 3 and color.RED or color.YELLOW, true)
    end
    local showDue = not it.done and it.due ~= nil
    local dayLabel, tLabel, overdue
    local dueW = 0
    if showDue then
      dayLabel, tLabel, overdue = dueParts(ctx, it, today)
      dueW = math.max(draw.measure(dayLabel, "small"), tLabel and draw.measure(tLabel, "small") or 0)
    end
    local reserve = showDue and (dueW + 14) or 0
    local title = fit(it.title, W - marginX - reserve - textX, "normal")
    draw.text(textX, rowY + 30, title, "normal", color.BLACK, "left")
    if it.done then
      strike(textX, rowY + 24, draw.measure(title, "normal"))
    elseif showDue then
      local c = overdue and color.RED or color.BLACK
      draw.text(W - marginX, rowY + 22, dayLabel, "small", c, "right")
      if tLabel then draw.text(W - marginX, rowY + 38, tLabel, "small", c, "right") end
    end
    local meta = it.project
    if it.labels ~= "" then meta = meta .. (meta ~= "" and " - " or "") .. it.labels end
    if meta ~= "" then
      draw.text(textX, rowY + 50, fit(meta, W - marginX - reserve - textX, "small"), "small", color.BLACK, "left")
    end
    if it.desc ~= "" then
      draw.text(textX, rowY + 70, fit(it.desc, W - marginX - textX, "small"), "small", color.BLACK, "left")
    end
    rowY = rowY + rowH
  end
end

-- "Slate": eine Zeile je Aufgabe, Datum und Uhrzeit rechts in einer Zeile (bis 9 Aufgaben).
local function drawFlat(ctx, items, today)
  local W = draw.width
  local marginX = 26
  local contentTop = draw.top + 10
  local contentBottom = draw.height - 20
  local shown = math.min(#items, 9)
  local rowH = (contentBottom - contentTop) // shown
  if rowH > 56 then rowH = 56 end
  if rowH < 40 then rowH = 40 end
  local rowY = contentTop
  for n = 1, #items do
    if rowY + rowH > contentBottom + 4 then break end
    local it = items[n]
    draw.line(marginX, rowY, W - marginX, rowY, color.BLACK)
    local cy = rowY + rowH // 2
    statusMark(it, marginX + 10, cy, 7)
    if not it.done and it.prio >= 2 then
      draw.circle(marginX + 22, cy - 9, 3, it.prio >= 3 and color.RED or color.YELLOW, true)
    end
    local showDue = not it.done and it.due ~= nil
    local combined, overdue
    local dueW = 0
    if showDue then
      local dayLabel, tLabel
      dayLabel, tLabel, overdue = dueParts(ctx, it, today)
      combined = tLabel and (dayLabel .. ", " .. tLabel) or dayLabel
      dueW = draw.measure(combined, "small")
    end
    local textX = marginX + 28
    local title = fit(it.title, W - marginX - (showDue and (dueW + 14) or 0) - textX, "normal")
    draw.text(textX, cy + 6, title, "normal", color.BLACK, "left")
    if it.done then
      strike(textX, cy, draw.measure(title, "normal"))
    elseif showDue then
      draw.text(W - marginX, cy + 5, combined, "small", overdue and color.RED or color.BLACK, "right")
    end
    rowY = rowY + rowH
  end
end

-- "Nano": nur Punkt, Titel und kurzes Datum (bis 14 Aufgaben).
local function drawCompact(ctx, items, today)
  local W = draw.width
  local marginX = 24
  local contentTop = draw.top + 6
  local contentBottom = draw.height - 16
  local shown = math.min(#items, 14)
  local rowH = (contentBottom - contentTop) // shown
  if rowH > 40 then rowH = 40 end
  if rowH < 24 then rowH = 24 end
  local rowY = contentTop
  for n = 1, #items do
    if rowY + rowH > contentBottom + 2 then break end
    local it = items[n]
    local cy = rowY + rowH // 2
    statusMark(it, marginX + 4, cy, 3)
    local showDue = not it.done and it.due ~= nil
    local dayLabel, overdue
    local dueW = 0
    if showDue then
      local unusedTime
      dayLabel, unusedTime, overdue = dueParts(ctx, it, today)
      dueW = draw.measure(dayLabel, "small") + 10
    end
    local title = fit(it.title, W - 2 * marginX - 14 - dueW, "small")
    draw.text(marginX + 14, cy + 5, title, "small", color.BLACK, "left")
    if it.done then
      strike(marginX + 14, cy, draw.measure(title, "small"))
    elseif showDue then
      draw.text(W - marginX, cy + 5, dayLabel, "small", overdue and color.RED or color.BLACK, "right")
    end
    rowY = rowY + rowH
  end
end

function on_draw(ctx, page)
  draw.clear(color.WHITE)
  local items = loadItems(ctx)
  if emptyState(ctx, items) then return end
  local today = todayKey()
  local style = ctx.cfg.style
  if style == "flat" then drawFlat(ctx, items, today)
  elseif style == "compact" then drawCompact(ctx, items, today)
  else drawCards(ctx, items, today) end
end

-- Widget: Kaestchen in der Quellenfarbe (Prioritaet: rot/gelb), davor optional "Mo 05.10.".
local function fnt(b, base)
  local t = b and b.font or 0
  if t < 0 and base == "normal" then return "small" end
  if t > 0 and base == "small" then return "normal" end
  return base
end

local function shortDate(ctx, s)
  local day = dueKey(s)
  if day == nil then return nil end
  local y, m, d = day // 10000, (day // 100) % 100, day % 100
  local wd = (dfc(y, m, d) + 4) % 7 + 1
  local names = ctx.lang == "en" and WDAY_EN or WDAY_DE
  return string.format("%s %02d.%02d.", names[wd], d, m)
end

function on_widget(ctx, box)
  local en = (ctx.lang == "en")
  local all = loadItems(ctx)
  local items = {}
  for _, it in ipairs(all) do if not it.done then items[#items + 1] = it end end
  local font = fnt(box, "small")
  local lineH = 22
  local y = box.y + 16
  local maxY = box.y + box.h - 4
  local showDue = ctx.cfg.wDue ~= false
  local showPrio = ctx.cfg.wPrio ~= false
  local shown = 0
  for _, it in ipairs(items) do
    if y > maxY then break end
    local c = it.col
    if showPrio and it.prio >= 3 then c = color.RED elseif showPrio and it.prio == 2 then c = color.YELLOW end
    draw.rect(box.x + 12, y - 10, 12, 12, c, false, 3)
    draw.rect(box.x + 13, y - 9, 10, 10, c, false, 2)
    local line = it.title
    if showDue and it.due ~= nil then line = shortDate(ctx, it.due) .. "  " .. it.title end
    draw.text(box.x + 32, y, fit(line, box.w - 46, font), font, color.BLACK, "left")
    y = y + lineH
    shown = shown + 1
  end
  if shown == 0 then
    local msg
    if #all > 0 or ctx.data.get("st") ~= nil then msg = en and "All done" or "Alles erledigt"
    else msg = en and "No data yet" or "Noch keine Daten" end
    draw.text(box.x + 12, box.y + 16, msg, font, color.BLACK, "left")
  end
end
