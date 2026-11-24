extends Node
## 战斗经验五级制、经验阈值、生命加成与旧存档折算测试。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/combat_experience_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"

var _failed: bool = false


func _ready() -> void:
	_run()
	if _failed:
		push_error("[combatexp] 测试失败")
		get_tree().quit(1)
	else:
		print("[combatexp] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	_test_level_mapping()
	_test_name_bounds()
	_test_thresholds_and_bonuses()
	_test_legacy_mapping()
	_test_stat_calculator_integration()


func _test_level_mapping() -> void:
	var expected: Array = [
		[1, 1, "新兵"],
		[2, 2, "普通士兵"],
		[3, 3, "老兵"],
		[4, 4, "精锐"],
		[5, 5, "百战精锐"],
	]
	for row: Array in expected:
		var level: int = int(row[0])
		_check(
			CombatExperience.tier_for_level(level) == int(row[1]),
			"等级 %d 映射到第 %d 级战斗经验" % [level, int(row[1])]
		)
		_check(
			CombatExperience.tier_name_for_level(level) == str(row[2]),
			"等级 %d 显示为“%s”" % [level, str(row[2])]
		)
	_check(CombatExperience.MAX_LEVEL == 5, "战斗经验只有五级")


func _test_name_bounds() -> void:
	_check(CombatExperience.tier_name_for_level(0) == "新兵", "非法低等级按新兵显示")
	_check(CombatExperience.tier_name_for_level(-5) == "新兵", "负等级按新兵显示")
	_check(CombatExperience.tier_name_for_level(99) == "百战精锐", "超高等级按百战精锐显示")
	_check(CombatExperience.tier_name_for_tier(0) == "新兵", "级别下界被钳制")
	_check(CombatExperience.tier_name_for_tier(99) == "百战精锐", "级别上界被钳制")


func _test_thresholds_and_bonuses() -> void:
	_check(CombatExperience.exp_to_next_level(1) == 100, "新兵升普通士兵需要 100")
	_check(CombatExperience.exp_to_next_level(2) == 300, "普通士兵升老兵需要 300")
	_check(CombatExperience.exp_to_next_level(3) == 500, "老兵升精锐需要 500")
	_check(CombatExperience.exp_to_next_level(4) == 1000, "精锐升百战精锐需要 1000")
	_check(CombatExperience.exp_to_next_level(5) == 0, "满级没有下一级")

	var expected_hp: Array[int] = [0, 5, 15, 30, 50]
	for index: int in range(expected_hp.size()):
		var level: int = index + 1
		_check(
			CombatExperience.max_hp_bonus_for_level(level) == expected_hp[index],
			"等级 %d 生命累计加成 %d" % [level, expected_hp[index]]
		)

	var stats: Dictionary = {
		"max_hp": 50,
		"attack": 10,
		"move_speed": 60.0,
		"attack_type": 0,
	}
	var applied: Dictionary = CombatExperience.apply_stat_bonuses(stats, 5)
	_check(int(applied["max_hp"]) == 100, "五级经验在最终属性上只加一次 +50")
	_check(int(applied["attack"]) == 10, "经验等级不改变攻击力")
	applied["max_hp"] = 999
	_check(int(stats["max_hp"]) == 50, "加成入口返回独立字典，不修改原属性")


func _test_legacy_mapping() -> void:
	var expected: Dictionary = {
		1: 1, 2: 1, 3: 2, 4: 2, 5: 3, 6: 3, 7: 4, 8: 4, 9: 5, 10: 5
	}
	for old_level: int in expected:
		_check(
			CombatExperience.legacy_level_to_combat_level(old_level)
				== int(expected[old_level]),
			"旧 %d 级折算为 %d 级" % [old_level, int(expected[old_level])]
		)


func _test_stat_calculator_integration() -> void:
	var config := load(MILITIA_PATH) as UnitConfig
	_check(config != null, "加载民兵配置")
	if config == null:
		return
	var unit := UnitData.new()
	unit.level = 5
	var stats: Dictionary = StatCalculator.compute_final_stats(unit, config)
	_check(
		int(stats.get("max_hp", 0)) == config.base_max_hp + 50,
		"满级战斗经验提供累计 +50 生命"
	)
	_check(
		int(stats.get("attack", 0)) == config.base_attack + 4 * config.attack_per_level,
		"攻击成长保持配置规则"
	)
	for stat_key: String in ["max_hp", "attack", "attack_interval", "move_speed",
			"attack_range", "attack_type", "body_height"]:
		_check(stats.has(stat_key), "最终属性包含可扩展键：%s" % stat_key)
	_check(CombatExperience.tier_name_for_level(unit.level) == "百战精锐", "5 级显示百战精锐")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[combatexp] OK: %s" % message)
	else:
		_failed = true
		push_error("[combatexp] FAIL: %s" % message)
