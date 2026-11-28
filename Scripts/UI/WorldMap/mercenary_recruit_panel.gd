class_name MercenaryRecruitPanel
extends Control
## 独立的酒馆雇佣兵招募界面。
##
## 只展示 MercenaryManager 的驻留记录并发起原子招募意图：
## - 左侧列表列出当前酒馆的雇佣兵；
## - 右侧复用战斗/部队详情相同的 UnitVisual 预览，展示真实装备、罩袍、
##   头盔、缨饰、武器与马匹；
## - 预览单位由 create_detached_unit 创建，不进入 UnitManager 仓储、
##   不属于任何部队，因此不会产生可被招募/移动/存档的重复实体。

signal closed
## 招募成功后广播，供大地图刷新金币/部队等只读显示。
signal mercenary_recruited(unit_id: String)

const UnitVisualScript = preload("res://Scripts/Systems/Combat/unit_visual.gd")
const WINDOW_SIZE := Vector2(1080.0, 660.0)
const PREVIEW_VIEWPORT_SIZE := Vector2i(220, 260)
const PREVIEW_SCALE: float = 3.2
const PREVIEW_FEET_POSITION := Vector2(110.0, 252.0)

var _context: WorldContext = null
var _settlement: SettlementData = null
var _selected_mercenary_id: String = ""
var _feedback_text: String = ""
## 每个雇佣兵只创建一个 detached 预览单位，避免反复选择时消耗额外 ID。
var _preview_units: Dictionary = {}

var _title_label: Label = null
var _gold_label: Label = null
var _list: VBoxContainer = null
var _empty_label: Label = null
var _name_label: Label = null
var _type_label: Label = null
var _tier_label: Label = null
var _mount_label: Label = null
var _exp_label: Label = null
var _price_label: Label = null
var _wage_label: Label = null
var _feedback_label: Label = null
var _recruit_button: Button = null
var _preview_viewport: SubViewport = null
var _preview_visual: UnitVisual = null


func setup(context: WorldContext) -> void:
	_context = context
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_full_rect(self)
	_build()


func open(settlement: SettlementData) -> bool:
	if _context == null or settlement == null:
		return false
	if settlement.settlement_type != SettlementData.SettlementType.TOWN:
		return false
	_settlement = settlement
	_title_label.text = "%s · 招募雇佣兵" % settlement.display_name
	_feedback_text = ""
	_selected_mercenary_id = ""
	visible = true
	_refresh()
	var mercenaries := _stationed_mercenaries()
	if not mercenaries.is_empty():
		_select_mercenary(mercenaries[0].mercenary_id)
	return true


func close() -> void:
	visible = false
	_settlement = null
	_selected_mercenary_id = ""
	_feedback_text = ""
	_clear_preview()
	_release_preview_units()
	closed.emit()


## 地点切换/外层面板关闭时清理显示状态，不广播 closed。
func reset() -> void:
	visible = false
	_settlement = null
	_selected_mercenary_id = ""
	_feedback_text = ""
	_clear_preview()
	_release_preview_units()


func get_settlement_id() -> String:
	return _settlement.settlement_id if _settlement != null else ""


func get_selected_mercenary_id() -> String:
	return _selected_mercenary_id


# ---------------------------------------------------------------------------
# 构建
# ---------------------------------------------------------------------------


func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "MercenaryRecruitDim"
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_set_full_rect(dim)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "MercenaryRecruitBody"
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
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	_title_label = _make_label("招募雇佣兵", 24)
	_title_label.name = "MercenaryRecruitTitle"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title_label)

	_gold_label = _make_label("", 14)
	_gold_label.name = "MercenaryRecruitGold"
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_gold_label)

	column.add_child(HSeparator.new())

	var body := HBoxContainer.new()
	body.name = "MercenaryRecruitBodyRow"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	column.add_child(body)

	var list_column := VBoxContainer.new()
	list_column.custom_minimum_size = Vector2(430.0, 0.0)
	list_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_column.add_theme_constant_override("separation", 6)
	body.add_child(list_column)

	list_column.add_child(_make_label("可招募雇佣兵", 16))
	var scroll := ScrollContainer.new()
	scroll.name = "MercenaryRecruitScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_column.add_child(scroll)

	_list = VBoxContainer.new()
	_list.name = "MercenaryRecruitList"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	_empty_label = _make_label("当前酒馆没有可招募的雇佣兵。", 13)
	_empty_label.name = "MercenaryRecruitEmpty"
	list_column.add_child(_empty_label)

	var detail := VBoxContainer.new()
	detail.name = "MercenaryRecruitDetail"
	detail.custom_minimum_size = Vector2(360.0, 0.0)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 6)
	body.add_child(detail)

	_build_preview(detail)

	_name_label = _make_label("", 20)
	_name_label.name = "MercenaryRecruitName"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_child(_name_label)

	_type_label = _make_label("", 14)
	_type_label.name = "MercenaryRecruitType"
	detail.add_child(_type_label)

	_tier_label = _make_label("", 14)
	_tier_label.name = "MercenaryRecruitTier"
	detail.add_child(_tier_label)

	_mount_label = _make_label("", 14)
	_mount_label.name = "MercenaryRecruitMount"
	detail.add_child(_mount_label)

	_exp_label = _make_label("", 14)
	_exp_label.name = "MercenaryRecruitExp"
	detail.add_child(_exp_label)

	_price_label = _make_label("", 14)
	_price_label.name = "MercenaryRecruitPrice"
	detail.add_child(_price_label)

	_wage_label = _make_label("", 14)
	_wage_label.name = "MercenaryRecruitWage"
	detail.add_child(_wage_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(spacer)

	_feedback_label = _make_label("", 13)
	_feedback_label.name = "MercenaryRecruitFeedback"
	_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_feedback_label)

	_recruit_button = _make_button("招募", "MercenaryRecruitButton")
	_recruit_button.pressed.connect(_on_recruit_pressed)
	detail.add_child(_recruit_button)

	var close_button := _make_button("返回酒馆", "MercenaryRecruitCloseButton")
	close_button.pressed.connect(close)
	detail.add_child(close_button)


## 复用 UnitDetailPanel 的预览方案：独立 SubViewport 中只放 UnitVisual，
## 不创建真实战斗单位或场景节点。
func _build_preview(parent: VBoxContainer) -> void:
	var preview_panel := PanelContainer.new()
	preview_panel.name = "MercenaryRecruitPreviewPanel"
	preview_panel.custom_minimum_size = Vector2(240.0, 280.0)
	preview_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(preview_panel)

	var container := SubViewportContainer.new()
	container.name = "MercenaryRecruitPreviewContainer"
	container.custom_minimum_size = Vector2(
		float(PREVIEW_VIEWPORT_SIZE.x), float(PREVIEW_VIEWPORT_SIZE.y)
	)
	container.stretch = true
	preview_panel.add_child(container)

	_preview_viewport = SubViewport.new()
	_preview_viewport.name = "MercenaryRecruitPreview"
	_preview_viewport.size = PREVIEW_VIEWPORT_SIZE
	_preview_viewport.transparent_bg = true
	_preview_viewport.handle_input_locally = false
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	container.add_child(_preview_viewport)

	var preview_root := Node2D.new()
	preview_root.name = "PreviewRoot"
	_preview_viewport.add_child(preview_root)

	_preview_visual = UnitVisualScript.new()
	_preview_visual.name = "PreviewUnitVisual"
	_preview_visual.position = PREVIEW_FEET_POSITION
	_preview_visual.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	preview_root.add_child(_preview_visual)


# ---------------------------------------------------------------------------
# 数据刷新
# ---------------------------------------------------------------------------


func _stationed_mercenaries() -> Array[MercenaryData]:
	if _context == null or _settlement == null:
		return []
	return _context.mercenary_manager.get_stationed_mercenaries(
		_settlement.settlement_id
	)


func _refresh() -> void:
	if _context == null or _settlement == null:
		return
	_gold_label.text = "金币：%s" % GoldUtils.format(
		float(_context.player_profile.gold)
	)
	_clear_list()
	var mercenaries := _stationed_mercenaries()
	for mercenary: MercenaryData in mercenaries:
		_list.add_child(_make_mercenary_row(mercenary))
	_empty_label.visible = mercenaries.is_empty()
	if _selected_mercenary_id.is_empty() and not mercenaries.is_empty():
		_select_mercenary(mercenaries[0].mercenary_id)
	elif not _selected_mercenary_id.is_empty():
		if _context.mercenary_manager.get_mercenary(_selected_mercenary_id) == null:
			_selected_mercenary_id = ""
			_clear_preview()
			_refresh_detail()
		else:
			_refresh_detail()


func _make_mercenary_row(mercenary: MercenaryData) -> Control:
	var button := Button.new()
	button.name = "MercenaryRecruitEntry_%s" % mercenary.mercenary_id
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, 38.0)
	button.text = "%s    %s    %s    %s" % [
		mercenary.display_name,
		_context.mercenary_manager.get_tier_display_name(mercenary),
		"骑马" if mercenary.mounted else "步行",
		CombatExperience.tier_name_for_level(mercenary.level),
	]
	button.pressed.connect(_select_mercenary.bind(mercenary.mercenary_id))
	return button


func _select_mercenary(mercenary_id: String) -> void:
	if _context == null:
		return
	var mercenary := _context.mercenary_manager.get_mercenary(mercenary_id)
	if mercenary == null:
		return
	_selected_mercenary_id = mercenary_id
	_feedback_text = ""
	_refresh_detail()
	_refresh_preview(mercenary)


func _refresh_detail() -> void:
	var mercenary: MercenaryData = null
	if _context != null and not _selected_mercenary_id.is_empty():
		mercenary = _context.mercenary_manager.get_mercenary(_selected_mercenary_id)
	if mercenary == null:
		_name_label.text = "未选择雇佣兵"
		_type_label.text = ""
		_tier_label.text = ""
		_mount_label.text = ""
		_exp_label.text = ""
		_price_label.text = ""
		_wage_label.text = ""
		_feedback_label.text = _feedback_text
		_recruit_button.disabled = true
		return

	var config := _context.unit_manager.get_unit_config(mercenary.config_id)
	var price: int = _context.mercenary_manager.get_recruit_price(mercenary)
	_name_label.text = mercenary.display_name
	_type_label.text = "类型：%s" % (
		config.get_class_display_name() if config != null else "雇佣兵"
	)
	_tier_label.text = "兵种等级：%s" % \
		_context.mercenary_manager.get_tier_display_name(mercenary)
	_mount_label.text = "坐骑：%s" % ("骑马" if mercenary.mounted else "步行")
	_exp_label.text = "战斗经验：%s" % CombatExperience.tier_name_for_level(
		mercenary.level
	)
	_price_label.text = "招募价格：%d 金币" % price
	_wage_label.text = "每日工资：%d" % \
		_context.mercenary_manager.get_daily_wage(mercenary)
	_feedback_label.text = _feedback_text
	var party := _context.get_player_party()
	_recruit_button.disabled = party == null \
		or not party.is_available_for_world() \
		or not _context.player_profile.can_afford(price)
	_recruit_button.text = "招募（%d 金币）" % price


func _refresh_preview(mercenary: MercenaryData) -> void:
	if _preview_visual == null or mercenary == null or _context == null:
		_clear_preview()
		return
	var unit := _get_preview_unit(mercenary)
	if unit == null:
		_clear_preview()
		return
	_preview_visual.setup(unit, _equipment_configs(unit))
	_preview_visual.set_facing(-1.0)
	_preview_visual.reset_locomotion()


## 预览单位不注册进 UnitManager、不属于任何部队；雇佣兵身份与外观
## 直接读取 MercenaryManager 的持久化快照。
func _get_preview_unit(mercenary: MercenaryData) -> UnitData:
	if _preview_units.has(mercenary.mercenary_id):
		return _preview_units[mercenary.mercenary_id] as UnitData
	var config := _context.unit_manager.get_unit_config(mercenary.config_id)
	if config == null:
		return null
	var party := _context.get_player_party()
	var faction_id: String = party.faction_id if party != null else ""
	var unit := _context.unit_manager.create_detached_unit(
		config,
		faction_id,
		mercenary.display_name,
		mercenary.level
	)
	if unit == null:
		return null
	unit.exp = mercenary.exp
	unit.is_mercenary = true
	unit.recruit_source = UnitData.MERCENARY_RECRUIT_SOURCE
	unit.appearance = _context.mercenary_manager.get_mercenary_appearance(mercenary)
	unit.current_hp = unit.max_hp
	_preview_units[mercenary.mercenary_id] = unit
	return unit


func _equipment_configs(unit: UnitData) -> Dictionary:
	var configs: Dictionary = {}
	if unit == null:
		return configs
	for slot_key_value: Variant in unit.equipment.keys():
		var slot_key: String = str(slot_key_value)
		var equipment_id: String = str(unit.equipment.get(slot_key_value, ""))
		var equipment := _context.unit_manager.get_equipment_config(equipment_id)
		if equipment != null:
			configs[slot_key] = equipment
	return configs


func _clear_preview() -> void:
	if _preview_visual != null:
		_preview_visual.setup(null)


func _release_preview_units() -> void:
	_preview_units.clear()


func _process(delta: float) -> void:
	if _preview_visual == null or _preview_visual.unit_data == null:
		return
	if not is_visible_in_tree():
		return
	_preview_visual.update_locomotion(delta, false)


# ---------------------------------------------------------------------------
# 招募
# ---------------------------------------------------------------------------


func _on_recruit_pressed() -> void:
	if _context == null or _settlement == null \
			or _selected_mercenary_id.is_empty():
		return
	var mercenary_id: String = _selected_mercenary_id
	var result: Dictionary = _context.mercenary_manager.recruit_mercenary_for_player(
		mercenary_id,
		_settlement.settlement_id,
		_context.player_profile,
		_context.player_party_id
	)
	if not bool(result.get("success", false)):
		_feedback_text = "招募失败：%s" % str(
			result.get("reason", "未知原因")
		)
		_refresh()
		return
	_preview_units.erase(mercenary_id)
	_selected_mercenary_id = ""
	_refresh()
	# 刷新会自动选中下一条雇佣兵并清空临时提示；招募结果需要保留给玩家确认。
	_feedback_text = "已招募 %s，花费 %d 金币。" % [
		str(result.get("unit_name", "雇佣兵")), int(result.get("price", 0))
	]
	_feedback_label.text = _feedback_text
	mercenary_recruited.emit(str(result.get("unit_id", "")))


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------


func _clear_list() -> void:
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_button(text: String, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(180.0, 38.0)
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
