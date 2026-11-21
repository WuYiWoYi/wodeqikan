extends Node
## 战斗撤退 UI 与结算测试：撤退按钮、结果面板、存活写回与无奖励。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/battle_retreat_test.tscn

var _failed: bool = false
var _context: WorldContext = null
var _scene: BattleScene = null
var _session: BattleSession = null
var _player: PartyData = null
var _enemy: PartyData = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[retreat] 测试失败")
		get_tree().quit(1)
	else:
		print("[retreat] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)

	_context = WorldContext.new()
	_context.name = "BattleRetreatContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	_player = _context.get_player_party()
	_enemy = _find_party_by_name(WorldInitializer.BANDIT_PARTY_NAME)
	_check(_player != null and _enemy != null, "玩家与敌人部队存在")
	if _player == null or _enemy == null:
		return

	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id
	_session = _context.battle_manager.start_battle(
		[_player.party_id], [_enemy.party_id], _enemy.world_position
	)
	_check(_session != null, "创建撤退测试战斗")
	if _session == null:
		return

	var packed := load("res://Scenes/Battle/battle.tscn") as PackedScene
	_scene = packed.instantiate() as BattleScene
	add_child(_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame

	var retreat_button := _scene.find_child("BattleRetreatButton", true, false) as Button
	_check(retreat_button != null, "战斗场景包含撤退按钮")
	if retreat_button == null:
		return
	retreat_button.pressed.emit()
	await get_tree().process_frame

	var result_panel := _scene.find_child("BattleResultPanel", true, false) as PanelContainer
	var result_label := _scene.find_child("BattleResultLabel", true, false) as Label
	_check(result_panel != null and result_panel.visible, "撤退后显示结果面板")
	_check(result_label != null and result_label.text == "已撤退", "结果显示已撤退")
	_check(_session.retreated_side_indices.has(_scene.get_player_side()), "记录撤退侧")
	_check(_session.winning_side_index == -1, "撤退没有获胜侧")

	var exp_label := _scene.find_child("BattleResultExpLabel", true, false) as Label
	var reward_label := _scene.find_child("BattleResultRewardLabel", true, false) as Label
	_check(exp_label != null and exp_label.text.contains("经验"), "撤退结果显示经验")
	_check(
		reward_label != null and reward_label.text.contains("金币"),
		"撤退结果显示奖励信息"
	)

	var gold_before := _context.player_profile.gold
	_check(
		_context.battle_manager.finish_battle(
			_session.battle_id, BattleSession.BattleResult.RETREATED
		),
		"撤退结算成功"
	)
	var result := _session.final_result
	_check(result != null, "撤退生成统一结果")
	if result != null:
		_check(result.end_reason == BattleResultData.EndReason.RETREAT, "结束原因为撤退")
		_check(result.get_party_casualties(_player.party_id) == 0, "撤退不产生阵亡")
		_check(
			result.get_party_survivors(_player.party_id)
				== WorldInitializer.PLAYER_TOTAL_MEMBER_COUNT,
			"撤退保留全部士兵"
		)
		_check(result.reward_gold == 0, "撤退无金币奖励")
	_check(_context.player_profile.gold == gold_before, "撤退不改变玩家金币")
	_check(_context.battle_manager.current_battle == null, "撤退结算后清理会话")


func _find_party_by_name(party_name: String) -> PartyData:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[retreat] OK: %s" % message)
	else:
		_failed = true
		push_error("[retreat] FAIL: %s" % message)


func _cleanup() -> void:
	if _context != null and _context.battle_manager.current_battle != null:
		_context.battle_manager.abort_battle(
			_context.battle_manager.current_battle.battle_id
		)
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_scene):
		_scene.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
