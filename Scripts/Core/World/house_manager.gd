class_name HouseManager
extends RefCounted
## 家族数据仓储与领袖维护的唯一入口。
##
## 约束：
## - 每个家族最多一位有效领袖，且领袖必须是本家族存活贵族；
## - 家族与贵族的双向关系通过 attach_noble / remove_noble 维护；
## - 封地归属以 SettlementData.owner_house_id 为权威，settlement_ids 只做缓存；
## - 本阶段不实现血缘、年龄与声望等继承条件。

var _houses: Dictionary = {}
var _id_generator: IdGenerator = null
var _noble_manager: NobleManager = null
var _settlement_manager: SettlementManager = null
var _kingdom_manager: KingdomManager = null
var _world_log_manager: WorldLogManager = null

var last_error: String = ""


func setup(
	id_generator: IdGenerator,
	noble_manager: NobleManager,
	settlement_manager: SettlementManager = null
) -> void:
	_id_generator = id_generator
	_noble_manager = noble_manager
	_settlement_manager = settlement_manager


func setup_political(
	kingdom_manager: KingdomManager, world_log_manager: WorldLogManager = null
) -> void:
	_kingdom_manager = kingdom_manager
	_world_log_manager = world_log_manager


## 新建家族；ID 使用统一 IdGenerator。初始世界应使用 register_house 固定 ID。
func create_house(
	house_name: String,
	banner_id: String = "",
	is_player_house: bool = false
) -> HouseData:
	if _id_generator == null:
		push_error("HouseManager 尚未初始化 IdGenerator")
		return null
	return register_house(
		_id_generator.next_id(IdGenerator.HOUSE),
		house_name,
		banner_id,
		is_player_house
	)


## 注册固定 ID 的家族（初始世界配置）；重复 ID 拒绝覆盖。
func register_house(
	house_id: String,
	house_name: String,
	banner_id: String = "",
	is_player_house: bool = false
) -> HouseData:
	if house_id.strip_edges().is_empty() or house_name.strip_edges().is_empty():
		last_error = "家族 ID 或名称不能为空。"
		return null
	if _houses.has(house_id):
		push_error("家族 ID 已存在，拒绝覆盖: %s" % house_id)
		last_error = "家族 ID 已存在。"
		return null
	var house := HouseData.new()
	house.house_id = house_id
	house.house_name = house_name
	house.banner_id = banner_id if not banner_id.is_empty() else house_id
	house.is_player_house = is_player_house
	_houses[house_id] = house
	last_error = ""
	return house


func get_house(house_id: String) -> HouseData:
	return _houses.get(house_id) as HouseData


func has_house(house_id: String) -> bool:
	return _houses.has(house_id)


func get_all_houses() -> Array[HouseData]:
	var result: Array[HouseData] = []
	for value: Variant in _houses.values():
		var house := value as HouseData
		if house != null:
			result.append(house)
	return result


## 部队/地点保存的是视觉家族 ID（FamilyRegistry.family_id），
## 政治归属使用 house_id；banner_id 是两者之间的稳定映射。
func get_house_by_banner_id(banner_id: String) -> HouseData:
	if banner_id.is_empty():
		return null
	for house: HouseData in get_all_houses():
		if house != null and house.banner_id == banner_id:
			return house
	return null


func get_player_house() -> HouseData:
	for house: HouseData in get_all_houses():
		if house != null and house.is_player_house:
			return house
	return null


func get_house_leader(house_id: String) -> NobleData:
	var house := get_house(house_id)
	if house == null or house.leader_noble_id.is_empty():
		return null
	return _noble_manager.get_noble(house.leader_noble_id) \
		if _noble_manager != null else null


func get_house_nobles(house_id: String, include_dead: bool = true) -> Array[NobleData]:
	var result: Array[NobleData] = []
	var house := get_house(house_id)
	if house == null or _noble_manager == null:
		return result
	for noble_id: String in house.noble_ids:
		var noble := _noble_manager.get_noble(noble_id)
		if noble == null:
			continue
		if not include_dead and not noble.alive:
			continue
		result.append(noble)
	return result


## 家族封地以 SettlementData.owner_house_id 为权威来源；不依赖缓存列表。
func get_house_settlements(house_id: String) -> Array[SettlementData]:
	var result: Array[SettlementData] = []
	if _settlement_manager == null or house_id.is_empty():
		return result
	for settlement: SettlementData in _settlement_manager.get_all_settlements():
		if settlement != null and settlement.owner_house_id == house_id:
			result.append(settlement)
	return result


## 把贵族挂入家族。允许改换家族：先从旧家族移除，再写入新家族。
func attach_noble(house_id: String, noble: NobleData) -> bool:
	var house := get_house(house_id)
	if house == null or noble == null or not noble.alive:
		last_error = "家族不存在或贵族无效。"
		return false
	if not noble.house_id.is_empty() and noble.house_id != house_id:
		remove_noble(noble.house_id, noble.lord_id)
	noble.house_id = house_id
	if not house.noble_ids.has(noble.lord_id):
		house.noble_ids.append(noble.lord_id)
	# 新家族没有领袖时，优先让高爵位/ID 靠前的贵族成为领袖。
	if house.leader_noble_id.is_empty() and noble.alive:
		_apply_leader(house, noble)
	last_error = ""
	return true


func remove_noble(house_id: String, noble_id: String) -> bool:
	var house := get_house(house_id)
	if house == null:
		return false
	house.noble_ids.erase(noble_id)
	if house.leader_noble_id == noble_id:
		house.leader_noble_id = ""
		_elect_leader(house)
	return true


## 显式指定家族领袖；必须属于本家族且存活。
func set_leader(house_id: String, noble_id: String) -> bool:
	var house := get_house(house_id)
	var noble := _noble_manager.get_noble(noble_id) \
		if _noble_manager != null else null
	if house == null or noble == null or not noble.alive:
		last_error = "家族或贵族无效，无法指定领袖。"
		return false
	if noble.house_id != house_id or not house.noble_ids.has(noble_id):
		last_error = "该贵族不属于此家族。"
		return false
	_apply_leader(house, noble)
	last_error = ""
	return true


## 读档/迁移后确保家族领袖标记有效；没有领袖时按稳定规则推举。
func ensure_leader(house_id: String) -> NobleData:
	var house := get_house(house_id)
	if house == null:
		return null
	if not house.leader_noble_id.is_empty():
		var current := _noble_manager.get_noble(house.leader_noble_id) \
			if _noble_manager != null else null
		if current != null and current.alive \
				and current.house_id == house_id:
			_apply_leader(house, current)
			return current
		house.leader_noble_id = ""
	return _elect_leader(house)


## 贵族死亡后的家族兜底：领袖死亡则推举新领袖；无人可推举则标记待处理。
func handle_noble_death(noble: NobleData) -> void:
	if noble == null or noble.house_id.is_empty():
		return
	var house := get_house(noble.house_id)
	if house == null:
		return
	if house.leader_noble_id != noble.lord_id:
		return
	house.leader_noble_id = ""
	var elected := _elect_leader(house)
	if elected == null:
		_mark_house_leaderless(house)


func _elect_leader(house: HouseData) -> NobleData:
	if house == null or _noble_manager == null:
		return null
	var candidates := get_house_nobles(house.house_id, false)
	if candidates.is_empty():
		return null
	# 规则：爵位高者优先；同爵位按 noble_id 字典序，保证结果稳定。
	candidates.sort_custom(func(a: NobleData, b: NobleData) -> bool:
		if a.rank != b.rank:
			return int(a.rank) > int(b.rank)
		return a.lord_id < b.lord_id
	)
	var elected := candidates[0]
	_apply_leader(house, elected)
	_log(
		WorldLogEntry.EventType.HOUSE_LEADER_CHANGED,
		"%s 推举 %s 为新的家族领袖。" % [house.house_name, elected.display_name],
		{"house_id": house.house_id, "noble_id": elected.lord_id}
	)
	return elected


func _apply_leader(house: HouseData, noble: NobleData) -> void:
	for other: NobleData in get_house_nobles(house.house_id, true):
		other.is_house_leader = other.lord_id == noble.lord_id
	house.leader_noble_id = noble.lord_id
	if _kingdom_manager != null:
		_kingdom_manager.on_house_leader_changed(house.house_id, noble.lord_id)


func _mark_house_leaderless(house: HouseData) -> void:
	house.leader_noble_id = ""
	if _kingdom_manager != null:
		_kingdom_manager.mark_ruling_house_leaderless(house.house_id)
	_log(
		WorldLogEntry.EventType.KINGDOM_PENDING,
		"%s 没有可用的存活贵族，已标记为待处理家族。" % house.house_name,
		{"house_id": house.house_id}
	)


## 读档或封地变化后重建 settlement_ids 缓存。
func refresh_settlement_links() -> void:
	for house: HouseData in get_all_houses():
		house.settlement_ids.clear()
	if _settlement_manager == null:
		return
	for settlement: SettlementData in _settlement_manager.get_all_settlements():
		if settlement == null or settlement.owner_house_id.is_empty():
			continue
		var house := get_house(settlement.owner_house_id)
		if house != null and not house.settlement_ids.has(settlement.settlement_id):
			house.settlement_ids.append(settlement.settlement_id)


## 校验家族、贵族与王国引用的双向一致性。返回错误列表，不修改数据。
func validate() -> Array[String]:
	var errors: Array[String] = []
	for house: HouseData in get_all_houses():
		if house == null:
			continue
		if house.leader_noble_id.is_empty():
			# 允许世界初始化过程中尚未推举，但必须在加载校验前补齐。
			continue
		var leader := _noble_manager.get_noble(house.leader_noble_id) \
			if _noble_manager != null else null
		if leader == null:
			errors.append("家族 %s 的领袖 %s 不存在" % [house.house_id, house.leader_noble_id])
			continue
		if leader.house_id != house.house_id:
			errors.append("家族 %s 的领袖不属于本家族" % house.house_id)
		if not leader.alive:
			errors.append("家族 %s 的领袖已死亡" % house.house_id)
		for noble_id: String in house.noble_ids:
			var noble := _noble_manager.get_noble(noble_id) \
				if _noble_manager != null else null
			if noble == null:
				errors.append("家族 %s 引用了不存在的贵族 %s" % [house.house_id, noble_id])
			elif noble.house_id != house.house_id:
				errors.append("贵族 %s 的家族归属与家族登记不一致" % noble_id)
	return errors


func to_dict() -> Dictionary:
	var payload: Dictionary = {}
	for house_id: String in _houses:
		var house := _houses[house_id] as HouseData
		if house != null:
			payload[house_id] = house.to_dict()
	return payload


func load_from_dict(payload: Dictionary) -> void:
	_houses.clear()
	for house_id: Variant in payload:
		var value: Variant = payload[house_id]
		if not value is Dictionary:
			continue
		var house := HouseData.from_dict(value)
		if house.house_id.is_empty():
			house.house_id = str(house_id)
		if house.house_id.is_empty():
			continue
		if _houses.has(house.house_id):
			push_error("存档中存在重复家族 ID，已跳过: %s" % house.house_id)
			continue
		_houses[house.house_id] = house


func _log(event_type: WorldLogEntry.EventType, text: String, metadata: Dictionary) -> void:
	if _world_log_manager != null:
		_world_log_manager.add_event(event_type, text, metadata)
