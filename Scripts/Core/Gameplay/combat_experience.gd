class_name CombatExperience
extends RefCounted
## 战斗经验等级：把 UnitData.level（1..MAX_LEVEL）映射为五个经验等级。
##
## 注意：这里的“战斗经验”不是兵种等级（UnitConfig.tier），也不是职业或装备等级。
## 名称、经验门槛与属性加成统一在本类维护；UI 只读取名称，不各自维护文本。
##
## 经验按“当前等级阶段”累计：
##   新兵 100 → 普通士兵 300 → 老兵 500 → 精锐 1000 → 百战精锐（上限）
## 晋升后保留超出当前门槛的经验，不会因升级丢失多余经验。

const MAX_LEVEL: int = 5

## 从低到高五个战斗经验等级。
const TIER_NAMES: Array[String] = ["新兵", "普通士兵", "老兵", "精锐", "百战精锐"]
## 每个级别的起始等级（1-based），与 TIER_NAMES 一一对应。
const TIER_MIN_LEVELS: Array[int] = [1, 2, 3, 4, 5]

## 下标 = 当前等级 - 1；值为升到下一等级所需经验。
## 最高等级没有下一级，查询时返回 0。四段之和为 1900，与升级链路一致。
const EXP_TO_NEXT_LEVEL: Array[int] = [100, 300, 500, 1000]

## 每个经验等级的最大生命值“累计”加成（相对新兵）：
## 新兵 +0 / 普通士兵 +5 / 老兵 +15 / 精锐 +30 / 百战精锐 +50。
## 由 StatCalculator 在最终属性计算时统一调用，永远按等级派生，
## 不累计写入存档，因此读档或重复刷新不会重复叠加。
const TIER_STAT_BONUSES: Array[Dictionary] = [
	{"max_hp": 0},
	{"max_hp": 5},
	{"max_hp": 15},
	{"max_hp": 30},
	{"max_hp": 50},
]


## 等级对应的 1-based 战斗经验级别；非法等级按边界处理。
static func tier_for_level(level: int) -> int:
	return clampi(level, 1, MAX_LEVEL)


## 等级对应的战斗经验名称，供详情面板与士兵列表共用。
static func tier_name_for_level(level: int) -> String:
	return tier_name_for_tier(tier_for_level(level))


static func tier_name_for_tier(tier: int) -> String:
	var index: int = clampi(tier - 1, 0, TIER_NAMES.size() - 1)
	return TIER_NAMES[index]


## 当前等级升到下一等级所需经验。已达到最高等级时返回 0。
static func exp_to_next_level(level: int) -> int:
	var index: int = level - 1
	if index < 0 or index >= EXP_TO_NEXT_LEVEL.size():
		return 0
	return maxi(1, EXP_TO_NEXT_LEVEL[index])


## 当前等级的生命值累计加成。等级超界时按五级上限处理。
static func max_hp_bonus_for_level(level: int) -> int:
	var bonuses := stat_bonuses_for_level(level)
	return int(bonuses.get("max_hp", 0))


## 旧存档的 10 级战斗经验 → v8 的五级经验。
## 旧显示规则为 1–2 新兵、3–4 一般士兵、5–6 老兵、7–8 精锐、9+ 百战精锐，
## 因此两级合并为一级，保持玩家看到的等级名称不变。
static func legacy_level_to_combat_level(old_level: int) -> int:
	if old_level <= 1:
		return 1
	return clampi(ceili(float(old_level) / 2.0), 1, MAX_LEVEL)


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
