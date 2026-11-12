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
local SHOW=true
local MAX_AGE=3*3600
local DAYS_DE={"Mo","Di","Mi","Do","Fr","Sa","So"}
local DAYS_EN={"Mon","Tue","Wed","Thu","Fri","Sat","Sun"}
local function trim(s)
return (s:gsub("^%s+",""):gsub("%s+$",""))
end
local function cutOne(s)
local i=#s
while i>1 and (s:byte(i) & 0xC0)==0x80 do i=i - 1 end
return s:sub(1,i - 1)
end
local function wrap(text,width,font,maxLines)
local lines={}
local rem=trim(text)
while rem~="" and #lines<maxLines do
if draw.measure(rem,font)<=width then
lines[#lines+1]=rem
break
end
local best,from=nil,1
while true do
local sp=rem:find(" ",from,true)
if sp==nil then break end
if draw.measure(rem:sub(1,sp - 1),font)<=width then
best=sp
from=sp+1
else
break
end
end
if best~=nil and best>1 then
lines[#lines+1]=rem:sub(1,best - 1)
rem=trim(rem:sub(best+1))
else
local buf=rem:sub(1,79)
local last=#buf
while last>1 and (buf:byte(last) & 0xC0)==0x80 do last=last - 1 end
if last>=1 and buf:byte(last)>=0xC0 then
local b=buf:byte(last)
local need=b>=0xF0 and 4 or (b>=0xE0 and 3 or 2)
if #buf - last+1<need then buf=buf:sub(1,last - 1) end
end
while buf~="" and draw.measure(buf,font)>width do buf=cutOne(buf) end
if buf=="" then break end
lines[#lines+1]=rem:sub(1,#buf)
rem=trim(rem:sub(#buf+1))
end
end
return lines
end
local function stamp(m,en)
local at=m.at
if at==nil then return "" end
local now=time.localtime()
if now~=nil and now.year==at.year and now.month==at.month and now.day==at.day then
return string.format("%02d:%02d",at.hour,at.min)
end
local days=en and DAYS_EN or DAYS_DE
return string.format("%s, %02d:%02d",days[(at.wday+6)%7+1],at.hour,at.min)
end
local function initial(name)
local c=name:match("^[\0-\127\194-\244][\128-\191]*") or "?"
if #c==1 and c>="a" and c<="z" then c=c:upper() end
return c
end
local function emptyState(en,y)
local cx=draw.width//2
local cy=y+14+22
draw.circle(cx,cy,22,color.BLACK,true)
draw.text(cx,cy+7,"-","large",color.WHITE,"center")
draw.text(cx,cy+22+32,en and "No message yet" or "Noch keine Nachricht","large",color.BLACK,"center")
draw.text(cx,cy+22+32+26,en and "Studio -> Store -> Family Board" or "Studio -> Store -> Pinnwand","normal",color.BLACK,"center")
end
function on_draw(ctx,page)
setStyle(ctx.cfg.style)
local en=(ctx.lang=="en")
SHOW=ctx.cfg.details~=false or ctx.preview==true
draw.clear(color.WHITE)
local y=draw.top+14
local m=inbox.latest(MAX_AGE)
if m==nil or m.text==nil or m.text=="" then
emptyState(en,y)
return
end
local cx=draw.width//2
local cardX=40
local cardW=draw.width - 2*cardX
local cardY=y+6
local cardBottom=draw.height - 30
local cardH=cardBottom - cardY
draw.rect(cardX,cardY,cardW,cardH,color.WHITE,true,18)
panel(cardX,cardY,cardW,cardH,18)
draw.rect(cardX+6,cardY+6,5,cardH - 12,color.ACCENT,true,2)
draw.circle(cx,cardY,10,color.ACCENT,true)
draw.circle(cx,cardY,10,color.BLACK,false)
draw.circle(cx,cardY,3,color.WHITE,true)
local pad=28
local left=cardX+pad
local right=cardX+cardW - pad
local width=right - left
local avatarR=24
local rowCy=cardY+pad+avatarR
local avatarCx=left+avatarR
draw.circle(avatarCx,rowCy,avatarR,color.ACCENT,true)
draw.circle(avatarCx,rowCy,avatarR,color.BLACK,false)
local sender=trim(m.sender or "")
if sender=="" then sender=en and "Family" or "Familie" end
draw.text(avatarCx,rowCy+8,initial(sender),"large",color.ACCENT_INK,"center")
draw.text(avatarCx+avatarR+14,rowCy+8,sender,"large",color.BLACK,"left")
local ts=stamp(m,en)
if SHOW and ts~="" then draw.text(right,rowCy+8,ts,"normal",color.BLACK,"right") end
local dividerY=rowCy+avatarR+16
draw.line(left,dividerY,left+width - 1,dividerY,color.BLACK)
local lines=wrap(m.text,width,"large",5)
local font,lineH,textTop="large",34,dividerY+40
if #lines>4 then
font,lineH,textTop="normal",24,dividerY+24
lines=wrap(m.text,width,"normal",8)
end
for i=1,#lines do
local ly=textTop+(i - 1)*lineH
if ly>=cardBottom - 16 then break end
draw.text(left,ly,lines[i],font,color.BLACK,"left")
end
end
function on_action(ctx,name)
local en=(ctx.lang=="en")
if name~="send" then return {ok=false,message=en and "Unknown action." or "Unbekannte Aktion."} end
local cfg=ctx.cfg or {}
local text=trim(cfg.message or "")
if text=="" then
return {ok=false,message=en and "Please enter a message first." or "Bitte zuerst eine Nachricht eingeben."}
end
local room=cfg.room
if room=="all" then room="" end
local ok,err=inbox.send(trim(cfg.sender or ""),text,room or "")
if not ok then
return {ok=false,message=(en and "Not sent: " or "Nicht gesendet: ")..tostring(err)}
end
return {ok=true,message=en and "Sent." or "Gesendet."}
end
