extends Node
## 大地图移动目标标记与动态虚线测试：
## 点击设置/更新目标、起点跟随部队、抵达或停止后清理、镜头变化不改变世界坐标。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/world_map_move_target_test.tscn

var _failed: bool = false
var _context: WorldContext = null
var _map: Node = null
var _player: PartyData = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[movetarget] 测试失败")
		get_tree().quit(1)
	else:
		print("[movetarget] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)

	_context = WorldContext.new()
	_context.name = "MoveTargetGuideContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	_player = _context.get_player_party()
	_check(_player != null, "玩家部队存在")
	if _player == null:
		return

	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id

	var packed_map := load("res://Scenes/WorldMap/world_map.tscn") as PackedScene
	_map = packed_map.instantiate()
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame

	var guide = _map.call("get_move_target_guide")
	_check(guide != null, "大地图创建目标标记表现节点")
	if guide == null:
		return
	_check(not guide.is_active(), "未下达移动指令时不显示目标")
	_check(_count_guide_nodes() == 1, "目标标记节点唯一")

	_player.world_position = Vector2(760.0, 620.0)
	_player.target_position = _player.world_position
	_player.movement_state = PartyData.MovementState.IDLE
	var player_icon := _map.get("_player_icon") as PartyIcon
	if player_icon != null:
		player_icon.position = _player.world_position

	var first_target := Vector2(1200.0, 900.0)
	_check(
		bool(_map.call("request_player_move", first_target)),
		"点击地图设置移动目标"
	)
	await get_tree().process_frame
	_check(guide.is_active(), "移动开始后显示目标标记与连线")
	_check(
		guide.get_target_position().is_equal_approx(first_target),
		"标记位于鼠标指定的世界坐标"
	)
	_check(
		guide.get_start_position().distance_to(_player.world_position) < 0.01,
		"虚线起点位于玩家部队当前位置"
	)
	_check(_map.position == Vector2.ZERO, "表现节点固定在世界原点")

	var second_target := Vector2(1500.0, 720.0)
	_check(
		bool(_map.call("request_player_move", second_target)),
		"再次点击更新移动目标"
	)
	await get_tree().process_frame
	_check(
		guide.get_target_position().is_equal_approx(second_target),
		"目标标记移动到新位置"
	)
	_check(_count_guide_nodes() == 1, "更新目标不会保留多个旧标记")

	# 镜头平移与缩放只改变画面，不应改变目标的世界坐标。
	_map.call("pan_camera", Vector2.RIGHT, 0.5)
	_map.call("_set_camera_zoom", 0.8)
	await get_tree().process_frame
	_check(
		guide.get_target_position().is_equal_approx(second_target),
		"镜头移动/缩放后目标世界坐标不变"
	)
	_map.call("_set_camera_zoom", 1.5)

	# 连线起点实时跟随部队图标。临时将移速置零，避免世界 tick
	# 在同一帧内推进部队导致比较基准漂移。
	var speed_before: float = _player.movement_speed
	_player.movement_speed = 0.0
	_player.world_position = Vector2(980.0, 680.0)
	if player_icon != null:
		player_icon.position = _player.world_position
	await get_tree().process_frame
	_check(
		guide.get_start_position().distance_to(_player.world_position) < 0.01,
		"连线起点跟随玩家部队实时位置"
	)
	_player.movement_speed = speed_before

	# 停止/抵达后清理。
	_context.world_map_manager.stop_party(_player.party_id)
	await get_tree().process_frame
	_check(not guide.is_active(), "停止或抵达后清除标记与连线")

	# 重新指定目标可以再次显示。
	_check(
		bool(_map.call("request_player_move", first_target)),
		"清理后重新指定目标"
	)
	await get_tree().process_frame
	_check(
		guide.is_active()
			and guide.get_target_position().is_equal_approx(first_target),
		"重新指定目标恢复标记与连线"
	)


func _count_guide_nodes() -> int:
	var count: int = 0
	if _map == null:
		return count
	for child: Node in _map.get_children():
		if child.name == "MoveTargetGuide":
			count += 1
	return count


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[movetarget] OK: %s" % message)
	else:
		_failed = true
		push_error("[movetarget] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_map):
		_map.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
