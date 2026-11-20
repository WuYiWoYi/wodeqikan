extends Node
## 存档读写（Autoload：SaveManager）。
##
## 初期格式：JSON。只保存持久化数据，不保存场景节点。
## 存档聚合（从 WorldContext 收集数据）在阶段 0 后半段实现。

const SAVE_SCHEMA_VERSION: int = SaveData.CURRENT_SCHEMA_VERSION
const SAVE_DIR: String = "user://saves"
const SLOT_EXTENSION: String = ".json"


func _ready() -> void:
	var error: Error = DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_warning("无法创建存档目录 %s（错误码 %s）" % [SAVE_DIR, error])


func save_game(slot_name: String, save_data: SaveData) -> Error:
	if slot_name.strip_edges().is_empty():
		push_error("存档槽名称不能为空")
		return ERR_INVALID_PARAMETER

	var path: String = get_slot_path(slot_name)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("无法写入存档: %s（错误码 %s）" % [path, FileAccess.get_open_error()])
		return FileAccess.get_open_error()

	file.store_string(JSON.stringify(save_data.to_dict(), "\t"))
	file.close()
	return OK


## 读取成功返回 SaveData；失败返回 null。
func load_game(slot_name: String) -> SaveData:
	var path: String = get_slot_path(slot_name)
	if not FileAccess.file_exists(path):
		push_warning("存档不存在: %s" % path)
		return null

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("无法读取存档: %s" % path)
		return null

	var json := JSON.new()
	var parse_error: Error = json.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		push_error("存档 JSON 解析失败: %s:%s（错误码 %s）" % [path, json.get_error_line(), parse_error])
		return null

	if not json.data is Dictionary:
		push_error("存档根节点不是字典: %s" % path)
		return null

	return SaveData.from_dict(json.data)


func has_save(slot_name: String) -> bool:
	return FileAccess.file_exists(get_slot_path(slot_name))


func delete_save(slot_name: String) -> Error:
	var path: String = get_slot_path(slot_name)
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	return DirAccess.remove_absolute(path)


func list_saves() -> PackedStringArray:
	var result := PackedStringArray()
	var dir: DirAccess = DirAccess.open(SAVE_DIR)
	if dir == null:
		return result

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(SLOT_EXTENSION):
			result.append(file_name.get_basename())
		file_name = dir.get_next()
	dir.list_dir_end()
	return result


func get_slot_path(slot_name: String) -> String:
	return "%s/%s%s" % [SAVE_DIR, slot_name.validate_filename(), SLOT_EXTENSION]
