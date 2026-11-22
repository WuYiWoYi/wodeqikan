extends Node
## 阶段 13 Step 5 测试：俘虏分配、战后选择与归属。
## 覆盖最大余数法、真实参战人数（含增援）、玩家胜利/失败流程、
## 战后界面预览/重置/确认、重复提交防护、存档读档与归属一致性。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/stage13_prisoner_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"
const HERO_PATH: String = "res://Data/Units/player_hero.tres"

var _failed: bool = false
var _militia: UnitConfig = null
var _hero: UnitConfig = null
var _ids: IdGenerator = null
var _units: UnitManager = null
var _parties: PartyManager = null
var _factions: FactionManager = null
var _profile: PlayerProfile = null
var _battle: BattleManager = null


func _ready() -> void:
	_run()
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	if _failed:
		push_error("[prisoner] 测试失败")
		get_tree().quit(1)
	else:
		print("[prisoner] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	_militia = load(MILITIA_PATH) as UnitConfig
	_hero = load(HERO_PATH) as UnitConfig
	_check(_militia != null and _hero != null, "加载兵种配置")
	if _militia == null or _hero == null:
		return

	_setup_managers()
	_test_share_algorithm()
	_test_prisoner_ownership_rules()
	_test_player_victory_allocation()
	_test_player_defeat_all()
	_test_reinforcement_counts()
	_test_selection_panel_preview()
	_test_save_reload_prisoners()


# ---------------------------------------------------------------------------
# 分配算法
# ---------------------------------------------------------------------------


func _test_share_algorithm() -> void:
	# 规格示例：10/20/30，20 名俘虏 → 3/7/10。
	var shares := BattleManager.compute_prisoner_shares(
		20, {"A": 10, "B": 20, "C": 30}
	)
	_check(
		shares["A"] == 3 and shares["B"] == 7 and shares["C"] == 10,
		"最大余数法示例 3/7/10"
	)
	_check(int(shares["A"]) + int(shares["B"]) + int(shares["C"]) == 20, "分配总数等于俘虏数")

	# 只有一支胜利部队。
	shares = BattleManager.compute_prisoner_shares(7, {"ONLY": 5})
	_check(shares["ONLY"] == 7, "单一胜利部队获得全部俘虏")

	# 余数相同：按稳定 party_id 顺序。
	shares = BattleManager.compute_prisoner_shares(1, {"B": 1, "A": 1})
	_check(
		shares["A"] == 1 and shares["B"] == 0,
		"余数相同时按 party_id 稳定顺序分配"
	)

	# 有效参战人数总和为 0：不除零，按稳定 ID 兜底。
	shares = BattleManager.compute_prisoner_shares(5, {"B": 0, "A": 0})
	_check(
		shares["A"] == 5 and shares["B"] == 0,
		"零参战人数按稳定 ID 兜底，不随机"
	)

	# 不能被整除且差异较大：每次总和必须守恒。
	var cases: Array[Dictionary] = [
		{"A": 1, "B": 2},
		{"A": 3, "B": 7},
		{"A": 1, "B": 1, "C": 1},
		{"A": 11, "B": 4, "C": 29, "D": 6},
	]
	for counts: Dictionary in cases:
		for total: int in [1, 2, 5, 17, 41]:
			var result := BattleManager.compute_prisoner_shares(total, counts)
			var sum: int = 0
			for party_id: String in result:
				sum += int(result[party_id])
			_check(sum == total, "分配守恒 P=%d counts=%s" % [total, counts])


# ---------------------------------------------------------------------------
# 归属规则
# ---------------------------------------------------------------------------


func _test_prisoner_ownership_rules() -> void:
	_reset_managers()
	var party := _make_party(FactionManager.BANDIT_FACTION_ID, "关押方")
	var winner := _make_party(FactionManager.PLAYER_FACTION_ID, "胜利方")
	var member := _add_unit(winner, _militia)
	var target := _add_unit(party, _militia)
	target.mark_wounded()
	# 战斗结算会先移除成员关系；这里模拟同一顺序。
	_check(_parties.remove_member(party.party_id, target.unit_id), "被俘单位先移出原部队")

	_check(not _parties.add_prisoner(winner.party_id, member.unit_id), "成员不能同时成为俘虏")
	_check(member.current_party_id == winner.party_id, "失败操作不改变成员归属")

	_check(_parties.add_prisoner(winner.party_id, target.unit_id), "伤兵可以成为俘虏")
	_check(target.is_prisoner(), "Unit 记录俘虏归属")
	_check(target.prisoner_owner_party_id == winner.party_id, "俘虏归属指向胜利方")
	_check(target.current_party_id.is_empty(), "俘虏不再是普通成员")
	_check(winner.prisoner_unit_ids.has(target.unit_id), "胜利方俘虏列表包含该单位")
	_check(not party.member_unit_ids.has(target.unit_id), "原部队成员列表不再包含俘虏")
	_check(not _parties.add_prisoner(party.party_id, target.unit_id), "不能重复关押同一俘虏")

	var second_owner := _make_party(FactionManager.PLAYER_FACTION_ID, "第二胜利方")
	_check(
		_parties.transfer_prisoner(target.unit_id, second_owner.party_id),
		"俘虏可在部队之间转移"
	)
	_check(not winner.prisoner_unit_ids.has(target.unit_id), "转移后旧部队列表移除")
	_check(second_owner.prisoner_unit_ids.has(target.unit_id), "转移后新部队列表包含")
	_check(
		target.prisoner_owner_party_id == second_owner.party_id,
		"转移后 Unit 归属同步"
	)

	_check(_parties.release_prisoner(target.unit_id), "释放俘虏")
	_check(not target.is_prisoner() and second_owner.prisoner_unit_ids.is_empty(), "释放后归属清空")

	# 一致性校验：正常数据无错误。
	_party_add_member_back(party, target)
	_check(
		_parties.validate_membership_consistency().is_empty(),
		"俘虏/成员归属一致"
	)


# ---------------------------------------------------------------------------
# 战斗结算
# ---------------------------------------------------------------------------


func _test_player_victory_allocation() -> void:
	_reset_managers()
	_set_all_wounded_chances(1.0)
	var player := _make_party(FactionManager.PLAYER_FACTION_ID, "玩家部队")
	_add_unit(player, _militia)
	_add_unit(player, _militia)
	var ally := _make_party(FactionManager.PLAYER_FACTION_ID, "友军部队")
	_add_unit(ally, _militia)
	_add_unit(ally, _militia)
	_add_unit(ally, _militia)
	var enemy := _make_party(FactionManager.BANDIT_FACTION_ID, "战败方")
	var enemy_units: Array[UnitData] = []
	for _i: int in range(3):
		enemy_units.append(_add_unit(enemy, _militia))
	_battle.player_party_id = player.party_id

	var session := _battle.start_battle(
		[player.party_id, ally.party_id], [enemy.party_id], Vector2.ZERO
	)
	_check(session != null, "开始多方胜利战斗")
	if session == null:
		return
	_zero_side_hp(session, session.get_side_of_party(enemy.party_id))
	_check(
		_battle.finish_battle(
			session.battle_id, BattleSession.BattleResult.ATTACKER_VICTORY
		),
		"多方战斗结算成功"
	)
	var data := session.final_result
	_check(data != null, "生成战斗结果")
	if data == null:
		return

	_check(data.get_total_prisoners() == 3, "战败方伤兵全部成为俘虏")
	_check(data.get_participant_unit_count(player.party_id) == 2, "玩家有效参战人数 2")
	_check(data.get_participant_unit_count(ally.party_id) == 3, "友军有效参战人数 3")
	# P=3, N=5 → 玩家 6/5=1 余 1；友军 9/5=1 余 4；余 1 给友军 → 1/2。
	_check(
		data.get_prisoners_for_party(player.party_id).size() == 1,
		"玩家按比例分到 1 名俘虏"
	)
	_check(data.get_prisoners_for_party(ally.party_id).size() == 2, "友军分到 2 名俘虏")
	_check(data.player_won, "玩家所在侧获胜")

	# 战败方成员列表不再包含被俘伤兵。
	_check(enemy.member_unit_ids.is_empty(), "被俘单位移出战败部队")
	var ally_prisoners := _parties.get_prisoner_ids(ally.party_id)
	_check(ally_prisoners.size() == 2, "友军已立即接收俘虏")
	for unit_id: String in ally_prisoners:
		var unit := _units.get_unit(unit_id)
		_check(unit != null and unit.is_prisoner() and unit.is_wounded(), "友军俘虏保留伤兵身份")
		_check(unit.prisoner_owner_party_id == ally.party_id, "友军俘虏归属正确")

	_check(
		_battle.has_pending_prisoner_selection(session.battle_id),
		"玩家份额等待战后确认"
	)
	var pending := _battle.get_pending_player_prisoners(session.battle_id)
	_check(pending.size() == 1, "玩家待接收俘虏 1 名")
	_check(player.prisoner_unit_ids.is_empty(), "确认前玩家真实俘虏列表不变")

	var accepted_id: String = pending[0]
	_check(
		_battle.commit_player_prisoners(session.battle_id, [accepted_id]),
		"确认接收玩家俘虏"
	)
	_check(player.prisoner_unit_ids == [accepted_id], "确认后进入玩家俘虏列表")
	var accepted := _units.get_unit(accepted_id)
	_check(accepted.is_prisoner(), "确认后 Unit 归属玩家")
	_check(not player.member_unit_ids.has(accepted_id), "俘虏不进入作战成员列表")
	_check(
		not _battle.has_pending_prisoner_selection(session.battle_id),
		"确认后清除待处理结算"
	)
	_check(
		not _battle.commit_player_prisoners(session.battle_id, [accepted_id]),
		"重复确认不会重复分配"
	)
	_check(player.prisoner_unit_ids.size() == 1, "重复确认不复制俘虏")

	# 所有俘虏只属于一支部队。
	var seen: Dictionary = {}
	for party: PartyData in _parties.get_all_parties():
		for unit_id: String in party.prisoner_unit_ids:
			_check(not seen.has(unit_id), "同一俘虏不会属于多支部队")
			seen[unit_id] = true


func _test_player_defeat_all() -> void:
	_reset_managers()
	_set_all_wounded_chances(1.0)
	var player := _make_party(FactionManager.PLAYER_FACTION_ID, "战败玩家")
	var player_unit := _add_unit(player, _militia)
	_add_unit(player, _militia)
	var enemy := _make_party(FactionManager.BANDIT_FACTION_ID, "胜利强盗")
	_add_unit(enemy, _militia)
	_battle.player_party_id = player.party_id

	var session := _battle.start_battle(
		[player.party_id], [enemy.party_id], Vector2.ZERO
	)
	_check(session != null, "开始玩家战败战斗")
	if session == null:
		return
	_zero_side_hp(session, session.get_side_of_party(player.party_id))
	_battle.finish_battle(session.battle_id, BattleSession.BattleResult.DEFENDER_VICTORY)
	var data := session.final_result
	_check(data != null and data.get_total_prisoners() == 2, "玩家伤兵成为俘虏")
	_check(not data.player_won, "玩家失败")
	_check(
		not _battle.has_pending_prisoner_selection(session.battle_id),
		"失败方不显示俘虏选择界面"
	)
	_check(enemy.prisoner_unit_ids.size() == 2, "胜利强盗立即接收全部俘虏")
	_check(player.member_unit_ids.is_empty(), "玩家被俘单位移出成员列表")
	_check(
		player.battle_state == PartyData.BattleState.DISABLED,
		"全员被俘的部队停止行动"
	)
	_check(player_unit.prisoner_owner_party_id == enemy.party_id, "玩家伤兵归属胜利方")


func _test_reinforcement_counts() -> void:
	_reset_managers()
	_set_all_wounded_chances(1.0)
	var merchant := _make_party(FactionManager.MERCHANT_FACTION_ID, "商队")
	_add_unit(merchant, _militia)
	_add_unit(merchant, _militia)
	var guard := _make_party(FactionManager.GUARD_FACTION_ID, "增援治安队")
	_add_unit(guard, _militia)
	_add_unit(guard, _militia)
	_add_unit(guard, _militia)
	var bandit := _make_party(FactionManager.BANDIT_FACTION_ID, "强盗")
	for _i: int in range(4):
		_add_unit(bandit, _militia)
	_battle.player_party_id = ""
	# 位置相同，增援就近加入。
	merchant.world_position = Vector2(100.0, 100.0)
	bandit.world_position = Vector2(100.0, 100.0)
	guard.world_position = Vector2(100.0, 100.0)

	var session := _battle.start_battle(
		[merchant.party_id], [bandit.party_id], Vector2(100.0, 100.0), true
	)
	_check(session != null, "开始离屏战斗")
	if session == null:
		return
	_check(_battle.try_join_battle(guard.party_id, session.battle_id), "治安队增援加入")
	_zero_side_hp(session, session.get_side_of_party(bandit.party_id))
	_battle.finish_battle(session.battle_id, BattleSession.BattleResult.ATTACKER_VICTORY)
	var data := session.final_result
	_check(data != null, "增援战斗生成结果")
	if data == null:
		return
	_check(data.get_participant_unit_count(merchant.party_id) == 2, "商队实际参战 2")
	_check(data.get_participant_unit_count(guard.party_id) == 3, "增援部队实际参战 3")
	_check(data.get_total_prisoners() == 4, "4 名伤兵成为俘虏")
	# P=4, N=5：商队 8/5=1 余 3；治安队 12/5=2 余 2 → 2/2。
	_check(_parties.get_prisoner_ids(merchant.party_id).size() == 2, "商队分到 2 名")
	_check(_parties.get_prisoner_ids(guard.party_id).size() == 2, "增援部队分到 2 名")
	_check(_parties.get_prisoner_ids(bandit.party_id).size() == 0, "战败方不持有俘虏")


# ---------------------------------------------------------------------------
# UI 预览
# ---------------------------------------------------------------------------


func _test_selection_panel_preview() -> void:
	_reset_managers()
	var party := _make_party(FactionManager.PLAYER_FACTION_ID, "界面玩家")
	var first := _add_unit(party, _militia)
	var second := _add_unit(party, _militia)
	var existing := _add_unit(party, _militia)
	first.mark_wounded()
	second.mark_wounded()
	existing.mark_wounded()
	# 已有俘虏：直接从成员转俘虏。
	_parties.remove_member(party.party_id, existing.unit_id)
	_check(_parties.add_prisoner(party.party_id, existing.unit_id), "准备已有俘虏")

	# 待分配单位必须是真实 Unit，但暂不属于任何部队。
	_parties.remove_member(party.party_id, first.unit_id)
	first.mark_prisoner("")
	_parties.remove_member(party.party_id, second.unit_id)
	second.mark_prisoner("")

	var panel := PrisonerSelectionPanel.new()
	add_child(panel)
	panel.setup(_units, [first.unit_id, second.unit_id], [existing.unit_id])
	_check(panel.get_left_ids().size() == 2, "左侧显示待接收俘虏")
	_check(panel.get_accepted_ids().is_empty(), "初始未选择")
	_check(panel.get_existing_ids() == [existing.unit_id], "右侧显示已有俘虏")

	panel.select_left(first.unit_id)
	_check(panel.get_accepted_ids() == [first.unit_id], "点击左侧加入接收")
	_check(panel.get_left_ids() == [second.unit_id], "接收后从左侧暂时消失")
	_check(not first.is_prisoner(), "未确认不修改真实归属")

	panel.withdraw_accepted(first.unit_id)
	_check(panel.get_accepted_ids().is_empty(), "点击右侧可撤回")
	_check(panel.get_left_ids().size() == 2, "撤回后回到左侧")

	panel.select_left(first.unit_id)
	panel.select_left(second.unit_id)
	panel.reset_selection()
	_check(panel.get_accepted_ids().is_empty(), "一键重置恢复初始状态")
	_check(panel.get_left_ids().size() == 2, "重置后全部回到待接收")

	var emitted: Array[Array] = []
	panel.committed.connect(func(ids: Array) -> void: emitted.append(ids))
	panel.select_left(second.unit_id)
	var confirm := panel.find_child("PrisonerConfirmButton", true, false) as Button
	_check(confirm != null, "存在确认按钮")
	confirm.pressed.emit()
	_check(emitted.size() == 1 and emitted[0] == [second.unit_id], "确认时只提选择结果")
	_check(panel.is_committed(), "确认后界面锁定")
	_check(not second.is_prisoner(), "界面本身不修改真实归属")
	panel.queue_free()


# ---------------------------------------------------------------------------
# 存档读档
# ---------------------------------------------------------------------------


func _test_save_reload_prisoners() -> void:
	var context := WorldContext.new()
	context.name = "PrisonerSaveContext"
	add_child(context)
	_check(WorldInitializer.create_new_world(context), "初始化俘虏存档世界")
	if not context.is_valid_world():
		context.queue_free()
		return
	var party := context.get_player_party()
	var victim: UnitData = null
	for unit_id: String in party.member_unit_ids:
		var candidate := context.unit_manager.get_unit(unit_id)
		if candidate != null and not candidate.is_player_character:
			victim = candidate
			break
	_check(victim != null, "找到用于俘虏存档的单位")
	if victim == null:
		context.queue_free()
		return
	victim.mark_wounded()
	context.party_manager.remove_member(party.party_id, victim.unit_id)
	_check(
		context.party_manager.add_prisoner(party.party_id, victim.unit_id),
		"准备玩家俘虏"
	)
	var save := context.to_save_data()

	var restored := WorldContext.new()
	restored.name = "PrisonerRestoredContext"
	add_child(restored)
	_check(restored.load_from_save_data(save), "俘虏存档可读取")
	if restored.is_valid_world():
		var loaded_party := restored.party_manager.get_party(party.party_id)
		var loaded_unit := restored.unit_manager.get_unit(victim.unit_id)
		_check(
			loaded_unit != null and loaded_unit.is_prisoner()
				and loaded_unit.prisoner_owner_party_id == party.party_id,
			"读档保留俘虏归属"
		)
		_check(
			loaded_party != null and loaded_party.prisoner_unit_ids == [victim.unit_id],
			"读档保留部队俘虏列表且无重复"
		)
		_check(
			loaded_party != null and not loaded_party.member_unit_ids.has(victim.unit_id),
			"俘虏不会重新变成成员"
		)
		# 幂等校正：再次执行不产生重复。
		restored.party_manager.sanitize_prisoner_ownership()
		restored.party_manager.sanitize_prisoner_ownership()
		_check(
			loaded_party.prisoner_unit_ids == [victim.unit_id],
			"重复校正不会复制俘虏"
		)
		_check(
			restored.party_manager.validate_membership_consistency().is_empty(),
			"读档后俘虏/成员归属一致"
		)
	restored.queue_free()
	context.queue_free()


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------


func _setup_managers() -> void:
	_ids = IdGenerator.new()
	_units = UnitManager.new()
	_units.setup(_ids)
	_units.register_unit_config(_militia)
	_units.register_unit_config(_hero)
	_parties = PartyManager.new()
	_parties.setup(_units, _ids)
	_factions = FactionManager.new()
	_factions.setup_defaults(_parties)
	_profile = PlayerProfile.new()
	_battle = BattleManager.new()
	_battle.setup(_units, _parties, _ids, _factions, _profile)


func _reset_managers() -> void:
	_setup_managers()
	_battle.set_wounded_config(WoundedConfig.create_default())
	_battle.set_wounded_rng_seed(7)


func _set_all_wounded_chances(value: float) -> void:
	var config := WoundedConfig.create_default()
	config.tier_wounded_chances = [value, value, value]
	_battle.set_wounded_config(config)


func _make_party(faction_id: String, party_name: String) -> PartyData:
	return _parties.create_party(faction_id, Vector2.ZERO, party_name)


func _add_unit(party: PartyData, config: UnitConfig) -> UnitData:
	var unit := _units.create_unit(config, party.faction_id)
	_check(unit != null and _parties.add_member(party.party_id, unit.unit_id),
		"创建并加入单位")
	return unit


func _party_add_member_back(party: PartyData, unit: UnitData) -> void:
	# 释放后的单位恢复成员身份，用于一致性校验。
	unit.status = UnitData.Status.ACTIVE
	unit.current_hp = unit.max_hp
	_parties.add_member(party.party_id, unit.unit_id)


func _zero_side_hp(session: BattleSession, side_index: int) -> void:
	for unit_id: String in session.get_side_unit_ids(side_index):
		var state := session.get_unit_state(unit_id)
		if state != null:
			state.battle_hp = 0
			state.alive = false


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[prisoner] OK: %s" % message)
	else:
		_failed = true
		push_error("[prisoner] FAIL: %s" % message)
