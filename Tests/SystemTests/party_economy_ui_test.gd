extends Node
## 部队面板经济 UI 测试：金币/工资显示、上马/下马、消耗物品晋升。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/party_economy_ui_test.tscn

const MOUNT_ID: String = "mount_horse_01"
const TOKEN_ID: String = "promotion_rank_token"

var _failed: bool = false
var _context: WorldContext = null
var _map: Node = null
var _panel: PartyPanel = null
var _player: PartyData = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[economyui] 测试失败")
		get_tree().quit(1)
	else:
		print("[economyui] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)

	_context = WorldContext.new()
	_context.name = "PartyEconomyUIContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return
	_player = _context.get_player_party()
	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id

	var packed := load("res://Scenes/WorldMap/world_map.tscn") as PackedScene
	_map = packed.instantiate()
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame

	var button := _map.find_child("PartyButton", true, false) as Button
	_check(button != null, "大地图存在部队按钮")
	if button == null:
		return
	button.pressed.emit()
	await get_tree().process_frame
	_panel = _map.find_child("PartyPanel", true, false) as PartyPanel
	_check(_panel != null and _panel.visible, "打开部队面板")
	if _panel == null:
		return

	_test_overview()
	await _test_mount_controls()
	await _test_promotion_ui()


func _test_overview() -> void:
	var gold := _panel.find_child("PartyPanelGoldLabel", true, false) as Label
	var wage := _panel.find_child("PartyPanelWageLabel", true, false) as Label
	_check(gold != null and gold.text.contains("0"), "部队面板显示金币")
	_check(wage != null and wage.text.contains("21"), "部队面板显示每日工资总额")


func _test_mount_controls() -> void:
	var militia := _find_member_unit("infantry_militia", false)
	_check(militia != null, "找到未骑乘民兵")
	if militia == null:
		return
	_select_member(militia.unit_id)
	await get_tree().process_frame

	var tier_before: int = _context.unit_manager.get_unit_config(militia.config_id).tier
	var hp_before: int = militia.max_hp
	var attack_before: int = militia.attack
	var wage_before: int = militia.wage
	var stock_before: int = _context.player_profile.get_item_count(MOUNT_ID)
	_check(stock_before == 1, "背包有 1 匹马")

	var option := _panel.find_child("DetailMountOption", true, false) as OptionButton
	var equip := _panel.find_child("DetailEquipMountButton", true, false) as Button
	var unequip := _panel.find_child("DetailUnequipMountButton", true, false) as Button
	_check(option != null and option.item_count >= 1, "坐骑下拉框列出背包马匹")
	_check(equip != null and not equip.disabled, "未骑乘时可装备坐骑")
	_check(unequip != null and unequip.disabled, "未骑乘时不能卸下")
	if option == null or equip == null:
		return
	option.select(0)
	equip.pressed.emit()
	await get_tree().process_frame

	_check(militia.is_mounted, "点击装备后士兵进入骑乘状态")
	_check(_context.player_profile.get_item_count(MOUNT_ID) == stock_before - 1,
		"装备坐骑消耗背包马匹")
	_check(_context.unit_manager.get_unit_config(militia.config_id).tier == tier_before,
		"上马不改变兵种等级")
	_check(militia.max_hp == hp_before and militia.attack == attack_before,
		"上马不改变基础生命与攻击")
	_check(militia.wage == wage_before, "上马不改变工资")
	_check(unequip != null and not unequip.disabled, "骑乘后可卸下坐骑")

	unequip.pressed.emit()
	await get_tree().process_frame
	_check(not militia.is_mounted, "点击卸下后恢复步兵状态")
	_check(_context.player_profile.get_item_count(MOUNT_ID) == stock_before,
		"卸下坐骑返还背包")
	_check(militia.wage == wage_before, "下马不改变工资")


func _test_promotion_ui() -> void:
	var militia := _find_member_unit("infantry_militia", false)
	_check(militia != null, "找到用于晋升的民兵")
	if militia == null:
		return
	_select_member(militia.unit_id)
	await get_tree().process_frame

	var button := _panel.find_child("DetailPromotionButton", true, false) as Button
	var info := _panel.find_child("DetailPromotionInfo", true, false) as Label
	var tier_label := _panel.find_child("DetailTier", true, false) as Label
	_check(button != null and not button.disabled, "有凭证时可以晋升")
	_check(info != null and info.text.contains("二级"), "晋升信息显示目标等级")
	_check(tier_label != null and tier_label.text.contains("一级"), "详情显示一级兵种")
	if button == null:
		return

	var tokens_before: int = _context.player_profile.get_item_count(TOKEN_ID)
	button.pressed.emit()
	await get_tree().process_frame
	_check(militia.config_id == "infantry_trained", "晋升后切换为二级兵种")
	_check(
		_context.player_profile.get_item_count(TOKEN_ID) == tokens_before - 1,
		"晋升消耗 1 个凭证"
	)
	_check(tier_label.text.contains("二级"), "晋升后详情显示二级兵种")
	_check(militia.wage == 5, "晋升后工资更新为二级工资")

	button.pressed.emit()
	await get_tree().process_frame
	_check(militia.config_id == "infantry_veteran", "继续晋升为三级兵种")
	_check(_context.player_profile.get_item_count(TOKEN_ID) == 0, "凭证已用完")
	_check(tier_label.text.contains("三级"), "晋升后详情显示三级兵种")
	_check(button.disabled, "最高等级时晋升按钮禁用")
	_check(not _context.unit_manager.promote_tier(
		militia.unit_id, _context.player_profile
	), "最高等级不能继续晋升")

	var wage := _panel.find_child("PartyPanelWageLabel", true, false) as Label
	_check(wage != null and wage.text.contains("29"), "工资总额随晋升同步更新")


func _find_member_unit(config_id: String, mounted: bool) -> UnitData:
	for unit_id: String in _player.member_unit_ids:
		var unit := _context.unit_manager.get_unit(unit_id)
		if unit == null:
			continue
		if unit.config_id == config_id and unit.is_mounted == mounted:
			return unit
	return null


func _select_member(unit_id: String) -> void:
	var item := _panel.find_child("MemberItem_%s" % unit_id, true, false) as PartyMemberItem
	_check(item != null, "成员列表包含目标士兵")
	if item != null:
		item.pressed.emit()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[economyui] OK: %s" % message)
	else:
		_failed = true
		push_error("[economyui] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_map):
		_map.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
