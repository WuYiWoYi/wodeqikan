class_name UnitController
extends RefCounted
## 单个士兵的战斗行为控制：待机、移动、索敌、攻击、受伤与死亡。
##
## 属性全部来自 UnitData；战斗位置与 HP 写入 BattleUnitState。
## 本类不读取或修改 UnitData.current_hp，结算由 BattleManager 统一完成。

const RETARGET_INTERVAL: float = 0.3
const ARRIVAL_RADIUS: float = 4.0
const ATTACK_RADIUS_PADDING: float = 8.0
const AUTO_ACQUIRE_RANGE: float = 1000.0

var unit_id: String = ""
var party_id: String = ""
var is_player_side: bool = false
var actor: UnitActor = null
var unit_data: UnitData = null
var state: BattleUnitState = null
var battle_bounds: Rect2 = Rect2()

var _attack_cooldown: float = 0.0
var _retarget_timer: float = 0.0
var _target: UnitController = null
var _manual_move_target := Vector2.ZERO
var _has_manual_move: bool = false
var _alive: bool = true


func setup(
	data: UnitData,
	battle_state: BattleUnitState,
	player_side: bool,
	actor_node: UnitActor,
	bounds: Rect2
) -> void:
	unit_data = data
	state = battle_state
	is_player_side = player_side
	actor = actor_node
	battle_bounds = bounds
	unit_id = state.unit_id
	party_id = state.party_id
	_alive = state.alive and state.battle_hp > 0


func is_alive() -> bool:
	return (
		_alive
		and state != null
		and state.alive
		and state.battle_hp > 0
	)


func get_position() -> Vector2:
	return state.battle_position if state != null else Vector2.ZERO


func has_move_command() -> bool:
	return _has_manual_move


func command_move(target: Vector2) -> void:
	if not is_alive():
		return
	_manual_move_target = _clamp_to_bounds(target)
	_has_manual_move = true
	_target = null


func tick(delta: float, enemies: Array[UnitController]) -> void:
	if not is_alive():
		return
	if state.battle_hp <= 0:
		_die()
		return

	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)

	if _has_manual_move:
		if _move_toward(_manual_move_target, delta):
			_has_manual_move = false
		return

	_retarget_timer -= delta
	if _target == null or not _target.is_alive() or _retarget_timer <= 0.0:
		_target = _find_nearest_enemy(enemies)
		_retarget_timer = RETARGET_INTERVAL

	if _target == null:
		return

	var target_position := _target.get_position()
	var distance := state.battle_position.distance_to(target_position)
	if distance > unit_data.attack_range + ATTACK_RADIUS_PADDING:
		_move_toward(target_position, delta)
		return

	_face_towards(target_position)
	if _attack_cooldown <= 0.0:
		_target.apply_damage(maxi(1, unit_data.attack))
		_attack_cooldown = maxf(0.05, unit_data.attack_interval)


func apply_damage(amount: int) -> void:
	if not is_alive():
		return
	state.battle_hp = maxi(0, state.battle_hp - maxi(0, amount))
	if state.battle_hp <= 0:
		_die()


func _die() -> void:
	state.battle_hp = 0
	state.alive = false
	_alive = false
	_target = null
	_has_manual_move = false


## 返回是否已到达目标点。
func _move_toward(target: Vector2, delta: float) -> bool:
	var to_target := target - state.battle_position
	var distance := to_target.length()
	if distance <= ARRIVAL_RADIUS:
		return true
	var step: float = minf(unit_data.move_speed * delta, distance)
	state.battle_position = _clamp_to_bounds(
		state.battle_position + to_target.normalized() * step
	)
	_face_towards(target)
	return false


func _face_towards(target: Vector2) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	actor.set_facing(target.x - state.battle_position.x)


func _find_nearest_enemy(enemies: Array[UnitController]) -> UnitController:
	var nearest: UnitController = null
	var nearest_distance: float = AUTO_ACQUIRE_RANGE
	for enemy: UnitController in enemies:
		if enemy == null or not enemy.is_alive():
			continue
		var distance := state.battle_position.distance_to(enemy.get_position())
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest = enemy
	return nearest


func _clamp_to_bounds(position: Vector2) -> Vector2:
	if battle_bounds.size == Vector2.ZERO:
		return position
	var clamped := position
	clamped.x = clampf(clamped.x, battle_bounds.position.x, battle_bounds.end.x)
	clamped.y = clampf(clamped.y, battle_bounds.position.y, battle_bounds.end.y)
	return clamped
