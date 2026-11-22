class_name MountInstanceData
extends RefCounted
## 单匹马的独立实例数据（阶段 12）。
##
## 马匹不能按 item_counts 堆叠；每匹马拥有唯一 instance_id、毛色与马鞍。
## 基础属性仍来自 EquipmentConfig（equipment_id 指向 MOUNT 槽配置），
## 本类只保存“这一匹马”的外观身份，便于交易、装备与存档保持一致。

const COAT_BLACK: String = "black"
const COAT_WHITE: String = "white"
const COAT_BROWN: String = "brown"
const COAT_IDS: Array[String] = [COAT_BLACK, COAT_WHITE, COAT_BROWN]
const DEFAULT_COAT: String = COAT_BROWN

const SADDLE_01: String = "saddle_01"
const SADDLE_IDS: Array[String] = [
	"saddle_01", "saddle_02", "saddle_03", "saddle_04",
	"saddle_05", "saddle_06", "saddle_07", "saddle_08",
]
const DEFAULT_SADDLE: String = SADDLE_01

const COAT_DISPLAY_NAMES: Dictionary = {
	COAT_BLACK: "黑马",
	COAT_WHITE: "白马",
	COAT_BROWN: "棕马",
}

## 已注册为 MOUNT 槽的装备 ID。由 EquipmentConfig 校验 / UnitManager 注册时写入，
## 让背包与管理器无需持有另一份“哪些物品是马匹”的配置。
static var _mount_item_ids: Dictionary = {}
static var _serial: int = 0

var instance_id: String = ""
var equipment_id: String = ""
var coat_style_id: String = DEFAULT_COAT
var saddle_style_id: String = DEFAULT_SADDLE
## 可选个体名；当前只用于显示，不影响属性。
var display_name: String = ""


static func register_mount_item(item_id: String) -> void:
	var normalized: String = item_id.strip_edges()
	if not normalized.is_empty():
		_mount_item_ids[normalized] = true


static func is_mount_item(item_id: String) -> bool:
	return _mount_item_ids.has(item_id.strip_edges())


static func get_registered_mount_ids() -> Array[String]:
	var result: Array[String] = []
	for item_id: Variant in _mount_item_ids.keys():
		result.append(str(item_id))
	result.sort()
	return result


## 随机生成一匹马。只在创建实例时调用一次，之后外观随实例持久化。
static func create_random(equipment_id: String) -> MountInstanceData:
	var instance := MountInstanceData.new()
	instance.equipment_id = equipment_id.strip_edges()
	instance.instance_id = _next_random_id()
	instance.coat_style_id = COAT_IDS[randi_range(0, COAT_IDS.size() - 1)]
	instance.saddle_style_id = SADDLE_IDS[randi_range(0, SADDLE_IDS.size() - 1)]
	return instance


## 旧存档迁移使用的确定性实例：同一 seed 永远得到同一 ID 与外观，
## 保证反复读档不会让马匹数量或外观发生漂移。
static func create_deterministic(
	equipment_id: String, seed_text: String
) -> MountInstanceData:
	var instance := MountInstanceData.new()
	instance.equipment_id = equipment_id.strip_edges()
	# 不使用 absi()：hash 为 INT_MIN 时 absi 仍返回负数，会让取模索引非法。
	var seed_value: int = hash(seed_text) & 0x7fffffff
	instance.instance_id = "mount_%d" % seed_value
	instance.coat_style_id = COAT_IDS[seed_value % COAT_IDS.size()]
	instance.saddle_style_id = SADDLE_IDS[
		(seed_value / COAT_IDS.size()) % SADDLE_IDS.size()
	]
	return instance


static func _next_random_id() -> String:
	_serial += 1
	return "mount_%d_%d_%d" % [
		Time.get_ticks_usec(), _serial, randi_range(0, 999999)
	]


static func coat_display_name(coat_style_id: String) -> String:
	return str(COAT_DISPLAY_NAMES.get(coat_style_id, COAT_DISPLAY_NAMES[DEFAULT_COAT]))


static func saddle_display_name(saddle_style_id: String) -> String:
	var index: int = SADDLE_IDS.find(saddle_style_id)
	if index < 0:
		index = 0
	return "马鞍 %d" % (index + 1)


func sanitize() -> void:
	equipment_id = equipment_id.strip_edges()
	if instance_id.strip_edges().is_empty():
		instance_id = _next_random_id()
	if not COAT_IDS.has(coat_style_id):
		coat_style_id = DEFAULT_COAT
	if not SADDLE_IDS.has(saddle_style_id):
		saddle_style_id = DEFAULT_SADDLE


func appearance_text() -> String:
	return "%s · %s" % [
		coat_display_name(coat_style_id),
		saddle_display_name(saddle_style_id),
	]


func to_dict() -> Dictionary:
	return {
		"instance_id": instance_id,
		"equipment_id": equipment_id,
		"coat_style_id": coat_style_id,
		"saddle_style_id": saddle_style_id,
		"display_name": display_name,
	}


static func from_dict(data: Dictionary) -> MountInstanceData:
	var instance := MountInstanceData.new()
	instance.instance_id = str(data.get("instance_id", ""))
	instance.equipment_id = str(data.get("equipment_id", ""))
	instance.coat_style_id = str(data.get("coat_style_id", DEFAULT_COAT))
	instance.saddle_style_id = str(data.get("saddle_style_id", DEFAULT_SADDLE))
	instance.display_name = str(data.get("display_name", ""))
	instance.sanitize()
	return instance
