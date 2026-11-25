class_name MercenaryData
extends RefCounted
## 全地图可招募雇佣兵的世界记录（持久化）。
##
## 一名雇佣兵在同一时刻只处于一种状态：
## - WAITING：尚未分配到酒馆，留在全地图待分配池；
## - STATIONED：驻留在 settlement_id 对应的城镇酒馆；
## - TRAVELING：正在前往 destination_settlement_id 的酒馆途中。
##
## 身份、类型、战斗经验与骑马属性在生成时确定；被玩家或 NPC 招募后
## 由 MercenaryManager 删除记录，不再回到可招募池。

enum State {
	WAITING,
	STATIONED,
	TRAVELING,
}

var mercenary_id: String = ""
var config_id: String = ""
var display_name: String = ""
## 兵种等级快照（2 或 3），价格计算与 UI 不依赖配置是否仍可加载。
var tier: int = 2
## 初始战斗经验等级（2 普通士兵 / 3 老兵 / 4 精锐）。
var level: int = 2
var exp: int = 0
## 是否骑马；参与价格计算，且必须与实际配置的 MOUNT 默认装备一致。
var mounted: bool = false
## 招募预览与最终单位共用的外观快照（持久化）。
## 旧存档缺失时由 MercenaryManager 在首次预览/招募时按雇佣兵规则生成并回填。
var appearance: Dictionary = {}

var state: State = State.WAITING
## STATIONED 时为当前酒馆城镇 ID；其他状态为空。
var settlement_id: String = ""
## TRAVELING 时的目标城镇酒馆 ID；其他状态为空。
var destination_settlement_id: String = ""
## TRAVELING 剩余世界时间（秒）。
var travel_remaining: float = 0.0
## 生成时的世界时间，仅用于展示与调试。
var spawned_at: float = 0.0


func is_waiting() -> bool:
	return state == State.WAITING


func is_stationed() -> bool:
	return state == State.STATIONED


func is_traveling() -> bool:
	return state == State.TRAVELING


func to_dict() -> Dictionary:
	return {
		"mercenary_id": mercenary_id,
		"config_id": config_id,
		"display_name": display_name,
		"tier": tier,
		"level": level,
		"exp": exp,
		"mounted": mounted,
		"state": int(state),
		"settlement_id": settlement_id,
		"destination_settlement_id": destination_settlement_id,
		"travel_remaining": travel_remaining,
		"spawned_at": spawned_at,
		"appearance": appearance.duplicate(true),
	}


static func from_dict(data: Dictionary) -> MercenaryData:
	var mercenary := MercenaryData.new()
	mercenary.mercenary_id = str(data.get("mercenary_id", ""))
	mercenary.config_id = str(data.get("config_id", ""))
	mercenary.display_name = str(data.get("display_name", ""))
	mercenary.tier = clampi(int(data.get("tier", 2)), 1, 3)
	mercenary.level = clampi(
		int(data.get("level", 2)),
		1,
		CombatExperience.MAX_LEVEL
	)
	mercenary.exp = maxi(0, int(data.get("exp", 0)))
	mercenary.mounted = bool(data.get("mounted", false))
	var state_value: int = int(data.get("state", State.WAITING))
	if state_value < State.WAITING or state_value > State.TRAVELING:
		state_value = State.WAITING
	mercenary.state = state_value as State
	mercenary.settlement_id = str(data.get("settlement_id", ""))
	mercenary.destination_settlement_id = str(
		data.get("destination_settlement_id", "")
	)
	mercenary.travel_remaining = maxf(0.0, float(data.get("travel_remaining", 0.0)))
	mercenary.spawned_at = maxf(0.0, float(data.get("spawned_at", 0.0)))
	var appearance_value: Variant = data.get("appearance", {})
	if appearance_value is Dictionary:
		mercenary.appearance = (appearance_value as Dictionary).duplicate(true)
	return mercenary
