class_name IdentityCategoryDefinition
extends Resource
## 新游戏身份类别静态配置（Data/Identity/Categories/*.tres）。
##
## 类别只决定一级界面的入口，与二级界面逻辑解耦。
## 新增类别只需新增 .tres，一级界面按钮会自动生成。

@export_category("Category")
## 唯一类别标识，身份配置通过它关联类别。
@export var category_id: String = ""
@export var display_name: String = ""

@export_category("Ordering")
## 一级界面的显示顺序，升序。
@export var sort_order: int = 0
## 关闭后不会出现在一级界面，但其身份配置仍可保留。
@export var enabled: bool = true


func validate() -> bool:
	return not category_id.strip_edges().is_empty() \
		and not display_name.strip_edges().is_empty()
