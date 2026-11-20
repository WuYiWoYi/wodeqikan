class_name PartyIcon
extends Node2D
## 大地图部队图标。只读取 PartyData，不修改权威数据。

var party: PartyData = null
var is_player: bool = false

var _name_label: Label = null


func setup(data: PartyData, player_owned: bool) -> void:
	party = data
	is_player = player_owned
	position = data.world_position
	_create_label()
	queue_redraw()


func _process(delta: float) -> void:
	if party == null:
		return
	var weight: float = clampf(delta * 12.0, 0.0, 1.0)
	position = position.lerp(party.world_position, weight)


func _draw() -> void:
	if party == null:
		return

	draw_circle(Vector2(0.0, 10.0), 12.0, Color(0.0, 0.0, 0.0, 0.25))
	if is_player:
		draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 32, Color("#4ea1ff"), 2.5, true)

	draw_line(Vector2(0.0, 8.0), Vector2(0.0, -30.0), Color("#3b2a1a"), 3.0, true)

	var flag_color: Color = Color("#2f7fdd") if is_player else Color("#b94b42")
	var flag := PackedVector2Array([
		Vector2(0.0, -30.0),
		Vector2(26.0, -24.0),
		Vector2(0.0, -15.0),
	])
	draw_colored_polygon(flag, flag_color)
	draw_polyline(
		PackedVector2Array([flag[0], flag[1], flag[2], flag[0]]),
		Color(0.0, 0.0, 0.0, 0.35),
		1.5,
		true
	)


func _create_label() -> void:
	if _name_label != null:
		_name_label.queue_free()
	_name_label = Label.new()
	_name_label.name = "NameLabel"
	_name_label.text = party.party_name
	_name_label.position = Vector2(-70.0, -56.0)
	_name_label.size = Vector2(140.0, 20.0)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.theme = UiTheme.create()
	_name_label.add_theme_font_size_override("font_size", 12)
	_name_label.add_theme_color_override("font_color", Color.WHITE)
	_name_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_name_label)
