class_name EquipmentConfig
extends Resource
## 装备静态配置（Data/Equipment/*.tres）。
##
## 只读模板；不保存“某个士兵是否装备了它”，实例化/耐久/品质均未实现。

enum Slot {
	WEAPON,
	OFFHAND,
	HEAD,
	BODY,
	MOUNT,
}

## 槽位字符串是 UnitData.equipment 的唯一键格式，与 Slot 顺序一一对应。
const SLOT_NAMES: Array[String] = ["WEAPON", "OFFHAND", "HEAD", "BODY", "MOUNT"]
const SLOT_DISPLAY_NAMES: Array[String] = ["武器", "副手", "头盔", "盔甲", "坐骑"]

@export var equipment_id: String = ""
@export var display_name: String = ""
@export var slot: Slot = Slot.WEAPON

@export_category("Stat Bonuses")
@export var attack_bonus: int = 0
@export var max_hp_bonus: int = 0
@export var move_speed_bonus: float = 0.0
@export var attack_range_bonus: float = 0.0
## WEAPON 槽的基础攻击距离；>0 时覆盖 UnitConfig 的 attack_range。
## 0 表示不覆盖（例如非武器槽或旧配置）。最终战斗矩形还会叠加
## CombatRules 的身体尺寸与武器向前加成。
@export var weapon_attack_range: float = 0.0

@export_category("Visual")
## 对应 UnitVisual 中的部件名，例如 "RightHandWeapon"。
@export var visual_part: String = ""
## 预留：未来可用于职业装备限制；当前不做校验。
@export var allowed_unit_config_ids: Array[String] = []


func validate() -> bool:
	if equipment_id.strip_edges().is_empty():
		push_error("EquipmentConfig 缺少 equipment_id: %s" % resource_path)
		return false
	if display_name.strip_edges().is_empty():
		push_error("EquipmentConfig 缺少 display_name: %s" % equipment_id)
		return false
	if slot_to_string(slot).is_empty():
		push_error("EquipmentConfig 槽位非法: %s" % equipment_id)
		return false
	return true


## UnitData.equipment 使用的槽位键，例如 "WEAPON"。
func slot_name() -> String:
	return slot_to_string(slot)


func slot_display_name() -> String:
	var index: int = int(slot)
	if index < 0 or index >= SLOT_DISPLAY_NAMES.size():
		return "未知"
	return SLOT_DISPLAY_NAMES[index]


## 返回属性加成的可读文本，例如 "攻击 +2  生命 +5"；无加成返回空字符串。
func bonus_text() -> String:
	var parts: Array[String] = []
	if attack_bonus != 0:
		parts.append("攻击 %+d" % attack_bonus)
	if max_hp_bonus != 0:
		parts.append("生命 %+d" % max_hp_bonus)
	if not is_zero_approx(move_speed_bonus):
		parts.append("移速 %+d" % int(round(move_speed_bonus)))
	if not is_zero_approx(attack_range_bonus):
		parts.append("射程 %+d" % int(round(attack_range_bonus)))
	if weapon_attack_range > 0.0:
		parts.append("攻击距离 %d" % int(round(weapon_attack_range)))
	return "  ".join(parts)


static func slot_to_string(value: Slot) -> String:
	var index: int = int(value)
	if index < 0 or index >= SLOT_NAMES.size():
		return ""
	return SLOT_NAMES[index]


## 合法槽位字符串返回对应的 Slot 整数值；非法字符串返回 -1。
## 返回值用 int 是为了让调用方无需处理 enum 转换失败。
static func slot_from_string(value: String) -> int:
	return SLOT_NAMES.find(value.strip_edges().to_upper())


static func slot_display_name_from_string(value: String) -> String:
	var index: int = slot_from_string(value)
	if index < 0 or index >= SLOT_DISPLAY_NAMES.size():
		return "未知"
	return SLOT_DISPLAY_NAMES[index]
