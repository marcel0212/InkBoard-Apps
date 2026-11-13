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
local KINDS={
free   ={de="Frei",en="Free"},
busy   ={de="Beschäftigt",en="Busy"},
meeting={de="Im Meeting",en="In a meeting"},
dnd    ={de="Bitte nicht stören",en="Do not disturb"},
away   ={de="Nicht da",en="Away"},
focus  ={de="Fokus-Zeit",en="Focus time"},
custom ={de="",en=""},
}
local function T(ctx,de,en) return (ctx.lang=="en") and en or de end
local function kindColor(k)
if k=="free" then return color.GREEN,color.WHITE end
if k=="busy" or k=="meeting" or k=="dnd" then return color.RED,color.WHITE end
if k=="away" then return color.YELLOW,color.BLACK end
if k=="focus" then return color.BLUE,color.WHITE end
return color.ACCENT,color.ACCENT_INK
end
local function clean(t,max)
t=tostring(t or ""):gsub("[%c]"," "):gsub("^%s+",""):gsub("%s+$","")
if #t>max then
local i=max
while i>1 and (t:byte(i+1) or 0) & 0xC0==0x80 do i=i - 1 end
t=t:sub(1,i)
end
return t
end
local function esc(s) return (tostring(s or ""):gsub('[%c"\\]',function(c) if c=='"' then return '\\"' elseif c=="\\" then return "\\\\" end return " " end)) end
local function current(ctx)
local st=tostring(ctx.data.get("st") or "")
local until_=tonumber(ctx.data.get("until")) or 0
local now=time.now() or 0
if st~="" and until_>0 and now>0 and now>=until_ then st="" end
local s={st=st,title=tostring(ctx.data.get("ttl") or ""),text=tostring(ctx.data.get("txt") or ""),
untilText=tostring(ctx.data.get("unt") or ""),next=tostring(ctx.data.get("nxt") or "")}
if st=="" then
local fb=(ctx.cfg and ctx.cfg.fallback) or "free"
if fb=="none" then s.st=""; s.text=""; s.untilText=""; s.title=""; s.next=tostring(ctx.data.get("nxt") or "") ; return s end
s.st=fb; s.title=""; s.text=""; s.untilText=""
end
return s
end
local function label(ctx,s)
if s.st=="" then return T(ctx,"Kein Status","No status") end
if s.title~="" then return s.title end
local k=KINDS[s.st] or KINDS.custom
local t=(ctx.lang=="en") and k.en or k.de
if t=="" then t=T(ctx,"Hinweis","Note") end
return t
end
local function fit(text,maxW,fonts)
for i=1,#fonts do
if draw.measure(text,fonts[i])<=maxW then return fonts[i] end
end
return fonts[#fonts]
end
local function bigFit(text,maxW,maxScale)
for sc=maxScale,2,-1 do if draw.measure(text,"large",sc)<=maxW then return "large",sc end end
for _,f in ipairs({"large","medium","normal"}) do if draw.measure(text,f)<=maxW then return f,1 end end
return "normal",1
end
local function untilLine(ctx,s)
if s.untilText=="" then return "" end
return T(ctx,"bis ","until ")..s.untilText
end
local function drawBento(ctx,s)
local bg,ink=kindColor(s.st)
draw.clear(color.WHITE)
local x,y,w,h=36,draw.top+12,draw.width - 72,draw.height - draw.top - 40
draw.rect(x,y,w,h,color.WHITE,true,22)
panel(x,y,w,h,22)
draw.rect(x+10,y+10,16,h - 20,bg,true,8)
local left=x+50
local inner=x+w - 28 - left
local name=tostring(ctx.cfg.name or "")
if name~="" and ctx.cfg.showName~=false then
draw.text(left,y+48,name,fit(name,inner - 56,{"large","medium","normal"}),color.BLACK,"left")
end
draw.circle(x+w - 60,y+52,22,bg,true)
draw.circle(x+w - 60,y+52,22,color.BLACK,false)
local t=label(ctx,s)
local f,sc=bigFit(t,inner,2)
draw.text(left,y+h//2+22,t,f,bg==color.YELLOW and color.BLACK or bg,"left",sc)
local sub=s.text
local ul=untilLine(ctx,s)
local ly=y+h//2+70
if sub~="" then draw.wrap(left,ly,inner,sub,"normal",color.BLACK); ly=ly+34 end
if ul~="" and ctx.cfg.showUntil~=false then
local cw=draw.measure(ul,"normal")+28
draw.rect(left,y+h - 92,cw,36,bg,true,14)
draw.text(left+14,y+h - 66,ul,"normal",ink,"left")
end
if s.next~="" then
draw.line(left,y+h - 44,x+w - 28,y+h - 44,color.BLACK)
draw.text(left,y+h - 16,T(ctx,"Danach: ","Next: ")..s.next,"small",color.BLACK,"left")
end
end
local function drawSlate(ctx,s)
local bg,ink=kindColor(s.st)
draw.clear(bg)
local cx=draw.width//2
local name=tostring(ctx.cfg.name or "")
if name~="" and ctx.cfg.showName~=false then
draw.text(cx,draw.top+52,name,"large",ink,"center")
end
local t=label(ctx,s)
local f,sc=bigFit(t,draw.width - 80,3)
draw.text(cx,draw.height//2+28,t,f,ink,"center",sc)
local ul=untilLine(ctx,s)
local y=draw.height//2+84
if s.text~="" then draw.text(cx,y,s.text,fit(s.text,draw.width - 40,{"medium","normal","small"}),ink,"center"); y=y+40 end
if ul~="" and ctx.cfg.showUntil~=false then draw.text(cx,y,ul,"large",ink,"center") end
if s.next~="" then draw.text(cx,draw.height - 22,T(ctx,"Danach: ","Next: ")..s.next,"normal",ink,"center") end
end
local function drawNano(ctx,s)
local bg=kindColor(s.st)
draw.clear(color.WHITE)
local x=56
draw.circle(x+30,draw.top+90,30,bg,true)
draw.circle(x+30,draw.top+90,30,color.BLACK,false)
local t=label(ctx,s)
local f=fit(t,draw.width - x - 120,{"large","medium","normal"})
draw.text(x+90,draw.top+90+10,t,f,color.BLACK,"left")
local y=draw.top+160
local name=tostring(ctx.cfg.name or "")
if name~="" and ctx.cfg.showName~=false then draw.text(x,y,name,"normal",color.BLACK,"left"); y=y+36 end
if s.text~="" then draw.wrap(x,y,draw.width - 2*x,s.text,"normal",color.BLACK); y=y+36 end
local ul=untilLine(ctx,s)
if ul~="" and ctx.cfg.showUntil~=false then draw.text(x,y,ul,"normal",color.ACCENT_TEXT,"left"); y=y+36 end
if s.next~="" then draw.text(x,draw.height - 26,T(ctx,"Danach: ","Next: ")..s.next,"small",color.BLACK,"left") end
end
function on_draw(ctx,page)
local s=current(ctx)
if ctx.data.get("ts")==nil then
if ctx.cfg.setupHint~=false and device.qrscreen(T(ctx,"Türschild einrichten","Set up door sign"),T(ctx,"Status setzen: QR-Code scannen","Set status: scan the QR code")) then return end
end
local style=setStyle(ctx.cfg.style) or "cards"
if style=="flat" then drawSlate(ctx,s)
elseif style=="compact" then drawNano(ctx,s)
else drawBento(ctx,s) end
end
function on_widget(ctx,box)
setStyle(ctx.cfg.style)
box=widgetFrame(box)
local s=current(ctx)
local bg,ink=kindColor(s.st)
local style=setStyle(ctx.cfg.style) or "cards"
local t=label(ctx,s)
local ul=untilLine(ctx,s)
if style=="flat" then
draw.rect(box.x+2,box.y+2,box.w - 4,box.h - 4,bg,true,10)
local f=fit(t,box.w - 20,{"large","normal","small"})
draw.text(box.x+box.w//2,box.y+box.h//2+(ul~="" and 2 or 8),t,f,ink,"center")
if ul~="" then draw.text(box.x+box.w//2,box.y+box.h//2+26,ul,"small",ink,"center") end
return
end
local r=math.min(14,box.h//4)
draw.circle(box.x+12+r,box.y+box.h//2,r,bg,true)
draw.circle(box.x+12+r,box.y+box.h//2,r,color.BLACK,false)
local tx=box.x+24+2*r
local f=fit(t,box.x+box.w - tx - 8,{"large","normal","small"})
draw.text(tx,box.y+box.h//2+((ul~="" or style=="cards") and 0 or 8),t,f,color.BLACK,"left")
if ul~="" then draw.text(tx,box.y+box.h//2+22,ul,"small",color.BLACK,"left") end
end
local function stateJson(ctx)
local s=current(ctx)
return string.format('{"st":"%s","title":"%s","text":"%s","until":%d,"untilText":"%s","next":"%s","ts":%d}',
esc(s.st),esc(s.title),esc(s.text),tonumber(ctx.data.get("until")) or 0,esc(s.untilText),esc(s.next),tonumber(ctx.data.get("ts")) or 0)
end
function on_http(ctx,req)
local q=json.decode(req.body or "")
if type(q)~="table" then return {status=400,body='{"error":"JSON"}'} end
local op=tostring(q.op or "get")
if op=="set" then
local st=tostring(q.st or "custom")
if KINDS[st]==nil then st="custom" end
local now=time.now() or 0
local u=tonumber(q["until"]) or 0
if u>0 and now>0 and u>now+14*86400 then u=0 end
ctx.data.set("st",st)
ctx.data.set("ttl",clean(q.title,40))
ctx.data.set("txt",clean(q.text,80))
ctx.data.set("until",u>0 and u or 0)
ctx.data.set("unt",u>0 and clean(q.untilText,12) or "")
ctx.data.set("nxt",clean(q.next,60))
ctx.data.set("ts",now>0 and now or 1)
return {status=200,body=stateJson(ctx),redraw=true}
elseif op=="clear" then
ctx.data.set("st",""); ctx.data.set("ttl",""); ctx.data.set("txt",""); ctx.data.set("until",0); ctx.data.set("unt",""); ctx.data.set("nxt","")
ctx.data.set("ts",time.now() or 1)
return {status=200,body=stateJson(ctx),redraw=true}
end
return {status=200,body=stateJson(ctx)}
end
function on_fetch(ctx)
return true
end
