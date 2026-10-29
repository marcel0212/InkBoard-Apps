local EN=false
local function T(de,en) if EN then return en end return de end
local PIC="pic"
local BROWSE_S=45
local TRIES=8
local MAX_BYTES=16777216
local function indexOf(names,name)
if name==nil then return nil end
for i=1,#names do
if names[i]==name then return i end
end
return nil
end
local function sign(x)
if x>0 then return 1 end
if x<0 then return -1 end
return 0
end
local function pickRandom(count,avoid)
if count<=1 then return 1 end
local seed=(time.now() or 0)%1000003
local i=(seed*7919+count*104729)%count+1
if i==avoid then i=i%count+1 end
return i
end
local function imageRot()
local s=system.settings()
local r=s and tonumber(s.images_rot) or 0
if r~=90 and r~=270 then r=0 end
return r
end
local function rotKey(rot)
return rot+draw.width
end
local function loadPicture(name,rot)
local bw,bh=draw.width,draw.height
if rot~=0 then bw,bh=480,800 end
local w,h=storage.image("dir",name,PIC,{w=bw,h=bh,style="photo",maxBytes=MAX_BYTES})
return w,h
end
local function browsing(d)
local bt=tonumber(d.get("bt"))
if bt==nil then return false end
local now=time.now()
if now==nil then return true end
return bt>0 and now - bt>=0 and now - bt<=BROWSE_S
end
function on_fetch(ctx)
local d=ctx.data
local cfg=ctx.cfg or {}
EN=(ctx.lang=="en")
local steps=tonumber(d.get("go"))
d.set("go",nil)
local want=d.get("to")
d.set("to",nil)
local opened=ctx.opened==true
local picLoaded=draw.image_size(PIC)~=nil
local rot=imageRot()
local sameRot=(tonumber(d.get("ro")) or 0)==rotKey(rot)
local showing=picLoaded and d.get("st")=="ok"
local names,count=storage.list("dir",{max=60})
if names==nil then
local msg=tostring(count)
if msg:find("kein externer Speicher",1,true) then
d.set("e",msg)
d.set("st","nonas")
return true
end
if showing then return true end
d.set("e",msg)
return false
end
d.set("c",#names)
if #names==0 then
d.set("st","empty")
d.set("n",nil)
d.set("i",nil)
d.set("e",nil)
return true
end
local cur=indexOf(names,d.get("n"))
local had=cur~=nil
if cur==nil then
cur=tonumber(d.get("i")) or 1
if cur<1 or cur>#names then cur=1 end
end
local target=cur
local dir=1
if want~=nil then
target=indexOf(names,want) or cur
elseif steps~=nil then
local sg=sign(steps)
if sg==0 then return true end
dir=sg
target=(cur - 1+sg)%#names+1
elseif had and not opened and #names>1 then
if cfg.order=="zufall" then target=pickRandom(#names,cur) else target=cur%#names+1 end
end
if target==cur and had and picLoaded and sameRot and d.get("st")=="ok" and (want==nil or want==d.get("n")) then
return true
end
local tried=0
local lastErr=nil
while tried<TRIES and tried<#names do
local w,h=loadPicture(names[target],rot)
if w~=nil then
d.set("ro",rotKey(rot))
if names[target]==d.get("n") then
d.set("rl",(tonumber(d.get("rl")) or 0)+1)
end
d.set("n",names[target])
d.set("i",target)
d.set("st","ok")
d.set("e",nil)
return true
end
lastErr=tostring(h)
tried=tried+1
target=(target - 1+dir)%#names+1
end
if showing then return true end
d.set("st","err")
d.set("e",lastErr or "")
d.set("i",target)
d.set("n",nil)
return true
end
function on_input(ctx,kind,n)
local d=ctx.data
if kind=="turn" then
if (tonumber(d.get("c")) or 0)<2 then return "blip" end
d.set("go",(tonumber(d.get("go")) or 0)+n)
d.set("bt",time.now() or 0)
return "fetch"
end
if browsing(d) then
d.set("bt",nil)
return "redraw"
end
return false
end
local function pill(text,cx)
local bw,bh=200,28
local bx=cx - bw//2
local by=draw.height - bh - 10
draw.rect(bx,by,bw,bh,color.WHITE,true,9)
draw.rect(bx,by,bw,bh,color.BLACK,false,9)
draw.text(cx,by+19,text,"small",color.BLACK,"center")
end
local function notice(cx,lines)
draw.rect(cx - 22,124,44,44,color.BLUE,true,22)
draw.text(cx,153,"?","large",color.WHITE,"center")
draw.text(cx,200,T("Noch keine Bilder","No pictures yet"),"large",color.BLACK,"center")
for i=1,#lines do
draw.text(cx,lines[i][1],lines[i][2],"normal",color.BLACK,"center")
end
end
local function drawQrPage(cx)
if device.qrscreen and device.qrscreen(T("Noch keine Bilder","No pictures yet"),T("QR-Code scannen, um ein Bild aufs Display zu schicken:","Scan the QR code to send a picture to the display:")) then
return
end
draw.text(cx,52,T("Noch keine Bilder","No pictures yet"),"large",color.BLACK,"center")
local msg=T("Das Gerät braucht eine WLAN-Verbindung, dann erscheint hier ein QR-Code.","The device needs a Wi-Fi connection; a QR code will appear here.")
local line,y="",100
for word in msg:gmatch("%S+") do
local try=(line=="") and word or (line.." "..word)
if line~="" and draw.measure(try,"normal")>draw.width - 40 then
draw.text(cx,y,line,"normal",color.BLACK,"center")
y,line=y+30,word
else
line=try
end
end
if line~="" then draw.text(cx,y,line,"normal",color.BLACK,"center") end
end
function on_http(ctx,req)
return {status=404,body="{}"}
end
function on_draw(ctx,page)
EN=(ctx.lang=="en")
local d=ctx.data
local cfg=ctx.cfg or {}
local cx=draw.width//2
draw.clear(color.WHITE)
local st=d.get("st")
local w,h=draw.image_size(PIC)
if st=="ok" and w~=nil then
local rot=imageRot()
local rw,rh=w,h
if rot~=0 then rw,rh=h,w end
local dw,dh=0,0
if rot==0 and (rw>draw.width or rh>draw.height) then
local sc=math.min(draw.width/rw,draw.height/rh)
rw,rh=math.floor(rw*sc),math.floor(rh*sc)
dw,dh=rw,rh
end
local x=(draw.width - rw)//2
local y=(draw.height - rh)//2
draw.image(PIC,x,y,dw,dh,rot)
if cfg.frame~=false then draw.rect(x - 1,y - 1,rw+2,rh+2,color.BLACK) end
if browsing(d) then
pill(string.format("%s %d %s %d",T("Bild","Picture"),tonumber(d.get("i")) or 1,T("von","of"),tonumber(d.get("c")) or 1),cx)
end
return
end
if st=="nonas" or st=="empty" then
drawQrPage(cx)
return
end
notice(cx,{
{244,T("Bilder in Studio unter Store -> Bilder hochladen -","Upload pictures in Studio under Store -> Pictures -")},
{268,T("gespeicherte Bilder laufen hier als Diashow.","saved pictures play here as a slideshow.")},
})
end
