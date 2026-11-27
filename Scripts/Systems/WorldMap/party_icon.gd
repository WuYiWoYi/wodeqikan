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
const TextureRegion = preload("res://Scripts/Core/World/texture_region_utils.gd")

var party: PartyData = null
var is_player: bool = false

var _style: PartyMarkerStyle = null
var _marker_color: Color = ENEMY_MARKER_COLOR
var _flag_texture: Texture2D = null
## 原始旗帜路径；缩略裁切后仍用于测试/调试读取配置来源。
var _flag_texture_path: String = ""
var _flag_sprite: Sprite2D = null
var _count_label: Label = null
var _last_count: int = -1
var _floating_label: Label = null
var _floating_tween: Tween = null
var _last_floating_text: String = ""
## 鼠标悬浮状态；只影响额外白色描边，不改变尺寸、位置或点击区域。
var _hovered: bool = false
## 与玩家的阵营关系；由 WorldMap 通过统一关系接口写入，图标不自行判断政治关系。
var _player_relation: int = FactionManager.PlayerRelation.NEUTRAL


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
	_flag_texture_path = flag_texture.resource_path if flag_texture != null else ""
	position = data.world_position
	_player_relation = FactionManager.PlayerRelation.NEUTRAL
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
	# 基础黑色圆形描边：外缘固定在标记外径，加粗部分全部向圆内扩展，
	# 因此整体视觉尺寸、位置与点击/悬浮判定都不改变。
	if _style.outline_width > 0.0:
		draw_arc(
			Vector2.ZERO,
			_style.get_outline_outer_radius() - _style.outline_width * 0.5,
			0.0, TAU, 64,
			_style.outline_color, _style.outline_width, true
		)
	# 持续阵营外环：玩家蓝色优先，其余按与玩家的关系显示绿/红/无。
	# 只绘制在主体外缘，不改变标记尺寸、点击区域或悬浮描边。
	var faction_ring := _resolve_faction_ring_color()
	if faction_ring.a > 0.0:
		draw_arc(
			Vector2.ZERO, radius + 3.0, 0.0, TAU, 40,
			faction_ring, 2.5, true
		)
	# 悬浮白色描边：画在圆形主体之外，与黑色基础描边同时存在。
	if _hovered and _style.hover_outline_width > 0.0:
		draw_arc(
			Vector2.ZERO,
			radius + _style.hover_outline_gap + _style.hover_outline_width * 0.5,
			0.0, TAU, 64,
			_style.hover_outline_color, _style.hover_outline_width, true
		)

	# 没有家族旗帜时，在圆内绘制简易默认旗帜，避免出现空圆。
	# 三角形顶点需落在旗帜裁剪圈内，因此单独限制半宽，避免越出圆形。
	if _flag_sprite == null or _flag_sprite.texture == null:
		var inner_radius: float = _style.get_flag_clip_radius()
		var half: float = minf(
			_style.flag_max_size * 0.5, inner_radius * 0.62
		)
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


## 仅切换悬浮白色描边；不改变标记尺寸、位置或点击区域。
func set_hovered(value: bool) -> void:
	if _hovered == value:
		return
	_hovered = value
	queue_redraw()


func is_hovered() -> bool:
	return _hovered


## 由 WorldMap 写入统一关系查询结果；只切换阵营外环，不影响其他状态。
func set_player_relation(relation: int) -> void:
	if _player_relation == relation:
		return
	_player_relation = relation
	queue_redraw()


func get_player_relation() -> int:
	return _player_relation


## 当前持续外环颜色；透明表示中立（不绘制阵营外环）。
func _resolve_faction_ring_color() -> Color:
	if is_player:
		return _style.player_ring_color
	match _player_relation:
		FactionManager.PlayerRelation.ALLIED:
			return _style.allied_ring_color
		FactionManager.PlayerRelation.HOSTILE:
			return _style.hostile_ring_color
		_:
			return Color(0.0, 0.0, 0.0, 0.0)


func get_faction_ring_color() -> Color:
	return _resolve_faction_ring_color()


func get_marker_style() -> PartyMarkerStyle:
	return _style


func get_flag_texture_path() -> String:
	return _flag_texture_path


## 部队上方的一次性浮动提示（例如“招募了1组采邑”）。
## 纯表现，不进入存档；重复触发会替换上一条提示。
func show_floating_text(text: String, duration: float = 2.2) -> void:
	if text.strip_edges().is_empty():
		return
	if _floating_tween != null and _floating_tween.is_valid():
		_floating_tween.kill()
	if _floating_label != null and is_instance_valid(_floating_label):
		_floating_label.queue_free()
	_last_floating_text = text
	var radius: float = _style.marker_radius if _style != null else 20.0
	_floating_label = Label.new()
	_floating_label.name = "FloatingText"
	_floating_label.text = text
	_floating_label.position = Vector2(-110.0, -radius - 54.0)
	_floating_label.size = Vector2(220.0, 26.0)
	_floating_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floating_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floating_label.z_index = 5
	_floating_label.theme = UiTheme.create()
	_floating_label.add_theme_font_size_override("font_size", 15)
	_floating_label.add_theme_color_override("font_color", Color("#ffe6a8"))
	_floating_label.add_theme_color_override(
		"font_shadow_color", Color(0.0, 0.0, 0.0, 0.9)
	)
	_floating_label.add_theme_constant_override("shadow_offset_x", 1)
	_floating_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_floating_label)
	_floating_tween = create_tween()
	_floating_tween.set_parallel(true)
	_floating_tween.tween_property(
		_floating_label,
		"position:y",
		_floating_label.position.y - 34.0,
		duration
	)
	_floating_tween.tween_property(
		_floating_label, "modulate:a", 0.0, duration
	).set_delay(duration * 0.35)
	_floating_tween.chain().tween_callback(_floating_label.queue_free)


func get_last_floating_text() -> String:
	return _last_floating_text


func _create_flag_sprite() -> void:
	if _flag_sprite != null:
		_flag_sprite.queue_free()
		_flag_sprite = null
	if _flag_texture == null:
		return

	# 透明留白不参与缩放：先按非透明像素区域裁切，再以有效尺寸等比放大。
	var trimmed := TextureRegion.get_trimmed_texture(_flag_texture)
	var texture_size: Vector2 = trimmed.get_size()
	_flag_sprite = Sprite2D.new()
	_flag_sprite.name = "FamilyFlag"
	_flag_sprite.texture = trimmed
	_flag_sprite.centered = true
	_flag_sprite.position = Vector2(0.0, _style.flag_vertical_offset)
	_flag_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_flag_sprite.z_index = 1
	# 等比缩放：取有效宽高中较大边，保持原始宽高比；再由圆形遮罩裁剪边缘。
	var factor: float = 1.0
	var longest_side: float = maxf(texture_size.x, texture_size.y)
	if longest_side > 0.0:
		factor = _style.flag_max_size / longest_side
		_flag_sprite.scale = Vector2(factor, factor)
	if ResourceLoader.exists(CIRCLE_FLAG_SHADER_PATH):
		var mask_shader := load(CIRCLE_FLAG_SHADER_PATH) as Shader
		if mask_shader != null:
			var mask_material := ShaderMaterial.new()
			mask_material.shader = mask_shader
			# 在旗帜精灵的局部像素空间裁剪正圆：把图标主体中心换算到精灵局部坐标，
			# 即使旗帜有垂直偏移也与圆形主体同心。
			# 精灵缩放会把局部半径放大 factor 倍，因此先换算回局部单位；
			# 这样遮罩与 draw_circle / draw_arc 共用同一世界半径基准，
			# 不再依赖 AtlasTexture 的图集 UV 或旗帜宽高比。
			var local_scale: float = maxf(0.0001, factor)
			mask_material.set_shader_parameter("use_local_circle", true)
			mask_material.set_shader_parameter(
				"circle_center", -_flag_sprite.position / local_scale
			)
			mask_material.set_shader_parameter(
				"circle_radius",
				_style.get_flag_clip_radius() / local_scale
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
