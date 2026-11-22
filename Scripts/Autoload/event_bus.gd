extends Node
## 跨系统事件总线（Autoload：EventBus）。
##
## 约定：
## - 只广播“已经发生的事实”，不用于请求-响应；
## - 事件参数只传实体 ID、基础类型或数据对象，不传场景节点；
## - 新增/删除信号必须同步更新 Docs/01_Core_Architecture.md 的事件契约表。
##
## 注意：本脚本是 Autoload，不使用 class_name，避免与全局单例名冲突。

signal game_state_changed(new_state: int)
signal game_session_started()
signal game_session_ended()

signal party_position_changed(party_id: String)
signal party_battle_state_changed(party_id: String, battle_state: int)
signal settlement_interaction_requested(settlement_id: String)
## 玩家实际进入/离开小场景的事实，供世界日志等系统消费。
signal settlement_entered(settlement_id: String, party_id: String)
signal settlement_exited(settlement_id: String, party_id: String)

signal battle_started(battle_id: String)
signal battle_finished(battle_id: String, result: int)
signal battle_participant_joined(battle_id: String, party_id: String, side_index: int)
## 增援部队已加入既有战斗。noble_id 可能为空（无贵族的普通部队）。
signal party_reinforced(
	battle_id: String, party_id: String, noble_id: String, side_index: int
)
## 离屏战斗完成一次小时结算后广播，供大地图战斗面板刷新存活人数。
signal battle_participants_updated(battle_id: String)
signal player_encounter_requested(
	encounter_id: String, attacker_party_id: String, target_party_id: String
)
signal player_battle_interaction_requested(interaction_id: String, battle_id: String)
signal unit_died(unit_id: String, party_id: String)

## 封地征召成功的事实。招募方、村庄与组数由业务接口产生，不来自按钮本身。
signal fief_recruited(
	recruiter_party_id: String,
	settlement_id: String,
	groups: int,
	is_player_recruiter: bool
)
## 普通冒险者被玩家招募成功的事实。
signal adventurer_recruited(settlement_id: String, unit_id: String, unit_name: String)
