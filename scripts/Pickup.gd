extends Node2D
## 地上的掉落物。
##
## ⭐ 走过去**自动**捡起 —— 不给 E 增加第二个含义（E 的含义是「交互 / 采集」）。
## ⭐ 背包满时**不会被捡走**，留在地上等你腾地方 —— 掉的东西绝不凭空消失。
##
## ⚠️ 不写 class_name（新增全局类名要先由编辑器扫描，否则命令行自测直接报错）。

var item := ""
var amount := 1

var _bob := 0.0

## ⚠️ 性能红线（M29.6）：字体**只在 _ready() 里取一次**。
##    这行原来写在 _draw() 里 —— 而掉落物每帧都在浮动，于是每帧新建一次 SystemFont，
##    实测 5152 µs/次 ⇒ 地面上每个「数量 > 1」的掉落物白烧约 6 毫秒/帧（堆满时 238 → 13 FPS）。
var _font: Font = null


func _ready() -> void:
	_font = GameData.make_font()


## 这是一枚灵印吗？（灵师的遗物）
func is_seal() -> bool:
	return GameData.SEALS.has(item)


func color() -> Color:
	if is_seal():
		return GameData.SEALS[item]["color"]
	if item == GameData.CURRENCY:
		return Color(0.92, 0.82, 0.45)              # 灵石偏金
	var d: Dictionary = GameData.MATERIALS.get(item, {})
	return d.get("color", Color(0.80, 0.80, 0.80))


func _process(delta: float) -> void:
	_bob += delta * 3.0
	queue_redraw()


func _draw() -> void:
	var s := float(GameData.PICKUP["size"])
	var c := color()
	var lift := -3.0 + sin(_bob) * 1.5             # 轻微上下浮动，一眼看出是「地上能捡的」
	# ⭐ M30.5b 路线②：材料 / 灵石有 8×8 贴图就画贴图。
	#    ⚠️ **灵印故意例外**：纹理没法按印染色，而地上那枚印必须一眼认出是哪一枚 ——
	#    所以它继续走形状语言（菱形 + 外环 + 印色），见下面那个 draw_arc。
	var drop_vis: Dictionary = {} if is_seal() else GameData.item_drop_visual(item)
	var tex := ActorVisual.texture_of(drop_vis)
	if tex != null:
		ActorVisual.draw_unit(self, tex, drop_vis, 0.0, lift)
	else:
		var pts := PackedVector2Array([
			Vector2(0.0, -s) + Vector2(0.0, lift),
			Vector2(s, 0.0) + Vector2(0.0, lift),
			Vector2(0.0, s) + Vector2(0.0, lift),
			Vector2(-s, 0.0) + Vector2(0.0, lift),
		])
		draw_colored_polygon(pts, c)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
				Color(1.0, 1.0, 1.0, 0.55), 1.5)

	# 灵印多一圈外环 —— 地上躺着一枚印和躺着一块材料，必须一眼分得开
	if is_seal():
		draw_arc(Vector2(0.0, lift), s + 6.0, 0.0, TAU, 20, Color(c.r, c.g, c.b, 0.85), 2.0)
	if amount > 1 and _font != null:
		draw_string(_font, Vector2(s + 3.0, 4.0), str(amount), HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				Color(0.85, 0.85, 0.88))