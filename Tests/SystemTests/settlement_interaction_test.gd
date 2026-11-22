extends Node
## 阶段 7 回归测试：点击地点只设置移动目标，真正到达后才打开地点面板。
## 覆盖：远距离点击、到达、路过、追逐、指令覆盖、切换地点、已在附近、
##        中途停止、城堡/城镇与原有地点面板内容。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . \
##     res://Tests/SystemTests/settlement_interaction_test.tscn

var _failed: bool = false
var _context: WorldContext = null
var _map: Node = null
var _player: PartyData = null
var _village: SettlementData = null
var _other_village: SettlementData = null
var _castle: SettlementData = null
var _town: SettlementData = null
var _panel: PanelContainer = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[settlement] 测试失败")
		get_tree().quit(1)
	else:
		print("[settlement] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)

	_context = WorldContext.new()
	_context.name = "SettlementInteractionContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return
	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id
	_player = _context.get_player_party()
	_village = _find_settlement(WorldInitializer.BARI_VILLAGE_NAME)
	_other_village = _find_settlement(WorldInitializer.MOXIXI_VILLAGE_NAME)
	_castle = _find_settlement("灰石城堡")
	_check(
		_player != null and _village != null and _other_village != null
			and _castle != null,
		"找到玩家与测试地点"
	)
	if _player == null or _village == null or _other_village == null \
			or _castle == null:
		return

	var packed := load("res://Scenes/WorldMap/world_map.tscn") as PackedScene
	_map = packed.instantiate()
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame
	_panel = _map.find_child("SettlementPanel", true, false) as PanelContainer
	_check(_panel != null, "地点面板存在")
	if _panel == null:
		return

	_test_far_click_and_arrival()
	_test_near_click()
	_test_plain_move_cancels_pending()
	_test_switch_settlement_target()
	_test_midway_stop_cancels_pending()
	_test_castle_and_town()
	_test_panel_content_unchanged()
	await _test_chase_passing()
	await _test_plain_passing()


## A + B：远距离点击只移动；到达后停止、暂停并打开面板。
func _test_far_click_and_arrival() -> void:
	_prepare_player_far(_village, Vector2(600.0, 0.0))
	_click(_village)
	_check(_player.target_position == _village.world_position,
		"远距离点击设置移动目标")
	_check(_player.movement_state == PartyData.MovementState.MOVING,
		"远距离点击开始移动")
	_check(not _panel.visible, "远距离点击不打开面板")
	_check(not _has_ui_pause(), "远距离点击不压入 ui_panel")
	_check(_pending_id() == _village.settlement_id, "记录待交互地点")

	# 移动途中即使贴近地点但尚未由移动系统停止，也不消费 pending。
	_player.world_position = _village.world_position + Vector2(20.0, 0.0)
	_player.movement_state = PartyData.MovementState.MOVING
	_map.call("_check_pending_settlement_interaction")
	_check(not _panel.visible, "移动状态中不打开面板")

	_simulate_arrival(_village)
	_check(_player.movement_state == PartyData.MovementState.IDLE, "到达后部队停止")
	_check(_pending_id().is_empty(), "到达后消费 pending")
	_check(_panel.visible, "到达后打开地点面板")
	_check(_has_ui_pause(), "到达后压入 ui_panel")
	_check(is_zero_approx(TimeManager.get_effective_world_scale()), "到达后世界暂停")
	_close_panel()


## G：已经位于交互半径内时允许直接打开，不要求无意义移动。
func _test_near_click() -> void:
	_prepare_player_far(_village, Vector2(20.0, 0.0))
	_click(_village)
	_check(_panel.visible, "已在交互半径内时直接打开面板")
	_check(_pending_id().is_empty(), "直接打开不留下 pending")
	_check(_player.movement_state == PartyData.MovementState.IDLE, "直接打开时停止部队")
	_close_panel()


## E：普通地图点击覆盖地点移动时清除 pending，经过旧地点不弹窗。
func _test_plain_move_cancels_pending() -> void:
	var far_target := Vector2(2700.0, 1900.0)
	_prepare_player_far(_village, Vector2(600.0, 0.0))
	_click(_village)
	_check(_pending_id() == _village.settlement_id, "先记录村庄 pending")

	_check(_map.call("handle_left_click", far_target), "点击普通地图位置")
	_check(_pending_id().is_empty(), "普通地图点击清除地点 pending")
	_check(_player.target_position == far_target, "移动目标改为普通位置")
	_check(_player.movement_state == PartyData.MovementState.MOVING, "继续移动")

	# 经过旧地点附近时不得因旧 pending 打开面板。
	_player.world_position = _village.world_position
	_player.movement_state = PartyData.MovementState.MOVING
	_player.target_position = far_target
	_map.call("_process", 0.016)
	_check(not _panel.visible, "覆盖指令后经过旧地点不打开面板")
	_check(_pending_id().is_empty(), "覆盖指令后 pending 保持为空")


## F：点击另一个地点直接替换 pending，只打开最终目标。
func _test_switch_settlement_target() -> void:
	_prepare_player_far(_village, Vector2(600.0, 0.0))
	_click(_village)
	_check(_pending_id() == _village.settlement_id, "先前往村庄 A")

	_click(_other_village)
	_check(_pending_id() == _other_village.settlement_id, "点击村庄 B 替换 pending")
	_check(_player.target_position == _other_village.world_position,
		"移动目标切换为村庄 B")
	_check(not _panel.visible, "切换目标途中不打开面板")

	_simulate_arrival(_other_village)
	_check(_panel.visible, "到达村庄 B 后打开面板")
	_check(str(_map.call("get_settlement_latch_id")) == _other_village.settlement_id,
		"只打开最终目标村庄 B")
	_check(_pending_id().is_empty(), "到达 B 后消费 pending")
	_close_panel()


## H：移动途中被外部停止在远处时取消 pending，不误弹面板。
func _test_midway_stop_cancels_pending() -> void:
	_prepare_player_far(_village, Vector2(600.0, 0.0))
	_click(_village)
	_check(_pending_id() == _village.settlement_id, "记录前往村庄的 pending")
	_player.world_position = _village.world_position + Vector2(-300.0, 0.0)
	_context.world_map_manager.stop_party(_player.party_id)
	_map.call("_check_pending_settlement_interaction")
	_check(not _panel.visible, "远处被停止后不打开面板")
	_check(_pending_id().is_empty(), "远处被停止后清除 pending")


## I：城堡与城镇同样必须先移动再打开。
func _test_castle_and_town() -> void:
	_prepare_player_far(_castle, Vector2(600.0, 0.0))
	_click(_castle)
	_check(_player.target_position == _castle.world_position,
		"远距离点击城堡设置移动目标")
	_check(not _panel.visible, "远距离点击城堡不立即打开")
	_simulate_arrival(_castle)
	_check(_panel.visible, "到达城堡后打开面板")
	_close_panel()

	_town = _context.settlement_manager.create_settlement(
		"测试城镇",
		SettlementData.SettlementType.TOWN,
		Vector2(2800.0, 300.0),
		WorldInitializer.PLAYER_FACTION_ID,
		60,
		50
	)
	_check(_town != null, "创建测试城镇")
	if _town == null:
		return
	_prepare_player_far(_town, Vector2(-500.0, 0.0))
	_click(_town)
	_check(_player.target_position == _town.world_position,
		"远距离点击城镇设置移动目标")
	_check(not _panel.visible, "远距离点击城镇不立即打开")
	_simulate_arrival(_town)
	_check(_panel.visible, "到达城镇后打开面板")
	_close_panel()


## 面板内容保持原有行为：自有村庄显示进入与征召入口，城堡不显示进入。
func _test_panel_content_unchanged() -> void:
	_prepare_player_far(_village, Vector2(20.0, 0.0))
	_click(_village)
	var enter_button := _map.find_child(
		"SettlementEnterButton", true, false
	) as Button
	var recruit_button := _map.find_child(
		"SettlementRecruitFiefButton", true, false
	) as Button
	_check(enter_button != null and enter_button.visible, "村庄面板仍提供进入入口")
	_check(recruit_button != null, "村庄面板仍提供采邑入口")
	_close_panel()

	_prepare_player_far(_castle, Vector2(20.0, 0.0))
	_click(_castle)
	_check(enter_button != null and not enter_button.visible,
		"城堡面板仍不提供进入入口")
	_check(recruit_button != null and not recruit_button.visible,
		"城堡面板不提供采邑入口")
	_close_panel()


## D：追逐部队时经过村庄不打开地点面板，也不打断追逐。
func _test_chase_passing() -> void:
	var merchant := _find_party(WorldInitializer.TEST_ENEMY_PARTY_NAME)
	if merchant == null:
		_check(false, "找到追逐目标")
		return
	# 追逐目标移远，避免玩家恰好站在目标旁而触发普通部队对话。
	merchant.world_position = _village.world_position + Vector2(900.0, 800.0)
	merchant.target_position = merchant.world_position
	merchant.movement_state = PartyData.MovementState.IDLE
	_prepare_player_far(_village, Vector2(500.0, 0.0))
	_player.focus_party_id = merchant.party_id
	_player.current_order = PartyData.OrderType.FOLLOW_PARTY
	_player.current_target_id = merchant.party_id
	_player.movement_state = PartyData.MovementState.MOVING
	_player.target_position = _village.world_position + Vector2(600.0, 0.0)
	_player.world_position = _village.world_position
	_map.call("_process", 0.016)
	_check(not _panel.visible, "追逐经过村庄不打开地点面板")
	_check(_pending_id().is_empty(), "追逐不创建地点 pending")
	_check(_player.focus_party_id == merchant.party_id, "追逐焦点不被地点打断")
	await get_tree().process_frame


## C：不以地点为目标的普通移动经过村庄不触发。
func _test_plain_passing() -> void:
	_prepare_player_far(_village, Vector2(0.0, 0.0))
	_player.movement_state = PartyData.MovementState.MOVING
	_player.target_position = _village.world_position + Vector2(600.0, 0.0)
	_map.call("_process", 0.016)
	_check(not _panel.visible, "普通移动经过村庄不打开面板")
	_check(_pending_id().is_empty(), "普通移动不创建地点 pending")
	_check(not _has_ui_pause(), "普通移动不压入地点面板暂停")
	await get_tree().process_frame


func _prepare_player_far(
	settlement: SettlementData, offset: Vector2
) -> void:
	_player.focus_party_id = ""
	_player.current_order = PartyData.OrderType.NONE
	_player.current_target_id = ""
	_player.world_position = settlement.world_position + offset
	_player.target_position = _player.world_position
	_player.movement_state = PartyData.MovementState.IDLE


func _click(settlement: SettlementData) -> void:
	_map.call("handle_left_click", settlement.world_position)


func _simulate_arrival(settlement: SettlementData) -> void:
	_player.world_position = settlement.world_position
	_player.target_position = settlement.world_position
	_player.movement_state = PartyData.MovementState.IDLE
	_map.call("_check_pending_settlement_interaction")


func _close_panel() -> void:
	_map.call("_on_settlement_leave_pressed")


func _pending_id() -> String:
	return str(_map.call("get_pending_settlement_interaction_id"))


func _has_ui_pause() -> bool:
	return TimeManager.has_pause_reason(GameManager.PAUSE_REASON_UI_PANEL)


func _find_settlement(display_name: String) -> SettlementData:
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement != null and settlement.display_name == display_name:
			return settlement
	return null


func _find_party(display_name: String) -> PartyData:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party != null and party.party_name == display_name:
			return party
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[settlement] OK: %s" % message)
	else:
		_failed = true
		push_error("[settlement] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_map):
		_map.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
