class_name EquipmentConfig
extends Resource
## 装备静态配置（Data/Equipment/*.tres）。

enum Slot {
	WEAPON,
	OFFHAND,
	HEAD,
	BODY,
	MOUNT,
}

@export var equipment_id: String = ""
@export var display_name: String = ""
@export var slot: Slot = Slot.WEAPON

@export_category("Stat Bonuses")
@export var attack_bonus: int = 0
@export var max_hp_bonus: int = 0
@export var move_speed_bonus: float = 0.0
@export var attack_range_bonus: float = 0.0

@export_category("Visual")
## 对应 UnitVisual 中的部件名，例如 "RightHandWeapon"。
@export var visual_part: String = ""
