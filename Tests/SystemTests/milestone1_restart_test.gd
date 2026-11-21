extends Node
## 跨进程存档测试。
## 第一次运行保存并退出；第二次运行（新进程）读取并校验。
##
## Godot ... milestone1_restart_test.tscn -- save
## Godot ... milestone1_restart_test.tscn -- load

const TEST_SLOT: String = "__m1_restart__"
const SAVED_POSITION: Vector2 = Vector2(700.0, 800.0)
const SAVED_TIME: float = 777.0

var _failed: bool = false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var phase: String = args[0] if args.size() > 0 else "save"
	if phase == "load":
		_load_phase()
	else:
		_save_phase()

	if _failed:
		push_error("[restart] 测试失败（阶段 %s）" % phase)
		get_tree().quit(1)
	else:
		print("[restart] 阶段 %s 通过" % phase)
		get_tree().quit(0)


func _save_phase() -> void:
	SaveManager.delete_save(TEST_SLOT)
	TimeManager.start_session()
	TimeManager.restore_world_time(SAVED_TIME, TimeManager.SPEED_DOUBLE)

	var context := WorldContext.new()
	context.name = "RestartSaveContext"
	add_child(context)
	_check(WorldInitializer.create_new_world(context), "写入阶段：创建世界")

	var player := context.get_player_party()
	player.world_position = SAVED_POSITION
	player.target_position = SAVED_POSITION
	player.movement_state = PartyData.MovementState.IDLE

	var save := context.to_save_data()
	_check(SaveManager.save_game(TEST_SLOT, save) == OK, "写入阶段：保存成功")
	var info := SaveManager.get_save_info(TEST_SLOT)
	_check(bool(info.get("valid", false)), "写入阶段：存档头有效")

	print("[restart] 写入世界 %s，玩家位置 %s，时间 %.1f" % [
		context.world_id, player.world_position, TimeManager.world_elapsed_seconds
	])
	TimeManager.stop_session()


func _load_phase() -> void:
	var info := SaveManager.get_save_info(TEST_SLOT)
	_check(not info.is_empty() and bool(info.get("valid", false)), "读取阶段：存档头有效")

	var save := SaveManager.load_game(TEST_SLOT)
	_check(save != null, "读取阶段：跨进程读取存档")
	if save == null:
		return

	var context := WorldContext.new()
	context.name = "RestartLoadContext"
	add_child(context)
	_check(context.load_from_save_data(save), "读取阶段：恢复 WorldContext")
	_check(context.party_manager.get_all_parties().size() == 4, "读取阶段：4 支部队")
	_check(
		context.settlement_manager.get_all_settlements().size() == 4,
		"读取阶段：4 个地点"
	)
	var player := context.get_player_party()
	_check(player != null, "读取阶段：玩家部队存在")
	if player != null:
		_check(player.world_position == SAVED_POSITION, "读取阶段：玩家位置一致")
	_check(is_equal_approx(save.world_elapsed_seconds, SAVED_TIME), "读取阶段：世界时间一致")
	_check(
		is_equal_approx(save.world_base_speed, TimeManager.SPEED_DOUBLE),
		"读取阶段：基础倍率一致"
	)
	_check(context.world_id == str(info.get("world_id", "")), "读取阶段：世界 ID 一致")

	SaveManager.delete_save(TEST_SLOT)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[restart] OK: %s" % message)
	else:
		_failed = true
		push_error("[restart] FAIL: %s" % message)
