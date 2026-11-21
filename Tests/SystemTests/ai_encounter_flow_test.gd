extends Node
## 阶段 4 遭遇流程集成测试：
## 1. 玩家接近离屏战斗后按阵营关系加入并进入 BattleScene；
## 2. AI 发起、玩家参与的屏幕战斗通过 battle_started 信号自动进入战斗场景。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/ai_encounter_flow_test.tscn

var _failed: bool = false


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
		_check(battle_scene.get_actor_count() == 17, "三方参战共生成 17 名士兵")

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
		_check(battle_scene.get_actor_count() == 12, "双方参战生成 12 名士兵")

	context.battle_manager.abort_battle(session.battle_id)
	GameManager.enter_main_menu()
	await get_tree().process_frame


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
