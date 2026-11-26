class_name UnitVisual
extends Node2D
## 士兵最终组合表现：统一组合 HumanVisual 与 HorseVisual。
##
## 人物与马匹贴图分别管理，但两者的 Sprite2D 都位于 z_index = 0 的子组中，
## 因此 VisualLayers 的相对 z 可以跨组形成最终遮挡顺序。
## 本类只读取 UnitData 的阵营与骑乘状态，不修改属性、装备或战斗数据。

const HumanVisualScript = preload("res://Scripts/Systems/Combat/human_visual.gd")
const HorseVisualScript = preload("res://Scripts/Systems/Combat/horse_visual.gd")

## 近战攻击进入有效命中帧时转发给 UnitActor；伤害结算由 UnitController 负责。
signal attack_hit_frame()

## 士兵部件统一使用阵营罩袍 shader；非罩袍部件通过同一 shader 的普通模式显示原色。
const UNIT_SHADER_PATH: String = "res://Shaders/faction_tabard.gdshader"
const FLASH_SHADER_PARAM: String = "flash_amount"
const SHADOW_PART_NAMES: Array[String] = ["FootShadow", "MountShadow"]

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
## 可选的外部影子层。战斗场景把所有士兵影子集中到角色层之下，
## 保证任何影子都不会覆盖其他士兵的身体/武器/头部。
var _shadow_layer: Node2D = null
var _detached_shadows: Array[Sprite2D] = []
## 每个 UnitVisual 拥有自己的材质实例：白闪参数只影响当前角色，
## 不会污染其他角色；材质在 rebuild 后重新绑定到所有部件。
var _flash_material: ShaderMaterial = null
var _tabard_material: ShaderMaterial = null
var _flash_strength: float = 0.0
## 尸体淡出：人物/马匹通过本节点 modulate 统一降低透明度；
## 影子已移出本子树，需要保存各自基准 alpha 后单独乘淡出系数。
var _corpse_alpha: float = 1.0
var _corpse_shadow_base_alphas: Array[float] = []


func setup(data: UnitData, equipment_configs: Dictionary = {}) -> void:
	unit_data = data
	_equipment_configs = equipment_configs.duplicate()
	_ensure_groups()
	if unit_data == null:
		_release_detached_shadows()
		_human_visual.clear_parts()
		_horse_visual.clear_parts()
		_horse_visual.visible = false
		_mounted = false
		return
	rebuild()


func rebuild() -> void:
	_ensure_groups()
	_corpse_alpha = 1.0
	modulate.a = 1.0
	_corpse_shadow_base_alphas.clear()
	if unit_data == null:
		_release_detached_shadows()
		_human_visual.clear_parts()
		_horse_visual.clear_parts()
		_horse_visual.visible = false
		_mounted = false
		return

	# 重建部件前先释放旧的外部影子，旧 Sprite 不属于 Human/Horse 子节点。
	_release_detached_shadows()

	# 外观选择（家族罩袍、领袖缨饰、等级头盔、家族长矛）在创建时一次性
	# 写入 UnitData.appearance；本类只消费最终结果，不包含任何家族分支规则。
	var appearance := UnitAppearance.get_appearance(unit_data)
	var tabard_texture_path: String = str(
		appearance.get("tabard_texture_path", "")
	)
	var plume_texture_path: String = _plume_texture_path
	if plume_texture_path.is_empty():
		plume_texture_path = str(appearance.get("plume_texture_path", ""))
	# 国王盔与普通头盔缨饰互斥：身份覆盖生效时只隐藏本次表现层的缨饰，
	# 不修改 appearance/装备；下一次重建若身份失效会自动恢复原缨饰。
	if not UnitAppearance.get_king_helmet_texture_path(unit_data).is_empty():
		plume_texture_path = ""
	_human_visual.rebuild(
		get_tabard_color(), plume_texture_path, tabard_texture_path
	)
	_apply_equipment_visuals()
	var mount := unit_data.get_mount_instance_data()
	var coat_style_id: String = mount.coat_style_id if mount != null else "brown"
	var saddle_style_id: String = mount.saddle_style_id if mount != null else "saddle_01"
	_horse_visual.rebuild(coat_style_id, saddle_style_id)
	_apply_hit_flash_materials()
	set_mounted(unit_data.is_mounted)
	set_facing(_facing)
	_attach_shadows_to_layer()


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
	var helmet_texture_path: String = ""
	var helmet_layer: int = 0
	var helmet_anchor := Vector2(-1.0, -1.0)
	var head := _equipment_configs.get("HEAD") as EquipmentConfig
	if head != null and unit_data.equipment.has("HEAD") \
			and not head.visual_texture_path.is_empty():
		helmet_texture_path = head.visual_texture_path
		helmet_layer = head.visual_layer
		helmet_anchor = head.visual_anchor
	else:
		helmet_texture_path = str(appearance.get("helmet_texture_path", ""))
	if not helmet_texture_path.is_empty():
		_apply_helmet_visual(helmet_texture_path, helmet_layer, helmet_anchor)


## 国王身份只覆盖“本应显示的头盔”；没有普通头盔时不会凭空添加。
## 覆盖结果不写入装备或外观数据，身份失效后下一次重建自动恢复原头盔。
func _apply_helmet_visual(
	texture_path: String, layer_override: int, anchor_pixels: Vector2
) -> void:
	var king_helmet_path: String = UnitAppearance.get_king_helmet_texture_path(
		unit_data
	)
	if not king_helmet_path.is_empty():
		_human_visual.set_helmet_texture(king_helmet_path)
		return
	_human_visual.set_helmet_texture(texture_path, layer_override, anchor_pixels)


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
	_sync_shadow_visibility()


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


## 指定外部影子层；传入 null 时影子回到人物/马匹组内部（默认行为）。
## 影子 Sprite 仍由 HumanVisual/HorseVisual 创建和驱动动画，
## 这里只改变它们的父节点，因此不复制任何动画逻辑。
func set_shadow_layer(layer: Node2D) -> void:
	if _shadow_layer == layer:
		return
	_release_detached_shadows()
	_shadow_layer = layer
	if unit_data != null:
		_attach_shadows_to_layer()


func get_shadow_layer() -> Node2D:
	return _shadow_layer


func get_detached_shadow_count() -> int:
	return _detached_shadows.size()


## 影子整体移出角色原子子树后，仍保留自身相对层级（同为 -99）。
## 影子层由战斗场景统一放在角色层之下，因此不会覆盖任何士兵主体。
func _attach_shadows_to_layer() -> void:
	if _shadow_layer == null or not is_instance_valid(_shadow_layer):
		return
	if not is_inside_tree() or not _shadow_layer.is_inside_tree():
		return
	var groups: Array[Node2D] = [_human_visual, _horse_visual]
	for group: Node2D in groups:
		if group == null or not is_instance_valid(group):
			continue
		for part_name: String in ["FootShadow", "MountShadow"]:
			var sprite: Sprite2D = group.get_part(part_name)
			if sprite == null:
				continue
			# remove_child 不会清空 PartVisual._sprites 中的引用，
			# 因此动画更新（马影缩放/透明度）仍会作用于同一个 Sprite。
			group.remove_child(sprite)
			_shadow_layer.add_child(sprite)
			sprite.position = Vector2.ZERO
			sprite.rotation = 0.0
			_detached_shadows.append(sprite)
	_sync_shadow_visibility()


## 释放已移出的影子 Sprite；下一轮 rebuild 会重新创建并再次移出。
func _release_detached_shadows() -> void:
	if _detached_shadows.is_empty():
		return
	var groups: Array[Node2D] = [_human_visual, _horse_visual]
	for group: Node2D in groups:
		if group == null or not is_instance_valid(group):
			continue
		for part_name: String in ["FootShadow", "MountShadow"]:
			var sprite: Sprite2D = group.get_part(part_name)
			if sprite != null and _detached_shadows.has(sprite):
				# remove_part 会同时从 _sprites 字典移除并 queue_free。
				group.remove_part(part_name)
	_detached_shadows.clear()


## 影子移出马匹/人物组后不再继承其 visible，需要按骑乘状态单独同步。
func _sync_shadow_visibility() -> void:
	for sprite: Sprite2D in _detached_shadows:
		if sprite == null or not is_instance_valid(sprite):
			continue
		if sprite.name == "Part_FootShadow":
			sprite.visible = not _mounted
		elif sprite.name == "Part_MountShadow":
			sprite.visible = _mounted


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
	reset_hit_reaction()
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


## 统一白闪：0 恢复原色，1 全白。人物与马匹的所有可见部件共用本角色的材质实例。
func set_hit_flash_strength(strength: float) -> void:
	var clamped: float = clampf(strength, 0.0, 1.0)
	if is_equal_approx(clamped, _flash_strength):
		return
	_flash_strength = clamped
	if _flash_material != null:
		_flash_material.set_shader_parameter(FLASH_SHADER_PARAM, clamped)
	if _tabard_material != null:
		_tabard_material.set_shader_parameter(FLASH_SHADER_PARAM, clamped)


func get_hit_flash_strength() -> float:
	return _flash_strength


# ---------------------------------------------------------------------------
# 死亡倒地与尸体淡出
# ---------------------------------------------------------------------------


## 开始倒地表现：人物向背后倒下，骑乘单位的马匹同时塌陷。
## 倒地姿态锁定后，普通待机/跑动/受击动画不会再覆盖。
func play_death_fall(duration: float) -> void:
	reset_hit_reaction()
	if _human_visual != null:
		_human_visual.play_death_fall(duration)
	if _horse_visual != null:
		_horse_visual.play_death_collapse(duration)


## 推进倒地动画；返回人物与马匹是否都已完成。
func advance_death_animation(delta: float) -> bool:
	var human_done: bool = true
	var horse_done: bool = true
	if _human_visual != null:
		human_done = bool(_human_visual.advance_death_animation(delta))
	if _horse_visual != null:
		horse_done = bool(_horse_visual.advance_death_animation(delta))
	return human_done and horse_done


## 记录影子当前透明度，作为淡出的基准；尸体淡出只缩放该值，不覆盖影子自身动画。
func capture_corpse_shadow_alpha() -> void:
	_corpse_shadow_base_alphas.clear()
	for sprite: Sprite2D in _detached_shadows:
		if sprite != null and is_instance_valid(sprite):
			_corpse_shadow_base_alphas.append(sprite.modulate.a)


## 统一尸体透明度：人物、马匹、武器、装备与影子一起淡出。
## 使用节点 modulate 而不是共享材质，避免影响其他角色。
func set_corpse_alpha(alpha: float) -> void:
	var clamped: float = clampf(alpha, 0.0, 1.0)
	_corpse_alpha = clamped
	modulate.a = clamped
	if _corpse_shadow_base_alphas.size() != _detached_shadows.size():
		capture_corpse_shadow_alpha()
	for i: int in range(_detached_shadows.size()):
		var sprite: Sprite2D = _detached_shadows[i]
		if sprite == null or not is_instance_valid(sprite):
			continue
		var base_alpha: float = (
			_corpse_shadow_base_alphas[i]
			if i < _corpse_shadow_base_alphas.size() else 1.0
		)
		sprite.modulate.a = base_alpha * clamped


func get_corpse_alpha() -> float:
	return _corpse_alpha


## 受击时取消当前攻击表现；未到有效帧的伤害由 UnitController 负责取消。
func cancel_attack_animation() -> void:
	if _human_visual != null:
		_human_visual.cancel_attack_animation()


func play_hit_reaction(direction: Vector2 = Vector2.ZERO) -> void:
	if _human_visual != null:
		_human_visual.play_hit_reaction(direction)


func get_hit_reaction_local_direction() -> Vector2:
	if _human_visual != null:
		return _human_visual.get_hit_reaction_local_direction()
	return Vector2.ZERO


func is_hit_reacting() -> bool:
	return _human_visual != null and _human_visual.is_hit_reacting()


func reset_hit_reaction() -> void:
	if _human_visual != null:
		_human_visual.reset_hit_reaction()


func play_attack_animation(direction: Vector2 = Vector2.LEFT) -> bool:
	if _human_visual == null:
		return false
	return bool(_human_visual.play_attack_animation(direction))


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
	if _human_visual.has_signal("attack_hit_frame"):
		var handler := Callable(self, "_on_human_attack_hit_frame")
		if not _human_visual.is_connected("attack_hit_frame", handler):
			_human_visual.connect("attack_hit_frame", handler)


## 把本角色专用的白闪材质绑定到人物与马匹的全部可见部件。
## 影子与阵营罩袍单独处理：影子不闪，罩袍保留自己的阵营材质但同步 flash 参数。
func _apply_hit_flash_materials() -> void:
	_tabard_material = null
	if _flash_material == null:
		_flash_material = _create_flash_material()
	_apply_flash_to_group(_human_visual)
	_apply_flash_to_group(_horse_visual)
	if _flash_material != null:
		_flash_material.set_shader_parameter(FLASH_SHADER_PARAM, _flash_strength)
	if _tabard_material != null:
		_tabard_material.set_shader_parameter(FLASH_SHADER_PARAM, _flash_strength)


func _apply_flash_to_group(group: Node2D) -> void:
	if group == null or not is_instance_valid(group):
		return
	for part_name_value: Variant in group.get_parts().keys():
		var part_name := str(part_name_value)
		if SHADOW_PART_NAMES.has(part_name):
			continue
		var sprite: Sprite2D = group.get_part(part_name)
		if sprite == null:
			continue
		if part_name == "Tabard":
			# 占位罩袍使用自己的阵营材质；家族罩袍没有材质，走普通白闪。
			var tabard_material := sprite.material as ShaderMaterial
			if tabard_material != null and bool(
				tabard_material.get_shader_parameter("use_faction_color")
			):
				_tabard_material = tabard_material
				continue
		if _flash_material != null:
			sprite.material = _flash_material


func _create_flash_material() -> ShaderMaterial:
	if not ResourceLoader.exists(UNIT_SHADER_PATH):
		return null
	var shader := load(UNIT_SHADER_PATH) as Shader
	if shader == null:
		return null
	var flash_material := ShaderMaterial.new()
	flash_material.shader = shader
	flash_material.set_shader_parameter("use_faction_color", false)
	flash_material.set_shader_parameter(FLASH_SHADER_PARAM, _flash_strength)
	return flash_material


func _on_human_attack_hit_frame() -> void:
	attack_hit_frame.emit()
