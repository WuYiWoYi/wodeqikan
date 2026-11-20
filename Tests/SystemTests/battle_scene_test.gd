extends Node
## Step 2.2 / 2.4：战斗场景生成、阵营区分、玩家移动命令、胜利判定与结算写回。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/battle_scene_test.tscn

var _failed: bool = false
var _context: WorldContext = null
var _battle_scene: Node2D = null
var _session: BattleSession = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[battle] 测试失败")
		get_tree().quit(1)
	else:
		print("[battle] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)

	_context = WorldContext.new()
	_context.name = "BattleSceneTestContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	var player := _context.get_player_party()
	var enemy := _find_party_by_name(WorldInitializer.TEST_ENEMY_PARTY_NAME)
	_check(player != null and enemy != null, "双方部队存在")
	if player == null or enemy == null:
		return

	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id

	var attacker_ids: Array[String] = [player.party_id]
	var defender_ids: Array[String] = [enemy.party_id]
	_session = _context.battle_manager.start_battle(
		attacker_ids, defender_ids, enemy.world_position
	)
	_check(_session != null, "创建战斗会话")
	if _session == null:
		return
	_check(is_zero_approx(TimeManager.get_effective_world_scale()), "战斗期间世界暂停")

	var packed := load("res://Scenes/Battle/battle.tscn") as PackedScene
	_battle_scene = packed.instantiate() as Node2D
	add_child(_battle_scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var characters := _battle_scene.get_node("World/Characters") as Node2D
	var actors := characters.get_children()
	_check(_battle_scene.get_actor_count() == 10, "生成 10 个士兵表现实例")
	_check(actors.size() == 10, "场景节点数量与参战单位一致")

	var seen_positions: Array[Vector2] = []
	var seen_ids: Dictionary = {}
	var correct_names: bool = true
	var correct_sides: bool = true
	for child: Node in actors:
		var actor := child as UnitActor
		if actor == null or actor.battle_state == null or actor.unit_data == null:
			correct_names = false
			continue
		var unit_id: String = actor.battle_state.unit_id
		if actor.name != "UnitActor_%s" % unit_id:
			correct_names = false
		if _session.get_unit_state(unit_id) == null:
			correct_names = false
		if seen_ids.has(unit_id):
			correct_names = false
		seen_ids[unit_id] = true

		var is_attacker: bool = _session.attacker_unit_ids.has(unit_id)
		if actor.is_player_side != is_attacker:
			correct_sides = false
		if not is_attacker and not _session.defender_unit_ids.has(unit_id):
			correct_sides = false

		var position := actor.battle_state.battle_position
		for other: Vector2 in seen_positions:
			if position.distance_to(other) < 1.0:
				correct_names = false
		seen_positions.append(position)

	_check(correct_names, "每个实例关联唯一且正确的 unit_id")
	_check(seen_ids.size() == 10, "10 个 unit_id 各不相同")
	_check(correct_sides, "玩家与敌方阵营识别正确")
	_check(seen_positions.size() == 10, "生成位置互不重叠")
	_check(player.member_unit_ids.size() == 5, "战斗不修改玩家成员关系")
	_check(enemy.member_unit_ids.size() == 5, "战斗不修改敌方成员关系")

	for unit_id: String in _session.get_all_unit_ids():
		var unit := _context.unit_manager.get_unit(unit_id)
		var state := _session.get_unit_state(unit_id)
		_check(
			unit != null and state != null and unit.current_hp == state.battle_hp,
			"战斗期间 UnitData HP 不被表现层修改: %s" % unit_id
		)

	var first_attacker_id: String = _session.attacker_unit_ids[0]
	var first_controller: UnitController = _battle_scene.get_controller(first_attacker_id)
	_check(first_controller != null, "可获取玩家单位控制器")
	if first_controller != null:
		var before_position: Vector2 = first_controller.get_position()
		_battle_scene.command_player_units(Vector2(640.0, 500.0))
		_check(first_controller.has_move_command(), "玩家点击命令被己方士兵接收")
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(
			first_controller.get_position() != before_position,
			"己方士兵响应移动命令"
		)

	var first_defender_id: String = _session.defender_unit_ids[0]
	var first_defender: UnitController = _battle_scene.get_controller(first_defender_id)
	_check(first_defender != null, "可获取敌方单位控制器")
	if first_controller != null and first_defender != null:
		var defender_start: Vector2 = first_defender.get_position()
		for i: int in range(5):
			await get_tree().physics_frame
		_check(first_defender.get_position() != defender_start, "敌方自动接近己方")

		# 清除手动移动命令，让己方恢复自动索敌。
		for unit_id: String in _session.attacker_unit_ids:
			var controller: UnitController = _battle_scene.get_controller(unit_id)
			if controller != null and controller.is_alive():
				controller.command_move(controller.get_position())
		await get_tree().physics_frame

		# 将一个敌人放入攻击范围，验证场景、控制器与 BattleUnitState 的联动。
		first_defender.state.battle_position = first_controller.get_position() + Vector2(15.0, 0.0)
		var defender_hp_before: int = first_defender.state.battle_hp
		var attacker_unit := _context.unit_manager.get_unit(first_attacker_id)
		var attacker_hp_before: int = attacker_unit.current_hp
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(first_defender.state.battle_hp < defender_hp_before, "自动索敌后造成伤害")
		_check(attacker_unit.current_hp == attacker_hp_before, "战斗伤害仍不写回 UnitData")

	# 直接清空敌方战斗 HP，验证死亡移除与胜利判定。
	for unit_id: String in _session.defender_unit_ids:
		var state := _session.get_unit_state(unit_id)
		state.battle_hp = 0
		state.alive = false
	await get_tree().physics_frame
	await get_tree().physics_frame

	var result_panel := _battle_scene.find_child("BattleResultPanel", true, false) as PanelContainer
	var result_label := _battle_scene.find_child("BattleResultLabel", true, false) as Label
	_check(result_panel != null and result_panel.visible, "一方全灭后显示战斗结果")
	_check(result_label != null and result_label.text == "战斗胜利", "敌方全灭判定为胜利")
	_check(_battle_scene.get_actor_count() == 5, "死亡士兵表现实例已移除")

	var surviving_id: String = _session.attacker_unit_ids[0]
	var surviving_state := _session.get_unit_state(surviving_id)
	surviving_state.battle_hp = 12
	_check(
		_context.battle_manager.finish_battle(
			_session.battle_id, BattleSession.BattleResult.ATTACKER_VICTORY
		),
		"执行战斗结算"
	)
	_check(_context.battle_manager.current_battle == null, "结算后清理 BattleSession")
	_check(not _context.battle_manager.finish_battle(
		_session.battle_id, BattleSession.BattleResult.ATTACKER_VICTORY
	), "同一场战斗不能重复结算")

	var surviving_unit := _context.unit_manager.get_unit(surviving_id)
	_check(surviving_unit != null and surviving_unit.current_hp == 12, "存活士兵写回剩余 HP")
	_check(player.member_unit_ids.has(surviving_id), "存活士兵保留成员关系")
	_check(player.battle_state == PartyData.BattleState.AVAILABLE, "玩家部队解锁")
	_check(enemy.battle_state == PartyData.BattleState.AVAILABLE, "敌方部队解锁")
	_check(enemy.member_unit_ids.is_empty(), "阵亡敌方成员全部移出部队")
	for unit_id: String in _session.defender_unit_ids:
		_check(_context.unit_manager.get_unit(unit_id) == null, "阵亡单位数据已清理")
	_check(
		is_equal_approx(TimeManager.get_effective_world_scale(), TimeManager.SPEED_NORMAL),
		"结算后恢复世界时间状态"
	)

	var save := _context.to_save_data()
	var restored := WorldContext.new()
	restored.name = "BattleSceneRestoredContext"
	add_child(restored)
	_check(restored.load_from_save_data(save), "战后存档可恢复")
	_check(restored.unit_manager.get_all_units().size() == 5, "战后存档只剩 5 名存活士兵")
	var restored_player := restored.party_manager.get_party(player.party_id)
	_check(
		restored_player != null and restored_player.member_unit_ids.size() == 5,
		"战后存档成员关系正确"
	)
	var restored_unit := restored.unit_manager.get_unit(surviving_id)
	_check(
		restored_unit != null and restored_unit.current_hp == 12,
		"战后存档保留剩余 HP"
	)
	restored.queue_free()


func _find_party_by_name(party_name: String) -> PartyData:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[battle] OK: %s" % message)
	else:
		_failed = true
		push_error("[battle] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_battle_scene):
		_battle_scene.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
