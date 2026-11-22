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
var owner_house_id: String = ""
## 实际代表家族管理封地的贵族（NobleData.noble_id）；可选。
var owner_noble_id: String = ""
## 旧字段别名：与 owner_noble_id 指向同一贵族，避免新旧所有权字段并存。
var owner_lord_id: String:
	get:
		return owner_noble_id
	set(value):
		owner_noble_id = value

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

## 当前村庄的冒险者候选人与距离下一次刷新的累计世界时间。
var adventurer_candidates: Array[AdventurerCandidateData] = []
var adventurer_refresh_elapsed: float = 0.0

var garrison_unit_ids: Array[String] = []
var is_under_siege: bool = false


func get_available_candidates() -> Array[AdventurerCandidateData]:
	var result: Array[AdventurerCandidateData] = []
	for candidate: AdventurerCandidateData in adventurer_candidates:
		if candidate != null and candidate.is_available():
			result.append(candidate)
	return result


func get_candidate(candidate_id: String) -> AdventurerCandidateData:
	for candidate: AdventurerCandidateData in adventurer_candidates:
		if candidate != null and candidate.candidate_id == candidate_id:
			return candidate
	return null


func has_owner() -> bool:
	return not owner_house_id.is_empty() or not owner_noble_id.is_empty()


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
		"owner_house_id": owner_house_id,
		"owner_noble_id": owner_noble_id,
		# 兼容旧读取方：所有权仍以 owner_noble_id 为唯一来源。
		"owner_lord_id": owner_noble_id,
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
	settlement.owner_house_id = str(
		data.get("owner_house_id", settlement.family_id)
	)
	settlement.owner_noble_id = str(
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
