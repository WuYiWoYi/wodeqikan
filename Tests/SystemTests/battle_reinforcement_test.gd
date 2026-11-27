extends Node
## 阶段 8 系统测试：增援加入既有战斗、后方部署、不重置既有单位，
## 以及玩家侧 NPC 增援提示的家族旗帜/贵族姓名来源与消息排队。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/battle_reinforcement_test.tscn

var _failed: bool = false
var _context: WorldContext = null
var _battle_scene: Node2D = null
var _session: BattleSession = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[reinforce] 测试失败")
		get_tree().quit(1)
	else:
		print("[reinforce] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)

	_context = WorldContext.new()
	_context.name = "BattleReinforcementTestContext"
	add_child(_context)
	# 测试夹具：使用平民身份并注册独立玩家家族，
	# 使玩家的政治关系不随 NPC 王国战争自动变化。
	var catalog := IdentityCatalog.load_default()
	var commoner := catalog.get_identity("IDENTITY_DORAMAN_MERCENARY") \
		if catalog != null else null
	_check(commoner != null, "加载平民身份配置")
	_check(WorldInitializer.create_new_world(_context, commoner), "初始化世界")
	if not _context.is_valid_world():
		return
	var player_house := _context.house_manager.register_house(
		WorldInitializer.HOUSE_PLAYER_ID,
		WorldInitializer.PLAYER_HOUSE_NAME,
		WorldInitializer.FAMILY_PLAYER_ID,
		true
	)
	_check(player_house != null, "注册独立玩家家族")
	_context.player_house_id = player_house.house_id
	var player_party := _context.get_player_party()
	if player_party != null:
		player_party.family_id = player_house.house_id

	var player := _context.get_player_party()
	var bandits := _find_party_by_name("山道强盗")
	# 新世界每个家族单支部队：伯克纳骑士由国王指挥，巴里骑士为同王国附庸。
	var burknania_knights := _find_party_by_name(WorldInitializer.BURKNANIA_KNIGHT_PARTY_NAME)
	var burknania_ally := _find_party_by_name(WorldInitializer.BARI_KNIGHT_PARTY_NAME)
	_check(
		player != null and bandits != null and burknania_knights != null
			and burknania_ally != null,
		"测试所需部队存在"
	)
	if player == null or bandits == null or burknania_knights == null \
			or burknania_ally == null:
		return

	# 玩家与伯克纳建立临时友好，使伯克纳部队成为玩家侧增援；
	# 同时把本地势力设为强盗敌对，保证增援方与敌方确有敌对关系。
	_context.faction_manager.set_house_relation(
		"HOUSE_PLAYER", "HOUSE_BURKNANIA", FactionManager.Relation.FRIENDLY
	)
	_context.faction_manager.set_relation(
		FactionManager.LOCAL_FACTION_ID,
		FactionManager.BANDIT_FACTION_ID,
		FactionManager.Relation.HOSTILE
	)

	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id

	_session = _context.battle_manager.start_battle(
		[player.party_id] as Array[String],
		[bandits.party_id] as Array[String],
		bandits.world_position
	)
	_check(_session != null, "创建玩家战斗")
	if _session == null:
		return

	var packed := load("res://Scenes/Battle/battle.tscn") as PackedScene
	_battle_scene = packed.instantiate() as Node2D
	add_child(_battle_scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var player_side: int = _battle_scene.get_player_side()
	var initial_actor_count: int = _battle_scene.get_actor_count()
	var initial_controllers: Dictionary = {}
	for unit_id: String in _session.get_all_unit_ids():
		initial_controllers[unit_id] = _battle_scene.get_controller(unit_id)

	# 增援部队进入战斗中心附近，满足加入距离。
	burknania_knights.world_position = _session.world_position
	var joined: bool = _context.battle_manager.try_join_battle(
		burknania_knights.party_id, _session.battle_id
	)
	_check(joined, "伯克纳骑士加入既有战斗")
	_check(
		_session.get_side_of_party(burknania_knights.party_id) == player_side,
		"增援加入玩家所在战斗侧"
	)
	var participant := _session.get_participant(burknania_knights.party_id)
	_check(participant != null and participant.is_reinforcement, "参战方标记为增援")
	_check(
		participant != null
			and participant.reinforcement_battle_id == _session.battle_id,
		"参战方记录增援战斗 ID"
	)
	for unit_id: String in _session.get_party_unit_ids(burknania_knights.party_id):
		var state := _session.get_unit_state(unit_id)
		_check(state != null and state.is_reinforcement, "增援单位带增援标记")
		if state != null:
			_check(
				state.reinforcement_battle_id == _session.battle_id,
				"增援单位记录战斗 ID"
			)

	await get_tree().process_frame
	await get_tree().process_frame

	var expected_actor_count: int = (
		initial_actor_count + burknania_knights.member_unit_ids.size()
	)
	_check(
		_battle_scene.get_actor_count() == expected_actor_count,
		"增援单位在场景中生成"
	)

	# 既有控制器对象与 HP 不被增援流程重建或重置。
	var existing_preserved: bool = true
	for unit_id: String in initial_controllers:
		var controller: UnitController = _battle_scene.get_controller(unit_id)
		if controller != initial_controllers[unit_id]:
			existing_preserved = false
	_check(existing_preserved, "既有单位控制器未被重置")

	var enemy_centroid := _centroid_of_side(_session.get_side_of_party(bandits.party_id))
	var all_rear: bool = true
	var no_overlap: bool = true
	var positions: Array[Vector2] = []
	for unit_id: String in _session.get_party_unit_ids(burknania_knights.party_id):
		var controller: UnitController = _battle_scene.get_controller(unit_id)
		if controller == null:
			all_rear = false
			continue
		var position := controller.get_position()
		positions.append(position)
		if position.x >= enemy_centroid.x:
			all_rear = false
		if not Rect2(Vector2.ZERO, BattleScene.BATTLEFIELD_SIZE).has_point(position):
			all_rear = false
		for existing: Vector2 in positions:
			if position != existing and position.distance_to(existing) < 30.0:
				no_overlap = false
		for unit_id_other: String in initial_controllers:
			var other: UnitController = _battle_scene.get_controller(unit_id_other)
			if other != null and position.distance_to(other.get_position()) < 30.0:
				no_overlap = false
	_check(all_rear, "增援在己方后方生成并保持战场边界内")
	_check(no_overlap, "增援生成位置不与既有单位重叠")

	var prompt_panel := _battle_scene.find_child(
		"ReinforcementPromptPanel", true, false
	) as PanelContainer
	var prompt_label := _battle_scene.find_child(
		"ReinforcementPromptLabel", true, false
	) as Label
	var prompt_badge := _battle_scene.find_child(
		"ReinforcementBannerBadge", true, false
	) as TextureRect
	_check(prompt_panel != null and prompt_panel.visible, "玩家侧增援显示提示")
	_check(
		prompt_label != null
			and prompt_label.text.contains(WorldInitializer.BURKNANIA_KING_NAME)
			and prompt_label.text.contains(WorldInitializer.BURKNANIA_HOUSE_NAME),
		"提示包含真实贵族与家族名称"
	)
	_check(
		prompt_badge != null and prompt_badge.visible and prompt_badge.texture != null,
		"配置了家族旗帜时显示徽章"
	)

	# 第二名增援进入队列，不覆盖当前提示。
	burknania_ally.world_position = _session.world_position
	_check(
		_context.battle_manager.try_join_battle(
			burknania_ally.party_id, _session.battle_id
		),
		"第二支伯克纳王国部队加入玩家侧"
	)
	var queue: Array = _battle_scene.get("_reinforcement_queue") as Array
	_check(queue != null and queue.size() >= 1, "多条增援提示进入队列而非覆盖")
	_check(
		prompt_label != null and prompt_label.text.contains(
			WorldInitializer.BURKNANIA_KING_NAME
		),
		"当前提示仍为第一条增援消息"
	)

	# 玩家自身与敌对侧增援不得产生提示。
	var queue_before: int = queue.size() if queue != null else 0
	var ally_noble := _context.house_manager.get_house_leader(
		WorldInitializer.HOUSE_BARI_ID
	)
	_battle_scene.call(
		"_on_party_reinforced",
		_session.battle_id,
		player.party_id,
		_context.player_lord_id,
		player_side
	)
	_battle_scene.call(
		"_on_party_reinforced",
		_session.battle_id,
		burknania_ally.party_id,
		ally_noble.lord_id if ally_noble != null else "",
		1 - player_side
	)
	queue = _battle_scene.get("_reinforcement_queue") as Array
	_check(
		(queue.size() if queue != null else 0) == queue_before,
		"玩家自身与非玩家侧增援不产生提示"
	)

	await _test_player_joins_bandit_side_reinforcement()
	await _test_three_side_bottom_reinforcement()


## 玩家参与战斗且强盗一方位于第 1 侧（右侧）时，后续增援必须部署在右侧。
func _test_player_joins_bandit_side_reinforcement() -> void:
	_finish_current_battle_scene()
	var player := _context.get_player_party()
	var bandits := _find_party_by_name(WorldInitializer.BANDIT_PARTY_NAME)
	var ally := _find_party_by_name(WorldInitializer.BARI_KNIGHT_PARTY_NAME)
	var east_bandits := _find_party_by_name(WorldInitializer.EAST_BANDIT_PARTY_NAME)
	_check(
		player != null and bandits != null and ally != null and east_bandits != null,
		"右侧增援测试所需部队存在"
	)
	if player == null or bandits == null or ally == null or east_bandits == null:
		return
	# 玩家与巴里骑士同属伯克纳王国；强盗因敌对关系位于第 1 侧（右侧）。
	_reset_party_for_battle(bandits)
	_reset_party_for_battle(ally)
	_reset_party_for_battle(player)
	_reset_party_for_battle(east_bandits)
	var position := Vector2(1500.0, 1500.0)
	# 巴里骑士与玩家为第 0 侧（左），强盗为第 1 侧（右）。
	_session = _context.battle_manager.start_battle(
		[ally.party_id, player.party_id] as Array[String],
		[bandits.party_id] as Array[String],
		position
	)
	_check(_session != null, "创建强盗位于右侧的玩家参与战斗")
	if _session == null:
		return
	_check(
		_session.get_side_of_party(player.party_id) == 0
			and _session.get_side_of_party(bandits.party_id) == 1,
		"玩家在左侧战斗侧，强盗在右侧战斗侧"
	)
	await _instantiate_battle_scene()
	var snapshot := _snapshot_controllers()
	var initial_count: int = _battle_scene.get_actor_count()

	east_bandits.world_position = position
	_check(
		_context.battle_manager.try_join_battle(
			east_bandits.party_id, _session.battle_id
		),
		"东路强盗作为增援加入既有战斗"
	)
	_check(
		_session.get_side_of_party(east_bandits.party_id) == 1,
		"增援加入强盗所在的第 1 侧"
	)
	await _wait_spawn_frames()
	_check(
		_battle_scene.get_actor_count()
			== initial_count + east_bandits.member_unit_ids.size(),
		"右侧增援单位全部生成"
	)
	var behind := _side_positions_behind(east_bandits.party_id, Vector2.RIGHT)
	var in_bounds := _side_positions_in_bounds(east_bandits.party_id)
	var spaced := _side_positions_spaced(east_bandits.party_id, snapshot)
	_check(behind, "右侧增援部署在右后方")
	_check(in_bounds, "右侧增援保持在战场边界内")
	_check(spaced, "右侧增援不与既有单位重叠")
	_check(_controllers_and_state_preserved(snapshot), "既有单位控制器、HP 与冷却未被重置")


## 三战斗侧时第 2 侧位于下方，其增援同样部署在下方后方。
func _test_three_side_bottom_reinforcement() -> void:
	_finish_current_battle_scene()
	var burknania_knight := _find_party_by_name(
		WorldInitializer.BURKNANIA_KNIGHT_PARTY_NAME
	)
	var burknania_ally := _find_party_by_name(
		WorldInitializer.BARI_KNIGHT_PARTY_NAME
	)
	var olin_knight := _find_party_by_name(WorldInitializer.OLIN_KNIGHT_PARTY_NAME)
	# 墨西西与奥林同属洛里亚克王国，可作为第 2 侧增援。
	var moxixi_knight := _find_party_by_name(
		WorldInitializer.MOXIXI_KNIGHT_PARTY_NAME
	)
	var player := _context.get_player_party()
	_check(
		burknania_knight != null and burknania_ally != null
			and olin_knight != null and moxixi_knight != null and player != null,
		"三侧增援测试所需部队存在"
	)
	if burknania_knight == null or burknania_ally == null \
			or olin_knight == null or moxixi_knight == null or player == null:
		return
	# 玩家与奥林友好，加入第 2 侧；同时保证屏幕战斗存在玩家参与。
	_context.faction_manager.set_house_relation(
		"HOUSE_PLAYER", "HOUSE_OLIN", FactionManager.Relation.FRIENDLY
	)
	# 新世界初始无战争；本测试临时让伯克纳与洛里亚克交战，
	# 使第 0/1 侧的伯克纳部队与第 2 侧的奥林/墨西西敌对。
	_context.kingdom_manager.declare_war(
		WorldInitializer.KINGDOM_BURKNANIA_ID, WorldInitializer.KINGDOM_LORIAK_ID
	)
	for party: PartyData in [
		burknania_knight, burknania_ally, olin_knight, moxixi_knight, player
	]:
		_reset_party_for_battle(party)

	var position := Vector2(1500.0, 1500.0)
	# 第 0/1 侧均为与奥林敌对的伯克纳部队，第 2 侧为奥林骑士与玩家；
	# 墨西西骑士只与第 2 侧友好，因此加入第 2 侧（下方）。
	_session = _context.battle_manager.start_battle_by_sides(
		[
			[burknania_knight.party_id],
			[burknania_ally.party_id],
			[olin_knight.party_id, player.party_id],
		],
		position
	)
	_check(_session != null, "创建三战斗侧屏幕战斗")
	if _session == null:
		return
	await _instantiate_battle_scene()
	var snapshot := _snapshot_controllers()

	moxixi_knight.world_position = position
	_check(
		_context.battle_manager.try_join_battle(
			moxixi_knight.party_id, _session.battle_id
		),
		"墨西西骑士加入既有三方战斗"
	)
	_check(
		_session.get_side_of_party(moxixi_knight.party_id) == 2
			and _session.get_side_of_party(moxixi_knight.party_id)
				== _session.get_side_of_party(olin_knight.party_id),
		"墨西西骑士加入第 2 侧"
	)
	await _wait_spawn_frames()
	var behind := _side_positions_behind(moxixi_knight.party_id, Vector2.DOWN)
	var in_bounds := _side_positions_in_bounds(moxixi_knight.party_id)
	var spaced := _side_positions_spaced(moxixi_knight.party_id, snapshot)
	_check(behind, "第 2 侧增援部署在下方后方")
	_check(in_bounds, "第 2 侧增援保持在战场边界内")
	_check(spaced, "第 2 侧增援不与既有单位重叠")
	_check(_controllers_and_state_preserved(snapshot), "三侧战斗中既有单位状态未被重置")


func _finish_current_battle_scene() -> void:
	if is_instance_valid(_battle_scene):
		_battle_scene.queue_free()
		_battle_scene = null
	if _session != null:
		if _context.battle_manager.get_battle(_session.battle_id) != null:
			_context.battle_manager.finish_battle(
				_session.battle_id, BattleSession.BattleResult.ABORTED
			)
		_session = null


func _instantiate_battle_scene() -> void:
	var packed := load("res://Scenes/Battle/battle.tscn") as PackedScene
	_battle_scene = packed.instantiate() as Node2D
	add_child(_battle_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	# 暂停战斗物理，冻结既有单位位置/HP/攻击冷却，便于精确验证增援不重置状态。
	_battle_scene.set("_scene_paused", true)


func _wait_spawn_frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _snapshot_controllers() -> Dictionary:
	var snapshot: Dictionary = {}
	if _session == null or _battle_scene == null:
		return snapshot
	for unit_id: String in _session.get_all_unit_ids():
		var controller: UnitController = _battle_scene.get_controller(unit_id)
		if controller != null:
			snapshot[unit_id] = {
				"controller": controller,
				"position": controller.get_position(),
				"hp": controller.state.battle_hp,
				"cooldown": controller.get_attack_cooldown(),
			}
	return snapshot


func _controllers_and_state_preserved(snapshot: Dictionary) -> bool:
	for unit_id_value: Variant in snapshot.keys():
		var unit_id := str(unit_id_value)
		var before: Dictionary = snapshot[unit_id_value]
		var controller: UnitController = _battle_scene.get_controller(unit_id)
		if controller != before["controller"]:
			return false
		if controller.get_position() != before["position"]:
			return false
		if controller.state.battle_hp != int(before["hp"]):
			return false
		if not is_equal_approx(
			controller.get_attack_cooldown(), float(before["cooldown"])
		):
			return false
	return true


func _side_positions_behind(party_id: String, away: Vector2) -> bool:
	var center := BattleScene.BATTLEFIELD_SIZE * 0.5
	for unit_id: String in _session.get_party_unit_ids(party_id):
		var controller: UnitController = _battle_scene.get_controller(unit_id)
		if controller == null:
			return false
		if (controller.get_position() - center).dot(away) <= 0.0:
			return false
	return true


func _side_positions_in_bounds(party_id: String) -> bool:
	var bounds := Rect2(Vector2.ZERO, BattleScene.BATTLEFIELD_SIZE)
	for unit_id: String in _session.get_party_unit_ids(party_id):
		var controller: UnitController = _battle_scene.get_controller(unit_id)
		if controller == null or not bounds.has_point(controller.get_position()):
			return false
	return true


func _side_positions_spaced(party_id: String, snapshot: Dictionary) -> bool:
	var positions: Array[Vector2] = []
	for unit_id: String in _session.get_party_unit_ids(party_id):
		var controller: UnitController = _battle_scene.get_controller(unit_id)
		if controller == null:
			return false
		var position := controller.get_position()
		for other: Vector2 in positions:
			if position.distance_to(other) < 30.0:
				return false
		for unit_id_value: Variant in snapshot.keys():
			var before: Dictionary = snapshot[unit_id_value]
			if position.distance_to(before["position"] as Vector2) < 30.0:
				return false
		positions.append(position)
	return true


func _reset_party_for_battle(party: PartyData) -> void:
	if party == null:
		return
	party.battle_state = PartyData.BattleState.AVAILABLE
	party.current_order = PartyData.OrderType.NONE
	party.current_target_id = ""
	party.attack_intent = false
	party.target_position = party.world_position
	party.movement_state = PartyData.MovementState.IDLE
	party.battle_response_id = ""
	party.battle_response_until = 0.0


func _centroid_of_side(side_index: int) -> Vector2:
	var total := Vector2.ZERO
	var count: int = 0
	for unit_id: String in _session.get_side_unit_ids(side_index):
		var controller: UnitController = _battle_scene.get_controller(unit_id)
		if controller != null and controller.is_alive():
			total += controller.get_position()
			count += 1
	if count == 0:
		return Vector2.ZERO
	return total / float(count)


func _find_party_by_name(party_name: String) -> PartyData:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[reinforce] OK: %s" % message)
	else:
		_failed = true
		push_error("[reinforce] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_battle_scene):
		_battle_scene.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
