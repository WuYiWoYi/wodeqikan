class_name SettlementIcon
extends Node2D
## 大地图地点图标。只读取 SettlementData。

var settlement: SettlementData = null

var _name_label: Label = null


func setup(data: SettlementData) -> void:
	settlement = data
	position = data.world_position
	_create_label()
	queue_redraw()


func _draw() -> void:
	if settlement == null:
		return

	draw_circle(Vector2(0.0, 8.0), 15.0, Color(0.0, 0.0, 0.0, 0.22))
	if settlement.settlement_type == SettlementData.SettlementType.CASTLE:
		_draw_castle()
	else:
		_draw_village()


func _draw_village() -> void:
	var wall := Color("#8a6a43")
	var roof := Color("#a24d3c")
	draw_rect(Rect2(-16.0, -4.0, 32.0, 18.0), wall, true)
	var roof_points := PackedVector2Array([
		Vector2(-21.0, -4.0),
		Vector2(0.0, -24.0),
		Vector2(21.0, -4.0),
	])
	draw_colored_polygon(roof_points, roof)
	draw_rect(Rect2(-5.0, 4.0, 10.0, 10.0), Color("#4a3020"), true)


func _draw_castle() -> void:
	var stone := Color("#8f9196")
	var dark := Color("#5a5d63")
	draw_rect(Rect2(-20.0, -10.0, 40.0, 24.0), stone, true)
	draw_rect(Rect2(-20.0, -10.0, 10.0, 24.0), dark, true)
	draw_rect(Rect2(10.0, -10.0, 10.0, 24.0), dark, true)
	draw_rect(Rect2(-24.0, -24.0, 10.0, 16.0), stone, true)
	draw_rect(Rect2(14.0, -24.0, 10.0, 16.0), stone, true)
	draw_rect(Rect2(-5.0, 2.0, 10.0, 12.0), Color("#303238"), true)
	draw_line(Vector2(0.0, -24.0), Vector2(0.0, -38.0), Color("#3b2a1a"), 2.0, true)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(0.0, -38.0),
			Vector2(12.0, -34.0),
			Vector2(0.0, -30.0),
		]),
		Color("#b94b42")
	)


func _create_label() -> void:
	if _name_label != null:
		_name_label.queue_free()
	_name_label = Label.new()
	_name_label.name = "NameLabel"
	_name_label.text = settlement.display_name
	_name_label.position = Vector2(-80.0, 26.0)
	_name_label.size = Vector2(160.0, 20.0)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.theme = UiTheme.create()
	_name_label.add_theme_font_size_override("font_size", 13)
	_name_label.add_theme_color_override("font_color", Color("#f3ead6"))
	_name_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_name_label)
