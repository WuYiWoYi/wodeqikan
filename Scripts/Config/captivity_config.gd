class_name CaptivityConfig
extends Resource
## 俘虏恢复与玩家逃脱的集中配置（Data/Combat/captivity_config.tres）。
##
## 所有数值按“游戏小时”定义，由 WorldSimulation 的世界 tick 推进。
## 俘虏恢复与伤兵治疗完全独立：不占用 WoundedHealingManager 的名额。

@export_category("Prisoner Healing")
## 每小时每名俘虏恢复的生命值。0 表示关闭俘虏恢复。
@export var prisoner_healing_per_hour: int = 5

@export_category("Player Escape")
## 玩家满血后每隔多少游戏小时进行一次逃脱判定。
@export var escape_check_interval_hours: float = 1.0
## 每次判定成功的概率。
@export_range(0.0, 1.0, 0.01) var escape_chance: float = 0.35
## 逃脱成功后的保护期（游戏小时）；期间 AI 不会主动攻击玩家。
@export var escape_protection_hours: float = 2.0


func sanitize() -> void:
	prisoner_healing_per_hour = maxi(0, prisoner_healing_per_hour)
	escape_check_interval_hours = maxf(0.1, escape_check_interval_hours)
	escape_chance = clampf(escape_chance, 0.0, 1.0)
	escape_protection_hours = maxf(0.0, escape_protection_hours)
