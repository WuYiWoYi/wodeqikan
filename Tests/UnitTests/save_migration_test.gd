extends Node
## Schema 迁移测试：旧 1–10 级战斗经验折算、赎回/雇佣兵/被俘字段默认值。
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
	_check(save.schema_version == 10, "旧存档升级到 v10")
	_check(save.captivity.is_empty(), "旧存档缺失被俘字段使用空载荷")
	_check(int(save.units["UNIT_000001"]["level"]) == 5, "旧 10 级折算为 5 级")
	_check(int(save.units["UNIT_000001"]["exp"]) == 123, "折算保留溢出经验")
	_check(int(save.units["UNIT_000002"]["level"]) == 4, "旧 7 级折算为 4 级")
	_check(int(save.units["UNIT_000003"]["level"]) == 2, "五级内等级保持不变")
	_check(int(save.units["UNIT_000004"]["level"]) == 1, "旧 1 级保持新兵")


func _test_current_schema() -> void:
	var payload := {
		"schema_version": 10,
		"units": {"UNIT_000009": {"level": 4, "exp": 20}},
		"ransoms": {"RANSOM_000001": {"status": 1}},
		"mercenaries": {"initialized": true, "records": []},
		"captivity": {
			"is_player_captive": true,
			"captor_party_id": "PARTY_000001",
			"prisoner_healing_last_hour": 3,
			"escape_check_last_hour": 4,
			"escape_protection_until": 0.0,
		},
	}
	var save := SaveData.from_dict(payload)
	_check(save != null, "v10 存档可读取")
	if save == null:
		return
	_check(int(save.units["UNIT_000009"]["level"]) == 4, "v10 读取不重复折算等级")
	_check(save.ransoms.has("RANSOM_000001"), "v10 读取赎回记录")
	_check(bool(save.mercenaries.get("initialized", false)), "v10 读取雇佣兵池")
	_check(
		bool(save.captivity.get("is_player_captive", false))
			and str(save.captivity.get("captor_party_id", "")) == "PARTY_000001",
		"v10 读取玩家被俘状态"
	)


func _test_missing_ransoms() -> void:
	var payload := {"schema_version": 8, "units": {}}
	var save := SaveData.from_dict(payload)
	_check(save != null and save.ransoms.is_empty(), "缺失赎回字段使用安全默认值")
	_check(save.mercenaries.is_empty(), "v8 缺失雇佣兵字段使用空载荷")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[migration] OK: %s" % message)
	else:
		_failed = true
		push_error("[migration] FAIL: %s" % message)
