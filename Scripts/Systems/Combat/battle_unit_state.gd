class_name BattleUnitState
extends RefCounted
## 战斗期间单个单位的临时权威状态。
##
## 战斗结束后由 BattleManager 统一写回 UnitData；战斗期间世界侧不得修改 battle_hp。

var unit_id: String = ""
var party_id: String = ""
var battle_hp: int = 0
var alive: bool = true
var battle_position: Vector2 = Vector2.ZERO
