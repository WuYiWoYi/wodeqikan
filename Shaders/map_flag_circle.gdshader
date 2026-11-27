shader_type canvas_item;
// 旗帜圆形遮罩：把方形/矩形旗帜裁剪成正圆，与圆形底盘/描边配合；
// 不修改原始贴图与宽高比。
//
// 两种模式：
// 1) use_local_circle = true：在画布局部像素空间按显式圆心/半径裁剪。
//    这是部队标记使用的模式：圆心与半径直接对应 PartyIcon 的 draw_circle /
//    draw_arc 坐标系，不受 AtlasTexture 图集 UV、旗帜宽高比或父节点缩放影响，
//    因此主体、黑色描边、旗帜遮罩与白色悬浮描边共用同一圆心与半径基准。
// 2) use_local_circle = false（默认）：沿用 UV 遮罩，仅供地点徽章等既有调用，
//    保持其原有表现不变。
uniform bool use_local_circle = false;
uniform vec2 circle_center = vec2(0.0);
uniform float circle_radius = 0.0;
uniform float uv_radius : hint_range(0.05, 0.5) = 0.5;
uniform float uv_aspect : hint_range(0.1, 10.0) = 1.0;

varying vec2 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	if (use_local_circle) {
		// VERTEX 为画布局部坐标；circle_center/circle_radius 也使用同一局部像素单位。
		if (circle_radius > 0.0 && length(local_position - circle_center) > circle_radius) {
			discard;
		}
	} else {
		vec2 centered_uv = (UV - vec2(0.5)) * vec2(uv_aspect, 1.0);
		if (length(centered_uv) > uv_radius) {
			discard;
		}
	}
	vec4 tex = texture(TEXTURE, UV) * COLOR;
	if (tex.a < 0.02) {
		discard;
	}
	COLOR = tex;
}
