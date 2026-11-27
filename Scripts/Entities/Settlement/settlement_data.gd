class_name SettlementData
extends RefCounted
## 村庄、城镇、城堡的持久化运行时数据。
##
## 封地所有权、人口、繁荣度、采邑储备与冒险者候选人都属于权威数据；
## 场景节点只负责显示，不持有唯一的游戏状态。

enum SettlementType {
	VILLAGE,
	TOWN,
	CASTLE,
}

var settlement_id: String = ""
var display_name: String = ""
var settlement_type: SettlementType = SettlementType.VILLAGE

var world_position: Vector2 = Vector2.ZERO
var faction_id: String = ""
## 地点旗帜/外观家族（持久化），与 FamilyRegistry.family_id 对齐。
## 政治归属以下方的 owner_house_id 为权威；family_id 只负责视觉身份。
var family_id: String = ""
## 直接拥有该地点的家族（HouseData.house_id）；空字符串表示无主。
## 这是领地所有权的唯一权威来源；家族领袖、爵位或个人身份变化不影响它。
var owner_house_id: String = ""
## 旧存档迁移输入：Schema v10 之前的个人所有者字段（owner_noble_id / owner_lord_id）。
## 读档后由 WorldContext 解析为贵族所属家族并清空，不作为任何现行所有权依据。
var _legacy_owner_noble_id: String = ""

## 该地点对应的小场景路径。空字符串表示使用村庄/城镇/城堡的默认模板。
## 初期所有村庄共用同一个基础场景，后续可逐村替换。
var scene_path: String = ""

var population: int = 0
var prosperity: int = 0

## 封地经济参数与缓存。tax_income_per_day 必须由 TaxCalculator 计算；
## 不允许 UI 或场景节点自行维护另一套税收公式。
var tax_base: int = 20
var tax_income_per_day: int = 0

## 采邑储备以“组”为单位；1 组固定生成 6 名士兵。
var fief_recruitment_stock: int = 0
var fief_recruitment_capacity: int = 4
## 距离下一次采邑补充的累计世界时间（秒）。
var fief_recruitment_elapsed: float = 0.0

## 当前村庄的普通冒险者候选人与距离下一次刷新的累计世界时间。
var adventurer_candidates: Array[AdventurerCandidateData] = []
var adventurer_refresh_elapsed: float = 0.0
## 贵族冒险者：每村最多 1 名，作为独立特殊候选人，不占用普通候选人上限。
## 一旦生成即置位 noble_adventurer_spawned；被招募后不会因读档重新生成。
var noble_adventurer_candidate: AdventurerCandidateData = null
var noble_adventurer_spawned: bool = false

var garrison_unit_ids: Array[String] = []
var is_under_siege: bool = false


func get_available_candidates() -> Array[AdventurerCandidateData]:
	var result: Array[AdventurerCandidateData] = []
	for candidate: AdventurerCandidateData in adventurer_candidates:
		if candidate != null and candidate.is_available():
			result.append(candidate)
	return result


## 候选人查询同时覆盖普通候选人与贵族冒险者；贵族冒险者只有 1 名。
func get_candidate(candidate_id: String) -> AdventurerCandidateData:
	for candidate: AdventurerCandidateData in adventurer_candidates:
		if candidate != null and candidate.candidate_id == candidate_id:
			return candidate
	if noble_adventurer_candidate != null \
			and noble_adventurer_candidate.candidate_id == candidate_id:
		return noble_adventurer_candidate
	return null


## 返回贵族冒险者候选人；已招募/未生成时返回 null。
func get_noble_adventurer_candidate() -> AdventurerCandidateData:
	return noble_adventurer_candidate


## 普通候选人与贵族冒险者的合并只读视图；UI 用来统一生成表现。
func get_all_adventurer_candidates() -> Array[AdventurerCandidateData]:
	var result: Array[AdventurerCandidateData] = []
	for candidate: AdventurerCandidateData in adventurer_candidates:
		if candidate != null:
			result.append(candidate)
	if noble_adventurer_candidate != null:
		result.append(noble_adventurer_candidate)
	return result


func has_owner() -> bool:
	return not owner_house_id.is_empty()


func to_dict() -> Dictionary:
	var candidates: Array[Dictionary] = []
	for candidate: AdventurerCandidateData in adventurer_candidates:
		if candidate != null:
			candidates.append(candidate.to_dict())
	return {
		"settlement_id": settlement_id,
		"display_name": display_name,
		"settlement_type": int(settlement_type),
		"world_position": [world_position.x, world_position.y],
		"faction_id": faction_id,
		"family_id": family_id,
		# 领地所有权只保存家族 ID；不再写出个人所有者字段。
		"owner_house_id": owner_house_id,
		"scene_path": scene_path,
		"population": population,
		"prosperity": prosperity,
		"tax_base": tax_base,
		"tax_income_per_day": tax_income_per_day,
		"fief_recruitment_stock": fief_recruitment_stock,
		"fief_recruitment_capacity": fief_recruitment_capacity,
		"fief_recruitment_elapsed": fief_recruitment_elapsed,
		"adventurer_candidates": candidates,
		"adventurer_refresh_elapsed": adventurer_refresh_elapsed,
		"noble_adventurer_candidate": (
			noble_adventurer_candidate.to_dict()
			if noble_adventurer_candidate != null else {}
		),
		"noble_adventurer_spawned": noble_adventurer_spawned,
		"garrison_unit_ids": garrison_unit_ids.duplicate(),
		"is_under_siege": is_under_siege,
	}


static func from_dict(data: Dictionary) -> SettlementData:
	var settlement := SettlementData.new()
	settlement.settlement_id = str(data.get("settlement_id", ""))
	settlement.display_name = str(data.get("display_name", ""))
	settlement.settlement_type = int(
		data.get("settlement_type", SettlementType.VILLAGE)
	) as SettlementType
	settlement.world_position = _read_vector2(data.get("world_position", []))
	settlement.faction_id = str(data.get("faction_id", ""))
	settlement.family_id = str(data.get("family_id", ""))
	settlement.owner_house_id = str(data.get("owner_house_id", ""))
	# 旧存档兼容：个人所有者只作为迁移输入，由 WorldContext 转成家族所有权。
	settlement._legacy_owner_noble_id = str(
		data.get("owner_noble_id", data.get("owner_lord_id", ""))
	)
	settlement.scene_path = str(data.get("scene_path", ""))
	settlement.population = maxi(0, int(data.get("population", 0)))
	settlement.prosperity = maxi(0, int(data.get("prosperity", 0)))
	settlement.tax_base = maxi(0, int(data.get("tax_base", 20)))
	settlement.tax_income_per_day = maxi(
		0, int(data.get("tax_income_per_day", 0))
	)
	settlement.fief_recruitment_capacity = maxi(
		0, int(data.get("fief_recruitment_capacity", 4))
	)
	settlement.fief_recruitment_stock = clampi(
		int(data.get("fief_recruitment_stock", 0)),
		0,
		settlement.fief_recruitment_capacity
	)
	settlement.fief_recruitment_elapsed = maxf(
		0.0, float(data.get("fief_recruitment_elapsed", 0.0))
	)
	settlement.adventurer_refresh_elapsed = maxf(
		0.0, float(data.get("adventurer_refresh_elapsed", 0.0))
	)
	settlement.is_under_siege = bool(data.get("is_under_siege", false))

	var candidate_values: Variant = data.get("adventurer_candidates", [])
	if candidate_values is Array:
		for value: Variant in candidate_values:
			if value is Dictionary:
				var candidate := AdventurerCandidateData.from_dict(value)
				if not candidate.candidate_id.is_empty():
					settlement.adventurer_candidates.append(candidate)

	# 旧存档没有贵族冒险者字段：保持未生成状态，由读档后的世界初始化补齐。
	var noble_value: Variant = data.get("noble_adventurer_candidate", {})
	if noble_value is Dictionary and not (noble_value as Dictionary).is_empty():
		var noble_candidate := AdventurerCandidateData.from_dict(
			noble_value as Dictionary
		)
		if not noble_candidate.candidate_id.is_empty():
			noble_candidate.is_noble = true
			settlement.noble_adventurer_candidate = noble_candidate
	settlement.noble_adventurer_spawned = bool(
		data.get(
			"noble_adventurer_spawned",
			settlement.noble_adventurer_candidate != null
		)
	)

	var garrison_values: Variant = data.get("garrison_unit_ids", [])
	if garrison_values is Array:
		for value: Variant in garrison_values:
			settlement.garrison_unit_ids.append(str(value))

	return settlement


static func _read_vector2(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		var values: Array = value
		return Vector2(float(values[0]), float(values[1]))
	return Vector2.ZERO
