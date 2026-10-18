#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
⭐ M31.3：**像素级暗缝统计（常驻工具）**。

为什么要有它：这轮已经**眼误两次 + 数据错一次** ——
  ① 把暗紫暗块当成地形，得出"实测 0% 未覆盖"；
  ② 把暗紫暗块当成地形，得出"三帧全覆盖无黑洞"；
  ③ 取景没钉住（相机平滑没收敛 / 玩家被拉回），24.2/10.5/3.7 那组基线作废。
⇒ team-lead 定案：**验证必须像素级，不许肉眼**。这个脚本就是那把尺。

做法：抓到的 PNG 里，"没有任何格子盖到"的地方就是 **clear color (15,18,20)**。
  把它抠出来做 4 邻域连通块统计：
    - bg%      ：底色像素占全图的比例（未覆盖率）
    - 块(≥N px)：面积 ≥ N 的连通块个数（"特征块" —— 一条缝 = 一格宽 64 × 缝高）
    - 最大块   ：最大连通块面积（px）

用法：
  python art/tools/pixel_gap.py art/tools/preview_xxx.png [更多 png...]
  python art/tools/pixel_gap.py art/tools/preview_*.png --min-area 200 --tol 6

⚠️ 只用标准库（PIL 在这台机器上装不了）：自己解 PNG（zlib + 反滤波）。
"""

import sys
import zlib
import struct
from collections import deque

CLEAR = (15, 18, 20)          # 工程 clear color（project.godot / RenderingServer 默认背景）
DEFAULT_TOL = 6               # 每通道允许偏差（后处理泛光/暗角会把底色轻微染色）
DEFAULT_MIN_AREA = 200        # "特征块" 门槛：一条一级台阶的缝 ≈ 64×21 ≈ 1344 px


def decode_png(path):
    """返回 (w, h, bytearray) —— 每像素 3 字节 RGB。只支持 8bit 非隔行（本项目出图都是这种）。"""
    with open(path, "rb") as f:
        data = f.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "不是 PNG: %s" % path
    pos = 8
    idat = bytearray()
    w = h = depth = ctype = None
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos + 4])[0]
        typ = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + ln]
        if typ == b"IHDR":
            w, h, depth, ctype, comp, filt, inter = struct.unpack(">IIBBBBB", body)
            assert depth == 8, "只支持 8bit，实际 %d" % depth
            assert ctype in (2, 6), "只支持 RGB/RGBA，实际 %d" % ctype
            assert inter == 0, "不支持隔行"
        elif typ == b"IDAT":
            idat += body
        elif typ == b"IEND":
            break
        pos += 12 + ln
    raw = zlib.decompress(bytes(idat))
    nch = 3 if ctype == 2 else 4
    stride = w * nch
    out = bytearray(w * h * 3)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        ft = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
        if ft == 1:
            for i in range(nch, stride):
                line[i] = (line[i] + line[i - nch]) & 0xFF
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ft == 3:
            for i in range(stride):
                a = line[i - nch] if i >= nch else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif ft == 4:
            for i in range(stride):
                a = line[i - nch] if i >= nch else 0
                b = prev[i]
                c = prev[i - nch] if i >= nch else 0
                pp = a + b - c
                pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        row_off = y * w * 3
        for x in range(w):
            s = x * nch
            out[row_off + x * 3: row_off + x * 3 + 3] = line[s:s + 3]
        prev = line
    return w, h, out, nch, raw[:0]


def build_mask(w, h, rgb, tol):
    """True = 底色（没有格子盖到）"""
    mask = bytearray(w * h)
    cr, cg, cb = CLEAR
    for i in range(w * h):
        r = rgb[i * 3]
        g = rgb[i * 3 + 1]
        b = rgb[i * 3 + 2]
        if abs(r - cr) <= tol and abs(g - cg) <= tol and abs(b - cb) <= tol:
            mask[i] = 1
    return mask


def components(w, h, mask, min_area):
    """4 邻域连通块；返回 (块数≥min_area, 最大面积, 全部面积降序前 8)"""
    seen = bytearray(w * h)
    areas = []
    q = deque()
    for s in range(w * h):
        if not mask[s] or seen[s]:
            continue
        seen[s] = 1
        q.clear()
        q.append(s)
        area = 0
        while q:
            i = q.popleft()
            area += 1
            x = i % w
            y = i // w
            if x > 0 and mask[i - 1] and not seen[i - 1]:
                seen[i - 1] = 1
                q.append(i - 1)
            if x < w - 1 and mask[i + 1] and not seen[i + 1]:
                seen[i + 1] = 1
                q.append(i + 1)
            if y > 0 and mask[i - w] and not seen[i - w]:
                seen[i - w] = 1
                q.append(i - w)
            if y < h - 1 and mask[i + w] and not seen[i + w]:
                seen[i + w] = 1
                q.append(i + w)
        areas.append(area)
    areas.sort(reverse=True)
    big = [a for a in areas if a >= min_area]
    return len(big), (areas[0] if areas else 0), areas[:8]


def sky_split(w, h, mask):
    """从屏幕**顶边**对底色做 4 邻域灌洪 ⇒ 顶边连得上的 = 天空带（地形轮廓上方，
    真实画面由远山/云雾盖住，不是缝）；剩下的底色 = 被地形包住的**真缝**。
    返回 (sky_px, seam_px)。"""
    seen = bytearray(w * h)
    q = deque()
    for x in range(w):
        if mask[x]:
            seen[x] = 1
            q.append(x)
    while q:
        i = q.popleft()
        x = i % w
        y = i // w
        for j in (i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1,
                  i - w if y > 0 else -1, i + w if y < h - 1 else -1):
            if j >= 0 and mask[j] and not seen[j]:
                seen[j] = 1
                q.append(j)
    sky = sum(seen)
    return sky, sum(mask) - sky


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    tol = DEFAULT_TOL
    min_area = DEFAULT_MIN_AREA
    for i, a in enumerate(sys.argv[1:]):
        if a == "--min-area":
            min_area = int(sys.argv[1:][i + 1])
        elif a == "--tol":
            tol = int(sys.argv[1:][i + 1])
    if not args:
        print(__doc__)
        return
    print("clear=%s tol=%d min_area=%d" % (CLEAR, tol, min_area))
    print("%-30s %7s %8s %8s %10s  %s" % (
            "file", "bg%", "缝%", "缝块", "最大缝px", "前8缝面积"))
    for path in args:
        w, h, rgb, _nch, _ = decode_png(path)
        mask = build_mask(w, h, rgb, tol)
        tot = sum(mask)
        sky, seam = sky_split(w, h, mask)
        tot = sum(mask)
        seam_n, seam_max, seam_top = seam_components(w, h, mask, min_area)
        name = path.replace("\\", "/").split("/")[-1]
        print("%-30s %6.1f%% %7.1f%% %8d %10d  %s"
              % (name, tot * 100.0 / (w * h), seam * 100.0 / (w * h),
                 seam_n, seam_max, seam_top))


def seam_components(w, h, mask, min_area):
    """只统计**不与顶边天空相连**的底色连通块（= 真缝/包住的洞）"""
    seen = bytearray(w * h)
    sky = bytearray(w * h)
    q = deque()
    for x in range(w):
        if mask[x]:
            seen[x] = 1
            sky[x] = 1
            q.append(x)
    while q:
        i = q.popleft()
        x = i % w
        y = i // w
        for j in (i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1,
                  i - w if y > 0 else -1, i + w if y < h - 1 else -1):
            if j >= 0 and mask[j] and not seen[j]:
                seen[j] = 1
                sky[j] = 1
                q.append(j)
    areas = []
    done = bytearray(w * h)
    for s in range(w * h):
        if mask[s] and not sky[s] and not done[s]:
            done[s] = 1
            q.clear()
            q.append(s)
            area = 0
            while q:
                i = q.popleft()
                area += 1
                x = i % w
                y = i // w
                for j in (i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1,
                          i - w if y > 0 else -1, i + w if y < h - 1 else -1):
                    if j >= 0 and mask[j] and not sky[j] and not done[j]:
                        done[j] = 1
                        q.append(j)
            areas.append(area)
    areas.sort(reverse=True)
    big = [a for a in areas if a >= min_area]
    return len(big), (areas[0] if areas else 0), areas[:8]


if __name__ == "__main__":
    main()
