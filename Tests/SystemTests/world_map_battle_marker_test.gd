extends Node
## 大地图多方战斗 UI 测试：单战斗标记、参战图标隐藏、按战斗侧分组、
## 小时伤亡实时更新、新部队加入与战斗结束后的图标恢复。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/world_map_battle_marker_test.tscn

var _failed: bool = false
var _context: WorldContext = null
var _map: Node = null
var _player: PartyData = null
var _merchant: PartyData = null
var _bandit: PartyData = null
var _guard: PartyData = null
var _battle_position := Vector2(1430.0, 1350.0)


func _ready() -> void:
	get_tree().current_scene = null
	await get_tree().process_frame
	await _run()
	_cleanup()
	if _failed:
		push_error("[battlemarker] 测试失败")
		get_tree().quit(1)
	else:
		print("[battlemarker] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)

	_context = WorldContext.new()
	_context.name = "BattleMarkerTestContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return
	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id
	_player = _context.get_player_party()
	_merchant = _find_party(WorldInitializer.TEST_ENEMY_PARTY_NAME)
	_bandit = _find_party(WorldInitializer.BANDIT_PARTY_NAME)
	_guard = _find_party(WorldInitializer.GUARD_PARTY_NAME)
	_check(
		_player != null and _merchant != null and _bandit != null and _guard != null,
		"找到玩家与三方 NPC"
	)
	if _player == null or _merchant == null or _bandit == null or _guard == null:
		return

	for party: PartyData in _context.party_manager.get_all_parties():
		party.ai_type = PartyData.PartyAIType.NONE
		party.attack_intent = false
		party.focus_party_id = ""
	_player.world_position = _battle_position + Vector2(20.0, 20.0)
	_player.target_position = _player.world_position
	_merchant.world_position = _battle_position
	_bandit.world_position = _battle_position + Vector2(60.0, 0.0)
	_guard.world_position = Vector2(2700.0, 1800.0)

	var packed := load("res://Scenes/WorldMap/world_map.tscn") as PackedScene
	_map = packed.instantiate()
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame

	var session := _context.battle_manager.start_battle(
		[_merchant.party_id], [_bandit.party_id], _battle_position, true
	)
	_check(session != null and session.offscreen, "创建 AI 对 AI 离屏战斗")
	if session == null:
		return
	_context.battle_manager.offscreen_config.settlement_interval_world_seconds = 1.0
	_context.battle_manager.offscreen_config.base_hourly_casualty_fraction = 0.5
	_context.battle_manager.offscreen_config.casualty_variance = 0.0
	await _wait_frames(6)
	# 战斗开始前玩家与商队距离过近，可能已经打开普通部队对话；先关闭它。
	var party_panel := _map.get("_party_panel") as Control
	if party_panel != null and party_panel.visible:
		_map.call("_on_party_leave_pressed")
		await get_tree().process_frame

	var marker := _map.call("get_battle_marker") as BattleMarker
	_check(marker != null, "大地图生成唯一战斗标记")
	_check(marker != null and marker.battle_id == session.battle_id, "战斗标记对应当前会话")
	_check(
		_count_markers() == 1,
		"同一场战斗只显示一个战斗标记"
	)
	_check(
		not _icon(_merchant).visible and not _icon(_bandit).visible,
		"参战部队的原图标暂时隐藏"
	)
	_check(
		_icon(_guard).visible and _icon(_player).visible,
		"未参战部队图标保持显示"
	)
	var summary: String = str(_map.call("get_battle_summary_text"))
	_check(summary.contains(_merchant.party_name), "战斗汇总显示商队")
	_check(summary.contains(_bandit.party_name), "战斗汇总显示强盗")
	_check(summary.contains("民兵（3）"), "战斗汇总按兵种统计人数")
	_check(summary.contains("职业步兵（2）"), "战斗汇总区分不同兵种")
	_check(marker != null and marker.get_count_text() == "10", "战斗标记显示总存活人数")
	_check(
		_map.call("is_battle_summary_visible") == true,
		"战斗汇总面板显示在战斗标记附近"
	)

	var alive_before: int = session.get_all_unit_ids().size()
	_context.battle_manager.tick(1.0)
	await _wait_frames(2)
	_check(session.offscreen_settlements_done == 1, "离屏战斗完成一次小时结算")
	var marker_count_after: int = 0
	if marker != null:
		marker_count_after = int(marker.get_count_text())
	_check(marker_count_after < alive_before, "战斗标记人数随伤亡更新")
	_check(
		int(session.offscreen_settlements_done) == 1,
		"UI 不创建额外战斗或重复结算"
	)
	var summary_after: String = str(_map.call("get_battle_summary_text"))
	_check(summary_after != summary, "战斗汇总文本随伤亡刷新")

	# 治安队加入商队一方：新部队自动进入同侧分组。
	_guard.world_position = _battle_position + Vector2(20.0, 0.0)
	_check(
		_context.battle_manager.try_join_battle(_guard.party_id, session.battle_id),
		"治安队加入已有战斗"
	)
	await _wait_frames(2)
	summary = str(_map.call("get_battle_summary_text"))
	_check(summary.contains(_guard.party_name), "新参战部队自动加入汇总")
	_check(not _icon(_guard).visible, "新参战部队图标被隐藏")
	_check(_count_markers() == 1, "新部队加入不会产生第二个战斗标记")

	_context.battle_manager.finish_battle(
		session.battle_id, BattleSession.BattleResult.ABORTED
	)
	await _wait_frames(4)
	_check(_map.call("get_battle_marker") == null, "战斗结束后移除战斗标记")
	_check(_map.call("get_battle_summary_text") == "", "战斗结束后清空汇总")
	_check(
		_icon(_merchant).visible and _icon(_bandit).visible and _icon(_guard).visible,
		"战斗结束后恢复参战部队普通图标"
	)

	# 三方战斗：每个 side_index 一列，第三列自动出现。
	var three_sides := _context.battle_manager.start_battle_by_sides(
		[[_player.party_id], [_merchant.party_id], [_bandit.party_id]],
		_battle_position,
		true
	)
	_check(three_sides != null, "创建三方离屏战斗")
	if three_sides != null:
		await _wait_frames(3)
		_check(
			int(_map.call("get_battle_summary_column_count")) == 3,
			"三方战斗按 side_index 生成三列"
		)
		var side_indices: Array = _map.call("get_battle_summary_side_indices")
		_check(side_indices == [0, 1, 2], "汇总列顺序对应战斗侧顺序")
		_context.battle_manager.finish_battle(
			three_sides.battle_id, BattleSession.BattleResult.ABORTED
		)
		await _wait_frames(3)
		_check(
			int(_map.call("get_battle_summary_column_count")) == 0,
			"战斗结束后清理所有汇总列"
		)
		_check(_map.call("get_battle_summary_text") == "", "三方战斗结束后清空汇总")

	await _test_parallel_battle_markers()


## 两场同时进行的离屏战斗各自拥有独立标记与图标隐藏范围。
func _test_parallel_battle_markers() -> void:
	_merchant.world_position = _battle_position
	_bandit.world_position = _battle_position + Vector2(40.0, 0.0)
	var second_position := Vector2(2400.0, 700.0)
	# 使用已在大地图上有图标的部队，便于验证两场战斗各自隐藏参战图标。
	var east_bandits := _find_party(WorldInitializer.EAST_BANDIT_PARTY_NAME)
	_check(east_bandits != null and _icon(east_bandits) != null, "找到第二场战斗部队图标")
	if east_bandits == null:
		return
	_guard.world_position = second_position
	east_bandits.world_position = second_position + Vector2(40.0, 0.0)
	var first := _context.battle_manager.start_battle(
		[_merchant.party_id], [_bandit.party_id], _battle_position, true
	)
	var second := _context.battle_manager.start_battle(
		[_guard.party_id], [east_bandits.party_id], second_position, true
	)
	_check(first != null and second != null, "同时创建两场离屏战斗")
	if first == null or second == null:
		return
	await _wait_frames(4)

	_check(_count_markers() == 2, "大地图同时显示两个战斗标记")
	var marker_first := _map.call(
		"get_battle_marker_for", first.battle_id
	) as BattleMarker
	var marker_second := _map.call(
		"get_battle_marker_for", second.battle_id
	) as BattleMarker
	_check(
		marker_first != null and marker_second != null
		and marker_first != marker_second,
		"两个战斗标记分别对应各自会话"
	)
	_check(
		marker_first != null and marker_first.battle_id == first.battle_id
		and marker_second != null and marker_second.battle_id == second.battle_id,
		"战斗标记 ID 与会话一致"
	)
	_check(
		not _icon(_merchant).visible and not _icon(_bandit).visible
		and not _icon(_guard).visible and not _icon(east_bandits).visible,
		"两场战斗的参战部队图标全部隐藏"
	)
	_check(_icon(_player).visible, "未参战部队图标保持显示")
	_check(
		marker_first != null
		and marker_first.get_count_text() == str(_session_alive(first))
		and marker_second != null
		and marker_second.get_count_text() == str(_session_alive(second)),
		"每个标记显示本场战斗自己的存活人数"
	)

	_context.battle_manager.finish_battle(
		first.battle_id, BattleSession.BattleResult.ABORTED
	)
	await _wait_frames(4)
	_check(_count_markers() == 1, "结束第一场后只删除对应标记")
	_check(
		_map.call("get_battle_marker_for", first.battle_id) == null
		and _map.call("get_battle_marker_for", second.battle_id) != null,
		"第二场标记仍然存在"
	)
	_check(
		_icon(_merchant).visible and _icon(_bandit).visible,
		"第一场存活部队恢复普通图标"
	)
	_check(
		not _icon(_guard).visible and not _icon(east_bandits).visible,
		"第二场参战部队图标仍然隐藏"
	)

	_context.battle_manager.finish_battle(
		second.battle_id, BattleSession.BattleResult.ABORTED
	)
	await _wait_frames(4)
	_check(_count_markers() == 0, "第二场结束后清除全部标记")
	_check(
		_icon(_guard).visible and _icon(east_bandits).visible,
		"第二场结束后恢复其部队图标"
	)


func _session_alive(session: BattleSession) -> int:
	if session == null:
		return 0
	var count: int = 0
	for unit_id: String in session.get_all_unit_ids():
		var state := session.get_unit_state(unit_id)
		if state != null and state.alive and state.battle_hp > 0:
			count += 1
	return count


func _wait_frames(count: int) -> void:
	for i: int in range(count):
		await get_tree().process_frame


func _icon(party: PartyData) -> PartyIcon:
	if party == null:
		return null
	return _map.find_child("PartyIcon_%s" % party.party_id, true, false) as PartyIcon


func _count_markers() -> int:
	return _map.find_children("BattleMarker_*", "Node2D", true, false).size()


func _find_party(party_name: String) -> PartyData:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[battlemarker] OK: %s" % message)
	else:
		_failed = true
		push_error("[battlemarker] FAIL: %s" % message)


func _cleanup() -> void:
	if _context != null:
		for session: BattleSession in _context.battle_manager.get_active_battles():
			_context.battle_manager.finish_battle(
				session.battle_id, BattleSession.BattleResult.ABORTED
			)
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_map):
		_map.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
