class_name PartyData
extends RefCounted
## 大地图部队的持久化运行时数据。
##
## 部队是大地图的基本移动实体；成员归属以 UnitData.current_party_id
## 与 PartyData.member_unit_ids 双向一致，修改必须统一经过 PartyManager。

enum BattleState {
	AVAILABLE,
	IN_BATTLE,
	RETURNING,
	DISABLED,
}

enum MovementState {
	IDLE,
	MOVING,
}

enum OrderType {
	NONE,
	MOVE,
	HOLD,
	INTERACT,
	BATTLE,
	FOLLOW_PARTY,
}

enum PartyAIType {
	NONE,
	TRADE_ROUTE,
	PATROL,
	BANDIT,
	GUARD,
}

## 部队控制类型：玩家输入或 NPC AI。
## 控制类型只决定“谁下达指令”，与阵营、家族、领袖身份相互独立。
enum ControlType {
	PLAYER,
	AI,
}

## 部队类型标识：只用于初始配置、表现与对话文本选择。
## 移动、成员、遭遇、战斗、结算与存档流程必须共用同一套 Party 架构。
enum PartyKind {
	GENERIC,
	PLAYER,
	FAMILY,
	MERCHANT,
	BANDIT,
	GUARD,
}

## 大地图行动意图：供悬浮面板展示，由现有权威字段推导。
## 这是只读派生状态，不进入存档，也不参与 AI 决定；
## UI 遇到无法命中的行为时可回退到 TRAVEL / IDLE。
enum Activity {
	IDLE,
	PATROL,
	TRAVEL,
	PURSUIT,
	RESPOND_TO_BATTLE,
	RECRUITING,
	FOLLOWING,
}

var party_id: String = ""
var party_name: String = ""
var faction_id: String = ""
## 所属家族（持久化）；空字符串表示无家族。
## 家族只影响表现，不代表阵营关系。
var family_id: String = ""
## 部队控制类型（持久化）。玩家部队为 PLAYER，其余默认 AI。
## 控制类型不参与阵营敌对判断，也不决定成员归属。
var control_type: ControlType = ControlType.AI
## 部队类型标识（持久化）；缺失时按阵营/家族/AI 类型安全推断。
var party_kind: PartyKind = PartyKind.GENERIC
## 部队旗帜贴图（持久化，可为空）。为空时大地图回退到家族旗帜。
## 旗帜属于部队表现数据，新增部队类型不需要新的标记节点。
var banner_texture_path: String = ""

## 当前领袖的 UnitData.unit_id（持久化）。
## 玩家身份、当前控制权和部队领袖是三个独立概念：
## - is_player_character 表示“这是玩家角色”；
## - BattleScene 的 controlled 表示“当前控制谁”；
## - leader_unit_id 表示“这支部队的领袖是谁”。
var leader_unit_id: String = ""
## 指挥本部队的贵族（NobleData.noble_id，持久化）。
## 部队→贵族→家族→王国的政治链路从这里开始；
## 旧存档缺失时由 NobleManager 按 noble.party_id 反向补齐。
var leader_noble_id: String = ""
## 旧领主字段保留用于兼容旧存档；新逻辑统一读取 leader_noble_id。
var leader_lord_id: String = ""

var world_position: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO
var movement_speed: float = 10.0
var sight_range: float = 40.0

var member_unit_ids: Array[String] = []
var current_order: OrderType = OrderType.NONE
var current_target_id: String = ""
var movement_state: MovementState = MovementState.IDLE
var battle_state: BattleState = BattleState.AVAILABLE

## 大地图 AI 行为。ai_route_index 表示下一步要前往的路线点索引。
## 商队路线使用 stable settlement_id；巡逻路线点由 AIManager 按类型提供。
var ai_type: PartyAIType = PartyAIType.NONE
var ai_route_index: int = 0
var ai_route_settlement_ids: Array[String] = []
## 该部队专属的巡逻点（持久化）。为空时 AIManager 使用全局默认巡逻路线。
## 家族骑士与新增强盗使用独立路线，避免写死在某张地图的 AI 代码中。
var ai_patrol_points: Array[Vector2] = []

## 运行时攻击/拦截意图，不进入存档；由 AIManager 维护，供大地图遭遇判定使用。
var attack_intent: bool = false

## 玩家主动追逐/接近的目标部队 ID，仅运行时使用，不进入存档。
## 非空时大地图不自动弹出村庄信息或无关部队对话，避免打断玩家追逐。
var focus_party_id: String = ""

## 战斗刚结束时禁止立即再次交战的截止世界时间（仅运行时，不进入存档）。
## 存活部队需要时间脱离接触；到期后由 AI 正常重新决策。
var engagement_cooldown_until: float = 0.0

## AI 已发现并正在接近的离屏战斗 ID（仅运行时，不进入存档）。
## 用于“看见战斗 → 前往战场”的目标保持，避免每个决策周期在发现/失去视野间抖动。
var battle_response_id: String = ""
## 战场响应目标保持截止世界时间；到期后若仍看不见参战方则放弃。
var battle_response_until: float = 0.0


func has_member(unit_id: String) -> bool:
	return member_unit_ids.has(unit_id)


func is_available_for_world() -> bool:
	return battle_state == BattleState.AVAILABLE


func is_player_controlled() -> bool:
	return control_type == ControlType.PLAYER


## 稳定的类型键，供遭遇文本配置与 UI 显示使用。
func get_kind_key() -> String:
	match party_kind:
		PartyKind.PLAYER:
			return "PLAYER"
		PartyKind.FAMILY:
			return "FAMILY"
		PartyKind.MERCHANT:
			return "MERCHANT"
		PartyKind.BANDIT:
			return "BANDIT"
		PartyKind.GUARD:
			return "GUARD"
		_:
			return "GENERIC"


## 从现有权威字段推导行动意图；不修改任何状态。
## 优先级：战场响应 > 追击攻击 > 跟随 > AI 路线/巡逻 > 普通移动。
func get_activity_state() -> Activity:
	if not battle_response_id.is_empty():
		return Activity.RESPOND_TO_BATTLE
	if attack_intent and not current_target_id.is_empty():
		return Activity.PURSUIT
	if current_order == OrderType.FOLLOW_PARTY:
		return Activity.FOLLOWING
	match ai_type:
		PartyAIType.PATROL, PartyAIType.GUARD:
			if movement_state == MovementState.MOVING:
				return Activity.PATROL
		PartyAIType.TRADE_ROUTE, PartyAIType.BANDIT:
			if movement_state == MovementState.MOVING:
				return Activity.TRAVEL
		_:
			pass
	if movement_state == MovementState.MOVING:
		return Activity.TRAVEL
	return Activity.IDLE


## 读档后补齐旧存档缺失的控制类型与部队类型。
## 只在类型为 GENERIC 时按现有字段推断，不覆盖已经持久化的明确类型；
## 玩家部队的控制权始终以 player_party_id 为准。
func apply_runtime_defaults(player_party_id: String) -> void:
	if not player_party_id.is_empty() and party_id == player_party_id:
		control_type = ControlType.PLAYER
		party_kind = PartyKind.PLAYER
		return

	control_type = ControlType.AI
	if party_kind != PartyKind.GENERIC:
		return
	if not family_id.is_empty():
		party_kind = PartyKind.FAMILY
	elif faction_id == FactionManager.BANDIT_FACTION_ID:
		party_kind = PartyKind.BANDIT
	elif faction_id == FactionManager.GUARD_FACTION_ID \
			or ai_type == PartyAIType.GUARD:
		party_kind = PartyKind.GUARD
	elif faction_id == FactionManager.MERCHANT_FACTION_ID \
			or ai_type == PartyAIType.TRADE_ROUTE:
		party_kind = PartyKind.MERCHANT


func to_dict() -> Dictionary:
	return {
		"party_id": party_id,
		"party_name": party_name,
		"faction_id": faction_id,
		"family_id": family_id,
		"control_type": int(control_type),
		"party_kind": int(party_kind),
		"banner_texture_path": banner_texture_path,
		"leader_unit_id": leader_unit_id,
		"leader_noble_id": leader_noble_id,
		"leader_lord_id": leader_lord_id,
		"world_position": [world_position.x, world_position.y],
		"target_position": [target_position.x, target_position.y],
		"movement_speed": movement_speed,
		"sight_range": sight_range,
		"member_unit_ids": member_unit_ids.duplicate(),
		"current_order": int(current_order),
		"current_target_id": current_target_id,
		"movement_state": int(movement_state),
		"battle_state": int(battle_state),
		"ai_type": int(ai_type),
		"ai_route_index": ai_route_index,
		"ai_route_settlement_ids": ai_route_settlement_ids.duplicate(),
		"ai_patrol_points": _vector2_array_to_data(ai_patrol_points),
	}


static func from_dict(data: Dictionary) -> PartyData:
	var party := PartyData.new()
	party.party_id = str(data.get("party_id", ""))
	party.party_name = str(data.get("party_name", ""))
	party.faction_id = str(data.get("faction_id", ""))
	party.family_id = str(data.get("family_id", ""))
	var control_value: int = int(data.get("control_type", ControlType.AI))
	if control_value < ControlType.PLAYER or control_value > ControlType.AI:
		control_value = ControlType.AI
	party.control_type = control_value as ControlType
	var kind_value: int = int(data.get("party_kind", PartyKind.GENERIC))
	if kind_value < PartyKind.GENERIC or kind_value > PartyKind.GUARD:
		kind_value = PartyKind.GENERIC
	party.party_kind = kind_value as PartyKind
	party.banner_texture_path = str(data.get("banner_texture_path", ""))
	party.leader_unit_id = str(data.get("leader_unit_id", ""))
	party.leader_noble_id = str(data.get("leader_noble_id", data.get("leader_lord_id", "")))
	party.leader_lord_id = str(data.get("leader_lord_id", ""))
	party.world_position = _read_vector2(data.get("world_position", []))
	party.target_position = _read_vector2(data.get("target_position", []))
	party.movement_speed = float(data.get("movement_speed", 10.0))
	party.sight_range = float(data.get("sight_range", 40.0))
	party.current_order = _read_enum(
		data.get("current_order", OrderType.NONE), OrderType.NONE, OrderType.FOLLOW_PARTY
	) as OrderType
	party.current_target_id = str(data.get("current_target_id", ""))
	party.movement_state = _read_enum(
		data.get("movement_state", MovementState.IDLE),
		MovementState.IDLE,
		MovementState.MOVING
	) as MovementState
	party.battle_state = _read_enum(
		data.get("battle_state", BattleState.AVAILABLE),
		BattleState.AVAILABLE,
		BattleState.DISABLED
	) as BattleState

	var member_values: Variant = data.get("member_unit_ids", [])
	if member_values is Array:
		for value: Variant in member_values:
			party.member_unit_ids.append(str(value))

	var ai_value: int = int(data.get("ai_type", PartyAIType.NONE))
	if ai_value < PartyAIType.NONE or ai_value > PartyAIType.GUARD:
		ai_value = PartyAIType.NONE
	party.ai_type = ai_value as PartyAIType
	party.ai_route_index = maxi(0, int(data.get("ai_route_index", 0)))

	var route_values: Variant = data.get("ai_route_settlement_ids", [])
	if route_values is Array:
		for value: Variant in route_values:
			party.ai_route_settlement_ids.append(str(value))

	var patrol_values: Variant = data.get("ai_patrol_points", [])
	if patrol_values is Array:
		for value: Variant in patrol_values:
			party.ai_patrol_points.append(_read_vector2(value))

	return party


## 读取整数枚举；超出范围时回退到给定默认值，避免坏存档产生幽灵状态。
static func _read_enum(value: Variant, fallback: int, max_value: int) -> int:
	var parsed: int = int(value)
	if parsed < 0 or parsed > max_value:
		return fallback
	return parsed


static func _vector2_array_to_data(points: Array[Vector2]) -> Array:
	var result: Array = []
	for point: Vector2 in points:
		result.append([point.x, point.y])
	return result


static func _read_vector2(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		var values: Array = value
		return Vector2(float(values[0]), float(values[1]))
	return Vector2.ZERO
