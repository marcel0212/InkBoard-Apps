-- Homeoffice: Fokus-Timer (Pomodoro), Pausen-/Bewegungserinnerung und Stand-up-Timer in einer App.
-- Bedienung am Drehgeber: Drehen wechselt die Ansicht, Klick startet/bestaetigt, zweimal Klick (innerhalb 3 s) beendet den Fokus-Timer.
-- Alles wird aus Zeitstempeln berechnet (E-Paper zeichnet nur beim Refresh). Skript-API Level 10 (on_input).

local ARM_SECONDS = 3
local EXERCISES_DE = {
  "Aufstehen und strecken",
  "Schultern kreisen, Nacken dehnen",
  "Ein Glas Wasser trinken",
  "Fenster auf: 5 mal tief durchatmen",
  "20 Sekunden in die Ferne schauen",
  "Eine Runde durch die Wohnung gehen",
  "10 Kniebeugen",
  "Handgelenke und Finger lockern",
}
local EXERCISES_EN = {
  "Stand up and stretch",
  "Roll your shoulders, stretch your neck",
  "Drink a glass of water",
  "Open the window: 5 deep breaths",
  "Look 20 seconds into the distance",
  "Walk a lap around the flat",
  "Do 10 squats",
  "Loosen your wrists and fingers",
}

local function tx(ctx, de, en)
  if ctx.lang == "en" then return en end
  return de
end

local function cfgn(ctx, key, def, lo, hi)
  local v = tonumber(ctx.cfg[key])
  if v == nil then v = def end
  v = math.floor(v)
  if v < lo then v = lo end
  if v > hi then v = hi end
  return v
end

local function num(ctx, key, def)
  local v = ctx.data.get(key)
  if type(v) == "number" then return v end
  return def
end

local function enabledViews(ctx)
  local l = {}
  if ctx.cfg.showFocus ~= false then l[#l + 1] = "focus" end
  if ctx.cfg.showBreak ~= false then l[#l + 1] = "break" end
  if ctx.cfg.showStand ~= false then l[#l + 1] = "stand" end
  if #l == 0 then l = {"focus", "break", "stand"} end
  return l
end

local function viewIndex(ctx, count)
  local v = num(ctx, "v", 1)
  v = math.floor(v)
  if v < 1 or v > count then v = 1 end
  return v
end

-- ---------------------------------------------------------------- Zeit

local function dayCount(ctx, key)
  local t = time.today()
  if t ~= nil and ctx.data.get("d") == t then return num(ctx, key, 0) end
  return 0
end

-- nur in on_fetch/on_input: neuer Tag setzt die Tageszaehler zurueck
local function rollDay(ctx)
  local t = time.today()
  if t == nil then return end
  if ctx.data.get("d") ~= t then
    ctx.data.set("d", t)
    ctx.data.set("fn", 0)
    ctx.data.set("bc", 0)
    ctx.data.set("s_tot", 0)
  end
end

local function hm(sec)
  sec = math.floor(sec)
  if sec < 0 then sec = 0 end
  local h = sec // 3600
  local m = (sec % 3600) // 60
  if h > 0 then return string.format("%d:%02d h", h, m) end
  return string.format("%d min", m)
end

local function clockText(ctx, minutesOfDay)
  local h = (minutesOfDay // 60) % 24
  local m = minutesOfDay % 60
  if ctx.clock24 == false then
    local ap = h >= 12 and "PM" or "AM"
    h = h % 12
    if h == 0 then h = 12 end
    return string.format("%d:%02d %s", h, m, ap)
  end
  return string.format("%02d:%02d", h, m)
end

local function endClock(ctx, lt, remSec)
  if lt == nil then return "" end
  return clockText(ctx, lt.hour * 60 + lt.min + math.ceil(remSec / 60))
end

-- Arbeitszeit: Stunden von/bis, optional nur Mo-Fr
local function workWindow(ctx, now, lt)
  local s = cfgn(ctx, "workStart", 8, 0, 23)
  local e = cfgn(ctx, "workEnd", 18, 1, 24)
  if lt == nil then return true, now end
  local inW = lt.hour >= s and lt.hour < e
  if ctx.cfg.weekdaysOnly ~= false and (lt.wday == 0 or lt.wday == 6) then inW = false end
  local startTs = now - (lt.hour * 3600 + lt.min * 60 + lt.sec) + s * 3600
  return inW, startTs
end

-- ---------------------------------------------------------------- Zustaende

local function focusState(ctx, now)
  local f0 = ctx.data.get("f0")
  if type(f0) ~= "number" then return nil end
  local work = cfgn(ctx, "focusMin", 25, 5, 90) * 60
  local short = cfgn(ctx, "shortMin", 5, 1, 30) * 60
  local long = cfgn(ctx, "longMin", 15, 5, 60) * 60
  local rounds = cfgn(ctx, "rounds", 4, 2, 8)
  local cycle = rounds * work + (rounds - 1) * short + long
  local el = now - f0
  if el < 0 then el = 0 end
  local base = (el // cycle) * rounds
  local e = el % cycle
  for i = 1, rounds do
    if e < work then
      return {kind = "work", round = i, rounds = rounds, rem = work - e, total = work, done = base + i - 1}
    end
    e = e - work
    local bl = (i < rounds) and short or long
    if e < bl then
      return {kind = (i < rounds) and "short" or "long", round = i, rounds = rounds, rem = bl - e, total = bl, done = base + i}
    end
    e = e - bl
  end
  return {kind = "work", round = 1, rounds = rounds, rem = work, total = work, done = base}
end

-- Pomodoros dieses Tages: gespeicherter Zaehler + noch nicht gebuchte der laufenden Sitzung
local function focusToday(ctx, st)
  local n = dayCount(ctx, "fn")
  if st ~= nil then
    local extra = st.done - num(ctx, "fc", 0)
    if extra > 0 then n = n + extra end
  end
  return n
end

local function breakState(ctx, now, lt)
  local every = cfgn(ctx, "breakEvery", 60, 15, 240) * 60
  local inW, wstart = workWindow(ctx, now, lt)
  if not inW then return {state = "off", count = dayCount(ctx, "bc")} end
  local last = num(ctx, "b0", 0)
  if last < wstart then last = wstart end
  local el = now - last
  if el < 0 then el = 0 end
  local rem = every - el
  return {state = (rem <= 0) and "due" or "wait", rem = rem, el = el, every = every, count = dayCount(ctx, "bc")}
end

local function exerciseText(ctx, lt, count)
  local list = (ctx.lang == "en") and EXERCISES_EN or EXERCISES_DE
  local day = lt and lt.day or 0
  return list[(count + day) % #list + 1]
end

local function standState(ctx, now, lt)
  local mode = ctx.data.get("s_m")
  if mode ~= "stand" then mode = "sit" end
  local since = num(ctx, "s_t", now)
  local sit = cfgn(ctx, "sitMin", 45, 10, 180) * 60
  local stand = cfgn(ctx, "standMin", 15, 5, 90) * 60
  local limit = (mode == "sit") and sit or stand
  local el = now - since
  if el < 0 then el = 0 end
  local tot = dayCount(ctx, "s_tot") + ((mode == "stand") and el or 0)
  local inW = workWindow(ctx, now, lt)
  if not inW then return {state = "off", mode = mode, total = tot} end
  local rem = limit - el
  return {state = (rem <= 0) and "due" or "wait", mode = mode, rem = rem, el = el, limit = limit, total = tot}
end

-- ---------------------------------------------------------------- Modelle (Text + Zahlen je Ansicht)

local function minutesLeft(sec)
  if sec <= 0 then return 0 end
  return math.ceil(sec / 60)
end

local function overdueText(sec)
  return "+" .. tostring(math.floor(-sec / 60))
end

local function focusModel(ctx, now, lt)
  local st = focusState(ctx, now)
  local today = focusToday(ctx, st)
  local fm = cfgn(ctx, "focusMin", 25, 5, 90)
  local m = {kind = "focus", icon = "clock", frac = 0, alert = false, good = false}
  m.title = tx(ctx, "Fokus-Timer", "Focus timer")
  local todayTxt = tx(ctx, "Heute: ", "Today: ") .. today .. (today == 1 and " Pomodoro" or " Pomodoros")
  if st == nil then
    m.label = tx(ctx, "Bereit", "Ready")
    m.big = tostring(fm)
    m.unit = "min"
    m.sub = todayTxt
    m.sub2 = ""
    m.hint = tx(ctx, "Klick: Fokus starten", "Click: start focus")
    m.short = tx(ctx, "Fokus bereit", "Focus ready")
    return m
  end
  m.frac = (st.total - st.rem) / st.total
  m.big = tostring(minutesLeft(st.rem))
  m.unit = "min"
  m.sub = tx(ctx, "Fertig um ", "Done at ") .. endClock(ctx, lt, st.rem)
  m.sub2 = todayTxt
  m.hint = tx(ctx, "Klick, 2. Klick binnen 3 s: beenden", "Click, 2nd click within 3 s: stop")
  if st.kind == "work" then
    m.label = tx(ctx, "Fokus - Runde ", "Focus - round ") .. st.round .. "/" .. st.rounds
    m.short = tx(ctx, "Fokus ", "Focus ") .. m.big .. " min"
  else
    m.good = true
    m.label = (st.kind == "long") and tx(ctx, "Lange Pause", "Long break") or tx(ctx, "Kurze Pause", "Short break")
    m.icon = "heart"
    m.short = tx(ctx, "Pause ", "Break ") .. m.big .. " min"
  end
  return m
end

local function breakModel(ctx, now, lt)
  local b = breakState(ctx, now, lt)
  local m = {kind = "break", icon = "bell", frac = 0, alert = false, good = false}
  m.title = tx(ctx, "Pause & Bewegung", "Break & movement")
  local cnt = tx(ctx, "Heute: ", "Today: ") .. b.count .. tx(ctx, " Pausen", " breaks")
  if b.state == "off" then
    m.label = tx(ctx, "Feierabend", "Off duty")
    m.big = "-"
    m.unit = ""
    m.sub = tx(ctx, "Außerhalb der Arbeitszeit", "Outside working hours")
    m.sub2 = cnt
    m.hint = tx(ctx, "Klick: Pause gemacht", "Click: break done")
    m.short = tx(ctx, "Pause: Feierabend", "Break: off duty")
    return m
  end
  local ex = exerciseText(ctx, lt, b.count)
  m.hint = tx(ctx, "Klick: Pause gemacht", "Click: break done")
  m.sub2 = cnt
  if b.state == "due" then
    m.alert = true
    m.label = tx(ctx, "Zeit für eine Pause!", "Time for a break!")
    m.big = overdueText(b.rem)
    m.unit = "min"
    m.sub = ex
    m.frac = 1
    m.short = tx(ctx, "Pause fällig!", "Break due!")
  else
    m.label = tx(ctx, "Nächste Pause in", "Next break in")
    m.big = tostring(minutesLeft(b.rem))
    m.unit = "min"
    m.sub = tx(ctx, "Idee: ", "Idea: ") .. ex
    m.frac = b.el / b.every
    m.short = tx(ctx, "Pause in ", "Break in ") .. m.big .. " min"
  end
  return m
end

local function standModel(ctx, now, lt)
  local s = standState(ctx, now, lt)
  local m = {kind = "stand", icon = "arrow_up", frac = 0, alert = false, good = false}
  m.title = tx(ctx, "Stand-up-Timer", "Stand-up timer")
  m.sub2 = tx(ctx, "Heute gestanden: ", "Standing today: ") .. hm(s.total)
  if s.state == "off" then
    m.label = tx(ctx, "Feierabend", "Off duty")
    m.big = "-"
    m.unit = ""
    m.sub = tx(ctx, "Außerhalb der Arbeitszeit", "Outside working hours")
    m.hint = (s.mode == "stand") and tx(ctx, "Klick: Hinsetzen", "Click: sit down") or tx(ctx, "Klick: Aufstehen", "Click: stand up")
    m.short = tx(ctx, "Stehen: Feierabend", "Stand: off duty")
    return m
  end
  m.frac = s.el / s.limit
  if m.frac > 1 then m.frac = 1 end
  if s.mode == "sit" then
    m.hint = tx(ctx, "Klick: Jetzt aufstehen", "Click: stand up now")
    if s.state == "due" then
      m.alert = true
      m.label = tx(ctx, "Zeit zum Aufstehen!", "Time to stand up!")
      m.big = overdueText(s.rem)
      m.unit = "min"
      m.sub = tx(ctx, "Seit ", "Sitting for ") .. hm(s.el) .. tx(ctx, " am Stück sitzend", "")
      m.short = tx(ctx, "Aufstehen!", "Stand up!")
    else
      m.label = tx(ctx, "Sitzen - noch", "Sitting - another")
      m.big = tostring(minutesLeft(s.rem))
      m.unit = "min"
      m.sub = tx(ctx, "Dann 1x aufstehen (", "Then stand for ") .. math.floor(cfgn(ctx, "standMin", 15, 5, 90)) .. " min" .. tx(ctx, ")", "")
      m.short = tx(ctx, "Stehen in ", "Stand in ") .. m.big .. " min"
    end
  else
    m.icon = "user"
    m.hint = tx(ctx, "Klick: Hinsetzen", "Click: sit down")
    if s.state == "due" then
      m.good = true
      m.label = tx(ctx, "Genug gestanden", "Enough standing")
      m.big = overdueText(s.rem)
      m.unit = "min"
      m.sub = tx(ctx, "Du darfst dich wieder setzen", "You may sit down again")
      m.short = tx(ctx, "Hinsetzen", "Sit down")
    else
      m.good = true
      m.label = tx(ctx, "Stehen - noch", "Standing - another")
      m.big = tostring(minutesLeft(s.rem))
      m.unit = "min"
      m.sub = tx(ctx, "Gut so, weiter stehen", "Nice, keep standing")
      m.short = tx(ctx, "Stehen ", "Standing ") .. m.big .. " min"
    end
  end
  return m
end

local function buildModel(ctx, kind, now, lt)
  if kind == "focus" then return focusModel(ctx, now, lt) end
  if kind == "break" then return breakModel(ctx, now, lt) end
  return standModel(ctx, now, lt)
end

-- Beispieldaten fuer die Vorschau im Dashboard-Editor (ctx.sample): Uhr und Zustaende gestellt
local function sampleContext(ctx)
  local now = 1790000000
  local lt = {year = 2026, month = 9, day = 21, hour = 10, min = 30, sec = 0, wday = 1, week = 39}
  local store = {d = "2026-09-21", f0 = now - 9 * 60, fc = 0, fn = 2, b0 = now - 61 * 60, bc = 3, s_m = "sit", s_t = now - 33 * 60, s_tot = 25 * 60}
  local proxy = {cfg = ctx.cfg, lang = ctx.lang, clock24 = ctx.clock24, data = {get = function(k) return store[k] end}}
  return proxy, now, lt
end

local function modelsFor(ctx)
  local lt = time.localtime()
  local now = time.now()
  local c = ctx
  if ctx.sample then
    c, now, lt = sampleContext(ctx)
  end
  if now == nil or now < 100000 then return nil end
  local views = enabledViews(ctx)
  local list = {}
  for i = 1, #views do list[i] = buildModel(c, views[i], now, lt) end
  return list
end

-- ---------------------------------------------------------------- Zeichnen (Seite)

local function bar(x, y, w, h, frac, col)
  if frac < 0 then frac = 0 end
  if frac > 1 then frac = 1 end
  draw.rect(x, y, w, h, color.BLACK, false, h // 2)
  local fw = math.floor((w - 4) * frac)
  if fw > h - 4 then
    draw.rect(x + 2, y + 2, fw, h - 4, col, true, (h - 4) // 2)
  elseif fw > 2 then
    draw.rect(x + 2, y + 2, fw, h - 4, col, true)
  end
end

local function accentFor(m)
  if m.alert then return color.RED end
  if m.good then return color.GREEN end
  return color.ACCENT
end

local function bigScale(t, unit, avail)
  for k = 3, 2, -1 do
    local uw = (unit ~= "") and (draw.measure(unit, "large") + 16) or 0
    if draw.measure(t, "huge", k) + uw <= avail then return k end
  end
  return 1
end

local function tabs(ctx, models, idx, y, style)
  local n = #models
  if draw.height > draw.width and style ~= "nano" then
    -- Hochformat: nur der aktive Reiter als Pille, darunter Punkte fuer alle Ansichten
    local t = models[idx].title
    local w = math.min(draw.width - 40, draw.measure(t, "small") + 44)
    draw.rect((draw.width - w) // 2, y, w, 36, color.ACCENT, true, 18)
    draw.text(draw.width // 2, y + 25, t, "small", color.ACCENT_INK, "center")
    for i = 1, n do
      local cx = draw.width // 2 + (i - (n + 1) / 2) * 22
      draw.circle(math.floor(cx), y + 52, 5, (i == idx) and color.ACCENT or color.BLACK, i == idx)
    end
    return
  end
  local gap = 10
  local w = (n == 1) and 200 or 170
  local total = n * w + (n - 1) * gap
  local x = (draw.width - total) // 2
  for i = 1, n do
    local m = models[i]
    local active = (i == idx)
    if style == "nano" then
      local cx = draw.width // 2 + (i - (n + 1) / 2) * 22
      draw.circle(math.floor(cx), y + 10, 6, active and color.ACCENT or color.BLACK, active)
    else
      if active then
        draw.rect(x, y, w, 36, color.ACCENT, true, 18)
        draw.text(x + w // 2, y + 25, m.title, "small", color.ACCENT_INK, "center")
      else
        draw.rect(x, y, w, 36, color.BLACK, false, 18)
        draw.text(x + w // 2, y + 25, m.title, "small", color.BLACK, "center")
      end
      x = x + w + gap
    end
  end
end

local function drawBento(ctx, m, models, idx)
  local col = accentFor(m)
  tabs(ctx, models, idx, draw.top + 12, "bento")
  local tall = draw.height > draw.width
  local cx, cy, cw, ch = 40, draw.top + 64, draw.width - 80, 306
  if tall then cx, cy, cw, ch = 24, draw.top + 84, draw.width - 48, draw.height - draw.top - 84 - 50 end
  draw.rect(cx, cy, cw, ch, color.BLACK, false, 20)
  draw.rect(cx + 1, cy + 1, cw - 2, ch - 2, color.BLACK, false, 19)
  draw.rect(cx + 24, cy + 16, 110, 8, col, true, 4)
  draw.icon(m.icon, cx + cw - 66, cy + 20, 40, col)
  draw.text(cx + 30, cy + 66, m.label, "large", m.alert and color.RED or color.BLACK, "left")
  local bsc = bigScale(m.big, m.unit, cw - 60)
  local by = tall and (cy + ch // 2 + 40) or (cy + 206)
  draw.text(cx + 30, by, m.big, "huge", col == color.ACCENT and color.ACCENT_TEXT or col, "left", bsc)
  local bw = draw.measure(m.big, "huge", bsc)
  if m.unit ~= "" then draw.text(cx + 30 + bw + 16, by, m.unit, "large", color.BLACK, "left") end
  if tall then
    draw.wrap(cx + 30, by + 50, cw - 60, m.sub, "normal", color.BLACK)
    draw.text(cx + 30, cy + 104, m.sub2, "small", color.BLACK, "left")
  else
    draw.text(cx + 30, cy + 246, m.sub, "normal", color.BLACK, "left")
    draw.text(cx + cw - 80, cy + 120, m.sub2, "small", color.BLACK, "right")
  end
  bar(cx + 30, cy + ch - 34, cw - 60, 18, m.frac, col)
  draw.text(draw.width // 2, draw.height - 22, m.hint .. "   |   " .. tx(ctx, "Drehen: Ansicht", "Turn: switch view"), "small", color.BLACK, "center")
end

local function drawSlate(ctx, m, models, idx)
  local col = accentFor(m)
  tabs(ctx, models, idx, draw.top + 12, "slate")
  local x = 60
  local tall = draw.height > draw.width
  local d = tall and 200 or 0   -- Hochformat: alles unter dem Label um d nach unten, Sub2 unter dem Label
  draw.rect(24, draw.top + 70, 14, 300 + (tall and 300 or 0), col, true)
  draw.text(x, draw.top + 106, m.label, "large", m.alert and color.RED or color.BLACK, "left")
  local bsc = bigScale(m.big, m.unit, draw.width - 2 * x - 10)
  draw.text(x, draw.top + 250 + d, m.big, "huge", color.BLACK, "left", bsc)
  local bw = draw.measure(m.big, "huge", bsc)
  if m.unit ~= "" then draw.text(x + bw + 16, draw.top + 250 + d, m.unit, "large", col == color.ACCENT and color.ACCENT_TEXT or col, "left") end
  draw.line(x, draw.top + 276 + d, draw.width - 60, draw.top + 276 + d, color.BLACK)
  draw.wrap(x, draw.top + 310 + d, draw.width - 120, m.sub, "normal", color.BLACK)
  if tall then draw.text(x, draw.top + 140, m.sub2, "small", color.BLACK, "left")
  else draw.text(draw.width - 60, draw.top + 106, m.sub2, "small", color.BLACK, "right") end
  bar(x, draw.top + 350 + d + (tall and 60 or 0), draw.width - 120, 14, m.frac, col)
  draw.text(draw.width // 2, draw.height - 22, m.hint .. "   |   " .. tx(ctx, "Drehen: Ansicht", "Turn: switch view"), "small", color.BLACK, "center")
end

local function drawNano(ctx, m, models, idx)
  local col = accentFor(m)
  tabs(ctx, models, idx, draw.top + 18, "nano")
  local cx = draw.width // 2
  local top0 = draw.top + ((draw.height > draw.width) and 150 or 0)
  draw.icon(m.icon, cx - 20, top0 + 52, 40, col)
  draw.text(cx, top0 + 128, m.label, "medium", m.alert and color.RED or color.BLACK, "center")
  local bw = draw.measure(m.big, "huge", 2)
  local uw = (m.unit ~= "") and (draw.measure(m.unit, "large") + 14) or 0
  local x = cx - (bw + uw) // 2
  draw.text(x, top0 + 236, m.big, "huge", col == color.ACCENT and color.ACCENT_TEXT or col, "left", 2)
  if m.unit ~= "" then draw.text(x + bw + 14, top0 + 236, m.unit, "large", color.BLACK, "left") end
  bar(math.max(30, cx - 260), top0 + 262, math.min(520, draw.width - 60), 12, m.frac, col)
  draw.text(cx, top0 + 308, m.sub, "normal", color.BLACK, "center")
  draw.text(cx, top0 + 336, m.sub2, "small", color.BLACK, "center")
  draw.text(cx, draw.height - 22, m.hint, "small", color.BLACK, "center")
end

function on_draw(ctx, page)
  draw.clear(color.WHITE)
  local models = modelsFor(ctx)
  if models == nil then
    draw.text(draw.width // 2, 280, tx(ctx, "Uhr nicht gestellt - warte auf Zeit ...", "Clock not set - waiting for time ..."), "medium", color.BLACK, "center")
    return
  end
  local idx = viewIndex(ctx, #models)
  local m = models[idx]
  local style = ctx.cfg.style
  if style == "slate" then drawSlate(ctx, m, models, idx)
  elseif style == "nano" then drawNano(ctx, m, models, idx)
  else drawBento(ctx, m, models, idx) end
  local arm = ctx.data.get("arm")
  local now = time.now()
  if m.kind == "focus" and type(arm) == "number" and now ~= nil and now - arm >= 0 and now - arm <= ARM_SECONDS then
    draw.rect(draw.width // 2 - 230, draw.height - 80, 460, 44, color.RED, true, 22)
    draw.text(draw.width // 2, draw.height - 50, tx(ctx, "Nochmal klicken zum Beenden", "Click again to stop"), "normal", color.WHITE, "center")
  end
end

-- ---------------------------------------------------------------- Widget

local function fnt(b, base)
  local t = b and b.font or 0
  if t < 0 and base == "normal" then return "small" end
  if t > 0 and base == "small" then return "normal" end
  return base
end

-- dringendste Ansicht: faellige Erinnerung > laufender Fokus-Timer > erste aktive Ansicht
local function pickUrgent(models)
  local best = models[1]
  for i = 1, #models do
    if models[i].alert then return models[i] end
  end
  for i = 1, #models do
    if models[i].kind == "focus" and models[i].frac > 0 then best = models[i] end
  end
  return best
end

function on_widget(ctx, box)
  local models = modelsFor(ctx)
  if models == nil then
    draw.text(box.x + box.w // 2, box.y + box.h // 2, tx(ctx, "Noch keine Daten", "No data yet"), "small", color.BLACK, "center")
    return
  end
  local style = box.style
  local rowH = 44
  if #models > 0 then rowH = math.min(58, math.max(44, box.h // #models)) end
  if box.fh >= 96 and #models > 1 and box.h >= 44 * #models then
    -- alle Ansichten als Zeilen mit Fortschrittsbalken
    local y = box.y + 4
    for i = 1, #models do
      local m = models[i]
      local col = accentFor(m)
      if style == "cards" then
        draw.rect(box.x + 4, y, box.w - 8, rowH - 6, color.BLACK, false, 10)
      elseif style == "flat" and i > 1 then
        draw.line(box.x + 6, y - 2, box.x + box.w - 6, y - 2, color.BLACK)
      end
      draw.icon(m.icon, box.x + 12, y + 6, 24, col)
      draw.text(box.x + 46, y + 20, m.short, fnt(box, "normal"), m.alert and color.RED or color.BLACK, "left")
      if style ~= "compact" then
        bar(box.x + 46, y + 26, box.w - 70, 8, m.frac, col)
      end
      y = y + rowH
    end
  else
    local m = pickUrgent(models)
    local col = accentFor(m)
    draw.icon(m.icon, box.x + 10, box.y + 8, 28, col)
    draw.text(box.x + 48, box.y + 28, m.label, fnt(box, "small"), m.alert and color.RED or color.BLACK, "left")
    local big = m.big .. ((m.unit ~= "") and (" " .. m.unit) or "")
    draw.text(box.x + 12, box.y + box.h // 2 + 26, big, "large", col == color.ACCENT and color.ACCENT_TEXT or col, "left")
    if box.h >= 80 then bar(box.x + 12, box.y + box.h - 18, box.w - 24, 8, m.frac, col) end
  end
end

-- ---------------------------------------------------------------- Abruf & Eingabe

local function syncFocus(ctx, now)
  local st = focusState(ctx, now)
  if st == nil then return end
  local fc = num(ctx, "fc", 0)
  if st.done > fc then
    ctx.data.set("fn", num(ctx, "fn", 0) + (st.done - fc))
    ctx.data.set("fc", st.done)
  end
end

function on_fetch(ctx)
  local now = time.now()
  if now == nil or now < 100000 then return false end
  rollDay(ctx)
  syncFocus(ctx, now)
  if type(ctx.data.get("s_t")) ~= "number" then ctx.data.set("s_t", now) end
  return true
end

function on_input(ctx, kind, n)
  local now = time.now()
  if now == nil or now < 100000 then return false end
  rollDay(ctx)
  local views = enabledViews(ctx)
  local idx = viewIndex(ctx, #views)
  if kind == "turn" then
    if #views < 2 then return false end
    idx = ((idx - 1 + n) % #views) + 1
    ctx.data.set("v", idx)
    ctx.data.set("arm", nil)
    return true
  end
  local view = views[idx]
  if view == "focus" then
    local f0 = ctx.data.get("f0")
    if type(f0) ~= "number" then
      ctx.data.set("f0", now)
      ctx.data.set("fc", 0)
      return true
    end
    local armed = ctx.data.get("arm")
    if type(armed) == "number" and now - armed >= 0 and now - armed <= ARM_SECONDS then
      syncFocus(ctx, now)
      ctx.data.set("f0", nil)
      ctx.data.set("fc", 0)
      ctx.data.set("arm", nil)
      return true
    end
    ctx.data.set("arm", now)
    return true
  elseif view == "break" then
    ctx.data.set("b0", now)
    ctx.data.set("bc", num(ctx, "bc", 0) + 1)
    return true
  else
    local mode = ctx.data.get("s_m")
    local since = num(ctx, "s_t", now)
    if mode == "stand" then
      local el = now - since
      if el < 0 then el = 0 end
      if el > 4 * 3600 then el = 4 * 3600 end
      ctx.data.set("s_tot", num(ctx, "s_tot", 0) + el)
      ctx.data.set("s_m", "sit")
    else
      ctx.data.set("s_m", "stand")
    end
    ctx.data.set("s_t", now)
    return true
  end
end
