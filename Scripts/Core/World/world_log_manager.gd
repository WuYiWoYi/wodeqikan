class_name WorldLogManager
extends RefCounted
## 世界日志的统一数据入口。
##
## 通过监听 EventBus 已发生的事实生成日志，业务脚本与 UI 不直接写入日志面板。
## 条目包含事件类型、世界时间与显示文本；同时保留 to_dict/from_dict 供后续持久化。

signal entry_added(entry: WorldLogEntry)

const MAX_ENTRIES: int = 100

var _entries: Array[WorldLogEntry] = []
var _battle_sessions: Dictionary = {}

var _battle_manager: BattleManager = null
var _party_manager: PartyManager = null
var _settlement_manager: SettlementManager = null
var _connected: bool = false


func setup(
	battle_manager: BattleManager,
	party_manager: PartyManager,
	settlement_manager: SettlementManager
) -> void:
	dispose()
	_battle_manager = battle_manager
	_party_manager = party_manager
	_settlement_manager = settlement_manager
	_connect_events()


func dispose() -> void:
	if not _connected:
		return
	if EventBus.battle_started.is_connected(_on_battle_started):
		EventBus.battle_started.disconnect(_on_battle_started)
	if EventBus.battle_finished.is_connected(_on_battle_finished):
		EventBus.battle_finished.disconnect(_on_battle_finished)
	if EventBus.player_encounter_requested.is_connected(_on_player_encounter_requested):
		EventBus.player_encounter_requested.disconnect(_on_player_encounter_requested)
	if EventBus.settlement_entered.is_connected(_on_settlement_entered):
		EventBus.settlement_entered.disconnect(_on_settlement_entered)
	if EventBus.settlement_exited.is_connected(_on_settlement_exited):
		EventBus.settlement_exited.disconnect(_on_settlement_exited)
	if EventBus.fief_recruited.is_connected(_on_fief_recruited):
		EventBus.fief_recruited.disconnect(_on_fief_recruited)
	if EventBus.adventurer_recruited.is_connected(_on_adventurer_recruited):
		EventBus.adventurer_recruited.disconnect(_on_adventurer_recruited)
	_connected = false
	_battle_sessions.clear()


func get_entries() -> Array[WorldLogEntry]:
	return _entries.duplicate()


func get_entry_count() -> int:
	return _entries.size()


func clear() -> void:
	_entries.clear()
	_battle_sessions.clear()


## 其他世界事件的统一扩展入口；调用方只提交事实文本，不接触日志 UI。
func add_event(
	event_type: WorldLogEntry.EventType,
	text: String,
	metadata: Dictionary = {}
) -> WorldLogEntry:
	if text.strip_edges().is_empty():
		return null
	var entry := WorldLogEntry.new()
	entry.event_type = event_type
	entry.world_time_seconds = TimeManager.world_elapsed_seconds
	entry.time_text = TimeManager.get_world_time_text()
	entry.text = text
	entry.metadata = metadata.duplicate(true)
	_entries.append(entry)
	while _entries.size() > MAX_ENTRIES:
		_entries.pop_front()
	entry_added.emit(entry)
	return entry


## 持久化接口；由 WorldContext 写入 SaveData。
func to_dict() -> Dictionary:
	var entries: Array[Dictionary] = []
	for entry: WorldLogEntry in _entries:
		entries.append(entry.to_dict())
	return {"entries": entries}


func load_from_dict(data: Dictionary) -> void:
	_entries.clear()
	var values: Variant = data.get("entries", [])
	if values is Array:
		for value: Variant in values:
			if value is Dictionary:
				_entries.append(WorldLogEntry.from_dict(value))
	while _entries.size() > MAX_ENTRIES:
		_entries.pop_front()


# ---------------------------------------------------------------------------
# EventBus 事实 → 日志文本
# ---------------------------------------------------------------------------


func _connect_events() -> void:
	if not EventBus.battle_started.is_connected(_on_battle_started):
		EventBus.battle_started.connect(_on_battle_started)
	if not EventBus.battle_finished.is_connected(_on_battle_finished):
		EventBus.battle_finished.connect(_on_battle_finished)
	if not EventBus.player_encounter_requested.is_connected(
		_on_player_encounter_requested
	):
		EventBus.player_encounter_requested.connect(_on_player_encounter_requested)
	if not EventBus.settlement_entered.is_connected(_on_settlement_entered):
		EventBus.settlement_entered.connect(_on_settlement_entered)
	if not EventBus.settlement_exited.is_connected(_on_settlement_exited):
		EventBus.settlement_exited.connect(_on_settlement_exited)
	if not EventBus.fief_recruited.is_connected(_on_fief_recruited):
		EventBus.fief_recruited.connect(_on_fief_recruited)
	if not EventBus.adventurer_recruited.is_connected(_on_adventurer_recruited):
		EventBus.adventurer_recruited.connect(_on_adventurer_recruited)
	_connected = true


func _on_battle_started(battle_id: String) -> void:
	if _battle_manager == null:
		return
	# 逐场查询：世界可同时存在多场战斗，不能读取全局唯一战斗。
	var session: BattleSession = _battle_manager.get_battle(battle_id)
	if session == null:
		return
	_battle_sessions[battle_id] = session
	add_event(
		WorldLogEntry.EventType.BATTLE_STARTED,
		"%s 发生了战斗。" % _sides_text(session),
		{"battle_id": battle_id}
	)


func _on_battle_finished(battle_id: String, _result: int) -> void:
	var session := _battle_sessions.get(battle_id) as BattleSession
	_battle_sessions.erase(battle_id)
	if session == null or session.final_result == null:
		add_event(
			WorldLogEntry.EventType.BATTLE_FINISHED,
			"一场战斗结束了。",
			{"battle_id": battle_id}
		)
		return

	var data := session.final_result
	add_event(
		WorldLogEntry.EventType.BATTLE_FINISHED,
		_battle_finished_text(session, data),
		{"battle_id": battle_id, "result": int(data.result_code)}
	)

	for party_id_value: Variant in data.survivors.keys():
		var party_id: String = str(party_id_value)
		if int(data.survivors[party_id]) > 0:
			continue
		if int(data.casualties.get(party_id, 0)) <= 0:
			continue
		# 同一场战斗内每个被消灭部队只记录一次。
		add_event(
			WorldLogEntry.EventType.PARTY_ELIMINATED,
			"%s 已被消灭。" % _party_name(party_id),
			{"party_id": party_id, "battle_id": battle_id}
		)


func _on_player_encounter_requested(
	_encounter_id: String, attacker_party_id: String, _target_party_id: String
) -> void:
	var player_name: String = _player_party_name()
	add_event(
		WorldLogEntry.EventType.PLAYER_ENCOUNTER,
		"%s 与 %s 发生了遭遇。" % [player_name, _party_name(attacker_party_id)],
		{"attacker_party_id": attacker_party_id}
	)


func _on_settlement_entered(settlement_id: String, _party_id: String) -> void:
	add_event(
		WorldLogEntry.EventType.SETTLEMENT_ENTERED,
		"玩家进入了%s。" % _settlement_name(settlement_id),
		{"settlement_id": settlement_id}
	)


func _on_settlement_exited(settlement_id: String, _party_id: String) -> void:
	add_event(
		WorldLogEntry.EventType.SETTLEMENT_EXITED,
		"玩家离开了%s。" % _settlement_name(settlement_id),
		{"settlement_id": settlement_id}
	)


func _on_fief_recruited(
	recruiter_party_id: String,
	settlement_id: String,
	groups: int,
	is_player_recruiter: bool
) -> void:
	var village_name: String = _settlement_name(settlement_id)
	var recruiter: String = "你" if is_player_recruiter \
		else _party_name(recruiter_party_id)
	add_event(
		WorldLogEntry.EventType.FIEF_RECRUITED,
		"%s 在%s征召了 %d 组采邑。" % [recruiter, village_name, maxi(1, groups)],
		{
			"party_id": recruiter_party_id,
			"settlement_id": settlement_id,
			"groups": groups,
			"is_player_recruiter": is_player_recruiter,
		}
	)


func _on_adventurer_recruited(
	settlement_id: String, unit_id: String, unit_name: String
) -> void:
	var village_name: String = _settlement_name(settlement_id)
	var recruit_name: String = unit_name if not unit_name.is_empty() else unit_id
	add_event(
		WorldLogEntry.EventType.ADVENTURER_RECRUITED,
		"你在%s招募了冒险者%s。" % [village_name, recruit_name],
		{
			"settlement_id": settlement_id,
			"unit_id": unit_id,
			"unit_name": unit_name,
		}
	)


# ---------------------------------------------------------------------------
# 文本格式化
# ---------------------------------------------------------------------------


func _sides_text(session: BattleSession) -> String:
	var side_texts: Array[String] = []
	for side_index: int in session.get_side_indices():
		side_texts.append(_side_names(session, side_index))
	return " 与 ".join(side_texts)


func _battle_finished_text(
	session: BattleSession, data: BattleResultData
) -> String:
	if data.result_code == int(BattleSession.BattleResult.ABORTED):
		return "%s 的战斗中止了。" % _sides_text(session)

	if data.result_code == int(BattleSession.BattleResult.RETREATED):
		var retreated: Array[String] = []
		for side_index: int in data.retreated_side_indices:
			retreated.append(_side_names(session, side_index))
		if retreated.is_empty():
			return "%s 的战斗结束了。" % _sides_text(session)
		return "%s 撤退了。" % "、".join(retreated)

	if data.winning_side_index < 0:
		return "%s 的战斗以平局结束。" % _sides_text(session)

	var winner: String = _side_names(session, data.winning_side_index)
	var losers: Array[String] = []
	for side_index: int in session.get_side_indices():
		if side_index != data.winning_side_index:
			losers.append(_side_names(session, side_index))
	if losers.is_empty():
		return "%s 赢得了战斗。" % winner
	return "%s 击败了 %s。" % [winner, "、".join(losers)]


func _side_names(session: BattleSession, side_index: int) -> String:
	var names: Array[String] = []
	for party_id: String in session.get_side_party_ids(side_index):
		names.append(_party_name(party_id))
	if names.is_empty():
		return "未知部队"
	return "、".join(names)


func _party_name(party_id: String) -> String:
	if _party_manager == null:
		return party_id
	var party := _party_manager.get_party(party_id)
	if party == null:
		return party_id
	return party.party_name if not party.party_name.is_empty() else party_id


func _player_party_name() -> String:
	if _battle_manager == null:
		return "玩家部队"
	return _party_name(_battle_manager.player_party_id)


func _settlement_name(settlement_id: String) -> String:
	if _settlement_manager == null:
		return settlement_id
	var settlement := _settlement_manager.get_settlement(settlement_id)
	if settlement == null:
		return settlement_id
	return settlement.display_name
