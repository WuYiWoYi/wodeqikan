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
## 与玩家同阵营的持续外环；玩家本人仍使用 player_ring_color。
@export var allied_ring_color: Color = Color("#4fbf6a")
## 与玩家敌对的持续外环。
@export var hostile_ring_color: Color = Color("#d9534f")

@export_category("Outline")
## 加粗前的基础描边宽度（1.5 像素沿 marker_radius 绘制）。
## 仅用于锁定描边外缘位置：加粗时外缘保持在 18.75，厚度全部向圆内扩展。
const BASELINE_OUTLINE_WIDTH: float = 1.5
## 部队标记圆形主体的基础黑色描边：始终绘制。
## 外缘不随宽度变化，因此部队标记最外侧轮廓与整体视觉尺寸不变。
@export var outline_color: Color = Color(0.0, 0.0, 0.0, 1.0)
@export var outline_width: float = 2.5
## 鼠标悬浮时的白色描边：略粗，绘制在基础描边外侧，两者同时保留。
@export var hover_outline_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var hover_outline_width: float = 3.0
## 悬浮描边与圆形主体外缘之间的间隙，避免盖住基础黑色描边。
@export var hover_outline_gap: float = 4.0
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
## 当前家族旗帜为 48×48 画布、有效像素约 30×36；48 将有效内容等比放大到
## 最长边 48，保持放大观感同时留出更清晰的黑色描边。
## 圆形底盘、边框与点击区域不受影响，旗帜仍由 shader 裁到黑色描边内缘。
@export var flag_max_size: float = 48.0
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


## 黑色基础描边的外缘：锁定为加粗前的位置（marker_radius + 0.75），
## 任何加粗都不向外移动，因此标记最外侧轮廓位置保持不变。
func get_outline_outer_radius() -> float:
	return marker_radius + BASELINE_OUTLINE_WIDTH * 0.5


## 黑色基础描边的内缘：描边宽度全部向圆内延伸后到达的半径。
func get_outline_inner_radius() -> float:
	return maxf(0.0, get_outline_outer_radius() - maxf(0.0, outline_width))


## 旗帜圆形遮罩的世界半径：优先裁到黑色描边内缘，使旗帜填满圆内有效区域
## 且绝不压住描边本体；没有黑色描边时退回到原有边框内缘。
## PartyIcon 把该半径换算到旗帜精灵的局部像素空间后交给遮罩 shader，
## 与 draw_circle / draw_arc 共用同一圆心和半径基准。
func get_flag_clip_radius() -> float:
	if outline_width > 0.0:
		return clampf(get_outline_inner_radius(), 1.0, marker_radius)
	return maxf(1.0, marker_radius - border_width * 0.5)


static func create_default() -> PartyMarkerStyle:
	return PartyMarkerStyle.new()
