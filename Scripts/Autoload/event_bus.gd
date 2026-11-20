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

signal battle_started(battle_id: String)
signal battle_finished(battle_id: String, result: int)
signal unit_died(unit_id: String, party_id: String)
