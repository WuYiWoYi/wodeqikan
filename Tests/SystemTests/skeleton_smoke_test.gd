extends Node
## 骨架冒烟测试：验证时间器、实体序列化、存档读写与 WorldContext 装配。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/skeleton_smoke_test.tscn

var _failed: bool = false


func _ready() -> void:
	await _run()
	if _failed:
		push_error("[smoke] 测试失败")
		get_tree().quit(1)
	else:
		print("[smoke] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	var context := WorldContext.new()
	context.name = "SmokeWorldContext"
	add_child(context)

	_check(context.unit_manager != null, "WorldContext 装配 UnitManager")
	_check(context.party_manager != null, "WorldContext 装配 PartyManager")

	var config := UnitConfig.new()
	config.config_id = "TEST_INFANTRY"
	config.display_name = "测试步兵"

	var unit := context.unit_manager.create_unit(config, "FACTION_000001")
	_check(unit != null, "UnitConfig 可生成 UnitData")
	if unit == null:
		return
	_check(unit.unit_id.begins_with("UNIT_"), "单位 ID 格式正确")
	_check(unit.current_hp == config.base_max_hp, "单位出生 HP 正确")

	var party := context.party_manager.create_party(
		"FACTION_000001", Vector2(120.0, 240.0), "测试部队"
	)
	_check(party != null, "可创建 PartyData")
	if party == null:
		return
	_check(context.party_manager.add_member(party.party_id, unit.unit_id), "可加入部队")
	_check(unit.current_party_id == party.party_id, "成员归属双向一致")

	var unit_round_trip := UnitData.from_dict(unit.to_dict())
	_check(unit_round_trip.unit_id == unit.unit_id, "UnitData 序列化往返")
	_check(unit_round_trip.current_party_id == party.party_id, "UnitData 归属往返")

	var party_round_trip := PartyData.from_dict(party.to_dict())
	_check(party_round_trip.world_position == party.world_position, "PartyData 坐标往返")
	_check(party_round_trip.member_unit_ids.has(unit.unit_id), "PartyData 成员往返")

	var save := SaveData.new()
	save.world_elapsed_seconds = 123.4
	save.id_counters = context.id_generator.to_dict()
	save.units = context.unit_manager.to_dict()
	save.parties = context.party_manager.to_dict()

	_check(SaveManager.save_game("__smoke_test__", save) == OK, "存档写入成功")
	var loaded := SaveManager.load_game("__smoke_test__")
	_check(loaded != null, "存档读取成功")
	if loaded != null:
		_check(loaded.units.size() == 1, "存档单位数量正确")
		_check(loaded.parties.size() == 1, "存档部队数量正确")
		_check(is_equal_approx(loaded.world_elapsed_seconds, 123.4), "存档时间正确")
	SaveManager.delete_save("__smoke_test__")

	var tick_counter: Array[int] = [0]
	var on_world_tick := func(_fixed_delta: float) -> void:
		tick_counter[0] += 1
	TimeManager.start_session()
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)
	TimeManager.world_tick.connect(on_world_tick)
	await get_tree().create_timer(0.5).timeout
	TimeManager.world_tick.disconnect(on_world_tick)
	TimeManager.stop_session()
	_check(tick_counter[0] >= 3, "0.5 秒内至少产生 3 次世界 tick（实际 %s）" % tick_counter[0])

	context.queue_free()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[smoke] OK: %s" % message)
	else:
		_failed = true
		push_error("[smoke] FAIL: %s" % message)
