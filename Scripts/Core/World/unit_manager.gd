class_name UnitManager
extends RefCounted
## 单位数据仓储。只管数据，不负责场景表现和单位 AI。
##
## 单写者原则：新增/删除单位、最终属性重算都经过本类。

var _units: Dictionary = {}
var _id_generator: IdGenerator = null


func setup(id_generator: IdGenerator) -> void:
	_id_generator = id_generator


## 依据兵种配置生成一个运行时单位。阶段 3 再接入等级/装备属性计算。
func create_unit(config: UnitConfig, faction_id: String) -> UnitData:
	if _id_generator == null:
		push_error("UnitManager 尚未初始化 IdGenerator")
		return null
	if config == null or not config.validate():
		return null

	var unit := UnitData.new()
	unit.unit_id = _id_generator.next_id(IdGenerator.UNIT)
	unit.config_id = config.config_id
	unit.display_name = config.display_name
	unit.level = config.base_level
	unit.max_hp = config.base_max_hp
	unit.current_hp = config.base_max_hp
	unit.attack = config.base_attack
	unit.attack_interval = config.attack_interval
	unit.move_speed = config.move_speed
	unit.attack_range = config.attack_range
	unit.faction_id = faction_id
	unit.is_mounted = config.is_mounted
	unit.equipment = config.default_equipment.duplicate(true)

	_units[unit.unit_id] = unit
	return unit


func add_unit(unit: UnitData) -> String:
	if unit == null:
		return ""
	if unit.unit_id.is_empty():
		if _id_generator == null:
			push_error("UnitManager 无法为无 ID 单位分配 ID")
			return ""
		unit.unit_id = _id_generator.next_id(IdGenerator.UNIT)
	_units[unit.unit_id] = unit
	return unit.unit_id


func get_unit(unit_id: String) -> UnitData:
	return _units.get(unit_id) as UnitData


func has_unit(unit_id: String) -> bool:
	return _units.has(unit_id)


func remove_unit(unit_id: String) -> void:
	_units.erase(unit_id)


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
		if unit != null:
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
		if not unit.unit_id.is_empty():
			_units[unit.unit_id] = unit
