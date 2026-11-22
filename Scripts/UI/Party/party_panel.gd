class_name PartyPanel
extends Control
## 玩家部队管理面板（大地图）。
##
## 只读取 PartyManager / UnitManager 的权威数据；不提供招募、解雇、装备更换等写操作。
## 打开与关闭由 WorldMap 负责时间暂停原因栈；本面板只发出 closed 信号。

signal closed

var _context: WorldContext = null
var _party: PartyData = null
var _selected_unit_id: String = ""
var _member_items: Dictionary = {}
## 当前部队携带的俘虏条目；与成员列表分开管理，但共用同一选中逻辑。
var _prisoner_items: Dictionary = {}

var _party_name_label: Label = null
var _faction_label: Label = null
var _member_count_label: Label = null
var _speed_label: Label = null
var _state_label: Label = null
var _movement_label: Label = null
var _target_label: Label = null
var _gold_label: Label = null
var _wage_label: Label = null
var _member_list: GridContainer = null
var _prisoner_list: GridContainer = null
var _empty_label: Label = null
var _prisoner_empty_label: Label = null
var _detail_panel: UnitDetailPanel = null


func setup(context: WorldContext) -> void:
	_context = context
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_full_rect(self)
	_build()


func open() -> void:
	visible = true
	refresh()


func close() -> void:
	visible = false
	closed.emit()


## 重新读取部队与单位数据。打开面板时调用一次，选中变化时只更新详情。
func refresh() -> void:
	if _context == null:
		return
	_party = _context.get_player_party()
	if _party == null:
		_show_party_missing()
		return

	var member_ids: Array[String] = _rebuild_member_list()
	var prisoner_ids: Array[String] = _rebuild_prisoner_list()
	var valid_ids: Array[String] = []
	valid_ids.append_array(member_ids)
	valid_ids.append_array(prisoner_ids)
	_party_name_label.text = _party.party_name
	_faction_label.text = "阵营：%s" % _faction_display_name(_party.faction_id)
	_member_count_label.text = "成员：%d　俘虏：%d" % [
		_party.member_unit_ids.size(), _party.prisoner_unit_ids.size()
	]
	_speed_label.text = "移动速度：%.1f" % _party.movement_speed
	_state_label.text = "部队状态：%s" % _battle_state_text(_party.battle_state)
	_gold_label.text = "金币：%d" % _context.player_profile.gold
	_wage_label.text = "每日工资：%d" % _context.party_manager.get_total_wage(
		_party.party_id
	)

	if _party.movement_state == PartyData.MovementState.MOVING:
		_movement_label.text = "移动状态：移动中"
		_target_label.text = "目标：(%d, %d)" % [
			int(round(_party.target_position.x)), int(round(_party.target_position.y))
		]
	else:
		_movement_label.text = "移动状态：待命"
		_target_label.text = "目标：%s" % (
			_party.current_target_id if not _party.current_target_id.is_empty() else "无"
		)

	if valid_ids.is_empty():
		_selected_unit_id = ""
		_detail_panel.clear()
		return
	if not valid_ids.has(_selected_unit_id):
		_selected_unit_id = valid_ids[0]
	_apply_selection()


func get_selected_unit_id() -> String:
	return _selected_unit_id


func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "PartyPanelDim"
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_set_full_rect(dim)
	add_child(dim)

	var window := PanelContainer.new()
	window.name = "PartyPanelWindow"
	window.anchor_left = 0.5
	window.anchor_top = 0.5
	window.anchor_right = 0.5
	window.anchor_bottom = 0.5
	# 横向优先扩大，为士兵/俘虏双列条目留出足够宽度；纵向只小幅增加。
	window.offset_left = -640.0
	window.offset_top = -330.0
	window.offset_right = 640.0
	window.offset_bottom = 330.0
	add_child(window)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	window.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	# 顶栏
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)

	var title := _make_label("部队管理", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_button := Button.new()
	close_button.name = "PartyPanelCloseButton"
	close_button.text = "关闭"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(80.0, 32.0)
	close_button.pressed.connect(close)
	header.add_child(close_button)

	# 部队概览
	var overview := GridContainer.new()
	overview.name = "PartyPanelOverview"
	overview.columns = 3
	overview.add_theme_constant_override("h_separation", 24)
	overview.add_theme_constant_override("v_separation", 4)
	column.add_child(overview)

	_party_name_label = _make_label("", 17)
	_party_name_label.name = "PartyPanelNameLabel"
	overview.add_child(_party_name_label)

	_faction_label = _make_label("", 14)
	_faction_label.name = "PartyPanelFactionLabel"
	overview.add_child(_faction_label)

	_member_count_label = _make_label("", 14)
	_member_count_label.name = "PartyPanelMemberCountLabel"
	overview.add_child(_member_count_label)

	_speed_label = _make_label("", 14)
	_speed_label.name = "PartyPanelSpeedLabel"
	overview.add_child(_speed_label)

	_state_label = _make_label("", 14)
	_state_label.name = "PartyPanelStateLabel"
	overview.add_child(_state_label)

	_movement_label = _make_label("", 14)
	_movement_label.name = "PartyPanelMovementLabel"
	overview.add_child(_movement_label)

	_target_label = _make_label("", 14)
	_target_label.name = "PartyPanelTargetLabel"
	overview.add_child(_target_label)

	_gold_label = _make_label("", 14)
	_gold_label.name = "PartyPanelGoldLabel"
	overview.add_child(_gold_label)

	_wage_label = _make_label("", 14)
	_wage_label.name = "PartyPanelWageLabel"
	overview.add_child(_wage_label)

	column.add_child(HSeparator.new())

	# 左列表 + 右详情
	var content := HBoxContainer.new()
	content.name = "PartyPanelContent"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	column.add_child(content)

	var list_column := VBoxContainer.new()
	list_column.custom_minimum_size = Vector2(560.0, 0.0)
	list_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(list_column)

	list_column.add_child(_make_label("士兵列表", 16))

	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_stretch_ratio = 2.2
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_column.add_child(list_scroll)

	# 士兵条目每行两个；条目宽度由网格自动均分。
	_member_list = GridContainer.new()
	_member_list.name = "PartyMemberList"
	_member_list.columns = 2
	_member_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_member_list.add_theme_constant_override("h_separation", 8)
	_member_list.add_theme_constant_override("v_separation", 8)
	list_scroll.add_child(_member_list)

	_empty_label = _make_label("部队中没有士兵", 14)
	_empty_label.name = "PartyMemberEmptyLabel"
	_empty_label.visible = false
	list_column.add_child(_empty_label)

	list_column.add_child(HSeparator.new())
	list_column.add_child(_make_label("俘虏列表", 16))

	var prisoner_scroll := ScrollContainer.new()
	prisoner_scroll.name = "PartyPrisonerScroll"
	prisoner_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	prisoner_scroll.size_flags_stretch_ratio = 1.0
	prisoner_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_column.add_child(prisoner_scroll)

	# 俘虏列表与士兵列表保持同样的双列排列与间距。
	_prisoner_list = GridContainer.new()
	_prisoner_list.name = "PartyPrisonerList"
	_prisoner_list.columns = 2
	_prisoner_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prisoner_list.add_theme_constant_override("h_separation", 8)
	_prisoner_list.add_theme_constant_override("v_separation", 8)
	prisoner_scroll.add_child(_prisoner_list)

	_prisoner_empty_label = _make_label("当前部队没有俘虏", 14)
	_prisoner_empty_label.name = "PartyPrisonerEmptyLabel"
	_prisoner_empty_label.visible = false
	_prisoner_empty_label.modulate = Color(0.78, 0.78, 0.78)
	list_column.add_child(_prisoner_empty_label)

	content.add_child(VSeparator.new())

	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(detail_scroll)

	_detail_panel = UnitDetailPanel.new()
	_detail_panel.name = "UnitDetailPanel"
	_detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_detail_panel)
	_detail_panel.setup(_context)
	_detail_panel.unit_changed.connect(_on_detail_unit_changed)


func _rebuild_member_list() -> Array[String]:
	var valid_ids: Array[String] = []
	for child: Node in _member_list.get_children():
		_member_list.remove_child(child)
		child.queue_free()
	_member_items.clear()

	if _party == null or _context == null:
		_empty_label.visible = true
		return valid_ids

	var seen: Dictionary = {}
	for unit_id: String in _party.member_unit_ids:
		if seen.has(unit_id):
			continue
		seen[unit_id] = true
		var unit := _context.unit_manager.get_unit(unit_id)
		if unit == null:
			# 无效成员引用只在数据层报告；UI 跳过，避免崩溃。
			continue
		valid_ids.append(unit_id)
		var item := PartyMemberItem.new()
		item.setup(
			unit,
			_context.unit_manager.get_unit_config(unit.config_id),
			_equipment_configs_for(unit)
		)
		item.pressed.connect(_on_member_pressed.bind(unit_id))
		_member_list.add_child(item)
		_member_items[unit_id] = item

	_empty_label.visible = valid_ids.is_empty()
	return valid_ids


## 只读取当前选中部队自己的俘虏列表，不混入其他部队或全局俘虏池。
func _rebuild_prisoner_list() -> Array[String]:
	var valid_ids: Array[String] = []
	for child: Node in _prisoner_list.get_children():
		_prisoner_list.remove_child(child)
		child.queue_free()
	_prisoner_items.clear()

	if _party == null or _context == null:
		_prisoner_empty_label.visible = true
		return valid_ids

	var seen: Dictionary = {}
	for unit_id: String in _party.prisoner_unit_ids:
		if seen.has(unit_id):
			continue
		seen[unit_id] = true
		var unit := _context.unit_manager.get_unit(unit_id)
		if unit == null:
			continue
		valid_ids.append(unit_id)
		var item := PartyMemberItem.new()
		item.setup(
			unit,
			_context.unit_manager.get_unit_config(unit.config_id),
			_equipment_configs_for(unit),
			true
		)
		item.pressed.connect(_on_prisoner_pressed.bind(unit_id))
		_prisoner_list.add_child(item)
		_prisoner_items[unit_id] = item

	_prisoner_empty_label.visible = valid_ids.is_empty()
	return valid_ids


func _apply_selection() -> void:
	for unit_id: String in _member_items:
		var item := _member_items[unit_id] as PartyMemberItem
		if item != null:
			item.set_selected(unit_id == _selected_unit_id)
	for unit_id: String in _prisoner_items:
		var item := _prisoner_items[unit_id] as PartyMemberItem
		if item != null:
			item.set_selected(unit_id == _selected_unit_id)
	_detail_panel.show_unit(_selected_unit_id)


func _on_member_pressed(unit_id: String) -> void:
	if not _member_items.has(unit_id):
		return
	_selected_unit_id = unit_id
	_apply_selection()


func _on_prisoner_pressed(unit_id: String) -> void:
	if not _prisoner_items.has(unit_id):
		return
	_selected_unit_id = unit_id
	_apply_selection()


## 头像缩略图与详情预览共用同一装备视觉配置来源。
func _equipment_configs_for(unit: UnitData) -> Dictionary:
	var configs: Dictionary = {}
	if unit == null or _context == null:
		return configs
	for slot_key_value: Variant in unit.equipment.keys():
		var slot_key := str(slot_key_value)
		var equipment_id := str(unit.equipment.get(slot_key_value, ""))
		var equipment := _context.unit_manager.get_equipment_config(equipment_id)
		if equipment != null:
			configs[slot_key] = equipment
	return configs


## 装备/晋升通过管理器写入后，刷新概览、成员列表与详情。
func _on_detail_unit_changed() -> void:
	refresh()


func _show_party_missing() -> void:
	_party_name_label.text = "未找到玩家部队"
	_faction_label.text = ""
	_member_count_label.text = ""
	_speed_label.text = ""
	_state_label.text = ""
	_movement_label.text = ""
	_target_label.text = "请返回大地图检查部队数据"
	_gold_label.text = ""
	_wage_label.text = ""
	_rebuild_member_list()
	_rebuild_prisoner_list()
	_detail_panel.clear()


func _make_label(label_text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _set_full_rect(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0


func _faction_display_name(faction_id: String) -> String:
	if _context != null:
		return _context.faction_manager.get_display_name(faction_id)
	return faction_id if not faction_id.is_empty() else "未知"


func _battle_state_text(state: PartyData.BattleState) -> String:
	match state:
		PartyData.BattleState.IN_BATTLE:
			return "战斗中"
		PartyData.BattleState.RETURNING:
			return "返程中"
		PartyData.BattleState.DISABLED:
			return "不可用"
		_:
			return "可用"
