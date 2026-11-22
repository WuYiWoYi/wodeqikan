extends Node
## 阶段 13 Step 5 集成测试：战斗结果面板 → 俘虏选择界面 → 返回大地图。
## 只验证界面衔接与真实归属提交，不实际切换场景（避免测试节点被释放）。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/stage13_prisoner_ui_flow_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"

var _failed: bool = false
var _context: WorldContext = null
var _scene: BattleScene = null
var _session: BattleSession = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[prisonerui] 测试失败")
		get_tree().quit(1)
	else:
		print("[prisonerui] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	var militia := load(MILITIA_PATH) as UnitConfig
	_check(militia != null, "加载兵种配置")
	if militia == null:
		return

	_context = WorldContext.new()
	_context.name = "PrisonerUiFlowContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return
	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id
	var player := _context.get_player_party()
	var enemy := _context.party_manager.create_party(
		FactionManager.BANDIT_FACTION_ID, player.world_position, "被俘敌军"
	)
	for _i: int in range(2):
		var unit := _context.unit_manager.create_unit(
			militia, FactionManager.BANDIT_FACTION_ID
		)
		_context.party_manager.add_member(enemy.party_id, unit.unit_id)

	var wounded := WoundedConfig.create_default()
	wounded.tier_wounded_chances = [1.0, 1.0, 1.0]
	_context.battle_manager.set_wounded_config(wounded)
	_context.battle_manager.set_wounded_rng_seed(11)
	_session = _context.battle_manager.start_battle(
		[player.party_id], [enemy.party_id], player.world_position
	)
	_check(_session != null, "创建玩家胜利战斗")
	if _session == null:
		return
	for unit_id: String in _session.get_side_unit_ids(
		_session.get_side_of_party(enemy.party_id)
	):
		var state := _session.get_unit_state(unit_id)
		state.battle_hp = 0
		state.alive = false

	var packed := load("res://Scenes/Battle/battle.tscn") as PackedScene
	_scene = packed.instantiate() as BattleScene
	add_child(_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	_check(_scene.get_session() == _session, "战斗场景绑定当前会话")

	# 模拟战斗结束判定并立即展示结果面板。
	_scene.set_result_delay_enabled(false)
	_scene.call("_prepare_result", false)
	var result_panel := _scene.find_child(
		"BattleResultPanel", true, false
	) as PanelContainer
	_check(result_panel != null and result_panel.visible, "先显示原有战斗结果面板")
	var return_button := _scene.find_child(
		"BattleReturnButton", true, false
	) as Button
	_check(return_button != null, "存在返回大地图按钮")
	return_button.pressed.emit()

	var prisoner_panel := _scene.find_child(
		"PrisonerSelectionPanel", true, false
	) as PrisonerSelectionPanel
	_check(
		prisoner_panel != null and prisoner_panel.visible,
		"确认结果后进入俘虏选择界面"
	)
	_check(not result_panel.visible, "俘虏选择界面接替结果面板")
	_check(
		_context.battle_manager.has_pending_prisoner_selection(_session.battle_id),
		"战斗结算已生成待确认玩家份额"
	)
	if prisoner_panel == null:
		return

	var left_ids := prisoner_panel.get_left_ids()
	_check(not left_ids.is_empty(), "左侧显示待接收俘虏")
	_check(
		_context.party_manager.get_prisoner_ids(
			_context.player_party_id
		).is_empty(),
		"确认前玩家真实俘虏列表为空"
	)

	# 直接提交（等价于点击确认），避免测试中真正切换场景。
	var accepted: Array[String] = []
	if not left_ids.is_empty():
		accepted.append(left_ids[0])
	_check(
		_context.battle_manager.commit_player_prisoners(
			_session.battle_id, accepted
		),
		"提交玩家接收的俘虏"
	)
	_check(
		_context.party_manager.get_prisoner_ids(_context.player_party_id) == accepted,
		"确认后俘虏进入玩家俘虏列表"
	)
	TimeManager.pop_pause(&"prisoner_selection")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[prisonerui] OK: %s" % message)
	else:
		_failed = true
		push_error("[prisonerui] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_scene):
		_scene.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
