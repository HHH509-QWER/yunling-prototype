extends Control
## 时印回溯的选择界面。**时间静止**：游戏暂停，只有这个面板在响应。
##
## ⭐ 待决问题 4：不自动保留最强 —— 「选哪一枚」本身就是玩法的一部分。
## ⚠️ 因为游戏是暂停的，这个节点必须 PROCESS_MODE_WHEN_PAUSED，否则收不到任何输入。

signal chosen(index: int)

var candidates: Array = []
var _info: Dictionary = {}      # {secs, frames_back, depth, reason}


## 把秒数说成人话：8 → "8 秒"，95 → "1 分 35 秒"。
static func fmt_back(secs: float) -> String:
	var s: int = int(maxf(0.0, secs))
	if s < 60:
		return "%d 秒" % s
	return "%d 分 %d 秒" % [s / 60, s % 60]

var _font: Font = null

const CARD_W := 190.0
const CARD_H := 132.0
const CARD_GAP := 22.0


func _ready() -> void:
	_font = GameData.make_font()
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED     # 暂停时必须还能收输入
	visible = false


## 打开面板。暂停由 Game 负责 —— 面板只管「显示什么」和「选了哪一枚」。
## ⭐ info 是盲跳回溯的信息：回到多久前 + 为什么退这么远（回溯点不可控，但必须**可解释**）。
func open(list: Array, info: Dictionary = {}) -> void:
	candidates = list.duplicate()
	_info = info.duplicate()
	visible = true
	queue_redraw()


func close() -> void:
	visible = false
	candidates.clear()
	queue_redraw()


## 选定第 i 枚。鼠标点、数字键、自测都走这一个入口。
func choose(i: int) -> void:
	if i < 0 or i >= candidates.size():
		return
	chosen.emit(i)


func _card_rect(i: int) -> Rect2:
	var n := candidates.size()
	var total := CARD_W * float(n) + CARD_GAP * float(n - 1)
	var x0 := size.x * 0.5 - total * 0.5
	return Rect2(Vector2(x0 + (CARD_W + CARD_GAP) * float(i), size.y * 0.5 - CARD_H * 0.5),
			Vector2(CARD_W, CARD_H))


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in range(candidates.size()):
			if _card_rect(i).has_point(event.position):
				choose(i)
				return


func _input(event: InputEvent) -> void:
	if not visible:
		return
	# 数字键 1..N 也能选：菜单里「数字键 = 第 N 项」和战斗里的灵印不冲突（不同模式）
	if event is InputEventKey and event.pressed and not event.echo:
		var idx := int(event.keycode) - int(KEY_1)
		if idx >= 0 and idx < candidates.size():
			get_viewport().set_input_as_handled()
			choose(idx)


func _draw() -> void:
	if not visible:
		return
	# 全屏压暗：让「时间静止」这件事看得见
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.03, 0.80))

	_text("时 印 回 溯", Vector2(size.x * 0.5 - 76.0, size.y * 0.5 - 186.0), Color(0.93, 0.88, 0.70), 30)
	# ⭐ 盲跳：回溯点不可控，但必须**可解释** —— 写清回到多久前、为什么退这么远
	_text("回到 %s前" % fmt_back(float(_info.get("secs", 0.0))),
			Vector2(size.x * 0.5 - 60.0, size.y * 0.5 - 150.0), Color(0.88, 0.90, 0.74), 18)
	_text(str(_info.get("reason", "")), Vector2(size.x * 0.5 - 118.0, size.y * 0.5 - 122.0),
			Color(0.70, 0.70, 0.74), 13)
	_text("时间静止 —— 选一枚灵印留下来", Vector2(size.x * 0.5 - 118.0, size.y * 0.5 - 100.0),
			Color(0.80, 0.80, 0.82), 15)

	for i in range(candidates.size()):
		_draw_card(i)

	_text("本命印「%s」无论如何都会留下；其余灵印随这一世一起失去。" % GameData.NATAL_SEAL,
			Vector2(size.x * 0.5 - 210.0, size.y * 0.5 + 116.0), Color(0.70, 0.66, 0.60), 13)
	_text("点击卡片，或按 1 - %d" % candidates.size(),
			Vector2(size.x * 0.5 - 66.0, size.y * 0.5 + 142.0), Color(0.60, 0.72, 0.80), 13)


func _draw_card(i: int) -> void:
	var r := _card_rect(i)
	var name_key := str(candidates[i])
	var d: Dictionary = GameData.SEALS[name_key]
	var col: Color = d["color"]

	draw_rect(r, Color(0.10, 0.11, 0.13, 0.96))
	draw_rect(r, Color(col.r, col.g, col.b, 0.85), false, 2.0)
	draw_circle(r.position + Vector2(r.size.x * 0.5, 34.0), 15.0, col)
	_text(str(i + 1), r.position + Vector2(r.size.x * 0.5 - 5.0, 40.0), Color(0.95, 0.95, 0.95), 15)
	_text(name_key, r.position + Vector2(r.size.x * 0.5 - 27.0, 74.0), Color(0.90, 0.88, 0.84), 15)
	_text(str(d["body_part"]), r.position + Vector2(r.size.x * 0.5 - 14.0, 94.0), Color(0.62, 0.66, 0.70), 12)
	_text(_skill_line(name_key), r.position + Vector2(10.0, 118.0), Color(0.66, 0.70, 0.74), 11)


func _skill_line(name_key: String) -> String:
	match str(GameData.SEALS[name_key]["skill"]["kind"]):
		"ember":
			return "持续攻击 · 灼烧"
		"guard":
			return "持续防御 · 护主"
		"bolt":
			return "一次性攻击 · 落雷"
		"shield":
			return "一次性防御 · 护盾"
	return ""


func _text(s: String, at: Vector2, col: Color, px: int) -> void:
	if _font != null:
		draw_string(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)