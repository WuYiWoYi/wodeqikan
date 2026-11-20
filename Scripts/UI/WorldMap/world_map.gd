extends Node2D
## 大地图场景控制器。
##
## 只读取 WorldContext 的权威数据并生成表现节点；
## 移动、时间、存档操作全部通过管理器/GameManager 接口完成。

const INTERACTION_RADIUS: float = 40.0
const INTERACTION_EXIT_RADIUS: float = 64.0
const CAMERA_FOLLOW_SPEED: float = 8.0
const CAMERA_PAN_SPEED: float = 650.0
const CAMERA_ZOOM_MIN: float = 0.5
const CAMERA_ZOOM_MAX: float = 2.0

@onready var map_background: MapBackground = $MapBackground
@onready var world_entities: Node2D = $WorldEntities
@onready var camera: Camera2D = $Camera2D

var _context: WorldContext = null
var _player_party: PartyData = null
var _player_icon: PartyIcon = null
var _camera_offset := Vector2.ZERO
var _last_player_position := Vector2.ZERO
var _settlement_latch_id: String = ""

var _ui_root: Control = null
var _world_time_label: Label = null
var _player_info_label: Label = null
var _pause_button: Button = null
var _speed_one_button: Button = null
var _speed_two_button: Button = null
var _time_buttons: Array[Button] = []

var _settlement_panel: PanelContainer = null
var _settlement_name_label: Label = null
var _settlement_type_label: Label = null
var _settlement_pause_active: bool = false

var _save_dim: ColorRect = null
var _save_panel: PanelContainer = null
var _save_name_edit: LineEdit = null
var _save_status_label: Label = null
var _save_list: ItemList = null
var _save_pause_active: bool = false


func _ready() -> void:
	_context = GameManager.world_context
	if _context == null or not _context.is_valid_world():
		push_error("大地图场景缺少有效的 WorldContext")
		call_deferred("_return_to_main_menu")
		return

	_player_party = _context.get_player_party()
	if _player_party == null:
		push_error("大地图场景找不到玩家部队")
		call_deferred("_return_to_main_menu")
		return

	map_background.set_world_size(_context.world_size)
	_context.world_map_manager.world_bounds = Rect2(Vector2.ZERO, _context.world_size)

	_build_ui()
	_build_world_entities()
	_connect_time_signals()

	camera.position = _player_party.world_position
	_last_player_position = _player_party.world_position
	_update_time_ui()
	_update_player_info()


func _process(delta: float) -> void:
	if _player_party == null:
		return

	_update_camera(delta)
	_update_player_info()
	_check_settlement_interaction()
	_last_player_position = _player_party.world_position


func _unhandled_input(event: InputEvent) -> void:
	if _context == null or _player_party == null or _is_input_blocked():
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			var target := get_global_mouse_position()
			if _context.world_map_manager.set_party_target(_context.player_party_id, target):
				_camera_offset = Vector2.ZERO
			get_viewport().set_input_as_handled()
			return

		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_camera_zoom(camera.zoom.x * 1.1)
			get_viewport().set_input_as_handled()
			return

		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_camera_zoom(camera.zoom.x / 1.1)
			get_viewport().set_input_as_handled()
			return


func _build_world_entities() -> void:
	for child: Node in world_entities.get_children():
		world_entities.remove_child(child)
		child.queue_free()

	for party: PartyData in _context.party_manager.get_all_parties():
		var party_icon: PartyIcon = PartyIcon.new()
		party_icon.name = "PartyIcon_%s" % party.party_id
		world_entities.add_child(party_icon)
		party_icon.setup(party, party.party_id == _context.player_party_id)
		if party.party_id == _context.player_party_id:
			_player_icon = party_icon

	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		var settlement_icon: SettlementIcon = SettlementIcon.new()
		settlement_icon.name = "SettlementIcon_%s" % settlement.settlement_id
		world_entities.add_child(settlement_icon)
		settlement_icon.setup(settlement)

	world_entities.y_sort_enabled = true


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "UI"
	add_child(canvas)

	_ui_root = Control.new()
	_ui_root.name = "WorldMapUI"
	_ui_root.theme = UiTheme.create()
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_full_rect(_ui_root)
	canvas.add_child(_ui_root)

	_build_top_bar()
	_build_bottom_bar()
	_build_settlement_panel()
	_build_save_panel()


func _build_top_bar() -> void:
	var top_bar := PanelContainer.new()
	top_bar.name = "TopBar"
	top_bar.anchor_right = 1.0
	top_bar.offset_bottom = 48.0
	_ui_root.add_child(top_bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	top_bar.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	_world_time_label = _make_label("世界时间", 15)
	_world_time_label.custom_minimum_size = Vector2(320.0, 0.0)
	row.add_child(_world_time_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_pause_button = _make_button("暂停", "PauseButton")
	_pause_button.toggle_mode = true
	_pause_button.pressed.connect(_on_pause_pressed)
	row.add_child(_pause_button)
	_time_buttons.append(_pause_button)

	_speed_one_button = _make_button("1x", "SpeedOneButton")
	_speed_one_button.toggle_mode = true
	_speed_one_button.pressed.connect(_on_speed_one_pressed)
	row.add_child(_speed_one_button)
	_time_buttons.append(_speed_one_button)

	_speed_two_button = _make_button("2x", "SpeedTwoButton")
	_speed_two_button.toggle_mode = true
	_speed_two_button.pressed.connect(_on_speed_two_pressed)
	row.add_child(_speed_two_button)
	_time_buttons.append(_speed_two_button)

	var save_button := _make_button("保存", "SaveButton")
	save_button.pressed.connect(_on_save_pressed)
	row.add_child(save_button)

	var menu_button := _make_button("主菜单", "MainMenuButton")
	menu_button.pressed.connect(_on_main_menu_pressed)
	row.add_child(menu_button)


func _build_bottom_bar() -> void:
	var bottom_bar := PanelContainer.new()
	bottom_bar.name = "BottomBar"
	bottom_bar.anchor_top = 1.0
	bottom_bar.anchor_right = 1.0
	bottom_bar.anchor_bottom = 1.0
	bottom_bar.offset_top = -38.0
	_ui_root.add_child(bottom_bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	bottom_bar.add_child(margin)

	_player_info_label = _make_label("玩家部队", 14)
	margin.add_child(_player_info_label)


func _build_settlement_panel() -> void:
	_settlement_panel = PanelContainer.new()
	_settlement_panel.name = "SettlementPanel"
	_settlement_panel.visible = false
	_settlement_panel.anchor_top = 0.5
	_settlement_panel.anchor_bottom = 0.5
	_settlement_panel.offset_left = 20.0
	_settlement_panel.offset_top = -110.0
	_settlement_panel.offset_right = 340.0
	_settlement_panel.offset_bottom = 110.0
	_ui_root.add_child(_settlement_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_settlement_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	_settlement_name_label = _make_label("", 24)
	_settlement_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_settlement_name_label)

	_settlement_type_label = _make_label("", 16)
	_settlement_type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_settlement_type_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	var leave_button := _make_button("离开地点", "SettlementLeaveButton")
	leave_button.custom_minimum_size = Vector2(0.0, 36.0)
	leave_button.pressed.connect(_on_settlement_leave_pressed)
	column.add_child(leave_button)


func _build_save_panel() -> void:
	_save_dim = ColorRect.new()
	_save_dim.name = "SaveDim"
	_save_dim.color = Color(0.0, 0.0, 0.0, 0.45)
	_save_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_save_dim.visible = false
	_set_full_rect(_save_dim)
	_ui_root.add_child(_save_dim)

	_save_panel = PanelContainer.new()
	_save_panel.name = "SavePanel"
	_save_panel.visible = false
	_save_panel.anchor_left = 0.5
	_save_panel.anchor_top = 0.5
	_save_panel.anchor_right = 0.5
	_save_panel.anchor_bottom = 0.5
	_save_panel.offset_left = -250.0
	_save_panel.offset_top = -230.0
	_save_panel.offset_right = 250.0
	_save_panel.offset_bottom = 230.0
	_ui_root.add_child(_save_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_save_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var title := _make_label("保存游戏", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	column.add_child(_make_label("存档名称", 14))
	_save_name_edit = LineEdit.new()
	_save_name_edit.name = "SaveNameEdit"
	_save_name_edit.placeholder_text = "例如 save_1"
	_save_name_edit.text = "save_1"
	column.add_child(_save_name_edit)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)

	var save_button := _make_button("保存", "ConfirmSaveButton")
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.pressed.connect(_on_confirm_save_pressed)
	buttons.add_child(save_button)

	var back_button := _make_button("返回", "CloseSaveButton")
	back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_button.pressed.connect(_on_close_save_pressed)
	buttons.add_child(back_button)

	_save_status_label = _make_label("", 14)
	_save_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_save_status_label.custom_minimum_size = Vector2(0.0, 40.0)
	column.add_child(_save_status_label)

	column.add_child(_make_label("已有存档", 14))
	_save_list = ItemList.new()
	_save_list.name = "SaveList"
	_save_list.custom_minimum_size = Vector2(0.0, 170.0)
	_save_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_save_list.item_selected.connect(_on_save_list_item_selected)
	column.add_child(_save_list)


func _connect_time_signals() -> void:
	if not TimeManager.world_speed_changed.is_connected(_on_world_speed_changed):
		TimeManager.world_speed_changed.connect(_on_world_speed_changed)
	if not TimeManager.world_time_changed.is_connected(_on_world_time_changed):
		TimeManager.world_time_changed.connect(_on_world_time_changed)


func _update_camera(delta: float) -> void:
	if not _is_input_blocked():
		var pan := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if pan != Vector2.ZERO:
			_camera_offset += pan * CAMERA_PAN_SPEED * delta / camera.zoom.x

	var desired := _player_party.world_position + _camera_offset
	var viewport_size := get_viewport_rect().size
	var half_view := viewport_size / (2.0 * camera.zoom.x)
	var world_size := _context.world_size

	if world_size.x > half_view.x * 2.0:
		desired.x = clampf(desired.x, half_view.x, world_size.x - half_view.x)
	else:
		desired.x = world_size.x * 0.5
	if world_size.y > half_view.y * 2.0:
		desired.y = clampf(desired.y, half_view.y, world_size.y - half_view.y)
	else:
		desired.y = world_size.y * 0.5

	var weight: float = 1.0 - exp(-CAMERA_FOLLOW_SPEED * delta)
	camera.position = camera.position.lerp(desired, weight)


func _set_camera_zoom(value: float) -> void:
	var zoom_value: float = clampf(value, CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX)
	camera.zoom = Vector2(zoom_value, zoom_value)


func _check_settlement_interaction() -> void:
	if _save_panel.visible or _settlement_panel.visible:
		return

	if _settlement_latch_id.is_empty():
		for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
			var closest := Geometry2D.get_closest_point_to_segment(
				settlement.world_position, _last_player_position, _player_party.world_position
			)
			if closest.distance_to(settlement.world_position) <= INTERACTION_RADIUS:
				_open_settlement(settlement)
				return
	else:
		var active: SettlementData = _context.settlement_manager.get_settlement(_settlement_latch_id)
		if active == null \
				or _player_party.world_position.distance_to(active.world_position) > INTERACTION_EXIT_RADIUS:
			_settlement_latch_id = ""


func _open_settlement(settlement: SettlementData) -> void:
	_settlement_latch_id = settlement.settlement_id
	_context.world_map_manager.stop_party(_context.player_party_id)
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	TimeManager.push_pause(GameManager.PAUSE_REASON_UI_PANEL)
	_settlement_pause_active = true

	_settlement_name_label.text = settlement.display_name
	_settlement_type_label.text = _settlement_type_text(settlement.settlement_type)
	_settlement_panel.visible = true
	_set_time_buttons_enabled(false)
	_update_time_ui()


func _on_settlement_leave_pressed() -> void:
	_settlement_panel.visible = false
	if _settlement_pause_active:
		TimeManager.pop_pause(GameManager.PAUSE_REASON_UI_PANEL)
		_settlement_pause_active = false
	# 不恢复时间：离开地点后仍保持暂停，玩家需主动选择 1x / 2x。
	_set_time_buttons_enabled(true)
	_update_time_ui()


func _on_pause_pressed() -> void:
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	_update_time_ui()


func _on_speed_one_pressed() -> void:
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)
	_update_time_ui()


func _on_speed_two_pressed() -> void:
	TimeManager.set_base_world_speed(TimeManager.SPEED_DOUBLE)
	_update_time_ui()


func _on_save_pressed() -> void:
	if _settlement_panel.visible:
		return
	_save_panel.visible = true
	_save_dim.visible = true
	TimeManager.push_pause(GameManager.PAUSE_REASON_UI_PANEL)
	_save_pause_active = true
	_set_time_buttons_enabled(false)
	_save_status_label.text = ""
	_save_name_edit.text = _default_slot_name()
	_refresh_save_list()
	_update_time_ui()


func _on_close_save_pressed() -> void:
	_save_panel.visible = false
	_save_dim.visible = false
	if _save_pause_active:
		TimeManager.pop_pause(GameManager.PAUSE_REASON_UI_PANEL)
		_save_pause_active = false
	_set_time_buttons_enabled(true)
	_update_time_ui()


func _on_confirm_save_pressed() -> void:
	var slot_name := _save_name_edit.text.strip_edges()
	if slot_name.is_empty():
		_save_status_label.text = "请输入存档名称"
		return

	var error: Error = GameManager.save_game(slot_name)
	if error == OK:
		_save_status_label.text = "保存成功：%s" % slot_name
		_refresh_save_list()
	else:
		_save_status_label.text = "保存失败（错误码 %s）" % error


func _on_save_list_item_selected(index: int) -> void:
	var slot_name: Variant = _save_list.get_item_metadata(index)
	if slot_name is String:
		_save_name_edit.text = slot_name


func _refresh_save_list() -> void:
	_save_list.clear()
	for info: Dictionary in SaveManager.list_save_infos():
		if not bool(info.get("valid", false)):
			continue
		var saved_at := str(info.get("saved_at", "未知时间")).replace("T", " ")
		var index: int = _save_list.add_item("%s    %s" % [str(info.get("slot", "")), saved_at])
		_save_list.set_item_metadata(index, str(info.get("slot", "")))


func _on_main_menu_pressed() -> void:
	GameManager.enter_main_menu()


func _on_world_speed_changed(_effective_scale: float) -> void:
	_update_time_ui()


func _on_world_time_changed(_total_seconds: float) -> void:
	_update_time_ui()


func _update_time_ui() -> void:
	if _world_time_label == null:
		return
	var effective := TimeManager.get_effective_world_scale()
	var speed_text := "暂停"
	if is_equal_approx(effective, TimeManager.SPEED_NORMAL):
		speed_text = "1x"
	elif is_equal_approx(effective, TimeManager.SPEED_DOUBLE):
		speed_text = "2x"

	_world_time_label.text = "世界时间：%s    倍率：%s" % [
		_format_world_time(TimeManager.world_elapsed_seconds), speed_text
	]

	if _pause_button != null:
		_pause_button.button_pressed = is_zero_approx(effective)
		_speed_one_button.button_pressed = is_equal_approx(effective, TimeManager.SPEED_NORMAL)
		_speed_two_button.button_pressed = is_equal_approx(effective, TimeManager.SPEED_DOUBLE)


func _update_player_info() -> void:
	if _player_info_label == null or _player_party == null:
		return
	_player_info_label.text = "%s    坐标 (%d, %d)    状态：%s" % [
		_player_party.party_name,
		int(round(_player_party.world_position.x)),
		int(round(_player_party.world_position.y)),
		"移动中" if _player_party.movement_state == PartyData.MovementState.MOVING else "待命",
	]


func _set_time_buttons_enabled(enabled: bool) -> void:
	for button: Button in _time_buttons:
		button.disabled = not enabled


func _is_input_blocked() -> bool:
	return _save_panel != null and (_save_panel.visible or _settlement_panel.visible)


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
	button.custom_minimum_size = Vector2(64.0, 30.0)
	button.focus_mode = Control.FOCUS_NONE
	return button


func _format_world_time(total_seconds: float) -> String:
	var total: int = maxi(0, int(total_seconds))
	var days: int = floori(float(total) / 86400.0) + 1
	var remainder: int = total % 86400
	var hours: int = floori(float(remainder) / 3600.0)
	var minutes: int = floori(float(remainder % 3600) / 60.0)
	var seconds: int = remainder % 60
	return "第 %d 天 %02d:%02d:%02d" % [days, hours, minutes, seconds]


func _settlement_type_text(type: SettlementData.SettlementType) -> String:
	match type:
		SettlementData.SettlementType.CASTLE:
			return "城堡"
		SettlementData.SettlementType.TOWN:
			return "城镇"
		_:
			return "村庄"


func _default_slot_name() -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	return "save_%s" % stamp


func _return_to_main_menu() -> void:
	GameManager.enter_main_menu()
