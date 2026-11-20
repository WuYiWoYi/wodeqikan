class_name DialogueManager
extends RefCounted
## 大地图与小场景共用的对话会话管理。
##
## 只维护对话状态与节点跳转；UI 负责显示，条件/效果由受控命令表执行。

var active_dialogue_id: String = ""
var current_node_id: String = ""


func start_dialogue(dialogue_id: String, start_node_id: String = "start") -> void:
	# TODO(阶段5)：加载对话配置、计算可用选项、暂停世界时间（大地图对话）。
	active_dialogue_id = dialogue_id
	current_node_id = start_node_id
	push_warning("DialogueManager.start_dialogue 尚未实现")


func choose(_choice_index: int) -> void:
	# TODO(阶段5)：按当前节点选项跳转并执行效果。
	pass


func end_dialogue() -> void:
	active_dialogue_id = ""
	current_node_id = ""


func is_active() -> bool:
	return not active_dialogue_id.is_empty()
