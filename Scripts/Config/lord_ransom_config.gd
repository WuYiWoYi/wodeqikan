class_name LordRansomConfig
extends Resource
## NPC 领主家族赎回流程的集中配置。
##
## 等待时间使用世界游戏小时：世界时间由 TimeManager 统一推进，暂停时不会
## 缩短等待。赎金在“请求生成”时一次性随机确定，之后不再变化。
## 所有数值都应通过本资源调整，禁止在管理器或 UI 中写死。

## 关闭后出售领主不再启动赎回流程。
@export var enabled: bool = true
## 出售到城镇后，家族发来赎回请求的最小/最大等待游戏小时。
@export var wait_hours_min: int = 12
@export var wait_hours_max: int = 48
## 领主仍关押在玩家部队中时，家族发起赎买请求的最小/最大等待游戏小时。
## 与出售等待相互独立，二者不能对同一领主的同一阶段同时生效。
@export var captive_wait_hours_min: int = 3
@export var captive_wait_hours_max: int = 12
## 请求生成时确定的赎金范围（金币）。必须大于 100。
@export var ransom_gold_min: int = 150
@export var ransom_gold_max: int = 400


func sanitize() -> void:
	wait_hours_min = maxi(1, wait_hours_min)
	wait_hours_max = maxi(wait_hours_min, wait_hours_max)
	captive_wait_hours_min = maxi(1, captive_wait_hours_min)
	captive_wait_hours_max = maxi(captive_wait_hours_min, captive_wait_hours_max)
	ransom_gold_min = maxi(101, ransom_gold_min)
	ransom_gold_max = maxi(ransom_gold_min, ransom_gold_max)


## 当前世界累计秒数 → 等待若干游戏小时后的累计秒数。
## 1 游戏小时 = TimeManager.REAL_SECONDS_PER_GAME_HOUR 个世界累计秒。
func wait_seconds_for_hours(hours: int) -> float:
	return maxf(0.0, float(hours) * TimeManager.REAL_SECONDS_PER_GAME_HOUR)


## 关押期赎买等待与出售赎回使用同一世界时间换算，仅默认小时数不同。
func captive_wait_hours_to_seconds(hours: int) -> float:
	return wait_seconds_for_hours(hours)


static func create_default() -> LordRansomConfig:
	var config := LordRansomConfig.new()
	config.enabled = true
	config.wait_hours_min = 12
	config.wait_hours_max = 48
	config.captive_wait_hours_min = 3
	config.captive_wait_hours_max = 12
	config.ransom_gold_min = 150
	config.ransom_gold_max = 400
	return config
