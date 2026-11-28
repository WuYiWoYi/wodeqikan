class_name MarketGoodsConfig
extends Resource
## 市场商品静态配置（Data/Market/*.tres）。
##
## 通过 item_id 关联已有的 EquipmentConfig 或 ItemConfig；不保存运行时库存。
## 城镇价格仍使用 buy_price / sell_price；村庄价格由库存比例在配置区间内插值。
## 所有价格字段允许小数；金币精度统一由 GoldUtils 处理。

## 商品可出现的市场类型。城堡永远没有市场。
enum MarketScope {
	TOWN_ONLY,
	VILLAGE_AND_TOWN,
	VILLAGE_ONLY,
}

@export var item_id: String = ""
## 城镇市场出售给玩家的基础单价；<= 0 表示城镇不出售。
@export var buy_price: float = 0.0
## 玩家出售给市场时获得的基础单价；<= 0 表示市场不收购。
@export var sell_price: float = 0.0
## 新世界/旧存档补齐该商品时的城镇初始库存。
@export var initial_stock: int = 0
@export var is_tradeable: bool = true
@export var scope: MarketScope = MarketScope.TOWN_ONLY
## 是否按数量堆叠。false 时每件商品保存独立实例（猪、马）。
@export var is_stackable: bool = true
## 大宗购买按钮一次移动的数量；空数组表示不启用。
@export var batch_purchase_amounts: Array[int] = []

@export_category("村庄价格")
## 产地采购标准价（库存处于正常水平时的基准价）。
@export var village_buy_base_price: float = 0.0
## 产地紧缺采购价区间：库存越低越接近区间高价端。
@export var village_scarcity_price_min: float = 0.0
@export var village_scarcity_price_max: float = 0.0
## 产地富足采购价区间：库存越高越接近区间低价端。
@export var village_abundance_price_min: float = 0.0
@export var village_abundance_price_max: float = 0.0
## 城镇紧缺收购价格区间（预留，本阶段城镇市场不参与动态库存）。
@export var town_scarcity_price_min: float = 0.0
@export var town_scarcity_price_max: float = 0.0

@export_category("村庄库存")
## 每 100 户对应的产地标准库存上限；<= 0 表示该商品不会作为村庄特产产出。
@export var stock_cap_per_100_households: int = 0
## 每 100 户额外提供的基础保底库存上限（面包 100、草料 50）。
@export var base_floor_per_100_households: int = 0
## 新村庄初始库存占动态上限的比例；0 表示从空库存开始。
@export var village_initial_stock_ratio: float = 0.5
## 每日 00:00 补货量占动态库存上限的比例（默认 25%）。
@export var daily_refill_ratio: float = 0.25
## 特产关联产出：例如猪特产同时产出肉。空字符串表示无关联。
@export var associated_item_id: String = ""
## 大地图特产图标贴图；为空时回退到 ItemConfig.icon_texture_path。
## 马匹没有普通 ItemConfig，因此由商品配置直接提供图标路径。
@export var icon_texture_path: String = ""

## 库存状态边界（占动态上限比例）：0-20% 严重紧缺、20-40% 紧缺、
## 40-70% 正常、70-100% 富足。允许后续通过配置调整。
const SEVERE_SCARCITY_RATIO: float = 0.2
const SCARCITY_RATIO: float = 0.4
const NORMAL_MID_RATIO: float = 0.55
const ABUNDANCE_RATIO: float = 0.7


func validate() -> bool:
	if item_id.strip_edges().is_empty():
		push_error("MarketGoodsConfig 缺少 item_id: %s" % resource_path)
		return false
	if buy_price < 0.0 or sell_price < 0.0:
		push_error("MarketGoodsConfig 价格不能为负数: %s" % item_id)
		return false
	if initial_stock < 0:
		push_error("MarketGoodsConfig 初始库存不能为负数: %s" % item_id)
		return false
	if stock_cap_per_100_households < 0:
		push_error("MarketGoodsConfig 每百户库存上限不能为负数: %s" % item_id)
		return false
	if base_floor_per_100_households < 0:
		push_error("MarketGoodsConfig 每百户保底库存不能为负数: %s" % item_id)
		return false
	if village_initial_stock_ratio < 0.0 or village_initial_stock_ratio > 1.0:
		push_error("MarketGoodsConfig 初始库存比例必须在 0..1 之间: %s" % item_id)
		return false
	if daily_refill_ratio < 0.0 or daily_refill_ratio > 1.0:
		push_error("MarketGoodsConfig 每日补货比例必须在 0..1 之间: %s" % item_id)
		return false
	if associated_item_id.strip_edges() == item_id.strip_edges():
		push_error("MarketGoodsConfig 关联商品不能指向自身: %s" % item_id)
		return false
	for amount: int in batch_purchase_amounts:
		if amount <= 0:
			push_error("MarketGoodsConfig 批量购买数量必须大于 0: %s" % item_id)
			return false
	return true


func can_buy() -> bool:
	return is_tradeable and buy_price > 0.0


func can_sell() -> bool:
	return is_tradeable and sell_price > 0.0


## 城镇/城堡的静态范围判断；村庄是否提供商品还需结合特产由 MarketManager 判断。
func is_available_at(settlement_type: int) -> bool:
	if settlement_type == SettlementData.SettlementType.CASTLE:
		return false
	if settlement_type == SettlementData.SettlementType.VILLAGE:
		return scope != MarketScope.TOWN_ONLY
	return scope != MarketScope.VILLAGE_ONLY


## 是否参与村庄库存与每日产出（特产或基础保底物资）。
func is_village_good() -> bool:
	return stock_cap_per_100_households > 0 \
		or base_floor_per_100_households > 0


func village_base_price() -> float:
	return village_buy_base_price if village_buy_base_price > 0.0 else buy_price


func scarcity_min() -> float:
	return village_scarcity_price_min if village_scarcity_price_min > 0.0 \
		else village_base_price()


func scarcity_max() -> float:
	return village_scarcity_price_max if village_scarcity_price_max > 0.0 \
		else village_base_price()


func abundance_min() -> float:
	return village_abundance_price_min if village_abundance_price_min > 0.0 \
		else village_base_price()


func abundance_max() -> float:
	return village_abundance_price_max if village_abundance_price_max > 0.0 \
		else village_base_price()


## 按库存占动态上限的比例计算村庄采购价。
## - 0%..40%：紧缺区间，库存越低越接近区间高价端；
## - 40%..70%：经标准价平滑过渡；
## - 70%..100%：富足区间，库存越高越接近区间低价端。
func compute_village_buy_price(stock_ratio: float) -> float:
	var ratio: float = clampf(stock_ratio, 0.0, 1.0)
	var base: float = village_base_price()
	var s_min: float = scarcity_min()
	var s_max: float = scarcity_max()
	var a_min: float = abundance_min()
	var a_max: float = abundance_max()
	var price: float = base
	if ratio <= SCARCITY_RATIO:
		var t: float = ratio / SCARCITY_RATIO
		price = lerpf(s_max, s_min, t)
	elif ratio <= NORMAL_MID_RATIO:
		var t: float = (ratio - SCARCITY_RATIO) \
			/ (NORMAL_MID_RATIO - SCARCITY_RATIO)
		price = lerpf(s_min, base, t)
	elif ratio <= ABUNDANCE_RATIO:
		var t: float = (ratio - NORMAL_MID_RATIO) \
			/ (ABUNDANCE_RATIO - NORMAL_MID_RATIO)
		price = lerpf(base, a_max, t)
	else:
		var t: float = (ratio - ABUNDANCE_RATIO) / (1.0 - ABUNDANCE_RATIO)
		price = lerpf(a_max, a_min, t)
	var lower: float = minf(minf(s_min, s_max), minf(a_min, a_max))
	lower = minf(lower, base)
	var upper: float = maxf(maxf(s_min, s_max), maxf(a_min, a_max))
	upper = maxf(upper, base)
	price = clampf(price, lower, upper)
	return GoldUtils.normalize(maxf(0.01, price))


func duplicate_config() -> MarketGoodsConfig:
	var copy := MarketGoodsConfig.new()
	copy.item_id = item_id
	copy.buy_price = buy_price
	copy.sell_price = sell_price
	copy.initial_stock = initial_stock
	copy.is_tradeable = is_tradeable
	copy.scope = scope
	copy.is_stackable = is_stackable
	copy.batch_purchase_amounts = batch_purchase_amounts.duplicate()
	copy.village_buy_base_price = village_buy_base_price
	copy.village_scarcity_price_min = village_scarcity_price_min
	copy.village_scarcity_price_max = village_scarcity_price_max
	copy.village_abundance_price_min = village_abundance_price_min
	copy.village_abundance_price_max = village_abundance_price_max
	copy.town_scarcity_price_min = town_scarcity_price_min
	copy.town_scarcity_price_max = town_scarcity_price_max
	copy.stock_cap_per_100_households = stock_cap_per_100_households
	copy.base_floor_per_100_households = base_floor_per_100_households
	copy.village_initial_stock_ratio = village_initial_stock_ratio
	copy.daily_refill_ratio = daily_refill_ratio
	copy.associated_item_id = associated_item_id
	copy.icon_texture_path = icon_texture_path
	return copy
