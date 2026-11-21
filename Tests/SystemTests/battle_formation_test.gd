extends Node
## 战斗队形集成测试：队形槽位、单位间距、多支友军 lane 分区与阵亡后重分配。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/battle_formation_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"

var _failed: bool = false
var _context: WorldContext = null
var _scene: BattleScene = null
var _session: BattleSession = null
var _player: PartyData = null
var _ally: PartyData = null
var _enemy: PartyData = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[formationint] 测试失败")
		get_tree().quit(1)
	else:
		print("[formationint] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)

	_context = WorldContext.new()
	_context.name = "FormationIntegrationContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")

	_player = _context.get_player_party()
	_enemy = _find_party_by_name(WorldInitializer.BANDIT_PARTY_NAME)
	_check(_player != null and _enemy != null, "玩家与敌人部队存在")
	if _player == null or _enemy == null:
		return

	var militia: UnitConfig = load(MILITIA_PATH) as UnitConfig
	_ally = _context.party_manager.create_party(
		WorldInitializer.PLAYER_FACTION_ID, Vector2(800.0, 700.0), "玩家援军"
	)
	for i: int in range(3):
		var unit := _context.unit_manager.create_unit(
			militia, WorldInitializer.PLAYER_FACTION_ID
		)
		_context.party_manager.add_member(_ally.party_id, unit.unit_id)

	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id
	_session = _context.battle_manager.start_battle_by_sides(
		[[_player.party_id, _ally.party_id], [_enemy.party_id]],
		_enemy.world_position
	)
	_check(_session != null, "创建双友军部队屏幕战斗")
	if _session == null:
		return

	var packed := load("res://Scenes/Battle/battle.tscn") as PackedScene
	_scene = packed.instantiate() as BattleScene
	add_child(_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame

	_check_formations()
	await _test_unit_death_reassignment()


func _check_formations() -> void:
	var player_slots := _collect_slots(_player)
	var ally_slots := _collect_slots(_ally)
	_check(player_slots.size() == 7, "玩家部队获得 7 个队形槽位")
	_check(ally_slots.size() == 3, "援军部队获得 3 个队形槽位")
	_check(_unique_count(player_slots) == player_slots.size(), "玩家部队槽位互不重复")
	_check(_unique_count(ally_slots) == ally_slots.size(), "援军槽位互不重复")

	var min_spacing: float = INF
	for i: int in range(player_slots.size()):
		for j: int in range(i + 1, player_slots.size()):
			min_spacing = minf(
				min_spacing, (player_slots[i] as Vector2).distance_to(player_slots[j])
			)
	_check(min_spacing > 20.0, "同部队槽位保持基本间距")

	var player_center := _average(player_slots)
	var ally_center := _average(ally_slots)
	_check(
		player_center.distance_to(ally_center) > 80.0,
		"多支友军部队使用不同 lane 区域"
	)

	# 所有玩家侧控制器都应获得槽位。
	for party: PartyData in [_player, _ally]:
		for unit_id: String in party.member_unit_ids:
			var controller := _scene.get_controller(unit_id)
			_check(
				controller != null and controller.has_formation_slot,
				"单位获得队形槽位: %s" % unit_id
			)


func _test_unit_death_reassignment() -> void:
	var victim_id := ""
	for unit_id: String in _player.member_unit_ids:
		var controller := _scene.get_controller(unit_id)
		if controller != null and controller.is_alive() \
				and not controller.is_player_controlled:
			victim_id = unit_id
			break
	_check(not victim_id.is_empty(), "找到用于阵亡测试的友军")
	if victim_id.is_empty():
		return

	var victim := _scene.get_controller(victim_id)
	victim.apply_damage(9999)
	for i: int in range(32):
		await get_tree().physics_frame

	var remaining_slots: Array[Vector2] = []
	for unit_id: String in _player.member_unit_ids:
		var controller := _scene.get_controller(unit_id)
		if controller == null:
			continue
		if controller.is_alive():
			_check(controller.has_formation_slot, "阵亡后存活单位仍有槽位")
			remaining_slots.append(controller.formation_slot)
	_check(
		_unique_count(remaining_slots) == remaining_slots.size(),
		"阵亡后队形槽位重新分配且不重复"
	)
	_check(
		remaining_slots.size() < 7,
		"阵亡单位不再占用队形槽位"
	)


func _collect_slots(party: PartyData) -> Array[Vector2]:
	var slots: Array[Vector2] = []
	for unit_id: String in party.member_unit_ids:
		var controller := _scene.get_controller(unit_id)
		if controller != null and controller.is_alive() and controller.has_formation_slot:
			slots.append(controller.formation_slot)
	return slots


func _average(slots: Array[Vector2]) -> Vector2:
	if slots.is_empty():
		return Vector2.ZERO
	var total := Vector2.ZERO
	for slot: Vector2 in slots:
		total += slot
	return total / float(slots.size())


func _unique_count(slots: Array[Vector2]) -> int:
	var seen: Dictionary = {}
	for slot: Vector2 in slots:
		seen["%.1f:%.1f" % [slot.x, slot.y]] = true
	return seen.size()


func _find_party_by_name(party_name: String) -> PartyData:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[formationint] OK: %s" % message)
	else:
		_failed = true
		push_error("[formationint] FAIL: %s" % message)


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
