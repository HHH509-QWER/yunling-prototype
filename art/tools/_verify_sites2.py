import sys, math
sys.path.insert(0,'art/tools')
from _verify_sites import ring, rho, terrain, deep, walk, reachable

HAND = [
 ("M01","秘境",1,(2640,912),"玄甲印 rank2"),
 ("M02","秘境",2,(2960,1456),"rank3"),
 ("M03","秘境",2,(1168,2608),"rank3"),
 ("M04","秘境",3,(3280,2448),"rank4"),
 ("M05","秘境",3,(1456,240),"rank4"),
 ("M06","秘境",4,(112,2864),"rank5"),
 ("N01","妖巢",1,(912,1808),""),
 ("N02","妖巢",2,(1808,2608),""),
 ("N03","妖巢",3,(2800,2832),""),
 ("N04","妖巢",3,(2192,2800),""),
 ("N05","妖巢",4,(144,848),""),
 ("N06","妖巢",4,(3472,2896),""),
 ("T01","灵潮",1,(2544,1712),""),
 ("T02","灵潮",2,(2928,2000),""),
 ("T03","灵潮",3,(432,1488),""),
 ("T04","灵潮",4,(1936,176),""),
 ("R01","灵材富集",2,(560,656),""),
 ("R02","灵材富集",3,(3248,592),""),
 ("R03","灵材富集",3,(720,2704),""),
 ("R04","灵材富集",4,(3440,1232),""),
 ("R05","灵材富集",4,(144,2000),""),
 ("R06","灵材富集",4,(1424,2960),""),
 ("P01","灵市",2,(2288,2384),""),
 ("P02","灵市",3,(2288,432),""),
 ("P03","灵市",4,(3376,1744),""),
 ("P04","灵市",4,(816,176),""),
 ("Y01","印源",2,(560,2160),""),
 ("Y02","印源",3,(2704,272),""),
 ("Y03","印源",4,(176,2448),""),
 ("Y04","印源",4,(3472,176),""),
]

GATHER = {
 1:[(2352,976),(2704,1968),(1168,944),(1456,976),(2224,2224),(1424,2064)],
 2:[(2192,592),(1232,496),(688,880),(752,1776),(2608,2640),(656,1232)],
 3:[(1904,368),(2832,336),(1360,2800),(784,272),(3216,2064),(3184,1232),(464,2768)],
 4:[(2096,176),(496,112),(112,1136),(3472,2800),(3376,1776),(3408,816),(112,112)],
}

MOBS = {
 1:[(1040,1776),(880,2160),(2480,2256),(2640,1552),(1008,1968),(1488,784),(1968,2288)],
 2:[(624,2224),(1328,2480),(880,2608),(2352,2384),(1360,624),(880,2384),(2704,560),(2800,2416),(2640,752),(2992,2480),(816,1136)],
 3:[(688,2768),(2608,400),(304,784),(1616,368),(2448,2864),(912,2832),(3280,368),(1968,2800),(368,368),(528,752),(368,1136),(3152,2256),(1552,2768),(3120,2832)],
 4:[(112,2384),(1616,112),(1072,144),(240,2736),(1136,2896),(2096,2960),(176,912),(2352,144),(2672,176),(3472,2512),(208,1328),(240,2256),(3376,1360),(3376,2352),(176,1648),(2864,2928),(400,2960),(1072,144)],
}

SEAL5 = [("e07","流风印",(868,640)),("e08","辉光印",(1776,688)),("e09","云雨印",(2772,2261.3)),
         ("e12","惊雷印",(3388,362.7),True),("e13","磐石印",(3360,2816),True)]

CITY=(1280,1024,2304,2048)
def in_city(p): return CITY[0]<=p[0]<=CITY[2] and CITY[1]<=p[1]<=CITY[3]
def d(a,b): return math.dist(a,b)
MERCHANT=(1792.0,1262.9); SPAWN=(1792.0,1536.0)

def report():
    bad=[]
    print("=== 30 手工定点 ===")
    for i,(sid,ty,rg,p,note) in enumerate(HAND):
        r=ring(*p); t=terrain(*p)
        iss=[]
        if r!=rg: iss.append("ring声明%d实%d"%(rg,r))
        if t=="水泽": iss.append("水泽")
        if deep(*p): iss.append("深水")
        if in_city(p): iss.append("在主城内")
        if not reachable(*p): iss.append("不可达")
        if iss: bad.append((sid,p,iss))
        print("%-4s %-5s 声明L%d 实L%d rho=%.4f %s %s %s"%(sid,ty,rg,r,rho(*p),t,
              "深水" if deep(*p) else "干", " ".join(iss)))
    print("--- 两两间距 <420 ---")
    for i in range(len(HAND)):
        for j in range(i+1,len(HAND)):
            dd=d(HAND[i][3],HAND[j][3])
            if dd<420: print("  %s-%s %.1f"%(HAND[i][0],HAND[j][0],dd)); bad.append((HAND[i][0]+"/"+HAND[j][0],None,["间距%.0f"%dd]))
    print("=== 采集 26 ===")
    gs=[]
    for rg in sorted(GATHER):
        for p in GATHER[rg]:
            r=ring(*p); gs.append((rg,p))
            iss=[]
            if r!=rg: iss.append("ring声明%d实%d"%(rg,r))
            if terrain(*p)=="水泽": iss.append("水泽")
            if deep(*p): iss.append("深水")
            if in_city(p): iss.append("在主城内")
            if iss: bad.append(("gather%s"%str(p),p,iss)); print("  !!",p,iss)
    print("  数量",len(gs))
    for i in range(len(gs)):
        for j in range(i+1,len(gs)):
            dd=d(gs[i][1],gs[j][1])
            if dd<240: print("  !! 采集间距 %.1f %s %s"%(dd,gs[i][1],gs[j][1])); bad.append(("gather间距",None,["%.0f"%dd]))
    print("=== 杂怪 ===")
    ms=[]
    for rg in sorted(MOBS):
        for p in MOBS[rg]:
            r=ring(*p); ms.append((rg,p))
            iss=[]
            if r!=rg: iss.append("ring声明%d实%d"%(rg,r))
            if terrain(*p)=="水泽": iss.append("水泽")
            if deep(*p): iss.append("深水")
            if in_city(p): iss.append("在主城内")
            if iss: bad.append(("mob%s"%str(p),p,iss)); print("  !!",p,iss)
    print("  数量",len(ms))
    dup=[]
    for i in range(len(ms)):
        for j in range(i+1,len(ms)):
            dd=d(ms[i][1],ms[j][1])
            if dd<180: print("  !! 杂怪间距 %.1f %s %s"%(dd,ms[i][1],ms[j][1])); dup.append((ms[i][1],ms[j][1],dd))
    print("=== 采集点 240px 内有杂怪？ ===")
    need=[]
    for rg,p in gs:
        best=min((d(p,q) for _,q in ms), default=1e9)
        if best>240: need.append((p,best))
        print("  %-14s 最近杂怪 %.1f %s"%(str(p),best,"需要补点" if best>240 else ""))
    print("=== 印出处 5 ===")
    for s in SEAL5:
        p=s[2]; print("  %-4s %-5s rho=%.4f L%d %s 深水=%s 可达=%s"%(s[0],s[1],rho(*p),ring(*p),terrain(*p),deep(*p),reachable(*p)))
    print("=== 汇总问题 ===")
    for b in bad: print("  ",b)
    print("  需补杂怪点:",need)
    return bad,need,dup

report()
