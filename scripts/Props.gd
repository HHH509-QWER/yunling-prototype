extends Node2D
## ⭐ M33：**高出地面的装饰物** —— 竹丛 / 岩石 / 石碑 / 枯树 / 灌木 / 祭坛。
##
## 为什么必须是**节点**，而不是画进 `Game._draw`：
##   地形画在 `Game` 自己的 `_draw` 里 —— 父节点自己的绘制**永远在所有子节点之下**。
##   所以只要装饰物也画在那儿，它就**永远压在玩家背后**，"走进竹林被竹叶盖住上半身" 不可能成立。
##   要遮挡，装饰物就必须和玩家**同父、同层、按 y 排序**：
##   ⇒ `Game` 打开了 `y_sort_enabled`，这些节点都直接挂在 `Game` 下面。
##
## ⚠️ 三条纪律：
##   ① **位置全部由 `GameData.cell_hash()` 决定**：世界是静态的，一样的位置每次启动都一样。
##   ② **原点必须在"脚下"**：y_sort 比的是节点 y。原点若落在物体中间，
##      「站在石头前面」会被判成「站在石头后面」—— 这类错最伤体感，且极难排查。
##   ③ **全部用 `_draw` 画，不依赖外部贴图**：先让世界"立起来"，美术件到位后再换 Sprite2D。
##      换的时候只改这里的 `_draw`，位置/排序/裁剪逻辑一行都不用动。
##
## ⚠️ 性能：这是个**静态**节点，但 Godot 不会自动剔除 CanvasItem（屏幕外的也照画）。
##    所以 `_process` 里按距离切 `visible`；间隔 0.2 秒，够用且几乎不花时间。

## 物体种类（由 `Game._prop_kind_at()` 决定）
var kind := "bamboo"
## 变体种子（取自格坐标哈希）—— 同一格永远长同一个样子
var sd := 0
## 主控（用于距离剔除；可为 null）
var game = null

var _cull_t := 0.0


func setup(p_kind: String, p_sd: int) -> void:
	kind = p_kind
	sd = p_sd


func _draw() -> void:
	match kind:
		"bamboo": _draw_bamboo()
		"rock": _draw_rock()
		"stele": _draw_stele()
		"deadtree": _draw_deadtree()
		"shrub": _draw_shrub()
		"altar": _draw_altar()


func _process(delta: float) -> void:
	if game == null or not is_instance_valid(game) or game.player == null:
		return
	_cull_t += delta
	if _cull_t < 0.2:
		return
	_cull_t = 0.0
	## 视口对角半径（1366×768 @2× ≈ 780 世界宽）+ 余量
	visible = global_position.distance_squared_to(game.player.position) < 950.0 * 950.0


# ---------------------------------------------------------------- 影子

## 脚下的落影。⚠️ 没有影子，物体看起来是"浮"在地面上的 —— 这是俯视角最便宜也最有效的一笔。
func _shadow(r: float, a := 0.18) -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.38))
	draw_circle(Vector2.ZERO, r, Color(0.0, 0.0, 0.0, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- 竹丛

func _draw_bamboo() -> void:
	var h := 34.0 + float(sd % 7) * 3.0
	var stalks := 2 + int((sd >> 3) % 3)
	_shadow(9.0, 0.20)
	for i in stalks:
		var dx := (float(i) - float(stalks) * 0.5) * 7.0 + float((sd >> (i + 2)) % 5) - 2.0
		var lean := float(int((sd >> (i + 5)) % 5) - 2) * 0.6
		# 竹杆：**三笔**才像竹 —— 暗主杆 + 中间色 + 受光侧边（竹子是圆柱，不是一条线）
		draw_line(Vector2(dx - 0.6, 0.0), Vector2(dx + lean - 0.6, -h), Color(0.18, 0.25, 0.12), 1.0)
		draw_line(Vector2(dx, 0.0), Vector2(dx + lean, -h), Color(0.26, 0.35, 0.17), 2.0)
		draw_line(Vector2(dx + 1.1, 0.0), Vector2(dx + lean + 1.1, -h), Color(0.34, 0.45, 0.21), 1.0)
		# 竹节：每 9px 一道横环。「节」是竹子最容易被认出来的特征，但**不能亮** ——
		# 节画亮了会变成一把"梯子"（第一版就是这样）。
		var k := 1
		while float(k) * 9.0 < h:
			var yy := -float(k) * 9.0
			var sx := dx + lean * (-yy / h)
			draw_line(Vector2(sx - 0.5, yy), Vector2(sx + 1.6, yy), Color(0.29, 0.38, 0.19), 1.0)
			k += 1
		# 叶：五笔斜线，长而细（竹叶不是圆点，也不是短刺）
		var tip := Vector2(dx + lean, -h)
		draw_line(tip, tip + Vector2(-9.0, -3.5), Color(0.27, 0.37, 0.16), 1.5)
		draw_line(tip, tip + Vector2(8.0, -4.0), Color(0.31, 0.42, 0.19), 1.5)
		draw_line(tip + Vector2(0.0, 3.0), tip + Vector2(-7.0, 4.0), Color(0.25, 0.34, 0.15), 1.5)
		draw_line(tip + Vector2(0.0, 5.0), tip + Vector2(6.0, 5.5), Color(0.28, 0.38, 0.17), 1.5)
		draw_line(tip + Vector2(0.0, 1.0), tip + Vector2(-3.0, -6.0), Color(0.30, 0.41, 0.18), 1.0)


# ---------------------------------------------------------------- 岩石

func _draw_rock() -> void:
	var w := 10.0 + float(sd % 6) * 2.0
	var h := 8.0 + float((sd >> 4) % 5) * 2.0
	_shadow(w * 0.9, 0.20)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-w, 0.0), Vector2(-w * 0.72, -h), Vector2(-w * 0.12, -h * 1.18),
		Vector2(w * 0.58, -h * 0.82), Vector2(w, 0.0)]), Color(0.25, 0.25, 0.29))
	# 顶面受光（一小块亮面，不是整块提亮 —— 整块提亮就变成"发光的石头"）
	draw_colored_polygon(PackedVector2Array([
		Vector2(-w * 0.58, -h * 0.60), Vector2(-w * 0.12, -h * 1.08),
		Vector2(w * 0.46, -h * 0.74), Vector2(w * 0.16, -h * 0.48)]), Color(0.34, 0.34, 0.39))


# ---------------------------------------------------------------- 石碑

func _draw_stele() -> void:
	_shadow(8.0, 0.22)
	draw_rect(Rect2(Vector2(-7.0, -4.0), Vector2(14.0, 5.0)), Color(0.20, 0.20, 0.24))   # 底座
	draw_rect(Rect2(Vector2(-5.0, -24.0), Vector2(10.0, 21.0)), Color(0.29, 0.29, 0.33))  # 碑身
	draw_rect(Rect2(Vector2(-5.0, -24.0), Vector2(3.0, 21.0)), Color(0.34, 0.34, 0.38))   # 受光侧
	# 符文：三点冷色微光。（**微光**，不是光源 —— 真发光留给灵泉/阵法）
	for i in 3:
		var y := -20.0 + float(i) * 6.0
		draw_rect(Rect2(Vector2(-2.0, y), Vector2(1.0, 3.0)), Color(0.42, 0.72, 0.76))
		draw_rect(Rect2(Vector2(1.0, y + 1.0), Vector2(1.0, 2.0)), Color(0.36, 0.62, 0.66))


# ---------------------------------------------------------------- 枯树（泥沼）

func _draw_deadtree() -> void:
	var h := 24.0 + float(sd % 6) * 3.0
	_shadow(8.0, 0.20)
	draw_line(Vector2.ZERO, Vector2(0.0, -h), Color(0.16, 0.13, 0.08), 3.0)
	# 枯枝：三段，越往上越细（阔叶树的剪影，但没有叶子 —— 泥沼的"死"）
	draw_line(Vector2(0.0, -h * 0.55), Vector2(-9.0, -h * 0.85), Color(0.16, 0.13, 0.08), 2.0)
	draw_line(Vector2(0.0, -h * 0.70), Vector2(8.0, -h * 0.95), Color(0.15, 0.12, 0.07), 2.0)
	draw_line(Vector2(0.0, -h * 0.85), Vector2(3.0, -h), Color(0.15, 0.12, 0.07), 1.0)


# ---------------------------------------------------------------- 灌木（灵田）

func _draw_shrub() -> void:
	_shadow(6.0, 0.18)
	draw_circle(Vector2(0.0, -5.0), 6.0, Color(0.20, 0.27, 0.13))
	draw_circle(Vector2(-3.0, -7.0), 4.0, Color(0.24, 0.32, 0.15))
	draw_circle(Vector2(3.5, -6.0), 3.5, Color(0.22, 0.29, 0.14))


# ---------------------------------------------------------------- 祭坛（出生点）

func _draw_altar() -> void:
	_shadow(30.0, 0.22)
	# 石台：三圈由外到内逐层变亮 = 一点点"台阶"的体积感
	draw_circle(Vector2.ZERO, 30.0, Color(0.16, 0.16, 0.18))
	draw_circle(Vector2.ZERO, 26.0, Color(0.22, 0.22, 0.25))
	draw_arc(Vector2.ZERO, 27.0, 0.0, TAU, 40, Color(0.28, 0.28, 0.31), 1.5)
	# 阵纹：**刻在石头上的暗青玉**，不是发光体 ——
	## ⚠️ 第一版用了 (0.38,0.68,0.70) 不透明，读出来是「科幻全息投影」，仙侠味儿全无。
	##    仙侠的阵法是**刻痕**：亮度只比石头高一档，靠"同心 + 辐射"的**形状**认出来。
	draw_arc(Vector2.ZERO, 21.0, 0.0, TAU, 40, Color(0.30, 0.44, 0.40, 0.55), 1.5)
	draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 28, Color(0.26, 0.38, 0.35, 0.45), 1.0)
	for i in 8:
		var a := TAU * float(i) / 8.0
		draw_line(Vector2(cos(a) * 13.0, sin(a) * 13.0),
				Vector2(cos(a) * 20.0, sin(a) * 20.0), Color(0.28, 0.42, 0.38, 0.40), 1.0)
	# ⚠️ 祭坛是**平躺**在地上的：它的 y_sort 原点在中点，玩家站上去时
	#    「人在坛上」应该盖住坛心 —— 这条只要原点位置对，y_sort 自动成立。
