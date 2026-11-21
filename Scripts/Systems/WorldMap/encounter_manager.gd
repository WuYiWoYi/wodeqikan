class_name EncounterManager
extends RefCounted
## 统一的大地图遭遇判定与玩家中途参战交互。
##
## 职责：
## - AI 对 AI / AI 对玩家的攻击意图遭遇（距离 AI_ENCOUNTER_RADIUS）；
## - 玩家接近进行中的离屏战斗时生成“加入/离开”交互请求；
## - 创建/加入战斗、委托 BattleManager 处理重复参战；
## - 停止相关部队并清理追逐/攻击意图。
##
## 具体 AI 只设置 attack_intent 与 current_target_id，不自行判断遭遇距离或创建战斗。

## 本次玩家遭遇的实际原因。用于决定对话文本与可用选项，而不是仅凭敌对关系推断。
enum EncounterReason {
	PASSIVE_ENCOUNTER,
	PLAYER_INITIATED,
	ENEMY_PURSUIT,
	OTHER,
}

const AI_ENCOUNTER_RADIUS: float = 50.0
## 玩家接近离屏战斗的交互距离；略小于 BattleManager.JOIN_RADIUS，确保选择“加入”时一定满足距离校验。
const BATTLE_INTERACTION_RADIUS: float = 55.0
## 离开交互范围需要超过该距离，避免玩家原地收到重复面板。
const BATTLE_INTERACTION_EXIT_RADIUS: float = 90.0
## 玩家选择“撤退”后，离开该距离前不会再次触发同一场遭遇。
const ENCOUNTER_DECLINE_EXIT_RADIUS: float = 90.0

var _party_manager: PartyManager = null
var _faction_manager: FactionManager = null
var _battle_manager: BattleManager = null
var _world_map_manager: WorldMapManager = null

var _encounter_serial: int = 0
var _interaction_serial: int = 0
## { encounter_id, attacker_party_id, target_party_id, reason }
var _pending_player_encounter: Dictionary = {}
## { interaction_id, battle_id, player_party_id }
var _pending_battle_interaction: Dictionary = {}
## 玩家选择“离开”后，直到离开交互范围或战斗结束前不再重复提示。
var _declined_battle_id: String = ""
## 玩家在遭遇面板选择“撤退”后，离开敌对部队一定距离前不重复触发同一遭遇。
var _declined_encounter_attacker_id: String = ""


func setup(
	party_manager: PartyManager,
	faction_manager: FactionManager,
	battle_manager: BattleManager,
	world_map_manager: WorldMapManager
) -> void:
	_party_manager = party_manager
	_faction_manager = faction_manager
	_battle_manager = battle_manager
	_world_map_manager = world_map_manager


# ---------------------------------------------------------------------------
# 敌对 AI 遭遇
# ---------------------------------------------------------------------------


func has_pending_player_encounter() -> bool:
	return not _pending_player_encounter.is_empty()


func get_pending_player_encounter() -> Dictionary:
	return _pending_player_encounter.duplicate(true)


func get_pending_encounter_reason() -> EncounterReason:
	return int(_pending_player_encounter.get(
		"reason", EncounterReason.OTHER
	)) as EncounterReason


## 只有敌对部队主动追击并成功拦截（ENEMY_PURSUIT）时禁止直接离开。
## 玩家主动接近、普通相遇等仍保留原有离开规则。
static func can_leave_encounter(reason: EncounterReason) -> bool:
	return reason != EncounterReason.ENEMY_PURSUIT


static func reason_key(reason: EncounterReason) -> String:
	match reason:
		EncounterReason.PASSIVE_ENCOUNTER:
			return "PASSIVE_ENCOUNTER"
		EncounterReason.PLAYER_INITIATED:
			return "PLAYER_INITIATED"
		EncounterReason.ENEMY_PURSUIT:
			return "ENEMY_PURSUIT"
		_:
			return "OTHER"


func clear_pending_player_encounter() -> void:
	_pending_player_encounter.clear()


## 统一遭遇判定。返回是否触发了玩家被主动拦截的遭遇。
func update_encounters() -> bool:
	if _party_manager == null or _faction_manager == null or _battle_manager == null:
		return false
	if not _pending_player_encounter.is_empty():
		return false
	if not _pending_battle_interaction.is_empty():
		return false
	_refresh_declined_encounter_latch()

	var battle := _battle_manager.current_battle
	var player_party_id: String = _battle_manager.player_party_id
	var parties: Array[PartyData] = _party_manager.get_all_parties()
	for i: int in range(parties.size()):
		var a := parties[i]
		if not _has_encounter_presence(a):
			continue
		for j: int in range(i + 1, parties.size()):
			var b := parties[j]
			if not _has_encounter_presence(b):
				continue
			# 刚结束战斗的部队优先脱离接触，不能被同一对手立刻拖回战斗。
			if _is_engagement_cooling(a) or _is_engagement_cooling(b):
				continue
			if not _faction_manager.is_hostile(a.faction_id, b.faction_id):
				continue
			if a.world_position.distance_to(b.world_position) > AI_ENCOUNTER_RADIUS:
				continue

			# 攻击意图必须明确指向对方，避免“正在追商队却顺手拦截玩家”。
			var a_attacks_b: bool = a.attack_intent and a.current_target_id == b.party_id
			var b_attacks_a: bool = b.attack_intent and b.current_target_id == a.party_id

			# 玩家被具有攻击意图的敌对 AI 拦截：交给 WorldMap 弹出遭遇对话。
			if not player_party_id.is_empty() and (a.party_id == player_party_id \
					or b.party_id == player_party_id):
				if battle != null:
					continue
				if not a.is_available_for_world() or not b.is_available_for_world():
					continue
				var attacker := a if b.party_id == player_party_id else b
				var target := b if attacker == a else a
				if _declined_encounter_attacker_id == attacker.party_id:
					continue
				# 两种成立方式：
				# 1. 敌对 AI 的 attack_intent 明确指向玩家；
				# 2. 玩家主动点击并持续追击该敌对部队（focus_party_id 指向对方）。
				# 玩家追击不要求目标停下，也不依赖目标反过来追击玩家。
				var ai_initiated: bool = (
					attacker.attack_intent
					and attacker.current_target_id == target.party_id
				)
				var player_pursuit: bool = (
					not target.focus_party_id.is_empty()
					and target.focus_party_id == attacker.party_id
				)
				if not ai_initiated and not player_pursuit:
					continue
				# 敌对部队主动追击优先于玩家追击：双方都在追对方时按拦截处理。
				var reason := (
					EncounterReason.ENEMY_PURSUIT
					if ai_initiated else EncounterReason.PLAYER_INITIATED
				)
				_begin_pending_player_encounter(attacker, target, reason)
				return true

			# NPC 对 NPC：已有离屏战斗时只处理“其中一方可加入”的情况。
			if battle != null:
				if not battle.offscreen:
					continue
				var engaged: PartyData = null
				var available: PartyData = null
				if battle.is_party_involved(a.party_id) and b.is_available_for_world():
					engaged = a
					available = b
				elif battle.is_party_involved(b.party_id) and a.is_available_for_world():
					engaged = b
					available = a
				if engaged == null:
					continue
				# 玩家加入离屏战斗由 battle interaction 流程处理。
				if available.party_id == player_party_id:
					continue
				if _battle_manager.try_join_battle(available.party_id):
					available.attack_intent = false
					return false
				continue

			if not a.is_available_for_world() or not b.is_available_for_world():
				continue
			if not (a_attacks_b or b_attacks_a):
				continue
			var ai_attacker := a if a_attacks_b else b
			var ai_target := b if ai_attacker == a else a
			var midpoint := (a.world_position + b.world_position) * 0.5
			_battle_manager.start_battle(
				[ai_attacker.party_id], [ai_target.party_id], midpoint, true
			)
			ai_attacker.attack_intent = false
			ai_target.attack_intent = false
			return false
	return false


## 战斗结束后的短暂冷却；与 AIManager 使用同一 PartyData 字段。
func _is_engagement_cooling(party: PartyData) -> bool:
	if party == null:
		return false
	return party.engagement_cooldown_until > TimeManager.world_elapsed_seconds


func _begin_pending_player_encounter(
	attacker: PartyData, target: PartyData, reason: EncounterReason
) -> void:
	_encounter_serial += 1
	_declined_encounter_attacker_id = ""
	_pending_player_encounter = {
		"encounter_id": "ENCOUNTER_%04d" % _encounter_serial,
		"attacker_party_id": attacker.party_id,
		"target_party_id": target.party_id,
		"reason": int(reason),
	}
	# 立即停止双方并清除追击/焦点，避免接触后继续推挤或旧指令覆盖战斗状态。
	_stop_party(attacker.party_id)
	_stop_party(target.party_id)
	attacker.attack_intent = false
	target.attack_intent = false
	attacker.focus_party_id = ""
	target.focus_party_id = ""
	EventBus.player_encounter_requested.emit(
		str(_pending_player_encounter["encounter_id"]),
		attacker.party_id,
		target.party_id
	)


## 玩家在遭遇面板选择撤退/离开：清理待处理遭遇，并在离开范围前不再重复提示。
## 敌对追击拦截不允许直接离开，因此该入口会拒绝处理这类遭遇。
func decline_player_encounter(attacker_party_id: String) -> void:
	if not can_leave_encounter(get_pending_encounter_reason()):
		return
	_pending_player_encounter.clear()
	_declined_encounter_attacker_id = attacker_party_id
	var player_party_id: String = _battle_manager.player_party_id \
		if _battle_manager != null else ""
	if not player_party_id.is_empty() and _world_map_manager != null:
		_world_map_manager.stop_party(player_party_id)


func clear_encounter_decline_latch() -> void:
	_declined_encounter_attacker_id = ""


func _refresh_declined_encounter_latch() -> void:
	if _declined_encounter_attacker_id.is_empty():
		return
	var player_party_id: String = _battle_manager.player_party_id \
		if _battle_manager != null else ""
	var player := _party_manager.get_party(player_party_id) \
		if _party_manager != null else null
	var attacker := _party_manager.get_party(_declined_encounter_attacker_id) \
		if _party_manager != null else null
	if player == null or attacker == null \
			or player.world_position.distance_to(attacker.world_position) \
			> ENCOUNTER_DECLINE_EXIT_RADIUS:
		_declined_encounter_attacker_id = ""


func _has_encounter_presence(party: PartyData) -> bool:
	if party == null or party.battle_state == PartyData.BattleState.DISABLED:
		return false
	if party.member_unit_ids.is_empty():
		return false
	# 参与离屏战斗的部队仍可作为“被加入”的一方；常规遭遇要求双方可用。
	return party.is_available_for_world() or party.battle_state == PartyData.BattleState.IN_BATTLE


# ---------------------------------------------------------------------------
# 玩家接近进行中的离屏战斗
# ---------------------------------------------------------------------------


func has_pending_battle_interaction() -> bool:
	return not _pending_battle_interaction.is_empty()


func get_pending_battle_interaction() -> Dictionary:
	return _pending_battle_interaction.duplicate(true)


func clear_pending_battle_interaction() -> void:
	_pending_battle_interaction.clear()


## 玩家选择“离开”后记录该战斗，直到离开交互范围或战斗结束前不再提示。
func decline_battle_interaction(battle_id: String) -> void:
	_declined_battle_id = battle_id
	_pending_battle_interaction.clear()


func clear_battle_interaction_latch() -> void:
	_declined_battle_id = ""


## 玩家接近进行中的离屏战斗时生成交互请求。返回是否触发。
func update_player_battle_interaction() -> bool:
	if _party_manager == null or _battle_manager == null:
		return false
	if not _pending_player_encounter.is_empty():
		return false
	if not _pending_battle_interaction.is_empty():
		return false

	var player_party_id: String = _battle_manager.player_party_id
	if player_party_id.is_empty():
		return false
	var player := _party_manager.get_party(player_party_id)
	if player == null:
		return false
	# 玩家正在主动追逐/接近目标部队时，不因路过 NPC 离屏战斗而打断追逐。
	# 敌对 AI 主动追击玩家的遭遇仍由 update_encounters 处理。
	if not player.focus_party_id.is_empty():
		return false

	var battle := _battle_manager.current_battle
	if _declined_battle_id != "" and (battle == null or battle.battle_id != _declined_battle_id):
		_declined_battle_id = ""

	if battle == null or not battle.offscreen:
		return false
	if battle.is_party_involved(player_party_id):
		return false
	if not player.is_available_for_world() or player.member_unit_ids.is_empty():
		return false

	var distance := player.world_position.distance_to(battle.world_position)
	if _declined_battle_id == battle.battle_id:
		if distance <= BATTLE_INTERACTION_EXIT_RADIUS:
			return false
		# 离开交互范围后允许再次触发。
		_declined_battle_id = ""
	if distance > BATTLE_INTERACTION_RADIUS:
		return false
	if _battle_manager.get_join_side(player_party_id) < 0:
		return false

	_interaction_serial += 1
	_pending_battle_interaction = {
		"interaction_id": "BATTLE_INTERACTION_%04d" % _interaction_serial,
		"battle_id": battle.battle_id,
		"player_party_id": player_party_id,
	}
	_stop_party(player_party_id)
	EventBus.player_battle_interaction_requested.emit(
		str(_pending_battle_interaction["interaction_id"]),
		battle.battle_id
	)
	return true


func _stop_party(party_id: String) -> void:
	if _world_map_manager != null:
		_world_map_manager.stop_party(party_id)
	var party := _party_manager.get_party(party_id) if _party_manager != null else null
	if party == null:
		return
	party.target_position = party.world_position
	party.movement_state = PartyData.MovementState.IDLE
	party.current_order = PartyData.OrderType.NONE
	party.current_target_id = ""
	party.attack_intent = false
	party.focus_party_id = ""
