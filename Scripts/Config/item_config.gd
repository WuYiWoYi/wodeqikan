class_name ItemConfig
extends Resource
## 消耗品/杂项物品的静态配置（Data/Items/*.tres）。
##
## 与 EquipmentConfig 分离：物品只进入玩家背包并记录数量，不装备到士兵槽位。
## 马匹仍使用 EquipmentConfig 的 MOUNT 槽位；晋升凭证等属于本类。

enum ItemType {
	CONSUMABLE,
	MISC,
}

@export var item_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var item_type: ItemType = ItemType.CONSUMABLE


func validate() -> bool:
	if item_id.strip_edges().is_empty():
		push_error("ItemConfig 缺少 item_id: %s" % resource_path)
		return false
	if display_name.strip_edges().is_empty():
		push_error("ItemConfig 缺少 display_name: %s" % item_id)
		return false
	return true


func type_display_name() -> String:
	match item_type:
		ItemType.CONSUMABLE:
			return "消耗品"
		_:
			return "杂物"
