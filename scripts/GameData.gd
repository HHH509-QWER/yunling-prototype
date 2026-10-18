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
	"speed": 116.0,          # 移动速度（像素/秒）
	"radius": 13.0,          # 身体半径，只用于画图
	"hp_max": 120.0,
	"essence_max": 100.0,
	## ⭐ 外观（像素美术）：文件不在就自动回退成色块，见 ActorVisual.gd
	"visual": {
		## ⭐⭐ M30.14：主角换成 **HD 立绘**（动画风管线）。
		##    ⚠️ 世界尺度**一点没变**：192px 的图 × scale 0.25 = **48 世界单位**，和旧像素贴图同样大。
		"texture": "res://art/units_hd/hd_player_idle1.png",
		"scale": 0.25,
		## ⭐ 动作表：一个动作 = 一组帧 + 速率 + 是否循环。加动作 = 加一行。
		##    播放由 Player 的 _anim 状态机管 —— 触发点在按键 / 施法那几处，不在 _draw 里。
		"anims": {
			## ⚠️ M30.14：暂时**每个动作只有 1 帧 HD 图**（先定风格）。
			##    剩下 15 帧出齐后，这里换成多帧列表即可 —— 动作表结构没变。
			## ⭐ M30.16：走路接上 **4 帧序列图**（用户出图 → 我按 4 格切）—— 不再是滑行的一张图。
			##    fps 9：8 帧/秒偏慢、12 偏赶，9 正好是"一步步走"的节奏。
			"walk": {"frames": ["res://art/units_hd/hd_player_walk1.png", "res://art/units_hd/hd_player_walk2.png", "res://art/units_hd/hd_player_walk3.png", "res://art/units_hd/hd_player_walk4.png"], "fps": 9.0, "loop": true},
			## ⭐⭐ M30.19：**8 方向**（用户从 360° 转盘导出 → 统一缩放/基准线切成 79×192）
			##    d=朝下 dl=左下 dr=右下 l=左 r=右 u=朝上 ul=左上 ur=右上。
			##    每向目前 1 帧（站姿与行走共用）；走路多帧等序列图再补。
			## ⭐ M30.20：6 帧真走路（用户出 8 方向 × 6 格序列图 → 统一缩放切成 68×192）
			"walk_d": {"frames": ["res://art/units_hd/hd_player_d1.png", "res://art/units_hd/hd_player_d2.png", "res://art/units_hd/hd_player_d3.png", "res://art/units_hd/hd_player_d4.png", "res://art/units_hd/hd_player_d5.png", "res://art/units_hd/hd_player_d6.png"], "fps": 10.0, "loop": true},
			## ⭐ M30.20：6 帧真走路（用户出 8 方向 × 6 格序列图 → 统一缩放切成 68×192）
			"walk_dl": {"frames": ["res://art/units_hd/hd_player_dl1.png", "res://art/units_hd/hd_player_dl2.png", "res://art/units_hd/hd_player_dl3.png", "res://art/units_hd/hd_player_dl4.png", "res://art/units_hd/hd_player_dl5.png", "res://art/units_hd/hd_player_dl6.png"], "fps": 10.0, "loop": true},
			## ⭐ M30.20：6 帧真走路（用户出 8 方向 × 6 格序列图 → 统一缩放切成 68×192）
			"walk_dr": {"frames": ["res://art/units_hd/hd_player_dr1.png", "res://art/units_hd/hd_player_dr2.png", "res://art/units_hd/hd_player_dr3.png", "res://art/units_hd/hd_player_dr4.png", "res://art/units_hd/hd_player_dr5.png", "res://art/units_hd/hd_player_dr6.png"], "fps": 10.0, "loop": true},
			## ⭐ M30.20：6 帧真走路（用户出 8 方向 × 6 格序列图 → 统一缩放切成 68×192）
			"walk_l": {"frames": ["res://art/units_hd/hd_player_l1.png", "res://art/units_hd/hd_player_l2.png", "res://art/units_hd/hd_player_l3.png", "res://art/units_hd/hd_player_l4.png", "res://art/units_hd/hd_player_l5.png", "res://art/units_hd/hd_player_l6.png"], "fps": 10.0, "loop": true},
			## ⭐ M30.20：6 帧真走路（用户出 8 方向 × 6 格序列图 → 统一缩放切成 68×192）
			"walk_r": {"frames": ["res://art/units_hd/hd_player_r1.png", "res://art/units_hd/hd_player_r2.png", "res://art/units_hd/hd_player_r3.png", "res://art/units_hd/hd_player_r4.png", "res://art/units_hd/hd_player_r5.png", "res://art/units_hd/hd_player_r6.png"], "fps": 10.0, "loop": true},
			## ⭐ M30.20：6 帧真走路（用户出 8 方向 × 6 格序列图 → 统一缩放切成 68×192）
			"walk_u": {"frames": ["res://art/units_hd/hd_player_u1.png", "res://art/units_hd/hd_player_u2.png", "res://art/units_hd/hd_player_u3.png", "res://art/units_hd/hd_player_u4.png", "res://art/units_hd/hd_player_u5.png", "res://art/units_hd/hd_player_u6.png"], "fps": 10.0, "loop": true},
			## ⭐ M30.20：6 帧真走路（用户出 8 方向 × 6 格序列图 → 统一缩放切成 68×192）
			"walk_ul": {"frames": ["res://art/units_hd/hd_player_ul1.png", "res://art/units_hd/hd_player_ul2.png", "res://art/units_hd/hd_player_ul3.png", "res://art/units_hd/hd_player_ul4.png", "res://art/units_hd/hd_player_ul5.png", "res://art/units_hd/hd_player_ul6.png"], "fps": 10.0, "loop": true},
			## ⭐ M30.20：6 帧真走路（用户出 8 方向 × 6 格序列图 → 统一缩放切成 68×192）
			"walk_ur": {"frames": ["res://art/units_hd/hd_player_ur1.png", "res://art/units_hd/hd_player_ur2.png", "res://art/units_hd/hd_player_ur3.png", "res://art/units_hd/hd_player_ur4.png", "res://art/units_hd/hd_player_ur5.png", "res://art/units_hd/hd_player_ur6.png"], "fps": 10.0, "loop": true},
			"cast": {"frames": ["res://art/units_hd/hd_player_cast1.png"], "fps": 10.0, "loop": false},
			"combo": {"frames": ["res://art/units_hd/hd_player_cast1.png"], "fps": 11.0, "loop": false},
			"attack": {"frames": ["res://art/units_hd/hd_player_stand.png"], "fps": 16.0, "loop": false},
		},
		## ⭐ M30.14：HD 立绘 192 高 × scale 0.25 = 48 世界单位（和旧贴图一样大）。
		## 脚底行 183 → 世界坐标 183×0.25 = 45.75 → offset.y = -(48/2 - 45.75) ≈ **-22**。
		## 自测会**真的去读 PNG 找脚底行**，算出来对不对 —— 换图换错它会红。
		"offset": Vector2(0.0, -22.0),
	},
}

# ---------------- 普攻 ----------------
# M1 的做法：每次出手，在玩家正前方生成一个「短命伤害区」。
# 它只活 life 秒，寿命到了就消失 —— 不是持续伤害。
const ATTACK := {
	"reach": 23.0,           # 攻击区中心离玩家多远
	"length": 44.0,          # 攻击区长度（沿朝向）
	"width": 36.0,           # 攻击区宽度（垂直朝向）
	"life": 0.12,            # 攻击区活多久（秒）
	"windup": 0.15,          # ⭐ M30.7 **前摇**（用户定案）：抬手 0.15 秒后才判定
	"knockback": 7.0,        # ⭐ 命中时把敌人推开多少像素（轻微击退）
	## ⭐ 掌风弧光：主角**不持武器** —— 这是「掌心凝灵、拍出一掌」的气流，纯表现，不参与判定。
	"arc": {
		"radius": 30.0,
		"spread": 120.0,     # 扇形张角（度）
		"life": 0.18,
	},
}

## ⭐ M30.7：普攻**随境界成长**（用户定案的数值：一阶 8 → 五阶 14，间隔 0.55 → 0.40 秒）。
##    为什么单独一张表、不并进 `REALMS`：普攻是「保底手段」，它的成长曲线要能
##    **单独看见、单独调**；并进境界表就会跟着别的数值一起动。
const ATTACK_REALM := {
	1: {"damage": 8.0, "cooldown": 0.55},
	2: {"damage": 9.0, "cooldown": 0.50},
	3: {"damage": 11.0, "cooldown": 0.46},
	4: {"damage": 12.0, "cooldown": 0.43},
	5: {"damage": 14.0, "cooldown": 0.40},
}


## 按境界取普攻数值。越界一律夹到表内 —— 境界只有 1..5，但读表的地方不该自己判边界。
static func attack_of(realm: int) -> Dictionary:
	var ks: Array = ATTACK_REALM.keys()
	ks.sort()
	return ATTACK_REALM[clampi(realm, int(ks[0]), int(ks[ks.size() - 1]))]

# ---------------- 假人 ----------------
const DUMMY := {
	"hp_max": 60.0,
	"radius": 16.0,
	"color": Color(0.55, 0.58, 0.62),
	"visual": {"texture": "res://art/units/dummy.png", "offset": Vector2(0.0, -14.0)},
	## 假人是 M1 的验收基线，摆在锚点旁边（走两步就能打）
	"spawns": [Vector2(1512.0, 1322.7), Vector2(2072.0, 1749.3)],
}


# ---------------- 灵印（M3）----------------
# ⭐ 「不砍玩法，砍数量」（开发计划 §六）：V0.1 只做 3 枚印、3 个命窍槽。
#    加一枚印 = 往这张表里加一条，逻辑代码一行都不用改。

## 命窍槽位数。⭐ 数字键 1 / 2 / 3 / 4 一一对应 ——
## 设计圣经 §五 的键位表写的就是 1 2 3 4，这里是把 V0.1 砍到 3 枚那一刀补回来。
const SEAL_SLOTS := 4

## 命窍**容量** = 你最多能拥有几枚灵印（活跃 4 + 备用）。
## ⭐ 活跃键永远是 1-4（键位表锁定），多带的印放**备用**，在 Tab 面板里换上场。
## ⭐ 强夺要求「容量没满」—— 所以抢来的印是有限资源，不是随便捡。
const SEAL_CAPACITY := 6

## 境界（M12）。⭐ 成长轴：灵力攒满 → 回锚点突破 → 境界 +1 → 上限与命窍容量一起涨。
## ⚠️ 境界名（炼气/筑基/金丹/元婴/化神）是本里程碑新加的 —— 设计圣经只定义了「灵印十等」，
##    没有定义灵师自己的境界名。这五个名字是通行叫法，改起来只动这张表。
## ⚠️ `seal_rank_max` = 这个境界能驾驭的印的**最高品阶**；高于它的印会被**封印**
##    （不可显化、不给被动、不给基础属性），境界够了自动解封。
##    文档 §11.1 写的是「一阶只能凡印」，但那样炼气期连二等精印（惊雷印）都用不了 ——
##    而目前游戏里最强的印才二等，等于整段炼气期只剩灰烬印能打。所以炼气给到 2。
const REALMS := {
	1: {"name": "炼气", "essence_max": 100.0, "hp_max": 120.0, "speed": 116.0, "cultivation": 100.0, "sub_max": 4, "sub_gain": {"hp": 6.0, "essence": 5.0, "speed": 1.0}, "seal_rank_max": 2, "capacity": 6},
	2: {"name": "筑基", "essence_max": 160.0, "hp_max": 150.0, "speed": 120.0, "cultivation": 160.0, "sub_max": 4, "sub_gain": {"hp": 6.0, "essence": 5.0, "speed": 1.0}, "seal_rank_max": 2, "capacity": 7},
	3: {"name": "金丹", "essence_max": 220.0, "hp_max": 180.0, "speed": 124.0, "cultivation": 220.0, "sub_max": 4, "sub_gain": {"hp": 6.0, "essence": 5.0, "speed": 1.0}, "seal_rank_max": 3, "capacity": 8},
	4: {"name": "元婴", "essence_max": 300.0, "hp_max": 220.0, "speed": 129.0, "cultivation": 300.0, "sub_max": 4, "sub_gain": {"hp": 6.0, "essence": 5.0, "speed": 1.0}, "seal_rank_max": 4, "capacity": 9},
	5: {"name": "化神", "essence_max": 400.0, "hp_max": 270.0, "speed": 135.0, "cultivation": 400.0, "sub_max": 4, "sub_gain": {"hp": 6.0, "essence": 5.0, "speed": 1.0}, "seal_rank_max": 10, "capacity": 10},
}

# ---------------- 修炼（灵力 -> 修为）----------------
## ⭐ 灵力是**燃料**：能花（显化灵印）、能买（灵石换）、能炼成修为。
##    修为是**进度**：只能涨，满了才能突破 —— 花不掉，也买不到。
##    这样「灵石买材料」和「灵石买灵力」才是真的在抢同一笔钱。
const CULTIVATE := {
	"per_press": 20.0,          # 按一次修炼花多少灵力
	"gain": 20.0,               # 换到多少修为（1:1，先简单）
	"essence_service": 25.0,    # 商人卖的「一份灵力」有多少
	"essence_price": 10,        # 一份灵力卖多少灵石
}

## ⚠️ M28（用户定案）：**回溯功能暂时移除** —— 原来这里有一张 DEPTH 表
##    （时间线帧数 / 拍帧间隔 / 收获评分权重 / 连死保底），随功能一起删掉。
##    死亡现在是最朴素的「回到上次存档」；要接回盲跳回溯时，把这张表一起恢复
##    （原值与设计记录见 设计圣经 §4.4 / 开发计划 M17）。
## ⚠️ M19：**锚点机制已移除**（用户定案）—— 这张表只剩"存档文件放哪、多久自动存一次"。
##    原来的三件事分别有了新家：复活点 = 时间线帧的位置；存档 = 定期自动；
##    回溯下限 = 没有了（可以退到本局最早，随机性彻底放开）。
const ANCHOR := {
	"save_path": "user://yunling_save.json",
	## ⭐ M27（用户定案）：**每 10 分钟**自动存一次（原来是 60 秒 —— 太频繁，每次都在写盘）。
	##    ⚠️ 别跟上面 DEPTH 的 frame_every_sec（每 60 秒拍一帧）搞混：
	##       那是**时间线**的粒度（只存在内存里，给盲跳回溯用），跟写盘无关。
	"autosave_sec": 600.0,
}

## ---------------- 印诀（M22 / 结印 M26）----------------
## ⭐ M26 用户拍板的触发方式（方案 A）：**按 R 起手进入结印状态 → 数字键填序列 → 凑齐结算**。
##    为什么不直接复用数字键：数字键已有职责「显化印」。复用会导致
##    「配成印诀的那两枚印再也无法单独使用」—— 那不能接受。
##    结印期间按下的印**不显化、不消耗**，只填进序列；代价只剩印诀那一笔灵力。
const COMBO_WINDOW := 1.2       # 结印窗口（秒）。每按一枚印**刷新**；超时安静收势，不扣任何东西。
## ⭐ **不用按键**：把需要的几枚印按出来（显化）的那一刻自动放。只吃灵力 +（各门自己的）冷却，
##    不消耗印的状态 —— 它是"合击"，不是"牺牲"。
## ⚠️ 键是**排过序**的两枚印名（用 combo_key() 生成）—— 别手写，写反了就对不上。
## 效果都建立在已有机制上（范围伤害 / DOT / 治疗 / 增益），不另造"持续领域"系统。
const COMBOS := {
	"云雨印|惊雷印": {
		"name": "雷雨交加", "kind": "storm",
		"essence": 30.0, "cooldown": 9.0,
		"radius": 110.0, "damage": 34.0, "dot": 6.0, "dot_time": 3.0, "heal": 40.0,
		"desc": "范围落雷 + 持续受创，自己回血",
	},
	"流风印|灰烬印": {
		"name": "燎原", "kind": "firewall",
		"essence": 28.0, "cooldown": 8.0,
		"length": 260.0, "width": 70.0, "damage": 30.0, "dot": 5.0, "dot_time": 4.0, "push": 70.0,
		"desc": "朝前一道火墙：灼烧 + 推开",
	},
	"惊雷印|灰烬印": {                 # ⚠️ 排序按**码点**：惊(60CA) < 灰(7070)，不是笔画顺序
		"name": "爆炎", "kind": "burst",
		"essence": 32.0, "cooldown": 10.0,
		"radius": 85.0, "damage": 48.0,
		"desc": "一颗爆裂火球：范围伤害",
	},
	"玄甲印|磐石印": {
		"name": "山岳", "kind": "guard",
		"essence": 25.0, "cooldown": 12.0,
		"duration": 6.0, "taken_mult": 0.5, "speed_mult": 0.6,
		"desc": "厚护盾 + 减伤 50%，移速 −40%",
	},
	"云雨印|流风印": {
		"name": "疾风", "kind": "haste",
		"essence": 22.0, "cooldown": 10.0,
		"duration": 5.0, "speed_mult": 1.6, "heal": 30.0,
		"desc": "移速 ×1.6 + 持续回血",
	},
	"惊雷印|磐石印": {
		"name": "引雷柱", "kind": "pillar",
		"essence": 30.0, "cooldown": 11.0,
		"radius": 130.0, "damage": 40.0, "dot": 7.0, "dot_time": 2.5,
		"desc": "立起石柱引雷：大范围落雷",
	},
}


## 两枚印的印诀键（**排过序**）。⚠️ 手写字符串一定会写反，一律走这里。
static func combo_key(a: String, b: String) -> String:
	var pair: Array = [a, b]
	pair.sort()
	return "%s|%s" % [pair[0], pair[1]]


## ---------------- 闪避与冲刺（M20）----------------
## ⭐ **两者都由「已融合的灵印」给**，不是天生就会：
##    · 闪避：命窍里**有一枚养熟的印**就能用（身法来自印）
##    · 冲刺：得有一枚**标注了 move="dash" 的移速印**养熟（比如流风印）
## 灵力是共同燃料 —— 闪避与冲刺都从同一条灵力里扣。
const MOVE := {
	"dodge": {
		"essence": 8.0,        # 花多少灵力
		"cooldown": 1.0,       # 冷却（秒）
		"invuln": 0.30,        # 无敌帧（秒）—— 略长于翻滚，收尾也算安全
		"distance": 70.0,     # 位移距离（像素）
		## ⭐ 位移**时长**：翻滚是「滚过去」，不是「瞬移过去」。
		##    第一版是"一帧跳完"，用户一句话打回：「瞬移有点太快」。
		##    现在是 140px 分 0.28 秒（= 500 px/s ≈ 2.15 倍走速）。**要更慢就调大这个数**。
		"duration": 0.28,
	},
	"dash": {
		"essence": 12.0,
		"cooldown": 3.0,
		"duration": 1.2,       # 加速持续（秒）
		"speed_mult": 2.2,     # 加速期间的速度倍率
	},
}

## 身体部位：名字 -> 主角局部坐标。
## ⭐ 逻辑代码只认「名字」，不认坐标 —— 将来做真身体，把这里的值换成
##    骨骼/节点给的位置即可，其余一行都不用改。
const BODY_PARTS := {
	"右手": Vector2(12.0, -4.0),
	"左臂": Vector2(-12.0, -6.0),
	"躯干": Vector2(0.0, 3.0),
	"周身": Vector2.ZERO,
}

## 灵印表。passive 的三种取值，决定了「收回后加成立即消失」是怎么算的：
##   attack_damage   —— 加在普攻伤害上
##   damage_taken    —— 乘在「主角受到的伤害」上（越小越硬）
##   attack_cooldown —— 乘在普攻冷却上（越小越快）
##
## ⭐ 灵印有四种形态，由两条轴组合出来（不是四套特例代码）：
##   费用轴  activate 一次性 / drain 每秒
##   存续轴  instant 放完即收 / hold 到你收回或灵力扣光 / timed 到点自动收回
##     一次性攻击 = activate + instant
##     持续攻击   = 小额 activate + drain + hold
##     持续防御   = 小额 activate + drain + hold
##     一次性防御 = activate + timed
## 加第五枚印 = 往这张表里加一行。
const SEALS := {
	"灰烬印": {
		"tags": ["火"],        # 标签：印诀与（将来）推演都靠它
		"shape": "claw",        # 形状语言：一眼认出是哪个印（先简化成几何图形）
		"rank": 1,                   # 十等：一等凡印
		## 炼化满 100% 后**永久生效**的基础属性（和显化期的 passive 分开算，两者可叠）
		"base": {"stat": "attack_damage", "value": 4},
		"activate": 6.0,             # 按下时一次性扣的灵力
		## ⭐ M24：用户反馈「灰烬印消耗灵力太快」—— 6/秒 在炼气期只够烧 16 秒，太快。
		##    改成 2.5/秒（100 灵力 ≈ 40 秒）。玄甲(8) / 云雨(7) 还没动，觉得快就说。
		"drain": 2.5,                # 每秒扣的灵力（0 = 不持续扣）
		"life": "hold",              # 持续攻击：烧着的同时一直在扣灵力
		"seal_hp_max": 40.0,
		"passive": "attack_damage",
		"passive_value": 6.0,
		"radius": 11.0,
		"color": Color(0.86, 0.46, 0.30),
		# ⭐ M30.5（路线②）：贴图优先，文件不在就自动回退到形状语言
		"visual": {"texture": "res://art/seals/seal_ash.png"},
		"body_part": "右手",
		"skill": {
			"kind": "ember",
			"range": 55.0,
			"cooldown": 1.2,
			"damage": 3.0,                      # 每跳伤害
			"tick": 0.5,                        # 每跳间隔
			"duration": 3.0,                    # 灼烧持续时长
		},
	},
	"玄甲印": {
		"tags": ["岩", "守"],        # 标签：印诀与（将来）推演都靠它
		"shape": "hex",        # 形状语言：一眼认出是哪个印（先简化成几何图形）
		"rank": 1,                   # 十等：一等凡印
		## 炼化满 100% 后**永久生效**的基础属性（和显化期的 passive 分开算，两者可叠）
		"base": {"stat": "hp_max", "value": 24},
		"activate": 8.0,
		"drain": 8.0,
		"life": "hold",              # 持续防御：护着你的同时一直在扣灵力
		"seal_hp_max": 80.0,         # 最耐打的一枚
		"passive": "damage_taken",
		"passive_value": 0.70,
		"radius": 13.0,
		"color": Color(0.40, 0.62, 0.85),
		# ⭐ M30.5（路线②）：贴图优先，文件不在就自动回退到形状语言
		"visual": {"texture": "res://art/seals/seal_hex.png"},
		"body_part": "躯干",
		"skill": {
			"kind": "guard",                  # 常驻：替主角挨伤害
			"range": 75.0,
			"transfer": 0.5,
		},
	},
	"惊雷印": {
		"tags": ["雷"],        # 标签：印诀与（将来）推演都靠它
		"shape": "bolt",        # 形状语言：一眼认出是哪个印（先简化成几何图形）
		"rank": 2,                   # 十等：二等精印
		## 炼化满 100% 后**永久生效**的基础属性（和显化期的 passive 分开算，两者可叠）
		"base": {"stat": "attack_cooldown", "value": 0.9},
		"activate": 18.0,
		"drain": 0.0,
		"life": "instant",           # 一次性攻击：落雷落下就自动收回
		"seal_hp_max": 50.0,
		"passive": "attack_cooldown",
		"passive_value": 0.70,
		"radius": 12.0,
		"color": Color(0.72, 0.62, 0.95),
		# ⭐ M30.5（路线②）：贴图优先，文件不在就自动回退到形状语言
		"visual": {"texture": "res://art/seals/seal_bolt.png"},
		"body_part": "左臂",
		"skill": {
			"kind": "bolt",
			"range": 130.0,
			"cooldown": 2.0,
			"damage": 18.0,
			"warn": 0.25,                     # 落雷前的预警时间
		},
	},
	"磐石印": {
		"tags": ["岩"],        # 标签：印诀与（将来）推演都靠它
		"shape": "square",        # 形状语言：一眼认出是哪个印（先简化成几何图形）
		"rank": 1,                   # 十等：一等凡印
		## 炼化满 100% 后**永久生效**的基础属性（和显化期的 passive 分开算，两者可叠）
		"base": {"stat": "essence_max", "value": 15},
		"activate": 14.0,
		"drain": 0.0,
		"life": "timed",            # 一次性防御：套一层盾，到点自动收回
		"life_time": 4.0,
		"seal_hp_max": 60.0,
		"passive": "damage_taken",
		"passive_value": 0.85,
		"radius": 12.0,
		"color": Color(0.60, 0.70, 0.55),
		# ⭐ M30.5（路线②）：贴图优先，文件不在就自动回退到形状语言
		"visual": {"texture": "res://art/seals/seal_rock.png"},
		"body_part": "周身",
		"skill": {
			"kind": "shield",
			"range": 0.0,
			"amount": 30.0,                   # 套一层 30 点的盾
		},
	},

	# ---- 以下三枚是灵师身上的印（M10）。开局你一枚都没有，只能靠强夺拿到 ----
	"云雨印": {
		"tags": ["水"],        # 标签：印诀与（将来）推演都靠它
		"shape": "drop",        # 形状语言：一眼认出是哪个印（先简化成几何图形）
		"rank": 2,
		"base": {"stat": "hp_max", "value": 18},
		"activate": 10.0,
		"drain": 7.0,
		"life": "hold",              # 持续防御：一直在滋润你的气血
		"seal_hp_max": 55.0,
		"passive": "damage_taken",
		"passive_value": 0.90,
		"radius": 12.0,
		"color": Color(0.45, 0.72, 0.90),
		# ⭐ M30.5（路线②）：贴图优先，文件不在就自动回退到形状语言
		"visual": {"texture": "res://art/seals/seal_rain.png"},
		"body_part": "躯干",
		"skill": {
			"kind": "heal",
			"range": 0.0,
			"cooldown": 2.0,
			"heal": 4.0,                       # 每 2 秒给主角回 4 点气血
		},
	},
	"流风印": {
		"tags": ["风"],        # 标签：印诀与（将来）推演都靠它
		"shape": "leaf",        # 形状语言：一眼认出是哪个印（先简化成几何图形）
		"rank": 2,
		## ⭐ 流风印是**移速印**：养熟它，主角才学会「冲刺」（见 MOVE 表）。
		"move": "dash",
		"base": {"stat": "move_speed", "value": 15.0},
		"activate": 12.0,
		"drain": 0.0,
		"life": "instant",
		"seal_hp_max": 45.0,
		"passive": "attack_cooldown",
		"passive_value": 0.85,
		"radius": 10.0,
		"color": Color(0.62, 0.86, 0.72),
		# ⭐ M30.5（路线②）：贴图优先，文件不在就自动回退到形状语言
		"visual": {"texture": "res://art/seals/seal_wind.png"},
		"body_part": "左臂",
		"skill": {
			"kind": "bolt",
			"range": 100.0,
			"cooldown": 1.4,
			"damage": 11.0,
			"warn": 0.15,                    # 又轻又快：单发弱，但几乎不给你反应时间
		},
	},
	"辉光印": {
		"tags": ["光", "爆"],        # 标签：印诀与（将来）推演都靠它
		"shape": "star",        # 形状语言：一眼认出是哪个印（先简化成几何图形）
		"rank": 2,
		"base": {"stat": "essence_max", "value": 12},
		"activate": 16.0,
		"drain": 0.0,
		"life": "timed",
		"life_time": 5.0,
		"seal_hp_max": 70.0,
		"passive": "attack_damage",
		"passive_value": 5.0,
		"radius": 14.0,
		"color": Color(0.95, 0.90, 0.60),
		# ⭐ M30.5（路线②）：贴图优先，文件不在就自动回退到形状语言
		"visual": {"texture": "res://art/seals/seal_light.png"},
		"body_part": "周身",
		"skill": {
			"kind": "shield",
			"range": 0.0,
			"amount": 45.0,                   # 比磐石印更厚的盾
		},
	},
}

## 开局命窍里的**两枚**印，顺序 = 数字键 1 / 2。
## ⭐ 只剩两枚是刻意的：惊雷印 / 磐石印改为**世界获得**（两只精英各掉一枚），
##    让"拿不到 → 拿到 → 还没融合不能用的"这条线在开局就成立。
const SEAL_ORDER := ["灰烬印", "玄甲印"]

## 灵印死亡的代价（待决问题 1）：反噬 = 气血上限 × 这个比例。
const SEAL_DEATH_BACKLASH := 0.15
## 灵印死亡后，该槽位受损、不可用的秒数。
const SLOT_DAMAGED_TIME := 60.0

# ---------------- 世界与分区（M7）----------------
# ⭐ 世界比屏幕大。相机跟着主角走，边界就是世界尺寸。
# ⚠️ M29 起**世界与所有距离减半**（2560×1440 → 1280×720）：相机 zoom = 2，
#    所以屏幕上看到的范围与改动前**完全一样**（683×384 世界像素 = 1366×768 屏幕像素），
#    但每个美术像素占 2×2 个屏幕像素 —— 像素颗粒粗一倍，空间关系不变。
const WORLD := {
	## ⭐ M31 Step 0：**世界容器 3584×3072**（= 112×96 格 × 32px）——《40 屏世界容器架构方案》定案。
	##    ⚠️ 上一版是 5120×2880（160×90 格）：横向收窄 30%、纵向加高 6.7%，
	##    纵横比从 16:9 变成 7:6。旧存档坐标按比例缩放后 clamp（见 SaveGame.VERSION 8）。
	"size": Vector2(3584.0, 3072.0),
}

## 视口与相机缩放（M29）。⭐ 这两个数字决定「1 个美术像素 = 几个屏幕像素」：
##   相机 zoom = 2 且世界与所有距离**减半** → 可见范围 = 视口 ÷ zoom = 683×384 世界像素，
##   屏幕上仍是 1366×768，但每个美术像素占 2×2 个屏幕像素（像素颗粒粗一倍、空间关系不变）。
## ⚠️ 场景里 Camera 的 zoom 必须与 CAMERA_ZOOM 一致 —— 自测守着这一条。
const VIEWPORT := Vector2(1366.0, 768.0)
const CAMERA_ZOOM := 2.0

## 分区。⭐ 分区只是「矩形 + 名字」，但它有三个用途：
##   ① 采集产出（M8：不同区出不同材料）② 敌人配置（M10）③ 让玩家认路
## 四个区各占世界一角，锚点在正中间 —— 从中心出发，四条路各通一个区。
## ⭐ M30.13（用户定案）：「没必要做成四个区域，先做好一个修仙世界」
##    → **一张连续大地图**：地形按**离出生点的远近**分层，越远越硬、越远越好的料。
##    边界用正弦扰动做成**不规则过渡线**（不是四个直角方块）。
## ⚠️ 迁移中：`ZONES`（四分区）暂时**只用来给采集点/敌人打标签**，渲染已经不看它了。
##    下一步把采集点/敌人改成按距离分布 + 把 4 条分区断言换成地形断言，那时才删 `ZONES`。
## ⭐⭐ M30.13c：**世界数据表**（由 `art/tools/gen_worldmap.mjs` 导出，112×96 格 × 32px）
##    R = 地形 id×50 / G = 海拔 / B = 水深 —— **渲染与玩法读同一张表**。
##    ⚠️ 绝不在 GDScript 里重算噪声：那会让「画出来的山」和「判定里的山」变成两座山。
const WORLD_MAP_PATH := "res://art/world/worldmap.png"
const WORLD_COLS := 112
const WORLD_ROWS := 96
const WORLD_CELL := 32.0
## 地形 id → 名字。⚠️ 顺序必须和生成器里的 T 一致（水/草/林/山/灵田/泥沼）
const WORLD_TERRAINS := ["水泽", "草地", "竹林", "灵岩", "灵田", "泥沼"]
## 崖的判定阈值：相邻格高差超过它就算一面崖
const CLIFF_STEP := 0.06
## 海拔 1.0 抬高多少像素。
## ⭐⭐ M31.3 重烘焙：48 → **200**。改它的唯一理由是「**级差与落差的数量级**」：
##    ① **级差**：21 级量化 → 一级 = 1/20 × 200 = **10 世界单位**。
##       硬上限是 **12**（=`CLIFF_STEP` 0.06 × 200）：超过它，相邻台地就被判成崖 ——
##       而 `can_step()` 对高差是**放行**的 → 「画面看着是墙、人却能走上去」，正是用户否决过的观感。
##    ② **落差**：量化后实际跨度 0.75 → 150 世界单位 ≈ **3.1 个身高**（身高 48）。
##       48 的时候落差只有 19px —— 不到半个身高，肉眼读出来是「平铺的花色」而不是「山」。
## 只影响观感（`_draw_world_height` 的 y 偏移 + 裁剪 padding），不参与任何碰撞判定。
##
## ⚠️⚠️ **抬升会「露底色」，这是几何必然，不要当成 padding bug 去修**：
##    每格只画**顶面**（M30.13e 按用户定案删了崖壁竖面），画在 `y - e×ELEV_LIFT`。
##    于是**只要某格的北邻比它高**，北邻就被抬得更高，两格之间露出一段底色，
##    洞高 = `Δe × ELEV_LIFT`（只在**向南下降**的相邻关系上出现；东西向只会错台，不会露洞）。
##    实测全图最大向南下降 0.60 → 洞高 **120px**（在 cell(39,11) 一带）。
##    → **无洞的条件是 `maxΔe × ELEV_LIFT < 一格高(32)`**，即 `ELEV_LIFT < 53`。
##      当前 200 远大于它，所以**地图上有位置是存在洞的**，这是已知且被接受的代价
##      （换它要动渲染层：把竖面画回来，或用连续偏移代替逐格台阶）。
##    ⚠️ 另一条常被误传的判据「`ELEV_LIFT ≤ 视口半屏高`」**不成立**：
##      抬升是**整片平移**，屏幕上缘空出的位置由下方同海拔的格补位，
##      实测抓帧点屏幕内 **0% 未覆盖**。别照这条去改 padding（padding 只决定画哪些格，
##      不改变画在哪；抬升向上，需要补的只有 `pad_dn`，e085fd2 已经补对了）。
const ELEV_LIFT := 200.0

static var _world_img: Image = null
static var _world_tried := false

## 读一次就缓存（112×96 很小；**不要每帧读**）
static func world_image() -> Image:
	if not _world_tried:
		_world_tried = true
		var tex: Texture2D = load(WORLD_MAP_PATH) as Texture2D
		if tex != null:
			var img := tex.get_image()
			if img != null and img.is_compressed():
				img.decompress()
			_world_img = img
	return _world_img

static func world_ready() -> bool:
	var img := world_image()
	return img != null and img.get_width() == WORLD_COLS and img.get_height() == WORLD_ROWS


## ⭐ M31.3：**世界图签名**（`world_sig`）—— 重烘焙 `worldmap.png` 的**安全网**。
##
## 为什么必须先装它：改这张图会**静默**连带改三样东西，且三者都没有任何检测机制 ——
##   ① `speed_mult_at()` 的 `elev >= 0.65` 高地减速 ×0.85（档位一变，移动手感暗中改）
##   ② `gen_worldmap.mjs` 里写死 `e01 = 0.4` 的出生点（LEVELS 一改可能落到水里或崖上）
##   ③ 同心层 / 主城的地块排布（山长在哪儿会变）
## 签名把「意外改动」变成「必须显式确认的改动」：重烘焙后自测必红，逼人去更新基线。
##
## ⚠️ 两条设计纪律：
##   ① **不用引擎的 `hash()`** —— 它的实现不保证跨版本 / 跨机器一致；签名必须可复现。
##      这里自己写两个 32 位整数哈希（FNV-1a + SDBM），纯整数运算，到哪台机器都一样。
##   ② 输入是**解码后的 RGBA8 像素**，不是文件字节 —— 换个编码器重导出、像素没变就不该报警。
const WORLD_SIG_PATH := "res://art/world/worldmap.sig"


static func _sig_fnv(b: PackedByteArray) -> int:
	var h := 2166136261
	for v in b:
		h = ((h ^ v) * 16777619) & 0xFFFFFFFF
	return h


static func _sig_sdbm(b: PackedByteArray) -> int:
	var h := 0
	for v in b:
		h = (v + (h << 6) + (h << 10) - h) & 0xFFFFFFFF
	return h


static func world_sig() -> String:
	var img := world_image()
	if img == null:
		return "no-image"
	var c: Image = img.duplicate()     # ⚠️ 显式标注：`duplicate()` 返回 Variant，不标会推不出类型
	c.convert(Image.FORMAT_RGBA8)      # 统一字节布局，免得编码格式影响签名
	var b: PackedByteArray = c.get_data()
	return "w1-%d-%d-%dx%d" % [_sig_fnv(b), _sig_sdbm(b), c.get_width(), c.get_height()]


## 基线（存在 `art/world/worldmap.sig`）。空串 = 还没建基线。
static func world_sig_baseline() -> String:
	if not FileAccess.file_exists(WORLD_SIG_PATH):
		return ""
	return FileAccess.get_file_as_string(WORLD_SIG_PATH).strip_edges()

static func world_cell(cx: int, cy: int) -> Color:
	var img := world_image()
	if img == null or cx < 0 or cy < 0 or cx >= WORLD_COLS or cy >= WORLD_ROWS:
		return Color(0.0, 0.0, 0.0, 0.0)
	return img.get_pixel(cx, cy)

static func cell_terrain(cx: int, cy: int) -> String:
	var idx := int(round(world_cell(cx, cy).r * 255.0 / 50.0))
	return WORLD_TERRAINS[clampi(idx, 0, WORLD_TERRAINS.size() - 1)]

static func cell_elev(cx: int, cy: int) -> float:
	return world_cell(cx, cy).g

static func cell_depth(cx: int, cy: int) -> float:
	return world_cell(cx, cy).b

static func in_map(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < WORLD_COLS and c.y < WORLD_ROWS

static func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / WORLD_CELL)), int(floor(pos.y / WORLD_CELL)))

static func elev_at_pos(pos: Vector2) -> float:
	var c := cell_of(pos)
	return cell_elev(c.x, c.y)

static func depth_at_pos(pos: Vector2) -> float:
	var c := cell_of(pos)
	return cell_depth(c.x, c.y)


## ⭐ M30.13d：**能不能从这里走到那里** —— 用户在意的「走在山上真的感觉在山上」就靠它。
##    ⚠️ 阈值和崖面渲染是**同一个** `CLIFF_STEP`。用一个、画一个，就会出现
##       「看着是崖却能走上去」或者「看着是平地却被挡住」—— 这种不一致最伤体感。
static func can_step(from_pos: Vector2, to_pos: Vector2) -> bool:
	var a := cell_of(from_pos)
	var b := cell_of(to_pos)
	if b == a:
		return true                       # 同一格内自由移动
	if not in_map(b):
		return true                       # 世界外归 _clamp_world 管，别在这儿判成崖
	if cell_depth(b.x, b.y) > 0.5:
		return false                      # 深水：挡住，得绕行
	# ⭐ M30.13e（用户定案）：「怎么墙给我挡住了，不要墙」
	#    → **高差不挡路**：多高的台地都能直接走上去。高度只保留**视觉**（台地偏移 + 遮挡），
	#      不再当墙用。深水仍然挡（那是水，不是墙）。
	return true


## 地形速度倍率：涉水明显变慢、高地略慢（「山上有分量」）、平地正常
static func speed_mult_at(pos: Vector2) -> float:
	if depth_at_pos(pos) > 0.0:
		return 0.60
	## ⭐ M31.3 重烘焙：0.62 → **0.60（= 12/20）**。
	##    规则：阈值必须**正好落在量化网格的某一级上**（k/20），否则减速带的边界会切在
	##    台面中间 —— 玩家「看着还在坡上，脚感却已经变了」。k/20 让减速边界与台缘重合。
	##    ⚠️ 取哪一级是**实测**定的，不是拍的：烘焙脚本会打印海拔直方图，
	##    13/20 实测只给 28.5%（低于目标 30~45%），12/20 给 **38.2%**（正中间）。
	##    ⚠️ 重烘焙后这张直方图会变 —— **改了烘焙就要回来复核这一级**，别让它悄悄跑偏。
	if elev_at_pos(pos) >= 0.60:
		return 0.85
	return 1.0


## ⭐⭐ M31.1（P0 收尾）：**环状地形那套已经删除**。
##    曾经有三套地形名并存：`zone_at`(四象限 草原/岩区…) / `terrain_at`(环状 灵田/石山/雷泽…)
##    / `cell_terrain`(格子 世界数据 R 通道) —— 三套名字互相不认，读错就出鬼。
##    现在：**`cell_terrain()` 是唯一的地形真相**；环状那套（含 `terrain_at`/`TERRAIN_CELL`）已删。
##    `zone_at` 保留但语义降级为「玩家在哪个象限」，只用于内容标注与历史断言。

## 地形名 → **兜底颜色**。只给 `Game._draw_world_flat()` 用（世界数据缺失时的保险），
## 正常渲染走 128px 地块贴图，不看这张表。
const WORLD_TERRAIN_COLORS := {
	"水泽": Color(0.10, 0.16, 0.24),
	"草地": Color(0.11, 0.14, 0.11),
	"竹林": Color(0.08, 0.12, 0.09),
	"灵岩": Color(0.14, 0.13, 0.12),
	"灵田": Color(0.16, 0.17, 0.11),
	## 泥沼：autotile 还没画，缺图时**这就是玩家看到的东西**。
	## ⚠️ 必须和「水泽」一眼分得开 —— 水泽偏蓝（B 最高），泥沼偏黄褐（R>G>B，B 最低）。
	"泥沼": Color(0.22, 0.19, 0.09),
}


## ⭐ M31 Step 0：四个区的矩形**从世界尺寸算**，不再写死。
##    ⚠️ 以前写死 2560×1440（= 旧世界 5120×2880 的一半）—— 世界一改尺寸，
##    「四个分区正好铺满世界」和「每区 2 处采集点」两条断言立刻假失败。
##    现在世界改多大，分区就跟着铺多大（**分区只是标签**：渲染与产出都不看它）。
static var ZONES: Dictionary = _build_zones()

static func _build_zones() -> Dictionary:
	var h: Vector2 = WORLD["size"] * 0.5          # 切分点 = 世界正中（四象限）
	return {
		"草原": {"rect": Rect2(0.0, 0.0, h.x, h.y), "color": Color(0.11, 0.14, 0.11),
			"visual": {"texture": "res://art/tiles/grass.png"}},
		"岩区": {"rect": Rect2(h.x, 0.0, h.x, h.y), "color": Color(0.14, 0.13, 0.12),
			"visual": {"texture": "res://art/tiles/rock.png"}},
		"雷区": {"rect": Rect2(0.0, h.y, h.x, h.y), "color": Color(0.10, 0.10, 0.16),
			"visual": {"texture": "res://art/tiles/thunder.png"}},
		"热区": {"rect": Rect2(h.x, h.y, h.x, h.y), "color": Color(0.16, 0.10, 0.09),
			"visual": {"texture": "res://art/tiles/heat.png"}},
	}

## 某个世界坐标落在哪个区。采集产出与敌人配置都靠它，避免在数据里重复写区名。
static func zone_at(pos: Vector2) -> String:
	for key in ZONES:
		if (ZONES[key]["rect"] as Rect2).has_point(pos):
			return key
	return ""


# ---------------- 物品（M8）----------------
## 材料表。⭐ 设计圣经 §3.6：材料按**来源**分类，不按颜色分类 ——
## 每一类都对应一条灵印线，所以合炼配方是**可推理的**，玩家能自己摸索。
## `volume` = **占背包多少容积**（M30.4）：草木 1 / 兽材 2 / 矿石 3 / 触媒 3。
## 为什么按类别给而不是「越贵越大」：让「值钱但占地方」和「便宜但好带」同时存在，
## 出门带什么才是个选择（矿石/触媒沉，草木轻）。
## price 是 M14 商人用它买卖的价格（灵石）。
## ⚠️ M30.3：`refine`（药力）**现在没有任何地方在用** —— 炼化已改成只吃灵力（不再投材料）。
##    数字先留着（以后「材料影响合炼成功率」之类可以直接用），但**别以为它还有效果**。
const MATERIALS := {
	# ⭐ M30.2：`use` = **可以直接使用**的效果（背包面板里点「使用」）。没有这一项 = 只能当投料。
	"蕴灵草": {"kind": "草木", "color": Color(0.45, 0.78, 0.42), "price": 4, "volume": 1, "refine": 2,
		"use": {"essence": 25.0}},    # 和「采一口」一样回 25 灵力
	"赤炎花": {"kind": "草木", "color": Color(0.88, 0.42, 0.30), "price": 9, "volume": 1, "refine": 4},
	"玄铁矿": {"kind": "矿石", "color": Color(0.55, 0.58, 0.66), "price": 12, "volume": 3, "refine": 5},
	"雷纹石": {"kind": "矿石", "color": Color(0.62, 0.55, 0.92), "price": 16, "volume": 3, "refine": 7},
	"兽骨":   {"kind": "兽材", "color": Color(0.82, 0.78, 0.66), "price": 6, "volume": 2, "refine": 3},
	"灵魄":   {"kind": "兽材", "color": Color(0.70, 0.86, 0.92), "price": 22, "volume": 2, "refine": 9},
	"地火芯": {"kind": "触媒", "color": Color(0.95, 0.55, 0.25), "price": 40, "volume": 3, "refine": 15},
	"雷髓":   {"kind": "触媒", "color": Color(0.72, 0.68, 1.00), "price": 45, "volume": 3, "refine": 18},
}

## 商人（M14）。⭐ 待决问题 10 的落地：**一个**商人、放在世界中心锚点旁（安全区）、
## **货架一次性、不补货** —— 想买东西就得先出门把灵石赚回来。
## 买卖价差就是他的利润：买价写在货架上，卖价 = MATERIALS[*].price × sell_ratio。
const MERCHANT := {
	"pos": Vector2(1792.0, 1262.9),       # ⭐ 真坐标：出生点 (1792,1536) 正上方 273px —— 安全区内
	"radius": 19.0,
	"reach": 46.0,                      # 站多近能交易
	"color": Color(0.86, 0.78, 0.52),
	"sell_ratio": 0.5,                  # 卖给商人只能拿回半价
	"stock": [
		{"item": "蕴灵草", "count": 5, "price": 6},
		{"item": "兽骨",   "count": 5, "price": 9},
		{"item": "玄铁矿", "count": 3, "price": 17},
		{"item": "地火芯", "count": 1, "price": 55},
		{"item": "雷髓",   "count": 1, "price": 60},
	],
	## ⭐ 服务：不限量、不占货架。这是灵石**永不枯竭的出口** ——
	##    货架会卖光，服务不会。也是灵力的第二个来源（第一个是采集）。
	##    取舍就在这里：同一笔灵石，买材料（合炼）还是买灵力（修炼）？
	"services": [
		{"id": "essence", "label": "灵力", "amount": 25.0, "price": 10},
	],
}

## 货币只有一种（开发计划 §7.1）。灵石不占背包容量。
const CURRENCY := "灵石"

## 背包容量 = **容积**（M30.4 用户定案：「物品应该加一个重量或者占据的容积，放入背包里会占据不同的体积」）。
## ⚠️ 单位从「件」变成了「容积」：每件东西占多少见 `MATERIALS[*].volume`。
##    于是「带什么出门」第一次成为一个真选择：草木 1 格、矿石 3 格。
## ⭐ **灵石不占容积**（货币）；**灵印也不占容积**（见 volume_of：不在材料表里的东西一律 0）。
## ⚠️ 数值 120 的理由：改成容积后旧存档的占用会变大（原来 1 件 = 1，现在 1~3），
##    120 能让「满包的矿石」这种旧档也不至于一进来就爆仓 —— 而且爆仓不丢东西，只是捡不动。
const BAG_CAPACITY := 120

## 掉落物：走过去自动捡。⭐ 不必按 E —— E 的含义是「交互（采集）」，不许一键两义。
## ⭐ M30.1：**同类就近并成一堆**（`merge_radius`）—— 同一件东西落在这个距离内就并进已有的那一堆，
##    数量相加，**东西一件不少**。为什么需要它：背包满时掉落物不会被捡走，而死亡会复活敌人，
##    同一个刷新点被反复打 → 那一带就堆出几十个小方块（又乱，又是每帧都要重绘的活节点）。
##    ⚠️ 只合并**材料与货币**；灵印永远单独一堆（它是唯一的，地上也要一眼看得出那是一枚印）。
const PICKUP := {
	"radius": 15.0,          # 主角走到多近就自动捡起
	"size": 7.0,
	"merge_radius": 40.0,    # 同类就近并堆的距离（世界像素；屏幕上 ×2 = 80px）
}

## 掉落表：按敌人原型。⭐ 固定数量，不做随机掉率 ——
## 随机掉率会让自测变成概率游戏，等有调参台了再上权重。
const ENEMY_DROPS := {
	"猛兽": {"兽骨": 2, "灵石": 3},
	"智谋": {"兽骨": 1, "灵魄": 1, "灵石": 5},
	"灵师": {"灵魄": 2, "灵石": 8},        # 它身上那枚印另外掉（走 carries）
	"蛮兽": {"兽骨": 2, "灵魄": 1, "灵石": 6},
	# ⭐ 精英的掉落 = 原型掉落 × drop_mult，再额外给一份 bonus_drop（见 Game._drop_loot）
}


## 采集点（蕴灵）：走过去按 E 采一口，回灵力，然后这个点就空了。
## ⭐ 它的「空没空」是**锚点快照**的一部分 —— 死亡回锚点时一起复原（待决问题 8）。
const GATHER := {
	"radius": 13.0,           # 采集点自己的大小（绘制用）
	"reach": 29.0,            # 主角要多近才能采
	"essence": 25.0,          # 采一次回多少灵力
	"color_full": Color(0.55, 0.85, 0.95),
	"color_empty": Color(0.26, 0.30, 0.34),
	## ⭐ 两态两张图：满的是一颗灵珠，空的是它的残壳。外面那圈光晕仍由代码画（那是状态）。
	"visual": {"texture": "res://art/world/gather_full.png",
		"empty_texture": "res://art/world/gather_empty.png"},
	## ⭐ 每区 2 处，都离锚点（世界中心）有一段路 —— 想采就得先走出去。
	## ⭐ 一处采集点 = 位置 + 产出 + 数量，写在同一个 dict 里。
	##    （不做「positions 与 yields 两个数组顺序必须对齐」那种平行表 —— 一旦错位没人发现。）
	## 产出规则：安全区（草原 / 岩区）给大宗基础材；危险区（雷区 / 热区）给**触媒**。
	## 这就是「去哪采」的第一层风险回报。
	## ⭐ M31 Step 0：`id`（g01…g08）= 稳定标识，用途同 ENEMY_SPAWNS 的 id（本轮只加字段）。
	"spots": [
		{"id": "g01", "pos": Vector2(420.0, 469.3),   "item": "蕴灵草", "amount": 2},   # 草原
		{"id": "g02", "pos": Vector2(1260.0, 298.7),    "item": "蕴灵草", "amount": 2},   # 草原
		{"id": "g03", "pos": Vector2(2380.0, 426.7),   "item": "玄铁矿", "amount": 2},   # 岩区
		{"id": "g04", "pos": Vector2(3220.0, 1109.3),  "item": "玄铁矿", "amount": 2},   # 岩区
		{"id": "g05", "pos": Vector2(448.0, 2517.3),   "item": "雷纹石", "amount": 2},   # 雷区
		{"id": "g06", "pos": Vector2(1204.0, 2816.0),   "item": "雷髓",   "amount": 1},   # 雷区（触媒）
		{"id": "g07", "pos": Vector2(2464.0, 2645.3),   "item": "赤炎花", "amount": 2},   # 热区
		{"id": "g08", "pos": Vector2(3248.0, 2090.7),  "item": "地火芯", "amount": 1},   # 热区（触媒）
	],
}

# ---------------- 合炼（M13）----------------
## 炉子参数。设计圣经 §3.3：**火候指针在绿区时点击**，失误则失败。
## ⭐ 指针速度刻意做成「一轮约 1.5 秒」—— 太快变成拼手速，太慢变成走流程。
const FURNACE := {
	"pointer_speed": 1.30,      # 指针来回速度（越快越难）
	"green_zone": 0.22,        # 绿区宽度（占整条的比例）
	"essence_cost": 60.0,      # 开一次炉的灵力（设计圣经 §3.3「消耗：灵力」）
	"base_chance": 50.0,       # 成功率基数（%）
	"per_material": 5.0,       # 每多一种辅材 +5%
	"per_soul": 10.0,          # 每个灵魄 +10%
	"per_rank": 10.0,          # 目标每高一等 -10%
	"event_chance": 0.5,       # 合炼中出「填料 / 减料」事件的概率
	"event_bonus": 12.0,       # 答对 +12%
	"event_penalty": 10.0,     # 答错 -10%
}

## 升阶：每一等把**这枚印自己的底子**抬起来多少。
## ⭐ 十等只影响这三样 —— 不改被动、不改形态（形态是数据表里写死的性格，不该被等级洗掉）。
const RANK_GAIN := {
	"seal_hp": 0.25,            # 印的血量 +25% / 等
	"skill": 0.20,              # 招式伤害 +20% / 等
}

## 配方表。⭐ 一张表写全，加配方只加一行。
##   mode = "upgrade"：主材 + 辅材 → **改主材自己的等级**（§3.3 升阶）
##   mode = "craft"  ：a + b + 辅材 → **全新的一枚**（a、b 作材料被消耗，§3.3 合成）
## ⚠️「哪种搭配产出哪一枚」是**设计选择**，不是从设定推导出来的 —— 手感不对就改这张表。
## ⚠️ **本命印不能当材料**（它和魂魄相连）—— 见 Player.can_use_as_material()。
const RECIPES := [
	{"mode": "upgrade", "main": "灰烬印", "to_rank": 2, "materials": {"赤炎花": 2, "地火芯": 1}},
	{"mode": "upgrade", "main": "玄甲印", "to_rank": 2, "materials": {"玄铁矿": 3}},
	{"mode": "upgrade", "main": "惊雷印", "to_rank": 3, "materials": {"雷纹石": 3}},
	{"mode": "upgrade", "main": "磐石印", "to_rank": 2, "materials": {"兽骨": 3}},
	# 合成：守 + 雷 相激而生光
	{"mode": "craft", "a": "玄甲印", "b": "惊雷印", "result": "辉光印",
		"materials": {"雷纹石": 2, "灵魄": 1}},
	# 合成：双土相叠，否极泰来而生水
	{"mode": "craft", "a": "玄甲印", "b": "磐石印", "result": "云雨印",
		"materials": {"玄铁矿": 3}},
	# 合成：雷动石开而生风
	{"mode": "craft", "a": "惊雷印", "b": "磐石印", "result": "流风印",
		"materials": {"雷髓": 1, "兽骨": 2}},
]

# ---------------- 打击感 ----------------
## ⭐ 全部集中在这一张表：**手感不对就改这里，不碰逻辑**。
## 「命中停顿」= 打中的瞬间把时间压慢几十毫秒 —— 这是「打中了」最有效的信号，成本也最低。
const JUICE := {
	"hitstop_on": true,
	"hitstop_scale": 0.05,       # 停顿期间的时间倍率
	"hitstop_hit": 0.035,        # 打中敌人停多久（秒）
	"hitstop_hurt": 0.060,       # 自己挨打停多久 —— 更重一点
	"shake_hit": 1.1,            # 打中敌人的震屏幅度（像素）
	"shake_hurt": 2.5,           # 自己挨打
	"shake_decay": 26.0,         # 震屏衰减速度（越大越快停）
	"numbers": true,             # damage 数字
	"number_life": 0.7,          # 数字活多久
}

## 灵印十等（设计圣经 §二）。⭐ 等级就是**阶级** —— 只有这一套数字，
## 升级 = 升等，靠合炼（M13）产出，不是打怪涨经验。
const RANKS := {
	1: "凡印", 2: "精印", 3: "通印", 4: "宝印", 5: "圣印",
	6: "道印", 7: "劫印", 8: "奇印", 9: "元印", 10: "祖印",
}

## 炼化。⭐ 炼化度挂在**印**上（不是槽位上）：换槽位不该丢炼化。
## 涨法两条腿：用（显化一次涨一点）+ 喂（投材料，大头，按材料本身的「药力」）。
## 满 100% → 这枚印的 `base` 基础属性**永久生效**（不必显化）。
## ⭐ 炼化 = 印与命窍的**融合度**，是**使用前提**：未满 100% 的印完全不能用
##（不能显化、不给被动、不给基础属性）—— "武功得完全学会才能用"。
## 涨法：**点「炼化」按钮花灵力** —— 唯一一条路（M30.3 用户定案：**不再吃材料**，见 SealPanel.do_refine）。
## ⚠️ 旧版那条「显化一次涨一点」已删：新语义下"不能用还怎么用着变熟"是自相矛盾的。
const REFINE := {
	"max": 100.0,
	"press_cost": 10.0,     # 点一次「炼化」花多少灵力
	"press_gain": 8.0,      # 一次涨多少炼化度 → 0→100 约 13 次 = 130 灵力（≈1.3 管）
	"start_refined": 100.0, # 开局自带的那两枚直接给满（否则开局打不了架）
}

## ⭐ M30.4：这件东西占多少**容积**。不在材料表里的一律返回 0 ——
##    于是**灵石（货币）和灵印（收藏）天然不占地方**（用户明确要求：「灵印就不占体积没有重量」）。
static func volume_of(item: String) -> int:
	if item == CURRENCY:
		return 0
	return int((MATERIALS.get(item, {}) as Dictionary).get("volume", 0))


## ⭐ M30.5b：物品的**中文名 → 英文短名**（贴图文件名）。
##    为什么要这张表：中文名**不进文件名** —— 以后改文案 / 换语言时不该动到素材。
##    加一件材料 = 这里加一行 + 跑一次 `art/tools/gen_items.mjs`。
const ART_ID := {
	"蕴灵草": "herb",
	"赤炎花": "flower",
	"玄铁矿": "ironore",
	"雷纹石": "tstone",
	"兽骨": "bone",
	"灵魄": "wisp",
	"地火芯": "ember",
	"雷髓": "marrow",
	"灵石": "stone",
}


## 面板 / 背包里的图标（32×32）。没有短名的返回 {} —— 调用方回退到形状语言。
## ⚠️ 返回的是**实体数据的形状**（`{"visual": {...}}`），不是裸的贴图字典 ——
##    因为 `ActorVisual.texture_of()/draw_unit()` 收的都是「实体数据」。
##    踩过：一开始返回 `{"texture": ...}`，结果 `texture_of()` 找不到 `visual` → 全都回退成菱形。
static func item_visual(item: String) -> Dictionary:
	var id := str(ART_ID.get(item, ""))
	if id == "":
		return {}
	return {"visual": {"texture": "res://art/items/%s.png" % id}}


## 地上的掉落物（8×8）。⭐ 灵印没有这张 —— 地上的印继续用形状语言画（见 Pickup.gd）。
static func item_drop_visual(item: String) -> Dictionary:
	var id := str(ART_ID.get(item, ""))
	if id == "":
		return {}
	return {"visual": {"texture": "res://art/items/%s_drop.png" % id}}


## 本命印：时印回溯时**永远保住**的那一枚（设计圣经 §4.2：第一世的灰烬印）。
## ⭐ 「其余灵印全部失去，只额外留一枚」是 §4.3 的锁定规则，不是保守设计。
const NATAL_SEAL := "灰烬印"

## 锚点：V0.1 只有一个固定锚点（出生点），不可覆盖（待决问题 3）。
## 死亡 → 恢复锚点快照（敌人复活 / 采集点复原）→ 主角回锚点。
## ⚠️ 多锚点与「主动设置锚点」不在 V0.1 范围。

## 灼烧最多叠几层（再多只刷新时长，不继续叠）。
const EMBER_MAX_STACK := 2
## 灵印血量低于这个比例 = 濒死（视觉忽明忽暗，纯表现，不影响数值）。
const SEAL_DYING_RATIO := 0.30


# ---------------- 敌人（M4）----------------
# ⭐ 和灵印表同一套思想：一条数据 = 一种敌人。加第三种只加一行，AI 一行都不用改。
#    seal_seek_chance 是「转向最近的显化灵印」的概率 —— 待决问题 2 的 V0.1 简化版：
#    猛兽型恒为 0（它只打主角），智谋型 30%。
## 灵师落雷的圈有多大。⭐ 预警圈画的就是它 —— 圈里才是会被打到的范围。
const CAST_RADIUS := 22.0

## 形状语言（M11）：每种原型一个**固定形状**。⭐ 怪物一多，「一眼分辨」就是功能需求，不是审美。
##   melee 圆 / hunter 方 / caster 菱 / charger 三角；精英一律再加一圈双外环 + 体型放大。
const SHAPES := {
	"melee": "circle",
	"hunter": "square",
	"caster": "diamond",
	"charger": "triangle",
}

## 精英规格。⭐ 精英不是新原型，是**同一个原型加档** ——
## 所以同一个 AI、同一个形状，只是更大更硬更疼，掉得也更多。
const ELITE := {
	"hp_mult": 3.0,
	"damage_mult": 1.5,
	"radius_mult": 1.35,
	"drop_mult": 3,
	"bonus_drop": "灵魄",     # 精英额外掉的高级辅材
}

const ENEMY := {
	"猛兽": {
		"behavior": "melee",
		"hp_max": 70.0,
		"radius": 17.0,
		"color": Color(0.78, 0.35, 0.30),
		"visual": {"texture": "res://art/units/enemy_beast.png", "offset": Vector2(0.0, -14.0)},
		"speed": 46.0,             # 追击速度（像素/秒）
		"aggro_range": 130.0,      # 进这个距离才开始追
		"attack_range": 18.0,      # 进这个距离才能打
		"attack_damage": 9.0,
		"attack_cooldown": 1.10,   # 两次攻击的最小间隔（秒）
		"seal_seek_chance": 0.0,
	},
	## 灵师：会**显化灵印**的对手。远程、站桩施法、施法前有预警。
	## ⭐ 打死它 → 可以强夺它身上那枚印（代价：契合度归零 = 抢来的印没有被动）。
	"灵师": {
		"behavior": "caster",
		"hp_max": 70.0,
		"radius": 16.0,
		"color": Color(0.38, 0.80, 0.86),
		"visual": {"texture": "res://art/units/enemy_caster.png", "offset": Vector2(0.0, -14.0)},
		"speed": 48.0,
		"aggro_range": 170.0,     # 视野最远
		"attack_range": 110.0,    # 打得也最远
		"attack_damage": 11.0,
		"attack_cooldown": 2.20,
		"seal_seek_chance": 0.45, # 它懂印 —— 更爱打你显化的灵印
		"keep_distance": 82.5,   # 走到这么近就停下施法，不贴脸
		"cast_warn": 0.45,        # 施法预警：给玩家闪开的时间
	},
	## 蛮兽：冲锋型。先**蓄力预警**（方向性，不是圈），再高速撞过来。
	## ⭐ 它和灵师要玩家做的事正好相反：灵师的圈要「走出去」，它的冲要「横着闪」。
	"蛮兽": {
		"behavior": "charger",
		"hp_max": 85.0,
		"radius": 18.0,
		"color": Color(0.86, 0.56, 0.24),
		"visual": {"texture": "res://art/units/enemy_charger.png", "offset": Vector2(0.0, -14.0)},
		"speed": 40.0,
		"aggro_range": 165.0,
		"attack_range": 15.0,
		"attack_damage": 16.0,
		"attack_cooldown": 1.80,
		"seal_seek_chance": 0.15,
		"charge_range": 150.0,   # 进这个距离就开始蓄力
		"charge_warn": 0.55,     # 蓄力多久（给玩家闪开的时间）
		"charge_speed": 270.0,   # 冲刺速度
		"charge_time": 0.34,     # 冲刺持续多久
	},
	"智谋": {
		"behavior": "hunter",
		"hp_max": 55.0,
		"radius": 16.0,
		"color": Color(0.55, 0.45, 0.80),
		"visual": {"texture": "res://art/units/enemy_hunter.png", "offset": Vector2(0.0, -14.0)},
		"speed": 38.0,
		"aggro_range": 150.0,
		"attack_range": 21.0,
		"attack_damage": 7.0,
		"attack_cooldown": 1.30,
		"seal_seek_chance": 0.30,  # 30% 概率改打显化中的灵印
	},
}

## 敌人出生点。⭐ 刻意放得离假人很远 ——
## 不然 M1 那条「伤害区命中 1 个目标」会因为顺手打到敌人而变红。
## ⭐ 出生点是世界正中 (1792, 1536)。最近的敌人是南北路口的 (1792,384) / (1792,2773.3)，
##    离出生点 1152 / 1237 px —— 都在仇恨圈（130 / 170 / 165，见 ENEMIES）**外面**，
##    所以走几步才会被发现，不会一开局就被围。假人离出生点约 352 px（M1 的验收基线）。
## ⚠️ M31 Step 0：以下坐标**就是世界像素真坐标**（单位 = 世界像素，世界 3584×3072）。
##    以前这里写的是「1280×720 设计空间」的坐标、运行时再乘 wscl —— 那套双重坐标系已删除。
##    ⚠️ 注意纵横比变了（16:9 → 7:6），所以各点之间的**距离不是等比缩放**，
##    但每个点落在世界里的**相对位置**（占世界的百分比）与改动前一致。
## ⭐⭐ M31 Step 0：`id` = **稳定标识**（e01…e13）。它是为「存档从数组下标改成稀疏 id 集合」铺路 ——
##    将来增删 / 重排刷新点，存档里已打死的敌人不会串位。**本轮只加字段，不动存档结构**。
const ENEMY_SPAWNS := [
	{"id": "e01", "archetype": "猛兽", "pos": Vector2(700.0, 896.0)},       # 草原
	{"id": "e02", "archetype": "智谋", "pos": Vector2(2940.0, 640.0)},      # 岩区
	{"id": "e03", "archetype": "猛兽", "pos": Vector2(560.0, 2346.7)},       # 雷区
	{"id": "e04", "archetype": "智谋", "pos": Vector2(3080.0, 2560.0)},      # 热区
	{"id": "e05", "archetype": "猛兽", "pos": Vector2(1792.0, 384.0)},        # 北边路口
	{"id": "e06", "archetype": "智谋", "pos": Vector2(1792.0, 2773.3)},       # 南边路口
	# ⭐ 三名灵师各带一枚印。雷区故意不放灵师 —— 留一个「只有材料、没有硬仗」的区。
	{"id": "e07", "archetype": "灵师", "pos": Vector2(868.0, 640.0), "carries": "流风印"},      # 草原
	{"id": "e08", "archetype": "灵师", "pos": Vector2(3052.0, 896.0), "carries": "辉光印"},     # 岩区
	{"id": "e09", "archetype": "灵师", "pos": Vector2(2772.0, 2261.3), "carries": "云雨印"},      # 热区
	# ⚠️ 这只蛮兽原来在 (1600,620) —— 离商人 (1280,592) 只有 322px，正好在它的仇恨圈（330）里，
	#    站在商人旁边交易会被它追着打。往东挪开，让「锚点 + 商人」这一带真的是安全区。
	{"id": "e10", "archetype": "蛮兽", "pos": Vector2(2660.0, 1664.0)},       # 中路偏右（真坐标，离商人 956px）
	{"id": "e11", "archetype": "蛮兽", "pos": Vector2(1372.0, 2560.0)},       # 雷区
	# ⭐ 精英都摆在**离锚点最远的两个角落** —— 越远越硬，这是最朴素的风险回报梯度
	{"id": "e12", "archetype": "智谋", "pos": Vector2(3388.0, 362.7), "carries": "惊雷印", "elite": true},     # 岩区深处
	{"id": "e13", "archetype": "蛮兽", "pos": Vector2(3360.0, 2816.0), "carries": "磐石印", "elite": true},    # 热区深处
]


## Godot 默认字体不含中日韩字形，这里直接向系统要一份中文字体。
##
## ⚠️⚠️ 性能红线（M29.6）：`SystemFont.new()` 实测要 **5152 µs**（它得去系统里解析 / 加载字体），
##    而 `Pickup._draw()` **每帧**都会问一次字体 —— 于是地面上每一个「数量 > 1」的掉落物
##    每帧白烧约 6 毫秒；地上堆满时实测从 238 FPS 掉到 **13 FPS**。
##    → 这里缓存一份，全项目共用同一个 Font 对象。字体是只读资源，共享完全安全。
##    ⚠️ 以后任何 `_draw()` / `_process()` 里都**不许** `new()` Resource（字体 / 贴图 / 材质 / Tween），
##       必须在 `_ready()` 里取一次存起来；自测里有一条源码扫描断言专门拦这个（见 _check_draw_hot_paths）。
static var _font_cache: Font = null

static func make_font() -> Font:
	if _font_cache != null:
		return _font_cache
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "微软雅黑", "SimHei", "黑体",
		"Noto Sans CJK SC", "Source Han Sans SC", "PingFang SC",
		"WenQuanYi Micro Hei", "sans-serif",
	])
	f.allow_system_fallback = true
	_font_cache = f
	return _font_cache
