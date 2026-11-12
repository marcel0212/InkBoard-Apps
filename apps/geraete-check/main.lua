local theme={s="cards"}
local function light(c) return c==color.YELLOW or c==color.WHITE end
local function inkOf(c)
if c==color.ACCENT then return color.ACCENT_INK elseif c==color.ACCENT_INK then return color.ACCENT end
return light(c) and color.BLACK or color.WHITE
end
local tiles,raw,pts={},nil,{}
local function tileInk(x,y,c,fill)
if theme.s~="klar" then return c end
if (not fill or c~=color.WHITE) and #pts<400 then pts[#pts+1]=x; pts[#pts+1]=y end
for i=#tiles,1,-1 do
local t=tiles[i]
if x>=t[1] and x<t[3] and y>=t[2] and y<t[4] then
local f,i=t[5],t[6]
if c==f or (f==color.ACCENT and c==color.ACCENT_TEXT) then return i end
if c==color.BLACK and not fill and not light(f) and f~=color.ACCENT_INK then return i end
if c==color.ACCENT_INK and f~=color.ACCENT then return light(f) and color.BLACK or color.WHITE end
if not fill and not light(f) and not light(c) and c~=color.ACCENT_INK then return i end
return c
end
end
return c
end
local function klarHook()
if raw then return end
raw={text=draw.text,wrap=draw.wrap,line=draw.line,rect=draw.rect,circle=draw.circle,triangle=draw.triangle,icon=draw.icon}
draw.text=function(x,y,s,f,c,...) return raw.text(x,y,s,f,tileInk(x,y - 4,c),...) end
draw.wrap=function(x,y,w,s,f,c,...) return raw.wrap(x,y,w,s,f,tileInk(x,y,c),...) end
draw.line=function(a,b,c2,d,c) return raw.line(a,b,c2,d,tileInk((a+c2)//2,(b+d)//2,c)) end
draw.circle=function(x,y,r,c,f)
c=tileInk(x,y,c,f)
if f and theme.s=="klar" and r>=8 and #tiles<120 then tiles[#tiles+1]={x - r,y - r,x+r,y+r,c,inkOf(c)} end
return raw.circle(x,y,r,c,f)
end
draw.triangle=function(a,b,c2,d,e,f,c,fl) return raw.triangle(a,b,c2,d,e,f,tileInk((a+c2+e)//3,(b+d+f)//3,c),fl) end
draw.icon=function(n,x,y,z,c) return raw.icon(n,x,y,z,tileInk(x+z//2,y+z//2,c)) end
draw.rect=function(x,y,w,h,c,fill,r)
c=tileInk(x+w//2,y+h//2,c,fill)
if fill and theme.s=="klar" and w>=16 and h>=12 and #tiles<120 then tiles[#tiles+1]={x,y,x+w,y+h,c,inkOf(c)} end
return raw.rect(x,y,w,h,c,fill,r)
end
end
local function setStyle(s)
theme.s=({bento="cards",slate="flat",nano="compact"})[s] or s or "cards"
tiles,pts={},{}
if theme.s=="klar" then klarHook() end
if theme.s=="relief" or theme.s=="klar" then return "cards" end
return s
end
local function card(x,y,w,h,c,r,nobar)
if theme.s=="relief" then
r=r or 12
draw.rect(x+6,y+6,w,h,color.BLACK,true,r)
draw.rect(x,y,w,h,color.WHITE,true,r)
draw.rect(x,y,w,h,color.BLACK,false,r)
draw.rect(x+1,y+1,w - 2,h - 2,color.BLACK,false,r)
return
elseif theme.s=="klar" then
if not c or c==color.BLACK then c=color.ACCENT end
draw.rect(x,y,w,h,c,true,math.min((r or 18)+8,30))
return
end
r=r or 10
draw.rect(x,y,w,h,color.WHITE,true,r)
draw.rect(x,y,w,h,color.BLACK,false,r)
if not nobar then draw.rect(x+6,y+6,5,h - 12,c or color.ACCENT,true,2) end
end
local function panel(x,y,w,h,r,c)
c=c or color.BLACK
local big=w>=60 and h>=30
if theme.s=="relief" and big then
local s=5
local rr=math.max(2,math.min(r or 12,40,w//2,h//2))
local function sichel(cx,cy,a0,a1)
local n=5
for i=0,n - 1 do
local u,v=math.rad(a0+(a1 - a0)*i/n),math.rad(a0+(a1 - a0)*(i+1)/n)
local c1,s1,c2,s2=math.cos(u)*rr,math.sin(u)*rr,math.cos(v)*rr,math.sin(v)*rr
local function f(v) return math.floor(v+0.5) end
draw.polygon({f(cx+c1),f(cy+s1),f(cx+c1+s),f(cy+s1+s),f(cx+c2+s),f(cy+s2+s),f(cx+c2),f(cy+s2)},color.BLACK,true)
end
end
draw.rect(x+w,y+rr,s,h - 2*rr+s,color.BLACK,true)
draw.rect(x+rr,y+h,w - 2*rr+s,s,color.BLACK,true)
sichel(x+w - rr,y+h - rr,0,90)
sichel(x+w - rr,y+rr,-45,0)
sichel(x+rr,y+h - rr,90,135)
end
if theme.s=="klar" and big then
c=c==color.BLACK and color.ACCENT or c
for i=1,#pts,2 do
if pts[i]>x and pts[i]<x+w and pts[i+1]>y and pts[i+1]<y+h then
for k=0,2 do draw.rect(x+k,y+k,w - 2*k,h - 2*k,c,false,r) end
return
end
end
draw.rect(x,y,w,h,c,true,math.min((r or 12)+8,30))
return
end
draw.rect(x,y,w,h,c,false,r)
end
local function widgetFrame(box)
local st=theme.s
local inner={}
for k,v in pairs(box) do inner[k]=v end
if st=="flat" then
draw.line(box.x+6,box.y+1,box.x+box.w - 6,box.y+1,color.BLACK)
draw.line(box.x+6,box.y+box.h - 2,box.x+box.w - 6,box.y+box.h - 2,color.BLACK)
inner.y,inner.h=box.y+2,box.h - 4
return inner
elseif st=="compact" then
draw.rect(box.x+3,box.y+4,2,box.h - 8,color.ACCENT,true)
inner.font=math.max(-1,(box.font or 0) - 1)
return inner
elseif st~="relief" and st~="klar" and st~="cards" then
return box
end
if st=="cards" then
card(box.x+1,box.y,box.w - 2,box.h - 1,color.ACCENT,10)
inner.x,inner.y,inner.w,inner.h=box.x+10,box.y+2,box.w - 14,box.h - 4
return inner
end
local x,y,w,h=box.x+4,box.y+2,box.w - 14,box.h - 12
card(x,y,w,h,color.ACCENT,st=="relief" and 12 or 18)
local pad=st=="relief" and 14 or 8
if box.h<60 then
inner.x,inner.y,inner.w,inner.h=box.x+pad,box.y+3,box.w - pad - 16,box.h - 13
else
inner.x,inner.y,inner.w,inner.h=box.x+pad,box.y+8,box.w - pad - 16,box.h - 20
end
return inner
end
local function pillW(txt,font,h,minw)
return math.max(minw or 0,draw.measure(txt,font or "small")+h)
end
local function pill(x,y,w,h,c,txt,font,tc)
if txt then w=pillW(txt,font,h,w) end
local r=h//2
c=c or color.ACCENT
if theme.s=="relief" then
draw.rect(x+3,y+3,w,h,color.BLACK,true,r)
draw.rect(x,y,w,h,c,true,r)
draw.rect(x,y,w,h,color.BLACK,false,r)
elseif theme.s=="klar" then
draw.rect(x,y,w,h,c,true,r)
else
draw.rect(x,y,w,h,c,false,r)
tc=tc or (c==color.ACCENT and color.ACCENT_TEXT or c)
end
if txt then draw.text(x+w//2,y+h//2+8,txt,font or "small",tc or (c==color.ACCENT and color.ACCENT_INK or color.WHITE),"center") end
return w
end
local function pbar(x,y,w,h,frac,c)
frac=math.max(0,math.min(1,frac or 0))
c=c or color.ACCENT
local r=h//2
if theme.s=="relief" then draw.rect(x+3,y+3,w,h,color.BLACK,true,r) ; draw.rect(x,y,w,h,color.WHITE,true,r) end
draw.rect(x,y,w,h,color.BLACK,false,r)
local fw=math.floor((w - 4)*frac)
if fw>h - 4 then draw.rect(x+2,y+2,fw,h - 4,c,true,(h - 4)//2)
elseif fw>2 then draw.rect(x+2,y+2,fw,h - 4,c,true) end
end
local OK,WARN,BAD,NONE=0,1,2,3
local function ago(sec,en)
if sec<0 then sec=0 end
if sec<90 then return en and "just now" or "gerade eben" end
if sec<5400 then return string.format(en and "%d min ago" or "vor %d Min.",math.floor(sec/60+0.5)) end
if sec<172800 then return string.format(en and "%d h ago" or "vor %d Std.",math.floor(sec/3600+0.5)) end
return string.format(en and "%d d ago" or "vor %d Tg.",math.floor(sec/86400+0.5))
end
local function span(sec,en)
if sec<3600 then return string.format("%d min",math.floor(sec/60)) end
if sec<86400 then return string.format(en and "%d h %d min" or "%d Std. %d Min.",sec//3600,(sec%3600)//60) end
return string.format(en and "%d d %d h" or "%d Tg. %d Std.",sec//86400,(sec%86400)//3600)
end
local function cut(text,maxw,font)
while #text>1 and draw.measure(text,font)>maxw do
local i=#text
while i>1 and (text:byte(i) & 0xC0)==0x80 do i=i - 1 end
text=text:sub(1,i - 1)
end
return text
end
local function rows(s,en)
local r={}
if s.clock_ok then
local t=time.localtime()
local v=t and string.format("%02d:%02d  %02d.%02d.%04d",t.hour,t.min,t.day,t.month,t.year) or "ok"
r[#r+1]={en and "Clock" or "Uhr",v,OK}
else
r[#r+1]={en and "Clock" or "Uhr",en and "Not set" or "Nicht gestellt",BAD}
end
if s.wifi then
local q,st=en and "good" or "gut",OK
if s.rssi<=-80 then q,st=en and "weak" or "schwach",BAD
elseif s.rssi<=-70 then q,st=en and "fair" or "mittel",WARN end
r[#r+1]={"WLAN",q,st}
else
r[#r+1]={"WLAN",en and "Not connected" or "Nicht verbunden",BAD}
end
if s.battery~=nil then
local st=OK
if s.battery<=10 then st=BAD elseif s.battery<=25 then st=WARN end
r[#r+1]={en and "Battery" or "Akku",string.format("%d %%  (%s)",math.floor(s.battery+0.5),s.on_battery and (en and "battery mode" or "Akkubetrieb") or (en and "mains" or "Netzbetrieb")),st}
else
r[#r+1]={en and "Battery" or "Akku",s.on_battery and (en and "No reading" or "Kein Messwert") or (en and "Mains powered" or "Netzbetrieb"),NONE}
end
local nas=en and "Data storage" or "Speicher für Daten"
if not s.nas_ready then
r[#r+1]={nas,en and "Not set up" or "Nicht eingerichtet",NONE}
elseif s.nas_fail_since~=nil and s.clock_ok then
r[#r+1]={nas,(en and "Upload failing for " or "Upload scheitert seit ")..span(s.now - s.nas_fail_since,en),BAD}
elseif s.nas_error~=nil and s.nas_error~="" then
r[#r+1]={nas,(en and "Error: " or "Fehler: ")..s.nas_error,BAD}
elseif s.nas_ok~=nil and s.clock_ok then
local age=s.now - s.nas_ok
r[#r+1]={nas,(en and "Last upload " or "Letzter Upload ")..ago(age,en),age>3*3600 and WARN or OK}
else
r[#r+1]={nas,en and "No upload since start" or "Noch kein Upload seit dem Start",(s.uptime>3600) and WARN or NONE}
end
local st=OK
if s.free_kb<40 then st=BAD elseif s.free_kb<80 then st=WARN end
r[#r+1]={en and "Memory" or "Arbeitsspeicher",string.format(en and "%d KB free" or "%d KB frei",s.free_kb),st}
r[#r+1]={"Firmware",string.format("%s  -  %s",s.version,(en and "up " or "läuft ")..span(s.uptime,en)),OK}
return r
end
local function light(cx,cy,r,st)
if st==NONE then
draw.circle(cx,cy,r,color.BLACK,false)
draw.circle(cx,cy,r - 1,color.BLACK,false)
else
local c=st==OK and color.GREEN or (st==WARN and color.YELLOW or color.RED)
draw.circle(cx,cy,r,c,true)
draw.circle(cx,cy,r,color.BLACK,false)
end
end
local function summary(list,en)
local bad,warn=0,0
for i=1,#list do
if list[i][3]==BAD then bad=bad+1 elseif list[i][3]==WARN then warn=warn+1 end
end
local fill,ink,msg=color.GREEN,color.WHITE,en and "All good" or "Alles in Ordnung"
if bad>0 then
fill,ink=color.RED,color.WHITE
msg=bad==1 and (en and "1 problem" or "1 Problem") or string.format(en and "%d problems" or "%d Probleme",bad)
if warn>0 then msg=msg..(warn==1 and (en and ", 1 notice" or ", 1 Hinweis") or string.format(en and ", %d notices" or ", %d Hinweise",warn)) end
elseif warn>0 then
fill,ink=color.YELLOW,color.BLACK
msg=warn==1 and (en and "1 notice" or "1 Hinweis") or string.format(en and "%d notices" or "%d Hinweise",warn)
end
return fill,ink,msg,bad,warn
end
local ROOM_DE={wohnzimmer="Wohnzimmer",flur="Flur",kueche="Küche",bad="Bad",schlafzimmer="Schlafzimmer",
buero="Büro",gaestezimmer="Gästezimmer",waschkueche="Waschküche",kinderzimmer="Kinderzimmer",arbeitszimmer="Arbeitszimmer",
esszimmer="Esszimmer",keller="Keller",garage="Garage",dachboden="Dachboden",balkon="Balkon",terrasse="Terrasse",diele="Diele"}
local ROOM_EN={wohnzimmer="Living room",flur="Hallway",kueche="Kitchen",bad="Bathroom",schlafzimmer="Bedroom",
buero="Office",gaestezimmer="Guest room",waschkueche="Laundry room",kinderzimmer="Kids' room",arbeitszimmer="Study",
esszimmer="Dining room",keller="Basement",garage="Garage",dachboden="Attic",balkon="Balcony",terrasse="Terrace",diele="Hall"}
local function room_label(r,en)
r=tostring(r or "")
if r=="" then return r end
local m=(en and ROOM_EN or ROOM_DE)[r:lower()]
if m then return m end
return r:sub(1,1):upper()..r:sub(2)
end
local function who_of(s,en)
return (s.room~=nil and s.room~="") and room_label(s.room,en) or "InkBoard"
end
function on_draw(ctx,page)
local en=(ctx.lang=="en")
local style=setStyle(ctx.cfg.style) or "flat"
draw.clear(color.WHITE)
local s=system.get()
if s==nil then
draw.text(draw.width//2,draw.top+160,en and "Device state not available" or "Gerätezustand nicht verfügbar","large",color.BLACK,"center")
draw.text(draw.width//2,draw.top+196,en and "Firmware update needed" or "Firmware-Update nötig","normal",color.BLACK,"center")
return
end
local list=rows(s,en)
local fill,ink,msg=summary(list,en)
local top=draw.top+10
local tall=draw.height>draw.width
if tall then
local W=draw.width
local n=#list
local function titleBar(h)
draw.rect(20,top,W - 40,h,fill,true,14)
local mf=draw.measure(msg,"large")<=W - 80 and "large" or "normal"
draw.text(40,top+36,cut(msg,W - 80,mf),mf,ink,"left")
draw.text(40,top+62,cut(who_of(s,en),W - 80,"normal"),"normal",ink,"left")
end
if style=="compact" then
draw.rect(30,top+20,W - 60,150,fill,true,20)
local mf=draw.measure(msg,"large")<=W - 90 and "large" or "normal"
draw.text(W//2,top+108,cut(msg,W - 90,mf),mf,ink,"center")
local cols=3
local colw=(W - 60)//cols
for i=1,n do
local c,r=(i - 1)%cols,(i - 1)//cols
local cx=30+colw*c+colw//2
local cy=top+250+r*130
light(cx,cy,24,list[i][3])
local nf=(draw.measure(list[i][1],"normal")<=colw - 8) and "normal" or "small"
draw.text(cx,cy+52,cut(list[i][1],colw - 8,nf),nf,color.BLACK,"center")
end
draw.text(W//2,top+560,cut(who_of(s,en).."  -  "..s.version,W - 40,"normal"),"normal",color.BLACK,"center")
return
end
titleBar(78)
local y=top+94
if style=="cards" then
local th=96
for i=1,n do
panel(20,y,W - 40,th,14)
light(52,y+30,14,list[i][3])
draw.text(78,y+36,list[i][1],"normal",color.BLACK,"left")
local v=list[i][2]
local font=draw.measure(v,"large")<=W - 80 and "large" or "normal"
draw.text(40,y+80,cut(v,W - 80,font),font,color.BLACK,"left")
y=y+th+10
end
else
local rowH=88
for i=1,n do
light(48,y+30,14,list[i][3])
draw.text(76,y+36,list[i][1],"normal",color.BLACK,"left")
local v=list[i][2]
local font=draw.measure(v,"large")<=W - 100 and "large" or "normal"
draw.text(76,y+74,cut(v,W - 100,font),font,color.BLACK,"left")
if i<n then draw.line(40,y+rowH,W - 24,y+rowH,color.BLACK) end
y=y+rowH+6
end
end
return
end
if style=="compact" then
draw.rect(60,top+20,draw.width - 120,130,fill,true,20)
draw.text(draw.width//2,top+100,cut(msg,draw.width - 160,"large"),"large",ink,"center")
local n=#list
local colw=(draw.width - 80)//n
for i=1,n do
local cx=40+colw*(i - 1)+colw//2
light(cx,top+210,20,list[i][3])
draw.text(cx,top+270,cut(list[i][1],colw - 6,"small"),"small",color.BLACK,"center")
end
draw.text(draw.width//2,top+340,who_of(s,en).."  -  "..s.version,"normal",color.BLACK,"center")
return
end
draw.rect(24,top,draw.width - 48,50,fill,true,14)
draw.text(48,top+34,msg,"large",ink,"left")
draw.text(draw.width - 48,top+33,who_of(s,en),"normal",ink,"right")
if style=="cards" then
local tw=(draw.width - 48 - 12)//2
local th=104
for i=1,#list do
local col,row=(i - 1)%2,(i - 1)//2
local x=24+col*(tw+12)
local y=top+62+row*(th+10)
panel(x,y,tw,th,14)
light(x+28,y+30,13,list[i][3])
draw.text(x+52,y+36,list[i][1],"normal",color.BLACK,"left")
local v=list[i][2]
local font="normal"
if draw.measure(v,"large")<=tw - 24 then font="large" end
draw.text(x+16,y+84,cut(v,tw - 24,font),font,color.BLACK,"left")
end
return
end
local y=top+62
local rowH=54
for i=1,#list do
local label,value,st=list[i][1],list[i][2],list[i][3]
local cy=y+rowH//2
light(50,cy,13,st)
draw.text(84,cy+8,label,"normal",color.BLACK,"left")
local maxw=draw.width - 24 - 270
local font="large"
if draw.measure(value,font)>maxw then font="normal" end
draw.text(draw.width - 40,cy+9,cut(value,maxw,font),font,color.BLACK,"right")
if i<#list then draw.line(84,y+rowH,draw.width - 40,y+rowH,color.BLACK) end
y=y+rowH
end
end
function on_widget(ctx,box)
setStyle(ctx.cfg.style)
box=widgetFrame(box)
local en=(ctx.lang=="en")
local s=system.get()
local cx=box.x+box.w//2
if s==nil then
draw.text(cx,box.y+box.h//2,en and "No data yet" or "Noch keine Daten","small",color.BLACK,"center")
return
end
local list=rows(s,en)
local fill,ink,msg=summary(list,en)
local bh=math.min(box.h,52)
if box.h<70 then bh=box.h end
draw.rect(box.x+4,box.y+2,box.w - 8,bh - 4,fill,true,10)
local mf=draw.measure(msg,"large")<=box.w - 24 and "large" or "normal"
draw.text(cx,box.y+bh//2+8,cut(msg,box.w - 24,mf),mf,ink,"center")
if box.h>=70 then
local n=#list
local colw=(box.w - 8)//n
local r=math.max(5,math.min(11,colw//2 - 3))
for i=1,n do
local x=box.x+4+colw*(i - 1)+colw//2
light(x,box.y+bh+r+8,r,list[i][3])
if box.h>=110 and colw>=56 and ctx.cfg.style~="compact" then
draw.text(x,box.y+bh+2*r+30,cut(list[i][1],colw - 2,"small"),"small",color.BLACK,"center")
end
end
end
end
