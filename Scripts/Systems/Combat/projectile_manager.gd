class_name ProjectileManager
extends RefCounted
## 战斗场景内的临时发射物管理器。
##
## 只负责创建/推进/销毁箭矢，不参与单位 AI、索敌或伤害规则。
## 箭矢节点直接挂在 Characters 下，以便复用场景现有的 YSort；地面的 Y
## 由 ArrowProjectile.position 决定，飞行高度只影响其子表现节点。

const ArrowProjectileScript = preload("res://Scripts/Systems/Combat/arrow_projectile.gd")

var _characters: Node = null
var _arrows: Array = []
var _next_arrow_index: int = 1


func setup(characters: Node) -> void:
	_characters = characters


## 由 UnitController 在成功发射时调用。shooter 必须是 UnitController；
## 目标坐标在调用时已经冻结，本方法不会保存/追踪目标单位。
func spawn_arrow(
	shooter: Variant,
	target_ground: Vector2,
	enemies: Array,
	damage: int,
	texture_path: String,
	speed: float,
	arc_height: float
) -> bool:
	if shooter == null or _characters == null or not is_instance_valid(_characters):
		return false
	if shooter.unit_data == null or shooter.state == null:
		return false

	var launch_ground: Vector2 = shooter.get_position()
	var launch_height: float = 20.0
	if shooter.has_method("get_ranged_launch_info"):
		var launch: Dictionary = shooter.get_ranged_launch_info()
		launch_ground = launch.get("ground", launch_ground)
		launch_height = float(launch.get("height", launch_height))

	var arrow := ArrowProjectileScript.new()
	arrow.name = "Arrow_%04d" % _next_arrow_index
	_next_arrow_index += 1
	_characters.add_child(arrow)
	arrow.setup(
		shooter,
		launch_ground,
		target_ground,
		launch_height,
		damage,
		enemies,
		texture_path,
		speed,
		arc_height
	)
	_arrows.append(arrow)
	return true


## 推进所有活动箭矢；结束的箭矢从场景与列表中移除。
func advance(delta: float) -> void:
	for i: int in range(_arrows.size() - 1, -1, -1):
		var arrow: Variant = _arrows[i]
		if arrow == null or not is_instance_valid(arrow):
			_arrows.remove_at(i)
			continue
		arrow.advance(delta)
		if arrow.is_finished():
			_arrows.remove_at(i)
			if arrow.get_parent() != null:
				arrow.get_parent().remove_child(arrow)
			arrow.queue_free()


func get_active_count() -> int:
	var count: int = 0
	for arrow: Variant in _arrows:
		if arrow != null and is_instance_valid(arrow) and not arrow.is_finished():
			count += 1
	return count


func get_arrows() -> Array:
	return _arrows.duplicate()


func clear() -> void:
	for arrow: Variant in _arrows:
		if arrow != null and is_instance_valid(arrow):
			arrow.queue_free()
	_arrows.clear()
