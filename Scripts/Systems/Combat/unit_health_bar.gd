class_name UnitHealthBar
extends Node2D
## 战斗单位头顶生命条。
##
## 与名称 Label 完全独立：满血或死亡时只隐藏本节点，名称保持显示。
## 只读取 BattleUnitState 的当前 HP 与 UnitData 的最大 HP，不修改任何数据。

const BAR_WIDTH: float = 32.0
const BAR_HEIGHT: float = 5.0
const BAR_TOP: float = -50.0
const FULL_HP_EPSILON: float = 0.0001

var max_hp: int = 1
var current_hp: int = 1
var alive: bool = true

var _ratio: float = 1.0


func setup(unit_max_hp: int) -> void:
	max_hp = maxi(unit_max_hp, 1)
	current_hp = max_hp
	alive = true
	position = Vector2(0.0, BAR_TOP)
	z_index = 1
	_refresh(true)


func update_health(unit_current_hp: int, unit_max_hp: int, is_alive: bool) -> void:
	var new_max: int = maxi(unit_max_hp, 1)
	var clamped_hp: int = clampi(unit_current_hp, 0, new_max)
	var changed: bool = (
		new_max != max_hp
		or clamped_hp != current_hp
		or is_alive != alive
	)
	max_hp = new_max
	current_hp = clamped_hp
	alive = is_alive
	if changed:
		_refresh(false)


func is_bar_visible() -> bool:
	return visible


func get_health_ratio() -> float:
	return _ratio


func _refresh(force_redraw: bool) -> void:
	_ratio = clampf(float(current_hp) / float(max_hp), 0.0, 1.0)
	var full_health: bool = _ratio >= 1.0 - FULL_HP_EPSILON
	visible = alive and not full_health
	if visible or force_redraw:
		queue_redraw()


func _draw() -> void:
	if not visible:
		return
	draw_rect(
		Rect2(-BAR_WIDTH * 0.5, 0.0, BAR_WIDTH, BAR_HEIGHT),
		Color(0.0, 0.0, 0.0, 0.7),
		true
	)
	var hp_color := Color("#6fdc6f") if _ratio > 0.35 else Color("#e05a4f")
	draw_rect(
		Rect2(-BAR_WIDTH * 0.5, 0.0, BAR_WIDTH * _ratio, BAR_HEIGHT),
		hp_color,
		true
	)
