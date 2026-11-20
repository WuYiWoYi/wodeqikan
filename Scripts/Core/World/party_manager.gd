class_name PartyManager
extends RefCounted
## 部队数据仓储与成员关系维护。
##
## 单写者原则：成员的增删必须经过本类，保证
## UnitData.current_party_id 与 PartyData.member_unit_ids 始终一致。

var _parties: Dictionary = {}
var _unit_manager: UnitManager = null
var _id_generator: IdGenerator = null


func setup(unit_manager: UnitManager, id_generator: IdGenerator) -> void:
	_unit_manager = unit_manager
	_id_generator = id_generator


func create_party(
	faction_id: String, world_position: Vector2, party_name: String = ""
) -> PartyData:
	if _id_generator == null:
		push_error("PartyManager 尚未初始化 IdGenerator")
		return null

	var party := PartyData.new()
	party.party_id = _id_generator.next_id(IdGenerator.PARTY)
	party.party_name = party_name if not party_name.is_empty() else "未命名部队"
	party.faction_id = faction_id
	party.world_position = world_position
	party.target_position = world_position
	_parties[party.party_id] = party
	return party


func add_party(party: PartyData) -> String:
	if party == null:
		return ""
	if party.party_id.is_empty():
		if _id_generator == null:
			push_error("PartyManager 无法为无 ID 部队分配 ID")
			return ""
		party.party_id = _id_generator.next_id(IdGenerator.PARTY)
	_parties[party.party_id] = party
	return party.party_id


func get_party(party_id: String) -> PartyData:
	return _parties.get(party_id) as PartyData


func has_party(party_id: String) -> bool:
	return _parties.has(party_id)


func remove_party(party_id: String) -> void:
	var party := get_party(party_id)
	if party == null:
		return
	for unit_id: String in party.member_unit_ids:
		var unit := _unit_manager.get_unit(unit_id) if _unit_manager != null else null
		if unit != null and unit.current_party_id == party_id:
			unit.current_party_id = ""
	_parties.erase(party_id)


func add_member(party_id: String, unit_id: String) -> bool:
	var party := get_party(party_id)
	var unit := _unit_manager.get_unit(unit_id) if _unit_manager != null else null
	if party == null or unit == null:
		return false

	if not party.member_unit_ids.has(unit_id):
		party.member_unit_ids.append(unit_id)
	unit.current_party_id = party_id
	return true


func remove_member(party_id: String, unit_id: String) -> bool:
	var party := get_party(party_id)
	if party == null:
		return false

	var removed: bool = party.member_unit_ids.has(unit_id)
	party.member_unit_ids.erase(unit_id)

	var unit := _unit_manager.get_unit(unit_id) if _unit_manager != null else null
	if unit != null and unit.current_party_id == party_id:
		unit.current_party_id = ""
	return removed


func get_units_of_party(party_id: String) -> Array[UnitData]:
	var result: Array[UnitData] = []
	var party := get_party(party_id)
	if party == null or _unit_manager == null:
		return result
	return _unit_manager.get_units_of_party(party)


func get_all_parties() -> Array[PartyData]:
	var result: Array[PartyData] = []
	for value: Variant in _parties.values():
		var party := value as PartyData
		if party != null:
			result.append(party)
	return result


func to_dict() -> Dictionary:
	var payload: Dictionary = {}
	for party_id: String in _parties:
		var party := _parties[party_id] as PartyData
		if party != null:
			payload[party_id] = party.to_dict()
	return payload


func load_from_dict(payload: Dictionary) -> void:
	_parties.clear()
	for party_id: Variant in payload:
		var value: Variant = payload[party_id]
		if not value is Dictionary:
			continue
		var party := PartyData.from_dict(value)
		if not party.party_id.is_empty():
			_parties[party.party_id] = party
