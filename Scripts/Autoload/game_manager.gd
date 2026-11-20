extends Node
## 全局游戏状态管理（Autoload：GameManager）。
##
## 只负责游戏运行状态和会话级容器的生命周期，不实现具体玩法。
## 世界数据由 WorldContext 持有；场景表现由 SceneManager 切换。

enum GameState {
	BOOT,
	MAIN_MENU,
	IN_GAME,
	EXITING,
}

const PAUSE_REASON_MAIN_MENU: StringName = &"main_menu"
const PAUSE_REASON_LOADING: StringName = &"loading"
const PAUSE_REASON_UI_PANEL: StringName = &"ui_panel"
const PAUSE_REASON_WORLD_DIALOGUE: StringName = &"world_dialogue"
const PAUSE_REASON_SMALL_SCENE: StringName = &"small_scene"

var game_state: GameState = GameState.BOOT
var world_context: WorldContext = null
var player_party_id: String = ""


func _ready() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	TimeManager.push_pause(PAUSE_REASON_MAIN_MENU)
	_set_game_state(GameState.MAIN_MENU)


func enter_main_menu() -> void:
	_teardown_world()
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	TimeManager.push_pause(PAUSE_REASON_MAIN_MENU)
	_set_game_state(GameState.MAIN_MENU)
	SceneManager.change_scene(SceneManager.MAIN_MENU_SCENE)


## 阶段 0 只建立世界上下文与场景入口；初始数据在阶段 1 补充。
func start_new_game() -> void:
	_teardown_world()
	TimeManager.clear_pauses()
	TimeManager.start_session()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)

	world_context = WorldContext.new()
	world_context.name = "WorldContext"
	add_child(world_context)

	_set_game_state(GameState.IN_GAME)
	EventBus.game_session_started.emit()
	SceneManager.change_scene(SceneManager.WORLD_MAP_SCENE)


## TODO(阶段0)：由 SaveManager 读取存档后重建 WorldContext。
func load_game(_slot_name: String) -> bool:
	push_warning("GameManager.load_game 尚未实现")
	return false


func enter_game_world(context: WorldContext) -> void:
	world_context = context
	_set_game_state(GameState.IN_GAME)


func quit_game() -> void:
	_set_game_state(GameState.EXITING)
	get_tree().quit()


func _teardown_world() -> void:
	if is_instance_valid(world_context):
		world_context.queue_free()
	world_context = null
	player_party_id = ""
	EventBus.game_session_ended.emit()


func _set_game_state(new_state: GameState) -> void:
	if game_state == new_state:
		return
	game_state = new_state
	EventBus.game_state_changed.emit(int(new_state))
