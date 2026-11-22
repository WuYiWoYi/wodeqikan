class_name BattleResultData
extends RefCounted
## 一场战斗的最终/预览结果。
##
## 屏幕战斗、离屏战斗与玩家中途参战的战斗共用本结构。
## 预览结果用于结果面板；finish_battle() 会生成并保存 finalized 结果。
## 结果对象在 finalized 后不再修改。

enum EndReason {
	UNDECIDED,
	ANNIHILATION,
	RETREAT,
	DRAW,
	ABORTED,
}

var battle_id: String = ""
## 与 BattleSession.BattleResult 的整数值对应，避免跨类循环依赖。
var result_code: int = 0
var winning_side_index: int = -1
var losing_side_indices: Array[int] = []
var retreated_side_indices: Array[int] = []
var player_side_index: int = -1
var player_won: bool = false

## { side_index: Array[String] }
var side_party_ids: Dictionary = {}
## 每个参战部队的快照：party_id / faction_id / side_index / status。
var participants: Array[Dictionary] = []
## party_id -> 永久阵亡 / 伤兵 / 存活人数。
## casualties 只统计永久死亡，伤兵单独记录，仍留在原部队。
var casualties: Dictionary = {}
var wounded: Dictionary = {}
var survivors: Dictionary = {}

## 阶段 13：可分配俘虏（战败方伤兵）与胜利方分配结果。
## 个体顺序稳定，分配结果只由 battle_id 与真实参战记录决定。
var prisoner_pool: Array[String] = []
## party_id -> Array[String]；所有胜利部队分配到的俘虏个体。
var prisoner_allocations: Dictionary = {}
## party_id -> 有效参战人数（实际加入本场战斗的单位，含增援）。
var participant_unit_counts: Dictionary = {}
## 玩家部队的俘虏是否已经确认提交；防止战后界面重复结算。
var player_prisoners_committed: bool = false
## 参战人数总和为 0 时的异常标记；此时按稳定顺序兜底分配。
var prisoner_allocation_degraded: bool = false

## unit_id -> 获得经验；party_id -> 该部队总经验。
var exp_gained_by_unit: Dictionary = {}
var exp_gained_by_party: Dictionary = {}
var player_exp_gained: int = 0

var reward_gold: int = 0
var reward_items: Array[String] = []

var end_reason: EndReason = EndReason.UNDECIDED
var player_involved: bool = false
var result_time: float = 0.0
var finalized: bool = false


func get_party_casualties(party_id: String) -> int:
	return int(casualties.get(party_id, 0))


func get_party_survivors(party_id: String) -> int:
	return int(survivors.get(party_id, 0))


func get_party_wounded(party_id: String) -> int:
	return int(wounded.get(party_id, 0))


func get_side_party_ids(side_index: int) -> Array[String]:
	var ids := side_party_ids.get(side_index, []) as Array[String]
	return ids.duplicate()


func get_side_casualties(side_index: int) -> int:
	var total: int = 0
	for party_id: String in get_side_party_ids(side_index):
		total += get_party_casualties(party_id)
	return total


func get_side_survivors(side_index: int) -> int:
	var total: int = 0
	for party_id: String in get_side_party_ids(side_index):
		total += get_party_survivors(party_id)
	return total


## 指定部队在本场战斗分配到的俘虏 ID 副本。
func get_prisoners_for_party(party_id: String) -> Array[String]:
	var ids: Array[String] = []
	var raw: Variant = prisoner_allocations.get(party_id, [])
	if raw is Array:
		for value: Variant in raw:
			ids.append(str(value))
	return ids


func get_total_prisoners() -> int:
	return prisoner_pool.size()


func get_participant_unit_count(party_id: String) -> int:
	return int(participant_unit_counts.get(party_id, 0))


func get_side_wounded(side_index: int) -> int:
	var total: int = 0
	for party_id: String in get_side_party_ids(side_index):
		total += get_party_wounded(party_id)
	return total


func end_reason_text() -> String:
	match end_reason:
		EndReason.ANNIHILATION:
			return "一方失去全部战斗能力"
		EndReason.RETREAT:
			return "主动撤退"
		EndReason.DRAW:
			return "平局"
		EndReason.ABORTED:
			return "战斗中止"
		_:
			return "未结算"


func to_dict() -> Dictionary:
	return {
		"battle_id": battle_id,
		"result_code": result_code,
		"winning_side_index": winning_side_index,
		"losing_side_indices": losing_side_indices.duplicate(),
		"retreated_side_indices": retreated_side_indices.duplicate(),
		"player_side_index": player_side_index,
		"player_won": player_won,
		"side_party_ids": side_party_ids.duplicate(true),
		"participants": participants.duplicate(true),
		"casualties": casualties.duplicate(true),
		"wounded": wounded.duplicate(true),
		"survivors": survivors.duplicate(true),
		"prisoner_pool": prisoner_pool.duplicate(),
		"prisoner_allocations": prisoner_allocations.duplicate(true),
		"participant_unit_counts": participant_unit_counts.duplicate(true),
		"player_prisoners_committed": player_prisoners_committed,
		"prisoner_allocation_degraded": prisoner_allocation_degraded,
		"exp_gained_by_unit": exp_gained_by_unit.duplicate(true),
		"exp_gained_by_party": exp_gained_by_party.duplicate(true),
		"player_exp_gained": player_exp_gained,
		"reward_gold": reward_gold,
		"reward_items": reward_items.duplicate(),
		"end_reason": int(end_reason),
		"player_involved": player_involved,
		"result_time": result_time,
		"finalized": finalized,
	}
