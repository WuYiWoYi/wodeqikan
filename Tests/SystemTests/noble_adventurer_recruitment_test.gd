extends Node
## 贵族冒险者与 NPC 普通冒险者招募系统测试。
## 覆盖：贵族候选人生成、真实三级单位与马匹实例、所有权权限、
## 招募后不可重复、存档往返、村庄步行人物+独立战马表现、
## NPC 领主在自有村庄招募普通冒险者与事件。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/noble_adventurer_recruitment_test.tscn

var _failed: bool = false
var _context: WorldContext = null
var _village_scene: VillageScene = null


func _ready() -> void:
	await _run()
	if _failed:
		push_error("[noble] 测试失败")
		get_tree().quit(1)
	else:
		print("[noble] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	TimeManager.world_elapsed_seconds = 0.0

	_context = WorldContext.new()
	_context.name = "NobleAdventurerTestContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return

	_test_noble_candidate_data()
	await _test_village_noble_visual()
	_test_owner_permission_and_recruitment()
	_test_noble_not_respawned_after_recruit()
	_test_ai_normal_adventurer_recruitment()

	_context.queue_free()


func _test_noble_candidate_data() -> void:
	var village := _find_settlement(WorldInitializer.PLAYER_VILLAGE_NAME)
	_check(village != null, "找到玩家村庄")
	if village == null:
		return
	var noble: AdventurerCandidateData = village.get_noble_adventurer_candidate()
	_check(noble != null and noble.is_noble, "村庄生成贵族冒险者候选人")
	_check(village.noble_adventurer_spawned, "贵族冒险者生成状态持久化")
	_check(village.adventurer_candidates.size() == 2, "贵族不占用普通候选人上限")
	if noble == null:
		return
	_check(noble.is_available(), "贵族候选人初始可招募")
	var config := _context.unit_manager.get_unit_config(noble.unit_config_id)
	_check(config != null and config.tier == 3, "贵族候选人是三级士兵")
	var mount: MountInstanceData = noble.get_mount_instance_data()
	_check(mount != null and not mount.instance_id.is_empty(), "贵族自带真实马匹实例")
	_check(
		noble.unit_data.get("is_mounted", false),
		"贵族单位快照保留真实骑乘关系"
	)
	_check(
		str(noble.unit_data.get("mount_instance", {}).get("instance_id", ""))
			== (mount.instance_id if mount != null else ""),
		"单位骑乘的马与候选人马匹实例一致"
	)
	_check(
		not noble.unit_id.is_empty()
		and _context.unit_manager.get_unit(noble.unit_id) == null,
		"贵族在村庄中拥有独立单位身份但尚未进入部队"
	)

	# 正常候选人仍然存在且不是贵族。
	var has_normal: bool = false
	for candidate: AdventurerCandidateData in village.adventurer_candidates:
		if candidate != null and not candidate.is_noble:
			has_normal = true
	_check(has_normal, "普通冒险者生成规则不受影响")

	# 存档往返：贵族身份、三级兵种、马匹与生成状态都保留。
	var save := _context.to_save_data()
	var restored := WorldContext.new()
	restored.name = "NobleRestoredContext"
	add_child(restored)
	_check(restored.load_from_save_data(save), "贵族候选人存档可恢复")
	var restored_village := _find_settlement_in(
		restored, WorldInitializer.PLAYER_VILLAGE_NAME
	)
	if restored_village != null:
		var restored_noble: AdventurerCandidateData = \
			restored_village.get_noble_adventurer_candidate()
		_check(restored_noble != null, "恢复后贵族候选人仍存在")
		if restored_noble != null:
			_check(
				restored_noble.unit_id == noble.unit_id,
				"恢复后贵族单位 ID 稳定"
			)
			_check(restored_noble.is_noble, "恢复后贵族类型保留")
			_check(
				restored_noble.unit_config_id == noble.unit_config_id,
				"恢复后三级兵种配置保留"
			)
			var restored_mount: MountInstanceData = \
				restored_noble.get_mount_instance_data()
			_check(
				restored_mount != null
				and mount != null
				and restored_mount.instance_id == mount.instance_id,
				"恢复后贵族战马实例不重复生成"
			)
		_check(
			restored_village.noble_adventurer_spawned,
			"恢复后生成状态不重置"
		)
	restored.queue_free()


func _test_village_noble_visual() -> void:
	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id
	var village := _find_settlement(WorldInitializer.PLAYER_VILLAGE_NAME)
	if village == null:
		return
	GameManager.current_settlement_id = village.settlement_id
	var packed := load("res://Scenes/Village/village.tscn") as PackedScene
	_village_scene = packed.instantiate() as VillageScene
	add_child(_village_scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var noble: AdventurerCandidateData = village.get_noble_adventurer_candidate()
	_check(_village_scene.get_noble_candidate_visual() != null,
		"村庄显示贵族冒险者人物")
	_check(_village_scene.get_noble_mount_visual() != null,
		"村庄显示贵族自备战马独立对象")
	_check(
		_village_scene.get_candidate_count() == village.adventurer_candidates.size(),
		"贵族表现不改变普通候选人数量接口"
	)
	var noble_position: Vector2 = _village_scene.get_noble_candidate_position()
	var mount_position: Vector2 = _village_scene.get_noble_mount_visual().position
	_check(
		noble_position.distance_to(mount_position) > 40.0,
		"贵族人物与战马位置互不重叠"
	)
	var visual := _village_scene.get_noble_candidate_visual()
	_check(
		visual.unit_data != null and not visual.unit_data.is_mounted,
		"村庄人物按步行表现"
	)
	_check(
		noble != null and noble.unit_data.get("is_mounted", false),
		"村庄表现不修改权威骑乘数据"
	)

	# 非拥有者只能查看，不能招募。
	var bari_lord := _find_lord_of_family(WorldInitializer.FAMILY_BARI_ID)
	if bari_lord != null and noble != null:
		var members_before: int = _context.get_player_party().member_unit_ids.size()
		var rejected: bool = _context.adventurer_recruitment_manager.recruit_candidate(
			village.settlement_id,
			noble.candidate_id,
			_context.player_profile,
			bari_lord.lord_id
		)
		_check(not rejected, "非村庄拥有者不能招募贵族冒险者")
		_check(
			_context.get_player_party().member_unit_ids.size() == members_before,
			"拒绝招募不产生单位"
		)
		_check(
			_context.adventurer_recruitment_manager.last_error.contains("拥有者"),
			"拒绝招募返回权限提示"
		)

	_village_scene.queue_free()
	_village_scene = null
	await get_tree().process_frame


func _test_owner_permission_and_recruitment() -> void:
	var village := _find_settlement(WorldInitializer.PLAYER_VILLAGE_NAME)
	var player_lord := _context.get_player_lord()
	var noble: AdventurerCandidateData = \
		village.get_noble_adventurer_candidate() if village != null else null
	if village == null or player_lord == null or noble == null:
		return
	# 所有权变更后权限立即变化：玩家不再是所有者时授权失败。
	var bari_lord := _find_lord_of_family(WorldInitializer.FAMILY_BARI_ID)
	var original_owner_id: String = village.owner_noble_id
	if bari_lord != null:
		village.owner_noble_id = bari_lord.lord_id
		_check(
			not _context.adventurer_recruitment_manager.is_noble_recruit_authorized(
				village, player_lord.lord_id
			),
			"村庄归属变更后原所有者立即失去贵族招募权限"
		)
		_check(
			_context.adventurer_recruitment_manager.is_noble_recruit_authorized(
				village, bari_lord.lord_id
			),
			"村庄新所有者立即获得贵族招募权限"
		)
		village.owner_noble_id = original_owner_id

	_context.player_profile.gold = 10
	var party := _context.get_player_party()
	var members_before: int = party.member_unit_ids.size()

	var recruited: bool = _context.adventurer_recruitment_manager.recruit_candidate(
		village.settlement_id,
		noble.candidate_id,
		_context.player_profile,
		player_lord.lord_id
	)
	_check(recruited, "村庄拥有者可以招募贵族冒险者")
	_check(
		party.member_unit_ids.size() == members_before + 1,
		"贵族与战马一次招募只新增 1 名士兵"
	)
	var unit := _context.unit_manager.get_unit(noble.unit_id)
	_check(unit != null, "贵族招募后成为真实单位")
	if unit != null:
		var config := _context.unit_manager.get_unit_config(unit.config_id)
		_check(config != null and config.tier == 3, "招募后的贵族仍是三级士兵")
		_check(unit.is_mounted, "招募后的贵族保持骑乘")
		var mount := unit.get_mount_instance_data()
		_check(
			mount != null and not mount.instance_id.is_empty(),
			"招募后的单位携带真实马匹实例"
		)
		_check(
			unit.current_party_id == party.party_id,
			"贵族单位加入玩家部队"
		)
	_check(
		noble.status == AdventurerCandidateData.Status.RECRUITED_PENDING_DEPARTURE,
		"贵族候选人标记为已招募待离开"
	)
	var rejected_again: bool = _context.adventurer_recruitment_manager.recruit_candidate(
		village.settlement_id,
		noble.candidate_id,
		_context.player_profile,
		player_lord.lord_id
	)
	_check(not rejected_again, "同一贵族不能重复招募")
	_check(
		party.member_unit_ids.size() == members_before + 1,
		"重复招募不产生额外单位"
	)

	var removed: int = _context.adventurer_recruitment_manager \
		.cleanup_departed_candidates(village.settlement_id)
	_check(removed == 1, "离开村庄后清理已招募贵族记录")
	_check(
		village.get_noble_adventurer_candidate() == null,
		"贵族候选人记录已移除"
	)
	_check(
		_context.unit_manager.get_unit(noble.unit_id) != null,
		"已招募贵族单位不受清理影响"
	)


func _test_noble_not_respawned_after_recruit() -> void:
	var village := _find_settlement(WorldInitializer.PLAYER_VILLAGE_NAME)
	if village == null:
		return
	_check(village.noble_adventurer_spawned, "招募后仍记录已生成")
	_context.adventurer_recruitment_manager.tick(10000.0)
	_context.adventurer_recruitment_manager.ensure_noble_candidate(village)
	_check(
		village.get_noble_adventurer_candidate() == null,
		"已招募贵族不会重新生成"
	)

	var save := _context.to_save_data()
	var restored := WorldContext.new()
	restored.name = "NobleRecruitedRestoredContext"
	add_child(restored)
	_check(restored.load_from_save_data(save), "已招募贵族存档可恢复")
	var restored_village := _find_settlement_in(
		restored, WorldInitializer.PLAYER_VILLAGE_NAME
	)
	if restored_village != null:
		_check(
			restored_village.get_noble_adventurer_candidate() == null,
			"读档后已招募贵族不会复活"
		)
		_check(
			restored_village.noble_adventurer_spawned,
			"读档后仍标记该村贵族已生成"
		)
	restored.queue_free()


func _test_ai_normal_adventurer_recruitment() -> void:
	var bari := _find_settlement(WorldInitializer.BARI_VILLAGE_NAME)
	var lord := _find_lord_of_family(WorldInitializer.FAMILY_BARI_ID)
	if bari == null or lord == null:
		return
	var party := _context.party_manager.get_party(lord.party_id)
	if party == null:
		_check(false, "NPC 领主存在真实部队")
		return
	# 清空采邑储备，迫使 AI 走普通冒险者招募分支。
	bari.fief_recruitment_stock = 0
	party.gold = 20
	var candidates_before: int = bari.get_available_candidates().size()
	if candidates_before == 0:
		_context.adventurer_recruitment_manager.initialize_settlement(bari, true)
		candidates_before = bari.get_available_candidates().size()
	_check(candidates_before > 0, "NPC 自有村庄存在普通冒险者候选人")
	var members_before: int = party.member_unit_ids.size()
	var events: Array[Dictionary] = []
	var on_recruited := func(
		event_party_id: String,
		settlement_id: String,
		counts: Dictionary,
		total: int,
		is_player: bool
	) -> void:
		events.append({
			"party_id": event_party_id,
			"settlement_id": settlement_id,
			"counts": counts,
			"total": total,
			"is_player": is_player,
		})
	EventBus.adventurers_recruited.connect(on_recruited)

	_context.ai_manager._tick_lord_strategic()
	_check(
		lord.current_goal == "ADVENTURER_RECRUIT"
		and lord.current_target_settlement_id == bari.settlement_id,
		"采邑为 0 时 AI 前往自有村庄招募普通冒险者"
	)
	party.world_position = bari.world_position
	party.target_position = bari.world_position
	party.movement_state = PartyData.MovementState.IDLE
	_context.ai_manager._tick_lord_strategic()

	_check(
		party.member_unit_ids.size() == members_before + candidates_before,
		"NPC 到达后招募全部可用普通冒险者"
	)
	_check(
		_count_normal_candidates(bari) == 0,
		"NPC 招募后移除普通候选人记录"
	)
	_check(lord.current_state == "IDLE", "NPC 招募结束后恢复普通 AI 状态")
	_check(not events.is_empty(), "NPC 招募成功发出统一事件")
	if not events.is_empty():
		var event := events[0]
		_check(not bool(event.get("is_player", true)), "事件标记 NPC 招募者")
		_check(
			int(event.get("total", 0)) == candidates_before,
			"事件数量来自实际招募人数"
		)
		_check(
			not (event.get("counts", {}) as Dictionary).is_empty(),
			"事件包含按兵种统计"
		)
	var bari_noble: AdventurerCandidateData = \
		bari.get_noble_adventurer_candidate()
	_check(
		bari_noble != null and bari_noble.is_available(),
		"NPC 不会招募贵族冒险者"
	)
	EventBus.adventurers_recruited.disconnect(on_recruited)


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


func _count_normal_candidates(settlement: SettlementData) -> int:
	var count: int = 0
	for candidate: AdventurerCandidateData in settlement.get_available_candidates():
		if candidate != null and not candidate.is_noble:
			count += 1
	return count


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[noble] OK: %s" % message)
	else:
		_failed = true
		push_error("[noble] FAIL: %s" % message)
