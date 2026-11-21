class_name PartyManager
extends RefCounted
## 部队数据仓储与成员关系维护。
##
## 单写者原则：成员的增删必须经过本类，保证
## UnitData.current_party_id 与 PartyData.member_unit_ids 始终一致。
## 一个单位最多属于一支部队；转队时先从旧部队移除，再加入新部队。

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


## 将已有 PartyData 注册进仓储；无 ID 时自动分配。
## 已存在的 ID 不允许覆盖，失败返回空字符串。
func add_party(party: PartyData) -> String:
	if party == null:
		return ""
	if party.party_id.is_empty():
		if _id_generator == null:
			push_error("PartyManager 无法为无 ID 部队分配 ID")
			return ""
		party.party_id = _id_generator.next_id(IdGenerator.PARTY)
	if _parties.has(party.party_id):
		push_error("部队 ID 已存在，拒绝覆盖: %s" % party.party_id)
		return ""
	_parties[party.party_id] = party
	return party.party_id


func get_party(party_id: String) -> PartyData:
	return _parties.get(party_id) as PartyData


func has_party(party_id: String) -> bool:
	return _parties.has(party_id)


## 解散部队：清空所有指向该部队的 current_party_id，单位本身保留在 UnitManager。
## 成功返回 true；部队不存在返回 false。
func remove_party(party_id: String) -> bool:
	var party := get_party(party_id)
	if party == null:
		return false

	if _unit_manager != null:
		# 同时清理成员列表中的单位与指向本部队的悬空引用。
		for unit: UnitData in _unit_manager.get_all_units():
			if unit.current_party_id == party_id:
				unit.current_party_id = ""

	_parties.erase(party_id)
	return true


## 将单位加入目标部队；单位已在其他部队时自动转队。
## 失败返回 false，且不修改任何归属数据。
func add_member(party_id: String, unit_id: String) -> bool:
	var party := get_party(party_id)
	if party == null:
		push_warning("PartyManager.add_member: 部队不存在 %s" % party_id)
		return false
	if _unit_manager == null:
		push_error("PartyManager 尚未装配 UnitManager")
		return false
	var unit := _unit_manager.get_unit(unit_id)
	if unit == null:
		push_warning("PartyManager.add_member: 单位不存在 %s" % unit_id)
		return false
	if unit.faction_id != party.faction_id:
		push_warning(
			"PartyManager.add_member: 阵营不一致，单位 %s(%s) 不能加入部队 %s(%s)"
			% [unit_id, unit.faction_id, party_id, party.faction_id]
		)
		return false

	# 先完成所有校验，再一次性修改数据，避免中途失败留下半转移状态。
	_detach_from_other_parties(unit_id, party_id)
	_normalize_member(party, unit_id)
	unit.current_party_id = party_id
	return true


## 把单位转移到目标部队；与 add_member 共用同一套底层规则。
func transfer_member(unit_id: String, target_party_id: String) -> bool:
	return add_member(target_party_id, unit_id)


## 从部队移除单位。单位本身保留；若其归属指向该部队则清空。
## 成员不存在或重复移除返回 false，不产生异常。
func remove_member(party_id: String, unit_id: String) -> bool:
	var party := get_party(party_id)
	if party == null:
		return false

	var removed: bool = party.member_unit_ids.has(unit_id)
	_remove_all_occurrences(party.member_unit_ids, unit_id)

	if _unit_manager != null:
		var unit := _unit_manager.get_unit(unit_id)
		if unit != null and unit.current_party_id == party_id:
			unit.current_party_id = ""
	return removed


func get_member_ids(party_id: String) -> Array[String]:
	var party := get_party(party_id)
	if party == null:
		return []
	return party.member_unit_ids.duplicate()


func get_units_of_party(party_id: String) -> Array[UnitData]:
	var result: Array[UnitData] = []
	var party := get_party(party_id)
	if party == null or _unit_manager == null:
		return result
	return _unit_manager.get_units_of_party(party)


## 当前部队所有成员的每日工资总额。无效成员引用会被跳过。
## 本阶段只统计与展示，不执行定期扣除。
func get_total_wage(party_id: String) -> int:
	var total: int = 0
	for unit: UnitData in get_units_of_party(party_id):
		total += maxi(0, unit.wage)
	return total


func get_all_parties() -> Array[PartyData]:
	var result: Array[PartyData] = []
	for value: Variant in _parties.values():
		var party := value as PartyData
		if party != null:
			result.append(party)
	return result


## 校验士兵与部队的双向归属是否一致；返回错误描述列表，空列表表示通过。
## 只报告问题，不自动改写数据：读档失败时保留原始数据供排查。
func validate_membership_consistency() -> Array[String]:
	var errors: Array[String] = []
	if _unit_manager == null:
		errors.append("PartyManager 尚未装配 UnitManager，无法校验成员关系")
		return errors

	var unit_to_party: Dictionary = {}
	for party: PartyData in get_all_parties():
		var local_seen: Dictionary = {}
		for unit_id: String in party.member_unit_ids:
			if local_seen.has(unit_id):
				errors.append("部队 %s 的成员列表重复包含单位 %s" % [party.party_id, unit_id])
				continue
			local_seen[unit_id] = true

			var unit := _unit_manager.get_unit(unit_id)
			if unit == null:
				errors.append("部队 %s 引用了不存在的单位 %s" % [party.party_id, unit_id])
				continue
			if unit_to_party.has(unit_id):
				errors.append(
					"单位 %s 同时出现在部队 %s 和 %s 的成员列表中"
					% [unit_id, unit_to_party[unit_id], party.party_id]
				)
				continue
			unit_to_party[unit_id] = party.party_id
			if unit.current_party_id != party.party_id:
				errors.append(
					"单位 %s 的 current_party_id=%s 与部队 %s 的成员列表不一致"
					% [unit_id, unit.current_party_id, party.party_id]
				)

	for unit: UnitData in _unit_manager.get_all_units():
		if unit.current_party_id.is_empty():
			continue
		if get_party(unit.current_party_id) == null:
			errors.append(
				"单位 %s 指向不存在的部队 %s" % [unit.unit_id, unit.current_party_id]
			)
			continue
		if not unit_to_party.has(unit.unit_id):
			errors.append(
				"单位 %s 的 current_party_id=%s，但不在该部队成员列表中"
				% [unit.unit_id, unit.current_party_id]
			)
	return errors


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
		if party.party_id.is_empty():
			continue
		if _parties.has(party.party_id):
			push_error("存档中存在重复部队 ID，已跳过后续记录: %s" % party.party_id)
			continue
		_parties[party.party_id] = party


## 从除目标部队外的所有部队成员列表中移除该单位，保证一单位最多一支部队。
func _detach_from_other_parties(unit_id: String, keep_party_id: String) -> void:
	for party: PartyData in get_all_parties():
		if party.party_id == keep_party_id:
			continue
		_remove_all_occurrences(party.member_unit_ids, unit_id)


## 保证单位在成员列表中恰好出现一次，且不改变已有单一成员的位置。
func _normalize_member(party: PartyData, unit_id: String) -> void:
	var count: int = 0
	for member_id: String in party.member_unit_ids:
		if member_id == unit_id:
			count += 1
	if count == 1:
		return
	_remove_all_occurrences(party.member_unit_ids, unit_id)
	party.member_unit_ids.append(unit_id)


func _remove_all_occurrences(ids: Array[String], unit_id: String) -> void:
	while ids.has(unit_id):
		ids.erase(unit_id)
