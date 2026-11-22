class_name MarketPanel
extends Control
## 村庄/城镇双栏交易界面（阶段 12）。
##
## 左栏是市场库存，右栏是玩家背包。所有移动只发生在 TradeSession 的预览快照里：
## - 购买后商品立即从左侧减少、在右侧增加；出售相反；
## - “重置交易”恢复打开界面时的原始状态；
## - “取消交易”直接丢弃预览；
## - 只有“确认交易”才调用 MarketManager 做原子结算。
##
## 马匹逐匹显示，每匹马保留独立外观；面包/草料等堆叠物品显示数量与批量按钮。
## 打开/关闭的暂停状态由 WorldMap 沿用地点面板的 ui_pause 原因。

signal closed
## 交易成功后广播结果，供 WorldMap 刷新其他只读面板。
signal traded(result: Dictionary)

const WINDOW_SIZE := Vector2(1220.0, 700.0)
const ROW_ICON_SIZE := Vector2(40.0, 40.0)
const INFO_MODULATE := Color(0.82, 0.82, 0.78)

var _context: WorldContext = null
var _settlement: SettlementData = null
var _session: TradeSession = null
var _feedback_text: String = ""

var _title_label: Label = null
var _gold_label: Label = null
var _market_list: VBoxContainer = null
var _player_list: VBoxContainer = null
var _market_empty_label: Label = null
var _player_empty_label: Label = null
var _purchase_total_label: Label = null
var _sale_total_label: Label = null
var _net_label: Label = null
var _status_label: Label = null
var _reset_button: Button = null
var _confirm_button: Button = null
var _cancel_button: Button = null


func setup(context: WorldContext) -> void:
	_context = context
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_full_rect(self)
	_build()


## 打开指定村庄/城镇市场；城堡或市场不可用时返回 false。
func open(settlement: SettlementData) -> bool:
	if _context == null or settlement == null:
		return false
	if not _context.market_manager.is_market_settlement(settlement):
		return false
	if _context.market_manager.get_market(settlement.settlement_id) == null:
		if not _context.market_manager.initialize_market(settlement):
			return false
	var session := TradeSession.new()
	if not session.setup(
		_context.market_manager, settlement.settlement_id, _context.player_profile
	):
		return false
	_settlement = settlement
	_session = session
	_feedback_text = ""
	_title_label.text = _title_for(settlement)
	visible = true
	refresh()
	return true


func close() -> void:
	_session = null
	_feedback_text = ""
	_settlement = null
	visible = false
	closed.emit()


func get_settlement_id() -> String:
	return _settlement.settlement_id if _settlement != null else ""


func get_trade_session() -> TradeSession:
	return _session


# ---------------------------------------------------------------------------
# 测试/外部只读接口
# ---------------------------------------------------------------------------


func get_preview_purchase_count(item_id: String) -> int:
	if _session == null:
		return 0
	return int(_session.get_purchase_items().get(item_id, 0))


func get_preview_sale_count(item_id: String) -> int:
	if _session == null:
		return 0
	return int(_session.get_sale_items().get(item_id, 0))


func get_purchase_total() -> int:
	return _session.get_purchase_total() if _session != null else 0


func get_sale_total() -> int:
	return _session.get_sale_total() if _session != null else 0


func get_net_amount() -> int:
	return _session.get_net_amount() if _session != null else 0


func is_confirm_enabled() -> bool:
	return _confirm_button != null and not _confirm_button.disabled


func get_status_text() -> String:
	return _status_label.text if _status_label != null else ""


func has_preview() -> bool:
	return _session != null and _session.has_preview()


func get_preview_market_count(item_id: String) -> int:
	return _session.get_market_count(item_id) if _session != null else 0


func get_preview_player_count(item_id: String) -> int:
	return _session.get_player_count(item_id) if _session != null else 0


# ---------------------------------------------------------------------------
# 刷新
# ---------------------------------------------------------------------------


func refresh() -> void:
	if _context == null or _settlement == null or _session == null:
		return
	_gold_label.text = "当前金币：%d" % _context.player_profile.gold
	_rebuild_market_list()
	_rebuild_player_list()
	_update_totals()


func _title_for(settlement: SettlementData) -> String:
	if settlement.settlement_type == SettlementData.SettlementType.VILLAGE:
		return "%s · 村庄补给" % settlement.display_name
	return "%s · 交易市场" % settlement.display_name


# ---------------------------------------------------------------------------
# 列表构建
# ---------------------------------------------------------------------------


func _rebuild_market_list() -> void:
	_clear_children(_market_list)
	var configs: Array[MarketGoodsConfig] = \
		_context.market_manager.get_goods_configs_for_settlement(
			_settlement.settlement_id
		)
	var row_count: int = 0
	for config: MarketGoodsConfig in configs:
		var item_id: String = config.item_id
		if MountInstanceData.is_mount_item(item_id):
			var instances: Array[MountInstanceData] = \
				_session.get_market_mount_instances_for(item_id)
			for instance: MountInstanceData in instances:
				_add_market_mount_row(config, instance)
				row_count += 1
		else:
			_add_market_stackable_row(config)
			row_count += 1
	_market_empty_label.visible = row_count == 0


func _add_market_stackable_row(config: MarketGoodsConfig) -> void:
	var item_id: String = config.item_id
	var preview_stock: int = _session.get_market_count(item_id)
	var row := _make_row(_market_list, "MarketGoodsRow_%s" % item_id)
	row.add_child(_make_item_icon(item_id))

	var info := _make_info_column(row)
	var name_label := _make_label(
		_context.market_manager.get_item_display_name(item_id), 16
	)
	name_label.name = "MarketGoodsName_%s" % item_id
	info.add_child(name_label)
	var detail_text: String = "库存：%d    单价：%d" % [
		preview_stock, maxi(0, config.buy_price)
	]
	if preview_stock <= 0:
		detail_text += "    （已售罄）"
	var detail := _make_label(detail_text, 13)
	detail.name = "MarketGoodsStock_%s" % item_id
	detail.modulate = INFO_MODULATE
	info.add_child(detail)

	var buy_button := _make_button(
		"MarketBuyButton_%s" % item_id,
		"购买 ×1",
		Vector2(96.0, 32.0)
	)
	buy_button.disabled = not config.can_buy() or preview_stock <= 0
	buy_button.pressed.connect(_on_buy_pressed.bind(item_id, 1))
	row.add_child(buy_button)

	if config.is_stackable:
		for amount: int in config.batch_purchase_amounts:
			if amount <= 1:
				continue
			var batch_button := _make_button(
				"MarketBuyButton_%s_%d" % [item_id, amount],
				"×%d" % amount,
				Vector2(56.0, 32.0)
			)
			batch_button.disabled = not config.can_buy() or preview_stock <= 0
			batch_button.pressed.connect(_on_buy_pressed.bind(item_id, amount))
			row.add_child(batch_button)


func _add_market_mount_row(
	config: MarketGoodsConfig,
	instance: MountInstanceData
) -> void:
	var item_id: String = config.item_id
	var row := _make_row(
		_market_list,
		"MarketGoodsRow_%s_%s" % [item_id, instance.instance_id]
	)
	row.add_child(_make_mount_icon(instance))

	var info := _make_info_column(row)
	var name_label := _make_label(_mount_title(config, instance), 16)
	name_label.name = "MarketGoodsName_%s_%s" % [item_id, instance.instance_id]
	info.add_child(name_label)
	var detail := _make_label(
		"市场待售 %d 匹 · 售价 %d" % [
			_session.get_market_count(item_id), maxi(0, config.buy_price)
		],
		13
	)
	detail.name = "MarketGoodsStock_%s_%s" % [item_id, instance.instance_id]
	detail.modulate = INFO_MODULATE
	info.add_child(detail)

	var buy_button := _make_button(
		"MarketBuyButton_%s_%s" % [item_id, instance.instance_id],
		"购买",
		Vector2(96.0, 32.0)
	)
	buy_button.disabled = not config.can_buy()
	buy_button.pressed.connect(
		_on_buy_mount_pressed.bind(instance.instance_id)
	)
	row.add_child(buy_button)


func _rebuild_player_list() -> void:
	_clear_children(_player_list)
	var configs: Array[MarketGoodsConfig] = \
		_context.market_manager.get_goods_configs_for_settlement(
			_settlement.settlement_id
		)
	var row_count: int = 0
	for config: MarketGoodsConfig in configs:
		var item_id: String = config.item_id
		if MountInstanceData.is_mount_item(item_id):
			var instances: Array[MountInstanceData] = \
				_session.get_player_mount_instances_for(item_id)
			for instance: MountInstanceData in instances:
				_add_player_mount_row(config, instance)
				row_count += 1
		else:
			if _session.get_player_count(item_id) <= 0:
				continue
			_add_player_stackable_row(config)
			row_count += 1
	_player_empty_label.visible = row_count == 0


func _add_player_stackable_row(config: MarketGoodsConfig) -> void:
	var item_id: String = config.item_id
	var preview_count: int = _session.get_player_count(item_id)
	var row := _make_row(_player_list, "MarketPlayerRow_%s" % item_id)
	row.add_child(_make_item_icon(item_id))

	var info := _make_info_column(row)
	var name_label := _make_label(
		_context.market_manager.get_item_display_name(item_id), 16
	)
	name_label.name = "MarketPlayerName_%s" % item_id
	info.add_child(name_label)
	var detail_text: String = "数量：%d" % preview_count
	if config.can_sell():
		detail_text += "    收购价：%d" % config.sell_price
	else:
		detail_text += "    不可出售"
	var detail := _make_label(detail_text, 13)
	detail.name = "MarketPlayerCount_%s" % item_id
	detail.modulate = INFO_MODULATE
	info.add_child(detail)

	var sell_button := _make_button(
		"MarketSellButton_%s" % item_id,
		"出售 ×1",
		Vector2(96.0, 32.0)
	)
	sell_button.visible = config.can_sell()
	sell_button.disabled = not config.can_sell() or preview_count <= 0
	sell_button.pressed.connect(_on_sell_pressed.bind(item_id, 1))
	row.add_child(sell_button)


func _add_player_mount_row(
	config: MarketGoodsConfig,
	instance: MountInstanceData
) -> void:
	var item_id: String = config.item_id
	var row := _make_row(
		_player_list,
		"MarketPlayerRow_%s_%s" % [item_id, instance.instance_id]
	)
	row.add_child(_make_mount_icon(instance))

	var info := _make_info_column(row)
	var name_label := _make_label(_mount_title(config, instance), 16)
	name_label.name = "MarketPlayerName_%s_%s" % [item_id, instance.instance_id]
	info.add_child(name_label)
	var detail_text: String = "坐骑"
	if config.can_sell():
		detail_text += "    收购价：%d" % config.sell_price
	else:
		detail_text += "    不可出售"
	var detail := _make_label(detail_text, 13)
	detail.name = "MarketPlayerCount_%s_%s" % [item_id, instance.instance_id]
	detail.modulate = INFO_MODULATE
	info.add_child(detail)

	var sell_button := _make_button(
		"MarketSellButton_%s_%s" % [item_id, instance.instance_id],
		"出售",
		Vector2(96.0, 32.0)
	)
	sell_button.visible = config.can_sell()
	sell_button.disabled = not config.can_sell()
	sell_button.pressed.connect(
		_on_sell_mount_pressed.bind(instance.instance_id)
	)
	row.add_child(sell_button)


func _mount_title(
	config: MarketGoodsConfig,
	instance: MountInstanceData
) -> String:
	var base_name: String = config.item_id
	if _context != null:
		base_name = _context.market_manager.get_item_display_name(config.item_id)
	var appearance: String = instance.appearance_text()
	if not instance.display_name.is_empty():
		return "%s（%s）" % [instance.display_name, appearance]
	return "%s · %s" % [base_name, appearance]


# ---------------------------------------------------------------------------
# 图标
# ---------------------------------------------------------------------------


func _make_item_icon(item_id: String) -> Control:
	var path: String = ""
	if _context != null:
		path = _context.market_manager.get_item_icon_path(item_id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return _make_icon_placeholder()
	var texture := load(path) as Texture2D
	if texture == null:
		return _make_icon_placeholder()
	var icon := TextureRect.new()
	icon.name = "MarketItemIcon_%s" % item_id
	icon.texture = texture
	icon.custom_minimum_size = ROW_ICON_SIZE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return icon


func _make_mount_icon(instance: MountInstanceData) -> Control:
	var icon := MountThumbnail.new()
	icon.name = "MarketMountIcon_%s" % instance.instance_id
	icon.custom_minimum_size = ROW_ICON_SIZE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.setup_from_instance(instance)
	return icon


func _make_icon_placeholder() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = ROW_ICON_SIZE
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var label := _make_label("?", 18)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return panel


# ---------------------------------------------------------------------------
# 预览操作
# ---------------------------------------------------------------------------


func _on_buy_pressed(item_id: String, amount: int) -> void:
	if _session == null or _settlement == null:
		return
	_session.buy(item_id, amount)
	_feedback_text = ""
	refresh()


func _on_sell_pressed(item_id: String, amount: int) -> void:
	if _session == null or _settlement == null:
		return
	_session.sell(item_id, amount)
	_feedback_text = ""
	refresh()


func _on_buy_mount_pressed(instance_id: String) -> void:
	if _session == null:
		return
	_session.buy_mount_instance(instance_id)
	_feedback_text = ""
	refresh()


func _on_sell_mount_pressed(instance_id: String) -> void:
	if _session == null:
		return
	_session.sell_mount_instance(instance_id)
	_feedback_text = ""
	refresh()


func _on_reset_pressed() -> void:
	if _session == null:
		return
	_session.reset()
	_feedback_text = ""
	refresh()


func _on_confirm_pressed() -> void:
	if _session == null or not is_confirm_enabled():
		return
	var result: Dictionary = _session.commit()
	if bool(result.get("success", false)):
		_feedback_text = _success_text(result)
		traded.emit(result)
	else:
		_feedback_text = "交易失败：%s" % str(result.get("error", "未知错误"))
	refresh()


func _on_cancel_pressed() -> void:
	close()


func _success_text(result: Dictionary) -> String:
	var gold_paid: int = int(result.get("gold_paid", 0))
	var gold_received: int = int(result.get("gold_received", 0))
	if gold_paid > 0:
		return "交易成功，支付 %d 金币。" % gold_paid
	if gold_received > 0:
		return "交易成功，获得 %d 金币。" % gold_received
	return "交易成功。"


# ---------------------------------------------------------------------------
# 金额与状态
# ---------------------------------------------------------------------------


func _update_totals() -> void:
	if _session == null:
		return
	var purchase_total: int = _session.get_purchase_total()
	var sale_total: int = _session.get_sale_total()
	var net_gold: int = _session.get_net_amount()
	_purchase_total_label.text = "玩家购入：%d 金币" % purchase_total
	_sale_total_label.text = "玩家售出：%d 金币" % sale_total
	if net_gold > 0:
		_net_label.text = "最终需要支付：%d 金币" % net_gold
	elif net_gold < 0:
		_net_label.text = "最终将获得：%d 金币" % (-net_gold)
	else:
		_net_label.text = "本次交易无需支付金币"

	_confirm_button.disabled = not _session.is_confirm_enabled()
	_reset_button.disabled = not _session.has_preview()
	if not _feedback_text.is_empty():
		_status_label.text = _feedback_text
		_status_label.modulate = Color(1.0, 0.86, 0.55)
	elif net_gold > int(_context.player_profile.gold):
		_status_label.text = "金币不足：需要 %d 金币，当前 %d 金币" % [
			net_gold, _context.player_profile.gold
		]
		_status_label.modulate = Color(1.0, 0.55, 0.45)
	else:
		_status_label.text = _session.get_status_text()
		_status_label.modulate = Color(1.0, 0.86, 0.55)


# ---------------------------------------------------------------------------
# 界面构建
# ---------------------------------------------------------------------------


func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "MarketPanelDim"
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_set_full_rect(dim)
	add_child(dim)

	var window := PanelContainer.new()
	window.name = "MarketPanelWindow"
	window.anchor_left = 0.5
	window.anchor_top = 0.5
	window.anchor_right = 0.5
	window.anchor_bottom = 0.5
	window.offset_left = -WINDOW_SIZE.x * 0.5
	window.offset_top = -WINDOW_SIZE.y * 0.5
	window.offset_right = WINDOW_SIZE.x * 0.5
	window.offset_bottom = WINDOW_SIZE.y * 0.5
	window.mouse_filter = Control.MOUSE_FILTER_STOP
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

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)

	_title_label = _make_label("交易市场", 24)
	_title_label.name = "MarketTitleLabel"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	_gold_label = _make_label("当前金币：0", 16)
	_gold_label.name = "MarketGoldLabel"
	header.add_child(_gold_label)

	column.add_child(HSeparator.new())

	var content := HBoxContainer.new()
	content.name = "MarketContent"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	column.add_child(content)

	_market_empty_label = _make_label("市场暂无商品", 14)
	_player_empty_label = _make_label("背包中没有可交易物品", 14)

	var market_column := _build_list_column(
		"市场商品", "MarketGoodsScroll", "MarketGoodsList", _market_empty_label
	)
	content.add_child(market_column)
	_market_list = market_column.find_child("MarketGoodsList", true, false) \
		as VBoxContainer

	content.add_child(VSeparator.new())

	var player_column := _build_list_column(
		"玩家背包", "MarketPlayerScroll", "MarketPlayerList", _player_empty_label
	)
	content.add_child(player_column)
	_player_list = player_column.find_child("MarketPlayerList", true, false) \
		as VBoxContainer

	column.add_child(HSeparator.new())

	var totals := GridContainer.new()
	totals.name = "MarketTotals"
	totals.columns = 3
	totals.add_theme_constant_override("h_separation", 28)
	totals.add_theme_constant_override("v_separation", 4)
	column.add_child(totals)

	_purchase_total_label = _make_label("玩家购入：0 金币", 15)
	_purchase_total_label.name = "MarketPurchaseTotalLabel"
	totals.add_child(_purchase_total_label)

	_sale_total_label = _make_label("玩家售出：0 金币", 15)
	_sale_total_label.name = "MarketSaleTotalLabel"
	totals.add_child(_sale_total_label)

	_net_label = _make_label("本次交易无需支付金币", 16)
	_net_label.name = "MarketNetLabel"
	totals.add_child(_net_label)

	_status_label = _make_label("", 14)
	_status_label.name = "MarketStatusLabel"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(0.0, 24.0)
	column.add_child(_status_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)

	_reset_button = _make_button(
		"MarketResetButton", "重置交易", Vector2(140.0, 38.0)
	)
	_reset_button.pressed.connect(_on_reset_pressed)
	buttons.add_child(_reset_button)

	_cancel_button = _make_button(
		"MarketCancelButton", "取消交易", Vector2(140.0, 38.0)
	)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	buttons.add_child(_cancel_button)

	_confirm_button = _make_button(
		"MarketConfirmButton", "确认交易", Vector2(140.0, 38.0)
	)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	buttons.add_child(_confirm_button)


func _build_list_column(
	title_text: String,
	scroll_name: String,
	list_name: String,
	empty_label: Label
) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	column.add_child(_make_label(title_text, 16))

	var scroll := ScrollContainer.new()
	scroll.name = scroll_name
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	column.add_child(scroll)

	var list := VBoxContainer.new()
	list.name = list_name
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	empty_label.visible = false
	column.add_child(empty_label)
	return column


## 创建一行并立即加入列表；返回内部 HBox 供调用方追加内容。
func _make_row(list: VBoxContainer, row_name: String) -> HBoxContainer:
	var panel := PanelContainer.new()
	panel.name = row_name
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0.0, 56.0)
	list.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	return row


func _make_info_column(row: HBoxContainer) -> VBoxContainer:
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)
	return info


func _make_button(
	button_name: String,
	text: String,
	min_size: Vector2
) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = min_size
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return button


func _clear_children(container: Node) -> void:
	if container == null:
		return
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


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
