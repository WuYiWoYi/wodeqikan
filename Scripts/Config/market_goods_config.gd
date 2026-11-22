class_name MarketGoodsConfig
extends Resource
## 市场商品静态配置（Data/Market/*.tres）。
##
## 通过 item_id 关联已有的 EquipmentConfig 或 ItemConfig；不保存运行时库存。
## 价格方向固定：buy_price 是玩家买入支付价，sell_price 是玩家卖出获得价。

## 商品可出现的市场类型。城堡永远没有市场。
enum MarketScope {
	TOWN_ONLY,
	VILLAGE_AND_TOWN,
}

@export var item_id: String = ""
## 玩家向市场购买时支付的单价；<= 0 表示不出售给玩家。
@export var buy_price: int = 0
## 玩家出售给市场时获得的单价；<= 0 表示市场不收购。
@export var sell_price: int = 0
## 新世界/旧存档补齐该商品时的初始库存。
@export var initial_stock: int = 0
@export var is_tradeable: bool = true
@export var scope: MarketScope = MarketScope.TOWN_ONLY
## 是否按数量堆叠。马匹由 MOUNT 装备自动判定为不可堆叠；
## 该字段主要决定 UI 是否显示数量与批量购买按钮。
@export var is_stackable: bool = true
## 大宗购买按钮一次移动的数量；空数组表示不启用。
@export var batch_purchase_amounts: Array[int] = []


func validate() -> bool:
	if item_id.strip_edges().is_empty():
		push_error("MarketGoodsConfig 缺少 item_id: %s" % resource_path)
		return false
	if buy_price < 0 or sell_price < 0:
		push_error("MarketGoodsConfig 价格不能为负数: %s" % item_id)
		return false
	if initial_stock < 0:
		push_error("MarketGoodsConfig 初始库存不能为负数: %s" % item_id)
		return false
	for amount: int in batch_purchase_amounts:
		if amount <= 0:
			push_error("MarketGoodsConfig 批量购买数量必须大于 0: %s" % item_id)
			return false
	return true


func can_buy() -> bool:
	return is_tradeable and buy_price > 0


func can_sell() -> bool:
	return is_tradeable and sell_price > 0


func is_available_at(settlement_type: int) -> bool:
	if settlement_type == SettlementData.SettlementType.CASTLE:
		return false
	if settlement_type == SettlementData.SettlementType.VILLAGE:
		return scope == MarketScope.VILLAGE_AND_TOWN
	return settlement_type == SettlementData.SettlementType.TOWN


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
	return copy
