-- Tuerschild (Paket tuerschild): zeigt am Display vor dem Zimmer, ob jemand da ist, im Meeting sitzt oder nicht gestoert werden will.
-- Skript-API Level 20 (on_http). Der Status kommt von aussen:
--   * Mac-App (Werkzeug "Tuerschild"): liest den Kalender (laufender Termin) und optional den Fokus-Status und schickt ihn alle paar Minuten,
--   * Handy-Seite des Geraets (QR-Code im Leerzustand, assets/phone.html): Schnellwahl per Knopf,
--   * jedes andere Programm per POST /app/tuerschild/api (Node-RED, Kurzbefehle ...).
-- Anfrage (JSON): {"op":"set","st":"free|busy|meeting|dnd|away|focus|custom","title":"Text","text":"Zusatzzeile","until":<unix>,"untilText":"14:30","next":"Text"}
--                 {"op":"clear"} | {"op":"get"}
-- Laeuft "until" ab, faellt die Anzeige auf den Rueckfall-Status (Einstellung "fallback") zurueck - ein vergessenes "Nicht stoeren" bleibt so nie stehen.

local KINDS = {
  free    = { de = "Frei",                en = "Free" },
  busy    = { de = "Beschäftigt",         en = "Busy" },
  meeting = { de = "Im Meeting",          en = "In a meeting" },
  dnd     = { de = "Bitte nicht stören",  en = "Do not disturb" },
  away    = { de = "Nicht da",            en = "Away" },
  focus   = { de = "Fokus-Zeit",          en = "Focus time" },
  custom  = { de = "",                    en = "" },
}

local function T(ctx, de, en) return (ctx.lang == "en") and en or de end

local function kindColor(k)
  if k == "free" then return color.GREEN, color.WHITE end
  if k == "busy" or k == "meeting" or k == "dnd" then return color.RED, color.WHITE end
  if k == "away" then return color.YELLOW, color.BLACK end
  if k == "focus" then return color.BLUE, color.WHITE end
  return color.ACCENT, color.ACCENT_INK
end

local function clean(t, max)
  t = tostring(t or ""):gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if #t > max then
    local i = max
    while i > 1 and (t:byte(i + 1) or 0) & 0xC0 == 0x80 do i = i - 1 end
    t = t:sub(1, i)
  end
  return t
end

local function esc(s) return (tostring(s or ""):gsub('[%c"\\]', function(c) if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" end return " " end)) end

-- ===== Zustand =====

local function current(ctx)
  local st = tostring(ctx.data.get("st") or "")
  local until_ = tonumber(ctx.data.get("until")) or 0
  local now = time.now() or 0
  if st ~= "" and until_ > 0 and now > 0 and now >= until_ then st = "" end -- abgelaufen
  local s = { st = st, title = tostring(ctx.data.get("ttl") or ""), text = tostring(ctx.data.get("txt") or ""),
              untilText = tostring(ctx.data.get("unt") or ""), next = tostring(ctx.data.get("nxt") or "") }
  if st == "" then
    local fb = (ctx.cfg and ctx.cfg.fallback) or "free"
    if fb == "none" then s.st = ""; s.text = ""; s.untilText = ""; s.title = ""; s.next = tostring(ctx.data.get("nxt") or "") ; return s end
    s.st = fb; s.title = ""; s.text = ""; s.untilText = ""
  end
  return s
end

local function label(ctx, s)
  if s.st == "" then return T(ctx, "Kein Status", "No status") end
  if s.title ~= "" then return s.title end
  local k = KINDS[s.st] or KINDS.custom
  local t = (ctx.lang == "en") and k.en or k.de
  if t == "" then t = T(ctx, "Hinweis", "Note") end
  return t
end

-- Schrift waehlen, die in die Breite passt
local function fit(text, maxW, fonts)
  for i = 1, #fonts do
    if draw.measure(text, fonts[i]) <= maxW then return fonts[i] end
  end
  return fonts[#fonts]
end

-- "huge" kann nur Ziffern: Statustext in "large" mit Vergroesserung (Skalierung), soweit er in die Breite passt
local function bigFit(text, maxW, maxScale)
  for sc = maxScale, 2, -1 do if draw.measure(text, "large", sc) <= maxW then return "large", sc end end
  for _, f in ipairs({ "large", "medium", "normal" }) do if draw.measure(text, f) <= maxW then return f, 1 end end
  return "normal", 1
end

local function untilLine(ctx, s)
  if s.untilText == "" then return "" end
  return T(ctx, "bis ", "until ") .. s.untilText
end

-- ===== Stile =====

local function drawBento(ctx, s)
  local bg, ink = kindColor(s.st)
  draw.clear(color.WHITE)
  local x, y, w, h = 36, draw.top + 12, draw.width - 72, draw.height - draw.top - 40
  draw.rect(x, y, w, h, color.WHITE, true, 22)
  draw.rect(x, y, w, h, color.BLACK, false, 22)
  draw.rect(x + 10, y + 10, 16, h - 20, bg, true, 8)
  local left = x + 50
  local inner = x + w - 28 - left
  local name = tostring(ctx.cfg.name or "")
  if name ~= "" and ctx.cfg.showName ~= false then
    draw.text(left, y + 48, name, fit(name, inner - 56, { "large", "medium", "normal" }), color.BLACK, "left")
  end
  draw.circle(x + w - 60, y + 52, 22, bg, true)
  draw.circle(x + w - 60, y + 52, 22, color.BLACK, false)
  local t = label(ctx, s)
  local f, sc = bigFit(t, inner, 2)
  draw.text(left, y + h // 2 + 22, t, f, bg == color.YELLOW and color.BLACK or bg, "left", sc)
  local sub = s.text
  local ul = untilLine(ctx, s)
  local ly = y + h // 2 + 70
  if sub ~= "" then draw.wrap(left, ly, inner, sub, "normal", color.BLACK); ly = ly + 34 end
  if ul ~= "" and ctx.cfg.showUntil ~= false then
    local cw = draw.measure(ul, "normal") + 28
    draw.rect(left, y + h - 92, cw, 36, bg, true, 14)
    draw.text(left + 14, y + h - 66, ul, "normal", ink, "left")
  end
  if s.next ~= "" then
    draw.line(left, y + h - 44, x + w - 28, y + h - 44, color.BLACK)
    draw.text(left, y + h - 16, T(ctx, "Danach: ", "Next: ") .. s.next, "small", color.BLACK, "left")
  end
end

local function drawSlate(ctx, s)
  local bg, ink = kindColor(s.st)
  draw.clear(bg)
  local cx = draw.width // 2
  local name = tostring(ctx.cfg.name or "")
  if name ~= "" and ctx.cfg.showName ~= false then
    draw.text(cx, draw.top + 52, name, "large", ink, "center")
  end
  local t = label(ctx, s)
  local f, sc = bigFit(t, draw.width - 80, 3)
  draw.text(cx, draw.height // 2 + 28, t, f, ink, "center", sc)
  local ul = untilLine(ctx, s)
  local y = draw.height // 2 + 84
  if s.text ~= "" then draw.text(cx, y, s.text, fit(s.text, draw.width - 40, { "medium", "normal", "small" }), ink, "center"); y = y + 40 end
  if ul ~= "" and ctx.cfg.showUntil ~= false then draw.text(cx, y, ul, "large", ink, "center") end
  if s.next ~= "" then draw.text(cx, draw.height - 22, T(ctx, "Danach: ", "Next: ") .. s.next, "normal", ink, "center") end
end

local function drawNano(ctx, s)
  local bg = kindColor(s.st)
  draw.clear(color.WHITE)
  local x = 56
  draw.circle(x + 30, draw.top + 90, 30, bg, true)
  draw.circle(x + 30, draw.top + 90, 30, color.BLACK, false)
  local t = label(ctx, s)
  local f = fit(t, draw.width - x - 120, { "large", "medium", "normal" })
  draw.text(x + 90, draw.top + 90 + 10, t, f, color.BLACK, "left")
  local y = draw.top + 160
  local name = tostring(ctx.cfg.name or "")
  if name ~= "" and ctx.cfg.showName ~= false then draw.text(x, y, name, "normal", color.BLACK, "left"); y = y + 36 end
  if s.text ~= "" then draw.wrap(x, y, draw.width - 2 * x, s.text, "normal", color.BLACK); y = y + 36 end
  local ul = untilLine(ctx, s)
  if ul ~= "" and ctx.cfg.showUntil ~= false then draw.text(x, y, ul, "normal", color.ACCENT_TEXT, "left"); y = y + 36 end
  if s.next ~= "" then draw.text(x, draw.height - 26, T(ctx, "Danach: ", "Next: ") .. s.next, "small", color.BLACK, "left") end
end

function on_draw(ctx, page)
  local s = current(ctx)
  if ctx.data.get("ts") == nil then
    -- noch nie ein Status gesendet: Hinweis mit QR-Code zur Handy-Seite, damit man ihn einrichten kann
    if ctx.cfg.setupHint ~= false and device.qrscreen(T(ctx, "Türschild einrichten", "Set up door sign"), T(ctx, "Status setzen: QR-Code scannen", "Set status: scan the QR code")) then return end
  end
  local style = ctx.cfg.style or "cards"
  if style == "flat" then drawSlate(ctx, s)
  elseif style == "compact" then drawNano(ctx, s)
  else drawBento(ctx, s) end
end

function on_widget(ctx, box)
  local s = current(ctx)
  local bg, ink = kindColor(s.st)
  local style = ctx.cfg.style or "cards"
  local t = label(ctx, s)
  local ul = untilLine(ctx, s)
  if style == "flat" then
    draw.rect(box.x + 2, box.y + 2, box.w - 4, box.h - 4, bg, true, 10)
    local f = fit(t, box.w - 20, { "large", "normal", "small" })
    draw.text(box.x + box.w // 2, box.y + box.h // 2 + (ul ~= "" and 2 or 8), t, f, ink, "center")
    if ul ~= "" then draw.text(box.x + box.w // 2, box.y + box.h // 2 + 26, ul, "small", ink, "center") end
    return
  end
  local r = math.min(14, box.h // 4)
  draw.circle(box.x + 12 + r, box.y + box.h // 2, r, bg, true)
  draw.circle(box.x + 12 + r, box.y + box.h // 2, r, color.BLACK, false)
  local tx = box.x + 24 + 2 * r
  local f = fit(t, box.x + box.w - tx - 8, { "large", "normal", "small" })
  draw.text(tx, box.y + box.h // 2 + ((ul ~= "" or style == "cards") and 0 or 8), t, f, color.BLACK, "left")
  if ul ~= "" then draw.text(tx, box.y + box.h // 2 + 22, ul, "small", color.BLACK, "left") end
end

-- ===== Handy-Seite / Programmierschnittstelle =====

local function stateJson(ctx)
  local s = current(ctx)
  return string.format('{"st":"%s","title":"%s","text":"%s","until":%d,"untilText":"%s","next":"%s","ts":%d}',
    esc(s.st), esc(s.title), esc(s.text), tonumber(ctx.data.get("until")) or 0, esc(s.untilText), esc(s.next), tonumber(ctx.data.get("ts")) or 0)
end

function on_http(ctx, req)
  local q = json.decode(req.body or "")
  if type(q) ~= "table" then return { status = 400, body = '{"error":"JSON"}' } end
  local op = tostring(q.op or "get")
  if op == "set" then
    local st = tostring(q.st or "custom")
    if KINDS[st] == nil then st = "custom" end
    local now = time.now() or 0
    local u = tonumber(q["until"]) or 0
    if u > 0 and now > 0 and u > now + 14 * 86400 then u = 0 end -- unsinnig weit in der Zukunft
    ctx.data.set("st", st)
    ctx.data.set("ttl", clean(q.title, 40))
    ctx.data.set("txt", clean(q.text, 80))
    ctx.data.set("until", u > 0 and u or 0)
    ctx.data.set("unt", u > 0 and clean(q.untilText, 12) or "")
    ctx.data.set("nxt", clean(q.next, 60))
    ctx.data.set("ts", now > 0 and now or 1)
    return { status = 200, body = stateJson(ctx), redraw = true }
  elseif op == "clear" then
    ctx.data.set("st", ""); ctx.data.set("ttl", ""); ctx.data.set("txt", ""); ctx.data.set("until", 0); ctx.data.set("unt", ""); ctx.data.set("nxt", "")
    ctx.data.set("ts", time.now() or 1)
    return { status = 200, body = stateJson(ctx), redraw = true }
  end
  return { status = 200, body = stateJson(ctx) }
end

-- Der Status laeuft von selbst ab: ein Takt pro Minute zeichnet neu, sobald "until" vorbei ist.
function on_fetch(ctx)
  return true
end
