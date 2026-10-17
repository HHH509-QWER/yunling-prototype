# ⚠️ 一次性脚本（Step 0.2）：删掉 wscl 双重坐标系
#
# 背景：GameData 里的坐标一直写在「1280×720 设计空间」里，运行时由 Game.gd 乘
#   wscl = WORLD["size"] / Vector2(1280, 720)
# 才变成世界坐标 —— 于是同一个工程里同时存在两套坐标。
#
# 做法：把乘完的**真坐标**直接写回数据表，Game.gd 不再乘。
#
# ⭐ 缩放系数怎么来的（两步合一，与存档迁移 v8 完全同一套比例）：
#     旧：设计坐标 × (4, 4)              = 旧世界(5120×2880)里的真坐标
#     再：× (3584/5120, 3072/2880)       = 新世界(3584×3072)里的真坐标  ← 存档迁移 v8 的比例
#   合起来就是 设计坐标 × (3584/1280, 3072/720) = × (2.8, 4.2667)
#   这也正是当前运行时 wscl 的值 —— 所以本脚本是**行为等价**改写，跑完自测应当一条不动。
#
# 跑法：python art/tools/once_bake_world_coords.py
# 复核：git diff scripts/GameData.gd

import re

SRC = "scripts/GameData.gd"
SX = 3584.0 / 1280.0      # 2.8
SY = 3072.0 / 720.0       # 4.2666...
OLD = (5120.0, 2880.0)
NEW = (3584.0, 3072.0)

VEC = re.compile(r"Vector2\(\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*\)")


def scale(m):
    x = round(float(m.group(1)) * SX, 1)
    y = round(float(m.group(2)) * SY, 1)
    return "Vector2(%.1f, %.1f)" % (x, y)


def span(text, start_pat, open_ch="[", close_ch="]"):
    """从 start_pat 处开始，返回平衡括号内的 (起, 止) 下标。"""
    i = text.index(start_pat)
    j = text.index(open_ch, i)
    depth = 0
    k = j
    while k < len(text):
        if text[k] == open_ch:
            depth += 1
        elif text[k] == close_ch:
            depth -= 1
            if depth == 0:
                return j, k + 1
        k += 1
    raise RuntimeError("括号不平衡: " + start_pat)


def rewrite(text, blocks):
    """blocks: [(标签, 起始 pattern)] —— 按从后往前改，避免下标错位。"""
    edits = []
    for label, pat in blocks:
        j, k = span(text, pat)
        edits.append((label, j, k))
    for label, j, k in sorted(edits, key=lambda e: -e[1]):
        new = VEC.sub(scale, text[j:k])
        n = len(VEC.findall(text[j:k]))
        text = text[:j] + new + text[k:]
        print("  %-14s 改了 %d 个坐标" % (label, n))
    return text


src = open(SRC, encoding="utf-8", newline="").read()

print("缩放系数: ×(%.4f, %.4f)   （旧世界 %s → 新世界 %s 的同一套比例）"
      % (SX, SY, OLD, NEW))

src = rewrite(src, [
    ("ENEMY_SPAWNS", 'const ENEMY_SPAWNS := ['),
    ("GATHER.spots", '"spots": ['),
    ("DUMMY.spawns", '"spawns": ['),
])

# MERCHANT.pos 是单个 Vector2，不是数组
i = src.index('const MERCHANT := {')
j = src.index('"pos":', i)
k = src.index("\n", j)
new = VEC.sub(scale, src[j:k])
print("  %-14s 改了 %d 个坐标" % ("MERCHANT.pos", len(VEC.findall(src[j:k]))))
src = src[:j] + new + src[k:]

# ⚠️ newline="" —— 工程文件是 LF，直接写会被 Windows Python 翻成 CRLF（整文件 diff）
open(SRC, "w", encoding="utf-8", newline="").write(src)
print("已写回 " + SRC)
