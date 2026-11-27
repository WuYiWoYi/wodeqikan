class_name KingdomManager
extends RefCounted
## 王国数据仓储与政治关系维护的唯一入口。
##
## 本阶段提供的核心规则：
## - 一个王国只有一个统治家族和一位国王；
## - 一个家族同一时间最多隶属于一个王国；
## - 附庸家族保留自己的领袖、贵族、部队与封地；
## - 王国战争关系对称保存，并由 FactionManager 传递给家族/部队查询。
##
## 不实现建立王国、加入/退出王国、宣战/停战 UI 与 AI 决策。

var _kingdoms: Dictionary = {}
var _id_generator: IdGenerator = null
var _house_manager: HouseManager = null
var _noble_manager: NobleManager = null
var _world_log_manager: WorldLogManager = null

var last_error: String = ""


func setup(
	id_generator: IdGenerator,
	house_manager: HouseManager,
	noble_manager: NobleManager
) -> void:
	_id_generator = id_generator
	_house_manager = house_manager
	_noble_manager = noble_manager


func set_world_log_manager(world_log_manager: WorldLogManager) -> void:
	_world_log_manager = world_log_manager


func create_kingdom(
	kingdom_name: String,
	ruling_house_id: String,
	king_noble_id: String,
	kingdom_color: Color = Color.WHITE
) -> KingdomData:
	if _id_generator == null:
		push_error("KingdomManager 尚未初始化 IdGenerator")
		return null
	return register_kingdom(
		_id_generator.next_id(IdGenerator.KINGDOM),
		kingdom_name,
		ruling_house_id,
		king_noble_id,
		kingdom_color
	)


## 注册固定 ID 的王国（初始世界配置）；重复 ID 拒绝覆盖。
func register_kingdom(
	kingdom_id: String,
	kingdom_name: String,
	ruling_house_id: String,
	king_noble_id: String,
	kingdom_color: Color = Color.WHITE
) -> KingdomData:
	if kingdom_id.strip_edges().is_empty() or kingdom_name.strip_edges().is_empty():
		last_error = "王国 ID 或名称不能为空。"
		return null
	if _kingdoms.has(kingdom_id):
		push_error("王国 ID 已存在，拒绝覆盖: %s" % kingdom_id)
		last_error = "王国 ID 已存在。"
		return null
	var house := _house_manager.get_house(ruling_house_id) \
		if _house_manager != null else null
	var king := _noble_manager.get_noble(king_noble_id) \
		if _noble_manager != null else null
	if house == null or king == null or not king.alive:
		last_error = "统治家族或国王无效，无法建立王国。"
		return null
	if house.leader_noble_id != king_noble_id:
		last_error = "国王必须是统治家族的领袖。"
		return null
	if int(king.rank) < int(NobleData.Rank.BARON):
		last_error = "骑士级家族不能成为王国统治家族。"
		return null
	if not house.kingdom_id.is_empty():
		last_error = "该家族已隶属于其他王国。"
		return null

	var kingdom := KingdomData.new()
	kingdom.kingdom_id = kingdom_id
	kingdom.kingdom_name = kingdom_name
	kingdom.ruling_house_id = ruling_house_id
	kingdom.king_noble_id = king_noble_id
	kingdom.kingdom_color = kingdom_color
	kingdom.is_active = true
	_kingdoms[kingdom.kingdom_id] = kingdom

	house.kingdom_id = kingdom.kingdom_id
	_sync_king_flags(kingdom, king_noble_id)
	last_error = ""
	return kingdom


func get_kingdom(kingdom_id: String) -> KingdomData:
	return _kingdoms.get(kingdom_id) as KingdomData


func get_all_kingdoms() -> Array[KingdomData]:
	var result: Array[KingdomData] = []
	for value: Variant in _kingdoms.values():
		var kingdom := value as KingdomData
		if kingdom != null:
			result.append(kingdom)
	result.sort_custom(func(a: KingdomData, b: KingdomData) -> bool:
		return a.kingdom_id < b.kingdom_id
	)
	return result


func get_active_kingdoms() -> Array[KingdomData]:
	var result: Array[KingdomData] = []
	for kingdom: KingdomData in get_all_kingdoms():
		if kingdom.is_active:
			result.append(kingdom)
	return result


func get_kingdom_for_house(house_id: String) -> KingdomData:
	var house := _house_manager.get_house(house_id) \
		if _house_manager != null else null
	if house == null or house.kingdom_id.is_empty():
		return null
	return get_kingdom(house.kingdom_id)


func get_ruling_house(kingdom_id: String) -> HouseData:
	var kingdom := get_kingdom(kingdom_id)
	if kingdom == null:
		return null
	return _house_manager.get_house(kingdom.ruling_house_id) \
		if _house_manager != null else null


func get_king(kingdom_id: String) -> NobleData:
	var kingdom := get_kingdom(kingdom_id)
	if kingdom == null or kingdom.king_noble_id.is_empty():
		return null
	return _noble_manager.get_noble(kingdom.king_noble_id) \
		if _noble_manager != null else null


func get_vassal_houses(kingdom_id: String) -> Array[HouseData]:
	var result: Array[HouseData] = []
	var kingdom := get_kingdom(kingdom_id)
	if kingdom == null or _house_manager == null:
		return result
	for house_id: String in kingdom.vassal_house_ids:
		var house := _house_manager.get_house(house_id)
		if house != null:
			result.append(house)
	return result


func get_all_houses_of_kingdom(kingdom_id: String) -> Array[HouseData]:
	var result: Array[HouseData] = []
	var ruling := get_ruling_house(kingdom_id)
	if ruling != null:
		result.append(ruling)
	result.append_array(get_vassal_houses(kingdom_id))
	return result


func get_kingdom_settlements(kingdom_id: String) -> Array[SettlementData]:
	var result: Array[SettlementData] = []
	if _house_manager == null:
		return result
	for house: HouseData in get_all_houses_of_kingdom(kingdom_id):
		result.append_array(_house_manager.get_house_settlements(house.house_id))
	return result


## 把家族加入王国附庸列表。统治家族不能作为普通附庸重复加入。
func add_vassal_house(kingdom_id: String, house_id: String) -> bool:
	var kingdom := get_kingdom(kingdom_id)
	var house := _house_manager.get_house(house_id) \
		if _house_manager != null else null
	if kingdom == null or house == null:
		last_error = "王国或家族不存在。"
		return false
	if house_id == kingdom.ruling_house_id:
		last_error = "统治家族不能作为普通附庸。"
		return false
	if not house.kingdom_id.is_empty() and house.kingdom_id != kingdom_id:
		last_error = "该家族已隶属于其他王国。"
		return false
	house.kingdom_id = kingdom_id
	house.overlord_house_id = kingdom.ruling_house_id
	if not kingdom.vassal_house_ids.has(house_id):
		kingdom.vassal_house_ids.append(house_id)
	_sync_king_flags(kingdom, kingdom.king_noble_id)
	last_error = ""
	EventBus.faction_relations_changed.emit()
	return true


func remove_vassal_house(kingdom_id: String, house_id: String) -> bool:
	var kingdom := get_kingdom(kingdom_id)
	var house := _house_manager.get_house(house_id) \
		if _house_manager != null else null
	if kingdom == null or house == null:
		return false
	var was_member: bool = kingdom.vassal_house_ids.has(house_id)
	kingdom.vassal_house_ids.erase(house_id)
	if house.kingdom_id == kingdom_id:
		house.kingdom_id = ""
		house.overlord_house_id = ""
	if was_member:
		EventBus.faction_relations_changed.emit()
	return true


## 宣战/停战关系必须对称保存。
func declare_war(a_kingdom_id: String, b_kingdom_id: String) -> bool:
	if a_kingdom_id == b_kingdom_id:
		return false
	var a := get_kingdom(a_kingdom_id)
	var b := get_kingdom(b_kingdom_id)
	if a == null or b == null:
		return false
	var changed: bool = false
	if not a.enemy_kingdom_ids.has(b_kingdom_id):
		a.enemy_kingdom_ids.append(b_kingdom_id)
		changed = true
	if not b.enemy_kingdom_ids.has(a_kingdom_id):
		b.enemy_kingdom_ids.append(a_kingdom_id)
		changed = true
	if changed:
		EventBus.faction_relations_changed.emit()
	return true


func end_war(a_kingdom_id: String, b_kingdom_id: String) -> bool:
	var a := get_kingdom(a_kingdom_id)
	var b := get_kingdom(b_kingdom_id)
	if a == null or b == null:
		return false
	var changed: bool = a.enemy_kingdom_ids.has(b_kingdom_id) \
		or b.enemy_kingdom_ids.has(a_kingdom_id)
	a.enemy_kingdom_ids.erase(b_kingdom_id)
	b.enemy_kingdom_ids.erase(a_kingdom_id)
	if changed:
		EventBus.faction_relations_changed.emit()
	return true


func are_at_war(a_kingdom_id: String, b_kingdom_id: String) -> bool:
	if a_kingdom_id.is_empty() or b_kingdom_id.is_empty() \
			or a_kingdom_id == b_kingdom_id:
		return false
	var a := get_kingdom(a_kingdom_id)
	return a != null and a.is_at_war_with(b_kingdom_id)


func get_enemy_kingdoms(kingdom_id: String) -> Array[KingdomData]:
	var result: Array[KingdomData] = []
	var kingdom := get_kingdom(kingdom_id)
	if kingdom == null:
		return result
	for enemy_id: String in kingdom.enemy_kingdom_ids:
		var enemy := get_kingdom(enemy_id)
		if enemy != null:
			result.append(enemy)
	return result


## 家族领袖变更：统治家族的新领袖自动继承国王身份。
func on_house_leader_changed(house_id: String, new_leader_id: String) -> void:
	for kingdom: KingdomData in get_all_kingdoms():
		if kingdom.ruling_house_id != house_id:
			continue
		var leader := _noble_manager.get_noble(new_leader_id) \
			if _noble_manager != null else null
		if leader == null or not leader.alive \
				or int(leader.rank) < int(NobleData.Rank.BARON):
			mark_ruling_house_leaderless(house_id)
			continue
		kingdom.king_noble_id = new_leader_id
		kingdom.is_active = true
		_sync_king_flags(kingdom, new_leader_id)


func mark_ruling_house_leaderless(house_id: String) -> void:
	for kingdom: KingdomData in get_all_kingdoms():
		if kingdom.ruling_house_id != house_id:
			continue
		kingdom.king_noble_id = ""
		kingdom.is_active = false
		_log(
			WorldLogEntry.EventType.KINGDOM_PENDING,
			"%s 失去有效国王，王国进入待处理状态。" % kingdom.kingdom_name,
			{"kingdom_id": kingdom.kingdom_id, "house_id": house_id}
		)


func _sync_king_flags(kingdom: KingdomData, king_noble_id: String) -> void:
	# 只清理本王国贵族的国王标记；其他王国由各自同步逻辑维护，互不覆盖。
	for house: HouseData in get_all_houses_of_kingdom(kingdom.kingdom_id):
		for noble: NobleData in _house_manager.get_house_nobles(house.house_id, true):
			noble.is_king = noble.lord_id == king_noble_id


func validate() -> Array[String]:
	var errors: Array[String] = []
	for kingdom: KingdomData in get_all_kingdoms():
		if kingdom == null:
			continue
		var ruling := _house_manager.get_house(kingdom.ruling_house_id) \
			if _house_manager != null else null
		if ruling == null:
			errors.append(
				"王国 %s 的统治家族 %s 不存在"
				% [kingdom.kingdom_id, kingdom.ruling_house_id]
			)
			continue
		if ruling.kingdom_id != kingdom.kingdom_id:
			errors.append("统治家族 %s 的王国归属不一致" % ruling.house_id)
		var king := _noble_manager.get_noble(kingdom.king_noble_id) \
			if _noble_manager != null else null
		if kingdom.is_active:
			if king == null:
				errors.append("王国 %s 缺少有效国王" % kingdom.kingdom_id)
			else:
				if king.house_id != ruling.house_id:
					errors.append("国王 %s 不属于统治家族" % king.lord_id)
				if ruling.leader_noble_id != king.lord_id:
					errors.append("国王 %s 不是统治家族领袖" % king.lord_id)
				if not king.is_king:
					errors.append("国王 %s 缺少 is_king 标记" % king.lord_id)
		for house_id: String in kingdom.vassal_house_ids:
			if house_id == kingdom.ruling_house_id:
				errors.append("王国 %s 把统治家族重复列为附庸" % kingdom.kingdom_id)
				continue
			var house := _house_manager.get_house(house_id) \
				if _house_manager != null else null
			if house == null:
				errors.append("王国 %s 引用了不存在的附庸家族 %s" % [kingdom.kingdom_id, house_id])
			elif house.kingdom_id != kingdom.kingdom_id:
				errors.append("附庸家族 %s 的王国归属不一致" % house_id)
		for enemy_id: String in kingdom.enemy_kingdom_ids:
			var enemy := get_kingdom(enemy_id)
			if enemy == null:
				errors.append("王国 %s 引用了不存在的敌国 %s" % [kingdom.kingdom_id, enemy_id])
			elif not enemy.enemy_kingdom_ids.has(kingdom.kingdom_id):
				errors.append("王国 %s 与 %s 的战争关系不对称" % [kingdom.kingdom_id, enemy_id])
	return errors


func to_dict() -> Dictionary:
	var payload: Dictionary = {}
	for kingdom_id: String in _kingdoms:
		var kingdom := _kingdoms[kingdom_id] as KingdomData
		if kingdom != null:
			payload[kingdom_id] = kingdom.to_dict()
	return payload


func load_from_dict(payload: Dictionary) -> void:
	_kingdoms.clear()
	for kingdom_id: Variant in payload:
		var value: Variant = payload[kingdom_id]
		if not value is Dictionary:
			continue
		var kingdom := KingdomData.from_dict(value)
		if kingdom.kingdom_id.is_empty():
			kingdom.kingdom_id = str(kingdom_id)
		if kingdom.kingdom_id.is_empty() or _kingdoms.has(kingdom.kingdom_id):
			continue
		_kingdoms[kingdom.kingdom_id] = kingdom


func _log(event_type: WorldLogEntry.EventType, text: String, metadata: Dictionary) -> void:
	if _world_log_manager != null:
		_world_log_manager.add_event(event_type, text, metadata)
