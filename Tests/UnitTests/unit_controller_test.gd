extends Node
## UnitController 单元测试：移动、索敌、攻击间隔、伤害、死亡、重新索敌与手动移动。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/unit_controller_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"
const TRAINED_PATH: String = "res://Data/Units/infantry_trained.tres"
const FACTION_PLAYER: String = "FACTION_PLAYER"
const FACTION_ENEMY: String = "FACTION_ENEMY"

var _failed: bool = false
var _militia: UnitConfig = null
var _trained: UnitConfig = null
var _ids: IdGenerator = null
var _units: UnitManager = null


func _ready() -> void:
	_run()
	if _failed:
		push_error("[controller] 测试失败")
		get_tree().quit(1)
	else:
		print("[controller] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	_militia = load(MILITIA_PATH) as UnitConfig
	_trained = load(TRAINED_PATH) as UnitConfig
	_ids = IdGenerator.new()
	_units = UnitManager.new()
	_units.setup(_ids)
	_check(_militia != null and _trained != null, "加载兵种配置")
	if _militia == null or _trained == null:
		return

	_test_approach()
	_test_mounted_battle_speed()
	_test_attack_interval()
	_test_death_and_retarget()
	_test_manual_move()
	_test_team_battle_converges()


func _test_approach() -> void:
	var unit := _units.create_unit(_militia, FACTION_PLAYER)
	var enemy_unit := _units.create_unit(_militia, FACTION_ENEMY)
	var controller := _make_controller(unit, Vector2(100.0, 100.0), true)
	var enemy := _make_controller(enemy_unit, Vector2(400.0, 100.0), false)
	var enemies: Array[UnitController] = [enemy]

	var start := controller.get_position()
	for i: int in range(10):
		controller.tick(0.1, enemies)
	_check(controller.get_position().x > start.x + 20.0, "自动向敌人接近")
	_check(
		controller.get_position().x < start.x + 45.0,
		"战斗移动速度已降低到原速度的 60%"
	)
	_check(absf(controller.get_position().y - 100.0) < 1.0, "沿直线移动")
	_check(controller.get_position().x < 400.0, "未穿过目标")


func _test_mounted_battle_speed() -> void:
	var foot_unit := _units.create_unit(_militia, FACTION_PLAYER)
	var mounted_unit := _units.create_unit(_militia, FACTION_PLAYER)
	mounted_unit.is_mounted = true
	mounted_unit.move_speed = 85.0
	var foot := _make_controller(foot_unit, Vector2(100.0, 100.0), true)
	var mounted := _make_controller(mounted_unit, Vector2(100.0, 300.0), true)

	_check(
		is_equal_approx(foot.get_battle_move_speed(), 36.0),
		"步兵战斗移速保持 60 × 0.6"
	)
	_check(
		is_equal_approx(mounted.get_battle_move_speed(), 85.0 * 0.84),
		"骑乘战斗移速使用独立系数"
	)

	var foot_start := foot.get_position()
	var mounted_start := mounted.get_position()
	foot.command_move(foot_start + Vector2(300.0, 0.0))
	mounted.command_move(mounted_start + Vector2(300.0, 0.0))
	for i: int in range(10):
		foot.tick(0.1, [])
		mounted.tick(0.1, [])
	var foot_distance := foot_start.distance_to(foot.get_position())
	var mounted_distance := mounted_start.distance_to(mounted.get_position())
	_check(foot_distance > 0.0 and mounted_distance > 0.0, "双方直线移动")
	_check(
		mounted_distance > foot_distance * 1.8,
		"同等条件下骑乘单位明显快于步兵"
	)
	_check(foot_unit.move_speed == 60.0, "战斗速度不修改 UnitData.move_speed")


func _test_attack_interval() -> void:
	var attacker_unit := _units.create_unit(_trained, FACTION_PLAYER)
	var target_unit := _units.create_unit(_militia, FACTION_ENEMY)
	var attacker := _make_controller(attacker_unit, Vector2(100.0, 100.0), true)
	var target := _make_controller(target_unit, Vector2(120.0, 100.0), false)
	var enemies: Array[UnitController] = [target]

	_check(target.state.battle_hp == 50, "目标初始 HP 正确")
	attacker.tick(0.1, enemies)
	_check(target.state.battle_hp == 30, "进入攻击范围后造成攻击力伤害")
	attacker.tick(0.5, enemies)
	_check(target.state.battle_hp == 30, "攻击间隔内不重复攻击")
	attacker.tick(0.5, enemies)
	_check(target.state.battle_hp == 10, "攻击间隔结束后再次攻击")
	_check(attacker_unit.current_hp == 100, "攻击不修改 UnitData.current_hp")


func _test_death_and_retarget() -> void:
	var attacker_unit := _units.create_unit(_trained, FACTION_PLAYER)
	var near_unit := _units.create_unit(_militia, FACTION_ENEMY)
	var far_unit := _units.create_unit(_militia, FACTION_ENEMY)
	var attacker := _make_controller(attacker_unit, Vector2(100.0, 100.0), true)
	var near_enemy := _make_controller(near_unit, Vector2(120.0, 100.0), false)
	var far_enemy := _make_controller(far_unit, Vector2(130.0, 100.0), false)
	near_enemy.state.battle_hp = 5
	var enemies: Array[UnitController] = [near_enemy, far_enemy]

	attacker.tick(0.1, enemies)
	_check(not near_enemy.is_alive(), "HP 归零后单位死亡")
	_check(near_enemy.state.alive == false, "死亡写入 BattleUnitState")
	_check(far_enemy.state.battle_hp == 50, "首次攻击只命中最近目标")

	attacker.tick(1.1, enemies)
	attacker.tick(0.1, enemies)
	_check(far_enemy.state.battle_hp < 50, "目标死亡后重新索敌并攻击")

	var dead_position := near_enemy.get_position()
	attacker.tick(0.1, enemies)
	_check(near_enemy.get_position() == dead_position, "死亡单位不再移动")
	var before := near_enemy.state.battle_hp
	near_enemy.apply_damage(10)
	_check(near_enemy.state.battle_hp == before, "死亡单位不再受伤")


func _test_manual_move() -> void:
	var unit := _units.create_unit(_militia, FACTION_PLAYER)
	var controller := _make_controller(unit, Vector2(100.0, 100.0), true)
	controller.command_move(Vector2(200.0, 100.0))
	_check(controller.has_move_command(), "收到手动移动命令")

	var start := controller.get_position()
	for i: int in range(10):
		controller.tick(0.1, [])
	_check(controller.get_position().x > start.x + 20.0, "手动命令优先于索敌")

	for i: int in range(45):
		controller.tick(0.1, [])
	_check(not controller.has_move_command(), "到达目标后清除移动命令")


func _test_team_battle_converges() -> void:
	var player_controllers: Array[UnitController] = []
	var enemy_controllers: Array[UnitController] = []
	for i: int in range(5):
		var player_config: UnitConfig = _militia if i < 3 else _trained
		var enemy_config: UnitConfig = _militia if i < 3 else _trained
		var player_unit := _units.create_unit(player_config, FACTION_PLAYER)
		var enemy_unit := _units.create_unit(enemy_config, FACTION_ENEMY)
		player_controllers.append(_make_controller(
			player_unit, _formation_position(i, true), true
		))
		enemy_controllers.append(_make_controller(
			enemy_unit, _formation_position(i, false), false
		))

	var ticks: int = 0
	while ticks < 2000:
		var player_alive := _alive_count(player_controllers)
		var enemy_alive := _alive_count(enemy_controllers)
		if player_alive == 0 or enemy_alive == 0:
			break
		for controller: UnitController in player_controllers:
			controller.tick(0.1, enemy_controllers)
		for controller: UnitController in enemy_controllers:
			controller.tick(0.1, player_controllers)
		ticks += 1

	_check(ticks < 2000, "5v5 自动战斗能在有限时间内结束")
	_check(
		_alive_count(player_controllers) == 0 or _alive_count(enemy_controllers) == 0,
		"自动战斗以一方全灭结束"
	)
	_check(
		_alive_count(player_controllers) + _alive_count(enemy_controllers) < 10,
		"自动战斗产生实际伤亡"
	)


func _formation_position(index: int, player_side: bool) -> Vector2:
	var row: int = index / 2
	var column: int = index % 2
	var direction: float = 1.0 if player_side else -1.0
	var base_x: float = 300.0 if player_side else 980.0
	return Vector2(
		base_x + direction * float(column) * 54.0,
		360.0 + (float(row) - 1.0) * 64.0
	)


func _alive_count(controllers: Array[UnitController]) -> int:
	var count: int = 0
	for controller: UnitController in controllers:
		if controller.is_alive():
			count += 1
	return count


func _make_controller(unit: UnitData, position: Vector2, player_side: bool) -> UnitController:
	var state := BattleUnitState.new()
	state.unit_id = unit.unit_id
	state.party_id = "PARTY_TEST"
	state.battle_hp = unit.current_hp
	state.alive = true
	state.battle_position = position
	var controller := UnitController.new()
	controller.setup(unit, state, player_side, null, Rect2(0.0, 0.0, 1000.0, 600.0))
	# 测试辅助：同一阵营参数映射到不同战斗侧，满足统一敌对判断。
	controller.side_index = 0 if player_side else 1
	return controller


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[controller] OK: %s" % message)
	else:
		_failed = true
		push_error("[controller] FAIL: %s" % message)
