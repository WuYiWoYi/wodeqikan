class_name SettlementNameTag
extends Control
## 固定屏幕 UI 中的地点名称组合：圆形家族徽章 + 地点名称。
##
## 布局：徽章在左、名称在右，同一水平线居中对齐；整体位于地点原有
## 大地图美术正上方。文字与徽章尺寸不随相机缩放，位置由世界坐标换算。
## 名称只绑定 SettlementData.settlement_id，同名村庄不会合并。
## 整个组合忽略鼠标，不参与地点点击、选择或悬浮判定。

const TAG_WIDTH: float = 240.0
const TAG_HEIGHT: float = 36.0
const BADGE_SIZE: float = 36.0
const BADGE_GAP: float = 8.0

var settlement: SettlementData = null
var _row: HBoxContainer = null
var _badge: FamilyBadge = null
var _name_label: Label = null


## 圆形家族徽章。只读取 FamilyConfig 的颜色，不参与世界坐标与点击。
class FamilyBadge extends Control:
	const RADIUS: float = 18.0
	const BORDER_COLOR: Color = Color(0.86, 0.82, 0.70, 0.95)

	var _family_color: Color = Color(0.45, 0.50, 0.58)
	var family_id: String = ""

	func setup(family: FamilyConfig) -> void:
		if family != null:
			_family_color = family.primary_color
			family_id = family.family_id
		queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(RADIUS * 2.0, RADIUS * 2.0)
		size = custom_minimum_size

	func _draw() -> void:
		draw_circle(Vector2(0.0, 2.0), RADIUS - 1.0, Color(0.0, 0.0, 0.0, 0.25))
		draw_circle(Vector2.ZERO, RADIUS, BORDER_COLOR)
		draw_circle(
			Vector2.ZERO,
			maxf(1.0, RADIUS - 2.5),
			_family_color.darkened(0.25)
		)
		# 统一的白色旗帜图形；家族身份由徽章底色表达。
		var white := Color(0.96, 0.94, 0.88, 0.96)
		draw_line(Vector2(-5.0, -9.0), Vector2(-5.0, 9.0), white, 2.0, true)
		draw_colored_polygon(
			PackedVector2Array([
				Vector2(-4.5, -9.0),
				Vector2(8.0, -5.0),
				Vector2(-4.5, -1.0),
			]),
			white
		)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(TAG_WIDTH, TAG_HEIGHT)
	size = Vector2(TAG_WIDTH, TAG_HEIGHT)


func setup(data: SettlementData, family: FamilyConfig = null) -> void:
	settlement = data
	_create_contents(family)
	queue_redraw()


## anchor 为地点美术顶部上方一点的屏幕坐标；组合整体位于该点上方并水平居中。
func set_screen_position(anchor: Vector2) -> void:
	position = anchor - Vector2(TAG_WIDTH * 0.5, TAG_HEIGHT)


func get_name_text() -> String:
	return _name_label.text if _name_label != null else ""


func has_family_badge() -> bool:
	return _badge != null and _badge.visible


func get_badge() -> Control:
	return _badge


## 徽章实际绑定的家族 ID；无徽章时为空。
func get_badge_family_id() -> String:
	return _badge.family_id if _badge != null and _badge.visible else ""


func get_name_label() -> Label:
	return _name_label


func _create_contents(family: FamilyConfig) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

	_row = HBoxContainer.new()
	_row.name = "SettlementNameRow"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", int(BADGE_GAP))
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_row)

	_badge = FamilyBadge.new()
	_badge.name = "SettlementFamilyBadge"
	_badge.visible = family != null
	_badge.setup(family)
	_row.add_child(_badge)

	_name_label = Label.new()
	_name_label.name = "SettlementNameLabel"
	_name_label.text = settlement.display_name if settlement != null else ""
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.theme = UiTheme.create()
	_name_label.add_theme_font_size_override("font_size", 15)
	_name_label.add_theme_color_override("font_color", Color("#f3ead6"))
	_name_label.add_theme_color_override(
		"font_shadow_color", Color(0.0, 0.0, 0.0, 0.85)
	)
	_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)
	_row.add_child(_name_label)
