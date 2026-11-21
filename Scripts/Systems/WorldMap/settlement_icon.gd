class_name SettlementIcon
extends Node2D
## 大地图地点图标。只读取 SettlementData / FamilyConfig。
##
## 村庄使用放大的圆形标记：外圈 + 家族旗帜，旗帜允许大于内径并由圆形边框裁剪。
## 城堡保留原有建筑绘制，不跟随村庄一起放大。
## 地点名称与其它屏幕 UI 不在这里绘制：它们位于固定屏幕层
## （SettlementNameTag），不会随相机缩放，也不会参与地图点击判定。

const VILLAGE_MARKER_RADIUS: float = 32.0
const VILLAGE_BORDER_WIDTH: float = 3.0
const VILLAGE_SHADOW_OFFSET_Y: float = 16.0
const VILLAGE_SHADOW_RADIUS: float = 22.0
## 旗帜最大边长刻意大于圆形内径，让四角被圆形边框裁掉。
const VILLAGE_FLAG_MAX_SIZE: float = 76.0
const VILLAGE_BORDER_COLOR: Color = Color(0.86, 0.82, 0.70, 0.95)
const VILLAGE_FALLBACK_COLOR: Color = Color(0.45, 0.50, 0.58)
const CASTLE_NAME_ANCHOR_RADIUS: float = 40.0
const CIRCLE_FLAG_SHADER_PATH: String = "res://Shaders/map_flag_circle.gdshader"

var settlement: SettlementData = null
var _family_color: Color = VILLAGE_FALLBACK_COLOR
var _has_family: bool = false
var _flag_texture: Texture2D = null
var _flag_sprite: Sprite2D = null


func setup(
	data: SettlementData,
	family: FamilyConfig = null,
	flag_texture: Texture2D = null
) -> void:
	settlement = data
	_has_family = family != null
	_family_color = family.primary_color if family != null else VILLAGE_FALLBACK_COLOR
	_flag_texture = flag_texture
	position = data.world_position if data != null else Vector2.ZERO
	_create_flag_sprite()
	queue_redraw()


## 名称层使用：返回标记顶部到名称底部的视觉半径（世界像素）。
static func get_name_anchor_radius(settlement_type: SettlementData.SettlementType) -> float:
	if settlement_type == SettlementData.SettlementType.VILLAGE:
		return VILLAGE_MARKER_RADIUS
	return CASTLE_NAME_ANCHOR_RADIUS


func get_marker_radius() -> float:
	if settlement == null or settlement.settlement_type != SettlementData.SettlementType.VILLAGE:
		return 0.0
	return VILLAGE_MARKER_RADIUS


func get_flag_max_size() -> float:
	return VILLAGE_FLAG_MAX_SIZE


func has_family_flag() -> bool:
	return _has_family and _flag_sprite != null and _flag_sprite.texture != null


func get_flag_texture_path() -> String:
	if _flag_texture == null:
		return ""
	return _flag_texture.resource_path


func _draw() -> void:
	if settlement == null:
		return
	if settlement.settlement_type == SettlementData.SettlementType.CASTLE:
		_draw_castle()
		return
	_draw_village_marker()


func _draw_village_marker() -> void:
	draw_circle(
		Vector2(0.0, VILLAGE_SHADOW_OFFSET_Y),
		VILLAGE_SHADOW_RADIUS,
		Color(0.0, 0.0, 0.0, 0.25)
	)
	draw_circle(Vector2.ZERO, VILLAGE_MARKER_RADIUS, VILLAGE_BORDER_COLOR)
	draw_circle(
		Vector2.ZERO,
		maxf(1.0, VILLAGE_MARKER_RADIUS - VILLAGE_BORDER_WIDTH),
		_family_color.darkened(0.35)
	)

	# 没有家族旗帜时绘制简易默认旗帜，避免出现空圆。
	if _flag_sprite == null or _flag_sprite.texture == null:
		var half: float = VILLAGE_FLAG_MAX_SIZE * 0.5
		draw_colored_polygon(
			PackedVector2Array([
				Vector2(-half, -half),
				Vector2(half, -half),
				Vector2(-half, half),
			]),
			_family_color.lightened(0.25)
		)
		draw_line(
			Vector2(-half, -half), Vector2(-half, half),
			Color(0.1, 0.08, 0.06, 0.9), 2.0, true
		)


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


func _create_flag_sprite() -> void:
	if _flag_sprite != null:
		_flag_sprite.queue_free()
		_flag_sprite = null
	if _flag_texture == null:
		return
	if settlement != null and settlement.settlement_type == SettlementData.SettlementType.CASTLE:
		return

	_flag_sprite = Sprite2D.new()
	_flag_sprite.name = "SettlementFlag"
	_flag_sprite.texture = _flag_texture
	_flag_sprite.centered = true
	_flag_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_flag_sprite.z_index = 1
	var texture_size: Vector2 = _flag_texture.get_size()
	var longest_side: float = maxf(texture_size.x, texture_size.y)
	if longest_side > 0.0:
		var factor: float = VILLAGE_FLAG_MAX_SIZE / longest_side
		_flag_sprite.scale = Vector2(factor, factor)
	if ResourceLoader.exists(CIRCLE_FLAG_SHADER_PATH):
		var mask_shader := load(CIRCLE_FLAG_SHADER_PATH) as Shader
		if mask_shader != null:
			var mask_material := ShaderMaterial.new()
			mask_material.shader = mask_shader
			var clip_radius: float = maxf(
				1.0, VILLAGE_MARKER_RADIUS - VILLAGE_BORDER_WIDTH * 0.5
			)
			mask_material.set_shader_parameter(
				"uv_radius",
				clampf(clip_radius / VILLAGE_FLAG_MAX_SIZE, 0.05, 0.5)
			)
			_flag_sprite.material = mask_material
	add_child(_flag_sprite)
