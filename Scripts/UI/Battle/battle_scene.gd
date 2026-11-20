class_name BattleScene
extends Node2D
## 战斗场景控制器：读取 BattleSession，生成 UnitActor，驱动实时战斗与结果返回。
##
## 只读取 UnitData 的静态属性，伤害写入 BattleUnitState；
## 战斗结算统一由 BattleManager.finish_battle() 执行。

const BATTLEFIELD_SIZE := Vector2(1280.0, 720.0)
const SPAWN_MARGIN_X: float = 300.0
const SPAWN_SPACING_X: float = 54.0
const SPAWN_SPACING_Y: float = 64.0

@onready var characters: Node2D = $World/Characters
@onready var camera: Camera2D = $Camera2D

var _context: WorldContext = null
var _battle_manager: BattleManager = null
var _session: BattleSession = null

## unit_id -> UnitActor / UnitController
var _actors: Dictionary = {}
var _controllers: Dictionary = {}
var _attacker_controllers: Array[UnitController] = []
var _defender_controllers: Array[UnitController] = []
var _handled_deaths: Dictionary = {}

var _battle_over: bool = false
var _returned: bool = false
var _result: BattleSession.BattleResult = BattleSession.BattleResult.UNDECIDED

var _ui_root: Control = null
var _info_label: Label = null
var _alive_label: Label = null
var _result_dim: ColorRect = null
var _result_panel: PanelContainer = null
var _result_label: Label = null
var _return_button: Button = null


func _ready() -> void:
	_context = GameManager.world_context
	if _context == null:
		push_error("战斗场景缺少 WorldContext")
		call_deferred("_abort_to_world_map")
		return

	_battle_manager = _context.battle_manager
	_session = _battle_manager.current_battle
	if _session == null:
		push_error("战斗场景缺少 BattleSession")
		call_deferred("_abort_to_world_map")
		return

	_session.status = BattleSession.Status.ACTIVE
	_build_ui()
	_spawn_units()
	camera.position = BATTLEFIELD_SIZE * 0.5
	camera.enabled = true
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, BATTLEFIELD_SIZE), Color("#4b5f3a"), true)
	draw_rect(
		Rect2(0.0, BATTLEFIELD_SIZE.y - 90.0, BATTLEFIELD_SIZE.x, 90.0),
		Color("#5a4a35"),
		true
	)
	var grid_color := Color(0.0, 0.0, 0.0, 0.08)
	for x: int in range(0, int(BATTLEFIELD_SIZE.x) + 1, 80):
		draw_line(Vector2(float(x), 0.0), Vector2(float(x), BATTLEFIELD_SIZE.y), grid_color, 1.0)
	for y: int in range(0, int(BATTLEFIELD_SIZE.y) + 1, 80):
		draw_line(Vector2(0.0, float(y)), Vector2(BATTLEFIELD_SIZE.x, float(y)), grid_color, 1.0)
	draw_line(
		Vector2(BATTLEFIELD_SIZE.x * 0.5, 0.0),
		Vector2(BATTLEFIELD_SIZE.x * 0.5, BATTLEFIELD_SIZE.y),
		Color(1.0, 1.0, 1.0, 0.08),
		2.0
	)


func _physics_process(delta: float) -> void:
	if _session == null or _battle_over:
		return

	for controller: UnitController in _attacker_controllers:
		controller.tick(delta, _defender_controllers)
	for controller: UnitController in _defender_controllers:
		controller.tick(delta, _attacker_controllers)

	_process_deaths()
	_update_alive_label()
	_check_battle_end()


func _unhandled_input(event: InputEvent) -> void:
	if _battle_over:
		return
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	var target := get_global_mouse_position()
	if not Rect2(Vector2.ZERO, BATTLEFIELD_SIZE).has_point(target):
		return
	command_player_units(target)
	get_viewport().set_input_as_handled()


## 命令所有存活己方士兵移动到目标点附近，保持简单间距。
func command_player_units(target: Vector2) -> void:
	var alive: Array[UnitController] = []
	for controller: UnitController in _attacker_controllers:
		if controller.is_alive():
			alive.append(controller)

	var columns: int = 2
	var rows: int = maxi(1, ceili(float(alive.size()) / float(columns)))
	for i: int in range(alive.size()):
		var row: int = i / columns
		var column: int = i % columns
		var offset := Vector2(
			(float(column) - 0.5) * 28.0,
			(float(row) - (float(rows) - 1.0) * 0.5) * 28.0
		)
		alive[i].command_move(target + offset)


func get_session() -> BattleSession:
	return _session


func get_actor_count() -> int:
	return _actors.size()


func get_controller(unit_id: String) -> UnitController:
	return _controllers.get(unit_id) as UnitController


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "UI"
	add_child(canvas)

	_ui_root = Control.new()
	_ui_root.name = "BattleUI"
	_ui_root.theme = UiTheme.create()
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_full_rect(_ui_root)
	canvas.add_child(_ui_root)

	var top_bar := PanelContainer.new()
	top_bar.name = "TopBar"
	top_bar.anchor_right = 1.0
	top_bar.offset_bottom = 46.0
	_ui_root.add_child(top_bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	top_bar.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	_info_label = _make_label("战斗", 17)
	_info_label.name = "BattleInfoLabel"
	_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_info_label)

	_alive_label = _make_label("", 16)
	_alive_label.name = "BattleAliveLabel"
	row.add_child(_alive_label)

	var hint := _make_label("左键点击地面：命令己方士兵移动", 14)
	hint.name = "BattleHintLabel"
	hint.anchor_left = 0.0
	hint.anchor_top = 1.0
	hint.anchor_right = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_top = -34.0
	hint.offset_bottom = -8.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color("#f3ead6"))
	hint.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	hint.add_theme_constant_override("shadow_offset_x", 1)
	hint.add_theme_constant_override("shadow_offset_y", 1)
	_ui_root.add_child(hint)

	_result_dim = ColorRect.new()
	_result_dim.name = "BattleResultDim"
	_result_dim.color = Color(0.0, 0.0, 0.0, 0.5)
	_result_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_dim.visible = false
	_set_full_rect(_result_dim)
	_ui_root.add_child(_result_dim)

	_result_panel = PanelContainer.new()
	_result_panel.name = "BattleResultPanel"
	_result_panel.visible = false
	_result_panel.anchor_left = 0.5
	_result_panel.anchor_top = 0.5
	_result_panel.anchor_right = 0.5
	_result_panel.anchor_bottom = 0.5
	_result_panel.offset_left = -220.0
	_result_panel.offset_top = -120.0
	_result_panel.offset_right = 220.0
	_result_panel.offset_bottom = 120.0
	_ui_root.add_child(_result_panel)

	var panel_margin := MarginContainer.new()
	panel_margin.add_theme_constant_override("margin_left", 22)
	panel_margin.add_theme_constant_override("margin_right", 22)
	panel_margin.add_theme_constant_override("margin_top", 20)
	panel_margin.add_theme_constant_override("margin_bottom", 20)
	_result_panel.add_child(panel_margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel_margin.add_child(column)

	_result_label = _make_label("", 26)
	_result_label.name = "BattleResultLabel"
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_result_label)

	_return_button = _make_button("返回大地图", "BattleReturnButton")
	_return_button.custom_minimum_size = Vector2(0.0, 42.0)
	_return_button.pressed.connect(_on_return_pressed)
	column.add_child(_return_button)


func _spawn_units() -> void:
	_spawn_side(_session.attacker_unit_ids, true)
	_spawn_side(_session.defender_unit_ids, false)
	_update_alive_label()


func _spawn_side(unit_ids: Array[String], is_attacker: bool) -> void:
	var total: int = unit_ids.size()
	for i: int in range(total):
		var unit_id: String = unit_ids[i]
		var unit := _context.unit_manager.get_unit(unit_id)
		var state := _session.get_unit_state(unit_id)
		if unit == null or state == null:
			push_warning("战斗场景跳过无效单位: %s" % unit_id)
			continue

		state.battle_position = _spawn_position(i, total, is_attacker)
		var actor := UnitActor.new()
		characters.add_child(actor)
		actor.setup(unit, state, is_attacker)

		var controller := UnitController.new()
		controller.setup(unit, state, is_attacker, actor, Rect2(Vector2.ZERO, BATTLEFIELD_SIZE))

		_actors[unit_id] = actor
		_controllers[unit_id] = controller
		if is_attacker:
			_attacker_controllers.append(controller)
		else:
			_defender_controllers.append(controller)


func _spawn_position(index: int, total: int, is_attacker: bool) -> Vector2:
	var columns: int = 2
	var rows: int = maxi(1, ceili(float(total) / float(columns)))
	var row: int = index / columns
	var column: int = index % columns
	var direction: float = 1.0 if is_attacker else -1.0
	var base_x: float = SPAWN_MARGIN_X if is_attacker else BATTLEFIELD_SIZE.x - SPAWN_MARGIN_X
	var x: float = base_x + direction * float(column) * SPAWN_SPACING_X
	var y: float = BATTLEFIELD_SIZE.y * 0.5 \
		+ (float(row) - (float(rows) - 1.0) * 0.5) * SPAWN_SPACING_Y
	return Vector2(x, y)


func _process_deaths() -> void:
	for controller: UnitController in _attacker_controllers:
		_handle_controller_death(controller)
	for controller: UnitController in _defender_controllers:
		_handle_controller_death(controller)


func _handle_controller_death(controller: UnitController) -> void:
	if controller == null or controller.is_alive():
		return
	if _handled_deaths.has(controller.unit_id):
		return
	_handled_deaths[controller.unit_id] = true

	var actor := _actors.get(controller.unit_id) as UnitActor
	if is_instance_valid(actor):
		actor.play_death()
	_actors.erase(controller.unit_id)
	controller.actor = null


func _update_alive_label() -> void:
	if _alive_label == null:
		return
	var attacker_alive := _count_alive(_attacker_controllers)
	var defender_alive := _count_alive(_defender_controllers)
	_alive_label.text = "我方：%d    敌方：%d" % [attacker_alive, defender_alive]


func _count_alive(controllers: Array[UnitController]) -> int:
	var count: int = 0
	for controller: UnitController in controllers:
		if controller.is_alive():
			count += 1
	return count


func _check_battle_end() -> void:
	var attacker_alive := _count_alive(_attacker_controllers)
	var defender_alive := _count_alive(_defender_controllers)
	if attacker_alive > 0 and defender_alive > 0:
		return

	_battle_over = true
	if attacker_alive == 0 and defender_alive == 0:
		_result = BattleSession.BattleResult.DRAW
	elif attacker_alive > 0:
		_result = BattleSession.BattleResult.ATTACKER_VICTORY
	else:
		_result = BattleSession.BattleResult.DEFENDER_VICTORY
	_show_result()


func _show_result() -> void:
	_result_dim.visible = true
	_result_panel.visible = true
	match _result:
		BattleSession.BattleResult.ATTACKER_VICTORY:
			_result_label.text = "战斗胜利"
		BattleSession.BattleResult.DEFENDER_VICTORY:
			_result_label.text = "战斗失败"
		BattleSession.BattleResult.DRAW:
			_result_label.text = "平局"
		_:
			_result_label.text = "战斗结束"
	_update_alive_label()


func _on_return_pressed() -> void:
	if _returned:
		return
	_returned = true
	_return_button.disabled = true

	if _battle_manager != null and _session != null:
		if not _battle_manager.finish_battle(_session.battle_id, int(_result)):
			push_error("战斗结算失败")

	var error: Error = SceneManager.change_scene(SceneManager.WORLD_MAP_SCENE)
	if error != OK:
		push_error("无法返回大地图（错误码 %s）" % error)


func _abort_to_world_map() -> void:
	if _battle_manager != null and _session != null:
		_battle_manager.abort_battle(_session.battle_id)
	SceneManager.change_scene(SceneManager.WORLD_MAP_SCENE)


func _set_full_rect(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _make_button(text: String, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 36.0)
	button.focus_mode = Control.FOCUS_NONE
	return button
