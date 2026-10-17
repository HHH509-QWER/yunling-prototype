extends Node2D
## 采集点：走过去按 E 采一口灵力，然后这个点就空了。
##
## ⭐ 它存在的意义不只是资源 —— 它是「锚点快照」的第一个真正的测试对象：
##    采空之后死一次，它必须复原。否则玩家回到锚点却采不到东西（待决问题 8）。
##
## ⚠️ 和 Seal/Enemy 一样不写 class_name（新增全局类名要先由编辑器扫描，否则命令行自测报错）。

var depleted := false      # 采空了吗

## 这一处产什么、产几个。由 Game 生成时从 GameData.GATHER["spots"] 写进来。
var item := ""
var amount := 1

var _flash := 0.0
var _bob := 0.0


func reach() -> float:
	return float(GameData.GATHER["reach"])


## 采一口。返回**是否真的采到了**（已经空了就返回 false）。
## ⭐ 灵力与材料由 Game 结算 —— 采集点只负责「我这儿还有没有东西」。
func gather() -> bool:
	if depleted:
		return false
	depleted = true
	_flash = 1.0
	queue_redraw()
	return true


## 锚点快照回滚时调它。
func restore() -> void:
	depleted = false
	_flash = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	_bob += delta * 2.0
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 3.0)
	queue_redraw()


func _draw() -> void:
	var r := float(GameData.GATHER["radius"])

	# 呼吸光晕：⭐ 留在贴图 / 形状**两种路径之外** —— 它表示「这里还活着」，是状态不是形象
	if not depleted:
		var pulse := 1.0 + 0.12 * sin(_bob * 3.0) + _flash * 0.35
		var glow: Color = GameData.GATHER["color_full"]
		draw_circle(Vector2.ZERO, r * pulse, Color(glow.r, glow.g, glow.b, 0.22))

	# ⭐ 路线②：有贴图就画贴图，没有还是形状 —— 见 ActorVisual.gd
	var tex := ActorVisual.texture_named(GameData.GATHER, "empty_texture") if depleted \
			else ActorVisual.texture_of(GameData.GATHER)
	if tex != null:
		ActorVisual.draw_unit(self, tex, GameData.GATHER, 0.0, 0.0 if depleted else sin(_bob) * 1.2)
		return

	if depleted:
		# 回退：空的 —— 暗、小、没有呼吸
		draw_circle(Vector2.ZERO, r * 0.6, Color(GameData.GATHER["color_empty"], 0.55))
		draw_arc(Vector2.ZERO, r * 0.6, 0.0, TAU, 16, Color(0.18, 0.20, 0.22, 0.7), 1.5)
		return

	# 回退：满的
	var col: Color = GameData.GATHER["color_full"]
	draw_circle(Vector2.ZERO, r * 0.55, col)
	draw_arc(Vector2.ZERO, r * 0.55, 0.0, TAU, 18, Color(0.90, 0.98, 1.0, 0.65), 1.5)