-- Uebersetzer-Baustein (store/lib/translate.lua): Google Translate zuerst, MyMemory als Ersatz.
-- Im Manifest unter permissions.net eintragen: "translate.googleapis.com" und "api.mymemory.translated.net".
-- Je on_fetch gelten hoechstens 6 Abrufe: translateUse(n) meldet schon verbrauchte Abrufe (z. B. den Datenabruf).
-- Benutzung: local de = translateText("Hello", "en", "de")  -- Text oder nil, "quota" | "budget" | "fail"

local TL = { used = 0, max = 6, mm = false, err = "" }

-- Letzter Fehlertext (fuer Protokoll/Anzeige): translateLastError()
local function translateLastError()
  return TL.err
end

local function translateUse(n)
  TL.used = TL.used + n
end

local function tlClean(t)
  t = t:gsub("&#(%d+);", function(d)
    local n = tonumber(d)
    if n < 128 then return string.char(n) end
    if n < 2048 then return string.char(192 + n // 64, 128 + n % 64) end
    return string.char(224 + n // 4096, 128 + (n // 64) % 64, 128 + n % 64)
  end)
  t = t:gsub("&quot;", '"'):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")
  return (t:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Google: Antwort ist [[["Hallo","hello",...],...],...]; die Teilstuecke werden aneinandergehaengt.
local function tlGoogle(s, from, to)
  local body, herr = http.get("https://translate.googleapis.com/translate_a/single?client=gtx&sl=" .. from .. "&tl=" .. to .. "&dt=t&q=" .. text.url_encode(s))
  if body == nil then TL.err = "Google: " .. tostring(herr); return nil, "fail" end
  local doc = json.decode(body)
  if type(doc) ~= "table" or type(doc[1]) ~= "table" then TL.err = "Google: Antwort unlesbar (" .. body:sub(1, 40) .. ")"; return nil, "fail" end
  local parts = {}
  for _, seg in ipairs(doc[1]) do
    if type(seg) == "table" and type(seg[1]) == "string" then parts[#parts + 1] = seg[1] end
  end
  local t = tlClean(table.concat(parts))
  if t == "" then TL.err = "Google: leere Antwort"; return nil, "fail" end
  if #s > 12 and t:lower() == s:lower() then TL.err = "Google: Text unveraendert"; return nil, "fail" end
  return t
end

local function tlMyMemory(s, from, to)
  local body, herr = http.get("https://api.mymemory.translated.net/get?langpair=" .. from .. "%7C" .. to .. "&q=" .. text.url_encode(s))
  if body == nil then TL.err = "MyMemory: " .. tostring(herr); return nil, "fail" end
  local doc = json.decode(body)
  if type(doc) ~= "table" or type(doc.responseData) ~= "table" then TL.err = "MyMemory: Antwort unlesbar"; return nil, "fail" end
  local t = doc.responseData.translatedText
  if type(t) ~= "string" then TL.err = "MyMemory: Antwort unlesbar"; return nil, "fail" end
  if t:find("MYMEMORY WARNING", 1, true) == 1 then TL.err = "MyMemory: Tageslimit erreicht"; return nil, "quota" end
  t = tlClean(t)
  if t == "" then TL.err = "MyMemory: leere Antwort"; return nil, "fail" end
  return t
end

local function translateText(s, from, to)
  from = from or "en"
  to = to or "de"
  if s == nil or s == "" then return "" end
  for _ = 1, 2 do
    if TL.used >= TL.max then TL.err = "keine Abrufe mehr uebrig"; return nil, "budget" end
    TL.used = TL.used + 1
    local t, kind
    if TL.mm then t, kind = tlMyMemory(s, from, to) else t, kind = tlGoogle(s, from, to) end
    if t ~= nil then
      TL.err = ""
      log("Uebersetzer " .. (TL.mm and "MyMemory" or "Google") .. ": ok (" .. s:sub(1, 24) .. " -> " .. t:sub(1, 24) .. ")")
      return t
    end
    log("Uebersetzer: " .. TL.err)
    if TL.mm then return nil, kind end
    TL.mm = true -- Google fehlgeschlagen: ab jetzt MyMemory als Ersatz
  end
  return nil, "fail"
end
