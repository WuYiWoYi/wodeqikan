extends Node
## 阶段 8 系统测试：贵族 → 家族 → 王国层级、附庸归属、
## 统一敌我查询、玩家中立与领袖死亡推举。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/political_hierarchy_test.tscn

const HOUSE_PLAYER: String = "HOUSE_PLAYER"
const HOUSE_BARI: String = "HOUSE_BARI"
const HOUSE_MOXIXI: String = "HOUSE_MOXIXI"
const HOUSE_BURKNANIA: String = "HOUSE_BURKNANIA"
const HOUSE_OLIN: String = "HOUSE_OLIN"
const KINGDOM_BURKNANIA: String = "KINGDOM_BURKNANIA"
const KINGDOM_OLIN: String = "KINGDOM_OLIN"

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
	_check(_context.house_manager.get_all_houses().size() == 5, "存在 5 个家族")
	_check(_context.kingdom_manager.get_all_kingdoms().size() == 2, "存在 2 个王国")
	_check(_context.get_player_house() != null, "玩家家族存在")
	_check(_context.get_player_house().is_player_house, "玩家家族标记正确")

	var burknania := _context.kingdom_manager.get_kingdom(KINGDOM_BURKNANIA)
	var olin := _context.kingdom_manager.get_kingdom(KINGDOM_OLIN)
	_check(burknania != null and olin != null, "两个王国均可查询")
	if burknania == null or olin == null:
		return
	_check(burknania.ruling_house_id == HOUSE_BURKNANIA, "伯克纳王国统治家族正确")
	_check(olin.ruling_house_id == HOUSE_OLIN, "奥林王国统治家族正确")
	_check(burknania.has_vassal(HOUSE_MOXIXI), "墨西西是伯克纳附庸")
	_check(olin.has_vassal(HOUSE_BARI), "巴里是奥林附庸")
	_check(burknania.is_at_war_with(KINGDOM_OLIN), "伯克纳对奥林宣战")
	_check(olin.is_at_war_with(KINGDOM_BURKNANIA), "奥林对伯克纳宣战（对称）")

	var burknania_king := _context.kingdom_manager.get_king(KINGDOM_BURKNANIA)
	var olin_king := _context.kingdom_manager.get_king(KINGDOM_OLIN)
	_check(burknania_king != null and burknania_king.is_king, "伯克纳国王有效并带国王标记")
	_check(olin_king != null and olin_king.is_king, "奥林国王有效并带国王标记")
	if burknania_king != null:
		_check(burknania_king.rank == NobleData.Rank.DUKE, "伯克纳国王为公爵级")
		_check(burknania_king.is_house_leader, "伯克纳国王兼任家族领袖")

	# 旧家族保留原有领袖、贵族与封地，只增加王国归属。
	var bari_leader := _context.house_manager.get_house_leader(HOUSE_BARI)
	var moxixi_leader := _context.house_manager.get_house_leader(HOUSE_MOXIXI)
	_check(bari_leader != null and bari_leader.rank == NobleData.Rank.BARON, "巴里保留男爵领袖")
	_check(moxixi_leader != null and moxixi_leader.rank == NobleData.Rank.BARON, "墨西西保留男爵领袖")
	_check(_context.house_manager.get_house_settlements(HOUSE_BARI).size() >= 2, "巴里保留并扩展封地")
	_check(_context.house_manager.get_house_settlements(HOUSE_MOXIXI).size() >= 2, "墨西西保留并扩展封地")

	var player_noble := _context.get_player_noble()
	_check(player_noble != null and player_noble.rank == NobleData.Rank.KNIGHT, "玩家是骑士贵族")
	_check(player_noble.is_house_leader, "玩家是家族领袖")
	_check(player_noble.liege_noble_id.is_empty(), "玩家无上级，保持独立")


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
	_check(_context.noble_manager.get_all_nobles().size() == 7, "世界中存在 7 名贵族")

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
	# 王国战争传播到所有成员家族。
	_check(faction.are_houses_hostile(HOUSE_BURKNANIA, HOUSE_OLIN), "伯克纳↔奥林敌对")
	_check(faction.are_houses_hostile(HOUSE_MOXIXI, HOUSE_OLIN), "墨西西↔奥林敌对")
	_check(faction.are_houses_hostile(HOUSE_BURKNANIA, HOUSE_BARI), "伯克纳↔巴里敌对")
	_check(faction.are_houses_hostile(HOUSE_MOXIXI, HOUSE_BARI), "墨西西↔巴里敌对")
	# 同王国成员友好。
	_check(faction.is_party_friendly(
		_party_of_house(HOUSE_BURKNANIA), _party_of_house(HOUSE_MOXIXI)
	), "伯克纳与墨西西友好")
	_check(faction.is_party_friendly(
		_party_of_house(HOUSE_OLIN), _party_of_house(HOUSE_BARI)
	), "奥林与巴里友好")
	# 玩家对两个王国及所有家族保持中立。
	for house_id: String in [
		HOUSE_BURKNANIA, HOUSE_OLIN, HOUSE_BARI, HOUSE_MOXIXI
	]:
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
	_check(save.schema_version == 5, "存档版本为 v5")
	_check(save.houses.size() == 5, "存档包含 5 个家族")
	_check(save.kingdoms.size() == 2, "存档包含 2 个王国")
	_check(save.nobles.size() == 7, "存档包含 7 名贵族")
	_check(save.player.get("player_house_id", "") == HOUSE_PLAYER, "存档记录玩家家族")

	var loaded := SaveData.from_dict(save.to_dict())
	_check(loaded != null, "存档可解析")
	if loaded == null:
		return
	var second := WorldContext.new()
	second.name = "PoliticalHierarchySecondContext"
	add_child(second)
	_check(second.load_from_save_data(loaded), "政治数据读档成功")
	_check(second.house_manager.get_all_houses().size() == 5, "读档恢复 5 个家族")
	_check(second.kingdom_manager.get_all_kingdoms().size() == 2, "读档恢复 2 个王国")
	_check(second.get_player_house() != null, "读档恢复玩家家族")
	_check(
		second.kingdom_manager.get_kingdom(KINGDOM_BURKNANIA).has_vassal(HOUSE_MOXIXI),
		"读档恢复附庸关系"
	)
	_check(
		second.faction_manager.are_houses_hostile(HOUSE_BURKNANIA, HOUSE_OLIN),
		"读档恢复战争关系"
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
	_check(_context.noble_manager.kill_noble(king.lord_id), "国王死亡被记录")
	_check(not king.alive, "国王标记为死亡")
	_check(not king.is_king, "死亡后移除国王标记")
	_check(not king.is_house_leader, "死亡后移除家族领袖标记")

	var house := _context.house_manager.get_house(HOUSE_BURKNANIA)
	_check(not house.leader_noble_id.is_empty(), "家族推举出新领袖")
	if not house.leader_noble_id.is_empty():
		var new_leader := _context.noble_manager.get_noble(house.leader_noble_id)
		_check(new_leader != null and new_leader.alive, "新领袖存活")
		_check(new_leader.is_house_leader, "新领袖带家族领袖标记")
		# 普通贵族只有骑士级，低于男爵门槛，因此王国进入待处理状态。
		_check(not burknania.is_active, "新领袖爵位不足时王国待处理")
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
