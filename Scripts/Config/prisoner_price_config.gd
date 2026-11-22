class_name PrisonerPriceConfig
extends Resource
## 俘虏出售价格集中配置（阶段 13 Step 6）。
##
## 价格只按单位等级计算，不考虑装备、伤势、经验与身份差异。
## UI 与交易管理器都必须通过本资源取值，禁止在界面中写死价格。

## 下标 = 单位等级 - 1。默认：1 级 10、2 级 20、3 级 30。
@export var level_prices: Array[int] = [10, 20, 30]


func sanitize() -> void:
	if level_prices.is_empty():
		level_prices.assign([10, 20, 30])
	for index: int in range(level_prices.size()):
		level_prices[index] = maxi(0, level_prices[index])


## 单位等级对应的出售价格；超出配置范围时使用边界价格。
func get_price_for_level(level: int) -> int:
	sanitize()
	var index: int = clampi(level - 1, 0, level_prices.size() - 1)
	return maxi(0, level_prices[index])


static func create_default() -> PrisonerPriceConfig:
	var config := PrisonerPriceConfig.new()
	config.level_prices.assign([10, 20, 30])
	return config
