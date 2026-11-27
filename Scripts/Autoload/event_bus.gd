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
## 部队真正到达大地图移动/跟随目标的事实；旧目标被替换后不会补发。
signal party_arrived(party_id: String)
signal party_battle_state_changed(party_id: String, battle_state: int)
## 玩家阵营关系发生变化（主动宣战、王国战争、家族归属等）。
## 只表示事实；大地图据此刷新部队外环与建筑名称底板颜色，不携带关系数据。
signal faction_relations_changed()
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
## 近战攻击动作开始（含空挥）；音效等表现可据此触发挥击反馈。
## 此时尚未结算伤害，有效帧由 UnitController 单独处理。
signal unit_attack_started(unit_id: String, party_id: String)
## 单位实际受到伤害后广播；killed 表示本次伤害使其失去战斗能力。
## 只在真实扣血后发出，未命中/0 伤害不会触发。
signal unit_hit(
	unit_id: String,
	party_id: String,
	attacker_unit_id: String,
	damage: int,
	killed: bool
)
## 单位进入/刷新受击僵直；duration 为本次刷新的统一僵直时长。
signal unit_staggered(unit_id: String, party_id: String, duration: float)

## 封地征召成功的事实。招募方、村庄与组数由业务接口产生，不来自按钮本身。
signal fief_recruited(
	recruiter_party_id: String,
	settlement_id: String,
	groups: int,
	is_player_recruiter: bool
)
## 普通冒险者被玩家招募成功的事实。
signal adventurer_recruited(settlement_id: String, unit_id: String, unit_name: String)
## 玩家或 NPC 在村庄招募冒险者成功的事实；counts 为 { config_id: 数量 }。
## 大地图据此显示统一的浮动提示，不在 UI 里推断招募结果。
signal adventurers_recruited(
	party_id: String,
	settlement_id: String,
	counts: Dictionary,
	total: int,
	is_player_recruiter: bool
)

## 酒馆雇佣兵被玩家或 NPC 招募成功；记录已从可招募池删除。
signal mercenary_recruited(
	settlement_id: String,
	party_id: String,
	mercenary_id: String,
	unit_id: String,
	unit_name: String,
	is_player_recruiter: bool
)

## 阶段 12：部队每日补给状态发生变化（只在低补给状态切换时广播）。
signal party_supply_changed(party_id: String, is_food_low: bool, is_fodder_low: bool)
## NPC 部队在市场中完成一次补给采购；只包含实际购买数量。
signal npc_supply_purchased(party_id: String, bread_count: int, fodder_count: int)
