class_name LordData
extends RefCounted
## 领主的持久化运行时数据。
##
## 领主是战略层决策主体；实际移动与战斗由所属 Party 执行。
## 领主身份（is_player_lord）与玩家角色（UnitData.is_player_character）是两个概念：
## 前者表示封地所有权与战略决策身份，后者表示小地图/战斗中由玩家操作的单位。

var lord_id: String = ""
var display_name: String = ""
var faction_id: String = ""
## 所属部队；一个领主的所属部队必须唯一。
var party_id: String = ""
## 玩家控制的领主身份；用于封地征召权限判断。
var is_player_lord: bool = false

## 性格/目标/状态使用字符串 ID，由 Data 配置定义，便于扩展而不改代码。
var personality_id: String = ""
var current_goal: String = ""
var current_state: String = ""
## 当前战略目标地点（例如前往自有村庄征召采邑）。
var current_target_settlement_id: String = ""

## 对其他领主的个人关系：{ lord_id: -100..100 }
var relationships: Dictionary = {}
var is_alive: bool = true


func get_relationship(other_lord_id: String) -> int:
	return int(relationships.get(other_lord_id, 0))


func set_relationship(other_lord_id: String, value: int) -> void:
	relationships[other_lord_id] = clampi(value, -100, 100)


func to_dict() -> Dictionary:
	return {
		"lord_id": lord_id,
		"display_name": display_name,
		"faction_id": faction_id,
		"party_id": party_id,
		"is_player_lord": is_player_lord,
		"personality_id": personality_id,
		"current_goal": current_goal,
		"current_state": current_state,
		"current_target_settlement_id": current_target_settlement_id,
		"relationships": relationships.duplicate(true),
		"is_alive": is_alive,
	}


static func from_dict(data: Dictionary) -> LordData:
	var lord := LordData.new()
	lord.lord_id = str(data.get("lord_id", ""))
	lord.display_name = str(data.get("display_name", ""))
	lord.faction_id = str(data.get("faction_id", ""))
	lord.party_id = str(data.get("party_id", ""))
	lord.is_player_lord = bool(data.get("is_player_lord", false))
	lord.personality_id = str(data.get("personality_id", ""))
	lord.current_goal = str(data.get("current_goal", ""))
	lord.current_state = str(data.get("current_state", ""))
	lord.current_target_settlement_id = str(
		data.get("current_target_settlement_id", "")
	)
	lord.is_alive = bool(data.get("is_alive", true))

	var relationships_value: Variant = data.get("relationships", {})
	if relationships_value is Dictionary:
		lord.relationships = (relationships_value as Dictionary).duplicate(true)
	return lord
