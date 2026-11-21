extends Node
## 世界日历测试：1103-01-01 起点、6 秒 = 1 小时、144 秒 = 1 天、时间段与倍率。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/time_calendar_test.tscn

var _failed: bool = false


func _ready() -> void:
	_run()
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	TimeManager.reset_session()
	if _failed:
		push_error("[time] 测试失败")
		get_tree().quit(1)
	else:
		print("[time] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	_check(TimeManager.START_YEAR == 1103, "起始年份 1103")
	_check(TimeManager.REAL_SECONDS_PER_GAME_HOUR == 6.0, "6 现实秒 = 1 游戏小时")

	TimeManager.reset_session()
	TimeManager.world_elapsed_seconds = 0.0
	_check(TimeManager.get_date_text() == "1103 年 1 月 1 日", "新游戏从 1103 年 1 月 1 日")
	_check(TimeManager.get_time_period() == "深夜", "0 点为深夜")

	# 6 秒 = 1 小时。
	TimeManager.world_elapsed_seconds = 6.0
	var parts := TimeManager.get_date_parts()
	_check(int(parts["hour"]) == 1 and int(parts["day"]) == 1, "6 秒推进 1 小时")
	_check(TimeManager.get_time_period() == "深夜", "1 点为深夜")

	TimeManager.world_elapsed_seconds = 30.0
	_check(TimeManager.get_time_period() == "清晨", "5 点为清晨")
	TimeManager.world_elapsed_seconds = 42.0
	_check(TimeManager.get_time_period() == "上午", "7 点为上午")
	TimeManager.world_elapsed_seconds = 72.0
	_check(TimeManager.get_time_period() == "下午", "12 点为下午")
	TimeManager.world_elapsed_seconds = 102.0
	_check(TimeManager.get_time_period() == "黄昏", "17 点为黄昏")
	TimeManager.world_elapsed_seconds = 114.0
	_check(TimeManager.get_time_period() == "夜晚", "19 点为夜晚")
	TimeManager.world_elapsed_seconds = 138.0
	_check(TimeManager.get_time_period() == "深夜", "23 点为深夜")

	# 144 秒 = 1 天。
	TimeManager.world_elapsed_seconds = 144.0
	_check(TimeManager.get_date_text() == "1103 年 1 月 2 日", "144 秒推进 1 天")
	_check(TimeManager.get_time_period() == "深夜", "次日 0 点为深夜")

	# 简化历法：30 天 = 1 个月，360 天 = 1 年。
	TimeManager.world_elapsed_seconds = 144.0 * 30.0
	_check(TimeManager.get_date_text() == "1103 年 2 月 1 日", "30 天后进入 2 月")
	TimeManager.world_elapsed_seconds = 144.0 * 360.0
	_check(TimeManager.get_date_text() == "1104 年 1 月 1 日", "360 天后进入下一年")
	TimeManager.world_elapsed_seconds = 144.0 * 359.0
	_check(TimeManager.get_date_text() == "1103 年 12 月 30 日", "第 360 天之前仍在 1103 年")

	# 大地图只显示年月日与时间段，不含小时/分钟。
	TimeManager.world_elapsed_seconds = 6.0 * 13.0
	var text := TimeManager.get_world_time_text()
	_check(text == "1103 年 1 月 1 日 下午", "世界时间文本只含日期与时间段")
	_check(not text.contains(":"), "世界时间文本不显示小时/分钟")

	# 倍率状态：1x / 2x / 暂停。
	TimeManager.start_session()
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)
	_check(is_equal_approx(TimeManager.get_effective_world_scale(), 1.0), "1x 有效倍率")
	TimeManager.set_base_world_speed(TimeManager.SPEED_DOUBLE)
	_check(is_equal_approx(TimeManager.get_effective_world_scale(), 2.0), "2x 有效倍率")
	TimeManager.push_pause(&"time_test")
	_check(is_zero_approx(TimeManager.get_effective_world_scale()), "暂停时有效倍率为 0")
	TimeManager.pop_pause(&"time_test")
	_check(is_equal_approx(TimeManager.get_effective_world_scale(), 2.0), "取消暂停恢复 2x")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[time] OK: %s" % message)
	else:
		_failed = true
		push_error("[time] FAIL: %s" % message)
