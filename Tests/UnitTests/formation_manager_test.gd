extends Node
## FormationManager 队形站位单元测试。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/formation_manager_test.tscn

var _failed: bool = false
var _formation := FormationManager.new()


func _ready() -> void:
	_run()
	if _failed:
		push_error("[formation] 测试失败")
		get_tree().quit(1)
	else:
		print("[formation] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	_test_line()
	_test_depth()
	_test_loose()
	_test_square()
	_check(
		_formation.compute_slots(FormationManager.FormationType.NONE, 5, 30.0).is_empty(),
		"无队形返回空站位"
	)
	_check(
		_formation.compute_slots(FormationManager.FormationType.INFANTRY_LINE, 0, 30.0).is_empty(),
		"0 个单位返回空站位"
	)


func _test_line() -> void:
	var slots := _formation.compute_slots(
		FormationManager.FormationType.INFANTRY_LINE, 5, 30.0
	)
	_check(slots.size() == 5, "横向队形生成 5 个站位")
	_check(_unique_count(slots) == 5, "横向队形站位互不相同")
	var min_lateral: float = INF
	var max_lateral: float = -INF
	for slot: Vector2 in slots:
		min_lateral = minf(min_lateral, slot.y)
		max_lateral = maxf(max_lateral, slot.y)
		_check(is_zero_approx(slot.x), "5 人横向队形只有一排")
	_check(max_lateral - min_lateral >= 100.0, "横向队形有明显横向展开")

	var ten_slots := _formation.compute_slots(
		FormationManager.FormationType.INFANTRY_LINE, 10, 30.0
	)
	_check(ten_slots.size() == 10, "10 人横向队形生成 10 个站位")
	var depths: Dictionary = {}
	for slot: Vector2 in ten_slots:
		depths[snappedf(slot.x, 0.1)] = true
	_check(depths.size() == 2, "超过横向容量后自动增加纵深层数")
	_check(_unique_count(ten_slots) == 10, "多排横向队形站位不重复")


func _test_depth() -> void:
	var slots := _formation.compute_slots(
		FormationManager.FormationType.DEPTH, 4, 30.0
	)
	_check(slots.size() == 4, "纵深队形生成 4 个站位")
	_check(_unique_count(slots) == 4, "纵深队形站位互不相同")
	for i: int in range(slots.size()):
		_check(is_zero_approx(slots[i].y), "纵深队形保持单列")
		if i > 0:
			_check(slots[i].x < slots[i - 1].x, "纵深队形沿反方向逐层向后")
	_check(slots[0].x == 0.0, "纵深队形第一名为前排")


func _test_loose() -> void:
	var line := _formation.compute_slots(
		FormationManager.FormationType.INFANTRY_LINE, 4, 30.0
	)
	var loose := _formation.compute_slots(
		FormationManager.FormationType.LOOSE, 4, 30.0
	)
	_check(loose.size() == 4, "松散队形生成 4 个站位")
	var line_spread: float = absf((line[3] as Vector2).y - (line[0] as Vector2).y)
	var loose_spread: float = absf((loose[3] as Vector2).y - (loose[0] as Vector2).y)
	_check(loose_spread > line_spread, "松散队形间距大于横队")


func _test_square() -> void:
	var slots := _formation.compute_slots(
		FormationManager.FormationType.INFANTRY_SQUARE, 9, 30.0
	)
	_check(slots.size() == 9, "方阵生成 9 个站位")
	var depths: Dictionary = {}
	var laterals: Dictionary = {}
	for slot: Vector2 in slots:
		depths[snappedf(slot.x, 0.1)] = true
		laterals[snappedf(slot.y, 0.1)] = true
	_check(depths.size() == 3 and laterals.size() == 3, "方阵为 3×3 布局")


func _unique_count(slots: Array[Vector2]) -> int:
	var seen: Dictionary = {}
	for slot: Vector2 in slots:
		seen["%.2f:%.2f" % [slot.x, slot.y]] = true
	return seen.size()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[formation] OK: %s" % message)
	else:
		_failed = true
		push_error("[formation] FAIL: %s" % message)
