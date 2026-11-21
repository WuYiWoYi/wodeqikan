class_name PartyData
extends RefCounted
## 大地图部队的持久化运行时数据。
##
## 部队是大地图的基本移动实体；成员归属以 UnitData.current_party_id
## 与 PartyData.member_unit_ids 双向一致，修改必须统一经过 PartyManager。

enum BattleState {
	AVAILABLE,
	IN_BATTLE,
	RETURNING,
	DISABLED,
}

enum MovementState {
	IDLE,
	MOVING,
}

enum OrderType {
	NONE,
	MOVE,
	HOLD,
	INTERACT,
	BATTLE,
	FOLLOW_PARTY,
}

enum PartyAIType {
	NONE,
	TRADE_ROUTE,
	PATROL,
	BANDIT,
	GUARD,
}

var party_id: String = ""
var party_name: String = ""
var faction_id: String = ""
var leader_lord_id: String = ""

var world_position: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO
var movement_speed: float = 10.0
var sight_range: float = 40.0

var member_unit_ids: Array[String] = []
var current_order: OrderType = OrderType.NONE
var current_target_id: String = ""
var movement_state: MovementState = MovementState.IDLE
var battle_state: BattleState = BattleState.AVAILABLE

## 大地图 AI 行为。ai_route_index 表示下一步要前往的路线点索引。
## 商队路线使用 stable settlement_id；巡逻路线点由 AIManager 按类型提供。
var ai_type: PartyAIType = PartyAIType.NONE
var ai_route_index: int = 0
var ai_route_settlement_ids: Array[String] = []

## 运行时攻击/拦截意图，不进入存档；由 AIManager 维护，供大地图遭遇判定使用。
var attack_intent: bool = false

## 玩家主动追逐/接近的目标部队 ID，仅运行时使用，不进入存档。
## 非空时大地图不自动弹出村庄信息或无关部队对话，避免打断玩家追逐。
var focus_party_id: String = ""


func has_member(unit_id: String) -> bool:
	return member_unit_ids.has(unit_id)


func is_available_for_world() -> bool:
	return battle_state == BattleState.AVAILABLE


func to_dict() -> Dictionary:
	return {
		"party_id": party_id,
		"party_name": party_name,
		"faction_id": faction_id,
		"leader_lord_id": leader_lord_id,
		"world_position": [world_position.x, world_position.y],
		"target_position": [target_position.x, target_position.y],
		"movement_speed": movement_speed,
		"sight_range": sight_range,
		"member_unit_ids": member_unit_ids.duplicate(),
		"current_order": int(current_order),
		"current_target_id": current_target_id,
		"movement_state": int(movement_state),
		"battle_state": int(battle_state),
		"ai_type": int(ai_type),
		"ai_route_index": ai_route_index,
		"ai_route_settlement_ids": ai_route_settlement_ids.duplicate(),
	}


static func from_dict(data: Dictionary) -> PartyData:
	var party := PartyData.new()
	party.party_id = str(data.get("party_id", ""))
	party.party_name = str(data.get("party_name", ""))
	party.faction_id = str(data.get("faction_id", ""))
	party.leader_lord_id = str(data.get("leader_lord_id", ""))
	party.world_position = _read_vector2(data.get("world_position", []))
	party.target_position = _read_vector2(data.get("target_position", []))
	party.movement_speed = float(data.get("movement_speed", 10.0))
	party.sight_range = float(data.get("sight_range", 40.0))
	party.current_order = int(data.get("current_order", OrderType.NONE)) as OrderType
	party.current_target_id = str(data.get("current_target_id", ""))
	party.movement_state = int(
		data.get("movement_state", MovementState.IDLE)
	) as MovementState
	party.battle_state = int(data.get("battle_state", BattleState.AVAILABLE)) as BattleState

	var member_values: Variant = data.get("member_unit_ids", [])
	if member_values is Array:
		for value: Variant in member_values:
			party.member_unit_ids.append(str(value))

	var ai_value: int = int(data.get("ai_type", PartyAIType.NONE))
	if ai_value < PartyAIType.NONE or ai_value > PartyAIType.GUARD:
		ai_value = PartyAIType.NONE
	party.ai_type = ai_value as PartyAIType
	party.ai_route_index = maxi(0, int(data.get("ai_route_index", 0)))

	var route_values: Variant = data.get("ai_route_settlement_ids", [])
	if route_values is Array:
		for value: Variant in route_values:
			party.ai_route_settlement_ids.append(str(value))

	return party


static func _read_vector2(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		var values: Array = value
		return Vector2(float(values[0]), float(values[1]))
	return Vector2.ZERO
