extends Node
## Milestone 1 系统测试。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/milestone1_test.tscn

const TEST_SLOT: String = "__m1_test__"

var _failed: bool = false
var _context: WorldContext = null
var _second_context: WorldContext = null
var _map: Node = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[m1] 测试失败")
		get_tree().quit(1)
	else:
		print("[m1] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)

	_context = WorldContext.new()
	_context.name = "MilestoneTestContextOne"
	add_child(_context)

	_check(WorldInitializer.create_new_world(_context), "新世界初始化成功")
	_check(_context.world_id.begins_with("WORLD_"), "世界 ID 使用 WORLD 前缀")
	_check(_context.world_size == Vector2(3000.0, 2000.0), "世界尺寸为 3000x2000")
	_check(_context.party_manager.get_all_parties().size() == 8, "生成 8 支部队")
	_check(_context.settlement_manager.get_all_settlements().size() == 4, "生成 4 个地点")
	_check(_context.get_player_party() != null, "玩家部队存在")

	var unique_ids: Dictionary = {}
	for party: PartyData in _context.party_manager.get_all_parties():
		unique_ids[party.party_id] = true
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		unique_ids[settlement.settlement_id] = true
	_check(unique_ids.size() == 12, "12 个实体 ID 全部唯一")

	var player := _context.get_player_party()
	var start_position := player.world_position
	_check(_context.world_map_manager.set_party_target(
		player.party_id, start_position + Vector2(200.0, 0.0)
	), "暂停时也可设置移动目标")
	var paused_world_time := TimeManager.world_elapsed_seconds
	await get_tree().create_timer(0.25).timeout
	_check(player.world_position == start_position, "暂停时移动停止")
	_check(
		is_equal_approx(TimeManager.world_elapsed_seconds, paused_world_time),
		"暂停时世界时间不推进"
	)
	_context.world_map_manager.stop_party(player.party_id)

	_check(_context.world_map_manager.set_party_target(
		player.party_id, start_position + Vector2(100.0, 0.0)
	), "玩家可设置移动目标")
	# 大地图实际速度统一为 PartyData.movement_speed 的 0.5 倍；
	# 给足 tick 数以确保走完 100 像素。
	for i: int in range(30):
		_context.world_map_manager.update_party_movement(TimeManager.WORLD_TICK_INTERVAL)
	_check(player.world_position == start_position + Vector2(100.0, 0.0), "玩家到达目标点")
	_check(player.movement_state == PartyData.MovementState.IDLE, "到达后停止移动")

	_context.world_map_manager.set_party_target(player.party_id, Vector2(-200.0, -200.0))
	_check(player.target_position == Vector2.ZERO, "目标点被限制在地图边界内")

	TimeManager.restore_world_time(321.0, TimeManager.SPEED_DOUBLE)
	var save := _context.to_save_data()
	_check(save.world_id == _context.world_id, "存档包含世界 ID")
	_check(save.player_party_id == _context.player_party_id, "存档包含玩家部队 ID")
	_check(save.parties.size() == 8, "存档包含 8 支部队")
	_check(save.settlements.size() == 4, "存档包含 4 个地点")
	_check(save.id_counters.size() > 0, "存档包含 ID 计数器")
	_check(is_equal_approx(save.world_elapsed_seconds, 321.0), "存档包含世界时间")

	_check(SaveManager.save_game(TEST_SLOT, save) == OK, "存档写入成功")
	var info := SaveManager.get_save_info(TEST_SLOT)
	_check(bool(info.get("valid", false)), "存档头信息有效")

	var loaded := SaveManager.load_game(TEST_SLOT)
	_check(loaded != null, "存档读取成功")
	if loaded == null:
		return

	_second_context = WorldContext.new()
	_second_context.name = "MilestoneTestContextTwo"
	add_child(_second_context)
	_check(_second_context.load_from_save_data(loaded), "WorldContext 从存档恢复")
	_check(_second_context.world_id == _context.world_id, "世界 ID 恢复一致")
	_check(_second_context.party_manager.get_all_parties().size() == 8, "部队数量恢复一致")
	_check(_second_context.settlement_manager.get_all_settlements().size() == 4, "地点数量恢复一致")
	_check(
		_second_context.get_player_party().world_position == player.world_position,
		"玩家位置恢复一致"
	)
	_check(
		_second_context.get_player_party().target_position == player.target_position,
		"目标位置恢复一致"
	)
	_check(
		_second_context.get_player_party().movement_state == player.movement_state,
		"移动状态恢复一致"
	)

	for party: PartyData in _context.party_manager.get_all_parties():
		var restored_party := _second_context.party_manager.get_party(party.party_id)
		_check(
			restored_party != null and restored_party.world_position == party.world_position,
			"部队位置恢复一致：%s" % party.party_id
		)

	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		var restored_settlement: SettlementData = _second_context.settlement_manager.get_settlement(
			settlement.settlement_id
		)
		_check(
			restored_settlement != null
			and restored_settlement.world_position == settlement.world_position
			and restored_settlement.display_name == settlement.display_name
			and restored_settlement.settlement_type == settlement.settlement_type,
			"地点数据恢复一致：%s" % settlement.settlement_id
		)

	TimeManager.restore_world_time(loaded.world_elapsed_seconds, loaded.world_base_speed)
	_check(is_equal_approx(TimeManager.world_elapsed_seconds, 321.0), "世界时间恢复")
	_check(
		is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_DOUBLE),
		"时间倍率恢复"
	)

	var old_party_count := _second_context.party_manager.get_all_parties().size()
	var new_party := _second_context.party_manager.create_party(
		"FACTION_TEST", Vector2.ZERO, "测试新部队"
	)
	_check(new_party != null, "读档后可继续创建部队")
	if new_party != null:
		_check(
			_second_context.id_generator.peek_last_value(IdGenerator.PARTY) == old_party_count + 1,
			"读档后 ID 计数器继续递增，不发生冲突"
		)

	var restored_player := _second_context.get_player_party()
	var position_before_resume := restored_player.world_position
	_second_context.world_map_manager.set_party_target(
		restored_player.party_id, position_before_resume + Vector2(60.0, 0.0)
	)
	for i: int in range(5):
		_second_context.world_map_manager.update_party_movement(TimeManager.WORLD_TICK_INTERVAL)
	_check(
		restored_player.world_position != position_before_resume,
		"读档后玩家部队可以继续移动"
	)

	var bad_slot := TEST_SLOT + "_bad"
	var bad_path := SaveManager.get_slot_path(bad_slot)
	var bad_file := FileAccess.open(bad_path, FileAccess.WRITE)
	if bad_file != null:
		bad_file.store_string("{ this is not valid json")
		bad_file.close()
		var bad_info := SaveManager.get_save_info(bad_slot)
		_check(
			bad_info.is_empty() or not bool(bad_info.get("valid", false)),
			"损坏存档不会进入有效存档列表"
		)
		_remove_if_exists(bad_path)

	var second_save := _second_context.to_save_data()
	_check(SaveManager.save_game(TEST_SLOT, second_save) == OK, "同一槽位可安全覆盖保存")

	remove_child(_second_context)
	_second_context.free()
	_second_context = null

	# 商队初始在橡木村；本测试会在橡木村附近测试地点面板，先移开避免部队对话抢占。
	for party: PartyData in _context.party_manager.get_all_parties():
		if party.party_name == WorldInitializer.TEST_ENEMY_PARTY_NAME:
			party.world_position = Vector2(900.0, 1500.0)
			party.target_position = party.world_position
			party.movement_state = PartyData.MovementState.IDLE
			break

	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)

	var packed_map := load("res://Scenes/WorldMap/world_map.tscn") as PackedScene
	_map = packed_map.instantiate()
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame

	var entities := _map.get_node("WorldEntities") as Node2D
	_check(entities.get_child_count() == 12, "大地图生成 8 个部队图标与 4 个地点图标")
	_check(_map.find_child("TopBar", true, false) != null, "大地图时间 UI 已生成")
	_check(_map.find_child("SettlementPanel", true, false) != null, "地点交互面板已生成")

	player.world_position = Vector2(500.0, 470.0)
	player.target_position = player.world_position
	player.movement_state = PartyData.MovementState.IDLE
	await get_tree().process_frame
	await get_tree().process_frame

	var settlement_panel := _map.find_child("SettlementPanel", true, false) as PanelContainer
	_check(settlement_panel != null and not settlement_panel.visible,
		"到达地点附近不会自动打开交互面板")
	_map.call("handle_left_click", player.world_position)
	await get_tree().process_frame
	_check(settlement_panel != null and settlement_panel.visible, "主动点击地点后打开交互面板")
	_check(is_zero_approx(TimeManager.get_effective_world_scale()), "打开地点面板后世界暂停")
	_check(player.movement_state == PartyData.MovementState.IDLE, "打开地点面板后停止移动")

	var leave_button := _map.find_child("SettlementLeaveButton", true, false) as Button
	_check(leave_button != null, "地点面板包含离开按钮")
	if leave_button != null:
		leave_button.pressed.emit()
		await get_tree().process_frame
		_check(not settlement_panel.visible, "离开地点后关闭面板")
		_check(is_zero_approx(TimeManager.get_effective_world_scale()), "离开地点后仍保持暂停")
		_check(
			is_zero_approx(TimeManager.get_base_world_speed()),
			"离开地点不会自动恢复基础倍率"
		)

	var pause_button := _map.find_child("PauseButton", true, false) as Button
	var speed_one_button := _map.find_child("SpeedOneButton", true, false) as Button
	var speed_two_button := _map.find_child("SpeedTwoButton", true, false) as Button
	_check(
		pause_button != null and speed_one_button != null and speed_two_button != null,
		"暂停/1x/2x 时间按钮已生成"
	)
	if pause_button != null and speed_one_button != null and speed_two_button != null:
		_click_toggle(pause_button)
		_check(
			pause_button.button_pressed
			and is_zero_approx(TimeManager.get_effective_world_scale()),
			"暂停按钮与 UI 状态一致"
		)
		_click_toggle(pause_button)
		_check(
			pause_button.button_pressed
			and is_zero_approx(TimeManager.get_effective_world_scale()),
			"重复点击暂停不会造成 UI/倍率不一致"
		)
		_click_toggle(speed_one_button)
		_check(
			speed_one_button.button_pressed
			and is_equal_approx(TimeManager.get_effective_world_scale(), TimeManager.SPEED_NORMAL),
			"1x 按钮正确切换并同步 UI"
		)
		_click_toggle(speed_two_button)
		_check(
			speed_two_button.button_pressed
			and is_equal_approx(TimeManager.get_effective_world_scale(), TimeManager.SPEED_DOUBLE),
			"2x 按钮正确切换并同步 UI"
		)

	var save_button := _map.find_child("SaveButton", true, false) as Button
	var save_panel := _map.find_child("SavePanel", true, false) as PanelContainer
	_check(save_button != null and save_panel != null, "大地图保存面板已生成")
	if save_button != null and save_panel != null:
		save_button.pressed.emit()
		await get_tree().process_frame
		_check(save_panel.visible, "保存按钮打开保存面板")
		_check(is_zero_approx(TimeManager.get_effective_world_scale()), "保存面板打开时暂停")
		var close_save := _map.find_child("CloseSaveButton", true, false) as Button
		if close_save != null:
			close_save.pressed.emit()
			await get_tree().process_frame
		_check(not save_panel.visible, "保存面板可关闭")
		_check(
			is_equal_approx(TimeManager.get_effective_world_scale(), TimeManager.SPEED_DOUBLE),
			"关闭保存面板后恢复原有倍率"
		)

	_check(GameManager.save_game(TEST_SLOT) == OK, "GameManager 聚合当前世界并保存")


func _click_toggle(button: Button) -> void:
	button.button_pressed = not button.button_pressed
	button.pressed.emit()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[m1] OK: %s" % message)
	else:
		_failed = true
		push_error("[m1] FAIL: %s" % message)


func _cleanup() -> void:
	if _map != null and is_instance_valid(_map):
		_map.free()
		_map = null
	if _second_context != null and is_instance_valid(_second_context):
		_second_context.free()
		_second_context = null

	GameManager.world_context = null
	GameManager.player_party_id = ""
	TimeManager.stop_session()
	SaveManager.delete_save(TEST_SLOT)
	_remove_if_exists(SaveManager.get_slot_path(TEST_SLOT) + ".bak")
	_remove_if_exists(SaveManager.get_slot_path(TEST_SLOT) + ".tmp")
	_remove_if_exists(SaveManager.get_slot_path(TEST_SLOT + "_bad"))


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
