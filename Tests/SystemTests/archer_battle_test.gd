extends Node
## 弓箭手系统测试：武器/兵种数据、弓表现、箭矢抛物线/假深度、高度命中、
## 固定目标坐标射空、AI 弓箭手、玩家弓箭、初始 3 名弓箭手与存档往返。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/archer_battle_test.tscn

const ARCHER_MILITIA_PATH: String = "res://Data/Units/archer_militia.tres"
const ARCHER_TRAINED_PATH: String = "res://Data/Units/archer_trained.tres"
const ARCHER_VETERAN_PATH: String = "res://Data/Units/archer_veteran.tres"
const BOW_PATH: String = "res://Data/Equipment/weapon_bow_01.tres"
const BOW_TEXTURE_PATH: String = "res://art/我的骑砍临时美术/武器弓临时.png"
const ARROW_TEXTURE_PATH: String = "res://art/我的骑砍临时美术/武器箭临时.png"

const ProjectileManagerScript = preload("res://Scripts/Systems/Combat/projectile_manager.gd")
const ArrowProjectileScript = preload("res://Scripts/Systems/Combat/arrow_projectile.gd")
const UnitActorScript = preload("res://Scripts/Systems/Combat/unit_actor.gd")
const HumanVisualScript = preload("res://Scripts/Systems/Combat/human_visual.gd")

const FACTION_PLAYER: String = "FACTION_PLAYER"
const FACTION_ENEMY: String = "FACTION_ENEMY"
const TEST_SLOT: String = "__archer_battle__"

var _failed: bool = false
var _ids: IdGenerator = null
var _units: UnitManager = null
var _archer_militia: UnitConfig = null
var _archer_trained: UnitConfig = null
var _archer_veteran: UnitConfig = null
var _bow: EquipmentConfig = null
var _root: Node2D = null
var _manager: RefCounted = null


func _ready() -> void:
	_run()
	SaveManager.delete_save(TEST_SLOT)
	if _failed:
		push_error("[archer] 测试失败")
		get_tree().quit(1)
	else:
		print("[archer] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	_setup_data()
	if _archer_militia == null or _archer_trained == null \
			or _archer_veteran == null or _bow == null:
		return

	_root = Node2D.new()
	_root.name = "ArrowTestRoot"
	add_child(_root)
	_manager = ProjectileManagerScript.new()
	_manager.setup(_root)

	_test_configs()
	_test_bow_visual()
	_test_arrow_trajectory_and_depth()
	_test_stationary_hit()
	_test_moving_target_misses()
	_test_high_arrow_passes_overhead()
	_test_dead_target_takes_no_damage()
	_test_one_arrow_one_damage()
	_test_ai_archer_fires_and_cools_down()
	_test_ai_archer_keeps_distance()
	_test_player_archer_fixed_target()
	_test_initial_party_and_save()


func _setup_data() -> void:
	_ids = IdGenerator.new()
	_units = UnitManager.new()
	_units.setup(_ids)
	_archer_militia = load(ARCHER_MILITIA_PATH) as UnitConfig
	_archer_trained = load(ARCHER_TRAINED_PATH) as UnitConfig
	_archer_veteran = load(ARCHER_VETERAN_PATH) as UnitConfig
	_bow = load(BOW_PATH) as EquipmentConfig
	_check(_archer_militia != null and _archer_trained != null
		and _archer_veteran != null, "加载三级弓箭手配置")
	_check(_bow != null, "加载临时弓配置")
	if _bow != null:
		_check(_units.register_equipment_config(_bow), "注册临时弓")


# ---------------------------------------------------------------------------
# 配置与派生数据
# ---------------------------------------------------------------------------


func _test_configs() -> void:
	_check(
		_archer_militia.tier == 1
			and _archer_militia.base_attack == 10
			and _archer_militia.base_max_hp == 50,
		"一级弓箭手基础属性 10 / 50"
	)
	_check(
		_archer_trained.tier == 2
			and _archer_trained.base_attack == 20
			and _archer_trained.base_max_hp == 100,
		"二级弓箭手基础属性 20 / 100"
	)
	_check(
		_archer_veteran.tier == 3
			and _archer_veteran.base_attack == 25
			and _archer_veteran.base_max_hp == 180,
		"三级弓箭手基础属性 25 / 180"
	)
	_check(
		_archer_militia.unit_class == UnitConfig.UnitClass.RANGED,
		"弓箭手使用远程兵种分类（仅用于显示）"
	)
	_check(
		_archer_militia.default_equipment.get("WEAPON", "") == "weapon_bow_01",
		"弓箭手默认装备弓"
	)
	_check(_bow.is_ranged_weapon(), "武器配置声明为远程攻击")
	_check(is_equal_approx(_bow.attack_interval_override, 3.0), "弓攻击间隔覆盖为 3 秒")
	_check(
		_bow.visual_anchor == Vector2(27.0, 36.0),
		"弓旋转中心按左下角 (27,12) 换算为左上角锚点 (27,36)"
	)
	var bow_texture := load(BOW_TEXTURE_PATH) as Texture2D
	var arrow_texture := load(ARROW_TEXTURE_PATH) as Texture2D
	_check(bow_texture != null and bow_texture.get_width() == 48
		and bow_texture.get_height() == 48, "弓素材为 48×48")
	_check(arrow_texture != null and arrow_texture.get_width() == 48
		and arrow_texture.get_height() == 48, "箭素材为 48×48")

	var unit: UnitData = _units.create_unit(_archer_militia, FACTION_PLAYER)
	_check(unit != null, "创建弓箭手单位")
	if unit == null:
		return
	_check(unit.is_ranged_attacker(), "攻击方式由武器派生为远程")
	_check(unit.equipment.get("WEAPON", "") == "weapon_bow_01", "单位保存弓装备")
	_check(unit.attack == 10 and unit.max_hp == 50, "弓箭手使用配置基础属性")
	_check(
		is_equal_approx(unit.attack_interval, 3.0),
		"弓把攻击冷却覆盖为 3 秒（即使兵种配置不同也一样）"
	)
	_check(is_equal_approx(unit.attack_range, 360.0), "弓提供远程射程")
	_check(unit.projectile_texture_path == ARROW_TEXTURE_PATH, "单位缓存箭矢贴图")
	_check(is_equal_approx(unit.body_height, 48.0), "步兵身体有效高度为 48")

	# 近战兵种不应被误判为远程；装备弓后才切换攻击方式。
	var militia_config: UnitConfig = load(
		"res://Data/Units/infantry_militia.tres"
	) as UnitConfig
	var melee_unit: UnitData = _units.create_unit(militia_config, FACTION_PLAYER)
	_check(melee_unit != null and not melee_unit.is_ranged_attacker(), "近战民兵保持近战攻击")
	if melee_unit != null:
		_check(_units.equip_item(melee_unit.unit_id, "weapon_bow_01"), "近战单位可装备弓")
		_check(melee_unit.is_ranged_attacker(), "装备弓后切换为远程攻击")
		_check(is_equal_approx(melee_unit.attack_interval, 3.0), "换弓后使用 3 秒攻击间隔")


# ---------------------------------------------------------------------------
# 弓表现
# ---------------------------------------------------------------------------


func _test_bow_visual() -> void:
	var unit: UnitData = _units.create_unit(_archer_militia, FACTION_PLAYER)
	var controller := _make_controller(unit, Vector2(100.0, 300.0), 0)
	var actor = UnitActorScript.new()
	_root.add_child(actor)
	actor.setup(unit, controller.state, true, {"WEAPON": _bow})

	_check(actor.visual != null and actor.visual.has_part("Weapon"), "弓箭手显示右手武器")
	var weapon_sprite: Sprite2D = actor.visual.get_part("Weapon")
	_check(
		weapon_sprite != null and weapon_sprite.texture != null
			and weapon_sprite.texture.resource_path == BOW_TEXTURE_PATH,
		"右手武器使用弓贴图"
	)
	if weapon_sprite != null:
		_check(
			weapon_sprite.offset == Vector2(-27.0, -36.0),
			"弓以指定旋转中心作为 Sprite 锚点"
		)
	var pivot: Node2D = actor.visual.get_weapon_pivot()
	_check(
		pivot != null and pivot.position == HumanVisualScript.BODY_WEAPON_ANCHOR,
		"弓使用现有 WeaponPivot 与手部锚点"
	)
	_check(is_equal_approx(actor.visual.get_facing(), -1.0), "弓默认朝左")

	actor.play_ranged_attack(Vector2.LEFT)
	_check(actor.visual.is_attack_animating(), "弓箭攻击触发拉弓动画")
	if pivot != null:
		actor.visual.advance_animation(HumanVisualScript.BOW_DRAW_TIME)
		_check(
			absf(angle_difference(pivot.rotation, 0.0)) < 0.001,
			"朝左射击时弓保持默认朝向"
		)
		actor.visual.advance_animation(HumanVisualScript.BOW_RELEASE_TIME)
		actor.visual.advance_animation(HumanVisualScript.BOW_RECOVER_TIME)
		_check(not actor.visual.is_attack_animating(), "弓箭动画结束后回到待机")
		_check(
			pivot.position.distance_to(HumanVisualScript.BODY_WEAPON_ANCHOR) < 0.01,
			"弓箭动画结束后回到手部锚点"
		)
	actor.queue_free()


# ---------------------------------------------------------------------------
# 箭矢轨迹、假深度与命中
# ---------------------------------------------------------------------------


func _test_arrow_trajectory_and_depth() -> void:
	var shooter := _make_archer_controller(Vector2(100.0, 300.0), 0)
	var arrow = ArrowProjectileScript.new()
	_root.add_child(arrow)
	arrow.setup(
		shooter,
		Vector2(100.0, 300.0),
		Vector2(500.0, 300.0),
		20.0,
		10,
		[],
		ARROW_TEXTURE_PATH,
		480.0,
		70.0
	)
	_check(
		is_equal_approx(arrow.position.y, 300.0),
		"箭矢节点出生在地面投影坐标"
	)
	_check(
		arrow.z_index == UnitActorScript.ACTOR_Z_INDEX,
		"箭矢保持基础地面 z（角色整体波段只作用于 UnitActor）"
	)
	var max_height: float = 0.0
	var ground_y_stable: bool = true
	var above_ground_mid: bool = false
	for i: int in range(100):
		arrow.advance(0.02)
		max_height = maxf(max_height, arrow.get_height())
		if not is_equal_approx(arrow.position.y, 300.0):
			ground_y_stable = false
		if arrow.get_height() > 20.0:
			above_ground_mid = true
		if arrow.is_finished():
			break
	_check(max_height > 60.0, "箭矢具有明显的抛物线高度")
	_check(above_ground_mid, "飞行过程中视觉高度高于地面")
	_check(ground_y_stable, "飞行高度不会改变地面深度坐标")
	_check(
		arrow.get_ground_position().distance_to(Vector2(500.0, 300.0)) < 1.0,
		"箭矢最终落到冻结的目标地面坐标"
	)
	_check(arrow.get_height() <= 0.5, "抵达终点时高度回到地面")
	_check(not arrow.has_hit(), "无敌人时箭矢不造成命中")
	arrow.queue_free()


func _test_stationary_hit() -> void:
	var shooter := _make_archer_controller(Vector2(100.0, 300.0), 0)
	var target := _make_enemy_archer(Vector2(500.0, 300.0))
	var hp_before: int = target.state.battle_hp
	var arrow: Variant = _spawn_arrow(shooter, target.get_position(), [target])
	_check(arrow != null, "创建射手箭矢")
	if arrow == null:
		return
	_advance_until_finished(arrow)
	_check(arrow.has_hit(), "静止目标被箭矢命中")
	_check(target.state.battle_hp == hp_before - 10, "命中造成一次攻击力伤害")
	_check(target.is_alive(), "目标仍存活")


func _test_moving_target_misses() -> void:
	var shooter := _make_archer_controller(Vector2(100.0, 300.0), 0)
	var target := _make_enemy_archer(Vector2(500.0, 300.0))
	var hp_before: int = target.state.battle_hp
	var fixed_target: Vector2 = target.get_position()
	var arrow: Variant = _spawn_arrow(shooter, fixed_target, [target])
	if arrow == null:
		return
	# 发射后目标移动到原坐标之外；箭矢仍飞向发射时保存的坐标。
	target.state.battle_position = Vector2(620.0, 300.0)
	_advance_until_finished(arrow)
	_check(not arrow.has_hit(), "目标移动后箭矢射空")
	_check(target.state.battle_hp == hp_before, "射空不造成伤害")
	_check(
		arrow.get_target_ground() == fixed_target,
		"箭矢终点不会随目标移动而修正"
	)


func _test_high_arrow_passes_overhead() -> void:
	var shooter := _make_archer_controller(Vector2(100.0, 300.0), 0)
	# 敌人位于抛物线最高点附近，但箭矢目标坐标处没有敌人。
	var overhead := _make_enemy_archer(Vector2(300.0, 300.0))
	var hp_before: int = overhead.state.battle_hp
	var arrow: Variant = _spawn_arrow(shooter, Vector2(500.0, 300.0), [overhead])
	if arrow == null:
		return
	_advance_until_finished(arrow)
	_check(not arrow.has_hit(), "高空飞行的箭矢不会命中下方敌人")
	_check(overhead.state.battle_hp == hp_before, "从头顶经过不造成伤害")
	_check(overhead.is_alive(), "头顶经过不改变敌人存活状态")


func _test_dead_target_takes_no_damage() -> void:
	var shooter := _make_archer_controller(Vector2(100.0, 300.0), 0)
	var target := _make_enemy_archer(Vector2(500.0, 300.0))
	target.apply_damage(9999)
	_check(not target.is_alive(), "测试目标已死亡")
	var arrow: Variant = _spawn_arrow(shooter, target.get_position(), [target])
	if arrow == null:
		return
	_advance_until_finished(arrow)
	_check(not arrow.has_hit(), "飞行中的箭矢不会命中已死亡目标")
	_check(target.state.battle_hp == 0, "死亡目标生命值不会再次变化")


func _test_one_arrow_one_damage() -> void:
	var shooter := _make_archer_controller(Vector2(100.0, 300.0), 0)
	var first := _make_enemy_archer(Vector2(500.0, 300.0))
	var second := _make_enemy_archer(Vector2(505.0, 300.0))
	var first_hp: int = first.state.battle_hp
	var second_hp: int = second.state.battle_hp
	var arrow: Variant = _spawn_arrow(shooter, first.get_position(), [first, second])
	if arrow == null:
		return
	_advance_until_finished(arrow)
	var total_loss: int = (
		first_hp - first.state.battle_hp
	) + (second_hp - second.state.battle_hp)
	_check(arrow.has_hit(), "重叠的敌人中命中一个")
	_check(total_loss == 10, "一支箭最多造成一次伤害")
	_check(
		first.state.battle_hp == first_hp or second.state.battle_hp == second_hp,
		"另一名重叠敌人不受伤"
	)


# ---------------------------------------------------------------------------
# AI 弓箭手
# ---------------------------------------------------------------------------


func _test_ai_archer_fires_and_cools_down() -> void:
	var archer := _make_archer_controller(Vector2(100.0, 300.0), 0)
	var target := _make_enemy_archer(Vector2(400.0, 300.0))
	var enemies: Array[UnitController] = [target]
	var start_position: Vector2 = archer.get_position()
	var hp_before: int = target.state.battle_hp

	archer.tick(0.01, enemies)
	_check(_manager.get_active_count() == 1, "AI 弓箭手在射程内发射一支箭")
	_check(is_equal_approx(archer.get_attack_cooldown(), 3.0), "发射后进入 3 秒冷却")
	_check(
		archer.get_position().distance_to(start_position) < 0.01,
		"射程内不向敌人冲锋"
	)
	_check(archer.get_ai_state() == UnitController.AIState.ATTACK, "AI 进入攻击状态")
	_manager.advance(1.0)
	_check(target.state.battle_hp == hp_before - 10, "箭矢按统一伤害结算")

	archer.tick(0.5, enemies)
	_check(_manager.get_active_count() == 0, "3 秒内不会连续射第二支箭")
	archer.tick(3.0, enemies)
	_check(_manager.get_active_count() == 1, "冷却结束后可以再次射击")
	_manager.clear()


func _test_ai_archer_keeps_distance() -> void:
	# 射程外：向敌人接近，而不是原地不动。
	var far_archer := _make_archer_controller(Vector2(100.0, 300.0), 0)
	var far_target := _make_enemy_archer(Vector2(700.0, 300.0))
	var far_enemies: Array[UnitController] = [far_target]
	var start_x: float = far_archer.get_position().x
	far_archer.tick(0.1, far_enemies)
	_check(_manager.get_active_count() == 0, "射程外不发射")
	_check(far_archer.get_ai_state() == UnitController.AIState.APPROACH, "射程外进入接近状态")
	_check(far_archer.get_position().x > start_x, "射程外向敌人接近")

	# 接近到射程内后重新开始射击。
	var fired: bool = false
	for i: int in range(500):
		far_archer.tick(0.05, far_enemies)
		if _manager.get_active_count() > 0:
			fired = true
			break
	_check(fired, "接近到射程内后开始射击")
	_manager.clear()

	# 敌人贴脸：弓箭手后撤拉开距离。
	var close_archer := _make_archer_controller(Vector2(400.0, 300.0), 0)
	var close_target := _make_enemy_archer(Vector2(450.0, 300.0))
	var close_enemies: Array[UnitController] = [close_target]
	var close_start: Vector2 = close_archer.get_position()
	close_archer.tick(0.1, close_enemies)
	_check(
		close_archer.get_position().x < close_start.x,
		"敌人贴脸时弓箭手向后退"
	)
	_manager.clear()


# ---------------------------------------------------------------------------
# 玩家弓箭
# ---------------------------------------------------------------------------


func _test_player_archer_fixed_target() -> void:
	var player := _make_archer_controller(Vector2(100.0, 300.0), 0)
	player.set_player_controlled(true)
	var target := _make_enemy_archer(Vector2(400.0, 300.0))
	var enemies: Array[UnitController] = [target]
	var hp_before: int = target.state.battle_hp

	_check(
		player.player_attack_at(Vector2(400.0, 300.0), enemies),
		"玩家弓箭左键射击成功"
	)
	_check(_manager.get_active_count() == 1, "玩家射击生成一支箭")
	_check(is_equal_approx(player.get_attack_cooldown(), 3.0), "玩家弓箭冷却为 3 秒")
	_check(
		not player.player_attack_at(Vector2(400.0, 300.0), enemies),
		"冷却期间不能连续射箭"
	)

	# 发射后目标移动，箭矢仍飞向冻结坐标并射空。
	target.state.battle_position = Vector2(620.0, 300.0)
	_manager.advance(1.0)
	_check(target.state.battle_hp == hp_before, "玩家箭矢不会追踪移动目标")

	# 冷却结束后重新射击静止目标。
	target.state.battle_position = Vector2(400.0, 300.0)
	player.player_tick(3.1, Vector2.ZERO)
	_check(
		player.player_attack_at(Vector2(400.0, 300.0), enemies),
		"冷却结束后玩家可以再次射击"
	)
	_manager.advance(1.0)
	_check(target.state.battle_hp == hp_before - 10, "玩家与 AI 共用同一套伤害结算")
	_manager.clear()


# ---------------------------------------------------------------------------
# 初始部队与存档
# ---------------------------------------------------------------------------


func _test_initial_party_and_save() -> void:
	var context := WorldContext.new()
	context.name = "ArcherPartyContext"
	add_child(context)
	_check(WorldInitializer.create_new_world(context), "初始化含弓箭手的新世界")
	if not context.is_valid_world():
		context.queue_free()
		return

	var player := context.get_player_party()
	_check(player != null, "玩家部队存在")
	if player == null:
		context.queue_free()
		return
	_check(
		player.member_unit_ids.size() == WorldInitializer.PLAYER_TOTAL_MEMBER_COUNT,
		"玩家部队人数包含 3 名弓箭手"
	)
	_check(
		WorldInitializer.PLAYER_TOTAL_MEMBER_COUNT
			== WorldInitializer.PLAYER_MILITIA_COUNT
				+ WorldInitializer.PLAYER_TRAINED_COUNT
				+ WorldInitializer.PLAYER_ARCHER_COUNT + 1,
		"编制常量与弓箭手数量一致"
	)

	var archer_count: int = 0
	var all_archers_valid: bool = true
	for unit_id: String in player.member_unit_ids:
		var unit := context.unit_manager.get_unit(unit_id)
		if unit == null or not unit.config_id.begins_with("archer_"):
			continue
		archer_count += 1
		if unit.display_name.is_empty() or unit.max_hp <= 0 or unit.attack <= 0:
			all_archers_valid = false
		if unit.equipment.get("WEAPON", "") != "weapon_bow_01":
			all_archers_valid = false
		if not unit.is_ranged_attacker():
			all_archers_valid = false
		if not is_equal_approx(unit.attack_interval, 3.0):
			all_archers_valid = false
	_check(archer_count == WorldInitializer.PLAYER_ARCHER_COUNT, "新游戏生成 3 名弓箭手")
	_check(all_archers_valid, "每名弓箭手都有完整数据、弓装备与 3 秒冷却")

	var save := context.to_save_data()
	_check(SaveManager.save_game(TEST_SLOT, save) == OK, "保存含弓箭手的存档")
	var loaded := SaveManager.load_game(TEST_SLOT)
	_check(loaded != null, "读取含弓箭手的存档")
	if loaded != null:
		var restored := WorldContext.new()
		restored.name = "ArcherPartyRestoredContext"
		add_child(restored)
		_check(restored.load_from_save_data(loaded), "恢复含弓箭手的世界")
		if restored.is_valid_world():
			var restored_player := restored.get_player_party()
			_check(
				restored_player.member_unit_ids.size()
					== WorldInitializer.PLAYER_TOTAL_MEMBER_COUNT,
				"读档后弓箭手数量不变"
			)
			var restored_archers: int = 0
			var restored_bows: bool = true
			for unit_id: String in restored_player.member_unit_ids:
				var unit := restored.unit_manager.get_unit(unit_id)
				if unit == null or not unit.config_id.begins_with("archer_"):
					continue
				restored_archers += 1
				if unit.equipment.get("WEAPON", "") != "weapon_bow_01":
					restored_bows = false
				if not unit.is_ranged_attacker():
					restored_bows = false
			_check(
				restored_archers == WorldInitializer.PLAYER_ARCHER_COUNT,
				"读档后弓箭手不会丢失或重复生成"
			)
			_check(restored_bows, "读档后弓装备与远程攻击方式保持不变")
			_check(
				restored.unit_manager.get_all_units().size()
					== context.unit_manager.get_all_units().size(),
				"读档不会重复生成单位"
			)
		restored.queue_free()
	context.queue_free()


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------


func _make_archer_controller(position: Vector2, side_index: int) -> UnitController:
	var unit: UnitData = _units.create_unit(_archer_militia, FACTION_PLAYER)
	return _make_controller(unit, position, side_index)


func _make_enemy_archer(position: Vector2) -> UnitController:
	var unit: UnitData = _units.create_unit(_archer_militia, FACTION_ENEMY)
	return _make_controller(unit, position, 1)


func _make_controller(
	unit: UnitData, position: Vector2, side_index: int
) -> UnitController:
	var state := BattleUnitState.new()
	state.unit_id = unit.unit_id
	state.party_id = "PARTY_ARCHER_TEST"
	state.battle_hp = unit.current_hp
	state.alive = true
	state.battle_position = position
	var controller := UnitController.new()
	controller.setup(
		unit, state, side_index == 0, null, Rect2(0.0, 0.0, 1280.0, 720.0)
	)
	controller.side_index = side_index
	controller.set_projectile_manager(_manager)
	return controller


func _spawn_arrow(
	shooter: UnitController, target_ground: Vector2, enemies: Array
) -> Variant:
	var ok: bool = _manager.spawn_arrow(
		shooter,
		target_ground,
		enemies,
		shooter.get_attack_damage(),
		shooter.unit_data.projectile_texture_path,
		shooter.unit_data.projectile_speed,
		shooter.unit_data.projectile_arc_height
	)
	if not ok:
		return null
	var arrows: Array = _manager.get_arrows()
	return arrows.back()


func _advance_until_finished(arrow: Variant) -> void:
	for i: int in range(300):
		if arrow.is_finished():
			return
		arrow.advance(0.02)
	_check(arrow.is_finished(), "箭矢在有限时间内结束飞行")
	_manager.clear()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[archer] OK: %s" % message)
	else:
		_failed = true
		push_error("[archer] FAIL: %s" % message)
