class_name EventFeed
extends Control
## 大地图右侧纵向事件框。
##
## 只展示 EventCenter 聚合出的“可操作事件”（当前为家族赎回请求）。
## 没有可操作事件时整体隐藏，不占用地图空间；点击条目发出意图信号，
## 打开详情由 WorldMap 决定，本控件不结算任何规则。

signal event_selected(event_id: String)

const WIDTH: float = 280.0
const TOP_OFFSET: float = 60.0
const MAX_HEIGHT: float = 430.0

var _context: WorldContext = null
var _list: VBoxContainer = null
var _count_label: Label = null
var _event_ids: Array[String] = []
var _signature: String = ""


func setup(context: WorldContext) -> void:
	_context = context
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -WIDTH - 12.0
	offset_right = -12.0
	offset_top = TOP_OFFSET
	offset_bottom = TOP_OFFSET + MAX_HEIGHT
	_build()
	refresh(true)


func refresh_if_needed() -> void:
	refresh(false)


func refresh(force: bool = false) -> void:
	if _context == null or _context.event_center == null:
		visible = false
		return
	var events: Array[Dictionary] = _context.event_center.get_actionable_events()
	var signature: String = _build_signature(events)
	if not force and signature == _signature:
		return
	_signature = signature
	_event_ids.clear()
	for event: Dictionary in events:
		_event_ids.append(str(event.get("event_id", "")))
	_rebuild(events)
	visible = not events.is_empty()


func get_event_ids() -> Array[String]:
	return _event_ids.duplicate()


func get_event_count() -> int:
	return _event_ids.size()


func _build_signature(events: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for event: Dictionary in events:
		parts.append("%s|%s|%s" % [
			str(event.get("event_id", "")),
			str(event.get("title", "")),
			str(event.get("gold", 0)),
		])
	return "||".join(parts)


func _build() -> void:
	var panel := PanelContainer.new()
	panel.name = "EventFeedPanel"
	_set_full_rect(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.10, 0.07, 0.92)
	style.border_color = Color(0.85, 0.68, 0.32, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	column.add_child(header)

	var title := Label.new()
	title.name = "EventFeedTitle"
	title.text = "待处理事件"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.96, 0.82, 0.52))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_count_label = Label.new()
	_count_label.name = "EventFeedCount"
	_count_label.add_theme_font_size_override("font_size", 13)
	_count_label.modulate = Color(1.0, 1.0, 1.0, 0.75)
	header.add_child(_count_label)

	column.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.name = "EventFeedScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0.0, MAX_HEIGHT - 74.0)
	column.add_child(scroll)

	_list = VBoxContainer.new()
	_list.name = "EventFeedList"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)


func _rebuild(events: Array[Dictionary]) -> void:
	if _list == null:
		return
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_count_label.text = "%d" % events.size()
	for event: Dictionary in events:
		_add_event_button(event)


func _add_event_button(event: Dictionary) -> void:
	var event_id: String = str(event.get("event_id", ""))
	if event_id.is_empty():
		return
	var button := Button.new()
	button.name = "EventFeedItem_%s" % _safe_node_suffix(event_id)
	var lord_name: String = str(event.get("lord_name", "领主"))
	var house_name: String = str(event.get("house_name", "家族"))
	var gold: int = int(event.get("gold", 0))
	var tag: String = str(event.get("tag", event.get("type_text", "赎回")))
	button.text = "[%s] %s\n%s · %s · %d 金币" % [
		tag,
		str(event.get("title", "家族赎回请求")),
		lord_name,
		house_name,
		gold,
	]
	button.tooltip_text = str(event.get("detail", ""))
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, 54.0)
	button.add_theme_font_size_override("font_size", 13)
	button.pressed.connect(_on_item_pressed.bind(event_id))
	_list.add_child(button)


func _on_item_pressed(event_id: String) -> void:
	event_selected.emit(event_id)


func _safe_node_suffix(value: String) -> String:
	var result: String = value
	for invalid: String in [":", "/", ".", "@", "%"]:
		result = result.replace(invalid, "_")
	return result


func _set_full_rect(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0
