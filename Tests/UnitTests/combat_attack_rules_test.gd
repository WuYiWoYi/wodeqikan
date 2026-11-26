extends Node
## 统一攻击规则测试：多人围攻、独立冷却、射程判定、AI 状态与骑乘移动加成。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/combat_attack_rules_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"
const TRAINED_PATH: String = "res://Data/Units/infantry_trained.tres"
const CombatRulesScript = preload("res://Scripts/Systems/Combat/combat_rules.gd")

var _failed: bool = false
var _militia: UnitConfig = null
var _trained: UnitConfig = null
var _units: UnitManager = null


func _ready() -> void:
	_run()
	if _failed:
		push_error("[attackrules] 测试失败")
		get_tree().quit(1)
	else:
		print("[attackrules] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	_militia = load(MILITIA_PATH) as UnitConfig
	_trained = load(TRAINED_PATH) as UnitConfig
	_units = UnitManager.new()
	_units.setup(IdGenerator.new())
	_check(_militia != null and _trained != null, "加载兵种配置")
	if _militia == null or _trained == null:
		return

	_test_multi_attackers_same_target()
	_test_player_surrounded_can_attack()
	_test_mixed_foot_and_mounted_attack()
	_test_single_target_per_attack()
	_test_independent_cooldowns()
	_test_player_free_attack()
	_test_ai_range_and_state()
	_test_directional_rectangle()
	_test_player_360_directions()
	_test_weapon_range_changes_area()
	_test_spatial_collision()
	_test_move_attack_bonus()


func _test_multi_attackers_same_target() -> void:
	var target_unit := _units.create_unit(_militia, "FACTION_ENEMY")
	# 使用更高生命值，专注验证 3 名攻击者的伤害叠加而不是一击致死。
	target_unit.max_hp = 200
	target_unit.current_hp = 200
	var target := _make_controller(target_unit, Vector2(500.0, 300.0), 1)
	var attackers: Array[UnitController] = []
	var offsets: Array[Vector2] = [
		Vector2(-40.0, 0.0), Vector2(0.0, -40.0), Vector2(40.0, 0.0)
	]
	for offset: Vector2 in offsets:
		var unit := _units.create_unit(_trained, "FACTION_PLAYER")
		attackers.append(_make_controller(unit, Vector2(500.0, 300.0) + offset, 0))

	for attacker: UnitController in attackers:
		attacker.tick(0.01, [target])
	_check(target.state.battle_hp == 200 - 60, "3 名敌人可同时攻击同一目标（20×3）")
	_check(target.is_alive(), "目标仍存活")
	for attacker: UnitController in attackers:
		_check(attacker.get_attack_cooldown() > 0.0, "每个攻击者各自进入冷却")

	var attacker_hp_before: Array[int] = []
	for attacker: UnitController in attackers:
		attacker_hp_before.append(attacker.state.battle_hp)
	# 受击后短暂僵直：先推进到僵直结束，再验证可以正常反击。
	target.tick(UnitController.STAGGER_DURATION + 0.01, attackers)
	target.tick(0.01, attackers)
	var total_loss: int = 0
	for i: int in range(attackers.size()):
		total_loss += attacker_hp_before[i] - attackers[i].state.battle_hp
	_check(total_loss == 10, "被围攻单位可以同时反击其中一个敌人")

	for attacker: UnitController in attackers:
		attacker.tick(0.01, [target])
	_check(target.state.battle_hp == 200 - 60, "攻击者冷却互不影响但各自独立生效")


func _test_player_surrounded_can_attack() -> void:
	var player_unit := _units.create_unit(_militia, "FACTION_PLAYER")
	player_unit.max_hp = 300
	player_unit.current_hp = 300
	var player := _make_controller(player_unit, Vector2(500.0, 300.0), 0)
	player.set_player_controlled(true)
	var attackers: Array[UnitController] = []
	var offsets: Array[Vector2] = [
		Vector2(-40.0, 0.0), Vector2(0.0, -40.0), Vector2(40.0, 0.0)
	]
	for offset: Vector2 in offsets:
		var enemy := _make_controller(
			_units.create_unit(_trained, "FACTION_ENEMY"),
			Vector2(500.0, 300.0) + offset,
			1
		)
		attackers.append(enemy)

	for attacker: UnitController in attackers:
		attacker.tick(0.01, [player])
	_check(player.state.battle_hp == 300 - 60, "玩家被三名敌人同时攻击")
	_check(player.is_alive(), "玩家仍可战斗")
	_check(player.is_staggered(), "玩家受击后进入短暂僵直")
	_check(
		not player.player_attack_at(attackers[0].get_position(), attackers),
		"僵直期间不能启动新的攻击"
	)

	# 僵直结束后恢复反击能力。
	player.player_tick(UnitController.STAGGER_DURATION + 0.01, Vector2.ZERO)
	_check(not player.is_staggered(), "僵直结束后恢复正常状态")

	var target_hp_before: int = attackers[0].state.battle_hp
	_check(
		player.player_attack_at(attackers[0].get_position(), attackers),
		"被围攻时玩家仍能攻击其中一个敌人"
	)
	_check(
		attackers[0].state.battle_hp == target_hp_before - 10,
		"玩家反击只伤害选中的敌人"
	)


func _test_mixed_foot_and_mounted_attack() -> void:
	var target := _make_controller(
		_make_custom_unit("UNIT_BIG_TARGET", 200, 0, 0.0, false),
		Vector2(500.0, 300.0),
		1
	)
	var foot := _make_controller(
		_units.create_unit(_trained, "FACTION_PLAYER"), Vector2(460.0, 300.0), 0
	)
	var rider := _make_controller(
		_make_custom_unit("UNIT_RIDER_ATTACK", 100, 8, 85.0, true),
		Vector2(540.0, 300.0),
		0
	)
	foot.tick(0.01, [target])
	rider.tick(0.01, [target])
	_check(target.state.battle_hp == 200 - 28, "步兵与骑兵可以同时攻击同一目标")
	_check(
		foot.get_attack_cooldown() > 0.0 and rider.get_attack_cooldown() > 0.0,
		"步兵与骑兵各自进入冷却"
	)


func _test_single_target_per_attack() -> void:
	var attacker_unit := _units.create_unit(_trained, "FACTION_PLAYER")
	var attacker := _make_controller(attacker_unit, Vector2(500.0, 300.0), 0)
	var left := _make_controller(
		_units.create_unit(_militia, "FACTION_ENEMY"), Vector2(480.0, 300.0), 1
	)
	var right := _make_controller(
		_units.create_unit(_militia, "FACTION_ENEMY"), Vector2(520.0, 300.0), 1
	)
	attacker.tick(0.01, [left, right])
	var total_loss: int = (50 - left.state.battle_hp) + (50 - right.state.battle_hp)
	_check(total_loss == 20, "一次攻击只结算一个目标")
	_check(left.state.battle_hp == 50 or right.state.battle_hp == 50, "另一个目标未被伤害")


func _test_independent_cooldowns() -> void:
	var target := _make_controller(
		_units.create_unit(_militia, "FACTION_ENEMY"), Vector2(500.0, 300.0), 1
	)
	var first := _make_controller(
		_units.create_unit(_militia, "FACTION_PLAYER"), Vector2(470.0, 300.0), 0
	)
	var second := _make_controller(
		_units.create_unit(_militia, "FACTION_PLAYER"), Vector2(530.0, 300.0), 0
	)

	first.tick(0.01, [target])
	second.tick(0.01, [target])
	_check(target.state.battle_hp == 50 - 20, "两个攻击者的伤害分别结算")
	_check(first.get_attack_cooldown() > 0.0 and second.get_attack_cooldown() > 0.0,
		"两个攻击者都有独立冷却")
	first.tick(0.01, [target])
	_check(target.state.battle_hp == 30, "攻击者在自身冷却内不能重复攻击")


func _test_player_free_attack() -> void:
	var player := _make_controller(
		_units.create_unit(_trained, "FACTION_PLAYER"), Vector2(300.0, 300.0), 0
	)
	player.set_player_controlled(true)
	var enemy := _make_controller(
		_units.create_unit(_militia, "FACTION_ENEMY"), Vector2(400.0, 300.0), 1
	)

	# 射程外/无敌人：仍然释放攻击动作并进入冷却，但不造成伤害。
	_check(
		player.player_attack_at(enemy.get_position(), [enemy]),
		"射程外也能主动释放攻击"
	)
	_check(player.get_attack_cooldown() > 0.0, "自由攻击同样进入冷却")
	_check(enemy.state.battle_hp == 50, "射程外空挥不产生伤害")
	_check(player.get_last_attack_target_id().is_empty(), "未命中时不记录攻击目标")
	_check(
		player.get_last_attack_direction().dot(Vector2.RIGHT) > 0.99,
		"空挥方向仍来自鼠标世界坐标"
	)
	_check(
		not player.player_attack_at(enemy.get_position(), [enemy]),
		"冷却期间不能连续空挥"
	)
	_check(enemy.state.battle_hp == 50, "冷却期间不产生伤害")

	player.player_tick(1.1, Vector2.ZERO)
	enemy.state.battle_position = Vector2(340.0, 300.0)
	_check(player.player_attack_at(enemy.get_position(), [enemy]), "进入射程后攻击命中")
	_check(enemy.state.battle_hp == 30, "玩家攻击使用统一伤害")
	_check(player.get_last_attack_target_id() == enemy.unit_id, "命中时记录目标")
	_check(player.get_attack_cooldown() > 0.0, "有效攻击进入冷却")

	var hp_after: int = enemy.state.battle_hp
	_check(
		not player.player_attack_at(enemy.get_position(), [enemy]),
		"冷却期间再次点击无效"
	)
	_check(enemy.state.battle_hp == hp_after, "冷却期间不产生重复伤害")

	# 完全没有敌人时也能空挥，然后按正常间隔恢复。
	var fresh_player := _make_controller(
		_units.create_unit(_trained, "FACTION_PLAYER"), Vector2(300.0, 500.0), 0
	)
	fresh_player.set_player_controlled(true)
	_check(
		fresh_player.player_attack_at(Vector2(100.0, 100.0), []),
		"完全没有敌人时仍可主动空挥"
	)
	_check(fresh_player.get_attack_cooldown() > 0.0, "空挥同样消耗攻击冷却")
	_check(
		fresh_player.get_last_attack_target_id().is_empty(),
		"空挥没有虚构攻击目标"
	)

	fresh_player.player_tick(1.1, Vector2.ZERO)
	var left := _make_controller(
		_units.create_unit(_militia, "FACTION_ENEMY"), Vector2(320.0, 500.0), 1
	)
	var right := _make_controller(
		_units.create_unit(_militia, "FACTION_ENEMY"), Vector2(280.0, 500.0), 1
	)
	_check(
		fresh_player.player_attack_at(Vector2(300.0, 500.0), [left, right]),
		"范围内有敌人时攻击生效"
	)
	_check(
		(50 - left.state.battle_hp) + (50 - right.state.battle_hp) == 20,
		"玩家一次点击只伤害一个目标"
	)


func _test_ai_range_and_state() -> void:
	var attacker := _make_controller(
		_units.create_unit(_trained, "FACTION_PLAYER"), Vector2(200.0, 300.0), 0
	)
	var target := _make_controller(
		_units.create_unit(_militia, "FACTION_ENEMY"), Vector2(600.0, 300.0), 1
	)
	var max_range: float = attacker.get_attack_center_range()

	attacker.tick(0.01, [target])
	_check(target.state.battle_hp == 50, "AI 不会在射程外攻击")
	_check(attacker.get_ai_state() == UnitController.AIState.APPROACH, "AI 进入接近状态")

	var ticks: int = 0
	var first_hit_distance: float = -1.0
	while ticks < 600 and target.state.battle_hp == 50:
		var before_distance: float = attacker.get_position().distance_to(target.get_position())
		attacker.tick(0.05, [target])
		if target.state.battle_hp < 50:
			first_hit_distance = before_distance
		ticks += 1
	_check(ticks < 600, "AI 能持续推进到射程内")
	_check(target.state.battle_hp == 30, "AI 进入射程后正常攻击")
	_check(
		first_hit_distance <= max_range + attacker.unit_data.move_speed * 0.05 + 0.01,
		"AI 首次命中发生在有效射程内"
	)
	_check(attacker.get_ai_state() == UnitController.AIState.ATTACK, "AI 进入攻击状态")

	target.state.battle_position = attacker.get_position() + Vector2(220.0, 0.0)
	attacker.tick(0.6, [target])
	_check(attacker.get_ai_state() == UnitController.AIState.APPROACH, "目标离开射程后重新追击")

	target.apply_damage(9999)
	attacker.tick(0.1, [target])
	_check(attacker.get_ai_state() == UnitController.AIState.SEEK, "目标死亡后重新搜索")


func _test_directional_rectangle() -> void:
	var attacker := _make_controller(
		_units.create_unit(_trained, "FACTION_PLAYER"), Vector2(500.0, 500.0), 0
	)
	var target := _make_controller(
		_units.create_unit(_militia, "FACTION_ENEMY"), Vector2(540.0, 500.0), 1
	)
	var forward_length: float = CombatRulesScript.attack_forward_length(attacker.unit_data)
	_check(is_equal_approx(forward_length, 52.0), "武器前向距离 = 20 + 身体直径 + 6")

	target.state.battle_position = Vector2(540.0, 500.0)
	_check(
		CombatRulesScript.is_in_attack_area(attacker, target, Vector2.RIGHT),
		"正前方目标在矩形内"
	)
	target.state.battle_position = Vector2(460.0, 500.0)
	_check(
		not CombatRulesScript.is_in_attack_area(attacker, target, Vector2.RIGHT),
		"攻击者背后的目标不被命中"
	)
	target.state.battle_position = Vector2(530.0, 530.0)
	_check(
		not CombatRulesScript.is_in_attack_area(attacker, target, Vector2.RIGHT),
		"矩形横向宽度外的目标不被命中"
	)
	target.state.battle_position = Vector2(560.0, 500.0)
	_check(
		not CombatRulesScript.is_in_attack_area(attacker, target, Vector2.RIGHT),
		"前向长度外的目标不被命中"
	)
	target.state.battle_position = Vector2(530.0, 515.0)
	_check(
		CombatRulesScript.is_in_attack_area(attacker, target, Vector2.RIGHT),
		"矩形内的斜向目标可以被命中"
	)


func _test_player_360_directions() -> void:
	var player := _make_controller(
		_units.create_unit(_trained, "FACTION_PLAYER"), Vector2(500.0, 500.0), 0
	)
	player.set_player_controlled(true)
	var targets: Array[UnitController] = []
	var target_specs: Array[Dictionary] = [
		{"pos": Vector2(470.0, 500.0), "dir": Vector2.LEFT},
		{"pos": Vector2(530.0, 500.0), "dir": Vector2.RIGHT},
		{"pos": Vector2(500.0, 470.0), "dir": Vector2.UP},
		{"pos": Vector2(500.0, 530.0), "dir": Vector2.DOWN},
	]
	for spec: Dictionary in target_specs:
		targets.append(_make_controller(
			_units.create_unit(_militia, "FACTION_ENEMY"),
			spec["pos"] as Vector2,
			1
		))

	for i: int in range(target_specs.size()):
		var target: UnitController = targets[i]
		var hp_before: Array[int] = []
		for other: UnitController in targets:
			hp_before.append(other.state.battle_hp)
		_check(
			player.player_attack_at(target.get_position(), targets),
			"玩家向第 %d 个方向攻击命中" % (i + 1)
		)
		var total_loss: int = 0
		for j: int in range(targets.size()):
			var loss: int = hp_before[j] - targets[j].state.battle_hp
			total_loss += loss
			if j == i:
				_check(loss == 20, "选中方向的目标受到伤害")
			else:
				_check(loss == 0, "其他方向目标不受伤")
		_check(total_loss == 20, "单次攻击只命中一个目标")
		var expected_dir: Vector2 = target_specs[i]["dir"] as Vector2
		_check(
			player.get_last_attack_direction().dot(expected_dir) > 0.99,
			"玩家记录的攻击方向与实际一致"
		)
		player.player_tick(2.0, Vector2.ZERO)

	# 同一矩形内多个目标：只选择一个。
	var left := _make_controller(
		_units.create_unit(_militia, "FACTION_ENEMY"), Vector2(530.0, 495.0), 1
	)
	var right := _make_controller(
		_units.create_unit(_militia, "FACTION_ENEMY"), Vector2(530.0, 505.0), 1
	)
	player.player_tick(2.0, Vector2.ZERO)
	_check(
		player.player_attack_at(Vector2(530.0, 500.0), [left, right]),
		"矩形内多个目标时仍执行一次攻击"
	)
	_check(
		(50 - left.state.battle_hp) + (50 - right.state.battle_hp) == 20,
		"矩形内多个目标只伤害一个"
	)


func _test_weapon_range_changes_area() -> void:
	var long_unit := _make_custom_unit("UNIT_LONG_REACH", 100, 5, 60.0, false)
	long_unit.attack_range = 20.0
	var short_unit := _make_custom_unit("UNIT_SHORT_REACH", 100, 5, 60.0, false)
	short_unit.attack_range = 14.0
	var long_attacker := _make_controller(long_unit, Vector2(500.0, 500.0), 0)
	var short_attacker := _make_controller(short_unit, Vector2(500.0, 500.0), 0)
	var target := _make_controller(
		_make_custom_unit("UNIT_EDGE_TARGET", 100, 0, 0.0, false),
		Vector2(549.0, 500.0),
		1
	)
	_check(
		CombatRulesScript.is_in_attack_area(long_attacker, target, Vector2.RIGHT),
		"较长武器可以命中 49 像素外目标"
	)
	_check(
		not CombatRulesScript.is_in_attack_area(short_attacker, target, Vector2.RIGHT),
		"较短武器不能命中同一距离目标"
	)
	_check(
		is_equal_approx(CombatRulesScript.attack_forward_length(short_unit), 46.0),
		"武器距离变化直接影响矩形长度"
	)


func _test_spatial_collision() -> void:
	var a := _make_controller(
		_units.create_unit(_militia, "FACTION_PLAYER"), Vector2(500.0, 500.0), 0
	)
	var b := _make_controller(
		_units.create_unit(_militia, "FACTION_PLAYER"), Vector2(505.0, 500.0), 0
	)
	var a_nearby: Array[UnitController] = [b]
	var b_nearby: Array[UnitController] = [a]
	a.nearby_controllers = a_nearby
	b.nearby_controllers = b_nearby
	for i: int in range(10):
		a.tick(0.1, [])
		b.tick(0.1, [])
	_check(
		a.get_position().distance_to(b.get_position()) >= UnitController.MIN_BODY_DISTANCE - 0.1,
		"重叠单位被实体碰撞推开"
	)

	var a_position_before: Vector2 = a.get_position()
	b.apply_damage(9999)
	a.tick(0.1, [])
	_check(a.get_position() == a_position_before, "死亡单位不再阻挡其他单位")


func _test_move_attack_bonus() -> void:
	var mounted := _make_custom_unit("UNIT_MOUNTED", 1000, 5, 85.0, true)
	_check(StatCalculator.compute_move_attack_bonus(mounted, true) == 2,
		"骑乘移动获得攻击加成")
	_check(StatCalculator.compute_move_attack_bonus(mounted, false) == 0,
		"骑乘停止移动后加成消失")
	mounted.move_speed = 999.0
	_check(
		StatCalculator.compute_move_attack_bonus(mounted, true)
			== StatCalculator.MOUNT_CHARGE_MAX_BONUS,
		"移动攻击加成受上限约束"
	)

	var foot := _make_custom_unit("UNIT_FOOT", 1000, 5, 60.0, false)
	_check(StatCalculator.compute_move_attack_bonus(foot, true) == 0,
		"步兵不会获得骑乘移动加成")

	# 玩家骑乘移动时攻击：5 + 2；停止后攻击：5。
	var target := _make_controller(
		_make_custom_unit("UNIT_TARGET", 1000, 0, 0.0, false), Vector2(0.0, 0.0), 1
	)
	var rider := _make_custom_unit("UNIT_RIDER", 100, 5, 85.0, true)
	var rider_controller := _make_controller(rider, Vector2(300.0, 300.0), 0)
	rider_controller.set_player_controlled(true)
	rider_controller.player_tick(0.1, Vector2.RIGHT)
	_check(rider_controller.is_moving(), "玩家保持移动输入时处于移动状态")
	target.state.battle_position = rider_controller.get_position() + Vector2(40.0, 0.0)
	_check(
		rider_controller.player_attack_at(target.get_position(), [target]),
		"骑乘移动中攻击命中"
	)
	_check(target.state.battle_hp == 1000 - 7, "骑乘移动攻击使用加成后的伤害")

	rider_controller.player_tick(1.1, Vector2.ZERO)
	_check(not rider_controller.is_moving(), "停止输入后退出移动状态")
	target.state.battle_position = rider_controller.get_position() + Vector2(40.0, 0.0)
	_check(
		rider_controller.player_attack_at(target.get_position(), [target]),
		"停止移动后仍可攻击"
	)
	_check(target.state.battle_hp == 1000 - 12, "停止移动后不再获得移动攻击加成")

	var edge_rider := _make_controller(
		_make_custom_unit("UNIT_EDGE_RIDER", 100, 5, 85.0, true), Vector2(1200.0, 400.0), 0
	)
	edge_rider.set_player_controlled(true)
	edge_rider.player_tick(0.1, Vector2.RIGHT)
	_check(not edge_rider.is_moving(), "被战场边界挡住时不算移动，不获得加成")

	var foot_controller := _make_controller(
		_make_custom_unit("UNIT_FOOT_CTRL", 100, 5, 60.0, false), Vector2(700.0, 300.0), 0
	)
	foot_controller.set_player_controlled(true)
	foot_controller.player_tick(0.1, Vector2.RIGHT)
	var foot_target := _make_controller(
		_make_custom_unit("UNIT_FOOT_TARGET", 1000, 0, 0.0, false),
		foot_controller.get_position() + Vector2(40.0, 0.0),
		1
	)
	_check(
		foot_controller.player_attack_at(foot_target.get_position(), [foot_target]),
		"步兵移动中攻击命中"
	)
	_check(foot_target.state.battle_hp == 995, "步兵移动不产生额外攻击加成")


func _make_custom_unit(
	unit_id: String, max_hp: int, attack: int, move_speed: float, mounted: bool
) -> UnitData:
	var unit := UnitData.new()
	unit.unit_id = unit_id
	unit.display_name = unit_id
	unit.max_hp = max_hp
	unit.current_hp = max_hp
	unit.attack = attack
	unit.attack_interval = 1.0
	unit.attack_range = 20.0
	unit.move_speed = move_speed
	unit.is_mounted = mounted
	if mounted:
		unit.equipment = {"MOUNT": "mount_horse_01"}
	return unit


func _make_controller(unit: UnitData, position: Vector2, side_index: int) -> UnitController:
	var state := BattleUnitState.new()
	state.unit_id = unit.unit_id
	state.party_id = "PARTY_TEST"
	state.battle_hp = unit.current_hp
	state.alive = true
	state.battle_position = position
	var controller := UnitController.new()
	controller.setup(unit, state, side_index == 0, null, Rect2(0.0, 0.0, 1200.0, 800.0))
	controller.side_index = side_index
	return controller


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[attackrules] OK: %s" % message)
	else:
		_failed = true
		push_error("[attackrules] FAIL: %s" % message)
