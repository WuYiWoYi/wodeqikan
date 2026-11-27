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

## ---------------------------------------------------------------------------
## 游戏日历
## ---------------------------------------------------------------------------
## 世界累计秒数是唯一权威时间；年月日与时间段全部由它换算，各系统不得自行累计。
## 1x 速度下：现实 2 秒 = 1 游戏小时，48 秒 = 1 游戏日。
const START_YEAR: int = 1103
const START_MONTH: int = 1
const START_DAY: int = 1
const REAL_SECONDS_PER_GAME_HOUR: float = 2.0
## 每 1 世界累计秒 = 30 游戏分钟（60 / 2）。
const GAME_MINUTES_PER_ELAPSED_SECOND: float = 30.0
const HOURS_PER_DAY: int = 24
## 本阶段采用简化历法：每月 30 天、每年 12 个月，便于后续统一调整。
const DAYS_PER_MONTH: int = 30
const MONTHS_PER_YEAR: int = 12

## 时间段集中配置；未命中任何区间时使用 DEFAULT_TIME_PERIOD。
const TIME_PERIODS: Array[Dictionary] = [
	{"start_hour": 5, "end_hour": 7, "name": "清晨"},
	{"start_hour": 7, "end_hour": 12, "name": "上午"},
	{"start_hour": 12, "end_hour": 17, "name": "下午"},
	{"start_hour": 17, "end_hour": 19, "name": "黄昏"},
	{"start_hour": 19, "end_hour": 23, "name": "夜晚"},
]
const DEFAULT_TIME_PERIOD: String = "深夜"

const SPEED_PAUSED: float = 0.0
const SPEED_NORMAL: float = 1.0
const SPEED_DOUBLE: float = 2.0
const BATTLE_WORLD_SPEED: float = 0.5

## 世界累计游戏时间（秒）。阶段 1 之后再换算为游戏内日期。
var world_elapsed_seconds: float = 0.0
var is_world_running: bool = false

var _base_world_speed: float = SPEED_NORMAL
var _battle_mode_active: bool = false
## { reason: 引用计数 }。多个界面可以同时使用同一个暂停原因，
## 必须成对 push/pop；只有计数归零时世界才恢复。
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


func get_base_world_speed() -> float:
	return _base_world_speed


func set_base_world_speed(speed: float) -> void:
	if speed != SPEED_PAUSED and speed != SPEED_NORMAL and speed != SPEED_DOUBLE:
		push_warning("无效的大地图时间倍率: %s（仅允许 0 / 1 / 2）" % speed)
		return
	if is_equal_approx(_base_world_speed, speed):
		return
	_base_world_speed = speed
	_emit_speed_changed()


## 读档时恢复世界累计时间与基础倍率。暂停原因由 GameManager 负责清理。
func restore_world_time(total_seconds: float, base_speed: float) -> void:
	world_elapsed_seconds = maxf(0.0, total_seconds)
	_world_accumulator = 0.0
	_battle_mode_active = false
	_base_world_speed = base_speed
	if _base_world_speed != SPEED_PAUSED \
			and _base_world_speed != SPEED_NORMAL \
			and _base_world_speed != SPEED_DOUBLE:
		_base_world_speed = SPEED_PAUSED
	_emit_speed_changed()
	world_time_changed.emit(world_elapsed_seconds)


func set_battle_mode(active: bool) -> void:
	if _battle_mode_active == active:
		return
	_battle_mode_active = active
	_emit_speed_changed()


## 使用“暂停原因栈”而不是布尔值，避免多个系统互相覆盖暂停状态。
## 同一原因允许嵌套：先打开的界面后关闭时不会意外恢复世界时间。
func push_pause(reason: StringName) -> void:
	_pause_reasons[reason] = int(_pause_reasons.get(reason, 0)) + 1
	_emit_speed_changed()


func pop_pause(reason: StringName) -> void:
	var count: int = int(_pause_reasons.get(reason, 0))
	if count <= 0:
		return
	if count <= 1:
		_pause_reasons.erase(reason)
	else:
		_pause_reasons[reason] = count - 1
	_emit_speed_changed()


func clear_pauses() -> void:
	if _pause_reasons.is_empty():
		return
	_pause_reasons.clear()
	_emit_speed_changed()


func has_pause_reason(reason: StringName) -> bool:
	return _pause_reasons.has(reason)


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


# ---------------------------------------------------------------------------
# 日历换算
# ---------------------------------------------------------------------------


## 世界累计秒数 → 游戏总分钟数。
func get_game_total_minutes(total_seconds: float = -1.0) -> int:
	var seconds: float = (
		world_elapsed_seconds if total_seconds < 0.0 else total_seconds
	)
	return maxi(0, int(floor(seconds * GAME_MINUTES_PER_ELAPSED_SECOND)))


## 世界累计秒数 → { year, month, day, hour, minute, total_hours, total_days }。
## 新游戏从 START_YEAR 年 START_MONTH 月 START_DAY 日 00:00 开始。
@warning_ignore("integer_division")
func get_date_parts(total_seconds: float = -1.0) -> Dictionary:
	var total_minutes: int = get_game_total_minutes(total_seconds)
	var total_hours: int = total_minutes / 60
	var total_days: int = total_hours / HOURS_PER_DAY
	var hour: int = total_hours % HOURS_PER_DAY

	var days_per_year: int = DAYS_PER_MONTH * MONTHS_PER_YEAR
	var year_offset: int = int(floor(float(total_days) / float(days_per_year)))
	var day_of_year: int = total_days % days_per_year
	var month_offset: int = int(floor(float(day_of_year) / float(DAYS_PER_MONTH)))
	var month_index: int = (START_MONTH - 1) + month_offset
	var year: int = START_YEAR + year_offset
	var month: int = month_index % MONTHS_PER_YEAR + 1
	var day: int = day_of_year % DAYS_PER_MONTH + START_DAY

	return {
		"year": year,
		"month": month,
		"day": day,
		"hour": hour,
		"minute": total_minutes % 60,
		"total_hours": total_hours,
		"total_days": total_days,
	}


## 仅年月日，例如“1103 年 1 月 1 日”。
func get_date_text(total_seconds: float = -1.0) -> String:
	var parts := get_date_parts(total_seconds)
	return "%d 年 %d 月 %d 日" % [parts["year"], parts["month"], parts["day"]]


## 根据当前小时返回时间段名称。
func get_time_period(total_seconds: float = -1.0) -> String:
	var parts := get_date_parts(total_seconds)
	var hour: int = int(parts["hour"])
	for period: Dictionary in TIME_PERIODS:
		var start_hour: int = int(period["start_hour"])
		var end_hour: int = int(period["end_hour"])
		if hour >= start_hour and hour < end_hour:
			return str(period["name"])
	return DEFAULT_TIME_PERIOD


## 大地图时间显示：只展示年月日与时间段，不显示小时和分钟。
func get_world_time_text(total_seconds: float = -1.0) -> String:
	return "%s %s" % [get_date_text(total_seconds), get_time_period(total_seconds)]


func _emit_speed_changed() -> void:
	world_speed_changed.emit(get_effective_world_scale())
