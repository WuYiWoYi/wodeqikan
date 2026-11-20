extends Node
## StatCalculator 单元测试。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/stat_calculator_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"
const TRAINED_PATH: String = "res://Data/Units/infantry_trained.tres"

var _failed: bool = false


func _ready() -> void:
	_run()
	if _failed:
		push_error("[stat] 测试失败")
		get_tree().quit(1)
	else:
		print("[stat] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	var militia: UnitConfig = load(MILITIA_PATH) as UnitConfig
	var trained: UnitConfig = load(TRAINED_PATH) as UnitConfig
	_check(militia != null, "加载民兵配置")
	_check(trained != null, "加载职业步兵配置")
	if militia == null or trained == null:
		return

	_check(militia.validate(), "民兵配置通过校验")
	_check(trained.validate(), "职业步兵配置通过校验")
	_check(militia.config_id == "infantry_militia", "民兵 config_id 正确")
	_check(trained.config_id == "infantry_trained", "职业步兵 config_id 正确")

	var unit := UnitData.new()
	var militia_stats := StatCalculator.compute_final_stats(unit, militia)
	_check(militia_stats.size() == StatCalculator.STAT_KEYS.size(), "返回全部基础属性")
	_check(int(militia_stats["max_hp"]) == 30, "民兵 max_hp = 30")
	_check(int(militia_stats["attack"]) == 5, "民兵 attack = 5")
	_check(is_equal_approx(float(militia_stats["attack_interval"]), 1.2), "民兵 attack_interval = 1.2")
	_check(is_equal_approx(float(militia_stats["move_speed"]), 60.0), "民兵 move_speed = 60")
	_check(is_equal_approx(float(militia_stats["attack_range"]), 20.0), "民兵 attack_range = 20")

	var trained_stats := StatCalculator.compute_final_stats(unit, trained)
	_check(int(trained_stats["max_hp"]) == 45, "职业步兵 max_hp = 45")
	_check(int(trained_stats["attack"]) == 8, "职业步兵 attack = 8")
	_check(is_equal_approx(float(trained_stats["attack_interval"]), 1.0), "职业步兵 attack_interval = 1.0")
	_check(is_equal_approx(float(trained_stats["move_speed"]), 55.0), "职业步兵 move_speed = 55")

	_check(StatCalculator.apply_to_unit(unit, militia), "写入民兵属性")
	_check(unit.max_hp == 30 and unit.attack == 5, "UnitData 获得民兵属性")
	_check(unit.current_hp == 1, "写入属性不重置 current_hp")

	unit.current_hp = 999
	_check(StatCalculator.apply_to_unit(unit, militia), "再次写入民兵属性")
	_check(unit.current_hp == 30, "超过上限的 current_hp 被 clamp")

	_check(StatCalculator.apply_to_unit(unit, trained), "写入职业步兵属性")
	_check(unit.max_hp == 45 and unit.attack == 8, "UnitData 获得职业步兵属性")
	_check(unit.current_hp == 30, "重算属性不重置 current_hp")

	unit.current_hp = 999
	_check(StatCalculator.apply_to_unit(unit, trained), "再次写入职业步兵属性")
	_check(unit.current_hp == 45, "新上限下再次 clamp")

	_check(StatCalculator.compute_final_stats(null, null).is_empty(), "空输入返回空字典")
	_check(StatCalculator.compute_final_stats(unit, null).is_empty(), "缺少配置返回空字典")
	_check(not StatCalculator.apply_to_unit(null, militia), "空单位写入失败")
	_check(not StatCalculator.apply_to_unit(unit, null), "空配置写入失败")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[stat] OK: %s" % message)
	else:
		_failed = true
		push_error("[stat] FAIL: %s" % message)
