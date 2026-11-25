extends Node
## 大地图部队管理面板测试：入口、概览、成员列表、详情切换、装备显示与暂停恢复。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/party_panel_test.tscn

var _failed: bool = false
var _context: WorldContext = null
var _map: Node = null
var _player: PartyData = null
var _panel: PartyPanel = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[partyui] 测试失败")
		get_tree().quit(1)
	else:
		print("[partyui] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)

	_context = WorldContext.new()
	_context.name = "PartyPanelTestContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")

	_player = _context.get_player_party()
	_check(_player != null, "玩家部队存在")
	if _player == null:
		return
	_check(
		_player.member_unit_ids.size() == WorldInitializer.PLAYER_TOTAL_MEMBER_COUNT,
		"玩家初始兵力完整"
	)

	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id

	var packed_map := load("res://Scenes/WorldMap/world_map.tscn") as PackedScene
	_map = packed_map.instantiate()
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame

	await _test_open_and_overview()
	await _test_member_list_and_switch()
	await _test_equipment_display()
	await _test_equipment_permissions()
	await _test_preview()
	await _test_invalid_member_reference()
	await _test_close_and_pause_stack()


func _test_open_and_overview() -> void:
	var button := _map.find_child("PartyButton", true, false) as Button
	_check(button != null, "大地图存在部队按钮")
	if button == null:
		return

	TimeManager.set_base_world_speed(TimeManager.SPEED_DOUBLE)
	TimeManager.clear_pauses()
	button.pressed.emit()
	await get_tree().process_frame

	_panel = _map.find_child("PartyPanel", true, false) as PartyPanel
	_check(_panel != null and _panel.visible, "点击部队按钮打开面板")
	if _panel == null or not _panel.visible:
		return
	_check(is_zero_approx(TimeManager.get_effective_world_scale()), "面板打开时世界暂停")
	_check(
		is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_DOUBLE),
		"打开面板不修改基础倍率"
	)
	_check(
		not bool(_map.call("request_player_move", Vector2(900.0, 700.0))),
		"面板打开时地图点击被拦截"
	)

	var name_label := _panel.find_child("PartyPanelNameLabel", true, false) as Label
	var faction_label := _panel.find_child("PartyPanelFactionLabel", true, false) as Label
	var count_label := _panel.find_child("PartyPanelMemberCountLabel", true, false) as Label
	var speed_label := _panel.find_child("PartyPanelSpeedLabel", true, false) as Label
	var state_label := _panel.find_child("PartyPanelStateLabel", true, false) as Label
	var movement_label := _panel.find_child("PartyPanelMovementLabel", true, false) as Label
	_check(name_label != null and name_label.text == _player.party_name, "显示部队名称")
	_check(faction_label != null and faction_label.text.contains("玩家"), "显示玩家阵营")
	_check(
		count_label != null and count_label.text.contains(str(_player.member_unit_ids.size())),
		"成员数量与 PartyData 一致"
	)
	_check(speed_label != null and speed_label.text.contains("150"), "显示部队移动速度")
	_check(state_label != null and state_label.text.contains("可用"), "显示部队状态")
	_check(movement_label != null and movement_label.text.contains("待命"), "显示待命状态")

	_player.movement_state = PartyData.MovementState.MOVING
	_player.target_position = Vector2(900.0, 700.0)
	_panel.refresh()
	_check(movement_label.text.contains("移动中"), "移动时显示移动中")
	var target_label := _panel.find_child("PartyPanelTargetLabel", true, false) as Label
	_check(target_label != null and target_label.text.contains("900"), "移动时显示目标坐标")
	_player.movement_state = PartyData.MovementState.IDLE
	_panel.refresh()


func _test_member_list_and_switch() -> void:
	if _panel == null:
		return
	var list := _panel.find_child("PartyMemberList", true, false) as GridContainer
	_check(list != null, "存在士兵列表")
	if list == null:
		return
	_check(list.columns == 2, "士兵列表使用双列排列")
	_check(list.get_child_count() == _player.member_unit_ids.size(), "列表人数与 PartyData 一致")
	var prisoner_list := _panel.find_child("PartyPrisonerList", true, false) as GridContainer
	_check(
		prisoner_list != null and prisoner_list.columns == 2,
		"俘虏列表使用双列排列"
	)

	var seen: Dictionary = {}
	for child: Node in list.get_children():
		var item := child as PartyMemberItem
		_check(item != null, "列表项类型正确")
		if item != null:
			_check(not seen.has(item.unit_id), "同一士兵只显示一次")
			seen[item.unit_id] = true
	_check(seen.size() == _player.member_unit_ids.size(), "列表人数与 PartyData 一致")

	var first_id: String = _player.member_unit_ids[0]
	var first_unit := _context.unit_manager.get_unit(first_id)
	_check(_panel.get_selected_unit_id() == first_id, "默认选中第一名士兵")

	var first_item := _panel.find_child("MemberItem_%s" % first_id, true, false) as PartyMemberItem
	_check(first_item != null, "第一名士兵列表项存在")
	if first_item != null:
		var member_name := first_item.find_child("MemberName", true, false) as Label
		var member_exp := first_item.find_child("MemberCombatExperience", true, false) as Label
		var member_hp := first_item.find_child("MemberHp", true, false) as Label
		_check(member_name != null and member_name.text == first_unit.display_name, "列表显示姓名")
		_check(
			member_exp != null
				and member_exp.text == "战斗经验：%s" % CombatExperience.tier_name_for_level(
					first_unit.level
				),
			"列表显示战斗经验文本等级"
		)
		_check(
			member_hp != null
				and member_hp.text.contains("%d / %d" % [first_unit.current_hp, first_unit.max_hp]),
			"列表显示当前生命值"
		)
		_check(first_item.find_child("MemberClass", true, false) == null, "列表不再显示兵种文字")
		_check(first_item.find_child("MemberStats", true, false) == null, "列表不再显示攻击等额外属性")
		_check(first_item.get_thumbnail() != null, "列表保留头像缩略图")

	var detail_name := _panel.find_child("DetailUnitName", true, false) as Label
	var detail_class := _panel.find_child("DetailUnitClass", true, false) as Label
	var detail_class_type := _panel.find_child("DetailUnitClassType", true, false) as Label
	var detail_combat_exp := _panel.find_child("DetailCombatExperience", true, false) as Label
	var detail_hp := _panel.find_child("DetailHp", true, false) as Label
	var detail_attack := _panel.find_child("DetailAttack", true, false) as Label
	var detail_interval := _panel.find_child("DetailAttackInterval", true, false) as Label
	var detail_speed := _panel.find_child("DetailMoveSpeed", true, false) as Label
	var detail_range := _panel.find_child("DetailAttackRange", true, false) as Label
	_check(detail_name != null and detail_name.text == first_unit.display_name, "默认显示第一名士兵名称")
	_check(detail_class != null and detail_class.text.contains("民兵"), "兵种名称正确")
	_check(detail_class_type != null and detail_class_type.text.contains("步兵"), "兵种类型正确")
	_check(
		detail_combat_exp != null
			and detail_combat_exp.text == "战斗经验：新兵",
		"详情以文本显示战斗经验"
	)
	_check(_panel.find_child("DetailLevel", true, false) == null, "详情不再显示数值等级")
	_check(_panel.find_child("DetailExp", true, false) == null, "详情不再显示经验数值")
	_check(_panel.find_child("DetailExpProgress", true, false) == null, "详情不再显示经验进度条")
	_check(_panel.find_child("DetailUnitId", true, false) == null, "详情不再显示内部 ID")
	_check(
		detail_hp != null and detail_hp.text.contains("%d / %d" % [first_unit.current_hp, first_unit.max_hp]),
		"HP 显示正确"
	)
	_check(detail_attack != null and detail_attack.text.contains(str(first_unit.attack)), "攻击显示正确")
	_check(detail_interval != null and detail_interval.text.contains("1.20"), "攻击间隔显示正确")
	_check(detail_speed != null and detail_speed.text.contains("60"), "移动速度显示正确")
	_check(detail_range != null and detail_range.text.contains("20"), "攻击距离显示正确")

	var second_id: String = _player.member_unit_ids[1]
	var second_item := _panel.find_child("MemberItem_%s" % second_id, true, false) as PartyMemberItem
	_check(second_item != null, "第二名士兵列表项存在")
	if second_item != null:
		second_item.pressed.emit()
		await get_tree().process_frame
		var second_unit := _context.unit_manager.get_unit(second_id)
		_check(_panel.get_selected_unit_id() == second_id, "点击后切换选中士兵")
		_check(detail_name.text == second_unit.display_name, "详情切换到第二名士兵")
		_check(second_item.is_selected(), "选中项有选中状态")

	var third_id: String = _player.member_unit_ids[2]
	var third_item := _panel.find_child("MemberItem_%s" % third_id, true, false) as PartyMemberItem
	if third_item != null:
		third_item.pressed.emit()
		await get_tree().process_frame


func _test_equipment_display() -> void:
	if _panel == null:
		return
	var weapon_label := _panel.find_child("DetailEquipment_WEAPON", true, false) as Label
	var offhand_label := _panel.find_child("DetailEquipment_OFFHAND", true, false) as Label
	_check(weapon_label != null and weapon_label.text.contains("无"), "空武器槽显示无")
	_check(offhand_label != null and offhand_label.text.contains("无"), "空副手槽显示无")

	var selected_id: String = _panel.get_selected_unit_id()
	_check(
		_context.unit_manager.equip_item(selected_id, "weapon_sword_01"),
		"数据层装备铁剑"
	)
	_panel.refresh()
	var detail_attack := _panel.find_child("DetailAttack", true, false) as Label
	_check(weapon_label.text.contains("铁剑"), "装备槽显示装备名称")
	_check(weapon_label.text.contains("攻击 +2"), "装备槽显示真实属性加成")
	_check(detail_attack != null and detail_attack.text.contains("12"), "装备后详情读取最终攻击")

	_check(
		_context.unit_manager.equip_item(selected_id, "mount_horse_01"),
		"数据层装备坐骑"
	)
	_panel.refresh()
	var mount_label := _panel.find_child("DetailEquipment_MOUNT", true, false) as Label
	_check(mount_label != null and mount_label.text.contains("普通战马"), "坐骑槽显示装备名称")
	var mount_state := _panel.find_child("DetailMountState", true, false) as Label
	_check(mount_state != null and mount_state.text.contains("骑乘"), "详情显示骑乘状态")


## 普通士兵可在详情面板更换装备；雇佣兵只能查看，装备与坐骑管理必须隐藏。
func _test_equipment_permissions() -> void:
	if _panel == null:
		return
	# _test_equipment_display 已给当前选中单位装备铁剑与坐骑，这里直接沿用。
	var normal_id: String = _panel.get_selected_unit_id()
	var normal_unit := _context.unit_manager.get_unit(normal_id)
	_check(
		normal_unit != null and not normal_unit.is_mercenary,
		"普通士兵用于装备权限测试"
	)
	if normal_unit == null:
		return

	var lock_label := _panel.find_child(
		"DetailMercenaryEquipmentLock", true, false
	) as Label
	var management := _panel.find_child(
		"DetailEquipmentManagement", true, false
	) as VBoxContainer
	var mount_section := _panel.find_child(
		"DetailMountSection", true, false
	) as VBoxContainer
	_check(lock_label != null and not lock_label.visible, "普通士兵不显示雇佣兵锁定提示")
	_check(management != null and management.visible, "普通士兵显示装备管理")
	_check(mount_section != null and mount_section.visible, "普通士兵显示坐骑管理")

	# 先卸下当前武器，保证后面的“更换”一定产生一次真实写入。
	var weapon_id: String = str(normal_unit.equipment.get("WEAPON", ""))
	if not weapon_id.is_empty():
		var unequip_button := _panel.find_child(
			"DetailUnequipButton_WEAPON", true, false
		) as Button
		_check(unequip_button != null and not unequip_button.disabled, "普通士兵可卸下武器")
		var stock_before: int = _context.player_profile.get_item_count(weapon_id)
		if unequip_button != null:
			unequip_button.pressed.emit()
			await get_tree().process_frame
		_check(not normal_unit.equipment.has("WEAPON"), "UI 卸下装备写入单位数据")
		_check(
			_context.player_profile.get_item_count(weapon_id) == stock_before + 1,
			"卸下装备返还玩家背包"
		)

	var option := _panel.find_child(
		"DetailEquipOption_WEAPON", true, false
	) as OptionButton
	var equip_button := _panel.find_child(
		"DetailEquipButton_WEAPON", true, false
	) as Button
	_check(option != null and equip_button != null, "普通士兵存在换装控件")
	var chosen_id: String = ""
	if option != null:
		for index: int in range(option.item_count):
			var metadata: Variant = option.get_item_metadata(index)
			if metadata is String and not (metadata as String).is_empty():
				option.select(index)
				chosen_id = metadata
				break
	_check(not chosen_id.is_empty(), "背包中有可更换武器")
	if chosen_id.is_empty() or equip_button == null:
		return
	var selected_stock_before: int = _context.player_profile.get_item_count(chosen_id)
	equip_button.pressed.emit()
	await get_tree().process_frame
	_check(
		str(normal_unit.equipment.get("WEAPON", "")) == chosen_id,
		"UI 更换装备写入单位数据"
	)
	_check(
		_context.player_profile.get_item_count(chosen_id) == selected_stock_before - 1,
		"更换装备从玩家背包扣除"
	)

	# 招募一名雇佣兵，验证其详情页面的装备管理被锁定。
	var manager: MercenaryManager = _context.mercenary_manager
	var town := _find_settlement(WorldInitializer.BURKNANIA_TOWN_NAME)
	_check(town != null, "找到用于招募的城市")
	if town == null:
		return
	var stationed: Array[MercenaryData] = manager.get_stationed_mercenaries(
		town.settlement_id
	)
	_check(not stationed.is_empty(), "城市酒馆有驻留雇佣兵")
	if stationed.is_empty():
		return
	var result: Dictionary = manager.recruit_mercenary_for_player(
		stationed[0].mercenary_id,
		town.settlement_id,
		_context.player_profile,
		_context.player_party_id
	)
	_check(bool(result.get("success", false)), "测试准备：雇佣兵加入玩家部队")
	var mercenary_unit_id: String = str(result.get("unit_id", ""))
	if mercenary_unit_id.is_empty():
		return
	_panel.refresh()
	await get_tree().process_frame
	var mercenary_item := _panel.find_child(
		"MemberItem_%s" % mercenary_unit_id, true, false
	) as PartyMemberItem
	_check(mercenary_item != null, "雇佣兵出现在成员列表")
	if mercenary_item == null:
		return
	mercenary_item.pressed.emit()
	await get_tree().process_frame

	var mercenary_unit := _context.unit_manager.get_unit(mercenary_unit_id)
	_check(mercenary_unit != null and mercenary_unit.is_mercenary, "雇佣兵身份显式记录")
	_check(mercenary_unit != null and not mercenary_unit.can_manage_equipment(),
		"雇佣兵在当前实现中禁止管理装备")
	lock_label = _panel.find_child(
		"DetailMercenaryEquipmentLock", true, false
	) as Label
	management = _panel.find_child(
		"DetailEquipmentManagement", true, false
	) as VBoxContainer
	mount_section = _panel.find_child(
		"DetailMountSection", true, false
	) as VBoxContainer
	_check(lock_label != null and lock_label.visible, "雇佣兵显示装备锁定提示")
	_check(management != null and not management.visible, "雇佣兵隐藏装备管理")
	_check(mount_section != null and not mount_section.visible, "雇佣兵隐藏坐骑管理")
	_check(
		_panel.find_child("DetailEquipButton_WEAPON", true, false) == null,
		"雇佣兵没有更换装备按钮"
	)
	_check(
		_panel.find_child("DetailUnequipButton_WEAPON", true, false) == null,
		"雇佣兵没有卸下装备按钮"
	)
	# 数据层也必须拒绝，不能只靠隐藏 UI。
	_check(
		not _context.unit_manager.unequip_slot_to_holder(
			mercenary_unit_id, "WEAPON", _context.player_profile
		),
		"数据层拒绝雇佣兵卸下装备"
	)


func _test_preview() -> void:
	if _panel == null:
		return
	var preview := _panel.find_child("PreviewUnitVisual", true, false) as UnitVisual
	_check(preview != null, "士兵详情包含美术预览")
	_check(
		_panel.find_child("DetailPreviewTitle", true, false) == null,
		"详情不再显示美术预览标题"
	)
	if preview == null:
		return
	_check(preview.scale.x > 2.0, "详情美术预览图片已放大")
	_check(preview.get_human_visual() != null, "预览使用人物表现组")
	_check(preview.get_horse_visual() != null, "预览使用马匹表现组")
	_check(preview.has_part("Body"), "预览显示人物身体")

	# 显式选一名步兵，避免受前一个装备测试给选中单位装备马匹的影响。
	var foot_id: String = ""
	for unit_id: String in _player.member_unit_ids:
		var unit := _context.unit_manager.get_unit(unit_id)
		if unit != null and not unit.is_mounted:
			foot_id = unit_id
			break
	_check(not foot_id.is_empty(), "玩家部队存在步兵")
	var foot_item := _panel.find_child(
		"MemberItem_%s" % foot_id, true, false
	) as PartyMemberItem
	if foot_item != null:
		foot_item.pressed.emit()
		await get_tree().process_frame
		_check(preview.unit_data != null and preview.unit_data.unit_id == foot_id,
			"步兵预览同步到选中士兵")
		_check(preview.get_horse_visual().visible == false, "步兵预览不显示马匹部件")
		_check(preview.get_part("FootShadow").is_visible_in_tree(), "步兵预览显示人物影子")

		# 预览复用 UnitVisual 的待机动画，而不是静态贴图。
		var foot_upper: Node2D = preview.get_human_visual().get_upper_body()
		var idle_rotation_before: float = foot_upper.rotation
		var idle_bob_before: float = foot_upper.position.y
		await get_tree().create_timer(0.6).timeout
		_check(
			absf(angle_difference(foot_upper.rotation, idle_rotation_before)) > 0.001
				or absf(foot_upper.position.y - idle_bob_before) > 0.05,
			"步兵 UI 预览播放待机动画"
		)

	var mounted_id: String = ""
	var fallback_mounted_id: String = ""
	for unit_id: String in _player.member_unit_ids:
		var unit := _context.unit_manager.get_unit(unit_id)
		if unit == null or not unit.is_mounted:
			continue
		if fallback_mounted_id.is_empty():
			fallback_mounted_id = unit_id
		if unit.config_id == "infantry_trained":
			mounted_id = unit_id
			break
	if mounted_id.is_empty():
		mounted_id = fallback_mounted_id
	_check(not mounted_id.is_empty(), "玩家部队存在骑乘士兵")
	if mounted_id.is_empty():
		return

	var mounted_item := _panel.find_child(
		"MemberItem_%s" % mounted_id, true, false
	) as PartyMemberItem
	_check(mounted_item != null, "列表包含骑乘士兵")
	if mounted_item == null:
		return
	var unit_count_before: int = _context.unit_manager.get_all_units().size()
	var mount_stock_before: int = _context.player_profile.get_item_count("mount_horse_01")
	var mounted_unit := _context.unit_manager.get_unit(mounted_id)
	var hp_before: int = mounted_unit.current_hp
	var equipment_before: Dictionary = mounted_unit.equipment.duplicate(true)

	mounted_item.pressed.emit()
	await get_tree().process_frame
	_check(_panel.get_selected_unit_id() == mounted_id, "切换到骑乘士兵")
	_check(preview.unit_data != null and preview.unit_data.unit_id == mounted_id,
		"预览同步到选中士兵")
	_check(preview.get_horse_visual().visible, "骑兵预览显示马匹表现组")
	_check(preview.get_part("MountBody").is_visible_in_tree(), "骑兵预览显示马身")
	_check(preview.get_part("MountSaddle").is_visible_in_tree(), "骑兵预览显示马鞍")
	_check(not preview.get_part("FootShadow").visible, "骑兵预览隐藏人物影子")
	_check(preview.get_part("MountShadow").is_visible_in_tree(), "骑兵预览显示骑马影子")
	_check(preview.get_part("LegLeft").is_visible_in_tree(), "骑兵预览保留人体双腿")
	_check(
		is_equal_approx(
			preview.get_human_visual().position.y,
			-15.0 + preview.get_horse_visual().get_body_offset_y()
		),
		"骑兵预览人物跟随马身起伏并保持 15 像素基础偏移"
	)
	_check(
		is_equal_approx(preview.get_human_visual().position.x, 3.0),
		"骑兵预览人物相对马匹向右偏移 3 像素"
	)

	# 骑乘预览播放马匹/骑手待机动画，且两者周期同步。
	var horse_rig: Node2D = preview.get_horse_visual().get_body_rig()
	var horse_bob_before: float = horse_rig.position.y
	var mounted_upper: Node2D = preview.get_human_visual().get_upper_body()
	var rider_bob_before: float = mounted_upper.position.y
	await get_tree().create_timer(0.6).timeout
	_check(
		absf(horse_rig.position.y - horse_bob_before) > 0.1,
		"骑兵 UI 预览播放马匹待机起伏"
	)
	_check(
		is_equal_approx(
			preview.get_human_visual().position.y,
			-15.0 + horse_rig.position.y
		),
		"骑兵 UI 预览骑手整体跟随马身"
	)
	_check(
		absf(mounted_upper.position.y - rider_bob_before) > 0.05,
		"骑兵 UI 预览骑手同步待机起伏"
	)
	_check(
		mounted_upper.position.y * horse_rig.position.y >= -0.01,
		"骑兵预览的骑手与马身起伏方向一致"
	)

	_check(mounted_unit.current_hp == hp_before, "预览不修改真实单位 HP")
	_check(
		mounted_unit.equipment.get("MOUNT", "") == equipment_before.get("MOUNT", ""),
		"预览不修改真实装备"
	)
	_check(
		_context.unit_manager.get_all_units().size() == unit_count_before,
		"预览不创建真实单位"
	)
	_check(
		_context.player_profile.get_item_count("mount_horse_01") == mount_stock_before,
		"预览不消耗马匹库存"
	)

	if foot_item != null:
		foot_item.pressed.emit()
		await get_tree().process_frame
		_check(preview.get_horse_visual().visible == false, "切回步兵后预览恢复步兵外观")
		_check(preview.get_part("FootShadow").is_visible_in_tree(), "切回步兵后显示人物影子")

	# 反复切换不累积预览部件/节点。
	var human_child_count: int = preview.get_human_visual().get_child_count()
	var horse_child_count: int = preview.get_horse_visual().get_child_count()
	for i: int in range(4):
		if mounted_item != null:
			mounted_item.pressed.emit()
			await get_tree().process_frame
		if foot_item != null:
			foot_item.pressed.emit()
			await get_tree().process_frame
	_check(
		preview.get_human_visual().get_child_count() == human_child_count,
		"反复切换不累积人物预览节点"
	)
	_check(
		preview.get_horse_visual().get_child_count() == horse_child_count,
		"反复切换不累积马匹预览节点"
	)


func _test_invalid_member_reference() -> void:
	if _panel == null:
		return
	var valid_count: int = _player.member_unit_ids.size()
	_player.member_unit_ids.append("UNIT_999999")
	_panel.refresh()
	await get_tree().process_frame
	var list := _panel.find_child("PartyMemberList", true, false) as GridContainer
	_check(
		list != null and list.get_child_count() == valid_count,
		"无效成员引用不会导致 UI 崩溃"
	)
	_player.member_unit_ids.erase("UNIT_999999")
	_panel.refresh()


func _test_close_and_pause_stack() -> void:
	if _panel == null:
		return
	var close_button := _panel.find_child("PartyPanelCloseButton", true, false) as Button
	_check(close_button != null, "面板存在关闭按钮")
	if close_button == null:
		return

	close_button.pressed.emit()
	await get_tree().process_frame
	_check(not _panel.visible, "关闭后隐藏部队面板")
	var hidden_preview := _panel.find_child("PreviewUnitVisual", true, false) as UnitVisual
	if hidden_preview != null and hidden_preview.unit_data != null:
		var hidden_upper: Node2D = hidden_preview.get_human_visual().get_upper_body()
		var hidden_rotation_before: float = hidden_upper.rotation
		await get_tree().create_timer(0.4).timeout
		_check(
			is_equal_approx(hidden_upper.rotation, hidden_rotation_before),
			"面板隐藏后预览不再推进待机动画"
		)
	_check(
		is_equal_approx(TimeManager.get_effective_world_scale(), TimeManager.SPEED_DOUBLE),
		"关闭后恢复此前基础倍率"
	)
	_check(
		is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_DOUBLE),
		"关闭后基础倍率保持不变"
	)

	TimeManager.push_pause(&"party_panel_test_hold")
	var button := _map.find_child("PartyButton", true, false) as Button
	button.pressed.emit()
	await get_tree().process_frame
	_check(_panel.visible, "存在其他暂停原因时仍可打开")
	_check(is_zero_approx(TimeManager.get_effective_world_scale()), "其他暂停原因保持生效")
	close_button.pressed.emit()
	await get_tree().process_frame
	_check(is_zero_approx(TimeManager.get_effective_world_scale()), "关闭面板不清除其他暂停原因")
	TimeManager.pop_pause(&"party_panel_test_hold")
	_check(
		is_equal_approx(TimeManager.get_effective_world_scale(), TimeManager.SPEED_DOUBLE),
		"移除其他暂停原因后恢复基础倍率"
	)


func _find_settlement(display_name: String) -> SettlementData:
	if _context == null:
		return null
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement != null and settlement.display_name == display_name:
			return settlement
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[partyui] OK: %s" % message)
	else:
		_failed = true
		push_error("[partyui] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_map):
		_map.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
