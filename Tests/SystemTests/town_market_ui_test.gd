extends Node
## 阶段 11 城镇市场 UI 测试：
## 城镇/村庄/城堡入口差异、双栏预览、取消不改数据、确认原子结算、
## 金币不足禁用确认、交易日志与存档恢复。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/town_market_ui_test.tscn

const TEST_SLOT: String = "__town_market_ui__"
const HORSE_ID: String = "mount_horse_01"

var _failed: bool = false
var _context: WorldContext = null
var _map: Node = null
var _player: PartyData = null
var _town: SettlementData = null
var _village: SettlementData = null
var _castle: SettlementData = null
var _settlement_panel: PanelContainer = null
var _market: MarketPanel = null
var _market_button: Button = null


func _ready() -> void:
	await _run()
	SaveManager.delete_save(TEST_SLOT)
	_cleanup()
	if _failed:
		push_error("[marketui] 测试失败")
		get_tree().quit(1)
	else:
		print("[marketui] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)

	_context = WorldContext.new()
	_context.name = "TownMarketUiContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return
	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id
	_player = _context.get_player_party()
	_town = _find_settlement(WorldInitializer.BURKNANIA_TOWN_NAME)
	_village = _find_settlement(WorldInitializer.BARI_VILLAGE_NAME)
	_castle = _find_settlement(WorldInitializer.OLIN_CASTLE_NAME)
	_check(
		_player != null and _town != null and _village != null and _castle != null,
		"找到玩家、城镇、村庄与城堡"
	)
	if _player == null or _town == null or _village == null or _castle == null:
		return

	var packed := load("res://Scenes/WorldMap/world_map.tscn") as PackedScene
	_map = packed.instantiate()
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame

	_settlement_panel = _map.find_child("SettlementPanel", true, false) as PanelContainer
	_market = _map.find_child("MarketPanel", true, false) as MarketPanel
	_market_button = _map.find_child(
		"SettlementMarketButton", true, false
	) as Button
	_check(
		_settlement_panel != null and _market != null and _market_button != null,
		"地点面板、市场面板与市场按钮存在"
	)
	if _settlement_panel == null or _market == null or _market_button == null:
		return

	_check(
		_context.market_manager.get_stock(_town.settlement_id, HORSE_ID) == 3,
		"新世界城镇市场初始有 3 匹战马"
	)

	_test_entry_visibility()
	_test_inventory_panel()
	_test_village_market_ui()
	_test_open_market_and_preview()
	_test_cancel_keeps_real_data()
	_test_confirm_and_log()
	_test_gold_insufficient()
	_test_save_reload_stock()


func _test_entry_visibility() -> void:
	_prepare_player_far(_village, Vector2(20.0, 0.0))
	_click_and_arrive(_village)
	_check(_settlement_panel.visible, "村庄面板打开")
	_check(_market_button.visible, "村庄显示购买补给入口")
	_check(_market_button.text == "购买补给", "村庄入口文案为购买补给")
	_close_settlement_panel()

	_prepare_player_far(_castle, Vector2(20.0, 0.0))
	_click_and_arrive(_castle)
	_check(_settlement_panel.visible, "城堡面板打开")
	_check(not _market_button.visible, "城堡不显示市场入口")
	_close_settlement_panel()

	_prepare_player_far(_town, Vector2(20.0, 0.0))
	_click_and_arrive(_town)
	_check(_settlement_panel.visible, "城镇面板打开")
	_check(_market_button.visible, "城镇显示交易市场入口")
	_check(_market_button.text == "交易市场", "城镇入口文案为交易市场")
	var enter_button := _map.find_child(
		"SettlementEnterButton", true, false
	) as Button
	_check(enter_button != null and not enter_button.visible, "城镇不显示进入村庄入口")
	_close_settlement_panel()


func _test_inventory_panel() -> void:
	var inventory_button := _map.find_child(
		"InventoryButton", true, false
	) as Button
	_check(inventory_button != null, "大地图提供背包入口")
	if inventory_button == null:
		return
	inventory_button.pressed.emit()
	var inventory := _map.find_child("InventoryPanel", true, false) as Control
	_check(inventory != null and inventory.visible, "点击背包打开背包面板")
	if inventory == null:
		return
	var gold_label := inventory.find_child("InventoryGoldLabel", true, false) as Label
	_check(
		gold_label != null
			and gold_label.text == "当前金币：%s" % GoldUtils.format(
				float(_context.player_profile.gold)
			),
		"背包金币与实际金币一致"
	)
	var horse_item := inventory.find_child(
		"InventoryItem_%s" % HORSE_ID, true, false
	) as Button
	_check(horse_item != null, "背包显示普通战马条目")
	if horse_item != null:
		_check(
			horse_item.text.contains("普通战马")
				and horse_item.text.contains(
					"×%d" % _context.player_profile.get_item_count(HORSE_ID)
				),
			"背包条目显示名称与当前数量"
		)
	_check(
		inventory.find_child("InventoryItem_promotion_rank_token", true, false) != null,
		"背包按物品 ID 合并显示晋升凭证"
	)
	_check(
		TimeManager.has_pause_reason(GameManager.PAUSE_REASON_UI_PANEL),
		"背包打开期间压入 UI 暂停"
	)
	var close_button := inventory.find_child(
		"InventoryCloseButton", true, false
	) as Button
	_check(close_button != null, "背包提供关闭按钮")
	if close_button != null:
		close_button.pressed.emit()
	_check(not inventory.visible, "关闭按钮关闭背包")
	_check(
		not TimeManager.has_pause_reason(GameManager.PAUSE_REASON_UI_PANEL),
		"关闭背包释放 UI 暂停原因"
	)


## 村庄市场与大地图共用 MarketPanel：只卖补给，批量按钮一次移动指定数量。
func _test_village_market_ui() -> void:
	_prepare_player_far(_village, Vector2(20.0, 0.0))
	_click_and_arrive(_village)
	_market_button.pressed.emit()
	_check(_market.visible, "点击购买补给打开村庄市场")
	var title := _market.find_child("MarketTitleLabel", true, false) as Label
	_check(
		title != null and title.text.contains(_village.display_name)
			and title.text.contains("村庄补给"),
		"村庄市场标题显示村庄补给"
	)
	_check(
		_market.find_child("MarketGoodsRow_bread", true, false) != null,
		"村庄市场显示面包"
	)
	_check(
		_market.find_child("MarketGoodsRow_fodder", true, false) != null,
		"村庄市场显示草料"
	)
	_check(
		_market.find_children("MarketGoodsRow_%s_*" % HORSE_ID, "PanelContainer", true, false).is_empty(),
		"村庄市场不显示马匹"
	)

	var bread_before: int = _context.player_profile.get_item_count("bread")
	var stock_before: int = _context.market_manager.get_stock(
		_village.settlement_id, "bread"
	)
	var gold_before: float = _context.player_profile.gold
	_press_button("MarketBuyButton_bread_10")
	_check(_market.get_preview_purchase_count("bread") == 10, "批量按钮预览购买 10 份面包")
	_check(
		is_equal_approx(_market.get_purchase_total(), 3.0),
		"面包批量购买按动态单价 0.3 计算，总价 3.0"
	)
	_check(
		_context.player_profile.get_item_count("bread") == bread_before,
		"村庄交易预览不修改真实背包"
	)
	_press_button("MarketResetButton")
	_check(_market.get_preview_purchase_count("bread") == 0, "重置交易恢复打开时状态")
	_check(_market.get_purchase_total() == 0.0, "重置后金额归零")

	_press_button("MarketBuyButton_bread_10")
	_press_button("MarketConfirmButton")
	_check(
		_context.player_profile.get_item_count("bread") == bread_before + 10,
		"村庄确认后获得 10 份面包"
	)
	_check(
		_context.market_manager.get_stock(_village.settlement_id, "bread")
			== stock_before - 10,
		"村庄确认后市场库存减少 10"
	)
	_check(
		is_equal_approx(_context.player_profile.gold, gold_before - 3.0),
		"村庄确认后按 0.3 单价扣款 3.0"
	)
	_press_button("MarketCancelButton")
	_close_settlement_panel()


func _test_open_market_and_preview() -> void:
	_prepare_player_far(_town, Vector2(20.0, 0.0))
	_click_and_arrive(_town)
	_market_button.pressed.emit()
	_check(_market.visible, "点击交易市场打开市场面板")
	_check(not _settlement_panel.visible, "市场打开时隐藏地点面板")
	_check(
		TimeManager.has_pause_reason(GameManager.PAUSE_REASON_UI_PANEL),
		"市场打开期间保持 UI 暂停"
	)
	var title := _market.find_child("MarketTitleLabel", true, false) as Label
	_check(
		title != null and title.text.contains(_town.display_name),
		"市场标题显示当前城镇名称"
	)
	_check(
		not _market.find_children(
			"MarketGoodsRow_%s_*" % HORSE_ID, "PanelContainer", true, false
		).is_empty(),
		"左栏逐匹显示市场马匹"
	)
	_check(
		not _market.find_children(
			"MarketPlayerRow_%s_*" % HORSE_ID, "PanelContainer", true, false
		).is_empty(),
		"右栏逐匹显示玩家背包马匹"
	)
	_check(not _market.is_confirm_enabled(), "没有交易预览时确认按钮禁用")

	var stock_before: int = _context.market_manager.get_stock(
		_town.settlement_id, HORSE_ID
	)
	var count_before: int = _context.player_profile.get_item_count(HORSE_ID)
	var gold_before: float = _context.player_profile.gold
	# 前面的村庄交易已合法写入日志；这里只验证预览不新增日志。
	var log_before: int = _context.world_log_manager.get_entry_count()

	_press_first("MarketBuyButton_%s_*" % HORSE_ID)
	_check(_market.get_preview_purchase_count(HORSE_ID) == 1, "购买预览数量增加 1")
	_check(_market.get_purchase_total() == 150.0, "购买总价实时计算为 150")
	_check(_market.get_net_amount() == 150.0, "净交易金额实时计算为 150")
	_check(_market.is_confirm_enabled(), "金币充足时可以确认交易")

	# 预览不得提前修改任何真实数据。
	_check(
		_context.market_manager.get_stock(_town.settlement_id, HORSE_ID) == stock_before,
		"交易预览不修改真实市场库存"
	)
	_check(
		_context.player_profile.get_item_count(HORSE_ID) == count_before,
		"交易预览不修改玩家背包"
	)
	_check(_context.player_profile.gold == gold_before, "交易预览不修改玩家金币")
	_check(
		_context.world_log_manager.get_entry_count() == log_before,
		"交易预览不写世界日志"
	)
	_press_button("MarketResetButton")
	_check(not _market.has_preview(), "重置后回到打开交易时的状态")


func _test_cancel_keeps_real_data() -> void:
	var stock_before: int = _context.market_manager.get_stock(
		_town.settlement_id, HORSE_ID
	)
	var count_before: int = _context.player_profile.get_item_count(HORSE_ID)
	var gold_before: int = _context.player_profile.gold
	var log_before: int = _context.world_log_manager.get_entry_count()
	_press_button("MarketCancelButton")
	_check(not _market.visible, "取消交易关闭市场")
	_check(_settlement_panel.visible, "取消交易后恢复地点面板")
	_check(
		_context.market_manager.get_stock(_town.settlement_id, HORSE_ID) == stock_before,
		"取消交易不修改市场库存"
	)
	_check(
		_context.player_profile.get_item_count(HORSE_ID) == count_before,
		"取消交易不修改玩家背包"
	)
	_check(_context.player_profile.gold == gold_before, "取消交易不修改金币")
	_check(
		_context.world_log_manager.get_entry_count() == log_before,
		"取消交易不写日志"
	)
	_check(
		TimeManager.has_pause_reason(GameManager.PAUSE_REASON_UI_PANEL),
		"返回地点面板后继续保持暂停"
	)


func _test_confirm_and_log() -> void:
	_market_button.pressed.emit()
	_check(_market.visible, "从地点面板重新打开市场")
	var stock_before: int = _context.market_manager.get_stock(
		_town.settlement_id, HORSE_ID
	)
	var count_before: int = _context.player_profile.get_item_count(HORSE_ID)
	var gold_before: float = _context.player_profile.gold
	var log_before: int = _context.world_log_manager.get_entry_count()

	_press_first("MarketBuyButton_%s_*" % HORSE_ID)
	_press_button("MarketConfirmButton")
	_check(
		_context.market_manager.get_stock(_town.settlement_id, HORSE_ID)
			== stock_before - 1,
		"确认后市场库存减少 1"
	)
	_check(
		_context.player_profile.get_item_count(HORSE_ID) == count_before + 1,
		"确认后玩家背包增加 1"
	)
	_check(_context.player_profile.gold == gold_before - 150.0, "确认后扣除 150 金币")
	_check(_market.visible, "确认交易后市场保持打开")
	_check(_market.get_preview_purchase_count(HORSE_ID) == 0, "确认后清空交易预览")
	_check(not _market.is_confirm_enabled(), "确认后确认按钮重新禁用")
	_check(
		_context.world_log_manager.get_entry_count() == log_before + 1,
		"成功交易写入一条世界日志"
	)
	var last_entry: WorldLogEntry = _context.world_log_manager.get_entries().back()
	_check(
		last_entry.event_type == WorldLogEntry.EventType.PLAYER_TRADE,
		"交易日志类型为 PLAYER_TRADE"
	)
	_check(
		last_entry.text.contains("购买了普通战马 ×1")
			and last_entry.text.contains("支付 150 金币"),
		"交易日志记录物品与金币变化"
	)

	# 市场仍打开时，只读背包面板数据应已同步到最新权威数据。
	var inventory := _map.find_child("InventoryPanel", true, false) as Control
	if inventory != null:
		var horse_item := inventory.find_child(
			"InventoryItem_%s" % HORSE_ID, true, false
		) as Button
		_check(
			horse_item != null
				and horse_item.text.contains(
					"×%d" % _context.player_profile.get_item_count(HORSE_ID)
				),
			"交易成功后背包面板数据同步刷新"
		)


func _test_gold_insufficient() -> void:
	_context.player_profile.gold = 10
	_market.refresh()
	_press_first("MarketBuyButton_%s_*" % HORSE_ID)
	_check(_market.get_net_amount() == 150.0, "金币不足时仍显示应付金额")
	_check(not _market.is_confirm_enabled(), "金币不足时禁用确认交易")
	_check(_market.get_status_text().contains("金币不足"), "界面明确提示金币不足")
	_check(
		_context.player_profile.gold == 10
			and _context.market_manager.get_stock(_town.settlement_id, HORSE_ID) >= 0,
		"金币不足时未发生任何结算"
	)
	_press_button("MarketCancelButton")
	_check(not _market.visible, "金币不足可取消返回地点面板")
	_check(_settlement_panel.visible, "金币不足取消后恢复地点面板")
	_context.player_profile.gold = 1000


func _test_save_reload_stock() -> void:
	var stored_stock: int = _context.market_manager.get_stock(
		_town.settlement_id, HORSE_ID
	)
	var stored_gold: float = _context.player_profile.gold
	var stored_count: int = _context.player_profile.get_item_count(HORSE_ID)
	_check(SaveManager.save_game(TEST_SLOT, _context.to_save_data()) == OK, "市场存档成功")
	var loaded := SaveManager.load_game(TEST_SLOT)
	_check(loaded != null, "读取市场存档")
	if loaded == null:
		return
	var restored := WorldContext.new()
	restored.name = "TownMarketRestoredContext"
	add_child(restored)
	_check(restored.load_from_save_data(loaded), "恢复包含市场库存的世界")
	_check(
		restored.market_manager.get_stock(_town.settlement_id, HORSE_ID)
			== stored_stock,
		"读档恢复城镇市场库存，不重置为初始值"
	)
	_check(restored.player_profile.gold == stored_gold, "读档恢复交易后的金币")
	_check(
		restored.player_profile.get_item_count(HORSE_ID) == stored_count,
		"读档恢复交易后的玩家物品"
	)
	_check(
		restored.market_manager.get_market(_village.settlement_id) != null,
		"读档恢复村庄补给市场"
	)
	restored.queue_free()

	# 旧存档缺少 markets 字段：读档时按当前配置初始化一次。
	var old_payload := SaveData.from_dict(loaded.to_dict())
	_check(old_payload != null, "复制旧格式存档")
	if old_payload != null:
		old_payload.markets = {}
		var old_restored := WorldContext.new()
		old_restored.name = "TownMarketOldSaveContext"
		add_child(old_restored)
		_check(old_restored.load_from_save_data(old_payload), "旧存档缺少市场数据时仍可读档")
		_check(
			old_restored.market_manager.get_stock(_town.settlement_id, HORSE_ID) == 3,
			"旧存档按商品配置补入初始市场库存"
		)
		old_restored.queue_free()


func _press_button(button_name: String) -> void:
	var button := _market.find_child(button_name, true, false) as Button
	_check(button != null, "找到按钮 %s" % button_name)
	if button != null:
		button.pressed.emit()


func _press_first(pattern: String) -> void:
	var buttons: Array[Node] = _market.find_children(pattern, "Button", true, false)
	_check(not buttons.is_empty(), "找到按钮 %s" % pattern)
	if not buttons.is_empty():
		(buttons[0] as Button).pressed.emit()


func _prepare_player_far(
	settlement: SettlementData, offset: Vector2
) -> void:
	_player.focus_party_id = ""
	_player.current_order = PartyData.OrderType.NONE
	_player.current_target_id = ""
	_player.world_position = settlement.world_position + offset
	_player.target_position = _player.world_position
	_player.movement_state = PartyData.MovementState.IDLE


func _click_and_arrive(settlement: SettlementData) -> void:
	_map.call("handle_left_click", settlement.world_position)
	_player.world_position = settlement.world_position
	_player.target_position = settlement.world_position
	_player.movement_state = PartyData.MovementState.IDLE
	_map.call("_check_pending_settlement_interaction")


func _close_settlement_panel() -> void:
	_map.call("_on_settlement_leave_pressed")


func _find_settlement(display_name: String) -> SettlementData:
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement != null and settlement.display_name == display_name:
			return settlement
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[marketui] OK: %s" % message)
	else:
		_failed = true
		push_error("[marketui] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_map):
		_map.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
