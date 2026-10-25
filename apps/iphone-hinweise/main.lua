-- Hinweise aufs iPhone (Paket iphone-hinweise): bringt die Warnungen des InkBoards dorthin, wo du sie sofort siehst - als Mitteilung auf dem iPhone.
-- Ueberwacht CO2, Luftfeuchte, Akkustand (dieses Geraet und die anderen im Netzwerk) und ob ein Geraet im Netzwerk verschwindet.
-- Versand ueber ntfy (kostenlose iPhone-App "ntfy", Server ntfy.sh oder eigener Server) und/oder E-Mail (mail.send, Empfaenger aus den Geraeteeinstellungen).
-- Skript-API Level 26. Laeuft im Hintergrund (backgroundFetch), auch wenn die App nicht angezeigt wird.
--
-- Ablauf je Lauf (on_fetch): Werte lesen -> pro Bedingung pruefen -> hoechstens eine Mitteilung je Bedingung und Sperrzeit ("cooldown") senden.
-- Zustand in ctx.data: "s_<bedingung>" = Unix-Zeit der letzten Mitteilung, "log" = die letzten Mitteilungen, "peers" = bekannte Geraete.

local CHECKS = { "co2", "hum", "bat", "off" }

local function T(ctx, de, en) return (ctx.lang == "en") and en or de end

local function now() return time.now() or 0 end

local function pretty(name)
  name = tostring(name or "")
  return (name:gsub("^%l", string.upper))
end

-- ===== Messwerte =====

-- Liste {name=, co2=, hum=, bat=} fuer dieses Geraet und alle frisch meldenden Geraete im Netzwerk
local function readings()
  local out = {}
  local s = sensor.get()
  local sys = system.get()
  if s then
    out[#out + 1] = { name = pretty(s.room or (sys and sys.room) or ""), co2 = s.co2, hum = s.humidity, bat = (sys and sys.on_battery and sys.battery) or s.battery, own = true }
  elseif sys and sys.battery then
    out[#out + 1] = { name = pretty(sys.room or ""), bat = sys.battery, own = true }
  end
  local peers = sensor.peers()
  if peers then
    for _, p in ipairs(peers) do
      if p.valid ~= false then out[#out + 1] = { name = pretty(p.room or "?"), co2 = p.co2, hum = p.humidity, bat = p.battery } end
    end
  end
  return out
end

-- ===== Bedingungen =====

local function cfgn(ctx, k, d) return tonumber(ctx.cfg[k]) or d end

-- Gibt Liste {key=, text=} der gerade verletzten Bedingungen zurueck
local function violations(ctx, rs)
  local v = {}
  if ctx.cfg.watchCo2 ~= false then
    local lim = cfgn(ctx, "co2Ppm", 1200)
    for _, r in ipairs(rs) do
      if r.co2 and r.co2 >= lim then v[#v + 1] = { key = "co2:" .. r.name, text = string.format(T(ctx, "CO2 in %s: %d ppm – bitte lüften", "CO2 in %s: %d ppm – please ventilate"), r.name ~= "" and r.name or "?", r.co2) } end
    end
  end
  if ctx.cfg.watchHum ~= false then
    local lo, hi = cfgn(ctx, "humLow", 30), cfgn(ctx, "humHigh", 70)
    for _, r in ipairs(rs) do
      if r.hum and r.hum > 0 then
        if r.hum < lo then v[#v + 1] = { key = "hum:" .. r.name, text = string.format(T(ctx, "Luft in %s zu trocken: %d %%", "Air in %s too dry: %d %%"), r.name, r.hum) } end
        if r.hum > hi then v[#v + 1] = { key = "hum:" .. r.name, text = string.format(T(ctx, "Luft in %s zu feucht: %d %%", "Air in %s too humid: %d %%"), r.name, r.hum) } end
      end
    end
  end
  if ctx.cfg.watchBat ~= false then
    local lim = cfgn(ctx, "batPct", 20)
    for _, r in ipairs(rs) do
      if r.bat and r.bat > 0 and r.bat <= lim then v[#v + 1] = { key = "bat:" .. r.name, text = string.format(T(ctx, "Akku von %s fast leer: %d %%", "Battery of %s almost empty: %d %%"), r.name ~= "" and r.name or "InkBoard", math.floor(r.bat)) } end
    end
  end
  return v
end

-- Bekannte Geraete merken und fehlende melden (Name|zuletzt gesehen;...)
local function offlineCheck(ctx, rs, v)
  local known = {}
  local raw = tostring(ctx.data.get("peers") or "")
  for name, ts in raw:gmatch("([^|;]+)|(%d+)") do known[name] = tonumber(ts) end
  local t = now()
  if t == 0 then return end
  for _, r in ipairs(rs) do if not r.own and r.name ~= "" then known[r.name] = t end end
  if ctx.cfg.watchOff ~= false then
    local lim = cfgn(ctx, "offMin", 45) * 60
    for name, ts in pairs(known) do
      if t - ts >= lim then
        v[#v + 1] = { key = "off:" .. name, text = string.format(T(ctx, "%s meldet sich nicht mehr (seit %d Min)", "%s is not responding (for %d min)"), name, (t - ts) // 60) }
      end
    end
  end
  local keep = {}
  for name, ts in pairs(known) do if t - ts < 7 * 86400 then keep[#keep + 1] = name .. "|" .. ts end end
  ctx.data.set("peers", table.concat(keep, ";"))
end

-- ===== Versand =====

local function topicUrl(ctx, title)
  local topic = tostring(ctx.cfg.topic or ""):gsub("[^%w_%-]", "")
  if topic == "" then return nil end
  local base = "https://ntfy.sh"
  if ctx.cfg.server == "own" and tostring(ctx.cfg.ownServer or "") ~= "" then base = tostring(ctx.cfg.ownServer):gsub("/+$", "") end
  local prio = ctx.cfg.urgent == false and "default" or "high"
  return base .. "/" .. topic .. "?title=" .. text.url_encode(title) .. "&priority=" .. prio .. "&tags=warning"
end

local function send(ctx, title, msg)
  local ok, err = false, nil
  local ch = ctx.cfg.channel or "ntfy"
  if ch == "ntfy" or ch == "both" then
    local url = topicUrl(ctx, title)
    if url == nil then err = T(ctx, "Thema (Topic) fehlt", "Topic missing")
    else
      local r, e = http.request{ url = url, method = "POST", body = msg, headers = { ["Content-Type"] = "text/plain" } }
      if r and r.status >= 200 and r.status < 300 then ok = true else err = e or ("HTTP " .. tostring(r and r.status)) end
    end
  end
  if ch == "mail" or ch == "both" then
    if mail.ready() then
      local r, e = mail.send(title, msg)
      if r then ok = true else err = err or e end
    else err = err or T(ctx, "E-Mail nicht eingerichtet", "E-mail not set up") end
  end
  return ok, err
end

local function addLog(ctx, msg)
  local log = tostring(ctx.data.get("log") or "")
  local line = now() .. "|" .. msg:gsub("[|\n]", " ")
  local lines = { line }
  for l in log:gmatch("[^\n]+") do if #lines < 4 then lines[#lines + 1] = l end end
  ctx.data.set("log", table.concat(lines, "\n"))
end

function on_fetch(ctx)
  local rs = readings()
  local v = violations(ctx, rs)
  offlineCheck(ctx, rs, v)
  local t = now()
  local cool = cfgn(ctx, "cooldown", 60) * 60
  local active, due, dueKeys = {}, {}, {}
  for _, x in ipairs(v) do
    active[#active + 1] = x.text
    local last = tonumber(ctx.data.get("s_" .. x.key)) or 0
    if t == 0 or t - last >= cool then due[#due + 1] = x.text; dueKeys[#dueKeys + 1] = x.key end
  end
  -- mail.send erlaubt nur eine Mail je Lauf, ntfy braucht je Lauf einen Abruf: alle faelligen Meldungen gehen in EINER Nachricht raus
  if #due > 0 then
    local title = (#due == 1) and due[1] or (#due .. T(ctx, " Hinweise vom InkBoard", " notices from the InkBoard"))
    local ok, err = send(ctx, title, table.concat(due, "\n"))
    if ok then
      for i = 1, #dueKeys do ctx.data.set("s_" .. dueKeys[i], t) end
      for i = #due, 1, -1 do addLog(ctx, due[i]) end
      ctx.data.set("err", "")
    else
      ctx.data.set("err", tostring(err or "?"))
    end
  end
  ctx.data.set("active", table.concat(active, "\n"))
  ctx.data.set("n_dev", #rs)
  ctx.data.set("ts", t)
  return true
end

function on_action(ctx, name)
  if name ~= "test" then return { ok = false, message = T(ctx, "Unbekannte Aktion.", "Unknown action.") } end
  local ok, err = send(ctx, "InkBoard", T(ctx, "Test: Hinweise aufs iPhone funktionieren.", "Test: iPhone notices work."))
  if ok then return { ok = true, message = T(ctx, "Gesendet – schau auf dein iPhone.", "Sent – check your iPhone.") } end
  return { ok = false, message = T(ctx, "Nicht gesendet: ", "Not sent: ") .. tostring(err) }
end

-- ===== Anzeige =====

local function lines(s)
  local out = {}
  for l in tostring(s or ""):gmatch("[^\n]+") do out[#out + 1] = l end
  return out
end

local function ago(ctx, ts)
  local t = now()
  if t == 0 or ts == 0 then return "" end
  local m = (t - ts) // 60
  if m < 1 then return T(ctx, "gerade eben", "just now") end
  if m < 60 then return T(ctx, "vor ", "") .. m .. T(ctx, " Min", " min ago") end
  local h = m // 60
  if h < 48 then return T(ctx, "vor ", "") .. h .. T(ctx, " Std", " h ago") end
  return T(ctx, "vor ", "") .. (h // 24) .. T(ctx, " Tagen", " d ago")
end

local function cut(text, maxW, font)
  text = tostring(text or "")
  if draw.measure(text, font) <= maxW then return text end
  while #text > 1 do
    local i = #text
    while i > 1 and (text:byte(i) & 0xC0) == 0x80 do i = i - 1 end
    text = text:sub(1, i - 1)
    if draw.measure(text .. "..", font) <= maxW then return text .. ".." end
  end
  return text
end

local function summary(ctx)
  local act = lines(ctx.data.get("active"))
  local n = tonumber(ctx.data.get("n_dev")) or 0
  return act, n, tostring(ctx.data.get("err") or "")
end

local function channelLabel(ctx)
  local ch = ctx.cfg.channel or "ntfy"
  if ch == "mail" then return T(ctx, "E-Mail", "E-mail") end
  if ch == "both" then return "ntfy + " .. T(ctx, "E-Mail", "e-mail") end
  return "ntfy"
end

local function drawBody(ctx, style)
  draw.clear(color.WHITE)
  local act, n, err = summary(ctx)
  local ok = (#act == 0) and err == ""
  local topY = draw.top + 14
  local x = 40
  local cardW = draw.width - 2 * x
  if style == "flat" then
    draw.rect(0, draw.top, draw.width, 120, ok and color.GREEN or color.RED, true)
    draw.text(x, draw.top + 52, ok and T(ctx, "Alles in Ordnung", "All good") or (#act .. T(ctx, " Warnung(en)", " warning(s)")), "large", color.WHITE, "left")
    draw.text(x, draw.top + 90, string.format(T(ctx, "%d Gerät(e) überwacht · %s", "%d device(s) watched · %s"), n, channelLabel(ctx)), "normal", color.WHITE, "left")
    topY = draw.top + 140
  else
    draw.rect(x, topY, cardW, 96, color.WHITE, true, 18)
    draw.rect(x, topY, cardW, 96, color.BLACK, false, 18)
    draw.circle(x + 48, topY + 48, 26, ok and color.GREEN or color.RED, true)
    draw.circle(x + 48, topY + 48, 26, color.BLACK, false)
    draw.text(x + 92, topY + 44, ok and T(ctx, "Alles in Ordnung", "All good") or (#act .. T(ctx, " Warnung(en)", " warning(s)")), "large", color.BLACK, "left")
    draw.text(x + 92, topY + 76, string.format(T(ctx, "%d Gerät(e) überwacht · Versand per %s", "%d device(s) watched · sent via %s"), n, channelLabel(ctx)), "small", color.BLACK, "left")
    topY = topY + 116
  end
  local y = topY
  if err ~= "" then
    draw.text(x, y + 20, cut(T(ctx, "Fehler: ", "Error: ") .. err, cardW, "normal"), "normal", color.RED, "left"); y = y + 34
  end
  for i = 1, math.min(#act, 4) do
    draw.circle(x + 8, y + 12, 7, color.RED, true)
    draw.text(x + 26, y + 18, cut(act[i], cardW - 26, "normal"), "normal", color.BLACK, "left")
    y = y + 32
  end
  if #act == 0 and err == "" then
    draw.text(x, y + 20, T(ctx, "Keine Grenze überschritten.", "No limit exceeded."), "normal", color.BLACK, "left"); y = y + 36
  end
  local log = lines(ctx.data.get("log"))
  if #log > 0 and y < draw.height - 70 then
    draw.line(x, y + 4, x + cardW, y + 4, color.BLACK)
    draw.text(x, y + 28, T(ctx, "Zuletzt gesendet", "Last sent"), "small", color.BLACK, "left"); y = y + 36
    for i = 1, math.min(#log, 3) do
      local ts, msg = log[i]:match("^(%d+)|(.*)$")
      if ts then
        if y > draw.height - 24 then break end
        draw.text(x, y + 14, cut(msg, cardW - 120, "small"), "small", color.BLACK, "left")
        draw.text(x + cardW, y + 14, ago(ctx, tonumber(ts)), "small", color.BLACK, "right")
        y = y + 24
      end
    end
  end
end

function on_draw(ctx, page)
  if tostring(ctx.cfg.channel or "ntfy") ~= "mail" and tostring(ctx.cfg.topic or "") == "" then
    draw.clear(color.WHITE)
    local cx = draw.width // 2
    draw.text(cx, 150, T(ctx, "Noch nicht eingerichtet", "Not set up yet"), "large", color.BLACK, "center")
    draw.wrap(80, 210, draw.width - 160, T(ctx, "1. iPhone-App „ntfy“ installieren\n2. Ein eigenes Thema abonnieren (langer, zufälliger Name)\n3. Denselben Namen hier unter „Thema“ eintragen", "1. Install the “ntfy” iPhone app\n2. Subscribe to your own topic (a long random name)\n3. Enter the same name here under “Topic”"), "normal", color.BLACK)
    return
  end
  drawBody(ctx, ctx.cfg.style or "cards")
end

function on_widget(ctx, box)
  local act, n, err = summary(ctx)
  local ok = (#act == 0) and err == ""
  local r = math.min(14, box.h // 4)
  draw.circle(box.x + 12 + r, box.y + box.h // 2, r, ok and color.GREEN or color.RED, true)
  draw.circle(box.x + 12 + r, box.y + box.h // 2, r, color.BLACK, false)
  local tx = box.x + 26 + 2 * r
  if ok then
    draw.text(tx, box.y + box.h // 2 + 8, T(ctx, "Alles ok", "All good"), "large", color.BLACK, "left")
  else
    local txt = (#act > 0) and act[1] or err
    draw.text(tx, box.y + box.h // 2 - 2, #act .. T(ctx, " Warnung(en)", " warning(s)"), "normal", color.BLACK, "left")
    draw.text(tx, box.y + box.h // 2 + 22, cut(txt, box.x + box.w - tx - 8, "small"), "small", color.BLACK, "left")
  end
end
