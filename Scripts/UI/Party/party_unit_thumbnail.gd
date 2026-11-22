class_name PartyUnitThumbnail
extends Control
## 部队面板列表项的士兵头像缩略图。
##
## 复用战斗表现层的 UnitVisual（人物/马匹/家族外观/装备贴图），不猜测
## 不存在的头像资源路径；没有有效单位时绘制安全的默认头肩剪影。
## 所有条目共用固定视口尺寸、缩放与脚底锚点，避免不同头像大小不一。

const UnitVisualScript = preload("res://Scripts/Systems/Combat/unit_visual.gd")

const THUMB_SIZE := Vector2(48.0, 56.0)
const VIEWPORT_SIZE := Vector2i(48, 56)
const VISUAL_SCALE: float = 0.8
const FEET_POSITION := Vector2(24.0, 53.0)

const FALLBACK_BODY: Color = Color(0.27, 0.29, 0.34, 1.0)
const FALLBACK_HEAD: Color = Color(0.36, 0.38, 0.43, 1.0)
const FALLBACK_BORDER: Color = Color(0.55, 0.52, 0.44, 0.75)

var _viewport_container: SubViewportContainer = null
var _viewport: SubViewport = null
var _visual: UnitVisual = null
var _has_unit: bool = false


func _init() -> void:
	name = "UnitThumbnail"
	custom_minimum_size = THUMB_SIZE
	size = THUMB_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_build()


func setup(unit: UnitData, equipment_configs: Dictionary = {}) -> void:
	_has_unit = unit != null
	if _visual != null:
		if _has_unit:
			_visual.setup(unit, equipment_configs)
			_visual.set_facing(-1.0)
			_visual.reset_locomotion()
		else:
			_visual.setup(null)
	if _viewport_container != null:
		_viewport_container.visible = _has_unit
	queue_redraw()


func has_unit_visual() -> bool:
	return _has_unit and _visual != null and _visual.unit_data != null


func get_unit_visual() -> UnitVisual:
	return _visual


func _process(delta: float) -> void:
	if _visual == null or _visual.unit_data == null:
		return
	if not is_visible_in_tree():
		return
	_visual.update_locomotion(delta, false)


func _draw() -> void:
	# 无有效单位时的默认头肩剪影，保证条目仍有稳定占位图。
	if _has_unit:
		return
	var area := size
	if area.x <= 0.0 or area.y <= 0.0:
		area = THUMB_SIZE
	draw_rect(Rect2(Vector2.ZERO, area), Color(0.08, 0.09, 0.11, 0.35), true)
	draw_rect(Rect2(Vector2.ZERO, area), FALLBACK_BORDER, false, 1.0)
	var center_x: float = area.x * 0.5
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(area.x * 0.20, area.y * 0.92),
			Vector2(area.x * 0.30, area.y * 0.62),
			Vector2(area.x * 0.70, area.y * 0.62),
			Vector2(area.x * 0.80, area.y * 0.92),
		]),
		FALLBACK_BODY
	)
	draw_circle(Vector2(center_x, area.y * 0.44), area.x * 0.17, FALLBACK_HEAD)
	draw_circle(
		Vector2(center_x, area.y * 0.44), area.x * 0.17, FALLBACK_BORDER, false, 1.0
	)


func _build() -> void:
	_viewport_container = SubViewportContainer.new()
	_viewport_container.name = "ThumbnailViewportContainer"
	_viewport_container.stretch = true
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport_container.visible = false
	_viewport_container.anchor_left = 0.0
	_viewport_container.anchor_top = 0.0
	_viewport_container.anchor_right = 1.0
	_viewport_container.anchor_bottom = 1.0
	_viewport_container.offset_left = 0.0
	_viewport_container.offset_top = 0.0
	_viewport_container.offset_right = 0.0
	_viewport_container.offset_bottom = 0.0
	add_child(_viewport_container)

	_viewport = SubViewport.new()
	_viewport.name = "ThumbnailViewport"
	_viewport.size = VIEWPORT_SIZE
	_viewport.transparent_bg = true
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_viewport_container.add_child(_viewport)

	var preview_root := Node2D.new()
	preview_root.name = "ThumbnailRoot"
	_viewport.add_child(preview_root)

	_visual = UnitVisualScript.new()
	_visual.name = "ThumbnailUnitVisual"
	_visual.position = FEET_POSITION
	_visual.scale = Vector2(VISUAL_SCALE, VISUAL_SCALE)
	preview_root.add_child(_visual)
