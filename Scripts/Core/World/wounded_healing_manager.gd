class_name WoundedHealingManager
extends RefCounted
## 伤兵按 WorldTime 顺序恢复的唯一结算入口。
##
## 规则：
## - 每经过 1 个游戏小时，每个仍在模拟中的部队获得 healing_per_hour 点治疗；
## - 按 PartyData.member_unit_ids 的成员顺序依次补 HP，先补满前一个再补下一个；
## - 所有单位满血后多余点数直接丢弃；
## - 暂停时不推进（WorldSimulation 不收到 tick），1x/2x 都按游戏小时结算；
## - last_settled_hour 持久化，读档不会重复结算同一小时；
## - 已被移除/解散的部队不在 PartyManager 中，自然不会被治疗。
##
## 只修改 UnitData 的 HP/状态与“仅剩伤兵”部队的可行动标记，不处理补给或工资。

const HEALING_CONFIG_PATH: String = "res://Data/Combat/healing_config.tres"
## 与 TimeManager.REAL_SECONDS_PER_GAME_HOUR 保持一致；1x 下 2 世界秒 = 1 游戏小时。
const SECONDS_PER_GAME_HOUR: float = 2.0

## 上次完成治疗结算的游戏小时（从世界起点累计）。
## -1 表示尚未初始化：第一次 tick 只记录当前小时，不补发历史治疗。
var last_settled_hour: int = -1

var _party_manager: PartyManager = null
var _unit_manager: UnitManager = null
var _config: HealingConfig = null


func setup(
	party_manager: PartyManager,
	unit_manager: UnitManager,
	config: HealingConfig = null
) -> void:
	_party_manager = party_manager
	_unit_manager = unit_manager
	if config != null:
		_config = config
	elif _config == null:
		_config = _load_config()
	_config.sanitize()


func set_config(config: HealingConfig) -> void:
	_config = config if config != null else HealingConfig.new()
	_config.sanitize()


func get_healing_per_hour() -> int:
	if _config == null:
		return 0
	return _config.get_healing_per_hour()


## 当前游戏小时（与 TimeManager 的 6 秒/游戏小时一致）。
func get_current_hour() -> int:
	return int(floor(TimeManager.world_elapsed_seconds / SECONDS_PER_GAME_HOUR))


## 读档时按存档推进时间恢复结算点；缺失时以存档时刻为起点，避免补发历史治疗。
func restore_settled_hour(saved_hour: int, world_elapsed_seconds: float) -> void:
	if saved_hour >= 0:
		last_settled_hour = saved_hour
	else:
		last_settled_hour = int(floor(world_elapsed_seconds / SECONDS_PER_GAME_HOUR))


## 仅由 WorldSimulation 的 WorldTime tick 调用。
## 返回本次结算跨过的游戏小时数；0 表示本 tick 没有新的整小时。
func tick() -> int:
	var current_hour: int = get_current_hour()
	if last_settled_hour < 0:
		# 新世界/旧存档起点：只记录，不追溯历史。
		last_settled_hour = current_hour
		return 0
	if current_hour <= last_settled_hour:
		return 0

	var hours: int = current_hour - last_settled_hour
	last_settled_hour = current_hour
	var per_hour: int = get_healing_per_hour()
	if per_hour <= 0 or _party_manager == null:
		return hours

	var total_points: int = per_hour * hours
	for party: PartyData in _party_manager.get_all_parties():
		apply_healing_to_party(party, total_points)
	return hours


## 对单个部队按成员顺序应用治疗点数。
## 返回 { points_used, healed_unit_ids }，便于测试与日志。
func apply_healing_to_party(party: PartyData, points: int) -> Dictionary:
	var result := {
		"points_used": 0,
		"healed_unit_ids": [] as Array[String],
	}
	if party == null or points <= 0 or _unit_manager == null:
		return result
	# 战斗中的 HP 权威属于 BattleUnitState，结算前不在这里改写。
	if party.battle_state == PartyData.BattleState.IN_BATTLE:
		return result
	if party.member_unit_ids.is_empty():
		return result

	var remaining: int = points
	var used: int = 0
	var healed_ids: Array[String] = []
	for unit_id: String in party.member_unit_ids:
		if remaining <= 0:
			break
		var unit := _unit_manager.get_unit(unit_id)
		if unit == null or unit.is_dead():
			continue
		var missing: int = maxi(0, unit.max_hp - unit.current_hp)
		if missing <= 0:
			continue
		var applied: int = mini(remaining, missing)
		unit.current_hp += applied
		unit.clamp_hp()
		remaining -= applied
		used += applied
		healed_ids.append(unit_id)

	result["points_used"] = used
	result["healed_unit_ids"] = healed_ids

	# 仅剩伤兵而被禁用的部队，在出现可战斗成员后恢复世界行动。
	if used > 0 and party.battle_state == PartyData.BattleState.DISABLED \
			and _has_active_member(party):
		party.battle_state = PartyData.BattleState.AVAILABLE
		EventBus.party_battle_state_changed.emit(
			party.party_id, int(party.battle_state)
		)
	return result


func _has_active_member(party: PartyData) -> bool:
	for unit_id: String in party.member_unit_ids:
		var unit := _unit_manager.get_unit(unit_id)
		if unit != null and unit.is_alive():
			return true
	return false


func _load_config() -> HealingConfig:
	if ResourceLoader.exists(HEALING_CONFIG_PATH):
		var loaded := load(HEALING_CONFIG_PATH) as HealingConfig
		if loaded != null:
			# 每个管理器持有独立副本，允许测试/未来药物系统调整而不污染全局资源。
			var copy := loaded.duplicate(true) as HealingConfig
			if copy != null:
				return copy
	return HealingConfig.new()
