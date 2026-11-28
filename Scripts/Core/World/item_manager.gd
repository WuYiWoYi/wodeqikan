class_name ItemManager
extends RefCounted
## 静态物品配置仓储（Data/Items）。
##
## 只注册与查询 ItemConfig，不保存玩家持有数量；数量由 PlayerProfile 背包维护。
## 装备（装备槽位）仍由 UnitManager 的 EquipmentConfig 注册表管理。

var _items: Dictionary = {}


## 注册物品模板。重复 item_id 拒绝覆盖并返回 false。
func register_item_config(config: ItemConfig) -> bool:
	if config == null or not config.validate():
		return false
	if _items.has(config.item_id):
		push_error("ItemConfig 重复注册，拒绝覆盖: %s" % config.item_id)
		return false
	_items[config.item_id] = config
	# 非堆叠普通商品（例如猪）每件保存独立实例；马匹仍由 MOUNT 装备体系管理。
	if not config.is_stackable and not MountInstanceData.is_mount_item(config.item_id):
		ItemInstanceData.register_instance_item(config.item_id)
	return true


func get_item_config(item_id: String) -> ItemConfig:
	return _items.get(item_id) as ItemConfig


func has_item_config(item_id: String) -> bool:
	return _items.has(item_id)


func get_all_item_configs() -> Array[ItemConfig]:
	var result: Array[ItemConfig] = []
	for value: Variant in _items.values():
		var config := value as ItemConfig
		if config != null:
			result.append(config)
	return result


## 物品显示名称；配置缺失时回退为 ID，避免 UI 崩溃。
func get_display_name(item_id: String) -> String:
	var config := get_item_config(item_id)
	if config != null:
		return config.display_name
	return item_id if not item_id.is_empty() else "未知物品"
