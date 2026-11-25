class_name FamilyPanel
extends Control
## 家族管理面板：只读展示玩家家族的贵族与封地。
##
## 数据全部在每次刷新时从 NobleManager / HouseManager / PartyManager /
## SettlementManager 实时读取，不在面板内保存成员或封地缓存。
## 打开/关闭的暂停原因由 WorldMap 统一管理；本面板只发出 closed 信号。

signal closed
signal settlement_selected(settlement_id: String)

const WINDOW_SIZE := Vector2(1000.0, 620.0)
const TAB_TROOPS: String = "troops"
const TAB_FIEFS: String = "fiefs"

var _context: WorldContext = null
var _current_tab: String = TAB_TROOPS
var _signature: String = ""
var _troop_entries: Array[Dictionary] = []
var _fief_entries: Array[Dictionary] = []

var _family_name_label: Label = null
var _troops_tab_button: Button = null
var _fiefs_tab_button: Button = null
var _content: VBoxContainer = null
var _empty_label: Label = null


func setup(context: WorldContext) -> void:
	_context = context
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_full_rect(self)
	_build()


func open() -> void:
	visible = true
	_current_tab = TAB_TROOPS
	refresh(true)


func close() -> void:
	visible = false
	closed.emit()


## 每帧调用安全；只有实时数据签名变化时才重建。
func refresh_if_needed() -> void:
	refresh(false)


func refresh(force: bool = false) -> void:
	if not visible and not force:
		return
	var troops: Array[Dictionary] = _collect_troops()
	var fiefs: Array[Dictionary] = _collect_fiefs()
	var family_name: String = _resolve_family_name()
	var signature: String = _build_signature(family_name, troops, fiefs)
	if not force and signature == _signature:
		return
	_signature = signature
	_troop_entries = troops
	_fief_entries = fiefs
	if _family_name_label != null:
		_family_name_label.text = family_name if not family_name.is_empty() else "暂无家族"
	_rebuild_content()


func get_family_name() -> String:
	return _family_name_label.text if _family_name_label != null else ""


func get_current_tab() -> String:
	return _current_tab


func set_tab(tab: String) -> void:
	if tab != TAB_TROOPS and tab != TAB_FIEFS:
		return
	_current_tab = tab
	_update_tab_buttons()
	_rebuild_content()


func get_troop_entries() -> Array[Dictionary]:
	return _troop_entries.duplicate(true)


func get_fief_entries() -> Array[Dictionary]:
	return _fief_entries.duplicate(true)


# ---------------------------------------------------------------------------
# 实时数据收集
# ---------------------------------------------------------------------------


func _collect_troops() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var house := _get_player_house()
	if house == null or _context == null:
		return entries
	for noble: NobleData in _context.house_manager.get_house_nobles(
		house.house_id, true
	):
		if noble == null or noble.is_player_lord:
			continue
		entries.append(_build_troop_entry(noble))
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")) < str(b.get("name", ""))
	)
	return entries


func _build_troop_entry(noble: NobleData) -> Dictionary:
	var party := _context.party_manager.get_party(noble.party_id) \
		if not noble.party_id.is_empty() else null
	var unit := _find_noble_unit(noble, party)
	var captured: bool = _is_noble_captive(unit, party)
	var status_text: String = "正常"
	if not noble.alive:
		status_text = "已阵亡"
	elif captured:
		status_text = "被俘"
	elif party != null and party.battle_state == PartyData.BattleState.IN_BATTLE:
		status_text = "战斗中"

	var party_text: String = "暂无部队"
	if noble.alive and not captured and party != null:
		party_text = _build_party_text(noble, party)

	return {
		"noble_id": noble.lord_id,
		"name": noble.display_name,
		"rank_text": noble.get_rank_text(),
		"status": status_text,
		"party_text": party_text,
		"captured": captured,
		"alive": noble.alive,
		"party_id": party.party_id if party != null else "",
		"member_count": party.member_unit_ids.size() if party != null else 0,
	}


## 优先返回当前在贵族所属部队中的单位；赎回后重建部队时不会被旧的
## 已出售/被俘单位记录误判。找不到匹配单位才回退到第一个同贵族 ID 单位。
func _find_noble_unit(noble: NobleData, party: PartyData) -> UnitData:
	if noble == null or _context == null:
		return null
	var fallback: UnitData = null
	for unit: UnitData in _context.unit_manager.get_all_units():
		if unit == null or unit.noble_id != noble.lord_id:
			continue
		if party != null and unit.current_party_id == party.party_id \
				and not unit.is_prisoner() and unit.sold_to_settlement_id.is_empty():
			return unit
		if fallback == null:
			fallback = unit
	return fallback


func _is_noble_captive(unit: UnitData, party: PartyData) -> bool:
	if unit == null:
		return false
	# 部队仍持有该贵族单位时，即使仓储里残留旧俘虏记录也以当前部队为准。
	if party != null and unit.current_party_id == party.party_id \
			and not unit.is_prisoner() and unit.sold_to_settlement_id.is_empty():
		return false
	return unit.is_prisoner() or not unit.sold_to_settlement_id.is_empty()


func _build_party_text(noble: NobleData, party: PartyData) -> String:
	var parts: Array[String] = [
		"成员 %d 人" % party.member_unit_ids.size()
	]
	var settlement_name: String = _nearest_settlement_name(party.world_position)
	if not settlement_name.is_empty():
		parts.append("%s附近" % settlement_name)
	var activity: String = _activity_text(noble, party)
	if not activity.is_empty():
		parts.append(activity)
	return " · ".join(parts)


func _activity_text(noble: NobleData, party: PartyData) -> String:
	if party.battle_state == PartyData.BattleState.IN_BATTLE:
		return "战斗中"
	if noble.current_state == "RECRUITING":
		return "征召中"
	match party.get_activity_state():
		PartyData.Activity.PATROL:
			return "巡逻"
		PartyData.Activity.TRAVEL:
			return "移动中"
		PartyData.Activity.PURSUIT:
			return "追击"
		PartyData.Activity.RESPOND_TO_BATTLE:
			return "支援战斗"
		PartyData.Activity.FOLLOWING:
			return "跟随"
		PartyData.Activity.RECRUITING:
			return "征召中"
		_:
			return "待命"


func _nearest_settlement_name(world_position: Vector2) -> String:
	var nearest: SettlementData = null
	var nearest_distance: float = INF
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement == null:
			continue
		var distance: float = world_position.distance_to(settlement.world_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = settlement
	return nearest.display_name if nearest != null else ""


func _collect_fiefs() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var house := _get_player_house()
	if house == null or _context == null:
		return entries

	var member_ids: Dictionary = {}
	for noble: NobleData in _context.house_manager.get_house_nobles(
		house.house_id, true
	):
		if noble != null:
			member_ids[noble.lord_id] = true

	var seen: Dictionary = {}
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement == null or seen.has(settlement.settlement_id):
			continue
		# 家族封地以 owner_house_id 为权威；同时接受明确属于家族成员的
		# owner_noble_id，绝不按名字或相邻关系推断。
		var belongs: bool = settlement.owner_house_id == house.house_id
		if not belongs and not settlement.owner_noble_id.is_empty() \
				and member_ids.has(settlement.owner_noble_id):
			belongs = true
		if not belongs:
			continue
		seen[settlement.settlement_id] = true
		entries.append(_build_fief_entry(settlement))

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: int = int(a.get("type_priority", 99))
		var pb: int = int(b.get("type_priority", 99))
		if pa != pb:
			return pa < pb
		return str(a.get("name", "")) < str(b.get("name", ""))
	)
	return entries


func _build_fief_entry(settlement: SettlementData) -> Dictionary:
	var type_text: String = ""
	var type_priority: int = 99
	match settlement.settlement_type:
		SettlementData.SettlementType.VILLAGE:
			type_text = "村庄"
			type_priority = 0
		SettlementData.SettlementType.TOWN:
			type_text = "城镇"
			type_priority = 1
		SettlementData.SettlementType.CASTLE:
			type_text = "城堡"
			type_priority = 2
		_:
			type_text = "地点"
	var owner_text: String = ""
	if not settlement.owner_noble_id.is_empty():
		var owner_noble: NobleData = _context.noble_manager.get_noble(
			settlement.owner_noble_id
		)
		if owner_noble != null:
			owner_text = owner_noble.display_name
	return {
		"settlement_id": settlement.settlement_id,
		"name": settlement.display_name,
		"type_text": type_text,
		"type_priority": type_priority,
		"detail": "%s · 人口 %d · 繁荣 %d" % [
			type_text, settlement.population, settlement.prosperity
		],
		"owner_text": owner_text,
	}


func _resolve_family_name() -> String:
	var house := _get_player_house()
	return house.house_name if house != null else ""


func _get_player_house() -> HouseData:
	if _context == null:
		return null
	return _context.get_player_house()


func _build_signature(
	family_name: String,
	troops: Array[Dictionary],
	fiefs: Array[Dictionary]
) -> String:
	var parts: Array[String] = [
		_current_tab,
		family_name,
	]
	for entry: Dictionary in troops:
		parts.append("%s|%s|%s|%s" % [
			str(entry.get("noble_id", "")),
			str(entry.get("name", "")),
			str(entry.get("status", "")),
			str(entry.get("party_text", "")),
		])
	parts.append("--fiefs--")
	for entry: Dictionary in fiefs:
		parts.append("%s|%s|%s" % [
			str(entry.get("settlement_id", "")),
			str(entry.get("name", "")),
			str(entry.get("owner_text", "")),
		])
	return "||".join(parts)


# ---------------------------------------------------------------------------
# 界面
# ---------------------------------------------------------------------------


func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "FamilyPanelDim"
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_set_full_rect(dim)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "FamilyPanelContainer"
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
	title.name = "FamilyPanelTitle"
	title.text = "家族"
	title.add_theme_font_size_override("font_size", 24)
	header.add_child(title)

	_family_name_label = Label.new()
	_family_name_label.name = "FamilyNameLabel"
	_family_name_label.add_theme_font_size_override("font_size", 18)
	_family_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_family_name_label)

	var close_button := Button.new()
	close_button.name = "FamilyPanelCloseButton"
	close_button.text = "关闭"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(64.0, 30.0)
	close_button.pressed.connect(close)
	header.add_child(close_button)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	column.add_child(tabs)

	_troops_tab_button = Button.new()
	_troops_tab_button.name = "FamilyTabTroopsButton"
	_troops_tab_button.text = "部队"
	_troops_tab_button.toggle_mode = true
	_troops_tab_button.focus_mode = Control.FOCUS_NONE
	_troops_tab_button.custom_minimum_size = Vector2(110.0, 32.0)
	_troops_tab_button.pressed.connect(set_tab.bind(TAB_TROOPS))
	tabs.add_child(_troops_tab_button)

	_fiefs_tab_button = Button.new()
	_fiefs_tab_button.name = "FamilyTabFiefsButton"
	_fiefs_tab_button.text = "封地"
	_fiefs_tab_button.toggle_mode = true
	_fiefs_tab_button.focus_mode = Control.FOCUS_NONE
	_fiefs_tab_button.custom_minimum_size = Vector2(110.0, 32.0)
	_fiefs_tab_button.pressed.connect(set_tab.bind(TAB_FIEFS))
	tabs.add_child(_fiefs_tab_button)

	var body_panel := PanelContainer.new()
	body_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body_panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_panel.add_child(scroll)

	_content = VBoxContainer.new()
	_content.name = "FamilyPanelContent"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	scroll.add_child(_content)

	_update_tab_buttons()


func _update_tab_buttons() -> void:
	if _troops_tab_button != null:
		_troops_tab_button.button_pressed = _current_tab == TAB_TROOPS
	if _fiefs_tab_button != null:
		_fiefs_tab_button.button_pressed = _current_tab == TAB_FIEFS


func _rebuild_content() -> void:
	if _content == null:
		return
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_empty_label = null

	if _get_player_house() == null:
		_add_empty_label("你还没有家族，暂无可管理的内容。")
		return

	if _current_tab == TAB_TROOPS:
		_rebuild_troops()
	else:
		_rebuild_fiefs()


func _rebuild_troops() -> void:
	_add_section_header("家族贵族（%d）" % _troop_entries.size())
	if _troop_entries.is_empty():
		_add_empty_label("家族暂无可管理的贵族。")
		return
	for entry: Dictionary in _troop_entries:
		_add_troop_entry(entry)


func _rebuild_fiefs() -> void:
	if _fief_entries.is_empty():
		_add_empty_label("家族暂无封地。")
		return
	var groups: Array[Dictionary] = [
		{"type_text": "村庄", "priority": 0},
		{"type_text": "城镇", "priority": 1},
		{"type_text": "城堡", "priority": 2},
	]
	for group: Dictionary in groups:
		var entries: Array[Dictionary] = []
		for entry: Dictionary in _fief_entries:
			if str(entry.get("type_text", "")) == str(group.get("type_text", "")):
				entries.append(entry)
		if entries.is_empty():
			continue
		_add_section_header("%s（%d）" % [
			str(group.get("type_text", "地点")), entries.size()
		])
		for entry: Dictionary in entries:
			_add_fief_entry(entry)


func _add_section_header(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.custom_minimum_size = Vector2(0.0, 30.0)
	_content.add_child(label)


func _add_empty_label(text: String) -> void:
	_empty_label = Label.new()
	_empty_label.name = "FamilyEmptyLabel"
	_empty_label.text = text
	_empty_label.add_theme_font_size_override("font_size", 14)
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.modulate = Color(1.0, 1.0, 1.0, 0.7)
	_content.add_child(_empty_label)


func _add_troop_entry(entry: Dictionary) -> void:
	var row := PanelContainer.new()
	row.name = "FamilyTroopEntry_%s" % _safe_node_suffix(
		str(entry.get("noble_id", ""))
	)
	_content.add_child(row)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	row.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	margin.add_child(column)

	var name_label := Label.new()
	name_label.name = "FamilyTroopName_%s" % _safe_node_suffix(
		str(entry.get("noble_id", ""))
	)
	name_label.text = "%s（%s）" % [
		str(entry.get("name", "无名贵族")),
		str(entry.get("rank_text", "骑士")),
	]
	name_label.add_theme_font_size_override("font_size", 16)
	column.add_child(name_label)

	var status_label := Label.new()
	status_label.name = "FamilyTroopStatus_%s" % _safe_node_suffix(
		str(entry.get("noble_id", ""))
	)
	status_label.text = "状态：%s" % str(entry.get("status", "正常"))
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.modulate = Color(0.95, 0.8, 0.55) \
		if bool(entry.get("captured", false)) else Color(1.0, 1.0, 1.0)
	column.add_child(status_label)

	var party_label := Label.new()
	party_label.name = "FamilyTroopParty_%s" % _safe_node_suffix(
		str(entry.get("noble_id", ""))
	)
	party_label.text = str(entry.get("party_text", "暂无部队"))
	party_label.add_theme_font_size_override("font_size", 13)
	party_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	party_label.modulate = Color(1.0, 1.0, 1.0, 0.75)
	column.add_child(party_label)


func _add_fief_entry(entry: Dictionary) -> void:
	var button := Button.new()
	var settlement_id: String = str(entry.get("settlement_id", ""))
	button.name = "FamilyFiefEntry_%s" % _safe_node_suffix(settlement_id)
	button.text = "%s　%s" % [
		str(entry.get("name", "未命名封地")),
		str(entry.get("detail", "")),
	]
	if not str(entry.get("owner_text", "")).is_empty():
		button.text += "　管理者：%s" % str(entry.get("owner_text", ""))
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, 40.0)
	button.pressed.connect(func() -> void: settlement_selected.emit(settlement_id))
	_content.add_child(button)


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
