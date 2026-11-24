extends Node
## Schema v7 → v8 迁移测试：旧 1–10 级战斗经验折算、赎回字段默认值。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/UnitTests/save_migration_test.tscn

var _failed: bool = false


func _ready() -> void:
	_test_legacy_levels()
	_test_current_schema()
	_test_missing_ransoms()
	if _failed:
		push_error("[migration] 测试失败")
		get_tree().quit(1)
	else:
		print("[migration] 全部通过")
		get_tree().quit(0)


func _test_legacy_levels() -> void:
	var payload := {
		"schema_version": 7,
		"units": {
			"UNIT_000001": {"level": 10, "exp": 123},
			"UNIT_000002": {"level": 7, "exp": 0},
			"UNIT_000003": {"level": 2, "exp": 40},
			"UNIT_000004": {"level": 1},
		},
	}
	var save := SaveData.from_dict(payload)
	_check(save != null, "旧存档可读取")
	if save == null:
		return
	_check(save.schema_version == 8, "旧存档升级到 v8")
	_check(int(save.units["UNIT_000001"]["level"]) == 5, "旧 10 级折算为 5 级")
	_check(int(save.units["UNIT_000001"]["exp"]) == 123, "折算保留溢出经验")
	_check(int(save.units["UNIT_000002"]["level"]) == 4, "旧 7 级折算为 4 级")
	_check(int(save.units["UNIT_000003"]["level"]) == 2, "五级内等级保持不变")
	_check(int(save.units["UNIT_000004"]["level"]) == 1, "旧 1 级保持新兵")


func _test_current_schema() -> void:
	var payload := {
		"schema_version": 8,
		"units": {"UNIT_000009": {"level": 4, "exp": 20}},
		"ransoms": {"RANSOM_000001": {"status": 1}},
	}
	var save := SaveData.from_dict(payload)
	_check(save != null, "v8 存档可读取")
	if save == null:
		return
	_check(int(save.units["UNIT_000009"]["level"]) == 4, "v8 读取不重复折算等级")
	_check(save.ransoms.has("RANSOM_000001"), "v8 读取赎回记录")


func _test_missing_ransoms() -> void:
	var payload := {"schema_version": 8, "units": {}}
	var save := SaveData.from_dict(payload)
	_check(save != null and save.ransoms.is_empty(), "缺失赎回字段使用安全默认值")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[migration] OK: %s" % message)
	else:
		_failed = true
		push_error("[migration] FAIL: %s" % message)
