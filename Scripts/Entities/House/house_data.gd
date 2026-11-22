class_name HouseData
extends RefCounted
## 家族的持久化运行时数据。
##
## 家族由多个贵族组成，拥有自己的领袖、封地与王国归属。
## 家族不等同于王国，也不直接拥有贵族部队：
## - 贵族通过 noble.house_id 归属家族；
## - 封地通过 SettlementData.owner_house_id 归属家族；
## - 部队通过 noble.party_id 由贵族独立指挥。
##
## noble_ids / settlement_ids 是便于查询的登记列表，权威关系仍以
## 贵族与封地上的 ID 字段为准；HouseManager 负责保持一致。

var house_id: String = ""
var house_name: String = ""
## 家族领袖 NobleData.noble_id；必须属于本家族且存活。
var leader_noble_id: String = ""
var noble_ids: Array[String] = []
var settlement_ids: Array[String] = []
## 所属王国；空字符串表示独立家族。
var kingdom_id: String = ""
## 上级统治家族；用于预留更细的封臣层级。
var overlord_house_id: String = ""
## 家族旗帜/徽章配置 ID。当前与 FamilyRegistry.family_id 对齐。
var banner_id: String = ""
var is_player_house: bool = false


func has_leader() -> bool:
	return not leader_noble_id.strip_edges().is_empty()


func has_kingdom() -> bool:
	return not kingdom_id.strip_edges().is_empty()


func has_noble(noble_id: String) -> bool:
	return noble_ids.has(noble_id)


func to_dict() -> Dictionary:
	return {
		"house_id": house_id,
		"house_name": house_name,
		"leader_noble_id": leader_noble_id,
		"noble_ids": noble_ids.duplicate(),
		"settlement_ids": settlement_ids.duplicate(),
		"kingdom_id": kingdom_id,
		"overlord_house_id": overlord_house_id,
		"banner_id": banner_id,
		"is_player_house": is_player_house,
	}


static func from_dict(data: Dictionary) -> HouseData:
	var house := HouseData.new()
	house.house_id = str(data.get("house_id", ""))
	house.house_name = str(data.get("house_name", ""))
	house.leader_noble_id = str(data.get("leader_noble_id", ""))
	house.kingdom_id = str(data.get("kingdom_id", ""))
	house.overlord_house_id = str(data.get("overlord_house_id", ""))
	house.banner_id = str(data.get("banner_id", ""))
	house.is_player_house = bool(data.get("is_player_house", false))

	var noble_values: Variant = data.get("noble_ids", [])
	if noble_values is Array:
		for value: Variant in noble_values:
			var noble_id: String = str(value)
			if not noble_id.is_empty() and not house.noble_ids.has(noble_id):
				house.noble_ids.append(noble_id)

	var settlement_values: Variant = data.get("settlement_ids", [])
	if settlement_values is Array:
		for value: Variant in settlement_values:
			var settlement_id: String = str(value)
			if not settlement_id.is_empty() and not house.settlement_ids.has(settlement_id):
				house.settlement_ids.append(settlement_id)
	return house
