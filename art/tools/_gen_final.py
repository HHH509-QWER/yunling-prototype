import sys, math
sys.path.insert(0,'art/tools')
import _verify_sites as V
def terrain(x,y):
    cx=int(x//32); cy=int(y//32)
    return V.TERR[max(0,min(5,int(round(V.cell(min(cx,111),min(cy,95))[0]/50.0))))]
def d(a,b): return math.dist(a,b)
from _verify_sites2 import GATHER, MOBS, SEAL5
CITY=lambda p: 1280<=p[0]<=2304 and 1024<=p[1]<=2048
DROPG={(1904,368),(3472,2800)}
MOVEM={(2608,2640):(2608,2608),(2640,752):(2528,712),(2448,2864):(2448,2832),(528,752):(496,752)}
# ---- 采集 24 ----
G=[]
for r in (1,2,3,4):
    for p in GATHER[r]:
        p2=MOVEM.get(p,p)
        if p2 in DROPG: continue
        G.append((V.ring(*p2),p2))
# ---- 杂怪 49 ----
M=[];seen=set()
for r in (1,2,3,4):
    for p in MOBS[r]:
        p2=MOVEM.get(p,p)
        if p2 in seen: continue
        seen.add(p2); M.append((V.ring(*p2),p2))
mm=[p for _,p in M]
# ---- 补点：每个采集点 240 内至少一个杂怪 ----
add=[]
for r,gp in G:
    if min(d(gp,q) for q in mm+add)<=240: continue
    best=None
    for rad in (200,190,210,180,220,230,170):
        for ang in range(0,360,5):
            x=round(gp[0]+rad*math.cos(math.radians(ang))); y=round(gp[1]+rad*math.sin(math.radians(ang)))
            if not (48<=x<=3536 and 48<=y<=3024): continue
            if V.deep(x,y) or terrain(x,y)=='水泽' or CITY((x,y)): continue
            if V.ring(x,y)!=r: continue
            if min(d((x,y),q) for q in mm+add)<180: continue
            if min(d((x,y),s[2]) for s in SEAL5)<180: continue
            best=(x,y); break
        if best: break
    if best: add.append(best)
    else: print('!! 安置不下', gp, file=sys.stderr)
allm=mm+add
print('采集 %d 分层 %s'%(len(G),[sum(1 for r,_ in G if r==k) for k in (1,2,3,4)]))
print('杂怪 原49 分层 %s + 新增 %d = %d' %([sum(1 for r,_ in M if r==k) for k in (1,2,3,4)],len(add),len(allm)))
print('杂怪最小间距 %.0f'%min(d(a,b) for i,a in enumerate(allm) for b in allm[i+1:]))
print('覆盖率: 每个采集点 240 内有杂怪 =',all(min(d(g,q) for q in allm)<=240 for _,g in G))
MER=(1792.0,1262.9); SP=(1792.0,1536.0)
en=allm+[s[2] for s in SEAL5]
print('最近敌人→商人 %.0f / →出生点 %.0f'%(min(d(p,MER) for p in en), min(d(p,SP) for p in en)))
print()
print('--- 新增杂怪点 ---')
for p in add:
    gp=min([g for _,g in G],key=lambda g:d(g,p))
    print('  (%d, %d)  服务 %s  间距 %.0f  L%d %s'%(p[0],p[1],str(gp),d(gp,p),V.ring(*p),terrain(*p)))
print()
print('--- GDScript 采集点 ---')
items={1:("蕴灵草",2),2:("玄铁矿",2),3:("雷纹石",2)}
l4=[("地火芯",1),("地火芯",1),("雷髓",1),("雷髓",1),("玄霜髓",1),("太虚核",1)]
order=sorted(G,key=lambda z:(z[0],z[1][1],z[1][0]))
i=0
for r,p in order:
    i+=1
    if r==4: it=l4.pop(0)
    else: it=items[r]
    print('\t\t{"id": "g%02d", "pos": Vector2(%d.0, %d.0), "item": "%s", "amount": %d, "ring": %d},'%(i,p[0],p[1],it[0],it[1],r))
print()
print('--- GDScript 杂怪 ---')
ARCH={1:["猛兽","智谋","猛兽","智谋","猛兽","智谋","猛兽"],
      2:["蛮兽","猛兽","智谋"],3:["蛮兽","智谋","猛兽"],4:["蛮兽","智谋","蛮兽"]}
# 保证 m01=猛兽 m02=智谋
n=0
lines=[]
for r,p in M:
    n+=1
    a=ARCH[r][(n-1)%len(ARCH[r])]
    if n==1: a="猛兽"
    if n==2: a="智谋"
    lines.append((n,r,p,a))
for k,p in enumerate(add):
    n+=1
    r=V.ring(*p)
    lines.append((n,r,p,ARCH[r][k%len(ARCH[r])]))
for n,r,p,a in lines:
    nm="m%02d"%n
    print('\t{"id": "%s", "archetype": "%s", "pos": Vector2(%d.0, %d.0), "ring": %d},'%(nm,a,p[0],p[1],r))
