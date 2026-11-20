class_name StatCalculator
extends RefCounted
## 单位最终属性计算：等级基础属性 + 装备属性 + 其他加成。
##
## 不把最终属性写回兵种配置；UnitData 只缓存计算结果。

static func compute_final_stats(_unit: UnitData, _config: UnitConfig) -> Dictionary:
	# TODO(阶段3)：实现等级成长、装备加成和上限/下限处理。
	return {}


static func apply_to_unit(_unit: UnitData, _config: UnitConfig) -> void:
	# TODO(阶段3)：调用 compute_final_stats 并写入 UnitData 缓存字段。
	pass
