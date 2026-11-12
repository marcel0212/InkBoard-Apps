local MAX_PER_PAGE=9
local HIST_N=24
local QUOTE_CHUNK=9
local HIST_CHUNK=5
local CHARS="0123456789abcdefghijklmnopqrstuvwxyz"
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
local CATALOG={
DAX="DAX",SPX="S&P 500",DJI="Dow Jones",IXIC="Nasdaq",
AAPL="Apple",MSFT="Microsoft",GOOGL="Alphabet",AMZN="Amazon",TSLA="Tesla",NVDA="Nvidia",
META="Meta",SAP="SAP",SIE="Siemens",VOW3="Volkswagen",ALV="Allianz",BMW="BMW",
["BTC/EUR"]="Bitcoin",["ETH/EUR"]="Ethereum",["SOL/EUR"]="Solana",["BNB/EUR"]="BNB",["XRP/EUR"]="XRP",
["ADA/EUR"]="Cardano",["DOGE/EUR"]="Dogecoin",["DOT/EUR"]="Polkadot",["LINK/EUR"]="Chainlink",
["LTC/EUR"]="Litecoin",
}
local DEFAULTS={
{"DAX","SPX","AAPL","MSFT","SAP"},
{"BTC/EUR","ETH/EUR","SOL/EUR"},
}
local function parseEntry(raw,crypto)
if type(raw)~="string" then return nil end
local name,sym=raw:match("^(.-)=(.+)$")
if not sym then sym=raw end
sym=trim(sym):upper()
if sym=="" or #sym>15 or not sym:match("^[A-Z0-9%./:_%-]+$") then return nil end
if crypto and not sym:find("/",1,true) then sym=sym.."/EUR" end
name=name and clean(name,23) or ""
local label=name~="" and name or (CATALOG[sym] or sym)
return {sym=sym,label=label}
end
local function symbolsFor(ctx,p)
local out,seen={},{}
local function add(e)
if e and not seen[e.sym] and #out<MAX_PER_PAGE then
seen[e.sym]=true
out[#out+1]=e
end
end
local focus=ctx.cfg[p==1 and "focusStock" or "focusCrypto"]
local hasFocus=type(focus)=="string" and trim(focus)~=""
if hasFocus then add(parseEntry(focus,p==2)) end
local list=ctx.cfg[p==1 and "stocks" or "crypto"]
if type(list)~="table" or #list==0 then
if hasFocus then return out end
list=DEFAULTS[p]
end
for _,raw in ipairs(list) do add(parseEntry(raw,p==2)) end
return out
end
local function readPage(ctx,p)
local map={}
local raw=ctx.data.get("q"..p)
if type(raw)~="string" then return map end
for line in (raw.."\n"):gmatch("([^\n]*)\n") do
local sym,price,pct,cur,hist=line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
local pr=tonumber(price)
if sym and pr then
map[sym]={price=pr,pct=tonumber(pct) or 0,cur=cur,hist=hist}
end
end
return map
end
local function writePage(ctx,p,order,recs)
local lines={}
for _,s in ipairs(order) do
local r=recs[s.sym]
if r then
lines[#lines+1]=s.sym.."\t"..string.format("%.8g",r.price).."\t"..string.format("%.4f",r.pct)
.."\t"..r.cur.."\t"..r.hist
end
end
local text=table.concat(lines,"\n")
while #text>1000 and #lines>1 do
lines[#lines]=nil
text=table.concat(lines,"\n")
end
ctx.data.set("q"..p,text)
end
local function encodeHist(vals)
local n=#vals
if n<2 then return "" end
local lo,hi=vals[1],vals[1]
for i=2,n do
if vals[i]<lo then lo=vals[i] end
if vals[i]>hi then hi=vals[i] end
end
local out={}
for i=1,n do
local k=17
if hi - lo>1e-9 then k=math.floor((vals[i] - lo)/(hi - lo)*35+0.5) end
out[i]=CHARS:sub(k+1,k+1)
end
return table.concat(out)
end
local function decodeHist(s)
local vals={}
for i=1,#s do
local k=CHARS:find(s:sub(i,i),1,true)
if k then vals[#vals+1]=k - 1 end
end
return vals
end
local function apiGet(url)
local r=http.request{url=url,headers={Accept="application/json"}}
if r==nil then return nil,"net" end
if r.status==401 or r.status==403 then return nil,"badkey" end
if r.status==429 then return nil,"limit" end
if r.status~=200 then return nil,"http" end
local doc=decodeCut(r.body,1)
if type(doc)~="table" then return nil,"parse" end
if doc.status=="error" and doc.close==nil and doc.values==nil then
local c=tonumber(doc.code)
if c==401 or c==403 then return nil,"badkey" end
if c==429 then return nil,"limit" end
return nil,"api"
end
return doc
end
local function symbolParam(chunk)
local parts={}
for i,s in ipairs(chunk) do parts[i]=text.url_encode(s.sym) end
return table.concat(parts,",")
end
local function entryOf(doc,chunk,sym)
if #chunk==1 then return doc end
local e=doc[sym]
if type(e)=="table" then return e end
return nil
end
local RANK={badkey=5,limit=4,net=3,http=3,parse=2,api=1}
function on_fetch(ctx)
local key=ctx.cfg.apiKey
if type(key)~="string" or trim(key)=="" then
ctx.data.set("st","nokey")
return
end
key=text.url_encode(trim(key))
local pages,all={symbolsFor(ctx,1),symbolsFor(ctx,2)},{}
for i=1,math.max(#pages[1],#pages[2]) do
for p=1,2 do
local s=pages[p][i]
if s then all[#all+1]={page=p,sym=s.sym,label=s.label} end
end
end
if #all==0 then
ctx.data.set("st","none")
return
end
local spark=ctx.cfg.spark~=false
local budget=ctx.cfg.plan=="paid" and 60 or 8
local k=math.max(1,math.min(#all,budget//(spark and 2 or 1)))
local cursor=tonumber(ctx.data.get("cur")) or 0
if cursor>=#all then cursor=0 end
local batch={}
for i=0,k - 1 do batch[#batch+1]=all[(cursor+i)%#all+1] end
local recs={readPage(ctx,1),readPage(ctx,2)}
local worst,worstRank,okAny=nil,0,false
local calls=0
local function note(why)
if why and (RANK[why] or 0)>worstRank then worst,worstRank=why,RANK[why] end
end
local function pause()
calls=calls+1
if calls>1 then time.sleep(250) end
end
local quoted={}
for from=1,#batch,QUOTE_CHUNK do
local chunk={}
for i=from,math.min(from+QUOTE_CHUNK - 1,#batch) do chunk[#chunk+1]=batch[i] end
pause()
local doc,why=apiGet("https://api.twelvedata.com/quote?symbol="..symbolParam(chunk).."&apikey="..key)
if doc then
for _,s in ipairs(chunk) do
local q=entryOf(doc,chunk,s.sym)
local price=q and tonumber(q.close)
if price then
local cur=type(q.currency)=="string" and q.currency or ""
if cur=="" then cur=s.sym:match("/(%u+)$") or "" end
local old=recs[s.page][s.sym]
recs[s.page][s.sym]={
price=price,
pct=tonumber(q.percent_change) or 0,
cur=clean(cur,3),
hist=old and old.hist or "",
}
quoted[#quoted+1]=s
okAny=true
end
end
else
note(why)
end
end
if spark and #quoted>0 and worstRank<RANK.limit then
for from=1,#quoted,HIST_CHUNK do
local chunk={}
for i=from,math.min(from+HIST_CHUNK - 1,#quoted) do chunk[#chunk+1]=quoted[i] end
pause()
local doc,why=apiGet("https://api.twelvedata.com/time_series?symbol="..symbolParam(chunk)
.."&interval=1h&outputsize="..HIST_N.."&apikey="..key)
if doc then
for _,s in ipairs(chunk) do
local e=entryOf(doc,chunk,s.sym)
local values=e and e.values
if type(values)=="table" then
local vals={}
for idx=#values,1,-1 do
local c=type(values[idx])=="table" and tonumber(values[idx].close)
if c then vals[#vals+1]=c end
end
if #vals>=2 then recs[s.page][s.sym].hist=encodeHist(vals) end
end
end
else
note(why)
end
end
end
for p=1,2 do writePage(ctx,p,pages[p],recs[p]) end
ctx.data.set("cur",tostring((cursor+k)%#all))
ctx.data.set("st",okAny and "ok" or (worst or "api"))
if not okAny and (ctx.data.get("q1") or "")=="" and (ctx.data.get("q2") or "")=="" then return end
if not okAny then return false end
end
local function fmtPrice(x,en)
local s=(x<1 and x>-1) and string.format("%.4f",x) or string.format("%.2f",x)
local int,frac=s:match("^(-?%d+)%.(%d+)$")
local sign=""
if int:sub(1,1)=="-" then sign,int="-",int:sub(2) end
local sep=en and "," or "."
local g=int:reverse():gsub("(%d%d%d)","%1"..sep)
g=g:reverse()
if g:sub(1,1)==sep then g=g:sub(2) end
return sign..g..(en and "." or ",")..frac
end
local function pctText(pct,en)
return (pct>=0 and "+" or "-")..num(math.abs(pct),2,en).." %"
end
local function badgeWidth(pct,font,en)
return (font=="small" and 6 or 8)+4+draw.measure(pctText(pct,en),font)
end
local function drawBadge(x,y,pct,font,en)
local col=pct>=0 and color.GREEN or color.RED
local tri=font=="small" and 6 or 8
local cy=y - tri//2 - 1
if pct>=0 then
draw.triangle(x,cy+tri//2,x+tri,cy+tri//2,x+tri//2,cy - tri//2,col,true)
else
draw.triangle(x,cy - tri//2,x+tri,cy - tri//2,x+tri//2,cy+tri//2,col,true)
end
local t=pctText(pct,en)
draw.text(x+tri+4,y,t,font,col,"left")
return tri+4+draw.measure(t,font)
end
local SHOW=true
local function sparkline(x,y,w,h,vals,col)
local n=#vals
if not SHOW or n<2 or w<8 then return end
local px,py
for i=1,n do
local cx=x+(i - 1)*(w - 1)//(n - 1)
local cy=y+h - 1 - math.floor(vals[i]/35*(h - 1)+0.5)
if px then
draw.line(px,py,cx,cy,col)
draw.line(px,py+1,cx,cy+1,col)
end
px,py=cx,cy
end
end
local function trendColor(pct) return pct>=0 and color.GREEN or color.RED end
local function pageItems(ctx,p)
if ctx.sample then
local H={"89abcdefghijkjihgfghijklm","mlkjihgfeddefghijklmnopq","5678abcdefghijklmnopqrstu"}
if p==2 then
return {
{label="Bitcoin",sym="BTC/EUR",price=61250.5,pct=1.8,cur="EUR",hist=H[1]:sub(1,24)},
{label="Ethereum",sym="ETH/EUR",price=2410.2,pct=-0.7,cur="EUR",hist=H[2]:sub(1,24)},
{label="Solana",sym="SOL/EUR",price=142.35,pct=3.1,cur="EUR",hist=H[3]:sub(1,24)},
}
end
return {
{label="DAX",sym="DAX",price=18432.5,pct=0.8,cur="EUR",hist=H[1]:sub(1,24)},
{label="Apple",sym="AAPL",price=227.1,pct=-0.4,cur="USD",hist=H[2]:sub(1,24)},
{label="SAP",sym="SAP",price=198.4,pct=1.2,cur="EUR",hist=H[3]:sub(1,24)},
}
end
local recs=readPage(ctx,p)
local out={}
for _,s in ipairs(symbolsFor(ctx,p)) do
local r=recs[s.sym]
if r then
r.label,r.sym=s.label,s.sym
out[#out+1]=r
end
end
return out
end
local function emptyState(ctx,p,items)
local en=ctx.lang=="en"
local where=en and "Store -> Stocks & Crypto -> Settings" or "Store -> Aktien & Krypto -> Einstellungen"
local key=ctx.cfg.apiKey
if type(key)~="string" or trim(key)=="" then
notice("gear",en and "Your access key from twelvedata.com is missing." or "Es fehlt noch dein Zugangsschlüssel von twelvedata.com.",where)
return true
end
if #items>0 then return false end
if #symbolsFor(ctx,p)==0 then
notice("gear",p==1 and (en and "No stock selected." or "Keine Aktie ausgewählt.")
or (en and "No cryptocurrency selected." or "Keine Kryptowährung ausgewählt."),where)
return true
end
local st=ctx.data.get("st")
if st==nil then
notice("clock",en and "Loading ..." or "Wird geladen ...")
elseif st=="badkey" then
notice("warning",en and "The access key does not work." or "Der Zugangsschlüssel passt nicht.",where)
elseif st=="limit" then
notice("warning",en and "Too many requests." or "Zu viele Abfragen.",en and "Trying again soon." or "Das Display versucht es gleich noch einmal.")
elseif st=="ok" then
notice("clock",en and "Loading ..." or "Wird geladen ...",en and "More symbols follow with the next update." or "Weitere Symbole folgen beim nächsten Abruf.")
else
notice("warning",en and "Could not load the prices." or "Die Kurse konnten nicht geladen werden.",en and "Trying again soon." or "Das Display versucht es gleich noch einmal.")
end
return true
end
local function drawCards(ctx,items)
local en=ctx.lang=="en"
local pos,tileW,tileH=gridLayout(#items,draw.height>draw.width and 1 or 3,draw.top+2,draw.height - 16,20,12,140)
for i,r in ipairs(items) do
local tx,ty=pos(i)
card(tx,ty,tileW,tileH,color.ACCENT,10)
local bw=badgeWidth(r.pct,"small",en)
draw.text(tx+14,ty+24,fit(r.label,tileW - 28 - bw - 8,"normal"),"normal",color.BLACK,"left")
drawBadge(tx+tileW - 14 - bw,ty+22,r.pct,"small",en)
local price=fmtPrice(r.price,en)
local priceY=ty+tileH - (tileH>100 and 46 or 20)
draw.text(tx+14,priceY,price,"large",color.BLACK,"left")
if r.cur~="" then
draw.text(tx+14+draw.measure(price,"large")+6,priceY,r.cur,"small",color.BLACK,"left")
end
if tileH>100 then
local vals=decodeHist(r.hist)
if #vals>=2 then sparkline(tx+14,ty+tileH - 36,tileW - 28,28,vals,trendColor(r.pct)) end
end
end
end
local function drawFlat(ctx,items)
local en=ctx.lang=="en"
local W=draw.width
local y,bottom=draw.top+6,draw.height - 16
local shown,rowH,truncated=rowLayout(#items,y,bottom,50,74,16)
local sparkX=190
local tall=draw.height>draw.width
local rowY=y
if tall then shown,rowY=0,y end
for i=1,(tall and #items or shown) do
local r=items[i]
local nl=tall and wrapLines(r.label,sparkX - 24 - 8,"normal",3) or {fit(r.label,sparkX - 24 - 8,"normal")}
local ex=(#nl - 1)*22
if tall then
rowH=50+ex
if rowY+rowH>bottom and i>1 then truncated=true; break end
shown=i
else
rowY=y+(i - 1)*rowH
end
for k,l in ipairs(nl) do draw.text(24,rowY+22+(k - 1)*22,l,"normal",color.BLACK,"left") end
drawBadge(24,rowY+38+ex,r.pct,"small",en)
local price=fmtPrice(r.price,en)
local priceW=draw.measure(price,"large")
local curW=r.cur~="" and (4+draw.measure(r.cur,"small")) or 0
local priceX=W - 26 - priceW - curW
local vals=decodeHist(r.hist)
if #vals>=2 then
local sparkW=priceX - 20 - sparkX
if sparkW>40 then sparkline(sparkX,rowY+6,sparkW,32,vals,trendColor(r.pct)) end
end
draw.text(priceX,rowY+26,price,"large",color.BLACK,"left")
if r.cur~="" then draw.text(priceX+priceW+4,rowY+26,r.cur,"small",color.BLACK,"left") end
if i<shown or tall then draw.line(24,rowY+rowH - 6,W - 24,rowY+rowH - 6,color.BLACK) end
if tall then rowY=rowY+rowH end
end
if truncated then
draw.text(W//2,(tall and rowY or y+shown*rowH)+12,
en and ("+"..(#items - shown).." more (all shown in Nano style)") or ("+"..(#items - shown).." weitere (alle im Nano-Stil)"),
"small",color.BLACK,"center")
end
end
local function drawCompact(ctx,items)
local en=ctx.lang=="en"
local W=draw.width
local y=draw.top+4
local rowH=(draw.height - 12 - y)//#items
if rowH>30 then rowH=30 end
local maxPrice,maxBadge=0,0
for _,r in ipairs(items) do
local w=draw.measure(fmtPrice(r.price,en),"small")
if r.cur~="" then w=w+4+draw.measure(r.cur,"small") end
if w>maxPrice then maxPrice=w end
local bw=badgeWidth(r.pct,"small",en)
if bw>maxBadge then maxBadge=bw end
end
local badgeX=W - 24 - maxBadge
local priceX=badgeX - 16 - maxPrice
local tallC=draw.height>draw.width
local acc=y
for i,r in ipairs(items) do
local rowY=y+(i - 1)*rowH
local base=rowY+rowH//2+4
local nl={fit(r.label,priceX - 8 - 24,"small")}
if tallC then
nl=wrapLines(r.label,priceX - 8 - 24,"small",3)
rowH=math.max(30,#nl*17+10)
if acc+rowH>draw.height - 12 and i>1 then break end
rowY=acc
base=rowY+20
acc=acc+rowH
end
for k,l in ipairs(nl) do draw.text(24,base+(k - 1)*17,l,"small",color.BLACK,"left") end
local price=fmtPrice(r.price,en)
draw.text(priceX,base,price,"small",color.BLACK,"left")
if r.cur~="" then draw.text(priceX+draw.measure(price,"small")+4,base,r.cur,"small",color.BLACK,"left") end
drawBadge(badgeX,base,r.pct,"small",en)
if i<#items then draw.line(20,rowY+rowH - 1,W - 20,rowY+rowH - 1,color.BLACK) end
end
end
function on_draw(ctx,page)
SHOW=ctx.cfg.details~=false or ctx.preview==true
draw.clear(color.WHITE)
local p=math.max(1,math.min(page or 1,2))
local items=pageItems(ctx,p)
if emptyState(ctx,p,items) then return end
local style=setStyle(ctx.cfg.style)
if style=="flat" then drawFlat(ctx,items)
elseif style=="compact" then drawCompact(ctx,items)
else drawCards(ctx,items) end
end
function on_widget(ctx,box)
setStyle(ctx.cfg.style)
box=widgetFrame(box)
local en=ctx.lang=="en"
local items=pageItems(ctx,ctx.cfg.wKind=="crypto" and 2 or 1)
local font=((box.font or 0)>0) and "normal" or "small"
if (box.font or 0)<0 then font="small" end
local compact=ctx.cfg.wCompact==true
local withSpark=not compact and ctx.cfg.wSpark~=false
local lineH=compact and 19 or 24
local y=box.y+17
local maxY=box.y+box.h - 4
local nameW=box.w*34//100
local function valueOf(r)
return fmtPrice(r.price,en).." "..(string.format("%+.1f",r.pct):gsub("%.",en and "." or ",")).."%"
end
local maxValue=0
for _,r in ipairs(items) do maxValue=math.max(maxValue,draw.measure(valueOf(r),font)) end
local sparkX=box.x+14+nameW
local sparkW=math.min(box.w*20//100,box.x+box.w - 8 - maxValue - 8 - sparkX)
local shown=0
for _,r in ipairs(items) do
if y>maxY then break end
local col=trendColor(r.pct)
draw.text(box.x+12,y,fit(r.label,nameW,font),font,color.BLACK,"left")
if withSpark and sparkW>=24 then
local vals=decodeHist(r.hist)
if #vals>=2 then sparkline(sparkX,y - 13,sparkW,12,vals,col) end
end
local vx=sparkX+math.max(sparkW,0)+4
draw.text(box.x+box.w - 8,y,fit(valueOf(r),box.x+box.w - 8 - vx,font),font,col,"right")
y=y+lineH
shown=shown+1
end
if shown==0 then
draw.text(box.x+12,box.y+16,ctx.data.get("st")==nil and (en and "No data yet" or "Noch keine Daten") or (en and "No quotes" or "Keine Kurse"),"small",color.BLACK,"left")
end
end
