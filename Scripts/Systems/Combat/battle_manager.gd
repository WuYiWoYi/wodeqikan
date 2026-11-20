class_name BattleManager
extends RefCounted
## 战斗会话与战斗结算的统一入口。
##
## 只负责战斗会话数据与部队锁定；场景加载通过 SceneManager，
## 大地图节点的展示由表现层自行订阅事件。

var current_battle: BattleSession = null

var _unit_manager: UnitManager = null
var _party_manager: PartyManager = null
var _id_generator: IdGenerator = null


func setup(unit_manager: UnitManager, party_manager: PartyManager, id_generator: IdGenerator) -> void:
	_unit_manager = unit_manager
	_party_manager = party_manager
	_id_generator = id_generator


func start_battle(
	_attacker_party_ids: Array[String],
	_defender_party_ids: Array[String],
	_world_position: Vector2
) -> BattleSession:
	# TODO(阶段4)：创建 BattleSession、把参战部队置为 IN_BATTLE、
	# 生成 BattleUnitState、切换 BattleScene、设置 TimeManager 战斗时间覆盖。
	push_warning("BattleManager.start_battle 尚未实现")
	return null


func add_reinforcement(_party_id: String, _battle_id: String) -> bool:
	# TODO(阶段6)：校验距离/阵营/加入条件后加入 BattleSession。
	return false


func finish_battle(_battle_id: String, _result: int) -> void:
	# TODO(阶段4)：结算 HP/死亡/经验/成员关系，解锁部队并返回大地图。
	pass
