extends Node2D
## ⭐ M31.3：**前景遮挡层**（竹林树冠盖住角色上半身）—— 斜 45°/HD-2D 的「立体书感」。
##
## ⚠️ 为什么它必须是**独立节点**，不能塞进 `Game._draw()`：
##    `Game` 自己的 `_draw()` 画在**它的子节点之前**（Godot 的 CanvasItem 默认顺序：
##    父节点的绘制命令先出，子节点后出）。玩家 / 敌人 / 采集点全是 `Game` 的子节点，
##    所以在 `Game._draw()` 里画竹子，永远只能落在人身**后** —— 那就不叫遮挡了。
##    挂在 `z_index` 更高的子节点上，才画在人**之后**，树冠才真的盖得住上半身。
##
## 调用方：`Game._set_fg_occlusion(true)`（命令行 `-- --foreground` 或游戏里按 F9）。
## 默认关闭 —— 用户定案过「地面上撒竹子太丑」（`Game.gd` 里 M30.24 那条），
## 所以先把开关递到他手里，看过再定价，不替他决定。

var game: Node = null

func _draw() -> void:
	if game == null or not is_instance_valid(game):
		return
	game._draw_foreground(self)
