class_name Player
extends Node2D
## 主角。
##
## M0：WASD 移动 + 朝向跟着鼠标
## M1：鼠标左键普攻 —— 在正前方生成一个短命伤害区
##
## ⭐ 读代码的重点：
##   _move()      —— 位置是「自己算」的
##   _face_mouse()—— 朝向由鼠标决定，不是由移动方向决定（这是《蕴灵印》的特点）
##   attack_center() —— 单独抽出来，让「真的按左键」和「自测」走同一段代码

var game: Node = null          # 由 Game 接线，见 Game._build_world()
var facing := Vector2.DOWN     # 朝向（单位向量）。Vector2.DOWN == Vector2(0, 1)
var hp := 120.0
var hp_max := 120.0

var _atk_cd := 0.0             # 攻击冷却剩余秒数
var _bob := 0.0                # 用来做呼吸动画的计时器


func _process(delta: float) -> void:
	_move(delta)
	_face_mouse()
	_attack_input(delta)
	_bob += delta * 6.0
	queue_redraw()


## WASD / 方向键移动。
## dir.normalized() 不能省：不归一化的话，斜着走会快 1.41 倍（勾股定理）。
func _move(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1.0

	if dir != Vector2.ZERO:
		position += dir.normalized() * float(GameData.PLAYER["speed"]) * delta


## 朝向 = 从自己指向鼠标。
## get_global_mouse_position() 给的是「鼠标在世界里的位置」，
## 减去自己的位置，就得到一个「从我指向鼠标」的向量。
func _face_mouse() -> void:
	var to_mouse: Vector2 = get_global_mouse_position() - position
	if to_mouse.length() > 1.0:      # 太近就不更新，避免抖动
		facing = to_mouse.normalized()


## 攻击区中心：在玩家朝向前方 reach 像素处。
func attack_center() -> Vector2:
	return position + facing * float(GameData.ATTACK["reach"])


## 按住左键就连续出招，靠 _atk_cd 控制频率。
func _attack_input(delta: float) -> void:
	_atk_cd = maxf(0.0, _atk_cd - delta)
	if _atk_cd > 0.0:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return

	_atk_cd = float(GameData.ATTACK["cooldown"])
	if game == null:
		return
	var a: Dictionary = GameData.ATTACK
	game.spawn_hit(attack_center(), facing,
			float(a["length"]), float(a["width"]), float(a["damage"]))


func _draw() -> void:
	var r := float(GameData.PLAYER["radius"])
	var bob := sin(_bob) * 3.0

	# 朝向线：让「鼠标指着哪」一眼可见。没有它，这个原型就分不清朝向。
	draw_line(facing * r * 0.6, facing * (r + 16.0), Color(1.0, 0.82, 0.35, 0.9), 2.5)

	# 影子 + 身体 + 描边
	draw_circle(Vector2(2.0, 8.0), r, Color(0.0, 0.0, 0.0, 0.30))
	draw_circle(Vector2(0.0, bob), r, Color(0.86, 0.87, 0.90))
	draw_arc(Vector2(0.0, bob), r, 0.0, TAU, 28, Color(0.20, 0.22, 0.28), 2.0)

	# 面朝方向的小暗点，像一只眼睛，让朝向更明显
	draw_circle(Vector2(0.0, bob) + facing * (r * 0.5), 3.0, Color(0.18, 0.20, 0.26))

	# 气血条
	draw_rect(Rect2(-24.0, -r - 16.0, 48.0, 5.0), Color(0.0, 0.0, 0.0, 0.6))
	draw_rect(Rect2(-24.0, -r - 16.0, 48.0 * clampf(hp / maxf(hp_max, 0.001), 0.0, 1.0), 5.0),
			Color(0.85, 0.30, 0.30))
