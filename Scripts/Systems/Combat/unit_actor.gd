class_name UnitActor
extends Node2D
## 战斗场景中的单个士兵表现节点。
##
## 只读取 UnitData 的静态属性与 BattleUnitState 的战斗状态，不修改 UnitData。
## 士兵外观由 UnitVisual 组合临时素材；本节点只负责选中圈、血条与名称。
## 死亡后由战斗场景移除本节点；权威状态仍保留在 BattleSession 中等待结算。

const UnitVisualScript = preload("res://Scripts/Systems/Combat/unit_visual.gd")

const SELECTION_RADIUS: float = 20.0
const SELECTION_RADIUS_MOUNTED: float = 27.0

## YSort 只对 z_index = 0 的直接子节点按实时 Y 排序，因此士兵根节点保持 0；
## 高于战场背景的层级由父节点 Characters（z_index = 200）统一提供。
## UnitVisual 的部件使用相对负 z_index，士兵整体作为原子子树随 Y 排序，
## 内部部件层级保持固定。实际 canvas z = Characters.z + 本值 + 部件 z。
const ACTOR_Z_INDEX: int = 0

## 实际位移速度高于阈值视为跑动；停止后保留短暂缓冲，避免待机/跑动抖动。
const MOVE_SPEED_THRESHOLD: float = 8.0
const MOVE_STATE_BUFFER: float = 0.12

var unit_data: UnitData = null
var battle_state: BattleUnitState = null
var is_player_side: bool = false
var is_controlled: bool = false
var visual: Node2D = null

var _facing: float = -1.0
var _name_label: Label = null
var _health_bar: UnitHealthBar = null
var _attack_flash: float = 0.0
var _visual_moving: bool = false
var _move_buffer: float = 0.0
## 独立的影子根节点：所有士兵影子统一位于角色层之下的 Shadow 层，
## 避免角色按 Y 排序后，前排影子覆盖后排身体。
var _shadow_root: Node2D = null


func setup(
	data: UnitData,
	state: BattleUnitState,
	player_side: bool,
	equipment_configs: Dictionary = {},
	shadow_parent: Node2D = null
) -> void:
	unit_data = data
	battle_state = state
	is_player_side = player_side
	name = "UnitActor_%s" % data.unit_id
	position = state.battle_position
	z_index = ACTOR_Z_INDEX

	if shadow_parent != null and is_instance_valid(shadow_parent):
		_shadow_root = Node2D.new()
		_shadow_root.name = "UnitShadow_%s" % data.unit_id
		_shadow_root.position = position
		shadow_parent.add_child(_shadow_root)

	visual = UnitVisualScript.new()
	visual.name = "Visual"
	add_child(visual)
	if _shadow_root != null:
		visual.set_shadow_layer(_shadow_root)
	visual.setup(data, equipment_configs)
	if _shadow_root != null:
		_shadow_root.scale.x = _facing

	_create_label()
	_create_health_bar()
	queue_redraw()


func _process(delta: float) -> void:
	if battle_state == null:
		return

	var new_position: Vector2 = battle_state.battle_position
	var moved_distance: float = position.distance_to(new_position)
	var speed: float = moved_distance / maxf(delta, 0.0001)
	position = new_position
	if _shadow_root != null and is_instance_valid(_shadow_root):
		_shadow_root.position = position

	if speed >= MOVE_SPEED_THRESHOLD:
		_visual_moving = true
		_move_buffer = MOVE_STATE_BUFFER
	else:
		_move_buffer = maxf(0.0, _move_buffer - delta)
		if _move_buffer <= 0.0:
			_visual_moving = false

	if is_instance_valid(visual):
		# 支持战斗中装备/卸下马匹后立即切换步兵/骑兵表现，不重建节点。
		if unit_data != null and visual.is_mounted_visual() != unit_data.is_mounted:
			visual.set_mounted(unit_data.is_mounted)
		visual.update_locomotion(delta, _visual_moving)

	if _attack_flash > 0.0:
		_attack_flash = maxf(0.0, _attack_flash - delta)
		if _attack_flash <= 0.0 and is_instance_valid(visual):
			visual.set_attack_flash(false)
	if _health_bar != null and unit_data != null:
		_health_bar.update_health(
			battle_state.battle_hp, unit_data.max_hp, battle_state.alive
		)
	queue_redraw()


func set_controlled(value: bool) -> void:
	if is_controlled != value:
		is_controlled = value
		queue_redraw()
	_update_name_visibility()


## 普通士兵隐藏头顶名称；只有玩家当前控制的单位显示名称。
func _update_name_visibility() -> void:
	if _name_label != null:
		_name_label.visible = is_controlled


func play_attack(direction: Vector2 = Vector2.LEFT) -> void:
	_attack_flash = 0.18
	if is_instance_valid(visual):
		visual.set_attack_flash(true)
		# 长矛动画纯表现；伤害/冷却已在 UnitController 中即时结算。
		visual.play_attack_animation(direction)
	queue_redraw()


## 弓箭攻击表现：拉弓/放箭；箭矢与伤害由 UnitController / ProjectileManager 负责。
func play_ranged_attack(direction: Vector2 = Vector2.LEFT) -> void:
	_attack_flash = 0.0
	if is_instance_valid(visual):
		visual.play_ranged_attack_animation(direction)
		visual.set_attack_flash(true)
	queue_redraw()


## 当前右手武器枢轴的世界坐标；弓的发射位置从这里取样。
## 没有武器枢轴时返回 Vector2.INF，调用方使用单位地面坐标作为回退。
func get_weapon_pivot_global_position() -> Vector2:
	if is_instance_valid(visual):
		var pivot: Node2D = visual.get_weapon_pivot()
		if pivot != null:
			return pivot.global_position
	return Vector2.INF


func is_attack_animating() -> bool:
	return is_instance_valid(visual) and visual.is_attack_animating()


## 仅挥动/刺出阶段锁定朝向，攻击后的长矛保持姿态不阻止移动转身。
func is_attack_pose_locked() -> bool:
	return is_instance_valid(visual) and visual.is_attack_pose_locked()


func is_visual_moving() -> bool:
	return _visual_moving


func set_facing(direction_x: float) -> void:
	if absf(direction_x) < 0.01:
		return
	var new_facing: float = 1.0 if direction_x > 0.0 else -1.0
	if not is_equal_approx(new_facing, _facing):
		_facing = new_facing
		if is_instance_valid(visual):
			visual.set_facing(_facing)
		if _shadow_root != null and is_instance_valid(_shadow_root):
			_shadow_root.scale.x = _facing
		queue_redraw()


func play_death() -> void:
	queue_free()


func _exit_tree() -> void:
	# 影子属于独立层级，必须随士兵表现节点一起清理，避免残留。
	if _shadow_root != null and is_instance_valid(_shadow_root):
		_shadow_root.queue_free()
		_shadow_root = null


func get_shadow_root() -> Node2D:
	return _shadow_root


func _draw() -> void:
	if unit_data == null or battle_state == null:
		return

	if is_controlled:
		var radius: float = (
			SELECTION_RADIUS_MOUNTED if unit_data.is_mounted else SELECTION_RADIUS
		)
		draw_arc(
			Vector2.ZERO,
			radius,
			0.0,
			TAU,
			32,
			Color("#ffd75e"),
			2.5,
			true
		)

	if not battle_state.alive:
		draw_line(Vector2(-10.0, -10.0), Vector2(10.0, 10.0), Color(0.0, 0.0, 0.0, 0.7), 2.5)


func _create_health_bar() -> void:
	_health_bar = UnitHealthBar.new()
	_health_bar.name = "HealthBar"
	_health_bar.setup(unit_data.max_hp if unit_data != null else 1)
	add_child(_health_bar)


func get_health_bar() -> UnitHealthBar:
	return _health_bar


func get_name_label() -> Label:
	return _name_label


func is_name_visible() -> bool:
	return _name_label != null and _name_label.visible


func _create_label() -> void:
	_name_label = Label.new()
	_name_label.name = "NameLabel"
	_name_label.text = unit_data.display_name
	# 默认隐藏；由 set_controlled() 按当前控制权切换，不影响生命条。
	_name_label.visible = is_controlled
	_name_label.position = Vector2(-50.0, -70.0)
	_name_label.size = Vector2(100.0, 18.0)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.theme = UiTheme.create()
	_name_label.add_theme_font_size_override("font_size", 11)
	_name_label.add_theme_color_override("font_color", Color.WHITE)
	_name_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_name_label)
