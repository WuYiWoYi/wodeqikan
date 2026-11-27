extends Node
## 阶段 10 阵营关系测试：强盗与所有政治家族贵族部队敌对，
## 同时不破坏同一家族、同一王国、王国战争、商队/治安队等既有关系。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . \
##     res://Tests/SystemTests/faction_bandit_hostility_test.tscn

var _failed: bool = false
var _context: WorldContext = null


func _ready() -> void:
	_run()
	_cleanup()
	if _failed:
		push_error("[banditrelation] 测试失败")
		get_tree().quit(1)
	else:
		print("[banditrelation] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	_context = WorldContext.new()
	_context.name = "BanditHostilityTestContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return

	var bandit := _find_party(WorldInitializer.BANDIT_PARTY_NAME)
	# 新世界每个 familia 只有一支骑士部队：统治家族“伯克纳骑士”由国王指挥，
	# 同王国的巴里骑士是附庸贵族；洛里亚克骑士为另一王国统治者。
	var burknania_king := _find_party(WorldInitializer.BURKNANIA_KNIGHT_PARTY_NAME)
	var burknania_knight := _find_party(WorldInitializer.BARI_KNIGHT_PARTY_NAME)
	var loriak_king := _find_party("洛里亚克骑士")
	var olin_knight := _find_party(WorldInitializer.OLIN_KNIGHT_PARTY_NAME)
	var player := _context.get_player_party()
	var merchant := _find_party(WorldInitializer.TEST_ENEMY_PARTY_NAME)
	var guard := _find_party(WorldInitializer.GUARD_PARTY_NAME)
	_check(
		bandit != null and burknania_king != null and burknania_knight != null
			and loriak_king != null and olin_knight != null and player != null
			and merchant != null and guard != null,
		"测试所需部队存在"
	)
	if bandit == null or burknania_king == null or burknania_knight == null \
			or loriak_king == null or olin_knight == null or player == null \
			or merchant == null or guard == null:
		return

	var factions := _context.faction_manager
	_check(
		factions.get_party_relation(bandit.party_id, burknania_king.party_id)
			== FactionManager.Relation.HOSTILE,
		"强盗 vs 伯克纳国王：敌对"
	)
	_check(
		factions.get_party_relation(bandit.party_id, burknania_knight.party_id)
			== FactionManager.Relation.HOSTILE,
		"强盗 vs 伯克纳附庸贵族：敌对"
	)
	_check(
		factions.get_party_relation(bandit.party_id, loriak_king.party_id)
			== FactionManager.Relation.HOSTILE,
		"强盗 vs 洛里亚克国王：敌对"
	)
	_check(
		factions.get_party_relation(bandit.party_id, olin_knight.party_id)
			== FactionManager.Relation.HOSTILE,
		"强盗 vs 洛里亚克附庸贵族：敌对"
	)
	_check(
		factions.get_party_relation(bandit.party_id, player.party_id)
			== FactionManager.Relation.HOSTILE,
		"强盗 vs 玩家家族贵族：敌对"
	)

	# 同家族两支部队：只用于关系查询，不需要成员。
	var bari_one := _context.party_manager.create_party(
		FactionManager.LOCAL_FACTION_ID, Vector2(100.0, 100.0), "巴里甲"
	)
	bari_one.family_id = WorldInitializer.FAMILY_BARI_ID
	bari_one.party_kind = PartyData.PartyKind.FAMILY
	var bari_two := _context.party_manager.create_party(
		FactionManager.LOCAL_FACTION_ID, Vector2(120.0, 100.0), "巴里乙"
	)
	bari_two.family_id = WorldInitializer.FAMILY_BARI_ID
	bari_two.party_kind = PartyData.PartyKind.FAMILY
	_check(
		factions.get_party_relation(bari_one.party_id, bari_two.party_id)
			== FactionManager.Relation.FRIENDLY,
		"同一家族贵族之间：友好"
	)
	_check(
		factions.get_party_relation(
			burknania_king.party_id, burknania_knight.party_id
		) == FactionManager.Relation.FRIENDLY,
		"同一王国的不同家族贵族：友好"
	)
	_check(
		factions.get_party_relation(burknania_king.party_id, loriak_king.party_id)
			== FactionManager.Relation.NEUTRAL,
		"不同王国未宣战时：中立"
	)
	_check(
		_context.kingdom_manager.declare_war(
			WorldInitializer.KINGDOM_BURKNANIA_ID, WorldInitializer.KINGDOM_LORIAK_ID
		),
		"可声明王国战争"
	)
	_check(
		factions.get_party_relation(burknania_king.party_id, loriak_king.party_id)
			== FactionManager.Relation.HOSTILE,
		"伯克纳王国 vs 洛里亚克王国：宣战后敌对"
	)
	_check(
		factions.get_party_relation(burknania_knight.party_id, olin_knight.party_id)
			== FactionManager.Relation.HOSTILE,
		"战争传播到双方附庸家族"
	)
	_context.kingdom_manager.end_war(
		WorldInitializer.KINGDOM_BURKNANIA_ID, WorldInitializer.KINGDOM_LORIAK_ID
	)
	_check(
		factions.get_party_relation(burknania_king.party_id, loriak_king.party_id)
			== FactionManager.Relation.NEUTRAL,
		"停战后恢复中立"
	)
	_check(
		factions.get_party_relation(merchant.party_id, player.party_id)
			== FactionManager.Relation.NEUTRAL,
		"商队 vs 玩家：保持中立"
	)
	_check(
		factions.get_party_relation(merchant.party_id, guard.party_id)
			== FactionManager.Relation.FRIENDLY,
		"商队 vs 治安队：保持友好"
	)

	# 强盗关系不依赖部队名称：拆分阵营与类型字段后仍成立。
	var renamed_bandit := _context.party_manager.create_party(
		FactionManager.BANDIT_FACTION_ID, Vector2(200.0, 200.0), "任意名称"
	)
	renamed_bandit.party_kind = PartyData.PartyKind.BANDIT
	_check(
		factions.get_party_relation(
			renamed_bandit.party_id, burknania_knight.party_id
		) == FactionManager.Relation.HOSTILE,
		"强盗敌对判断不依赖部队名称"
	)


func _find_party(party_name: String) -> PartyData:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[banditrelation] OK: %s" % message)
	else:
		_failed = true
		push_error("[banditrelation] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	if is_instance_valid(_context):
		_context.queue_free()
