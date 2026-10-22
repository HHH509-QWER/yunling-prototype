import sys, math, re
sys.path.insert(0,'art/tools')
import _verify_sites as V
from _verify_sites2 import GATHER, MOBS, SEAL5
def terrain(x,y):
    cx=max(0,min(111,int(x//32))); cy=max(0,min(95,int(y//32)))
    return V.TERR[max(0,min(5,int(round(V.cell(cx,cy)[0]/50.0))))]
def d(a,b): return math.dist(a,b)
CITY=lambda p: 1280<=p[0]<=2304 and 1024<=p[1]<=2048
DROPG={(1904,368),(3472,2800)}
MOVEM={(2608,2640):(2608,2608),(2640,752):(2528,712),(2448,2864):(2448,2832),(528,752):(496,752)}
src=open('scripts/GameData.gd',encoding='utf-8').read()
sb=src.split('const WORLD_SITES := [')[1]
SITES=[(float(m.group(2)),float(m.group(3))) for m in re.finditer(r'"id": "([A-Z]\d\d)".*?Vector2\(([\d.]+), ([\d.]+)\)', sb)]
print('手工定点 %d 个'%len(SITES))
# 采集 24
G=[]
for r in (1,2,3,4):
    for p in GATHER[r]:
        p2=MOVEM.get(p,p)
        if p2 in DROPG: continue
        G.append((V.ring(*p2),p2))
# 杂怪 49
M=[];seen=set()
for r in (1,2,3,4):
    for p in MOBS[r]:
        p2=MOVEM.get(p,p)
        if p2 in seen: continue
        seen.add(p2); M.append((V.ring(*p2),p2))
mm=[p for _,p in M]
SEAL=[(868,640),(1776,688),(2772,2261),(3120,1072),(400,2704)]
SITE_MIN=[400,300,250,200,150,100]   # 逐级放宽
add=[]
for r,gp in G:
    if min(d(gp,q) for q in mm+add)<=240: continue
    best=None; used=None
    for smin in SITE_MIN:
        for rad in (200,190,210,180,220,230,170,240):
            for ang in range(0,360,5):
                x=round(gp[0]+rad*math.cos(math.radians(ang))); y=round(gp[1]+rad*math.sin(math.radians(ang)))
                if not (48<=x<=3536 and 48<=y<=3024): continue
                if V.deep(x,y) or terrain(x,y)=='水泽' or CITY((x,y)): continue
                if V.ring(x,y)!=r: continue
                if min(d((x,y),q) for q in mm+add)<170: continue
                if min(d((x,y),s) for s in SEAL)<170: continue
                if min(d((x,y),s) for s in SITES)<smin: continue
                best=(x,y); used=smin; break
            if best: break
        if best: break
    if best: add.append(best); print('  补点 (%d,%d)  服务 %s  距 %.0f  L%d %s  站点余量 %d'%(best[0],best[1],str(gp),d(gp,best),V.ring(*best),terrain(*best),used))
    else: print('!! 安置不下', gp, file=sys.stderr)
allm=mm+add
print('采集 %d 分层 %s'%(len(G),[sum(1 for r,_ in G if r==k) for k in (1,2,3,4)]))
print('杂怪 49 + 新增 %d = %d'%(len(add),len(allm)))
en=allm+SEAL
print('覆盖 240 =',all(min(d(g,q) for q in en)<=240 for _,g in G))
print('最大「采集→最近怪」= %.0f'%max(min(d(g,q) for q in en) for _,g in G))
MER=(1792.0,1262.9); SP=(1792.0,1536.0)
print('最近敌人→商人 %.0f / →出生点 %.0f'%(min(d(p,MER) for p in en), min(d(p,SP) for p in en)))
print('刷怪两两最小 %.0f'%min(d(a,b) for i,a in enumerate(en) for b in en[i+1:]))
print('刷怪→手工定点最小 %.0f'%min(min(d(p,s) for s in SITES) for p in en))
print()
print('--- GDScript 补点 ---')
ARCH={1:["猛兽","智谋","猛兽"],2:["蛮兽","猛兽","智谋"],3:["蛮兽","智谋","猛兽"],4:["蛮兽","智谋","蛮兽"]}
for k,p in enumerate(add):
    r=V.ring(*p)
    print('\t{"id": "m%02d", "archetype": "%s", "pos": Vector2(%d.0, %d.0), "ring": %d},'%(50+k,ARCH[r][k%len(ARCH[r])],p[0],p[1],r))
