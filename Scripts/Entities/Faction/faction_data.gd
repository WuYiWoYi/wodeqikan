class_name FactionData
extends RefCounted
## 阵营的持久化运行时数据。

var faction_id: String = ""
var display_name: String = ""
var color: Color = Color.WHITE
var is_player_faction: bool = false
## 外交关系：{ faction_id: 好感度 -100..100 }
var relations: Dictionary = {}


func get_relation(other_faction_id: String) -> int:
	return int(relations.get(other_faction_id, 0))


func set_relation(other_faction_id: String, value: int) -> void:
	relations[other_faction_id] = clampi(value, -100, 100)


func to_dict() -> Dictionary:
	return {
		"faction_id": faction_id,
		"display_name": display_name,
		"color": color.to_html(true),
		"is_player_faction": is_player_faction,
		"relations": relations.duplicate(true),
	}


static func from_dict(data: Dictionary) -> FactionData:
	var faction := FactionData.new()
	faction.faction_id = str(data.get("faction_id", ""))
	faction.display_name = str(data.get("display_name", ""))
	faction.color = Color.from_string(str(data.get("color", "#ffffffff")), Color.WHITE)
	faction.is_player_faction = bool(data.get("is_player_faction", false))

	var relations_value: Variant = data.get("relations", {})
	if relations_value is Dictionary:
		faction.relations = (relations_value as Dictionary).duplicate(true)
	return faction
