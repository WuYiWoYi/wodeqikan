class_name ArrowProjectile
extends Node2D
## 一支临时箭矢：固定目标坐标 + 抛物线视觉高度 + 高度命中判定。
##
## 关键约束：
## - 节点 position 始终是“地面投影坐标”，参与 Characters 的 YSort；
## - 飞行高度只改变子 Sprite/Line2D 的局部 Y 偏移，绝不写回地面坐标；
## - 目标坐标在发射时冻结，不读取/追踪目标单位的后续位置；
## - 每支箭最多命中一次，命中或抵达终点后结束。
##
## 不直接修改 UnitData：伤害统一通过目标的 UnitController.apply_damage() 结算。

## 地面命中半径。目标移动超过该范围后，箭矢自然射空。
const HIT_GROUND_RADIUS: float = 18.0
## 极短/极长飞行时间的保护范围。
const MIN_FLIGHT_TIME: float = 0.05
const MAX_FLIGHT_TIME: float = 3.0
## 没有贴图时的回退箭矢绘制长度。
const FALLBACK_ARROW_LENGTH: float = 18.0

var _shooter: Variant = null
var _enemies: Array = []
var _start_ground: Vector2 = Vector2.ZERO
var _target_ground: Vector2 = Vector2.ZERO
var _launch_height: float = 20.0
var _arc_height: float = 70.0
var _speed: float = 480.0
var _damage: int = 0
var _duration: float = 1.0
var _elapsed: float = 0.0
var _height: float = 0.0
var _finished: bool = false
var _hit: bool = false
var _visual: Node2D = null


## 由 ProjectileManager 调用。start_ground 是射手脚下坐标；launch_height 是
## 弓相对地面的视觉高度。target_ground 是本次射击冻结的地面目标坐标。
func setup(
	shooter: Variant,
	start_ground: Vector2,
	target_ground: Vector2,
	launch_height: float,
	damage: int,
	enemies: Array,
	texture_path: String,
	speed: float,
	arc_height: float
) -> void:
	_shooter = shooter
	_start_ground = start_ground
	_target_ground = target_ground
	_launch_height = maxf(0.0, launch_height)
	_damage = maxi(0, damage)
	_enemies = enemies.duplicate()
	_speed = maxf(1.0, speed)
	_arc_height = maxf(0.0, arc_height)

	var distance: float = _start_ground.distance_to(_target_ground)
	_duration = clampf(distance / _speed, MIN_FLIGHT_TIME, MAX_FLIGHT_TIME)

	# 地面深度使用节点自身 position；与 UnitActor 使用同一 z 层，参与 YSort。
	z_index = UnitActor.ACTOR_Z_INDEX
	position = _start_ground
	_create_visual(texture_path)
	_update_visual(0.0)


## 推进飞行与命中检测；由 ProjectileManager 每物理帧调用。
func advance(delta: float) -> void:
	if _finished:
		return
	_elapsed += maxf(0.0, delta)
	var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
	_update_visual(t)
	_check_hits()
	if _finished:
		return
	if t >= 1.0:
		_finish(false)


func is_finished() -> bool:
	return _finished


func has_hit() -> bool:
	return _hit


func get_ground_position() -> Vector2:
	return position


func get_height() -> float:
	return _height


func get_target_ground() -> Vector2:
	return _target_ground


func get_visual_position() -> Vector2:
	return position + Vector2(0.0, -_height)


func _update_visual(t: float) -> void:
	# 地面投影与视觉高度严格分离：地面坐标用于排序，视觉高度只偏移表现子节点。
	position = _start_ground.lerp(_target_ground, t)
	_height = _launch_height * (1.0 - t) + 4.0 * _arc_height * t * (1.0 - t)
	if _visual == null:
		return
	_visual.position = Vector2(0.0, -_height)
	# 视觉速度 = 地面速度 + 高度导数；让箭头随抛物线转向。
	var ground_velocity: Vector2 = (_target_ground - _start_ground) / _duration
	var height_rate: float = (
		-_launch_height + 4.0 * _arc_height * (1.0 - 2.0 * t)
	) / _duration
	var visual_velocity: Vector2 = ground_velocity + Vector2(0.0, -height_rate)
	if visual_velocity.length_squared() > 0.0001:
		# 箭素材默认箭头朝上；向上旋转 -PI/2 后与飞行方向一致。
		_visual.rotation = visual_velocity.angle() + PI * 0.5


func _check_hits() -> void:
	if _finished or _shooter == null:
		return
	var shooter_side: int = int(_shooter.side_index)
	for enemy: Variant in _enemies:
		if enemy == null:
			continue
		if int(enemy.side_index) == shooter_side:
			continue
		if not enemy.is_alive():
			continue
		var enemy_ground: Vector2 = enemy.get_position()
		if position.distance_to(enemy_ground) > HIT_GROUND_RADIUS:
			continue
		var body_height: float = 48.0
		if enemy.unit_data != null:
			body_height = maxf(1.0, float(enemy.unit_data.body_height))
		# 仅地面位置重合不足以命中；箭矢必须处于敌人有效身体高度内。
		if _height > body_height:
			continue
		enemy.apply_damage(_damage)
		_hit = true
		_finish(true)
		return


func _finish(hit: bool) -> void:
	_finished = true
	_hit = hit
	if _visual != null:
		_visual.visible = false


func _create_visual(texture_path: String) -> void:
	var texture: Texture2D = null
	if not texture_path.is_empty() and ResourceLoader.exists(texture_path):
		texture = load(texture_path) as Texture2D
	if texture != null:
		var sprite := Sprite2D.new()
		sprite.name = "ArrowSprite"
		sprite.texture = texture
		sprite.centered = false
		# 以贴图中心为旋转中心；箭素材默认箭头朝上。
		sprite.offset = -Vector2(
			float(texture.get_width()) * 0.5, float(texture.get_height()) * 0.5
		)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sprite)
		_visual = sprite
		return

	# 贴图缺失时保持可测试的最小表现，不阻断攻击逻辑。
	var line := Line2D.new()
	line.name = "ArrowFallback"
	line.points = PackedVector2Array([
		Vector2(0.0, -FALLBACK_ARROW_LENGTH * 0.5),
		Vector2(0.0, FALLBACK_ARROW_LENGTH * 0.5),
	])
	line.width = 2.0
	line.default_color = Color("#e6d6a8")
	add_child(line)
	_visual = line
