extends Node
## 主世界日志面板测试：左下角固定、事件自动刷新、滚动区域与地图输入不受阻挡。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/world_log_ui_test.tscn

var _failed: bool = false
var _context: WorldContext = null
var _map: Node = null
var _player: PartyData = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[logui] 测试失败")
		get_tree().quit(1)
	else:
		print("[logui] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)

	_context = WorldContext.new()
	_context.name = "WorldLogUiContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return
	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id
	_player = _context.get_player_party()

	var packed := load("res://Scenes/WorldMap/world_map.tscn") as PackedScene
	_map = packed.instantiate()
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame

	var panel := _map.find_child("WorldLogPanel", true, false) as PanelContainer
	_check(panel != null, "大地图创建世界日志面板")
	if panel == null:
		return
	_check(is_equal_approx(panel.anchor_top, 1.0), "日志面板锚定屏幕底部")
	_check(is_equal_approx(panel.anchor_bottom, 1.0), "日志面板固定在左下角")
	_check(is_equal_approx(panel.anchor_left, 0.0), "日志面板锚定屏幕左侧")
	_check(panel.offset_left >= 0.0 and panel.offset_bottom < 0.0, "日志面板位于左下角可视区域内")
	_check(
		panel.mouse_filter != Control.MOUSE_FILTER_STOP,
		"日志面板不会永久吞掉地图点击"
	)
	var scroll := panel.find_child("WorldLogScroll", true, false) as ScrollContainer
	_check(scroll != null, "日志面板包含滚动区域")
	_check(
		scroll != null
		and scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO,
		"日志超出高度时支持滚动"
	)
	var title := panel.find_child("WorldLogTitle", true, false) as Label
	_check(title != null and title.text == "世界日志", "日志面板保留标题节点")
	_check(
		not title.visible and not scroll.visible,
		"默认折叠：标题与滚动条隐藏"
	)
	var collapsed_label := panel.find_child(
		"WorldLogCollapsedText", true, false
	) as Label
	_check(
		collapsed_label != null and collapsed_label.visible,
		"默认折叠：仅保留事件文本"
	)

	_check(_map.call("get_world_log_entry_count") == 0, "初始日志为空")
	_context.world_log_manager.add_event(
		WorldLogEntry.EventType.OTHER, "第一条世界事件"
	)
	await get_tree().process_frame
	var text: String = str(_map.call("get_world_log_text"))
	_check(text.contains("第一条世界事件"), "新日志自动显示在面板数据中")
	_check(_count_entry_labels() == 1, "日志面板实时生成一条条目")
	_check(
		collapsed_label != null
			and collapsed_label.text.contains("第一条世界事件"),
		"折叠状态持续更新最新事件文本"
	)

	_test_collapse_interaction(panel, title, scroll, collapsed_label)

	var village := _first_village()
	if village != null:
		EventBus.settlement_entered.emit(village.settlement_id, _player.party_id)
		await get_tree().process_frame
		text = str(_map.call("get_world_log_text"))
		_check(text.contains("玩家进入了%s" % village.display_name), "进入村庄事件显示在日志中")
		EventBus.settlement_exited.emit(village.settlement_id, _player.party_id)
		await get_tree().process_frame
		text = str(_map.call("get_world_log_text"))
		_check(text.contains("玩家离开了%s" % village.display_name), "离开村庄事件显示在日志中")

	for i: int in range(8):
		_context.world_log_manager.add_event(
			WorldLogEntry.EventType.OTHER, "滚动事件 %d" % i
		)
	await get_tree().process_frame
	_check(_count_entry_labels() == 11, "多条日志全部进入滚动内容")
	_check(str(_map.call("get_world_log_text")).contains("滚动事件 7"), "最新日志保持可见")

	# 日志上限为 20：继续追加后底层与 UI 都只保留最新 20 条。
	for i: int in range(25):
		_context.world_log_manager.add_event(
			WorldLogEntry.EventType.OTHER, "上限事件 %d" % i
		)
	await get_tree().process_frame
	_check(_count_entry_labels() == 20, "日志面板最多显示 20 条")
	_check(_map.call("get_world_log_entry_count") == 20, "管理器只保留 20 条")
	text = str(_map.call("get_world_log_text"))
	_check(text.contains("上限事件 24"), "最新日志保持可见")
	_check(not text.contains("第一条世界事件"), "最旧日志被清理")

	# 面板可见时仍保留地图移动入口。
	var target := _player.world_position + Vector2(120.0, 0.0)
	_check(_map.call("request_player_move", target), "日志面板不阻挡地图点击/移动")

	# 日志数量继续受管理器上限约束，UI 只读取数据。
	_context.world_log_manager.clear()
	_check(_map.call("get_world_log_entry_count") == 0, "管理器清空后日志数据为空")


## 折叠/展开交互：点击文本展开，点击其他区域折叠；数据持续更新不改变状态。
func _test_collapse_interaction(
	panel: PanelContainer, title: Label, scroll: ScrollContainer, collapsed: Label
) -> void:
	_check(not bool(_map.call("is_world_log_expanded")), "日志默认处于折叠状态")
	var collapsed_rect := Rect2()
	var log_panel: WorldLogPanel = _map.call("get_world_log_panel")
	if log_panel != null:
		collapsed_rect = log_panel.get_collapsed_interaction_rect()
	_check(
		collapsed_rect.size.x > 0.0 and collapsed_rect.size.y > 0.0,
		"折叠文本具有可点击区域"
	)

	var inside := InputEventMouseButton.new()
	inside.button_index = MOUSE_BUTTON_LEFT
	inside.pressed = true
	inside.position = collapsed_rect.get_center()
	_map.call("_unhandled_input", inside)
	_check(bool(_map.call("is_world_log_expanded")), "点击事件文本展开完整面板")
	_check(title.visible and scroll.visible, "展开后恢复标题、滚动条与内容")
	_check(
		panel.mouse_filter == Control.MOUSE_FILTER_STOP,
		"展开面板拦截自身区域的地图点击"
	)

	var outside := InputEventMouseButton.new()
	outside.button_index = MOUSE_BUTTON_LEFT
	outside.pressed = true
	outside.position = Vector2(5.0, 5.0)
	_map.call("_input", outside)
	_check(not bool(_map.call("is_world_log_expanded")), "点击其他区域后自动折叠")
	_check(
		not title.visible and not scroll.visible and collapsed.visible,
		"折叠后只保留事件文本"
	)
	_check(
		panel.mouse_filter != Control.MOUSE_FILTER_STOP,
		"折叠面板不阻挡地图点击"
	)


func _count_entry_labels() -> int:
	if _map == null:
		return 0
	return _map.find_children("WorldLogEntry_*", "Label", true, false).size()


func _first_village() -> SettlementData:
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement.settlement_type == SettlementData.SettlementType.VILLAGE:
			return settlement
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[logui] OK: %s" % message)
	else:
		_failed = true
		push_error("[logui] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_map):
		_map.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
