class_name AppearanceConfig
extends Resource
## 士兵外观随机池（Data/Appearance/appearance_config.tres）。
##
## 随机结果在创建单位时一次性写入 UnitData.appearance，之后读档直接使用
## 持久化的资源路径，不再重新随机。头盔按兵种 tier 选择；罩袍主/副概率
## 按 tier 配置，领袖与三级兵始终使用主罩袍。

@export_category("Helmet Pools")
@export var tier1_helmet_texture_paths: Array[String] = []
@export var tier2_helmet_texture_paths: Array[String] = []
@export var tier3_helmet_texture_paths: Array[String] = []

@export_category("Tabard Primary Chance")
## 一级兵使用主罩袍的概率；其余概率使用副罩袍（未配置副罩袍时仍用主）。
@export_range(0.0, 1.0, 0.01) var tier1_primary_tabard_chance: float = 0.2
@export_range(0.0, 1.0, 0.01) var tier2_primary_tabard_chance: float = 0.5
@export_range(0.0, 1.0, 0.01) var tier3_primary_tabard_chance: float = 1.0


func get_helmet_texture_paths(tier: int) -> Array[String]:
	match clampi(tier, 1, 3):
		1:
			return tier1_helmet_texture_paths
		2:
			return tier2_helmet_texture_paths
		_:
			return tier3_helmet_texture_paths


func get_primary_tabard_chance(tier: int, is_leader: bool) -> float:
	if is_leader:
		return 1.0
	match clampi(tier, 1, 3):
		1:
			return tier1_primary_tabard_chance
		2:
			return tier2_primary_tabard_chance
		_:
			return tier3_primary_tabard_chance


## 从对应等级头盔池中随机挑选；池为空返回空路径。
func pick_helmet_texture_path(
	tier: int, rng: RandomNumberGenerator = null
) -> String:
	var paths: Array[String] = get_helmet_texture_paths(tier)
	if paths.is_empty():
		return ""
	var index: int = rng.randi_range(0, paths.size() - 1) if rng != null \
		else randi_range(0, paths.size() - 1)
	return paths[index]
