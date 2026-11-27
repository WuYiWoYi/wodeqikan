class_name IdentityCatalog
extends RefCounted
## 新游戏文化/身份配置注册表。
##
## 只读加载 Data/Cultures、Data/Identity/Categories 与 Data/Identity/Identities
## 下的 .tres，不进入存档。选择界面只通过本类查询文化、类别与身份；新增文化
## 或身份只需增加配置文件，不需要改 UI 逻辑。
##
## 文化配置通过 Resource 动态读取字段，不依赖 class_name 全局类缓存，
## 避免新增配置脚本后编辑器/无头运行尚未重建类缓存时解析失败。

const CULTURE_CONFIG_DIR: String = "res://Data/Cultures"
const CATEGORY_CONFIG_DIR: String = "res://Data/Identity/Categories"
const IDENTITY_CONFIG_DIR: String = "res://Data/Identity/Identities"

var _cultures: Dictionary = {}
var _categories: Dictionary = {}
var _identities: Dictionary = {}


## 从默认目录加载；任何配置错误都返回 null，由调用方提示失败。
static func load_default() -> IdentityCatalog:
	return load_from_dirs(CULTURE_CONFIG_DIR, CATEGORY_CONFIG_DIR, IDENTITY_CONFIG_DIR)


static func load_from_dirs(
		culture_dir: String, category_dir: String, identity_dir: String
) -> IdentityCatalog:
	var catalog := IdentityCatalog.new()
	if not catalog._load_cultures(culture_dir):
		return null
	if not catalog._load_categories(category_dir):
		return null
	if not catalog._load_identities(identity_dir):
		return null
	if catalog._cultures.is_empty() or catalog._categories.is_empty() \
			or catalog._identities.is_empty():
		push_error("文化/身份配置为空: %s / %s / %s" % [
			culture_dir, category_dir, identity_dir
		])
		return null
	return catalog


func register_culture(config: Resource) -> bool:
	if config == null:
		push_error("文化配置无效")
		return false
	var culture_id: String = str(config.get("culture_id"))
	var display_name: String = str(config.get("display_name"))
	if culture_id.strip_edges().is_empty() or display_name.strip_edges().is_empty():
		push_error("文化配置无效")
		return false
	if _cultures.has(culture_id):
		push_error("文化 ID 重复: %s" % culture_id)
		return false
	_cultures[culture_id] = config
	return true


func register_category(config: IdentityCategoryDefinition) -> bool:
	if config == null or not config.validate():
		push_error("身份类别配置无效")
		return false
	if _categories.has(config.category_id):
		push_error("身份类别 ID 重复: %s" % config.category_id)
		return false
	_categories[config.category_id] = config
	return true


func register_identity(config: IdentityDefinition) -> bool:
	if config == null or not config.validate():
		push_error("身份配置无效")
		return false
	if _identities.has(config.identity_id):
		push_error("身份 ID 重复: %s" % config.identity_id)
		return false
	if not _cultures.has(config.culture_id):
		push_error("身份 %s 引用了不存在的文化 %s" % [
			config.identity_id, config.culture_id
		])
		return false
	if not _categories.has(config.category_id):
		push_error("身份 %s 引用了不存在的类别 %s" % [
			config.identity_id, config.category_id
		])
		return false
	_identities[config.identity_id] = config
	return true


## 返回 Variant：文化配置字段由 Resource 动态提供，调用方按配置读取。
func get_culture(culture_id: String) -> Variant:
	return _cultures.get(culture_id)


func get_category(category_id: String) -> IdentityCategoryDefinition:
	return _categories.get(category_id) as IdentityCategoryDefinition


func get_identity(identity_id: String) -> IdentityDefinition:
	return _identities.get(identity_id) as IdentityDefinition


## 文化选择界面使用：启用文化按 sort_order 升序。
func get_enabled_cultures() -> Array:
	var result: Array = []
	for value: Variant in _cultures.values():
		var culture: Variant = value
		if culture != null and culture.enabled:
			result.append(culture)
	result.sort_custom(_compare_cultures)
	return result


## 一级界面使用：启用类别按 sort_order 升序。类别只作为身份类型名称来源。
func get_enabled_categories() -> Array[IdentityCategoryDefinition]:
	var result: Array[IdentityCategoryDefinition] = []
	for value: Variant in _categories.values():
		var category := value as IdentityCategoryDefinition
		if category != null and category.enabled:
			result.append(category)
	result.sort_custom(_compare_categories)
	return result


## 身份选择界面使用：指定文化下启用的身份，先按身份类型排序，再按 sort_order。
func get_enabled_identities_for_culture(
		culture_id: String
) -> Array[IdentityDefinition]:
	var result: Array[IdentityDefinition] = []
	for value: Variant in _identities.values():
		var identity := value as IdentityDefinition
		if identity != null and identity.enabled \
				and identity.culture_id == culture_id:
			result.append(identity)
	result.sort_custom(_compare_identities)
	return result


## 是否至少存在一个「启用文化 + 启用身份」的可选组合。
func has_selectable_cultures() -> bool:
	for value: Variant in get_enabled_cultures():
		var culture: Variant = value
		if culture != null \
				and not get_enabled_identities_for_culture(
					str(culture.culture_id)
				).is_empty():
			return true
	return false


func _load_cultures(directory: String) -> bool:
	var success: bool = true
	for path: String in _list_resource_paths(directory):
		var config := load(path) as Resource
		if config == null or not register_culture(config):
			push_error("无法加载文化配置: %s" % path)
			success = false
	return success


func _load_categories(directory: String) -> bool:
	var success: bool = true
	for path: String in _list_resource_paths(directory):
		var config := load(path) as IdentityCategoryDefinition
		if config == null:
			push_error("无法加载身份类别配置: %s" % path)
			success = false
			continue
		if not register_category(config):
			push_error("身份类别配置注册失败: %s" % path)
			success = false
	return success


func _load_identities(directory: String) -> bool:
	var success: bool = true
	for path: String in _list_resource_paths(directory):
		var config := load(path) as IdentityDefinition
		if config == null:
			push_error("无法加载身份配置: %s" % path)
			success = false
			continue
		if not register_identity(config):
			push_error("身份配置注册失败: %s" % path)
			success = false
	return success


static func _compare_cultures(a: Variant, b: Variant) -> bool:
	if a.sort_order != b.sort_order:
		return a.sort_order < b.sort_order
	return a.culture_id < b.culture_id


static func _compare_categories(
		a: IdentityCategoryDefinition, b: IdentityCategoryDefinition
) -> bool:
	if a.sort_order != b.sort_order:
		return a.sort_order < b.sort_order
	return a.category_id < b.category_id


func _compare_identities(a: IdentityDefinition, b: IdentityDefinition) -> bool:
	var order_a: int = _identity_type_order(a)
	var order_b: int = _identity_type_order(b)
	if order_a != order_b:
		return order_a < order_b
	if a.sort_order != b.sort_order:
		return a.sort_order < b.sort_order
	return a.identity_id < b.identity_id


## 缺少类别配置时排到最后，避免单个坏配置打断整个列表排序。
func _identity_type_order(identity: IdentityDefinition) -> int:
	var category := get_category(identity.category_id)
	return category.sort_order if category != null else 999


static func _list_resource_paths(directory: String) -> Array[String]:
	var paths: Array[String] = []
	var dir: DirAccess = DirAccess.open(directory)
	if dir == null:
		push_error("配置目录不存在: %s" % directory)
		return paths
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			paths.append(directory.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths
