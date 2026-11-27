extends Node
## 阶段 8 系统测试：贵族 → 家族 → 王国层级、六方势力附庸归属、
## 统一敌我查询、玩家中立与领袖死亡。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/political_hierarchy_test.tscn

const HOUSE_PLAYER: String = "HOUSE_PLAYER"
const HOUSE_BARI: String = "HOUSE_BARI"
const HOUSE_MOXIXI: String = "HOUSE_MOXIXI"
const HOUSE_BURKNANIA: String = "HOUSE_BURKNANIA"
const HOUSE_OLIN: String = "HOUSE_OLIN"
const HOUSE_ODESTER: String = "HOUSE_ODESTER"
const HOUSE_EKTOR: String = "HOUSE_EKTOR"
const HOUSE_BAFLE: String = "HOUSE_BAFLE"
const HOUSE_FRANI: String = "HOUSE_FRANI"
const HOUSE_DINDANI: String = "HOUSE_DINDANI"
const HOUSE_KONLIA: String = "HOUSE_KONLIA"
const HOUSE_MIQIQI: String = "HOUSE_MIQIQI"
const HOUSE_VAILA: String = "HOUSE_VAILA"
const HOUSE_LORIAK: String = "HOUSE_LORIAK"
const HOUSE_ROSVIK: String = "HOUSE_ROSVIK"
const HOUSE_TAINA: String = "HOUSE_TAINA"
const HOUSE_VALEMON: String = "HOUSE_VALEMON"
const HOUSE_KRIKA: String = "HOUSE_KRIKA"
const KINGDOM_BURKNANIA: String = "KINGDOM_BURKNANIA"
const KINGDOM_FRANI: String = "KINGDOM_FRANI"
const KINGDOM_VAILA: String = "KINGDOM_VAILA"
const KINGDOM_LORIAK: String = "KINGDOM_LORIAK"
const KINGDOM_TAINA: String = "KINGDOM_TAINA"
const KINGDOM_VALEMON: String = "KINGDOM_VALEMON"

var _failed: bool = false
var _context: WorldContext = null


func _ready() -> void:
	_run()
	if _failed:
		push_error("[political] 测试失败")
		get_tree().quit(1)
	else:
		print("[political] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	TimeManager.world_elapsed_seconds = 0.0

	_context = WorldContext.new()
	_context.name = "PoliticalHierarchyTestContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return

	_test_houses_and_kingdoms()
	_test_noble_parties()
	_test_relations()
	_test_save_roundtrip()
	_test_leader_death()
	_context.queue_free()


func _test_houses_and_kingdoms() -> void:
	_check(_context.house_manager.get_all_houses().size() == 18, "存在 18 个家族")
	_check(_context.kingdom_manager.get_all_kingdoms().size() == 6, "存在 6 个王国")
	_check(_context.get_player_house() != null, "玩家家族存在")
	_check(_context.get_player_house().is_player_house, "玩家家族标记正确")

	var expected_kingdoms: Array[Dictionary] = [
		{
			"id": KINGDOM_BURKNANIA, "name": "伯克纳王国",
			"ruler": HOUSE_BURKNANIA, "people": "多拉曼人",
			"vassals": [HOUSE_ODESTER, HOUSE_EKTOR, HOUSE_BAFLE, HOUSE_BARI],
		},
		{
			"id": KINGDOM_FRANI, "name": "弗拉尼伯国",
			"ruler": HOUSE_FRANI, "people": "布吉多人",
			"vassals": [HOUSE_DINDANI, HOUSE_KONLIA, HOUSE_MIQIQI],
		},
		{
			"id": KINGDOM_VAILA, "name": "瓦伊拉王国",
			"ruler": HOUSE_VAILA, "people": "布吉多人",
			"vassals": [],
		},
		{
			"id": KINGDOM_LORIAK, "name": "洛里亚克王国",
			"ruler": HOUSE_LORIAK, "people": "洛里斯人",
			"vassals": [HOUSE_OLIN, HOUSE_MOXIXI, HOUSE_ROSVIK],
		},
		{
			"id": KINGDOM_TAINA, "name": "泰纳公国",
			"ruler": HOUSE_TAINA, "people": "蒙卡人",
			"vassals": [],
		},
		{
			"id": KINGDOM_VALEMON, "name": "瓦勒蒙联盟",
			"ruler": HOUSE_VALEMON, "people": "蒙卡人",
			"vassals": [HOUSE_KRIKA],
		},
	]
	for spec: Dictionary in expected_kingdoms:
		var kingdom := _context.kingdom_manager.get_kingdom(str(spec["id"]))
		_check(kingdom != null, "王国可查询: %s" % str(spec["name"]))
		if kingdom == null:
			continue
		_check(kingdom.kingdom_name == str(spec["name"]), "王国名称正确")
		_check(kingdom.people_name == str(spec["people"]), "民族名称正确")
		_check(kingdom.ruling_house_id == str(spec["ruler"]), "统治家族正确")
		for vassal: String in spec["vassals"] as Array:
			_check(kingdom.has_vassal(vassal), "附庸关系正确: %s" % vassal)
		var king := _context.kingdom_manager.get_king(kingdom.kingdom_id)
		_check(king != null and king.is_king, "国王有效并带国王标记")
		if king != null:
			_check(king.rank == NobleData.Rank.DUKE, "国王为公爵级")
			_check(king.is_house_leader, "国王兼任家族领袖")
		_check(kingdom.enemy_kingdom_ids.is_empty(), "初始没有战争")

	# 旧家族保留原有领袖、贵族与封地，只增加/调整王国归属。
	var bari_leader := _context.house_manager.get_house_leader(HOUSE_BARI)
	var moxixi_leader := _context.house_manager.get_house_leader(HOUSE_MOXIXI)
	var olin_leader := _context.house_manager.get_house_leader(HOUSE_OLIN)
	_check(bari_leader != null and bari_leader.rank == NobleData.Rank.BARON, "巴里保留男爵领袖")
	_check(moxixi_leader != null and moxixi_leader.rank == NobleData.Rank.BARON, "墨西西保留男爵领袖")
	_check(olin_leader != null and olin_leader.rank == NobleData.Rank.BARON, "奥林保留男爵领袖")
	_check(_context.house_manager.get_house_settlements(HOUSE_BARI).size() == 2, "巴里保留 2 处封地")
	_check(_context.house_manager.get_house_settlements(HOUSE_MOXIXI).size() == 2, "墨西西保留 2 处封地")
	_check(_context.house_manager.get_house_settlements(HOUSE_BURKNANIA).size() == 2, "伯克纳保留 2 处封地")
	_check(_context.house_manager.get_house_settlements(HOUSE_OLIN).size() == 2, "奥林保留 2 处封地")
	_check(_context.house_manager.get_house_settlements(HOUSE_PLAYER).size() == 1, "玩家保留青禾村")

	var player_noble := _context.get_player_noble()
	_check(player_noble != null and player_noble.rank == NobleData.Rank.KNIGHT, "玩家是骑士贵族")
	_check(player_noble.is_house_leader, "玩家是家族领袖")
	_check(player_noble.liege_noble_id.is_empty(), "玩家无上级，保持独立")

	# 附庸家族领袖必须效忠本王国国王；统治者无上级。
	for kingdom: KingdomData in _context.kingdom_manager.get_all_kingdoms():
		var king := _context.kingdom_manager.get_king(kingdom.kingdom_id)
		if king == null:
			continue
		for house: HouseData in _context.kingdom_manager.get_vassal_houses(
			kingdom.kingdom_id
		):
			var leader := _context.house_manager.get_house_leader(house.house_id)
			_check(
				leader != null and leader.liege_noble_id == king.lord_id,
				"附庸领袖效忠国王: %s" % house.house_name
			)


func _test_noble_parties() -> void:
	var party_ids: Dictionary = {}
	for noble: NobleData in _context.noble_manager.get_all_nobles():
		_check(not noble.party_id.is_empty(), "贵族 %s 拥有独立部队" % noble.display_name)
		_check(not party_ids.has(noble.party_id), "贵族部队 ID 唯一")
		party_ids[noble.party_id] = true
		var party := _context.party_manager.get_party(noble.party_id)
		_check(party != null, "贵族部队存在: %s" % noble.display_name)
		if party != null:
			_check(
				party.leader_noble_id == noble.lord_id,
				"部队记录指挥贵族: %s" % party.party_name
			)
	_check(_context.noble_manager.get_all_nobles().size() == 18, "世界中存在 18 名贵族")

	# 上下级关系不能自我引用或形成循环。
	for noble: NobleData in _context.noble_manager.get_all_nobles():
		_check(noble.liege_noble_id != noble.lord_id, "贵族不能成为自己的上级")
		if not noble.liege_noble_id.is_empty():
			_check(
				_context.noble_manager.get_noble(noble.liege_noble_id) != null,
				"上级贵族引用有效"
			)


func _test_relations() -> void:
	var faction := _context.faction_manager
	# 同王国成员友好。
	_check(faction.is_party_friendly(
		_party_of_house(HOUSE_BURKNANIA), _party_of_house(HOUSE_BARI)
	), "伯克纳与巴里（同王国）友好")
	_check(faction.is_party_friendly(
		_party_of_house(HOUSE_LORIAK), _party_of_house(HOUSE_OLIN)
	), "洛里亚克与奥林（同王国）友好")
	_check(faction.is_party_friendly(
		_party_of_house(HOUSE_FRANI), _party_of_house(HOUSE_DINDANI)
	), "弗拉尼与丁达尼（同王国）友好")
	_check(faction.is_party_friendly(
		_party_of_house(HOUSE_VALEMON), _party_of_house(HOUSE_KRIKA)
	), "瓦勒蒙与克里卡（同王国）友好")
	# 不同王国但未宣战：中立，不是敌对。
	_check(not faction.are_houses_hostile(HOUSE_BURKNANIA, HOUSE_LORIAK),
		"伯克纳与洛里亚克未宣战")
	_check(not faction.are_houses_hostile(HOUSE_FRANI, HOUSE_TAINA),
		"弗拉尼与泰纳未宣战")
	# 玩家对所有家族保持中立。
	for house_id: String in _context.house_manager.get_all_houses().map(
		func(house: HouseData) -> String: return house.house_id
	):
		if house_id == HOUSE_PLAYER:
			continue
		_check(faction.is_party_neutral(
			_context.player_party_id, _party_of_house(house_id)
		), "玩家对 %s 中立" % house_id)
	# 部队级阵营查询仍然有效（强盗对玩家敌对）。
	var bandits := _find_party_by_name("山道强盗")
	_check(bandits != null, "强盗部队存在")
	if bandits != null:
		_check(
			faction.is_party_hostile(_context.player_party_id, bandits.party_id),
			"无家族部队继续使用阵营关系"
		)


func _test_save_roundtrip() -> void:
	var save := _context.to_save_data()
	_check(save.schema_version == 10, "存档版本为 v10")
	_check(save.houses.size() == 18, "存档包含 18 个家族")
	_check(save.kingdoms.size() == 6, "存档包含 6 个王国")
	_check(save.nobles.size() == 18, "存档包含 18 名贵族")
	_check(save.player.get("player_house_id", "") == HOUSE_PLAYER, "存档记录玩家家族")
	_check(
		(save.kingdoms[KINGDOM_BURKNANIA] as Dictionary).get("people_name", "")
			== "多拉曼人",
		"存档保存民族字段"
	)

	var loaded := SaveData.from_dict(save.to_dict())
	_check(loaded != null, "存档可解析")
	if loaded == null:
		return
	var second := WorldContext.new()
	second.name = "PoliticalHierarchySecondContext"
	add_child(second)
	_check(second.load_from_save_data(loaded), "政治数据读档成功")
	_check(second.house_manager.get_all_houses().size() == 18, "读档恢复 18 个家族")
	_check(second.kingdom_manager.get_all_kingdoms().size() == 6, "读档恢复 6 个王国")
	_check(second.get_player_house() != null, "读档恢复玩家家族")
	_check(
		second.kingdom_manager.get_kingdom(KINGDOM_BURKNANIA).has_vassal(HOUSE_BARI),
		"读档恢复附庸关系"
	)
	_check(
		second.kingdom_manager.get_kingdom(KINGDOM_BURKNANIA).people_name == "多拉曼人",
		"读档恢复民族字段"
	)
	_check(
		not second.faction_manager.are_houses_hostile(HOUSE_BURKNANIA, HOUSE_LORIAK),
		"读档后仍无战争"
	)
	_check(
		second.faction_manager.is_party_neutral(
			second.player_party_id, _party_of_house_in(second, HOUSE_BURKNANIA)
		),
		"读档后玩家仍保持中立"
	)
	for noble: NobleData in second.noble_manager.get_all_nobles():
		if noble.is_player_lord or noble.party_id.is_empty():
			continue
		var party := second.party_manager.get_party(noble.party_id)
		_check(
			party != null and party.leader_noble_id == noble.lord_id,
			"读档恢复部队指挥关系: %s" % noble.display_name
		)
	second.queue_free()


func _test_leader_death() -> void:
	var burknania := _context.kingdom_manager.get_kingdom(KINGDOM_BURKNANIA)
	var king := _context.kingdom_manager.get_king(KINGDOM_BURKNANIA)
	_check(king != null and burknania.is_active, "死亡测试前王国有效")
	if king == null:
		return
	# 新世界每个 NPC 家族只有一名领袖，没有第二继承人；
	# 国王死亡后家族无领袖、王国进入待处理状态，而不是伪造新贵族。
	_check(_context.noble_manager.kill_noble(king.lord_id), "国王死亡被记录")
	_check(not king.alive, "国王标记为死亡")
	_check(not king.is_king, "死亡后移除国王标记")
	_check(not king.is_house_leader, "死亡后移除家族领袖标记")

	var house := _context.house_manager.get_house(HOUSE_BURKNANIA)
	_check(house.leader_noble_id.is_empty(), "无继承人的家族保持无领袖")
	_check(not burknania.is_active, "失去国王的王国进入待处理状态")
	_check(burknania.king_noble_id.is_empty(), "待处理王国不再指向无效国王")


func _party_of_house(house_id: String) -> String:
	return _party_of_house_in(_context, house_id)


func _party_of_house_in(context: WorldContext, house_id: String) -> String:
	var leader := context.house_manager.get_house_leader(house_id)
	if leader == null:
		return ""
	return leader.party_id


func _find_party_by_name(party_name: String) -> PartyData:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[political] OK: %s" % label)
	else:
		_failed = true
		push_error("[political] FAIL: %s" % label)
