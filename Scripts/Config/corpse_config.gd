class_name CorpseConfig
extends Resource
## 战斗尸体表现时长的唯一配置来源。
##
## 死亡后的表现流程：倒地动画 → 尸体留存 → 逐渐淡出 → 移除视觉对象。
## 本配置只影响表现层，不改变 BattleUnitState、胜负结算或 AI；
## 具体留存时长属于待确认数值，可在 Data/Combat/corpse_config.tres 中调整。

const DEFAULT_FALL_DURATION: float = 0.55
## 暂定默认值：具体留存时长由后续平衡确认，不在多个脚本中重复硬编码。
const DEFAULT_LINGER_DURATION: float = 6.0
const DEFAULT_FADE_DURATION: float = 1.2

## 倒地动画时长（秒）。0 表示立即完成倒地姿态。
@export var fall_duration: float = DEFAULT_FALL_DURATION
## 倒地完成后尸体保持可见的时长（秒）。
@export var linger_duration: float = DEFAULT_LINGER_DURATION
## 尸体淡出时长（秒）。0 表示留存结束后立即移除。
@export var fade_duration: float = DEFAULT_FADE_DURATION


func sanitize() -> void:
	fall_duration = maxf(0.0, fall_duration)
	linger_duration = maxf(0.0, linger_duration)
	fade_duration = maxf(0.0, fade_duration)


static func create_default() -> CorpseConfig:
	var config := CorpseConfig.new()
	config.sanitize()
	return config
