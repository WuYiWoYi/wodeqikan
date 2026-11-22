extends Node
## 多方战斗测试：战斗侧划分、友军/第三方加入、距离与重复校验、离屏结算、BattleScene 多侧。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/multi_party_battle_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"
const RAIDER_FACTION_ID: String = "FACTION_RAIDER"
const NEUTRAL_FACTION_ID: String = "FACTION_NEUTRAL"

var _failed: bool = false
var _militia: UnitConfig = null
var _ids: IdGenerator = null
var _units: UnitManager = null
var _parties: PartyManager = null
var _factions: FactionManager = null
var _battle: BattleManager = null
var _context: WorldContext = null
var _battle_scene: Node2D = null

var _player: PartyData = null
var _merchant: PartyData = null
var _guard: PartyData = null
var _bandit: PartyData = null
var _raider: PartyData = null
var _neutral: PartyData = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[multi] 测试失败")
		get_tree().quit(1)
	else:
		print("[multi] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	_militia = load(MILITIA_PATH) as UnitConfig
	_check(_militia != null, "加载民兵配置")
	if _militia == null:
		return

	_setup_fixture()
	_test_two_side_regression()
	_test_friendly_join()
	_test_neutral_cannot_join()
	_test_third_side_join()
	_test_distance_and_duplicate_rules()
	_test_multi_side_auto_resolve()
	await _test_battle_scene_multi_side()


func _setup_fixture() -> void:
	_ids = IdGenerator.new()
	_units = UnitManager.new()
	_units.setup(_ids)
	_parties = PartyManager.new()
	_parties.setup(_units, _ids)
	_factions = FactionManager.new()
	_factions.setup_defaults(_parties)
	_factions.register_faction(NEUTRAL_FACTION_ID, "中立者")
	_factions.register_faction(RAIDER_FACTION_ID, "劫掠者")
	_factions.set_relation(
		RAIDER_FACTION_ID, FactionManager.PLAYER_FACTION_ID,
		FactionManager.Relation.HOSTILE
	)
	_factions.set_relation(
		RAIDER_FACTION_ID, FactionManager.MERCHANT_FACTION_ID,
		FactionManager.Relation.HOSTILE
	)
	_factions.set_relation(
		RAIDER_FACTION_ID, FactionManager.BANDIT_FACTION_ID,
		FactionManager.Relation.HOSTILE
	)
	_factions.set_relation(
		RAIDER_FACTION_ID, FactionManager.GUARD_FACTION_ID,
		FactionManager.Relation.HOSTILE
	)

	_battle = BattleManager.new()
	_battle.setup(_units, _parties, _ids, _factions)

	_player = _make_party(FactionManager.PLAYER_FACTION_ID, "玩家", 2)
	_merchant = _make_party(FactionManager.MERCHANT_FACTION_ID, "商队", 2)
	_guard = _make_party(FactionManager.GUARD_FACTION_ID, "治安队", 2)
	_bandit = _make_party(FactionManager.BANDIT_FACTION_ID, "强盗", 2)
	_raider = _make_party(RAIDER_FACTION_ID, "劫掠者", 2)
	_neutral = _make_party(NEUTRAL_FACTION_ID, "中立者", 1)
	_battle.player_party_id = _player.party_id


func _test_two_side_regression() -> void:
	_reset_positions()
	var session := _battle.start_battle(
		[_player.party_id], [_bandit.party_id], Vector2(1000.0, 1000.0)
	)
	_check(session != null, "双方战斗仍可创建")
	if session == null:
		return
	_check(session.get_side_count() == 2, "双方战斗包含 2 个战斗侧")
	_check(
		session.get_side_of_party(_player.party_id) == 0
		and session.get_side_of_party(_bandit.party_id) == 1,
		"进攻方与防守方分属不同战斗侧"
	)
	_check(session.attacker_unit_ids.size() == 2, "进攻方单位进入 legacy 列表")
	_check(session.defender_unit_ids.size() == 2, "防守方单位进入 legacy 列表")
	_check(session.paused_world, "玩家参与的战斗暂停世界")
	_check(
		_player.battle_state == PartyData.BattleState.IN_BATTLE
		and _bandit.battle_state == PartyData.BattleState.IN_BATTLE,
		"双方部队被锁定"
	)
	var independent := _battle.start_battle(
		[_guard.party_id], [_raider.party_id], Vector2(200.0, 200.0), true
	)
	_check(
		independent != null,
		"玩家战斗进行中仍可在其他位置创建独立 AI 离屏战斗"
	)
	_check(
		_battle.get_active_battles().size() == 2,
		"玩家屏幕战斗与 AI 离屏战斗同时存在"
	)
	if independent != null:
		_check(
			_battle.abort_battle(independent.battle_id),
			"中止独立 AI 离屏战斗"
		)
		_check(
			_battle.get_battle(session.battle_id) == session,
			"结束 AI 战斗不影响玩家屏幕战斗"
		)
	_check(_battle.abort_battle(session.battle_id), "中止双方战斗")


func _test_friendly_join() -> void:
	_reset_positions()
	var session := _battle.start_battle(
		[_merchant.party_id], [_bandit.party_id], Vector2(1000.0, 1000.0), true
	)
	_check(session != null, "创建商队-强盗离屏战斗")
	if session == null:
		return
	_guard.world_position = Vector2(1040.0, 1000.0)
	_check(
		_battle.can_party_join(_guard.party_id, session.battle_id),
		"治安队可加入商队一方"
	)
	_check(
		_battle.try_join_battle(_guard.party_id, session.battle_id),
		"治安队加入战斗"
	)
	_check(
		session.get_side_of_party(_guard.party_id)
		== session.get_side_of_party(_merchant.party_id),
		"治安队与商队同侧"
	)
	_check(
		session.get_side_of_party(_guard.party_id)
		!= session.get_side_of_party(_bandit.party_id),
		"治安队与强盗不同侧"
	)
	_check(session.get_side_count() == 2, "友军加入不增加战斗侧")
	_check(_battle.abort_battle(session.battle_id), "中止友军加入测试")


func _test_neutral_cannot_join() -> void:
	_reset_positions()
	var session := _battle.start_battle(
		[_merchant.party_id], [_bandit.party_id], Vector2(1000.0, 1000.0), true
	)
	_check(session != null, "创建中立加入测试战斗")
	if session == null:
		return
	_neutral.world_position = Vector2(1020.0, 1000.0)
	_check(
		_battle.get_join_side(_neutral.party_id, session.battle_id) < 0,
		"与任何一方都无敌对关系的中立部队不能加入"
	)
	_check(
		not _battle.try_join_battle(_neutral.party_id, session.battle_id),
		"中立部队加入失败"
	)
	_check(not session.is_party_involved(_neutral.party_id), "中立部队未进入参战列表")
	_check(_battle.abort_battle(session.battle_id), "中止中立加入测试")


func _test_third_side_join() -> void:
	_reset_positions()
	var session := _battle.start_battle(
		[_merchant.party_id], [_bandit.party_id], Vector2(1000.0, 1000.0), true
	)
	_check(session != null, "创建第三方加入测试战斗")
	if session == null:
		return
	_raider.world_position = Vector2(1030.0, 1000.0)
	var side := _battle.get_join_side(_raider.party_id, session.battle_id)
	_check(side < 0, "与双方都敌对的部队不自动获得第三方战斗侧")
	_check(
		not _battle.try_join_battle(_raider.party_id, session.battle_id),
		"与所有战斗侧敌对时不能以协助名义加入"
	)
	_check(session.get_side_count() == 2, "第三方加入失败不改变战斗侧数量")
	_check(
		not session.is_party_involved(_raider.party_id),
		"第三方未进入参战列表"
	)
	_check(_battle.abort_battle(session.battle_id), "中止第三方加入测试")


func _test_distance_and_duplicate_rules() -> void:
	_reset_positions()
	var session := _battle.start_battle(
		[_merchant.party_id], [_bandit.party_id], Vector2(1000.0, 1000.0), true
	)
	_check(session != null, "创建距离与重复规则测试战斗")
	if session == null:
		return
	_guard.world_position = Vector2(1000.0 + BattleManager.JOIN_RADIUS + 10.0, 1000.0)
	_check(
		not _battle.can_party_join(_guard.party_id, session.battle_id),
		"超出加入半径不能加入"
	)
	_guard.world_position = Vector2(1020.0, 1000.0)
	_check(
		_battle.try_join_battle(_merchant.party_id, session.battle_id) == false,
		"已在战斗中的部队不能重复加入"
	)
	_check(
		_battle.get_join_side(_merchant.party_id, session.battle_id) < 0,
		"已参战部队没有可加入侧"
	)
	_check(
		not session.is_party_involved(_guard.party_id),
		"未成功加入的部队不在参战列表"
	)
	_check(_battle.abort_battle(session.battle_id), "中止距离与重复测试")


func _test_multi_side_auto_resolve() -> void:
	_reset_positions()
	# 第三方现在只能由显式多方入口创建，不再通过 get_join_side 自动生成。
	var session := _battle.start_battle_by_sides(
		[[_merchant.party_id], [_bandit.party_id], [_raider.party_id]],
		Vector2(1000.0, 1000.0),
		true
	)
	_check(session != null, "创建多方自动结算战斗")
	if session == null:
		return
	_check(session.get_side_count() == 3, "自动结算前存在 3 个战斗侧")

	_check(_battle.resolve_current_battle_now(), "多方离屏战斗按小时推进并结算")
	_check(_battle.get_battle(session.battle_id) == null, "多方离屏战斗自动结算")
	_check(session.status == BattleSession.Status.ENDED, "战斗会话标记为结束")
	for party: PartyData in [_merchant, _bandit, _raider]:
		_check(
			party.battle_state != PartyData.BattleState.IN_BATTLE,
			"结算后参战部队解除战斗状态: %s" % party.party_name
		)


func _test_battle_scene_multi_side() -> void:
	_reset_positions()
	# 玩家与商队同侧（中立但共同敌对强盗），强盗为第二侧，劫掠者为第三侧。
	var sides: Array = [
		[_player.party_id, _merchant.party_id],
		[_bandit.party_id],
		[_raider.party_id],
	]
	var session := _battle.start_battle_by_sides(sides, Vector2(1000.0, 1000.0), false)
	_check(session != null, "创建三战斗侧屏幕战斗")
	if session == null:
		return
	_check(session.get_side_count() == 3, "屏幕战斗包含 3 个战斗侧")
	_check(
		session.get_side_of_party(_player.party_id) == 0,
		"玩家处于战斗侧 0"
	)

	_context = WorldContext.new()
	_context.name = "MultiBattleContext"
	add_child(_context)
	# 用测试管理器替换 WorldContext 默认装配，保证战斗场景读取同一批数据。
	_context.unit_manager = _units
	_context.party_manager = _parties
	_context.faction_manager = _factions
	_context.battle_manager = _battle
	_context.player_party_id = _player.party_id
	GameManager.world_context = _context
	GameManager.player_party_id = _player.party_id

	var packed := load("res://Scenes/Battle/battle.tscn") as PackedScene
	_battle_scene = packed.instantiate() as Node2D
	add_child(_battle_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	# 本测试直接清空其他战斗侧后立即检查胜负；关闭胜利展示延迟。
	_battle_scene.set_result_delay_enabled(false)

	_check(_battle_scene.get_side_controller_count(0) == 4, "战斗侧 0 生成 4 名士兵")
	_check(_battle_scene.get_side_controller_count(1) == 2, "战斗侧 1 生成 2 名士兵")
	_check(_battle_scene.get_side_controller_count(2) == 2, "战斗侧 2 生成 2 名士兵")
	_check(
		_battle_scene.get_enemy_controller_count(0) == 4,
		"战斗侧 0 的敌人只来自其他战斗侧"
	)
	_check(_battle_scene.get_player_side() == 0, "战斗场景识别玩家战斗侧")

	# 直接清除其他两个战斗侧，快速验证胜负与结算。
	for side_index: int in [1, 2]:
		for unit_id: String in session.get_side_unit_ids(side_index):
			var state := session.get_unit_state(unit_id)
			if state != null:
				state.battle_hp = 0
				state.alive = false
	await get_tree().physics_frame
	await get_tree().physics_frame

	var result_label := _battle_scene.find_child("BattleResultLabel", true, false) as Label
	_check(result_label != null and result_label.text == "战斗胜利", "玩家侧获胜显示胜利")
	_check(session.winning_side_index == 0, "战斗会话记录获胜侧")

	_check(
		_battle.finish_battle(
			session.battle_id, BattleSession.BattleResult.ATTACKER_VICTORY
		),
		"三方战斗结算成功"
	)
	_check(_battle.current_battle == null, "结算后清理战斗会话")
	_check(
		_player.battle_state == PartyData.BattleState.AVAILABLE,
		"玩家部队结算后解锁"
	)

	if is_instance_valid(_battle_scene):
		_battle_scene.queue_free()
		_battle_scene = null


func _make_party(faction_id: String, party_name: String, unit_count: int) -> PartyData:
	var party := _parties.create_party(faction_id, Vector2(1000.0, 1000.0), party_name)
	party.movement_speed = 110.0
	party.sight_range = 300.0
	for i: int in range(unit_count):
		var unit := _units.create_unit(_militia, faction_id)
		_parties.add_member(party.party_id, unit.unit_id)
	return party


func _reset_positions() -> void:
	for session: BattleSession in _battle.get_active_battles():
		_battle.finish_battle(
			session.battle_id, BattleSession.BattleResult.ABORTED
		)
	for party: PartyData in [_player, _merchant, _guard, _bandit, _raider, _neutral]:
		party.battle_state = PartyData.BattleState.AVAILABLE
		party.current_order = PartyData.OrderType.NONE
		party.current_target_id = ""
		party.world_position = Vector2(1000.0, 1000.0)
		party.target_position = party.world_position
		party.movement_state = PartyData.MovementState.IDLE
	_ensure_party_units(_player, 2)
	_ensure_party_units(_merchant, 2)
	_ensure_party_units(_guard, 2)
	_ensure_party_units(_bandit, 2)
	_ensure_party_units(_raider, 2)
	_ensure_party_units(_neutral, 1)


func _ensure_party_units(party: PartyData, count: int) -> void:
	while party.member_unit_ids.size() < count:
		var unit := _units.create_unit(_militia, party.faction_id)
		if not _parties.add_member(party.party_id, unit.unit_id):
			push_error("测试补员失败: %s" % party.party_id)
			return


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[multi] OK: %s" % message)
	else:
		_failed = true
		push_error("[multi] FAIL: %s" % message)


func _cleanup() -> void:
	if _battle != null:
		for session: BattleSession in _battle.get_active_battles():
			_battle.finish_battle(
				session.battle_id, BattleSession.BattleResult.ABORTED
			)
	GameManager.world_context = null
	GameManager.player_party_id = ""
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	if is_instance_valid(_battle_scene):
		_battle_scene.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
