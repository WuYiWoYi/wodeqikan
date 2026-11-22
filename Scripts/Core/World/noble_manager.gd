class_name NobleManager
extends LordManager
## 贵族数据仓储、等级、上下级关系与死亡处理的唯一入口。
##
## 继承 LordManager 以兼容旧接口（get_lord / get_all_lords / party_id 唯一约束）；
## 实际存储的实例统一为 NobleData，因此旧系统读取 lord_id 时仍然有效。
##
## 本阶段约束：
## - 一个贵族同一时间最多指挥一支主部队（party_id 唯一）；
## - 不允许自己成为自己的上级，也不允许循环上下级；
## - 贵族死亡时清理无效上级引用，并触达家族领袖推举。

var _house_manager: HouseManager = null
var _kingdom_manager: KingdomManager = null
var _world_log_manager: WorldLogManager = null


func setup_political(
	house_manager: HouseManager,
	kingdom_manager: KingdomManager = null,
	world_log_manager: WorldLogManager = null
) -> void:
	_house_manager = house_manager
	_kingdom_manager = kingdom_manager
	_world_log_manager = world_log_manager


## 创建一个 NobleData；参数保持与旧 LordManager.create_lord 兼容。
func create_lord(
	display_name: String,
	faction_id: String,
	party_id: String,
	is_player_lord: bool = false
) -> LordData:
	var noble := create_noble(
		display_name, faction_id, party_id, "", NobleData.Rank.KNIGHT, is_player_lord
	)
	return noble


func create_noble(
	display_name: String,
	faction_id: String,
	party_id: String = "",
	house_id: String = "",
	rank: NobleData.Rank = NobleData.Rank.KNIGHT,
	is_player_lord: bool = false,
	is_house_leader: bool = false
) -> NobleData:
	if _id_generator == null:
		push_error("NobleManager 尚未初始化 IdGenerator")
		return null
	if not party_id.is_empty() and get_lord_by_party_id(party_id) != null:
		push_error("部队 %s 已属于其他贵族，拒绝重复分配" % party_id)
		return null

	var noble := NobleData.new()
	noble.lord_id = _id_generator.next_id(IdGenerator.LORD)
	noble.display_name = display_name if not display_name.strip_edges().is_empty() \
		else "无名贵族"
	noble.faction_id = faction_id
	noble.party_id = party_id
	noble.is_player_lord = is_player_lord
	noble.rank = rank
	noble.house_id = house_id
	noble.is_alive = true
	_lords[noble.lord_id] = noble

	if not house_id.is_empty() and _house_manager != null:
		var house := _house_manager.get_house(house_id)
		if house == null:
			push_warning("贵族 %s 的家族不存在: %s" % [noble.lord_id, house_id])
		else:
			_house_manager.attach_noble(house_id, noble)
			if is_house_leader:
				_house_manager.set_leader(house_id, noble.lord_id)
	return noble


func get_noble(noble_id: String) -> NobleData:
	return _lords.get(noble_id) as NobleData


func get_noble_by_party_id(party_id: String) -> NobleData:
	if party_id.is_empty():
		return null
	for value: Variant in _lords.values():
		var noble := value as NobleData
		if noble != null and noble.party_id == party_id:
			return noble
	return null


func get_player_noble() -> NobleData:
	for noble: NobleData in get_all_nobles():
		if noble != null and noble.is_player_lord:
			return noble
	return null


func get_all_nobles() -> Array[NobleData]:
	var result: Array[NobleData] = []
	for value: Variant in _lords.values():
		var noble := value as NobleData
		if noble != null:
			result.append(noble)
		else:
			var lord := value as LordData
			if lord != null:
				# 理论上不应出现；按只读兼容对象返回空，避免继续传播类型错误。
				push_warning("贵族仓储中出现非 NobleData 实例: %s" % lord.lord_id)
	return result


func get_nobles_of_house(house_id: String) -> Array[NobleData]:
	var result: Array[NobleData] = []
	for noble: NobleData in get_all_nobles():
		if noble.house_id == house_id:
			result.append(noble)
	return result


func get_alive_nobles_of_house(house_id: String) -> Array[NobleData]:
	var result: Array[NobleData] = []
	for noble: NobleData in get_nobles_of_house(house_id):
		if noble.alive:
			result.append(noble)
	return result


## 设置直接上级；拒绝自我引用与循环。
func set_liege(noble_id: String, liege_noble_id: String) -> bool:
	var noble := get_noble(noble_id)
	if noble == null or not noble.alive:
		return false
	if liege_noble_id.is_empty():
		noble.liege_noble_id = ""
		return true
	if liege_noble_id == noble_id:
		push_warning("贵族不能成为自己的上级: %s" % noble_id)
		return false
	var liege := get_noble(liege_noble_id)
	if liege == null or not liege.alive:
		return false
	var cursor := liege
	var guard: int = 0
	while cursor != null and not cursor.liege_noble_id.is_empty() and guard < 1024:
		if cursor.liege_noble_id == noble_id:
			push_warning("不允许形成循环上下级关系: %s -> %s" % [noble_id, liege_noble_id])
			return false
		cursor = get_noble(cursor.liege_noble_id)
		guard += 1
	noble.liege_noble_id = liege_noble_id
	return true


func get_liege(noble_id: String) -> NobleData:
	var noble := get_noble(noble_id)
	if noble == null or noble.liege_noble_id.is_empty():
		return null
	return get_noble(noble.liege_noble_id)


func get_direct_vassals(noble_id: String) -> Array[NobleData]:
	var result: Array[NobleData] = []
	for noble: NobleData in get_all_nobles():
		if noble.liege_noble_id == noble_id:
			result.append(noble)
	return result


## 贵族死亡：清理上级引用、触达家族领袖推举，并写入世界日志。
func kill_noble(noble_id: String) -> bool:
	var noble := get_noble(noble_id)
	if noble == null or not noble.alive:
		return false

	noble.alive = false
	noble.is_king = false
	noble.is_house_leader = false
	noble.current_state = "DEAD"
	noble.current_goal = ""

	# 直属下级改为继承死者上级；没有有效上级时清空，避免引用死亡贵族。
	for vassal: NobleData in get_direct_vassals(noble_id):
		if vassal.lord_id == noble_id:
			continue
		vassal.liege_noble_id = noble.liege_noble_id if not noble.liege_noble_id.is_empty() \
			else ""
	noble.liege_noble_id = ""

	if _house_manager != null:
		_house_manager.handle_noble_death(noble)
	_log(
		WorldLogEntry.EventType.NOBLE_DIED,
		"%s 去世了。" % noble.display_name,
		{"noble_id": noble.lord_id, "house_id": noble.house_id}
	)
	return true


## 读档时以 NobleData 解析，并补齐 ID 计数器。
func load_from_dict(payload: Dictionary) -> void:
	_lords.clear()
	for noble_id: Variant in payload:
		var value: Variant = payload[noble_id]
		if not value is Dictionary:
			continue
		var noble := NobleData.from_dict(value)
		if noble.lord_id.is_empty():
			noble.lord_id = str(noble_id)
		if noble.lord_id.is_empty():
			continue
		if _lords.has(noble.lord_id):
			push_error("存档中存在重复贵族 ID，已跳过: %s" % noble.lord_id)
			continue
		if not noble.party_id.is_empty() and get_lord_by_party_id(noble.party_id) != null:
			push_error(
				"存档中部队 %s 被多个贵族引用，%s 已跳过"
				% [noble.party_id, noble.lord_id]
			)
			continue
		_lords[noble.lord_id] = noble

	if _id_generator != null:
		var max_value: int = _id_generator.peek_last_value(IdGenerator.LORD)
		for noble: NobleData in get_all_nobles():
			max_value = maxi(max_value, _extract_numeric_id(noble.lord_id))
		if max_value > _id_generator.peek_last_value(IdGenerator.LORD):
			var counters: Dictionary = _id_generator.to_dict()
			counters[IdGenerator.LORD] = max_value
			_id_generator.restore_from(counters)


## 在旧 LordManager 校验基础上追加贵族/家族/上下级校验。
func validate(party_manager: PartyManager = null) -> Array[String]:
	var errors: Array[String] = super.validate(party_manager)
	var ids: Dictionary = {}
	for noble: NobleData in get_all_nobles():
		if ids.has(noble.lord_id):
			errors.append("贵族 ID 重复: %s" % noble.lord_id)
		ids[noble.lord_id] = true
		if noble.house_id.is_empty():
			continue
		if _house_manager != null and _house_manager.get_house(noble.house_id) == null:
			errors.append("贵族 %s 引用了不存在的家族 %s" % [noble.lord_id, noble.house_id])
		if not noble.liege_noble_id.is_empty():
			if noble.liege_noble_id == noble.lord_id:
				errors.append("贵族 %s 的上级是自己" % noble.lord_id)
			elif get_noble(noble.liege_noble_id) == null:
				errors.append(
					"贵族 %s 引用了不存在的上级 %s"
					% [noble.lord_id, noble.liege_noble_id]
				)
			elif _has_liege_cycle(noble):
				errors.append("贵族 %s 存在循环上下级关系" % noble.lord_id)
	return errors


func _has_liege_cycle(start: NobleData) -> bool:
	var seen: Dictionary = {}
	var cursor := start
	while cursor != null and not cursor.liege_noble_id.is_empty():
		if seen.has(cursor.lord_id):
			return true
		seen[cursor.lord_id] = true
		cursor = get_noble(cursor.liege_noble_id)
	return false


func _log(event_type: WorldLogEntry.EventType, text: String, metadata: Dictionary) -> void:
	if _world_log_manager != null:
		_world_log_manager.add_event(event_type, text, metadata)
