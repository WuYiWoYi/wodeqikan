extends Node
## 雇佣兵世界系统测试：类型/经验/价格、酒馆驻留、玩家与 NPC 招募、
## 装备权限、总量增长/流动、容量与存档往返。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/mercenary_system_test.tscn

const TOWN_NAME: String = WorldInitializer.BURKNANIA_TOWN_NAME

var _failed: bool = false
var _context: WorldContext = null
var _manager: MercenaryManager = null
var _town: SettlementData = null
var _second_town: SettlementData = null


func _ready() -> void:
	_run()
	_cleanup()
	if _failed:
		push_error("[mercenary] 测试失败")
		get_tree().quit(1)
	else:
		print("[mercenary] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	TimeManager.world_elapsed_seconds = 0.0

	_context = WorldContext.new()
	_context.name = "MercenaryTestContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return
	_manager = _context.mercenary_manager
	_town = _find_settlement(TOWN_NAME)
	_check(_town != null, "找到初始城镇")

	_test_initial_state()
	_test_price_rules()
	_test_player_recruitment()
	_test_failure_paths()
	_test_growth_and_capacity()
	_test_npc_recruitment_priority()
	_test_flow()
	_test_save_roundtrip()
	_test_old_save_initialization()

	_context.queue_free()


func _test_initial_state() -> void:
	_check(_context.player_profile.gold == 10000, "新游戏金币为 10000")
	_check(
		_manager.get_total_pool_count()
			== _context.recruitment_config.mercenary_initial_count,
		"初始雇佣兵总量来自统一配置"
	)
	if _town != null:
		_check(
			_manager.get_stationed_count(_town.settlement_id)
				<= _manager.get_tavern_capacity(),
			"城镇酒馆不超过容量上限"
		)
	_check(
		_manager.get_stationed_count(_town.settlement_id)
			+ _manager.get_waiting_count()
			+ _manager.get_traveling_count()
			== _manager.get_total_pool_count(),
		"雇佣兵状态互斥且总数守恒"
	)

	var seen_ids: Dictionary = {}
	for mercenary: MercenaryData in _manager.get_all_mercenaries():
		_check(not seen_ids.has(mercenary.mercenary_id), "雇佣兵 ID 唯一")
		seen_ids[mercenary.mercenary_id] = true
		_check(mercenary.tier == 2 or mercenary.tier == 3, "只生成 Tier 2/3")
		_check(
			mercenary.level >= 2 and mercenary.level <= 4,
			"初始经验只允许普通士兵/老兵/精锐"
		)
		var config := _context.unit_manager.get_unit_config(mercenary.config_id)
		_check(config != null, "雇佣兵兵种配置存在")
		if config == null:
			continue
		var mount_slot: String = EquipmentConfig.SLOT_NAMES[
			EquipmentConfig.Slot.MOUNT
		]
		_check(
			mercenary.mounted == config.default_equipment.has(mount_slot),
			"骑马状态与实际默认坐骑一致"
		)
		if mercenary.config_id == "mercenary_rogue_knight":
			_check(not mercenary.mounted, "无赖骑士没有坐骑")

		# 雇佣兵外观由显式身份决定，不依赖名称：
		# 等级罩袍、无家族长矛、仅无赖骑士拥有专属缨饰。
		var appearance: Dictionary = _manager.get_mercenary_appearance(mercenary)
		var appearance_config: AppearanceConfig = _context.appearance_config
		_check(not appearance.is_empty(), "雇佣兵拥有持久化外观快照")
		_check(
			str(appearance.get("tabard_variant", "")) == "MERCENARY",
			"雇佣兵使用独立罩袍变体"
		)
		_check(
			str(appearance.get("family_id", "")).is_empty(),
			"雇佣兵不属于家族外观"
		)
		_check(
			str(appearance.get("tabard_texture_path", ""))
				== appearance_config.get_mercenary_tabard_texture_path(
					mercenary.tier
				),
			"雇佣兵罩袍按 Tier 选择美术"
		)
		_check(
			str(appearance.get("spear_texture_path", "")).is_empty(),
			"雇佣兵不使用家族长矛外观"
		)
		var plume_path := str(appearance.get("plume_texture_path", ""))
		if appearance_config.mercenary_plume_config_ids.has(
			mercenary.config_id
		):
			_check(
				plume_path == appearance_config.mercenary_plume_texture_path
					and not plume_path.is_empty(),
				"专属缨饰只给予配置指定的雇佣兵"
			)
		else:
			_check(plume_path.is_empty(), "普通雇佣兵不佩戴专属缨饰")

	# 即使当前池中没有无赖骑士，也验证专属缨饰的配置路由。
	var rogue_config := _context.unit_manager.get_unit_config(
		"mercenary_rogue_knight"
	)
	var sergeant_config := _context.unit_manager.get_unit_config(
		"mercenary_sergeant"
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var rogue_appearance := UnitAppearance.build_appearance(
		rogue_config, null, _context.appearance_config, false, rng, true
	)
	var sergeant_appearance := UnitAppearance.build_appearance(
		sergeant_config, null, _context.appearance_config, false, rng, true
	)
	_check(
		str(rogue_appearance.get("plume_texture_path", ""))
			== _context.appearance_config.mercenary_plume_texture_path,
		"无赖骑士获得专属缨饰"
	)
	_check(
		str(sergeant_appearance.get("plume_texture_path", "")).is_empty(),
		"军士不获得无赖骑士缨饰"
	)
	_check(
		not str(sergeant_appearance.get("tabard_texture_path", "")).is_empty(),
		"Tier2 雇佣兵罩袍路径已配置"
	)


func _test_price_rules() -> void:
	var config: RecruitmentConfig = _context.recruitment_config
	_check(config.get_civilian_recruit_cost(1) == 5, "普通 Tier1 招募价格 5")
	_check(config.get_civilian_recruit_cost(3) == 400, "普通 Tier3 招募价格 400")
	_check(config.get_mercenary_recruit_cost(2, 2, false) == 35, "Tier2 基础 35")
	_check(config.get_mercenary_recruit_cost(2, 3, false) == 45, "老兵 +10")
	_check(config.get_mercenary_recruit_cost(2, 4, false) == 65, "精锐 +30")
	_check(
		config.get_mercenary_recruit_cost(2, 4, true) == 95,
		"骑马额外 +30"
	)
	_check(config.get_mercenary_recruit_cost(3, 2, false) == 80, "Tier3 基础 80")
	_check(
		config.get_mercenary_recruit_cost(3, 4, false) == 110,
		"Tier3 精锐累计 +30"
	)
	_check(
		config.get_mercenary_recruit_cost(3, 4, true) == 140,
		"骑马加成与经验加成叠加"
	)

	var tier2 := _context.unit_manager.get_unit_config("mercenary_sergeant")
	var tier3 := _context.unit_manager.get_unit_config("mercenary_rogue_knight")
	_check(tier2 != null and tier2.daily_wage == 4, "Tier2 雇佣兵日薪 4")
	_check(tier3 != null and tier3.daily_wage == 9, "Tier3 雇佣兵日薪 9")
	_check(
		_context.unit_manager.get_unit_config("infantry_militia").daily_wage == 1,
		"普通 Tier1 日薪 1"
	)
	_check(
		_context.unit_manager.get_unit_config("infantry_trained").daily_wage == 3,
		"普通 Tier2 日薪 3"
	)
	_check(
		_context.unit_manager.get_unit_config("infantry_veteran").daily_wage == 7,
		"普通 Tier3 日薪 7"
	)


func _test_player_recruitment() -> void:
	var mercenary := _first_stationed()
	if mercenary == null:
		_check(false, "存在可招募的驻留雇佣兵")
		return
	var price := _manager.get_recruit_price(mercenary)
	var expected_wage := _manager.get_daily_wage(mercenary)
	var gold_before: int = _context.player_profile.gold
	var party := _context.get_player_party()
	var members_before: int = party.member_unit_ids.size()
	var pool_before: int = _manager.get_total_pool_count()
	var mercenary_id: String = mercenary.mercenary_id
	var level: int = mercenary.level
	var expected_appearance: Dictionary = \
		_manager.get_mercenary_appearance(mercenary)

	var result := _manager.recruit_mercenary_for_player(
		mercenary_id,
		_town.settlement_id,
		_context.player_profile,
		_context.player_party_id
	)
	_check(bool(result.get("success", false)), "玩家酒馆招募成功")
	_check(
		_context.player_profile.gold == gold_before - price,
		"招募只扣除统一价格"
	)
	_check(party.member_unit_ids.size() == members_before + 1, "部队增加 1 人")
	_check(_manager.get_total_pool_count() == pool_before - 1, "记录从可招募池移除")
	_check(_manager.get_mercenary(mercenary_id) == null, "同一雇佣兵不可重复招募")

	var unit := _context.unit_manager.get_unit(str(result.get("unit_id", "")))
	_check(unit != null, "招募生成真实单位")
	if unit == null:
		return
	_check(unit.is_mercenary, "雇佣兵身份显式持久化")
	_check(
		unit.recruit_source == UnitData.MERCENARY_RECRUIT_SOURCE,
		"招募来源记录为酒馆雇佣兵"
	)
	_check(unit.level == level, "保留雇佣兵初始战斗经验")
	_check(
		unit.appearance == expected_appearance,
		"招募后的单位外观与酒馆预览一致"
	)
	_check(unit.wage == expected_wage, "日薪来自兵种配置")
	_check(not unit.can_manage_equipment(), "雇佣兵不允许管理装备")

	# 所有装备写入口都必须被拒绝，而不只是 UI 隐藏。
	var mount_slot: String = EquipmentConfig.SLOT_NAMES[EquipmentConfig.Slot.MOUNT]
	_check(
		not _context.unit_manager.equip_item(unit.unit_id, "weapon_sword_01"),
		"雇佣兵不能直接更换武器"
	)
	_check(
		not _context.unit_manager.equip_item_from_holder(
			unit.unit_id, "weapon_sword_01", _context.player_profile
		),
		"雇佣兵不能从背包换装"
	)
	_check(
		not _context.unit_manager.unequip_slot(unit.unit_id, "WEAPON"),
		"雇佣兵不能直接卸下装备"
	)
	_check(
		not _context.unit_manager.unequip_slot_to_holder(
			unit.unit_id, "WEAPON", _context.player_profile
		),
		"雇佣兵不能把装备卸回背包"
	)
	_check(
		not _context.unit_manager.equip_mount(unit.unit_id, "mount_horse_01", _context.player_profile),
		"雇佣兵不能更换坐骑"
	)
	_check(
		not _context.unit_manager.unequip_mount(unit.unit_id, _context.player_profile),
		"雇佣兵不能卸下坐骑"
	)
	_check(
		unit.equipment.get(mount_slot, "") == (
			_unit_default_mount(unit.config_id)
		),
		"雇佣兵原有装备未受拒绝操作影响"
	)

	# 普通士兵仍然可以换装，且物品守恒。
	var normal := _first_normal_unit(party)
	if normal != null:
		var old_weapon: String = str(normal.equipment.get("WEAPON", ""))
		var new_weapon: String = "weapon_bow_01" \
			if old_weapon != "weapon_bow_01" else "weapon_sword_01"
		_context.player_profile.add_item(new_weapon, 1)
		var inventory_before: int = _context.player_profile.get_item_count(
			new_weapon
		)
		_check(
			_context.unit_manager.equip_item_from_holder(
				normal.unit_id, new_weapon, _context.player_profile
			),
			"普通士兵可以从背包更换武器"
		)
		_check(
			_context.player_profile.get_item_count(new_weapon)
				== inventory_before - 1,
			"换装消耗背包物品"
		)
		if not old_weapon.is_empty() and old_weapon != new_weapon:
			_check(
				_context.player_profile.get_item_count(old_weapon) >= 1,
				"旧装备返回背包"
			)
		_check(
			_context.unit_manager.unequip_slot_to_holder(
				normal.unit_id, "WEAPON", _context.player_profile
			),
			"普通士兵可以卸下装备"
		)


func _test_failure_paths() -> void:
	var mercenary := _first_stationed()
	if mercenary == null:
		_check(false, "失败路径需要驻留雇佣兵")
		return
	var party := _context.get_player_party()
	var members_before: int = party.member_unit_ids.size()
	var gold_before: int = _context.player_profile.gold
	var pool_before: int = _manager.get_total_pool_count()

	_context.player_profile.gold = 0
	var result := _manager.recruit_mercenary_for_player(
		mercenary.mercenary_id,
		_town.settlement_id,
		_context.player_profile,
		_context.player_party_id
	)
	_check(not bool(result.get("success", false)), "金币不足招募失败")
	_check(_context.player_profile.gold == 0, "失败不扣金币")
	_check(party.member_unit_ids.size() == members_before, "失败不改变部队")
	_check(_manager.get_total_pool_count() == pool_before, "失败不移除记录")
	_check(
		_manager.get_mercenary(mercenary.mercenary_id) != null,
		"失败后雇佣兵仍可招募"
	)
	_context.player_profile.gold = gold_before

	# 已在别处/已招募的记录不能从当前酒馆再次招募。
	var other_town_id: String = (
		_second_town.settlement_id if _second_town != null else "SETTLEMENT_NONE"
	)
	var stale := _manager.recruit_mercenary_for_player(
		mercenary.mercenary_id,
		other_town_id,
		_context.player_profile,
		_context.player_party_id
	)
	_check(not bool(stale.get("success", false)), "地点不匹配招募失败")
	_check(
		_context.player_profile.gold == gold_before,
		"地点校验失败不扣金币"
	)


func _test_growth_and_capacity() -> void:
	_context.recruitment_config.mercenary_flow_chance = 0.0
	_context.recruitment_config.npc_mercenary_recruit_chance = 0.0
	var pool_before: int = _manager.get_total_pool_count()
	var interval: float = _hours_to_seconds(
		_context.recruitment_config.mercenary_growth_interval_hours
	)
	_manager.tick(interval)
	_check(
		_manager.get_total_pool_count() == pool_before + 1,
		"每 12 游戏小时增加 1 名雇佣兵"
	)
	_check(
		_manager.get_stationed_count(_town.settlement_id)
			<= _manager.get_tavern_capacity(),
		"增长后酒馆仍不超过容量"
	)
	if _town != null:
		_check(
			_manager.get_stationed_count(_town.settlement_id) == 7,
			"唯一的城镇酒馆被填满到 7"
		)
	_check(
		_manager.get_waiting_count()
			== _manager.get_total_pool_count() - 7,
		"超出容量的雇佣兵留在待分配池"
	)


func _test_flow() -> void:
	# 测试专用第二城镇：生产世界仍只有一个城镇，但流动逻辑必须通用。
	_second_town = _context.settlement_manager.create_settlement(
		"测试流动镇",
		SettlementData.SettlementType.TOWN,
		Vector2(2400.0, 1600.0),
		WorldInitializer.LOCAL_FACTION_ID,
		180,
		60
	)
	_check(_second_town != null, "创建测试用第二城镇")
	if _second_town == null:
		return
	_context.recruitment_config.mercenary_flow_chance = 1.0
	_context.recruitment_config.npc_mercenary_recruit_chance = 0.0
	var pool_before: int = _manager.get_total_pool_count()
	var flow_interval: float = _hours_to_seconds(
		_context.recruitment_config.mercenary_flow_interval_hours
	)
	_manager.tick(flow_interval)
	_check(_manager.get_total_pool_count() >= pool_before, "流动不减少总量")
	_check(
		_manager.get_traveling_count() > 0
			or _manager.get_stationed_count(_second_town.settlement_id) > 0,
		"雇佣兵开始向另一个城镇流动"
	)
	var travel: float = _hours_to_seconds(
		_context.recruitment_config.mercenary_travel_duration_hours
	)
	_manager.tick(travel + 0.1)
	_check(
		_manager.get_stationed_count(_second_town.settlement_id) > 0,
		"流动完成后在新城镇酒馆驻留"
	)
	_check(
		_manager.get_stationed_count(_town.settlement_id)
			<= _manager.get_tavern_capacity()
			and _manager.get_stationed_count(_second_town.settlement_id)
				<= _manager.get_tavern_capacity(),
		"每个城镇独立遵守容量上限"
	)
	# 同一记录不能同时出现在两个城镇。
	var town_ids: Dictionary = {}
	for mercenary: MercenaryData in _manager.get_all_mercenaries():
		if mercenary.is_stationed():
			town_ids[mercenary.mercenary_id] = mercenary.settlement_id
	_check(
		town_ids.size() <= _manager.get_total_pool_count(),
		"同一雇佣兵不同时驻留多个酒馆"
	)


func _test_npc_recruitment_priority() -> void:
	_context.recruitment_config.mercenary_flow_chance = 0.0
	_context.recruitment_config.npc_mercenary_recruit_chance = 1.0
	_context.recruitment_config.npc_mercenary_recruit_interval_hours = 0.1
	_context.recruitment_config.npc_mercenary_recruit_max_per_check = 1
	_context.recruitment_config.npc_mercenary_party_size_threshold = 99
	_context.recruitment_config.npc_mercenary_gold_reserve = 0
	_context.recruitment_config.npc_mercenary_town_radius = 3000.0

	# 玩家正在查看的酒馆不会被 NPC 抢购。
	var stationed_town := _town if _manager.get_stationed_count(
		_town.settlement_id
	) > 0 else _second_town
	_check(stationed_town != null, "NPC 招募测试需要驻留雇佣兵")
	if stationed_town == null:
		return
	_manager.set_player_viewing_tavern(stationed_town.settlement_id)
	var pool_before: int = _manager.get_total_pool_count()
	_manager.tick(_hours_to_seconds(0.11))
	_check(
		_manager.get_total_pool_count() == pool_before,
		"玩家正在查看的酒馆不会被 NPC 抢购"
	)

	_manager.set_player_viewing_tavern("")
	for party: PartyData in _context.party_manager.get_all_parties():
		if party != null and not party.is_player_controlled() \
				and party.party_id != _context.player_party_id:
			party.gold = maxi(party.gold, 1000)
	var pool_after: int = _manager.get_total_pool_count()
	var npc_members_before: int = _count_npc_members()
	var player_gold_before: int = _context.player_profile.gold
	_manager.tick(_hours_to_seconds(0.11))
	_check(
		_manager.get_total_pool_count() == pool_after - 1,
		"NPC 从酒馆招募后记录移除"
	)
	_check(
		_count_npc_members() == npc_members_before + 1,
		"NPC 部队通过真实单位路径增加成员"
	)
	_check(
		_context.player_profile.gold == player_gold_before,
		"NPC 招募不影响玩家金币"
	)
	var recruited := _find_npc_mercenary_unit()
	_check(recruited != null and recruited.is_mercenary, "NPC 招募单位为雇佣兵身份")


func _test_save_roundtrip() -> void:
	var payload: Dictionary = _manager.to_dict()
	var records_before: Array[MercenaryData] = _manager.get_all_mercenaries()
	var count_before: int = records_before.size()
	_check(bool(payload.get("initialized", false)), "存档记录已初始化标记")

	var copy := MercenaryManager.new()
	copy.setup(
		_context.unit_manager,
		_context.party_manager,
		_context.settlement_manager,
		_context.noble_manager,
		_context.id_generator,
		_context.recruitment_config,
		_context.family_registry,
		_context.appearance_config
	)
	copy.load_from_dict(payload)
	_check(
		copy.get_total_pool_count() == count_before,
		"读档恢复相同数量的雇佣兵"
	)
	var ids: Dictionary = {}
	for mercenary: MercenaryData in copy.get_all_mercenaries():
		_check(not ids.has(mercenary.mercenary_id), "读档后 ID 不重复")
		ids[mercenary.mercenary_id] = true
		_check(
			mercenary.state == MercenaryData.State.WAITING
				or mercenary.state == MercenaryData.State.STATIONED
				or mercenary.state == MercenaryData.State.TRAVELING,
			"读档恢复合法状态"
		)
	if _town != null:
		_check(
			copy.get_stationed_count(_town.settlement_id)
				<= copy.get_tavern_capacity(),
			"读档后酒馆占用不超容量"
		)
	copy.initialize_world(true)
	_check(
		copy.get_total_pool_count() == count_before,
		"已初始化存档不会重复生成初始雇佣兵"
	)
	_check(
		is_equal_approx(
			float(copy.to_dict().get("growth_elapsed", -1.0)),
			float(payload.get("growth_elapsed", 0.0))
		),
		"读档保留增长计时"
	)


func _test_old_save_initialization() -> void:
	var legacy := MercenaryManager.new()
	legacy.setup(
		_context.unit_manager,
		_context.party_manager,
		_context.settlement_manager,
		_context.noble_manager,
		_context.id_generator,
		_context.recruitment_config,
		_context.family_registry,
		_context.appearance_config
	)
	legacy.load_from_dict({})
	_check(not legacy.is_initialized(), "缺少字段的旧存档视为未初始化")
	legacy.initialize_world(true)
	_check(
		legacy.get_total_pool_count()
			== _context.recruitment_config.mercenary_initial_count,
		"旧存档首次载入只生成一次初始雇佣兵池"
	)


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------


func _first_stationed() -> MercenaryData:
	if _town == null:
		return null
	var stationed := _manager.get_stationed_mercenaries(_town.settlement_id)
	return stationed[0] if not stationed.is_empty() else null


func _first_normal_unit(party: PartyData) -> UnitData:
	if party == null:
		return null
	for unit_id: String in party.member_unit_ids:
		var unit := _context.unit_manager.get_unit(unit_id)
		if unit != null and not unit.is_mercenary and not unit.is_player_character:
			return unit
	return null


func _unit_default_mount(config_id: String) -> String:
	var config := _context.unit_manager.get_unit_config(config_id)
	if config == null:
		return ""
	var mount_slot: String = EquipmentConfig.SLOT_NAMES[EquipmentConfig.Slot.MOUNT]
	return str(config.default_equipment.get(mount_slot, ""))


func _count_npc_members() -> int:
	var total: int = 0
	for party: PartyData in _context.party_manager.get_all_parties():
		if party == null or party.party_id == _context.player_party_id \
				or party.is_player_controlled():
			continue
		total += party.member_unit_ids.size()
	return total


func _find_npc_mercenary_unit() -> UnitData:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party == null or party.party_id == _context.player_party_id \
				or party.is_player_controlled():
			continue
		for unit_id: String in party.member_unit_ids:
			var unit := _context.unit_manager.get_unit(unit_id)
			if unit != null and unit.is_mercenary:
				return unit
	return null


func _find_settlement(settlement_name: String) -> SettlementData:
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement != null and settlement.display_name == settlement_name:
			return settlement
	return null


func _hours_to_seconds(hours: float) -> float:
	return hours * TimeManager.REAL_SECONDS_PER_GAME_HOUR


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[mercenary] OK: %s" % message)
	else:
		_failed = true
		push_error("[mercenary] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_context):
		_context.queue_free()
