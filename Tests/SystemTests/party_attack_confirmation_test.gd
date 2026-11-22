extends Node
## 阶段 10 系统测试：玩家主动攻击二次确认。
## 覆盖确认弹窗、取消无副作用、确认前条件重校验、重复入口不重复创建战斗，
## 以及加入友军既有战斗时不弹攻击确认。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . \
##     res://Tests/SystemTests/party_attack_confirmation_test.tscn

var _failed: bool = false
var _context: WorldContext = null
var _map: Node = null
var _player: PartyData = null
var _bandit: PartyData = null
var _merchant: PartyData = null


func _ready() -> void:
	get_tree().current_scene = null
	await get_tree().process_frame
	await _run()
	_cleanup()
	if _failed:
		push_error("[attackconfirm] 测试失败")
		get_tree().quit(1)
	else:
		print("[attackconfirm] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	_context = WorldContext.new()
	_context.name = "AttackConfirmTestContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return
	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id
	_player = _context.get_player_party()
	_bandit = _find_party(WorldInitializer.BANDIT_PARTY_NAME)
	_merchant = _find_party(WorldInitializer.TEST_ENEMY_PARTY_NAME)
	_check(
		_player != null and _bandit != null and _merchant != null,
		"找到玩家、强盗与商队"
	)
	if _player == null or _bandit == null or _merchant == null:
		return
	_isolate_world()

	var packed := load("res://Scenes/WorldMap/world_map.tscn") as PackedScene
	_map = packed.instantiate()
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame

	_test_confirm_and_cancel_without_side_effects()
	_test_confirmation_revalidates()
	_test_repeated_entry_creates_one_battle()
	_test_joining_ally_battle_needs_no_confirmation()


func _test_confirm_and_cancel_without_side_effects() -> void:
	_open_dialogue(_bandit)
	_check(_party_panel_visible(), "打开敌对部队对话")
	var fight := _button("PartyFightButton")
	_check(fight != null and fight.text == "发起战斗", "敌对部队显示发起战斗按钮")
	if fight == null:
		return

	var player_before := _party_snapshot(_player)
	var enemy_before := _party_snapshot(_bandit)
	var world_before := TimeManager.world_elapsed_seconds
	var scale_before := TimeManager.get_effective_world_scale()
	fight.pressed.emit()
	var confirm := _map.find_child("AttackConfirmPanel", true, false) as PanelContainer
	var confirm_label := _map.find_child("AttackConfirmLabel", true, false) as Label
	_check(confirm != null and confirm.visible, "点击发起战斗先显示二次确认")
	_check(
		confirm_label != null and confirm_label.text.contains(_bandit.party_name),
		"确认文本包含目标部队名"
	)
	_check(not _context.battle_manager.has_any_active_battles(), "确认前不创建战斗")
	_check(
		_context.battle_manager.get_battle_for_party(_player.party_id) == null,
		"确认前玩家未进入战斗"
	)
	_check(_party_panel_visible(), "确认时原部队对话仍然保留")

	var cancel := _button("CancelAttackButton")
	_check(cancel != null, "确认面板提供取消按钮")
	if cancel != null:
		cancel.pressed.emit()
	_check(
		confirm != null and not confirm.visible,
		"取消后关闭确认面板"
	)
	_check(_party_panel_visible(), "取消后返回原部队对话")
	_check(not _context.battle_manager.has_any_active_battles(), "取消不创建战斗")
	_check(
		_party_snapshot(_player) == player_before
			and _party_snapshot(_bandit) == enemy_before,
		"取消不改变双方状态、位置与成员"
	)
	_check(
		is_equal_approx(TimeManager.world_elapsed_seconds, world_before)
			and is_equal_approx(
				TimeManager.get_effective_world_scale(), scale_before
			),
		"取消不改变世界时间与暂停状态"
	)
	_close_dialogue()


func _test_confirmation_revalidates() -> void:
	_open_dialogue(_bandit)
	var fight := _button("PartyFightButton")
	if fight == null:
		return
	fight.pressed.emit()
	# 确认前目标失效：确认必须重新校验并拒绝开战。
	_bandit.battle_state = PartyData.BattleState.DISABLED
	var confirm := _button("ConfirmAttackButton")
	if confirm != null:
		confirm.pressed.emit()
	_check(
		not _context.battle_manager.has_any_active_battles(),
		"条件变化后确认不会创建战斗"
	)
	var status := _map.find_child("PartyDialogueStatus", true, false) as Label
	_check(
		status != null and not status.text.is_empty(),
		"条件变化后显示无法开战原因"
	)
	var panel := _map.find_child("AttackConfirmPanel", true, false) as PanelContainer
	_check(panel != null and not panel.visible, "校验失败后关闭确认面板")
	_bandit.battle_state = PartyData.BattleState.AVAILABLE
	_close_dialogue()


func _test_repeated_entry_creates_one_battle() -> void:
	_open_dialogue(_bandit)
	var first: BattleSession = _map.call("begin_battle_with_party")
	_check(first != null, "确认后的统一入口创建战斗")
	var second: BattleSession = _map.call("begin_battle_with_party")
	_check(second == null, "重复进入统一入口被拒绝")
	_check(
		first != null and _context.battle_manager.get_active_battles().size() == 1,
		"重复确认不会创建第二场战斗"
	)
	_check(
		_player.battle_state == PartyData.BattleState.IN_BATTLE
			and _bandit.battle_state == PartyData.BattleState.IN_BATTLE,
		"一次性创建的战斗锁定了双方"
	)
	if first != null:
		_context.battle_manager.finish_battle(
			first.battle_id, BattleSession.BattleResult.ABORTED
		)
	_map.set("_battle_transition_started", false)
	_close_dialogue()


func _test_joining_ally_battle_needs_no_confirmation() -> void:
	_check(
		not _context.battle_manager.has_any_active_battles(),
		"加入友军战斗前没有残留战斗"
	)
	var position := Vector2(2200.0, 1400.0)
	_player.world_position = position + Vector2(30.0, 0.0)
	_player.target_position = _player.world_position
	var session := _context.battle_manager.start_battle(
		[_bandit.party_id], [_merchant.party_id], position, true
	)
	_check(session != null, "创建友军参与的离屏战斗")
	if session == null:
		return
	_open_dialogue(_merchant)
	var fight := _button("PartyFightButton")
	_check(fight != null and fight.text == "加入战斗", "友军战斗显示加入战斗按钮")
	var confirm := _map.find_child("AttackConfirmPanel", true, false) as PanelContainer
	if fight != null:
		fight.pressed.emit()
	_check(
		confirm != null and not confirm.visible,
		"加入友军战斗不弹主动攻击确认"
	)
	var joined := _context.battle_manager.get_battle_for_party(_player.party_id)
	_check(
		joined == session and _context.battle_manager.get_active_battles().size() == 1,
		"加入的是既有战斗，没有重复创建"
	)
	_check(
		joined != null
			and joined.get_side_of_party(_player.party_id)
				== joined.get_side_of_party(_merchant.party_id)
			and joined.get_side_of_party(_player.party_id)
				!= joined.get_side_of_party(_bandit.party_id),
		"玩家加入商队一方"
	)


func _open_dialogue(party: PartyData) -> void:
	_map.call("_open_party_dialogue", party)


func _close_dialogue() -> void:
	var panel := _map.find_child("PartyDialoguePanel", true, false) as Control
	if panel != null and panel.visible:
		_map.call("_on_party_leave_pressed")


func _party_panel_visible() -> bool:
	var panel := _map.find_child("PartyDialoguePanel", true, false) as Control
	return panel != null and panel.visible


func _button(node_name: String) -> Button:
	return _map.find_child(node_name, true, false) as Button


func _party_snapshot(party: PartyData) -> Dictionary:
	if party == null:
		return {}
	return {
		"battle_state": int(party.battle_state),
		"order": int(party.current_order),
		"movement": int(party.movement_state),
		"target_id": party.current_target_id,
		"attack_intent": party.attack_intent,
		"focus": party.focus_party_id,
		"world_position": party.world_position,
		"target_position": party.target_position,
		"units": party.member_unit_ids.size(),
	}


func _isolate_world() -> void:
	for party: PartyData in _context.party_manager.get_all_parties():
		party.ai_type = PartyData.PartyAIType.NONE
		party.attack_intent = false
		party.focus_party_id = ""
		party.current_target_id = ""
		party.current_order = PartyData.OrderType.NONE
		party.movement_state = PartyData.MovementState.IDLE
		party.battle_state = PartyData.BattleState.AVAILABLE
		party.battle_response_id = ""
		if party.party_id != _player.party_id:
			party.world_position = Vector2(4000.0, 2400.0)
			party.target_position = party.world_position
	_player.world_position = Vector2(1000.0, 1000.0)
	_player.target_position = _player.world_position
	_bandit.world_position = Vector2(1050.0, 1000.0)
	_bandit.target_position = _bandit.world_position


func _find_party(party_name: String) -> PartyData:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[attackconfirm] OK: %s" % message)
	else:
		_failed = true
		push_error("[attackconfirm] FAIL: %s" % message)


func _cleanup() -> void:
	if is_instance_valid(_context):
		for session: BattleSession in _context.battle_manager.get_active_battles():
			_context.battle_manager.finish_battle(
				session.battle_id, BattleSession.BattleResult.ABORTED
			)
	# 先移除大地图，避免其 _process 在 WorldContext 释放后继续读取世界尺寸。
	if is_instance_valid(_map):
		_map.free()
		_map = null
	GameManager.enter_main_menu()
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_context):
		_context.queue_free()
