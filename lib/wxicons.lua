-- ===== Wetter-Symbole aller Stile (Klassisch, Tusche, Skizze, Aquarell, Buntstift): im Paket gezeichnet, laeuft auch auf aelterer Firmware =====
-- Alle Masse in Prozent der Symbolgroesse; Raster = 2x2-Bayer (Stufen 0..4 = 0/25/50/75/100 %). Flaechen werden zeilenweise als Spans gezeichnet.

local wxDrawStyled
do
local wxFloor, wxCeil, wxSqrt, wxAbs = math.floor, math.ceil, math.sqrt, math.abs

local function wxP(size, p)
  local v = size * p + (p >= 0 and 50 or -50)
  if v >= 0 then return v // 100 end
  return -((-v) // 100)
end
local function wxDiv(a, b) -- Ganzzahldivision mit Abschneiden Richtung 0 (wie C)
  local q = wxAbs(a) // wxAbs(b)
  if (a < 0) ~= (b < 0) then q = -q end
  return q
end
local function wxDot(x, y, c) draw.rect(x, y, 1, 1, c, true) end
local function wxSpan(x0, x1, y, c) if x1 >= x0 then draw.rect(x0, y, x1 - x0 + 1, 1, c, true) end end
local function wxOn(x, y, level) -- Rasterpunkt gesetzt?
  local m
  if y % 2 == 0 then m = (x % 2 == 0) and 0 or 2 else m = (x % 2 == 0) and 3 or 1 end
  return level > m
end
local function wxPatSpan(x0, x1, y, level, c)
  if level >= 4 then wxSpan(x0, x1, y, c) return end
  if level <= 0 then return end
  for x = x0, x1 do if wxOn(x, y, level) then wxDot(x, y, c) end end
end

local function wxMinus(a, b, c, d, y, col) -- [a,b] ohne [c,d]
  if not a then return end
  if not c or d < a or c > b then wxSpan(a, b, y, col) return end
  wxSpan(a, c - 1, y, col)
  wxSpan(d + 1, b, y, col)
end

-- Deckung je Pixel aus 2x2-Unterabtastung (Abtastpunkte x+0,25 / x+0,75 in zwei Teilzeilen): weiche Raender als Raster wie in der Firmware.
-- Form = {add = {Primitive}, sub = {Primitive}}; Primitive: {"c", cx, cy, R} Kreis, {"r", cx, cy, hx, hy, R} abgerundetes Rechteck (R inkl. 0,5)
local function wxPrimIv(p, sy)
  if p[1] == "c" then
    local dy = sy - (p[3] + 0.5)
    local d = p[4] * p[4] - dy * dy
    if d < 0 then return nil end
    local h = wxSqrt(d)
    return p[2] + 0.5 - h, p[2] + 0.5 + h
  end
  local dy = wxAbs(sy - (p[3] + 0.5))
  local half
  if dy <= p[5] then half = p[4] + p[6]
  else
    local dd = dy - p[5]
    if dd > p[6] then return nil end
    half = p[4] + wxSqrt(p[6] * p[6] - dd * dd)
  end
  return p[2] + 0.5 - half, p[2] + 0.5 + half
end
local function wxMerge(list)
  table.sort(list, function(a, b) return a[1] < b[1] end)
  local out, m = {}, 0
  for i = 1, #list do
    local s = list[i]
    if m > 0 and s[1] <= out[m][2] then
      if s[2] > out[m][2] then out[m][2] = s[2] end
    else m = m + 1; out[m] = {s[1], s[2]} end
  end
  return out
end
local function wxShapeIv(shape, sy)
  local list = {}
  for _, p in ipairs(shape.add) do
    local l, r = wxPrimIv(p, sy)
    if l then list[#list + 1] = {l, r} end
  end
  local add = wxMerge(list)
  if not shape.sub then return add end
  local sl = {}
  for _, p in ipairs(shape.sub) do
    local l, r = wxPrimIv(p, sy)
    if l then sl[#sl + 1] = {l, r} end
  end
  if #sl == 0 then return add end
  sl = wxMerge(sl)
  local out = {}
  for _, a in ipairs(add) do
    local l = a[1]
    for _, s in ipairs(sl) do
      if s[2] >= l and s[1] <= a[2] then
        if s[1] > l then out[#out + 1] = {l, s[1]} end
        l = s[2]
      end
    end
    if l < a[2] then out[#out + 1] = {l, a[2]} end
  end
  return out
end
local function wxCovAt(I1, I2, x)
  local c = 0
  for k = 1, 2 do
    local I = k == 1 and I1 or I2
    for _, iv in ipairs(I) do
      if x + 0.25 >= iv[1] and x + 0.25 <= iv[2] then c = c + 1 end
      if x + 0.75 >= iv[1] and x + 0.75 <= iv[2] then c = c + 1 end
    end
  end
  return c
end
-- Segmente {a, b, Deckung 1..4} der Zeile y
local function wxSegs(shape, y)
  local I1, I2 = wxShapeIv(shape, y + 0.25), wxShapeIv(shape, y + 0.75)
  local set, list = {}, {}
  for k = 1, 2 do
    for _, iv in ipairs(k == 1 and I1 or I2) do
      for e = 1, 2 do
        local u = wxFloor(iv[e])
        if not set[u] then set[u] = true; list[#list + 1] = u end
      end
    end
  end
  local segs, m = {}, 0
  if #list == 0 then return segs end
  table.sort(list)
  local function push(a, b, c)
    if c <= 0 then return end
    if m > 0 and segs[m][2] == a - 1 and segs[m][3] == c then segs[m][2] = b
    else m = m + 1; segs[m] = {a, b, c} end
  end
  for i = 1, #list do
    local u = list[i]
    push(u, u, wxCovAt(I1, I2, u))
    local nx = list[i + 1]
    if nx and nx > u + 1 then push(u + 1, nx - 1, wxCovAt(I1, I2, u + 1)) end
  end
  return segs
end
-- laeuft ueber die Pixelbereiche zweier Segmentlisten und ruft fn(von, bis, deckungA, deckungB)
local function wxSweep(A, B, fn)
  local bp, seen = {}, {}
  for _, L in ipairs({A, B}) do
    for _, s in ipairs(L) do
      if not seen[s[1]] then seen[s[1]] = true; bp[#bp + 1] = s[1] end
      if not seen[s[2] + 1] then seen[s[2] + 1] = true; bp[#bp + 1] = s[2] + 1 end
    end
  end
  table.sort(bp)
  local ia, ib = 1, 1
  for i = 1, #bp - 1 do
    local p, q = bp[i], bp[i + 1] - 1
    while A[ia] and A[ia][2] < p do ia = ia + 1 end
    while B[ib] and B[ib][2] < p do ib = ib + 1 end
    local ca = (A[ia] and A[ia][1] <= p) and A[ia][3] or 0
    local cb = (B[ib] and B[ib][1] <= p) and B[ib][3] or 0
    if ca > 0 or cb > 0 then fn(p, q, ca, cb) end
  end
end
local function wxInk(p, q, y, ink, c) -- Deckung ink (1..4) als Raster
  if ink >= 4 then wxSpan(p, q, y, c) elseif ink > 0 then wxPatSpan(p, q, y, ink, c) end
end
local function wxCircShape(cx, cy, r) return {add = {{"c", cx, cy, r + 0.5}}} end

-- Wolke: drei Kreise + abgerundetes Rechteck
local function wxCloudGeom(cx, cy, w)
  local X, Y, R = {-25, -4, 23}, {8, -5, 8}, {17, 24, 18}
  local g = {cxs = {}, cys = {}, rs = {}}
  for i = 1, 3 do
    g.cxs[i] = cx + wxP(w, X[i]); g.cys[i] = cy + wxP(w, Y[i]); g.rs[i] = wxP(w, R[i])
  end
  local bx, by, bw, bh = cx + wxP(w, -42), cy + wxP(w, 2), wxP(w, 84), wxP(w, 26)
  g.br = wxP(w, 13)
  g.rcx = bx + bw // 2; g.rcy = by + bh // 2
  g.hx = bw // 2 - g.br; g.hy = bh // 2 - g.br
  g.y0 = cy + wxP(w, -29); g.y1 = by + bh
  return g
end
local function wxCloudShape(g, e)
  local add = {}
  for i = 1, 3 do add[i] = {"c", g.cxs[i], g.cys[i], g.rs[i] + e + 0.5} end
  add[4] = {"r", g.rcx, g.rcy, g.hx, g.hy, g.br + e + 0.5}
  return {add = add}
end

-- Wolke in einem der Stile (kind 1 Tusche, 2 Skizze, 3 Aquarell, 4 Buntstift). level 0..4 Raster, 5 = durchgehend; t = Konturbreite; ring = weisser Freiraum aussen
local function wxCloudSt(cx, cy, w, kind, level, flatCol, t, ring)
  local g = wxCloudGeom(cx, cy, w)
  local outl = (kind == 2 or kind == 4)
  local ext = (outl and t or 0) + ring + 1
  local K, Wh = color.BLACK, color.WHITE
  local sR = ring > 0 and wxCloudShape(g, ring) or nil
  local sT = outl and wxCloudShape(g, t) or nil
  local s0 = wxCloudShape(g, 0)
  for y = g.y0 - ext, g.y1 + ext do
    if sR then
      for _, s in ipairs(wxSegs(sR, y)) do if s[3] >= 2 then wxSpan(s[1], s[2], y, Wh) end end
    end
    if outl then
      wxSweep(wxSegs(sT, y), wxSegs(s0, y), function(p, q, ca, cb)
        if ca <= 0 then return end
        wxSpan(p, q, y, Wh)
        if cb < 4 then wxInk(p, q, y, ca - cb, K) end
      end)
    else
      local col = (kind == 1) and K or flatCol
      for _, s in ipairs(wxSegs(s0, y)) do
        local eff = (kind == 1 and level >= 5) and s[3] or math.min(level, s[3])
        wxInk(s[1], s[2], y, eff, col)
      end
    end
  end
end

local function wxStroke(x0, y0, x1, y1, wd, c)
  local n = math.max(wxAbs(x1 - x0), wxAbs(y1 - y0))
  local h = wd // 2
  for i = 0, n do
    local xx = n > 0 and x0 + wxDiv((x1 - x0) * i, n) or x0
    local yy = n > 0 and y0 + wxDiv((y1 - y0) * i, n) or y0
    draw.rect(xx - h, yy - h, wd, wd, c, true)
  end
end
local function wxStrokePat(x0, y0, x1, y1, wd, level, c)
  local n = math.max(wxAbs(x1 - x0), wxAbs(y1 - y0))
  local h = wd // 2
  local seen = {}
  for i = 0, n do
    local xx = n > 0 and x0 + wxDiv((x1 - x0) * i, n) or x0
    local yy = n > 0 and y0 + wxDiv((y1 - y0) * i, n) or y0
    for dy = 0, wd - 1 do
      for dx = 0, wd - 1 do
        local px, py = xx - h + dx, yy - h + dy
        local key = py * 4096 + px
        if not seen[key] then
          seen[key] = true
          if wxOn(px, py, level) then wxDot(px, py, c) end
        end
      end
    end
  end
end

-- gefuelltes Vieleck (gerade-ungerade, Scanline); colB ~= nil: Schachbrett colA/colB
local function wxFillPoly(px, py, n, colA, colB)
  local y0, y1 = py[1], py[1]
  for i = 2, n do
    if py[i] < y0 then y0 = py[i] end
    if py[i] > y1 then y1 = py[i] end
  end
  for y = y0, y1 do
    local xs, m = {}, 0
    for i = 1, n do
      local j = i % n + 1
      local ax, ay, bx, by = px[i], py[i], px[j], py[j]
      if ay ~= by then
        if ay > by then ax, bx = bx, ax; ay, by = by, ay end
        if y >= ay and y < by then m = m + 1; xs[m] = ax + wxDiv((bx - ax) * (y - ay), by - ay) end
      end
    end
    table.sort(xs)
    for a = 1, m - 1, 2 do
      if colB then
        for x = xs[a], xs[a + 1] do wxDot(x, y, ((x + y) % 2 == 1) and colB or colA) end
      else wxSpan(xs[a], xs[a + 1], y, colA) end
    end
  end
end

local function wxStarC(x, y, s, c, dither)
  if dither then
    local w = math.max(1, s * 2 // 5)
    wxFillPoly({x, x + w, x + s, x + w, x, x - w, x - s, x - w}, {y - s, y - w, y, y + w, y + s, y + w, y, y - w}, 8, c, color.WHITE)
    draw.rect(x - s, y, 2 * s + 1, 1, c, true) -- durchgehende Achsen: bleibt auch gezoomt ein Stern
    draw.rect(x, y - s, 1, 2 * s + 1, c, true)
    return
  end
  local w = math.max(1, s // 2)
  draw.triangle(x - w, y, x + w, y, x, y - s, c, true)
  draw.triangle(x - w, y, x + w, y, x, y + s, c, true)
  draw.triangle(x, y - w, x, y + w, x - s, y, c, true)
  draw.triangle(x, y - w, x, y + w, x + s, y, c, true)
end

-- Sonne: kind 1/3 Scheibe (3 = gelb), 2/4 Kreislinie (4 = gelb); discLevel < 4: Scheibe gerastert (Sonne hinter Wolken)
local function wxSunSt(x, y, r, mask, kind, sw, discLevel)
  discLevel = discLevel or 4
  local col = (kind >= 3) and color.YELLOW or color.BLACK
  local gap = math.max(2, r * 4 // 10)
  local len = math.max(3, r * 8 // 10)
  local dxs, dys = {0, 10, 0, -10, 7, 7, -7, -7}, {-10, 0, 10, 0, -7, 7, 7, -7}
  for i = 0, 7 do
    if (mask >> i) & 1 == 1 then
      local a = r + gap
      local o = a + (i < 4 and len or len * 8 // 10)
      wxStroke(x + wxDiv(dxs[i + 1] * a, 10), y + wxDiv(dys[i + 1] * a, 10), x + wxDiv(dxs[i + 1] * o, 10), y + wxDiv(dys[i + 1] * o, 10), sw, col)
    end
  end
  local solid = (kind == 1 or kind == 3)
  local rin = math.max(r - sw, 0)
  local so = wxCircShape(x, y, r)
  local si = (not solid and rin > 0) and wxCircShape(x, y, rin) or nil
  for py = y - r - 1, y + r + 1 do
    local A = wxSegs(so, py)
    if solid then
      for _, s in ipairs(A) do wxInk(s[1], s[2], py, math.min(s[3], discLevel), col) end
    else
      wxSweep(A, si and wxSegs(si, py) or {}, function(p, q, ca, cb)
        if cb == 4 then wxSpan(p, q, py, color.WHITE)
        elseif ca > 0 then wxInk(p, q, py, ca - cb, col) end
      end)
    end
  end
end

-- Mondsichel: fillCol innen, border (Breite b, 0 = keiner) aussen
local function wxMoonSt(x, y, r, cdx, cdy, rc, fillCol, borderCol, b)
  local cx2, cy2 = x + cdx, y + cdy
  local sF = {add = {{"c", x, y, r + 0.5}}, sub = {{"c", cx2, cy2, rc + 0.5}}}
  local sB = {add = {{"c", x, y, r + b + 0.5}}, sub = {{"c", cx2, cy2, rc - b + 0.5}}}
  for py = y - r - b - 1, y + r + b + 1 do
    wxSweep(wxSegs(b > 0 and sB or sF, py), wxSegs(sF, py), function(p, q, ca, cf)
      if cf == 4 then wxSpan(p, q, py, fillCol)
      elseif b > 0 then
        local ink = ca - cf
        if ink >= 4 then wxSpan(p, q, py, borderCol)
        elseif ink > 0 then wxSpan(p, q, py, color.WHITE); wxPatSpan(p, q, py, ink, borderCol)
        elseif cf > 0 then wxSpan(p, q, py, fillCol) end
      elseif cf > 0 then wxPatSpan(p, q, py, cf, fillCol) end
    end)
  end
end

-- Blitz: outer = Rand-/Freiraumfarbe (Breite b), inner = Fuellung; inner2 ~= inner: Schachbrett inner/inner2
local function wxBoltSt(x, y, h, outer, inner, b, inner2)
  local bx, by = {2, 11, 4, 11, -7, -2, -9}, {-15, -15, -3, -3, 16, 3, 3}
  local ox, oy = {-1, 0, 1, -1, 1, -1, 0, 1}, {-1, -1, -1, 0, 0, 1, 1, 1}
  for pass = 0, 1 do
    for k = 1, (pass == 0 and 8 or 1) do
      local px, py = {}, {}
      for i = 1, 7 do
        px[i] = x + wxDiv(bx[i] * h, 32) + (pass == 0 and ox[k] * b or 0)
        py[i] = y + wxDiv(by[i] * h, 32) + (pass == 0 and oy[k] * b or 0)
      end
      if pass == 1 and inner2 ~= inner then wxFillPoly(px, py, 7, inner, inner2)
      else wxFillPoly(px, py, 7, pass == 0 and outer or inner) end
    end
  end
end

local function wxFlakeSt(x, y, fr, kind, sw, c)
  local k, h = fr * 87 // 100, fr // 2
  if kind == 1 or kind == 3 then -- Kreuz (x)
    local d = fr * 7 // 10
    if kind == 1 then
      wxStrokePat(x - d, y - d, x + d, y + d, sw + 2, 3, c)
      wxStrokePat(x - d, y + d, x + d, y - d, sw + 2, 3, c)
    else
      wxStroke(x - d, y - d, x + d, y + d, sw, c)
      wxStroke(x - d, y + d, x + d, y - d, sw, c)
    end
  else -- Stern (*)
    wxStroke(x, y - fr, x, y + fr, sw, c)
    wxStroke(x - k, y - h, x + k, y + h, sw, c)
    wxStroke(x - k, y + h, x + k, y - h, sw, c)
  end
end


-- ===== Klassisch (Stil 0): Wolke mit Kontur, gelbe Sonne mit Rand, blaue Tropfen/Flocken; mit denselben Grundformen wie die Firmware =====
local function wxCapsule(x0, y0, x1, y1, r, c)
  if r <= 2 then -- duenne Linien: Kreisstempel entlang der Linie
    local n = math.max(wxAbs(x1 - x0), wxAbs(y1 - y0))
    for i = 0, n do
      local xx = n > 0 and x0 + wxDiv((x1 - x0) * i, n) or x0
      local yy = n > 0 and y0 + wxDiv((y1 - y0) * i, n) or y0
      if r == 0 then wxDot(xx, yy, c) else draw.circle(xx, yy, r, c, true) end
    end
    return
  end
  draw.circle(x0, y0, r, c, true)
  draw.circle(x1, y1, r, c, true)
  local dx, dy = x1 - x0, y1 - y0
  local len = wxFloor(wxSqrt(dx * dx + dy * dy))
  if len == 0 then return end
  local nx, ny = wxDiv(-dy * r, len), wxDiv(dx * r, len)
  draw.triangle(x0 + nx, y0 + ny, x0 - nx, y0 - ny, x1 + nx, y1 + ny, c, true)
  draw.triangle(x1 + nx, y1 + ny, x1 - nx, y1 - ny, x0 - nx, y0 - ny, c, true)
end
local function wxClassicCloud(cx, cy, size)
  local b = size >= 90 and 4 or (size >= 56 and 3 or 2)
  local cL, cLy, rL = cx + wxP(size, -25), cy + wxP(size, 8), wxP(size, 17)
  local cM, cMy, rM = cx + wxP(size, -4), cy + wxP(size, -5), wxP(size, 24)
  local cR, cRy, rR = cx + wxP(size, 23), cy + wxP(size, 8), wxP(size, 18)
  local bx, by, bw, bh, br = cx + wxP(size, -42), cy + wxP(size, 2), wxP(size, 84), wxP(size, 26), wxP(size, 13)
  local K, Wh = color.BLACK, color.WHITE
  draw.circle(cL, cLy, rL + b, K, true); draw.circle(cM, cMy, rM + b, K, true); draw.circle(cR, cRy, rR + b, K, true)
  draw.rect(bx - b, by - b, bw + 2 * b, bh + 2 * b, K, true, br + b)
  draw.circle(cL, cLy, rL, Wh, true); draw.circle(cM, cMy, rM, Wh, true); draw.circle(cR, cRy, rR, Wh, true)
  draw.rect(bx, by, bw, bh, Wh, true, br)
end
local function wxClassicSun(x, y, r, size, mask)
  local ow = size >= 90 and 4 or (size >= 56 and 3 or 2)
  local b = ow > 2 and ow - 1 or 2
  local t = size >= 90 and 3 or (size >= 48 and 2 or 1)
  local gap = math.max(2, r // 3)
  local len = math.max(3, r * 2 // 3)
  local dxs, dys = {0, 1, 0, -1, 7, 7, -7, -7}, {-1, 0, 1, 0, -7, 7, 7, -7}
  for i = 0, 7 do
    if (mask >> i) & 1 == 1 then
      local ux = i < 4 and dxs[i + 1] * 10 or dxs[i + 1]
      local uy = i < 4 and dys[i + 1] * 10 or dys[i + 1]
      local a = r + b + gap
      local o = a + (i < 4 and len or len * 8 // 10)
      wxCapsule(x + wxDiv(ux * a, 10), y + wxDiv(uy * a, 10), x + wxDiv(ux * o, 10), y + wxDiv(uy * o, 10), t, color.BLACK)
    end
  end
  draw.circle(x, y, r + b, color.BLACK, true)
  draw.circle(x, y, r, color.YELLOW, true)
end
local function wxClassicBolt(x, y, h)
  local bx, by = {2, 11, 4, 11, -7, -2, -9}, {-15, -15, -3, -3, 16, 3, 3}
  local b = h >= 52 and 2 or 1
  local ox, oy = {-1, 0, 1, -1, 1, -1, 0, 1}, {-1, -1, -1, 0, 0, 1, 1, 1}
  for pass = 0, 1 do
    for k = 1, (pass == 0 and 8 or 1) do
      local px, py = {}, {}
      for i = 1, 7 do
        px[i] = x + wxDiv(bx[i] * h, 32) + (pass == 0 and ox[k] * b or 0)
        py[i] = y + wxDiv(by[i] * h, 32) + (pass == 0 and oy[k] * b or 0)
      end
      wxFillPoly(px, py, 7, pass == 0 and color.BLACK or color.YELLOW)
    end
  end
end
local function wxClassicMoon(x, y, r, cdx, cdy, rc, b)
  local cx2, cy2 = x + cdx, y + cdy
  local function iv(cx, cy, rr, py) -- Pixel mit Abstand <= rr
    if rr < 0 then return nil end
    local d = rr * rr - (py - cy) * (py - cy)
    if d < 0 then return nil end
    local h = wxFloor(wxSqrt(d))
    return cx - h, cx + h
  end
  local function cut(cx, cy, rr, py) -- Pixel mit Abstand <= rr als auszuschliessender Bereich
    return iv(cx, cy, rr, py)
  end
  for py = y - r - b, y + r + b do
    local a, bb = iv(x, y, r + b, py)
    local c, d = cut(cx2, cy2, rc - b, py)
    wxMinus(a, bb, c, d, py, color.BLACK)
    a, bb = iv(x, y, r, py)
    c, d = cut(cx2, cy2, rc, py)
    wxMinus(a, bb, c, d, py, color.YELLOW)
  end
end
local function wxDrawClassic(cond, cx, cy, size)
  local function P(p) return wxP(size, p) end
  local K, Bl, Y = color.BLACK, color.BLUE, color.YELLOW
  if cond == 0 then wxClassicSun(cx, cy, P(22), size, 0xFF)
  elseif cond == 1 then
    wxClassicSun(cx + P(14), cy + P(-16), P(17), size, 0x01 | 0x02 | 0x10 | 0x80 | 0x20)
    wxClassicCloud(cx + P(-4), cy + P(10), size * 80 // 100)
  elseif cond == 2 then wxClassicCloud(cx, cy, size * 95 // 100)
  elseif cond == 3 then
    wxClassicCloud(cx, cy + P(-16), size * 78 // 100)
    local th = math.max(P(5), 2)
    local ys, xl, xr = {P(17), P(29), P(41)}, {P(-34), P(-26), P(-34)}, {P(34), P(30), P(34)}
    for i = 1, 3 do wxCapsule(cx + xl[i], cy + ys[i], cx + xr[i], cy + ys[i], math.max(th // 2, 1), K) end
  elseif cond == 4 or cond == 5 then
    local heavy = cond == 5
    wxClassicCloud(cx, cy + P(-15), size * 94 // 100)
    local r = math.max(P(4), 1)
    local len = heavy and P(22) or P(16)
    local xs3, xs2 = {P(-22), P(0), P(22)}, {P(-12), P(12)}
    for i = 1, (heavy and 3 or 2) do
      local x, y = cx + (heavy and xs3[i] or xs2[i]), cy + P(23) + ((i - 1) % 2 == 1 and P(7) or 0)
      wxCapsule(x + len // 4, y, x - len // 4, y + len, r, Bl)
    end
  elseif cond == 6 then
    wxClassicCloud(cx, cy + P(-15), size * 94 // 100)
    local fr = math.max(P(10), 3)
    for i = 0, 2 do
      local x, y = cx + P(-22) + i * P(22), cy + P(35) + (i % 2 == 1 and P(8) or 0)
      local k, h = fr * 87 // 100, fr // 2
      local rr = fr >= 12 and 2 or (fr >= 6 and 1 or 0)
      wxCapsule(x, y - fr, x, y + fr, rr, Bl)
      wxCapsule(x - k, y - h, x + k, y + h, rr, Bl)
      wxCapsule(x - k, y + h, x + k, y - h, rr, Bl)
    end
  elseif cond == 7 then
    wxClassicCloud(cx, cy + P(-16), size * 94 // 100)
    wxClassicBolt(cx + P(2), cy + P(31), P(52))
  elseif cond == 9 then
    wxClassicCloud(cx, cy + P(-15), size * 94 // 100)
    local r = math.max(P(6), 2)
    for i = 0, 2 do
      local x, y = cx + P(-20) + i * P(20), cy + P(31) + (i % 2 == 1 and P(9) or 0)
      draw.circle(x, y, r + 1, K, true)
      draw.circle(x, y, r > 2 and r - 1 or r, Bl, true)
    end
  elseif cond == 10 then
    local ow = size >= 90 and 4 or (size >= 56 and 3 or 2)
    wxClassicMoon(cx + P(-4), cy + P(2), P(30), P(15), P(-11), P(25), ow > 2 and ow - 1 or 2)
    wxStarC(cx + P(24), cy + P(-24), math.max(P(11), 2), K, false)
    wxStarC(cx + P(32), cy + P(6), math.max(P(6), 1), K, false)
    if size >= 40 then wxStarC(cx + P(12), cy + P(34), P(6), K, false) end
  else
    local ow = size >= 90 and 4 or (size >= 56 and 3 or 2)
    wxClassicMoon(cx + P(12), cy + P(-15), P(21), P(10), P(-8), P(18), ow > 2 and ow - 1 or 2)
    if size >= 40 then wxStarC(cx + P(-22), cy + P(-30), P(7), K, false) end
    wxClassicCloud(cx + P(-4), cy + P(10), size * 80 // 100)
  end
end

local WX_CONDS = {clear = 0, partly = 1, cloudy = 2, fog = 3, drizzle = 4, rain = 5, snow = 6, thunder = 7, hail = 9, clear_night = 10, partly_night = 11}

-- Zeichnet das Symbol; false bei unbekanntem Zustand (dann zeichnet die Firmware)
wxDrawStyled = function(condName, cx, cy, size, night, kind)
  if type(condName) ~= "string" then return false end
  if night then
    if condName == "clear" then condName = "clear_night" elseif condName == "partly" then condName = "partly_night" end
  end
  local cond = WX_CONDS[condName]
  if not cond then return false end
  if size < 8 then size = 8 end
  if kind == 0 then wxDrawClassic(cond, cx, cy, size) return true end
  local function P(p) return wxP(size, p) end
  local outl = (kind == 2 or kind == 4)
  local dith = (kind == 1 or kind == 3) -- Tusche und Aquarell: Niederschlag, Nebel, Sterne gerastert
  local sw = size >= 100 and 3 or (size >= 56 and 2 or 1)
  local gap = size >= 100 and 4 or (size >= 56 and 3 or 2)
  local t = outl and sw or 0
  local ring = outl and (t + gap - 1) or gap
  local K, Wh, Y, Bl = color.BLACK, color.WHITE, color.YELLOW, color.BLUE
  local pc = (kind >= 3) and Bl or K -- Niederschlag
  local yc = (kind >= 3) and Y or K -- Sonne/Mond/Blitz
  local function cloud(x, y, w, kindLevel, rg)
    local level = (kindLevel == 1) and 1 or 2
    local col = (kindLevel == 2) and K or Bl
    if kind == 1 then level = (kindLevel == 1) and 2 or 5 end
    wxCloudSt(x, y, w, kind, level, col, t, rg)
  end
  local function drops(n, y0, len)
    local x3, x2 = {-22, 0, 22}, {-12, 12}
    for i = 1, n do
      local x = cx + P(n == 3 and x3[i] or x2[i])
      local y = cy + y0 + ((i - 1) % 2 == 1 and P(7) or 0)
      if dith then wxStrokePat(x + len // 4, y, x - len // 4, y + len, sw + 1, 3, pc)
      else wxStroke(x + len // 4, y, x - len // 4, y + len, sw, pc) end
    end
  end

  if cond == 0 then
    wxSunSt(cx, cy, P(21), 0xFF, kind, sw)
  elseif cond == 1 then
    wxSunSt(cx + P(15), cy + P(-17), P(16), 0x01 | 0x02 | 0x10 | 0x80 | 0x20, kind, sw, kind == 1 and 2 or 4)
    cloud(cx + P(-4), cy + P(10), size * 82 // 100, 0, ring)
  elseif cond == 2 then
    cloud(cx + P(17), cy + P(-12), size * 62 // 100, 1, 0)
    cloud(cx + P(-8), cy + P(9), size * 84 // 100, 0, ring)
  elseif cond == 3 then
    cloud(cx, cy + P(-15), size * 80 // 100, 0, 0)
    local ys, xl, xr = {P(18), P(29), P(40)}, {P(-32), P(-24), P(-32)}, {P(32), P(28), P(32)}
    for i = 1, 3 do
      if dith then wxStrokePat(cx + xl[i], cy + ys[i], cx + xr[i], cy + ys[i], sw + 1, 3, pc)
      else wxStroke(cx + xl[i], cy + ys[i], cx + xr[i], cy + ys[i], sw, pc) end
    end
  elseif cond == 4 then
    cloud(cx, cy + P(-14), size * 90 // 100, 0, 0)
    drops(2, P(24), P(14))
  elseif cond == 5 then
    cloud(cx, cy + P(-14), size * 90 // 100, 0, 0)
    drops(3, P(24), P(20))
  elseif cond == 6 then
    cloud(cx, cy + P(-14), size * 90 // 100, 0, 0)
    local fr = math.max(3, P(8))
    for i = 0, 2 do wxFlakeSt(cx + P(-22) + i * P(22), cy + P(33) + (i % 2 == 1 and P(9) or 0), fr, kind, sw, pc) end
  elseif cond == 7 then
    cloud(cx, cy + P(-16), size * 90 // 100, kind == 3 and 2 or 0, 0)
    local b = outl and (sw > 1 and sw - 1 or 1) or gap
    local outer = (kind == 1 and Wh) or (kind == 2 and K) or (kind == 3 and Wh) or Y
    local inner = (kind == 1 and K) or (kind == 2 and Wh) or (kind == 3 and Y) or Wh
    wxBoltSt(cx + P(2), cy + P(30), P(50), outer, inner, b, kind == 1 and Y or inner)
  elseif cond == 9 then
    cloud(cx, cy + P(-14), size * 90 // 100, 0, 0)
    local r = math.max(1, P(4))
    for i = 0, 2 do draw.circle(cx + P(-20) + i * P(20), cy + P(32) + (i % 2 == 1 and P(9) or 0), r, pc, true) end
  elseif cond == 10 then
    local r = P(30)
    if kind == 1 then wxMoonSt(cx + P(-4), cy + P(2), r, P(15), P(-11), P(25), K, K, 0)
    elseif kind == 3 then wxMoonSt(cx + P(-4), cy + P(2), r, P(15), P(-11), P(25), Y, Y, 0)
    else wxMoonSt(cx + P(-4), cy + P(2), r, P(15), P(-11), P(25), Wh, kind == 2 and K or Y, sw) end
    wxStarC(cx + P(26), cy + P(-24), math.max(2, P(10)), yc, dith and size >= 40)
    if size >= 40 then wxStarC(cx + P(33), cy + P(6), P(6), yc, dith) end
  else -- 11: teils bewoelkt, Nacht
    local r, mx, my = P(22), cx + P(17), cy + P(-18)
    if kind == 1 then wxMoonSt(mx, my, r, P(11), P(-9), P(19), K, K, 0)
    elseif kind == 3 then wxMoonSt(mx, my, r, P(11), P(-9), P(19), Y, Y, 0)
    else wxMoonSt(mx, my, r, P(11), P(-9), P(19), Wh, kind == 2 and K or Y, sw) end
    cloud(cx + P(-4), cy + P(10), size * 82 // 100, 0, ring)
  end
  return true
end
end
