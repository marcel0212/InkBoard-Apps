local theme={s="cards"}
local function setStyle(s)
theme.s=s or "cards"
if theme.s=="relief" or theme.s=="klar" then return "cards" end
return s
end
local function card(x,y,w,h,c,r,nobar)
if theme.s=="relief" then
r=r or 12
draw.rect(x+5,y+5,w,h,color.BLACK,true,r)
draw.rect(x,y,w,h,color.WHITE,true,r)
draw.rect(x,y,w,h,color.BLACK,false,r)
if not nobar then draw.rect(x+6,y+10,4,h - 20,c or color.ACCENT,true,2) end
return
elseif theme.s=="klar" then
r=r or 20
draw.rect(x,y,w,h,color.WHITE,true,r)
draw.rect(x,y,w,h,color.BLACK,false,r)
draw.rect(x+1,y+1,w - 2,h - 2,color.BLACK,false,r)
return
end
r=r or 10
draw.rect(x,y,w,h,color.WHITE,true,r)
draw.rect(x,y,w,h,color.BLACK,false,r)
draw.rect(x+6,y+6,5,h - 12,c or color.ACCENT,true,2)
end
local function panel(x,y,w,h,r,c)
c=c or color.BLACK
local big=w>=60 and h>=30
if theme.s=="relief" and big then
local s=5
draw.rect(x+w,y+s,s,h,color.BLACK,true)
draw.rect(x+s,y+h,w,s,color.BLACK,true)
end
draw.rect(x,y,w,h,c,false,r)
if theme.s=="klar" and big then draw.rect(x+1,y+1,w - 2,h - 2,c,false,r) end
end
local function widgetFrame(box)
if theme.s~="relief" and theme.s~="klar" then return box end
local x,y,w,h=box.x+4,box.y+2,box.w - 14,box.h - 12
card(x,y,w,h,color.ACCENT,theme.s=="relief" and 12 or 18)
local pad=theme.s=="relief" and 14 or 8
local inner={}
for k,v in pairs(box) do inner[k]=v end
inner.x,inner.y,inner.w,inner.h=box.x+pad,box.y+8,box.w - pad - 16,box.h - 20
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
