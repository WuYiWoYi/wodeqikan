class_name PlayerProfile
extends RefCounted
## 玩家会话级数据：金币与物品栏。
##
## 存放在 WorldContext 中，随存档的 player 字典保存。
## inventory 保持“出现过的物品 ID 列表”以兼容旧存档；item_counts 记录数量。
## 旧存档缺少 item_counts 时，inventory 中每个物品按 1 件处理，不升级 Schema。

var gold: int = 0
## 当前存放装备/战利品 ID；后续装备 UI 可直接读取。
var inventory: Array[String] = []
## { equipment_id: int }，与 inventory 同步；数量为 0 的物品不会保留。
var item_counts: Dictionary = {}


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


## 单件物品数量；未记录数量的旧数据按 1 件处理。
func get_item_count(equipment_id: String) -> int:
	if equipment_id.is_empty():
		return 0
	if item_counts.has(equipment_id):
		return maxi(0, int(item_counts[equipment_id]))
	return 1 if inventory.has(equipment_id) else 0


func has_item(equipment_id: String) -> bool:
	return get_item_count(equipment_id) > 0


## 增加物品并叠加数量；新物品同时加入 inventory。
func add_item(equipment_id: String, count: int = 1) -> bool:
	if equipment_id.is_empty() or count <= 0:
		return false
	item_counts[equipment_id] = get_item_count(equipment_id) + count
	if not inventory.has(equipment_id):
		inventory.append(equipment_id)
	return true


## 消耗指定数量；数量不足时不修改任何数据。
func remove_item(equipment_id: String, count: int = 1) -> bool:
	if equipment_id.is_empty() or count <= 0:
		return false
	var current: int = get_item_count(equipment_id)
	if current < count:
		return false
	var remaining: int = current - count
	if remaining <= 0:
		item_counts.erase(equipment_id)
		inventory.erase(equipment_id)
	else:
		item_counts[equipment_id] = remaining
	return true


func to_dict() -> Dictionary:
	return {
		"gold": gold,
		"inventory": inventory.duplicate(),
		"inventory_counts": item_counts.duplicate(),
	}


static func from_dict(data: Dictionary) -> PlayerProfile:
	var profile := PlayerProfile.new()
	profile.gold = maxi(0, int(data.get("gold", 0)))

	var values: Variant = data.get("inventory", [])
	if values is Array:
		for value: Variant in values:
			var item_id: String = str(value)
			if not item_id.is_empty() and not profile.inventory.has(item_id):
				profile.inventory.append(item_id)

	var counts_value: Variant = data.get("inventory_counts", {})
	if counts_value is Dictionary:
		for key: Variant in counts_value:
			var item_id: String = str(key)
			var count: int = maxi(0, int(counts_value[key]))
			if item_id.is_empty() or count <= 0:
				continue
			profile.item_counts[item_id] = count
			if not profile.inventory.has(item_id):
				profile.inventory.append(item_id)

	# 旧存档只有 inventory：每个条目按 1 件处理。
	for item_id: String in profile.inventory:
		if not profile.item_counts.has(item_id):
			profile.item_counts[item_id] = 1

	# 清理数量为 0 或不在 inventory 中的计数，保持两个字段一致。
	for item_id: Variant in profile.item_counts.keys():
		var key: String = str(item_id)
		if int(profile.item_counts[item_id]) <= 0:
			profile.item_counts.erase(item_id)
		elif not profile.inventory.has(key):
			profile.inventory.append(key)

	return profile
