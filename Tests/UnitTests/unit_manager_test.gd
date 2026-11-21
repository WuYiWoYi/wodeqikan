extends Node
## UnitManager 单元测试：配置注册、创建、经验升级、装备与属性重算。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/unit_manager_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"
const TRAINED_PATH: String = "res://Data/Units/infantry_trained.tres"
const SWORD_PATH: String = "res://Data/Equipment/weapon_sword_01.tres"
const SHIELD_PATH: String = "res://Data/Equipment/shield_wood_01.tres"
const ARMOR_PATH: String = "res://Data/Equipment/armor_leather_01.tres"
const FACTION_ID: String = "FACTION_PLAYER"

var _failed: bool = false


func _ready() -> void:
	_run()
	if _failed:
		push_error("[unit] 测试失败")
		get_tree().quit(1)
	else:
		print("[unit] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	var militia: UnitConfig = load(MILITIA_PATH) as UnitConfig
	var trained: UnitConfig = load(TRAINED_PATH) as UnitConfig
	var sword: EquipmentConfig = load(SWORD_PATH) as EquipmentConfig
	var shield: EquipmentConfig = load(SHIELD_PATH) as EquipmentConfig
	var armor: EquipmentConfig = load(ARMOR_PATH) as EquipmentConfig
	_check(militia != null and trained != null, "加载两种兵种配置")
	_check(sword != null and shield != null and armor != null, "加载装备配置")
	if militia == null or trained == null or sword == null \
			or shield == null or armor == null:
		return

	var ids := IdGenerator.new()
	var units := UnitManager.new()
	units.setup(ids)

	_check(units.register_unit_config(militia), "注册民兵配置")
	_check(units.register_unit_config(trained), "注册职业步兵配置")
	_check(not units.register_unit_config(militia), "重复兵种配置拒绝覆盖")
	_check(units.get_unit_config("infantry_militia") == militia, "按 config_id 查询兵种配置")
	_check(units.get_unit_config("missing") == null, "未知兵种配置返回 null")

	_check(units.register_equipment_config(sword), "注册铁剑")
	_check(units.register_equipment_config(shield), "注册木盾")
	_check(units.register_equipment_config(armor), "注册皮甲")
	_check(not units.register_equipment_config(sword), "重复装备配置拒绝覆盖")
	_check(units.get_equipment_config("weapon_sword_01") == sword, "按 ID 查询装备配置")
	_check(units.get_equipment_config("missing") == null, "未知装备返回 null")

	var unit_a := units.create_unit(militia, FACTION_ID)
	var unit_b := units.create_unit(militia, FACTION_ID)
	_check(unit_a != null, "创建第一个民兵")
	_check(unit_b != null, "创建第二个民兵")
	if unit_a == null or unit_b == null:
		return

	_check(unit_a.unit_id.begins_with("UNIT_"), "单位 ID 使用 UNIT_ 前缀")
	_check(unit_a.unit_id != unit_b.unit_id, "两次创建得到不同 ID")
	_check(unit_a.get_instance_id() != unit_b.get_instance_id(), "两次创建是独立实例")
	_check(units.get_all_units().size() == 2, "仓储包含 2 个单位")
	_check(units.get_unit(unit_a.unit_id) == unit_a, "按 ID 查询到正确单位")
	_check(units.has_unit(unit_a.unit_id), "has_unit 正确")
	_check(not units.has_unit("UNIT_999999"), "不存在的 ID 查询失败")

	_check(unit_a.config_id == "infantry_militia", "config_id 来自配置")
	_check(unit_a.display_name == "民兵 01", "独立名称带编号 1")
	_check(unit_b.display_name == "民兵 02", "独立名称带编号 2")
	_check(unit_a.level == 1, "等级来自配置")
	_check(unit_a.exp == 0, "初始经验为 0")
	_check(unit_a.current_hp == unit_a.max_hp, "出生满血")
	_check(unit_a.max_hp == 50 and unit_a.attack == 10, "民兵基础属性正确")
	_check(unit_a.current_party_id.is_empty(), "出生时没有归属部队")
	_check(unit_a.faction_id == FACTION_ID, "阵营正确")

	var unit_trained := units.create_unit(trained, FACTION_ID)
	_check(unit_trained != null, "创建职业步兵")
	if unit_trained != null:
		_check(unit_trained.max_hp == 100 and unit_trained.attack == 20, "职业步兵属性不同")
		_check(is_equal_approx(unit_trained.move_speed, 55.0), "职业步兵移动速度正确")
		_check(unit_trained.display_name == "职业步兵 01", "不同兵种独立编号")

	# 默认装备：合法装备复制，槽位不匹配的条目被拒绝。
	var recruit_config := UnitConfig.new()
	recruit_config.config_id = "test_recruit"
	recruit_config.display_name = "测试兵"
	recruit_config.base_max_hp = 20
	recruit_config.base_attack = 3
	recruit_config.default_equipment = {
		"WEAPON": "weapon_sword_01",
		"HEAD": "weapon_sword_01",
	}
	var recruit := units.create_unit(recruit_config, FACTION_ID)
	_check(recruit != null, "创建带默认装备的兵种")
	if recruit != null:
		_check(recruit.equipment.size() == 1, "非法默认装备被丢弃")
		_check(recruit.equipment.get("WEAPON", "") == "weapon_sword_01", "合法默认装备保留")
		_check(recruit.attack == 5, "默认装备参与初始属性")

	var invalid_config := UnitConfig.new()
	_check(units.create_unit(invalid_config, FACTION_ID) == null, "无效配置不能创建单位")
	_check(units.create_unit(null, FACTION_ID) == null, "空配置不能创建单位")
	_check(UnitManager.new().create_unit(militia, FACTION_ID) == null, "未装配 IdGenerator 不能创建单位")

	var duplicate_unit := UnitData.new()
	duplicate_unit.unit_id = unit_a.unit_id
	duplicate_unit.display_name = "冒名单位"
	duplicate_unit.max_hp = 999
	var duplicate_result := units.add_unit(duplicate_unit)
	_check(duplicate_result.is_empty(), "重复 ID 注册失败")
	_check(units.get_unit(unit_a.unit_id) == unit_a, "重复 ID 不覆盖原单位")
	_check(units.get_unit(unit_a.unit_id).display_name == "民兵 01", "原单位数据保持不变")
	_check(units.get_all_units().size() == 4, "重复注册未增加单位数量")

	var anonymous := UnitData.new()
	anonymous.display_name = "匿名单位"
	var anonymous_id := units.add_unit(anonymous)
	_check(not anonymous_id.is_empty(), "无 ID 单位自动分配 ID")
	_check(units.get_unit(anonymous_id) == anonymous, "自动分配后可按 ID 查询")
	_check(units.get_all_units().size() == 5, "匿名单位已注册")

	_test_experience(units, unit_b, militia)
	_test_equipment(units, unit_a, sword, shield, armor)

	var party_manager := PartyManager.new()
	party_manager.setup(units, ids)
	var party := party_manager.create_party(FACTION_ID, Vector2(10.0, 20.0), "测试部队")
	_check(party != null, "创建测试部队")
	if party == null:
		return
	_check(party_manager.add_member(party.party_id, unit_a.unit_id), "单位加入部队")
	_check(not units.remove_unit(unit_a.unit_id), "已归属部队的单位不能直接删除")
	_check(units.has_unit(unit_a.unit_id), "删除失败后单位仍然存在")
	_check(party_manager.remove_member(party.party_id, unit_a.unit_id), "先移除部队归属")
	_check(units.remove_unit(unit_a.unit_id), "无归属单位可以删除")
	_check(not units.has_unit(unit_a.unit_id), "删除后无法查询到单位")
	_check(not units.remove_unit(unit_a.unit_id), "重复删除返回失败")

	var orphan := UnitData.new()
	orphan.config_id = "unknown_config"
	_check(not units.add_unit(orphan).is_empty(), "未知配置单位可注册")
	_check(not units.recalculate_stats(orphan.unit_id), "未注册兵种配置的重算失败")
	_check(not units.recalculate_stats("UNIT_999999"), "不存在单位重算失败")


func _test_experience(units: UnitManager, unit: UnitData, config: UnitConfig) -> void:
	_check(config.exp_to_next_level(1) == 100, "1 级升级需要 100 经验")
	_check(config.exp_to_next_level(2) == 150, "2 级升级需要 150 经验")
	_check(config.exp_to_next_level(3) == 200, "3 级升级需要 200 经验")

	_check(not units.add_exp(unit.unit_id, 0), "0 经验被拒绝")
	_check(not units.add_exp(unit.unit_id, -10), "负经验被拒绝")
	_check(not units.add_exp("UNIT_999999", 100), "不存在单位无法增加经验")

	_check(units.add_exp(unit.unit_id, 40), "增加未达升级线的经验")
	_check(unit.level == 1 and unit.exp == 40, "未达升级线不升级")

	_check(units.add_exp(unit.unit_id, 60), "补足经验触发升级")
	_check(unit.level == 2 and unit.exp == 0, "升级后扣除经验")
	_check(unit.max_hp == 55 and unit.attack == 11, "升级后属性自动重算")

	_check(units.add_exp(unit.unit_id, 450), "一次增加大量经验")
	_check(unit.level == 4 and unit.exp == 100, "一次经验可连续升多级")
	_check(unit.max_hp == 65 and unit.attack == 13, "连续升级后属性正确")

	_check(units.add_exp(unit.unit_id, 1000000), "增加足以升满的经验")
	_check(unit.level == 10 and unit.exp == 0, "达到最高等级并清空经验")
	_check(unit.max_hp == 95 and unit.attack == 19, "满级属性按上限计算")
	_check(not units.add_exp(unit.unit_id, 100), "满级后不再积累经验")
	_check(unit.level == 10 and unit.exp == 0, "满级后状态不变")


func _test_equipment(
	units: UnitManager,
	unit: UnitData,
	sword: EquipmentConfig,
	shield: EquipmentConfig,
	armor: EquipmentConfig
) -> void:
	_check(unit.equipment.is_empty(), "初始没有装备")

	_check(units.equip_item(unit.unit_id, sword.equipment_id), "装备铁剑成功")
	_check(unit.equipment.get("WEAPON", "") == "weapon_sword_01", "装备写入武器槽")
	_check(unit.attack == 12, "铁剑攻击加成生效")

	_check(units.equip_item(unit.unit_id, shield.equipment_id), "装备木盾成功")
	_check(unit.equipment.size() == 2, "两个槽位各一件装备")
	_check(unit.max_hp == 55, "木盾生命加成生效")
	_check(unit.current_hp == 50, "装备提高上限不自动回血")

	_check(units.equip_item(unit.unit_id, armor.equipment_id), "装备皮甲成功")
	_check(unit.max_hp == 63, "多件装备加成叠加")

	_check(not units.equip_item(unit.unit_id, "missing_equipment"), "未知装备 ID 失败")
	_check(unit.equipment.size() == 3, "失败不修改装备数据")

	var axe := EquipmentConfig.new()
	axe.equipment_id = "test_axe"
	axe.display_name = "测试斧"
	axe.slot = EquipmentConfig.Slot.WEAPON
	axe.attack_bonus = 5
	_check(units.register_equipment_config(axe), "注册同槽位新装备")
	_check(units.equip_item(unit.unit_id, axe.equipment_id), "同槽位替换装备")
	_check(unit.equipment.get("WEAPON", "") == "test_axe", "武器槽被替换")
	_check(unit.equipment.size() == 3, "同槽位替换不增加槽位数量")
	_check(unit.attack == 15, "替换后按新装备重算")

	_check(not units.unequip_slot(unit.unit_id, "HEAD"), "空槽位无法卸下")
	_check(not units.unequip_slot(unit.unit_id, "INVALID"), "非法槽位无法卸下")
	_check(units.unequip_slot(unit.unit_id, "WEAPON"), "卸下武器成功")
	_check(not unit.equipment.has("WEAPON"), "武器槽被清空")
	_check(unit.attack == 10, "卸下后攻击恢复基础值")

	unit.current_hp = 10
	_check(units.equip_item(unit.unit_id, armor.equipment_id), "已有皮甲时重复装备")
	_check(unit.current_hp == 10, "装备变化不重置当前 HP")

	units.unequip_slot(unit.unit_id, "BODY")
	units.unequip_slot(unit.unit_id, "OFFHAND")
	_check(unit.current_hp == 10 and unit.max_hp == 50, "卸下装备后上限恢复")
	_check(unit.current_hp == 10, "上限降低不自动回血")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[unit] OK: %s" % message)
	else:
		_failed = true
		push_error("[unit] FAIL: %s" % message)
