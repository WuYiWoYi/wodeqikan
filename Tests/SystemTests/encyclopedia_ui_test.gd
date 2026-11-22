extends Node
## 阶段 8 系统测试：百科入口、三级导航、动态数据、徽章占位与相机保持。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/encyclopedia_ui_test.tscn

const HOUSE_MOXIXI: String = "HOUSE_MOXIXI"
const KINGDOM_BURKNANIA: String = "KINGDOM_BURKNANIA"

var _failed: bool = false
var _context: WorldContext = null
var _map: Node2D = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[encyclopedia] 测试失败")
		get_tree().quit(1)
	else:
		print("[encyclopedia] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)

	_context = WorldContext.new()
	_context.name = "EncyclopediaTestContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return
	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id

	var packed := load("res://Scenes/WorldMap/world_map.tscn") as PackedScene
	_map = packed.instantiate() as Node2D
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame

	var encyclopedia_button := _map.find_child(
		"EncyclopediaButton", true, false
	) as Button
	_check(encyclopedia_button != null, "大地图顶栏存在百科入口")
	if encyclopedia_button == null:
		return

	var panel := _map.find_child("EncyclopediaPanel", true, false) as PanelContainer
	var dim := _map.find_child("EncyclopediaDim", true, false) as ColorRect
	var title := _map.find_child("EncyclopediaTitle", true, false) as Label
	var back_button := _map.find_child(
		"EncyclopediaBackButton", true, false
	) as Button
	_check(panel != null and dim != null, "百科面板与遮罩已生成")
	if panel == null or dim == null:
		return

	var camera := _map.get_node("Camera2D") as Camera2D
	var camera_before := camera.position
	var scale_before := TimeManager.get_effective_world_scale()

	encyclopedia_button.pressed.emit()
	await get_tree().process_frame
	_check(panel.visible and dim.visible, "点击百科后打开面板")
	_check(
		is_zero_approx(TimeManager.get_effective_world_scale()),
		"百科打开时世界暂停"
	)
	_check(
		title.text.contains("王国") and back_button != null and not back_button.visible,
		"一级为王国列表且无返回按钮"
	)

	# 一级列表读取真实数据：名称、统治家族、国王、附庸数、封地数、关系与战争状态。
	var kingdom_button := _map.find_child(
		"EncyclopediaKingdom_%s" % KINGDOM_BURKNANIA, true, false
	) as Button
	_check(kingdom_button != null, "一级列表包含伯克纳尼亚王国")
	if kingdom_button != null:
		_check(kingdom_button.text.contains("伯克纳尼亚王国"), "王国名称来自数据")
		_check(kingdom_button.text.contains("伯克纳家族"), "统治家族来自数据")
		_check(kingdom_button.text.contains("伯克纳国王"), "国王来自数据")
		_check(kingdom_button.text.contains("附庸家族：1"), "附庸数量来自数据")
		_check(kingdom_button.text.contains("封地：4"), "封地数量来自数据")
		_check(kingdom_button.text.contains("交战中"), "战争状态来自数据")
		kingdom_button.pressed.emit()
		await get_tree().process_frame

	_check(title.text.contains("伯克纳尼亚王国"), "二级为王国详情")
	_check(back_button.visible, "二级显示返回按钮")
	var vassal_button := _map.find_child(
		"EncyclopediaHouse_%s" % HOUSE_MOXIXI, true, false
	) as Button
	_check(vassal_button != null, "二级列出可点击的附庸家族")
	if vassal_button != null:
		vassal_button.pressed.emit()
		await get_tree().process_frame

	_check(title.text.contains("墨西西家族"), "三级为家族详情")
	_check(_list_has_text("墨西西领主"), "三级列出家族贵族")
	_check(_list_has_text("墨西西"), "三级列出家族封地")

	back_button.pressed.emit()
	await get_tree().process_frame
	_check(title.text.contains("伯克纳尼亚王国"), "返回上一级到王国详情")
	back_button.pressed.emit()
	await get_tree().process_frame
	_check(title.text.contains("王国") and not back_button.visible, "再返回到王国列表")

	# 动态更新：贵族死亡后三级详情刷新。
	kingdom_button = _map.find_child(
		"EncyclopediaKingdom_%s" % KINGDOM_BURKNANIA, true, false
	) as Button
	_check(kingdom_button != null, "可重新进入伯克纳尼亚王国")
	if kingdom_button != null:
		kingdom_button.pressed.emit()
		await get_tree().process_frame
	var house_button := _map.find_child(
		"EncyclopediaHouse_HOUSE_BURKNANIA", true, false
	) as Button
	_check(house_button != null, "统治家族可进入家族详情")
	if house_button != null:
		house_button.pressed.emit()
		await get_tree().process_frame
		var lord := _context.noble_manager.get_noble_by_party_id(
			_find_party_id(WorldInitializer.BURKNANIA_KNIGHT_PARTY_NAME)
		)
		_check(lord != null, "找到伯克纳普通贵族")
		if lord != null:
			_check(_context.noble_manager.kill_noble(lord.lord_id), "贵族死亡写入数据")
			await get_tree().process_frame
			await get_tree().process_frame
			_check(_list_has_text("已故"), "家族详情动态显示死亡状态")

	# 缺失旗帜使用占位徽章。
	var placeholder_house := _context.house_manager.register_house(
		"HOUSE_TEST_NO_BANNER", "无徽章测试家族", ""
	)
	if placeholder_house != null:
		var badge: Control = _map.call("_make_house_badge", placeholder_house)
		_check(
			badge != null and badge.find_child("HouseBadgePlaceholder", true, false) != null,
			"缺失家族旗帜时使用占位徽章"
		)

	_map.call("_on_close_encyclopedia_pressed")
	await get_tree().process_frame
	_check(not panel.visible and not dim.visible, "关闭百科后隐藏面板")
	_check(
		is_equal_approx(
			TimeManager.get_effective_world_scale(), scale_before
		),
		"关闭百科后恢复原世界速度"
	)
	await get_tree().process_frame
	_check(
		camera.position.distance_to(camera_before) <= 2.0,
		"打开/关闭百科不重置相机"
	)
	_check(_context.player_party_id == GameManager.player_party_id, "玩家部队未被百科改变")


func _list_has_text(needle: String) -> bool:
	var list := _map.find_child("EncyclopediaList", true, false)
	if list == null:
		return false
	for label: Node in list.find_children("*", "Label", true, false):
		if (label as Label).text.contains(needle):
			return true
	return false


func _find_party_id(party_name: String) -> String:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party.party_id
	return ""


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[encyclopedia] OK: %s" % message)
	else:
		_failed = true
		push_error("[encyclopedia] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_map):
		_map.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
