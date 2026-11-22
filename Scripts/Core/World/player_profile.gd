class_name PlayerProfile
extends RefCounted
## 玩家会话级数据：金币与物品栏。
##
## 物品存储委托给 InventoryData：普通物品按数量堆叠，马匹按独立实例保存。
## inventory / item_counts 作为兼容访问入口保留，旧调用方无需改动。

var gold: int = 0
var _data: InventoryData = InventoryData.new()

## 出现过的物品 ID 列表（兼容旧存档与 UI 枚举）。
var inventory: Array[String]:
	get:
		return _data.inventory
	set(value):
		_data.inventory = value

## { item_id: 数量 }，只包含可堆叠物品；马匹不再写入这里。
var item_counts: Dictionary:
	get:
		return _data.stackable_counts
	set(value):
		_data.stackable_counts = value


func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold = maxi(0, gold + amount)


## 查询金币是否足够。
func can_afford(amount: int) -> bool:
	return amount >= 0 and gold >= amount


## 扣除金币；数量非法或余额不足时返回 false，不修改金币。
func spend_gold(amount: int) -> bool:
	if amount <= 0 or gold < amount:
		return false
	gold -= amount
	return true


## 单件物品数量；马匹返回独立实例数量。
func get_item_count(equipment_id: String) -> int:
	return _data.get_item_count(equipment_id)


func has_item(equipment_id: String) -> bool:
	return get_item_count(equipment_id) > 0


## 增加物品并叠加数量；马匹会生成独立实例。
func add_item(equipment_id: String, count: int = 1) -> bool:
	return _data.add_item(equipment_id, count)


## 消耗指定数量；数量不足时不修改任何数据。
func remove_item(equipment_id: String, count: int = 1) -> bool:
	return _data.remove_item(equipment_id, count)


# ---------------------------------------------------------------------------
# 马匹实例
# ---------------------------------------------------------------------------


func add_mount_instance(instance: MountInstanceData) -> bool:
	return _data.add_mount_instance(instance)


func remove_mount_instance(instance_id: String) -> MountInstanceData:
	return _data.remove_mount_instance(instance_id)


func take_mount_instance(item_id: String) -> MountInstanceData:
	return _data.take_mount_instance(item_id)


func get_mount_instance(instance_id: String) -> MountInstanceData:
	return _data.get_mount_instance(instance_id)


func has_mount_instance(instance_id: String) -> bool:
	return _data.has_mount_instance(instance_id)


func get_mount_instances(item_id: String = "") -> Array[MountInstanceData]:
	return _data.get_mount_instances(item_id)


func get_all_mount_instances() -> Array[MountInstanceData]:
	return _data.get_all_mount_instances()


func get_mount_count(item_id: String = "") -> int:
	return _data.get_mount_count(item_id)


func restore_mount_instances(instances: Array[MountInstanceData]) -> void:
	_data.restore_mount_instances(instances)


## 交易回滚专用：整体恢复背包，不生成新实例。
func restore_inventory_state(
	counts: Dictionary,
	inventory_list: Array,
	instances: Array
) -> void:
	_data.restore_state(inventory_list, counts, instances)


func migrate_legacy_mount_counts() -> void:
	_data.migrate_legacy_mount_counts()


## 读档专用：原地替换内容，保持外部持有的 PlayerProfile 引用不变。
func restore_from(other: PlayerProfile) -> void:
	if other == null:
		return
	gold = maxi(0, other.gold)
	_data = other._data


# ---------------------------------------------------------------------------
# 序列化
# ---------------------------------------------------------------------------


func to_dict() -> Dictionary:
	var payload: Dictionary = {
		"gold": gold,
		"inventory": inventory.duplicate(),
		"inventory_counts": item_counts.duplicate(true),
	}
	var instances: Array[Dictionary] = []
	for instance: MountInstanceData in _data.mount_instances:
		if instance != null:
			instances.append(instance.to_dict())
	payload["mount_instances"] = instances
	return payload


static func from_dict(data: Dictionary) -> PlayerProfile:
	var profile := PlayerProfile.new()
	profile.gold = maxi(0, int(data.get("gold", 0)))
	profile._data = InventoryData.from_dict(data)
	profile._data.migrate_legacy_mount_counts()
	return profile
