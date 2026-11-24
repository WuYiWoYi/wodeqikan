extends Node
## NPC 领主出售后的家族赎回：价格、等待、事件、接受/取消、失效、UI 与存档。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/lord_ransom_test.tscn

var _failed: bool = false
var _context: WorldContext = null
var _map: Node = null
var _player: PartyData = null
var _town: SettlementData = null
var _other_settlement: SettlementData = null
var _used_noble_ids: Array[String] = []


func _ready() -> void:
	await _run_async()
	_cleanup()
	if _failed:
		push_error("[ransom] 测试失败")
		get_tree().quit(1)
	else:
		print("[ransom] 全部通过")
		get_tree().quit(0)


func _run_async() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)
	_context = WorldContext.new()
	_context.name = "LordRansomTestContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return
	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id
	_player = _context.get_player_party()
	_town = _find_settlement(WorldInitializer.BURKNANIA_TOWN_NAME)
	_other_settlement = _find_settlement(WorldInitializer.BARI_VILLAGE_NAME)
	_check(_player != null and _town != null and _other_settlement != null, "找到玩家部队与地点")
	if _player == null or _town == null or _other_settlement == null:
		return

	await _test_sale_and_accept_with_ui()
	_test_invalid_event_closes_dialog()
	_test_missing_house_recovers()
	_test_pending_request_persistence()


# ---------------------------------------------------------------------------
# 出售 → 等待 → 事件 → 接受（带右侧事件框与详情弹窗）
# ---------------------------------------------------------------------------


func _test_sale_and_accept_with_ui() -> void:
	var lord := _next_lord_unit()
	_check(not lord.is_empty(), "找到可出售的 NPC 领主单位")
	if lord.is_empty():
		return
	var unit := _context.unit_manager.get_unit(str(lord["unit_id"]))
	var noble := _context.noble_manager.get_noble(str(lord["noble_id"]))
	_used_noble_ids.append(noble.lord_id)

	_check(
		_context.prisoner_trade_manager.get_sell_price(unit) == 100,
		"NPC 领主统一售价 100 金币"
	)
	var sold := _sell_lord(unit, noble)
	_check(bool(sold.get("success", false)), "领主可作为俘虏出售")
	_check(int(sold.get("gold", 0)) == 100, "出售领主获得 100 金币")
	_check(
		_context.lord_ransom_manager.get_lord_state(noble.lord_id) == "WAITING",
		"出售后进入等待状态"
	)
	_check(
		_context.event_center.get_events_of_type("RANSOM").is_empty(),
		"出售当下不立即产生事件"
	)

	_advance_to_due(noble.lord_id)
	var events: Array[Dictionary] = _context.event_center.get_events_of_type("RANSOM")
	_check(events.size() == 1, "等待结束后生成一条家族赎回事件")
	if events.is_empty():
		return
	var event: Dictionary = events[0]
	var ransom_id: String = str(event.get("ransom_id", ""))
	var ransom_gold: int = int(event.get("gold", 0))
	_check(ransom_gold > 100, "赎金大于 100 金币")
	_check(str(event.get("lord_name", "")) == noble.display_name, "事件包含领主名")
	_check(not str(event.get("house_name", "")).is_empty(), "事件包含家族名")
	_check(bool(event.get("actionable", false)), "事件标记为可操作")
	_check(
		_context.lord_ransom_manager.get_lord_state(noble.lord_id) == "REQUESTED",
		"事件生成后进入已请求状态"
	)
	_check(_context.lord_ransom_manager.decline_ransom(ransom_id), "取消只保留事件")
	_check(
		_context.event_center.get_events_of_type("RANSOM").size() == 1,
		"取消后事件仍然存在"
	)

	var packed := load("res://Scenes/WorldMap/world_map.tscn") as PackedScene
	_map = packed.instantiate()
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame
	var feed = _map.call("get_event_feed")
	var dialog = _map.call("get_event_detail_dialog")
	_check(feed != null and feed.visible, "右侧事件框在有事件时显示")
	if feed == null or dialog == null:
		return
	_check(feed.get_event_ids() == [str(event.get("event_id", ""))], "事件框显示当前事件")
	_check(
		is_equal_approx(TimeManager.get_effective_world_scale(), 1.0),
		"只显示事件框不会暂停世界时间"
	)

	var item := _first_feed_button(feed)
	_check(item != null, "事件框包含可点击条目")
	if item == null:
		return
	item.pressed.emit()
	await get_tree().process_frame
	_check(dialog.visible, "点击事件打开详情弹窗")
	_check(dialog.get_title_text() == "家族赎回请求", "详情标题正确")
	_check(dialog.get_body_text().contains(noble.display_name), "详情包含领主名")
	_check(dialog.get_body_text().contains(str(event.get("house_name", ""))), "详情包含家族名")
	_check(dialog.get_gold_text().contains(str(ransom_gold)), "详情包含赎金")
	_check(is_zero_approx(TimeManager.get_effective_world_scale()), "详情弹窗打开时暂停世界")

	var gold_before: int = _context.player_profile.gold
	var accept_button := dialog.find_child("RansomAcceptButton", true, false) as Button
	_check(accept_button != null, "详情弹窗存在接受按钮")
	if accept_button == null:
		return
	accept_button.pressed.emit()
	await get_tree().process_frame

	_check(_context.player_profile.gold == gold_before + ransom_gold, "接受后只支付一次赎金")
	_check(not dialog.visible, "接受后弹窗关闭")
	_check(not feed.visible, "接受后事件框隐藏")
	_check(
		_context.lord_ransom_manager.get_lord_state(noble.lord_id) == "ACCEPTED",
		"接受后记录进入已赎回状态"
	)
	_check(_context.event_center.get_events_of_type("RANSOM").is_empty(), "接受后事件移除")

	var restored_unit := _context.unit_manager.get_unit(unit.unit_id)
	_check(restored_unit != null and restored_unit.is_alive(), "领主恢复为可活动单位")
	_check(restored_unit.sold_to_settlement_id.is_empty(), "领主清除出售状态")
	_check(not restored_unit.is_prisoner(), "领主不再是俘虏")
	_check(not restored_unit.current_party_id.is_empty(), "领主重新加入部队")
	var party := _context.party_manager.get_party(restored_unit.current_party_id)
	_check(party != null, "领主部队存在")
	if party != null:
		_check(party.leader_unit_id == restored_unit.unit_id, "领主重新成为部队领袖")
		_check(party.leader_noble_id == noble.lord_id, "部队仍由同一贵族指挥")
		_check(party.member_unit_ids.size() >= 2, "领主部队重新补充士兵")
	var leaders: int = 0
	for other: PartyData in _context.party_manager.get_all_parties():
		if other != null and other.leader_noble_id == noble.lord_id:
			leaders += 1
	_check(leaders == 1, "同一领主不会出现重复部队")
	_check(_near_house_settlement(party, noble), "领主出现在家族据点附近")

	# 重复点击接受不会再次支付。
	var gold_after: int = _context.player_profile.gold
	var again: Dictionary = _context.lord_ransom_manager.accept_ransom(ransom_id)
	_check(not bool(again.get("success", false)), "已完成请求不能再次接受")
	_check(_context.player_profile.gold == gold_after, "重复接受不重复支付")

	# 已完成状态写入存档，且读档后不重新生成事件。
	var save := _context.to_save_data()
	_check(save.schema_version == 8, "存档升级到 v8")
	_check(save.ransoms.has(ransom_id), "存档保存赎回记录")
	var restored_context := WorldContext.new()
	restored_context.name = "LordRansomRestoredContext"
	add_child(restored_context)
	_check(restored_context.load_from_save_data(save), "读档恢复赎回记录")
	_check(
		restored_context.lord_ransom_manager.get_lord_state(noble.lord_id) == "ACCEPTED",
		"读档保留已赎回状态"
	)
	_check(
		restored_context.event_center.get_events_of_type("RANSOM").is_empty(),
		"已完成事件读档后不重新出现"
	)
	var restored_in_world := restored_context.unit_manager.get_unit(unit.unit_id)
	_check(
		restored_in_world != null and not restored_in_world.current_party_id.is_empty(),
		"读档后领主仍在世界中"
	)
	restored_context.queue_free()


# ---------------------------------------------------------------------------
# 事件待处理时领主状态变化 → 弹窗立即失效
# ---------------------------------------------------------------------------


func _test_invalid_event_closes_dialog() -> void:
	var lord := _next_lord_unit()
	if lord.is_empty():
		return
	var unit := _context.unit_manager.get_unit(str(lord["unit_id"]))
	var noble := _context.noble_manager.get_noble(str(lord["noble_id"]))
	_used_noble_ids.append(noble.lord_id)
	_sell_lord(unit, noble)
	_advance_to_due(noble.lord_id)
	var events: Array[Dictionary] = _context.event_center.get_events_of_type("RANSOM")
	_check(events.size() == 1, "第二名领主的赎回事件已生成")
	if events.is_empty():
		return
	var event: Dictionary = events[0]
	_map.call("_on_event_feed_selected", str(event.get("event_id", "")))
	var dialog = _map.call("get_event_detail_dialog")
	_check(dialog.visible, "第二名领主弹窗已打开")

	# 模拟领主状态被其他流程改变（例如再次出售/重新关押）。
	unit.sold_to_settlement_id = _other_settlement.settlement_id
	dialog.refresh_if_needed()
	_check(not dialog.visible, "事件失效时弹窗立即关闭")
	_check(
		_context.event_center.get_events_of_type("RANSOM").is_empty(),
		"失效事件从事件框移除"
	)
	var gold_before: int = _context.player_profile.gold
	var result: Dictionary = _context.lord_ransom_manager.accept_ransom(
		str(event.get("ransom_id", ""))
	)
	_check(not bool(result.get("success", false)), "失效事件不可领取")
	_check(_context.player_profile.gold == gold_before, "失效事件不支付赎金")
	_check(
		_context.lord_ransom_manager.get_lord_state(noble.lord_id) == "INVALID",
		"状态变为已失效"
	)


# ---------------------------------------------------------------------------
# 家族不存在 → 终止流程并让领主回到世界
# ---------------------------------------------------------------------------


func _test_missing_house_recovers() -> void:
	var lord := _next_lord_unit()
	if lord.is_empty():
		return
	var unit := _context.unit_manager.get_unit(str(lord["unit_id"]))
	var noble := _context.noble_manager.get_noble(str(lord["noble_id"]))
	var original_house_id: String = noble.house_id
	_used_noble_ids.append(noble.lord_id)
	_sell_lord(unit, noble)
	_advance_to_due(noble.lord_id)
	_check(
		_context.event_center.get_events_of_type("RANSOM").size() == 1,
		"第三名领主的赎回事件已生成"
	)

	noble.house_id = "HOUSE_MISSING"
	_context.event_center.get_events_of_type("RANSOM")
	_check(
		_context.lord_ransom_manager.get_lord_state(noble.lord_id) == "INVALID",
		"家族不存在时流程终止"
	)
	_check(
		_context.event_center.get_events_of_type("RANSOM").is_empty(),
		"异常终止的事件不再显示"
	)
	var recovered := _context.unit_manager.get_unit(unit.unit_id)
	_check(
		recovered != null and recovered.sold_to_settlement_id.is_empty(),
		"异常终止后领主不再停留在已出售状态"
	)
	_check(
		recovered != null and not recovered.current_party_id.is_empty(),
		"异常终止后领主重新进入世界"
	)
	# 恢复测试中被临时破坏的家族引用，后续存档/读档保持合法世界状态。
	noble.house_id = original_house_id


# ---------------------------------------------------------------------------
# 待处理请求存档/读档
# ---------------------------------------------------------------------------


func _test_pending_request_persistence() -> void:
	var lord := _next_lord_unit()
	if lord.is_empty():
		return
	var unit := _context.unit_manager.get_unit(str(lord["unit_id"]))
	var noble := _context.noble_manager.get_noble(str(lord["noble_id"]))
	_used_noble_ids.append(noble.lord_id)
	_sell_lord(unit, noble)
	_advance_to_due(noble.lord_id)
	var events: Array[Dictionary] = _context.event_center.get_events_of_type("RANSOM")
	_check(events.size() == 1, "待处理事件已生成")
	if events.is_empty():
		return
	var event: Dictionary = events[0]
	var ransom_id: String = str(event.get("ransom_id", ""))
	var gold: int = int(event.get("gold", 0))

	var save := _context.to_save_data()
	TimeManager.restore_world_time(save.world_elapsed_seconds, TimeManager.SPEED_NORMAL)
	var restored := WorldContext.new()
	restored.name = "LordRansomPendingRestoredContext"
	add_child(restored)
	_check(restored.load_from_save_data(save), "待处理请求可正常读档")
	var restored_events: Array[Dictionary] = restored.event_center.get_events_of_type("RANSOM")
	_check(restored_events.size() == 1, "待处理事件读档后仍然存在且只有一条")
	if not restored_events.is_empty():
		_check(
			str(restored_events[0].get("ransom_id", "")) == ransom_id,
			"请求使用稳定 ransom_id"
		)
		_check(int(restored_events[0].get("gold", 0)) == gold, "赎金生成后保持不变")
	_check(
		restored.lord_ransom_manager.get_lord_state(noble.lord_id) == "REQUESTED",
		"读档保留已请求状态"
	)
	restored.queue_free()


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------


func _next_lord_unit() -> Dictionary:
	var units: Array[UnitData] = _context.unit_manager.get_all_units()
	units.sort_custom(func(a: UnitData, b: UnitData) -> bool:
		return a.unit_id < b.unit_id
	)
	for unit: UnitData in units:
		if unit == null or not unit.is_noble_lord() or unit.is_player_character:
			continue
		if _used_noble_ids.has(unit.noble_id):
			continue
		var noble := _context.noble_manager.get_noble(unit.noble_id)
		if noble == null or not noble.alive or noble.house_id.is_empty():
			continue
		return {"unit_id": unit.unit_id, "noble_id": noble.lord_id}
	return {}


func _sell_lord(unit: UnitData, noble: NobleData) -> Dictionary:
	var party := _context.party_manager.get_party(noble.party_id)
	if party != null and party.member_unit_ids.has(unit.unit_id):
		_context.party_manager.remove_member(party.party_id, unit.unit_id)
	if not unit.current_party_id.is_empty():
		_context.party_manager.remove_member(unit.current_party_id, unit.unit_id)
	if unit.is_prisoner():
		_context.party_manager.remove_prisoner(
			unit.prisoner_owner_party_id, unit.unit_id
		)
	_check(
		_context.party_manager.add_prisoner(_player.party_id, unit.unit_id),
		"领主成为玩家俘虏"
	)
	return _context.prisoner_trade_manager.sell_prisoners(
		_player.party_id, [unit.unit_id], _town.settlement_id
	)


func _advance_to_due(noble_id: String) -> void:
	var record: Dictionary = _context.lord_ransom_manager.get_record_for_noble(noble_id)
	if record.is_empty():
		return
	TimeManager.world_elapsed_seconds = float(record.get("due_world_seconds", 0.0)) + 1.0
	_context.lord_ransom_manager.tick()


func _near_house_settlement(party: PartyData, noble: NobleData) -> bool:
	if party == null or _context.house_manager == null:
		return false
	var settlements: Array[SettlementData] = (
		_context.house_manager.get_house_settlements(noble.house_id)
	)
	if settlements.is_empty():
		return false
	var expected: SettlementData = settlements[0]
	for settlement: SettlementData in settlements:
		if settlement.owner_noble_id == noble.lord_id:
			expected = settlement
			break
	return party.world_position.distance_to(expected.world_position) <= 120.0


func _first_feed_button(feed) -> Button:
	var list: Node = feed.find_child("EventFeedList", true, false)
	if list == null:
		return null
	for child: Node in list.get_children():
		if child is Button:
			return child as Button
	return null


func _find_settlement(display_name: String) -> SettlementData:
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement != null and settlement.display_name == display_name:
			return settlement
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[ransom] OK: %s" % message)
	else:
		_failed = true
		push_error("[ransom] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_map):
		_map.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
