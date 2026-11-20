class_name FactionConfig
extends Resource
## 阵营静态配置（Data/Factions/*.tres）。

@export var faction_id: String = ""
@export var display_name: String = ""
@export var color: Color = Color.WHITE
@export var is_player_faction: bool = false
## 初始外交关系：{ faction_id: 好感度 -100..100 }
@export var initial_relations: Dictionary = {}
