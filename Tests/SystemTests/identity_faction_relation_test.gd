extends Node
## 新游戏身份开局阵营关系测试（2026-11-27 规则重整）。
##
## 只通过 FactionManager 的统一接口判定，验证六个身份：
## - 贵族：所属家族 → 所属王国 → 同王国成员家族/部队/建筑同阵营；
## - 平民：无家族/无王国，仅玩家本人部队同阵营；
## - 瓦伊拉家族领袖：独立家族，不建立/加入任何王国；
## - 文化、出生点、旧地图标记不参与阵营判定；
## - 敌国关系按正式王国战争传播；
## - 大地图部队外环与建筑名称底板统一读取同一接口。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/identity_faction_relation_test.tscn

const ALLIED: int = FactionManager.PlayerRelation.ALLIED
const NEUTRAL: int = FactionManager.PlayerRelation.NEUTRAL
const HOSTILE: int = FactionManager.PlayerRelation.HOSTILE

var _failed: bool = false
var _catalog: IdentityCatalog = null
var _map: Node = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[identity-faction] 测试失败")
		get_tree().quit(1)
	else:
		print("[identity-faction] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	TimeManager.world_elapsed_seconds = 0.0
	_catalog = IdentityCatalog.load_default()
	_check(_catalog != null, "文化与身份配置可加载")
	if _catalog == null:
		return
	_test_ektor_second_son()
	_test_commoners()
	_test_dindani_knight()
	_test_vaila_leader()
	await _test_world_map_visuals()


## 4.1 埃克托家族次子：HOUSE_EKTOR → KINGDOM_BURKNANIA。
func _test_ektor_second_son() -> void:
	var context := _create_world("IDENTITY_EKTOR_SECOND_SON")
	if context == null:
		return
	print("[identity-faction] --- 埃克托家族次子 ---")
	var house := context.get_player_house()
	_check(house != null and house.house_id == WorldInitializer.HOUSE_EKTOR_ID,
		"玩家属于埃克托家族")
	_check(house != null and house.kingdom_id == WorldInitializer.KINGDOM_BURKNANIA_ID,
		"埃克托家族属于伯克纳王国")

	for house_id: String in [
		WorldInitializer.HOUSE_EKTOR_ID,
		WorldInitializer.HOUSE_BURKNANIA_ID,
		WorldInitializer.HOUSE_ODESTER_ID,
		WorldInitializer.HOUSE_BAFLE_ID,
		WorldInitializer.HOUSE_BARI_ID,
	]:
		_expect_house(context, house_id, ALLIED, "伯克纳王国成员家族同阵营")
	for house_id: String in [
		WorldInitializer.HOUSE_FRANI_ID,
		WorldInitializer.HOUSE_DINDANI_ID,
		WorldInitializer.HOUSE_VAILA_ID,
		WorldInitializer.HOUSE_LORIAK_ID,
		WorldInitializer.HOUSE_OLIN_ID,
		WorldInitializer.HOUSE_MOXIXI_ID,
		WorldInitializer.HOUSE_TAINA_ID,
		WorldInitializer.HOUSE_VALEMON_ID,
	]:
		_expect_house(context, house_id, NEUTRAL, "不同王国/独立家族保持中立")

	_expect_kingdom(context, WorldInitializer.KINGDOM_BURKNANIA_ID, ALLIED,
		"玩家所属王国同阵营")
	for kingdom_id: String in [
		WorldInitializer.KINGDOM_FRANI_ID,
		WorldInitializer.KINGDOM_LORIAK_ID,
		WorldInitializer.KINGDOM_TAINA_ID,
		WorldInitializer.KINGDOM_VALEMON_ID,
		WorldInitializer.KINGDOM_VAILA_ID,
	]:
		_expect_kingdom(context, kingdom_id, NEUTRAL, "其他王国不自动同阵营")

	# 仅“有主且属于伯克纳王国”的建筑为绿色；无主建筑保持中立（不以旗帜推断）。
	for name: String in [
		"伯克纳尼亚", "伯克纳", "灰石堡垒", "巴里",
		"埃克托尼亚", "埃克托",
	]:
		_expect_settlement(context, name, ALLIED, "伯克纳王国所属建筑同阵营")
	for name: String in ["墨西西", "奥林", "弗拉尼亚", "塞洛斯要塞"]:
		_expect_settlement(context, name, NEUTRAL, "非所属建筑保持中立")

	for name: String in ["伯克纳骑士", "奥德斯特骑士", "埃克托骑士", "巴夫勒骑士", "巴里骑士"]:
		_expect_party(context, name, ALLIED, "伯克纳王国所属部队同阵营")
	for name: String in ["弗拉尼骑士", "墨西西骑士", "瓦伊拉骑士"]:
		_expect_party(context, name, NEUTRAL, "其他王国部队保持中立")
	_expect_party(context, "玩家部队", ALLIED, "玩家本人部队同阵营")

	# 伯克纳与洛里亚克开战：敌国成员家族、部队与有主建筑全部敌对。
	_check(context.kingdom_manager.declare_war(
		WorldInitializer.KINGDOM_BURKNANIA_ID, WorldInitializer.KINGDOM_LORIAK_ID
	), "伯克纳与洛里亚克开战")
	for house_id: String in [
		WorldInitializer.HOUSE_LORIAK_ID,
		WorldInitializer.HOUSE_OLIN_ID,
		WorldInitializer.HOUSE_MOXIXI_ID,
		WorldInitializer.HOUSE_ROSVIK_ID,
	]:
		_expect_house(context, house_id, HOSTILE, "敌国成员家族敌对")
	for name: String in ["墨西西骑士", "奥林骑士", "罗斯维克骑士"]:
		_expect_party(context, name, HOSTILE, "敌国部队显示敌对")
	for name: String in ["墨西西", "奥林", "奥林德斯堡"]:
		_expect_settlement(context, name, HOSTILE, "敌国有主建筑显示敌对")
	# 同阵营关系不被战争破坏；未参战王国仍中立。
	_expect_house(context, WorldInitializer.HOUSE_BURKNANIA_ID, ALLIED,
		"开战后同王国仍同阵营")
	_expect_settlement(context, "伯克纳", ALLIED, "开战后同阵营建筑仍为绿色")
	_expect_house(context, WorldInitializer.HOUSE_FRANI_ID, NEUTRAL,
		"未参战王国保持中立")
	_destroy_world(context)


## 4.2 / 4.4 / 4.6 三个平民身份：无家族、无王国，仅玩家本人同阵营。
func _test_commoners() -> void:
	for identity_id: String in [
		"IDENTITY_DORAMAN_MERCENARY",
		"IDENTITY_FRANI_MERCHANT",
		"IDENTITY_ROGUE_KNIGHT",
	]:
		var context := _create_world(identity_id)
		if context == null:
			continue
		print("[identity-faction] --- %s ---" % identity_id)
		_check(context.player_house_id.is_empty(), "平民没有玩家家族: %s" % identity_id)
		_check(context.get_player_house() == null, "平民家族查询为空: %s" % identity_id)
		_check(context.player_lord_id.is_empty(), "平民没有贵族记录: %s" % identity_id)
		_expect_party(context, "玩家部队", ALLIED, "平民仅玩家本人同阵营")
		for name: String in ["伯克纳骑士", "埃克托骑士", "弗拉尼骑士", "丁达尼骑士", "瓦伊拉骑士"]:
			_expect_party(context, name, NEUTRAL, "平民不因文化/旧数据获得同阵营部队")
		for name: String in ["伯克纳尼亚", "伯克纳", "灰石堡垒", "巴里", "弗拉尼亚", "墨西西"]:
			_expect_settlement(context, name, NEUTRAL, "平民不存在错误绿色建筑")
		for house_id: String in [
			WorldInitializer.HOUSE_BURKNANIA_ID,
			WorldInitializer.HOUSE_EKTOR_ID,
			WorldInitializer.HOUSE_FRANI_ID,
			WorldInitializer.HOUSE_DINDANI_ID,
			WorldInitializer.HOUSE_VAILA_ID,
		]:
			_expect_house(context, house_id, NEUTRAL, "平民不自动与家族同阵营")
		for kingdom_id: String in [
			WorldInitializer.KINGDOM_BURKNANIA_ID,
			WorldInitializer.KINGDOM_FRANI_ID,
			WorldInitializer.KINGDOM_VAILA_ID,
		]:
			_expect_kingdom(context, kingdom_id, NEUTRAL, "平民不自动加入王国")
		_destroy_world(context)


## 4.3 丁达尼家族骑士：HOUSE_DINDANI → KINGDOM_FRANI。
func _test_dindani_knight() -> void:
	var context := _create_world("IDENTITY_DINDANI_KNIGHT")
	if context == null:
		return
	print("[identity-faction] --- 丁达尼家族骑士 ---")
	var house := context.get_player_house()
	_check(house != null and house.house_id == WorldInitializer.HOUSE_DINDANI_ID,
		"玩家属于丁达尼家族")
	_check(house != null and house.kingdom_id == WorldInitializer.KINGDOM_FRANI_ID,
		"丁达尼家族属于弗拉尼伯国")
	for house_id: String in [
		WorldInitializer.HOUSE_DINDANI_ID,
		WorldInitializer.HOUSE_FRANI_ID,
		WorldInitializer.HOUSE_KONLIA_ID,
		WorldInitializer.HOUSE_MIQIQI_ID,
	]:
		_expect_house(context, house_id, ALLIED, "弗拉尼王国成员家族同阵营")
	# 同文化的瓦伊拉家族（布吉多人）不因文化自动同阵营。
	_expect_house(context, WorldInitializer.HOUSE_VAILA_ID, NEUTRAL,
		"同文化家族不自动同阵营")
	_expect_house(context, WorldInitializer.HOUSE_BURKNANIA_ID, NEUTRAL,
		"其他王国保持中立")
	for name: String in ["弗拉尼骑士", "丁达尼骑士", "康利亚骑士", "米奇奇骑士"]:
		_expect_party(context, name, ALLIED, "弗拉尼王国部队同阵营")
	for name: String in ["伯克纳骑士", "瓦伊拉骑士"]:
		_expect_party(context, name, NEUTRAL, "非所属部队保持中立")

	# 弗拉尼与伯克纳开战：伯克纳成员家族、部队与有主建筑敌对。
	_check(context.kingdom_manager.declare_war(
		WorldInitializer.KINGDOM_FRANI_ID, WorldInitializer.KINGDOM_BURKNANIA_ID
	), "弗拉尼与伯克纳开战")
	for house_id: String in [
		WorldInitializer.HOUSE_BURKNANIA_ID,
		WorldInitializer.HOUSE_EKTOR_ID,
		WorldInitializer.HOUSE_BARI_ID,
		WorldInitializer.HOUSE_ODESTER_ID,
		WorldInitializer.HOUSE_BAFLE_ID,
	]:
		_expect_house(context, house_id, HOSTILE, "敌国成员家族敌对")
	for name: String in ["伯克纳骑士", "巴里骑士", "埃克托骑士"]:
		_expect_party(context, name, HOSTILE, "敌国部队显示敌对")
	for name: String in ["伯克纳尼亚", "伯克纳", "灰石堡垒", "巴里"]:
		_expect_settlement(context, name, HOSTILE, "敌国有主建筑显示敌对")
	_expect_party(context, "弗拉尼骑士", ALLIED, "开战后本方部队仍同阵营")
	_destroy_world(context)


## 4.5 瓦伊拉家族领袖：HOUSE_VAILA 独立，无王国。
func _test_vaila_leader() -> void:
	var context := _create_world("IDENTITY_VAILA_LEADER")
	if context == null:
		return
	print("[identity-faction] --- 瓦伊拉家族领袖 ---")
	var house := context.get_player_house()
	_check(house != null and house.house_id == WorldInitializer.HOUSE_VAILA_ID,
		"玩家属于瓦伊拉家族")
	_check(house != null and house.kingdom_id.is_empty(), "瓦伊拉家族保持独立")
	_check(context.player_lord_id == house.leader_noble_id if house != null else false,
		"玩家是独立家族领袖")
	_check(context.kingdom_manager.get_kingdom(WorldInitializer.KINGDOM_VAILA_ID) == null,
		"独立家族身份不建立瓦伊拉王国")
	_check(context.kingdom_manager.get_all_kingdoms().size() == 5,
		"独立家族身份下世界只有 5 个王国")

	_expect_house(context, WorldInitializer.HOUSE_VAILA_ID, ALLIED,
		"玩家家族同阵营")
	_expect_party(context, "瓦伊拉骑士", ALLIED, "玩家家族部队同阵营")
	_expect_party(context, "玩家部队", ALLIED, "玩家本人部队同阵营")
	for house_id: String in [
		WorldInitializer.HOUSE_BURKNANIA_ID,
		WorldInitializer.HOUSE_EKTOR_ID,
		WorldInitializer.HOUSE_FRANI_ID,
		WorldInitializer.HOUSE_DINDANI_ID,
		WorldInitializer.HOUSE_LORIAK_ID,
	]:
		_expect_house(context, house_id, NEUTRAL, "独立家族不自动与其他家族同阵营")
	for name: String in ["伯克纳骑士", "弗拉尼骑士", "洛里亚克骑士"]:
		_expect_party(context, name, NEUTRAL, "独立家族不自动与其他部队同阵营")
	for name: String in ["伯克纳尼亚", "伯克纳", "灰石堡垒", "巴里", "弗拉尼亚", "墨西西"]:
		_expect_settlement(context, name, NEUTRAL, "独立家族不存在错误绿色建筑")

	# 其他王国开战不会把独立家族卷入。
	_check(context.kingdom_manager.declare_war(
		WorldInitializer.KINGDOM_BURKNANIA_ID, WorldInitializer.KINGDOM_LORIAK_ID
	), "其他王国之间开战")
	_expect_house(context, WorldInitializer.HOUSE_BURKNANIA_ID, NEUTRAL,
		"独立家族不因他国战争敌对")
	_expect_house(context, WorldInitializer.HOUSE_LORIAK_ID, NEUTRAL,
		"独立家族不因他国战争敌对")
	_expect_party(context, "伯克纳骑士", NEUTRAL, "独立家族不因他国战争敌对部队")
	_expect_party(context, "瓦伊拉骑士", ALLIED, "独立家族部队保持同阵营")
	_destroy_world(context)


## 7. 大地图表现：部队外环与建筑底板统一读取 FactionManager 结果。
func _test_world_map_visuals() -> void:
	var context := _create_world("IDENTITY_EKTOR_SECOND_SON")
	if context == null:
		return
	print("[identity-faction] --- 大地图表现 ---")
	GameManager.world_context = context
	GameManager.player_party_id = context.player_party_id
	var packed := load("res://Scenes/WorldMap/world_map.tscn") as PackedScene
	_map = packed.instantiate()
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame

	var burknania_party := _find_party(context, "伯克纳骑士")
	var frani_party := _find_party(context, "弗拉尼骑士")
	var moxixi_party := _find_party(context, "墨西西骑士")
	var burknania_settlement := _find_settlement(context, "伯克纳")
	var frani_settlement := _find_settlement(context, "弗拉尼亚")
	var moxixi_settlement := _find_settlement(context, "墨西西")
	_check(
		burknania_party != null and frani_party != null and moxixi_party != null
			and burknania_settlement != null and frani_settlement != null
			and moxixi_settlement != null,
		"大地图表现测试所需实体存在"
	)
	if burknania_party == null or frani_party == null or moxixi_party == null \
			or burknania_settlement == null or frani_settlement == null \
			or moxixi_settlement == null:
		_destroy_world(context)
		return

	_check(
		_map.call("get_party_player_relation", burknania_party.party_id) == ALLIED,
		"大地图同阵营部队使用统一关系接口"
	)
	var burknania_icon := _map.call("get_party_icon", burknania_party.party_id) as PartyIcon
	var frani_icon := _map.call("get_party_icon", frani_party.party_id) as PartyIcon
	_check(
		burknania_icon != null and burknania_icon.get_faction_ring_color()
			.is_equal_approx(burknania_icon.get_marker_style().allied_ring_color),
		"同阵营部队显示绿色外环"
	)
	_check(
		frani_icon != null and frani_icon.get_faction_ring_color().a == 0.0,
		"中立部队不显示阵营外环"
	)
	_check(
		_tag_color(_map, burknania_settlement).is_equal_approx(
			SettlementNameTag.ALLIED_BACKGROUND_COLOR
		),
		"同阵营建筑显示绿色名称底板"
	)
	_check(
		_tag_color(_map, frani_settlement).is_equal_approx(
			SettlementNameTag.BACKGROUND_COLOR
		),
		"中立建筑保持黑色名称底板"
	)

	# 王国开战后，既有地图立即按统一接口刷新为敌对表现。
	context.kingdom_manager.declare_war(
		WorldInitializer.KINGDOM_BURKNANIA_ID, WorldInitializer.KINGDOM_LORIAK_ID
	)
	_map.call("_refresh_faction_visuals")
	var moxixi_icon := _map.call("get_party_icon", moxixi_party.party_id) as PartyIcon
	_check(
		moxixi_icon != null and moxixi_icon.get_player_relation() == HOSTILE
			and moxixi_icon.get_faction_ring_color().is_equal_approx(
				moxixi_icon.get_marker_style().hostile_ring_color
			),
		"敌国部队显示红色外环"
	)
	_check(
		_tag_color(_map, moxixi_settlement).is_equal_approx(
			SettlementNameTag.HOSTILE_BACKGROUND_COLOR
		),
		"敌国建筑显示红色名称底板"
	)
	_destroy_world(context)


func _create_world(identity_id: String) -> WorldContext:
	var identity := _catalog.get_identity(identity_id)
	_check(identity != null, "身份配置存在: %s" % identity_id)
	if identity == null:
		return null
	var context := WorldContext.new()
	context.name = "IdentityFactionContext_%s" % identity_id
	add_child(context)
	if not WorldInitializer.create_new_world(context, identity):
		_check(false, "创建世界: %s" % identity_id)
		_destroy_world(context)
		return null
	_check(context.is_valid_world(), "世界有效: %s" % identity_id)
	return context


func _destroy_world(context: WorldContext) -> void:
	if context == null or not is_instance_valid(context):
		return
	if _map != null and is_instance_valid(_map) and _map.get_parent() == self:
		remove_child(_map)
		_map.queue_free()
		_map = null
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if context.get_parent() == self:
		remove_child(context)
	context.free()


func _find_settlement(context: WorldContext, display_name: String) -> SettlementData:
	for settlement: SettlementData in context.settlement_manager.get_all_settlements():
		if settlement != null and settlement.display_name == display_name:
			return settlement
	return null


func _find_party(context: WorldContext, party_name: String) -> PartyData:
	for party: PartyData in context.party_manager.get_all_parties():
		if party != null and party.party_name == party_name:
			return party
	return null


func _tag_color(map_node: Node, settlement: SettlementData) -> Color:
	if map_node == null or settlement == null:
		return Color.TRANSPARENT
	var tag := map_node.call(
		"get_settlement_name_tag", settlement.settlement_id
	) as SettlementNameTag
	return tag.get_background_color() if tag != null else Color.TRANSPARENT


func _expect_house(
	context: WorldContext, house_id: String, relation: int, message: String
) -> void:
	var actual: int = context.faction_manager.get_player_relation_for_house(house_id)
	_check(actual == relation, "%s: %s=%s" % [
		message, house_id, _relation_text(actual)
	])


func _expect_party(
	context: WorldContext, party_name: String, relation: int, message: String
) -> void:
	var party := _find_party(context, party_name)
	if party == null:
		_check(false, "%s: 部队不存在 %s" % [message, party_name])
		return
	var actual: int = context.faction_manager.get_player_relation_for_party(
		party.party_id
	)
	_check(actual == relation, "%s: %s=%s" % [
		message, party_name, _relation_text(actual)
	])


func _expect_settlement(
	context: WorldContext, display_name: String, relation: int, message: String
) -> void:
	var settlement := _find_settlement(context, display_name)
	if settlement == null:
		_check(false, "%s: 地点不存在 %s" % [message, display_name])
		return
	var actual: int = context.faction_manager.get_player_relation_for_settlement(
		settlement.settlement_id
	)
	_check(actual == relation, "%s: %s=%s" % [
		message, display_name, _relation_text(actual)
	])


func _expect_kingdom(
	context: WorldContext, kingdom_id: String, relation: int, message: String
) -> void:
	var actual: int = context.faction_manager.get_player_relation_for_kingdom(
		kingdom_id
	)
	_check(actual == relation, "%s: %s=%s" % [
		message, kingdom_id, _relation_text(actual)
	])


func _relation_text(relation: int) -> String:
	match relation:
		ALLIED:
			return "同阵营"
		HOSTILE:
			return "敌对"
		_:
			return "中立"


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[identity-faction] OK: %s" % message)
	else:
		_failed = true
		push_error("[identity-faction] FAIL: %s" % message)


func _cleanup() -> void:
	if _map != null and is_instance_valid(_map):
		_map.queue_free()
		_map = null
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
