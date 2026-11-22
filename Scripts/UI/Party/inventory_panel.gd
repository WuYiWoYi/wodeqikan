class_name InventoryPanel
extends Control
## 玩家背包面板（大地图）。
##
## 只读取 PlayerProfile / UnitManager / ItemManager 的权威数据；
## 不提供增减物品接口，也不直接修改金币。打开/关闭的暂停原因由 WorldMap 管理。

signal closed

const WINDOW_SIZE := Vector2(860.0, 620.0)

var _context: WorldContext = null
var _selected_item_id: String = ""

var _gold_label: Label = null
var _item_list: VBoxContainer = null
var _empty_label: Label = null
var _detail_name_label: Label = null
var _detail_type_label: Label = null
var _detail_count_label: Label = null
var _detail_description_label: Label = null
var _item_buttons: Dictionary = {}


func setup(context: WorldContext) -> void:
	_context = context
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_full_rect(self)
	_build()


func open() -> void:
	visible = true
	refresh()


func close() -> void:
	visible = false
	closed.emit()


func get_selected_item_id() -> String:
	return _selected_item_id


## 当前背包中数量大于 0 的物品 ID，按显示名 + ID 稳定排序。
func get_display_item_ids() -> Array[String]:
	var ids: Array[String] = []
	for entry: Dictionary in _collect_entries():
		ids.append(str(entry["item_id"]))
	return ids


## 从权威数据重建列表与详情；同 ID 物品只显示一个条目。
func refresh() -> void:
	if _context == null or _item_list == null:
		return
	_gold_label.text = "当前金币：%d" % _context.player_profile.gold

	var entries: Array[Dictionary] = _collect_entries()
	_clear_children(_item_list)
	_item_buttons.clear()
	_empty_label.visible = entries.is_empty()

	for entry: Dictionary in entries:
		var item_id: String = str(entry["item_id"])
		var button := Button.new()
		button.name = "InventoryItem_%s" % item_id
		button.text = "%s  ×%d    %s" % [
			str(entry["name"]), int(entry["count"]), str(entry["type_text"])
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0.0, 36.0)
		button.pressed.connect(_on_item_pressed.bind(item_id))
		_item_list.add_child(button)
		_item_buttons[item_id] = button

	if entries.is_empty():
		_selected_item_id = ""
		_clear_detail()
		return
	if _selected_item_id.is_empty() or not _item_buttons.has(_selected_item_id):
		_selected_item_id = str(entries[0]["item_id"])
	_apply_selection()


func _collect_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if _context == null:
		return entries
	var profile: PlayerProfile = _context.player_profile
	var seen: Dictionary = {}
	for item_id_value: Variant in profile.inventory:
		seen[str(item_id_value)] = true
	for item_id_value: Variant in profile.item_counts:
		seen[str(item_id_value)] = true

	for item_id_value: Variant in seen:
		var item_id: String = str(item_id_value)
		var count: int = profile.get_item_count(item_id)
		if item_id.is_empty() or count <= 0:
			continue
		entries.append({
			"item_id": item_id,
			"name": _item_display_name(item_id),
			"count": count,
			"type_text": _item_type_text(item_id),
		})

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var name_a: String = str(a["name"])
		var name_b: String = str(b["name"])
		if name_a == name_b:
			return str(a["item_id"]) < str(b["item_id"])
		return name_a < name_b
	)
	return entries


func _on_item_pressed(item_id: String) -> void:
	if not _item_buttons.has(item_id):
		return
	_selected_item_id = item_id
	_apply_selection()


func _apply_selection() -> void:
	for item_id_value: Variant in _item_buttons:
		var item_id: String = str(item_id_value)
		var button := _item_buttons[item_id] as Button
		if button != null:
			button.disabled = item_id == _selected_item_id
	var entry := _find_entry(_selected_item_id)
	if entry.is_empty():
		_clear_detail()
		return
	_detail_name_label.text = str(entry["name"])
	_detail_type_label.text = "类型：%s" % str(entry["type_text"])
	_detail_count_label.text = "持有数量：%d" % int(entry["count"])
	_detail_description_label.text = _item_description(_selected_item_id)


func _find_entry(item_id: String) -> Dictionary:
	for entry: Dictionary in _collect_entries():
		if str(entry["item_id"]) == item_id:
			return entry
	return {}


func _clear_detail() -> void:
	if _detail_name_label == null:
		return
	_detail_name_label.text = "未选择物品"
	_detail_type_label.text = ""
	_detail_count_label.text = ""
	_detail_description_label.text = ""


func _item_display_name(item_id: String) -> String:
	if _context != null and _context.unit_manager != null:
		var equipment := _context.unit_manager.get_equipment_config(item_id)
		if equipment != null:
			return equipment.display_name
	if _context != null and _context.item_manager != null:
		var item := _context.item_manager.get_item_config(item_id)
		if item != null:
			return item.display_name
	# 不认识的历史物品 ID 也不能让 UI 崩溃。
	return "未知物品（%s）" % item_id if not item_id.is_empty() else "未知物品"


func _item_type_text(item_id: String) -> String:
	if _context != null and _context.unit_manager != null:
		var equipment := _context.unit_manager.get_equipment_config(item_id)
		if equipment != null:
			return "%s（装备）" % equipment.slot_display_name()
	if _context != null and _context.item_manager != null:
		var item := _context.item_manager.get_item_config(item_id)
		if item != null:
			return item.type_display_name()
	return "未知"


func _item_description(item_id: String) -> String:
	if _context != null and _context.unit_manager != null:
		var equipment := _context.unit_manager.get_equipment_config(item_id)
		if equipment != null:
			var lines: Array[String] = []
			lines.append("可装备槽位：%s" % equipment.slot_display_name())
			var bonus: String = equipment.bonus_text()
			lines.append("属性加成：%s" % (bonus if not bonus.is_empty() else "无"))
			return "\n".join(lines)
	if _context != null and _context.item_manager != null:
		var item := _context.item_manager.get_item_config(item_id)
		if item != null:
			return item.description if not item.description.is_empty() else "暂无描述。"
	return "该物品缺少静态配置，仅显示当前持有数量。"


func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "InventoryPanelDim"
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_set_full_rect(dim)
	add_child(dim)

	var window := PanelContainer.new()
	window.name = "InventoryPanelWindow"
	window.anchor_left = 0.5
	window.anchor_top = 0.5
	window.anchor_right = 0.5
	window.anchor_bottom = 0.5
	window.offset_left = -WINDOW_SIZE.x * 0.5
	window.offset_top = -WINDOW_SIZE.y * 0.5
	window.offset_right = WINDOW_SIZE.x * 0.5
	window.offset_bottom = WINDOW_SIZE.y * 0.5
	add_child(window)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	window.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)

	var title := _make_label("玩家背包", 24)
	title.name = "InventoryTitleLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_gold_label = _make_label("当前金币：0", 16)
	_gold_label.name = "InventoryGoldLabel"
	header.add_child(_gold_label)

	var close_button := Button.new()
	close_button.name = "InventoryCloseButton"
	close_button.text = "关闭"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(80.0, 32.0)
	close_button.pressed.connect(close)
	header.add_child(close_button)

	column.add_child(HSeparator.new())

	var content := HBoxContainer.new()
	content.name = "InventoryContent"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	column.add_child(content)

	var list_column := VBoxContainer.new()
	list_column.custom_minimum_size = Vector2(420.0, 0.0)
	list_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(list_column)
	list_column.add_child(_make_label("物品列表", 16))

	var list_scroll := ScrollContainer.new()
	list_scroll.name = "InventoryScroll"
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_column.add_child(list_scroll)

	_item_list = VBoxContainer.new()
	_item_list.name = "InventoryItemList"
	_item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_list.add_theme_constant_override("separation", 6)
	list_scroll.add_child(_item_list)

	_empty_label = _make_label("背包中没有物品", 14)
	_empty_label.name = "InventoryEmptyLabel"
	_empty_label.visible = false
	list_column.add_child(_empty_label)

	content.add_child(VSeparator.new())

	var detail_column := VBoxContainer.new()
	detail_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_column.add_theme_constant_override("separation", 8)
	content.add_child(detail_column)
	detail_column.add_child(_make_label("物品详情", 16))

	_detail_name_label = _make_label("未选择物品", 20)
	_detail_name_label.name = "InventoryDetailNameLabel"
	detail_column.add_child(_detail_name_label)

	_detail_type_label = _make_label("", 15)
	_detail_type_label.name = "InventoryDetailTypeLabel"
	detail_column.add_child(_detail_type_label)

	_detail_count_label = _make_label("", 15)
	_detail_count_label.name = "InventoryDetailCountLabel"
	detail_column.add_child(_detail_count_label)

	_detail_description_label = _make_label("", 14)
	_detail_description_label.name = "InventoryDetailDescriptionLabel"
	_detail_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_description_label.custom_minimum_size = Vector2(300.0, 0.0)
	detail_column.add_child(_detail_description_label)


func _clear_children(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _make_label(label_text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _set_full_rect(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0
