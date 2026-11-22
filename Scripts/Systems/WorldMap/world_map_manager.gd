class_name WorldMapManager
extends RefCounted
## 大地图坐标、移动与跟随时目标的统一处理者。
##
## 只修改 PartyData 的大地图字段；不创建图标、不操作 UI。
## 视觉节点读取数据并在 _process 中插值。

const ARRIVAL_RADIUS: float = 2.0
## 大地图实际移动速度倍率。所有部队都经过 update_party_movement 的统一入口，
## 因此只在这里乘一次；PartyData.movement_speed 仍保存原始基础速度，
## 小地图/战斗移动完全不受影响。
const WORLD_MAP_SPEED_SCALE: float = 0.5
## 跟随目标位置的刷新间隔（世界秒），避免每个 tick 都重新寻路。
const FOLLOW_REFRESH_INTERVAL: float = 0.5
## 与跟随目标距离小于该值视为追上，结束跟随。
const FOLLOW_COMPLETE_RADIUS: float = 14.0

var world_bounds: Rect2 = Rect2()
var _party_manager: PartyManager = null
var _vision_manager: VisionManager = null
var _follow_timer: float = 0.0


func setup(party_manager: PartyManager, vision_manager: VisionManager = null) -> void:
	_party_manager = party_manager
	_vision_manager = vision_manager


func bind_vision(vision_manager: VisionManager) -> void:
	_vision_manager = vision_manager


func set_party_target(party_id: String, target: Vector2) -> bool:
	if _party_manager == null:
		return false
	var party := _party_manager.get_party(party_id)
	if party == null or not party.is_available_for_world():
		return false

	# 新移动指令覆盖跟随指令；AI 追击仍然是 MOVE，不受这里清除目标的影响。
	if party.current_order == PartyData.OrderType.FOLLOW_PARTY:
		party.current_target_id = ""
	party.target_position = _clamp_to_world(target)
	party.current_order = PartyData.OrderType.MOVE
	party.movement_state = PartyData.MovementState.MOVING
	return true


## 让 follower 持续追赶 target 的最新位置。
## 目标必须存在、可用、有存活成员。
## 跟随只由玩家主动点击地图部队触发：部队图标始终可见，
## 因此不要求目标处于观察者视野内，否则远距离点击只会走向旧坐标，
## 目标继续巡逻后就再也追不上（中立家族骑士等不会主动接近玩家）。
func set_party_follow(follower_id: String, target_id: String) -> bool:
	if _party_manager == null:
		return false
	var follower := _party_manager.get_party(follower_id)
	var target := _party_manager.get_party(target_id)
	if follower == null or target == null or follower_id == target_id:
		return false
	if not follower.is_available_for_world() or not target.is_available_for_world():
		return false
	if target.member_unit_ids.is_empty():
		return false

	follower.current_order = PartyData.OrderType.FOLLOW_PARTY
	follower.current_target_id = target_id
	follower.target_position = _clamp_to_world(target.world_position)
	follower.movement_state = PartyData.MovementState.MOVING
	return true


## 清除跟随指令；普通移动指令不受影响。
func cancel_follow(party_id: String) -> bool:
	if _party_manager == null:
		return false
	var party := _party_manager.get_party(party_id)
	if party == null or party.current_order != PartyData.OrderType.FOLLOW_PARTY:
		return false
	_clear_follow(party)
	return true


## 仅由 WorldSimulation 在 world_tick 中调用。
func update_party_movement(fixed_delta: float) -> void:
	if _party_manager == null:
		return

	_follow_timer += fixed_delta
	if _follow_timer >= FOLLOW_REFRESH_INTERVAL:
		_follow_timer = fmod(_follow_timer, FOLLOW_REFRESH_INTERVAL)
		_refresh_follow_targets()

	for party: PartyData in _party_manager.get_all_parties():
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
			if party.current_order == PartyData.OrderType.FOLLOW_PARTY:
				# 到达的是旧目标点：立即读取目标最新位置，避免每 0.5 秒停顿一次。
				if _refresh_follow_party(party):
					continue
				party.movement_state = PartyData.MovementState.IDLE
			else:
				party.movement_state = PartyData.MovementState.IDLE
				party.current_order = PartyData.OrderType.NONE
			EventBus.party_position_changed.emit(party.party_id)
			continue

		var step_distance: float = minf(
			get_effective_movement_speed(party) * fixed_delta, distance
		)
		var next_position := party.world_position + to_target.normalized() * step_distance
		party.world_position = _clamp_to_world(next_position)
		EventBus.party_position_changed.emit(party.party_id)


## 大地图实际速度（含统一倍率）。仅用于移动计算与测试展示；
## 不改写 PartyData.movement_speed，避免重复乘 0.5。
func get_effective_movement_speed(party: PartyData) -> float:
	if party == null:
		return 0.0
	return party.movement_speed * WORLD_MAP_SPEED_SCALE


func stop_party(party_id: String) -> bool:
	if _party_manager == null:
		return false
	var party := _party_manager.get_party(party_id)
	if party == null:
		return false
	party.target_position = party.world_position
	party.movement_state = PartyData.MovementState.IDLE
	party.current_order = PartyData.OrderType.NONE
	party.current_target_id = ""
	party.attack_intent = false
	party.battle_response_id = ""
	party.battle_response_until = 0.0
	return true


func update_visibility() -> void:
	# 视野由 VisionManager 按需查询；本处保留空实现以兼容既有 tick 顺序。
	pass


func _refresh_follow_targets() -> void:
	if _party_manager == null:
		return
	for party: PartyData in _party_manager.get_all_parties():
		if party == null or party.current_order != PartyData.OrderType.FOLLOW_PARTY:
			continue
		if not _refresh_follow_party(party):
			_clear_follow(party)


## 更新单个跟随者；仍可跟随返回 true，否则 false（由调用方决定清理）。
func _refresh_follow_party(party: PartyData) -> bool:
	if _party_manager == null or party == null:
		return false
	if party.current_order != PartyData.OrderType.FOLLOW_PARTY:
		return false
	if not party.is_available_for_world():
		return false

	var target := _party_manager.get_party(party.current_target_id)
	if target == null or target.party_id == party.party_id:
		return false
	if target.member_unit_ids.is_empty():
		return false
	# 目标正在离屏战斗中：保持追击关系但原地等待，战斗结束后自动恢复跟随。
	# 不能直接清除跟随指令，否则玩家追上后目标刚打完仗，双方会僵在原地。
	if not target.is_available_for_world():
		if target.battle_state == PartyData.BattleState.IN_BATTLE:
			party.movement_state = PartyData.MovementState.IDLE
			party.target_position = party.world_position
			return true
		return false
	# 玩家主动点击的追击不因目标离开视野而中断；地图图标始终可见，
	# 中断会让远距离点击巡逻部队时永远无法接触。

	if party.world_position.distance_to(target.world_position) <= FOLLOW_COMPLETE_RADIUS:
		return false

	party.target_position = _clamp_to_world(target.world_position)
	party.movement_state = PartyData.MovementState.MOVING
	return true


func _clear_follow(party: PartyData) -> void:
	party.target_position = party.world_position
	party.movement_state = PartyData.MovementState.IDLE
	party.current_order = PartyData.OrderType.NONE
	party.current_target_id = ""


func _clamp_to_world(position: Vector2) -> Vector2:
	if world_bounds.size == Vector2.ZERO:
		return position
	var clamped := position
	clamped.x = clampf(clamped.x, world_bounds.position.x, world_bounds.end.x)
	clamped.y = clampf(clamped.y, world_bounds.position.y, world_bounds.end.y)
	return clamped
