extends Node
## BattleManager 单元测试：开始校验、锁定、失败结算、重复结算。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/battle_manager_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"
const FACTION_A: String = "FACTION_A"
const FACTION_B: String = "FACTION_B"

var _failed: bool = false


func _ready() -> void:
	_run()
	if _failed:
		push_error("[bm] 测试失败")
		get_tree().quit(1)
	else:
		print("[bm] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	var militia: UnitConfig = load(MILITIA_PATH) as UnitConfig
	_check(militia != null, "加载民兵配置")
	if militia == null:
		return

	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)

	var ids := IdGenerator.new()
	var units := UnitManager.new()
	units.setup(ids)
	var parties := PartyManager.new()
	parties.setup(units, ids)
	var battle_manager := BattleManager.new()
	battle_manager.setup(units, parties, ids)

	var party_a := parties.create_party(FACTION_A, Vector2.ZERO, "A 队")
	var party_b := parties.create_party(FACTION_B, Vector2.ZERO, "B 队")
	var empty_a := parties.create_party(FACTION_A, Vector2.ZERO, "空 A")
	var empty_b := parties.create_party(FACTION_B, Vector2.ZERO, "空 B")
	_check(party_a != null and party_b != null, "创建双方部队")
	if party_a == null or party_b == null:
		return

	var attacks_a: Array[String] = [party_a.party_id]
	var attacks_b: Array[String] = [party_b.party_id]
	_check(
		battle_manager.start_battle(attacks_a, attacks_b, Vector2.ZERO) == null,
		"双方无士兵时拒绝开战"
	)
	_check(
		battle_manager.start_battle(
			[empty_a.party_id], [empty_b.party_id], Vector2.ZERO
		) == null,
		"空部队拒绝开战"
	)
	_check(
		battle_manager.start_battle(attacks_a, attacks_a, Vector2.ZERO) == null,
		"同一部队不能同时作为双方"
	)

	var unit_a1 := units.create_unit(militia, FACTION_A)
	var unit_a2 := units.create_unit(militia, FACTION_A)
	var unit_b1 := units.create_unit(militia, FACTION_B)
	var unit_b2 := units.create_unit(militia, FACTION_B)
	for unit: UnitData in [unit_a1, unit_a2]:
		parties.add_member(party_a.party_id, unit.unit_id)
	for unit: UnitData in [unit_b1, unit_b2]:
		parties.add_member(party_b.party_id, unit.unit_id)

	var same_faction := parties.create_party(FACTION_A, Vector2.ZERO, "同阵营")
	var same_unit := units.create_unit(militia, FACTION_A)
	parties.add_member(same_faction.party_id, same_unit.unit_id)
	_check(
		battle_manager.start_battle(
			attacks_a, [same_faction.party_id], Vector2.ZERO
		) == null,
		"同阵营拒绝开战"
	)

	var session := battle_manager.start_battle(attacks_a, attacks_b, Vector2.ZERO)
	_check(session != null, "合法双方创建战斗会话")
	if session == null:
		return
	_check(session.attacker_unit_ids.size() == 2, "进攻方 2 名士兵")
	_check(session.defender_unit_ids.size() == 2, "防守方 2 名士兵")
	_check(party_a.battle_state == PartyData.BattleState.IN_BATTLE, "进攻方锁定")
	_check(party_b.battle_state == PartyData.BattleState.IN_BATTLE, "防守方锁定")
	_check(is_zero_approx(TimeManager.get_effective_world_scale()), "战斗期间世界暂停")
	_check(
		battle_manager.start_battle(attacks_a, attacks_b, Vector2.ZERO) == null,
		"已有战斗时拒绝重复开始"
	)

	# 玩家战败结算：进攻方全灭，防守方保留剩余 HP。
	for unit_id: String in session.attacker_unit_ids:
		var state := session.get_unit_state(unit_id)
		state.battle_hp = 0
		state.alive = false
	var survivor_state := session.get_unit_state(unit_b1.unit_id)
	survivor_state.battle_hp = 7

	_check(
		battle_manager.finish_battle(
			session.battle_id, BattleSession.BattleResult.DEFENDER_VICTORY
		),
		"战败结算成功"
	)
	_check(battle_manager.current_battle == null, "结算后清理会话")
	_check(party_a.member_unit_ids.is_empty(), "战败方成员全部移除")
	_check(units.get_unit(unit_a1.unit_id) == null, "战败方单位数据删除 1")
	_check(units.get_unit(unit_a2.unit_id) == null, "战败方单位数据删除 2")
	_check(party_b.member_unit_ids.size() == 2, "胜利方成员保留")
	_check(units.get_unit(unit_b1.unit_id).current_hp == 7, "胜利方写回剩余 HP")
	_check(units.get_unit(unit_b2.unit_id).current_hp == 50, "未受伤单位保持满血")
	_check(party_a.battle_state == PartyData.BattleState.DISABLED, "战败方全员阵亡后失效")
	_check(party_b.battle_state == PartyData.BattleState.AVAILABLE, "胜利方解锁")
	_check(
		is_equal_approx(TimeManager.get_effective_world_scale(), TimeManager.SPEED_NORMAL),
		"结算后恢复世界时间"
	)
	_check(
		not battle_manager.finish_battle(
			session.battle_id, BattleSession.BattleResult.DEFENDER_VICTORY
		),
		"不能重复结算"
	)

	TimeManager.stop_session()
	TimeManager.clear_pauses()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[bm] OK: %s" % message)
	else:
		_failed = true
		push_error("[bm] FAIL: %s" % message)
