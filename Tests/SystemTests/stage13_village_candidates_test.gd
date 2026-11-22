extends Node
## 阶段 13 Step 2 测试：村庄初始冒险者候选人。
## 覆盖独立 Unit 身份、每村上限/去重、非村庄不生成、存档往返不重复、
## 旧存档身份补齐幂等，以及招募后进入玩家部队。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/stage13_village_candidates_test.tscn

const TEST_SLOT: String = "__stage13_candidates__"

var _failed: bool = false
var _context: WorldContext = null


func _ready() -> void:
	await _run()
	SaveManager.delete_save(TEST_SLOT)
	_cleanup()
	if _failed:
		push_error("[s13cand] 测试失败")
		get_tree().quit(1)
	else:
		print("[s13cand] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)

	_context = WorldContext.new()
	_context.name = "Stage13CandidatesContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return

	_test_initial_identities()
	_test_refresh_limit_and_dedup()
	_test_non_village_empty()
	var save := _context.to_save_data()
	_test_save_reload(save)
	_test_recruit_identity(save)
	_test_legacy_migration()


func _test_initial_identities() -> void:
	var villages := _villages_in(_context)
	_check(not villages.is_empty(), "世界包含村庄")
	var max_candidates: int = (
		_context.adventurer_recruitment_manager.get_economy_config()
			.adventurer_max_candidates
	)
	var initial_count: int = (
		_context.adventurer_recruitment_manager.get_economy_config()
			.adventurer_initial_count
	)
	for settlement: SettlementData in villages:
		var count: int = settlement.adventurer_candidates.size()
		_check(
			count == mini(initial_count, max_candidates),
			"村庄 %s 初始候选人数正确（%d）" % [settlement.display_name, count]
		)
		_check(count <= max_candidates, "村庄 %s 不超过上限" % settlement.display_name)
		var seen_ids: Dictionary = {}
		for candidate: AdventurerCandidateData in settlement.adventurer_candidates:
			_check(candidate != null, "候选人不为空")
			if candidate == null:
				continue
			_check(
				not candidate.candidate_id.is_empty(),
				"候选人拥有唯一 ID"
			)
			_check(
				not seen_ids.has(candidate.candidate_id),
				"同一村庄候选人不重复"
			)
			seen_ids[candidate.candidate_id] = true
			_check(
				not candidate.unit_id.is_empty() and not candidate.unit_data.is_empty(),
				"候选人拥有独立 Unit 身份快照"
			)
			_check(
				str(candidate.unit_data.get("unit_id", "")) == candidate.unit_id,
				"身份快照 ID 与候选人索引一致"
			)
			_check(
				str(candidate.unit_data.get("config_id", ""))
					== _context.adventurer_recruitment_manager
						.get_economy_config().adventurer_unit_config_id,
				"候选人使用统一冒险者兵种配置"
			)
			# 招募前不得进入 UnitManager 仓储，也不属于任何部队。
			_check(
				not _context.unit_manager.has_unit(candidate.unit_id),
				"未招募候选人不进入 UnitManager"
			)
			_check(
				str(candidate.unit_data.get("current_party_id", "")).is_empty(),
				"未招募候选人不属于任何部队"
			)
			_check(
				candidate.status == AdventurerCandidateData.Status.AVAILABLE,
				"初始候选人状态为可招募"
			)


func _test_refresh_limit_and_dedup() -> void:
	var interval: float = (
		_context.adventurer_recruitment_manager.get_economy_config()
			.adventurer_refresh_interval
	)
	var max_candidates: int = (
		_context.adventurer_recruitment_manager.get_economy_config()
			.adventurer_max_candidates
	)
	# 模拟多个刷新周期；每村最多补到上限，不能超员或产生重复身份。
	for iteration: int in range(3):
		_context.adventurer_recruitment_manager.tick(interval * 4.0)
	for settlement: SettlementData in _villages_in(_context):
		_check(
			settlement.adventurer_candidates.size() <= max_candidates,
			"刷新后 %s 不超过上限" % settlement.display_name
		)
		var candidate_ids: Dictionary = {}
		var unit_ids: Dictionary = {}
		for candidate: AdventurerCandidateData in settlement.adventurer_candidates:
			if candidate == null:
				continue
			_check(
				not candidate_ids.has(candidate.candidate_id),
				"刷新后候选人不重复"
			)
			candidate_ids[candidate.candidate_id] = true
			_check(
				not candidate.unit_id.is_empty()
					and not unit_ids.has(candidate.unit_id),
				"刷新后单位身份唯一"
			)
			unit_ids[candidate.unit_id] = true
			_check(
				str(candidate.unit_data.get("unit_id", "")) == candidate.unit_id,
				"刷新后身份快照与索引一致"
			)
		_check(
			not settlement.adventurer_candidates.is_empty(),
			"刷新后村庄仍有候选人"
		)


func _test_non_village_empty() -> void:
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement == null \
				or settlement.settlement_type == SettlementData.SettlementType.VILLAGE:
			continue
		_check(
			settlement.adventurer_candidates.is_empty(),
			"非村庄 %s 不生成候选人" % settlement.display_name
		)


func _test_save_reload(save: SaveData) -> void:
	var restored := WorldContext.new()
	restored.name = "Stage13CandidatesRestored"
	add_child(restored)
	_check(restored.load_from_save_data(save), "读档恢复世界")
	if not restored.is_valid_world():
		_check(false, "恢复后的世界有效")
		restored.queue_free()
		return

	var original_total: int = _count_candidates(_context)
	var restored_total: int = _count_candidates(restored)
	_check(
		restored_total == original_total,
		"读档不增减候选人（%d / %d）" % [restored_total, original_total]
	)

	for settlement: SettlementData in _villages_in(_context):
		var loaded_settlement := restored.settlement_manager.get_settlement(
			settlement.settlement_id
		)
		_check(loaded_settlement != null, "读档恢复村庄 %s" % settlement.display_name)
		if loaded_settlement == null:
			continue
		_check(
			loaded_settlement.adventurer_candidates.size()
				== settlement.adventurer_candidates.size(),
			"读档保持 %s 候选人数量" % settlement.display_name
		)
		var original_ids: Array[String] = _candidate_ids(settlement)
		var loaded_ids: Array[String] = _candidate_ids(loaded_settlement)
		_check(original_ids == loaded_ids, "读档保持候选人 ID 与顺序")
		for index: int in range(
			mini(settlement.adventurer_candidates.size(),
				loaded_settlement.adventurer_candidates.size())
		):
			var before: AdventurerCandidateData = settlement.adventurer_candidates[index]
			var after: AdventurerCandidateData = (
				loaded_settlement.adventurer_candidates[index]
			)
			_check(
				before.unit_id == after.unit_id,
				"读档保持候选人 Unit 身份 ID"
			)
			_check(
				str(after.unit_data.get("unit_id", "")) == after.unit_id,
				"读档后身份快照一致"
			)
			_check(
				not restored.unit_manager.has_unit(after.unit_id),
				"读档后未招募候选人仍不进入仓储"
			)

	# 再次初始化同一村庄必须幂等。
	var first_village: SettlementData = _villages_in(restored)[0]
	var count_before: int = first_village.adventurer_candidates.size()
	var created: int = restored.adventurer_recruitment_manager.ensure_candidate_identities(
		first_village
	)
	_check(created == 0, "已有身份的候选人不会重复创建")
	_check(
		first_village.adventurer_candidates.size() == count_before,
		"幂等初始化不增加候选人"
	)
	restored.queue_free()


func _test_recruit_identity(save: SaveData) -> void:
	var restored := WorldContext.new()
	restored.name = "Stage13CandidatesRecruit"
	add_child(restored)
	_check(restored.load_from_save_data(save), "重新读档用于招募测试")
	if not restored.is_valid_world():
		restored.queue_free()
		return

	var village: SettlementData = _villages_in(restored)[0]
	var candidate: AdventurerCandidateData = null
	for entry: AdventurerCandidateData in village.adventurer_candidates:
		if entry != null and entry.is_available():
			candidate = entry
			break
	_check(candidate != null, "找到可招募候选人")
	if candidate == null:
		restored.queue_free()
		return

	var player := restored.get_player_party()
	var unit_id: String = candidate.unit_id
	var candidate_name: String = candidate.display_name
	var level: int = int(candidate.unit_data.get("level", 1))
	var units_before: int = restored.unit_manager.get_all_units().size()
	var members_before: int = player.member_unit_ids.size()

	_check(
		restored.adventurer_recruitment_manager.recruit_candidate(
			village.settlement_id, candidate.candidate_id, restored.player_profile
		),
		"招募候选人成功"
	)
	_check(
		candidate.status
			== AdventurerCandidateData.Status.RECRUITED_PENDING_DEPARTURE,
		"候选人标记为已招募"
	)
	_check(candidate.unit_data.is_empty(), "招募后清空候选人身份快照")
	_check(
		restored.unit_manager.get_all_units().size() == units_before + 1,
		"招募后仓储新增且仅新增一个单位"
	)
	var unit := restored.unit_manager.get_unit(unit_id)
	_check(unit != null, "招募后单位进入 UnitManager")
	if unit != null:
		_check(unit.unit_id == candidate.unit_id, "沿用候选人原单位 ID")
		_check(unit.display_name == candidate_name, "保留候选人名称")
		_check(unit.level == level, "保留候选人等级")
		_check(unit.current_party_id == player.party_id, "单位归属玩家部队")
	_check(
		player.member_unit_ids.has(unit_id)
			and player.member_unit_ids.size() == members_before + 1,
		"招募后加入玩家部队成员列表"
	)
	# 同一候选人不能再次招募，也不能产生第二个单位。
	var units_after: int = restored.unit_manager.get_all_units().size()
	_check(
		not restored.adventurer_recruitment_manager.recruit_candidate(
			village.settlement_id, candidate.candidate_id, restored.player_profile
		),
		"已招募候选人不能重复招募"
	)
	_check(
		restored.unit_manager.get_all_units().size() == units_after,
		"重复招募不产生额外单位"
	)

	# 招募后的存档不能再把单位放回候选人快照（防止读档复制单位）。
	var save_after := restored.to_save_data()
	var reloaded := WorldContext.new()
	reloaded.name = "Stage13CandidatesRecruitReload"
	add_child(reloaded)
	_check(reloaded.load_from_save_data(save_after), "招募后存档可正常读取")
	if reloaded.is_valid_world():
		_check(
			reloaded.unit_manager.has_unit(unit_id),
			"读档后招募单位仍在仓储"
		)
		var loaded_village := reloaded.settlement_manager.get_settlement(
			village.settlement_id
		)
		if loaded_village != null:
			for entry: AdventurerCandidateData in loaded_village.adventurer_candidates:
				_check(
					entry == null or entry.unit_id != unit_id
						or entry.unit_data.is_empty(),
					"读档后同一单位不同时存在于候选人与部队"
				)
	_check(
		not reloaded.unit_manager.has_unit(unit_id)
			or reloaded.party_manager.get_party(player.party_id) != null,
		"读档后归属关系完整"
	)
	reloaded.queue_free()
	restored.queue_free()


func _test_legacy_migration() -> void:
	# 模拟阶段 13 之前的存档：候选人只有名字/外观，没有 Unit 身份。
	var provenance := WorldContext.new()
	provenance.name = "Stage13CandidatesLegacy"
	add_child(provenance)
	_check(WorldInitializer.create_new_world(provenance), "初始化迁移测试世界")
	if not provenance.is_valid_world():
		provenance.queue_free()
		return
	var village: SettlementData = _villages_in(provenance)[0]
	var candidate: AdventurerCandidateData = village.adventurer_candidates[0]
	candidate.unit_id = ""
	candidate.unit_data = {}

	var created: int = (
		provenance.adventurer_recruitment_manager.ensure_candidate_identities(
			village
		)
	)
	_check(created >= 1, "旧候选人补齐独立 Unit 身份")
	_check(
		not candidate.unit_id.is_empty() and not candidate.unit_data.is_empty(),
		"补齐后索引与快照存在"
	)
	var identity_id: String = candidate.unit_id
	var total_after_first: int = _count_candidates(provenance)
	var created_again: int = (
		provenance.adventurer_recruitment_manager.ensure_candidate_identities(
			village
		)
	)
	_check(created_again == 0, "重复补齐不会再次创建身份")
	_check(candidate.unit_id == identity_id, "重复补齐保持同一身份 ID")
	_check(
		_count_candidates(provenance) == total_after_first,
		"重复补齐不增加候选人数量"
	)
	_check(
		not provenance.unit_manager.has_unit(identity_id),
		"补齐的身份仍不属于仓储/部队"
	)
	provenance.queue_free()


func _villages_in(context: WorldContext) -> Array[SettlementData]:
	var villages: Array[SettlementData] = []
	for settlement: SettlementData in context.settlement_manager.get_all_settlements():
		if settlement != null \
				and settlement.settlement_type == SettlementData.SettlementType.VILLAGE:
			villages.append(settlement)
	return villages


func _count_candidates(context: WorldContext) -> int:
	var total: int = 0
	for settlement: SettlementData in context.settlement_manager.get_all_settlements():
		if settlement != null:
			total += settlement.adventurer_candidates.size()
	return total


func _candidate_ids(settlement: SettlementData) -> Array[String]:
	var ids: Array[String] = []
	for candidate: AdventurerCandidateData in settlement.adventurer_candidates:
		ids.append(candidate.candidate_id if candidate != null else "")
	return ids


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[s13cand] OK: %s" % message)
	else:
		_failed = true
		push_error("[s13cand] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_context):
		_context.queue_free()
