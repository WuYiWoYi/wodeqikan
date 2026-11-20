class_name WorldSimulation
extends RefCounted
## 世界模拟调度器：只消费 TimeManager 的固定步长 tick，按固定顺序推进数据。
##
## 本类不依赖场景节点，因此大地图场景未加载时世界仍然可以运行。

var _unit_manager: UnitManager = null
var _party_manager: PartyManager = null
var _world_map_manager: WorldMapManager = null
var _ai_manager: AIManager = null


func bind(
	unit_manager: UnitManager,
	party_manager: PartyManager,
	world_map_manager: WorldMapManager,
	ai_manager: AIManager
) -> void:
	_unit_manager = unit_manager
	_party_manager = party_manager
	_world_map_manager = world_map_manager
	_ai_manager = ai_manager


func on_world_tick(fixed_delta: float) -> void:
	if _party_manager == null or _world_map_manager == null or _ai_manager == null:
		return

	# 固定顺序：移动 -> 视野/遭遇 -> AI 决策 -> 地点模拟（阶段 5 接入）。
	_world_map_manager.update_party_movement(fixed_delta)
	_world_map_manager.update_visibility()
	_ai_manager.tick(fixed_delta)
