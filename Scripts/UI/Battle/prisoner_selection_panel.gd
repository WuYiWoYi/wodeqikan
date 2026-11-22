class_name PrisonerSelectionPanel
extends Control
## 战后俘虏选择界面（阶段 13 Step 5）。
##
## 左栏：本次战斗分配给玩家部队的可接收俘虏。
## 右栏：玩家当前持有的俘虏（已有俘虏只读展示）+ 本次已选择接收的俘虏。
##
## 所有点击只修改本地预览列表；只有确认时由 BattleManager 统一提交真实归属。
## UI 不直接修改 UnitData/PartyData。

signal committed(accepted_unit_ids: Array)

const WINDOW_SIZE := Vector2(880.0, 560.0)
const ROW_MIN_HEIGHT := 34.0

var _unit_manager: UnitManager = null
## 本次分配给玩家、尚未接收的俘虏。
var _left_ids: Array[String] = []
## 玩家进入界面前已经持有的俘虏（只读）。
var _existing_ids: Array[String] = []
## 本次已选择接收的俘虏（确认后提交）。
var _accepted_ids: Array[String] = []
var _committed: bool = false

var _left_list: VBoxContainer = null
var _right_list: VBoxContainer = null
var _left_empty: Label = null
var _right_empty: Label = null
var _status_label: Label = null
var _confirm_button: Button = null
var _reset_button: Button = null


## allocated_ids：本次分配给玩家的俘虏；existing_ids：玩家已有俘虏。
func setup(
	unit_manager: UnitManager,
	allocated_ids: Array,
	existing_ids: Array = []
) -> void:
	_unit_manager = unit_manager
	_left_ids.clear()
	for value: Variant in allocated_ids:
		var unit_id: String = str(value)
		if not unit_id.is_empty() and not _left_ids.has(unit_id):
			_left_ids.append(unit_id)
	_existing_ids.clear()
	for value: Variant in existing_ids:
		var unit_id: String = str(value)
		if not unit_id.is_empty() and not _existing_ids.has(unit_id):
			_existing_ids.append(unit_id)
	_accepted_ids.clear()
	_committed = false
	visible = true
	if _left_list == null:
		_build()
	_refresh()


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_full_rect(self)

	var dim := ColorRect.new()
	dim.name = "PrisonerDim"
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_set_full_rect(dim)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "PrisonerPanel"
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
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := _make_label("接收俘虏", 24)
	title.name = "PrisonerTitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var hint := _make_label(
		"点击左侧俘虏将其加入接收列表；点击右侧本次接收的俘虏可撤回。确认后不可撤销。",
		12
	)
	hint.name = "PrisonerHintLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)

	var lists := HBoxContainer.new()
	lists.name = "PrisonerLists"
	lists.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lists.add_theme_constant_override("separation", 16)
	column.add_child(lists)

	var left_column := VBoxContainer.new()
	left_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lists.add_child(left_column)
	var left_title := _make_label("本次分配（待接收）", 15)
	left_title.name = "PrisonerLeftTitle"
	left_column.add_child(left_title)
	_left_list = _make_scroll_list("PrisonerLeftList", left_column)
	_left_empty = _make_label("没有待接收的俘虏。", 12)
	_left_empty.name = "PrisonerLeftEmpty"
	left_column.add_child(_left_empty)

	var right_column := VBoxContainer.new()
	right_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lists.add_child(right_column)
	var right_title := _make_label("接收列表 / 当前俘虏", 15)
	right_title.name = "PrisonerRightTitle"
	right_column.add_child(right_title)
	_right_list = _make_scroll_list("PrisonerRightList", right_column)
	_right_empty = _make_label("尚未选择接收俘虏。", 12)
	_right_empty.name = "PrisonerRightEmpty"
	right_column.add_child(_right_empty)

	_status_label = _make_label("", 12)
	_status_label.name = "PrisonerStatusLabel"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status_label)

	var buttons := HBoxContainer.new()
	buttons.name = "PrisonerButtons"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	column.add_child(buttons)

	_reset_button = _make_button("一键重置", "PrisonerResetButton")
	_reset_button.pressed.connect(reset_selection)
	buttons.add_child(_reset_button)

	_confirm_button = _make_button("确认接收", "PrisonerConfirmButton")
	_confirm_button.pressed.connect(_on_confirm_pressed)
	buttons.add_child(_confirm_button)


func _make_scroll_list(node_name: String, parent: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 300.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = node_name
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	return list


func _refresh() -> void:
	_clear_list(_left_list)
	_clear_list(_right_list)

	# 左栏：本次分配但尚未接收。
	for unit_id: String in _left_ids:
		if _accepted_ids.has(unit_id):
			continue
		var button := _make_prisoner_button(unit_id, false)
		button.name = "PrisonerLeft_%s" % unit_id
		button.pressed.connect(_on_left_pressed.bind(unit_id))
		_left_list.add_child(button)

	# 右栏：已有俘虏（只读）+ 本次已接收。
	for unit_id: String in _existing_ids:
		var existing := _make_prisoner_button(unit_id, false)
		existing.name = "PrisonerExisting_%s" % unit_id
		existing.disabled = true
		existing.modulate = Color(0.78, 0.78, 0.74)
		_right_list.add_child(existing)
	for unit_id: String in _accepted_ids:
		var accepted := _make_prisoner_button(unit_id, true)
		accepted.name = "PrisonerAccepted_%s" % unit_id
		accepted.pressed.connect(_on_right_pressed.bind(unit_id))
		_right_list.add_child(accepted)

	var left_count: int = _left_ids.size() - _accepted_ids.size()
	_left_empty.visible = left_count <= 0
	_right_empty.visible = _existing_ids.is_empty() and _accepted_ids.is_empty()
	_status_label.text = "待接收 %d / 本次已选择 %d / 当前持有 %d" % [
		maxi(0, left_count), _accepted_ids.size(), _existing_ids.size()
	]
	_reset_button.disabled = _accepted_ids.is_empty() or _committed
	_confirm_button.disabled = _committed


func _make_prisoner_button(unit_id: String, can_withdraw: bool) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0.0, ROW_MIN_HEIGHT)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	var suffix := "    撤回" if can_withdraw else ""
	button.text = "%s%s" % [_describe_unit(unit_id), suffix]
	return button


func _describe_unit(unit_id: String) -> String:
	if _unit_manager == null:
		return unit_id
	var unit := _unit_manager.get_unit(unit_id)
	if unit == null:
		return unit_id
	var unit_name: String = unit.display_name
	var config := _unit_manager.get_unit_config(unit.config_id)
	if unit_name.is_empty() and config != null:
		unit_name = config.display_name
	if unit_name.is_empty():
		unit_name = unit_id
	var identity: String = config.display_name if config != null else unit.config_id
	return "%s    Lv.%d    %s" % [unit_name, unit.level, identity]


func _clear_list(list: VBoxContainer) -> void:
	if list == null:
		return
	for child: Node in list.get_children():
		list.remove_child(child)
		child.queue_free()


func _on_left_pressed(unit_id: String) -> void:
	if _committed or not _left_ids.has(unit_id) or _accepted_ids.has(unit_id):
		return
	_accepted_ids.append(unit_id)
	_refresh()


func _on_right_pressed(unit_id: String) -> void:
	if _committed or not _accepted_ids.has(unit_id):
		return
	_accepted_ids.erase(unit_id)
	_refresh()


## 恢复打开界面时的初始分配（已有俘虏不受影响）。
func reset_selection() -> void:
	if _committed:
		return
	_accepted_ids.clear()
	_refresh()


func _on_confirm_pressed() -> void:
	if _committed:
		return
	_committed = true
	_confirm_button.disabled = true
	_reset_button.disabled = true
	committed.emit(_accepted_ids.duplicate())


# ---------------------------------------------------------------------------
# 测试/外部只读入口
# ---------------------------------------------------------------------------


func get_left_ids() -> Array[String]:
	var result: Array[String] = []
	for unit_id: String in _left_ids:
		if not _accepted_ids.has(unit_id):
			result.append(unit_id)
	return result


func get_accepted_ids() -> Array[String]:
	return _accepted_ids.duplicate()


func get_existing_ids() -> Array[String]:
	return _existing_ids.duplicate()


func is_committed() -> bool:
	return _committed


func select_left(unit_id: String) -> void:
	_on_left_pressed(unit_id)


func withdraw_accepted(unit_id: String) -> void:
	_on_right_pressed(unit_id)


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _make_button(text: String, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(160.0, 38.0)
	button.focus_mode = Control.FOCUS_NONE
	return button


func _set_full_rect(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0
