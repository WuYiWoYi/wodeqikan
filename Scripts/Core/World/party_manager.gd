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
	faction_id: String,
	world_position: Vector2,
	party_name: String = "",
	party_kind: PartyData.PartyKind = PartyData.PartyKind.GENERIC
) -> PartyData:
	if _id_generator == null:
		push_error("PartyManager 尚未初始化 IdGenerator")
		return null

	var party := PartyData.new()
	party.party_id = _id_generator.next_id(IdGenerator.PARTY)
	party.party_name = party_name if not party_name.is_empty() else "未命名部队"
	party.faction_id = faction_id
	party.party_kind = party_kind
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
			if unit.prisoner_owner_party_id == party_id:
				# 部队解散后俘虏不再属于任何部队，保留 Unit 数据供后续处理。
				unit.clear_prisoner_ownership()

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
	if unit.is_prisoner() or not unit.sold_to_settlement_id.is_empty():
		push_warning(
			"PartyManager.add_member: 单位 %s 已处于俘虏/出售状态，不能直接加入部队"
			% unit_id
		)
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
## 领袖被移除时同步清空 leader_unit_id，避免留下悬空引用。
func remove_member(party_id: String, unit_id: String) -> bool:
	var party := get_party(party_id)
	if party == null:
		return false

	var removed: bool = party.member_unit_ids.has(unit_id)
	_remove_all_occurrences(party.member_unit_ids, unit_id)
	if removed and party.leader_unit_id == unit_id:
		party.leader_unit_id = ""

	if _unit_manager != null:
		var unit := _unit_manager.get_unit(unit_id)
		if unit != null and unit.current_party_id == party_id:
			unit.current_party_id = ""
	return removed


## 返回部队领袖单位；未设置、已移除或单位不存在时返回 null。
func get_leader_unit(party_id: String) -> UnitData:
	var party := get_party(party_id)
	if party == null or party.leader_unit_id.is_empty() or _unit_manager == null:
		return null
	var unit := _unit_manager.get_unit(party.leader_unit_id)
	if unit == null or not party.member_unit_ids.has(unit.unit_id):
		return null
	return unit


func is_party_leader(unit_id: String) -> bool:
	if unit_id.is_empty():
		return false
	for party: PartyData in get_all_parties():
		if party.leader_unit_id == unit_id:
			return true
	return false


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


# ---------------------------------------------------------------------------
# 俘虏归属（阶段 13）
# ---------------------------------------------------------------------------
# 俘虏与成员互斥：加入俘虏列表前必须先从原部队移除成员关系。
# 归属由 UnitData.prisoner_owner_party_id 与 PartyData.prisoner_unit_ids
# 双向维护；敌方单位允许加入胜利方俘虏列表，不受阵营一致性限制。


## 返回部队持有的俘虏 ID 副本。
func get_prisoner_ids(party_id: String) -> Array[String]:
	var party := get_party(party_id)
	if party == null:
		return []
	return party.prisoner_unit_ids.duplicate()


func get_prisoner_units(party_id: String) -> Array[UnitData]:
	var result: Array[UnitData] = []
	if _unit_manager == null:
		return result
	for unit_id: String in get_prisoner_ids(party_id):
		var unit := _unit_manager.get_unit(unit_id)
		if unit != null:
			result.append(unit)
	return result


func get_prisoner_owner_party_id(unit_id: String) -> String:
	if _unit_manager == null:
		return ""
	var unit := _unit_manager.get_unit(unit_id)
	return unit.prisoner_owner_party_id if unit != null else ""


func is_prisoner(unit_id: String) -> bool:
	return not get_prisoner_owner_party_id(unit_id).is_empty()


## 将单位加入部队俘虏列表。单位必须存在、不是任何部队成员、
## 且尚未被其他部队关押。所有校验通过后才修改数据。
func add_prisoner(party_id: String, unit_id: String) -> bool:
	var party := get_party(party_id)
	if party == null:
		push_warning("PartyManager.add_prisoner: 部队不存在 %s" % party_id)
		return false
	if _unit_manager == null:
		push_error("PartyManager 尚未装配 UnitManager")
		return false
	var unit := _unit_manager.get_unit(unit_id)
	if unit == null:
		push_warning("PartyManager.add_prisoner: 单位不存在 %s" % unit_id)
		return false
	if party.prisoner_unit_ids.has(unit_id):
		return false
	if not unit.current_party_id.is_empty() or _is_member_of_any_party(unit_id):
		push_warning(
			"PartyManager.add_prisoner: 单位 %s 仍是部队成员，不能成为俘虏" % unit_id
		)
		return false
	if not unit.prisoner_owner_party_id.is_empty():
		push_warning(
			"PartyManager.add_prisoner: 单位 %s 已被部队 %s 关押"
			% [unit_id, unit.prisoner_owner_party_id]
		)
		return false
	if unit.status == UnitData.Status.DEAD:
		return false

	party.prisoner_unit_ids.append(unit_id)
	unit.mark_prisoner(party_id)
	return true


## 在部队之间转移俘虏；任一校验失败时不修改数据。
func transfer_prisoner(unit_id: String, target_party_id: String) -> bool:
	var target := get_party(target_party_id)
	if target == null or _unit_manager == null:
		return false
	var unit := _unit_manager.get_unit(unit_id)
	if unit == null:
		return false
	if target.prisoner_unit_ids.has(unit_id):
		return true
	if not unit.current_party_id.is_empty() or _is_member_of_any_party(unit_id):
		return false
	var old_owner := unit.prisoner_owner_party_id
	if not old_owner.is_empty() and not remove_prisoner(old_owner, unit_id):
		return false
	return add_prisoner(target_party_id, unit_id)


## 从部队俘虏列表移除并清空归属；Unit 数据保留。
func remove_prisoner(party_id: String, unit_id: String) -> bool:
	var party := get_party(party_id)
	if party == null or not party.prisoner_unit_ids.has(unit_id):
		return false
	_remove_all_occurrences(party.prisoner_unit_ids, unit_id)
	if _unit_manager != null:
		var unit := _unit_manager.get_unit(unit_id)
		if unit != null and unit.prisoner_owner_party_id == party_id:
			unit.clear_prisoner_ownership()
	return true


## 按单位 ID 释放俘虏（找到当前关押部队后移除）。
func release_prisoner(unit_id: String) -> bool:
	var owner_id: String = get_prisoner_owner_party_id(unit_id)
	if owner_id.is_empty():
		return false
	return remove_prisoner(owner_id, unit_id)


func _is_member_of_any_party(unit_id: String) -> bool:
	for party: PartyData in get_all_parties():
		if party.member_unit_ids.has(unit_id):
			return true
	return false


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

		# 领袖必须是本部队的有效成员，避免读档后遭遇/战斗 UI 引用悬空单位。
		if not party.leader_unit_id.is_empty():
			if not party.member_unit_ids.has(party.leader_unit_id):
				errors.append(
					"部队 %s 的领袖 %s 不在该部队成员列表中"
					% [party.party_id, party.leader_unit_id]
				)
			elif _unit_manager.get_unit(party.leader_unit_id) == null:
				errors.append(
					"部队 %s 的领袖 %s 不存在" % [party.party_id, party.leader_unit_id]
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

	# 阶段 13：俘虏与成员互斥，且俘虏双向归属必须一致。
	var prisoner_to_party: Dictionary = {}
	for party: PartyData in get_all_parties():
		var local_seen: Dictionary = {}
		for unit_id: String in party.prisoner_unit_ids:
			if local_seen.has(unit_id):
				errors.append("部队 %s 的俘虏列表重复包含单位 %s" % [party.party_id, unit_id])
				continue
			local_seen[unit_id] = true
			if unit_to_party.has(unit_id):
				errors.append(
					"单位 %s 同时是部队 %s 的成员和部队 %s 的俘虏"
					% [unit_id, unit_to_party[unit_id], party.party_id]
				)
				continue
			if prisoner_to_party.has(unit_id):
				errors.append(
					"单位 %s 同时被部队 %s 和 %s 关押"
					% [unit_id, prisoner_to_party[unit_id], party.party_id]
				)
				continue
			prisoner_to_party[unit_id] = party.party_id
			var unit := _unit_manager.get_unit(unit_id)
			if unit == null:
				errors.append("部队 %s 的俘虏 %s 不存在" % [party.party_id, unit_id])
			elif unit.prisoner_owner_party_id != party.party_id:
				errors.append(
					"单位 %s 的俘虏归属=%s 与部队 %s 的俘虏列表不一致"
					% [unit_id, unit.prisoner_owner_party_id, party.party_id]
				)

	for unit: UnitData in _unit_manager.get_all_units():
		if unit.prisoner_owner_party_id.is_empty():
			continue
		if not prisoner_to_party.has(unit.unit_id):
			errors.append(
				"单位 %s 的俘虏归属=%s，但不在该部队俘虏列表中"
				% [unit.unit_id, unit.prisoner_owner_party_id]
			)
	return errors


## 读档后校正俘虏双向归属；幂等，只修复明显不一致的数据。
## 成员身份优先：同一单位同时出现在两处时保留成员关系并解除俘虏归属。
func sanitize_prisoner_ownership() -> Array[String]:
	var notes: Array[String] = []
	if _unit_manager == null:
		return notes

	var member_ids: Dictionary = {}
	for party: PartyData in get_all_parties():
		for unit_id: String in party.member_unit_ids:
			member_ids[unit_id] = true

	var claimed: Dictionary = {}
	for party: PartyData in get_all_parties():
		var cleaned: Array[String] = []
		for unit_id: String in party.prisoner_unit_ids:
			var unit := _unit_manager.get_unit(unit_id)
			if unit == null:
				notes.append("移除不存在单位 %s 的俘虏记录" % unit_id)
				continue
			if member_ids.has(unit_id):
				notes.append("单位 %s 仍是成员，解除俘虏记录" % unit_id)
				unit.clear_prisoner_ownership()
				continue
			if claimed.has(unit_id):
				notes.append(
					"单位 %s 重复出现在多支部队俘虏列表，保留 %s"
					% [unit_id, claimed[unit_id]]
				)
				continue
			claimed[unit_id] = party.party_id
			cleaned.append(unit_id)
		if cleaned.size() != party.prisoner_unit_ids.size():
			party.prisoner_unit_ids.clear()
			party.prisoner_unit_ids.append_array(cleaned)

	# 以俘虏列表为准修复 Unit 归属；列表外的归属一律清空。
	for unit: UnitData in _unit_manager.get_all_units():
		if member_ids.has(unit.unit_id):
			if not unit.prisoner_owner_party_id.is_empty():
				unit.clear_prisoner_ownership()
			continue
		if claimed.has(unit.unit_id):
			unit.prisoner_owner_party_id = str(claimed[unit.unit_id])
			unit.current_party_id = ""
		elif not unit.prisoner_owner_party_id.is_empty():
			notes.append("清除单位 %s 的悬空俘虏归属" % unit.unit_id)
			unit.clear_prisoner_ownership()
	return notes


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


## 读档后统一补齐运行时默认值：玩家部队控制权、旧存档缺失的部队类型。
## 必须在成员关系校验前调用，但不修改成员、位置或路线数据。
func apply_runtime_defaults(player_party_id: String) -> void:
	for party: PartyData in get_all_parties():
		if party != null:
			party.apply_runtime_defaults(player_party_id)


## 读档后清理仅运行时字段与已失效的战斗/追逐状态。
##
## 存档不保存活动战斗会话，因此 IN_BATTLE/RETURNING 必须回落为可行动状态，
## 否则部队会永久卡在战斗状态。返回被修正项的说明列表，供日志与测试核对。
func sanitize_loaded_runtime_state() -> Array[String]:
	var notes: Array[String] = []
	for party: PartyData in get_all_parties():
		if party == null:
			continue
		# 这些字段不进入存档，读档时一律视为“无意图”。
		party.attack_intent = false
		party.focus_party_id = ""
		party.engagement_cooldown_until = 0.0

		if party.battle_state == PartyData.BattleState.IN_BATTLE \
				or party.battle_state == PartyData.BattleState.RETURNING:
			var fallback: PartyData.BattleState = (
				PartyData.BattleState.DISABLED
				if party.member_unit_ids.is_empty()
				else PartyData.BattleState.AVAILABLE
			)
			notes.append(
				"部队 %s 无活动战斗，战斗状态回落为 %s"
				% [party.party_id, PartyData.BattleState.keys()[fallback]]
			)
			party.battle_state = fallback

		# 战斗指令已随战斗结束失效。
		if party.current_order == PartyData.OrderType.BATTLE:
			party.current_order = PartyData.OrderType.NONE

		# 追逐/跟随目标不存在时清理引用；仅在目标确实失效时停止移动，
		# 避免无故丢弃存档中有效的移动目标。
		if not party.current_target_id.is_empty() \
				and get_party(party.current_target_id) == null:
			notes.append(
				"部队 %s 的追击目标 %s 不存在，已清除"
				% [party.party_id, party.current_target_id]
			)
			party.current_target_id = ""
			if party.current_order == PartyData.OrderType.FOLLOW_PARTY:
				party.current_order = PartyData.OrderType.NONE
			if party.movement_state == PartyData.MovementState.MOVING:
				party.movement_state = PartyData.MovementState.IDLE
				party.target_position = party.world_position
		elif party.current_order == PartyData.OrderType.FOLLOW_PARTY \
				and party.current_target_id.is_empty():
			party.current_order = PartyData.OrderType.NONE
	return notes


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
