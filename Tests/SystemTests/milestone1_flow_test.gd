extends Node
## 端到端流程测试：新游戏 -> 大地图 -> 移动 -> 保存 -> 主菜单 -> 读档。
## 测试节点会主动脱离 current_scene，避免场景切换时被释放。

const TEST_SLOT: String = "__m1_flow__"

var _failed: bool = false


func _ready() -> void:
	# 场景切换只释放 current_scene；测试节点作为 root 的普通子节点保留。
	get_tree().current_scene = null
	await get_tree().process_frame
	await _run()
	_cleanup()
	if _failed:
		push_error("[flow] 测试失败")
		get_tree().quit(1)
	else:
		print("[flow] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	_check(GameManager.start_new_game(), "New Game 成功")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(get_tree().current_scene != null, "新游戏后存在当前场景")
	if get_tree().current_scene != null:
		_check(get_tree().current_scene.name == "WorldMap", "新游戏进入 WorldMap")
		var entities := get_tree().current_scene.get_node_or_null("WorldEntities")
		var context := GameManager.world_context
		var expected_entities: int = (
			context.party_manager.get_all_parties().size()
				+ context.settlement_manager.get_all_settlements().size()
		) if context != null else -1
		_check(
			entities != null and entities.get_child_count() == expected_entities,
			"WorldMap 为所有部队与地点生成地图实体"
		)

	_check(GameManager.world_context != null, "GameManager 持有 WorldContext")
	if GameManager.world_context == null:
		return
	_check(GameManager.world_context.is_valid_world(), "WorldContext 数据有效")

	var player := GameManager.world_context.get_player_party()
	_check(player != null, "玩家部队存在")
	if player == null:
		return

	var start_position := player.world_position
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)
	GameManager.world_context.world_map_manager.set_party_target(
		player.party_id, start_position + Vector2(180.0, 0.0)
	)
	await get_tree().create_timer(0.45).timeout
	_check(player.world_position.distance_to(start_position) > 5.0, "1x 下玩家部队真实移动")
	_check(TimeManager.world_elapsed_seconds > 0.0, "1x 下世界时间推进")
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)

	var saved_position := player.world_position
	var saved_time := TimeManager.world_elapsed_seconds
	_check(GameManager.save_game(TEST_SLOT) == OK, "流程中保存成功")
	_check(SaveManager.get_latest_save_slot() == TEST_SLOT, "Continue 选中最新有效存档")

	GameManager.enter_main_menu()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(GameManager.world_context == null, "返回主菜单后销毁 WorldContext")
	if get_tree().current_scene != null:
		_check(get_tree().current_scene.name == "MainMenu", "返回 MainMenu 场景")

	_check(GameManager.load_game(TEST_SLOT), "Load Game 成功")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(get_tree().current_scene != null and get_tree().current_scene.name == "WorldMap", "读档进入 WorldMap")
	_check(GameManager.world_context != null and GameManager.world_context.is_valid_world(), "读档后世界有效")

	if GameManager.world_context != null:
		var restored := GameManager.world_context.get_player_party()
		_check(restored != null, "读档后玩家部队存在")
		if restored != null:
			_check(restored.world_position == saved_position, "读档恢复玩家位置")
		_check(
			is_equal_approx(TimeManager.world_elapsed_seconds, saved_time),
			"读档恢复世界时间"
		)

	GameManager.enter_main_menu()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(GameManager.continue_game(), "Continue 成功")
	await get_tree().process_frame
	await get_tree().process_frame
	if get_tree().current_scene != null:
		_check(get_tree().current_scene.name == "WorldMap", "Continue 进入 WorldMap")

	var game_manager_count: int = 0
	for child: Node in get_tree().root.get_children():
		if child.name == "GameManager":
			game_manager_count += 1
	_check(game_manager_count == 1, "场景切换未重复创建 Autoload")
	_check(
		get_tree().root.find_children("WorldMap", "Node2D", true, false).size() == 1,
		"场景切换未残留旧 WorldMap 节点"
	)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[flow] OK: %s" % message)
	else:
		_failed = true
		push_error("[flow] FAIL: %s" % message)


func _cleanup() -> void:
	GameManager.enter_main_menu()
	TimeManager.stop_session()
	SaveManager.delete_save(TEST_SLOT)
	_remove_if_exists(SaveManager.get_slot_path(TEST_SLOT) + ".bak")
	_remove_if_exists(SaveManager.get_slot_path(TEST_SLOT) + ".tmp")


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
