class_name EventReminder
extends Control
## 大地图右侧的待处理事件提醒。
##
## 只展示 EventCenter 当前可操作事件的数量，不维护独立事件状态、不暂停世界。
## 提醒自身不决定打开哪个事件：点击只发出 open_requested，
## 由 WorldMap 根据当前事件数量打开详情或事件中心。

signal open_requested

const WIDTH: float = 232.0
const HEIGHT: float = 46.0
const RIGHT_MARGIN: float = 12.0

var _context: WorldContext = null
var _button: Button = null
var _event_ids: Array[String] = []
var _signature: String = ""


func setup(context: WorldContext) -> void:
	_context = context
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -WIDTH - RIGHT_MARGIN
	offset_right = -RIGHT_MARGIN
	offset_top = -HEIGHT * 0.5
	offset_bottom = HEIGHT * 0.5
	_build()
	refresh(true)


func refresh_if_needed() -> void:
	refresh(false)


## 事件集合变化时才重建文本；可见性始终由真实待处理事件数量决定。
func refresh(force: bool = false) -> void:
	if _context == null or _context.event_center == null:
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	var events: Array[Dictionary] = _context.event_center.get_actionable_events()
	var ids: Array[String] = []
	for event: Dictionary in events:
		ids.append(str(event.get("event_id", "")))
	var signature: String = "||".join(PackedStringArray(ids))
	if not force and signature == _signature:
		return
	_signature = signature
	_event_ids = ids
	if _button != null:
		_button.text = "有新的事件待处理（%d）" % ids.size()
		_button.disabled = ids.is_empty()
	visible = not ids.is_empty()
	mouse_filter = (
		Control.MOUSE_FILTER_STOP if visible else Control.MOUSE_FILTER_IGNORE
	)


func get_event_ids() -> Array[String]:
	return _event_ids.duplicate()


func get_event_count() -> int:
	return _event_ids.size()


func get_text() -> String:
	return _button.text if _button != null else ""


func _build() -> void:
	_button = Button.new()
	_button.name = "EventReminderButton"
	_button.focus_mode = Control.FOCUS_NONE
	_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_button.add_theme_font_size_override("font_size", 14)
	_button.add_theme_color_override("font_color", Color(0.98, 0.88, 0.62))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.12, 0.07, 0.94)
	style.border_color = Color(0.92, 0.72, 0.34, 0.95)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	_button.add_theme_stylebox_override("normal", style)
	_button.add_theme_stylebox_override("hover", style)
	_button.add_theme_stylebox_override("pressed", style)
	_button.pressed.connect(_on_pressed)
	_set_full_rect(_button)
	add_child(_button)


func _on_pressed() -> void:
	if _event_ids.is_empty():
		return
	open_requested.emit()


func _set_full_rect(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0
