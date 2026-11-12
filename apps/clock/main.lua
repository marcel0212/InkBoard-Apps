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
local DAYS_DE={"Sonntag","Montag","Dienstag","Mittwoch","Donnerstag","Freitag","Samstag"}
local DAYS_EN={"Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"}
local MONTHS_DE={"Januar","Februar","März","April","Mai","Juni","Juli","August","September","Oktober","November","Dezember"}
local MONTHS_EN={"January","February","March","April","May","June","July","August","September","October","November","December"}
local MASK={0x3F,0x06,0x5B,0x4F,0x66,0x6D,0x7D,0x07,0x7F,0x6F}
local function digit(x,y,w,h,t,d,col)
local m=MASK[d+1]
if m==nil then return end
local half=(h - 3*t)//2
if m & 0x01~=0 then draw.rect(x+t,y,w - 2*t,t,col,true) end
if m & 0x02~=0 then draw.rect(x+w - t,y+t,t,half,col,true) end
if m & 0x04~=0 then draw.rect(x+w - t,y+2*t+half,t,half,col,true) end
if m & 0x08~=0 then draw.rect(x+t,y+h - t,w - 2*t,t,col,true) end
if m & 0x10~=0 then draw.rect(x,y+2*t+half,t,half,col,true) end
if m & 0x20~=0 then draw.rect(x,y+t,t,half,col,true) end
if m & 0x40~=0 then draw.rect(x+t,y+t+half,w - 2*t,t,col,true) end
end
local function timeWidth(w,t)
return 4*w+6*t
end
local function drawTime(str,cx,y,w,h,t,col,colonCol)
local gap=t
local colonSpace=3*t
local x=cx - timeWidth(w,t)//2
for i=1,5 do
local c=str:sub(i,i)
if i==3 then
local ccx=x+(colonSpace - t)//2
draw.rect(ccx,y+h//3 - t//2,t,t,colonCol,true)
draw.rect(ccx,y+(2*h)//3 - t//2,t,t,colonCol,true)
x=x+colonSpace
else
local d=tonumber(c)
if d then digit(x,y,w,h,t,d,col) end
x=x+w+gap
end
end
return y+h
end
local function drawPair(str2,cx,y,w,h,t,col)
local x=cx - (2*w+t)//2
for i=1,2 do
local d=tonumber(str2:sub(i,i))
if d then digit(x,y,w,h,t,d,col) end
x=x+w+t
end
return y+h
end
local function drawStacked(str,cx,y,h,col,colonCol)
local w=h*11//21
local t=h//8
if t<6 then t=6 end
local gap=t*2
drawPair(str:sub(1,2),cx,y,w,h,t,col)
local y2=y+h+gap
local cy=y+h+gap//2
draw.rect(cx - 2*t - t//2,cy - t//2,t,t,colonCol,true)
draw.rect(cx+2*t - t//2,cy - t//2,t,t,colonCol,true)
drawPair(str:sub(4,5),cx,y2,w,h,t,col)
return y2+h,(2*w+t)//2
end
local function clockStrings(ctx,lt)
local h=lt.hour
local ampm=""
if not ctx.clock24 then
ampm=h>=12 and "PM" or "AM"
h=h%12
if h==0 then h=12 end
end
return string.format("%02d:%02d",h,lt.min),ampm
end
local function names(ctx)
if ctx.lang=="en" then return DAYS_EN,MONTHS_EN end
return DAYS_DE,MONTHS_DE
end
function on_draw(ctx,page)
local en=(ctx.lang=="en")
draw.clear(color.WHITE)
local lt=time.localtime()
local cx=draw.width//2
local y=draw.top+14
if lt==nil then
draw.text(cx,260,en and "Time is still syncing ..." or "Zeit synchronisiert sich noch ...","medium",color.BLACK,"center")
return
end
local days,months=names(ctx)
local accent=color.ACCENT
local str,ampm=clockStrings(ctx,lt)
local dateLong=string.format("%s, %02d.%02d.%04d",days[lt.wday+1],lt.day,lt.month,lt.year)
local kw=(en and "Week " or "KW ")..lt.week
local style=setStyle(ctx.cfg.style)
local portrait=draw.height>draw.width
if portrait then
local avail=draw.height - draw.top
if style=="slate" then
local h=230
local top=draw.top+(avail - (2*h+2*(h//4)+120))//2
local bottom,halfW=drawStacked(str,cx,top,h,color.BLACK,accent)
if ampm~="" then draw.text(cx+halfW+8,bottom - 4,ampm,"normal",color.BLACK,"left") end
draw.line(24,bottom+30,draw.width - 24,bottom+30,color.BLACK)
draw.text(cx,bottom+74,dateLong,"large",color.BLACK,"center")
draw.text(cx,bottom+106,kw,"normal",color.BLACK,"center")
elseif style=="nano" then
local h=160
local top=draw.top+(avail - (2*h+h//4+140))//2
local bottom,halfW=drawStacked(str,cx,top,h,color.BLACK,accent)
if ampm~="" then draw.text(cx+halfW+8,bottom - 4,ampm,"normal",color.BLACK,"left") end
draw.text(cx,bottom+40,dateLong,"normal",color.BLACK,"center")
draw.text(cx,bottom+66,kw,"normal",color.BLACK,"center")
local barW,barH=draw.width - 80,14
local barX=cx - barW//2
local barY=bottom+90
local minutes=lt.hour*60+lt.min
local fillW=barW*minutes//1440
draw.rect(barX,barY,barW,barH,color.BLACK,false)
if fillW>2 then draw.rect(barX+1,barY+1,fillW - 2,barH - 2,accent,true) end
draw.text(barX,barY+barH+18,"0","small",color.BLACK,"left")
draw.text(barX+barW - 14,barY+barH+18,"24","small",color.BLACK,"left")
else
local cardX,cardW=20,draw.width - 40
local h=200
local cardH=2*h+h//4+60
local tileH,gap=130,16
local cardY=draw.top+(avail - (cardH+gap+tileH))//2
panel(cardX,cardY,cardW,cardH,16)
panel(cardX+1,cardY+1,cardW - 2,cardH - 2,15)
local bottom,halfW=drawStacked(str,cx,cardY+30,h,color.BLACK,accent)
if ampm~="" then draw.text(cx+halfW+8,bottom - 4,ampm,"normal",color.BLACK,"left") end
local tileY=cardY+cardH+gap
local tileW=(cardW - gap)//2
panel(cardX,tileY,tileW,tileH,16)
draw.rect(cardX+1,tileY+1,tileW - 2,8,accent,true)
draw.text(cardX+tileW//2,tileY+66,days[lt.wday+1],"large",color.BLACK,"center")
draw.text(cardX+tileW//2,tileY+102,string.format("%02d.%02d.%04d",lt.day,lt.month,lt.year),"normal",color.BLACK,"center")
local tile2X=cardX+tileW+gap
panel(tile2X,tileY,tileW,tileH,16)
draw.rect(tile2X+1,tileY+1,tileW - 2,8,accent,true)
draw.text(tile2X+tileW//2,tileY+66,months[lt.month],"large",color.BLACK,"center")
draw.text(tile2X+tileW//2,tileY+102,kw,"normal",color.BLACK,"center")
end
return
end
if style=="slate" then
local w,h,t=110,210,26
local bottom=drawTime(str,cx,y+40,w,h,t,color.BLACK,accent)
if ampm~="" then
draw.text(cx+timeWidth(w,t)//2+12,bottom - 4,ampm,"normal",color.BLACK,"left")
end
draw.line(cx - 240,bottom+34,cx+240,bottom+34,color.BLACK)
draw.text(cx,bottom+80,dateLong,"large",color.BLACK,"center")
draw.text(cx,bottom+112,kw,"normal",color.BLACK,"center")
elseif style=="nano" then
local w,h,t=72,132,16
local bottom=drawTime(str,cx,y+28,w,h,t,color.BLACK,accent)
if ampm~="" then
draw.text(cx+timeWidth(w,t)//2+10,bottom - 4,ampm,"normal",color.BLACK,"left")
end
draw.text(cx,bottom+40,dateLong.." · "..kw,"normal",color.BLACK,"center")
local barW,barH=520,14
local barX=cx - barW//2
local barY=bottom+70
local minutes=lt.hour*60+lt.min
local fillW=barW*minutes//1440
draw.rect(barX,barY,barW,barH,color.BLACK,false)
if fillW>2 then draw.rect(barX+1,barY+1,fillW - 2,barH - 2,accent,true) end
draw.text(barX,barY+barH+18,"0","small",color.BLACK,"left")
draw.text(barX+barW - 14,barY+barH+18,"24","small",color.BLACK,"left")
else
local cardX,cardW=70,draw.width - 140
local cardY,cardH=y+12,252
panel(cardX,cardY,cardW,cardH,16)
panel(cardX+1,cardY+1,cardW - 2,cardH - 2,15)
local w,h,t=96,180,22
local bottom=drawTime(str,cx,cardY+(cardH - h)//2,w,h,t,color.BLACK,accent)
if ampm~="" then
draw.text(cx+timeWidth(w,t)//2+12,bottom - 4,ampm,"normal",color.BLACK,"left")
end
local tileY,tileH,gap=cardY+cardH+18,118,18
local tileW=(cardW - gap)//2
panel(cardX,tileY,tileW,tileH,16)
draw.rect(cardX+1,tileY+1,tileW - 2,8,accent,true)
draw.text(cardX+tileW//2,tileY+58,days[lt.wday+1],"large",color.BLACK,"center")
draw.text(cardX+tileW//2,tileY+92,string.format("%02d.%02d.%04d",lt.day,lt.month,lt.year),"normal",color.BLACK,"center")
local tile2X=cardX+tileW+gap
panel(tile2X,tileY,tileW,tileH,16)
draw.rect(tile2X+1,tileY+1,tileW - 2,8,accent,true)
draw.text(tile2X+tileW//2,tileY+58,months[lt.month],"large",color.BLACK,"center")
draw.text(tile2X+tileW//2,tileY+92,kw,"normal",color.BLACK,"center")
end
end
local function fnt(b,base)
local t=b and b.font or 0
if t<0 and base=="normal" then return "small" end
if t>0 and base=="small" then return "normal" end
return base
end
function on_widget(ctx,box)
setStyle(ctx.cfg.style)
box=widgetFrame(box)
local lt=time.localtime()
if lt==nil then
draw.text(box.x+box.w//2,box.y+box.h//2,ctx.lang=="en" and "No data yet" or "Noch keine Daten","small",color.BLACK,"center")
return
end
local days=names(ctx)
local str,ampm=clockStrings(ctx,lt)
local showDate=ctx.cfg.showDate
local cx=box.x+box.w//2
local maxY=box.y+box.h - 6
local hAvail=(maxY - box.y) - (showDate and 26 or 0)
local h=hAvail - 6
if h>210 then h=210 end
local fs=box.fontStep or 0
if fs<0 then h=h*(fs==-1 and 85 or 70)//100 end
local dateLong=string.format("%s, %02d.%02d.%04d",days[lt.wday+1],lt.day,lt.month,lt.year)
if h>=44 then
local w=h*11//21
local t=h//8
if t<6 then t=6 end
local limit=box.w - 16 - (ampm~="" and 56 or 0)
while w>22 and timeWidth(w,t)>limit do
w=w - 4
h=w*21//11
t=h//8
if t<6 then t=6 end
end
local bottom=drawTime(str,cx,box.y+4,w,h,t,color.BLACK,color.ACCENT)
if ampm~="" then
draw.text(cx+timeWidth(w,t)//2+6,bottom - 2,ampm,fnt(box,"small"),color.BLACK,"left")
end
if showDate and bottom+20<=maxY then
draw.text(cx,bottom+18,dateLong,fnt(box,"small"),color.BLACK,"center")
end
else
local txt=ampm~="" and (str.." "..ampm) or str
local ty=box.y+(maxY - box.y)//2+12
draw.text(cx,showDate and ty - 8 or ty,txt,"large",color.BLACK,"center")
if showDate and ty+14<=maxY then
draw.text(cx,ty+14,dateLong,fnt(box,"small"),color.BLACK,"center")
end
end
end
