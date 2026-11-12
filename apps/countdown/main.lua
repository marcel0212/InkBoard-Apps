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
local function accentColor(name)
if name=="green" then return color.GREEN end
if name=="red" then return color.RED end
if name=="yellow" then return color.YELLOW end
if name=="black" then return color.BLACK end
return color.BLUE
end
local function drawCard(cfg,days,accent)
local x,y=40,draw.top+24
local w,h=draw.width - 86,draw.height - draw.top - 64
card(x,y,w,h,accent,theme.s=="relief" and 16 or 24)
local lx=x+(theme.s=="relief" and 34 or 30)
local label=cfg.label or ""
local lf=(draw.measure(label,"large")<=w - 70) and "large" or "medium"
draw.text(lx,y+64,label,lf,color.BLACK,"left")
if days==nil then
draw.text(lx,y+160,"Datum ungültig","medium",color.RED,"left")
return
end
local cx,cy=x+w//2,y+h//2+50
local function sc(t)
for k=3,2,-1 do if draw.measure(t,"huge",k)<=w - 80 then return k end end
return 1
end
if days==0 then
draw.text(cx,cy,"Heute!","large",accent,"center",3)
else
local t=tostring(days<0 and -days or days)
draw.text(cx,cy,t,"huge",days<0 and color.BLACK or accent,"center",sc(t))
local unit=days<0 and "Tage vorbei" or (days==1 and "Tag" or "Tage")
draw.text(cx,cy+56,unit,"medium",color.BLACK,"center")
end
if cfg.showDate and cfg.date then
local pw=draw.measure(cfg.date,"small")+36
pill(x+w - pw - 24,y+h - 58,pw,34,accent,cfg.date,"small",accent==color.YELLOW and color.BLACK or color.WHITE)
end
end
function on_draw(ctx,page)
local cfg=ctx.cfg
local days=time.days_until(cfg.date)
local accent=accentColor(cfg.accent)
draw.clear(color.WHITE)
setStyle(cfg.style)
if theme.s=="relief" or theme.s=="klar" then return drawCard(cfg,days,accent) end
draw.rect(0,draw.top,24,draw.height - draw.top,accent,true)
local tall=draw.height>draw.width
local lf=(draw.measure(cfg.label or "","large")<=draw.width - 100) and "large" or ((draw.measure(cfg.label or "","medium")<=draw.width - 100) and "medium" or "normal")
draw.text(80,90,cfg.label,lf,color.BLACK,"left")
if days==nil then
draw.text(80,240,"Datum ungültig",lf,color.RED,"left")
return
end
local cy=tall and (draw.height//2) or 300
local function sc(t)
for k=3,2,-1 do if draw.measure(t,"huge",k)<=draw.width - 100 then return k end end
return 1
end
if days<0 then
local t=tostring(-days)
draw.text(draw.width//2,cy,t,"huge",color.BLACK,"center",sc(t))
draw.text(draw.width//2,cy+70,"Tage vorbei","medium",color.BLACK,"center")
elseif days==0 then
draw.text(draw.width//2,cy - 10,"Heute!","large",accent,"center",3)
else
local t=tostring(days)
draw.text(draw.width//2,cy,t,"huge",accent,"center",sc(t))
draw.text(draw.width//2,cy+70,days==1 and "Tag" or "Tage","normal",color.BLACK,"center")
end
if cfg.showDate then
draw.text(draw.width - 40,draw.height - 30,cfg.date,"small",color.BLACK,"right")
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
local days=time.days_until(ctx.cfg.date)
draw.text(box.x+12,box.y+26,ctx.cfg.label,fnt(box,"small"),color.BLACK,"left")
if days~=nil then
draw.text(box.x+12,box.y+box.h//2+18,tostring(days),"large",accentColor(ctx.cfg.accent),"left")
end
end
