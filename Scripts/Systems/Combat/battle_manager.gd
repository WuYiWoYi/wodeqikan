class_name BattleManager
extends RefCounted
## 战斗会话与战斗结算的统一入口。
##
## 只负责战斗会话数据、部队锁定与结算；场景加载/返回由场景控制器调用 SceneManager。
## 战斗期间 HP 的唯一权威是 BattleUnitState，结算时统一写回 UnitData。

var current_battle: BattleSession = null

var _unit_manager: UnitManager = null
var _party_manager: PartyManager = null
var _id_generator: IdGenerator = null


func setup(unit_manager: UnitManager, party_manager: PartyManager, id_generator: IdGenerator) -> void:
	_unit_manager = unit_manager
	_party_manager = party_manager
	_id_generator = id_generator


func is_in_battle() -> bool:
	return current_battle != null


## 创建战斗会话并锁定双方部队。不会切换场景；调用方负责进入 BattleScene。
## 失败返回 null，且不修改任何部队或时间状态。
func start_battle(
	attacker_party_ids: Array[String],
	defender_party_ids: Array[String],
	world_position: Vector2
) -> BattleSession:
	if current_battle != null:
		push_warning("已有进行中的战斗，拒绝重复开始")
		return null
	if _unit_manager == null or _party_manager == null or _id_generator == null:
		push_error("BattleManager 尚未装配")
		return null
	if attacker_party_ids.is_empty() or defender_party_ids.is_empty():
		push_warning("战斗双方不能为空")
		return null

	var all_party_ids: Array[String] = []
	all_party_ids.append_array(attacker_party_ids)
	all_party_ids.append_array(defender_party_ids)
	var seen: Dictionary = {}
	for party_id: String in all_party_ids:
		if seen.has(party_id):
			push_warning("同一部队不能重复参战: %s" % party_id)
			return null
		seen[party_id] = true

	var attacker_parties := _collect_parties(attacker_party_ids)
	var defender_parties := _collect_parties(defender_party_ids)
	if attacker_parties.size() != attacker_party_ids.size() \
			or defender_parties.size() != defender_party_ids.size():
		return null

	var attacker_faction := attacker_parties[0].faction_id
	var defender_faction := defender_parties[0].faction_id
	for party: PartyData in attacker_parties:
		if party.faction_id != attacker_faction:
			push_warning("进攻方部队阵营不一致")
			return null
	for party: PartyData in defender_parties:
		if party.faction_id != defender_faction:
			push_warning("防守方部队阵营不一致")
			return null
	if attacker_faction == defender_faction:
		push_warning("战斗双方阵营相同，拒绝开始")
		return null

	for party: PartyData in attacker_parties:
		if not party.is_available_for_world():
			push_warning("进攻方部队不可参战: %s" % party.party_id)
			return null
	for party: PartyData in defender_parties:
		if not party.is_available_for_world():
			push_warning("防守方部队不可参战: %s" % party.party_id)
			return null

	var session := BattleSession.new()
	session.battle_id = _id_generator.next_id(IdGenerator.BATTLE)
	session.world_position = world_position
	session.attacker_party_ids = attacker_party_ids.duplicate()
	session.defender_party_ids = defender_party_ids.duplicate()
	session.attacker_faction_id = attacker_faction
	session.defender_faction_id = defender_faction

	_fill_side_units(session, attacker_parties, true)
	_fill_side_units(session, defender_parties, false)
	if session.attacker_unit_ids.is_empty() or session.defender_unit_ids.is_empty():
		push_warning("战斗至少需要双方各一名存活士兵")
		return null

	current_battle = session
	_lock_parties(session)
	# 屏幕内战斗冻结世界模拟；set_battle_mode(0.5) 保留给未来的离屏战斗。
	TimeManager.push_pause(GameManager.PAUSE_REASON_BATTLE)
	EventBus.battle_started.emit(session.battle_id)
	return session


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
	_settle_session(session)
	_unlock_parties(session)
	current_battle = null

	TimeManager.pop_pause(GameManager.PAUSE_REASON_BATTLE)
	EventBus.battle_finished.emit(battle_id, int(session.result))
	return true


func abort_battle(battle_id: String) -> bool:
	return finish_battle(battle_id, BattleSession.BattleResult.ABORTED)


func add_reinforcement(_party_id: String, _battle_id: String) -> bool:
	# TODO(阶段6)：校验距离/阵营/加入条件后加入 BattleSession。
	return false


func _collect_parties(party_ids: Array[String]) -> Array[PartyData]:
	var result: Array[PartyData] = []
	for party_id: String in party_ids:
		var party := _party_manager.get_party(party_id)
		if party == null:
			push_warning("参战部队不存在: %s" % party_id)
			continue
		result.append(party)
	return result


func _fill_side_units(
	session: BattleSession, parties: Array[PartyData], is_attacker: bool
) -> void:
	for party: PartyData in parties:
		for unit_id: String in party.member_unit_ids:
			if session.unit_states.has(unit_id):
				continue
			var unit := _unit_manager.get_unit(unit_id)
			if unit == null or not unit.is_alive():
				push_warning("跳过无效或阵亡单位: %s" % unit_id)
				continue
			var state := BattleUnitState.new()
			state.unit_id = unit_id
			state.party_id = party.party_id
			state.battle_hp = unit.current_hp
			state.alive = true
			session.add_unit_state(state)
			if is_attacker:
				session.attacker_unit_ids.append(unit_id)
			else:
				session.defender_unit_ids.append(unit_id)


func _lock_parties(session: BattleSession) -> void:
	var party_ids: Array[String] = []
	party_ids.append_array(session.attacker_party_ids)
	party_ids.append_array(session.defender_party_ids)
	for party_id: String in party_ids:
		var party := _party_manager.get_party(party_id)
		if party == null:
			continue
		party.battle_state = PartyData.BattleState.IN_BATTLE
		party.movement_state = PartyData.MovementState.IDLE
		party.target_position = party.world_position
		party.current_order = PartyData.OrderType.NONE
		EventBus.party_battle_state_changed.emit(party.party_id, int(party.battle_state))


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


func _unlock_parties(session: BattleSession) -> void:
	var party_ids: Array[String] = []
	party_ids.append_array(session.attacker_party_ids)
	party_ids.append_array(session.defender_party_ids)
	party_ids.append_array(session.reinforcement_party_ids)
	for party_id: String in party_ids:
		var party := _party_manager.get_party(party_id)
		if party == null:
			continue
		party.battle_state = PartyData.BattleState.AVAILABLE
		party.movement_state = PartyData.MovementState.IDLE
		party.current_target_id = ""
		party.current_order = PartyData.OrderType.NONE
		EventBus.party_battle_state_changed.emit(party.party_id, int(party.battle_state))
