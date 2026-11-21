class_name SettlementNameTag
extends Control
## 固定屏幕 UI 中的地点名称标签。
##
## 名称由大地图每帧把地点世界坐标转换为屏幕坐标后定位，
## 位于圆形标记正上方；文字大小不随相机缩放，但仍然跟随建筑移动。
## 整个标签忽略鼠标，不参与地点点击、选择或悬浮判定。
## 名称只绑定 SettlementData.settlement_id，同名村庄不会合并。

const TAG_WIDTH: float = 180.0
const TAG_HEIGHT: float = 26.0

var settlement: SettlementData = null
var _name_label: Label = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(TAG_WIDTH, TAG_HEIGHT)
	size = Vector2(TAG_WIDTH, TAG_HEIGHT)


func setup(data: SettlementData) -> void:
	settlement = data
	_create_label()
	queue_redraw()


## anchor 为标记顶部上方一点的屏幕坐标；标签整体位于该点上方并水平居中。
func set_screen_position(anchor: Vector2) -> void:
	position = anchor - Vector2(TAG_WIDTH * 0.5, TAG_HEIGHT)


func get_name_text() -> String:
	return _name_label.text if _name_label != null else ""


func _create_label() -> void:
	if _name_label != null:
		_name_label.queue_free()
	_name_label = Label.new()
	_name_label.name = "SettlementNameLabel"
	_name_label.text = settlement.display_name if settlement != null else ""
	_name_label.position = Vector2.ZERO
	_name_label.size = Vector2(TAG_WIDTH, TAG_HEIGHT)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	add_child(_name_label)
