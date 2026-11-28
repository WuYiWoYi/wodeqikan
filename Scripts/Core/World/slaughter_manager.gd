class_name SlaughterManager
extends RefCounted
## 牲畜宰杀的唯一业务入口。
##
## 只处理猪与马：移除玩家背包中的具体实例，并增加 20 单位肉。
## UI 只发起意图；实例移除、肉库存增加与失败回滚都在这里完成。
## 不新增持久化字段：状态完全由背包/市场数据推导。

const PIG_ID: String = "pig"
const MEAT_ID: String = "meat"
const MEAT_PER_ANIMAL: int = 20

var last_error: String = ""

var _item_manager: ItemManager = null


func setup(item_manager: ItemManager) -> void:
	_item_manager = item_manager


func can_slaughter(item_id: String) -> bool:
	return _is_livestock(item_id)


## 宰杀背包中的一只牲畜；成功返回 {"success", "item_id", "meat_added"}。
func slaughter(holder: Variant, item_id: String) -> Dictionary:
	last_error = ""
	if holder == null:
		return _failure("缺少背包数据")
	if not _is_livestock(item_id):
		return _failure("该物品不能宰杀")
	var removed: bool = false
	if MountInstanceData.is_mount_item(item_id):
		var mount: MountInstanceData = holder.take_mount_instance(item_id)
		removed = mount != null
	else:
		var instance: ItemInstanceData = holder.take_item_instance(item_id)
		removed = instance != null
	if not removed:
		return _failure("背包中没有可宰杀的牲畜")
	if not holder.add_item(MEAT_ID, MEAT_PER_ANIMAL):
		# 极端情况下恢复被移除的个体，避免牲畜凭空消失。
		_restore_livestock(holder, item_id)
		return _failure("无法获得肉，宰杀已取消")
	return {
		"success": true,
		"error": "",
		"item_id": item_id,
		"meat_added": MEAT_PER_ANIMAL,
	}


func _is_livestock(item_id: String) -> bool:
	if MountInstanceData.is_mount_item(item_id):
		return true
	if item_id != PIG_ID:
		return false
	if _item_manager != null:
		var config := _item_manager.get_item_config(item_id)
		return config != null and not config.is_stackable
	return ItemInstanceData.is_instance_item(item_id)


func _restore_livestock(holder: Variant, item_id: String) -> void:
	if MountInstanceData.is_mount_item(item_id):
		holder.add_mount_instance(
			MountInstanceData.create_deterministic(
				item_id, "slaughter-rollback|%s|%d" % [item_id, Time.get_ticks_usec()]
			)
		)
	else:
		holder.add_item_instance(
			ItemInstanceData.create_deterministic(
				item_id, "slaughter-rollback|%s|%d" % [item_id, Time.get_ticks_usec()]
			)
		)


func _failure(message: String) -> Dictionary:
	last_error = message
	return {
		"success": false,
		"error": message,
		"item_id": "",
		"meat_added": 0,
	}
