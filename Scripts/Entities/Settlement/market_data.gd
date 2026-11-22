class_name MarketData
extends RefCounted
## 单个村庄/城镇市场的运行时库存。
##
## 每个地点拥有独立 MarketData，不与其他地点或背包共享。
## - stock: { item_id: 数量 }，只保存可堆叠商品。
## - mount_instances: 市场中待售的每一匹马，拥有独立外观与实例 ID。

var settlement_id: String = ""
var stock: Dictionary = {}
var mount_instances: Array[MountInstanceData] = []
## 已按商品配置初始化过的 item_id。用于区分“商品卖光”和“旧存档缺少该商品”，
## 避免读档时把卖光的库存重新补满。
var initialized_items: Dictionary = {}


func get_stock(item_id: String) -> int:
	if item_id.is_empty():
		return 0
	if MountInstanceData.is_mount_item(item_id):
		return get_mount_count(item_id)
	return maxi(0, int(stock.get(item_id, 0)))


func set_stock(item_id: String, count: int) -> void:
	if item_id.is_empty():
		return
	if MountInstanceData.is_mount_item(item_id):
		push_warning("马匹库存必须通过实例管理，不能直接设置数量: %s" % item_id)
		return
	stock[item_id] = maxi(0, count)


func add_stock(item_id: String, count: int) -> void:
	if item_id.is_empty() or count <= 0:
		return
	if MountInstanceData.is_mount_item(item_id):
		push_warning("马匹不能按数量加入市场库存: %s" % item_id)
		return
	stock[item_id] = get_stock(item_id) + count


## 库存不足时返回 false 且不修改库存。
func remove_stock(item_id: String, count: int) -> bool:
	if item_id.is_empty() or count <= 0:
		return false
	if MountInstanceData.is_mount_item(item_id):
		if get_mount_count(item_id) < count:
			return false
		for i: int in range(count):
			if take_mount_instance(item_id) == null:
				return false
		return true
	var current: int = get_stock(item_id)
	if current < count:
		return false
	stock[item_id] = current - count
	return true


# ---------------------------------------------------------------------------
# 马匹实例
# ---------------------------------------------------------------------------


func get_mount_count(item_id: String = "") -> int:
	if item_id.is_empty():
		return mount_instances.size()
	var count: int = 0
	for instance: MountInstanceData in mount_instances:
		if instance != null and instance.equipment_id == item_id:
			count += 1
	return count


func get_mount_instances(item_id: String = "") -> Array[MountInstanceData]:
	var result: Array[MountInstanceData] = []
	for instance: MountInstanceData in mount_instances:
		if instance != null and (item_id.is_empty() or instance.equipment_id == item_id):
			result.append(instance)
	return result


func get_mount_instance(instance_id: String) -> MountInstanceData:
	for instance: MountInstanceData in mount_instances:
		if instance != null and instance.instance_id == instance_id:
			return instance
	return null


func add_mount_instance(instance: MountInstanceData) -> bool:
	if instance == null or instance.instance_id.is_empty() \
			or instance.equipment_id.is_empty():
		return false
	if get_mount_instance(instance.instance_id) != null:
		push_error("市场马匹实例 ID 重复: %s" % instance.instance_id)
		return false
	mount_instances.append(instance)
	return true


func remove_mount_instance(instance_id: String) -> MountInstanceData:
	for index: int in range(mount_instances.size()):
		var instance := mount_instances[index]
		if instance != null and instance.instance_id == instance_id:
			mount_instances.remove_at(index)
			return instance
	return null


func take_mount_instance(item_id: String) -> MountInstanceData:
	for index: int in range(mount_instances.size()):
		var instance := mount_instances[index]
		if instance != null and instance.equipment_id == item_id:
			mount_instances.remove_at(index)
			return instance
	return null


func restore_mount_instances(instances: Array[MountInstanceData]) -> void:
	mount_instances.clear()
	for instance: MountInstanceData in instances:
		if instance != null:
			mount_instances.append(instance)


func is_initialized(item_id: String) -> bool:
	return initialized_items.has(item_id)


func mark_initialized(item_id: String) -> void:
	if not item_id.is_empty():
		initialized_items[item_id] = true


# ---------------------------------------------------------------------------
# 序列化
# ---------------------------------------------------------------------------


func to_dict() -> Dictionary:
	var instances: Array[Dictionary] = []
	for instance: MountInstanceData in mount_instances:
		if instance != null:
			instances.append(instance.to_dict())
	return {
		"settlement_id": settlement_id,
		"stock": stock.duplicate(true),
		"mount_instances": instances,
		"initialized_items": initialized_items.duplicate(true),
	}


static func from_dict(data: Dictionary) -> MarketData:
	var market := MarketData.new()
	market.settlement_id = str(data.get("settlement_id", ""))
	var stock_value: Variant = data.get("stock", {})
	if stock_value is Dictionary:
		var stock_data: Dictionary = stock_value
		for key: Variant in stock_data:
			var item_id: String = str(key)
			var count: int = int(stock_data[key])
			if item_id.is_empty() or count < 0:
				continue
			market.stock[item_id] = count

	var instance_value: Variant = data.get("mount_instances", [])
	if instance_value is Array:
		for value: Variant in instance_value:
			if not value is Dictionary:
				continue
			var instance := MountInstanceData.from_dict(value)
			if instance.instance_id.is_empty() or instance.equipment_id.is_empty():
				continue
			if market.get_mount_instance(instance.instance_id) != null:
				continue
			market.mount_instances.append(instance)

	var initialized_value: Variant = data.get("initialized_items", {})
	if initialized_value is Dictionary:
		for key: Variant in (initialized_value as Dictionary).keys():
			market.initialized_items[str(key)] = true

	# 旧存档没有初始化标记：已有库存键或马匹实例的商品视为已初始化。
	for item_id_value: Variant in market.stock.keys():
		market.initialized_items[str(item_id_value)] = true
	for instance: MountInstanceData in market.mount_instances:
		if instance != null:
			market.initialized_items[instance.equipment_id] = true

	# 旧存档可能把马匹数量存在 stock 中：转成确定性实例，保证只迁移一次。
	var legacy_mount_ids: Array[String] = []
	for item_id_value: Variant in market.stock.keys():
		var item_id: String = str(item_id_value)
		if MountInstanceData.is_mount_item(item_id):
			legacy_mount_ids.append(item_id)
	for item_id: String in legacy_mount_ids:
		var count: int = maxi(0, int(market.stock.get(item_id, 0)))
		market.stock.erase(item_id)
		for index: int in range(count):
			market.mount_instances.append(MountInstanceData.create_deterministic(
				item_id, "market|%s|%s|%d" % [market.settlement_id, item_id, index]
			))
	return market
