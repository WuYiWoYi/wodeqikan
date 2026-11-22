class_name HealingConfig
extends Resource
## 伤兵恢复参数的唯一配置来源。
##
## 每游戏小时生成的治疗点数 = base_healing_per_hour + medicine_healing_bonus。
## 当前阶段没有药物技能/界面，medicine 接口先保留，后续只需改配置或注入加成。

@export var base_healing_per_hour: int = 1
## 未来药物/技能提供的每游戏小时额外治疗点；当前固定为 0。
@export var medicine_healing_bonus: int = 0


func get_healing_per_hour() -> int:
	return maxi(0, base_healing_per_hour + medicine_healing_bonus)


func sanitize() -> void:
	base_healing_per_hour = maxi(0, base_healing_per_hour)
	medicine_healing_bonus = maxi(0, medicine_healing_bonus)


static func create_default() -> HealingConfig:
	return HealingConfig.new()
