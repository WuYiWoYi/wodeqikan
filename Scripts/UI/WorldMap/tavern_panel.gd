class_name TavernPanel
extends Control
## 城镇酒馆二级界面（阶段 13 Step 6）。
##
## 三个入口：出售俘虏、查看雇佣兵信息（占位）、离开酒馆。
## 出售俘虏采用与市场一致的“临时预览 → 确认提交”：
## 左栏＝本次准备卖给城镇的俘虏，右栏＝玩家当前俘虏。
## 未确认前金币与真实归属不变；确认由 PrisonerTradeManager 原子结算。

signal closed
## 出售成功后广播结果，供大地图刷新金币/背包等只读显示。
signal prisoners_sold(result: Dictionary)

const WINDOW_SIZE := Vector2(960.0, 620.0)
const ROW_MIN_HEIGHT := 34.0

var _context: WorldContext = null
var _settlement: SettlementData = null
## 嵌入模式：作为城镇信息面板的一段内容，不再创建独立二级窗口。
var _embedded: bool = false
## 进入出售界面时的玩家俘虏快照。
var _initial_prisoner_ids: Array[String] = []
## 本次预览中准备出售的俘虏（尚未提交）。
var _sell_ids: Array[String] = []
var _feedback_text: String = ""

var _menu_view: VBoxContainer = null
var _sell_view: VBoxContainer = null
var _merc_view: VBoxContainer = null
var _title_label: Label = null
var _gold_label: Label = null
var _buyer_list: VBoxContainer = null
var _player_list: VBoxContainer = null
var _buyer_empty: Label = null
var _player_empty: Label = null
var _total_label: Label = null
var _feedback_label: Label = null
var _confirm_button: Button = null


func setup(context: WorldContext, embedded: bool = false) -> void:
	_context = context
	_embedded = embedded
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_full_rect(self)
	_build()


## 打开酒馆；只有城镇可用。失败返回 false。
func open(settlement: SettlementData) -> bool:
	if _context == null or settlement == null:
		return false
	if settlement.settlement_type != SettlementData.SettlementType.TOWN:
		return false
	_settlement = settlement
	_title_label.text = "%s · 酒馆" % settlement.display_name
	_feedback_text = ""
	visible = true
	_show_menu()
	_refresh_gold()
	return true


func close() -> void:
	visible = false
	_settlement = null
	_sell_ids.clear()
	_initial_prisoner_ids.clear()
	closed.emit()


## 面板被整体关闭/切换地点时清理显示状态，不广播 closed，
## 避免调用方在收尾阶段又被信号切回城镇信息视图。
func reset() -> void:
	visible = false
	_settlement = null
	_sell_ids.clear()
	_initial_prisoner_ids.clear()
	_feedback_text = ""
	if _menu_view != null:
		_show_menu()


func get_settlement_id() -> String:
	return _settlement.settlement_id if _settlement != null else ""


func is_sell_view_visible() -> bool:
	return _sell_view != null and _sell_view.visible


func is_menu_visible() -> bool:
	return _menu_view != null and _menu_view.visible


# ---------------------------------------------------------------------------
# 构建
# ---------------------------------------------------------------------------


func _build() -> void:
	var column: VBoxContainer = null
	if _embedded:
		# 嵌入城镇信息面板：不创建遮罩、不创建二级窗口，原面板位置/尺寸不变。
		column = VBoxContainer.new()
		column.name = "TavernEmbeddedContent"
		column.add_theme_constant_override("separation", 8)
		_set_full_rect(column)
		add_child(column)
	else:
		var dim := ColorRect.new()
		dim.name = "TavernDim"
		dim.color = Color(0.0, 0.0, 0.0, 0.55)
		dim.mouse_filter = Control.MOUSE_FILTER_STOP
		_set_full_rect(dim)
		add_child(dim)

		var panel := PanelContainer.new()
		panel.name = "TavernPanelBody"
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

		column = VBoxContainer.new()
		column.add_theme_constant_override("separation", 10)
		margin.add_child(column)

	_build_content(column)


func _build_content(column: VBoxContainer) -> void:
	_title_label = _make_label("酒馆", 24)
	_title_label.name = "TavernTitleLabel"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title_label)

	_gold_label = _make_label("", 14)
	_gold_label.name = "TavernGoldLabel"
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_gold_label)

	column.add_child(HSeparator.new())

	_menu_view = VBoxContainer.new()
	_menu_view.name = "TavernMenuView"
	_menu_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_menu_view.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu_view.add_theme_constant_override("separation", 14)
	column.add_child(_menu_view)
	_build_menu_view()

	_sell_view = VBoxContainer.new()
	_sell_view.name = "TavernSellView"
	_sell_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sell_view.add_theme_constant_override("separation", 8)
	_sell_view.visible = false
	column.add_child(_sell_view)
	_build_sell_view()

	_merc_view = VBoxContainer.new()
	_merc_view.name = "TavernMercenaryView"
	_merc_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_merc_view.alignment = BoxContainer.ALIGNMENT_CENTER
	_merc_view.add_theme_constant_override("separation", 14)
	_merc_view.visible = false
	column.add_child(_merc_view)
	_build_mercenary_view()


func _build_menu_view() -> void:
	var sell_button := _make_button("出售俘虏", "TavernSellPrisonersButton")
	sell_button.custom_minimum_size = Vector2(260.0, 44.0)
	sell_button.pressed.connect(_show_sell_view)
	_menu_view.add_child(sell_button)

	var merc_button := _make_button("查看雇佣兵信息", "TavernMercenariesButton")
	merc_button.custom_minimum_size = Vector2(260.0, 44.0)
	merc_button.pressed.connect(_show_mercenary_view)
	_menu_view.add_child(merc_button)

	# 内嵌时按钮语义是切回城镇信息，而不是关闭独立窗口。
	var leave_text: String = "返回城镇" if _embedded else "离开酒馆"
	var leave_button := _make_button(leave_text, "TavernLeaveButton")
	leave_button.custom_minimum_size = Vector2(260.0, 44.0)
	leave_button.pressed.connect(close)
	_menu_view.add_child(leave_button)


func _build_sell_view() -> void:
	# 嵌入城镇面板时空间较窄，两栏改为上下排列；独立窗口仍使用左右两栏。
	var lists: BoxContainer = null
	if _embedded:
		lists = VBoxContainer.new()
	else:
		lists = HBoxContainer.new()
	lists.name = "TavernSellLists"
	lists.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lists.add_theme_constant_override("separation", 6 if _embedded else 16)
	_sell_view.add_child(lists)

	var buyer_column := VBoxContainer.new()
	buyer_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lists.add_child(buyer_column)
	buyer_column.add_child(_make_label("城镇买方接收", 15))
	var buyer_scroll := _make_scroll("TavernBuyerList", buyer_column)
	_buyer_list = buyer_scroll
	_buyer_empty = _make_label("尚未选择要出售的俘虏。", 12)
	_buyer_empty.name = "TavernBuyerEmpty"
	buyer_column.add_child(_buyer_empty)

	var player_column := VBoxContainer.new()
	player_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lists.add_child(player_column)
	player_column.add_child(_make_label("玩家当前俘虏", 15))
	var player_scroll := _make_scroll("TavernPlayerPrisonerList", player_column)
	_player_list = player_scroll
	_player_empty = _make_label("没有可出售的俘虏。", 12)
	_player_empty.name = "TavernPlayerPrisonerEmpty"
	player_column.add_child(_player_empty)

	_total_label = _make_label("", 14)
	_total_label.name = "TavernTotalLabel"
	_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sell_view.add_child(_total_label)

	_feedback_label = _make_label("", 13)
	_feedback_label.name = "TavernFeedbackLabel"
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sell_view.add_child(_feedback_label)

	var buttons := HBoxContainer.new()
	buttons.name = "TavernSellButtons"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	_sell_view.add_child(buttons)

	var reset_button := _make_button("一键重置", "TavernSellResetButton")
	reset_button.pressed.connect(reset_sale)
	buttons.add_child(reset_button)

	_confirm_button = _make_button("确认交易", "TavernSellConfirmButton")
	_confirm_button.pressed.connect(_on_confirm_sale)
	buttons.add_child(_confirm_button)

	var back_button := _make_button("返回酒馆", "TavernSellBackButton")
	back_button.pressed.connect(_show_menu)
	buttons.add_child(back_button)


func _build_mercenary_view() -> void:
	var label := _make_label("雇佣兵信息尚未开放。", 16)
	label.name = "TavernMercenaryPlaceholder"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_merc_view.add_child(label)
	var back_button := _make_button("返回酒馆", "TavernMercenaryBackButton")
	back_button.pressed.connect(_show_menu)
	_merc_view.add_child(back_button)


# ---------------------------------------------------------------------------
# 视图切换
# ---------------------------------------------------------------------------


func _show_menu() -> void:
	_menu_view.visible = true
	_sell_view.visible = false
	_merc_view.visible = false
	_refresh_gold()


func _show_sell_view() -> void:
	if _context == null:
		return
	_sell_ids.clear()
	_feedback_text = ""
	_initial_prisoner_ids = _current_player_prisoners()
	_menu_view.visible = false
	_merc_view.visible = false
	_sell_view.visible = true
	_refresh_sell_view()


func _show_mercenary_view() -> void:
	_menu_view.visible = false
	_sell_view.visible = false
	_merc_view.visible = true


# ---------------------------------------------------------------------------
# 出售预览
# ---------------------------------------------------------------------------


func _current_player_prisoners() -> Array[String]:
	if _context == null:
		return []
	return _context.party_manager.get_prisoner_ids(_context.player_party_id)


func _refresh_gold() -> void:
	if _context == null:
		return
	_gold_label.text = "金币：%d" % _context.player_profile.gold


func _refresh_sell_view() -> void:
	if _context == null or _player_list == null:
		return
	_clear_list(_buyer_list)
	_clear_list(_player_list)

	for unit_id: String in _sell_ids:
		var row := _make_prisoner_button(unit_id, "撤回")
		row.name = "TavernBuyer_%s" % unit_id
		row.pressed.connect(_on_withdraw_pressed.bind(unit_id))
		_buyer_list.add_child(row)

	for unit_id: String in _initial_prisoner_ids:
		if _sell_ids.has(unit_id):
			continue
		var row := _make_prisoner_button(unit_id, "卖出")
		row.name = "TavernPlayer_%s" % unit_id
		row.pressed.connect(_on_sell_pressed.bind(unit_id))
		_player_list.add_child(row)

	_buyer_empty.visible = _sell_ids.is_empty()
	_player_empty.visible = _initial_prisoner_ids.size() - _sell_ids.size() <= 0
	var total: int = 0
	for unit_id: String in _sell_ids:
		total += _context.prisoner_trade_manager.get_sell_price(
			_context.unit_manager.get_unit(unit_id)
		)
	_total_label.text = "本次出售 %d 名俘虏，预计获得 %d 金币" % [
		_sell_ids.size(), total
	]
	_feedback_label.text = _feedback_text
	_confirm_button.disabled = _sell_ids.is_empty()
	_refresh_gold()


func _on_sell_pressed(unit_id: String) -> void:
	if _sell_ids.has(unit_id) or not _initial_prisoner_ids.has(unit_id):
		return
	_sell_ids.append(unit_id)
	_feedback_text = ""
	_refresh_sell_view()


func _on_withdraw_pressed(unit_id: String) -> void:
	if not _sell_ids.has(unit_id):
		return
	_sell_ids.erase(unit_id)
	_feedback_text = ""
	_refresh_sell_view()


func reset_sale() -> void:
	_sell_ids.clear()
	_feedback_text = ""
	_refresh_sell_view()


func _on_confirm_sale() -> void:
	if _context == null or _settlement == null or _sell_ids.is_empty():
		return
	var result: Dictionary = _context.prisoner_trade_manager.sell_prisoners(
		_context.player_party_id, _sell_ids.duplicate(), _settlement.settlement_id
	)
	if not bool(result.get("success", false)):
		_feedback_text = "交易失败：%s" % str(result.get("reason", "未知原因"))
		_refresh_sell_view()
		return

	var sold_count: int = (result.get("sold_unit_ids", []) as Array).size()
	var gold: int = int(result.get("gold", 0))
	_feedback_text = "已出售 %d 名俘虏，获得 %d 金币。" % [sold_count, gold]
	_sell_ids.clear()
	# 成交后以最新归属为准，未出售的俘虏继续显示。
	_initial_prisoner_ids = _current_player_prisoners()
	_refresh_sell_view()
	prisoners_sold.emit(result)


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------


func _make_prisoner_button(unit_id: String, action_text: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0.0, ROW_MIN_HEIGHT)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.text = "%s    %s" % [_describe_unit(unit_id), action_text]
	return button


func _describe_unit(unit_id: String) -> String:
	if _context == null:
		return unit_id
	var unit := _context.unit_manager.get_unit(unit_id)
	if unit == null:
		return unit_id
	var unit_name: String = unit.display_name
	var config := _context.unit_manager.get_unit_config(unit.config_id)
	if unit_name.is_empty() and config != null:
		unit_name = config.display_name
	if unit_name.is_empty():
		unit_name = unit_id
	var identity: String = config.display_name if config != null else unit.config_id
	return "%s    Lv.%d    %s" % [unit_name, unit.level, identity]


func _make_scroll(node_name: String, parent: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	# 嵌入城镇面板时两栏上下排列，单栏高度压缩；独立窗口保持原高度。
	scroll.custom_minimum_size = Vector2(0.0, 110.0 if _embedded else 360.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = node_name
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	return list


func _clear_list(list: VBoxContainer) -> void:
	if list == null:
		return
	for child: Node in list.get_children():
		list.remove_child(child)
		child.queue_free()


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _make_button(text: String, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(150.0, 36.0)
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
