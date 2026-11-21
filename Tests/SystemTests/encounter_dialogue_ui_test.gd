extends Node
## 阶段 7：大地图圆形标记与底部 NPC 遭遇对话测试。
## 覆盖：统一标记尺寸、敌对追击无离开选项、领袖头像/默认剪影、
## 玩家主动接近的对话与离开选项、对话文本来自配置。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/encounter_dialogue_ui_test.tscn

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
		push_error("[encui] 测试失败")
		get_tree().quit(1)
	else:
		print("[encui] 全部通过")
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
	_bandit = _find_party(WorldInitializer.BANDIT_PARTY_NAME)
	_merchant = _find_party(WorldInitializer.TEST_ENEMY_PARTY_NAME)
	_check(
		_context != null and _map != null and _player != null
		and _bandit != null and _merchant != null,
		"世界、大地图与测试部队存在"
	)
	if _context == null or _map == null or _player == null \
			or _bandit == null or _merchant == null:
		return

	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	_isolate_parties()
	_test_marker_style()
	await _test_enemy_pursuit_dialogue()
	await _test_missing_leader_fallback()
	await _test_player_initiated_dialogue()


func _test_marker_style() -> void:
	var style := load(
		"res://Data/WorldMap/party_marker_style.tres"
	) as PartyMarkerStyle
	_check(style != null, "加载统一的部队标记样式")
	if style == null:
		return
	_check(
		is_equal_approx(style.marker_radius, 18.0),
		"部队圆形标记恢复扩编前的原始尺寸"
	)
	_check(
		style.flag_max_size <= 30.0,
		"部队旗帜未随村庄一起放大"
	)
	var player_icon := _map.find_child(
		"PartyIcon_%s" % _player.party_id, true, false
	) as PartyIcon
	var bandit_icon := _map.find_child(
		"PartyIcon_%s" % _bandit.party_id, true, false
	) as PartyIcon
	var knights := _find_party(WorldInitializer.BARI_KNIGHT_PARTY_NAME)
	var knight_icon: PartyIcon = null
	if knights != null:
		knight_icon = _map.find_child(
			"PartyIcon_%s" % knights.party_id, true, false
		) as PartyIcon
	_check(
		player_icon != null and bandit_icon != null and knight_icon != null,
		"玩家/强盗/家族部队使用同一标记组件"
	)
	if player_icon != null and bandit_icon != null and knight_icon != null:
		_check(
			is_equal_approx(player_icon.get_marker_radius(), bandit_icon.get_marker_radius())
			and is_equal_approx(
				bandit_icon.get_marker_radius(), knight_icon.get_marker_radius()
			),
			"不同部队类型标记尺寸一致"
		)
		_check(
			is_equal_approx(bandit_icon.get_marker_radius(), style.marker_radius),
			"标记半径读取集中样式配置"
		)
		_check(
			player_icon.get_count_text() == str(_player.member_unit_ids.size()),
			"统一标记仍显示部队人数"
		)


func _test_enemy_pursuit_dialogue() -> void:
	_bandit.world_position = _player.world_position + Vector2(40.0, 0.0)
	_bandit.attack_intent = true
	_bandit.current_target_id = _player.party_id
	_check(_context.encounter_manager.update_encounters(), "敌对部队追击追上玩家")
	await get_tree().process_frame

	var panel := _find_panel("PlayerEncounterPanel")
	_check(panel != null and panel.visible, "弹出底部遭遇对话")
	if panel == null or not panel.visible:
		return
	_check(
		_context.encounter_manager.get_pending_encounter_reason()
		== EncounterManager.EncounterReason.ENEMY_PURSUIT,
		"遭遇原因记录为 ENEMY_PURSUIT"
	)
	_check(
		panel.anchor_top >= 0.99 and panel.anchor_bottom >= 0.99,
		"遭遇对话锚定在屏幕下方"
	)
	var portrait := panel.find_child("EncounterPortrait", true, false) as EncounterPortrait
	_check(
		portrait != null and portrait.has_leader_visual(),
		"显示对方领袖角色头像/剪影"
	)
	var name_label := panel.find_child(
		"EncounterPartyNameLabel", true, false
	) as Label
	var leader := _context.party_manager.get_leader_unit(_bandit.party_id)
	_check(
		name_label != null and name_label.text == _player_leader_name(_bandit, leader),
		"显示对方领袖名称"
	)
	var text_label := panel.find_child(
		"EncounterDescriptionLabel", true, false
	) as Label
	_check(
		text_label != null and text_label.text.contains("财物"),
		"强盗追击对话来自配置文本"
	)
	var leave_button := panel.find_child(
		"EncounterLeaveButton", true, false
	) as Button
	_check(
		leave_button != null and not leave_button.visible and leave_button.disabled,
		"敌对追击成功后不显示离开选项"
	)
	_check(_count_visible_buttons(panel) == 1, "只保留战斗等敌对处理选项")
	var fight_button := panel.find_child(
		"EncounterFightButton", true, false
	) as Button
	_check(fight_button != null and fight_button.visible, "保留战斗选项")
	_map.call("cancel_player_encounter")
	await get_tree().process_frame


func _test_missing_leader_fallback() -> void:
	var leader_id: String = _bandit.leader_unit_id
	_bandit.leader_unit_id = ""
	_bandit.attack_intent = true
	_bandit.current_target_id = _player.party_id
	_check(_context.encounter_manager.update_encounters(), "无领袖部队仍可触发遭遇")
	await get_tree().process_frame
	var panel := _find_panel("PlayerEncounterPanel")
	_check(panel != null and panel.visible, "无领袖部队遭遇对话正常显示")
	if panel != null and panel.visible:
		var portrait := panel.find_child(
			"EncounterPortrait", true, false
		) as EncounterPortrait
		_check(
			portrait != null and not portrait.has_leader_visual(),
			"无有效领袖时使用安全默认剪影"
		)
		var name_label := panel.find_child(
			"EncounterPartyNameLabel", true, false
		) as Label
		_check(
			name_label != null and name_label.text == _bandit.party_name,
			"无领袖名称时回退到部队名"
		)
		_map.call("cancel_player_encounter")
	await get_tree().process_frame
	_bandit.leader_unit_id = leader_id


func _test_player_initiated_dialogue() -> void:
	_context.encounter_manager.clear_encounter_decline_latch()
	_bandit.attack_intent = false
	_bandit.current_target_id = ""
	_bandit.world_position = _player.world_position + Vector2(40.0, 0.0)
	_player.focus_party_id = _bandit.party_id
	_check(_context.encounter_manager.update_encounters(), "玩家主动接近敌对部队")
	await get_tree().process_frame
	var panel := _find_panel("PlayerEncounterPanel")
	_check(panel != null and panel.visible, "玩家主动遭遇同样弹出底部对话")
	if panel == null or not panel.visible:
		return
	_check(
		_context.encounter_manager.get_pending_encounter_reason()
		== EncounterManager.EncounterReason.PLAYER_INITIATED,
		"玩家主动接近记录为 PLAYER_INITIATED"
	)
	var leave_button := panel.find_child(
		"EncounterLeaveButton", true, false
	) as Button
	_check(
		leave_button != null and leave_button.visible and not leave_button.disabled,
		"玩家主动遭遇仍保留离开选项"
	)
	var text_label := panel.find_child(
		"EncounterDescriptionLabel", true, false
	) as Label
	_check(
		text_label != null and text_label.text.contains("强盗"),
		"玩家主动遭遇使用对应配置文本"
	)
	_map.call("cancel_player_encounter")
	await get_tree().process_frame


func _isolate_parties() -> void:
	for party: PartyData in _context.party_manager.get_all_parties():
		var is_player: bool = party.party_id == _player.party_id
		party.ai_type = PartyData.PartyAIType.NONE
		party.attack_intent = false
		party.focus_party_id = ""
		party.current_target_id = ""
		party.current_order = PartyData.OrderType.NONE
		party.movement_state = PartyData.MovementState.IDLE
		if not is_player:
			party.world_position = Vector2(2700.0, 1800.0)
		party.target_position = party.world_position
	_player.world_position = Vector2(900.0, 1200.0)
	_player.target_position = _player.world_position


func _player_leader_name(party: PartyData, leader: UnitData) -> String:
	if leader != null and not leader.display_name.strip_edges().is_empty():
		return leader.display_name
	return party.party_name


func _count_visible_buttons(root: Node) -> int:
	var count: int = 0
	for node: Node in root.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.visible:
			count += 1
	return count


func _find_panel(node_name: String) -> PanelContainer:
	if _map == null:
		return null
	return _map.find_child(node_name, true, false) as PanelContainer


func _find_party(party_name: String) -> PartyData:
	if _context == null:
		return null
	for party: PartyData in _context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[encui] OK: %s" % message)
	else:
		_failed = true
		push_error("[encui] FAIL: %s" % message)


func _cleanup() -> void:
	GameManager.enter_main_menu()
	TimeManager.stop_session()
	TimeManager.clear_pauses()
