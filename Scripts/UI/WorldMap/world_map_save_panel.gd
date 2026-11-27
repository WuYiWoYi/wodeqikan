class_name WorldMapSavePanel
extends Control
## 大地图存档覆盖层：只负责面板显隐、存档名与槽位列表。
## 写盘统一走 GameManager；暂停原因由大地图覆盖层登记簿持有。

signal closed

const MapUiKitScript = preload("res://Scripts/UI/WorldMap/map_ui_kit.gd")

var _dim: ColorRect = null
var _panel: PanelContainer = null
var _name_edit: LineEdit = null
var _status_label: Label = null
var _save_list: ItemList = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	MapUiKitScript.set_full_rect(self)
	_build()


func get_panel() -> Control:
	return _panel


func is_open() -> bool:
	return _panel != null and _panel.visible


func open() -> void:
	if _panel == null:
		return
	_panel.visible = true
	_dim.visible = true
	_status_label.text = ""
	_name_edit.text = _default_slot_name()
	_refresh_list()


func close() -> void:
	if not is_open():
		return
	_panel.visible = false
	_dim.visible = false
	closed.emit()


func _build() -> void:
	_dim = ColorRect.new()
	_dim.name = "SaveDim"
	_dim.color = Color(0.0, 0.0, 0.0, 0.45)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	MapUiKitScript.set_full_rect(_dim)
	add_child(_dim)

	_panel = PanelContainer.new()
	_panel.name = "SavePanel"
	_panel.visible = false
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -250.0
	_panel.offset_top = -230.0
	_panel.offset_right = 250.0
	_panel.offset_bottom = 230.0
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var title := MapUiKitScript.make_label("保存游戏", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	column.add_child(MapUiKitScript.make_label("存档名称", 14))
	_name_edit = LineEdit.new()
	_name_edit.name = "SaveNameEdit"
	_name_edit.placeholder_text = "例如 save_1"
	_name_edit.text = "save_1"
	column.add_child(_name_edit)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)

	var save_button := MapUiKitScript.make_button("保存", "ConfirmSaveButton")
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.pressed.connect(_on_confirm_save_pressed)
	buttons.add_child(save_button)

	var back_button := MapUiKitScript.make_button("返回", "CloseSaveButton")
	back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_button.pressed.connect(close)
	buttons.add_child(back_button)

	_status_label = MapUiKitScript.make_label("", 14)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(0.0, 40.0)
	column.add_child(_status_label)

	column.add_child(MapUiKitScript.make_label("已有存档", 14))
	_save_list = ItemList.new()
	_save_list.name = "SaveList"
	_save_list.custom_minimum_size = Vector2(0.0, 170.0)
	_save_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_save_list.item_selected.connect(_on_save_list_item_selected)
	column.add_child(_save_list)


func _on_confirm_save_pressed() -> void:
	var slot_name := _name_edit.text.strip_edges()
	if slot_name.is_empty():
		_status_label.text = "请输入存档名称"
		return
	var error: Error = GameManager.save_game(slot_name)
	if error == OK:
		_status_label.text = "保存成功：%s" % slot_name
		_refresh_list()
	else:
		_status_label.text = "保存失败（错误码 %s）" % error


func _on_save_list_item_selected(index: int) -> void:
	var slot_name: Variant = _save_list.get_item_metadata(index)
	if slot_name is String:
		_name_edit.text = slot_name


func _refresh_list() -> void:
	_save_list.clear()
	for info: Dictionary in SaveManager.list_save_infos():
		if not bool(info.get("valid", false)):
			continue
		var saved_at := str(info.get("saved_at", "未知时间")).replace("T", " ")
		var index: int = _save_list.add_item(
			"%s    %s" % [str(info.get("slot", "")), saved_at]
		)
		_save_list.set_item_metadata(index, str(info.get("slot", "")))


func _default_slot_name() -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	return "save_%s" % stamp
