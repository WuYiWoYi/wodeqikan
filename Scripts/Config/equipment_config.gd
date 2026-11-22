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

## 武器攻击方式。近战沿用现有定向矩形；远程锁定目标坐标并生成箭矢。
## 是否能够远程攻击由武器配置决定，不通过兵种名称或 unit_class 判断。
enum AttackType {
	MELEE,
	RANGED,
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
## 武器攻击方式；非 WEAPON 槽忽略。
@export var attack_type: AttackType = AttackType.MELEE
## >0 时覆盖 UnitConfig.attack_interval；弓统一为 3 秒攻击冷却。
@export var attack_interval_override: float = 0.0

@export_category("Projectile")
## 远程武器生成的箭矢贴图；空字符串表示使用代码绘制的最小回退表现。
@export var projectile_texture_path: String = ""
## 箭矢地面飞行速度（像素/秒）。
@export var projectile_speed: float = 480.0
## 抛物线最大视觉高度（像素）；地面深度不受该值影响。
@export var projectile_arc_height: float = 70.0

@export_category("Visual")
## 对应 UnitVisual 中的部件名，例如 "RightHandWeapon"。
@export var visual_part: String = ""
## 可选的装备贴图路径。空字符串表示使用该槽位的默认表现（例如长矛）。
## 头盔/左手武器素材尚未提供时可以保持为空，接口与层级仍然有效。
@export var visual_texture_path: String = ""
## 可选层级覆盖；0 表示使用槽位默认层级。
## 右手武器默认 RIGHT_HAND_WEAPON、左手 LEFT_HAND_WEAPON、头盔 HELMET。
@export var visual_layer: int = 0
## 可选素材锚点（素材左上角像素坐标）；(-1,-1) 表示使用部件默认锚点。
@export var visual_anchor: Vector2 = Vector2(-1.0, -1.0)
## 预留：未来可用于职业装备限制；当前不做校验。
@export var allowed_unit_config_ids: Array[String] = []


## 是否为远程武器。调用方应通过本方法判断攻击方式，而不是检查兵种名称。
func is_ranged_weapon() -> bool:
	return slot == Slot.WEAPON and attack_type == AttackType.RANGED


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
	# MOUNT 装备自动登记为“不可堆叠的马匹物品”，供背包与市场识别。
	if slot == Slot.MOUNT:
		MountInstanceData.register_mount_item(equipment_id.strip_edges())
	if slot == Slot.WEAPON and attack_type == AttackType.RANGED:
		if projectile_speed <= 0.0:
			push_error("远程武器 projectile_speed 必须大于 0: %s" % equipment_id)
			return false
		if projectile_arc_height < 0.0:
			push_error("远程武器 projectile_arc_height 不能为负数: %s" % equipment_id)
			return false
		if attack_interval_override <= 0.0:
			push_error("远程武器必须配置攻击间隔覆盖值: %s" % equipment_id)
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
