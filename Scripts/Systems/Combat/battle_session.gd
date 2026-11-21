class_name BattleSession
extends RefCounted
## 一次战斗的临时数据容器。
##
## 支持多个战斗侧：side_index 相同的部队互为友军，不同侧互为敌人。
## 不替代 UnitData / PartyData；战斗不进入存档。

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
	## 非 0/1 战斗侧获胜（多方战斗）。
	SIDE_VICTORY,
	## 玩家主动撤退 / 战斗侧撤退。
	RETREATED,
}

var battle_id: String = ""
var world_position: Vector2 = Vector2.ZERO

## 兼容旧双方流程：side 0 = attacker，side 1 = defender。
var attacker_party_ids: Array[String] = []
var defender_party_ids: Array[String] = []
var reinforcement_party_ids: Array[String] = []

var attacker_unit_ids: Array[String] = []
var defender_unit_ids: Array[String] = []

var attacker_faction_id: String = ""
var defender_faction_id: String = ""

## { party_id: BattleParticipant }
var participants: Dictionary = {}
## { side_index: Array[String] }
var side_party_ids: Dictionary = {}
## { side_index: Array[String] }
var side_unit_ids: Dictionary = {}

## unit_id -> BattleUnitState
var unit_states: Dictionary = {}

var status: Status = Status.PREPARING
var result: BattleResult = BattleResult.UNDECIDED
var winning_side_index: int = -1
## 结算后的统一结果；非 null 表示本场已结算，不得再次修改。
var final_result: BattleResultData = null
## 主动撤退的战斗侧。
var retreated_side_indices: Array[int] = []

## 离屏战斗不暂停世界，依靠计时自动结算；屏幕战斗会暂停世界并进入 BattleScene。
var offscreen: bool = false
var paused_world: bool = false
var player_involved: bool = false
var elapsed_world_seconds: float = 0.0
## 离屏战斗按世界时间累计，每满 1 个游戏小时结算一次伤亡。
var offscreen_settlement_accumulator: float = 0.0
var offscreen_settlements_done: int = 0
## 小数伤亡累计；避免小部队每小时被迫固定损失相同人数。
var offscreen_casualty_credit: Dictionary = {}

var _side_indices: Array[int] = []


func add_participant(
	party_id: String, faction_id: String, side_index: int
) -> BattleParticipant:
	if party_id.is_empty() or participants.has(party_id):
		return null
	var participant := BattleParticipant.new()
	participant.party_id = party_id
	participant.faction_id = faction_id
	participant.side_index = side_index
	participant.joined_at_world_seconds = elapsed_world_seconds
	participants[party_id] = participant

	if not _side_indices.has(side_index):
		_side_indices.append(side_index)
		_side_indices.sort()
		side_party_ids[side_index] = [] as Array[String]
		side_unit_ids[side_index] = [] as Array[String]
	(side_party_ids[side_index] as Array[String]).append(party_id)

	if side_index == 0:
		attacker_party_ids.append(party_id)
	elif side_index == 1:
		defender_party_ids.append(party_id)
	return participant


func get_participant(party_id: String) -> BattleParticipant:
	return participants.get(party_id) as BattleParticipant


func get_side_of_party(party_id: String) -> int:
	var participant := get_participant(party_id)
	return participant.side_index if participant != null else -1


func get_side_indices() -> Array[int]:
	return _side_indices.duplicate()


func get_side_count() -> int:
	return _side_indices.size()


func get_next_side_index() -> int:
	if _side_indices.is_empty():
		return 0
	return _side_indices[_side_indices.size() - 1] + 1


func get_side_party_ids(side_index: int) -> Array[String]:
	var ids := side_party_ids.get(side_index, []) as Array[String]
	return ids.duplicate()


func get_side_unit_ids(side_index: int) -> Array[String]:
	var ids := side_unit_ids.get(side_index, []) as Array[String]
	return ids.duplicate()


func get_all_party_ids() -> Array[String]:
	var ids: Array[String] = []
	for side_index: int in _side_indices:
		ids.append_array(get_side_party_ids(side_index))
	return ids


func get_all_unit_ids() -> Array[String]:
	var ids: Array[String] = []
	for side_index: int in _side_indices:
		ids.append_array(get_side_unit_ids(side_index))
	return ids


func add_unit_state(state: BattleUnitState) -> void:
	if state == null or state.unit_id.is_empty():
		return
	unit_states[state.unit_id] = state
	var participant := get_participant(state.party_id)
	if participant == null:
		return
	var side_index: int = participant.side_index
	if not side_unit_ids.has(side_index):
		side_unit_ids[side_index] = [] as Array[String]
	var ids := side_unit_ids[side_index] as Array[String]
	if not ids.has(state.unit_id):
		ids.append(state.unit_id)

	if side_index == 0:
		attacker_unit_ids.append(state.unit_id)
	elif side_index == 1:
		defender_unit_ids.append(state.unit_id)


func get_unit_state(unit_id: String) -> BattleUnitState:
	return unit_states.get(unit_id) as BattleUnitState


func is_party_involved(party_id: String) -> bool:
	return participants.has(party_id)


func is_attacker_party(party_id: String) -> bool:
	return get_side_of_party(party_id) == 0


## 返回指定部队自己的战斗单位 ID（不是整个战斗侧）。
func get_party_unit_ids(party_id: String) -> Array[String]:
	var unit_ids: Array[String] = []
	var side_index: int = get_side_of_party(party_id)
	if side_index < 0:
		return unit_ids
	for unit_id: String in get_side_unit_ids(side_index):
		var state := get_unit_state(unit_id)
		if state != null and state.party_id == party_id:
			unit_ids.append(unit_id)
	return unit_ids


func get_opposing_party_ids(side_index: int) -> Array[String]:
	var party_ids: Array[String] = []
	for other_side: int in _side_indices:
		if other_side != side_index:
			party_ids.append_array(get_side_party_ids(other_side))
	return party_ids
