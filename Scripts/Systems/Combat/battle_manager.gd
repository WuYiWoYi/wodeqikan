class_name BattleManager
extends RefCounted
## 战斗会话与战斗结算的统一入口。
##
## 支持双方与多方战斗：
## - 每个参战部队是一个 BattleParticipant，拥有 side_index；
## - side_index 相同为友军，不同侧互为敌人；
## - 屏幕战斗暂停世界并进入 BattleScene；
## - 离屏战斗保持世界运行，每游戏小时结算一次伤亡，期间允许第三方加入。
##
## 战斗期间 HP 的唯一权威是 BattleUnitState，结算时统一写回 UnitData。

const JOIN_RADIUS: float = 60.0
const OFFSCREEN_CONFIG_PATH: String = "res://Data/Combat/offscreen_battle_default.tres"

## 战斗经验与奖励集中配置。
const EXP_SURVIVAL_BASE: int = 10
const EXP_WIN_BONUS: int = 20
const VICTORY_GOLD_BASE: int = 50
const GOLD_PER_ENEMY_CASUALTY: int = 5
const MAX_LOOT_ITEMS: int = 3

var current_battle: BattleSession = null
var player_party_id: String = ""
var player_profile: PlayerProfile = null
## 离屏战斗小时结算参数；可由测试或后续配置替换。
var offscreen_config: OffscreenBattleConfig = null
var offscreen_resolver: OffscreenBattleResolver = null

var _unit_manager: UnitManager = null
var _party_manager: PartyManager = null
var _id_generator: IdGenerator = null
var _faction_manager: FactionManager = null


func setup(
	unit_manager: UnitManager,
	party_manager: PartyManager,
	id_generator: IdGenerator,
	faction_manager: FactionManager = null,
	profile: PlayerProfile = null
) -> void:
	_unit_manager = unit_manager
	_party_manager = party_manager
	_id_generator = id_generator
	_faction_manager = faction_manager
	player_profile = profile

	if offscreen_config == null:
		offscreen_config = _load_offscreen_config()
	offscreen_resolver = OffscreenBattleResolver.new()
	offscreen_resolver.setup(offscreen_config)


## 替换离屏战斗参数；已开始的战斗不会回溯修改已完成的小时结算。
func set_offscreen_config(config: OffscreenBattleConfig) -> void:
	offscreen_config = config if config != null else OffscreenBattleConfig.new()
	if offscreen_resolver == null:
		offscreen_resolver = OffscreenBattleResolver.new()
	offscreen_resolver.setup(offscreen_config)


func _load_offscreen_config() -> OffscreenBattleConfig:
	if ResourceLoader.exists(OFFSCREEN_CONFIG_PATH):
		var loaded := load(OFFSCREEN_CONFIG_PATH) as OffscreenBattleConfig
		if loaded != null:
			# 每个 BattleManager 使用独立副本，避免运行时调整参数污染全局资源缓存。
			var copy := loaded.duplicate(true) as OffscreenBattleConfig
			if copy != null:
				return copy
	return OffscreenBattleConfig.new()


func is_in_battle() -> bool:
	return current_battle != null


## 兼容旧双方调用。offscreen 为 true 时不停世界，用于 NPC 对 NPC 战斗。
func start_battle(
	attacker_party_ids: Array[String],
	defender_party_ids: Array[String],
	world_position: Vector2,
	offscreen: bool = false
) -> BattleSession:
	if attacker_party_ids.is_empty() or defender_party_ids.is_empty():
		push_warning("战斗双方不能为空")
		return null
	var sides: Array = [attacker_party_ids, defender_party_ids]
	return start_battle_by_sides(sides, world_position, offscreen)


## 以战斗侧列表创建战斗。sides[0] 为旧流程中的 attacker，sides[1] 为 defender。
func start_battle_by_sides(
	sides: Array, world_position: Vector2, offscreen: bool = false
) -> BattleSession:
	if current_battle != null:
		push_warning("已有进行中的战斗，拒绝重复开始")
		return null
	if _unit_manager == null or _party_manager == null or _id_generator == null:
		push_error("BattleManager 尚未装配")
		return null
	if sides.size() < 2:
		push_warning("战斗至少需要两个战斗侧")
		return null

	var seen: Dictionary = {}
	var all_parties: Array[PartyData] = []
	var side_parties: Array = []
	for side_value: Variant in sides:
		if not side_value is Array:
			return null
		var party_ids: Array = side_value
		if party_ids.is_empty():
			push_warning("战斗侧不能为空")
			return null
		var parties := _collect_parties_from_values(party_ids)
		if parties.size() != party_ids.size():
			return null
		for party: PartyData in parties:
			if seen.has(party.party_id):
				push_warning("同一部队不能重复参战: %s" % party.party_id)
				return null
			seen[party.party_id] = true
			if not party.is_available_for_world():
				push_warning("部队不可参战: %s" % party.party_id)
				return null
			if _count_living_units(party) == 0:
				push_warning("部队没有存活士兵: %s" % party.party_id)
				return null
			all_parties.append(party)
		if not _validate_side_relations(parties):
			return null
		side_parties.append(parties)

	if all_parties.is_empty() or _all_same_faction(all_parties):
		push_warning("战斗双方阵营相同，拒绝开始")
		return null

	var player_involved: bool = _contains_player(all_parties)
	if player_involved:
		offscreen = false

	var session := BattleSession.new()
	session.battle_id = _id_generator.next_id(IdGenerator.BATTLE)
	session.world_position = world_position
	session.offscreen = offscreen
	session.player_involved = player_involved
	session.status = BattleSession.Status.ACTIVE
	session.attacker_faction_id = (side_parties[0][0] as PartyData).faction_id
	session.defender_faction_id = (side_parties[1][0] as PartyData).faction_id

	for side_index: int in range(side_parties.size()):
		var parties: Array = side_parties[side_index]
		for party: PartyData in parties:
			session.add_participant(party.party_id, party.faction_id, side_index)
			_add_party_units(session, party)
		if session.get_side_unit_ids(side_index).is_empty():
			push_warning("战斗侧没有有效士兵")
			return null

	current_battle = session
	for party: PartyData in all_parties:
		_lock_party(party)

	if not offscreen:
		TimeManager.push_pause(GameManager.PAUSE_REASON_BATTLE)
		session.paused_world = true
	elif offscreen_resolver != null:
		# 每场离屏战斗重置随机源；配置固定 seed 时便于自动化复现。
		offscreen_resolver.reset_random()

	EventBus.battle_started.emit(session.battle_id)
	return session


## 离屏战斗按世界时间推进；由 WorldSimulation 每个 world_tick 调用。
## 每满 1 个游戏小时结算一次伤亡；屏幕战斗（offscreen = false）完全跳过。
func tick(world_delta: float) -> void:
	var session := current_battle
	if session == null or session.status == BattleSession.Status.ENDED:
		return
	if not session.offscreen or world_delta <= 0.0:
		return

	session.elapsed_world_seconds += world_delta
	session.offscreen_settlement_accumulator += world_delta
	var interval: float = _get_offscreen_interval()
	var settled_this_tick: bool = false

	while session.offscreen_settlement_accumulator + 0.0001 >= interval:
		if current_battle != session or not session.offscreen:
			return
		session.offscreen_settlement_accumulator -= interval
		_settle_offscreen_hour(session)
		settled_this_tick = true
		if _try_finish_offscreen_battle(session, false):
			return
		if session.offscreen_settlements_done >= _get_max_offscreen_hours():
			_try_finish_offscreen_battle(session, true)
			return

	if settled_this_tick:
		# 事件在最后一次小时结算后、战斗未结束时广播；若已结束由 battle_finished 通知。
		EventBus.battle_participants_updated.emit(session.battle_id)

	# 安全上限：长期无法分出胜负时按剩余战力结算。
	if session.offscreen_settlements_done >= _get_max_offscreen_hours():
		_try_finish_offscreen_battle(session, true)


## 测试/调试入口：连续推进小时结算，直到战斗结束或达到安全上限。
func resolve_current_battle_now() -> bool:
	var session := current_battle
	if session == null or not session.offscreen:
		return false
	var guard: int = 0
	while current_battle == session and session.offscreen:
		_settle_offscreen_hour(session)
		if _try_finish_offscreen_battle(session, false):
			return true
		guard += 1
		if guard >= _get_max_offscreen_hours():
			return _try_finish_offscreen_battle(session, true)
	return false


func _settle_offscreen_hour(session: BattleSession) -> void:
	if offscreen_resolver == null:
		return
	session.offscreen_settlements_done += 1
	offscreen_resolver.settle_hour(session, _unit_manager)
	# 每小时伤亡立即从部队成员列表移除，使世界数据中的兵力随战斗变化；
	# UnitData 保留到最终结算，避免提前丢失战利品与阵亡事件。
	_remove_offscreen_dead_from_parties(session)


func _remove_offscreen_dead_from_parties(session: BattleSession) -> void:
	if _party_manager == null or _unit_manager == null:
		return
	for value: Variant in session.unit_states.values():
		var state := value as BattleUnitState
		if state == null or (state.alive and state.battle_hp > 0):
			continue
		var unit := _unit_manager.get_unit(state.unit_id)
		if unit == null or unit.current_party_id.is_empty():
			continue
		_party_manager.remove_member(unit.current_party_id, state.unit_id)


func _get_offscreen_interval() -> float:
	if offscreen_config != null \
			and offscreen_config.settlement_interval_world_seconds > 0.0:
		return offscreen_config.settlement_interval_world_seconds
	return TimeManager.REAL_SECONDS_PER_GAME_HOUR


func _get_max_offscreen_hours() -> int:
	if offscreen_config != null:
		return maxi(1, offscreen_config.max_settlement_hours)
	return 48


## 返回是否已结算。force = true 时按剩余战力在安全上限强制分出胜负。
func _try_finish_offscreen_battle(
	session: BattleSession, force: bool
) -> bool:
	var living_count: int = offscreen_resolver.count_living_sides(session) \
		if offscreen_resolver != null else 0
	var winner: int = -1
	var should_finish: bool = false

	if living_count <= 1:
		should_finish = true
		if living_count == 1:
			for side_index: int in session.get_side_indices():
				var has_living: bool = false
				for unit_id: String in session.get_side_unit_ids(side_index):
					var state := session.get_unit_state(unit_id)
					if state != null and state.alive and state.battle_hp > 0:
						has_living = true
						break
				if has_living:
					winner = side_index
					break
	elif force:
		should_finish = true
		winner = offscreen_resolver.get_strongest_living_side(
			session, _unit_manager
		) if offscreen_resolver != null else -1

	if not should_finish:
		return false

	session.winning_side_index = winner
	return finish_battle(session.battle_id, _result_for_winning_side(winner))


func _result_for_winning_side(
	winning_side: int
) -> BattleSession.BattleResult:
	if winning_side < 0:
		return BattleSession.BattleResult.DRAW
	if winning_side == 0:
		return BattleSession.BattleResult.ATTACKER_VICTORY
	if winning_side == 1:
		return BattleSession.BattleResult.DEFENDER_VICTORY
	return BattleSession.BattleResult.SIDE_VICTORY


## 结算战斗：写回 HP、移除阵亡单位、解锁部队、清理会话和时间状态。
## 重复调用或 battle_id 不匹配时返回 false，不重复结算。
func finish_battle(battle_id: String, result: int) -> bool:
	var session := current_battle
	if session == null:
		push_warning("没有进行中的战斗可结算")
		return false
	if session.battle_id != battle_id:
		push_warning("战斗 ID 不匹配: %s" % battle_id)
		return false
	if session.status == BattleSession.Status.ENDED:
		return false

	session.status = BattleSession.Status.ENDED
	session.result = int(result) as BattleSession.BattleResult
	match session.result:
		BattleSession.BattleResult.ATTACKER_VICTORY:
			session.winning_side_index = 0
		BattleSession.BattleResult.DEFENDER_VICTORY:
			session.winning_side_index = 1
		BattleSession.BattleResult.SIDE_VICTORY:
			pass
		_:
			session.winning_side_index = -1

	# 先基于战斗中的临时状态生成结果并应用经验/奖励，再移除阵亡单位。
	var result_data := build_battle_result(session, session.result, true)
	result_data.finalized = true
	session.final_result = result_data

	_settle_session(session)
	_unlock_session_parties(session)
	current_battle = null

	if session.paused_world:
		TimeManager.pop_pause(GameManager.PAUSE_REASON_BATTLE)
		session.paused_world = false
	EventBus.battle_finished.emit(battle_id, int(session.result))
	return true


## 生成统一战斗结果。apply = false 用于结果面板预览；apply = true 会发放经验/奖励。
func build_battle_result(
	session: BattleSession,
	result: int,
	apply: bool = false
) -> BattleResultData:
	var data := BattleResultData.new()
	if session == null:
		return data

	data.battle_id = session.battle_id
	data.result_code = int(result)
	data.player_involved = session.player_involved
	data.result_time = TimeManager.world_elapsed_seconds
	data.side_party_ids = session.side_party_ids.duplicate(true)
	data.retreated_side_indices = session.retreated_side_indices.duplicate()
	data.winning_side_index = session.winning_side_index
	data.player_side_index = session.get_side_of_party(player_party_id) \
		if not player_party_id.is_empty() else -1

	var battle_result := int(result) as BattleSession.BattleResult
	match battle_result:
		BattleSession.BattleResult.RETREATED:
			data.end_reason = BattleResultData.EndReason.RETREAT
		BattleSession.BattleResult.ABORTED:
			data.end_reason = BattleResultData.EndReason.ABORTED
		BattleSession.BattleResult.DRAW:
			data.end_reason = BattleResultData.EndReason.DRAW
		_:
			data.end_reason = BattleResultData.EndReason.ANNIHILATION

	if data.winning_side_index >= 0:
		for side_index: int in session.get_side_indices():
			if side_index != data.winning_side_index:
				data.losing_side_indices.append(side_index)

	var win_bonus_applies: bool = data.winning_side_index >= 0 \
		and battle_result != BattleSession.BattleResult.ABORTED \
		and battle_result != BattleSession.BattleResult.RETREATED \
		and battle_result != BattleSession.BattleResult.DRAW

	# 参战部队快照与伤亡。
	for participant_value: Variant in session.participants.values():
		var participant := participant_value as BattleParticipant
		if participant == null:
			continue
		data.participants.append({
			"party_id": participant.party_id,
			"faction_id": participant.faction_id,
			"side_index": participant.side_index,
			"status": int(participant.status),
		})
		var party_casualties: int = 0
		var party_survivors: int = 0
		for unit_id: String in session.get_party_unit_ids(participant.party_id):
			var state := session.get_unit_state(unit_id)
			if state == null:
				continue
			if state.alive and state.battle_hp > 0:
				party_survivors += 1
			else:
				party_casualties += 1
		data.casualties[participant.party_id] = party_casualties
		data.survivors[participant.party_id] = party_survivors

	# 经验：存活单位获得基础经验，获胜侧额外奖励；中止战斗不发放。
	if battle_result != BattleSession.BattleResult.ABORTED:
		for participant_value: Variant in session.participants.values():
			var participant := participant_value as BattleParticipant
			if participant == null:
				continue
			var party_exp: int = 0
			for unit_id: String in session.get_party_unit_ids(participant.party_id):
				var state := session.get_unit_state(unit_id)
				if state == null or not state.alive or state.battle_hp <= 0:
					continue
				var amount: int = EXP_SURVIVAL_BASE
				if win_bonus_applies and participant.side_index == data.winning_side_index:
					amount += EXP_WIN_BONUS
				data.exp_gained_by_unit[unit_id] = amount
				party_exp += amount
				if participant.party_id == player_party_id:
					data.player_exp_gained += amount
				if apply:
					_unit_manager.add_exp(unit_id, amount)
			data.exp_gained_by_party[participant.party_id] = party_exp

	# 奖励：仅玩家参与且玩家所在侧获胜时发放。
	data.player_won = data.player_involved and data.player_side_index >= 0 \
		and data.player_side_index == data.winning_side_index
	if data.player_won and win_bonus_applies:
		var enemy_casualties: int = 0
		for party_id: String in data.casualties:
			var participant := session.get_participant(party_id)
			if participant != null and participant.side_index != data.winning_side_index:
				enemy_casualties += int(data.casualties[party_id])
		data.reward_gold = VICTORY_GOLD_BASE + enemy_casualties * GOLD_PER_ENEMY_CASUALTY

		var seen_items: Dictionary = {}
		for participant_value: Variant in session.participants.values():
			var participant := participant_value as BattleParticipant
			if participant == null or participant.side_index == data.winning_side_index:
				continue
			for unit_id: String in session.get_party_unit_ids(participant.party_id):
				var state := session.get_unit_state(unit_id)
				if state != null and (not state.alive or state.battle_hp <= 0):
					var unit := _unit_manager.get_unit(unit_id)
					if unit == null:
						continue
					for equipment_value: Variant in unit.equipment.values():
						var item_id: String = str(equipment_value)
						if item_id.is_empty() or seen_items.has(item_id):
							continue
						seen_items[item_id] = true
						data.reward_items.append(item_id)
						if data.reward_items.size() >= MAX_LOOT_ITEMS:
							break
					if data.reward_items.size() >= MAX_LOOT_ITEMS:
						break
			if data.reward_items.size() >= MAX_LOOT_ITEMS:
				break

		if apply and player_profile != null:
			player_profile.add_gold(data.reward_gold)
			for item_id: String in data.reward_items:
				player_profile.add_item(item_id)

	return data


## 主动撤退一个战斗侧。屏幕战斗由 BattleScene 显示结果后统一结算；
## 离屏战斗直接结算为 RETREATED。
func retreat_side(side_index: int) -> bool:
	var session := current_battle
	if session == null or session.status == BattleSession.Status.ENDED:
		return false
	if not session.get_side_indices().has(side_index):
		return false
	if not session.retreated_side_indices.has(side_index):
		session.retreated_side_indices.append(side_index)
	for party_id: String in session.get_side_party_ids(side_index):
		var participant := session.get_participant(party_id)
		if participant != null:
			participant.status = BattleParticipant.Status.WITHDRAWN
	if not session.player_involved:
		return finish_battle(session.battle_id, BattleSession.BattleResult.RETREATED)
	return true


func abort_battle(battle_id: String) -> bool:
	return finish_battle(battle_id, BattleSession.BattleResult.ABORTED)


func add_reinforcement(party_id: String, battle_id: String) -> bool:
	if current_battle == null or current_battle.battle_id != battle_id:
		return false
	return try_join_battle(party_id)


## 仅根据阵营关系决定新部队应加入哪个战斗侧。
## 返回 -1 表示不应加入；返回当前不存在的 side 索引表示建立新的第三方战斗侧。
func get_join_side(party_id: String) -> int:
	var session := current_battle
	if session == null or session.status == BattleSession.Status.ENDED:
		return -1
	if session.is_party_involved(party_id):
		return -1
	var party := _party_manager.get_party(party_id) if _party_manager != null else null
	if party == null or not party.is_available_for_world():
		return -1
	if _count_living_units(party) == 0:
		return -1
	if _faction_manager == null:
		return -1

	var hostile_exists: bool = false
	var candidate_sides: Array[int] = []
	for side_index: int in session.get_side_indices():
		var has_hostile: bool = false
		for other_id: String in session.get_side_party_ids(side_index):
			var other := _party_manager.get_party(other_id)
			if other != null and _faction_manager.is_hostile(
				party.faction_id, other.faction_id
			):
				has_hostile = true
				hostile_exists = true
		if not has_hostile:
			candidate_sides.append(side_index)

	if not hostile_exists:
		# 与任何参战方都没有敌对关系：中立部队不能自动参战。
		return -1
	if candidate_sides.is_empty():
		# 与现有所有战斗侧都敌对：建立独立第三方。
		return session.get_next_side_index()

	# 优先加入有友军的战斗侧；同分时取更早的战斗侧。
	var best_side: int = candidate_sides[0]
	var best_friendly: int = -1
	for side_index: int in candidate_sides:
		var friendly_count: int = 0
		for other_id: String in session.get_side_party_ids(side_index):
			var other := _party_manager.get_party(other_id)
			if other != null and _faction_manager.is_friendly(
				party.faction_id, other.faction_id
			):
				friendly_count += 1
		if friendly_count > best_friendly:
			best_friendly = friendly_count
			best_side = side_index
	return best_side


func can_party_join(party_id: String) -> bool:
	var session := current_battle
	if session == null:
		return false
	var party := _party_manager.get_party(party_id) if _party_manager != null else null
	if party == null:
		return false
	if party.world_position.distance_to(session.world_position) > JOIN_RADIUS:
		return false
	return get_join_side(party_id) >= 0


## 尝试把部队加入当前战斗。成功会把部队切换为 IN_BATTLE。
func try_join_battle(party_id: String) -> bool:
	var session := current_battle
	if session == null or session.status == BattleSession.Status.ENDED:
		return false
	var party := _party_manager.get_party(party_id) if _party_manager != null else null
	if party == null or not party.is_available_for_world():
		return false
	if party.world_position.distance_to(session.world_position) > JOIN_RADIUS:
		return false

	var side_index: int = get_join_side(party_id)
	if side_index < 0:
		return false
	if _count_living_units(party) == 0:
		return false

	var participant: BattleParticipant = session.add_participant(
		party_id, party.faction_id, side_index
	)
	if participant == null:
		return false
	_add_party_units(session, party)
	_lock_party(party)

	if party_id == player_party_id:
		session.player_involved = true
		_ensure_screen_battle(session)

	EventBus.battle_participant_joined.emit(
		session.battle_id, party_id, participant.side_index
	)
	return true


# ---------------------------------------------------------------------------
# 内部实现
# ---------------------------------------------------------------------------


func _collect_parties_from_values(party_ids: Array) -> Array[PartyData]:
	var result: Array[PartyData] = []
	for value: Variant in party_ids:
		var party_id: String = str(value)
		var party := _party_manager.get_party(party_id)
		if party == null:
			push_warning("参战部队不存在: %s" % party_id)
			continue
		result.append(party)
	return result


func _validate_side_relations(parties: Array) -> bool:
	if _faction_manager == null:
		return true
	for i: int in range(parties.size()):
		for j: int in range(i + 1, parties.size()):
			var a := parties[i] as PartyData
			var b := parties[j] as PartyData
			if a != null and b != null \
					and _faction_manager.is_hostile(a.faction_id, b.faction_id):
				push_warning("敌对阵营不能处于同一战斗侧: %s / %s" % [a.party_id, b.party_id])
				return false
	return true


func _all_same_faction(parties: Array[PartyData]) -> bool:
	if parties.is_empty():
		return true
	var faction_id: String = parties[0].faction_id
	for party: PartyData in parties:
		if party.faction_id != faction_id:
			return false
	return true


func _contains_player(parties: Array[PartyData]) -> bool:
	if player_party_id.is_empty():
		return false
	for party: PartyData in parties:
		if party.party_id == player_party_id:
			return true
	return false


func _count_living_units(party: PartyData) -> int:
	if party == null:
		return 0
	var count: int = 0
	for unit_id: String in party.member_unit_ids:
		var unit := _unit_manager.get_unit(unit_id)
		if unit != null and unit.is_alive():
			count += 1
	return count


func _add_party_units(session: BattleSession, party: PartyData) -> int:
	var participant: BattleParticipant = session.get_participant(party.party_id)
	if participant == null:
		return 0
	var added: int = 0
	for unit_id: String in party.member_unit_ids:
		if session.unit_states.has(unit_id):
			continue
		var unit := _unit_manager.get_unit(unit_id)
		if unit == null or not unit.is_alive():
			continue
		var state := BattleUnitState.new()
		state.unit_id = unit_id
		state.party_id = party.party_id
		state.battle_hp = unit.current_hp
		state.alive = true
		session.add_unit_state(state)
		added += 1
	return added


func _lock_party(party: PartyData) -> void:
	if party == null:
		return
	party.battle_state = PartyData.BattleState.IN_BATTLE
	party.movement_state = PartyData.MovementState.IDLE
	party.target_position = party.world_position
	party.current_order = PartyData.OrderType.NONE
	party.current_target_id = ""
	party.attack_intent = false
	EventBus.party_battle_state_changed.emit(party.party_id, int(party.battle_state))


func _ensure_screen_battle(session: BattleSession) -> void:
	if session.offscreen:
		session.offscreen = false
	if not session.paused_world:
		TimeManager.push_pause(GameManager.PAUSE_REASON_BATTLE)
		session.paused_world = true


func _settle_session(session: BattleSession) -> void:
	for value: Variant in session.unit_states.values():
		var state := value as BattleUnitState
		if state == null:
			continue
		var unit := _unit_manager.get_unit(state.unit_id)
		if unit == null:
			continue

		var final_hp: int = clampi(state.battle_hp, 0, unit.max_hp)
		if not state.alive or final_hp <= 0:
			state.alive = false
			state.battle_hp = 0
			unit.current_hp = 0
			_destroy_dead_unit(state)
		else:
			unit.current_hp = final_hp


## 阵亡单位不能继续作为部队正常成员保留。
## 先经 PartyManager 移除归属，再删除 UnitData，避免留下悬空成员 ID。
func _destroy_dead_unit(state: BattleUnitState) -> void:
	_party_manager.remove_member(state.party_id, state.unit_id)

	var unit := _unit_manager.get_unit(state.unit_id)
	if unit != null and not unit.current_party_id.is_empty():
		_party_manager.remove_member(unit.current_party_id, state.unit_id)

	if not _unit_manager.remove_unit(state.unit_id):
		push_error("无法移除阵亡单位: %s" % state.unit_id)
	EventBus.unit_died.emit(state.unit_id, state.party_id)


func _unlock_session_parties(session: BattleSession) -> void:
	for party_id: String in session.get_all_party_ids():
		var party := _party_manager.get_party(party_id)
		if party == null:
			continue
		# 全员阵亡的部队不再参与世界模拟，也停止大地图 AI。
		if party.member_unit_ids.is_empty():
			party.battle_state = PartyData.BattleState.DISABLED
		else:
			party.battle_state = PartyData.BattleState.AVAILABLE
		party.movement_state = PartyData.MovementState.IDLE
		party.target_position = party.world_position
		party.current_target_id = ""
		party.current_order = PartyData.OrderType.NONE
		party.attack_intent = false
		EventBus.party_battle_state_changed.emit(party.party_id, int(party.battle_state))
