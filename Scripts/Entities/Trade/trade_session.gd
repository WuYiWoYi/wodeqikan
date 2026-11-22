class_name TradeSession
extends RefCounted
## 一次未确认交易的预览状态（阶段 12）。
##
## - 打开市场时保存市场与玩家背包的完整快照；
## - 所有购买/出售操作只移动预览数据，不修改 MarketData、PlayerProfile 或任何存档；
## - 重置交易直接恢复打开时的快照，不做反向回放；
## - 确认交易时才把差异提交给 MarketManager，由它统一校验与结算。
##
## 马匹是独立实例：预览按 instance_id 移动具体个体，普通物品按数量移动。

var settlement_id: String = ""
var holder: Variant = null
var market_manager: MarketManager = null

var _market: MarketData = null
var _settlement_type: int = -1

## 预览中的市场 / 玩家普通物品数量。
var _market_counts: Dictionary = {}
var _player_counts: Dictionary = {}
## 预览中的市场 / 玩家马匹实例（保存具体个体，不复制马匹数据）。
var _market_mounts: Array[MountInstanceData] = []
var _player_mounts: Array[MountInstanceData] = []

## 打开交易时的快照，用于“重置交易”。
var _initial_market_counts: Dictionary = {}
var _initial_player_counts: Dictionary = {}
var _initial_market_mount_ids: Array[String] = []
var _initial_player_mount_ids: Array[String] = []

var _trade_serial: int = 0


func setup(
	p_market_manager: MarketManager,
	p_settlement_id: String,
	p_holder: Variant
) -> bool:
	market_manager = p_market_manager
	settlement_id = p_settlement_id
	holder = p_holder
	_trade_serial = 0
	return refresh_from_state()


## 打开界面或交易提交成功后，以真实数据重建预览。
func refresh_from_state() -> bool:
	_market = null
	_settlement_type = -1
	_market_counts.clear()
	_player_counts.clear()
	_market_mounts.clear()
	_player_mounts.clear()
	_initial_market_counts.clear()
	_initial_player_counts.clear()
	_initial_market_mount_ids.clear()
	_initial_player_mount_ids.clear()

	if market_manager == null or holder == null or settlement_id.is_empty():
		return false
	_market = market_manager.get_market(settlement_id)
	if _market == null:
		return false
	var settlement := market_manager.get_settlement(settlement_id)
	if settlement == null:
		return false
	_settlement_type = settlement.settlement_type

	for config: MarketGoodsConfig in market_manager.get_all_goods_configs():
		if config == null or not config.is_available_at(_settlement_type):
			continue
		var item_id: String = config.item_id
		if MountInstanceData.is_mount_item(item_id):
			_market_mounts.append_array(_market.get_mount_instances(item_id))
			_player_mounts.append_array(holder.get_mount_instances(item_id))
		else:
			_market_counts[item_id] = _market.get_stock(item_id)
			_player_counts[item_id] = int(holder.get_item_count(item_id))

	_initial_market_counts = _market_counts.duplicate(true)
	_initial_player_counts = _player_counts.duplicate(true)
	for instance: MountInstanceData in _market_mounts:
		_initial_market_mount_ids.append(instance.instance_id)
	for instance: MountInstanceData in _player_mounts:
		_initial_player_mount_ids.append(instance.instance_id)
	return true


func is_valid() -> bool:
	return _market != null


func get_settlement_type() -> int:
	return _settlement_type


# ---------------------------------------------------------------------------
# 预览查询
# ---------------------------------------------------------------------------


func get_market_count(item_id: String) -> int:
	if MountInstanceData.is_mount_item(item_id):
		return _count_mounts(_market_mounts, item_id)
	return maxi(0, int(_market_counts.get(item_id, 0)))


func get_player_count(item_id: String) -> int:
	if MountInstanceData.is_mount_item(item_id):
		return _count_mounts(_player_mounts, item_id)
	return maxi(0, int(_player_counts.get(item_id, 0)))


func get_market_mount_instances() -> Array[MountInstanceData]:
	return _market_mounts.duplicate()


func get_player_mount_instances() -> Array[MountInstanceData]:
	return _player_mounts.duplicate()


func get_market_mount_instances_for(item_id: String) -> Array[MountInstanceData]:
	var result: Array[MountInstanceData] = []
	for instance: MountInstanceData in _market_mounts:
		if instance != null and instance.equipment_id == item_id:
			result.append(instance)
	return result


func get_player_mount_instances_for(item_id: String) -> Array[MountInstanceData]:
	var result: Array[MountInstanceData] = []
	for instance: MountInstanceData in _player_mounts:
		if instance != null and instance.equipment_id == item_id:
			result.append(instance)
	return result


# ---------------------------------------------------------------------------
# 预览操作
# ---------------------------------------------------------------------------


## 市场 → 玩家。返回实际移动数量；马匹一次只能移动一匹。
func buy(item_id: String, amount: int = 1) -> int:
	if market_manager == null or _market == null or amount <= 0:
		return 0
	if MountInstanceData.is_mount_item(item_id):
		return buy_mount_instance(_first_mount_id(_market_mounts, item_id))
	var available: int = get_market_count(item_id)
	var moved: int = mini(amount, available)
	if moved <= 0:
		return 0
	_market_counts[item_id] = available - moved
	_player_counts[item_id] = get_player_count(item_id) + moved
	return moved


## 玩家 → 市场。返回实际移动数量；马匹一次只能移动一匹。
func sell(item_id: String, amount: int = 1) -> int:
	if market_manager == null or _market == null or amount <= 0:
		return 0
	if MountInstanceData.is_mount_item(item_id):
		return sell_mount_instance(_first_mount_id(_player_mounts, item_id))
	var available: int = get_player_count(item_id)
	var moved: int = mini(amount, available)
	if moved <= 0:
		return 0
	_player_counts[item_id] = available - moved
	_market_counts[item_id] = get_market_count(item_id) + moved
	return moved


## 购买指定市场马匹实例；不存在时返回 0。
func buy_mount_instance(instance_id: String) -> int:
	if instance_id.is_empty():
		return 0
	for index: int in range(_market_mounts.size()):
		var instance := _market_mounts[index]
		if instance != null and instance.instance_id == instance_id:
			_market_mounts.remove_at(index)
			_player_mounts.append(instance)
			return 1
	return 0


## 出售指定玩家马匹实例；不存在时返回 0。
func sell_mount_instance(instance_id: String) -> int:
	if instance_id.is_empty():
		return 0
	for index: int in range(_player_mounts.size()):
		var instance := _player_mounts[index]
		if instance != null and instance.instance_id == instance_id:
			_player_mounts.remove_at(index)
			_market_mounts.append(instance)
			return 1
	return 0


## 恢复打开交易时的预览；不触碰真实数据。
func reset() -> void:
	_market_counts = _initial_market_counts.duplicate(true)
	_player_counts = _initial_player_counts.duplicate(true)
	_market_mounts.clear()
	_player_mounts.clear()
	for instance_id: String in _initial_market_mount_ids:
		var instance := _find_actual_market_mount(instance_id)
		if instance != null:
			_market_mounts.append(instance)
	for instance_id: String in _initial_player_mount_ids:
		var instance: MountInstanceData = holder.get_mount_instance(instance_id)
		if instance != null:
			_player_mounts.append(instance)


# ---------------------------------------------------------------------------
# 差异与结算
# ---------------------------------------------------------------------------


## 需提交给 MarketManager 的普通物品购买数量（不含马匹）。
func get_purchase_counts() -> Dictionary:
	var result: Dictionary = {}
	for item_id: String in _initial_market_counts:
		if MountInstanceData.is_mount_item(item_id):
			continue
		var delta: int = int(_initial_market_counts.get(item_id, 0)) \
			- get_market_count(item_id)
		if delta > 0:
			result[item_id] = delta
	return result


## 需提交给 MarketManager 的普通物品出售数量（不含马匹）。
func get_sale_counts() -> Dictionary:
	var result: Dictionary = {}
	for item_id: String in _initial_player_counts:
		if MountInstanceData.is_mount_item(item_id):
			continue
		var delta: int = get_player_count(item_id) \
			- int(_initial_player_counts.get(item_id, 0))
		if delta > 0:
			result[item_id] = delta
	return result


## 购买的独立马匹实例 ID。
func get_purchase_mount_instance_ids() -> Array[String]:
	var result: Array[String] = []
	for instance: MountInstanceData in _player_mounts:
		if instance != null and not _initial_player_mount_ids.has(instance.instance_id):
			result.append(instance.instance_id)
	return result


## 出售的独立马匹实例 ID。
func get_sale_mount_instance_ids() -> Array[String]:
	var result: Array[String] = []
	for instance: MountInstanceData in _market_mounts:
		if instance != null and not _initial_market_mount_ids.has(instance.instance_id):
			result.append(instance.instance_id)
	return result


## 汇总预览购买（普通物品按数量、马匹按装备 ID 计数），供结果提示使用。
func get_purchase_items() -> Dictionary:
	var result: Dictionary = get_purchase_counts()
	var mount_ids: Array[String] = get_purchase_mount_instance_ids()
	for instance_id: String in mount_ids:
		var instance := _find_player_mount(instance_id)
		if instance != null:
			result[instance.equipment_id] = int(
				result.get(instance.equipment_id, 0)
			) + 1
	return result


func get_sale_items() -> Dictionary:
	var result: Dictionary = get_sale_counts()
	var mount_ids: Array[String] = get_sale_mount_instance_ids()
	for instance_id: String in mount_ids:
		var instance := _find_market_mount(instance_id)
		if instance != null:
			result[instance.equipment_id] = int(
				result.get(instance.equipment_id, 0)
			) + 1
	return result


func get_purchase_total() -> int:
	var total: int = 0
	var counts: Dictionary = get_purchase_counts()
	for item_id: String in counts:
		var config := market_manager.get_goods_config(item_id)
		if config != null:
			total += config.buy_price * int(counts[item_id])
	for instance_id: String in get_purchase_mount_instance_ids():
		var instance := _find_player_mount(instance_id)
		if instance == null:
			continue
		var config := market_manager.get_goods_config(instance.equipment_id)
		if config != null:
			total += config.buy_price
	return total


func get_sale_total() -> int:
	var total: int = 0
	var counts: Dictionary = get_sale_counts()
	for item_id: String in counts:
		var config := market_manager.get_goods_config(item_id)
		if config != null:
			total += config.sell_price * int(counts[item_id])
	for instance_id: String in get_sale_mount_instance_ids():
		var instance := _find_market_mount(instance_id)
		if instance == null:
			continue
		var config := market_manager.get_goods_config(instance.equipment_id)
		if config != null:
			total += config.sell_price
	return total


## 正数表示玩家需支付，负数表示玩家将获得金币。
func get_net_amount() -> int:
	return get_purchase_total() - get_sale_total()


func has_preview() -> bool:
	return not get_purchase_counts().is_empty() \
		or not get_sale_counts().is_empty() \
		or not get_purchase_mount_instance_ids().is_empty() \
		or not get_sale_mount_instance_ids().is_empty()


func is_confirm_enabled() -> bool:
	if not has_preview():
		return false
	var net: int = get_net_amount()
	if net <= 0:
		return true
	return int(holder.gold) >= net


func get_gold() -> int:
	return int(holder.gold) if holder != null else 0


func get_status_text() -> String:
	if not has_preview():
		return "点击左右两侧的按钮移动物品，确认后才会结算。"
	var purchase: int = get_purchase_total()
	var sale: int = get_sale_total()
	var net: int = purchase - sale
	var text: String = "买入 %d 金币，卖出 %d 金币" % [purchase, sale]
	if net > 0:
		text += "，需支付 %d 金币（持有 %d）" % [net, get_gold()]
		if get_gold() < net:
			text += " · 金币不足"
	elif net < 0:
		text += "，将获得 %d 金币" % absi(net)
	else:
		text += "，无需支付金币"
	return text


## 提交交易；成功后才修改真实数据并刷新预览。
func commit() -> Dictionary:
	if market_manager == null or not has_preview():
		return {
			"success": false,
			"error": "没有待确认的交易",
			"purchased_items": {},
			"sold_items": {},
			"purchase_total": 0,
			"sale_total": 0,
			"net_gold": 0,
			"gold_paid": 0,
			"gold_received": 0,
			"purchased_mount_instance_ids": [],
			"sold_mount_instance_ids": [],
		}
	_trade_serial += 1
	var trade_id: String = "trade_%s_%d_%d" % [
		settlement_id, Time.get_ticks_usec(), _trade_serial
	]
	var result: Dictionary = market_manager.execute_player_trade(
		settlement_id,
		get_purchase_counts(),
		get_sale_counts(),
		holder,
		trade_id,
		get_purchase_mount_instance_ids(),
		get_sale_mount_instance_ids()
	)
	if bool(result.get("success", false)):
		refresh_from_state()
	return result


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------


func _count_mounts(instances: Array[MountInstanceData], item_id: String) -> int:
	var count: int = 0
	for instance: MountInstanceData in instances:
		if instance != null and instance.equipment_id == item_id:
			count += 1
	return count


func _first_mount_id(instances: Array[MountInstanceData], item_id: String) -> String:
	for instance: MountInstanceData in instances:
		if instance != null and instance.equipment_id == item_id:
			return instance.instance_id
	return ""


func _find_market_mount(instance_id: String) -> MountInstanceData:
	for instance: MountInstanceData in _market_mounts:
		if instance != null and instance.instance_id == instance_id:
			return instance
	return null


func _find_player_mount(instance_id: String) -> MountInstanceData:
	for instance: MountInstanceData in _player_mounts:
		if instance != null and instance.instance_id == instance_id:
			return instance
	return null


## 重置交易时从真实市场数据找回初始马匹实例引用。
func _find_actual_market_mount(instance_id: String) -> MountInstanceData:
	if _market == null:
		return null
	return _market.get_mount_instance(instance_id)
