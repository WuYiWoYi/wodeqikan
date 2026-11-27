extends Node
## 玩家主动追击同向移动敌军的大地图接触测试。
## 覆盖：持续追击、进入遭遇距离、双方停止、暂停与面板、撤退、拒绝锁、再次触发与进入战斗。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/player_pursuit_encounter_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"

var _failed: bool = false
var _context: WorldContext = null
var _map: Node = null
var _player: PartyData = null
var _bandit: PartyData = null
var _militia: UnitConfig = null


func _ready() -> void:
	get_tree().current_scene = null
	await get_tree().process_frame
	await _run()
	_cleanup()
	if _failed:
		push_error("[pursuit] 测试失败")
		get_tree().quit(1)
	else:
		print("[pursuit] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.clear_pauses()
	TimeManager.stop_session()
	_check(GameManager.start_new_game(), "新游戏启动")
	await get_tree().process_frame
	await get_tree().process_frame

	_context = GameManager.world_context
	_map = get_tree().current_scene
	_player = _context.get_player_party() if _context != null else null
	_bandit = _find_party_by_name(WorldInitializer.BANDIT_PARTY_NAME)
	_check(_player != null and _bandit != null and _map != null, "玩家、强盗与大地图存在")
	if _player == null or _bandit == null or _map == null:
		return

	_isolate_parties()
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)
	_player.world_position = Vector2(900.0, 1200.0)
	_player.target_position = _player.world_position
	_player.movement_state = PartyData.MovementState.IDLE
	_player.current_order = PartyData.OrderType.NONE
	_bandit.world_position = Vector2(1080.0, 1200.0)
	_bandit.target_position = Vector2(2500.0, 1200.0)
	_bandit.movement_state = PartyData.MovementState.MOVING
	_bandit.current_order = PartyData.OrderType.MOVE
	_bandit.attack_intent = false

	_check(_map.call("request_party_command", _bandit.party_id), "点击移动中的敌军开始追击")
	_check(_player.focus_party_id == _bandit.party_id, "记录主动追击焦点")
	_check(_player.current_order == PartyData.OrderType.FOLLOW_PARTY, "玩家进入持续跟随指令")

	# 0.08 倍率下玩家 36 px/s、强盗 20 px/s，180 像素初始间距约需 12 个 tick。
	var triggered: bool = false
	for i: int in range(700):
		_context.world_map_manager.update_party_movement(0.1)
		if _context.encounter_manager.update_encounters():
			triggered = true
			break
		if _player.world_position.distance_to(_bandit.world_position) > 400.0:
			break
	_check(triggered, "同向追击进入有效距离后触发一次接触")
	_check(
		_player.world_position.distance_to(_bandit.world_position) <= 50.0,
		"接触发生在有效遭遇距离内"
	)
	_check(
		_player.movement_state == PartyData.MovementState.IDLE
		and _bandit.movement_state == PartyData.MovementState.IDLE,
		"接触成立后双方立即停止移动"
	)
	_check(
		_player.target_position == _player.world_position
		and _bandit.target_position == _bandit.world_position,
		"接触后清除旧移动目标，避免位置回弹"
	)
	_check(
		_player.current_target_id.is_empty()
		and _bandit.current_target_id.is_empty()
		and _player.focus_party_id.is_empty(),
		"接触后清除追击目标与焦点"
	)
	_check(not _bandit.attack_intent, "接触后清除攻击意图")

	var player_stop := _player.world_position
	var bandit_stop := _bandit.world_position
	_context.world_map_manager.update_party_movement(0.5)
	_check(
		_player.world_position == player_stop
		and _bandit.world_position == bandit_stop,
		"接触后继续移动 tick 不会推挤或回弹"
	)

	await get_tree().process_frame
	var panel := _find_panel("PlayerEncounterPanel")
	_check(panel != null and panel.visible, "弹出战斗选择界面")
	_check(
		is_zero_approx(TimeManager.get_effective_world_scale()),
		"遭遇界面暂停世界时间"
	)
	_check(
		is_equal_approx(
			TimeManager.get_base_world_speed(), TimeManager.SPEED_NORMAL
		),
		"遭遇界面不改变基础倍率"
	)
	if panel != null and panel.visible:
		var retreat := panel.find_child("EncounterLeaveButton", true, false) as Button
		_check(retreat != null, "提供撤退选项")
		if retreat != null:
			retreat.pressed.emit()
	await get_tree().process_frame
	_check(panel != null and not panel.visible, "撤退后关闭遭遇界面")
	_check(
		_context.encounter_manager.get_pending_player_encounter().is_empty(),
		"撤退后清理待处理遭遇"
	)
	_check(
		is_equal_approx(
			TimeManager.get_effective_world_scale(), TimeManager.SPEED_NORMAL
		),
		"撤退后恢复基础倍率"
	)
	_check(
		_player.movement_state == PartyData.MovementState.IDLE
		and _bandit.movement_state == PartyData.MovementState.IDLE,
		"撤退后不会留下永久移动中的部队"
	)

	# 阶段 10 补充：地图点击、目标变向、目标参战、战后冷却与 AI 恢复。
	_militia = load(MILITIA_PATH) as UnitConfig
	_check(_militia != null, "加载民兵配置")
	if _militia == null:
		return
	_test_map_move_clears_focus()
	await _test_pursuit_survives_direction_change()
	await _test_focus_survives_target_battle()
	await _test_pursuit_waits_for_post_battle_cooldown()
	await _test_ai_repursues_player_after_cooldown()

	# 仍在拒绝范围内再次追击：不重复弹出同一场遭遇。
	_player.focus_party_id = _bandit.party_id
	_check(
		not _context.encounter_manager.update_encounters(),
		"撤退后原地再次追击不会重复触发"
	)

	# 离开拒绝范围后重新接近可以再次触发。
	_player.world_position = _bandit.world_position + Vector2(140.0, 0.0)
	_context.encounter_manager.update_encounters()
	_check(
		_context.encounter_manager.get_pending_player_encounter().is_empty(),
		"离开拒绝范围只清除锁存，不立即触发"
	)
	_player.world_position = _bandit.world_position + Vector2(45.0, 0.0)
	_player.focus_party_id = _bandit.party_id
	_check(
		_context.encounter_manager.update_encounters(),
		"离开范围后再次接近可以重新触发"
	)
	await get_tree().process_frame
	panel = _find_panel("PlayerEncounterPanel")
	if panel == null or not panel.visible:
		return
	var fight := panel.find_child("EncounterFightButton", true, false) as Button
	_check(fight != null, "重新触发后存在战斗按钮")
	if fight != null:
		fight.pressed.emit()
	for i: int in range(8):
		await get_tree().process_frame

	_check(
		get_tree().current_scene != null and get_tree().current_scene.name == "Battle",
		"选择战斗后进入战斗场景"
	)
	var session := _context.battle_manager.current_battle
	_check(session != null, "创建或加入唯一战斗会话")
	if session != null:
		_check(
			session.get_side_of_party(_player.party_id)
			!= session.get_side_of_party(_bandit.party_id),
			"玩家与追击目标处于不同战斗侧"
		)
		_context.battle_manager.abort_battle(session.battle_id)


# ---------------------------------------------------------------------------
# 阶段 10：追击在目标变向、参战与战后冷却期间的稳定性
# ---------------------------------------------------------------------------


## 普通地图移动指令必须清除主动追击焦点。
func _test_map_move_clears_focus() -> void:
	_reset_pursuit_parties()
	_player.focus_party_id = _bandit.party_id
	_check(
		bool(_map.call("request_player_move", Vector2(1500.0, 1800.0))),
		"地图点击下达普通移动"
	)
	_check(_player.focus_party_id.is_empty(), "普通地图移动清除追击焦点")
	_check(
		_player.current_order != PartyData.OrderType.FOLLOW_PARTY,
		"普通地图移动结束跟随指令"
	)
	_context.world_map_manager.stop_party(_player.party_id)


## 目标中途改变方向后，玩家跟随目标仍读取其最新位置并最终触发遭遇。
func _test_pursuit_survives_direction_change() -> void:
	_reset_pursuit_parties()
	_clear_decline_latch()
	_player.world_position = Vector2(900.0, 1200.0)
	_bandit.world_position = Vector2(1080.0, 1200.0)
	_bandit.target_position = Vector2(1600.0, 1200.0)
	_bandit.movement_state = PartyData.MovementState.MOVING
	_bandit.current_order = PartyData.OrderType.MOVE
	_check(
		bool(_map.call("request_party_command", _bandit.party_id)),
		"变向测试开始追击"
	)
	for i: int in range(10):
		_context.world_map_manager.update_party_movement(0.1)
	# 目标转向后，跟随目标必须更新到新位置，而不是沿用旧方向。
	_bandit.target_position = Vector2(1200.0, 1600.0)
	_bandit.movement_state = PartyData.MovementState.MOVING
	_context.world_map_manager.update_party_movement(0.6)
	_check(
		_player.focus_party_id == _bandit.party_id,
		"目标变向后焦点保持"
	)
	_check(
		_player.target_position.distance_to(_bandit.world_position) <= 60.0,
		"目标变向后跟随坐标同步到新位置"
	)
	_player.world_position = _bandit.world_position + Vector2(40.0, 0.0)
	_context.world_map_manager.stop_party(_bandit.party_id)
	_check(
		_context.encounter_manager.update_encounters(),
		"目标变向后仍能正常触发遭遇"
	)
	await _dismiss_encounter_panel()
	_clear_decline_latch()


## 目标进入其他战斗时保留追击关系并原地等待，战斗结束后恢复跟随。
func _test_focus_survives_target_battle() -> void:
	_reset_pursuit_parties()
	var old_fraction: float = _context.battle_manager.offscreen_config.base_hourly_casualty_fraction
	var old_variance: float = _context.battle_manager.offscreen_config.casualty_variance
	_context.battle_manager.offscreen_config.base_hourly_casualty_fraction = 0.0
	_context.battle_manager.offscreen_config.casualty_variance = 0.0

	_player.world_position = Vector2(900.0, 1200.0)
	_bandit.world_position = Vector2(1080.0, 1200.0)
	_check(
		bool(_map.call("request_party_command", _bandit.party_id)),
		"目标参战前开始追击"
	)
	var guard := _make_temp_party(
		FactionManager.GUARD_FACTION_ID, Vector2(1100.0, 1200.0), "目标战斗对手"
	)
	var session := _context.battle_manager.start_battle(
		[_bandit.party_id], [guard.party_id], _bandit.world_position, true
	)
	_check(session != null, "目标进入另一场离屏战斗")
	if session != null:
		_map.call("_update_focus_state")
		_check(
			_player.focus_party_id == _bandit.party_id,
			"目标进入战斗后焦点不被清除"
		)
		_context.world_map_manager.update_party_movement(0.5)
		_check(
			_player.current_order == PartyData.OrderType.FOLLOW_PARTY
				and _player.movement_state == PartyData.MovementState.IDLE,
			"目标战斗中玩家保持跟随指令并原地等待"
		)
		# 收尾阶段靠近目标，验证焦点在战斗结束后仍保留。
		_player.world_position = _bandit.world_position + Vector2(40.0, 0.0)

		_context.battle_manager.resolve_current_battle_now()
		_check(
			_context.battle_manager.get_battle(session.battle_id) == null,
			"目标所在战斗已结束"
		)
		_map.call("_update_focus_state")
		_check(
			_player.focus_party_id == _bandit.party_id,
			"目标战斗结束后焦点仍然保留"
		)
		_context.world_map_manager.update_party_movement(0.5)
		_check(
			_player.current_order == PartyData.OrderType.FOLLOW_PARTY
				and _player.movement_state == PartyData.MovementState.MOVING,
			"目标战斗结束后自动恢复追击移动"
		)

	_destroy_temp_party(guard)
	_context.battle_manager.offscreen_config.base_hourly_casualty_fraction = old_fraction
	_context.battle_manager.offscreen_config.casualty_variance = old_variance
	_reset_pursuit_parties()


## 目标刚结束战斗处于冷却时，玩家追上后等待；冷却结束必须可靠触发，而不是永久卡住。
func _test_pursuit_waits_for_post_battle_cooldown() -> void:
	_reset_pursuit_parties()
	_clear_decline_latch()
	TimeManager.world_elapsed_seconds = 0.0
	var old_fraction: float = _context.battle_manager.offscreen_config.base_hourly_casualty_fraction
	var old_variance: float = _context.battle_manager.offscreen_config.casualty_variance
	_context.battle_manager.offscreen_config.base_hourly_casualty_fraction = 0.0
	_context.battle_manager.offscreen_config.casualty_variance = 0.0

	_bandit.world_position = Vector2(1200.0, 1200.0)
	var caravan := _make_temp_party(
		FactionManager.MERCHANT_FACTION_ID,
		Vector2(1230.0, 1200.0),
		"被击败的商队"
	)
	var session := _context.battle_manager.start_battle(
		[_bandit.party_id], [caravan.party_id], Vector2(1215.0, 1200.0), true
	)
	_check(session != null, "强盗击败商队的离屏战斗")
	if session == null:
		_destroy_temp_party(caravan)
		return
	_context.battle_manager.resolve_current_battle_now()
	_check(
		_bandit.engagement_cooldown_until > TimeManager.world_elapsed_seconds,
		"强盗战后进入冷却"
	)
	# 商队退场，避免干扰追击。
	caravan.world_position = Vector2(2500.0, 1800.0)
	caravan.target_position = caravan.world_position
	caravan.movement_state = PartyData.MovementState.IDLE

	_player.world_position = Vector2(900.0, 1200.0)
	_bandit.world_position = Vector2(1200.0, 1200.0)
	_bandit.target_position = _bandit.world_position
	_bandit.movement_state = PartyData.MovementState.IDLE
	_check(
		bool(_map.call("request_party_command", _bandit.party_id)),
		"商队战败后玩家继续追击强盗"
	)

	# 强盗原地等待，300 像素间距按玩家 12 px/s 约需 250 个 tick。
	var triggered: bool = false
	for i: int in range(500):
		_context.world_map_manager.update_party_movement(0.1)
		TimeManager.world_elapsed_seconds += 0.2
		if _context.encounter_manager.update_encounters():
			triggered = true
			break
	_check(triggered, "冷却结束后玩家追击可靠触发遭遇")
	_check(
		TimeManager.world_elapsed_seconds >= 30.0 - 0.001,
		"遭遇发生在战后冷却结束之后"
	)
	_check(
		_player.world_position.distance_to(_bandit.world_position)
			<= EncounterManager.AI_ENCOUNTER_RADIUS,
		"等待期间玩家保持在遭遇距离内"
	)
	await _dismiss_encounter_panel()
	_clear_decline_latch()
	_destroy_temp_party(caravan)
	_context.battle_manager.offscreen_config.base_hourly_casualty_fraction = old_fraction
	_context.battle_manager.offscreen_config.casualty_variance = old_variance
	_reset_pursuit_parties()


## 战后冷却结束，AI 强盗重新把玩家视为追击目标并主动拦截。
func _test_ai_repursues_player_after_cooldown() -> void:
	_reset_pursuit_parties()
	_clear_decline_latch()
	TimeManager.world_elapsed_seconds = 0.0
	_player.world_position = Vector2(1200.0, 1200.0)
	_bandit.world_position = Vector2(1600.0, 1200.0)
	_bandit.sight_range = 500.0
	_bandit.ai_type = PartyData.PartyAIType.BANDIT
	_bandit.engagement_cooldown_until = 10.0

	_context.ai_manager.tick(1.0)
	_check(
		_bandit.current_target_id.is_empty() and not _bandit.attack_intent,
		"冷却中强盗不追击玩家"
	)

	TimeManager.world_elapsed_seconds = 11.0
	_context.ai_manager.tick(1.0)
	_check(
		_bandit.current_target_id == _player.party_id and _bandit.attack_intent,
		"冷却结束后强盗重新锁定玩家"
	)
	_bandit.world_position = _player.world_position + Vector2(40.0, 0.0)
	_check(
		_context.encounter_manager.update_encounters(),
		"恢复追击后主动拦截玩家"
	)
	await _dismiss_encounter_panel()
	_clear_decline_latch()
	_bandit.ai_type = PartyData.PartyAIType.NONE
	_reset_pursuit_parties()


func _reset_pursuit_parties() -> void:
	_context.encounter_manager.clear_pending_player_encounter()
	for party: PartyData in [_player, _bandit]:
		party.focus_party_id = ""
		party.attack_intent = false
		party.current_target_id = ""
		party.current_order = PartyData.OrderType.NONE
		party.target_position = party.world_position
		party.movement_state = PartyData.MovementState.IDLE
		party.battle_state = PartyData.BattleState.AVAILABLE
	_context.battle_manager.player_party_id = _context.player_party_id


func _clear_decline_latch() -> void:
	# 拉开到拒绝锁存退出距离之外，让后续场景可以重新触发同一对手。
	_player.world_position = _bandit.world_position + Vector2(300.0, 0.0)
	_context.encounter_manager.update_encounters()


func _dismiss_encounter_panel() -> void:
	await get_tree().process_frame
	var panel := _find_panel("PlayerEncounterPanel")
	if panel != null and panel.visible:
		# 测试清理直接走取消入口；AI 主动拦截不允许撤退，不能依赖撤退按钮。
		_map.call("cancel_player_encounter")
		await get_tree().process_frame
	else:
		_context.encounter_manager.clear_pending_player_encounter()


func _make_temp_party(
	faction_id: String, position: Vector2, party_name: String
) -> PartyData:
	var party := _context.party_manager.create_party(faction_id, position, party_name)
	party.target_position = position
	party.movement_state = PartyData.MovementState.IDLE
	party.sight_range = 250.0
	party.movement_speed = 100.0
	for i: int in range(3):
		var unit := _context.unit_manager.create_unit(_militia, faction_id)
		_context.party_manager.add_member(party.party_id, unit.unit_id)
	return party


func _destroy_temp_party(party: PartyData) -> void:
	if party == null:
		return
	for unit_id: String in party.member_unit_ids.duplicate():
		_context.party_manager.remove_member(party.party_id, unit_id)
		_context.unit_manager.remove_unit(unit_id)
	_context.party_manager.remove_party(party.party_id)


func _isolate_parties() -> void:
	for party: PartyData in _context.party_manager.get_all_parties():
		var is_target: bool = party.party_id == _player.party_id \
			or party.party_id == _bandit.party_id
		party.ai_type = PartyData.PartyAIType.NONE
		party.attack_intent = false
		party.focus_party_id = ""
		party.current_target_id = ""
		party.current_order = PartyData.OrderType.NONE
		party.movement_state = PartyData.MovementState.IDLE
		if not is_target:
			party.world_position = Vector2(2700.0, 1800.0)
			party.target_position = party.world_position


func _find_party_by_name(party_name: String) -> PartyData:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _find_panel(node_name: String) -> PanelContainer:
	if get_tree().current_scene == null:
		return null
	return get_tree().current_scene.find_child(node_name, true, false) as PanelContainer


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[pursuit] OK: %s" % message)
	else:
		_failed = true
		push_error("[pursuit] FAIL: %s" % message)


func _cleanup() -> void:
	if _context != null and _context.battle_manager.current_battle != null:
		_context.battle_manager.abort_battle(
			_context.battle_manager.current_battle.battle_id
		)
	GameManager.enter_main_menu()
	TimeManager.stop_session()
	TimeManager.clear_pauses()
