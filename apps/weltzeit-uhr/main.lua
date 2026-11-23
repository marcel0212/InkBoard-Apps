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
local FOFF={small=5,s8=6,normal=6,n10=7,medium=9,large=13}
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
if txt then draw.text(x+w//2,y+h//2+(FOFF[font or "small"] or 6),txt,font or "small",tc or (c==color.ACCENT and color.ACCENT_INK or color.WHITE),"center") end
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
local function mark(x,y,w,h,r)
if theme.s=="relief" then
draw.rect(x+3,y+3,w,h,color.BLACK,true,r)
draw.rect(x,y,w,h,color.WHITE,true,r)
draw.rect(x,y,w,h,color.BLACK,false,r)
draw.rect(x+1,y+1,w - 2,h - 2,color.BLACK,false,r)
elseif theme.s=="klar" then
for k=0,2 do draw.rect(x+k,y+k,w - 2*k,h - 2*k,color.ACCENT,false,r) end
else
draw.rect(x,y,w,h,color.BLACK,false,r)
end
end
local function trim(s)
return (s:gsub("^%s+",""):gsub("%s+$",""))
end
local function cut(s,n)
if #s<=n then return s end
local count,i=0,1
while i<=#s do
local b=s:byte(i)
if b<0x80 then i=i+1 elseif b>=0xF0 then i=i+4 elseif b>=0xE0 then i=i+3 else i=i+2 end
count=count+1
if count>=n then break end
end
return s:sub(1,i - 1)
end
local function clean(s,n)
s=tostring(s or ""):gsub("%c"," ")
return cut(trim(s),n)
end
local function fit(s,w,font)
while #s>1 and draw.measure(s,font)>w do
s=s:sub(1,#s - 1)
while #s>1 and (s:byte(#s) & 0xC0)==0x80 do s=s:sub(1,#s - 1) end
if #s>1 and s:byte(#s)>=0xC0 then s=s:sub(1,#s - 1) end
end
return s
end
local function num(x,digits,en)
local s=string.format("%."..digits.."f",x)
if not en then s=s:gsub("%.",",") end
return s
end
local function decodeCut(body,level)
local doc=json.decode(body)
if type(doc)=="table" then return doc end
level=level or 2
local open,inStr,esc,safe,safeOpen={},false,false,nil,nil
for i=1,#body do
local c=body:byte(i)
if inStr then
if esc then esc=false elseif c==92 then esc=true elseif c==34 then inStr=false end
elseif c==34 then inStr=true
elseif c==123 or c==91 then open[#open+1]=c
elseif c==125 or c==93 then
open[#open]=nil
if #open==level then
safe=i
safeOpen={table.unpack(open)}
end
end
end
if safe==nil then return nil end
local head=body:sub(1,safe)
for i=#safeOpen,1,-1 do head=head..(safeOpen[i]==123 and "}" or "]") end
doc=json.decode(head)
if type(doc)=="table" then return doc end
return nil
end
local function notice(icon,line1,line2)
local cx=draw.width//2
draw.icon(icon,cx - 24,170,48,color.ACCENT)
draw.text(cx,260,line1,"normal",color.BLACK,"center")
if line2~=nil then draw.text(cx,290,line2,"small",color.BLACK,"center") end
end
local function rowLayout(n,top,bottom,minH,maxH,hint)
local avail=bottom - top
local fit=math.max(1,avail//minH)
local shown=math.min(n,fit)
local truncated=shown<n
if truncated and hint then avail=avail - hint end
local rowH=avail//math.max(shown,1)
if rowH>maxH then rowH=maxH end
return shown,rowH,truncated
end
local function gridLayout(n,cols,top,bottom,margin,gap,maxTileH)
local rows=(n+cols - 1)//cols
local tileW=(draw.width - 2*margin - (cols - 1)*gap)//cols
local tileH=((bottom - top) - (rows - 1)*gap)//math.max(rows,1)
if maxTileH and tileH>maxTileH then tileH=maxTileH end
return function(i)
local col,row=(i - 1)%cols,(i - 1)//cols
return margin+col*(tileW+gap),top+row*(tileH+gap),tileW,tileH
end,tileW,tileH
end
local function columns(widths,rightEdge)
local total=0
for _,w in ipairs(widths) do total=total+w end
local xs,x={},rightEdge - total
for i,w in ipairs(widths) do xs[i]=x; x=x+w end
return xs
end
local function wrapLines(s,width,font,maxLines)
local lines,line={},""
for word in s:gmatch("%S+") do
local try=line=="" and word or (line.." "..word)
if draw.measure(try,font)<=width or line=="" then
line=try
else
lines[#lines+1]=line
line=word
if #lines==maxLines then break end
end
end
if #lines<maxLines and line~="" then lines[#lines+1]=line end
for i=1,#lines do
if draw.measure(lines[i],font)>width then
local l=lines[i]
while #l>1 and draw.measure(l,font)>width do
l=l:sub(1,#l - 1)
while #l>1 and (l:byte(#l) & 0xC0)==0x80 do l=l:sub(1,#l - 1) end
if #l>1 and l:byte(#l)>=0xC0 then l=l:sub(1,#l - 1) end
end
lines[i]=l
end
end
return lines
end
local CITIES={
{"local","Lokalzeit","Local time",0,"local"},
{"honolulu","Honolulu","Honolulu",-600,"none"},
{"anchorage","Anchorage","Anchorage",-540,"us"},
{"losangeles","Los Angeles","Los Angeles",-480,"us"},
{"vancouver","Vancouver","Vancouver",-480,"us"},
{"phoenix","Phoenix","Phoenix",-420,"none"},
{"denver","Denver","Denver",-420,"us"},
{"mexiko","Mexiko-Stadt","Mexico City",-360,"none"},
{"chicago","Chicago","Chicago",-360,"us"},
{"houston","Houston","Houston",-360,"us"},
{"newyork","New York","New York",-300,"us"},
{"toronto","Toronto","Toronto",-300,"us"},
{"miami","Miami","Miami",-300,"us"},
{"bogota","Bogotá","Bogotá",-300,"none"},
{"lima","Lima","Lima",-300,"none"},
{"caracas","Caracas","Caracas",-240,"none"},
{"santiago","Santiago de Chile","Santiago",-240,"cl"},
{"saopaulo","São Paulo","São Paulo",-180,"none"},
{"buenosaires","Buenos Aires","Buenos Aires",-180,"none"},
{"reykjavik","Reykjavik","Reykjavik",0,"none"},
{"accra","Accra","Accra",0,"none"},
{"lissabon","Lissabon","Lisbon",0,"eu"},
{"london","London","London",0,"eu"},
{"dublin","Dublin","Dublin",0,"eu"},
{"madrid","Madrid","Madrid",60,"eu"},
{"paris","Paris","Paris",60,"eu"},
{"brussel","Brüssel","Brussels",60,"eu"},
{"amsterdam","Amsterdam","Amsterdam",60,"eu"},
{"berlin","Berlin","Berlin",60,"eu"},
{"zuerich","Zürich","Zurich",60,"eu"},
{"wien","Wien","Vienna",60,"eu"},
{"rom","Rom","Rome",60,"eu"},
{"kopenhagen","Kopenhagen","Copenhagen",60,"eu"},
{"oslo","Oslo","Oslo",60,"eu"},
{"stockholm","Stockholm","Stockholm",60,"eu"},
{"prag","Prag","Prague",60,"eu"},
{"warschau","Warschau","Warsaw",60,"eu"},
{"budapest","Budapest","Budapest",60,"eu"},
{"lagos","Lagos","Lagos",60,"none"},
{"algier","Algier","Algiers",60,"none"},
{"athen","Athen","Athens",120,"eu"},
{"helsinki","Helsinki","Helsinki",120,"eu"},
{"bukarest","Bukarest","Bucharest",120,"eu"},
{"kiew","Kiew","Kyiv",120,"eu"},
{"kairo","Kairo","Cairo",120,"eg"},
{"telaviv","Tel Aviv","Tel Aviv",120,"il"},
{"johannesburg","Johannesburg","Johannesburg",120,"none"},
{"istanbul","Istanbul","Istanbul",180,"none"},
{"moskau","Moskau","Moscow",180,"none"},
{"riad","Riad","Riyadh",180,"none"},
{"doha","Doha","Doha",180,"none"},
{"nairobi","Nairobi","Nairobi",180,"none"},
{"addis","Addis Abeba","Addis Ababa",180,"none"},
{"teheran","Teheran","Tehran",210,"none"},
{"dubai","Dubai","Dubai",240,"none"},
{"karatschi","Karatschi","Karachi",300,"none"},
{"delhi","Neu-Delhi","New Delhi",330,"none"},
{"mumbai","Mumbai","Mumbai",330,"none"},
{"colombo","Colombo","Colombo",330,"none"},
{"kathmandu","Kathmandu","Kathmandu",345,"none"},
{"dhaka","Dhaka","Dhaka",360,"none"},
{"almaty","Almaty","Almaty",360,"none"},
{"bangkok","Bangkok","Bangkok",420,"none"},
{"jakarta","Jakarta","Jakarta",420,"none"},
{"hochiminh","Ho-Chi-Minh-Stadt","Ho Chi Minh City",420,"none"},
{"singapur","Singapur","Singapore",480,"none"},
{"kualalumpur","Kuala Lumpur","Kuala Lumpur",480,"none"},
{"hongkong","Hongkong","Hong Kong",480,"none"},
{"peking","Peking","Beijing",480,"none"},
{"shanghai","Shanghai","Shanghai",480,"none"},
{"taipeh","Taipeh","Taipei",480,"none"},
{"manila","Manila","Manila",480,"none"},
{"perth","Perth","Perth",480,"none"},
{"tokio","Tokio","Tokyo",540,"none"},
{"seoul","Seoul","Seoul",540,"none"},
{"adelaide","Adelaide","Adelaide",570,"au"},
{"brisbane","Brisbane","Brisbane",600,"none"},
{"sydney","Sydney","Sydney",600,"au"},
{"melbourne","Melbourne","Melbourne",600,"au"},
{"auckland","Auckland","Auckland",720,"nz"},
}
local BYID={}
for _,c in ipairs(CITIES) do BYID[c[1]]=c end
local WD_DE={"So","Mo","Di","Mi","Do","Fr","Sa"}
local WD_EN={"Sun","Mon","Tue","Wed","Thu","Fri","Sat"}
local function daysFromCivil(y,m,d)
if m<=2 then y=y - 1 end
local era=y//400
local yoe=y - era*400
local mp=(m+9)%12
local doy=(153*mp+2)//5+d - 1
local doe=yoe*365+yoe//4 - yoe//100+doy
return era*146097+doe - 719468
end
local function civilFromDays(z)
z=z+719468
local era=z//146097
local doe=z - era*146097
local yoe=(doe - doe//1460+doe//36524 - doe//146096)//365
local y=yoe+era*400
local doy=doe - (365*yoe+yoe//4 - yoe//100)
local mp=(5*doy+2)//153
local d=doy - (153*mp+2)//5+1
local m=mp<10 and mp+3 or mp - 9
if m<=2 then y=y+1 end
return y,m,d
end
local function weekday(days) return (days+4)%7 end
local function nthSunday(y,m,n)
local first=daysFromCivil(y,m,1)
local add=(7 - weekday(first))%7
return first+add+7*(n - 1)
end
local function lastSunday(y,m)
local ny,nm=y,m+1
if nm>12 then ny,nm=y+1,1 end
local last=daysFromCivil(ny,nm,1) - 1
return last - weekday(last)
end
local function sunOnOrAfter(y,m,d)
local z=daysFromCivil(y,m,d)
return z+(7 - weekday(z))%7
end
local function lastWeekday(y,m,wd)
local ny,nm=y,m+1
if nm>12 then ny,nm=y+1,1 end
local last=daysFromCivil(ny,nm,1) - 1
return last - (weekday(last) - wd)%7
end
local function isDst(rule,t,std)
if rule=="none" or rule=="local" then return false end
local y=civilFromDays((t+std*60)//86400)
if rule=="eu" then
return t>=lastSunday(y,3)*86400+3600 and t<lastSunday(y,10)*86400+3600
elseif rule=="us" then
local s=nthSunday(y,3,2)*86400+7200 - std*60
local e=nthSunday(y,11,1)*86400+7200 - (std+60)*60
return t>=s and t<e
elseif rule=="au" then
local s=nthSunday(y,10,1)*86400+7200 - std*60
local e=nthSunday(y,4,1)*86400+10800 - (std+60)*60
return t>=s or t<e
elseif rule=="nz" then
local s=lastSunday(y,9)*86400+7200 - std*60
local e=nthSunday(y,4,1)*86400+10800 - (std+60)*60
return t>=s or t<e
elseif rule=="cl" then
local st=sunOnOrAfter(y,9,2)*86400 - std*60
local e=sunOnOrAfter(y,4,2)*86400 - (std+60)*60
return t>=st or t<e
elseif rule=="eg" then
local st=lastWeekday(y,4,5)*86400 - std*60
local e=(lastWeekday(y,10,4)+1)*86400 - (std+60)*60
return t>=st and t<e
elseif rule=="il" then
local st=(lastSunday(y,3) - 2)*86400+7200 - std*60
local e=lastSunday(y,10)*86400+7200 - (std+60)*60
return t>=st and t<e
end
return false
end
local function nowUtc()
local n=time.now()
if n and n>1600000000 then return n end
return daysFromCivil(2026,11,22)*86400+11*3600+30*60
end
local function offsetOf(city,utc)
if city[5]=="extra" then
local r=city.rec
local off=r[1]
if r[3]==1 and not (r[5]>0 and utc>=r[5]) then off=r[1]+r[2] end
return off,off~=r[1]
end
if city[5]=="local" then
local lt=time.localtime()
if not lt then return 0,false end
local ls=daysFromCivil(lt.year,lt.month,lt.day)*86400+lt.hour*3600+lt.min*60+lt.sec
local off=ls - utc
off=((off+900)//1800)*1800
return off,false
end
local dst=isDst(city[5],utc,city[4])
return (city[4]+(dst and 60 or 0))*60,dst
end
local function fmtTime(h,m,clock24)
if clock24 then return string.format("%02d:%02d",h,m) end
local suf=h>=12 and " pm" or " am"
local hh=h%12
if hh==0 then hh=12 end
return string.format("%d:%02d",hh,m)..suf
end
local function fmtDiff(sec,en)
local mins=sec//60
local sign=mins<0 and "-" or "+"
mins=math.abs(mins)
local h,m=mins//60,mins%60
local u=en and " h" or " Std"
if mins==0 then return en and "same time" or "gleiche Zeit" end
if m==0 then return sign..h..u end
return string.format("%s%d:%02d%s",sign,h,m,u)
end
local function entry(city,utc,base,en,clock24)
local off,dst=offsetOf(city,utc)
local t=utc+off
local days,secs=t//86400,t%86400
local y,mo,d=civilFromDays(days)
local e={
name=en and city[3] or city[2],
id=city[1],
h=secs//3600,m=(secs%3600)//60,
days=days,off=off,dst=dst,
wd=(en and WD_EN or WD_DE)[weekday(days)+1],
}
e.time=fmtTime(e.h,e.m,clock24)
e.date=en and string.format("%02d/%02d",mo,d) or string.format("%02d.%02d.",d,mo)
if base then
e.dd=days - base.days
e.diff=fmtDiff(off - base.off,en)
else
e.dd=0
end
return e
end
local function dayWord(dd,en)
if dd==0 then return en and "today" or "heute" end
if dd>0 then return en and "tomorrow" or "morgen" end
return en and "yesterday" or "gestern"
end
local DEMO_CITIES={"Lokalzeit","New York","Tokio","Sydney"}
local function parseIso(str)
local y,mo,d,h,mi,se=tostring(str or ""):match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
if not y then return 0 end
return daysFromCivil(tonumber(y),tonumber(mo),tonumber(d))*86400+tonumber(h)*3600+tonumber(mi)*60+tonumber(se)
end
local FOLD={["ä"]="a",["ö"]="o",["ü"]="u",["ß"]="ss",["é"]="e",["á"]="a",["ã"]="a",["í"]="i",["ó"]="o",["ç"]="c"}
local function norm(str)
str=tostring(str or ""):lower()
str=str:gsub("[\195][\128-\191]",function(ch) return FOLD[ch] or ch end)
return (str:gsub("[%s%-%.]",""))
end
local BYNAME={}
for _,c in ipairs(CITIES) do
BYNAME[norm(c[1])]=c
BYNAME[norm(c[2])]=c
BYNAME[norm(c[3])]=c
end
BYNAME[norm("Local")]=BYID["local"]
BYNAME[norm("Lokal")]=BYID["local"]
local function entries(cfg)
local out={}
local raw=type(cfg.cities)=="table" and cfg.cities or nil
if raw==nil then
raw={}
for i,n in ipairs(DEMO_CITIES) do raw[i]=n end
end
local nExtra=0
for _,ln in ipairs(raw) do
if #out>=6 then break end
ln=tostring(ln)
local name,zone=ln:match("^%s*(.-)%s*=%s*([%w_%-]+/[%w_%-/]+)%s*$")
if not zone then zone=ln:match("^%s*([%w_%-]+/[%w_%-/]+)%s*$") end
if zone then
if nExtra<3 then
nExtra=nExtra+1
if not name or name=="" then name=(zone:match("([^/]+)$") or zone):gsub("_"," ") end
out[#out+1]={zone=zone,name=clean(name,24),idx=nExtra}
end
else
local c=BYNAME[norm(ln)]
if c then out[#out+1]={city=c} end
end
end
if #out==0 then out[1]={city=BYID["local"]} end
return out
end
local function cityList(ctx)
local list={}
for _,e in ipairs(entries(ctx.cfg)) do
if e.city then
list[#list+1]=e.city
else
local rec=ctx.data.get("z"..e.idx)
local zone,nums=tostring(rec or ""):match("^([^|]+)|(.+)$")
if zone==e.zone then
local r={}
for v in nums:gmatch("%-?%d+") do r[#r+1]=tonumber(v) end
if #r==5 then list[#list+1]={"x"..e.idx,e.name,e.name,0,"extra",rec=r} end
end
end
end
if #list==0 then list[1]=BYID["local"] end
return list
end
function on_fetch(ctx)
local ex={}
for _,e in ipairs(entries(ctx.cfg)) do if e.zone then ex[#ex+1]=e end end
if #ex==0 then return true end
local okAny=false
for i,e in ipairs(ex) do
if i>1 then time.sleep(300) end
local body,err=http.get("https://worldtimeapi.org/api/timezone/"..e.zone,4096)
local d=body and json.decode(body)
if type(d)=="table" and tonumber(d.raw_offset) then
local dst=d.dst==true
local rec=table.concat({math.floor(tonumber(d.raw_offset)),dst and math.floor(tonumber(d.dst_offset) or 3600) or 0,
dst and 1 or 0,parseIso(d.dst_from),parseIso(d.dst_until)},",")
ctx.data.set("z"..e.idx,e.zone.."|"..rec)
okAny=true
else
log("Weltzeit: "..e.zone..": "..tostring(err or "ungueltige Antwort"))
end
end
return okAny
end
local function build(ctx)
local en=(ctx.lang=="en")
local utc=nowUtc()
local list=cityList(ctx)
local out,base={},nil
for i,c in ipairs(list) do
local e=entry(c,utc,base,en,ctx.clock24~=false)
if i==1 then base=e end
out[i]=e
end
return out,en
end
local function pickFont(s,w,fonts)
for _,f in ipairs(fonts) do
if draw.measure(s,f)<=w then return f end
end
return fonts[#fonts]
end
local function drawTiles(list,en)
local n=#list
local cols=(n<=2) and n or ((n==4) and 2 or 3)
local at,tw,th=gridLayout(n,cols,draw.top+16,draw.height - 18,24,16,230)
for i,e in ipairs(list) do
local x,y,w,h=at(i)
card(x,y,w,h,color.ACCENT,theme.s=="relief" and 14 or 20)
local pad=24
local small=h<150
draw.text(x+pad,y+40,fit(e.name,w - pad*2 - (i>1 and 74 or 0),"normal"),"normal",color.BLACK,"left")
local tf=pickFont(e.time,w - pad*2,small and {"large","medium","normal"} or {"huge","large","medium"})
draw.text(x+w//2,y+h//2+(small and 24 or 34),e.time,tf,color.BLACK,"center")
local sub=e.wd.." "..e.date
if e.dd~=0 then sub=sub..", "..dayWord(e.dd,en) end
draw.text(x+pad,y+h - 26,fit(sub,w - pad*2,"small"),"small",color.BLACK,"left")
if i>1 then
local dw=pillW(e.diff,"small",26,0)
if dw<=w//2 then pill(x+w - dw - 16,y+14,dw,26,color.ACCENT,e.diff,"small") end
end
end
end
local function drawRows(list,en)
local n=#list
local compact=theme.s=="compact"
local top,bottom=draw.top+10,draw.height - 12
local shown,rowH=rowLayout(n,top,bottom,compact and 44 or 56,compact and 64 or 78)
local startY=top+((bottom - top) - rowH*shown)//2
for i=1,shown do
local e=list[i]
local y=startY+(i - 1)*rowH
if theme.s=="flat" then
draw.line(40,y+rowH - 1,draw.width - 40,y+rowH - 1,color.BLACK)
else
draw.rect(24,y+6,5,rowH - 12,color.ACCENT,true)
end
local nf=rowH>=64 and "medium" or "normal"
draw.text(48,y+rowH//2 - 2,e.name,nf,color.BLACK,"left")
local sub=e.wd.." "..e.date
if e.dd~=0 then sub=sub..", "..dayWord(e.dd,en) end
if i>1 then sub=sub.."  ("..e.diff..")" end
draw.text(48,y+rowH//2+22,fit(sub,430,"small"),"small",color.ACCENT_TEXT,"left")
draw.text(draw.width - 40,y+rowH//2+14,e.time,rowH>=64 and "large" or "medium",color.BLACK,"right")
end
end
local DESIGNS={"karten","heim","analog","tabelle","sonne","typo"}
local function designOf(cfg)
local d=cfg.design
if d==nil then d=DESIGNS[(tonumber(cfg.opt) or 0)+1] end
return d or "karten"
end
local function subLine(e,en)
local t=e.wd.." "..e.date
if e.dd~=0 then t=t..", "..dayWord(e.dd,en) end
return t
end
local function isNight(e) return e.h<6 or e.h>=20 end
local function bigScale(t,w)
for k=3,2,-1 do if draw.measure(t,"huge",k)<=w then return k end end
return 1
end
local function thick(x1,y1,x2,y2,col,t)
local dx,dy=x2 - x1,y2 - y1
local len=math.sqrt(dx*dx+dy*dy)
if len==0 then return end
local nx,ny=-dy/len,dx/len
for k=-(t//2),t//2 do
draw.line(math.floor(x1+nx*k+0.5),math.floor(y1+ny*k+0.5),math.floor(x2+nx*k+0.5),math.floor(y2+ny*k+0.5),col)
end
end
local function clockFace(cx,cy,r,e)
draw.rect(cx - r,cy - r,2*r,2*r,color.WHITE,true,r)
draw.rect(cx - r,cy - r,2*r,2*r,color.BLACK,false,r)
for i=0,11 do
local a=math.rad(i*30 - 90)
local r1=r - ((i%3==0) and 11 or 7)
draw.line(cx+math.floor(math.cos(a)*(r - 3)+0.5),cy+math.floor(math.sin(a)*(r - 3)+0.5),
cx+math.floor(math.cos(a)*r1+0.5),cy+math.floor(math.sin(a)*r1+0.5),color.BLACK)
end
local ha=math.rad((e.h%12+e.m/60)*30 - 90)
local ma=math.rad(e.m*6 - 90)
thick(cx,cy,cx+math.cos(ha)*r*0.5,cy+math.sin(ha)*r*0.5,color.BLACK,5)
thick(cx,cy,cx+math.cos(ma)*r*0.78,cy+math.sin(ma)*r*0.78,color.ACCENT,3)
draw.rect(cx - 4,cy - 4,8,8,color.BLACK,true,4)
end
local function sunMoon(cx,cy,r,night)
if night then
draw.rect(cx - r,cy - r,2*r,2*r,color.BLUE,true,r)
draw.rect(cx - r+r//2,cy - r - r//4,2*r - r//4,2*r - r//4,color.WHITE,true,r)
draw.rect(cx - r,cy - r,2*r,2*r,color.BLACK,false,r)
else
draw.rect(cx - r,cy - r,2*r,2*r,color.YELLOW,true,r)
draw.rect(cx - r,cy - r,2*r,2*r,color.BLACK,false,r)
for k=0,7 do
local a=math.rad(k*45)
draw.line(cx+math.floor(math.cos(a)*(r+4)+0.5),cy+math.floor(math.sin(a)*(r+4)+0.5),
cx+math.floor(math.cos(a)*(r+9)+0.5),cy+math.floor(math.sin(a)*(r+9)+0.5),color.BLACK)
end
end
end
local function isFancyStyle() return theme.s=="relief" or theme.s=="klar" or theme.s=="cards" end
local function gridFor(n)
local cols=(n<=2) and n or ((n==4) and 2 or 3)
return gridLayout(n,cols,draw.top+16,draw.height - 18,24,16,230)
end
local function frameBox(x,y,w,h)
if isFancyStyle() then card(x,y,w,h,color.ACCENT,theme.s=="relief" and 14 or 20)
else
draw.rect(x,y,w,h,color.WHITE,true,8)
draw.rect(x,y,w,h,color.BLACK,false,8)
end
end
local function drawHeim(list,en)
local top,bottom=draw.top+14,draw.height - 16
local n=#list
local e=list[1]
local mainH=n>1 and 220 or (bottom - top)
frameBox(24,top,752,mainH)
draw.text(54,top+46,e.name,"medium",color.BLACK,"left")
draw.text(400,top+mainH//2+40,e.time,"huge",color.BLACK,"center",bigScale(e.time,680))
draw.text(54,top+mainH - 22,subLine(e,en),"small",color.BLACK,"left")
local m=math.min(n - 1,5)
if m<1 then return end
local gap=14
local cw=(752 - (m - 1)*gap)//m
local y0=top+mainH+18
local h=bottom - y0
for i=1,m do
local c=list[i+1]
local x=24+(i - 1)*(cw+gap)
frameBox(x,y0,cw,h)
draw.text(x+cw//2,y0+30,fit(c.name,cw - 16,"small"),"small",color.BLACK,"center")
draw.text(x+cw//2,y0+h//2+14,c.time,pickFont(c.time,cw - 12,{"large","medium","normal"}),color.BLACK,"center")
draw.text(x+cw//2,y0+h - 14,fit(c.diff..(c.dd~=0 and (", "..dayWord(c.dd,en)) or ""),cw - 10,"small"),"small",color.ACCENT_TEXT,"center")
end
end
local function drawAnalog(list,en)
local n=#list
local at,tw,th=gridFor(n)
for i,e in ipairs(list) do
local x,y,w,h=at(i)
frameBox(x,y,w,h)
if w>=330 then
local r=math.min(h//2 - 18,74)
clockFace(x+r+24,y+h//2,r,e)
local tx=x+2*r+48
draw.text(tx,y+44,fit(e.name,w - (tx - x) - 14,"normal"),"normal",color.BLACK,"left")
draw.text(tx,y+h//2+22,e.time,pickFont(e.time,w - (tx - x) - 14,{"large","medium","normal"}),color.BLACK,"left")
draw.text(tx,y+h - 22,fit(subLine(e,en),w - (tx - x) - 14,"small"),"small",color.BLACK,"left")
else
local r=math.min(h//2 - 52,w//2 - 22,60)
if r<24 then r=24 end
clockFace(x+w//2,y+r+14,r,e)
draw.text(x+w//2,y+2*r+40,fit(e.name,w - 16,"small"),"small",color.BLACK,"center")
draw.text(x+w//2,y+h - 34,e.time,pickFont(e.time,w - 20,{"large","medium","normal"}),color.BLACK,"center")
end
end
end
local function drawTable(list,en)
local n=#list
local top,bottom=draw.top+10,draw.height - 12
local shown,rowH=rowLayout(n,top,bottom,52,74)
local startY=top+((bottom - top) - rowH*shown)//2
for i=1,shown do
local e=list[i]
local y=startY+(i - 1)*rowH
if i%2==1 and isFancyStyle() then draw.rect(24,y,draw.width - 48,rowH - 2,color.WHITE,true,8); draw.rect(24,y,draw.width - 48,rowH - 2,color.BLACK,false,8)
else draw.line(40,y+rowH - 1,draw.width - 40,y+rowH - 1,color.BLACK) end
local cy=y+rowH//2
draw.rect(44,cy - 10,20,20,isNight(e) and color.BLACK or color.YELLOW,true,10)
draw.rect(44,cy - 10,20,20,color.BLACK,false,10)
draw.text(84,cy+8,fit(e.name,250,"medium"),"medium",color.BLACK,"left")
draw.text(360,cy+6,fit(subLine(e,en),200,"small"),"small",color.BLACK,"left")
if i>1 then draw.text(590,cy+6,fit(e.diff,100,"small"),"small",color.ACCENT_TEXT,"left") end
draw.text(draw.width - 40,cy+14,e.time,"large",color.BLACK,"right")
end
end
local function drawSonne(list,en)
local n=#list
local at,tw,th=gridFor(n)
for i,e in ipairs(list) do
local x,y,w,h=at(i)
frameBox(x,y,w,h)
draw.text(x+22,y+40,fit(e.name,w - 90,"normal"),"normal",color.BLACK,"left")
sunMoon(x+w - 40,y+38,16,isNight(e))
draw.text(x+w//2,y+h//2+30,e.time,pickFont(e.time,w - 40,{"huge","large","medium"}),color.BLACK,"center")
local note=(i==1) and (en and "home" or "Heimat") or e.diff
draw.text(x+22,y+h - 20,fit(note..(e.dd~=0 and (", "..dayWord(e.dd,en)) or ""),w - 44,"small"),"small",color.ACCENT_TEXT,"left")
end
end
local function drawTypo(list,en)
local top,bottom=draw.top+10,draw.height - 12
local e=list[1]
local n=#list
local bigH=n>1 and 230 or (bottom - top)
draw.text(40,top+bigH//2+40,e.time,"huge",color.BLACK,"left",bigScale(e.time,700))
draw.text(44,top+40,e.name,"medium",color.ACCENT_TEXT,"left")
draw.text(draw.width - 40,top+40,subLine(e,en),"small",color.BLACK,"right")
if n<2 then return end
local m=math.min(n - 1,5)
local y0=top+bigH+6
local rh=math.min(46,(bottom - y0)//m)
for i=1,m do
local c=list[i+1]
local y=y0+(i - 1)*rh
draw.line(40,y,draw.width - 40,y,color.BLACK)
local cy=y+rh//2+8
draw.text(44,cy,fit(c.name,230,"normal"),"normal",color.BLACK,"left")
draw.text(300,cy,c.time,"medium",color.BLACK,"left")
draw.text(430,cy,fit(subLine(c,en),240,"small"),"small",color.BLACK,"left")
draw.text(draw.width - 40,cy,c.diff,"small",color.ACCENT_TEXT,"right")
end
end
function on_draw(ctx,page)
setStyle(ctx.cfg.style)
draw.clear(color.WHITE)
local list,en=build(ctx)
local design=designOf(ctx.cfg)
if design=="heim" then return drawHeim(list,en) end
if design=="analog" then return drawAnalog(list,en) end
if design=="tabelle" then return drawTable(list,en) end
if design=="sonne" then return drawSonne(list,en) end
if design=="typo" then return drawTypo(list,en) end
if theme.s=="relief" or theme.s=="klar" or theme.s=="cards" then
drawTiles(list,en)
else
drawRows(list,en)
end
end
function on_widget(ctx,box)
setStyle(ctx.cfg.style)
box=widgetFrame(box)
local list=build(ctx)
local n=math.min(#list,math.max(1,box.h//30))
if n==1 and box.h>=56 then
local e=list[1]
draw.text(box.x+12,box.y+20,fit(e.name,box.w - 20,"small"),"small",color.BLACK,"left")
draw.text(box.x+12,box.y+box.h//2+24,e.time,pickFont(e.time,box.w - 24,{"large","medium","normal"}),color.ACCENT_TEXT,"left")
return
end
local rh=box.h//n
for i=1,n do
local e=list[i]
local y=box.y+(i - 1)*rh+rh//2+6
local tw=draw.measure(e.time,"normal")
draw.text(box.x+box.w - 6,y,e.time,"normal",i==1 and color.ACCENT_TEXT or color.BLACK,"right")
draw.text(box.x+12,y,fit(e.name,box.w - tw - 30,"small"),"small",color.BLACK,"left")
end
end
