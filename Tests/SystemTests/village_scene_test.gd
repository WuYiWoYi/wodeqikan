extends Node
## 村庄场景测试：玩家表现、无武器、NPC 距离交互、对话关闭与越界倒计时。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/village_scene_test.tscn

var _failed: bool = false
var _context: WorldContext = null
var _village: VillageScene = null
var _player_unit: UnitData = null
var _equipment_before: Dictionary = {}
var _exit_signal_received: bool = false


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[village] 测试失败")
		get_tree().quit(1)
	else:
		print("[village] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)

	_context = WorldContext.new()
	_context.name = "VillageSceneTestContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return

	var village := _find_village()
	_check(village != null, "存在村庄")
	if village == null:
		return
	_check(not village.scene_path.is_empty(), "村庄关联场景配置")
	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id
	GameManager.current_settlement_id = village.settlement_id

	var player_party := _context.get_player_party()
	for unit_id: String in player_party.member_unit_ids:
		var unit := _context.unit_manager.get_unit(unit_id)
		if unit != null and unit.is_player_character:
			_player_unit = unit
			break
	_check(_player_unit != null, "找到玩家角色")
	if _player_unit == null:
		return
	_equipment_before = _player_unit.equipment.duplicate(true)
	var unit_count_before: int = _context.unit_manager.get_all_units().size()

	var packed := load("res://Scenes/Village/village.tscn") as PackedScene
	_village = packed.instantiate() as VillageScene
	add_child(_village)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(_village.get_village_name() == village.display_name, "村庄名称来自地点数据")
	var name_label := _village.find_child("VillageNameLabel", true, false) as Label
	_check(name_label != null and name_label.text.contains(village.display_name),
		"界面显示村庄名称")

	var visual := _village.get_player_visual()
	_check(visual != null and visual.unit_data == _player_unit,
		"村庄复用玩家权威 UnitData")
	_check(visual != null and not visual.is_weapon_visible(),
		"村庄中玩家不显示武器")
	_check(_village.find_child("VillageElderVisual", true, false) != null,
		"村庄头人使用 UnitVisual 表现")

	_test_interaction_range()
	await _test_dialogue_and_movement()
	_test_exit_countdown()

	_check(_player_unit.equipment == _equipment_before, "村庄不修改玩家装备数据")
	_check(_context.unit_manager.get_all_units().size() == unit_count_before,
		"村庄不复制或删除单位")
	_check(_player_unit.current_hp > 0, "玩家权威生命值未被村庄场景改写")


func _test_interaction_range() -> void:
	_check(_village.get_player_position().distance_to(_village.get_elder_position()) > 130.0,
		"默认出生点距离村庄头人较远")
	_check(not _village.try_interact_with_elder(), "距离不足时不能触发对话")
	_check(not _village.is_dialogue_open(), "距离不足时对话保持关闭")
	var panel := _village.get_dialogue_panel()
	_check(panel != null and is_equal_approx(panel.anchor_top, 1.0),
		"对话栏锚定在屏幕下方")


func _test_dialogue_and_movement() -> void:
	_village.set_player_position(_village.get_elder_position() + Vector2(-80.0, 40.0))
	_check(_village.try_interact_with_elder(), "靠近后可以打开对话")
	_check(_village.is_dialogue_open(), "对话界面打开")

	var speaker := _village.find_child(
		"VillageDialogueSpeakerLabel", true, false
	) as Label
	var text_label := _village.find_child(
		"VillageDialogueTextLabel", true, false
	) as Label
	var choice := _village.find_child(
		"VillageDialogueChoice_0", true, false
	) as Button
	_check(speaker != null and speaker.text == "村庄头人", "对话显示 NPC 名称")
	_check(text_label != null and text_label.text.contains(_village.get_village_name()),
		"对话文本由数据配置并替换村庄名")
	_check(choice != null and choice.text == "谢谢你，我要走了", "数据驱动对话选项")

	var position_before: Vector2 = _village.get_player_position()
	_village.set_test_input(Vector2.RIGHT, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(
		_village.get_player_position().is_equal_approx(position_before),
		"对话期间玩家不能移动"
	)

	choice.pressed.emit()
	await get_tree().process_frame
	_check(not _village.is_dialogue_open(), "点击选项后关闭对话")

	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(
		_village.get_player_position().x > position_before.x,
		"关闭对话后恢复移动"
	)
	_village.set_test_input(Vector2.ZERO, false)


func _test_exit_countdown() -> void:
	_village.set_auto_return_enabled(false)
	_village.set_player_position(Vector2(40.0, 900.0))
	_village.advance_exit_countdown(1.0)
	_check(_village.get_exit_countdown() > 0.9, "越界后开始倒计时")
	var exit_label := _village.find_child("VillageExitLabel", true, false) as Label
	_check(exit_label != null and exit_label.text.contains("离开村庄"),
		"界面显示离开倒计时")

	# 返回可活动区域后取消倒计时。
	_village.set_player_position(Vector2(300.0, 900.0))
	_village.advance_exit_countdown(0.1)
	_check(is_zero_approx(_village.get_exit_countdown()), "返回边界内取消倒计时")

	_village.exit_requested.connect(_on_village_exit_requested)

	_village.set_player_position(Vector2(40.0, 900.0))
	_village.advance_exit_countdown(5.1)
	_check(_exit_signal_received, "连续越界 5 秒触发离开请求")
	_check(_village.is_returning_to_world(), "触发后进入返回状态")


func _on_village_exit_requested() -> void:
	_exit_signal_received = true


func _find_village() -> SettlementData:
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement.settlement_type == SettlementData.SettlementType.VILLAGE:
			return settlement
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[village] OK: %s" % message)
	else:
		_failed = true
		push_error("[village] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	GameManager.current_settlement_id = ""
	GameManager.pending_settlement_latch_id = ""
	if is_instance_valid(_village):
		_village.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
