extends Node
## 小场景摄像机测试：统一视野、跟随、自由视角、边界限制、切回跟随。
## 覆盖村庄实际场景与 SceneCameraRig 的通用行为。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/small_scene_camera_test.tscn

var _failed: bool = false
var _context: WorldContext = null
var _village: VillageScene = null
var _test_camera: Camera2D = null
var _rig: SceneCameraRig = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[camera] 测试失败")
		get_tree().quit(1)
	else:
		print("[camera] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	_test_unified_view_size()
	await _test_rig_follow_and_free_mode()
	await _test_village_camera()


func _test_unified_view_size() -> void:
	_check(
		is_equal_approx(
			SceneCameraRig.compute_unified_zoom(Vector2(1920.0, 1080.0)), 2.0
		),
		"1920×1080 下村庄与战斗统一使用 2 倍缩放"
	)
	_check(
		is_equal_approx(
			SceneCameraRig.compute_unified_zoom(Vector2(1280.0, 720.0)),
			4.0 / 3.0
		),
		"其他 16:9 分辨率按同一世界区域换算"
	)
	_check(
		SceneCameraRig.VIEW_SIZE == Vector2(960.0, 540.0),
		"统一视野基准为 960×540 世界单位"
	)


func _test_rig_follow_and_free_mode() -> void:
	var holder := Node2D.new()
	holder.name = "CameraRigHolder"
	add_child(holder)
	_test_camera = Camera2D.new()
	_test_camera.name = "TestCamera"
	holder.add_child(_test_camera)
	_test_camera.make_current()
	await get_tree().process_frame

	_rig = SceneCameraRig.new()
	_rig.setup(_test_camera, Rect2(Vector2.ZERO, Vector2(1280.0, 720.0)))
	_rig.snap_to(Vector2(640.0, 360.0))
	var expected_zoom: float = SceneCameraRig.compute_unified_zoom(
		_test_camera.get_viewport().get_visible_rect().size
	)
	_check(
		is_equal_approx(_test_camera.zoom.x, expected_zoom),
		"摄像机使用统一视野缩放"
	)
	_check(not _rig.is_free_mode(), "默认模式为跟随")

	var start_position := _rig.get_camera_position()
	for i: int in range(10):
		_rig.update(0.1, Vector2(760.0, 360.0), true)
	_check(
		_rig.get_camera_position().x > start_position.x,
		"跟随模式下摄像机平滑靠近目标"
	)

	_rig.set_free_mode(true)
	_check(_rig.is_free_mode(), "可以切换到自由视角")
	_rig.set_test_free_input(Vector2.RIGHT)
	var free_start := _rig.get_camera_position()
	_rig.update(0.5, Vector2(760.0, 360.0), true)
	_check(
		_rig.get_camera_position().x > free_start.x,
		"自由视角下方向输入移动摄像机"
	)

	# 持续向右移动，必须停在地图边界内。
	for i: int in range(200):
		_rig.update(0.5, Vector2(760.0, 360.0), true)
	var viewport_size: Vector2 = _test_camera.get_viewport().get_visible_rect().size
	var half_view_x: float = viewport_size.x / (2.0 * _test_camera.zoom.x)
	var max_center_x: float = 1280.0 - half_view_x
	_check(
		_rig.get_camera_position().x <= max_center_x + 0.01,
		"自由视角不会移出地图边界"
	)

	_rig.set_test_free_input(Vector2.ZERO, false)
	_rig.set_free_mode(false)
	_check(not _rig.is_free_mode(), "可以切回跟随模式")
	_check(
		_rig.get_camera_position().distance_to(
			_clamp_expected(Vector2(760.0, 360.0))
		) < 0.5,
		"切回跟随后重新定位到当前角色"
	)

	holder.queue_free()
	await get_tree().process_frame


func _test_village_camera() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)

	_context = WorldContext.new()
	_context.name = "SmallSceneCameraContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return
	var village_data := _find_village()
	_check(village_data != null, "找到村庄")
	if village_data == null:
		return
	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id
	GameManager.current_settlement_id = village_data.settlement_id

	var packed := load("res://Scenes/Village/village.tscn") as PackedScene
	_village = packed.instantiate() as VillageScene
	add_child(_village)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var village_rig := _village.get_camera_rig()
	_check(village_rig != null, "村庄使用共享摄像机控制器")
	if village_rig == null:
		return
	var village_camera := _village.find_child("Camera2D", true, false) as Camera2D
	var expected_zoom: float = SceneCameraRig.compute_unified_zoom(
		village_camera.get_viewport().get_visible_rect().size
	)
	_check(
		is_equal_approx(village_camera.zoom.x, expected_zoom),
		"村庄使用统一视野缩放"
	)

	var player_position := _village.get_player_position()
	var camera_before := _village.get_camera_position()
	_village.set_camera_free_mode(true)
	_village.set_test_free_camera_input(Vector2.RIGHT)
	for i: int in range(5):
		await get_tree().physics_frame
	_check(
		_village.get_player_position().distance_to(player_position) < 0.01,
		"自由视角移动不会改变玩家角色位置"
	)
	_check(
		_village.get_camera_position().x > camera_before.x,
		"村庄自由视角可以移动摄像机"
	)
	_village.set_test_free_camera_input(Vector2.ZERO, false)
	_village.set_camera_free_mode(false)
	_check(not _village.is_camera_free_mode(), "村庄可以切回跟随模式")

	var follow_start := _village.get_camera_position()
	_village.set_player_position(Vector2(1200.0, 600.0))
	for i: int in range(20):
		await get_tree().physics_frame
	_check(
		_village.get_camera_position().distance_to(follow_start) > 1.0,
		"跟随模式下摄像机随玩家移动"
	)


func _clamp_expected(target: Vector2) -> Vector2:
	var viewport_size: Vector2 = _test_camera.get_viewport().get_visible_rect().size
	if viewport_size == Vector2.ZERO:
		return target
	var half_view: Vector2 = viewport_size / (2.0 * _test_camera.zoom.x)
	var result := target
	result.x = clampf(result.x, half_view.x, 1280.0 - half_view.x)
	result.y = clampf(result.y, half_view.y, 720.0 - half_view.y)
	return result


func _find_village() -> SettlementData:
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement.settlement_type == SettlementData.SettlementType.VILLAGE:
			return settlement
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[camera] OK: %s" % message)
	else:
		_failed = true
		push_error("[camera] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	GameManager.current_settlement_id = ""
	if is_instance_valid(_village):
		_village.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
