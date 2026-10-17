extends Node2D
## 商人（M14）。⭐ 灵石的**回收站**：把采来的材料换成灵石，也能买到懒得去挖的东西。
##
## ⭐ 形状语言里他**不是任何一种怪**：六边形 + 头顶一颗灵石菱形 —— 一眼看出「这个能说话」。
## ⚠️ 不写 class_name（新增全局类名要先由编辑器扫描，否则命令行自测直接报错）。

## 货架：材料名 -> 剩余数量。由 Game 从 GameData.MERCHANT["stock"] 建好塞进来，
## 之后它就属于**世界状态**（进快照、进存档）—— 买过就少了，回溯/读档会一起退回去。
var stock: Dictionary = {}

var _bob := 0.0


func reach() -> float:
	return float(GameData.MERCHANT["reach"])


func available(item: String) -> int:
	return int(stock.get(item, 0))


func _process(delta: float) -> void:
	_bob += delta * 2.0
	queue_redraw()


func _draw() -> void:
	var r := float(GameData.MERCHANT["radius"])
	var col: Color = GameData.MERCHANT["color"]
	var bob := sin(_bob) * 2.0

	draw_circle(Vector2(2.0, 8.0), r, Color(0.0, 0.0, 0.0, 0.30))
	# 六边形：不是圆 / 方 / 菱 / 三角里的任何一个
	var pts := PackedVector2Array([])
	for i in range(6):
		var a := TAU * float(i) / 6.0 - PI * 0.5
		pts.append(Vector2(cos(a), sin(a)) * r + Vector2(0.0, bob))
	draw_colored_polygon(pts, col)
	var ring := pts.duplicate()
	ring.append(pts[0])
	draw_polyline(ring, Color(0.24, 0.20, 0.12), 2.0)
	# 头顶一颗灵石（菱形）—— 他做的是灵石的生意
	var c := Vector2(0.0, bob - r - 11.0)
	var s := 5.0
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0.0, -s), c + Vector2(s, 0.0), c + Vector2(0.0, s), c + Vector2(-s, 0.0)]),
		Color(0.94, 0.84, 0.46))