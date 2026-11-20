class_name SaveData
extends RefCounted
## 单个存档的完整持久化容器。
##
## 只保存数据，不保存场景节点。各实体以 ID 为键保存。
## 阶段 0 先建立结构与版本号，聚合逻辑在阶段 0 后半段实现。

const CURRENT_SCHEMA_VERSION: int = 1

var schema_version: int = CURRENT_SCHEMA_VERSION
var project_version: String = "0.1.0"
var saved_at: String = ""

var world_elapsed_seconds: float = 0.0
var world_base_speed: float = 1.0
var id_counters: Dictionary = {}

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
	return {
		"schema_version": schema_version,
		"project_version": project_version,
		"saved_at": Time.get_datetime_string_from_system(),
		"time": {
			"world_elapsed_seconds": world_elapsed_seconds,
			"world_base_speed": world_base_speed,
		},
		"id_counters": id_counters.duplicate(true),
		"player": player.duplicate(true),
		"world_state": world_state.duplicate(true),
		"scene_state": scene_state.duplicate(true),
		"units": units.duplicate(true),
		"parties": parties.duplicate(true),
		"lords": lords.duplicate(true),
		"settlements": settlements.duplicate(true),
		"factions": factions.duplicate(true),
		"quests": quests.duplicate(true),
	}


## 读取失败（版本不兼容）返回 null。
static func from_dict(payload: Dictionary) -> SaveData:
	var save := SaveData.new()
	save.schema_version = int(payload.get("schema_version", 0))
	save.project_version = str(payload.get("project_version", ""))

	if save.schema_version > CURRENT_SCHEMA_VERSION:
		push_error(
			"存档版本 %s 高于当前支持的版本 %s" % [save.schema_version, CURRENT_SCHEMA_VERSION]
		)
		return null

	save.saved_at = str(payload.get("saved_at", ""))

	var time_block: Dictionary = _as_dict(payload.get("time", {}))
	save.world_elapsed_seconds = float(time_block.get("world_elapsed_seconds", 0.0))
	save.world_base_speed = float(time_block.get("world_base_speed", 1.0))

	save.id_counters = _as_dict(payload.get("id_counters", {}))
	save.player = _as_dict(payload.get("player", {}))
	save.world_state = _as_dict(payload.get("world_state", {}))
	save.scene_state = _as_dict(payload.get("scene_state", {}))
	save.units = _as_dict(payload.get("units", {}))
	save.parties = _as_dict(payload.get("parties", {}))
	save.lords = _as_dict(payload.get("lords", {}))
	save.settlements = _as_dict(payload.get("settlements", {}))
	save.factions = _as_dict(payload.get("factions", {}))
	save.quests = _as_dict(payload.get("quests", {}))

	# TODO(schema v2+)：在这里执行数据迁移。
	return save


static func _as_dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}
