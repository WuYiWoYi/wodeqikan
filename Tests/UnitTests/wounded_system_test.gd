extends Node
## 阶段 13 Step 3 测试：伤兵状态与战斗结算。
## 覆盖 tier 概率配置、伤兵保留身份/等级/装备/经验、玩家角色永久死亡、
## 概率采样、伤兵不参战、成员列表标识、序列化与读档保持。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/UnitTests/wounded_system_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"
const TRAINED_PATH: String = "res://Data/Units/infantry_trained.tres"
const VETERAN_PATH: String = "res://Data/Units/infantry_veteran.tres"
const HERO_PATH: String = "res://Data/Units/player_hero.tres"

var _failed: bool = false
var _militia: UnitConfig = null
var _trained: UnitConfig = null
var _veteran: UnitConfig = null
var _hero: UnitConfig = null
var _ids: IdGenerator = null
var _units: UnitManager = null
var _parties: PartyManager = null
var _factions: FactionManager = null
var _profile: PlayerProfile = null
var _battle: BattleManager = null


func _ready() -> void:
	_run()
	if _failed:
		push_error("[wounded] 测试失败")
		get_tree().quit(1)
	else:
		print("[wounded] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	_militia = load(MILITIA_PATH) as UnitConfig
	_trained = load(TRAINED_PATH) as UnitConfig
	_veteran = load(VETERAN_PATH) as UnitConfig
	_hero = load(HERO_PATH) as UnitConfig
	_check(
		_militia != null and _trained != null and _veteran != null and _hero != null,
		"加载兵种配置"
	)
	if _militia == null or _trained == null or _veteran == null or _hero == null:
		return

	_setup_managers()
	_test_config_values()
	_test_wounded_retention()
	_test_permanent_death()
	_test_player_character_death_rule()
	_test_probability_sample()
	_test_wounded_cannot_join_battle()
	_test_unit_serialization()
	_test_member_list_item()
	_test_world_save_reload()


func _setup_managers() -> void:
	_ids = IdGenerator.new()
	_units = UnitManager.new()
	_units.setup(_ids)
	_units.register_unit_config(_militia)
	_units.register_unit_config(_trained)
	_units.register_unit_config(_veteran)
	_units.register_unit_config(_hero)
	_parties = PartyManager.new()
	_parties.setup(_units, _ids)
	_factions = FactionManager.new()
	_factions.setup_defaults(_parties)
	_profile = PlayerProfile.new()
	_battle = BattleManager.new()
	_battle.setup(_units, _parties, _ids, _factions, _profile)
	_battle.player_party_id = ""


func _test_config_values() -> void:
	var config := load(
		"res://Data/Combat/wounded_config.tres"
	) as WoundedConfig
	_check(config != null, "加载负伤概率配置")
	if config == null:
		return
	_check(is_equal_approx(config.get_wounded_chance(1), 0.5), "一级兵负伤概率 50%")
	_check(is_equal_approx(config.get_wounded_chance(2), 0.6), "二级兵负伤概率 60%")
	_check(is_equal_approx(config.get_wounded_chance(3), 0.8), "三级兵负伤概率 80%")
	_check(is_equal_approx(config.get_wounded_chance(99), 0.8), "越界 tier 取边界概率")
	config.enabled = false
	_check(is_zero_approx(config.get_wounded_chance(1)), "关闭后概率为 0")
	config.enabled = true


func _test_wounded_retention() -> void:
	_reset_managers()
	_set_all_chances(1.0)
	_battle.set_wounded_rng_seed(1)

	var player := _make_party(FactionManager.PLAYER_FACTION_ID, "伤兵玩家")
	var hero := _add_unit(player, _hero)
	var militia := _add_unit(player, _militia)
	var trained := _add_unit(player, _trained)
	var veteran := _add_unit(player, _veteran)
	var enemy := _make_party(FactionManager.BANDIT_FACTION_ID, "伤兵强盗")
	var enemy_a := _add_unit(enemy, _militia)
	var enemy_b := _add_unit(enemy, _militia)
	_battle.player_party_id = player.party_id
	_prepare_wounded_metadata(militia)

	var session := _battle.start_battle(
		[player.party_id], [enemy.party_id], Vector2.ZERO
	)
	_check(session != null, "开始负伤测试战斗")
	if session == null:
		return
	_set_all_units_zero_hp(session)
	_check(
		_battle.finish_battle(
			session.battle_id, BattleSession.BattleResult.ATTACKER_VICTORY
		),
		"负伤战斗结算成功"
	)
	var result := session.final_result
	_check(result != null, "生成战斗结果")
	if result == null:
		return

	_check(result.get_party_casualties(player.party_id) == 1, "玩家角色永久阵亡 1")
	_check(result.get_party_wounded(player.party_id) == 3, "三名士兵成为伤兵")
	_check(result.get_party_survivors(player.party_id) == 0, "无存活单位")
	_check(result.get_party_casualties(enemy.party_id) == 0, "敌人无永久阵亡")
	_check(result.get_party_wounded(enemy.party_id) == 2, "敌人产生两名伤兵")

	var hero_unit := _units.get_unit(hero.unit_id)
	_check(hero_unit == null, "玩家角色不参与负伤概率，直接阵亡")
	for unit_id: String in [militia.unit_id, trained.unit_id, veteran.unit_id]:
		var unit := _units.get_unit(unit_id)
		_check(unit != null, "伤兵单位数据仍存在")
		if unit == null:
			continue
		_check(unit.status == UnitData.Status.WOUNDED, "伤兵状态显式标记")
		_check(unit.current_hp == 0, "伤兵当前 HP 为 0")
		_check(not unit.is_alive(), "伤兵被视为无法战斗")
		_check(unit.is_wounded(), "is_wounded() 为真")
		_check(player.member_unit_ids.has(unit.unit_id), "伤兵仍留在原部队")
	_check(
		militia.level == 2 and militia.exp == 15,
		"伤兵保留等级与经验"
	)
	_check(
		str(militia.equipment.get("WEAPON", "")) == "weapon_sword_01",
		"伤兵保留装备"
	)
	# 阶段 13 Step 5：战败方伤兵成为胜利方俘虏，离开原部队成员列表。
	_check(not enemy.member_unit_ids.has(enemy_a.unit_id)
			and not enemy.member_unit_ids.has(enemy_b.unit_id),
		"战败方伤兵离开原部队")
	var pending: Array[String] = _battle.get_pending_player_prisoners(
		session.battle_id
	)
	_check(pending.has(enemy_a.unit_id) and pending.has(enemy_b.unit_id),
		"战败方伤兵进入玩家待确认俘虏份额")
	_check(
		_units.get_unit(enemy_a.unit_id) != null
			and _units.get_unit(enemy_a.unit_id).status == UnitData.Status.WOUNDED,
		"俘虏保留伤兵 Unit 身份"
	)
	_check(
		enemy.battle_state == PartyData.BattleState.DISABLED,
		"只剩伤兵的部队停止世界行动"
	)
	# 伤兵不算永久死亡：奖励只按永久阵亡的敌人计算。
	_check(result.reward_gold == BattleManager.VICTORY_GOLD_BASE, "伤兵不产生击杀金币")


func _test_permanent_death() -> void:
	_reset_managers()
	_set_all_chances(0.0)
	var player := _make_party(FactionManager.PLAYER_FACTION_ID, "永久阵亡方")
	var unit_a := _add_unit(player, _militia)
	var unit_b := _add_unit(player, _militia)
	var enemy := _make_party(FactionManager.BANDIT_FACTION_ID, "永久阵亡敌人")
	var enemy_unit := _add_unit(enemy, _militia)
	_battle.player_party_id = player.party_id

	var session := _battle.start_battle(
		[player.party_id], [enemy.party_id], Vector2.ZERO
	)
	_check(session != null, "开始永久死亡测试战斗")
	if session == null:
		return
	_set_all_units_zero_hp(session)
	_battle.finish_battle(session.battle_id, BattleSession.BattleResult.DRAW)
	var result := session.final_result
	_check(
		result.get_party_casualties(player.party_id) == 2
			and result.get_party_wounded(player.party_id) == 0,
		"概率为 0 时全部永久阵亡"
	)
	_check(
		player.member_unit_ids.is_empty(), "永久阵亡单位移出部队"
	)
	_check(
		_units.get_unit(unit_a.unit_id) == null
			and _units.get_unit(unit_b.unit_id) == null,
		"永久阵亡单位数据被清理"
	)
	_check(_units.get_unit(enemy_unit.unit_id) == null, "敌方永久阵亡单位同样清理")


func _test_player_character_death_rule() -> void:
	_reset_managers()
	_set_all_chances(1.0)
	var player := _make_party(FactionManager.PLAYER_FACTION_ID, "玩家角色")
	var hero := _add_unit(player, _hero)
	var enemy := _make_party(FactionManager.BANDIT_FACTION_ID, "敌人")
	_add_unit(enemy, _militia)
	_battle.player_party_id = player.party_id

	var session := _battle.start_battle(
		[player.party_id], [enemy.party_id], Vector2.ZERO
	)
	_check(session != null, "开始玩家角色死亡测试")
	if session == null:
		return
	_set_all_units_zero_hp(session)
	_battle.finish_battle(session.battle_id, BattleSession.BattleResult.DEFENDER_VICTORY)
	var result := session.final_result
	_check(
		result.get_party_casualties(player.party_id) == 1,
		"玩家角色保持永久死亡规则"
	)
	_check(
		_units.get_unit(hero.unit_id) == null and player.member_unit_ids.is_empty(),
		"玩家角色阵亡后照常移除"
	)
	_check(
		result.get_party_wounded(enemy.party_id) == 1,
		"同场普通士兵仍按概率负伤"
	)


func _test_probability_sample() -> void:
	_reset_managers()
	_set_all_chances(0.0)
	var config := WoundedConfig.create_default()
	config.tier_wounded_chances = [0.5, 0.6, 0.8]
	_battle.set_wounded_config(config)
	_battle.set_wounded_rng_seed(20261122)

	var sample_size: int = 400
	var player := _make_party(FactionManager.PLAYER_FACTION_ID, "采样部队")
	for index: int in range(sample_size):
		_add_unit(player, _militia)
	var enemy := _make_party(FactionManager.BANDIT_FACTION_ID, "采样敌人")
	_add_unit(enemy, _militia)
	_battle.player_party_id = player.party_id
	var session := _battle.start_battle(
		[player.party_id], [enemy.party_id], Vector2.ZERO
	)
	_check(session != null, "开始概率采样战斗")
	if session == null:
		return
	_set_all_units_zero_hp(session)

	# build_battle_result 会触发一次性负伤判定；只读取状态，不立即结算。
	var result := _battle.build_battle_result(
		session, BattleSession.BattleResult.ATTACKER_VICTORY, false
	)
	var wounded_count: int = result.get_party_wounded(player.party_id)
	var ratio: float = float(wounded_count) / float(sample_size)
	_check(
		ratio > 0.42 and ratio < 0.58,
		"固定种子下 50%% 概率采样接近期望（实际 %.3f）" % ratio
	)
	# 同一场战斗重复预览不能重新掷骰。
	var result_again := _battle.build_battle_result(
		session, BattleSession.BattleResult.ATTACKER_VICTORY, false
	)
	_check(
		result_again.get_party_wounded(player.party_id) == wounded_count,
		"预览与最终结果共用同一次负伤判定"
	)
	_battle.abort_battle(session.battle_id)


func _test_wounded_cannot_join_battle() -> void:
	_reset_managers()
	_set_all_chances(0.0)
	var party := _make_party(FactionManager.PLAYER_FACTION_ID, "混合部队")
	var active := _add_unit(party, _militia)
	var wounded := _add_unit(party, _militia)
	wounded.mark_wounded()
	var enemy := _make_party(FactionManager.BANDIT_FACTION_ID, "对手")
	_add_unit(enemy, _militia)
	_battle.player_party_id = party.party_id

	var session := _battle.start_battle(
		[party.party_id], [enemy.party_id], Vector2.ZERO
	)
	_check(session != null, "包含伤兵的部队仍可参战")
	if session == null:
		return
	var side_ids := session.get_side_unit_ids(
		session.get_side_of_party(party.party_id)
	)
	_check(side_ids.has(active.unit_id), "可战斗成员进入战斗")
	_check(not side_ids.has(wounded.unit_id), "伤兵不进入战斗")
	_check(
		session.get_unit_state(wounded.unit_id) == null,
		"伤兵没有战斗单位状态"
	)
	_battle.abort_battle(session.battle_id)


func _test_unit_serialization() -> void:
	var unit := UnitData.new()
	unit.unit_id = "u_wounded"
	unit.config_id = "infantry_militia"
	unit.level = 2
	unit.exp = 7
	unit.equipment = {"WEAPON": "weapon_sword_01"}
	unit.mark_wounded()
	var restored := UnitData.from_dict(unit.to_dict())
	_check(restored.status == UnitData.Status.WOUNDED, "序列化保留伤兵状态")
	_check(restored.current_hp == 0, "序列化保留 0 HP")
	_check(restored.level == 2 and restored.exp == 7, "序列化保留等级/经验")
	_check(
		str(restored.equipment.get("WEAPON", "")) == "weapon_sword_01",
		"序列化保留装备"
	)

	# 旧存档没有 status：0 HP 单位按伤兵归一化，避免读档误删。
	var legacy := unit.to_dict()
	legacy.erase("status")
	var legacy_unit := UnitData.from_dict(legacy)
	_check(
		legacy_unit.status == UnitData.Status.WOUNDED,
		"旧存档 0 HP 单位恢复为伤兵"
	)

	# HP 恢复有效值后自动回到正常状态。
	restored.current_hp = 10
	restored.clamp_hp()
	_check(
		restored.status == UnitData.Status.ACTIVE and restored.is_alive(),
		"HP 恢复后伤兵自动变回正常"
	)


func _test_member_list_item() -> void:
	var unit := UnitData.new()
	unit.unit_id = "u_ui"
	unit.config_id = "infantry_militia"
	unit.level = 1
	unit.max_hp = 50
	unit.current_hp = 0
	unit.status = UnitData.Status.WOUNDED
	unit.display_name = "测试伤兵"
	var item := PartyMemberItem.new()
	add_child(item)
	item.setup(unit, _militia)
	# 列表条目只保留头像、姓名、战斗经验与生命值；伤兵通过 0 生命值体现。
	var hp_label := item.find_child("MemberHp", true, false) as Label
	_check(hp_label != null and hp_label.text.contains("0 / 50"), "伤兵列表项显示当前生命值")
	var exp_label := item.find_child("MemberCombatExperience", true, false) as Label
	_check(
		exp_label != null and exp_label.text == "战斗经验：新兵",
		"成员列表显示战斗经验文本等级"
	)
	item.queue_free()


func _test_world_save_reload() -> void:
	var context := WorldContext.new()
	context.name = "WoundedSaveContext"
	add_child(context)
	_check(WorldInitializer.create_new_world(context), "初始化伤兵存档世界")
	if not context.is_valid_world():
		return
	var party := context.get_player_party()
	var victim: UnitData = null
	for unit_id: String in party.member_unit_ids:
		var candidate := context.unit_manager.get_unit(unit_id)
		if candidate != null and not candidate.is_player_character:
			victim = candidate
			break
	_check(victim != null, "找到普通士兵用于伤兵存档")
	if victim == null:
		context.queue_free()
		return
	victim.mark_wounded()
	var save := context.to_save_data()

	var restored := WorldContext.new()
	restored.name = "WoundedRestoredContext"
	add_child(restored)
	_check(restored.load_from_save_data(save), "伤兵存档可正常读取")
	if restored.is_valid_world():
		var loaded_party := restored.party_manager.get_party(party.party_id)
		var loaded_unit := restored.unit_manager.get_unit(victim.unit_id)
		_check(
			loaded_unit != null
				and loaded_unit.status == UnitData.Status.WOUNDED
				and loaded_unit.current_hp == 0,
			"读档保留伤兵状态与 0 HP"
		)
		_check(
			loaded_party != null and loaded_party.member_unit_ids.has(victim.unit_id),
			"读档后伤兵仍属于原部队"
		)
	restored.queue_free()
	context.queue_free()


func _reset_managers() -> void:
	_ids = IdGenerator.new()
	_units = UnitManager.new()
	_units.setup(_ids)
	_units.register_unit_config(_militia)
	_units.register_unit_config(_trained)
	_units.register_unit_config(_veteran)
	_units.register_unit_config(_hero)
	_parties = PartyManager.new()
	_parties.setup(_units, _ids)
	_factions = FactionManager.new()
	_factions.setup_defaults(_parties)
	_profile = PlayerProfile.new()
	_battle = BattleManager.new()
	_battle.setup(_units, _parties, _ids, _factions, _profile)
	_battle.set_wounded_config(WoundedConfig.create_default())
	_battle.set_wounded_rng_seed(7)


func _set_all_chances(value: float) -> void:
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


func _prepare_wounded_metadata(unit: UnitData) -> void:
	unit.level = 2
	unit.exp = 15
	unit.equipment = {"WEAPON": "weapon_sword_01"}


func _set_all_units_zero_hp(session: BattleSession) -> void:
	for value: Variant in session.unit_states.values():
		var state := value as BattleUnitState
		if state == null:
			continue
		state.battle_hp = 0
		state.alive = false


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[wounded] OK: %s" % message)
	else:
		_failed = true
		push_error("[wounded] FAIL: %s" % message)
