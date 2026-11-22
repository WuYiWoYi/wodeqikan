extends Node
## 阶段 13 Step 6 测试：城镇酒馆与俘虏出售。
## 覆盖价格配置、原子出售、UI 预览/重置/确认、酒馆三入口与地点面板入口。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/stage13_tavern_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"

var _failed: bool = false
var _militia: UnitConfig = null
var _context: WorldContext = null
var _map: Node = null
var _player: PartyData = null
var _town: SettlementData = null
var _village: SettlementData = null
var _tavern: TavernPanel = null
var _settlement_panel: PanelContainer = null
var _prisoner_ids: Array[String] = []


func _ready() -> void:
	await _run_async()
	_cleanup()
	if _failed:
		push_error("[tavern] 测试失败")
		get_tree().quit(1)
	else:
		print("[tavern] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	await _run_async()


func _run_async() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	_militia = load(MILITIA_PATH) as UnitConfig
	_check(_militia != null, "加载兵种配置")
	if _militia == null:
		return

	_test_price_config()
	_setup_world()
	if not _context.is_valid_world():
		return
	_test_trade_manager_atomicity()
	await _test_ui_entry_visibility()
	_test_tavern_menu_and_selling()
	print("[tavern] 完成")


func _test_price_config() -> void:
	var config := load(
		"res://Data/Settlements/prisoner_price_config.tres"
	) as PrisonerPriceConfig
	_check(config != null, "加载俘虏价格配置")
	if config == null:
		return
	_check(config.get_price_for_level(1) == 10, "1 级俘虏 10 金币")
	_check(config.get_price_for_level(2) == 20, "2 级俘虏 20 金币")
	_check(config.get_price_for_level(3) == 30, "3 级俘虏 30 金币")
	_check(config.get_price_for_level(9) == 30, "高等级取边界价格")
	_check(config.get_price_for_level(0) == 10, "非法等级回退到 1 级价格")


func _setup_world() -> void:
	_context = WorldContext.new()
	_context.name = "TavernTestContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return
	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id
	_player = _context.get_player_party()
	_town = _find_settlement(WorldInitializer.BURKNANIA_TOWN_NAME)
	_village = _find_settlement(WorldInitializer.BARI_VILLAGE_NAME)
	_check(_player != null and _town != null and _village != null, "找到玩家、城镇与村庄")
	if _player == null or _town == null or _village == null:
		return

	# 准备 3 名等级不同的玩家俘虏（独立 Unit，不属于成员列表）。
	for level: int in [1, 2, 3]:
		var unit := _context.unit_manager.create_unit(_militia, _player.faction_id)
		if unit == null:
			continue
		unit.level = level
		unit.display_name = "俘虏%d" % level
		_check(
			_context.party_manager.add_member(_player.party_id, unit.unit_id),
			"俘虏先加入部队"
		)
		_context.party_manager.remove_member(_player.party_id, unit.unit_id)
		unit.mark_wounded()
		if _context.party_manager.add_prisoner(_player.party_id, unit.unit_id):
			_prisoner_ids.append(unit.unit_id)
	_check(_prisoner_ids.size() == 3, "准备 3 名玩家俘虏")


func _test_trade_manager_atomicity() -> void:
	var manager := _context.prisoner_trade_manager
	_check(manager != null, "俘虏交易管理器存在")
	if manager == null:
		return
	var gold_before: int = _context.player_profile.gold
	_check(manager.get_price_for_level(1) == 10, "交易管理器读取统一价格")

	# 其他部队的俘虏：整体失败，不扣金币、不移除。
	var other_party := _context.party_manager.create_party(
		FactionManager.BANDIT_FACTION_ID, Vector2.ZERO, "其他部队"
	)
	var foreign := _context.unit_manager.create_unit(
		_militia, FactionManager.BANDIT_FACTION_ID
	)
	foreign.mark_wounded()
	_context.party_manager.add_prisoner(other_party.party_id, foreign.unit_id)
	var result: Dictionary = manager.sell_prisoners(
		_player.party_id, [_prisoner_ids[0], foreign.unit_id], _town.settlement_id
	)
	_check(not bool(result.get("success", false)), "包含其他部队俘虏时整笔交易失败")
	_check(_context.player_profile.gold == gold_before, "失败交易不改变金币")
	_check(
		_context.party_manager.get_prisoner_ids(_player.party_id).size() == 3,
		"失败交易不移除任何俘虏"
	)

	# 空选择与不存在单位同样失败。
	result = manager.sell_prisoners(_player.party_id, [], _town.settlement_id)
	_check(not bool(result.get("success", false)), "空选择不产生交易")
	result = manager.sell_prisoners(
		_player.party_id, ["missing_unit"], _town.settlement_id
	)
	_check(not bool(result.get("success", false)), "不存在单位导致失败")

	# 成功出售：重复 ID 去重，价格按等级累计。
	result = manager.sell_prisoners(
		_player.party_id,
		[_prisoner_ids[0], _prisoner_ids[0], _prisoner_ids[2]],
		_town.settlement_id
	)
	_check(bool(result.get("success", false)), "合法俘虏可出售")
	_check(int(result.get("gold", 0)) == 40, "1 级 + 3 级共 40 金币")
	_check(
		(result.get("sold_unit_ids", []) as Array).size() == 2,
		"重复 ID 只出售一次"
	)
	_check(
		_context.player_profile.gold == gold_before + 40,
		"出售成功后金币正确增加"
	)
	var sold_unit := _context.unit_manager.get_unit(_prisoner_ids[2])
	_check(sold_unit != null, "出售后 Unit 仍保留身份")
	_check(
		sold_unit.sold_to_settlement_id == _town.settlement_id,
		"出售后进入明确离开玩家控制状态"
	)
	_check(not sold_unit.is_prisoner(), "出售后不再是玩家俘虏")
	_check(
		_context.party_manager.get_prisoner_ids(_player.party_id) == [_prisoner_ids[1]],
		"未出售的俘虏保留在玩家列表"
	)
	# 同一批不能重复出售。
	result = manager.sell_prisoners(
		_player.party_id, [_prisoner_ids[2]], _town.settlement_id
	)
	_check(not bool(result.get("success", false)), "已售出俘虏不能再次出售")

	# 重置测试用的玩家俘虏，保留 2 名用于 UI 流程。
	var extra := _context.unit_manager.create_unit(_militia, _player.faction_id)
	extra.level = 1
	extra.mark_wounded()
	_context.party_manager.add_prisoner(_player.party_id, extra.unit_id)
	_prisoner_ids = _context.party_manager.get_prisoner_ids(_player.party_id)
	_check(_prisoner_ids.size() == 2, "UI 测试前有 2 名俘虏")


func _test_ui_entry_visibility() -> void:
	var packed := load("res://Scenes/WorldMap/world_map.tscn") as PackedScene
	_map = packed.instantiate()
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame
	_settlement_panel = _map.find_child("SettlementPanel", true, false) as PanelContainer
	_tavern = _map.find_child("TavernPanel", true, false) as TavernPanel
	var tavern_button := _map.find_child(
		"SettlementTavernButton", true, false
	) as Button
	_check(
		_settlement_panel != null and _tavern != null and tavern_button != null,
		"地点面板、酒馆面板与酒馆按钮存在"
	)
	if _settlement_panel == null or _tavern == null or tavern_button == null:
		return

	# 城镇显示酒馆入口。
	_map.call("_open_settlement", _town)
	_check(tavern_button.visible and not tavern_button.disabled, "城镇信息面板显示进入酒馆")
	# 村庄不显示酒馆。
	_map.call("_open_settlement", _village)
	_check(not tavern_button.visible, "村庄不显示酒馆入口")
	# 城堡不显示酒馆。
	var castle := _find_settlement(WorldInitializer.OLIN_CASTLE_NAME)
	if castle != null:
		_map.call("_open_settlement", castle)
		_check(not tavern_button.visible, "城堡不显示酒馆入口")


func _test_tavern_menu_and_selling() -> void:
	if _tavern == null:
		return
	_map.call("_open_settlement", _town)
	var tavern_button := _map.find_child(
		"SettlementTavernButton", true, false
	) as Button
	tavern_button.pressed.emit()
	_check(_tavern.visible, "点击进入酒馆后界面显示")
	# 酒馆内容嵌入原地点面板，窗口本身保持可见、位置与尺寸不变。
	_check(_settlement_panel.visible, "酒馆内容复用城镇信息面板，不打开第二个窗口")
	_check(_tavern.is_menu_visible(), "酒馆默认显示菜单")

	# 雇佣兵占位界面。
	var merc_button := _tavern.find_child(
		"TavernMercenariesButton", true, false
	) as Button
	_check(merc_button != null, "存在查看雇佣兵信息入口")
	merc_button.pressed.emit()
	var placeholder := _tavern.find_child(
		"TavernMercenaryPlaceholder", true, false
	) as Label
	_check(placeholder != null and placeholder.visible, "雇佣兵信息占位界面显示")
	(_tavern.find_child("TavernMercenaryBackButton", true, false) as Button).pressed.emit()

	# 进入出售界面。
	var sell_button := _tavern.find_child(
		"TavernSellPrisonersButton", true, false
	) as Button
	sell_button.pressed.emit()
	_check(_tavern.is_sell_view_visible(), "出售俘虏界面显示")
	var gold_before: int = _context.player_profile.gold
	var prisoner_before := _context.party_manager.get_prisoner_ids(_player.party_id)
	_check(prisoner_before.size() == 2, "右侧显示玩家当前俘虏")

	var first_id: String = prisoner_before[0]
	var row := _tavern.find_child(
		"TavernPlayer_%s" % first_id, true, false
	) as Button
	_check(row != null, "右侧每名俘虏有卖出按钮")
	row.pressed.emit()
	_check(
		_tavern.find_child("TavernBuyer_%s" % first_id, true, false) != null,
		"卖出后移动到城镇买方列表"
	)
	_check(_context.player_profile.gold == gold_before, "未确认前金币不变")
	_check(
		_context.party_manager.get_prisoner_ids(_player.party_id).size() == 2,
		"未确认前真实归属不变"
	)

	# 一键重置恢复初始状态。
	(_tavern.find_child("TavernSellResetButton", true, false) as Button).pressed.emit()
	_check(
		_tavern.find_child("TavernPlayer_%s" % first_id, true, false) != null,
		"重置后俘虏回到玩家列表"
	)

	# 确认出售。
	(_tavern.find_child("TavernPlayer_%s" % first_id, true, false) as Button).pressed.emit()
	(_tavern.find_child("TavernSellConfirmButton", true, false) as Button).pressed.emit()
	var sold_level: int = _context.unit_manager.get_unit(first_id).level
	var expected_gold: int = (
		_context.prisoner_trade_manager.get_price_for_level(sold_level)
	)
	_check(
		_context.player_profile.gold == gold_before + expected_gold,
		"确认后金币按等级增加"
	)
	_check(
		not _context.party_manager.get_prisoner_ids(_player.party_id).has(first_id),
		"确认后俘虏离开玩家列表"
	)
	var sold := _context.unit_manager.get_unit(first_id)
	_check(
		sold != null and sold.sold_to_settlement_id == _town.settlement_id,
		"确认后 Unit 进入出售状态"
	)
	_check(
		(_tavern.find_child("TavernPlayer_%s" % first_id, true, false)) == null,
		"确认后界面刷新移除已售俘虏"
	)

	# 离开酒馆恢复城镇信息面板。
	(_tavern.find_child("TavernSellBackButton", true, false) as Button).pressed.emit()
	(_tavern.find_child("TavernLeaveButton", true, false) as Button).pressed.emit()
	_check(not _tavern.visible, "离开酒馆后关闭界面")
	_check(_settlement_panel.visible, "离开酒馆后恢复城镇信息面板")


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------


func _find_settlement(display_name: String) -> SettlementData:
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement != null and settlement.display_name == display_name:
			return settlement
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[tavern] OK: %s" % message)
	else:
		_failed = true
		push_error("[tavern] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_map):
		_map.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
