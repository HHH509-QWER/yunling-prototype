"""在**真实游戏尺寸**下看四帧：192 画布 × 0.25 世界缩放 × 2 相机缩放 = 96px 屏高。
这一段是为了判断「那些细节缺陷到底看不看得见」——放大 8 倍时刺眼的东西，实际游戏里往往不存在。
"""
from PIL import Image
import glob

SRC = sorted(glob.glob(r"C:\Users\Administrator\Desktop\photo\攻击\*.png"))
CANVAS, FOOT_ROW = 192, 191
SCREEN = 96          # 屏高（zoom 2）
VIEW = 3             # 交付图再放大 3 倍，便于在对话里看清


def to_alpha(im):
    im = im.convert("RGBA"); px = im.load(); w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 40 or (r > 244 and g > 244 and b > 244):
                px[x, y] = (0, 0, 0, 0)
    return im


def bounds(im):
    px = im.load(); w, h = im.size
    pts = [(x, y) for y in range(h) for x in range(w) if px[x, y][3] > 0]
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def foot_cx(im, y1):
    px = im.load(); w, _ = im.size
    xs = [x for y in range(max(0, y1 - 36), y1 + 1) for x in range(w) if px[x, y][3] > 0]
    return (min(xs) + max(xs)) / 2.0


raw, hs = [], []
for p in SRC:
    im = to_alpha(Image.open(p))
    x0, y0, x1, y1 = bounds(im)
    raw.append((im, x0, y0, x1, y1)); hs.append(y1 - y0 + 1)
k = CANVAS / float(max(hs))

frames = []
for (im, x0, y0, x1, y1) in raw:
    cx = foot_cx(im, y1)
    bw = int(round((x1 - x0 + 1) * k)); bh = int(round((y1 - y0 + 1) * k))
    crop = im.crop((x0, y0, x1 + 1, y1 + 1)).resize((bw, bh), Image.NEAREST)
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.alpha_composite(crop, (int(round(CANVAS / 2.0 - (cx - x0) * k)), FOOT_ROW - bh + 1))
    frames.append(canvas)

# 真实屏高 96px：192 → 96 用 LANCZOS（模拟 GPU 线性采样），再 ×VIEW 放大看
items = frames + [Image.open(r"art\units_hd\p4_r.png").convert("RGBA")]
cell = SCREEN * VIEW
strip = Image.new("RGB", (cell * len(items), cell + 24), (30, 34, 30))
for i, im in enumerate(items):
    small = im.resize((SCREEN, SCREEN), Image.LANCZOS)
    strip.paste(small.resize((cell, cell), Image.NEAREST), (i * cell, 24))
strip.save(r"art\tools\preview_attack_actual_size.png")
print("实际尺寸对比:", strip.size, "（每格 = 96px 屏高放大 3 倍；背景是草地绿）")
