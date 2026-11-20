class_name UnitActor
extends Node2D
## 战斗场景中的单个士兵表现节点。
##
## 只读取 UnitData 的静态属性与 BattleUnitState 的战斗状态，不修改 UnitData。
## 死亡后由战斗场景移除本节点；权威状态仍保留在 BattleSession 中等待结算。

const BODY_RADIUS: float = 13.0

var unit_data: UnitData = null
var battle_state: BattleUnitState = null
var is_player_side: bool = false

var _facing: float = -1.0
var _name_label: Label = null


func setup(data: UnitData, state: BattleUnitState, player_side: bool) -> void:
	unit_data = data
	battle_state = state
	is_player_side = player_side
	name = "UnitActor_%s" % data.unit_id
	position = state.battle_position
	_create_label()
	queue_redraw()


func _process(_delta: float) -> void:
	if battle_state == null:
		return
	position = battle_state.battle_position
	queue_redraw()


func set_facing(direction_x: float) -> void:
	if absf(direction_x) < 0.01:
		return
	var new_facing: float = 1.0 if direction_x > 0.0 else -1.0
	if not is_equal_approx(new_facing, _facing):
		_facing = new_facing
		queue_redraw()


func play_death() -> void:
	queue_free()


func _draw() -> void:
	if unit_data == null or battle_state == null:
		return

	var body_color := Color("#2f6fd0") if is_player_side else Color("#b83b35")
	var outline_color := Color("#d8ecff") if is_player_side else Color("#ffd2cc")

	draw_circle(Vector2(0.0, 10.0), BODY_RADIUS, Color(0.0, 0.0, 0.0, 0.25))
	draw_circle(Vector2.ZERO, BODY_RADIUS, outline_color)
	draw_circle(Vector2.ZERO, BODY_RADIUS - 2.0, body_color)
	draw_circle(Vector2(0.0, -15.0), 6.5, Color("#e6c39a"))

	# 武器朝向：默认朝左。
	draw_line(
		Vector2(-4.0 * _facing, -2.0),
		Vector2(18.0 * _facing, -8.0),
		Color("#d9d9d9"),
		2.5,
		true
	)

	var max_hp: int = maxi(unit_data.max_hp, 1)
	var ratio: float = clampf(float(battle_state.battle_hp) / float(max_hp), 0.0, 1.0)
	draw_rect(Rect2(-16.0, -34.0, 32.0, 5.0), Color(0.0, 0.0, 0.0, 0.7), true)
	var hp_color := Color("#6fdc6f") if ratio > 0.35 else Color("#e05a4f")
	draw_rect(Rect2(-16.0, -34.0, 32.0 * ratio, 5.0), hp_color, true)

	if not battle_state.alive:
		draw_line(Vector2(-10.0, -10.0), Vector2(10.0, 10.0), Color(0.0, 0.0, 0.0, 0.7), 2.5)


func _create_label() -> void:
	_name_label = Label.new()
	_name_label.name = "NameLabel"
	_name_label.text = unit_data.display_name
	_name_label.position = Vector2(-50.0, -58.0)
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
