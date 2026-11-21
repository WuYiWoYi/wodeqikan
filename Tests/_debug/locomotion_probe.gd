extends Node2D
## 临时调试：大比例渲染步兵/骑兵跑步的连续相位，用于人工检查腿部与马身动画。
## 运行（非 headless）：
##   Godot_v4.6.1-stable_win64.exe --path . res://Tests/_debug/locomotion_probe.tscn

const UnitVisualScript = preload("res://Scripts/Systems/Combat/unit_visual.gd")
const SHOT_DIR: String = "user://locomotion/"

var _foot: Node2D = null
var _mounted: Node2D = null
var _phase_label: Label = null


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("#4b5f3a"))
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(SHOT_DIR)
	)

	_foot = UnitVisualScript.new()
	_foot.position = Vector2(420.0, 760.0)
	_foot.scale = Vector2(5.0, 5.0)
	# 部件使用负 z_index；根节点背景绘制在 z=0，需要把单位抬到背景之上。
	_foot.z_index = 100
	add_child(_foot)
	_foot.setup(_make_unit("PROBE_FOOT", false))

	_mounted = UnitVisualScript.new()
	_mounted.position = Vector2(1200.0, 760.0)
	_mounted.scale = Vector2(5.0, 5.0)
	_mounted.z_index = 100
	add_child(_mounted)
	_mounted.setup(_make_unit("PROBE_MOUNTED", true))

	_phase_label = Label.new()
	_phase_label.position = Vector2(40.0, 40.0)
	_phase_label.add_theme_font_size_override("font_size", 34)
	_phase_label.add_theme_color_override("font_color", Color.WHITE)
	add_child(_phase_label)

	# 先让 blend 稳定进入跑动状态。
	for i: int in range(20):
		_foot.update_locomotion(0.02, true)
		_mounted.update_locomotion(0.02, true)

	for phase: int in range(4):
		_phase_label.text = "跃马相位 %d / 4（步兵左 / 骑兵右）" % (phase + 1)
		await _capture("run_%d" % (phase + 1))
		# RUN_BOB_PERIOD = 0.5 秒，0.125 秒即四分之一周期。
		_foot.update_locomotion(0.125, true)
		_mounted.update_locomotion(0.125, true)

	# 待机姿态：确认双腿回位、马腿基本静止。
	for i: int in range(20):
		_foot.update_locomotion(0.02, false)
		_mounted.update_locomotion(0.02, false)
	_phase_label.text = "待机（步兵左 / 骑兵右）"
	await _capture("idle")
	get_tree().quit(0)


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(SHOT_DIR + file_name + ".png")
	var error := get_viewport().get_texture().get_image().save_png(path)
	print("LOCOMOTION shot %s (error=%s)" % [path, error])


func _make_unit(unit_id: String, mounted: bool) -> UnitData:
	var unit := UnitData.new()
	unit.unit_id = unit_id
	unit.display_name = unit_id
	unit.faction_id = "FACTION_PLAYER"
	unit.is_mounted = mounted
	return unit


func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, 1920.0, 1080.0), Color("#4b5f3a"), true)
	draw_line(Vector2(0.0, 760.0), Vector2(1920.0, 760.0), Color(1, 1, 1, 0.15), 2.0)
