extends Node
## 世界日历测试：1103-01-01 起点、2 秒 = 1 小时、48 秒 = 1 天、时间段与倍率。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/time_calendar_test.tscn

var _failed: bool = false


func _ready() -> void:
	await _run()
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
	_check(TimeManager.REAL_SECONDS_PER_GAME_HOUR == 2.0, "2 现实秒 = 1 游戏小时")

	TimeManager.reset_session()
	TimeManager.world_elapsed_seconds = 0.0
	_check(TimeManager.get_date_text() == "1103 年 1 月 1 日", "新游戏从 1103 年 1 月 1 日")
	_check(TimeManager.get_time_period() == "深夜", "0 点为深夜")

	# 2 秒 = 1 小时。
	TimeManager.world_elapsed_seconds = 2.0
	var parts := TimeManager.get_date_parts()
	_check(int(parts["hour"]) == 1 and int(parts["day"]) == 1, "2 秒推进 1 小时")
	_check(TimeManager.get_time_period() == "深夜", "1 点为深夜")

	TimeManager.world_elapsed_seconds = 10.0
	_check(TimeManager.get_time_period() == "清晨", "5 点为清晨")
	TimeManager.world_elapsed_seconds = 14.0
	_check(TimeManager.get_time_period() == "上午", "7 点为上午")
	TimeManager.world_elapsed_seconds = 24.0
	_check(TimeManager.get_time_period() == "下午", "12 点为下午")
	TimeManager.world_elapsed_seconds = 34.0
	_check(TimeManager.get_time_period() == "黄昏", "17 点为黄昏")
	TimeManager.world_elapsed_seconds = 38.0
	_check(TimeManager.get_time_period() == "夜晚", "19 点为夜晚")
	TimeManager.world_elapsed_seconds = 46.0
	_check(TimeManager.get_time_period() == "深夜", "23 点为深夜")

	# 48 秒 = 1 天。
	TimeManager.world_elapsed_seconds = 48.0
	_check(TimeManager.get_date_text() == "1103 年 1 月 2 日", "48 秒推进 1 天")
	_check(TimeManager.get_time_period() == "深夜", "次日 0 点为深夜")

	# 简化历法：30 天 = 1 个月，360 天 = 1 年。
	TimeManager.world_elapsed_seconds = 48.0 * 30.0
	_check(TimeManager.get_date_text() == "1103 年 2 月 1 日", "30 天后进入 2 月")
	TimeManager.world_elapsed_seconds = 48.0 * 360.0
	_check(TimeManager.get_date_text() == "1104 年 1 月 1 日", "360 天后进入下一年")
	TimeManager.world_elapsed_seconds = 48.0 * 359.0
	_check(TimeManager.get_date_text() == "1103 年 12 月 30 日", "第 360 天之前仍在 1103 年")

	# 大地图只显示年月日与时间段，不含小时/分钟。
	TimeManager.world_elapsed_seconds = 2.0 * 13.0
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

	# 同一暂停原因允许嵌套：先关闭的内层界面不能解除外层界面的暂停。
	TimeManager.push_pause(&"nested_test")
	TimeManager.push_pause(&"nested_test")
	TimeManager.pop_pause(&"nested_test")
	_check(
		TimeManager.has_pause_reason(&"nested_test")
			and is_zero_approx(TimeManager.get_effective_world_scale()),
		"嵌套暂停释放一层后仍保持暂停"
	)
	TimeManager.pop_pause(&"nested_test")
	_check(
		not TimeManager.has_pause_reason(&"nested_test")
			and is_equal_approx(TimeManager.get_effective_world_scale(), 2.0),
		"嵌套暂停全部释放后恢复原倍率"
	)

	# 实测 1x 累积：现实约 2 秒应推进 1 个游戏小时。
	TimeManager.restore_world_time(0.0, TimeManager.SPEED_NORMAL)
	var real_start: int = Time.get_ticks_msec()
	await get_tree().create_timer(2.05).timeout
	var real_elapsed: float = float(Time.get_ticks_msec() - real_start) / 1000.0
	var real_parts := TimeManager.get_date_parts()
	_check(
		int(real_parts["hour"]) == 1,
		"现实 %.2f 秒推进到 1 点（世界累计 %.2f 秒）" % [
			real_elapsed, TimeManager.world_elapsed_seconds
		]
	)

	# 实测暂停：不推进世界时间。
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	var paused_seconds: float = TimeManager.world_elapsed_seconds
	await get_tree().create_timer(0.2).timeout
	_check(
		is_equal_approx(TimeManager.world_elapsed_seconds, paused_seconds),
		"暂停期间现实时间流逝但世界时间不推进"
	)

	# 实测 2x：现实约 1 秒推进 1 个游戏小时。
	TimeManager.restore_world_time(0.0, TimeManager.SPEED_DOUBLE)
	real_start = Time.get_ticks_msec()
	await get_tree().create_timer(1.05).timeout
	real_elapsed = float(Time.get_ticks_msec() - real_start) / 1000.0
	var double_parts := TimeManager.get_date_parts()
	_check(
		int(double_parts["hour"]) >= 1,
		"2 倍速下现实 %.2f 秒至少推进 1 个游戏小时（世界累计 %.2f 秒）" % [
			real_elapsed, TimeManager.world_elapsed_seconds
		]
	)
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[time] OK: %s" % message)
	else:
		_failed = true
		push_error("[time] FAIL: %s" % message)
