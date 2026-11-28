class_name ItemInstanceData
extends RefCounted
## 非堆叠普通商品的独立实例（当前用于猪）。
##
## 与 MountInstanceData 分离：马匹的外观与属性来自 MOUNT 装备配置，
## 猪等普通商品只需要“这一件个体”的身份，不保存复杂属性。
## 哪些 item_id 使用实例由 ItemConfig.is_stackable = false 决定，
## 通过 register_instance_item() 注册，背包与市场共用同一份注册表。

static var _instance_item_ids: Dictionary = {}
static var _serial: int = 0

var instance_id: String = ""
var item_id: String = ""


static func register_instance_item(item_id: String) -> void:
	var normalized: String = item_id.strip_edges()
	if not normalized.is_empty():
		_instance_item_ids[normalized] = true


static func is_instance_item(item_id: String) -> bool:
	var normalized: String = item_id.strip_edges()
	return not normalized.is_empty() and _instance_item_ids.has(normalized)


static func create_random(item_id: String) -> ItemInstanceData:
	var instance := ItemInstanceData.new()
	instance.item_id = item_id.strip_edges()
	instance.instance_id = _next_random_id()
	return instance


## 旧存档数量迁移使用确定性 ID，保证反复读档不会生成不同实例。
static func create_deterministic(
	item_id: String, seed_text: String
) -> ItemInstanceData:
	var instance := ItemInstanceData.new()
	instance.item_id = item_id.strip_edges()
	var seed_value: int = hash(seed_text) & 0x7fffffff
	instance.instance_id = "item_%d" % seed_value
	return instance


static func _next_random_id() -> String:
	_serial += 1
	return "item_%d_%d_%d" % [
		Time.get_ticks_usec(), _serial, randi_range(0, 999999)
	]


func sanitize() -> void:
	item_id = item_id.strip_edges()
	if instance_id.strip_edges().is_empty():
		instance_id = _next_random_id()
	register_instance_item(item_id)


func to_dict() -> Dictionary:
	return {
		"instance_id": instance_id,
		"item_id": item_id,
	}


static func from_dict(data: Dictionary) -> ItemInstanceData:
	var instance := ItemInstanceData.new()
	instance.instance_id = str(data.get("instance_id", ""))
	instance.item_id = str(data.get("item_id", ""))
	instance.sanitize()
	return instance
