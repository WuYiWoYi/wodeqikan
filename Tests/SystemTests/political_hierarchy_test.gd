extends Node
## 阶段 8 系统测试：贵族 → 家族 → 王国层级、六方势力附庸归属、
## 统一敌我查询、玩家身份家族归属与领袖死亡。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/political_hierarchy_test.tscn

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
	_test_family_ownership_recruitment()
	_test_relations()
	_test_save_roundtrip()
	_test_leader_death()
	_context.queue_free()


func _test_houses_and_kingdoms() -> void:
	_check(_context.house_manager.get_all_houses().size() == 17, "存在 17 个正式家族")
	_check(_context.kingdom_manager.get_all_kingdoms().size() == 6, "存在 6 个王国")
	_check(_context.get_player_house() != null, "玩家家族存在")
	_check(_context.get_player_house().is_player_house, "玩家家族标记正确")
	_check(_context.get_player_house().house_id == HOUSE_EKTOR,
		"默认身份加入埃克托家族而非测试家族")
	_check(not _context.house_manager.has_house("HOUSE_PLAYER"), "不存在测试玩家家族")

	var expected_kingdoms: Array[Dictionary] = [
		{
			"id": KINGDOM_BURKNANIA, "name": "伯克纳王国",
			"ruler": HOUSE_BURKNANIA, "people": "多拉曼人",
			"vassals": [HOUSE_ODESTER, HOUSE_EKTOR, HOUSE_BAFLE, HOUSE_BARI],
			"king_rank": NobleData.Rank.DUKE,
		},
		{
			"id": KINGDOM_FRANI, "name": "弗拉尼王国",
			"ruler": HOUSE_FRANI, "people": "布吉多人",
			"vassals": [HOUSE_DINDANI, HOUSE_KONLIA, HOUSE_MIQIQI],
			"king_rank": NobleData.Rank.DUKE,
		},
		{
			"id": KINGDOM_VAILA, "name": "瓦伊拉伯国",
			"ruler": HOUSE_VAILA, "people": "布吉多人",
			"vassals": [],
			"king_rank": NobleData.Rank.BARON,
		},
		{
			"id": KINGDOM_LORIAK, "name": "洛里亚克王国",
			"ruler": HOUSE_LORIAK, "people": "洛里斯人",
			"vassals": [HOUSE_OLIN, HOUSE_MOXIXI, HOUSE_ROSVIK],
			"king_rank": NobleData.Rank.DUKE,
		},
		{
			"id": KINGDOM_TAINA, "name": "泰纳伯公国",
			"ruler": HOUSE_TAINA, "people": "蒙卡人",
			"vassals": [],
			"king_rank": NobleData.Rank.DUKE,
		},
		{
			"id": KINGDOM_VALEMON, "name": "瓦勒蒙联盟",
			"ruler": HOUSE_VALEMON, "people": "蒙卡人",
			"vassals": [HOUSE_KRIKA],
			"king_rank": NobleData.Rank.BARON,
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
			_check(king.rank == spec["king_rank"], "国王爵位符合配置")
			_check(king.is_house_leader, "国王兼任家族领袖")
		_check(kingdom.enemy_kingdom_ids.is_empty(), "初始没有战争")

	# 家族全部指定贵族与领地归属。
	var bari_leader := _context.house_manager.get_house_leader(HOUSE_BARI)
	var moxixi_leader := _context.house_manager.get_house_leader(HOUSE_MOXIXI)
	var olin_leader := _context.house_manager.get_house_leader(HOUSE_OLIN)
	_check(bari_leader != null and bari_leader.rank == NobleData.Rank.BARON, "巴里保留男爵领袖")
	_check(moxixi_leader != null and moxixi_leader.rank == NobleData.Rank.BARON, "墨西西保留男爵领袖")
	_check(olin_leader != null and olin_leader.rank == NobleData.Rank.BARON, "奥林保留男爵领袖")
	_check(bari_leader != null and bari_leader.display_name == "埃尔韦·德·巴里", "巴里领袖姓名正确")
	_check(_context.house_manager.get_house_settlements(HOUSE_BARI).size() == 3, "巴里有 3 处封地")
	_check(_context.house_manager.get_house_settlements(HOUSE_MOXIXI).size() == 2, "墨西西有 2 处封地")
	_check(_context.house_manager.get_house_settlements(HOUSE_BURKNANIA).size() == 5, "伯克纳有 5 处封地")
	_check(_context.house_manager.get_house_settlements(HOUSE_OLIN).size() == 2, "奥林有 2 处封地")
	_check(_context.house_manager.get_house_settlements(HOUSE_EKTOR).size() == 6, "埃克托有 6 处封地")
	_check(_context.house_manager.get_house_settlements(HOUSE_BAFLE).size() == 2, "巴夫勒有 2 处封地")
	_check(_context.house_manager.get_house_settlements(HOUSE_VAILA).size() == 2, "瓦伊拉有 2 处封地")

	var expected_members: Dictionary = {
		# 埃克托家族为 4 名配置贵族 + 默认身份玩家。
		HOUSE_BURKNANIA: 4, HOUSE_ODESTER: 3, HOUSE_EKTOR: 5,
		HOUSE_BAFLE: 2, HOUSE_BARI: 3, HOUSE_FRANI: 4, HOUSE_DINDANI: 2,
		HOUSE_KONLIA: 2, HOUSE_MIQIQI: 3, HOUSE_VAILA: 2, HOUSE_LORIAK: 4,
		HOUSE_OLIN: 2, HOUSE_MOXIXI: 2, HOUSE_ROSVIK: 4, HOUSE_TAINA: 4,
		HOUSE_VALEMON: 4, HOUSE_KRIKA: 2,
	}
	var total_members: int = 0
	var npc_members: int = 0
	for house_id: String in expected_members:
		var house_nobles := _context.house_manager.get_house_nobles(
			house_id, true
		)
		_check(
			house_nobles.size() == int(expected_members[house_id]),
			"家族成员数正确: %s" % house_id
		)
		total_members += house_nobles.size()
		for noble: NobleData in house_nobles:
			if noble != null and not noble.is_player_lord:
				npc_members += 1
	# 51 名 NPC 贵族 + 默认身份玩家。
	_check(npc_members == 51, "17 个家族共 51 名 NPC 贵族")
	_check(total_members == 52, "家族成员合计包含玩家 1 名")
	_check(_context.noble_manager.get_all_nobles().size() == 52,
		"世界共 52 名贵族（含玩家）")

	# 17 个家族的正式领袖姓名。
	var expected_leaders: Dictionary = {
		HOUSE_BAFLE: "威廉·德·巴夫勒",
		HOUSE_ODESTER: "罗杰·德·奥德斯特",
		HOUSE_EKTOR: "阿莫里·德·埃克托",
		HOUSE_BURKNANIA: "奥东·德·伯克纳",
		HOUSE_BARI: "埃尔韦·德·巴里",
		HOUSE_DINDANI: "康拉",
		HOUSE_KONLIA: "圣维克",
		HOUSE_FRANI: "奥利维耶",
		HOUSE_MIQIQI: "休",
		HOUSE_MOXIXI: "墨西西里曼",
		HOUSE_OLIN: "卡斯泰尔",
		HOUSE_LORIAK: "菲利普",
		HOUSE_ROSVIK: "蒙塞尔",
		HOUSE_TAINA: "贝洛夫",
		HOUSE_VALEMON: "卢卡",
		HOUSE_KRIKA: "杜布拉",
		HOUSE_VAILA: "瓦尔登",
	}
	for house_id: String in expected_leaders:
		var leader := _context.house_manager.get_house_leader(house_id)
		_check(
			leader != null and leader.display_name == str(expected_leaders[house_id]),
			"家族领袖姓名正确: %s" % house_id
		)
		_check(leader != null and leader.is_house_leader, "领袖标记唯一有效: %s" % house_id)

	# 六个政治实体的国王姓名。
	var expected_kings: Dictionary = {
		KINGDOM_BURKNANIA: "奥东·德·伯克纳",
		KINGDOM_FRANI: "奥利维耶",
		KINGDOM_LORIAK: "菲利普",
		KINGDOM_TAINA: "贝洛夫",
		KINGDOM_VALEMON: "卢卡",
		KINGDOM_VAILA: "瓦尔登",
	}
	for kingdom_id: String in expected_kings:
		var king := _context.kingdom_manager.get_king(kingdom_id)
		_check(
			king != null and king.display_name == str(expected_kings[kingdom_id]),
			"国王姓名正确: %s" % kingdom_id
		)

	var player_noble := _context.get_player_noble()
	var ektor_leader := _context.house_manager.get_house_leader(HOUSE_EKTOR)
	_check(player_noble != null and player_noble.rank == NobleData.Rank.KNIGHT, "玩家是骑士贵族")
	_check(not player_noble.is_house_leader, "次子不是家族领袖")
	_check(ektor_leader != null and ektor_leader.display_name == "阿莫里·德·埃克托",
		"埃克托家族领袖姓名正确")
	_check(ektor_leader != null and player_noble.liege_noble_id == ektor_leader.lord_id,
		"玩家效忠埃克托家族领袖")
	_check(_context.faction_manager.get_player_relation_for_house(HOUSE_BURKNANIA)
		== FactionManager.PlayerRelation.ALLIED,
		"玩家通过埃克托家族与伯克纳王国同阵营")

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
	_check(_context.noble_manager.get_all_nobles().size() == 52,
		"世界中存在 52 名贵族（51 NPC + 玩家）")
	_check(_context.party_manager.get_all_parties().size() == 56,
		"世界共 56 支部队（51 贵族 + 玩家 + 商队 + 3 强盗）")

	# 上下级关系不能自我引用或形成循环。
	for noble: NobleData in _context.noble_manager.get_all_nobles():
		_check(noble.liege_noble_id != noble.lord_id, "贵族不能成为自己的上级")
		if not noble.liege_noble_id.is_empty():
			_check(
				_context.noble_manager.get_noble(noble.liege_noble_id) != null,
				"上级贵族引用有效"
			)


func _test_family_ownership_recruitment() -> void:
	var fief := _context.fief_recruitment_manager
	var bafle_leader := _context.house_manager.get_house_leader(HOUSE_BAFLE)
	var robert := _find_noble_by_name("罗贝尔·德·巴夫勒")
	var bafle_village := _find_settlement("巴夫勒")
	_check(bafle_leader != null and robert != null, "巴夫勒家族领袖与骑士存在")
	_check(bafle_village != null, "巴夫勒村存在")
	if bafle_village == null or bafle_leader == null or robert == null:
		return
	_check(bafle_village.owner_house_id == HOUSE_BAFLE, "巴夫勒村归巴夫勒家族所有")
	_check(fief.is_authorized_owner(bafle_village, bafle_leader.lord_id),
		"家族领袖可征召家族村庄")
	_check(fief.is_authorized_owner(bafle_village, robert.lord_id),
		"非领袖骑士同样可征召家族村庄")
	var outsider := _context.house_manager.get_house_leader(HOUSE_BARI)
	_check(outsider != null and not fief.is_authorized_owner(
		bafle_village, outsider.lord_id
	), "其他家族成员不能征召巴夫勒村庄")
	# 实际征召同样按家族归属放行：领袖与骑士各成功一次，外家族失败。
	_check(fief.recruit_group(bafle_village.settlement_id, bafle_leader.lord_id),
		"家族领袖可实际征召采邑")
	_check(fief.recruit_group(bafle_village.settlement_id, robert.lord_id),
		"同家族骑士可实际征召采邑")
	_check(outsider != null and not fief.recruit_group(
		bafle_village.settlement_id, outsider.lord_id
	), "外家族成员实际征召被拒绝")

	# 59 处配置领地均有家族所有者，且视觉旗帜与所有者一致；个人所有者字段已移除。
	var owned_count: int = 0
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement == null or not settlement.has_owner():
			continue
		owned_count += 1
		var house := _context.house_manager.get_house(settlement.owner_house_id)
		_check(house != null, "领地家族存在: %s" % settlement.display_name)
		if house != null and not settlement.family_id.is_empty():
			_check(
				house.banner_id == settlement.family_id,
				"领地旗帜与所有者家族一致: %s" % settlement.display_name
			)
	_check(owned_count == 59, "59 处领地有家族所有者")


func _find_noble_by_name(display_name: String) -> NobleData:
	for noble: NobleData in _context.noble_manager.get_all_nobles():
		if noble.display_name == display_name:
			return noble
	return null


func _find_settlement(display_name: String) -> SettlementData:
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement.display_name == display_name:
			return settlement
	return null


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
	# 玩家通过埃克托家族属于伯克纳王国：同王国友好，其他王国未宣战中立。
	_check(faction.is_party_friendly(
		_context.player_party_id, _party_of_house(HOUSE_EKTOR)
	), "玩家与所属埃克托家族友好")
	_check(faction.is_party_friendly(
		_context.player_party_id, _party_of_house(HOUSE_BURKNANIA)
	), "玩家与伯克纳王国友好")
	_check(faction.is_party_friendly(
		_context.player_party_id, _party_of_house(HOUSE_BARI)
	), "玩家与同王国巴里友好")
	_check(faction.is_party_neutral(
		_context.player_party_id, _party_of_house(HOUSE_MOXIXI)
	), "玩家对洛里亚克成员中立")
	_check(faction.is_party_neutral(
		_context.player_party_id, _party_of_house(HOUSE_TAINA)
	), "玩家对泰纳中立")
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
	_check(save.schema_version == 11, "存档版本为 v11")
	_check(save.houses.size() == 17, "存档包含 17 个正式家族")
	_check(save.kingdoms.size() == 6, "存档包含 6 个王国")
	_check(save.nobles.size() == 52, "存档包含 52 名贵族")
	_check(save.player.get("player_house_id", "") == HOUSE_EKTOR, "存档记录玩家家族")
	_check(save.player.get("identity_id", "") == "IDENTITY_EKTOR_SECOND_SON",
		"存档记录身份选择结果")
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
	_check(second.house_manager.get_all_houses().size() == 17, "读档恢复 17 个正式家族")
	_check(second.kingdom_manager.get_all_kingdoms().size() == 6, "读档恢复 6 个王国")
	_check(second.get_player_house() != null, "读档恢复玩家家族")
	_check(second.get_player_house().house_id == HOUSE_EKTOR, "读档恢复埃克托家族归属")
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
		second.faction_manager.is_party_friendly(
			second.player_party_id, _party_of_house_in(second, HOUSE_BURKNANIA)
		),
		"读档后玩家与所属王国保持友好"
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
	# 伯克纳家族有 4 名贵族：国王死亡后按爵位/稳定 ID 推举新领袖并继承王位。
	_check(_context.noble_manager.kill_noble(king.lord_id), "国王死亡被记录")
	_check(not king.alive, "国王标记为死亡")
	_check(not king.is_king, "死亡后移除国王标记")
	_check(not king.is_house_leader, "死亡后移除家族领袖标记")

	var house := _context.house_manager.get_house(HOUSE_BURKNANIA)
	var new_leader := _context.house_manager.get_house_leader(HOUSE_BURKNANIA)
	_check(not house.leader_noble_id.is_empty(), "存活成员中推举出新领袖")
	_check(new_leader != null and new_leader.display_name == "坦雷德·德·伯克纳",
		"按爵位推举男爵为新领袖")
	_check(burknania.is_active, "王国在新领袖产生后保持有效")
	_check(new_leader != null and burknania.king_noble_id == new_leader.lord_id,
		"新领袖继承王位")
	_check(new_leader != null and new_leader.is_king, "新国王带国王标记")


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
