extends Node
## 玩家被敌对 AI 主动拦截时的遭遇对话测试。
## 覆盖：无意图不触发、暂停原因栈、对话内容、防重复、取消清理、战斗选项进入战斗场景。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/player_encounter_test.tscn

const OTHER_PAUSE: StringName = &"player_encounter_test_hold"

var _failed: bool = false


func _ready() -> void:
	get_tree().current_scene = null
	await get_tree().process_frame
	await _run()
	_cleanup()
	if _failed:
		push_error("[encounter] 测试失败")
		get_tree().quit(1)
	else:
		print("[encounter] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.clear_pauses()
	TimeManager.stop_session()
	_check(GameManager.start_new_game(), "新游戏启动")
	await get_tree().process_frame
	await get_tree().process_frame

	var context := GameManager.world_context
	var player := context.get_player_party() if context != null else null
	var bandit := _find_party_by_name(context, WorldInitializer.BANDIT_PARTY_NAME)
	var merchant := _find_party_by_name(context, WorldInitializer.TEST_ENEMY_PARTY_NAME)
	var guard := _find_party_by_name(context, WorldInitializer.GUARD_PARTY_NAME)
	_check(
		player != null and bandit != null and merchant != null and guard != null,
		"玩家与三方 NPC 部队存在"
	)
	if player == null or bandit == null or merchant == null or guard == null:
		return

	# 固定测试场景，避免其他 AI 干扰。
	player.world_position = Vector2(900.0, 1200.0)
	player.target_position = player.world_position
	player.movement_state = PartyData.MovementState.IDLE
	player.current_order = PartyData.OrderType.NONE
	player.current_target_id = ""
	bandit.world_position = Vector2(940.0, 1200.0)
	bandit.target_position = bandit.world_position
	bandit.movement_state = PartyData.MovementState.IDLE
	bandit.current_order = PartyData.OrderType.NONE
	bandit.current_target_id = ""
	bandit.attack_intent = false
	bandit.ai_type = PartyData.PartyAIType.NONE
	merchant.world_position = Vector2(2600.0, 1800.0)
	merchant.target_position = merchant.world_position
	merchant.movement_state = PartyData.MovementState.IDLE
	merchant.ai_type = PartyData.PartyAIType.NONE
	guard.world_position = Vector2(2500.0, 1700.0)
	guard.target_position = guard.world_position
	guard.movement_state = PartyData.MovementState.IDLE
	guard.ai_type = PartyData.PartyAIType.NONE

	TimeManager.set_base_world_speed(TimeManager.SPEED_DOUBLE)
	TimeManager.push_pause(OTHER_PAUSE)

	# 玩家主动接近敌对 AI，但 AI 没有攻击意图：不弹出遭遇。
	_check(
		not context.encounter_manager.update_encounters(),
		"无敌对 AI 攻击意图时不触发遭遇"
	)
	await get_tree().process_frame
	var panel := _find_encounter_panel()
	_check(panel != null and not panel.visible, "无攻击意图不弹出遭遇对话")

	# 敌对 AI 主动追击玩家：触发遭遇对话。
	bandit.attack_intent = true
	bandit.current_target_id = player.party_id
	_check(
		context.encounter_manager.update_encounters(),
		"敌对 AI 主动拦截玩家时触发遭遇"
	)
	await get_tree().process_frame

	panel = _find_encounter_panel()
	_check(panel != null and panel.visible, "遭遇对话正常显示")
	if panel == null or not panel.visible:
		return
	_check(
		is_zero_approx(TimeManager.get_effective_world_scale()),
		"遭遇对话打开后世界暂停"
	)
	_check(
		is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_DOUBLE),
		"遭遇对话不改变基础世界倍率"
	)

	var name_label := panel.find_child("EncounterPartyNameLabel", true, false) as Label
	var faction_label := panel.find_child("EncounterFactionLabel", true, false) as Label
	var troop_label := panel.find_child("EncounterTroopLabel", true, false) as Label
	var description := panel.find_child("EncounterDescriptionLabel", true, false) as Label
	_check(name_label != null and name_label.text == bandit.party_name, "显示敌对部队名称")
	_check(faction_label != null and faction_label.text.contains("强盗"), "显示敌对阵营")
	_check(
		troop_label != null and troop_label.text.contains(str(bandit.member_unit_ids.size())),
		"显示敌对部队人数"
	)
	_check(description != null and description.text.contains("财物"), "显示强盗遭遇描述")

	var fight_button := panel.find_child("EncounterFightButton", true, false) as Button
	var retreat_button := panel.find_child("EncounterLeaveButton", true, false) as Button
	_check(fight_button != null and fight_button.visible, "遭遇对话提供战斗选项")
	_check(
		context.encounter_manager.get_pending_encounter_reason()
		== EncounterManager.EncounterReason.ENEMY_PURSUIT,
		"记录敌对追击拦截的遭遇原因"
	)
	_check(
		retreat_button != null and not retreat_button.visible
		and retreat_button.disabled,
		"敌对追击成功后不显示离开选项且按钮不可用"
	)
	_check(
		panel.anchor_top >= 0.99 and panel.anchor_bottom >= 0.99,
		"遭遇对话位于屏幕下方"
	)
	var portrait := panel.find_child("EncounterPortrait", true, false) as EncounterPortrait
	_check(
		portrait != null and portrait.has_leader_visual(),
		"遭遇对话显示对方领袖头像/剪影"
	)

	# 对话期间双方停止移动。
	_check(
		player.movement_state == PartyData.MovementState.IDLE
		and bandit.movement_state == PartyData.MovementState.IDLE,
		"遭遇对话期间双方停止移动"
	)
	_check(
		player.target_position == player.world_position
		and bandit.target_position == bandit.world_position,
		"遭遇对话期间双方目标被清除"
	)
	_check(
		player.current_target_id.is_empty() and bandit.current_target_id.is_empty(),
		"遭遇对话期间清除追逐目标"
	)
	_check(not bandit.attack_intent, "触发遭遇后清除攻击意图")

	# 防重复。
	var pending: Dictionary = context.encounter_manager.get_pending_player_encounter()
	_check(not pending.is_empty(), "记录待处理遭遇")
	_check(
		not context.encounter_manager.update_encounters(),
		"待处理遭遇期间不会再次触发"
	)
	await get_tree().process_frame
	_check(
		_count_encounter_panels() == 1,
		"遭遇对话不会重复弹出"
	)

	# 异常关闭：只移除本次遭遇暂停，不影响其他暂停原因与基础倍率。
	var world_map: Node = get_tree().current_scene
	world_map.call("cancel_player_encounter")
	await get_tree().process_frame
	_check(not panel.visible, "取消后关闭遭遇对话")
	_check(
		is_zero_approx(TimeManager.get_effective_world_scale()),
		"取消遭遇不会清除其他暂停原因"
	)
	_check(
		is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_DOUBLE),
		"取消遭遇保留基础倍率"
	)
	_check(
		context.encounter_manager.get_pending_player_encounter().is_empty(),
		"取消后清理待处理遭遇"
	)
	TimeManager.pop_pause(OTHER_PAUSE)
	_check(
		is_equal_approx(TimeManager.get_effective_world_scale(), TimeManager.SPEED_DOUBLE),
		"移除其他暂停后恢复 2x"
	)

	# 再次触发并选择战斗，验证进入战斗场景。
	bandit.attack_intent = true
	bandit.current_target_id = player.party_id
	_check(context.encounter_manager.update_encounters(), "再次触发遭遇")
	await get_tree().process_frame
	panel = _find_encounter_panel()
	_check(panel != null and panel.visible, "再次显示遭遇对话")
	if panel == null or not panel.visible:
		return
	fight_button = panel.find_child("EncounterFightButton", true, false) as Button
	_check(fight_button != null, "再次找到战斗按钮")
	if fight_button == null:
		return
	fight_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	_check(
		get_tree().current_scene != null and get_tree().current_scene.name == "Battle",
		"选择战斗后进入战斗场景"
	)
	var session := context.battle_manager.current_battle
	_check(session != null, "遭遇战斗会话存在")
	if session != null:
		_check(
			session.get_side_of_party(player.party_id) == 0,
			"玩家位于战斗侧 0"
		)
		_check(
			session.get_side_of_party(bandit.party_id) == 1,
			"强盗位于战斗侧 1"
		)
		_check(
			is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_DOUBLE),
			"进入战斗后基础倍率保持不变"
		)
		context.battle_manager.abort_battle(session.battle_id)
	_check(
		is_equal_approx(TimeManager.get_effective_world_scale(), TimeManager.SPEED_DOUBLE),
		"战斗结束后恢复 2x"
	)


func _find_party_by_name(context: WorldContext, party_name: String) -> PartyData:
	if context == null:
		return null
	for party: PartyData in context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _find_encounter_panel() -> PanelContainer:
	if get_tree().current_scene == null:
		return null
	return get_tree().current_scene.find_child(
		"PlayerEncounterPanel", true, false
	) as PanelContainer


func _count_encounter_panels() -> int:
	if get_tree().current_scene == null:
		return 0
	return get_tree().current_scene.find_children(
		"PlayerEncounterPanel", "PanelContainer", true, false
	).size()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[encounter] OK: %s" % message)
	else:
		_failed = true
		push_error("[encounter] FAIL: %s" % message)


func _cleanup() -> void:
	GameManager.enter_main_menu()
	TimeManager.stop_session()
	TimeManager.clear_pauses()
