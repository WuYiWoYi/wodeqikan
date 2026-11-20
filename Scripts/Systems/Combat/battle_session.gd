class_name BattleSession
extends RefCounted
## 一次战斗的临时数据容器。
##
## 不替代 UnitData / PartyData；初始版本不支持战斗中存档。

enum Status {
	PREPARING,
	ACTIVE,
	ENDED,
}

enum BattleResult {
	UNDECIDED,
	ATTACKER_VICTORY,
	DEFENDER_VICTORY,
	DRAW,
	ABORTED,
}

var battle_id: String = ""
var world_position: Vector2 = Vector2.ZERO

var attacker_party_ids: Array[String] = []
var defender_party_ids: Array[String] = []
var reinforcement_party_ids: Array[String] = []

## 双方参战单位 ID，顺序与生成顺序一致。
var attacker_unit_ids: Array[String] = []
var defender_unit_ids: Array[String] = []

## 双方阵营，用于战斗场景显示与后续阵营规则。
var attacker_faction_id: String = ""
var defender_faction_id: String = ""

## unit_id -> BattleUnitState
var unit_states: Dictionary = {}

var status: Status = Status.PREPARING
var result: BattleResult = BattleResult.UNDECIDED


func add_unit_state(state: BattleUnitState) -> void:
	if state == null or state.unit_id.is_empty():
		return
	unit_states[state.unit_id] = state


func get_unit_state(unit_id: String) -> BattleUnitState:
	return unit_states.get(unit_id) as BattleUnitState


func is_party_involved(party_id: String) -> bool:
	return (
		attacker_party_ids.has(party_id)
		or defender_party_ids.has(party_id)
		or reinforcement_party_ids.has(party_id)
	)


func is_attacker_party(party_id: String) -> bool:
	return attacker_party_ids.has(party_id)


func get_party_unit_ids(party_id: String) -> Array[String]:
	if attacker_party_ids.has(party_id):
		return attacker_unit_ids.duplicate()
	if defender_party_ids.has(party_id):
		return defender_unit_ids.duplicate()
	return []


func get_all_unit_ids() -> Array[String]:
	var unit_ids: Array[String] = []
	unit_ids.append_array(attacker_unit_ids)
	unit_ids.append_array(defender_unit_ids)
	return unit_ids
