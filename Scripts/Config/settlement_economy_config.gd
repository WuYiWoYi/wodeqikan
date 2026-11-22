class_name SettlementEconomyConfig
extends Resource
## 封地经济与征召参数集中配置（Data/Settlements/settlement_economy_config.tres）。
##
## 本资源只保存可调整的平衡参数，不保存任何单个地点的运行时状态。
## 采邑补充周期、人口/繁荣度成本、冒险者刷新与 AI 征召阈值都集中在这里，
## 避免散落在 SettlementManager / AIManager / UI 中。

@export_category("Fief Recruitment")
## 每组采邑固定人数（同时用于校验配置完整性）。
@export var fief_group_size: int = 6
@export var fief_max_stock: int = 4
@export var fief_initial_stock: int = 4
## 采邑骑乘单位使用的马匹装备配置 ID。
@export var fief_mount_equipment_id: String = "mount_horse_01"
## 成功征召一组后扣除的人口与繁荣度。
@export var fief_population_cost: int = 4
@export var fief_prosperity_cost: int = 2

@export_category("Population / Prosperity Bounds")
@export var population_min: int = 0
@export var prosperity_min: int = 0
@export var prosperity_max: int = 100

@export_category("Fief Refill")
## 基础补充周期（世界秒）。实际周期 = 基础周期 × 人口系数 × 繁荣度系数。
@export var refill_base_interval: float = 144.0
@export var refill_population_reference: float = 100.0
@export var refill_prosperity_reference: float = 40.0
## 人口系数 = clamp(reference / max(population, 1), min, max)。
@export var refill_population_factor_min: float = 0.5
@export var refill_population_factor_max: float = 4.0
## 繁荣度系数 = clamp(reference / max(prosperity, 1), min, max)。
@export var refill_prosperity_factor_min: float = 0.6
@export var refill_prosperity_factor_max: float = 3.0

@export_category("Adventurers")
@export var adventurer_max_candidates: int = 5
@export var adventurer_refresh_interval: float = 144.0
@export var adventurer_recruit_cost: int = 1
## 新游戏每个村庄初始生成的候选人数。
@export var adventurer_initial_count: int = 2
@export var adventurer_unit_config_id: String = "infantry_militia"

@export_category("Tax / AI")
@export var default_tax_base: int = 20
## AI 领主部队人数低于该值时尝试前往自有村庄征召采邑。
@export var ai_lord_recruit_threshold: int = 12


func sanitize() -> void:
	fief_group_size = maxi(1, fief_group_size)
	fief_max_stock = maxi(1, fief_max_stock)
	fief_initial_stock = clampi(fief_initial_stock, 0, fief_max_stock)
	fief_population_cost = maxi(0, fief_population_cost)
	fief_prosperity_cost = maxi(0, fief_prosperity_cost)
	population_min = maxi(0, population_min)
	prosperity_min = maxi(0, prosperity_min)
	prosperity_max = maxi(prosperity_min, prosperity_max)
	refill_base_interval = maxf(1.0, refill_base_interval)
	refill_population_reference = maxf(1.0, refill_population_reference)
	refill_prosperity_reference = maxf(1.0, refill_prosperity_reference)
	refill_population_factor_min = maxf(0.01, refill_population_factor_min)
	refill_population_factor_max = maxf(
		refill_population_factor_min, refill_population_factor_max
	)
	refill_prosperity_factor_min = maxf(0.01, refill_prosperity_factor_min)
	refill_prosperity_factor_max = maxf(
		refill_prosperity_factor_min, refill_prosperity_factor_max
	)
	adventurer_max_candidates = maxi(0, adventurer_max_candidates)
	adventurer_refresh_interval = maxf(1.0, adventurer_refresh_interval)
	adventurer_recruit_cost = maxi(0, adventurer_recruit_cost)
	adventurer_initial_count = clampi(
		adventurer_initial_count, 0, adventurer_max_candidates
	)
	default_tax_base = maxi(0, default_tax_base)
	ai_lord_recruit_threshold = maxi(1, ai_lord_recruit_threshold)
