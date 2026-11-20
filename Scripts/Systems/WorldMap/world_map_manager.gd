class_name WorldMapManager
extends RefCounted
## 大地图坐标、移动与视野的统一处理者。
##
## 只修改 PartyData 的大地图字段；不创建图标、不操作 UI。
## 视觉节点读取数据并在 _process 中插值。

const ARRIVAL_RADIUS: float = 2.0

var world_bounds: Rect2 = Rect2()
var _party_manager: PartyManager = null


func setup(party_manager: PartyManager) -> void:
	_party_manager = party_manager


func set_party_target(party_id: String, target: Vector2) -> bool:
	if _party_manager == null:
		return false
	var party := _party_manager.get_party(party_id)
	if party == null or not party.is_available_for_world():
		return false

	party.target_position = _clamp_to_world(target)
	party.current_order = PartyData.OrderType.MOVE
	party.movement_state = PartyData.MovementState.MOVING
	return true


## 仅由 WorldSimulation 在 world_tick 中调用。
func update_party_movement(fixed_delta: float) -> void:
	if _party_manager == null:
		return

	for party in _party_manager.get_all_parties():
		if party == null or not party.is_available_for_world():
			continue
		if party.movement_state != PartyData.MovementState.MOVING:
			continue
		if party.movement_speed <= 0.0:
			continue

		var to_target: Vector2 = party.target_position - party.world_position
		var distance: float = to_target.length()
		if distance <= ARRIVAL_RADIUS:
			party.world_position = party.target_position
			party.movement_state = PartyData.MovementState.IDLE
			party.current_order = PartyData.OrderType.NONE
			EventBus.party_position_changed.emit(party.party_id)
			continue

		var step_distance: float = minf(party.movement_speed * fixed_delta, distance)
		var next_position := party.world_position + to_target.normalized() * step_distance
		party.world_position = _clamp_to_world(next_position)
		EventBus.party_position_changed.emit(party.party_id)


func stop_party(party_id: String) -> bool:
	if _party_manager == null:
		return false
	var party := _party_manager.get_party(party_id)
	if party == null:
		return false
	party.target_position = party.world_position
	party.movement_state = PartyData.MovementState.IDLE
	party.current_order = PartyData.OrderType.NONE
	return true


func update_visibility() -> void:
	# TODO(阶段2)：基于视野半径计算玩家可见部队集合与发现/离开事件。
	pass


func _clamp_to_world(position: Vector2) -> Vector2:
	if world_bounds.size == Vector2.ZERO:
		return position
	var clamped := position
	clamped.x = clampf(clamped.x, world_bounds.position.x, world_bounds.end.x)
	clamped.y = clampf(clamped.y, world_bounds.position.y, world_bounds.end.y)
	return clamped
