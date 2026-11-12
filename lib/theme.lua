-- Stil-Bausteine (store/lib/theme.lua): setStyle(), card(), panel(), widgetFrame(), pill(), pbar()
-- Fuenf Stile: Relief (erhaben, Hartschatten), Klar (Apple: farbige Kacheln ohne Rand), Bento ("cards": Akzentbalken),
-- Slate ("flat") und Nano ("compact"). Relief und Klar nutzen das Kartenlayout der App, aber mit eigener Optik.
local theme = { s = "cards" }
local function light(c) return c == color.YELLOW or c == color.WHITE end
local function inkOf(c)
  if c == color.ACCENT then return color.ACCENT_INK elseif c == color.ACCENT_INK then return color.ACCENT end
  return light(c) and color.BLACK or color.WHITE
end

-- Klar: gefuellte Flaechen werden gemerkt. Schwarz (auf dunkler Flaeche) und die Flaechenfarbe selbst zeichnen darin
-- in der passenden Schriftfarbe (weiss auf Blau, schwarz auf Gelb), damit jede App ohne Umbau lesbar bleibt.
local tiles, raw, pts = {}, nil, {}
local function tileInk(x, y, c, fill)
  if theme.s ~= "klar" then return c end
  if (not fill or c ~= color.WHITE) and #pts < 400 then pts[#pts + 1] = x; pts[#pts + 1] = y end -- schon gezeichneter Inhalt (panel() fuellt nur leere Flaechen)
  for i = #tiles, 1, -1 do
    local t = tiles[i]
    if x >= t[1] and x < t[3] and y >= t[2] and y < t[4] then
      local f, i = t[5], t[6]
      if c == f or (f == color.ACCENT and c == color.ACCENT_TEXT) then return i end
      if c == color.BLACK and not fill and not light(f) and f ~= color.ACCENT_INK then return i end -- Schrift/Linien, keine schwarzen Flaechen
      if c == color.ACCENT_INK and f ~= color.ACCENT then return light(f) and color.BLACK or color.WHITE end
      return c
    end
  end
  return c
end
local function klarHook()
  if raw then return end
  raw = { text = draw.text, wrap = draw.wrap, line = draw.line, rect = draw.rect, circle = draw.circle, triangle = draw.triangle, icon = draw.icon }
  draw.text = function(x, y, s, f, c, ...) return raw.text(x, y, s, f, tileInk(x, y - 4, c), ...) end
  draw.wrap = function(x, y, w, s, f, c, ...) return raw.wrap(x, y, w, s, f, tileInk(x, y, c), ...) end
  draw.line = function(a, b, c2, d, c) return raw.line(a, b, c2, d, tileInk((a + c2) // 2, (b + d) // 2, c)) end
  draw.circle = function(x, y, r, c, f)
    c = tileInk(x, y, c, f)
    if f and theme.s == "klar" and r >= 8 and #tiles < 120 then tiles[#tiles + 1] = { x - r, y - r, x + r, y + r, c, inkOf(c) } end
    return raw.circle(x, y, r, c, f)
  end
  draw.triangle = function(a, b, c2, d, e, f, c, fl) return raw.triangle(a, b, c2, d, e, f, tileInk((a + c2 + e) // 3, (b + d + f) // 3, c), fl) end
  draw.icon = function(n, x, y, z, c) return raw.icon(n, x, y, z, tileInk(x + z // 2, y + z // 2, c)) end
  draw.rect = function(x, y, w, h, c, fill, r)
    c = tileInk(x + w // 2, y + h // 2, c, fill)
    if fill and theme.s == "klar" and w >= 16 and h >= 12 and #tiles < 120 then tiles[#tiles + 1] = { x, y, x + w, y + h, c, inkOf(c) } end
    return raw.rect(x, y, w, h, c, fill, r)
  end
end

-- Stil-Weiche: setStyle(ctx.cfg.style) vor dem Zeichnen.
local function setStyle(s)
  theme.s = s or "cards"
  tiles, pts = {}, {}
  if theme.s == "klar" then klarHook() end
  if theme.s == "relief" or theme.s == "klar" then return "cards" end
  return s
end

-- Karte: Bento = weisse Karte, duenner Rand, Akzentbalken links. Relief = erhaben (harter Schatten, kraeftiger Rand,
-- kein Balken). Klar = farbige Kachel ohne Rand (Farbe c, sonst Akzent); Schrift darin passt sich an.
local function card(x, y, w, h, c, r, nobar)
  if theme.s == "relief" then
    r = r or 12
    draw.rect(x + 6, y + 6, w, h, color.BLACK, true, r)
    draw.rect(x, y, w, h, color.WHITE, true, r)
    draw.rect(x, y, w, h, color.BLACK, false, r)
    draw.rect(x + 1, y + 1, w - 2, h - 2, color.BLACK, false, r)
    return
  elseif theme.s == "klar" then
    if not c or c == color.BLACK then c = color.ACCENT end
    draw.rect(x, y, w, h, c, true, math.min((r or 18) + 8, 30))
    return
  end
  r = r or 10
  draw.rect(x, y, w, h, color.WHITE, true, r)
  draw.rect(x, y, w, h, color.BLACK, false, r)
  if not nobar then draw.rect(x + 6, y + 6, 5, h - 12, c or color.ACCENT, true, 2) end
end

-- Umrandete Flaeche (auch nach dem Inhalt aufrufbar): Relief = Schatten an Unter- und Rechtskante, Klar = kraeftiger farbiger Rand.
-- Kleine Flaechen (Haekchen, Punkte) bekommen weder Schatten noch Doppelrahmen.
local function panel(x, y, w, h, r, c)
  c = c or color.BLACK
  local big = w >= 60 and h >= 30
  if theme.s == "relief" and big then
    -- Schatten folgt der Rundung der Kachel (wie bei card): Geraden plus Eck-Sicheln aus Vierecken, nichts ueberdeckt den Inhalt
    local s = 5
    local rr = math.max(2, math.min(r or 12, 40, w // 2, h // 2))
    local function sichel(cx, cy, a0, a1)
      local n = 5
      for i = 0, n - 1 do
        local u, v = math.rad(a0 + (a1 - a0) * i / n), math.rad(a0 + (a1 - a0) * (i + 1) / n)
        local c1, s1, c2, s2 = math.cos(u) * rr, math.sin(u) * rr, math.cos(v) * rr, math.sin(v) * rr
        local function f(v) return math.floor(v + 0.5) end
        draw.polygon({f(cx + c1), f(cy + s1), f(cx + c1 + s), f(cy + s1 + s), f(cx + c2 + s), f(cy + s2 + s), f(cx + c2), f(cy + s2)}, color.BLACK, true)
      end
    end
    draw.rect(x + w, y + rr, s, h - 2 * rr + s, color.BLACK, true)
    draw.rect(x + rr, y + h, w - 2 * rr + s, s, color.BLACK, true)
    sichel(x + w - rr, y + h - rr, 0, 90)      -- unten rechts
    sichel(x + w - rr, y + rr, -45, 0)         -- oben rechts
    sichel(x + rr, y + h - rr, 90, 135)        -- unten links
  end
  if theme.s == "klar" and big then
    c = c == color.BLACK and color.ACCENT or c
    for i = 1, #pts, 2 do -- schon Inhalt in der Flaeche: nur farbiger Rand, sonst farbige Kachel
      if pts[i] > x and pts[i] < x + w and pts[i + 1] > y and pts[i + 1] < y + h then
        for k = 0, 2 do draw.rect(x + k, y + k, w - 2 * k, h - 2 * k, c, false, r) end
        return
      end
    end
    draw.rect(x, y, w, h, c, true, math.min((r or 12) + 8, 30))
    return
  end
  draw.rect(x, y, w, h, c, false, r)
end

-- Widget im Stil Relief/Klar (mit all=true auch Bento): eine Karte um den ganzen Inhalt; gibt die Box fuer den Inhalt zurueck (sonst unveraendert).
local function widgetFrame(box, all)
  local st = theme.s
  if st ~= "relief" and st ~= "klar" and not (all and st == "cards") then return box end
  local x, y, w, h = box.x + 4, box.y + 2, box.w - 14, box.h - 12
  local r = st == "relief" and 12 or (st == "klar" and 18 or 10)
  card(x, y, w, h, color.ACCENT, r)
  local pad = st == "relief" and 14 or (st == "klar" and 8 or 20)
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
