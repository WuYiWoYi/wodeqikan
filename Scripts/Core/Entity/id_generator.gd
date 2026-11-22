class_name IdGenerator
extends RefCounted
## 持久化实体 ID 生成器。
##
## 格式：<PREFIX>_<6 位序号>，例如 UNIT_000001。
## ID 计数器随存档保存，ID 永不复用；禁止用节点名、节点路径或数组下标代替 ID。

const WORLD: String = "WORLD"
const UNIT: String = "UNIT"
const PARTY: String = "PARTY"
const LORD: String = "LORD"
const SETTLEMENT: String = "SETTLEMENT"
const FACTION: String = "FACTION"
const QUEST: String = "QUEST"
const BATTLE: String = "BATTLE"
const CANDIDATE: String = "CANDIDATE"

var _counters: Dictionary = {}


func next_id(prefix: String) -> String:
	if prefix.strip_edges().is_empty():
		push_error("IdGenerator.next_id 收到空前缀")
		return ""
	var next_value: int = int(_counters.get(prefix, 0)) + 1
	_counters[prefix] = next_value
	return "%s_%06d" % [prefix, next_value]


func peek_last_value(prefix: String) -> int:
	return int(_counters.get(prefix, 0))


func restore_from(counters: Dictionary) -> void:
	_counters = counters.duplicate(true)


func to_dict() -> Dictionary:
	return _counters.duplicate(true)
