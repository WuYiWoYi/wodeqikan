class_name InventoryData
extends RefCounted
## 通用物品存储：普通可堆叠物品 + 独立马匹实例。
##
## 玩家 PlayerProfile 与 NPC PartyData 共用本类，避免出现两套背包规则。
## - stackable_counts: { item_id: 数量 }，面包、草料、晋升凭证等。
## - mount_instances: Array[MountInstanceData]，每匹马单独保存。
## inventory 仅保留“出现过的物品 ID 列表”，用于兼容旧存档与 UI 快速枚举。

var inventory: Array[String] = []
var stackable_counts: Dictionary = {}
var mount_instances: Array[MountInstanceData] = []


# ---------------------------------------------------------------------------
# 查询
# ---------------------------------------------------------------------------


func get_item_count(item_id: String) -> int:
	var normalized: String = item_id.strip_edges()
	if normalized.is_empty():
		return 0
	if MountInstanceData.is_mount_item(normalized):
		_migrate_legacy_mount_counts()
		return get_mount_count(normalized)
	return maxi(0, int(stackable_counts.get(normalized, 0)))


func has_item(item_id: String) -> bool:
	return get_item_count(item_id) > 0


func get_mount_count(item_id: String = "") -> int:
	if item_id.is_empty():
		return mount_instances.size()
	var count: int = 0
	for instance: MountInstanceData in mount_instances:
		if instance != null and instance.equipment_id == item_id:
			count += 1
	return count


func get_all_mount_instances() -> Array[MountInstanceData]:
	return mount_instances.duplicate()


func get_mount_instances(item_id: String) -> Array[MountInstanceData]:
	var result: Array[MountInstanceData] = []
	for instance: MountInstanceData in mount_instances:
		if instance != null and (item_id.is_empty() or instance.equipment_id == item_id):
			result.append(instance)
	return result


func get_mount_instance(instance_id: String) -> MountInstanceData:
	if instance_id.is_empty():
		return null
	for instance: MountInstanceData in mount_instances:
		if instance != null and instance.instance_id == instance_id:
			return instance
	return null


func has_mount_instance(instance_id: String) -> bool:
	return get_mount_instance(instance_id) != null


# ---------------------------------------------------------------------------
# 增减
# ---------------------------------------------------------------------------


## 增加普通物品；马匹 ID 会转换为独立实例，绝不写入 stackable_counts。
func add_item(item_id: String, count: int = 1) -> bool:
	var normalized: String = item_id.strip_edges()
	if normalized.is_empty() or count <= 0:
		return false
	if MountInstanceData.is_mount_item(normalized):
		for i: int in range(count):
			if not add_mount_instance(MountInstanceData.create_random(normalized)):
				return false
		return true
	stackable_counts[normalized] = get_item_count(normalized) + count
	_sync_inventory()
	return true


## 消耗普通物品或马匹实例；数量不足时不修改任何数据。
func remove_item(item_id: String, count: int = 1) -> bool:
	var normalized: String = item_id.strip_edges()
	if normalized.is_empty() or count <= 0:
		return false
	if MountInstanceData.is_mount_item(normalized):
		_migrate_legacy_mount_counts()
		if get_mount_count(normalized) < count:
			return false
		for i: int in range(count):
			var instance := take_mount_instance(normalized)
			if instance == null:
				return false
		return true
	var current: int = get_item_count(normalized)
	if current < count:
		return false
	var remaining: int = current - count
	if remaining <= 0:
		stackable_counts.erase(normalized)
	else:
		stackable_counts[normalized] = remaining
	_sync_inventory()
	return true


func add_mount_instance(instance: MountInstanceData) -> bool:
	if instance == null:
		return false
	instance.sanitize()
	if instance.instance_id.is_empty() or instance.equipment_id.is_empty():
		return false
	if has_mount_instance(instance.instance_id):
		push_error("马匹实例 ID 重复，拒绝加入背包: %s" % instance.instance_id)
		return false
	# 马匹不能同时存在普通堆叠计数中。
	stackable_counts.erase(instance.equipment_id)
	mount_instances.append(instance)
	_sync_inventory()
	return true


func remove_mount_instance(instance_id: String) -> MountInstanceData:
	for index: int in range(mount_instances.size()):
		var instance := mount_instances[index]
		if instance != null and instance.instance_id == instance_id:
			mount_instances.remove_at(index)
			_sync_inventory()
			return instance
	return null


## 取出指定装备 ID 的第一匹马；用于旧接口按 equipment_id 装备/出售。
func take_mount_instance(item_id: String) -> MountInstanceData:
	for index: int in range(mount_instances.size()):
		var instance := mount_instances[index]
		if instance != null and instance.equipment_id == item_id:
			mount_instances.remove_at(index)
			_sync_inventory()
			return instance
	return null


## 读档回滚专用：整体替换实例列表。
func restore_mount_instances(instances: Array[MountInstanceData]) -> void:
	mount_instances.clear()
	for instance: MountInstanceData in instances:
		if instance != null:
			mount_instances.append(instance)
	_sync_inventory()


## 交易回滚专用：一次性恢复普通物品数量、物品 ID 列表与马匹实例。
## 不生成新实例、不触发旧存档迁移，保证回滚后与快照完全一致。
func restore_state(
	inventory_list: Array,
	counts: Dictionary,
	instances: Array
) -> void:
	inventory.clear()
	for value: Variant in inventory_list:
		var item_id: String = str(value)
		if not item_id.is_empty() and not inventory.has(item_id):
			inventory.append(item_id)
	stackable_counts.clear()
	for key: Variant in counts:
		var item_id: String = str(key)
		var count: int = int(counts[key])
		if item_id.is_empty() or count <= 0:
			continue
		stackable_counts[item_id] = count
	mount_instances.clear()
	for value: Variant in instances:
		var instance := value as MountInstanceData
		if instance != null:
			mount_instances.append(instance)
	_sync_inventory()


# ---------------------------------------------------------------------------
# 兼容与序列化
# ---------------------------------------------------------------------------


## 旧存档可能把马匹放在 stackable_counts / item_counts 中；
## 这里只转换一次，转换后数量与前后的实例总数保持一致。
func migrate_legacy_mount_counts() -> void:
	_migrate_legacy_mount_counts()


func _migrate_legacy_mount_counts() -> void:
	if stackable_counts.is_empty():
		return
	var legacy_ids: Array[String] = []
	for item_id_value: Variant in stackable_counts.keys():
		var item_id: String = str(item_id_value)
		if MountInstanceData.is_mount_item(item_id):
			legacy_ids.append(item_id)
	for item_id: String in legacy_ids:
		var count: int = maxi(0, int(stackable_counts.get(item_id, 0)))
		stackable_counts.erase(item_id)
		for index: int in range(count):
			add_mount_instance(MountInstanceData.create_deterministic(
				item_id, "legacy|%s|%d" % [item_id, index]
			))
	_sync_inventory()


## 保持 inventory 与两类存储一致：有数量/实例的 ID 出现一次，归零的移除。
func _sync_inventory() -> void:
	var present: Dictionary = {}
	for item_id_value: Variant in stackable_counts.keys():
		var item_id: String = str(item_id_value)
		if int(stackable_counts[item_id]) > 0:
			present[item_id] = true
	for instance: MountInstanceData in mount_instances:
		if instance != null and not instance.equipment_id.is_empty():
			present[instance.equipment_id] = true

	var next_inventory: Array[String] = []
	for item_id: String in inventory:
		if present.has(item_id) and not next_inventory.has(item_id):
			next_inventory.append(item_id)
	for item_id_value: Variant in present.keys():
		var item_id: String = str(item_id_value)
		if not next_inventory.has(item_id):
			next_inventory.append(item_id)
	inventory = next_inventory


func to_dict() -> Dictionary:
	var instances: Array[Dictionary] = []
	for instance: MountInstanceData in mount_instances:
		if instance != null:
			instances.append(instance.to_dict())
	return {
		"inventory": inventory.duplicate(),
		"stackable_counts": stackable_counts.duplicate(true),
		"mount_instances": instances,
	}


static func from_dict(data: Dictionary) -> InventoryData:
	var storage := InventoryData.new()

	var inventory_value: Variant = data.get("inventory", [])
	if inventory_value is Array:
		for value: Variant in inventory_value:
			var item_id: String = str(value)
			if not item_id.is_empty() and not storage.inventory.has(item_id):
				storage.inventory.append(item_id)

	# 新字段名优先；旧存档使用 inventory_counts。
	var counts_value: Variant = data.get("stackable_counts", data.get("inventory_counts", {}))
	if counts_value is Dictionary:
		var counts: Dictionary = counts_value
		for key: Variant in counts:
			var item_id: String = str(key)
			var count: int = maxi(0, int(counts[key]))
			if item_id.is_empty() or count <= 0:
				continue
			storage.stackable_counts[item_id] = count

	var instance_value: Variant = data.get("mount_instances", [])
	if instance_value is Array:
		for value: Variant in instance_value:
			if not value is Dictionary:
				continue
			var instance := MountInstanceData.from_dict(value)
			if instance.instance_id.is_empty() or instance.equipment_id.is_empty():
				continue
			if storage.has_mount_instance(instance.instance_id):
				continue
			storage.mount_instances.append(instance)

	# 旧存档只有 inventory：每个条目按 1 件处理。
	# 已有马匹实例的装备 ID 不能再补成堆叠数量，否则读档会凭空多出马匹。
	for item_id: String in storage.inventory:
		if storage.stackable_counts.has(item_id):
			continue
		if MountInstanceData.is_mount_item(item_id):
			if storage.get_mount_count(item_id) == 0:
				storage.stackable_counts[item_id] = 1
		else:
			storage.stackable_counts[item_id] = 1

	storage._sync_inventory()
	return storage
