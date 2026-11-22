extends Node
## 阶段 13 Step 4 测试：伤兵按 WorldTime 顺序恢复。
## 覆盖每游戏小时治疗点数（基础 + 药物预留）、成员顺序与溢出结转、
## 暂停/同一小时不重复结算、1x/2x 都按游戏小时、玩家与 NPC 同规则、
## 已移除部队不治疗、战斗中不治疗、伤兵恢复后回到正常状态、读档不补发。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/UnitTests/wounded_healing_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"
const SECONDS_PER_HOUR: float = 6.0

var _failed: bool = false
var _militia: UnitConfig = null
var _ids: IdGenerator = null
var _units: UnitManager = null
var _parties: PartyManager = null
var _healing: WoundedHealingManager = null


func _ready() -> void:
	_run()
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	if _failed:
		push_error("[healing] 测试失败")
		get_tree().quit(1)
	else:
		print("[healing] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	_militia = load(MILITIA_PATH) as UnitConfig
	_check(_militia != null, "加载兵种配置")
	if _militia == null:
		return

	_test_config_values()
	_test_member_order_and_overflow()
	_test_order_skips_full_units()
	_test_hourly_settlement_and_no_double_settle()
	_test_paused_does_not_heal()
	_test_speed_multiplier_same_per_game_hour()
	_test_all_parties_and_removed_party()
	_test_in_battle_party_not_healed()
	_test_wounded_recovers_to_active()
	_test_disabled_party_reenabled()
	_test_restore_does_not_backfill()


# ---------------------------------------------------------------------------
# 配置
# ---------------------------------------------------------------------------


func _test_config_values() -> void:
	var config := load(
		"res://Data/Combat/healing_config.tres"
	) as HealingConfig
	_check(config != null, "加载治疗配置")
	if config == null:
		return
	_check(config.get_healing_per_hour() == 1, "默认每游戏小时 1 点")
	config.medicine_healing_bonus = 3
	_check(config.get_healing_per_hour() == 4, "药物加成进入统一治疗点数")
	config.base_healing_per_hour = -5
	config.medicine_healing_bonus = -2
	config.sanitize()
	_check(config.get_healing_per_hour() == 0, "负值被归一化为 0")


# ---------------------------------------------------------------------------
# 顺序与溢出
# ---------------------------------------------------------------------------


func _test_member_order_and_overflow() -> void:
	_reset_managers()
	var party := _make_party(FactionManager.PLAYER_FACTION_ID, "顺序治疗")
	var unit_a := _add_unit(party, 98, 100)
	var unit_b := _add_unit(party, 90, 100)

	var result := _healing.apply_healing_to_party(party, 12)
	_check(result["points_used"] == 12, "12 点全部用完")
	_check(
		unit_a.current_hp == 100 and unit_b.current_hp == 100,
		"先补满 A 再补 B：98/100 + 90/100 + 12 → 100/100 + 100/100"
	)
	_check(
		result["healed_unit_ids"] == [unit_a.unit_id, unit_b.unit_id],
		"按成员顺序记录治疗单位"
	)

	# 成员顺序改变时，溢出目标同样改变。
	var party_reordered := _make_party(FactionManager.PLAYER_FACTION_ID, "换序治疗")
	var first := _add_unit(party_reordered, 90, 100)
	var second := _add_unit(party_reordered, 98, 100)
	_move_member_to_front(party_reordered, second.unit_id)
	result = _healing.apply_healing_to_party(party_reordered, 3)
	_check(
		second.current_hp == 100 and first.current_hp == 91,
		"按新的成员顺序依次补血（3 点：满前一个再下一个）"
	)


func _test_order_skips_full_units() -> void:
	_reset_managers()
	var party := _make_party(FactionManager.PLAYER_FACTION_ID, "跳过满血")
	var full := _add_unit(party, 100, 100)
	var hurt := _add_unit(party, 90, 100)
	var untouched := _add_unit(party, 80, 100)

	var result := _healing.apply_healing_to_party(party, 10)
	_check(full.current_hp == 100, "满血单位不消耗治疗点")
	_check(hurt.current_hp == 100, "治疗点全部给第一个受伤单位")
	_check(untouched.current_hp == 80, "溢出为 0 时后续单位不恢复")
	_check(
		result["healed_unit_ids"] == [hurt.unit_id],
		"只记录实际恢复的单位"
	)

	# 剩余治疗点继续按顺序补给下一个受伤单位。
	result = _healing.apply_healing_to_party(party, 25)
	_check(
		untouched.current_hp == 100 and result["points_used"] == 20,
		"溢出点继续给后续受伤单位，满血后丢弃多余点"
	)

	# 全体满血时多余点数直接丢弃。
	result = _healing.apply_healing_to_party(party, 5)
	_check(result["points_used"] == 0, "全满时治疗点丢弃")


# ---------------------------------------------------------------------------
# WorldTime 结算
# ---------------------------------------------------------------------------


func _test_hourly_settlement_and_no_double_settle() -> void:
	_reset_managers()
	var party := _make_party(FactionManager.PLAYER_FACTION_ID, "每小时治疗")
	var unit := _add_unit(party, 0, 100)
	unit.mark_wounded()

	_set_world_seconds(0.0)
	_healing.last_settled_hour = -1
	_check(_healing.tick() == 0, "首次 tick 只记录起点，不补发历史")
	_check(unit.current_hp == 0, "初始化小时不治疗")

	_set_world_seconds(SECONDS_PER_HOUR)
	_check(_healing.tick() == 1, "跨过 1 个游戏小时")
	_check(unit.current_hp == 1, "每小时获得 1 点治疗")

	# 同一小时内再次 tick 不重复结算。
	_check(_healing.tick() == 0, "同一小时再次 tick 不结算")
	_check(unit.current_hp == 1, "同一小时不会重复治疗")

	# 一次跨 3 小时（例如卡顿/加速）按小时补算。
	_set_world_seconds(SECONDS_PER_HOUR * 4.0)
	_check(_healing.tick() == 3, "一次跨过 3 个游戏小时")
	_check(unit.current_hp == 4, "跨多小时按小时累计治疗")

	# 跨小时但未满整小时不结算。
	_set_world_seconds(SECONDS_PER_HOUR * 4.0 + 2.0)
	_check(_healing.tick() == 0, "未到下一个整小时不结算")
	_check(unit.current_hp == 4, "未满整小时不产生治疗")


func _test_paused_does_not_heal() -> void:
	_reset_managers()
	var party := _make_party(FactionManager.PLAYER_FACTION_ID, "暂停部队")
	var unit := _add_unit(party, 0, 100)
	unit.mark_wounded()

	_set_world_seconds(0.0)
	_healing.last_settled_hour = -1
	_healing.tick()
	# 暂停时 TimeManager 不推进 world_elapsed_seconds，WorldSimulation 也不 tick。
	TimeManager.push_pause(&"test_pause")
	_check(_healing.tick() == 0, "暂停时没有新的游戏小时")
	_check(unit.current_hp == 0, "暂停期间不恢复")
	TimeManager.pop_pause(&"test_pause")

	# 恢复后按实际游戏小时继续，不会补发暂停期间的现实时间。
	_set_world_seconds(SECONDS_PER_HOUR)
	_check(_healing.tick() == 1, "恢复后正常跨小时")
	_check(unit.current_hp == 1, "恢复后只按游戏小时治疗")


func _test_speed_multiplier_same_per_game_hour() -> void:
	_reset_managers()
	var party := _make_party(FactionManager.PLAYER_FACTION_ID, "倍率部队")
	var unit := _add_unit(party, 0, 100)
	unit.mark_wounded()

	# 1x：推进 2 个游戏小时。
	_set_world_seconds(0.0)
	_healing.last_settled_hour = -1
	_healing.tick()
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)
	_set_world_seconds(SECONDS_PER_HOUR * 2.0)
	_healing.tick()
	var normal_hp: int = unit.current_hp
	_check(normal_hp == 2, "1 倍速 2 小时治疗 2 点")

	# 2x：同样推进 2 个游戏小时。
	unit.current_hp = 0
	unit.status = UnitData.Status.WOUNDED
	_set_world_seconds(0.0)
	_healing.last_settled_hour = -1
	_healing.tick()
	TimeManager.set_base_world_speed(TimeManager.SPEED_DOUBLE)
	_set_world_seconds(SECONDS_PER_HOUR * 2.0)
	_healing.tick()
	_check(unit.current_hp == normal_hp, "2 倍速同样按游戏小时治疗，结果一致")
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)


# ---------------------------------------------------------------------------
# 部队范围
# ---------------------------------------------------------------------------


func _test_all_parties_and_removed_party() -> void:
	_reset_managers()
	var player := _make_party(FactionManager.PLAYER_FACTION_ID, "玩家部队")
	var player_unit := _add_unit(player, 0, 100)
	player_unit.mark_wounded()
	var npc := _make_party(FactionManager.BANDIT_FACTION_ID, "NPC 部队")
	var npc_unit := _add_unit(npc, 0, 100)
	npc_unit.mark_wounded()
	var removed := _make_party(FactionManager.BANDIT_FACTION_ID, "已移除部队")
	var removed_unit := _add_unit(removed, 0, 100)
	removed_unit.mark_wounded()

	_check(_parties.remove_party(removed.party_id), "移除部队")

	_set_world_seconds(0.0)
	_healing.last_settled_hour = -1
	_healing.tick()
	_set_world_seconds(SECONDS_PER_HOUR)
	_healing.tick()

	_check(player_unit.current_hp == 1, "玩家部队获得治疗")
	_check(npc_unit.current_hp == 1, "NPC 部队使用同一规则获得治疗")
	_check(removed_unit.current_hp == 0, "已移除部队不治疗")


func _test_in_battle_party_not_healed() -> void:
	_reset_managers()
	var party := _make_party(FactionManager.PLAYER_FACTION_ID, "战斗中部队")
	var unit := _add_unit(party, 0, 100)
	unit.mark_wounded()
	party.battle_state = PartyData.BattleState.IN_BATTLE

	var result := _healing.apply_healing_to_party(party, 10)
	_check(result["points_used"] == 0, "战斗中不修改 HP")
	_check(unit.current_hp == 0, "战斗中伤兵不恢复")

	party.battle_state = PartyData.BattleState.AVAILABLE
	_healing.apply_healing_to_party(party, 10)
	_check(unit.current_hp == 10, "脱离战斗后恢复治疗")


# ---------------------------------------------------------------------------
# 状态与可用性
# ---------------------------------------------------------------------------


func _test_wounded_recovers_to_active() -> void:
	_reset_managers()
	var party := _make_party(FactionManager.PLAYER_FACTION_ID, "伤兵恢复")
	var unit := _add_unit(party, 0, 3)
	unit.mark_wounded()
	_check(unit.status == UnitData.Status.WOUNDED, "治疗前是伤兵")
	_check(not unit.is_alive(), "治疗前无法战斗")

	var result := _healing.apply_healing_to_party(party, 2)
	_check(unit.current_hp == 2, "恢复部分 HP")
	_check(
		unit.status == UnitData.Status.ACTIVE and unit.is_alive(),
		"HP 恢复为有效值后立即回到正常状态"
	)

	_healing.apply_healing_to_party(party, 5)
	_check(unit.current_hp == 3, "恢复上限为最大 HP")
	_check(result["points_used"] == 2, "部分治疗点数记录正确")


func _test_disabled_party_reenabled() -> void:
	_reset_managers()
	var party := _make_party(FactionManager.PLAYER_FACTION_ID, "仅剩伤兵")
	var unit := _add_unit(party, 0, 2)
	unit.mark_wounded()
	party.battle_state = PartyData.BattleState.DISABLED

	# 没有治疗点时不改变部队可用性。
	_healing.apply_healing_to_party(party, 0)
	_check(
		party.battle_state == PartyData.BattleState.DISABLED,
		"未恢复 HP 时保持停止行动"
	)

	# HP 恢复为有效值后，部队重新加入世界行动。
	_healing.apply_healing_to_party(party, 1)
	_check(
		party.battle_state == PartyData.BattleState.AVAILABLE,
		"出现可战斗成员后部队恢复行动"
	)


# ---------------------------------------------------------------------------
# 读档
# ---------------------------------------------------------------------------


func _test_restore_does_not_backfill() -> void:
	_reset_managers()
	var party := _make_party(FactionManager.PLAYER_FACTION_ID, "读档部队")
	var unit := _add_unit(party, 0, 100)
	unit.mark_wounded()

	# 存档记录：世界已走过 10 小时，最后一小时已结算。
	_set_world_seconds(SECONDS_PER_HOUR * 10.0)
	_healing.restore_settled_hour(10, SECONDS_PER_HOUR * 10.0)
	_check(_healing.tick() == 0, "读档后同一小时不重复结算")
	_check(unit.current_hp == 0, "读档不会补发已结算小时")

	_set_world_seconds(SECONDS_PER_HOUR * 11.0)
	_healing.tick()
	_check(unit.current_hp == 1, "读档后只结算新的游戏小时")

	# 旧存档没有 healing_last_settled_hour：以存档时刻为起点。
	_reset_managers()
	var legacy_party := _make_party(FactionManager.PLAYER_FACTION_ID, "旧存档部队")
	var legacy_unit := _add_unit(legacy_party, 0, 100)
	legacy_unit.mark_wounded()
	_set_world_seconds(SECONDS_PER_HOUR * 50.0)
	_healing.restore_settled_hour(-1, SECONDS_PER_HOUR * 50.0)
	_check(_healing.tick() == 0, "旧存档首 tick 不补发")
	_check(legacy_unit.current_hp == 0, "旧存档不会一次性补发 50 小时治疗")


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------


func _reset_managers() -> void:
	_ids = IdGenerator.new()
	_units = UnitManager.new()
	_units.setup(_ids)
	_units.register_unit_config(_militia)
	_parties = PartyManager.new()
	_parties.setup(_units, _ids)
	_healing = WoundedHealingManager.new()
	var config := HealingConfig.create_default()
	config.base_healing_per_hour = 1
	config.medicine_healing_bonus = 0
	_healing.setup(_parties, _units, config)


func _set_world_seconds(seconds: float) -> void:
	TimeManager.restore_world_time(seconds, TimeManager.SPEED_NORMAL)


func _make_party(faction_id: String, party_name: String) -> PartyData:
	return _parties.create_party(faction_id, Vector2.ZERO, party_name)


func _add_unit(party: PartyData, hp: int, max_hp: int) -> UnitData:
	var unit := _units.create_unit(_militia, party.faction_id)
	_check(unit != null and _parties.add_member(party.party_id, unit.unit_id),
		"创建并加入单位")
	if unit == null:
		return null
	unit.max_hp = max_hp
	unit.current_hp = hp
	unit.clamp_hp()
	return unit


func _move_member_to_front(party: PartyData, unit_id: String) -> void:
	party.member_unit_ids.erase(unit_id)
	party.member_unit_ids.insert(0, unit_id)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[healing] OK: %s" % message)
	else:
		_failed = true
		push_error("[healing] FAIL: %s" % message)
