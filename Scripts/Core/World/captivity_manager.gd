class_name CaptivityManager
extends RefCounted
## 俘虏恢复与玩家被俘/逃脱的唯一结算入口。
##
## 规则：
## - 所有部队持有的俘虏按游戏小时独立恢复生命值，不占用伤兵治疗名额；
## - 玩家角色在战败后成为胜利方的真实俘虏，原部队失去控制；
## - 玩家俘虏满血后，WorldSimulation 每个配置间隔进行一次逃脱判定；
## - 逃脱成功后移除俘虏归属，并把玩家角色作为唯一成员放回玩家部队，
##   位置取押送部队附近的合法、不重叠坐标；
## - 逃脱保护期按世界时间自然到期，AI 主动攻击入口统一查询本管理器。
##
## 本类只修改 UnitData/PartyData 的俘虏、HP、位置与部队状态，
## 不创建场景节点，也不处理 UI。

const CONFIG_PATH: String = "res://Data/Combat/captivity_config.tres"
const SECONDS_PER_GAME_HOUR: float = 6.0
## 逃脱落点与押送部队的最小距离，以及尝试半径。
const ESCAPE_MIN_DISTANCE: float = 42.0
const ESCAPE_PARTY_GAP: float = 30.0
const ESCAPE_RADIUS_STEPS: Array[float] = [42.0, 70.0, 100.0, 140.0, 190.0]

var player_captive: bool = false
var captor_party_id: String = ""
## 上次完成俘虏治疗结算的游戏小时（-1 = 尚未初始化，不补发历史治疗）。
var prisoner_healing_last_hour: int = -1
## 上次逃脱判定的游戏小时；玩家未满血时持续跟随当前小时。
var escape_check_last_hour: int = -1
## 逃脱保护截止世界时间（TimeManager.world_elapsed_seconds）。
var escape_protection_until: float = 0.0

var _unit_manager: UnitManager = null
var _party_manager: PartyManager = null
var _world_map_manager: WorldMapManager = null
var _player_party_id: String = ""
var _config: CaptivityConfig = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func setup(
	unit_manager: UnitManager,
	party_manager: PartyManager,
	world_map_manager: WorldMapManager,
	config: CaptivityConfig = null
) -> void:
	_unit_manager = unit_manager
	_party_manager = party_manager
	_world_map_manager = world_map_manager
	set_config(config)
	_rng.randomize()


func set_config(config: CaptivityConfig) -> void:
	if config != null:
		_config = config
	elif _config == null:
		_config = _load_config()
	_config.sanitize()


func get_config() -> CaptivityConfig:
	return _config


func set_player_party_id(party_id: String) -> void:
	_player_party_id = party_id


func get_captor_party_id() -> String:
	return captor_party_id


func is_player_captive() -> bool:
	return player_captive


func is_player_protected() -> bool:
	return TimeManager.world_elapsed_seconds < escape_protection_until


func get_escape_protection_until() -> float:
	return escape_protection_until


func get_current_hour() -> int:
	return int(floor(TimeManager.world_elapsed_seconds / SECONDS_PER_GAME_HOUR))


# ---------------------------------------------------------------------------
# 世界 tick
# ---------------------------------------------------------------------------


## 仅由 WorldSimulation 的 WorldTime tick 调用。
func on_world_tick(_fixed_delta: float) -> void:
	_settle_prisoner_healing()
	_check_player_escape()


func _settle_prisoner_healing() -> void:
	var current_hour: int = get_current_hour()
	if prisoner_healing_last_hour < 0:
		prisoner_healing_last_hour = current_hour
		return
	if current_hour <= prisoner_healing_last_hour:
		return
	var hours: int = current_hour - prisoner_healing_last_hour
	prisoner_healing_last_hour = current_hour
	if _config == null or _config.prisoner_healing_per_hour <= 0 \
			or _party_manager == null or _unit_manager == null:
		return
	# 每名俘虏独立获得治疗；不能按部队共享点数，否则列表靠后的玩家角色
	# 会被其他俘虏长期挤占，导致满血逃脱几乎无法发生。
	var points: int = _config.prisoner_healing_per_hour * hours
	for party: PartyData in _party_manager.get_all_parties():
		heal_party_prisoners(party, points)


## 每名俘虏独立恢复 points 点生命值（不共享点数），返回实际恢复总量。
## 玩家角色与普通俘虏使用同一条规则，但互不抢占治疗点数。
func heal_party_prisoners(party: PartyData, points: int) -> int:
	if party == null or points <= 0 or _unit_manager == null:
		return 0
	var used: int = 0
	for unit_id: String in party.prisoner_unit_ids:
		var unit := _unit_manager.get_unit(unit_id)
		if unit == null or unit.is_dead():
			continue
		var missing: int = maxi(0, unit.max_hp - unit.current_hp)
		if missing <= 0:
			continue
		var applied: int = mini(points, missing)
		unit.current_hp += applied
		unit.clamp_hp()
		used += applied
	return used


func _check_player_escape() -> void:
	if not player_captive:
		return
	var unit := find_player_unit()
	if unit == null or unit.is_dead():
		_clear_captive_state()
		return
	var party := _party_manager.get_party(captor_party_id) \
		if _party_manager != null else null
	# 押送部队被消灭/解散后俘虏归属会被清除：直接视为获释。
	if party == null or not unit.is_prisoner() \
			or unit.prisoner_owner_party_id != captor_party_id:
		liberate_player("captor_gone")
		return

	var current_hour: int = get_current_hour()
	if escape_check_last_hour < 0:
		escape_check_last_hour = current_hour
	# 未满血时不进行判定，并把检查点保持在当前小时，
	# 保证满血后还需要至少一个完整间隔才尝试逃脱。
	if unit.current_hp < unit.max_hp:
		escape_check_last_hour = current_hour
		return
	if _config == null:
		return
	var interval: int = maxi(1, int(ceil(_config.escape_check_interval_hours)))
	while current_hour - escape_check_last_hour >= interval:
		escape_check_last_hour += interval
		if _rng.randf() < _config.escape_chance:
			escape_player()
			return


# ---------------------------------------------------------------------------
# 被俘状态同步
# ---------------------------------------------------------------------------


## 战斗结算后/读档后调用：以“玩家角色是否被某部队关押”为唯一事实来源。
func sync_player_capture() -> void:
	if _party_manager == null or _unit_manager == null:
		return
	var unit := find_player_unit()
	if unit == null or unit.is_dead():
		_clear_captive_state()
		return
	if unit.is_prisoner() and not unit.prisoner_owner_party_id.is_empty():
		var owner_id: String = unit.prisoner_owner_party_id
		if _party_manager.get_party(owner_id) == null:
			liberate_player("captor_gone")
			return
		if not player_captive or captor_party_id != owner_id:
			_begin_capture(owner_id)
		else:
			_disable_player_party()
		return
	# 玩家已不是俘虏（被释放/押送部队消失）：恢复玩家部队。
	if player_captive:
		liberate_player("released")


func find_player_unit() -> UnitData:
	if _unit_manager == null:
		return null
	for unit: UnitData in _unit_manager.get_all_units():
		if unit != null and unit.is_player_character:
			return unit
	return null


func _begin_capture(owner_id: String) -> void:
	player_captive = true
	captor_party_id = owner_id
	escape_check_last_hour = get_current_hour()
	_disable_player_party()


func _disable_player_party() -> void:
	var party := _party_manager.get_party(_player_party_id) \
		if _party_manager != null else null
	if party == null:
		return
	party.battle_state = PartyData.BattleState.DISABLED
	party.movement_state = PartyData.MovementState.IDLE
	party.target_position = party.world_position
	party.current_order = PartyData.OrderType.NONE
	party.current_target_id = ""
	party.attack_intent = false
	party.focus_party_id = ""
	party.battle_response_id = ""
	party.battle_response_until = 0.0


## 逃脱成功：满血恢复、清空俘虏归属、重建单成员玩家部队并进入保护期。
func escape_player() -> bool:
	if not player_captive:
		return false
	var unit := find_player_unit()
	if unit == null or unit.is_dead():
		_clear_captive_state()
		return false
	unit.status = UnitData.Status.ACTIVE
	unit.current_hp = unit.max_hp
	return _restore_player_party(unit, true)


## 非主动逃脱（押送者消失/被释放）：保留当前 HP，但至少保证存活。
func liberate_player(_reason: String) -> bool:
	if not player_captive:
		return false
	var unit := find_player_unit()
	if unit == null or unit.is_dead():
		_clear_captive_state()
		return false
	if unit.current_hp <= 0:
		unit.current_hp = 1
	unit.status = UnitData.Status.ACTIVE
	return _restore_player_party(unit, false)


func _restore_player_party(unit: UnitData, full_heal: bool) -> bool:
	if _party_manager == null:
		return false
	var captor := _party_manager.get_party(captor_party_id)
	var origin: Vector2 = captor.world_position if captor != null \
		else Vector2.ZERO
	if not captor_party_id.is_empty():
		_party_manager.remove_prisoner(captor_party_id, unit.unit_id)
	unit.clear_prisoner_ownership()
	if full_heal:
		unit.current_hp = unit.max_hp
	unit.status = UnitData.Status.ACTIVE

	var party := _party_manager.get_party(_player_party_id)
	if party == null:
		# 正常情况下玩家部队作为身份锚点始终保留；这里仅做防御性处理，
		# 不创建第二支玩家部队。
		push_error(
			"CaptivityManager: 玩家部队不存在，无法恢复控制: %s"
			% _player_party_id
		)
		_clear_captive_state()
		return false

	if unit.current_party_id != party.party_id:
		if not _party_manager.add_member(party.party_id, unit.unit_id):
			push_error(
				"CaptivityManager: 玩家角色无法重新加入玩家部队: %s"
				% unit.unit_id
			)
			return false
	party.leader_unit_id = unit.unit_id
	party.control_type = PartyData.ControlType.PLAYER
	party.battle_state = PartyData.BattleState.AVAILABLE
	party.movement_state = PartyData.MovementState.IDLE
	party.current_order = PartyData.OrderType.NONE
	party.current_target_id = ""
	party.attack_intent = false
	party.focus_party_id = ""
	party.battle_response_id = ""
	party.battle_response_until = 0.0

	var escape_position := _find_escape_position(origin)
	party.world_position = escape_position
	party.target_position = escape_position
	party.engagement_cooldown_until = TimeManager.world_elapsed_seconds

	var protection_seconds: float = 0.0
	if _config != null:
		protection_seconds = _config.escape_protection_hours * SECONDS_PER_GAME_HOUR
	escape_protection_until = maxf(
		escape_protection_until,
		TimeManager.world_elapsed_seconds + protection_seconds
	)
	escape_check_last_hour = get_current_hour()
	player_captive = false
	captor_party_id = ""
	_disable_other_members(party, unit.unit_id)
	return true


## 玩家部队按规则只包含玩家角色；异常残留的其他成员不删除数据，
## 只从玩家部队移出，避免“逃脱后自动恢复原有士兵”。
func _disable_other_members(party: PartyData, player_unit_id: String) -> void:
	var ids: Array[String] = party.member_unit_ids.duplicate()
	for unit_id: String in ids:
		if unit_id == player_unit_id:
			continue
		_party_manager.remove_member(party.party_id, unit_id)


func _find_escape_position(origin: Vector2) -> Vector2:
	var bounds: Rect2 = Rect2()
	if _world_map_manager != null:
		bounds = _world_map_manager.world_bounds
	var margin: float = 20.0
	var candidates: Array[Vector2] = []
	for radius: float in ESCAPE_RADIUS_STEPS:
		for index: int in range(12):
			var angle: float = TAU * float(index) / 12.0
			candidates.append(
				origin + Vector2(cos(angle), sin(angle)) * radius
			)
	for candidate: Vector2 in candidates:
		var position := candidate
		if bounds.size != Vector2.ZERO:
			position.x = clampf(
				position.x, bounds.position.x + margin, bounds.end.x - margin
			)
			position.y = clampf(
				position.y, bounds.position.y + margin, bounds.end.y - margin
			)
		if position.distance_to(origin) < ESCAPE_MIN_DISTANCE * 0.5:
			continue
		if _is_position_free(position):
			return position
	var fallback := origin + Vector2(ESCAPE_MIN_DISTANCE, 0.0)
	if bounds.size != Vector2.ZERO:
		fallback.x = clampf(
			fallback.x, bounds.position.x + margin, bounds.end.x - margin
		)
		fallback.y = clampf(
			fallback.y, bounds.position.y + margin, bounds.end.y - margin
		)
	return fallback


func _is_position_free(position: Vector2) -> bool:
	if _party_manager == null:
		return true
	for party: PartyData in _party_manager.get_all_parties():
		if party == null or party.party_id == _player_party_id:
			continue
		if party.member_unit_ids.is_empty():
			continue
		if party.world_position.distance_to(position) < ESCAPE_PARTY_GAP:
			return false
	return true


func _clear_captive_state() -> void:
	player_captive = false
	captor_party_id = ""


# ---------------------------------------------------------------------------
# 存档
# ---------------------------------------------------------------------------


func to_dict() -> Dictionary:
	return {
		"is_player_captive": player_captive,
		"captor_party_id": captor_party_id,
		"prisoner_healing_last_hour": prisoner_healing_last_hour,
		"escape_check_last_hour": escape_check_last_hour,
		"escape_protection_until": escape_protection_until,
	}


## 读档时按存档推进时间恢复结算点；缺失时以存档时刻为起点，避免补发历史治疗。
func load_from_dict(data: Dictionary, world_elapsed_seconds: float) -> void:
	var current_hour: int = int(floor(world_elapsed_seconds / SECONDS_PER_GAME_HOUR))
	player_captive = bool(data.get("is_player_captive", false))
	captor_party_id = str(data.get("captor_party_id", ""))
	if not player_captive:
		captor_party_id = ""
	prisoner_healing_last_hour = int(
		data.get("prisoner_healing_last_hour", -1)
	)
	if prisoner_healing_last_hour < 0:
		prisoner_healing_last_hour = current_hour
	escape_check_last_hour = int(data.get("escape_check_last_hour", -1))
	if escape_check_last_hour < 0:
		escape_check_last_hour = current_hour
	escape_protection_until = maxf(
		0.0, float(data.get("escape_protection_until", 0.0))
	)


## 读档实体恢复后校正被俘状态：不信任过期的押送部队/归属引用。
func validate_after_load() -> void:
	sync_player_capture()


func _load_config() -> CaptivityConfig:
	if ResourceLoader.exists(CONFIG_PATH):
		var loaded := load(CONFIG_PATH) as CaptivityConfig
		if loaded != null:
			# 每个管理器持有独立副本，允许测试/未来系统调整而不污染全局资源。
			var copy := loaded.duplicate(true) as CaptivityConfig
			if copy != null:
				return copy
	return CaptivityConfig.new()
