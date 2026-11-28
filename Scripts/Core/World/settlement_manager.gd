class_name SettlementManager
extends RefCounted
## 地点数据仓储与序列化。
##
## 只管理 SettlementData，不负责场景标记、交互面板或地点模拟。

var _settlements: Dictionary = {}
var _id_generator: IdGenerator = null


func setup(id_generator: IdGenerator) -> void:
	_id_generator = id_generator


func create_settlement(
	display_name: String,
	settlement_type: SettlementData.SettlementType,
	world_position: Vector2,
	faction_id: String = "",
	population: int = 0,
	prosperity: int = 0,
	map_key: String = ""
) -> SettlementData:
	if _id_generator == null:
		push_error("SettlementManager 尚未初始化 IdGenerator")
		return null

	var settlement := SettlementData.new()
	settlement.settlement_id = _id_generator.next_id(IdGenerator.SETTLEMENT)
	settlement.display_name = display_name
	settlement.map_key = map_key
	settlement.settlement_type = settlement_type
	settlement.world_position = world_position
	settlement.faction_id = faction_id
	settlement.population = population
	settlement.prosperity = prosperity
	# 户数暂以人口作为占位默认值，后续地图/地点配置可直接覆盖该字段。
	settlement.households = maxi(0, population)
	_settlements[settlement.settlement_id] = settlement
	return settlement


func add_settlement(settlement: SettlementData) -> String:
	if settlement == null:
		return ""
	if settlement.settlement_id.is_empty():
		if _id_generator == null:
			push_error("SettlementManager 无法为无 ID 地点分配 ID")
			return ""
		settlement.settlement_id = _id_generator.next_id(IdGenerator.SETTLEMENT)
	_settlements[settlement.settlement_id] = settlement
	return settlement.settlement_id


func get_settlement(settlement_id: String) -> SettlementData:
	return _settlements.get(settlement_id) as SettlementData


func has_settlement(settlement_id: String) -> bool:
	return _settlements.has(settlement_id)


func remove_settlement(settlement_id: String) -> void:
	_settlements.erase(settlement_id)


func get_all_settlements() -> Array[SettlementData]:
	var result: Array[SettlementData] = []
	for value: Variant in _settlements.values():
		var settlement := value as SettlementData
		if settlement != null:
			result.append(settlement)
	return result


## 村庄破坏状态接口：状态由 SettlementData 持有，UI 不直接改。
## 本阶段只提供写入与查询，不实现具体破坏事件。
func set_settlement_destroyed(settlement_id: String, destroyed: bool) -> bool:
	var settlement := get_settlement(settlement_id)
	if settlement == null:
		return false
	if settlement.settlement_type != SettlementData.SettlementType.VILLAGE:
		return false
	settlement.set_destroyed(destroyed)
	return true


func is_settlement_destroyed(settlement_id: String) -> bool:
	var settlement := get_settlement(settlement_id)
	return settlement != null and settlement.is_destroyed()


func to_dict() -> Dictionary:
	var payload: Dictionary = {}
	for settlement_id: String in _settlements:
		var settlement := _settlements[settlement_id] as SettlementData
		if settlement != null:
			payload[settlement_id] = settlement.to_dict()
	return payload


func load_from_dict(payload: Dictionary) -> void:
	_settlements.clear()
	for settlement_id: Variant in payload:
		var value: Variant = payload[settlement_id]
		if not value is Dictionary:
			continue
		var settlement := SettlementData.from_dict(value)
		if not settlement.settlement_id.is_empty():
			_settlements[settlement.settlement_id] = settlement
