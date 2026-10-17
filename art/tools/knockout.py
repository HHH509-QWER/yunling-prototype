import sys, numpy as np
from PIL import Image
from collections import deque
src, out = sys.argv[1], sys.argv[2]
im = Image.open(src).convert('RGBA')
a = np.array(im); h, w = a.shape[:2]
rgb = a[:, :, :3].astype(np.int16)
grey = (rgb.max(axis=2) - rgb.min(axis=2)) < 16
white = grey & (rgb.min(axis=2) > 228)
# ⭐ 只吃掉与图边连通的白色：白袍在内部，不会被误伤
vis = np.zeros((h, w), bool); dq = deque()
for x in range(w):
    for y in (0, h - 1):
        if white[y, x] and not vis[y, x]: vis[y, x] = True; dq.append((y, x))
for y in range(h):
    for x in (0, w - 1):
        if white[y, x] and not vis[y, x]: vis[y, x] = True; dq.append((y, x))
while dq:
    y, x = dq.popleft()
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        ny, nx = y + dy, x + dx
        if 0 <= ny < h and 0 <= nx < w and white[ny, nx] and not vis[ny, nx]:
            vis[ny, nx] = True; dq.append((ny, nx))
a[:, :, 3] = np.where(vis, 0, 255)
ys, xs = np.where(a[:, :, 3] > 8)
if len(ys) == 0: print('EMPTY'); sys.exit(1)
y0, y1, x0, x1 = int(ys.min()), int(ys.max()), int(xs.min()), int(xs.max())
im2 = Image.fromarray(a).crop((x0, y0, x1 + 1, y1 + 1))
TARGET_H, MARGIN = 192, 8
th2 = TARGET_H - MARGIN
tw2 = max(1, round(im2.width * th2 / im2.height))
im3 = im2.resize((tw2, th2), Image.LANCZOS)
canvas = Image.new('RGBA', (tw2, TARGET_H), (0, 0, 0, 0))
canvas.alpha_composite(im3, (0, 0))
canvas.save(out)
print('ok size=%dx%d content=%dx%d src=%dx%d' % (tw2, TARGET_H, x1 - x0 + 1, y1 - y0 + 1, w, h))