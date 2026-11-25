class_name RecruitmentConfig
extends Resource
## 普通招募、酒馆雇佣兵与全地图雇佣兵池的统一配置。
##
## 价格计算集中在本类，招募入口（村庄候选人、酒馆、NPC AI）只调用接口，
## 不各自维护另一套价格公式。日薪仍由 UnitConfig.daily_wage 唯一提供，
## 避免同一数值在 Resource 与 UnitConfig 中重复。

@export_category("Civilian Recruitment")
## 普通 Tier 1 村庄招募价格（一次性扣除）。
@export var civilian_tier1_recruit_cost: int = 5
## 普通 Tier 3 招募价格（例如贵族冒险者）。
@export var civilian_tier3_recruit_cost: int = 400

@export_category("Mercenary Price")
@export var mercenary_tier2_base_cost: int = 35
@export var mercenary_tier3_base_cost: int = 80
## 允许生成的雇佣兵战斗经验等级（2=普通士兵 / 3=老兵 / 4=精锐）。
@export var mercenary_experience_levels: Array[int] = [2, 3, 4]
## 与等级一一对应的累计价格加成；不允许新兵或百战精锐。
@export var mercenary_experience_cost_bonuses: Array[int] = [0, 10, 30]
@export var mercenary_experience_weights: Array[float] = [0.55, 0.30, 0.15]
## 骑马雇佣兵的额外招募价格；不影响日薪。
@export var mercenary_mounted_cost_bonus: int = 30

@export_category("Mercenary World Pool")
## 新游戏初始雇佣兵总数（包含酒馆驻留与待分配池）。
@export var mercenary_initial_count: int = 10
## 每隔多少游戏小时向全地图总量增加 1 名雇佣兵。
@export var mercenary_growth_interval_hours: float = 12.0
## 每个城镇酒馆最多同时驻留的雇佣兵数量。
@export var mercenary_tavern_capacity: int = 7
## 雇佣兵流动检查周期与每次检查时的离开概率。
@export var mercenary_flow_interval_hours: float = 24.0
@export_range(0.0, 1.0, 0.01) var mercenary_flow_chance: float = 0.25
## 城镇间流动所需的世界时间。
@export var mercenary_travel_duration_hours: float = 2.0
## 雇佣兵类型配置 ID 与随机权重（一一对应）。
@export var mercenary_type_config_ids: Array[String] = [
	"mercenary_archer",
	"mercenary_sergeant",
	"mercenary_mounted_sergeant",
	"mercenary_rogue_knight",
]
@export var mercenary_type_weights: Array[float] = [3.0, 3.0, 2.0, 1.0]

@export_category("NPC Mercenary Recruitment")
## NPC 领主招募检查周期（游戏小时）。玩家正在查看的酒馆不会被 NPC 抢购。
@export var npc_mercenary_recruit_interval_hours: float = 6.0
@export_range(0.0, 1.0, 0.01) var npc_mercenary_recruit_chance: float = 0.25
@export var npc_mercenary_recruit_max_per_check: int = 1
## NPC 部队人数达到该值时不再招募雇佣兵（低优先级补充）。
@export var npc_mercenary_party_size_threshold: int = 18
## NPC 招募后至少保留的金币。
@export var npc_mercenary_gold_reserve: int = 50
## NPC 必须位于城镇酒馆交互半径内才能招募。
@export var npc_mercenary_town_radius: float = 40.0


## 普通招募价格：只定义 Tier 1 与 Tier 3；Tier 2 普通招募当前不使用。
func get_civilian_recruit_cost(tier: int) -> int:
	if tier <= 1:
		return maxi(0, civilian_tier1_recruit_cost)
	if tier >= 3:
		return maxi(0, civilian_tier3_recruit_cost)
	return 0


func get_mercenary_base_cost(tier: int) -> int:
	match tier:
		2:
			return maxi(0, mercenary_tier2_base_cost)
		3:
			return maxi(0, mercenary_tier3_base_cost)
		_:
			return 0


## 战斗经验累计价格加成：等级低于最低档为 0，高于最高档取最高档。
func get_experience_cost_bonus(level: int) -> int:
	if mercenary_experience_levels.is_empty() \
			or mercenary_experience_cost_bonuses.is_empty():
		return 0
	var bonus: int = 0
	for index: int in range(mercenary_experience_levels.size()):
		if level < mercenary_experience_levels[index]:
			break
		bonus = maxi(0, int(mercenary_experience_cost_bonuses[
			mini(index, mercenary_experience_cost_bonuses.size() - 1)
		]))
	return bonus


## 统一价格公式：基础价格 + 经验加成 + 骑马加成。
func get_mercenary_recruit_cost(tier: int, level: int, mounted: bool) -> int:
	var cost: int = get_mercenary_base_cost(tier)
	cost += get_experience_cost_bonus(level)
	if mounted:
		cost += maxi(0, mercenary_mounted_cost_bonus)
	return maxi(0, cost)


## 按权重随机选择雇佣兵类型；权重缺失或全为 0 时退化为均匀随机。
func pick_mercenary_config_id(rng: RandomNumberGenerator) -> String:
	if mercenary_type_config_ids.is_empty():
		return ""
	var weights: Array[float] = []
	var total: float = 0.0
	for index: int in range(mercenary_type_config_ids.size()):
		var weight: float = maxf(
			0.0,
			float(mercenary_type_weights[index])
				if index < mercenary_type_weights.size() else 1.0
		)
		weights.append(weight)
		total += weight
	if total <= 0.0:
		return mercenary_type_config_ids[rng.randi_range(
			0, mercenary_type_config_ids.size() - 1
		)]
	var roll: float = rng.randf_range(0.0, total)
	for index: int in range(mercenary_type_config_ids.size()):
		roll -= weights[index]
		if roll <= 0.0:
			return mercenary_type_config_ids[index]
	return mercenary_type_config_ids[mercenary_type_config_ids.size() - 1]


## 按权重随机选择初始战斗经验；只返回配置允许的等级。
func pick_experience_level(rng: RandomNumberGenerator) -> int:
	if mercenary_experience_levels.is_empty():
		return 2
	var weights: Array[float] = []
	var total: float = 0.0
	for index: int in range(mercenary_experience_levels.size()):
		var weight: float = maxf(
			0.0,
			float(mercenary_experience_weights[index])
				if index < mercenary_experience_weights.size() else 1.0
		)
		weights.append(weight)
		total += weight
	if total <= 0.0:
		return mercenary_experience_levels[rng.randi_range(
			0, mercenary_experience_levels.size() - 1
		)]
	var roll: float = rng.randf_range(0.0, total)
	for index: int in range(mercenary_experience_levels.size()):
		roll -= weights[index]
		if roll <= 0.0:
			return mercenary_experience_levels[index]
	return mercenary_experience_levels[mercenary_experience_levels.size() - 1]


func sanitize() -> void:
	civilian_tier1_recruit_cost = maxi(0, civilian_tier1_recruit_cost)
	civilian_tier3_recruit_cost = maxi(0, civilian_tier3_recruit_cost)
	mercenary_tier2_base_cost = maxi(0, mercenary_tier2_base_cost)
	mercenary_tier3_base_cost = maxi(0, mercenary_tier3_base_cost)
	mercenary_mounted_cost_bonus = maxi(0, mercenary_mounted_cost_bonus)

	if mercenary_experience_levels.is_empty():
		mercenary_experience_levels = [2, 3, 4]
	while mercenary_experience_cost_bonuses.size() < mercenary_experience_levels.size():
		mercenary_experience_cost_bonuses.append(
			mercenary_experience_cost_bonuses[
				mercenary_experience_cost_bonuses.size() - 1
			] if not mercenary_experience_cost_bonuses.is_empty() else 0
		)
	while mercenary_experience_weights.size() < mercenary_experience_levels.size():
		mercenary_experience_weights.append(1.0)

	mercenary_initial_count = maxi(0, mercenary_initial_count)
	mercenary_growth_interval_hours = maxf(0.1, mercenary_growth_interval_hours)
	mercenary_tavern_capacity = maxi(1, mercenary_tavern_capacity)
	mercenary_flow_interval_hours = maxf(0.1, mercenary_flow_interval_hours)
	mercenary_flow_chance = clampf(mercenary_flow_chance, 0.0, 1.0)
	mercenary_travel_duration_hours = maxf(0.0, mercenary_travel_duration_hours)

	if mercenary_type_config_ids.is_empty():
		mercenary_type_config_ids = [
			"mercenary_archer",
			"mercenary_sergeant",
			"mercenary_mounted_sergeant",
			"mercenary_rogue_knight",
		]
	if mercenary_type_weights.size() < mercenary_type_config_ids.size():
		mercenary_type_weights.resize(mercenary_type_config_ids.size())
		for index: int in range(mercenary_type_weights.size()):
			mercenary_type_weights[index] = maxf(0.0, mercenary_type_weights[index])

	npc_mercenary_recruit_interval_hours = maxf(
		0.1, npc_mercenary_recruit_interval_hours
	)
	npc_mercenary_recruit_chance = clampf(npc_mercenary_recruit_chance, 0.0, 1.0)
	npc_mercenary_recruit_max_per_check = maxi(
		0, npc_mercenary_recruit_max_per_check
	)
	npc_mercenary_party_size_threshold = maxi(
		1, npc_mercenary_party_size_threshold
	)
	npc_mercenary_gold_reserve = maxi(0, npc_mercenary_gold_reserve)
	npc_mercenary_town_radius = maxf(0.0, npc_mercenary_town_radius)
