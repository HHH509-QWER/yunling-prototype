// 后处理皮层：廉价泛光 + 色彩分级 + 暗角
// ⚠️ 我们的渲染器是 gl_compatibility ——**没有** Environment 的 glow/DOF，
//    所以泛光只能用「屏幕采样 + 亮部提取」这招，Effect 很轻但在这套美术下够用。
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float glow_strength : hint_range(0.0, 1.0) = 0.30;
uniform float threshold : hint_range(0.0, 1.0) = 0.72;
uniform float grade_strength : hint_range(0.0, 0.5) = 0.16;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.40;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = texture(screen_tex, uv).rgb;

	// —— 廉价泛光：4 个偏移采样，只留超过阈值的亮部 ——
	vec3 g = vec3(0.0);
	float o = 0.0035;
	g += max(texture(screen_tex, uv + vec2(o)).rgb - threshold, 0.0);
	g += max(texture(screen_tex, uv - vec2(o)).rgb - threshold, 0.0);
	g += max(texture(screen_tex, uv + vec2(0.0, o)).rgb - threshold, 0.0);
	g += max(texture(screen_tex, uv - vec2(0.0, o)).rgb - threshold, 0.0);
	c += g * glow_strength;

	// —— 色彩分级：暗部偏青、亮部偏暖（电影感）——
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, c * vec3(0.92, 0.98, 1.10), (1.0 - l) * grade_strength);
	c = mix(c, c * vec3(1.06, 1.02, 0.94), l * grade_strength);

	// —— 暗角：把视线压回中间 ——
	vec2 d = uv - vec2(0.5);
	float v = smoothstep(0.34, 0.80, sqrt(d.x * d.x + d.y * d.y) * 1.18);
	c *= (1.0 - v * vignette_strength);

	COLOR = vec4(c, 1.0);
}
