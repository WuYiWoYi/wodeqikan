class_name UnitAppearance
extends RefCounted
## 士兵外观一次性生成器。
##
## 输出全部是字符串/简单值，可直接进入 JSON 存档：
## - family_id
## - tabard_variant / tabard_texture_path / tabard_color
## - helmet_texture_path
## - plume_texture_path（仅领袖）
## - spear_texture_path（家族配置存在时）
##
## 规则集中在 AppearanceConfig 与 FamilyConfig；UnitVisual 只读取最终结果，
## 不包含任何具体家族判断。已有 appearance 的单位不会重新随机。

const VERSION: int = 1


static func ensure_random(
	unit: UnitData,
	unit_config: UnitConfig,
	family: FamilyConfig,
	config: AppearanceConfig,
	is_leader: bool = false,
	rng: RandomNumberGenerator = null
) -> void:
	if unit == null or not unit.appearance.is_empty():
		return

	var tier: int = clampi(unit_config.tier if unit_config != null else 1, 1, 3)
	var appearance: Dictionary = {
		"version": VERSION,
		"family_id": family.family_id if family != null else "",
		"tabard_variant": "",
		"tabard_texture_path": "",
		"tabard_color": "",
		"helmet_texture_path": "",
		"plume_texture_path": "",
		"spear_texture_path": "",
	}

	if config != null:
		appearance["helmet_texture_path"] = config.pick_helmet_texture_path(tier, rng)

	if family != null:
		unit.family_id = family.family_id
		var use_primary: bool = true
		if family.has_secondary_tabard():
			var primary_chance: float = 1.0 if config == null \
				else config.get_primary_tabard_chance(tier, is_leader)
			var roll: float = rng.randf() if rng != null else randf()
			use_primary = is_leader or roll < primary_chance
		appearance["tabard_variant"] = "PRIMARY" if use_primary else "SECONDARY"
		appearance["tabard_texture_path"] = family.get_tabard_texture_path(use_primary)
		appearance["tabard_color"] = family.get_tabard_color(use_primary).to_html(false)
		appearance["spear_texture_path"] = family.spear_texture_path
		if is_leader:
			appearance["plume_texture_path"] = family.leader_plume_texture_path

	unit.appearance = appearance


## 旧存档/手工构造单位缺失 appearance 时的安全空值。
static func get_appearance(unit: UnitData) -> Dictionary:
	if unit == null or unit.appearance.is_empty():
		return {}
	return unit.appearance


static func get_texture_path(unit: UnitData, key: String) -> String:
	var appearance := get_appearance(unit)
	return str(appearance.get(key, ""))


static func get_tabard_variant(unit: UnitData) -> String:
	var appearance := get_appearance(unit)
	return str(appearance.get("tabard_variant", ""))
