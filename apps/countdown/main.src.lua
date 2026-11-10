-- Countdown: zaehlt die Tage bis zu einem Zieldatum herunter.
-- Skript-API Level 1 (siehe docs/V2_APPSTORE.md): draw.*, color.*, time.*, ctx.cfg
--#include theme

local function accentColor(name)
  if name == "green" then return color.GREEN end
  if name == "red" then return color.RED end
  if name == "yellow" then return color.YELLOW end
  if name == "black" then return color.BLACK end
  return color.BLUE
end

-- Relief/Klar: eine grosse Karte mit Bezeichnung, Tageszahl und dem Zieldatum als Pille
local function drawCard(cfg, days, accent)
  local x, y = 40, draw.top + 24
  local w, h = draw.width - 86, draw.height - draw.top - 64
  card(x, y, w, h, accent, theme.s == "relief" and 16 or 24)
  local lx = x + (theme.s == "relief" and 34 or 30)
  local label = cfg.label or ""
  local lf = (draw.measure(label, "large") <= w - 70) and "large" or "medium"
  draw.text(lx, y + 64, label, lf, color.BLACK, "left")
  if days == nil then
    draw.text(lx, y + 160, "Datum ungültig", "medium", color.RED, "left")
    return
  end
  local cx, cy = x + w // 2, y + h // 2 + 50
  local function sc(t)
    for k = 3, 2, -1 do if draw.measure(t, "huge", k) <= w - 80 then return k end end
    return 1
  end
  if days == 0 then
    draw.text(cx, cy, "Heute!", "large", accent, "center", 3)
  else
    local t = tostring(days < 0 and -days or days)
    draw.text(cx, cy, t, "huge", days < 0 and color.BLACK or accent, "center", sc(t))
    local unit = days < 0 and "Tage vorbei" or (days == 1 and "Tag" or "Tage")
    draw.text(cx, cy + 56, unit, "medium", color.BLACK, "center")
  end
  if cfg.showDate and cfg.date then
    local pw = draw.measure(cfg.date, "small") + 36
    pill(x + w - pw - 24, y + h - 58, pw, 34, accent, cfg.date, "small", accent == color.YELLOW and color.BLACK or color.WHITE)
  end
end

function on_draw(ctx, page)
  local cfg = ctx.cfg
  local days = time.days_until(cfg.date)
  local accent = accentColor(cfg.accent)

  draw.clear(color.WHITE)
  setStyle(cfg.style)
  if theme.s == "relief" or theme.s == "klar" then return drawCard(cfg, days, accent) end
  draw.rect(0, draw.top, 24, draw.height - draw.top, accent, true)

  local tall = draw.height > draw.width
  local lf = (draw.measure(cfg.label or "", "large") <= draw.width - 100) and "large" or ((draw.measure(cfg.label or "", "medium") <= draw.width - 100) and "medium" or "normal")
  draw.text(80, 90, cfg.label, lf, color.BLACK, "left")
  if days == nil then
    draw.text(80, 240, "Datum ungültig", lf, color.RED, "left")
    return
  end
  local cy = tall and (draw.height // 2) or 300
  local function sc(t)
    for k = 3, 2, -1 do if draw.measure(t, "huge", k) <= draw.width - 100 then return k end end
    return 1
  end
  if days < 0 then
    local t = tostring(-days)
    draw.text(draw.width // 2, cy, t, "huge", color.BLACK, "center", sc(t))
    draw.text(draw.width // 2, cy + 70, "Tage vorbei", "medium", color.BLACK, "center")
  elseif days == 0 then
    draw.text(draw.width // 2, cy - 10, "Heute!", "large", accent, "center", 3)
  else
    local t = tostring(days)
    draw.text(draw.width // 2, cy, t, "huge", accent, "center", sc(t))
    draw.text(draw.width // 2, cy + 70, days == 1 and "Tag" or "Tage", "normal", color.BLACK, "center")
  end
  if cfg.showDate then
    draw.text(draw.width - 40, draw.height - 30, cfg.date, "small", color.BLACK, "right")
  end
end

-- CHANGELOG 506: Schriftgroesse des Widgets (box.font: -1 klein, 0 normal, +1 gross) fuer die Bezeichnung
local function fnt(b, base)
  local t = b and b.font or 0
  if t < 0 and base == "normal" then return "small" end
  if t > 0 and base == "small" then return "normal" end
  return base
end

function on_widget(ctx, box)
  setStyle(ctx.cfg.style)
  box = widgetFrame(box)
  local days = time.days_until(ctx.cfg.date)
  draw.text(box.x + 12, box.y + 26, ctx.cfg.label, fnt(box, "small"), color.BLACK, "left")
  if days ~= nil then
    draw.text(box.x + 12, box.y + box.h // 2 + 18, tostring(days), "large", accentColor(ctx.cfg.accent), "left") -- 1.0.2: Tageszahl linksbuendig, bündig mit der Bezeichnung
  end
end
