class_name PrisonerPriceConfig
extends Resource
## 俘虏出售价格集中配置。
##
## 士兵按“兵种等级（UnitConfig.tier）”定价，不按战斗经验等级定价：
##   一级 5 / 二级 20 / 三级 60 金币。
## NPC 领主统一 100 金币，与其部队人数、家族地位和经验等级无关。
## UI 与交易管理器都必须通过本资源取值，禁止在界面中写死价格。

## 下标 = 兵种 tier - 1。默认：1 级 5、2 级 20、3 级 60。
@export var tier_prices: Array[int] = [5, 20, 60]
## 具有 NPC 领主身份（UnitData.noble_id 非空）的俘虏统一售价。
@export var lord_price: int = 100


func sanitize() -> void:
	if tier_prices.is_empty():
		tier_prices.assign([5, 20, 60])
	for index: int in range(tier_prices.size()):
		tier_prices[index] = maxi(0, tier_prices[index])
	lord_price = maxi(0, lord_price)


## 兵种等级对应的出售价格；超出配置范围时使用边界价格。
func get_price_for_tier(tier: int) -> int:
	sanitize()
	var index: int = clampi(tier - 1, 0, tier_prices.size() - 1)
	return maxi(0, tier_prices[index])


func get_lord_price() -> int:
	sanitize()
	return lord_price


static func create_default() -> PrisonerPriceConfig:
	var config := PrisonerPriceConfig.new()
	config.tier_prices.assign([5, 20, 60])
	config.lord_price = 100
	return config
