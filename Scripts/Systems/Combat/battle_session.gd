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
