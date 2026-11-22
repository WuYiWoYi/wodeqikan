extends Node
## 战斗经验文本等级与属性加成扩展入口测试。
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
	_test_tier_mapping()
	_test_name_bounds()
	_test_bonus_interface()
	_test_stat_calculator_integration()


func _test_tier_mapping() -> void:
	var expected: Array = [
		[1, 1, "新兵"],
		[2, 1, "新兵"],
		[3, 2, "一般士兵"],
		[4, 2, "一般士兵"],
		[5, 3, "老兵"],
		[6, 3, "老兵"],
		[7, 4, "精锐"],
		[8, 4, "精锐"],
		[9, 5, "百战精锐"],
		[10, 5, "百战精锐"],
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


func _test_name_bounds() -> void:
	_check(CombatExperience.tier_name_for_level(0) == "新兵", "非法低等级按新兵显示")
	_check(CombatExperience.tier_name_for_level(-5) == "新兵", "负等级按新兵显示")
	_check(CombatExperience.tier_name_for_level(99) == "百战精锐", "超高等级按百战精锐显示")
	_check(CombatExperience.tier_name_for_tier(0) == "新兵", "级别下界被钳制")
	_check(CombatExperience.tier_name_for_tier(99) == "百战精锐", "级别上界被钳制")


func _test_bonus_interface() -> void:
	# 本次只预留接口：五个级别都还没有确认的加成数值。
	for level: int in range(1, 11):
		_check(
			CombatExperience.stat_bonuses_for_level(level).is_empty(),
			"等级 %d 当前没有额外加成" % level
		)

	var stats: Dictionary = {
		"max_hp": 50,
		"attack": 10,
		"move_speed": 60.0,
		"attack_type": 0,
	}
	var applied: Dictionary = CombatExperience.apply_stat_bonuses(stats, 5)
	_check(applied == stats, "无加成时最终属性保持不变")
	applied["max_hp"] = 999
	_check(int(stats["max_hp"]) == 50, "加成入口返回独立字典，不修改原属性")


func _test_stat_calculator_integration() -> void:
	var config := load(MILITIA_PATH) as UnitConfig
	_check(config != null, "加载民兵配置")
	if config == null:
		return
	var unit := UnitData.new()
	unit.level = 9
	var stats: Dictionary = StatCalculator.compute_final_stats(unit, config)
	_check(
		int(stats.get("max_hp", 0)) == config.base_max_hp + 8 * config.hp_per_level,
		"战斗经验加成接入后不改变现有等级成长"
	)
	_check(
		int(stats.get("attack", 0)) == config.base_attack + 8 * config.attack_per_level,
		"攻击成长保持原规则"
	)
	for stat_key: String in ["max_hp", "attack", "attack_interval", "move_speed",
			"attack_range", "attack_type", "body_height"]:
		_check(stats.has(stat_key), "最终属性包含可扩展键：%s" % stat_key)
	_check(CombatExperience.tier_name_for_level(unit.level) == "百战精锐", "9 级显示百战精锐")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[combatexp] OK: %s" % message)
	else:
		_failed = true
		push_error("[combatexp] FAIL: %s" % message)
