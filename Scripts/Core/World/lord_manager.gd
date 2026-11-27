class_name LordManager
extends RefCounted
## 领主数据仓储、创建、查询与序列化。
##
## 只管理 LordData，不负责部队移动、封地模拟或 UI。
## 约束：
## - 一个领主的所属部队唯一；同一个 party_id 不能分配给两个领主。
## - 封地通过 SettlementData.owner_house_id 归属家族，不再关联个人领主。
## - 玩家领主用 is_player_lord 标记，不等同于玩家角色。

var _lords: Dictionary = {}
var _id_generator: IdGenerator = null
var _party_manager: PartyManager = null


func setup(id_generator: IdGenerator, party_manager: PartyManager = null) -> void:
	_id_generator = id_generator
	_party_manager = party_manager


func create_lord(
	display_name: String,
	faction_id: String,
	party_id: String,
	is_player_lord: bool = false
) -> LordData:
	if _id_generator == null:
		push_error("LordManager 尚未初始化 IdGenerator")
		return null
	if not party_id.is_empty() and get_lord_by_party_id(party_id) != null:
		push_error("部队 %s 已属于其他领主，拒绝重复分配" % party_id)
		return null

	var lord := LordData.new()
	lord.lord_id = _id_generator.next_id(IdGenerator.LORD)
	lord.display_name = display_name if not display_name.strip_edges().is_empty() else "无名领主"
	lord.faction_id = faction_id
	lord.party_id = party_id
	lord.is_player_lord = is_player_lord
	_lords[lord.lord_id] = lord
	return lord


## 注册已有 LordData。ID 已存在或 party_id 已被占用时拒绝，返回空字符串。
func add_lord(lord: LordData) -> String:
	if lord == null:
		return ""
	if lord.lord_id.is_empty():
		if _id_generator == null:
			push_error("LordManager 无法为无 ID 领主分配 ID")
			return ""
		lord.lord_id = _id_generator.next_id(IdGenerator.LORD)
	if _lords.has(lord.lord_id):
		push_error("领主 ID 已存在，拒绝覆盖: %s" % lord.lord_id)
		return ""
	if not lord.party_id.is_empty():
		var existing := get_lord_by_party_id(lord.party_id)
		if existing != null and existing.lord_id != lord.lord_id:
			push_error(
				"部队 %s 已属于领主 %s，拒绝重复分配"
				% [lord.party_id, existing.lord_id]
			)
			return ""
	_lords[lord.lord_id] = lord
	return lord.lord_id


func get_lord(lord_id: String) -> LordData:
	return _lords.get(lord_id) as LordData


func has_lord(lord_id: String) -> bool:
	return _lords.has(lord_id)


func get_lord_by_party_id(party_id: String) -> LordData:
	if party_id.is_empty():
		return null
	for lord: LordData in get_all_lords():
		if lord != null and lord.party_id == party_id:
			return lord
	return null


func get_player_lord() -> LordData:
	for lord: LordData in get_all_lords():
		if lord != null and lord.is_player_lord:
			return lord
	return null


func get_lords_of_faction(faction_id: String) -> Array[LordData]:
	var result: Array[LordData] = []
	for lord: LordData in get_all_lords():
		if lord != null and lord.faction_id == faction_id:
			result.append(lord)
	return result


func remove_lord(lord_id: String) -> bool:
	var lord := get_lord(lord_id)
	if lord == null:
		return false
	_lords.erase(lord_id)
	return true


func get_all_lords() -> Array[LordData]:
	var result: Array[LordData] = []
	for value: Variant in _lords.values():
		var lord := value as LordData
		if lord != null:
			result.append(lord)
	return result


## 读档/世界校验：领主 ID 唯一、部队存在且唯一、玩家领主至多一名。
func validate(party_manager: PartyManager = null) -> Array[String]:
	var errors: Array[String] = []
	var manager: PartyManager = party_manager if party_manager != null else _party_manager
	var party_owners: Dictionary = {}
	var player_lord_count: int = 0
	for lord: LordData in get_all_lords():
		if lord == null:
			continue
		if lord.is_player_lord:
			player_lord_count += 1
		if lord.party_id.is_empty():
			continue
		if party_owners.has(lord.party_id):
			errors.append(
				"部队 %s 同时属于领主 %s 与 %s"
				% [lord.party_id, party_owners[lord.party_id], lord.lord_id]
			)
			continue
		party_owners[lord.party_id] = lord.lord_id
		if manager != null and manager.get_party(lord.party_id) == null:
			errors.append(
				"领主 %s 的部队 %s 不存在" % [lord.lord_id, lord.party_id]
			)
	if player_lord_count > 1:
		errors.append("世界中存在多个玩家领主")
	return errors


func to_dict() -> Dictionary:
	var payload: Dictionary = {}
	for lord_id: String in _lords:
		var lord := _lords[lord_id] as LordData
		if lord != null:
			payload[lord_id] = lord.to_dict()
	return payload


func load_from_dict(payload: Dictionary) -> void:
	_lords.clear()
	for lord_id: Variant in payload:
		var value: Variant = payload[lord_id]
		if not value is Dictionary:
			continue
		var lord := LordData.from_dict(value)
		if lord.lord_id.is_empty():
			continue
		if _lords.has(lord.lord_id):
			push_error("存档中存在重复领主 ID，已跳过后续记录: %s" % lord.lord_id)
			continue
		if not lord.party_id.is_empty() and get_lord_by_party_id(lord.party_id) != null:
			push_error(
				"存档中部队 %s 被多个领主引用，领主 %s 已跳过"
				% [lord.party_id, lord.lord_id]
			)
			continue
		_lords[lord.lord_id] = lord

	# ID 计数器可能落后于已加载的领主编号；恢复时补齐，避免新领主 ID 重复。
	if _id_generator != null:
		var max_value: int = _id_generator.peek_last_value(IdGenerator.LORD)
		for lord: LordData in get_all_lords():
			max_value = maxi(max_value, _extract_numeric_id(lord.lord_id))
		if max_value > _id_generator.peek_last_value(IdGenerator.LORD):
			var counters: Dictionary = _id_generator.to_dict()
			counters[IdGenerator.LORD] = max_value
			_id_generator.restore_from(counters)


static func _extract_numeric_id(value: String) -> int:
	var parts: PackedStringArray = value.split("_")
	if parts.is_empty():
		return 0
	return int(parts[parts.size() - 1])
