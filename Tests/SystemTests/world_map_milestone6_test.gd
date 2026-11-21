extends Node
## 阶段 6 大地图测试：时间 UI、人数图标、悬浮面板、追逐时禁止无关自动交互。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/world_map_milestone6_test.tscn

var _failed: bool = false
var _context: WorldContext = null
var _map: Node = null
var _player: PartyData = null
var _merchant: PartyData = null
var _guard: PartyData = null
var _village: SettlementData = null
var _castle: SettlementData = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[wm6] 测试失败")
		get_tree().quit(1)
	else:
		print("[wm6] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	TimeManager.world_elapsed_seconds = 0.0

	_context = WorldContext.new()
	_context.name = "WorldMapM6Context"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return
	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id

	_player = _context.get_player_party()
	_merchant = _find_party("河畔商队")
	_guard = _find_party("北境巡逻队")
	_village = _find_settlement("橡木村")
	_castle = _find_settlement("灰石城堡")
	_check(_player != null and _merchant != null and _guard != null, "找到测试部队")
	_check(_village != null and _castle != null, "找到测试地点")
	if _player == null or _merchant == null or _guard == null:
		return

	var packed := load("res://Scenes/WorldMap/world_map.tscn") as PackedScene
	_map = packed.instantiate()
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame

	_test_time_ui()
	_test_party_icon_counts()
	_test_hover_panel()
	await _test_icon_count_updates()
	_test_chase_suppression()


func _test_time_ui() -> void:
	var label := _map.find_child("TopBar", true, false)
	_check(label != null, "大地图顶栏存在")
	var time_label := _find_label_with_prefix(_map, "世界时间")
	_check(time_label != null, "顶栏显示世界时间")
	if time_label == null:
		return
	_check(time_label.text.contains("1103 年 1 月 1 日"), "新游戏日期 1103 年 1 月 1 日")
	_check(time_label.text.contains("深夜"), "新游戏时间段为深夜")
	_check(not time_label.text.contains("00:00"), "大地图不显示小时和分钟")
	_check(time_label.text.contains("倍率：暂停"), "显示暂停倍率")


func _test_party_icon_counts() -> void:
	for party: PartyData in _context.party_manager.get_all_parties():
		var icon := _map.find_child("PartyIcon_%s" % party.party_id, true, false) as PartyIcon
		_check(icon != null, "部队存在图标: %s" % party.party_name)
		if icon == null:
			continue
		_check(icon.get_count_text() == str(party.member_unit_ids.size()),
			"图标只显示人数: %s" % party.party_name)
		_check(icon.find_child("NameLabel", true, false) == null,
			"图标不再显示部队名称: %s" % party.party_name)


func _test_hover_panel() -> void:
	_map.call("apply_hover_for_test", _merchant.world_position)
	_check(_map.call("is_hover_panel_visible") == true, "悬浮部队图标显示信息面板")
	var text: String = str(_map.call("get_hover_panel_text"))
	_check(text.contains(_merchant.party_name), "悬浮面板显示部队名称")
	_check(text.contains("民兵（3）"), "悬浮面板合并显示民兵数量")
	_check(text.contains("职业步兵（2）"), "悬浮面板显示士兵类型")

	_map.call("apply_hover_for_test", _player.world_position)
	text = str(_map.call("get_hover_panel_text"))
	_check(text.contains("骑马职业步兵（3）"), "骑马与步兵分开统计")
	_check(text.contains("玩家角色（1）"), "玩家角色单独显示")

	_map.call("clear_hover_for_test")
	_check(_map.call("is_hover_panel_visible") == false, "鼠标离开后悬浮面板关闭")


func _test_icon_count_updates() -> void:
	var member_id: String = _guard.member_unit_ids[0]
	var before: int = _guard.member_unit_ids.size()
	_check(_context.party_manager.remove_member(_guard.party_id, member_id),
		"移除一名部队成员")
	await get_tree().process_frame
	var icon := _map.find_child(
		"PartyIcon_%s" % _guard.party_id, true, false
	) as PartyIcon
	_check(icon != null and icon.get_count_text() == str(before - 1),
		"人数变化后图标数字同步更新")


func _test_chase_suppression() -> void:
	if _village == null or _guard == null:
		return

	# 玩家主动追逐时，经过村庄不打开地点面板。
	_player.world_position = _village.world_position
	_player.focus_party_id = _merchant.party_id
	_player.movement_state = PartyData.MovementState.MOVING
	_player.target_position = _village.world_position + Vector2(600.0, 0.0)
	_map.call("_check_settlement_interaction")
	var settlement_panel := _map.find_child("SettlementPanel", true, false) as PanelContainer
	_check(settlement_panel != null and not settlement_panel.visible,
		"追逐中经过村庄不打开地点界面")

	# 路过无关友方部队也不打断追逐。
	_guard.world_position = _player.world_position
	_map.call("_check_party_interaction")
	var party_panel := _map.find_child("PartyDialoguePanel", true, false) as PanelContainer
	_check(party_panel != null and not party_panel.visible,
		"追逐中路过无关部队不打开对话")

	# 到达目标后恢复正常自动交互。
	_player.focus_party_id = ""
	_player.movement_state = PartyData.MovementState.IDLE
	_map.call("_check_settlement_interaction")
	_check(settlement_panel.visible, "停止追逐后主动接近村庄仍可打开面板")
	if settlement_panel.visible:
		var enter_button := _map.find_child(
			"SettlementEnterButton", true, false
		) as Button
		_check(enter_button != null and enter_button.visible, "村庄面板提供进入村庄入口")
		_check(_village.scene_path == "res://Scenes/Village/village.tscn",
			"村庄关联独立场景配置")
		_check(_castle.scene_path.is_empty(), "城堡暂不关联小场景")
		var leave_button := _map.find_child(
			"SettlementLeaveButton", true, false
		) as Button
		if leave_button != null:
			leave_button.pressed.emit()

	# 主动接近其他部队仍保留原对话逻辑。
	_player.focus_party_id = ""
	_player.movement_state = PartyData.MovementState.IDLE
	_guard.world_position = _player.world_position
	_map.call("_check_party_interaction")
	_check(party_panel.visible, "无追逐时主动接近部队打开对话")
	if party_panel.visible:
		var leave_button := _map.find_child(
			"PartyLeaveButton", true, false
		) as Button
		if leave_button != null:
			leave_button.pressed.emit()


func _find_label_with_prefix(root: Node, prefix: String) -> Label:
	for child: Node in root.find_children("*", "Label", true, false):
		var label := child as Label
		if label != null and label.text.begins_with(prefix):
			return label
	return null


func _find_party(party_name: String) -> PartyData:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _find_settlement(display_name: String) -> SettlementData:
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement.display_name == display_name:
			return settlement
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[wm6] OK: %s" % message)
	else:
		_failed = true
		push_error("[wm6] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_map):
		_map.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
