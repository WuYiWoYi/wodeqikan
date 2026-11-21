class_name BattleParticipant
extends RefCounted
## 一次战斗中的单个参战部队。
##
## 只保存战斗内的归属与状态，不替代 PartyData。
## side_index 相同视为同一战斗侧，同侧单位不会互相攻击。

enum Status {
	ACTIVE,
	DEFEATED,
	WITHDRAWN,
}

var party_id: String = ""
var faction_id: String = ""
var side_index: int = 0
var joined_at_world_seconds: float = 0.0
var status: Status = Status.ACTIVE
