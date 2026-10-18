extends Node2D

## ⭐⭐ M31.3：**抓帧工具（常驻，不许再用临时脚本）**。
##    team-lead 硬要求：「抓帧的可信度必须变成断言，不能靠人记住」——
##    这轮已经**数据出错三次**：① 眼误把暗紫块当地形（"实测 0% 未覆盖"）；
##    ② 眼误"三帧全覆盖"；③ 相机 `position_smoothing` 没收敛 + 玩家被出生逻辑拉回
##    ⇒ 取景根本没钉住，24.2/10.5/3.7 那组基线全部作废。
##    ⇒ 结论：**光靠"小心一点"守不住**。下面三条做成脚本内的**强制检查**，
##       不满足就**不写文件**（不是警告），退出码非 0。
##
## 跑法（窗口模式，headless 抓不到画面）：
##   Godot --path . --resolution 1366x768 -- \
##        --x=1264 --y=368 --out=res://art/tools/preview_x.png [--skirt] [--flat]
##   退出码：0=出图成功；2=参数不合法；3=自检失败（**没出图**）；4=存图失败。
##
## `--flat`（素色直出，**测覆盖率必带**）：关 CanvasModulate / PostFx / HUD。
##    ⚠️ M31.3 后这里不再提「云 / 远山」—— 那两层已被**彻底删除**（用户拍板），
##        素色直出只剩「关压暗 + 关后处理 + 关 HUD」三件事。
##    默认画面叠着压暗+分级+半透，暗地形和 clear color 只差几个灰阶 ⇒
##    像素统计把暗地形数进"未覆盖"（前两轮眼误的土壤）。素色直出后画面只剩
##    「地形 or clear color」，`art/tools/pixel_gap.py` 才量得准。
##
## ⚠️ 主场景要临时改成 `res://tests/capture_frame.tscn`，跑完必须改回去
##    （本脚本自己会在最后一行打印提醒，别指望人记）。
##
## 自检清单（任一不过 ⇒ 拒绝出图，退出码 3）：
##   ① 相机 `position_smoothing_enabled == false`（平滑没收敛是第③次数据错误的根因）
##   ② `camera.offset == ZERO`（震屏会把画面整体位移）
##   ③ `camera.zoom == CAMERA_ZOOM`（缩放一变，屏幕覆盖的世界范围就变了）
##   ④ **玩家每帧钉在目标点**（钉不住 ⇒ `_draw_world_height()` 的 vis_r 裁剪用错位置）
##   ⑤ **`cam_center` 打印并断言等于目标点**（相机被世界边界夹住时按夹后值比，不假装没夹）

const WARMUP := 8          ## 前 N 帧只钉人 + 等渲染收敛，不校验不出图
const EPS := 0.5           ## 允许的位置误差（世界单位）

var game: Node2D = null
var target := Vector2.ZERO
var out_path := ""
var frame := 0
var done := false


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var sx := ""
	var sy := ""
	for arg in a:
		var s := str(arg)
		if s.begins_with("--x="):
			sx = s.substr(4)      ## ⚠️ "--x=" 是 **4** 个字符（踩过：写成 5 会吃掉首位数字，
		elif s.begins_with("--y="):                  ## 1264 变 264，而且夹取断言还发现不了）
			sy = s.substr(4)
		elif s.begins_with("--out="):
			out_path = s.substr(6)
	if sx == "" or sy == "" or out_path == "":
		push_error("[抓帧] 参数不全：需要 --x= --y= --out=（示例见脚本头注释）")
		get_tree().quit(2)
		return
	if not sx.is_valid_float() or not sy.is_valid_float():
		push_error("[抓帧] --x/--y 不是数字：%s / %s" % [sx, sy])
		get_tree().quit(2)
		return
	target = Vector2(float(sx), float(sy))

	game = load("res://scenes/Main.tscn").instantiate()
	add_child(game)
	## 素色直出：关掉一切会染色/挡画面的叠层（见头注释）
	## ⚠️ HUD 也关：底栏/右上角面板是深色半透，像素统计会把它们数进"未覆盖"。
	if a.has("--flat"):
		game.set("debug_flat", true)
		for n in game.get_children():
			if n is CanvasModulate:
				n.color = Color.WHITE
			elif n is CanvasLayer:
				n.visible = str(n.name) != "HudLayer"
	print("[抓帧] 目标点 = %s，输出 = %s，素色直出 = %s" % [str(target), out_path, a.has("--flat")])


func _process(_delta: float) -> void:
	if game == null or done:
		return
	frame += 1
	_pin()
	if frame < WARMUP:
		return
	## ⚠️ 校验放在"钉完之后"的**下一帧头**：此时上一帧的画面已经按钉好的位置渲染完了
	if not _verify():
		_abort()
		return
	done = true
	_save()


## 每帧把玩家和相机钉死在目标点（缺一不可：玩家决定 vis_r 裁剪，相机决定画面中心）
func _pin() -> void:
	if game.get("player") == null:
		return
	var p = game.player
	if not is_instance_valid(p):
		return
	p.position = target
	var cam = game.camera
	if cam == null or not is_instance_valid(cam):
		return
	cam.position_smoothing_enabled = false   ## ①
	cam.offset = Vector2.ZERO                ## ②
	cam.zoom = Vector2(GameData.CAMERA_ZOOM, GameData.CAMERA_ZOOM)   ## ③
	cam.global_position = target


func _verify() -> bool:
	var ok := true
	var cam = game.camera
	if cam == null or not is_instance_valid(cam):
		push_error("[抓帧自检] 拿不到相机")
		return false
	## ①②③
	if cam.position_smoothing_enabled:
		push_error("[抓帧自检] camera.position_smoothing_enabled 仍为 true（平滑没关 ⇒ 画面中心漂）")
		ok = false
	if not cam.offset.is_equal_approx(Vector2.ZERO):
		push_error("[抓帧自检] camera.offset = %s（震屏位移没清）" % str(cam.offset))
		ok = false
	if not cam.zoom.is_equal_approx(Vector2(GameData.CAMERA_ZOOM, GameData.CAMERA_ZOOM)):
		push_error("[抓帧自检] camera.zoom = %s（不是 %s）" % [str(cam.zoom), GameData.CAMERA_ZOOM])
		ok = false
	## ④
	var p = game.player
	if p == null or not is_instance_valid(p):
		push_error("[抓帧自检] 拿不到玩家")
		ok = false
	elif p.position.distance_to(target) > EPS:
		push_error("[抓帧自检] 玩家没钉住：在 %s，目标 %s（差 %.1f）"
				% [str(p.position), str(target), p.position.distance_to(target)])
		ok = false
	## ⑤ cam_center —— 打印 + 断言等于目标点。⚠️ 两道闸：
	##    (a) **目标点不许被世界边界夹到** —— 夹了说明你要看的点本来就不在完整视野里，
	##        出的图和"目标点"对不上号（试过：--x 写错吃掉首位，夹取把 (264,68) 变 (341.5,192)
	##        竟然还通过了断言）。
	##    (b) cam_center 必须等于夹后目标（相机没钉住立刻红）。
	var cc: Vector2 = cam.get_screen_center_position()
	var want := _clamped_target()
	print("[抓帧自检] cam_center = %s（目标 %s，边界夹后应为 %s）"
			% [str(cc), str(target), str(want)])
	if not want.is_equal_approx(target):
		push_error("[抓帧自检] 目标点 %s 被世界边界夹成 %s —— 取景点不合法，**不出图**"
				% [str(target), str(want)])
		ok = false
	if cc.distance_to(want) > EPS:
		push_error("[抓帧自检] cam_center 偏离目标 %.1f 世界单位 —— 取景没钉住，本次**不出图**"
				% cc.distance_to(want))
		ok = false
	return ok


## 相机被世界边界夹住时的真实中心（不夹的话画面会露出世界外，Godot 会自动夹）
func _clamped_target() -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	var z9 := GameData.CAMERA_ZOOM
	var half := Vector2(vp.x, vp.y) / z9 * 0.5
	var ws: Vector2 = GameData.WORLD["size"]
	return Vector2(
			clampf(target.x, half.x, ws.x - half.x),
			clampf(target.y, half.y, ws.y - half.y))


func _abort() -> void:
	push_error("[抓帧] 自检未通过 ⇒ **拒绝出图**（退出码 3）。"
			+ "这不是警告：不合格的图比没有图更危险，它会让下一轮基于错误数字下结论。")
	get_tree().quit(3)


func _save() -> void:
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out_path)
	if err != OK:
		push_error("[抓帧] 存图失败 %s（err=%d）" % [out_path, err])
		get_tree().quit(4)
		return
	print("[抓帧] 已出图 %s（%dx%d，cam_center 已校验）" % [out_path, img.get_width(), img.get_height()])
	print("[抓帧] ⚠️ 记得把 project.godot 的 run/main_scene 改回 res://scenes/Main.tscn")
	get_tree().quit(0)
