class_name GameData
extends RefCounted
## 全局数据表与工具函数。
##
## ⭐ 这个文件是整个工程最重要的设计思想：把「有什么」和「能做什么」分开。
## 想加一种敌人、想调一个数值，只动这里，逻辑代码一行都不用改。
## （这就是《学习路线》板块 2 讲的「数据驱动」——回到 gu 工程也要学它。）
##
## 注意：Godot 默认字体不含中文字形，这里用 SystemFont 直接向系统要一份，
## 见 make_font()。这个办法是从 gu 工程抄来的，已经验证过能正常显示中文。

# ---------------- 玩家 ----------------
const PLAYER := {
	"speed": 232.0,          # 移动速度（像素/秒）
	"radius": 13.0,          # 身体半径，只用于画图
	"hp_max": 120.0,
	"essence_max": 100.0,
}

# ---------------- 普攻 ----------------
# M1 的做法：每次出手，在玩家正前方生成一个「短命伤害区」。
# 它只活 life 秒，寿命到了就消失 —— 不是持续伤害。
const ATTACK := {
	"damage": 12.0,          # 每次伤害
	"cooldown": 0.28,        # 冷却（秒）
	"reach": 46.0,           # 攻击区中心离玩家多远
	"length": 44.0,          # 攻击区长度（沿朝向）
	"width": 36.0,           # 攻击区宽度（垂直朝向）
	"life": 0.12,            # 攻击区活多久（秒）
}

# ---------------- 假人 ----------------
const DUMMY := {
	"hp_max": 60.0,
	"radius": 16.0,
	"color": Color(0.55, 0.58, 0.62),
	"spawns": [Vector2(880.0, 384.0), Vector2(520.0, 250.0)],
}


## Godot 默认字体不含中日韩字形，这里直接向系统要一份中文字体。
static func make_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "微软雅黑", "SimHei", "黑体",
		"Noto Sans CJK SC", "Source Han Sans SC", "PingFang SC",
		"WenQuanYi Micro Hei", "sans-serif",
	])
	f.allow_system_fallback = true
	return f
