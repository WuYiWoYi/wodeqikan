class_name EncounterPortrait
extends Control
## 遭遇对话中的 NPC 领袖头像/剪影。
##
## 复用战斗表现层的 UnitVisual，不复制角色美术系统。
## 没有有效领袖数据时绘制安全默认剪影，保证 UI 不报错。

const UnitVisualScript = preload("res://Scripts/Systems/Combat/unit_visual.gd")

const PORTRAIT_SIZE := Vector2(180.0, 220.0)
const PREVIEW_VIEWPORT_SIZE := Vector2i(180, 220)
const PREVIEW_SCALE: float = 1.45
const PREVIEW_FEET_POSITION := Vector2(90.0, 202.0)

const FALLBACK_BACKGROUND: Color = Color(0.08, 0.09, 0.11, 0.85)
const FALLBACK_BORDER: Color = Color(0.62, 0.58, 0.48, 0.8)
const FALLBACK_BODY: Color = Color(0.24, 0.26, 0.30, 1.0)
const FALLBACK_HEAD: Color = Color(0.30, 0.32, 0.37, 1.0)

var _unit_manager: UnitManager = null
var _unit: UnitData = null
var _viewport_container: SubViewportContainer = null
var _viewport: SubViewport = null
var _visual: UnitVisual = null


func _init() -> void:
	name = "EncounterPortrait"
	custom_minimum_size = PORTRAIT_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_build_viewport()


func setup(unit_manager: UnitManager) -> void:
	_unit_manager = unit_manager


## 显示领袖角色；无效单位（null / 已阵亡）自动回退到默认剪影。
func show_leader(unit: UnitData) -> void:
	_unit = unit if unit != null and unit.is_alive() else null
	if _viewport_container != null:
		_viewport_container.visible = _unit != null
	if _unit != null and _visual != null:
		_visual.setup(_unit, _visual_equipment_configs(_unit))
		_visual.set_facing(-1.0)
		_visual.reset_locomotion()
	queue_redraw()


func clear() -> void:
	show_leader(null)


func has_leader_visual() -> bool:
	return _unit != null


func get_leader_unit_id() -> String:
	return _unit.unit_id if _unit != null else ""


func _process(delta: float) -> void:
	if _visual == null or _unit == null or not is_visible_in_tree():
		return
	_visual.update_locomotion(delta, false)


func _draw() -> void:
	if _unit != null:
		return
	var area: Vector2 = size
	if area.x <= 0.0 or area.y <= 0.0:
		area = PORTRAIT_SIZE
	var center := Vector2(area.x * 0.5, area.y * 0.5)
	draw_rect(Rect2(Vector2.ZERO, area), FALLBACK_BACKGROUND, true)
	draw_rect(Rect2(Vector2.ZERO, area), FALLBACK_BORDER, false, 2.0)
	# 头肩剪影：不依赖任何角色资源，缺领袖数据时仍能保持对话式布局。
	var shoulder_y: float = area.y * 0.78
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(area.x * 0.18, shoulder_y),
			Vector2(area.x * 0.30, area.y * 0.56),
			Vector2(area.x * 0.70, area.y * 0.56),
			Vector2(area.x * 0.82, shoulder_y),
			Vector2(area.x * 0.82, area.y * 0.94),
			Vector2(area.x * 0.18, area.y * 0.94),
		]),
		FALLBACK_BODY
	)
	draw_circle(Vector2(center.x, area.y * 0.42), area.x * 0.16, FALLBACK_HEAD)
	draw_circle(
		Vector2(center.x, area.y * 0.42), area.x * 0.16, FALLBACK_BORDER, false, 2.0
	)


func _build_viewport() -> void:
	_viewport_container = SubViewportContainer.new()
	_viewport_container.name = "PortraitViewportContainer"
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
	_viewport.name = "PortraitViewport"
	_viewport.size = PREVIEW_VIEWPORT_SIZE
	_viewport.transparent_bg = true
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_viewport_container.add_child(_viewport)

	var preview_root := Node2D.new()
	preview_root.name = "PortraitRoot"
	_viewport.add_child(preview_root)

	_visual = UnitVisualScript.new()
	_visual.name = "PortraitUnitVisual"
	_visual.position = PREVIEW_FEET_POSITION
	_visual.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	preview_root.add_child(_visual)


func _visual_equipment_configs(unit: UnitData) -> Dictionary:
	var configs: Dictionary = {}
	if unit == null or _unit_manager == null:
		return configs
	for slot_key_value: Variant in unit.equipment.keys():
		var slot_key: String = str(slot_key_value)
		var equipment_id: String = str(unit.equipment.get(slot_key_value, ""))
		var equipment := _unit_manager.get_equipment_config(equipment_id)
		if equipment != null:
			configs[slot_key] = equipment
	return configs
