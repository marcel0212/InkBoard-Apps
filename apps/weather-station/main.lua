local outdoor={}
local indoor={}
do
local DAYS_DE={"Sonntag","Montag","Dienstag","Mittwoch","Donnerstag","Freitag","Samstag"}
local DAYS_EN={"Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"}
local SHORT_DE={"Mo","Di","Mi","Do","Fr","Sa","So"}
local SHORT_EN={"Mon","Tue","Wed","Thu","Fri","Sat","Sun"}
local MONTHS_DE={"Januar","Februar","März","April","Mai","Juni","Juli","August","September","Oktober","November","Dezember"}
local MONTHS_EN={"January","February","March","April","May","June","July","August","September","October","November","December"}
local W=(draw and draw.width) or 800
local CARD_MARGIN=14
local CARD_RADIUS=8
local ICON_STYLE=nil
local ICON_IDS={classic=0,ink=1,sketch=2,watercolor=3,crayon=4}
local LUA_ICONS=false
local wxSetBudget,wxDrawStyled
local function setIconStyle(name)
ICON_STYLE=ICON_IDS[name]
LUA_ICONS=false
local w=weather.get()
if w and w.icon_style==nil and ICON_STYLE and ICON_STYLE>=1 then
LUA_ICONS=true
wxSetBudget(260)
end
end
do
local wxBudget=0
local wxFloor,wxCeil,wxSqrt,wxAbs=math.floor,math.ceil,math.sqrt,math.abs
local function wxP(size,p)
local v=size*p+(p>=0 and 50 or -50)
if v>=0 then return v//100 end
return -((-v)//100)
end
local function wxDiv(a,b)
local q=wxAbs(a)//wxAbs(b)
if (a<0)~=(b<0) then q=-q end
return q
end
local function wxDot(x,y,c) draw.rect(x,y,1,1,c,true) end
local function wxSpan(x0,x1,y,c) if x1>=x0 then draw.rect(x0,y,x1 - x0+1,1,c,true) end end
local function wxOn(x,y,level)
local m
if y%2==0 then m=(x%2==0) and 0 or 2 else m=(x%2==0) and 3 or 1 end
return level>m
end
local function wxPatSpan(x0,x1,y,level,c)
if level>=4 then wxSpan(x0,x1,y,c) return end
if level<=0 then return end
for x=x0,x1 do if wxOn(x,y,level) then wxDot(x,y,c) end end
end
local function wxMinus(a,b,c,d,y,col)
if not a then return end
if not c or d<a or c>b then wxSpan(a,b,y,col) return end
wxSpan(a,c - 1,y,col)
wxSpan(d+1,b,y,col)
end
local function wxPrimIv(p,sy)
if p[1]=="c" then
local dy=sy - (p[3]+0.5)
local d=p[4]*p[4] - dy*dy
if d<0 then return nil end
local h=wxSqrt(d)
return p[2]+0.5 - h,p[2]+0.5+h
end
local dy=wxAbs(sy - (p[3]+0.5))
local half
if dy<=p[5] then half=p[4]+p[6]
else
local dd=dy - p[5]
if dd>p[6] then return nil end
half=p[4]+wxSqrt(p[6]*p[6] - dd*dd)
end
return p[2]+0.5 - half,p[2]+0.5+half
end
local function wxMerge(list)
table.sort(list,function(a,b) return a[1]<b[1] end)
local out,m={},0
for i=1,#list do
local s=list[i]
if m>0 and s[1]<=out[m][2] then
if s[2]>out[m][2] then out[m][2]=s[2] end
else m=m+1; out[m]={s[1],s[2]} end
end
return out
end
local function wxShapeIv(shape,sy)
local list={}
for _,p in ipairs(shape.add) do
local l,r=wxPrimIv(p,sy)
if l then list[#list+1]={l,r} end
end
local add=wxMerge(list)
if not shape.sub then return add end
local sl={}
for _,p in ipairs(shape.sub) do
local l,r=wxPrimIv(p,sy)
if l then sl[#sl+1]={l,r} end
end
if #sl==0 then return add end
sl=wxMerge(sl)
local out={}
for _,a in ipairs(add) do
local l=a[1]
for _,s in ipairs(sl) do
if s[2]>=l and s[1]<=a[2] then
if s[1]>l then out[#out+1]={l,s[1]} end
l=s[2]
end
end
if l<a[2] then out[#out+1]={l,a[2]} end
end
return out
end
local function wxCovAt(I1,I2,x)
local c=0
for k=1,2 do
local I=k==1 and I1 or I2
for _,iv in ipairs(I) do
if x+0.25>=iv[1] and x+0.25<=iv[2] then c=c+1 end
if x+0.75>=iv[1] and x+0.75<=iv[2] then c=c+1 end
end
end
return c
end
local function wxSegs(shape,y)
local I1,I2=wxShapeIv(shape,y+0.25),wxShapeIv(shape,y+0.75)
local set,list={},{}
for k=1,2 do
for _,iv in ipairs(k==1 and I1 or I2) do
for e=1,2 do
local u=wxFloor(iv[e])
if not set[u] then set[u]=true; list[#list+1]=u end
end
end
end
local segs,m={},0
if #list==0 then return segs end
table.sort(list)
local function push(a,b,c)
if c<=0 then return end
if m>0 and segs[m][2]==a - 1 and segs[m][3]==c then segs[m][2]=b
else m=m+1; segs[m]={a,b,c} end
end
for i=1,#list do
local u=list[i]
push(u,u,wxCovAt(I1,I2,u))
local nx=list[i+1]
if nx and nx>u+1 then push(u+1,nx - 1,wxCovAt(I1,I2,u+1)) end
end
return segs
end
local function wxSweep(A,B,fn)
local bp,seen={},{}
for _,L in ipairs({A,B}) do
for _,s in ipairs(L) do
if not seen[s[1]] then seen[s[1]]=true; bp[#bp+1]=s[1] end
if not seen[s[2]+1] then seen[s[2]+1]=true; bp[#bp+1]=s[2]+1 end
end
end
table.sort(bp)
local ia,ib=1,1
for i=1,#bp - 1 do
local p,q=bp[i],bp[i+1] - 1
while A[ia] and A[ia][2]<p do ia=ia+1 end
while B[ib] and B[ib][2]<p do ib=ib+1 end
local ca=(A[ia] and A[ia][1]<=p) and A[ia][3] or 0
local cb=(B[ib] and B[ib][1]<=p) and B[ib][3] or 0
if ca>0 or cb>0 then fn(p,q,ca,cb) end
end
end
local function wxInk(p,q,y,ink,c)
if ink>=4 then wxSpan(p,q,y,c) elseif ink>0 then wxPatSpan(p,q,y,ink,c) end
end
local function wxCircShape(cx,cy,r) return {add={{"c",cx,cy,r+0.5}}} end
local function wxCloudGeom(cx,cy,w)
local X,Y,R={-25,-4,23},{8,-5,8},{17,24,18}
local g={cxs={},cys={},rs={}}
for i=1,3 do
g.cxs[i]=cx+wxP(w,X[i]); g.cys[i]=cy+wxP(w,Y[i]); g.rs[i]=wxP(w,R[i])
end
local bx,by,bw,bh=cx+wxP(w,-42),cy+wxP(w,2),wxP(w,84),wxP(w,26)
g.br=wxP(w,13)
g.rcx=bx+bw//2; g.rcy=by+bh//2
g.hx=bw//2 - g.br; g.hy=bh//2 - g.br
g.y0=cy+wxP(w,-29); g.y1=by+bh
return g
end
local function wxCloudShape(g,e)
local add={}
for i=1,3 do add[i]={"c",g.cxs[i],g.cys[i],g.rs[i]+e+0.5} end
add[4]={"r",g.rcx,g.rcy,g.hx,g.hy,g.br+e+0.5}
return {add=add}
end
local function wxCloudSt(cx,cy,w,kind,level,flatCol,t,ring)
local g=wxCloudGeom(cx,cy,w)
local outl=(kind==2 or kind==4)
local ext=(outl and t or 0)+ring+1
local K,Wh=color.BLACK,color.WHITE
local sR=ring>0 and wxCloudShape(g,ring) or nil
local sT=outl and wxCloudShape(g,t) or nil
local s0=wxCloudShape(g,0)
for y=g.y0 - ext,g.y1+ext do
if sR then
for _,s in ipairs(wxSegs(sR,y)) do if s[3]>=2 then wxSpan(s[1],s[2],y,Wh) end end
end
if outl then
wxSweep(wxSegs(sT,y),wxSegs(s0,y),function(p,q,ca,cb)
if ca<=0 then return end
wxSpan(p,q,y,Wh)
if cb<4 then wxInk(p,q,y,ca - cb,K) end
end)
else
local col=(kind==1) and K or flatCol
for _,s in ipairs(wxSegs(s0,y)) do
local eff=(kind==1 and level>=5) and s[3] or math.min(level,s[3])
wxInk(s[1],s[2],y,eff,col)
end
end
end
end
local function wxStroke(x0,y0,x1,y1,wd,c)
local n=math.max(wxAbs(x1 - x0),wxAbs(y1 - y0))
local h=wd//2
for i=0,n do
local xx=n>0 and x0+wxDiv((x1 - x0)*i,n) or x0
local yy=n>0 and y0+wxDiv((y1 - y0)*i,n) or y0
draw.rect(xx - h,yy - h,wd,wd,c,true)
end
end
local function wxStrokePat(x0,y0,x1,y1,wd,level,c)
local n=math.max(wxAbs(x1 - x0),wxAbs(y1 - y0))
local h=wd//2
local seen={}
for i=0,n do
local xx=n>0 and x0+wxDiv((x1 - x0)*i,n) or x0
local yy=n>0 and y0+wxDiv((y1 - y0)*i,n) or y0
for dy=0,wd - 1 do
for dx=0,wd - 1 do
local px,py=xx - h+dx,yy - h+dy
local key=py*4096+px
if not seen[key] then
seen[key]=true
if wxOn(px,py,level) then wxDot(px,py,c) end
end
end
end
end
end
local function wxFillPoly(px,py,n,colA,colB)
local y0,y1=py[1],py[1]
for i=2,n do
if py[i]<y0 then y0=py[i] end
if py[i]>y1 then y1=py[i] end
end
for y=y0,y1 do
local xs,m={},0
for i=1,n do
local j=i%n+1
local ax,ay,bx,by=px[i],py[i],px[j],py[j]
if ay~=by then
if ay>by then ax,bx=bx,ax; ay,by=by,ay end
if y>=ay and y<by then m=m+1; xs[m]=ax+wxDiv((bx - ax)*(y - ay),by - ay) end
end
end
table.sort(xs)
for a=1,m - 1,2 do
if colB then
for x=xs[a],xs[a+1] do wxDot(x,y,((x+y)%2==1) and colB or colA) end
else wxSpan(xs[a],xs[a+1],y,colA) end
end
end
end
local function wxStarC(x,y,s,c,dither)
if dither then
local w=math.max(1,s*2//5)
wxFillPoly({x,x+w,x+s,x+w,x,x - w,x - s,x - w},{y - s,y - w,y,y+w,y+s,y+w,y,y - w},8,c,color.WHITE)
draw.rect(x - s,y,2*s+1,1,c,true)
draw.rect(x,y - s,1,2*s+1,c,true)
return
end
local w=math.max(1,s//2)
draw.triangle(x - w,y,x+w,y,x,y - s,c,true)
draw.triangle(x - w,y,x+w,y,x,y+s,c,true)
draw.triangle(x,y - w,x,y+w,x - s,y,c,true)
draw.triangle(x,y - w,x,y+w,x+s,y,c,true)
end
local function wxSunSt(x,y,r,mask,kind,sw,discLevel)
discLevel=discLevel or 4
local col=(kind>=3) and color.YELLOW or color.BLACK
local gap=math.max(2,r*4//10)
local len=math.max(3,r*8//10)
local dxs,dys={0,10,0,-10,7,7,-7,-7},{-10,0,10,0,-7,7,7,-7}
for i=0,7 do
if (mask>>i) & 1==1 then
local a=r+gap
local o=a+(i<4 and len or len*8//10)
wxStroke(x+wxDiv(dxs[i+1]*a,10),y+wxDiv(dys[i+1]*a,10),x+wxDiv(dxs[i+1]*o,10),y+wxDiv(dys[i+1]*o,10),sw,col)
end
end
local solid=(kind==1 or kind==3)
local rin=math.max(r - sw,0)
local so=wxCircShape(x,y,r)
local si=(not solid and rin>0) and wxCircShape(x,y,rin) or nil
for py=y - r - 1,y+r+1 do
local A=wxSegs(so,py)
if solid then
for _,s in ipairs(A) do wxInk(s[1],s[2],py,math.min(s[3],discLevel),col) end
else
wxSweep(A,si and wxSegs(si,py) or {},function(p,q,ca,cb)
if cb==4 then wxSpan(p,q,py,color.WHITE)
elseif ca>0 then wxInk(p,q,py,ca - cb,col) end
end)
end
end
end
local function wxMoonSt(x,y,r,cdx,cdy,rc,fillCol,borderCol,b)
local cx2,cy2=x+cdx,y+cdy
local sF={add={{"c",x,y,r+0.5}},sub={{"c",cx2,cy2,rc+0.5}}}
local sB={add={{"c",x,y,r+b+0.5}},sub={{"c",cx2,cy2,rc - b+0.5}}}
for py=y - r - b - 1,y+r+b+1 do
wxSweep(wxSegs(b>0 and sB or sF,py),wxSegs(sF,py),function(p,q,ca,cf)
if cf==4 then wxSpan(p,q,py,fillCol)
elseif b>0 then
local ink=ca - cf
if ink>=4 then wxSpan(p,q,py,borderCol)
elseif ink>0 then wxSpan(p,q,py,color.WHITE); wxPatSpan(p,q,py,ink,borderCol)
elseif cf>0 then wxSpan(p,q,py,fillCol) end
elseif cf>0 then wxPatSpan(p,q,py,cf,fillCol) end
end)
end
end
local function wxBoltSt(x,y,h,outer,inner,b,inner2)
local bx,by={2,11,4,11,-7,-2,-9},{-15,-15,-3,-3,16,3,3}
local ox,oy={-1,0,1,-1,1,-1,0,1},{-1,-1,-1,0,0,1,1,1}
for pass=0,1 do
for k=1,(pass==0 and 8 or 1) do
local px,py={},{}
for i=1,7 do
px[i]=x+wxDiv(bx[i]*h,32)+(pass==0 and ox[k]*b or 0)
py[i]=y+wxDiv(by[i]*h,32)+(pass==0 and oy[k]*b or 0)
end
if pass==1 and inner2~=inner then wxFillPoly(px,py,7,inner,inner2)
else wxFillPoly(px,py,7,pass==0 and outer or inner) end
end
end
end
local function wxFlakeSt(x,y,fr,kind,sw,c)
local k,h=fr*87//100,fr//2
if kind==1 or kind==3 then
local d=fr*7//10
if kind==1 then
wxStrokePat(x - d,y - d,x+d,y+d,sw+2,3,c)
wxStrokePat(x - d,y+d,x+d,y - d,sw+2,3,c)
else
wxStroke(x - d,y - d,x+d,y+d,sw,c)
wxStroke(x - d,y+d,x+d,y - d,sw,c)
end
else
wxStroke(x,y - fr,x,y+fr,sw,c)
wxStroke(x - k,y - h,x+k,y+h,sw,c)
wxStroke(x - k,y+h,x+k,y - h,sw,c)
end
end
local function wxCapsule(x0,y0,x1,y1,r,c)
if r<=2 then
local n=math.max(wxAbs(x1 - x0),wxAbs(y1 - y0))
for i=0,n do
local xx=n>0 and x0+wxDiv((x1 - x0)*i,n) or x0
local yy=n>0 and y0+wxDiv((y1 - y0)*i,n) or y0
if r==0 then wxDot(xx,yy,c) else draw.circle(xx,yy,r,c,true) end
end
return
end
draw.circle(x0,y0,r,c,true)
draw.circle(x1,y1,r,c,true)
local dx,dy=x1 - x0,y1 - y0
local len=wxFloor(wxSqrt(dx*dx+dy*dy))
if len==0 then return end
local nx,ny=wxDiv(-dy*r,len),wxDiv(dx*r,len)
draw.triangle(x0+nx,y0+ny,x0 - nx,y0 - ny,x1+nx,y1+ny,c,true)
draw.triangle(x1+nx,y1+ny,x1 - nx,y1 - ny,x0 - nx,y0 - ny,c,true)
end
local function wxClassicCloud(cx,cy,size)
local b=size>=90 and 4 or (size>=56 and 3 or 2)
local cL,cLy,rL=cx+wxP(size,-25),cy+wxP(size,8),wxP(size,17)
local cM,cMy,rM=cx+wxP(size,-4),cy+wxP(size,-5),wxP(size,24)
local cR,cRy,rR=cx+wxP(size,23),cy+wxP(size,8),wxP(size,18)
local bx,by,bw,bh,br=cx+wxP(size,-42),cy+wxP(size,2),wxP(size,84),wxP(size,26),wxP(size,13)
local K,Wh=color.BLACK,color.WHITE
draw.circle(cL,cLy,rL+b,K,true); draw.circle(cM,cMy,rM+b,K,true); draw.circle(cR,cRy,rR+b,K,true)
draw.rect(bx - b,by - b,bw+2*b,bh+2*b,K,true,br+b)
draw.circle(cL,cLy,rL,Wh,true); draw.circle(cM,cMy,rM,Wh,true); draw.circle(cR,cRy,rR,Wh,true)
draw.rect(bx,by,bw,bh,Wh,true,br)
end
local function wxClassicSun(x,y,r,size,mask)
local ow=size>=90 and 4 or (size>=56 and 3 or 2)
local b=ow>2 and ow - 1 or 2
local t=size>=90 and 3 or (size>=48 and 2 or 1)
local gap=math.max(2,r//3)
local len=math.max(3,r*2//3)
local dxs,dys={0,1,0,-1,7,7,-7,-7},{-1,0,1,0,-7,7,7,-7}
for i=0,7 do
if (mask>>i) & 1==1 then
local ux=i<4 and dxs[i+1]*10 or dxs[i+1]
local uy=i<4 and dys[i+1]*10 or dys[i+1]
local a=r+b+gap
local o=a+(i<4 and len or len*8//10)
wxCapsule(x+wxDiv(ux*a,10),y+wxDiv(uy*a,10),x+wxDiv(ux*o,10),y+wxDiv(uy*o,10),t,color.BLACK)
end
end
draw.circle(x,y,r+b,color.BLACK,true)
draw.circle(x,y,r,color.YELLOW,true)
end
local function wxClassicBolt(x,y,h)
local bx,by={2,11,4,11,-7,-2,-9},{-15,-15,-3,-3,16,3,3}
local b=h>=52 and 2 or 1
local ox,oy={-1,0,1,-1,1,-1,0,1},{-1,-1,-1,0,0,1,1,1}
for pass=0,1 do
for k=1,(pass==0 and 8 or 1) do
local px,py={},{}
for i=1,7 do
px[i]=x+wxDiv(bx[i]*h,32)+(pass==0 and ox[k]*b or 0)
py[i]=y+wxDiv(by[i]*h,32)+(pass==0 and oy[k]*b or 0)
end
wxFillPoly(px,py,7,pass==0 and color.BLACK or color.YELLOW)
end
end
end
local function wxClassicMoon(x,y,r,cdx,cdy,rc,b)
local cx2,cy2=x+cdx,y+cdy
local function iv(cx,cy,rr,py)
if rr<0 then return nil end
local d=rr*rr - (py - cy)*(py - cy)
if d<0 then return nil end
local h=wxFloor(wxSqrt(d))
return cx - h,cx+h
end
local function cut(cx,cy,rr,py)
return iv(cx,cy,rr,py)
end
for py=y - r - b,y+r+b do
local a,bb=iv(x,y,r+b,py)
local c,d=cut(cx2,cy2,rc - b,py)
wxMinus(a,bb,c,d,py,color.BLACK)
a,bb=iv(x,y,r,py)
c,d=cut(cx2,cy2,rc,py)
wxMinus(a,bb,c,d,py,color.YELLOW)
end
end
local function wxDrawClassic(cond,cx,cy,size)
local function P(p) return wxP(size,p) end
local K,Bl,Y=color.BLACK,color.BLUE,color.YELLOW
if cond==0 then wxClassicSun(cx,cy,P(22),size,0xFF)
elseif cond==1 then
wxClassicSun(cx+P(14),cy+P(-16),P(17),size,0x01 | 0x02 | 0x10 | 0x80 | 0x20)
wxClassicCloud(cx+P(-4),cy+P(10),size*80//100)
elseif cond==2 then wxClassicCloud(cx,cy,size*95//100)
elseif cond==3 then
wxClassicCloud(cx,cy+P(-16),size*78//100)
local th=math.max(P(5),2)
local ys,xl,xr={P(17),P(29),P(41)},{P(-34),P(-26),P(-34)},{P(34),P(30),P(34)}
for i=1,3 do wxCapsule(cx+xl[i],cy+ys[i],cx+xr[i],cy+ys[i],math.max(th//2,1),K) end
elseif cond==4 or cond==5 then
local heavy=cond==5
wxClassicCloud(cx,cy+P(-15),size*94//100)
local r=math.max(P(4),1)
local len=heavy and P(22) or P(16)
local xs3,xs2={P(-22),P(0),P(22)},{P(-12),P(12)}
for i=1,(heavy and 3 or 2) do
local x,y=cx+(heavy and xs3[i] or xs2[i]),cy+P(23)+((i - 1)%2==1 and P(7) or 0)
wxCapsule(x+len//4,y,x - len//4,y+len,r,Bl)
end
elseif cond==6 then
wxClassicCloud(cx,cy+P(-15),size*94//100)
local fr=math.max(P(10),3)
for i=0,2 do
local x,y=cx+P(-22)+i*P(22),cy+P(35)+(i%2==1 and P(8) or 0)
local k,h=fr*87//100,fr//2
local rr=fr>=12 and 2 or (fr>=6 and 1 or 0)
wxCapsule(x,y - fr,x,y+fr,rr,Bl)
wxCapsule(x - k,y - h,x+k,y+h,rr,Bl)
wxCapsule(x - k,y+h,x+k,y - h,rr,Bl)
end
elseif cond==7 then
wxClassicCloud(cx,cy+P(-16),size*94//100)
wxClassicBolt(cx+P(2),cy+P(31),P(52))
elseif cond==9 then
wxClassicCloud(cx,cy+P(-15),size*94//100)
local r=math.max(P(6),2)
for i=0,2 do
local x,y=cx+P(-20)+i*P(20),cy+P(31)+(i%2==1 and P(9) or 0)
draw.circle(x,y,r+1,K,true)
draw.circle(x,y,r>2 and r - 1 or r,Bl,true)
end
elseif cond==10 then
local ow=size>=90 and 4 or (size>=56 and 3 or 2)
wxClassicMoon(cx+P(-4),cy+P(2),P(30),P(15),P(-11),P(25),ow>2 and ow - 1 or 2)
wxStarC(cx+P(24),cy+P(-24),math.max(P(11),2),K,false)
wxStarC(cx+P(32),cy+P(6),math.max(P(6),1),K,false)
if size>=40 then wxStarC(cx+P(12),cy+P(34),P(6),K,false) end
else
local ow=size>=90 and 4 or (size>=56 and 3 or 2)
wxClassicMoon(cx+P(12),cy+P(-15),P(21),P(10),P(-8),P(18),ow>2 and ow - 1 or 2)
if size>=40 then wxStarC(cx+P(-22),cy+P(-30),P(7),K,false) end
wxClassicCloud(cx+P(-4),cy+P(10),size*80//100)
end
end
local WX_CONDS={clear=0,partly=1,cloudy=2,fog=3,drizzle=4,rain=5,snow=6,thunder=7,hail=9,clear_night=10,partly_night=11}
wxDrawStyled=function(condName,cx,cy,size,night,kind)
if type(condName)~="string" then return false end
if night then
if condName=="clear" then condName="clear_night" elseif condName=="partly" then condName="partly_night" end
end
local cond=WX_CONDS[condName]
if not cond then return false end
if size<8 then size=8 end
if wxBudget<size then return false end
wxBudget=wxBudget - size
if kind==0 then wxDrawClassic(cond,cx,cy,size) return true end
local function P(p) return wxP(size,p) end
local outl=(kind==2 or kind==4)
local dith=(kind==1 or kind==3) and size>=56
local sw=size>=100 and 3 or (size>=56 and 2 or 1)
local gap=size>=100 and 4 or (size>=56 and 3 or 2)
local t=outl and sw or 0
local ring=outl and (t+gap - 1) or gap
local K,Wh,Y,Bl=color.BLACK,color.WHITE,color.YELLOW,color.BLUE
local pc=(kind>=3) and Bl or K
local yc=(kind>=3) and Y or K
local function cloud(x,y,w,kindLevel,rg)
local level=(kindLevel==1) and 1 or 2
if kind==3 then level=(kindLevel==0) and 4 or ((kindLevel==1) and 2 or 3) end
local col=(kindLevel==2) and K or Bl
if kind==1 then level=(kindLevel==1) and 2 or 5 end
wxCloudSt(x,y,w,kind,level,col,t,rg)
end
local function drops(n,y0,len)
local x3,x2={-22,0,22},{-12,12}
for i=1,n do
local x=cx+P(n==3 and x3[i] or x2[i])
local y=cy+y0+((i - 1)%2==1 and P(7) or 0)
if dith then wxStrokePat(x+len//4,y,x - len//4,y+len,sw+1,3,pc)
else wxStroke(x+len//4,y,x - len//4,y+len,size<56 and sw+1 or sw,pc) end
end
end
if cond==0 then
wxSunSt(cx,cy,P(21),0xFF,kind,sw)
elseif cond==1 then
wxSunSt(cx+P(15),cy+P(-17),P(16),0x01 | 0x02 | 0x10 | 0x80 | 0x20,kind,sw,kind==1 and 2 or 4)
cloud(cx+P(-4),cy+P(10),size*82//100,0,ring)
elseif cond==2 then
cloud(cx+P(17),cy+P(-12),size*62//100,1,0)
cloud(cx+P(-8),cy+P(9),size*84//100,0,ring)
elseif cond==3 then
cloud(cx,cy+P(-15),size*80//100,0,0)
local ys,xl,xr={P(18),P(29),P(40)},{P(-32),P(-24),P(-32)},{P(32),P(28),P(32)}
for i=1,3 do
if dith then wxStrokePat(cx+xl[i],cy+ys[i],cx+xr[i],cy+ys[i],sw+1,3,pc)
else wxStroke(cx+xl[i],cy+ys[i],cx+xr[i],cy+ys[i],size<56 and sw+1 or sw,pc) end
end
elseif cond==4 then
cloud(cx,cy+P(-14),size*90//100,0,0)
drops(2,P(24),P(14))
elseif cond==5 then
cloud(cx,cy+P(-14),size*90//100,0,0)
drops(3,P(24),P(20))
elseif cond==6 then
cloud(cx,cy+P(-14),size*90//100,0,0)
local fr=math.max(3,P(8))
for i=0,2 do wxFlakeSt(cx+P(-22)+i*P(22),cy+P(33)+(i%2==1 and P(9) or 0),fr,kind,sw,pc) end
elseif cond==7 then
cloud(cx,cy+P(-16),size*90//100,kind==3 and 2 or 0,0)
local b=outl and (sw>1 and sw - 1 or 1) or gap
local outer=(kind==1 and Wh) or (kind==2 and K) or (kind==3 and Wh) or Y
local inner=(kind==1 and K) or (kind==2 and Wh) or (kind==3 and Y) or Wh
wxBoltSt(cx+P(2),cy+P(30),P(50),outer,inner,b,kind==1 and Y or inner)
elseif cond==9 then
cloud(cx,cy+P(-14),size*90//100,0,0)
local r=math.max(1,P(4))
for i=0,2 do draw.circle(cx+P(-20)+i*P(20),cy+P(32)+(i%2==1 and P(9) or 0),r,pc,true) end
elseif cond==10 then
local r=P(30)
if kind==1 then wxMoonSt(cx+P(-4),cy+P(2),r,P(15),P(-11),P(25),K,K,0)
elseif kind==3 then wxMoonSt(cx+P(-4),cy+P(2),r,P(15),P(-11),P(25),Y,Y,0)
else wxMoonSt(cx+P(-4),cy+P(2),r,P(15),P(-11),P(25),Wh,kind==2 and K or Y,sw) end
wxStarC(cx+P(26),cy+P(-24),math.max(2,P(10)),yc,dith and size>=40)
if size>=40 then wxStarC(cx+P(33),cy+P(6),P(6),yc,dith) end
else
local r,mx,my=P(22),cx+P(17),cy+P(-18)
if kind==1 then wxMoonSt(mx,my,r,P(11),P(-9),P(19),K,K,0)
elseif kind==3 then wxMoonSt(mx,my,r,P(11),P(-9),P(19),Y,Y,0)
else wxMoonSt(mx,my,r,P(11),P(-9),P(19),Wh,kind==2 and K or Y,sw) end
cloud(cx+P(-4),cy+P(10),size*82//100,0,ring)
end
return true
end
wxSetBudget=function(n) wxBudget=n end
end
local function wxIcon(cond,cx,cy,size,night)
if LUA_ICONS and wxDrawStyled(cond,cx,cy,size,night,ICON_STYLE) then return end
return draw.weather_icon(cond,cx,cy,size,night,ICON_STYLE)
end
local function wxIconBox(cond,cx,top,bottom,maxSize,night)
local h=bottom - top
local size=math.min(maxSize,(h*100)//112)
if size<8 then size=8 end
local cy=top+(h - size*112//100)//2+size*55//100
wxIcon(cond,cx,cy,size,night)
end
local function tr(en,de,ctx) if ctx.lang=="en" then return en end return de end
local function accentCard(x,y,w,h)
draw.rect(x,y,w,h,color.WHITE,true,CARD_RADIUS)
draw.rect(x,y,w,h,color.BLACK,false,CARD_RADIUS)
draw.rect(x+6,y+6,5,h - 12,color.ACCENT,true,2)
end
local function hline(x,y,w)
draw.rect(x,y,w,1,color.BLACK,true)
end
local function thickLine(x0,y0,x1,y1,col)
draw.line(x0,y0,x1,y1,col)
draw.line(x0,y0+1,x1,y1+1,col)
draw.line(x0+1,y0,x1+1,y1,col)
draw.line(x0,y0 - 1,x1,y1 - 1,col)
draw.line(x0 - 1,y0,x1 - 1,y1,col)
end
local function catmull(p0,p1,p2,p3,t)
local t2,t3=t*t,t*t*t
return 0.5*((2*p1)+(-p0+p2)*t+(2*p0 - 5*p1+4*p2 - p3)*t2+(-p0+3*p1 - 3*p2+p3)*t3)
end
local function round(v) return math.floor(v+0.5) end
local function sparkline(x,y,w,h,vals,col)
local n=#vals
if n<2 then return end
local minV,maxV=vals[1],vals[1]
for i=2,n do
if vals[i]<minV then minV=vals[i] end
if vals[i]>maxV then maxV=vals[i] end
end
local range=maxV - minV
if range<0.5 then range=0.5 end
local function xAt(idx) return x+idx*(w - 1)/(n - 1) end
local function yAt(v) return y+h - 1 - (v - minV)/range*(h - 1) end
local px,py=xAt(0),yAt(vals[1])
for i=1,n - 1 do
local p0=vals[i>1 and i - 1 or i]
local p1=vals[i]
local p2=vals[i+1]
local p3=vals[i+2<=n and i+2 or i+1]
for s=1,4 do
local t=s/4
local nx,ny=xAt(i - 1+t),yAt(catmull(p0,p1,p2,p3,t))
thickLine(round(px),round(py),round(nx),round(ny),col)
px,py=nx,ny
end
end
end
local function notice(cx,y,kind,line1,line2)
local r=22
local cy=y+r
if kind=="loading" then
for i=0,2 do draw.circle(cx,cy,r - i,color.BLACK,false) end
for i=-1,1 do draw.circle(cx+i*12,cy,3,color.BLACK,true) end
else
draw.circle(cx,cy,r,color.BLUE,true)
draw.text(cx,cy+7,"?","large",color.WHITE,"center")
end
local y1=cy+r+32
draw.text(cx,y1,line1,"large",color.BLACK,"center")
if line2 and line2~="" then draw.text(cx,y1+26,line2,"normal",color.BLACK,"center") end
end
local function aqColor(aqi)
if aqi==1 then return color.GREEN end
if aqi==2 or aqi==3 then return color.YELLOW end
if aqi==4 or aqi==5 then return color.RED end
return color.BLACK
end
local function fmtTime(min)
return string.format("%02d:%02d",min//60,min%60)
end
local function facts(w,ctx)
local dash="-"
local vis=dash
if w.visibility then
vis=(w.visibility>=10) and ">10.0 km" or string.format("%.1f km",w.visibility)
end
return {
sunrise=w.sunrise and fmtTime(w.sunrise) or dash,
sunset=w.sunset and fmtTime(w.sunset) or dash,
wind=w.wind and string.format("%.0f km/h",w.wind) or dash,
hum=string.format("%d %%",w.humidity or 0),
press=w.pressure and string.format("%d hPa",w.pressure) or dash,
uv=w.uv and string.format("%.1f",w.uv) or dash,
vis=vis,
}
end
local function factCell(x,y,label,value)
draw.text(x,y,label,"small",color.BLACK)
draw.text(x,y+18,value,"normal",color.BLACK)
end
local function factGrid(w,ctx,x0,colGap,right,rowH,y0,aqDy)
local f=facts(w,ctx)
local colW=(W - right - x0 - colGap)//2
local x1=x0+colW+colGap
factCell(x0,y0,tr("Sunrise","Sonnenaufgang",ctx),f.sunrise)
factCell(x1,y0,tr("Sunset","Sonnenuntergang",ctx),f.sunset)
factCell(x0,y0+rowH,"Wind",f.wind)
factCell(x1,y0+rowH,tr("Humidity","Feuchte",ctx),f.hum)
factCell(x0,y0+rowH*2,tr("Pressure","Luftdruck",ctx),f.press)
factCell(x1,y0+rowH*2,tr("UV index","UV-Index",ctx),f.uv)
factCell(x0,y0+rowH*3,tr("Visibility","Sichtweite",ctx),f.vis)
draw.text(x1,y0+rowH*3,tr("Air quality","Luftqualität",ctx),"small",color.BLACK)
draw.text(x1,y0+rowH*3+aqDy,w.aqi_label or "-","small",aqColor(w.aqi))
end
local function boundsOf(hourly)
local minV,maxV=hourly[1].temp,hourly[1].temp
for i=2,#hourly do
if hourly[i].temp<minV then minV=hourly[i].temp end
if hourly[i].temp>maxV then maxV=hourly[i].temp end
end
return minV,maxV
end
local function hourlyBlock(w,y,sparkXL,sparkXR,sparkH,labelX,maxDy,iconSize,iconDy,hourDy)
local n=#w.hourly
local sw=W - sparkXL - sparkXR
local temps={}
for i=1,n do temps[i]=w.hourly[i].temp end
sparkline(sparkXL,y,sw,sparkH,temps,color.ACCENT)
local minV,maxV=boundsOf(w.hourly)
draw.text(labelX,y+maxDy,string.format("%.0f°",maxV),"small",color.BLACK)
draw.text(labelX,y+sparkH,string.format("%.0f°",minV),"small",color.BLACK)
local step=n>12 and 4 or 2
local i=0
while i<n do
local px=sparkXL+(i*(sw - 1))//(n - 1)
wxIconBox(w.hourly[i+1].cond,px,y+sparkH - 2,y+sparkH+hourDy - 15,iconSize,w.hourly[i+1].night)
draw.text(px,y+sparkH+hourDy,string.format("%dh",w.hourly[i+1].hour),"normal",color.BLACK,"center")
i=i+step
end
end
local function dailyBlock(w,ctx,y,cardX,wdDy,iconSize,iconDy,tempDy)
local count=#w.daily
local rowW=W - 2*cardX
local gap=6
local colW=(rowW - (count - 1)*gap)//count
local short=(ctx.lang=="en") and SHORT_EN or SHORT_DE
for i=1,count do
local d=w.daily[i]
local cx=cardX+(i - 1)*(colW+gap)+colW//2
draw.text(cx,y+wdDy,short[((d.wday+6)%7)+1],"normal",color.BLACK,"center")
wxIconBox(d.cond,cx,y+wdDy+4,y+tempDy - 15,iconSize)
draw.text(cx,y+tempDy,string.format("%.0f°/%.0f°",d.max,d.min),"normal",color.BLACK,"center")
end
end
local function titleBlock(w,ctx,y,titleDy,dateDy)
local loc=(w.location and w.location~="") and w.location or tr("Location","Standort",ctx)
draw.text(W//2,y+titleDy,loc,"large",color.BLACK,"center")
local lt=time.localtime()
if lt then
local days=(ctx.lang=="en") and DAYS_EN or DAYS_DE
local months=(ctx.lang=="en") and MONTHS_EN or MONTHS_DE
draw.text(W//2,y+dateDy,string.format("%s, %s %d",days[lt.wday+1],months[lt.month],lt.day),"normal",color.BLACK,"center")
end
end
local function bigTemp(x,baseline,temp)
local digits=string.format("%.0f",temp)
draw.text(x,baseline,digits,"huge",color.BLACK)
local ux=x+draw.measure(digits,"huge")+4
draw.text(ux,baseline,"°C","large",color.BLACK)
end
local function feelsText(w,ctx)
return string.format(tr("feels like %.0f °C","gefühlt %.0f °C",ctx),w.feels)
end
local drawPortrait
local function drawBigStyle(w,ctx,flat)
if draw.height>draw.width then return drawPortrait(w,ctx,flat,false) end
local y=draw.top+2
titleBlock(w,ctx,y,20,38)
y=y+54
local factY=y
local factRowH=140
local cardW=W - 2*CARD_MARGIN
local function section(top,h)
if flat then hline(CARD_MARGIN,top,cardW) else accentCard(CARD_MARGIN,top,cardW,h) end
end
section(factY - 10,factRowH+20)
wxIcon(w.cond,104,factY+factRowH//2,112,w.night)
bigTemp(190,factY+69,w.temp)
draw.text(190,factY+90,feelsText(w,ctx),"normal",color.BLACK)
factGrid(w,ctx,345,20,26,34,factY+6,18)
y=factY+factRowH+26
if #w.hourly>=2 then
section(y - 10,102)
hourlyBlock(w,y,60,28,40,CARD_MARGIN+(flat and 8 or 18),8,24,17,38)
y=y+40+68
end
if #w.daily>0 then
section(y - 10,106)
dailyBlock(w,ctx,y,26,12,40,47,80)
else
notice(W//2,y,"loading",tr("Forecast is loading ...","Vorhersage wird geladen ...",ctx))
end
end
drawPortrait=function(w,ctx,flat,compact)
local y=draw.top+10
titleBlock(w,ctx,y,26,46)
y=y+70
local cardW=W - 2*CARD_MARGIN
local function section(top,h)
if flat then hline(CARD_MARGIN,top,cardW) else accentCard(CARD_MARGIN,top,cardW,h) end
end
local heroH=compact and 130 or 170
section(y - 6,heroH)
wxIcon(w.cond,compact and 80 or 92,y+heroH//2 - 8,compact and 82 or 104,w.night)
if compact then
draw.text(150,y+62,string.format("%.0f °C",w.temp),"large",color.BLACK)
draw.text(150,y+88,feelsText(w,ctx),"normal",color.BLACK)
else
bigTemp(160,y+92,w.temp)
draw.text(160,y+122,feelsText(w,ctx),"normal",color.BLACK)
end
y=y+heroH+22
local rowH=compact and 44 or 52
local fh=rowH*4+18
section(y - 10,fh)
factGrid(w,ctx,CARD_MARGIN+22,20,CARD_MARGIN+14,rowH,y+8,20)
y=y+fh+14
if #w.hourly>=2 then
section(y - 10,112)
hourlyBlock(w,y+4,60,28,44,CARD_MARGIN+14,8,24,17,42)
y=y+44+74
end
if #w.daily>0 then
section(y - 10,112)
local keep={}
for i=1,math.min(#w.daily,5) do keep[i]=w.daily[i] end
local w2={daily=keep}
dailyBlock(w2,ctx,y+2,22,14,40,49,84)
else
notice(W//2,y,"loading",tr("Forecast is loading ...","Vorhersage wird geladen ...",ctx))
end
end
local function drawCompact(w,ctx)
if draw.height>draw.width then return drawPortrait(w,ctx,false,true) end
local y=draw.top+2
titleBlock(w,ctx,y,18,34)
y=y+46
local factY=y
local factRowH=108
local cardW=W - 2*CARD_MARGIN
accentCard(CARD_MARGIN,factY - 8,cardW,factRowH+14)
wxIcon(w.cond,96,factY+factRowH//2,76,w.night)
draw.text(160,factY+50,string.format("%.0f °C",w.temp),"large",color.BLACK)
draw.text(160,factY+72,feelsText(w,ctx),"normal",color.BLACK)
factGrid(w,ctx,320,16,22,26,factY+4,16)
y=factY+factRowH+16
if #w.hourly>=2 then
accentCard(CARD_MARGIN,y - 8,cardW,30+46)
hourlyBlock(w,y,56,24,30,CARD_MARGIN+16,6,14,12,28)
y=y+30+52
end
if #w.daily>0 then
accentCard(CARD_MARGIN,y - 8,cardW,84)
dailyBlock(w,ctx,y,22,12,26,38,64)
else
notice(W//2,y,"loading",tr("Forecast is loading ...","Vorhersage wird geladen ...",ctx))
end
end
local COND_DE={clear="Klar",partly="Teils bewölkt",cloudy="Bewölkt",fog="Nebel",drizzle="Nieselregen",
rain="Regen",snow="Schnee",thunder="Gewitter",unknown="Wetter"}
local COND_EN={clear="Clear",partly="Partly cloudy",cloudy="Cloudy",fog="Fog",drizzle="Drizzle",
rain="Rain",snow="Snow",thunder="Thunderstorm",unknown="Weather"}
local function fit(s,font,maxw)
if draw.measure(s,font)<=maxw then return s end
while #s>1 and draw.measure(s.."...",font)>maxw do
local n=#s
repeat n=n - 1 until n<=1 or (s:byte(n)<128 or s:byte(n)>=192)
s=s:sub(1,n)
end
return s.."..."
end
local function centered(cx,y,s,font,col,lo,hi)
s=fit(s,font,hi - lo)
draw.text(cx,y,s,font,col,"center")
end
local function fnt(b,base)
local t=b and b.font or 0
if t<0 and base=="normal" then return "small" end
if t>0 and base=="small" then return "normal" end
return base
end
local function widgetCurrent(w,ctx,b,top,maxY,compact,extra)
local areaH=maxY - top
local cx=b.x+b.w//2
local temp=string.format("%.0f°C",w.temp)
local feelsLine=string.format(tr("feels %.0f° · %d %%","gefühlt %.0f° · %d %%",ctx),w.feels or w.temp,w.humidity or 0)
if b.w<190 then
local cap=compact and 55 or 80
local size=areaH - 40
if size>cap then size=cap end
if size<26 then size=26 end
if size>b.w - 16 then size=b.w - 16 end
local icy=top+6+size//2
wxIcon(w.cond,cx,icy,size,w.night)
local ty=icy+size//2+26
if ty>maxY - 4 then ty=maxY - 4 end
centered(cx,ty,temp,"large",color.BLACK,b.x+4,b.x+b.w - 4)
local after=ty
if extra and not compact and ty+22<=maxY then
centered(cx,ty+21,feelsLine,fnt(b,"small"),color.BLACK,b.x+4,b.x+b.w - 4)
after=ty+21
end
local bottom=icy+size//2
return bottom>after and bottom or after
end
local size=areaH - 4
local cap=compact and 66 or ((areaH>=130 and b.w>=280) and 145 or 97)
if size>cap then size=cap end
if size<30 then size=30 end
if b.w<200 and size>62 then size=62 end
local icy=top+areaH//2
wxIcon(w.cond,b.x+16+size//2,icy,size,w.night)
local tx=b.x+34+size
local withLabel=areaH>=56 and not compact
local ty
if withLabel then
local names=(ctx.lang=="en") and COND_EN or COND_DE
local off=(size>88) and (areaH//2 - 40) or 0
if off<0 then off=0 end
draw.text(tx,top+17+off,fit(names[w.cond] or names.unknown,fnt(b,"small"),b.x+b.w - tx - 6),fnt(b,"small"),color.BLACK)
ty=top+52+off
else
ty=top+areaH//2+12
end
draw.text(tx,ty,temp,"large",color.BLACK)
local after=ty
if extra and withLabel and ty+24<=maxY then
draw.text(tx,ty+23,fit(feelsLine,fnt(b,"small"),b.x+b.w - tx - 6),fnt(b,"small"),color.BLACK)
after=ty+23
end
local bottom=icy+size//2
return bottom>after and bottom or after
end
local function widgetForecast(w,ctx,b,top,maxY,compact,withBarOpt)
if #w.daily==0 or maxY - top<18 then return top end
local withBar=withBarOpt and b.w>=250
local rowH=compact and 20 or 36
local n=(maxY - top)//rowH
if n>#w.daily then n=#w.daily end
if n<1 then n=1 end
if not compact then rowH=math.min(48,(maxY - top)//n) end
local iconSize=compact and 0 or math.max(24,math.min(40,rowH - 4))
local weekMin,weekMax=w.daily[1].min,w.daily[1].max
for i=2,n do
if w.daily[i].min<weekMin then weekMin=w.daily[i].min end
if w.daily[i].max>weekMax then weekMax=w.daily[i].max end
end
local range=(weekMax - weekMin)>0.5 and (weekMax - weekMin) or 1
local iconCol=compact and 0 or (iconSize+20)
local short=(ctx.lang=="en") and SHORT_EN or SHORT_DE
for i=1,n do
local d=w.daily[i]
local cy=top+(i - 1)*rowH+rowH//2
draw.text(b.x+12,cy+5,short[((d.wday+6)%7)+1],fnt(b,"small"),i==1 and color.ACCENT or color.BLACK)
if not compact then wxIcon(d.cond,b.x+40+iconSize//2,cy,iconSize) end
if withBar then
local minX=b.x+32+iconCol
draw.text(minX+18,cy+5,string.format("%.0f°",d.min),fnt(b,"small"),color.BLACK,"center")
local bx=minX+42
local bw=b.x+b.w - 44 - bx
draw.rect(bx,cy - 6,bw,13,color.BLACK,false,6)
local s0=math.floor((d.min - weekMin)/range*(bw - 6))
local e0=math.floor((d.max - weekMin)/range*(bw - 6))
local fw=e0 - s0
if fw<8 then fw=8 end
if s0+fw>bw - 6 then s0=bw - 6 - fw end
if s0<0 then s0=0 end
draw.rect(bx+3+s0,cy - 3,fw,7,color.ACCENT,true,3)
draw.text(b.x+b.w - 24,cy+5,string.format("%.0f°",d.max),fnt(b,"small"),color.BLACK,"center")
else
centered(b.x+b.w - 44,cy+5,string.format("%.0f° / %.0f°",d.max,d.min),fnt(b,"small"),color.BLACK,b.x+32+iconCol,b.x+b.w - 4)
end
end
return top+n*rowH
end
local function widgetRain(w,ctx,b,top,maxY)
if not w.rain or #w.rain==0 or maxY - top<16 then return top end
local first
for i=1,#w.rain do
if w.rain[i].mm>0.1 then first=i break end
end
local headline
if not first then
headline=tr("No rain in the next 2 h","Kein Regen in den nächsten 2 Std.",ctx)
else
local mins=(w.rain[first].t - time.now())//60
if mins<=1 then headline=tr("Rain now","Regen jetzt",ctx)
else headline=string.format(tr("Rain in ~%d min","Regen in ca. %d Min",ctx),mins) end
end
local function wrapLines(font)
local ls,cur={},""
for word in headline:gmatch("%S+") do
local try=(cur=="") and word or (cur.." "..word)
if draw.measure(try,font)<=b.w - 24 or cur=="" then cur=try
else ls[#ls+1]=cur cur=word end
end
ls[#ls+1]=cur
return ls
end
local font=fnt(b,"small")
local lines=wrapLines(font)
if #lines>2 and font~="small" then
font="small"
lines=wrapLines(font)
end
while #lines>2 do lines[2]=lines[2].." "..table.remove(lines,3) end
local step=(font=="small") and 12 or 14
local col=first and color.ACCENT or color.BLACK
for i,l in ipairs(lines) do
draw.text(b.x+12,top+13+(i - 1)*step,fit(l,font,b.w - 24),font,col)
end
local headBottom=top+13+(#lines - 1)*step+7
local labelsH=(b.w>=220) and 14 or 0
local barsH=maxY - headBottom - labelsH
local n=#w.rain
if barsH<12 or b.w<140 or n<2 then return headBottom end
local marginX,gap=12,4
local barW=(b.w - 2*marginX - (n - 1)*gap)//n
if barW<4 then barW=4 end
local maxP=1
for i=1,n do if w.rain[i].mm>maxP then maxP=w.rain[i].mm end end
local baseY=headBottom+barsH
for i=1,n do
local bx=b.x+marginX+(i - 1)*(barW+gap)
local mm=w.rain[i].mm
if mm>0.05 then
local bh=math.floor(math.min(mm/maxP,1)*barsH)
if bh<5 then bh=5 end
draw.rect(bx,baseY - bh,barW,bh,color.ACCENT,true,2)
else
draw.rect(bx,baseY - 4,barW,4,color.BLACK,false,2)
end
end
if labelsH>0 then
draw.text(b.x+marginX,baseY+12,tr("now","jetzt",ctx),fnt(b,"small"),color.BLACK)
local midX=b.x+marginX+(n//2)*(barW+gap)+barW//2
draw.text(midX,baseY+12,"+1h",fnt(b,"small"),color.BLACK,"center")
local lastRight=b.x+marginX+(n - 1)*(barW+gap)+barW
draw.text(lastRight - barW//2,baseY+12,"+2h",fnt(b,"small"),color.BLACK,"center")
end
return baseY+labelsH
end
local function widgetWarning(w,ctx)
if ctx.cfg.warn==false then return nil end
local now=time.now()
if not now then return nil end
local nowH=time.date(now).hour
local function soon(h,span) return h~=nil and ((h - nowH)%24)<=span end
local function bad(c) return c=="thunder" or c=="hail" end
local storm=bad(w.cond)
local minT=w.temp
if w.hourly then
for i=1,#w.hourly do
local e=w.hourly[i]
if soon(e.hour,2) and bad(e.cond) then storm=true end
if soon(e.hour,3) and e.temp~=nil and (minT==nil or e.temp<minT) then minT=e.temp end
end
end
if storm then return tr("Storm warning: thunderstorm","Unwetter: Gewitter",ctx),color.RED,color.WHITE end
if w.wind and w.wind>=60 then
return string.format(tr("Storm warning: wind %d km/h","Sturmwarnung: Wind %d km/h",ctx),math.floor(w.wind+0.5)),color.RED,color.WHITE
end
if minT~=nil and minT<=0 then
return string.format(tr("Frost: %d °C","Frost: %d °C",ctx),math.floor(minT+0.5)),color.BLUE,color.WHITE
end
if w.rain then
for i=1,#w.rain do
local r=w.rain[i]
if r.t>now and r.t<now+3600 and r.mm>0.1 then
local mins=(r.t - now)//60
if mins<=1 then return tr("Rain starting now","Regen beginnt jetzt",ctx),color.YELLOW,color.BLACK end
return string.format(tr("Rain in ~%d min","Regen in ca. %d Min",ctx),mins),color.YELLOW,color.BLACK
end
end
end
return nil
end
function outdoor.on_widget(ctx,b)
setIconStyle(ctx.cfg.wIconStyle)
local w,why=weather.get()
if not w then
local msg=(why=="nolocation") and tr("Location not set","Standort nicht eingerichtet",ctx) or tr("Loading ...","Wird geladen ...",ctx)
draw.text(b.x+b.w//2,b.y+b.h//2,fit(msg,"small",b.w - 16),"small",color.BLACK,"center")
return
end
local opt=ctx.cfg.opt or 0
local extra=(opt & 1)~=0
local showForecast=(opt & 2)~=0 or (b.h>=170 and w.daily~=nil and #w.daily>0 and not (ctx.cfg.style=="compact"))
local showRain=(opt & 4)~=0 and w.rain~=nil and #w.rain>0
local compact=(ctx.cfg.style=="compact")
local top=b.y
local maxY=b.y+b.h - 4
local warnText,warnBg,warnInk
if b.h>=100 and b.w>=150 then warnText,warnBg,warnInk=widgetWarning(w,ctx) end
if warnText then maxY=maxY - 26 end
local rainH=showRain and (compact and 40 or 56) or 0
local belowMax=showRain and (maxY - rainH - 14) or maxY
if belowMax<top+20 then belowMax=maxY end
local blockMax=belowMax
if showForecast then
local cur=compact and 78 or 108
blockMax=top+cur
if blockMax>belowMax then blockMax=belowMax end
end
local y=widgetCurrent(w,ctx,b,top,blockMax,compact,extra)
if showForecast and belowMax - (y+14)>=18 then
hline(b.x+12,y+7,b.w - 24)
y=widgetForecast(w,ctx,b,y+14,belowMax,compact,extra)
end
if showRain and maxY - (y+14)>=18 then
hline(b.x+12,y+7,b.w - 24)
widgetRain(w,ctx,b,y+14,maxY)
end
if warnText then
local wy=b.y+b.h - 24
draw.rect(b.x+4,wy,b.w - 8,20,warnBg,true,6)
draw.text(b.x+b.w//2,wy+14,fit(warnText,"small",b.w - 24),"small",warnInk,"center")
end
end
function outdoor.on_draw(ctx,page)
setIconStyle(ctx.cfg.iconStyle)
draw.clear(color.WHITE)
local w,why=weather.get()
if not w then
local y=draw.top+16
if why=="nolocation" then
notice(W//2,y,"setup",tr("Location not set.","Standort nicht eingerichtet.",ctx),tr("Studio -> Store -> Weather","Studio -> Store -> Wetter",ctx))
else
notice(W//2,y,"loading",tr("Loading ...","Wird geladen ...",ctx))
end
return true
end
local style=ctx.cfg.style
if style=="compact" then
drawCompact(w,ctx)
else
drawBigStyle(w,ctx,style=="flat")
end
return true
end
end
do
local W=(draw and draw.width) or 800
local CARD_MARGIN=14
local CARD_RADIUS=8
local HISTORY_DAYS=1
local TEMP_COLOR=color.BLUE
local CO2_COLOR=color.BLACK
local HUM_COLOR=color.BLUE
local function tr(en,de,ctx) if ctx.lang=="en" then return en end return de end
local function round(v) if v>=0 then return math.floor(v+0.5) end return -math.floor(-v+0.5) end
local function fit(s,font,maxw)
if draw.measure(s,font)<=maxw then return s end
while #s>1 and draw.measure(s.."...",font)>maxw do s=s:sub(1,#s - 1) end
return s.."..."
end
local function accentCard(x,y,w,h,accent)
draw.rect(x,y,w,h,color.WHITE,true,CARD_RADIUS)
draw.rect(x,y,w,h,color.BLACK,false,CARD_RADIUS)
draw.rect(x+6,y+6,5,h - 12,accent or color.ACCENT,true,2)
end
local function hline(x,y,w,col) draw.rect(x,y,w,1,col or color.BLACK,true) end
local function vline(x,y,h) draw.rect(x,y,1,h,color.BLACK,true) end
local function thickLine(x0,y0,x1,y1,col)
draw.line(x0,y0,x1,y1,col)
draw.line(x0,y0+1,x1,y1+1,col)
draw.line(x0+1,y0,x1+1,y1,col)
draw.line(x0,y0 - 1,x1,y1 - 1,col)
draw.line(x0 - 1,y0,x1 - 1,y1,col)
end
local function catmull(p0,p1,p2,p3,t)
local t2,t3=t*t,t*t*t
return 0.5*((2*p1)+(-p0+p2)*t+(2*p0 - 5*p1+4*p2 - p3)*t2+(-p0+3*p1 - 3*p2+p3)*t3)
end
local function curve(vals,n,xAt,yAt,col)
local px,py=xAt(0),yAt(vals[1])
for i=1,n - 1 do
local p0=vals[i>1 and i - 1 or i]
local p1=vals[i]
local p2=vals[i+1]
local p3=vals[i+2<=n and i+2 or i+1]
for s=1,4 do
local t=s/4
local nx,ny=xAt(i - 1+t),yAt(catmull(p0,p1,p2,p3,t))
thickLine(round(px),round(py),round(nx),round(ny),col)
px,py=nx,ny
end
end
end
local function fmtNum(v,decimals)
if decimals==0 then return string.format("%d",round(v)) end
return string.format("%.1f",v)
end
local function sparkline(x,y,w,h,vals,n,col,axis,decimals)
if n<2 then return end
local minV,maxV=vals[1],vals[1]
for i=2,n do
if vals[i]<minV then minV=vals[i] end
if vals[i]>maxV then maxV=vals[i] end
end
local range=maxV - minV
if range<0.5 then range=0.5 end
local lineX,lineW=x,w
if axis then
draw.text(x,y+7,fmtNum(maxV,decimals),"small",color.BLACK)
draw.text(x,y+h - 1,fmtNum(minV,decimals),"small",color.BLACK)
lineX,lineW=x+26,w - 26
end
curve(vals,n,
function(idx) return lineX+idx*(lineW - 1)/(n - 1) end,
function(v) return y+h - 1 - (v - minV)/range*(h - 1) end,col)
end
local function localOffset()
local lt=time.localtime()
if not lt then return 0 end
local sod=lt.hour*3600+lt.min*60+lt.sec
return (sod - (time.now()%86400))%86400
end
local function axisChart(x,y,w,h,vals,epochs,n,col,decimals)
if n<2 then return end
local minV,maxV=vals[1],vals[1]
for i=2,n do
if vals[i]<minV then minV=vals[i] end
if vals[i]>maxV then maxV=vals[i] end
end
local range=maxV - minV
if range<1 then range=1 end
minV=minV - range*0.12
maxV=maxV+range*0.12
range=maxV - minV
local yAxisW,xAxisH,xRight=44,18,24
local plotX=x+yAxisW
local plotW=w - yAxisW - xRight
local plotH=h - xAxisH
for i=0,4 do
local v=maxV - (range*i)/4
local ly=y+(i*(plotH - 1))//4
hline(plotX,ly,plotW)
draw.text(x,ly+4,fmtNum(v,decimals),"small",color.BLACK)
end
curve(vals,n,
function(idx) return plotX+idx*(plotW - 1)/(n - 1) end,
function(v) return y+plotH - 1 - (v - minV)/range*(plotH - 1) end,col)
local off=localOffset()
local labels=n<5 and n or 5
for i=0,labels - 1 do
local idx=labels>1 and ((n - 1)*i)//(labels - 1) or 0
local sec=((epochs[idx+1] or 0)+off)%86400
local lbl=string.format("%02d:%02d",sec//3600,(sec%3600)//60)
local lx=plotX+(idx*(plotW - 1))//(n - 1)
draw.text(lx,y+h - 2,lbl,"small",color.BLACK,"center")
end
end
local function thermometerIcon(x,y,col,s)
s=s or 1
local sw,sh,sr=round(6*s),round(13*s),round(3*s)
draw.rect(x+round(5*s),y,sw,sh,col,true,sr)
draw.circle(x+round(8*s),y+round(14*s),round(6*s),col,true)
draw.circle(x+round(8*s),y+round(14*s),round(3*s),color.WHITE,true)
end
local function co2Icon(x,y,col,s)
s=s or 1
draw.circle(x+round(4*s),y+round(9*s),round(4*s),col,true)
draw.circle(x+round(12*s),y+round(5*s),round(3*s),col,true)
draw.circle(x+round(12*s),y+round(13*s),round(3*s),col,true)
end
local function dropletIcon(x,y,col,s)
s=s or 1
draw.triangle(x+round(7*s),y,x+round(1*s),y+round(11*s),x+round(13*s),y+round(11*s),col,true)
draw.circle(x+round(7*s),y+round(11*s),round(6*s),col,true)
end
local ICONS={temp=thermometerIcon,co2=co2Icon,hum=dropletIcon}
local function pillBadge(text,cx,y,fill)
local pillW=draw.measure(text,"large")+48
if pillW<280 then pillW=280 end
local maxW=2*math.min(cx,W - cx) - 16
if pillW>maxW then pillW=maxW end
draw.rect(cx - pillW//2,y,pillW,48,fill,true,20)
draw.text(cx,y+48 - 14,text,"large",color.WHITE,"center")
return y+48
end
local function warningBanner(cx,y,width,text,col)
local lines,cur={},""
for word in text:gmatch("%S+") do
local try=(cur=="") and word or (cur.." "..word)
if draw.measure(try,"small")<=width - 30 or cur=="" then cur=try
else lines[#lines+1]=cur cur=word end
end
lines[#lines+1]=cur
while #lines>2 do lines[2]=lines[2].." "..table.remove(lines,3) end
local bannerH=14+#lines*16
draw.rect(cx - width//2,y,width,bannerH,col,true,8)
for i,l in ipairs(lines) do draw.text(cx,y+20+(i - 1)*16,l,"small",color.WHITE,"center") end
return y+bannerH
end
local function notice(cx,y,kind,line1)
local r=22
local cy=y+r
draw.rect(cx - r,cy - r,2*r,2*r,color.ACCENT,true,r)
if kind=="loading" then
for i=-1,1 do draw.circle(cx+i*12,cy,3,color.WHITE,true) end
else
draw.text(cx,cy+7,"-","large",color.WHITE,"center")
end
draw.text(cx,cy+r+32,line1,"large",color.BLACK,"center")
end
local function noticeCompact(cx,y,kind,line1)
local r=10
local textW=draw.measure(line1,"normal")
local clusterW=textW+2*r+10
local circleCx=cx - clusterW//2+r
local textCx=circleCx+r+5+textW//2
draw.circle(circleCx,y,r,color.ACCENT,true)
if kind=="loading" then
for i=-1,1 do draw.circle(circleCx+i*5,y,1,color.WHITE,true) end
else
draw.text(circleCx,y+4,"-","normal",color.WHITE,"center")
end
draw.text(textCx,y+4,line1,"normal",color.BLACK,"center")
end
local function batteryIcon(x,y,col,pct)
local bodyW,bodyH=22,12
draw.rect(x,y,bodyW,bodyH,col,false,2)
draw.rect(x+bodyW,y+3,3,6,col,true)
if not pct then
draw.line(x - 2,y - 2,x+bodyW+5,y+bodyH+2,col)
draw.line(x - 2,y - 1,x+bodyW+5,y+bodyH+3,col)
return
end
if pct<0 then pct=0 end
if pct>100 then pct=100 end
local fillW=round((bodyW - 4)*pct/100)
if fillW>0 then draw.rect(x+2,y+2,fillW,bodyH - 4,pct<20 and color.RED or col,true) end
end
local ROOMS_DE={wohnzimmer="Wohnzimmer",flur="Flur",kueche="Küche",bad="Bad",schlafzimmer="Schlafzimmer"}
local ROOMS_EN={wohnzimmer="Living room",flur="Hallway",kueche="Kitchen",bad="Bathroom",schlafzimmer="Bedroom"}
local ROOMS_MORE_DE={buero="Büro",gaestezimmer="Gästezimmer",waschkueche="Waschküche",kinderzimmer="Kinderzimmer",arbeitszimmer="Arbeitszimmer",esszimmer="Esszimmer",keller="Keller",garage="Garage",dachboden="Dachboden",balkon="Balkon",terrasse="Terrasse",diele="Diele"}
local ROOMS_MORE_EN={buero="Office",gaestezimmer="Guest room",waschkueche="Laundry room",kinderzimmer="Kids' room",arbeitszimmer="Study",esszimmer="Dining room",keller="Basement",garage="Garage",dachboden="Attic",balkon="Balcony",terrasse="Terrace",diele="Hall"}
local function roomName(id,ctx)
local en=(ctx.lang=="en")
local key=tostring(id or ""):lower()
local m=(en and ROOMS_EN or ROOMS_DE)[key] or (en and ROOMS_MORE_EN or ROOMS_MORE_DE)[key]
if m then return m end
return id
end
local function relTime(epoch,ctx)
if not epoch or epoch<=0 then return "" end
local diff=time.now() - epoch
if diff<0 then diff=0 end
local min=diff//60
if min<1 then return tr("just now","gerade eben",ctx) end
if min<60 then return string.format(tr("%d min ago","vor %d Min.",ctx),min) end
if min<1440 then return string.format(tr("%d h ago","vor %d Std.",ctx),min//60) end
return string.format(tr("%d d ago","vor %d Tagen",ctx),min//1440)
end
local function co2Zone(s)
if s.co2<800 then return 2 end
if s.co2<s.co2_warn_ppm then return 1 end
return 0
end
local CO2_COLORS={[0]=color.RED,[1]=color.YELLOW,[2]=color.GREEN}
local function humZone(s)
if s.humidity<s.hum_low then return 0 end
if s.humidity>s.hum_high then return 2 end
return 1
end
local HUM_COLORS={[0]=color.YELLOW,[1]=color.GREEN,[2]=color.BLUE}
local function histTitle(hours,ctx)
if hours<48 then return string.format(tr("Trend (%dh)","Verlauf (%d Std.)",ctx),hours) end
return string.format(tr("Trend (%d days)","Verlauf (%d Tage)",ctx),hours//24)
end
local RANGE_HOURS=24
local function trimRange(h)
if RANGE_HOURS>=24 or h.n<2 then return h end
local cutoff=h.time[h.n] - RANGE_HOURS*3600
local first=1
while first<h.n and h.time[first]<cutoff do first=first+1 end
if first==1 then return h end
local out={temp={},humidity={},co2={},time={},n=h.n - first+1}
for i=first,h.n do
local j=i - first+1
out.temp[j],out.humidity[j],out.co2[j],out.time[j]=h.temp[i],h.humidity[i],h.co2[i],h.time[i]
end
out.hours=math.min(h.hours,RANGE_HOURS)
return out
end
local function loadHistory(peer)
local h=sensor.history(peer,HISTORY_DAYS)
if h and h.n>=2 then
h=trimRange(h)
if h.n>=2 then return h end
end
return nil
end
local function statCell(x,y,w,h,kind,idColor,label,value,mode,statusText,statusColor)
draw.rect(x,y,w,h,color.BLACK,false,CARD_RADIUS)
local iconX,iconY=x+10,y+8
ICONS[kind](iconX,iconY,idColor,1)
draw.text(iconX+22,iconY+13,label,"small",idColor)
draw.text(x+10,y+56,value,"large",color.BLACK)
if mode==1 then
local pillH,pillY,pillW=22,y+h - 22 - 8,w - 20
draw.rect(x+10,pillY,pillW,pillH,statusColor,true,6)
draw.text(x+10+pillW//2,pillY+pillH - 6,statusText,"small",color.WHITE,"center")
elseif mode==2 then
draw.text(x+w//2,y+h - 10,statusText,"small",idColor,"center")
end
end
local function average(vals,n)
if n<=0 then return 0 end
local sum=0
for i=1,n do sum=sum+vals[i] end
return sum/n
end
local function co2Status(s,ctx)
local z=co2Zone(s)
if z==2 then return tr("very good air","sehr gute Luft",ctx) end
if z==1 then return tr("air okay","Luft okay",ctx) end
return tr("please ventilate","bitte lüften",ctx)
end
local function humStatus(s,ctx)
local z=humZone(s)
if z==0 then return tr("too dry","zu trocken",ctx) end
if z==2 then return tr("too humid","zu feucht",ctx) end
return tr("optimal","optimal",ctx)
end
local function pageCards(s,ctx)
local top=draw.top
local cardW=W - 2*CARD_MARGIN
local h=loadHistory(0)
local statGap=12
local statW=(cardW - 2*statGap)//3
local statH=90
local statY=top+6
local x1=CARD_MARGIN
local x2=x1+statW+statGap
local x3=x2+statW+statGap
local y1,y2,y3=statY,statY,statY
local stacked=draw.height>draw.width
if stacked then
statW=cardW
x2,x3=x1,x1
y2=y1+statH+8
y3=y2+statH+8
end
local tempStatus=s.temp<18 and tr("cool","kühl",ctx) or (s.temp>24 and tr("warm","warm",ctx) or tr("comfortable","angenehm",ctx))
statCell(x1,y1,statW,statH,"temp",TEMP_COLOR,tr("Temperature","Temperatur",ctx),
string.format(tr("%.1f°C","%.1f °C",ctx),s.temp),2,tempStatus,color.BLACK)
statCell(x2,y2,statW,statH,"co2",CO2_COLOR,"CO2",string.format("%d ppm",s.co2),
s.co2_warn and 1 or 0,co2Status(s,ctx),CO2_COLORS[co2Zone(s)])
statCell(x3,y3,statW,statH,"hum",HUM_COLOR,tr("Humidity","Luftfeuchtigkeit",ctx),string.format("%.0f %%",s.humidity),
s.hum_warn and 1 or 0,humStatus(s,ctx),HUM_COLORS[humZone(s)])
local divider1=y3+statH+10
hline(CARD_MARGIN,divider1,cardW)
if not h then
noticeCompact(W//2,divider1+50,"empty",tr("Not enough trend data yet","Noch nicht genug Verlaufsdaten",ctx))
return
end
local focus=ctx.cfg.focus or "co2"
local series,fcol,fname,fdec,fval=h.co2,CO2_COLOR,"CO2",0,string.format("%d ppm",s.co2)
if focus=="temperature" then
series,fcol,fname,fdec,fval=h.temp,TEMP_COLOR,tr("TEMPERATURE","TEMPERATUR",ctx),1,string.format("%.1f °C",s.temp)
elseif focus=="humidity" then
series,fcol,fname,fdec,fval=h.humidity,HUM_COLOR,tr("HUMIDITY","LUFTFEUCHTIGKEIT",ctx),0,string.format("%.0f %%",s.humidity)
end
local focusY=divider1+14
local title
if h.hours<48 then title=string.format(tr("%s TREND - LAST %dH","%s-VERLAUF - LETZTE %d STD.",ctx),fname,h.hours)
else title=string.format(tr("%s TREND - LAST %d DAYS","%s-VERLAUF - LETZTE %d TAGE",ctx),fname,h.hours//24) end
draw.text(CARD_MARGIN,focusY+14,title,"normal",color.BLACK)
draw.text(CARD_MARGIN+cardW,focusY+14,fval,"normal",color.BLACK,"right")
local chartY=focusY+26
local tall=draw.height>draw.width
local chartH=tall and 170 or 140
axisChart(CARD_MARGIN,chartY,cardW,chartH,series,h.time,h.n,fcol,fdec)
local divider2=chartY+chartH+12
local showT=focus~="temperature" and ctx.cfg.showTemp~=false
local showH=focus~="humidity" and ctx.cfg.showHum~=false
local showC=focus~="co2" and ctx.cfg.showCo2~=false
local count=(showT and 1 or 0)+(showH and 1 or 0)+(showC and 1 or 0)
if count==0 then return end
hline(CARD_MARGIN,divider2,cardW)
local miniGap=12
local miniW=count==1 and cardW or (cardW - miniGap)//2
local miniH=tall and 170 or 100
local miniY=divider2+14
local sx=CARD_MARGIN
local function secondary(label,value,col,vals,dec)
vline(sx,miniY,miniH)
draw.text(sx+14,miniY+18,label,"normal",color.BLACK)
draw.text(sx+14,miniY+50,value,"large",color.BLACK)
sparkline(sx+14,miniY+60,miniW - 28,miniH - 70,vals,h.n,col,true,dec)
sx=sx+miniW+miniGap
end
if showT then secondary(tr("Temperature","Temperatur",ctx),string.format(tr("Ø %.1f°C","Ø %.1f °C",ctx),average(h.temp,h.n)),TEMP_COLOR,h.temp,1) end
if showH then secondary(tr("Humidity","Luftfeuchtigkeit",ctx),string.format("Ø %.0f %%",average(h.humidity,h.n)),HUM_COLOR,h.humidity,0) end
if showC then secondary("CO2",string.format("Ø %.0f ppm",average(h.co2,h.n)),CO2_COLOR,h.co2,0) end
vline(sx - miniGap,miniY,miniH)
end
local function banners(s,ctx,cx,y,width,step)
if s.co2_warn and s.co2>=s.co2_warn_ppm then
y=warningBanner(cx,y,width,tr("CO2 too high - please ventilate!","CO2 zu hoch - bitte lüften!",ctx),color.RED)+step
end
if s.hum_warn and s.humidity<s.hum_low then
y=warningBanner(cx,y,width,tr("Air too dry - humidifier recommended","Luft zu trocken - Luftbefeuchter empfohlen",ctx),color.YELLOW)+step
elseif s.hum_warn and s.humidity>s.hum_high then
y=warningBanner(cx,y,width,tr("Air too humid - please ventilate","Luft zu feucht - bitte lüften",ctx),color.BLUE)+step
end
return y
end
local function threeSparks(h,ctx,x0,totalW,y,graphH,titleY)
local colGap=20
local colW=(totalW - 2*colGap)//3
local c1=x0
local c2=c1+colW+colGap
local c3=c2+colW+colGap
draw.text(c1+colW//2,titleY,tr("Temperature","Temperatur",ctx),"normal",color.BLACK,"center")
draw.text(c2+colW//2,titleY,tr("Humidity","Feuchte",ctx),"normal",color.BLACK,"center")
draw.text(c3+colW//2,titleY,"CO2","normal",color.BLACK,"center")
sparkline(c1,y,colW,graphH,h.temp,h.n,TEMP_COLOR,true,1)
sparkline(c2,y,colW,graphH,h.humidity,h.n,HUM_COLOR,true,0)
sparkline(c3,y,colW,graphH,h.co2,h.n,CO2_COLOR,true,0)
end
local function pageCompact(s,ctx)
local top=draw.top
local cx=W//2
local cardW=W - 2*CARD_MARGIN
local valuesY=top+6
local valuesCardH=200
accentCard(CARD_MARGIN,valuesY,cardW,valuesCardH)
local contentY=valuesY+16
local zc=s.co2<800 and color.GREEN or (s.co2<s.co2_warn_ppm and color.YELLOW or color.RED)
pillBadge(string.format("%d ppm CO2",s.co2),cx,contentY,zc)
draw.text(cx,contentY+58,string.format(tr("%.1f°C","%.1f °C",ctx),s.temp),"normal",color.BLACK,"center")
draw.text(cx,contentY+80,string.format(tr("%.0f%% humidity","%.0f %% Feuchte",ctx),s.humidity),"normal",color.BLACK,"center")
local bannerY=contentY+98
if s.co2_warn and s.co2>=s.co2_warn_ppm then
warningBanner(cx,bannerY,cardW - 60,tr("CO2 too high - please ventilate!","CO2 zu hoch - bitte lüften!",ctx),color.RED)
end
if s.hum_warn and s.humidity<s.hum_low then
warningBanner(cx,bannerY+38,cardW - 60,tr("Air too dry - humidifier recommended","Luft zu trocken - Luftbefeuchter empfohlen",ctx),color.YELLOW)
elseif s.hum_warn and s.humidity>s.hum_high then
warningBanner(cx,bannerY+38,cardW - 60,tr("Air too humid - please ventilate","Luft zu feucht - bitte lüften",ctx),color.BLUE)
end
local h=loadHistory(0)
if h then
local histY=valuesY+valuesCardH+10
local gx=(draw.height>draw.width) and 190 or 0
accentCard(CARD_MARGIN,histY,cardW,118+gx)
draw.text(cx,histY+20,histTitle(h.hours,ctx),"normal",color.BLACK,"center")
local graphY=histY+34
local colGap=20
local colW=(cardW - 40 - 2*colGap)//3
local c1=CARD_MARGIN+20
local c2=c1+colW+colGap
local c3=c2+colW+colGap
draw.text(c1+colW//2,graphY+10,tr("Temperature","Temperatur",ctx),"normal",color.BLACK,"center")
sparkline(c1,graphY+16,colW,56+gx,h.temp,h.n,TEMP_COLOR,true,1)
draw.text(c2+colW//2,graphY+10,tr("Humidity","Feuchte",ctx),"normal",color.BLACK,"center")
sparkline(c2,graphY+16,colW,56+gx,h.humidity,h.n,HUM_COLOR,true,0)
draw.text(c3+colW//2,graphY+10,"CO2","normal",color.BLACK,"center")
sparkline(c3,graphY+16,colW,56+gx,h.co2,h.n,CO2_COLOR,true,0)
end
end
local function pageFlat(s,ctx)
local top=draw.top
local cx=W//2
local lineY=top+6+25
local zc=s.co2<800 and color.GREEN or (s.co2<s.co2_warn_ppm and color.YELLOW or color.RED)
lineY=pillBadge(string.format("%d ppm CO2",s.co2),cx,lineY,zc)+30
if s.co2_warn and s.co2>=s.co2_warn_ppm then
lineY=warningBanner(cx,lineY,W - 80,tr("CO2 too high - please ventilate!","CO2 zu hoch - bitte lüften!",ctx),color.RED)+16
end
draw.text(cx,lineY,string.format(tr("%.1f°C","%.1f °C",ctx),s.temp),"normal",color.BLACK,"center")
lineY=lineY+26
draw.text(cx,lineY,string.format(tr("%.0f%% humidity","%.0f %% Feuchte",ctx),s.humidity),"normal",color.BLACK,"center")
lineY=lineY+26
if s.hum_warn and s.humidity<s.hum_low then
lineY=warningBanner(cx,lineY,W - 80,tr("Air too dry - humidifier recommended","Luft zu trocken - Luftbefeuchter empfohlen",ctx),color.YELLOW)+16
elseif s.hum_warn and s.humidity>s.hum_high then
lineY=warningBanner(cx,lineY,W - 80,tr("Air too humid - please ventilate","Luft zu feucht - bitte lüften",ctx),color.BLUE)+16
end
local h=loadHistory(0)
if h then
lineY=lineY+10
hline(40,lineY,W - 80)
lineY=lineY+22
draw.text(cx,lineY,histTitle(h.hours,ctx),"normal",color.BLACK,"center")
lineY=lineY+18
local graphY=lineY
local gx=(draw.height>draw.width) and 230 or 0
local colGap=20
local colW=(W - 80 - 2*colGap)//3
local c1=40
local c2=c1+colW+colGap
local c3=c2+colW+colGap
draw.text(c1+colW//2,graphY+10,tr("Temperature","Temperatur",ctx),"normal",color.BLACK,"center")
sparkline(c1,graphY+16,colW,70+gx,h.temp,h.n,TEMP_COLOR,true,1)
draw.text(c2+colW//2,graphY+10,tr("Humidity","Feuchte",ctx),"normal",color.BLACK,"center")
sparkline(c2,graphY+16,colW,70+gx,h.humidity,h.n,HUM_COLOR,true,0)
draw.text(c3+colW//2,graphY+10,"CO2","normal",color.BLACK,"center")
sparkline(c3,graphY+16,colW,70+gx,h.co2,h.n,CO2_COLOR,true,0)
end
end
local function pageNetwork(ctx)
local top=draw.top
local cx=W//2
local compact=(ctx.cfg.style=="compact")
local s=sensor.get()
local tiles={}
local nowE=time.now()
local warnPpm,warnOn=1200,false
if s then warnPpm,warnOn=s.co2_warn_ppm,s.co2_warn end
local selfHist=loadHistory(0)
local room=s and s.room or ""
tiles[1]={
room=room,isSelf=true,valid=s~=nil,
co2=s and s.co2 or 0,temp=s and s.temp or 0,hum=s and s.humidity or 0,
hist=selfHist,seen=nowE,battery=s and s.battery or nil,
}
local peers=sensor.peers()
for i,p in ipairs(peers) do
tiles[#tiles+1]={
room=p.room,isSelf=false,valid=p.valid,co2=p.co2,temp=p.temp,hum=p.humidity,
hist=loadHistory(i),seen=p.seen,battery=p.battery,
}
end
if #tiles<=1 then
notice(cx,top+20,"empty",tr("No other InkBoard found on the network.","Kein anderes InkBoard im Netzwerk gefunden.",ctx))
return
end
local warmest,coldest,highest=nil,nil,nil
local valid,sumT,sumH=0,0,0
for i,t in ipairs(tiles) do
if t.valid then
valid=valid+1
sumT=sumT+t.temp
sumH=sumH+t.hum
if not warmest or t.temp>tiles[warmest].temp then warmest=i end
if not coldest or t.temp<tiles[coldest].temp then coldest=i end
if not highest or t.co2>tiles[highest].co2 then highest=i end
end
end
local showRanking=valid>=2
local cardW=W - 2*CARD_MARGIN
local gridGap=12
local cols=(draw.height>draw.width) and 1 or 2
local tileW=cols==2 and (cardW - gridGap)//2 or cardW
local headerOffset=0
if valid>=1 then
local fmtAvg=cols==2 and tr("Avg %.1f°C · %.0f%% humidity across %d rooms","Ø %.1f°C · %.0f%% Feuchte über %d Räume",ctx)
or tr("Avg %.1f°C · %.0f%% · %d rooms","Ø %.1f°C · %.0f%% · %d Räume",ctx)
draw.text(cx,top+14,string.format(fmtAvg,sumT/valid,sumH/valid,valid),"normal",color.BLACK,"center")
headerOffset=24
end
local tileH=(compact and 108 or 124)+18+(cols==1 and 34 or 0)
local col1X=CARD_MARGIN
local col2X=CARD_MARGIN+tileW+gridGap
for i,t in ipairs(tiles) do
local row,col=(i - 1)//cols,(i - 1)%cols
local tx=(col==0) and col1X or col2X
local ty=top+6+headerOffset+row*(tileH+gridGap)
local alarm=warnOn and t.valid and t.co2>=warnPpm
accentCard(tx,ty,tileW,tileH,alarm and color.RED or color.ACCENT)
local title=roomName(t.room,ctx)
if t.isSelf then title=title.." ("..tr("this device","dieses Gerät",ctx)..")" end
draw.text(tx+16,ty+20,title,"normal",color.BLACK)
if not t.valid then
noticeCompact(tx+tileW//2,ty+tileH//2+2,"loading",tr("No reading yet","Noch keine Messung",ctx))
else
draw.text(tx+16,ty+42,string.format("%.1f°C · %.0f%% · %d ppm",t.temp,t.hum,t.co2),"normal",alarm and color.RED or color.BLACK)
local statusY=ty+58
local battX,battY=tx+tileW - 16 - 25,ty+50
local rel,relCol
if alarm and t.hist and t.hist.n>=1 then
local n=t.hist.n
local since=t.hist.time[n]
local ranOut=true
for p=n,1,-1 do
if t.hist.co2[p]<warnPpm then ranOut=false break end
since=t.hist.time[p]
end
local durMin=(nowE>since) and ((nowE - since)//60) or 0
if durMin<1 then rel=tr("since just now","seit gerade eben",ctx)
elseif durMin<60 then
rel=string.format(ranOut and tr("for %d+ min","seit mind. %d Min.",ctx) or tr("for %d min","seit %d Min.",ctx),durMin)
else
rel=string.format(ranOut and tr("for %d+ h","seit mind. %d Std.",ctx) or tr("for %d h","seit %d Std.",ctx),durMin//60)
end
relCol=color.RED
else
rel=relTime(t.seen,ctx)
relCol=color.BLACK
end
draw.text(tx+16,statusY,rel,"small",relCol)
if showRanking then
local badge,bcol
if i==highest then badge,bcol="CO2 max",CO2_COLOR
elseif i==warmest then badge,bcol=tr("warmest","wärmste",ctx),TEMP_COLOR
elseif i==coldest then badge,bcol=tr("coldest","kälteste",ctx),color.BLUE end
if badge then draw.text(battX - 6,statusY,badge,"small",bcol,"right") end
end
batteryIcon(battX,battY,color.BLACK,t.battery)
if t.hist and t.hist.n>=2 then
local graphX,graphY=tx+16,ty+68
local graphW=tileW - 32
local colGap=6
local colW=(graphW - 2*colGap)//3
local g1=graphX
local g2=g1+colW+colGap
local g3=g2+colW+colGap
local titleY=graphY+7
local sparkY=graphY+13
local sparkH=(ty+tileH - 8) - sparkY
draw.text(g1+colW//2,titleY,"Temp","small",TEMP_COLOR,"center")
draw.text(g2+colW//2,titleY,tr("Humid.","Feuchte",ctx),"small",HUM_COLOR,"center")
draw.text(g3+colW//2,titleY,"CO2","small",CO2_COLOR,"center")
sparkline(g1,sparkY,colW,sparkH,t.hist.temp,t.hist.n,TEMP_COLOR,true,1)
sparkline(g2,sparkY,colW,sparkH,t.hist.humidity,t.hist.n,HUM_COLOR,true,0)
sparkline(g3,sparkY,colW,sparkH,t.hist.co2,t.hist.n,CO2_COLOR,true,0)
end
end
end
end
local function applyCfg(ctx)
RANGE_HOURS=tonumber(ctx.cfg.range) or 24
end
function indoor.on_draw(ctx,page,nativePage)
applyCfg(ctx)
draw.clear(color.WHITE)
if nativePage==2 then
pageNetwork(ctx)
return true
end
local s=sensor.get()
if not s then
notice(W//2,draw.top+20,"loading",tr("No reading available yet.","Noch keine Messung verfügbar.",ctx))
return true
end
local style=ctx.cfg.style
if style=="compact" then pageCompact(s,ctx)
elseif style=="flat" then pageFlat(s,ctx)
else pageCards(s,ctx) end
return true
end
function indoor.on_widget(ctx,b)
applyCfg(ctx)
local s=sensor.get()
if not s then
draw.text(b.x+b.w//2,b.y+b.h//2,tr("No reading yet","Noch keine Messung",ctx),"small",color.BLACK,"center")
return
end
local opt=ctx.cfg.opt or 0
local compact=(ctx.cfg.style=="compact")
local font=(b.font<0) and "small" or ((b.font>0) and "medium" or "normal")
local iconScale=1.35
local maxY=b.y+b.h - 6
local x=b.x+16
local showCurves=(not compact) and (opt & 1)~=0
local h=showCurves and loadHistory(0) or nil
local selectMode=(opt & (2 | 4 | 16))~=0
local showT=selectMode and (opt & 2)~=0 or not selectMode
local showH=selectMode and (opt & 4)~=0 or not selectMode
local showC=selectMode and (opt & 16)~=0 or not selectMode
if not showT and not showH and not showC then showT=true end
local order={}
if showT then order[#order+1]=0 end
if showH then order[#order+1]=1 end
if showC then order[#order+1]=2 end
local humCol=s.hum_warn and HUM_COLORS[humZone(s)] or color.BLACK
local co2Col=s.co2_warn and CO2_COLORS[co2Zone(s)] or color.BLACK
local tBuf=string.format("%.1f°C",s.temp)
local hBuf=string.format("%.0f %%",s.humidity)
local cBuf=string.format("%d ppm",s.co2)
local function item(idx,px,py,spark,sx,sw)
if idx==0 then
thermometerIcon(px,py,TEMP_COLOR,iconScale)
draw.text(px+28,py+16,tBuf,font,color.BLACK)
if spark and h then sparkline(sx,py - 4,sw,28,h.temp,h.n,TEMP_COLOR,false,1) end
elseif idx==1 then
dropletIcon(px,py,humCol,iconScale)
draw.text(px+28,py+16,hBuf,font,color.BLACK)
if spark and h then sparkline(sx,py - 4,sw,28,h.humidity,h.n,HUM_COLOR,false,0) end
else
co2Icon(px,py,co2Col,iconScale)
draw.text(px+28,py+16,cBuf,font,color.BLACK)
if spark and h then sparkline(sx,py - 4,sw,28,h.co2,h.n,CO2_COLOR,false,0) end
end
end
if compact then
local y=b.y+6
for i,idx in ipairs(order) do
if i>1 and y+20>maxY then break end
item(idx,x,y,false,0,0)
y=y+29
end
return
end
if showCurves then
local sparkX=x+92
local sparkW=b.x+b.w - 12 - sparkX
local sparkOk=sparkW>=40 and h~=nil
local y=b.y+10
for i,idx in ipairs(order) do
if i>1 and y+20>maxY then break end
item(idx,x,y,sparkOk,sparkX,sparkW)
y=y+38
end
return
end
local rowY=b.y+10
local x2=b.x+b.w//2+8
for i,idx in ipairs(order) do
local col=(i - 1)%2
local row=(i - 1)//2
local py=rowY+row*40
if row>0 and py+20>maxY then break end
item(idx,col==0 and x or x2,py,false,0,0)
end
end
end
function on_draw(ctx,page)
local p=ctx.cfg.page
if p==nil then p=(page or 1) - 1 end
if p==1 then return outdoor.on_draw(ctx,page) end
return indoor.on_draw(ctx,page,p)
end
function on_widget(ctx,b)
if ctx.cfg.widget=="weather_outdoor" then return outdoor.on_widget(ctx,b) end
return indoor.on_widget(ctx,b)
end
