extends Control
## 主菜单：新游戏、继续、读取、设置占位、退出。
##
## UI 只发起操作请求；世界恢复统一由 GameManager 执行。

var _continue_button: Button = null
var _status_label: Label = null

var _load_dim: ColorRect = null
var _load_panel: PanelContainer = null
var _load_list: ItemList = null
var _load_button: Button = null
var _selected_slot: String = ""

var _settings_dim: ColorRect = null
var _settings_panel: PanelContainer = null


func _ready() -> void:
	theme = UiTheme.create()
	_build_ui()
	_refresh_continue_button()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.name = "Background"
	background.color = Color("#10151c")
	_set_full_rect(background)
	add_child(background)

	var center := CenterContainer.new()
	center.name = "Center"
	_set_full_rect(center)
	add_child(center)

	var column := VBoxContainer.new()
	column.name = "MenuColumn"
	column.custom_minimum_size = Vector2(340.0, 0.0)
	column.add_theme_constant_override("separation", 10)
	center.add_child(column)

	var title := _make_label("我的骑砍", 46)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var subtitle := _make_label("阶段 5 · 战斗与大地图原型", 16)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color("#9fb0c2"))
	column.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 16.0)
	column.add_child(spacer)

	var new_game_button := _make_button("新游戏", "NewGameButton", 44.0)
	new_game_button.pressed.connect(_on_new_game_pressed)
	column.add_child(new_game_button)

	_continue_button = _make_button("继续游戏", "ContinueButton", 44.0)
	_continue_button.pressed.connect(_on_continue_pressed)
	column.add_child(_continue_button)

	var load_button := _make_button("读取存档", "LoadGameButton", 44.0)
	load_button.pressed.connect(_on_load_game_pressed)
	column.add_child(load_button)

	var settings_button := _make_button("设置", "SettingsButton", 44.0)
	settings_button.pressed.connect(_on_settings_pressed)
	column.add_child(settings_button)

	var quit_button := _make_button("退出游戏", "QuitButton", 44.0)
	quit_button.pressed.connect(_on_quit_pressed)
	column.add_child(quit_button)

	_status_label = _make_label("", 14)
	_status_label.name = "StatusLabel"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.custom_minimum_size = Vector2(0.0, 28.0)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", Color("#e2b86b"))
	column.add_child(_status_label)

	_build_load_panel()
	_build_settings_panel()


func _build_load_panel() -> void:
	_load_dim = ColorRect.new()
	_load_dim.name = "LoadDim"
	_load_dim.color = Color(0.0, 0.0, 0.0, 0.5)
	_load_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_load_dim.visible = false
	_set_full_rect(_load_dim)
	add_child(_load_dim)

	_load_panel = PanelContainer.new()
	_load_panel.name = "LoadPanel"
	_load_panel.visible = false
	_center_panel(_load_panel, Vector2(560.0, 420.0))
	add_child(_load_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_load_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := _make_label("读取存档", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	_load_list = ItemList.new()
	_load_list.name = "LoadList"
	_load_list.custom_minimum_size = Vector2(0.0, 220.0)
	_load_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_load_list.item_selected.connect(_on_load_item_selected)
	_load_list.item_activated.connect(_on_load_item_activated)
	column.add_child(_load_list)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)

	_load_button = _make_button("读取", "LoadButton", 38.0)
	_load_button.disabled = true
	_load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_load_button.pressed.connect(_on_load_confirmed)
	buttons.add_child(_load_button)

	var back_button := _make_button("返回", "LoadBackButton", 38.0)
	back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_button.pressed.connect(_hide_load_panel)
	buttons.add_child(back_button)


func _build_settings_panel() -> void:
	_settings_dim = ColorRect.new()
	_settings_dim.name = "SettingsDim"
	_settings_dim.color = Color(0.0, 0.0, 0.0, 0.5)
	_settings_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_dim.visible = false
	_set_full_rect(_settings_dim)
	add_child(_settings_dim)

	_settings_panel = PanelContainer.new()
	_settings_panel.name = "SettingsPanel"
	_settings_panel.visible = false
	_center_panel(_settings_panel, Vector2(420.0, 220.0))
	add_child(_settings_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_settings_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	var title := _make_label("设置", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var text := _make_label("设置功能将在后续版本实现。", 15)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(text)

	var close_button := _make_button("关闭", "SettingsCloseButton", 36.0)
	close_button.pressed.connect(_hide_settings_panel)
	column.add_child(close_button)


func _on_new_game_pressed() -> void:
	_status_label.text = ""
	if not GameManager.start_new_game():
		_status_label.text = "新游戏创建失败，请查看日志。"


func _on_continue_pressed() -> void:
	_status_label.text = ""
	if not GameManager.continue_game():
		_status_label.text = "没有可用的存档。"


func _on_load_game_pressed() -> void:
	_status_label.text = ""
	_refresh_load_list()
	_load_panel.visible = true
	_load_dim.visible = true


func _hide_load_panel() -> void:
	_load_panel.visible = false
	_load_dim.visible = false


func _refresh_load_list() -> void:
	_load_list.clear()
	_selected_slot = ""
	_load_button.disabled = true

	for info: Dictionary in SaveManager.list_save_infos():
		if not bool(info.get("valid", false)):
			continue
		var slot_name := str(info.get("slot", ""))
		var saved_at := str(info.get("saved_at", "")).replace("T", " ")
		if saved_at.is_empty():
			saved_at = "未知时间"
		var index: int = _load_list.add_item("%s    %s" % [slot_name, saved_at])
		_load_list.set_item_metadata(index, slot_name)

	# 必须先选择一个存档才能读取。
	_load_button.disabled = true


func _on_load_item_selected(index: int) -> void:
	var slot_value: Variant = _load_list.get_item_metadata(index)
	if slot_value is String:
		_selected_slot = slot_value
		_load_button.disabled = _selected_slot.is_empty()


func _on_load_item_activated(index: int) -> void:
	_on_load_item_selected(index)
	_on_load_confirmed()


func _on_load_confirmed() -> void:
	if _selected_slot.is_empty():
		_status_label.text = "请选择一个存档。"
		return
	_status_label.text = ""
	if not GameManager.load_game(_selected_slot):
		_status_label.text = "存档读取失败，文件可能已损坏。"
		return
	_hide_load_panel()


func _on_settings_pressed() -> void:
	_settings_panel.visible = true
	_settings_dim.visible = true


func _hide_settings_panel() -> void:
	_settings_panel.visible = false
	_settings_dim.visible = false


func _on_quit_pressed() -> void:
	GameManager.quit_game()


func _refresh_continue_button() -> void:
	_continue_button.disabled = SaveManager.get_latest_save_slot().is_empty()


func _set_full_rect(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0


func _center_panel(panel: Control, panel_size: Vector2) -> void:
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -panel_size.x * 0.5
	panel.offset_top = -panel_size.y * 0.5
	panel.offset_right = panel_size.x * 0.5
	panel.offset_bottom = panel_size.y * 0.5


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _make_button(text: String, node_name: String, min_height: float) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(0.0, min_height)
	button.focus_mode = Control.FOCUS_NONE
	return button
