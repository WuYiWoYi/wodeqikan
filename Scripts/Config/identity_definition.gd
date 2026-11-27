class_name IdentityDefinition
extends Resource
## 新游戏身份静态配置（Data/Identity/Identities/*.tres）。
##
## 只描述身份本身，不保存玩家的选择结果，也不包含任何初始化数值。
## 新增身份只需新增一个 .tres，无需修改身份选择 UI。

@export_category("Identity")
## 唯一身份标识，不依赖显示名称；未来初始化按此 ID 分派。
@export var identity_id: String = ""
@export var display_name: String = ""
## 关联 IdentityCategoryDefinition.category_id，用于展示贵族/平民类型。
@export var category_id: String = ""
## 关联 CultureDefinition.culture_id；身份选择按文化过滤。
@export var culture_id: String = ""

@export_category("Description")
## 身份选择界面展示的背景故事。
@export_multiline var description: String = ""
## 身份加成预览行；未确定的条目使用“待设定”占位，不自行补充数值。
@export var bonus_lines: PackedStringArray = PackedStringArray()

@export_category("Ordering")
## 同一文化、同一身份类型内的显示顺序，升序。
@export var sort_order: int = 0
## 关闭后不会出现在身份选择界面，但仍保留配置。
@export var enabled: bool = true


func validate() -> bool:
	return not identity_id.strip_edges().is_empty() \
		and not display_name.strip_edges().is_empty() \
		and not category_id.strip_edges().is_empty() \
		and not culture_id.strip_edges().is_empty()
