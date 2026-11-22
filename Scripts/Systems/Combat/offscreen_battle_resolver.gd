class_name OffscreenBattleResolver
extends RefCounted
## 离屏 AI 对 AI 战斗的小时结算器。
##
## 每调用一次 settle_hour() 结算一个游戏小时：
## 1. 根据双方存活单位的攻击、最大生命、兵种等级、骑乘状态与剩余生命计算战力；
## 2. 按“敌方战力占双方总战力”的比例换算伤亡比例，并加入随机波动；
## 3. 伤亡人数按小数累计，避免小部队每小时被迫固定损失一人；
## 4. 战力较低的单位更可能被选中阵亡，等级/生命/骑乘会实际影响生存。
##
## 本类只修改 BattleUnitState，不写回 UnitData / PartyData；最终结算仍由
## BattleManager.finish_battle() 完成。

const MIN_UNIT_POWER: float = 0.01

var config: OffscreenBattleConfig = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func setup(battle_config: OffscreenBattleConfig) -> void:
	config = battle_config
	if config == null:
		config = OffscreenBattleConfig.new()
	reset_random()


func reset_random(seed_override: int = -1) -> void:
	var seed_value: int = seed_override
	if seed_value < 0 and config != null:
		seed_value = config.random_seed
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


## 结算一个游戏小时。返回：
## { "casualties": { side_index: int }, "living_by_side": { side_index: int } }
func settle_hour(session: BattleSession, unit_manager: UnitManager) -> Dictionary:
	var result: Dictionary = {
		"casualties": {},
		"living_by_side": {},
	}
	if session == null or unit_manager == null or config == null:
		return result

	var living_by_side: Dictionary = _collect_living(session)
	var power_by_side: Dictionary = {}
	for side_index: int in session.get_side_indices():
		var states: Array = living_by_side.get(side_index, [])
		var total_power: float = 0.0
		for state_value: Variant in states:
			total_power += _unit_power(state_value as BattleUnitState, unit_manager)
		power_by_side[side_index] = total_power
		result["living_by_side"][side_index] = states.size()

	var casualties_by_side: Dictionary = {}
	for side_index: int in session.get_side_indices():
		var states: Array = living_by_side.get(side_index, [])
		if states.is_empty():
			casualties_by_side[side_index] = 0
			continue

		var own_power: float = float(power_by_side.get(side_index, 0.0))
		var enemy_power: float = 0.0
		for other_side: int in session.get_side_indices():
			if other_side == side_index:
				continue
			enemy_power += float(power_by_side.get(other_side, 0.0))

		var pressure_ratio: float = 0.5
		if own_power + enemy_power > 0.0:
			pressure_ratio = enemy_power / (own_power + enemy_power)
		var pressure_factor: float = clampf(
			pressure_ratio * config.pressure_scale,
			config.min_pressure_factor,
			config.max_pressure_factor
		)
		var variance: float = _rng.randf_range(
			1.0 - config.casualty_variance,
			1.0 + config.casualty_variance
		)
		var fraction: float = clampf(
			config.base_hourly_casualty_fraction * pressure_factor * variance,
			0.0,
			config.max_hourly_casualty_fraction
		)

		# 用小数累计伤亡，避免 20 人部队每小时都必须损失至少 1 人的固定节奏。
		var credit_key: Variant = side_index
		var credit: float = float(
			session.offscreen_casualty_credit.get(credit_key, 0.0)
		)
		credit += float(states.size()) * fraction
		var casualty_count: int = int(floor(credit))
		if casualty_count >= states.size():
			casualty_count = states.size()
			credit = 0.0
		else:
			credit -= float(casualty_count)
		session.offscreen_casualty_credit[credit_key] = credit

		var victims: Array = _select_victims(states, casualty_count, unit_manager)
		for victim_value: Variant in victims:
			var victim := victim_value as BattleUnitState
			if victim == null:
				continue
			victim.battle_hp = 0
			victim.alive = false
		casualties_by_side[side_index] = victims.size()

	result["casualties"] = casualties_by_side
	result["living_by_side"] = _count_living_by_side(session)
	return result


## 当前存活战斗侧数量。只有至少存在一名存活单位的战斗侧才计入。
## 例如 A 方 0 人、B 方 5 人时应返回 1，而不是统计字典的条目数 2。
func count_living_sides(session: BattleSession) -> int:
	if session == null:
		return 0
	var count: int = 0
	for side_index: int in session.get_side_indices():
		for unit_id: String in session.get_side_unit_ids(side_index):
			var state := session.get_unit_state(unit_id)
			if state != null and state.alive and state.battle_hp > 0:
				count += 1
				break
	return count


## 达到安全上限时按剩余战力选择获胜侧；返回 -1 表示平局。
func get_strongest_living_side(
	session: BattleSession, unit_manager: UnitManager
) -> int:
	var living_by_side: Dictionary = _collect_living(session)
	var best_side: int = -1
	var best_power: float = -1.0
	var tied: bool = false
	for side_index: int in session.get_side_indices():
		var states: Array = living_by_side.get(side_index, [])
		if states.is_empty():
			continue
		var total_power: float = 0.0
		for state_value: Variant in states:
			total_power += _unit_power(state_value as BattleUnitState, unit_manager)
		if total_power > best_power + 0.001:
			best_power = total_power
			best_side = side_index
			tied = false
		elif absf(total_power - best_power) <= 0.001:
			tied = true
	return -1 if tied else best_side


func get_side_power(
	session: BattleSession, unit_manager: UnitManager, side_index: int
) -> float:
	var total_power: float = 0.0
	for unit_id: String in session.get_side_unit_ids(side_index):
		var state := session.get_unit_state(unit_id)
		if state != null and state.alive and state.battle_hp > 0:
			total_power += _unit_power(state, unit_manager)
	return total_power


func _collect_living(session: BattleSession) -> Dictionary:
	var result: Dictionary = {}
	for side_index: int in session.get_side_indices():
		var states: Array = []
		for unit_id: String in session.get_side_unit_ids(side_index):
			var state := session.get_unit_state(unit_id)
			if state != null and state.alive and state.battle_hp > 0:
				states.append(state)
		result[side_index] = states
	return result


func _count_living_by_side(session: BattleSession) -> Dictionary:
	var counts: Dictionary = {}
	for side_index: int in session.get_side_indices():
		var count: int = 0
		for unit_id: String in session.get_side_unit_ids(side_index):
			var state := session.get_unit_state(unit_id)
			if state != null and state.alive and state.battle_hp > 0:
				count += 1
		counts[side_index] = count
	return counts


func _unit_power(state: BattleUnitState, unit_manager: UnitManager) -> float:
	if state == null or unit_manager == null:
		return MIN_UNIT_POWER
	var unit := unit_manager.get_unit(state.unit_id)
	if unit == null:
		return MIN_UNIT_POWER

	var unit_config := unit_manager.get_unit_config(unit.config_id)
	var tier: int = unit_config.tier if unit_config != null else 1
	var tier_multiplier: float = 1.0 + float(maxi(tier - 1, 0)) \
		* config.tier_power_bonus_per_level
	var mounted_multiplier: float = (
		1.0 + config.mounted_power_bonus if unit.is_mounted else 1.0
	)
	var hp_ratio: float = 1.0
	if unit.max_hp > 0:
		hp_ratio = clampf(float(state.battle_hp) / float(unit.max_hp), 0.0, 1.0)
	var raw_power: float = (
		float(unit.attack) * config.attack_power_weight
		+ float(unit.max_hp) * config.hp_power_weight
	)
	return maxf(
		MIN_UNIT_POWER,
		raw_power * tier_multiplier * mounted_multiplier * hp_ratio
	)


## 优先让战力较低的单位阵亡；随机权重保留波动，不会每次固定同一批人。
func _select_victims(
	states: Array, count: int, unit_manager: UnitManager
) -> Array:
	var victims: Array = []
	if count <= 0:
		return victims
	var pool: Array = states.duplicate()
	var clamped_count: int = mini(count, pool.size())
	for i: int in range(clamped_count):
		var weights: Array[float] = []
		var total_weight: float = 0.0
		for state_value: Variant in pool:
			var power: float = _unit_power(state_value as BattleUnitState, unit_manager)
			var weight: float = 1.0 / maxf(power, MIN_UNIT_POWER)
			weights.append(weight)
			total_weight += weight
		var roll: float = _rng.randf() * total_weight
		var selected_index: int = pool.size() - 1
		var accumulated: float = 0.0
		for index: int in range(pool.size()):
			accumulated += weights[index]
			if roll <= accumulated:
				selected_index = index
				break
		victims.append(pool[selected_index])
		pool.remove_at(selected_index)
	return victims
