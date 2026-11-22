shader_type canvas_item;
// 大地图圆形旗帜遮罩：把方形/矩形旗帜裁剪成圆形，
// 与圆形底盘边框配合；不修改原始贴图与宽高比。
// uv_radius 由 PartyMarkerStyle 计算，允许旗帜大于圆形内径，
// 在边框内缘裁掉四角，保证所有部队标记视觉比例一致。
// uv_aspect 为有效贴图宽/高；裁掉透明边距后旗帜可能不是正方形，
// 用它把归一化 UV 换算到贴图像素比例，遮罩在屏幕上仍是正圆。
uniform float uv_radius : hint_range(0.05, 0.5) = 0.5;
uniform float uv_aspect : hint_range(0.1, 10.0) = 1.0;

void fragment() {
	vec2 centered_uv = (UV - vec2(0.5)) * vec2(uv_aspect, 1.0);
	if (length(centered_uv) > uv_radius) {
		discard;
	}
	vec4 tex = texture(TEXTURE, UV) * COLOR;
	if (tex.a < 0.02) {
		discard;
	}
	COLOR = tex;
}
