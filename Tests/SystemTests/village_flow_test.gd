extends Node
## 端到端村庄流程：大地图 → 进入村庄 → 对话 → 越界 5 秒 → 返回大地图。
## 测试节点主动脱离 current_scene，避免场景切换时被释放。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/village_flow_test.tscn

var _failed: bool = false
var _village_id: String = ""
var _member_ids: Array[String] = []
var _hero_equipment: Dictionary = {}
var _party_position := Vector2.ZERO


func _ready() -> void:
	get_tree().current_scene = null
	await get_tree().process_frame
	await _run()
	_cleanup()
	if _failed:
		push_error("[vflow] 测试失败")
		get_tree().quit(1)
	else:
		print("[vflow] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	_check(GameManager.start_new_game(), "New Game 成功")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(get_tree().current_scene != null and get_tree().current_scene.name == "WorldMap",
		"新游戏进入大地图")
	if get_tree().current_scene == null:
		return

	var context := GameManager.world_context
	_check(context != null and context.is_valid_world(), "WorldContext 有效")
	if context == null:
		return
	var player := context.get_player_party()
	_check(player != null, "玩家部队存在")
	if player == null:
		return

	var village := _find_village(context)
	_check(village != null, "找到可进入的村庄")
	if village == null:
		return
	_village_id = village.settlement_id
	# 模拟玩家已走到村庄入口后进入。
	player.world_position = village.world_position
	_member_ids = player.member_unit_ids.duplicate()
	_party_position = player.world_position
	var hero := _find_player_hero(context, player)
	_check(hero != null, "找到玩家角色")
	if hero != null:
		_hero_equipment = hero.equipment.duplicate(true)

	var world_map := get_tree().current_scene
	_check(world_map.has_method("enter_village"), "大地图提供进入村庄入口")
	var entered: bool = bool(world_map.call("enter_village", _village_id))
	_check(entered, "进入村庄调用成功")
	await get_tree().process_frame
	await get_tree().process_frame

	_check(get_tree().current_scene != null and get_tree().current_scene.name == "Village",
		"切换到村庄场景")
	_check(GameManager.current_settlement_id == _village_id, "记录当前村庄 ID")
	_check(TimeManager.has_pause_reason(GameManager.PAUSE_REASON_SMALL_SCENE),
		"村庄场景保持世界暂停")
	var village_scene := get_tree().current_scene as VillageScene
	_check(village_scene != null, "村庄场景控制器可用")
	if village_scene == null:
		return

	var visual := village_scene.get_player_visual()
	_check(visual != null and visual.unit_data == hero, "村庄使用玩家现有 UnitData")
	_check(visual != null and not visual.is_weapon_visible(), "村庄中不显示武器")
	if hero != null:
		_check(hero.equipment == _hero_equipment, "进入村庄不修改玩家装备数据")

	village_scene.set_player_position(
		village_scene.get_elder_position() + Vector2(-80.0, 40.0)
	)
	_check(village_scene.try_interact_with_elder(), "与村庄头人对话")
	_check(village_scene.is_dialogue_open(), "对话界面打开")
	var choice := village_scene.find_child(
		"VillageDialogueChoice_0", true, false
	) as Button
	_check(choice != null, "对话选项存在")
	if choice != null:
		choice.pressed.emit()
		await get_tree().process_frame
	_check(not village_scene.is_dialogue_open(), "点击选项关闭对话")

	# 连续越界 5 秒后自动返回。
	village_scene.set_player_position(Vector2(40.0, 900.0))
	village_scene.advance_exit_countdown(5.1)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_check(get_tree().current_scene != null and get_tree().current_scene.name == "WorldMap",
		"越界 5 秒后返回大地图")
	_check(not TimeManager.has_pause_reason(GameManager.PAUSE_REASON_SMALL_SCENE),
		"返回后清理 small_scene 暂停")
	_check(not TimeManager.has_pause_reason(GameManager.PAUSE_REASON_WORLD_DIALOGUE),
		"返回后清理对话暂停")
	_check(is_zero_approx(TimeManager.get_base_world_speed()),
		"返回后恢复进入前的大地图倍率")
	_check(GameManager.pending_settlement_latch_id.is_empty(),
		"返回大地图后消费一次性地点交互锁")

	if get_tree().current_scene != null:
		var returned_map := get_tree().current_scene
		var latch_id: String = str(returned_map.call("get_settlement_latch_id"))
		_check(latch_id == _village_id, "村口地点交互被锁住一次")

	var restored_player := context.get_player_party()
	_check(restored_player != null, "返回后玩家部队仍存在")
	if restored_player != null:
		_check(restored_player.member_unit_ids == _member_ids, "村庄不改变部队成员")
		_check(restored_player.world_position == _party_position, "村庄不改变大地图位置")
	if hero != null:
		_check(hero.equipment == _hero_equipment, "返回后玩家装备仍未被修改")
		var icon := get_tree().current_scene.find_child(
			"PartyIcon_%s" % context.player_party_id, true, false
		) as PartyIcon
		_check(icon != null and icon.get_count_text() == str(_member_ids.size()),
			"返回大地图后部队图标显示正确人数")

	GameManager.enter_main_menu()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(GameManager.world_context == null, "返回主菜单后销毁 WorldContext")


func _find_village(context: WorldContext) -> SettlementData:
	for settlement: SettlementData in context.settlement_manager.get_all_settlements():
		if settlement.settlement_type == SettlementData.SettlementType.VILLAGE:
			return settlement
	return null


func _find_player_hero(context: WorldContext, party: PartyData) -> UnitData:
	for unit_id: String in party.member_unit_ids:
		var unit := context.unit_manager.get_unit(unit_id)
		if unit != null and unit.is_player_character:
			return unit
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[vflow] OK: %s" % message)
	else:
		_failed = true
		push_error("[vflow] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.enter_main_menu()
