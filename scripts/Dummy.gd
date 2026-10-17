class_name Dummy
extends Node2D
## 假人：不会动、不会还手，只用来验证「打中了、掉血了」。
##
## M1 的靶子。它存在的唯一目的是让「伤害」这件事**可被观察**——
## 一个看不见效果的原型，你没法判断自己写对了没有。

var hp := 60.0
var hp_max := 60.0
var font: Font = null
var game: Node = null      # 由 Game 接线（和 Player / Enemy 同一套）

var _flash := 0.0          # 被打中时闪白的强度，1.0 → 0.0


## 唯一的公开方法。谁想伤害它，都得走这里 —— 这样掉血的规则只有一处。
## ⭐ 假人也要有打击感：玩家开局第一个打的就是它（敌人还在 330px 外），
##    打上去没反馈，第一印象就是「这游戏手感差」。
## ⚠️ 唯独**不冒伤害数字** —— 它自己已经在头顶画了「当前/上限」，再加飘字会叠在一起。
func take_damage(dmg: float) -> void:
	hp = maxf(0.0, hp - dmg)
	_flash = 1.0
	if game != null:
		if game.has_method("hitstop"):
			game.hitstop(float(GameData.JUICE["hitstop_hit"]))
		if game.has_method("add_shake"):
			game.add_shake(float(GameData.JUICE["shake_hit"]))
	queue_redraw()


func _process(delta: float) -> void:
	if _flash <= 0.0:
		return
	_flash = maxf(0.0, _flash - delta * 6.0)
	queue_redraw()


func _draw() -> void:
	var r := float(GameData.DUMMY["radius"])
	var col: Color = GameData.DUMMY["color"]
	if _flash > 0.0:
		col = col.lerp(Color(1.0, 1.0, 1.0), _flash * 0.8)

	# ⭐ 有贴图就画贴图，没有就还是色块 —— 见 ActorVisual.gd
	var tex := ActorVisual.texture_of(GameData.DUMMY)
	if tex != null:
		ActorVisual.draw_unit(self, tex, GameData.DUMMY, _flash)
	else:
		draw_circle(Vector2(2.0, 8.0), r, Color(0.0, 0.0, 0.0, 0.30))
		draw_circle(Vector2.ZERO, r, col)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 26, Color(0.20, 0.20, 0.24), 2.0)

	# 血条。分母用 maxf(hp_max, 0.001) 只是为了防「除以零」，
	# 不能用 maxf(hp_max, 1.0) —— 那样一旦有人把血量改成 0.5，血条就永远填不满。
	draw_rect(Rect2(-24.0, -r - 15.0, 48.0, 5.0), Color(0.0, 0.0, 0.0, 0.6))
	draw_rect(Rect2(-24.0, -r - 15.0, 48.0 * clampf(hp / maxf(hp_max, 0.001), 0.0, 1.0), 5.0),
			Color(0.85, 0.30, 0.30))

	if font != null:
		draw_string(font, Vector2(-45.0, -r - 20.0), "%d/%d" % [int(hp), int(hp_max)],
				HORIZONTAL_ALIGNMENT_CENTER, 90.0, 12, Color(0.90, 0.88, 0.84))
