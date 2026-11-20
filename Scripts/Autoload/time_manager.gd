extends Node
## 全局游戏时间管理（Autoload：TimeManager）。
##
## 时间域：
## - WorldTime：世界模拟时间，由本脚本统一推进，固定步长 0.1 秒；
## - SceneTime：小场景时间，由场景自身的 _physics_process 驱动；
## - UITime：UI 表现时间，使用真实帧时间，永远不受世界暂停影响。
##
## 禁止使用 Engine.time_scale 或 get_tree().paused 实现游戏暂停。

signal world_tick(fixed_delta: float)
signal world_speed_changed(effective_scale: float)
signal world_time_changed(total_game_seconds: float)

const WORLD_TICK_INTERVAL: float = 0.1
const MAX_TICKS_PER_FRAME: int = 10

const SPEED_PAUSED: float = 0.0
const SPEED_NORMAL: float = 1.0
const SPEED_DOUBLE: float = 2.0
const BATTLE_WORLD_SPEED: float = 0.5

## 世界累计游戏时间（秒）。阶段 1 之后再换算为游戏内日期。
var world_elapsed_seconds: float = 0.0
var is_world_running: bool = false

var _base_world_speed: float = SPEED_NORMAL
var _battle_mode_active: bool = false
var _pause_reasons: Dictionary = {}
var _world_accumulator: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if not is_world_running:
		return

	var scaled_delta: float = delta * get_effective_world_scale()
	if scaled_delta <= 0.0:
		return

	_world_accumulator += scaled_delta
	var ticks: int = 0
	while _world_accumulator >= WORLD_TICK_INTERVAL and ticks < MAX_TICKS_PER_FRAME:
		_world_accumulator -= WORLD_TICK_INTERVAL
		ticks += 1
		world_elapsed_seconds += WORLD_TICK_INTERVAL
		world_tick.emit(WORLD_TICK_INTERVAL)

	if ticks >= MAX_TICKS_PER_FRAME:
		# 长时间卡顿后不补跑过多次 tick，避免“死亡螺旋”。
		_world_accumulator = 0.0

	if ticks > 0:
		world_time_changed.emit(world_elapsed_seconds)


## 有效倍率计算顺序：显式暂停 > 玩家暂停（0） > 战斗覆盖（0.5） > 基础倍率。
func get_effective_world_scale() -> float:
	if not _pause_reasons.is_empty():
		return SPEED_PAUSED
	if is_zero_approx(_base_world_speed):
		return SPEED_PAUSED
	if _battle_mode_active:
		return BATTLE_WORLD_SPEED
	return _base_world_speed


func set_base_world_speed(speed: float) -> void:
	if speed != SPEED_PAUSED and speed != SPEED_NORMAL and speed != SPEED_DOUBLE:
		push_warning("无效的大地图时间倍率: %s（仅允许 0 / 1 / 2）" % speed)
		return
	if is_equal_approx(_base_world_speed, speed):
		return
	_base_world_speed = speed
	_emit_speed_changed()


func set_battle_mode(active: bool) -> void:
	if _battle_mode_active == active:
		return
	_battle_mode_active = active
	_emit_speed_changed()


## 使用“暂停原因栈”而不是布尔值，避免多个系统互相覆盖暂停状态。
func push_pause(reason: StringName) -> void:
	_pause_reasons[reason] = true
	_emit_speed_changed()


func pop_pause(reason: StringName) -> void:
	if _pause_reasons.erase(reason):
		_emit_speed_changed()


func clear_pauses() -> void:
	if _pause_reasons.is_empty():
		return
	_pause_reasons.clear()
	_emit_speed_changed()


## 开始一个新的游戏会话（新游戏或读档）。
func start_session() -> void:
	reset_session()
	is_world_running = true


## 返回主菜单或退出时停止世界时间。
func stop_session() -> void:
	is_world_running = false
	_world_accumulator = 0.0


func reset_session() -> void:
	world_elapsed_seconds = 0.0
	_world_accumulator = 0.0
	_base_world_speed = SPEED_NORMAL
	_battle_mode_active = false
	_pause_reasons.clear()
	_emit_speed_changed()


func _emit_speed_changed() -> void:
	world_speed_changed.emit(get_effective_world_scale())
