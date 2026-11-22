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
const PAUSE_REASON_BATTLE: StringName = &"battle"
const PAUSE_REASON_ENCOUNTER_DIALOGUE: StringName = &"encounter_dialogue"
const PAUSE_REASON_BATTLE_INTERACTION: StringName = &"battle_encounter_dialogue"

var game_state: GameState = GameState.BOOT
var world_context: WorldContext = null
var player_party_id: String = ""

## 小场景（村庄）运行时状态，不进入存档。
var current_settlement_id: String = ""
## 返回大地图后用于抑制一次地点自动交互，避免玩家站在村口时面板立刻重开。
var pending_settlement_latch_id: String = ""
## 进入小场景前的大地图基础倍率，返回时恢复。
var small_scene_return_base_speed: float = 0.0


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


## 新游戏：创建初始世界数据并进入大地图。进入大地图后默认暂停。
func start_new_game() -> bool:
	_teardown_world()
	TimeManager.clear_pauses()
	TimeManager.start_session()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)

	var context := WorldContext.new()
	context.name = "WorldContext"
	add_child(context)
	world_context = context

	if not WorldInitializer.create_new_world(context):
		push_error("初始世界数据创建失败")
		_teardown_world()
		TimeManager.stop_session()
		return false

	player_party_id = context.player_party_id
	_set_game_state(GameState.IN_GAME)
	EventBus.game_session_started.emit()

	var error: Error = SceneManager.change_scene(SceneManager.WORLD_MAP_SCENE)
	if error != OK:
		_teardown_world()
		TimeManager.stop_session()
		return false
	return true


## 读档是 Continue 与 Load Game 共用的唯一恢复入口。
func load_game(slot_name: String) -> bool:
	var save := SaveManager.load_game(slot_name)
	if save == null:
		return false

	_teardown_world()
	TimeManager.clear_pauses()
	TimeManager.start_session()

	var context := WorldContext.new()
	context.name = "WorldContext"
	add_child(context)
	world_context = context

	if not context.load_from_save_data(save):
		push_error("存档数据不完整，无法恢复世界: %s" % slot_name)
		_teardown_world()
		TimeManager.stop_session()
		return false

	player_party_id = context.player_party_id
	TimeManager.restore_world_time(save.world_elapsed_seconds, save.world_base_speed)
	_set_game_state(GameState.IN_GAME)
	EventBus.game_session_started.emit()

	var error: Error = SceneManager.change_scene(SceneManager.WORLD_MAP_SCENE)
	if error != OK:
		_teardown_world()
		TimeManager.stop_session()
		return false
	return true


func continue_game() -> bool:
	var slot_name: String = SaveManager.get_latest_save_slot()
	if slot_name.is_empty():
		return false
	return load_game(slot_name)


## 由 UI 调用；只聚合与写盘，不改变当前运行状态。
func save_game(slot_name: String) -> Error:
	if world_context == null:
		return ERR_UNCONFIGURED
	# 任意进行中的战斗（包括 AI 离屏战斗）都不进入存档，避免静默丢失战斗。
	if world_context.battle_manager.has_any_active_battles():
		push_error("战斗期间不能存档")
		return ERR_BUSY
	if not world_context.is_valid_world():
		push_error("当前世界数据不完整，拒绝保存")
		return ERR_INVALID_DATA
	return SaveManager.save_game(slot_name, world_context.to_save_data())


func has_active_world() -> bool:
	return world_context != null and world_context.is_valid_world()


func enter_game_world(context: WorldContext) -> void:
	world_context = context
	if context != null:
		player_party_id = context.player_party_id
	_set_game_state(GameState.IN_GAME)


func quit_game() -> void:
	_set_game_state(GameState.EXITING)
	get_tree().quit()


func _teardown_world() -> void:
	var had_world := world_context != null
	_destroy_world_context()
	if had_world:
		EventBus.game_session_ended.emit()


func _destroy_world_context() -> void:
	if is_instance_valid(world_context):
		if world_context.get_parent() == self:
			remove_child(world_context)
		# 同步释放，确保旧 WorldSimulation 立刻断开 world_tick，
		# 避免新旧世界同时接收 tick。
		world_context.free()
	world_context = null
	player_party_id = ""
	current_settlement_id = ""
	pending_settlement_latch_id = ""
	small_scene_return_base_speed = 0.0


func _set_game_state(new_state: GameState) -> void:
	if game_state == new_state:
		return
	game_state = new_state
	EventBus.game_state_changed.emit(int(new_state))
