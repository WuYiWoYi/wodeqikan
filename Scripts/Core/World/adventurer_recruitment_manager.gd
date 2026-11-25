class_name AdventurerRecruitmentManager
extends RefCounted
## 普通/贵族冒险者候选人的刷新，以及玩家与 NPC 的统一招募入口。
##
## 普通招募不是封地义务：任何村庄的候选人都可以被玩家支付金币招募，
## 不要求玩家拥有该村庄。候选人数据保存在 SettlementData 中；刷新由
## WorldSimulation 的世界 tick 驱动，不依赖村庄场景是否打开。

const NAME_POOL: Array[String] = [
	"阿拉丁", "贝恩", "卡尔", "德里克", "伊万",
	"法尔科", "戈登", "哈罗德", "伊萨克", "贾马尔",
]

## 候选人在村庄小场景中的生成位置；必须位于可活动区域内且避开建筑。
const CANDIDATE_POSITIONS: Array[Vector2] = [
	Vector2(700.0, 620.0),
	Vector2(1080.0, 700.0),
	Vector2(1450.0, 690.0),
	Vector2(820.0, 730.0),
	Vector2(1620.0, 700.0),
]

## 贵族冒险者的独立位置；与普通候选位置错开，马匹显示在人物左侧。
const NOBLE_CANDIDATE_POSITION: Vector2 = Vector2(1000.0, 600.0)
## 村庄场景中自备战马相对贵族冒险者的位置偏移（仅表现，不修改骑乘数据）。
const NOBLE_MOUNT_VISUAL_OFFSET: Vector2 = Vector2(-110.0, 4.0)

const RECRUIT_SOURCE: String = "adventurer_recruitment"

var player_party_id: String = ""
var last_error: String = ""

var _unit_manager: UnitManager = null
var _party_manager: PartyManager = null
var _settlement_manager: SettlementManager = null
var _family_registry: FamilyRegistry = null
var _economy_config: SettlementEconomyConfig = null
var _appearance_config: AppearanceConfig = null
var _id_generator: IdGenerator = null
## 封地所有权判断的唯一复用入口；贵族冒险者权限不另写一套规则。
var _fief_recruitment_manager: FiefRecruitmentManager = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func setup(
	unit_manager: UnitManager,
	party_manager: PartyManager,
	settlement_manager: SettlementManager,
	id_generator: IdGenerator,
	family_registry: FamilyRegistry = null,
	economy_config: SettlementEconomyConfig = null,
	fief_recruitment_manager: FiefRecruitmentManager = null
) -> void:
	_unit_manager = unit_manager
	_party_manager = party_manager
	_settlement_manager = settlement_manager
	_id_generator = id_generator
	_family_registry = family_registry
	_economy_config = economy_config if economy_config != null \
		else SettlementEconomyConfig.new()
	_economy_config.sanitize()
	_fief_recruitment_manager = fief_recruitment_manager
	_rng.randomize()


func set_appearance_config(config: AppearanceConfig) -> void:
	_appearance_config = config


func get_economy_config() -> SettlementEconomyConfig:
	return _economy_config


## 新游戏/读档后补齐单个村庄的候选人与刷新计时。
## 读档时 fill_initial=false：不新增候选人，但会为旧存档候选人补齐
## 独立 Unit 身份（幂等，不会重复创建）。
func initialize_settlement(settlement: SettlementData, fill_initial: bool = true) -> void:
	if settlement == null:
		return
	settlement.adventurer_refresh_elapsed = maxf(
		0.0, settlement.adventurer_refresh_elapsed
	)
	# 先补齐已有候选人的身份，再决定是否补足初始人数；
	# 补足循环只按数量判断，不会为同一候选人重复生成身份。
	ensure_candidate_identities(settlement)
	# 贵族冒险者每村最多 1 名；已在生成时记录 spawned，读档不会重复生成。
	ensure_noble_candidate(settlement)
	if not fill_initial:
		return
	var target_count: int = mini(
		_economy_config.adventurer_initial_count,
		_economy_config.adventurer_max_candidates
	)
	while _normal_candidate_count(settlement) < target_count:
		if not _spawn_candidate(settlement):
			break


## 为缺少独立 Unit 身份的候选人补齐快照；已存在则原样保留。
## 返回本次实际创建的身份数量。普通候选人与贵族冒险者共用同一快照规则。
func ensure_candidate_identities(settlement: SettlementData) -> int:
	if settlement == null or _unit_manager == null:
		return 0
	var created: int = 0
	for candidate: AdventurerCandidateData in settlement.adventurer_candidates:
		created += _ensure_candidate_identity(settlement, candidate)
	created += _ensure_candidate_identity(
		settlement, settlement.noble_adventurer_candidate
	)
	return created


## 补齐单个候选人的 Unit 快照；已存在则只修正索引。
func _ensure_candidate_identity(
	settlement: SettlementData, candidate: AdventurerCandidateData
) -> int:
	if candidate == null \
			or candidate.status != AdventurerCandidateData.Status.AVAILABLE:
		return 0
	# 已注册到仓储（理论上只在异常存档中出现）：沿用真实单位，不新建。
	if not candidate.unit_id.is_empty() \
			and _unit_manager.has_unit(candidate.unit_id):
		return 0
	# 候选人快照已存在：保证索引与快照一致即可。
	if not candidate.unit_data.is_empty():
		var snapshot_id: String = str(candidate.unit_data.get("unit_id", ""))
		if candidate.unit_id.is_empty():
			candidate.unit_id = snapshot_id
		return 0

	var config_id: String = candidate.unit_config_id
	if config_id.is_empty():
		config_id = _default_config_id(candidate)
	var config := _unit_manager.get_unit_config(config_id)
	if config == null:
		push_error("冒险者兵种配置不存在: %s" % config_id)
		return 0
	var unit: UnitData = _unit_manager.create_detached_unit(
		config, "", candidate.display_name
	)
	if unit == null:
		return 0
	candidate.unit_id = unit.unit_id
	if candidate.is_noble:
		_apply_noble_mount(unit, candidate)
	var family: FamilyConfig = null
	if _family_registry != null and not settlement.family_id.is_empty():
		family = _family_registry.get_config(settlement.family_id)
	if candidate.appearance.is_empty():
		UnitAppearance.ensure_random(
			unit, config, family, _appearance_config, false, _rng
		)
		candidate.appearance = unit.appearance.duplicate(true)
	else:
		unit.appearance = candidate.appearance.duplicate(true)
		unit.family_id = str(candidate.appearance.get("family_id", ""))
	candidate.unit_data = unit.to_dict()
	return 1


## 为村庄生成一名贵族冒险者。需要村庄真实拥有者；没有拥有者时不标记已生成，
## 以便村庄之后获得归属时再补。生成后不会重复生成，招募后也不会读档复活。
func ensure_noble_candidate(settlement: SettlementData) -> bool:
	if settlement == null \
			or settlement.settlement_type != SettlementData.SettlementType.VILLAGE:
		return false
	if settlement.noble_adventurer_spawned:
		return false
	if not settlement.has_owner():
		return false
	if settlement.noble_adventurer_candidate != null:
		settlement.noble_adventurer_spawned = true
		return false
	var candidate := _build_noble_candidate(settlement)
	if candidate == null:
		return false
	settlement.noble_adventurer_candidate = candidate
	settlement.noble_adventurer_spawned = true
	return true


func _build_noble_candidate(
	settlement: SettlementData
) -> AdventurerCandidateData:
	if _id_generator == null or _unit_manager == null:
		push_error("AdventurerRecruitmentManager 尚未初始化")
		return null
	var config_id: String = _economy_config.noble_adventurer_unit_config_id
	var config := _unit_manager.get_unit_config(config_id)
	if config == null:
		push_error("贵族冒险者兵种配置不存在: %s" % config_id)
		return null

	var candidate := AdventurerCandidateData.new()
	candidate.candidate_id = _id_generator.next_id(IdGenerator.CANDIDATE)
	candidate.display_name = _pick_name(settlement)
	candidate.settlement_id = settlement.settlement_id
	candidate.unit_config_id = config_id
	candidate.is_noble = true
	candidate.world_position = NOBLE_CANDIDATE_POSITION
	candidate.status = AdventurerCandidateData.Status.AVAILABLE

	var unit: UnitData = _unit_manager.create_detached_unit(
		config, "", candidate.display_name
	)
	if unit == null:
		push_error("无法为贵族冒险者创建独立单位身份")
		return null
	candidate.unit_id = unit.unit_id
	_apply_noble_mount(unit, candidate)
	var family: FamilyConfig = null
	if _family_registry != null and not settlement.family_id.is_empty():
		family = _family_registry.get_config(settlement.family_id)
	UnitAppearance.ensure_random(
		unit, config, family, _appearance_config, false, _rng
	)
	candidate.appearance = unit.appearance.duplicate(true)
	unit.family_id = str(candidate.appearance.get("family_id", ""))
	candidate.unit_data = unit.to_dict()
	return candidate


## 给候选人的独立单位装备真实马匹实例；实例 ID 与外观随候选人存档。
func _apply_noble_mount(unit: UnitData, candidate: AdventurerCandidateData) -> void:
	if unit == null or candidate == null:
		return
	var mount: MountInstanceData = candidate.get_mount_instance_data()
	var equipment_id: String = _economy_config.fief_mount_equipment_id
	if mount == null:
		mount = MountInstanceData.create_random(equipment_id)
		mount.display_name = "自备战马"
	candidate.mount_instance = mount.to_dict()
	_unit_manager.equip_detached_mount(unit, mount.equipment_id, mount)


func _normal_candidate_count(settlement: SettlementData) -> int:
	if settlement == null:
		return 0
	return settlement.adventurer_candidates.size()


func _default_config_id(candidate: AdventurerCandidateData) -> String:
	if candidate != null and candidate.is_noble:
		return _economy_config.noble_adventurer_unit_config_id
	return _economy_config.adventurer_unit_config_id


## 只由 WorldSimulation 的世界 tick 调用。
func tick(world_delta: float) -> void:
	if _settlement_manager == null or world_delta <= 0.0:
		return
	for settlement: SettlementData in _settlement_manager.get_all_settlements():
		if settlement == null \
				or settlement.settlement_type != SettlementData.SettlementType.VILLAGE:
			continue
		# 村庄获得拥有者后补上贵族冒险者；已生成/已招募的村庄不会重复生成。
		ensure_noble_candidate(settlement)
		if _normal_candidate_count(settlement) >= _economy_config.adventurer_max_candidates:
			settlement.adventurer_refresh_elapsed = 0.0
			continue
		settlement.adventurer_refresh_elapsed += world_delta
		var guard: int = 0
		while settlement.adventurer_refresh_elapsed >= _economy_config.adventurer_refresh_interval \
				and _normal_candidate_count(settlement) < _economy_config.adventurer_max_candidates \
				and guard < 16:
			settlement.adventurer_refresh_elapsed -= _economy_config.adventurer_refresh_interval
			if not _spawn_candidate(settlement):
				break
			guard += 1
		if _normal_candidate_count(settlement) >= _economy_config.adventurer_max_candidates:
			settlement.adventurer_refresh_elapsed = 0.0


func get_candidate(
	settlement_id: String, candidate_id: String
) -> AdventurerCandidateData:
	var settlement := _get_settlement(settlement_id)
	if settlement == null:
		return null
	return settlement.get_candidate(candidate_id)


## 贵族冒险者是否允许由指定贵族招募。直接复用封地所有权授权规则：
## 明确 owner_noble_id 时只认该贵族；未指定时认所有者家族领袖。
func is_noble_recruit_authorized(
	settlement: SettlementData, recruiter_lord_id: String
) -> bool:
	if settlement == null or recruiter_lord_id.strip_edges().is_empty():
		return false
	if _fief_recruitment_manager != null:
		return _fief_recruitment_manager.is_authorized_owner(
			settlement, recruiter_lord_id
		)
	# 未装配封地管理器时只接受明确个人所有者，避免放宽权限。
	return settlement.owner_noble_id == recruiter_lord_id


## 玩家支付固定金币招募一名候选人。任何失败都不扣金币、不创建单位。
## 贵族冒险者额外要求 recruiter_lord_id 是村庄真实拥有者。
func recruit_candidate(
	settlement_id: String,
	candidate_id: String,
	profile: PlayerProfile,
	recruiter_lord_id: String = ""
) -> bool:
	var settlement := _get_settlement(settlement_id)
	if settlement == null:
		last_error = "村庄不存在。"
		return false
	var candidate := settlement.get_candidate(candidate_id)
	if candidate == null:
		last_error = "候选人不存在。"
		return false
	if not candidate.is_available():
		last_error = "该候选人已经加入队伍。"
		return false
	if profile == null:
		last_error = "玩家档案无效。"
		return false
	if candidate.is_noble \
			and not is_noble_recruit_authorized(settlement, recruiter_lord_id):
		last_error = "只有村庄拥有者可以招募贵族冒险者。"
		return false
	var cost: int = _economy_config.adventurer_recruit_cost
	if not profile.can_afford(cost):
		last_error = "金币不足，招募需要 %d 金币。" % cost
		return false
	var party := _party_manager.get_party(player_party_id) \
		if _party_manager != null and not player_party_id.is_empty() else null
	if party == null:
		last_error = "玩家部队不可用。"
		return false
	if not party.is_available_for_world():
		last_error = "玩家部队当前无法接受新成员。"
		return false

	var unit := _recruit_candidate_into_party(
		settlement, candidate, party, profile, true
	)
	if unit == null:
		return false

	EventBus.adventurers_recruited.emit(
		party.party_id,
		settlement.settlement_id,
		{unit.config_id: 1},
		1,
		true
	)
	return true


## NPC 领主在自己拥有的村庄一次性招募全部可用的普通冒险者。
## 贵族冒险者不在此接口内；士兵与金币都走与玩家完全相同的真实数据路径。
## 返回 { success, total, counts: { config_id: 数量 } }。
func recruit_normal_candidates_for_party(
	settlement_id: String,
	party_id: String,
	recruiter_lord_id: String
) -> Dictionary:
	var result := {"success": false, "total": 0, "counts": {}}
	var settlement := _get_settlement(settlement_id)
	if settlement == null:
		last_error = "村庄不存在。"
		return result
	if _party_manager == null:
		last_error = "部队管理器不可用。"
		return result
	var party := _party_manager.get_party(party_id)
	if party == null:
		last_error = "招募者部队不存在。"
		return result
	if not party.is_available_for_world():
		last_error = "部队当前无法接受新成员。"
		return result
	if not is_noble_recruit_authorized(settlement, recruiter_lord_id):
		last_error = "只有村庄拥有者可以招募冒险者。"
		return result

	var counts: Dictionary = {}
	var candidates: Array[AdventurerCandidateData] = settlement.get_available_candidates()
	for candidate: AdventurerCandidateData in candidates:
		if candidate == null or candidate.is_noble:
			continue
		if not party.can_afford(_economy_config.adventurer_recruit_cost):
			break
		var unit := _recruit_candidate_into_party(
			settlement, candidate, party, party, false
		)
		if unit == null:
			continue
		counts[unit.config_id] = int(counts.get(unit.config_id, 0)) + 1
		result["total"] = int(result["total"]) + 1
		# NPC 不在村庄场景中停留，招募完成后立即移除候选人记录，避免重复招募。
		settlement.adventurer_candidates.erase(candidate)

	result["counts"] = counts
	result["success"] = int(result["total"]) > 0
	if bool(result["success"]):
		last_error = ""
		EventBus.adventurers_recruited.emit(
			party.party_id,
			settlement.settlement_id,
			counts.duplicate(true),
			int(result["total"]),
			false
		)
	return result


## 玩家与 NPC 共用的候选人→真实单位流程。payer 需支持 can_afford/spend_gold。
## keep_pending=true 时保留“已招募待离开”记录供村庄 UI 标记；NPC 立即移除。
func _recruit_candidate_into_party(
	settlement: SettlementData,
	candidate: AdventurerCandidateData,
	party: PartyData,
	payer: Variant,
	emit_log_event: bool
) -> UnitData:
	if settlement == null or candidate == null or party == null or payer == null:
		return null
	if not candidate.is_available():
		last_error = "该候选人已经加入队伍。"
		return null
	if not party.is_available_for_world():
		last_error = "部队当前无法接受新成员。"
		return null
	var cost: int = _economy_config.adventurer_recruit_cost
	if not bool(payer.can_afford(cost)):
		last_error = "金币不足，招募需要 %d 金币。" % cost
		return null

	var config_id: String = candidate.unit_config_id
	if config_id.is_empty():
		config_id = _default_config_id(candidate)
	var config := _unit_manager.get_unit_config(config_id)
	if config == null:
		last_error = "冒险者兵种配置不存在: %s" % config_id
		return null

	# 优先使用候选人已有的独立 Unit 身份；旧存档缺失身份时才新建。
	# 两条路径都最终把真实单位注册到 UnitManager 并加入目标部队。
	var unit := _materialize_candidate_unit(candidate, party, config, settlement)
	if unit == null:
		last_error = "无法创建冒险者单位。"
		return null

	if not _party_manager.add_member(party.party_id, unit.unit_id):
		_unit_manager.remove_unit(unit.unit_id)
		last_error = "冒险者无法加入部队。"
		return null
	if not bool(payer.spend_gold(cost)):
		_party_manager.remove_member(party.party_id, unit.unit_id)
		_unit_manager.remove_unit(unit.unit_id)
		last_error = "金币不足，招募失败。"
		return null

	unit.joined_at_game_time = TimeManager.world_elapsed_seconds
	unit.recruit_source = RECRUIT_SOURCE
	unit.recruit_settlement_id = settlement.settlement_id
	unit.origin_faction_id = party.faction_id

	candidate.status = AdventurerCandidateData.Status.RECRUITED_PENDING_DEPARTURE
	candidate.unit_id = unit.unit_id
	# 单位已由 UnitManager 持有，清空候选人快照，避免存档中出现重复身份。
	candidate.unit_data = {}
	last_error = ""
	if emit_log_event:
		EventBus.adventurer_recruited.emit(
			settlement.settlement_id, unit.unit_id, unit.display_name
		)
	return unit


## 玩家离开村庄时移除本次已招募的候选人记录；已加入部队的 UnitData 不受影响。
## 重复调用是幂等的。贵族冒险者被招募后同样移除，且不会再次生成。
func cleanup_departed_candidates(settlement_id: String) -> int:
	var settlement := _get_settlement(settlement_id)
	if settlement == null:
		return 0
	var removed: int = 0
	var remaining: Array[AdventurerCandidateData] = []
	for candidate: AdventurerCandidateData in settlement.adventurer_candidates:
		if candidate == null:
			continue
		if candidate.status == AdventurerCandidateData.Status.RECRUITED_PENDING_DEPARTURE:
			removed += 1
			continue
		remaining.append(candidate)
	settlement.adventurer_candidates = remaining
	if settlement.noble_adventurer_candidate != null \
			and settlement.noble_adventurer_candidate.status \
				== AdventurerCandidateData.Status.RECRUITED_PENDING_DEPARTURE:
		settlement.noble_adventurer_candidate = null
		removed += 1
	return removed


## 把候选人身份变成 UnitManager 仓储中的真实单位。
## 有快照时复用快照（保持同一 unit_id），否则按旧存档路径新建。
func _materialize_candidate_unit(
	candidate: AdventurerCandidateData,
	party: PartyData,
	config: UnitConfig,
	settlement: SettlementData
) -> UnitData:
	if not candidate.unit_data.is_empty():
		var restored := UnitData.from_dict(candidate.unit_data)
		if restored == null or restored.unit_id.is_empty():
			return null
		# 索引是权威 ID：快照 ID 异常时以候选人的 unit_id 为准，
		# 避免同一候选人在存档中产生两个身份。
		if not candidate.unit_id.is_empty():
			restored.unit_id = candidate.unit_id
		if _unit_manager.has_unit(restored.unit_id):
			push_error("候选人单位 ID 已在仓储中: %s" % restored.unit_id)
			return null
		restored.faction_id = party.faction_id
		restored.current_party_id = ""
		restored.display_name = candidate.display_name
		if not candidate.appearance.is_empty():
			restored.appearance = candidate.appearance.duplicate(true)
			restored.family_id = str(candidate.appearance.get("family_id", ""))
		# 先补齐快照缺失的战马关系，再注册进仓储，避免绕过 UnitManager 写装备。
		_apply_candidate_mount_to_unit(restored, candidate)
		if _unit_manager.add_unit(restored).is_empty():
			return null
		# 招募时按当前配置/装备重算一次，确保属性与统一计算入口一致。
		_unit_manager.recalculate_stats(restored.unit_id)
		return restored

	# 旧档路径同样先构造未注册单位，补齐外观/坐骑后再由 UnitManager 注册。
	var created := _unit_manager.create_detached_unit(
		config, party.faction_id, candidate.display_name
	)
	if created == null:
		return null
	_apply_candidate_appearance(created, candidate, config, settlement)
	_apply_candidate_mount_to_unit(created, candidate)
	if _unit_manager.add_unit(created).is_empty():
		return null
	_unit_manager.recalculate_stats(created.unit_id)
	return created


## 旧存档/缺失快照路径：为贵族冒险者补回真实坐骑，再统一重算属性。
## 已有 MOUNT 的快照以快照为准，避免重复生成马匹或覆盖外观。
func _apply_candidate_mount_to_unit(
	unit: UnitData, candidate: AdventurerCandidateData
) -> void:
	if unit == null or candidate == null or not candidate.is_noble:
		return
	var slot_key: String = EquipmentConfig.SLOT_NAMES[EquipmentConfig.Slot.MOUNT]
	if unit.equipment.has(slot_key):
		return
	var mount: MountInstanceData = candidate.get_mount_instance_data()
	if mount == null:
		var equipment_id: String = _economy_config.fief_mount_equipment_id
		mount = MountInstanceData.create_random(equipment_id)
		mount.display_name = "自备战马"
		candidate.mount_instance = mount.to_dict()
	unit.equipment[slot_key] = mount.equipment_id
	unit.set_mount_instance_data(mount)
	unit.is_mounted = true


func _apply_candidate_appearance(
	unit: UnitData,
	candidate: AdventurerCandidateData,
	config: UnitConfig,
	settlement: SettlementData
) -> void:
	if not candidate.appearance.is_empty():
		unit.appearance = candidate.appearance.duplicate(true)
		unit.family_id = str(candidate.appearance.get("family_id", ""))
		return
	var family: FamilyConfig = null
	if _family_registry != null and not settlement.family_id.is_empty():
		family = _family_registry.get_config(settlement.family_id)
	UnitAppearance.ensure_random(
		unit, config, family, _appearance_config, false, _rng
	)
	candidate.appearance = unit.appearance.duplicate(true)


func _spawn_candidate(settlement: SettlementData) -> bool:
	if _id_generator == null:
		push_error("AdventurerRecruitmentManager 尚未初始化 IdGenerator")
		return false
	if settlement.adventurer_candidates.size() >= _economy_config.adventurer_max_candidates:
		return false
	var config_id: String = _economy_config.adventurer_unit_config_id
	var config := _unit_manager.get_unit_config(config_id) if _unit_manager != null else null
	if config == null:
		push_error("冒险者兵种配置不存在: %s" % config_id)
		return false

	var candidate := AdventurerCandidateData.new()
	candidate.candidate_id = _id_generator.next_id(IdGenerator.CANDIDATE)
	candidate.display_name = _pick_name(settlement)
	candidate.settlement_id = settlement.settlement_id
	candidate.unit_config_id = config_id
	candidate.world_position = _pick_position(settlement)
	candidate.status = AdventurerCandidateData.Status.AVAILABLE

	# 候选人拥有独立 Unit 身份，但暂不进入仓储/部队；快照随村庄存档。
	var candidate_unit: UnitData = _unit_manager.create_detached_unit(
		config, "", candidate.display_name
	)
	if candidate_unit == null:
		push_error("无法为村庄候选人创建独立单位身份")
		return false
	candidate.unit_id = candidate_unit.unit_id

	var family: FamilyConfig = null
	if _family_registry != null and not settlement.family_id.is_empty():
		family = _family_registry.get_config(settlement.family_id)
	UnitAppearance.ensure_random(
		candidate_unit, config, family, _appearance_config, false, _rng
	)
	candidate.appearance = candidate_unit.appearance.duplicate(true)
	candidate_unit.family_id = str(candidate.appearance.get("family_id", ""))
	candidate.unit_data = candidate_unit.to_dict()

	settlement.adventurer_candidates.append(candidate)
	return true


func _pick_name(settlement: SettlementData) -> String:
	var used: Dictionary = {}
	for candidate: AdventurerCandidateData in settlement.adventurer_candidates:
		if candidate != null:
			used[candidate.display_name] = true
	var base_name: String = NAME_POOL[_rng.randi_range(0, NAME_POOL.size() - 1)]
	if not used.has(base_name):
		return base_name
	var suffix: int = 2
	while used.has("%s %d" % [base_name, suffix]):
		suffix += 1
	return "%s %d" % [base_name, suffix]


func _pick_position(settlement: SettlementData) -> Vector2:
	var used: Dictionary = {}
	for candidate: AdventurerCandidateData in settlement.adventurer_candidates:
		if candidate != null:
			used[candidate.world_position] = true
	for position: Vector2 in CANDIDATE_POSITIONS:
		if not used.has(position):
			return position
	# 候选人数达到上限前不会到这里；仍返回一个安全位置避免生成失败。
	return CANDIDATE_POSITIONS[settlement.adventurer_candidates.size() % CANDIDATE_POSITIONS.size()]


func _get_settlement(settlement_id: String) -> SettlementData:
	if _settlement_manager == null:
		return null
	return _settlement_manager.get_settlement(settlement_id)
