extends Node
## 战斗场景弓箭集成测试：玩家弓箭手接管、鼠标世界坐标射击入口、
## ProjectileManager 注入、弓表现与箭矢伤害结算。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/archer_scene_test.tscn

const BOW_TEXTURE_PATH: String = "res://art/我的骑砍临时美术/武器弓临时.png"

var _failed: bool = false


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[archerscene] 测试失败")
		get_tree().quit(1)
	else:
		print("[archerscene] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)

	var context := WorldContext.new()
	context.name = "ArcherSceneTestContext"
	add_child(context)
	_check(WorldInitializer.create_new_world(context), "初始化世界")
	if not context.is_valid_world():
		return

	var player := context.get_player_party()
	var bandit := _find_party_by_ai(context, PartyData.PartyAIType.BANDIT)
	_check(player != null and bandit != null, "玩家与强盗部队存在")
	if player == null or bandit == null:
		return

	GameManager.world_context = context
	GameManager.player_party_id = context.player_party_id

	var session := context.battle_manager.start_battle(
		[player.party_id], [bandit.party_id], bandit.world_position
	)
	_check(session != null, "创建玩家与强盗的战斗")
	if session == null:
		return

	var packed := load("res://Scenes/Battle/battle.tscn") as PackedScene
	var battle_scene := packed.instantiate() as Node2D
	add_child(battle_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	battle_scene.set_result_delay_enabled(false)
	# 隔离测试：停止场景自身的 AI 推进，箭矢由测试手动推进。
	battle_scene.set_physics_process(false)
	var manager: Variant = battle_scene.get_projectile_manager()
	_check(manager != null, "战斗场景创建发射物管理器")
	if manager == null:
		return
	manager.clear()

	var archer_id: String = ""
	for unit_id: String in player.member_unit_ids:
		var unit := context.unit_manager.get_unit(unit_id)
		if unit != null and unit.config_id.begins_with("archer_"):
			archer_id = unit_id
			break
	_check(not archer_id.is_empty(), "玩家部队包含弓箭手")
	if archer_id.is_empty():
		return

	var archer := battle_scene.get_controller(archer_id) as UnitController
	_check(archer != null and archer.is_ranged_unit(), "战斗场景弓箭手识别为远程单位")
	if archer == null:
		return
	_check(archer.actor != null, "弓箭手拥有战斗表现节点")
	if archer.actor != null:
		var weapon := archer.actor.visual.get_part("Weapon") as Sprite2D
		_check(
			weapon != null and weapon.texture != null
				and weapon.texture.resource_path == BOW_TEXTURE_PATH,
			"战斗场景中弓箭手显示弓"
		)

	# 接管弓箭手；控制权切换后仍应能立即使用弓箭。
	battle_scene.call("_set_controlled_controller", archer)
	_check(
		battle_scene.get_controlled_unit_id() == archer_id,
		"玩家可以接管弓箭手"
	)

	var enemy_id: String = ""
	var enemy_ids: Array[String] = session.get_party_unit_ids(bandit.party_id)
	for candidate: String in enemy_ids:
		if battle_scene.get_controller(candidate) != null:
			enemy_id = candidate
			break
	_check(not enemy_id.is_empty(), "找到有效敌方单位")
	if enemy_id.is_empty():
		return
	var enemy := battle_scene.get_controller(enemy_id) as UnitController
	var target_ground: Vector2 = archer.get_position() + Vector2(300.0, 0.0)
	enemy.state.battle_position = target_ground
	var hp_before: int = enemy.state.battle_hp

	# 与鼠标输入共用同一个入口：传入的是已经转换好的战场世界坐标。
	_check(
		battle_scene.try_player_attack_at(target_ground),
		"玩家接管弓箭手后左键射箭"
	)
	_check(
		is_equal_approx(archer.get_attack_cooldown(), 3.0),
		"战斗场景玩家弓箭冷却为 3 秒"
	)
	_check(manager.get_active_count() == 1, "战斗场景生成一支箭")

	manager.advance(1.0)
	_check(
		enemy.state.battle_hp == hp_before - archer.get_attack_damage(),
		"箭矢命中通过现有伤害入口结算"
	)
	_check(manager.get_active_count() == 0, "命中后箭矢被清理")

	# 冷却期间再次点击不会创建第二支箭。
	_check(
		not battle_scene.try_player_attack_at(target_ground),
		"冷却期间战斗场景拒绝再次射箭"
	)
	_check(manager.get_active_count() == 0, "冷却期间不生成箭矢")

	context.battle_manager.abort_battle(session.battle_id)


func _find_party_by_ai(
	context: WorldContext, ai_type: PartyData.PartyAIType
) -> PartyData:
	for party: PartyData in context.party_manager.get_all_parties():
		if party.ai_type == ai_type:
			return party
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[archerscene] OK: %s" % message)
	else:
		_failed = true
		push_error("[archerscene] FAIL: %s" % message)


func _cleanup() -> void:
	# 不切换主菜单：本测试节点就是当前场景根，change_scene 会在 quit 前释放它。
	TimeManager.stop_session()
	TimeManager.clear_pauses()
