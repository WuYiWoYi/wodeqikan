extends Node
## 玩家阵营敌对关系与大地图表现测试。
## 覆盖：主动攻击宣战、王国连带敌对、无王国玩家、加入王国同阵营、
## 王国战争继承、部队外环与建筑名称底板颜色、宣战记录存档往返。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . \
##     res://Tests/SystemTests/player_faction_relation_ui_test.tscn

var _failed: bool = false
var _context: WorldContext = null
var _map: Node = null
var _player: PartyData = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[playerfaction] 测试失败")
		get_tree().quit(1)
	else:
		print("[playerfaction] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)

	_context = WorldContext.new()
	_context.name = "PlayerFactionRelationContext"
	add_child(_context)
	var catalog := IdentityCatalog.load_default()
	var commoner := catalog.get_identity("IDENTITY_DORAMAN_MERCENARY") \
		if catalog != null else null
	_check(commoner != null, "加载平民身份配置")
	_check(WorldInitializer.create_new_world(_context, commoner), "初始化世界")
	if not _context.is_valid_world():
		return
	# 测试夹具：平民身份无家族；注册独立玩家家族并给一处封地，
	# 用于验证“无王国玩家”的阵营关系与建筑底板。
	var house := _context.house_manager.register_house(
		WorldInitializer.HOUSE_PLAYER_ID,
		WorldInitializer.PLAYER_HOUSE_NAME,
		WorldInitializer.FAMILY_PLAYER_ID,
		true
	)
	_check(house != null, "注册独立玩家家族")
	_context.player_house_id = house.house_id
	var player_settlement := _find_settlement("埃克托")
	_check(player_settlement != null, "找到测试玩家封地")
	if player_settlement != null:
		player_settlement.owner_house_id = house.house_id
	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id
	_player = _context.get_player_party()
	# 玩家部队绑定测试家族，使部队级关系能走家族关系分支。
	_player.family_id = house.house_id

	var packed := load("res://Scenes/WorldMap/world_map.tscn") as PackedScene
	_map = packed.instantiate()
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame

	var bari_party := _find_party("巴里骑士")
	var burknania_party := _find_party("伯克纳骑士")
	var moxixi_party := _find_party("墨西西骑士")
	var taina_party := _find_party("泰纳骑士")
	var vaila_party := _find_party("瓦伊拉骑士")
	var bari_settlement := _find_settlement("巴里")
	var moxixi_settlement := _find_settlement("墨西西")
	_check(
		bari_party != null and burknania_party != null and moxixi_party != null
			and taina_party != null and vaila_party != null
			and bari_settlement != null and moxixi_settlement != null
			and player_settlement != null,
		"测试所需部队与地点存在"
	)
	if bari_party == null or burknania_party == null or moxixi_party == null \
			or taina_party == null or vaila_party == null \
			or bari_settlement == null or moxixi_settlement == null \
			or player_settlement == null:
		return

	_test_initial_visuals(
		bari_party, bari_settlement, moxixi_settlement, player_settlement
	)
	_test_kingdom_wide_hostility(
		bari_party, burknania_party, moxixi_party, bari_settlement, moxixi_settlement
	)
	_test_independent_house_hostility(bari_party, burknania_party, bari_settlement)
	_test_join_kingdom_and_war(
		moxixi_party, taina_party, moxixi_settlement
	)
	_test_attack_entry_declares_war(vaila_party)
	_test_persistence()


func _test_initial_visuals(
	bari_party: PartyData,
	bari_settlement: SettlementData,
	moxixi_settlement: SettlementData,
	player_settlement: SettlementData
) -> void:
	var factions := _context.faction_manager
	_check(
		factions.get_player_relation_for_party(_player.party_id)
			== FactionManager.PlayerRelation.ALLIED,
		"玩家本人部队与玩家同阵营"
	)
	_check(
		_map.call("get_party_player_relation", bari_party.party_id)
			== FactionManager.PlayerRelation.NEUTRAL,
		"未宣战时巴里骑士中立"
	)
	var player_icon := _icon(_player.party_id)
	var bari_icon := _icon(bari_party.party_id)
	_check(
		player_icon != null and player_icon.is_player
			and player_icon.get_faction_ring_color().is_equal_approx(
				player_icon.get_marker_style().player_ring_color
			),
		"玩家部队保持蓝色外环"
	)
	_check(
		bari_icon != null and bari_icon.get_faction_ring_color().a == 0.0,
		"中立部队不显示阵营外环"
	)
	_check(
		_tag_color(player_settlement).is_equal_approx(
			SettlementNameTag.ALLIED_BACKGROUND_COLOR
		),
		"玩家自有建筑显示绿色底板"
	)
	_check(
		_tag_color(bari_settlement).is_equal_approx(
			SettlementNameTag.BACKGROUND_COLOR
		),
		"中立建筑保持黑色底板"
	)
	_check(
		_tag_color(moxixi_settlement).is_equal_approx(
			SettlementNameTag.BACKGROUND_COLOR
		),
		"其他王国建筑未宣战前保持中立"
	)


func _test_kingdom_wide_hostility(
	bari_party: PartyData,
	burknania_party: PartyData,
	moxixi_party: PartyData,
	bari_settlement: SettlementData,
	moxixi_settlement: SettlementData
) -> void:
	var factions := _context.faction_manager
	_check(
		factions.declare_player_hostility_against_party(bari_party.party_id),
		"玩家攻击巴里骑士触发宣战"
	)
	_check(
		factions.get_player_relation_for_house(WorldInitializer.HOUSE_BARI_ID)
			== FactionManager.PlayerRelation.HOSTILE,
		"被攻击家族敌对"
	)
	_check(
		factions.get_player_relation_for_house(
			WorldInitializer.HOUSE_BURKNANIA_ID
		) == FactionManager.PlayerRelation.HOSTILE,
		"目标所属王国统治家族连带敌对"
	)
	_check(
		factions.get_player_relation_for_house(WorldInitializer.HOUSE_ODESTER_ID)
			== FactionManager.PlayerRelation.HOSTILE,
		"目标王国其他附庸家族连带敌对"
	)
	_check(
		factions.get_player_relation_for_house(WorldInitializer.HOUSE_MOXIXI_ID)
			== FactionManager.PlayerRelation.NEUTRAL,
		"其他王国不受连带影响"
	)
	_check(
		factions.get_party_relation(_player.party_id, bari_party.party_id)
			== FactionManager.Relation.HOSTILE,
		"部队级统一关系识别玩家与目标为敌对"
	)
	_check(
		factions.get_player_relation_for_kingdom(
			WorldInitializer.KINGDOM_BURKNANIA_ID
		) == FactionManager.PlayerRelation.HOSTILE,
		"玩家未加入王国也可与目标王国敌对"
	)

	var bari_icon := _icon(bari_party.party_id)
	var burknania_icon := _icon(burknania_party.party_id)
	var moxixi_icon := _icon(moxixi_party.party_id)
	var style := bari_icon.get_marker_style() if bari_icon != null else null
	_check(
		bari_icon != null and style != null
			and bari_icon.get_player_relation()
				== FactionManager.PlayerRelation.HOSTILE
			and bari_icon.get_faction_ring_color().is_equal_approx(
				style.hostile_ring_color
			),
		"敌对部队显示红色外环"
	)
	_check(
		burknania_icon != null
			and burknania_icon.get_player_relation()
				== FactionManager.PlayerRelation.HOSTILE,
		"同王国其他部队同步变为敌对"
	)
	_check(
		moxixi_icon != null
			and moxixi_icon.get_player_relation()
				== FactionManager.PlayerRelation.NEUTRAL,
		"其他王国部队保持中立"
	)
	_check(
		_tag_color(bari_settlement).is_equal_approx(
			SettlementNameTag.HOSTILE_BACKGROUND_COLOR
		),
		"敌对建筑显示红色半透明底板"
	)
	_check(
		_tag_color(moxixi_settlement).is_equal_approx(
			SettlementNameTag.BACKGROUND_COLOR
		),
		"中立建筑底板保持不变"
	)


func _test_independent_house_hostility(
	bari_party: PartyData, burknania_party: PartyData, bari_settlement: SettlementData
) -> void:
	var factions := _context.faction_manager
	# 让巴里家族脱离王国，验证“无王国家族”只产生自身敌对。
	_context.kingdom_manager.remove_vassal_house(
		WorldInitializer.KINGDOM_BURKNANIA_ID, WorldInitializer.HOUSE_BARI_ID
	)
	factions.clear_player_hostilities()
	_map.call("_refresh_faction_visuals")
	_check(
		factions.declare_player_hostility_against_party(bari_party.party_id),
		"攻击无王国家族仍可宣战"
	)
	_check(
		factions.get_player_relation_for_house(WorldInitializer.HOUSE_BARI_ID)
			== FactionManager.PlayerRelation.HOSTILE,
		"无王国家族本身敌对"
	)
	_check(
		factions.get_player_relation_for_house(
			WorldInitializer.HOUSE_BURKNANIA_ID
		) == FactionManager.PlayerRelation.NEUTRAL,
		"不自动扩展到原王国其他家族"
	)
	_check(
		factions.get_player_hostile_kingdom_ids().is_empty(),
		"无王国家族不产生王国层面宣战"
	)
	_check(
		_context.kingdom_manager.get_enemy_kingdoms(
			WorldInitializer.KINGDOM_BURKNANIA_ID
		).is_empty(),
		"王国之间没有新增战争"
	)
	_check(
		_icon(bari_party.party_id) != null
			and _icon(bari_party.party_id).get_player_relation()
				== FactionManager.PlayerRelation.HOSTILE,
		"独立敌对家族部队显示红色外环"
	)
	_check(
		_icon(burknania_party.party_id) != null
			and _icon(burknania_party.party_id).get_player_relation()
				== FactionManager.PlayerRelation.NEUTRAL,
		"原王国其他部队恢复中立表现"
	)
	_check(
		_tag_color(bari_settlement).is_equal_approx(
			SettlementNameTag.HOSTILE_BACKGROUND_COLOR
		),
		"独立敌对家族建筑显示红色底板"
	)


func _test_join_kingdom_and_war(
	moxixi_party: PartyData,
	taina_party: PartyData,
	moxixi_settlement: SettlementData
) -> void:
	var factions := _context.faction_manager
	_check(
		_context.kingdom_manager.add_vassal_house(
			WorldInitializer.KINGDOM_LORIAK_ID, WorldInitializer.HOUSE_PLAYER_ID
		),
		"玩家家族加入洛里亚克王国"
	)
	_check(
		factions.get_player_relation_for_house(WorldInitializer.HOUSE_MOXIXI_ID)
			== FactionManager.PlayerRelation.ALLIED,
		"同王国其他家族与玩家同阵营"
	)
	_check(
		factions.get_player_relation_for_house(WorldInitializer.HOUSE_OLIN_ID)
			== FactionManager.PlayerRelation.ALLIED,
		"同王国附庸家族与玩家同阵营"
	)
	_check(
		_icon(moxixi_party.party_id) != null
			and _icon(moxixi_party.party_id).get_player_relation()
				== FactionManager.PlayerRelation.ALLIED,
		"同阵营部队切换为绿色外环"
	)
	_check(
		_icon(_player.party_id) != null
			and _icon(_player.party_id).is_player
			and _icon(_player.party_id).get_faction_ring_color().is_equal_approx(
				_icon(_player.party_id).get_marker_style().player_ring_color
			),
		"玩家本人蓝色外环不被绿色覆盖"
	)
	_check(
		_tag_color(moxixi_settlement).is_equal_approx(
			SettlementNameTag.ALLIED_BACKGROUND_COLOR
		),
		"同阵营建筑显示绿色底板"
	)

	_check(
		_context.kingdom_manager.declare_war(
			WorldInitializer.KINGDOM_LORIAK_ID, WorldInitializer.KINGDOM_TAINA_ID
		),
		"洛里亚克王国与泰纳公国开战"
	)
	_check(
		factions.get_player_relation_for_house(WorldInitializer.HOUSE_TAINA_ID)
			== FactionManager.PlayerRelation.HOSTILE,
		"玩家所在王国的敌国成员家族敌对"
	)
	_check(
		_icon(taina_party.party_id) != null
			and _icon(taina_party.party_id).get_player_relation()
				== FactionManager.PlayerRelation.HOSTILE,
		"敌国部队显示红色外环"
	)


func _test_attack_entry_declares_war(vaila_party: PartyData) -> void:
	var factions := _context.faction_manager
	_map.set("_party_latch_id", vaila_party.party_id)
	var session: BattleSession = _map.call("begin_battle_with_party")
	_check(session != null, "玩家主动攻击瓦伊拉骑士创建战斗")
	if session == null:
		return
	_check(
		factions.get_player_relation_for_house(WorldInitializer.HOUSE_VAILA_ID)
			== FactionManager.PlayerRelation.HOSTILE,
		"主动攻击入口触发对目标家族的敌对"
	)
	_check(
		_context.kingdom_manager.are_at_war(
			WorldInitializer.KINGDOM_LORIAK_ID, WorldInitializer.KINGDOM_VAILA_ID
		),
		"玩家所在王国与目标王国正式开战"
	)
	_check(
		_icon(vaila_party.party_id) != null
			and _icon(vaila_party.party_id).get_player_relation()
				== FactionManager.PlayerRelation.HOSTILE,
		"攻击后目标部队立即显示红色外环"
	)
	_context.battle_manager.finish_battle(
		session.battle_id, BattleSession.BattleResult.ABORTED
	)
	_map.set("_battle_transition_started", false)
	TimeManager.clear_pauses()


func _test_persistence() -> void:
	var factions := _context.faction_manager
	var save := _context.to_save_data()
	var saved_houses: Array = save.factions.get("player_hostile_house_ids", [])
	var saved_kingdoms: Array = save.factions.get("player_hostile_kingdom_ids", [])
	_check(
		saved_houses.has(WorldInitializer.HOUSE_BARI_ID)
			and saved_houses.has(WorldInitializer.HOUSE_VAILA_ID),
		"存档记录玩家个人敌对家族"
	)
	# 玩家个人宣战记录只保存自己触发的战争；加入王国后继承的敌对王国
	# 由 KingdomData.enemy_kingdom_ids 保存，不重复写入玩家个人表。
	_check(
		saved_kingdoms.has(WorldInitializer.KINGDOM_VAILA_ID)
			and not saved_kingdoms.has(WorldInitializer.KINGDOM_TAINA_ID),
		"存档记录玩家个人宣战王国"
	)

	var restored := SaveData.from_dict(save.to_dict())
	_check(
		restored != null and not restored.factions.is_empty(),
		"宣战记录可随 SaveData JSON 往返"
	)
	factions.clear_player_hostilities()
	_check(
		factions.get_player_relation_for_house(WorldInitializer.HOUSE_BARI_ID)
			== FactionManager.PlayerRelation.NEUTRAL,
		"清空后敌对关系解除"
	)
	factions.load_from_dict(restored.factions if restored != null else {})
	_check(
		factions.get_player_relation_for_house(WorldInitializer.HOUSE_BARI_ID)
			== FactionManager.PlayerRelation.HOSTILE,
		"读档恢复敌对家族"
	)
	_check(
		factions.get_player_relation_for_house(WorldInitializer.HOUSE_VAILA_ID)
			== FactionManager.PlayerRelation.HOSTILE,
		"读档恢复敌对王国成员家族"
	)


func _icon(party_id: String) -> PartyIcon:
	if _map == null:
		return null
	return _map.call("get_party_icon", party_id) as PartyIcon


func _tag_color(settlement: SettlementData) -> Color:
	if settlement == null:
		return Color.TRANSPARENT
	var tag := _map.call(
		"get_settlement_name_tag", settlement.settlement_id
	) as SettlementNameTag
	return tag.get_background_color() if tag != null else Color.TRANSPARENT


func _find_party(party_name: String) -> PartyData:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party != null and party.party_name == party_name:
			return party
	return null


func _find_settlement(settlement_name: String) -> SettlementData:
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement != null and settlement.display_name == settlement_name:
			return settlement
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[playerfaction] OK: %s" % message)
	else:
		_failed = true
		push_error("[playerfaction] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_map):
		_map.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
