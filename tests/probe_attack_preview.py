"""把四张攻击帧按**脚心对齐**归一成 192 画布，并拼一张对比图（含现有 p4_r 作比例参考）。

为什么要单独写这个：这批素材的 bbox 中心会随手臂伸缩来回跑 125px（原图尺度），
如果按「包围盒居中」放画布，人物会左右滑。必须用**脚心**当横向锚点。
"""
from PIL import Image
import glob, os

SRC = sorted(glob.glob(r"C:\Users\Administrator\Desktop\photo\攻击\*.png"))
CANVAS = 192
FOOT_ROW = 191
K_UP = 4               # 预览放大倍数
OUT = r"art\tools\preview_attack.png"


def mask_bounds(im):
    w, h = im.size
    px = im.load()
    pts = []
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a >= 40 and not (r > 244 and g > 244 and b > 244):
                pts.append((x, y))
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def to_alpha(im):
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 40 or (r > 244 and g > 244 and b > 244):
                px[x, y] = (0, 0, 0, 0)
    return im


def foot_cx(im, y1):
    px = im.load()
    w, _ = im.size
    xs = [x for y in range(max(0, y1 - 36), y1 + 1) for x in range(w) if px[x, y][3] > 0]
    return (min(xs) + max(xs)) / 2.0


# 1) 先算共用缩放系数：四帧里最高的那帧 = 192
raw = []
heights = []
for p in SRC:
    im = to_alpha(Image.open(p))
    x0, y0, x1, y1 = mask_bounds(im)
    raw.append((im, x0, y0, x1, y1))
    heights.append(y1 - y0 + 1)
k = CANVAS / float(max(heights))
print(f"共用系数 k = {k:.6f}（最高帧 {max(heights)}px → 192）")

# 2) 逐帧缩放 + 脚心居中
frames = []
for (im, x0, y0, x1, y1) in raw:
    cx = foot_cx(im, y1)
    bw = int(round((x1 - x0 + 1) * k))
    bh = int(round((y1 - y0 + 1) * k))
    crop = im.crop((x0, y0, x1 + 1, y1 + 1)).resize((bw, bh), Image.NEAREST)
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    left = int(round(CANVAS / 2.0 - (cx - x0) * k))
    top = FOOT_ROW - bh + 1
    canvas.alpha_composite(crop, (left, top))
    frames.append(canvas)
    xs = [x for y in range(CANVAS) for x in range(CANVAS) if canvas.load()[x, y][3] > 0]
    ys = [y for y in range(CANVAS) for x in range(CANVAS) if canvas.load()[x, y][3] > 0]
    print(f"  frame{len(frames)}: 192 画布内 x {min(xs)}..{max(xs)}  y {min(ys)}..{max(ys)}"
          f"  右侧余量 {CANVAS-1-max(xs)}")

# 3) 对比条：四帧 + p4_r（都放大 4 倍）
ref = Image.open(r"art\units_hd\p4_r.png").convert("RGBA")
items = frames + [ref]
W = CANVAS * K_UP
strip = Image.new("RGBA", (W * len(items), W), (24, 22, 20, 255))
for i, im in enumerate(items):
    big = im.resize((W, W), Image.NEAREST)
    strip.alpha_composite(big, (i * W, 0))
    # 中线：脚心应该都落在这条线上
    px = strip.load()
    for y in range(W):
        px[i * W + W // 2, y] = (90, 80, 60, 255)
strip.convert("RGB").save(OUT)
print("预览:", OUT, strip.size)
