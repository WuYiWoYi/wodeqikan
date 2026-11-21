extends Node
## 玩家主动追击同向移动敌军的大地图接触测试。
## 覆盖：持续追击、进入遭遇距离、双方停止、暂停与面板、撤退、拒绝锁、再次触发与进入战斗。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/player_pursuit_encounter_test.tscn

var _failed: bool = false
var _context: WorldContext = null
var _map: Node = null
var _player: PartyData = null
var _bandit: PartyData = null


func _ready() -> void:
	get_tree().current_scene = null
	await get_tree().process_frame
	await _run()
	_cleanup()
	if _failed:
		push_error("[pursuit] 测试失败")
		get_tree().quit(1)
	else:
		print("[pursuit] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.clear_pauses()
	TimeManager.stop_session()
	_check(GameManager.start_new_game(), "新游戏启动")
	await get_tree().process_frame
	await get_tree().process_frame

	_context = GameManager.world_context
	_map = get_tree().current_scene
	_player = _context.get_player_party() if _context != null else null
	_bandit = _find_party_by_name(WorldInitializer.BANDIT_PARTY_NAME)
	_check(_player != null and _bandit != null and _map != null, "玩家、强盗与大地图存在")
	if _player == null or _bandit == null or _map == null:
		return

	_isolate_parties()
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)
	_player.world_position = Vector2(900.0, 1200.0)
	_player.target_position = _player.world_position
	_player.movement_state = PartyData.MovementState.IDLE
	_player.current_order = PartyData.OrderType.NONE
	_bandit.world_position = Vector2(1080.0, 1200.0)
	_bandit.target_position = Vector2(2500.0, 1200.0)
	_bandit.movement_state = PartyData.MovementState.MOVING
	_bandit.current_order = PartyData.OrderType.MOVE
	_bandit.attack_intent = false

	_check(_map.call("request_party_command", _bandit.party_id), "点击移动中的敌军开始追击")
	_check(_player.focus_party_id == _bandit.party_id, "记录主动追击焦点")
	_check(_player.current_order == PartyData.OrderType.FOLLOW_PARTY, "玩家进入持续跟随指令")

	var triggered: bool = false
	for i: int in range(300):
		_context.world_map_manager.update_party_movement(0.1)
		if _context.encounter_manager.update_encounters():
			triggered = true
			break
		if _player.world_position.distance_to(_bandit.world_position) > 400.0:
			break
	_check(triggered, "同向追击进入有效距离后触发一次接触")
	_check(
		_player.world_position.distance_to(_bandit.world_position) <= 50.0,
		"接触发生在有效遭遇距离内"
	)
	_check(
		_player.movement_state == PartyData.MovementState.IDLE
		and _bandit.movement_state == PartyData.MovementState.IDLE,
		"接触成立后双方立即停止移动"
	)
	_check(
		_player.target_position == _player.world_position
		and _bandit.target_position == _bandit.world_position,
		"接触后清除旧移动目标，避免位置回弹"
	)
	_check(
		_player.current_target_id.is_empty()
		and _bandit.current_target_id.is_empty()
		and _player.focus_party_id.is_empty(),
		"接触后清除追击目标与焦点"
	)
	_check(not _bandit.attack_intent, "接触后清除攻击意图")

	var player_stop := _player.world_position
	var bandit_stop := _bandit.world_position
	_context.world_map_manager.update_party_movement(0.5)
	_check(
		_player.world_position == player_stop
		and _bandit.world_position == bandit_stop,
		"接触后继续移动 tick 不会推挤或回弹"
	)

	await get_tree().process_frame
	var panel := _find_panel("PlayerEncounterPanel")
	_check(panel != null and panel.visible, "弹出战斗选择界面")
	_check(
		is_zero_approx(TimeManager.get_effective_world_scale()),
		"遭遇界面暂停世界时间"
	)
	_check(
		is_equal_approx(
			TimeManager.get_base_world_speed(), TimeManager.SPEED_NORMAL
		),
		"遭遇界面不改变基础倍率"
	)
	if panel != null and panel.visible:
		var retreat := panel.find_child("EncounterLeaveButton", true, false) as Button
		_check(retreat != null, "提供撤退选项")
		if retreat != null:
			retreat.pressed.emit()
	await get_tree().process_frame
	_check(panel != null and not panel.visible, "撤退后关闭遭遇界面")
	_check(
		_context.encounter_manager.get_pending_player_encounter().is_empty(),
		"撤退后清理待处理遭遇"
	)
	_check(
		is_equal_approx(
			TimeManager.get_effective_world_scale(), TimeManager.SPEED_NORMAL
		),
		"撤退后恢复基础倍率"
	)
	_check(
		_player.movement_state == PartyData.MovementState.IDLE
		and _bandit.movement_state == PartyData.MovementState.IDLE,
		"撤退后不会留下永久移动中的部队"
	)

	# 仍在拒绝范围内再次追击：不重复弹出同一场遭遇。
	_player.focus_party_id = _bandit.party_id
	_check(
		not _context.encounter_manager.update_encounters(),
		"撤退后原地再次追击不会重复触发"
	)

	# 离开拒绝范围后重新接近可以再次触发。
	_player.world_position = _bandit.world_position + Vector2(140.0, 0.0)
	_context.encounter_manager.update_encounters()
	_check(
		_context.encounter_manager.get_pending_player_encounter().is_empty(),
		"离开拒绝范围只清除锁存，不立即触发"
	)
	_player.world_position = _bandit.world_position + Vector2(45.0, 0.0)
	_player.focus_party_id = _bandit.party_id
	_check(
		_context.encounter_manager.update_encounters(),
		"离开范围后再次接近可以重新触发"
	)
	await get_tree().process_frame
	panel = _find_panel("PlayerEncounterPanel")
	if panel == null or not panel.visible:
		return
	var fight := panel.find_child("EncounterFightButton", true, false) as Button
	_check(fight != null, "重新触发后存在战斗按钮")
	if fight != null:
		fight.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	_check(
		get_tree().current_scene != null and get_tree().current_scene.name == "Battle",
		"选择战斗后进入战斗场景"
	)
	var session := _context.battle_manager.current_battle
	_check(session != null, "创建或加入唯一战斗会话")
	if session != null:
		_check(
			session.get_side_of_party(_player.party_id)
			!= session.get_side_of_party(_bandit.party_id),
			"玩家与追击目标处于不同战斗侧"
		)
		_context.battle_manager.abort_battle(session.battle_id)


func _isolate_parties() -> void:
	for party: PartyData in _context.party_manager.get_all_parties():
		var is_target: bool = party.party_id == _player.party_id \
			or party.party_id == _bandit.party_id
		party.ai_type = PartyData.PartyAIType.NONE
		party.attack_intent = false
		party.focus_party_id = ""
		party.current_target_id = ""
		party.current_order = PartyData.OrderType.NONE
		party.movement_state = PartyData.MovementState.IDLE
		if not is_target:
			party.world_position = Vector2(2700.0, 1800.0)
			party.target_position = party.world_position


func _find_party_by_name(party_name: String) -> PartyData:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _find_panel(node_name: String) -> PanelContainer:
	if get_tree().current_scene == null:
		return null
	return get_tree().current_scene.find_child(node_name, true, false) as PanelContainer


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[pursuit] OK: %s" % message)
	else:
		_failed = true
		push_error("[pursuit] FAIL: %s" % message)


func _cleanup() -> void:
	if _context != null and _context.battle_manager.current_battle != null:
		_context.battle_manager.abort_battle(
			_context.battle_manager.current_battle.battle_id
		)
	GameManager.enter_main_menu()
	TimeManager.stop_session()
	TimeManager.clear_pauses()
