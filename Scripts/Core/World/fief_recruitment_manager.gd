class_name FiefRecruitmentManager
extends RefCounted
## 封地采邑征召与补充的唯一业务入口。
##
## 职责：
## - 校验封地所有权（只有 owner_lord_id 与领主 ID 相同才允许征召）；
## - 以“组”为单位原子化生成 6 名士兵并加入领主部队；
## - 征召后扣除村庄人口、繁荣度并重算税收；
## - 按 WorldTime 推进采邑储备补充。
##
## 本类不操作 UI，也不直接写场景节点；成功事实通过 EventBus 广播，
## 由世界日志与大地图提示自行订阅。

const GROUP_COMPOSITION: Array[Dictionary] = [
	{"config_id": "infantry_veteran", "display_name": "骑马扈从", "count": 1, "mounted": true},
	{"config_id": "infantry_trained", "display_name": "骑马军士", "count": 1, "mounted": true},
	{"config_id": "infantry_trained", "display_name": "军士", "count": 1, "mounted": false},
	{"config_id": "infantry_militia", "display_name": "步兵", "count": 2, "mounted": false},
	{"config_id": "archer_militia", "display_name": "弓箭手", "count": 1, "mounted": false},
]

const RECRUIT_SOURCE: String = "fief_recruitment"

var _unit_manager: UnitManager = null
var _party_manager: PartyManager = null
var _settlement_manager: SettlementManager = null
var _lord_manager: LordManager = null
var _family_registry: FamilyRegistry = null
var _economy_config: SettlementEconomyConfig = null
var _appearance_config: AppearanceConfig = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var last_error: String = ""


func setup(
	unit_manager: UnitManager,
	party_manager: PartyManager,
	settlement_manager: SettlementManager,
	lord_manager: LordManager,
	family_registry: FamilyRegistry = null,
	economy_config: SettlementEconomyConfig = null
) -> void:
	_unit_manager = unit_manager
	_party_manager = party_manager
	_settlement_manager = settlement_manager
	_lord_manager = lord_manager
	_family_registry = family_registry
	_economy_config = economy_config if economy_config != null \
		else SettlementEconomyConfig.new()
	_economy_config.sanitize()
	_rng.randomize()


func set_appearance_config(config: AppearanceConfig) -> void:
	_appearance_config = config


func get_economy_config() -> SettlementEconomyConfig:
	return _economy_config


## 新游戏初始化或读档修正：写入容量、初始储备、税收参数。
## fill_initial_stock 只在新游戏使用；读档必须保留存档中的实际储备。
func initialize_settlement(
	settlement: SettlementData, fill_initial_stock: bool = false
) -> void:
	if settlement == null:
		return
	# 只有村庄有采邑储备；城镇/城堡即使读档也不保留容量。
	settlement.fief_recruitment_capacity = (
		_economy_config.fief_max_stock
		if settlement.settlement_type == SettlementData.SettlementType.VILLAGE
		else 0
	)
	settlement.fief_recruitment_stock = clampi(
		settlement.fief_recruitment_stock,
		0,
		settlement.fief_recruitment_capacity
	)
	if fill_initial_stock:
		settlement.fief_recruitment_stock = _economy_config.fief_initial_stock
		settlement.fief_recruitment_elapsed = 0.0
	if settlement.tax_base <= 0:
		settlement.tax_base = _economy_config.default_tax_base
	clamp_settlement(settlement)


## 对人口、繁荣度、储备与税收做统一边界修正。
func clamp_settlement(settlement: SettlementData) -> void:
	if settlement == null:
		return
	settlement.population = maxi(
		_economy_config.population_min, settlement.population
	)
	settlement.prosperity = clampi(
		settlement.prosperity,
		_economy_config.prosperity_min,
		_economy_config.prosperity_max
	)
	settlement.fief_recruitment_capacity = (
		maxi(0, _economy_config.fief_max_stock)
		if settlement.settlement_type == SettlementData.SettlementType.VILLAGE
		else 0
	)
	settlement.fief_recruitment_stock = clampi(
		settlement.fief_recruitment_stock,
		0,
		settlement.fief_recruitment_capacity
	)
	settlement.fief_recruitment_elapsed = maxf(
		0.0, settlement.fief_recruitment_elapsed
	)
	settlement.adventurer_refresh_elapsed = maxf(
		0.0, settlement.adventurer_refresh_elapsed
	)
	settlement.tax_base = maxi(0, settlement.tax_base)
	settlement.tax_income_per_day = get_tax_income(settlement)


func get_tax_income(settlement: SettlementData) -> int:
	if settlement == null:
		return 0
	return TaxCalculator.compute_daily_tax(
		settlement.population, settlement.prosperity, settlement.tax_base
	)


## 当前人口/繁荣度对应的采邑补充周期（世界秒）。
func get_refill_interval(settlement: SettlementData) -> float:
	if settlement == null:
		return _economy_config.refill_base_interval
	var population_factor: float = clampf(
		_economy_config.refill_population_reference
			/ float(maxi(settlement.population, 1)),
		_economy_config.refill_population_factor_min,
		_economy_config.refill_population_factor_max
	)
	var prosperity_factor: float = clampf(
		_economy_config.refill_prosperity_reference
			/ float(maxi(settlement.prosperity, 1)),
		_economy_config.refill_prosperity_factor_min,
		_economy_config.refill_prosperity_factor_max
	)
	return maxf(
		1.0,
		_economy_config.refill_base_interval * population_factor * prosperity_factor
	)


## 只由 WorldSimulation 的世界 tick 调用；暂停时不会推进。
func tick(world_delta: float) -> void:
	if _settlement_manager == null or world_delta <= 0.0:
		return
	for settlement: SettlementData in _settlement_manager.get_all_settlements():
		if settlement == null \
				or settlement.settlement_type != SettlementData.SettlementType.VILLAGE:
			continue
		if settlement.fief_recruitment_capacity <= 0:
			continue
		if settlement.fief_recruitment_stock >= settlement.fief_recruitment_capacity:
			settlement.fief_recruitment_elapsed = 0.0
			continue
		settlement.fief_recruitment_elapsed += world_delta
		var interval: float = get_refill_interval(settlement)
		var guard: int = 0
		while settlement.fief_recruitment_elapsed >= interval \
				and settlement.fief_recruitment_stock < settlement.fief_recruitment_capacity \
				and guard < 64:
			settlement.fief_recruitment_elapsed -= interval
			settlement.fief_recruitment_stock += 1
			guard += 1
		if settlement.fief_recruitment_stock >= settlement.fief_recruitment_capacity:
			settlement.fief_recruitment_elapsed = 0.0


## 贵族是否拥有该封地；只判断所有权，不检查储备、部队状态等征召前置条件。
## 供征召与只读经济/事件预览共用，避免 UI 复制授权规则。
func is_authorized_owner(settlement: SettlementData, lord_id: String) -> bool:
	if settlement == null or lord_id.strip_edges().is_empty():
		return false
	var lord := _lord_manager.get_lord(lord_id) if _lord_manager != null else null
	if lord == null or not lord.is_alive:
		return false
	var noble := lord as NobleData
	if settlement.owner_noble_id == lord_id:
		return true
	if settlement.owner_noble_id.is_empty() \
			and not settlement.owner_house_id.is_empty() and noble != null:
		return noble.house_id == settlement.owner_house_id and noble.is_house_leader
	return false


## 贵族是否获得封地家族授权；空 ID 或无效贵族一律拒绝。
## 本阶段规则：只有村庄可征召；封地明确指定 owner_noble_id 时只认该贵族；
## 未指定个人所有者时，允许所有者家族的领袖征召。
func can_recruit(settlement_id: String, lord_id: String) -> bool:
	var settlement: SettlementData = null
	if _settlement_manager != null:
		settlement = _settlement_manager.get_settlement(settlement_id)
	if settlement == null or settlement.settlement_type != SettlementData.SettlementType.VILLAGE:
		last_error = "该地点不是村庄，无法征召采邑。"
		return false
	if lord_id.strip_edges().is_empty():
		last_error = "没有有效的领主身份。"
		return false
	var lord := _lord_manager.get_lord(lord_id) if _lord_manager != null else null
	if lord == null or not lord.is_alive:
		last_error = "领主不存在或已死亡，无法征召采邑。"
		return false
	if not is_authorized_owner(settlement, lord_id):
		last_error = "你不是该封地家族的授权贵族，无法征召采邑。"
		return false
	if settlement.fief_recruitment_stock <= 0:
		last_error = "当前没有可征召的采邑。"
		return false
	var party := _party_manager.get_party(lord.party_id) if _party_manager != null else null
	if party == null:
		last_error = "领主没有可用的部队。"
		return false
	if not party.is_available_for_world():
		last_error = "领主部队当前无法接受征召。"
		return false
	last_error = ""
	return true


## 征召一组采邑。成功返回 true；失败不扣除任何资源，也不留下部分单位。
func recruit_group(settlement_id: String, lord_id: String) -> bool:
	if not can_recruit(settlement_id, lord_id):
		return false
	var settlement := _settlement_manager.get_settlement(settlement_id)
	var lord := _lord_manager.get_lord(lord_id)
	var party := _party_manager.get_party(lord.party_id)

	var created_units: Array[UnitData] = []
	var expected_count: int = 0
	for entry: Dictionary in GROUP_COMPOSITION:
		expected_count += int(entry.get("count", 0))
	if expected_count != _economy_config.fief_group_size:
		last_error = "采邑编制配置人数与每组人数不一致。"
		return false

	var family: FamilyConfig = null
	if _family_registry != null and not settlement.family_id.is_empty():
		family = _family_registry.get_config(settlement.family_id)

	for entry: Dictionary in GROUP_COMPOSITION:
		var config_id: String = str(entry.get("config_id", ""))
		var config := _unit_manager.get_unit_config(config_id)
		if config == null:
			last_error = "采邑兵种配置不存在: %s" % config_id
			_rollback_units(created_units)
			return false
		var display_name: String = str(entry.get("display_name", config.display_name))
		var count: int = int(entry.get("count", 0))
		for _i: int in range(count):
			var unit := _unit_manager.create_unit(
				config, party.faction_id, display_name
			)
			if unit == null:
				last_error = "采邑士兵创建失败。"
				_rollback_units(created_units)
				return false
			created_units.append(unit)
			unit.recruit_source = RECRUIT_SOURCE
			unit.recruit_settlement_id = settlement.settlement_id
			unit.origin_faction_id = party.faction_id
			unit.joined_at_game_time = TimeManager.world_elapsed_seconds
			UnitAppearance.ensure_random(
				unit, config, family, _appearance_config, false, _rng
			)
			if bool(entry.get("mounted", false)):
				if not _unit_manager.equip_item(
					unit.unit_id, _economy_config.fief_mount_equipment_id
				):
					last_error = "采邑骑乘士兵装备马匹失败。"
					_rollback_units(created_units)
					return false
			if not _party_manager.add_member(party.party_id, unit.unit_id):
				last_error = "采邑士兵无法加入领主部队。"
				_rollback_units(created_units)
				return false

	# 所有 6 名士兵创建、装备并加入部队成功后才结算村庄成本。
	settlement.fief_recruitment_stock = maxi(
		0, settlement.fief_recruitment_stock - 1
	)
	settlement.population = maxi(
		_economy_config.population_min,
		settlement.population - _economy_config.fief_population_cost
	)
	settlement.prosperity = clampi(
		settlement.prosperity - _economy_config.fief_prosperity_cost,
		_economy_config.prosperity_min,
		_economy_config.prosperity_max
	)
	settlement.fief_recruitment_elapsed = 0.0
	clamp_settlement(settlement)

	EventBus.fief_recruited.emit(
		party.party_id, settlement.settlement_id, 1, lord.is_player_lord
	)
	last_error = ""
	return true


func _rollback_units(units: Array[UnitData]) -> void:
	for unit: UnitData in units:
		if unit == null:
			continue
		if not unit.current_party_id.is_empty():
			_party_manager.remove_member(unit.current_party_id, unit.unit_id)
		_unit_manager.remove_unit(unit.unit_id)
