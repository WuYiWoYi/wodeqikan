class_name PartyMemberItem
extends Button
## 部队面板中的单条士兵列表项。
##
## 只读取 UnitData / UnitConfig 的现成字段，不计算属性。

var unit_id: String = ""

var _name_label: Label = null
var _class_label: Label = null
var _stats_label: Label = null
var _status_label: Label = null
var _selected: bool = false


func setup(unit: UnitData, config: UnitConfig) -> void:
	unit_id = unit.unit_id
	name = "MemberItem_%s" % unit.unit_id
	text = ""
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(0.0, 84.0 if unit.is_wounded() else 66.0)
	tooltip_text = "点击查看士兵详情"
	_build(unit, config)
	set_selected(false)


func set_selected(value: bool) -> void:
	_selected = value
	button_pressed = value
	modulate = Color(0.72, 0.95, 0.72) if value else Color.WHITE


func is_selected() -> bool:
	return _selected


func _build(unit: UnitData, config: UnitConfig) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_set_full_rect(margin)
	add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(header)

	_name_label = _make_label(
		unit.display_name if not unit.display_name.is_empty() else "未命名士兵", 16
	)
	_name_label.name = "MemberName"
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_name_label)

	var level_label := _make_label("Lv.%d" % unit.level, 14)
	level_label.name = "MemberLevel"
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(level_label)

	_class_label = _make_label("", 13)
	_class_label.name = "MemberClass"
	column.add_child(_class_label)
	if config != null:
		var class_text: String = config.get_class_display_name()
		if unit.is_mounted:
			class_text = "骑乘" + class_text
		_class_label.text = "%s · %s" % [config.display_name, class_text]
	else:
		var unknown_text: String = "骑乘" if unit.is_mounted else ""
		_class_label.text = "未知兵种（%s）%s" % [unit.config_id, unknown_text]

	_stats_label = _make_label("", 13)
	_stats_label.name = "MemberStats"
	column.add_child(_stats_label)
	_stats_label.text = "HP %d/%d    攻击 %d" % [
		unit.current_hp, unit.max_hp, unit.attack
	]

	# 伤兵是显式状态，必须在成员列表中可识别；永久死亡不会出现在这里。
	_status_label = _make_label("", 13)
	_status_label.name = "MemberStatus"
	_status_label.visible = false
	column.add_child(_status_label)
	if unit.is_wounded():
		_status_label.visible = true
		_status_label.text = "伤兵（无法战斗，按小时恢复）"
		_status_label.add_theme_color_override("font_color", Color("#e8a06a"))


func _make_label(label_text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = label_text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
