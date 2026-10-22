"""量化对比：新攻击帧 vs 现有 p4_r.png —— 亮度、颜色数、描边占比。
用来说清「为什么两张图放一起会觉得新图更亮/更清楚」。
"""
from PIL import Image
import glob, statistics

def stats(path, label):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    px = im.load()
    lum, cols, edge = [], set(), 0
    solid = 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 40:
                continue
            if r > 244 and g > 244 and b > 244:
                continue
            solid += 1
            lum.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
            cols.add((r // 8, g // 8, b // 8))
            if (r + g + b) / 3 < 60:
                edge += 1
    print(f"{label:<26} 不透明 {solid:>6}  平均亮度 {statistics.mean(lum):6.1f}  "
          f"暗部占比 {edge/solid*100:5.1f}%  颜色数 {len(cols):>4}")
    return statistics.mean(lum)

print("== 归一后的攻击帧（1024 原图，仅看趋势）==")
for p in sorted(glob.glob(r"C:\Users\Administrator\Desktop\photo\攻击\*.png")):
    stats(p, p.split("\\")[-1])

print("\n== 现有 192 成品 ==")
for p in sorted(glob.glob(r"art\units_hd\*.png")):
    stats(p, p.split("\\")[-1])
