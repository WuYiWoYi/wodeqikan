class_name GoldUtils
extends RefCounted
## 金币数值统一的精度与显示工具。
##
## 商品价格允许小数（例如面包 0.3），金币余额、交易总额与存档统一使用
## 两位小数精度。所有写入金币的地方都必须经过 normalize()，避免浮点误差累计。

const PRECISION: float = 0.01
## 比较余额时允许的微小误差，避免 0.1 + 0.2 这类浮点误差导致误判。
const EPSILON: float = 0.000001


## 统一到非负、两位小数。
static func normalize(amount: float) -> float:
	return snappedf(maxf(0.0, amount), PRECISION)


## 金币显示：整数金额不显示小数，小数金额最多保留两位并去掉末尾 0。
static func format(amount: float) -> String:
	var value: float = normalize(amount)
	if is_equal_approx(value, roundf(value)):
		return "%d" % int(roundf(value))
	var text: String = "%.2f" % value
	while text.ends_with("0"):
		text = text.substr(0, text.length() - 1)
	if text.ends_with("."):
		text = text.substr(0, text.length() - 1)
	return text


## 余额是否足够；使用 EPSILON 抵消浮点误差。
static func can_afford(balance: float, amount: float) -> bool:
	if amount < 0.0:
		return false
	return normalize(balance) + EPSILON >= normalize(amount)
