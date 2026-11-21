extends Node
## 骑乘系统测试：马匹库存消耗/返还、MOUNT 派生状态、骑乘属性与存档兼容。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/mounted_unit_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"
const TRAINED_PATH: String = "res://Data/Units/infantry_trained.tres"
const MOUNT_PATH: String = "res://Data/Equipment/mount_horse_01.tres"
const MOUNT_ID: String = "mount_horse_01"

var _failed: bool = false


func _ready() -> void:
	await _run()
	if _failed:
		push_error("[mounted] 测试失败")
		get_tree().quit(1)
	else:
		print("[mounted] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	var militia: UnitConfig = load(MILITIA_PATH) as UnitConfig
	var trained: UnitConfig = load(TRAINED_PATH) as UnitConfig
	var mount: EquipmentConfig = load(MOUNT_PATH) as EquipmentConfig
	_check(militia != null and trained != null and mount != null, "加载兵种与马匹配置")
	if militia == null or trained == null or mount == null:
		return

	_test_inventory_and_mounting(militia, mount)
	_test_legacy_serialization()
	_test_new_game_composition()
	await _test_world_save_round_trip()


func _test_inventory_and_mounting(militia: UnitConfig, mount: EquipmentConfig) -> void:
	var units := UnitManager.new()
	units.setup(IdGenerator.new())
	_check(units.register_equipment_config(mount), "注册马匹装备")

	var first := units.create_unit(militia, "FACTION_PLAYER")
	var second := units.create_unit(militia, "FACTION_PLAYER")
	_check(first != null and second != null, "创建两名步兵")
	if first == null or second == null:
		return

	var profile := PlayerProfile.new()
	profile.add_item(MOUNT_ID, 1)
	_check(profile.get_item_count(MOUNT_ID) == 1, "物品栏有 1 匹马")

	first.level = 3
	first.exp = 42
	_check(units.recalculate_stats(first.unit_id), "骑乘前重算 3 级属性")
	_check(units.equip_mount(first.unit_id, MOUNT_ID, profile), "第一匹马装备成功")
	_check(first.is_mounted, "装备 MOUNT 后进入骑乘状态")
	_check(first.equipment.get("MOUNT", "") == MOUNT_ID, "MOUNT 槽写入马匹 ID")
	_check(is_equal_approx(first.move_speed, 85.0), "民兵骑乘后移速 60 + 25")
	_check(profile.get_item_count(MOUNT_ID) == 0, "装备消耗 1 匹马")
	_check(first.level == 3 and first.exp == 42, "骑乘不改变等级与经验")
	_check(
		first.config_id == "infantry_militia" and first.faction_id == "FACTION_PLAYER",
		"骑乘不改变兵种配置与阵营身份"
	)

	_check(
		not units.equip_mount(second.unit_id, MOUNT_ID, profile),
		"库存不足时不能骑乘"
	)
	_check(not second.is_mounted, "失败不改变第二名步兵状态")
	_check(
		not units.equip_mount(first.unit_id, MOUNT_ID, profile),
		"已装备同一匹马时不能重复消耗"
	)

	_check(units.unequip_mount(first.unit_id, profile), "卸下马匹成功")
	_check(not first.is_mounted, "卸下后恢复步兵状态")
	_check(is_equal_approx(first.move_speed, 60.0), "卸下后移速恢复")
	_check(profile.get_item_count(MOUNT_ID) == 1, "卸下马匹返还库存")
	_check(first.level == 3 and first.exp == 42, "卸下马匹不改变等级与经验")

	_check(units.equip_mount(second.unit_id, MOUNT_ID, profile), "马匹可以再装备给另一名士兵")
	_check(second.is_mounted and not first.is_mounted, "同一匹马不会同时装备给两人")

	# 替换坐骑时，旧坐骑返还库存。
	var horse_two := EquipmentConfig.new()
	horse_two.equipment_id = "mount_horse_02"
	horse_two.display_name = "备用战马"
	horse_two.slot = EquipmentConfig.Slot.MOUNT
	horse_two.move_speed_bonus = 10.0
	_check(units.register_equipment_config(horse_two), "注册第二匹坐骑")
	profile.add_item("mount_horse_02", 1)
	_check(units.equip_mount(second.unit_id, "mount_horse_02", profile), "替换坐骑成功")
	_check(second.equipment.get("MOUNT", "") == "mount_horse_02", "MOUNT 槽切换到新坐骑")
	_check(profile.get_item_count(MOUNT_ID) == 1, "旧坐骑返还库存")
	_check(profile.get_item_count("mount_horse_02") == 0, "新坐骑从库存消耗")
	_check(units.equip_mount(second.unit_id, MOUNT_ID, profile), "换回普通战马")
	_check(profile.get_item_count("mount_horse_02") == 1, "备用战马返还库存")

	# 直接使用数据层 equip_item 时也必须同步骑乘状态。
	var third := units.create_unit(militia, "FACTION_PLAYER")
	_check(units.equip_item(third.unit_id, MOUNT_ID), "数据层直接装备坐骑")
	_check(third.is_mounted, "equip_item 同步骑乘状态")
	_check(units.unequip_slot(third.unit_id, "MOUNT"), "数据层卸下坐骑")
	_check(not third.is_mounted, "unequip_slot 同步恢复步兵状态")

	# 骑乘属性由 StatCalculator 统一提供；移动加成使用最终移速。
	_check(
		StatCalculator.compute_move_attack_bonus(second, true) == 2,
		"骑乘移动攻击加成来自最终移速"
	)
	_check(StatCalculator.compute_move_attack_bonus(second, false) == 0, "停止移动加成归零")
	_check(StatCalculator.compute_move_attack_bonus(first, true) == 0, "步兵没有骑乘加成")


func _test_legacy_serialization() -> void:
	var legacy := {
		"unit_id": "UNIT_LEGACY",
		"config_id": "infantry_militia",
		"display_name": "旧存档步兵",
		"max_hp": 30,
		"current_hp": 24,
		"is_mounted": true,
		"equipment": {},
	}
	var unit := UnitData.from_dict(legacy)
	_check(not unit.is_mounted, "旧存档缺少 MOUNT 装备时按步兵处理")
	_check(unit.current_hp == 24, "旧存档 HP 保留")

	var mounted_payload := legacy.duplicate(true)
	mounted_payload["unit_id"] = "UNIT_LEGACY_MOUNTED"
	mounted_payload["equipment"] = {"MOUNT": MOUNT_ID}
	var mounted_unit := UnitData.from_dict(mounted_payload)
	_check(mounted_unit.is_mounted, "旧存档有 MOUNT 装备时恢复骑乘状态")

	var legacy_profile := PlayerProfile.from_dict({
		"gold": 10,
		"inventory": [MOUNT_ID],
	})
	_check(legacy_profile.get_item_count(MOUNT_ID) == 1, "旧物品栏每个条目按 1 件处理")

	legacy_profile.add_item(MOUNT_ID, 2)
	var profile_payload := legacy_profile.to_dict()
	var restored_profile := PlayerProfile.from_dict(profile_payload)
	_check(restored_profile.get_item_count(MOUNT_ID) == 3, "物品数量往返一致")
	_check(restored_profile.remove_item(MOUNT_ID, 3), "消耗全部数量")
	_check(not restored_profile.has_item(MOUNT_ID), "数量归零后从物品栏移除")


func _test_new_game_composition() -> void:
	var context := WorldContext.new()
	context.name = "MountedCompositionContext"
	add_child(context)
	_check(WorldInitializer.create_new_world(context), "初始化新世界")
	var player := context.get_player_party()
	_check(player != null, "玩家部队存在")
	if player == null:
		context.queue_free()
		return

	var hero_count: int = 0
	var foot_count: int = 0
	var mounted_count: int = 0
	var mounted_unit: UnitData = null
	for unit_id: String in player.member_unit_ids:
		var unit := context.unit_manager.get_unit(unit_id)
		if unit == null:
			continue
		if unit.is_player_character:
			hero_count += 1
		if unit.is_mounted:
			mounted_count += 1
			mounted_unit = unit
		else:
			foot_count += 1
	_check(player.member_unit_ids.size() == 7, "玩家部队包含 7 名成员")
	_check(hero_count == 1, "保留 1 名玩家角色")
	_check(foot_count >= 1, "存在普通步兵")
	_check(mounted_count == 3, "玩家部队包含 3 名骑乘测试士兵")
	_check(
		context.player_profile.get_item_count(MOUNT_ID) == 1,
		"新游戏马匹库存与已装备数量一致（4 - 3）"
	)
	_check(
		mounted_unit != null and mounted_unit.config_id == "infantry_trained",
		"骑乘单位沿用普通步兵兵种，不新增骑兵 ID"
	)
	if mounted_unit != null:
		_check(mounted_unit.equipment.get("MOUNT", "") == MOUNT_ID, "骑乘单位装备马匹")
		_check(is_equal_approx(mounted_unit.move_speed, 80.0), "职业步兵骑乘移速 55 + 25")

	context.queue_free()


func _test_world_save_round_trip() -> void:
	var context := WorldContext.new()
	context.name = "MountedSaveContext"
	add_child(context)
	_check(WorldInitializer.create_new_world(context), "初始化存档测试世界")
	var player := context.get_player_party()
	if player == null:
		context.queue_free()
		return

	var mounted_id: String = ""
	for unit_id: String in player.member_unit_ids:
		var unit := context.unit_manager.get_unit(unit_id)
		if unit != null and unit.is_mounted:
			mounted_id = unit_id
			break
	_check(not mounted_id.is_empty(), "找到骑乘测试单位")
	if mounted_id.is_empty():
		context.queue_free()
		return

	var save := context.to_save_data()
	var restored := WorldContext.new()
	restored.name = "MountedRestoredContext"
	add_child(restored)
	_check(restored.load_from_save_data(save), "骑乘世界存档可恢复")

	var restored_unit := restored.unit_manager.get_unit(mounted_id)
	_check(restored_unit != null and restored_unit.is_mounted, "读档后保持骑乘状态")
	if restored_unit != null:
		_check(restored_unit.equipment.get("MOUNT", "") == MOUNT_ID, "读档后保留 MOUNT 装备")
		_check(is_equal_approx(restored_unit.move_speed, 80.0), "读档后骑乘属性重算正确")
		_check(
			StatCalculator.compute_move_attack_bonus(restored_unit, true) == 2,
			"读档后移动攻击加成仍由统一属性入口提供"
		)
	_check(
		restored.player_profile.get_item_count(MOUNT_ID) == 1,
		"读档后马匹库存数量一致"
	)

	restored.queue_free()
	context.queue_free()
	await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[mounted] OK: %s" % message)
	else:
		_failed = true
		push_error("[mounted] FAIL: %s" % message)
