class_name MarketManager
extends RefCounted
## 村庄/城镇市场的库存与交易业务入口。
##
## - 市场库存按地点独立保存；村庄只卖补给，城镇卖补给与马匹，城堡没有市场。
## - 普通商品按数量堆叠；马匹按 MarketData.mount_instances 独立保存。
## - UI 只提交交易预览，真正修改金币/物品/库存必须经过本管理器。
## - 交易执行前完成全部校验，提交阶段失败会回滚到交易前快照。
## - 只有玩家来源的交易写入世界日志；NPC 交易不写玩家日志。

enum TradeSource {
	PLAYER,
	NPC,
}

const MAX_SUBMITTED_TRADE_IDS: int = 256
## 1 游戏日 = 48 世界秒（1 世界秒 = 30 游戏分钟）。
const SECONDS_PER_GAME_DAY: float = 48.0
## 一次性跨越多日时最多补算的天数，避免异常时间导致长时间循环。
const MAX_DAILY_PRODUCTION_DAYS: int = 3650

var last_error: String = ""

var _goods: Dictionary = {}
## { settlement_id: MarketData }
var _markets: Dictionary = {}
## 已提交的交易 ID，防止同一笔交易被重复结算。
var _submitted_trade_ids: Dictionary = {}
var _submitted_trade_order: Array[String] = []

var _settlement_manager: SettlementManager = null
var _unit_manager: UnitManager = null
var _item_manager: ItemManager = null
var _world_log_manager: WorldLogManager = null


func setup(
	settlement_manager: SettlementManager,
	unit_manager: UnitManager,
	item_manager: ItemManager,
	world_log_manager: WorldLogManager
) -> void:
	_settlement_manager = settlement_manager
	_unit_manager = unit_manager
	_item_manager = item_manager
	_world_log_manager = world_log_manager


# ---------------------------------------------------------------------------
# 静态商品配置
# ---------------------------------------------------------------------------


## 注册商品配置。item_id 必须能关联到已注册的装备或普通物品。
func register_goods_config(config: MarketGoodsConfig) -> bool:
	if config == null or not config.validate():
		return false
	var item_id: String = config.item_id.strip_edges()
	if _goods.has(item_id):
		push_error("MarketGoodsConfig 重复注册，拒绝覆盖: %s" % item_id)
		return false
	if not has_trade_item(item_id):
		push_error("MarketGoodsConfig 引用了未知物品 ID: %s" % item_id)
		return false
	_goods[item_id] = config.duplicate_config()
	return true


func has_trade_item(item_id: String) -> bool:
	if item_id.is_empty():
		return false
	if _unit_manager != null and _unit_manager.has_equipment_config(item_id):
		return true
	if _item_manager != null and _item_manager.has_item_config(item_id):
		return true
	return false


func get_goods_config(item_id: String) -> MarketGoodsConfig:
	return _goods.get(item_id) as MarketGoodsConfig


func has_goods_config(item_id: String) -> bool:
	return _goods.has(item_id)


## 稳定排序，避免 UI 每次刷新顺序跳动。
func get_all_goods_configs() -> Array[MarketGoodsConfig]:
	var result: Array[MarketGoodsConfig] = []
	for value: Variant in _goods.values():
		var config := value as MarketGoodsConfig
		if config != null:
			result.append(config)
	result.sort_custom(func(a: MarketGoodsConfig, b: MarketGoodsConfig) -> bool:
		return a.item_id < b.item_id
	)
	return result


## 指定地点实际提供的商品配置（村庄/城镇范围不同）。
func get_goods_configs_for_settlement(
	settlement_id: String
) -> Array[MarketGoodsConfig]:
	var result: Array[MarketGoodsConfig] = []
	if _settlement_manager == null:
		return result
	var settlement := _settlement_manager.get_settlement(settlement_id)
	if settlement == null:
		return result
	for config: MarketGoodsConfig in get_all_goods_configs():
		if is_goods_available_at(config, settlement):
			result.append(config)
	return result


## 商品显示名；优先读取装备配置，其次普通物品配置，最后回退为 ID。
func get_item_display_name(item_id: String) -> String:
	if _unit_manager != null:
		var equipment := _unit_manager.get_equipment_config(item_id)
		if equipment != null:
			return equipment.display_name
	if _item_manager != null:
		var item := _item_manager.get_item_config(item_id)
		if item != null:
			return item.display_name
	return item_id if not item_id.is_empty() else "未知物品"


func get_item_icon_path(item_id: String) -> String:
	# 商品配置可覆盖图标（马匹没有 ItemConfig）；否则回退普通物品图标。
	var goods := get_goods_config(item_id)
	if goods != null and not goods.icon_texture_path.strip_edges().is_empty():
		return goods.icon_texture_path.strip_edges()
	if _item_manager != null:
		var item := _item_manager.get_item_config(item_id)
		if item != null:
			return item.get_icon_path()
	return ""


func is_mount_item(item_id: String) -> bool:
	return MountInstanceData.is_mount_item(item_id)


# ---------------------------------------------------------------------------
# 市场库存
# ---------------------------------------------------------------------------


func get_market(settlement_id: String) -> MarketData:
	return _markets.get(settlement_id) as MarketData


func get_settlement(settlement_id: String) -> SettlementData:
	if _settlement_manager == null:
		return null
	return _settlement_manager.get_settlement(settlement_id)


func get_stock(settlement_id: String, item_id: String) -> int:
	var market := get_market(settlement_id)
	return market.get_stock(item_id) if market != null else 0


## 村庄与城镇提供市场；城堡永远没有市场。
func is_market_settlement(settlement: SettlementData) -> bool:
	if settlement == null:
		return false
	return settlement.settlement_type == SettlementData.SettlementType.VILLAGE \
		or settlement.settlement_type == SettlementData.SettlementType.TOWN


# ---------------------------------------------------------------------------
# 村庄库存配置与查询
# ---------------------------------------------------------------------------


## 只有村庄参与动态库存上限与每日补货；城镇保持静态初始库存与市场规则。
func is_village_settlement(settlement: SettlementData) -> bool:
	return settlement != null \
		and settlement.settlement_type == SettlementData.SettlementType.VILLAGE


func get_village_households(settlement_id: String) -> int:
	var settlement := get_settlement(settlement_id)
	return maxi(0, settlement.households) if is_village_settlement(settlement) else 0


func get_village_specialty_item_ids(settlement_id: String) -> Array[String]:
	var result: Array[String] = []
	var settlement := get_settlement(settlement_id)
	if is_village_settlement(settlement):
		result.append_array(settlement.village_specialty_item_ids)
	return result


func is_village_specialty(settlement_id: String, item_id: String) -> bool:
	var settlement := get_settlement(settlement_id)
	return is_village_settlement(settlement) \
		and settlement.is_village_specialty(item_id)


## 村庄目标库存与动态上限一致：每日补货按上限的固定比例增加，
## 不再使用“缺口比例”模型。
func get_village_stock_target(settlement_id: String, item_id: String) -> int:
	return get_village_stock_max(settlement_id, item_id)


## 动态库存上限 = (特产每百户上限 + 基础保底每百户上限) × 户数 ÷ 100。
## 上限只由配置与户数决定，玩家交易不会改变上限。
func get_village_stock_max(settlement_id: String, item_id: String) -> int:
	var settlement := get_settlement(settlement_id)
	var config := get_goods_config(item_id)
	if not is_village_settlement(settlement) or config == null:
		return 0
	if not is_goods_available_at(config, settlement):
		return 0
	return _config_stock_max(settlement, config)


## 该村庄所有参与库存机制的商品配置，按 item_id 稳定排序。
func get_village_stock_configs(settlement_id: String) -> Array[MarketGoodsConfig]:
	var result: Array[MarketGoodsConfig] = []
	var settlement := get_settlement(settlement_id)
	if not is_village_settlement(settlement):
		return result
	for config: MarketGoodsConfig in get_goods_configs_for_settlement(settlement_id):
		if config.is_village_good() and _config_stock_max(settlement, config) > 0:
			result.append(config)
	return result


## 商品在该地点是否实际提供。
## 城镇仍按 scope；村庄只提供“基础保底物资 + 本村特产 + 特产关联产出”。
func is_goods_available_at(
	config: MarketGoodsConfig,
	settlement: SettlementData
) -> bool:
	if config == null or settlement == null:
		return false
	match settlement.settlement_type:
		SettlementData.SettlementType.CASTLE:
			return false
		SettlementData.SettlementType.TOWN:
			return config.is_available_at(settlement.settlement_type)
		_:
			if not config.is_village_good():
				return false
			if settlement.is_village_specialty(config.item_id):
				return true
			if config.base_floor_per_100_households > 0:
				return true
			return _is_associated_product(settlement, config.item_id)


## 猪特产会同时产出肉；关联关系来自猪的商品配置，不按名称硬编码。
func _is_associated_product(
	settlement: SettlementData, item_id: String
) -> bool:
	for specialty_id: String in settlement.village_specialty_item_ids:
		var specialty := get_goods_config(specialty_id)
		if specialty != null and specialty.associated_item_id == item_id:
			return true
	return false


## 每日补货量 = 动态上限 × 补货比例；不低于 1，且不超过剩余空间。
func calculate_daily_production_amount(
	stock_max: int,
	current: int,
	ratio: float
) -> int:
	if stock_max <= 0 or current >= stock_max or ratio <= 0.0:
		return 0
	var amount: int = int(ceil(
		float(stock_max) * clampf(ratio, 0.0, 1.0)
	))
	return clampi(maxi(1, amount), 1, stock_max - current)


## 商品购买单价；村庄按当前库存占动态上限的比例动态计算。
func get_buy_price(settlement_id: String, item_id: String) -> float:
	var config := get_goods_config(item_id)
	if config == null or not config.can_buy():
		return 0.0
	var settlement := get_settlement(settlement_id)
	if settlement == null or not is_goods_available_at(config, settlement):
		return 0.0
	if settlement.settlement_type == SettlementData.SettlementType.TOWN:
		return GoldUtils.normalize(config.buy_price)
	var stock_max: int = _config_stock_max(settlement, config)
	if stock_max <= 0:
		return 0.0
	var market := get_market(settlement_id)
	var stock: int = market.get_stock(item_id) if market != null else 0
	var ratio: float = float(stock) / float(stock_max)
	return config.compute_village_buy_price(ratio)


## 商品收购单价；村庄收购价保持静态配置，不随库存变化。
func get_sell_price(_settlement_id: String, item_id: String) -> float:
	var config := get_goods_config(item_id)
	if config == null or not config.can_sell():
		return 0.0
	return GoldUtils.normalize(config.sell_price)


func _config_stock_max(
	settlement: SettlementData,
	config: MarketGoodsConfig
) -> int:
	if not config.is_village_good():
		return 0
	var per_100: int = maxi(0, config.base_floor_per_100_households)
	if settlement.is_village_specialty(config.item_id) \
			or _is_associated_product(settlement, config.item_id):
		per_100 += maxi(0, config.stock_cap_per_100_households)
	var households: int = maxi(0, settlement.households)
	return maxi(0, int(floor(
		float(per_100) * float(households) / 100.0
	)))


## 商品在村庄中的库存上限；非村庄或未参与库存机制时返回 -1（不限制）。
func _stock_cap_for(settlement: SettlementData, item_id: String) -> int:
	if not is_village_settlement(settlement):
		return -1
	var config := get_goods_config(item_id)
	if config == null:
		return -1
	var max_stock: int = _config_stock_max(settlement, config)
	return max_stock if max_stock > 0 else -1


## 新世界的初始库存/实例数：村庄按动态上限的比例；城镇使用静态初始库存。
func _get_initial_stock_for(
	settlement: SettlementData,
	config: MarketGoodsConfig
) -> int:
	if is_village_settlement(settlement):
		var max_stock: int = _config_stock_max(settlement, config)
		if max_stock <= 0:
			return 0
		return clampi(
			int(floor(float(max_stock) * config.village_initial_stock_ratio)),
			0,
			max_stock
		)
	return maxi(0, config.initial_stock)


## 为所有村庄与城镇补齐市场库存。新游戏与读档共用；已初始化过的商品不会被重置。
func ensure_markets() -> bool:
	if _settlement_manager == null:
		last_error = "市场管理器尚未初始化地点仓储"
		return false
	var success: bool = true
	for settlement: SettlementData in _settlement_manager.get_all_settlements():
		if settlement == null or not is_market_settlement(settlement):
			continue
		if _ensure_market(settlement) == null:
			success = false
	return success


## 初始化单个村庄/城镇市场；城堡返回 false。
func initialize_market(settlement: SettlementData) -> bool:
	if not is_market_settlement(settlement):
		return false
	return _ensure_market(settlement) != null


func _ensure_market(settlement: SettlementData) -> MarketData:
	var settlement_id: String = settlement.settlement_id
	if settlement_id.is_empty():
		return null
	var market := _markets.get(settlement_id) as MarketData
	if market == null:
		market = MarketData.new()
		market.settlement_id = settlement_id
		_markets[settlement_id] = market
	for value: Variant in _goods.values():
		var config := value as MarketGoodsConfig
		if config == null or not is_goods_available_at(config, settlement):
			continue
		if market.is_initialized(config.item_id):
			continue
		# 旧存档可能已有库存但没有初始化标记：视为已初始化，不再补货。
		if market.stock.has(config.item_id) \
				or market.get_mount_count(config.item_id) > 0 \
				or market.get_item_instance_count(config.item_id) > 0:
			market.mark_initialized(config.item_id)
			continue
		var initial: int = _get_initial_stock_for(settlement, config)
		if is_mount_item(config.item_id):
			for index: int in range(initial):
				market.add_mount_instance(MountInstanceData.create_random(config.item_id))
		elif ItemInstanceData.is_instance_item(config.item_id):
			for index: int in range(initial):
				market.add_item_instance(
					ItemInstanceData.create_random(config.item_id)
				)
		else:
			market.set_stock(config.item_id, initial)
		market.mark_initialized(config.item_id)
	return market


func to_dict() -> Dictionary:
	var markets: Dictionary = {}
	for settlement_id: String in _markets:
		var market := _markets[settlement_id] as MarketData
		if market != null:
			markets[settlement_id] = market.to_dict()
	return {"markets": markets}


func load_from_dict(data: Dictionary) -> void:
	_markets.clear()
	var values: Variant = data.get("markets", {})
	if not values is Dictionary:
		return
	var payload: Dictionary = values
	for key: Variant in payload:
		var settlement_id: String = str(key)
		var value: Variant = payload[key]
		if settlement_id.is_empty() or not value is Dictionary:
			continue
		var market := MarketData.from_dict(value)
		if market.settlement_id.is_empty():
			market.settlement_id = settlement_id
		# 外层键是权威归属；避免存档内部字段错位造成库存串地点。
		market.settlement_id = settlement_id
		_markets[settlement_id] = market


# ---------------------------------------------------------------------------
# 村庄库存每日补货
# ---------------------------------------------------------------------------


## 由 WorldSimulation 每个世界 tick 调用；暂停时不推进。
## 旧“按世界时间缓慢恢复”已停用：村庄只保留每日 00:00 补货。
func tick_village_stock(_fixed_delta: float) -> void:
	settle_village_daily_production()


## 每日 00:00 结算一次；同一游戏日不会重复补充。
## 旧存档/新市场没有日期记录时，以当前日作为起点，不补发历史产出。
func settle_village_daily_production() -> void:
	if _settlement_manager == null:
		return
	var today: int = int(TimeManager.get_date_parts()["total_days"])
	for settlement: SettlementData in _settlement_manager.get_all_settlements():
		if not is_village_settlement(settlement):
			continue
		var market := _markets.get(settlement.settlement_id) as MarketData
		if market == null:
			continue
		# 被破坏村庄暂停所有物资产出与补货，但保留现有库存。
		# 仍推进补货日期，避免恢复后补发破坏期间的产出。
		if settlement.is_destroyed():
			market.daily_production_day = today
			continue
		if market.daily_production_day < 0:
			market.daily_production_day = today
			continue
		if today <= market.daily_production_day:
			continue
		var day: int = market.daily_production_day
		var guard: int = 0
		while day < today and guard < MAX_DAILY_PRODUCTION_DAYS:
			day += 1
			_apply_daily_production(settlement, market)
			guard += 1
		market.daily_production_day = today


## 每日补货：每个参与村庄库存的商品增加“动态上限 × 每日比例”，
## 不超过上限。猪/马按个体实例补充，其余商品按数量补充。
func _apply_daily_production(
	settlement: SettlementData,
	market: MarketData
) -> void:
	for value: Variant in _goods.values():
		var config := value as MarketGoodsConfig
		if config == null or not is_goods_available_at(config, settlement):
			continue
		var item_id: String = config.item_id
		var stock_max: int = _config_stock_max(settlement, config)
		if stock_max <= 0:
			continue
		var stock: int = market.get_stock(item_id)
		var amount: int = calculate_daily_production_amount(
			stock_max, stock, config.daily_refill_ratio
		)
		if amount <= 0:
			continue
		if is_mount_item(item_id):
			for index: int in range(amount):
				market.add_mount_instance(MountInstanceData.create_random(item_id))
		elif ItemInstanceData.is_instance_item(item_id):
			for index: int in range(amount):
				market.add_item_instance(
					ItemInstanceData.create_random(item_id)
				)
		else:
			market.add_stock(item_id, amount, stock_max)


## 村庄库存查询（与 get_stock 同源，供 UI 与逻辑层统一读取）。
func get_village_stock(settlement_id: String, item_id: String) -> int:
	return get_stock(settlement_id, item_id)


## 程序化增加村庄库存；受动态上限约束，返回实际增加量。
## 被破坏村庄暂停产出，这里同样拒绝写入。
func add_village_stock(
	settlement_id: String,
	item_id: String,
	count: int
) -> int:
	var settlement := get_settlement(settlement_id)
	var market := get_market(settlement_id)
	if market == null or count <= 0:
		return 0
	if settlement != null and settlement.is_destroyed():
		return 0
	var cap: int = _stock_cap_for(settlement, item_id)
	var current: int = market.get_stock(item_id)
	var allowed: int = count if cap < 0 else mini(count, maxi(0, cap - current))
	if allowed <= 0:
		return 0
	if is_mount_item(item_id):
		for index: int in range(allowed):
			market.add_mount_instance(MountInstanceData.create_random(item_id))
		return allowed
	if ItemInstanceData.is_instance_item(item_id):
		for index: int in range(allowed):
			market.add_item_instance(ItemInstanceData.create_random(item_id))
		return allowed
	return market.add_stock(item_id, allowed, cap)


## 程序化减少村庄库存；库存不足时返回 false 且不修改。
func remove_village_stock(
	settlement_id: String,
	item_id: String,
	count: int
) -> bool:
	var market := get_market(settlement_id)
	if market == null or count <= 0:
		return false
	return market.remove_stock(item_id, count)


# ---------------------------------------------------------------------------
# 交易
# ---------------------------------------------------------------------------


## 玩家交易唯一入口。purchases / sales 是 { item_id: 数量 } 预览数据；
## 马匹还可以通过实例 ID 列表指定具体个体。
func execute_player_trade(
	settlement_id: String,
	purchases: Dictionary,
	sales: Dictionary,
	holder: Variant,
	trade_id: String = "",
	purchase_mount_instance_ids: Array[String] = [],
	sale_mount_instance_ids: Array[String] = [],
	purchase_item_instance_ids: Array[String] = [],
	sale_item_instance_ids: Array[String] = []
) -> Dictionary:
	return execute_trade(
		TradeSource.PLAYER,
		settlement_id,
		purchases,
		sales,
		holder,
		trade_id,
		purchase_mount_instance_ids,
		sale_mount_instance_ids,
		purchase_item_instance_ids,
		sale_item_instance_ids
	)


## NPC 交易入口：holder 为 PartyData。NPC 交易即使成功也不写玩家世界日志。
func execute_npc_trade(
	settlement_id: String,
	purchases: Dictionary,
	sales: Dictionary,
	holder: Variant,
	trade_id: String = "",
	purchase_mount_instance_ids: Array[String] = [],
	sale_mount_instance_ids: Array[String] = [],
	purchase_item_instance_ids: Array[String] = [],
	sale_item_instance_ids: Array[String] = []
) -> Dictionary:
	return execute_trade(
		TradeSource.NPC,
		settlement_id,
		purchases,
		sales,
		holder,
		trade_id,
		purchase_mount_instance_ids,
		sale_mount_instance_ids,
		purchase_item_instance_ids,
		sale_item_instance_ids
	)


## 统一交易实现。UI 不应直接调用 PlayerProfile / PartyData 的增减接口处理交易。
func execute_trade(
	source: TradeSource,
	settlement_id: String,
	purchases: Dictionary,
	sales: Dictionary,
	holder: Variant,
	trade_id: String = "",
	purchase_mount_instance_ids: Array[String] = [],
	sale_mount_instance_ids: Array[String] = [],
	purchase_item_instance_ids: Array[String] = [],
	sale_item_instance_ids: Array[String] = []
) -> Dictionary:
	last_error = ""
	if holder == null:
		return _failure("交易方数据不存在")
	if _settlement_manager == null:
		return _failure("地点仓储未初始化")
	var settlement := _settlement_manager.get_settlement(settlement_id)
	if settlement == null:
		return _failure("地点不存在")
	if not is_market_settlement(settlement):
		return _failure("该地点没有交易市场")
	var market := get_market(settlement_id)
	if market == null:
		return _failure("该地点市场尚未初始化")
	if not trade_id.is_empty() and _submitted_trade_ids.has(trade_id):
		return _failure("该笔交易已经提交，不能重复结算")

	var purchase_error: String = _validate_item_map(purchases, "购买列表")
	if not purchase_error.is_empty():
		return _failure(purchase_error)
	var sale_error: String = _validate_item_map(sales, "出售列表")
	if not sale_error.is_empty():
		return _failure(sale_error)

	var purchase_items: Dictionary = _normalized_items(purchases)
	var sale_items: Dictionary = _normalized_items(sales)
	var purchase_mount_ids: Array[String] = _unique_ids(purchase_mount_instance_ids)
	var sale_mount_ids: Array[String] = _unique_ids(sale_mount_instance_ids)
	var purchase_item_ids: Array[String] = _unique_ids(purchase_item_instance_ids)
	var sale_item_ids: Array[String] = _unique_ids(sale_item_instance_ids)
	if purchase_mount_ids.size() != purchase_mount_instance_ids.size() \
			or sale_mount_ids.size() != sale_mount_instance_ids.size() \
			or purchase_item_ids.size() != purchase_item_instance_ids.size() \
			or sale_item_ids.size() != sale_item_instance_ids.size():
		return _failure("交易中包含重复的商品实例")

	# 旧接口按 item_id 数量购买/出售非堆叠商品时，转换为具体实例。
	var extraction_error: String = _extract_legacy_instance_ids(
		market, holder, settlement, purchase_items, sale_items,
		purchase_mount_ids, sale_mount_ids,
		purchase_item_ids, sale_item_ids
	)
	if not extraction_error.is_empty():
		return _failure(extraction_error)
	if purchase_items.is_empty() and sale_items.is_empty() \
			and purchase_mount_ids.is_empty() and sale_mount_ids.is_empty() \
			and purchase_item_ids.is_empty() and sale_item_ids.is_empty():
		return _failure("本次交易没有任何物品")

	var purchase_total: float = 0.0
	for item_id: String in purchase_items:
		var config := get_goods_config(item_id)
		var count: int = int(purchase_items[item_id])
		if config == null or not config.can_buy() \
				or not is_goods_available_at(config, settlement):
			return _failure("商品不可购买: %s" % item_id)
		if market.get_stock(item_id) < count:
			return _failure("市场库存不足: %s" % get_item_display_name(item_id))
		purchase_total += get_buy_price(settlement_id, item_id) * float(count)
	var purchase_instance_items: Dictionary = {}
	for instance_id: String in purchase_mount_ids:
		var instance := market.get_mount_instance(instance_id)
		if instance == null:
			return _failure("市场中没有该匹马")
		var config := get_goods_config(instance.equipment_id)
		if config == null or not config.can_buy() \
				or not is_goods_available_at(config, settlement):
			return _failure("该马匹不可购买: %s" % instance.equipment_id)
		purchase_total += get_buy_price(settlement_id, instance.equipment_id)
		purchase_instance_items[instance.equipment_id] = int(
			purchase_instance_items.get(instance.equipment_id, 0)
		) + 1
	for instance_id: String in purchase_item_ids:
		var instance := market.get_item_instance(instance_id)
		if instance == null:
			return _failure("市场中没有该件商品")
		var config := get_goods_config(instance.item_id)
		if config == null or not config.can_buy() \
				or not is_goods_available_at(config, settlement):
			return _failure("该商品不可购买: %s" % instance.item_id)
		purchase_total += get_buy_price(settlement_id, instance.item_id)
		purchase_instance_items[instance.item_id] = int(
			purchase_instance_items.get(instance.item_id, 0)
		) + 1

	var sale_total: float = 0.0
	for item_id: String in sale_items:
		var config := get_goods_config(item_id)
		var count: int = int(sale_items[item_id])
		if config == null or not config.can_sell() \
				or not is_goods_available_at(config, settlement):
			return _failure("商品不可出售: %s" % item_id)
		if int(holder.get_item_count(item_id)) < count:
			return _failure("背包物品不足: %s" % get_item_display_name(item_id))
		sale_total += get_sell_price(settlement_id, item_id) * float(count)
	var sale_instance_items: Dictionary = {}
	for instance_id: String in sale_mount_ids:
		var instance: MountInstanceData = holder.get_mount_instance(instance_id)
		if instance == null:
			return _failure("背包中没有该匹马")
		var config := get_goods_config(instance.equipment_id)
		if config == null or not config.can_sell() \
				or not is_goods_available_at(config, settlement):
			return _failure("该马匹不可出售: %s" % instance.equipment_id)
		var mount_cap: int = _stock_cap_for(settlement, instance.equipment_id)
		if mount_cap >= 0 and market.get_stock(instance.equipment_id) \
				+ int(sale_instance_items.get(instance.equipment_id, 0)) >= mount_cap:
			return _failure("村庄库存已满，无法出售: %s"
				% get_item_display_name(instance.equipment_id))
		sale_total += get_sell_price(settlement_id, instance.equipment_id)
		sale_instance_items[instance.equipment_id] = int(
			sale_instance_items.get(instance.equipment_id, 0)
		) + 1
	for instance_id: String in sale_item_ids:
		var instance: ItemInstanceData = holder.get_item_instance(instance_id)
		if instance == null:
			return _failure("背包中没有该件商品")
		var config := get_goods_config(instance.item_id)
		if config == null or not config.can_sell() \
				or not is_goods_available_at(config, settlement):
			return _failure("该商品不可出售: %s" % instance.item_id)
		var item_cap: int = _stock_cap_for(settlement, instance.item_id)
		if item_cap >= 0 and market.get_stock(instance.item_id) \
				+ int(sale_instance_items.get(instance.item_id, 0)) >= item_cap:
			return _failure("村庄库存已满，无法出售: %s"
				% get_item_display_name(instance.item_id))
		sale_total += get_sell_price(settlement_id, instance.item_id)
		sale_instance_items[instance.item_id] = int(
			sale_instance_items.get(instance.item_id, 0)
		) + 1

	var net_gold: float = GoldUtils.normalize(purchase_total - sale_total)
	if net_gold > 0.0 and not GoldUtils.can_afford(float(holder.gold), net_gold):
		return _failure("金币不足，需要 %s，当前 %s" % [
			GoldUtils.format(net_gold),
			GoldUtils.format(float(holder.gold)),
		])

	var gold_paid: float = GoldUtils.normalize(maxf(0.0, net_gold))
	var gold_received: float = GoldUtils.normalize(maxf(0.0, -net_gold))

	# 提交前快照；提交阶段任何异常都恢复到这里，保证交易原子性。
	var holder_snapshot: Dictionary = _snapshot_holder(holder)
	var market_stock_before: Dictionary = market.stock.duplicate(true)
	var market_mounts_before: Array[MountInstanceData] = market.mount_instances.duplicate()
	var market_items_before: Array[ItemInstanceData] = market.item_instances.duplicate()

	var commit_ok: bool = true
	# 1. 出售普通物品：持有者 → 市场。
	for item_id: String in sale_items:
		var count: int = int(sale_items[item_id])
		if not holder.remove_item(item_id, count):
			commit_ok = false
			break
		# 村庄库存不得突破上限；超出部分不进入村庄库存。
		# 城镇商品与非库存商品保持原有行为。
		market.add_stock(item_id, count, _stock_cap_for(settlement, item_id))
	# 2. 出售马匹：逐匹转移实例。
	if commit_ok:
		for instance_id: String in sale_mount_ids:
			var instance: MountInstanceData = holder.remove_mount_instance(instance_id)
			if instance == null or not market.add_mount_instance(instance):
				commit_ok = false
				break
	# 3. 出售非堆叠普通商品（猪）：逐件转移实例。
	if commit_ok:
		for instance_id: String in sale_item_ids:
			var instance: ItemInstanceData = holder.remove_item_instance(instance_id)
			if instance == null or not market.add_item_instance(instance):
				commit_ok = false
				break
	# 4. 购买普通物品：市场 → 持有者。
	if commit_ok:
		for item_id: String in purchase_items:
			var count: int = int(purchase_items[item_id])
			if not market.remove_stock(item_id, count):
				commit_ok = false
				break
			if not holder.add_item(item_id, count):
				commit_ok = false
				break
	# 5. 购买马匹：逐匹转移实例。
	if commit_ok:
		for instance_id: String in purchase_mount_ids:
			var instance := market.remove_mount_instance(instance_id)
			if instance == null or not holder.add_mount_instance(instance):
				commit_ok = false
				break
	# 6. 购买非堆叠普通商品：逐件转移实例。
	if commit_ok:
		for instance_id: String in purchase_item_ids:
			var instance := market.remove_item_instance(instance_id)
			if instance == null or not holder.add_item_instance(instance):
				commit_ok = false
				break
	# 7. 金币结算。
	if commit_ok and gold_paid > 0.0:
		commit_ok = holder.spend_gold(gold_paid)
	if commit_ok and gold_received > 0.0:
		holder.add_gold(gold_received)

	if not commit_ok:
		_restore_holder(holder, holder_snapshot)
		market.stock = market_stock_before
		market.restore_mount_instances(market_mounts_before)
		market.restore_item_instances(market_items_before)
		return _failure("交易提交失败，已回滚")

	if not trade_id.is_empty():
		_remember_trade_id(trade_id)

	var purchased_items: Dictionary = purchase_items.duplicate()
	for item_id: String in purchase_instance_items:
		purchased_items[item_id] = int(purchased_items.get(item_id, 0)) \
			+ int(purchase_instance_items[item_id])
	var sold_items: Dictionary = sale_items.duplicate()
	for item_id: String in sale_instance_items:
		sold_items[item_id] = int(sold_items.get(item_id, 0)) \
			+ int(sale_instance_items[item_id])

	if source == TradeSource.PLAYER:
		_write_player_trade_log(
			settlement,
			purchased_items,
			sold_items,
			purchase_total,
			sale_total,
			net_gold,
			gold_paid,
			gold_received
		)

	return {
		"success": true,
		"error": "",
		"settlement_id": settlement_id,
		"source": int(source),
		"purchased_items": purchased_items,
		"sold_items": sold_items,
		"purchase_total": purchase_total,
		"sale_total": sale_total,
		"net_gold": net_gold,
		"gold_paid": gold_paid,
		"gold_received": gold_received,
		"purchased_mount_instance_ids": purchase_mount_ids.duplicate(),
		"sold_mount_instance_ids": sale_mount_ids.duplicate(),
		"purchased_item_instance_ids": purchase_item_ids.duplicate(),
		"sold_item_instance_ids": sale_item_ids.duplicate(),
	}


## 将旧接口中的马匹/非堆叠商品数量转换为实例 ID，并从数量字典中移除这些键。
func _extract_legacy_instance_ids(
	market: MarketData,
	holder: Variant,
	settlement: SettlementData,
	purchase_items: Dictionary,
	sale_items: Dictionary,
	purchase_mount_ids: Array[String],
	sale_mount_ids: Array[String],
	purchase_item_ids: Array[String],
	sale_item_ids: Array[String]
) -> String:
	for item_id_value: Variant in purchase_items.keys():
		var item_id: String = str(item_id_value)
		if not is_mount_item(item_id) \
				and not ItemInstanceData.is_instance_item(item_id):
			continue
		var count: int = int(purchase_items[item_id])
		var config := get_goods_config(item_id)
		if config == null or not is_goods_available_at(config, settlement):
			return "该地点不提供该商品"
		if is_mount_item(item_id):
			var available: Array[MountInstanceData] = market.get_mount_instances(item_id)
			if available.size() < count:
				return "市场库存不足: %s" % get_item_display_name(item_id)
			for index: int in range(count):
				purchase_mount_ids.append(available[index].instance_id)
		else:
			var available_items: Array[ItemInstanceData] = \
				market.get_item_instances(item_id)
			if available_items.size() < count:
				return "市场库存不足: %s" % get_item_display_name(item_id)
			for index: int in range(count):
				purchase_item_ids.append(available_items[index].instance_id)
		purchase_items.erase(item_id)

	for item_id_value: Variant in sale_items.keys():
		var item_id: String = str(item_id_value)
		if not is_mount_item(item_id) \
				and not ItemInstanceData.is_instance_item(item_id):
			continue
		var count: int = int(sale_items[item_id])
		var config := get_goods_config(item_id)
		if config == null or not is_goods_available_at(config, settlement):
			return "该地点不收购该商品"
		if is_mount_item(item_id):
			var owned: Array[MountInstanceData] = holder.get_mount_instances(item_id)
			if owned.size() < count:
				return "背包物品不足: %s" % get_item_display_name(item_id)
			for index: int in range(count):
				sale_mount_ids.append(owned[index].instance_id)
		else:
			var owned_items: Array[ItemInstanceData] = \
				holder.get_item_instances(item_id)
			if owned_items.size() < count:
				return "背包物品不足: %s" % get_item_display_name(item_id)
			for index: int in range(count):
				sale_item_ids.append(owned_items[index].instance_id)
		sale_items.erase(item_id)

	# 同一件实例不能同时出现在买卖两侧。
	for instance_id: String in purchase_mount_ids:
		if sale_mount_ids.has(instance_id):
			return "同一匹马不能同时买入和卖出"
	for instance_id: String in purchase_item_ids:
		if sale_item_ids.has(instance_id):
			return "同一件商品不能同时买入和卖出"
	return ""


func _unique_ids(ids: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for instance_id: String in ids:
		if instance_id.is_empty() or result.has(instance_id):
			continue
		result.append(instance_id)
	return result


func _validate_item_map(items: Dictionary, label: String) -> String:
	for key: Variant in items:
		var item_id: String = str(key).strip_edges()
		if item_id.is_empty():
			return "%s包含空物品 ID" % label
		var value: Variant = items[key]
		if not (value is int or value is float):
			return "%s数量必须是数字: %s" % [label, item_id]
		if int(value) < 0:
			return "%s数量不能为负数: %s" % [label, item_id]
	return ""


func _normalized_items(items: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in items:
		var item_id: String = str(key).strip_edges()
		var count: int = int(items[key])
		if item_id.is_empty() or count <= 0:
			continue
		result[item_id] = int(result.get(item_id, 0)) + count
	return result


func _snapshot_holder(holder: Variant) -> Dictionary:
	return {
		"gold": float(holder.gold),
		"counts": holder.item_counts.duplicate(true),
		"inventory": holder.inventory.duplicate(),
		"mounts": holder.get_all_mount_instances(),
		"item_instances": holder.get_all_item_instances(),
	}


func _restore_holder(holder: Variant, snapshot: Dictionary) -> void:
	holder.gold = GoldUtils.normalize(float(snapshot.get("gold", 0.0)))
	holder.restore_inventory_state(
		snapshot.get("counts", {}).duplicate(true),
		snapshot.get("inventory", []).duplicate(),
		snapshot.get("mounts", []),
		snapshot.get("item_instances", [])
	)


func _remember_trade_id(trade_id: String) -> void:
	_submitted_trade_ids[trade_id] = true
	_submitted_trade_order.append(trade_id)
	while _submitted_trade_order.size() > MAX_SUBMITTED_TRADE_IDS:
		var oldest: String = _submitted_trade_order.pop_front()
		_submitted_trade_ids.erase(oldest)


func _failure(message: String) -> Dictionary:
	last_error = message
	return {
		"success": false,
		"error": message,
		"settlement_id": "",
		"source": -1,
		"purchased_items": {},
		"sold_items": {},
		"purchase_total": 0.0,
		"sale_total": 0.0,
		"net_gold": 0.0,
		"gold_paid": 0.0,
		"gold_received": 0.0,
		"purchased_mount_instance_ids": [],
		"sold_mount_instance_ids": [],
		"purchased_item_instance_ids": [],
		"sold_item_instance_ids": [],
	}


# ---------------------------------------------------------------------------
# 日志
# ---------------------------------------------------------------------------


func _write_player_trade_log(
	settlement: SettlementData,
	purchase_items: Dictionary,
	sale_items: Dictionary,
	purchase_total: float,
	sale_total: float,
	net_gold: float,
	gold_paid: float,
	gold_received: float
) -> void:
	if _world_log_manager == null:
		return
	var text: String = _trade_log_text(
		settlement.display_name,
		purchase_items,
		sale_items,
		net_gold,
		gold_paid,
		gold_received
	)
	_world_log_manager.add_event(
		WorldLogEntry.EventType.PLAYER_TRADE,
		text,
		{
			"settlement_id": settlement.settlement_id,
			"purchased_items": purchase_items.duplicate(),
			"sold_items": sale_items.duplicate(),
			"purchase_total": purchase_total,
			"sale_total": sale_total,
			"gold_paid": gold_paid,
			"gold_received": gold_received,
			"net_gold": net_gold,
		}
	)


func _trade_log_text(
	settlement_name: String,
	purchase_items: Dictionary,
	sale_items: Dictionary,
	net_gold: float,
	gold_paid: float,
	gold_received: float
) -> String:
	var bought: String = _items_text(purchase_items)
	var sold: String = _items_text(sale_items)
	if not bought.is_empty() and not sold.is_empty():
		if net_gold > 0.0:
			return "你在%s交易市场购买%s，出售%s，最终支付 %s 金币。" \
				% [settlement_name, bought, sold, GoldUtils.format(gold_paid)]
		if net_gold < 0.0:
			return "你在%s交易市场购买%s，出售%s，最终获得 %s 金币。" \
				% [settlement_name, bought, sold, GoldUtils.format(gold_received)]
		return "你在%s交易市场购买%s，出售%s，本次交易无需支付金币。" \
			% [settlement_name, bought, sold]
	if not bought.is_empty():
		return "你在%s交易市场购买了%s，支付 %s 金币。" \
			% [settlement_name, bought, GoldUtils.format(gold_paid)]
	if not sold.is_empty():
		return "你在%s交易市场出售了%s，获得 %s 金币。" \
			% [settlement_name, sold, GoldUtils.format(gold_received)]
	return "你在%s交易市场完成了一笔交易。" % settlement_name


func _items_text(items: Dictionary) -> String:
	var item_ids: Array[String] = []
	for key: Variant in items:
		item_ids.append(str(key))
	item_ids.sort()
	var parts: Array[String] = []
	for item_id: String in item_ids:
		parts.append(
			"%s ×%d" % [get_item_display_name(item_id), int(items[item_id])]
		)
	return "、".join(parts)
