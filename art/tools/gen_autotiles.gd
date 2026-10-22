## ⭐ M33：**地表瓦片生成器（32×32，5 地形 × 16 掩码）**
##
## 为什么要有它 —— 旧的 `art/tiles/auto_*.png` 有四个硬伤，全部是"看起来难看"的直接原因：
##   ① **太暗**：底色 RGB 只有 20~40（0.08~0.15），乘上 `CanvasModulate` 之后整屏挤进 20 个灰阶，
##      草地 / 竹林 / 山岩在屏幕上读数几乎一样。
##   ② **同一张噪声换色**：四种地形共用一套纹样，只是色相不同 ⇒「竹林」读不出竹子，
##      只是一块更绿的地毯。地形身份必须由**纹样**承担，不能只由色相承担。
##   ③ **边带是「4px 近黑 + 1px 亮线」**：铺满屏之后，每条地形边界都是一圈亮框，远处看就是
##      「一块块黑色贴纸板」。分界应该靠**暗**（缝隙），不该靠**亮**（描边）。
##   ④ **泥沼根本没有瓦片**：`WORLD_TERRAINS` 有 6 种地形，`auto_*` 只做了 5 套，泥沼一直走纯色兜底。
##
## 这次一次全部重做：亮一档的底色 + 每种地形自己的纹样 + 「渐变暗边 + 无亮线」的边带 + 补齐泥沼。
##
## ⚠️ 三条纪律：
##   ① **固定种子**：每次跑出来完全一样（可复现，截图能对比）。随机好看不如可复现。
##   ② **只画纹样，不画光**：发光留给灵泉 / 阵法 / 灵印。地面一亮就抢戏，怪和掉落物就读不出来了。
##   ③ 掩码位序必须和 `Game._auto_tile()` 一致：bit0=N bit1=E bit2=S bit3=W，**1 = 邻居不同**。
##
## 跑法：写完后用 MCP 让编辑器重新导入（`filesystem_manage` op=reimport / scan），再重启游戏。
extends RefCounted

const N := 32

## 每种地形：底色区间 + 纹样频率 + 固定种子。
## 亮度整体比旧瓦片高一档（dark ≈ 0.10，light ≈ 0.24），配合 1.3 左右的环境光就够了。
const TERRAINS := {
	"草地": {"dark": Color(0.09, 0.12, 0.08), "light": Color(0.18, 0.23, 0.15), "freq": 3.0, "seed": 11},
	"竹林": {"dark": Color(0.07, 0.10, 0.06), "light": Color(0.15, 0.19, 0.10), "freq": 4.0, "seed": 23},
	"灵岩": {"dark": Color(0.11, 0.11, 0.13), "light": Color(0.21, 0.21, 0.25), "freq": 2.0, "seed": 37},
	"灵田": {"dark": Color(0.13, 0.13, 0.07), "light": Color(0.22, 0.21, 0.12), "freq": 3.0, "seed": 41},
	"泥沼": {"dark": Color(0.11, 0.09, 0.04), "light": Color(0.20, 0.16, 0.09), "freq": 2.5, "seed": 53},
}


## ⭐ 每种（地形 × 掩码）生成 **3 个变体**，运行时按格坐标哈希挑一个。
##    为什么：同一张 32px 图铺满屏，**任何有辨识度的纹样都会暴露重复** ——
##    32px 一个周期在 2× 缩放下就是 64px，眼睛一眼就能看出"格子"。
##    3 个变体把周期拉到 96px（世界单位）且完全不规则，重复感基本消失。
const VARIANTS := 3

func run() -> String:
	var made := 0
	var errors: Array = []
	for tn in TERRAINS:
		var spec: Dictionary = TERRAINS[tn]
		for v in VARIANTS:
			var rng := RandomNumberGenerator.new()
			## 种子按「地形种子 + 变体号」偏移 —— 每个变体纹样不同，但**可复现**
			rng.seed = int(spec["seed"]) + v * 1000
			var base := _make_base(spec["dark"], spec["light"], float(spec["freq"]))
			_motifs(base, tn, rng)
			for mask in 16:
				var img: Image = base.duplicate() as Image
				_apply_edges(img, mask)
				## ⚠️ 同时写两份：带变体号的（运行时首选）+ 不带变体号的（v0 的兼容兜底，
				##    保证「变体文件缺失」时 `_auto_tile` 还能退回旧路径而不是画成纯色）
				var p := "res://art/tiles/auto_%s_%d_%d.png" % [tn, mask, v]
				if not _save(img, p, errors):
					continue
				made += 1
				if v == 0:
					if _save(img, "res://art/tiles/auto_%s_%d.png" % [tn, mask], errors):
						made += 1
	return "写盘 %d 张，失败 %d 张 %s" % [made, errors.size(), str(errors)]


func _save(img: Image, p: String, errors: Array) -> bool:
	var err := img.save_png(p)
	if err != OK:
		# ⚠️ 有的环境里运行期 `res://` 不可写 —— 退到绝对路径，别静默失败
		err = img.save_png(ProjectSettings.globalize_path(p))
		if err != OK:
			errors.append("%s: %d" % [p, err])
			return false
	return true


# ---------------------------------------------------------------- 底纹

## 底色 + 大尺度明暗。用三角函数的**周期整数倍**当噪声 ⇒ 天然无缝（和 gen_tiles.mjs 同一套思路）。
func _make_base(dark: Color, light: Color, freq: float) -> Image:
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	for y in N:
		for x in N:
			var px := float(x) / N * TAU
			var py := float(y) / N * TAU
			var a := sin(px * freq) * cos(py * freq)
			var b := 0.5 * sin(px * freq * 2.3 + 1.7) * cos(py * freq * 1.7)
			var c := 0.25 * sin(px * freq * 3.0 + 3.1) * sin(py * freq * 2.1 + 0.7)
			var t := clampf((a + b + c + 1.6) / 3.2, 0.0, 1.0)
			img.set_pixel(x, y, dark.lerp(light, t))
	return img


func _motifs(img: Image, tn: String, rng: RandomNumberGenerator) -> void:
	match tn:
		"草地":
			# 草叶：细竖线，高矮不一（等长会像"刺"，不像草）
			## ⚠️ 对比度要**低**：纹样是地面，不是前景。第一版用 0.80 alpha，
			##    铺满屏后整片地像"撒了碎纸屑"，比原来的纯噪声还跳。
			for i in 18:
				var x := rng.randi_range(0, N - 1)
				var y := rng.randi_range(0, N - 1)
				var h := rng.randi_range(2, 4)
				for k in h:
					_add(img, x, y - k, Color(0.26, 0.35, 0.19), 0.50)
				if rng.randf() < 0.45:
					_add(img, x + 1, y - h, Color(0.30, 0.39, 0.21), 0.35)
			# 碎石：亮度只比底色高一档 —— 太亮会变成满屏白点
			for i in 6:
				_add(img, rng.randi_range(0, N - 1), rng.randi_range(0, N - 1), Color(0.30, 0.31, 0.27), 0.45)
			# 野花：极少量、低饱和。仙气靠留白，不靠花
			for i in 2:
				_add(img, rng.randi_range(0, N - 1), rng.randi_range(0, N - 1), Color(0.50, 0.50, 0.32), 0.70)
		"竹林":
			# 落叶：细长斜线（竹叶是长的，圆点读不出竹）
			for i in 30:
				var x := rng.randi_range(0, N - 1)
				var y := rng.randi_range(0, N - 1)
				var dir := 1 if rng.randf() < 0.5 else -1
				var ln := rng.randi_range(3, 5)
				for k in ln:
					_add(img, x + dir * k, y + (k >> 1), Color(0.20, 0.26, 0.11), 0.55)
			# 竹影：几道竖向暗条，暗示"立着的竹子投下的影"（这是竹林和草地的本质区别）
			for i in 3:
				var x := rng.randi_range(0, N - 1)
				for y in N:
					_add(img, x, y, Color(0.04, 0.07, 0.04), 0.14)
			for i in 4:
				_add(img, rng.randi_range(0, N - 1), rng.randi_range(0, N - 1), Color(0.28, 0.36, 0.16), 0.55)
		"灵岩":
			# 错缝石板：块宽 16、块高 8，隔行错开 —— 「人工铺过」和「野地」一眼之别
			for r in 4:
				var y0 := r * 8
				var off := 0 if (r % 2) == 0 else 8
				for c in 2:
					var x0 := c * 16 + off
					for y in range(y0, y0 + 8):
						for x in range(x0, x0 + 16):
							if y == y0 + 7 or x == x0 + 15:
								_add(img, x, y, Color(0.07, 0.07, 0.09), 0.38)
			# 裂缝：折线（直裂像划痕）
			for i in 5:
				var x := rng.randi_range(0, N - 1)
				var y := rng.randi_range(0, N - 1)
				for k in 6:
					_add(img, x + k, y + (k >> 1), Color(0.06, 0.06, 0.08), 0.40)
			# 灵石微光：一点点冷色亮点（不发光，只是比石头亮）
			for i in 5:
				_add(img, rng.randi_range(0, N - 1), rng.randi_range(0, N - 1), Color(0.34, 0.40, 0.52), 0.50)
		"灵田":
			# 垄沟：横向暗线（田是"种"出来的，必须有方向感）
			for r in 4:
				var y := r * 8 + 6
				for x in N:
					_add(img, x, y, Color(0.09, 0.09, 0.04), 0.26)
			# 灵苗：竖着两像素的高光绿，间距不规则
			for i in 9:
				var x := rng.randi_range(0, N - 1)
				var y := rng.randi_range(0, N - 1)
				_add(img, x, y, Color(0.36, 0.42, 0.18), 0.85)
				_add(img, x, y - 1, Color(0.44, 0.50, 0.22), 0.85)
			# 灵光点：极淡的暖黄，暗示这片地在"养"东西
			for i in 3:
				_add(img, rng.randi_range(0, N - 1), rng.randi_range(0, N - 1), Color(0.46, 0.44, 0.22), 0.35)
		"泥沼":
			# 泥浆斑块：成片的暗湿区（泥沼要有"烂"的质感，不能是均匀的土）
			for i in 16:
				var x := rng.randi_range(0, N - 1)
				var y := rng.randi_range(0, N - 1)
				for k in 4:
					_add(img, x + (k & 1), y + (k >> 1), Color(0.05, 0.04, 0.02), 0.45)
			# 气泡：暗底 + 亮边（"活"的沼，不是死土）
			for i in 7:
				var x := rng.randi_range(0, N - 1)
				var y := rng.randi_range(0, N - 1)
				_add(img, x, y, Color(0.30, 0.26, 0.12), 0.70)
				_add(img, x, y - 1, Color(0.38, 0.33, 0.16), 0.55)
			# 枯苇：三像素竖线
			for i in 5:
				var x := rng.randi_range(0, N - 1)
				var y := rng.randi_range(0, N - 1)
				_add(img, x, y, Color(0.18, 0.15, 0.07), 0.80)
				_add(img, x, y - 1, Color(0.16, 0.13, 0.06), 0.80)


# ---------------------------------------------------------------- 边带

## 按掩码压暗边缘。
## ⚠️ 关键设计：**暗边 + 无亮线**。
##    旧瓦片在暗边内侧有一条 1px 亮线，本意是"高光勾边"，实际铺满屏后形成一圈圈亮框
##    —— 那是"贴纸板"观感的主要来源。分界应该读成**缝隙（暗）**，不该读成**描边（亮）**。
func _apply_edges(img: Image, mask: int) -> void:
	if mask == 0:
		return
	for y in N:
		for x in N:
			var dmin := 999
			if (mask & 1) != 0:
				dmin = mini(dmin, y)
			if (mask & 2) != 0:
				dmin = mini(dmin, N - 1 - x)
			if (mask & 4) != 0:
				dmin = mini(dmin, N - 1 - y)
			if (mask & 8) != 0:
				dmin = mini(dmin, x)
			if dmin > 5:
				continue
			var c := img.get_pixel(x, y)
			# 0px = 最深的**分界缝**；1~4px 渐回底色；5px = 几乎无影响（收边不硬）
			## ⚠️ 第一版分界用 0.52，铺满屏后每块地形都镶了一圈**黑框**，像贴纸。
			##    分界只要"读得出来"，不要"画得出来" —— 0.66 才和地面是同一张皮。
			var k := 0.66 if dmin == 0 else (0.80 + 0.045 * float(dmin))
			img.set_pixel(x, y, Color(c.r * k, c.g * k, c.b * k, 1.0))


# ---------------------------------------------------------------- 像素工具

func _add(img: Image, x: int, y: int, c: Color, a: float) -> void:
	var xx := ((x % N) + N) % N
	var yy := ((y % N) + N) % N
	var o := img.get_pixel(xx, yy)
	img.set_pixel(xx, yy, Color(lerpf(o.r, c.r, a), lerpf(o.g, c.g, a), lerpf(o.b, c.b, a), 1.0))
