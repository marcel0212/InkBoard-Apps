-- Bild des Tages: Wikimedia Commons "Bild des Tages" (ohne Schluessel) oder NASA "Astronomy Picture of the Day".
-- Skript-API Level 18 (http.image mit ram = true). Das Bild liegt im Arbeitsspeicher und wird nach einem Neustart neu geladen.
--#include theme
--#include text
--#include ui

local PIC = "potd"

-- Wikitext -> Klartext (Verweise [[a|b]] -> b, Vorlagen und Formatierung raus)
local function wiki(s)
  s = tostring(s or "")
  for _ = 1, 3 do s = s:gsub("{{[^{}]*}}", "") end
  s = s:gsub("%[%[[^%]|]*|([^%]]*)%]%]", "%1")
  s = s:gsub("%[%[:?([^%]]*)%]%]", "%1")
  s = s:gsub("%[https?://%S+ ([^%]]*)%]", "%1")
  s = s:gsub("'''?", "")
  s = s:gsub("<[^>]*>", "")
  s = s:gsub("&nbsp;", " "):gsub("&amp;", "&"):gsub("&quot;", '"'):gsub("&#039;", "'")
  s = s:gsub("%s+", " ")
  return clean(s, 700)
end

local function stripTags(s)
  s = tostring(s or ""):gsub("<[^>]*>", ""):gsub("&nbsp;", " "):gsub("&amp;", "&"):gsub("&quot;", '"'):gsub("&#039;", "'")
  return clean(s, 120)
end

local function fileTitle(name)
  local t = name:gsub("^[Ff]ile:", ""):gsub("%.%w+$", ""):gsub("_", " ")
  return clean(t, 90)
end

local function loadImage(url, w, h)
  local ok, err = http.image(url, PIC, w, h, { ram = true })
  if ok then return true end
  -- Zu gross fuer den Download (300 KB)? Wikimedia-Vorschaubild in kleinerer Breite nochmal versuchen.
  for _, px in ipairs({ 560, 360 }) do
    local small = url:gsub("/(%d+)px%-", "/" .. px .. "px-")
    if small ~= url then
      ok, err = http.image(small, PIC, w, h, { ram = true })
      if ok then return true end
    end
  end
  return false, err
end

local function setCommon(ctx, title, desc, credit, src, day, hasImg, err)
  ctx.data.set("title", title)
  ctx.data.set("desc", desc)
  ctx.data.set("credit", credit)
  ctx.data.set("src", src)
  ctx.data.set("day", day)
  ctx.data.set("img", hasImg and "1" or "0")
  ctx.data.set("err", err or "")
end

-- Quelle 1: Wikimedia Commons
local function fetchCommons(ctx, day, en)
  local ex = "{{Potd/" .. day .. "}}@@{{Potd/" .. day .. " (en)}}@@{{Potd/" .. day .. " (de)}}"
  local body, err = http.get("https://commons.wikimedia.org/w/api.php?action=expandtemplates&format=json&prop=wikitext&text=" .. text.url_encode(ex), 12288)
  if not body then return nil, "Commons: " .. tostring(err) end
  local doc = json.decode(body)
  local wt = doc and doc.expandtemplates and doc.expandtemplates.wikitext
  if not wt then return nil, "Commons: keine Antwort" end
  local file, d_en, d_de = wt:match("^(.-)@@(.-)@@(.*)$")
  if not file then return nil, "Commons: unbekanntes Format" end
  file = clean(file, 200)
  if file == "" or file:find("Template:", 1, true) then return nil, "Heute noch kein Bild" end
  if not file:lower():match("^file:") then file = "File:" .. file end
  local desc = en and d_en or d_de
  if desc:find("Template:", 1, true) or #wiki(desc) < 3 then desc = d_en end
  desc = wiki(desc)

  time.sleep(300)
  local url = "https://commons.wikimedia.org/w/api.php?action=query&format=json&prop=imageinfo&iiprop=url%7Cextmetadata&iiurlwidth=800"
    .. "&iiextmetadatafilter=Artist%7CLicenseShortName%7CObjectName&titles=" .. text.url_encode(file)
  local b2, e2 = http.get(url, 12288)
  if not b2 then return nil, "Commons: " .. tostring(e2) end
  local d2 = json.decode(b2)
  local page = d2 and d2.query and d2.query.pages
  local info
  if page then for _, p in pairs(page) do info = p.imageinfo and p.imageinfo[1] end end
  if not info or not info.thumburl then return nil, "Commons: kein Bild" end
  local md = info.extmetadata or {}
  local title = md.ObjectName and stripTags(md.ObjectName.value) or ""
  if title == "" or #title > 90 then title = fileTitle(file) end
  local artist = md.Artist and stripTags(md.Artist.value) or ""
  local lic = md.LicenseShortName and stripTags(md.LicenseShortName.value) or ""
  local credit = cut(artist, 50)
  if lic ~= "" then credit = (credit ~= "" and (credit .. ", ") or "") .. cut(lic, 24) end
  time.sleep(300)
  local ok, ierr = loadImage(info.thumburl, 760, 420)
  return { title = title, desc = desc, credit = credit, img = ok, err = ok and "" or ("Bild: " .. tostring(ierr)) }
end

-- Quelle 2: NASA APOD (eigener Schluessel, sonst DEMO_KEY mit Tageslimit); Texte nur auf Englisch
local function fetchApod(ctx, day)
  local key = ctx.cfg.apodKey
  if key == nil or key == "" then key = "DEMO_KEY" end
  local body, err = http.get("https://api.nasa.gov/planetary/apod?thumbs=true&api_key=" .. text.url_encode(key), 12288)
  if not body then return nil, "NASA: " .. tostring(err) end
  local d = json.decode(body)
  if type(d) ~= "table" or not d.title then return nil, "NASA: Antwort ohne Bild (Limit erreicht?)" end
  local src = d.media_type == "image" and d.url or d.thumbnail_url
  local ok, ierr = false, "kein Bild (Video)"
  if src then
    time.sleep(300)
    ok, ierr = loadImage(src, 760, 420)
  end
  local credit = d.copyright and ("(c) " .. clean(d.copyright, 50)) or "NASA"
  return { title = clean(d.title, 90), desc = clean(d.explanation, 700), credit = credit, img = ok, err = ok and "" or ("Bild: " .. tostring(ierr)) }
end

function on_fetch(ctx)
  local day = time.today()
  if not day then return false end
  local src = ctx.cfg.source == "apod" and "apod" or "commons"
  if ctx.data.get("day") == day and ctx.data.get("src") == src and ctx.data.get("img") == "1" and draw.image_size(PIC) then
    return true -- schon geladen
  end
  local en = (ctx.lang == "en")
  local r, err
  if src == "apod" then r, err = fetchApod(ctx, day) else r, err = fetchCommons(ctx, day, en) end
  if not r then
    log("Bild des Tages: " .. tostring(err))
    ctx.data.set("err", clean(err, 120))
    return false
  end
  setCommon(ctx, r.title, r.desc, r.credit, src, day, r.img, r.err)
  return true
end

local SAMPLE = false -- Vorschau (ohne Netz): gezeichnetes Beispielbild statt Foto
local smp = {}
local function dget(ctx, k)
  if SAMPLE and smp[k] ~= nil then return smp[k] end
  return ctx.data.get(k)
end

local function imgBox()
  if SAMPLE then return 760, 420 end
  local w, h = draw.image_size(PIC)
  return w, h
end

-- Bild in die Box (maxW x maxH) einpassen; liefert Breite und Hoehe
local function fitBox(maxW, maxH)
  local iw, ih = imgBox()
  local sc = math.min(maxW / iw, maxH / ih)
  return math.max(1, math.floor(iw * sc)), math.max(1, math.floor(ih * sc))
end

local function blit(x, y, dw, dh)
  if not SAMPLE then draw.image(PIC, x, y, dw, dh); return end
  draw.rect(x, y, dw, dh, color.BLUE, true)
  draw.rect(x, y + dh * 6 // 10, dw, dh - dh * 6 // 10, color.GREEN, true)
  draw.rect(x + dw * 69 // 100, y + dh // 8, dw // 8, dw // 8, color.YELLOW, true, dw // 16)
  draw.rect(x + dw // 13, y + dh * 6 // 10 - dh // 8, dw * 29 // 100, dh // 4, color.WHITE, true, dh // 8)
end

local function drawText(x, y, w, ctx, en, full)
  local title = dget(ctx, "title") or ""
  local lines = draw.wrap(x, y, w, title, "medium", color.BLACK)
  y = y + lines * 32 + 6
  local desc = dget(ctx, "desc") or ""
  if desc ~= "" then
    local room = (draw.height - 70 - y) // 24
    if not full then room = math.min(room, 6) end
    local shown = wrapLines(desc, w, "normal", math.max(room, 1))
    for _, ln in ipairs(shown) do
      draw.text(x, y + 20, ln, "normal", color.BLACK, "left")
      y = y + 24
    end
  end
end

function on_draw(ctx, page)
  local en = (ctx.lang == "en")
  setStyle(ctx.cfg.style)
  draw.clear(color.WHITE)
  SAMPLE = false
  local title = ctx.data.get("title")
  if ctx.data.get("demo") == "1" or (title == nil and ctx.preview == true) then
    SAMPLE = true
    smp.title = en and "Sunrise over the lake" or "Sonnenaufgang am See"
    smp.desc = en and "A calm morning at the lake: mist rises over the water while the first light reaches the hills on the far shore." or "Ein ruhiger Morgen am See: Nebel steigt über dem Wasser auf, während das erste Licht die Hügel am anderen Ufer erreicht."
    smp.credit = "Beispiel, CC BY-SA 4.0"
    smp.src = "commons"
    title = smp.title
  end
  if title == nil then
    local err = dget(ctx, "err") or ""
    if err ~= "" then
      notice("error", en and "Picture not loaded" or "Bild nicht geladen", err)
    else
      notice("loading", en and "Loading ..." or "Wird geladen ...")
    end
    return
  end
  local fancy = theme.s == "relief" or theme.s == "klar" or theme.s == "cards"
  local credit = dget(ctx, "credit") or ""
  local srcName = dget(ctx, "src") == "apod" and "NASA APOD" or "Wikimedia Commons"
  local hasImg = SAMPLE or (dget(ctx, "img") == "1" and draw.image_size(PIC) ~= nil)
  local tall = draw.height > draw.width
  local top, bottom = draw.top + 14, draw.height - 16

  if page == 2 and hasImg then
    -- Seite 2: Bild (klein) + Titel und Kurztext
    if tall then
      local dw, dh = fitBox(draw.width - 48, 396)
      local ix = (draw.width - dw) // 2
      if theme.s == "relief" then draw.rect(ix + 5, top + 5, dw, dh, color.BLACK, true) end
      blit(ix, top, dw, dh)
      draw.rect(ix, top, dw, dh, color.BLACK, false)
      local ty = top + dh + 26
      draw.wrap(24, ty, draw.width - 48, dget(ctx, "title") or "", "medium", color.BLACK)
      draw.text(24, bottom - 8, fit(srcName .. (credit ~= "" and (" - " .. credit) or ""), draw.width - 48, "small"), "small", color.ACCENT_TEXT, "left")
      return
    end
    local bx, bw, bh = 36, 520, bottom - top
    local dw, dh = fitBox(bw, 396)
    local ix = bx + (bw - dw) // 2
    local iy = top + (bh - dh) // 2
    if theme.s == "relief" then draw.rect(ix + 5, iy + 5, dw, dh, color.BLACK, true) end
    blit(ix, iy, dw, dh)
    if theme.s ~= "klar" then draw.rect(ix, iy, dw, dh, color.BLACK, false) end
    local tx = bx + bw + 26
    local tw = draw.width - tx - 28
    if tw < 100 then return end
    if fancy then card(tx - 14, top, tw + 28 - 4, bh, color.ACCENT, theme.s == "relief" and 16 or 22); tx = tx + 8; tw = tw - 16 end
    drawText(tx, top + 40, tw, ctx, en, false)
    draw.text(tx, bottom - 14, fit(credit, tw, "small"), "small", color.ACCENT_TEXT, "left")
    return
  end

  if not hasImg then
    -- Ohne Bild: Textseite (Titel, ganze Beschreibung, Quelle)
    local x, y, w, h = 40, top, draw.width - 80, bottom - top
    if fancy then card(x, y, w, h, color.ACCENT, theme.s == "relief" and 16 or 22) end
    drawText(x + 28, y + 40, w - 56, ctx, en, true)
    draw.text(x + 28, y + h - 18, fit(srcName .. (credit ~= "" and (" - " .. credit) or ""), w - 56, "small"), "small", color.ACCENT_TEXT, "left")
    local e = dget(ctx, "err") or ""
    if e ~= "" then draw.text(x + w - 28, y + 24, fit(e, w // 2, "small"), "small", color.RED, "right") end
    return
  end

  -- Seite 1: grosses Bild, darunter nur der Titel
  local strip = 44
  local dw, dh = fitBox(draw.width - 32, bottom - top - strip)
  local ix = (draw.width - dw) // 2
  if theme.s == "relief" then draw.rect(ix + 5, top + 5, dw, dh, color.BLACK, true) end
  blit(ix, top, dw, dh)
  if theme.s ~= "klar" then draw.rect(ix, top, dw, dh, color.BLACK, false) end
  draw.text(draw.width // 2, bottom - 8, fit(dget(ctx, "title") or "", draw.width - 48, "medium"), "medium", color.BLACK, "center")
end

function on_widget(ctx, box)
  setStyle(ctx.cfg.style)
  box = widgetFrame(box)
  local en = (ctx.lang == "en")
  local title = ctx.data.get("title")
  if ctx.sample or ctx.data.get("demo") == "1" then title = en and "Sunrise over the lake" or "Sonnenaufgang am See" end
  if title == nil then
    draw.text(box.x + 12, box.y + 22, en and "No data yet" or "Noch keine Daten", "small", color.BLACK, "left")
    return
  end
  local hasImg = ctx.data.get("img") == "1" and draw.image_size(PIC) ~= nil and not ctx.sample and ctx.data.get("demo") ~= "1"
  if hasImg and box.h >= 70 and box.w >= 120 then
    local iw, ih = draw.image_size(PIC)
    local maxW = box.w >= 220 and (box.w * 55 // 100) or (box.w - 12)
    local maxH = box.w >= 220 and (box.h - 8) or (box.h * 60 // 100)
    local s = math.min(maxW / iw, maxH / ih)
    local dw, dh = math.floor(iw * s), math.floor(ih * s)
    draw.image(PIC, box.x + 6, box.y + 4, dw, dh)
    if box.w >= 220 then
      draw.wrap(box.x + dw + 16, box.y + 22, box.w - dw - 22, title, "small", color.BLACK)
    else
      draw.text(box.x + 6, box.y + box.h - 6, fit(title, box.w - 12, "small"), "small", color.BLACK, "left")
    end
    return
  end
  draw.wrap(box.x + 12, box.y + 22, box.w - 20, title, box.h >= 60 and "normal" or "small", color.BLACK)
end
