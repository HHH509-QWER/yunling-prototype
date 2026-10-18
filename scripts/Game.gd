extends Node2D
## 《蕴灵印》原型主控。
##
## M0：WASD 移动 + 鼠标朝向          —— 跑通「看得见、动得了」
## M1：鼠标左键普攻 + 会掉血的假人    —— 跑通「打得到、掉得了血」
## M2：--selftest 自测钩子           —— 改完之后，一条命令告诉你有没有弄坏东西
##
## 这个工程刻意保持小。规矩只有一条：
##   ⭐ 每一行你都得能解释。解释不了的，宁可先不写。
## 写不出来的地方，去 Desktop\gu\ 看思路，然后自己敲一遍 —— 不要复制。

const EnemyScript := preload("res://scripts/Enemy.gd")
const GatherScript := preload("res://scripts/Gather.gd")
const BagPanelScript := preload("res://scripts/BagPanel.gd")
const ItemsScript := preload("res://scripts/Items.gd")
const PickupScript := preload("res://scripts/Pickup.gd")
const SaveGameScript := preload("res://scripts/SaveGame.gd")
const SmithScript := preload("res://scripts/Smith.gd")
const MerchantScript := preload("res://scripts/Merchant.gd")
const TradeScript := preload("res://scripts/Trade.gd")
const ForegroundLayerScript := preload("res://scripts/ForegroundLayer.gd")

var player: Player = null
var dummies: Array = []        # 场上所有假人（M1 的靶子，一直留着当验收基线）
var enemies: Array = []        # 场上所有敌人（M4）
var hits: Array = []           # 短命伤害区，只用于判定和显示
var swings: Array = []         # ⭐ M30.7：掌风弧光（**纯表现**，不参与任何判定）
var font: Font = null

## 锚点。⭐ V0.1 固定一个、不可覆盖（待决问题 3：开局自动设，免得第一次死亡劝退）
var spawn_point := Vector2.ZERO
var deaths := 0                   # 死过几次 —— 自测靠它判断「死亡流程有没有触发」

var gathers: Array = []           # 场上所有采集点
var pickups: Array = []           # 地上所有掉落物

## 刚捡到东西时给 HUD 的提示（"获得 兽骨 ×2"）。
var pickup_toast := ""
var pickup_toast_t := 0.0
## 背包满了的提示（同样是给 HUD 看的）。
var bag_full_hint := false
## 地上这枚印你**已经有一枚**了（同时唯一性 §2.1）时的提示 —— 也是给 HUD 看的。
## ⚠️ M29.5 起「命窍满」不再是失败：装不进命窍的印进**背包**（收藏无上限）。
var seize_dup_hint := false
## 锚点快照：敌人（谁活着 / 在哪 / 多少血）+ 采集点（哪些空了）。
## ⭐ 死亡 = 恢复这张快照 —— 死之后杀掉的敌人会回来、采空的点会复原（待决问题 8）。
var snapshot: Dictionary = {}

## 自测模式下**不写盘** —— 免得跑一次自测就把玩家的真存档冲掉。
var selftest := false

## 打击感：飘字与震屏（参数在 GameData.JUICE）。
var numbers: Array = []
var shake := 0.0
## 命中停顿的**真实时间**截止点（毫秒）。0 = 没有停顿在进行。
var _hitstop_until_ms := 0

var hud: Control = null           # 屏幕层 HUD（在场景里，由 _ready 接线）
## ⚠️ M28：RewindPanel 的变量与接线已移除（回溯暂停）。场景节点还留着，等重新设计时接回。
var camera: Camera2D = null       # 跟着主角走的相机（在场景里，由 _ready 接线）
## ⭐ M31.3：**前景遮挡开关**（默认关）。开法：命令行加 `-- --foreground`，或游戏里按 **F9**。
##    打开后走进竹林能看见树冠盖住上半身 —— 斜 45° 视角下遮挡是自动产生的，
##    先把开关递到用户手里看过再定价，不替他决定（M30.24 那条定案只是嫌那一版执行丑）。
##    ⚠️ 默认关 = 场景树完全不变（节点懒建），对自测零影响。
var fg_occlusion := false
var fg_layer: Node2D = null       # 懒建：第一次打开时才挂上来
## ⭐ M31.3：**南向裙边**开关（F11，默认关）。
##    每格只画顶面 ⇒ 北邻比自己高时，两格之间露出一条**底色竖条**，
##    缝高 = Δe×ELEV_LIFT（实测 h21×w64 = 一级台阶 × 一格宽 @zoom2）。
##    裙边 = 把自己（低格）的顶面**同色同纹理向上延伸** Δ 顶到北邻底边 ——
##    ⚠️ 不是"画一面崖壁墙"：M30.13e 用户否决的正是"灰墙看着像地图上乱摆的障碍"。
##    ⇒ 不许描边 / 阴影 / 渐变，那些会让它读成独立物件而不是地形本身的延续。
##    ⚠️ 与 F9/F10 同一个规矩：**默认关，把待验证假设变成点一下**，让用户自己定价。
## ⚠️⚠️ **只填 ≤ 一级台阶的缝**（`SKIRT_MAX`）。更大的缝**不许在渲染层糊**：
##    一条 122 世界单位（2.5 个身高）的同色竖条 = 一面地色的墙，而 `can_step()` 对高差放行
##    ⇒ 正是 `GameData.ELEV_LIFT` 注释里写死的那句「画面看着是墙、人却能走上去，用户否决过」。
##    大缝是**数据层**的问题（见 `_check_world_terrain()` 末尾那条预警），回去查烘焙，别在渲染层盖。
const SKIRT_MAX := 10.5    # 一级台阶 = 量化步长 1/20 × ELEV_LIFT 200 = 10，留 0.5 浮点余量
var skirt := false
var seal_panel: Control = null    # 命窍 / 炼化面板（在场景里，由 _ready 接线）
var forge_panel: Control = null   # 合炼面板（在场景里，由 _ready 接线）
var trade_panel: Control = null   # 交易面板（在场景里，由 _ready 接线）
var bag_panel: Control = null     # 背包面板（M30.2；**代码建的** —— 新面板不动场景文件）

var merchant = null               # 商人（代码建的，货架跟着世界走）
## 货架：材料 -> 剩余。⭐ 它是**世界状态**：进快照、进存档（买过就少了，回溯会退回来）。
var merchant_stock: Dictionary = {}



var _pass := 0
var _fail := 0

## ⭐ M31.3：自测**基线只看下界**。文档曾写 583、实测 584、grep 得 582 —— 三个数字打架的根因是
##    断言数本来就随代码增长而变。**锁死"恰好 584"是脆的**：谁加一条断言就红，谁删一条也红，
##    两种红长得一样，逼人去人工判断"是涨了还是跌了"—— 而人工判断正是会漏的环节。
##    所以只锁下界：只能涨不能跌。删断言 → 红；加断言 → 绿并打印实际值。
const SELFTEST_MIN := 584
## 自测**有没有跑完**的标记（防假绿灯，见 `_selftest_finish()`）。
var _st_started := false
var _st_done := false
var _st_finished := false
var _st_manual_tick := false      # 自测手动喂 `_process` 时置 1（免得被当成"该收尾了"）


func _ready() -> void:
	font = GameData.make_font()

	# HUD 是场景里的节点（不是代码建的）；把主控接给它，它自己去读玩家状态
	hud = $HudLayer/Hud
	hud.game = self

	camera = $Camera                 # 相机在场景里（边界在编辑器里看得见）
	## ⭐ M30.25：**相机边界跟着世界走** —— 世界从 1280×720 变成 5120×2880，
	##    边界原来写死在 .tscn 里（0/1280/0/720），不改就等于把人锁在左上角那口井里。
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(GameData.WORLD["size"].x)
	camera.limit_bottom = int(GameData.WORLD["size"].y)
	_setup_lighting()
	# ⭐ M30.29 后处理（泛光 + 色彩分级 + 暗角）—— **是开着的**，画面「电影感」的来源。
	#    ⚠️ 这里原来写着「暂时关闭：开启后游戏启动即崩」—— **那条注释是过期的**（M31 实测推翻）：
	#       ① headless 与窗口模式跑 `--selftest` 都不崩；
	#       ② 工程自带的 `tests/fx_probe.tscn` 探针实测
	#          `FXPROBE screen ... diff=0.000 VERDICT=PASS` —— 它验的正是这里用的
	#          「屏幕纹理采样 shader」，在 `gl_compatibility` 下支持良好。
	#       真实状态一直是「开着且没崩」，只是注释没跟着改，把后来人吓住了。
	#    ⚠️ 教训（架构要求）：**凡能变成断言的要求一律升级成断言** —— 注释会与代码脱节，断言不会。
	_setup_post_fx()
	seal_panel = $HudLayer/SealPanel
	seal_panel.closed.connect(_on_seal_panel_closed)
	forge_panel = $HudLayer/ForgePanel
	forge_panel.closed.connect(_on_seal_panel_closed)      # 同样是「关了就恢复时间」
	trade_panel = $HudLayer/TradePanel
	trade_panel.closed.connect(_on_seal_panel_closed)

	# ⭐ M30.2：背包面板（B）。**代码建的** —— 它是新面板，代码建就不动 scenes/Main.tscn；
	#    世界里的东西（玩家 / 敌人 / 采集点 / 掉落物 / 商人）本来就大多是代码建的。
	bag_panel = BagPanelScript.new()
	bag_panel.name = "BagPanel"
	bag_panel.game = self
	$HudLayer.add_child(bag_panel)
	bag_panel.closed.connect(_on_seal_panel_closed)

	# 命令行钩子，跑法见 README「怎么跑自测」
	# ⭐ 也认一个标记文件（res://.godot/run_selftest 内容为 1）：本机进程启动被沙箱拦下时，
	#    仍然能由编辑器启动、用这个标记触发自测 —— 跑完把内容改成 0 即可。
	#    放在 .godot/ 里是因为它被 gitignore（不进仓库），而且一定是可写的工作区路径。
	# ⭐ M31.3：前景遮挡开关（默认关）。放在自测分支**之前**，探针跑起来也能带上它。
	if OS.get_cmdline_user_args().has("--foreground"):
		_set_fg_occlusion(true)
	# ⭐ M31.3：南向裙边开关（`--skirt`），与前景遮挡同一套：默认关，抓帧对照时显式开。
	if OS.get_cmdline_user_args().has("--skirt"):
		skirt = true
	# ⭐ M31.3：**世界图签名** —— 重烘焙后启动即报警（自测里还有断言兜底，见 `_check_world_sig`）。
	_check_world_sig()
	# ⭐ M31.3：`--worldsig` = 重建基线。**这是唯一的更新路径**，见 `_regen_world_sig()`。
	if OS.get_cmdline_user_args().has("--worldsig"):
		_regen_world_sig()
		return

	var want_selftest := OS.get_cmdline_user_args().has("--selftest")
	if not want_selftest and FileAccess.file_exists("res://.godot/run_selftest"):
		want_selftest = FileAccess.get_file_as_string("res://.godot/run_selftest").strip_edges() == "1"
	if want_selftest:
		_run_selftest()
		return

	_build_world()
	load_game()                      # 有存档就读回来（设锚时写的那一份）


# ==================== 搭世界 ====================

func _build_world() -> void:
	player = Player.new()
	player.game = self      # ⭐ 接线：Player 通过 game 回调主控，见 Player._attack_input()
	player.name = "Player"  # 代码建的节点默认叫 @Node2D@N，起了名运行时场景树才看得懂
	spawn_point = GameData.WORLD["size"] * 0.5      # ⭐ M7：锚点从「屏幕中心」搬到「世界中心」
	player.position = spawn_point
	player.died.connect(_on_player_died)
	add_child(player)

	## ⭐ M31 Step 0：数据表里的坐标**已经是世界真坐标**（由 art/tools/once_bake_world_coords.py
	##    一次性烘焙提交）—— 全工程只剩一套坐标，这里不再乘任何缩放系数。
	for pos: Vector2 in GameData.DUMMY["spawns"]:
		_spawn_dummy(pos)

	for spec: Dictionary in GameData.ENEMY_SPAWNS:
		_spawn_enemy(str(spec["archetype"]), spec["pos"] as Vector2, str(spec.get("carries", "")), bool(spec.get("elite", false)))

	for spot: Dictionary in GameData.GATHER["spots"]:
		_spawn_gather(spot["pos"] as Vector2, str(spot["item"]), int(spot["amount"]))

	# 货架 + 商人（M14）
	merchant_stock.clear()
	for entry in GameData.MERCHANT["stock"]:
		merchant_stock[str(entry["item"])] = int(entry["count"])
	_spawn_merchant()

	# ⭐ 开局在出生点拍一张快照 = 设下「不可覆盖的初始锚点」（待决问题 3）
	take_snapshot()                                  # 顺便拍下时间线第一帧 + 钉住锚帧


## 画世界：四个分区的底色 + 世界边框 + 区名。
## ⭐ 区名画在分区正中 —— 「我走进哪个区了」这件事必须一眼看得出。
## ⭐ M30.13c：世界渲染的缓存。世界是**静态**的 —— 排序只算一次，不在 _draw 里每帧分配
##    （项目有性能红线：_draw 里不许出现分配/字体/缓动）
var _world_order: Array = []
var _world_order_ready := false
var _tile_cache: Dictionary = {}

func _world_tile(path: String) -> Texture2D:
	if not _tile_cache.has(path):
		_tile_cache[path] = load(path) as Texture2D
	return _tile_cache[path]

func _world_tile_of(tn: String) -> Texture2D:
	match tn:
		"竹林": return _world_tile("res://art/tiles/grass.png")
		"灵岩": return _world_tile("res://art/tiles/rock.png")
		"灵田": return _world_tile("res://art/tiles/grass.png")
		## ⭐ M31.3：泥沼还没有自己的贴图，先用草地底 + 调色顶着（见 `_world_tint_of`）。
		##    等美术出图只要改这里一行，别的地方都不用动。
		"泥沼": return _world_tile("res://art/tiles/grass.png")
		_: return _world_tile("res://art/tiles/grass.png")

func _world_tint_of(tn: String) -> Color:
	match tn:
		"竹林": return Color(0.60, 0.78, 0.60)      # 竹林 = 草地压暗偏绿（没有独立贴图，先靠调色）
		"灵田": return Color(1.15, 1.18, 0.92)      # 灵田 = 偏黄
		"泥沼": return Color(0.86, 0.80, 0.58)      # 泥沼 = 压暗偏黄褐（湿地，不是水：不偏蓝）
		_: return Color(1.0, 1.0, 1.0)

## ⭐ M30.26：**实体激活半径**（interest management）—— 大世界真正该先做的一步。
##    地形已经有「只画可见格」的裁剪，但**实体**（敌人/掉落/采集点/假人）每个都在
##    _process + _draw —— 数量一多就掉帧。离玩家足够远的直接停处理、不绘制，走近再唤醒。
##    ⚠️ 两条纪律：
##      ① **自测模式跳过**：测试要在同一帧里摆弄远处的敌人，不能被休眠掉。
##      ② **回滞**（唤醒 900 / 休眠 1040）：在边界上来回走不会每帧开关闪烁。
const ACTIVE_R := 900.0
const SLEEP_R := 1040.0


func _tick_activation() -> void:
	if selftest or player == null or not is_instance_valid(player):
		return
	_apply_activation(enemies, player.position)
	_apply_activation(pickups, player.position)
	_apply_activation(gathers, player.position)
	_apply_activation(dummies, player.position)


func _apply_activation(arr: Array, pp: Vector2) -> void:
	for e in arr:
		if e == null or not is_instance_valid(e):
			continue
		var d := (e.position as Vector2).distance_to(pp)
		var want: bool = e.is_processing()      # 回滞区间内保持原状（显式 bool：e 是无类型数组元素，推断不出）
		if d > SLEEP_R:
			want = false
		elif d <= ACTIVE_R:
			want = true
		if e.is_processing() != want:
			e.set_process(want)
			e.set_physics_process(want)
			e.visible = want


## ⭐ M30.27：**远景层 / 空气透视** —— 「大世界」四根支柱里最值的一条：
##    ① **边缘雾**：世界四周一圈雾，越靠边越浓 —— 大脑把它读成「那边还有很远」。
##    ② **山脊剪影**：北边界一条锯齿山脊，颜色**洗淡偏青蓝**（空气透视），
##       并且**只跟着相机挪一小部分**（视差 0.35）→ 它看起来「在很远的后方」。
##    ⚠️ 两条纪律：
##      · 必须画在世界之前（背景）；
##      · 全部由**位置**算（不用随机数），所以每帧稳定、不会闪。
## ⭐ M30.28：**环境压暗 + 点光** —— 画面从"能看"到"有氛围"的开关。
##    `CanvasModulate` 把整个 2D 画布压暗并染冷色；`PointLight2D` 在关键位置打暖光。
##    ⚠️ 三条纪律：
##      ① 压暗要**温和**（0.7 左右）：太暗就看不清怪和采集点了。
##      ② 点光**数量要少**（现在是 6 处）：光源多了又会把"暗"抵消掉。
##      ③ 光照是**纯表现**，不参与任何判定 —— 关掉它玩法一点不变。
## ⭐ M30.29：**后处理皮层**（泛光 + 色彩分级 + 暗角）—— 画面"电影感"的来源。
##    ⚠️ 为什么用 shader 而不是 Environment：我们的渲染器是 `gl_compatibility`，
##       Environment 的 glow/DOF **不支持**；但只要挂一层 CanvasLayer + ColorRect + 屏幕采样，
##       泛光/分级/暗角全都能做（这条是 Compatibility 下的正确解法）。
##    ⚠️ 层级：layer = 100 → 画在游戏之上（但低于调试 UI）。
func _setup_post_fx() -> void:
	var sh: Shader = load("res://art/fx/post_fx.gdshader") as Shader
	if sh == null:
		return                                   # shader 没导入就整个跳过（不改画面，也不崩）
	var cl := CanvasLayer.new()
	cl.name = "PostFx"
	cl.layer = 100
	add_child(cl)
	var cr := ColorRect.new()
	cr.name = "Screen"
	cr.set_anchors_preset(Control.PRESET_FULL_RECT)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE   # ⚠️ 别吃掉鼠标：普攻/朝向都靠它
	var mat := ShaderMaterial.new()
	mat.shader = sh
	cr.material = mat
	cl.add_child(cr)


func _setup_lighting() -> void:
	var cm := CanvasModulate.new()
	cm.name = "AmbientTint"
	cm.color = Color(0.62, 0.66, 0.78)      # 压暗 + 偏冷（夜里/仙气的底子）
	add_child(cm)
	var tex: Texture2D = load("res://art/fx/light_radial.png") as Texture2D
	if tex == null:
		return                                  # 贴图没导入就只压暗，不点灯（不让它把游戏弄崩）
	## 光的位置**跟着数据走**（商人 + 采集点），不是我瞎摆
	var spots: Array = []
	spots.append(GameData.MERCHANT["pos"])
	for s in GameData.GATHER["spots"]:
		spots.append(s["pos"] as Vector2)
	for i in range(mini(spots.size(), 6)):
		var l := PointLight2D.new()
		l.texture = tex
		l.position = spots[i]
		l.energy = 0.9
		l.texture_scale = 2.2
		l.color = Color(1.0, 0.88, 0.70)        # 暖光（和冷色环境形成对比）
		l.shadow_enabled = false                 # 阴影先不开：要 LightOccluder2D，下一批
		add_child(l)


func _draw_far() -> void:
	## ⭐ M30.30：**远景层（最终版）** —— 只做两件事：世界上下边缘的薄雾带。
	##    ⚠️ 之前那版（6 层 × 4 边 + 北侧山脊）在实机上会让**整屏变黑**，
	##       而最小化函数体后地形又正常 → 说明是那些大面积叠加矩形在 Compatibility 下的绘制问题。
	##       所以这里**只用两条最简单的雾带**（不做循环、不做山脊），先把"边缘有雾"落地；
	##       山脊剪影留到以后用真实的远景贴图（美术图）来做，而不是程序画条带。
	var ws2: Vector2 = GameData.WORLD["size"]
	draw_rect(Rect2(Vector2(0.0, 0.0), Vector2(ws2.x, 200.0)), Color(0.56, 0.63, 0.72, 0.10))
	draw_rect(Rect2(Vector2(0.0, ws2.y - 200.0), Vector2(ws2.x, 200.0)), Color(0.56, 0.63, 0.72, 0.10))



## ⭐ M30.27：**云带**（前景薄雾）—— 低透明度、缓慢横向漂移，给画面"气"。
## ⭐ M31.3：**云从"三条矩形"改成"一团"** —— 一团 = 6 个半径不同的重叠圆，
##    边缘靠圆的交叠堆出来，不再是方角。之前那版是 `draw_rect`，一眼看得出是条。
##    ⚠️ 全部由**时间与序号**算（无随机数）→ 每帧稳定、不会闪。
func _draw_clouds() -> void:
	var ws: Vector2 = GameData.WORLD["size"]
	var t := float(Time.get_ticks_msec()) / 1000.0
	for b in range(3):
		var yy := ws.y * (0.20 + 0.30 * float(b)) + sin(t * 0.13 + float(b)) * 20.0
		var xx := fmod(t * (6.0 + float(b) * 4.0) + float(b) * 1400.0, ws.x + 1200.0) - 600.0
		_draw_puff(xx, yy, 150.0 - 34.0 * float(b), 0.055 - 0.007 * float(b))


## 一团云：6 个圆叠出蓬松边缘（比矩形贵不了多少，但一眼就是云）
func _draw_puff(cx: float, cy: float, w: float, a: float) -> void:
	var col := Color(0.78, 0.84, 0.90, a)
	draw_circle(Vector2(cx, cy), w * 0.30, col)
	draw_circle(Vector2(cx + w * 0.02, cy + w * 0.11), w * 0.24, col)
	draw_circle(Vector2(cx - w * 0.26, cy + w * 0.07), w * 0.21, col)
	draw_circle(Vector2(cx + w * 0.29, cy + w * 0.05), w * 0.19, col)
	draw_circle(Vector2(cx - w * 0.10, cy - w * 0.13), w * 0.18, col)
	draw_circle(Vector2(cx + w * 0.13, cy - w * 0.11), w * 0.16, col)


## ⭐ M31.3：**远山剪影**（两层 + 空气透视）—— 「修仙界」里"大"的那一半。
##
## **为什么画在世界之后、而不是之前**：俯视角没有地平线，世界铺满整屏，
##    画在背景层会被地形整片盖掉、一点都看不见。山必须落在**屏幕顶部那条带**上，
##    压在地形之上 —— 那一条带在玩家眼里就是"北边、很远"。
##
## **为什么用缓存折线 + draw_set_transform**：项目红线是 `_draw()` 里不许分配。
##    山脊形状是**静态**的（只由峰序号决定），所以只建一次，每帧只挪绘制原点。
##
## **视差**：远层 0.18 / 近层 0.35 —— 挪得越慢，大脑读成越远。
## **空气透视**：远层更淡更青蓝、近层更实更深（现实里越远越被空气"洗白"）。
##
## ⚠️ 三条纪律：
##   ① alpha 压得很低（≤0.34）+ 下缘三层渐隐 —— 绝不遮住怪和采集点；
##   ② 自测模式跳过（与 `_draw_far()` 一致：自测不跑表现层，省得 headless 里空转）；
##      ⚠️ 更正一处旧注释：`tests/fx_probe.tscn` 是**独立场景**，根本不加载 Game.gd，
##         它翻不翻红和这里没关系 —— 真正的原因只是"自测不测表现层"。
##   ③ **必须把 transform 复位**：`draw_set_transform` 会影响之后所有绘制调用。
const RIDGE_STEP := 128.0
const RIDGE_W := 4352.0          # 够宽：视差位移 0.65×3584 + 一屏，走到东边也不会露出端点
const RIDGE_BAND := 150.0        # 山脚相对屏幕顶的位置（世界像素）
const RIDGE_PAR := [0.18, 0.35]  # 远层 → 近层（视差系数，越小越远）
const RIDGE_COL := [Color(0.58, 0.65, 0.75, 0.24), Color(0.38, 0.44, 0.55, 0.32)]
var _ridge_polys: Array[PackedVector2Array] = []


## 峰高只由 (序号, 层) 决定 → 同一座山永远一样高，不闪、不抖
func _ridge_poly(layer: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := int(RIDGE_W / RIDGE_STEP)
	pts.append(Vector2(0.0, 0.0))
	for i in range(n):
		var x0 := float(i) * RIDGE_STEP
		var r1 := float((i * 7919 + layer * 104729) % 997) / 997.0       # 大起伏
		var r2 := float((i * 104729 + layer * 7919) % 89) / 89.0         # 小锯齿
		var peak := 46.0 + 52.0 * r1 + 16.0 * r2 + float(layer) * 14.0
		pts.append(Vector2(x0 + RIDGE_STEP * 0.28, -peak * 0.55))
		pts.append(Vector2(x0 + RIDGE_STEP * 0.52, -peak))
		pts.append(Vector2(x0 + RIDGE_STEP * 0.78, -peak * 0.42))
	pts.append(Vector2(RIDGE_W, 0.0))
	return pts


func _draw_ridges() -> void:
	if selftest or not is_instance_valid(camera):
		return
	if _ridge_polys.is_empty():
		_ridge_polys = [_ridge_poly(0), _ridge_poly(1)]
	var z9 := camera.zoom
	z9 = Vector2(maxf(z9.x, 0.01), maxf(z9.y, 0.01))
	var half: Vector2 = get_viewport_rect().size / z9 * 0.5
	var ctr: Vector2 = camera.global_position
	var top_y := ctr.y - half.y
	var base_y := top_y + RIDGE_BAND
	var span := half.x * 2.0
	## 顶部薄霾：把山脊上缘缝进地形，免得看成"贴在屏幕上的一条带"
	draw_rect(Rect2(Vector2(ctr.x - half.x, top_y), Vector2(span, 64.0)), Color(0.62, 0.69, 0.78, 0.10))
	for L in range(2):
		var par := float(RIDGE_PAR[L])
		## ⭐ 左端外扩量**跟着视口算**，不能写死常数（原来写的是 -300，复核时改掉）：
		##    记可见左边缘 u = ctr.x - half.x（相机被 limit 夹住时 u ≥ 0），要求 tx ≤ u 恒成立。
		##    取 tx = (1-par)*(ctr.x - half.x) - 48  →  tx - u = -par*u - 48 ≤ 0，**任意视口宽都成立**。
		##    ⚠️ 写死 -300 为什么不行：`window/stretch/aspect = "expand"`，视口宽会随窗口变，
		##       half.x 不是定值；窗口拉宽到 ~1460px 以上时远层（par=0.18）左端会缩进屏幕里露馅。
		##    右端由 RIDGE_W 兜住（余量 3000+，任何现实视口都够），所以只改左边这一项。
		var tx := (1.0 - par) * (ctr.x - half.x) - 48.0
		draw_set_transform(Vector2(tx, base_y), 0.0, Vector2.ONE)
		draw_colored_polygon(_ridge_polys[L], RIDGE_COL[L] as Color)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)      # ⚠️ 必复位
	## 下缘渐隐：三层递减 alpha，让山"化"进地里，而不是硬切一条边
	for k in range(3):
		draw_rect(Rect2(Vector2(ctr.x - half.x, base_y + float(k) * 30.0), Vector2(span, 30.0)),
				Color(0.56, 0.63, 0.72, 0.09 - 0.03 * float(k)))


func _draw_world() -> void:
	var ws: Vector2 = GameData.WORLD["size"]
	if GameData.world_ready():
		_draw_world_height()
	else:
		_draw_world_flat()
	draw_rect(Rect2(Vector2.ZERO, ws), Color(0.36, 0.38, 0.42), false, 6.0)

## ⭐ M30.13c：**带高度的世界** —— 「走在山上真的感觉在山上」就靠这三条：
##    ① 每格按海拔**向上偏移** ② 按海拔**从低到高**绘制（高的后画 → 盖住低的 = 遮挡）
##    ③ 南边比自己低就画一面**崖壁竖面**（顶亮底暗 + 墙脚阴影），不是色块边界
## ⭐ M31.2：按邻居掩码取 autotile 变体。
##    掩码 bit0=N bit1=E bit2=S bit3=W，**1 = 邻居地形不同**（要画边）。
##    世界边缘当作"同类"（不然地图边框会出现一圈假接缝）。
##    ⚠️ 变体贴图缺失就返回 null，调用方回退到纯色 —— 不让缺图把地形画崩。
var _auto_cache: Dictionary = {}


func _auto_tile(tn: String, cx: int, cy: int) -> Texture2D:
	var mask := 0
	if GameData.in_map(Vector2i(cx, cy - 1)) and GameData.cell_terrain(cx, cy - 1) != tn:
		mask |= 1
	if GameData.in_map(Vector2i(cx + 1, cy)) and GameData.cell_terrain(cx + 1, cy) != tn:
		mask |= 2
	if GameData.in_map(Vector2i(cx, cy + 1)) and GameData.cell_terrain(cx, cy + 1) != tn:
		mask |= 4
	if GameData.in_map(Vector2i(cx - 1, cy)) and GameData.cell_terrain(cx - 1, cy) != tn:
		mask |= 8
	var key := tn + "_" + str(mask)
	if not _auto_cache.has(key):
		var p := "res://art/tiles/auto_" + tn + "_" + str(mask) + ".png"
		_auto_cache[key] = (load(p) as Texture2D) if ResourceLoader.exists(p) else null
	return _auto_cache[key]


## ⭐ M31.2：**接缝渐变** —— 在边界内侧叠两层「邻居色」（alpha 0.16 / 0.09）。
##    ⭐ 为什么不做 47-blob 那种全套变体：素材量与接线量成倍；
##    这里用"邻居色渐变"几行就拿到 80% 的效果，且不需要额外美术。
func _blend_seams(r: Rect2, tn: String, cx: int, cy: int) -> void:
	var w := 7.0
	for d9 in [[0, -1], [1, 0], [0, 1], [-1, 0]]:
		var nx: int = cx + int(d9[0])
		var ny: int = cy + int(d9[1])
		if not GameData.in_map(Vector2i(nx, ny)):
			continue
		var nt := GameData.cell_terrain(nx, ny)
		if nt == tn:
			continue
		var nc: Color = GameData.WORLD_TERRAIN_COLORS.get(nt, Color(0.2, 0.2, 0.2))
		for layer in range(2):
			var ww := w * (1.0 - 0.45 * float(layer))
			var a := 0.16 - 0.07 * float(layer)
			var col := Color(nc.r, nc.g, nc.b, a)
			if int(d9[1]) < 0:
				draw_rect(Rect2(r.position, Vector2(r.size.x, ww)), col)
			elif int(d9[1]) > 0:
				draw_rect(Rect2(r.position + Vector2(0.0, r.size.y - ww), Vector2(r.size.x, ww)), col)
			elif int(d9[0]) < 0:
				draw_rect(Rect2(r.position, Vector2(ww, r.size.y)), col)
			else:
				draw_rect(Rect2(r.position + Vector2(r.size.x - ww, 0.0), Vector2(ww, r.size.y)), col)


func _draw_world_height() -> void:
	if not _world_order_ready:
		_world_order_ready = true
		for cy in range(GameData.WORLD_ROWS):
			for cx in range(GameData.WORLD_COLS):
				_world_order.append([GameData.cell_elev(cx, cy), cx, cy])
		_world_order.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var cell := GameData.WORLD_CELL
	## ⭐ M30.25：**只画可见格子** —— 世界变成 160×90 = 14400 格，全画是自杀。
	##    可见范围 = 相机中心 ± 视口/zoom 的一半，再外扩 2 格（防止边缘露白）。
	## ⭐ M31.3 复核修正：**下缘的 padding 必须把海拔抬升算进去**（原来是写死的 2 格 = 64）。
	##    裁剪判的是**未抬升**的格角 (cx*cell, cy*cell)，画的时候却往上挪了 e*ELEV_LIFT
	##    —— 高格子会被抬进可见区、却又被裁掉，屏幕**下缘缺格**。
	##    抬升是**向上**的，所以只有下缘要补；补一个通道上限（e = 世界图 g 通道 ∈ [0,1]）
	##    最稳：这样**任意 ELEV_LIFT** 都不缺格，且不依赖烘焙表里的具体海拔上限。
	var vis_r := Rect2(Vector2.ZERO, Vector2(2048.0, 2048.0))
	if is_instance_valid(camera):
		var z9 := camera.zoom
		z9 = Vector2(maxf(z9.x, 0.01), maxf(z9.y, 0.01))
		var half := get_viewport_rect().size / z9 * 0.5
		## ⚠️ 不能用 camera.get_screen_center_position()：在 _draw 里它可能还没更新，
		##    结果整屏都落在裁剪框外 → **画面全黑**（踩过一次）。用玩家位置最稳。
		var ctr9 := player.position if (player != null and is_instance_valid(player)) else camera.global_position
		var pad_up := cell * 2.0
		var pad_dn := cell * 2.0 + GameData.ELEV_LIFT      # ⭐ 下缘 += 最大抬升量
		vis_r = Rect2(ctr9 - half - Vector2(cell * 2.0, pad_up),
				half * 2.0 + Vector2(cell * 4.0, pad_up + pad_dn))
	for c in _world_order:
		if not vis_r.has_point(Vector2(float(c[1]) * cell, float(c[2]) * cell)):
			continue
		var cx: int = c[1]
		var cy: int = c[2]
		var e := GameData.cell_elev(cx, cy)
		var at := Vector2(float(cx) * cell, float(cy) * cell - e * GameData.ELEV_LIFT)
		var r := Rect2(at, Vector2(cell, cell))
		var tn := GameData.cell_terrain(cx, cy)
		var tex: Texture2D = null
		if tn == "水泽":
			# 水：按深浅上色（深 = 暗）。真正的 autotile 水岸是下一批
			var d := GameData.cell_depth(cx, cy)
			draw_rect(r, Color(0.12, 0.26, 0.40).lerp(Color(0.04, 0.11, 0.22), d))
		else:
			## ⭐ M31.2（P1）：**接缝处理** —— 两件事一起做才不"像色块"：
			##    ① 用 autotile 变体（`auto_<地形>_<掩码>.png`）：需要画边的那侧有暗边+内亮边
			##    ② 在边界内侧叠 2 层**邻居色**的低透明渐变 → 颜色是"过渡"过去的，不是硬切
			tex = _auto_tile(tn, cx, cy)
			if tex != null:
				draw_texture_rect(tex, r, false, _world_tint_of(tn))
			else:
				draw_rect(r, GameData.WORLD_TERRAIN_COLORS.get(tn, Color(0.16, 0.20, 0.16)))
			_blend_seams(r, tn, cx, cy)
		## ⭐ M31.3：**南向裙边**（F11）—— 把自己（低格）的顶面**向上延伸** Δ 顶到北邻底边。
		##    Δ = (e_北 − e_自己) × ELEV_LIFT，正好等于那条露出底色的缝高；
		##    ⚠️ 用**自己的**颜色/纹理（不是灰色墙面），且不加描边/阴影/渐变 ——
		##       M30.13e 否决的是"看着像障碍的墙"，裙边必须读作地形本身的延续。
		if skirt and GameData.in_map(Vector2i(cx, cy - 1)):
			var d9 := (GameData.cell_elev(cx, cy - 1) - e) * GameData.ELEV_LIFT
			## ⚠️ 限高：只补 ≤ 一级台阶的缝。超过的**故意不画** —— 那是数据层的异常落差，
			##    在这儿补出来就是一面能穿过去的墙（见 `SKIRT_MAX` 的注释）。
			if d9 > 0.01 and d9 <= SKIRT_MAX:
				var sr := Rect2(Vector2(at.x, at.y - d9), Vector2(cell, d9))
				if tn == "水泽":
					draw_rect(sr, Color(0.12, 0.26, 0.40).lerp(
							Color(0.04, 0.11, 0.22), GameData.cell_depth(cx, cy)))
				elif tex != null:
					var ts := tex.get_size()
					# 只取贴图的**顶部**对应的那一段（缝比一格高时取整张拉伸），避免压扁感
					draw_texture_rect_region(tex, sr,
							Rect2(Vector2.ZERO, Vector2(ts.x, ts.y * minf(1.0, d9 / cell))),
							_world_tint_of(tn))
				else:
					draw_rect(sr, GameData.WORLD_TERRAIN_COLORS.get(tn, Color(0.16, 0.20, 0.16)))
		# ⭐ M30.13e（用户定案）：**不再画崖壁竖面** —— 那些灰墙看着像地图上乱摆的障碍。
		#    高度还在（每格按海拔偏移 + 低的先画高的后画 = 遮挡），只是不画"墙"了。

## ⚠️ 保险：世界数据缺失（图没导入 / 路径写错）就退回平铺渲染 —— 不让一张图把世界画崩
func _draw_world_flat() -> void:
	var ws: Vector2 = GameData.WORLD["size"]
	## ⭐ M31.1：兜底渲染也走**格子地形**（和正常渲染同一套名字），不再用环状遗留。
	var cell := GameData.WORLD_CELL
	for gy in range(GameData.WORLD_ROWS):
		for gx in range(GameData.WORLD_COLS):
			var at := Vector2(float(gx) * cell, float(gy) * cell)
			var key := GameData.cell_terrain(gx, gy)
			draw_rect(Rect2(at, Vector2(cell, cell)), GameData.WORLD_TERRAIN_COLORS.get(key, Color(0.2, 0.22, 0.2)))

	# ⚠️ M19：锚点金环已移除（锚点机制关掉了）—— 世界里不再有"家"这个标记。
	#    复活点由时间线帧决定，玩家不需要知道它在哪。


func _spawn_dummy(pos: Vector2) -> Dummy:
	var d := Dummy.new()
	d.name = "Dummy%d" % (dummies.size() + 1)
	d.position = pos
	d.hp_max = float(GameData.DUMMY["hp_max"])
	d.hp = d.hp_max
	d.font = font
	d.game = self                    # ⭐ 接线：假人也走和 Enemy 同一套打击感
	add_child(d)
	dummies.append(d)
	return d


func _spawn_enemy(archetype: String, pos: Vector2, carries: String = "", elite := false) -> void:
	var e = EnemyScript.new()
	e.name = "Enemy_%s_%d" % [archetype, enemies.size() + 1]
	e.setup(archetype, player, self, elite)
	e.carries = carries            # ⭐ 灵师身上那枚印。打死它才有强夺的机会
	# ⭐ 死亡即从名单移除，只有这一个出口 ——
	#    否则被灼烧（不经过 spawn_hit）烧死的敌人会永远留在名单里，成为一具不死的尸体。
	e.died.connect(_on_enemy_died)
	e.position = pos
	add_child(e)
	enemies.append(e)


func _remove_enemy(e) -> void:
	enemies.erase(e)
	e.queue_free()


func _on_enemy_died(e) -> void:
	_drop_loot(e.position, str(e.archetype), e.elite)

	if str(e.carries) != "":
		_spawn_pickup(e.position, str(e.carries), 1)   # ⭐ 灵师的遗物：一枚印，走过去强夺
	if e.elite and hud != null:
		# ⚠️ M19：原来这里会「自动钉锚」，锚点机制移除后不再移动任何东西 ——
		#    进度由定期自动存档负责（ANCHOR.autosave_sec）。
		hud.notice("击败强敌 —— 掉了一枚印")
	_remove_enemy(e)


func _spawn_merchant() -> void:
	merchant = MerchantScript.new()
	merchant.name = "Merchant"
	## ⭐ M31 Step 0：坐标已是真坐标，不再乘世界缩放系数
	merchant.position = GameData.MERCHANT["pos"] as Vector2
	# ⚠️ 让商人**拿着同一个 Dictionary 引用** —— 之后所有读写都落在 merchant_stock 上，
	#    快照恢复时才不用管「换没换过对象」。
	merchant.stock = merchant_stock
	add_child(merchant)


func _spawn_gather(pos: Vector2, item: String, amount: int) -> void:
	var g = GatherScript.new()
	g.name = "Gather%d" % (gathers.size() + 1)
	g.position = pos
	g.item = item
	g.amount = amount
	add_child(g)
	gathers.append(g)


## 掉一件东西在地上。
## ⭐ M30.1：先试**就近合并**（同类 + 在 merge_radius 内）—— 合得进去就把数量加到那一堆上，
##    不新建节点。返回真正承载这件东西的那个节点（调用方一般不管，自测会读它）。
func _spawn_pickup(pos: Vector2, item: String, amount: int):
	var merged = _mergeable_pickup(pos, item)
	if merged != null:
		merged.amount += amount
		merged.queue_redraw()             # 数量字要跟着变
		return merged
	var p = PickupScript.new()
	p.name = "Pickup%d" % (pickups.size() + 1)
	p.position = pos
	p.item = item
	p.amount = amount
	add_child(p)
	pickups.append(p)
	return p


## 找一堆可以并进去的同类掉落物（M30.1）。没有就返回 null。
## ⚠️ 灵印不参与合并 —— 它是唯一的，而且地上要一眼看得出「那是一枚印」。
func _mergeable_pickup(pos: Vector2, item: String):
	if GameData.SEALS.has(item):
		return null
	var r := float(GameData.PICKUP["merge_radius"])
	var best = null
	var best_d := r
	for p in pickups:
		if not is_instance_valid(p) or str(p.item) != item:
			continue
		var d: float = pos.distance_to(p.position)
		if d <= best_d:
			best_d = d
			best = p
	return best


## 敌人死了掉什么。⭐ 固定数量（表里写死的），不做随机掉率 ——
## 随机掉率会让自测变成概率游戏。
func _drop_loot(pos: Vector2, archetype: String, elite := false) -> void:
	var table: Dictionary = GameData.ENEMY_DROPS.get(archetype, {})
	var mult := int(GameData.ELITE["drop_mult"]) if elite else 1
	var total := maxf(float(table.size() + (1 if elite else 0)), 1.0)
	var i := 0
	for item in table:
		# 围着尸体摊开一圈，免得几件东西叠在同一个点上分不清
		var off := Vector2(18.0, 0.0).rotated(TAU * float(i) / total)
		_spawn_pickup(pos + off, str(item), int(table[item]) * mult)
		i += 1
	# ⭐ 精英额外掉一份高级辅材 —— 「打硬的仗有额外回报」
	if elite:
		var off2 := Vector2(18.0, 0.0).rotated(TAU * float(table.size()) / total)
		_spawn_pickup(pos + off2, str(GameData.ELITE["bonus_drop"]), 1)


## 飘字与震屏每帧收尾。
func _tick_juice(delta: float) -> void:
	if not numbers.is_empty():
		var keep_n: Array = []
		for n in numbers:
			n["t"] = float(n["t"]) + delta
			if float(n["t"]) < float(n["life"]):
				keep_n.append(n)
		numbers = keep_n
		queue_redraw()

	# ⭐ M30.7：掌风弧光也按寿命收掉（和飘字同一套规矩）
	if not swings.is_empty():
		var keep_s: Array = []
		for s in swings:
			s["t"] = float(s["t"]) + delta
			if float(s["t"]) < float(s["life"]):
				keep_s.append(s)
		swings = keep_s
		queue_redraw()

	# 命中停顿：用真实时间判定结束（不受 time_scale 影响），到点就放回去
	if _hitstop_until_ms > 0 and Time.get_ticks_msec() >= _hitstop_until_ms:
		_end_hitstop()

	# 震屏：衰减到 0 就**精确归零** —— 否则画面会一直偏着
	if shake > 0.0:
		shake = maxf(0.0, shake - delta * float(GameData.JUICE["shake_decay"]))
		if camera != null:
			if shake > 0.0:
				camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake
			else:
				camera.offset = Vector2.ZERO


## 掉落物自动拾取 + 提示计时。
## ⭐ 背包满时**不捡走** —— 东西留在地上，绝不凭空消失。
func _tick_pickups(delta: float) -> void:
	if pickup_toast_t > 0.0:
		pickup_toast_t = maxf(0.0, pickup_toast_t - delta)
		if pickup_toast_t <= 0.0:
			pickup_toast = ""

	bag_full_hint = false
	seize_dup_hint = false
	if player == null or not is_instance_valid(player):
		return
	var r := float(GameData.PICKUP["radius"])
	for p in pickups.duplicate():
		if not is_instance_valid(p):
			continue
		if player.position.distance_to(p.position) > r:
			continue

		# ⭐ 灵印走**强夺**这条路（M20：抢来的印炼化满后一样有被动）。
		# ⚠️ M29.5：**收藏无上限** —— 命窍满了就进背包，绝不把印丢在地上。
		if p.is_seal():
			if player.seize(str(p.item)):
				if player.bag_seals.has(str(p.item)):
					pickup_toast = "获得 %s（命窍满了，先放背包）" % p.item
				else:
					pickup_toast = "强夺 %s（要炼化满才能用）" % p.item
				pickup_toast_t = 2.6
				pickups.erase(p)
				p.queue_free()
			else:
				seize_dup_hint = true        # 唯一会失败的情况：这枚印你已经有一枚了
			continue
		var added: int = player.bag.add(p.item, p.amount)
		if added >= p.amount:
			pickup_toast = "获得 %s ×%d" % [p.item, p.amount]
			pickup_toast_t = 1.6
			pickups.erase(p)
			p.queue_free()
		else:
			bag_full_hint = true          # 捡不动，东西留在原地


## 离某点最近的、还没被采空的采集点（在采集距离内）。
## Game.try_gather() 和 HUD 的「E 采集」提示都用它 —— 只有一个判定入口。
func nearest_gather(pos: Vector2):
	var best = null
	var best_d := INF
	for g in gathers:
		if not is_instance_valid(g) or g.depleted:
			continue
		var d: float = pos.distance_to(g.position)
		if d <= g.reach() and d < best_d:
			best_d = d
			best = g
	return best


## 按 E 采集。返回回了多少灵力（0 = 附近没有可采的点）。
func try_gather() -> float:
	var g = nearest_gather(player.position)
	if g == null:
		return 0.0
	# ⭐ 背包满了就不采：采到的材料绝不凭空消失，采集点也不被白白消耗
	# ⭐ M30.4：按**容积**判 —— 只剩 1 格容积时，「3 格的矿石」采不动（那不等于背包满）
	if not player.bag.fits(g.item):
		bag_full_hint = true
		return 0.0
	if not g.gather():
		return 0.0
	var got: float = float(GameData.GATHER["essence"])
	player.essence = minf(player.essence_max, player.essence + got)
	player.bag.add(g.item, g.amount)
	return got


# ---------------- 打击感 ----------------

## 冒一个伤害数字。
func add_number(pos: Vector2, amount: float, color: Color) -> void:
	if not bool(GameData.JUICE["numbers"]):
		return
	numbers.append({"pos": pos, "text": str(int(roundf(amount))), "color": color,
			"t": 0.0, "life": float(GameData.JUICE["number_life"])})


## 震一下。取最大值 —— 同时挨好几下也不会震成筛子。
func add_shake(amount: float) -> void:
	shake = maxf(shake, amount)


## 命中停顿：把时间压慢几十毫秒。
## ⚠️ 不用 `create_timer` 来恢复 —— 主循环一旦卡住（窗口切到后台、调试器断点），
##    计时器就不会走，`time_scale` 会**永远停在 0.05**，整个游戏变成慢动作。
##    改成记一个**真实时间**的截止点，由 _tick_juice 每帧检查（真实时间不受 time_scale 影响）。
func hitstop(duration := 0.05) -> void:
	if selftest or not bool(GameData.JUICE["hitstop_on"]):
		return
	Engine.time_scale = float(GameData.JUICE["hitstop_scale"])
	_hitstop_until_ms = maxi(_hitstop_until_ms, Time.get_ticks_msec() + int(duration * 1000.0))


## 到点了就把时间倍率放回去。
func _end_hitstop() -> void:
	_hitstop_until_ms = 0
	Engine.time_scale = 1.0


## 锚点前移 + 存档。⭐ 设锚 = 把「到这一刻为止的成长」钉住 = 存一次档。
## 触发点：击败**精英**后自动钉锚（设计圣经 §4.3「击败强敌后」）。
## ⭐ M19：**锚点机制没了** —— "钉住进度"不再由某个地点触发，而是**定期自动存**。
## 存档 = 拍快照 + 拍一帧（时间线多一个安全点）+ 写盘。
func save_now() -> bool:
	take_snapshot()
	return save_game()


func save_game() -> bool:
	if selftest:
		return false
	return SaveGameScript.save_to(str(GameData.ANCHOR["save_path"]), self)


func load_game() -> bool:
	if selftest:
		return false
	if not SaveGameScript.load_from(str(GameData.ANCHOR["save_path"]), self):
		return false
	# ⭐ M25（用户要求「开局自动补满灵力」）：读档 = 开局 → 按**读回来的境界**重算上限再补满。
	#    ⚠️ 只补满不够：from_dict 改了 realm，如果这里不 refresh_limits()，
	#    上限会停在旧境界的值（读化神档却只有炼气的 100 上限）。
	if player != null and is_instance_valid(player):
		player.refill()
	take_snapshot()          # 读档之后立刻重拍一次，否则下一次死亡会退回开局状态
	return true


## E 的唯一入口：按**站的地方**决定这一下是「突破」还是「采集」。
## ⭐ 一个键只有一个含义（交互），交互的对象由上下文决定。
func try_interact() -> void:
	if player == null or not is_instance_valid(player):
		return
	# ⚠️ M19：原来站在锚点旁按 E = 突破；锚点没了之后突破只在 Tab 命窍面板里做。
	if try_trade():
		return
	try_gather()


## 修炼：把灵力炼成修为。⭐ 灵力唯一的「变强」出口 ——
## 打架花掉的灵力和修炼花掉的灵力是同一笔，这才是取舍。
func try_cultivate() -> float:
	var gained: float = player.cultivate()
	if gained > 0.0:
		add_number(player.position + Vector2(0.0, -34.0), gained, Color(0.72, 0.88, 0.98))
	queue_redraw()
	return gained


## 站在商人旁边 → 开交易面板。
func try_trade() -> bool:
	if merchant == null or not is_instance_valid(merchant):
		return false
	if player.position.distance_to(merchant.position) > merchant.reach():
		return false
	trade_panel.open(self)
	get_tree().paused = true
	return true


## 修为攒满 → 突破。⭐ **不再要求回锚点**（用户改的规则：任意地方都能突破）。
## ⚠️ 突破是**局内收获**：这里**不拍快照、不写盘** ——
##    死亡回溯会连**境界和修为一起**退回「最后一次钉锚」时的状态（用户要的就是这个）。
##    想把它存下来，目前只能靠**击败精英**自动钉锚（主动设锚还没做，见待决问题 14）。
func try_breakthrough() -> bool:
	if not player.can_breakthrough():
		return false
	if not player.breakthrough():
		return false
	# ⚠️ 刻意不拍快照、不写盘：突破只是局内收获，死亡会把它连同修为一起退回。
	if hud != null:
		hud.notice("突破 —— 境界 → %s（未钉锚：死亡会退回）" % player.realm_name())
	return true


# ---------------- 自动存档（M19 / M27）----------------
## ⚠️ M28（用户定案）：**回溯功能暂时移除** —— 时间线 / 盲跳 / 深度评分 / 连死保底 / 退帧
##    全部删掉，等后面重新设计。死亡现在是最朴素的「回到上次存档」（见 _on_player_died）。
##    要接回来时：timeline + capture_frame + rollback_* + RewindPanel 一起加回来即可 ——
##    快照（take_snapshot / restore_snapshot）与 spawn_point 都还在，底子没动。
var _autosave_timer := 0.0       # 定期自动存档的计时（间隔见 GameData.ANCHOR.autosave_sec）

## 境界比**快照**（= 上次存档）高吗？⭐ 突破是局内收获，不写盘 —— 死了会跟着退回去。
## HUD 用它显示「未存档」：不然玩家突破完一死就退回，又会以为是 bug。
func unbanked_realm() -> bool:
	return int(snapshot.get("realm", 0)) != player.realm


## 给锚点拍快照。开局拍一次就是「初始锚点」；将来多锚点时可以在别处再拍。
## ⭐ 「钉住这一刻」是一件事，别拆成两件：
##    拍快照（= 死亡回溯的兜底）+ 拍一帧（= 时间线的关键帧）+ 把锚帧下标前移到这里。
##    （曾经快照和帧是分开的，结果自测钉了快照却没钉帧 —— 回溯直接退到别处去了。）
func take_snapshot() -> void:
	# ⭐ 用户决定「连境界一起倒流」（严格照 §4.3）：所以修为也在快照里。
	snapshot = _snapshot_dict()

## ⭐ M31 Step 0：列出**落在世界矩形之外的内容点**。正常应返回空数组。
##    ⚠️ 为什么要有它：改世界尺寸 / 重排内容点时，坐标烤出界是**静默**的 ——
##    不报错、不崩溃，只是玩家永远走不到那儿。带印的精英一旦出界，那枚印就成了死档。
##    ⚠️ Step 1 加 `sites` 表后，把 sites 也扫进来（现在只有 ENEMY_SPAWNS 与 GATHER.spots）。
func content_out_of_world() -> Array:
	var ws3: Vector2 = GameData.WORLD["size"]
	var out: Array = []
	for spec: Dictionary in GameData.ENEMY_SPAWNS:
		var p: Vector2 = spec["pos"] as Vector2
		if p.x < 0.0 or p.y < 0.0 or p.x > ws3.x or p.y > ws3.y:
			out.append("%s@%s" % [str(spec.get("id", "?")), str(p)])
	for spot: Dictionary in GameData.GATHER["spots"]:
		var gp: Vector2 = spot["pos"] as Vector2
		if gp.x < 0.0 or gp.y < 0.0 or gp.x > ws3.x or gp.y > ws3.y:
			out.append("%s@%s" % [str(spot.get("id", "?")), str(gp)])
	return out


## 快照的字典本体。⭐ 抽出来是因为**时间线的每一帧**也要存一份同样的东西。
func _snapshot_dict() -> Dictionary:
	var es: Array = []
	for e in enemies:
		if is_instance_valid(e) and e.is_alive():
			es.append({"archetype": e.archetype, "pos": e.position, "hp": e.hp,
					"carries": e.carries, "elite": e.elite})
	var gs: Array = []
	for g in gathers:
		gs.append(is_instance_valid(g) and g.depleted)
	return {
		"enemies": es,
		"gathers": gs,
		"realm": player.realm,
		"bag": player.bag.items.duplicate(),
		"stones": player.bag.stones,
		"refine": player.seal_refine.duplicate(),
		"ranks": player.seal_rank.duplicate(),
		"cultivation": player.cultivation,
		"stock": merchant_stock.duplicate(),
	}


## 恢复锚点快照。⭐ 敌人是**重建**的：快照时已经死掉的不在名单里，所以它们保持死亡；
##    快照之后被打死的会在这里复活。采集点同理。
func restore_snapshot() -> void:
	restore_snapshot_from(snapshot)


## ⭐ 真正的恢复实现。盲跳回溯要能恢复到**时间线上的任意一帧**，所以票据是参数，
##    而不是固定读 `snapshot`（`restore_snapshot()` 保留原语义 = 用锚点快照）。
func restore_snapshot_from(snap: Dictionary) -> void:
	for e in enemies.duplicate():
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()

	# ⭐ 地上散落的东西也属于「这一世」—— 时间倒流，它们跟着消失（§4.3）
	for p in pickups.duplicate():
		if is_instance_valid(p):
			p.queue_free()
	pickups.clear()
	# ⚠️⚠️ 下面三处**必须读参数 `snap`，不能读全局 `snapshot`** —— 踩过：写成了全局，
	#    只有一个快照（锚点帧）时看不出来；将来加了第二个槽位（域边界存档），
	#    跨域回退会静默退到**错误的那一帧**。自测「按票据恢复，而不是按全局快照」守着这一条。
	for rec: Dictionary in snap.get("enemies", []):
		_spawn_enemy(str(rec["archetype"]), rec["pos"], str(rec.get("carries", "")), bool(rec.get("elite", false)))
	for i in range(enemies.size()):
		enemies[i].hp = float(snap["enemies"][i]["hp"])

	var gs: Array = snap.get("gathers", [])
	for i in range(gathers.size()):
		if not is_instance_valid(gathers[i]):
			continue
		if i < gs.size() and bool(gs[i]):
			gathers[i].depleted = true
		else:
			gathers[i].restore()

	# ⭐ 修为一起倒流：境界 / 灵力 / 材料 / 灵石 / 炼化 全部退回锚点值
	if player != null and is_instance_valid(player):
		player.realm = int(snap.get("realm", 1))
		player.bag.items = (snap.get("bag", {}) as Dictionary).duplicate()
		player.bag.stones = int(snap.get("stones", 0))
		player.seal_refine = (snap.get("refine", {}) as Dictionary).duplicate()
		player.seal_rank = (snap.get("ranks", {}) as Dictionary).duplicate()
		player.cultivation = float(snap.get("cultivation", 0.0))
	# ⚠️ 货架要**原地改**：Merchant 拿着这个 Dictionary 的引用，换对象它就指向旧的了
	merchant_stock.clear()
	for k in snap.get("stock", {}):
		merchant_stock[str(k)] = int(snap["stock"][k])
	# ⚠️ 下面两句**必须在循环外面** —— 之前缩进掉进循环里了，货架空的时候就不会执行
	if player != null and is_instance_valid(player):
		player.refresh_limits()
		player.essence = player.essence_max


## 离某点最近的敌人（射程内）。灵印的招式靠它选目标 —— 确定性，不需要随机数。
func nearest_enemy_to(pos: Vector2, range_px: float) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for e in enemies:
		if not is_instance_valid(e) or not e.is_alive():
			continue
		var d: float = pos.distance_to(e.position)
		if d <= range_px and d < best_d:
			best_d = d
			best = e
	return best


## 某枚灵印留下的灼烧，全部清掉。收回 / 死亡 / 槽位受损三条路径都走这里。
func clear_dots_from(seal) -> void:
	for e in enemies:
		if is_instance_valid(e):
			e.clear_dots_from(seal)


## 场上现在显化中的灵印。敌人（智谋型）通过这个问「我能不能改打灵印」。
func summoned_seals() -> Array:
	if player == null:
		return []
	return player.summoned_seals()


## ⚠️ M28：回溯已移除。这个函数只是**兼容旧测试里的调用** ——
##    现在死亡会**同步立即**完成复活（见 _on_player_died），所以这里是个空操作。
##    等旧测试都改成直接调 take_damage 之后，这个壳就删掉。
func _on_rewind_chosen(_index: int) -> void:
	pass


## 主角死亡（M28：回溯已移除 —— 现在是最朴素的「回到上次存档」）。
## ⚠️ 用户定案：**先不需要回溯**，等后面再设计。所以这里**不做任何"退到哪一帧"的选择**，
##    只把世界退回**快照**（= 上次存档那一刻的敌人 / 采集点 / 背包 / 修为），主角回出生点、补满。
##    ⚠️ 代价由此变得很直白：**上次存档之后的一切都会失去**（现在是 10 分钟一存）。
##    要接回盲跳回溯时：timeline + capture_frame + rollback_* + RewindPanel 一起加回来即可。
func _on_player_died(_p: Player) -> void:
	deaths += 1
	restore_snapshot()                   # 世界退回快照（= 上次存档）
	player.respawn(spawn_point)
	player.refill()
	# ⚠️ 必须写盘：否则「死完退出重进」就能绕过代价
	save_game()


# ==================== 印诀（M22→M26，代码里仍叫 combo）====================
## 六个印诀各自的**世界效果**。⭐ 都建立在已有机制上（范围伤害 / DOT / 治疗 / 增益）——
## 没有另造"持续领域"系统：那要写 tick、要处理死亡、要进快照，收益不值。
## 触发方式见 Player 里的「结印」状态机（按 R 起手 → 数字键填序列 → 凑齐结算）。


## 放一个印诀的世界效果。返回命中数（自测就靠它判断对错）。
func execute_combo(key: String) -> int:
	if not GameData.COMBOS.has(key):
		return 0
	var d: Dictionary = GameData.COMBOS[key]
	var hits := 0
	match str(d["kind"]):
		"storm":
			hits = _combo_aoe(player.position, float(d["radius"]), float(d["damage"]), key,
					float(d.get("dot", 0.0)), float(d.get("dot_time", 0.0)))
			player.heal(float(d.get("heal", 0.0)))
		"burst":
			hits = _combo_aoe(player.position, float(d["radius"]), float(d["damage"]), key, 0.0, 0.0)
		"pillar":
			hits = _combo_aoe(player.position, float(d["radius"]), float(d["damage"]), key,
					float(d.get("dot", 0.0)), float(d.get("dot_time", 0.0)))
		"firewall":
			var dir: Vector2 = player.facing.normalized()
			if dir == Vector2.ZERO:
				dir = Vector2.RIGHT
			hits = _combo_line(player.position, player.position + dir * float(d["length"]),
					float(d["width"]), float(d["damage"]), key, float(d.get("dot", 0.0)),
					float(d.get("dot_time", 0.0)), float(d.get("push", 0.0)), dir)
		"guard", "haste":
			hits = 0            # 只给自己上增益 —— 那部分 Player 已经上了
	if hud != null:
		hud.notice("印诀 · %s" % str(d["name"]))
	return hits


## 圆形范围伤害（雷雨交加 / 爆炎 / 引雷柱）。
## ⚠️ 遍历 duplicate()：take_damage 可能打死敌人，_on_enemy_died 会改 enemies。
func _combo_aoe(center: Vector2, radius: float, damage: float, src: String,
		dot_dmg: float, dot_time: float) -> int:
	var n := 0
	for e in enemies.duplicate():
		if not is_instance_valid(e) or not e.is_alive():
			continue
		if e.position.distance_to(center) > radius:
			continue
		e.take_damage(damage)
		n += 1
		if dot_dmg > 0.0 and is_instance_valid(e) and e.is_alive():
			e.add_dot(dot_dmg, dot_time, src, 0.5, Color(0.78, 0.70, 1.0))
	return n


## 线段范围伤害（燎原 · 火墙）：判定 = 点到线段的距离。
func _combo_line(from: Vector2, to: Vector2, width: float, damage: float, src: String,
		dot_dmg: float, dot_time: float, push: float, dir: Vector2) -> int:
	var n := 0
	for e in enemies.duplicate():
		if not is_instance_valid(e) or not e.is_alive():
			continue
		if _dist_to_segment(e.position, from, to) > width:
			continue
		e.take_damage(damage)
		n += 1
		if push > 0.0 and is_instance_valid(e):
			e.position += dir * push
		if dot_dmg > 0.0 and is_instance_valid(e) and e.is_alive():
			e.add_dot(dot_dmg, dot_time, src, 0.5, Color(0.98, 0.66, 0.34))
	return n


## 点到线段的距离。
func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 <= 0.0001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# ==================== 伤害判定 ====================

## ⭐ M30.7：掌风弧光。Player 在**前摇开始**时喊这一次 —— 它不参与判定，
##    纯粹是「我要打了」的可读信号（0.15 秒后才真的掉血，见 Player._strike）。
##    ⚠️ 将来 M31 做特效层时，这条和 hits 一起搬进 Fx.gd —— 现在先留在主控里。
func spawn_swing(center: Vector2, dir: Vector2) -> void:
	swings.append({"center": center, "dir": dir, "t": 0.0,
			"life": float(GameData.ATTACK["arc"]["life"])})
	queue_redraw()


## 生成一个短命伤害区，并立刻结算命中。
## 返回命中了几个目标 —— 自测就是靠这个返回值判断对错的。
func spawn_hit(center: Vector2, dir: Vector2, length: float, width: float, dmg: float) -> int:
	var n := 0
	# 用 duplicate()：下面可能删假人，不能一边遍历一边改原数组
	for d in dummies.duplicate():
		if not is_instance_valid(d):
			continue
		if _in_attack_area(d.position, center, dir, length, width):
			d.take_damage(dmg)
			n += 1
			if d.hp <= 0.0:
				_remove_dummy(d)

	# 敌人也吃这一刀。⭐ 和假人共用同一个 _in_attack_area —— 判定规则只有一处
	for e in enemies.duplicate():
		if not is_instance_valid(e) or not e.is_alive():
			continue
		if _in_attack_area(e.position, center, dir, length, width):
			e.take_damage(dmg)      # 打死的话它自己会 emit died，由 _on_enemy_died 移除
			n += 1
			# ⭐ M30.7：轻微击退（没死才推 —— 死了马上就消失了，推它没意义）
			if is_instance_valid(e) and e.is_alive():
				e.position += dir.normalized() * float(GameData.ATTACK["knockback"])

	hits.append({
		"center": center, "dir": dir, "length": length, "width": width,
		"t": 0.0, "life": float(GameData.ATTACK["life"]),
	})
	queue_redraw()
	return n


## 判断一个点是否落在「以 center 为中心、朝向 dir、长 length 宽 width」的矩形里。
##
## 做法：把点换算到**攻击者自己的坐标系**——沿朝向走多远 + 偏离朝向多少。
## 这样就不用真的去旋转矩形了。
## ⭐ 这套算法将来加「扇形」时，只要再比一个角度就行，不用推倒重来。
func _in_attack_area(p: Vector2, center: Vector2, dir: Vector2, length: float, width: float) -> bool:
	var rel := p - center
	var along := rel.dot(dir)                        # 正值 = 在攻击区前方
	var side := rel.dot(Vector2(-dir.y, dir.x))      # 垂直于朝向的分量
	return absf(along) <= length * 0.5 and absf(side) <= width * 0.5


func _remove_dummy(d: Dummy) -> void:
	dummies.erase(d)          # 先从名单里划掉（自测会查这个）
	d.queue_free()            # 再真正销毁节点


# ==================== 每帧 ====================

## Tab = 开关命窍面板。⭐ 打开时暂停（在菜单里被打死是说不过去的）。
func _input(event: InputEvent) -> void:
	# ⭐ 已经被面板吃掉的键不要再处理 —— 面板关自己时会解除暂停，
	#    若不看这个标记，这里会把同一个 Tab 又当成「打开」处理一遍。
	if get_viewport().is_input_handled():
		return
	if player == null or not is_instance_valid(player):
		return
	if player._dead:
		return                       # 刚死、正在复活，这一帧不给开面板
	if event.is_action_pressed("open_panel"):
		toggle_seal_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_forge"):
		toggle_forge_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_bag"):
		toggle_bag_panel()
		get_viewport().set_input_as_handled()
	# ⭐ M31.3：F9 = 前景遮挡开关（默认关，见 `fg_occlusion`）。没走 InputMap，
	#    就是为了不动 project.godot —— 这是个临时评估开关，不是正式操作。
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F9:
		_set_fg_occlusion(not fg_occlusion)
		print("[前景遮挡] %s（F9 切换）" % ("开" if fg_occlusion else "关"))
		get_viewport().set_input_as_handled()
	# ⭐ M31.3：F11 = 南向裙边开关（默认关，见 `skirt`）。同上，不动 project.godot。
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F11:
		skirt = not skirt
		print("[南向裙边] %s（F11 切换）" % ("开" if skirt else "关"))
		get_viewport().set_input_as_handled()


## ⭐ M31.3：前景遮挡开关。节点**懒建 + 复用**：关着的时候场景树保持原样，
##    ⚠️ `z_index = 64` 是关键 —— 玩家/敌人是 `Game` 的子节点（z=0），
##    遮挡层必须比它们高才画在人**之后**（详见 `ForegroundLayer.gd` 的注释）。
func _set_fg_occlusion(on: bool) -> void:
	fg_occlusion = on
	if on and fg_layer == null:
		fg_layer = ForegroundLayerScript.new()
		fg_layer.name = "FgLayer"
		fg_layer.z_index = 64
		fg_layer.game = self
		add_child(fg_layer)
	if fg_layer != null:
		fg_layer.visible = on
		fg_layer.queue_redraw()


func toggle_forge_panel() -> void:
	if forge_panel == null:
		return
	if forge_panel.visible:
		forge_panel.close()
		return
	if seal_panel != null and seal_panel.visible:
		return                       # 命窍面板开着就别叠炉子
	forge_panel.open(self)
	get_tree().paused = true


func toggle_seal_panel() -> void:
	if seal_panel.visible:
		seal_panel.close()
		return
	seal_panel.open(player, self)      # 把主控也给它 —— 修炼要飘字
	get_tree().paused = true


## B = 开关背包面板（M30.2）。和别的面板一样：打开就暂停时间。
func toggle_bag_panel() -> void:
	if bag_panel == null:
		return
	if bag_panel.visible:
		bag_panel.close()
		return
	bag_panel.open(player, self)
	get_tree().paused = true


func _on_seal_panel_closed() -> void:
	get_tree().paused = false


func _process(delta: float) -> void:
	# ⭐ M31.3：自测收尾的**兜底调用** —— 必须放在 `_process` 的第一行。
	#    主体在 `_ready` 里跑；一旦它抛异常，`_ready` 整个中断、收尾就永远不到，
	#    而这里下一帧照样会执行 → 收尾（打印汇总 + 非 0 退出）一定发生，假绿灯不可能再出现。
	#    ⚠️ 自测自己会**手动**喂 `_process`（见 `_st_manual_tick`）—— 那次不能触发收尾，
	#    否则主体才跑一半就被提前收尾（踩过：117 项就打印了汇总）。
	if _st_started and not _st_finished and not _st_manual_tick:
		_selftest_finish()
		return
	# 相机跟住主角（M7）。⭐ 必须放在最前面 —— 下面有个 hits 为空就短路 return
	if camera != null and player != null and is_instance_valid(player):
		camera.global_position = player.position
	# ⭐ M31.3：前景遮挡层有风摆动画，得每帧重画（只在开着的时候）。
	if fg_occlusion and fg_layer != null:
		fg_layer.queue_redraw()

	# 掉落物自动拾取 + 提示计时（M8）。⭐ 同样要在下面那个短路之前
	_tick_pickups(delta)

	# ⭐ M19/M27：定期自动存档（每 autosave_sec 一次 —— 现在是 10 分钟）
	#    ⚠️ 间隔一拉长，"退出时存一次"就变成了主力：窗口直接关掉会走 _notification 存盘。
	#    另外死亡回溯也会写盘，所以死亡这条路永远是安全的。
	_autosave_timer += delta
	if _autosave_timer >= float(GameData.ANCHOR["autosave_sec"]):
		_autosave_timer = 0.0
		save_now()

	# 打击感：飘字上浮 + 震屏衰减。⭐ 同样必须在下面那个短路之前
	_tick_juice(delta)
	_tick_activation()      # ⭐ M30.26：远处的实体休眠（大世界真正该先做的那件事）

	# 短命伤害区：寿命到了就丢掉，不然会一直堆在内存里
	if not hits.is_empty():
		var keep: Array = []
		for h in hits:
			h["t"] = float(h["t"]) + delta
			if float(h["t"]) < float(h["life"]):
				keep.append(h)
		hits = keep
	# ⭐ M31.3（重烘焙收尾时抓帧抓出来的真 bug）：queue_redraw 必须**每帧**调。
	#    原来它被塞在 `if hits.is_empty(): return` 的后面 —— 不打架就整帧不重画，
	#    `_draw()` 的绘制命令被引擎缓存复用，而 `_draw_world_height()` 里的 vis_r
	#    裁剪又是按「_draw 那一刻的玩家位置」算的 ⇒ 玩家走远后，屏幕上只有
	#    「上次打架时那一圈」的格子，其余全是黑（clear color 15,18,20）。
	#    之前观察到的"黑带/黑缝"全是它，不是几何、不是 padding、更不是 LIFT 太大。
	#    _draw 本身很便宜（vis_r 已裁剪，实测算下来一屏 575 格），放最后一行没负担。
	queue_redraw()


## 关窗口 / 编辑器停止运行：先存一次（不然"玩了一小时没到自动存档点就退出"会白玩）。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		save_now()


func _draw() -> void:
	# ⭐ M30.27：**远景层**（边缘雾 + 山脊）画在**世界之前** —— 背景必须先画，否则会盖住玩家。
	# ⚠️ M30.27 远景层暂时**关闭**：开启后画面全黑（日志无报错 → 是覆盖关系问题，不是脚本错）。
	# #    代码保留，下一批定位：先把边缘雾/山脊分开单独开关，逐个排除。   # ⚠️ M30.27 暂时关闭：开启后画面全黑（待排障）
	_draw_far()
	# 世界底色（M7）：⭐ 放在最前面 —— 父节点先画，所以它天然是背景
	_draw_world()
	_draw_swings()

	# 把伤害区画出来。不给玩家看见，他就不知道自己的攻击范围到底有多大。
	for h in hits:
		var c: Vector2 = h["center"]
		var d: Vector2 = h["dir"]
		var perp := Vector2(-d.y, d.x)               # 垂直于朝向的方向
		var hl := float(h["length"]) * 0.5
		var hw := float(h["width"]) * 0.5
		var k := 1.0 - clampf(float(h["t"]) / maxf(float(h["life"]), 0.001), 0.0, 1.0)

		var p0 := c + d * hl + perp * hw
		var p1 := c + d * hl - perp * hw
		var p2 := c - d * hl - perp * hw
		var p3 := c - d * hl + perp * hw
		# ⭐ M30.7：判定框**弱化成幽灵** —— 它现在只负责「看得清打到哪」，
		#    主视觉交给掌风弧光。用户要求「未命中就别花哨」，所以压到几乎只剩描边。
		draw_colored_polygon(PackedVector2Array([p0, p1, p2, p3]),
				Color(0.95, 0.85, 0.45, 0.09 * k))
		draw_polyline(PackedVector2Array([p0, p1, p2, p3, p0]),
				Color(1.0, 0.92, 0.55, 0.30 * k), 1.5)

	# 伤害数字：往上飘 + 淡出（世界坐标，所以会跟着相机走）
	for n in numbers:
		var fade := 1.0 - clampf(float(n["t"]) / maxf(float(n["life"]), 0.001), 0.0, 1.0)
		var at: Vector2 = n["pos"] + Vector2(-30.0, -18.0 - (1.0 - fade) * 28.0)
		if font != null:
			draw_string(font, at, str(n["text"]), HORIZONTAL_ALIGNMENT_CENTER, 60.0, 15,
					Color(n["color"], fade))

	# ⭐ M30.27：**云带**（前景薄雾）—— 画在地形之后，才有"雾在人和地之间"的层次。
	#    ⚠️ M31.3 更正措辞（行为不变、云不挪）：原文「画在实体之后」是**错的** —— Godot 的
	#       CanvasItem 顺序是**父节点的 `_draw()` 画在子节点之前**，而玩家/敌人全是 `Game`
	#       的子节点（详见 `ForegroundLayer.gd` 头注释），所以这里的云实际落在**实体之下**。
	#       定案原文说的是「在**人和地**之间」= 地形 < 云 < 人 —— 现状正好命中，别再挪。
	#       想让云盖到人，该挂 `FgLayer`（`_set_fg_occlusion`，z_index=64），不是改这一行。
	# ⭐ M31.3：**远山剪影** —— 画在云**之前**（山比云远，近盖远）。俯视角没有地平线，
	#    必须压在地形之上，落在屏幕顶部那条带上才读得出"北边很远的地方有山"。
	_draw_ridges()
	# ⭐ 云（近雾）画在山**之后** —— 山是远景、云是近雾，语义上必须近盖远。
	#    ⚠️ M31.3 更正：原来这里是云在前、山在后，把"近的被远的盖"写反了（只改顺序不改行为量级：
	#       云 alpha 0.055 vs 山 0.24，视觉变化可忽略）。
	_draw_clouds()
	# ⭐ M30.24（用户定案）：**那套"地面上撒竹子"不要了**（"太丑"）。
	#    大世界的尺度感不靠地面装饰，靠**远处的层次**（山影 / 雾 / 空气透视）——
	#    而那属于**背景层**（要画在 _draw 的最前面），不是这里。
	#    ⭐ M31.3：`_draw_foreground()` 现在**可开关**了（命令行 `-- --foreground` 或 F9，默认关）。
	#    它不在这里调用 —— 原因不是"还没做"，而是**在这里调用遮不住人**：
	#    `Game._draw()` 画在子节点之前，而玩家/敌人都是 `Game` 的子节点。
	#    打开开关后由 z_index=64 的 `FgLayer` 子节点来画，才落在人之后。


## ⭐ M30.7：掌风弧光。一个**月牙**（外弧 + 内弧拼成的环形扇面）朝朝向扫出去 ——
##    「掌心凝灵、拍出一掌」的气流，不是刀光（主角不持武器）。
##    ⚠️ 纯表现：它和 `hits`（判定）是**两件事**，判定永远只看 hits。
## ⭐ M30.22：**前景遮挡层** —— 这是 HD-2D「立体书感」最便宜的一步（不用换渲染器、不用新美术）。
##    做法：竹林格的**树冠**在角色之后绘制（同 CanvasItem 后画 = 盖在上面），
##    玩家走进竹林时上半身被树冠遮住；走出竹林就露出来。
##    ⚠️ 两条纪律：
##      ① 树冠位置**由格子决定**，绝不跟着玩家画 —— 跟着画就成了「头上顶个帽子」。
##      ② 只画玩家附近 3 格内的竹林，不刷满屏幕（性能 + 画面都不该被树冠淹掉）。
## ⚠️ 参数是**画在哪个 CanvasItem 上**：默认状态下本函数不被调用；
##    打开开关后由 `FgLayer` 传自己进来（在 `Game._draw()` 里画 = 落在人身后，遮不住）。
func _draw_foreground(target: CanvasItem) -> void:
	if player == null or not is_instance_valid(player):
		return
	var pc := GameData.cell_of(player.position)
	var cell := GameData.WORLD_CELL
	## ⚠️ 只画**玩家上方 2 格到下方 1 格**：能遮挡玩家的只可能是这些格，多画无意义
	for dy in range(-2, 2):
		for dx in range(-2, 3):
			var cx: int = pc.x + dx
			var cy: int = pc.y + dy
			if not GameData.in_map(Vector2i(cx, cy)):
				continue
			if GameData.cell_terrain(cx, cy) != "竹林":
				continue
			## ⭐ M30.23：真竹子（原来那三团圆已经删了）。
			##    由**格坐标**做种子：同一格的竹竿位置/高度/叶数永远一样（不会闪）；
			##    只有**风摆**随时间动 —— 那一项让整个画面立刻"活"起来。
			var h9: int = (cx * 73856093) ^ (cy * 19349663)
			var ah: int = abs(h9)
			var base_y := float(cy) * cell - GameData.cell_elev(cx, cy) * GameData.ELEV_LIFT + cell
			var tsec := float(Time.get_ticks_msec()) / 1000.0
			var sway := sin(tsec * 1.7 + float(ah % 628) * 0.01) * 2.4
			for k in range(3):
				var sx := float(cx) * cell + cell * (0.26 + 0.24 * float(k)) + float((ah >> (k * 3)) % 5) - 2.0
				var top := base_y - 25.0 - float((ah >> (k * 4 + 1)) % 9)
				## 竹竿（深绿）+ 竹节（一节亮）
				target.draw_line(Vector2(sx, base_y), Vector2(sx + sway * 0.6, top), Color(0.15, 0.25, 0.14, 0.95), 2.0)
				target.draw_line(Vector2(sx + sway * 0.6, top + 11.0), Vector2(sx + sway * 0.6, top + 7.0),
						Color(0.30, 0.45, 0.24, 0.95), 2.0)
				## 竹叶：三片斜细叶（羽状）
				for m in range(3):
					var lx := sx + sway * 0.9 + float(m - 1) * 5.0
					var ly := top + float(m) * 3.0
					var dir9 := -1.0 if m == 1 else 1.0
					target.draw_line(Vector2(lx, ly), Vector2(lx + dir9 * 9.0, ly + 4.0), Color(0.23, 0.40, 0.21, 0.92), 1.5)


func _draw_swings() -> void:
	if swings.is_empty():
		return
	var arc: Dictionary = GameData.ATTACK["arc"]
	var half := deg_to_rad(float(arc["spread"]) * 0.5)
	for s in swings:
		var k := 1.0 - clampf(float(s["t"]) / maxf(float(s["life"]), 0.001), 0.0, 1.0)   # 1 → 0
		var c: Vector2 = s["center"]
		var dirv: Vector2 = s["dir"]
		# 越扫越远、越扫越淡：扇面往外推，才像「扫出去」而不是「贴在手上」
		var rad := float(arc["radius"]) * (1.0 + (1.0 - k) * 0.35)
		var a0 := dirv.angle() - half
		var outer := PackedVector2Array()
		var inner := PackedVector2Array()
		for i in range(13):
			var a := a0 + (2.0 * half) * float(i) / 12.0
			outer.append(c + Vector2(cos(a), sin(a)) * rad)
		for i in range(12, -1, -1):
			var a2 := a0 + (2.0 * half) * float(i) / 12.0
			inner.append(c + Vector2(cos(a2), sin(a2)) * (rad * 0.62))
		var band := PackedVector2Array()
		band.append_array(outer)
		band.append_array(inner)
		draw_colored_polygon(band, Color(0.74, 0.92, 0.99, 0.26 * k))
		draw_polyline(outer, Color(0.88, 0.97, 1.0, 0.72 * k), 2.0)
		draw_polyline(inner, Color(0.78, 0.93, 1.0, 0.40 * k), 1.5)


# ==================== 自测（M2）====================
# 为什么值得写：编程 70% 的时间在找 bug，不是写新代码。
# 有了它，你每次改完只要跑一条命令，就知道自己有没有弄坏东西。

## ⭐ M31.3：**世界图签名比对**（启动时跑一次）。
##    不是断言 —— 它只在**运行期**吼一声，让人在改图的第一时间就知道；
##    真正的拦截交给自测里那三条 `world_sig` 断言（吼一声可以被忽略，红的测试不能）。
func _check_world_sig() -> void:
	var sig := GameData.world_sig()
	var base := GameData.world_sig_baseline()
	if base == "":
		print("[world_sig] ⚠️ 没有基线文件 %s（当前 %s）—— 跑一次 `-- --worldsig` 建基线"
				% [GameData.WORLD_SIG_PATH, sig])
		return
	if sig != base:
		push_error("worldmap.png 和基线对不上：当前 %s / 基线 %s。"
				% [sig, base]
				+ " 若是**有意**重烘焙，请跑 `-- --worldsig` 更新基线（这是唯一路径）。")


## ⭐ M31.3：**更新世界图基线的唯一路径**。
##    跑法：`Godot --path . -- --worldsig`（或窗口模式同样加 `-- --worldsig`）。
##    ⚠️ 这一步要**你自己跑、且确认过地形确实是你想要的** —— 它不是"让测试变绿"的按钮，
##    它是一次显式的确认：我改了地图，下面三处联动我已经想过 ——
##      ① `speed_mult_at()` 的高地减速阈值 ② 出生点 `e01` ③ 同心层 / 主城排布。
func _regen_world_sig() -> void:
	var sig := GameData.world_sig()
	var f := FileAccess.open(GameData.WORLD_SIG_PATH, FileAccess.WRITE)
	if f == null:
		print("[world_sig] 写不了基线文件：", GameData.WORLD_SIG_PATH)
		get_tree().quit(1)
		return
	f.store_string(sig)
	f.close()
	print("[world_sig] 基线已写入 %s = %s" % [GameData.WORLD_SIG_PATH, sig])
	get_tree().quit(0)


## ⭐⭐ M31.3 收尾：**地形参数的三条防线**（烘焙参数的回归测试）。
##    起因：这一轮烘焙学会了两件事 —— ① 动 `LEVELS` / `ELEV_LIFT` 会**同时**改掉崖的判定、
##    移动手感和画面观感，而三者原本都没有任何检测；② 上一轮全靠人眼看图才发现问题。
##    这三条把「靠人记」变成「改坏就红」。
##
## ⚠️ 三条各自守什么，别合并（合并了就不知道红在哪）：
##   A **量化级差**：用 **最小非零** 相邻高差（= 量化步长 1/(LEVELS-1)），不是最大值。
##     全图 max 是 120 世界单位，那是水陆边界 / 出生点平台的**有意崖**，拿它当 bug 就永远红。
##     守的是「LEVELS 变粗或 LIFT 变大 → **所有台缘都成崖** → 画面看着是墙人却能走上去」。
##   B **洞高**：`max(向南下降) × LIFT ≤ 半屏高`。守黑带。判据推导见 `GameData.ELEV_LIFT` 注释。
##   C **水面 / 泥沼占比**：守「水面悄悄没了」和「新增地形被烘没了」。
func _check_world_terrain() -> void:
	if not GameData.world_ready():
		return
	var lift := GameData.ELEV_LIFT
	var cliff_w := GameData.CLIFF_STEP * lift            # 崖的世界单位上限（12）
	# 半屏高度换算成**世界单位**：视口像素 ÷ zoom ÷ 2。⚠️ 别写死 192（改 zoom 就错）
	# ⚠️⚠️ **不能用 `get_viewport_rect()`**：headless 下窗口是**方的**（实测 (1366,1366)），
	#    算出来是 341.5 而不是 192 —— 这条防线在 CI（headless）里就形同虚设，等于没写。
	#    改用工程里配的视口高度，headless 与窗口模式都是 768 → 半屏 192。
	var vh := float(ProjectSettings.get_setting("display/window/size/viewport_height", 768))
	var z9 := GameData.CAMERA_ZOOM
	if is_instance_valid(camera):
		z9 = maxf(camera.zoom.y, 0.01)
	var half_h := vh * 0.5 / z9
	var step := 1.0          # 最小非零相邻高差 = 量化步长
	var cliff_n := 0
	var pair_n := 0
	var max_drop := 0.0      # 最大「向南下降」× LIFT = 最大洞高（世界单位）
	var water := 0
	var marsh := 0
	for cy in range(GameData.WORLD_ROWS):
		for cx in range(GameData.WORLD_COLS):
			var tn := GameData.cell_terrain(cx, cy)
			if tn == "水泽":
				water += 1
			elif tn == "泥沼":
				marsh += 1
			var e := GameData.cell_elev(cx, cy)
			for k in range(2):
				var nx2: int = cx + (1 if k == 0 else 0)
				var ny2: int = cy + (0 if k == 0 else 1)
				if not GameData.in_map(Vector2i(nx2, ny2)):
					continue
				var ad := absf(GameData.cell_elev(nx2, ny2) - e)
				pair_n += 1
				if ad > 1e-6 and ad < step:
					step = ad
				if ad > GameData.CLIFF_STEP:
					cliff_n += 1
			if GameData.in_map(Vector2i(cx, cy + 1)):
				max_drop = maxf(max_drop, (e - GameData.cell_elev(cx, cy + 1)) * lift)
	var total := GameData.WORLD_COLS * GameData.WORLD_ROWS
	var cliff_pct := 100.0 * float(cliff_n) / float(maxi(pair_n, 1))
	var water_pct := 100.0 * float(water) / float(total)
	var marsh_pct := 100.0 * float(marsh) / float(total)
	## ⭐ M31.3 收尾复核：**那条"黑带"守的是 bug，不是几何**（queue_redraw 被短路，fbe4fab 已修）。
	##    下面三条按"它到底守得住什么"重新定性，守不住的一律改名或删掉 ——
	##    留一条永远绿、又挡不住任何东西的断言，等于养一条看起来在工作的防线。
	_check("量化级差 × LIFT ≤ 崖阈值（守「每级台缘的暗缝宽度」）", step * lift <= cliff_w + 0.001,
			"%.2f 世界单位 > %.2f（量化步长 %.4f = 1/20；崖壁不画，所以这一级差 = 每级台缘暗缝的高度）"
			% [step * lift, cliff_w, step])
	_check("全图崖占比 ≤ 10%（守「暗缝密度」）", cliff_pct <= 10.0,
			"%.1f%%（%d/%d 组相邻关系是崖 → 就有多少条暗缝）" % [cliff_pct, cliff_n, pair_n])
	## ⚠️ 这条**只挡灾难性回归**（LIFT 翻倍 / 落差暴增才会红），不挡观感：
	##    暗缝的观感门槛是一格高 32（`ELEV_LIFT < 53`），当前 120 世界单位**并不达标**，
	##    那是已知代价，正解是补南向裙边（见 `GameData.ELEV_LIFT` 注释），不是压落差。
	##    别把这条阈值当成"合格线"去调 —— 它只是"别再坏下去"的绊线。
	_check("最大「向南下降」暗缝高度 ≤ 半屏高（绊线：只挡灾难性回归，不挡观感）",
			max_drop <= half_h + 0.001,
			"暗缝 %.0f > 半屏 %.0f（缝高 = Δe×LIFT，只在向南下降处出现；观感门槛是 32，当前不达标）"
			% [max_drop, half_h])
	## ⭐ 新增（替代被删掉的「LIFT ≤ 半屏×1.25」那条 —— 它守的"黑带"已被证伪，纯装饰，删）：
	##    出生点平坝（±16 格）内海拔被烘焙成同一档 ⇒ **必须零向南级差 ⇒ 零暗缝**。
	##    这条守的是"主城/出生区画面干净"，一旦重烘焙把平坝打散（LEVELS 或清场半径改了）立刻红。
	var spawn_drop := 0.0
	var cc := Vector2i(GameData.WORLD_COLS / 2, GameData.WORLD_ROWS / 2)
	for cy in range(cc.y - 16, cc.y + 16):
		for cx in range(cc.x - 16, cc.x + 16):
			if not GameData.in_map(Vector2i(cx, cy + 1)):
				continue
			spawn_drop = maxf(spawn_drop,
					(GameData.cell_elev(cx, cy) - GameData.cell_elev(cx, cy + 1)) * lift)
	_check("出生点平坝（±16 格）内零暗缝（守「主城/出生区画面干净」）", spawn_drop <= 0.001,
			"平坝内最大向南级差 %.2f 世界单位（平坝必须同档；LEVELS 或清场半径改了必红）"
			% spawn_drop)
	_check("水面占比 8~12%（烘焙参数的直接产物，守「水面悄悄没了」）",
			water_pct >= 8.0 and water_pct <= 12.0,
			"%.1f%%（%d/%d 格）" % [water_pct, water, total])
	_check("泥沼存在且不过量（M31.3 新增地形，守「被烘没了」）",
			marsh > 0 and marsh_pct < 10.0,
			"%.2f%%（%d 格）" % [marsh_pct, marsh])
	## ⭐ M31.3：**全屏暗缝覆盖率**（四个取景点：出生点 + 上轮抓帧的 drop/shore/slope）
	##    ⚠️ 校准依据：修复前像素实测 drop 24.2% / shore 10.5% / slope 3.7%。
	##    ① 裙边**开**时应≈0 —— 这条守的是"裙边逻辑以后被改坏"（改坏立刻红）。
	##    ② 裙边**关**时是当前默认观感，只作绊线（≤30%，防止哪天突然翻倍）。
	var gap_on := 0.0
	var gap_off := 0.0
	for pt in [Vector2(1792.0, 1536.0), Vector2(1264.0, 368.0),
			Vector2(2672.0, 656.0), Vector2(2256.0, 2320.0)]:
		gap_on = maxf(gap_on, _gap_ratio_at(pt, true))
		gap_off = maxf(gap_off, _gap_ratio_at(pt, false))
	## ⚠️ 阈值按「裙边只填 ≤ 一级台阶」之后的新现实重标：开裙边**不会归零**（大缝故意不填），
	##    守的是"小缝被填掉"这件事本身 ⇒ 用"开了必须比关了明显少"作判据（留 1 个点余量）。
	_check("裙边开启后暗缝覆盖率必须下降（守「裙边逻辑被改坏 / 被限死」）", gap_on < gap_off - 1.0,
			"关 %.1f%% → 开 %.1f%%（只填 ≤%.1f 的缝，大缝故意留着；算法见 `_gap_ratio_at`）"
			% [gap_off, gap_on, SKIRT_MAX])
	_check("裙边关闭时暗缝覆盖率 ≤ 30%（绊线：记录默认观感，只挡突然恶化）", gap_off <= 30.0,
			"%.1f 个百分点（裙边默认关，这是当前默认观感的已知值）" % gap_off)
	## ⭐ 判据（team-lead 拍板，取代"未覆盖率%"）：**单条最大缝高 ≤ 一格高(32)，且不存在 >32 的缝**。
	##    ⚠️ 分两类报：水陆交界的深水岸（走不下去，不是"能穿过去的墙"）与陆-陆可通行缝（是真问题）。
	var seam_land := 0.0        # 陆-陆（可通行）最大缝高
	var seam_water := 0.0       # 至少一侧是水的最大缝高
	var seam_land_n := 0
	var seam_big := 0
	for cy9 in range(GameData.WORLD_ROWS - 1):
		for cx9 in range(GameData.WORLD_COLS):
			var d9b := (GameData.cell_elev(cx9, cy9) - GameData.cell_elev(cx9, cy9 + 1)) * lift
			if d9b <= 32.0:
				continue
			seam_big += 1
			if GameData.cell_terrain(cx9, cy9) == "水泽" or GameData.cell_terrain(cx9, cy9 + 1) == "水泽":
				seam_water = maxf(seam_water, d9b)
			else:
				seam_land = maxf(seam_land, d9b)
				seam_land_n += 1
	## ⚠️ 这条**当前不满足**（陆-陆最大 120，全在出生平台北缘 cy=31 / x 67~72）——
	##    它是**数据层**的问题（平台被烘焙成硬边方台），修法在 `gen_worldmap.mjs` 给平台加过渡带，
	##    ⇒ 要动 worldmap.png + 重签 .sig，得 team-lead / 用户拍板，**先打印不设闸**，别假装守住了。
	print("[地形预警] 陆-陆可通行的大缝：%d 条，最大 %.0f 世界单位（>32 观感门槛；"
			% [seam_land_n, seam_land]
			+ "位置集中在出生平台北缘 cy=31；水陆交界大缝最大 %.0f，深水岸走不下去，不计入）"
			% seam_water)
	_check("陆-陆可通行的大缝（>32）不超过 8 条（绊线：锁住当前已知集合，不许扩散）",
			seam_land_n <= 8,
			"%d 条，最大 %.0f（当前已知：出生平台北缘 6 条 60~120；"
			% [seam_land_n, seam_land]
			+ "真要归零得回烘焙给平台加过渡带，那要动 worldmap.png，待拍板）")


## ⭐ M31.3：**全屏暗缝覆盖率** —— 把外面那套「clear color 连通块统计」搬进引擎，
##    直接按**世界数据 + 绘制源码的同一套几何**算"屏幕上哪些地方没有任何格子覆盖"，
##    ⇒ 不依赖抓帧、不依赖肉眼（这轮已经眼误两次，不许再看图下结论）。
## 算法：把视野切成 4×4 世界单位的粗网格，把「格子顶面」（+ 可选裙边）铺进去，
##    没被铺到的网格占比 = 暗缝覆盖率。缝最窄 10 世界单位（一级台阶 0.05×200）→ 2~3 行网格，抓得住。
## ⚠️ 只在自测里跑（有 resize，不在 _draw 里）。
const GAP_GRID := 4.0


func _gap_ratio_at(center: Vector2, use_skirt: bool) -> float:
	var cell := GameData.WORLD_CELL
	var vw := float(ProjectSettings.get_setting("display/window/size/viewport_width", 1366))
	var vh := float(ProjectSettings.get_setting("display/window/size/viewport_height", 768))
	var z9 := GameData.CAMERA_ZOOM
	if is_instance_valid(camera):
		z9 = maxf(camera.zoom.y, 0.01)
	var half := Vector2(vw, vh) / z9 * 0.5
	## ⚠️ 相机被世界边界夹住，取点时要照样夹 —— 不然取到边角会算出假的高覆盖率
	var ctr := Vector2(
			clampf(center.x, half.x, float(GameData.WORLD_COLS) * cell - half.x),
			clampf(center.y, half.y, float(GameData.WORLD_ROWS) * cell - half.y))
	var view := Rect2(ctr - half, half * 2.0)
	var gw := int(ceilf(view.size.x / GAP_GRID))
	var gh := int(ceilf(view.size.y / GAP_GRID))
	var cov := PackedByteArray()
	cov.resize(gw * gh)
	var pad_up := cell * 2.0
	var pad_dn := cell * 2.0 + GameData.ELEV_LIFT
	var vis_r := Rect2(ctr - half - Vector2(cell * 2.0, pad_up),
			half * 2.0 + Vector2(cell * 4.0, pad_up + pad_dn))
	for cy in range(GameData.WORLD_ROWS):
		for cx in range(GameData.WORLD_COLS):
			var p := Vector2(float(cx) * cell, float(cy) * cell)
			if not vis_r.has_point(p):
				continue
			var e := GameData.cell_elev(cx, cy)
			var top := float(cy) * cell - e * GameData.ELEV_LIFT
			_gap_mark(cov, view, gw, gh, Rect2(Vector2(p.x, top), Vector2(cell, cell)))
			if use_skirt and GameData.in_map(Vector2i(cx, cy - 1)):
				var d9 := (GameData.cell_elev(cx, cy - 1) - e) * GameData.ELEV_LIFT
				if d9 > 0.01 and d9 <= SKIRT_MAX:      # ⚠️ 与绘制端同一条限高
					_gap_mark(cov, view, gw, gh, Rect2(Vector2(p.x, top - d9), Vector2(cell, d9)))
	var unc := 0
	for v in cov:
		if v == 0:
			unc += 1
	return 100.0 * float(unc) / float(maxi(gw * gh, 1))


func _gap_mark(cov: PackedByteArray, view: Rect2, gw: int, gh: int, r: Rect2) -> void:
	var x0 := int(floorf((maxf(r.position.x, view.position.x) - view.position.x) / GAP_GRID))
	var x1 := int(ceilf((minf(r.position.x + r.size.x, view.position.x + view.size.x)
			- view.position.x) / GAP_GRID))
	var y0 := int(floorf((maxf(r.position.y, view.position.y) - view.position.y) / GAP_GRID))
	var y1 := int(ceilf((minf(r.position.y + r.size.y, view.position.y + view.size.y)
			- view.position.y) / GAP_GRID))
	for gy in range(maxi(y0, 0), mini(y1, gh)):
		for gx in range(maxi(x0, 0), mini(x1, gw)):
			cov[gy * gw + gx] = 1


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("[PASS] ", label)
		return
	_fail += 1
	var tail := ""
	if detail != "":
		tail = "  —— " + detail
	print("[FAIL] ", label, tail)


## ⭐ M29.6 性能红线断言：**`_draw()` 里不许 `new()` Resource**。
## 为什么要用「读自己源码」这种笨办法：
##    掉落物那条 bug（`Pickup._draw()` 每帧新建 SystemFont）**编译得过、跑得动、自测全绿**，
##    只有「地面上堆了十几个掉落物」时才会暴露 —— 逻辑断言抓不到它，只能抓代码形状。
## ⚠️ 导出版里 .gd 是字节码、读不到源码 → 那种环境下安静跳过（断言不该因环境而假失败）。
func _check_draw_hot_paths() -> void:
	var files := DirAccess.get_files_at("res://scripts")
	if files.is_empty():
		return
	var banned := ["make_font(", "SystemFont.new(", "create_tween("]
	var bad := ""
	var scanned := 0
	for fname in files:
		var fn := str(fname)
		if not fn.ends_with(".gd"):
			continue
		var text := FileAccess.get_file_as_string("res://scripts/%s" % fn)
		if text.is_empty():
			continue
		scanned += 1
		var in_draw := false
		var ln := 0
		for raw in text.split("\n"):
			ln += 1
			var line := str(raw)
			if line.begins_with("func "):
				in_draw = line.begins_with("func _draw")      # 函数一换，标记跟着换
				continue
			if not in_draw:
				continue
			var s := line.strip_edges()
			if s.begins_with("#"):
				continue
			for b in banned:
				if s.contains(str(b)):
					bad += "%s:%d " % [fn, ln]
	_check("_draw() 里没有 new() Resource（读源码扫了 %d 个脚本）" % scanned, bad == "",
			"踩线的位置：" + bad)


## ⭐ 自测专用的固定命窍配置：4 个槽位 = 灰烬/玄甲/惊雷/磐石，且**全部炼满**（= 可用）。
## 为什么需要它：开局现在只有**两枚**（惊雷/磐石改为世界获得），
## 而战斗相关的自测需要一个"火力齐全且都能用"的起点 —— 否则每条战斗断言都要自己搭一次场。
func _test_loadout() -> void:
	var load: Array = ["灰烬印", "玄甲印", "惊雷印", "磐石印"]
	for i in range(player.slot_seal.size()):
		if player.slot_summoned[i] != null:
			player.toggle_slot(i)                  # 先收回，免得留下悬空的 Seal 节点
		player.slot_seal[i] = str(load[i]) if i < load.size() else ""
		player.slot_damaged[i] = 0.0
		player.slot_life[i] = 0.0
	# ⚠️ M29.5：**顺带清空背包里的印**。否则「换上背包印」那个用例会把一枚印留在背包里，
	#    而下面又把同一枚摆回活跃槽 → 同一枚印有两份，「合成后备注的印还留着」会假失败。踩过。
	player.bag_seals.clear()
	for name_key in load:
		player.seal_refine[str(name_key)] = float(GameData.REFINE["max"])   # 炼满 = 可用
	# ⚠️ M23：**别让印诀的副产物泄漏到后面的测试**。
	#    四枚印一起显化会凑出印诀（玄甲+磐石 = 山岳）→ 减伤/减速留在身上，
	#    后面「被动对照」就会看到 0.70×0.5 = 0.35 而假失败。踩过。
	player.combo_cds.clear()
	player.cancel_sealing()          # 别让结印状态泄漏到后面的测试
	player._bulwark_left = 0.0
	player._haste_left = 0.0
	player._bulwark_taken = 1.0
	player._bulwark_speed = 1.0
	player._haste_speed = 1.0
	player.essence = player.essence_max


## ⭐ M31.3：**假绿灯**修的是结构，不是某一行。
##    历史坑：`camera.zoom` 那一行若在 Camera3D 下抛异常，会中断整个 `_run_selftest()`，
##    而收尾的 `quit()` 在异常路径下不执行 → 进程以 0 退出 = **崩了却看起来全过**。
##    ⚠️ GDScript **没有 try/catch**（4.x 至今没实现），所以单条断言的异常**抓不住**；
##    能做的、也必须做的是：**让"没跑完"本身变成一次 FAIL**。
##    做法：主体跑在 `_run_selftest_body()`，只有全程没抛异常才会走到 `_st_done = true`；
##    收尾 `_selftest_finish()` 由 `_process()` 兜底调用 —— 主体抛异常也照样执行。
func _run_selftest() -> void:
	selftest = true                 # ⭐ 自测绝不写盘
	_st_started = true
	print("=== 《蕴灵印》自测 ===")
	_run_selftest_body()
	_selftest_finish()


func _run_selftest_body() -> void:
	_build_world()

	# 1. 世界搭起来了吗
	_check("玩家已创建", player != null and is_instance_valid(player), "player 是 null")
	# ⭐ M25：开局（新局）就是满的 —— 用户要求「开局自动补满灵力」
	# ⭐ M27：自动存档间隔（用户定案 10 分钟）
	#    （原来这里还有一条「拍帧间隔 = 60 秒」的断言 —— M28 回溯移除后一并删了）
	_check("自动存档间隔是 10 分钟（用户定案）",
			is_equal_approx(float(GameData.ANCHOR["autosave_sec"]), 600.0),
			"%.0f 秒" % float(GameData.ANCHOR["autosave_sec"]))
	_check("新开局灵力是满的", is_equal_approx(player.essence, player.essence_max),
			"%.0f / %.0f" % [player.essence, player.essence_max])
	_check("新开局气血也是满的", is_equal_approx(player.hp, player.hp_max),
			"%.0f / %.0f" % [player.hp, player.hp_max])

	# 2. 假人按数据表生成了吗（数量来自 GameData，不是写死的数字）
	var want: int = GameData.DUMMY["spawns"].size()
	_check("假人数量是 %d" % want, dummies.size() == want, "实际 %d 个" % dummies.size())

	# 3. 打一下，目标血量应该**严格**减少约定的数值
	var d: Dummy = dummies[0]
	var before: float = d.hp
	var dmg: float = float(GameData.attack_of(player.realm)["damage"])
	var n: int = spawn_hit(d.position, Vector2.DOWN,
			float(GameData.ATTACK["length"]), float(GameData.ATTACK["width"]), dmg)
	_check("伤害区命中 1 个目标", n == 1, "实际命中 %d 个" % n)
	_check("血量严格减少 %.0f" % dmg, is_equal_approx(d.hp, before - dmg),
			"从 %.1f 变成 %.1f" % [before, d.hp])

	# 4. 打死了就该从名单里划掉
	spawn_hit(d.position, Vector2.DOWN, 44.0, 36.0, 9999.0)
	_check("血量归零的假人已从名单移除", not dummies.has(d), "dummies 里还有它")

	# 5. 方向性：攻击区中心必须落在玩家朝向的正前方
	player.position = Vector2(400.0, 300.0)
	player.facing = Vector2.RIGHT
	var rc := player.attack_center()
	_check("朝右时攻击区中心在玩家右侧",
			rc.x > player.position.x and is_equal_approx(rc.y, player.position.y),
			"attack_center() = %s" % rc)

	# ==================== M3：灵印 / 命窍 ====================
	# ⭐ 下面这些数字都是**写死的期望值**，不是从 GameData 里读回来的。
	#    如果读回来再比，等于自己跟自己比 —— 那不叫验收。

	# ⚠️ 这一段需要"火力齐全"的起点：开局只有两枚印（灰烬/玄甲），
	#    所以先把自测配置（4 枚 + 全部炼满 = 可用）铺好，再验灵印机制。
	_test_loadout()

	var before_ess: float = player.essence
	var r1: Dictionary = player.toggle_slot(0)
	_check("按 1 显化灰烬印", bool(r1.get("ok", false)) and str(r1.get("action", "")) == "summon", str(r1))
	_check("显化时严格扣 activate（灰烬印 = 6）", is_equal_approx(player.essence, before_ess - 6.0),
			"从 %.1f 变成 %.1f" % [before_ess, player.essence])

	var r2: Dictionary = player.toggle_slot(1)
	var armor = player.slot_summoned[1]
	_check("按 2 显化玄甲印", armor != null, "slot_summoned[1] 是 null")
	if armor != null:
		var seal_hp0: float = armor.hp
		armor.take_damage(10.0)
		_check("显化中的灵印有独立血条、能被打掉血", armor.hp < seal_hp0,
				"%.1f → %.1f" % [seal_hp0, armor.hp])
	_check("玄甲印的减伤被动生效（受伤 ×0.70）", is_equal_approx(player.damage_taken_mult(), 0.70),
			"倍率 %.2f" % player.damage_taken_mult())

	player.toggle_slot(1)
	_check("收回后被动加成立即消失", is_equal_approx(player.damage_taken_mult(), 1.0),
			"倍率 %.2f" % player.damage_taken_mult())

	# 连按两次 = 显化 → 收回。不该出现「叠了两个灵印」
	player.toggle_slot(0)                      # 先把灰烬印收回，回到干净状态
	var c_idle: int = player.summoned_count()
	player.toggle_slot(0)                      # 第 1 次：显化
	var c1: int = player.summoned_count()
	player.toggle_slot(0)                      # 第 2 次：收回
	var c2: int = player.summoned_count()
	_check("连按两次数字键不会叠加两个灵印", c_idle == 0 and c1 == 1 and c2 == 0,
			"显化数量 %d → %d → %d" % [c_idle, c1, c2])

	var hp_before: float = player.hp
	var r3: Dictionary = player.toggle_slot(2)
	var thunder = player.slot_summoned[2]
	_check("按 3 显化惊雷印", thunder != null, "slot_summoned[2] 是 null")
	if thunder != null:
		thunder.take_damage(99999.0)
		_check("灵印死亡后从命窍移除", str(player.slot_seal[2]) == "", "槽位仍是「%s」" % player.slot_seal[2])
		_check("反噬 = 气血上限的 15%",
				is_equal_approx(player.hp, hp_before - player.hp_max * 0.15),
				"%.1f → %.1f（期望 %.1f）" % [hp_before, player.hp, hp_before - player.hp_max * 0.15])
		_check("槽位进入受损状态", float(player.slot_damaged[2]) > 0.0,
				"剩余 %.1f 秒" % player.slot_damaged[2])

	# ==================== M4：敌人 AI ====================
	# ⭐ 敌人的判断全在 step_ai(delta) 里，所以这里直接喂 delta —— 不依赖真实帧。

	_check("敌人按数据表生成 %d 个" % GameData.ENEMY_SPAWNS.size(),
			enemies.size() == GameData.ENEMY_SPAWNS.size(), "实际 %d 个" % enemies.size())
	# ⭐ M31 Step 0：稳定 id —— 将来存档从「数组下标」改成「稀疏 id 集合」的地基。
	#    先守住两条不变量：每条都有非空 id，且 id 互不重复（重复 = 存档串位）。
	var e_ids: Array = []
	var e_id_bad := ""
	for sp in GameData.ENEMY_SPAWNS:
		var eid: String = str((sp as Dictionary).get("id", ""))
		if eid == "" or e_ids.has(eid):
			e_id_bad += (str(eid) if eid != "" else "<空>") + " "
		e_ids.append(eid)
	_check("每个敌人刷新点都有非空且不重复的 id", e_id_bad == "", "有问题：" + e_id_bad)

	var foe = enemies[0]        # 猛兽
	var brain = enemies[1]      # 智谋

	# 6. 仇恨范围外不动
	player.position = spawn_point
	foe.position = player.position + Vector2(0.0, 900.0)
	foe._aggro = false
	var pos0: Vector2 = foe.position
	foe.step_ai(0.1)
	_check("仇恨范围外不追击", foe.position.is_equal_approx(pos0), "位置动了：%s" % foe.position)

	# 7. 进仇恨范围就追过来
	foe.position = player.position + Vector2(0.0, 100.0)
	foe._aggro = false
	var dist_a: float = foe.position.distance_to(player.position)
	foe.step_ai(0.1)
	var dist_b: float = foe.position.distance_to(player.position)
	_check("进入仇恨范围后追击", dist_b < dist_a, "距离 %.1f → %.1f" % [dist_a, dist_b])

	# 8. 近身按冷却造成约定伤害
	foe.position = player.position + Vector2(0.0, 10.0)
	foe._aggro = true
	foe._target = player
	foe._cd = 0.0
	var hp_a: float = player.hp
	foe.step_ai(0.016)
	_check("近身后造成约定伤害 9", is_equal_approx(player.hp, hp_a - 9.0),
			"%.1f → %.1f" % [hp_a, player.hp])
	var hp_b: float = player.hp
	foe.step_ai(0.016)
	_check("冷却未走完不会连击", is_equal_approx(player.hp, hp_b), "又掉了 %.1f" % (hp_b - player.hp))

	# 9. 智谋型按概率转向显化中的灵印（roll 注入 → 规则可确定性验收）
	player.essence = player.essence_max   # 补满灵力，专心测 AI
	player.toggle_slot(0)
	var seal0 = player.slot_summoned[0]
	_check("智谋型 roll=0.10（<30%）时改打灵印", brain.choose_target(0.10) == seal0, "选错了目标")
	_check("智谋型 roll=0.90（≥30%）时仍打主角", brain.choose_target(0.90) == player, "选错了目标")
	_check("猛兽型任何 roll 都只打主角", foe.choose_target(0.0) == player, "选错了目标")

	# 10. 主角血量归零 → 触发死亡流程
	player.position = Vector2(300.0, 300.0)     # 先走开，才好验证「回到出生点」
	player.take_damage(99999.0)
	_check("主角血量归零触发死亡流程", deaths == 1, "deaths = %d" % deaths)
	_on_rewind_chosen(0)                      # M6：死亡会走「时间静止 → 选一枚 → 回溯」
	_check("死亡后回到出生点并回满血",
			player.position.is_equal_approx(spawn_point) and is_equal_approx(player.hp, player.hp_max),
			"位置 %s / 血 %.1f" % [player.position, player.hp])

	# ==================== M3.5：按一下就是使用 ====================
	# ⭐ 招式的决策入口是 Seal.step_skill(delta)，这里直接喂 delta —— 不依赖真实帧。
	# ⚠️ 自测共享同一个世界，前面的断言打死过灵印，所以这里要把槽位复原。

	player.position = spawn_point
	player.hp = player.hp_max
	player.essence = player.essence_max
	_test_loadout()

	# ⚠️ 上面那条「主角死亡」会**重建敌人**（锚点快照回滚），所以 foe/brain 得重新取
	foe = enemies[0]
	brain = enemies[1]
	foe.hp = foe.hp_max
	foe.dots.clear()
	foe.position = spawn_point + Vector2(60.0, 0.0)        # 灰烬印射程 110 内
	brain.position = spawn_point + Vector2(900.0, 0.0)      # 所有射程外

	# 1. 按一下 = 显化 + 立刻出招
	player.toggle_slot(0)
	var ember = player.slot_summoned[0]
	_check("按 1 显化灰烬印并立刻点火（不用等第一帧）",
			ember != null and foe.dots.size() == 1, "dots = %d" % foe.dots.size())

	# 2. 灼烧按 tick 扣血
	var dot_hp: float = foe.hp
	foe.step_ai(0.6)                                        # 跨过 0.5s 的一跳
	_check("灼烧每跳扣 3", is_equal_approx(foe.hp, dot_hp - 3.0),
			"%.1f → %.1f" % [dot_hp, foe.hp])

	# 3. 叠层上限
	foe.dots.clear()
	foe.add_dot(3.0, 3.0, ember, 0.5)                       # 第一枚印点的火
	foe.add_dot(3.0, 3.0, player, 0.5)                      # 假装第二枚印
	_check("灼烧可叠 2 层", foe.dots.size() == 2, "dots = %d" % foe.dots.size())
	foe.add_dot(3.0, 3.0, brain, 0.5)                       # 第三枚印
	_check("超过上限只刷新、不继续叠", foe.dots.size() == 2, "dots = %d" % foe.dots.size())

	# 4. 收回 → 火立刻灭，血不再掉
	foe.dots.clear()
	foe.add_dot(3.0, 3.0, ember, 0.5)
	var burning_hp: float = foe.hp
	player.toggle_slot(0)                                   # 收回灰烬印
	_check("收回后该印留下的火立刻清干净", foe.dots.size() == 0, "dots = %d" % foe.dots.size())
	foe.step_ai(1.0)
	_check("收回后敌人不再因灼烧掉血", is_equal_approx(foe.hp, burning_hp),
			"%.1f → %.1f" % [burning_hp, foe.hp])

	# 5. 惊雷印：预警 → 落雷；冷却；收回取消
	foe.hp = foe.hp_max
	foe.position = spawn_point + Vector2(100.0, 0.0)        # 130 射程内（惊雷印 range）
	player.essence = player.essence_max
	player.toggle_slot(2)
	var bolt = player.slot_summoned[2]
	var bolt_hp: float = foe.hp
	_check("按 3 显化惊雷印并挂上预警（尚未掉血）",
			bolt != null and bolt.has_pending_strike() and is_equal_approx(foe.hp, bolt_hp),
			"%.1f → %.1f" % [bolt_hp, foe.hp])
	bolt.step_skill(0.3)                                    # 跨过 0.25s 预警
	_check("预警时间到，落雷命中 18", is_equal_approx(foe.hp, bolt_hp - 18.0),
			"%.1f → %.1f" % [bolt_hp, foe.hp])
	var bolt_hp2: float = foe.hp
	bolt.step_skill(0.1)                                    # 冷却还剩 1.6s
	_check("冷却未走完不会再挂预警", is_equal_approx(foe.hp, bolt_hp2), "又掉了 %.1f" % (bolt_hp2 - foe.hp))

	bolt.step_skill(999.0)                                  # 清冷却，重新挂一道
	var cancel_hp: float = foe.hp
	player.toggle_slot(2)                                   # 收回
	_check("收回时未落地的雷被取消", bolt.has_pending_strike() == false, "预警没清掉")
	bolt.step_skill(0.3)
	_check("收回后那一道雷不会落下", is_equal_approx(foe.hp, cancel_hp),
			"%.1f → %.1f" % [cancel_hp, foe.hp])

	# 6. 玄甲印护主：先吃自身被动（×0.70），再转移走一半
	player.essence = player.essence_max
	player.hp = player.hp_max
	player.toggle_slot(1)
	var armor2 = player.slot_summoned[1]
	var p_hp: float = player.hp
	var a_hp: float = armor2.hp
	player.take_damage(20.0)
	_check("护主：主角掉 7（20 ×0.70 被动，再转走一半）",
			is_equal_approx(player.hp, p_hp - 7.0), "%.1f → %.1f" % [p_hp, player.hp])
	_check("护主：玄甲印承受另一半 7", is_equal_approx(armor2.hp, a_hp - 7.0),
			"%.1f → %.1f" % [a_hp, armor2.hp])

	armor2.position = player.position + Vector2(400.0, 0.0)  # 挪出 150 射程（自测不跑真实帧，位置可控）
	var p_hp2: float = player.hp
	var a_hp2: float = armor2.hp
	player.take_damage(20.0)
	_check("超出射程时不护主，主角掉满 14", is_equal_approx(player.hp, p_hp2 - 14.0),
			"%.1f → %.1f" % [p_hp2, player.hp])
	_check("超出射程时灵印不掉血", is_equal_approx(armor2.hp, a_hp2), "%.1f → %.1f" % [a_hp2, armor2.hp])

	# 7. 濒死：纯表现，不改数值
	armor2.hp = armor2.hp_max * 0.2
	_check("血量低于 30% 进入濒死", armor2.is_dying(), "hp = %.1f" % armor2.hp)
	_check("濒死不影响「还活着」", armor2.is_alive(), "is_alive 返回 false")

	# 8. 灵印被打死 → 它的火一起灭
	player.essence = player.essence_max
	foe.position = player.position + Vector2(60.0, 0.0)
	player.toggle_slot(0)
	var ember2 = player.slot_summoned[0]
	ember2.step_skill(0.0)
	_check("灰烬印留下灼烧", foe.dots.size() == 1, "dots = %d" % foe.dots.size())
	ember2.take_damage(99999.0)
	_check("灵印死亡后它的火也一起灭", foe.dots.size() == 0, "dots = %d" % foe.dots.size())

	# 9. 主角死亡 → 显化灵印自动收回，且不赔命
	if player.slot_summoned[1] != null:
		player.toggle_slot(1)                               # 先收回护主印，免得致死一击先把它打死
	player.slot_seal[2] = "惊雷印"
	player.slot_damaged[2] = 0.0
	player.essence = player.essence_max
	player.toggle_slot(2)
	player.hp = player.hp_max
	player.take_damage(99999.0)
	_check("主角死亡后显化灵印全部自动收回", player.summoned_count() == 0,
			"还剩 %d 个" % player.summoned_count())
	# ⚠️ M28：原来这里断言「回溯后命窍里仍然留着本命印」（时印会把本命印带回来）。
	#    回溯移除后，死亡**根本不碰命窍**，所以这条规则随功能一起暂停 —— 不测了。

	# ==================== M3.6：四种形态 ====================
	# ⭐ 持续 / timed / instant 的判定入口是 Player._tick_slots(delta)，自测直接喂 delta。

	_test_loadout()
	player.position = spawn_point
	player.hp = player.hp_max
	player.shield = 0.0
	player.shield_max = 0.0
	player.essence = player.essence_max
	# ⚠️ 同上：M3.5 的死一次会重建敌人，这里的引用也要重新取
	foe = enemies[0]
	brain = enemies[1]
	foe.hp = foe.hp_max
	foe.dots.clear()
	foe.position = player.position + Vector2(100.0, 0.0)      # 惊雷印射程 130 内

	_check("命窍有 4 个槽位", player.slot_seal.size() == 4,
			"实际 %d 个" % player.slot_seal.size())

	# 1. 一次性防御：套盾
	player.toggle_slot(3)
	_check("按 4 显化磐石印并套上 30 点护盾", is_equal_approx(player.shield, 30.0),
			"盾 = %.1f" % player.shield)

	# 2. 受伤顺序：先吃被动乘数（磐石印 ×0.85），再吃盾
	var hp_before_shield: float = player.hp
	player.take_damage(20.0)                                   # 20 ×0.85 = 17，全被盾吃掉
	_check("受伤先扣盾（20 ×0.85 = 17 由盾承担）", is_equal_approx(player.shield, 13.0),
			"盾 = %.1f" % player.shield)
	_check("盾没吃完时血一点不掉", is_equal_approx(player.hp, hp_before_shield),
			"血 %.1f → %.1f" % [hp_before_shield, player.hp])

	# 3. 盾吃满后，溢出部分才扣血
	player.take_damage(20.0)                                   # 盾 13 被吃光，溢出 4 点扣血
	_check("盾吃满后溢出 4 点才扣血",
			is_equal_approx(player.shield, 0.0) and is_equal_approx(player.hp, hp_before_shield - 4.0),
			"盾 = %.1f / 血 = %.1f" % [player.shield, player.hp])

	# 4. 收回 -> 盾立即消失
	player.essence = player.essence_max
	player.toggle_slot(3)
	_check("收回磐石印后护盾立刻消失", is_zero_approx(player.shield), "盾 = %.1f" % player.shield)

	# 5. timed 型：到点自动收回
	player.toggle_slot(3)
	player._tick_slots(2.0)                                    # life_time = 4 秒
	_check("护盾未到期时还在（2 秒 < 4 秒）", player.slot_summoned[3] != null, "2 秒就没了")
	player._tick_slots(2.5)
	_check("4 秒到期后磐石印自动收回", player.slot_summoned[3] == null, "还没收")
	_check("到期后护盾一起消失", is_zero_approx(player.shield), "盾 = %.1f" % player.shield)

	# 6. 持续型：每秒烧灵力
	# ⚠️ 一律**按数据算**：调平衡（比如灰烬印从 6/秒 改成 2.5/秒）不该让测试变红。
	var hd: float = float(GameData.SEALS["灰烬印"]["drain"])
	player.essence = player.essence_max
	player.toggle_slot(0)
	var after_activate: float = player.essence
	player._tick_slots(1.0)
	_check("持续型每秒扣 drain（灰烬印 %.1f/秒）" % hd,
			is_equal_approx(after_activate - player.essence, hd),
			"%.1f → %.1f" % [after_activate, player.essence])

	# 7. 灵力扣光 -> 持续型自动收回，且不算死亡
	player.essence = hd * 0.5                                  # 不够再烧一秒（按数据算）
	player._tick_slots(1.0)
	_check("灵力扣光时持续型自动收回", player.slot_summoned[0] == null, "还显化着")
	_check("灵力归零不会变成负数", is_zero_approx(player.essence), "灵力 = %.1f" % player.essence)
	_check("自动收回不算灵印死亡", str(player.slot_seal[0]) == "灰烬印",
			"槽位变成「%s」" % player.slot_seal[0])

	# 8. 一次性攻击：招式结算前不收回，结算后自动收回
	player.essence = player.essence_max
	player.toggle_slot(2)                                      # 惊雷印 activate 18 / drain 0
	var bolt2 = player.slot_summoned[2]
	var ess_after_bolt: float = player.essence
	_check("按 3 显化惊雷印并挂上预警", bolt2 != null and bolt2.has_pending_strike(), "没挂上预警")
	player._tick_slots(0.1)
	_check("招式结算前不会被提前收回", player.slot_summoned[2] != null, "被提前收了")
	player._tick_slots(0.1)
	_check("drain 为 0 的印不会随时间扣灵力", is_equal_approx(player.essence, ess_after_bolt),
			"%.1f → %.1f" % [ess_after_bolt, player.essence])

	var foe_hp_before_bolt: float = foe.hp
	bolt2.step_skill(0.3)                                      # 雷落地
	_check("落雷命中扣 18", is_equal_approx(foe.hp, foe_hp_before_bolt - 18.0),
			"%.1f → %.1f" % [foe_hp_before_bolt, foe.hp])
	player._tick_slots(0.1)
	_check("一次性型招式结算后自动收回", player.slot_summoned[2] == null, "没收回去")
	_check("自动收回没有取消那一发雷", is_equal_approx(foe.hp, foe_hp_before_bolt - 18.0),
			"伤害被取消了")

	# 9. 部位是名字，不是坐标
	player.essence = player.essence_max
	player.toggle_slot(0)
	var ember3 = player.slot_summoned[0]
	var want_pos: Vector2 = player.position + GameData.BODY_PARTS["右手"]
	_check("灰烬印贴在「右手」这个部位上",
			ember3 != null and ember3.position.is_equal_approx(want_pos),
			"实际位置 %s，期望 %s" % [ember3.position, want_pos])
	_check("玄甲印的部位是「躯干」", str(GameData.SEALS["玄甲印"]["body_part"]) == "躯干",
			"实际 %s" % GameData.SEALS["玄甲印"]["body_part"])

	# 10. 四个槽位互不干扰
	player.essence = player.essence_max
	player.toggle_slot(1)
	_check("槽 1 与槽 4 可以同时显化", player.slot_summoned[0] != null and player.slot_summoned[1] != null,
			"显化数量 %d" % player.summoned_count())
	_check("两个槽位是不同的灵印节点", player.slot_summoned[0] != player.slot_summoned[1], "拿到同一个节点")

	# 11. 主角死亡 -> 全部收回、盾清零
	player.toggle_slot(3)                                      # 再套一层盾
	player.hp = player.hp_max
	player.take_damage(99999.0)
	_on_rewind_chosen(0)                      # M6：死亡会走回溯流程
	_check("主角死亡后显化灵印全部收回", player.summoned_count() == 0,
			"还剩 %d 个" % player.summoned_count())
	_check("主角死亡后护盾清零", is_zero_approx(player.shield), "盾 = %.1f" % player.shield)

	# ==================== M5：锚点 + 死亡重生 ====================
	# ⭐ 验收就一句：死亡后回到锚点，采集点恢复正常、敌人复活。

	player.position = spawn_point
	player.hp = player.hp_max
	player.essence = player.essence_max
	for i in range(player.slot_seal.size()):
		player.slot_damaged[i] = 0.0
		if player.slot_summoned[i] != null:
			player.toggle_slot(i)

	_check("采集点按数据表生成 %d 个" % GameData.GATHER["spots"].size(),
			gathers.size() == GameData.GATHER["spots"].size(), "实际 %d 个" % gathers.size())
	var g_ids: Array = []
	var g_id_bad := ""
	for spot in GameData.GATHER["spots"]:
		var gid: String = str((spot as Dictionary).get("id", ""))
		if gid == "" or g_ids.has(gid):
			g_id_bad += (str(gid) if gid != "" else "<空>") + " "
		g_ids.append(gid)
	_check("每个采集点都有非空且不重复的 id", g_id_bad == "", "有问题：" + g_id_bad)

	# 1. 走到采集点旁按 E
	var gp = gathers[0]
	player.position = gp.position
	player.essence = 40.0
	var got: float = try_gather()
	_check("按 E 采集回 25 点灵力", is_equal_approx(got, 25.0) and is_equal_approx(player.essence, 65.0),
			"采到 %.0f，灵力 %.1f" % [got, player.essence])
	_check("采过的点变成已耗尽", gp.depleted, "还是满的")

	# 2. 同一个点采不出第二次
	_check("同一个点采不出第二次", is_zero_approx(try_gather()), "又采到了")

	# 3. 灵力封顶不溢出
	player.essence = player.essence_max - 5.0
	player.position = gathers[1].position
	try_gather()
	_check("灵力封顶不溢出", is_equal_approx(player.essence, player.essence_max),
			"灵力 = %.1f" % player.essence)

	# 4. 站远了采不到
	player.position = spawn_point + Vector2(0.0, 400.0)
	_check("离采集点太远就采不到", is_zero_approx(try_gather()), "竟然采到了")

	# 5. 死亡 → 回锚点 + 采集点复原 + 敌人复活
	var enemy_total: int = snapshot["enemies"].size()
	enemies[0].take_damage(99999.0)                 # 打死一个（它会从 enemies 里移除）
	var alive_before: int = enemies.size()
	_check("打死一个敌人后场上少一个", alive_before == enemy_total - 1, "剩 %d 个" % alive_before)

	player.hp = player.hp_max
	player.position = Vector2(300.0, 300.0)
	player.take_damage(99999.0)                     # 死一次
	_on_rewind_chosen(0)

	_check("死亡后回到回溯帧的位置", player.position.is_equal_approx(spawn_point), "位置 %s" % player.position)
	_check("死亡后灵力回满", is_equal_approx(player.essence, player.essence_max),
			"灵力 = %.1f" % player.essence)
	_check("死亡后敌人复活（数量回到快照值）", enemies.size() == enemy_total,
			"%d → %d" % [alive_before, enemies.size()])
	_check("复活的敌人血量回到快照值",
			is_equal_approx(enemies[0].hp, float(snapshot["enemies"][0]["hp"])),
			"hp = %.1f" % enemies[0].hp)
	_check("复活的敌人位置回到快照位置",
			enemies[0].position.is_equal_approx(snapshot["enemies"][0]["pos"]),
			"位置 %s" % enemies[0].position)
	_check("死亡后采集点复原（两个都可以再采）",
			not gathers[0].depleted and not gathers[1].depleted, "还是空的")

	# 6. 快照语义：快照时已经死掉的敌人不会复活
	#    ⭐ 这一条是「快照」和「重置」的分界线 —— 没有它，M5 就只是把世界推倒重来。
	enemies[0].take_damage(99999.0)
	var alive_at_snapshot: int = enemies.size()
	gathers[0].depleted = true
	take_snapshot()                                # 在「少一个敌人 + 采集点 1 空着」的时刻拍快照
	player.hp = player.hp_max
	player.take_damage(99999.0)                    # 再死一次
	_on_rewind_chosen(0)
	_check("快照时已死的敌人不会复活", enemies.size() == alive_at_snapshot,
			"期望 %d 个，实际 %d 个" % [alive_at_snapshot, enemies.size()])
	_check("快照时已空的采集点保持空", gathers[0].depleted, "被复原了")

	# 6b. ⭐ restore_snapshot_from 必须按**传进来的票据**恢复，而不是按全局 `snapshot`
	#     踩过的坑：函数体里写死了全局 snapshot。只有一个锚点快照时**完全看不出来**，
	#     一旦将来加第二个槽位（域边界存档），跨域回退会静默退到错误的那一帧。
	take_snapshot()                                  # 全局 snapshot = 这一刻（血量高、采集点 1 是满的）
	var hp_at_anchor: float = enemies[0].hp
	enemies[0].hp = 7.0                              # 打残（不死，仍留在名单里）
	gathers[1].depleted = true
	var ticket: Dictionary = _snapshot_dict()        # 票据 = 「残血 7 + 采集点 1 空」
	enemies[0].hp = 3.0                              # 再补一刀：票据 ≠ 全局快照 ≠ 现状
	gathers[1].depleted = false
	restore_snapshot_from(ticket)
	_check("按票据恢复：血量回到**票据**里的 7（不是全局快照的 %.1f）" % hp_at_anchor,
			is_equal_approx(enemies[0].hp, 7.0),
			"hp = %.1f（票据 7 / 全局 %.1f）" % [enemies[0].hp, hp_at_anchor])
	_check("按票据恢复：采集点状态取**票据**里的值（空）", gathers[1].depleted, "被复原成满的")
	restore_snapshot()                               # 收尾：回到锚点帧，不影响后面的用例

	# ==================== M6 → M28：死亡 = 回到上次存档 ====================
	# ⚠️ M28（用户定案）：**回溯功能暂时移除**，等后面重新设计。
	#    所以这里不再测「面板 / 选印 / 退到哪一帧」，只测现在的规则：
	#    **死亡 → 世界退回快照（= 上次存档）+ 主角回出生点 + 补满 + 写盘**。
	_test_loadout()
	player.position = spawn_point
	player.hp = player.hp_max
	player.essence = player.essence_max
	take_snapshot()                       # 手动拍一次 = 模拟「上次存档」

	# 死后该退掉的东西
	player.bag.items["兽骨"] = 3
	player.bag.stones = 77
	player.cultivation = 40.0
	var m28_enemies: int = enemies.size()
	var m28_gathers: int = gathers.size()
	player.position = Vector2(600.0, 1200.0)      # 死前跑远一点

	player.hp = player.hp_max
	player.take_damage(99999.0)

	_check("死亡后回到出生点", player.position.is_equal_approx(spawn_point), str(player.position))
	# ⚠️ 比较的是**当前**上限，不是死前的上限：快照恢复会重算上限（炼化度/境界都可能被退回去），
	#    死前记下的那个数会过期（踩过：115/100 这种假失败）。
	_check("死亡后气血与灵力补满",
			is_equal_approx(player.hp, player.hp_max) and is_equal_approx(player.essence, player.essence_max),
			"%.0f/%.0f  %.0f/%.0f" % [player.hp, player.hp_max, player.essence, player.essence_max])
	_check("世界退回快照：背包里的东西退掉了", int(player.bag.items.get("兽骨", 0)) == 0,
			str(player.bag.items))
	_check("世界退回快照：灵石退掉了", int(player.bag.stones) == 0, str(player.bag.stones))
	_check("世界退回快照：修为退掉了", is_zero_approx(player.cultivation), "%.0f" % player.cultivation)
	_check("世界退回快照：敌人名单复原", enemies.size() == m28_enemies,
			"%d → %d" % [m28_enemies, enemies.size()])
	_check("世界退回快照：采集点复原", gathers.size() == m28_gathers,
			"%d → %d" % [m28_gathers, gathers.size()])
	_check("不再弹任何回溯面板（功能已移除）", not get_tree().paused, "游戏被暂停了")
	_check("死亡不夺走命窍（§4.3 的「除本命印外全失」随回溯一起暂停）",
			str(player.slot_seal[0]) != "" and str(player.slot_seal[1]) != "", str(player.slot_seal))

	# ==================== M7：世界与探索 ====================
	# ⭐ 验收：相机跟随且不越界；跑到四角能看到边界；换一个区能找到不同的采集点。

	var ws: Vector2 = GameData.WORLD["size"]
	# ⚠️ M29：世界与所有距离减半 + 相机 zoom = 2，所以「比屏幕大」要按**可见范围**算。
	#    全部按数据算 —— 写死 1366/768 会在调缩放时假失败（这次就是）。
	_check("相机 zoom 与数据表一致（世界减半的配套）",
			camera.zoom.is_equal_approx(Vector2(GameData.CAMERA_ZOOM, GameData.CAMERA_ZOOM)),
			"zoom = %s" % str(camera.zoom))
	_check("世界比可见范围大（视口 %.0f×%.0f ÷ zoom %.0f）"
			% [GameData.VIEWPORT.x, GameData.VIEWPORT.y, GameData.CAMERA_ZOOM],
			ws.x > GameData.VIEWPORT.x / GameData.CAMERA_ZOOM
			and ws.y > GameData.VIEWPORT.y / GameData.CAMERA_ZOOM,
			"世界 = %.0f×%.0f" % [ws.x, ws.y])
	_check("出生点在世界中心（世界布局没变）", spawn_point.is_equal_approx(ws * 0.5), str(spawn_point))

	# ==================== M29.6：性能红线 ====================
	# ⭐ 实测依据：地面上每个「数量 > 1」的掉落物，因为 `_draw()` 里每帧新建 SystemFont，
	#    白烧约 **6 毫秒/帧**；18 个在场时从 238 FPS 掉到 **13 FPS**。修好后同样 18 个 = 240 FPS。
	_check("make_font() 只造一次字体（缓存生效）", GameData.make_font() == GameData.make_font(),
			"两次拿到不同的 Font 实例")
	_check_draw_hot_paths()

	var area := 0.0
	for key in GameData.ZONES:
		var r: Rect2 = GameData.ZONES[key]["rect"]
		area += r.size.x * r.size.y
	_check("四个分区正好铺满世界（无空洞、无重叠）", is_equal_approx(area, ws.x * ws.y),
			"分区总面积 %.0f，世界 %.0f" % [area, ws.x * ws.y])

	# ⭐ 不变量版（数据派生）：每个区的中心必须落回自己 —— 改世界大小也不会假失败
	var zc_bad := ""
	for key in GameData.ZONES:
			var zr: Rect2 = GameData.ZONES[key]["rect"]
			if GameData.zone_at(zr.position + zr.size * 0.5) != key:
				zc_bad += str(key) + " "
	_check("每个分区自己的中心都落回自己（不变量）", zc_bad == "", "落错的区：" + zc_bad)
	## ⚠️ 这条原来是「zone_at 认得四个区的中心」—— 但 `zone_at` 早就改按**地形**返回了
	##    （连续大地图之后它返回 灵田/竹林/…），旧断言是在测已经不存在的东西。
	##    现在测的是**真正该成立的**：世界中心与四角都能返回一个**合法地形名**。
	## ⚠️ 这里原本比对的是 `WORLD_TERRAINS`（世界数据里 R 通道的地形名：水泽/草地/竹林/灵岩/灵田），
	##    但 `terrain_at()` 返回的是 `TERRAIN` 的 key（灵田/竹林/石山/雷泽/熔脉）—— **两套名字不一样**，
	##    所以这条断言一直在拿错集合比对（测的东西不存在）。用 TERRAIN.keys() 才对。
	var tnames: Array = GameData.WORLD_TERRAINS
	var tprobe: Array = [ws * 0.5, Vector2(ws.x * 0.1, ws.y * 0.1), Vector2(ws.x * 0.9, ws.y * 0.9), Vector2(ws.x * 0.9, ws.y * 0.1)]
	var tbad := ""
	for tp in tprobe:
		var tc := GameData.cell_of(tp)
		var tn: String = GameData.cell_terrain(tc.x, tc.y)
		if not tnames.has(tn):
			tbad += str(tp) + "=" + tn + " "
	_check("地形判定在整个世界范围内都返回合法地形", tbad == "", tbad)

	# 每个区都有采集点 —— 这才是「走出去探索」的意义
	for key in GameData.ZONES:
		var zone_count := 0
		for g in gathers:
			if is_instance_valid(g) and GameData.zone_at(g.position) == key:
				zone_count += 1
		_check("分区「%s」里有 2 处采集点" % key, zone_count == 2, "实际 %d 处" % zone_count)

	# 主角被钳在世界里
	player.position = Vector2(-500.0, -500.0)
	player._move(0.016)
	_check("主角走不出世界左上角", player.position.is_equal_approx(Vector2.ZERO), str(player.position))
	player.position = Vector2(9999.0, 9999.0)
	player._move(0.016)
	_check("主角走不出世界右下角", player.position.is_equal_approx(ws), str(player.position))

	# 相机：跟住主角 + 边界就是世界
	player.position = spawn_point
	camera.global_position = Vector2.ZERO
	_st_manual_tick = true            # ⭐ 告诉 `_process`：这是自测在手动喂帧，不是该收尾了
	_process(0.016)
	_st_manual_tick = false
	_check("相机跟住了主角", camera.global_position.is_equal_approx(player.position),
			"相机在 %s，主角在 %s" % [camera.global_position, player.position])
	_check("相机边界 = 世界矩形，不会拍到地图外",
			camera.limit_left == 0 and camera.limit_top == 0
			and is_equal_approx(float(camera.limit_right), ws.x)
			and is_equal_approx(float(camera.limit_bottom), ws.y),
			"limits = %d / %d / %d / %d" % [camera.limit_left, camera.limit_right,
					camera.limit_top, camera.limit_bottom])
	_check("相机是当前相机（不然画面不跟）", camera.is_current(), str(camera.is_current()))

	# ==================== M8：物品与背包 ====================
	# ⭐ 验收：打死敌人掉东西、能捡、背包数字对；背包满时行为明确。

	player.bag.items.clear()
	player.bag.stones = 0
	for pk in pickups.duplicate():
		if is_instance_valid(pk):
			pk.queue_free()
	pickups.clear()
	player.position = spawn_point

	_check("材料表有 8 种", GameData.MATERIALS.size() == 8, "实际 %d 种" % GameData.MATERIALS.size())
	_check("背包一开始是空的", player.bag.capacity_used() == 0 and player.bag.stones == 0,
			"占用 %d，灵石 %d" % [player.bag.capacity_used(), player.bag.stones])

	# 1. 采集把材料放进背包（灵力那条 M5 行为不变）
	# ⚠️ 不能拿 gathers[0]：前面 M5 那段已经把它采空，而且快照语义让它保持空着
	var spot0 = null
	for g in gathers:
		if is_instance_valid(g) and not g.depleted:
			spot0 = g
			break
	_check("场上还有可采的点", spot0 != null, "全被采空了")
	player.position = spot0.position
	var got_m: float = try_gather()
	_check("采集把材料放进背包", player.bag.count(spot0.item) == spot0.amount,
			"背包里有 %d 个 %s" % [player.bag.count(spot0.item), spot0.item])
	_check("采集仍然回 25 灵力（M5 行为没变）", is_equal_approx(got_m, 25.0), "回了 %.0f" % got_m)

	# 2. 危险区出触媒
	var catalyst := ""
	for sp: Dictionary in GameData.GATHER["spots"]:
		if str(GameData.MATERIALS[sp["item"]]["kind"]) == "触媒":
			catalyst = str(sp["item"])
			break
	_check("采集点里有触媒（雷区 / 热区）", catalyst != "", "一个都没找到")

	# 3. 敌人死了掉东西
	enemies[0].take_damage(99999.0)
	var dropped: int = pickups.size()
	_check("敌人死后地上有掉落物", dropped > 0, "掉了 %d 件" % dropped)
	var drop_names: Array = []
	for pk in pickups:
		drop_names.append(str(pk.item))
	_check("猛兽掉兽骨", drop_names.has("兽骨"), str(drop_names))

	# 4. 走过去自动捡（不用按键）
	var first_pk = pickups[0]
	var first_item: String = str(first_pk.item)
	var first_amount: int = int(first_pk.amount)
	var stones_before: int = player.bag.stones
	player.position = first_pk.position
	_tick_pickups(0.016)
	var picked: bool = player.bag.count(first_item) >= first_amount
	if first_item == GameData.CURRENCY:
		picked = player.bag.stones > stones_before
	_check("走过去自动捡起（不用按键）", picked, "背包里 %s = %d" % [first_item, player.bag.count(first_item)])
	_check("捡过的那件从地上消失", not pickups.has(first_pk), "还留在地上")

	# 5. 灵石不占背包容量
	var used: int = player.bag.capacity_used()
	player.bag.add(GameData.CURRENCY, 100)
	_check("灵石不占背包容积", player.bag.capacity_used() == used,
			"占用从 %d 变成 %d" % [used, player.bag.capacity_used()])

	# 6. ⭐ M30.4：背包按**容积**算（不同材料占不同体积）
	player.bag.items.clear()
	_check("草木 1 格 / 兽材 2 格 / 矿石 3 格（数字来自数据表）",
			GameData.volume_of("蕴灵草") == 1 and GameData.volume_of("兽骨") == 2
			and GameData.volume_of("玄铁矿") == 3,
			"草 %d / 骨 %d / 矿 %d" % [GameData.volume_of("蕴灵草"), GameData.volume_of("兽骨"),
					GameData.volume_of("玄铁矿")])
	_check("灵石不占容积（货币）", GameData.volume_of(GameData.CURRENCY) == 0,
			str(GameData.volume_of(GameData.CURRENCY)))
	_check("灵印不占容积（收藏 —— 用户明确要求「灵印就不占体积没有重量」）",
			GameData.volume_of("灰烬印") == 0 and GameData.volume_of("流风印") == 0,
			"%d / %d" % [GameData.volume_of("灰烬印"), GameData.volume_of("流风印")])

	player.bag.add("兽骨", 10)                      # 10 件 × 2 格 = 20 格
	_check("占用 = 件数 × 单件体积", player.bag.capacity_used() == 20,
			"%d 件兽骨 = %d 格" % [player.bag.count("兽骨"), player.bag.capacity_used()])
	var room_before_m30: int = player.bag.room_left()
	player.bag.add("蕴灵草", 5)
	_check("不同材料按各自的体积扣容积", player.bag.room_left() == room_before_m30 - 5,
			"%d → %d" % [room_before_m30, player.bag.room_left()])

	# 剩 1 格：3 格的矿石放不下，但 1 格的草木放得下 —— 这正是 is_full() 判不出来的那件事
	player.bag.items.clear()
	player.bag.add("玄铁矿", 39)                    # 117 格
	player.bag.add("兽骨", 1)                       # 119 格，剩 1
	_check("剩 1 格：矿石放不下、草木放得下（而且 is_full() 还是 false）",
			not player.bag.fits("玄铁矿") and player.bag.fits("蕴灵草") and not player.bag.is_full(),
			"剩 %d 格" % player.bag.room_left())

	# 整件装不下就一个都不装（不留半件）；最后把包装满，给下面的「捡不动」用例当起点
	player.bag.items.clear()
	var ore_room: int = int(GameData.BAG_CAPACITY) / GameData.volume_of("玄铁矿")
	var put_in: int = player.bag.add("玄铁矿", ore_room + 5)
	_check("整件装不下就一个都不装（不留半件）", put_in == ore_room,
			"放进去 %d，本来最多 %d" % [put_in, ore_room])
	_check("塞满之后 is_full() 为真", player.bag.is_full(), "还剩 %d 格" % player.bag.room_left())
	_check("满了以后一件也放不下", player.bag.add("兽骨", 1) == 0, "竟然放进去了")

	# 7. 背包满 → 拒绝拾取（东西留在地上）+ 拒绝采集（采集点不被消耗）
	var ground = pickups[0] if not pickups.is_empty() else null
	if ground == null:
		_spawn_pickup(player.position + Vector2(10.0, 0.0), "兽骨", 1)
		ground = pickups[0]
	var ground_before: int = pickups.size()
	player.position = ground.position
	_tick_pickups(0.016)
	_check("背包满时掉落物留在地上", pickups.size() == ground_before,
			"%d → %d 件" % [ground_before, pickups.size()])
	_check("背包满时给出提示", bag_full_hint, "没提示")

	var fresh_spot = null
	for g in gathers:
		if is_instance_valid(g) and not g.depleted:
			fresh_spot = g
			break
	player.position = fresh_spot.position
	var got_full: float = try_gather()
	_check("背包满时采集被拒绝", is_zero_approx(got_full), "竟然采到了 %.0f" % got_full)
	_check("背包满时采集点不被白白消耗", not fresh_spot.depleted, "被采空了")

	# 7b. ⭐ M30.1：同类掉落物**就近并成一堆** —— 只减少**节点**，不减少**东西**
	#     为什么要它：背包满时掉落物不会被捡走，而死亡会复活敌人，同一个刷新点被反复打，
	#     那一带就会堆出几十个小方块（又乱，又是每帧都要重绘的活节点）。
	for pk in pickups.duplicate():
		if is_instance_valid(pk):
			pk.queue_free()
	pickups.clear()
	player.bag.items.clear()
	var merge_at := Vector2(100.0, 100.0)
	_spawn_pickup(merge_at, "兽骨", 2)
	_spawn_pickup(merge_at + Vector2(6.0, 0.0), "兽骨", 3)
	_check("同类就近并成一堆", pickups.size() == 1, "堆数 %d" % pickups.size())
	_check("并堆后数量相加（东西一件不少）", int(pickups[0].amount) == 5,
			"amount = %d" % int(pickups[0].amount))

	_spawn_pickup(merge_at, "灵魄", 1)
	_check("不同的东西不并堆", pickups.size() == 2, "堆数 %d" % pickups.size())

	var merge_far := float(GameData.PICKUP["merge_radius"]) + 20.0
	_spawn_pickup(merge_at + Vector2(merge_far, 0.0), "兽骨", 1)
	_check("同类但隔得远就不并（不会被远处的吸走）", pickups.size() == 3, "堆数 %d" % pickups.size())

	_spawn_pickup(merge_at, "流风印", 1)
	_spawn_pickup(merge_at + Vector2(4.0, 0.0), "流风印", 1)
	_check("灵印不参与并堆（它是唯一的，地上要一眼认得出）", pickups.size() == 5,
			"堆数 %d" % pickups.size())

	# ==================== M30.2：背包面板（点选 / 使用 / 丢弃）====================
	# ⭐ 验收：用户那套点法逐条落地 + 规则层的「不浪费」「灵印不能丢」。
	# ⚠️ 面板是 _ready 里**代码建**的节点，自测直接调它的方法 —— 不去模拟鼠标（鼠标那一路已在实机点过）。
	player.bag.items.clear()
	player.bag.add("蕴灵草", 5)
	player.bag.add("兽骨", 3)
	bag_panel.open(player, self)
	_check("背包面板能开（B）", bag_panel.visible, "没开")

	var ent: Array = bag_panel.entries()
	_check("面板列出的就是背包里的东西", ent.size() == 2, "列了 %d 项" % ent.size())
	_check("列表按名字排序（顺序可预期，截图能复现）",
			str(ent[0]["name"]) == "兽骨" and str(ent[1]["name"]) == "蕴灵草",
			"%s / %s" % [str(ent[0]["name"]), str(ent[1]["name"])])

	bag_panel.select_one("兽骨")
	_check("左键点一下 = 选中 1 个", bag_panel.sel_count == 1, "选了 %d" % bag_panel.sel_count)
	bag_panel.select_one("兽骨")
	bag_panel.select_one("兽骨")
	_check("继续点每次 +1（点两下 = 3）", bag_panel.sel_count == 3, "选了 %d" % bag_panel.sel_count)
	bag_panel.select_one("兽骨")
	_check("点到上限就停在全部（不会超过拥有数）", bag_panel.sel_count == 3, "选了 %d" % bag_panel.sel_count)

	bag_panel.select_one("蕴灵草")
	bag_panel.select_all("蕴灵草")
	_check("右键 = 选中全部", bag_panel.sel_count == 5, "选了 %d" % bag_panel.sel_count)
	bag_panel.select_all("蕴灵草")
	_check("再按一次右键 = 取消选择", bag_panel.sel_count == 0, "选了 %d" % bag_panel.sel_count)
	bag_panel.select_one("兽骨")
	_check("换一件东西：选中数从 1 重新开始（不会带过来）", bag_panel.sel_count == 1,
			"选了 %d" % bag_panel.sel_count)

	player.essence = 0.0
	bag_panel.select_all("蕴灵草")
	var used_herb: int = bag_panel.do_use()
	_check("使用蕴灵草：回灵力", player.essence > 0.0, "灵力 %.0f" % player.essence)
	_check("未满就能用：选中的 5 个全都用掉（不再按「够不够回满」卡）", used_herb == 5,
			"用了 %d 个" % used_herb)
	_check("用完之后刚好到上限", is_equal_approx(player.essence, player.essence_max),
			"%.0f / %.0f" % [player.essence, player.essence_max])
	_check("灵力封顶不溢出", player.essence <= player.essence_max, "%.0f" % player.essence)
	_check("超出上限的部分会明说浪费（界面不糊弄）", bag_panel._msg.contains("浪费"), "%s" % bag_panel._msg)
	_check("用光了：选中被清掉（不会留着「选中一件没有的东西」）",
			bag_panel.sel_item == "" and bag_panel.sel_count == 0,
			"sel=%s n=%d" % [bag_panel.sel_item, bag_panel.sel_count])

	# ⭐ M30.3：**用户报过的那个 bug** —— 灵力没满、但「不够回满一次」时也必须能用
	player.bag.add("蕴灵草", 2)
	player.essence = player.essence_max - 5.0
	bag_panel.select_one("蕴灵草")
	var used_partial: int = bag_panel.do_use()
	_check("灵力没满但不够回满一次时**依然能用**（这就是报过的 bug）", used_partial == 1,
			"用了 %d：%s" % [used_partial, bag_panel._msg])
	_check("用完之后灵力才到上限", is_equal_approx(player.essence, player.essence_max),
			"%.0f" % player.essence)

	bag_panel.select_all("蕴灵草")
	var used_full: int = bag_panel.do_use()
	_check("灵力满了就不给用（理由说清）", used_full == 0 and bag_panel._msg.contains("满"),
			"用了 %d：%s" % [used_full, bag_panel._msg])

	bag_panel.select_one("兽骨")
	var used_bone: int = bag_panel.do_use()
	_check("没有使用效果的材料：用不了 + 说清它用于合炼",
			used_bone == 0 and bag_panel._msg.contains("合炼"), "%s" % bag_panel._msg)

	# ⭐ 把选中数确定在 1 再测丢弃：`select_one` 换目标时会从 0 重新开始（继续点才是 +1）
	bag_panel.select_one("蕴灵草")
	bag_panel.select_one("兽骨")
	_check("换回兽骨：选中数是 1（丢弃用例的前置）", bag_panel.sel_count == 1, "选了 %d" % bag_panel.sel_count)
	var lost0: int = bag_panel.do_discard()
	_check("丢弃第一下只是确认（东西还在）", lost0 == 0 and int(player.bag.count("兽骨")) == 3,
			"兽骨 %d：%s" % [int(player.bag.count("兽骨")), bag_panel._msg])
	var lost1: int = bag_panel.do_discard()
	_check("再点一下才真的丢掉", lost1 == 1 and int(player.bag.count("兽骨")) == 2,
			"丢了 %d，剩 %d" % [lost1, int(player.bag.count("兽骨"))])

	# ⭐ M30.3（用户定案）：**灵印也能丢** —— 只有本命印丢不掉
	var discardable_seal := ""
	for nk_r in player.reserve_seals:
		if str(nk_r) != str(GameData.NATAL_SEAL):
			discardable_seal = str(nk_r)
			break
	if discardable_seal == "":
		player.reserve_seals.append("流风印")
		discardable_seal = "流风印"
	bag_panel.select_one(discardable_seal)
	bag_panel.do_discard()                        # 第一下：确认
	var lost_seal: int = bag_panel.do_discard()   # 第二下：真丢
	_check("灵印可以丢弃（M30.3 用户定案）", lost_seal == 1 and not player.has_seal(discardable_seal),
			"丢了 %d，has=%s" % [lost_seal, str(player.has_seal(discardable_seal))])
	_check("丢掉之后它不再出现在背包列表里",
			not bag_panel.entries().any(func(e): return str(e["name"]) == discardable_seal), "还在列表里")
	_check("丢掉之后炼化度也一起清掉（不然拿回来会带着旧进度）",
			is_zero_approx(player.refine_of(discardable_seal)), "%.0f" % player.refine_of(discardable_seal))
	_check("本命印不能丢弃（和「不能当材料」同一条理由）",
			not ItemsScript.can_discard(str(GameData.NATAL_SEAL))
			and ItemsScript.discard_reason(str(GameData.NATAL_SEAL)).contains("本命印"),
			ItemsScript.discard_reason(str(GameData.NATAL_SEAL)))

	bag_panel.close()
	_check("面板能关（关了世界继续跑）", not bag_panel.visible, "还开着")

	# 8. 回溯把地上的东西一并抹掉（§4.3）
	player.bag.items.clear()
	_spawn_pickup(player.position + Vector2(200.0, 0.0), "兽骨", 1)
	var stones_at_anchor: int = int(snapshot.get("stones", 0))
	var bag_at_anchor: int = (snapshot.get("bag", {}) as Dictionary).size()
	player.hp = player.hp_max
	player.take_damage(99999.0)
	_on_rewind_chosen(0)
	_check("回溯把地上的掉落物一并抹掉", pickups.is_empty(), "还剩 %d 件" % pickups.size())
	# ⚠️ M12 改写了这条：用户要求「连境界一起倒流」（严格照 §4.3），
	#    所以灵石与材料也退回锚点值 —— 不再是「地上的没了、背包里的还在」。
	_check("回溯把灵石退回那一帧的值", player.bag.stones == stones_at_anchor,
			"灵石 %d，锚点值 %d" % [player.bag.stones, stones_at_anchor])
	_check("回溯把材料退回那一帧的值", player.bag.items.size() == bag_at_anchor,
			"材料种类 %d，锚点值 %d" % [player.bag.items.size(), bag_at_anchor])

	# ==================== M9：灵印成长与炼化 ====================
	# ⭐ 十等 = 等级（升级靠合炼）；炼化度 = 这一枚印养得多熟，满 100% 解锁永久基础属性。

	_test_loadout()
	player.seal_refine.clear()
	player.refresh_limits()
	player.bag.items.clear()
	player.bag.stones = 0
	player.bag.add("蕴灵草", 20)
	player.bag.add("兽骨", 20)
	player.position = spawn_point

	_check("十等表有十级", GameData.RANKS.size() == 10, "实际 %d 级" % GameData.RANKS.size())
	_check("一等叫凡印、二等叫精印",
			str(GameData.RANKS[1]) == "凡印" and str(GameData.RANKS[2]) == "精印",
			"%s / %s" % [GameData.RANKS[1], GameData.RANKS[2]])
	var ranks_ok := true
	for key in GameData.SEALS:
		if not GameData.RANKS.has(int(GameData.SEALS[key]["rank"])):
			ranks_ok = false
	_check("四枚印的等级都在十等表里", ranks_ok, "有印的 rank 不在表里")
	_check("惊雷印是二等精印（数据表 rank = 2）",
			int(GameData.SEALS["惊雷印"]["rank"]) == 2, "实际 %d" % int(GameData.SEALS["惊雷印"]["rank"]))
	_check("刚重置时炼化度是 0", is_zero_approx(player.refine_of("灰烬印")),
			"%.1f" % player.refine_of("灰烬印"))

	# 1. ⭐ 炼化只能靠「花灵力炼化」或「投灵材」—— 显化本身不再涨
	#    （新语义：炼化是**使用前提**，"不能用还怎么靠用变熟"自相矛盾）
	player.seal_refine["灰烬印"] = 100.0        # 先炼满 —— 炼化是使用前提
	player.essence = player.essence_max
	var refine_before_m9: float = player.refine_of("灰烬印")
	player.toggle_slot(0)
	_check("显化不再涨炼化度（炼化是使用前提，不是用得越多越熟）",
			is_equal_approx(player.refine_of("灰烬印"), refine_before_m9),
			"%.1f → %.1f" % [refine_before_m9, player.refine_of("灰烬印")])
	player.toggle_slot(0)
	player.seal_refine["灰烬印"] = 10.0         # ⚠️ 退回 10：给下面「炼化」留出可涨的空间
	player.essence = player.essence_max

	# 2. 炼化：⭐ **只吃灵力**（M30.3 用户定案：「炼化灵印需要消耗灵气而不是消耗材料」）
	seal_panel.open(player)
	seal_panel.pick_seal(0)
	_check("面板选印后进入炼化步", seal_panel.step == 1 and seal_panel.current_seal() == "灰烬印",
			"step=%d seal=%s" % [seal_panel.step, seal_panel.current_seal()])
	_check("背包列表里仍然看得到材料（只是不再用于炼化）",
			seal_panel.material_list().has("蕴灵草"), str(seal_panel.material_list()))
	var grass_before: int = player.bag.count("蕴灵草")
	var bones_before_m9: int = player.bag.count("兽骨")
	var ess_before_press: float = player.essence
	var gained: float = seal_panel.do_refine()
	_check("点「炼化」：炼化度 +press_gain（按数据表算，不写死）",
			is_equal_approx(gained, float(GameData.REFINE["press_gain"])), "涨了 %.1f" % gained)
	_check("点「炼化」：扣的是**灵力**（按 press_cost）",
			is_equal_approx(ess_before_press - player.essence, float(GameData.REFINE["press_cost"])),
			"灵力 %.0f → %.0f" % [ess_before_press, player.essence])
	_check("炼化**不再消耗材料**（蕴灵草一个没少）", player.bag.count("蕴灵草") == grass_before,
			"%d → %d" % [grass_before, player.bag.count("蕴灵草")])
	_check("炼化也不再消耗别的材料（兽骨一个没少）", player.bag.count("兽骨") == bones_before_m9,
			"%d → %d" % [bones_before_m9, player.bag.count("兽骨")])

	# 3. 封顶 100%，不溢出；灵力不够就炼不动
	player.add_refine("灰烬印", 999.0)
	_check("炼化度封顶在 100%", is_equal_approx(player.refine_of("灰烬印"), 100.0),
			"%.1f" % player.refine_of("灰烬印"))
	_check("炼满之后再炼不涨", is_zero_approx(player.add_refine("灰烬印", 50.0)), "又涨了")
	_check("炼满之后炼化按钮是灰的（点不动）", not seal_panel.can_refine_now(), "按钮还亮着")
	player.seal_refine["灰烬印"] = 20.0
	player.essence = 0.0
	_check("灵力不够时点炼化被拒（且灵力一点没扣）",
			is_zero_approx(seal_panel.do_refine()) and is_zero_approx(player.essence),
			"灵力 %.0f：%s" % [player.essence, seal_panel._msg])
	player.essence = player.essence_max
	player.add_refine("灰烬印", 999.0)          # 还回炼满（下面第 4 段要用）

	# 4. 满 100% → 基础属性**永久**生效
	_check("灰烬印炼满：普攻伤害 +4（不显化也在）",
			is_equal_approx(player.attack_damage_bonus(), 4.0), "%.1f" % player.attack_damage_bonus())
	player.essence = player.essence_max
	player.toggle_slot(0)
	_check("显化期被动与炼化基础属性可叠（6 + 4 = 10）",
			is_equal_approx(player.attack_damage_bonus(), 10.0), "%.1f" % player.attack_damage_bonus())
	player.toggle_slot(0)
	_check("收回后只剩炼化给的那 4 点",
			is_equal_approx(player.attack_damage_bonus(), 4.0), "%.1f" % player.attack_damage_bonus())

	var hp_before_m9: float = player.hp_max
	player.add_refine("玄甲印", 100.0)
	_check("玄甲印炼满：气血上限 +24（当场生效）",
			is_equal_approx(player.hp_max, hp_before_m9 + 24.0), "%.1f" % player.hp_max)
	player.add_refine("磐石印", 100.0)
	_check("磐石印炼满：灵力上限 +15（100 → 115）",
			is_equal_approx(player.essence_max, 115.0), "%.1f" % player.essence_max)
	player.add_refine("惊雷印", 100.0)
	_check("惊雷印炼满：普攻冷却 ×0.90（永久乘算）",
			is_equal_approx(player.attack_cooldown_mult(), 0.90), "%.3f" % player.attack_cooldown_mult())
	_check("四枚印全部炼满", player.refined_seals().size() == 4,
			"实际 %d 枚" % player.refined_seals().size())
	_check("没炼过的印炼化度是 0", is_zero_approx(player.refine_of("云雨印")),
			"%.1f" % player.refine_of("云雨印"))
	_check("没炼过的印不算炼满", not player.is_refined("云雨印"), "竟然算炼满")

	# 5. Tab 开关：面板一来就把时间冻住
	seal_panel.close()
	toggle_seal_panel()
	_check("Tab 打开命窍面板并暂停时间",
			seal_panel.visible and get_tree().paused,
			"visible=%s paused=%s" % [str(seal_panel.visible), str(get_tree().paused)])
	toggle_seal_panel()
	_check("再按一次 Tab 关闭并恢复时间",
			not seal_panel.visible and not get_tree().paused,
			"visible=%s paused=%s" % [str(seal_panel.visible), str(get_tree().paused)])

	# ==================== M10：灵师与强夺 ====================
	# ⭐ 验收：抢来的印要炼化才能用（M20 起炼化满就有被动）；容量满时无法再夺；活跃 / 备用可以换。

	seal_panel.close()
	_test_loadout()
	player.reserve_seals.clear()
	player.seized_seals.clear()
	player.seal_refine.clear()
	player.refresh_limits()
	player.position = spawn_point
	player.hp = player.hp_max
	player.essence = player.essence_max

	# 1. 灵师按数据表出场
	var mages: Array = []
	for e in enemies:
		if is_instance_valid(e) and e.is_caster():
			mages.append(e)
	_check("场上有 3 名灵师", mages.size() == 3, "实际 %d 名" % mages.size())
	var mage = mages[0]
	_check("灵师带着一枚印", str(mage.carries) != "", "它身上什么都没有")
	_check("它带的印存在于数据表", GameData.SEALS.has(str(mage.carries)), str(mage.carries))
	_check("猛兽与智谋没被认成灵师",
			not enemies[0].is_caster() and not enemies[1].is_caster(), "认错了")

	# 2. 施法机制：预警 → 落地；站圈里挨打，走出圈躲掉
	for i in range(player.slot_summoned.size()):
		if player.slot_summoned[i] != null:
			player.toggle_slot(i)
	player.hp = player.hp_max
	mage.hp = mage.hp_max
	mage.position = player.position + Vector2(120.0, 0.0)
	var steps := 0
	while not mage.is_casting() and steps < 40:
		mage.step_ai(0.1)
		steps += 1
	_check("灵师进入距离后会开始酝酿", mage.is_casting(), "喂了 %d 帧还没动静" % steps)
	var hp_before_cast: float = player.hp
	player.position = mage.cast_target()          # 站在圈里不动
	mage.step_ai(1.0)                             # 预警烧完，雷落地
	_check("站在预警圈里会挨打", player.hp < hp_before_cast,
			"血 %.0f → %.0f" % [hp_before_cast, player.hp])

	player.hp = player.hp_max
	mage.position = player.position + Vector2(120.0, 0.0)
	steps = 0
	while not mage.is_casting() and steps < 40:
		mage.step_ai(0.1)
		steps += 1
	player.position = mage.cast_target() + Vector2(220.0, 0.0)   # 走开
	mage.step_ai(1.0)
	_check("走出预警圈就躲掉了（预警是给玩家的）",
			is_equal_approx(player.hp, player.hp_max), "血 %.0f / %.0f" % [player.hp, player.hp_max])

	# 3. 打死灵师 → 掉出它那枚印
	var carried := str(mage.carries)
	mage.take_damage(99999.0)
	var ground_seal = null
	for pk in pickups:
		if is_instance_valid(pk) and pk.is_seal():
			ground_seal = pk
			break
	_check("灵师死后地上掉出一枚灵印", ground_seal != null, "地上只有材料")
	_check("掉出来的就是它身上那枚",
			ground_seal != null and str(ground_seal.item) == carried,
			"期望 %s，实际 %s" % [carried, "-" if ground_seal == null else str(ground_seal.item)])

	# 4. 走过去强夺 → 进备用 + 打上「抢来的」
	var owned_before: int = player.owned_count()
	player.position = ground_seal.position
	_tick_pickups(0.016)
	_check("强夺后印进了备用", player.reserve_seals.has(carried), str(player.reserve_seals))
	_check("强夺后拥有数 +1", player.owned_count() == owned_before + 1,
			"%d → %d" % [owned_before, player.owned_count()])
	_check("抢来的印被标记为契合度归零", player.seized_seals.has(carried), str(player.seized_seals))

	# 5. ⭐ M20（用户定案）：**所有灵印炼化满都享受被动** —— "抢来的没被动"这条规则取消了。
	#    改成：抢来的印**一样要炼化**（那才是门槛），炼满之后和养出来的没区别。
	seal_panel.open(player)
	seal_panel.pick_seal(3)
	seal_panel.swap(player.reserve_seals.find(carried))
	_check("换印：备用那枚上了活跃槽 4", str(player.slot_seal[3]) == carried,
			"槽 4 = %s" % player.slot_seal[3])
	_check("换印不改变拥有总数", player.owned_count() == owned_before + 1,
			"实际 %d" % player.owned_count())
	player.essence = player.essence_max
	_check("抢来的印还没炼化 → 门槛挡着，用不了（不是「能用但没被动」）",
			not bool(player.toggle_slot(3)["ok"]), "竟然显化成功了")
	player.seal_refine[carried] = float(GameData.REFINE["max"])
	player.essence = player.essence_max
	_check("抢来的印炼化满 → 能显化", bool(player.toggle_slot(3)["ok"]), "还是不能用")
	_check("抢来的印炼化满 → 被动照常算数（M20 新规则）",
			player.passive_works(carried) and player.slot_summoned[3] != null,
			"passive_works=%s summoned=%s" % [str(player.passive_works(carried)),
					str(player.slot_summoned[3] != null)])
	player.toggle_slot(3)
	player.essence = player.essence_max
	player.toggle_slot(1)                          # 对照：玄甲印 受伤 ×0.70
	player.add_refine("玄甲印", 100.0)      # ⭐ 炼化是使用前提：先炼满才谈得上被动
	player.toggle_slot(1)
	_check("对照：自己养的印被动照常生效",
			is_equal_approx(player.damage_taken_mult(), 0.70),
			"受伤乘数 = %.2f（期望 0.70）" % player.damage_taken_mult())
	player.toggle_slot(1)

	# 6. ⭐ M29.5：命窍满了**不再拿不下** —— 装不进命窍的印进**背包**（收藏无上限）
	#    ⚠️ 别写死印名 —— 哪个灵师排在前面是数据表决定的
	while player.can_seize():
		var got_one := false
		for key in GameData.SEALS:
			if not player.has_seal(str(key)):
				player.seize(str(key))
				got_one = true
				break
		if not got_one:
			break
	_check("命窍装满（容量 %d）" % int(GameData.SEAL_CAPACITY),
			player.aperture_count() == int(GameData.SEAL_CAPACITY) and not player.can_seize(),
			"命窍 %d / %d" % [player.aperture_count(), player.capacity()])
	var leftover := ""
	for key in GameData.SEALS:
		if not player.has_seal(str(key)):
			leftover = str(key)
			break
	_check("场上还有一枚没到手的印（下面的用例靠它）", leftover != "", "七枚印都在手上了")
	if leftover != "":
		# ⭐ 这次改的核心：命窍满了，**地上的印照样被捡走**（以前会留在原地 + 提示「命窍已满」）
		_spawn_pickup(player.position + Vector2(10.0, 0.0), leftover, 1)
		var last_seal = pickups[pickups.size() - 1]
		seize_dup_hint = false
		_tick_pickups(0.016)
		_check("命窍满时地上的印照样被捡走（不再留在原地）", not pickups.has(last_seal), "还留在地上")
		_check("捡到的那枚落进了背包", player.bag_seals.has(leftover), str(player.bag_seals))
		_check("命窍枚数没被撑破（容量仍然是门槛）",
				player.aperture_count() == int(GameData.SEAL_CAPACITY),
				"命窍被撑到 %d" % player.aperture_count())
		_check("背包里的印也算「拥有」", player.has_seal(leftover), "has_seal 不认识它")
		_check("捡一枚装不进命窍的印不会误报「已满」", not seize_dup_hint, "还是报了已满")

	# 7. 换印：备用 ↔ 活跃（换下来的回备用）
	seal_panel.close()
	var active_now := str(player.slot_seal[3])
	seal_panel.open(player)
	seal_panel.pick_seal(3)
	seal_panel.swap(0)
	_check("换印后槽 4 换成了另一枚", str(player.slot_seal[3]) != active_now,
			"还是 %s" % active_now)
	_check("被换下来的印回到备用", player.reserve_seals.has(active_now), str(player.reserve_seals))
	_check("换来换去不改变命窍里的枚数", player.aperture_count() == int(GameData.SEAL_CAPACITY),
			"实际 %d" % player.aperture_count())
	seal_panel.close()

	# 7b. ⭐ M29.5：**背包里的印**能直接换上活跃槽（换下来的那枚回背包）
	if not player.bag_seals.is_empty():
		var bag_name := str(player.bag_seals[0])
		var slot_before := str(player.slot_seal[3])
		seal_panel.open(player)
		seal_panel.pick_seal(3)
		seal_panel.select_bag_seal(bag_name)
		_check("选中背包里的印后「换上」按钮可用", seal_panel.can_swap_selected(), "按钮是灰的")
		_check("换上成功", seal_panel.do_swap_selected(), "换不上")
		_check("活跃槽 4 现在是背包里那枚", str(player.slot_seal[3]) == bag_name,
				"槽 4 是 %s" % player.slot_seal[3])
		_check("被换下来的那枚回了背包", player.bag_seals.has(slot_before), str(player.bag_seals))
		_check("命窍枚数仍然不变", player.aperture_count() == int(GameData.SEAL_CAPACITY),
				"命窍 %d" % player.aperture_count())
		seal_panel.close()

	# 8. ⚠️ M28：原来这里测「回溯把抢来的印也带走」（时印的夺印规则）。
	#    回溯移除后死亡不碰命窍与备用，那条规则随功能暂停 —— 这里只验死亡本身能跑、不夺印。
	player.hp = player.hp_max
	player.take_damage(99999.0)
	_check("死亡不夺走灵印（时印的夺印规则已随回溯暂停）", player.owned_count() >= 2,
			"拥有 %d 枚" % player.owned_count())

	# ==================== M11：怪物丰富与掉落 ====================
	# ⭐ 验收：每种原型都有验收断言与掉落表；一眼能分辨原型。

	_check("敌人有 4 种原型", GameData.ENEMY.size() == 4, "实际 %d 种" % GameData.ENEMY.size())
	var shape_ok := true
	for key in GameData.ENEMY:
		var bh := str(GameData.ENEMY[key].get("behavior", ""))
		if bh == "" or not GameData.SHAPES.has(bh):
			shape_ok = false
	_check("每种原型都有 behavior，且都在形状表里", shape_ok, "有原型没形状")
	var drop_ok := true
	for key in GameData.ENEMY:
		if not GameData.ENEMY_DROPS.has(str(key)):
			drop_ok = false
	_check("每种原型都有掉落表", drop_ok, "有原型没掉落表")
	_check("形状表有四种形状", GameData.SHAPES.size() == 4, "实际 %d 种" % GameData.SHAPES.size())

	# 复位
	for i in range(player.slot_summoned.size()):
		if player.slot_summoned[i] != null:
			player.toggle_slot(i)
	player.hp = player.hp_max
	player.position = spawn_point

	# 1. 蛮兽（冲锋型）：蓄力 → 锁定方向 → 冲刺
	var charger = null
	for e in enemies:
		if is_instance_valid(e) and e.behavior() == "charger":
			charger = e
			break
	_check("场上有蛮兽（冲锋型）", charger != null, "一只都没有")
	charger.hp = charger.hp_max
	charger.position = player.position + Vector2(80.0, 0.0)      # 150 蓄力距离内 + 冲得到
	charger._cd = 0.0
	var csteps := 0
	while not charger.is_casting() and csteps < 60:
		charger.step_ai(0.1)
		csteps += 1
	_check("蛮兽进入距离后会开始蓄力", charger.is_casting(), "喂了 %d 帧还没蓄力" % csteps)

	var hp_before_charge: float = player.hp
	while charger.is_casting():
		charger.step_ai(0.05)
	_check("蓄力结束后进入冲刺", charger.is_charging(), "没冲起来")
	for k in range(14):
		charger.step_ai(0.05)
	_check("站着不动会被撞到", player.hp < hp_before_charge,
			"血 %.0f → %.0f" % [hp_before_charge, player.hp])

	# 横着闪开：方向在冲刺开始那一刻就锁死了
	player.hp = player.hp_max
	charger.position = player.position + Vector2(80.0, 0.0)
	charger._cd = 0.0
	charger._warn = 0.0
	charger._charge_t = 0.0
	csteps = 0
	while not charger.is_casting() and csteps < 60:
		charger.step_ai(0.05)
		csteps += 1
	while charger.is_casting():
		charger.step_ai(0.05)
	player.position = charger.position + Vector2(0.0, 110.0)   # 横着闪（与冲刺距离同量级）
	for k in range(14):
		charger.step_ai(0.05)
	_check("横着闪开就不会被撞到（方向已锁定）",
			is_equal_approx(player.hp, player.hp_max), "血 %.0f / %.0f" % [player.hp, player.hp_max])

	# 2. 精英：同一套 AI，只是加档
	var elites: Array = []
	for e in enemies:
		if is_instance_valid(e) and e.elite:
			elites.append(e)
	_check("场上有 2 只精英", elites.size() == 2, "实际 %d 只" % elites.size())
	var el = elites[0]
	var base_hp := float(GameData.ENEMY[el.archetype]["hp_max"])
	_check("精英血量 = 原型 × 3", is_equal_approx(el.hp_max, base_hp * 3.0),
			"%.0f（原型 %.0f）" % [el.hp_max, base_hp])
	_check("精英体型更大", el.radius_value() > float(GameData.ENEMY[el.archetype]["radius"]),
			"%.1f" % el.radius_value())
	_check("精英伤害更高", el.damage_value() > float(GameData.ENEMY[el.archetype]["attack_damage"]),
			"%.1f" % el.damage_value())
	_check("精英用的还是同一个原型（不是新原型）", GameData.ENEMY.has(el.archetype), el.archetype)

	# 3. 精英掉落：原型 × drop_mult + 额外高级辅材
	# ⚠️ M30.1：**按数量断言，不要按地上的节点数** —— 同类掉落物会就近并堆，
	#    而 `ELITE.bonus_drop` 恰好就是「灵魄」，智谋的掉落表里本来也有灵魄：
	#    同一次掉落里就有两件同名的（相距 36px < merge_radius）→ 并成一堆，节点数必然少于条目数。
	#    ⭐ 要验的从来是「东西一件不少」；地上剩几个方块是表现，不是规则。（踩过：这条原来是数节点的）
	# ⚠️ 仍然先清空地面：`spawned` 靠「新加的节点」，若新掉落并进了**旧堆**，那件东西就不在 spawned 里。
	for pk0 in pickups.duplicate():
		if is_instance_valid(pk0):
			pk0.queue_free()
	pickups.clear()
	var before_cnt: int = pickups.size()
	el.take_damage(99999.0)
	var spawned: Array = pickups.slice(before_cnt)
	# ⚠️ 名字别叫 got —— `_run_selftest` 是个两千行的函数，早年已经用过这个名字（踩过：Parser Error）
	var drop_totals := {}                      # 名字 -> 地上的总量（并堆也一起算进去）
	for pk in spawned:
		if is_instance_valid(pk):
			var ik := str(pk.item)
			drop_totals[ik] = int(drop_totals.get(ik, 0)) + int(pk.amount)
	_check("精英掉落一件不少（原型 ×3）：兽骨 3 / 灵石 15",
			int(drop_totals.get("兽骨", 0)) == 3 and int(drop_totals.get(GameData.CURRENCY, 0)) == 15,
			str(drop_totals))
	_check("精英的 bonus_drop（灵魄）叠在掉落之上：3 本体 + 1 奖励 = 4",
			int(drop_totals.get("灵魄", 0)) == 4, "灵魄 %d" % int(drop_totals.get("灵魄", 0)))
	var lingpo_piles: Array = spawned.filter(func(q): return is_instance_valid(q) and str(q.item) == "灵魄")
	_check("同名的两件灵魄并成了一堆（M30.1 就地钉住）", lingpo_piles.size() == 1,
			"灵魄堆数 %d" % lingpo_piles.size())
	var carried_dropped := false
	for pk2 in spawned:
		if is_instance_valid(pk2) and GameData.SEALS.has(str(pk2.item)):
			carried_dropped = true
	_check("精英带着的那枚印也掉出来了（惊雷 / 磐石的唯一来源）",
			carried_dropped, "没掉印")

	# 4. 精英身份能扛过回溯（快照要记住它）
	# ⚠️ 期望值按「快照那一刻还活着的数量」算 —— 上面刚打死一只，快照里就只有一只
	var elites_alive := 0
	for e in enemies:
		if is_instance_valid(e) and e.elite:
			elites_alive += 1
	take_snapshot()
	player.hp = player.hp_max
	player.take_damage(99999.0)
	_on_rewind_chosen(0)
	var elites_after := 0
	for e in enemies:
		if is_instance_valid(e) and e.elite:
			elites_after += 1
	_check("回溯后精英还是精英（快照记住了）", elites_after == elites_alive,
			"期望 %d 只，实际 %d 只" % [elites_alive, elites_after])

	# ==================== M12：成长、锚点与存档 ====================
	# ⭐ 验收：攒满 → 突破 → 属性与容量变化；设锚 → 死亡回新锚点；关掉重开进度还在。

	_test_loadout()
	player.seal_refine.clear()          # 清掉炼化，免得基础属性加成混进境界数值里
	player.bag.items.clear()
	player.bag.stones = 0
	player.realm = 1
	player.refresh_limits()
	player.cultivation = 0.0
	player.position = spawn_point
	player.hp = player.hp_max
	player.essence = player.essence_max

	_check("境界表有 5 级", GameData.REALMS.size() == 5, "实际 %d 级" % GameData.REALMS.size())
	_check("开局是炼气（境界 1）", player.realm == 1 and player.realm_name() == "炼气",
			"%s（%d）" % [player.realm_name(), player.realm])
	_check("气血 / 灵力上限来自境界表",
			is_equal_approx(player.hp_max, 120.0) and is_equal_approx(player.essence_max, 100.0),
			"%.0f / %.0f" % [player.hp_max, player.essence_max])

	# 1. 突破条件：**修为攒满**（地点不限 —— 用户改的规则）
	player.cultivation = 0.0
	_check("修为没攒满时不能突破",
			not player.can_breakthrough() and not try_breakthrough(), "竟然突破了")
	player.cultivation = player.cultivation_max()
	_check("修为攒满就能突破", player.can_breakthrough(), "不行")
	# ⭐ 用户改的规则：**任意位置都能突破**（不再要求回锚点）
	var anchor_keep_bt: Vector2 = spawn_point
	player.position = spawn_point + Vector2(400.0, 400.0)
	_check("任意位置都能突破（不再要求回锚点）", try_breakthrough(), "突破失败")
	_check("突破**不移动锚点**（不钉锚，复活点照旧）",
			spawn_point.is_equal_approx(anchor_keep_bt), str(spawn_point))
	player.position = spawn_point
	_check("境界 +1（炼气 → 筑基）", player.realm == 2 and player.realm_name() == "筑基",
			"%s（%d）" % [player.realm_name(), player.realm])
	_check("突破后气血上限按新境界算（120 → 150）", is_equal_approx(player.hp_max, 150.0),
			"%.0f" % player.hp_max)
	_check("突破后灵力上限按新境界算（100 → 160）", is_equal_approx(player.essence_max, 160.0),
			"%.0f" % player.essence_max)
	_check("突破后命窍容量 +1（6 → 7）", player.capacity() == 7, "容量 %d" % player.capacity())
	_check("突破后移速按新境界算（%.0f → %.0f）" % [GameData.REALMS[1]["speed"], GameData.REALMS[2]["speed"]],
			is_equal_approx(player.move_speed(), float(GameData.REALMS[2]["speed"]) + player.sub_bonus("speed")),
			"%.0f" % player.move_speed())
	_check("突破把修为归零", is_zero_approx(player.cultivation), "修为 %.0f" % player.cultivation)
	_check("突破后灵力回满（新境界的上限）",
			is_equal_approx(player.essence, player.essence_max),
			"灵力 %.0f / %.0f" % [player.essence, player.essence_max])

	player.realm = player.max_realm()
	player.refresh_limits()
	player.cultivation = player.cultivation_max()
	_check("到顶了就不能再突破", not player.can_breakthrough(), "还能突破")
	player.realm = 2
	player.refresh_limits()

	# 3. 存档：⚠️ M19 起没有「设锚」了 —— 存档是**定期自动**的（save_now = 拍快照 + 拍帧 + 写盘）
	var old_anchor: Vector2 = spawn_point
	var new_anchor := Vector2(1800.0, 1000.0)
	player.position = new_anchor
	take_snapshot()                              # 钉住这一刻（自动存档做的就是这件事）
	_check("存档不会移动出生点（锚点机制已移除）", spawn_point.is_equal_approx(old_anchor),
			"出生点被挪到了 %s" % str(spawn_point))
	player.hp = player.hp_max
	player.position = Vector2(300.0, 300.0)
	player.take_damage(99999.0)
	_on_rewind_chosen(0)
	# ⚠️ M28：原来断言「死亡后退到时间线那一帧的位置」—— 回溯移除后统一回出生点。
	_check("死亡后回到出生点（不再有「退到某一帧」这回事）", player.position.is_equal_approx(spawn_point),
			str(player.position))

	# 4. 境界也随回溯倒流（用户决定：严格照 §4.3）
	player.realm = 3
	player.refresh_limits()
	player.essence = player.essence_max
	take_snapshot()                              # 在境界 3 钉住这一刻
	player.realm = 4
	player.refresh_limits()
	player.hp = player.hp_max
	player.take_damage(99999.0)
	_on_rewind_chosen(0)
	_check("境界随回溯倒流（4 → 3）", player.realm == 3, "境界 %d" % player.realm)
	_check("上限跟着退回锚点时的值（金丹基础 + 当时的小境界 + 炼化满的基础加成）",
			is_equal_approx(player.hp_max, 180.0 + player.sub_bonus("hp") + player.base_bonus_add("hp_max")),
			"%.0f（基础 180 + 小境界 %.0f + 炼化 %.0f）" % [player.hp_max, player.sub_bonus("hp"),
					player.base_bonus_add("hp_max")])

	# 5. 击败精英：⚠️ M19 起**不再移动任何东西**（原来这里是"自动钉锚"）
	var spawn_before_elite: Vector2 = spawn_point
	var elite3 = null
	for e in enemies:
		if is_instance_valid(e) and e.elite:
			elite3 = e
			break
	_check("场上还有精英可打", elite3 != null, "一只都不剩了")
	player.position = Vector2(700.0, 900.0)
	elite3.position = player.position + Vector2(24.0, 0.0)
	elite3.take_damage(99999.0)
	_check("击败精英不再移动出生点（钉锚已移除）", spawn_point.is_equal_approx(spawn_before_elite),
			"出生点被挪到了 %s" % str(spawn_point))

	# 6. 存档：序列化是纯函数，往返必须一致
	var saved: Dictionary = SaveGameScript.to_dict(self)
	_check("存档里有背包里的印（收藏无上限）", saved.has("bag_seals"), str(saved.keys()))
	_check("存档里有出生点 / 境界 / 命窍 / 背包",
			saved.has("anchor") and saved.has("realm") and saved.has("slots") and saved.has("bag"),
			str(saved.keys()))
	var keep_realm: int = player.realm
	var keep_anchor: Vector2 = spawn_point
	player.realm = 1
	spawn_point = Vector2.ZERO
	var loaded: bool = SaveGameScript.from_dict(self, saved)
	_check("读档成功", loaded, "读档失败")
	_check("读档把境界读回来了", player.realm == keep_realm,
			"%d，期望 %d" % [player.realm, keep_realm])
	_check("读档把出生点读回来了", spawn_point.is_equal_approx(keep_anchor), str(spawn_point))
	_check("读档拒绝槽位数不符的存档",
			not SaveGameScript.from_dict(self, {"anchor": [0.0, 0.0], "slots": ["只有一枚"]}),
			"竟然收下了")
	_check("读档拒绝缺字段的存档（没有出生点的存档不认）",
			not SaveGameScript.from_dict(self, {"realm": 2}), "竟然收下了")
	_check("自测模式下绝不写盘", not save_game(), "竟然写了盘")

	# 7. 真的写一次盘（写到**临时文件**，不碰真存档）—— 验 JSON 往返与 FileAccess
	var tmp := "user://_selftest_save.json"
	_check("存档能写到磁盘", SaveGameScript.save_to(tmp, self), "写盘失败")
	_check("磁盘上确实有这个文件", FileAccess.file_exists(tmp), "文件不在")
	var readback: String = ""
	var rf := FileAccess.open(tmp, FileAccess.READ)
	if rf != null:
		readback = rf.get_as_text()
		rf.close()
	_check("写出来的是人能读的 JSON（含 anchor / realm）",
			readback.contains("\"anchor\"") and readback.contains("\"realm\""),
			"内容 %.60s" % readback)
	player.realm = 1
	var disk_ok: bool = SaveGameScript.load_from(tmp, self)
	_check("能从磁盘读回来", disk_ok, "读盘失败")
	_check("读回来的是存档里的境界", player.realm == keep_realm,
			"%d，期望 %d" % [player.realm, keep_realm])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	_check("临时存档已清理", not FileAccess.file_exists(tmp), "还留着")

	# ==================== M13：合炼（规则层）====================
	# ⭐ 界面不在这一批 —— 这里验的是「能不能炼 / 成功率多少 / 失败会失去什么」。

	_test_loadout()
	player.seal_rank.clear()
	player.seized_seals.clear()
	player.reserve_seals.clear()
	player.bag.items.clear()
	player.essence = player.essence_max
	player.hp = player.hp_max
	player.position = spawn_point

	_check("配方表 7 条（4 升阶 + 3 合成）", GameData.RECIPES.size() == 7,
			"实际 %d 条" % GameData.RECIPES.size())
	var mode_ok := true
	for r in GameData.RECIPES:
		if str(r["mode"]) != "upgrade" and str(r["mode"]) != "craft":
			mode_ok = false
	_check("每条配方的 mode 都合法", mode_ok, "有配方 mode 不对")

	# 1. 材料不够时说得清缺什么
	var r_up: Dictionary = GameData.RECIPES[0]          # 灰烬印 → 二等（赤炎花×2 + 地火芯×1）
	_check("没材料时做不了这条配方", not SmithScript.can_afford(self, r_up), "竟然能做")
	var miss: Array = SmithScript.missing(self, r_up)
	var said_mat := false
	for s in miss:
		if str(s).contains("赤炎花"):
			said_mat = true
	_check("缺料说明里点名了缺哪种材料", said_mat, str(miss))
	player.bag.add("赤炎花", 5)
	player.bag.add("地火芯", 3)
	_check("补上材料后就能做了", SmithScript.can_afford(self, r_up),
			str(SmithScript.missing(self, r_up)))

	# 2. 成功率公式（手算对照，不从代码里读回来）
	_check("升阶成功率 = 50 + 2种辅材×5 − 1等×10 = 50", is_equal_approx(SmithScript.chance(self, r_up), 50.0),
			"实际 %.1f" % SmithScript.chance(self, r_up))
	var r_craft: Dictionary = GameData.RECIPES[4]      # 玄甲 + 惊雷 → 辉光（雷纹石×2 + 灵魄×1）
	_check("合成成功率 = 50 + 2×5 + 1灵魄×10 − 1等×10 = 60",
			is_equal_approx(SmithScript.chance(self, r_craft), 60.0),
			"实际 %.1f" % SmithScript.chance(self, r_craft))
	var plan_up: Dictionary = SmithScript.plan(self, r_up, true, 1, 0.99)   # 加料 +12
	_check("加料把成功率抬起来（50 → 62）", is_equal_approx(float(plan_up["chance"]), 62.0),
			"实际 %.1f" % float(plan_up["chance"]))
	var plan_dn: Dictionary = SmithScript.plan(self, r_up, true, 2, 0.99)   # 减料 −10
	_check("减料把成功率压下去（50 → 40）", is_equal_approx(float(plan_dn["chance"]), 40.0),
			"实际 %.1f" % float(plan_dn["chance"]))

	# 3. 火候：绿区判定 + 失误必失败
	_check("指针在正中算命中", SmithScript.in_green(0.5), "没命中")
	_check("指针在绿区内算命中", SmithScript.in_green(0.42), "没命中")
	_check("指针出了绿区算失误", not SmithScript.in_green(0.30), "竟然命中")
	var miss_plan: Dictionary = SmithScript.plan(self, r_up, false, 1, 0.0)
	_check("火候失误必失败（运气再好也没用）",
			not bool(miss_plan["success"]) and str(miss_plan["reason"]) == "pointer_miss",
			str(miss_plan))
	_check("随机数小就成功", bool(SmithScript.plan(self, r_up, true, 0, 0.10)["success"]), "竟然失败")
	_check("随机数大就失败", not bool(SmithScript.plan(self, r_up, true, 0, 0.90)["success"]), "竟然成功")

	# 4. 升阶：成功加等级、失败只赔辅材
	var rank_before: int = player.rank_of("灰烬印")
	_check("升阶前是数据表里的基础等级", rank_before == 1, "实际 %d" % rank_before)
	var rep: Dictionary = SmithScript.apply(self, r_up, true)
	_check("升阶成功：等级 +1", player.rank_of("灰烬印") == rank_before + 1,
			"实际 %d" % player.rank_of("灰烬印"))
	_check("升阶成功：辅材按数量被消耗",
			player.bag.count("赤炎花") == 3 and player.bag.count("地火芯") == 2,
			"赤炎花 %d / 地火芯 %d" % [player.bag.count("赤炎花"), player.bag.count("地火芯")])
	_check("升阶成功：印还在（§3.3 升阶不吃印）", player.has_seal("灰烬印"), "印没了")
	_check("升阶扣灵力", player.essence < player.essence_max, "灵力没扣")
	_check("升阶后印的血量系数变大（1.25）",
			is_equal_approx(player.seal_hp_scale_of("灰烬印"), 1.25),
			"%.2f" % player.seal_hp_scale_of("灰烬印"))
	_check("升阶后招式系数变大（1.20）",
			is_equal_approx(player.skill_scale_of("灰烬印"), 1.20),
			"%.2f" % player.skill_scale_of("灰烬印"))
	player.essence = player.essence_max
	player.toggle_slot(0)
	var up_seal = player.slot_summoned[0]
	_check("升阶后的印显化时血量按系数放大（40 → 50）",
			up_seal != null and is_equal_approx(up_seal.hp_max, 50.0),
			"%.1f" % (0.0 if up_seal == null else up_seal.hp_max))
	player.toggle_slot(0)

	var r_up2: Dictionary = GameData.RECIPES[1]        # 玄甲印 升阶（玄铁矿×3）
	player.bag.add("玄铁矿", 5)
	player.essence = player.essence_max
	var rk: int = player.rank_of("玄甲印")
	SmithScript.apply(self, r_up2, false)
	_check("升阶失败：等级不变", player.rank_of("玄甲印") == rk,
			"%d → %d" % [rk, player.rank_of("玄甲印")])
	_check("升阶失败：印还在", player.has_seal("玄甲印"), "印没了")
	_check("升阶失败：辅材照样浪费（5 → 2）", player.bag.count("玄铁矿") == 2,
			"玄铁矿 %d" % player.bag.count("玄铁矿"))

	# 5. 合成：两枚印都进去，产出一枚新的
	player.bag.items.clear()
	player.bag.add("玄铁矿", 5)
	player.essence = player.essence_max
	var r_c2: Dictionary = GameData.RECIPES[5]         # 玄甲 + 磐石 → 云雨
	_check("合成前两枚印都在", player.has_seal("玄甲印") and player.has_seal("磐石印"),
			"缺印：%s" % str(SmithScript.missing(self, r_c2)))
	SmithScript.apply(self, r_c2, true)
	_check("合成成功：两枚材料印都消失",
			not player.has_seal("玄甲印") and not player.has_seal("磐石印"), "还留着")
	_check("合成成功：产出新印（进备用）", player.has_seal("云雨印"), str(player.reserve_seals))
	_check("合成产出的印不是抢来的（被动照常生效）", player.passive_works("云雨印"),
			"被当成抢来的了")

	# 6. 本命印不能当材料
	_check("本命印不能当合炼材料", not player.can_use_as_material(GameData.NATAL_SEAL), "竟然能")
	var fake := {"mode": "craft", "a": GameData.NATAL_SEAL, "b": "惊雷印", "result": "辉光印",
			"materials": {}}
	var said_natal := false
	for s in SmithScript.missing(self, fake):
		if str(s).contains("本命印"):
			said_natal = true
	_check("配方里用到本命印时会被拦下并说明理由", said_natal,
			str(SmithScript.missing(self, fake)))

	# 7. 等级也随回溯 / 存档走
	take_snapshot()
	var rank_snap: int = player.rank_of("灰烬印")
	player.seal_rank["灰烬印"] = 9
	player.hp = player.hp_max
	player.take_damage(99999.0)
	_on_rewind_chosen(0)
	_check("灵印等级随回溯退回那一帧的值", player.rank_of("灰烬印") == rank_snap,
			"实际 %d，期望 %d" % [player.rank_of("灰烬印"), rank_snap])
	var saved3: Dictionary = SaveGameScript.to_dict(self)
	_check("存档里带着灵印等级", saved3.has("ranks"), str(saved3.keys()))
	player.seal_rank["灰烬印"] = 4
	SaveGameScript.from_dict(self, saved3)
	_check("读档把灵印等级读回来了", player.rank_of("灰烬印") == rank_snap,
			"实际 %d" % player.rank_of("灰烬印"))

	# ==================== M13：合炼（界面流程）====================
	# ⭐ 界面里的**规则**照样能测：面板只负责「画什么、什么时候让玩家按」。

	player.bag.items.clear()
	player.essence = player.essence_max
	player.seal_rank.clear()
	forge_panel.open(self)
	_check("炉子打开时停在「选配方」这一步", forge_panel.step == 0 and forge_panel.visible,
			"step=%d" % forge_panel.step)

	# 1. 做不了的配方：说清缺什么，而且开不了炉
	forge_panel.recipe_index = 0
	_check("没材料时面板判定做不了", not forge_panel.can_do(), "竟然能做")
	_check("做不了时开炉被拒绝", not forge_panel.start(0), "竟然开了")
	_check("并且把「还差什么」写出来给玩家看", forge_panel._msg.contains("还差"), forge_panel._msg)

	# 2. 补齐材料 → 开炉（强制不出事件）→ 指针开始动
	player.bag.add("赤炎花", 5)
	player.bag.add("地火芯", 3)
	_check("补料后就能做了", forge_panel.can_do(), str(SmithScript.missing(self, forge_panel.current())))
	_check("开炉成功", forge_panel.start(0), "开炉失败")
	_check("直接进火候这一步（这次没事件）", forge_panel.step == 2 and forge_panel.running,
			"step=%d running=%s" % [forge_panel.step, str(forge_panel.running)])
	var rk0: int = player.rank_of("灰烬印")
	_check("指针不动时在最左边", is_zero_approx(forge_panel.pointer), "%.2f" % forge_panel.pointer)
	forge_panel._process(0.4)                    # 喂一点时间，指针应该动了
	_check("喂时间后指针会走", forge_panel.pointer > 0.0, "%.2f" % forge_panel.pointer)

	# 3. 点在绿区 + 运气好 → 成功
	forge_panel.pointer = 0.5                    # 正中绿区
	var rep_ui: Dictionary = forge_panel.strike(0.0)
	_check("绿区命中 + roll=0 → 成功", bool(rep_ui["success"]), str(rep_ui))
	_check("面板把「命中」也报出来", bool(rep_ui["hit"]), "没报")
	_check("成功后等级 +1", player.rank_of("灰烬印") == rk0 + 1,
			"%d → %d" % [rk0, player.rank_of("灰烬印")])
	_check("结果出来后停在「结果」这一步", forge_panel.step == 3, "step=%d" % forge_panel.step)

	# 4. 点在绿区但运气差 → 失败
	player.bag.items.clear()
	player.bag.add("赤炎花", 5)
	player.bag.add("地火芯", 3)
	player.essence = player.essence_max
	forge_panel.step = 0
	forge_panel.recipe_index = 0
	forge_panel.start(0)
	forge_panel.pointer = 0.5
	var rep_bad: Dictionary = forge_panel.strike(0.99)
	_check("绿区命中但 roll 太高 → 失败", not bool(rep_bad["success"]), str(rep_bad))
	_check("失败时命中标记仍然为真（是运气不是手滑）", bool(rep_bad["hit"]), "hit 不对")

	# 5. 指针出绿区 → 必失败，运势再好也没用
	player.bag.items.clear()
	player.bag.add("赤炎花", 5)
	player.bag.add("地火芯", 3)
	player.essence = player.essence_max
	forge_panel.step = 0
	forge_panel.start(0)
	forge_panel.pointer = 0.20                   # 绿区外
	var rk1: int = player.rank_of("灰烬印")
	var rep_miss: Dictionary = forge_panel.strike(0.0)
	_check("指针出绿区 → 必失败（roll=0 也没用）", not bool(rep_miss["success"]), str(rep_miss))
	_check("火候失误时命中标记为假", not bool(rep_miss["hit"]), "hit 不对")
	_check("火候失误不涨等级", player.rank_of("灰烬印") == rk1, "竟然涨了")

	# 6. 填料事件：面板要把选择传下去
	player.bag.items.clear()
	player.bag.add("赤炎花", 5)
	player.bag.add("地火芯", 3)
	player.essence = player.essence_max
	forge_panel.step = 0
	forge_panel.start(1)                         # 强制出事件
	_check("强制出事件时停在事件这一步", forge_panel.step == 1, "step=%d" % forge_panel.step)
	forge_panel.choose_event(true)               # 加料
	_check("选了加料后进火候，且选择被记住",
			forge_panel.step == 2 and forge_panel._event_choice == 1,
			"step=%d choice=%d" % [forge_panel.step, forge_panel._event_choice])
	forge_panel.pointer = 0.5
	var rep_ev: Dictionary = forge_panel.strike(0.0)
	_check("事件加料后成功率比基础高（50 → 62）",
			is_equal_approx(float(rep_ev["chance"]), 62.0), "实际 %.0f" % float(rep_ev["chance"]))

	# 7. 开关与互斥
	forge_panel.close()
	_check("关炉子后恢复时间", not get_tree().paused, "还暂停着")
	toggle_forge_panel()
	_check("按 F 打开炉子并暂停时间",
			forge_panel.visible and get_tree().paused,
			"visible=%s paused=%s" % [str(forge_panel.visible), str(get_tree().paused)])
	toggle_forge_panel()
	_check("再按 F 关闭并恢复时间",
			not forge_panel.visible and not get_tree().paused, "没关上")
	_check("真实随机也能跑（不注入）", forge_panel.strike() .is_empty(), "不该能点")

	# ==================== M14：交易 ====================
	# ⭐ 验收：买卖后灵石与背包数字一致；价格表数据驱动。

	trade_panel.close()
	player.bag.items.clear()
	player.bag.stones = 0
	player.essence = 0.0
	merchant_stock.clear()
	for entry in GameData.MERCHANT["stock"]:
		merchant_stock[str(entry["item"])] = int(entry["count"])

	_check("商人站在世界里", merchant != null and is_instance_valid(merchant), "没有商人")
	_check("货架按数据表建好", merchant_stock.size() == GameData.MERCHANT["stock"].size(),
			"货架 %d 条" % merchant_stock.size())
	_check("商人拿着的是同一个货架对象（不是副本）", merchant.stock == merchant_stock,
			"引用不一致 —— 快照恢复会失效")

	# 1. 价格表：卖价 = 表里的价 × sell_ratio（逐项对照，证明确实从表里读）
	var price_ok := true
	for item in GameData.MATERIALS:
		var want_sell := maxi(1, int(floorf(float(GameData.MATERIALS[item]["price"])
				* float(GameData.MERCHANT["sell_ratio"]))))
		if TradeScript.sell_price(str(item)) != want_sell:
			price_ok = false
	_check("每种材料的卖价都按「表里价 × sell_ratio」算", price_ok, "有对不上的")
	_check("蕴灵草 卖 2（基础价 4 × 0.5）", TradeScript.sell_price("蕴灵草") == 2,
			"%.0f" % TradeScript.sell_price("蕴灵草"))
	_check("雷髓 卖 22（基础价 45 × 0.5 向下取整）", TradeScript.sell_price("雷髓") == 22,
			"%d" % TradeScript.sell_price("雷髓"))
	var spread_ok := true
	for entry in GameData.MERCHANT["stock"]:
		var it := str(entry["item"])
		if TradeScript.buy_price(it) <= TradeScript.sell_price(it):
			spread_ok = false
	_check("他的卖价一定高于收价（不然可以刷灵石）", spread_ok, "有倒挂的")

	# 2. 买：灵石扣、货架少、背包多
	var item0 := str(GameData.MERCHANT["stock"][0]["item"])
	var buy_p := TradeScript.buy_price(item0)
	player.bag.stones = 100
	var stock0: int = merchant.available(item0)
	var r_ok: Dictionary = TradeScript.buy(self, item0)
	_check("买一个：灵石按买价扣掉", player.bag.stones == 100 - buy_p,
			"%d，期望 %d" % [player.bag.stones, 100 - buy_p])
	_check("买一个：货架少一件", merchant.available(item0) == stock0 - 1,
			"%d → %d" % [stock0, merchant.available(item0)])
	_check("买一个：背包多一件", player.bag.count(item0) == 1,
			"%d 个" % player.bag.count(item0))

	# 3. 买不了的情况：灵石不够 / 没货 / 背包满
	player.bag.stones = 0
	_check("灵石不够就买不了", not TradeScript.can_buy(self, item0), "竟然能买")
	var r_poor: Dictionary = TradeScript.buy(self, item0)
	_check("买不起时什么都不变",
			not bool(r_poor["ok"]) and merchant.available(item0) == stock0 - 1,
			str(r_poor))
	
	# 4. 卖：背包少、灵石多
	player.bag.stones = 0
	var sell_p: int = TradeScript.sell_price(item0)
	var r_sell: Dictionary = TradeScript.sell(self, item0)
	_check("卖一个：灵石按卖价进账", player.bag.stones == sell_p,
			"%d，期望 %d" % [player.bag.stones, sell_p])
	_check("卖一个：背包少一件", player.bag.count(item0) == 0,
			"%d 个" % player.bag.count(item0))
	_check("卖没有的东西会被拒绝", not bool(TradeScript.sell(self, "雷髓")["ok"]), "竟然卖了")

	# 5. 面板：买 / 卖 / 换边
	player.bag.items.clear()
	player.bag.stones = 50
	trade_panel.open(self)
	_check("面板一开始停在「他卖你的」这一侧", trade_panel.side == 0 and not trade_panel.list().is_empty(),
			"side=%d list=%d" % [trade_panel.side, trade_panel.list().size()])
	trade_panel.index = 0
	var r_ui: Dictionary = trade_panel.trade()
	_check("面板里买一个：东西进了背包", bool(r_ui["ok"]) and player.bag.count(item0) == 1,
			str(r_ui))
	# ⭐ 鼠标：**点哪一列就是买/卖哪一列**（不再需要先按键切边）
	var sell_hit: Dictionary = trade_panel.row_at(trade_panel.row_rect(0, 1).position + Vector2(10.0, 18.0))
	_check("点右侧的行会被识别成「卖」", int(sell_hit.get("side", -1)) == 1, str(sell_hit))
	var buy_hit: Dictionary = trade_panel.row_at(trade_panel.row_rect(0, 0).position + Vector2(10.0, 18.0))
	_check("点左侧的行会被识别成「买」", int(buy_hit.get("side", -1)) == 0, str(buy_hit))
	_check("点两列之间的空白什么也识别不出来",
			trade_panel.row_at(Vector2(670.0, 300.0)).is_empty(),
			str(trade_panel.row_at(Vector2(670.0, 300.0))))

	# ⭐ 单击 = 选中（不成交）；双击 = 成交
	player.bag.items.clear()
	player.bag.add("兽骨", 2)
	player.bag.stones = 100
	trade_panel._opened_frame = Engine.get_process_frames() - 1   # 假装面板早就开了
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = trade_panel.row_rect(0, 1).position + Vector2(10.0, 18.0)
	trade_panel.set_side(0)
	trade_panel._gui_input(click)
	_check("单击右侧：选中了「卖」这一侧", trade_panel.side == 1 and trade_panel.index == 0,
			"side=%d index=%d" % [trade_panel.side, trade_panel.index])
	# ⚠️ M30.4：这里按**件数**断言（原来按 capacity_used()，那是「1 件 = 1 格」时代的写法）
	_check("单击不成交（灵石与背包都没动）",
			player.bag.stones == 100 and player.bag.count("兽骨") == 2,
			"灵石 %d 兽骨 %d 件（%d 格）" % [player.bag.stones, player.bag.count("兽骨"),
					player.bag.capacity_used()])

	var dbl_sell := InputEventMouseButton.new()
	dbl_sell.button_index = MOUSE_BUTTON_LEFT
	dbl_sell.pressed = true
	dbl_sell.double_click = true
	dbl_sell.position = trade_panel.row_rect(0, 1).position + Vector2(10.0, 18.0)
	trade_panel._gui_input(dbl_sell)
	_check("双击右侧：直接卖出（背包少一件、灵石增加）",
			player.bag.count("兽骨") == 1 and player.bag.stones > 100,
			"兽骨 %d 件（%d 格）灵石 %d" % [player.bag.count("兽骨"), player.bag.capacity_used(),
					player.bag.stones])

	var dbl_buy := InputEventMouseButton.new()
	dbl_buy.button_index = MOUSE_BUTTON_LEFT
	dbl_buy.pressed = true
	dbl_buy.double_click = true
	dbl_buy.position = trade_panel.row_rect(0, 0).position + Vector2(10.0, 18.0)
	var stones_before_buy: int = player.bag.stones
	trade_panel._gui_input(dbl_buy)
	_check("双击左侧：直接买入（灵石减少）", player.bag.stones < stones_before_buy,
			"灵石 %d → %d" % [stones_before_buy, player.bag.stones])
	_check("双击买入后停在「买」这一侧", trade_panel.side == 0, "side=%d" % trade_panel.side)

	# ⭐ 回归：**不依赖平台的双击标志** —— 两次同位置按下就该成交
	#    （合成/注入的事件不带 double_click，所以这条必须靠自己算时间）
	player.bag.items.clear()
	player.bag.stones = 200
	trade_panel._last_click_row = -1
	trade_panel._last_click_ms = -99999
	var p1 := InputEventMouseButton.new()
	p1.button_index = MOUSE_BUTTON_LEFT
	p1.pressed = true
	p1.position = trade_panel.row_rect(0, 0).position + Vector2(10.0, 18.0)
	var p2 := InputEventMouseButton.new()
	p2.button_index = MOUSE_BUTTON_LEFT
	p2.pressed = true
	p2.position = p1.position
	var stones_before_synth: int = player.bag.stones
	trade_panel._gui_input(p1)          # 第一下：只选中
	trade_panel._gui_input(p2)          # 第二下（没有 double_click 标志）：应当成交
	_check("两次同位置按下就成交（不靠平台标志）", player.bag.stones < stones_before_synth,
			"灵石 %d → %d" % [stones_before_synth, player.bag.stones])
	_check("成交后背包里多了一件", player.bag.capacity_used() >= 1,
			"背包 %d" % player.bag.capacity_used())
	trade_panel.set_side(1)
	trade_panel.index = 0
	var stones_before_sell: int = player.bag.stones
	var r_ui2: Dictionary = trade_panel.trade()
	_check("面板里卖一个：灵石增加", bool(r_ui2["ok"]) and player.bag.stones > stones_before_sell,
			str(r_ui2))
	trade_panel.close()
	_check("关了面板恢复时间", not get_tree().paused, "还暂停着")

	# 6. E 的第三个上下文：站在商人旁边开的是交易，不是采集
	player.position = merchant.position
	player.essence = 0.0
	try_interact()
	_check("站在商人旁按 E 开的是交易面板", trade_panel.visible, "没开")
	_check("开交易时游戏暂停", get_tree().paused, "没暂停")
	trade_panel.close()

	# 7. 货架是**世界状态**：随回溯退回、随存档保存
	take_snapshot()
	var stock_snap: int = merchant.available("雷髓")
	merchant.stock["雷髓"] = 0
	player.hp = player.hp_max
	player.take_damage(99999.0)
	_on_rewind_chosen(0)
	_check("货架随回溯退回那一帧的状态", merchant.available("雷髓") == stock_snap,
			"%d，期望 %d" % [merchant.available("雷髓"), stock_snap])
	var saved5: Dictionary = SaveGameScript.to_dict(self)
	_check("存档里带着货架", saved5.has("stock"), str(saved5.keys()))
	merchant.stock["兽骨"] = 0
	SaveGameScript.from_dict(self, saved5)
	_check("读档把货架读回来", merchant.available("兽骨") > 0,
			"兽骨剩 %d" % merchant.available("兽骨"))
	_check("读档后商人手里还是同一个货架对象", merchant.stock == merchant_stock, "引用断了")
	# ⭐ 回归：读一份**没有货架字段**的旧存档，货架不该被清空
	var old_save: Dictionary = SaveGameScript.to_dict(self)
	old_save.erase("stock")
	merchant_stock.clear()
	for entry2 in GameData.MERCHANT["stock"]:
		merchant_stock[str(entry2["item"])] = int(entry2["count"])
	SaveGameScript.from_dict(self, old_save)
	_check("读没有货架字段的旧存档，货架还在（回归）",
			merchant.available("蕴灵草") > 0,
			"货架被清空了：%s" % str(merchant_stock))
	# ⭐ M25：refill() = 「开局」的统一定义（新局 / 读档 / 回溯 / 突破都走它）
	player.hp = 1.0
	player.essence = 1.0
	player.refill()
	_check("refill() 把气血与灵力都补满",
			is_equal_approx(player.hp, player.hp_max) and is_equal_approx(player.essence, player.essence_max),
			"%.0f/%.0f  %.0f/%.0f" % [player.hp, player.hp_max, player.essence, player.essence_max])
	# ⚠️ 这条守的是"读档"那条路：from_dict 改了境界却不重算上限 → 上限停在旧境界
	player.realm = 1
	player.refill()
	var m25_low: float = player.essence_max
	player.realm = 5
	player.refill()
	_check("境界变了之后 refill() 按新上限补满（读档那条路的关键）",
			player.essence_max > m25_low and is_equal_approx(player.essence, player.essence_max),
			"%.0f → %.0f（灵力 %.0f）" % [m25_low, player.essence_max, player.essence])
	player.realm = 1
	player.refill()
	_check("存档版本号是 8（+ 世界容器改尺寸）", int(SaveGameScript.VERSION) == 8,
			"%d" % int(SaveGameScript.VERSION))

	# ⭐ 接线：E 必须真的走到 try_interact（否则「E 交易 / E 突破」的提示是空话）
	trade_panel.close()
	player.essence = 0.0
	player.position = merchant.position
	var e_ev := InputEventAction.new()
	e_ev.action = "interact"
	e_ev.pressed = true
	player._input(e_ev)
	_check("按 E 真的走到 try_interact（站在商人旁会开面板）", trade_panel.visible,
			"面板没开 —— E 没接上")
	trade_panel.close()
	# 站在空地上按 E：什么也不该发生，但也不能报错
	player.position = spawn_point + Vector2(400.0, 300.0)
	player._input(e_ev)
	_check("空地上按 E 什么也不发生", not trade_panel.visible and not seal_panel.visible,
			"竟然开了面板")

	# ⭐ 回归：**开面板的那一下不能算作操作**（实测：按 E 开交易会顺手买下第一件）
	trade_panel.close()
	player.bag.items.clear()
	player.bag.stones = 100
	merchant_stock.clear()
	for entry3 in GameData.MERCHANT["stock"]:
		merchant_stock[str(entry3["item"])] = int(entry3["count"])
	trade_panel.open(self)                       # 同帧打开
	trade_panel.index = 0
	trade_panel._input(e_ev)                     # 同一个事件接着传进来
	_check("开面板那一帧的 E 不会成交（回归）",
			player.bag.stones == 100 and player.bag.capacity_used() == 0,
			"灵石 %d，背包 %d —— 被顺手买了" % [player.bag.stones, player.bag.capacity_used()])
	trade_panel._opened_frame = Engine.get_process_frames() - 1   # 模拟「下一帧」
	trade_panel.index = 0
	trade_panel._input(e_ev)
	_check("下一帧的 E 正常成交", player.bag.capacity_used() == 1,
			"背包 %d" % player.bag.capacity_used())
	trade_panel.close()

	# ==================== 修炼：「灵石 → 灵力 → 修为 → 境界」====================
	# ⭐ 灵力是**燃料**（能花、能买、能炼），修为是**进度**（只能涨、花不掉、买不到）。

	player.bag.items.clear()
	player.bag.stones = 0
	player.realm = 1
	player.refresh_limits()
	player.cultivation = 0.0
	player.essence = player.essence_max
	for i in range(player.slot_summoned.size()):
		if player.slot_summoned[i] != null:
			player.toggle_slot(i)

	_check("修为上限由境界表给（炼气 = 100）", is_equal_approx(player.cultivation_max(), 100.0),
			"%.0f" % player.cultivation_max())

	# 1. 修炼：花灵力换修为
	var gain1: float = player.cultivate()
	_check("修炼一次：花 20 灵力换 20 修为",
			is_equal_approx(gain1, 20.0) and is_equal_approx(player.cultivation, 20.0)
			and is_equal_approx(player.essence, player.essence_max - 20.0),
			"修为 +%.0f / 灵力剩 %.0f" % [gain1, player.essence])

	# 2. 修为满了就不再换（也不白扣灵力）
	player.cultivation = player.cultivation_max()
	var ess_before_cult: float = player.essence
	_check("修为满了就修炼不动了",
			is_zero_approx(player.cultivate()) and is_equal_approx(player.essence, ess_before_cult),
			"竟然还在换")

	# 3. 灵力不足 1 点就换不了
	player.cultivation = 0.0
	player.essence = 0.5
	_check("灵力不足 1 点就修炼不了", is_zero_approx(player.cultivate()), "竟然换了")

	# 4. 只按**真正换到的部分**扣灵力（不吃亏）
	player.cultivation = player.cultivation_max() - 5.0
	player.essence = player.essence_max
	var gain2: float = player.cultivate()
	_check("修为快满时只换差额，灵力也只扣那么多",
			is_equal_approx(gain2, 5.0)
			and is_equal_approx(player.essence, player.essence_max - 5.0),
			"换到 %.0f 扣了 %.0f" % [gain2, player.essence_max - player.essence])

	# 4.5 修炼按钮在命窍界面里（⭐ 用户要求：不该跑回锚点按 E）
	player.essence = player.essence_max
	player.cultivation = 0.0
	seal_panel.open(player, self)
	_check("命窍面板能修炼（按钮可用）", seal_panel.can_cultivate(), "按钮是灰的")
	var gained_ui: float = seal_panel.do_cultivate()
	_check("点「修炼」按钮：花 20 灵力换 20 修为",
			is_equal_approx(gained_ui, 20.0) and is_equal_approx(player.cultivation, 20.0)
			and is_equal_approx(player.essence, player.essence_max - 20.0),
			"换到 %.0f 修为 / 灵力剩 %.0f" % [gained_ui, player.essence])
	_check("修炼按钮画在面板里、且和点击区一致",
			seal_panel.cultivate_rect().size.x > 0.0 and seal_panel.cultivate_rect().has_point(
					seal_panel.cultivate_rect().position + Vector2(5.0, 5.0)),
			str(seal_panel.cultivate_rect()))
	player.essence = 0.0
	_check("灵力不足时按钮变灰（不能修炼）", not seal_panel.can_cultivate(), "竟然还能点")
	_check("灵力不足时点按钮不会涨修为",
			is_zero_approx(seal_panel.do_cultivate()) and is_equal_approx(player.cultivation, 20.0),
			"修为 %.0f" % player.cultivation)
	_check("灰色按钮的提示说清了原因", seal_panel._msg.contains("修炼不动"), seal_panel._msg)
	seal_panel.close()

	# ⭐ 站在锚点旁按 E 现在**只**做突破，不再顺手修炼
	player.position = spawn_point
	player.cultivation = 0.0
	player.essence = player.essence_max
	try_interact()
	_check("E 不再有隐藏含义（修炼与突破都在面板里）",
			is_zero_approx(player.cultivation), "竟然修炼了 %.0f" % player.cultivation)

	# 5. 灵石换灵力（商人的「服务」）
	player.cultivation = 0.0
	player.essence = 0.0
	player.bag.stones = 100
	var stock_before_svc: int = merchant.available("蕴灵草")
	_check("商人的买列 = 货架 + 服务",
			TradeScript.buy_entries(self).size() == TradeScript.stock_list(self).size() + 1,
			"%d 条" % TradeScript.buy_entries(self).size())
	var svc: Dictionary = TradeScript.service_of("essence")
	_check("灵力服务存在且标了不限量", not svc.is_empty() and float(svc["amount"]) > 0.0, str(svc))
	var stones_before_svc: int = player.bag.stones
	var r_svc: Dictionary = TradeScript.buy_entry(self, svc)
	_check("买一份灵力：灵石按价扣、灵力按量加",
			bool(r_svc["ok"]) and player.bag.stones == stones_before_svc - int(svc["price"])
			and is_equal_approx(player.essence, float(svc["amount"])),
			"灵石 %d→%d / 灵力 %.0f" % [stones_before_svc, player.bag.stones, player.essence])
	_check("买灵力不消耗货架（服务不限量）",
			merchant.available("蕴灵草") == stock_before_svc,
			"货架被扣了：%d → %d" % [stock_before_svc, merchant.available("蕴灵草")])

	# 6. 灵力满了 / 灵石不够 → 买不了（不白花钱）
	player.essence = player.essence_max
	_check("灵力已满时买不了灵力（不白花钱）", not TradeScript.can_buy_entry(self, svc), "竟然能买")
	player.essence = 0.0
	player.bag.stones = 0
	_check("灵石不够也买不了灵力", not TradeScript.can_buy_entry(self, svc), "竟然能买")

	# 7. 修为是进度：进快照、进存档
	player.cultivation = 40.0
	take_snapshot()
	player.cultivation = 90.0
	player.hp = player.hp_max
	player.take_damage(99999.0)
	_on_rewind_chosen(0)
	_check("修为随回溯退回那一帧的值", is_equal_approx(player.cultivation, 40.0),
			"实际 %.0f" % player.cultivation)
	var saved6: Dictionary = SaveGameScript.to_dict(self)
	_check("存档里带着修为", saved6.has("cultivation"), str(saved6.keys()))
	player.cultivation = 7.0
	SaveGameScript.from_dict(self, saved6)
	_check("读档把修为读回来", is_equal_approx(player.cultivation, 40.0),
			"实际 %.0f" % player.cultivation)

	# ==================== 锚点可见性（用户报告：「修为满了却突破不了」）====================
	# ⭐ 根因不是突破坏了，是**玩家找不到锚点** ——
	#    击败精英会自动把锚点钉在主角脚下，而世界里没有任何标记；
	#    玩家站在世界中心（商人在那儿）按 E，距离 700+px，够不着。
	player.cultivation = 0.0
	player.realm = 1
	player.refresh_limits()
	# M19：锚点机制移除 —— 「触发范围」「罗盘的世界→屏幕换算」两条断言一并删除。

	# M19：锚点没了 —— **E 在任何地方都不再是突破**（突破只在 Tab 命窍面板里做）
	var keep_spawn: Vector2 = spawn_point
	var realm_before_far: int = player.realm
	player.cultivation = player.cultivation_max()
	player.position = Vector2(900.0, 900.0)
	try_interact()
	_check("E 在任何地方都不会突破（突破只在命窍面板里）",
			player.realm == realm_before_far, "境界 %d → %d" % [realm_before_far, player.realm])
	seal_panel.open(player, self)
	_check("命窍面板里随时能突破（按钮亮了）", seal_panel.can_breakthrough_now(), "按钮是灰的")
	_check("点「突破」按钮：境界 +1",
			seal_panel.do_breakthrough() and player.realm == realm_before_far + 1,
			"境界 %d" % player.realm)
	_check("没攒满时点突破按钮会被拒绝",
			not seal_panel.do_breakthrough() and player.realm == realm_before_far + 1,
			"境界 %d" % player.realm)
	_check("突破不动出生点（它跟突破本来就无关）",
			spawn_point.is_equal_approx(keep_spawn), str(spawn_point))

	# ⭐⭐ 用户要的规则：突破是**局内收获** —— 它不拍快照，死亡会连境界和修为一起退回去。

	# 第一段：突破**不动回溯点**（snapshot 里的境界 / 修为必须原封不动）
	player.realm = 1
	player.refresh_limits()
	player.cultivation = player.cultivation_max()
	var snap_realm0: int = int(snapshot.get("realm", 0))
	var snap_cult0: float = float(snapshot.get("cultivation", 0.0))
	_check("突破这一步真的生效了", try_breakthrough(), "突破失败")
	_check("突破不改回溯点（snapshot 的境界没动）",
			int(snapshot.get("realm", 0)) == snap_realm0,
			"snapshot 境界 %d → %d" % [snap_realm0, int(snapshot.get("realm", 0))])
	_check("突破不改回溯点（snapshot 的修为没动）",
			is_equal_approx(float(snapshot.get("cultivation", 0.0)), snap_cult0),
			"snapshot 修为 %.0f → %.0f" % [snap_cult0, float(snapshot.get("cultivation", 0.0))])
	_check("此刻境界高于回溯点 = 未钉锚", unbanked_realm(), "居然已经是钉锚状态")

	# 第二段：突破完就死 → 境界与修为**一起退回**回溯点的值
	var snap_realm_at_death: int = int(snapshot.get("realm", 0))
	var snap_cult_at_death: float = float(snapshot.get("cultivation", 0.0))
	var realm_after_bt: int = player.realm
	player.hp = player.hp_max
	player.take_damage(99999.0)
	_on_rewind_chosen(0)
	_check("突破完就死：境界**退回**回溯点的值（突破不钉锚）",
			player.realm == snap_realm_at_death,
			"突破到 %d，死了回到 %d（期望 %d）" % [realm_after_bt, player.realm, snap_realm_at_death])
	_check("突破完就死：修为也回到回溯点的值",
			is_equal_approx(player.cultivation, snap_cult_at_death),
			"修为 %.0f（期望 %.0f）" % [player.cultivation, snap_cult_at_death])
	_check("死完就不再是「未钉锚」状态", not unbanked_realm(), "还挂着未钉锚")

	# 第三段：反过来 —— **钉了锚**之后突破才存得住
	player.realm = 1
	player.refresh_limits()
	player.cultivation = player.cultivation_max()
	try_breakthrough()
	_check("刚突破完还是未钉锚", unbanked_realm(), "竟然已经钉住了")
	save_now()                                  # 存档 = 拍快照 + 拍帧（自测里不写盘）
	_check("钉锚之后就不再是未钉锚", not unbanked_realm(), "钉锚没生效")
	player.hp = player.hp_max
	player.take_damage(99999.0)
	_on_rewind_chosen(0)
	_check("钉锚之后再死：突破保住了", player.realm == 2, "境界 %d" % player.realm)
	spawn_point = keep_spawn
	player.realm = 1
	player.cultivation = 0.0
	player.refresh_limits()

	# 提示条
	hud.notice("测试提示", 2.0)
	_check("HUD 能显示一句话提示", hud._notice == "测试提示", hud._notice)
	hud._process(3.0)
	_check("提示会自己消失（不会永远挂在屏幕上）", hud._notice == "", hud._notice)

	# ==================== M17/M28：盲跳回溯（已移除）====================
	# ⚠️ M28（用户定案）：回溯功能**暂时移除**，等后面重新设计（见开发计划）。
	#    原来这里测的是：时间线拍帧 / 深度评分 / 退帧公式 / 连死保底 / 锚帧下限 / 整合流程。
	#    这些函数（capture_frame / current_depth_score / rollback_*）已随功能一起删掉，
	#    所以整段测试一并删除 —— 不是"跳过"，是**没有东西可测了**。
	#    接回来时：把函数和这段测试一起恢复（设计记录在 设计圣经 §4.4）。
	# ==================== M18：炼化门槛 / 封印 / 小境界 ====================
	_test_loadout()
	player.essence = player.essence_max

	# 1. 炼化 = 使用前提
	player.seal_refine["玄甲印"] = 0.0
	var ru1: Dictionary = player.toggle_slot(1)
	_check("未融合的印不能用（reason=unusable）",
			not bool(ru1["ok"]) and str(ru1.get("reason", "")) == "unusable", str(ru1))
	_check("拒绝的理由说清是「未融合」",
			str(ru1.get("detail", "")).contains("未融合"), str(ru1))

	# 2. 点一次「炼化」：花灵力、涨炼化度
	var ess_before_ref: float = player.essence
	var rp: Dictionary = player.refine_press("玄甲印")
	_check("炼化一次：灵力 -10、炼化度 +8",
			bool(rp["ok"]) and is_equal_approx(player.essence, ess_before_ref - 10.0)
			and is_equal_approx(player.refine_of("玄甲印"), 8.0),
			"灵力 %.0f→%.0f 炼化 %.0f" % [ess_before_ref, player.essence, player.refine_of("玄甲印")])
	player.seal_refine["玄甲印"] = 0.0
	player.essence = 5.0
	_check("灵力不够时炼化被拒（且不扣灵力）",
			not bool(player.refine_press("玄甲印")["ok"]) and is_equal_approx(player.essence, 5.0),
			"灵力 %.0f" % player.essence)
	player.seal_refine["玄甲印"] = float(GameData.REFINE["max"])
	player.essence = player.essence_max        # ⚠️ 上一步把灵力压到 5 了，先补满再验"能用"
	_check("炼满之后就能用了", bool(player.toggle_slot(1)["ok"]), "还是不能用")
	player.toggle_slot(1)
	player.essence = player.essence_max

	# 3. 封印：用**品阶谓词**验（GameData 是 const，测试里改不了某枚印的 rank）
	player.realm = 1
	player.refresh_limits()
	_check("炼气可驾驭的品阶上限是 2 等", player.seal_rank_cap() == 2, str(player.seal_rank_cap()))
	_check("3 等印在炼气期会被封印", player.is_sealed_rank(3), "没封印")
	_check("2 等印在炼气期能用（惊雷印只要炼满就能上）", not player.is_sealed_rank(2), "被封印了")
	player.realm = 3
	player.refresh_limits()
	_check("金丹可驾驭到 4 等 → 3 等解封（解封是自动的，没有额外操作）",
			not player.is_sealed_rank(3) and player.is_sealed_rank(5),
			"cap=%d" % player.seal_rank_cap())
	player.realm = 1
	player.refresh_limits()

	# 4. 小境界：修为的刻度，不是独立进度
	player.realm = 1
	player.refresh_limits()
	player.cultivation = 0.0
	_check("修为 0 → 小境界「初」(0/4)", player.sub() == 0 and player.sub_name() == "初",
			"%d %s" % [player.sub(), player.sub_name()])
	player.cultivation = player.cultivation_max() * 0.25
	_check("修为 1/4 → 小境界「中」(1/4)", player.sub() == 1 and player.sub_name() == "中",
			"%d %s" % [player.sub(), player.sub_name()])
	player.cultivation = player.cultivation_max()
	_check("修为满 → 小境界「巅峰」(3/4)", player.sub() == 3 and player.sub_name() == "巅峰",
			"%d %s" % [player.sub(), player.sub_name()])
	_check("小境界给少量加成（巅峰 = 气血 +18）", is_equal_approx(player.sub_bonus("hp"), 18.0),
			"%.1f" % player.sub_bonus("hp"))
	# ⚠️ 只比"差值"：气血上限里还有炼化满的基础加成，写死总数会随着那部分变动而假失败
	player.cultivation = 0.0
	player.refresh_limits()
	var hp_at_sub0: float = player.hp_max
	player.cultivation = player.cultivation_max()
	player.refresh_limits()
	_check("修为满（巅峰）让气血上限多 18",
			is_equal_approx(player.hp_max - hp_at_sub0, 18.0),
			"%.0f → %.0f" % [hp_at_sub0, player.hp_max])
	var realm_save_sub: int = player.realm
	player.breakthrough()
	_check("突破后小境界归零（修为清零 → 刻度自然回 0）",
			player.sub() == 0 and player.realm == realm_save_sub + 1,
			"sub=%d realm=%d" % [player.sub(), player.realm])
	player.realm = 1
	player.cultivation = 0.0
	player.refresh_limits()

	# 5. 开局：只有两枚、而且两枚都是"已融合"的
	_check("开局只给两枚印", GameData.SEAL_ORDER.size() == 2, str(GameData.SEAL_ORDER))
	var fresh_p = Player.new()          # 和 _build_world 一样：Player 是全局类名
	add_child(fresh_p)
	_check("开局那两枚直接炼满（否则第一场架打不了）",
			fresh_p.is_refined("灰烬印") and fresh_p.is_refined("玄甲印"),
			str(fresh_p.seal_refine))
	_check("第 3、4 槽是空的（惊雷 / 磐石改为世界获得）",
			str(fresh_p.slot_seal[2]) == "" and str(fresh_p.slot_seal[3]) == "",
			str(fresh_p.slot_seal))
	_check("开局两枚都能用", bool(fresh_p.can_use("灰烬印")["ok"]) and bool(fresh_p.can_use("玄甲印")["ok"]),
			"有一枚不能用")
	fresh_p.queue_free()

	# 6. 旧档迁移：v2 的炼化度不是门槛 → 读进来要补满，否则玩家的印全变废铁
	var v2_save: Dictionary = SaveGameScript.to_dict(self)
	v2_save["version"] = 2
	v2_save["refine"] = {"灰烬印": 10.0, "玄甲印": 20.0}
	SaveGameScript.from_dict(self, v2_save)
	_check("读 v2 旧档：已有印的炼化度补满（不然全变废铁）",
			is_equal_approx(player.refine_of("灰烬印"), 100.0)
			and is_equal_approx(player.refine_of("玄甲印"), 100.0),
			"灰烬 %.0f / 玄甲 %.0f" % [player.refine_of("灰烬印"), player.refine_of("玄甲印")])
	var v3_save: Dictionary = SaveGameScript.to_dict(self)
	v3_save["version"] = 3
	v3_save["refine"] = {"灰烬印": 10.0}
	SaveGameScript.from_dict(self, v3_save)
	_check("读 v3 新档：炼化度原样读回（不做迁移）",
			is_equal_approx(player.refine_of("灰烬印"), 10.0),
			"灰烬 %.0f" % player.refine_of("灰烬印"))
	_test_loadout()

	# 7. 旧档迁移链：v4 →（减半）→（×4）→（v8 改尺寸按比例）→ 世界中心
	#    ⭐ 迁移是**链式**的：每一条只管自己那一段，所以 v4 档要把 v5/v7/v8 三段全走一遍。
	var v4_save: Dictionary = SaveGameScript.to_dict(self)
	v4_save["version"] = 4
	v4_save["anchor"] = [1280.0, 720.0]        # 旧世界的正中心
	SaveGameScript.from_dict(self, v4_save)
	_check("读 v4 旧档：减半 → ×4 → 按 v8 比例缩放（1280,720 → 世界中心 %s）" % str(GameData.WORLD["size"] * 0.5),
			spawn_point.is_equal_approx(GameData.WORLD["size"] * 0.5), str(spawn_point))
	var v5_save: Dictionary = SaveGameScript.to_dict(self)
	v5_save["version"] = 5
	v5_save["anchor"] = [1280.0, 720.0]        # v5 世界（减半后）的坐标
	SaveGameScript.from_dict(self, v5_save)
	_check("读 v5 旧档：只走 ×4 与 v8 缩放（1280,720 → 3584,3072）",
			spawn_point.is_equal_approx(Vector2(3584.0, 3072.0)), str(spawn_point))
	# 8. 旧档迁移（M31 Step 0）：v7 的坐标是**旧世界** 5120×2880 的，读进来必须按比例缩放
	var v7_save: Dictionary = SaveGameScript.to_dict(self)
	v7_save["version"] = 7
	v7_save["anchor"] = [2560.0, 1440.0]        # 旧世界的正中心
	SaveGameScript.from_dict(self, v7_save)
	_check("读 v7 旧档：按分轴比例缩放（旧中心 2560,1440 → 新中心 1792,1536）",
			spawn_point.is_equal_approx(GameData.WORLD["size"] * 0.5), str(spawn_point))
	_check("迁移系数是分轴的（x ×0.7 / y ×1.0667，纵横比变了）",
			is_equal_approx(SaveGameScript.WORLD_SIZE_V7.x * 0.7, GameData.WORLD["size"].x)
			and is_equal_approx(SaveGameScript.WORLD_SIZE_V7.y * (3072.0 / 2880.0), GameData.WORLD["size"].y),
			"%s → %s" % [str(SaveGameScript.WORLD_SIZE_V7), str(GameData.WORLD["size"])])
	var v8_save: Dictionary = SaveGameScript.to_dict(self)
	v8_save["anchor"] = [1000.0, 500.0]        # 已经是新世界的坐标
	SaveGameScript.from_dict(self, v8_save)
	_check("读 v8 新档：坐标原样读回（不做迁移）",
			spawn_point.is_equal_approx(Vector2(1000.0, 500.0)), str(spawn_point))
	# 9. 兜底：手改坏的存档也不能把主角丢到图外
	var v8_out: Dictionary = SaveGameScript.to_dict(self)
	v8_out["anchor"] = [99999.0, -500.0]
	SaveGameScript.from_dict(self, v8_out)
	#    ⚠️ 分轴夹取：x 夹到右边界、y 夹到上边界 —— 不是整体夹到同一个角
	_check("越界坐标一律夹进世界内", spawn_point.is_equal_approx(Vector2(GameData.WORLD["size"].x, 0.0)),
			str(spawn_point))
	spawn_point = GameData.WORLD["size"] * 0.5

	# ==================== M20：闪避与冲刺（由灵印解锁）====================
	_test_loadout()                            # 灰烬/玄甲/惊雷/磐石 —— 都不是移速印
	player.essence = player.essence_max
	player.dodge_cd = 0.0
	player.dash_cd = 0.0
	player._invuln = 0.0
	_check("有养熟的印 → 能闪避（身法来自印）", player.can_dodge(), "不能闪避")
	_check("没有移速印 → 不能冲刺", not player.can_dash(), "竟然能冲刺")
	_check("冲刺被拒时说明白「需要移速印」",
			str(player.try_dash()["reason"]).contains("移速印"),
			str(player.try_dash()["reason"]))

	var rd: Dictionary = player.try_dodge()
	_check("闪避：扣 8 灵力 + 进冷却 + 给无敌帧",
			bool(rd["ok"]) and is_equal_approx(player.essence, player.essence_max - 8.0)
			and player.dodge_cd > 0.0 and player._invuln > 0.0, str(rd))
	var hp_at_dodge: float = player.hp
	player.take_damage(999.0)
	_check("无敌帧内吃不到伤害", is_equal_approx(player.hp, hp_at_dodge),
			"%.0f → %.0f" % [hp_at_dodge, player.hp])
	player._invuln = 0.0
	_check("冷却中不能再闪", not bool(player.try_dodge()["ok"]), "竟然连闪了")

	player.dodge_cd = 0.0
	player.essence = player.essence_max
	player.seal_refine["流风印"] = float(GameData.REFINE["max"])   # 养熟移速印
	_check("养熟流风印 → 能冲刺", player.can_dash(), "还是不能")
	player.dash_cd = 0.0
	var rsh: Dictionary = player.try_dash()
	_check("冲刺：扣 12 灵力 + 进冷却 + 有加速时长",
			bool(rsh["ok"]) and is_equal_approx(player.essence, player.essence_max - 12.0)
			and player.dash_cd > 0.0 and player._dash_left > 0.0, str(rsh))
	_check("移速印的基础属性生效（流风印 = 移速 +%.0f）" % float(GameData.SEALS["流风印"]["base"]["value"]),
			is_equal_approx(player.move_speed(),
					float(GameData.REALMS[player.realm]["speed"]) + player.sub_bonus("speed")
					+ float(GameData.SEALS["流风印"]["base"]["value"])),
			"%.0f" % player.move_speed())
	# ⭐ M20b：翻滚必须是「滚」出来的 —— 用户反馈「瞬移有点太快了」
	player.position = GameData.WORLD["size"] * 0.5      # 挪到世界正中，免得撞边界被夹
	player.facing = Vector2(1.0, 0.0)                    # 没输入时朝正面滚（确定性）
	player._dodge_left = 0.0
	player.dodge_cd = 0.0
	player._invuln = 0.0
	player.essence = player.essence_max
	var pos_pre: Vector2 = player.position
	var r_roll: Dictionary = player.try_dodge()
	_check("按下闪避的那一帧没有位移（不是瞬移）",
			bool(r_roll["ok"]) and player.position.is_equal_approx(pos_pre),
			"一按就跳到了 %s" % str(player.position))
	_check("按下后进入翻滚状态（位移有时长）", player._dodge_left > 0.0,
			"剩余 %.2f 秒" % player._dodge_left)
	player._move(0.01)
	var step_px: float = player.position.distance_to(pos_pre)
	_check("第一帧只走一小段（0.01 秒约 5px，而不是一次跳完全程）",
			step_px > 0.0 and step_px < 20.0, "走了 %.1f px" % step_px)
	for i in range(40):
		player._move(0.01)
	var total_px: float = player.position.distance_to(pos_pre)
	var want_px: float = float(GameData.MOVE["dodge"]["distance"])
	_check("滚完全程 ≈ 位移距离（%.0fpx）" % want_px, absf(total_px - want_px) < want_px * 0.1,
			"总位移 %.1f px（期望 %.0f）" % [total_px, want_px])
	_check("滚完之后状态清空（操作交还玩家）", is_zero_approx(player._dodge_left),
			"还剩 %.2f" % player._dodge_left)

	# ⚠️ 收尾：把翻滚/无敌状态清干净 —— 否则后面的「主角挨打」测试会被无敌帧吃掉
	#    （踩过：留着 _invuln 导致「挨打闪白 / 冒数字 / 震屏」三条忽然失败）
	player._invuln = 0.0
	player._dodge_left = 0.0
	player._dash_left = 0.0
	player.dodge_cd = 0.0
	player.dash_cd = 0.0
	player.seal_refine.clear()
	_check("一枚养熟的印都没有 → 闪避也没了（能力确实挂在印上）",
			not player.can_dodge(), "还能闪")
	_test_loadout()

	# ==================== M21：命窍界面（球形空窍 + 背包）====================
	_test_loadout()
	seal_panel.open(player, self)

	# 1. 每枚印都有形状，而且互不相同
	var shape_of: Array = []
	var missing_shape: Array = []
	for nk in GameData.SEALS.keys():
		var sh := str(GameData.SEALS[nk].get("shape", ""))
		if sh == "":
			missing_shape.append(str(nk))
		elif not shape_of.has(sh):
			shape_of.append(sh)
	_check("每枚印都有形状（形状语言）", missing_shape.is_empty(), str(missing_shape))
	_check("7 枚印的形状互不相同", shape_of.size() == GameData.SEALS.size(),
			"%d 种 / %d 枚" % [shape_of.size(), GameData.SEALS.size()])

	# ⭐ 这条是**踩出来的**：惊雷印第一版画了个自交的闪电折线，
	#    Geometry2D 三角化失败 → draw_colored_polygon 报错 → 整个 _draw() 中断，
	#    结果右半边界面（背包）整块空白。所以每个形状都必须能三角化。
	var bad_shapes: Array = []
	for nk in GameData.SEALS.keys():
		var m21_pts: PackedVector2Array = seal_panel._shape_points(str(GameData.SEALS[nk]["shape"]))
		if m21_pts.size() < 3 or Geometry2D.triangulate_polygon(m21_pts).is_empty():
			bad_shapes.append(str(nk))
	# ==================== M30.5：贴图落地体检 ====================
	# ⭐ 验收：7 枚印都配了贴图、文件真在盘上、尺寸符合规范；而且**假路径一定回退**
	#    （回退那条路不能因为「路径都写对了」而永远没人走）。
	var seal_no_tex: Array = []
	var seal_bad_size: Array = []
	for nk5 in GameData.SEALS.keys():
		var t5 := ActorVisual.texture_of(GameData.SEALS[nk5])
		if t5 == null:
			seal_no_tex.append(str(nk5))
		elif t5.get_width() != 32 or t5.get_height() != 32:
			seal_bad_size.append("%s=%dx%d" % [nk5, t5.get_width(), t5.get_height()])
	_check("7 枚印都接了贴图（art/seals/）", seal_no_tex.is_empty(), str(seal_no_tex))
	_check("灵印贴图都是 32×32（规范尺寸表）", seal_bad_size.is_empty(), str(seal_bad_size))

	# ⭐ M30.14：主角换成 HD 立绘。这里不只查数字 —— **真的去读 PNG 找脚底行**，
	#    再算脚落在世界的哪个位置。以后换图/换 offset 换错了，这条会自己红。
	var pvis9: Dictionary = GameData.PLAYER["visual"]
	var ptex9 := ActorVisual.texture_of(GameData.PLAYER)
	var psc9 := float(pvis9.get("scale", 1.0))
	_check("主角是 HD 立绘（192 高）",
			ptex9 != null and ptex9.get_height() == 192,
			("%dx%d" % [ptex9.get_width(), ptex9.get_height()]) if ptex9 != null else "没加载到")
	_check("**世界尺度没变**：192 × 0.25 = 48 世界单位（和旧像素贴图一样大，玩法不动）",
			ptex9 != null and is_equal_approx(float(ptex9.get_height()) * psc9, 48.0),
			"= %.2f" % (float(ptex9.get_height()) * psc9 if ptex9 != null else 0.0))
	var foot9 := -1
	if ptex9 != null:
		var himg9 := ptex9.get_image()
		if himg9 != null:
			if himg9.is_compressed():
				himg9.decompress()
			for fy in range(himg9.get_height() - 1, -1, -1):
				for fx in range(himg9.get_width()):
					if himg9.get_pixel(fx, fy).a > 0.03:
						foot9 = fy
						break
				if foot9 >= 0:
					break
	var foot_world9 := 0.0
	if foot9 >= 0 and ptex9 != null:
		foot_world9 = (float(foot9) + 1.0 - float(ptex9.get_height()) * 0.5) * psc9 + float(pvis9["offset"].y)
	_check("脚踩在碰撞圆心上（实测 PNG 脚底行算出来的，容差 1px）",
			foot9 >= 0 and absf(foot_world9) <= 1.0,
			"脚底行 %d → 世界 %.2f" % [foot9, foot_world9])

	var fake_vis := {"visual": {"texture": "res://art/seals/__没有这一张__.png"}}
	_check("贴图路径不存在时**安静回退**（返回 null，不报错）",
			ActorVisual.texture_of(fake_vis) == null, "竟然加载出了东西")

	# ⭐ 一条断言管住**整张贴图清单**：凡是数据表里写了路径的，文件必须真的在。
	#    起因：敌人那 4 条路径曾经「写好了但没人调用」—— 看着是已接，其实是死路。
	var tex_missing: Array = []
	var bundles: Array = [["player", GameData.PLAYER], ["dummy", GameData.DUMMY], ["gather", GameData.GATHER]]
	for key5 in GameData.ZONES:
		bundles.append(["zone_" + str(key5), GameData.ZONES[key5]])
	for key6 in GameData.ENEMY:
		bundles.append(["enemy_" + str(key6), GameData.ENEMY[key6]])
	for pair5 in bundles:
		var data5: Dictionary = pair5[1]
		var vis5: Variant = data5.get("visual", null)
		if not (vis5 is Dictionary):
			continue
		var vd5: Dictionary = vis5
		if not vd5.has("texture") or str(vd5["texture"]) == "":
			continue
		if ActorVisual.texture_of(data5) == null:
			tex_missing.append(str(pair5[0]))
		if vd5.has("empty_texture") and ActorVisual.texture_named(data5, "empty_texture") == null:
			tex_missing.append(str(pair5[0]) + "（空态）")
	_check("数据表里写了路径的贴图，文件都真的存在", tex_missing.is_empty(), str(tex_missing))

	# ⭐ M30.5b：物品图标（32×32）与掉落 token（8×8）—— **一套配方两种尺寸**
	var item_no_art: Array = []
	var item_names5: Array = GameData.MATERIALS.keys()
	item_names5.append(GameData.CURRENCY)
	for it5 in item_names5:
		var itn := str(it5)
		if not GameData.ART_ID.has(itn):
			item_no_art.append("%s（没短名）" % itn)
			continue
		var ic5 := ActorVisual.texture_of(GameData.item_visual(itn))
		var dt5 := ActorVisual.texture_of(GameData.item_drop_visual(itn))
		if ic5 == null:
			item_no_art.append("%s（没图标）" % itn)
		elif ic5.get_width() != 32 or ic5.get_height() != 32:
			item_no_art.append("%s（图标 %dx%d）" % [itn, ic5.get_width(), ic5.get_height()])
		if dt5 == null:
			item_no_art.append("%s（没掉落图）" % itn)
		elif dt5.get_width() != 8 or dt5.get_height() != 8:
			item_no_art.append("%s（掉落 %dx%d）" % [itn, dt5.get_width(), dt5.get_height()])
	_check("每种材料 + 灵石都有图标(32×32)与掉落图(8×8)", item_no_art.is_empty(), str(item_no_art))
	_check("灵印没有掉落图（有意的例外：地上的印要能认出是哪一枚，只能走形状语言）",
			GameData.item_drop_visual("流风印").is_empty(), str(GameData.item_drop_visual("流风印")))

	var body_scan := ""
	for fn5 in ["Player.gd", "Enemy.gd", "Dummy.gd", "Gather.gd", "Seal.gd", "Pickup.gd", "BagPanel.gd", "SealPanel.gd", "Hud.gd"]:
		var src5 := FileAccess.get_file_as_string("res://scripts/%s" % fn5)
		if not src5.is_empty() and not src5.contains("ActorVisual."):
			body_scan += fn5 + " "
	_check("所有画身体的地方都走 ActorVisual（贴图才不是死路径）", body_scan == "", "没走：" + body_scan)

	_check("每个形状都能三角化（自交形状会把整个界面画布中断掉）",
			bad_shapes.is_empty(), str(bad_shapes))

	# 2. 空窍大小 = 灵力容量
	player.realm = 1
	player.refresh_limits()
	var orb_r1: float = seal_panel.orb_radius()
	player.realm = 5
	player.refresh_limits()
	var orb_r5: float = seal_panel.orb_radius()
	_check("空窍半径跟着灵力容量变大", orb_r5 > orb_r1, "%.0f → %.0f" % [orb_r1, orb_r5])
	_check("空窍半径有上下限（不会撑爆屏幕）", orb_r1 >= 90.0 and orb_r5 <= 168.0,
			"%.0f / %.0f" % [orb_r1, orb_r5])
	player.realm = 1
	player.refresh_limits()

	# 3. 空窍放已炼化的印；背包放未炼化的印 + 材料
	player.seal_refine["辉光印"] = 0.0
	if not player.reserve_seals.has("辉光印"):
		player.reserve_seals.append("辉光印")
	_check("未炼化的印在背包里（和材料放一起）",
			not seal_panel.orb_seals().has("辉光印"), str(seal_panel.orb_seals()))
	var m21_be: Array = seal_panel.bag_entries()
	var m21_first := str(m21_be[0]["kind"]) if not m21_be.is_empty() else "(空)"
	_check("背包里「未炼化的印」排在材料前面", m21_first == "seal", m21_first)
	_check("已炼化的印在空窍里（三枚都在）",
			seal_panel.orb_seals().has("灰烬印") and seal_panel.orb_seals().has("玄甲印"),
			str(seal_panel.orb_seals()))
	player.seal_refine["辉光印"] = float(GameData.REFINE["max"])
	_check("炼满之后它就从背包进空窍了（空窍只收已融合的）",
			seal_panel.orb_seals().has("辉光印"), str(seal_panel.orb_seals()))
	var m21_inbag: bool = false
	for e in seal_panel.bag_entries():
		if str(e["name"]) == "辉光印" and str(e["kind"]) == "seal":
			m21_inbag = true
	_check("而且它不再出现在背包的印那一栏", not m21_inbag, "两处都在")
	player.reserve_seals.erase("辉光印")

	# 4. 灵气粒子：数量固定 + 全都落在球内（动画由时间算，不存状态）
	var m21_gas: Array = seal_panel._gas_particles()
	var m21_in := true
	for m21_gp in m21_gas:
		if m21_gp["pos"].distance_to(seal_panel.orb_center()) > seal_panel.orb_radius() + 1.0:
			m21_in = false
	_check("灵气粒子有 52 颗，且全落在空窍球内", m21_gas.size() == 52 and m21_in,
			"%d 颗，全在球内=%s" % [m21_gas.size(), str(m21_in)])
	seal_panel.close()

	# ==================== M21b：空窍里的印点得到（换印）====================
	_test_loadout()
	seal_panel.open(player, self)
	player.reserve_seals.append("辉光印")
	player.seal_refine["辉光印"] = float(GameData.REFINE["max"])
	var m21b_keys: Array = seal_panel.orb_seals()
	var m21b_i: int = m21b_keys.find("辉光印")
	_check("备用印也在空窍里（已融合的都在）", m21b_i >= 0, str(m21b_keys))
	# ⚠️ 这条守的是用户撞到的 bug：命中测试以前返回**活跃槽下标**，
	#    备用印 find() 得到 -1 → pick_seal(-1) 被挡掉 → 空窍里只有活跃的 4 枚点得到。
	var m21b_hit: int = seal_panel._orb_seal_at(seal_panel.orb_seal_pos(m21b_i, m21b_keys.size()))
	_check("点空窍里的备用印能命中（返回 orb_seals 下标，不是 -1）", m21b_hit == m21b_i,
			"命中 %d，期望 %d" % [m21b_hit, m21b_i])
	_check("点空窍外面不会误命中", seal_panel._orb_seal_at(Vector2(100.0, 700.0)) == -1, "误命中")
	seal_panel.pick_seal(0)                       # 目标槽 = 第 1 格
	seal_panel.select_bag_seal("辉光印")
	_check("选中备用印后「换上活跃槽 N」按钮可用", seal_panel.can_swap_selected(), "按钮没亮")
	_check("点「换上」：备用印真的换上去了",
			seal_panel.do_swap_selected() and str(player.slot_seal[0]) == "辉光印",
			str(player.slot_seal))
	_check("换下来的印进了备用", player.reserve_seals.has("灰烬印"), str(player.reserve_seals))
	_check("活跃槽里的印不会弹出「换上」按钮", not seal_panel.can_swap_selected(), "弹了")
	_check("换印后不再处于换印步（回到炼化步）", seal_panel.step == 1, "step=%d" % seal_panel.step)
	# ⭐ 换回来，再走一次**真实点击路径**（合成鼠标事件喂给 _gui_input）——
	#    光验 API 不够：用户是按不了按钮，不是 API 坏了。
	seal_panel.pick_seal(0)
	seal_panel.select_bag_seal("灰烬印")
	var m21b_ev := InputEventMouseButton.new()
	m21b_ev.button_index = MOUSE_BUTTON_LEFT
	m21b_ev.pressed = true
	m21b_ev.position = seal_panel.swap_target_rect().position + Vector2(6.0, 6.0)
	seal_panel._gui_input(m21b_ev)
	_check("点「换上」按钮真的能换（走 _gui_input 这条真实路径）",
			str(player.slot_seal[0]) == "灰烬印", str(player.slot_seal))
	# 空窍里的印点得到吗（也是走 _gui_input）
	var m21b_orbs: Array = seal_panel.orb_seals()
	var m21b_ev2 := InputEventMouseButton.new()
	m21b_ev2.button_index = MOUSE_BUTTON_LEFT
	m21b_ev2.pressed = true
	m21b_ev2.position = seal_panel.orb_seal_pos(0, m21b_orbs.size())
	seal_panel._gui_input(m21b_ev2)
	_check("点空窍里的印会被选中（不是没反应）", seal_panel.current_seal() == str(m21b_orbs[0]),
			"选中=%s，期望 %s" % [seal_panel.current_seal(), str(m21b_orbs[0])])
	player.reserve_seals.erase("辉光印")
	player.reserve_seals.erase("灰烬印")
	_test_loadout()
	seal_panel.close()

	# ==================== M26：印诀（结印触发）====================
	# ⭐ 方案 A（用户拍板）：**按 R 起手进入结印 → 数字键填序列 → 凑齐结算**。
	#    结印时按下的印**不显化、不消耗**；代价只剩印诀那一笔灵力。
	_test_loadout()
	player.combo_cds.clear()
	player.cancel_sealing()
	player.essence = player.essence_max

	# 1. 数据自洽
	var m26_bad_keys: Array = []
	for k in GameData.COMBOS.keys():
		var m26p: PackedStringArray = str(k).split("|")
		if m26p.size() != 2 or GameData.combo_key(str(m26p[0]), str(m26p[1])) != str(k):
			m26_bad_keys.append(str(k))
	_check("印诀表的键都是排过序的（一律用 combo_key 生成）", m26_bad_keys.is_empty(), str(m26_bad_keys))
	var m26_bad_seals: Array = []
	for k in GameData.COMBOS.keys():
		for part in str(k).split("|"):
			if not GameData.SEALS.has(str(part)):
				m26_bad_seals.append(str(k))
	_check("印诀表引用的印都存在", m26_bad_seals.is_empty(), str(m26_bad_seals))
	var m26_no_tag: Array = []
	for nk in GameData.SEALS.keys():
		if (GameData.SEALS[nk].get("tags", []) as Array).is_empty():
			m26_no_tag.append(str(nk))
	_check("每枚印都有标签（印诀与将来的推演都靠它）", m26_no_tag.is_empty(), str(m26_no_tag))
	_check("一共六对印诀", GameData.COMBOS.size() == 6, str(GameData.COMBOS.size()))
	_check("结印窗口是 1.2 秒（用户拍板）", is_equal_approx(float(GameData.COMBO_WINDOW), 1.2),
			str(GameData.COMBO_WINDOW))

	# 2. 起手
	var m26_s: Dictionary = player.toggle_sealing()
	_check("按 R 起手进入结印", bool(m26_s["ok"]) and player.is_sealing(), str(m26_s))
	_check("起手就给满窗口", is_equal_approx(player.seal_window_left, player.combo_window()),
			"%.2f" % player.seal_window_left)

	# 3. ⭐ 填第一枚：不显化、不扣灵力
	var m26_ess: float = player.essence
	var m26_i1: Dictionary = player.input_seal(0)
	_check("结印时按印**不显化**", bool(m26_i1["ok"]) and player.slot_summoned[0] == null,
			"槽1 = %s" % str(player.slot_summoned[0]))
	_check("结印时按印**不扣灵力**（没有显化费）", is_equal_approx(player.essence, m26_ess),
			"%.0f → %.0f" % [m26_ess, player.essence])
	_check("序列记下了第一枚", player.seal_input.size() == 1 and str(player.seal_input[0]) == "灰烬印",
			str(player.seal_input))

	# 4. 填第二枚 → 结算
	var m26_target = null
	for e in enemies:
		if is_instance_valid(e) and e.is_alive():
			m26_target = e
			break
	_check("场上有敌人可以挨这一下", m26_target != null, "一只都没有")
	m26_target.position = player.position + Vector2(40.0, 0.0)
	var m26_hp: float = m26_target.hp
	var m26_i2: Dictionary = player.input_seal(2)
	_check("填满两枚 → 印诀结算（爆炎）", str(m26_i2["fired"]) == "爆炎", str(m26_i2))
	var m26_key: String = GameData.combo_key("灰烬印", "惊雷印")
	_check("只扣印诀那一笔灵力（没有显化费）",
			is_equal_approx(player.essence, m26_ess - float(GameData.COMBOS[m26_key]["essence"])),
			"%.0f → %.0f（期望 %.0f）" % [m26_ess, player.essence,
					m26_ess - float(GameData.COMBOS[m26_key]["essence"])])
	_check("爆炎真的打到了身边的敌人",
			not is_instance_valid(m26_target) or m26_target.hp < m26_hp, "血量没变")
	_check("放成一次 = 学会了（记进知识）", player.is_combo_learned(m26_key), str(player.learned_combos))
	_check("结算后结印状态自动清空", not player.is_sealing() and player.seal_input.is_empty(),
			"sealing=%s input=%d" % [str(player.is_sealing()), player.seal_input.size()])
	_check("进冷却（每门各自）", player.combo_cd_for(m26_key) > 0.0, "%.1f" % player.combo_cd_for(m26_key))

	# 5. 冷却中再结 → 结算被拒，理由写清，且不扣费
	player.essence = player.essence_max
	player.toggle_sealing()
	player.input_seal(0)
	var m26_ess2: float = player.essence
	var m26_i3: Dictionary = player.input_seal(2)
	_check("冷却中结不出（理由写清）", str(m26_i3["fired"]) == "" and player.last_combo_msg.contains("冷却"),
			player.last_combo_msg)
	_check("冷却中被拒也不扣灵力", is_equal_approx(player.essence, m26_ess2), "%.0f" % player.essence)

	# 6. 配不出印诀的两枚 → 如实说，不扣费
	player.combo_cds.clear()
	player.essence = player.essence_max
	player.toggle_sealing()
	player.input_seal(0)
	var m26_ess3: float = player.essence
	var m26_i4: Dictionary = player.input_seal(1)
	_check("配不出印诀的两枚：放不出来 + 如实提示", str(m26_i4["fired"]) == ""
			and player.last_combo_msg.contains("配不出"), player.last_combo_msg)
	_check("配不出也不扣灵力", is_equal_approx(player.essence, m26_ess3), "%.0f" % player.essence)

	# 7. 窗口超时：自动收势，不扣任何东西
	player.toggle_sealing()
	player.input_seal(0)
	_check("窗口在跑", player.is_sealing() and player.seal_window_left > 0.0,
			"%.2f" % player.seal_window_left)
	player._process(0.6)
	_check("半秒还没超时，还在结印", player.is_sealing(), "%.2f" % player.seal_window_left)
	player._process(1.0)
	_check("超过窗口 → 自动收势（不扣任何东西）",
			not player.is_sealing() and player.seal_input.is_empty(), "%.2f" % player.seal_window_left)

	# 8. ⭐ 结印与"印在不在场"无关
	for i in range(player.slot_seal.size()):
		player.recall_slot(i)
	player.combo_cds.clear()
	player.essence = player.essence_max
	_check("一枚印都没显化，照样能起手结印",
			bool(player.toggle_sealing()["ok"]) and player.summoned_names().is_empty(),
			"summoned=%d" % player.summoned_names().size())
	player.input_seal(0)
	var m26_i5: Dictionary = player.input_seal(2)
	_check("不显化任何印也能放出印诀", str(m26_i5["fired"]) == "爆炎", str(m26_i5))
	_check("放完印诀，场上依然没有印（结印不上场、也不回收）",
			player.summoned_names().is_empty(), str(player.summoned_names()))

	# 9. 未融合的印结不出来
	player.seal_refine["磐石印"] = 0.0
	player.toggle_sealing()
	var m26_i6: Dictionary = player.input_seal(3)
	_check("未融合的印结不出印诀（并说清原因）",
			not bool(m26_i6["ok"]) and str(m26_i6["reason"]).contains("融合"), str(m26_i6))
	player.seal_refine["磐石印"] = float(GameData.REFINE["max"])
	player.cancel_sealing()

	# 10. 面板里的连线 = 真能结的印诀（同源）
	seal_panel.open(player, self)
	_check("空窍里画出的印诀连线就是能结的（同源）", seal_panel.combo_links().size() >= 1,
			str(seal_panel.combo_links()))
	seal_panel.close()
	player.combo_cds.clear()
	player.cancel_sealing()
	player.essence = player.essence_max
	_test_loadout()
	# ==================== 打击感（反馈层）====================
	# ⭐ 反馈不是装饰：没有它，「数值好不好」根本验不出来。

	_check("手感参数表存在，且停顿倍率 < 1",
			GameData.JUICE.has("hitstop_scale") and float(GameData.JUICE["hitstop_scale"]) < 1.0,
			str(GameData.JUICE.get("hitstop_scale", "缺")))
	_check("震屏是衰减的（decay > 0），不会永远抖",
			float(GameData.JUICE["shake_decay"]) > 0.0,
			str(GameData.JUICE["shake_decay"]))

	# 1. 飘字
	numbers.clear()
	add_number(Vector2(100.0, 100.0), 12.4, Color.WHITE)
	_check("冒一个伤害数字", numbers.size() == 1, "%d 个" % numbers.size())
	_check("数字取整显示（12.4 → \"12\"）", str(numbers[0]["text"]) == "12",
			"实际「%s」" % str(numbers[0]["text"]))
	_tick_juice(float(GameData.JUICE["number_life"]) + 0.1)
	_check("数字过期就消失（不会一直堆着）", numbers.is_empty(), "还剩 %d 个" % numbers.size())

	# 2. 命中停顿：⭐ 自测模式下绝不动时间倍率（否则整个测试都被拖慢）
	Engine.time_scale = 1.0
	hitstop(0.05)
	_check("自测模式下不停顿、时间倍率保持 1.0", is_equal_approx(Engine.time_scale, 1.0),
			"time_scale = %.2f" % Engine.time_scale)

	# ⭐ 回归：时间倍率**必须能被放回去**（哪怕主循环卡住、计时器根本不走）
	#    踩过：用 create_timer 恢复，主循环一停就永远停在 0.05，整个游戏变慢动作。
	Engine.time_scale = 0.05
	_hitstop_until_ms = Time.get_ticks_msec() + 10000
	_tick_juice(0.016)
	_check("停顿还没到时，时间倍率保持压慢", is_equal_approx(Engine.time_scale, 0.05),
			"time_scale = %.2f" % Engine.time_scale)
	_hitstop_until_ms = Time.get_ticks_msec() - 1
	_tick_juice(0.016)
	_check("到点就把时间倍率放回 1.0（回归）", is_equal_approx(Engine.time_scale, 1.0),
			"time_scale = %.2f" % Engine.time_scale)
	_check("放回后截止点清零", _hitstop_until_ms == 0, str(_hitstop_until_ms))

	# 3. 震屏：取最大值 + 精确归零
	shake = 0.0
	add_shake(3.0)
	add_shake(1.0)
	_check("震屏取最大值（同时挨几下不会叠加成筛子）", is_equal_approx(shake, 3.0),
			"shake = %.1f" % shake)
	camera.offset = Vector2(9.0, 9.0)
	_tick_juice(1.0)
	_check("震屏会衰减到 0", is_zero_approx(shake), "shake = %.2f" % shake)
	_check("归零后相机偏移也精确清零（否则画面一直偏）",
			camera.offset.is_equal_approx(Vector2.ZERO), str(camera.offset))

	# 4. 敌人挨打 = 数字 + 震屏；持续伤害的每跳只跳字不震屏
	numbers.clear()
	shake = 0.0
	var victim2 = enemies[0]
	victim2.hp = victim2.hp_max
	victim2.take_damage(7.0)
	_check("打敌人会冒数字", numbers.size() >= 1, "%d 个" % numbers.size())
	_check("打敌人会带一点震屏", shake > 0.0, "shake = %.1f" % shake)
	shake = 0.0
	numbers.clear()
	victim2.take_damage(3.0, Color(0.98, 0.66, 0.34), false)      # DoT 那一跳
	_check("持续伤害每跳只跳字、不震屏",
			numbers.size() >= 1 and is_zero_approx(shake),
			"数字 %d 个 / shake %.1f" % [numbers.size(), shake])

	# 5. 主角挨打 = 闪白 + 红色数字 + 更重的震屏
	player.hp = player.hp_max
	player._hurt = 0.0
	shake = 0.0
	numbers.clear()
	player.take_damage(10.0)
	_check("主角挨打会闪白", player._hurt > 0.0, "_hurt = %.2f" % player._hurt)
	_check("主角挨打会冒数字", numbers.size() >= 1, "%d 个" % numbers.size())
	_check("主角挨打的震屏比打敌人重",
			shake >= float(GameData.JUICE["shake_hurt"]) - 0.01, "shake = %.1f" % shake)
	_tick_juice(1.0)
	_check("震屏收干净后画面归位", is_zero_approx(shake) and camera.offset.is_equal_approx(Vector2.ZERO),
			"shake %.2f offset %s" % [shake, str(camera.offset)])

	# ==================== 回归：面板「关不掉」bug ====================
	# ⭐ bug 成因：_input 从子节点往父节点传。面板关自己 → 解除暂停 →
	#    Game._input 在同一帧接着处理同一个键 → 又把面板开回来。
	#    修法：面板吃掉这个键，Game 尊重「已被吃掉」的标记。
	seal_panel.close()
	toggle_seal_panel()
	_check("回归前置：Tab 能打开命窍面板", seal_panel.visible and get_tree().paused,
			"visible=%s paused=%s" % [str(seal_panel.visible), str(get_tree().paused)])
	var tab_ev := InputEventAction.new()
	tab_ev.action = "open_panel"
	tab_ev.pressed = true
	# ⚠️ 打开的那一帧面板不响应任何操作，所以先模拟「已经过了一帧」
	seal_panel._opened_frame = Engine.get_process_frames() - 1
	seal_panel._input(tab_ev)          # 面板先收到 → 关自己 + 吃掉这个键
	_input(tab_ev)                     # Game 后收到 → 必须认出「已被吃掉」而不再开
	_check("Tab 关掉面板后没有被重新打开（回归）",
			not seal_panel.visible and not get_tree().paused,
			"visible=%s paused=%s" % [str(seal_panel.visible), str(get_tree().paused)])
	get_viewport().set_input_as_handled()   # 手动把标记留着，别影响后面的用例

	# ==================== M30.7：普攻（掌风 / 真前摇 / 境界成长）====================
	# ⭐ 验收：数值表对齐用户定案；**抬手 0.15 秒后才判定**；命中才有闪白与击退。
	# ⚠️ 放在自测最末：这段会动 player / enemies / hits / swings，放中间会污染前面的用例。
	_check("普攻数值表五档齐全（一阶 → 五阶）", GameData.ATTACK_REALM.size() == 5,
			str(GameData.ATTACK_REALM.size()))
	_check("一阶 8 / 五阶 14、间隔 0.55 → 0.40（用户定案）",
			is_equal_approx(float(GameData.attack_of(1)["damage"]), 8.0)
			and is_equal_approx(float(GameData.attack_of(5)["damage"]), 14.0)
			and is_equal_approx(float(GameData.attack_of(1)["cooldown"]), 0.55)
			and is_equal_approx(float(GameData.attack_of(5)["cooldown"]), 0.40),
			"一阶 %.1f/%.2f 五阶 %.1f/%.2f" % [float(GameData.attack_of(1)["damage"]),
					float(GameData.attack_of(1)["cooldown"]), float(GameData.attack_of(5)["damage"]),
					float(GameData.attack_of(5)["cooldown"])])
	var m30_ok := true
	for m30_r in range(2, 6):
		if float(GameData.attack_of(m30_r)["damage"]) < float(GameData.attack_of(m30_r - 1)["damage"]):
			m30_ok = false
		if float(GameData.attack_of(m30_r)["cooldown"]) > float(GameData.attack_of(m30_r - 1)["cooldown"]):
			m30_ok = false
	_check("伤害单调不降、间隔单调不增（越练越强）", m30_ok, "")
	_check("越界的境界被夹回表内（读表的地方不用自己判边界）",
			is_equal_approx(float(GameData.attack_of(0)["damage"]), 8.0)
			and is_equal_approx(float(GameData.attack_of(99)["damage"]), 14.0), "")

	# ---- 真前摇：抬手先出弧光，0.15 秒后才判定 ----
	player.position = spawn_point
	player._dead = false
	player._atk_cd = 0.0
	player._windup_left = 0.0
	swings.clear()
	hits.clear()
	Input.action_press("attack")
	player._attack_input(0.016)
	_check("按下左键：**立刻**出现掌风弧光（看得见要打了）", swings.size() == 1,
			"弧光 %d" % swings.size())
	_check("但这一刻**还没有判定**（真前摇，不是「演出式」）", hits.is_empty(),
			"提前判定了 %d 下" % hits.size())
	player._attack_input(0.016)
	_check("前摇期间不会重复出招（连点不叠招）", swings.size() == 1, "弧光 %d" % swings.size())
	player._attack_input(float(GameData.ATTACK["windup"]) + 0.001)
	Input.action_release("attack")
	_check("前摇走完 → 判定生效", hits.size() == 1, "判定 %d" % hits.size())
	_check("前摇时长就是数据表里那 0.15 秒",
			is_equal_approx(float(GameData.ATTACK["windup"]), 0.15),
			"%.2f" % float(GameData.ATTACK["windup"]))

	# ---- 命中：敌人吃满伤害 + 被轻微击退 ----
	var m30_foe = null
	for e30 in enemies:
		if is_instance_valid(e30) and e30.is_alive():
			m30_foe = e30
			break
	if m30_foe == null:
		_spawn_enemy("猛兽", spawn_point + Vector2(40.0, 0.0))
		m30_foe = enemies[enemies.size() - 1]
	player.position = spawn_point
	player.facing = Vector2.RIGHT
	m30_foe.position = player.position + Vector2(10.0, 0.0)
	m30_foe.hp = m30_foe.hp_max
	var m30_hp0: float = m30_foe.hp
	var m30_x0: float = m30_foe.position.x
	hits.clear()
	player._atk_cd = 0.0
	player._windup_left = 0.0
	Input.action_press("attack")
	player._attack_input(0.016)
	Input.action_release("attack")
	player._attack_input(float(GameData.ATTACK["windup"]) + 0.001)
	_check("命中：伤害 = 境界表 + 炼化的基础加成（不写死数字）",
			is_equal_approx(m30_hp0 - m30_foe.hp,
					float(GameData.attack_of(player.realm)["damage"]) + player.attack_damage_bonus()),
			"掉了 %.1f" % (m30_hp0 - m30_foe.hp))
	_check("命中：敌人被**轻微击退**（沿朝向推开，不是原地不动）",
			m30_foe.position.x > m30_x0 + 1.0, "x %.1f → %.1f" % [m30_x0, m30_foe.position.x])
	_check("击退距离就是数据表里那个像素数",
			is_equal_approx(m30_foe.position.x - m30_x0, float(GameData.ATTACK["knockback"])),
			"推了 %.1f" % (m30_foe.position.x - m30_x0))

	# ---- 空挥：判定命中 0 个（未命中就没有任何命中反馈）----
	_check("空挥命中 0 个目标（未命中不产生任何反馈）",
			spawn_hit(Vector2(9999.0, 9999.0), Vector2.RIGHT, 44.0, 36.0, 8.0) == 0, "竟然打到了")

	# ---- 后摇可取消：冷却中照样能走（边打边跑）----
	player.position = spawn_point
	player._atk_cd = 0.5                      # 假装刚出过手
	var m30_px: float = player.position.x
	Input.action_press("move_right")
	player._move(0.1)
	Input.action_release("move_right")
	_check("后摇不粘手：冷却中照样能走动", player.position.x > m30_px + 0.5,
			"x %.1f → %.1f" % [m30_px, player.position.x])
	_check("普攻不显化灵印（用普攻的时候是安全的）",
			player.slot_summoned.filter(func(x): return x != null).is_empty(),
			"有 %d 枚印显化着" % player.slot_summoned.filter(func(x): return x != null).size())

	# ⭐ M30.13c：世界数据（高度模型）—— 渲染与玩法读同一张表
	## ⭐ M31 Step 0：尺寸**从数据算**（以前写死「40×23」，M30.25 放大世界后就一直是错的）
	_check("世界数据已加载且尺寸是 %d×%d（每格 %.0fpx）" % [
				GameData.WORLD_COLS, GameData.WORLD_ROWS, GameData.WORLD_CELL],
			GameData.world_ready(), "读取失败：%s" % GameData.WORLD_MAP_PATH)
	_check("世界格数 × 每格像素 == 世界尺寸（格表与世界容器自洽）",
			is_equal_approx(float(GameData.WORLD_COLS) * GameData.WORLD_CELL, GameData.WORLD["size"].x)
			and is_equal_approx(float(GameData.WORLD_ROWS) * GameData.WORLD_CELL, GameData.WORLD["size"].y),
			"%d×%.0f=%d vs %s" % [GameData.WORLD_COLS, GameData.WORLD_CELL,
				int(GameData.WORLD_COLS * GameData.WORLD_CELL), str(GameData.WORLD["size"])])
	## ⭐ M31.3：**世界图签名** —— 重烘焙的安全网。改 `worldmap.png` 会静默连带改
	##    高地减速阈值 / 出生点 / 同心层排布，这三处都没有自己的检测 —— 只有签名能兜住。
	##    ⚠️ 有意重烘焙后**必须**跑 `-- --worldsig` 更新基线，否则这条永远红（这是故意的）。
	var wsig := GameData.world_sig()
	var wsig_base := GameData.world_sig_baseline()
	_check("世界图签名有基线（art/world/worldmap.sig）", wsig_base != "",
			"基线文件缺失，跑 `-- --worldsig` 建一个")
	_check("世界图**没被偷改**（签名与基线一致；重烘焙后要显式更新基线）",
			wsig != "no-image" and wsig == wsig_base,
			"当前 %s / 基线 %s" % [wsig, wsig_base])
	_check("世界图签名是确定性的（连算两次一样，跨机器才可信）", GameData.world_sig() == wsig,
			"两次算的不一样：%s vs %s" % [wsig, GameData.world_sig()])
	## ⭐⭐ M31.3 收尾：地形参数的三条防线（级差 / 洞高 / 水面·泥沼占比），见 `_check_world_terrain()`
	_check_world_terrain()

	## ⭐⭐ M31 Step 0：**所有内容点的坐标必须落在世界矩形内**。
	##    起因：这次世界从 5120 宽收窄到 3584 宽 —— 若按字面把 wscl 固定成 (4,4) 烘焙，
	##    **13 个敌人里 7 个、8 个采集点里 2 个会落到世界之外**，其中两只精英带印，玩家永远够不到。
	##    那次是人工算出来的，下次不一定有人算 → 把这条升级成断言，谁烤出界都会红。
	##    ⚠️ Step 1 出 `sites` 表后，把 sites 也加进 `content_out_of_world()` 的扫描名单。
	var oob: Array = content_out_of_world()
	_check("所有内容点（敌人 / 采集点）的坐标都在世界矩形内", oob.is_empty(),
			"越界 %d 个：%s" % [oob.size(), str(oob)])
	var cliff_cnt := 0
	var deep_cnt := 0
	var elev_min := 1.0
	var elev_max := 0.0
	for cy2 in range(GameData.WORLD_ROWS):
		for cx2 in range(GameData.WORLD_COLS):
			var e2 := GameData.cell_elev(cx2, cy2)
			elev_min = minf(elev_min, e2)
			elev_max = maxf(elev_max, e2)
			if e2 - GameData.cell_elev(cx2, mini(cy2 + 1, GameData.WORLD_ROWS - 1)) >= GameData.CLIFF_STEP:
				cliff_cnt += 1
			if GameData.cell_depth(cx2, cy2) > 0.5:
				deep_cnt += 1
	_check("高度模型里真的有崖（有崖才谈得上「站在山上」）", cliff_cnt > 20, "崖格 %d" % cliff_cnt)
	_check("有深水（将来要挡住玩家、只能绕行的那部分）", deep_cnt > 10, "深水格 %d" % deep_cnt)
	_check("海拔场是起伏的（不是平的）", elev_max - elev_min > 0.3,
			"海拔 %.2f ~ %.2f" % [elev_min, elev_max])

	# ⭐ M30.13d：**行走规则** —— 崖/深水挡住、涉水与高地减速。
	#    样本全部**从世界数据里搜出来**（不写死坐标）：换一张地图，这几条依然成立。
	var c_a := Vector2.ZERO
	var c_b := Vector2.ZERO
	var deep := Vector2.ZERO
	var f_a := Vector2.ZERO
	var f_b := Vector2.ZERO
	var has_cliff := false
	var has_deep := false
	var has_flat := false
	for cy3 in range(GameData.WORLD_ROWS):
		for cx3 in range(GameData.WORLD_COLS - 1):
			var pa := Vector2(float(cx3) * 32.0 + 16.0, float(cy3) * 32.0 + 16.0)
			var pb := pa + Vector2(32.0, 0.0)
			var de := absf(GameData.cell_elev(cx3, cy3) - GameData.cell_elev(cx3 + 1, cy3))
			if not has_cliff and de >= GameData.CLIFF_STEP:
				c_a = pa
				c_b = pb
				has_cliff = true
			if not has_deep and GameData.cell_depth(cx3, cy3) > 0.5:
				deep = pa
				has_deep = true
			if not has_flat and de < GameData.CLIFF_STEP and GameData.cell_depth(cx3, cy3) <= 0.0 and GameData.cell_depth(cx3 + 1, cy3) <= 0.0:
				f_a = pa
				f_b = pb
				has_flat = true
	_check("崖**不再**挡路（用户定案「不要墙」：高差多大都能走，高度只做视觉）",
			has_cliff and GameData.can_step(c_a, c_b), "崖样本 %s → %s" % [c_a, c_b])
	_check("深水挡住玩家（只能绕行或将来做桥/舟）",
			has_deep and not GameData.can_step(deep - Vector2(32.0, 0.0), deep), "深水样本 %s" % deep)
	_check("平地能走（别把正常移动也挡了）",
			has_flat and GameData.can_step(f_a, f_b), "平地样本 %s → %s" % [f_a, f_b])
	_check("涉水减速、高地略慢（地形有分量）",
			has_deep and GameData.speed_mult_at(deep) < 1.0,
			"深水倍率 %.2f" % GameData.speed_mult_at(deep))
	_check("同一格内自由移动（不会被自己的格子挡住）",
			GameData.can_step(Vector2(100.0, 100.0), Vector2(104.0, 103.0)), "同格微动")

	_st_done = true                  # ⭐ 只有全程没抛异常才会走到这（假绿灯的判据）


## ⭐ 自测收尾：**异常路径也必须执行**。
##    正常路径由 `_run_selftest()` 直接调；主体中途抛异常时由 `_process()` 兜底调 —— 见下面的守卫。
##    ⚠️ `_st_finished` 保证只跑一次（两条路径不会重复 quit）。
func _selftest_finish() -> void:
	if _st_finished:
		return
	_st_finished = true
	var total := _pass + _fail
	if not _st_done:
		# ⭐ 这才是"假绿灯"的根因修法：没跑完 ≠ 全过，它是一次明确的失败。
		_fail += 1
		print("[FAIL] 自测**没跑完**（中途抛异常中断，只完成 %d 项）—— 这不是绿灯" % total)
	_check("断言总数不低于基线 %d（只能涨不能跌；删断言必红）" % SELFTEST_MIN,
			total >= SELFTEST_MIN, "实际 %d 项" % total)
	print("通过 %d 项，失败 %d 项" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
