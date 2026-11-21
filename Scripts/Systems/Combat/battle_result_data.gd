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
## party_id -> 阵亡/存活人数
var casualties: Dictionary = {}
var survivors: Dictionary = {}

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
		"survivors": survivors.duplicate(true),
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
