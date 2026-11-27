class_name WorldTerrain
extends RefCounted
## 大地图地形与寻路的唯一实现。
##
## 只读取 WorldMapDefinition（边界/湖泊/山脉）并回答两类问题：
## 1. 某个世界坐标是否可通行；
## 2. 两个世界坐标之间绕过不可通行区域的最短折线。
## 不保存部队状态，也不直接修改任何实体；WorldMapManager 负责把路径
## 转换成逐帧移动，MapBackground 只读取路径用于绘制道路。

## A* 网格边长（世界像素）。40 世界像素 = 8 参考像素，足以绕开山脉与湖泊。
const CELL_SIZE: float = 40.0
## 湖泊/山脉的额外安全边距，避免部队贴边穿入美术轮廓。
const OBSTACLE_MARGIN: float = 6.0
## 直线通路检测采样步长；越小越保守。
const SEGMENT_SAMPLE_STEP: float = 12.0
## 端点落在不可通行区域时，向外寻找可通行点的最大半径。
const SNAP_SEARCH_RADIUS: float = 600.0
const SNAP_SEARCH_STEP: float = 20.0
const MAX_CACHED_PATHS: int = 256

var _definition: WorldMapDefinition = null
var _world_size: Vector2 = Vector2.ZERO
## 闭合多边形（首点重复），便于 Geometry2D 与线段距离计算。
var _boundary: PackedVector2Array = PackedVector2Array()
var _lake: PackedVector2Array = PackedVector2Array()
## 湖泊包围盒（含边距），用于快速排除绝大多数网格点。
var _lake_bounds: Rect2 = Rect2()
var _mountains: Array[Dictionary] = []
var _astar: AStarGrid2D = null
var _path_cache: Dictionary = {}
var _cache_order: Array[String] = []


func build(definition: WorldMapDefinition) -> bool:
	if definition == null:
		return false
	_definition = definition
	_world_size = definition.get_world_size()
	if _world_size.x <= 0.0 or _world_size.y <= 0.0:
		return false
	_boundary = _close_polygon(definition.get_world_boundary())
	_lake = _close_polygon(definition.get_world_lake())
	_lake_bounds = _compute_bounds(_lake, OBSTACLE_MARGIN)
	_mountains = definition.get_world_mountains()
	if _boundary.size() < 3:
		return false
	_build_grid()
	_path_cache.clear()
	_cache_order.clear()
	return true


func is_valid() -> bool:
	return _astar != null and _world_size != Vector2.ZERO


func get_world_size() -> Vector2:
	return _world_size


## 是否位于地图外边界以内（边界本身视为不可通行）。
func is_inside_boundary(world_position: Vector2) -> bool:
	if _boundary.size() < 3:
		return false
	return Geometry2D.is_point_in_polygon(world_position, _boundary)


## 是否为湖泊/山脉（不含边界判断）。供绘制与测试使用。
func is_blocked_terrain(world_position: Vector2) -> bool:
	return _is_in_lake(world_position) or _is_in_mountain(world_position)


## 可通行 = 在边界内，且不在湖泊/山脉（含安全边距）中。
func is_passable(world_position: Vector2) -> bool:
	if not is_inside_boundary(world_position):
		return false
	if _is_in_lake(world_position):
		return false
	if _is_in_mountain(world_position):
		return false
	return true


## 直线移动是否不会穿过不可通行区域。用于保持直线路径不被无谓改道。
func is_segment_passable(from: Vector2, to: Vector2) -> bool:
	var distance: float = from.distance_to(to)
	if distance <= 0.001:
		return is_passable(from)
	var steps: int = maxi(1, int(ceil(distance / SEGMENT_SAMPLE_STEP)))
	for index: int in range(steps + 1):
		var point: Vector2 = from.lerp(to, float(index) / float(steps))
		if not is_passable(point):
			return false
	return true


## 返回从 from 到 to 的折线（含首尾）。直线可通行时只返回两个点。
## 无路可走时返回空数组，由调用者决定原地等待。
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	if not is_valid():
		return result
	if is_segment_passable(from, to):
		result.append(from)
		result.append(to)
		return result

	var cache_key := _path_cache_key(from, to)
	var cached: Variant = _path_cache.get(cache_key)
	if cached is PackedVector2Array:
		return (cached as PackedVector2Array).duplicate()

	var start := nearest_passable_point(from, SNAP_SEARCH_RADIUS)
	var goal := nearest_passable_point(to, SNAP_SEARCH_RADIUS)
	if start == goal:
		result.append(start)
		result.append(goal)
		return result

	var start_cell := _world_to_cell(start)
	var goal_cell := _world_to_cell(goal)
	if not _astar.is_in_boundsv(start_cell) or not _astar.is_in_boundsv(goal_cell):
		return result
	start_cell = _nearest_open_cell(start_cell)
	goal_cell = _nearest_open_cell(goal_cell)
	if start_cell.x < 0 or goal_cell.x < 0:
		return result

	var cells: Array[Vector2i] = _astar.get_id_path(start_cell, goal_cell)
	if cells.is_empty():
		return result

	var points := PackedVector2Array()
	points.append(from)
	for index: int in range(cells.size()):
		var cell_center := _cell_to_world(cells[index])
		if index == 0 or index == cells.size() - 1:
			continue
		if points[points.size() - 1].distance_to(cell_center) >= 1.0:
			points.append(cell_center)
	if not is_passable(to):
		points.append(goal)
	else:
		points.append(to)
	result = _smooth(points)
	_store_cache(cache_key, result)
	return result


## 把任意位置收敛到最近的可通行点；主要用于移动目标与边界外点击。
func nearest_passable_point(
	world_position: Vector2, max_radius: float = SNAP_SEARCH_RADIUS
) -> Vector2:
	if is_passable(world_position):
		return world_position
	if not is_inside_boundary(world_position):
		var inward := _closest_point_on_boundary(world_position)
		var toward_center: Vector2 = (_world_size * 0.5 - inward).normalized()
		var nudge := maxf(4.0, SEGMENT_SAMPLE_STEP)
		var candidate := inward + toward_center * nudge
		if is_passable(candidate):
			return candidate
	# 湖泊/山脉：按同心圆向外搜索第一个可通行点。
	var radius: float = SNAP_SEARCH_STEP
	while radius <= max_radius:
		var samples: int = maxi(8, int(ceil(radius / 16.0)))
		for index: int in range(samples):
			var angle: float = TAU * float(index) / float(samples)
			var candidate := world_position + Vector2(cos(angle), sin(angle)) * radius
			if is_passable(candidate):
				return candidate
		radius += SNAP_SEARCH_STEP
	return _closest_point_on_boundary(world_position)


## 道路绘制与测试使用：返回道路折线，经过 A* 绕行。
func get_road_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var path := find_path(from, to)
	if path.is_empty():
		path.append(from)
		path.append(to)
	return path


func _build_grid() -> void:
	_astar = AStarGrid2D.new()
	var width: int = maxi(1, int(ceil(_world_size.x / CELL_SIZE)))
	var height: int = maxi(1, int(ceil(_world_size.y / CELL_SIZE)))
	_astar.region = Rect2i(0, 0, width, height)
	_astar.cell_size = Vector2(CELL_SIZE, CELL_SIZE)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_astar.update()
	for y: int in range(height):
		for x: int in range(width):
			var center := Vector2(
				(float(x) + 0.5) * CELL_SIZE,
				(float(y) + 0.5) * CELL_SIZE
			)
			if not is_passable(center):
				_astar.set_point_solid(Vector2i(x, y), true)


func _nearest_open_cell(cell: Vector2i) -> Vector2i:
	if _astar.is_in_boundsv(cell) and not _astar.is_point_solid(cell):
		return cell
	for radius: int in range(1, 12):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var candidate := cell + Vector2i(dx, dy)
				if _astar.is_in_boundsv(candidate) and not _astar.is_point_solid(candidate):
					return candidate
	return Vector2i(-1, -1)


func _world_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(world_position.x / CELL_SIZE)),
		int(floor(world_position.y / CELL_SIZE))
	)


func _cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(
		(float(cell.x) + 0.5) * CELL_SIZE,
		(float(cell.y) + 0.5) * CELL_SIZE
	)


## 拉直折线：在保持可通行直线的前提下尽量跳过中间点。
func _smooth(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() <= 2:
		return points
	var result := PackedVector2Array()
	result.append(points[0])
	var index: int = 0
	while index < points.size() - 1:
		var next_index: int = points.size() - 1
		while next_index > index + 1 \
				and not is_segment_passable(points[index], points[next_index]):
			next_index -= 1
		result.append(points[next_index])
		index = next_index
	return result


func _is_in_lake(world_position: Vector2) -> bool:
	if _lake.size() < 3:
		return false
	# 湖泊在地图中央且面积有限：先用包围盒排除远点，避免每个网格点都
	# 做 11 次线段距离计算。
	if not _lake_bounds.has_point(world_position):
		return false
	if Geometry2D.is_point_in_polygon(world_position, _lake):
		return true
	return _distance_to_polyline(world_position, _lake) <= OBSTACLE_MARGIN


func _compute_bounds(points: PackedVector2Array, margin: float) -> Rect2:
	if points.is_empty():
		return Rect2()
	var minimum := points[0]
	var maximum := points[0]
	for point: Vector2 in points:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	minimum -= Vector2(margin, margin)
	maximum += Vector2(margin, margin)
	return Rect2(minimum, maximum - minimum)


func _is_in_mountain(world_position: Vector2) -> bool:
	for mountain: Dictionary in _mountains:
		var center: Vector2 = mountain.get("center", Vector2.ZERO)
		var semi_major: float = float(mountain.get("semi_major", 0.0)) + OBSTACLE_MARGIN
		var semi_minor: float = float(mountain.get("semi_minor", 0.0)) + OBSTACLE_MARGIN
		if semi_major <= 0.0 or semi_minor <= 0.0:
			continue
		var angle: float = deg_to_rad(float(mountain.get("angle_deg", 0.0)))
		var local: Vector2 = (world_position - center).rotated(-angle)
		var normalized: float = (
			(local.x * local.x) / (semi_major * semi_major)
			+ (local.y * local.y) / (semi_minor * semi_minor)
		)
		if normalized <= 1.0:
			return true
	return false


func _distance_to_polyline(point: Vector2, polygon: PackedVector2Array) -> float:
	var best: float = INF
	for index: int in range(polygon.size() - 1):
		var closest := Geometry2D.get_closest_point_to_segment(
			point, polygon[index], polygon[index + 1]
		)
		best = minf(best, point.distance_to(closest))
	return best


func _closest_point_on_boundary(point: Vector2) -> Vector2:
	var best_point := point
	var best_distance: float = INF
	for index: int in range(_boundary.size() - 1):
		var closest := Geometry2D.get_closest_point_to_segment(
			point, _boundary[index], _boundary[index + 1]
		)
		var distance := point.distance_to(closest)
		if distance < best_distance:
			best_distance = distance
			best_point = closest
	return best_point


func _close_polygon(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	if points.is_empty():
		return result
	result.append_array(points)
	if result[0] != result[result.size() - 1]:
		result.append(result[0])
	return result


func _path_cache_key(from: Vector2, to: Vector2) -> String:
	return "%d:%d:%d:%d" % [
		roundi(from.x / 8.0),
		roundi(from.y / 8.0),
		roundi(to.x / 8.0),
		roundi(to.y / 8.0),
	]


func _store_cache(key: String, path: PackedVector2Array) -> void:
	if _path_cache.has(key):
		return
	_path_cache[key] = path.duplicate()
	_cache_order.append(key)
	while _cache_order.size() > MAX_CACHED_PATHS:
		var oldest: String = _cache_order.pop_front()
		_path_cache.erase(oldest)
