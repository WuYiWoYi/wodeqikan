class_name AdventurerRecruitmentManager
extends RefCounted
## 普通冒险者候选人的刷新与玩家招募入口。
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
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func setup(
	unit_manager: UnitManager,
	party_manager: PartyManager,
	settlement_manager: SettlementManager,
	id_generator: IdGenerator,
	family_registry: FamilyRegistry = null,
	economy_config: SettlementEconomyConfig = null
) -> void:
	_unit_manager = unit_manager
	_party_manager = party_manager
	_settlement_manager = settlement_manager
	_id_generator = id_generator
	_family_registry = family_registry
	_economy_config = economy_config if economy_config != null \
		else SettlementEconomyConfig.new()
	_economy_config.sanitize()
	_rng.randomize()


func set_appearance_config(config: AppearanceConfig) -> void:
	_appearance_config = config


func get_economy_config() -> SettlementEconomyConfig:
	return _economy_config


## 新游戏/读档后补齐单个村庄的候选人与刷新计时。
func initialize_settlement(settlement: SettlementData, fill_initial: bool = true) -> void:
	if settlement == null:
		return
	settlement.adventurer_refresh_elapsed = maxf(
		0.0, settlement.adventurer_refresh_elapsed
	)
	if not fill_initial:
		return
	var target_count: int = mini(
		_economy_config.adventurer_initial_count,
		_economy_config.adventurer_max_candidates
	)
	while settlement.adventurer_candidates.size() < target_count:
		if not _spawn_candidate(settlement):
			break


## 只由 WorldSimulation 的世界 tick 调用。
func tick(world_delta: float) -> void:
	if _settlement_manager == null or world_delta <= 0.0:
		return
	for settlement: SettlementData in _settlement_manager.get_all_settlements():
		if settlement == null \
				or settlement.settlement_type != SettlementData.SettlementType.VILLAGE:
			continue
		if settlement.adventurer_candidates.size() >= _economy_config.adventurer_max_candidates:
			settlement.adventurer_refresh_elapsed = 0.0
			continue
		settlement.adventurer_refresh_elapsed += world_delta
		var guard: int = 0
		while settlement.adventurer_refresh_elapsed >= _economy_config.adventurer_refresh_interval \
				and settlement.adventurer_candidates.size() < _economy_config.adventurer_max_candidates \
				and guard < 16:
			settlement.adventurer_refresh_elapsed -= _economy_config.adventurer_refresh_interval
			if not _spawn_candidate(settlement):
				break
			guard += 1
		if settlement.adventurer_candidates.size() >= _economy_config.adventurer_max_candidates:
			settlement.adventurer_refresh_elapsed = 0.0


func get_candidate(
	settlement_id: String, candidate_id: String
) -> AdventurerCandidateData:
	var settlement := _get_settlement(settlement_id)
	if settlement == null:
		return null
	return settlement.get_candidate(candidate_id)


## 玩家支付固定金币招募一名候选人。任何失败都不扣金币、不创建单位。
func recruit_candidate(
	settlement_id: String,
	candidate_id: String,
	profile: PlayerProfile
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

	var config_id: String = candidate.unit_config_id
	if config_id.is_empty():
		config_id = _economy_config.adventurer_unit_config_id
	var config := _unit_manager.get_unit_config(config_id)
	if config == null:
		last_error = "冒险者兵种配置不存在: %s" % config_id
		return false

	var unit := _unit_manager.create_unit(
		config, party.faction_id, candidate.display_name
	)
	if unit == null:
		last_error = "无法创建冒险者单位。"
		return false
	_apply_candidate_appearance(unit, candidate, config, settlement)

	if not _party_manager.add_member(party.party_id, unit.unit_id):
		_unit_manager.remove_unit(unit.unit_id)
		last_error = "冒险者无法加入玩家部队。"
		return false
	if not profile.spend_gold(cost):
		_party_manager.remove_member(party.party_id, unit.unit_id)
		_unit_manager.remove_unit(unit.unit_id)
		last_error = "金币不足，招募失败。"
		return false

	unit.joined_at_game_time = TimeManager.world_elapsed_seconds
	unit.recruit_source = RECRUIT_SOURCE
	unit.recruit_settlement_id = settlement.settlement_id
	unit.origin_faction_id = party.faction_id

	candidate.status = AdventurerCandidateData.Status.RECRUITED_PENDING_DEPARTURE
	candidate.unit_id = unit.unit_id
	last_error = ""
	EventBus.adventurer_recruited.emit(
		settlement.settlement_id, unit.unit_id, unit.display_name
	)
	return true


## 玩家离开村庄时移除本次已招募的候选人记录；已加入部队的 UnitData 不受影响。
## 重复调用是幂等的。
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
	return removed


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

	var appearance_unit := UnitData.new()
	appearance_unit.display_name = candidate.display_name
	appearance_unit.config_id = config_id
	var family: FamilyConfig = null
	if _family_registry != null and not settlement.family_id.is_empty():
		family = _family_registry.get_config(settlement.family_id)
	UnitAppearance.ensure_random(
		appearance_unit, config, family, _appearance_config, false, _rng
	)
	candidate.appearance = appearance_unit.appearance.duplicate(true)

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
