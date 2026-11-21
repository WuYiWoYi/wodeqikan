extends Node
## 战斗侧胜负测试：同一侧一支部队全灭但另一支存活时战斗继续；
## 一侧全部失去战斗能力后才结算为失败。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/battle_side_result_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"

var _failed: bool = false
var _context: WorldContext = null
var _scene: BattleScene = null
var _session: BattleSession = null
var _player: PartyData = null
var _ally: PartyData = null
var _enemy: PartyData = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[sideresult] 测试失败")
		get_tree().quit(1)
	else:
		print("[sideresult] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)

	_context = WorldContext.new()
	_context.name = "BattleSideResultContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")

	_player = _context.get_player_party()
	_enemy = _find_party_by_name(WorldInitializer.BANDIT_PARTY_NAME)
	_check(_player != null and _enemy != null, "玩家与敌人部队存在")
	if _player == null or _enemy == null:
		return

	var militia: UnitConfig = load(MILITIA_PATH) as UnitConfig
	_ally = _context.party_manager.create_party(
		WorldInitializer.PLAYER_FACTION_ID, Vector2(800.0, 700.0), "侧翼友军"
	)
	for i: int in range(2):
		var unit := _context.unit_manager.create_unit(
			militia, WorldInitializer.PLAYER_FACTION_ID
		)
		_context.party_manager.add_member(_ally.party_id, unit.unit_id)

	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id
	_session = _context.battle_manager.start_battle_by_sides(
		[[_player.party_id, _ally.party_id], [_enemy.party_id]],
		_enemy.world_position
	)
	_check(_session != null, "创建同一侧多部队战斗")
	if _session == null:
		return

	var packed := load("res://Scenes/Battle/battle.tscn") as PackedScene
	_scene = packed.instantiate() as BattleScene
	add_child(_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame

	var result_panel := _scene.find_child("BattleResultPanel", true, false) as PanelContainer
	_check(result_panel != null, "战斗场景包含结果面板")

	# 只消灭侧翼友军：同侧玩家部队仍存活，战斗应继续。
	for unit_id: String in _ally.member_unit_ids:
		var state := _session.get_unit_state(unit_id)
		if state != null:
			state.battle_hp = 0
			state.alive = false
	await _settle_frames(4)
	_check(
		result_panel != null and not result_panel.visible,
		"一支友军全灭但同侧仍有部队时战斗继续"
	)
	_check(_scene.get_controller_count_alive(_scene.get_player_side()) > 0, "玩家侧仍有存活单位")

	# 再消灭玩家部队：整个战斗侧失去战斗能力，应判定失败。
	for unit_id: String in _player.member_unit_ids:
		var state := _session.get_unit_state(unit_id)
		if state != null:
			state.battle_hp = 0
			state.alive = false
	await _settle_frames(6)
	_check(result_panel != null and result_panel.visible, "玩家侧全部失去战斗能力后结算")
	var result_label := _scene.find_child("BattleResultLabel", true, false) as Label
	_check(result_label != null and result_label.text == "战斗失败", "玩家侧全灭判定为失败")

	_check(
		_context.battle_manager.finish_battle(
			_session.battle_id, BattleSession.BattleResult.DEFENDER_VICTORY
		),
		"侧级失败结算成功"
	)
	var result := _session.final_result
	_check(result != null, "生成统一结果")
	if result != null:
		_check(result.winning_side_index == 1, "获胜侧为敌方")
		_check(
			result.get_party_casualties(_player.party_id)
				== WorldInitializer.PLAYER_TOTAL_MEMBER_COUNT,
			"玩家部队全员伤亡"
		)
		_check(
			result.get_party_casualties(_ally.party_id) == 2,
			"友军部队伤亡 2"
		)
		_check(result.player_won == false, "玩家侧失败")


func _settle_frames(count: int) -> void:
	for i: int in range(count):
		await get_tree().physics_frame


func _find_party_by_name(party_name: String) -> PartyData:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[sideresult] OK: %s" % message)
	else:
		_failed = true
		push_error("[sideresult] FAIL: %s" % message)


func _cleanup() -> void:
	if _context != null and _context.battle_manager.current_battle != null:
		_context.battle_manager.abort_battle(
			_context.battle_manager.current_battle.battle_id
		)
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_scene):
		_scene.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
