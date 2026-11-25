class_name UnitManager
extends RefCounted
## 单位数据仓储。只管数据，不负责场景表现和单位 AI。
##
## 单写者原则：新增/删除单位、等级与经验、装备、最终属性重算都经过本类。
## 单位归属关系由 PartyManager 维护，本类不直接修改 PartyData。
##
## 静态配置（UnitConfig / EquipmentConfig）只读注册在本类中；不序列化 Resource，
## 也不在每次属性计算时从磁盘重新加载。

var _units: Dictionary = {}
var _id_generator: IdGenerator = null

## { config_id: UnitConfig } / { equipment_id: EquipmentConfig }
var _unit_configs: Dictionary = {}
var _equipment_configs: Dictionary = {}
## 士兵独立名称的编号计数器；名称本身随 UnitData 持久化。
var _name_counters: Dictionary = {}


func setup(id_generator: IdGenerator) -> void:
	_id_generator = id_generator


# ---------------------------------------------------------------------------
# 静态配置注册与查询
# ---------------------------------------------------------------------------


## 注册兵种模板。重复 config_id 拒绝覆盖并返回 false。
func register_unit_config(config: UnitConfig) -> bool:
	if config == null or not config.validate():
		return false
	if _unit_configs.has(config.config_id):
		push_error("UnitConfig 重复注册，拒绝覆盖: %s" % config.config_id)
		return false
	_unit_configs[config.config_id] = config
	return true


## 注册装备模板。重复 equipment_id 拒绝覆盖并返回 false。
func register_equipment_config(config: EquipmentConfig) -> bool:
	if config == null or not config.validate():
		return false
	if _equipment_configs.has(config.equipment_id):
		push_error("EquipmentConfig 重复注册，拒绝覆盖: %s" % config.equipment_id)
		return false
	_equipment_configs[config.equipment_id] = config
	return true


func get_unit_config(config_id: String) -> UnitConfig:
	return _unit_configs.get(config_id) as UnitConfig


func get_equipment_config(equipment_id: String) -> EquipmentConfig:
	return _equipment_configs.get(equipment_id) as EquipmentConfig


func has_unit_config(config_id: String) -> bool:
	return _unit_configs.has(config_id)


func has_equipment_config(equipment_id: String) -> bool:
	return _equipment_configs.has(equipment_id)


# ---------------------------------------------------------------------------
# 创建与仓储
# ---------------------------------------------------------------------------


## 依据兵种配置生成一个运行时单位。
## 基础属性统一由 StatCalculator 计算，避免与 UnitManager 各维护一套规则。
## display_name/level 是可选的个体覆盖：家族领袖、剧情角色可以拥有自己的名字
## 与初始等级；普通新兵保持空名称与配置基础等级。
func create_unit(
	config: UnitConfig,
	faction_id: String,
	display_name: String = "",
	level: int = 0
) -> UnitData:
	var unit := _build_unit_data(config, faction_id, display_name, level)
	if unit == null:
		return null
	if _units.has(unit.unit_id):
		push_error("UnitManager 生成出重复单位 ID: %s" % unit.unit_id)
		return null
	_units[unit.unit_id] = unit
	return unit


## 创建一个尚未进入仓储、也不属于任何部队的独立 UnitData。
##
## 用于村庄冒险者候选人：候选人需要真实的单位身份（唯一 ID、等级、属性、
## 外观与装备），但在被招募前不应出现在 UnitManager 仓储或任何部队中。
## 招募成功后再通过 add_unit() 注册到仓储并加入玩家部队。
## 属性仍由 StatCalculator 统一计算，不维护第二套公式。
func create_detached_unit(
	config: UnitConfig,
	faction_id: String,
	display_name: String = "",
	level: int = 0
) -> UnitData:
	var unit := _build_unit_data(config, faction_id, display_name, level)
	if unit == null:
		return null
	if _units.has(unit.unit_id):
		push_error("UnitManager 生成出重复单位 ID: %s" % unit.unit_id)
		return null
	return unit


## 为尚未注册的独立单位装备一匹真实马匹实例，并按装备重算属性。
##
## 用于贵族冒险者候选人：候选人需要在被招募前就拥有完整的三级士兵 + 战马
## 数据快照，但不能进入 UnitManager 仓储。已注册单位必须走 equip_item /
## equip_mount_instance，避免绕过仓储单写者规则。
func equip_detached_mount(
	unit: UnitData,
	equipment_id: String,
	instance: MountInstanceData = null
) -> bool:
	if unit == null or _units.has(unit.unit_id):
		return false
	var equipment := get_equipment_config(equipment_id)
	if equipment == null or equipment.slot != EquipmentConfig.Slot.MOUNT:
		return false
	var config := get_unit_config(unit.config_id)
	if config == null:
		return false
	var mount := instance
	if mount == null or mount.equipment_id != equipment_id:
		mount = MountInstanceData.create_random(equipment_id)

	var slot_key: String = EquipmentConfig.SLOT_NAMES[EquipmentConfig.Slot.MOUNT]
	var had_previous: bool = unit.equipment.has(slot_key)
	var previous_equipment: Variant = unit.equipment.get(slot_key)
	var previous_instance: Dictionary = unit.mount_instance.duplicate(true)

	unit.equipment[slot_key] = equipment_id
	unit.set_mount_instance_data(mount)
	unit.is_mounted = true
	if StatCalculator.apply_to_unit(unit, config, _equipment_configs):
		# 新创建的候选人应满血；装备提高上限后同步当前生命。
		unit.current_hp = unit.max_hp
		return true

	if had_previous:
		unit.equipment[slot_key] = previous_equipment
	else:
		unit.equipment.erase(slot_key)
	unit.mount_instance = previous_instance
	unit.is_mounted = had_previous
	return false


## 创建单位数据但不注册；create_unit / create_detached_unit 的唯一构造入口。
func _build_unit_data(
	config: UnitConfig,
	faction_id: String,
	display_name: String,
	level: int
) -> UnitData:
	if _id_generator == null:
		push_error("UnitManager 尚未初始化 IdGenerator")
		return null
	if config == null or not config.validate():
		return null

	var resolved := _resolve_unit_config(config)
	if resolved == null:
		return null

	var unit := UnitData.new()
	unit.unit_id = _id_generator.next_id(IdGenerator.UNIT)

	unit.config_id = resolved.config_id
	unit.display_name = (
		display_name if not display_name.strip_edges().is_empty()
		else _next_unit_name(resolved)
	)
	var max_level: int = maxi(resolved.max_level, 1)
	unit.level = clampi(
		level if level > 0 else resolved.base_level, 1, max_level
	)
	unit.exp = 0
	unit.wage = maxi(0, resolved.daily_wage)
	unit.faction_id = faction_id
	unit.is_player_character = resolved.is_player_character
	unit.equipment = _sanitize_default_equipment(resolved.default_equipment)
	var mount_slot: String = EquipmentConfig.SLOT_NAMES[EquipmentConfig.Slot.MOUNT]
	if unit.equipment.has(mount_slot):
		var mount_id: String = str(unit.equipment[mount_slot])
		unit.set_mount_instance_data(MountInstanceData.create_deterministic(
			mount_id, "unit|%s|%s" % [unit.unit_id, mount_id]
		))

	if not StatCalculator.apply_to_unit(unit, resolved, _equipment_configs):
		push_error("UnitManager 无法计算单位基础属性: %s" % resolved.config_id)
		return null
	# 骑乘状态只由 MOUNT 装备决定；兵种配置的 is_mounted 不再单独生成骑兵。
	unit.is_mounted = unit.equipment.has(
		EquipmentConfig.SLOT_NAMES[EquipmentConfig.Slot.MOUNT]
	)
	if resolved.is_mounted and not unit.is_mounted:
		push_warning(
			"兵种 %s 标记为骑乘，但默认装备没有 MOUNT；按步兵创建"
			% resolved.config_id
		)
	unit.current_hp = unit.max_hp
	unit.current_party_id = ""

	return unit


## 将已有 UnitData 注册进仓储；无 ID 时自动分配。
## 已存在的 ID 不允许覆盖，失败返回空字符串。
func add_unit(unit: UnitData) -> String:
	if unit == null:
		return ""
	if unit.unit_id.is_empty():
		if _id_generator == null:
			push_error("UnitManager 无法为无 ID 单位分配 ID")
			return ""
		unit.unit_id = _id_generator.next_id(IdGenerator.UNIT)
	if _units.has(unit.unit_id):
		push_error("单位 ID 已存在，拒绝覆盖: %s" % unit.unit_id)
		return ""
	_units[unit.unit_id] = unit
	return unit.unit_id


func get_unit(unit_id: String) -> UnitData:
	return _units.get(unit_id) as UnitData


func has_unit(unit_id: String) -> bool:
	return _units.has(unit_id)


## 删除单位。仍属于部队时拒绝删除，必须先经 PartyManager.remove_member()。
## 成功返回 true；单位不存在或仍被部队引用时返回 false，原数据保持不变。
func remove_unit(unit_id: String) -> bool:
	var unit := get_unit(unit_id)
	if unit == null:
		return false
	if not unit.current_party_id.is_empty():
		push_error(
			"单位 %s 仍属于部队 %s，不能直接删除；请先通过 PartyManager 移除成员"
			% [unit_id, unit.current_party_id]
		)
		return false
	_units.erase(unit_id)
	return true


func get_all_units() -> Array[UnitData]:
	var result: Array[UnitData] = []
	for value: Variant in _units.values():
		var unit := value as UnitData
		if unit != null:
			result.append(unit)
	return result


func get_units_of_party(party: PartyData) -> Array[UnitData]:
	var result: Array[UnitData] = []
	if party == null:
		return result
	for unit_id: String in party.member_unit_ids:
		var unit := get_unit(unit_id)
		if unit != null and not result.has(unit):
			result.append(unit)
	return result


# ---------------------------------------------------------------------------
# 经验与升级
# ---------------------------------------------------------------------------


## 增加经验并自动处理升级。经验值非法、单位不存在或已满级时返回 false。
## 支持一次增加触发多次升级；达到最高等级后经验归零，不再累积。
func add_exp(unit_id: String, amount: int) -> bool:
	var unit := get_unit(unit_id)
	if unit == null or amount <= 0:
		return false

	var config := get_unit_config(unit.config_id)
	if config == null:
		push_error("无法增加经验：单位 %s 的兵种配置 %s 未注册"
			% [unit_id, unit.config_id])
		return false

	var max_level: int = maxi(config.max_level, 1)
	unit.level = clampi(unit.level, 1, max_level)
	unit.exp = maxi(0, unit.exp)

	if unit.level >= max_level:
		unit.exp = 0
		return false

	unit.exp += amount
	var leveled: bool = false
	while unit.level < max_level:
		var required: int = config.exp_to_next_level(unit.level)
		if unit.exp < required:
			break
		unit.exp -= required
		unit.level += 1
		leveled = true

	if unit.level >= max_level:
		unit.exp = 0

	if leveled:
		return recalculate_stats(unit_id)
	return true


## 当前等级升到下一级所需经验；单位或配置无效返回 0。
## 读档/迁移后把等级与经验校正到当前五级制：
## - 旧 1–10 级超出上限时按 ceil(level / 2) 折算；
## - 经验超过当前阈值时补升级，避免存档后“有经验却不升级”；
## - 满级经验归零，与 add_exp 的规则一致。
func normalize_combat_progression() -> void:
	for unit: UnitData in get_all_units():
		if unit == null:
			continue
		var config := get_unit_config(unit.config_id)
		if config == null:
			continue
		var max_level: int = maxi(config.max_level, 1)
		unit.level = maxi(1, unit.level)
		unit.exp = maxi(0, unit.exp)
		if unit.level > max_level:
			unit.level = CombatExperience.legacy_level_to_combat_level(unit.level)
			unit.level = clampi(unit.level, 1, max_level)
		while unit.level < max_level:
			var required: int = config.exp_to_next_level(unit.level)
			if required <= 0 or unit.exp < required:
				break
			unit.exp -= required
			unit.level += 1
		if unit.level >= max_level:
			unit.exp = 0


func get_exp_to_next_level(unit_id: String) -> int:
	var unit := get_unit(unit_id)
	if unit == null:
		return 0
	var config := get_unit_config(unit.config_id)
	if config == null:
		return 0
	if unit.level >= maxi(config.max_level, 1):
		return 0
	return config.exp_to_next_level(unit.level)


# ---------------------------------------------------------------------------
# 装备
# ---------------------------------------------------------------------------


## 装备物品；槽位由 EquipmentConfig.slot 决定，同槽位已有装备会被替换。
## 任意校验失败时返回 false 且不修改数据。
func equip_item(unit_id: String, equipment_id: String) -> bool:
	var unit := get_unit(unit_id)
	if unit == null:
		return false
	var equipment := get_equipment_config(equipment_id)
	if equipment == null:
		push_error("装备失败：单位 %s 引用不存在的装备 %s" % [unit_id, equipment_id])
		return false
	if not equipment.validate():
		return false

	var slot_key: String = equipment.slot_name()
	if slot_key.is_empty():
		push_error("装备失败：装备 %s 槽位非法" % equipment_id)
		return false

	var had_previous: bool = unit.equipment.has(slot_key)
	var previous: Variant = unit.equipment.get(slot_key)
	var previous_mount_instance: Dictionary = unit.mount_instance.duplicate(true)
	unit.equipment[slot_key] = equipment_id
	if slot_key == EquipmentConfig.SLOT_NAMES[EquipmentConfig.Slot.MOUNT]:
		var existing := unit.get_mount_instance_data()
		if existing == null or existing.equipment_id != equipment_id:
			unit.set_mount_instance_data(MountInstanceData.create_deterministic(
				equipment_id, "unit|%s|%s" % [unit_id, equipment_id]
			))
	if recalculate_stats(unit_id):
		return true

	# 属性重算失败时回滚，避免留下半更新状态。
	if had_previous:
		unit.equipment[slot_key] = previous
	else:
		unit.equipment.erase(slot_key)
	unit.mount_instance = previous_mount_instance
	recalculate_stats(unit_id)
	return false


## 卸下指定槽位装备。槽位非法或该槽位为空返回 false。
func unequip_slot(unit_id: String, slot: String) -> bool:
	var unit := get_unit(unit_id)
	if unit == null:
		return false
	var slot_key: String = slot.strip_edges().to_upper()
	if EquipmentConfig.slot_from_string(slot_key) < 0:
		return false
	if not unit.equipment.has(slot_key):
		return false

	unit.equipment.erase(slot_key)
	if slot_key == EquipmentConfig.SLOT_NAMES[EquipmentConfig.Slot.MOUNT]:
		unit.mount_instance = {}
	return recalculate_stats(unit_id)


## 从物品持有者装备“某一匹具体马”。holder 可以是 PlayerProfile 或 PartyData。
## 替换已有坐骑时，旧马匹实例原样返还持有者，外观不变。
func equip_mount_instance(unit_id: String, instance_id: String, holder: Variant) -> bool:
	var unit := get_unit(unit_id)
	if unit == null or holder == null or instance_id.is_empty():
		return false
	var instance: MountInstanceData = holder.get_mount_instance(instance_id)
	if instance == null:
		return false
	var equipment := get_equipment_config(instance.equipment_id)
	if equipment == null or equipment.slot != EquipmentConfig.Slot.MOUNT:
		return false

	var slot_key: String = equipment.slot_name()
	var had_previous: bool = unit.equipment.has(slot_key)
	var previous_equipment: Variant = unit.equipment.get(slot_key)
	var previous_instance: MountInstanceData = _ensure_unit_mount_instance(unit)

	var removed: MountInstanceData = holder.remove_mount_instance(instance_id)
	if removed == null:
		return false

	unit.equipment[slot_key] = instance.equipment_id
	unit.mount_instance = instance.to_dict()
	if recalculate_stats(unit_id):
		if had_previous and previous_instance != null:
			holder.add_mount_instance(previous_instance)
		return true

	# 回滚：恢复原装备与原马匹实例，再把新马匹放回持有者。
	if had_previous:
		unit.equipment[slot_key] = previous_equipment
		unit.mount_instance = (
			previous_instance.to_dict() if previous_instance != null else {}
		)
	else:
		unit.equipment.erase(slot_key)
		unit.mount_instance = {}
	recalculate_stats(unit_id)
	holder.add_mount_instance(removed)
	return false


## 兼容旧调用：按装备 ID 从持有者取第一匹匹配的马。
func equip_mount(
	unit_id: String, equipment_id: String, holder: Variant
) -> bool:
	if holder == null:
		return false
	var instances: Array[MountInstanceData] = holder.get_mount_instances(equipment_id)
	if instances.is_empty():
		# 触发旧存档马匹数量迁移后再取一次。
		holder.get_item_count(equipment_id)
		instances = holder.get_mount_instances(equipment_id)
	if instances.is_empty():
		return false
	return equip_mount_instance(unit_id, instances[0].instance_id, holder)


## 卸下 MOUNT 装备并把同一匹马（含外观与实例 ID）返还持有者。
func unequip_mount(unit_id: String, holder: Variant) -> bool:
	var unit := get_unit(unit_id)
	if unit == null or holder == null:
		return false

	var slot_key: String = EquipmentConfig.SLOT_NAMES[EquipmentConfig.Slot.MOUNT]
	if not unit.equipment.has(slot_key):
		return false
	var previous_equipment: Variant = unit.equipment.get(slot_key)
	var previous_instance := _ensure_unit_mount_instance(unit)
	if previous_instance == null:
		return false

	if not unequip_slot(unit_id, slot_key):
		return false
	if holder.add_mount_instance(previous_instance):
		return true

	# 理论不会发生；回滚以保持“卸下必返还”的约束。
	unit.equipment[slot_key] = previous_equipment
	unit.mount_instance = previous_instance.to_dict()
	recalculate_stats(unit_id)
	return false


## 读取单位当前坐骑实例；旧数据缺失时按单位 ID 生成确定性外观并写回。
func _ensure_unit_mount_instance(unit: UnitData) -> MountInstanceData:
	if unit == null:
		return null
	var slot_key: String = EquipmentConfig.SLOT_NAMES[EquipmentConfig.Slot.MOUNT]
	var mount_id: String = str(unit.equipment.get(slot_key, ""))
	if mount_id.is_empty():
		return null
	var instance := unit.get_mount_instance_data()
	if instance == null or instance.equipment_id != mount_id:
		instance = MountInstanceData.create_deterministic(
			mount_id, "unit|%s|%s" % [unit.unit_id, mount_id]
		)
		unit.mount_instance = instance.to_dict()
	return instance


# ---------------------------------------------------------------------------
# 兵种等级晋升
# ---------------------------------------------------------------------------


## 消耗晋升物品，把士兵切换到更高兵种等级。
## 保留 level / exp / 装备 / 骑乘状态；失败时不消耗物品、不修改任何字段。
func promote_tier(unit_id: String, profile: PlayerProfile) -> bool:
	var unit := get_unit(unit_id)
	if unit == null or profile == null:
		return false
	var config := get_unit_config(unit.config_id)
	if config == null:
		return false
	if config.is_max_tier():
		return false

	var target_config := get_unit_config(config.promotion_target_config_id)
	if target_config == null:
		push_error(
			"晋升失败：单位 %s 的目标兵种 %s 未注册"
			% [unit_id, config.promotion_target_config_id]
		)
		return false
	if target_config.tier <= config.tier:
		push_error("晋升失败：目标兵种等级不高于当前等级: %s" % unit.config_id)
		return false

	var item_id: String = config.promotion_item_id.strip_edges()
	var cost: int = maxi(1, config.promotion_item_cost)
	if item_id.is_empty():
		return false
	if not profile.remove_item(item_id, cost):
		return false

	var previous_config_id: String = unit.config_id
	var previous_display_name: String = unit.display_name
	var previous_level: int = unit.level
	var previous_exp: int = unit.exp
	var previous_wage: int = unit.wage
	var max_level: int = maxi(target_config.max_level, 1)

	unit.config_id = target_config.config_id
	unit.level = clampi(unit.level, 1, max_level)
	unit.exp = maxi(0, unit.exp)
	if unit.level >= max_level:
		unit.exp = 0
	# 名称格式为“兵种名 + 编号”；晋升时替换兵种名前缀，保留个体编号。
	if unit.display_name.begins_with(config.display_name):
		var suffix: String = unit.display_name.substr(config.display_name.length())
		unit.display_name = "%s%s" % [target_config.display_name, suffix]
	# 工资跟随兵种等级；骑马状态与装备不受影响。
	unit.wage = maxi(0, target_config.daily_wage)

	if recalculate_stats(unit_id):
		return true

	# 重算失败时回滚兵种、名称、等级、经验、工资与物品消耗。
	unit.config_id = previous_config_id
	unit.display_name = previous_display_name
	unit.level = previous_level
	unit.exp = previous_exp
	unit.wage = previous_wage
	recalculate_stats(unit_id)
	profile.add_item(item_id, cost)
	return false


# ---------------------------------------------------------------------------
# 属性重算
# ---------------------------------------------------------------------------


## 按当前兵种配置、等级与装备重算最终属性。
## current_hp 只做上限 clamp，不会自动回满。
func recalculate_stats(unit_id: String) -> bool:
	var unit := get_unit(unit_id)
	if unit == null:
		return false
	var config := get_unit_config(unit.config_id)
	if config == null:
		push_error("属性重算失败：单位 %s 的兵种配置 %s 未注册"
			% [unit_id, unit.config_id])
		return false

	_sanitize_unit_equipment(unit)
	if unit.display_name.strip_edges().is_empty():
		unit.display_name = config.display_name
	var applied: bool = StatCalculator.apply_to_unit(unit, config, _equipment_configs)
	if applied:
		# 骑乘状态是 MOUNT 装备的派生状态，不允许与装备数据不一致。
		unit.is_mounted = unit.equipment.has(
			EquipmentConfig.SLOT_NAMES[EquipmentConfig.Slot.MOUNT]
		)
		# 旧存档缺少工资字段时按当前兵种等级补全；已有工资保持不变，
		# 保证工资与士兵个体绑定，不因装备或读档重算而改变。
		if unit.wage < 0:
			unit.wage = maxi(0, config.daily_wage)
	return applied


## 重算全部单位；返回失败描述列表，空列表表示全部成功。
## 读档装配完成后由 WorldContext 调用。
func recalculate_all_stats() -> Array[String]:
	var errors: Array[String] = []
	for unit: UnitData in get_all_units():
		if not recalculate_stats(unit.unit_id):
			errors.append(
				"单位 %s 属性重算失败（config_id=%s）"
				% [unit.unit_id, unit.config_id]
			)
	return errors


# ---------------------------------------------------------------------------
# 序列化
# ---------------------------------------------------------------------------


func to_dict() -> Dictionary:
	var payload: Dictionary = {}
	for unit_id: String in _units:
		var unit := _units[unit_id] as UnitData
		if unit != null:
			payload[unit_id] = unit.to_dict()
	return payload


func load_from_dict(payload: Dictionary) -> void:
	_units.clear()
	_name_counters.clear()
	for unit_id: Variant in payload:
		var value: Variant = payload[unit_id]
		if not value is Dictionary:
			continue
		var unit := UnitData.from_dict(value)
		if unit.unit_id.is_empty():
			continue
		if _units.has(unit.unit_id):
			push_error("存档中存在重复单位 ID，已跳过后续记录: %s" % unit.unit_id)
			continue
		_units[unit.unit_id] = unit
		_name_counters[unit.config_id] = int(_name_counters.get(unit.config_id, 0)) + 1


# ---------------------------------------------------------------------------
# 内部工具
# ---------------------------------------------------------------------------


## 优先使用已注册的权威配置；未注册时把传入配置注册为模板。
func _resolve_unit_config(config: UnitConfig) -> UnitConfig:
	var registered := get_unit_config(config.config_id)
	if registered != null:
		return registered
	if not register_unit_config(config):
		return null
	return config


## 生成“兵种名 + 两位编号”的独立名称，例如“民兵 01”。
func _next_unit_name(config: UnitConfig) -> String:
	var next_index: int = int(_name_counters.get(config.config_id, 0)) + 1
	_name_counters[config.config_id] = next_index
	return "%s %02d" % [config.display_name, next_index]


## 默认装备必须引用已注册且槽位匹配的装备；非法条目报告错误后丢弃。
func _sanitize_default_equipment(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for slot_key: Variant in source:
		var slot_name: String = str(slot_key).strip_edges().to_upper()
		var equipment_id: String = str(source[slot_key])
		if EquipmentConfig.slot_from_string(slot_name) < 0:
			push_error("默认装备槽位非法: %s（装备 %s）" % [slot_name, equipment_id])
			continue
		var equipment := get_equipment_config(equipment_id)
		if equipment == null:
			push_error("默认装备引用不存在的配置: %s" % equipment_id)
			continue
		if equipment.slot_name() != slot_name:
			push_error(
				"默认装备槽位不匹配: %s 属于 %s，却放在 %s"
				% [equipment_id, equipment.slot_name(), slot_name]
			)
			continue
		result[slot_name] = equipment_id
	return result


## 清理指向不存在配置或槽位不匹配的装备引用。
## 属性重算前调用，保证无效引用不会静默参与计算。
func _sanitize_unit_equipment(unit: UnitData) -> void:
	if unit.equipment.is_empty():
		return
	var invalid_slots: Array[String] = []
	for slot_key: Variant in unit.equipment:
		var slot_name: String = str(slot_key)
		var equipment_id: String = str(unit.equipment[slot_key])
		if EquipmentConfig.slot_from_string(slot_name) < 0:
			push_error("单位 %s 的装备槽位非法，已移除: %s" % [unit.unit_id, slot_name])
			invalid_slots.append(slot_name)
			continue
		var equipment := get_equipment_config(equipment_id)
		if equipment == null:
			push_error(
				"单位 %s 引用了不存在的装备 %s，已移除"
				% [unit.unit_id, equipment_id]
			)
			invalid_slots.append(slot_name)
			continue
		if equipment.slot_name() != slot_name:
			push_error(
				"单位 %s 的装备 %s 槽位不匹配，已移除"
				% [unit.unit_id, equipment_id]
			)
			invalid_slots.append(slot_name)
	for slot_name: String in invalid_slots:
		unit.equipment.erase(slot_name)
	if not unit.equipment.has(
		EquipmentConfig.SLOT_NAMES[EquipmentConfig.Slot.MOUNT]
	):
		unit.mount_instance = {}
