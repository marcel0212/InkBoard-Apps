-- Countdown: zaehlt die Tage bis zu einem Zieldatum herunter.
-- Skript-API Level 1 (siehe docs/V2_APPSTORE.md): draw.*, color.*, time.*, ctx.cfg

local function accentColor(name)
  if name == "green" then return color.GREEN end
  if name == "red" then return color.RED end
  if name == "yellow" then return color.YELLOW end
  if name == "black" then return color.BLACK end
  return color.BLUE
end

function on_draw(ctx, page)
  local cfg = ctx.cfg
  local days = time.days_until(cfg.date)
  local accent = accentColor(cfg.accent)

  draw.clear(color.WHITE)
  draw.rect(0, draw.top, 24, draw.height - draw.top, accent, true)

  draw.text(80, 90, cfg.label, "large", color.BLACK, "left")
  if days == nil then
    draw.text(80, 240, "Datum ungültig", "large", color.RED, "left")
    return
  end
  if days < 0 then
    draw.text(draw.width // 2, 300, tostring(-days), "huge", color.BLACK, "center", 3)
    draw.text(draw.width // 2, 370, "Tage vorbei", "medium", color.BLACK, "center")
  elseif days == 0 then
    draw.text(draw.width // 2, 290, "Heute!", "large", accent, "center", 3)
  else
    draw.text(draw.width // 2, 300, tostring(days), "huge", accent, "center", 3)
    draw.text(draw.width // 2, 370, days == 1 and "Tag" or "Tage", "normal", color.BLACK, "center")
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
  local days = time.days_until(ctx.cfg.date)
  draw.text(box.x + 12, box.y + 26, ctx.cfg.label, fnt(box, "small"), color.BLACK, "left")
  if days ~= nil then
    draw.text(box.x + 12, box.y + box.h // 2 + 18, tostring(days), "large", accentColor(ctx.cfg.accent), "left") -- 1.0.2: Tageszahl linksbuendig, bündig mit der Bezeichnung
  end
end
