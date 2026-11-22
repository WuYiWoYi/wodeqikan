extends Node
## 阶段 4 遭遇流程集成测试：
## 1. 玩家接近离屏战斗后按阵营关系加入并进入 BattleScene；
## 2. AI 发起、玩家参与的屏幕战斗通过 battle_started 信号自动进入战斗场景。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/ai_encounter_flow_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"
const RAIDER_FACTION_ID: String = "FACTION_RAIDER"

var _failed: bool = false

# 独立 AI 场景使用的受控管理器（不依赖完整世界，避免无关 AI 干扰）。
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


func _ready() -> void:
	get_tree().current_scene = null
	await get_tree().process_frame
	await _run()
	_cleanup()
	if _failed:
		push_error("[aiflow] 测试失败")
		get_tree().quit(1)
	else:
		print("[aiflow] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	await _test_player_joins_offscreen_battle()
	await _test_battle_started_signal_enters_scene()
	_test_ai_assistance_scenarios()


func _test_player_joins_offscreen_battle() -> void:
	TimeManager.clear_pauses()
	TimeManager.stop_session()
	_check(GameManager.start_new_game(), "新游戏启动：玩家加入离屏战斗")
	await get_tree().process_frame
	await get_tree().process_frame

	var context := GameManager.world_context
	_check(context != null and context.is_valid_world(), "WorldContext 有效")
	if context == null:
		return
	var player := context.get_player_party()
	var merchant := _find_party_by_name(context, WorldInitializer.TEST_ENEMY_PARTY_NAME)
	var bandit := _find_party_by_name(context, WorldInitializer.BANDIT_PARTY_NAME)
	_check(player != null and merchant != null and bandit != null, "玩家、商队、强盗均存在")
	if player == null or merchant == null or bandit == null:
		return

	var battle_position := Vector2(900.0, 1200.0)
	player.world_position = battle_position + Vector2(20.0, 0.0)
	player.target_position = player.world_position
	player.movement_state = PartyData.MovementState.IDLE
	player.current_order = PartyData.OrderType.NONE
	merchant.world_position = battle_position
	merchant.target_position = merchant.world_position
	merchant.movement_state = PartyData.MovementState.IDLE
	bandit.world_position = battle_position
	bandit.target_position = bandit.world_position
	bandit.movement_state = PartyData.MovementState.IDLE

	var session := context.battle_manager.start_battle(
		[bandit.party_id], [merchant.party_id], battle_position, true
	)
	_check(session != null, "创建商队-强盗离屏战斗")
	if session == null:
		return
	_check(session.offscreen and not session.player_involved, "初始为离屏非玩家战斗")

	_check(
		context.encounter_manager.update_player_battle_interaction(),
		"玩家接近离屏战斗触发交互请求"
	)
	await get_tree().process_frame
	await get_tree().process_frame

	var world_map := get_tree().current_scene
	var interaction_panel := world_map.find_child(
		"BattleInteractionPanel", true, false
	) as PanelContainer
	_check(
		interaction_panel != null and interaction_panel.visible,
		"显示加入/离开交互面板"
	)
	_check(not session.player_involved, "选择前不会自动加入")
	_check(session.offscreen, "选择前战斗仍为离屏状态")
	if interaction_panel == null or not interaction_panel.visible:
		return

	var join_button := interaction_panel.find_child(
		"BattleJoinButton", true, false
	) as Button
	_check(join_button != null, "交互面板包含加入战斗按钮")
	if join_button == null:
		return
	join_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	_check(
		get_tree().current_scene != null and get_tree().current_scene.name == "Battle",
		"选择加入后进入战斗场景"
	)
	_check(session.player_involved, "战斗标记为玩家参与")
	_check(
		context.battle_manager.current_battle == session,
		"加入已有战斗而非创建新战斗"
	)
	_check(
		session.get_side_of_party(player.party_id)
		== session.get_side_of_party(merchant.party_id),
		"玩家加入商队一方"
	)
	_check(
		session.get_side_of_party(player.party_id)
		!= session.get_side_of_party(bandit.party_id),
		"玩家与强盗不同战斗侧"
	)
	var battle_scene := get_tree().current_scene as BattleScene
	_check(battle_scene != null, "当前场景为 BattleScene")
	if battle_scene != null:
		_check(
			battle_scene.get_player_side() == session.get_side_of_party(player.party_id),
			"战斗场景使用玩家的实际战斗侧"
		)
		_check(
			battle_scene.get_actor_count()
				== player.member_unit_ids.size() + merchant.member_unit_ids.size()
					+ bandit.member_unit_ids.size(),
			"三方参战生成全部士兵"
		)

	context.battle_manager.abort_battle(session.battle_id)
	GameManager.enter_main_menu()
	await get_tree().process_frame
	await get_tree().process_frame


func _test_battle_started_signal_enters_scene() -> void:
	TimeManager.clear_pauses()
	TimeManager.stop_session()
	_check(GameManager.start_new_game(), "新游戏启动：信号进入战斗")
	await get_tree().process_frame
	await get_tree().process_frame

	var context := GameManager.world_context
	var player := context.get_player_party() if context != null else null
	var bandit := _find_party_by_name(
		context, WorldInitializer.BANDIT_PARTY_NAME
	) if context != null else null
	_check(player != null and bandit != null, "玩家与强盗存在")
	if player == null or bandit == null:
		return

	# 模拟 AI 追上玩家后请求创建战斗；场景切换由 WorldMap 监听 battle_started 完成。
	var session := context.battle_manager.start_battle(
		[player.party_id], [bandit.party_id], player.world_position, false
	)
	_check(session != null, "创建玩家屏幕战斗")
	if session == null:
		return

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	_check(
		get_tree().current_scene != null and get_tree().current_scene.name == "Battle",
		"battle_started 信号自动进入战斗场景"
	)
	var battle_scene := get_tree().current_scene as BattleScene
	_check(battle_scene != null, "信号路径生成 BattleScene")
	if battle_scene != null:
		_check(
			battle_scene.get_actor_count()
				== player.member_unit_ids.size() + bandit.member_unit_ids.size(),
			"双方参战生成全部士兵"
		)

	context.battle_manager.abort_battle(session.battle_id)
	GameManager.enter_main_menu()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# 阶段 10：AI 助攻、视野门槛、关系分支与战后冷却
# ---------------------------------------------------------------------------


func _test_ai_assistance_scenarios() -> void:
	_militia = load(MILITIA_PATH) as UnitConfig
	_check(_militia != null, "加载民兵配置")
	if _militia == null:
		return
	_setup_ai_fixture()
	_test_vision_gated_assistance()
	_test_relation_cases_for_assistance()
	_test_multi_side_assistance_checks_all_sides()
	_test_post_battle_cooldown_and_recovery()
	_test_multiple_battle_survivors_move()
	_cleanup_ai_fixture()


func _setup_ai_fixture() -> void:
	TimeManager.world_elapsed_seconds = 0.0
	_ids = IdGenerator.new()
	_units = UnitManager.new()
	_units.setup(_ids)
	_parties = PartyManager.new()
	_parties.setup(_units, _ids)
	_settlements = SettlementManager.new()
	_settlements.setup(_ids)
	_factions = FactionManager.new()
	_factions.setup_defaults(_parties)
	_factions.register_faction(RAIDER_FACTION_ID, "劫掠者")
	_factions.set_relation(
		RAIDER_FACTION_ID, FactionManager.MERCHANT_FACTION_ID,
		FactionManager.Relation.HOSTILE
	)
	_factions.set_relation(
		RAIDER_FACTION_ID, FactionManager.BANDIT_FACTION_ID,
		FactionManager.Relation.HOSTILE
	)
	_vision = VisionManager.new()
	_vision.setup(_parties, _factions, _units)
	_map = WorldMapManager.new()
	_map.setup(_parties, _vision)
	_map.world_bounds = Rect2(Vector2.ZERO, Vector2(5000.0, 3000.0))
	_battle = BattleManager.new()
	_battle.setup(_units, _parties, _ids, _factions)
	_battle.offscreen_config.base_hourly_casualty_fraction = 0.0
	_battle.offscreen_config.casualty_variance = 0.0
	_encounters = EncounterManager.new()
	_encounters.setup(_parties, _factions, _battle, _map)
	_ai = AIManager.new()
	_ai.setup(_units, _parties, _map, _settlements, _factions, _vision, _battle)


## 战场中心在推进范围内也不够，必须真的看见参战方；
## 提高视野后才响应，且加入的是既有战斗。
func _test_vision_gated_assistance() -> void:
	var center := Vector2(2000.0, 1000.0)
	var merchant := _make_ai_party(
		FactionManager.MERCHANT_FACTION_ID, center, "被袭商队"
	)
	var bandit := _make_ai_party(FactionManager.BANDIT_FACTION_ID, center, "袭击强盗")
	var guard := _make_ai_party(
		FactionManager.GUARD_FACTION_ID, Vector2(2000.0, 1600.0), "响应治安队"
	)
	guard.ai_type = PartyData.PartyAIType.GUARD
	var session := _battle.start_battle(
		[bandit.party_id], [merchant.party_id], center, true
	)
	_check(session != null, "创建视野门槛测试战斗")
	if session == null:
		_destroy_ai_party(merchant)
		_destroy_ai_party(bandit)
		_destroy_ai_party(guard)
		return
	_check(
		guard.world_position.distance_to(center) <= AIManager.BATTLE_APPROACH_RADIUS,
		"治安队在战场接近范围内"
	)

	# 视野 250 < 与参战方距离 600：不能凭空得知战斗。
	guard.sight_range = 250.0
	_ai.tick(1.0)
	_check(
		guard.battle_response_id.is_empty(),
		"看不见参战方时不响应战场"
	)
	_check(
		guard.target_position != center,
		"看不见参战方时移动目标不是战场中心"
	)

	# 提高视野后能看见商队，开始接近。
	guard.sight_range = 650.0
	_ai.tick(1.0)
	_check(
		guard.battle_response_id == session.battle_id,
		"看见参战方后记录要响应的战斗"
	)
	_check(
		guard.target_position.distance_to(center) < 0.5,
		"看见后把接近目标设为该战场"
	)

	# 到达加入半径后由 EncounterManager 加入既有战斗。
	guard.world_position = center + Vector2(0.0, 30.0)
	_encounters.update_encounters()
	_check(
		_battle.get_battle_for_party(guard.party_id) == session,
		"治安队通过既有战斗加入而非新建战斗"
	)
	_check(_battle.get_active_battles().size() == 1, "AI 协助不会产生第二场战斗")
	_check(
		session.get_side_count() == 2,
		"协助方加入既有战斗侧，不创建第三侧"
	)
	_check(
		session.get_side_of_party(guard.party_id)
			== session.get_side_of_party(merchant.party_id),
		"治安队加入商队一方"
	)

	_battle.finish_battle(session.battle_id, BattleSession.BattleResult.ABORTED)
	_destroy_ai_party(merchant)
	_destroy_ai_party(bandit)
	_destroy_ai_party(guard)


## 关系分支：只有“恰好一侧敌对、另有一侧友方/中立”才可协助；
## 双方都敌对或都不敌对时不得自动参战。
func _test_relation_cases_for_assistance() -> void:
	var center := Vector2(2000.0, 1000.0)
	var merchant := _make_ai_party(
		FactionManager.MERCHANT_FACTION_ID, center, "关系商队"
	)
	var bandit := _make_ai_party(
		FactionManager.BANDIT_FACTION_ID, center, "关系强盗"
	)
	var guard := _make_ai_party(
		FactionManager.GUARD_FACTION_ID, Vector2(2020.0, 1000.0), "关系治安队"
	)
	var raider := _make_ai_party(
		RAIDER_FACTION_ID, Vector2(2020.0, 1040.0), "关系劫掠者"
	)
	var neutral := _make_ai_party(
		FactionManager.LOCAL_FACTION_ID, Vector2(2020.0, 960.0), "中立部队"
	)
	var session := _battle.start_battle(
		[bandit.party_id], [merchant.party_id], center, true
	)
	_check(session != null, "创建关系分支测试战斗")
	if session == null:
		for party: PartyData in [merchant, bandit, guard, raider, neutral]:
			_destroy_ai_party(party)
		return

	# A：对一侧友好、另一侧敌对。
	_check(
		_battle.get_join_side(guard.party_id, session.battle_id)
			== session.get_side_of_party(merchant.party_id),
		"A 一侧敌对另一侧友好：加入友好方"
	)
	# B：双方都敌对，不得以协助名义加入或新建第三侧。
	_check(
		_battle.get_join_side(raider.party_id, session.battle_id) < 0,
		"B 双方都敌对：没有可加入侧"
	)
	_check(
		not _battle.try_join_battle(raider.party_id, session.battle_id)
			and session.get_side_count() == 2,
		"B 双方都敌对：不创建第三战斗侧"
	)
	# C：双方都不敌对（全中立）。
	_check(
		_battle.get_join_side(neutral.party_id, session.battle_id) < 0,
		"C 对所有侧中立：不自动参战"
	)
	# D：已在其他战斗中的部队不能同时加入。
	var second_session := _battle.start_battle(
		[raider.party_id], [neutral.party_id], Vector2(4000.0, 500.0), true
	)
	_check(second_session != null, "创建第二场战斗锁定关系部队")
	if second_session != null:
		_check(
			_battle.get_join_side(raider.party_id, session.battle_id) < 0,
			"D 已在其他战斗中：不能加入本场战斗"
		)
		_battle.finish_battle(
			second_session.battle_id, BattleSession.BattleResult.ABORTED
		)

	_battle.finish_battle(session.battle_id, BattleSession.BattleResult.ABORTED)
	for party: PartyData in [merchant, bandit, guard, raider, neutral]:
		_destroy_ai_party(party)


## 多方战斗必须检查全部战斗侧，而不是只看前两侧。
func _test_multi_side_assistance_checks_all_sides() -> void:
	var center := Vector2(2500.0, 1200.0)
	var merchant := _make_ai_party(
		FactionManager.MERCHANT_FACTION_ID, center, "多方商队"
	)
	var neutral := _make_ai_party(
		FactionManager.LOCAL_FACTION_ID, center, "多方中立"
	)
	var bandit := _make_ai_party(
		FactionManager.BANDIT_FACTION_ID, center, "多方强盗"
	)
	var guard := _make_ai_party(
		FactionManager.GUARD_FACTION_ID, Vector2(2530.0, 1200.0), "多方治安队"
	)
	var session := _battle.start_battle_by_sides(
		[[merchant.party_id], [neutral.party_id], [bandit.party_id]],
		center,
		true
	)
	_check(session != null, "创建三侧战斗")
	if session == null:
		for party: PartyData in [merchant, neutral, bandit, guard]:
			_destroy_ai_party(party)
		return
	# 若只比较前两侧，会认为“没有敌对侧”而拒绝；正确实现必须看到第 3 侧强盗。
	_check(
		_battle.get_join_side(guard.party_id, session.battle_id)
			== session.get_side_of_party(merchant.party_id),
		"检查全部战斗侧后加入唯一敌对侧之外的友方"
	)
	var raider := _make_ai_party(
		RAIDER_FACTION_ID, Vector2(2530.0, 1240.0), "多方劫掠者"
	)
	_check(
		_battle.get_join_side(raider.party_id, session.battle_id)
			== session.get_side_of_party(neutral.party_id),
		"与两侧敌对时加入唯一无敌对关系的一侧"
	)
	_battle.finish_battle(session.battle_id, BattleSession.BattleResult.ABORTED)
	for party: PartyData in [merchant, neutral, bandit, guard, raider]:
		_destroy_ai_party(party)


## 战后先脱离接触、恢复路线；冷却结束后可以重新追击并触发新战斗。
func _test_post_battle_cooldown_and_recovery() -> void:
	var route_a := _settlements.create_settlement(
		"战后路线甲", SettlementData.SettlementType.VILLAGE, Vector2(3000.0, 500.0)
	)
	var route_b := _settlements.create_settlement(
		"战后路线乙", SettlementData.SettlementType.VILLAGE, Vector2(3500.0, 700.0)
	)
	var bandit := _make_ai_party(
		FactionManager.BANDIT_FACTION_ID, Vector2(2500.0, 1200.0), "战后强盗"
	)
	bandit.ai_type = PartyData.PartyAIType.BANDIT
	bandit.ai_route_index = 0
	bandit.ai_route_settlement_ids.append(route_a.settlement_id)
	bandit.ai_route_settlement_ids.append(route_b.settlement_id)
	var merchant := _make_ai_party(
		FactionManager.MERCHANT_FACTION_ID, Vector2(2600.0, 1200.0), "战后商队"
	)
	var session := _battle.start_battle(
		[bandit.party_id], [merchant.party_id], Vector2(2550.0, 1200.0), true
	)
	_check(session != null, "创建战后冷却测试战斗")
	if session == null:
		_destroy_ai_party(bandit)
		_destroy_ai_party(merchant)
		return
	_check(_battle.resolve_current_battle_now(), "离屏战斗结算完成")
	_check(
		bandit.battle_state == PartyData.BattleState.AVAILABLE
			and merchant.battle_state == PartyData.BattleState.AVAILABLE,
		"战斗结束后双方恢复可用"
	)
	_check(
		bandit.engagement_cooldown_until > TimeManager.world_elapsed_seconds,
		"战斗结束后进入遭遇冷却"
	)

	# 冷却中：不追回原目标，恢复路线游荡。
	bandit.world_position = Vector2(2500.0, 1200.0)
	merchant.world_position = Vector2(2600.0, 1200.0)
	_ai.tick(1.0)
	_check(
		bandit.current_target_id.is_empty() and not bandit.attack_intent,
		"冷却中不重新追击刚交战的商队"
	)
	_check(
		bandit.target_position == route_a.world_position,
		"冷却中恢复强盗路线目标"
	)
	_check(
		bandit.movement_state == PartyData.MovementState.MOVING,
		"冷却中继续正常大地图移动"
	)
	# 即使双方被强制设置攻击意图，冷却也不允许立即再战。
	bandit.attack_intent = true
	bandit.current_target_id = merchant.party_id
	merchant.attack_intent = true
	merchant.current_target_id = bandit.party_id
	_encounters.update_encounters()
	_check(
		_battle.get_battle_for_party(bandit.party_id) == null,
		"冷却期间不会立即创建新战斗"
	)
	bandit.attack_intent = false
	bandit.current_target_id = ""
	merchant.attack_intent = false
	merchant.current_target_id = ""

	# 冷却结束后重新评估目标并追击。
	TimeManager.world_elapsed_seconds = bandit.engagement_cooldown_until + 0.5
	bandit.sight_range = 400.0
	_ai.tick(1.0)
	_check(
		bandit.current_target_id == merchant.party_id and bandit.attack_intent,
		"冷却结束后重新追击视野内敌对目标"
	)
	_check(
		bandit.target_position == merchant.world_position,
		"冷却结束后追击目标跟随商队位置"
	)
	bandit.world_position = Vector2(2620.0, 1200.0)
	_encounters.update_encounters()
	var renewed := _battle.get_battle_for_party(bandit.party_id)
	_check(renewed != null, "冷却结束后可再次触发遭遇")
	_check(
		renewed != null and _battle.get_active_battles().size() == 1,
		"恢复后的追击只创建一场战斗"
	)
	if renewed != null:
		_battle.finish_battle(renewed.battle_id, BattleSession.BattleResult.ABORTED)
	_destroy_ai_party(bandit)
	_destroy_ai_party(merchant)


## 两场离屏战斗同时结算后，全部幸存部队都必须恢复大地图移动，
## 不能因为另一场战斗结束或冷却而卡在 IDLE。
func _test_multiple_battle_survivors_move() -> void:
	var route_a := _settlements.create_settlement(
		"多战路线甲", SettlementData.SettlementType.VILLAGE, Vector2(3000.0, 800.0)
	)
	var route_b := _settlements.create_settlement(
		"多战路线乙", SettlementData.SettlementType.VILLAGE, Vector2(3400.0, 1000.0)
	)
	var pairs: Array = []
	for i: int in range(2):
		var bandit := _make_ai_party(
			FactionManager.BANDIT_FACTION_ID,
			Vector2(2000.0 + i * 300.0, 1200.0),
			"多战强盗%d" % i
		)
		bandit.ai_type = PartyData.PartyAIType.BANDIT
		bandit.ai_route_index = 0
		bandit.ai_route_settlement_ids.append(route_a.settlement_id)
		bandit.ai_route_settlement_ids.append(route_b.settlement_id)
		var merchant := _make_ai_party(
			FactionManager.MERCHANT_FACTION_ID,
			Vector2(2000.0 + i * 300.0, 1200.0),
			"多战商队%d" % i
		)
		pairs.append([bandit, merchant])

	var sessions: Array[BattleSession] = []
	for i: int in range(2):
		var bandit: PartyData = pairs[i][0]
		var merchant: PartyData = pairs[i][1]
		var session := _battle.start_battle(
			[bandit.party_id], [merchant.party_id], bandit.world_position, true
		)
		if session != null:
			sessions.append(session)
	_check(sessions.size() == 2, "创建两场独立离屏战斗")
	if sessions.size() != 2:
		for pair: Array in pairs:
			_destroy_ai_party(pair[0])
			_destroy_ai_party(pair[1])
		return

	_check(_battle.resolve_current_battle_now(), "两场离屏战斗同时结算")
	_check(_battle.get_active_battles().is_empty(), "结算后没有残留战斗")
	for pair: Array in pairs:
		for party: PartyData in pair:
			_check(
				party.battle_state == PartyData.BattleState.AVAILABLE,
				"幸存部队恢复可用：%s" % party.party_name
			)

	_ai.tick(1.0)
	for pair: Array in pairs:
		var bandit: PartyData = pair[0]
		_check(
			bandit.movement_state == PartyData.MovementState.MOVING
				and not bandit.target_position.is_equal_approx(bandit.world_position),
			"战后强盗恢复大地图移动：%s" % bandit.party_name
		)
	for pair: Array in pairs:
		_destroy_ai_party(pair[0])
		_destroy_ai_party(pair[1])


func _make_ai_party(
	faction_id: String, position: Vector2, party_name: String, unit_count: int = 3
) -> PartyData:
	var party := _parties.create_party(faction_id, position, party_name)
	party.target_position = position
	party.movement_state = PartyData.MovementState.IDLE
	party.sight_range = 250.0
	party.movement_speed = 110.0
	for i: int in range(unit_count):
		var unit := _units.create_unit(_militia, faction_id)
		_parties.add_member(party.party_id, unit.unit_id)
	return party


func _destroy_ai_party(party: PartyData) -> void:
	if party == null:
		return
	for unit_id: String in party.member_unit_ids.duplicate():
		_parties.remove_member(party.party_id, unit_id)
		_units.remove_unit(unit_id)
	_parties.remove_party(party.party_id)


func _cleanup_ai_fixture() -> void:
	if _battle != null:
		for session: BattleSession in _battle.get_active_battles():
			_battle.finish_battle(session.battle_id, BattleSession.BattleResult.ABORTED)
	TimeManager.world_elapsed_seconds = 0.0


func _find_party_by_name(context: WorldContext, party_name: String) -> PartyData:
	if context == null:
		return null
	for party: PartyData in context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[aiflow] OK: %s" % message)
	else:
		_failed = true
		push_error("[aiflow] FAIL: %s" % message)


func _cleanup() -> void:
	GameManager.enter_main_menu()
	TimeManager.stop_session()
	TimeManager.clear_pauses()
