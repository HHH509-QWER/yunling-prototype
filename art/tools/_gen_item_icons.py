"""M31.4：给两种新增顶层触媒生成 32×32 图标 + 8×8 掉落 token（**占位图**，美术可整张替换）。
⚠️ 只改 art/items/ 下这 4 个新文件，不碰任何已有图。
   替换方式：用同文件名覆盖即可（尺寸必须保持 32×32 / 8×8，代码不用动）。
"""
import zlib, struct, math, os

def write_png(path, w, h, rgba):
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            raw.extend(rgba[y*w+x])
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    open(path, "wb").write(png)

def gem(px, py, size, base, dark, light):
    """单个像素：八面体宝石——上半亮、下半暗，加一道左上高光和一圈暗边。"""
    cx = cy = (size - 1) / 2.0
    r = size / 2.0 - 1.5
    dx = (px - cx) / r
    dy = (py - cy) / r
    # 竖长一点的八面体（和雷髓那种"竖着的核"一致）
    d = abs(dx) ** 1.7 + abs(dy / 1.15) ** 1.7
    if d > 1.0:
        return (0, 0, 0, 0)
    if d > 0.80:
        return dark + (255,)                       # 暗边
    # 主面：左上偏亮、右下偏暗（一道斜向的棱）
    t = (dx + dy * 1.2) * 0.5                      # -1..1
    c = [base[i] + (light[i] - base[i]) * max(0.0, -t) * 0.9
         + (dark[i] - base[i]) * max(0.0, t) * 0.9 for i in range(3)]
    # 高光：左上偏上的一块
    hx, hy = -0.42, -0.42
    hl = max(0.0, 1.0 - math.dist((dx, dy), (hx, hy)) / 0.42)
    c = [c[i] + (255 - c[i]) * hl * 0.75 for i in range(3)]
    return (int(max(0, min(255, c[0]))), int(max(0, min(255, c[1]))),
            int(max(0, min(255, c[2]))), 255)

SPECS = {
    # 玄霜髓：冰蓝（和 MATERIALS.color Color(0.62,0.86,0.95) 同一套色）
    "frostcore": ((86, 168, 214), (34, 78, 116), (198, 240, 255)),
    # 太虚核：淡金（Color(0.90,0.80,0.45)）
    "voidcore":  ((214, 186, 100), (104, 84, 34), (255, 240, 190)),
}

os.makedirs("art/items", exist_ok=True)
for name, (base, dark, light) in SPECS.items():
    for size, suffix in ((32, ""), (8, "_drop")):
        w = h = size
        buf = [gem(x, y, size, base, dark, light) for y in range(h) for x in range(w)]
        p = "art/items/%s%s.png" % (name, suffix)
        write_png(p, w, h, buf)
        print("写出", p, "%dx%d" % (w, h))
