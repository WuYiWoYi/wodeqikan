shader_type canvas_item;
// 士兵部件统一材质：
// - 阵营罩袍模式：只替换占位身体贴图中的蓝色罩袍区域，保留黑色描边与白色十字/高光；
// - 普通部件模式：保持贴图原色，同时支持受击白闪；
// - 白闪通过每个角色独立的材质实例控制，避免一个角色受击影响其他角色。
uniform bool use_faction_color = true;
uniform vec4 faction_color : source_color = vec4(0.25, 0.5, 0.88, 1.0);
// 0 = 正常颜色，1 = 全白；同一角色连续受击时由表现层刷新/回落。
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV) * COLOR;
	if (use_faction_color) {
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
		tex = vec4(faction_color.rgb * shade, tex.a * faction_color.a);
	}

	COLOR = vec4(mix(tex.rgb, vec3(1.0), flash_amount), tex.a);
}
