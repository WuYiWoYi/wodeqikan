extends Node
## Milestone 2 端到端流程：
## 大地图 → 接近 AI 部队 → 对话 → 发起战斗 → 生成士兵 → 实时战斗 → 结算 → 返回大地图 → 存档/读档。
## 测试节点主动脱离 current_scene，避免场景切换时被释放。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/milestone2_flow_test.tscn

const TEST_SLOT: String = "__m2_flow__"

const HumanVisualScript = preload(
	"res://Scripts/Systems/Combat/human_visual.gd"
)

var _failed: bool = false


func _ready() -> void:
	get_tree().current_scene = null
	await get_tree().process_frame
	await _run()
	_cleanup()
	if _failed:
		push_error("[m2flow] 测试失败")
		get_tree().quit(1)
	else:
		print("[m2flow] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.clear_pauses()
	TimeManager.stop_session()

	_check(GameManager.start_new_game(), "新游戏启动成功")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(
		get_tree().current_scene != null and get_tree().current_scene.name == "WorldMap",
		"进入大地图"
	)

	var context := GameManager.world_context
	_check(context != null and context.is_valid_world(), "WorldContext 有效")
	if context == null:
		return
	var player := context.get_player_party()
	var enemy := _find_party_by_name(context, WorldInitializer.TEST_ENEMY_PARTY_NAME)
	_check(player != null and enemy != null, "玩家与敌方部队存在")
	if player == null or enemy == null:
		return
	_check(
		player.member_unit_ids.size() == WorldInitializer.PLAYER_TOTAL_MEMBER_COUNT,
		"玩家拥有完整初始部队"
	)
	_check(enemy.member_unit_ids.size() == 5, "敌方拥有 5 名测试士兵")
	var total_units_initial: int = context.unit_manager.get_all_units().size()
	var expected_units_after: int = total_units_initial - enemy.member_unit_ids.size()

	# 商队初始位于橡木村；移到远离地点的空地，避免地点面板抢占部队对话。
	enemy.world_position = Vector2(900.0, 1500.0)
	enemy.target_position = enemy.world_position
	enemy.movement_state = PartyData.MovementState.IDLE

	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)
	player.world_position = enemy.world_position + Vector2(-20.0, 0.0)
	player.target_position = player.world_position
	player.movement_state = PartyData.MovementState.IDLE
	# 新规则：普通寻路不再自动弹窗，模拟玩家主动点击目标部队。
	player.focus_party_id = enemy.party_id

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var world_map := get_tree().current_scene
	var dialogue := world_map.find_child("PartyDialoguePanel", true, false) as PanelContainer
	_check(dialogue != null and dialogue.visible, "接近敌方后打开对话")
	_check(is_zero_approx(TimeManager.get_effective_world_scale()), "对话期间世界暂停")
	if dialogue == null or not dialogue.visible:
		return

	var fight_button := world_map.find_child("PartyFightButton", true, false) as Button
	_check(fight_button != null and not fight_button.disabled, "发起战斗按钮可用")
	if fight_button == null:
		return
	# 主动攻击先弹出确认面板，不会直接进入战斗。
	fight_button.pressed.emit()
	await get_tree().process_frame
	var attack_confirm := world_map.find_child(
		"AttackConfirmPanel", true, false
	) as PanelContainer
	_check(
		attack_confirm != null and attack_confirm.visible,
		"发起战斗先弹出攻击确认"
	)
	var confirm_button := world_map.find_child(
		"ConfirmAttackButton", true, false
	) as Button
	_check(confirm_button != null, "存在确认攻击按钮")
	if confirm_button == null:
		return
	confirm_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	_check(
		get_tree().current_scene != null and get_tree().current_scene.name == "Battle",
		"进入战斗场景"
	)
	var battle_scene := get_tree().current_scene as BattleScene
	if battle_scene == null:
		return
	# 本测试在清空敌方后立即检查结果面板；关闭胜利展示延迟。
	battle_scene.set_result_delay_enabled(false)

	var session := context.battle_manager.current_battle
	_check(session != null, "战斗会话存在")
	if session == null:
		return
	_check(
		session.attacker_unit_ids.size() == player.member_unit_ids.size(),
		"玩家全部士兵参战"
	)
	_check(session.defender_unit_ids.size() == 5, "敌方 5 名士兵参战")
	var actor_count: int = battle_scene.get_actor_count()
	_check(
		actor_count == player.member_unit_ids.size() + enemy.member_unit_ids.size(),
		"战斗场景生成全部参战士兵"
	)

	# 让一个敌人进入己方攻击范围，验证实时伤害只写 BattleUnitState。
	var first_attacker: UnitController = battle_scene.get_controller(session.attacker_unit_ids[0])
	_check(first_attacker != null, "战斗控制器已创建")
	if first_attacker == null:
		return
	var first_defender: UnitController = null
	for unit_id: String in session.defender_unit_ids:
		var candidate: UnitController = battle_scene.get_controller(unit_id)
		if candidate == null or not candidate.is_alive():
			continue
		if first_defender == null or candidate.get_position().distance_to(
			first_attacker.get_position()
		) < first_defender.get_position().distance_to(first_attacker.get_position()):
			first_defender = candidate
	_check(first_defender != null, "找到最近的敌方单位")
	if first_defender == null:
		return
	first_defender.state.battle_position = first_attacker.get_position() + Vector2(15.0, 0.0)
	var defender_hp_before: int = first_defender.state.battle_hp
	var attacker_unit := context.unit_manager.get_unit(first_attacker.unit_id)
	var attacker_world_hp: int = attacker_unit.current_hp
	if first_attacker.is_player_controlled:
		first_attacker.player_attack_at(
			first_defender.get_position(), [first_defender]
		)
	else:
		# 2 秒足以结束既有冷却，并让目标（已在 15 像素内）进入攻击。
		first_attacker.tick(2.0, [first_defender])
	_check(
		first_defender.state.battle_hp == defender_hp_before,
		"攻击前摇/戳击未到有效帧时不提前扣血"
	)
	_advance_melee_hit(first_attacker)
	_check(first_defender.state.battle_hp < defender_hp_before, "实时攻击减少战斗 HP")
	_check(attacker_unit.current_hp == attacker_world_hp, "实时攻击不写回 UnitData")

	# 直接清空敌方 HP，快速结束战斗并验证胜利结果。
	for unit_id: String in session.defender_unit_ids:
		var state := session.get_unit_state(unit_id)
		state.battle_hp = 0
		state.alive = false

	var surviving_id: String = session.attacker_unit_ids[0]
	session.get_unit_state(surviving_id).battle_hp = 12

	await get_tree().physics_frame
	await get_tree().physics_frame

	var result_panel := battle_scene.find_child("BattleResultPanel", true, false) as PanelContainer
	var result_label := battle_scene.find_child("BattleResultLabel", true, false) as Label
	_check(result_panel != null and result_panel.visible, "战斗结束显示结果")
	_check(result_label != null and result_label.text == "战斗胜利", "胜利结果正确")

	var return_button := battle_scene.find_child("BattleReturnButton", true, false) as Button
	_check(return_button != null, "结果面板包含返回大地图按钮")
	if return_button == null:
		return
	return_button.pressed.emit()
	await get_tree().process_frame
	# 胜利后若有待接收俘虏，会先进入俘虏选择界面；本测试不接收任何俘虏。
	var prisoner_panel := battle_scene.find_child(
		"PrisonerSelectionPanel", true, false
	) as Control
	if prisoner_panel != null and prisoner_panel.visible:
		var prisoner_confirm := battle_scene.find_child(
			"PrisonerConfirmButton", true, false
		) as Button
		_check(prisoner_confirm != null, "战后俘虏界面可确认")
		if prisoner_confirm != null:
			prisoner_confirm.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	_check(
		get_tree().current_scene != null and get_tree().current_scene.name == "WorldMap",
		"返回大地图"
	)
	_check(context.battle_manager.current_battle == null, "BattleSession 已清理")
	_check(player.battle_state == PartyData.BattleState.AVAILABLE, "玩家部队已解锁")
	_check(
		context.party_manager.get_party(enemy.party_id) == null,
		"敌方全员阵亡后从大地图移除"
	)
	_check(
		player.member_unit_ids.size() == WorldInitializer.PLAYER_TOTAL_MEMBER_COUNT,
		"玩家士兵存活并保留成员关系"
	)
	_check(
		player.current_target_id.is_empty() and player.focus_party_id.is_empty(),
		"玩家不再保留已消灭敌方的目标引用"
	)
	_check(
		context.unit_manager.get_all_units().size() == expected_units_after,
		"UnitManager 只保留存活士兵"
	)
	var surviving_unit := context.unit_manager.get_unit(surviving_id)
	_check(
		surviving_unit != null and surviving_unit.current_hp == 12,
		"结算写回存活士兵剩余 HP"
	)
	_check(
		is_equal_approx(TimeManager.get_effective_world_scale(), TimeManager.SPEED_NORMAL),
		"返回大地图后恢复世界时间"
	)

	_check(GameManager.save_game(TEST_SLOT) == OK, "战后保存成功")
	var loaded := SaveManager.load_game(TEST_SLOT)
	_check(loaded != null, "战后存档读取成功")
	if loaded == null:
		return
	var restored := WorldContext.new()
	restored.name = "Milestone2RestoredContext"
	add_child(restored)
	_check(restored.load_from_save_data(loaded), "战后存档恢复并通过关系校验")
	_check(
		restored.unit_manager.get_all_units().size() == expected_units_after,
		"读档后只恢复存活士兵"
	)
	var restored_player := restored.party_manager.get_party(player.party_id)
	var restored_enemy := restored.party_manager.get_party(enemy.party_id)
	_check(
		restored_player != null and restored_player.member_unit_ids.size()
			== WorldInitializer.PLAYER_TOTAL_MEMBER_COUNT,
		"读档后玩家成员关系正确"
	)
	_check(restored_enemy == null, "读档后不恢复已消灭的敌方部队")
	var restored_unit := restored.unit_manager.get_unit(surviving_id)
	_check(
		restored_unit != null and restored_unit.current_hp == 12,
		"读档后剩余 HP 正确"
	)
	restored.queue_free()


func _find_party_by_name(context: WorldContext, party_name: String) -> PartyData:
	for party: PartyData in context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


## 伤害现在发生在长矛戳击的有效帧；测试直接推进动画，避免依赖真实帧率。
func _advance_melee_hit(controller: UnitController) -> void:
	if controller == null or controller.actor == null:
		return
	controller.actor.advance_attack_animation(
		HumanVisualScript.SPEAR_WINDUP_TIME
	)
	controller.actor.advance_attack_animation(
		HumanVisualScript.SPEAR_THRUST_TIME
	)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[m2flow] OK: %s" % message)
	else:
		_failed = true
		push_error("[m2flow] FAIL: %s" % message)


func _cleanup() -> void:
	GameManager.enter_main_menu()
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	SaveManager.delete_save(TEST_SLOT)
	_remove_if_exists(SaveManager.get_slot_path(TEST_SLOT) + ".bak")
	_remove_if_exists(SaveManager.get_slot_path(TEST_SLOT) + ".tmp")


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
