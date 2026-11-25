class_name AdventurerCandidateData
extends RefCounted
## 村庄冒险者候选人的持久化运行时数据。
##
## 阶段 13 起，每名候选人拥有独立的 UnitData 身份（唯一 unit_id、等级、属性、
## 装备与外观快照），但候选人数据仍保存在村庄中，既不属于任何部队，
## 也不在 UnitManager 仓储里注册；只有玩家支付金币招募后才通过 add_unit()
## 进入仓储并加入玩家部队。unit_data 保存该身份的完整快照，招募后清空，
## 避免与仓储中的同一单位重复。候选人保留最终外观选择，避免重复随机。

enum Status {
	AVAILABLE,
	RECRUITED_PENDING_DEPARTURE,
}

var candidate_id: String = ""
var display_name: String = ""
var settlement_id: String = ""
var unit_config_id: String = ""
## 贵族冒险者：固定三级士兵，只允许村庄拥有者招募，并自带一匹真实战马实例。
## 普通冒险者保持 false，沿用原有生成与刷新规则。
var is_noble: bool = false
## 村庄小场景中的生成位置（世界像素）。
var world_position: Vector2 = Vector2.ZERO
var status: Status = Status.AVAILABLE
## 候选人独立 Unit 身份的 ID；招募后仍保留，便于追溯。
var unit_id: String = ""
## 候选人 UnitData 的完整快照（UnitData.to_dict()）。
## AVAILABLE 时保存身份；招募后清空，单位改由 UnitManager 仓储持有。
var unit_data: Dictionary = {}
## 创建时一次性生成的外观字典，结构与 UnitData.appearance 一致。
var appearance: Dictionary = {}
## 贵族冒险者自备战马的独立实例（MountInstanceData.to_dict()）。
## 与 unit_data 中的 mount_instance 指向同一匹马；招募后清空 unit_data 时
## 仍保留该显示数据，直到候选人记录被清理。
var mount_instance: Dictionary = {}


func is_available() -> bool:
	return status == Status.AVAILABLE


## 返回候选人携带的真实马匹实例；普通冒险者或数据缺失时返回 null。
func get_mount_instance_data() -> MountInstanceData:
	if mount_instance.is_empty():
		var snapshot_mount: Variant = unit_data.get("mount_instance", {})
		if snapshot_mount is Dictionary and not (snapshot_mount as Dictionary).is_empty():
			return MountInstanceData.from_dict(snapshot_mount as Dictionary)
		return null
	return MountInstanceData.from_dict(mount_instance)


func to_dict() -> Dictionary:
	return {
		"candidate_id": candidate_id,
		"display_name": display_name,
		"settlement_id": settlement_id,
		"unit_config_id": unit_config_id,
		"is_noble": is_noble,
		"world_position": [world_position.x, world_position.y],
		"status": int(status),
		"unit_id": unit_id,
		"unit_data": unit_data.duplicate(true),
		"appearance": appearance.duplicate(true),
		"mount_instance": mount_instance.duplicate(true),
	}


static func from_dict(data: Dictionary) -> AdventurerCandidateData:
	var candidate := AdventurerCandidateData.new()
	candidate.candidate_id = str(data.get("candidate_id", ""))
	candidate.display_name = str(data.get("display_name", ""))
	candidate.settlement_id = str(data.get("settlement_id", ""))
	candidate.unit_config_id = str(data.get("unit_config_id", ""))
	candidate.is_noble = bool(data.get("is_noble", false))
	candidate.world_position = _read_vector2(data.get("world_position", []))
	var status_value: int = int(data.get("status", Status.AVAILABLE))
	if status_value < Status.AVAILABLE or status_value > Status.RECRUITED_PENDING_DEPARTURE:
		status_value = Status.AVAILABLE
	candidate.status = status_value as Status
	candidate.unit_id = str(data.get("unit_id", ""))
	var unit_data_value: Variant = data.get("unit_data", {})
	if unit_data_value is Dictionary:
		candidate.unit_data = (unit_data_value as Dictionary).duplicate(true)
	var appearance_value: Variant = data.get("appearance", {})
	if appearance_value is Dictionary:
		candidate.appearance = (appearance_value as Dictionary).duplicate(true)
	var mount_value: Variant = data.get("mount_instance", {})
	if mount_value is Dictionary:
		candidate.mount_instance = (mount_value as Dictionary).duplicate(true)
	return candidate


static func _read_vector2(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		var values: Array = value
		return Vector2(float(values[0]), float(values[1]))
	return Vector2.ZERO
