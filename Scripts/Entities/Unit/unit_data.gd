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

var faction_id: String = ""
var current_party_id: String = ""
var equipment: Dictionary = {}
var is_mounted: bool = false
## 玩家角色身份（持久化）；当前由谁控制由 BattleScene 运行时决定。
var is_player_character: bool = false

## 招募来源信息（游戏内时间、方式、地点、原阵营）。
var joined_at_game_time: float = 0.0
var recruit_source: String = ""
var recruit_settlement_id: String = ""
var origin_faction_id: String = ""


func is_alive() -> bool:
	return current_hp > 0


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
		"faction_id": faction_id,
		"current_party_id": current_party_id,
		"equipment": equipment.duplicate(true),
		"is_mounted": is_mounted,
		"is_player_character": is_player_character,
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
	unit.faction_id = str(data.get("faction_id", ""))
	unit.current_party_id = str(data.get("current_party_id", ""))
	unit.is_player_character = bool(data.get("is_player_character", false))
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
