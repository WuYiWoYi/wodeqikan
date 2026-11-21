class_name UnitData
extends RefCounted
## 单个士兵/角色的持久化运行时数据。
##
## 权威数据：身份、等级、经验、装备、归属、招募来源。
## 派生数据：max_hp / attack 等最终属性，由 StatCalculator 依据配置与装备重算。
## current_hp 在非战斗状态下由世界侧写入；战斗期间以 BattleUnitState 为准。

var unit_id: String = ""
var config_id: String = ""
var display_name: String = ""

var level: int = 1
var exp: int = 0
## 每日工资。创建时来自兵种等级配置；晋升时切换到新等级工资。
## 骑马/下马不改变该值。旧存档缺失时用 -1 表示“按当前配置补全”。
var wage: int = 0

var max_hp: int = 1
var current_hp: int = 1
var attack: int = 0
var attack_interval: float = 1.0
var move_speed: float = 60.0
var attack_range: float = 20.0
## 由当前 WEAPON 装备派生：0 = 近战，1 = 远程。不通过兵种名称判断。
var attack_type: int = EquipmentConfig.AttackType.MELEE
## 远程命中判定使用的身体有效高度；骑乘时由 StatCalculator 追加坐骑高度。
var body_height: float = 48.0
## 远程武器发射物表现参数；近战单位保持默认值且不会被使用。
var projectile_texture_path: String = ""
var projectile_speed: float = 480.0
var projectile_arc_height: float = 70.0

var faction_id: String = ""
## 家族身份（持久化）。空字符串表示无家族，使用阵营色/默认外观。
var family_id: String = ""
var current_party_id: String = ""
var equipment: Dictionary = {}
var is_mounted: bool = false
## 玩家角色身份（持久化）；当前由谁控制由 BattleScene 运行时决定。
var is_player_character: bool = false
## 创建时一次性生成并持久化的外观选择。
## 键：family_id / tabard_variant / tabard_texture_path / tabard_color /
##     helmet_texture_path / plume_texture_path / spear_texture_path。
## 旧存档缺失时为空字典，回退到原有阵营外观。
var appearance: Dictionary = {}

## 招募来源信息（游戏内时间、方式、地点、原阵营）。
var joined_at_game_time: float = 0.0
var recruit_source: String = ""
var recruit_settlement_id: String = ""
var origin_faction_id: String = ""


func is_alive() -> bool:
	return current_hp > 0


## 当前装备的武器是否为远程武器。攻击行为入口统一读取该派生值。
func is_ranged_attacker() -> bool:
	return attack_type == EquipmentConfig.AttackType.RANGED


func clamp_hp() -> void:
	current_hp = clampi(current_hp, 0, maxi(max_hp, 0))


func to_dict() -> Dictionary:
	return {
		"unit_id": unit_id,
		"config_id": config_id,
		"display_name": display_name,
		"level": level,
		"exp": exp,
		"wage": wage,
		"max_hp": max_hp,
		"current_hp": current_hp,
		"attack": attack,
		"attack_interval": attack_interval,
		"move_speed": move_speed,
		"attack_range": attack_range,
		"attack_type": attack_type,
		"body_height": body_height,
		"projectile_texture_path": projectile_texture_path,
		"projectile_speed": projectile_speed,
		"projectile_arc_height": projectile_arc_height,
		"faction_id": faction_id,
		"family_id": family_id,
		"current_party_id": current_party_id,
		"equipment": equipment.duplicate(true),
		"is_mounted": is_mounted,
		"is_player_character": is_player_character,
		"appearance": appearance.duplicate(true),
		"joined_at_game_time": joined_at_game_time,
		"recruit_source": recruit_source,
		"recruit_settlement_id": recruit_settlement_id,
		"origin_faction_id": origin_faction_id,
	}


static func from_dict(data: Dictionary) -> UnitData:
	var unit := UnitData.new()
	unit.unit_id = str(data.get("unit_id", ""))
	unit.config_id = str(data.get("config_id", ""))
	unit.display_name = str(data.get("display_name", ""))
	unit.level = int(data.get("level", 1))
	unit.exp = int(data.get("exp", 0))
	# 旧存档没有 wage：保留 -1 哨兵，UnitManager 重算时按配置补全。
	unit.wage = int(data.get("wage", -1))
	unit.max_hp = int(data.get("max_hp", 1))
	unit.current_hp = int(data.get("current_hp", unit.max_hp))
	unit.attack = int(data.get("attack", 0))
	unit.attack_interval = float(data.get("attack_interval", 1.0))
	unit.move_speed = float(data.get("move_speed", 60.0))
	unit.attack_range = float(data.get("attack_range", 20.0))
	# 以下字段是旧存档没有的派生缓存；读档后由 UnitManager 按装备重算。
	unit.attack_type = int(data.get("attack_type", EquipmentConfig.AttackType.MELEE))
	unit.body_height = maxf(1.0, float(data.get("body_height", 48.0)))
	unit.projectile_texture_path = str(data.get("projectile_texture_path", ""))
	unit.projectile_speed = maxf(1.0, float(data.get("projectile_speed", 480.0)))
	unit.projectile_arc_height = maxf(
		0.0, float(data.get("projectile_arc_height", 70.0))
	)
	unit.faction_id = str(data.get("faction_id", ""))
	unit.family_id = str(data.get("family_id", ""))
	unit.current_party_id = str(data.get("current_party_id", ""))
	unit.is_player_character = bool(data.get("is_player_character", false))

	# 外观字段是阶段 6 追加的可选数据；旧存档没有时保持空字典。
	var appearance_value: Variant = data.get("appearance", {})
	if appearance_value is Dictionary:
		unit.appearance = (appearance_value as Dictionary).duplicate(true)
	unit.joined_at_game_time = float(data.get("joined_at_game_time", 0.0))
	unit.recruit_source = str(data.get("recruit_source", ""))
	unit.recruit_settlement_id = str(data.get("recruit_settlement_id", ""))
	unit.origin_faction_id = str(data.get("origin_faction_id", ""))

	var equipment_value: Variant = data.get("equipment", {})
	if equipment_value is Dictionary:
		unit.equipment = (equipment_value as Dictionary).duplicate(true)

	# 骑乘状态由 MOUNT 装备槽推导，不信任旧存档中的 is_mounted 标记。
	# 旧存档既没有 MOUNT 装备也没有马匹字段时，单位按步兵处理。
	unit.is_mounted = unit.equipment.has(
		EquipmentConfig.SLOT_NAMES[EquipmentConfig.Slot.MOUNT]
	)

	unit.clamp_hp()
	return unit
