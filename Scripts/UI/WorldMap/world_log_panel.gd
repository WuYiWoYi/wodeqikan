class_name WorldLogPanel
extends PanelContainer
## 大地图与村庄共用的世界日志面板。
##
## 只读取 WorldLogManager 的条目；订阅 entry_added 自动刷新。
## 节点名称保持 WorldLogPanel / WorldLogScroll / WorldLogContent / WorldLogTitle，
## 便于自动化测试在任一场景中稳定查找。

const PANEL_WIDTH: float = 460.0
const PANEL_HEIGHT: float = 220.0
const BOTTOM_MARGIN: float = 54.0

var _log_manager: WorldLogManager = null
var _scroll: ScrollContainer = null
var _content: VBoxContainer = null


func _ready() -> void:
	_build()


func _exit_tree() -> void:
	unbind()


func setup(log_manager: WorldLogManager) -> void:
	unbind()
	_log_manager = log_manager
	if _log_manager != null and not _log_manager.entry_added.is_connected(
		_on_entry_added
	):
		_log_manager.entry_added.connect(_on_entry_added)
	rebuild()


func unbind() -> void:
	if _log_manager != null and _log_manager.entry_added.is_connected(_on_entry_added):
		_log_manager.entry_added.disconnect(_on_entry_added)
	_log_manager = null


func rebuild() -> void:
	if _content == null:
		return
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()

	var entries: Array[WorldLogEntry] = (
		_log_manager.get_entries() if _log_manager != null else []
	)
	if entries.is_empty():
		var empty := _make_label("暂无世界事件", 12)
		empty.name = "WorldLogEmpty"
		empty.modulate = Color(0.82, 0.82, 0.78)
		_content.add_child(empty)
		return

	for index: int in range(entries.size()):
		var entry: WorldLogEntry = entries[index]
		var line: String = entry.text
		if not entry.time_text.is_empty():
			line = "%s  %s" % [entry.time_text, entry.text]
		var label := _make_label(line, 12)
		label.name = "WorldLogEntry_%d" % index
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.custom_minimum_size = Vector2(PANEL_WIDTH - 56.0, 0.0)
		_content.add_child(label)

	call_deferred("_scroll_to_bottom")


func get_log_text() -> String:
	var lines: Array[String] = []
	if _log_manager != null:
		for entry: WorldLogEntry in _log_manager.get_entries():
			lines.append(entry.text)
	return "\n".join(lines)


func get_entry_count() -> int:
	return _log_manager.get_entry_count() if _log_manager != null else 0


func _build() -> void:
	name = "WorldLogPanel"
	anchor_left = 0.0
	anchor_top = 1.0
	anchor_right = 0.0
	anchor_bottom = 1.0
	offset_left = 12.0
	offset_right = 12.0 + PANEL_WIDTH
	offset_top = -BOTTOM_MARGIN - PANEL_HEIGHT
	offset_bottom = -BOTTOM_MARGIN
	mouse_filter = Control.MOUSE_FILTER_PASS

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)

	var title := _make_label("世界日志", 16)
	title.name = "WorldLogTitle"
	column.add_child(title)

	var separator := HSeparator.new()
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(separator)

	_scroll = ScrollContainer.new()
	_scroll.name = "WorldLogScroll"
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	column.add_child(_scroll)

	_content = VBoxContainer.new()
	_content.name = "WorldLogContent"
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 3)
	_scroll.add_child(_content)


func _scroll_to_bottom() -> void:
	if _scroll == null:
		return
	var scroll_bar := _scroll.get_v_scroll_bar()
	if scroll_bar != null:
		_scroll.scroll_vertical = int(scroll_bar.max_value)


func _on_entry_added(_entry: WorldLogEntry) -> void:
	rebuild()


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	return label
