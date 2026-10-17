extends Node2D
## 渲染器能力探针（技术风险实测，不是游戏内容）
##
## ⭐ 为什么需要它：项目用的是 **GL Compatibility** 渲染后端（见 project.godot 的
##    rendering/renderer/rendering_method）。网上大量 Godot 2D 特效教程默认你在用
##    Forward+，照抄到 Compatibility 上会**静默失效** —— 不报错，只是什么都没发生。
##
## 这个探针把「到底支不支持」变成**可读回的数字**：同一帧缓冲里采样开关光源 / 开关
## 屏幕纹理 shader / GPU 粒子 vs CPU 粒子 前后的像素值，然后判定。
##
## 结果全部以 FXPROBE 开头打进游戏日志。
## 跑法：project_run(mode="custom", scene="res://tests/fx_probe.tscn")

var _bg: ColorRect
var _light: PointLight2D
var _overlay: ColorRect
var _gpu: GPUParticles2D
var _cpu: CPUParticles2D
var _vsize := Vector2(1366.0, 768.0)

func _ready() -> void:
	_build()
	_run()

## ---------- 搭建 ----------
func _build() -> void:
	_vsize = get_viewport().get_visible_rect().size

	_bg = ColorRect.new()
	_bg.color = Color(0.25, 0.25, 0.25, 1.0)        # 中灰底：亮度和反色都最容易判断
	_bg.size = _vsize
	_bg.z_index = -10
	add_child(_bg)

	# 程序化生成光照贴图：径向渐变，不需要美术画
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var ltex := GradientTexture2D.new()
	ltex.gradient = grad
	ltex.width = 256
	ltex.height = 256
	ltex.fill = GradientTexture2D.FILL_RADIAL
	ltex.fill_from = Vector2(0.5, 0.5)
	ltex.fill_to = Vector2(1.0, 0.5)

	_light = PointLight2D.new()
	_light.texture = ltex
	_light.texture_scale = 2.5
	_light.energy = 2.0
	_light.position = _vsize * Vector2(0.5, 0.5)
	_light.enabled = false
	add_child(_light)

	# 屏幕纹理 shader：反色。生效 → 采样值应等于 1 - 底色
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\n" \
		+ "uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;\n" \
		+ "void fragment() {\n" \
		+ "    vec3 s = texture(screen_tex, SCREEN_UV).rgb;\n" \
		+ "    COLOR = vec4(vec3(1.0) - s, 1.0);\n" \
		+ "}\n"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_overlay = ColorRect.new()
	_overlay.material = mat
	_overlay.size = _vsize
	_overlay.z_index = 20
	_overlay.visible = false
	add_child(_overlay)

	# GPU 粒子（左）与 CPU 粒子（右）做对照：原地不动，保证盖住采样点
	_gpu = GPUParticles2D.new()
	_gpu.position = _vsize * Vector2(0.3, 0.5)
	_gpu.amount = 128
	_gpu.lifetime = 1.5
	_gpu.preprocess = 0.8
	_gpu.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 14.0
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 3.0
	pm.scale_max = 7.0
	pm.color = Color(1, 1, 1, 1)
	_gpu.process_material = pm
	add_child(_gpu)

	_cpu = CPUParticles2D.new()
	_cpu.position = _vsize * Vector2(0.7, 0.5)
	_cpu.amount = 128
	_cpu.lifetime = 1.5
	_cpu.preprocess = 0.8
	_cpu.local_coords = false
	_cpu.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_cpu.emission_sphere_radius = 14.0
	_cpu.direction = Vector2(0, -1)
	_cpu.spread = 180.0
	_cpu.initial_velocity_min = 0.0
	_cpu.initial_velocity_max = 0.0
	_cpu.gravity = Vector2.ZERO
	_cpu.scale_amount_min = 3.0
	_cpu.scale_amount_max = 7.0
	_cpu.color = Color(1, 1, 1, 1)
	add_child(_cpu)

## ---------- 采样 ----------
func _settle(frames: int = 4) -> void:
	for i in range(frames):
		await get_tree().process_frame

func _grab() -> Image:
	await RenderingServer.frame_post_draw
	var vt := get_viewport().get_texture()
	return vt.get_image() if vt != null else null

## 取一小片区域里最亮/最暗的像素，避免粒子随机位置导致的漏采样
func _sample(at: Vector2i, radius: int = 4, brightest: bool = true) -> Color:
	var img := await _grab()
	if img == null or img.get_width() == 0:
		return Color(-1, -1, -1, -1)                 # 哨兵值：读不回来
	var best := img.get_pixel(clampi(at.x, 0, img.get_width() - 1), clampi(at.y, 0, img.get_height() - 1))
	for y in range(at.y - radius, at.y + radius + 1):
		for x in range(at.x - radius, at.x + radius + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var c := img.get_pixel(x, y)
			var better: bool = c.get_luminance() > best.get_luminance() if brightest else c.get_luminance() < best.get_luminance()
			if better:
				best = c
	return best

func _v(x: float) -> float:
	return snappedf(x, 0.001)

## ---------- 跑测试 ----------
func _run() -> void:
	await _settle(6)
	var center := Vector2i(int(_vsize.x * 0.5), int(_vsize.y * 0.5))
	var p_gpu := Vector2i(int(_vsize.x * 0.3), int(_vsize.y * 0.5))
	var p_cpu := Vector2i(int(_vsize.x * 0.7), int(_vsize.y * 0.5))

	print("FXPROBE viewport=%s renderer=%s" % [str(_vsize), RenderingServer.get_video_adapter_name()])

	# ---- ① PointLight2D 是否生效 ----
	_light.enabled = false
	await _settle()
	var base := await _sample(center)
	_light.enabled = true
	await _settle()
	var lit := await _sample(center)
	var d_light := _v(lit.get_luminance() - base.get_luminance())
	print("FXPROBE light  base=%s  lit=%s  delta=%+.3f  VERDICT=%s" % [
		str(base.to_html(false)), str(lit.to_html(false)), d_light,
		"PASS" if d_light > 0.03 else "FAIL"])

	# ---- ② hint_screen_texture 是否生效 ----
	_light.enabled = false
	_overlay.visible = true
	await _settle()
	var inv := await _sample(center)
	var expect := 1.0 - base.r
	var d_screen: float = abs(inv.r - expect)
	print("FXPROBE screen base=%s  inverted=%s  expect_r=%.3f  diff=%.3f  VERDICT=%s" % [
		str(base.to_html(false)), str(inv.to_html(false)), expect, d_screen,
		"PASS" if (d_screen < 0.06 and inv.r < 0.97) else "FAIL"])
	_overlay.visible = false

	# ---- ③ GPU 粒子 vs CPU 粒子 ----
	await _settle(45)
	var s_gpu := await _sample(p_gpu, 6)
	var s_cpu := await _sample(p_cpu, 6)
	var d_gpu := _v(s_gpu.get_luminance() - base.get_luminance())
	var d_cpu := _v(s_cpu.get_luminance() - base.get_luminance())
	print("FXPROBE gpu_particles sample=%s delta=%+.3f VERDICT=%s" % [
		str(s_gpu.to_html(false)), d_gpu, "PASS" if d_gpu > 0.1 else "FAIL"])
	print("FXPROBE cpu_particles sample=%s delta=%+.3f VERDICT=%s" % [
		str(s_cpu.to_html(false)), d_cpu, "PASS" if d_cpu > 0.1 else "FAIL"])

	# 停在一个好看的状态，方便截图留证
	_light.enabled = true
	print("FXPROBE done")
