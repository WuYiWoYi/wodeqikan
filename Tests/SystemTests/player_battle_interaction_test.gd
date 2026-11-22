extends Node
## 玩家接近进行中的离屏战斗时的“加入/离开”交互测试。
## 覆盖：暂停与面板、加入已有战斗、离开后不重复、离开范围后可重触发、
## 战斗结束/异常关闭清理、基础倍率与其他暂停原因保护。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/player_battle_interaction_test.tscn

const OTHER_PAUSE: StringName = &"player_battle_interaction_test_hold"

var _failed: bool = false


func _ready() -> void:
	get_tree().current_scene = null
	await get_tree().process_frame
	await _run()
	_cleanup()
	if _failed:
		push_error("[battleinteraction] 测试失败")
		get_tree().quit(1)
	else:
		print("[battleinteraction] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.clear_pauses()
	TimeManager.stop_session()
	_check(GameManager.start_new_game(), "新游戏启动")
	await get_tree().process_frame
	await get_tree().process_frame

	var context := GameManager.world_context
	var player := context.get_player_party() if context != null else null
	var merchant := _find_party_by_name(context, WorldInitializer.TEST_ENEMY_PARTY_NAME)
	var bandit := _find_party_by_name(context, WorldInitializer.BANDIT_PARTY_NAME)
	var guard := _find_party_by_name(context, WorldInitializer.GUARD_PARTY_NAME)
	_check(
		player != null and merchant != null and bandit != null and guard != null,
		"玩家与 NPC 部队存在"
	)
	if player == null or merchant == null or bandit == null or guard == null:
		return

	# 固定测试场景，避免其他 AI 干扰。
	var battle_position := Vector2(900.0, 1200.0)
	# 55 在交互/加入范围内，但在普通部队对话的 40 像素范围之外。
	_place_party(player, battle_position + Vector2(55.0, 0.0))
	_place_party(merchant, battle_position)
	_place_party(bandit, battle_position)
	_place_party(guard, Vector2(2600.0, 1800.0))
	guard.ai_type = PartyData.PartyAIType.NONE
	merchant.ai_type = PartyData.PartyAIType.NONE
	bandit.ai_type = PartyData.PartyAIType.NONE

	var session := context.battle_manager.start_battle(
		[bandit.party_id], [merchant.party_id], battle_position, true
	)
	_check(session != null, "创建商队-强盗离屏战斗")
	if session == null:
		return
	_check(session.offscreen and not session.player_involved, "初始为离屏非玩家战斗")

	# 保持 2x 基础倍率，验证交互面板不会修改它。
	TimeManager.set_base_world_speed(TimeManager.SPEED_DOUBLE)
	TimeManager.push_pause(OTHER_PAUSE)
	_check(
		context.encounter_manager.update_player_battle_interaction(),
		"玩家接近离屏战斗触发交互"
	)
	await get_tree().process_frame

	var panel := _find_panel()
	_check(panel != null and panel.visible, "显示加入/离开面板")
	if panel == null or not panel.visible:
		return
	_check(
		is_zero_approx(TimeManager.get_effective_world_scale()),
		"交互面板打开后世界暂停"
	)
	_check(
		is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_DOUBLE),
		"交互面板不改变基础倍率"
	)
	_check(not session.player_involved, "选择前不会自动加入")
	_check(session.offscreen, "选择前战斗仍为离屏状态")
	_check(
		context.battle_manager.get_battle(session.battle_id) == session
		and context.battle_manager.get_active_battles().size() == 1,
		"交互不创建新战斗"
	)

	var summary := panel.find_child(
		"BattleInteractionSummaryLabel", true, false
	) as Label
	var join_button := panel.find_child("BattleJoinButton", true, false) as Button
	var leave_button := panel.find_child("BattleLeaveButton", true, false) as Button
	_check(summary != null and summary.text.contains(merchant.party_name), "面板显示交战方")
	_check(summary != null and summary.text.contains(bandit.party_name), "面板显示双方名称")
	_check(join_button != null, "存在加入战斗按钮")
	_check(leave_button != null, "存在离开按钮")
	_check(
		player.movement_state == PartyData.MovementState.IDLE
		and player.target_position == player.world_position,
		"交互期间玩家停止移动"
	)
	_check(
		not context.encounter_manager.update_player_battle_interaction(),
		"同一遭遇不会重复生成交互"
	)
	_check(_count_panels() == 1, "不会重复弹出面板")

	if leave_button == null:
		return
	leave_button.pressed.emit()
	_check(not panel.visible, "选择离开后关闭面板")
	_check(
		is_zero_approx(TimeManager.get_effective_world_scale()),
		"离开后仍保留其他暂停原因"
	)
	_check(
		context.encounter_manager.get_pending_battle_interaction().is_empty(),
		"离开后清理交互请求"
	)
	_check(
		context.battle_manager.get_battle(session.battle_id) == session
		and session.offscreen,
		"离开后 NPC 战斗继续"
	)
	_check(not session.player_involved, "离开后玩家未参战")

	# 仍处于交互范围：不重复弹出。
	_check(
		not context.encounter_manager.update_player_battle_interaction(),
		"离开后原地不会重复弹出"
	)
	# 离开交互范围后再次接近可以重新触发。
	_place_party(player, battle_position + Vector2(120.0, 0.0))
	_check(
		not context.encounter_manager.update_player_battle_interaction(),
		"离开交互范围后清除拒绝记录"
	)
	_place_party(player, battle_position + Vector2(55.0, 0.0))
	_check(
		context.encounter_manager.update_player_battle_interaction(),
		"再次接近可以重新弹出"
	)
	await get_tree().process_frame
	panel = _find_panel()
	_check(panel != null and panel.visible, "重新显示交互面板")
	if panel == null or not panel.visible:
		return

	# 异常关闭：清理本次暂停，不清除其他暂停原因。
	var world_map: Node = get_tree().current_scene
	world_map.call("cancel_battle_interaction")
	_check(not panel.visible, "异常关闭后隐藏面板")
	_check(
		is_zero_approx(TimeManager.get_effective_world_scale()),
		"异常关闭不清除其他暂停原因"
	)
	_check(
		context.encounter_manager.get_pending_battle_interaction().is_empty(),
		"异常关闭清理交互请求"
	)
	_check(
		context.battle_manager.get_battle(session.battle_id) == session
		and session.offscreen,
		"异常关闭不影响 NPC 战斗"
	)

	# 重新打开并让战斗在面板打开期间结束。
	_check(
		context.encounter_manager.update_player_battle_interaction(),
		"异常关闭后可以重新触发"
	)
	await get_tree().process_frame
	panel = _find_panel()
	_check(panel != null and panel.visible, "战斗结束测试面板已打开")
	if panel == null or not panel.visible:
		return
	context.battle_manager.finish_battle(
		session.battle_id, BattleSession.BattleResult.ABORTED
	)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not panel.visible, "战斗结束后自动关闭面板")
	_check(
		context.encounter_manager.get_pending_battle_interaction().is_empty(),
		"战斗结束后清理交互请求"
	)
	_check(
		is_zero_approx(TimeManager.get_effective_world_scale()),
		"战斗结束清理后只保留其他暂停"
	)

	TimeManager.pop_pause(OTHER_PAUSE)
	_check(
		is_equal_approx(TimeManager.get_effective_world_scale(), TimeManager.SPEED_DOUBLE),
		"移除其他暂停后恢复 2x"
	)

	# 新建一场离屏战斗，验证加入已有战斗而非创建新战斗。
	var session_two := context.battle_manager.start_battle(
		[bandit.party_id], [merchant.party_id], battle_position, true
	)
	_check(session_two != null, "创建第二场离屏战斗")
	if session_two == null:
		return
	_check(
		context.encounter_manager.update_player_battle_interaction(),
		"再次触发中加入交互"
	)
	await get_tree().process_frame
	panel = _find_panel()
	_check(panel != null and panel.visible, "加入交互面板已打开")
	if panel == null or not panel.visible:
		return
	join_button = panel.find_child("BattleJoinButton", true, false) as Button
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
	_check(
		context.battle_manager.current_battle == session_two,
		"玩家加入已有战斗而非创建新战斗"
	)
	_check(session_two.player_involved, "战斗标记为玩家参与")
	_check(
		session_two.get_side_of_party(player.party_id)
		== session_two.get_side_of_party(merchant.party_id),
		"玩家加入商队一方"
	)
	_check(
		session_two.get_side_of_party(player.party_id)
		!= session_two.get_side_of_party(bandit.party_id),
		"玩家与强盗不同战斗侧"
	)
	_check(
		is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_DOUBLE),
		"加入战斗后基础倍率保持"
	)
	context.battle_manager.abort_battle(session_two.battle_id)


func _place_party(party: PartyData, position: Vector2) -> void:
	party.world_position = position
	party.target_position = position
	party.movement_state = PartyData.MovementState.IDLE
	party.current_order = PartyData.OrderType.NONE
	party.current_target_id = ""
	party.attack_intent = false


func _find_party_by_name(context: WorldContext, party_name: String) -> PartyData:
	if context == null:
		return null
	for party: PartyData in context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _find_panel() -> PanelContainer:
	if get_tree().current_scene == null:
		return null
	return get_tree().current_scene.find_child(
		"BattleInteractionPanel", true, false
	) as PanelContainer


func _count_panels() -> int:
	if get_tree().current_scene == null:
		return 0
	return get_tree().current_scene.find_children(
		"BattleInteractionPanel", "PanelContainer", true, false
	).size()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[battleinteraction] OK: %s" % message)
	else:
		_failed = true
		push_error("[battleinteraction] FAIL: %s" % message)


func _cleanup() -> void:
	GameManager.enter_main_menu()
	TimeManager.stop_session()
	TimeManager.clear_pauses()
