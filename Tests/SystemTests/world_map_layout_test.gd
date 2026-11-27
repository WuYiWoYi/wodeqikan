extends Node
## 大地图重建测试：参考图布局、坐标唯一性、边界/湖泊/山脉不可通行、
## 道路绕行、时间标定、六方势力与旗帜配置。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/world_map_layout_test.tscn

const EXPECTED_SETTLEMENT_COUNT: int = 63
const EXPECTED_HOUSE_COUNT: int = 18
const EXPECTED_KINGDOM_COUNT: int = 6
const EXPECTED_NOBLE_COUNT: int = 18
const EXPECTED_PARTY_COUNT: int = 23
const MIN_SETTLEMENT_SPACING: float = 250.0
const MIN_BOUNDARY_CLEARANCE_REFERENCE: float = 1.0
## 1 游戏小时 = 2 世界秒；玩家原始速度 450 × 0.08 = 36 世界像素/秒。
## 移速基准由 20 调整为 30、玩家单独为 36 后，最近地点对的行程约 5.8 游戏小时。
const SECONDS_PER_GAME_HOUR: float = 2.0

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

	var definition := _context.world_map_definition
	_check(definition != null, "加载大地图定义")
	if definition == null:
		return

	_test_map_definition(definition)
	_test_settlement_layout()
	_test_terrain_and_paths()
	_test_time_calibration()
	_test_political_layout()
	_test_flags()


func _test_map_definition(definition: WorldMapDefinition) -> void:
	_check(
		_context.world_size == Vector2(7780.0, 6615.0),
		"世界尺寸为 7780x6615（1556x1323 × 5）"
	)
	_check(
		_context.world_size == definition.get_world_size(),
		"世界尺寸来自地图定义"
	)
	_check(definition.boundary_points.size() >= 40, "边界为不规则多边形")
	_check(definition.lake_points.size() >= 6, "湖泊为多边形")
	_check(definition.mountains.size() == 5, "配置 5 座山脉")
	_check(definition.roads.size() == 46, "配置 46 条显式道路")

	var known_keys: Dictionary = {}
	for value: Dictionary in definition.settlements:
		known_keys[str(value.get("key", ""))] = true
	for road: PackedStringArray in definition.roads:
		_check(road.size() == 2, "道路包含两个端点")
		_check(
			known_keys.has(road[0]) and known_keys.has(road[1]),
			"道路端点有效: %s - %s" % [road[0], road[1]]
		)


func _test_settlement_layout() -> void:
	var settlements := _context.settlement_manager.get_all_settlements()
	_check(settlements.size() == EXPECTED_SETTLEMENT_COUNT, "存在 63 个地点")

	var names: Dictionary = {}
	var positions: Dictionary = {}
	for settlement: SettlementData in settlements:
		_check(
			not names.has(settlement.display_name),
			"地点名称唯一: %s" % settlement.display_name
		)
		names[settlement.display_name] = true
		var key := "%d:%d" % [
			roundi(settlement.world_position.x), roundi(settlement.world_position.y)
		]
		_check(not positions.has(key), "地点坐标唯一: %s" % settlement.display_name)
		positions[key] = true
		_check(
			_settlement_inside_boundary(settlement),
			"地点位于绿线边界内: %s" % settlement.display_name
		)
		_check(
			not _context.world_terrain.is_blocked_terrain(settlement.world_position),
			"地点不在湖泊/山脉中: %s" % settlement.display_name
		)

	_check(_all_settlements_spaced(settlements), "任意两个地点之间保留足够间距")
	_check(
		_settlement_named("埃克托") != null
			and _settlement_named("埃克托村") != null,
		"同名埃克托使用独立 key/显示名区分"
	)


func _test_terrain_and_paths() -> void:
	var terrain := _context.world_terrain
	_check(terrain != null and terrain.is_valid(), "装配真实地形寻路")
	if terrain == null or not terrain.is_valid():
		return

	_check(not terrain.is_passable(Vector2(40.0, 40.0)), "地图外不可通行")
	var lake_center := _polygon_centroid(_context.world_map_definition.get_world_lake())
	_check(not terrain.is_passable(lake_center), "湖泊中心不可通行")
	for mountain: Dictionary in _context.world_map_definition.get_world_mountains():
		var center: Vector2 = mountain.get("center", Vector2.ZERO)
		_check(not terrain.is_passable(center), "山脉中心不可通行")

	var lake_snap := terrain.nearest_passable_point(lake_center)
	_check(terrain.is_passable(lake_snap), "湖泊附近存在最近可通行点")
	_check(
		lake_snap.distance_to(lake_center) > 0.0,
		"不可通行点会被收敛到岸边"
	)

	var dindani := _context.world_map_definition.get_settlement_world_position(
		"dindani"
	)
	var ogavina := _context.world_map_definition.get_settlement_world_position(
		"ogavina"
	)
	var path := terrain.find_path(dindani, ogavina)
	_check(path.size() > 2, "穿越山脉的道路会绕行")
	_check(_path_is_passable(terrain, path), "绕行路径全程可通行")
	_check(
		not terrain.is_segment_passable(dindani, ogavina),
		"丁达尼—奥加维纳直线确实被山脉阻断"
	)

	var open_start := _context.get_player_party().world_position
	var open_goal := open_start + Vector2(240.0, 0.0)
	var open_path := terrain.find_path(open_start, open_goal)
	_check(open_path.size() == 2, "无障碍路段保持直线路径")


func _test_time_calibration() -> void:
	var settlements := _context.settlement_manager.get_all_settlements()
	var nearest_distance: float = INF
	for i: int in range(settlements.size()):
		for j: int in range(i + 1, settlements.size()):
			nearest_distance = minf(
				nearest_distance,
				settlements[i].world_position.distance_to(
					settlements[j].world_position
				)
			)
	var player := _context.get_player_party()
	var effective_speed := _context.world_map_manager.get_effective_movement_speed(
		player
	)
	var travel_hours: float = nearest_distance / effective_speed / SECONDS_PER_GAME_HOUR
	_check(
		absf(travel_hours - 5.77) <= 0.6,
		"最近地点行程与新移速基准标定一致（实际 %.2f 游戏小时）" % travel_hours
	)
	_check(
		is_equal_approx(WorldMapManager.WORLD_MAP_SPEED_SCALE, 0.08),
		"大地图移动系数为 0.08"
	)


func _test_political_layout() -> void:
	var houses := _context.house_manager.get_all_houses()
	var kingdoms := _context.kingdom_manager.get_all_kingdoms()
	var nobles := _context.noble_manager.get_all_nobles()
	var parties := _context.party_manager.get_all_parties()
	_check(houses.size() == EXPECTED_HOUSE_COUNT, "存在 18 个家族")
	_check(kingdoms.size() == EXPECTED_KINGDOM_COUNT, "存在 6 个王国")
	_check(nobles.size() == EXPECTED_NOBLE_COUNT, "存在 18 名贵族")
	_check(parties.size() == EXPECTED_PARTY_COUNT, "存在 23 支部队")

	var expected: Array[Dictionary] = [
		{
			"id": WorldInitializer.KINGDOM_BURKNANIA_ID,
			"name": "伯克纳王国",
			"people": "多拉曼人",
			"ruler": WorldInitializer.HOUSE_BURKNANIA_ID,
			"vassals": [
				WorldInitializer.HOUSE_ODESTER_ID,
				WorldInitializer.HOUSE_EKTOR_ID,
				WorldInitializer.HOUSE_BAFLE_ID,
				WorldInitializer.HOUSE_BARI_ID,
			],
		},
		{
			"id": WorldInitializer.KINGDOM_FRANI_ID,
			"name": "弗拉尼伯国",
			"people": "布吉多人",
			"ruler": WorldInitializer.HOUSE_FRANI_ID,
			"vassals": [
				WorldInitializer.HOUSE_DINDANI_ID,
				WorldInitializer.HOUSE_KONLIA_ID,
				WorldInitializer.HOUSE_MIQIQI_ID,
			],
		},
		{
			"id": WorldInitializer.KINGDOM_VAILA_ID,
			"name": "瓦伊拉王国",
			"people": "布吉多人",
			"ruler": WorldInitializer.HOUSE_VAILA_ID,
			"vassals": [],
		},
		{
			"id": WorldInitializer.KINGDOM_LORIAK_ID,
			"name": "洛里亚克王国",
			"people": "洛里斯人",
			"ruler": WorldInitializer.HOUSE_LORIAK_ID,
			"vassals": [
				WorldInitializer.HOUSE_OLIN_ID,
				WorldInitializer.HOUSE_MOXIXI_ID,
				WorldInitializer.HOUSE_ROSVIK_ID,
			],
		},
		{
			"id": WorldInitializer.KINGDOM_TAINA_ID,
			"name": "泰纳公国",
			"people": "蒙卡人",
			"ruler": WorldInitializer.HOUSE_TAINA_ID,
			"vassals": [],
		},
		{
			"id": WorldInitializer.KINGDOM_VALEMON_ID,
			"name": "瓦勒蒙联盟",
			"people": "蒙卡人",
			"ruler": WorldInitializer.HOUSE_VALEMON_ID,
			"vassals": [WorldInitializer.HOUSE_KRIKA_ID],
		},
	]
	for spec: Dictionary in expected:
		var kingdom := _context.kingdom_manager.get_kingdom(str(spec["id"]))
		_check(kingdom != null, "王国存在: %s" % str(spec["name"]))
		if kingdom == null:
			continue
		_check(kingdom.kingdom_name == str(spec["name"]), "王国名称正确: %s" % str(spec["name"]))
		_check(kingdom.people_name == str(spec["people"]), "民族配置正确: %s" % str(spec["people"]))
		_check(kingdom.ruling_house_id == str(spec["ruler"]), "统治家族正确: %s" % str(spec["name"]))
		for vassal: String in spec["vassals"] as Array:
			_check(kingdom.has_vassal(vassal), "附庸关系正确: %s" % vassal)
		_check(kingdom.enemy_kingdom_ids.is_empty(), "初始没有发明战争: %s" % str(spec["name"]))
		var king := _context.kingdom_manager.get_king(kingdom.kingdom_id)
		_check(king != null and king.is_king, "国王有效: %s" % str(spec["name"]))

	# 旧世界确认的所有权保留；其余地点无主。旗帜（family_id）不参与该判断。
	var owned: Dictionary = {
		"巴里": WorldInitializer.HOUSE_BARI_ID,
		"灰石堡垒": WorldInitializer.HOUSE_BARI_ID,
		"墨西西": WorldInitializer.HOUSE_MOXIXI_ID,
		"北境村": WorldInitializer.HOUSE_MOXIXI_ID,
		"伯克纳尼亚": WorldInitializer.HOUSE_BURKNANIA_ID,
		"伯克纳": WorldInitializer.HOUSE_BURKNANIA_ID,
		"奥林德斯堡": WorldInitializer.HOUSE_OLIN_ID,
		"奥林": WorldInitializer.HOUSE_OLIN_ID,
		"青禾村": WorldInitializer.HOUSE_PLAYER_ID,
	}
	var owner_count: int = 0
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement.has_owner():
			owner_count += 1
			_check(
				owned.get(settlement.display_name, "") == settlement.owner_house_id,
				"保留旧归属: %s" % settlement.display_name
			)
	_check(owner_count == owned.size(), "只有 9 个地点保留明确所有权")


func _test_flags() -> void:
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement.family_id.is_empty():
			continue
		var family := _context.family_registry.get_config(settlement.family_id)
		_check(family != null, "地点旗帜家族存在: %s" % settlement.display_name)
		if family != null and not family.banner_texture_path.is_empty():
			_check(
				ResourceLoader.exists(family.banner_texture_path),
				"旗帜资源存在: %s" % settlement.display_name
			)
	_check(
		_context.family_registry.get_config("FAMILY_KRIKA").banner_texture_path.ends_with(
			"克里卡旗帜16_16.png"
		),
		"克里卡旗帜命名已统一"
	)
	_check(
		_context.family_registry.get_config("FAMILY_BURKNANIA").banner_texture_path.ends_with(
			"伯克纳旗帜16_16.png"
		),
		"伯克纳旗帜引用已修复"
	)
	_check(
		_context.family_registry.get_config("FAMILY_VAILA") != null,
		"瓦伊拉家族配置存在（暂无专属美术）"
	)


func _settlement_inside_boundary(settlement: SettlementData) -> bool:
	var terrain := _context.world_terrain
	if terrain == null:
		return false
	return terrain.is_inside_boundary(settlement.world_position)


func _all_settlements_spaced(settlements: Array[SettlementData]) -> bool:
	for i: int in range(settlements.size()):
		for j: int in range(i + 1, settlements.size()):
			if settlements[i].world_position.distance_to(
				settlements[j].world_position
			) < MIN_SETTLEMENT_SPACING:
				return false
	return true


func _path_is_passable(terrain: WorldTerrain, path: PackedVector2Array) -> bool:
	if path.is_empty():
		return false
	for index: int in range(path.size()):
		if not terrain.is_passable(path[index]):
			return false
		if index > 0 and not terrain.is_segment_passable(path[index - 1], path[index]):
			return false
	return true


func _polygon_centroid(points: PackedVector2Array) -> Vector2:
	var total := Vector2.ZERO
	for point: Vector2 in points:
		total += point
	return total / maxf(1.0, float(points.size()))


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
