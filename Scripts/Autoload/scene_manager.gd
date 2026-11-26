extends Node
## 场景加载与切换（Autoload：SceneManager）。
##
## 只负责切换表现场景，不持有世界数据。
## 世界数据的生命周期由 GameManager / WorldContext 管理。

signal scene_change_requested(scene_path: String)
signal scene_changed(scene_path: String)

const MAIN_MENU_SCENE: String = "res://Scenes/MainMenu/main_menu.tscn"
## 新游戏身份选择的独立全屏场景。
const IDENTITY_SELECT_SCENE: String = "res://Scenes/Identity/identity_select.tscn"
const WORLD_MAP_SCENE: String = "res://Scenes/WorldMap/world_map.tscn"
const BATTLE_SCENE: String = "res://Scenes/Battle/battle.tscn"
const VILLAGE_SCENE: String = "res://Scenes/Village/village.tscn"
const TOWN_SCENE: String = "res://Scenes/Town/town.tscn"
const CASTLE_SCENE: String = "res://Scenes/Castle/castle.tscn"

var current_scene_path: String = ""


func change_scene(scene_path: String) -> Error:
	if not ResourceLoader.exists(scene_path):
		push_error("场景不存在: %s" % scene_path)
		return ERR_FILE_NOT_FOUND

	if scene_path == current_scene_path and get_tree().current_scene != null:
		return OK

	scene_change_requested.emit(scene_path)
	var error: Error = get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("场景切换失败: %s（错误码 %s）" % [scene_path, error])
		return error

	current_scene_path = scene_path
	scene_changed.emit(scene_path)
	return OK


func reload_current_scene() -> Error:
	if current_scene_path.is_empty():
		return ERR_UNCONFIGURED
	return change_scene(current_scene_path)
