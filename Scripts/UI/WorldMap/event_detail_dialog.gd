class_name EventDetailDialog
extends Control
## 可操作事件详情弹窗（当前用于家族赎回请求）。
##
## UI 只发起意图：接受时调用 LordRansomManager.accept_ransom()，
## 取消只关闭弹窗，不支付金币、不移除事件。
## 每次刷新都从 EventCenter 重新读取当前世界状态；事件失效时自动关闭。

signal closed
signal accepted(ransom_id: String)

const WINDOW_SIZE := Vector2(560.0, 460.0)

var _context: WorldContext = null
var _event_id: String = ""
var _title_label: Label = null
var _body_label: Label = null
var _lord_label: Label = null
var _house_label: Label = null
var _gold_label: Label = null
var _status_label: Label = null
var _accept_button: Button = null
var _decline_button: Button = null
var _accepting: bool = false


func setup(context: WorldContext) -> void:
	_context = context
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_full_rect(self)
	visible = false
	_build()


func open(event_id: String) -> bool:
	if _context == null or _context.event_center == null:
		return false
	var event: Dictionary = _context.event_center.get_event(event_id)
	if event.is_empty() or not bool(event.get("actionable", false)):
		return false
	_event_id = event_id
	_accepting = false
	visible = true
	_refresh(event)
	return true


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## 每帧调用安全：弹窗打开期间持续校验事件是否仍然有效。
func refresh_if_needed() -> void:
	if not visible or _context == null or _context.event_center == null:
		return
	var event: Dictionary = _context.event_center.get_event(_event_id)
	if event.is_empty() or not bool(event.get("actionable", false)):
		close()
		return
	_refresh(event)


func get_event_id() -> String:
	return _event_id


func get_title_text() -> String:
	return _title_label.text if _title_label != null else ""


func get_body_text() -> String:
	return _body_label.text if _body_label != null else ""


func get_gold_text() -> String:
	return _gold_label.text if _gold_label != null else ""


func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "EventDetailDim"
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_set_full_rect(dim)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "EventDetailPanel"
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
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)

	_title_label = Label.new()
	_title_label.name = "EventDetailTitle"
	_title_label.text = "家族赎回请求"
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	var close_button := Button.new()
	close_button.name = "EventDetailCloseButton"
	close_button.text = "关闭"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(64.0, 30.0)
	close_button.pressed.connect(close)
	header.add_child(close_button)

	column.add_child(HSeparator.new())

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	column.add_child(info)

	_lord_label = _make_info_label("EventDetailLord", "领主：")
	info.add_child(_lord_label)
	_house_label = _make_info_label("EventDetailHouse", "家族：")
	info.add_child(_house_label)
	_gold_label = _make_info_label("EventDetailGold", "赎金：0 金币")
	info.add_child(_gold_label)

	column.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	_body_label = Label.new()
	_body_label.name = "EventDetailBody"
	_body_label.add_theme_font_size_override("font_size", 15)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body_label)

	_status_label = Label.new()
	_status_label.name = "EventDetailStatus"
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.modulate = Color(1.0, 0.92, 0.68, 0.9)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status_label)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)

	_decline_button = Button.new()
	_decline_button.name = "RansomDeclineButton"
	_decline_button.text = "取消"
	_decline_button.focus_mode = Control.FOCUS_NONE
	_decline_button.custom_minimum_size = Vector2(88.0, 34.0)
	_decline_button.pressed.connect(_on_decline_pressed)
	actions.add_child(_decline_button)

	_accept_button = Button.new()
	_accept_button.name = "RansomAcceptButton"
	_accept_button.text = "接受赎金"
	_accept_button.focus_mode = Control.FOCUS_NONE
	_accept_button.custom_minimum_size = Vector2(110.0, 34.0)
	_accept_button.pressed.connect(_on_accept_pressed)
	actions.add_child(_accept_button)


func _make_info_label(node_name: String, text: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	return label


func _refresh(event: Dictionary) -> void:
	if _title_label == null:
		return
	_title_label.text = str(event.get("title", "家族赎回请求"))
	_lord_label.text = "领主：%s" % str(event.get("lord_name", "未知"))
	_house_label.text = "家族：%s" % str(event.get("house_name", "未知"))
	_gold_label.text = "赎金：%d 金币" % int(event.get("gold", 0))
	_body_label.text = str(event.get("detail", ""))
	_status_label.text = ""
	_decline_button.text = str(event.get("decline_label", "取消"))
	_accept_button.disabled = _accepting or not bool(event.get("actionable", false))
	_decline_button.disabled = _accepting


## 出售赎回的“取消”只关闭弹窗；关押期赎买的“拒绝”还必须结束事件。
## 是否结束事件由事件数据（decline_ends_event）决定，UI 不判断来源类型。
func _on_decline_pressed() -> void:
	if _accepting:
		return
	var event: Dictionary = {}
	if _context != null and _context.event_center != null:
		event = _context.event_center.get_event(_event_id)
	if event.is_empty():
		close()
		return
	if bool(event.get("decline_ends_event", false)):
		var ransom_id: String = str(event.get("ransom_id", ""))
		if not ransom_id.is_empty() and _context.lord_ransom_manager != null:
			_context.lord_ransom_manager.reject_captive_ransom(ransom_id)
	close()


func _on_accept_pressed() -> void:
	if _accepting:
		return
	var ransom_id: String = str(
		_context.event_center.get_event(_event_id).get("ransom_id", "")
	)
	if ransom_id.is_empty():
		close()
		return
	_accepting = true
	_accept_button.disabled = true
	_decline_button.disabled = true
	var result: Dictionary = _context.lord_ransom_manager.accept_ransom(ransom_id)
	if not bool(result.get("success", false)):
		_accepting = false
		var event: Dictionary = _context.event_center.get_event(_event_id)
		if event.is_empty():
			close()
		else:
			_refresh(event)
			_status_label.text = str(result.get("reason", "赎回失败"))
		return
	visible = false
	accepted.emit(ransom_id)
	closed.emit()


func _set_full_rect(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0
