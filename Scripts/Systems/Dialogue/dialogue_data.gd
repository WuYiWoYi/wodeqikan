class_name DialogueData
extends Resource
## 数据驱动对话配置（Data/Dialogues/*.tres）。
##
## 结构：{ node_id: { "text": String, "choices": Array[Dictionary] } }
## choice: { "text": String, "next_node_id": String }；next 为空表示结束对话。
## 本阶段支持单节点、单选项，后续可扩展分支/条件，不需要改 UI 逻辑。

@export var dialogue_id: String = ""
@export var speaker_name: String = ""
@export var start_node_id: String = "start"
@export var nodes: Dictionary = {}


func validate() -> bool:
	if dialogue_id.strip_edges().is_empty():
		push_error("DialogueData 缺少 dialogue_id: %s" % resource_path)
		return false
	if speaker_name.strip_edges().is_empty():
		push_error("DialogueData 缺少 speaker_name: %s" % dialogue_id)
		return false
	if not nodes.has(start_node_id):
		push_error("DialogueData 缺少起始节点 %s: %s" % [start_node_id, dialogue_id])
		return false
	return true


func get_node_data(node_id: String) -> Dictionary:
	var value: Variant = nodes.get(node_id, {})
	if value is Dictionary:
		return value
	return {}


func has_node(node_id: String) -> bool:
	return nodes.has(node_id)
