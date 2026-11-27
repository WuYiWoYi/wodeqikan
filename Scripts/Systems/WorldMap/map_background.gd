class_name MapBackground
extends Node2D
## 大地图背景：边界、道路、湖泊与山脉的纯绘制层。
##
## 新地图只读取 WorldMapDefinition 与 WorldTerrain，不保存任何世界状态；
## 地点图标、名称与旗帜仍由 SettlementIcon / SettlementNameTag 负责。
## 旧存档（世界尺寸不匹配）继续使用原来的矩形草地绘制，避免地图与
## 旧地点坐标错位。

@export var world_size: Vector2 = Vector2(5000.0, 3000.0)

## 外围海洋：边界外不可通行区域，柔和的海水蓝，避免高饱和。
const OCEAN_COLOR: Color = Color("#5a8fae")
## 可通行陆地：柔和草地绿，作为地图主体底色。
const LAND_COLOR: Color = Color("#a8c483")
## 陆地低强度网格纹理，只绘制在陆地多边形内部。
const GRID_COLOR: Color = Color(0.16, 0.30, 0.10, 0.055)
const GRID_STEP: float = 200.0
## 海岸线：陆地与海洋的清晰分界。
const COASTLINE_COLOR: Color = Color("#2f7a4a")
const COASTLINE_WIDTH: float = 6.0
const ROAD_COLOR: Color = Color("#7a7469")
const ROAD_WIDTH: float = 5.0
const ROAD_DASH: float = 26.0
const ROAD_GAP: float = 18.0
## 中央淡水湖：比外围海洋稍深的蓝色，与海洋和陆地都能区分。
const LAKE_FILL: Color = Color("#3c7396")
const LAKE_LINE: Color = Color("#2a5675")
const LAKE_WIDTH: float = 6.0
const MOUNTAIN_FILL: Color = Color("#aaa79f")
const MOUNTAIN_LINE: Color = Color("#6d6a64")
const MOUNTAIN_WIDTH: float = 4.0

var _definition: WorldMapDefinition = null
var _terrain: WorldTerrain = null
var _road_paths: Array[PackedVector2Array] = []
var _road_paths_ready: bool = false
## 陆地网格按陆地多边形裁切后的线段缓存，仅在定义/尺寸变化时重算。
var _land_grid_segments: Array[PackedVector2Array] = []
var _land_grid_ready: bool = false


func _ready() -> void:
	z_index = -100
	queue_redraw()


func set_world_size(size: Vector2) -> void:
	if size == Vector2.ZERO:
		return
	world_size = size
	_road_paths_ready = false
	_land_grid_ready = false
	queue_redraw()


## 由 WorldMap 在场景就绪时注入；旧存档也会注入，但尺寸不匹配时走旧绘制。
func set_map_definition(
	definition: WorldMapDefinition, terrain: WorldTerrain = null
) -> void:
	_definition = definition
	_terrain = terrain
	_road_paths_ready = false
	_land_grid_ready = false
	queue_redraw()


func _draw() -> void:
	if _definition != null and world_size == _definition.get_world_size():
		_draw_rebuilt_map()
		return
	_draw_legacy_map()


## 新地图：外围海洋 + 绿色陆地 + 湖泊 + 山脉，全部来自 WorldMapDefinition。
func _draw_rebuilt_map() -> void:
	# 整块世界先铺海洋蓝；边界外的不可通行区域因此始终是海面。
	draw_rect(Rect2(Vector2.ZERO, world_size), OCEAN_COLOR, true)

	var boundary := _definition.get_world_boundary()
	var closed := _close_polygon(boundary)
	if closed.size() >= 3:
		# 填充多边形不能重复首点，否则 Godot 三角化会失败；描边可以闭合。
		draw_colored_polygon(_open_polygon(closed), LAND_COLOR)
		_draw_land_grid(closed)
		# 海岸线覆盖陆地与海洋的交界，保证边界清晰、不出现色彩渗透。
		draw_polyline(closed, COASTLINE_COLOR, COASTLINE_WIDTH, true)

	_draw_roads()

	var lake := _close_polygon(_definition.get_world_lake())
	if lake.size() >= 3:
		draw_colored_polygon(_open_polygon(lake), LAKE_FILL)
		draw_polyline(lake, LAKE_LINE, LAKE_WIDTH, true)

	for mountain: Dictionary in _definition.get_world_mountains():
		_draw_mountain_ellipse(mountain)


## 陆地网格纹理：直线按陆地多边形裁切，海洋区域不会出现网格。
func _draw_land_grid(land: PackedVector2Array) -> void:
	if not _land_grid_ready:
		_land_grid_segments = _build_clipped_grid(land)
		_land_grid_ready = true
	for segment: PackedVector2Array in _land_grid_segments:
		if segment.size() >= 2:
			draw_polyline(segment, GRID_COLOR, 1.0)


func _build_clipped_grid(land: PackedVector2Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var polygon := _open_polygon(land)
	if polygon.size() < 3:
		return result
	var x := GRID_STEP
	while x < world_size.x:
		var vertical := PackedVector2Array([
			Vector2(x, 0.0), Vector2(x, world_size.y)
		])
		result.append_array(
			Geometry2D.intersect_polyline_with_polygon(vertical, polygon)
		)
		x += GRID_STEP
	var y := GRID_STEP
	while y < world_size.y:
		var horizontal := PackedVector2Array([
			Vector2(0.0, y), Vector2(world_size.x, y)
		])
		result.append_array(
			Geometry2D.intersect_polyline_with_polygon(horizontal, polygon)
		)
		y += GRID_STEP
	return result


func _draw_roads() -> void:
	if not _road_paths_ready:
		_road_paths.clear()
		for road: Dictionary in _definition.get_world_roads():
			var from: Vector2 = road.get("from", Vector2.ZERO)
			var to: Vector2 = road.get("to", Vector2.ZERO)
			if _terrain != null:
				_road_paths.append(_terrain.get_road_path(from, to))
			else:
				_road_paths.append(PackedVector2Array([from, to]))
		_road_paths_ready = true
	for path: PackedVector2Array in _road_paths:
		_draw_dashed_polyline(path, ROAD_COLOR, ROAD_WIDTH, ROAD_DASH, ROAD_GAP)


## 旋转椭圆：参考图中山脉以细长灰色椭圆表示，填色后描边。
func _draw_mountain_ellipse(mountain: Dictionary) -> void:
	var center: Vector2 = mountain.get("center", Vector2.ZERO)
	var semi_major: float = float(mountain.get("semi_major", 0.0))
	var semi_minor: float = float(mountain.get("semi_minor", 0.0))
	if semi_major <= 0.0 or semi_minor <= 0.0:
		return
	var angle: float = deg_to_rad(float(mountain.get("angle_deg", 0.0)))
	var points := PackedVector2Array()
	var segments: int = 48
	for index: int in range(segments):
		var theta: float = TAU * float(index) / float(segments)
		var local := Vector2(cos(theta) * semi_major, sin(theta) * semi_minor)
		points.append(center + local.rotated(angle))
	draw_colored_polygon(_open_polygon(points), MOUNTAIN_FILL)
	points.append(points[0])
	draw_polyline(points, MOUNTAIN_LINE, MOUNTAIN_WIDTH, true)


func _draw_dashed_polyline(
	points: PackedVector2Array,
	color: Color,
	width: float,
	dash_length: float,
	gap_length: float
) -> void:
	if points.size() < 2:
		return
	var pattern: float = dash_length + gap_length
	var phase: float = 0.0
	for index: int in range(points.size() - 1):
		var from: Vector2 = points[index]
		var to: Vector2 = points[index + 1]
		var segment_length: float = from.distance_to(to)
		if segment_length <= 0.001:
			continue
		var direction: Vector2 = (to - from) / segment_length
		var travelled: float = 0.0
		while travelled < segment_length:
			var in_pattern: float = fmod(phase + travelled, pattern)
			if in_pattern < dash_length:
				var dash_remaining: float = dash_length - in_pattern
				var end_distance: float = minf(
					segment_length, travelled + dash_remaining
				)
				draw_line(
					from + direction * travelled,
					from + direction * end_distance,
					color,
					width,
					true
				)
				travelled = end_distance
			else:
				travelled += pattern - in_pattern
		phase = fmod(phase + segment_length, pattern)


## 填充用：去掉重复的最后一点（首尾相同会让三角化失败）。
func _open_polygon(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	if points.is_empty():
		return result
	result.append_array(points)
	if result.size() > 1 and result[0] == result[result.size() - 1]:
		result.remove_at(result.size() - 1)
	return result


func _close_polygon(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	if points.is_empty():
		return result
	result.append_array(points)
	if result[0] != result[result.size() - 1]:
		result.append(result[0])
	return result


# ---------------------------------------------------------------------------
# 旧存档兼容绘制：保持原 5000×3000 世界的草地/河流/道路表现。
# ---------------------------------------------------------------------------

func _draw_legacy_map() -> void:
	draw_rect(Rect2(Vector2.ZERO, world_size), Color("#6f8f4e"), true)

	var grid_color := Color(1.0, 1.0, 1.0, 0.035)
	var step := 200.0
	var x := 0.0
	while x <= world_size.x:
		draw_line(Vector2(x, 0.0), Vector2(x, world_size.y), grid_color, 1.0)
		x += step
	var y := 0.0
	while y <= world_size.y:
		draw_line(Vector2(0.0, y), Vector2(world_size.x, y), grid_color, 1.0)
		y += step

	_draw_legacy_clearings()
	_draw_legacy_river()
	_draw_legacy_roads()

	draw_rect(Rect2(Vector2.ZERO, world_size), Color("#2d3b26"), false, 8.0)


func _draw_legacy_clearings() -> void:
	var clearings := [
		Vector2(2500.0, 700.0),
		Vector2(2250.0, 1000.0),
		Vector2(2900.0, 750.0),
		Vector2(3200.0, 1000.0),
		Vector2(1600.0, 1500.0),
		Vector2(2600.0, 2100.0),
		Vector2(2900.0, 2350.0),
		Vector2(2950.0, 1850.0),
		Vector2(3250.0, 2050.0),
	]
	for point: Vector2 in clearings:
		draw_circle(point, 95.0, Color(0.86, 0.79, 0.56, 0.30))


func _draw_legacy_river() -> void:
	var river := PackedVector2Array([
		Vector2(140.0, -20.0),
		Vector2(380.0, 300.0),
		Vector2(650.0, 700.0),
		Vector2(980.0, 1000.0),
		Vector2(1250.0, 1250.0),
		Vector2(1500.0, 1600.0),
		Vector2(1650.0, 2020.0),
	])
	draw_polyline(river, Color("#315f80"), 86.0, true)
	draw_polyline(river, Color("#4f8bb0"), 64.0, true)


func _draw_legacy_roads() -> void:
	var road_color := Color("#b7a06a")
	var roads := [
		[Vector2(1600.0, 1500.0), Vector2(2900.0, 750.0)],
		[Vector2(1600.0, 1500.0), Vector2(2950.0, 1850.0)],
		[Vector2(2500.0, 700.0), Vector2(2900.0, 750.0)],
		[Vector2(2250.0, 1000.0), Vector2(2500.0, 700.0)],
		[Vector2(2900.0, 750.0), Vector2(3200.0, 1000.0)],
		[Vector2(2250.0, 1000.0), Vector2(2900.0, 750.0)],
		[Vector2(2950.0, 1850.0), Vector2(3250.0, 2050.0)],
		[Vector2(2950.0, 1850.0), Vector2(2600.0, 2100.0)],
		[Vector2(2600.0, 2100.0), Vector2(2900.0, 2350.0)],
	]
	for road: Array in roads:
		var from: Vector2 = road[0]
		var to: Vector2 = road[1]
		draw_line(from, to, Color(0.25, 0.2, 0.12, 0.18), 22.0, true)
		draw_line(from, to, road_color, 14.0, true)
