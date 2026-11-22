class_name UnitDetailPanel
extends VBoxContainer
## 部队面板右侧的士兵详情。
##
## 只读取 UnitManager 中的最终属性缓存与静态配置；不计算属性、不修改数据。

const EQUIPMENT_SLOT_ORDER: Array[String] = ["WEAPON", "OFFHAND", "HEAD", "BODY", "MOUNT"]
const EQUIPMENT_SLOT_LABELS: Array[String] = ["武器", "副手", "头盔", "盔甲", "坐骑"]
const UnitVisualScript = preload("res://Scripts/Systems/Combat/unit_visual.gd")

## 通过管理器完成装备/晋升后发出，由 PartyPanel 刷新概览与成员列表。
signal unit_changed

const PREVIEW_VIEWPORT_SIZE := Vector2i(180, 200)
const PREVIEW_SCALE: float = 1.6
const PREVIEW_FEET_POSITION := Vector2(90.0, 180.0)

var _context: WorldContext = null
var _preview_viewport: SubViewport = null
var _preview_visual: UnitVisual = null

var _selected_unit_id: String = ""

var _name_label: Label = null
var _class_label: Label = null
var _class_type_label: Label = null
var _tier_label: Label = null
var _mount_state_label: Label = null
var _wage_label: Label = null
var _id_label: Label = null
var _level_label: Label = null
var _exp_label: Label = null
var _exp_progress: ProgressBar = null

var _hp_label: Label = null
var _attack_label: Label = null
var _attack_interval_label: Label = null
var _move_speed_label: Label = null
var _attack_range_label: Label = null

var _equipment_labels: Dictionary = {}
var _mount_option: OptionButton = null
var _equip_mount_button: Button = null
var _unequip_mount_button: Button = null
var _mount_status_label: Label = null

var _promotion_label: Label = null
var _promotion_button: Button = null
var _promotion_status_label: Label = null

var _recruit_source_label: Label = null
var _recruit_settlement_label: Label = null
var _recruit_time_label: Label = null


func setup(context: WorldContext) -> void:
	_context = context
	add_theme_constant_override("separation", 6)
	_build()
	clear()


## 展示指定士兵；单位不存在时显示空状态。
func show_unit(unit_id: String) -> void:
	if _context == null:
		clear()
		return
	var unit := _context.unit_manager.get_unit(unit_id)
	if unit == null:
		clear()
		return

	var config := _context.unit_manager.get_unit_config(unit.config_id)
	var max_level: int = maxi(config.max_level, 1) if config != null else 1

	_selected_unit_id = unit_id
	_mount_status_label.text = ""
	_promotion_status_label.text = ""
	_name_label.text = unit.display_name if not unit.display_name.is_empty() else "未命名士兵"
	_class_label.text = "兵种：%s" % (
		config.display_name if config != null else "未知（%s）" % unit.config_id
	)
	_class_type_label.text = "类型：%s" % (
		config.get_class_display_name() if config != null else "未知"
	)
	_tier_label.text = "兵种等级：%s" % (
		config.get_tier_display_name() if config != null else "未知"
	)
	_mount_state_label.text = _mounted_state_text(unit)
	_wage_label.text = "每日工资：%d" % maxi(0, unit.wage)
	_id_label.text = "ID：%s" % unit.unit_id
	_level_label.text = "等级：%d / %d" % [unit.level, max_level]

	var required: int = _context.unit_manager.get_exp_to_next_level(unit.unit_id)
	if required <= 0:
		_exp_label.text = "经验：已满级"
		_exp_progress.max_value = 1
		_exp_progress.value = 1
	else:
		_exp_label.text = "经验：%d / %d" % [unit.exp, required]
		_exp_progress.max_value = float(required)
		_exp_progress.value = float(clampi(unit.exp, 0, required))

	_hp_label.text = "生命：%d / %d" % [unit.current_hp, unit.max_hp]
	_attack_label.text = "攻击力：%d" % unit.attack
	_attack_interval_label.text = "攻击间隔：%.2f 秒" % unit.attack_interval
	_move_speed_label.text = "移动速度：%.1f" % unit.move_speed
	_attack_range_label.text = "攻击距离：%.1f" % unit.attack_range

	_refresh_equipment(unit)
	_refresh_mount_controls(unit)
	_refresh_promotion(unit, config)
	_refresh_recruit_info(unit)
	_refresh_preview(unit)


func clear() -> void:
	if _name_label == null:
		return
	_selected_unit_id = ""
	_name_label.text = "未选择士兵"
	_class_label.text = ""
	_class_type_label.text = ""
	_tier_label.text = ""
	_mount_state_label.text = ""
	_wage_label.text = ""
	_id_label.text = ""
	_level_label.text = ""
	_exp_label.text = ""
	_exp_progress.max_value = 1
	_exp_progress.value = 0
	_hp_label.text = ""
	_attack_label.text = ""
	_attack_interval_label.text = ""
	_move_speed_label.text = ""
	_attack_range_label.text = ""
	for slot: String in _equipment_labels:
		var index: int = EQUIPMENT_SLOT_ORDER.find(slot)
		var label_text: String = EQUIPMENT_SLOT_LABELS[index] if index >= 0 else slot
		(_equipment_labels[slot] as Label).text = "%s：无" % label_text
	if _mount_option != null:
		_mount_option.clear()
		_mount_option.add_item("背包中没有马匹")
		_mount_option.set_item_disabled(0, true)
	if _equip_mount_button != null:
		_equip_mount_button.disabled = true
	if _unequip_mount_button != null:
		_unequip_mount_button.disabled = true
	_mount_status_label.text = ""
	_promotion_label.text = ""
	_promotion_button.disabled = true
	_promotion_status_label.text = ""
	_recruit_source_label.text = ""
	_recruit_settlement_label.text = ""
	_recruit_time_label.text = ""
	_clear_preview()


func _build() -> void:
	var title := _make_label("士兵详情", 20)
	title.name = "DetailTitle"
	add_child(title)

	_build_preview()

	_name_label = _make_label("", 18)
	_name_label.name = "DetailUnitName"
	add_child(_name_label)

	_class_label = _make_label("", 14)
	_class_label.name = "DetailUnitClass"
	add_child(_class_label)

	_class_type_label = _make_label("", 14)
	_class_type_label.name = "DetailUnitClassType"
	add_child(_class_type_label)

	_tier_label = _make_label("", 14)
	_tier_label.name = "DetailTier"
	add_child(_tier_label)

	_mount_state_label = _make_label("", 14)
	_mount_state_label.name = "DetailMountState"
	add_child(_mount_state_label)

	_wage_label = _make_label("", 14)
	_wage_label.name = "DetailWage"
	add_child(_wage_label)

	_id_label = _make_label("", 12)
	_id_label.name = "DetailUnitId"
	_id_label.modulate = Color(0.75, 0.75, 0.75)
	add_child(_id_label)

	add_child(HSeparator.new())

	_level_label = _make_label("", 15)
	_level_label.name = "DetailLevel"
	add_child(_level_label)

	_exp_label = _make_label("", 14)
	_exp_label.name = "DetailExp"
	add_child(_exp_label)

	_exp_progress = ProgressBar.new()
	_exp_progress.name = "DetailExpProgress"
	_exp_progress.show_percentage = false
	_exp_progress.custom_minimum_size = Vector2(0.0, 10.0)
	_exp_progress.max_value = 1
	_exp_progress.value = 0
	add_child(_exp_progress)

	add_child(HSeparator.new())
	add_child(_make_label("战斗属性", 16))

	_hp_label = _make_label("", 14)
	_hp_label.name = "DetailHp"
	add_child(_hp_label)

	_attack_label = _make_label("", 14)
	_attack_label.name = "DetailAttack"
	add_child(_attack_label)

	_attack_interval_label = _make_label("", 14)
	_attack_interval_label.name = "DetailAttackInterval"
	add_child(_attack_interval_label)

	_move_speed_label = _make_label("", 14)
	_move_speed_label.name = "DetailMoveSpeed"
	add_child(_move_speed_label)

	_attack_range_label = _make_label("", 14)
	_attack_range_label.name = "DetailAttackRange"
	add_child(_attack_range_label)

	add_child(HSeparator.new())
	add_child(_make_label("装备", 16))

	for index: int in range(EQUIPMENT_SLOT_ORDER.size()):
		var slot: String = EQUIPMENT_SLOT_ORDER[index]
		var label := _make_label("%s：无" % EQUIPMENT_SLOT_LABELS[index], 14)
		label.name = "DetailEquipment_%s" % slot
		add_child(label)
		_equipment_labels[slot] = label

	add_child(HSeparator.new())
	add_child(_make_label("坐骑管理", 16))

	_mount_option = OptionButton.new()
	_mount_option.name = "DetailMountOption"
	_mount_option.custom_minimum_size = Vector2(0.0, 32.0)
	_mount_option.focus_mode = Control.FOCUS_NONE
	add_child(_mount_option)

	var mount_buttons := HBoxContainer.new()
	mount_buttons.add_theme_constant_override("separation", 8)
	add_child(mount_buttons)

	_equip_mount_button = Button.new()
	_equip_mount_button.name = "DetailEquipMountButton"
	_equip_mount_button.text = "装备坐骑"
	_equip_mount_button.focus_mode = Control.FOCUS_NONE
	_equip_mount_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_equip_mount_button.pressed.connect(_on_equip_mount_pressed)
	mount_buttons.add_child(_equip_mount_button)

	_unequip_mount_button = Button.new()
	_unequip_mount_button.name = "DetailUnequipMountButton"
	_unequip_mount_button.text = "卸下坐骑"
	_unequip_mount_button.focus_mode = Control.FOCUS_NONE
	_unequip_mount_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_unequip_mount_button.pressed.connect(_on_unequip_mount_pressed)
	mount_buttons.add_child(_unequip_mount_button)

	_mount_status_label = _make_label("", 12)
	_mount_status_label.name = "DetailMountStatus"
	_mount_status_label.modulate = Color(1.0, 0.86, 0.55)
	add_child(_mount_status_label)

	add_child(HSeparator.new())
	add_child(_make_label("兵种晋升", 16))

	_promotion_label = _make_label("", 13)
	_promotion_label.name = "DetailPromotionInfo"
	_promotion_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_promotion_label)

	_promotion_button = Button.new()
	_promotion_button.name = "DetailPromotionButton"
	_promotion_button.text = "晋升兵种"
	_promotion_button.focus_mode = Control.FOCUS_NONE
	_promotion_button.custom_minimum_size = Vector2(0.0, 34.0)
	_promotion_button.pressed.connect(_on_promotion_pressed)
	add_child(_promotion_button)

	_promotion_status_label = _make_label("", 12)
	_promotion_status_label.name = "DetailPromotionStatus"
	_promotion_status_label.modulate = Color(1.0, 0.86, 0.55)
	add_child(_promotion_status_label)

	add_child(HSeparator.new())
	add_child(_make_label("招募信息", 16))

	_recruit_source_label = _make_label("", 13)
	_recruit_source_label.name = "DetailRecruitSource"
	add_child(_recruit_source_label)

	_recruit_settlement_label = _make_label("", 13)
	_recruit_settlement_label.name = "DetailRecruitSettlement"
	add_child(_recruit_settlement_label)

	_recruit_time_label = _make_label("", 13)
	_recruit_time_label.name = "DetailRecruitTime"
	add_child(_recruit_time_label)


## 复用战斗表现层的 UnitVisual，但放进独立 SubViewport，不创建真实单位。
func _build_preview() -> void:
	var preview_title := _make_label("美术预览", 14)
	preview_title.name = "DetailPreviewTitle"
	preview_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(preview_title)

	var preview_panel := PanelContainer.new()
	preview_panel.name = "DetailPreviewPanel"
	preview_panel.custom_minimum_size = Vector2(200.0, 220.0)
	preview_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(preview_panel)

	var container := SubViewportContainer.new()
	container.name = "DetailPreviewViewportContainer"
	container.custom_minimum_size = Vector2(
		float(PREVIEW_VIEWPORT_SIZE.x), float(PREVIEW_VIEWPORT_SIZE.y)
	)
	container.stretch = true
	preview_panel.add_child(container)

	_preview_viewport = SubViewport.new()
	_preview_viewport.name = "DetailPreviewViewport"
	_preview_viewport.size = PREVIEW_VIEWPORT_SIZE
	_preview_viewport.transparent_bg = true
	_preview_viewport.handle_input_locally = false
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	container.add_child(_preview_viewport)

	var preview_root := Node2D.new()
	preview_root.name = "PreviewRoot"
	_preview_viewport.add_child(preview_root)

	_preview_visual = UnitVisualScript.new()
	_preview_visual.name = "PreviewUnitVisual"
	_preview_visual.position = PREVIEW_FEET_POSITION
	_preview_visual.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	preview_root.add_child(_preview_visual)


func _refresh_preview(unit: UnitData) -> void:
	if _preview_visual == null:
		return
	_preview_visual.setup(unit, _visual_equipment_configs(unit))
	_preview_visual.set_facing(-1.0)
	# 切换预览对象时从干净的待机相位开始，避免沿用上一名士兵的状态。
	_preview_visual.reset_locomotion()


func _visual_equipment_configs(unit: UnitData) -> Dictionary:
	var configs: Dictionary = {}
	if unit == null or _context == null:
		return configs
	for slot_key_value: Variant in unit.equipment.keys():
		var slot_key: String = str(slot_key_value)
		var equipment_id: String = str(unit.equipment.get(slot_key_value, ""))
		var equipment := _context.unit_manager.get_equipment_config(equipment_id)
		if equipment != null:
			configs[slot_key] = equipment
	return configs


## 复用战斗表现层的待机动画；面板不可见时不推进动画。
func _process(delta: float) -> void:
	if _preview_visual == null or _preview_visual.unit_data == null:
		return
	if not is_visible_in_tree():
		return
	_preview_visual.update_locomotion(delta, false)


func _clear_preview() -> void:
	if _preview_visual != null:
		_preview_visual.setup(null)


## 背包中的马匹从 PlayerProfile 读取；装备/卸下统一经过 UnitManager，
## 保证“背包 + 装备”总数守恒，不会重复或丢失。
func _refresh_mount_controls(unit: UnitData) -> void:
	if _mount_option == null:
		return
	_mount_option.clear()
	# 每匹马都是独立实例：按具体个体列出外观，而不是按装备 ID 合并。
	var instances: Array[MountInstanceData] = \
		_context.player_profile.get_all_mount_instances()
	instances.sort_custom(func(a: MountInstanceData, b: MountInstanceData) -> bool:
		if a.equipment_id == b.equipment_id:
			return a.instance_id < b.instance_id
		return a.equipment_id < b.equipment_id
	)

	if instances.is_empty():
		_mount_option.add_item("背包中没有马匹")
		_mount_option.set_item_disabled(0, true)
		_mount_option.select(0)
	else:
		for instance: MountInstanceData in instances:
			if instance == null:
				continue
			var equipment := _context.unit_manager.get_equipment_config(
				instance.equipment_id
			)
			var display_name: String = (
				equipment.display_name if equipment != null else instance.equipment_id
			)
			var index: int = _mount_option.item_count
			_mount_option.add_item(
				"%s · %s" % [display_name, instance.appearance_text()]
			)
			_mount_option.set_item_metadata(index, instance.instance_id)
		if _mount_option.item_count > 0:
			_mount_option.select(0)

	_equip_mount_button.disabled = instances.is_empty() or unit.is_mounted
	_unequip_mount_button.disabled = not unit.is_mounted


func _get_selected_mount_instance_id() -> String:
	if _mount_option == null or _mount_option.selected < 0:
		return ""
	var metadata: Variant = _mount_option.get_item_metadata(_mount_option.selected)
	return str(metadata) if metadata is String else ""


func _on_equip_mount_pressed() -> void:
	if _selected_unit_id.is_empty():
		return
	var instance_id: String = _get_selected_mount_instance_id()
	if instance_id.is_empty():
		_mount_status_label.text = "背包中没有可装备的马匹"
		return
	if _context.unit_manager.equip_mount_instance(
		_selected_unit_id, instance_id, _context.player_profile
	):
		unit_changed.emit()
		_mount_status_label.text = "已装备坐骑"
	else:
		_mount_status_label.text = "无法装备：库存不足或单位状态不允许"


func _on_unequip_mount_pressed() -> void:
	if _selected_unit_id.is_empty():
		return
	if _context.unit_manager.unequip_mount(
		_selected_unit_id, _context.player_profile
	):
		unit_changed.emit()
		_mount_status_label.text = "已卸下坐骑，马匹已返回背包"
	else:
		_mount_status_label.text = "无法卸下：该单位当前没有坐骑"


func _refresh_promotion(_unit: UnitData, config: UnitConfig) -> void:
	if _promotion_label == null:
		return
	if config == null:
		_promotion_label.text = "兵种配置缺失，无法晋升"
		_promotion_button.disabled = true
		return
	if config.is_max_tier():
		_promotion_label.text = "已达到最高兵种等级"
		_promotion_button.disabled = true
		return

	var target := _context.unit_manager.get_unit_config(
		config.promotion_target_config_id
	)
	var item_id: String = config.promotion_item_id
	var item_name: String = _context.item_manager.get_display_name(item_id)
	var owned: int = _context.player_profile.get_item_count(item_id)
	var cost: int = maxi(1, config.promotion_item_cost)
	if target == null:
		_promotion_label.text = "目标兵种配置缺失（%s）" % (
			config.promotion_target_config_id
		)
		_promotion_button.disabled = true
		return

	_promotion_label.text = "晋升至：%s %s\n需要：%s ×%d（拥有 %d）" % [
		target.get_tier_display_name(),
		target.display_name,
		item_name,
		cost,
		owned,
	]
	_promotion_button.disabled = owned < cost


func _on_promotion_pressed() -> void:
	if _selected_unit_id.is_empty():
		return
	var unit := _context.unit_manager.get_unit(_selected_unit_id)
	if unit == null:
		return
	if not _context.unit_manager.promote_tier(
		_selected_unit_id, _context.player_profile
	):
		_promotion_status_label.text = "晋升失败：物品不足或已最高等级"
		return
	unit_changed.emit()
	var config := _context.unit_manager.get_unit_config(unit.config_id)
	_promotion_status_label.text = "已晋升为 %s" % (
		config.display_name if config != null else unit.config_id
	)


func _mounted_state_text(unit: UnitData) -> String:
	if not unit.is_mounted:
		return "状态：步行"
	var mount_id: String = str(unit.equipment.get("MOUNT", ""))
	var mount := _context.unit_manager.get_equipment_config(mount_id)
	if mount == null:
		return "状态：骑乘"
	return "状态：骑乘（%s）" % mount.display_name


func _refresh_equipment(unit: UnitData) -> void:
	for index: int in range(EQUIPMENT_SLOT_ORDER.size()):
		var slot: String = EQUIPMENT_SLOT_ORDER[index]
		var slot_label: String = EQUIPMENT_SLOT_LABELS[index]
		var label := _equipment_labels[slot] as Label
		var equipment_id: String = str(unit.equipment.get(slot, ""))
		if equipment_id.is_empty():
			label.text = "%s：无" % slot_label
			continue

		var equipment := _context.unit_manager.get_equipment_config(equipment_id)
		if equipment == null:
			# 理论上重算阶段已清理无效引用；这里仍保留安全显示。
			label.text = "%s：未知装备（%s）" % [slot_label, equipment_id]
			continue

		var bonus: String = equipment.bonus_text()
		if bonus.is_empty():
			label.text = "%s：%s" % [slot_label, equipment.display_name]
		else:
			label.text = "%s：%s（%s）" % [slot_label, equipment.display_name, bonus]


func _refresh_recruit_info(unit: UnitData) -> void:
	_recruit_source_label.text = "招募来源：%s" % (
		unit.recruit_source if not unit.recruit_source.is_empty() else "未知"
	)
	_recruit_settlement_label.text = "招募地点：%s" % (
		unit.recruit_settlement_id if not unit.recruit_settlement_id.is_empty() else "未知"
	)
	if unit.joined_at_game_time > 0.0:
		_recruit_time_label.text = "加入部队：%s" % _format_world_time(unit.joined_at_game_time)
	else:
		_recruit_time_label.text = "加入部队：未知"


func _make_label(label_text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = label_text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _format_world_time(total_seconds: float) -> String:
	return TimeManager.get_world_time_text(total_seconds)
