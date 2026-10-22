import sys, math, json
sys.path.insert(0,'art/tools')
import _verify_sites as V
def terrain(x,y):
    cx=int(x//32); cy=int(y//32)
    return V.TERR[max(0,min(5,int(round(V.cell(min(cx,111),min(cy,95))[0]/50.0))))]
def d(a,b): return math.dist(a,b)
from _verify_sites2 import GATHER, MOBS, SEAL5
CITY=lambda p: 1280<=p[0]<=2304 and 1024<=p[1]<=2048
MOVEM={(2448,2864):(2448,2832),(528,752):(496,752)}
others=list(dict.fromkeys([MOVEM.get(p,p) for r in (1,2,3,4) for p in MOBS[r]]))
print('=== (2640,752) 挪位候选（目标 L2，且离所有其它杂怪>=180）===')
for cand in [(2640,720),(2768,752),(2800,752),(2752,720),(2768,720),(2736,736),(2800,720),(2640,704),(2720,704)]:
    md=min(d(cand,q) for q in others)
    print('  %-13s L%d rho%.4f minDist%.0f %s'%(str(cand),V.ring(*cand),V.rho(*cand),md,
        'OK' if (md>=180 and V.ring(*cand)==2 and not V.deep(*cand) and terrain(*cand)!='水泽') else 'no'))
