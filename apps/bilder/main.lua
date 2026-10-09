local EN = false
local function T(de, en) if EN then return en end return de end
local PIC = "pic"          -- Name des Arbeitsspeicher-Bilds
local BROWSE_S = 45        -- so lange bleibt die Positions-Pille nach dem Blaettern (PAGE_MODE_TIMEOUT_MS)
local TRIES = 8            -- so viele Bilder werden je Lauf hoechstens probiert (die eingebaute App ueberspringt defekte Bilder ohne Grenze)
local MAX_BYTES = 16777216 -- groesste erlaubte Datei (die eingebaute App hat kein Limit; hier die Obergrenze der API)
local function indexOf(names, name)
if name == nil then return nil end
for i = 1, #names do
if names[i] == name then return i end
end
return nil
end
local function sign(x)
if x > 0 then return 1 end
if x < 0 then return -1 end
return 0
end
local function pickRandom(count, avoid)
if count <= 1 then return 1 end
local seed = (time.now() or 0) % 1000003
local i = (seed * 7919 + count * 104729) % count + 1
if i == avoid then i = i % count + 1 end
return i
end
local function loadPicture(name)
local w, h = storage.image("dir", name, PIC, { w = 800, h = 480, style = "photo", maxBytes = MAX_BYTES })
return w, h
end
local function browsing(d)
local bt = tonumber(d.get("bt"))
if bt == nil then return false end
local now = time.now()
if now == nil then return true end
return bt > 0 and now - bt >= 0 and now - bt <= BROWSE_S
end
function on_fetch(ctx)
local d = ctx.data
local cfg = ctx.cfg or {}
EN = (ctx.lang == "en")
local steps = tonumber(d.get("go"))     -- aufsummierte Schritte der Drehung (nil = keine Bedienung)
d.set("go", nil)
local want = d.get("to")                -- dieses Bild als Naechstes zeigen (Studio "Speichern")
d.set("to", nil)
local opened = ctx.opened == true
local picLoaded = draw.image_size(PIC) ~= nil
local showing = picLoaded and d.get("st") == "ok"
local names, count = storage.list("dir", { max = 60 })
if names == nil then
local msg = tostring(count)
if msg:find("kein externer Speicher", 1, true) then
d.set("e", msg)
d.set("st", "nonas")
return true
end
if showing then return true end
d.set("e", msg)
return false
end
d.set("c", #names)
if #names == 0 then
d.set("st", "empty")
d.set("n", nil)
d.set("i", nil)
d.set("e", nil)
return true
end
local cur = indexOf(names, d.get("n"))
local had = cur ~= nil
if cur == nil then
cur = tonumber(d.get("i")) or 1
if cur < 1 or cur > #names then cur = 1 end
end
local target = cur
local dir = 1
if want ~= nil then
target = indexOf(names, want) or cur
elseif steps ~= nil then
local sg = sign(steps)
if sg == 0 then return true end       -- Rastungen heben sich auf: nichts zu tun
dir = sg
target = (cur - 1 + sg) % #names + 1
elseif had and not opened and #names > 1 then
if cfg.order == "zufall" then target = pickRandom(#names, cur) else target = cur % #names + 1 end
end
if target == cur and had and picLoaded and d.get("st") == "ok" and (want == nil or want == d.get("n")) then
return true -- nichts zu tun (Oeffnen mit Bild im Speicher, ein einziges Bild)
end
local tried = 0
local lastErr = nil
while tried < TRIES and tried < #names do
local w, h = loadPicture(names[target])
if w ~= nil then
if names[target] == d.get("n") then
d.set("rl", (tonumber(d.get("rl")) or 0) + 1) -- dasselbe Bild neu geladen (Neustart): Daten aendern, damit neu gezeichnet wird
end
d.set("n", names[target])
d.set("i", target)
d.set("st", "ok")
d.set("e", nil)
return true
end
lastErr = tostring(h)
tried = tried + 1
target = (target - 1 + dir) % #names + 1
end
if showing then return true end          -- das alte Bild steht noch: nichts aendern, naechster Versuch im naechsten Takt
d.set("st", "err")
d.set("e", lastErr or "")
d.set("i", target)
d.set("n", nil)
return true
end
function on_input(ctx, kind, n)
local d = ctx.data
if kind == "turn" then
if (tonumber(d.get("c")) or 0) < 2 then return "blip" end -- 1 Bild oder keins: Drehen ohne Wirkung (Doppelblip)
d.set("go", (tonumber(d.get("go")) or 0) + n)
d.set("bt", time.now() or 0)
return "fetch"
end
if browsing(d) then
d.set("bt", nil)
return "redraw"
end
return false
end
local function pill(text, cx)
local bw, bh = 200, 28
local bx = cx - bw // 2
local by = draw.height - bh - 10
draw.rect(bx, by, bw, bh, color.WHITE, true, 9)
draw.rect(bx, by, bw, bh, color.BLACK, false, 9)
draw.text(cx, by + 19, text, "small", color.BLACK, "center")
end
local function notice(cx, lines)
draw.rect(cx - 22, 124, 44, 44, color.BLUE, true, 22)
draw.text(cx, 153, "?", "large", color.WHITE, "center")
draw.text(cx, 200, T("Noch keine Bilder", "No pictures yet"), "large", color.BLACK, "center")
for i = 1, #lines do
draw.text(cx, lines[i][1], lines[i][2], "normal", color.BLACK, "center")
end
end
local QR_CAPS = { 53, 78, 106, 134, 154, 192 }
local function qrSize(s, maxSize)
for i, cap in ipairs(QR_CAPS) do
if #s <= cap then
local modules = 4 * (i + 2) + 17
local scale = math.min(6, maxSize // modules)
if scale < 2 then return 0 end
return modules * scale
end
end
return 0
end
local function drawQrPage(cx, nonas)
draw.text(cx, 52, T("Noch keine Bilder", "No pictures yet"), "large", color.BLACK, "center")
local url = device.url()
if url == nil then
draw.text(cx, 100, T("Das Gerät braucht eine WLAN-Verbindung, dann erscheint hier ein QR-Code.", "The device needs a Wi-Fi connection; a QR code will appear here."), "normal", color.BLACK, "center")
return
end
draw.text(cx, 90, T("QR-Code mit dem Handy scannen und dort ein Bild auswählen -", "Scan the QR code with your phone and choose a picture there -"), "normal", color.BLACK, "center")
if nonas then
draw.text(cx, 114, T("\"Direkt anzeigen\" geht ohne Speicher; für die Diashow den NAS einrichten.", "\"Show once\" works without storage; set up the NAS for the slideshow."), "normal", color.BLACK, "center")
else
draw.text(cx, 114, T("direkt anzeigen oder für die Diashow speichern.", "show it once or save it for the slideshow."), "normal", color.BLACK, "center")
end
local size = qrSize(url, 230)
if size == 0 then return end
local pad = 10
local qx, qy = cx - size // 2, 148
size = draw.qr(url, qx, qy, 230) or size
draw.rect(qx - pad, qy - pad, size + pad * 2, size + pad * 2, color.BLACK, false, 12)
draw.rect(qx - pad + 1, qy - pad + 1, size + pad * 2 - 2, size + pad * 2 - 2, color.BLACK, false, 11)
draw.text(cx, qy + size + pad + 26, url, "normal", color.BLACK, "center")
end
function on_http(ctx, req)
return { status = 404, body = "{}" }
end
function on_draw(ctx, page)
EN = (ctx.lang == "en")
local d = ctx.data
local cfg = ctx.cfg or {}
local cx = draw.width // 2
draw.clear(color.WHITE)
local st = d.get("st")
local w, h = draw.image_size(PIC)
if st == "ok" and w ~= nil then
local x = (draw.width - w) // 2
local y = (draw.height - h) // 2
draw.image(PIC, x, y)
if cfg.frame ~= false then draw.rect(x - 1, y - 1, w + 2, h + 2, color.BLACK) end
if browsing(d) then
pill(string.format("%s %d %s %d", T("Bild", "Picture"), tonumber(d.get("i")) or 1, T("von", "of"), tonumber(d.get("c")) or 1), cx)
end
return
end
if st == "nonas" or st == "empty" then
drawQrPage(cx, st == "nonas")
return
end
notice(cx, {
{ 244, T("Bilder in Studio unter Apps -> Bilder hochladen -", "Upload pictures in Studio under Apps -> Pictures -") },
{ 268, T("gespeicherte Bilder laufen hier als Diashow.", "saved pictures play here as a slideshow.") },
})
end
