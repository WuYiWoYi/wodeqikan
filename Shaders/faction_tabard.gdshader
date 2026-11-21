shader_type canvas_item;
// 临时阵营罩袍着色：只替换占位身体贴图中的蓝色罩袍区域，
// 保留黑色描边与白色十字/高光。没有独立罩袍贴图时的临时方案。
uniform vec4 faction_color : source_color = vec4(0.25, 0.5, 0.88, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV) * COLOR;
	if (tex.a < 0.05) {
		discard;
	}

	// 只有明显偏蓝的像素属于罩袍区域。
	float blue_dominance = tex.b - max(tex.r, tex.g);
	if (blue_dominance < 0.15) {
		discard;
	}

	float luma = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	float shade = clamp(0.55 + luma, 0.55, 1.2);
	COLOR = vec4(faction_color.rgb * shade, tex.a * faction_color.a);
}
