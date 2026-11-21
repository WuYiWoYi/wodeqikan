extends Node
## 阶段 6 数据层测试：三级兵种、工资、晋升、金币与背包数量。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/unit_tier_wage_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"
const TRAINED_PATH: String = "res://Data/Units/infantry_trained.tres"
const VETERAN_PATH: String = "res://Data/Units/infantry_veteran.tres"
const MOUNT_ID: String = "mount_horse_01"
const TOKEN_ID: String = "promotion_rank_token"

var _failed: bool = false


func _ready() -> void:
	_run()
	if _failed:
		push_error("[tier] 测试失败")
		get_tree().quit(1)
	else:
		print("[tier] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	var militia: UnitConfig = load(MILITIA_PATH) as UnitConfig
	var trained: UnitConfig = load(TRAINED_PATH) as UnitConfig
	var veteran: UnitConfig = load(VETERAN_PATH) as UnitConfig
	_check(militia != null and trained != null and veteran != null, "加载三级兵种配置")
	if militia == null or trained == null or veteran == null:
		return

	_test_configs(militia, trained, veteran)

	var context := WorldContext.new()
	context.name = "TierWageContext"
	add_child(context)
	_check(WorldInitializer.create_new_world(context), "创建测试世界")
	if not context.is_valid_world():
		context.queue_free()
		return

	_test_new_game_economy(context)
	_test_mount_does_not_change_tier(context)
	_test_promotion(context)
	_test_old_save_wage_migration(context)
	_test_gold_api()
	_test_save_round_trip(context)

	context.queue_free()


func _test_configs(
	militia: UnitConfig, trained: UnitConfig, veteran: UnitConfig
) -> void:
	_check(militia.tier == 1 and militia.base_attack == 10 and militia.base_max_hp == 50,
		"一级兵种基础属性 10 / 50")
	_check(trained.tier == 2 and trained.base_attack == 20 and trained.base_max_hp == 100,
		"二级兵种基础属性 20 / 100")
	_check(veteran.tier == 3 and veteran.base_attack == 25 and veteran.base_max_hp == 180,
		"三级兵种基础属性 25 / 180")
	_check(militia.daily_wage == 2 and trained.daily_wage == 5 and veteran.daily_wage == 10,
		"三个等级工资独立配置")
	_check(
		militia.promotion_target_config_id == "infantry_trained"
			and trained.promotion_target_config_id == "infantry_veteran"
			and veteran.is_max_tier(),
		"晋升链路 一级 → 二级 → 三级"
	)
	_check(militia.validate() and trained.validate() and veteran.validate(), "三级兵种配置通过校验")


func _test_new_game_economy(context: WorldContext) -> void:
	var player := context.get_player_party()
	_check(
		player != null
			and player.member_unit_ids.size() == WorldInitializer.PLAYER_TOTAL_MEMBER_COUNT,
		"玩家部队为完整初始编制"
	)
	_check(context.player_profile.get_item_count(TOKEN_ID) == 2, "新游戏测试晋升凭证 2 个")
	_check(context.player_profile.get_item_count(MOUNT_ID) == 1, "新游戏背包剩余 1 匹马")
	_check(
		context.party_manager.get_total_wage(player.party_id)
			== WorldInitializer.PLAYER_MILITIA_COUNT * 2
				+ WorldInitializer.PLAYER_TRAINED_COUNT * 5,
		"玩家部队每日工资按民兵/职业步兵数量计算"
	)

	var militia_unit: UnitData = null
	var trained_unit: UnitData = null
	var hero_unit: UnitData = null
	for unit_id: String in player.member_unit_ids:
		var unit := context.unit_manager.get_unit(unit_id)
		if unit == null:
			continue
		if unit.config_id == "infantry_militia" and militia_unit == null:
			militia_unit = unit
		elif unit.config_id == "infantry_trained" and trained_unit == null:
			trained_unit = unit
		if unit.is_player_character:
			hero_unit = unit
	_check(militia_unit != null and trained_unit != null and hero_unit != null,
		"玩家部队包含三类成员")
	if militia_unit != null:
		_check(militia_unit.wage == 2, "民兵工资来自配置")
		_check(militia_unit.max_hp == 50 and militia_unit.attack == 10,
			"民兵使用一级基础属性")
	if trained_unit != null:
		_check(trained_unit.wage == 5, "职业步兵工资来自配置")
		_check(trained_unit.max_hp == 100 and trained_unit.attack == 20,
			"职业步兵使用二级基础属性")
	if hero_unit != null:
		_check(hero_unit.wage == 0, "玩家角色不领取工资")


func _test_mount_does_not_change_tier(context: WorldContext) -> void:
	var player := context.get_player_party()
	var militia_unit := _find_unit(context, player, "infantry_militia", false)
	_check(militia_unit != null, "找到未骑乘民兵")
	if militia_unit == null:
		return
	var tier_before: int = context.unit_manager.get_unit_config(
		militia_unit.config_id
	).tier
	var hp_before: int = militia_unit.max_hp
	var attack_before: int = militia_unit.attack
	var wage_before: int = militia_unit.wage

	_check(
		context.unit_manager.equip_mount(
			militia_unit.unit_id, MOUNT_ID, context.player_profile
		),
		"从背包给民兵装备马匹"
	)
	_check(militia_unit.is_mounted, "装备 MOUNT 后进入骑乘状态")
	_check(
		context.unit_manager.get_unit_config(militia_unit.config_id).tier == tier_before,
		"骑马不改变兵种等级"
	)
	_check(militia_unit.max_hp == hp_before and militia_unit.attack == attack_before,
		"骑马不改变基础生命与攻击"
	)
	_check(militia_unit.wage == wage_before, "骑马不改变工资")
	_check(is_equal_approx(militia_unit.move_speed, 85.0), "保留马匹移速加成 60 + 25")

	_check(
		context.unit_manager.unequip_mount(militia_unit.unit_id, context.player_profile),
		"卸下马匹成功"
	)
	_check(not militia_unit.is_mounted, "卸下后恢复步兵状态")
	_check(context.player_profile.get_item_count(MOUNT_ID) == 1, "卸下后马匹返回背包")
	_check(militia_unit.wage == wage_before, "下马不改变工资")


func _test_promotion(context: WorldContext) -> void:
	var player := context.get_player_party()
	var unit := _find_unit(context, player, "infantry_militia", false)
	_check(unit != null, "找到用于晋升的民兵")
	if unit == null:
		return

	unit.level = 3
	unit.exp = 42
	_check(context.unit_manager.recalculate_stats(unit.unit_id), "设置 3 级属性")
	_check(unit.max_hp == 60 and unit.attack == 12, "3 级民兵属性 60 / 12")
	var level_before: int = unit.level
	var exp_before: int = unit.exp
	var equipment_before: Dictionary = unit.equipment.duplicate(true)
	var unit_count_before: int = context.unit_manager.get_all_units().size()
	var tokens_before: int = context.player_profile.get_item_count(TOKEN_ID)

	_check(
		context.unit_manager.promote_tier(unit.unit_id, context.player_profile),
		"消耗晋升凭证提升到二级"
	)
	_check(unit.config_id == "infantry_trained", "晋升后切换到二级兵种配置")
	_check(unit.level == level_before and unit.exp == exp_before, "晋升保留等级与经验")
	_check(unit.equipment == equipment_before, "晋升保留装备")
	_check(unit.wage == 5, "晋升后工资切换为二级工资")
	_check(unit.max_hp == 116 and unit.attack == 24, "二级 3 级属性按新成长曲线重算")
	_check(
		context.player_profile.get_item_count(TOKEN_ID) == tokens_before - 1,
		"晋升消耗 1 个凭证"
	)
	_check(
		unit.max_hp >= unit.current_hp,
		"晋升提高生命上限后当前生命不超过上限"
	)

	var tokens_left: int = context.player_profile.get_item_count(TOKEN_ID)
	_check(
		context.unit_manager.promote_tier(unit.unit_id, context.player_profile),
		"继续晋升到三级"
	)
	_check(unit.config_id == "infantry_veteran", "晋升后切换到三级兵种配置")
	_check(unit.wage == 10, "晋升后工资切换为三级工资")
	_check(unit.max_hp == 200 and unit.attack == 31, "三级 3 级属性 200 / 31")
	_check(
		context.player_profile.get_item_count(TOKEN_ID) == tokens_left - 1,
		"第二次晋升再消耗 1 个凭证"
	)
	_check(
		not context.unit_manager.promote_tier(unit.unit_id, context.player_profile),
		"三级已最高等级，不能继续晋升"
	)
	_check(unit.config_id == "infantry_veteran", "最高等级晋升失败不修改兵种")
	_check(context.player_profile.get_item_count(TOKEN_ID) == 0, "失败不消耗物品")
	_check(context.unit_manager.get_all_units().size() == unit_count_before,
		"晋升不创建或删除单位")

	# 物品不足时不产生部分修改。
	var other := _find_unit(context, player, "infantry_militia", false)
	_check(other != null, "找到第二名民兵")
	if other != null:
		var other_config_before: String = other.config_id
		var other_attack_before: int = other.attack
		_check(
			not context.unit_manager.promote_tier(
				other.unit_id, context.player_profile
			),
			"凭证不足时晋升失败"
		)
		_check(other.config_id == other_config_before, "失败不切换兵种")
		_check(other.attack == other_attack_before, "失败不修改属性")


func _test_old_save_wage_migration(context: WorldContext) -> void:
	var legacy := UnitData.from_dict({
		"unit_id": "UNIT_LEGACY_WAGE",
		"config_id": "infantry_militia",
		"display_name": "旧存档民兵",
		"level": 1,
		"exp": 0,
	})
	_check(legacy.wage == -1, "旧存档缺少工资字段时使用哨兵值")
	_check(not context.unit_manager.add_unit(legacy).is_empty(), "旧单位注册成功")
	_check(context.unit_manager.recalculate_stats(legacy.unit_id), "旧单位属性重算成功")
	_check(legacy.wage == 2, "旧存档工资按当前兵种配置补全")
	_check(context.unit_manager.remove_unit(legacy.unit_id), "清理旧单位")


func _test_gold_api() -> void:
	var profile := PlayerProfile.new()
	profile.add_gold(100)
	_check(profile.gold == 100, "增加金币")
	_check(profile.can_afford(60), "余额足够")
	_check(profile.spend_gold(60), "扣除金币成功")
	_check(profile.gold == 40, "扣除后余额正确")
	_check(not profile.spend_gold(41), "余额不足时扣除失败")
	_check(profile.gold == 40, "扣除失败不改变余额")
	_check(not profile.spend_gold(-5), "负数额扣除被拒绝")
	profile.add_gold(-10)
	_check(profile.gold == 40, "add_gold 不接受负数")


func _test_save_round_trip(context: WorldContext) -> void:
	var player := context.get_player_party()
	var unit := _find_unit(context, player, "infantry_veteran", false)
	if unit == null:
		unit = _find_unit(context, player, "infantry_trained", false)
	_check(unit != null, "找到已晋升单位用于存档")
	if unit == null:
		return
	var unit_id: String = unit.unit_id
	var config_id: String = unit.config_id
	var wage: int = unit.wage
	var level: int = unit.level
	var exp: int = unit.exp

	var save := context.to_save_data()
	var restored := WorldContext.new()
	restored.name = "TierWageRestoredContext"
	add_child(restored)
	_check(restored.load_from_save_data(save), "存档可恢复")
	var restored_unit := restored.unit_manager.get_unit(unit_id)
	_check(restored_unit != null, "读档后单位存在")
	if restored_unit != null:
		_check(restored_unit.config_id == config_id, "读档保留兵种等级配置")
		_check(restored_unit.wage == wage, "读档保留工资")
		_check(restored_unit.level == level and restored_unit.exp == exp,
			"读档保留等级与经验")
		var config := restored.unit_manager.get_unit_config(restored_unit.config_id)
		_check(config != null and config.tier == 3, "读档后兵种等级仍为三级")
	_check(
		restored.player_profile.get_item_count(TOKEN_ID) ==
			context.player_profile.get_item_count(TOKEN_ID),
		"读档后晋升凭证数量一致"
	)
	_check(
		restored.player_profile.get_item_count(MOUNT_ID) ==
			context.player_profile.get_item_count(MOUNT_ID),
		"读档后马匹数量一致"
	)
	restored.queue_free()


func _find_unit(
	context: WorldContext, party: PartyData, config_id: String, mounted: bool
) -> UnitData:
	for unit_id: String in party.member_unit_ids:
		var unit := context.unit_manager.get_unit(unit_id)
		if unit == null:
			continue
		if unit.config_id == config_id and unit.is_mounted == mounted:
			return unit
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[tier] OK: %s" % message)
	else:
		_failed = true
		push_error("[tier] FAIL: %s" % message)
