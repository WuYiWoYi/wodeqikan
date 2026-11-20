class_name UnitManager
extends RefCounted
## 单位数据仓储。只管数据，不负责场景表现和单位 AI。
##
## 单写者原则：新增/删除单位、最终属性重算都经过本类。
## 单位归属关系由 PartyManager 维护，本类不直接修改 PartyData。

var _units: Dictionary = {}
var _id_generator: IdGenerator = null


func setup(id_generator: IdGenerator) -> void:
	_id_generator = id_generator


## 依据兵种配置生成一个运行时单位。
## 基础属性统一由 StatCalculator 计算，避免与 UnitManager 各维护一套规则。
func create_unit(config: UnitConfig, faction_id: String) -> UnitData:
	if _id_generator == null:
		push_error("UnitManager 尚未初始化 IdGenerator")
		return null
	if config == null or not config.validate():
		return null

	var unit := UnitData.new()
	unit.unit_id = _id_generator.next_id(IdGenerator.UNIT)
	if _units.has(unit.unit_id):
		push_error("UnitManager 生成出重复单位 ID: %s" % unit.unit_id)
		return null

	unit.config_id = config.config_id
	unit.display_name = config.display_name
	unit.level = config.base_level
	unit.faction_id = faction_id
	unit.is_mounted = config.is_mounted
	unit.equipment = config.default_equipment.duplicate(true)

	if not StatCalculator.apply_to_unit(unit, config):
		push_error("UnitManager 无法计算单位基础属性: %s" % config.config_id)
		return null
	unit.current_hp = unit.max_hp
	unit.current_party_id = ""

	_units[unit.unit_id] = unit
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


func to_dict() -> Dictionary:
	var payload: Dictionary = {}
	for unit_id: String in _units:
		var unit := _units[unit_id] as UnitData
		if unit != null:
			payload[unit_id] = unit.to_dict()
	return payload


func load_from_dict(payload: Dictionary) -> void:
	_units.clear()
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
