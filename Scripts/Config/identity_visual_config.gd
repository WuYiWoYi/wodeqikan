class_name IdentityVisualConfig
extends Resource
## 新游戏身份选择界面左侧详情的贴图映射（Data/Identity/identity_visual_config.tres）。
##
## 以配置 ID 为键映射到 Texture2D，UI 不硬编码贴图路径。未配置或配置为空的 ID
## 由 UI 使用统一占位表现，不影响选择流程与布局。

const DEFAULT_PATH: String = "res://Data/Identity/identity_visual_config.tres"

@export_category("Detail Visuals")
## 键为 CultureDefinition.culture_id。
@export var culture_textures: Dictionary = {}
## 键为 IdentityDefinition.identity_id。
@export var identity_textures: Dictionary = {}


## 加载默认映射；文件缺失或类型错误时返回空配置，由 UI 显示占位。
static func load_default() -> IdentityVisualConfig:
	if not ResourceLoader.exists(DEFAULT_PATH):
		return IdentityVisualConfig.new()
	var resource: Resource = load(DEFAULT_PATH)
	if resource is IdentityVisualConfig:
		return resource
	push_warning("身份选择贴图配置类型错误: %s" % DEFAULT_PATH)
	return IdentityVisualConfig.new()


func get_culture_texture(culture_id: String) -> Texture2D:
	return _get_texture(culture_textures, culture_id)


func get_identity_texture(identity_id: String) -> Texture2D:
	return _get_texture(identity_textures, identity_id)


func _get_texture(mapping: Dictionary, key: String) -> Texture2D:
	if key.strip_edges().is_empty():
		return null
	var value: Variant = mapping.get(key)
	return value as Texture2D
