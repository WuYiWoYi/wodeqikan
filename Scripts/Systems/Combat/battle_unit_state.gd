class_name BattleUnitState
extends RefCounted
## 战斗期间单个单位的临时权威状态。
##
## 战斗结束后由 BattleManager 统一写回 UnitData；战斗期间世界侧不得修改 battle_hp。

var unit_id: String = ""
var party_id: String = ""
var battle_hp: int = 0
var alive: bool = true
## 结算前的负伤判定结果；每场战斗只判定一次，预览与最终结算共用。
var wounded: bool = false
var wounded_decided: bool = false
var battle_position: Vector2 = Vector2.ZERO
## 增援标记只影响表现层出生位置与提示，不改变单位属性或战斗规则。
var is_reinforcement: bool = false
var reinforcement_battle_id: String = ""
var reinforcement_arrival_time: float = 0.0
