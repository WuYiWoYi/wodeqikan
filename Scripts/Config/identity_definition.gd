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
## 关联 IdentityCategoryDefinition.category_id。
@export var category_id: String = ""

@export_category("Description")
## 二级身份选择界面展示的背景故事。
@export_multiline var description: String = ""

@export_category("Ordering")
## 同类别内的显示顺序，升序。
@export var sort_order: int = 0
## 关闭后不会出现在身份选择界面，但仍保留配置。
@export var enabled: bool = true


func validate() -> bool:
	return not identity_id.strip_edges().is_empty() \
		and not display_name.strip_edges().is_empty() \
		and not category_id.strip_edges().is_empty()
