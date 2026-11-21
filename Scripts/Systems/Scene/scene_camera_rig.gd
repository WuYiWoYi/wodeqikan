class_name SceneCameraRig
extends RefCounted
## 村庄与战斗小场景共用的摄像机控制。
##
## 职责：
## - 使用统一的“世界可视区域”计算缩放，保证村庄与战斗看到的区域大小一致；
## - 默认平滑跟随当前玩家控制角色；
## - 支持自由视角模式（WASD / 方向键移动摄像机，不移动角色）；
## - 跟随与自由模式都限制在地图/战场边界内。
##
## 本类只操作一个 Camera2D，不创建额外摄像机，也不修改任何世界数据。

## 统一视野基准：在 1920×1080 下正好显示 960×540 世界单位。
## 其他分辨率按相同世界区域换算缩放；宽高比不同时至少保留该区域。
const VIEW_SIZE: Vector2 = Vector2(960.0, 540.0)
const FOLLOW_SMOOTHING: float = 8.0
const FREE_MOVE_SPEED: float = 650.0
const MIN_ZOOM: float = 0.5
const MAX_ZOOM: float = 4.0

var camera: Camera2D = null
var bounds: Rect2 = Rect2()
var follow_offset: Vector2 = Vector2.ZERO
var free_mode: bool = false

## 自动化测试用自由视角输入；正常游戏读取真实按键。
var has_test_free_input: bool = false
var test_free_input: Vector2 = Vector2.ZERO

var _last_follow_position: Vector2 = Vector2.ZERO
var _has_follow_position: bool = false
var _free_position: Vector2 = Vector2.ZERO


func setup(
	camera_node: Camera2D,
	world_bounds: Rect2,
	follow_position_offset: Vector2 = Vector2.ZERO
) -> void:
	camera = camera_node
	bounds = world_bounds
	follow_offset = follow_position_offset
	_apply_unified_zoom()
	if camera != null:
		_free_position = camera.position


func clear() -> void:
	camera = null
	_has_follow_position = false


func is_free_mode() -> bool:
	return free_mode


func get_mode_text() -> String:
	return "自由视角" if free_mode else "跟随视角"


## 当前缩放；无摄像机时返回 1。
func get_zoom() -> float:
	return camera.zoom.x if camera != null else 1.0


## 统一视野换算：给定视口尺寸，返回能看到至少 VIEW_SIZE 世界区域的缩放。
static func compute_unified_zoom(viewport_size: Vector2) -> float:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return 1.0
	var zoom: float = minf(
		viewport_size.x / VIEW_SIZE.x,
		viewport_size.y / VIEW_SIZE.y
	)
	return clampf(zoom, MIN_ZOOM, MAX_ZOOM)


## 立即把摄像机放到目标位置（受边界限制）。用于场景进入和切回跟随模式。
func snap_to(world_position: Vector2) -> void:
	_last_follow_position = world_position
	_has_follow_position = true
	if camera == null:
		return
	_apply_unified_zoom()
	camera.position = _clamp_center(world_position + follow_offset, camera.zoom.x)


func toggle_free_mode() -> bool:
	set_free_mode(not free_mode)
	return free_mode


## 切入自由模式时从当前镜头位置开始；切回跟随时重新定位到最近一次跟随目标。
func set_free_mode(active: bool) -> void:
	if active == free_mode:
		return
	free_mode = active
	if camera == null:
		return
	_apply_unified_zoom()
	if active:
		_free_position = camera.position
	elif _has_follow_position:
		camera.position = _clamp_center(
			_last_follow_position + follow_offset, camera.zoom.x
		)


## 每帧更新。follow_active 为 false 时（例如观战）镜头保持当前位置。
func update(
	delta: float,
	follow_position: Vector2,
	follow_active: bool = true,
	input_allowed: bool = true
) -> void:
	if camera == null:
		return
	_apply_unified_zoom()

	if follow_active:
		_last_follow_position = follow_position
		_has_follow_position = true

	if free_mode:
		var direction := _read_free_input() if input_allowed else Vector2.ZERO
		if direction.length_squared() > 1.0:
			direction = direction.normalized()
		if direction != Vector2.ZERO:
			_free_position += direction * FREE_MOVE_SPEED * delta / maxf(camera.zoom.x, 0.001)
		_free_position = _clamp_center(_free_position, camera.zoom.x)
		camera.position = _free_position
		return

	if not _has_follow_position:
		return
	var desired: Vector2 = _clamp_center(
		_last_follow_position + follow_offset, camera.zoom.x
	)
	var weight: float = 1.0 - exp(-FOLLOW_SMOOTHING * delta)
	camera.position = camera.position.lerp(desired, weight)
	# 平滑后再次限制，避免边缘插值时短暂越界。
	camera.position = _clamp_center(camera.position, camera.zoom.x)


func set_test_free_input(direction: Vector2, active: bool = true) -> void:
	test_free_input = direction.limit_length(1.0)
	has_test_free_input = active


func get_camera_position() -> Vector2:
	return camera.position if camera != null else Vector2.ZERO


func _apply_unified_zoom() -> void:
	if camera == null:
		return
	var viewport_size := _get_viewport_size()
	var zoom_value: float = compute_unified_zoom(viewport_size)
	camera.zoom = Vector2(zoom_value, zoom_value)


func _get_viewport_size() -> Vector2:
	if camera == null:
		return Vector2.ZERO
	var viewport := camera.get_viewport()
	if viewport != null:
		return viewport.get_visible_rect().size
	return Vector2.ZERO


func _read_free_input() -> Vector2:
	if has_test_free_input:
		return test_free_input
	var direction := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		direction.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		direction.y += 1.0
	return direction


## 把镜头中心限制在边界内；世界小于可视区域时居中。
func _clamp_center(center: Vector2, zoom_value: float) -> Vector2:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return center
	var viewport_size := _get_viewport_size()
	if viewport_size == Vector2.ZERO:
		return center
	var half_view: Vector2 = viewport_size / (2.0 * maxf(zoom_value, 0.001))
	var result := center
	if bounds.size.x > half_view.x * 2.0:
		result.x = clampf(
			result.x, bounds.position.x + half_view.x, bounds.end.x - half_view.x
		)
	else:
		result.x = bounds.position.x + bounds.size.x * 0.5
	if bounds.size.y > half_view.y * 2.0:
		result.y = clampf(
			result.y, bounds.position.y + half_view.y, bounds.end.y - half_view.y
		)
	else:
		result.y = bounds.position.y + bounds.size.y * 0.5
	return result
