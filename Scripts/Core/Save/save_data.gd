class_name SaveData
extends RefCounted
## 单个存档的完整持久化容器。
##
## 只保存数据，不保存场景节点。各实体以 ID 为键保存。
## Schema v3 增加世界日志；v4 增加领主、封地所有权、村庄人口/繁荣度、
## 采邑储备、冒险者候选人与玩家领主/玩家角色 ID。
## v5 增加贵族、家族与王国数据；旧存档的 lords 会迁移为 nobles。
## 阶段 11 增加 markets 字段（可选，缺失时按商品配置初始化），不提升 Schema。
## v6（阶段 12）增加独立马匹实例、村庄市场、NPC 背包/资金与每日补给结算日。
## v7（阶段 13）增加伤兵状态、部队俘虏列表、俘虏归属与伤兵治疗结算小时。
## v8 增加战斗经验五级制（旧 1–10 级折算）与 NPC 领主赎回记录。
## 读取时保留 v1 → v8 的浅迁移入口，缺失字段按安全默认值恢复。

const CURRENT_SCHEMA_VERSION: int = 8
## 战斗经验等级上限；与 CombatExperience.MAX_LEVEL 保持一致。
const MAX_COMBAT_LEVEL: int = 5

var schema_version: int = CURRENT_SCHEMA_VERSION
var project_version: String = "0.2.0"
var saved_at: String = ""

var world_id: String = ""
var world_created_at: String = ""
var world_size: Vector2 = Vector2.ZERO

var world_elapsed_seconds: float = 0.0
var world_base_speed: float = 1.0
var id_counters: Dictionary = {}
## 上一次完成补给结算的游戏日（TimeManager total_days）。
## -1 表示旧存档尚未结算过，读档后以当前日作为起点。
var supply_last_settled_day: int = -1
## 阶段 13：上一次完成伤兵治疗结算的游戏小时（累计小时）。
## -1 表示旧存档/新世界尚未初始化，读档后以当前小时为起点，不补发历史治疗。
var healing_last_settled_hour: int = -1

var player_party_id: String = ""
var player: Dictionary = {}
var world_state: Dictionary = {}
var scene_state: Dictionary = {}
## 世界日志：战斗结果、部队覆灭与遭遇历史。
var world_log: Dictionary = {}

## 以下均为 { 实体 ID: 实体数据字典 }。
var units: Dictionary = {}
var parties: Dictionary = {}
## 贵族数据（v5 权威字段）。
var nobles: Dictionary = {}
## 兼容 v4：旧存档只有 lords；读取时回退到 nobles。
var lords: Dictionary = {}
var houses: Dictionary = {}
var kingdoms: Dictionary = {}
var settlements: Dictionary = {}
## 村庄/城镇市场库存：{ settlement_id: { stock, mount_instances, initialized_items } }。
## 旧存档缺失时由 MarketManager 按当前商品配置初始化一次。
var markets: Dictionary = {}
## NPC 领主赎回记录：{ ransom_id: { noble_id, status, due_world_seconds, ... } }。
var ransoms: Dictionary = {}
var factions: Dictionary = {}
var quests: Dictionary = {}


func to_dict() -> Dictionary:
	var player_payload: Dictionary = player.duplicate(true)
	player_payload["party_id"] = player_party_id

	return {
		"schema_version": schema_version,
		"project_version": project_version,
		"saved_at": Time.get_datetime_string_from_system(),
		"world": {
			"world_id": world_id,
			"created_at": world_created_at,
			"size": [world_size.x, world_size.y],
		},
		"time": {
			"world_elapsed_seconds": world_elapsed_seconds,
			"world_base_speed": world_base_speed,
			"supply_last_settled_day": supply_last_settled_day,
			"healing_last_settled_hour": healing_last_settled_hour,
		},
		"id_counters": id_counters.duplicate(true),
		"player": player_payload,
		"world_state": world_state.duplicate(true),
		"scene_state": scene_state.duplicate(true),
		"world_log": world_log.duplicate(true),
		"units": units.duplicate(true),
		"parties": parties.duplicate(true),
		"nobles": nobles.duplicate(true),
		"lords": lords.duplicate(true),
		"houses": houses.duplicate(true),
		"kingdoms": kingdoms.duplicate(true),
		"settlements": settlements.duplicate(true),
		"markets": markets.duplicate(true),
		"ransoms": ransoms.duplicate(true),
		"factions": factions.duplicate(true),
		"quests": quests.duplicate(true),
	}


## 读取失败（版本不兼容或坏数据）返回 null。
static func from_dict(payload: Dictionary) -> SaveData:
	var save := SaveData.new()
	save.schema_version = int(payload.get("schema_version", 0))
	save.project_version = str(payload.get("project_version", ""))

	if save.schema_version <= 0 or save.schema_version > CURRENT_SCHEMA_VERSION:
		push_error(
			"存档版本 %s 不受支持（当前支持 1..%s）"
			% [save.schema_version, CURRENT_SCHEMA_VERSION]
		)
		return null

	save.saved_at = str(payload.get("saved_at", ""))

	var world_block: Dictionary = _as_dict(payload.get("world", {}))
	save.world_id = str(world_block.get("world_id", ""))
	save.world_created_at = str(world_block.get("created_at", ""))
	save.world_size = _read_vector2(world_block.get("size", []), Vector2.ZERO)

	var time_block: Dictionary = _as_dict(payload.get("time", {}))
	save.world_elapsed_seconds = maxf(0.0, float(time_block.get("world_elapsed_seconds", 0.0)))
	save.world_base_speed = float(time_block.get("world_base_speed", 1.0))
	save.supply_last_settled_day = int(
		time_block.get("supply_last_settled_day", -1)
	)
	save.healing_last_settled_hour = int(
		time_block.get("healing_last_settled_hour", -1)
	)

	save.id_counters = _as_dict(payload.get("id_counters", {}))
	save.player = _as_dict(payload.get("player", {}))
	save.player_party_id = str(payload.get("player_party_id", save.player.get("party_id", "")))
	save.world_state = _as_dict(payload.get("world_state", {}))
	save.scene_state = _as_dict(payload.get("scene_state", {}))
	save.world_log = _as_dict(payload.get("world_log", {}))
	save.units = _as_dict(payload.get("units", {}))
	save.parties = _as_dict(payload.get("parties", {}))
	save.nobles = _as_dict(payload.get("nobles", {}))
	save.lords = _as_dict(payload.get("lords", {}))
	save.houses = _as_dict(payload.get("houses", {}))
	save.kingdoms = _as_dict(payload.get("kingdoms", {}))
	save.settlements = _as_dict(payload.get("settlements", {}))
	save.markets = _as_dict(payload.get("markets", {}))
	save.ransoms = _as_dict(payload.get("ransoms", {}))
	save.factions = _as_dict(payload.get("factions", {}))
	save.quests = _as_dict(payload.get("quests", {}))

	# Schema v1 -> v2 迁移：旧存档缺少 world 字段，保留原始 player 数据。
	if save.schema_version < 2:
		save.schema_version = 2
	# v6 -> v7：缺失的伤兵/俘虏字段由 UnitData/PartyData 的默认值补齐；
	# 归属双向校正由 PartyManager.sanitize_prisoner_ownership() 幂等完成。
	if save.schema_version < 7:
		save.schema_version = 7
	# v7 -> v8：旧存档的 1–10 级战斗经验折算为 5 级制；
	# 赎回记录缺失时为空，旧存档不需要伪造历史出售记录。
	if save.schema_version < 8:
		_migrate_legacy_unit_levels(save.units)
		save.schema_version = 8
	# v4 -> v5：旧存档只有 lords，没有独立 nobles/houses/kingdoms；
	# 具体政治数据由 WorldContext 在加载后迁移，不在这里伪造实体。
	return save


## 旧存档的 1–10 级战斗经验按 ceil(level / 2) 折算为 5 级；
## 溢出经验保留，由 UnitManager 在加载后按新阈值补升级。
## 已经是 5 级内的存档不改变等级，重复调用安全。
static func _migrate_legacy_unit_levels(units_payload: Dictionary) -> void:
	for unit_id: Variant in units_payload:
		var value: Variant = units_payload[unit_id]
		if not value is Dictionary:
			continue
		var data := value as Dictionary
		var old_level: int = int(data.get("level", 1))
		if old_level > MAX_COMBAT_LEVEL:
			var new_level: int = int(ceil(float(old_level) / 2.0))
			data["level"] = clampi(new_level, 1, MAX_COMBAT_LEVEL)
		data["exp"] = maxi(0, int(data.get("exp", 0)))
		units_payload[unit_id] = data


static func _as_dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


static func _read_vector2(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		var values: Array = value
		return Vector2(float(values[0]), float(values[1]))
	return fallback
