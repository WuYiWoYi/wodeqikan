extends Node
## 存档读写（Autoload：SaveManager）。
##
## 初期格式：JSON。只保存持久化数据，不保存场景节点。
## 写入流程：临时文件 -> 校验 -> 备份旧档 -> 替换 -> 清理备份。

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
	if slot_name.validate_filename().is_empty():
		push_error("存档槽名称无效: %s" % slot_name)
		return ERR_INVALID_PARAMETER
	if save_data == null:
		return ERR_INVALID_PARAMETER

	var path: String = get_slot_path(slot_name)
	var temp_path: String = path + ".tmp"
	var backup_path: String = path + ".bak"

	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("无法写入临时存档: %s（错误码 %s）" % [temp_path, FileAccess.get_open_error()])
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(save_data.to_dict(), "\t"))
	file.close()

	var verify_payload := _read_payload(temp_path, false)
	if verify_payload.is_empty():
		DirAccess.remove_absolute(temp_path)
		push_error("临时存档校验失败: %s" % temp_path)
		return ERR_FILE_CORRUPT
	if int(verify_payload.get("schema_version", 0)) != save_data.schema_version:
		DirAccess.remove_absolute(temp_path)
		push_error("临时存档版本不一致: %s" % temp_path)
		return ERR_FILE_CORRUPT

	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)
	var had_existing: bool = FileAccess.file_exists(path)
	if had_existing:
		var backup_error: Error = DirAccess.rename_absolute(path, backup_path)
		if backup_error != OK:
			DirAccess.remove_absolute(temp_path)
			push_error("无法备份旧存档: %s（错误码 %s）" % [path, backup_error])
			return backup_error

	var rename_error: Error = DirAccess.rename_absolute(temp_path, path)
	if rename_error != OK:
		if had_existing:
			DirAccess.rename_absolute(backup_path, path)
		DirAccess.remove_absolute(temp_path)
		push_error("无法替换存档文件: %s（错误码 %s）" % [path, rename_error])
		return rename_error

	if had_existing:
		DirAccess.remove_absolute(backup_path)
	return OK


## 读取成功返回 SaveData；失败返回 null。
func load_game(slot_name: String) -> SaveData:
	var path: String = get_slot_path(slot_name)
	if not FileAccess.file_exists(path):
		push_warning("存档不存在: %s" % path)
		return null

	var payload := _read_payload(path, true)
	if payload.is_empty():
		return null
	return SaveData.from_dict(payload)


func has_save(slot_name: String) -> bool:
	return FileAccess.file_exists(get_slot_path(slot_name))


func delete_save(slot_name: String) -> Error:
	var path: String = get_slot_path(slot_name)
	var error: Error = ERR_FILE_NOT_FOUND
	if FileAccess.file_exists(path):
		error = DirAccess.remove_absolute(path)
	if FileAccess.file_exists(path + ".bak"):
		DirAccess.remove_absolute(path + ".bak")
	if FileAccess.file_exists(path + ".tmp"):
		DirAccess.remove_absolute(path + ".tmp")
	return error


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


## 读取存档头信息，供 Continue / Load Game 列表使用。
func get_save_info(slot_name: String) -> Dictionary:
	var path: String = get_slot_path(slot_name)
	if not FileAccess.file_exists(path):
		return {}

	var payload := _read_payload(path, false)
	if payload.is_empty():
		return {}

	var schema_version: int = int(payload.get("schema_version", 0))
	var world_block := _as_dict(payload.get("world", {}))
	var player_block := _as_dict(payload.get("player", {}))
	var parties := _as_dict(payload.get("parties", {}))
	var settlements := _as_dict(payload.get("settlements", {}))
	var world_id: String = str(world_block.get("world_id", ""))
	var player_party_id: String = str(
		payload.get("player_party_id", player_block.get("party_id", ""))
	)
	var valid: bool = (
		schema_version > 0
		and schema_version <= SaveData.CURRENT_SCHEMA_VERSION
		and not world_id.is_empty()
		and not player_party_id.is_empty()
		and parties.has(player_party_id)
		and not settlements.is_empty()
	)
	return {
		"slot": slot_name,
		"saved_at": str(payload.get("saved_at", "")),
		"schema_version": schema_version,
		"world_id": world_id,
		"player_party_id": player_party_id,
		"valid": valid,
		"path": path,
	}


## 按保存时间倒序返回所有可解析的存档头信息。
func list_save_infos() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot_name: String in list_saves():
		var info := get_save_info(slot_name)
		if not info.is_empty():
			result.append(info)
	result.sort_custom(_sort_save_infos_desc)
	return result


func get_latest_save_slot() -> String:
	for info: Dictionary in list_save_infos():
		if bool(info.get("valid", false)):
			return str(info.get("slot", ""))
	return ""


func get_slot_path(slot_name: String) -> String:
	return "%s/%s%s" % [SAVE_DIR, slot_name.validate_filename(), SLOT_EXTENSION]


func _sort_save_infos_desc(a: Dictionary, b: Dictionary) -> bool:
	var a_time := str(a.get("saved_at", ""))
	var b_time := str(b.get("saved_at", ""))
	if a_time == b_time:
		return str(a.get("slot", "")) > str(b.get("slot", ""))
	return a_time > b_time


func _read_payload(path: String, log_errors: bool) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		if log_errors:
			push_error("无法读取存档: %s（错误码 %s）" % [path, FileAccess.get_open_error()])
		return {}

	var json := JSON.new()
	var parse_error: Error = json.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		if log_errors:
			push_error("存档 JSON 解析失败: %s:%s（错误码 %s）" % [path, json.get_error_line(), parse_error])
		return {}
	if not json.data is Dictionary:
		if log_errors:
			push_error("存档根节点不是字典: %s" % path)
		return {}
	return (json.data as Dictionary).duplicate(true)


func _as_dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}
