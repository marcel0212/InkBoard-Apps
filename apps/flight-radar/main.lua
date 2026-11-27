local EN=false
local function T(de,en) if EN then return en end return de end
local ADSB="https://api.adsb.lol"
local MIN_GAP=120
local RETRY=120
local FAR_KM=150
local FAR_AGE=600
local POOL=50
local COVPOOL=8
local KEEP={"hex","flight","r","t","desc","ownOp","lat","lon","alt_baro","gs","track"}
local MISS_TTL,MISS_MAX=1800,16
local AIR_GAP=1800
local COV_FLUSH=600
local COV_PROBES=4
local PROBES=16
local SKY_VER="r54"
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
local function radiusOf(cfg)
local r=tonumber(cfg.radius)
if r==nil then return 25 end
r=math.floor(r+0.5)
if r<5 or r>100 then return 25 end
return r
end
local SKY={white=color.WHITE,blue=color.BLUE,yellow=color.YELLOW,green=color.GREEN,black=color.BLACK}
local function skyOf(cfg)
local s=cfg.sky
if SKY[s]==nil then return "white" end
return s
end
local function rnd(x) return math.floor(x+0.5) end
local function keyOf(loc,radius) return string.format("%.4f,%.4f,%d",loc.lat,loc.lon,radius) end
local function split(s)
local t,i={},1
while true do
local j=s:find("\t",i,true)
if not j then t[#t+1]=s:sub(i); break end
t[#t+1]=s:sub(i,j - 1)
i=j+1
end
return t
end
local function icaoOf(cs)
if #cs>=3 and cs:sub(1,3):find("^%u%u%u$") then return cs:sub(1,3) end
return nil
end
local DIRS_DE={"N","NO","O","SO","S","SW","W","NW"}
local DIRS_EN={"N","NE","E","SE","S","SW","W","NW"}
local function compass(b) return (EN and DIRS_EN or DIRS_DE)[((b+22)//45)%8+1] end
local RAD=math.pi/180
local function distKm(la1,lo1,la2,lo2)
local dLa,dLo=(la2 - la1)*RAD,(lo2 - lo1)*RAD
local s1,s2=math.sin(dLa/2),math.sin(dLo/2)
local a=s1*s1+math.cos(la1*RAD)*math.cos(la2*RAD)*s2*s2
return 6371.0*2*math.atan(math.sqrt(a),math.sqrt(1 - a))
end
local function bearing(la1,lo1,la2,lo2)
local dLo=(lo2 - lo1)*RAD
local y=math.sin(dLo)*math.cos(la2*RAD)
local x=math.cos(la1*RAD)*math.sin(la2*RAD) - math.sin(la1*RAD)*math.cos(la2*RAD)*math.cos(dLo)
local d=rnd(math.atan(y,x)/RAD)
if d<0 then d=d+360 end
return d%360
end
local TB
local function tables()
if TB==nil then TB="\n"..(asset.read("tables") or "") end
return TB
end
local OV
local function overlay()
if OV then return OV end
OV={air={},airN={},grp={},typ={}}
local txt=file.read("airl")
if txt then
for line in txt:gmatch("[^\n]+") do
local f=split(line)
if f[1]=="A" and f[2] then
OV.air[f[2]]={i=f[3] or "",n=f[4] or "",c=f[5] or ""}
OV.airN[#OV.airN+1]=f[2]
elseif f[1]=="G" and f[2] then
OV.grp[f[2]]=true
elseif f[1]=="T" and f[2] and f[3] then
OV.typ[#OV.typ+1]={f[2],f[3],f[4]=="1"}
end
end
end
return OV
end
local function airInfo(icao)
local o=overlay().air[icao]
local bi,bn,bc="","",""
local s=tables():find("\nA;"..icao..";",1,true)
if s then
local e=TB:find("\n",s+1,true) or (#TB+1)
bi,bn,bc=TB:sub(s+3,e - 1):match("^[^;]*;([^;]*);([^;]*);([^;]*)")
bi,bn,bc=bi or "",bn or "",bc or ""
end
return (o and o.i~="") and o.i or bi,(o and o.n~="") and o.n or bn,(o and o.c~="") and o.c or bc
end
local function typeAsset(tc)
if tc==nil or tc=="" then return nil end
local ov=overlay()
local g,base
for _,e in ipairs(ov.typ) do
if tc:sub(1,#e[1])==e[1] then g,base=e[2],e[3]; break end
end
if not g then
for p,grp,l in tables():gmatch("\nT;([^;]*);([^;]*);(%d)") do
if tc:sub(1,#p)==p then g,base=grp,l=="1"; break end
end
end
if not g then return nil end
return g,base or ov.grp[g]==true
end
local ACRAW=""
local function acLine(tag,a)
return table.concat({tag,a.hex,a.cs,a.reg,a.tc,a.desc,a.air,string.format("%.4f",a.lat),string.format("%.4f",a.lon),
a.gnd and 1 or 0,a.alt,a.gs,a.trk,string.format("%.2f",a.dist),a.brg,a.grp,a.lv and 1 or 0,a.ia,a.tl},"\t")
end
local function saveAc(key,at,total,list,far)
local out={"H\t"..key.."\t"..at.."\t"..total}
for _,a in ipairs(list) do out[#out+1]=acLine("A",a) end
if far and far.key and #far.list>0 then
out[#out+1]="FH\t"..far.key.."\t"..far.at
for _,a in ipairs(far.list) do out[#out+1]=acLine("F",a) end
end
return file.write("ac",table.concat(out,"\n"))
end
local function loadAc()
local txt=file.read("ac")
if not txt then return nil,nil end
local ac,fail,raw={list={}},nil,{}
for line in txt:gmatch("[^\n]+") do
local f=split(line)
if f[1]=="H" then
ac.key,ac.at,ac.total=f[2],tonumber(f[3]) or 0,tonumber(f[4]) or 0
raw[#raw+1]=line
elseif (f[1]=="A" or f[1]=="F") and #f>=15 then
local dst=ac.list
if f[1]=="F" then
ac.far=ac.far or {list={}}
dst=ac.far.list
end
dst[#dst+1]={hex=f[2],cs=f[3],reg=f[4],tc=f[5],desc=f[6],air=f[7],lat=tonumber(f[8]) or 0,
lon=tonumber(f[9]) or 0,gnd=f[10]=="1",alt=tonumber(f[11]) or -1,gs=tonumber(f[12]) or -1,
trk=tonumber(f[13]) or -1,dist=tonumber(f[14]) or 0,brg=tonumber(f[15]) or 0,
grp=f[16] or "",lv=f[17]=="1",ia=f[18] or "",tl=f[19] or ""}
raw[#raw+1]=line
elseif f[1]=="FH" then
ac.far=ac.far or {list={}}
ac.far.key,ac.far.at=f[2],tonumber(f[3]) or 0
raw[#raw+1]=line
elseif f[1]=="E" then
fail={key=f[2],at=tonumber(f[3]) or 0,msg=f[4] or ""}
end
end
ACRAW=table.concat(raw,"\n")
if ac.key==nil then ac=nil end
return ac,fail
end
local function applyFeature(ctx,ac)
local ft=ctx.data.get("ft")
if type(ft)~="string" or ft=="" or not ac or not ac.list or (ac.list[1] and ac.list[1].hex==ft) then return end
for i=2,#ac.list do
if ac.list[i].hex==ft then
local a=table.remove(ac.list,i)
table.insert(ac.list,1,a)
return
end
end
end
local function saveFail(key,now,msg)
local line="E\t"..key.."\t"..now.."\t"..clean(msg,100)
return file.write("ac",ACRAW=="" and line or (ACRAW.."\n"..line))
end
local S
local sDirty=false
local function stLoad()
if S then return S end
S={miss={},sig="",air=0,seen={},seenSet={},ex={},exN={},bk={},dl={}}
local txt=file.read("st")
if not txt then return S end
for line in txt:gmatch("[^\n]+") do
local f=split(line)
local k=f[1]
if k=="M" and f[2] then S.miss[#S.miss+1]={f[2],tonumber(f[3]) or 0}
elseif k=="S" then S.sig=f[2] or ""
elseif k=="T" then S.air=tonumber(f[2]) or 0
elseif k=="D" then S.dl[#S.dl+1]=f[2] or ""
elseif k=="C" then
S.cv={date=f[2] or "",time=f[3] or "",fn=f[4] or "fr_inkboard.csv",start=tonumber(f[5]) or 0,flush=tonumber(f[6]) or 0,
pend=f[7]=="1",dirty=f[8]=="1",last=tonumber(f[9]) or 0,closed=f[10]=="1"}
elseif k=="X" and f[2] then S.seen[#S.seen+1]=f[2]; S.seenSet[f[2]]=true
elseif k=="E" and f[2] then S.ex[f[2]]=tonumber(f[3]) or 0; S.exN[#S.exN+1]=f[2]
elseif k=="B" and #f>=13 then
local smp={}
for x in (f[14] or ""):gmatch("[^|]+") do smp[#smp+1]=x end
S.bk[#S.bk+1]={cat=tonumber(f[2]) or 0,grp=f[3],tc=f[4],tn=f[5],icao=f[6],ia=f[7],air=f[8],n=tonumber(f[9]) or 0,
amin=tonumber(f[10]) or 0,amax=tonumber(f[11]) or 0,have=f[12]=="1",gnd=f[13]=="1",smp=smp}
end
end
return S
end
local function stText(slim)
local o={}
for _,m in ipairs(S.miss) do o[#o+1]="M\t"..m[1].."\t"..m[2] end
o[#o+1]="S\t"..S.sig
o[#o+1]="T\t"..S.air
for _,l in ipairs(S.dl) do o[#o+1]="D\t"..l end
local cv=S.cv
if cv then
o[#o+1]=table.concat({"C",cv.date,cv.time,cv.fn,cv.start,cv.flush,cv.pend and 1 or 0,cv.dirty and 1 or 0,cv.last,cv.closed and 1 or 0},"\t")
if not slim then
for _,h in ipairs(S.seen) do o[#o+1]="X\t"..h end
for _,n in ipairs(S.exN) do o[#o+1]="E\t"..n.."\t"..S.ex[n] end
end
for _,b in ipairs(S.bk) do
o[#o+1]=table.concat({"B",b.cat,b.grp,b.tc,b.tn,b.icao,b.ia,b.air,b.n,b.amin,b.amax,b.have and 1 or 0,b.gnd and 1 or 0,
table.concat(b.smp,"|")},"\t")
end
end
return table.concat(o,"\n")
end
local function stFlush()
if not S or not sDirty then return end
local txt=stText(false)
if #txt>23000 then txt=stText(true) end
local ok,err=file.write("st",txt)
if not ok then log("Flight Radar: Zustand nicht gespeichert ("..tostring(err)..")") end
sDirty=false
end
local function missHas(name,now)
for _,m in ipairs(S.miss) do
if m[1]==name then return now - m[2]<MISS_TTL end
end
return false
end
local function missAdd(name,now)
for _,m in ipairs(S.miss) do
if m[1]==name then m[2]=now; sDirty=true; return end
end
if #S.miss>=MISS_MAX then table.remove(S.miss,1) end
S.miss[#S.miss+1]={name,now}
sDirty=true
end
local probes=0
local EXM={}
local function fileExists(name,now)
if EXM[name]~=nil then return EXM[name] end
if missHas(name,now) then return false end
if probes>=PROBES then return nil end
probes=probes+1
local r,err=storage.exists("dir",name)
if r==nil then log("Flight Radar: "..name..": "..tostring(err)); return nil end
EXM[name]=r
if not r then missAdd(name,now) end
return r
end
local function skyFile(a)
if a.grp=="" then return nil end
if a.lv then
if a.ia=="" then return nil end
return a.grp.."_"..a.ia..".png"
end
return a.grp..".png"
end
local CNAME={black="K",schwarz="K",white="W",weiss="W",["weiß"]="W",red="R",rot="R",green="G",gruen="G",
["grün"]="G",blue="B",blau="B",yellow="Y",gelb="Y"}
local CEXP={K="schwarz",W="weiss",R="rot",G="gruen",B="blau",Y="gelb"}
local function oneLine(s,n)
s=tostring(s):gsub("%c"," ")
return s:sub(1,n)
end
local function parseAirlines(doc)
local n={air={},airN={},grp={},grpN={},typ={}}
local skipped=0
if type(doc.airlines)=="table" then
for _,o in ipairs(doc.airlines) do
if #n.airN>=64 then
skipped=skipped+1
elseif type(o)=="table" and type(o.icao)=="string" and #o.icao==3 then
local icao=o.icao:upper()
local iata=type(o.iata)=="string" and #o.iata==2 and o.iata:lower() or ""
local name=type(o.name)=="string" and oneLine(o.name,31) or ""
local c=type(o.color)=="string" and CNAME[o.color:lower()] or ""
n.air[icao]={i=iata,n=name,c=c}
n.airN[#n.airN+1]=icao
else
skipped=skipped+1
end
end
end
if type(doc.enableLiveryGroups)=="table" then
for _,g in ipairs(doc.enableLiveryGroups) do
if #n.grpN>=16 then break end
if type(g)=="string" and g~="" then
n.grp[g:sub(1,15)]=true
n.grpN[#n.grpN+1]=g:sub(1,15)
end
end
end
if type(doc.aircraftTypes)=="table" then
for _,o in ipairs(doc.aircraftTypes) do
local p,g=type(o)=="table" and o.prefix,type(o)=="table" and o.group
if #n.typ>=32 then
skipped=skipped+1
elseif type(p)=="string" and type(g)=="string" and #p>=1 and #p<=7 and #g>=1 and #g<=15 then
local l=o.hasLiveries
if type(l)~="boolean" then l=true end
n.typ[#n.typ+1]={p:upper(),g,l}
else
skipped=skipped+1
end
end
end
return n,skipped
end
local function overlayText(n)
local o={}
for _,k in ipairs(n.airN) do
local a=n.air[k]
o[#o+1]="A\t"..k.."\t"..a.i.."\t"..a.n.."\t"..a.c
end
for _,g in ipairs(n.grpN) do o[#o+1]="G\t"..g end
for _,t in ipairs(n.typ) do o[#o+1]="T\t"..t[1].."\t"..t[2].."\t"..(t[3] and 1 or 0) end
return table.concat(o,"\n")
end
local function diffOverlay(old,new)
local lines,plus,tilde,minus={},0,0,0
local function dash(s) return s~="" and s or "-" end
for _,k in ipairs(new.airN) do
local b,a=old.air[k],new.air[k]
if not b then
plus=plus+1
lines[#lines+1]="+ "..k..(a.n~="" and (" ("..a.n..")") or "")
else
local ch=""
if b.i~=a.i then ch=ch.."IATA "..dash(b.i).."->"..dash(a.i).."; " end
if b.n~=a.n then ch=ch.."Name "..dash(b.n).."->"..dash(a.n).."; " end
if b.c~=a.c then ch=ch.."Farbe geaendert; " end
if ch~="" then tilde=tilde+1; lines[#lines+1]="~ "..k..": "..ch end
end
end
for _,k in ipairs(old.airN) do
if not new.air[k] then minus=minus+1; lines[#lines+1]="- "..k.." (nicht mehr in airlines.json enthalten)" end
end
for g in pairs(new.grp) do
if not old.grp[g] then plus=plus+1; lines[#lines+1]='+ Baugruppe "'..g..'" freigeschaltet' end
end
for g in pairs(old.grp) do
if not new.grp[g] then minus=minus+1; lines[#lines+1]='- Baugruppe "'..g..'" nicht mehr freigeschaltet' end
end
local oldT={}
for _,t in ipairs(old.typ) do oldT[t[1]]=t end
local newT={}
for _,t in ipairs(new.typ) do
newT[t[1]]=true
local b=oldT[t[1]]
if not b then
plus=plus+1
lines[#lines+1]='+ Typcode "'..t[1]..'" -> Gruppe "'..t[2]..'"'..(t[3] and "" or " (ohne Lackierungen)")
else
local ch=""
if b[2]~=t[2] then ch=ch.."Gruppe "..b[2].."->"..t[2].."; " end
if b[3]~=t[3] then ch=ch.."Lackierungen "..(b[3] and "an" or "aus").."->"..(t[3] and "an" or "aus").."; " end
if ch~="" then tilde=tilde+1; lines[#lines+1]='~ Typcode "'..t[1]..'": '..ch end
end
end
for _,t in ipairs(old.typ) do
if not newT[t[1]] then minus=minus+1; lines[#lines+1]='- Typcode "'..t[1]..'" (nicht mehr in airlines.json enthalten)' end
end
return lines,plus,tilde,minus
end
local function applyAirlines(txt)
local doc,derr=json.decode(txt)
if type(doc)~="table" then
log("Flight Radar: airlines.json nicht lesbar ("..tostring(derr)..") - bisheriger Stand bleibt aktiv.")
return false,T("airlines.json nicht lesbar - bisheriger Stand bleibt aktiv.","airlines.json not readable - the previous state stays active.")
end
local new,skipped=parseAirlines(doc)
local lines,plus,tilde,minus=diffOverlay(overlay(),new)
local ok,err=file.write("airl",overlayText(new))
if not ok then return false,"file: "..tostring(err) end
OV=new
stLoad().sig=""
S.dl={}
local used=0
for _,l in ipairs(lines) do
if used>1800 then S.dl[#S.dl+1]="..."; break end
S.dl[#S.dl+1]=l
used=used+#l+1
end
if #S.dl==0 then S.dl[1]="(keine Aenderungen gegenueber dem vorherigen Stand)" end
sDirty=true
for _,l in ipairs(lines) do log("Flight Radar: airlines.json "..l) end
local msg=string.format(T("airlines.json geladen: %d Airlines, %d Liverei-Gruppen, %d Flugzeugtypen. Änderungen: +%d ~%d -%d.","airlines.json loaded: %d airlines, %d livery groups, %d aircraft types. Changes: +%d ~%d -%d."),
#new.airN,#new.grpN,#new.typ,plus,tilde,minus)
if skipped>0 then msg=msg..string.format(T(" %d ungültige übersprungen."," %d invalid skipped."),skipped) end
if lines[1] then msg=msg.." "..cut(lines[1],36) end
return true,msg
end
local function exportJson()
local ov=overlay()
local order,seen={},{}
for icao in tables():gmatch("\nA;(%u+);") do
if not seen[icao] then seen[icao]=true; order[#order+1]=icao end
end
for _,k in ipairs(ov.airN) do
if not seen[k] then seen[k]=true; order[#order+1]=k end
end
local out={'{\n  "airlines": [\n'}
for i,icao in ipairs(order) do
local ia,nm,c=airInfo(icao)
local row='    {"icao": "'..icao..'"'
if ia~="" then row=row..', "iata": "'..ia..'"' end
if nm~="" then row=row..', "name": "'..nm:gsub('"',"'")..'"' end
if c~="" then row=row..', "color": "'..CEXP[c]..'"' end
out[#out+1]=row.."}"..(i<#order and "," or "").."\n"
end
out[#out+1]='  ],\n  "enableLiveryGroups": [\n'
local groups,gseen,types,over={},{},{},{}
for _,e in ipairs(ov.typ) do over[e[1]]=true end
local tbl={}
for p,g,l in tables():gmatch("\nT;([^;]*);([^;]*);(%d)") do tbl[#tbl+1]={p,g,l=="1"} end
for _,e in ipairs(tbl) do
if (e[3] or ov.grp[e[2]]) and not gseen[e[2]] then gseen[e[2]]=true; groups[#groups+1]=e[2] end
end
local gk={}
for g in pairs(ov.grp) do gk[#gk+1]=g end
table.sort(gk)
for _,g in ipairs(gk) do
if not gseen[g] then gseen[g]=true; groups[#groups+1]=g end
end
for i,g in ipairs(groups) do out[#out+1]='    "'..g..'"'..(i<#groups and "," or "").."\n" end
for _,e in ipairs(ov.typ) do types[#types+1]={e[1],e[2],e[3]} end
for _,e in ipairs(tbl) do
if not over[e[1]] then types[#types+1]={e[1],e[2],e[3] or ov.grp[e[2]]==true} end
end
out[#out+1]='  ],\n  "aircraftTypes": [\n'
for i,e in ipairs(types) do
out[#out+1]='    {"prefix": "'..e[1]..'", "group": "'..e[2]..'", "hasLiveries": '..(e[3] and "true" or "false").."}"..
(i<#types and "," or "").."\n"
end
out[#out+1]="  ]\n}\n"
return table.concat(out)
end
local CATS={[0]="Fehlendes Lackierungsbild","Fehlendes Basisbild","Airline ohne IATA-Zuordnung","Unbekannter Flugzeugtyp"}
local CHEAD={"Scan-Datum","Scan-Uhrzeit","Kategorie","Flugzeugtyp","Typ-Code","Flugzeuggruppe","Airline","Airline-ICAO","Airline-IATA",
"Anzahl Sichtungen","Reisehöhe","Beispiele (Callsign/Registrierung)","Route (Linienflug?)","Historie (fruehere Scans)","Hinweis"}
local function csvField(s)
s=tostring(s)
if s:find('[;"\r\n]') then return '"'..(s:gsub('"','""'))..'"' end
return s
end
local function fmtInt(v)
local s=tostring(math.abs(v))
local o=s:reverse():gsub("(%d%d%d)","%1."):reverse()
if o:sub(1,1)=="." then o=o:sub(2) end
return (v<0 and "-" or "")..o
end
local function covCsv()
local out={"\xEF\xBB\xBF"}
local row={}
for i,h in ipairs(CHEAD) do row[i]=csvField(h) end
out[#out+1]=table.concat(row,";").."\r\n"
local ord={}
for i=1,#S.bk do ord[i]=S.bk[i] end
for i=2,#ord do
local key,j=ord[i],i - 1
while j>=1 and (ord[j].cat>key.cat or (ord[j].cat==key.cat and ord[j].n<key.n)) do ord[j+1]=ord[j]; j=j - 1 end
ord[j+1]=key
end
for _,b in ipairs(ord) do
local alt
if b.have then
alt=b.amin==b.amax and (fmtInt(b.amin).." ft") or (fmtInt(b.amin).."-"..fmtInt(b.amax).." ft")
else
alt=b.gnd and "Boden" or "?"
end
local hint
if b.cat==0 then hint=string.format("Datei %s_%s.png im Asset-Paket ergaenzen",b.grp,b.ia)
elseif b.cat==1 then hint=string.format("Basisdatei %s.png im Asset-Paket ergaenzen",b.grp)
elseif b.cat==2 then hint=string.format('FR_ICAO_IATA um "%s" erweitern - UND danach vermutlich auch die Lackierung %s_??.png ergaenzen',b.icao,b.grp)
else hint=string.format('FR_TYPE_ASSETS um "%s" (%s) erweitern',b.tc,b.tn) end
local f={S.cv.date,S.cv.time,CATS[b.cat],b.tn,b.tc,b.grp,b.air,b.icao,b.ia,tostring(b.n),alt,table.concat(b.smp,", "),"","",hint}
for i=1,#f do f[i]=csvField(f[i]) end
out[#out+1]=table.concat(f,";").."\r\n"
end
return table.concat(out)
end
local function covFlush(now)
local cv=S.cv
if not cv then return nil end
cv.flush,cv.dirty=now,false
sDirty=true
if not storage.ready() then return nil end
local ok,err=storage.write("cov",cv.fn,covCsv())
cv.pend=not ok
log(string.format("Flight Radar: Auswertung %s (%d Punkte) %s.",cv.fn,#S.bk,ok and "auf dem Speicher abgelegt" or ("NICHT auf den Speicher geschrieben: "..tostring(err))))
return ok,err
end
local function covStart(now)
stLoad()
if S.cv and (S.cv.pend or S.cv.dirty) then covFlush(now) end
local t=time.localtime()
local cv={date="",time="",fn="fr_inkboard.csv",start=now,flush=now,pend=false,dirty=false,last=now,closed=false}
if t then
cv.date=string.format("%02d.%02d.%04d",t.day,t.month,t.year%10000)
cv.time=string.format("%02d:%02d",t.hour,t.min)
cv.fn=string.format("fr_inkboard_%04d%02d%02d_%02d%02d.csv",t.year,t.month,t.day,t.hour,t.min)
end
S.cv,S.seen,S.seenSet,S.ex,S.exN,S.bk=cv,{},{},{},{},{}
sDirty=true
end
local function covAdd(cat,grp,ia,a,icao)
local b
for _,e in ipairs(S.bk) do
if e.cat==cat and ((cat==0 and e.grp==grp and e.ia==ia) or (cat==1 and e.grp==grp) or (cat==2 and e.icao==icao and e.grp==grp)
or (cat==3 and e.tc==a.tc)) then b=e; break end
end
if not b then
if #S.bk>=48 then return end
b={cat=cat,grp=grp,tc=a.tc,tn=a.desc,icao=icao,ia=ia,air=a.air,n=0,amin=0,amax=0,have=false,gnd=false,smp={}}
S.bk[#S.bk+1]=b
end
if b.n<65535 then b.n=b.n+1 end
if b.tn=="" then b.tn=a.desc end
if b.air=="" then b.air=a.air end
local smp=(a.cs~="" and a.cs or "?").."/"..(a.reg~="" and a.reg or "?")
local known=false
for _,x in ipairs(b.smp) do if x==smp then known=true end end
if not known and #b.smp<6 then b.smp[#b.smp+1]=smp end
if a.gnd then b.gnd=true
elseif not b.have then b.amin,b.amax,b.have=a.alt,a.alt,true
else
if a.alt<b.amin then b.amin=a.alt end
if a.alt>b.amax then b.amax=a.alt end
end
S.cv.dirty=true
sDirty=true
end
local function covExists(name,now,left)
if S.ex[name]~=nil then return S.ex[name],left end
local v=EXM[name]
if v==nil and missHas(name,now) then v=false end
if v==nil then
if left<=0 or probes>=PROBES then return -2,left end
left=left - 1
v=fileExists(name,now)
if v==nil then return -1,left end
end
local r=v and 1 or 0
if #S.exN<48 then S.exN[#S.exN+1]=name; S.ex[name]=r; sDirty=true end
return r,left
end
local function covClassify(a,now,left)
if a.tc=="" then return true,left end
local icao=icaoOf(a.cs) or ""
if a.grp=="" then covAdd(3,"","",a,icao); return true,left end
local nasOk=storage.ready()
local base=a.grp..".png"
local e,b
if not a.lv then
if not nasOk then return true,left end
e,left=covExists(base,now,left)
if e==0 then covAdd(1,a.grp,"",a,icao) end
return e>=0,left
end
if a.ia=="" then covAdd(2,a.grp,"",a,icao); return true,left end
if not nasOk then return true,left end
e,left=covExists(a.grp.."_"..a.ia..".png",now,left)
if e<0 then return false,left end
if e==1 then return true,left end
b,left=covExists(base,now,left)
if b<0 then return false,left end
if b==0 then covAdd(1,a.grp,"",a,icao) else covAdd(0,a.grp,a.ia,a,icao) end
return true,left
end
local function covStep(ac,now)
stLoad()
if not S.cv or S.cv.closed or now - S.cv.last>900 then covStart(now) end
S.cv.last=now
local left=COV_PROBES
for i=1,math.min(#ac.list,COVPOOL) do
local a=ac.list[i]
if a.hex~="" and not S.seenSet[a.hex] then
local done
done,left=covClassify(a,now,left)
if done then
if #S.seen>=96 then S.seenSet[table.remove(S.seen,1)]=nil end
S.seen[#S.seen+1]=a.hex
S.seenSet[a.hex]=true
sDirty=true
end
end
end
if S.cv.dirty and now - S.cv.flush>=COV_FLUSH then covFlush(now) end
end
local function covSummary()
local c={[0]=0,0,0,0}
for _,b in ipairs(S.bk) do c[b.cat]=c[b.cat]+1 end
return string.format(T("%d Punkte: %d Lackierung fehlt, %d Basisbild fehlt, %d Airline ohne IATA, %d unbekannter Typ.",
"%d items: %d livery missing, %d base image missing, %d airline without IATA, %d unknown type."),#S.bk,c[0],c[1],c[2],c[3])
end
local function visible(ctx)
if ctx.view==nil or ctx.view=="app" then return true end
return ctx.view=="dashboard" and #(ctx.widgets or {})>0
end
local function fld(v,n)
if type(v)~="string" then return "" end
return clean(v,n)
end
local function makeAc(a,d,loc)
local cs=fld(a.flight,9)
local icao=icaoOf(cs)
local ia,nm,tl="","",""
if icao then ia,nm,tl=airInfo(icao) end
local air=fld(a.ownOp,35)
if air=="" then air=nm end
local tc=fld(a.t,5)
local grp,lv=typeAsset(tc)
local ab=a.alt_baro
local gnd=type(ab)=="string"
local trk=type(a.track)=="number" and rnd(a.track)%360 or -1
return {hex=fld(a.hex,7),cs=cs,reg=fld(a.r,11),tc=tc,desc=fld(a.desc,39),air=air,
lat=a.lat,lon=a.lon,gnd=gnd,alt=gnd and 0 or (type(ab)=="number" and rnd(ab) or -1),
gs=type(a.gs)=="number" and rnd(a.gs) or -1,trk=trk,dist=d,brg=bearing(loc.lat,loc.lon,a.lat,a.lon),
grp=grp or "",lv=lv==true,ia=ia,tl=tl}
end
local function parseAc(body,loc,radius)
local p=body:find('"ac":[',1,true)
if not p then return nil end
local pool,total={},0
for obj in body:gmatch("%b{}",p+6) do
local a=json.decode(obj)
if type(a)=="table" and type(a.lat)=="number" and type(a.lon)=="number" then
local d=distKm(loc.lat,loc.lon,a.lat,a.lon)
if d<=radius+0.5 then
total=total+1
local slot
if #pool<POOL then
slot=#pool+1
else
local worst,wi=-1,nil
for i=1,#pool do
if pool[i].dist>worst then worst,wi=pool[i].dist,i end
end
if wi and d<worst then slot=wi end
end
if slot then pool[slot]=makeAc(a,d,loc) end
end
end
end
table.sort(pool,function(x,y) return x.dist<y.dist end)
return pool,total
end
local function routeStep(ctx,first)
local cs=first.cs:gsub("[^%w]","")
if cs=="" then ctx.data.set("rt",nil); return end
local rt=ctx.data.get("rt")
if type(rt)=="string" and rt:match("^([^|]*)")==cs then return end
local from,to="",""
local body='{"planes":[{"callsign":"'..cs..'","lat":'..string.format("%.4f",first.lat)..',"lng":'..string.format("%.4f",first.lon).."}]}"
local r=http.request{url=ADSB.."/api/0/routeset",method="POST",body=body,maxBytes=8192,
headers={["Content-Type"]="application/json",Accept="application/json"}}
if r and r.status==200 then
local doc=json.decode(r.body)
local codes=type(doc)=="table" and type(doc[1])=="table" and doc[1]._airport_codes_iata
if type(codes)=="string" and codes~="" and not codes:find("unknown",1,true) then
local a,b=codes:match("^([^-]+).*%-([^-]+)$")
if a and #a>=3 and #b>=3 then from,to=a:sub(1,4),b:sub(1,4) end
end
else
log("Flight Radar: Route nicht abrufbar")
end
ctx.data.set("rt",cs.."|"..from.."|"..to)
end
local function nasKnown(name,now,cap)
stLoad()
local v=S.ex[name]
if v~=nil then return v==1 end
if EXM[name]==nil and not missHas(name,now) and probes>=cap then return nil end
return fileExists(name,now)
end
local function featureStep(ctx,ac,now)
if not storage.ready() then return end
local pick,partial,gone=nil,false,false
local old=ctx.data.get("ft")
for i=1,#ac.list do
local name=skyFile(ac.list[i])
if name then
local r=nasKnown(name,now,9)
if r then pick=ac.list[i].hex; break end
if r==nil then partial=true elseif ac.list[i].hex==old then gone=true end
end
end
if pick then
ctx.data.set("ft",pick)
elseif not partial or gone then
ctx.data.set("ft",nil)
end
applyFeature(ctx,ac)
end
local SLOTS_P={
{{20,460,40,760,240,true}},
{{20,460,420,760,240,true},{20,460,40,380,240,true}},
{{20,460,520,760,240,true},{20,460,290,500,240,true},{20,460,40,270,240,true}},
{{20,460,570,780,240,true},{20,400,395,560,210,true},{80,460,225,385,270,true},{20,400,40,215,210,true}},
{{20,460,600,780,240,true},{20,400,440,590,210,true},{80,460,290,430,270,true},{20,400,160,280,210,true},{80,460,40,150,270,true}},
}
local function bands(heights,gap,top,scx)
local out,y={},top
for i,h in ipairs(heights) do
out[i]={15,790,y,y+h,scx[i],false}
y=y+h+gap
end
return out
end
local SLOTS={
{{{20,780,20,414,400,true}},{{20,780,20,414,300,true}},{{20,780,20,414,500,true}}},
{bands({190,160},24,40,{300,500}),bands({160,190},24,40,{500,300}),bands({190,160},24,40,{500,300}),bands({160,190},24,40,{300,500})},
{bands({156,138,120},14,10,{300,500,300}),bands({120,156,138},14,10,{500,300,500}),bands({138,120,156},14,10,{300,500,300}),
bands({156,120,138},14,10,{500,300,500}),bands({138,156,120},14,10,{300,500,300}),bands({120,138,156},14,10,{500,300,500})},
}
local LABEL_H=58
local function skyOri() return draw.height>draw.width and "P" or "L" end
local function skySig(ctx,ac)
local p={SKY_VER..skyOri(),skyOf(ctx.cfg)}
for i=1,math.min(#ac.list,POOL) do
local a=ac.list[i]
p[#p+1]=(a.grp~="" and a.grp or "-")..":"..((a.lv and a.ia~="") and a.ia or "-")
end
return table.concat(p,"|")
end
local function skyImagesThere(sk)
for _,e in ipairs(sk) do
if not draw.image_size("sky"..e.idx) then return false end
end
return true
end
local function skyParse(v)
if type(v)~="string" then return nil,{} end
local sig,rest=v:match("^([^~]*)~(.*)$")
if not sig then return nil,{} end
local list={}
for ent in rest:gmatch("[^;]+") do
local f={}
for n in ent:gmatch("[^,]+") do f[#f+1]=n end
if #f>=9 then
list[#list+1]={hex=f[1],idx=tonumber(f[2]),x=tonumber(f[3]),y=tonumber(f[4]),lx=tonumber(f[5]),ly=tonumber(f[6]),
lw=tonumber(f[7])}
end
end
return sig,list
end
local function farList(ctx,ac,now)
local loc=weather.location()
if not loc then return {} end
local key=keyOf(loc,FAR_KM)
local fa=ac.far
if fa and fa.key~=key then fa=nil end
if fa and now>=fa.at and now - fa.at<FAR_AGE then return fa.list end
local tried=tonumber(ctx.data.get("fat")) or 0
if now>=tried and now - tried<RETRY then return fa and fa.list or {} end
ctx.data.set("fat",tostring(now))
local nm=math.min(250,math.max(3,rnd(FAR_KM/1.852)))
local r,err=http.request{url=string.format(ADSB.."/v2/point/%.4f/%.4f/%d",loc.lat,loc.lon,nm),keep=KEEP,maxBytes=65536,
headers={Accept="application/json"}}
if not r or r.status~=200 or r.body=="" then
log("Flight Radar: erweiterte Suche fehlgeschlagen: "..tostring(err or (r and r.status)))
return fa and fa.list or {}
end
local pool,total=parseAc(r.body,loc,FAR_KM)
r=nil
if not pool then return fa and fa.list or {} end
ac.far={key=key,at=now,list=pool}
if ac.key then saveAc(ac.key,ac.at,ac.total,ac.list,ac.far) end
log(string.format("Flight Radar: erweiterte Suche (%d km): %d Flugzeug(e).",FAR_KM,total))
return pool
end
local function skyStep(ctx,ac,now)
if not storage.ready() then return end
stLoad()
local sig=skySig(ctx,ac)
local cands,partial={},false
local maxC=skyOri()=="P" and 5 or 3
local function known(name)
local r=nasKnown(name,now,PROBES - #cands - 1)
if r==nil then partial=true; return false end
return r
end
for i=1,math.min(#ac.list,POOL) do
if #cands>=maxC then break end
local a=ac.list[i]
local name=(a.lv and not a.gnd) and skyFile(a) or nil
if name and known(name) then cands[#cands+1]={a=a,name=name} end
end
if #cands<maxC and not partial then
local seen={}
for _,a in ipairs(ac.list) do seen[a.hex]=true end
for _,f in ipairs(farList(ctx,ac,now)) do
if #cands>=maxC then break end
local name=(not seen[f.hex]) and f.lv and not f.gnd and skyFile(f) or nil
if name and known(name) then cands[#cands+1]={a=f,name=name} end
end
end
if #cands==0 and partial then return end
local prev=tonumber(ctx.data.get("skv")) or 0
local slots
if skyOri()=="P" then
slots={}
local base=SLOTS_P[#cands] or {}
local off=#base>0 and (now//7)%#base or 0
if off==prev and #base>1 then off=(off+1)%#base end
for c=1,#base do slots[c]=base[(c - 1+off)%#base+1] end
ctx.data.set("skv",tostring(off))
else
local set=SLOTS[#cands] or {}
local v=#set>0 and (now//7)%#set+1 or 1
if v==prev and #set>1 then v=v%#set+1 end
slots=set[v] or {}
ctx.data.set("skv",tostring(v))
end
local ent={}
local ol=(skyOf(ctx.cfg)=="blue" or skyOf(ctx.cfg)=="black") and color.WHITE or color.BLACK
for c,cand in ipairs(cands) do
local s=slots[c]
local x0,x1,y0,y1,scx,below=s[1],s[2],s[3],s[4],s[5],s[6]
local slotW,slotH=x1 - x0,y1 - y0 - (below and LABEL_H or 0)
if probes>=PROBES then break end
probes=probes+1
local w,h=storage.image("dir",cand.name,"sky"..c,{w=math.min(slotW - 8,600),h=slotH,up=133,style="cutout",outline=ol})
if w and w>=8 and h>=8 then
local x=math.max(x0,math.min(x1 - w,scx - w//2))
local y=math.max(y0,math.min(y0+slotH - h,y0+slotH//2 - h//2))
local lx,ly,lw
if below then
lx,ly,lw=x+w//2,math.min(draw.height - 36,y+h+27),math.min(slotW - 16,380)
else
local rightFree,leftFree=790 - (x+w),x - 10
if rightFree>=leftFree then lx=x+w+math.min(rightFree,190)//2+4 else lx=x - math.min(leftFree,190)//2 - 4 end
lx=math.max(75,math.min(725,lx))
ly=y+h//2+5
lw=math.max(60,math.min(math.max(rightFree,leftFree),190) - 10)
end
ent[#ent+1]=table.concat({cand.a.hex,c,x,y,lx,ly,lw,w,h},",")
else
if w==nil and tostring(h):find("nicht gefunden",1,true) then missAdd(cand.name,now) end
log("Flight Radar: Himmel "..cand.name..": "..tostring(h))
end
end
if #ent==0 and partial then return end
S.sig=(partial and #cands<maxC) and "" or sig
sDirty=true
ctx.data.set("sk",sig.."~"..table.concat(ent,";"))
log(string.format("Flight Radar: Himmel komponiert (%d von %d Flugzeugen als Render).",#ent,math.min(#ac.list,POOL)))
end
local function extras(ctx,ac,now)
featureStep(ctx,ac,now)
skyStep(ctx,ac,now)
covStep(ac,now)
end
local function airlinesPeriodic(now)
stLoad()
if now - S.air<AIR_GAP or not storage.ready() then return end
S.air=now
sDirty=true
local txt,err=storage.read("dir","airlines.json")
if txt then applyAirlines(txt) elseif err~="nicht gefunden" then log("Flight Radar: airlines.json: "..tostring(err)) end
end
local function fetchMain(ctx)
EN=ctx.lang=="en"
probes,EXM=0,{}
if not visible(ctx) then return true end
local loc=weather.location()
if not loc then return true end
local radius=radiusOf(ctx.cfg)
local key=keyOf(loc,radius)
local now=time.now()
if now==nil then log("Flight Radar: Uhr nicht synchron"); return false end
local shown=ctx.view==nil or ctx.view=="app"
local ac,fail=loadAc()
if ac then applyFeature(ctx,ac) end
local have=ac and ac.key==key
airlinesPeriodic(now)
if ctx.opened then
if shown then covStart(now) end
if shown and have and not (fail and fail.key==key) then
if #ac.list>0 then extras(ctx,ac,now) else skyStep(ctx,ac,now) end
end
return true
end
if fail and fail.key==key then
if now - fail.at<RETRY then return false end
elseif have and now>=ac.at and now - ac.at<MIN_GAP then
if shown then
if #ac.list>0 then extras(ctx,ac,now) else skyStep(ctx,ac,now) end
end
return true
end
local nm=rnd(radius/1.852)
if nm<3 then nm=3 elseif nm>250 then nm=250 end
local r,err=http.request{url=string.format(ADSB.."/v2/point/%.4f/%.4f/%d",loc.lat,loc.lon,nm),keep=KEEP,maxBytes=65536,
headers={Accept="application/json"}}
local msg
if not r then
log("Flight Radar: "..tostring(err))
msg=T("Verbindung fehlgeschlagen","Connection failed")
elseif r.status~=200 then
log("Flight Radar: HTTP-Status "..tostring(r.status))
msg=T("Quelle nicht erreichbar","Source unreachable")
elseif r.body=="" then
msg=T("Leere Antwort","Empty response")
else
local pool,total=parseAc(r.body,loc,radius)
r=nil
if pool==nil then
log("Flight Radar: Antwort ohne ac-Liste")
msg=T("Antwort nicht erkannt","Response not recognized")
else
local ok,werr=saveAc(key,now,total,pool,have and ac.far or nil)
if not ok then
msg="file: "..tostring(werr)
else
log(string.format("Flight Radar: %d Flugzeug(e) im Umkreis (%d uebernommen).",total,#pool))
if #pool>0 then
local acn={key=key,at=now,list=pool,total=total,far=have and ac.far or nil}
applyFeature(ctx,acn)
routeStep(ctx,acn.list[1])
if shown then
local before=acn.list[1]
extras(ctx,acn,now)
if acn.list[1]~=before then routeStep(ctx,acn.list[1]) end
end
else
ctx.data.set("rt",nil)
if shown then skyStep(ctx,{key=key,at=now,list={},total=total,far=have and ac.far or nil},now) end
end
return true
end
end
end
saveFail(key,now,msg)
return false
end
function on_fetch(ctx)
local ok=fetchMain(ctx)
stFlush()
return ok
end
function on_close(ctx)
EN=ctx.lang=="en"
probes=0
stLoad()
local now=time.now() or 0
if S.cv then
if S.cv.pend or S.cv.dirty then covFlush(now) end
S.cv.closed=true
sDirty=true
end
stFlush()
end
function on_action(ctx,name)
EN=ctx.lang=="en"
probes=0
if name=="coverage" then
stLoad()
local now=time.now() or 0
if not S.cv then return {ok=false,message=T("Noch keine Auswertung: erst die App öffnen und Flugzeuge abwarten.","No coverage data yet: open the app and wait for aircraft.")} end
local ok,err=covFlush(now)
stFlush()
local msg=covSummary()
if ok then return {ok=true,message=cut(msg.." "..S.cv.fn,150)} end
if ok==nil then return {ok=true,message=cut(msg.." "..T("Kein Speicher eingerichtet.","No storage set up."),150)} end
return {ok=false,message=cut(msg.." "..tostring(err),150)}
end
if name=="airlines_import" then
local txt=file.read("airin")
if not txt then return {ok=false,message=T("Keine Datei empfangen.","No file received.")} end
file.write("airin","")
stLoad().air=time.now() or 0
local ok,msg=applyAirlines(txt)
stFlush()
return {ok=ok,message=cut(msg,150)}
end
if name=="airlines_diff" then
stLoad()
if #S.dl==0 then return {ok=false,message=T("Noch keine airlines.json übernommen.","No airlines.json applied yet.")} end
local ok,err=file.write("airdiff",T("Änderungen der letzten airlines.json-Übernahme","Changes of the last airlines.json import").."\n\n"..table.concat(S.dl,"\n").."\n")
if not ok then return {ok=false,message=tostring(err)} end
return {ok=true,message=T("Änderungsliste bereit.","Change list ready.")}
end
if name=="coverage_download" then
stLoad()
if not S.cv then return {ok=false,message=T("Noch keine Auswertung: erst die App öffnen und Flugzeuge abwarten.","No coverage data yet: open the app and wait for aircraft.")} end
local ok,err=file.write("covout",covCsv())
if not ok then return {ok=false,message=T("Auswertung zu gross oder nicht speicherbar: ","Report too large or not storable: ")..tostring(err)} end
return {ok=true,message=cut(covSummary(),150)}
end
if name=="airlines_download" then
local ok,err=file.write("airout",exportJson())
if not ok then return {ok=false,message=T("Export zu gross oder nicht speicherbar: ","Export too large or not storable: ")..tostring(err)} end
return {ok=true,message=T("Gesamtstand bereit.","Overall state ready.")}
end
if name~="airlines_run" and name~="airlines_reload" then return {ok=false,message=T("Unbekannte Aktion.","Unknown action.")} end
local mode=name=="airlines_reload" and "reload" or ctx.cfg.airMode
if mode=="export" then
if not storage.ready() then return {ok=false,message=T("Kein externer Speicher eingerichtet.","No external storage set up.")} end
local ok,err=storage.write("dir","airlines_export.json",exportJson())
if not ok then return {ok=false,message=tostring(err)} end
return {ok=true,message=T("airlines_export.json liegt im Speicher-Ordner (als airlines.json umbenennen und ergänzen).","airlines_export.json is in the storage folder (rename to airlines.json and extend).")}
elseif mode=="reset" then
file.write("airl","")
stLoad().sig=""
S.dl={"(alle eigenen Eintraege verworfen)"}
sDirty=true
stFlush()
return {ok=true,message=T("Eigene Einträge verworfen, es gilt wieder der eingebaute Stand.","Own entries discarded, the built-in state applies again.")}
end
if not storage.ready() then return {ok=false,message=T("Kein externer Speicher eingerichtet.","No external storage set up.")} end
local txt,err=storage.read("dir","airlines.json")
if not txt then
if err=="nicht gefunden" then return {ok=false,message=T("Keine airlines.json im Speicher-Ordner gefunden.","No airlines.json found in the storage folder.")} end
return {ok=false,message=tostring(err)}
end
stLoad().air=time.now() or 0
local ok,msg=applyAirlines(txt)
stFlush()
return {ok=ok,message=cut(msg,150)}
end
local EXTRAS=true
local function nameOf(a) return a.cs~="" and a.cs or (a.reg~="" and a.reg or a.hex) end
local function routeOf(ctx,a)
local rt=ctx.data.get("rt")
if type(rt)~="string" or a.cs=="" then return nil end
local cs,from,to=rt:match("^([^|]*)|([^|]*)|([^|]*)$")
if cs==a.cs:gsub("[^%w]","") and #from>=3 and #to>=3 then return from,to end
return nil
end
local function arrowRoute(x,baseY,from,to,font,gap,aw,hh,limitX)
draw.text(x,baseY,from,font,color.BLACK)
local ax=x+draw.measure(from,font)+gap
local ay=baseY - (aw>30 and 10 or 8)
if limitX and ax+aw+gap+draw.measure(to,font)>limitX then return end
draw.rect(ax,ay - 1,aw - (aw>30 and 8 or 7),3,color.ACCENT,true)
draw.triangle(ax+aw - (aw>30 and 9 or 8),ay - hh,ax+aw - (aw>30 and 9 or 8),ay+hh,ax+aw,ay,color.ACCENT,true)
draw.text(ax+aw+gap,baseY,to,font,color.BLACK)
end
local function haloText(x,y,str,font,ink,halo,al)
for dy=-1,1 do
for dx=-1,1 do
if dx~=0 or dy~=0 then draw.text(x+dx,y+dy,str,font,halo,al) end
end
end
draw.text(x,y,str,font,ink,al)
end
local function altText(a)
if a.gnd then return T("am Boden","on ground") end
if a.alt>=0 then return fmtInt(rnd(a.alt*0.3048)).." m" end
return nil
end
local function skyLabel(a,e,ink,halo,H)
local lw=e.lw>0 and e.lw or 150
local cx,ly=e.lx,math.min(e.ly,H - 36)
if not EXTRAS then
haloText(cx,ly,fit(a.cs~="" and a.cs or (a.tc~="" and a.tc or a.hex),lw,"small"),"small",ink,halo,"center")
return
end
local typ=a.desc~="" and a.desc or a.tc
local air=a.air~="" and a.air:upper() or (typ~="" and typ:upper() or "")
local l2=nameOf(a)
if a.air~="" and typ~="" then l2=l2 .." · "..typ end
local l3=a.dist<10 and string.format("%.1f km",a.dist) or string.format("%d km",rnd(a.dist))
local at=altText(a)
if at then l3=l3 .." · "..at end
local t1=fit(air,lw,"small")
haloText(cx,ly - 17,t1,"small",ink,halo,"center")
local rw=math.max(40,math.min(lw,draw.measure(t1,"small")))
draw.rect(cx - rw//2 - 1,ly - 10,rw+2,3,halo,true)
draw.rect(cx - rw//2,ly - 9,rw,1,ink,true)
haloText(cx,ly+7,fit(l2,lw,"small"),"small",ink,halo,"center")
haloText(cx,ly+22,fit(l3,lw,"small"),"small",ink,halo,"center")
end
local function skyPage(ctx,st,ac,radius)
local W,H=draw.width,draw.height
local id=skyOf(ctx.cfg)
local dark=id=="blue" or id=="black"
local fg=dark and color.WHITE or color.BLACK
if id~="white" then draw.rect(0,0,W,H,SKY[id],true) end
local sg,ent=skyParse(ctx.data.get("sk"))
if sg and sg:sub(1,#SKY_VER+1)~=SKY_VER..skyOri() then ent={} end
if st~="ok" and not (st=="empty" and #ent>0) then
local line
if st=="noloc" then line=T("Kein Standort hinterlegt.","No location set.")
elseif st=="loading" then line=T("Wird geladen ...","Loading ...")
elseif st=="error" then line=T("Abruf fehlgeschlagen.","Fetch failed.")
else line=string.format(T("Gerade kein Flugzeug im Umkreis von %d km.","No aircraft within %d km right now."),radius) end
draw.text(W//2,H//2 - 8,line,"normal",fg,"center")
return
end
local farN,far=0,nil
for _,e in ipairs(ent) do
local a
for _,x in ipairs(ac.list) do
if x.hex==e.hex then a=x; break end
end
if not a then
far=far or (ac.far and ac.far.list or {})
for _,x in ipairs(far) do
if x.hex==e.hex then a=x; farN=farN+1; break end
end
end
if a and draw.image("sky"..e.idx,e.x,e.y) then
skyLabel(a,e,fg,dark and color.BLACK or color.WHITE,H)
end
end
if #ent==0 then
local a1=ac.list[1]
local want=a1 and a1.lv and skyFile(a1) or nil
draw.text(W//2,H//2 - 8,T("Kein Flugzeug mit Lackierung im Umkreis.","No aircraft with a livery image nearby."),"normal",fg,"center")
if want then draw.text(W//2,H//2+16,T("Fehlt auf dem Speicher: ","Missing on the storage: ")..want,"small",fg,"center") end
end
local foot
if ac.total==1 then foot=string.format(T("1 Flugzeug im Umkreis von %d km","1 aircraft within %d km"),radius)
else foot=string.format(T("%d Flugzeuge im Umkreis von %d km","%d aircraft within %d km"),ac.total,radius) end
if farN>0 then foot=foot..string.format(T("  ·  Suche erweitert bis %d km","  ·  search widened to %d km"),FAR_KM) end
draw.text(14,H - 10,foot,"small",fg)
end
local function state(ctx)
local loc=weather.location()
if not loc then return "noloc",nil,0 end
local radius=radiusOf(ctx.cfg)
local key=keyOf(loc,radius)
local ac,fail=loadAc()
if ac then applyFeature(ctx,ac) end
local nowT=time.now()
local fresh=ac and ac.key==key and nowT~=nil and ac.at~=nil and nowT>=ac.at and nowT - ac.at<1800
if fail and fail.key==key and not fresh then return "error",{msg=fail.msg},radius end
if not ac or ac.key~=key then return "loading",nil,radius end
ac.radius=radius
if #ac.list==0 then return "empty",ac,radius end
return "ok",ac,radius
end
function on_draw(ctx,page)
EN=ctx.lang=="en"
SHP=nil
EXTRAS=ctx.cfg.details~=false or ctx.preview==true
draw.clear(color.WHITE)
local st,ac,radius=state(ctx)
skyPage(ctx,st,ac,radius)
end
local function sampleAc()
return {total=3,radius=25,list={{hex="3c6444",cs="DLH123",reg="D-AIZZ",tc="A20N",desc="AIRBUS A-320neo",
air="Lufthansa",lat=53.6,lon=10.0,gnd=false,alt=11000,gs=430,trk=70,dist=7.4,brg=225,grp="a320neo",lv=true,
ia="lh",tl="Y"}}}
end
function on_widget(ctx,box)
EN=ctx.lang=="en"
local st,ac,radius=state(ctx)
local sample=false
if st~="ok" and st~="empty" and ctx.sample then st,ac,radius,sample="ok",sampleAc(),25,true end
local textX,textW,top=box.x+12,math.max(20,box.w - 24),box.y
if st~="ok" and st~="empty" then
draw.text(box.x+12,top+16,fit(T("Noch keine Daten","No data yet"),box.w - 20,"small"),"small",color.BLACK)
return
end
local maxY=box.y+box.h - 4
if st=="empty" then
draw.text(textX,top+12,T("FLUGRADAR","FLIGHT RADAR"),"small",color.ACCENT_TEXT)
draw.text(textX,top+44,fit(T("Freier Himmel","Clear skies"),textW,"large"),"large",color.GREEN)
if top+44+16<=maxY then
draw.text(textX,top+60,fit(string.format(T("im Umkreis von %d km","within %d km"),radius),textW,"small"),"small",color.BLACK)
end
return
end
local a=ac.list[1]
local fh=box.fh or box.h
draw.text(textX,top+12,fit(T("FLUG","FLIGHT").." · "..nameOf(a),textW,"small"),"small",color.ACCENT_TEXT)
local from,to
if sample then from,to="HAM","PMI" else from,to=routeOf(ctx,a) end
local statusY=top+44
if from then
arrowRoute(textX,statusY,from,to,"large",8,26,5,box.x+box.w - 12)
else
draw.text(textX,statusY,fit(a.desc~="" and a.desc or (a.tc~="" and a.tc or "-"),textW,"large"),"large",color.BLACK)
end
local y=statusY+19+2
if fh>=92 and y<=maxY then
local altPart
if a.gnd then altPart=T("am Boden","on ground") elseif a.alt>=0 then altPart=rnd(a.alt*0.3048).." m" else altPart="-" end
local detail=altPart
if from then detail=(a.desc~="" and a.desc or (a.tc~="" and a.tc or "-")).." · "..altPart end
draw.text(textX,y,fit(detail,textW,"small"),"small",color.BLACK)
y=y+19
end
if fh>=140 and y<=maxY then
local dist=a.dist<10 and string.format("%.1f km",a.dist) or (rnd(a.dist).." km")
local line
if a.gs>=0 then line=string.format(T("%s · aus %s · %d km/h","%s · from %s · %d km/h"),dist,compass(a.brg),rnd(a.gs*1.852))
else line=string.format(T("%s · aus %s","%s · from %s"),dist,compass(a.brg)) end
draw.text(textX,y,fit(line,textW,"small"),"small",color.BLACK)
y=y+19
if ctx.cfg.wAirline==true and y<=maxY and (a.air~="" or a.reg~="") then
local op=a.air~="" and a.reg~="" and (a.air.." · "..a.reg) or (a.air~="" and a.air or a.reg)
draw.text(textX,y,fit(op,textW,"small"),"small",color.BLACK)
end
end
end
