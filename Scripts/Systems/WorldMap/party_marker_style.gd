class_name PartyMarkerStyle
extends Resource
## 大地图部队圆形标记的集中样式配置。
##
## 图标大小、边框、旗帜缩放与人数位置都从这里读取，
## PartyIcon 不各自硬编码尺寸。

@export_category("Marker")
## 标准圆形标记半径。所有部队类型共用该尺寸，保持扩编前的原始大小。
@export var marker_radius: float = 18.0
@export var border_width: float = 2.0
@export var shadow_offset_y: float = 10.0
@export var shadow_radius: float = 12.0
@export var marker_fill_color: Color = Color(0.11, 0.13, 0.16, 0.92)
@export var marker_border_color: Color = Color(0.86, 0.82, 0.70, 0.95)
@export var player_ring_color: Color = Color("#4ea1ff")
## 阵营回退色：没有家族颜色时由 PartyIcon 统一读取，避免每种部队各写一套绘制。
@export var faction_colors: Dictionary = {
	"FACTION_PLAYER": Color("#2f7fdd"),
	"FACTION_LOCAL": Color("#4d8c57"),
	"FACTION_MERCHANT": Color("#c7992e"),
	"FACTION_BANDIT": Color("#b94b42"),
	"FACTION_GUARD": Color("#338c8f"),
}

@export_category("Flag")
## 旗帜等比缩放后的最大边长（像素，按贴图画布计算）。
## 当前家族旗帜为 48×48 画布、有效像素约 30×36；44 让有效旗帜接近内圆，
## 同时保留遮罩留白，不覆盖外圈边框。圆形底盘、边框和点击区域不受影响。
@export var flag_max_size: float = 44.0
@export var flag_vertical_offset: float = 0.0

@export_category("Count")
@export var count_offset: Vector2 = Vector2(0.0, 24.0)
@export var count_font_size: int = 16


## 阵营回退色；未知阵营使用默认敌方色。
func get_faction_color(faction_id: String, fallback: Color) -> Color:
	var value: Variant = faction_colors.get(faction_id)
	if value is Color:
		return value
	return fallback


## 旗帜遮罩的 UV 半径：把旗帜裁剪到圆形边框内缘。
## flag_max_size 对应 UV 长度 1.0，因此 UV 半径 = 世界半径 / 旗帜边长。
func get_flag_clip_uv_radius() -> float:
	if flag_max_size <= 0.0:
		return 0.5
	var clip_radius: float = maxf(1.0, marker_radius - border_width * 0.5)
	return clampf(clip_radius / flag_max_size, 0.05, 0.5)


static func create_default() -> PartyMarkerStyle:
	return PartyMarkerStyle.new()
