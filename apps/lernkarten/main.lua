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
local LANG_NAME={
eng={"Englisch","English"},spa={"Spanisch","Spanish"},fra={"Französisch","French"},
ita={"Italienisch","Italian"},por={"Portugiesisch","Portuguese"},nld={"Niederländisch","Dutch"},
swe={"Schwedisch","Swedish"},dan={"Dänisch","Danish"},deu={"Deutsch","German"},
}
local SAMPLE_SENT={{f="Where is the train station?",b="Wo ist der Bahnhof?"},{f="I would like a coffee, please.",b="Ich hätte gern einen Kaffee, bitte."}}
local SAMPLE_QUIZ={{f="Which planet is known as the Red Planet?",b="Mars",o={"Venus","Mars","Jupiter","Saturn"}}}
local function deckKey(ctx)
local c=ctx.cfg
return table.concat({c.deck or "sentences",c.learn or "eng",c.native or "deu",c.category or "any",c.difficulty or "any"},"|")
end
local function pct(s)
return (tostring(s or ""):gsub("%%(%x%x)",function(h) return string.char(tonumber(h,16)) end))
end
local function shuffled(list,seed)
local out={table.unpack(list)}
local s=seed
for i=#out,2,-1 do
s=(s*75+74)%65537
local j=s%i+1
out[i],out[j]=out[j],out[i]
end
return out
end
local function fetchTrivia(ctx)
local c=ctx.cfg
local url="https://opentdb.com/api.php?amount=10&type=multiple&encode=url3986"
if c.category and c.category~="any" then url=url.."&category="..c.category end
if c.difficulty and c.difficulty~="any" then url=url.."&difficulty="..c.difficulty end
local body,err=http.get(url,16384)
if not body then return nil,"Open Trivia DB: "..tostring(err) end
local doc=json.decode(body)
if type(doc)~="table" then return nil,"Open Trivia DB: keine Antwort" end
if doc.response_code==5 then return nil,"Zu viele Anfragen, später erneut" end
local out={}
for i,q in ipairs(doc.results or {}) do
local opts={pct(q.correct_answer)}
for _,w in ipairs(q.incorrect_answers or {}) do opts[#opts+1]=pct(w) end
local f=clean(pct(q.question),200)
for k,o in ipairs(opts) do opts[k]=clean(o:gsub("|","/"),60) end
local right=opts[1]
opts=shuffled(opts,i*7919+#f)
out[#out+1]=f.."\t"..right.."\t"..table.concat(opts,"|")
end
if #out==0 then return nil,"Keine Fragen erhalten" end
return out
end
local function fetchSentences(ctx)
local c=ctx.cfg
local from,to=c.learn or "eng",c.native or "deu"
if from==to then return nil,"Lernsprache und Muttersprache sind gleich" end
local url="https://tatoeba.org/en/api_v0/search?from="..from.."&to="..to
.."&trans_filter=limit&trans_to="..to.."&sort=random&limit=12"
local r,err=http.request{url=url,maxBytes=65536,keep={"text","lang"},
skip={"audios","transcriptions","user","permissions","current_user_review","paging"},headers={Accept="application/json"}}
if not r then return nil,"Tatoeba: "..tostring(err) end
if r.status and r.status~=200 then return nil,"Tatoeba: Status "..tostring(r.status) end
local doc=json.decode(r.body or "")
if type(doc)~="table" or type(doc.results)~="table" then return nil,"Tatoeba: keine Antwort" end
local out={}
for _,s in ipairs(doc.results) do
local f,b=clean(s.text,160),nil
for _,grp in ipairs(s.translations or {}) do
for _,t in ipairs(grp) do
if not b and t.lang==to and t.text then b=clean(t.text,160) end
end
end
if b and f~="" and #f<=110 and #b<=110 then out[#out+1]=f.."\t"..b end
end
if #out==0 then return nil,"Keine Sätze erhalten" end
return out
end
function on_fetch(ctx)
local deck=ctx.cfg.deck or "sentences"
if deck=="own" then return true end
local lines,err
if deck=="trivia" then lines,err=fetchTrivia(ctx) else lines,err=fetchSentences(ctx) end
if not lines then
log("Lernkarten: "..tostring(err))
ctx.data.set("err",clean(err,120))
return false
end
local ok,werr=file.write("deck",table.concat(lines,"\n"))
if not ok then
ctx.data.set("err",clean(werr,120))
return false
end
ctx.data.set("key",deckKey(ctx))
ctx.data.set("n",#lines)
ctx.data.set("err","")
return true
end
local function loadDeck(ctx)
local deck=ctx.cfg.deck or "sentences"
local cards={}
if deck=="own" then
local list=type(ctx.cfg.cards)=="table" and ctx.cfg.cards or {}
for _,ln in ipairs(list) do
local f,b=tostring(ln):match("^(.-)%s*[=;]%s*(.+)$")
if f and f~="" then cards[#cards+1]={f=clean(f,160),b=clean(b,160)} end
end
elseif ctx.data.get("key")==deckKey(ctx) then
local raw=file.read("deck") or ""
for ln in raw:gmatch("[^\n]+") do
local f,b,o=ln:match("^([^\t]*)\t([^\t]*)\t?(.*)$")
if f and b then
local card={f=f,b=b}
if o and o~="" then
card.o={}
for part in o:gmatch("[^|]+") do card.o[#card.o+1]=part end
end
cards[#cards+1]=card
end
end
end
if #cards==0 and (ctx.preview==true or ctx.sample or ctx.data.get("demo")=="1") then
cards=(deck=="trivia") and SAMPLE_QUIZ or SAMPLE_SENT
end
return cards
end
local function pickIndex(ctx,n)
if ctx.preview==true or ctx.data.get("demo")=="1" then return 1 end
local iv=(tonumber(ctx.cfg.minutes) or 30)*60
if iv<60 then iv=60 end
local now=time.now() or 0
return (now//iv)%n+1
end
local function wrapAll(s,w,font)
local lines,line={},""
for word in tostring(s):gmatch("%S+") do
local try=line=="" and word or (line.." "..word)
if draw.measure(try,font)<=w or line=="" then
line=try
else
lines[#lines+1]=line
line=word
end
end
if line~="" then lines[#lines+1]=line end
for i,l in ipairs(lines) do lines[i]=fit(l,w,font) end
return lines
end
local LH={large=46,medium=36,normal=28,small=22}
local function layoutText(s,w,availH,fonts)
fonts=fonts or {"large","medium","normal"}
local last=fonts[#fonts]
for _,f in ipairs(fonts) do
local lines=wrapAll(s,w,f)
if #lines*LH[f]<=availH or f==last then
local maxl=math.max(1,availH//LH[f])
while #lines>maxl do table.remove(lines) end
return f,lines
end
end
end
local function drawLines(x,y,lines,font,col,align)
for i,l in ipairs(lines) do draw.text(x,y+(i - 1)*LH[font],l,font,col,align or "left") end
return #lines*LH[font]
end
local function frame(ctx)
local top,bottom=draw.top+14,draw.height - 16
local x,y,w,h=40,top,draw.width - 80,bottom - top
local st=theme.s
if st=="relief" or st=="klar" or st=="cards" then
card(x,y,w,h,color.ACCENT,st=="relief" and 16 or 22)
return x+34,y+20,w - 68,h - 40
elseif st=="flat" then
draw.line(x,y,x+w,y,color.BLACK)
draw.line(x,y+h,x+w,y+h,color.BLACK)
return x+6,y+14,w - 12,h - 28
end
draw.rect(x - 16,y,5,h,color.ACCENT,true)
return x+6,y+10,w - 12,h - 20
end
local function deckLabel(ctx,en)
local c=ctx.cfg
if c.deck=="trivia" then return en and "Quiz" or "Quiz" end
if c.deck=="own" then return en and "My cards" or "Eigene Karten" end
local l=LANG_NAME[c.learn or "eng"] or LANG_NAME.eng
local n=LANG_NAME[c.native or "deu"] or LANG_NAME.deu
local a,b=l[en and 2 or 1],n[en and 2 or 1]
if c.reverse then a,b=b,a end
return a.." - "..b
end
local function pillRow(x,y,w,ctx,en,idx,n)
local label=deckLabel(ctx,en)
pill(x,y,0,30,color.ACCENT,fit(label,w - 140,"small"),"small")
local cnt=idx.."/"..n
local cw=pillW(cnt,"small",30,0)
pill(x+w - cw,y,cw,30,color.ACCENT,cnt,"small")
end
function on_draw(ctx,page)
local en=(ctx.lang=="en")
setStyle(ctx.cfg.style)
draw.clear(color.WHITE)
local cards=loadDeck(ctx)
if #cards==0 then
local err=ctx.data.get("err") or ""
if (ctx.cfg.deck or "sentences")=="own" then
notice("info",en and "No cards yet" or "Noch keine Karten",en and "Add cards in the settings (front = back)" or "Karten in den Einstellungen eintragen (Vorderseite = Rückseite)")
elseif err~="" then
notice("error",en and "Cards not loaded" or "Karten nicht geladen",err)
else
notice("loading",en and "Loading cards ..." or "Karten werden geladen ...")
end
return
end
local idx=pickIndex(ctx,#cards)
local c=cards[idx]
local front,back=c.f,c.b
if c.o==nil and ctx.cfg.reverse then front,back=back,front end
local x,y,w,h=frame(ctx)
pillRow(x,y,w,ctx,en,idx,#cards)
local ty=y+52
local th=h - 52
local backPage=(page==2)
if c.o then
local f,lines=layoutText(front,w,110,{"medium","normal"})
local used=drawLines(x,ty+LH[f] - 8,lines,f,color.BLACK)
local oy=ty+used+14
local rowH=math.min(52,(y+h - oy)//math.max(#c.o,1))
for i,o in ipairs(c.o) do
local ry=oy+(i - 1)*rowH
local label=string.char(64+i).."   "..fit(o,w - 70,"normal")
if backPage and o==back then
pill(x - 6,ry,w+12,rowH - 8,color.ACCENT,label,"normal")
else
draw.text(x+6,ry+rowH//2+4,label,"normal",(backPage and color.BLACK) or color.BLACK,"left")
end
end
return
end
if not backPage then
local f,lines=layoutText(front,w,th - 10)
local total=#lines*LH[f]
drawLines(x+w//2,ty+(th - total)//2+LH[f] - 10,lines,f,color.BLACK,"center")
else
local f1,l1=layoutText(front,w,60,{"normal","small"})
drawLines(x,ty+LH[f1] - 6,l1,f1,color.ACCENT_TEXT)
local ly=ty+math.max(#l1,1)*LH[f1]+10
draw.line(x,ly,x+w,ly,color.BLACK)
local room=y+h - (ly+16)
local f,lines=layoutText(back,w,room)
local total=#lines*LH[f]
drawLines(x+w//2,ly+16+(room - total)//2+LH[f] - 10,lines,f,color.BLACK,"center")
end
end
function on_widget(ctx,box)
setStyle(ctx.cfg.style)
box=widgetFrame(box)
local en=(ctx.lang=="en")
local cards=loadDeck(ctx)
if #cards==0 then
draw.text(box.x+12,box.y+22,en and "No cards yet" or "Noch keine Karten","small",color.BLACK,"left")
return
end
local c=cards[pickIndex(ctx,#cards)]
local front,back=c.f,c.b
if c.o==nil and ctx.cfg.reverse then front,back=back,front end
local w=box.w - 20
local showBack=box.h>=96
local maxFront=showBack and math.max(1,(box.h - 52)//22) or math.max(1,(box.h - 8)//22)
local lines=wrapAll(front,w,"small")
while #lines>maxFront do table.remove(lines) end
local used=drawLines(box.x+12,box.y+20,lines,"small",color.BLACK)
if showBack then
local bl=wrapAll(back,w,"small")
local room=math.max(1,(box.y+box.h - (box.y+used+30))//22)
while #bl>room do table.remove(bl) end
drawLines(box.x+12,box.y+used+30,bl,"small",color.ACCENT_TEXT)
end
end
