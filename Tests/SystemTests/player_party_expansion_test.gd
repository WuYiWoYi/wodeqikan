extends Node
## 玩家初始部队扩编测试。
## 覆盖：15 人编制（含 3 名弓箭手）、完整 UnitData、骑乘/马匹库存、成员归属、
## 存档往返不丢失或重复生成成员。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/player_party_expansion_test.tscn

var _failed: bool = false


func _ready() -> void:
	_run()
	if _failed:
		push_error("[playerexp] 测试失败")
		get_tree().quit(1)
	else:
		print("[playerexp] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	var context := WorldContext.new()
	context.name = "PlayerExpansionContext"
	add_child(context)
	_check(WorldInitializer.create_new_world(context), "初始化世界")
	if not context.is_valid_world():
		return

	var player := context.get_player_party()
	_check(player != null, "玩家部队存在")
	if player == null:
		return

	_check(
		player.member_unit_ids.size() == WorldInitializer.PLAYER_TOTAL_MEMBER_COUNT,
		"玩家部队人数为 15"
	)
	_check(
		WorldInitializer.PLAYER_TOTAL_MEMBER_COUNT
			== WorldInitializer.PLAYER_MILITIA_COUNT
				+ WorldInitializer.PLAYER_TRAINED_COUNT
				+ WorldInitializer.PLAYER_ARCHER_COUNT + 1,
		"编制常量与人数一致"
	)

	var hero_count: int = 0
	var militia_count: int = 0
	var trained_count: int = 0
	var archer_count: int = 0
	var mounted_count: int = 0
	var all_have_data: bool = true
	var all_belong_to_party: bool = true
	var seen_ids: Dictionary = {}
	for unit_id: String in player.member_unit_ids:
		var unit := context.unit_manager.get_unit(unit_id)
		if unit == null or unit.config_id.is_empty() or unit.max_hp <= 0:
			all_have_data = false
			continue
		if seen_ids.has(unit.unit_id):
			all_have_data = false
		seen_ids[unit.unit_id] = true
		if unit.current_party_id != player.party_id:
			all_belong_to_party = false
		match unit.config_id:
			"player_hero":
				hero_count += 1
			"infantry_militia":
				militia_count += 1
			"infantry_trained":
				trained_count += 1
			_:
				if unit.config_id.begins_with("archer_"):
					archer_count += 1
		if unit.is_mounted:
			mounted_count += 1

	_check(all_have_data, "所有新增成员都有完整 UnitData")
	_check(all_belong_to_party, "所有成员归属玩家部队")
	_check(hero_count == 1, "保留 1 名玩家角色")
	_check(
		militia_count == WorldInitializer.PLAYER_MILITIA_COUNT,
		"民兵数量符合配置"
	)
	_check(
		trained_count == WorldInitializer.PLAYER_TRAINED_COUNT,
		"职业步兵数量符合配置"
	)
	_check(
		archer_count == WorldInitializer.PLAYER_ARCHER_COUNT,
		"弓箭手数量符合配置"
	)
	_check(
		mounted_count == WorldInitializer.PLAYER_MOUNTED_TRAINED_COUNT,
		"骑乘士兵数量符合配置"
	)
	_check(
		not player.leader_unit_id.is_empty()
			and seen_ids.has(player.leader_unit_id),
		"玩家角色仍是部队领袖"
	)
	_check(
		context.player_profile.get_item_count(WorldInitializer.TEST_MOUNT_ID)
			== WorldInitializer.TEST_MOUNT_STOCK
				- WorldInitializer.PLAYER_MOUNTED_TRAINED_COUNT,
		"马匹库存正确扣除骑乘装备"
	)

	# 存档往返：成员数量与 ID 不变，不重复生成。
	var save := context.to_save_data()
	var restored := WorldContext.new()
	restored.name = "PlayerExpansionRestoredContext"
	add_child(restored)
	_check(restored.load_from_save_data(save), "存档可恢复")
	if restored.is_valid_world():
		var restored_player := restored.get_player_party()
		_check(restored_player != null, "读档后玩家部队存在")
		if restored_player != null:
			_check(
				restored_player.member_unit_ids.size()
					== WorldInitializer.PLAYER_TOTAL_MEMBER_COUNT,
				"读档后成员数量不变"
			)
			var same_ids: bool = true
			for unit_id: String in player.member_unit_ids:
				if not restored_player.member_unit_ids.has(unit_id):
					same_ids = false
			_check(same_ids, "读档后成员 ID 一致")
			_check(
				restored.unit_manager.get_all_units().size()
					== context.unit_manager.get_all_units().size(),
				"读档不会重复生成单位"
			)
	restored.queue_free()
	context.queue_free()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[playerexp] OK: %s" % message)
	else:
		_failed = true
		push_error("[playerexp] FAIL: %s" % message)
