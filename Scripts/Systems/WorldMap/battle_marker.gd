class_name BattleMarker
extends Node2D
## 大地图上同一场 BattleSession 的唯一战斗标记。
##
## 参战部队的普通 PartyIcon 在战斗期间隐藏，由本标记汇总显示。
## 只读取 BattleSession 的公开数据，不修改战斗或部队状态。

const MARKER_Z_INDEX: int = 400

var battle_id: String = ""
var _count_label: Label = null
var _last_count: int = -1


func setup(id: String, world_position: Vector2) -> void:
	battle_id = id
	name = "BattleMarker_%s" % id
	position = world_position
	z_index = MARKER_Z_INDEX
	_create_count_label()
	set_alive_count(0)
	queue_redraw()


func set_battle_position(world_position: Vector2) -> void:
	position = world_position


func set_alive_count(count: int) -> void:
	if _count_label == null:
		return
	if count == _last_count:
		return
	_last_count = count
	_count_label.text = str(count)


func get_count_text() -> String:
	return _count_label.text if _count_label != null else ""


func _draw() -> void:
	draw_circle(Vector2(0.0, 8.0), 22.0, Color(0.0, 0.0, 0.0, 0.3))
	draw_circle(Vector2.ZERO, 19.0, Color("#8f2f2f"))
	draw_arc(Vector2.ZERO, 19.0, 0.0, TAU, 32, Color("#f0c060"), 2.0, true)

	# 交叉武器。
	var blade := Color("#f4ead2")
	draw_line(Vector2(-10.0, -10.0), Vector2(10.0, 10.0), blade, 3.0, true)
	draw_line(Vector2(10.0, -10.0), Vector2(-10.0, 10.0), blade, 3.0, true)
	draw_line(Vector2(-12.0, -14.0), Vector2(-6.0, -8.0), Color("#d9c58f"), 2.0, true)
	draw_line(Vector2(12.0, -14.0), Vector2(6.0, -8.0), Color("#d9c58f"), 2.0, true)


func _create_count_label() -> void:
	if _count_label != null:
		_count_label.queue_free()
	_count_label = Label.new()
	_count_label.name = "BattleMarkerCountLabel"
	_count_label.text = "0"
	_count_label.position = Vector2(-26.0, 14.0)
	_count_label.size = Vector2(52.0, 24.0)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count_label.theme = UiTheme.create()
	_count_label.add_theme_font_size_override("font_size", 16)
	_count_label.add_theme_color_override("font_color", Color.WHITE)
	_count_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	_count_label.add_theme_constant_override("shadow_offset_x", 1)
	_count_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_count_label)
