extends Node
## 阶段 9 布局测试：王国/家族聚集、地点间距、地图边界与部队旗帜尺寸。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/world_map_layout_test.tscn

const MIN_SETTLEMENT_SPACING: float = 250.0
const MAX_FAMILY_SPAN: float = 500.0
const MAX_KINGDOM_SPAN: float = 1100.0

var _failed: bool = false
var _context: WorldContext = null


func _ready() -> void:
	_run()
	_cleanup()
	if _failed:
		push_error("[layout] 测试失败")
		get_tree().quit(1)
	else:
		print("[layout] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()

	_context = WorldContext.new()
	_context.name = "WorldMapLayoutContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return

	var settlements := _context.settlement_manager.get_all_settlements()
	_check(settlements.size() == 9, "存在 9 个地点")
	_check(
		_context.world_size == Vector2(5000.0, 3000.0),
		"世界尺寸保持 5000x3000"
	)

	var names: Dictionary = {}
	for settlement: SettlementData in settlements:
		_check(not names.has(settlement.display_name), "地点名称唯一: %s" % settlement.display_name)
		names[settlement.display_name] = settlement
		_check(
			_settlement_inside_world(settlement),
			"地点位于地图有效范围内: %s" % settlement.display_name
		)

	_check(_all_settlements_spaced(settlements), "任意两个地点之间保留足够间距")

	var bari: SettlementData = _settlement_named("巴里")
	var grey: SettlementData = _settlement_named("灰石城堡")
	var moxixi: SettlementData = _settlement_named("墨西西")
	var north: SettlementData = _settlement_named("北境村")
	var burknania_town: SettlementData = _settlement_named("伯克纳尼亚")
	var burkna: SettlementData = _settlement_named("伯克纳")
	var olin_castle: SettlementData = _settlement_named("奥林德斯堡")
	var olin_village: SettlementData = _settlement_named("奥林")
	if bari == null or grey == null or moxixi == null or north == null \
			or burknania_town == null or burkna == null \
			or olin_castle == null or olin_village == null:
		_check(false, "取得全部王国/家族地点")
		return

	_check(
		bari.world_position.distance_to(grey.world_position) <= MAX_FAMILY_SPAN,
		"巴里家族封地相互靠近"
	)
	_check(
		moxixi.world_position.distance_to(north.world_position) <= MAX_FAMILY_SPAN,
		"墨西西家族封地相互靠近"
	)
	_check(
		burknania_town.world_position.distance_to(burkna.world_position) <= MAX_FAMILY_SPAN,
		"伯克纳尼亚城镇与伯克纳村庄相邻"
	)
	_check(
		olin_castle.world_position.distance_to(olin_village.world_position) <= MAX_FAMILY_SPAN,
		"奥林德斯堡与奥林村庄相邻"
	)

	var burknania_points: Array[Vector2] = [
		moxixi.world_position,
		north.world_position,
		burknania_town.world_position,
		burkna.world_position,
	]
	var olin_points: Array[Vector2] = [
		bari.world_position,
		grey.world_position,
		olin_castle.world_position,
		olin_village.world_position,
	]
	_check(
		_max_pair_distance(burknania_points) <= MAX_KINGDOM_SPAN,
		"伯克纳王国地点形成集中区域"
	)
	_check(
		_max_pair_distance(olin_points) <= MAX_KINGDOM_SPAN,
		"奥林王国地点形成集中区域"
	)

	var burknania_center := _centroid(burknania_points)
	var olin_center := _centroid(olin_points)
	var kingdom_gap := burknania_center.distance_to(olin_center)
	_check(kingdom_gap >= 600.0, "两个王国区域之间保留势力间隔")
	_check(kingdom_gap <= 1800.0, "两个王国区域没有过度分散")

	_check(
		moxixi.world_position.distance_to(burknania_center) <= 900.0
		and north.world_position.distance_to(burknania_center) <= 900.0,
		"墨西西封地靠近伯克纳王国区域"
	)
	_check(
		bari.world_position.distance_to(olin_center) <= 900.0
		and grey.world_position.distance_to(olin_center) <= 900.0,
		"巴里封地靠近奥林王国区域"
	)

	# 部队图标：只放大内部旗帜，圆形尺寸与遮罩半径保持不变。
	var style := load(
		"res://Data/WorldMap/party_marker_style.tres"
	) as PartyMarkerStyle
	_check(style != null, "加载部队标记样式")
	if style != null:
		_check(is_equal_approx(style.marker_radius, 18.0), "圆形半径保持 18")
		_check(style.flag_max_size > 30.0, "内部旗帜尺寸增大")
		_check(
			style.flag_max_size <= style.marker_radius * 2.0 + 4.0,
			"旗帜不改变圆形底盘尺寸"
		)
		_check(
			style.get_flag_clip_uv_radius() < 0.5,
			"旗帜由圆形遮罩限制在可视范围内"
		)


func _settlement_inside_world(settlement: SettlementData) -> bool:
	var margin: float = 120.0
	return settlement.world_position.x >= margin \
		and settlement.world_position.y >= margin \
		and settlement.world_position.x <= _context.world_size.x - margin \
		and settlement.world_position.y <= _context.world_size.y - margin


func _all_settlements_spaced(settlements: Array[SettlementData]) -> bool:
	for i: int in range(settlements.size()):
		for j: int in range(i + 1, settlements.size()):
			if settlements[i].world_position.distance_to(
				settlements[j].world_position
			) < MIN_SETTLEMENT_SPACING:
				return false
	return true


func _max_pair_distance(points: Array[Vector2]) -> float:
	var maximum: float = 0.0
	for i: int in range(points.size()):
		for j: int in range(i + 1, points.size()):
			maximum = maxf(maximum, points[i].distance_to(points[j]))
	return maximum


func _centroid(points: Array[Vector2]) -> Vector2:
	var total := Vector2.ZERO
	for point: Vector2 in points:
		total += point
	return total / float(points.size())


func _settlement_named(settlement_name: String) -> SettlementData:
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement.display_name == settlement_name:
			return settlement
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[layout] OK: %s" % message)
	else:
		_failed = true
		push_error("[layout] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	if is_instance_valid(_context):
		_context.queue_free()
