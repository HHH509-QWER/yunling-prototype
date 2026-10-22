## ⭐ M33：**补两个缺图标的材料**（玄霜髓 / 太虚核）—— 32×32 图标 + 8×8 掉落图。
##
## ⚠️ 这是 `art/tools/gen_items.mjs` 的**同配方移植**，不是另起一套画法：
##    画法 = 多边形填充 → 贴边压深 + 左上高光（dress）→ 1px 墨线描边（INK）。
##    之所以用 GDScript 重写一遍：本机 `pwsh` 起不来（0xC0000142），node 跑不了。
##    ⇒ 将来能跑 node 时，**以 `gen_items.mjs` 为准**重新生成一遍，产物应当一致；
##      如果两边出现差异，先怀疑这里，别怀疑 JS。
##
## 跑法：写完后由 MCP 让编辑器重新导入（`filesystem_manage` op=scan），再重启游戏。
##
## ⚠️ 两条纪律（与 gen_items.mjs 一致）：
##   ① 颜色取自 `GameData.MATERIALS[*].color` —— 改数据表就重跑，不要在这里另调色。
##   ② 掉落图是**同一配方的整数降采样**（S=8 重画一遍），不是另画一套；
##      否则"背包里看到的"和"地上捡到的"会变成两个东西。
extends RefCounted

const INK := Color8(16, 17, 22)
const ICON := 32
const DROP := 8

## 两种材料的底色（和 GameData.MATERIALS 里那两行一致）
const ITEMS := {
	"frost": Color8(158, 219, 242),        # 玄霜髓：霜蓝
	"voidcore": Color8(230, 204, 115),     # 太虚核：太虚金
}


func run() -> String:
	var made := 0
	for id in ITEMS:
		var base: Color = ITEMS[id]
		var dark := Color(base.r * 0.55, base.g * 0.55, base.b * 0.55)
		var light := Color(minf(base.r * 1.3, 1.0), minf(base.g * 1.3, 1.0), minf(base.b * 1.3, 1.0))
		for pair in [[ICON, ""], [DROP, "_drop"]]:
			var S: int = pair[0]
			var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
			img.fill(Color(0, 0, 0, 0))
			match id:
				"frost": _draw_frost(img, base, dark, light)
				"voidcore": _draw_voidcore(img, base, dark, light)
			_dress(img, base, dark, light)
			_outline(img, INK)
			var p := "res://art/items/%s%s.png" % [id, str(pair[1])]
			var err := img.save_png(p)
			if err != OK:
				return "保存失败：%s (%d)" % [p, err]
			made += 1
	return "生成 %d 张（玄霜髓 / 太虚核 各 图标 + 掉落）" % made


# ---------------------------------------------------------------- 两种图形

## 玄霜髓：一簇**竖向霜晶**（主晶 + 侧晶 + 高光）。和雷髓（一道雷）形状不同，
## 但同属"晶体"家族 —— 同类材料应该看得出是一家的。
func _draw_frost(img: Image, base: Color, dark: Color, light: Color) -> void:
	_poly(img, [
		Vector2(0.48, 0.05), Vector2(0.66, 0.34), Vector2(0.61, 0.84),
		Vector2(0.45, 0.95), Vector2(0.35, 0.56)], base)
	_poly(img, [
		Vector2(0.32, 0.34), Vector2(0.43, 0.47), Vector2(0.37, 0.82),
		Vector2(0.25, 0.66)], dark)
	_poly(img, [Vector2(0.50, 0.13), Vector2(0.59, 0.31), Vector2(0.47, 0.46)], light)


## 太虚核：**一圈金环包着一颗空心的核**（"太虚"= 空）。
## ⚠️ 中间那块暗必须用 darkened 的底色，不能用 INK —— 描边色是"轮廓"，
##    拿来当"洞"会让整个图标和背景糊成一块。
func _draw_voidcore(img: Image, base: Color, dark: Color, light: Color) -> void:
	_poly(img, [
		Vector2(0.50, 0.08), Vector2(0.86, 0.32), Vector2(0.86, 0.66),
		Vector2(0.50, 0.92), Vector2(0.14, 0.66), Vector2(0.14, 0.32)], base)
	_poly(img, [
		Vector2(0.50, 0.32), Vector2(0.65, 0.42), Vector2(0.65, 0.58),
		Vector2(0.50, 0.68), Vector2(0.35, 0.58), Vector2(0.35, 0.42)], dark)
	_poly(img, [
		Vector2(0.32, 0.24), Vector2(0.46, 0.16), Vector2(0.56, 0.20),
		Vector2(0.40, 0.30)], light)


# ---------------------------------------------------------------- 画法（对齐 gen_items.mjs）

func _poly(img: Image, pts: Array, c: Color) -> void:
	var S := img.get_width()
	for y in S:
		for x in S:
			var px := (float(x) + 0.5) / float(S)
			var py := (float(y) + 0.5) / float(S)
			if _in_poly(px, py, pts):
				img.set_pixel(x, y, c)


## 偶奇规则（even-odd）—— 和 JS 里的扫描线填充是同一个判据
func _in_poly(px: float, py: float, pts: Array) -> bool:
	var inside := false
	var n := pts.size()
	for i in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		if (a.y > py) != (b.y > py):
			var xint := a.x + (py - a.y) / (b.y - a.y) * (b.x - a.x)
			if px < xint:
				inside = not inside
	return inside


## 贴边压深 + 左上高光。⭐ 小尺寸下这一步是"有没有立体感"的分水岭。
## ⚠️ 只处理**底层色**（和 base 完全相等的像素），不碰已经画好的细节层 —— 否则高光会被压掉。
func _dress(img: Image, base: Color, dark: Color, light: Color) -> void:
	var S := img.get_width()
	var src := img.duplicate() as Image
	for y in S:
		for x in S:
			var c := src.get_pixel(x, y)
			if c.a == 0.0 or not _same(c, base):
				continue
			var edge := false
			for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var nx := x + int(d[0])
				var ny := y + int(d[1])
				if nx < 0 or ny < 0 or nx >= S or ny >= S or src.get_pixel(nx, ny).a == 0.0:
					edge = true
					break
			var t := float(x + y) / float(S * 2)
			img.set_pixel(x, y, dark if edge else (light if t < 0.34 else base))


## 1px 墨线描边：透明的像素，只要四邻里有不透明的，就涂墨色。
func _outline(img: Image, ink: Color) -> void:
	var S := img.get_width()
	var src := img.duplicate() as Image
	for y in S:
		for x in S:
			if src.get_pixel(x, y).a != 0.0:
				continue
			for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var nx := x + int(d[0])
				var ny := y + int(d[1])
				if nx < 0 or ny < 0 or nx >= S or ny >= S:
					continue
				if src.get_pixel(nx, ny).a != 0.0:
					img.set_pixel(x, y, ink)
					break


## 按 8 位比较颜色（浮点相等不可靠，画的时候是精确值，但别赌）
func _same(a: Color, b: Color) -> bool:
	return roundi(a.r * 255.0) == roundi(b.r * 255.0) \
			and roundi(a.g * 255.0) == roundi(b.g * 255.0) \
			and roundi(a.b * 255.0) == roundi(b.b * 255.0)
