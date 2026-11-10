-- Stil-Bausteine fuer Relief/Klar (store/lib/theme.lua): setStyle(), card(), panel(), widgetFrame()

-- Stil-Weiche: setStyle(ctx.cfg.style) vor dem Zeichnen; "relief" und "klar" nutzen das Kartenlayout, aber mit eigener Optik.
local theme = { s = "cards" }
local function setStyle(s)
  theme.s = s or "cards"
  if theme.s == "relief" or theme.s == "klar" then return "cards" end
  return s
end

-- Karte: Standard = Akzentbalken links. Relief = harter Schatten + eingerueckter Balken, Klar = helle Kachel ohne Balken.
-- nobar = true: Relief ohne Balken (wenn links schon eine farbige Pille/Marke sitzt).
local function card(x, y, w, h, c, r, nobar)
  if theme.s == "relief" then
    r = r or 12
    draw.rect(x + 5, y + 5, w, h, color.BLACK, true, r)
    draw.rect(x, y, w, h, color.WHITE, true, r)
    draw.rect(x, y, w, h, color.BLACK, false, r)
    if not nobar then draw.rect(x + 6, y + 10, 4, h - 20, c or color.ACCENT, true, 2) end
    return
  elseif theme.s == "klar" then
    r = r or 20
    draw.rect(x, y, w, h, color.WHITE, true, r)
    draw.rect(x, y, w, h, color.BLACK, false, r)
    draw.rect(x + 1, y + 1, w - 2, h - 2, color.BLACK, false, r)
    return
  end
  r = r or 10
  draw.rect(x, y, w, h, color.WHITE, true, r)
  draw.rect(x, y, w, h, color.BLACK, false, r)
  draw.rect(x + 6, y + 6, 5, h - 12, c or color.ACCENT, true, 2)
end

-- Umrandete Flaeche (auch nach dem Inhalt aufrufbar): Relief = Schatten nur an Unter- und Rechtskante, Klar = doppelter Rahmen.
-- Kleine Flaechen (Haekchen, Punkte) bekommen weder Schatten noch Doppelrahmen.
local function panel(x, y, w, h, r, c)
  c = c or color.BLACK
  local big = w >= 60 and h >= 30
  if theme.s == "relief" and big then
    local s = 5
    draw.rect(x + w, y + s, s, h, color.BLACK, true)
    draw.rect(x + s, y + h, w, s, color.BLACK, true)
  end
  draw.rect(x, y, w, h, c, false, r)
  if theme.s == "klar" and big then draw.rect(x + 1, y + 1, w - 2, h - 2, c, false, r) end
end

-- Widget im Stil Relief/Klar: eine Karte um den ganzen Inhalt; gibt die Box fuer den Inhalt zurueck (sonst unveraendert).
local function widgetFrame(box)
  if theme.s ~= "relief" and theme.s ~= "klar" then return box end
  local x, y, w, h = box.x + 4, box.y + 2, box.w - 14, box.h - 12
  card(x, y, w, h, color.ACCENT, theme.s == "relief" and 12 or 18)
  local pad = theme.s == "relief" and 14 or 8
  local inner = {}
  for k, v in pairs(box) do inner[k] = v end
  inner.x, inner.y, inner.w, inner.h = box.x + pad, box.y + 8, box.w - pad - 16, box.h - 20
  return inner
end

-- Erhabene Pille (Relief: harter Schatten, Klar: flach gefuellt, sonst nur Rahmen); Text optional, zentriert.
local function pillW(txt, font, h, minw)
  return math.max(minw or 0, draw.measure(txt, font or "small") + h)
end
local function pill(x, y, w, h, c, txt, font, tc)
  if txt then w = pillW(txt, font, h, w) end   -- variable Breite: waechst mit dem Text
  local r = h // 2
  c = c or color.ACCENT
  if theme.s == "relief" then
    draw.rect(x + 3, y + 3, w, h, color.BLACK, true, r)
    draw.rect(x, y, w, h, c, true, r)
    draw.rect(x, y, w, h, color.BLACK, false, r)
  elseif theme.s == "klar" then
    draw.rect(x, y, w, h, c, true, r)
  else
    draw.rect(x, y, w, h, c, false, r)
    tc = tc or (c == color.ACCENT and color.ACCENT_TEXT or c)
  end
  if txt then draw.text(x + w // 2, y + h // 2 + 8, txt, font or "small", tc or (c == color.ACCENT and color.ACCENT_INK or color.WHITE), "center") end
  return w
end

-- Fortschrittsbalken; Relief mit Schatten unter der Rinne, Klar als schmale runde Rinne.
local function pbar(x, y, w, h, frac, c)
  frac = math.max(0, math.min(1, frac or 0))
  c = c or color.ACCENT
  local r = h // 2
  if theme.s == "relief" then draw.rect(x + 3, y + 3, w, h, color.BLACK, true, r) ; draw.rect(x, y, w, h, color.WHITE, true, r) end
  draw.rect(x, y, w, h, color.BLACK, false, r)
  local fw = math.floor((w - 4) * frac)
  if fw > h - 4 then draw.rect(x + 2, y + 2, fw, h - 4, c, true, (h - 4) // 2)
  elseif fw > 2 then draw.rect(x + 2, y + 2, fw, h - 4, c, true) end
end
