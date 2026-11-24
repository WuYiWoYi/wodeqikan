class_name StatCalculator
extends RefCounted
## 单位最终属性计算：兵种基础属性 + 等级成长 + 装备加成 +
## 由武器派生的攻击方式/弹道参数与骑乘身高。
##
## 不把最终属性写回兵种配置；UnitData 只缓存计算结果。
## 本类是运行时属性的唯一计算入口：UnitManager 创建单位与重算时必须调用 apply_to_unit()。
## 本类不访问场景节点、UI 或资源加载器；装备配置由 UnitManager 传入。

const STAT_KEYS: Array[String] = [
	"max_hp",
	"attack",
	"attack_interval",
	"move_speed",
	"attack_range",
	"attack_type",
	"body_height",
	"projectile_texture_path",
	"projectile_speed",
	"projectile_arc_height",
]

## 骑乘移动攻击加成集中配置。
## 使用 UnitData 的最终移动速度（已包含坐骑与装备加成），超出阈值的速度按比例
## 转为攻击加成，并设置上限，避免异常速度导致攻击力无限增长。
## 停止移动时由调用方传入 is_moving = false，加成立即为 0。
const MOUNT_CHARGE_SPEED_THRESHOLD: float = 60.0
const MOUNT_CHARGE_ATTACK_PER_SPEED: float = 0.1
const MOUNT_CHARGE_MAX_BONUS: int = 5

## 骑乘时身体有效高度追加值；用于远程箭矢的高度命中判定。
const MOUNTED_BODY_HEIGHT_BONUS: float = 18.0
## 未配置远程武器时的发射物默认参数。
const DEFAULT_PROJECTILE_SPEED: float = 480.0
const DEFAULT_PROJECTILE_ARC_HEIGHT: float = 70.0


## 返回最终属性字典；缺少兵种配置时返回空字典。
## equipment_configs 为 { equipment_id: EquipmentConfig }；缺失或槽位不匹配的装备
## 会被忽略（由 UnitManager 在重算前负责上报与清理无效引用）。
static func compute_final_stats(
	unit: UnitData, config: UnitConfig, equipment_configs: Dictionary = {}
) -> Dictionary:
	if config == null:
		return {}

	# 等级成长只计算到 max_level，超过上限的旧存档等级不会继续放大属性。
	var level: int = 1
	if unit != null:
		level = clampi(unit.level, 1, maxi(config.max_level, 1))
	var levels_gained: int = level - 1

	var max_hp: int = config.base_max_hp + levels_gained * config.hp_per_level
	var attack: int = config.base_attack + levels_gained * config.attack_per_level
	var move_speed: float = config.move_speed + levels_gained * config.move_speed_per_level
	var attack_range: float = (
		config.attack_range + levels_gained * config.attack_range_per_level
	)
	var attack_interval: float = maxf(config.attack_interval, 0.0)
	var attack_type: int = EquipmentConfig.AttackType.MELEE
	var projectile_texture_path: String = ""
	var projectile_speed: float = DEFAULT_PROJECTILE_SPEED
	var projectile_arc_height: float = DEFAULT_PROJECTILE_ARC_HEIGHT
	var has_mount: bool = false
	var range_bonus_total: float = 0.0
	var weapon_range_override: float = -1.0

	if unit != null:
		for slot_key: Variant in unit.equipment:
			var equipment_id: String = str(unit.equipment[slot_key])
			var equipment := equipment_configs.get(equipment_id) as EquipmentConfig
			if equipment == null:
				continue
			if EquipmentConfig.slot_to_string(equipment.slot) != str(slot_key):
				continue
			max_hp += equipment.max_hp_bonus
			attack += equipment.attack_bonus
			move_speed += equipment.move_speed_bonus
			range_bonus_total += equipment.attack_range_bonus
			# 武器是攻击距离与攻击方式的唯一来源；>0 时覆盖 UnitConfig 基础距离。
			if equipment.slot == EquipmentConfig.Slot.WEAPON:
				if equipment.weapon_attack_range > 0.0:
					weapon_range_override = equipment.weapon_attack_range
				attack_type = int(equipment.attack_type)
				if equipment.attack_interval_override > 0.0:
					attack_interval = equipment.attack_interval_override
				projectile_texture_path = equipment.projectile_texture_path
				projectile_speed = maxf(1.0, equipment.projectile_speed)
				projectile_arc_height = maxf(0.0, equipment.projectile_arc_height)
			elif equipment.slot == EquipmentConfig.Slot.MOUNT:
				has_mount = true

	if weapon_range_override >= 0.0:
		attack_range = (
			weapon_range_override
			+ levels_gained * config.attack_range_per_level
		)
	attack_range += range_bonus_total

	var body_height: float = config.body_height + (
		MOUNTED_BODY_HEIGHT_BONUS if has_mount else 0.0
	)
	var final_stats := {
		"max_hp": maxi(1, max_hp),
		"attack": maxi(0, attack),
		"attack_interval": attack_interval,
		"move_speed": maxf(move_speed, 0.0),
		"attack_range": maxf(attack_range, 0.0),
		"attack_type": attack_type,
		"body_height": maxf(1.0, body_height),
		"projectile_texture_path": projectile_texture_path,
		"projectile_speed": projectile_speed,
		"projectile_arc_height": projectile_arc_height,
	}
	# 战斗经验加成与兵种基础属性、等级成长、装备加成保持独立；
	# 加成表由 CombatExperience 统一维护，当前按等级追加最大 HP。
	return CombatExperience.apply_stat_bonuses(final_stats, level)


## 骑乘且正在移动时的额外攻击力。
## 步兵、未装备 MOUNT 的单位、停止移动的单位一律返回 0。
static func compute_move_attack_bonus(unit: UnitData, is_moving: bool) -> int:
	if unit == null or not is_moving or not unit.is_mounted:
		return 0
	if not unit.equipment.has(EquipmentConfig.SLOT_NAMES[EquipmentConfig.Slot.MOUNT]):
		return 0
	var speed_over_threshold: float = maxf(
		0.0, unit.move_speed - MOUNT_CHARGE_SPEED_THRESHOLD
	)
	return clampi(
		int(floor(speed_over_threshold * MOUNT_CHARGE_ATTACK_PER_SPEED)),
		0,
		MOUNT_CHARGE_MAX_BONUS
	)


## 单次攻击的最终攻击力：基础攻击 + 骑乘移动加成。
static func compute_effective_attack(unit: UnitData, is_moving: bool) -> int:
	if unit == null:
		return 0
	return maxi(0, unit.attack + compute_move_attack_bonus(unit, is_moving))


## 计算并写入 UnitData 的派生属性缓存，返回是否成功。
## current_hp 只做上限 clamp，不在此重置；出生满血由 UnitManager 负责。
static func apply_to_unit(
	unit: UnitData, config: UnitConfig, equipment_configs: Dictionary = {}
) -> bool:
	if unit == null or config == null:
		return false
	var stats := compute_final_stats(unit, config, equipment_configs)
	if stats.is_empty():
		return false

	unit.max_hp = int(stats["max_hp"])
	unit.attack = int(stats["attack"])
	unit.attack_interval = float(stats["attack_interval"])
	unit.move_speed = float(stats["move_speed"])
	unit.attack_range = float(stats["attack_range"])
	unit.attack_type = int(stats["attack_type"])
	unit.body_height = float(stats["body_height"])
	unit.projectile_texture_path = str(stats["projectile_texture_path"])
	unit.projectile_speed = float(stats["projectile_speed"])
	unit.projectile_arc_height = float(stats["projectile_arc_height"])
	unit.clamp_hp()
	return true
