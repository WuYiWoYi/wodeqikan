extends Node
## 阶段 8 系统测试：百科一级分类、二级详情、敌对势力、动态数据、徽章占位与相机保持。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/encyclopedia_ui_test.tscn

const HOUSE_MOXIXI: String = "HOUSE_MOXIXI"
const HOUSE_BURKNANIA: String = "HOUSE_BURKNANIA"
const HOUSE_PLAYER: String = "HOUSE_PLAYER"
const KINGDOM_BURKNANIA: String = "KINGDOM_BURKNANIA"
const KINGDOM_OLIN: String = "KINGDOM_OLIN"

var _failed: bool = false
var _context: WorldContext = null
var _map: Node2D = null
var _panel: PanelContainer = null
var _dim: ColorRect = null
var _title: Label = null
var _back_button: Button = null


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

	_panel = _map.find_child("EncyclopediaPanel", true, false) as PanelContainer
	_dim = _map.find_child("EncyclopediaDim", true, false) as ColorRect
	_title = _map.find_child("EncyclopediaTitle", true, false) as Label
	_back_button = _map.find_child("EncyclopediaBackButton", true, false) as Button
	_check(_panel != null and _dim != null, "百科面板与遮罩已生成")
	if _panel == null or _dim == null:
		return

	var camera := _map.get_node("Camera2D") as Camera2D
	var camera_before := camera.position
	var scale_before := TimeManager.get_effective_world_scale()

	encyclopedia_button.pressed.emit()
	await get_tree().process_frame
	_check(_panel.visible and _dim.visible, "点击百科后打开面板")
	_check(
		is_zero_approx(TimeManager.get_effective_world_scale()),
		"百科打开时世界暂停"
	)

	# 一级：只显示王国、家族、地点三个分类，不显示任何具体王国详情。
	_check(_title.text == "百科", "一级标题为百科")
	_check(not _back_button.visible, "一级无返回按钮")
	var kingdoms_category := _find_button("EncyclopediaCategory_Kingdoms")
	var houses_category := _find_button("EncyclopediaCategory_Houses")
	var locations_category := _find_button("EncyclopediaCategory_Locations")
	_check(kingdoms_category != null, "一级显示王国分类")
	_check(houses_category != null, "一级显示家族分类")
	_check(locations_category != null, "一级显示地点分类")
	_check(
		kingdoms_category.text.contains("王国")
			and houses_category.text.contains("家族")
			and locations_category.text.contains("地点"),
		"一级分类文本来自数据"
	)
	_check(not _list_has_text("统治家族"), "一级不混入王国详情")

	# 一级分类 → 条目列表。
	await _click("EncyclopediaCategory_Kingdoms")
	_check(_title.text.contains("王国"), "点击王国分类进入条目列表")
	_check(_back_button.visible, "条目列表显示返回按钮")
	var kingdom_button := _find_button("EncyclopediaKingdom_%s" % KINGDOM_BURKNANIA)
	_check(kingdom_button != null, "王国列表包含伯克纳尼亚王国")
	if kingdom_button != null:
		_check(kingdom_button.text.contains("伯克纳尼亚王国"), "王国名称来自数据")
		_check(kingdom_button.text.contains("伯克纳家族"), "统治家族来自数据")
		_check(kingdom_button.text.contains("伯克纳国王"), "国王来自数据")
		_check(kingdom_button.text.contains("附庸家族：1"), "附庸数量来自数据")
		_check(kingdom_button.text.contains("封地：4"), "封地数量来自数据")
		_check(kingdom_button.text.contains("交战中"), "战争状态来自数据")
		_check(
			kingdom_button.text.contains("奥林王国"),
			"战争对象来自数据"
		)

	# 二级：王国详情。
	await _click("EncyclopediaKingdom_%s" % KINGDOM_BURKNANIA)
	_check(_title.text.contains("伯克纳尼亚王国"), "二级为王国详情")
	_check(_subtitle_text().contains("二级：王国详情"), "王国详情标注二级")

	var enemy_button := _find_button("EncyclopediaEnemyKingdom_%s" % KINGDOM_OLIN)
	_check(enemy_button != null, "王国详情列出敌对王国")
	_check(enemy_button != null and enemy_button.text.contains("奥林王国"), "敌对王国名称来自数据")
	_check(_list_has_text("敌对独立家族（0）"), "无敌对独立家族时显示空状态")

	await _click("EncyclopediaEnemyKingdom_%s" % KINGDOM_OLIN)
	_check(_title.text.contains("奥林王国"), "点击敌对王国跳转对应详情")
	_check(
		_find_button("EncyclopediaEnemyKingdom_%s" % KINGDOM_BURKNANIA) != null,
		"敌对关系双向可跳转"
	)
	_back_button.pressed.emit()
	await get_tree().process_frame
	_check(_title.text.contains("伯克纳尼亚王国"), "从敌对王国返回原王国详情")
	_back_button.pressed.emit()
	await get_tree().process_frame
	_check(_title.text.contains("王国") and _back_button.visible, "从王国详情返回王国列表")
	_back_button.pressed.emit()
	await get_tree().process_frame
	_check(_title.text == "百科" and not _back_button.visible, "从王国列表返回一级分类")

	# 家族分类 → 家族详情。
	await _click("EncyclopediaCategory_Houses")
	_check(_title.text.contains("家族"), "点击家族分类进入家族列表")
	_check(_find_button("EncyclopediaHouse_%s" % HOUSE_MOXIXI) != null, "家族列表包含墨西西家族")
	_check(
		_find_button("EncyclopediaHouse_%s" % HOUSE_PLAYER) != null,
		"家族列表包含独立玩家家族"
	)

	await _click("EncyclopediaHouse_%s" % HOUSE_MOXIXI)
	_check(_title.text.contains("墨西西家族"), "二级为家族详情")
	_check(_subtitle_text().contains("所属王国：伯克纳尼亚王国"), "家族详情显示所属王国")
	_check(_list_has_text("墨西西领主"), "家族详情列出贵族")
	_check(_list_has_text("墨西西"), "家族详情列出封地")
	_check(_list_has_text("敌对王国（1）"), "家族详情列出敌对王国")
	_check(
		_find_button("EncyclopediaEnemyKingdom_%s" % KINGDOM_OLIN) != null,
		"家族敌对王国来自统一关系数据"
	)
	_back_button.pressed.emit()
	await get_tree().process_frame

	# 独立玩家家族没有敌对王国，显示空状态。
	await _click("EncyclopediaHouse_%s" % HOUSE_PLAYER)
	_check(_subtitle_text().contains("独立家族"), "玩家家族显示为独立家族")
	_check(_list_has_text("敌对王国（0）"), "玩家家族无敌对王国")
	_check(_list_has_text("没有敌对王国。"), "无敌对王国显示空状态")
	_back_button.pressed.emit()
	await get_tree().process_frame
	_back_button.pressed.emit()
	await get_tree().process_frame
	_check(_title.text == "百科", "从家族列表返回一级分类")

	# 地点分类 → 地点详情。
	await _click("EncyclopediaCategory_Locations")
	_check(_title.text.contains("地点"), "点击地点分类进入地点列表")
	var town_id := _find_settlement_id("伯克纳尼亚")
	_check(not town_id.is_empty(), "找到伯克纳尼亚城镇")
	if not town_id.is_empty():
		var town_button := _find_button("EncyclopediaSettlement_%s" % town_id)
		_check(town_button != null, "地点列表包含伯克纳尼亚城镇")
		await _click("EncyclopediaSettlement_%s" % town_id)
		_check(_title.text.contains("伯克纳尼亚"), "二级为地点详情")
		_check(_list_has_text("类型：城镇"), "地点详情显示类型")
		_check(_list_has_text("所有者："), "地点详情显示所有者")
		_check(_list_has_text("人口："), "地点详情显示人口")
		_check(_list_has_text("繁荣度："), "地点详情显示繁荣度")
		_back_button.pressed.emit()
		await get_tree().process_frame
		_back_button.pressed.emit()
		await get_tree().process_frame

	# 动态更新：贵族死亡后家族详情刷新。
	await _click("EncyclopediaCategory_Houses")
	await _click("EncyclopediaHouse_%s" % HOUSE_BURKNANIA)
	_check(_title.text.contains("伯克纳家族"), "进入统治家族详情")
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
	_check(not _panel.visible and not _dim.visible, "关闭百科后隐藏面板")
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


func _find_button(node_name: String) -> Button:
	return _map.find_child(node_name, true, false) as Button


func _click(node_name: String) -> void:
	var button := _find_button(node_name)
	if button != null:
		button.pressed.emit()
	await get_tree().process_frame


func _subtitle_text() -> String:
	var subtitle := _map.find_child("EncyclopediaSubtitle", true, false) as Label
	return subtitle.text if subtitle != null else ""


func _list_has_text(needle: String) -> bool:
	var list := _map.find_child("EncyclopediaList", true, false)
	if list == null:
		return false
	for label: Node in list.find_children("*", "Label", true, false):
		if (label as Label).text.contains(needle):
			return true
	return false


func _find_settlement_id(display_name: String) -> String:
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement.display_name == display_name:
			return settlement.settlement_id
	return ""


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
