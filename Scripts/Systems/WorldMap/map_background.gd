class_name MapBackground
extends Node2D
## Milestone 1 的简单大地图背景：草地、道路、河流与边界。
## 纯绘制，不参与任何世界数据。

@export var world_size: Vector2 = Vector2(5000.0, 3000.0)


func _ready() -> void:
	z_index = -100
	queue_redraw()


func set_world_size(size: Vector2) -> void:
	if size == Vector2.ZERO:
		return
	world_size = size
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, world_size), Color("#6f8f4e"), true)

	# 轻微网格，便于判断移动距离。
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

	_draw_settlement_clearings()
	_draw_river()
	_draw_roads()

	draw_rect(Rect2(Vector2.ZERO, world_size), Color("#2d3b26"), false, 8.0)


func _draw_settlement_clearings() -> void:
	var clearings := [
		# 伯克纳尼亚王国区域（北）：统治家族与墨西西附庸封地。
		Vector2(2500.0, 700.0),
		Vector2(2250.0, 1000.0),
		Vector2(2900.0, 750.0),
		Vector2(3200.0, 1000.0),
		# 玩家中立村庄位于两王国之间的西侧缓冲地带。
		Vector2(1600.0, 1500.0),
		# 奥林王国区域（南）：统治家族与巴里附庸封地。
		Vector2(2600.0, 2100.0),
		Vector2(2900.0, 2350.0),
		Vector2(2950.0, 1850.0),
		Vector2(3250.0, 2050.0),
	]
	for point: Vector2 in clearings:
		draw_circle(point, 95.0, Color(0.86, 0.79, 0.56, 0.30))


func _draw_river() -> void:
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


func _draw_roads() -> void:
	var road_color := Color("#b7a06a")
	var roads := [
		# 玩家村庄到两个王国区域的联络道路。
		[Vector2(1600.0, 1500.0), Vector2(2900.0, 750.0)],
		[Vector2(1600.0, 1500.0), Vector2(2950.0, 1850.0)],
		# 伯克纳尼亚区域内部：统治家族、附庸与各自封地。
		[Vector2(2500.0, 700.0), Vector2(2900.0, 750.0)],
		[Vector2(2250.0, 1000.0), Vector2(2500.0, 700.0)],
		[Vector2(2900.0, 750.0), Vector2(3200.0, 1000.0)],
		[Vector2(2250.0, 1000.0), Vector2(2900.0, 750.0)],
		# 奥林区域内部：统治家族、附庸与各自封地。
		[Vector2(2950.0, 1850.0), Vector2(3250.0, 2050.0)],
		[Vector2(2950.0, 1850.0), Vector2(2600.0, 2100.0)],
		[Vector2(2600.0, 2100.0), Vector2(2900.0, 2350.0)],
	]
	for road: Array in roads:
		var from: Vector2 = road[0]
		var to: Vector2 = road[1]
		draw_line(from, to, Color(0.25, 0.2, 0.12, 0.18), 22.0, true)
		draw_line(from, to, road_color, 14.0, true)
