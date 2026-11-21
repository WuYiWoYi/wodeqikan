class_name DialogueManager
extends RefCounted
## 大地图与小场景共用的对话会话管理。
##
## 只维护当前 DialogueData / 节点与选项跳转；UI 负责显示。
## 对话文本与选项全部来自 DialogueData，不在 UI 中硬编码。

var active_dialogue_id: String = ""
var current_node_id: String = ""

var _data: DialogueData = null


## 开始一段对话。data 为 null 或起始节点不存在时返回 false。
func start_dialogue(
	data: DialogueData, start_node_id: String = ""
) -> bool:
	if data == null or not data.validate():
		return false
	var node_id: String = start_node_id.strip_edges()
	if node_id.is_empty():
		node_id = data.start_node_id
	if not data.has_node(node_id):
		push_error("对话节点不存在: %s / %s" % [data.dialogue_id, node_id])
		return false

	_data = data
	active_dialogue_id = data.dialogue_id
	current_node_id = node_id
	return true


func is_active() -> bool:
	return _data != null and not active_dialogue_id.is_empty()


func get_speaker_name() -> String:
	return _data.speaker_name if _data != null else ""


func get_current_text() -> String:
	if _data == null:
		return ""
	return str(_data.get_node_data(current_node_id).get("text", ""))


## 当前节点的选项列表；每项为 { "text": String, "next_node_id": String }。
func get_choices() -> Array:
	if _data == null:
		return []
	var value: Variant = _data.get_node_data(current_node_id).get("choices", [])
	if value is Array:
		return (value as Array).duplicate(true)
	return []


## 选择选项。返回 true 表示对话仍在继续；false 表示对话已结束或选择无效。
## 空 next_node_id 或目标节点不存在时结束对话（配置错误不会卡住 UI）。
func choose(index: int) -> bool:
	if _data == null:
		return false
	var choices: Array = get_choices()
	if index < 0 or index >= choices.size():
		return false
	var choice: Variant = choices[index]
	if not choice is Dictionary:
		end_dialogue()
		return false
	var next_node_id: String = str((choice as Dictionary).get("next_node_id", ""))
	if next_node_id.is_empty() or not _data.has_node(next_node_id):
		end_dialogue()
		return false
	current_node_id = next_node_id
	return true


func end_dialogue() -> void:
	_data = null
	active_dialogue_id = ""
	current_node_id = ""
