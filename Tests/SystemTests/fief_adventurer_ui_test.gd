extends Node
## 阶段 7 UI 测试：村庄候选人 NPC/对话招募、离开清理、
## 大地图封地信息与采邑征召按钮、部队上方浮动提示。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/fief_adventurer_ui_test.tscn

var _failed: bool = false
var _context: WorldContext = null
var _village: VillageScene = null
var _map: Node = null
var _player_village: SettlementData = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[fiefui] 测试失败")
		get_tree().quit(1)
	else:
		print("[fiefui] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)

	_context = WorldContext.new()
	_context.name = "FiefAdventurerUiContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return
	_player_village = _find_settlement(WorldInitializer.PLAYER_VILLAGE_NAME)
	_check(_player_village != null, "找到玩家封地村庄")
	if _player_village == null:
		return
	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id
	GameManager.current_settlement_id = _player_village.settlement_id
	_context.player_profile.gold = 10

	await _test_village_candidates()
	await _test_world_map_panel()


func _test_village_candidates() -> void:
	var packed := load("res://Scenes/Village/village.tscn") as PackedScene
	_village = packed.instantiate() as VillageScene
	add_child(_village)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(
		_village.get_candidate_count() == 2,
		"村庄为每名候选人生成 NPC 表现"
	)
	_check(_village.get_world_log_panel() != null, "村庄显示共享世界日志面板")
	var candidate: AdventurerCandidateData = (
		_player_village.get_available_candidates()[0]
	)
	if candidate == null:
		_check(false, "存在可交互候选人")
		return
	_check(
		_village.get_candidate_visual(candidate.candidate_id) != null,
		"候选人 NPC 绑定权威候选人 ID"
	)

	_village.set_player_position(
		_village.get_candidate_position(candidate.candidate_id) + Vector2(60.0, 0.0)
	)
	_check(
		_village.try_interact_with_candidate(candidate.candidate_id),
		"靠近候选人后可以打开对话"
	)
	_check(_village.is_dialogue_open(), "候选人对话打开")
	var choices: Array = _context.dialogue_manager.get_choices()
	_check(
		choices.size() >= 1
		and str((choices[0] as Dictionary).get("action", ""))
			== "recruit_adventurer",
		"对话提供统一招募动作"
	)
	var members_before: int = _context.get_player_party().member_unit_ids.size()
	var recruit_button := _village.find_child(
		"VillageDialogueChoice_0", true, false
	) as Button
	_check(recruit_button != null, "对话生成招募按钮")
	if recruit_button == null:
		return
	recruit_button.pressed.emit()
	await get_tree().process_frame
	_check(not _village.is_dialogue_open(), "招募后对话关闭")
	_check(
		_context.get_player_party().member_unit_ids.size() == members_before + 1,
		"UI 招募创建 1 个真实单位"
	)
	_check(
		candidate.status
			== AdventurerCandidateData.Status.RECRUITED_PENDING_DEPARTURE,
		"UI 招募更新候选人状态"
	)
	var name_label := _village.find_child(
		"AdventurerCandidateName_%s" % candidate.candidate_id, true, false
	) as Label
	_check(
		name_label != null and name_label.text.contains("已招募"),
		"已招募候选人在离开前仍保留并标记"
	)

	# 再次对话不再出现招募动作。
	_village.set_player_position(
		_village.get_candidate_position(candidate.candidate_id) + Vector2(60.0, 0.0)
	)
	_check(
		_village.try_interact_with_candidate(candidate.candidate_id),
		"已招募候选人仍可对话"
	)
	var second_choices: Array = _context.dialogue_manager.get_choices()
	var has_recruit_action: bool = false
	for value: Variant in second_choices:
		if value is Dictionary \
				and str((value as Dictionary).get("action", "")) \
					== "recruit_adventurer":
			has_recruit_action = true
	_check(not has_recruit_action, "重复对话不再提供招募选项")
	_village.call("_close_dialogue")

	var candidate_id: String = candidate.candidate_id
	_village.set_auto_return_enabled(false)
	_village.call("_request_exit")
	await get_tree().process_frame
	_check(
		_player_village.get_candidate(candidate_id) == null,
		"离开村庄后清理已招募候选人"
	)
	_check(
		_village.get_candidate_count() == 2
		and _village.get_candidate_visual(candidate_id) != null,
		"离开时只清理候选人数据，场景销毁前表现节点仍有效"
	)

	_village.queue_free()
	_village = null
	await get_tree().process_frame


func _test_world_map_panel() -> void:
	GameManager.pending_settlement_latch_id = _player_village.settlement_id
	var packed := load("res://Scenes/WorldMap/world_map.tscn") as PackedScene
	_map = packed.instantiate()
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame

	_map.call("_open_settlement", _player_village)
	await get_tree().process_frame
	var panel := _map.find_child("SettlementPanel", true, false) as PanelContainer
	_check(panel != null and panel.visible, "打开地点信息面板")
	var owner_label := _map.find_child(
		"SettlementOwnerLabel", true, false
	) as Label
	var family_label := _map.find_child(
		"SettlementFamilyLabel", true, false
	) as Label
	var population_label := _map.find_child(
		"SettlementPopulationLabel", true, false
	) as Label
	var prosperity_label := _map.find_child(
		"SettlementProsperityLabel", true, false
	) as Label
	var tax_label := _map.find_child("SettlementTaxLabel", true, false) as Label
	_check(
		owner_label != null and owner_label.text.contains("玩家领主"),
		"面板显示封地领主"
	)
	_check(
		family_label != null and family_label.text.contains("玩家家族"),
		"面板显示地点家族"
	)
	_check(
		population_label != null
		and population_label.text.contains(str(_player_village.population)),
		"面板显示人口"
	)
	_check(
		prosperity_label != null
		and prosperity_label.text.contains(str(_player_village.prosperity)),
		"面板显示繁荣度"
	)
	_check(
		tax_label != null and tax_label.text.contains(
			str(_player_village.tax_income_per_day)
		),
		"面板显示统一计算的税收"
	)

	var button := _map.find_child(
		"SettlementRecruitFiefButton", true, false
	) as Button
	_check(button != null and button.visible and not button.disabled,
		"自有村庄显示采邑征召入口")
	if button == null:
		return
	var members_before: int = _context.get_player_party().member_unit_ids.size()
	var stock_before: int = _player_village.fief_recruitment_stock
	button.pressed.emit()
	await get_tree().process_frame
	_check(
		_context.get_player_party().member_unit_ids.size() == members_before + 6,
		"UI 征召生成一组 6 名采邑"
	)
	_check(
		_player_village.fief_recruitment_stock == stock_before - 1,
		"UI 征召消耗封地储备"
	)
	_check(not button.disabled, "仍有储备时可继续征召")
	var icon := _map.call(
		"get_party_icon", _context.player_party_id
	) as PartyIcon
	_check(
		icon != null and icon.get_last_floating_text() == "招募了1组采邑",
		"部队图标上方显示征召提示"
	)

	# 非自有村庄不显示征召入口。
	_map.call("_on_settlement_leave_pressed")
	var bari := _find_settlement(WorldInitializer.BARI_VILLAGE_NAME)
	_map.call("_open_settlement", bari)
	await get_tree().process_frame
	_check(
		not button.visible,
		"非自有封地隐藏采邑征召入口"
	)
	_map.call("_on_settlement_leave_pressed")


func _find_settlement(display_name: String) -> SettlementData:
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement != null and settlement.display_name == display_name:
			return settlement
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[fiefui] OK: %s" % message)
	else:
		_failed = true
		push_error("[fiefui] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	GameManager.current_settlement_id = ""
	GameManager.pending_settlement_latch_id = ""
	if is_instance_valid(_village):
		_village.queue_free()
	if is_instance_valid(_map):
		_map.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
