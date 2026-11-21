class_name PartyIcon
extends Node2D
## 大地图部队圆形标记。只读取 PartyData，不修改权威数据。
##
## 圆形底盘 + 内部旗帜；旗帜等比放大后可超出内径，由圆形遮罩裁掉四角。
## 尺寸、边框、阵营回退色、旗帜缩放与人数位置统一来自 PartyMarkerStyle。
## 所有部队类型共用这一个节点；家族色/阵营色只通过数据传入。
## 图标不显示部队名称，完整信息由鼠标悬浮面板提供。

const PLAYER_MARKER_COLOR: Color = Color("#2f7fdd")
const ENEMY_MARKER_COLOR: Color = Color("#b94b42")
const CIRCLE_FLAG_SHADER_PATH: String = "res://Shaders/map_flag_circle.gdshader"

var party: PartyData = null
var is_player: bool = false

var _style: PartyMarkerStyle = null
var _marker_color: Color = ENEMY_MARKER_COLOR
var _flag_texture: Texture2D = null
var _flag_sprite: Sprite2D = null
var _count_label: Label = null
var _last_count: int = -1


func setup(
	data: PartyData,
	player_owned: bool,
	flag_texture: Texture2D = null,
	marker_color: Color = Color(0.0, 0.0, 0.0, 0.0),
	style: PartyMarkerStyle = null
) -> void:
	party = data
	is_player = player_owned
	_style = style if style != null else PartyMarkerStyle.create_default()
	if marker_color.a > 0.0:
		_marker_color = marker_color
	elif is_player:
		_marker_color = PLAYER_MARKER_COLOR
	elif data != null:
		# 无家族颜色的 NPC 部队按阵营读取统一回退色，而不是一律使用敌方红。
		_marker_color = _style.get_faction_color(data.faction_id, ENEMY_MARKER_COLOR)
	else:
		_marker_color = ENEMY_MARKER_COLOR
	_flag_texture = flag_texture
	position = data.world_position
	_create_flag_sprite()
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

	var radius: float = _style.marker_radius
	draw_circle(
		Vector2(0.0, _style.shadow_offset_y),
		_style.shadow_radius,
		Color(0.0, 0.0, 0.0, 0.25)
	)
	# 外圈边框 + 内部底色；家族色作为圆形底盘色。
	draw_circle(Vector2.ZERO, radius, _style.marker_border_color)
	draw_circle(
		Vector2.ZERO,
		maxf(1.0, radius - _style.border_width),
		_marker_color.darkened(0.35)
	)
	if is_player:
		draw_arc(
			Vector2.ZERO, radius + 3.0, 0.0, TAU, 40,
			_style.player_ring_color, 2.5, true
		)

	# 没有家族旗帜时，在圆内绘制简易默认旗帜，避免出现空圆。
	if _flag_sprite == null or _flag_sprite.texture == null:
		var half: float = _style.flag_max_size * 0.5
		draw_colored_polygon(
			PackedVector2Array([
				Vector2(-half, -half),
				Vector2(half, -half),
				Vector2(-half, half),
			]),
			_marker_color.lightened(0.25)
		)
		draw_line(
			Vector2(-half, -half), Vector2(-half, half),
			Color(0.1, 0.08, 0.06, 0.9), 2.0, true
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


func get_marker_radius() -> float:
	return _style.marker_radius if _style != null else 0.0


func get_flag_texture_path() -> String:
	if _flag_texture == null:
		return ""
	return _flag_texture.resource_path


func _create_flag_sprite() -> void:
	if _flag_sprite != null:
		_flag_sprite.queue_free()
		_flag_sprite = null
	if _flag_texture == null:
		return

	_flag_sprite = Sprite2D.new()
	_flag_sprite.name = "FamilyFlag"
	_flag_sprite.texture = _flag_texture
	_flag_sprite.centered = true
	_flag_sprite.position = Vector2(0.0, _style.flag_vertical_offset)
	_flag_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_flag_sprite.z_index = 1
	# 等比缩放：取宽高中较大边，保持原始宽高比；再由圆形遮罩裁剪边缘。
	var texture_size: Vector2 = _flag_texture.get_size()
	var longest_side: float = maxf(texture_size.x, texture_size.y)
	if longest_side > 0.0:
		var factor: float = _style.flag_max_size / longest_side
		_flag_sprite.scale = Vector2(factor, factor)
	if ResourceLoader.exists(CIRCLE_FLAG_SHADER_PATH):
		var mask_shader := load(CIRCLE_FLAG_SHADER_PATH) as Shader
		if mask_shader != null:
			var mask_material := ShaderMaterial.new()
			mask_material.shader = mask_shader
			# 裁剪半径贴近边框内缘：旗帜允许大于内径，但不会盖住外圈边框。
			mask_material.set_shader_parameter(
				"uv_radius", _style.get_flag_clip_uv_radius()
			)
			_flag_sprite.material = mask_material
	add_child(_flag_sprite)


func _create_count_label() -> void:
	if _count_label != null:
		_count_label.queue_free()
	_count_label = Label.new()
	_count_label.name = "CountLabel"
	_count_label.text = "0"
	_count_label.position = _style.count_offset - Vector2(24.0, 12.0)
	_count_label.size = Vector2(48.0, 24.0)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count_label.z_index = 2
	_count_label.theme = UiTheme.create()
	_count_label.add_theme_font_size_override("font_size", _style.count_font_size)
	_count_label.add_theme_color_override("font_color", Color.WHITE)
	_count_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	_count_label.add_theme_constant_override("shadow_offset_x", 1)
	_count_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_count_label)
