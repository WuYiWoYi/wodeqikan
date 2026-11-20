class_name StatCalculator
extends RefCounted
## 单位最终属性计算：等级基础属性 + 装备属性 + 其他加成。
##
## 不把最终属性写回兵种配置；UnitData 只缓存计算结果。
## 本类是运行时属性的唯一计算入口：UnitManager 创建单位时必须调用 apply_to_unit()。
## 当前为基础版，只复制 UnitConfig 的静态属性，等级成长与装备加成留待后续实现。

const STAT_KEYS: Array[String] = [
	"max_hp",
	"attack",
	"attack_interval",
	"move_speed",
	"attack_range",
]


## 返回最终属性字典；无效输入返回空字典。
## 目前不依赖 unit 的等级与装备，保留参数用于后续成长公式。
## TODO(阶段3)：接入等级成长、装备加成与其他修正（KI120）。
static func compute_final_stats(_unit: UnitData, config: UnitConfig) -> Dictionary:
	if config == null:
		return {}
	return {
		"max_hp": maxi(config.base_max_hp, 0),
		"attack": maxi(config.base_attack, 0),
		"attack_interval": maxf(config.attack_interval, 0.0),
		"move_speed": maxf(config.move_speed, 0.0),
		"attack_range": maxf(config.attack_range, 0.0),
	}


## 计算并写入 UnitData 的派生属性缓存，返回是否成功。
## current_hp 只做上限 clamp，不在此重置；出生满血由 UnitManager 负责。
static func apply_to_unit(unit: UnitData, config: UnitConfig) -> bool:
	if unit == null or config == null:
		return false
	var stats := compute_final_stats(unit, config)
	if stats.is_empty():
		return false

	unit.max_hp = int(stats["max_hp"])
	unit.attack = int(stats["attack"])
	unit.attack_interval = float(stats["attack_interval"])
	unit.move_speed = float(stats["move_speed"])
	unit.attack_range = float(stats["attack_range"])
	unit.clamp_hp()
	return true
