-- Textbausteine fuer Pakete (store/lib/text.lua)

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Auf n Zeichen (UTF-8) kuerzen.
local function cut(s, n)
  if #s <= n then return s end
  local count, i = 0, 1
  while i <= #s do
    local b = s:byte(i)
    if b < 0x80 then i = i + 1 elseif b >= 0xF0 then i = i + 4 elseif b >= 0xE0 then i = i + 3 else i = i + 2 end
    count = count + 1
    if count >= n then break end
  end
  return s:sub(1, i - 1)
end

-- Steuerzeichen (Tab/Zeilenumbruch trennen oft die Felder) raus, auf n Zeichen kuerzen.
local function clean(s, n)
  s = tostring(s or ""):gsub("%c", " ")
  return cut(trim(s), n)
end

-- Auf Pixelbreite w kuerzen (kein Auslassungszeichen: das Display kennt es nicht).
local function fit(s, w, font)
  while #s > 1 and draw.measure(s, font) > w do
    s = s:sub(1, #s - 1)
    while #s > 1 and (s:byte(#s) & 0xC0) == 0x80 do s = s:sub(1, #s - 1) end
  end
  return s
end

-- Zahl mit Komma statt Punkt (deutsche Schreibweise), digits Nachkommastellen.
local function num(x, digits, en)
  local s = string.format("%." .. digits .. "f", x)
  if not en then s = s:gsub("%.", ",") end
  return s
end

-- Antwort-JSON, das beim 24-KB-Limit abgeschnitten wurde: behaelt alle vollstaendigen Listenelemente und
-- schliesst die offenen Klammern. level = Verschachtelungstiefe der Liste, in der abgeschnitten sein darf
-- (Standard 1: ein Element der obersten Liste/des obersten Objekts, z. B. {"stations":[{..},{..}] hat Tiefe 2).
local function decodeCut(body, level)
  local doc = json.decode(body)
  if type(doc) == "table" then return doc end
  level = level or 2
  local open, inStr, esc, safe, safeOpen = {}, false, false, nil, nil
  for i = 1, #body do
    local c = body:byte(i)
    if inStr then
      if esc then esc = false elseif c == 92 then esc = true elseif c == 34 then inStr = false end
    elseif c == 34 then inStr = true
    elseif c == 123 or c == 91 then open[#open + 1] = c
    elseif c == 125 or c == 93 then
      open[#open] = nil
      if #open == level then
        safe = i
        safeOpen = { table.unpack(open) }
      end
    end
  end
  if safe == nil then return nil end
  local head = body:sub(1, safe)
  for i = #safeOpen, 1, -1 do head = head .. (safeOpen[i] == 123 and "}" or "]") end
  doc = json.decode(head)
  if type(doc) == "table" then return doc end
  return nil
end
