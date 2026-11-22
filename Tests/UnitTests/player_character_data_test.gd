extends Node
## 玩家角色数据测试：新游戏创建、玩家部队归属、is_player_character 持久化与玩家档案往返。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/player_character_data_test.tscn

const TEST_SLOT: String = "__player_character_test__"

var _failed: bool = false


func _ready() -> void:
	_run()
	SaveManager.delete_save(TEST_SLOT)
	if _failed:
		push_error("[playerdata] 测试失败")
		get_tree().quit(1)
	else:
		print("[playerdata] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	var context := WorldContext.new()
	context.name = "PlayerCharacterDataContext"
	add_child(context)
	_check(WorldInitializer.create_new_world(context), "初始化世界")

	var player := context.get_player_party()
	_check(player != null, "玩家部队存在")
	if player == null:
		return
	_check(
		player.member_unit_ids.size() == WorldInitializer.PLAYER_TOTAL_MEMBER_COUNT,
		"玩家部队包含全部初始成员"
	)

	var hero: UnitData = null
	for unit_id: String in player.member_unit_ids:
		var unit := context.unit_manager.get_unit(unit_id)
		if unit != null and unit.is_player_character:
			hero = unit
			break
	_check(hero != null, "玩家部队包含玩家角色 Unit")
	if hero == null:
		return
	_check(hero.config_id == "player_hero", "玩家角色使用 player_hero 配置")
	_check(hero.current_party_id == player.party_id, "玩家角色属于玩家部队")
	_check(hero.is_alive(), "玩家角色创建时存活")
	_check(hero.max_hp == 180 and hero.attack == 25, "玩家角色使用三级配置最终属性")
	_check(hero.level == 1 and hero.exp == 0, "玩家角色使用正常等级/经验")

	# 普通士兵不能带玩家角色身份。
	var npc_unit: UnitData = null
	for unit_id: String in player.member_unit_ids:
		var unit := context.unit_manager.get_unit(unit_id)
		if unit != null and not unit.is_player_character:
			npc_unit = unit
			break
	_check(npc_unit != null, "玩家部队中仍有普通士兵")
	if npc_unit != null:
		_check(not npc_unit.is_player_character, "普通士兵不是玩家角色")

	_check(
		context.battle_manager.player_profile == context.player_profile,
		"BattleManager 使用 WorldContext 的玩家档案"
	)
	context.player_profile.gold = 123
	context.player_profile.add_item("weapon_sword_01")
	var save := context.to_save_data()
	_check(save.player.get("gold", 0) == 123, "存档包含玩家金币")
	_check(save.player.get("inventory", []).has("weapon_sword_01"), "存档包含玩家物品")

	var restored := WorldContext.new()
	restored.name = "PlayerCharacterRestoredContext"
	add_child(restored)
	_check(restored.load_from_save_data(save), "读档恢复世界")
	var restored_player := restored.get_player_party()
	_check(restored_player != null, "读档恢复玩家部队")
	if restored_player != null:
		var restored_hero: UnitData = null
		for unit_id: String in restored_player.member_unit_ids:
			var unit := restored.unit_manager.get_unit(unit_id)
			if unit != null and unit.is_player_character:
				restored_hero = unit
				break
		_check(restored_hero != null, "读档保留玩家角色身份")
		if restored_hero != null:
			_check(restored_hero.unit_id == hero.unit_id, "玩家角色 ID 往返一致")
			_check(restored_hero.config_id == "player_hero", "玩家角色配置往返一致")
	_check(restored.player_profile.gold == 123, "读档恢复玩家金币")
	_check(
		restored.player_profile.inventory.has("weapon_sword_01"),
		"读档恢复玩家物品"
	)
	_check(
		restored.battle_manager.player_profile == restored.player_profile,
		"读档后 BattleManager 仍使用同一玩家档案对象"
	)

	context.queue_free()
	restored.queue_free()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[playerdata] OK: %s" % message)
	else:
		_failed = true
		push_error("[playerdata] FAIL: %s" % message)
