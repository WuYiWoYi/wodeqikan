class_name SupplyManager
extends RefCounted
## 部队每日补给统一结算（阶段 12）。
##
## 职责：
## - 统计士兵与马匹的每日面包/草料需求；
## - 按游戏日边界扣除玩家与 NPC 部队补给；
## - 提供剩余天数、缺粮/缺草料状态与目标储备采购量查询。
##
## 不负责市场交易、价格或路线决策；AI 通过本类查询需求后交给 MarketManager 结算。

const BREAD_ID: String = "bread"
const FODDER_ID: String = "fodder"
## 剩余天数低于该值视为低补给。
const LOW_SUPPLY_DAYS: float = 3.0
## NPC 采购时希望补充到的储备天数。
const TARGET_RESERVE_DAYS: float = 7.0
## 每日消耗为 0 时的剩余天数哨兵，避免除零。
const NO_CONSUMPTION_DAYS: float = 9999.0
const MAX_BACKFILL_DAYS: int = 3650

var last_settled_day: int = -1

var _party_manager: PartyManager = null
var _unit_manager: UnitManager = null
var _player_profile: PlayerProfile = null
var _player_party_id: String = ""
## { party_id: {"food": bool, "fodder": bool} }，只用于状态变化去重通知。
var _low_state: Dictionary = {}


func setup(
	party_manager: PartyManager,
	unit_manager: UnitManager,
	player_profile: PlayerProfile,
	player_party_id: String = ""
) -> void:
	_party_manager = party_manager
	_unit_manager = unit_manager
	_player_profile = player_profile
	_player_party_id = player_party_id


func set_player_party_id(party_id: String) -> void:
	_player_party_id = party_id


## 新世界/读档完成后调用：以当前游戏日作为结算起点，避免开局立刻扣粮。
func reset_settlement_day(day: int = -1) -> void:
	last_settled_day = (
		int(TimeManager.get_date_parts()["total_days"]) if day < 0 else day
	)
	_low_state.clear()


## 返回部队物品持有者：玩家部队使用 PlayerProfile，NPC 使用 PartyData 自身。
func get_holder(party: PartyData) -> Variant:
	if party == null:
		return null
	if _is_player_party(party):
		return _player_profile if _player_profile != null else party
	return party


func _is_player_party(party: PartyData) -> bool:
	if party == null:
		return false
	return party.is_player_controlled() or (
		not _player_party_id.is_empty() and party.party_id == _player_party_id
	)


# ---------------------------------------------------------------------------
# 需求与状态
# ---------------------------------------------------------------------------


## 有效成员数：仍在部队且未阵亡的士兵。
func get_member_count(party: PartyData) -> int:
	if party == null or _unit_manager == null:
		return 0
	var count: int = 0
	for unit_id: String in party.member_unit_ids:
		var unit := _unit_manager.get_unit(unit_id)
		if unit != null and unit.current_hp > 0:
			count += 1
	return count


## 已装备在士兵身上的马匹数量。
func get_equipped_mount_count(party: PartyData) -> int:
	if party == null or _unit_manager == null:
		return 0
	var mount_slot: String = EquipmentConfig.SLOT_NAMES[EquipmentConfig.Slot.MOUNT]
	var count: int = 0
	for unit_id: String in party.member_unit_ids:
		var unit := _unit_manager.get_unit(unit_id)
		if unit != null and unit.current_hp > 0 and unit.equipment.has(mount_slot):
			count += 1
	return count


## 部队拥有的马匹总数 = 已装备 + 背包中未装备的独立马匹实例。
func get_total_mount_count(party: PartyData) -> int:
	var holder: Variant = get_holder(party)
	var backpack_count: int = 0
	if holder != null and holder.has_method("get_mount_count"):
		backpack_count = int(holder.get_mount_count(""))
	return get_equipped_mount_count(party) + backpack_count


## 部队补给状态查询；UI 与 AI 共用同一结果。
func get_status(party: PartyData) -> Dictionary:
	var holder: Variant = get_holder(party)
	var bread_count: int = 0
	var fodder_count: int = 0
	if holder != null:
		bread_count = int(holder.get_item_count(BREAD_ID))
		fodder_count = int(holder.get_item_count(FODDER_ID))
	var daily_bread: int = get_member_count(party)
	var daily_fodder: int = get_total_mount_count(party)
	var food_days: float = (
		float(bread_count) / float(daily_bread)
		if daily_bread > 0 else NO_CONSUMPTION_DAYS
	)
	var fodder_days: float = (
		float(fodder_count) / float(daily_fodder)
		if daily_fodder > 0 else NO_CONSUMPTION_DAYS
	)
	return {
		"bread_count": bread_count,
		"fodder_count": fodder_count,
		"daily_bread_consumption": daily_bread,
		"daily_fodder_consumption": daily_fodder,
		"food_days_remaining": food_days,
		"fodder_days_remaining": fodder_days,
		"is_food_low": daily_bread > 0 and food_days <= LOW_SUPPLY_DAYS,
		"is_fodder_low": daily_fodder > 0 and fodder_days <= LOW_SUPPLY_DAYS,
		"bread_shortage": int(party.supply_bread_shortage) if party != null else 0,
		"fodder_shortage": int(party.supply_fodder_shortage) if party != null else 0,
	}


func has_low_supply(party: PartyData) -> bool:
	var status := get_status(party)
	return bool(status["is_food_low"]) or bool(status["is_fodder_low"])


## 为把补给补到 TARGET_RESERVE_DAYS 天所需的采购数量。
func get_purchase_needs(party: PartyData) -> Dictionary:
	var status := get_status(party)
	var daily_bread: int = int(status["daily_bread_consumption"])
	var daily_fodder: int = int(status["daily_fodder_consumption"])
	var target_bread: int = int(ceil(float(daily_bread) * TARGET_RESERVE_DAYS))
	var target_fodder: int = int(ceil(float(daily_fodder) * TARGET_RESERVE_DAYS))
	var needs: Dictionary = {}
	var bread_need: int = maxi(0, target_bread - int(status["bread_count"]))
	var fodder_need: int = maxi(0, target_fodder - int(status["fodder_count"]))
	if bread_need > 0:
		needs[BREAD_ID] = bread_need
	if fodder_need > 0:
		needs[FODDER_ID] = fodder_need
	return needs


# ---------------------------------------------------------------------------
# 每日结算
# ---------------------------------------------------------------------------


## 由 WorldSimulation 每个世界 tick 调用。只在游戏日边界结算，暂停/倍速安全。
func update_daily() -> void:
	var today: int = int(TimeManager.get_date_parts()["total_days"])
	if last_settled_day < 0:
		last_settled_day = today
		return
	if today <= last_settled_day:
		return

	var guard: int = 0
	while last_settled_day < today and guard < MAX_BACKFILL_DAYS:
		last_settled_day += 1
		_settle_all_parties()
		guard += 1
	if guard >= MAX_BACKFILL_DAYS:
		last_settled_day = today
	_emit_status_changes()


func _settle_all_parties() -> void:
	if _party_manager == null:
		return
	for party: PartyData in _party_manager.get_all_parties():
		if party == null or party.member_unit_ids.is_empty():
			continue
		settle_party(party)


## 单支部队每日结算；返回实际消耗与缺口。数量永远不会变成负数。
func settle_party(party: PartyData) -> Dictionary:
	var result: Dictionary = {
		"bread_consumed": 0,
		"fodder_consumed": 0,
		"bread_shortage": 0,
		"fodder_shortage": 0,
	}
	var holder: Variant = get_holder(party)
	if holder == null:
		return result

	var bread_need: int = get_member_count(party)
	var fodder_need: int = get_total_mount_count(party)
	var bread_available: int = int(holder.get_item_count(BREAD_ID))
	var fodder_available: int = int(holder.get_item_count(FODDER_ID))
	var bread_consumed: int = mini(bread_need, bread_available)
	var fodder_consumed: int = mini(fodder_need, fodder_available)
	if bread_consumed > 0:
		holder.remove_item(BREAD_ID, bread_consumed)
	if fodder_consumed > 0:
		holder.remove_item(FODDER_ID, fodder_consumed)

	party.supply_bread_shortage = maxi(0, bread_need - bread_consumed)
	party.supply_fodder_shortage = maxi(0, fodder_need - fodder_consumed)
	result["bread_consumed"] = bread_consumed
	result["fodder_consumed"] = fodder_consumed
	result["bread_shortage"] = party.supply_bread_shortage
	result["fodder_shortage"] = party.supply_fodder_shortage
	return result


## 只在低补给状态发生变化时广播，避免每个 tick 重复提示。
func _emit_status_changes() -> void:
	if _party_manager == null:
		return
	for party: PartyData in _party_manager.get_all_parties():
		if party == null or party.member_unit_ids.is_empty():
			continue
		var status := get_status(party)
		var food_low: bool = bool(status["is_food_low"])
		var fodder_low: bool = bool(status["is_fodder_low"])
		var previous: Dictionary = _low_state.get(party.party_id, {})
		var changed: bool = (
			bool(previous.get("food", false)) != food_low
			or bool(previous.get("fodder", false)) != fodder_low
		)
		_low_state[party.party_id] = {"food": food_low, "fodder": fodder_low}
		if changed:
			EventBus.party_supply_changed.emit(party.party_id, food_low, fodder_low)
