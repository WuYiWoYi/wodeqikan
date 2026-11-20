class_name AIManager
extends RefCounted
## AI 决策调度器。
##
## 三层决策频率：
## - 单位实时行为：小场景物理帧，由 UnitController/UnitAI 自行处理；
## - 部队战术决策：每个 PARTY_DECISION_INTERVAL 世界秒；
## - 领主战略决策：每个 LORD_DECISION_INTERVAL 世界秒。
##
## 禁止在渲染帧中扫描全部部队/领主做决策。

const PARTY_DECISION_INTERVAL: float = 1.0
const LORD_DECISION_INTERVAL: float = 30.0

var _unit_manager: UnitManager = null
var _party_manager: PartyManager = null
var _party_timer: float = 0.0
var _lord_timer: float = 0.0


func setup(unit_manager: UnitManager, party_manager: PartyManager) -> void:
	_unit_manager = unit_manager
	_party_manager = party_manager


func tick(world_delta: float) -> void:
	if _party_manager == null:
		return

	_party_timer += world_delta
	_lord_timer += world_delta

	if _party_timer >= PARTY_DECISION_INTERVAL:
		# 不补跑错过的时间桶，避免卡顿后集中决策。
		_party_timer = fmod(_party_timer, PARTY_DECISION_INTERVAL)
		_tick_party_tactical()

	if _lord_timer >= LORD_DECISION_INTERVAL:
		_lord_timer = fmod(_lord_timer, LORD_DECISION_INTERVAL)
		_tick_lord_strategic()


func _tick_party_tactical() -> void:
	# TODO(阶段5)：对可用部队做附近威胁评估、目标选择与移动/撤退指令。
	pass


func _tick_lord_strategic() -> void:
	# TODO(阶段5)：领主招募、驻防、参战与撤退等战略决策。
	pass
