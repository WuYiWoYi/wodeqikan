class_name MercenaryManager
extends RefCounted
## 全地图可招募雇佣兵的唯一管理与招募入口。
##
## 职责：
## - 维护雇佣兵世界记录（待分配 / 酒馆驻留 / 城镇间流动）；
## - 按游戏世界时间增加总量并随机分配到城镇酒馆；
## - 玩家与 NPC 招募共用同一价格、金币与部队加入路径；
## - 玩家正在查看的酒馆不会被 NPC 抢购（玩家优先级更高）。
##
## 本类只写 MercenaryData 与真实 UnitData；不写场景节点，也不复制战斗逻辑。

const MAX_SPAWN_PER_TICK: int = 16
const MAX_FLOW_CHECKS_PER_TICK: int = 16

var last_error: String = ""

var _mercenaries: Dictionary = {}
var _initialized: bool = false
var _growth_elapsed: float = 0.0
var _flow_elapsed: float = 0.0
var _npc_recruit_elapsed: float = 0.0
## 玩家当前打开的酒馆城镇；NPC 不从这里招募，保证玩家优先。
var _player_viewing_tavern_id: String = ""

var _unit_manager: UnitManager = null
var _party_manager: PartyManager = null
var _settlement_manager: SettlementManager = null
var _noble_manager: NobleManager = null
var _family_registry: FamilyRegistry = null
var _appearance_config: AppearanceConfig = null
var _recruitment_config: RecruitmentConfig = null
var _id_generator: IdGenerator = null
var _player_party_id: String = ""
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func setup(
	unit_manager: UnitManager,
	party_manager: PartyManager,
	settlement_manager: SettlementManager,
	noble_manager: NobleManager,
	id_generator: IdGenerator,
	recruitment_config: RecruitmentConfig,
	family_registry: FamilyRegistry = null,
	appearance_config: AppearanceConfig = null
) -> void:
	_unit_manager = unit_manager
	_party_manager = party_manager
	_settlement_manager = settlement_manager
	_noble_manager = noble_manager
	_id_generator = id_generator
	_recruitment_config = recruitment_config if recruitment_config != null \
		else RecruitmentConfig.new()
	_recruitment_config.sanitize()
	_family_registry = family_registry
	_appearance_config = appearance_config
	_rng.randomize()


func set_appearance_config(config: AppearanceConfig) -> void:
	_appearance_config = config


func set_player_party_id(party_id: String) -> void:
	_player_party_id = party_id


func get_config() -> RecruitmentConfig:
	return _recruitment_config


# ---------------------------------------------------------------------------
# 查询
# ---------------------------------------------------------------------------


func is_initialized() -> bool:
	return _initialized


func get_all_mercenaries() -> Array[MercenaryData]:
	var result: Array[MercenaryData] = []
	var ids: Array = _mercenaries.keys()
	ids.sort()
	for id_value: Variant in ids:
		var mercenary := _mercenaries.get(id_value) as MercenaryData
		if mercenary != null:
			result.append(mercenary)
	return result


func get_mercenary(mercenary_id: String) -> MercenaryData:
	return _mercenaries.get(mercenary_id) as MercenaryData


## 全地图当前仍属于可招募池的总量（驻留 + 流动 + 待分配）。
func get_total_pool_count() -> int:
	return _mercenaries.size()


func get_waiting_count() -> int:
	var count: int = 0
	for mercenary: MercenaryData in _mercenaries.values():
		if mercenary != null and mercenary.is_waiting():
			count += 1
	return count


func get_traveling_count() -> int:
	var count: int = 0
	for mercenary: MercenaryData in _mercenaries.values():
		if mercenary != null and mercenary.is_traveling():
			count += 1
	return count


func get_stationed_mercenaries(settlement_id: String) -> Array[MercenaryData]:
	var result: Array[MercenaryData] = []
	if settlement_id.is_empty():
		return result
	for mercenary: MercenaryData in get_all_mercenaries():
		if mercenary.is_stationed() and mercenary.settlement_id == settlement_id:
			result.append(mercenary)
	return result


func get_stationed_count(settlement_id: String) -> int:
	return get_stationed_mercenaries(settlement_id).size()


## 城镇酒馆占用 = 已驻留 + 正在前往该城镇的雇佣兵。
## exclude 用于流动完成时排除自身，避免把自己算作占位。
func get_tavern_occupancy(
	settlement_id: String, exclude_mercenary_id: String = ""
) -> int:
	var count: int = 0
	for mercenary: MercenaryData in _mercenaries.values():
		if mercenary == null or mercenary.mercenary_id == exclude_mercenary_id:
			continue
		if mercenary.is_stationed() and mercenary.settlement_id == settlement_id:
			count += 1
		elif mercenary.is_traveling() \
				and mercenary.destination_settlement_id == settlement_id:
			count += 1
	return count


func get_tavern_capacity() -> int:
	return maxi(1, _recruitment_config.mercenary_tavern_capacity)


func get_recruit_price(mercenary: MercenaryData) -> int:
	if mercenary == null or _recruitment_config == null:
		return 0
	return _recruitment_config.get_mercenary_recruit_cost(
		mercenary.tier, mercenary.level, mercenary.mounted
	)


## 日薪唯一来自兵种配置；招募价格加成不影响日薪。
func get_daily_wage(mercenary: MercenaryData) -> int:
	if mercenary == null or _unit_manager == null:
		return 0
	var config := _unit_manager.get_unit_config(mercenary.config_id)
	return maxi(0, config.daily_wage) if config != null else 0


func get_tier_display_name(mercenary: MercenaryData) -> String:
	if mercenary == null:
		return "未知"
	return UnitConfig.tier_display_name(mercenary.tier)


## 玩家打开酒馆时登记，NPC 招募检查会跳过该城镇；关闭时传空字符串。
func set_player_viewing_tavern(settlement_id: String) -> void:
	_player_viewing_tavern_id = settlement_id if settlement_id else ""


# ---------------------------------------------------------------------------
# 初始化与时间推进
# ---------------------------------------------------------------------------


## 新游戏或旧存档首次载入时建立雇佣兵池。只执行一次。
## seed_initial=false 仅用于显式空池测试或迁移；不会重复发放。
func initialize_world(seed_initial: bool = true) -> void:
	if _initialized:
		return
	_initialized = true
	if not seed_initial:
		return
	var count: int = maxi(0, _recruitment_config.mercenary_initial_count)
	for _i: int in range(count):
		_spawn_mercenary()
	_assign_all_waiting()


## 只由 WorldSimulation 的世界 tick 调用；暂停时不推进。
func tick(world_delta: float) -> void:
	if not _initialized or world_delta <= 0.0:
		return
	_update_traveling(world_delta)
	_advance_growth(world_delta)
	_advance_flow(world_delta)
	_advance_npc_recruitment(world_delta)


func _advance_growth(world_delta: float) -> void:
	var interval: float = _hours_to_world_seconds(
		_recruitment_config.mercenary_growth_interval_hours
	)
	if interval <= 0.0:
		return
	_growth_elapsed += world_delta
	var spawned: int = 0
	while _growth_elapsed >= interval and spawned < MAX_SPAWN_PER_TICK:
		_growth_elapsed -= interval
		spawned += 1
		_spawn_mercenary()
	if spawned > 0:
		_assign_all_waiting()


func _advance_flow(world_delta: float) -> void:
	var interval: float = _hours_to_world_seconds(
		_recruitment_config.mercenary_flow_interval_hours
	)
	if interval <= 0.0:
		return
	_flow_elapsed += world_delta
	var checks: int = 0
	while _flow_elapsed >= interval and checks < MAX_FLOW_CHECKS_PER_TICK:
		_flow_elapsed -= interval
		checks += 1
		_try_start_flows()
	if checks > 0:
		_assign_all_waiting()


func _advance_npc_recruitment(world_delta: float) -> void:
	var interval: float = _hours_to_world_seconds(
		_recruitment_config.npc_mercenary_recruit_interval_hours
	)
	if interval <= 0.0:
		return
	_npc_recruit_elapsed += world_delta
	var checks: int = 0
	while _npc_recruit_elapsed >= interval and checks < MAX_FLOW_CHECKS_PER_TICK:
		_npc_recruit_elapsed -= interval
		checks += 1
		_try_npc_recruitment()


func _hours_to_world_seconds(hours: float) -> float:
	return maxf(0.0, hours) * TimeManager.REAL_SECONDS_PER_GAME_HOUR


# ---------------------------------------------------------------------------
# 生成、分配与流动
# ---------------------------------------------------------------------------


func _spawn_mercenary() -> MercenaryData:
	if _id_generator == null or _unit_manager == null:
		push_error("MercenaryManager 尚未初始化")
		return null
	var config_id: String = _recruitment_config.pick_mercenary_config_id(_rng)
	var config := _unit_manager.get_unit_config(config_id)
	if config == null:
		push_error("雇佣兵兵种配置不存在: %s" % config_id)
		return null
	if config.tier < 2 or config.tier > 3:
		push_error("雇佣兵只允许 Tier 2/3: %s" % config_id)
		return null

	var mercenary := MercenaryData.new()
	mercenary.mercenary_id = _id_generator.next_id(IdGenerator.MERCENARY)
	mercenary.config_id = config.config_id
	mercenary.display_name = config.display_name
	mercenary.tier = config.tier
	mercenary.level = _recruitment_config.pick_experience_level(_rng)
	mercenary.exp = 0
	mercenary.mounted = config.default_equipment.has(
		EquipmentConfig.SLOT_NAMES[EquipmentConfig.Slot.MOUNT]
	)
	# 外观在生成记录时一次性确定并持久化：酒馆预览与最终招募单位使用
	# 完全相同的罩袍/头盔/缨饰，且不随 UI 打开次数变化。
	mercenary.appearance = _build_mercenary_appearance(mercenary, config)
	mercenary.state = MercenaryData.State.WAITING
	mercenary.spawned_at = TimeManager.world_elapsed_seconds
	_mercenaries[mercenary.mercenary_id] = mercenary
	return mercenary


## 把待分配池中的雇佣兵均匀分配到有空位的城镇酒馆。
func _assign_all_waiting() -> void:
	for mercenary: MercenaryData in get_all_mercenaries():
		if mercenary.is_waiting():
			_assign_to_tavern(mercenary)


func _assign_to_tavern(mercenary: MercenaryData) -> bool:
	if mercenary == null:
		return false
	var town := _pick_tavern_with_capacity(mercenary.mercenary_id)
	if town == null:
		mercenary.state = MercenaryData.State.WAITING
		mercenary.settlement_id = ""
		mercenary.destination_settlement_id = ""
		mercenary.travel_remaining = 0.0
		return false
	mercenary.state = MercenaryData.State.STATIONED
	mercenary.settlement_id = town.settlement_id
	mercenary.destination_settlement_id = ""
	mercenary.travel_remaining = 0.0
	return true


## 随机选择空位最少的酒馆之一，避免所有雇佣兵长期集中在一处。
func _pick_tavern_with_capacity(
	exclude_mercenary_id: String,
	exclude_settlement_id: String = ""
) -> SettlementData:
	var towns: Array[SettlementData] = _get_tavern_towns()
	if towns.is_empty():
		return null
	var capacity: int = get_tavern_capacity()
	var best_occupancy: int = capacity
	var candidates: Array[SettlementData] = []
	for town: SettlementData in towns:
		if town.settlement_id == exclude_settlement_id:
			continue
		var occupancy: int = get_tavern_occupancy(
			town.settlement_id, exclude_mercenary_id
		)
		if occupancy >= capacity:
			continue
		if occupancy < best_occupancy:
			best_occupancy = occupancy
			candidates.clear()
		if occupancy == best_occupancy:
			candidates.append(town)
	if candidates.is_empty():
		return null
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _get_tavern_towns() -> Array[SettlementData]:
	var towns: Array[SettlementData] = []
	if _settlement_manager == null:
		return towns
	for settlement: SettlementData in _settlement_manager.get_all_settlements():
		if settlement != null \
				and settlement.settlement_type == SettlementData.SettlementType.TOWN:
			towns.append(settlement)
	towns.sort_custom(func(a: SettlementData, b: SettlementData) -> bool:
		return a.settlement_id < b.settlement_id
	)
	return towns


func _try_start_flows() -> void:
	for mercenary: MercenaryData in get_all_mercenaries():
		if not mercenary.is_stationed():
			continue
		if _rng.randf() > _recruitment_config.mercenary_flow_chance:
			continue
		var destination := _pick_tavern_with_capacity(
			mercenary.mercenary_id, mercenary.settlement_id
		)
		if destination == null:
			continue
		mercenary.state = MercenaryData.State.TRAVELING
		mercenary.destination_settlement_id = destination.settlement_id
		mercenary.settlement_id = ""
		mercenary.travel_remaining = _hours_to_world_seconds(
			_recruitment_config.mercenary_travel_duration_hours
		)


func _update_traveling(world_delta: float) -> void:
	for mercenary: MercenaryData in get_all_mercenaries():
		if not mercenary.is_traveling():
			continue
		mercenary.travel_remaining = maxf(
			0.0, mercenary.travel_remaining - world_delta
		)
		# 流动时间为 0 时立即到达，保证配置可以关闭旅行延迟。
		if mercenary.travel_remaining > 0.0:
			continue
		_complete_travel(mercenary)


func _complete_travel(mercenary: MercenaryData) -> void:
	var destination := _settlement_manager.get_settlement(
		mercenary.destination_settlement_id
	)
	if destination != null \
			and destination.settlement_type == SettlementData.SettlementType.TOWN \
			and get_tavern_occupancy(destination.settlement_id, mercenary.mercenary_id) \
				< get_tavern_capacity():
		mercenary.state = MercenaryData.State.STATIONED
		mercenary.settlement_id = destination.settlement_id
		mercenary.destination_settlement_id = ""
		mercenary.travel_remaining = 0.0
		return
	# 目的地失效或已满：回到待分配池，稍后重新分配，不重复生成。
	mercenary.state = MercenaryData.State.WAITING
	mercenary.settlement_id = ""
	mercenary.destination_settlement_id = ""
	mercenary.travel_remaining = 0.0
	_assign_to_tavern(mercenary)


# ---------------------------------------------------------------------------
# 招募
# ---------------------------------------------------------------------------


## 玩家酒馆招募入口。返回 { success, reason, price, unit_id, unit_name }。
func recruit_mercenary_for_player(
	mercenary_id: String,
	settlement_id: String,
	profile: PlayerProfile,
	party_id: String = ""
) -> Dictionary:
	var resolved_party_id: String = party_id if not party_id.is_empty() \
		else _player_party_id
	var party := _party_manager.get_party(resolved_party_id) \
		if _party_manager != null else null
	if party == null:
		return _failure("玩家部队不可用。")
	return _recruit_mercenary(
		mercenary_id, settlement_id, party, profile, true
	)


## NPC 或测试可直接调用的通用招募入口。payer 需支持 can_afford/spend_gold。
func recruit_mercenary_for_party(
	mercenary_id: String,
	settlement_id: String,
	party: PartyData,
	payer: Variant
) -> Dictionary:
	return _recruit_mercenary(mercenary_id, settlement_id, party, payer, false)


func _recruit_mercenary(
	mercenary_id: String,
	settlement_id: String,
	party: PartyData,
	payer: Variant,
	is_player: bool
) -> Dictionary:
	last_error = ""
	if _unit_manager == null or _party_manager == null:
		return _failure("雇佣兵管理器尚未初始化。")
	var mercenary := get_mercenary(mercenary_id)
	if mercenary == null:
		return _failure("该雇佣兵已不在可招募池。")
	if not mercenary.is_stationed() or mercenary.settlement_id != settlement_id:
		return _failure("该雇佣兵已离开当前酒馆。")
	var settlement := _settlement_manager.get_settlement(settlement_id) \
		if _settlement_manager != null else null
	if settlement == null \
			or settlement.settlement_type != SettlementData.SettlementType.TOWN:
		return _failure("当前地点没有可用的酒馆。")
	if party == null or not party.is_available_for_world():
		return _failure("部队当前无法接受新成员。")
	if payer == null or not payer.has_method("can_afford") \
			or not payer.has_method("spend_gold"):
		return _failure("招募者资金接口不可用。")
	var config := _unit_manager.get_unit_config(mercenary.config_id)
	if config == null:
		return _failure("雇佣兵兵种配置缺失。")
	var price: int = get_recruit_price(mercenary)
	if not bool(payer.can_afford(price)):
		return _failure("金币不足，招募需要 %d 金币。" % price)

	# 先创建并加入部队，金币扣除失败时整体回滚。
	var unit := _unit_manager.create_unit(
		config, party.faction_id, "", mercenary.level
	)
	if unit == null:
		return _failure("无法创建雇佣兵单位。")
	unit.exp = mercenary.exp
	unit.is_mercenary = true
	unit.recruit_source = UnitData.MERCENARY_RECRUIT_SOURCE
	unit.recruit_settlement_id = settlement_id
	unit.origin_faction_id = party.faction_id
	unit.joined_at_game_time = TimeManager.world_elapsed_seconds
	# 预览与实战共用同一份持久化外观；克隆后单位独立持有，不共享字典。
	unit.appearance = get_mercenary_appearance(mercenary)
	if not _party_manager.add_member(party.party_id, unit.unit_id):
		_unit_manager.remove_unit(unit.unit_id)
		return _failure("雇佣兵无法加入部队。")
	if not bool(payer.spend_gold(price)):
		_party_manager.remove_member(party.party_id, unit.unit_id)
		_unit_manager.remove_unit(unit.unit_id)
		return _failure("金币不足，招募失败。")

	_mercenaries.erase(mercenary.mercenary_id)
	# 酒馆空位立即让给待分配池中的雇佣兵。
	_assign_all_waiting()
	last_error = ""
	var result := {
		"success": true,
		"reason": "",
		"price": price,
		"unit_id": unit.unit_id,
		"unit_name": unit.display_name,
		"mercenary_id": mercenary.mercenary_id,
		"settlement_id": settlement_id,
		"party_id": party.party_id,
		"is_player_recruiter": is_player,
	}
	EventBus.mercenary_recruited.emit(
		settlement_id,
		party.party_id,
		mercenary.mercenary_id,
		unit.unit_id,
		unit.display_name,
		is_player
	)
	return result


## 返回雇佣兵持久化的外观快照；旧存档缺失时按同一套规则补生成一次。
func get_mercenary_appearance(mercenary: MercenaryData) -> Dictionary:
	if mercenary == null:
		return {}
	if not mercenary.appearance.is_empty():
		return mercenary.appearance.duplicate(true)
	var config := _unit_manager.get_unit_config(mercenary.config_id) \
		if _unit_manager != null else null
	if config == null:
		return {}
	mercenary.appearance = _build_mercenary_appearance(mercenary, config)
	return mercenary.appearance.duplicate(true)


## 雇佣兵外观使用 mercenary_id 派生随机种子：生成顺序变化不会改变同一记录的外观。
func _build_mercenary_appearance(
	mercenary: MercenaryData, config: UnitConfig
) -> Dictionary:
	if mercenary == null or config == null:
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("mercenary|%s" % mercenary.mercenary_id)
	return UnitAppearance.build_appearance(
		config, null, _appearance_config, false, rng, true
	)


func _failure(reason: String) -> Dictionary:
	last_error = reason
	return {"success": false, "reason": reason}


# ---------------------------------------------------------------------------
# NPC 招募（低优先级）
# ---------------------------------------------------------------------------


func _try_npc_recruitment() -> void:
	if _party_manager == null or _noble_manager == null:
		return
	if _recruitment_config.npc_mercenary_recruit_chance < 1.0 \
			and _rng.randf() > _recruitment_config.npc_mercenary_recruit_chance:
		return

	var recruiters: Array[Dictionary] = []
	for noble: NobleData in _noble_manager.get_all_nobles():
		if noble == null or not noble.alive or noble.is_player_lord:
			continue
		var party := _party_manager.get_party(noble.party_id)
		if party == null or not party.is_available_for_world():
			continue
		if party.member_unit_ids.size() \
				>= _recruitment_config.npc_mercenary_party_size_threshold:
			continue
		var town := _find_town_near(party.world_position)
		if town == null or town.settlement_id == _player_viewing_tavern_id:
			continue
		if get_stationed_count(town.settlement_id) <= 0:
			continue
		recruiters.append({"party": party, "town": town, "payer": party})
	if recruiters.is_empty():
		return

	var attempts: int = mini(
		maxi(1, _recruitment_config.npc_mercenary_recruit_max_per_check),
		recruiters.size()
	)
	var start: int = _rng.randi_range(0, recruiters.size() - 1)
	for offset: int in range(attempts):
		var recruiter: Dictionary = recruiters[(start + offset) % recruiters.size()]
		var town := recruiter["town"] as SettlementData
		var party := recruiter["party"] as PartyData
		var stationed := get_stationed_mercenaries(town.settlement_id)
		if stationed.is_empty():
			continue
		var mercenary := stationed[_rng.randi_range(0, stationed.size() - 1)]
		var price: int = get_recruit_price(mercenary)
		if not party.can_afford(
			price + _recruitment_config.npc_mercenary_gold_reserve
		):
			continue
		var result := _recruit_mercenary(
			mercenary.mercenary_id, town.settlement_id, party, party, false
		)
		if bool(result.get("success", false)):
			return


func _find_town_near(world_position: Vector2) -> SettlementData:
	if _settlement_manager == null:
		return null
	var nearest: SettlementData = null
	var nearest_distance: float = INF
	for settlement: SettlementData in _settlement_manager.get_all_settlements():
		if settlement == null \
				or settlement.settlement_type != SettlementData.SettlementType.TOWN:
			continue
		var distance: float = world_position.distance_to(settlement.world_position)
		if distance <= _recruitment_config.npc_mercenary_town_radius \
				and distance < nearest_distance:
			nearest_distance = distance
			nearest = settlement
	return nearest


# ---------------------------------------------------------------------------
# 序列化与读档校正
# ---------------------------------------------------------------------------


func to_dict() -> Dictionary:
	var records: Array[Dictionary] = []
	for mercenary: MercenaryData in get_all_mercenaries():
		records.append(mercenary.to_dict())
	return {
		"initialized": _initialized,
		"growth_elapsed": _growth_elapsed,
		"flow_elapsed": _flow_elapsed,
		"npc_recruit_elapsed": _npc_recruit_elapsed,
		"records": records,
	}


func load_from_dict(payload: Dictionary) -> void:
	_mercenaries.clear()
	_initialized = bool(payload.get("initialized", false))
	_growth_elapsed = maxf(0.0, float(payload.get("growth_elapsed", 0.0)))
	_flow_elapsed = maxf(0.0, float(payload.get("flow_elapsed", 0.0)))
	_npc_recruit_elapsed = maxf(
		0.0, float(payload.get("npc_recruit_elapsed", 0.0))
	)
	var records_value: Variant = payload.get("records", [])
	if records_value is Array:
		for value: Variant in records_value:
			if not value is Dictionary:
				continue
			var mercenary := MercenaryData.from_dict(value)
			if mercenary.mercenary_id.is_empty() \
					or _mercenaries.has(mercenary.mercenary_id):
				continue
			_mercenaries[mercenary.mercenary_id] = mercenary
	_sanitize_after_load()


## 读档校正：无效配置、无效城镇与超容量记录一律回到待分配池。
func _sanitize_after_load() -> void:
	var capacity: int = get_tavern_capacity()
	var occupancy: Dictionary = {}
	for mercenary: MercenaryData in get_all_mercenaries():
		var config := _unit_manager.get_unit_config(mercenary.config_id) \
			if _unit_manager != null else null
		if config == null:
			push_warning(
				"雇佣兵 %s 的兵种配置不存在，保留记录但不参与驻留"
				% mercenary.mercenary_id
			)
		if mercenary.is_stationed():
			var town := _settlement_manager.get_settlement(
				mercenary.settlement_id
			) if _settlement_manager != null else null
			if town == null \
					or town.settlement_type != SettlementData.SettlementType.TOWN:
				mercenary.state = MercenaryData.State.WAITING
				mercenary.settlement_id = ""
				continue
			var current: int = int(occupancy.get(town.settlement_id, 0))
			if current >= capacity:
				mercenary.state = MercenaryData.State.WAITING
				mercenary.settlement_id = ""
				continue
			occupancy[town.settlement_id] = current + 1
		elif mercenary.is_traveling():
			var destination := _settlement_manager.get_settlement(
				mercenary.destination_settlement_id
			) if _settlement_manager != null else null
			if destination == null \
					or destination.settlement_type != SettlementData.SettlementType.TOWN:
				mercenary.state = MercenaryData.State.WAITING
				mercenary.destination_settlement_id = ""
				mercenary.travel_remaining = 0.0
				continue
			var destination_count: int = int(
				occupancy.get(destination.settlement_id, 0)
			)
			if destination_count >= capacity:
				mercenary.state = MercenaryData.State.WAITING
				mercenary.destination_settlement_id = ""
				mercenary.travel_remaining = 0.0
				continue
			occupancy[destination.settlement_id] = destination_count + 1
