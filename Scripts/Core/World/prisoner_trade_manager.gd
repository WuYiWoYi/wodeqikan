class_name PrisonerTradeManager
extends RefCounted
## 俘虏出售的唯一业务入口（阶段 13 Step 6）。
##
## 规则：
## - 只允许出售调用方部队当前关押的俘虏，不允许出售其他部队的俘虏；
## - 士兵价格只由 PrisonerPriceConfig 按兵种 tier 计算，NPC 领主统一 100；
## - 采用“全部校验后一次性提交”，任意一项失败都不产生部分交易；
## - 出售后 Unit 保留身份但清除部队/俘虏归属，并记录出售地点，
##   进入明确的“离开玩家控制”状态；
## - NPC 领主出售后交给 LordRansomManager 启动家族赎回等待流程。

const PRICE_CONFIG_PATH: String = "res://Data/Settlements/prisoner_price_config.tres"

var _party_manager: PartyManager = null
var _unit_manager: UnitManager = null
var _player_profile: PlayerProfile = null
var _config: PrisonerPriceConfig = null
## 可选：NPC 领主出售后的赎回流程入口；普通士兵不经过它。
var _ransom_manager: LordRansomManager = null


func setup(
	party_manager: PartyManager,
	unit_manager: UnitManager,
	player_profile: PlayerProfile,
	config: PrisonerPriceConfig = null,
	ransom_manager: LordRansomManager = null
) -> void:
	_party_manager = party_manager
	_unit_manager = unit_manager
	_player_profile = player_profile
	_ransom_manager = ransom_manager
	_config = config if config != null else _load_config()
	_config.sanitize()


func set_config(config: PrisonerPriceConfig) -> void:
	_config = config if config != null else PrisonerPriceConfig.create_default()
	_config.sanitize()


## 统一售价入口：NPC 领主固定价，普通士兵按兵种 tier 定价。
## UI 与出售逻辑都必须走这里，不得自行判断价格。
func get_sell_price(unit: UnitData) -> int:
	if unit == null or _config == null:
		return 0
	if unit.is_noble_lord():
		return _config.get_lord_price()
	return _config.get_price_for_tier(_get_unit_tier(unit))


func get_price_for_tier(tier: int) -> int:
	if _config == null:
		return 0
	return _config.get_price_for_tier(tier)


func get_lord_price() -> int:
	if _config == null:
		return 0
	return _config.get_lord_price()


## 原子出售。unit_ids 必须全部属于 party_id 的俘虏列表。
## 返回 { success, gold, sold_unit_ids, reason }。
func sell_prisoners(
	party_id: String, unit_ids: Array, settlement_id: String
) -> Dictionary:
	var result := {
		"success": false,
		"gold": 0,
		"sold_unit_ids": [] as Array[String],
		"reason": "",
	}
	if _party_manager == null or _unit_manager == null:
		result["reason"] = "交易系统未初始化"
		return result
	var party := _party_manager.get_party(party_id)
	if party == null:
		result["reason"] = "部队不存在"
		return result
	if settlement_id.is_empty():
		result["reason"] = "缺少出售地点"
		return result

	# 先完整校验，避免中途失败造成部分出售。
	var unique_ids: Array[String] = []
	var units: Array[UnitData] = []
	var total_gold: int = 0
	for value: Variant in unit_ids:
		var unit_id: String = str(value)
		if unit_id.is_empty() or unique_ids.has(unit_id):
			continue
		var unit := _unit_manager.get_unit(unit_id)
		if unit == null:
			result["reason"] = "单位不存在: %s" % unit_id
			return result
		if unit.prisoner_owner_party_id != party_id \
				or not party.prisoner_unit_ids.has(unit_id):
			result["reason"] = "单位不是该部队的俘虏: %s" % unit_id
			return result
		if not unit.current_party_id.is_empty() or party.member_unit_ids.has(unit_id):
			result["reason"] = "俘虏同时是部队成员: %s" % unit_id
			return result
		var price: int = get_sell_price(unit)
		if price <= 0:
			result["reason"] = "单位没有有效出售价格: %s" % unit_id
			return result
		unique_ids.append(unit_id)
		units.append(unit)
		total_gold += price

	if unique_ids.is_empty():
		result["reason"] = "没有选择俘虏"
		return result

	# 所有校验通过后一次性提交。
	if _player_profile != null:
		_player_profile.add_gold(total_gold)
	for unit: UnitData in units:
		if not _party_manager.remove_prisoner(party_id, unit.unit_id):
			# remove_prisoner 失败在完成校验后几乎不可达；保持防御式处理。
			push_error("出售俘虏时移除归属失败: %s" % unit.unit_id)
		unit.mark_sold(settlement_id)
		# 普通士兵到此结束；NPC 领主交给赎回流程登记出售状态并启动等待。
		if _ransom_manager != null and unit.is_noble_lord():
			_ransom_manager.on_lord_sold(unit, settlement_id)

	result["success"] = true
	result["gold"] = total_gold
	result["sold_unit_ids"] = unique_ids
	return result


func _get_unit_tier(unit: UnitData) -> int:
	if _unit_manager != null:
		var config := _unit_manager.get_unit_config(unit.config_id)
		if config != null:
			return maxi(1, config.tier)
	return 1


func _load_config() -> PrisonerPriceConfig:
	if ResourceLoader.exists(PRICE_CONFIG_PATH):
		var loaded := load(PRICE_CONFIG_PATH) as PrisonerPriceConfig
		if loaded != null:
			var copy := loaded.duplicate(true) as PrisonerPriceConfig
			if copy != null:
				return copy
	return PrisonerPriceConfig.create_default()
