class_name VisionManager
extends RefCounted
## 大地图部队视野查询的唯一入口。
##
## 采用简单的世界坐标距离检测：目标与观察者距离 <= observer.sight_range 即可见。
## 本类只查询数据，不修改位置、不触发移动、不参与 UI。
## 视野是即时的：目标离开范围后 can_see() 立即返回 false，调用方负责清除追击目标。

var _party_manager: PartyManager = null
var _faction_manager: FactionManager = null
var _unit_manager: UnitManager = null


func setup(
	party_manager: PartyManager,
	faction_manager: FactionManager,
	unit_manager: UnitManager = null
) -> void:
	_party_manager = party_manager
	_faction_manager = faction_manager
	_unit_manager = unit_manager


func can_see(observer_id: String, target_id: String) -> bool:
	if _party_manager == null:
		return false
	if observer_id.is_empty() or target_id.is_empty() or observer_id == target_id:
		return false
	var observer := _party_manager.get_party(observer_id)
	var target := _party_manager.get_party(target_id)
	if observer == null or target == null:
		return false
	if not _is_active_party(observer) or not _is_valid_target(target):
		return false
	return observer.world_position.distance_to(target.world_position) <= maxf(
		observer.sight_range, 0.0
	)


## 返回观察者当前可见的全部有效部队（不含自身、失效部队与空部队）。
func get_visible_parties(observer_id: String) -> Array[PartyData]:
	var result: Array[PartyData] = []
	if _party_manager == null:
		return result
	var observer := _party_manager.get_party(observer_id)
	if observer == null or not _is_active_party(observer):
		return result

	var sight: float = maxf(observer.sight_range, 0.0)
	for target: PartyData in _party_manager.get_all_parties():
		if target == null or target.party_id == observer_id:
			continue
		if not _is_valid_target(target):
			continue
		if observer.world_position.distance_to(target.world_position) <= sight:
			result.append(target)
	return result


func get_visible_hostile_parties(observer_id: String) -> Array[PartyData]:
	return _filter_by_relation(observer_id, FactionManager.Relation.HOSTILE)


func get_visible_friendly_parties(observer_id: String) -> Array[PartyData]:
	return _filter_by_relation(observer_id, FactionManager.Relation.FRIENDLY)


func get_visible_neutral_parties(observer_id: String) -> Array[PartyData]:
	return _filter_by_relation(observer_id, FactionManager.Relation.NEUTRAL)


## 最近的可见敌对部队；没有返回 null。
func get_nearest_visible_hostile(observer_id: String) -> PartyData:
	return _nearest(get_visible_hostile_parties(observer_id), observer_id)


## 最近的可见友方部队；没有返回 null。
func get_nearest_visible_friendly(observer_id: String) -> PartyData:
	return _nearest(get_visible_friendly_parties(observer_id), observer_id)


func get_distance(observer_id: String, target_id: String) -> float:
	if _party_manager == null:
		return INF
	var observer := _party_manager.get_party(observer_id)
	var target := _party_manager.get_party(target_id)
	if observer == null or target == null:
		return INF
	return observer.world_position.distance_to(target.world_position)


func _filter_by_relation(
	observer_id: String, relation: FactionManager.Relation
) -> Array[PartyData]:
	var result: Array[PartyData] = []
	if _party_manager == null:
		return result
	var observer := _party_manager.get_party(observer_id)
	if observer == null:
		return result
	for target: PartyData in get_visible_parties(observer_id):
		if _faction_manager == null:
			continue
		if _faction_manager.get_relation(observer.faction_id, target.faction_id) == relation:
			result.append(target)
	return result


func _nearest(parties: Array[PartyData], observer_id: String) -> PartyData:
	var observer := _party_manager.get_party(observer_id) if _party_manager != null else null
	if observer == null:
		return null
	var nearest: PartyData = null
	var nearest_distance: float = INF
	for target: PartyData in parties:
		var distance := observer.world_position.distance_to(target.world_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = target
	return nearest


## 观察者必须可用且有存活士兵；DISABLED / IN_BATTLE 部队不主动发现目标。
func _is_active_party(party: PartyData) -> bool:
	if party == null or not party.is_available_for_world():
		return false
	return _has_living_member(party)


## 可被发现/追击的目标：可用、有存活士兵、不是空部队。
func _is_valid_target(party: PartyData) -> bool:
	if party == null or not party.is_available_for_world():
		return false
	return _has_living_member(party)


func _has_living_member(party: PartyData) -> bool:
	if party.member_unit_ids.is_empty():
		return false
	if _unit_manager == null:
		return true
	for unit_id: String in party.member_unit_ids:
		var unit := _unit_manager.get_unit(unit_id)
		if unit != null and unit.is_alive():
			return true
	return false
