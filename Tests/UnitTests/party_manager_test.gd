extends Node
## PartyManager 单元测试：成员增删、转队、重复 ID、解散与一致性校验。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/party_manager_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"
const FACTION_A: String = "FACTION_A"
const FACTION_B: String = "FACTION_B"

var _failed: bool = false
var _militia: UnitConfig = null


func _ready() -> void:
	_run()
	if _failed:
		push_error("[party] 测试失败")
		get_tree().quit(1)
	else:
		print("[party] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	_militia = load(MILITIA_PATH) as UnitConfig
	_check(_militia != null, "加载民兵配置")
	if _militia == null:
		return

	_test_membership_operations()
	_test_validation()


func _test_membership_operations() -> void:
	var ids := IdGenerator.new()
	var units := UnitManager.new()
	units.setup(ids)
	var parties := PartyManager.new()
	parties.setup(units, ids)

	var unit_one := units.create_unit(_militia, FACTION_A)
	var unit_two := units.create_unit(_militia, FACTION_A)
	_check(unit_one != null and unit_two != null, "创建测试单位")
	if unit_one == null or unit_two == null:
		return

	var party_a := parties.create_party(FACTION_A, Vector2.ZERO, "甲队")
	var party_b := parties.create_party(FACTION_A, Vector2(100.0, 0.0), "乙队")
	_check(party_a != null and party_b != null, "创建两支部队")
	if party_a == null or party_b == null:
		return
	_check(party_a.party_id.begins_with("PARTY_"), "部队 ID 使用 PARTY_ 前缀")
	_check(party_a.party_name == "甲队", "部队名称正确")

	_check(parties.add_member(party_a.party_id, unit_one.unit_id), "单位加入甲队")
	_check(party_a.member_unit_ids.has(unit_one.unit_id), "甲队成员列表包含单位")
	_check(unit_one.current_party_id == party_a.party_id, "单位归属指向甲队")
	var member_ids := parties.get_member_ids(party_a.party_id)
	_check(member_ids.size() == 1 and member_ids.has(unit_one.unit_id), "get_member_ids 返回成员列表")
	member_ids.append("UNIT_999999")
	_check(not party_a.member_unit_ids.has("UNIT_999999"), "get_member_ids 返回副本")

	_check(parties.add_member(party_a.party_id, unit_one.unit_id), "重复加入同一部队安全返回")
	_check(_count(party_a.member_unit_ids, unit_one.unit_id) == 1, "重复加入不产生重复成员")

	_check(parties.add_member(party_b.party_id, unit_one.unit_id), "单位转入乙队")
	_check(not party_a.member_unit_ids.has(unit_one.unit_id), "转队后甲队不再包含单位")
	_check(_count(party_b.member_unit_ids, unit_one.unit_id) == 1, "乙队只包含一个该单位")
	_check(unit_one.current_party_id == party_b.party_id, "单位最终只指向乙队")

	_check(parties.transfer_member(unit_one.unit_id, party_a.party_id), "transfer_member 转回甲队")
	_check(not party_b.member_unit_ids.has(unit_one.unit_id), "转回后乙队不再包含单位")
	_check(_count(party_a.member_unit_ids, unit_one.unit_id) == 1, "甲队只包含一个该单位")
	_check(unit_one.current_party_id == party_a.party_id, "transfer_member 更新双向归属")

	_check(parties.remove_member(party_a.party_id, unit_one.unit_id), "从甲队移除单位")
	_check(units.has_unit(unit_one.unit_id), "移除成员后单位仍然存在")
	_check(unit_one.current_party_id.is_empty(), "移除后归属清空")
	_check(not party_a.member_unit_ids.has(unit_one.unit_id), "甲队成员列表已移除单位")
	_check(not parties.remove_member(party_a.party_id, unit_one.unit_id), "重复移除返回失败")
	_check(not parties.remove_member(party_a.party_id, "UNIT_999999"), "移除不存在的成员返回失败")

	var enemy_party := parties.create_party(FACTION_B, Vector2.ZERO, "敌方部队")
	_check(enemy_party != null, "创建敌方部队")
	if enemy_party != null:
		_check(not parties.add_member(enemy_party.party_id, unit_two.unit_id), "不同阵营不能加入")
		_check(enemy_party.member_unit_ids.is_empty(), "失败后敌方成员列表不变")
		_check(unit_two.current_party_id.is_empty(), "失败后单位归属不变")

	_check(not parties.add_member("PARTY_999999", unit_two.unit_id), "不存在的部队拒绝加入")
	_check(not parties.add_member(party_a.party_id, "UNIT_999999"), "不存在的单位拒绝加入")

	var duplicate_party := PartyData.new()
	duplicate_party.party_id = party_a.party_id
	duplicate_party.party_name = "冒名部队"
	_check(parties.add_party(duplicate_party).is_empty(), "重复部队 ID 注册失败")
	_check(parties.get_party(party_a.party_id).party_name == "甲队", "重复 ID 不覆盖原部队")

	_check(parties.add_member(party_a.party_id, unit_two.unit_id), "第二个单位加入甲队")
	_check(parties.remove_party(party_a.party_id), "解散甲队")
	_check(not parties.has_party(party_a.party_id), "解散后部队 ID 不可查询")
	_check(units.has_unit(unit_two.unit_id), "解散后单位保留")
	_check(unit_two.current_party_id.is_empty(), "解散后成员归属清空")
	_check(not parties.remove_party(party_a.party_id), "重复解散返回失败")

	_check(parties.validate_membership_consistency().is_empty(), "正常数据通过一致性校验")


func _test_validation() -> void:
	var ids := IdGenerator.new()
	var units := UnitManager.new()
	units.setup(ids)
	var parties := PartyManager.new()
	parties.setup(units, ids)

	var unit_one := units.create_unit(_militia, FACTION_A)
	var party_one := parties.create_party(FACTION_A, Vector2.ZERO, "校验一队")
	var party_two := parties.create_party(FACTION_A, Vector2.ZERO, "校验二队")
	_check(unit_one != null and party_one != null and party_two != null, "创建校验夹具")
	if unit_one == null or party_one == null or party_two == null:
		return
	_check(parties.validate_membership_consistency().is_empty(), "校验夹具初始状态一致")

	party_one.member_unit_ids.append("UNIT_999999")
	_check(
		_contains(parties.validate_membership_consistency(), "不存在的单位"),
		"检测到部队引用不存在的单位"
	)
	party_one.member_unit_ids.clear()

	unit_one.current_party_id = "PARTY_999999"
	_check(
		_contains(parties.validate_membership_consistency(), "不存在的部队"),
		"检测到单位指向不存在的部队"
	)
	unit_one.current_party_id = ""

	_check(parties.add_member(party_one.party_id, unit_one.unit_id), "准备双向一致数据")
	party_two.member_unit_ids.append(unit_one.unit_id)
	_check(
		_contains(parties.validate_membership_consistency(), "同时出现在部队"),
		"检测到单位同时属于两支部队"
	)
	party_two.member_unit_ids.clear()

	unit_one.current_party_id = party_two.party_id
	_check(
		_contains(parties.validate_membership_consistency(), "成员列表不一致"),
		"检测到 current_party_id 与成员列表不一致"
	)
	unit_one.current_party_id = party_one.party_id

	party_one.member_unit_ids.append(unit_one.unit_id)
	_check(
		_contains(parties.validate_membership_consistency(), "重复包含"),
		"检测到同一部队成员列表重复"
	)
	party_one.member_unit_ids.erase(unit_one.unit_id)

	_check(parties.remove_member(party_one.party_id, unit_one.unit_id), "清理校验数据")
	_check(parties.validate_membership_consistency().is_empty(), "清理后重新通过校验")


func _count(ids: Array[String], unit_id: String) -> int:
	var count: int = 0
	for value: String in ids:
		if value == unit_id:
			count += 1
	return count


func _contains(messages: Array[String], needle: String) -> bool:
	for message: String in messages:
		if message.contains(needle):
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[party] OK: %s" % message)
	else:
		_failed = true
		push_error("[party] FAIL: %s" % message)
