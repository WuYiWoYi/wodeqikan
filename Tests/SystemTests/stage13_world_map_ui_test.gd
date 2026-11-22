extends Node
## 阶段 13 Step 1 大地图表现测试：
## 建筑家族旗帜、图标/文本对齐、半透明底板、停留部队旗帜条、
## 圆形旗帜内部放大，以及玩家/NPC 移速展示。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/stage13_world_map_ui_test.tscn

var _failed: bool = false
var _context: WorldContext = null
var _map: Node = null
var _player: PartyData = null
var _merchant: PartyData = null
var _guard: PartyData = null
var _village: SettlementData = null
var _castle: SettlementData = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[s13map] 测试失败")
		get_tree().quit(1)
	else:
		print("[s13map] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)

	_context = WorldContext.new()
	_context.name = "Stage13WorldMapUiContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return
	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id

	_player = _context.get_player_party()
	_merchant = _find_party("河畔商队")
	_guard = _find_party("北境巡逻队")
	_village = _find_settlement(WorldInitializer.BARI_VILLAGE_NAME)
	_castle = _find_settlement(WorldInitializer.OLIN_CASTLE_NAME)
	_check(
		_player != null and _merchant != null and _guard != null,
		"找到玩家与 NPC 部队"
	)
	_check(_village != null and _castle != null, "找到村庄与城堡")
	if _player == null or _merchant == null or _guard == null \
			or _village == null or _castle == null:
		return

	var packed := load("res://Scenes/WorldMap/world_map.tscn") as PackedScene
	_map = packed.instantiate()
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame

	_test_settlement_family_flag()
	_test_background_and_alignment()
	_test_party_flag_inside_circle()
	_test_stationed_banners()
	_test_multiple_settlements()
	_test_speed_display()
	_test_party_removal_restores_icon()


func _test_settlement_family_flag() -> void:
	var tag := _map.call(
		"get_settlement_name_tag", _village.settlement_id
	) as SettlementNameTag
	_check(tag != null, "村庄名称标签存在")
	if tag == null:
		return
	_check(
		tag.has_family_badge() == not _village.family_id.is_empty(),
		"有家族的地点显示家族徽章"
	)
	var family := _context.family_registry.get_config(_village.family_id)
	_check(family != null, "读取村庄家族配置")
	if family != null:
		_check(
			tag.get_badge_flag_texture_path() == family.banner_texture_path,
			"建筑徽章使用家族旗帜美术"
		)
		_check(
			tag.get_badge_flag_texture_path().ends_with("巴里旗帜16_16.png"),
			"徽章旗帜来自现有家族美术配置"
		)

	# 家族归属变化后名称标签重建为新家族旗帜。
	var original_family_id := _village.family_id
	# FamilyRegistry 以 family_id 查询；从现有家族中挑一个不同的。
	var replacement: FamilyConfig = null
	for candidate: FamilyConfig in _context.family_registry.get_all_configs():
		if candidate != null and candidate.family_id != original_family_id:
			replacement = candidate
			break
	_check(replacement != null, "找到用于归属变化的家族")
	if replacement != null:
		_village.family_id = replacement.family_id
		_map.call("_update_settlement_name_tags")
		_check(
			tag.get_bound_family_id() == replacement.family_id,
			"建筑归属变化后标签重新绑定"
		)
		_check(
			tag.get_badge_flag_texture_path() == replacement.banner_texture_path,
			"建筑归属变化后显示新家族旗帜"
		)
		_village.family_id = original_family_id
		_map.call("_update_settlement_name_tags")
		_check(
			tag.get_badge_flag_texture_path() == family.banner_texture_path,
			"恢复原家族后旗帜同步恢复"
		)


func _test_background_and_alignment() -> void:
	var tag := _map.call(
		"get_settlement_name_tag", _village.settlement_id
	) as SettlementNameTag
	if tag == null:
		return
	var background := tag.get_background_control()
	_check(background != null, "名称组合带有半透明底板")
	if background == null:
		return
	var row := tag.get_row_control()
	_check(
		background.get_index() == 0 and row != null
			and row.get_index() > background.get_index(),
		"底板绘制在徽章与名称之后（底层）"
	)
	_check(
		background.size.x <= SettlementNameTag.TAG_WIDTH
			and background.size.y <= SettlementNameTag.TAG_HEIGHT,
		"底板尺寸不超出名称组合"
	)
	_check(
		background.size.x > 0.0 and background.position.x >= 0.0,
		"底板按内容动态尺寸并保持居中（size=%s, pos=%s）"
			% [background.size, background.position]
	)
	var badge := tag.get_badge()
	var name_label := tag.get_name_label()
	_check(
		badge != null and name_label != null
			and badge.size_flags_vertical == Control.SIZE_SHRINK_CENTER
			and name_label.size_flags_vertical == Control.SIZE_SHRINK_CENTER,
		"徽章与名称在行内垂直居中"
	)
	if badge != null and badge.has_method("get_draw_center"):
		_check(
			badge.get_draw_center() == Vector2(18.0, 18.0),
			"圆形徽章绘制中心位于控件内，而非左上角"
		)


func _test_party_flag_inside_circle() -> void:
	var style := load(
		"res://Data/WorldMap/party_marker_style.tres"
	) as PartyMarkerStyle
	_check(style != null, "加载部队标记样式")
	if style == null:
		return
	_check(is_equal_approx(style.marker_radius, 18.0), "圆形外径保持 18")
	_check(is_equal_approx(style.border_width, 2.0), "圆形边框保持 2")
	_check(style.flag_max_size > 44.0, "圆形内部旗帜进一步放大")
	_check(
		style.get_flag_clip_uv_radius() < 0.5,
		"放大后的旗帜仍被圆形遮罩裁剪"
	)
	var icon := _map.find_child(
		"PartyIcon_%s" % _guard.party_id, true, false
	) as PartyIcon
	_check(icon != null and icon.get_marker_radius() == style.marker_radius,
		"部队图标使用统一圆形尺寸")


func _test_stationed_banners() -> void:
	# 商队停留在地点上：隐藏圆形图标，只显示地点下方旗帜。
	_place_party(_merchant, _village.world_position)
	# 把镜头与玩家移到村庄附近，确保建筑/旗帜条在可见区域内。
	_place_party(_player, _village.world_position + Vector2(120.0, 0.0))
	_map.camera.position = _player.world_position
	_map.camera.force_update_scroll()
	_map.call("_process", 0.016)
	_check(
		_map.call("is_party_stationed", _merchant.party_id),
		"按实际坐标判定商队停留在村庄"
	)
	_check(
		str(_map.call("get_stationed_settlement_id", _merchant.party_id))
			== _village.settlement_id,
		"停留部队归属到正确建筑"
	)
	var icon := _map.find_child(
		"PartyIcon_%s" % _merchant.party_id, true, false
	) as PartyIcon
	_check(icon != null and not icon.visible, "停留部队隐藏普通圆形图标")
	var bar := _map.call(
		"get_stationed_bar", _village.settlement_id
	) as SettlementStationedBar
	_check(bar != null, "村庄拥有独立的停留部队旗帜条")
	if bar != null:
		var tag := _map.call(
			"get_settlement_name_tag", _village.settlement_id
		) as SettlementNameTag
		_check(bar.visible, "有停留部队时旗帜条可见")
		_check(
			bar.get_banner_party_ids().has(_merchant.party_id),
			"旗帜条显示停留部队"
		)
		_check(
			tag != null and bar.position.y > tag.position.y,
			"旗帜条位于建筑名称 UI 下方"
		)

	# 离开建筑：恢复图标并移除旗帜，绝不两处同时显示。
	_move_party_far(_merchant)
	_map.call("_process", 0.016)
	_check(
		not _map.call("is_party_stationed", _merchant.party_id),
		"离开建筑后不再判定为停留"
	)
	_check(icon != null and icon.visible, "离开建筑后恢复普通图标")
	if bar != null:
		_check(
			not bar.get_banner_party_ids().has(_merchant.party_id),
			"离开建筑后移除旗帜"
		)
		_check(not bar.visible, "没有停留部队时旗帜条隐藏")

	# 移动中的部队即使位于建筑坐标上也不算停留。
	_move_party_far(_merchant)
	_merchant.world_position = _village.world_position
	_merchant.target_position = _village.world_position + Vector2(200.0, 0.0)
	_merchant.movement_state = PartyData.MovementState.MOVING
	_map.call("_process", 0.016)
	_check(
		not _map.call("is_party_stationed", _merchant.party_id),
		"移动中的部队不算停留"
	)


func _test_multiple_settlements() -> void:
	_place_party(_merchant, _village.world_position)
	_place_party(_guard, _castle.world_position)
	_map.call("_process", 0.016)
	var village_bar := _map.call(
		"get_stationed_bar", _village.settlement_id
	) as SettlementStationedBar
	var castle_bar := _map.call(
		"get_stationed_bar", _castle.settlement_id
	) as SettlementStationedBar
	_check(village_bar != null and castle_bar != null, "不同建筑各自维护旗帜条")
	if village_bar != null and castle_bar != null:
		_check(
			village_bar.get_banner_party_ids() == [_merchant.party_id],
			"村庄旗帜条只包含自己的停留部队"
		)
		_check(
			castle_bar.get_banner_party_ids() == [_guard.party_id],
			"城堡旗帜条只包含自己的停留部队"
		)

	# 多支部队时按行排列并换行；直接验证旗帜条组件，避免污染世界数据。
	var standalone := SettlementStationedBar.new()
	standalone.name = "StandaloneStationedBar"
	add_child(standalone)
	var entries: Array[Dictionary] = []
	for index: int in range(12):
		entries.append({
			"party_id": "p%02d" % index,
			"display_name": "部队%d" % index,
			"texture": null,
			"texture_path": "",
			"color": Color.WHITE,
		})
	standalone.set_entries(entries)
	var per_row: int = standalone.get_per_row_count()
	_check(standalone.get_banner_count() == 12, "旗帜条容纳全部停留部队")
	_check(per_row > 1 and per_row < 12, "单行容量受限")
	_check(
		standalone.size.y > SettlementStationedBar.BANNER_SIZE.y,
		"超过单行容量后自动换行"
	)
	standalone.queue_free()

	_move_party_far(_merchant)
	# 与商队保持不同坐标，避免后续悬浮命中另一支部队。
	_place_party(_guard, Vector2(4200.0, 2400.0))
	_map.call("_process", 0.016)


func _test_speed_display() -> void:
	_place_party(_merchant, Vector2(4200.0, 2800.0))
	_place_party(_player, Vector2(1600.0, 2200.0))
	_map.call("_process", 0.016)

	var expected_player_speed: float = (
		_context.world_map_manager.get_effective_movement_speed(_player)
	)
	var info_label := _find_label_with_prefix(_map, _player.party_name)
	_check(info_label != null, "底部玩家信息栏存在")
	if info_label != null:
		_check(info_label.text.contains("移动速度："), "玩家信息栏显示移动速度")
		_check(
			info_label.text.contains("%.1f" % expected_player_speed),
			"玩家移速使用统一最终速度"
		)
		_check(
			info_label.text.contains("坐标") and info_label.text.contains("状态"),
			"移速不挤掉原有信息"
		)

	_map.call("set_alt_detail_active", false)
	_map.call("apply_hover_for_test", _merchant.world_position)
	var hover_text: String = str(_map.call("get_hover_panel_text"))
	_check(hover_text.contains("移动速度："), "NPC 悬浮面板显示移速")
	_check(
		hover_text.contains(
			"%.1f" % _context.world_map_manager.get_effective_movement_speed(
				_merchant
			)
		),
		"NPC 移速与统一入口一致（实际：%s）" % hover_text.replace("\n", " / ")
	)
	_check(
		hover_text.contains(_merchant.party_name),
		"移速行不替代原有名称信息（实际：%s）" % hover_text.replace("\n", " / ")
	)

	# 停止状态同样显示速度，不因 IDLE 隐藏。
	_merchant.movement_state = PartyData.MovementState.IDLE
	_map.call("_process", 0.016)
	_map.call("apply_hover_for_test", _merchant.world_position)
	_check(
		str(_map.call("get_hover_panel_text")).contains("移动速度："),
		"停止时仍显示移速"
	)
	_map.call("clear_hover_for_test")


func _test_party_removal_restores_icon() -> void:
	_place_party(_merchant, _village.world_position)
	_map.call("_process", 0.016)
	var bar := _map.call(
		"get_stationed_bar", _village.settlement_id
	) as SettlementStationedBar
	if bar != null:
		_check(bar.get_banner_party_ids().has(_merchant.party_id), "移除前旗帜存在")
	# 模拟部队被消灭/解散：直接移除部队后，旗帜与遗留图标都必须清理。
	_check(
		_context.party_manager.remove_party(_merchant.party_id),
		"移除测试部队"
	)
	_map.call("_process", 0.016)
	_check(
		not _map.call("is_party_stationed", _merchant.party_id),
		"部队移除后不再停留在建筑"
	)
	if bar != null:
		_check(
			not bar.get_banner_party_ids().has(_merchant.party_id),
			"部队移除后旗帜同步消失"
		)
	var icon := _map.find_child(
		"PartyIcon_%s" % _merchant.party_id, true, false
	) as PartyIcon
	_check(
		icon == null or not icon.visible,
		"部队移除后不保留可见图标"
	)


func _place_party(party: PartyData, position: Vector2) -> void:
	party.world_position = position
	party.target_position = position
	party.movement_state = PartyData.MovementState.IDLE


func _move_party_far(party: PartyData) -> void:
	_place_party(party, Vector2(4200.0, 2800.0))


func _find_label_with_prefix(root: Node, prefix: String) -> Label:
	for child: Node in root.find_children("*", "Label", true, false):
		var label := child as Label
		if label != null and label.text.begins_with(prefix):
			return label
	return null


func _find_party(party_name: String) -> PartyData:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _find_settlement(display_name: String) -> SettlementData:
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement.display_name == display_name:
			return settlement
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[s13map] OK: %s" % message)
	else:
		_failed = true
		push_error("[s13map] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_map):
		_map.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
