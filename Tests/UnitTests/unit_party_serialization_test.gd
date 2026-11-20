extends Node
## 士兵与部队成员关系的存档往返测试。
## 覆盖：5 名士兵、多支部队、转队、保存/读取、读档后继续转队、二次往返、坏引用拒绝加载。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/unit_party_serialization_test.tscn

const TEST_SLOT: String = "__unit_party_test__"
const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"
const TRAINED_PATH: String = "res://Data/Units/infantry_trained.tres"

var _failed: bool = false


func _ready() -> void:
	await _run()
	SaveManager.delete_save(TEST_SLOT)
	if _failed:
		push_error("[serde] 测试失败")
		get_tree().quit(1)
	else:
		print("[serde] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	var militia: UnitConfig = load(MILITIA_PATH) as UnitConfig
	var trained: UnitConfig = load(TRAINED_PATH) as UnitConfig
	_check(militia != null and trained != null, "加载两种兵种配置")
	if militia == null or trained == null:
		return

	var context := WorldContext.new()
	context.name = "UnitPartySaveContext"
	add_child(context)
	_check(WorldInitializer.create_new_world(context), "初始化世界")
	var party_a := context.get_player_party()
	_check(party_a != null, "取得玩家部队 Party A")
	if party_a == null:
		return

	# Milestone 2 新游戏会预置双方测试士兵；本测试从空世界开始。
	for party: PartyData in context.party_manager.get_all_parties():
		for unit_id: String in party.member_unit_ids.duplicate():
			context.party_manager.remove_member(party.party_id, unit_id)
			context.unit_manager.remove_unit(unit_id)
	_check(context.unit_manager.get_all_units().is_empty(), "清空预置测试士兵")

	var militia_ids: Array[String] = []
	for i: int in range(3):
		var unit := context.unit_manager.create_unit(militia, WorldInitializer.PLAYER_FACTION_ID)
		_check(unit != null, "创建第 %d 名民兵" % (i + 1))
		if unit != null:
			militia_ids.append(unit.unit_id)
			_check(
				context.party_manager.add_member(party_a.party_id, unit.unit_id),
				"民兵 %d 加入 Party A" % (i + 1)
			)
	for i: int in range(2):
		var unit := context.unit_manager.create_unit(trained, WorldInitializer.PLAYER_FACTION_ID)
		_check(unit != null, "创建第 %d 名职业步兵" % (i + 1))
		if unit != null:
			_check(
				context.party_manager.add_member(party_a.party_id, unit.unit_id),
				"职业步兵 %d 加入 Party A" % (i + 1)
			)

	_check(militia_ids.size() == 3, "3 名民兵创建成功")
	_check(party_a.member_unit_ids.size() == 5, "Party A 包含 5 名成员")
	_check(context.party_manager.get_units_of_party(party_a.party_id).size() == 5, "Party A 成员可查询")

	if militia_ids.is_empty():
		return
	var moved_unit_id: String = militia_ids[0]
	var party_b := context.party_manager.create_party(
		WorldInitializer.PLAYER_FACTION_ID, Vector2(900.0, 900.0), "Party B"
	)
	_check(party_b != null, "创建 Party B")
	if party_b == null:
		return

	_check(context.party_manager.remove_member(party_a.party_id, moved_unit_id), "从 Party A 移除 1 名民兵")
	_check(context.unit_manager.has_unit(moved_unit_id), "移除后该民兵仍存在")
	_check(
		context.unit_manager.get_unit(moved_unit_id).current_party_id.is_empty(),
		"移除后归属暂时清空"
	)
	_check(context.party_manager.add_member(party_b.party_id, moved_unit_id), "将该民兵转入 Party B")
	_check(party_a.member_unit_ids.size() == 4, "Party A 剩余 4 名成员")
	_check(party_b.member_unit_ids.size() == 1, "Party B 包含 1 名成员")

	var save := context.to_save_data()
	_check(save.units.size() == 5, "存档包含 5 名士兵")
	_check(save.parties.size() == 4, "存档包含 4 支部队")
	_check(SaveManager.save_game(TEST_SLOT, save) == OK, "第一次保存成功")

	var loaded := SaveManager.load_game(TEST_SLOT)
	_check(loaded != null, "第一次读取成功")
	if loaded == null:
		return

	var restored := WorldContext.new()
	restored.name = "UnitPartyRestoredContext"
	add_child(restored)
	_check(restored.load_from_save_data(loaded), "恢复世界并通过成员关系校验")
	_check(restored.player_party_id == party_a.party_id, "恢复玩家部队 ID")

	var restored_a := restored.party_manager.get_party(party_a.party_id)
	var restored_b := restored.party_manager.get_party(party_b.party_id)
	_check(restored_a != null and restored_b != null, "恢复两支部队")
	if restored_a == null or restored_b == null:
		return
	_check(restored_a.member_unit_ids.size() == 4, "恢复后 Party A 有 4 名成员")
	_check(restored_b.member_unit_ids.size() == 1, "恢复后 Party B 有 1 名成员")
	_check(not restored_a.member_unit_ids.has(moved_unit_id), "恢复后 Party A 不含已转出民兵")
	_check(restored_b.member_unit_ids.has(moved_unit_id), "恢复后 Party B 含该民兵")

	var restored_unit := restored.unit_manager.get_unit(moved_unit_id)
	_check(restored_unit != null, "恢复该民兵数据")
	if restored_unit != null:
		_check(restored_unit.current_party_id == party_b.party_id, "恢复后归属指向 Party B")
		_check(restored_unit.config_id == "infantry_militia", "恢复后兵种正确")
		_check(restored_unit.max_hp == 30 and restored_unit.attack == 5, "恢复后基础属性正确")
		_check(restored_unit.current_hp == 30, "恢复后当前生命正确")
		_check(is_equal_approx(restored_unit.attack_interval, 1.2), "恢复后攻击间隔正确")

	var militia_count: int = 0
	var trained_count: int = 0
	for unit: UnitData in restored.unit_manager.get_all_units():
		if unit.config_id == "infantry_militia":
			militia_count += 1
		elif unit.config_id == "infantry_trained":
			trained_count += 1
		_check(unit.current_hp <= unit.max_hp and unit.current_hp >= 0, "生命值在合法范围: %s" % unit.unit_id)
	_check(militia_count == 3, "恢复后民兵数量为 3")
	_check(trained_count == 2, "恢复后职业步兵数量为 2")

	var second_moved_id: String = restored_a.member_unit_ids[0]
	_check(restored.party_manager.transfer_member(second_moved_id, party_b.party_id), "读档后继续转移士兵")
	_check(restored_a.member_unit_ids.size() == 3, "继续转移后 Party A 有 3 名成员")
	_check(restored_b.member_unit_ids.size() == 2, "继续转移后 Party B 有 2 名成员")
	_check(
		restored.unit_manager.get_unit(second_moved_id).current_party_id == party_b.party_id,
		"继续转移后双向归属一致"
	)

	var save_again := restored.to_save_data()
	_check(SaveManager.save_game(TEST_SLOT, save_again) == OK, "第二次保存成功")
	var loaded_again := SaveManager.load_game(TEST_SLOT)
	_check(loaded_again != null, "第二次读取成功")
	if loaded_again == null:
		return

	var restored_again := WorldContext.new()
	restored_again.name = "UnitPartyRestoredAgainContext"
	add_child(restored_again)
	_check(restored_again.load_from_save_data(loaded_again), "二次往返通过成员关系校验")
	var final_a := restored_again.party_manager.get_party(party_a.party_id)
	var final_b := restored_again.party_manager.get_party(party_b.party_id)
	_check(final_a != null and final_b != null, "二次往返恢复两支部队")
	if final_a != null and final_b != null:
		_check(final_a.member_unit_ids.size() == 3, "二次往返后 Party A 有 3 名成员")
		_check(final_b.member_unit_ids.size() == 2, "二次往返后 Party B 有 2 名成员")
		_check(final_b.member_unit_ids.has(second_moved_id), "二次往返后转移结果保留")

	_check_corrupt_payload_rejected(loaded_again, party_a.party_id)

	context.queue_free()
	restored.queue_free()
	restored_again.queue_free()


func _check_corrupt_payload_rejected(loaded: SaveData, party_id: String) -> void:
	var corrupt := SaveData.new()
	corrupt.world_id = loaded.world_id
	corrupt.world_created_at = loaded.world_created_at
	corrupt.world_size = loaded.world_size
	corrupt.player_party_id = loaded.player_party_id
	corrupt.id_counters = loaded.id_counters
	corrupt.units = loaded.units
	corrupt.parties = loaded.parties.duplicate(true)
	corrupt.settlements = loaded.settlements

	var party_payload: Dictionary = corrupt.parties[party_id]
	var members: Array = party_payload["member_unit_ids"]
	members.append("UNIT_999999")
	party_payload["member_unit_ids"] = members
	corrupt.parties[party_id] = party_payload

	var corrupt_context := WorldContext.new()
	corrupt_context.name = "UnitPartyCorruptContext"
	add_child(corrupt_context)
	_check(not corrupt_context.load_from_save_data(corrupt), "成员引用损坏时拒绝读档")
	corrupt_context.queue_free()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[serde] OK: %s" % message)
	else:
		_failed = true
		push_error("[serde] FAIL: %s" % message)
