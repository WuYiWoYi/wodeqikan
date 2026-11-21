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
	_check(_context.battle_manager.try_join_battle(_guard.party_id), "治安队加入已有战斗")
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
	if _context != null and _context.battle_manager.current_battle != null:
		_context.battle_manager.finish_battle(
			_context.battle_manager.current_battle.battle_id,
			BattleSession.BattleResult.ABORTED
		)
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_map):
		_map.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
