extends Node
## 大地图中立部队与主动交互测试：
## 普通寻路/追击路过中立或无关敌对部队不弹窗；主动点击目标才打开对话；
## 只有敌对 AI 实际追击玩家时才自动遭遇。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/neutral_party_interaction_test.tscn

var _failed: bool = false
var _context: WorldContext = null
var _map: Node = null
var _player: PartyData = null
var _merchant: PartyData = null
var _bandit: PartyData = null
var _guard: PartyData = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[neutral] 测试失败")
		get_tree().quit(1)
	else:
		print("[neutral] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)

	_context = WorldContext.new()
	_context.name = "NeutralPartyTestContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return
	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id
	_player = _context.get_player_party()
	_merchant = _find_party(WorldInitializer.TEST_ENEMY_PARTY_NAME)
	_bandit = _find_party(WorldInitializer.BANDIT_PARTY_NAME)
	_guard = _find_party(WorldInitializer.GUARD_PARTY_NAME)
	_check(
		_player != null and _merchant != null and _bandit != null and _guard != null,
		"找到玩家与三方 NPC"
	)
	if _player == null or _merchant == null or _bandit == null or _guard == null:
		return

	_isolate_parties()
	_player.world_position = Vector2(900.0, 1200.0)
	_merchant.world_position = Vector2(1000.0, 1200.0)
	_bandit.world_position = Vector2(1100.0, 1300.0)
	_guard.world_position = Vector2(700.0, 1300.0)

	var packed := load("res://Scenes/WorldMap/world_map.tscn") as PackedScene
	_map = packed.instantiate()
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame
	# 直接调用交互判定，避免场景帧与玩家位置模拟互相干扰。
	_map.set_process(false)

	var party_panel := _path_panel()
	_check(party_panel != null and not party_panel.visible, "初始不显示部队对话")

	# 1. 普通寻路经过中立部队：不弹窗。
	_player.focus_party_id = ""
	_map.set("_last_player_position", Vector2(1040.0, 1200.0))
	_player.world_position = Vector2(960.0, 1200.0)
	_map.call("_check_party_interaction")
	_check(not party_panel.visible, "普通寻路路过中立部队不会自动弹窗")
	_check(
		not TimeManager.has_pause_reason(GameManager.PAUSE_REASON_UI_PANEL),
		"路过中立部队不会被强制暂停"
	)

	# 2. 玩家追击其他目标时路过中立部队：不弹窗。
	_player.focus_party_id = _guard.party_id
	_map.call("_check_party_interaction")
	_check(not party_panel.visible, "追击其他目标时路过中立部队不打断行动")

	# 3. 玩家主动点击中立部队并接近：沿用主动交互入口。
	_player.focus_party_id = ""
	_merchant.world_position = _player.world_position + Vector2(100.0, 0.0)
	_check(
		_map.call("request_party_command", _merchant.party_id),
		"点击中立部队进入主动接近"
	)
	_check(_player.focus_party_id == _merchant.party_id, "记录主动交互目标")
	_map.set("_last_player_position", _player.world_position)
	_player.world_position = _merchant.world_position + Vector2(-20.0, 0.0)
	_map.call("_check_party_interaction")
	_check(party_panel.visible, "主动接近点击过的部队会打开对话")
	_check(
		party_panel.anchor_top >= 0.99 and party_panel.anchor_bottom >= 0.99,
		"普通部队对话同样位于屏幕下方"
	)
	var party_portrait := party_panel.find_child(
		"PartyPortrait", true, false
	) as EncounterPortrait
	_check(
		party_portrait != null and party_portrait.has_leader_visual(),
		"普通部队对话显示对方领袖头像/剪影"
	)
	_check(_player.focus_party_id.is_empty(), "对话打开后清理追逐焦点")
	if party_panel.visible:
		_map.call("_on_party_leave_pressed")
	_check(not party_panel.visible, "离开部队对话后关闭面板")

	# 4. 附近无关敌对部队没有追击玩家：不自动遭遇。
	_player.world_position = Vector2(900.0, 1200.0)
	_merchant.world_position = Vector2(1000.0, 1200.0)
	_bandit.world_position = Vector2(940.0, 1200.0)
	_player.focus_party_id = _merchant.party_id
	_bandit.attack_intent = false
	_bandit.current_target_id = ""
	_check(
		not _context.encounter_manager.update_encounters(),
		"无关敌对部队仅靠近不会自动打断玩家"
	)
	_check(
		not _context.encounter_manager.has_pending_player_encounter(),
		"无追击关系时不产生待处理遭遇"
	)
	_check(
		not TimeManager.has_pause_reason(GameManager.PAUSE_REASON_ENCOUNTER_DIALOGUE),
		"无追击关系时不暂停世界"
	)

	# 5. 敌对 AI 明确追击并追上玩家：触发一次自动遭遇。
	_bandit.attack_intent = true
	_bandit.current_target_id = _player.party_id
	_check(
		_context.encounter_manager.update_encounters(),
		"敌对 AI 实际追上玩家时触发遭遇"
	)
	await get_tree().process_frame
	var encounter_panel := _path_panel("PlayerEncounterPanel")
	_check(encounter_panel != null and encounter_panel.visible, "显示遭遇选择面板")
	_check(
		TimeManager.has_pause_reason(GameManager.PAUSE_REASON_ENCOUNTER_DIALOGUE),
		"遭遇面板暂停世界"
	)
	_check(
		_player.movement_state == PartyData.MovementState.IDLE
		and _bandit.movement_state == PartyData.MovementState.IDLE,
		"遭遇后双方停止移动"
	)
	_check(_player.focus_party_id.is_empty(), "遭遇后清除玩家追击焦点")
	_check(
		not _context.encounter_manager.update_encounters(),
		"同一追击关系不会重复触发遭遇"
	)
	if encounter_panel != null and encounter_panel.visible:
		var retreat := encounter_panel.find_child(
			"EncounterLeaveButton", true, false
		) as Button
		_check(
			retreat != null and not retreat.visible,
			"敌对 AI 追击拦截时不提供离开选项"
		)
		# 没有离开选项时通过取消/战斗流程结束对话；这里验证清理接口。
		_map.call("cancel_player_encounter")
	await get_tree().process_frame
	_check(
		_context.encounter_manager.get_pending_player_encounter().is_empty(),
		"取消后清理待处理遭遇"
	)
	_check(
		not TimeManager.has_pause_reason(GameManager.PAUSE_REASON_ENCOUNTER_DIALOGUE),
		"取消后移除遭遇暂停"
	)


func _isolate_parties() -> void:
	for party: PartyData in _context.party_manager.get_all_parties():
		party.ai_type = PartyData.PartyAIType.NONE
		party.attack_intent = false
		party.focus_party_id = ""
		party.current_target_id = ""
		party.current_order = PartyData.OrderType.NONE
		party.movement_state = PartyData.MovementState.IDLE
		party.target_position = party.world_position


func _path_panel(node_name: String = "PartyDialoguePanel") -> PanelContainer:
	if _map == null:
		return null
	return _map.find_child(node_name, true, false) as PanelContainer


func _find_party(party_name: String) -> PartyData:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[neutral] OK: %s" % message)
	else:
		_failed = true
		push_error("[neutral] FAIL: %s" % message)


func _cleanup() -> void:
	if _context != null and _context.battle_manager.current_battle != null:
		_context.battle_manager.finish_battle(
			_context.battle_manager.current_battle.battle_id,
			BattleSession.BattleResult.ABORTED
		)
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_map):
		_map.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
