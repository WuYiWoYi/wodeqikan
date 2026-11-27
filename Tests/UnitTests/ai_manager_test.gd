extends Node
## AIManager 单元测试：路线 AI、强盗追击、治安队拦截、离屏战斗与中途加入。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/ai_manager_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"

var _failed: bool = false
var _militia: UnitConfig = null
var _ids: IdGenerator = null
var _units: UnitManager = null
var _parties: PartyManager = null
var _settlements: SettlementManager = null
var _factions: FactionManager = null
var _vision: VisionManager = null
var _map: WorldMapManager = null
var _battle: BattleManager = null
var _encounters: EncounterManager = null
var _ai: AIManager = null

var _oak: SettlementData = null
var _riverside: SettlementData = null
var _north: SettlementData = null
var _castle: SettlementData = null

var _player: PartyData = null
var _trade: PartyData = null
var _guard: PartyData = null
var _bandit: PartyData = null
var _none: PartyData = null
var _in_battle: PartyData = null
var _disabled: PartyData = null


func _ready() -> void:
	_run()
	if _failed:
		push_error("[ai] 测试失败")
		get_tree().quit(1)
	else:
		print("[ai] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	_militia = load(MILITIA_PATH) as UnitConfig
	_check(_militia != null, "加载民兵配置")
	_check(
		is_equal_approx(WorldInitializer.PLAYER_MOVE_SPEED, 450.0),
		"玩家原始速度为 450（等效 36）"
	)
	_check(
		is_equal_approx(WorldInitializer.MERCHANT_MOVE_SPEED, 80.0 * 2.5),
		"商队速度按基准 30 换算"
	)
	_check(
		is_equal_approx(WorldInitializer.GUARD_MOVE_SPEED, 120.0 * 2.5),
		"治安队速度按基准 30 换算"
	)
	_check(
		is_equal_approx(WorldInitializer.BANDIT_MOVE_SPEED, 100.0 * 2.5),
		"强盗速度按基准 30 换算"
	)
	if _militia == null:
		return

	_setup_fixture()
	_test_serialization_defaults()
	_test_initial_targets()
	_test_no_repeat_while_moving()
	_test_trade_route_cycle()
	_test_patrol_cycle()
	_test_skipped_parties()
	_test_bounds_and_serialization()
	_test_reload_continues_movement()
	_test_bandit_priority_and_chase()
	_test_bandit_targets_guard_and_player()
	_test_bandit_target_switch_margin()
	_test_ai_encounter_detection()
	_test_bandit_encounter_offscreen()
	_test_guard_priority()
	_test_guard_battle_join()
	_test_ai_responds_to_multiple_battles()
	_test_parallel_encounters_create_two_battles()
	_cleanup_battle()


func _setup_fixture() -> void:
	_ids = IdGenerator.new()
	_units = UnitManager.new()
	_units.setup(_ids)
	_parties = PartyManager.new()
	_parties.setup(_units, _ids)
	_settlements = SettlementManager.new()
	_settlements.setup(_ids)
	_factions = FactionManager.new()
	_factions.setup_defaults(_parties)
	_vision = VisionManager.new()
	_vision.setup(_parties, _factions, _units)
	_map = WorldMapManager.new()
	_map.setup(_parties, _vision)
	_map.world_bounds = Rect2(Vector2.ZERO, Vector2(3000.0, 2000.0))
	_battle = BattleManager.new()
	_battle.setup(_units, _parties, _ids, _factions)
	_encounters = EncounterManager.new()
	_encounters.setup(_parties, _factions, _battle, _map)
	_ai = AIManager.new()
	_ai.setup(_units, _parties, _map, _settlements, _factions, _vision, _battle)

	_oak = _settlements.create_settlement(
		"橡木村", SettlementData.SettlementType.VILLAGE, Vector2(500.0, 500.0)
	)
	_riverside = _settlements.create_settlement(
		"河畔村", SettlementData.SettlementType.VILLAGE, Vector2(1200.0, 900.0)
	)
	_north = _settlements.create_settlement(
		"北境村", SettlementData.SettlementType.VILLAGE, Vector2(2200.0, 500.0)
	)
	_castle = _settlements.create_settlement(
		"灰石城堡", SettlementData.SettlementType.CASTLE, Vector2(1800.0, 1300.0)
	)

	_player = _parties.create_party(
		FactionManager.PLAYER_FACTION_ID, Vector2(760.0, 620.0), "玩家"
	)
	_trade = _parties.create_party(
		FactionManager.MERCHANT_FACTION_ID, Vector2(900.0, 1500.0), "商队"
	)
	_guard = _parties.create_party(
		FactionManager.GUARD_FACTION_ID, Vector2(2350.0, 1100.0), "治安队"
	)
	_bandit = _parties.create_party(
		FactionManager.BANDIT_FACTION_ID, Vector2(1650.0, 900.0), "强盗"
	)
	_none = _parties.create_party(
		FactionManager.LOCAL_FACTION_ID, Vector2(1500.0, 1500.0), "无 AI"
	)
	_in_battle = _parties.create_party(
		FactionManager.LOCAL_FACTION_ID, Vector2(1800.0, 1600.0), "战斗中"
	)
	_disabled = _parties.create_party(
		FactionManager.LOCAL_FACTION_ID, Vector2(1900.0, 1600.0), "已失效"
	)

	_player.movement_speed = WorldInitializer.PLAYER_MOVE_SPEED
	_player.sight_range = WorldInitializer.PLAYER_SIGHT_RANGE
	_trade.movement_speed = WorldInitializer.MERCHANT_MOVE_SPEED
	_trade.sight_range = WorldInitializer.NPC_SIGHT_RANGE
	_guard.movement_speed = WorldInitializer.GUARD_MOVE_SPEED
	_guard.sight_range = WorldInitializer.GUARD_SIGHT_RANGE
	_bandit.movement_speed = WorldInitializer.BANDIT_MOVE_SPEED
	_bandit.sight_range = WorldInitializer.BANDIT_SIGHT_RANGE

	_trade.ai_type = PartyData.PartyAIType.TRADE_ROUTE
	_trade.ai_route_index = 0
	_trade.ai_route_settlement_ids.append(_oak.settlement_id)
	_trade.ai_route_settlement_ids.append(_riverside.settlement_id)

	_guard.ai_type = PartyData.PartyAIType.GUARD
	_guard.ai_route_index = 0

	# 默认关闭强盗 AI，避免路线测试被追击行为干扰；专项测试再打开。
	_bandit.ai_type = PartyData.PartyAIType.NONE
	_bandit.ai_route_index = 0
	_bandit.ai_route_settlement_ids.append(_castle.settlement_id)
	_bandit.ai_route_settlement_ids.append(_north.settlement_id)

	_in_battle.ai_type = PartyData.PartyAIType.PATROL
	_in_battle.battle_state = PartyData.BattleState.IN_BATTLE
	_disabled.ai_type = PartyData.PartyAIType.PATROL
	_disabled.battle_state = PartyData.BattleState.DISABLED

	# 玩家即使被误设 AI 类型，也必须由 player_party_id 排除。
	_player.ai_type = PartyData.PartyAIType.PATROL
	_player.ai_route_index = 0
	_ai.player_party_id = _player.party_id
	_battle.player_party_id = _player.party_id

	for party: PartyData in [
		_player, _trade, _guard, _bandit, _none, _in_battle, _disabled
	]:
		var unit := _units.create_unit(_militia, party.faction_id)
		_parties.add_member(party.party_id, unit.unit_id)


func _test_serialization_defaults() -> void:
	var old_party := PartyData.from_dict({"party_id": "PARTY_OLD", "movement_speed": 300.0})
	_check(old_party.ai_type == PartyData.PartyAIType.NONE, "旧存档 ai_type 默认为 NONE")
	_check(old_party.ai_route_index == 0, "旧存档 ai_route_index 默认为 0")
	_check(old_party.ai_route_settlement_ids.is_empty(), "旧存档路线 ID 默认为空")
	_check(is_equal_approx(old_party.movement_speed, 300.0), "旧存档保留原部队速度")

	var trade_copy := PartyData.from_dict(_trade.to_dict())
	_check(
		trade_copy.ai_type == PartyData.PartyAIType.TRADE_ROUTE,
		"商队 AI 类型可序列化"
	)
	_check(trade_copy.ai_route_index == 0, "商队路线索引可序列化")
	_check(
		trade_copy.ai_route_settlement_ids == _trade.ai_route_settlement_ids,
		"商队地点 ID 可序列化"
	)

	var bandit_copy := PartyData.from_dict({
		"party_id": "PARTY_BANDIT",
		"ai_type": PartyData.PartyAIType.BANDIT,
	})
	_check(bandit_copy.ai_type == PartyData.PartyAIType.BANDIT, "强盗 AI 类型可序列化")
	var guard_copy := PartyData.from_dict({
		"party_id": "PARTY_GUARD",
		"ai_type": PartyData.PartyAIType.GUARD,
	})
	_check(guard_copy.ai_type == PartyData.PartyAIType.GUARD, "治安队 AI 类型可序列化")


func _test_initial_targets() -> void:
	_ai.tick(1.0)
	_check(_trade.target_position == _oak.world_position, "商队初始目标为橡木村")
	_check(
		_trade.movement_state == PartyData.MovementState.MOVING,
		"商队开始移动"
	)
	_check(
		_guard.target_position == AIManager.PATROL_POINTS[0],
		"治安队初始目标为第 1 个巡逻点"
	)
	_check(
		_guard.movement_state == PartyData.MovementState.MOVING,
		"治安队开始巡逻"
	)
	_check(
		_bandit.target_position == _bandit.world_position
		and _bandit.movement_state == PartyData.MovementState.IDLE,
		"未启用 AI 的强盗保持原地"
	)
	_check(
		_none.target_position == _none.world_position
		and _none.movement_state == PartyData.MovementState.IDLE,
		"NONE 类型部队不自动移动"
	)
	_check(
		_player.target_position == _player.world_position
		and _player.movement_state == PartyData.MovementState.IDLE,
		"玩家部队不被 AI 控制"
	)
	_check(
		_in_battle.movement_state == PartyData.MovementState.IDLE,
		"战斗中的部队不执行 AI"
	)
	_check(
		_disabled.movement_state == PartyData.MovementState.IDLE,
		"失效部队不执行 AI"
	)


func _test_no_repeat_while_moving() -> void:
	var sentinel := Vector2(1234.0, 567.0)
	_trade.target_position = sentinel
	_ai.tick(1.0)
	_check(_trade.target_position == sentinel, "移动中不重复设置目标")
	_trade.target_position = _oak.world_position


func _test_trade_route_cycle() -> void:
	_move_all_to_targets()
	_check(_trade.world_position == _oak.world_position, "商队到达橡木村")
	_check(_trade.movement_state == PartyData.MovementState.IDLE, "商队到达后待命")

	_ai.tick(1.0)
	_check(_trade.ai_route_index == 1, "商队路线前进到河畔村")
	_check(_trade.target_position == _riverside.world_position, "商队目标切换为河畔村")

	_move_all_to_targets()
	_ai.tick(1.0)
	_check(_trade.ai_route_index == 0, "商队往返回到橡木村")
	_check(_trade.target_position == _oak.world_position, "商队目标切换回橡木村")

	_move_all_to_targets()
	_ai.tick(1.0)
	_check(_trade.ai_route_index == 1, "商队第二次往返到河畔村")
	_check(_trade.target_position == _riverside.world_position, "商队持续循环")


func _test_patrol_cycle() -> void:
	_guard.world_position = AIManager.PATROL_POINTS[0]
	_guard.target_position = _guard.world_position
	_guard.movement_state = PartyData.MovementState.IDLE
	_guard.ai_route_index = 0

	_ai.tick(1.0)
	_check(_guard.ai_route_index == 1, "治安队到达点 0 后前往点 1")
	_check(_guard.target_position == AIManager.PATROL_POINTS[1], "巡逻目标为点 1")

	_move_all_to_targets()
	_ai.tick(1.0)
	_check(_guard.ai_route_index == 2, "治安队前往点 2")
	_check(_guard.target_position == AIManager.PATROL_POINTS[2], "巡逻目标为点 2")

	_move_all_to_targets()
	_ai.tick(1.0)
	_check(_guard.ai_route_index == 3, "治安队前往点 3")
	_check(_guard.target_position == AIManager.PATROL_POINTS[3], "巡逻目标为点 3")

	_move_all_to_targets()
	_ai.tick(1.0)
	_check(_guard.ai_route_index == 0, "最后一个点之后回到点 0")
	_check(_guard.target_position == AIManager.PATROL_POINTS[0], "巡逻循环闭合")


func _test_skipped_parties() -> void:
	var player_position := _player.world_position
	var battle_position := _in_battle.world_position
	var disabled_position := _disabled.world_position
	var none_position := _none.world_position

	_ai.tick(1.0)
	_check(_player.world_position == player_position, "玩家位置不被 AI 修改")
	_check(_in_battle.world_position == battle_position, "战斗中部队位置不变")
	_check(_disabled.world_position == disabled_position, "失效部队位置不变")
	_check(_none.world_position == none_position, "NONE 部队位置不变")
	_check(
		_player.target_position == _player.world_position,
		"玩家目标不被 AI 改写"
	)

	_in_battle.battle_state = PartyData.BattleState.AVAILABLE
	_ai.tick(1.0)
	_check(
		_in_battle.movement_state == PartyData.MovementState.MOVING,
		"战斗结束后恢复 AI 巡逻"
	)
	_check(
		_in_battle.target_position
		== AIManager.PATROL_POINTS[_in_battle.ai_route_index],
		"恢复后沿用已有巡逻进度"
	)


func _test_bounds_and_serialization() -> void:
	var clamp_party := _parties.create_party(
		FactionManager.LOCAL_FACTION_ID, Vector2(2900.0, 1900.0), "边界"
	)
	_map.set_party_target(clamp_party.party_id, Vector2(9999.0, 9999.0))
	_check(
		clamp_party.target_position == Vector2(3000.0, 2000.0),
		"AI 目标经过地图边界限制"
	)

	_trade.movement_state = PartyData.MovementState.MOVING
	_trade.target_position = _riverside.world_position
	var moving_copy := PartyData.from_dict(_trade.to_dict())
	_check(
		moving_copy.movement_state == PartyData.MovementState.MOVING,
		"存档保留移动状态"
	)
	_check(
		moving_copy.target_position == _riverside.world_position,
		"存档保留移动目标"
	)
	_check(
		is_equal_approx(moving_copy.movement_speed, _trade.movement_speed),
		"存档保留部队速度"
	)

	_guard.ai_route_index = 2
	var patrol_copy := PartyData.from_dict(_guard.to_dict())
	_check(patrol_copy.ai_route_index == 2, "存档保留巡逻进度")


func _test_reload_continues_movement() -> void:
	_trade.world_position = Vector2(900.0, 900.0)
	_trade.target_position = _riverside.world_position
	_trade.movement_state = PartyData.MovementState.MOVING
	_trade.ai_route_index = 1
	_trade.movement_speed = WorldInitializer.MERCHANT_MOVE_SPEED

	var reloaded_parties := PartyManager.new()
	reloaded_parties.setup(_units, IdGenerator.new())
	reloaded_parties.load_from_dict(_parties.to_dict())
	var reloaded_trade := reloaded_parties.get_party(_trade.party_id)
	_check(reloaded_trade != null, "读档恢复商队部队")
	if reloaded_trade == null:
		return
	_check(
		reloaded_trade.movement_state == PartyData.MovementState.MOVING,
		"读档保留移动状态"
	)
	_check(
		reloaded_trade.target_position == _riverside.world_position,
		"读档保留移动目标"
	)
	_check(reloaded_trade.ai_route_index == 1, "读档保留路线进度")

	var reloaded_map := WorldMapManager.new()
	reloaded_map.setup(reloaded_parties)
	reloaded_map.world_bounds = Rect2(Vector2.ZERO, Vector2(3000.0, 2000.0))
	var before := reloaded_trade.world_position
	reloaded_map.update_party_movement(1.0)
	_check(reloaded_trade.world_position != before, "读档后 NPC 继续移动")


# ---------------------------------------------------------------------------
# 阶段 4：强盗与治安队 AI
# ---------------------------------------------------------------------------


func _test_bandit_priority_and_chase() -> void:
	_reset_main_parties()
	_bandit.ai_type = PartyData.PartyAIType.BANDIT
	_bandit.ai_route_index = 0
	_bandit.world_position = Vector2(1000.0, 1000.0)
	_bandit.target_position = _bandit.world_position
	_bandit.movement_state = PartyData.MovementState.IDLE
	_bandit.current_target_id = ""

	# 玩家更近，但商队优先级更高。
	_player.world_position = Vector2(1050.0, 1050.0)
	_trade.world_position = Vector2(1100.0, 1000.0)
	_trade.target_position = Vector2(1300.0, 1000.0)
	_trade.movement_state = PartyData.MovementState.MOVING
	_guard.world_position = Vector2(2200.0, 1600.0)

	_ai.tick(1.0)
	_check(_bandit.current_target_id == _trade.party_id, "强盗优先选择商队")
	_check(_bandit.attack_intent, "强盗追击时具有攻击意图")
	_check(
		_bandit.target_position == _trade.world_position,
		"强盗目标指向商队当前位置"
	)
	_check(
		_bandit.movement_state == PartyData.MovementState.MOVING,
		"强盗开始追击"
	)

	_trade.world_position = Vector2(1200.0, 1000.0)
	_ai.tick(1.0)
	_check(
		_bandit.target_position == _trade.world_position,
		"追击目标随商队位置更新"
	)

	# 商队与玩家都离开强盗视野：清除目标并恢复路线游荡。
	_trade.world_position = Vector2(1700.0, 1000.0)
	_player.world_position = Vector2(2600.0, 1800.0)
	_ai.tick(1.0)
	_check(_bandit.current_target_id.is_empty(), "目标离开视野后清除追击目标")
	_check(not _bandit.attack_intent, "失去目标后清除攻击意图")
	_check(
		_bandit.target_position == _castle.world_position,
		"失去目标后恢复强盗路线"
	)
	_bandit.ai_type = PartyData.PartyAIType.NONE


func _test_bandit_targets_guard_and_player() -> void:
	_reset_main_parties()
	_bandit.ai_type = PartyData.PartyAIType.BANDIT
	_bandit.world_position = Vector2(1000.0, 1000.0)
	_bandit.current_target_id = ""
	_trade.world_position = Vector2(2600.0, 1800.0)
	_player.world_position = Vector2(1100.0, 1000.0)
	_guard.world_position = Vector2(1100.0, 1000.0)

	_ai.tick(1.0)
	_check(
		_bandit.current_target_id == _guard.party_id,
		"无商队时强盗优先追击治安队"
	)

	_guard.world_position = Vector2(2600.0, 1800.0)
	_ai.tick(1.0)
	_check(
		_bandit.current_target_id == _player.party_id,
		"无商队与治安队时强盗追击玩家"
	)
	_check(
		_bandit.target_position == _player.world_position,
		"追击玩家时读取玩家最新位置"
	)

	_bandit.ai_type = PartyData.PartyAIType.NONE
	_reset_main_parties()


func _test_bandit_target_switch_margin() -> void:
	_reset_main_parties()
	_bandit.ai_type = PartyData.PartyAIType.BANDIT
	_bandit.world_position = Vector2(1000.0, 1000.0)
	_bandit.current_target_id = ""
	_bandit.attack_intent = false
	_trade.world_position = Vector2(2600.0, 1800.0)
	_guard.world_position = Vector2(2600.0, 1800.0)
	_player.world_position = Vector2(1100.0, 1000.0)

	_ai.tick(1.0)
	_check(_bandit.current_target_id == _player.party_id, "没有更优目标时追击玩家")

	_trade.world_position = Vector2(1200.0, 1000.0)
	_ai.tick(1.0)
	_check(
		_bandit.current_target_id == _trade.party_id,
		"追逐玩家时发现商队会重新评估并切换"
	)

	# 两个同类型目标评分接近时保留当前目标。
	_reset_main_parties()
	_bandit.ai_type = PartyData.PartyAIType.BANDIT
	_bandit.world_position = Vector2(1000.0, 1000.0)
	_bandit.current_target_id = _guard.party_id
	_bandit.attack_intent = true
	_player.world_position = Vector2(2600.0, 1800.0)
	_trade.world_position = Vector2(2600.0, 1800.0)
	_guard.world_position = Vector2(1200.0, 1000.0)
	_guard.current_target_id = ""
	var near_guard := _make_temp_party(
		FactionManager.GUARD_FACTION_ID, Vector2(1100.0, 1000.0), "近处治安队"
	)
	_ai.tick(1.0)
	_check(
		_bandit.current_target_id == _guard.party_id,
		"评分差距小于阈值时保留当前目标"
	)
	_destroy_party(near_guard)
	_bandit.ai_type = PartyData.PartyAIType.NONE
	_reset_main_parties()


func _test_ai_encounter_detection() -> void:
	_reset_main_parties()
	var merchant := _make_temp_party(
		FactionManager.MERCHANT_FACTION_ID, Vector2(2000.0, 1000.0), "遭遇商队"
	)
	var bandit := _make_temp_party(
		FactionManager.BANDIT_FACTION_ID, Vector2(2040.0, 1000.0), "遭遇强盗"
	)

	_encounters.update_encounters()
	_check(not _battle.has_any_active_battles(), "双方没有攻击意图时不触发遭遇")

	bandit.attack_intent = true
	bandit.current_target_id = merchant.party_id
	_encounters.update_encounters()
	var session := _battle.get_battle_for_party(bandit.party_id)
	_check(session != null, "单方具有攻击意图即可触发遭遇")
	if session != null:
		_check(session.offscreen, "NPC 遭遇使用离屏战斗")
		_check(
			bandit.battle_state == PartyData.BattleState.IN_BATTLE
			and merchant.battle_state == PartyData.BattleState.IN_BATTLE,
			"遭遇后双方被锁定"
		)
		var same_session := session
		_encounters.update_encounters()
		_check(
			_battle.get_battle_for_party(bandit.party_id) == same_session
			and _battle.get_active_battles().size() == 1,
			"不会重复创建同一场战斗"
		)
		_battle.abort_battle(session.battle_id)
	_destroy_party(merchant)
	_destroy_party(bandit)
	_reset_main_parties()

	# 双方互相具有攻击意图。
	merchant = _make_temp_party(
		FactionManager.MERCHANT_FACTION_ID, Vector2(2000.0, 1000.0), "互攻商队"
	)
	bandit = _make_temp_party(
		FactionManager.BANDIT_FACTION_ID, Vector2(2040.0, 1000.0), "互攻强盗"
	)
	merchant.attack_intent = true
	bandit.attack_intent = true
	merchant.current_target_id = bandit.party_id
	bandit.current_target_id = merchant.party_id
	_encounters.update_encounters()
	var mutual_session := _battle.get_battle_for_party(merchant.party_id)
	_check(mutual_session != null, "双方互相具有攻击意图时触发遭遇")
	if mutual_session != null:
		_battle.abort_battle(mutual_session.battle_id)
	_destroy_party(merchant)
	_destroy_party(bandit)
	_reset_main_parties()

	# 友方部队即使被误设攻击意图也不会遭遇。
	var merchant_one := _make_temp_party(
		FactionManager.MERCHANT_FACTION_ID, Vector2(2000.0, 1000.0), "商队一"
	)
	var merchant_two := _make_temp_party(
		FactionManager.MERCHANT_FACTION_ID, Vector2(2040.0, 1000.0), "商队二"
	)
	merchant_one.attack_intent = true
	merchant_two.attack_intent = true
	merchant_one.current_target_id = merchant_two.party_id
	merchant_two.current_target_id = merchant_one.party_id
	_encounters.update_encounters()
	_check(not _battle.has_any_active_battles(), "友方部队接近不会触发战斗")
	_destroy_party(merchant_one)
	_destroy_party(merchant_two)
	_reset_main_parties()


func _test_bandit_encounter_offscreen() -> void:
	_reset_main_parties()
	# 将主强盗移开，使用临时部队避免污染后续测试。
	_bandit.world_position = Vector2(2600.0, 1800.0)
	var temp_merchant := _make_temp_party(
		FactionManager.MERCHANT_FACTION_ID, Vector2(1020.0, 1000.0), "临时商队"
	)
	var temp_bandit := _make_temp_party(
		FactionManager.BANDIT_FACTION_ID, Vector2(1000.0, 1000.0), "临时强盗"
	)
	temp_bandit.ai_type = PartyData.PartyAIType.BANDIT
	temp_bandit.sight_range = 320.0

	_ai.tick(1.0)
	_encounters.update_encounters()
	var session := _battle.get_battle_for_party(temp_bandit.party_id)
	_check(session != null, "强盗追上目标后创建战斗")
	if session == null:
		_destroy_party(temp_merchant)
		_destroy_party(temp_bandit)
		return
	_check(session.offscreen, "NPC 对 NPC 使用离屏战斗")
	_check(not session.paused_world, "离屏战斗不暂停世界")
	_check(
		temp_bandit.battle_state == PartyData.BattleState.IN_BATTLE,
		"强盗进入战斗状态"
	)
	_check(
		temp_merchant.battle_state == PartyData.BattleState.IN_BATTLE,
		"商队被锁定进入战斗"
	)

	var bandit_position := temp_bandit.world_position
	var merchant_position := temp_merchant.world_position
	_ai.tick(1.0)
	_check(
		temp_bandit.world_position == bandit_position
		and temp_merchant.world_position == merchant_position,
		"战斗期间双方停止大地图移动"
	)
	_check(
		_battle.get_battle_for_party(temp_bandit.party_id) == session,
		"不会重复创建战斗"
	)

	_check(_battle.resolve_current_battle_now(), "离屏战斗按小时推进并结算")
	_check(_battle.get_battle(session.battle_id) == null, "离屏战斗结束后自动结算")
	_check(
		temp_bandit.battle_state != PartyData.BattleState.IN_BATTLE
		and temp_merchant.battle_state != PartyData.BattleState.IN_BATTLE,
		"结算后双方解除战斗状态"
	)
	_check(session.final_result != null and session.final_result.finalized,
		"离屏战斗生成 finalized 结果")

	_destroy_party(temp_merchant)
	_destroy_party(temp_bandit)
	_reset_main_parties()


func _test_guard_priority() -> void:
	_reset_main_parties()
	_bandit.ai_type = PartyData.PartyAIType.NONE
	_bandit.world_position = Vector2(2600.0, 1800.0)
	_guard.world_position = Vector2(1000.0, 1000.0)
	_guard.current_target_id = ""
	_trade.world_position = Vector2(1500.0, 1500.0)

	var threatening := _make_temp_party(
		FactionManager.BANDIT_FACTION_ID, Vector2(1150.0, 1000.0), "威胁商队的强盗"
	)
	threatening.current_target_id = _trade.party_id
	var idle_bandit := _make_temp_party(
		FactionManager.BANDIT_FACTION_ID, Vector2(1050.0, 1000.0), "附近强盗"
	)
	idle_bandit.current_target_id = ""

	_ai.tick(1.0)
	_check(
		_guard.current_target_id == threatening.party_id,
		"治安队优先拦截正在威胁商队的强盗"
	)
	_check(
		_guard.target_position == threatening.world_position,
		"治安队追击优先目标"
	)

	_destroy_party(threatening)
	_destroy_party(idle_bandit)
	_ai.tick(1.0)
	_check(
		_guard.current_target_id.is_empty(),
		"目标消失后治安队清除追击目标"
	)
	_check(
		_guard.target_position == AIManager.PATROL_POINTS[_guard.ai_route_index],
		"治安队无目标后恢复巡逻"
	)
	_reset_main_parties()


func _test_guard_battle_join() -> void:
	_reset_main_parties()
	_bandit.world_position = Vector2(2600.0, 1800.0)
	_guard.world_position = Vector2(2200.0, 1700.0)
	_trade.world_position = Vector2(900.0, 1500.0)

	var temp_merchant := _make_temp_party(
		FactionManager.MERCHANT_FACTION_ID, Vector2(1000.0, 1000.0), "交战商队"
	)
	var temp_bandit := _make_temp_party(
		FactionManager.BANDIT_FACTION_ID, Vector2(1020.0, 1000.0), "交战强盗"
	)
	var session := _battle.start_battle(
		[temp_bandit.party_id], [temp_merchant.party_id], Vector2(1010.0, 1000.0), true
	)
	_check(session != null, "创建商队-强盗离屏战斗")
	if session == null:
		_destroy_party(temp_merchant)
		_destroy_party(temp_bandit)
		return

	var temp_guard := _make_temp_party(
		FactionManager.GUARD_FACTION_ID, Vector2(1040.0, 1000.0), "响应治安队"
	)
	temp_guard.ai_type = PartyData.PartyAIType.GUARD
	temp_guard.sight_range = WorldInitializer.GUARD_SIGHT_RANGE

	_ai.tick(1.0)
	_encounters.update_encounters()
	_check(
		_battle.get_battle_for_party(temp_guard.party_id) == session,
		"治安队加入不会重复创建战斗"
	)
	_check(
		session.get_side_of_party(temp_guard.party_id)
		== session.get_side_of_party(temp_merchant.party_id),
		"治安队加入商队一方"
	)
	_check(
		session.get_side_of_party(temp_guard.party_id)
		!= session.get_side_of_party(temp_bandit.party_id),
		"治安队与强盗处于不同战斗侧"
	)
	_check(
		temp_guard.battle_state == PartyData.BattleState.IN_BATTLE,
		"加入后治安队进入战斗状态"
	)

	_battle.finish_battle(session.battle_id, BattleSession.BattleResult.ABORTED)
	_check(_battle.get_battle(session.battle_id) == null, "测试战斗已中止")
	_destroy_party(temp_guard)
	_destroy_party(temp_merchant)
	_destroy_party(temp_bandit)
	_reset_main_parties()


## 两场不同位置的离屏战斗：两名治安队分别响应各自距离最近的战场。
func _test_ai_responds_to_multiple_battles() -> void:
	_reset_main_parties()
	_guard.world_position = Vector2(100.0, 100.0)
	_bandit.world_position = Vector2(100.0, 300.0)
	var merchant_one := _make_temp_party(
		FactionManager.MERCHANT_FACTION_ID, Vector2(2000.0, 1000.0), "战场一商队"
	)
	var bandit_one := _make_temp_party(
		FactionManager.BANDIT_FACTION_ID, Vector2(2030.0, 1000.0), "战场一强盗"
	)
	var merchant_two := _make_temp_party(
		FactionManager.MERCHANT_FACTION_ID, Vector2(2600.0, 1000.0), "战场二商队"
	)
	var bandit_two := _make_temp_party(
		FactionManager.BANDIT_FACTION_ID, Vector2(2630.0, 1000.0), "战场二强盗"
	)
	var first := _battle.start_battle(
		[merchant_one.party_id], [bandit_one.party_id], Vector2(2015.0, 1000.0), true
	)
	var second := _battle.start_battle(
		[merchant_two.party_id], [bandit_two.party_id], Vector2(2615.0, 1000.0), true
	)
	_check(first != null and second != null, "创建两处独立战场")
	if first == null or second == null:
		_destroy_party(merchant_one)
		_destroy_party(bandit_one)
		_destroy_party(merchant_two)
		_destroy_party(bandit_two)
		return

	var guard_one := _make_temp_party(
		FactionManager.GUARD_FACTION_ID, Vector2(1980.0, 1000.0), "响应治安队一"
	)
	var guard_two := _make_temp_party(
		FactionManager.GUARD_FACTION_ID, Vector2(2580.0, 1000.0), "响应治安队二"
	)
	guard_one.ai_type = PartyData.PartyAIType.GUARD
	guard_two.ai_type = PartyData.PartyAIType.GUARD
	guard_one.sight_range = 800.0
	guard_two.sight_range = 800.0

	_ai.tick(1.0)
	_check(
		guard_one.target_position.distance_to(first.world_position) < 0.5,
		"第一名治安队前往较近的第一处战场"
	)
	_check(
		guard_two.target_position.distance_to(second.world_position) < 0.5,
		"第二名治安队前往较近的第二处战场"
	)
	_check(
		_battle.get_active_battles().size() == 2,
		"AI 响应不会合并两场战斗"
	)

	_battle.finish_battle(first.battle_id, BattleSession.BattleResult.ABORTED)
	_check(
		_battle.get_battle(second.battle_id) == second,
		"结束第一处战场不影响第二处"
	)
	_battle.finish_battle(second.battle_id, BattleSession.BattleResult.ABORTED)
	_destroy_party(guard_one)
	_destroy_party(guard_two)
	_destroy_party(merchant_one)
	_destroy_party(bandit_one)
	_destroy_party(merchant_two)
	_destroy_party(bandit_two)
	_reset_main_parties()


## 两组互不相关的敌对部队可以各自触发一场离屏战斗。
func _test_parallel_encounters_create_two_battles() -> void:
	_reset_main_parties()
	_guard.world_position = Vector2(100.0, 100.0)
	_bandit.world_position = Vector2(120.0, 100.0)
	var merchant_one := _make_temp_party(
		FactionManager.MERCHANT_FACTION_ID, Vector2(2000.0, 1000.0), "遭遇商队一"
	)
	var bandit_one := _make_temp_party(
		FactionManager.BANDIT_FACTION_ID, Vector2(2040.0, 1000.0), "遭遇强盗一"
	)
	var merchant_two := _make_temp_party(
		FactionManager.MERCHANT_FACTION_ID, Vector2(2200.0, 1200.0), "遭遇商队二"
	)
	var bandit_two := _make_temp_party(
		FactionManager.BANDIT_FACTION_ID, Vector2(2240.0, 1200.0), "遭遇强盗二"
	)
	for pair: Array in [[bandit_one, merchant_one], [bandit_two, merchant_two]]:
		var attacker := pair[0] as PartyData
		var target := pair[1] as PartyData
		attacker.attack_intent = true
		attacker.current_target_id = target.party_id

	_encounters.update_encounters()
	_encounters.update_encounters()
	var first := _battle.get_battle_for_party(bandit_one.party_id)
	var second := _battle.get_battle_for_party(bandit_two.party_id)
	_check(
		first != null and second != null and first != second,
		"两组部队各自创建独立战斗"
	)
	_check(
		_battle.get_active_battles().size() == 2,
		"世界同时存在两场遭遇战斗"
	)
	if first == null or second == null:
		_destroy_party(merchant_one)
		_destroy_party(bandit_one)
		_destroy_party(merchant_two)
		_destroy_party(bandit_two)
		return
	_check(
		merchant_one.battle_state == PartyData.BattleState.IN_BATTLE
		and bandit_two.battle_state == PartyData.BattleState.IN_BATTLE,
		"各战斗只锁定自己的参战部队"
	)
	_check(
		_battle.get_battle_for_party(merchant_one.party_id) == first
		and _battle.get_battle_for_party(merchant_two.party_id) == second,
		"没有部队被错误分配到另一场战斗"
	)

	_battle.tick(6.0)
	_check(
		first.offscreen_settlements_done >= 1
		and second.offscreen_settlements_done >= 1,
		"两场遭遇战斗分别推进小时结算"
	)
	var second_states := _snapshot_session_states(second)
	_battle.finish_battle(first.battle_id, BattleSession.BattleResult.ABORTED)
	_check(
		_battle.get_battle(second.battle_id) == second
		and _session_states_equal(second, second_states),
		"结束一场遭遇战斗不影响另一场"
	)
	_check(
		merchant_two.battle_state == PartyData.BattleState.IN_BATTLE,
		"另一场战斗部队保持锁定"
	)
	_battle.finish_battle(second.battle_id, BattleSession.BattleResult.ABORTED)
	_destroy_party(merchant_one)
	_destroy_party(bandit_one)
	_destroy_party(merchant_two)
	_destroy_party(bandit_two)
	_reset_main_parties()


func _snapshot_session_states(session: BattleSession) -> Dictionary:
	var result: Dictionary = {}
	for unit_id: String in session.get_all_unit_ids():
		var state := session.get_unit_state(unit_id)
		if state != null:
			result[unit_id] = [state.alive, state.battle_hp]
	return result


func _session_states_equal(session: BattleSession, snapshot: Dictionary) -> bool:
	for unit_id_value: Variant in snapshot.keys():
		var unit_id: String = str(unit_id_value)
		var state := session.get_unit_state(unit_id)
		var before: Array = snapshot[unit_id_value]
		if state == null or state.alive != bool(before[0]) \
				or state.battle_hp != int(before[1]):
			return false
	return true


func _reset_main_parties() -> void:
	_cleanup_battle()
	for party: PartyData in [
		_player, _trade, _guard, _bandit, _none, _in_battle, _disabled
	]:
		party.battle_state = PartyData.BattleState.AVAILABLE
		party.current_order = PartyData.OrderType.NONE
		party.current_target_id = ""
		party.attack_intent = false
		party.target_position = party.world_position
		party.movement_state = PartyData.MovementState.IDLE
	_bandit.ai_type = PartyData.PartyAIType.NONE
	_bandit.ai_route_index = 0
	_player.world_position = Vector2(760.0, 620.0)
	_trade.world_position = Vector2(900.0, 1500.0)
	_guard.world_position = Vector2(2350.0, 1100.0)
	_bandit.world_position = Vector2(1650.0, 900.0)
	_trade.ai_route_index = 0
	_guard.ai_route_index = 0


func _cleanup_battle() -> void:
	if _battle != null:
		for session: BattleSession in _battle.get_active_battles():
			_battle.finish_battle(
				session.battle_id, BattleSession.BattleResult.ABORTED
			)


func _make_temp_party(faction_id: String, position: Vector2, party_name: String) -> PartyData:
	var party := _parties.create_party(faction_id, position, party_name)
	party.target_position = position
	party.movement_state = PartyData.MovementState.IDLE
	party.sight_range = 250.0
	party.movement_speed = 110.0
	var unit := _units.create_unit(_militia, faction_id)
	_parties.add_member(party.party_id, unit.unit_id)
	return party


func _destroy_party(party: PartyData) -> void:
	if party == null:
		return
	for unit_id: String in party.member_unit_ids.duplicate():
		_parties.remove_member(party.party_id, unit_id)
		_units.remove_unit(unit_id)
	_parties.remove_party(party.party_id)


func _move_all_to_targets() -> void:
	# 大地图移动系数为 0.08，单次 10 秒推进不足以跨越大距离；
	# 循环推进直到所有部队待命，保留精确到达语义。
	for i: int in range(600):
		_map.update_party_movement(10.0)
		var all_idle: bool = true
		for party: PartyData in _parties.get_all_parties():
			if party.movement_state == PartyData.MovementState.MOVING:
				all_idle = false
				break
		if all_idle:
			return


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[ai] OK: %s" % message)
	else:
		_failed = true
		push_error("[ai] FAIL: %s" % message)
