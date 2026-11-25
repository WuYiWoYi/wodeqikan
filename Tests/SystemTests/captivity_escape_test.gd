extends Node
## 玩家被俘、俘虏恢复、逃脱、保护期与存档测试。
##
## 覆盖：
## - 玩家战败后角色成为胜利方真实俘虏，原部队失去控制但身份锚点保留；
## - 俘虏按配置独立恢复 HP（不占用伤兵治疗名额）；
## - 满血后按间隔/概率逃脱，重建只含玩家角色的部队并落在押送部队附近；
## - 逃脱后的配置保护期阻止 AI 主动遭遇；
## - 被俘/计时/保护期随存档恢复；
## - 顶栏玩家 HP 与左侧被俘面板读取真实 UnitData。
##
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/captivity_escape_test.tscn

var _failed: bool = false
var _context: WorldContext = null
var _map: Node = null
var _player: PartyData = null
var _captor: PartyData = null
var _hero: UnitData = null
var _hero_equipment: Dictionary = {}
var _hero_max_hp: int = 0


func _ready() -> void:
	await _run_async()
	_cleanup()
	if _failed:
		push_error("[captivity] 测试失败")
		get_tree().quit(1)
	else:
		print("[captivity] 全部通过")
		get_tree().quit(0)


func _run_async() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	_setup_world()
	if _context == null:
		return
	_capture_player()
	if not _context.captivity_manager.is_player_captive():
		return
	_initialize_capture_timers()
	await _test_captive_ui()
	await _test_prisoner_healing()
	var save := _save_while_captive()
	_free_map()
	var restored := _load_restored(save)
	if restored == null:
		return
	_test_escape(restored)
	_test_escape_protection(restored)
	print("[captivity] 完成")


func _setup_world() -> void:
	_context = WorldContext.new()
	_context.name = "CaptivityTestContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return

	# 让全部战败成员都成为伤兵/俘虏，便于验证逃脱后不会自动恢复旧士兵。
	var wounded := WoundedConfig.new()
	wounded.enabled = true
	var guaranteed: Array[float] = [1.0, 1.0, 1.0]
	wounded.tier_wounded_chances = guaranteed
	_context.battle_manager.set_wounded_config(wounded)

	var config := CaptivityConfig.new()
	config.prisoner_healing_per_hour = 10000
	config.escape_check_interval_hours = 1.0
	config.escape_chance = 0.0
	config.escape_protection_hours = 2.0
	_context.captivity_manager.set_config(config)

	_player = _context.get_player_party()
	_captor = _find_party(WorldInitializer.BANDIT_PARTY_NAME)
	_hero = _context.get_player_unit()
	_check(
		_player != null and _captor != null and _hero != null,
		"玩家部队、押送候选部队与玩家角色存在"
	)
	if _player == null or _captor == null or _hero == null:
		return
	_hero_equipment = _hero.equipment.duplicate(true)
	_hero_max_hp = _hero.max_hp
	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id


func _capture_player() -> void:
	var session := _context.battle_manager.start_battle(
		[_player.party_id], [_captor.party_id], _captor.world_position
	)
	_check(session != null, "创建玩家战败测试战斗")
	if session == null:
		return
	for unit_id: String in session.attacker_unit_ids:
		var state := session.get_unit_state(unit_id)
		state.battle_hp = 0
		state.alive = false
	var player_member_count: int = _player.member_unit_ids.size()
	var captor_member_count: int = _captor.member_unit_ids.size()
	_check(
		_context.battle_manager.finish_battle(
			session.battle_id, BattleSession.BattleResult.DEFENDER_VICTORY
		),
		"玩家战败结算成功"
	)

	_check(_hero.is_prisoner(), "玩家角色成为真实俘虏")
	_check(
		_hero.prisoner_owner_party_id == _captor.party_id,
		"玩家角色被胜利方关押"
	)
	_check(
		_context.captivity_manager.is_player_captive(),
		"管理器进入玩家被俘状态"
	)
	_check(
		_context.captivity_manager.get_captor_party_id() == _captor.party_id,
		"记录押送部队"
	)
	_check(_hero.current_hp == 0, "玩家角色被俘时保留 0 HP")
	_check(_hero.max_hp == _hero_max_hp, "玩家角色最大生命值不变")
	_check(_hero.equipment == _hero_equipment, "玩家角色装备完整保留")
	_check(
		_player.member_unit_ids.is_empty(),
		"玩家角色不再作为原部队可操作成员（全员被俘）"
	)
	_check(
		_player.battle_state == PartyData.BattleState.DISABLED,
		"玩家原部队失去世界控制"
	)
	_check(
		_context.party_manager.get_party(_player.party_id) != null,
		"玩家部队作为身份锚点保留"
	)
	_check(_player.prisoner_unit_ids.is_empty(), "玩家部队不持有自己的战败成员")
	_check(
		_captor.prisoner_unit_ids.size() == player_member_count,
		"胜利方接收全部玩家俘虏"
	)
	_check(
		_context.party_manager.get_party(_captor.party_id) != null
			and _captor.member_unit_ids.size() == captor_member_count,
		"胜利方部队不受战败清理影响"
	)
	_check(
		_context.party_manager.get_party(_player.party_id) != null
			and _context.unit_manager.get_unit(_hero.unit_id) != null,
		"战败清理不删除玩家部队与玩家角色"
	)
	_check(
		_captor.current_target_id.is_empty() and not _captor.attack_intent
			and _captor.focus_party_id.is_empty(),
		"战斗结束清除押送方旧追击引用"
	)


func _initialize_capture_timers() -> void:
	_context.captivity_manager.on_world_tick(0.1)
	_check(
		_context.captivity_manager.prisoner_healing_last_hour == 0,
		"首次 world tick 初始化俘虏治疗计时"
	)


func _test_captive_ui() -> void:
	var packed := load("res://Scenes/WorldMap/world_map.tscn") as PackedScene
	_map = packed.instantiate()
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame

	var hp_label := _map.find_child("PlayerHpLabel", true, false) as Label
	_check(hp_label != null, "顶栏存在玩家生命值字段")
	if hp_label != null:
		_check(
			hp_label.text == "生命 0/%d" % _hero_max_hp,
			"顶栏显示被俘玩家角色的真实 HP"
		)
	var panel := _map.find_child("CaptiveStatusPanel", true, false) as PanelContainer
	_check(panel != null and panel.visible, "被俘时显示左侧状态面板")
	var captor_label := _map.find_child("CaptiveCaptorLabel", true, false) as Label
	_check(
		captor_label != null and captor_label.text.contains(_captor.party_name),
		"被俘面板显示押送部队"
	)
	var captive_hp := _map.find_child("CaptiveHpLabel", true, false) as Label
	_check(
		captive_hp != null and captive_hp.text.contains("0")
			and captive_hp.text.contains(str(_hero_max_hp)),
		"被俘面板显示玩家生命"
	)
	var pause_button := _map.find_child("PauseButton", true, false) as Button
	var speed_button := _map.find_child("SpeedOneButton", true, false) as Button
	_check(
		pause_button != null and not pause_button.disabled
			and speed_button != null and not speed_button.disabled,
		"被俘期间仍可切换世界倍率"
	)


func _test_prisoner_healing() -> void:
	var captor_prisoners_before: int = _captor.prisoner_unit_ids.size()
	_check(
		TimeManager.world_tick.is_connected(
			_context.world_simulation.on_world_tick
		),
		"大地图世界 tick 已连接到 WorldSimulation"
	)

	# 每名俘虏独立获得治疗点数：共享池会让列表靠后的玩家角色几乎拿不到治疗。
	var hp_before: Dictionary = {}
	for unit_id: String in _captor.prisoner_unit_ids:
		var prisoner := _context.unit_manager.get_unit(unit_id)
		if prisoner != null:
			hp_before[unit_id] = prisoner.current_hp
	_context.captivity_manager.heal_party_prisoners(_captor, 5)
	var everyone_healed: bool = not hp_before.is_empty()
	for unit_id: String in hp_before:
		var prisoner := _context.unit_manager.get_unit(unit_id)
		if prisoner == null \
				or prisoner.current_hp < mini(prisoner.max_hp, int(hp_before[unit_id]) + 5):
			everyone_healed = false
	_check(everyone_healed, "单次恢复让每名俘虏各自获得点数")
	_check(
		_hero.current_hp == mini(_hero.max_hp, 5),
		"玩家角色作为俘虏同样直接获得治疗"
	)

	# 不使用管理器手动调用：真正让 TimeManager 推进 1 个游戏小时（2x 下约 3 秒），
	# 验证“被俘玩家随大地图时间恢复”的完整链路。
	for party: PartyData in _context.party_manager.get_all_parties():
		if party != null:
			party.ai_type = PartyData.PartyAIType.NONE
			party.attack_intent = false
			party.movement_state = PartyData.MovementState.IDLE
			party.target_position = party.world_position
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_DOUBLE)
	var start_seconds: float = TimeManager.world_elapsed_seconds
	var frames: int = 0
	while TimeManager.world_elapsed_seconds < start_seconds + 6.2 and frames < 1800:
		await get_tree().process_frame
		frames += 1
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	_check(
		TimeManager.world_elapsed_seconds >= start_seconds + 6.0,
		"世界时间真实推进到下一个游戏小时"
	)
	_check(_hero.current_hp == _hero.max_hp, "满血前按配置恢复俘虏生命值")
	_check(
		_context.captivity_manager.prisoner_healing_last_hour == 1,
		"真实世界 tick 驱动俘虏恢复结算"
	)
	_check(
		_context.captivity_manager.is_player_captive(),
		"逃脱概率为 0 时满血仍保持被俘"
	)
	_check(
		_captor.prisoner_unit_ids.size() == captor_prisoners_before,
		"俘虏恢复不改变俘虏归属"
	)
	var all_full: bool = true
	for unit_id: String in _captor.prisoner_unit_ids:
		var unit := _context.unit_manager.get_unit(unit_id)
		if unit == null or unit.current_hp < unit.max_hp:
			all_full = false
	_check(all_full, "押送方所有俘虏独立恢复生命值")
	if _map != null and is_instance_valid(_map):
		await get_tree().process_frame
		await get_tree().process_frame
		var hp_label := _map.find_child("PlayerHpLabel", true, false) as Label
		_check(
			hp_label != null and hp_label.text == "生命 %d/%d" % [
				_hero.max_hp, _hero_max_hp
			],
			"顶栏 HP 随俘虏恢复实时更新"
		)


func _save_while_captive() -> SaveData:
	var save := _context.to_save_data()
	_check(
		bool(save.captivity.get("is_player_captive", false)),
		"存档记录玩家被俘状态"
	)
	_check(
		str(save.captivity.get("captor_party_id", "")) == _captor.party_id,
		"存档记录押送部队"
	)
	return save


func _load_restored(save: SaveData) -> WorldContext:
	TimeManager.restore_world_time(save.world_elapsed_seconds, TimeManager.SPEED_PAUSED)
	var restored := WorldContext.new()
	restored.name = "CaptivityRestoredContext"
	add_child(restored)
	_check(restored.load_from_save_data(save), "被俘存档可恢复")
	if not restored.is_valid_world():
		return null
	var hero := restored.get_player_unit()
	_check(hero != null and hero.is_player_character, "读档恢复玩家角色身份")
	_check(
		hero != null and hero.is_prisoner()
			and hero.prisoner_owner_party_id == _captor.party_id,
		"读档恢复玩家角色俘虏归属"
	)
	_check(
		hero != null and hero.current_hp == hero.max_hp,
		"读档保留俘虏恢复后的 HP"
	)
	_check(
		restored.captivity_manager.is_player_captive()
			and restored.captivity_manager.get_captor_party_id() == _captor.party_id,
		"读档恢复被俘管理器状态"
	)
	_check(
		restored.captivity_manager.prisoner_healing_last_hour == 1
			and restored.captivity_manager.escape_check_last_hour == 1,
		"读档恢复俘虏恢复/逃脱计时"
	)
	var restored_player := restored.get_player_party()
	_check(
		restored_player != null and restored_player.member_unit_ids.is_empty()
			and restored_player.battle_state == PartyData.BattleState.DISABLED,
		"读档后玩家原部队仍不可操作"
	)
	_check(
		restored.unit_manager.get_unit(hero.unit_id).equipment == _hero_equipment,
		"读档保留被俘玩家装备"
	)
	return restored


func _test_escape(restored: WorldContext) -> void:
	var hero := restored.get_player_unit()
	var player := restored.get_player_party()
	var captor := restored.party_manager.get_party(_captor.party_id)
	var config := restored.captivity_manager.get_config()
	config.escape_chance = 1.0
	var captor_prisoners_before: int = captor.prisoner_unit_ids.size()
	var captor_position: Vector2 = captor.world_position
	TimeManager.restore_world_time(12.0, TimeManager.SPEED_PAUSED)
	restored.captivity_manager.on_world_tick(0.1)

	_check(
		not restored.captivity_manager.is_player_captive(),
		"满血且判定成功后逃脱"
	)
	_check(not hero.is_prisoner(), "逃脱后清除玩家俘虏归属")
	_check(hero.status == UnitData.Status.ACTIVE, "逃脱后玩家角色恢复活动状态")
	_check(hero.current_hp == hero.max_hp, "逃脱时玩家角色满血")
	_check(
		not captor.prisoner_unit_ids.has(hero.unit_id)
			and captor.prisoner_unit_ids.size() == captor_prisoners_before - 1,
		"押送方移除逃脱的玩家角色"
	)
	_check(
		player.member_unit_ids.size() == 1
			and player.member_unit_ids.has(hero.unit_id),
		"重建只包含玩家角色的玩家部队"
	)
	_check(
		player.leader_unit_id == hero.unit_id
			and player.battle_state == PartyData.BattleState.AVAILABLE
			and player.is_available_for_world(),
		"玩家重新获得部队控制"
	)
	_check(
		captor.prisoner_unit_ids.size() > 0,
		"逃脱不会自动恢复原有士兵"
	)
	_check(
		player.world_position.distance_to(captor_position)
			>= CaptivityManager.ESCAPE_MIN_DISTANCE * 0.5,
		"逃脱落点与押送部队保持距离"
	)
	var bounds: Rect2 = restored.world_map_manager.world_bounds
	_check(
		player.world_position.x >= bounds.position.x + 20.0
			and player.world_position.x <= bounds.end.x - 20.0
			and player.world_position.y >= bounds.position.y + 20.0
			and player.world_position.y <= bounds.end.y - 20.0,
		"逃脱落点位于合法地图边界内"
	)
	_check(
		restored.captivity_manager.is_player_protected(),
		"逃脱后立即进入保护期"
	)


func _test_escape_protection(restored: WorldContext) -> void:
	var player := restored.get_player_party()
	var captor := restored.party_manager.get_party(_captor.party_id)
	_check(
		restored.captivity_manager.get_escape_protection_until()
			== TimeManager.world_elapsed_seconds
				+ 2.0 * CaptivityManager.SECONDS_PER_GAME_HOUR,
		"保护期按配置持续 2 个游戏小时"
	)
	_check(
		restored.ai_manager.get("_captivity_manager") != null,
		"AI 管理器查询同一被俘/保护状态"
	)
	_check(
		restored.encounter_manager.get("_captivity_manager") != null,
		"遭遇管理器查询同一被俘/保护状态"
	)

	# 构造 AI 主动追击玩家的接触。
	player.world_position = Vector2(1200.0, 1200.0)
	player.target_position = player.world_position
	player.movement_state = PartyData.MovementState.IDLE
	player.engagement_cooldown_until = 0.0
	captor.world_position = Vector2(1230.0, 1200.0)
	captor.target_position = captor.world_position
	captor.movement_state = PartyData.MovementState.IDLE
	captor.attack_intent = true
	captor.current_target_id = player.party_id
	captor.engagement_cooldown_until = 0.0
	restored.encounter_manager.clear_pending_player_encounter()
	restored.encounter_manager.clear_encounter_decline_latch()
	_check(
		not restored.encounter_manager.update_encounters(),
		"保护期内 AI 主动攻击不触发 Player遭遇"
	)
	_check(
		restored.encounter_manager.get_pending_player_encounter().is_empty(),
		"保护期内不生成待处理遭遇"
	)

	# 保护期结束后恢复正常的 AI 主动拦截。
	TimeManager.restore_world_time(
		restored.captivity_manager.get_escape_protection_until(),
		TimeManager.SPEED_PAUSED
	)
	_check(not restored.captivity_manager.is_player_protected(), "保护期自然到期")
	captor.attack_intent = true
	captor.current_target_id = player.party_id
	_check(
		restored.encounter_manager.update_encounters(),
		"保护期结束后 AI 可再次主动拦截玩家"
	)
	restored.encounter_manager.clear_pending_player_encounter()


func _find_party(party_name: String) -> PartyData:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _free_map() -> void:
	if _map != null and is_instance_valid(_map):
		_map.queue_free()
		_map = null
	GameManager.world_context = null
	GameManager.player_party_id = ""


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if _map != null and is_instance_valid(_map):
		_map.queue_free()
	if _context != null and is_instance_valid(_context):
		_context.queue_free()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[captivity] OK: %s" % message)
	else:
		_failed = true
		push_error("[captivity] FAIL: %s" % message)
