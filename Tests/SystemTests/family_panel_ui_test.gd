extends Node
## 家族管理界面测试：大地图家族入口、暂停规则、部队页实时状态、
## 封地页分组/归属实时更新与点击定位。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/family_panel_ui_test.tscn

const TAB_TROOPS: String = "troops"
const TAB_FIEFS: String = "fiefs"
## 测试夹具：以平民身份开局，再手工装配一个测试玩家家族与封地，
## 以便验证“除玩家外没有家族成员”的空状态。
const TEST_VILLAGE_NAME: String = "埃克托"

var _failed: bool = false
var _context: WorldContext = null
var _map: Node = null
var _panel = null
var _house: HouseData = null
var _noble: NobleData = null
var _party: PartyData = null


func _ready() -> void:
	await _run()
	if _failed:
		push_error("[familyui] 测试失败")
		get_tree().quit(1)
	else:
		print("[familyui] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	TimeManager.world_elapsed_seconds = 0.0

	_context = WorldContext.new()
	_context.name = "FamilyPanelTestContext"
	add_child(_context)
	var catalog := IdentityCatalog.load_default()
	var commoner := catalog.get_identity("IDENTITY_DORAMAN_MERCENARY") \
		if catalog != null else null
	_check(commoner != null, "加载平民身份配置")
	_check(WorldInitializer.create_new_world(_context, commoner), "初始化世界")
	if not _context.is_valid_world():
		return
	_check(_context.get_player_house() == null, "平民开局没有玩家家族")

	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id
	GameManager.pending_settlement_latch_id = ""
	var packed := load("res://Scenes/WorldMap/world_map.tscn") as PackedScene
	_map = packed.instantiate()
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame

	await _test_commoner_family_panel()
	_setup_test_player_family()
	_house = _context.get_player_house()
	_check(_house != null, "玩家拥有家族")

	await _test_entry_and_empty_state()
	_create_family_noble_and_party()
	await _test_troop_page()
	await _test_fief_page_and_locate()

	_map.queue_free()
	_context.queue_free()


## 平民身份不自动创建家族；测试手工装配玩家家族、玩家贵族与一处封地。
func _setup_test_player_family() -> void:
	_house = _context.house_manager.register_house(
		WorldInitializer.HOUSE_PLAYER_ID,
		WorldInitializer.PLAYER_HOUSE_NAME,
		WorldInitializer.FAMILY_PLAYER_ID,
		true
	)
	if _house == null:
		return
	_context.player_house_id = _house.house_id
	var player_party := _context.get_player_party()
	if player_party == null:
		return
	player_party.family_id = WorldInitializer.FAMILY_PLAYER_ID
	var player_noble := _context.noble_manager.create_noble(
		WorldInitializer.PLAYER_LORD_NAME,
		WorldInitializer.PLAYER_FACTION_ID,
		player_party.party_id,
		_house.house_id,
		NobleData.Rank.KNIGHT,
		true,
		true
	)
	if player_noble != null:
		_context.player_lord_id = player_noble.lord_id
		player_party.leader_noble_id = player_noble.lord_id
	var village := _find_settlement(TEST_VILLAGE_NAME)
	if village != null:
		village.owner_house_id = _house.house_id


## 平民身份没有家族：入口仍可用，面板显示空状态且不伪造家族。
func _test_commoner_family_panel() -> void:
	var button := _map.find_child("FamilyButton", true, false) as Button
	_check(button != null, "平民身份仍有家族入口")
	if button == null:
		return
	button.pressed.emit()
	await get_tree().process_frame
	_panel = _map.call("get_family_panel")
	_check(_panel != null and _panel.visible, "平民打开家族面板不崩溃")
	if _panel == null:
		return
	_check(_panel.get_family_name() == "暂无家族", "平民家族标题显示暂无家族")
	_check(_panel.get_troop_entries().is_empty(), "平民家族部队为空")
	var fiefs_button := _map.find_child(
		"FamilyTabFiefsButton", true, false
	) as Button
	if fiefs_button != null:
		fiefs_button.pressed.emit()
		await get_tree().process_frame
	_check(_panel.get_fief_entries().is_empty(), "平民家族封地为空")
	var close_button := _map.find_child(
		"FamilyPanelCloseButton", true, false
	) as Button
	_check(close_button != null, "平民家族面板有关闭按钮")
	if close_button != null:
		close_button.pressed.emit()
		await get_tree().process_frame
	_check(not _panel.visible, "平民关闭家族面板回到大地图")


func _test_entry_and_empty_state() -> void:
	var button := _map.find_child("FamilyButton", true, false) as Button
	_check(button != null, "大地图顶栏存在家族入口")
	if button == null:
		return
	button.pressed.emit()
	await get_tree().process_frame
	_panel = _map.call("get_family_panel")
	_check(_panel != null and _panel.visible, "点击家族入口打开家族面板")
	_check(
		TimeManager.has_pause_reason(GameManager.PAUSE_REASON_UI_PANEL),
		"家族面板沿用 UI 面板暂停原因"
	)
	_check(
		_panel.get_current_tab() == TAB_TROOPS,
		"家族面板默认显示部队页"
	)
	_check(
		_panel.get_family_name() == WorldInitializer.PLAYER_HOUSE_NAME,
		"面板标题显示玩家家族名"
	)
	_check(
		_panel.get_troop_entries().is_empty(),
		"玩家之外的家族 NPC 为空时不伪造成员"
	)
	var empty_label := _map.find_child("FamilyEmptyLabel", true, false) as Label
	_check(
		empty_label != null and empty_label.text.contains("暂无可管理"),
		"家族部队为空时显示空状态"
	)

	var close_button := _map.find_child(
		"FamilyPanelCloseButton", true, false
	) as Button
	_check(close_button != null, "家族面板有关闭按钮")
	if close_button != null:
		close_button.pressed.emit()
	await get_tree().process_frame
	_check(not _panel.visible, "关闭家族面板回到大地图")
	_check(
		not TimeManager.has_pause_reason(GameManager.PAUSE_REASON_UI_PANEL),
		"关闭家族面板后解除暂停"
	)


func _create_family_noble_and_party() -> void:
	var village := _find_settlement(TEST_VILLAGE_NAME)
	if village == null or _house == null:
		return
	_party = _context.party_manager.create_party(
		WorldInitializer.PLAYER_FACTION_ID,
		village.world_position,
		"测试家族部队",
		PartyData.PartyKind.FAMILY
	)
	_check(_party != null, "为测试家族创建真实部队")
	if _party == null:
		return
	_party.family_id = WorldInitializer.FAMILY_PLAYER_ID
	_party.movement_state = PartyData.MovementState.IDLE
	_party.battle_state = PartyData.BattleState.AVAILABLE

	var config := _context.unit_manager.get_unit_config("infantry_militia")
	var member := _context.unit_manager.create_unit(
		config, WorldInitializer.PLAYER_FACTION_ID, "测试士兵"
	)
	if member != null:
		_context.party_manager.add_member(_party.party_id, member.unit_id)
	_check(
		_party.member_unit_ids.size() == 1,
		"测试家族部队包含真实成员"
	)

	_noble = _context.noble_manager.create_noble(
		"测试家族贵族",
		WorldInitializer.PLAYER_FACTION_ID,
		_party.party_id,
		_house.house_id,
		NobleData.Rank.KNIGHT
	)
	if _noble != null:
		_party.leader_noble_id = _noble.lord_id
	_check(_noble != null, "测试贵族进入玩家家族")
	if _noble != null:
		_check(
			_context.house_manager.get_house_nobles(_house.house_id, true).size()
				>= 2,
			"家族同时包含玩家与 NPC 贵族"
		)


func _test_troop_page() -> void:
	if _noble == null:
		return
	_map.call("open_family_panel")
	await get_tree().process_frame
	var entries: Array[Dictionary] = _panel.get_troop_entries()
	_check(entries.size() == 1, "部队页列出家族 NPC 贵族")
	if entries.is_empty():
		return
	var entry: Dictionary = entries[0]
	_check(str(entry.get("name", "")) == "测试家族贵族", "部队页显示贵族姓名")
	_check(str(entry.get("status", "")) == "正常", "正常贵族状态正确")
	_check(str(entry.get("party_text", "")).contains("成员 1 人"),
		"部队摘要显示真实成员数量")
	_check(
		str(entry.get("party_text", "")).contains(
			TEST_VILLAGE_NAME
		),
		"部队摘要显示附近地点"
	)
	_check(
		not _context.get_player_lord().lord_id == str(entry.get("noble_id", "")),
		"部队页排除玩家本人"
	)
	var player_entry := _map.find_child(
		"FamilyTroopEntry_%s" % _context.get_player_lord().lord_id,
		true, false
	)
	_check(player_entry == null, "部队页没有玩家条目节点")

	# 战斗中：状态读取实时 BattleState。
	_party.battle_state = PartyData.BattleState.IN_BATTLE
	_panel.call("refresh", true)
	entries = _panel.get_troop_entries()
	_check(str(entries[0].get("status", "")) == "战斗中", "战斗状态实时显示")
	_party.battle_state = PartyData.BattleState.AVAILABLE
	_panel.call("refresh", true)

	# 被俘：仍保留条目，但不显示旧部队信息。
	var config := _context.unit_manager.get_unit_config("infantry_militia")
	var captive_unit := _context.unit_manager.create_unit(
		config, WorldInitializer.PLAYER_FACTION_ID, "被俘测试单位"
	)
	if captive_unit != null:
		captive_unit.noble_id = _noble.lord_id
		captive_unit.mark_prisoner("CAPTIVE_OWNER_PARTY")
	_panel.call("refresh", true)
	entries = _panel.get_troop_entries()
	_check(entries.size() == 1, "被俘贵族仍列在家族部队页")
	entry = entries[0]
	_check(str(entry.get("status", "")) == "被俘", "被俘状态实时显示")
	_check(str(entry.get("party_text", "")) == "暂无部队",
		"被俘时不显示过期的部队信息")

	# 阵亡：仍可从家族数据中看到，状态实时更新。
	_noble.is_alive = false
	_panel.call("refresh", true)
	entries = _panel.get_troop_entries()
	_check(entries.size() == 1, "阵亡贵族仍保留在家族列表")
	_check(str(entries[0].get("status", "")) == "已阵亡", "阵亡状态实时显示")
	_noble.is_alive = true
	_panel.call("refresh", true)

	var close_button := _map.find_child(
		"FamilyPanelCloseButton", true, false
	) as Button
	if close_button != null:
		close_button.pressed.emit()
	await get_tree().process_frame


func _test_fief_page_and_locate() -> void:
	if _house == null:
		return
	var player_village := _find_settlement(TEST_VILLAGE_NAME)
	var bari := _find_settlement(WorldInitializer.BARI_VILLAGE_NAME)
	var olin_castle := _find_settlement(WorldInitializer.OLIN_CASTLE_NAME)
	var burk_town := _find_settlement(WorldInitializer.BURKNANIA_TOWN_NAME)
	if player_village == null or bari == null:
		return
	_map.call("open_family_panel")
	await get_tree().process_frame
	var fiefs_button := _map.find_child(
		"FamilyTabFiefsButton", true, false
	) as Button
	_check(fiefs_button != null, "家族面板存在封地页签")
	if fiefs_button != null:
		fiefs_button.pressed.emit()
	await get_tree().process_frame
	_check(
		_panel.get_current_tab() == TAB_FIEFS,
		"切换到封地页"
	)

	var now_fiefs: Array[Dictionary] = _panel.get_fief_entries()
	_check(_contains_settlement(now_fiefs, player_village.settlement_id),
		"封地页包含玩家家族村庄")
	if olin_castle != null:
		_check(not _contains_settlement(now_fiefs, olin_castle.settlement_id),
			"封地页排除其他家族城堡")
	if burk_town != null:
		_check(not _contains_settlement(now_fiefs, burk_town.settlement_id),
			"封地页排除其他家族城镇")

	# 家族成员获得更多封地后立即出现，无需重开面板。
	bari.owner_house_id = _house.house_id
	_panel.call("refresh", true)
	now_fiefs = _panel.get_fief_entries()
	_check(_contains_settlement(now_fiefs, bari.settlement_id),
		"家族成员拥有的村庄实时加入封地页")
	if olin_castle != null:
		olin_castle.owner_house_id = _house.house_id
		_panel.call("refresh", true)
		now_fiefs = _panel.get_fief_entries()
		_check(_contains_settlement(now_fiefs, olin_castle.settlement_id),
			"城堡按现有所有权实时加入封地页")
		_check(_has_type(now_fiefs, "城堡"), "封地页按城堡类型分组")

	# 所有权转回其他家族后实时消失。
	bari.owner_house_id = WorldInitializer.HOUSE_BARI_ID
	_panel.call("refresh", true)
	now_fiefs = _panel.get_fief_entries()
	_check(not _contains_settlement(now_fiefs, bari.settlement_id),
		"封地所有权变更后立即从家族封地页移除")

	# 点击封地定位镜头并关闭面板，不修改地点数据。
	var owner_house_before: String = player_village.owner_house_id
	var fief_button := _map.find_child(
		"FamilyFiefEntry_%s" % player_village.settlement_id, true, false
	) as Button
	_check(fief_button != null, "封地条目可点击定位")
	if fief_button != null:
		fief_button.pressed.emit()
		await get_tree().process_frame
	_check(not _panel.visible, "点击封地后关闭家族面板")
	_check(
		not TimeManager.has_pause_reason(GameManager.PAUSE_REASON_UI_PANEL),
		"点击封地返回大地图后解除暂停"
	)
	var camera := _map.get_node("Camera2D") as Camera2D
	_check(
		camera != null
		and camera.position.distance_to(player_village.world_position) < 1.0,
		"点击封地后镜头定位到该地点"
	)
	_check(
		player_village.owner_house_id == owner_house_before,
		"点击封地不修改地点归属"
	)


func _contains_settlement(entries: Array[Dictionary], settlement_id: String) -> bool:
	for entry: Dictionary in entries:
		if str(entry.get("settlement_id", "")) == settlement_id:
			return true
	return false


func _has_type(entries: Array[Dictionary], type_text: String) -> bool:
	for entry: Dictionary in entries:
		if str(entry.get("type_text", "")) == type_text:
			return true
	return false


func _find_settlement(display_name: String) -> SettlementData:
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement != null and settlement.display_name == display_name:
			return settlement
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[familyui] OK: %s" % message)
	else:
		_failed = true
		push_error("[familyui] FAIL: %s" % message)
