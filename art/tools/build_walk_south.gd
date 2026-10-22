## 把 4 张 1024×1024 的「正面行走」序列帧做成和 p4_d.png 同规格的 192 画布素材。
##
## 输入：`C:/Users/Administrator/Desktop/photo/walk_south_v4_frame1..4.png`（白底）
## 输出：`art/units_hd/p4_d_walk_1..4.png`（192×192，人物 48 高，脚底在第 191 行，水平居中）
##
## ⚠️ 和 build_player_4dir.gd 的关键差别：**四帧共用同一个缩放系数**。
##    那一版是「每个方向各自归一到 48」（不同方向是同一角色的不同画，尺寸不可比）；
##    而同一套走路循环的四帧必须同比例放大 —— 否则肩宽/身高会逐帧呼吸，走起来像在膨胀。
##    做法：先裁掉每帧自己的包围盒，取四帧里最高的那帧当参考（→48），其余按同一比例。
##
## 跑法（无头）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://art/tools/build_walk_south.gd
extends SceneTree

const SRC_DIR := "C:/Users/Administrator/Desktop/photo"
const SRC := [
	"walk_south_v4_frame1.png",
	"walk_south_v4_frame2.png",
	"walk_south_v4_frame3.png",
	"walk_south_v4_frame4.png",
]
const OUT_DIR := "res://art/units_hd"
const OUT_FMT := "p4_d_walk_%d.png"

const OUT_H := 48        # 人物在画布里的目标高度（世界单位，和现有契约一致）
const CANVAS := 192      # 输出画布边长
const FOOT_ROW := 191    # 脚底落在最后一行
const PROC_MAX := 512    # 处理时的最大边长（够用且泛洪快）


func _init() -> void:
	var cuts: Array = []
	for name in SRC:
		var p := "%s/%s" % [SRC_DIR, name]
		var img := _load(p)
		if img == null:
			print("FAIL 读图失败：", p)
			quit(1)
			return
		cuts.append(_cut(img))

	## 四帧共用比例：最高的一帧正好 48，其余同比例
	var max_h := 0
	for c in cuts:
		max_h = maxi(max_h, (c as Image).get_height())
	var k := float(OUT_H) / float(maxi(max_h, 1))

	var report := ""
	for i in cuts.size():
		var img := _fit_shared(cuts[i], k)
		var out := "%s/%s" % [OUT_DIR, OUT_FMT % (i + 1)]
		var err := (img as Image).save_png(out)
		if err != OK:
			print("FAIL 保存失败 ", out, " err=", err)
			quit(1)
			return
		report += "%s:%dx%d " % [OUT_FMT % (i + 1), (img as Image).get_width(), (img as Image).get_height()]
	print("OK 共 ", cuts.size(), " 帧 → ", report)
	quit(0)


func _load(p: String) -> Image:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return null
	var buf := f.get_buffer(f.get_length())
	var img := Image.new()
	var err := img.load_png_from_buffer(buf)
	if err != OK:
		err = img.load_jpg_from_buffer(buf)
	if err != OK:
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


## 抠白底 + 只留最大连通块 + 裁到包围盒
func _cut(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var k := minf(float(PROC_MAX) / float(w), float(PROC_MAX) / float(h))
	if k < 1.0:
		img.resize(maxi(1, int(float(w) * k)), maxi(1, int(float(h) * k)), Image.INTERPOLATE_LANCZOS)
	_flood_white(img)
	_keep_largest(img)
	return img.get_region(img.get_used_rect())


## 从四边泛洪，把与边界连通的近白像素设为透明
func _flood_white(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack: Array = []
	for x in w:
		stack.push_back(x)
		stack.push_back((h - 1) * w + x)
	for y in h:
		stack.push_back(y * w)
		stack.push_back(y * w + w - 1)
	while not stack.is_empty():
		var i: int = stack.pop_back()
		if seen[i] == 1:
			continue
		seen[i] = 1
		var x := i % w
		var y := (i - x) / w
		var c := img.get_pixel(x, y)
		if c.a < 0.5 or c.r < 0.93 or c.g < 0.93 or c.b < 0.93:
			continue
		img.set_pixel(x, y, Color(0, 0, 0, 0))
		if x > 0:
			stack.push_back(i - 1)
		if x < w - 1:
			stack.push_back(i + 1)
		if y > 0:
			stack.push_back(i - w)
		if y < h - 1:
			stack.push_back(i + w)


## 只保留最大的不透明连通块（人物），其余清空
func _keep_largest(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var lbl := PackedInt32Array()
	lbl.resize(w * h)
	var best := 0
	var best_n := 0
	var cur := 0
	for start in w * h:
		if lbl[start] != 0:
			continue
		if img.get_pixel(start % w, (start - start % w) / w).a < 0.5:
			lbl[start] = -1
			continue
		cur += 1
		var n := 0
		var stack: Array = [start]
		lbl[start] = cur
		while not stack.is_empty():
			var i: int = stack.pop_back()
			n += 1
			var x := i % w
			var y := (i - x) / w
			for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var nx := x + int(d[0])
				var ny := y + int(d[1])
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var j := ny * w + nx
				if lbl[j] != 0:
					continue
				if img.get_pixel(nx, ny).a < 0.5:
					lbl[j] = -1
					continue
				lbl[j] = cur
				stack.push_back(j)
		if n > best_n:
			best_n = n
			best = cur
	for i in w * h:
		if lbl[i] != best:
			img.set_pixel(i % w, (i - i % w) / w, Color(0, 0, 0, 0))


## 按**共用比例 k** 把裁剪后的图放进 192 画布：水平居中、脚底压到最后一行。
func _fit_shared(src: Image, k: float) -> Image:
	var tw := maxi(1, int(round(float(src.get_width()) * k)))
	var th := maxi(1, int(round(float(src.get_height()) * k)))
	var scaled := src.duplicate() as Image
	scaled.resize(tw, th, Image.INTERPOLATE_LANCZOS)
	## 48px 的原生像素 → 最近邻放大回 192 画布，保住硬边
	var big := scaled.duplicate() as Image
	big.resize(tw * 4, th * 4, Image.INTERPOLATE_NEAREST)
	## ⚠️ 放大后高度必须 ≤ 脚底行，否则会把人顶出画布
	if big.get_height() > FOOT_ROW + 1:
		var k2 := float(FOOT_ROW + 1) / float(big.get_height())
		big.resize(maxi(1, int(float(big.get_width()) * k2)), FOOT_ROW + 1, Image.INTERPOLATE_NEAREST)
	var canvas := Image.create(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	var ox := int((CANVAS - big.get_width()) * 0.5)
	var oy := FOOT_ROW + 1 - big.get_height()
	canvas.blit_rect(big, Rect2i(0, 0, big.get_width(), big.get_height()), Vector2i(ox, oy))
	return canvas
