class_name TaxCalculator
extends RefCounted
## 封地税收的唯一计算入口。
##
## 只做纯计算，不读取或修改任何管理器：人口与繁荣度越高，预计每日税收越高；
## 人口或繁荣度为 0 时税收为 0，结果永远不会为负数。
## UI 与业务层都必须调用本类，不允许自行复制公式。


static func compute_daily_tax(
	population: int, prosperity: int, tax_base: int
) -> int:
	if tax_base <= 0 or population <= 0 or prosperity <= 0:
		return 0
	var population_factor: float = float(population) / 100.0
	var prosperity_factor: float = float(prosperity) / 100.0
	return maxi(0, int(round(float(tax_base) * population_factor * prosperity_factor)))
