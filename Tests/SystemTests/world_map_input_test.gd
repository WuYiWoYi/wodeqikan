extends Node
## 大地图输入测试：数字键时间控制、UI 暂停保护、点击移动目标后切 1x。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/world_map_input_test.tscn

var _failed: bool = false
var _context: WorldContext = null
var _map: Node = null
var _player: PartyData = null
var _enemy: PartyData = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[input] 测试失败")
		get_tree().quit(1)
	else:
		print("[input] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)

	_context = WorldContext.new()
	_context.name = "InputTestContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")

	_player = _context.get_player_party()
	_enemy = _find_party_by_name(WorldInitializer.TEST_ENEMY_PARTY_NAME)
	_check(_player != null and _enemy != null, "玩家与敌方部队存在")
	if _player == null or _enemy == null:
		return
	_check(
		is_equal_approx(_player.movement_speed, 150.0),
		"新游戏玩家速度为 150"
	)
	_check(
		is_equal_approx(_enemy.movement_speed, WorldInitializer.MERCHANT_MOVE_SPEED),
		"商队移动速度为 80"
	)
	var guard_party := _find_party_by_name(WorldInitializer.GUARD_PARTY_NAME)
	var bandit_party := _find_party_by_name(WorldInitializer.BANDIT_PARTY_NAME)
	_check(
		guard_party != null
		and is_equal_approx(guard_party.movement_speed, WorldInitializer.GUARD_MOVE_SPEED),
		"治安队移动速度为 120"
	)
	_check(
		bandit_party != null
		and is_equal_approx(bandit_party.movement_speed, WorldInitializer.BANDIT_MOVE_SPEED),
		"强盗移动速度为 100"
	)

	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id

	var packed_map := load("res://Scenes/WorldMap/world_map.tscn") as PackedScene
	_map = packed_map.instantiate()
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame

	_test_time_keys()
	await _test_save_panel_blocks_input()
	await _test_party_dialogue_blocks_input()
	_test_follow_party()
	await _test_map_click_speed()
	_test_pause_tip_state()
	_test_single_double_click()
	_test_arrival_auto_pause()
	await _test_camera_controls()
	await _test_npc_runtime_movement()


func _test_time_keys() -> void:
	TimeManager.clear_pauses()

	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	_send_key(KEY_2)
	_check(
		is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_NORMAL),
		"顶部数字键 2 切换到 1x"
	)

	_send_key(KEY_3)
	_check(
		is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_DOUBLE),
		"顶部数字键 3 切换到 2x"
	)

	_send_key(KEY_1)
	_check(
		is_zero_approx(TimeManager.get_base_world_speed()),
		"顶部数字键 1 暂停"
	)

	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)
	_send_key(KEY_KP_3)
	_check(
		is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_NORMAL),
		"数字小键盘不触发快捷时间"
	)

	_send_key(KEY_3, true, true)
	_check(
		is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_NORMAL),
		"按住数字键的 echo 不重复触发"
	)

	_send_key(KEY_3, false)
	_check(
		is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_NORMAL),
		"按键释放事件不触发"
	)

	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)


func _test_save_panel_blocks_input() -> void:
	TimeManager.set_base_world_speed(TimeManager.SPEED_DOUBLE)
	var save_button := _map.find_child("SaveButton", true, false) as Button
	_check(save_button != null, "保存按钮存在")
	if save_button == null:
		return
	save_button.pressed.emit()
	await get_tree().process_frame

	_send_key(KEY_1)
	_check(
		is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_DOUBLE),
		"保存面板打开时快捷键不改变基础倍率"
	)
	_check(is_zero_approx(TimeManager.get_effective_world_scale()), "保存面板暂停保持")
	_check(
		not bool(_map.call("request_player_move", Vector2(800.0, 700.0))),
		"保存面板打开时地图点击不设置目标"
	)

	var close_button := _map.find_child("CloseSaveButton", true, false) as Button
	if close_button != null:
		close_button.pressed.emit()
		await get_tree().process_frame
	_check(
		is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_DOUBLE),
		"关闭保存面板后基础倍率不变"
	)
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)


func _test_party_dialogue_blocks_input() -> void:
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)
	# 商队初始位于橡木村；移到远离地点的空地，避免地点面板抢占对话。
	_enemy.world_position = Vector2(900.0, 1500.0)
	_enemy.target_position = _enemy.world_position
	_enemy.movement_state = PartyData.MovementState.IDLE
	_player.world_position = _enemy.world_position + Vector2(-20.0, 0.0)
	_player.target_position = _player.world_position
	_player.movement_state = PartyData.MovementState.IDLE
	# 新规则：需要玩家主动点击/选择目标部队才会自动打开普通对话。
	_player.focus_party_id = _enemy.party_id
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var panel := _map.find_child("PartyDialoguePanel", true, false) as PanelContainer
	_check(panel != null and panel.visible, "接近部队后打开对话")
	if panel == null or not panel.visible:
		return

	_send_key(KEY_3)
	_check(
		is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_NORMAL),
		"部队对话打开时快捷键不改变基础倍率"
	)
	_check(is_zero_approx(TimeManager.get_effective_world_scale()), "部队对话暂停保持")
	_check(
		not bool(_map.call("request_player_move", Vector2(800.0, 700.0))),
		"部队对话打开时地图点击不设置目标"
	)

	var leave_button := _map.find_child("PartyLeaveButton", true, false) as Button
	if leave_button != null:
		leave_button.pressed.emit()
		await get_tree().process_frame
	_check(not panel.visible, "离开后关闭部队对话")
	_check(
		is_equal_approx(TimeManager.get_effective_world_scale(), TimeManager.SPEED_NORMAL),
		"离开对话后恢复原基础倍率"
	)

	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	_player.world_position = Vector2(760.0, 620.0)
	_player.target_position = _player.world_position
	_player.movement_state = PartyData.MovementState.IDLE
	await get_tree().process_frame
	await get_tree().process_frame


func _test_follow_party() -> void:
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	var manager := _context.world_map_manager
	_player.world_position = Vector2(900.0, 1200.0)
	_player.target_position = _player.world_position
	_player.movement_state = PartyData.MovementState.IDLE
	_player.current_order = PartyData.OrderType.NONE
	_player.current_target_id = ""
	_enemy.world_position = Vector2(1000.0, 1200.0)
	_enemy.target_position = Vector2(1400.0, 1200.0)
	_enemy.movement_state = PartyData.MovementState.MOVING
	_enemy.battle_state = PartyData.BattleState.AVAILABLE
	# 关闭目标自身移动，单独验证跟随目标读取其最新坐标。
	_enemy.movement_speed = 0.0

	_check(
		bool(_map.call("request_player_follow", _enemy.party_id)),
		"点击移动中的部队进入跟随"
	)
	_check(
		_player.current_order == PartyData.OrderType.FOLLOW_PARTY,
		"玩家指令切换为跟随"
	)
	_check(_player.current_target_id == _enemy.party_id, "记录被跟随部队 ID")
	_check(
		is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_NORMAL),
		"跟随指令把基础倍率切为 1x"
	)

	manager.update_party_movement(0.5)
	_check(
		_player.target_position == _enemy.world_position,
		"跟随目标读取目标最新位置"
	)
	_enemy.world_position = Vector2(1100.0, 1200.0)
	manager.update_party_movement(0.5)
	_check(
		_player.target_position == Vector2(1100.0, 1200.0),
		"目标移动后跟随目标持续更新"
	)

	# 目标离开玩家视野：主动点击的追击不应中断（地图图标始终可见）。
	_enemy.world_position = Vector2(1600.0, 1200.0)
	manager.update_party_movement(0.5)
	_check(
		_player.current_order == PartyData.OrderType.FOLLOW_PARTY,
		"目标离开视野后仍保持主动跟随"
	)
	_check(
		_player.target_position == Vector2(1600.0, 1200.0),
		"视野外目标仍更新跟随坐标"
	)

	# 目标进入战斗。
	_player.world_position = Vector2(900.0, 1200.0)
	_enemy.world_position = Vector2(1000.0, 1200.0)
	_check(bool(_map.call("request_player_follow", _enemy.party_id)), "重新进入跟随")
	_enemy.battle_state = PartyData.BattleState.IN_BATTLE
	manager.update_party_movement(0.5)
	_check(
		_player.current_order == PartyData.OrderType.FOLLOW_PARTY,
		"目标进入战斗后保留追击关系"
	)
	_check(
		_player.movement_state == PartyData.MovementState.IDLE,
		"目标战斗中追击方原地等待"
	)
	_enemy.battle_state = PartyData.BattleState.AVAILABLE
	_enemy.target_position = _enemy.world_position
	_enemy.movement_state = PartyData.MovementState.IDLE
	manager.update_party_movement(0.5)
	_check(
		_player.movement_state == PartyData.MovementState.MOVING
			and _player.current_order == PartyData.OrderType.FOLLOW_PARTY,
		"目标战斗结束后自动恢复跟随"
	)
	_enemy.battle_state = PartyData.BattleState.DISABLED
	manager.update_party_movement(0.5)
	_check(
		_player.current_order != PartyData.OrderType.FOLLOW_PARTY,
		"目标失效后清理追击关系"
	)
	_enemy.battle_state = PartyData.BattleState.AVAILABLE

	# 追上目标。
	_player.world_position = Vector2(900.0, 1200.0)
	_enemy.world_position = Vector2(1000.0, 1200.0)
	_check(bool(_map.call("request_player_follow", _enemy.party_id)), "再次进入跟随")
	_player.world_position = _enemy.world_position + Vector2(5.0, 0.0)
	manager.update_party_movement(0.5)
	_check(
		_player.current_order != PartyData.OrderType.FOLLOW_PARTY,
		"追上目标后结束跟随"
	)

	# 新指令取消旧跟随。
	_player.world_position = Vector2(900.0, 1200.0)
	_enemy.world_position = Vector2(1000.0, 1200.0)
	_check(bool(_map.call("request_player_follow", _enemy.party_id)), "跟随用于取消测试")
	_check(
		_request_move(Vector2(850.0, 1150.0)),
		"跟随期间仍可下达普通移动"
	)
	_check(_player.current_order == PartyData.OrderType.MOVE, "普通移动覆盖跟随指令")
	_check(_player.current_target_id.is_empty(), "普通移动清除跟随目标")

	# 点击分发：移动中/静止部队都进入跟随，避免目标在接近途中移动后丢失。
	_player.world_position = Vector2(900.0, 1200.0)
	_enemy.world_position = Vector2(1000.0, 1200.0)
	_enemy.movement_state = PartyData.MovementState.MOVING
	_check(
		bool(_map.call("request_party_command", _enemy.party_id)),
		"点击移动中的部队下达跟随"
	)
	_check(_player.current_order == PartyData.OrderType.FOLLOW_PARTY, "点击移动部队进入跟随")
	_enemy.movement_state = PartyData.MovementState.IDLE
	_check(
		bool(_map.call("request_party_command", _enemy.party_id)),
		"点击静止部队同样下达跟随"
	)
	_check(_player.current_order == PartyData.OrderType.FOLLOW_PARTY, "点击静止部队进入跟随")
	_check(_player.current_target_id == _enemy.party_id, "静止部队也记录跟随目标")

	manager.stop_party(_player.party_id)
	_player.world_position = Vector2(760.0, 620.0)
	_player.target_position = _player.world_position
	_player.movement_state = PartyData.MovementState.IDLE
	_enemy.world_position = Vector2(900.0, 1500.0)
	_enemy.target_position = _enemy.world_position
	_enemy.movement_state = PartyData.MovementState.IDLE
	_enemy.movement_speed = WorldInitializer.MERCHANT_MOVE_SPEED
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)


func _test_map_click_speed() -> void:
	TimeManager.clear_pauses()
	_player.world_position = Vector2(760.0, 620.0)
	_player.target_position = _player.world_position
	_player.movement_state = PartyData.MovementState.IDLE

	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	_check(_request_move(Vector2(900.0, 700.0)), "暂停时点击地图可设置移动目标")
	_check(
		is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_NORMAL),
		"暂停时点击地图切换到 1x"
	)
	_check(
		_player.movement_state == PartyData.MovementState.MOVING,
		"点击后玩家部队开始移动"
	)
	_stop_player()

	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)
	_check(_request_move(Vector2(900.0, 700.0)), "1x 时点击地图可设置移动目标")
	_check(
		is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_NORMAL),
		"1x 时点击地图保持 1x"
	)
	_stop_player()

	TimeManager.set_base_world_speed(TimeManager.SPEED_DOUBLE)
	_check(_request_move(Vector2(900.0, 700.0)), "2x 时点击地图可设置移动目标")
	_check(
		is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_NORMAL),
		"2x 时点击地图切换到 1x"
	)
	_stop_player()

	TimeManager.set_base_world_speed(TimeManager.SPEED_DOUBLE)
	_player.battle_state = PartyData.BattleState.IN_BATTLE
	_check(not _request_move(Vector2(900.0, 700.0)), "不可用部队设置目标失败")
	_check(
		is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_DOUBLE),
		"设置目标失败不改变倍率"
	)
	_player.battle_state = PartyData.BattleState.AVAILABLE

	_check(not _request_move(Vector2(-10.0, -10.0)), "地图外点击不设置目标")
	_check(
		is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_DOUBLE),
		"地图外点击不改变倍率"
	)

	TimeManager.push_pause(&"input_test_hold")
	_check(_request_move(Vector2(900.0, 700.0)), "存在其他暂停原因时仍可设置目标")
	_check(
		is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_NORMAL),
		"设置目标后基础倍率切为 1x"
	)
	_check(
		is_zero_approx(TimeManager.get_effective_world_scale()),
		"其他暂停原因仍使有效时间保持暂停"
	)
	TimeManager.pop_pause(&"input_test_hold")
	_check(
		is_equal_approx(TimeManager.get_effective_world_scale(), TimeManager.SPEED_NORMAL),
		"移除其他暂停后恢复 1x"
	)
	_stop_player()

	TimeManager.set_base_world_speed(TimeManager.SPEED_DOUBLE)
	var save_button := _map.find_child("SaveButton", true, false) as Button
	if save_button != null:
		save_button.pressed.emit()
		await get_tree().process_frame
	_check(not _request_move(Vector2(900.0, 700.0)), "保存面板打开时点击失败")
	_check(
		is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_DOUBLE),
		"保存面板打开时点击不改变倍率"
	)
	var close_button := _map.find_child("CloseSaveButton", true, false) as Button
	if close_button != null:
		close_button.pressed.emit()
		await get_tree().process_frame
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)


func _test_pause_tip_state() -> void:
	var tip := _map.find_child("WorldPausedTip", true, false) as Label
	_check(tip != null, "存在暂停提示")
	if tip == null:
		return
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	_check(tip.visible and tip.text.contains("已暂停"), "暂停时显示已暂停提示")
	_check(
		tip.get_theme_color("font_color") == Color("#D97706"),
		"暂停提示使用琥珀色"
	)
	var tip_font := tip.get_theme_font("font") as FontVariation
	_check(
		tip_font != null and tip_font.variation_embolden > 0.0,
		"暂停提示使用半粗体"
	)

	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)
	_check(not tip.visible, "世界运行时隐藏暂停提示")

	# 其他暂停原因（例如 UI 面板）同样来自实际 TimeManager 状态。
	TimeManager.push_pause(&"input_test_tip")
	_check(tip.visible, "其他暂停原因也显示暂停提示")
	TimeManager.pop_pause(&"input_test_tip")
	_check(not tip.visible, "移除暂停原因后隐藏提示")
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)


func _test_single_double_click() -> void:
	TimeManager.clear_pauses()
	_stop_player()
	_player.world_position = Vector2(760.0, 620.0)
	_player.target_position = _player.world_position
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)

	# 单击：双击窗口结束前不执行，窗口结束后切 1x。
	_map.call("_queue_map_click", Vector2(900.0, 700.0))
	_check(
		is_zero_approx(TimeManager.get_base_world_speed()),
		"第一次点击先等待双击判定，不立即切换倍率"
	)
	# 大于脚本内 0.28 秒的双击窗口。
	_map.call("_update_pending_map_click", 0.3)
	_check(
		is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_NORMAL),
		"单击地图切换到 1x"
	)
	_check(
		_player.movement_state == PartyData.MovementState.MOVING,
		"单击地图下达移动指令"
	)

	_stop_player()
	_player.world_position = Vector2(760.0, 620.0)
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)
	_map.call("_queue_map_click", Vector2(900.0, 700.0))
	_map.call("_queue_map_click", Vector2(900.0, 700.0))
	_check(
		is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_DOUBLE),
		"同一位置双击切换到 2x"
	)
	_check(
		_player.movement_state == PartyData.MovementState.MOVING,
		"双击仍然只通过统一入口下达移动"
	)
	_stop_player()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)


func _test_arrival_auto_pause() -> void:
	TimeManager.clear_pauses()
	_stop_player()
	_player.world_position = Vector2(1000.0, 1200.0)
	_player.target_position = Vector2(1004.0, 1200.0)
	_player.movement_state = PartyData.MovementState.MOVING
	_player.current_order = PartyData.OrderType.MOVE
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)

	# 尚未到达时不暂停。
	_enemy.world_position = Vector2(2600.0, 1800.0)
	_enemy.target_position = _enemy.world_position
	_enemy.movement_state = PartyData.MovementState.IDLE
	_context.world_map_manager.update_party_movement(0.01)
	_check(
		is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_NORMAL),
		"到达前不自动暂停"
	)

	_context.world_map_manager.update_party_movement(1.0)
	_check(
		_player.world_position == _player.target_position,
		"玩家部队真正到达目标"
	)
	# 移动逻辑在下一步 tick 判定到达，复用既有到达检测。
	_context.world_map_manager.update_party_movement(0.01)
	_check(
		is_zero_approx(TimeManager.get_base_world_speed()),
		"玩家到达指定目标后自动暂停"
	)

	# NPC 到达不触发玩家暂停。
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)
	_stop_player()
	var npc := _find_party_by_name(WorldInitializer.GUARD_PARTY_NAME)
	_check(npc != null, "找到用于到达测试的 NPC 部队")
	if npc != null:
		npc.world_position = Vector2(2300.0, 1100.0)
		npc.target_position = Vector2(2304.0, 1100.0)
		npc.movement_state = PartyData.MovementState.MOVING
		npc.current_order = PartyData.OrderType.MOVE
		_context.world_map_manager.update_party_movement(1.0)
		_context.world_map_manager.update_party_movement(0.01)
		_check(
			npc.world_position == npc.target_position,
			"NPC 到达自身目标"
		)
		_check(
			is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_NORMAL),
			"NPC 到达不会暂停玩家世界"
		)
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)


## WASD 自由镜头：四方向平移、停止跟随、点击地图/部队恢复跟随、缩放速度与边界。
func _test_camera_controls() -> void:
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	var cam := _map.get("camera") as Camera2D
	_check(cam != null, "大地图相机存在")
	if cam == null:
		return
	cam.zoom = Vector2(1.0, 1.0)

	_player.world_position = Vector2(2500.0, 1500.0)
	_player.target_position = _player.world_position
	_player.movement_state = PartyData.MovementState.IDLE
	cam.position = _player.world_position
	_check(bool(_map.call("request_player_move", Vector2(2600.0, 1500.0))), "下达移动指令")
	_check(
		str(_map.call("get_camera_mode_name")) == "FOLLOW_PLAYER",
		"移动指令后镜头跟随玩家"
	)

	# 四个方向：W 上、A 左、S 下、D 右。
	var direction_cases: Array = [
		[Vector2.UP, "W 镜头向上"],
		[Vector2.LEFT, "A 镜头向左"],
		[Vector2.DOWN, "S 镜头向下"],
		[Vector2.RIGHT, "D 镜头向右"],
	]
	for case: Array in direction_cases:
		var direction: Vector2 = case[0]
		cam.position = Vector2(2500.0, 1500.0)
		var before := cam.position
		cam.zoom = Vector2(1.0, 1.0)
		_map.call("pan_camera", direction, 0.5)
		var delta := cam.position - before
		_check(
			delta.normalized().dot(direction) > 0.99,
			str(case[1])
		)
	_check(bool(_map.call("is_free_camera")), "按 WASD 后进入自由镜头")

	# 玩家部队继续移动，自由镜头不被拉回。
	cam.position = Vector2(2500.0, 1500.0)
	var free_position := cam.position
	_player.world_position += Vector2(300.0, 0.0)
	_map.call("_update_camera", 0.5)
	_check(
		cam.position.distance_to(free_position) < 0.01,
		"自由镜头期间玩家移动不会拉回镜头"
	)

	# 点击地图下达新移动指令后恢复跟随。
	_check(
		bool(_map.call("request_player_move", _player.world_position + Vector2(8.0, 0.0))),
		"自由镜头下仍可点击地图移动"
	)
	_check(str(_map.call("get_camera_mode_name")) == "FOLLOW_PLAYER", "点击地图恢复跟随")
	for i: int in range(12):
		_map.call("_update_camera", 0.2)
	_check(
		cam.position.distance_to(_player.world_position) < 40.0,
		"恢复跟随后镜头平滑回到玩家附近"
	)

	# 点击部队开始跟随同样恢复跟随。
	cam.position = Vector2(1000.0, 800.0)
	_map.call("pan_camera", Vector2.RIGHT, 0.2)
	_enemy.battle_state = PartyData.BattleState.AVAILABLE
	_check(
		bool(_map.call("request_player_follow", _enemy.party_id)),
		"自由镜头下点击部队开始跟随"
	)
	_check(str(_map.call("get_camera_mode_name")) == "FOLLOW_PLAYER", "点击部队恢复跟随")

	# 缩放后世界平移速度按比例变化，屏幕观感接近一致。
	cam.zoom = Vector2(1.0, 1.0)
	cam.position = Vector2(2500.0, 1500.0)
	_map.call("pan_camera", Vector2.RIGHT, 0.5)
	var world_step_1x: float = cam.position.x - 2500.0
	cam.zoom = Vector2(2.0, 2.0)
	cam.position = Vector2(2500.0, 1500.0)
	_map.call("pan_camera", Vector2.RIGHT, 0.5)
	var world_step_2x: float = cam.position.x - 2500.0
	_check(world_step_1x > 0.0, "1 倍缩放平移有效")
	_check(
		is_equal_approx(world_step_1x, world_step_2x * 2.0),
		"2 倍缩放时世界平移速度按比例降低"
	)

	# 边界限制。
	var clamped: Vector2 = _map.call(
		"_clamp_camera_position", Vector2(99999.0, 99999.0)
	)
	_check(
		clamped.x < 99999.0 and clamped.y < 99999.0,
		"自由镜头不能移出地图边界"
	)

	# UI 打开时 WASD 不移动镜头。
	TimeManager.set_base_world_speed(TimeManager.SPEED_DOUBLE)
	cam.zoom = Vector2(1.0, 1.0)
	cam.position = Vector2(2500.0, 1500.0)
	var save_button := _map.find_child("SaveButton", true, false) as Button
	if save_button != null:
		save_button.pressed.emit()
		await get_tree().process_frame
	var blocked_before := cam.position
	var moved_while_blocked: bool = bool(
		_map.call("_apply_camera_input", 0.5, Vector2.RIGHT)
	)
	_check(not moved_while_blocked, "UI 打开时忽略镜头平移输入")
	_check(cam.position == blocked_before, "UI 打开时镜头位置不变")
	var close_button := _map.find_child("CloseSaveButton", true, false) as Button
	if close_button != null:
		close_button.pressed.emit()
		await get_tree().process_frame
	# 清理相机测试留下的跟随指令，避免影响后续 NPC 移动测试。
	_context.world_map_manager.stop_party(_player.party_id)
	_player.focus_party_id = ""
	_player.world_position = Vector2(760.0, 620.0)
	_player.target_position = _player.world_position
	_player.movement_state = PartyData.MovementState.IDLE
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)


func _test_npc_runtime_movement() -> void:
	var patrol := _find_party_by_name("北境巡逻队")
	_check(patrol != null, "北境巡逻队存在")
	if patrol == null:
		return

	TimeManager.clear_pauses()
	_player.world_position = Vector2(760.0, 620.0)
	_player.target_position = _player.world_position
	_player.movement_state = PartyData.MovementState.IDLE
	var player_start := _player.world_position
	var enemy_start := _enemy.world_position
	var patrol_start := patrol.world_position

	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)
	await get_tree().create_timer(1.3).timeout
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)

	_check(
		_enemy.world_position.distance_to(enemy_start) > 1.0,
		"商队由 WorldTime tick 驱动移动"
	)
	_check(
		patrol.world_position.distance_to(patrol_start) > 1.0,
		"巡逻队由 WorldTime tick 驱动移动"
	)
	_check(
		_player.world_position.distance_to(player_start) < 0.01,
		"NPC AI 不修改玩家位置"
	)


func _request_move(target: Vector2) -> bool:
	return bool(_map.call("request_player_move", target))


func _stop_player() -> void:
	_context.world_map_manager.stop_party(_player.party_id)


func _send_key(keycode: int, pressed: bool = true, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	event.echo = echo
	_map._unhandled_input(event)


func _find_party_by_name(party_name: String) -> PartyData:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[input] OK: %s" % message)
	else:
		_failed = true
		push_error("[input] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_map):
		_map.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
