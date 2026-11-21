class_name SettlementData
extends RefCounted
## 村庄、城镇、城堡的持久化运行时数据。

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
## 地点所属家族（持久化）；仅用于地图名称旁的家族旗帜，不影响外交。
var family_id: String = ""
var owner_lord_id: String = ""

## 该地点对应的小场景路径。空字符串表示使用村庄/城镇/城堡的默认模板。
## 初期所有村庄共用同一个基础场景，后续可逐村替换。
var scene_path: String = ""

var population: int = 0
var prosperity: int = 0
var garrison_unit_ids: Array[String] = []
var is_under_siege: bool = false


func to_dict() -> Dictionary:
	return {
		"settlement_id": settlement_id,
		"display_name": display_name,
		"settlement_type": int(settlement_type),
		"world_position": [world_position.x, world_position.y],
		"faction_id": faction_id,
		"family_id": family_id,
		"owner_lord_id": owner_lord_id,
		"scene_path": scene_path,
		"population": population,
		"prosperity": prosperity,
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
	settlement.owner_lord_id = str(data.get("owner_lord_id", ""))
	settlement.scene_path = str(data.get("scene_path", ""))
	settlement.population = int(data.get("population", 0))
	settlement.prosperity = int(data.get("prosperity", 0))
	settlement.is_under_siege = bool(data.get("is_under_siege", false))

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
