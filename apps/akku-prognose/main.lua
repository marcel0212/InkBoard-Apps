-- Akku-Prognose mit Spar-Berater (Paket akku-prognose): sammelt Akkuwerte, rechnet die Restlaufzeit hoch und sagt,
-- welche Einstellung am meisten Laufzeit bringt. Skript-API Level 27 (system.get/system.settings, nur lesend; ab 27 mit Ruhezeiten).
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

-- Vorschlaege: Liste { key, text(de/en), gain } nach Nutzen sortiert, plus Gesamtergebnis
local function advise(an, en)
  local st = an.st
  local out = { tips = {} }
  if st == nil then return out end
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
  local list = {}
  local viewLabel = st.dashboard and (en and "Dashboard interval" or "Dashboard-Intervall") or (en and "App interval" or "App-Intervall")
  local nv = next_step(st.view_min)
  if nv and st.view_min < 120 then
    local r = eval(nv, st.sensor_log_min)
    if r.cut > 0 then
      r.text = string.format("%s %d -> %d Min.", viewLabel, st.view_min, nv)
      list[#list + 1] = r
    end
  end
  local ns = next_step(st.sensor_log_min)
  if ns and st.sensor_log_min < st.view_min and st.sensor_log_min < 120 then
    local target = math.min(ns, st.view_min)
    local r = eval(st.view_min, target)
    if r.cut > 0 then
      r.text = string.format(en and "Sensor log %d -> %d min" or "Sensor-Verlauf %d -> %d Min.", st.sensor_log_min, target)
      list[#list + 1] = r
    end
  end
  table.sort(list, function(a, b) return a.cut > b.cut end)
  out.list = list
  local v2 = nv or st.view_min
  local s2 = math.min(v2, 180)
  if s2 < st.sensor_log_min then s2 = st.sensor_log_min end
  local all = eval(v2, s2)
  if all.cut > ((list[1] and list[1].cut) or 0) then out.all = all end
  if an.sys.wifi and an.sys.rssi <= -75 then
    out.tips[#out.tips + 1] = en and "Weak Wi-Fi: every connection takes longer and costs battery" or "Schwacher WLAN-Empfang: jede Verbindung dauert länger und kostet Akku"
  end
  if st.ui_window_min > 3 then
    out.tips[#out.tips + 1] = string.format(en and "Operating window %d min: shorter saves battery after button wake" or "Bedienfenster %d Min.: kürzer spart Akku nach Tasterweckung", st.ui_window_min)
  end
  -- Ruhezeiten: ohne Nachtruhe/Abwesend weckt das Geraet rund um die Uhr (Schaetzung der eingesparten Weckungen)
  do
    local q = (st.quiet_pct or 0) / 100
    if st.night_on == false then
      local cut = math.floor((8 / 24) / (1 - q) * 100 * (1 - q) + 0.5)
      out.tips[#out.tips + 1] = string.format(en and "Night quiet (e.g. 22-06): about %d%% fewer wake-ups" or "Nachtruhe (z. B. 22-06 Uhr): ca. %d%% weniger Weckungen", cut)
    end
    if st.away_on == false then
      local cut = math.floor((9 * 5 / 168) * 100 + 0.5)
      out.tips[#out.tips + 1] = string.format(en and "Away (work, Mon-Fri 8-17): about %d%% fewer wake-ups" or "Abwesend (Arbeit, Mo-Fr 8-17 Uhr): ca. %d%% weniger Weckungen", cut)
    end
  end
  if st.minimal then
    out.tips[#out.tips + 1] = en and "Minimal mode is active (after crashes): wake every 60 min" or "Minimalmodus aktiv (nach Abstürzen): Weckung nur alle 60 Min."
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
    draw.text(draw.width // 2, top + 196, en and "Firmware update needed (API 25)" or "Firmware-Update nötig (API 25)", "normal", color.BLACK, "center")
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
    draw.text(draw.width // 2, top + 180, en and "Firmware update needed (API 25)" or "Firmware-Update nötig (API 25)", "normal", color.BLACK, "center")
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
  for i = 1, math.min(3, #adv.list) do
    local r = adv.list[i]
    draw.rect(40, y, draw.width - 80, 64, color.BLACK, false, 12)
    draw.text(58, y + 28, cut(r.text, 470, "normal"), "normal", color.BLACK, "left")
    local gain
    if r.days and an.days then
      gain = string.format("+%s", fmt_days(math.max(0, r.days - an.days), en))
      draw.text(draw.width - 58, y + 30, gain, "large", color.GREEN, "right")
      draw.text(58, y + 54, string.format(en and "%s -> %s, %d%% fewer wake-ups" or "%s -> %s, %d%% weniger Weckungen", fmt_days(an.days, en), fmt_days(r.days, en), r.cut), "small", color.BLACK, "left")
    else
      draw.text(draw.width - 58, y + 30, string.format(en and "-%d%% wake-ups" or "-%d%% Weckungen", r.cut), "normal", color.GREEN, "right")
    end
    y = y + 72
  end
  if adv.all and adv.all.days and an.days then
    draw.rect(40, y, draw.width - 80, 56, color.GREEN, true, 12)
    draw.text(58, y + 36, string.format(en and "All together: %s -> %s" or "Alles zusammen: %s -> %s", fmt_days(an.days, en), fmt_days(adv.all.days, en)), "large", color.BLACK, "left")
    y = y + 64
  end
  for i = 1, #adv.tips do
    if y > draw.height - 40 then break end
    draw.text(44, y + 22, cut("- " .. adv.tips[i], draw.width - 88, "small"), "small", color.BLACK, "left")
    y = y + 26
  end
  local st = an.st
  draw.text(40, draw.height - 40, string.format(en and "Now: wake %d min, view %d min, sensor log %d min" or "Aktuell: Weckabstand %d Min., Anzeige %d Min., Sensor-Verlauf %d Min.", st.wake_min, st.view_min, st.sensor_log_min), "small", color.BLACK, "left")
  draw.text(40, draw.height - 12, en and "Estimate based on your own readings" or "Schätzung nach deinen eigenen Messwerten", "small", color.BLACK, "left")
end

function on_draw(ctx, page)
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
