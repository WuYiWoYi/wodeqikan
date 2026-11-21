extends Node
## 阶段 6 大地图测试：时间 UI、人数图标、悬浮面板、追逐时禁止无关自动交互。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/world_map_milestone6_test.tscn

var _failed: bool = false
var _context: WorldContext = null
var _map: Node = null
var _player: PartyData = null
var _merchant: PartyData = null
var _guard: PartyData = null
var _village: SettlementData = null
var _castle: SettlementData = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[wm6] 测试失败")
		get_tree().quit(1)
	else:
		print("[wm6] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	TimeManager.world_elapsed_seconds = 0.0

	_context = WorldContext.new()
	_context.name = "WorldMapM6Context"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return
	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id

	_player = _context.get_player_party()
	_merchant = _find_party("河畔商队")
	_guard = _find_party("北境巡逻队")
	_village = _find_settlement("巴里")
	_castle = _find_settlement("灰石城堡")
	_check(_player != null and _merchant != null and _guard != null, "找到测试部队")
	_check(_village != null and _castle != null, "找到测试地点")
	if _player == null or _merchant == null or _guard == null:
		return

	var packed := load("res://Scenes/WorldMap/world_map.tscn") as PackedScene
	_map = packed.instantiate()
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame

	_test_time_ui()
	_test_party_icon_counts()
	_test_settlement_name_tags()
	_test_hover_panel()
	_test_alt_input_switch()
	await _test_icon_count_updates()
	_test_chase_suppression()


func _test_time_ui() -> void:
	var label := _map.find_child("TopBar", true, false)
	_check(label != null, "大地图顶栏存在")
	var time_label := _find_label_with_prefix(_map, "世界时间")
	_check(time_label != null, "顶栏显示世界时间")
	if time_label == null:
		return
	_check(time_label.text.contains("1103 年 1 月 1 日"), "新游戏日期 1103 年 1 月 1 日")
	_check(time_label.text.contains("深夜"), "新游戏时间段为深夜")
	_check(not time_label.text.contains("00:00"), "大地图不显示小时和分钟")
	_check(time_label.text.contains("倍率：暂停"), "显示暂停倍率")


func _test_party_icon_counts() -> void:
	for party: PartyData in _context.party_manager.get_all_parties():
		var icon := _map.find_child("PartyIcon_%s" % party.party_id, true, false) as PartyIcon
		_check(icon != null, "部队存在图标: %s" % party.party_name)
		if icon == null:
			continue
		_check(icon.get_count_text() == str(party.member_unit_ids.size()),
			"图标只显示人数: %s" % party.party_name)
		_check(icon.find_child("NameLabel", true, false) == null,
			"图标不再显示部队名称: %s" % party.party_name)


func _test_settlement_name_tags() -> void:
	# 名称已从世界空间图标移出，改为固定屏幕 UI。
	var icon := _map.find_child(
		"SettlementIcon_%s" % _village.settlement_id, true, false
	) as SettlementIcon
	_check(icon != null and icon.find_child("NameLabel", true, false) == null,
		"地点图标不再携带随相机缩放的名称")
	var tag := _map.call(
		"get_settlement_name_tag", _village.settlement_id
	) as SettlementNameTag
	_check(tag != null, "固定屏幕层生成地点名称标签")
	if tag == null:
		return
	_check(tag.get_name_text() == "巴里", "地点名称标签显示巴里")
	_check(tag.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"地点名称标签不拦截地图点击")
	_check(tag.get_parent().name == "SettlementNameLayer",
		"地点名称位于独立屏幕 UI 层")
	# 世界层保留村庄原始美术，位置/缩放/点击区域不变。
	_check(
		icon != null and icon.position == _village.world_position,
		"村庄美术位于原世界坐标"
	)
	_check(
		icon != null and icon.scale == Vector2.ONE,
		"村庄美术保持原始缩放"
	)
	# 名称 UI 是固定尺寸的“徽章 + 名称”组合。
	_check(
		tag.size == Vector2(SettlementNameTag.TAG_WIDTH, SettlementNameTag.TAG_HEIGHT),
		"地点名称组合使用固定屏幕尺寸"
	)
	var badge := tag.get_badge()
	var name_label := tag.get_name_label()
	_check(
		badge != null and name_label != null
			and badge.get_index() < name_label.get_index(),
		"家族徽章位于名称左侧"
	)
	_check(
		tag.has_family_badge() == not _village.family_id.is_empty(),
		"有家族的村庄显示徽章"
	)
	if not _village.family_id.is_empty():
		_check(
			tag.get_badge_family_id() == _village.family_id,
			"徽章读取地点实际家族而不是名称"
		)

	# 无家族地点不显示徽章（回退为纯名称）。
	var castle_tag := _map.call(
		"get_settlement_name_tag", _castle.settlement_id
	) as SettlementNameTag
	if castle_tag != null:
		_check(
			castle_tag.has_family_badge() == not _castle.family_id.is_empty(),
			"无家族地点隐藏家族徽章"
		)
	# 名称整体位于标记上方：标签底边不高于标记顶部。
	var marker_screen: Vector2 = (
		_map.get_viewport().get_canvas_transform() * _village.world_position
	)
	var marker_radius: float = SettlementIcon.get_name_anchor_radius(
		_village.settlement_type
	) * _map.camera.zoom.y
	_check(
		tag.position.y + tag.size.y <= marker_screen.y - marker_radius,
		"村庄名称显示在圆形标记正上方"
	)

	# 相机移动后名称仍然跟随建筑的世界坐标。
	# 暂停场景 _process，避免相机跟随玩家把测试位移立即覆盖。
	var position_before := tag.position
	_map.set_process(false)
	_map.camera.position += Vector2(120.0, 80.0)
	_map.camera.force_update_scroll()
	_map.call("_update_settlement_name_tags")
	_check(tag.position != position_before, "相机移动后地点名称跟随建筑")
	_map.set_process(true)

	# 家族骑士部队使用家族旗帜圆形标记。
	var knights := _find_party("巴里骑士")
	_check(knights != null, "找到巴里骑士部队")
	if knights != null:
		var party_icon := _map.find_child(
			"PartyIcon_%s" % knights.party_id, true, false
		) as PartyIcon
		_check(party_icon != null and party_icon.get_marker_radius() > 0.0,
			"家族部队使用圆形标记")
		_check(
			party_icon != null and party_icon.get_flag_texture_path().ends_with(
				"巴里旗帜16_16.png"
			),
			"家族部队标记使用家族旗帜"
		)


func _test_hover_panel() -> void:
	_map.call("set_alt_detail_active", false)
	_map.call("apply_hover_for_test", _merchant.world_position)
	_check(_map.call("is_hover_panel_visible") == true, "悬浮部队图标显示信息面板")
	var text: String = str(_map.call("get_hover_panel_text"))
	_check(text.contains(_merchant.party_name), "悬浮面板默认显示部队名称")
	_check(not text.contains("民兵（3）"), "默认模式不显示兵种构成")
	_check(not text.contains("总人数"), "默认模式不显示总人数")

	# 按住左 Alt：鼠标不动也立即展开详细构成。
	_map.call("set_alt_detail_active", true)
	text = str(_map.call("get_hover_panel_text"))
	_check(text.contains("总人数：%d" % _merchant.member_unit_ids.size()),
		"按住左 Alt 显示总人数")
	_check(text.contains("民兵（3）"), "详细模式合并显示民兵数量")
	_check(text.contains("职业步兵（2）"), "详细模式显示士兵类型")

	_map.call("apply_hover_for_test", _player.world_position)
	text = str(_map.call("get_hover_panel_text"))
	_check(
		text.contains(
			"骑马职业步兵（%d）" % WorldInitializer.PLAYER_MOUNTED_TRAINED_COUNT
		),
		"骑马与步兵分开统计"
	)
	_check(text.contains("玩家角色（1）"), "玩家角色单独显示")

	# 松开左 Alt：立即恢复简单模式，无需移动鼠标。
	_map.call("set_alt_detail_active", false)
	text = str(_map.call("get_hover_panel_text"))
	_check(text.contains(_player.party_name), "松开后仍显示部队名称")
	_check(not text.contains("总人数"), "松开后立即恢复简单模式")
	_check(not text.contains("玩家角色（1）"), "简单模式不再显示兵种构成")

	_map.call("clear_hover_for_test")
	_check(_map.call("is_hover_panel_visible") == false, "鼠标离开后悬浮面板关闭")


## 输入层只认左 Alt；右 Alt 不切换详细模式。
func _test_alt_input_switch() -> void:
	_map.call("set_alt_detail_active", false)

	var left_alt := InputEventKey.new()
	left_alt.keycode = KEY_ALT
	left_alt.physical_keycode = KEY_ALT
	left_alt.location = KEY_LOCATION_LEFT
	left_alt.pressed = true
	_map.call("_input", left_alt)
	_check(_map.call("is_alt_detail_active") == true, "按下左 Alt 进入详细模式")

	var right_alt := InputEventKey.new()
	right_alt.keycode = KEY_ALT
	right_alt.physical_keycode = KEY_ALT
	right_alt.location = KEY_LOCATION_RIGHT
	right_alt.pressed = true
	_map.call("_input", right_alt)
	_check(
		_map.call("is_alt_detail_active") == true,
		"按下右 Alt 不改变详细模式"
	)

	left_alt.pressed = false
	_map.call("_input", left_alt)
	_check(_map.call("is_alt_detail_active") == false, "松开左 Alt 退出详细模式")


func _test_icon_count_updates() -> void:
	var member_id: String = _guard.member_unit_ids[0]
	var before: int = _guard.member_unit_ids.size()
	_check(_context.party_manager.remove_member(_guard.party_id, member_id),
		"移除一名部队成员")
	await get_tree().process_frame
	var icon := _map.find_child(
		"PartyIcon_%s" % _guard.party_id, true, false
	) as PartyIcon
	_check(icon != null and icon.get_count_text() == str(before - 1),
		"人数变化后图标数字同步更新")


func _test_chase_suppression() -> void:
	if _village == null or _guard == null or _castle == null:
		return

	var settlement_panel := _map.find_child("SettlementPanel", true, false) as PanelContainer
	var party_panel := _map.find_child("PartyDialoguePanel", true, false) as PanelContainer
	_check(settlement_panel != null and party_panel != null, "地点与部队面板存在")
	if settlement_panel == null or party_panel == null:
		return

	# 把无关部队移远，确保测试的是“路过”而非目标已经到达。
	_merchant.world_position = Vector2(2600.0, 1800.0)
	_merchant.target_position = _merchant.world_position
	_merchant.movement_state = PartyData.MovementState.IDLE
	_guard.world_position = Vector2(2500.0, 1700.0)
	_guard.target_position = _guard.world_position
	_guard.movement_state = PartyData.MovementState.IDLE

	# 普通寻路经过村庄：逐帧更新不会按距离自动打开地点面板。
	_player.focus_party_id = ""
	_player.world_position = _village.world_position
	_player.movement_state = PartyData.MovementState.MOVING
	_player.target_position = _village.world_position + Vector2(600.0, 0.0)
	_map.call("_process", 0.016)
	_check(not settlement_panel.visible, "正常移动经过村庄不打开地点界面")

	# 追逐部队时经过村庄同样不打断当前行动。
	_player.focus_party_id = _merchant.party_id
	_map.call("_process", 0.016)
	_check(not settlement_panel.visible, "追击中经过村庄不打开地点界面")
	_check(not party_panel.visible, "追击中不自动打开无关部队对话")

	# 主动点击村庄才打开地点面板。
	_player.focus_party_id = ""
	_player.movement_state = PartyData.MovementState.IDLE
	_map.call("handle_left_click", _village.world_position)
	_check(settlement_panel.visible, "主动点击村庄打开地点面板")
	if settlement_panel.visible:
		var enter_button := _map.find_child(
			"SettlementEnterButton", true, false
		) as Button
		_check(enter_button != null and enter_button.visible, "村庄面板提供进入村庄入口")
		_check(_village.scene_path == "res://Scenes/Village/village.tscn",
			"村庄关联独立场景配置")
		_check(_castle.scene_path.is_empty(), "城堡暂不关联小场景")
		var leave_button := _map.find_child(
			"SettlementLeaveButton", true, false
		) as Button
		if leave_button != null:
			leave_button.pressed.emit()

	# 主动点击城堡同样打开面板，但不提供村庄入口。
	_map.call("handle_left_click", _castle.world_position)
	_check(settlement_panel.visible, "主动点击城堡打开地点面板")
	if settlement_panel.visible:
		var enter_button := _map.find_child(
			"SettlementEnterButton", true, false
		) as Button
		_check(enter_button != null and not enter_button.visible,
			"城堡面板不提供进入村庄入口")
		var leave_button := _map.find_child(
			"SettlementLeaveButton", true, false
		) as Button
		if leave_button != null:
			leave_button.pressed.emit()

	# 主动点击目标部队后仍保留原对话逻辑；普通路过不再自动弹窗。
	_player.focus_party_id = _guard.party_id
	_player.movement_state = PartyData.MovementState.IDLE
	_guard.world_position = _player.world_position
	_map.call("_check_party_interaction")
	_check(party_panel.visible, "主动点击目标部队后打开对话")
	if party_panel.visible:
		var leave_button := _map.find_child(
			"PartyLeaveButton", true, false
		) as Button
		if leave_button != null:
			leave_button.pressed.emit()


func _find_label_with_prefix(root: Node, prefix: String) -> Label:
	for child: Node in root.find_children("*", "Label", true, false):
		var label := child as Label
		if label != null and label.text.begins_with(prefix):
			return label
	return null


func _find_party(party_name: String) -> PartyData:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _find_settlement(display_name: String) -> SettlementData:
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement.display_name == display_name:
			return settlement
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[wm6] OK: %s" % message)
	else:
		_failed = true
		push_error("[wm6] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_map):
		_map.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
