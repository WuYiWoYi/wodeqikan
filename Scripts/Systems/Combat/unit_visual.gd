class_name UnitVisual
extends Node2D
## 士兵最终组合表现：统一组合 HumanVisual 与 HorseVisual。
##
## 人物与马匹贴图分别管理，但两者的 Sprite2D 都位于 z_index = 0 的子组中，
## 因此 VisualLayers 的相对 z 可以跨组形成最终遮挡顺序。
## 本类只读取 UnitData 的阵营与骑乘状态，不修改属性、装备或战斗数据。

const HumanVisualScript = preload("res://Scripts/Systems/Combat/human_visual.gd")
const HorseVisualScript = preload("res://Scripts/Systems/Combat/horse_visual.gd")

const FACTION_COLORS: Dictionary = {
	"FACTION_PLAYER": Color(0.25, 0.48, 0.88),
	"FACTION_LOCAL": Color(0.30, 0.55, 0.34),
	"FACTION_MERCHANT": Color(0.78, 0.60, 0.18),
	"FACTION_BANDIT": Color(0.66, 0.20, 0.18),
	"FACTION_GUARD": Color(0.20, 0.55, 0.58),
}
const DEFAULT_FACTION_COLOR: Color = Color(0.45, 0.50, 0.58)
const LOCOMOTION_BLEND_TIME: float = 0.18

var unit_data: UnitData = null
var _human_visual: Node2D = null
var _horse_visual: Node2D = null
## { slot_name: EquipmentConfig }，用于头部/左手/右手装备表现；为空时使用默认长矛与头部。
var _equipment_configs: Dictionary = {}
var _facing: float = -1.0
var _mounted: bool = false
var _plume_texture_path: String = HumanVisualScript.PLUME_TEXTURE_PATH
var _idle_time: float = 0.0
var _run_time: float = 0.0
var _locomotion_blend: float = 0.0
var _locomotion_moving: bool = false


func setup(data: UnitData, equipment_configs: Dictionary = {}) -> void:
	unit_data = data
	_equipment_configs = equipment_configs.duplicate()
	_ensure_groups()
	if unit_data == null:
		_human_visual.clear_parts()
		_horse_visual.clear_parts()
		_horse_visual.visible = false
		_mounted = false
		return
	rebuild()


func rebuild() -> void:
	_ensure_groups()
	if unit_data == null:
		_human_visual.clear_parts()
		_horse_visual.clear_parts()
		_horse_visual.visible = false
		_mounted = false
		return

	# 外观选择（家族罩袍、领袖缨饰、等级头盔、家族长矛）在创建时一次性
	# 写入 UnitData.appearance；本类只消费最终结果，不包含任何家族分支规则。
	var appearance := UnitAppearance.get_appearance(unit_data)
	var tabard_texture_path: String = str(
		appearance.get("tabard_texture_path", "")
	)
	var plume_texture_path: String = _plume_texture_path
	if plume_texture_path.is_empty():
		plume_texture_path = str(appearance.get("plume_texture_path", ""))
	_human_visual.rebuild(
		get_tabard_color(), plume_texture_path, tabard_texture_path
	)
	_apply_equipment_visuals()
	_horse_visual.rebuild()
	set_mounted(unit_data.is_mounted)
	set_facing(_facing)


## 根据装备槽位的视觉配置替换/增加部件；缺少贴图时保持默认表现。
func _apply_equipment_visuals() -> void:
	var appearance := UnitAppearance.get_appearance(unit_data)
	var weapon_applied: bool = false
	var weapon := _equipment_configs.get("WEAPON") as EquipmentConfig
	if weapon != null and unit_data.equipment.has("WEAPON") \
			and not weapon.visual_texture_path.is_empty():
		_human_visual.set_right_hand_weapon_texture(
			weapon.visual_texture_path, weapon.visual_layer, weapon.visual_anchor
		)
		weapon_applied = true
	# 没有武器装备时使用家族长矛；它只改变表现，不改变武器/属性数据。
	if not weapon_applied:
		var family_spear: String = str(appearance.get("spear_texture_path", ""))
		if not family_spear.is_empty():
			_human_visual.set_right_hand_weapon_texture(family_spear)

	var offhand := _equipment_configs.get("OFFHAND") as EquipmentConfig
	if offhand != null and unit_data.equipment.has("OFFHAND") \
			and not offhand.visual_texture_path.is_empty():
		_human_visual.set_left_hand_weapon_texture(
			offhand.visual_texture_path, offhand.visual_layer, offhand.visual_anchor
		)

	# 装备头盔优先；没有 HEAD 装备时显示按等级随机并持久化的外观头盔。
	var head_applied: bool = false
	var head := _equipment_configs.get("HEAD") as EquipmentConfig
	if head != null and unit_data.equipment.has("HEAD") \
			and not head.visual_texture_path.is_empty():
		_human_visual.set_helmet_texture(
			head.visual_texture_path, head.visual_layer, head.visual_anchor
		)
		head_applied = true
	if not head_applied:
		var appearance_helmet: String = str(
			appearance.get("helmet_texture_path", "")
		)
		if not appearance_helmet.is_empty():
			_human_visual.set_helmet_texture(appearance_helmet)


## 运行时更新装备视觉配置并重建部件；不修改 UnitData 的装备数据。
func set_equipment_configs(equipment_configs: Dictionary) -> void:
	_equipment_configs = equipment_configs.duplicate()
	if unit_data != null:
		rebuild()


func set_mounted(mounted: bool) -> void:
	_mounted = mounted
	if _human_visual == null or _horse_visual == null:
		return
	_human_visual.set_mounted(mounted)
	_horse_visual.visible = mounted


func set_facing(direction_x: float) -> void:
	if absf(direction_x) < 0.01:
		return
	var new_facing: float = 1.0 if direction_x > 0.0 else -1.0
	_facing = new_facing
	if _human_visual != null:
		_human_visual.set_facing(_facing)
	if _horse_visual != null:
		_horse_visual.set_facing(_facing)


func get_facing() -> float:
	return _facing


## 由 UnitActor 按实际移动状态调用；人物与马匹共享时间轴，保证骑乘时动作协调。
func update_locomotion(delta: float, is_moving: bool) -> void:
	_locomotion_moving = is_moving
	_idle_time += delta
	_run_time += delta
	var target: float = 1.0 if is_moving else 0.0
	_locomotion_blend = move_toward(
		_locomotion_blend, target, delta / LOCOMOTION_BLEND_TIME
	)
	# 先推进马匹整体姿态，再让骑手跟随马身垂直偏移。
	if _horse_visual != null:
		_horse_visual.update_locomotion(
			_idle_time, _run_time, _locomotion_blend, delta
		)
	var rider_offset_y: float = (
		_horse_visual.get_body_offset_y()
		if _mounted and _horse_visual != null else 0.0
	)
	if _human_visual != null:
		_human_visual.update_locomotion(
			_idle_time, _run_time, _locomotion_blend, delta, rider_offset_y
		)


## 重置共享动画时间轴到待机起点；用于 UI 预览切换等需要干净状态的场景。
func reset_locomotion() -> void:
	_idle_time = 0.0
	_run_time = 0.0
	_locomotion_blend = 0.0
	_locomotion_moving = false
	if _horse_visual != null:
		_horse_visual.update_locomotion(0.0, 0.0, 0.0, 0.0)
	var rider_offset_y: float = (
		_horse_visual.get_body_offset_y()
		if _mounted and _horse_visual != null else 0.0
	)
	if _human_visual != null:
		_human_visual.update_locomotion(0.0, 0.0, 0.0, 0.0, rider_offset_y)


func is_locomotion_moving() -> bool:
	return _locomotion_moving


func get_locomotion_blend() -> float:
	return _locomotion_blend


## 仅改变本次场景中的武器表现；不影响装备数据或存档。
func set_weapon_visible(value: bool) -> void:
	if _human_visual != null:
		_human_visual.set_weapon_visible(value)


func is_weapon_visible() -> bool:
	return _human_visual != null and _human_visual.is_weapon_visible()


func set_attack_flash(active: bool) -> void:
	if _human_visual != null:
		_human_visual.set_attack_flash(active)


func play_attack_animation(direction: Vector2 = Vector2.LEFT) -> void:
	if _human_visual != null:
		_human_visual.play_attack_animation(direction)


func play_ranged_attack_animation(direction: Vector2 = Vector2.LEFT) -> void:
	if _human_visual != null:
		_human_visual.play_ranged_attack_animation(direction)


func advance_animation(delta: float) -> void:
	if _human_visual != null:
		_human_visual.advance_animation(delta)


func get_weapon_pivot() -> Node2D:
	return _human_visual.get_weapon_pivot() if _human_visual != null else null


func get_weapon_rotation() -> float:
	return _human_visual.get_weapon_rotation() if _human_visual != null else 0.0


func get_attack_target_rotation() -> float:
	return _human_visual.get_attack_target_rotation() if _human_visual != null else 0.0


func is_attack_animating() -> bool:
	return _human_visual.is_attack_animating() if _human_visual != null else false


## 挥动/刺出阶段才锁定朝向；攻击后的保持与恢复姿态允许转身移动。
func is_attack_pose_locked() -> bool:
	return _human_visual.is_attack_pose_locked() if _human_visual != null else false


## 预留：不同士兵/装备可以指定不同缨饰贴图；空路径表示不显示。
func set_plume_texture(texture_path: String) -> void:
	_plume_texture_path = texture_path
	if unit_data != null:
		rebuild()


func get_part(part_name: String) -> Sprite2D:
	if _human_visual != null:
		var human_part: Sprite2D = _human_visual.get_part(part_name)
		if human_part != null:
			return human_part
	if _horse_visual != null:
		return _horse_visual.get_part(part_name)
	return null


func has_part(part_name: String) -> bool:
	return get_part(part_name) != null


func get_parts() -> Dictionary:
	var result: Dictionary = {}
	if _human_visual != null:
		result.merge(_human_visual.get_parts(), true)
	if _horse_visual != null:
		result.merge(_horse_visual.get_parts(), true)
	return result


func get_part_effective_z(part_name: String) -> int:
	if _human_visual != null and _human_visual.has_part(part_name):
		return _human_visual.get_part_effective_z(part_name)
	if _horse_visual != null and _horse_visual.has_part(part_name):
		return _horse_visual.get_part_effective_z(part_name)
	return 0


func is_mounted_visual() -> bool:
	return _mounted


func get_faction_color() -> Color:
	if unit_data == null:
		return DEFAULT_FACTION_COLOR
	return FACTION_COLORS.get(unit_data.faction_id, DEFAULT_FACTION_COLOR)


## 罩袍着色优先级：家族外观持久化的颜色 > 阵营默认色。
## 家族贴图存在时颜色不会覆盖贴图，仅作为缺失资源时的回退。
func get_tabard_color() -> Color:
	if unit_data == null:
		return DEFAULT_FACTION_COLOR
	var color_text: String = UnitAppearance.get_appearance(unit_data).get(
		"tabard_color", ""
	)
	if color_text.is_empty():
		return get_faction_color()
	return Color.from_string(color_text, get_faction_color())


func get_human_visual() -> Node2D:
	return _human_visual


func get_horse_visual() -> Node2D:
	return _horse_visual


func _ensure_groups() -> void:
	if _human_visual == null or not is_instance_valid(_human_visual):
		_human_visual = HumanVisualScript.new()
		_human_visual.name = "HumanVisual"
		add_child(_human_visual)
	if _horse_visual == null or not is_instance_valid(_horse_visual):
		_horse_visual = HorseVisualScript.new()
		_horse_visual.name = "HorseVisual"
		add_child(_horse_visual)
