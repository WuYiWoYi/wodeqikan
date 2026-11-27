extends Node
## 阶段 7 系统测试：领主/封地所有权、采邑征召、冒险者候选人、
## AI 领主征召、税收计算与存档往返。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/fief_adventurer_system_test.tscn

## 默认身份（埃克托次子）通过家族所有权获得埃克托村庄的使用权；
## 领地归家族所有，任何家族成员都可征召。
const PLAYER_VILLAGE_NAME: String = "埃克托"

var _failed: bool = false
var _context: WorldContext = null


func _ready() -> void:
	_run()
	if _failed:
		push_error("[fief] 测试失败")
		get_tree().quit(1)
	else:
		print("[fief] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	TimeManager.world_elapsed_seconds = 0.0

	_context = WorldContext.new()
	_context.name = "FiefAdventurerTestContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return
	_assign_player_village()

	_test_ownership()
	_test_fief_recruitment()
	_test_adventurer_recruitment()
	_test_noble_adventurer_recruitment()
	_test_candidate_refresh()
	_test_ai_lord_recruitment()
	_test_save_roundtrip()

	_context.queue_free()


func _test_ownership() -> void:
	var player_lord := _context.get_player_lord()
	_check(player_lord != null and player_lord.is_player_lord, "存在玩家领主")
	_check(
		not _context.player_unit_id.is_empty()
		and _context.get_player_unit() != null,
		"玩家角色 ID 独立持久化"
	)
	var player_village := _player_village()
	_check(player_village != null, "存在玩家封地村庄")
	if player_village == null or player_lord == null:
		return
	_check(
		player_village.owner_house_id == _context.player_house_id,
		"玩家村庄归属玩家所属家族"
	)
	_check(
		player_village.family_id == WorldInitializer.FAMILY_EKTOR_ID,
		"玩家村庄保留埃克托家族旗帜"
	)
	_check(player_village.fief_recruitment_stock == 4, "初始采邑储备为 4 组")
	_check(player_village.adventurer_candidates.size() == 2, "村庄初始 2 名候选人")
	var expected_tax := TaxCalculator.compute_daily_tax(
		player_village.population, player_village.prosperity,
		player_village.tax_base
	)
	_check(player_village.tax_income_per_day == expected_tax, "税收由统一计算器得出")

	var bari_lord := _find_lord_of_family(WorldInitializer.FAMILY_BARI_ID)
	var bari := _find_settlement(WorldInitializer.BARI_VILLAGE_NAME)
	_check(bari_lord != null and bari != null, "NPC 领主与巴里村庄存在")
	if bari_lord != null and bari != null:
		_check(
			not bari_lord.is_player_lord
				and bari.owner_house_id == WorldInitializer.HOUSE_BARI_ID,
			"NPC 家族拥有独立封地"
		)
		_check(
			not bari_lord.party_id.is_empty()
			and _context.party_manager.get_party(bari_lord.party_id) != null,
			"领主关联真实部队"
		)


func _test_fief_recruitment() -> void:
	var village := _player_village()
	var player_lord := _context.get_player_lord()
	if village == null or player_lord == null:
		return
	var party := _context.get_player_party()
	var units_before: int = _context.unit_manager.get_all_units().size()
	var members_before: int = party.member_unit_ids.size()
	var population_before: int = village.population
	var prosperity_before: int = village.prosperity
	var log_before: int = _context.world_log_manager.get_entry_count()

	_check(
		_context.fief_recruitment_manager.recruit_group(
			village.settlement_id, player_lord.lord_id
		),
		"玩家可在自有村庄征召一组采邑"
	)
	var new_count: int = party.member_unit_ids.size() - members_before
	_check(new_count == 6, "一组采邑生成 6 名士兵")
	_check(
		_context.unit_manager.get_all_units().size() == units_before + 6,
		"6 名采邑均通过 UnitManager 创建"
	)
	_check(village.fief_recruitment_stock == 3, "征召后储备减少 1 组")
	_check(
		village.population == population_before - 4,
		"征召扣除 4 点人口"
	)
	_check(
		village.prosperity == prosperity_before - 2,
		"征召扣除 2 点繁荣度"
	)
	_check(
		village.tax_income_per_day == TaxCalculator.compute_daily_tax(
			village.population, village.prosperity, village.tax_base
		),
		"人口/繁荣度变化后重算税收"
	)

	var mounted_count: int = 0
	var has_archer: bool = false
	var has_veteran: bool = false
	for index: int in range(
		party.member_unit_ids.size() - new_count, party.member_unit_ids.size()
	):
		var unit := _context.unit_manager.get_unit(party.member_unit_ids[index])
		if unit == null:
			continue
		if unit.is_mounted:
			mounted_count += 1
		if unit.config_id == "archer_militia":
			has_archer = true
		if unit.config_id == "infantry_veteran":
			has_veteran = true
	_check(mounted_count == 2, "编制包含 2 名骑乘士兵")
	_check(has_archer and has_veteran, "编制包含弓箭手与三级骑兵")
	_check(
		_context.world_log_manager.get_entry_count() == log_before + 1,
		"征召成功写入一条世界日志"
	)
	var last_entry := _context.world_log_manager.get_entries()[
		_context.world_log_manager.get_entry_count() - 1
	]
	_check(
		last_entry.event_type == WorldLogEntry.EventType.FIEF_RECRUITED
		and last_entry.text.contains(village.display_name),
		"封地征召日志使用真实村庄名"
	)

	var bari := _find_settlement(WorldInitializer.BARI_VILLAGE_NAME)
	var before_invalid: int = party.member_unit_ids.size()
	_check(
		bari != null and not _context.fief_recruitment_manager.recruit_group(
			bari.settlement_id, player_lord.lord_id
		),
		"非自有封地拒绝征召"
	)
	_check(
		party.member_unit_ids.size() == before_invalid,
		"失败征召不产生单位"
	)


func _test_adventurer_recruitment() -> void:
	var village := _player_village()
	if village == null:
		return
	village.adventurer_candidates.clear()
	_context.adventurer_recruitment_manager.initialize_settlement(village, true)
	var candidate: AdventurerCandidateData = village.get_available_candidates()[0]
	if candidate == null:
		_check(false, "村庄存在可招募候选人")
		return
	var party := _context.get_player_party()
	var units_before: int = _context.unit_manager.get_all_units().size()
	var members_before: int = party.member_unit_ids.size()
	var log_before: int = _context.world_log_manager.get_entry_count()
	var candidate_name: String = candidate.display_name
	var candidate_appearance: Dictionary = candidate.appearance.duplicate(true)
	_context.player_profile.gold = 10

	_check(
		_context.adventurer_recruitment_manager.recruit_candidate(
			village.settlement_id, candidate.candidate_id, _context.player_profile
		),
		"支付 5 金币招募候选人"
	)
	_check(_context.player_profile.gold == 5, "普通 Tier1 招募只扣除 5 金币")
	_check(
		party.member_unit_ids.size() == members_before + 1
		and _context.unit_manager.get_all_units().size() == units_before + 1,
		"候选人只生成 1 个真实单位"
	)
	_check(
		candidate.status
			== AdventurerCandidateData.Status.RECRUITED_PENDING_DEPARTURE,
		"候选人进入等待离开状态"
	)
	var recruited := _context.unit_manager.get_unit(candidate.unit_id)
	_check(recruited != null and recruited.display_name == candidate_name,
		"招募单位保留随机姓名")
	_check(
		recruited != null and recruited.appearance == candidate_appearance,
		"招募单位沿用候选人持久化外观"
	)
	_check(
		_context.world_log_manager.get_entry_count() == log_before + 1,
		"冒险者招募写入世界日志"
	)
	var last_entry := _context.world_log_manager.get_entries()[
		_context.world_log_manager.get_entry_count() - 1
	]
	_check(
		last_entry.event_type == WorldLogEntry.EventType.ADVENTURER_RECRUITED
		and last_entry.text.contains(village.display_name)
		and last_entry.text.contains(candidate_name),
		"冒险者日志使用真实村庄名与单位名"
	)

	var gold_after: int = _context.player_profile.gold
	var units_after: int = _context.unit_manager.get_all_units().size()
	_check(
		not _context.adventurer_recruitment_manager.recruit_candidate(
			village.settlement_id, candidate.candidate_id, _context.player_profile
		),
		"同一候选人不能重复招募"
	)
	_check(
		_context.player_profile.gold == gold_after
		and _context.unit_manager.get_all_units().size() == units_after,
		"重复招募不扣金币也不产生单位"
	)

	_check(
		_context.adventurer_recruitment_manager.cleanup_departed_candidates(
			village.settlement_id
		) == 1,
		"离开村庄后清理已招募候选人"
	)
	_check(village.get_candidate(candidate.candidate_id) == null,
		"候选人记录已移除")
	_check(_context.unit_manager.get_unit(candidate.unit_id) != null,
		"已招募单位不受候选人清理影响")
	_check(
		_context.adventurer_recruitment_manager.cleanup_departed_candidates(
			village.settlement_id
		) == 0,
		"重复清理是幂等的"
	)


## 普通 Tier3 招募：价格 400、日薪 7、初始战斗经验 2 级，且不是雇佣兵。
func _test_noble_adventurer_recruitment() -> void:
	var village := _player_village()
	var player_lord := _context.get_player_lord()
	if village == null or player_lord == null:
		_check(false, "贵族冒险者测试需要玩家村庄与领主")
		return
	_context.adventurer_recruitment_manager.initialize_settlement(village, false)
	var candidate: AdventurerCandidateData = village.noble_adventurer_candidate
	_check(
		candidate != null and candidate.is_available(),
		"玩家村庄存在可招募的贵族冒险者"
	)
	if candidate == null:
		return
	var party := _context.get_player_party()
	var members_before: int = party.member_unit_ids.size()
	_context.player_profile.gold = 399
	_check(
		not _context.adventurer_recruitment_manager.recruit_candidate(
			village.settlement_id,
			candidate.candidate_id,
			_context.player_profile,
			player_lord.lord_id
		),
		"金币不足 400 时无法招募 Tier3"
	)
	_check(_context.player_profile.gold == 399, "失败不扣金币")
	_check(candidate.is_available(), "失败保留候选人")

	_context.player_profile.gold = 500
	_check(
		_context.adventurer_recruitment_manager.recruit_candidate(
			village.settlement_id,
			candidate.candidate_id,
			_context.player_profile,
			player_lord.lord_id
		),
		"支付 400 金币招募 Tier3"
	)
	_check(_context.player_profile.gold == 100, "Tier3 招募扣除 400 金币")
	_check(party.member_unit_ids.size() == members_before + 1, "Tier3 加入玩家部队")
	var unit := _context.unit_manager.get_unit(candidate.unit_id)
	_check(unit != null, "Tier3 生成真实单位")
	if unit == null:
		return
	_check(unit.level == 2, "Tier3 初始战斗经验为普通士兵（2 级）")
	_check(unit.wage == 7, "Tier3 日薪为 7")
	_check(not unit.is_mercenary, "普通招募的 Tier3 不是雇佣兵")
	_check(unit.can_manage_equipment(), "普通招募的 Tier3 允许管理装备")


func _test_candidate_refresh() -> void:
	var village := _find_settlement(WorldInitializer.BARI_VILLAGE_NAME)
	if village == null:
		return
	village.adventurer_candidates.clear()
	village.adventurer_refresh_elapsed = 0.0
	var interval: float = _context.adventurer_recruitment_manager.get_economy_config().adventurer_refresh_interval
	_context.adventurer_recruitment_manager.tick(interval)
	_check(village.adventurer_candidates.size() == 1, "世界时间推进后刷新候选人")
	_context.adventurer_recruitment_manager.tick(interval * 20.0)
	_check(
		village.adventurer_candidates.size() == 5,
		"候选人数量不超过每村 5 名上限"
	)


func _test_ai_lord_recruitment() -> void:
	var bari := _find_settlement(WorldInitializer.BARI_VILLAGE_NAME)
	var lord := _find_lord_of_family(WorldInitializer.FAMILY_BARI_ID)
	if bari == null or lord == null:
		return
	var party := _context.party_manager.get_party(lord.party_id)
	if party == null:
		return
	var members_before: int = party.member_unit_ids.size()
	var stock_before: int = bari.fief_recruitment_stock
	var log_before: int = _context.world_log_manager.get_entry_count()

	_context.ai_manager._tick_lord_strategic()
	_check(
		lord.current_target_settlement_id == bari.settlement_id
		and lord.current_state == "RECRUITING",
		"AI 领主前往自有封地征召"
	)
	party.world_position = bari.world_position
	party.target_position = bari.world_position
	party.movement_state = PartyData.MovementState.IDLE
	_context.ai_manager._tick_lord_strategic()
	_check(
		party.member_unit_ids.size() == members_before + 6,
		"AI 领主到达后招募 1 组 6 人"
	)
	_check(
		bari.fief_recruitment_stock == stock_before - 1,
		"AI 征召同样消耗封地储备"
	)
	_check(lord.current_state == "IDLE", "征召结束后恢复普通 AI 状态")
	_check(
		_context.world_log_manager.get_entry_count() == log_before + 1,
		"AI 征召写入世界日志且不重复"
	)


func _test_save_roundtrip() -> void:
	var village := _player_village()
	var player_lord := _context.get_player_lord()
	if village == null or player_lord == null:
		return
	var expected_candidate_count: int = village.adventurer_candidates.size()
	var expected_stock: int = village.fief_recruitment_stock
	var expected_population: int = village.population
	var expected_prosperity: int = village.prosperity
	var save := _context.to_save_data()
	_check(not save.lords.is_empty(), "存档包含领主数据")
	_check(
		str(save.player.get("player_lord_id", "")) == _context.player_lord_id,
		"存档包含玩家领主 ID"
	)
	_check(
		str(save.player.get("player_unit_id", "")) == _context.player_unit_id,
		"存档包含玩家角色 ID"
	)

	var restored := WorldContext.new()
	restored.name = "FiefAdventurerRestoredContext"
	add_child(restored)
	_check(restored.load_from_save_data(save), "封地与候选人存档可恢复")
	_check(
		restored.player_lord_id == _context.player_lord_id,
		"玩家领主 ID 往返一致"
	)
	_check(
		restored.player_unit_id == _context.player_unit_id,
		"玩家角色 ID 往返一致"
	)
	var restored_village := _find_settlement_in(restored, PLAYER_VILLAGE_NAME)
	_check(restored_village != null, "恢复玩家村庄")
	if restored_village != null:
		_check(
			restored_village.owner_house_id == _context.player_house_id,
			"封地家族所有权往返一致"
		)
		_check(
			restored_village.fief_recruitment_stock == expected_stock,
			"采邑储备往返一致"
		)
		_check(
			restored_village.population == expected_population
			and restored_village.prosperity == expected_prosperity,
			"人口与繁荣度往返一致"
		)
		_check(
			restored_village.tax_income_per_day == TaxCalculator.compute_daily_tax(
				expected_population, expected_prosperity,
				restored_village.tax_base
			),
			"恢复后税收缓存正确"
		)
		_check(
			restored_village.adventurer_candidates.size()
				== expected_candidate_count,
			"冒险者候选人往返一致"
		)
		for candidate: AdventurerCandidateData in restored_village.adventurer_candidates:
			_check(
				not candidate.appearance.is_empty(),
				"候选人外观持久化"
			)
			break
	restored.queue_free()


func _assign_player_village() -> void:
	var village := _find_settlement(PLAYER_VILLAGE_NAME)
	var player_house := _context.get_player_house()
	if village == null or player_house == null:
		return
	village.owner_house_id = player_house.house_id


func _player_village() -> SettlementData:
	return _find_settlement(PLAYER_VILLAGE_NAME)


func _find_settlement(display_name: String) -> SettlementData:
	return _find_settlement_in(_context, display_name)


static func _find_settlement_in(
	context: WorldContext, display_name: String
) -> SettlementData:
	if context == null:
		return null
	for settlement: SettlementData in context.settlement_manager.get_all_settlements():
		if settlement != null and settlement.display_name == display_name:
			return settlement
	return null


func _find_lord_of_family(family_id: String) -> LordData:
	for lord: LordData in _context.lord_manager.get_all_lords():
		if lord == null:
			continue
		var party := _context.party_manager.get_party(lord.party_id)
		if party != null and party.family_id == family_id:
			return lord
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[fief] OK: %s" % message)
	else:
		_failed = true
		push_error("[fief] FAIL: %s" % message)
