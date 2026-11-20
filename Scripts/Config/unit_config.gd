class_name UnitConfig
extends Resource
## 兵种静态配置（Data/Units/*.tres）。
##
## 只定义“兵种模板”，不保存单个士兵的运行时状态。
## 运行时 UnitData 通过 config_id 引用本配置。

enum UnitClass {
	INFANTRY,
	RANGED,
	CAVALRY,
}

@export_category("Identity")
@export var config_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var unit_class: UnitClass = UnitClass.INFANTRY
@export var is_mounted: bool = false

@export_category("Base Stats")
@export var base_level: int = 1
@export var base_max_hp: int = 30
@export var base_attack: int = 5
@export var attack_interval: float = 1.0
@export var attack_range: float = 20.0
@export var move_speed: float = 60.0

@export_category("Visual / Economy")
@export var visual_scene_path: String = ""
@export var recruit_cost: int = 0
@export var default_equipment: Dictionary = {}


func validate() -> bool:
	if config_id.strip_edges().is_empty():
		push_error("UnitConfig 缺少 config_id: %s" % resource_path)
		return false
	if display_name.strip_edges().is_empty():
		push_error("UnitConfig 缺少 display_name: %s" % resource_path)
		return false
	if base_max_hp <= 0 or base_attack <= 0:
		push_error("UnitConfig 基础属性非法: %s" % config_id)
		return false
	return true
