local MX = 26                 -- Seitenrand
local CONTENT_BOTTOM = 442
local FOOTER_BASE = 468
local TITLE_BASE, TITLE_LH = 84, 32
local MAX_ING, MAX_STEPS, MAX_NUT, MAX_PAGES = 40, 24, 8, 40
local ING_BYTES, STEP_BYTES = 95, 319 -- Feldbreiten der eingebauten App (char[96] / char[320] ohne Abschluss)
local BROWSE_SECONDS = 45             -- PAGE_MODE_TIMEOUT_MS der Firmware
local function T(ctx, de, en)
if ctx.lang == "en" then return en end
return de
end
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function cutBytes(s, n)
if #s <= n then return s end
local i = n
while i > 0 and (s:byte(i + 1) & 0xC0) == 0x80 do i = i - 1 end
return s:sub(1, i)
end
local function clean(s, n)
return cutBytes(text.strip_html(tostring(s or "")), n)
end
local function dropChar(s)
local i = #s
while i > 1 and (s:byte(i) & 0xC0) == 0x80 do i = i - 1 end
return s:sub(1, i - 1)
end
local function fit(s, w, font)
while #s > 0 and draw.measure(s, font) > w do s = dropChar(s) end
return s
end
local function wrap(s, maxW, font, maxLines)
local rest = trim(s)
local out = {}
while #rest > 0 and #out < maxLines do
if draw.measure(rest, font) <= maxW then
out[#out + 1] = rest
break
end
local best, from = nil, 1
while true do
local sp = rest:find(" ", from, true)
if sp == nil then break end
if draw.measure(rest:sub(1, sp - 1), font) <= maxW then
best = sp
from = sp + 1
else
break
end
end
local line
if best ~= nil and best > 1 then
line = rest:sub(1, best - 1)
rest = trim(rest:sub(best + 1))
else
local buf = cutBytes(rest, 79)
while #buf > 0 and draw.measure(buf, font) > maxW do buf = dropChar(buf) end
if #buf == 0 then break end
line = rest:sub(1, #buf)
rest = trim(rest:sub(#buf + 1))
end
out[#out + 1] = line
end
return out
end
local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function jstr(s)
local r = tostring(s):gsub('[%c"\\]', function(c) return ESC[c] or string.format("\\u%04x", c:byte()) end)
return '"' .. r .. '"'
end
local function enc(v)
local t = type(v)
if t == "string" then return jstr(v) end
if t == "number" then return string.format("%d", math.floor(v)) end
if t == "boolean" then return v and "true" or "false" end
if t == "table" then
if #v > 0 or next(v) == nil then
local p = {}
for i = 1, #v do p[i] = enc(v[i]) end
return "[" .. table.concat(p, ",") .. "]"
end
local keys = {}
for k in pairs(v) do keys[#keys + 1] = k end
table.sort(keys)
local p = {}
for _, k in ipairs(keys) do p[#p + 1] = jstr(k) .. ":" .. enc(v[k]) end
return "{" .. table.concat(p, ",") .. "}"
end
return "null"
end
local function int(x) return math.floor(tonumber(x) or 0) end
local function strList(t, maxN)
local out = {}
if type(t) == "table" then
for _, v in ipairs(t) do
if type(v) == "string" and v ~= "" and #out < maxN then out[#out + 1] = v end
end
end
return out
end
local function loadRecipe()
local raw = file.read("recipe")
if type(raw) ~= "string" or raw == "" then return nil end
local t = json.decode(raw)
if type(t) ~= "table" then return nil end
local d = {
raw = raw, title = tostring(t.title or ""), source = tostring(t.source or ""), url = tostring(t.pageUrl or ""),
yield = tostring(t.yield or ""), time = tostring(t.time or ""), base = int(t.baseServings), cur = int(t.currentServings),
ing = strList(t.ingredients, MAX_ING), steps = strList(t.steps, MAX_STEPS), nut = {},
}
if type(t.nutrition) == "table" then
for _, p in ipairs(t.nutrition) do
if type(p) == "table" and #d.nut < MAX_NUT then d.nut[#d.nut + 1] = { tostring(p.label or ""), tostring(p.value or "") } end
end
end
if d.title == "" and #d.ing == 0 and #d.steps == 0 then return nil end
if d.base < 0 then d.base = 0 end
if d.cur < 1 then d.cur = d.base end
return d
end
local function saveRecipe(d)
local nut = {}
for _, p in ipairs(d.nut) do nut[#nut + 1] = { label = p[1], value = p[2] } end
local doc = {
title = d.title, source = d.source, pageUrl = d.url, yield = d.yield, time = d.time,
baseServings = d.base, currentServings = d.cur, ingredients = d.ing, steps = d.steps, nutrition = nut,
}
return file.write("recipe", enc(doc))
end
local function bump(ctx) ctx.data.set("rv", (int(ctx.data.get("rv")) + 1) % 100000) end
local function clearBrowse(ctx)
ctx.data.set("browse", nil)
ctx.data.set("bt", nil)
end
local function browsing(ctx)
if ctx.data.get("browse") ~= 1 then return false end
local bt = int(ctx.data.get("bt"))
if bt <= 0 then return true end
local age = time.now() - bt
return age < 0 or age < BROWSE_SECONDS -- Uhr zurueckgesprungen: Modus bleibt
end
local getLayout -- Vorwaertsdeklaration: on_http (Seitenzahl fuer die Handy-Seite) steht vor der Seitenaufteilung
function on_fetch(ctx)
local url = ctx.data.get("pu")
if type(url) ~= "string" or url == "" then return true end
ctx.data.set("pu", nil)
local r, err = recipe.fetch(url)
if r == nil then
ctx.data.set("st", "error")
ctx.data.set("err", cutBytes(tostring(err or "Abruf fehlgeschlagen"), 200))
log("Rezept: " .. tostring(err))
return true
end
local d = {
title = clean(r.title, 95), source = clean(r.source, 47), url = cutBytes(tostring(r.url or ""), 159), yield = clean(r.yield, 31),
time = clean(r.time, 31), base = int(r.base_servings), cur = int(r.base_servings), ing = {}, steps = {}, nut = {},
}
for _, v in ipairs(r.ingredients or {}) do
local c = clean(v, ING_BYTES)
if c ~= "" and #d.ing < MAX_ING then d.ing[#d.ing + 1] = c end
end
for _, v in ipairs(r.steps or {}) do
local c = clean(v, STEP_BYTES)
if c ~= "" and #d.steps < MAX_STEPS then d.steps[#d.steps + 1] = c end
end
for _, p in ipairs(r.nutrition or {}) do
local l, v = clean(p[1], 19), clean(p[2], 27)
if l ~= "" and #d.nut < MAX_NUT then d.nut[#d.nut + 1] = { l, v } end
end
local ok, werr = saveRecipe(d)
if not ok then
ctx.data.set("st", "error")
ctx.data.set("err", cutBytes(tostring(werr or "Speichern fehlgeschlagen"), 200))
return true
end
ctx.data.set("st", "ok")
ctx.data.set("err", "")
ctx.data.set("pg", 0)
clearBrowse(ctx)
bump(ctx)
log("Rezept geladen: " .. d.title)
return true
end
local function reply(status, tbl, fetch, redraw)
return { status = status, body = enc(tbl), fetch = fetch, redraw = redraw }
end
local function manualLines(src, asSteps, maxN, maxLen)
local out = {}
for line in (tostring(src or "") .. "\n"):gmatch("([^\n]*)\n") do
local s = line:gsub("^[ \t\r]+", "")
if s:sub(1, 1) == "-" or s:sub(1, 1) == "*" then
s = s:sub(2)
elseif s:sub(1, 3) == "\226\128\162" then
s = s:sub(4)
elseif asSteps then
local num = s:match("^%d+[%.%)]")
if num ~= nil then s = s:sub(#num + 1) end
end
local c = clean(s, maxLen)
if c ~= "" and #out < maxN then out[#out + 1] = c end
end
return out
end
function on_http(ctx, req)
local q = json.decode(req.body or "")
if type(q) ~= "table" then return reply(400, { error = "JSON" }) end
local op = tostring(q.op or "")
local d = loadRecipe()
if op == "status" then
local st = ctx.data.get("st")
if st ~= "pending" and st ~= "ok" and st ~= "error" then st = "idle" end
local pages = 0
if d ~= nil and st ~= "pending" then pages = #getLayout(d).pages end -- ScriptMeasureGfx: dieselben Textmasse wie beim Zeichnen
local out = {
pages = pages,
state = st, error = tostring(ctx.data.get("err") or ""), valid = d ~= nil,
title = d and d.title or "", source = d and d.source or "", yield = d and d.yield or "", time = d and d.time or "",
baseServings = d and d.base or 0, currentServings = d and d.cur or 0,
ingredients = d and #d.ing or 0, steps = d and #d.steps or 0, nutrition = d and #d.nut or 0,
}
if st == "ok" or st == "error" then ctx.data.set("st", "idle") end -- einmal ausgeliefert, dann zurueck auf idle
return reply(200, out)
end
if op == "recipe" then
if d == nil then return reply(200, { valid = false }) end
local ing = {}
for i, v in ipairs(d.ing) do
ing[i] = (d.base > 0 and d.cur ~= d.base) and recipe.scale(v, d.base, d.cur) or v
end
local nut = {}
for i, p in ipairs(d.nut) do nut[i] = { p[1], p[2] } end
return reply(200, {
valid = true, title = d.title, source = d.source, url = d.url, yield = d.yield, time = d.time,
baseServings = d.base, currentServings = d.cur, ingredients = ing, steps = d.steps, nutrition = nut,
})
end
if op == "url" then
local url = trim(tostring(q.url or ""))
if url:sub(1, 7) == "http://" then url = "https://" .. url:sub(8) end
if #url < 12 or url:sub(1, 8) ~= "https://" then
return reply(200, { success = false, error = T(ctx, "Bitte einen vollständigen Link einfügen.", "Please paste a complete link.") })
end
if #url > 1000 then
return reply(200, { success = false, error = T(ctx, "Der Link ist zu lang.", "The link is too long.") })
end
local now = time.now()
local since = int(ctx.data.get("pt"))
if ctx.data.get("st") == "pending" and since > 0 and now - since < 180 then
return reply(200, { success = false, error = T(ctx, "Es läuft bereits ein Abruf.", "A fetch is already running.") })
end
ctx.data.set("pu", url)
ctx.data.set("st", "pending")
ctx.data.set("err", "")
ctx.data.set("pt", now)
return reply(200, { success = true }, true)
end
if op == "manual" then
local en = ctx.lang == "en"
local n = {
title = clean(q.title, 95), source = en and "Pasted manually" or "Manuell eingefügt", url = "", time = "", yield = clean(q.yield, 31),
base = 0, cur = 0, nut = {},
}
if n.title == "" then n.title = en and "Recipe" or "Rezept" end
if n.yield ~= "" and not n.yield:find("%D") then n.yield = n.yield .. (en and " servings" or " Portionen") end
n.base = int(n.yield:match("%d+"))
n.cur = n.base
n.ing = manualLines(q.ingredients, false, MAX_ING, ING_BYTES)
n.steps = manualLines(q.steps, true, MAX_STEPS, STEP_BYTES)
if #n.ing == 0 and #n.steps == 0 then
return reply(200, { success = false, error = T(ctx, "Bitte Zutaten oder Zubereitung einfügen.", "Please paste ingredients or steps.") })
end
local ok, err = saveRecipe(n)
if not ok then return reply(200, { success = false, error = tostring(err or "Speichern fehlgeschlagen") }) end
ctx.data.set("pg", 0)
clearBrowse(ctx)
bump(ctx)
return reply(200, { success = true, ingredients = #n.ing, steps = #n.steps }, nil, true)
end
if op == "clear" then
file.write("recipe", "")
ctx.data.set("pg", 0)
clearBrowse(ctx)
bump(ctx)
return reply(200, { success = true }, nil, true)
end
if op == "servings" then
if d == nil or d.base <= 0 then
return reply(200, { success = false, error = T(ctx, "Für dieses Rezept konnte keine Portionenzahl erkannt werden.", "No serving count could be detected for this recipe.") })
end
local s = int(q.servings)
if s < 1 or s > 99 then
return reply(200, { success = false, error = T(ctx, "Ungültige Portionenzahl (1-99).", "Invalid serving count (1-99).") })
end
d.cur = s
local ok, err = saveRecipe(d)
if not ok then return reply(200, { success = false, error = tostring(err or "Speichern fehlgeschlagen") }) end
bump(ctx)
return reply(200, { success = true, currentServings = s }, nil, true)
end
return reply(400, { error = "op" })
end
local function titleLayout(d)
local lines = wrap(d.title, draw.width - 2 * MX, "large", 2)
local n = #lines
if n <= 0 then n = 1 end
local last = TITLE_BASE + (n - 1) * TITLE_LH
local meta = last + 28
local sec = meta + 30
return { lines = lines, n = n, meta = meta, sec = sec, top = sec + 16 }
end
local function layoutIng(d, top, start, doDraw)
local colW = (draw.width - 2 * MX - 28) // 2
local textW = colW - 18
local col, y, consumed, i = 0, top, 0, start
while i <= #d.disp do
local lines = wrap(d.disp[i], textW, "normal", 3)
local lc = #lines
if lc == 0 then lc = 1 end
local itemH = lc * 24 + 10
if y + itemH > CONTENT_BOTTOM then
if col == 0 then
col = 1 -- linke Spalte voll: dieselbe Zutat oben in der rechten Spalte erneut versuchen
y = top
else
break
end
else
if doDraw then
local x = MX + col * (colW + 28)
draw.circle(x + 5, y + 10, 4, color.ACCENT, true)
draw.circle(x + 5, y + 10, 4, color.BLACK, false)
for ln = 1, #lines do draw.text(x + 18, y + 16 + (ln - 1) * 24, lines[ln], "normal", color.BLACK, "left") end
end
y = y + itemH
consumed = consumed + 1
i = i + 1
end
end
return consumed
end
local function layoutSteps(d, top, start, doDraw)
local textX = MX + 40
local textW = draw.width - MX - textX
local y, consumed = top, 0
for i = start, #d.steps do
local lines = wrap(d.steps[i], textW, "normal", 5)
local lc = #lines
if lc == 0 then lc = 1 end
local itemH = lc * 24 + 18
if y + itemH > CONTENT_BOTTOM then break end
if doDraw then
local cy = y + 12
draw.circle(MX + 13, cy, 13, color.ACCENT, true)
draw.text(MX + 13, cy + 4, tostring(i), "small", color.ACCENT_INK, "center")
for ln = 1, #lines do draw.text(textX, y + 16 + (ln - 1) * 24, lines[ln], "normal", color.BLACK, "left") end
end
y = y + itemH
consumed = consumed + 1
end
return consumed
end
local function layoutNut(d, top, start, doDraw)
local rowH = 34
local halfW = (draw.width - 2 * MX - 16) // 2
local y, consumed = top, 0
for i = start, #d.nut do
if y + rowH > CONTENT_BOTTOM then break end
if doDraw then
draw.text(MX, y + 22, fit(d.nut[i][1], halfW, "normal"), "normal", color.BLACK, "left")
draw.text(draw.width - MX, y + 22, fit(d.nut[i][2], halfW, "normal"), "normal", color.BLACK, "right")
draw.line(MX, y + rowH - 6, draw.width - MX, y + rowH - 6, color.BLACK)
end
y = y + rowH
consumed = consumed + 1
end
return consumed
end
local LAYOUT = { key = nil }
function getLayout(d)
local key = d.raw .. "#" .. d.cur
if LAYOUT.key == key then return LAYOUT end
d.disp = {}
for i, v in ipairs(d.ing) do
local shown = v
if d.base >= 1 and d.cur >= 1 and d.cur ~= d.base then shown = recipe.scale(v, d.base, d.cur) end
d.disp[i] = cutBytes(shown, 111)
end
local tl = titleLayout(d)
local pages = {}
local function add(kind, count, fn)
local idx = 1
while idx <= count and #pages < MAX_PAGES do
local n = fn(d, tl.top, idx, false)
if n <= 0 then n = 1 end
pages[#pages + 1] = { s = kind, from = idx, n = n }
idx = idx + n
end
end
add("i", #d.disp, layoutIng)
add("s", #d.steps, layoutSteps)
add("n", #d.nut, layoutNut)
if #pages == 0 then pages[1] = { s = "i", from = 1, n = 0 } end
LAYOUT.key, LAYOUT.tl, LAYOUT.pages, LAYOUT.disp = key, tl, pages, d.disp
return LAYOUT
end
local function pageIndex(ctx, count)
local p = int(ctx.data.get("pg"))
if p < 0 or p >= count then p = 0 end
return p
end
function on_input(ctx, kind, n)
local d = loadRecipe()
if d == nil then return false end
if kind == "click" then
if ctx.data.get("browse") == 1 then
local active = browsing(ctx)
clearBrowse(ctx)
return active
end
return false
end
local lay = getLayout(d)
local total = #lay.pages
if total <= 1 then return "blip" end
ctx.data.set("browse", 1)
ctx.data.set("bt", time.now())
ctx.data.set("pg", (pageIndex(ctx, total) + int(n)) % total)
return true
end
local function drawEmpty(ctx)
if device.qrscreen and device.qrscreen(T(ctx, "Noch kein Rezept geladen", "No recipe loaded yet"), T(ctx, "QR-Code scannen, um ein Rezept zu laden:", "Scan the QR code to load a recipe:")) then
return
end
local cx = draw.width // 2
local topY = draw.top
draw.text(cx, topY + 44, T(ctx, "Noch kein Rezept geladen", "No recipe loaded yet"), "large", color.BLACK, "center")
draw.text(cx, topY + 90, T(ctx, "Das Gerät braucht eine WLAN-Verbindung, dann erscheint hier ein QR-Code.", "The device needs a Wi-Fi connection; a QR code will appear here."), "normal", color.BLACK, "center")
end
function on_draw(ctx, page)
draw.clear(color.WHITE)
local d = loadRecipe()
if d == nil then
drawEmpty(ctx)
return
end
local lay = getLayout(d)
d.disp = lay.disp
local tl, pages = lay.tl, lay.pages
local total = #pages
local pg = pageIndex(ctx, total)
local p = pages[pg + 1]
local W = draw.width
for ln = 1, #tl.lines do
draw.text(MX, TITLE_BASE + (ln - 1) * TITLE_LH, tl.lines[ln], "large", color.BLACK, "left")
end
local yieldShown = d.yield
if d.base > 0 and d.cur > 0 and d.cur ~= d.base then
yieldShown = d.cur .. " " .. T(ctx, "Portionen", "servings")
end
local meta = {}
for _, part in ipairs({ d.source, yieldShown, d.time }) do
if part ~= "" then meta[#meta + 1] = part end
end
if #meta > 0 then
draw.text(MX, tl.meta, fit(table.concat(meta, " · "), W - 2 * MX, "small"), "small", color.BLACK, "left")
end
local secTotal, secNo = 0, 0
for i, q in ipairs(pages) do
if q.s == p.s then
secTotal = secTotal + 1
if i <= pg + 1 then secNo = secNo + 1 end
end
end
draw.rect(MX, tl.sec - 12, 6, 15, color.ACCENT, true)
local name
if p.s == "i" then name = T(ctx, "ZUTATEN", "INGREDIENTS")
elseif p.s == "s" then name = T(ctx, "ZUBEREITUNG", "PREPARATION")
else name = T(ctx, "NÄHRWERTE", "NUTRITION") end
if secTotal > 1 then name = name .. " (" .. secNo .. "/" .. secTotal .. ")" end
draw.text(MX + 14, tl.sec, name, "small", color.BLACK, "left")
draw.line(MX, tl.sec + 8, W - MX, tl.sec + 8, color.BLACK)
if p.s == "i" then layoutIng(d, tl.top, p.from, true)
elseif p.s == "s" then layoutSteps(d, tl.top, p.from, true)
else layoutNut(d, tl.top, p.from, true) end
draw.line(MX, FOOTER_BASE - 16, W - MX, FOOTER_BASE - 16, color.BLACK)
draw.text(MX, FOOTER_BASE, T(ctx, "Seite ", "Page ") .. (pg + 1) .. T(ctx, " von ", " of ") .. total, "small", color.BLACK, "left")
if total > 1 then
local hint
if browsing(ctx) then
hint = T(ctx, "Drehen blättert · Knopf: fertig", "Turn to flip · press: done")
else
hint = T(ctx, "Blättern: Drehen", "Browse: turn the dial")
end
draw.text(W - MX, FOOTER_BASE, hint, "small", color.BLACK, "right")
end
end
