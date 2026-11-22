class_name WoundedConfig
extends Resource
## 战斗负伤概率的唯一配置来源。
##
## 战斗结算只读取本配置，不在多个结算点硬编码 50/60/80%。
## 概率按兵种 tier 读取；玩家角色保留原有永久死亡规则，不参与负伤判定。
## enabled=false 时所有阵亡单位都永久死亡（单元测试与特殊模式可用）。

## 是否启用负伤判定。生产世界由 WorldContext 注入启用配置。
@export var enabled: bool = true
## 下标 0 对应 tier 1；超出范围时取边界值。默认 50% / 60% / 80%。
@export var tier_wounded_chances: Array[float] = [0.5, 0.6, 0.8]


func sanitize() -> void:
	var cleaned: Array[float] = []
	for chance: float in tier_wounded_chances:
		cleaned.append(clampf(chance, 0.0, 1.0))
	if cleaned.is_empty():
		cleaned = [0.0]
	tier_wounded_chances = cleaned


## 指定 tier 的负伤概率；未启用或 tier 非法时返回 0。
func get_wounded_chance(tier: int) -> float:
	if not enabled:
		return 0.0
	if tier_wounded_chances.is_empty():
		return 0.0
	var index: int = clampi(tier - 1, 0, tier_wounded_chances.size() - 1)
	return clampf(tier_wounded_chances[index], 0.0, 1.0)


static func create_default() -> WoundedConfig:
	var config := WoundedConfig.new()
	config.sanitize()
	return config
