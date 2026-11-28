class_name FamilyConfig
extends Resource
## 家族静态配置（Data/Families/*.tres）。
##
## 只描述家族的视觉身份，不保存家族关系、外交或领地状态。
## 运行时单位/部队/地点只持久化 family_id；旗帜、颜色与服装资源在
## UnitAppearance / 大地图表现层按本配置解析。

@export_category("Identity")
@export var family_id: String = ""
@export var display_name: String = ""
## 所属文化（CultureDefinition.culture_id）。只用于静态外观映射，
## 不进入存档，也不参与阵营、外交或天赋结算。
@export var culture_id: String = ""

@export_category("Colors")
## 主色用于家族旗帜底色、地图标记与主罩袍回退色。
@export var primary_color: Color = Color.WHITE
## 副色用于副罩袍回退色；留空资源时自动回退主色。
@export var secondary_color: Color = Color.WHITE

@export_category("Banner")
@export_file("*.png") var banner_texture_path: String = ""

@export_category("Tabard")
@export_file("*.png") var tabard_primary_texture_path: String = ""
@export_file("*.png") var tabard_secondary_texture_path: String = ""

@export_category("Leader / Weapon")
@export_file("*.png") var leader_plume_texture_path: String = ""
@export_file("*.png") var spear_texture_path: String = ""


func validate() -> bool:
	return not family_id.strip_edges().is_empty() \
		and not display_name.strip_edges().is_empty()


func has_secondary_tabard() -> bool:
	return not tabard_secondary_texture_path.strip_edges().is_empty()


func get_tabard_texture_path(use_primary: bool) -> String:
	if use_primary:
		return tabard_primary_texture_path
	if has_secondary_tabard():
		return tabard_secondary_texture_path
	return tabard_primary_texture_path


func get_tabard_color(use_primary: bool) -> Color:
	if use_primary or not has_secondary_tabard():
		return primary_color
	return secondary_color
