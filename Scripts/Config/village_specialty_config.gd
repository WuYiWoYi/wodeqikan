class_name VillageSpecialtyConfig
extends Resource
## 村庄特产静态配置（Data/Settlements/village_specialties.tres）。
##
## 使用大地图定义的稳定 key 作为配置主键；建筑名称只用于旧存档迁移回退。
## 这里只保存“哪个村庄生产什么”，村庄户数与当前库存仍由 SettlementData /
## MarketData 持有。新增村庄或调整特产时只改这份数据，不改交易逻辑。

const DEFAULT_PATH: String = "res://Data/Settlements/village_specialties.tres"

## 三个数组一一对应，避免在 .tres 中手写复杂字典。
@export var settlement_keys: Array[String] = []
@export var display_names: Array[String] = []
@export var specialty_item_ids: Array[String] = []
## 可选户数覆盖；0 表示沿用人口作为户数。
@export var households: Array[int] = []


static func load_default() -> VillageSpecialtyConfig:
	if not ResourceLoader.exists(DEFAULT_PATH):
		return null
	return load(DEFAULT_PATH) as VillageSpecialtyConfig


func get_specialty_for_key(key: String) -> String:
	var index: int = settlement_keys.find(key)
	if index < 0 or index >= specialty_item_ids.size():
		return ""
	return specialty_item_ids[index]


func get_specialty_for_name(display_name: String) -> String:
	var index: int = display_names.find(display_name)
	if index < 0 or index >= specialty_item_ids.size():
		return ""
	return specialty_item_ids[index]


func get_key_for_name(display_name: String) -> String:
	var index: int = display_names.find(display_name)
	if index < 0 or index >= settlement_keys.size():
		return ""
	return settlement_keys[index]


func get_households_for_key(key: String) -> int:
	var index: int = settlement_keys.find(key)
	if index < 0 or index >= households.size():
		return 0
	return maxi(0, households[index])


## 新游戏：按稳定 key 写入特产与可用户数。
func apply_to_settlement(settlement: SettlementData, key: String) -> void:
	if settlement == null or key.is_empty():
		return
	var item_id: String = get_specialty_for_key(key)
	if not item_id.is_empty() and not settlement.village_specialty_item_ids.has(item_id):
		settlement.village_specialty_item_ids.append(item_id)
	var configured_households: int = get_households_for_key(key)
	if configured_households > 0:
		settlement.households = configured_households


## 旧存档：缺少特产或 map_key 时按稳定 key / 名称回退。
## 已存在的特产列表视为权威，不覆盖；只补缺失字段。
func apply_defaults(settlement: SettlementData) -> void:
	if settlement == null:
		return
	var key: String = settlement.map_key
	if key.is_empty():
		key = get_key_for_name(settlement.display_name)
	if not key.is_empty() and settlement.map_key.is_empty():
		settlement.map_key = key
	if settlement.village_specialty_item_ids.is_empty() and not key.is_empty():
		var item_id: String = get_specialty_for_key(key)
		if not item_id.is_empty():
			settlement.village_specialty_item_ids.append(item_id)
	var configured_households: int = get_households_for_key(key)
	if settlement.households <= 0 and configured_households > 0:
		settlement.households = configured_households
