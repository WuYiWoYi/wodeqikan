class_name LordRansomManager
extends RefCounted
## NPC 领主出售后的家族赎回生命周期。
##
## 流程：
##   玩家出售领主 → WAITING（按世界时间等待）
##   → 家族请求生成 → REQUESTED（事件中心可操作）
##   → 玩家接受 → ACCEPTED（支付一次赎金、领主重新出现在世界）
##   → 玩家取消 → 保持 REQUESTED，不支付、不释放。
##
## 本类是赎回记录的唯一写者；事件中心与 UI 只读取 get_active_events()。
## 所有状态都从当前实体数据重新校验，不信任 UI 缓存的旧事件副本。

enum Status {
	WAITING,
	REQUESTED,
	ACCEPTED,
	INVALID,
}

const CONFIG_PATH: String = "res://Data/Lords/lord_ransom_config.tres"
const ACTION_TYPE_RANSOM: String = "RANSOM"

## 只读 WorldContext；不声明具体类型以避免脚本循环引用。
var _context = null
var _unit_manager: UnitManager = null
var _party_manager: PartyManager = null
var _noble_manager: NobleManager = null
var _house_manager: HouseManager = null
var _settlement_manager: SettlementManager = null
var _id_generator: IdGenerator = null
var _player_profile: PlayerProfile = null
var _world_log_manager: WorldLogManager = null
var _config: LordRansomConfig = null

## { ransom_id: Dictionary }。记录随存档持久化，不保存 UI 节点。
var _records: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func setup(
	context,
	unit_manager: UnitManager,
	party_manager: PartyManager,
	noble_manager: NobleManager,
	house_manager: HouseManager,
	settlement_manager: SettlementManager,
	id_generator: IdGenerator,
	player_profile: PlayerProfile,
	world_log_manager: WorldLogManager = null,
	config: LordRansomConfig = null
) -> void:
	_context = context
	_unit_manager = unit_manager
	_party_manager = party_manager
	_noble_manager = noble_manager
	_house_manager = house_manager
	_settlement_manager = settlement_manager
	_id_generator = id_generator
	_player_profile = player_profile
	_world_log_manager = world_log_manager
	_config = config if config != null else _load_config()
	_config.sanitize()
	_rng.randomize()


func set_config(config: LordRansomConfig) -> void:
	_config = config if config != null else LordRansomConfig.create_default()
	_config.sanitize()


func get_config() -> LordRansomConfig:
	return _config


## 出售领主后登记等待。由 PrisonerTradeManager 在 mark_sold 之后调用。
## 同一领主只保留一条记录：再次出售会重置为新的等待周期。
func on_lord_sold(unit: UnitData, settlement_id: String) -> String:
	if _config == null or not _config.enabled:
		return ""
	if unit == null or not unit.is_noble_lord() or settlement_id.is_empty():
		return ""
	var noble := _noble_manager.get_noble(unit.noble_id) if _noble_manager != null else null
	if noble == null or not noble.alive:
		return ""

	var record := get_record_for_noble(unit.noble_id)
	if record.is_empty():
		record = _create_record(unit, noble, settlement_id)
		_records[str(record["ransom_id"])] = record
	else:
		_reset_record(record, unit, noble, settlement_id)
	_log(
		"%s 被出售给 %s，家族将在稍后决定是否赎人。"
		% [noble.display_name, _settlement_name(settlement_id)],
		{"ransom_id": str(record.get("ransom_id", "")), "noble_id": noble.lord_id}
	)
	return str(record.get("ransom_id", ""))


## 世界 tick：把到期的等待转为正式请求，并清理已失效的请求。
func tick() -> void:
	if _config == null or not _config.enabled:
		return
	var now: float = TimeManager.world_elapsed_seconds
	var ids: Array = _records.keys()
	ids.sort()
	for key: Variant in ids:
		var record: Dictionary = _record_at(key)
		if record == null or record.is_empty():
			continue
		var status: int = int(record.get("status", Status.INVALID))
		if status == Status.WAITING:
			var reason: String = _check_record(record, false)
			if not reason.is_empty():
				_invalidate(record, reason, _should_recover(reason))
				continue
			if now + 0.001 >= float(record.get("due_world_seconds", 0.0)):
				_generate_request(record)
		elif status == Status.REQUESTED:
			var reason: String = _check_record(record, true)
			if not reason.is_empty():
				_invalidate(record, reason, _should_recover(reason))


## 当前可操作的赎回事件。返回值每次重新构建，调用方不得缓存为权威数据。
func get_active_events() -> Array[Dictionary]:
	tick()
	var events: Array[Dictionary] = []
	var ids: Array = _records.keys()
	ids.sort()
	for key: Variant in ids:
		var record: Dictionary = _record_at(key)
		if record == null or int(record.get("status", Status.INVALID)) != Status.REQUESTED:
			continue
		if not _check_record(record, true).is_empty():
			continue
		events.append(_build_event(record))
	return events


func get_event_view(ransom_id: String) -> Dictionary:
	var record: Dictionary = _record_at(ransom_id)
	if record == null or int(record.get("status", Status.INVALID)) != Status.REQUESTED:
		return {}
	if not _check_record(record, true).is_empty():
		return {}
	return _build_event(record)


## 接受赎回：再次校验当前世界状态，支付一次赎金并让领主重回世界。
## 返回 { success, gold, reason }。
func accept_ransom(ransom_id: String) -> Dictionary:
	var result := {"success": false, "gold": 0, "reason": ""}
	var record: Dictionary = _record_at(ransom_id)
	if record == null or record.is_empty():
		result["reason"] = "赎回请求不存在"
		return result
	if int(record.get("status", Status.INVALID)) != Status.REQUESTED:
		result["reason"] = "赎回请求已结束"
		return result

	var reason: String = _check_record(record, true)
	if not reason.is_empty():
		_invalidate(record, reason, _should_recover(reason))
		result["reason"] = _reason_text(reason)
		return result

	var unit := _unit_manager.get_unit(str(record.get("noble_unit_id", "")))
	var noble := _noble_manager.get_noble(str(record.get("noble_id", "")))
	if unit == null or noble == null:
		_invalidate(record, "lord_missing", false)
		result["reason"] = _reason_text("lord_missing")
		return result

	var gold: int = maxi(0, int(record.get("ransom_gold", 0)))
	# 先写终态，保证重复点击/重复请求不会二次支付。
	record["status"] = Status.ACCEPTED
	record["accepted_world_seconds"] = TimeManager.world_elapsed_seconds
	record["paid_gold"] = gold
	unit.mark_ransomed()
	if _player_profile != null and gold > 0:
		_player_profile.add_gold(gold)

	var restored: bool = _restore_lord_to_world(unit, noble, record, false)
	if not restored:
		push_error("[LordRansomManager] 赎回后重建领主部队失败: %s" % noble.lord_id)
	_log(
		"%s 的家族支付 %d 金币赎回了他。" % [noble.display_name, gold],
		{"ransom_id": ransom_id, "noble_id": noble.lord_id, "gold": gold}
	)

	result["success"] = true
	result["gold"] = gold
	return result


## 取消只关闭界面：记录与领主状态保持不变，不支付金币。
func decline_ransom(ransom_id: String) -> bool:
	var record: Dictionary = _record_at(ransom_id)
	return record != null and int(record.get("status", Status.INVALID)) == Status.REQUESTED


func get_record_for_noble(noble_id: String) -> Dictionary:
	if noble_id.is_empty():
		return {}
	for key: Variant in _records:
		var record: Dictionary = _record_at(key)
		if record != null and str(record.get("noble_id", "")) == noble_id:
			return record
	return {}


func get_lord_state(noble_id: String) -> String:
	var record := get_record_for_noble(noble_id)
	if record.is_empty():
		return "ACTIVE"
	match int(record.get("status", Status.INVALID)):
		Status.WAITING:
			return "WAITING"
		Status.REQUESTED:
			return "REQUESTED"
		Status.ACCEPTED:
			return "ACCEPTED"
		_:
			return "INVALID"


func to_dict() -> Dictionary:
	var payload: Dictionary = {}
	for key: Variant in _records:
		var record: Dictionary = _record_at(key)
		if record != null:
			payload[str(key)] = record.duplicate(true)
	return payload


func load_from_dict(payload: Dictionary) -> void:
	_records.clear()
	if payload == null:
		return
	for key: Variant in payload:
		var value: Variant = payload[key]
		if not value is Dictionary:
			continue
		var record := _sanitize_record(str(key), value as Dictionary)
		if record.is_empty():
			continue
		_records[str(record["ransom_id"])] = record
	_dedupe_by_noble()
	sanitize_after_load()


## 读档后校正：丢弃缺少稳定 ID 的记录，失效记录不再产生事件。
func sanitize_after_load() -> void:
	if _records.is_empty():
		return
	var ids: Array = _records.keys()
	ids.sort()
	for key: Variant in ids:
		var record: Dictionary = _record_at(key)
		if record == null:
			continue
		var status: int = int(record.get("status", Status.INVALID))
		if status == Status.ACCEPTED or status == Status.INVALID:
			continue
		var reason: String = _check_record(record, status == Status.REQUESTED)
		if not reason.is_empty():
			_invalidate(record, reason, _should_recover(reason))


# ---------------------------------------------------------------------------
# 记录与校验
# ---------------------------------------------------------------------------


func _create_record(
	unit: UnitData, noble: NobleData, settlement_id: String
) -> Dictionary:
	var wait_hours: int = _rng.randi_range(
		_config.wait_hours_min, _config.wait_hours_max
	)
	var now: float = TimeManager.world_elapsed_seconds
	var party := _party_manager.get_party(noble.party_id)
	var house := _house_manager.get_house(noble.house_id) if _house_manager != null else null
	return {
		"ransom_id": _id_generator.next_id(IdGenerator.RANSOM)
		if _id_generator != null else "",
		"noble_id": noble.lord_id,
		"noble_unit_id": unit.unit_id,
		"house_id": noble.house_id,
		"house_name": house.house_name if house != null else "",
		"lord_name": noble.display_name,
		"party_id": noble.party_id,
		"party_name": party.party_name if party != null else "",
		"sold_settlement_id": settlement_id,
		"sold_world_seconds": now,
		"due_world_seconds": now + _config.wait_seconds_for_hours(wait_hours),
		"ransom_gold": 0,
		"status": Status.WAITING,
		"requested_world_seconds": -1.0,
		"accepted_world_seconds": -1.0,
		"paid_gold": 0,
		"invalid_reason": "",
	}


func _reset_record(
	record: Dictionary, unit: UnitData, noble: NobleData, settlement_id: String
) -> void:
	var wait_hours: int = _rng.randi_range(
		_config.wait_hours_min, _config.wait_hours_max
	)
	var now: float = TimeManager.world_elapsed_seconds
	var party := _party_manager.get_party(noble.party_id)
	var house := _house_manager.get_house(noble.house_id) if _house_manager != null else null
	record["noble_id"] = noble.lord_id
	record["noble_unit_id"] = unit.unit_id
	record["house_id"] = noble.house_id
	record["house_name"] = house.house_name if house != null else ""
	record["lord_name"] = noble.display_name
	record["party_id"] = noble.party_id
	record["party_name"] = party.party_name if party != null else ""
	record["sold_settlement_id"] = settlement_id
	record["sold_world_seconds"] = now
	record["due_world_seconds"] = now + _config.wait_seconds_for_hours(wait_hours)
	record["ransom_gold"] = 0
	record["status"] = Status.WAITING
	record["requested_world_seconds"] = -1.0
	record["accepted_world_seconds"] = -1.0
	record["paid_gold"] = 0
	record["invalid_reason"] = ""


## 返回空字符串表示记录仍然有效；否则返回稳定错误键。
func _check_record(record: Dictionary, require_request_ready: bool) -> String:
	if _unit_manager == null or _noble_manager == null:
		return "manager_missing"
	var unit := _unit_manager.get_unit(str(record.get("noble_unit_id", "")))
	if unit == null:
		return "lord_missing"
	if not unit.is_noble_lord():
		return "lord_identity_missing"
	if not unit.prisoner_owner_party_id.is_empty():
		return "lord_is_captive"
	if unit.sold_to_settlement_id.is_empty() \
			or unit.sold_to_settlement_id != str(record.get("sold_settlement_id", "")):
		return "sold_state_changed"
	if not unit.current_party_id.is_empty():
		return "lord_in_party"
	var noble := _noble_manager.get_noble(str(record.get("noble_id", "")))
	if noble == null or not noble.alive:
		return "noble_missing"
	if noble.house_id.is_empty():
		return "house_missing"
	if _house_manager == null or _house_manager.get_house(noble.house_id) == null:
		return "house_missing"
	if require_request_ready and _find_spawn_settlement(record, noble, false) == null:
		return "no_friendly_settlement"
	return ""


func _should_recover(reason: String) -> bool:
	return reason == "house_missing" or reason == "no_friendly_settlement"


func _invalidate(record: Dictionary, reason: String, recover: bool) -> void:
	if int(record.get("status", Status.INVALID)) == Status.INVALID:
		return
	record["status"] = Status.INVALID
	record["invalid_reason"] = reason
	if recover:
		# 异常终止时尽量让领主回到世界，避免永久停留在“已出售”状态。
		var unit := _unit_manager.get_unit(str(record.get("noble_unit_id", "")))
		var noble := _noble_manager.get_noble(str(record.get("noble_id", "")))
		if unit != null and noble != null \
				and unit.sold_to_settlement_id == str(record.get("sold_settlement_id", "")):
			unit.mark_ransomed()
			_restore_lord_to_world(unit, noble, record, true)
	_log(
		"家族赎回请求失效（%s）：%s。" % [reason, str(record.get("lord_name", ""))],
		{"ransom_id": str(record.get("ransom_id", "")), "noble_id": str(record.get("noble_id", ""))}
	)


func _generate_request(record: Dictionary) -> void:
	var reason: String = _check_record(record, true)
	if not reason.is_empty():
		_invalidate(record, reason, _should_recover(reason))
		return
	var gold: int = _rng.randi_range(
		_config.ransom_gold_min, _config.ransom_gold_max
	)
	record["ransom_gold"] = maxi(101, gold)
	record["requested_world_seconds"] = TimeManager.world_elapsed_seconds
	record["status"] = Status.REQUESTED
	_log(
		"%s 的家族发来赎回请求，赎金 %d 金币。"
		% [str(record.get("lord_name", "")), int(record["ransom_gold"])],
		{"ransom_id": str(record.get("ransom_id", "")), "noble_id": str(record.get("noble_id", ""))}
	)


func _build_event(record: Dictionary) -> Dictionary:
	var ransom_id: String = str(record.get("ransom_id", ""))
	var lord_name: String = str(record.get("lord_name", "无名领主"))
	var house_name: String = str(record.get("house_name", "未知家族"))
	var gold: int = int(record.get("ransom_gold", 0))
	var settlement_name: String = _settlement_name(
		str(record.get("sold_settlement_id", ""))
	)
	var title: String = "家族赎回请求"
	var detail: String = (
		"%s 被关押在%s。\n%s 希望以 %d 金币赎回他。\n\n"
		+ "接受：收取赎金，领主将在家乡附近重新出现。\n"
		+ "取消：保持现状，事件继续保留。"
	) % [lord_name, settlement_name, house_name, gold]
	return {
		"event_id": "ransom:%s" % ransom_id,
		"type": "RANSOM",
		"type_text": "赎回",
		"title": title,
		"detail": detail,
		"actionable": true,
		"action_type": ACTION_TYPE_RANSOM,
		"ransom_id": ransom_id,
		"noble_id": str(record.get("noble_id", "")),
		"house_id": str(record.get("house_id", "")),
		"house_name": house_name,
		"lord_name": lord_name,
		"gold": gold,
		"due_world_seconds": float(record.get("due_world_seconds", 0.0)),
	}


func _reason_text(reason: String) -> String:
	match reason:
		"house_missing":
			return "领主家族已不存在，赎回流程终止"
		"no_friendly_settlement":
			return "家族没有可用据点，赎回流程终止"
		"sold_state_changed":
			return "领主状态已变化，事件失效"
		"lord_is_captive":
			return "领主已被重新关押，事件失效"
		"lord_in_party":
			return "领主已回到部队，事件失效"
		"noble_missing":
			return "领主已不存在，事件失效"
		_:
			return "赎回请求已失效"


# ---------------------------------------------------------------------------
# 重新放回世界
# ---------------------------------------------------------------------------


func _restore_lord_to_world(
	unit: UnitData, noble: NobleData, record: Dictionary, allow_any_settlement: bool
) -> bool:
	if _context == null or _party_manager == null:
		return false
	var spawn: SettlementData = _find_spawn_settlement(record, noble, allow_any_settlement)
	if spawn == null and allow_any_settlement:
		spawn = _find_any_settlement()
	if spawn == null:
		return false

	var party := _resolve_party(noble, record, spawn)
	if party == null:
		return false

	var spawn_position: Vector2 = spawn.world_position + Vector2(48.0, 36.0)
	_reset_party_runtime(party, spawn_position)
	if not WorldInitializer.restore_lord_party(_context, party, noble, unit):
		return false
	noble.party_id = party.party_id
	return true


func _resolve_party(
	noble: NobleData, record: Dictionary, spawn: SettlementData
) -> PartyData:
	# 优先复用贵族当前指挥的部队，绝不新建第二支重复部队。
	if not noble.party_id.is_empty():
		var existing := _party_manager.get_party(noble.party_id)
		if existing != null and not existing.is_player_controlled():
			return existing
	# 兼容旧存档/异常状态：按 leader_noble_id 找回原部队。
	for party: PartyData in _party_manager.get_all_parties():
		if party != null and not party.is_player_controlled() \
				and party.leader_noble_id == noble.lord_id:
			return party
	# 记录快照中的部队仍然存在时也复用。
	var snapshot_id: String = str(record.get("party_id", ""))
	if not snapshot_id.is_empty():
		var snapshot := _party_manager.get_party(snapshot_id)
		if snapshot != null and not snapshot.is_player_controlled() \
				and (snapshot.leader_noble_id.is_empty() \
					or snapshot.leader_noble_id == noble.lord_id):
			return snapshot

	var house := _house_manager.get_house(noble.house_id)
	var party_name: String = str(record.get("party_name", ""))
	if party_name.is_empty():
		party_name = "%s的部队" % noble.display_name
	var faction_id: String = noble.faction_id if not noble.faction_id.is_empty() \
		else spawn.faction_id
	var party := _party_manager.create_party(
		faction_id,
		spawn.world_position,
		party_name,
		PartyData.PartyKind.FAMILY
	)
	if party == null:
		return null
	party.family_id = house.banner_id if house != null else ""
	party.leader_noble_id = noble.lord_id
	party.movement_speed = WorldInitializer.FAMILY_KNIGHT_MOVE_SPEED
	party.sight_range = WorldInitializer.FAMILY_KNIGHT_SIGHT_RANGE
	return party


func _reset_party_runtime(party: PartyData, spawn_position: Vector2) -> void:
	party.world_position = spawn_position
	party.target_position = spawn_position
	party.movement_state = PartyData.MovementState.IDLE
	party.current_order = PartyData.OrderType.NONE
	party.current_target_id = ""
	party.battle_state = PartyData.BattleState.AVAILABLE
	party.attack_intent = false
	party.focus_party_id = ""
	party.engagement_cooldown_until = 0.0
	party.battle_response_id = ""
	party.battle_response_until = 0.0
	if party.ai_type == PartyData.PartyAIType.NONE:
		party.ai_type = PartyData.PartyAIType.PATROL
	party.ai_route_index = 0
	if party.ai_patrol_points.is_empty():
		party.ai_patrol_points = [
			spawn_position,
			spawn_position + Vector2(120.0, 40.0),
			spawn_position + Vector2(80.0, 140.0),
			spawn_position + Vector2(-60.0, 80.0),
		]


func _find_spawn_settlement(
	record: Dictionary, noble: NobleData, allow_any: bool
) -> SettlementData:
	if _house_manager != null and _settlement_manager != null:
		var house_settlements: Array[SettlementData] = (
			_house_manager.get_house_settlements(noble.house_id)
		)
		house_settlements.sort_custom(
			func(a: SettlementData, b: SettlementData) -> bool:
				return a.settlement_id < b.settlement_id
		)
		for settlement: SettlementData in house_settlements:
			if settlement.owner_noble_id == noble.lord_id:
				return settlement
		if not house_settlements.is_empty():
			return house_settlements[0]
		# 无家族封地时，退回该贵族的任意封地。
		for settlement: SettlementData in _settlement_manager.get_all_settlements():
			if settlement != null and settlement.owner_noble_id == noble.lord_id:
				return settlement
	if allow_any:
		return _find_any_settlement()
	return null


func _find_any_settlement() -> SettlementData:
	if _settlement_manager == null:
		return null
	var settlements: Array[SettlementData] = _settlement_manager.get_all_settlements()
	if settlements.is_empty():
		return null
	settlements.sort_custom(
		func(a: SettlementData, b: SettlementData) -> bool:
			return a.settlement_id < b.settlement_id
	)
	return settlements[0]


func _settlement_name(settlement_id: String) -> String:
	if _settlement_manager == null or settlement_id.is_empty():
		return "未知地点"
	var settlement := _settlement_manager.get_settlement(settlement_id)
	return settlement.display_name if settlement != null else "未知地点"


# ---------------------------------------------------------------------------
# 序列化
# ---------------------------------------------------------------------------


func _sanitize_record(ransom_id: String, data: Dictionary) -> Dictionary:
	var record := {
		"ransom_id": ransom_id if not ransom_id.is_empty() \
			else str(data.get("ransom_id", "")),
		"noble_id": str(data.get("noble_id", "")),
		"noble_unit_id": str(data.get("noble_unit_id", "")),
		"house_id": str(data.get("house_id", "")),
		"house_name": str(data.get("house_name", "")),
		"lord_name": str(data.get("lord_name", "")),
		"party_id": str(data.get("party_id", "")),
		"party_name": str(data.get("party_name", "")),
		"sold_settlement_id": str(data.get("sold_settlement_id", "")),
		"sold_world_seconds": maxf(0.0, float(data.get("sold_world_seconds", 0.0))),
		"due_world_seconds": maxf(0.0, float(data.get("due_world_seconds", 0.0))),
		"ransom_gold": maxi(0, int(data.get("ransom_gold", 0))),
		"status": clampi(
			int(data.get("status", Status.INVALID)), Status.WAITING, Status.INVALID
		),
		"requested_world_seconds": float(data.get("requested_world_seconds", -1.0)),
		"accepted_world_seconds": float(data.get("accepted_world_seconds", -1.0)),
		"paid_gold": maxi(0, int(data.get("paid_gold", 0))),
		"invalid_reason": str(data.get("invalid_reason", "")),
	}
	if str(record["ransom_id"]).is_empty() or str(record["noble_id"]).is_empty() \
			or str(record["noble_unit_id"]).is_empty():
		return {}
	return record


func _dedupe_by_noble() -> void:
	var best_by_noble: Dictionary = {}
	for key: Variant in _records.keys():
		var record: Dictionary = _record_at(key)
		if record == null:
			continue
		var noble_id: String = str(record.get("noble_id", ""))
		if noble_id.is_empty():
			continue
		var current: Dictionary = _record_from(best_by_noble.get(noble_id))
		if current == null or float(record.get("sold_world_seconds", 0.0)) \
				>= float(current.get("sold_world_seconds", 0.0)):
			best_by_noble[noble_id] = record
	var kept: Dictionary = {}
	for key: Variant in best_by_noble:
		var record: Dictionary = _record_from(best_by_noble[key])
		kept[str(record.get("ransom_id", ""))] = record
	_records = kept


func _record_at(key: Variant) -> Dictionary:
	return _record_from(_records.get(key))


func _record_from(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value as Dictionary
	return {}


func _load_config() -> LordRansomConfig:
	if ResourceLoader.exists(CONFIG_PATH):
		var loaded := load(CONFIG_PATH) as LordRansomConfig
		if loaded != null:
			var copy := loaded.duplicate(true) as LordRansomConfig
			if copy != null:
				return copy
	return LordRansomConfig.create_default()


func _log(text: String, metadata: Dictionary) -> void:
	if _world_log_manager != null:
		_world_log_manager.add_event(WorldLogEntry.EventType.OTHER, text, metadata)
