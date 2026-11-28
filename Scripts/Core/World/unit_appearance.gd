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

## 国王盔是纯表现的身份覆盖：由 WorldContext 在装配时注册只读解析器，
## UnitVisual 每次重建时查询当前身份，不把结果写入 UnitData/装备/存档。
static var _king_override_owner: Object = null
static var _king_helmet_texture_path: String = ""
static var _king_unit_predicate: Callable = Callable()

## 贵族文化头盔同样是纯表现覆盖：WorldContext 注册文化解析器，
## 只对贵族单位生效；结果不写入 UnitData/装备/存档。
static var _noble_override_owner: Object = null
static var _noble_helmet_texture_paths: Dictionary = {}
static var _noble_culture_resolver: Callable = Callable()


## 注册当前世界的国王外观覆盖。资源缺失时清空路径，回退普通头盔。
static func configure_king_helmet_override(
	owner: Object, texture_path: String, unit_predicate: Callable
) -> void:
	_king_override_owner = owner
	_king_helmet_texture_path = (
		texture_path if not texture_path.is_empty() \
			and ResourceLoader.exists(texture_path) else ""
	)
	_king_unit_predicate = unit_predicate


## 世界销毁时清理注册；只允许当前拥有者清理，避免覆盖后来注册的世界。
static func clear_king_helmet_override(owner: Object) -> void:
	if owner != null and _king_override_owner != null \
			and _king_override_owner != owner:
		return
	_king_override_owner = null
	_king_helmet_texture_path = ""
	_king_unit_predicate = Callable()


## 单位当前是否应显示国王盔；身份由解析器实时判断，没有头盔时返回空。
static func get_king_helmet_texture_path(unit: UnitData) -> String:
	if unit == null or _king_helmet_texture_path.is_empty():
		return ""
	if not _king_unit_predicate.is_valid():
		return ""
	if not bool(_king_unit_predicate.call(unit)):
		return ""
	return _king_helmet_texture_path


## 注册贵族文化头盔覆盖。缺失资源不进入映射，回退普通头盔；
## 解析器返回 culture_id，非贵族或没有文化时返回空字符串。
static func configure_noble_helmet_override(
	owner: Object,
	texture_paths_by_culture: Dictionary,
	culture_resolver: Callable
) -> void:
	_noble_override_owner = owner
	_noble_helmet_texture_paths.clear()
	for culture_value: Variant in texture_paths_by_culture:
		var culture_id: String = str(culture_value)
		var texture_path: String = str(texture_paths_by_culture[culture_value])
		if culture_id.is_empty() or texture_path.is_empty():
			continue
		if ResourceLoader.exists(texture_path):
			_noble_helmet_texture_paths[culture_id] = texture_path
	_noble_culture_resolver = culture_resolver


## 世界销毁时清理注册；只允许当前拥有者清理，避免覆盖后来注册的世界。
static func clear_noble_helmet_override(owner: Object) -> void:
	if owner != null and _noble_override_owner != null \
			and _noble_override_owner != owner:
		return
	_noble_override_owner = null
	_noble_helmet_texture_paths.clear()
	_noble_culture_resolver = Callable()


## 贵族单位当前应显示的专属头盔；普通士兵、无文化或未配置时返回空。
static func get_noble_helmet_texture_path(unit: UnitData) -> String:
	if unit == null or _noble_helmet_texture_paths.is_empty():
		return ""
	if not _noble_culture_resolver.is_valid():
		return ""
	var culture_id: String = str(_noble_culture_resolver.call(unit))
	if culture_id.is_empty():
		return ""
	return str(_noble_helmet_texture_paths.get(culture_id, ""))


static func ensure_random(
	unit: UnitData,
	unit_config: UnitConfig,
	family: FamilyConfig,
	config: AppearanceConfig,
	is_leader: bool = false,
	rng: RandomNumberGenerator = null,
	is_mercenary: bool = false
) -> void:
	if unit == null or not unit.appearance.is_empty():
		return

	var appearance: Dictionary = build_appearance(
		unit_config, family, config, is_leader, rng, is_mercenary
	)
	if family != null and not is_mercenary:
		unit.family_id = family.family_id
	unit.appearance = appearance


## 生成一份可持久化的外观字典，不依赖 UnitData。
## 雇佣兵外观只由 is_mercenary 与 tier/配置决定：
## - 按 tier 使用专属罩袍；
## - 不使用家族罩袍颜色、家族制式长矛或领袖缨饰；
## - 只有配置中指定的兵种（无赖骑士）显示专属缨饰。
static func build_appearance(
	unit_config: UnitConfig,
	family: FamilyConfig,
	config: AppearanceConfig,
	is_leader: bool = false,
	rng: RandomNumberGenerator = null,
	is_mercenary: bool = false
) -> Dictionary:
	var tier: int = clampi(unit_config.tier if unit_config != null else 1, 1, 3)
	var appearance: Dictionary = {
		"version": VERSION,
		"family_id": "",
		"tabard_variant": "",
		"tabard_texture_path": "",
		"tabard_color": "",
		"helmet_texture_path": "",
		"plume_texture_path": "",
		"spear_texture_path": "",
	}

	if config != null:
		appearance["helmet_texture_path"] = config.pick_helmet_texture_path(tier, rng)

	if is_mercenary:
		appearance["tabard_variant"] = "MERCENARY"
		if config != null:
			appearance["tabard_texture_path"] = \
				config.get_mercenary_tabard_texture_path(tier)
			appearance["plume_texture_path"] = config.get_mercenary_plume_texture_path(
				unit_config.config_id if unit_config != null else ""
			)
		return appearance

	if family != null:
		appearance["family_id"] = family.family_id
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

	return appearance


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
