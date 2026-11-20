class_name SaveData
extends RefCounted
## 单个存档的完整持久化容器。
##
## 只保存数据，不保存场景节点。各实体以 ID 为键保存。
## Schema v2 增加了世界标识、世界尺寸与玩家部队 ID。

const CURRENT_SCHEMA_VERSION: int = 2

var schema_version: int = CURRENT_SCHEMA_VERSION
var project_version: String = "0.2.0"
var saved_at: String = ""

var world_id: String = ""
var world_created_at: String = ""
var world_size: Vector2 = Vector2.ZERO

var world_elapsed_seconds: float = 0.0
var world_base_speed: float = 1.0
var id_counters: Dictionary = {}

var player_party_id: String = ""
var player: Dictionary = {}
var world_state: Dictionary = {}
var scene_state: Dictionary = {}

## 以下均为 { 实体 ID: 实体数据字典 }。
var units: Dictionary = {}
var parties: Dictionary = {}
var lords: Dictionary = {}
var settlements: Dictionary = {}
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
		},
		"id_counters": id_counters.duplicate(true),
		"player": player_payload,
		"world_state": world_state.duplicate(true),
		"scene_state": scene_state.duplicate(true),
		"units": units.duplicate(true),
		"parties": parties.duplicate(true),
		"lords": lords.duplicate(true),
		"settlements": settlements.duplicate(true),
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

	save.id_counters = _as_dict(payload.get("id_counters", {}))
	save.player = _as_dict(payload.get("player", {}))
	save.player_party_id = str(payload.get("player_party_id", save.player.get("party_id", "")))
	save.world_state = _as_dict(payload.get("world_state", {}))
	save.scene_state = _as_dict(payload.get("scene_state", {}))
	save.units = _as_dict(payload.get("units", {}))
	save.parties = _as_dict(payload.get("parties", {}))
	save.lords = _as_dict(payload.get("lords", {}))
	save.settlements = _as_dict(payload.get("settlements", {}))
	save.factions = _as_dict(payload.get("factions", {}))
	save.quests = _as_dict(payload.get("quests", {}))

	# Schema v1 -> v2 迁移：旧存档缺少 world 字段，保留原始 player 数据。
	if save.schema_version < 2:
		save.schema_version = 2
	return save


static func _as_dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


static func _read_vector2(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		var values: Array = value
		return Vector2(float(values[0]), float(values[1]))
	return fallback
