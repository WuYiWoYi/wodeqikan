class_name KingdomData
extends RefCounted
## 王国的持久化运行时数据。
##
## 王国由统治家族与若干附庸家族组成：
## - ruling_house_id 是唯一统治家族；
## - king_noble_id 必须是统治家族的领袖；
## - vassal_house_ids 只保存附庸家族，统治家族不重复列入；
## - enemy_kingdom_ids 表示正在交战的王国。
##
## 本阶段只建立数据与查询接口，不实现建立王国的操作流程、宣战/停战 UI。

var kingdom_id: String = ""
var kingdom_name: String = ""
var ruling_house_id: String = ""
var king_noble_id: String = ""
var vassal_house_ids: Array[String] = []
var enemy_kingdom_ids: Array[String] = []
var kingdom_color: Color = Color.WHITE
## 失去有效统治家族/国王时置为 false，等待后续政治流程处理。
var is_active: bool = true


func has_vassal(house_id: String) -> bool:
	return vassal_house_ids.has(house_id)


func is_at_war_with(other_kingdom_id: String) -> bool:
	return enemy_kingdom_ids.has(other_kingdom_id)


func get_all_house_ids() -> Array[String]:
	var result: Array[String] = []
	if not ruling_house_id.is_empty():
		result.append(ruling_house_id)
	for house_id: String in vassal_house_ids:
		if not result.has(house_id):
			result.append(house_id)
	return result


func to_dict() -> Dictionary:
	return {
		"kingdom_id": kingdom_id,
		"kingdom_name": kingdom_name,
		"ruling_house_id": ruling_house_id,
		"king_noble_id": king_noble_id,
		"vassal_house_ids": vassal_house_ids.duplicate(),
		"enemy_kingdom_ids": enemy_kingdom_ids.duplicate(),
		"kingdom_color": kingdom_color.to_html(true),
		"is_active": is_active,
	}


static func from_dict(data: Dictionary) -> KingdomData:
	var kingdom := KingdomData.new()
	kingdom.kingdom_id = str(data.get("kingdom_id", ""))
	kingdom.kingdom_name = str(data.get("kingdom_name", ""))
	kingdom.ruling_house_id = str(data.get("ruling_house_id", ""))
	kingdom.king_noble_id = str(data.get("king_noble_id", ""))
	kingdom.kingdom_color = Color.from_string(
		str(data.get("kingdom_color", "#ffffffff")), Color.WHITE
	)
	kingdom.is_active = bool(data.get("is_active", true))

	var vassal_values: Variant = data.get("vassal_house_ids", [])
	if vassal_values is Array:
		for value: Variant in vassal_values:
			var house_id: String = str(value)
			if not house_id.is_empty() and not kingdom.vassal_house_ids.has(house_id):
				kingdom.vassal_house_ids.append(house_id)

	var enemy_values: Variant = data.get("enemy_kingdom_ids", [])
	if enemy_values is Array:
		for value: Variant in enemy_values:
			var enemy_id: String = str(value)
			if not enemy_id.is_empty() and not kingdom.enemy_kingdom_ids.has(enemy_id):
				kingdom.enemy_kingdom_ids.append(enemy_id)
	return kingdom
