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
## 负伤概率配置；由 WorldContext 注入。未注入时按永久死亡处理（测试默认）。
const WOUNDED_CONFIG_PATH: String = "res://Data/Combat/wounded_config.tres"
## 战斗结束后存活部队的禁止再战时间（世界秒）。
## 避免双方刚解锁就因仍在接触范围内而立刻重新开战，导致看似卡死。
const POST_BATTLE_ENGAGEMENT_COOLDOWN: float = 30.0

## 战斗经验与奖励集中配置。
const EXP_SURVIVAL_BASE: int = 10
const EXP_WIN_BONUS: int = 20
const VICTORY_GOLD_BASE: int = 50
const GOLD_PER_ENEMY_CASUALTY: int = 5
const MAX_LOOT_ITEMS: int = 3

## 玩家当前正在参与的屏幕战斗。AI 离屏战斗不写入此字段。
## 它不再代表世界上唯一的战斗；世界可同时存在多场战斗。
var current_battle: BattleSession = null
## 所有进行中的战斗：{ battle_id: BattleSession }。
var active_battles: Dictionary = {}
## 部队参战索引：{ party_id: battle_id }。每支部队同一时间只能参与一场战斗。
var party_battle_lookup: Dictionary = {}
var player_party_id: String = ""
var player_profile: PlayerProfile = null
## 离屏战斗小时结算参数；可由测试或后续配置替换。
var offscreen_config: OffscreenBattleConfig = null
## 离屏结算模板；每场离屏战斗实际使用独立的 Resolver 与随机序列。
var offscreen_resolver: OffscreenBattleResolver = null
## { battle_id: OffscreenBattleResolver }
var _offscreen_resolvers: Dictionary = {}
## 已结算但仍等待玩家确认接收的俘虏：{ battle_id: BattleSession }。
## 用 battle_id 唯一标识结算，确认后立即移除，防止重复提交。
var _pending_prisoner_settlements: Dictionary = {}

## 负伤概率的唯一配置入口；null 表示不启用负伤（阵亡即永久死亡）。
var wounded_config: WoundedConfig = null
## 负伤判定随机源；固定种子保证同一世界的结算可复现。
var _wounded_rng: RandomNumberGenerator = RandomNumberGenerator.new()

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
	# 固定初始种子：同一场战斗的判定可复现；测试可通过 set_wounded_rng_seed 覆盖。
	_wounded_rng.seed = 0x5A17C0DE


## 注入负伤概率配置；传入 null 时关闭负伤判定。
func set_wounded_config(config: WoundedConfig) -> void:
	wounded_config = config
	if wounded_config != null:
		wounded_config.sanitize()


## 测试用：重置负伤判定随机序列，保证概率采样可复现。
func set_wounded_rng_seed(seed_value: int) -> void:
	_wounded_rng.seed = seed_value


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


## 玩家是否正处于屏幕战斗中。
func is_in_battle() -> bool:
	return current_battle != null


## 世界中是否存在任意进行中的战斗（包括 AI 离屏战斗）。
func has_any_active_battles() -> bool:
	return not get_active_battles().is_empty()


## 按 ID 查询进行中的战斗；已结束或不存在时返回 null。
func get_battle(battle_id: String) -> BattleSession:
	var session := active_battles.get(battle_id) as BattleSession
	if session == null or session.status == BattleSession.Status.ENDED:
		return null
	return session


## 查询某支部队正在参与的战斗；未参战或战斗已结束时返回 null。
func get_battle_for_party(party_id: String) -> BattleSession:
	if party_id.is_empty():
		return null
	var battle_id: String = str(party_battle_lookup.get(party_id, ""))
	if battle_id.is_empty():
		return null
	var session := get_battle(battle_id)
	if session == null or not session.is_party_involved(party_id):
		party_battle_lookup.erase(party_id)
		return null
	return session


## 当前全部进行中的战斗（快照，已过滤结束会话）。
func get_active_battles() -> Array[BattleSession]:
	var sessions: Array[BattleSession] = []
	for value: Variant in active_battles.values():
		var session := value as BattleSession
		if session == null or session.status == BattleSession.Status.ENDED:
			continue
		sessions.append(session)
	sessions.sort_custom(func(a: BattleSession, b: BattleSession) -> bool:
		return a.battle_id < b.battle_id
	)
	return sessions


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
			if _is_party_in_battle(party.party_id):
				push_warning("部队已处于其他战斗中: %s" % party.party_id)
				return null
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
		# 玩家同一时间只能参与一场屏幕战斗。
		if current_battle != null:
			push_warning("玩家已处于屏幕战斗中，拒绝开始新的玩家战斗")
			return null
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

	active_battles[session.battle_id] = session
	for party: PartyData in all_parties:
		party_battle_lookup[party.party_id] = session.battle_id
		_lock_party(party)

	if player_involved:
		current_battle = session

	if not offscreen:
		TimeManager.push_pause(GameManager.PAUSE_REASON_BATTLE)
		session.paused_world = true
	else:
		# 每场离屏战斗使用独立 Resolver 与随机序列；固定 seed 时仍可复现。
		_create_offscreen_resolver(session.battle_id)

	EventBus.battle_started.emit(session.battle_id)
	return session


## 离屏战斗按世界时间推进；由 WorldSimulation 每个 world_tick 调用。
## 每满 1 个游戏小时结算一次伤亡；屏幕战斗（offscreen = false）完全跳过。
func tick(world_delta: float) -> void:
	if world_delta <= 0.0:
		return
	# 先取快照：结算过程中战斗可能结束并从 active_battles 删除，
	# 不得因此跳过其他战斗的本次推进。
	for session: BattleSession in get_active_battles():
		if session.offscreen:
			_tick_offscreen_battle(session, world_delta)


func _tick_offscreen_battle(session: BattleSession, world_delta: float) -> void:
	if session == null or session.status == BattleSession.Status.ENDED:
		return
	session.elapsed_world_seconds += world_delta
	session.offscreen_settlement_accumulator += world_delta
	var interval: float = _get_offscreen_interval()
	var settled_this_tick: bool = false

	while session.offscreen_settlement_accumulator + 0.0001 >= interval:
		if not _is_battle_active(session) or not session.offscreen:
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


## 测试/调试入口：推进全部离屏战斗直到结束或达到安全上限。
## 多场战斗时逐场独立结算，互不影响。
func resolve_current_battle_now() -> bool:
	var resolved_any: bool = false
	for session: BattleSession in get_active_battles():
		if not session.offscreen:
			continue
		resolved_any = true
		_resolve_offscreen_battle_now(session)
	return resolved_any


## 测试/调试入口：推进指定战斗直到结束或达到安全上限。
func resolve_battle_now(battle_id: String) -> bool:
	var session := get_battle(battle_id)
	if session == null or not session.offscreen:
		return false
	_resolve_offscreen_battle_now(session)
	return true


func _resolve_offscreen_battle_now(session: BattleSession) -> void:
	var guard: int = 0
	while _is_battle_active(session) and session.offscreen:
		_settle_offscreen_hour(session)
		if _try_finish_offscreen_battle(session, false):
			return
		guard += 1
		if guard >= _get_max_offscreen_hours():
			_try_finish_offscreen_battle(session, true)
			return


func _settle_offscreen_hour(session: BattleSession) -> void:
	var resolver: OffscreenBattleResolver = _get_offscreen_resolver(session.battle_id)
	if resolver == null:
		return
	session.offscreen_settlements_done += 1
	resolver.settle_hour(session, _unit_manager)
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
	var resolver: OffscreenBattleResolver = _get_offscreen_resolver(session.battle_id)
	var living_count: int = resolver.count_living_sides(session) \
		if resolver != null else 0
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
		winner = resolver.get_strongest_living_side(
			session, _unit_manager
		) if resolver != null else -1

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
	var session := get_battle(battle_id)
	if session == null:
		push_warning("没有可结算的战斗: %s" % battle_id)
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
	_claim_battle_prisoners(session, result_data)
	_unlock_session_parties(session)
	_remove_battle_registry(session)
	if current_battle == session:
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

	# 负伤判定必须先于结果统计；每场战斗只判定一次，预览与最终结算一致。
	_decide_wounded_outcomes(session)

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
		var party_wounded: int = 0
		var party_survivors: int = 0
		for unit_id: String in session.get_party_unit_ids(participant.party_id):
			var state := session.get_unit_state(unit_id)
			if state == null:
				continue
			if state.alive and state.battle_hp > 0:
				party_survivors += 1
			elif state.wounded:
				party_wounded += 1
			else:
				party_casualties += 1
		data.casualties[participant.party_id] = party_casualties
		data.wounded[participant.party_id] = party_wounded
		data.survivors[participant.party_id] = party_survivors

	# 阶段 13：战败方伤兵成为可分配俘虏，按真实参战人数分给胜利部队。
	# 预览与最终结算使用同一套稳定顺序，重复调用不会改变结果。
	if win_bonus_applies:
		_build_prisoner_allocation(session, data)

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
				# 伤兵仍保有装备，只有永久死亡的单位才掉落战利品。
				if state != null and (not state.alive or state.battle_hp <= 0) \
						and not state.wounded:
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
	if get_battle(battle_id) == null:
		return false
	return try_join_battle(party_id, battle_id)


## 仅根据阵营关系决定新部队应加入哪一场指定战斗的哪个战斗侧。
## battle_id 必须显式指定，禁止在多场战斗环境下猜测目标战斗。
##
## 返回 -1 表示不应加入。只有“存在敌对侧且至少有一个非敌对侧”时才允许协助；
## 与所有战斗侧都敌对时不再自动创建第三方，避免 AI 任性卷入多方混战。
func get_join_side(party_id: String, battle_id: String) -> int:
	var session := get_battle(battle_id)
	if session == null:
		return -1
	if session.is_party_involved(party_id):
		return -1
	# 已经在其他战斗中的部队不能加入本场战斗。
	if _is_party_in_battle(party_id):
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
			if other != null and _faction_manager.is_party_hostile(
				party.party_id, other.party_id
			):
				has_hostile = true
				hostile_exists = true
		if not has_hostile:
			candidate_sides.append(side_index)

	if not hostile_exists:
		# 与任何参战方都没有敌对关系：中立部队不能自动参战。
		return -1
	if candidate_sides.is_empty():
		# 与现有所有战斗侧都敌对：不允许以“协助其中一方”的方式加入，
		# 也不再自动创建第三方战斗侧。
		return -1

	# 优先加入有友军的战斗侧；同分时取更早的战斗侧。
	var best_side: int = candidate_sides[0]
	var best_friendly: int = -1
	for side_index: int in candidate_sides:
		var friendly_count: int = 0
		for other_id: String in session.get_side_party_ids(side_index):
			var other := _party_manager.get_party(other_id)
			if other != null and _faction_manager.is_party_friendly(
				party.party_id, other.party_id
			):
				friendly_count += 1
		if friendly_count > best_friendly:
			best_friendly = friendly_count
			best_side = side_index
	return best_side


func can_party_join(party_id: String, battle_id: String) -> bool:
	var session := get_battle(battle_id)
	if session == null:
		return false
	var party := _party_manager.get_party(party_id) if _party_manager != null else null
	if party == null:
		return false
	if party.world_position.distance_to(session.world_position) > JOIN_RADIUS:
		return false
	return get_join_side(party_id, battle_id) >= 0


## 尝试把部队加入指定战斗。成功会把部队切换为 IN_BATTLE。
func try_join_battle(party_id: String, battle_id: String) -> bool:
	var session := get_battle(battle_id)
	if session == null:
		return false
	var party := _party_manager.get_party(party_id) if _party_manager != null else null
	if party == null or not party.is_available_for_world():
		return false
	if party.world_position.distance_to(session.world_position) > JOIN_RADIUS:
		return false

	var side_index: int = get_join_side(party_id, battle_id)
	if side_index < 0:
		return false
	if _count_living_units(party) == 0:
		return false

	var participant: BattleParticipant = session.add_participant(
		party_id, party.faction_id, side_index
	)
	if participant == null:
		return false
	# 通过本入口加入的都是既有战斗的增援；初始参战方由 start_battle_by_sides 加入。
	participant.is_reinforcement = true
	participant.reinforcement_battle_id = session.battle_id
	participant.reinforcement_arrival_time = TimeManager.world_elapsed_seconds
	_add_party_units(session, party)
	party_battle_lookup[party_id] = session.battle_id
	_lock_party(party)

	if party_id == player_party_id:
		session.player_involved = true
		current_battle = session
		_ensure_screen_battle(session)

	EventBus.battle_participant_joined.emit(
		session.battle_id, party_id, participant.side_index
	)
	EventBus.party_reinforced.emit(
		session.battle_id,
		party_id,
		party.leader_noble_id,
		participant.side_index
	)
	return true


# ---------------------------------------------------------------------------
# 内部实现
# ---------------------------------------------------------------------------


func _is_party_in_battle(party_id: String) -> bool:
	return get_battle_for_party(party_id) != null


func _is_battle_active(session: BattleSession) -> bool:
	if session == null or session.status == BattleSession.Status.ENDED:
		return false
	return active_battles.get(session.battle_id) == session


## 每场离屏战斗独立 Resolver：独立随机序列，互不干扰。
func _create_offscreen_resolver(battle_id: String) -> OffscreenBattleResolver:
	var resolver := OffscreenBattleResolver.new()
	resolver.setup(offscreen_config)
	_offscreen_resolvers[battle_id] = resolver
	return resolver


func _get_offscreen_resolver(battle_id: String) -> OffscreenBattleResolver:
	var resolver := _offscreen_resolvers.get(battle_id) as OffscreenBattleResolver
	if resolver == null:
		resolver = _create_offscreen_resolver(battle_id)
	return resolver


func _remove_battle_registry(session: BattleSession) -> void:
	active_battles.erase(session.battle_id)
	_offscreen_resolvers.erase(session.battle_id)
	for party_id: String in session.get_all_party_ids():
		if str(party_battle_lookup.get(party_id, "")) == session.battle_id:
			party_battle_lookup.erase(party_id)


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
					and _faction_manager.is_party_hostile(a.party_id, b.party_id):
				push_warning("敌对部队不能处于同一战斗侧: %s / %s" % [a.party_id, b.party_id])
				return false
	return true


## 参战方身份相同则拒绝开战。政治部队按家族比较，无家族部队仍按阵营比较。
func _all_same_faction(parties: Array[PartyData]) -> bool:
	if parties.is_empty():
		return true
	var first_house: String = ""
	if _faction_manager != null:
		first_house = _faction_manager.get_party_house_id(parties[0].party_id)
	if not first_house.is_empty():
		for party: PartyData in parties:
			if _faction_manager.get_party_house_id(party.party_id) != first_house:
				return false
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
		# 增援标记随参战方写入单位战斗状态，表现层据此在后方出生。
		state.is_reinforcement = participant.is_reinforcement
		state.reinforcement_battle_id = participant.reinforcement_battle_id
		state.reinforcement_arrival_time = participant.reinforcement_arrival_time
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
	party.battle_response_id = ""
	party.battle_response_until = 0.0
	EventBus.party_battle_state_changed.emit(party.party_id, int(party.battle_state))


func _ensure_screen_battle(session: BattleSession) -> void:
	if session.offscreen:
		session.offscreen = false
	if not session.paused_world:
		TimeManager.push_pause(GameManager.PAUSE_REASON_BATTLE)
		session.paused_world = true


## 结算前一次性决定每个 0 HP 单位的去留。
## 玩家角色保留原有永久死亡规则；普通士兵按 tier 概率负伤。
## 判定结果写回 BattleUnitState，预览与最终结算共用，不会重复掷骰。
func _decide_wounded_outcomes(session: BattleSession) -> void:
	if session == null:
		return
	for value: Variant in session.unit_states.values():
		var state := value as BattleUnitState
		if state == null or state.wounded_decided:
			continue
		if state.alive and state.battle_hp > 0:
			continue
		state.wounded_decided = true
		state.wounded = false
		var unit := _unit_manager.get_unit(state.unit_id)
		if unit == null or unit.is_player_character:
			continue
		if wounded_config == null or not wounded_config.enabled:
			continue
		var config := _unit_manager.get_unit_config(unit.config_id)
		var tier: int = config.tier if config != null else 1
		var chance: float = wounded_config.get_wounded_chance(tier)
		if chance <= 0.0:
			continue
		if _wounded_rng.randf() < chance:
			state.wounded = true


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
			if state.wounded:
				# 伤兵保留原部队成员身份、等级、装备与经验，只把 HP 置 0。
				unit.mark_wounded()
				# 防御性修复：经历异常增援/转队后确保仍属于本战斗的部队。
				if unit.current_party_id != state.party_id:
					var party := _party_manager.get_party(state.party_id)
					if party != null:
						_party_manager.add_member(party.party_id, unit.unit_id)
			else:
				unit.mark_dead()
				_destroy_dead_unit(state)
		else:
			unit.current_hp = final_hp
			unit.status = UnitData.Status.ACTIVE


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
	var cooldown_until: float = (
		TimeManager.world_elapsed_seconds + POST_BATTLE_ENGAGEMENT_COOLDOWN
	)
	for party_id: String in session.get_all_party_ids():
		var party := _party_manager.get_party(party_id)
		if party == null:
			continue
		# 没有任何可战斗成员的部队（全员永久阵亡或仅剩伤兵）停止世界移动与 AI。
		# 只有伤兵的部队仍保留成员，等待阶段 13 的顺序治疗恢复后重新启用。
		if _count_living_units(party) == 0:
			party.battle_state = PartyData.BattleState.DISABLED
		else:
			party.battle_state = PartyData.BattleState.AVAILABLE
			# 存活部队短暂禁止再战，给出脱离接触与恢复路线的时间。
			party.engagement_cooldown_until = maxf(
				party.engagement_cooldown_until, cooldown_until
			)
		# 清除旧战斗残留的移动目标：移动状态改为 IDLE 后，
		# 由 AIManager 在下一个决策周期按 AI 类型重新生成目标/路线。
		# 保留旧 target_position 会让部队在解锁后朝失效目标短暂移动。
		party.target_position = party.world_position
		party.movement_state = PartyData.MovementState.IDLE
		party.current_target_id = ""
		party.current_order = PartyData.OrderType.NONE
		party.attack_intent = false
		party.focus_party_id = ""
		party.battle_response_id = ""
		party.battle_response_until = 0.0
		EventBus.party_battle_state_changed.emit(party.party_id, int(party.battle_state))


# ---------------------------------------------------------------------------
# 俘虏分配与接收（阶段 13）
# ---------------------------------------------------------------------------


## 最大余数法：把 total_prisoners 按 participant_counts 的比例分给各部队。
## 返回 { party_id: 数量 }；数量和恒等于 total_prisoners。
## 余数相同时按 party_id 字典序决定先后，保证结果稳定可复现。
static func compute_prisoner_shares(
	total_prisoners: int, participant_counts: Dictionary
) -> Dictionary:
	var shares: Dictionary = {}
	var party_ids: Array[String] = []
	for key: Variant in participant_counts:
		party_ids.append(str(key))
	party_ids.sort()
	for party_id: String in party_ids:
		shares[party_id] = 0
	if total_prisoners <= 0 or party_ids.is_empty():
		return shares

	var total_count: int = 0
	for party_id: String in party_ids:
		total_count += maxi(0, int(participant_counts.get(party_id, 0)))

	# 有效参战人数总和为 0：不允许除零或随机分配，按稳定 ID 首个部队兜底。
	if total_count <= 0:
		shares[party_ids[0]] = total_prisoners
		return shares

	var assigned: int = 0
	var remainders: Array[Dictionary] = []
	for party_id: String in party_ids:
		var count: int = maxi(0, int(participant_counts.get(party_id, 0)))
		var product: int = total_prisoners * count
		var base: int = product / total_count
		shares[party_id] = base
		assigned += base
		remainders.append({"party_id": party_id, "remainder": product % total_count})

	var remaining: int = total_prisoners - assigned
	remainders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var rem_a: int = int(a["remainder"])
		var rem_b: int = int(b["remainder"])
		if rem_a != rem_b:
			return rem_a > rem_b
		return str(a["party_id"]) < str(b["party_id"])
	)
	var index: int = 0
	while remaining > 0 and not remainders.is_empty():
		var entry := remainders[index % remainders.size()]
		var party_id: String = str(entry["party_id"])
		shares[party_id] = int(shares.get(party_id, 0)) + 1
		remaining -= 1
		index += 1
	return shares


## 统计胜利方真实参战人数，分配战败方伤兵为俘虏。
## 只读取 BattleSession 的实际参战记录，不使用战斗结束后的剩余人数。
func _build_prisoner_allocation(
	session: BattleSession, data: BattleResultData
) -> void:
	var winning_side: int = data.winning_side_index
	if session == null or data == null or winning_side < 0:
		return

	for participant_value: Variant in session.participants.values():
		var participant := participant_value as BattleParticipant
		if participant == null:
			continue
		# get_party_unit_ids 基于实际加入战斗的状态表，增援也会计入且只计一次。
		data.participant_unit_counts[participant.party_id] = \
			session.get_party_unit_ids(participant.party_id).size()

	var winner_ids: Array[String] = session.get_side_party_ids(winning_side)
	winner_ids.sort()

	var pool: Array[String] = []
	for side_index: int in session.get_side_indices():
		if side_index == winning_side:
			continue
		for unit_id: String in session.get_side_unit_ids(side_index):
			var state := session.get_unit_state(unit_id)
			if state != null and state.wounded:
				pool.append(unit_id)
	pool.sort()
	data.prisoner_pool = pool
	if pool.is_empty() or winner_ids.is_empty():
		return

	var counts: Dictionary = {}
	for party_id: String in winner_ids:
		counts[party_id] = data.get_participant_unit_count(party_id)
	var total_count: int = 0
	for party_id: String in counts:
		total_count += int(counts[party_id])
	if total_count <= 0:
		data.prisoner_allocation_degraded = true

	var shares := compute_prisoner_shares(pool.size(), counts)
	var allocations: Dictionary = {}
	var cursor: int = 0
	for party_id: String in winner_ids:
		var quota: int = int(shares.get(party_id, 0))
		var assigned_ids: Array[String] = []
		for _i: int in range(quota):
			if cursor >= pool.size():
				break
			assigned_ids.append(pool[cursor])
			cursor += 1
		allocations[party_id] = assigned_ids
	data.prisoner_allocations = allocations


## 结算后立即把俘虏从战败部队移出：非玩家胜利部队直接接收，
## 玩家份额保留为“待确认”，由战后界面确认后提交。
func _claim_battle_prisoners(
	session: BattleSession, data: BattleResultData
) -> void:
	if session == null or data == null or data.prisoner_pool.is_empty():
		return

	for unit_id: String in data.prisoner_pool:
		var unit := _unit_manager.get_unit(unit_id)
		if unit == null:
			continue
		var state := session.get_unit_state(unit_id)
		if state != null:
			_party_manager.remove_member(state.party_id, unit_id)
		if not unit.current_party_id.is_empty():
			_party_manager.remove_member(unit.current_party_id, unit_id)
		# 待分配状态：已不再属于任何部队，也不会参与移动或治疗。
		unit.mark_prisoner("")

	for party_id: String in data.prisoner_allocations:
		if party_id == player_party_id:
			continue
		for unit_id: String in data.get_prisoners_for_party(party_id):
			if not _party_manager.add_prisoner(party_id, unit_id):
				push_warning(
					"俘虏分配失败：单位 %s → 部队 %s" % [unit_id, party_id]
				)

	var player_share := data.get_prisoners_for_party(player_party_id)
	if not player_share.is_empty() and data.player_involved and data.player_won:
		_pending_prisoner_settlements[session.battle_id] = session


## 战后界面是否仍有等待玩家确认的俘虏。
func has_pending_prisoner_selection(battle_id: String) -> bool:
	return _pending_prisoner_settlements.has(battle_id)


## 玩家本次可分到的俘虏 ID（稳定顺序）。
func get_pending_player_prisoners(battle_id: String) -> Array[String]:
	var session := _pending_prisoner_settlements.get(battle_id) as BattleSession
	if session == null or session.final_result == null:
		return []
	return session.final_result.get_prisoners_for_party(player_party_id)


## 提交玩家战后选择。accepted_unit_ids 必须是分配列表的子集；
## 未接收的俘虏被释放（移出世界）。重复调用返回 false 且不改变数据。
func commit_player_prisoners(
	battle_id: String, accepted_unit_ids: Array
) -> bool:
	var session := _pending_prisoner_settlements.get(battle_id) as BattleSession
	if session == null or session.final_result == null:
		return false
	var data := session.final_result
	if data.player_prisoners_committed:
		_pending_prisoner_settlements.erase(battle_id)
		return false

	var allocation := data.get_prisoners_for_party(player_party_id)
	var player_party := _party_manager.get_party(player_party_id)

	# 规范化选择：只接受分配列表内的单位，去重。
	var accepted: Dictionary = {}
	var accepted_ids: Array[String] = []
	for value: Variant in accepted_unit_ids:
		var unit_id: String = str(value)
		if not allocation.has(unit_id) or accepted.has(unit_id):
			continue
		accepted[unit_id] = true
		accepted_ids.append(unit_id)

	# 先校验全部待接收单位，全部通过后再提交，避免部分结算。
	if player_party != null:
		var valid_ids: Array[String] = []
		for unit_id: String in accepted_ids:
			var unit := _unit_manager.get_unit(unit_id)
			if unit == null or unit.status == UnitData.Status.DEAD \
					or not unit.current_party_id.is_empty() \
					or _party_manager.is_prisoner(unit_id):
				accepted.erase(unit_id)
				continue
			valid_ids.append(unit_id)
		accepted_ids = valid_ids

	var added_ids: Array[String] = []
	var commit_ok: bool = player_party != null
	if commit_ok:
		for unit_id: String in accepted_ids:
			if _party_manager.add_prisoner(player_party_id, unit_id):
				added_ids.append(unit_id)
			else:
				commit_ok = false
				break
	if not commit_ok:
		# 回滚已加入的俘虏，保持待确认状态供重试。
		for unit_id: String in added_ids:
			_party_manager.remove_prisoner(player_party_id, unit_id)
		return false

	for unit_id: String in allocation:
		if accepted.has(unit_id):
			continue
		_release_unclaimed_prisoner(unit_id)

	data.player_prisoners_committed = true
	_pending_prisoner_settlements.erase(battle_id)
	return true


## 玩家未接收的俘虏：清空归属并移出世界，避免留下无主伤兵。
func _release_unclaimed_prisoner(unit_id: String) -> void:
	var unit := _unit_manager.get_unit(unit_id)
	if unit == null:
		return
	unit.clear_prisoner_ownership()
	if not unit.current_party_id.is_empty():
		_party_manager.remove_member(unit.current_party_id, unit_id)
	_unit_manager.remove_unit(unit_id)
