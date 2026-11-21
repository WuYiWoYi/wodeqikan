extends Node
## 玩家胜利结算延迟测试。
## 覆盖：胜利后结果数据立即生成、面板延迟约 3 秒；失败立即展示；
## 延迟期间退出场景安全取消；不重复触发。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/battle_result_delay_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"
const DELAY_WAIT_FRAMES: int = 260

var _failed: bool = false
var _context: WorldContext = null
var _player: PartyData = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[delay] 测试失败")
		get_tree().quit(1)
	else:
		print("[delay] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)

	_context = WorldContext.new()
	_context.name = "BattleResultDelayContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	_player = _context.get_player_party()
	_check(_player != null, "玩家部队存在")
	if _player == null:
		return
	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id

	# --- 玩家胜利：数据立即生成，面板延迟展示 ---
	var enemy := _create_enemy_party("延迟测试敌人甲", 2)
	var session := _context.battle_manager.start_battle_by_sides(
		[[_player.party_id], [enemy.party_id]], enemy.world_position
	)
	_check(session != null, "创建胜利测试战斗")
	if session == null:
		return
	var scene := await _open_scene()
	if scene == null:
		return
	_check(
		BattleScene.VICTORY_RESULT_DELAY > 2.5 and BattleScene.VICTORY_RESULT_DELAY < 3.5,
		"胜利延迟约为 3 秒"
	)
	_kill_side(session, 1)
	await _wait_physics(3)
	_check(scene.is_result_pending(), "胜利后进入结算延迟")
	_check(scene.get_result_data() != null, "结算数据在延迟期间已生成")
	var pending = scene.get_result_data()
	if pending != null:
		_check(pending.winning_side_index == 0, "延迟期间已记录获胜侧")
		_check(
			pending.get_side_survivors(scene.get_player_side()) > 0,
			"延迟期间已统计存活人数"
		)
	_check(scene.get_result_delay_remaining() > 0.0, "延迟计时尚未结束")
	var panel := scene.find_child("BattleResultPanel", true, false) as PanelContainer
	var label := scene.find_child("BattleResultLabel", true, false) as Label
	_check(panel != null and not panel.visible, "胜利后立即不显示结果面板")

	await _wait_physics(DELAY_WAIT_FRAMES)
	_check(not scene.is_result_pending(), "延迟计时结束")
	_check(panel != null and panel.visible, "约 3 秒后显示胜利结果面板")
	_check(label != null and label.text == "战斗胜利", "胜利结果文本正确")
	_check(scene.get_result_data() == pending, "展示后不重复生成结算数据")
	scene.skip_result_delay()
	_check(panel != null and panel.visible, "重复调用不会隐藏或重复弹出面板")

	_context.battle_manager.finish_battle(
		session.battle_id, BattleSession.BattleResult.ATTACKER_VICTORY
	)
	scene.queue_free()
	await _wait_physics(2)

	# --- 延迟期间退出场景：安全取消 ---
	var enemy_b := _create_enemy_party("延迟测试敌人乙", 2)
	var session_b := _context.battle_manager.start_battle_by_sides(
		[[_player.party_id], [enemy_b.party_id]], enemy_b.world_position
	)
	_check(session_b != null, "创建取消测试战斗")
	if session_b == null:
		return
	var scene_b := await _open_scene()
	if scene_b == null:
		return
	_kill_side(session_b, 1)
	await _wait_physics(2)
	_check(scene_b.is_result_pending(), "取消测试进入结算延迟")
	scene_b.queue_free()
	await _wait_physics(3)
	_check(not is_instance_valid(scene_b), "延迟期间退出场景不保留计时节点")
	_check(_context.battle_manager.current_battle == session_b, "退出场景不自动结算战斗")
	_context.battle_manager.abort_battle(session_b.battle_id)

	# --- 失败：不延迟，立即展示 ---
	var enemy_c := _create_enemy_party("延迟测试敌人丙", 2)
	var session_c := _context.battle_manager.start_battle_by_sides(
		[[_player.party_id], [enemy_c.party_id]], enemy_c.world_position
	)
	_check(session_c != null, "创建失败测试战斗")
	if session_c == null:
		return
	var scene_c := await _open_scene()
	if scene_c == null:
		return
	_kill_side(session_c, 0)
	await _wait_physics(4)
	_check(not scene_c.is_result_pending(), "失败不进入结算延迟")
	var panel_c := scene_c.find_child("BattleResultPanel", true, false) as PanelContainer
	var label_c := scene_c.find_child("BattleResultLabel", true, false) as Label
	_check(panel_c != null and panel_c.visible, "失败后立即显示结果面板")
	_check(label_c != null and label_c.text == "战斗失败", "失败结果文本正确")
	_context.battle_manager.finish_battle(
		session_c.battle_id, BattleSession.BattleResult.DEFENDER_VICTORY
	)
	scene_c.queue_free()
	await _wait_physics(2)


func _create_enemy_party(party_name: String, unit_count: int) -> PartyData:
	var militia: UnitConfig = load(MILITIA_PATH) as UnitConfig
	var party := _context.party_manager.create_party(
		WorldInitializer.BANDIT_FACTION_ID,
		_player.world_position + Vector2(60.0, 0.0),
		party_name,
		PartyData.PartyKind.BANDIT
	)
	for i: int in range(unit_count):
		var unit := _context.unit_manager.create_unit(
			militia, WorldInitializer.BANDIT_FACTION_ID
		)
		_context.party_manager.add_member(party.party_id, unit.unit_id)
	return party


func _open_scene() -> BattleScene:
	var packed := load("res://Scenes/Battle/battle.tscn") as PackedScene
	var scene := packed.instantiate() as BattleScene
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	return scene


func _kill_side(session: BattleSession, side_index: int) -> void:
	for unit_id: String in session.get_side_unit_ids(side_index):
		var state := session.get_unit_state(unit_id)
		if state != null:
			state.battle_hp = 0
			state.alive = false


func _wait_physics(count: int) -> void:
	for i: int in range(count):
		await get_tree().physics_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[delay] OK: %s" % message)
	else:
		_failed = true
		push_error("[delay] FAIL: %s" % message)


func _cleanup() -> void:
	if _context != null and _context.battle_manager.current_battle != null:
		_context.battle_manager.abort_battle(
			_context.battle_manager.current_battle.battle_id
		)
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_context):
		_context.queue_free()
