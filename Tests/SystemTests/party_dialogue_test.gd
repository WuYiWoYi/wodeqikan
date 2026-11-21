extends Node
## Step 2.1：大地图 AI 部队交互与对话 UI 测试。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/party_dialogue_test.tscn

const TEST_SLOT: String = "__party_dialogue_test__"

var _failed: bool = false
var _context: WorldContext = null
var _map: Node = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[dialogue] 测试失败")
		get_tree().quit(1)
	else:
		print("[dialogue] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)

	_context = WorldContext.new()
	_context.name = "DialogueTestContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")

	var player := _context.get_player_party()
	var enemy := _find_party_by_name(WorldInitializer.TEST_ENEMY_PARTY_NAME)
	_check(player != null and enemy != null, "玩家与敌方部队存在")
	if player == null or enemy == null:
		return
	_check(player.member_unit_ids.size() == 7, "玩家测试兵力为 7")
	_check(enemy.member_unit_ids.size() == 5, "敌方测试兵力为 5")

	# 商队初始位于橡木村；把它移到远离地点的空地，避免地点面板抢占对话。
	enemy.world_position = Vector2(900.0, 1500.0)
	enemy.target_position = enemy.world_position
	enemy.movement_state = PartyData.MovementState.IDLE

	# 在创建大地图前把玩家放到敌方附近，_last_player_position 会以该位置初始化。
	player.world_position = enemy.world_position + Vector2(-20.0, 0.0)
	player.target_position = player.world_position
	player.movement_state = PartyData.MovementState.IDLE

	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id
	TimeManager.set_base_world_speed(TimeManager.SPEED_DOUBLE)

	var packed_map := load("res://Scenes/WorldMap/world_map.tscn") as PackedScene
	_map = packed_map.instantiate()
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var panel := _map.find_child("PartyDialoguePanel", true, false) as PanelContainer
	_check(panel != null and panel.visible, "接近敌方部队后打开对话 UI")
	if panel == null:
		return

	var name_label := _map.find_child("PartyNameLabel", true, false) as Label
	var faction_label := _map.find_child("PartyFactionLabel", true, false) as Label
	var troop_label := _map.find_child("PartyTroopLabel", true, false) as Label
	_check(name_label != null and name_label.text == enemy.party_name, "显示敌方部队名称")
	_check(
		faction_label != null and faction_label.text.contains("商队"),
		"显示敌方阵营"
	)
	_check(
		troop_label != null and troop_label.text.contains("5"),
		"显示兵力且与 PartyData 一致"
	)
	_check(is_zero_approx(TimeManager.get_effective_world_scale()), "对话打开时世界暂停")

	for i: int in range(5):
		await get_tree().process_frame
	_check(
		_map.find_children("PartyDialoguePanel", "PanelContainer", true, false).size() == 1,
		"重复帧不会创建多个对话窗口"
	)

	var leave_button := _map.find_child("PartyLeaveButton", true, false) as Button
	_check(leave_button != null, "对话包含离开按钮")
	if leave_button == null:
		return
	leave_button.pressed.emit()
	await get_tree().process_frame
	_check(not panel.visible, "点击离开后关闭对话 UI")
	_check(
		is_equal_approx(TimeManager.get_effective_world_scale(), TimeManager.SPEED_DOUBLE),
		"离开后恢复此前世界时间状态"
	)

	# 离开交互范围后再次接近，验证可重复打开。
	player.world_position = enemy.world_position + Vector2(-100.0, 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	player.world_position = enemy.world_position + Vector2(-20.0, 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(panel.visible, "离开范围后再次接近可重新打开对话")

	var fight_button := _map.find_child("PartyFightButton", true, false) as Button
	_check(fight_button != null and not fight_button.disabled, "双方有兵时发起战斗可用")
	if fight_button == null:
		return

	var session: BattleSession = _map.begin_battle_with_party()
	_check(session != null, "发起战斗进入准备流程")
	if session == null:
		return
	_check(_context.battle_manager.current_battle == session, "BattleManager 持有战斗会话")
	_check(session.attacker_unit_ids.size() == 7, "玩家 7 名士兵进入会话")
	_check(session.defender_unit_ids.size() == 5, "敌方 5 名士兵进入会话")
	_check(player.battle_state == PartyData.BattleState.IN_BATTLE, "玩家部队已锁定")
	_check(enemy.battle_state == PartyData.BattleState.IN_BATTLE, "敌方部队已锁定")
	_check(is_zero_approx(TimeManager.get_effective_world_scale()), "战斗准备期间世界暂停")
	_check(not panel.visible, "进入战斗准备后关闭对话")
	_check(GameManager.save_game(TEST_SLOT) == ERR_BUSY, "战斗期间禁止存档")

	_check(_context.battle_manager.abort_battle(session.battle_id), "中止测试战斗")
	_check(_context.battle_manager.current_battle == null, "中止后清理战斗会话")
	_check(player.battle_state == PartyData.BattleState.AVAILABLE, "中止后玩家部队解锁")
	_check(enemy.battle_state == PartyData.BattleState.AVAILABLE, "中止后敌方部队解锁")
	_check(
		is_equal_approx(TimeManager.get_effective_world_scale(), TimeManager.SPEED_DOUBLE),
		"中止后恢复世界时间状态"
	)


func _find_party_by_name(party_name: String) -> PartyData:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[dialogue] OK: %s" % message)
	else:
		_failed = true
		push_error("[dialogue] FAIL: %s" % message)


func _cleanup() -> void:
	SaveManager.delete_save(TEST_SLOT)
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_map):
		_map.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
