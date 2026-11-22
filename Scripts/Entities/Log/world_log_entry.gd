class_name WorldLogEntry
extends RefCounted
## 世界日志中的单条记录。
##
## 只保存事件类型、发生时间与显示文本；不持有 UI、管理器或场景节点。

enum EventType {
	OTHER,
	BATTLE_STARTED,
	BATTLE_FINISHED,
	PARTY_ELIMINATED,
	PLAYER_ENCOUNTER,
	SETTLEMENT_ENTERED,
	SETTLEMENT_EXITED,
	FIEF_RECRUITED,
	ADVENTURER_RECRUITED,
	NOBLE_DIED,
	HOUSE_LEADER_CHANGED,
	KINGDOM_PENDING,
}

var event_type: EventType = EventType.OTHER
var world_time_seconds: float = 0.0
var time_text: String = ""
var text: String = ""
var metadata: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"event_type": int(event_type),
		"world_time_seconds": world_time_seconds,
		"time_text": time_text,
		"text": text,
		"metadata": metadata.duplicate(true),
	}


static func from_dict(data: Dictionary) -> WorldLogEntry:
	var entry := WorldLogEntry.new()
	var type_value: int = int(data.get("event_type", EventType.OTHER))
	if type_value < int(EventType.OTHER) \
			or type_value > int(EventType.KINGDOM_PENDING):
		type_value = int(EventType.OTHER)
	entry.event_type = type_value as EventType
	entry.world_time_seconds = float(data.get("world_time_seconds", 0.0))
	entry.time_text = str(data.get("time_text", ""))
	entry.text = str(data.get("text", ""))
	var metadata_value: Variant = data.get("metadata", {})
	if metadata_value is Dictionary:
		entry.metadata = (metadata_value as Dictionary).duplicate(true)
	return entry
