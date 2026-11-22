extends Node
## BattleResultData / 战斗结算测试：伤亡、经验、升级、奖励、撤退、多方、离屏与重复结算保护。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/battle_result_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"

var _failed: bool = false
var _militia: UnitConfig = null
var _ids: IdGenerator = null
var _units: UnitManager = null
var _parties: PartyManager = null
var _factions: FactionManager = null
var _battle: BattleManager = null
var _profile: PlayerProfile = null


func _ready() -> void:
	_run()
	if _failed:
		push_error("[result] 测试失败")
		get_tree().quit(1)
	else:
		print("[result] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	_militia = load(MILITIA_PATH) as UnitConfig
	_check(_militia != null, "加载民兵配置")
	if _militia == null:
		return

	_ids = IdGenerator.new()
	_units = UnitManager.new()
	_units.setup(_ids)
	_parties = PartyManager.new()
	_parties.setup(_units, _ids)
	_factions = FactionManager.new()
	_factions.setup_defaults(_parties)
	_profile = PlayerProfile.new()
	_battle = BattleManager.new()
	_battle.setup(_units, _parties, _ids, _factions, _profile)

	_test_victory_result()
	_test_mid_join_result()
	_test_retreat_result()
	_test_multi_side_result()
	_test_offscreen_result()


func _test_victory_result() -> void:
	var player := _make_party(FactionManager.PLAYER_FACTION_ID, "结算玩家", 2)
	var enemy := _make_party(FactionManager.BANDIT_FACTION_ID, "结算强盗", 2)
	_battle.player_party_id = player.party_id

	var hero_candidate := _units.get_unit(player.member_unit_ids[0])
	hero_candidate.exp = 90
	var enemy_with_loot := _units.get_unit(enemy.member_unit_ids[0])
	enemy_with_loot.equipment = {"WEAPON": "weapon_sword_01"}

	var session := _battle.start_battle(
		[player.party_id], [enemy.party_id], Vector2.ZERO
	)
	_check(session != null, "创建胜利结算战斗")
	if session == null:
		return

	for unit_id: String in player.member_unit_ids:
		var state := session.get_unit_state(unit_id)
		state.battle_hp = 15
		state.alive = true
	for unit_id: String in enemy.member_unit_ids:
		var state := session.get_unit_state(unit_id)
		state.battle_hp = 0
		state.alive = false

	var gold_before := _profile.gold
	_check(
		_battle.finish_battle(session.battle_id, BattleSession.BattleResult.ATTACKER_VICTORY),
		"胜利结算成功"
	)
	var result := session.final_result
	_check(result != null and result.finalized, "生成 finalized BattleResult")
	if result == null:
		return
	_check(
		result.end_reason == BattleResultData.EndReason.ANNIHILATION,
		"全灭结束原因正确"
	)
	_check(result.winning_side_index == 0, "获胜侧为 0")
	_check(result.losing_side_indices == [1], "失败侧为 1")
	_check(result.player_involved and result.player_won, "玩家参与并获胜")
	_check(result.get_party_casualties(enemy.party_id) == 2, "敌方阵亡 2")
	_check(result.get_party_survivors(player.party_id) == 2, "我方存活 2")
	_check(result.player_exp_gained == 60, "玩家总经验 60")
	_check(result.exp_gained_by_unit.get(hero_candidate.unit_id) == 30, "单个存活单位经验 30")
	_check(hero_candidate.level == 2 and hero_candidate.exp == 20, "经验触发升级")
	_check(hero_candidate.max_hp == 55, "升级后属性重算")
	_check(hero_candidate.current_hp == 15, "结算保留战斗剩余 HP")
	_check(result.reward_gold == 60, "金币奖励按敌方伤亡计算")
	_check(result.reward_items == ["weapon_sword_01"], "战利品来自阵亡敌人装备")
	_check(_profile.gold == gold_before + 60, "金币写入玩家数据")
	_check(_profile.inventory.has("weapon_sword_01"), "装备写入玩家物品栏")
	_check(_battle.current_battle == null, "结算后清理会话")
	_check(player.battle_state == PartyData.BattleState.AVAILABLE, "胜利方解锁")
	_check(enemy.battle_state == PartyData.BattleState.DISABLED, "失败方失效")
	_check(enemy.member_unit_ids.is_empty(), "阵亡单位移出部队")
	_check(_units.get_unit(enemy_with_loot.unit_id) == null, "阵亡单位数据删除")

	var exp_after := hero_candidate.exp
	var level_after := hero_candidate.level
	var gold_after := _profile.gold
	_check(
		not _battle.finish_battle(session.battle_id, BattleSession.BattleResult.ATTACKER_VICTORY),
		"同一场战斗不能重复结算"
	)
	_check(
		hero_candidate.exp == exp_after and hero_candidate.level == level_after,
		"重复结算不重复发经验"
	)
	_check(_profile.gold == gold_after, "重复结算不重复发奖励")


func _test_mid_join_result() -> void:
	var player := _make_party(FactionManager.PLAYER_FACTION_ID, "中途玩家", 1)
	var merchant := _make_party(FactionManager.MERCHANT_FACTION_ID, "中途商队", 1)
	var bandit := _make_party(FactionManager.BANDIT_FACTION_ID, "中途强盗", 1)
	_battle.player_party_id = player.party_id
	var session := _battle.start_battle(
		[bandit.party_id], [merchant.party_id], Vector2.ZERO, true
	)
	_check(session != null and session.offscreen, "创建可加入的离屏战斗")
	if session == null:
		return
	_check(
		_battle.try_join_battle(player.party_id, session.battle_id),
		"玩家中途加入已有战斗"
	)
	_check(not session.offscreen, "玩家加入后转为屏幕战斗")
	_check(session.player_involved, "战斗标记玩家参与")
	_check(
		session.get_side_of_party(player.party_id)
		== session.get_side_of_party(merchant.party_id),
		"玩家加入商队一侧"
	)

	for unit_id: String in session.get_side_unit_ids(0):
		var state := session.get_unit_state(unit_id)
		state.battle_hp = 0
		state.alive = false
	var gold_before := _profile.gold
	_check(
		_battle.finish_battle(session.battle_id, BattleSession.BattleResult.DEFENDER_VICTORY),
		"中途加入战斗结算成功"
	)
	var result := session.final_result
	_check(result != null, "中途加入生成统一结果")
	if result == null:
		return
	_check(result.player_side_index == 1, "结果记录玩家侧为 1")
	_check(result.player_won, "玩家侧获胜")
	_check(result.player_exp_gained == 30, "中途加入的玩家存活单位获得经验")
	_check(result.reward_gold == 55, "中途加入获胜获得对应奖励")
	_check(_profile.gold == gold_before + 55, "中途加入奖励写入玩家数据")
	_check(
		not _battle.finish_battle(
			session.battle_id, BattleSession.BattleResult.DEFENDER_VICTORY
		),
		"中途加入战斗不能重复结算"
	)
	_check(_profile.gold == gold_before + 55, "重复结算不重复发奖励")


func _test_retreat_result() -> void:
	var player := _make_party(FactionManager.PLAYER_FACTION_ID, "撤退玩家", 1)
	var enemy := _make_party(FactionManager.BANDIT_FACTION_ID, "撤退敌人", 1)
	_battle.player_party_id = player.party_id
	var session := _battle.start_battle(
		[player.party_id], [enemy.party_id], Vector2.ZERO
	)
	_check(session != null, "创建撤退战斗")
	if session == null:
		return
	_check(_battle.retreat_side(0), "玩家侧发起撤退")
	_check(session.retreated_side_indices.has(0), "撤退侧被记录")
	var gold_before := _profile.gold
	_check(
		_battle.finish_battle(session.battle_id, BattleSession.BattleResult.RETREATED),
		"撤退结算成功"
	)
	var result := session.final_result
	_check(result != null, "撤退生成结果")
	if result == null:
		return
	_check(result.end_reason == BattleResultData.EndReason.RETREAT, "结束原因为撤退")
	_check(result.winning_side_index == -1, "撤退没有获胜侧")
	_check(result.retreated_side_indices.has(0), "结果记录撤退侧")
	_check(not result.player_won, "撤退不算玩家获胜")
	_check(result.reward_gold == 0, "撤退不发胜利奖励")
	_check(result.get_party_casualties(player.party_id) == 0, "撤退不是全员阵亡")
	_check(result.get_party_survivors(player.party_id) == 1, "撤退单位存活")
	_check(_profile.gold == gold_before, "撤退不改变金币")
	_check(player.battle_state == PartyData.BattleState.AVAILABLE, "撤退方解锁")


func _test_multi_side_result() -> void:
	var player := _make_party(FactionManager.PLAYER_FACTION_ID, "多方玩家", 1)
	var bandit := _make_party(FactionManager.BANDIT_FACTION_ID, "多方强盗", 1)
	var guard := _make_party(FactionManager.GUARD_FACTION_ID, "多方治安队", 1)
	_battle.player_party_id = player.party_id
	var session := _battle.start_battle_by_sides(
		[[player.party_id], [bandit.party_id], [guard.party_id]],
		Vector2.ZERO,
		true
	)
	_check(session != null, "创建三方结算战斗")
	if session == null:
		return
	for side_index: int in [0, 1]:
		for unit_id: String in session.get_side_unit_ids(side_index):
			var state := session.get_unit_state(unit_id)
			state.battle_hp = 0
			state.alive = false
	session.winning_side_index = 2
	var gold_before := _profile.gold
	_check(
		_battle.finish_battle(session.battle_id, BattleSession.BattleResult.SIDE_VICTORY),
		"三方战斗结算成功"
	)
	var result := session.final_result
	_check(result != null, "三方战斗生成结果")
	if result == null:
		return
	_check(result.winning_side_index == 2, "第三方获胜")
	_check(result.losing_side_indices.has(0) and result.losing_side_indices.has(1), "另外两方失败")
	_check(not result.player_won, "玩家失败不获得胜利奖励")
	_check(result.reward_gold == 0, "玩家失败无金币")
	_check(_profile.gold == gold_before, "玩家失败不改变金币")
	_check(result.get_party_casualties(player.party_id) == 1, "玩家方阵亡")
	_check(result.get_party_survivors(guard.party_id) == 1, "获胜方存活")


func _test_offscreen_result() -> void:
	var merchant := _make_party(FactionManager.MERCHANT_FACTION_ID, "离屏商队", 2)
	var bandit := _make_party(FactionManager.BANDIT_FACTION_ID, "离屏强盗", 2)
	var gold_before := _profile.gold
	var session := _battle.start_battle(
		[merchant.party_id], [bandit.party_id], Vector2.ZERO, true
	)
	_check(session != null and session.offscreen, "创建离屏战斗")
	if session == null:
		return
	_check(_battle.resolve_current_battle_now(), "离屏战斗按小时推进并自动结算")
	_check(_battle.get_battle(session.battle_id) == null, "离屏战斗自动结算")
	var result := session.final_result
	_check(result != null and result.finalized, "离屏战斗生成 finalized 结果")
	_check(session.status == BattleSession.Status.ENDED, "离屏战斗状态结束")
	if result != null:
		_check(not result.player_involved, "离屏 NPC 战斗不标记玩家参与")
		_check(result.player_side_index == -1, "离屏 NPC 战斗没有玩家侧")
		_check(result.reward_gold == 0, "玩家未参与的 NPC 战斗不发奖励")
		_check(result.participants.size() == 2, "离屏结果包含双方部队")
	_check(_profile.gold == gold_before, "离屏 NPC 战斗不改变玩家金币")


func _make_party(faction_id: String, party_name: String, count: int) -> PartyData:
	var party := _parties.create_party(faction_id, Vector2.ZERO, party_name)
	for i: int in range(count):
		var unit := _units.create_unit(_militia, faction_id)
		_parties.add_member(party.party_id, unit.unit_id)
	return party


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[result] OK: %s" % message)
	else:
		_failed = true
		push_error("[result] FAIL: %s" % message)
