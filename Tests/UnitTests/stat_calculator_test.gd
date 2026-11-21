extends Node
## StatCalculator 单元测试：基础属性、等级成长、装备加成与 HP 安全规则。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/stat_calculator_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"
const TRAINED_PATH: String = "res://Data/Units/infantry_trained.tres"

var _failed: bool = false


func _ready() -> void:
	_run()
	if _failed:
		push_error("[stat] 测试失败")
		get_tree().quit(1)
	else:
		print("[stat] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	var militia: UnitConfig = load(MILITIA_PATH) as UnitConfig
	var trained: UnitConfig = load(TRAINED_PATH) as UnitConfig
	_check(militia != null, "加载民兵配置")
	_check(trained != null, "加载职业步兵配置")
	if militia == null or trained == null:
		return

	_check(militia.validate(), "民兵配置通过校验")
	_check(trained.validate(), "职业步兵配置通过校验")
	_check(militia.config_id == "infantry_militia", "民兵 config_id 正确")
	_check(trained.config_id == "infantry_trained", "职业步兵 config_id 正确")

	# 1 级单位属性等于兵种基础属性。
	var unit := UnitData.new()
	var militia_stats := StatCalculator.compute_final_stats(unit, militia)
	_check(militia_stats.size() == StatCalculator.STAT_KEYS.size(), "返回全部基础属性")
	_check(int(militia_stats["max_hp"]) == 50, "民兵 max_hp = 50")
	_check(int(militia_stats["attack"]) == 10, "民兵 attack = 10")
	_check(is_equal_approx(float(militia_stats["attack_interval"]), 1.2), "民兵 attack_interval = 1.2")
	_check(is_equal_approx(float(militia_stats["move_speed"]), 60.0), "民兵 move_speed = 60")
	_check(is_equal_approx(float(militia_stats["attack_range"]), 20.0), "民兵 attack_range = 20")

	var trained_stats := StatCalculator.compute_final_stats(unit, trained)
	_check(int(trained_stats["max_hp"]) == 100, "职业步兵 max_hp = 100")
	_check(int(trained_stats["attack"]) == 20, "职业步兵 attack = 20")
	_check(is_equal_approx(float(trained_stats["attack_interval"]), 1.0), "职业步兵 attack_interval = 1.0")
	_check(is_equal_approx(float(trained_stats["move_speed"]), 55.0), "职业步兵 move_speed = 55")

	# 等级成长：民兵每级 +5 HP / +1 攻击。
	var level_unit := UnitData.new()
	level_unit.level = 3
	var level_stats := StatCalculator.compute_final_stats(level_unit, militia)
	_check(int(level_stats["max_hp"]) == 60, "3 级民兵 max_hp = 60")
	_check(int(level_stats["attack"]) == 12, "3 级民兵 attack = 12")
	_check(is_equal_approx(float(level_stats["attack_interval"]), 1.2), "等级不改变攻击间隔")

	var trained_level_unit := UnitData.new()
	trained_level_unit.level = 3
	var trained_level_stats := StatCalculator.compute_final_stats(trained_level_unit, trained)
	_check(int(trained_level_stats["max_hp"]) == 116, "3 级职业步兵 max_hp = 116")
	_check(int(trained_level_stats["attack"]) == 24, "3 级职业步兵 attack = 24")

	# 超过等级上限时成长被钳制在 max_level。
	var capped_unit := UnitData.new()
	capped_unit.level = 99
	var capped_stats := StatCalculator.compute_final_stats(capped_unit, militia)
	_check(int(capped_stats["max_hp"]) == 95, "超过上限按 10 级计算 max_hp")
	_check(int(capped_stats["attack"]) == 19, "超过上限按 10 级计算 attack")

	# 装备加成。
	var sword := _make_equipment("sword", "铁剑", EquipmentConfig.Slot.WEAPON)
	sword.attack_bonus = 3
	var shield := _make_equipment("shield", "木盾", EquipmentConfig.Slot.OFFHAND)
	shield.max_hp_bonus = 5
	var horse := _make_equipment("horse", "战马", EquipmentConfig.Slot.MOUNT)
	horse.move_speed_bonus = 5.0
	horse.attack_range_bonus = 2.0
	var equipment_configs: Dictionary = {
		"sword": sword,
		"shield": shield,
		"horse": horse,
	}

	var gear_unit := UnitData.new()
	gear_unit.equipment = {"WEAPON": "sword", "OFFHAND": "shield"}
	var gear_stats := StatCalculator.compute_final_stats(gear_unit, militia, equipment_configs)
	_check(int(gear_stats["max_hp"]) == 55, "木盾提供 +5 最大生命")
	_check(int(gear_stats["attack"]) == 13, "铁剑提供 +3 攻击")

	# 等级与多件装备叠加。
	gear_unit.level = 2
	gear_unit.equipment = {"WEAPON": "sword", "OFFHAND": "shield", "MOUNT": "horse"}
	var stacked_stats := StatCalculator.compute_final_stats(
		gear_unit, militia, equipment_configs
	)
	_check(int(stacked_stats["max_hp"]) == 60, "等级与多件装备生命叠加")
	_check(int(stacked_stats["attack"]) == 14, "等级与多件装备攻击叠加")
	_check(is_equal_approx(float(stacked_stats["move_speed"]), 65.0), "坐骑提供移速加成")
	_check(is_equal_approx(float(stacked_stats["attack_range"]), 22.0), "坐骑提供射程加成")

	# 武器攻击距离：WEAPON 的 weapon_attack_range > 0 时覆盖单位基础射程。
	var long_weapon := _make_equipment("long_weapon", "长柄武器", EquipmentConfig.Slot.WEAPON)
	long_weapon.weapon_attack_range = 30.0
	var short_weapon := _make_equipment("short_weapon", "短武器", EquipmentConfig.Slot.WEAPON)
	short_weapon.weapon_attack_range = 14.0
	equipment_configs["long_weapon"] = long_weapon
	equipment_configs["short_weapon"] = short_weapon
	var weapon_unit := UnitData.new()
	weapon_unit.equipment = {"WEAPON": "long_weapon"}
	var long_weapon_stats := StatCalculator.compute_final_stats(
		weapon_unit, militia, equipment_configs
	)
	_check(is_equal_approx(float(long_weapon_stats["attack_range"]), 30.0),
		"武器攻击距离覆盖单位基础射程")
	weapon_unit.equipment = {"WEAPON": "short_weapon"}
	var short_weapon_stats := StatCalculator.compute_final_stats(
		weapon_unit, militia, equipment_configs
	)
	_check(is_equal_approx(float(short_weapon_stats["attack_range"]), 14.0),
		"更换武器后攻击距离自然切换")
	weapon_unit.equipment = {"WEAPON": "long_weapon", "MOUNT": "horse"}
	var weapon_mount_stats := StatCalculator.compute_final_stats(
		weapon_unit, militia, equipment_configs
	)
	_check(is_equal_approx(float(weapon_mount_stats["attack_range"]), 32.0),
		"武器基础距离与装备射程加成叠加")

	# 骑乘移动攻击加成：使用最终移速、仅骑乘移动时生效并设上限。
	var mounted := UnitData.new()
	mounted.attack = 8
	mounted.move_speed = 85.0
	mounted.is_mounted = true
	mounted.equipment = {"MOUNT": "horse"}
	_check(StatCalculator.compute_move_attack_bonus(mounted, true) == 2,
		"骑乘移动攻击加成 = 超出基础移速部分折算")
	_check(StatCalculator.compute_move_attack_bonus(mounted, false) == 0,
		"停止移动不提供攻击加成")
	_check(StatCalculator.compute_effective_attack(mounted, true) == 10,
		"有效攻击 = 基础攻击 + 移动加成")
	mounted.move_speed = 999.0
	_check(
		StatCalculator.compute_move_attack_bonus(mounted, true)
			== StatCalculator.MOUNT_CHARGE_MAX_BONUS,
		"移动攻击加成有上限"
	)
	mounted.is_mounted = false
	_check(StatCalculator.compute_move_attack_bonus(mounted, true) == 0,
		"步兵移动不提供骑乘加成")

	# 空装备与无效装备不产生额外属性。
	var bare_unit := UnitData.new()
	bare_unit.equipment = {}
	var bare_stats := StatCalculator.compute_final_stats(bare_unit, militia, equipment_configs)
	_check(int(bare_stats["max_hp"]) == 50 and int(bare_stats["attack"]) == 10, "空装备等于基础属性")

	bare_unit.equipment = {"WEAPON": "missing_weapon"}
	var invalid_stats := StatCalculator.compute_final_stats(
		bare_unit, militia, equipment_configs
	)
	_check(int(invalid_stats["attack"]) == 10, "无效装备 ID 被忽略")

	bare_unit.equipment = {"HEAD": "sword"}
	var mismatched_stats := StatCalculator.compute_final_stats(
		bare_unit, militia, equipment_configs
	)
	_check(int(mismatched_stats["attack"]) == 10, "槽位不匹配的装备被忽略")

	# HP 安全规则。
	var hp_unit := UnitData.new()
	hp_unit.current_hp = 20
	hp_unit.level = 2
	_check(StatCalculator.apply_to_unit(hp_unit, militia), "写入 2 级属性")
	_check(hp_unit.max_hp == 55, "升级后最大 HP 提高")
	_check(hp_unit.current_hp == 20, "最大 HP 提高不自动恢复当前 HP")

	hp_unit.level = 1
	_check(StatCalculator.apply_to_unit(hp_unit, militia), "回退到 1 级属性")
	_check(hp_unit.max_hp == 50 and hp_unit.current_hp == 20, "最大 HP 降低但仍高于当前 HP")

	hp_unit.current_hp = 58
	_check(StatCalculator.apply_to_unit(hp_unit, militia), "再次写入 1 级属性")
	_check(hp_unit.current_hp == 50, "当前 HP 被钳制到新上限")

	_check(StatCalculator.apply_to_unit(unit, militia), "写入民兵属性")
	_check(unit.max_hp == 50 and unit.attack == 10, "UnitData 获得民兵属性")
	_check(unit.current_hp == 1, "写入属性不重置 current_hp")

	unit.current_hp = 999
	_check(StatCalculator.apply_to_unit(unit, militia), "再次写入民兵属性")
	_check(unit.current_hp == 50, "超过上限的 current_hp 被 clamp")

	_check(StatCalculator.apply_to_unit(unit, trained), "写入职业步兵属性")
	_check(unit.max_hp == 100 and unit.attack == 20, "UnitData 获得职业步兵属性")
	_check(unit.current_hp == 50, "重算属性不重置 current_hp")

	unit.current_hp = 999
	_check(StatCalculator.apply_to_unit(unit, trained), "再次写入职业步兵属性")
	_check(unit.current_hp == 100, "新上限下再次 clamp")

	_check(StatCalculator.compute_final_stats(null, null).is_empty(), "空输入返回空字典")
	_check(StatCalculator.compute_final_stats(unit, null).is_empty(), "缺少配置返回空字典")
	_check(not StatCalculator.apply_to_unit(null, militia), "空单位写入失败")
	_check(not StatCalculator.apply_to_unit(unit, null), "空配置写入失败")


func _make_equipment(
	equipment_id: String, display_name: String, slot: EquipmentConfig.Slot
) -> EquipmentConfig:
	var equipment := EquipmentConfig.new()
	equipment.equipment_id = equipment_id
	equipment.display_name = display_name
	equipment.slot = slot
	return equipment


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[stat] OK: %s" % message)
	else:
		_failed = true
		push_error("[stat] FAIL: %s" % message)
