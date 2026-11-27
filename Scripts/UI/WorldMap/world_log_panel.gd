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
## 大地图折叠态只显示最新一条事件文本，高度按单行文本与内边距计算。
const COLLAPSED_HEIGHT: float = 42.0

var _log_manager: WorldLogManager = null
var _scroll: ScrollContainer = null
var _content: VBoxContainer = null
var _title: Label = null
var _separator: HSeparator = null
var _collapsed_label: Label = null

## 大地图日志默认折叠为纯事件文本；村庄等场景保持完整面板。
var _collapsible: bool = false
var _expanded: bool = true


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
		_refresh_collapsed_text()
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

	_refresh_collapsed_text()
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

	_title = _make_label("世界日志", 16)
	_title.name = "WorldLogTitle"
	column.add_child(_title)

	_separator = HSeparator.new()
	_separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_separator)

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

	# 折叠态只保留最新事件文本；标题、分隔线与滚动区域隐藏。
	_collapsed_label = _make_label("", 13)
	_collapsed_label.name = "WorldLogCollapsedText"
	_collapsed_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_collapsed_label.clip_text = true
	_collapsed_label.add_theme_color_override("font_color", Color("#f3ead6"))
	_collapsed_label.add_theme_color_override(
		"font_shadow_color", Color(0.0, 0.0, 0.0, 0.9)
	)
	_collapsed_label.add_theme_constant_override("shadow_offset_x", 1)
	_collapsed_label.add_theme_constant_override("shadow_offset_y", 1)
	_collapsed_label.visible = false
	column.add_child(_collapsed_label)


## 大地图启用折叠；村庄等共享面板保持完整显示。
func set_collapsible(value: bool) -> void:
	_collapsible = value
	_expanded = not value
	_apply_visibility_state()


func is_collapsible() -> bool:
	return _collapsible


func is_expanded() -> bool:
	return _expanded


func is_collapsed() -> bool:
	return _collapsible and not _expanded


func expand() -> void:
	if not _collapsible or _expanded:
		return
	_expanded = true
	_apply_visibility_state()
	call_deferred("_scroll_to_bottom")


func collapse() -> void:
	if not _collapsible or not _expanded:
		return
	_expanded = false
	_apply_visibility_state()


## 折叠时只替换面板装饰与容器表现，事件文本保持可见。
func _apply_visibility_state() -> void:
	if _scroll == null or _title == null or _separator == null \
			or _collapsed_label == null:
		return
	var expanded: bool = not _collapsible or _expanded
	_title.visible = expanded
	_separator.visible = expanded
	_scroll.visible = expanded
	_collapsed_label.visible = not expanded
	if expanded:
		remove_theme_stylebox_override("panel")
		mouse_filter = Control.MOUSE_FILTER_STOP if _collapsible \
			else Control.MOUSE_FILTER_PASS
		offset_top = -BOTTOM_MARGIN - PANEL_HEIGHT
		offset_bottom = -BOTTOM_MARGIN
	else:
		# 折叠态不绘制底板，也不拦截任何鼠标事件。
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		offset_top = -BOTTOM_MARGIN - COLLAPSED_HEIGHT
		offset_bottom = -BOTTOM_MARGIN


func get_collapsed_text() -> String:
	return _collapsed_label.text if _collapsed_label != null else ""


## 折叠态可点击展开的区域：只有事件文本本身，不包含面板空白范围。
func get_collapsed_interaction_rect() -> Rect2:
	if _collapsed_label == null or not _collapsed_label.visible:
		return Rect2()
	var rect := _collapsed_label.get_global_rect()
	var font := _collapsed_label.get_theme_font("font")
	var font_size: int = _collapsed_label.get_theme_font_size("font_size")
	var text_width: float = rect.size.x
	if font != null and not _collapsed_label.text.is_empty():
		text_width = font.get_string_size(
			_collapsed_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size
		).x
	rect.size.x = clampf(text_width + 4.0, 1.0, rect.size.x)
	rect.size.y = maxf(rect.size.y, 18.0)
	return rect


func _refresh_collapsed_text() -> void:
	if _collapsed_label == null:
		return
	var entries: Array[WorldLogEntry] = (
		_log_manager.get_entries() if _log_manager != null else []
	)
	_collapsed_label.text = entries[-1].text if not entries.is_empty() \
		else "暂无世界事件"


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
