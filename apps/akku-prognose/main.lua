-- Akku-Prognose mit Spar-Berater (Paket akku-prognose): sammelt Akkuwerte, rechnet die Restlaufzeit hoch und sagt,
-- welche Einstellung am meisten Laufzeit bringt. Skript-API Level 25 (system.get/system.settings, nur lesend; ab 27 mit Ruhezeiten;
-- ab Firmware v2.2.1 / API 28 zusaetzlich system.apps(): der Berater prueft dann auch jede installierte App und das Dashboard).
-- Kein KI-Modell auf dem Geraet: einfaches Verbrauchsmodell (Grundverbrauch + Kosten je Weckung), alles lokal.
-- Messwerte: Datei "samples" (Zeilen "epoch prozent weckabstand"), gelernte Kosten je Weckung: Datei "cal".
-- on_fetch laeuft nur, solange die App angezeigt wird oder als Widget platziert ist (Firmware-Regel) - dann sammelt sie.

local BASE = 0.3      -- Grundverbrauch im Tiefschlaf (Prozent je Tag), grob
local RESERVE = 5     -- "leer" = 5 %
local LADDER = { 5, 10, 15, 20, 30, 45, 60, 90, 120, 180 }
local MAXS = 64

local function en_of(ctx) return ctx.lang == "en" end

local function load_samples()
  local t = {}
  local txt = file.read("samples")
  if txt then
    for a, b, c in txt:gmatch("(%d+) ([%d%.]+) (%d+)") do
      t[#t + 1] = { t = tonumber(a), p = tonumber(b), w = tonumber(c) }
    end
  end
  return t
end

local function save_samples(t)
  local parts = {}
  for i = 1, #t do parts[i] = string.format("%d %.1f %d", t[i].t, t[i].p, t[i].w) end
  return file.write("samples", table.concat(parts, "\n"))
end

local function thin(t)
  if #t <= MAXS then return t end
  local r = {}
  for i = 2, #t, 2 do r[#r + 1] = t[i] end
  if r[#r] ~= t[#t] then r[#r + 1] = t[#t] end
  return r
end

-- Entladerate in Prozent je Tag aus den Messwerten (kleinste Quadrate), nil solange zu wenig Daten
local function fit(t)
  local n = #t
  if n < 4 then return nil end
  local span = t[n].t - t[1].t
  if span < 3 * 3600 then return nil end
  local sx, sy, sxx, sxy = 0, 0, 0, 0
  for i = 1, n do
    local x = (t[i].t - t[1].t) / 3600
    sx = sx + x; sy = sy + t[i].p; sxx = sxx + x * x; sxy = sxy + x * t[i].p
  end
  local den = n * sxx - sx * sx
  if den <= 0 then return nil end
  local slope = (n * sxy - sx * sy) / den   -- Prozent je Stunde
  local rate = -slope * 24
  if rate < 0.05 then return nil end
  return rate
end

local function next_step(v)
  for i = 1, #LADDER do
    if LADDER[i] >= v * 1.4 then return LADDER[i] end
  end
  return nil
end

local function days_parts(d, en)
  if d == nil then return "-", "" end
  if d < 1 then return string.format("%d", math.max(1, math.floor(d * 24 + 0.5))), (en and "h" or "Std.") end
  if d < 10 then
    local n = string.format("%.1f", d)
    if not en then n = n:gsub("%.", ",") end
    return n, (en and "d" or "Tg.")
  end
  if d > 400 then return ">400", (en and "d" or "Tg.") end
  return string.format("%d", math.floor(d + 0.5)), (en and "d" or "Tg.")
end

local function fmt_days(d, en)
  local n, u = days_parts(d, en)
  if u == "" then return n end
  return n .. " " .. u
end

-- Gesamtauswertung: pct, rate (gemessen, %/Tag), c (Kosten je Weckung), days (Restlaufzeit), measured
local function analyse()
  local s = system.get()
  if s == nil then return nil end
  local st = system.settings()
  local an = { sys = s, st = st, n = 0 }
  if system.apps then
    local okA, list = pcall(system.apps)
    if okA and type(list) == "table" then an.apps = list end
  end
  if s.battery ~= nil then an.pct = s.battery end
  local t = load_samples()
  an.samples = t
  an.n = #t
  if #t >= 2 then an.span = t[#t].t - t[1].t else an.span = 0 end
  an.rate = fit(t)
  local calTxt = file.read("cal")
  an.cal = calTxt and tonumber(calTxt) or nil
  -- Ruhezeiten (Nachtruhe, Abwesend) weckt das Geraet nicht: nur der Rest des Tages zaehlt (API 27)
  local q = (st and st.quiet_pct or 0) / 100
  an.q = q
  local W = (st and st.wake_min and st.wake_min > 0) and (1440 / st.wake_min) * (1 - q) or nil
  an.W = W
  if an.rate and W then
    an.c = (an.rate - BASE) / W
    if an.c < 0.001 then an.c = 0.001 end
  elseif an.cal then
    an.c = an.cal
  end
  local D = an.rate
  an.measured = D ~= nil
  if D == nil and an.c and W then D = BASE + W * an.c end
  an.drain = D
  if D and an.pct then
    local days = (an.pct - RESERVE) / D
    if days < 0 then days = 0 end
    an.days = days
  end
  return an
end

-- Wecktakt aus Ansichts- und Sensorintervall (wie die Firmware: App sichtbar = nur Ansichtsintervall)
local function wake_of(st, view, sens)
  if (not st.dashboard) and st.apps > 0 then return view end
  return math.min(sens, view)
end

local function floor5(v) if v < 5 then return 5 end return v end

local function app_name(a)
  if a.name and a.name ~= "" then return a.name end
  return a.id or "?"
end

-- Vorschlaege: Liste { text, where, cut (% weniger Weckungen), days (nur fuer die gerade sichtbare Ansicht), other } nach Nutzen sortiert,
-- plus Gesamtergebnis und weitere Hinweise. Geprueft werden: sichtbare Ansicht (App oder Dashboard), Dashboard-Takt, Sensor-Verlauf,
-- jede eingeschaltete App (Aktualisierung), Wetter, Netz, Bedienfenster, Ruhezeiten, WLAN, Widgets, Hintergrund-Apps, Akku-Stufe.
local function advise(an, en)
  local st = an.st
  local out = { tips = {} }
  if st == nil then return out end
  local apps = an.apps or {}
  local W = an.W
  local old = wake_of(st, st.view_min, st.sensor_log_min)
  local function eval(view, sens)
    local nw = wake_of(st, view, sens)
    local wake = st.wake_min
    if old > 0 then wake = st.wake_min * nw / old end
    local W2 = (1440 / wake) * (1 - (st.quiet_pct or 0) / 100)
    local r = { view = view, sens = sens, wake = wake, cut = W and math.floor((1 - W2 / W) * 100 + 0.5) or 0 }
    if an.c and an.pct then
      r.drain = BASE + W2 * an.c
      r.days = (an.pct - RESERVE) / r.drain
    end
    return r
  end
  local cur
  for i = 1, #apps do if apps[i].current then cur = apps[i] end end
  local list = {}
  local nv = next_step(st.view_min)
  if nv and st.view_min < 120 then
    local r = eval(nv, st.sensor_log_min)
    if r.cut > 0 then
      if st.dashboard then
        r.text = string.format(en and "Refresh the dashboard every %d instead of %d min" or "Dashboard alle %d statt %d Min. aktualisieren", nv, st.view_min)
        r.where = en and "Set in: Dashboard > Auto-refresh every (minutes)" or "Einstellen: Dashboard > Automatisch aktualisieren alle (Minuten)"
      elseif cur then
        r.text = string.format(en and 'Refresh "%s" every %d instead of %d min' or 'App "%s" alle %d statt %d Min. aktualisieren', app_name(cur), nv, st.view_min)
        r.where = en and "Set in: Store > the app > Refresh (min)" or "Einstellen: Store > die App > Aktualisierung (Min.)"
      else
        r.text = string.format(en and "Refresh the open app every %d instead of %d min" or "Geöffnete App alle %d statt %d Min. aktualisieren", nv, st.view_min)
        r.where = en and "Set in: Store > the app > Refresh (min)" or "Einstellen: Store > die App > Aktualisierung (Min.)"
      end
      list[#list + 1] = r
    end
  end
  local ns = next_step(st.sensor_log_min)
  if ns and st.sensor_log_min < st.view_min and st.sensor_log_min < 120 then
    local target = math.min(ns, st.view_min)
    local r = eval(st.view_min, target)
    if r.cut > 0 then
      r.text = string.format(en and "Measure the sensor every %d instead of %d min" or "Sensor alle %d statt %d Min. messen", target, st.sensor_log_min)
      r.where = en and "Set in: Settings > Battery mode > Sensor/history interval" or "Einstellen: Einstellungen > Akkubetrieb > Sensor-/Verlaufsintervall"
      list[#list + 1] = r
    end
  end
  -- Ansichten, auf denen das Geraet gerade NICHT steht: gilt, sobald man dorthin wechselt und das Geraet dort schlafen geht
  local function other(text, where, oldw, neww, dash)
    local rawOld = oldw
    oldw, neww = floor5(oldw), floor5(neww)
    if neww <= oldw then return end
    list[#list + 1] = { text = text, where = where, cut = math.floor((1 - oldw / neww) * 100 + 0.5), other = true, low = rawOld, dash = dash }
  end
  local dash_now = st.dashboard or st.apps == 0
  if not dash_now and (st.dashboard_min or 0) > 0 then
    local dm, sm = st.dashboard_min, st.sensor_log_min
    local ndm = next_step(dm)
    if ndm and dm < sm and dm < 120 then
      other(string.format(en and "Refresh the dashboard every %d instead of %d min" or "Dashboard alle %d statt %d Min. aktualisieren", math.min(ndm, sm), dm),
        en and "Set in: Dashboard > Auto-refresh every (minutes)" or "Einstellen: Dashboard > Automatisch aktualisieren alle (Minuten)", dm, math.min(ndm, sm), true)
    end
    local nsm = next_step(sm)
    if nsm and sm < dm and sm < 120 then
      other(string.format(en and "Measure the sensor every %d instead of %d min" or "Sensor alle %d statt %d Min. messen", math.min(nsm, dm), sm),
        en and "Set in: Settings > Battery mode > Sensor/history interval" or "Einstellen: Einstellungen > Akkubetrieb > Sensor-/Verlaufsintervall", sm, math.min(nsm, dm), true)
    end
  end
  local nbg, nfast = 0, 0
  for i = 1, #apps do
    local a = apps[i]
    if a.enabled and a.bg then nbg = nbg + 1 end
    if a.enabled and not a.current and a.refresh_min and a.refresh_min < 30 then
      local na = next_step(floor5(a.refresh_min))   -- unter 5 Min. weckt das Geraet ohnehin nicht (Untergrenze)
      if na then
        nfast = nfast + 1
        other(string.format(en and 'App "%s": every %d instead of %d min' or 'App "%s" alle %d statt %d Min.', app_name(a), na, a.refresh_min),
          en and "Set in: Store > the app > Refresh (min)" or "Einstellen: Store > die App > Aktualisierung (Min.)", a.refresh_min, na)
      end
    end
  end
  for i = 1, #list do list[i].idx = i end
  -- erst die Ansicht, auf der das Geraet gerade steht, dann die anderen (jeweils nach Nutzen)
  table.sort(list, function(a, b)
    if (a.other or false) ~= (b.other or false) then return not a.other end
    if a.cut ~= b.cut then return a.cut > b.cut end
    if (a.low or 0) ~= (b.low or 0) then return (a.low or 0) < (b.low or 0) end
    return a.idx < b.idx
  end)
  out.list = list
  local v2 = nv or st.view_min
  local s2 = math.min(v2, 180)
  if s2 < st.sensor_log_min then s2 = st.sensor_log_min end
  local all = eval(v2, s2)
  local best_now = 0
  for i = 1, #list do if not list[i].other and list[i].cut > best_now then best_now = list[i].cut end end
  if all.cut > best_now then out.all = all end
  local tips = out.tips
  local function tip(t) tips[#tips + 1] = t end
  if an.sys.wifi and an.sys.rssi <= -75 then
    tip(en and "Weak Wi-Fi: every connection takes longer and costs battery" or "Schwacher WLAN-Empfang: jede Verbindung dauert länger und kostet Akku")
  end
  if st.ui_window_min > 3 then
    tip(string.format(en and "Operating window %d min: shorter saves battery after button wake" or "Bedienfenster %d Min.: kürzer spart Akku nach Tasterweckung", st.ui_window_min))
  end
  if (st.weather_min or 0) > 0 and st.weather_min < 30 then
    tip(string.format(en and "Weather fetch every %d min: 30 min or more saves radio time" or "Wetterabruf alle %d Min.: ab 30 Min. spart Funkzeit", st.weather_min))
  end
  if (st.net_min or 0) > 0 and st.net_min < 30 then
    tip(string.format(en and "Network upload every %d min: 30 min or more saves radio time" or "Netz-Takt %d Min.: ab 30 Min. spart Funkzeit", st.net_min))
  end
  if (st.widgets or 0) >= 6 then
    tip(string.format(en and "Dashboard with %d widgets: fewer widgets means less loading and drawing" or "Dashboard mit %d Widgets: weniger Widgets heißt weniger Laden und Zeichnen", st.widgets))
  end
  if nbg >= 2 then
    tip(string.format(en and "%d apps fetch in the background: each wake-up connects Wi-Fi longer" or "%d Apps rufen im Hintergrund ab: jede Weckung hält das WLAN länger an", nbg))
  end
  if (st.stage or 0) > 0 then
    tip(en and "Battery low: the device already stretches its wake interval" or "Akku niedrig: das Gerät streckt den Wecktakt bereits automatisch")
  end
  -- Ruhezeiten: ohne Nachtruhe/Abwesend weckt das Geraet rund um die Uhr (Schaetzung der eingesparten Weckungen)
  do
    local q = (st.quiet_pct or 0) / 100
    if st.night_on == false then
      local cut = math.floor((8 / 24) / (1 - q) * 100 * (1 - q) + 0.5)
      tip(string.format(en and "Night quiet (e.g. 22-06): about %d%% fewer wake-ups" or "Nachtruhe (z. B. 22-06 Uhr): ca. %d%% weniger Weckungen", cut))
    end
    if st.away_on == false then
      local cut = math.floor((9 * 5 / 168) * 100 + 0.5)
      tip(string.format(en and "Away (work, Mon-Fri 8-17): about %d%% fewer wake-ups" or "Abwesend (Arbeit, Mo-Fr 8-17 Uhr): ca. %d%% weniger Weckungen", cut))
    end
  end
  if st.minimal then
    tip(en and "Minimal mode is active (after crashes): wake every 60 min" or "Minimalmodus aktiv (nach Abstürzen): Weckung nur alle 60 Min.")
  end
  return out
end

local function on_fetch_impl()
  local s = system.get()
  local st = system.settings()
  if s == nil or st == nil or not s.clock_ok or s.battery == nil or not s.on_battery then return true end
  local t = load_samples()
  local last = t[#t]
  if last and s.now - last.t < 600 then return true end
  if last and (s.battery > last.p + 2 or last.w ~= st.wake_min) then
    -- Ladevorgang oder anderer Wecktakt: gelernte Kosten je Weckung sichern, neue Reihe beginnen
    local rate = fit(t)
    if rate and last.w > 0 then
      local c = (rate - BASE) / (1440 / last.w)
      if c >= 0.001 then file.write("cal", string.format("%.5f", c)) end
    end
    t = {}
  end
  t[#t + 1] = { t = s.now, p = s.battery, w = st.wake_min }
  t = thin(t)
  local rate = fit(t)
  if rate and st.wake_min > 0 then
    local c = (rate - BASE) / ((1440 / st.wake_min) * (1 - (st.quiet_pct or 0) / 100))
    if c >= 0.001 then file.write("cal", string.format("%.5f", c)) end
  end
  save_samples(t)
  return true
end

function on_fetch(ctx)
  return on_fetch_impl()
end

-- ===== Zeichnen =====

local function pct_color(p)
  if p == nil then return color.BLACK end
  if p <= 15 then return color.RED end
  if p <= 40 then return color.YELLOW end
  return color.GREEN
end

local function battery_icon(x, y, w, h, p)
  draw.rect(x, y, w - 5, h, color.BLACK, false, 4)
  draw.rect(x + w - 5, y + h // 3, 5, h // 3, color.BLACK, true)
  if p then
    local fw = math.floor((w - 12) * math.max(0, math.min(100, p)) / 100)
    if fw > 0 then draw.rect(x + 4, y + 4, fw, h - 8, pct_color(p), true, 2) end
  end
end

local function cut(text, maxw, font)
  while #text > 1 and draw.measure(text, font) > maxw do
    local i = #text
    while i > 1 and (text:byte(i) & 0xC0) == 0x80 do i = i - 1 end
    text = text:sub(1, i - 1)
  end
  return text
end

local function empty_date(days, en)
  local s = system.get()
  if not days or days > 365 or not s then return nil end
  local d = time.date(math.floor(s.now + days * 86400))
  if not d then return nil end
  return string.format("%02d.%02d.%04d", d.day, d.month, d.year)
end

local function no_data(ctx, x, y, w, h, msg)
  draw.text(x + w // 2, y + h // 2, msg, "normal", color.BLACK, "center")
end

-- Verlaufsgraf: Messpunkte + gestrichelte Prognose bis "leer"
local function chart(an, x, y, w, h, en)
  draw.rect(x, y, w, h, color.BLACK, false, 6)
  local t = an.samples
  if #t < 2 then
    draw.text(x + w // 2, y + h // 2 + 6, en and "collecting data" or "sammle Messwerte", "small", color.BLACK, "center")
    return
  end
  local s = an.sys
  local t0 = t[1].t
  local t1 = s.now
  local tEnd = t1
  if an.rate and an.days then tEnd = t1 + math.min(an.days, 30) * 86400 end
  if tEnd - t0 < 3600 then tEnd = t0 + 3600 end
  local px, py, pw, ph = x + 8, y + 8, w - 16, h - 16
  local function X(tt) return px + math.floor(pw * (tt - t0) / (tEnd - t0)) end
  local function Y(p) return py + math.floor(ph * (100 - math.max(0, math.min(100, p))) / 100) end
  draw.line(px, Y(RESERVE), px + pw, Y(RESERVE), color.RED)
  for i = 2, #t do draw.line(X(t[i - 1].t), Y(t[i - 1].p), X(t[i].t), Y(t[i].p), color.BLACK) end
  if an.rate and an.pct then
    local ex = X(t1 + math.min(an.days or 0, 30) * 86400)
    local x0, y0 = X(t1), Y(an.pct)
    local steps = 12
    for i = 0, steps - 1, 2 do
      local xa = x0 + (ex - x0) * i // steps
      local xb = x0 + (ex - x0) * (i + 1) // steps
      local ya = y0 + (Y(RESERVE) - y0) * i // steps
      local yb = y0 + (Y(RESERVE) - y0) * (i + 1) // steps
      draw.line(xa, ya, xb, yb, color.BLUE)
    end
  end
  draw.circle(X(t1), Y(an.pct or t[#t].p), 4, color.BLACK, true)
end

local function status_line(an, en)
  local s = an.sys
  if not s.on_battery then return en and "Mains powered - no forecast needed" or "Netzbetrieb - keine Prognose nötig" end
  if s.battery == nil then return en and "No battery reading" or "Kein Akku-Messwert" end
  if not s.clock_ok then return en and "Clock not set" or "Uhr nicht gestellt" end
  if an.days == nil then
    if an.span < 3 * 3600 then
      local left = math.max(1, math.ceil((3 * 3600 - an.span) / 3600))
      return string.format(en and "Collecting data, about %d h to go" or "Sammle Messwerte, noch ca. %d Std.", left)
    end
    return en and "Battery not draining (charging?)" or "Akku entlädt sich nicht (lädt?)"
  end
  if not an.measured then return en and "Estimate from earlier measurement" or "Schätzung aus früherer Messung" end
  return nil
end

local function page_forecast(ctx)
  local en = en_of(ctx)
  local style = ctx.cfg.style or "cards"
  draw.clear(color.WHITE)
  local an = analyse()
  local top = draw.top
  if an == nil then
    draw.text(draw.width // 2, top + 160, en and "Device state not available" or "Gerätezustand nicht verfügbar", "large", color.BLACK, "center")
    draw.text(draw.width // 2, top + 196, en and "Firmware update needed" or "Firmware-Update nötig", "normal", color.BLACK, "center")
    return
  end
  local note = status_line(an, en)
  local pct = an.pct
  local daysTxt = fmt_days(an.days, en)
  local pctTxt = pct and string.format("%d %%", math.floor(pct + 0.5)) or "-"
  local rateTxt = an.drain and string.format(en and "%.1f %%/day" or "%.1f %%/Tag", an.drain):gsub("%.", en and "." or ",") or "-"
  local emptyTxt = empty_date(an.days, en) or "-"
  if style == "compact" then
    battery_icon(draw.width // 2 - 60, top + 30, 120, 48, pct)
    draw.text(draw.width // 2, top + 150, pctTxt, "large", color.BLACK, "center")
    local dn, du = days_parts(an.days, en)
    draw.text(draw.width // 2, top + 250, dn, "huge", pct_color(pct), "center", 2)
    draw.text(draw.width // 2, top + 325, du, "large", pct_color(pct), "center")
    draw.text(draw.width // 2, top + 375, en and "estimated runtime" or "geschätzte Restlaufzeit", "normal", color.BLACK, "center")
    if note then draw.text(draw.width // 2, top + 420, cut(note, draw.width - 60, "normal"), "normal", color.BLACK, "center") end
    return
  end
  if style == "flat" then
    local rows = {
      { en and "Battery" or "Akku", pctTxt },
      { en and "Runtime" or "Restlaufzeit", an.days and ("ca. " .. daysTxt) or "-" },
      { en and "Drain" or "Verbrauch", rateTxt },
      { en and "Empty around" or "Leer etwa", emptyTxt },
      { en and "Wake interval" or "Weckabstand", an.st and string.format((an.st.quiet_pct or 0) > 0 and (en and "%d min, quiet %d%%" or "%d Min., Ruhe %d%%") or "%d Min.", an.st.wake_min, an.st.quiet_pct or 0) or "-" },
      { en and "Readings" or "Messwerte", tostring(an.n) },
    }
    local y = top + 12
    for i = 1, #rows do
      draw.text(40, y + 36, rows[i][1], "normal", color.BLACK, "left")
      draw.text(draw.width - 40, y + 36, rows[i][2], "large", i == 2 and pct_color(pct) or color.BLACK, "right")
      draw.line(40, y + 52, draw.width - 40, y + 52, color.BLACK)
      y = y + 56
    end
    if note then draw.text(40, y + 30, cut(note, draw.width - 80, "normal"), "normal", color.BLACK, "left") end
    return
  end
  -- Bento
  local gap = 12
  local lw = 300
  draw.rect(24, top + 10, lw, 140, color.BLACK, false, 14)
  battery_icon(44, top + 28, 90, 36, pct)
  draw.text(150, top + 58, pctTxt, "large", color.BLACK, "left")
  draw.text(44, top + 110, en and "Battery" or "Akku", "normal", color.BLACK, "left")
  draw.text(44, top + 138, an.st and (string.format(en and "wakes every %d min" or "weckt alle %d Min.", an.st.wake_min) .. (((an.st.quiet_pct or 0) > 0) and string.format(en and ", quiet %d%%" or ", Ruhe %d%%", an.st.quiet_pct) or "")) or "", "small", color.BLACK, "left")
  local rx = 24 + lw + gap
  local rw = draw.width - rx - 24
  draw.rect(rx, top + 10, rw, 140, pct_color(pct), an.days ~= nil, 14)
  draw.rect(rx, top + 10, rw, 140, color.BLACK, false, 14)
  draw.text(rx + 24, top + 44, en and "Estimated runtime" or "Geschätzte Restlaufzeit", "normal", color.BLACK, "left")
  local dn, du = days_parts(an.days, en)
  draw.text(rx + 24, top + 112, dn, "huge", color.BLACK, "left")
  if du ~= "" then draw.text(rx + 24 + draw.measure(dn, "huge") + 14, top + 112, du, "large", color.BLACK, "left") end
  draw.text(rx + rw - 24, top + 138, rateTxt, "small", color.BLACK, "right")
  chart(an, 24, top + 10 + 140 + gap, draw.width - 48, draw.height - top - 10 - 140 - gap - 50, en)
  local ny = draw.height - 18
  draw.text(28, ny, note or ((en and "Empty around " or "Leer etwa ") .. emptyTxt), "normal", color.BLACK, "left")
end

local function page_advisor(ctx)
  local en = en_of(ctx)
  draw.clear(color.WHITE)
  local an = analyse()
  local top = draw.top
  if an == nil or an.st == nil then
    draw.text(draw.width // 2, top + 180, en and "Firmware update needed" or "Firmware-Update nötig", "normal", color.BLACK, "center")
    return
  end
  if not an.sys.on_battery then
    draw.text(draw.width // 2, top + 180, en and "The advisor applies to battery mode" or "Der Berater gilt für den Akkubetrieb", "normal", color.BLACK, "center")
    return
  end
  local adv = advise(an, en)
  draw.text(40, top + 40, en and "Saving advisor" or "Spar-Berater", "large", color.BLACK, "left")
  local sub
  if an.days then
    sub = string.format(en and "Now: about %s" or "Jetzt: ca. %s", fmt_days(an.days, en))
  else
    sub = en and "Runtime needs about 3 h of readings" or "Laufzeit-Rechnung braucht ca. 3 Std. Messwerte"
  end
  draw.text(draw.width - 40, top + 38, cut(sub, 420, "normal"), "normal", color.BLACK, "right")
  draw.line(40, top + 52, draw.width - 40, top + 52, color.BLACK)
  local y = top + 66
  if #adv.list == 0 and #adv.tips == 0 then
    draw.rect(40, y, draw.width - 80, 70, color.GREEN, true, 14)
    draw.text(draw.width // 2, y + 44, en and "Settings are already frugal" or "Die Einstellungen sind bereits sparsam", "large", color.BLACK, "center")
    return
  end
  for i = 1, math.min(adv.all and 2 or 3, #adv.list) do
    local r = adv.list[i]
    draw.rect(40, y, draw.width - 80, 84, color.BLACK, false, 12)
    draw.text(58, y + 28, cut(r.text, 470, "normal"), "normal", color.BLACK, "left")
    if r.where then draw.text(58, y + 76, cut(r.where, draw.width - 116, "small"), "small", color.BLACK, "left") end
    local gain
    if r.days and an.days and not r.other then
      gain = string.format("+%s", fmt_days(math.max(0, r.days - an.days), en))
      draw.text(draw.width - 58, y + 30, gain, "large", color.GREEN, "right")
      draw.text(58, y + 54, string.format(en and "%s -> %s, %d%% fewer wake-ups" or "%s -> %s, %d%% weniger Weckungen", fmt_days(an.days, en), fmt_days(r.days, en), r.cut), "small", color.BLACK, "left")
    else
      draw.text(draw.width - 58, y + 30, string.format(en and "-%d%% wake-ups" or "-%d%% Weckungen", r.cut), "normal", color.GREEN, "right")
      if r.other then
        local msg
        if r.dash then msg = en and "saves battery while the dashboard is shown" or "Spart Akku, solange das Dashboard angezeigt wird"
        else msg = en and "saves battery while this app is shown" or "Spart Akku, solange diese App angezeigt wird" end
        draw.text(58, y + 54, msg, "small", color.BLACK, "left")
      end
    end
    y = y + 92
  end
  if adv.all and adv.all.days and an.days then
    draw.rect(40, y, draw.width - 80, 56, color.GREEN, true, 12)
    draw.text(58, y + 36, string.format(en and "All together: %s -> %s" or "Alles zusammen: %s -> %s", fmt_days(an.days, en), fmt_days(adv.all.days, en)), "large", color.BLACK, "left")
    y = y + 64
  end
  for i = 1, #adv.tips do
    if y + 26 > draw.height - 54 then break end
    draw.text(44, y + 22, cut("- " .. adv.tips[i], draw.width - 88, "small"), "small", color.BLACK, "left")
    y = y + 26
  end
  local st = an.st
  draw.text(40, draw.height - 40, string.format(en and "Now: wake %d min, view %d min, sensor log %d min" or "Aktuell: Weckabstand %d Min., Anzeige %d Min., Sensor-Verlauf %d Min.", st.wake_min, st.view_min, st.sensor_log_min), "small", color.BLACK, "left")
  draw.text(40, draw.height - 12, en and "Estimate based on your own readings" or "Schätzung nach deinen eigenen Messwerten", "small", color.BLACK, "left")
end

-- Seite 3: Einstellungen-Check - alle Einstellungen mit Einfluss auf den Akku und jede eingeschaltete App auf einen Blick (Ampeln)
local function rate_min(v)
  if v == nil or v <= 0 then return nil end
  if v >= 30 then return color.GREEN end
  if v >= 15 then return color.YELLOW end
  return color.RED
end

local function page_check(ctx)
  local en = en_of(ctx)
  draw.clear(color.WHITE)
  local an = analyse()
  local top = draw.top
  if an == nil or an.st == nil then
    draw.text(draw.width // 2, top + 180, en and "Firmware update needed" or "Firmware-Update nötig", "normal", color.BLACK, "center")
    return
  end
  local st, s = an.st, an.sys
  local rows = {}
  local function row(label, value, c) rows[#rows + 1] = { label, value, c } end
  local mn = en and " min" or " Min."
  row(en and "Wake interval (now)" or "Wecktakt (jetzt)", st.wake_min .. mn, rate_min(st.wake_min))
  row(en and "Dashboard refresh" or "Dashboard-Takt", (st.dashboard_min or 0) .. mn, rate_min(st.dashboard_min))
  row(en and "Sensor history" or "Sensor-Verlauf", st.sensor_log_min .. mn, rate_min(st.sensor_log_min))
  row(en and "Weather fetch" or "Wetter-Abruf", (st.weather_min or 0) .. mn, rate_min(st.weather_min))
  row(en and "Network upload" or "Netz-Takt", (st.net_min or 0) .. mn, rate_min(st.net_min))
  local uw = st.ui_window_min or 0
  row(en and "Operating window" or "Bedienfenster", uw .. mn, uw <= 3 and color.GREEN or (uw <= 5 and color.YELLOW or color.RED))
  row(en and "Night quiet" or "Nachtruhe", st.night_on and (en and "on" or "an") or (en and "off" or "aus"), st.night_on and color.GREEN or color.YELLOW)
  row(en and "Away" or "Abwesend", st.away_on and (en and "on" or "an") or (en and "off" or "aus"), st.away_on and color.GREEN or color.YELLOW)
  if s.wifi and s.rssi then
    row(en and "Wi-Fi signal" or "WLAN-Signal", (s.rssi >= -70 and (en and "good" or "gut") or (s.rssi >= -80 and (en and "fair" or "mittel") or (en and "weak" or "schwach"))), s.rssi >= -70 and color.GREEN or (s.rssi >= -80 and color.YELLOW or color.RED))
  end
  local stg = st.stage or 0
  row(en and "Battery stage" or "Akku-Stufe", stg == 0 and (en and "normal" or "normal") or (stg == 1 and (en and "low" or "niedrig") or (en and "critical" or "kritisch")), stg == 0 and color.GREEN or (stg == 1 and color.YELLOW or color.RED))
  if st.minimal then row(en and "Minimal mode" or "Minimalmodus", en and "on" or "an", color.RED) end
  local bad = 0
  for i = 1, #rows do if rows[i][3] == color.RED or rows[i][3] == color.YELLOW then bad = bad + 1 end end

  draw.text(40, top + 40, en and "Settings check" or "Einstellungen-Check", "large", color.BLACK, "left")
  draw.line(40, top + 52, draw.width - 40, top + 52, color.BLACK)
  local lx, lw = 40, 350
  local rx = 420
  local y = top + 64
  for i = 1, #rows do
    local r = rows[i]
    if r[3] then draw.circle(lx + 7, y + 12, 6, r[3], true) end
    draw.text(lx + 22, y + 18, r[1], "small", color.BLACK, "left")
    draw.text(lx + lw, y + 18, r[2], "small", color.BLACK, "right")
    y = y + 27
  end
  -- Apps
  local y2 = top + 64
  if an.apps == nil then
    draw.text(rx, y2 + 18, en and "Update the firmware for the app check" or "Für die App-Prüfung bitte die Firmware aktualisieren", "small", color.BLACK, "left")
  else
    local act = {}
    for i = 1, #an.apps do if an.apps[i].enabled then act[#act + 1] = an.apps[i] end end
    table.sort(act, function(a, b) return (a.refresh_min or 0) < (b.refresh_min or 0) end)
    draw.text(rx, y2 + 18, string.format(en and "Apps (%d active), Dashboard %d widgets" or "Apps (%d aktiv), Dashboard %d Widgets", #act, st.widgets or 0), "small", color.BLACK, "left")
    y2 = y2 + 27
    local maxRows = 8
    for i = 1, math.min(maxRows, #act) do
      local a = act[i]
      local c = rate_min(a.refresh_min)
      if c == color.RED or c == color.YELLOW then bad = bad + 1 end
      if c then draw.circle(rx + 7, y2 + 12, 6, c, true) end
      local nm = (a.current and "> " or "") .. app_name(a)
      local flags = ""
      if a.bg then flags = flags .. (en and " +background" or " +Hintergrund") end
      if (a.widgets or 0) > 0 then flags = flags .. " +" .. a.widgets .. (en and " widget" or " Widget") end
      draw.text(rx + 22, y2 + 18, cut(nm, 175, "small"), "small", color.BLACK, "left")
      draw.text(draw.width - 40, y2 + 18, (a.refresh_min or 0) .. mn .. flags, "small", color.BLACK, "right")
      y2 = y2 + 27
    end
    if #act > maxRows then
      draw.text(rx + 22, y2 + 18, string.format(en and "+ %d more (all at %d min or more)" or "+ %d weitere (ab %d Min.)", #act - maxRows, act[maxRows + 1].refresh_min or 0), "small", color.BLACK, "left")
    end
  end
  local sub
  if bad == 0 then sub = en and "All settings are frugal" or "Alle Einstellungen sind sparsam"
  else sub = string.format(en and "%d points could be improved" or "%d Punkte mit Sparpotenzial", bad) end
  draw.text(draw.width - 40, top + 38, cut(sub, 420, "normal"), "normal", color.BLACK, "right")
  draw.text(40, draw.height - 40, en and "Green: frugal, yellow: could be better, red: costs a lot" or "Grün: sparsam, gelb: ginge besser, rot: kostet viel", "small", color.BLACK, "left")
  draw.text(40, draw.height - 12, en and "H = fetches in the background, W = widgets in the dashboard, > = shown now" or "H = ruft im Hintergrund ab, W = Widgets im Dashboard, > = gerade sichtbar", "small", color.BLACK, "left")
end

function on_draw(ctx, page)
  if page == 3 then return page_check(ctx) end
  if page == 2 then return page_advisor(ctx) end
  return page_forecast(ctx)
end

function on_widget(ctx, box)
  local en = en_of(ctx)
  local an = analyse()
  local cx = box.x + box.w // 2
  if an == nil then
    draw.text(cx, box.y + box.h // 2, en and "No data yet" or "Noch keine Daten", "small", color.BLACK, "center")
    return
  end
  local pct = an.pct
  local pctTxt = pct and string.format("%d %%", math.floor(pct + 0.5)) or "-"
  local style = ctx.cfg.style or "cards"
  local big = an.days and fmt_days(an.days, en) or (an.sys.on_battery and "..." or "~")
  if box.h < 70 or style == "compact" then
    draw.text(cx, box.y + box.h // 2 + 12, big, box.h >= 60 and "large" or "normal", pct_color(pct), "center")
    if box.h >= 60 then draw.text(cx, box.y + box.h - 6, pctTxt, "small", color.BLACK, "center") end
    return
  end
  local iw = math.min(80, box.w - 20)
  battery_icon(cx - iw // 2, box.y + 6, iw, math.min(34, box.h // 4), pct)
  draw.text(cx, box.y + 6 + math.min(34, box.h // 4) + 28, big, "large", pct_color(pct), "center")
  if style == "flat" and box.h >= 110 and an.drain then
    draw.text(cx, box.y + box.h - 8, string.format(en and "%.1f %%/day" or "%.1f %%/Tag", an.drain):gsub("%.", en and "." or ","), "small", color.BLACK, "center")
  else
    draw.text(cx, box.y + box.h - 8, pctTxt, "small", color.BLACK, "center")
  end
end
