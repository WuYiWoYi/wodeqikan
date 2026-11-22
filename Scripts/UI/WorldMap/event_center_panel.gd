class_name EventCenterPanel
extends Control
## 主界面事件中心：左侧事件列表，右侧选中事件详情。
##
## 面板只展示 EventCenter 聚合出的现有系统状态，不生成任务、不结算事件。
## 打开/关闭的暂停原因由 WorldMap 管理；本面板只发出 closed 信号。

signal closed

const WINDOW_SIZE := Vector2(1080.0, 640.0)
const LIST_WIDTH: float = 320.0

var _context: WorldContext = null
var _events: Array[Dictionary] = []
var _selected_event_id: String = ""
var _signature: String = ""

var _list: VBoxContainer = null
var _detail_title: Label = null
var _detail_body: Label = null
var _empty_detail: Label = null
var _item_buttons: Dictionary = {}


func setup(context: WorldContext) -> void:
	_context = context
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_full_rect(self)
	_build()


func open() -> void:
	visible = true
	refresh(true)


func close() -> void:
	visible = false
	closed.emit()


## 只在事件数据发生变化时重建列表；每帧调用是安全的。
func refresh_if_needed() -> void:
	refresh(false)


func refresh(force: bool = false) -> void:
	if not visible and not force:
		return
	if _context == null or _context.event_center == null:
		return
	var events: Array[Dictionary] = _context.event_center.get_events()
	var signature: String = _build_signature(events)
	if not force and signature == _signature:
		return
	_signature = signature
	_events = events
	_rebuild_list()


func get_event_ids() -> Array[String]:
	var ids: Array[String] = []
	for event: Dictionary in _events:
		ids.append(str(event.get("event_id", "")))
	return ids


func get_selected_event_id() -> String:
	return _selected_event_id


func get_detail_text() -> String:
	if _detail_body == null:
		return ""
	return _detail_body.text


func select_event(event_id: String) -> void:
	if not _item_buttons.has(event_id):
		return
	_selected_event_id = event_id
	_apply_selection()


func _build_signature(events: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for event: Dictionary in events:
		parts.append("%s|%s|%s" % [
			str(event.get("event_id", "")),
			str(event.get("title", "")),
			str(event.get("detail", "")),
		])
	return "||".join(parts)


func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "EventCenterDim"
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_set_full_rect(dim)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "EventCenterPanel"
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -WINDOW_SIZE.x * 0.5
	panel.offset_top = -WINDOW_SIZE.y * 0.5
	panel.offset_right = WINDOW_SIZE.x * 0.5
	panel.offset_bottom = WINDOW_SIZE.y * 0.5
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)

	var title := Label.new()
	title.name = "EventCenterTitle"
	title.text = "事件"
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_button := Button.new()
	close_button.name = "EventCenterCloseButton"
	close_button.text = "关闭"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(64.0, 30.0)
	close_button.pressed.connect(close)
	header.add_child(close_button)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size = Vector2(LIST_WIDTH, 0.0)
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(left_panel)

	var left_scroll := ScrollContainer.new()
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(left_scroll)

	_list = VBoxContainer.new()
	_list.name = "EventCenterList"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	left_scroll.add_child(_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)

	_detail_title = Label.new()
	_detail_title.name = "EventCenterDetailTitle"
	_detail_title.add_theme_font_size_override("font_size", 20)
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_detail_title)

	right.add_child(HSeparator.new())

	var detail_scroll := ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(detail_scroll)

	_detail_body = Label.new()
	_detail_body.name = "EventCenterDetailBody"
	_detail_body.add_theme_font_size_override("font_size", 15)
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_detail_body)

	_empty_detail = Label.new()
	_empty_detail.name = "EventCenterEmptyDetail"
	_empty_detail.text = "选择左侧事件查看详情。"
	_empty_detail.add_theme_font_size_override("font_size", 15)
	_empty_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_empty_detail)


func _rebuild_list() -> void:
	if _list == null:
		return
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_item_buttons.clear()

	var quests: Array[Dictionary] = []
	var pending: Array[Dictionary] = []
	for event: Dictionary in _events:
		if str(event.get("type", "")) == "QUEST":
			quests.append(event)
		else:
			pending.append(event)

	_add_section_header("已接取任务（%d）" % quests.size())
	if quests.is_empty():
		_add_empty_row("暂无已接取的任务。")
	else:
		for event: Dictionary in quests:
			_add_event_button(event)

	_add_section_header("待处理事项（%d）" % pending.size())
	if pending.is_empty():
		_add_empty_row("当前没有需要处理的事项。")
	else:
		for event: Dictionary in pending:
			_add_event_button(event)

	var valid_id: bool = false
	for event: Dictionary in _events:
		if str(event.get("event_id", "")) == _selected_event_id:
			valid_id = true
			break
	if not valid_id:
		_selected_event_id = str(_events[0].get("event_id", "")) \
			if not _events.is_empty() else ""
	_apply_selection()


func _add_section_header(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.custom_minimum_size = Vector2(0.0, 30.0)
	_list.add_child(label)


func _add_empty_row(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate = Color(1.0, 1.0, 1.0, 0.65)
	_list.add_child(label)


func _add_event_button(event: Dictionary) -> void:
	var event_id: String = str(event.get("event_id", ""))
	if event_id.is_empty():
		return
	var button := Button.new()
	button.name = "EventCenterItem_%s" % _safe_node_suffix(event_id)
	button.text = "[%s] %s" % [
		str(event.get("type_text", "事件")), str(event.get("title", "未命名事件"))
	]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(0.0, 38.0)
	button.pressed.connect(select_event.bind(event_id))
	_list.add_child(button)
	_item_buttons[event_id] = button


func _apply_selection() -> void:
	for event_id_value: Variant in _item_buttons:
		var event_id: String = str(event_id_value)
		var button := _item_buttons[event_id] as Button
		if button != null:
			button.button_pressed = event_id == _selected_event_id

	var event := _find_event(_selected_event_id)
	if event.is_empty():
		_detail_title.text = "事件"
		_detail_body.text = ""
		_empty_detail.visible = true
		return
	_empty_detail.visible = false
	_detail_title.text = "[%s] %s" % [
		str(event.get("type_text", "事件")), str(event.get("title", ""))
	]
	_detail_body.text = str(event.get("detail", ""))


func _find_event(event_id: String) -> Dictionary:
	for event: Dictionary in _events:
		if str(event.get("event_id", "")) == event_id:
			return event
	return {}


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
