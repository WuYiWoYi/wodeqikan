extends Node
## 战斗伤害经验测试：有效伤害 +1、击杀额外 +10、未命中/0 伤害不发经验、
## 同一敌人不重复发放击杀经验，且经验通过 BattleManager 写回 UnitManager。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/UnitTests/combat_experience_award_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"

var _failed: bool = false
var _awards: Array = []


func _ready() -> void:
	_test_damage_awards()
	_test_battle_manager_bridge()
	if _failed:
		push_error("[combatxp] 测试失败")
		get_tree().quit(1)
	else:
		print("[combatxp] 全部通过")
		get_tree().quit(0)


func _test_damage_awards() -> void:
	var attacker := _make_controller("UNIT_ATTACKER", 100)
	var second_attacker := _make_controller("UNIT_ATTACKER_2", 100)
	var target := _make_controller("UNIT_TARGET", 30)
	attacker.experience_callback = _on_experience
	second_attacker.experience_callback = _on_experience

	# 0 伤害/负伤害不是有效伤害，不发放经验。
	target.apply_damage(0, attacker)
	target.apply_damage(-5, attacker)
	_check(_awards.is_empty(), "0/负伤害不发放经验")

	# 有效伤害 +1；未击杀不追加击杀奖励。
	target.apply_damage(10, attacker)
	_check(_awards == [["UNIT_ATTACKER", 1]], "命中一次获得 1 经验")
	_check(target.state.battle_hp == 20, "目标扣除实际伤害")

	# 致命一击 +1 +10；同一目标死亡后不再发放。
	target.apply_damage(20, attacker)
	_check(
		_awards == [["UNIT_ATTACKER", 1], ["UNIT_ATTACKER", 11]],
		"击杀获得 1 + 10 经验"
	)
	_check(not target.is_alive(), "目标进入阵亡状态")
	target.apply_damage(50, attacker)
	_check(_awards.size() == 2, "已死亡目标不重复发放经验")

	# 击杀经验只给实际击杀者，不给之前造成伤害的其他人。
	var target_b := _make_controller("UNIT_TARGET_B", 8)
	target_b.apply_damage(3, attacker)
	target_b.apply_damage(5, second_attacker)
	_check(
		_awards == [
			["UNIT_ATTACKER", 1], ["UNIT_ATTACKER", 11],
			["UNIT_ATTACKER", 1], ["UNIT_ATTACKER_2", 11],
		],
		"击杀奖励只发给最后一击的攻击者"
	)

	# 自伤不发放经验。
	var before_size: int = _awards.size()
	attacker.apply_damage(1, attacker)
	_check(_awards.size() == before_size, "自身伤害不发放经验")


func _test_battle_manager_bridge() -> void:
	var ids := IdGenerator.new()
	var units := UnitManager.new()
	units.setup(ids)
	var militia := load(MILITIA_PATH) as UnitConfig
	_check(militia != null, "加载民兵配置")
	if militia == null:
		return
	_check(units.register_unit_config(militia), "注册民兵配置")
	var parties := PartyManager.new()
	parties.setup(units, ids)
	var factions := FactionManager.new()
	factions.setup_defaults(parties)
	var profile := PlayerProfile.new()
	var battle := BattleManager.new()
	battle.setup(units, parties, ids, factions, profile)

	var unit := units.create_unit(militia, FactionManager.PLAYER_FACTION_ID)
	_check(unit != null, "创建用于经验的单位")
	if unit == null:
		return
	battle.grant_combat_experience(unit.unit_id, 100)
	_check(unit.level == 2 and unit.exp == 0, "BattleManager 经验写回触发升级")
	battle.grant_combat_experience(unit.unit_id, 0)
	_check(unit.level == 2 and unit.exp == 0, "0 经验不写回")


func _make_controller(unit_id: String, hp: int) -> UnitController:
	var data := UnitData.new()
	data.unit_id = unit_id
	var state := BattleUnitState.new()
	state.unit_id = unit_id
	state.battle_hp = hp
	state.alive = true
	var controller := UnitController.new()
	controller.setup(data, state, false, null, Rect2(0.0, 0.0, 1000.0, 1000.0))
	return controller


func _on_experience(unit_id: String, amount: int) -> void:
	_awards.append([unit_id, amount])


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[combatxp] OK: %s" % message)
	else:
		_failed = true
		push_error("[combatxp] FAIL: %s" % message)
