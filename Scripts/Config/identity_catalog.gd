class_name IdentityCatalog
extends RefCounted
## 新游戏身份配置注册表。
##
## 只读加载 Data/Identity/Categories 与 Data/Identity/Identities 下的 .tres，
## 不进入存档。身份选择 UI 只通过本类查询类别与身份；新增类别或身份时
## 只需增加配置文件，不需要改 UI 逻辑。

const CATEGORY_CONFIG_DIR: String = "res://Data/Identity/Categories"
const IDENTITY_CONFIG_DIR: String = "res://Data/Identity/Identities"

var _categories: Dictionary = {}
var _identities: Dictionary = {}


## 从默认目录加载；任何配置错误都返回 null，由调用方提示失败。
static func load_default() -> IdentityCatalog:
	return load_from_dirs(CATEGORY_CONFIG_DIR, IDENTITY_CONFIG_DIR)


static func load_from_dirs(category_dir: String, identity_dir: String) -> IdentityCatalog:
	var catalog := IdentityCatalog.new()
	if not catalog._load_categories(category_dir):
		return null
	if not catalog._load_identities(identity_dir):
		return null
	if catalog._categories.is_empty() or catalog._identities.is_empty():
		push_error("身份配置为空: %s / %s" % [category_dir, identity_dir])
		return null
	return catalog


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
	if not _categories.has(config.category_id):
		push_error("身份 %s 引用了不存在的类别 %s" % [
			config.identity_id, config.category_id
		])
		return false
	_identities[config.identity_id] = config
	return true


func get_category(category_id: String) -> IdentityCategoryDefinition:
	return _categories.get(category_id) as IdentityCategoryDefinition


func get_identity(identity_id: String) -> IdentityDefinition:
	return _identities.get(identity_id) as IdentityDefinition


## 一级界面使用：启用类别按 sort_order 升序。
func get_enabled_categories() -> Array[IdentityCategoryDefinition]:
	var result: Array[IdentityCategoryDefinition] = []
	for value: Variant in _categories.values():
		var category := value as IdentityCategoryDefinition
		if category != null and category.enabled:
			result.append(category)
	result.sort_custom(_compare_categories)
	return result


## 二级界面使用：指定类别下启用的身份按 sort_order 升序。
func get_enabled_identities(category_id: String) -> Array[IdentityDefinition]:
	var result: Array[IdentityDefinition] = []
	for value: Variant in _identities.values():
		var identity := value as IdentityDefinition
		if identity != null and identity.enabled \
				and identity.category_id == category_id:
			result.append(identity)
	result.sort_custom(_compare_identities)
	return result


## 是否至少存在一个「启用类别 + 启用身份」的可选组合。
func has_selectable_identities() -> bool:
	for category: IdentityCategoryDefinition in get_enabled_categories():
		if not get_enabled_identities(category.category_id).is_empty():
			return true
	return false


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


static func _compare_categories(
		a: IdentityCategoryDefinition, b: IdentityCategoryDefinition
) -> bool:
	if a.sort_order != b.sort_order:
		return a.sort_order < b.sort_order
	return a.category_id < b.category_id


static func _compare_identities(a: IdentityDefinition, b: IdentityDefinition) -> bool:
	if a.sort_order != b.sort_order:
		return a.sort_order < b.sort_order
	return a.identity_id < b.identity_id


static func _list_resource_paths(directory: String) -> Array[String]:
	var paths: Array[String] = []
	var dir: DirAccess = DirAccess.open(directory)
	if dir == null:
		push_error("身份配置目录不存在: %s" % directory)
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
