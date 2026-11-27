extends Node
## 主界面事件中心测试：数据接入层只读聚合、确定性 ID、列表/详情切换、
## 状态变化后刷新、重复打开不产生重复事件。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/event_center_test.tscn

var _failed: bool = false
var _context: WorldContext = null
var _map: Node = null
var _overlay: Control = null


func _ready() -> void:
	_test_data_layer()
	await _run_ui()
	_cleanup()
	if _failed:
		push_error("[event_center] 测试失败")
		get_tree().quit(1)
	else:
		print("[event_center] 全部通过")
		get_tree().quit(0)


func _test_data_layer() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)

	_context = WorldContext.new()
	_context.name = "EventCenterTestContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return
	# 测试夹具：默认贵族身份通过家族所有权获得埃克托村庄。
	var village: SettlementData = null
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement != null and settlement.display_name == "埃克托":
			village = settlement
			break
	var player_house := _context.get_player_house()
	_check(village != null and player_house != null, "找到玩家家族封地")
	if village != null and player_house != null:
		village.owner_house_id = player_house.house_id

	var events: Array[Dictionary] = _context.event_center.get_events()
	_check(not events.is_empty(), "初始世界存在待处理事件")
	var unique: Dictionary = {}
	var fief_count: int = 0
	var adventurer_count: int = 0
	for event: Dictionary in events:
		var event_id: String = str(event.get("event_id", ""))
		_check(not event_id.is_empty(), "事件具有确定性 ID")
		_check(
			not event.get("title", "").is_empty() and not event.get("detail", "").is_empty(),
			"事件包含标题与详情"
		)
		_check(not event.get("type_text", "").is_empty(), "事件具有可区分的类型文本")
		if unique.has(event_id):
			_check(false, "事件 ID 不重复：%s" % event_id)
		unique[event_id] = true
		if str(event.get("type", "")) == "FIEF":
			fief_count += 1
		elif str(event.get("type", "")) == "ADVENTURER":
			adventurer_count += 1

	_check(fief_count >= 1, "玩家封地产生可征召事件")
	_check(adventurer_count >= 1, "村庄候选人产生冒险者事件")
	_check(
		_context.event_center.get_events_of_type("QUEST").is_empty(),
		"无任务系统时任务事件为空"
	)

	var second_ids := _collect_ids(_context.event_center.get_events())
	_check(
		second_ids == _collect_ids(events),
		"重复读取事件结果稳定，不创建新事件"
	)


func _run_ui() -> void:
	if _context == null or not _context.is_valid_world():
		return
	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id

	var packed := load("res://Scenes/WorldMap/world_map.tscn") as PackedScene
	_map = packed.instantiate()
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame

	_overlay = _map.call("get_event_center_panel") as Control
	var button := _map.find_child("EventCenterButton", true, false) as Button
	_check(_overlay != null and button != null, "顶栏存在事件入口")
	if _overlay == null or button == null:
		return

	button.pressed.emit()
	await get_tree().process_frame
	_check(_overlay.visible, "点击事件入口打开事件中心")
	_check(
		is_zero_approx(TimeManager.get_effective_world_scale()),
		"事件中心打开时世界暂停"
	)
	_check(_time_buttons_disabled(), "事件中心打开时时间控制禁用")

	var first_ids: Array[String] = _overlay.get_event_ids()
	_check(not first_ids.is_empty(), "左侧列表包含实际事件")
	_check(
		first_ids == _collect_ids(_context.event_center.get_events()),
		"界面事件与数据层一致"
	)
	_check(
		_list_has_text("已接取任务（0）") and _list_has_text("暂无已接取的任务。"),
		"任务分栏为空且显示空状态"
	)
	_check(_list_has_text("待处理事项（%d）" % first_ids.size()), "待处理事项计数正确")

	var selected: String = _overlay.get_selected_event_id()
	_check(not selected.is_empty(), "默认选中第一个事件")
	var first_detail: String = str(_overlay.get_detail_text())
	_check(not first_detail.is_empty(), "右侧显示选中事件详情")
	_check(first_detail == _detail_for(selected), "详情绑定同一事件数据")

	if first_ids.size() >= 2:
		var second: String = first_ids[1]
		_overlay.call("select_event", second)
		await get_tree().process_frame
		_check(_overlay.get_selected_event_id() == second, "点击列表切换选中事件")
		_check(
			str(_overlay.get_detail_text()) == _detail_for(second),
			"切换后详情同步更新"
		)

	_map.call("close_event_center")
	await get_tree().process_frame
	_check(not _overlay.visible, "关闭事件中心")
	_check(
		is_equal_approx(TimeManager.get_effective_world_scale(), 1.0),
		"关闭事件中心后恢复世界速度"
	)
	_check(not _time_buttons_disabled(), "关闭事件中心后恢复时间控制入口")

	# 重复打开：事件数量不变，不产生重复条目。
	button.pressed.emit()
	await get_tree().process_frame
	var reopened_ids: Array[String] = _overlay.get_event_ids()
	_check(reopened_ids == first_ids, "重复打开事件中心不产生重复事件")

	# 状态变化：玩家封地采邑储备耗尽后，对应事件从列表移除。
	var fief_event_id: String = ""
	for event: Dictionary in _context.event_center.get_events():
		if str(event.get("type", "")) == "FIEF":
			fief_event_id = str(event.get("event_id", ""))
			break
	_check(not fief_event_id.is_empty(), "找到玩家封地事件")
	if not fief_event_id.is_empty():
		for settlement: SettlementData in _context.get_player_owned_settlements():
			settlement.fief_recruitment_stock = 0
		_overlay.call("refresh_if_needed")
		await get_tree().process_frame
		_check(
			not _overlay.get_event_ids().has(fief_event_id),
			"采邑耗尽后事件从列表移除"
		)

	_map.call("close_event_center")
	await get_tree().process_frame


func _collect_ids(events: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for event: Dictionary in events:
		ids.append(str(event.get("event_id", "")))
	return ids


func _detail_for(event_id: String) -> String:
	for event: Dictionary in _context.event_center.get_events():
		if str(event.get("event_id", "")) == event_id:
			return str(event.get("detail", ""))
	return ""


func _time_buttons_disabled() -> bool:
	for node_name: String in ["PauseButton", "SpeedOneButton", "SpeedTwoButton"]:
		var button := _map.find_child(node_name, true, false) as Button
		if button == null or not button.disabled:
			return false
	return true


func _list_has_text(needle: String) -> bool:
	if _overlay == null:
		return false
	var list := _overlay.find_child("EventCenterList", true, false)
	if list == null:
		return false
	for label: Node in list.find_children("*", "Label", true, false):
		if (label as Label).text.contains(needle):
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[event_center] OK: %s" % message)
	else:
		_failed = true
		push_error("[event_center] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_map):
		_map.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
