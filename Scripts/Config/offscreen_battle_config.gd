class_name OffscreenBattleConfig
extends Resource
## AI 对 AI 离屏战斗的结算参数。
##
## 每经过 settlement_interval_world_seconds（默认 2 世界秒 = 1 游戏小时），
## 根据双方剩余战力、兵种等级、骑乘状态与随机波动结算一次伤亡。
## 公式集中在 OffscreenBattleResolver，本资源只提供可调整参数。

@export_category("Timing")
## 1 游戏小时 = 2 世界累计秒（TimeManager.REAL_SECONDS_PER_GAME_HOUR）。
@export var settlement_interval_world_seconds: float = 2.0
## 安全上限；达到后按剩余战力判定胜负，避免极端情况下战斗无限持续。
@export var max_settlement_hours: int = 48

@export_category("Casualty Formula")
## 均势下每小时的基础伤亡比例。
@export var base_hourly_casualty_fraction: float = 0.20
## 敌方战力占比换算为伤亡比例的放大系数。
@export var pressure_scale: float = 2.0
## 压力系数下限/上限，避免极端战力差导致毫无伤亡或瞬间全灭。
@export var min_pressure_factor: float = 0.35
@export var max_pressure_factor: float = 2.0
## 单小时最大伤亡比例。
@export var max_hourly_casualty_fraction: float = 0.55
## 随机波动幅度：0.30 表示伤亡比例在 0.7x–1.3x 之间波动。
@export var casualty_variance: float = 0.30

@export_category("Combat Power")
## 单兵战力 = (攻击 × attack_weight + 最大生命 × hp_weight) × 等级加成 × 骑乘加成 × 剩余生命比例。
@export var attack_power_weight: float = 1.0
@export var hp_power_weight: float = 0.35
## 每高一级兵种等级（tier）增加的战力比例。
@export var tier_power_bonus_per_level: float = 0.18
## 骑乘单位的战力加成。
@export var mounted_power_bonus: float = 0.15

@export_category("Random")
## -1 表示每次战斗随机播种；>= 0 时用于自动化测试复现。
@export var random_seed: int = -1


func validate() -> bool:
	var valid: bool = true
	if settlement_interval_world_seconds <= 0.0:
		push_error("OffscreenBattleConfig: 结算间隔必须大于 0")
		valid = false
	if max_settlement_hours < 1:
		push_error("OffscreenBattleConfig: 最大结算小时数必须大于等于 1")
		valid = false
	if base_hourly_casualty_fraction < 0.0 or base_hourly_casualty_fraction > 1.0:
		push_error("OffscreenBattleConfig: 基础伤亡比例必须在 0..1")
		valid = false
	if max_hourly_casualty_fraction < 0.0 or max_hourly_casualty_fraction > 1.0:
		push_error("OffscreenBattleConfig: 最大伤亡比例必须在 0..1")
		valid = false
	if casualty_variance < 0.0 or casualty_variance >= 1.0:
		push_error("OffscreenBattleConfig: 随机波动必须在 0..<1")
		valid = false
	return valid
