class_name ActorVisual
extends RefCounted
## 单位外观：**有贴图就画贴图，没有贴图就回退到形状（色块）**。
##
## ⭐ 和 GameData 里「加一枚印 = 加一行」是同一个哲学：
##    换美术 = 改数据表里的 visual 字段，各个 _draw() 一行都不用动。
##    这也是《像素美术规范》里「贴图落地」那一步的唯一入口。
##
## 数据表里的写法（整个 visual 可以省，省了就永远是色块）：
##     "visual": {
##         "texture": "res://art/units/player.png",  # 文件不存在 = 自动回退形状，不报错
##         "scale": 1.0,                              # 只认 1 / 2 这类整数倍 —— 像素风铁律
##         "offset": Vector2(0.0, -16.0),             # 相对碰撞中心的像素偏移
##     }
##
## ⚠️ 像素风两条铁律（改这个文件之前先读）：
##   ① 贴图按原始像素尺寸 1:1 显示。像素风九成的问题都出在「缩成非整数倍」上。
##   ② 位置对齐交给项目设置 rendering/2d/snap/snap_2d_transforms_to_pixel，
##      别在这里手写取整 —— 手写取整会把相机跟随搞成抖动。


## 取外观配置：永远返回 Dictionary，调用方不用判空。
static func cfg_of(data: Dictionary) -> Dictionary:
	var v: Variant = data.get("visual", null)
	return v if v is Dictionary else {}


## ⭐ 故意用 ResourceLoader.exists() 而不是 load() 之后判空：
##    美术还没画的时候，数据表里可以先写好路径，游戏照常跑，文件一放进去就自动生效。
static var _cache: Dictionary = {}

## 按路径取贴图（带缓存）。⭐ 缓存是必须的：_draw() 每帧都会问一次，不能每帧去查文件系统。
## null 也一起缓存 —— 所以「补上美术文件后」要重跑一次游戏才会显示出来。
static func texture_of_path(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		var res: Variant = load(path)
		if res is Texture2D:
			tex = res
	_cache[path] = tex
	return tex


## 按数据表里的**任意键**取贴图 —— 有的东西不止一态，比如采集点：
##     "visual": {"texture": "满的.png", "empty_texture": "空的.png"}
static func texture_named(data: Dictionary, key: String) -> Texture2D:
	return texture_of_path(str(cfg_of(data).get(key, "")))


## 有贴图且文件存在 → 返回 Texture2D；否则 null（调用方走形状回退）。
static func texture_of(data: Dictionary) -> Texture2D:
	return texture_of_path(str(cfg_of(data).get("texture", "")))


## ---- 动作（anims）----
## ⭐ 数据表里一个动作 = 一组帧 + 速率 + 是否循环：
##     "anims": {"cast": {"frames": [a.png, b.png], "fps": 10.0, "loop": false}}
##    加动作 = 加一行；播放由节点上的 _anim 状态机管，换美术不用改代码。

## 这个动作的帧数组（没有就返回空数组）
static func anim_frames(data: Dictionary, anim: String) -> Array:
	var anims: Variant = cfg_of(data).get("anims", null)
	if anims is Dictionary and (anims as Dictionary).has(anim):
		return ((anims as Dictionary)[anim] as Dictionary).get("frames", [])
	return []


## 这个动作有几帧
static func frame_count(data: Dictionary, anim: String) -> int:
	return anim_frames(data, anim).size()


## 这个动作每秒几帧（缺省 8）
static func anim_fps(data: Dictionary, anim: String) -> float:
	var anims: Variant = cfg_of(data).get("anims", null)
	if anims is Dictionary and (anims as Dictionary).has(anim):
		return float((((anims as Dictionary)[anim]) as Dictionary).get("fps", 8.0))
	return 8.0


## 这个动作循环吗（缺省 loop=true）
static func anim_loops(data: Dictionary, anim: String) -> bool:
	var anims: Variant = cfg_of(data).get("anims", null)
	if anims is Dictionary and (anims as Dictionary).has(anim):
		return bool((((anims as Dictionary)[anim]) as Dictionary).get("loop", true))
	return true


## 取某个动作的第 idx 帧（越界自动夹住）
static func texture_frame(data: Dictionary, anim: String, idx: int) -> Texture2D:
	var frames := anim_frames(data, anim)
	if frames.is_empty():
		return texture_of(data)
	return texture_of_path(str(frames[clampi(idx, 0, frames.size() - 1)]))


## 把一张**图标**按 1:1 居中画在 at（面板 / 背包 / HUD 用）。
## ⭐ 面板是**原生分辨率**（不跟世界 zoom），所以 32×32 图标 1:1 画出来就是 32px，正好一行。
static func draw_icon(ci: CanvasItem, tex: Texture2D, at: Vector2, alpha := 1.0) -> void:
	if tex == null:
		return
	var sz := Vector2(tex.get_width(), tex.get_height())
	ci.draw_texture_rect(tex, Rect2((at - sz * 0.5).round(), sz), false, Color(1.0, 1.0, 1.0, alpha))


## 把贴图以「碰撞圆心」为原点画出来。
## flash 0~1：挨打闪白（同一张图再叠一层白，不需要写着色器）
## bob：上下浮动的像素数（走路/漂浮表现）；alpha：整体透明度
static func draw_unit(ci: CanvasItem, tex: Texture2D, data: Dictionary, flash: float = 0.0,
		bob: float = 0.0, alpha: float = 1.0) -> void:
	var cfg := cfg_of(data)
	## 只认整数倍：0.5 倍会把一个美术像素劈成半个屏幕像素，整张图立刻变脏
	## ⚠️ 旧像素风铁律：scale 只认整数倍（不许 1.5 这种，会糊）。
	##    ⭐ 但 **HD（动画风）管线必须允许分数倍** —— 192px 的立绘要用 0.25 缩回 48 世界单位，
	##    否则会被强行取整成 1.0，人物瞬间变成 4 倍大的巨人。
	##    规则：>= 1 的仍然取整（保住旧行为）；< 1 的原样放行。
	var raw_scale := float(cfg.get("scale", 1.0))
	var k := raw_scale if raw_scale < 1.0 else maxf(roundf(raw_scale), 1.0)
	var sz := Vector2(tex.get_width(), tex.get_height()) * k
	var off := Vector2(cfg.get("offset", Vector2.ZERO)) + Vector2(0.0, bob)
	## 左上角取整：贴图边长是偶数时它本来就是整数，奇数边长（不规范）也不至于半像素糊掉
	var rect := Rect2((-sz * 0.5 + off).round(), sz)
	ci.draw_texture_rect(tex, rect, false, Color(1.0, 1.0, 1.0, alpha))
	if flash > 0.001:
		ci.draw_texture_rect(tex, rect, false, Color(1.0, 1.0, 1.0, alpha * clampf(flash, 0.0, 1.0) * 0.85))