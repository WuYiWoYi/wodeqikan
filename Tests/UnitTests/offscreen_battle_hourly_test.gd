extends Node
## 离屏战斗按游戏小时结算测试。
## 覆盖：1 小时门槛、双方伤亡、兵种等级影响、人数不为负、
## 玩家加入保留伤亡、加入后不再进行离屏结算。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/offscreen_battle_hourly_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"
const VETERAN_PATH: String = "res://Data/Units/infantry_veteran.tres"

var _failed: bool = false
var _ids: IdGenerator = null
var _units: UnitManager = null
var _parties: PartyManager = null
var _factions: FactionManager = null
var _battle: BattleManager = null
var _militia: UnitConfig = null
var _veteran: UnitConfig = null


func _ready() -> void:
	_run()
	_cleanup()
	if _failed:
		push_error("[offscreen] 测试失败")
		get_tree().quit(1)
	else:
		print("[offscreen] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	_militia = load(MILITIA_PATH) as UnitConfig
	_veteran = load(VETERAN_PATH) as UnitConfig
	_check(_militia != null and _veteran != null, "加载兵种配置")
	if _militia == null or _veteran == null:
		return
	_setup_fixture()
	_test_hourly_gate_and_casualties()
	_test_tier_affects_casualties()
	_test_player_join_preserves_casualties()
	_test_battle_ends_by_annihilation()
	_test_living_side_count_ignores_empty_sides()
	_test_parallel_offscreen_battles()


func _setup_fixture() -> void:
	_ids = IdGenerator.new()
	_units = UnitManager.new()
	_units.setup(_ids)
	_parties = PartyManager.new()
	_parties.setup(_units, _ids)
	_factions = FactionManager.new()
	_factions.setup_defaults(_parties)
	_battle = BattleManager.new()
	_battle.setup(_units, _parties, _ids, _factions)

	var config := OffscreenBattleConfig.new()
	# 1x 下 2 世界秒 = 1 游戏小时。
	config.settlement_interval_world_seconds = 2.0
	config.base_hourly_casualty_fraction = 0.2
	config.casualty_variance = 0.0
	config.random_seed = 20261121
	_battle.set_offscreen_config(config)


func _test_hourly_gate_and_casualties() -> void:
	var merchant := _make_party(
		FactionManager.MERCHANT_FACTION_ID, _militia, 5, "小时商队"
	)
	var bandit := _make_party(
		FactionManager.BANDIT_FACTION_ID, _militia, 5, "小时强盗"
	)
	var session := _battle.start_battle(
		[merchant.party_id], [bandit.party_id], Vector2(1000.0, 1000.0), true
	)
	_check(session != null and session.offscreen, "创建离屏战斗")
	if session == null:
		return

	_battle.tick(1.9)
	_check(session.offscreen_settlements_done == 0, "不足 1 个游戏小时不结算")
	_check(_alive_count(session) == 10, "未到结算时间没有伤亡")

	_battle.tick(0.1)
	_check(session.offscreen_settlements_done == 1, "满 1 个游戏小时结算一次")
	_check(session.offscreen_settlement_accumulator < 0.001, "结算后清空小时累计")
	_check(_alive_count(session) < 10, "小时结算产生伤亡")
	_check(_alive_count(session) >= 0, "伤亡不会导致负人数")
	_check(_all_hp_non_negative(session), "所有战斗单位 HP 不为负")
	_check(session.offscreen_casualty_credit.has(0), "记录战斗侧小数伤亡累计")
	_check(
		merchant.member_unit_ids.size() < 5
		and bandit.member_unit_ids.size() < 5,
		"小时伤亡立即更新双方部队成员列表"
	)
	_check(
		_context_units_retained(session),
		"阵亡单位 UnitData 保留到最终结算"
	)

	_battle.resolve_current_battle_now()
	_check(session.status == BattleSession.Status.ENDED, "战斗最终结束")
	_check(session.final_result != null and session.final_result.finalized,
		"离屏战斗生成 finalized 结果")
	_check(_battle.get_battle(session.battle_id) == null, "结算后清理战斗注册表")


func _test_tier_affects_casualties() -> void:
	var militia_party := _make_party(
		FactionManager.MERCHANT_FACTION_ID, _militia, 5, "民兵方"
	)
	var veteran_party := _make_party(
		FactionManager.BANDIT_FACTION_ID, _veteran, 5, "精锐方"
	)
	var session := _battle.start_battle(
		[militia_party.party_id], [veteran_party.party_id],
		Vector2(1000.0, 1000.0), true
	)
	_check(session != null, "创建民兵对精锐离屏战斗")
	if session == null:
		return

	_battle.tick(2.0)
	var militia_alive: int = _side_alive_count(session, 0)
	var veteran_alive: int = _side_alive_count(session, 1)
	_check(militia_alive < 5, "低阶部队承受伤亡")
	_check(veteran_alive > militia_alive, "精锐部队在同等人数下伤亡更少")

	_battle.resolve_current_battle_now()
	_check(session.final_result != null, "等级影响测试战斗完成结算")


func _test_player_join_preserves_casualties() -> void:
	var merchant := _make_party(
		FactionManager.MERCHANT_FACTION_ID, _militia, 6, "待加入商队"
	)
	var bandit := _make_party(
		FactionManager.BANDIT_FACTION_ID, _militia, 6, "待加入强盗"
	)
	var player := _make_party(
		FactionManager.PLAYER_FACTION_ID, _militia, 3, "加入玩家"
	)
	_battle.player_party_id = player.party_id
	var battle_position := Vector2(1200.0, 1000.0)
	var session := _battle.start_battle(
		[merchant.party_id], [bandit.party_id], battle_position, true
	)
	_check(session != null, "创建可加入离屏战斗")
	if session == null:
		return
	_battle.tick(2.0)
	var alive_before_join: int = _alive_count(session)
	var existing_states: Dictionary = {}
	for unit_id: String in session.get_all_unit_ids():
		var state := session.get_unit_state(unit_id)
		if state != null:
			existing_states[unit_id] = [state.alive, state.battle_hp]
	var settlements_before: int = session.offscreen_settlements_done
	_check(alive_before_join < 12, "加入前已经发生离屏伤亡")

	player.world_position = battle_position
	_check(
		_battle.try_join_battle(player.party_id, session.battle_id),
		"玩家中途加入离屏战斗"
	)
	_check(not session.offscreen and session.player_involved,
		"玩家加入后转换为屏幕战斗")
	var existing_preserved: bool = true
	for unit_id_value: Variant in existing_states.keys():
		var unit_id: String = str(unit_id_value)
		var state := session.get_unit_state(unit_id)
		var before: Array = existing_states[unit_id_value]
		if state == null or state.alive != bool(before[0]) \
				or state.battle_hp != int(before[1]):
			existing_preserved = false
			break
	_check(existing_preserved, "原参战单位的伤亡与剩余 HP 在转换后完全保留")
	_check(session.get_side_of_party(player.party_id) == 0,
		"玩家按阵营关系加入商队一侧")

	_battle.tick(60.0)
	_check(session.offscreen_settlements_done == settlements_before,
		"转换为屏幕战斗后不再进行离屏小时结算")
	_check(_battle.get_battle(session.battle_id) == session, "屏幕战斗不会被离屏计时结算")

	_battle.finish_battle(session.battle_id, BattleSession.BattleResult.DRAW)


func _test_battle_ends_by_annihilation() -> void:
	var merchant := _make_party(
		FactionManager.MERCHANT_FACTION_ID, _militia, 4, "全灭商队"
	)
	var bandit := _make_party(
		FactionManager.BANDIT_FACTION_ID, _militia, 4, "全灭强盗"
	)
	var session := _battle.start_battle(
		[merchant.party_id], [bandit.party_id], Vector2(1000.0, 1000.0), true
	)
	_check(session != null, "创建全灭测试战斗")
	if session == null:
		return
	var guard: int = 0
	while _battle.get_battle(session.battle_id) == session and guard < 100:
		_battle.tick(2.0)
		guard += 1
	_check(_battle.get_battle(session.battle_id) == null, "一方全灭后自动结束战斗")
	_check(session.final_result != null, "全灭战斗生成结果")
	var living_sides: int = 0
	for side_index: int in session.get_side_indices():
		if _side_alive_count(session, side_index) > 0:
			living_sides += 1
	_check(living_sides <= 1, "战斗结束时最多只剩一个战斗侧")


## 一方 0 人、另一方存活时，存活侧数量必须为 1，并立即结束战斗。
func _test_living_side_count_ignores_empty_sides() -> void:
	var merchant := _make_party(
		FactionManager.MERCHANT_FACTION_ID, _militia, 4, "单边存活商队"
	)
	var bandit := _make_party(
		FactionManager.BANDIT_FACTION_ID, _militia, 2, "全灭强盗"
	)
	var session := _battle.start_battle(
		[merchant.party_id], [bandit.party_id], Vector2(1000.0, 1000.0), true
	)
	_check(session != null, "创建单边存活测试战斗")
	if session == null:
		return
	for unit_id: String in session.get_side_unit_ids(1):
		var state := session.get_unit_state(unit_id)
		if state != null:
			state.alive = false
			state.battle_hp = 0
	var resolver := OffscreenBattleResolver.new()
	resolver.setup(_battle.offscreen_config)
	_check(
		resolver.count_living_sides(session) == 1,
		"0 人战斗侧不计入存活侧数量"
	)

	_battle.tick(2.0)
	_check(
		_battle.get_battle(session.battle_id) == null
		and session.status == BattleSession.Status.ENDED,
		"一方全灭后离屏战斗立即结束"
	)
	_check(
		session.winning_side_index == 0,
		"存活方判定为胜利方"
	)
	_check(
		session.final_result != null and session.final_result.finalized,
		"单边全灭生成 finalized 结果"
	)

	# 双方同时全灭：按平局结束。
	var a := _make_party(FactionManager.MERCHANT_FACTION_ID, _militia, 2, "同时全灭 A")
	var b := _make_party(FactionManager.BANDIT_FACTION_ID, _militia, 2, "同时全灭 B")
	var draw_session := _battle.start_battle(
		[a.party_id], [b.party_id], Vector2(1100.0, 1000.0), true
	)
	_check(draw_session != null, "创建双方全灭测试战斗")
	if draw_session != null:
		for unit_id: String in draw_session.get_all_unit_ids():
			var state := draw_session.get_unit_state(unit_id)
			if state != null:
				state.alive = false
				state.battle_hp = 0
		_battle.tick(2.0)
		_check(
			_battle.get_battle(draw_session.battle_id) == null,
			"双方全灭时立即结束"
		)
		_check(
			draw_session.result == BattleSession.BattleResult.DRAW,
			"双方全灭按平局处理"
		)


## 两场离屏战斗在同一 tick 内独立推进，结束一场不影响另一场。
func _test_parallel_offscreen_battles() -> void:
	var merchant_a := _make_party(
		FactionManager.MERCHANT_FACTION_ID, _militia, 4, "并行商队 A"
	)
	var bandit_a := _make_party(
		FactionManager.BANDIT_FACTION_ID, _militia, 4, "并行强盗 A"
	)
	var merchant_b := _make_party(
		FactionManager.MERCHANT_FACTION_ID, _militia, 4, "并行商队 B"
	)
	var bandit_b := _make_party(
		FactionManager.BANDIT_FACTION_ID, _militia, 4, "并行强盗 B"
	)
	var first := _battle.start_battle(
		[merchant_a.party_id], [bandit_a.party_id], Vector2(1400.0, 1000.0), true
	)
	var second := _battle.start_battle(
		[merchant_b.party_id], [bandit_b.party_id], Vector2(1600.0, 1000.0), true
	)
	_check(first != null and second != null, "同时创建两场离屏战斗")
	if first == null or second == null:
		return
	_check(_battle.get_active_battles().size() == 2, "两场战斗同时存在")

	_battle.tick(2.0)
	_check(
		first.offscreen_settlements_done == 1
		and second.offscreen_settlements_done == 1,
		"同一世界 tick 推进两场战斗"
	)
	var second_alive_before: int = _alive_count(second)
	var second_states_before: Dictionary = _snapshot_states(second)

	_battle.finish_battle(
		first.battle_id, BattleSession.BattleResult.ATTACKER_VICTORY
	)
	_check(
		_battle.get_battle(first.battle_id) == null
		and _battle.get_battle(second.battle_id) == second,
		"结束第一场后第二场仍在进行"
	)
	_check(
		_alive_count(second) == second_alive_before
		and _states_equal(second, second_states_before),
		"结算第一场不改变第二场的伤亡与本场状态"
	)
	_check(
		bandit_b.battle_state == PartyData.BattleState.IN_BATTLE,
		"第二场参战部队保持锁定"
	)

	_battle.finish_battle(second.battle_id, BattleSession.BattleResult.DRAW)
	_check(
		not _battle.has_any_active_battles(),
		"第二场结算后全部清空"
	)


func _snapshot_states(session: BattleSession) -> Dictionary:
	var result: Dictionary = {}
	for unit_id: String in session.get_all_unit_ids():
		var state := session.get_unit_state(unit_id)
		if state != null:
			result[unit_id] = [state.alive, state.battle_hp]
	return result


func _states_equal(session: BattleSession, snapshot: Dictionary) -> bool:
	for unit_id_value: Variant in snapshot.keys():
		var unit_id: String = str(unit_id_value)
		var state := session.get_unit_state(unit_id)
		var before: Array = snapshot[unit_id_value]
		if state == null or state.alive != bool(before[0]) \
				or state.battle_hp != int(before[1]):
			return false
	return true


func _make_party(
	faction_id: String, config: UnitConfig, count: int, party_name: String
) -> PartyData:
	var party := _parties.create_party(faction_id, Vector2(1000.0, 1000.0), party_name)
	party.movement_speed = 100.0
	party.sight_range = 300.0
	for i: int in range(count):
		var unit := _units.create_unit(config, faction_id)
		_parties.add_member(party.party_id, unit.unit_id)
	return party


func _alive_count(session: BattleSession) -> int:
	var count: int = 0
	for side_index: int in session.get_side_indices():
		count += _side_alive_count(session, side_index)
	return count


func _side_alive_count(session: BattleSession, side_index: int) -> int:
	var count: int = 0
	for unit_id: String in session.get_side_unit_ids(side_index):
		var state := session.get_unit_state(unit_id)
		if state != null and state.alive and state.battle_hp > 0:
			count += 1
	return count


func _all_hp_non_negative(session: BattleSession) -> bool:
	for value: Variant in session.unit_states.values():
		var state := value as BattleUnitState
		if state != null and state.battle_hp < 0:
			return false
	return true


func _context_units_retained(session: BattleSession) -> bool:
	for value: Variant in session.unit_states.values():
		var state := value as BattleUnitState
		if state != null and not state.alive and _units.get_unit(state.unit_id) == null:
			return false
	return true


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[offscreen] OK: %s" % message)
	else:
		_failed = true
		push_error("[offscreen] FAIL: %s" % message)


func _cleanup() -> void:
	if _battle != null:
		for session: BattleSession in _battle.get_active_battles():
			_battle.finish_battle(
				session.battle_id, BattleSession.BattleResult.ABORTED
			)
	TimeManager.clear_pauses()
