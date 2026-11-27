extends Node
## 主地图信息栏与建筑信息面板交互测试。
## 覆盖：金币/移速实时显示、普通与 ALT 悬浮明细、每日收支复用现有缓存、
##        村庄/城堡/城镇建筑面板打开时仍可使用百科/部队/背包/事件，
##        但世界时间控制保持禁用；关闭覆盖层不破坏建筑面板与暂停状态。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/main_map_info_test.tscn

var _failed: bool = false
var _context: WorldContext = null
var _map: Node = null
var _party: PartyData = null
var _settlement_panel: PanelContainer = null
var _encyclopedia_panel: PanelContainer = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[main_map_info] 测试失败")
		get_tree().quit(1)
	else:
		print("[main_map_info] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)

	_context = WorldContext.new()
	_context.name = "MainMapInfoTestContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return
	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id
	_party = _context.get_player_party()

	var packed := load("res://Scenes/WorldMap/world_map.tscn") as PackedScene
	_map = packed.instantiate()
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame

	_settlement_panel = _map.find_child("SettlementPanel", true, false) as PanelContainer
	_encyclopedia_panel = _map.find_child(
		"EncyclopediaPanel", true, false
	) as PanelContainer
	_check(_party != null and _settlement_panel != null, "找到玩家部队与地点面板")
	if _party == null or _settlement_panel == null:
		return

	await _test_time_centered()
	_test_top_info_icon_scale()
	await _test_day_night_clock()
	await _test_money_display_and_tooltip()
	await _test_speed_display_and_tooltip()
	await _test_troop_display_and_tooltip()
	_test_building_panel_ui_permissions()


func _test_time_centered() -> void:
	# 无头模式启动时视口可能只有 64×64；按项目目标分辨率验证顶栏布局。
	get_window().size = Vector2i(1920, 1080)
	await get_tree().process_frame
	await get_tree().process_frame
	var time_label := _map.find_child("WorldTimeLabel", true, false) as Label
	var clock := _map.find_child("DayNightClock", true, false) as Control
	var top_bar := _map.find_child("TopBar", true, false) as Control
	var left := _map.find_child("TopBarLeft", true, false) as Control
	var right := _map.find_child("TopBarRight", true, false) as Control
	_check(
		time_label != null and clock != null and top_bar != null
			and left != null and right != null,
		"顶栏左中右区域与昼夜窗口存在"
	)
	if time_label == null or clock == null or top_bar == null \
			or left == null or right == null:
		return
	var clock_rect := clock.get_global_rect()
	var viewport_center_x: float = _map.get_viewport_rect().size.x * 0.5
	_check(
		absf(clock_rect.size.x - clock_rect.size.y) <= 0.5,
		"昼夜窗口为正方形（%.1f×%.1f）" % [clock_rect.size.x, clock_rect.size.y]
	)
	_check(
		absf(clock_rect.get_center().x - viewport_center_x) <= 2.0,
		"昼夜窗口位于顶栏水平中心（%.1f vs %.1f）" % [
			clock_rect.get_center().x, viewport_center_x
		]
	)
	_check(
		clock_rect.position.y >= top_bar.get_global_rect().position.y - 0.5
			and clock_rect.end.y <= top_bar.get_global_rect().end.y + 0.5,
		"昼夜窗口完整位于顶栏内"
	)
	_check(clock.clip_contents, "昼夜窗口裁切超出遮罩的美术")
	_check(
		clock.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
		"昼夜美术使用最近邻采样"
	)
	_check(
		left.get_global_rect().end.x <= time_label.get_global_rect().position.x,
		"左侧金币/移速不与世界时间重叠"
	)
	_check(
		time_label.get_global_rect().end.x <= clock_rect.position.x,
		"世界时间位于昼夜窗口左侧且不重叠"
	)
	_check(
		clock_rect.end.x <= right.get_global_rect().position.x,
		"昼夜窗口不与右侧功能入口重叠"
	)
	_check(
		left.get_global_rect().end.x <= right.get_global_rect().position.x,
		"左侧信息与右侧入口不重叠"
	)

	# 1280 宽度：紧凑顶栏入口仍不挤压居中窗口与左侧信息。
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	clock_rect = clock.get_global_rect()
	_check(
		absf(
			clock_rect.get_center().x - _map.get_viewport_rect().size.x * 0.5
		) <= 2.0,
		"1280 宽度下昼夜窗口仍居中"
	)
	_check(
		left.get_global_rect().end.x <= time_label.get_global_rect().position.x,
		"1280 宽度下左侧信息不与时间重叠"
	)
	_check(
		time_label.get_global_rect().end.x <= clock_rect.position.x,
		"1280 宽度下时间不覆盖昼夜窗口"
	)
	_check(
		clock_rect.end.x <= right.get_global_rect().position.x,
		"1280 宽度下昼夜窗口不与右侧入口重叠"
	)
	_check(
		right.get_global_rect().size.x >= 500.0,
		"1280 宽度下右侧入口保持可容纳的宽度"
	)
	get_window().size = Vector2i(1920, 1080)
	await get_tree().process_frame
	await get_tree().process_frame


func _test_top_info_icon_scale() -> void:
	var top_bar := _map.find_child("TopBar", true, false) as Control
	for icon_name: String in [
		"MoneyLabelIcon", "PartySpeedLabelIcon", "PartySizeLabelIcon"
	]:
		var icon := _map.find_child(icon_name, true, false) as TextureRect
		_check(icon != null, "%s 存在" % icon_name)
		if icon == null:
			continue
		_check(
			icon.custom_minimum_size.is_equal_approx(Vector2(40.0, 40.0)),
			"%s 美术尺寸为 40×40（放大 2 倍）" % icon_name
		)
		_check(
			icon.size.x >= 40.0 and icon.size.y >= 40.0,
			"%s 实际布局尺寸不小于 40×40" % icon_name
		)
		_check(
			icon.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
			"%s 保持等比缩放" % icon_name
		)
		_check(
			icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
			"%s 保持最近邻采样" % icon_name
		)
		if top_bar != null:
			_check(
				top_bar.get_global_rect().encloses(icon.get_global_rect()),
				"%s 完整位于顶栏内，不被裁切" % icon_name
			)


## 昼夜滚动只由世界时间换算：验证正午/黄昏/午夜/黎明、跨午夜连续、
## 暂停停住、2 倍速同步与读档恢复后的位置。
func _test_day_night_clock() -> void:
	var clock := _map.find_child("DayNightClock", true, false) as Control
	if clock == null:
		return
	var original_seconds: float = TimeManager.world_elapsed_seconds
	var original_speed: float = TimeManager.get_base_world_speed()

	# 暂停状态下逐点核对映射，避免测试等待期间时间推进影响精度。
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	await _check_clock_at_hour(clock, 12.0, 0.0, "12:00 完整显示白天")
	await _check_clock_at_hour(clock, 18.0, 24.0, "18:00 处于昼夜交接")
	await _check_clock_at_hour(clock, 24.0, 48.0, "00:00 完整显示黑夜")
	await _check_clock_at_hour(clock, 30.0, 72.0, "06:00 处于夜昼交接")
	await _check_clock_at_hour(clock, 36.0, 0.0, "次日 12:00 回到白天")
	await _check_clock_at_hour(clock, 23.5, 46.0, "午夜前滚动位置连续")
	await _check_clock_at_hour(clock, 24.5, 50.0, "跨午夜后滚动位置连续")

	# 暂停：世界时间不推进时偏移保持不变。
	TimeManager.restore_world_time(
		18.0 * TimeManager.REAL_SECONDS_PER_GAME_HOUR, TimeManager.SPEED_PAUSED
	)
	await get_tree().process_frame
	var paused_offset: float = clock.get_texture_offset_pixels()
	var paused_seconds: float = TimeManager.world_elapsed_seconds
	await get_tree().create_timer(0.2).timeout
	_check(
		is_equal_approx(TimeManager.world_elapsed_seconds, paused_seconds)
			and is_equal_approx(clock.get_texture_offset_pixels(), paused_offset),
		"世界暂停时昼夜滚动停止"
	)

	# 2 倍速：偏移始终等于当前世界时间的换算值，没有独立累加误差。
	TimeManager.restore_world_time(
		12.0 * TimeManager.REAL_SECONDS_PER_GAME_HOUR, TimeManager.SPEED_DOUBLE
	)
	await get_tree().create_timer(0.2).timeout
	var expected_phase: float = _expected_clock_phase(TimeManager.world_elapsed_seconds)
	_check(
		absf(clock.get_scroll_phase() - expected_phase) <= 0.002,
		"2 倍速下昼夜位置与世界时间同步（%.4f vs %.4f）" % [
			clock.get_scroll_phase(), expected_phase
		]
	)

	# 读档：restore_world_time 走与读档相同的接口，位置立即刷新。
	TimeManager.restore_world_time(
		18.0 * TimeManager.REAL_SECONDS_PER_GAME_HOUR, TimeManager.SPEED_PAUSED
	)
	await get_tree().process_frame
	_check(
		absf(clock.get_texture_offset_pixels() - 24.0) <= 0.01,
		"读档恢复时间后昼夜位置立即更新"
	)

	TimeManager.restore_world_time(original_seconds, original_speed)
	TimeManager.clear_pauses()
	await get_tree().process_frame


func _check_clock_at_hour(
	clock: Control, hour: float, expected_offset: float, message: String
) -> void:
	TimeManager.restore_world_time(
		hour * TimeManager.REAL_SECONDS_PER_GAME_HOUR, TimeManager.SPEED_PAUSED
	)
	await get_tree().process_frame
	_check(
		absf(clock.get_texture_offset_pixels() - expected_offset) <= 0.01,
		"%s（偏移 %.2f/%.2f）" % [
			message, clock.get_texture_offset_pixels(), expected_offset
		]
	)


func _expected_clock_phase(total_seconds: float) -> float:
	var day_length: float = (
		TimeManager.HOURS_PER_DAY * TimeManager.REAL_SECONDS_PER_GAME_HOUR
	)
	return fposmod(fposmod(total_seconds / day_length, 1.0) - 0.5, 1.0)


func _test_money_display_and_tooltip() -> void:
	var money_label := _map.find_child("MoneyLabel", true, false) as Label
	_check(money_label != null, "顶栏显示金币")
	if money_label == null:
		return
	var gold: int = _context.player_profile.gold
	_check(
		money_label.text == str(gold),
		"金币只显示数值（%s）" % money_label.text
	)
	_check(not money_label.text.contains("金币"), "金币不再显示文字前缀")
	_check(_map.find_child("MoneyLabelIcon", true, false) != null, "金币图标存在")
	_check(
		_map.find_child("MoneyLabelEntry", true, false) != null,
		"金币图标与数值属于同一悬浮条目"
	)

	_context.player_profile.gold = gold - 123
	await get_tree().process_frame
	_check(
		money_label.text == str(gold - 123),
		"金币变化后实时更新"
	)
	_context.player_profile.gold = gold
	await get_tree().process_frame

	# 普通悬浮：只显示净收入。
	_map.call("set_top_info_hover_for_test", "MoneyLabel", true)
	_check(bool(_map.call("is_top_info_tooltip_visible")), "金币悬浮显示提示")
	var preview: Dictionary = _context.get_daily_balance_preview()
	var net: int = int(preview.get("net", 0))
	var normal_text := str(_map.call("get_top_info_tooltip_text"))
	_check(normal_text.contains("预计每日收入："), "普通悬浮显示预计每日收入")
	_check(
		normal_text.contains(_format_signed(net)),
		"普通悬浮净收入来自实际数据"
	)
	_check(not normal_text.contains("总计"), "普通悬浮不显示明细")

	# ALT：显示收支构成，值与预览数据一致。
	_map.call("set_alt_detail_active", true)
	await get_tree().process_frame
	var alt_text := str(_map.call("get_top_info_tooltip_text"))
	_check(alt_text.contains("每日收支"), "ALT 金币悬浮显示每日收支")
	_check(alt_text.contains("总计 %s" % _format_signed(net)), "ALT 显示总净额")
	var wage: int = _context.party_manager.get_total_wage(_context.player_party_id)
	if wage > 0:
		_check(alt_text.contains("部队工资"), "ALT 显示部队工资项目")
		_check(alt_text.contains(_format_signed(-wage)), "工资使用实际数值")
	var owned := _context.get_player_owned_settlements()
	var tax_total: int = 0
	for settlement: SettlementData in owned:
		tax_total += settlement.tax_income_per_day
		if settlement.tax_income_per_day > 0:
			_check(
				alt_text.contains("%s税收" % settlement.display_name),
				"ALT 显示 %s 税收" % settlement.display_name
			)
	_check(int(preview.get("income_total", -1)) == tax_total, "收入合计等于封地税收缓存")
	_check(int(preview.get("expense_total", -1)) == wage, "支出合计等于部队工资缓存")

	# 松开 ALT 恢复简述，移出隐藏。
	_map.call("set_alt_detail_active", false)
	await get_tree().process_frame
	var restored := str(_map.call("get_top_info_tooltip_text"))
	_check(
		restored.contains("预计每日收入：") and not restored.contains("每日收支"),
		"松开 ALT 恢复简述"
	)
	_map.call("set_top_info_hover_for_test", "MoneyLabel", false)
	_check(not bool(_map.call("is_top_info_tooltip_visible")), "移出金币后关闭提示")


func _test_speed_display_and_tooltip() -> void:
	var speed_label := _map.find_child("PartySpeedLabel", true, false) as Label
	_check(speed_label != null, "顶栏显示部队移速")
	if speed_label == null:
		return
	var effective: float = _context.world_map_manager.get_effective_movement_speed(_party)
	_check(
		speed_label.text == "%.1f" % effective,
		"移速只显示数值（%s）" % speed_label.text
	)
	_check(not speed_label.text.contains("移速"), "移速不再显示文字前缀")
	_check(
		_map.find_child("PartySpeedLabelIcon", true, false) != null,
		"移速图标存在"
	)
	_check(
		_map.find_child("PartySpeedLabelEntry", true, false) != null,
		"移速图标与数值属于同一悬浮条目"
	)

	_party.movement_speed += 10.0
	await get_tree().process_frame
	var changed: float = _context.world_map_manager.get_effective_movement_speed(_party)
	_check(
		speed_label.text == "%.1f" % changed,
		"移速随部队速度变化实时更新"
	)
	_party.movement_speed -= 10.0
	await get_tree().process_frame

	_map.call("set_top_info_hover_for_test", "PartySpeedLabel", true)
	_check(bool(_map.call("is_top_info_tooltip_visible")), "移速悬浮显示提示")
	var normal_text := str(_map.call("get_top_info_tooltip_text"))
	_check(normal_text.contains("当前部队移速：%.1f" % effective), "普通悬浮显示当前移速")
	_check(not normal_text.contains("最终移速"), "普通悬浮不显示明细")

	_map.call("set_alt_detail_active", true)
	await get_tree().process_frame
	var alt_text := str(_map.call("get_top_info_tooltip_text"))
	_check(alt_text.contains("基础移速"), "ALT 显示基础移速")
	_check(alt_text.contains("大地图移动系数"), "ALT 显示移动系数")
	_check(alt_text.contains("最终移速：%.1f" % effective), "ALT 最终移速与移动结算一致")
	var breakdown: Dictionary = _context.world_map_manager.get_movement_speed_breakdown(
		_party
	)
	for item_value: Variant in breakdown.get("items", []):
		if item_value is Dictionary:
			_check(
				alt_text.contains(str((item_value as Dictionary).get("label", ""))),
				"ALT 移速因素来自实际分解"
			)

	_map.call("set_alt_detail_active", false)
	await get_tree().process_frame
	_check(
		str(_map.call("get_top_info_tooltip_text")).contains("当前部队移速："),
		"松开 ALT 恢复移速简述"
	)
	_map.call("set_top_info_hover_for_test", "PartySpeedLabel", false)
	_check(not bool(_map.call("is_top_info_tooltip_visible")), "移出移速后关闭提示")


func _test_troop_display_and_tooltip() -> void:
	var troop_label := _map.find_child("PartySizeLabel", true, false) as Label
	_check(troop_label != null, "顶栏显示部队人数")
	if troop_label == null:
		return
	var counts: Dictionary = _expected_party_counts()
	_check(
		troop_label.text == str(int(counts["total"])),
		"部队人数显示实际成员数（%s）" % troop_label.text
	)
	_check(
		_map.find_child("PartySizeLabelIcon", true, false) != null,
		"部队人数图标存在"
	)
	var entry := _map.find_child("PartySizeLabelEntry", true, false) as HBoxContainer
	_check(entry != null, "部队人数图标与数值属于同一悬浮条目")
	if entry != null:
		var icon := entry.get_node_or_null("PartySizeLabelIcon") as Control
		var value := entry.get_node_or_null("PartySizeLabel") as Control
		_check(
			entry.mouse_filter == Control.MOUSE_FILTER_STOP,
			"条目容器接收悬浮事件"
		)
		_check(
			icon != null and icon.mouse_filter == Control.MOUSE_FILTER_IGNORE
				and value != null and value.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"图标与数值共同由条目容器触发悬浮"
		)

	_map.call("set_top_info_hover_for_test", "PartySizeLabel", true)
	var tooltip := str(_map.call("get_top_info_tooltip_text"))
	_check(bool(_map.call("is_top_info_tooltip_visible")), "部队人数悬浮显示提示")
	_check(tooltip.contains("部队"), "部队提示包含标题")
	_check(
		tooltip.contains("可战斗人数 %d" % int(counts["combat"])),
		"部队提示显示可战斗人数"
	)
	_check(
		tooltip.contains("伤员 %d" % int(counts["wounded"])),
		"部队提示显示伤员"
	)
	_check(
		tooltip.contains("俘虏 %d" % int(counts["prisoners"])),
		"部队提示显示俘虏"
	)

	# 伤兵：总人数不变，可战斗与伤员按真实状态分别统计。
	var wounded_unit: UnitData = null
	for unit_id: String in _party.member_unit_ids:
		var unit := _context.unit_manager.get_unit(unit_id)
		if unit != null and unit.is_alive() and not unit.is_player_character:
			wounded_unit = unit
			break
	if wounded_unit != null:
		wounded_unit.mark_wounded()
		await get_tree().process_frame
		counts = _expected_party_counts()
		_check(
			troop_label.text == str(int(counts["total"])),
			"出现伤员后部队总人数保持正确"
		)
		tooltip = str(_map.call("get_top_info_tooltip_text"))
		_check(
			tooltip.contains("可战斗人数 %d" % int(counts["combat"])),
			"伤员不计入可战斗人数"
		)
		_check(
			tooltip.contains("伤员 %d" % int(counts["wounded"])),
			"伤员数量实时更新"
		)

	# 俘虏：由真实部队俘虏列表统计，不混入成员人数。
	var base_unit := _context.unit_manager.get_unit(_party.member_unit_ids[0])
	var member_config: UnitConfig = null
	if wounded_unit != null:
		member_config = _context.unit_manager.get_unit_config(wounded_unit.config_id)
	elif base_unit != null:
		member_config = _context.unit_manager.get_unit_config(base_unit.config_id)
	var prisoner: UnitData = null
	if member_config != null:
		prisoner = _context.unit_manager.create_unit(
			member_config, _party.faction_id
		)
	if prisoner != null:
		_check(
			_context.party_manager.add_member(_party.party_id, prisoner.unit_id),
			"准备俘虏：先加入部队"
		)
		_context.party_manager.remove_member(_party.party_id, prisoner.unit_id)
		prisoner.mark_wounded()
		_check(
			_context.party_manager.add_prisoner(_party.party_id, prisoner.unit_id),
			"准备俘虏：加入玩家俘虏列表"
		)
		await get_tree().process_frame
		counts = _expected_party_counts()
		tooltip = str(_map.call("get_top_info_tooltip_text"))
		_check(
			tooltip.contains("俘虏 %d" % int(counts["prisoners"])),
			"俘虏数量来自真实俘虏列表"
		)
		_check(
			troop_label.text == str(int(counts["total"])),
			"俘虏不计入部队成员人数"
		)
		_context.party_manager.remove_prisoner(_party.party_id, prisoner.unit_id)

	# 恢复准备数据，避免影响后续建筑面板测试。
	if wounded_unit != null:
		wounded_unit.current_hp = wounded_unit.max_hp
		wounded_unit.clamp_hp()
	await get_tree().process_frame
	_map.call("set_top_info_hover_for_test", "PartySizeLabel", false)
	_check(not bool(_map.call("is_top_info_tooltip_visible")), "移出部队人数后关闭提示")
	_check(
		troop_label.text == str(int(_expected_party_counts()["total"])),
		"恢复后部队人数显示正确"
	)


func _expected_party_counts() -> Dictionary:
	var combat: int = 0
	var wounded: int = 0
	for unit_id: String in _party.member_unit_ids:
		var unit := _context.unit_manager.get_unit(unit_id)
		if unit == null:
			continue
		if unit.is_wounded():
			wounded += 1
		elif unit.is_alive():
			combat += 1
	return {
		"combat": combat,
		"wounded": wounded,
		"prisoners": _party.prisoner_unit_ids.size(),
		"total": combat + wounded,
	}


func _test_building_panel_ui_permissions() -> void:
	var targets: Array[SettlementData] = [
		_find_settlement(WorldInitializer.BARI_VILLAGE_NAME),
		_find_settlement("灰石堡垒"),
		_find_settlement(WorldInitializer.BURKNANIA_TOWN_NAME),
	]
	for settlement: SettlementData in targets:
		_check(settlement != null, "找到建筑测试地点")
		if settlement == null:
			continue
		TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)
		_open_settlement_panel(settlement)
		_check(_settlement_panel.visible, "%s 建筑面板打开" % settlement.display_name)
		if not _settlement_panel.visible:
			continue
		_check(_time_buttons_disabled(), "建筑面板打开时时间控制禁用")
		_check(
			is_zero_approx(TimeManager.get_effective_world_scale()),
			"建筑面板打开时世界暂停"
		)

		# 百科。
		_click("EncyclopediaButton")
		_check(
			_encyclopedia_panel != null and _encyclopedia_panel.visible,
			"建筑面板打开时可打开百科"
		)
		_check(_time_buttons_disabled(), "打开百科后时间控制仍禁用")
		_map.call("_on_close_encyclopedia_pressed")
		_check(_settlement_panel.visible, "关闭百科后建筑面板仍在")
		_check(_time_buttons_disabled(), "关闭百科后建筑面板仍锁定时间")

		# 部队。
		_check(bool(_map.call("open_party_panel")), "建筑面板打开时可打开部队")
		_check(_time_buttons_disabled(), "打开部队后时间控制仍禁用")
		_map.call("close_party_panel")
		_check(_settlement_panel.visible, "关闭部队后建筑面板仍在")
		_check(_time_buttons_disabled(), "关闭部队后建筑面板仍锁定时间")

		# 背包。
		_check(bool(_map.call("open_inventory")), "建筑面板打开时可打开背包")
		_check(_time_buttons_disabled(), "打开背包后时间控制仍禁用")
		_map.call("close_inventory")
		_check(_settlement_panel.visible, "关闭背包后建筑面板仍在")
		_check(_time_buttons_disabled(), "关闭背包后建筑面板仍锁定时间")

		# 事件。
		_check(bool(_map.call("open_event_center")), "建筑面板打开时可打开事件中心")
		_check(_time_buttons_disabled(), "打开事件中心后时间控制仍禁用")
		_map.call("close_event_center")
		_check(_settlement_panel.visible, "关闭事件中心后建筑面板仍在")
		_check(_time_buttons_disabled(), "关闭事件中心后建筑面板仍锁定时间")

		_map.call("_on_settlement_leave_pressed")
		_check(not _settlement_panel.visible, "%s 建筑面板已关闭" % settlement.display_name)
		_check(not _time_buttons_disabled(), "离开地点后恢复时间控制入口")
		var world_pause: bool = TimeManager.has_pause_reason(
			GameManager.PAUSE_REASON_UI_PANEL
		)
		_check(not world_pause, "离开地点后没有残留 UI 暂停")


func _open_settlement_panel(settlement: SettlementData) -> void:
	_party.focus_party_id = ""
	_party.current_order = PartyData.OrderType.NONE
	_party.current_target_id = ""
	_party.world_position = settlement.world_position
	_party.target_position = settlement.world_position
	_party.movement_state = PartyData.MovementState.IDLE
	_map.call("handle_left_click", settlement.world_position)


func _click(node_name: String) -> void:
	var button := _map.find_child(node_name, true, false) as Button
	if button != null:
		button.pressed.emit()


func _time_buttons_disabled() -> bool:
	for node_name: String in ["PauseButton", "SpeedOneButton", "SpeedTwoButton"]:
		var button := _map.find_child(node_name, true, false) as Button
		if button == null or not button.disabled:
			return false
	return true


func _format_signed(amount: int) -> String:
	return "+%d" % amount if amount >= 0 else "-%d" % absi(amount)


func _find_settlement(display_name: String) -> SettlementData:
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement != null and settlement.display_name == display_name:
			return settlement
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[main_map_info] OK: %s" % message)
	else:
		_failed = true
		push_error("[main_map_info] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_map):
		_map.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
