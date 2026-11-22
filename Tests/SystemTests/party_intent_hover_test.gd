extends Node
## 阶段 10 系统测试：部队悬浮面板的行动意图。
## 覆盖追击、跟随、巡逻、前往地点、响应战场、征召、保持前进、待命，
## 意图变化后的自动刷新，以及 Alt 详细构成不被破坏。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . \
##     res://Tests/SystemTests/party_intent_hover_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"

var _failed: bool = false
var _context: WorldContext = null
var _map: Node = null
var _probe: PartyData = null
var _player: PartyData = null
var _bandit: PartyData = null
var _militia: UnitConfig = null


func _ready() -> void:
	get_tree().current_scene = null
	await get_tree().process_frame
	await _run()
	_cleanup()
	if _failed:
		push_error("[intenthover] 测试失败")
		get_tree().quit(1)
	else:
		print("[intenthover] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	_militia = load(MILITIA_PATH) as UnitConfig
	_check(_militia != null, "加载民兵配置")
	if _militia == null:
		return

	_context = WorldContext.new()
	_context.name = "IntentHoverTestContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return
	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id
	# 让悬浮测试部队与强盗敌对，覆盖“跟随敌对目标按追击显示”分支。
	_context.faction_manager.set_relation(
		FactionManager.LOCAL_FACTION_ID,
		FactionManager.BANDIT_FACTION_ID,
		FactionManager.Relation.HOSTILE
	)
	_player = _context.get_player_party()
	_bandit = _find_party(WorldInitializer.BANDIT_PARTY_NAME)
	_check(_player != null and _bandit != null, "找到玩家与强盗")
	if _player == null or _bandit == null:
		return

	var packed := load("res://Scenes/WorldMap/world_map.tscn") as PackedScene
	_map = packed.instantiate()
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame

	_probe = _make_probe_party()
	_check(_probe != null, "创建悬浮测试部队")
	if _probe == null:
		return
	_test_idle_and_patrol()
	_test_travel_and_pursuit()
	_test_follow_and_battle_response()
	_test_recruiting_intent()
	_test_intent_auto_refresh()
	_test_alt_details_and_no_mutation()


func _test_idle_and_patrol() -> void:
	_reset_probe()
	_check_activity("行动：暂无行动", "待命部队显示暂无行动")

	_probe.ai_type = PartyData.PartyAIType.PATROL
	_check_activity("行动：正在附近巡逻", "静止巡逻部队显示附近巡逻")

	_probe.target_position = _probe.world_position + Vector2(200.0, 0.0)
	_probe.movement_state = PartyData.MovementState.MOVING
	_check_activity("行动：正在前往巡逻区域", "巡逻移动显示前往巡逻区域")


func _test_travel_and_pursuit() -> void:
	_reset_probe()
	var settlement := _context.settlement_manager.get_all_settlements()[0]
	_probe.ai_type = PartyData.PartyAIType.TRADE_ROUTE
	_probe.target_position = settlement.world_position
	_probe.movement_state = PartyData.MovementState.MOVING
	_check_activity(
		"行动：正在前往：%s" % settlement.display_name,
		"前往地点时显示具体地名"
	)

	_reset_probe()
	_probe.attack_intent = true
	_probe.current_target_id = _bandit.party_id
	_probe.target_position = _bandit.world_position
	_probe.movement_state = PartyData.MovementState.MOVING
	var probe_before := _party_snapshot(_probe)
	var bandit_before := _party_snapshot(_bandit)
	_check_activity(
		"行动：正在追击：%s" % _bandit.party_name, "追击时显示目标部队名"
	)
	_check(
		_party_snapshot(_probe) == probe_before
			and _party_snapshot(_bandit) == bandit_before,
		"悬浮显示不修改 AI 或部队状态"
	)


func _test_follow_and_battle_response() -> void:
	_reset_probe()
	_probe.current_order = PartyData.OrderType.FOLLOW_PARTY
	_probe.current_target_id = _player.party_id
	_probe.movement_state = PartyData.MovementState.MOVING
	_check_activity(
		"行动：正在跟随：%s" % _player.party_name, "跟随友军显示正在跟随"
	)

	_probe.current_target_id = _bandit.party_id
	_check_activity(
		"行动：正在追击：%s" % _bandit.party_name, "跟随敌对目标按追击显示"
	)

	_reset_probe()
	var merchant := _find_party(WorldInitializer.TEST_ENEMY_PARTY_NAME)
	var other_bandit := _find_party(WorldInitializer.EAST_BANDIT_PARTY_NAME)
	_check(merchant != null and other_bandit != null, "找到响应战场测试部队")
	if merchant == null or other_bandit == null:
		return
	var session := _context.battle_manager.start_battle(
		[other_bandit.party_id], [merchant.party_id], Vector2(500.0, 500.0), true
	)
	_check(session != null, "创建离屏战斗")
	if session != null:
		_probe.battle_response_id = session.battle_id
		_check_activity("行动：正在前往战场", "响应战场时显示正在前往战场")
		_probe.battle_response_id = ""
		_context.battle_manager.finish_battle(
			session.battle_id, BattleSession.BattleResult.ABORTED
		)


func _test_recruiting_intent() -> void:
	_reset_probe()
	var knight := _find_party(WorldInitializer.BURKNANIA_KNIGHT_PARTY_NAME)
	_check(knight != null, "找到拥有领主的骑士部队")
	if knight == null:
		return
	var lord: LordData = _context.lord_manager.get_lord_by_party_id(
		knight.party_id
	)
	_check(lord != null, "骑士部队存在领主数据")
	if lord == null:
		return
	var old_state := lord.current_state
	var old_target := lord.current_target_settlement_id
	var old_position := knight.world_position
	knight.world_position = Vector2(4200.0, 2400.0)
	var settlement := _context.settlement_manager.get_all_settlements()[0]
	lord.current_state = "RECRUITING"
	lord.current_target_settlement_id = settlement.settlement_id
	_check_activity_at(
		knight,
		"行动：正在前往征召：%s" % settlement.display_name,
		"征召状态优先显示目标地点"
	)
	lord.current_state = old_state
	lord.current_target_settlement_id = old_target
	knight.world_position = old_position


func _test_intent_auto_refresh() -> void:
	_reset_probe()
	_probe.attack_intent = true
	_probe.current_target_id = _bandit.party_id
	_probe.movement_state = PartyData.MovementState.MOVING
	_check_activity(
		"行动：正在追击：%s" % _bandit.party_name, "初始追击意图显示正确"
	)
	# 意图在悬浮期间改变：同一部队再次悬浮必须刷新文本。
	_probe.attack_intent = false
	_probe.current_target_id = ""
	_probe.movement_state = PartyData.MovementState.IDLE
	_check_activity("行动：暂无行动", "意图改变后悬浮文本自动刷新")


func _test_alt_details_and_no_mutation() -> void:
	_reset_probe()
	_map.call("_apply_party_hover", _probe.world_position)
	_check(_detail_labels().is_empty(), "默认悬浮不显示兵种构成")
	var before := _party_snapshot(_probe)
	_map.call("set_alt_detail_active", true)
	var details := _detail_labels()
	_check(not details.is_empty(), "按住 Alt 时展开兵种构成")
	var joined := " ".join(details)
	_check(joined.contains("总人数：1"), "Alt 详情显示总人数")
	_check(
		joined.contains("民兵"),
		"Alt 详情显示真实兵种（实际：%s）" % joined
	)
	_map.call("set_alt_detail_active", false)
	_check(_detail_labels().is_empty(), "松开 Alt 后恢复简洁悬浮")
	_check(_party_snapshot(_probe) == before, "展开详情不修改部队运行时状态")


func _check_activity(expected: String, message: String) -> void:
	_check_activity_at(_probe, expected, message)


func _check_activity_at(
	party: PartyData, expected: String, message: String
) -> void:
	_map.call("_apply_party_hover", party.world_position)
	var panel := _map.find_child("PartyHoverPanel", true, false) as PanelContainer
	var label := _map.find_child("PartyHoverActivity", true, false) as Label
	_check(panel != null and panel.visible, "%s（面板可见）" % message)
	_check(
		label != null and label.text == expected,
		"%s（实际：%s）" % [message, label.text if label != null else "<无>"]
	)


func _detail_labels() -> Array[String]:
	var result: Array[String] = []
	var content := _map.find_child("PartyHoverContent", true, false)
	if content == null:
		return result
	# 同名 Label 会被 Godot 自动改名，因此按“非标题/行动行”收集详情行。
	for child: Node in content.get_children():
		if not child is Label:
			continue
		var label := child as Label
		if label.name == "PartyHoverName" or label.name == "PartyHoverActivity" \
				or label.name == "PartyHoverPolitics":
			continue
		result.append(label.text)
	return result


func _make_probe_party() -> PartyData:
	var party := _context.party_manager.create_party(
		FactionManager.LOCAL_FACTION_ID, Vector2(4000.0, 2500.0), "悬浮测试部队"
	)
	party.target_position = party.world_position
	party.movement_state = PartyData.MovementState.IDLE
	var unit := _context.unit_manager.create_unit(
		_militia, FactionManager.LOCAL_FACTION_ID
	)
	_context.party_manager.add_member(party.party_id, unit.unit_id)
	return party


func _reset_probe() -> void:
	if _probe == null:
		return
	_probe.world_position = Vector2(4000.0, 2500.0)
	_probe.target_position = _probe.world_position
	_probe.movement_state = PartyData.MovementState.IDLE
	_probe.ai_type = PartyData.PartyAIType.NONE
	_probe.current_order = PartyData.OrderType.NONE
	_probe.current_target_id = ""
	_probe.attack_intent = false
	_probe.battle_response_id = ""
	_probe.battle_response_until = 0.0
	_probe.focus_party_id = ""


func _party_snapshot(party: PartyData) -> Dictionary:
	if party == null:
		return {}
	return {
		"battle_state": int(party.battle_state),
		"order": int(party.current_order),
		"movement": int(party.movement_state),
		"target_id": party.current_target_id,
		"attack_intent": party.attack_intent,
		"target_position": party.target_position,
		"world_position": party.world_position,
		"units": party.member_unit_ids.size(),
	}


func _find_party(party_name: String) -> PartyData:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[intenthover] OK: %s" % message)
	else:
		_failed = true
		push_error("[intenthover] FAIL: %s" % message)


func _cleanup() -> void:
	if _context != null:
		for session: BattleSession in _context.battle_manager.get_active_battles():
			_context.battle_manager.finish_battle(
				session.battle_id, BattleSession.BattleResult.ABORTED
			)
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_map):
		_map.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
