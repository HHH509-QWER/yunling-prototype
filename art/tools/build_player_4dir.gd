## ⭐ M33：**把三张单方向立绘（前/后/左）做成四方向主角素材**。
##
## 输入：三张 2048×2048 JPEG（白底 + 右下角水印），前 / 后 / 左。
## 输出：`art/units_hd/p4_d.png` / `p4_u.png` / `p4_l.png` / `p4_r.png`
##       —— 192×192 画布，人物 48px 高，脚底在最后一行，水平居中。
##
## ⚠️ 为什么输出 192 画布而不是 48：
##    工程现有契约是「192 高 × scale 0.25 = 48 世界单位」，自测还写死了 192 和脚底行。
##    先把 48px 的原生像素**用最近邻放大 4 倍**塞进 192 画布，契约一个字都不用改，
##    而显示出来（192 / 0.25 再被 2× 缩放）和原生 48px 是**等价的** —— 同样是硬边。
##    ⇒ 换素材不动玩法、不动测试，这是最省事也最安全的接法。
##
## ⚠️ 三个必须做的处理（少一个都不能用）：
##    ① **抠白底**：从画面四边泛洪，只吃与边界连通的近白像素。人物内部的白袍被黑描边挡住。
##    ② **去掉水印**：右下角"豆包 AI 生成"是一块孤立的不透明像素，泛洪吃不掉它。
##       做法是**只保留最大的连通块**（= 人物），其余一律清空。
##    ③ **统一比例**：三张图的人物高度不一样 —— 但修法**不是**"共用一个缩放系数"。
##       旧做法取三者中位数当系数，结果只有贴着中位数的那张正好 48px，最矮的背面只剩
##       41px（用户反馈"背面比别的面矮"就是这条）。三张的宽高比几乎一致
##       （正面 0.521 / 背面 0.512），说明是同一角色被画小了 ⇒ **每一向各自归一到 OUT_H**。
##       脚底仍统一压到最后一行，否则走路时人会上下跳。
##
## 跑法：在运行中的游戏里 `load("res://art/tools/build_player_4dir.gd").new().run()`
extends RefCounted

const OUT_H := 48            # 人物在画布里的目标高度（世界单位）
const CANVAS := 192          # 输出画布边长（= 现有契约）
const FOOT_ROW := 191        # 脚底落在哪一行（画布最后一行）
const PROC_MAX := 512        # 处理时的最大边长（够用，且泛洪快）

const SRC := [
	"C:/Users/Administrator/.dsh/attachments/v1/objects/38/3851c07cde75b90e31736ebb276668fb708c30b20c3ec11bcec6a324270b1150",  # 前
	"C:/Users/Administrator/.dsh/attachments/v1/objects/aa/aad067d014227f33bceeba4cbd857c18eafd5f6e1ac230aebe2a0c8beaa57856",  # 后
	"C:/Users/Administrator/.dsh/attachments/v1/objects/88/88cf9d5b6b7b2e3062e5790dee957ad8f7c40a476d7a392298a788ce299a5c5b",  # 左
]


func run() -> String:
	var cuts: Array = []
	for p in SRC:
		var img := _load(p)
		if img == null:
			return "读图失败：%s" % p
		cuts.append(_cut(img))
	## ⭐ M33a：**每一向各自归一到 OUT_H**（不再共用一个中位缩放系数）。
	##    旧做法下三张里只有贴着中位数的那张正好 48px，最矮的背面只有 41px —— 就是"背面矮"的根因。
	var out: Array = []
	for c in cuts:
		out.append(_fit_h(c, OUT_H))
	## 右 = 左的水平镜像（省一张图的生成成本，也是像素游戏的标准做法）
	var right: Image = (out[2] as Image).duplicate() as Image
	right.flip_x()
	out.append(right)
	var names := ["d", "u", "l", "r"]
	var msg := ""
	for i in 4:
		var p2 := "res://art/units_hd/p4_%s.png" % names[i]
		var err := (out[i] as Image).save_png(p2)
		if err != OK:
			return "保存失败 %s (%d)" % [p2, err]
		msg += "%s:%dx%d " % [names[i], (out[i] as Image).get_width(), (out[i] as Image).get_height()]
	return "四方向已出 → " + msg


func _load(p: String) -> Image:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return null
	var buf := f.get_buffer(f.get_length())
	var img := Image.new()
	var err := img.load_jpg_from_buffer(buf)
	if err != OK:
		err = img.load_png_from_buffer(buf)
	if err != OK:
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


## 抠底 + 去孤块 + 裁到人物包围盒
func _cut(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var k := minf(float(PROC_MAX) / float(w), float(PROC_MAX) / float(h))
	if k < 1.0:
		img.resize(maxi(1, int(float(w) * k)), maxi(1, int(float(h) * k)), Image.INTERPOLATE_LANCZOS)
	w = img.get_width()
	h = img.get_height()
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


## 只保留最大的不透明连通块（人物），其余（水印、杂点）清空
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


## 按**目标高度**（艺术像素）放进 192 画布：水平居中、脚底压到最后一行。
## 每一向各自归一 ⇒ 四向成品高度都是 OUT_H，换方向不会忽高忽低。
func _fit_h(src: Image, target_h: int) -> Image:
	var th := maxi(1, target_h)
	var tw := maxi(1, int(round(float(src.get_width()) * float(th) / maxf(float(src.get_height()), 1.0))))
	var scaled := src.duplicate() as Image
	scaled.resize(tw, th, Image.INTERPOLATE_LANCZOS)
	## 48px 的原生像素 → 最近邻放大回 192 画布，保住硬边（见文件头）
	var k := int(round(float(CANVAS) / float(OUT_H)))
	var big := scaled.duplicate() as Image
	big.resize(tw * k, th * k, Image.INTERPOLATE_NEAREST)
	## ⚠️ 放大后高度必须 ≤ 脚底行，否则会把人顶出画布
	if big.get_height() > FOOT_ROW + 1:
		var k2 := float(FOOT_ROW + 1) / float(big.get_height())
		big.resize(int(float(big.get_width()) * k2), FOOT_ROW + 1, Image.INTERPOLATE_NEAREST)
	var canvas := Image.create(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	var ox := int((CANVAS - big.get_width()) * 0.5)
	var oy := FOOT_ROW + 1 - big.get_height()
	canvas.blit_rect(big, Rect2i(0, 0, big.get_width(), big.get_height()), Vector2i(ox, oy))
	return canvas
