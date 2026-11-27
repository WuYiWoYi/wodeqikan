class_name MapUiKit
extends RefCounted
## 大地图 UI 构件：无状态的控件创建与布局辅助。
## 只统一外观，不持有世界数据，也不管理暂停或场景生命周期。


static func set_full_rect(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0


static func make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label


static func make_button(text: String, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(64.0, 30.0)
	button.focus_mode = Control.FOCUS_NONE
	return button


static func settlement_type_text(type: SettlementData.SettlementType) -> String:
	match type:
		SettlementData.SettlementType.CASTLE:
			return "城堡"
		SettlementData.SettlementType.TOWN:
			return "城镇"
		_:
			return "村庄"
