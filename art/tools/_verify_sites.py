import sys, math
sys.path.insert(0,'art/tools')
from pixel_gap import decode_png
W,H,RGB,_,_ = decode_png('art/world/worldmap.png')   # 112x96, rgb 3B
COLS,ROWS,CELL = 112,96,32.0
WSX,WSY = COLS*CELL, ROWS*CELL
CX,CY = WSX/2, WSY/2
THR=[0.52,0.71,0.86]
TERR=["水泽","草地","竹林","灵岩","灵田","泥沼"]

def cell(cx,cy):
    i=(cy*W+cx)*3
    return tuple(RGB[i:i+3])

def ring(x,y):
    rho=max(abs(x-CX)/CX, abs(y-CY)/CY)
    for i,t in enumerate(THR):
        if rho<=t: return i+1
    return 4

def rho(x,y):
    return max(abs(x-CX)/CX, abs(y-CY)/CY)

def terrain(x,y):
    cx=int(x//CELL); cy=int(y//CELL)
    r,g,b=cell(min(cx,COLS-1),min(cy,ROWS-1))
    return TERR[max(0,min(5,int(round(r*255/50.0))))]

def depth(x,y):
    cx=int(x//CELL); cy=int(y//CELL)
    r,g,b=cell(min(cx,COLS-1),min(cy,ROWS-1))
    return b

def deep(x,y):   # 深水口径：B >= 128
    return depth(x,y)>=128

def walk(x,y):
    return not deep(x,y)

# BFS 可达（从出生点，4邻域，只走非深水）
from collections import deque
def reachable(tx,ty):
    sx,sy=int(CX//CELL),int(CY//CELL)
    tx2,ty2=int(tx//CELL),int(ty//CELL)
    seen=bytearray(COLS*ROWS); q=deque()
    if deep(CX,CY): return False
    seen[sy*COLS+sx]=1; q.append((sx,sy))
    while q:
        x,y=q.popleft()
        if (x,y)==(tx2,ty2): return True
        for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
            nx,ny=x+dx,y+dy
            if 0<=nx<COLS and 0<=ny<ROWS and not seen[ny*COLS+nx]:
                seen[ny*COLS+nx]=1
                if not deep(nx*CELL+1,ny*CELL+1): q.append((nx,ny))
    return False

def pool():
    cnt=[0,0,0,0]; g128=0
    for cy in range(ROWS):
        for cx in range(COLS):
            x,y=cx*CELL+1,cy*CELL+1
            if deep(x,y): continue
            r=ring(x,y); cnt[r-1]+=1
            if cell(cx,cy)[2]==128: g128+=1
    return cnt,g128

if __name__=='__main__':
    print('pool(4层可走格) =',pool()[0],' total',sum(pool()[0]),' B==128的格数',pool()[1])
    for nm,(x,y) in [('e07',(868,640)),('e08old',(3052,896)),('e08new',(1776,688)),
                     ('e09',(2772,2261.3)),('e02',(2940,640)),('e12',(3388,362.7)),('e13',(3360,2816))]:
        print('%-8s rho=%.4f L%d terr=%s deep=%s reach=%s'%(nm,rho(x,y),ring(x,y),terrain(x,y),deep(x,y),reachable(x,y)))
