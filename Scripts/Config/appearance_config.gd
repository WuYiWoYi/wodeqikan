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

@export_category("Mercenary Appearance")
## 雇佣兵按 tier 使用的专属罩袍。身份只由 UnitData.is_mercenary 决定，
## 不读取姓名、家族或部队类型；Tier2/Tier3 各自独立配置。
@export var mercenary_tier2_tabard_texture_path: String = ""
@export var mercenary_tier3_tabard_texture_path: String = ""
## 专属缨饰只发给指定兵种配置（当前为无赖骑士），其他雇佣兵不显示缨饰。
@export var mercenary_plume_config_ids: Array[String] = ["mercenary_rogue_knight"]
@export var mercenary_plume_texture_path: String = ""

@export_category("Identity Appearance Override")
## 国王身份对应的头盔外观覆盖。只在原本就会显示头盔时替换贴图；
## 不写入 UnitData.appearance / 装备数据，身份失效后自动恢复原头盔。
@export var king_helmet_texture_path: String = ""


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


## 雇佣兵罩袍：只按 tier 取，不参与家族主/副罩袍随机。
func get_mercenary_tabard_texture_path(tier: int) -> String:
	match clampi(tier, 1, 3):
		2:
			return mercenary_tier2_tabard_texture_path
		3:
			return mercenary_tier3_tabard_texture_path
		_:
			return ""


## 雇佣兵缨饰：只有兵种配置命中专属列表时才显示。
func get_mercenary_plume_texture_path(config_id: String) -> String:
	if config_id.is_empty() or not mercenary_plume_config_ids.has(config_id):
		return ""
	return mercenary_plume_texture_path
