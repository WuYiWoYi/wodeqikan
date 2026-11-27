class_name CultureDefinition
extends Resource
## 新游戏文化静态配置（Data/Cultures/*.tres）。
##
## 只描述文化的展示内容：名称、背景与天赋预览。天赋当前仅用于界面展示，
## 不写入任何运行时系统，也不进入存档。

@export_category("Culture")
## 唯一文化标识，身份配置通过 culture_id 关联。
@export var culture_id: String = ""
@export var display_name: String = ""

@export_category("Description")
## 文化选择界面左侧展示的背景介绍。
@export_multiline var description: String = ""
## 文化天赋预览行；未确定的条目使用“待设定”占位，不自行补充数值。
@export var talent_lines: PackedStringArray = PackedStringArray()

@export_category("Ordering")
## 文化选择界面的显示顺序，升序。
@export var sort_order: int = 0
## 关闭后不会出现在文化选择界面，但仍保留配置。
@export var enabled: bool = true


func validate() -> bool:
	return not culture_id.strip_edges().is_empty() \
		and not display_name.strip_edges().is_empty()
