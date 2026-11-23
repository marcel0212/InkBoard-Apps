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
local API="https://api.themoviedb.org/3/movie/"
local IMG="https://image.tmdb.org/t/p/w185"
local GENRE_DE={[28]="Action",[12]="Abenteuer",[16]="Animation",[35]="Komödie",[80]="Krimi",[99]="Dokumentarfilm",
[18]="Drama",[10751]="Familie",[14]="Fantasy",[36]="Historie",[27]="Horror",[10402]="Musik",[9648]="Mystery",
[10749]="Liebesfilm",[878]="Science-Fiction",[10770]="TV-Film",[53]="Thriller",[10752]="Kriegsfilm",[37]="Western"}
local GENRE_EN={[28]="Action",[12]="Adventure",[16]="Animation",[35]="Comedy",[80]="Crime",[99]="Documentary",
[18]="Drama",[10751]="Family",[14]="Fantasy",[36]="History",[27]="Horror",[10402]="Music",[9648]="Mystery",
[10749]="Romance",[878]="Sci-Fi",[10770]="TV movie",[53]="Thriller",[10752]="War",[37]="Western"}
local SAMPLE={
{"Der Wilde Roboter 2","2026-11-27",7.8,"Animation"},{"Wicked: Teil drei","2026-11-20",7.1,"Fantasy"},
{"Die Gaunerbande","2026-11-13",6.9,"Komödie"},{"Stille im Wald","2026-11-06",6.4,"Thriller"},
{"Mondschein","2026-10-30",7.5,"Drama"},{"Last Stop Berlin","2026-10-23",6.2,"Krimi"},
}
local function dateShort(d,en)
local y,m,dd=tostring(d or ""):match("^(%d+)-(%d+)-(%d+)$")
if not y then return "" end
if en then return string.format("%s/%s",m,dd) end
return string.format("%d.%d.",tonumber(dd),tonumber(m))
end
local function fetchList(ctx,kind,today,en)
local key=ctx.cfg.apiKey
local lang=en and "en-US" or "de-DE"
local region=ctx.cfg.region or "DE"
local url=API..kind.."?api_key="..text.url_encode(key).."&language="..lang.."&region="..region.."&page=1"
local r,err=http.request{url=url,maxBytes=65536,keep={"title","release_date","vote_average","poster_path","genre_ids"},headers={Accept="application/json"}}
if not r then return nil,"TMDB: "..tostring(err) end
if r.status==401 then return nil,en and "TMDB key invalid" or "TMDB-Schlüssel ungültig" end
if r.status and r.status~=200 then return nil,"TMDB: Status "..tostring(r.status) end
local doc=json.decode(r.body or "")
if type(doc)~="table" or type(doc.results)~="table" then return nil,"TMDB: keine Antwort" end
local genres=en and GENRE_EN or GENRE_DE
local rows={}
for _,m in ipairs(doc.results) do
local d=m.release_date or ""
local keep=true
if kind=="upcoming" and d~="" and d<today then keep=false end
if m.title and m.title~="" and keep then
local g=""
if type(m.genre_ids)=="table" and m.genre_ids[1] then g=genres[m.genre_ids[1]] or "" end
rows[#rows+1]={clean(m.title,60),d,tonumber(m.vote_average) or 0,g,m.poster_path or ""}
end
end
if kind=="upcoming" then table.sort(rows,function(a,b) return a[2]<b[2] end) end
return rows
end
local function store(ctx,n,rows)
local lines={}
for i=1,math.min(#rows,8) do
local r=rows[i]
lines[#lines+1]=table.concat({r[1],r[2],string.format("%.1f",r[3]),r[4]},"\t")
end
file.write("k"..n,table.concat(lines,"\n"))
end
function on_fetch(ctx)
local key=ctx.cfg.apiKey
if key==nil or key=="" then
ctx.data.set("err","nokey")
return false
end
local today=time.today()
if not today then return false end
local en=(ctx.lang=="en")
ctx.data.set("err","")
local first=true
for n,kind in ipairs({"now_playing","upcoming"}) do
if not first then time.sleep(300) end
first=false
local rows,err=fetchList(ctx,kind,today,en)
if not rows then
log("Kino: "..tostring(err))
ctx.data.set("err",clean(err,120))
return false
end
store(ctx,n,rows)
ctx.data.set("n"..n,math.min(#rows,8))
if ctx.cfg.posters~=false and rows[1] and rows[1][5]~="" then
time.sleep(300)
local ok=http.image(IMG..rows[1][5],"poster"..n,185,278,{ram=true})
ctx.data.set("p"..n,ok and "1" or "0")
else
ctx.data.set("p"..n,"0")
end
end
ctx.data.set("day",today)
return true
end
local function loadRows(ctx,n)
local rows={}
local raw=file.read("k"..n) or ""
for ln in raw:gmatch("[^\n]+") do
local t,d,v,g=ln:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t?(.*)$")
if t then rows[#rows+1]={t,d,tonumber(v) or 0,g} end
end
if #rows==0 and (ctx.preview==true or ctx.sample or ctx.data.get("demo")=="1") then rows=SAMPLE end
return rows
end
local function rating(v,en)
if not v or v<=0 then return "" end
return num(v,1,en)
end
local function drawRow(x,y,w,h,r,en,upcoming)
local sub=r[4]
local right=upcoming and dateShort(r[2],en) or rating(r[3],en)
if right=="" then right=dateShort(r[2],en) end
local rw=draw.measure(right,"normal")
draw.text(x+w,y+h//2+6,right,"normal",color.ACCENT_TEXT,"right")
local tw=w - rw - 20
if sub~="" and h>=52 then
draw.text(x,y+h//2 - 2,fit(r[1],tw,"normal"),"normal",color.BLACK,"left")
draw.text(x,y+h//2+20,fit(sub,tw,"small"),"small",color.BLACK,"left")
else
draw.text(x,y+h//2+6,fit(r[1],tw,"normal"),"normal",color.BLACK,"left")
end
end
function on_draw(ctx,page)
local en=(ctx.lang=="en")
setStyle(ctx.cfg.style)
draw.clear(color.WHITE)
local n=(page==2) and 2 or 1
local upcoming=n==2
if (ctx.cfg.apiKey==nil or ctx.cfg.apiKey=="") and not ctx.preview and ctx.data.get("demo")~="1" then
notice("gear",en and "TMDB key missing" or "TMDB-Schlüssel fehlt",en and "Enter your free key in the app settings" or "Kostenlosen Schlüssel in den App-Einstellungen eintragen")
return
end
local rows=loadRows(ctx,n)
if #rows==0 then
local err=ctx.data.get("err") or ""
if err~="" and err~="nokey" then notice("error",en and "Not loaded" or "Nicht geladen",err)
else notice("loading",en and "Loading ..." or "Wird geladen ...") end
return
end
local fancy=theme.s=="relief" or theme.s=="klar" or theme.s=="cards"
local top,bottom=draw.top+14,draw.height - 16
local hasPoster=ctx.data.get("p"..n)=="1" and draw.image_size("poster"..n)~=nil
local first=rows[1]
local px=40
local colW=hasPoster and 220 or 0
if hasPoster then
local iw,ih=draw.image_size("poster"..n)
if fancy then card(px,top,colW,bottom - top,color.ACCENT,theme.s=="relief" and 16 or 22) end
local ix=px+(colW - iw)//2
local iy=top+16
if theme.s=="relief" then draw.rect(ix+4,iy+4,iw,ih,color.BLACK,true) end
draw.image("poster"..n,ix,iy)
draw.rect(ix,iy,iw,ih,color.BLACK,false)
end
local lx=px+(hasPoster and colW+26 or 0)
local lw=draw.width - 40 - lx
local head=upcoming and (en and "Coming soon" or "Demnächst") or (en and "In cinemas" or "Im Kino")
if fancy then
card(lx,top,lw,bottom - top,color.ACCENT,theme.s=="relief" and 16 or 22)
lx,lw=lx+28,lw - 56
else
draw.rect(lx - 14,top,5,bottom - top,color.ACCENT,true)
end
draw.text(lx,top+38,head,"medium",color.BLACK,"left")
local lw0,lh0=draw.image_size("tmdb")
if lw0 then
draw.image("tmdb",lx+lw - lw0,top+24 - lh0//2)
else
draw.text(lx+lw,top+36,"TMDB","small",color.ACCENT_TEXT,"right")
end
local note=en and "Uses the TMDB API, not endorsed or certified by TMDB." or "Nutzt die TMDB-API, von TMDB nicht unterstützt oder zertifiziert."
draw.text(lx,bottom - 10,fit(note,lw,"small"),"small",color.ACCENT_TEXT,"left")
local ry=top+58
local shown,rowH=rowLayout(#rows,ry,bottom - 40,48,70)
for i=1,shown do
local y=ry+(i - 1)*rowH
if i>1 then draw.line(lx,y,lx+lw,y,color.BLACK) end
drawRow(lx,y,lw,rowH,rows[i],en,upcoming)
end
end
function on_widget(ctx,box)
setStyle(ctx.cfg.style)
box=widgetFrame(box)
local en=(ctx.lang=="en")
local rows=loadRows(ctx,1)
if #rows==0 then
local nokey=ctx.cfg.apiKey==nil or ctx.cfg.apiKey==""
draw.text(box.x+12,box.y+22,nokey and (en and "TMDB key missing" or "TMDB-Schlüssel fehlt") or (en and "No data yet" or "Noch keine Daten"),"small",color.BLACK,"left")
return
end
local n=math.min(#rows,math.max(1,(box.h - 4)//28))
local rh=box.h//n
for i=1,n do
local r=rows[i]
local y=box.y+(i - 1)*rh+rh//2+6
local rt=rating(r[3],en)
local rw=rt~="" and draw.measure(rt,"small")+10 or 0
if rt~="" then draw.text(box.x+box.w - 6,y,rt,"small",color.ACCENT_TEXT,"right") end
draw.text(box.x+12,y,fit(r[1],box.w - rw - 28,"small"),"small",color.BLACK,"left")
end
end
