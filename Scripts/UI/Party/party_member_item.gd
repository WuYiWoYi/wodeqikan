class_name PartyMemberItem
extends Button
## 部队面板中的单条士兵/俘虏列表项。
##
## 只读取 UnitData / UnitConfig 的现成字段，不计算属性。
## 左侧复用 UnitVisual 生成头像缩略图；右侧只保留姓名、战斗经验与生命值。
## 条目采用双列网格布局，宽度由部队面板统一分配。

const PartyUnitThumbnailScript = preload(
	"res://Scripts/UI/Party/party_unit_thumbnail.gd"
)
const ITEM_HEIGHT: float = 68.0

var unit_id: String = ""
var is_prisoner: bool = false

var _name_label: Label = null
var _combat_exp_label: Label = null
var _hp_label: Label = null
var _thumbnail: Control = null
var _selected: bool = false


func setup(
	unit: UnitData,
	config: UnitConfig,
	equipment_configs: Dictionary = {},
	prisoner: bool = false
) -> void:
	unit_id = unit.unit_id
	is_prisoner = prisoner
	name = "MemberItem_%s" % unit.unit_id
	text = ""
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, ITEM_HEIGHT)
	tooltip_text = "点击查看俘虏详情" if prisoner else "点击查看士兵详情"
	_build(unit, config, equipment_configs)
	set_selected(false)


func set_selected(value: bool) -> void:
	_selected = value
	button_pressed = value
	modulate = Color(0.72, 0.95, 0.72) if value else Color.WHITE


func is_selected() -> bool:
	return _selected


func get_thumbnail() -> Control:
	return _thumbnail


func _build(
	unit: UnitData, _config: UnitConfig, equipment_configs: Dictionary
) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_set_full_rect(margin)
	add_child(margin)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	# 头像缩略图：固定尺寸与裁切规则，右侧文本不会被挤压。
	_thumbnail = PartyUnitThumbnailScript.new()
	_thumbnail.name = "MemberThumbnail"
	_thumbnail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_thumbnail.setup(unit, equipment_configs)
	row.add_child(_thumbnail)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 2)
	row.add_child(column)

	# 条目只保留姓名、战斗经验与当前生命值；兵种、攻击等细节在中间详情区查看。
	_name_label = _make_label(
		unit.display_name if not unit.display_name.is_empty() else "未命名士兵", 15
	)
	_name_label.name = "MemberName"
	column.add_child(_name_label)

	_combat_exp_label = _make_label(
		"战斗经验：%s" % CombatExperience.tier_name_for_level(unit.level), 13
	)
	_combat_exp_label.name = "MemberCombatExperience"
	_combat_exp_label.modulate = Color(0.82, 0.84, 0.9)
	column.add_child(_combat_exp_label)

	_hp_label = _make_label(
		"生命：%d / %d" % [unit.current_hp, unit.max_hp], 13
	)
	_hp_label.name = "MemberHp"
	column.add_child(_hp_label)
	# 伤兵仍保留在成员列表中，通过生命值 0 与颜色提示；不额外占用文字空间。
	if unit.is_wounded():
		_hp_label.add_theme_color_override("font_color", Color("#e8a06a"))
	elif is_prisoner:
		_hp_label.add_theme_color_override("font_color", Color("#8fb8e8"))


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
