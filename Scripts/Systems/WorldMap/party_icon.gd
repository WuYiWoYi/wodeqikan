class_name PartyIcon
extends Node2D
## 大地图部队图标。只读取 PartyData，不修改权威数据。
##
## 图标不再显示部队名称，只在旗帜下方显示当前人数；
## 完整名称与成员构成由鼠标悬浮面板显示。

var party: PartyData = null
var is_player: bool = false

var _count_label: Label = null
var _last_count: int = -1


func setup(data: PartyData, player_owned: bool) -> void:
	party = data
	is_player = player_owned
	position = data.world_position
	_create_count_label()
	_refresh_count()
	queue_redraw()


func _process(delta: float) -> void:
	if party == null:
		return
	var weight: float = clampf(delta * 12.0, 0.0, 1.0)
	position = position.lerp(party.world_position, weight)
	_refresh_count()


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


## 部队人数徽标；人数变化时同步更新。
func _refresh_count() -> void:
	if _count_label == null or party == null:
		return
	var count: int = party.member_unit_ids.size()
	if count == _last_count:
		return
	_last_count = count
	_count_label.text = str(count)


func get_count_text() -> String:
	return _count_label.text if _count_label != null else ""


func _create_count_label() -> void:
	if _count_label != null:
		_count_label.queue_free()
	_count_label = Label.new()
	_count_label.name = "CountLabel"
	_count_label.text = "0"
	_count_label.position = Vector2(-24.0, 6.0)
	_count_label.size = Vector2(48.0, 24.0)
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
