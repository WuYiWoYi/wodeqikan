class_name CombatExperience
extends RefCounted
## 战斗经验等级：把 UnitData.level（1..max_level）映射为五个文本级别。
##
## 注意：这里的“战斗经验”不是兵种等级（UnitConfig.tier），也不是职业或装备等级。
## 名称、等级区间与属性加成统一在本类维护；UI 只读取名称，不各自维护文本。
## 底层经验积累（UnitData.exp）与逐级成长机制保持不变。

## 从低到高五个战斗经验级别。
const TIER_NAMES: Array[String] = ["新兵", "一般士兵", "老兵", "精锐", "百战精锐"]
## 每个级别的起始等级（1-based），与 TIER_NAMES 一一对应：
## 新兵 1-2 / 一般士兵 3-4 / 老兵 5-6 / 精锐 7-8 / 百战精锐 9+。
const TIER_MIN_LEVELS: Array[int] = [1, 3, 5, 7, 9]

## 预留：每个战斗经验级别对最终属性的加成。
## 键使用 StatCalculator 的最终属性键（如 "max_hp" / "attack"），后续在
## StatCalculator 中增加新属性时，只要在加成表填写同名键即可自动生效，
## 不需要修改 UnitData 或任何 UI。
## 当前五个级别均为空字典：加成数值尚未确认，本次不加入具体平衡数值。
const TIER_STAT_BONUSES: Array[Dictionary] = [{}, {}, {}, {}, {}]


## 等级对应的 1-based 战斗经验级别；非法等级按 1 级处理。
static func tier_for_level(level: int) -> int:
	var clamped_level: int = maxi(level, 1)
	var tier: int = 1
	for index: int in range(TIER_MIN_LEVELS.size()):
		if clamped_level >= TIER_MIN_LEVELS[index]:
			tier = index + 1
	return tier


## 等级对应的战斗经验名称，供详情面板与士兵列表共用。
static func tier_name_for_level(level: int) -> String:
	return tier_name_for_tier(tier_for_level(level))


static func tier_name_for_tier(tier: int) -> String:
	var index: int = clampi(tier - 1, 0, TIER_NAMES.size() - 1)
	return TIER_NAMES[index]


## 当前等级的属性加成；尚未配置时返回空字典。
static func stat_bonuses_for_level(level: int) -> Dictionary:
	var index: int = tier_for_level(level) - 1
	if index < 0 or index >= TIER_STAT_BONUSES.size():
		return {}
	return TIER_STAT_BONUSES[index]


## 把战斗经验加成叠加到最终属性字典，返回新字典，不修改入参。
## 只处理数值型且已存在于 stats 中的键；未知键忽略，便于后续扩展新属性。
static func apply_stat_bonuses(stats: Dictionary, level: int) -> Dictionary:
	# 始终返回独立字典，调用方可以安全修改结果而不影响原属性。
	var result: Dictionary = stats.duplicate()
	var bonuses: Dictionary = stat_bonuses_for_level(level)
	if bonuses.is_empty():
		return result
	for stat_key: Variant in bonuses:
		var key: String = str(stat_key)
		if not result.has(key):
			continue
		var bonus: Variant = bonuses[stat_key]
		var current: Variant = result[key]
		if not (bonus is int or bonus is float):
			continue
		if not (current is int or current is float):
			continue
		if current is int and bonus is int:
			result[key] = int(current) + int(bonus)
		else:
			result[key] = float(current) + float(bonus)
	return result
