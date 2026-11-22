class_name AdventurerCandidateData
extends RefCounted
## 村庄冒险者候选人的持久化运行时数据。
##
## 候选人不是部队成员，也不在 UnitManager 中注册；只有玩家支付金币招募后，
## 才通过 UnitManager 创建一个真正的 UnitData。候选人保留最终外观选择，
## 避免每次进入村庄重新随机。

enum Status {
	AVAILABLE,
	RECRUITED_PENDING_DEPARTURE,
}

var candidate_id: String = ""
var display_name: String = ""
var settlement_id: String = ""
var unit_config_id: String = ""
## 村庄小场景中的生成位置（世界像素）。
var world_position: Vector2 = Vector2.ZERO
var status: Status = Status.AVAILABLE
## 招募成功后关联的真实 UnitData ID；未招募时为空。
var unit_id: String = ""
## 创建时一次性生成的外观字典，结构与 UnitData.appearance 一致。
var appearance: Dictionary = {}


func is_available() -> bool:
	return status == Status.AVAILABLE


func to_dict() -> Dictionary:
	return {
		"candidate_id": candidate_id,
		"display_name": display_name,
		"settlement_id": settlement_id,
		"unit_config_id": unit_config_id,
		"world_position": [world_position.x, world_position.y],
		"status": int(status),
		"unit_id": unit_id,
		"appearance": appearance.duplicate(true),
	}


static func from_dict(data: Dictionary) -> AdventurerCandidateData:
	var candidate := AdventurerCandidateData.new()
	candidate.candidate_id = str(data.get("candidate_id", ""))
	candidate.display_name = str(data.get("display_name", ""))
	candidate.settlement_id = str(data.get("settlement_id", ""))
	candidate.unit_config_id = str(data.get("unit_config_id", ""))
	candidate.world_position = _read_vector2(data.get("world_position", []))
	var status_value: int = int(data.get("status", Status.AVAILABLE))
	if status_value < Status.AVAILABLE or status_value > Status.RECRUITED_PENDING_DEPARTURE:
		status_value = Status.AVAILABLE
	candidate.status = status_value as Status
	candidate.unit_id = str(data.get("unit_id", ""))
	var appearance_value: Variant = data.get("appearance", {})
	if appearance_value is Dictionary:
		candidate.appearance = (appearance_value as Dictionary).duplicate(true)
	return candidate


static func _read_vector2(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		var values: Array = value
		return Vector2(float(values[0]), float(values[1]))
	return Vector2.ZERO
