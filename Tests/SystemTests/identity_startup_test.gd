extends Node
## 新游戏身份 → 实际开局数据测试。
##
## 覆盖六个正式身份：出生地点、玩家家族/爵位、家族领袖、所属王国、
## 平民无家族、青禾村/北境村与北境巡逻队移除、身份字段存档往返。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/identity_startup_test.tscn

const EXPECTED_HOUSE_COUNT: int = 17
const EXPECTED_KINGDOM_COUNT: int = 6
const SPAWN_TOLERANCE: float = 600.0

## 身份配置与期望结果的交叉校验；不按显示名称推断任何归属。
const CASES: Array[Dictionary] = [
	{
		"identity_id": "IDENTITY_EKTOR_SECOND_SON",
		"spawn": "ektor_town",
		"family": "FAMILY_EKTOR",
		"house": "HOUSE_EKTOR",
		"kingdom": "KINGDOM_BURKNANIA",
		"noble": true,
		"leader": false,
		"rank": 1,
	},
	{
		"identity_id": "IDENTITY_DORAMAN_MERCENARY",
		"spawn": "bafleborg",
		"family": "",
		"house": "",
		"kingdom": "",
		"noble": false,
		"leader": false,
		"rank": 0,
	},
	{
		"identity_id": "IDENTITY_DINDANI_KNIGHT",
		"spawn": "dindani_castle",
		"family": "FAMILY_DINDANI",
		"house": "HOUSE_DINDANI",
		"kingdom": "KINGDOM_FRANI",
		"noble": true,
		"leader": false,
		"rank": 1,
	},
	{
		"identity_id": "IDENTITY_FRANI_MERCHANT",
		"spawn": "frania",
		"family": "",
		"house": "",
		"kingdom": "",
		"noble": false,
		"leader": false,
		"rank": 0,
	},
	{
		"identity_id": "IDENTITY_VAILA_LEADER",
		"spawn": "vaila_castle",
		"family": "FAMILY_VAILA",
		"house": "HOUSE_VAILA",
		"kingdom": "",
		"noble": true,
		"leader": true,
		"rank": 3,
	},
	{
		"identity_id": "IDENTITY_ROGUE_KNIGHT",
		"spawn": "rosviknia",
		"family": "",
		"house": "",
		"kingdom": "",
		"noble": false,
		"leader": false,
		"rank": 0,
	},
]

var _failed: bool = false
var _catalog: IdentityCatalog = null


func _ready() -> void:
	_run()
	if _failed:
		push_error("[identity-startup] 测试失败")
		get_tree().quit(1)
	else:
		print("[identity-startup] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	TimeManager.world_elapsed_seconds = 0.0

	_catalog = IdentityCatalog.load_default()
	_check(_catalog != null, "文化/身份配置可加载")
	if _catalog == null:
		return
	_check(_catalog.get_identity("IDENTITY_EKTOR_SECOND_SON") != null,
		"默认身份配置存在")

	for case: Dictionary in CASES:
		_test_identity_case(case)


func _test_identity_case(case: Dictionary) -> void:
	var identity_id: String = str(case["identity_id"])
	var identity := _catalog.get_identity(identity_id)
	_check(identity != null, "身份配置存在: %s" % identity_id)
	if identity == null:
		return
	_check(identity.spawn_location_id == str(case["spawn"]),
		"身份出生地点配置正确: %s" % identity_id)
	_check(identity.family_id == str(case["family"]),
		"身份家族配置正确: %s" % identity_id)
	_check(identity.family_system_enabled == bool(case["noble"]),
		"身份家族系统开关正确: %s" % identity_id)

	var context := _create_world(identity)
	if context == null:
		return
	_test_spawn(context, case)
	_test_identity_binding(context, case)
	_test_world_cleanup(context, case)
	_test_save_roundtrip(context, case)
	_destroy_world(context)


func _test_spawn(context: WorldContext, case: Dictionary) -> void:
	var definition := context.world_map_definition
	var spawn_key: String = str(case["spawn"])
	var target := definition.get_settlement_world_position(spawn_key)
	var player := context.get_player_party()
	_check(player != null, "玩家部队存在: %s" % str(case["identity_id"]))
	if player == null:
		return
	_check(
		player.world_position.distance_to(target) <= SPAWN_TOLERANCE,
		"出生点位于身份地点附近: %s" % str(case["identity_id"])
	)
	_check(
		context.world_terrain != null
			and context.world_terrain.is_passable(player.world_position),
		"出生点位于可通行区域: %s" % str(case["identity_id"])
	)


func _test_identity_binding(context: WorldContext, case: Dictionary) -> void:
	var identity_id: String = str(case["identity_id"])
	var expect_noble: bool = bool(case["noble"])
	_check(context.player_identity_id == identity_id, "会话保存身份 ID: %s" % identity_id)
	_check(context.player_culture_id == _catalog.get_identity(identity_id).culture_id,
		"会话保存文化 ID: %s" % identity_id)
	_check(context.player_identity_name == _catalog.get_identity(identity_id).display_name,
		"会话保存身份显示名: %s" % identity_id)

	var player := context.get_player_party()
	if not expect_noble:
		_check(context.player_house_id.is_empty(), "平民没有玩家家族: %s" % identity_id)
		_check(context.player_lord_id.is_empty(), "平民没有贵族记录: %s" % identity_id)
		_check(context.get_player_house() == null, "平民家族查询为空: %s" % identity_id)
		_check(context.get_player_noble() == null, "平民贵族查询为空: %s" % identity_id)
		_check(player != null and player.family_id.is_empty(),
			"平民玩家部队没有家族旗帜: %s" % identity_id)
		_check(player != null and player.member_unit_ids.size() > 0,
			"平民玩家部队正常生成: %s" % identity_id)
		return

	var expected_house: String = str(case["house"])
	var expected_family: String = str(case["family"])
	var player_noble := context.get_player_noble()
	var house := context.get_player_house()
	_check(player != null and player.family_id == expected_family,
		"玩家部队绑定身份家族: %s" % identity_id)
	_check(context.player_house_id == expected_house,
		"玩家所属家族正确: %s" % identity_id)
	_check(house != null and house.house_id == expected_house and house.is_player_house,
		"正式家族承担玩家家族职责: %s" % identity_id)
	_check(player_noble != null, "贵族身份创建玩家贵族: %s" % identity_id)
	if player_noble == null:
		return
	_check(player_noble.house_id == expected_house, "玩家贵族属于目标家族: %s" % identity_id)
	_check(int(player_noble.rank) == int(case["rank"]), "玩家爵位正确: %s" % identity_id)
	_check(player_noble.display_name == _catalog.get_identity(identity_id).display_name,
		"玩家身份标记使用身份名称: %s" % identity_id)

	var expect_leader: bool = bool(case["leader"])
	var house_leader := context.house_manager.get_house_leader(expected_house)
	_check(house_leader != null, "目标家族有领袖: %s" % identity_id)
	if expect_leader:
		_check(player_noble.is_house_leader and house_leader == player_noble,
			"玩家成为家族领袖: %s" % identity_id)
		_check(player_noble.liege_noble_id.is_empty(), "家族领袖没有上级: %s" % identity_id)
		var kingdom_id: String = str(case["kingdom"])
		if kingdom_id.is_empty():
			# 独立家族身份：玩家是家族领袖，但不加入任何王国，也不成为国王。
			_check(house.kingdom_id.is_empty(), "独立家族不隶属王国: %s" % identity_id)
			_check(
				context.kingdom_manager.get_kingdom_for_house(expected_house) == null,
				"独立家族没有所属王国: %s" % identity_id
			)
			_check(not player_noble.is_king, "独立家族领袖不是国王: %s" % identity_id)
			return
		var kingdom := context.kingdom_manager.get_kingdom(kingdom_id)
		_check(kingdom != null, "玩家所属王国存在: %s" % identity_id)
		if kingdom != null:
			_check(kingdom.king_noble_id == player_noble.lord_id,
				"玩家成为王国国王: %s" % identity_id)
			_check(kingdom.ruling_house_id == expected_house,
				"玩家家族是统治家族: %s" % identity_id)
			_check(house.kingdom_id == kingdom_id, "玩家家族隶属目标王国: %s" % identity_id)
	else:
		_check(not player_noble.is_house_leader, "玩家不是家族领袖: %s" % identity_id)
		_check(house_leader != player_noble, "家族领袖保持原 NPC: %s" % identity_id)
		_check(player_noble.liege_noble_id == house_leader.lord_id,
			"玩家效忠家族领袖: %s" % identity_id)
		_check(house.kingdom_id == str(case["kingdom"]),
			"玩家家族所属王国正确: %s" % identity_id)
		_check(
			context.kingdom_manager.get_kingdom_for_house(expected_house) != null,
			"玩家家族属于正式王国: %s" % identity_id
		)


func _test_world_cleanup(context: WorldContext, case: Dictionary) -> void:
	_check(context.house_manager.get_all_houses().size() == EXPECTED_HOUSE_COUNT,
		"世界中不存在额外玩家测试家族")
	_check(not context.house_manager.has_house("HOUSE_PLAYER"), "不创建 HOUSE_PLAYER")
	# 独立家族身份接管统治家族后，该家族不建立王国，因此只有 5 个王国。
	var expected_kingdoms: int = EXPECTED_KINGDOM_COUNT
	if bool(case["leader"]) and str(case["kingdom"]).is_empty():
		expected_kingdoms = EXPECTED_KINGDOM_COUNT - 1
	_check(context.kingdom_manager.get_all_kingdoms().size() == expected_kingdoms,
		"王国数量符合身份配置: %s" % str(case["identity_id"]))
	if expected_kingdoms < EXPECTED_KINGDOM_COUNT:
		_check(
			context.kingdom_manager.get_kingdom(WorldInitializer.KINGDOM_VAILA_ID) == null,
			"独立家族身份不建立瓦伊拉王国"
		)
	_check(_find_settlement_by_name(context, "青禾村") == null, "青禾村已移除")
	_check(_find_settlement_by_name(context, "北境村") == null, "北境村已移除")
	_check(_find_party_by_name(context, "北境巡逻队") == null, "北境巡逻队已移除")
	_check(context.house_manager.get_house_settlements("HOUSE_MOXIXI").size() == 2,
		"墨西西拥有墨西西堡与墨西西村，且不再拥有北境村")
	_check(context.house_manager.get_house_settlements("HOUSE_PLAYER").is_empty(),
		"不存在玩家测试家族封地")


func _test_save_roundtrip(context: WorldContext, case: Dictionary) -> void:
	var identity_id: String = str(case["identity_id"])
	var save := context.to_save_data()
	_check(save.player.get("identity_id", "") == identity_id,
		"存档保存身份 ID: %s" % identity_id)
	_check(save.player.get("player_house_id", "") == str(case["house"]),
		"存档保存玩家家族: %s" % identity_id)
	var parsed := SaveData.from_dict(save.to_dict())
	_check(parsed != null, "存档可解析: %s" % identity_id)
	if parsed == null:
		return
	var restored := WorldContext.new()
	restored.name = "IdentityStartupRestored"
	add_child(restored)
	_check(restored.load_from_save_data(parsed), "读档成功: %s" % identity_id)
	if not bool(case["noble"]):
		_check(restored.get_player_house() == null, "平民读档后仍无家族: %s" % identity_id)
		_check(restored.get_player_noble() == null, "平民读档后不被补成贵族: %s" % identity_id)
		_check(restored.player_lord_id.is_empty(), "平民读档后无贵族 ID: %s" % identity_id)
	else:
		_check(restored.get_player_house() != null, "贵族读档后恢复家族: %s" % identity_id)
		var noble := restored.get_player_noble()
		_check(noble != null, "贵族读档后恢复玩家贵族: %s" % identity_id)
		if noble != null:
			_check(noble.house_id == str(case["house"]), "读档恢复家族归属: %s" % identity_id)
			if bool(case["leader"]):
				var kingdom_id: String = str(case["kingdom"])
				if kingdom_id.is_empty():
					_check(noble.is_house_leader and not noble.is_king,
						"读档保持独立家族领袖身份: %s" % identity_id)
				else:
					var kingdom := restored.kingdom_manager.get_kingdom(kingdom_id)
					_check(kingdom != null and kingdom.king_noble_id == noble.lord_id,
						"读档恢复玩家国王身份: %s" % identity_id)
	_destroy_world(restored)


func _create_world(identity: IdentityDefinition) -> WorldContext:
	var context := WorldContext.new()
	context.name = "IdentityStartupContext"
	add_child(context)
	if not WorldInitializer.create_new_world(context, identity):
		_check(false, "创建世界: %s" % identity.identity_id)
		_destroy_world(context)
		return null
	_check(context.is_valid_world(), "世界有效: %s" % identity.identity_id)
	return context


func _destroy_world(context: WorldContext) -> void:
	if context == null or not is_instance_valid(context):
		return
	if context.get_parent() == self:
		remove_child(context)
	context.free()


func _find_settlement_by_name(
	context: WorldContext, display_name: String
) -> SettlementData:
	for settlement: SettlementData in context.settlement_manager.get_all_settlements():
		if settlement != null and settlement.display_name == display_name:
			return settlement
	return null


func _find_party_by_name(context: WorldContext, party_name: String) -> PartyData:
	for party: PartyData in context.party_manager.get_all_parties():
		if party != null and party.party_name == party_name:
			return party
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[identity-startup] OK: %s" % message)
	else:
		_failed = true
		push_error("[identity-startup] FAIL: %s" % message)
