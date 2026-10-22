from PIL import Image
import glob, os

def load(path):
    return Image.open(path).convert("RGBA")

def solid_mask(im):
    w, h = im.size
    px = im.load()
    m = []
    for y in range(h):
        row = []
        for x in range(w):
            r, g, b, a = px[x, y]
            row.append(a >= 40 and not (r > 244 and g > 244 and b > 244))
        m.append(row)
    return m

def band_x(m, y0, y1):
    xs = [x for y in range(y0, y1) for x in range(len(m[y])) if m[y][x]]
    if not xs:
        return None
    return min(xs), max(xs), (min(xs) + max(xs)) / 2.0

files = sorted(glob.glob(r"C:\Users\Administrator\Desktop\photo\攻击\*.png"))
print("frame, bbox_w, bbox_h, foot_center, foot_x0, foot_x1, head_center, body_center")
data = []
for p in files:
    im = load(p)
    m = solid_mask(im)
    h = len(m); w = len(m[0])
    ys = [y for y in range(h) if any(m[y])]
    y1 = max(ys)
    # 脚：最底下 36px
    foot = band_x(m, max(0, y1 - 36), y1 + 1)
    # 头：最上面 90px
    head = band_x(m, min(ys), min(ys) + 90)
    # 全身
    body = band_x(m, 0, h)
    data.append((os.path.basename(p), body[1] - body[0] + 1, y1 - min(ys) + 1,
                 foot[2], foot[0], foot[1], head[2], (body[0] + body[1]) / 2.0))
    print(f"{data[-1][0]:<26} {data[-1][1]:>4} {data[-1][2]:>4}  foot_cx={foot[2]:>7.1f} "
          f"({foot[0]},{foot[1]})  head_cx={head[2]:>7.1f}  body_cx={(body[0]+body[1])/2.0:>7.1f}")

print()
fcs = [d[3] for d in data]
hcs = [d[6] for d in data]
print(f"脚心横向漂移 = {max(fcs)-min(fcs):.1f}px（原图 1024 尺度）")
print(f"头心横向漂移 = {max(hcs)-min(hcs):.1f}px")
print()
print("以脚心为锚、按最高帧归一（k = 192 / max_h）后，每帧在 192 画布里的位置：")
maxh = max(d[2] for d in data)
k = 192.0 / maxh
for d in data:
    bw = d[1] * k
    # 脚心相对 bbox 左边的偏移
    left_off = (d[3] - d[4]) * k
    print(f"  {d[0]:<26} 高 {d[2]*k:6.1f}  宽 {bw:6.1f}  脚心在 bbox 左侧 {left_off:6.1f}px 处")
print(f"\nk = {k:.6f}")
