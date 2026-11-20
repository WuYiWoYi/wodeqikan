extends Node
## UnitManager 单元测试。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/unit_manager_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"
const TRAINED_PATH: String = "res://Data/Units/infantry_trained.tres"
const FACTION_ID: String = "FACTION_PLAYER"

var _failed: bool = false


func _ready() -> void:
	_run()
	if _failed:
		push_error("[unit] 测试失败")
		get_tree().quit(1)
	else:
		print("[unit] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	var militia: UnitConfig = load(MILITIA_PATH) as UnitConfig
	var trained: UnitConfig = load(TRAINED_PATH) as UnitConfig
	var ids := IdGenerator.new()
	var units := UnitManager.new()
	units.setup(ids)

	var unit_a := units.create_unit(militia, FACTION_ID)
	var unit_b := units.create_unit(militia, FACTION_ID)
	_check(unit_a != null, "创建第一个民兵")
	_check(unit_b != null, "创建第二个民兵")
	if unit_a == null or unit_b == null:
		return

	_check(unit_a.unit_id.begins_with("UNIT_"), "单位 ID 使用 UNIT_ 前缀")
	_check(unit_a.unit_id != unit_b.unit_id, "两次创建得到不同 ID")
	_check(unit_a.get_instance_id() != unit_b.get_instance_id(), "两次创建是独立实例")
	_check(units.get_all_units().size() == 2, "仓储包含 2 个单位")
	_check(units.get_unit(unit_a.unit_id) == unit_a, "按 ID 查询到正确单位")
	_check(units.has_unit(unit_a.unit_id), "has_unit 正确")
	_check(not units.has_unit("UNIT_999999"), "不存在的 ID 查询失败")

	_check(unit_a.config_id == "infantry_militia", "config_id 来自配置")
	_check(unit_a.display_name == "民兵", "显示名来自配置")
	_check(unit_a.level == 1, "等级来自配置")
	_check(unit_a.current_hp == unit_a.max_hp, "出生满血")
	_check(unit_a.max_hp == 30 and unit_a.attack == 5, "民兵基础属性正确")
	_check(unit_a.current_party_id.is_empty(), "出生时没有归属部队")
	_check(unit_a.faction_id == FACTION_ID, "阵营正确")

	var unit_trained := units.create_unit(trained, FACTION_ID)
	_check(unit_trained != null, "创建职业步兵")
	if unit_trained != null:
		_check(unit_trained.max_hp == 45 and unit_trained.attack == 8, "职业步兵属性不同")
		_check(is_equal_approx(unit_trained.move_speed, 55.0), "职业步兵移动速度正确")

	var invalid_config := UnitConfig.new()
	_check(units.create_unit(invalid_config, FACTION_ID) == null, "无效配置不能创建单位")
	_check(units.create_unit(null, FACTION_ID) == null, "空配置不能创建单位")
	_check(UnitManager.new().create_unit(militia, FACTION_ID) == null, "未装配 IdGenerator 不能创建单位")

	var duplicate := UnitData.new()
	duplicate.unit_id = unit_a.unit_id
	duplicate.display_name = "冒名单位"
	duplicate.max_hp = 999
	var duplicate_result := units.add_unit(duplicate)
	_check(duplicate_result.is_empty(), "重复 ID 注册失败")
	_check(units.get_unit(unit_a.unit_id) == unit_a, "重复 ID 不覆盖原单位")
	_check(units.get_unit(unit_a.unit_id).display_name == "民兵", "原单位数据保持不变")
	_check(units.get_all_units().size() == 3, "重复注册未增加单位数量")

	var anonymous := UnitData.new()
	anonymous.display_name = "匿名单位"
	var anonymous_id := units.add_unit(anonymous)
	_check(not anonymous_id.is_empty(), "无 ID 单位自动分配 ID")
	_check(units.get_unit(anonymous_id) == anonymous, "自动分配后可按 ID 查询")
	_check(units.get_all_units().size() == 4, "匿名单位已注册")

	var party_manager := PartyManager.new()
	party_manager.setup(units, ids)
	var party := party_manager.create_party(FACTION_ID, Vector2(10.0, 20.0), "测试部队")
	_check(party != null, "创建测试部队")
	if party == null:
		return
	_check(party_manager.add_member(party.party_id, unit_a.unit_id), "单位加入部队")
	_check(not units.remove_unit(unit_a.unit_id), "已归属部队的单位不能直接删除")
	_check(units.has_unit(unit_a.unit_id), "删除失败后单位仍然存在")
	_check(party_manager.remove_member(party.party_id, unit_a.unit_id), "先移除部队归属")
	_check(units.remove_unit(unit_a.unit_id), "无归属单位可以删除")
	_check(not units.has_unit(unit_a.unit_id), "删除后无法查询到单位")
	_check(not units.remove_unit(unit_a.unit_id), "重复删除返回失败")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[unit] OK: %s" % message)
	else:
		_failed = true
		push_error("[unit] FAIL: %s" % message)
