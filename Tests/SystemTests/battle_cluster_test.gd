extends Node
## 小地图战斗集群与部署测试。
## 覆盖：双方初始距离、战场边界、接敌后单位分散、目标分流、
## 局部避让不产生严重重叠或卡死。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/battle_cluster_test.tscn

var _failed: bool = false
var _context: WorldContext = null
var _scene: BattleScene = null
var _session: BattleSession = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[cluster] 测试失败")
		get_tree().quit(1)
	else:
		print("[cluster] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)

	_context = WorldContext.new()
	_context.name = "BattleClusterContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	var player := _context.get_player_party()
	var bandit := _find_party_by_name(WorldInitializer.BANDIT_PARTY_NAME)
	_check(player != null and bandit != null, "玩家与强盗部队存在")
	if player == null or bandit == null:
		return

	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id
	_session = _context.battle_manager.start_battle(
		[player.party_id], [bandit.party_id], bandit.world_position
	)
	_check(_session != null, "创建屏幕战斗")
	if _session == null:
		return

	var packed := load("res://Scenes/Battle/battle.tscn") as PackedScene
	_scene = packed.instantiate() as BattleScene
	add_child(_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame

	var initial_gap: float = _side_centroid(0).distance_to(_side_centroid(1))
	_check(
		initial_gap >= BattleScene.INITIAL_DEPLOYMENT_DISTANCE - 80.0,
		"双方初始部署距离明显增加"
	)
	_check(_all_inside(), "初始单位全部位于战场边界内")
	_check(_formation_slots_separated(), "双方在各自半场列阵，不共用中点槽位")

	# 接近过程中不应出现严重重叠，且目标会按占用情况分流。
	for i: int in range(240):
		await get_tree().physics_frame
	_check(_all_inside(), "接近过程中单位不脱离战场边界")
	_check(_no_severe_overlap(), "接近过程中无严重重叠")
	_check(_distinct_target_count() >= 2, "多名士兵不会全部锁定同一个敌人")

	# 将双方拉近到接敌距离，观察近战阶段的分布与稳定性。
	_place_sides_for_contact()
	for i: int in range(180):
		await get_tree().physics_frame
	_check(_all_inside(), "接敌后单位仍在战场边界内")
	_check(_no_severe_overlap(), "接敌后未出现严重重叠")
	_check(_max_local_crowd() <= 5, "局部单位不会全部挤在同一点")
	_check(_lateral_spread() > 60.0, "接敌后士兵在纵深/横向形成分布")
	_check(_distinct_target_count() >= 2, "接敌后仍保持多目标分流")


func _side_centroid(side_index: int) -> Vector2:
	var total := Vector2.ZERO
	var count: int = 0
	for unit_id: String in _session.get_side_unit_ids(side_index):
		var controller := _scene.get_controller(unit_id)
		if controller != null and controller.is_alive():
			total += controller.get_position()
			count += 1
	return total / float(count) if count > 0 else Vector2.ZERO


func _formation_slots_separated() -> bool:
	var player_slot_x: float = 0.0
	var enemy_slot_x: float = 0.0
	var player_count: int = 0
	var enemy_count: int = 0
	for unit_id: String in _session.get_side_unit_ids(0):
		var controller := _scene.get_controller(unit_id)
		if controller != null and controller.has_formation_slot:
			player_slot_x += controller.formation_slot.x
			player_count += 1
	for unit_id: String in _session.get_side_unit_ids(1):
		var controller := _scene.get_controller(unit_id)
		if controller != null and controller.has_formation_slot:
			enemy_slot_x += controller.formation_slot.x
			enemy_count += 1
	if player_count == 0 or enemy_count == 0:
		return false
	player_slot_x /= float(player_count)
	enemy_slot_x /= float(enemy_count)
	return enemy_slot_x - player_slot_x >= BattleScene.SIDE_LINE_GAP * 0.5


func _all_inside() -> bool:
	var bounds := Rect2(Vector2.ZERO, BattleScene.BATTLEFIELD_SIZE)
	for unit_id: String in _session.get_all_unit_ids():
		var controller := _scene.get_controller(unit_id)
		if controller != null and controller.is_alive() \
				and not bounds.has_point(controller.get_position()):
			return false
	return true


func _no_severe_overlap() -> bool:
	var positions := _alive_positions()
	for i: int in range(positions.size()):
		for j: int in range(i + 1, positions.size()):
			if positions[i].distance_to(positions[j]) < 12.0:
				return false
	return true


func _max_local_crowd() -> int:
	var positions := _alive_positions()
	var max_crowd: int = 0
	for i: int in range(positions.size()):
		var crowd: int = 0
		for j: int in range(positions.size()):
			if i != j and positions[i].distance_to(positions[j]) < 26.0:
				crowd += 1
		max_crowd = maxi(max_crowd, crowd)
	return max_crowd


func _lateral_spread() -> float:
	var positions := _alive_positions()
	if positions.is_empty():
		return 0.0
	var min_x: float = positions[0].x
	var max_x: float = positions[0].x
	for position: Vector2 in positions:
		min_x = minf(min_x, position.x)
		max_x = maxf(max_x, position.x)
	return max_x - min_x


func _distinct_target_count() -> int:
	var targets: Dictionary = {}
	for unit_id: String in _session.get_side_unit_ids(0):
		var controller := _scene.get_controller(unit_id)
		if controller == null or not controller.is_alive():
			continue
		var target_id: String = controller.get_target_unit_id()
		if not target_id.is_empty():
			targets[target_id] = true
	return targets.size()


func _alive_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for unit_id: String in _session.get_all_unit_ids():
		var controller := _scene.get_controller(unit_id)
		if controller != null and controller.is_alive():
			positions.append(controller.get_position())
	return positions


func _place_sides_for_contact() -> void:
	# 保持各战斗侧内部相对站位，只把两侧拉到约 300 像素间距。
	for side_index: int in [0, 1]:
		var ids: Array[String] = _session.get_side_unit_ids(side_index)
		for index: int in range(ids.size()):
			var controller := _scene.get_controller(ids[index])
			if controller == null or not controller.is_alive():
				continue
			var local_x: float = float(index % 4) * 40.0
			var local_y: float = float(index / 4) * 40.0 - 40.0
			var base_x: float = 490.0 if side_index == 0 else 790.0
			controller.state.battle_position = Vector2(
				base_x + local_x, 360.0 + local_y
			)


func _find_party_by_name(party_name: String) -> PartyData:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[cluster] OK: %s" % message)
	else:
		_failed = true
		push_error("[cluster] FAIL: %s" % message)


func _cleanup() -> void:
	if _context != null and _context.battle_manager.current_battle != null:
		_context.battle_manager.abort_battle(
			_context.battle_manager.current_battle.battle_id
		)
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_scene):
		_scene.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
