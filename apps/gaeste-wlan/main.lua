-- Gaeste-WLAN (Paket gaeste-wlan): zeitlich begrenzter Gast-Modus - WLAN-QR-Code zum Scannen, Zugangsdaten, Willkommenstext
-- und Hausregeln. Gast-Modus starten/beenden, Text und Regeln aendern per Handy-Seite (QR-Code). Skript-API Level 23.
-- Zustand: Datei "gast" (lokal) und optional "gast.txt" auf dem externen Speicher (storagePath-Feld "dir"), pro Zeile
-- "schluessel TAB zeit TAB wert" (until = Ende des Gast-Modus in Unix-Sekunden, 0 = aus; welcome; r1..r6 = Hausregeln).
-- Abgleich in on_fetch: je Schluessel gewinnt die neuere Zeit. WLAN-Name/Passwort stehen nur in den Einstellungen dieses
-- Geraets und werden nie ueber den Speicher oder die Handy-Seite verteilt. Ohne externen Speicher: "nicht synchronisiert".

local NAS_FILE = "gast.txt"
local MAX_RULES = 6
local HOURS = { [24] = true, [72] = true, [168] = true, [336] = true }

local function T(ctx, de, en) return (ctx.lang == "en") and en or de end

-- ===== Daten =====

local function parse(text)
  local m = {}
  if text then
    for k, ts, v in text:gmatch("([%w_]+)\t(%d+)\t([^\n]*)") do m[k] = { ts = tonumber(ts), v = v } end
  end
  return m
end

local function serialize(m)
  local keys = {}
  for k in pairs(m) do keys[#keys + 1] = k end
  table.sort(keys)
  local out = {}
  for i = 1, #keys do out[i] = string.format("%s\t%d\t%s", keys[i], m[keys[i]].ts, m[keys[i]].v) end
  return table.concat(out, "\n")
end

local function merge(a, b)
  for k, e in pairs(b) do
    local x = a[k]
    if x == nil or e.ts > x.ts then a[k] = e end
  end
end

local function load_local() return parse(file.read("gast")) end
local function now_ts() return time.now() or 0 end
local function val(m, k) return m[k] and m[k].v or "" end

local function clean(t, maxlen)
  t = tostring(t or ""):gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if #t > maxlen then
    local i = maxlen
    while i > 1 and (t:byte(i + 1) or 0) & 0xC0 == 0x80 do i = i - 1 end
    t = t:sub(1, i)
  end
  return t
end

-- Gast-Modus: dauerhaft (Einstellung) oder bis "until". left = Restsekunden (nil = dauerhaft), active = laeuft
local function state(ctx, m)
  if ctx.cfg.always then return true, nil end
  local u = tonumber(val(m, "until")) or 0
  local now = now_ts()
  if u <= 0 then return false, 0 end
  if now == 0 then return true, nil end -- Uhr nicht gestellt: Ende unbekannt
  return u > now, math.max(0, u - now)
end

local function rules_of(m)
  local r = {}
  for i = 1, MAX_RULES do
    local t = val(m, "r" .. i)
    if t ~= "" then r[#r + 1] = t end
  end
  return r
end

local function welcome_of(ctx, m)
  local w = val(m, "welcome")
  if w ~= "" then return w end
  return T(ctx, "Willkommen! Schön, dass ihr da seid.", "Welcome! Great to have you here.")
end

local function left_text(ctx, left)
  if left == nil then return ctx.cfg.always and T(ctx, "dauerhaft", "permanent") or "" end
  local d = left // 86400
  local h = (left % 86400) // 3600
  local mi = (left % 3600) // 60
  if d >= 1 then
    return string.format(T(ctx, "noch %d %s %d Std", "%d %s %d h left"), d, d == 1 and T(ctx, "Tag", "day") or T(ctx, "Tage", "days"), h)
  end
  if h >= 1 then return string.format(T(ctx, "noch %d Std %d Min", "%d h %d min left"), h, mi) end
  return string.format(T(ctx, "noch %d Min", "%d min left"), math.max(1, mi))
end

-- WLAN-QR nach dem ueblichen Schema WIFI:T:WPA;S:name;P:passwort;;  (Sonderzeichen \ ; , : " mit Backslash)
local function wifi_payload(ctx)
  local ssid = tostring(ctx.cfg.ssid or "")
  if ssid == "" then return nil end
  local function esc(s) return (s:gsub('([\\;,:"])', "\\%1")) end
  local sec = tostring(ctx.cfg.sec or "WPA")
  if sec == "nopass" then return "WIFI:T:nopass;S:" .. esc(ssid) .. ";;" end
  return "WIFI:T:" .. sec .. ";S:" .. esc(ssid) .. ";P:" .. esc(tostring(ctx.cfg.pass or "")) .. ";;"
end

-- ===== Abruf: Abgleich mit dem externen Speicher =====

function on_fetch(ctx)
  local m = load_local()
  local sync = "local"
  if storage.ready() then
    local remote, err = storage.read("dir", NAS_FILE)
    if remote == nil and err == "nicht gefunden" then remote = "" end
    if remote ~= nil then
      merge(m, parse(remote))
      local s = serialize(m)
      if s ~= remote then
        sync = storage.write("dir", NAS_FILE, s) and "ok" or "error"
      else
        sync = "ok"
      end
    else
      sync = "error"
    end
  end
  file.write("gast", serialize(m))
  ctx.data.set("sync", sync)
  if sync == "ok" then ctx.data.set("syncAt", now_ts()) end
  return true
end

-- ===== Handy-Seite =====

local function esc(t)
  return (tostring(t):gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" end
    return " "
  end))
end

local function reply(status, body) return { status = status, body = body } end

local function state_json(ctx, m)
  local active, left = state(ctx, m)
  local rules = rules_of(m)
  local rj = {}
  for i = 1, #rules do rj[i] = '"' .. esc(rules[i]) .. '"' end
  return string.format('{"active":%s,"left":%d,"always":%s,"welcome":"%s","rules":[%s],"ssid":"%s","sync":"%s"}',
    tostring(active), left or -1, tostring(ctx.cfg.always and true or false), esc(val(m, "welcome")), table.concat(rj, ","),
    esc(ctx.cfg.ssid or ""), esc(ctx.data.get("sync") or "local"))
end

function on_http(ctx, req)
  local q = json.decode(req.body or "")
  if type(q) ~= "table" then return reply(400, '{"error":"JSON"}') end
  local op = tostring(q.op or "list")
  local m = load_local()
  local now = now_ts()
  local changed = false
  if op == "start" then
    local h = math.floor(tonumber(q.hours) or 0)
    if not HOURS[h] or now == 0 then return reply(400, '{"error":"Dauer oder Uhr"}') end
    m["until"] = { ts = now, v = tostring(now + h * 3600) }
    changed = true
  elseif op == "stop" then
    m["until"] = { ts = now, v = "0" }
    changed = true
  elseif op == "set" then
    m.welcome = { ts = now, v = clean(q.welcome, 80) }
    local list = type(q.rules) == "table" and q.rules or {}
    for i = 1, MAX_RULES do
      local t = clean(list[i], 70)
      if t ~= "" or m["r" .. i] then m["r" .. i] = { ts = now, v = t } end
    end
    changed = true
  end
  if changed then
    file.write("gast", serialize(m))
    local r = reply(200, state_json(ctx, m))
    r.fetch = true
    r.redraw = true
    return r
  end
  return reply(200, state_json(ctx, m))
end

-- ===== Zeichnen =====

local function cut(text, maxw, font)
  while #text > 1 and draw.measure(text, font) > maxw do
    local i = #text
    while i > 1 and (text:byte(i) & 0xC0) == 0x80 do i = i - 1 end
    text = text:sub(1, i - 1)
  end
  return text
end

-- groesste Schrift, in der der Text noch passt (sonst abgeschnitten in der kleinsten)
local function fit(text, maxw, fonts)
  for i = 1, #fonts do
    if draw.measure(text, fonts[i]) <= maxw then return text, fonts[i] end
  end
  local f = fonts[#fonts]
  return cut(text, maxw, f), f
end

local function sync_text(ctx)
  local s = ctx.data.get("sync")
  if s == "ok" then return T(ctx, "synchronisiert", "synced") end
  if s == "error" then return T(ctx, "Sync-Fehler", "sync error") end
  return T(ctx, "nicht synchronisiert", "not synced")
end

local function page_off(ctx)
  draw.clear(color.WHITE)
  local title = T(ctx, "Gast-Modus ist aus", "Guest mode is off")
  local hint = T(ctx, "QR-Code scannen und den Gast-Modus am Handy starten:", "Scan the QR code to start guest mode on your phone:")
  if device.qrscreen and device.qrscreen(title, hint) then return end
  draw.text(draw.width // 2, draw.top + 150, title, "large", color.BLACK, "center")
end

local function page_wifi(ctx)
  local style = ctx.cfg.style or "cards"
  local m = load_local()
  local active, left = state(ctx, m)
  if not active then return page_off(ctx) end
  draw.clear(color.WHITE)
  local payload = wifi_payload(ctx)
  local y0 = draw.top
  local W, H = draw.width, draw.height
  if not payload then
    draw.text(W // 2, y0 + 140, T(ctx, "WLAN-Name fehlt", "Wi-Fi name missing"), "large", color.BLACK, "center")
    draw.text(W // 2, y0 + 180, T(ctx, "In den App-Einstellungen eintragen", "Enter it in the app settings"), "normal", color.BLACK, "center")
    return
  end
  local ssid = tostring(ctx.cfg.ssid)
  local pass = tostring(ctx.cfg.pass or "")
  local open = (ctx.cfg.sec == "nopass")
  local lt = left_text(ctx, left)
  if style == "compact" then
    -- Nano: QR-Code links, Name und Passwort gross daneben - ohne Rahmen, mittig auf dem Schirm
    local side = draw.qr(payload, 0, 0, 400) or 0
    draw.rect(0, 0, side, side, color.WHITE, true, 0)
    local qy = y0 + (H - y0 - side) // 2
    draw.qr(payload, 40, qy, 400)
    local tx = 40 + side + 40
    local maxw = W - tx - 24
    local my = qy + side // 2
    local t1, f1 = fit(ssid, maxw, { "large", "normal" })
    draw.text(tx, my - (open and -8 or 18), t1, f1, color.BLACK, "left")
    if not open then
      local t2, f2 = fit(pass, maxw, { "large", "normal" })
      draw.text(tx, my + 30, t2, f2, color.BLACK, "left")
    end
    if lt ~= "" then draw.text(tx, qy + side - 2, lt, "normal", color.BLACK, "left") end
    return
  end
  draw.text(28, y0 + 34, cut(welcome_of(ctx, m), W - 56, "large"), "large", color.BLACK, "left")
  local top = y0 + 52
  local q = math.min(H - top - 92, W // 2 - 20)
  local cw = math.min(q + 24, 250)
  if style == "cards" then draw.rect(24, top, cw, q + 24, color.BLACK, false, 14) end
  local side = draw.qr(payload, 24 + 12, top + 12, q) or q
  -- QR-Code in der Karte zentrieren (die Groesse ergibt sich aus dem Inhalt, hoechstens 6 Pixel je Modul)
  local qx = 24 + (cw - side) // 2
  local qy = top + (q + 24 - side) // 2
  draw.rect(24 + 2, top + 2, cw - 4, q + 20, color.WHITE, true, 12)
  draw.qr(payload, qx, qy, side)
  local tx = 24 + cw + 28
  local maxw = W - tx - 28
  if style == "cards" then
    draw.rect(tx - 14, top, maxw + 28, q + 24, color.BLACK, false, 14)
  else
    draw.line(tx - 14, top, tx - 14, top + q + 24, color.BLACK)
  end
  draw.text(tx, top + 32, T(ctx, "WLAN", "Wi-Fi"), "small", color.BLACK, "left")
  local t1, f1 = fit(ssid, maxw, { "large", "normal" })
  draw.text(tx, top + 68, t1, f1, color.BLACK, "left")
  if not open then
    draw.text(tx, top + 116, T(ctx, "Passwort", "Password"), "small", color.BLACK, "left")
    local t2, f2 = fit(pass, maxw, { "large", "normal" })
    draw.text(tx, top + 152, t2, f2, color.BLACK, "left")
  else
    draw.text(tx, top + 116, T(ctx, "ohne Passwort", "no password"), "normal", color.BLACK, "left")
  end
  draw.text(tx, top + q + 8, cut(T(ctx, "Kamera auf den QR-Code halten", "Point your camera at the QR code"), maxw, "small"), "small", color.BLACK, "left")
  if lt ~= "" then
    local bw = draw.measure(lt, "normal") + 28
    local by = H - 22
    if style == "cards" then
      draw.rect(W - 28 - bw, by - 24, bw, 34, color.YELLOW, true, 17)
      draw.rect(W - 28 - bw, by - 24, bw, 34, color.BLACK, false, 17)
      draw.text(W - 28 - bw // 2, by, lt, "normal", color.BLACK, "center")
    else
      draw.text(W - 28, by, lt, "normal", color.BLACK, "right")
    end
  end
  draw.text(28, H - 10, sync_text(ctx), "small", color.BLACK, "left")
end

local function page_rules(ctx)
  local style = ctx.cfg.style or "cards"
  local m = load_local()
  local rules = rules_of(m)
  if #rules == 0 then
    draw.clear(color.WHITE)
    local title = T(ctx, "Keine Hausregeln", "No house rules")
    local hint = T(ctx, "QR-Code scannen und Regeln am Handy eintragen:", "Scan the QR code to add rules on your phone:")
    if device.qrscreen and device.qrscreen(title, hint) then return end
    draw.text(draw.width // 2, draw.top + 150, title, "large", color.BLACK, "center")
    return
  end
  draw.clear(color.WHITE)
  local y0 = draw.top
  local W, H = draw.width, draw.height
  draw.text(28, y0 + 38, T(ctx, "Hausregeln", "House rules"), "large", color.BLACK, "left")
  draw.line(28, y0 + 52, W - 28, y0 + 52, color.BLACK)
  local n = #rules
  local rowH = math.min(64, (H - y0 - 90) // n)
  local font = (style == "compact") and "large" or "normal"
  for i = 1, n do
    local y = y0 + 64 + (i - 1) * rowH
    if style == "cards" then
      draw.rect(24, y, W - 48, rowH - 8, color.BLACK, false, 12)
    elseif style == "flat" then
      draw.line(28, y + rowH - 4, W - 28, y + rowH - 4, color.BLACK)
    end
    local cy = y + (rowH - 8) // 2
    draw.circle(52, cy, 14, color.BLUE, true)
    draw.circle(52, cy, 14, color.BLACK, false)
    draw.text(52, cy + 7, tostring(i), "normal", color.WHITE, "center")
    draw.text(80, cy + 8, cut(rules[i], W - 80 - 44, font), font, color.BLACK, "left")
  end
end

function on_draw(ctx, page)
  if page == 2 then return page_rules(ctx) end
  return page_wifi(ctx)
end

function on_widget(ctx, box)
  local style = ctx.cfg.style or "cards"
  local m = load_local()
  local active, left = state(ctx, m)
  local cx = box.x + box.w // 2
  local payload = active and wifi_payload(ctx) or nil
  if not active then
    draw.text(cx, box.y + box.h // 2 + 6, T(ctx, "Gast-Modus aus", "Guest mode off"), "normal", color.BLACK, "center")
    return
  end
  if not payload then
    draw.text(cx, box.y + box.h // 2 + 6, T(ctx, "WLAN-Name fehlt", "Wi-Fi name missing"), "normal", color.BLACK, "center")
    return
  end
  local ssid = tostring(ctx.cfg.ssid)
  if box.h < 90 or style == "compact" then
    local q = math.min(box.h - 28, box.w - 16)
    local side = draw.qr(payload, cx - q // 2, box.y + 4, q) or 0
    draw.text(cx, box.y + box.h - 6, cut(ssid, box.w - 12, "small"), "small", color.BLACK, "center")
    return
  end
  local q = box.h - 20
  local side = draw.qr(payload, box.x + 10, box.y + 10, q) or q
  local tx = box.x + 10 + side + 14
  local maxw = box.x + box.w - tx - 8
  local lt = left_text(ctx, left)
  local t1, f1 = fit(ssid, maxw, { "normal", "small" })
  if box.h >= 110 then
    draw.text(tx, box.y + 22, T(ctx, "Gäste-WLAN", "Guest Wi-Fi"), "small", color.BLACK, "left")
    draw.text(tx, box.y + 50, t1, f1, color.BLACK, "left")
    if ctx.cfg.sec ~= "nopass" and tostring(ctx.cfg.pass or "") ~= "" then
      local t2, f2 = fit(tostring(ctx.cfg.pass), maxw, { "normal", "small" })
      draw.text(tx, box.y + 76, t2, f2, color.BLACK, "left")
    end
    if lt ~= "" then draw.text(tx, box.y + box.h - 8, cut(lt, maxw, "small"), "small", color.GREEN, "left") end
  else
    draw.text(tx, box.y + box.h // 2 - 4, t1, f1, color.BLACK, "left")
    if lt ~= "" then draw.text(tx, box.y + box.h // 2 + 22, cut(lt, maxw, "small"), "small", color.GREEN, "left") end
  end
end
