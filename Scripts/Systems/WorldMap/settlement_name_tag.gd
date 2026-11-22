class_name SettlementNameTag
extends Control
## 固定屏幕 UI 中的地点名称组合：圆形家族徽章 + 地点名称 + 半透明底板。
##
## 布局：徽章在左、名称在右，同一水平线居中对齐；整体位于地点原有
## 大地图美术正上方。文字与徽章尺寸不随相机缩放，位置由世界坐标换算。
## 底板只包裹“徽章 + 名称”的内容宽度，随内容动态变化。
## 名称只绑定 SettlementData.settlement_id，同名村庄不会合并。
## 整个组合忽略鼠标，不参与地点点击、选择或悬浮判定。

const TextureRegion = preload("res://Scripts/Core/World/texture_region_utils.gd")

const TAG_WIDTH: float = 240.0
const TAG_HEIGHT: float = 36.0
const BADGE_GAP: float = 8.0
## 半透明底板在内容四周的留白。
const BACKGROUND_PADDING := Vector2(10.0, 4.0)
const BACKGROUND_COLOR: Color = Color(0.05, 0.06, 0.08, 0.55)
const BACKGROUND_BORDER: Color = Color(0.86, 0.82, 0.70, 0.28)

var settlement: SettlementData = null

## 实际绑定的家族 ID；无家族时为空。用于检测家族归属变化后重建。
var _bound_family_id: String = ""
var _background: Panel = null
var _row: HBoxContainer = null
var _badge: FamilyBadge = null
var _name_label: Label = null


## 圆形家族徽章。读取 FamilyConfig 的家族旗帜美术与颜色，
## 不参与世界坐标、点击或悬浮判定。
class FamilyBadge extends Control:
	const RADIUS: float = 18.0
	const BADGE_SIZE: float = 36.0
	const BORDER_COLOR: Color = Color(0.86, 0.82, 0.70, 0.95)
	## 旗帜在徽章内可视区域中的最大边长；外圈尺寸保持不变。
	const FLAG_MAX_SIZE: float = 30.0
	const CIRCLE_FLAG_SHADER_PATH: String = "res://Shaders/map_flag_circle.gdshader"

	var _family_color: Color = Color(0.45, 0.50, 0.58)
	var family_id: String = ""
	var flag_texture_path: String = ""
	var _flag_rect: TextureRect = null

	func setup(family: FamilyConfig) -> void:
		family_id = ""
		flag_texture_path = ""
		_family_color = Color(0.45, 0.50, 0.58)
		if family != null:
			family_id = family.family_id
			_family_color = family.primary_color
			flag_texture_path = family.banner_texture_path
		_refresh_flag_texture()
		queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(BADGE_SIZE, BADGE_SIZE)
		size = custom_minimum_size
		# 旗帜是子节点；把子节点裁剪到徽章圆形绘制区域内，避免方形四角
		# 越出圆形可视范围。必须同时绘制本控件（圆形剪影底框），
		# 否则只会剩下旗帜图标与名称，圆形底板丢失。
		clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		_refresh_flag_texture()

	func _draw() -> void:
		var center := Vector2(RADIUS, RADIUS)
		draw_circle(center + Vector2(0.0, 2.0), RADIUS - 1.0, Color(0.0, 0.0, 0.0, 0.25))
		draw_circle(center, RADIUS, BORDER_COLOR)
		draw_circle(
			center,
			maxf(1.0, RADIUS - 2.5),
			_family_color.darkened(0.25)
		)
		# 缺少家族旗帜美术时，保留统一的白色旗帜图形作为回退。
		if _flag_rect == null or _flag_rect.texture == null:
			var white := Color(0.96, 0.94, 0.88, 0.96)
			draw_line(
				center + Vector2(-5.0, -9.0),
				center + Vector2(-5.0, 9.0),
				white, 2.0, true
			)
			draw_colored_polygon(
				PackedVector2Array([
					center + Vector2(-4.5, -9.0),
					center + Vector2(8.0, -5.0),
					center + Vector2(-4.5, -1.0),
				]),
				white
			)

	## 家族旗帜作为子节点绘制在圆形底色之上；正方形贴图由 clip_children 裁圆。
	func _refresh_flag_texture() -> void:
		if _flag_rect != null:
			_flag_rect.queue_free()
			_flag_rect = null
		if flag_texture_path.is_empty() or not ResourceLoader.exists(flag_texture_path):
			return
		var loaded := load(flag_texture_path) as Texture2D
		if loaded == null:
			return
		# 去掉 PNG 透明留白后再排版；像素画的有效范围按运行时计算结果裁切，
		# 不修改源美术。不同家族的旗帜因此拥有统一的实际视觉大小。
		var texture := TextureRegion.get_trimmed_texture(loaded)
		var effective_size := texture.get_size()
		_flag_rect = TextureRect.new()
		_flag_rect.name = "FamilyFlag"
		_flag_rect.texture = texture
		_flag_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_flag_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_flag_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_flag_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_flag_rect.size = Vector2(FLAG_MAX_SIZE, FLAG_MAX_SIZE)
		_flag_rect.position = Vector2(RADIUS, RADIUS) - _flag_rect.size * 0.5
		# 圆形遮罩：与部队图标共用同一 shader，旗帜不越出徽章圆形可视区域。
		if ResourceLoader.exists(CIRCLE_FLAG_SHADER_PATH):
			var mask_shader := load(CIRCLE_FLAG_SHADER_PATH) as Shader
			if mask_shader != null:
				var mask_material := ShaderMaterial.new()
				mask_material.shader = mask_shader
				mask_material.set_shader_parameter("uv_radius", 0.5)
				mask_material.set_shader_parameter(
					"uv_aspect",
					effective_size.x / maxf(1.0, effective_size.y)
				)
				_flag_rect.material = mask_material
		add_child(_flag_rect)

	func get_flag_texture_path() -> String:
		# 返回配置中的原始路径（裁切纹理是运行时 AtlasTexture，没有 resource_path）。
		return flag_texture_path

	func get_draw_center() -> Vector2:
		return Vector2(RADIUS, RADIUS)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(TAG_WIDTH, TAG_HEIGHT)
	size = Vector2(TAG_WIDTH, TAG_HEIGHT)


func setup(data: SettlementData, family: FamilyConfig = null) -> void:
	settlement = data
	_bound_family_id = family.family_id if family != null else (
		data.family_id if data != null else ""
	)
	_create_contents(family)
	queue_redraw()
	# 同步计算一次底板尺寸；WorldMap 每帧还会调用 update_background_layout()
	# 以覆盖字体/文本布局延迟变化的情况。
	_update_background()
	call_deferred("_update_background")


## anchor 为地点美术顶部上方一点的屏幕坐标；组合整体位于该点上方并水平居中。
func set_screen_position(anchor: Vector2) -> void:
	position = anchor - Vector2(TAG_WIDTH * 0.5, TAG_HEIGHT)


func get_name_text() -> String:
	return _name_label.text if _name_label != null else ""


func has_family_badge() -> bool:
	return _badge != null and _badge.visible


func get_badge() -> Control:
	return _badge


## 徽章实际绑定的家族 ID；无徽章时为空。
func get_badge_family_id() -> String:
	return _badge.family_id if _badge != null and _badge.visible else ""


## 名称标签当前绑定的地点家族 ID（含无家族时的空字符串）。
func get_bound_family_id() -> String:
	return _bound_family_id


func get_badge_flag_texture_path() -> String:
	return _badge.get_flag_texture_path() if _badge != null else ""


func get_name_label() -> Label:
	return _name_label


## 名称行容器；用于验证底板与内容的绘制顺序。
func get_row_control() -> HBoxContainer:
	return _row


## 半透明底板；只用于测试与布局校验，不参与交互。
func get_background_control() -> Panel:
	return _background


func _create_contents(family: FamilyConfig) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_background = null
	_row = null
	_badge = null
	_name_label = null

	# 半透明底板位于内容之后（先添加 => 绘制在底层），尺寸由内容决定。
	_background = Panel.new()
	_background.name = "SettlementNameBackground"
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background_style := StyleBoxFlat.new()
	background_style.bg_color = BACKGROUND_COLOR
	background_style.border_color = BACKGROUND_BORDER
	background_style.set_border_width_all(1)
	background_style.set_corner_radius_all(8)
	_background.add_theme_stylebox_override("panel", background_style)
	add_child(_background)

	_row = HBoxContainer.new()
	_row.name = "SettlementNameRow"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", int(BADGE_GAP))
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_row)

	_badge = FamilyBadge.new()
	_badge.name = "SettlementFamilyBadge"
	_badge.visible = family != null
	_badge.setup(family)
	# 徽章与文字都按自身最小高度在名称行内垂直居中，
	# 不拉伸、不整体位移，修复图标与文本的上下错位。
	_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(_badge)

	_name_label = Label.new()
	_name_label.name = "SettlementNameLabel"
	_name_label.text = settlement.display_name if settlement != null else ""
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.theme = UiTheme.create()
	_name_label.add_theme_font_size_override("font_size", 15)
	_name_label.add_theme_color_override("font_color", Color("#f3ead6"))
	_name_label.add_theme_color_override(
		"font_shadow_color", Color(0.0, 0.0, 0.0, 0.85)
	)
	_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)
	_row.add_child(_name_label)

	# 名称或徽章变化时底板跟随内容尺寸，不写死宽度。
	if not _row.resized.is_connected(_update_background):
		_row.resized.connect(_update_background)


## 供 WorldMap 每帧同步底板尺寸；内容未变化时只是重复写同样的值。
func update_background_layout() -> void:
	_update_background()


## 根据“徽章 + 名称”的实际最小尺寸计算底板，并保持整体居中。
func _update_background() -> void:
	if _background == null or _row == null:
		return
	var content_size := _row.get_combined_minimum_size()
	var background_size := Vector2(
		content_size.x + BACKGROUND_PADDING.x * 2.0,
		content_size.y + BACKGROUND_PADDING.y * 2.0
	)
	background_size.x = minf(background_size.x, TAG_WIDTH)
	background_size.y = minf(background_size.y, TAG_HEIGHT)
	_background.size = background_size
	_background.position = (size - background_size) * 0.5
