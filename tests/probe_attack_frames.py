from PIL import Image
import glob, os, sys

def analyze(path, label):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    px = im.load()
    # 白底 -> 视为空（这批素材是白底不透明的）
    def solid(x, y):
        r, g, b, a = px[x, y]
        if a < 40:
            return False
        return not (r > 244 and g > 244 and b > 244)
    xs, ys = [], []
    for y in range(h):
        for x in range(w):
            if solid(x, y):
                xs.append(x); ys.append(y)
    if not xs:
        print(f"{label}: 空图")
        return None
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    res = dict(label=label, w=w, h=h, x0=x0, x1=x1, y0=y0, y1=y1,
               bw=x1 - x0 + 1, bh=y1 - y0 + 1, foot=y1, wpx=w - (x1 - x0 + 1))
    print(f"{label:<26} 画布{w}x{h}  bbox=({x0},{y0})-({x1},{y1})  "
          f"宽{res['bw']:>4} 高{res['bh']:>4}  脚底行{y1:>4}  左右留白(x0/右边)={x0}/{w-1-x1}")
    return res

print("==== 攻击帧（1024 原图）====")
rows = []
for p in sorted(glob.glob(r"C:\Users\Administrator\Desktop\photo\攻击\*.png")):
    rows.append(analyze(p, os.path.basename(p)))

if rows:
    hs = [r["bh"] for r in rows]
    ft = [r["foot"] for r in rows]
    print(f"\n身高范围 {min(hs)}..{max(hs)}（差 {max(hs)-min(hs)}px）")
    print(f"脚底行范围 {min(ft)}..{max(ft)}（差 {max(ft)-min(ft)}px）")
    # 按身高归一：k = 48/max_h，看每帧缩放后脚底落在哪
    kmax = max(hs)
    k = 48.0 / kmax
    print(f"\n若按「最高帧=48」共用系数 k={k:.5f}：")
    for r in rows:
        print(f"  {r['label']:<26} 高 {r['bh']*k:5.1f}  宽 {r['bw']*k:5.1f}")

print("\n==== 现有立绘（192 成品）====")
for p in sorted(glob.glob(r"art\units_hd\p4_*.png")):
    analyze(p, os.path.basename(p))
