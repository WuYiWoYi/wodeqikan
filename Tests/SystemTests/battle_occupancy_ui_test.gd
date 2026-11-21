extends Node
## 战斗占用提示回归测试。
## 覆盖：世界上已有离屏战斗时，独立部队对话不再显示笼统的“无法开始战斗”，
## 而是禁用战斗按钮并说明原因；点击参战方时改为加入已有战斗。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/battle_occupancy_ui_test.tscn

var _failed: bool = false
var _context: WorldContext = null
var _map: Node = null
var _battle_position: Vector2 = Vector2(2400.0, 1700.0)


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[battleblock] 测试失败")
		get_tree().quit(1)
	else:
		print("[battleblock] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)

	_context = WorldContext.new()
	_context.name = "BattleOccupancyTestContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id

	var player := _context.get_player_party()
	var knights := _find_party(WorldInitializer.MOXIXI_KNIGHT_PARTY_NAME)
	var guard := _find_party(WorldInitializer.GUARD_PARTY_NAME)
	var bandit := _find_party(WorldInitializer.BANDIT_PARTY_NAME)
	_check(
		player != null and knights != null and guard != null and bandit != null,
		"玩家、墨西西骑士、治安队、强盗均存在"
	)
	if player == null or knights == null or guard == null or bandit == null:
		return

	# 世界中先开始一场与玩家无关的离屏战斗。
	guard.world_position = _battle_position
	guard.target_position = _battle_position
	guard.movement_state = PartyData.MovementState.IDLE
	bandit.world_position = _battle_position + Vector2(10.0, 0.0)
	bandit.target_position = bandit.world_position
	bandit.movement_state = PartyData.MovementState.IDLE
	var active := _context.battle_manager.start_battle(
		[guard.party_id], [bandit.party_id], _battle_position, true
	)
	_check(active != null and active.offscreen, "创建离屏战斗")
	if active == null:
		return

	# 玩家在远处找到墨西西骑士（非参战方）。
	_position_pair(player, knights, Vector2(700.0, 1700.0))
	player.focus_party_id = knights.party_id
	await _instantiate_map()

	var panel := _map.find_child("PartyDialoguePanel", true, false) as PanelContainer
	var fight_button := _map.find_child("PartyFightButton", true, false) as Button
	var status := _map.find_child("PartyDialogueStatus", true, false) as Label
	_check(panel != null and panel.visible, "与墨西西骑士的对话正常打开")
	if panel == null or fight_button == null or status == null:
		return
	_check(fight_button.disabled, "已有战斗时禁止另开战场")
	_check(
		status.text.contains("另一场战斗正在进行"),
		"面板说明真实原因（另一场战斗正在进行）"
	)
	_check(fight_button.text == "发起战斗", "非参战方按钮保持发起战斗")

	var session: BattleSession = _map.begin_battle_with_party()
	_check(session == null, "绕过按钮直接调用也会被拒绝")
	_check(
		status.text.contains("另一场战斗正在进行"),
		"拒绝后仍显示具体原因，而不是笼统提示"
	)
	_check(
		_context.battle_manager.current_battle == active,
		"原有离屏战斗不受影响"
	)

	# 关闭对话，靠近战场并点击参战方：按钮应变为加入战斗。
	_map.call("_close_party_dialogue")
	player.world_position = _battle_position + Vector2(20.0, 0.0)
	player.target_position = player.world_position
	player.movement_state = PartyData.MovementState.IDLE
	_map.call("_open_party_dialogue", guard)
	_check(panel.visible, "参战方的对话可打开")
	_check(not fight_button.disabled, "可加入时按钮可用")
	_check(fight_button.text == "加入战斗", "按钮变为加入战斗")

	var joined: BattleSession = _map.begin_battle_with_party()
	_check(joined == active, "加入已有战斗而不是新建战斗")
	if joined == null:
		return
	_check(joined.player_involved, "加入后战斗标记为玩家参与")
	_check(not joined.offscreen, "加入后切换为屏幕战斗")
	_check(
		player.battle_state == PartyData.BattleState.IN_BATTLE,
		"玩家部队被锁定"
	)
	_check(not panel.visible, "加入后关闭对话")
	_check(
		_context.battle_manager.current_battle == active,
		"BattleManager 仍持有同一场战斗"
	)


func _instantiate_map() -> void:
	var packed := load("res://Scenes/WorldMap/world_map.tscn") as PackedScene
	_map = packed.instantiate()
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


func _position_pair(player: PartyData, enemy: PartyData, at: Vector2) -> void:
	enemy.world_position = at
	enemy.target_position = at
	enemy.movement_state = PartyData.MovementState.IDLE
	player.world_position = at + Vector2(-20.0, 0.0)
	player.target_position = player.world_position
	player.movement_state = PartyData.MovementState.IDLE


func _find_party(party_name: String) -> PartyData:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[battleblock] OK: %s" % message)
	else:
		_failed = true
		push_error("[battleblock] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_map):
		_map.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
