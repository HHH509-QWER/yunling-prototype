// 溶解消散：fbm 噪声 + 阈值裁剪 + 边缘发光
// 迁移自 Unity 手写版 Assets/Shaders/Dissolve.shader（HLSL → GLSL，原理完全一致）
// 用途：怪物死亡消散 / 场景过渡 / 宝物出现
//
// ⚠️ 本项目渲染器是 gl_compatibility，discard 在 ES2 下可用，
//    但被丢弃的像素会破坏 early-z —— 只用在少量小物件上，别给全屏图层挂。
shader_type canvas_item;

uniform vec4 base_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float cutoff : hint_range(0.0, 1.0) = 0.0;
uniform float noise_scale : hint_range(0.1, 40.0) = 8.0;
uniform vec4 edge_color : source_color = vec4(1.0, 0.45, 0.12, 1.0);
uniform float edge_width : hint_range(0.001, 0.3) = 0.06;
uniform float edge_boost : hint_range(0.0, 8.0) = 4.0;

// —— 伪随机：同一坐标永远同一个值，可重现 ——
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// —— 值噪声：格点随机 + 双线性平滑插值 ——
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);   // 等价 smoothstep，让过渡不折线
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// —— fbm：频率翻倍、振幅减半，叠 4 层 ——
float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * value_noise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	// canvas_item 里的 COLOR 进来时已经是「贴图 × modulate」，直接当底色用
	float n = fbm(UV * noise_scale);

	// 阈值裁剪：噪声低于 cutoff 的像素直接杀掉
	if (n < cutoff) {
		discard;
	}

	// 等值带：贴着 cutoff 的那一圈像素 → 发光边缘
	float edge = 1.0 - smoothstep(cutoff, cutoff + edge_width, n);

	vec3 col = COLOR.rgb * base_tint.rgb + edge_color.rgb * edge * edge_boost;
	COLOR = vec4(col, COLOR.a);
}
