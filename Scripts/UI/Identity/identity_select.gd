extends Control
## 新游戏身份选择全屏界面。
##
## 由主菜单通过 SceneManager 切换进入，主菜单场景已被释放，因此本界面是
## 独立全屏场景而不是附着弹窗。流程：一级类别 → 二级身份 → 最终确认。
## 只有最终确认会调用 GameManager.start_new_game()；此前不创建存档、不建世界。

enum Page {
	CATEGORY,
	IDENTITY,
	CONFIRM,
}

const GOLD: Color = Color("#E0B66A")
const TEXT_PRIMARY: Color = Color("#e8eef4")
const TEXT_MUTED: Color = Color("#9fb0c2")
const TEXT_DISABLED: Color = Color("#5f6b78")
const CONTENT_MIN_WIDTH: float = 340.0
const CONTENT_MAX_WIDTH: float = 640.0
const BUTTON_HEIGHT: float = 54.0
const OPTION_SEPARATION: int = 10
## 二级选项超过该行数后只滚动选项区域，避免把整页布局顶出屏幕。
const MAX_VISIBLE_OPTIONS: int = 3
const STORY_PLACEHOLDER: String = "从下方选择一个身份，查看他的来历。"
const NO_SELECTION_TEXT: String = "当前选择：未选择"

var _catalog: IdentityCatalog = null

var _content_margin: MarginContainer = null
var _category_page: VBoxContainer = null
var _identity_page: VBoxContainer = null
var _confirm_page: VBoxContainer = null

var _category_buttons: VBoxContainer = null
var _category_button_group: ButtonGroup = null
var _category_status_label: Label = null

var _identity_page_title: Label = null
var _story_panel: PanelContainer = null
var _story_title_label: Label = null
var _story_label: Label = null
var _selection_label: Label = null
var _identity_options_scroll: ScrollContainer = null
var _identity_buttons: VBoxContainer = null
var _identity_button_group: ButtonGroup = null

var _confirm_path_label: Label = null
var _confirm_status_label: Label = null

var _current_page: Page = Page.CATEGORY
var _selected_category_id: String = ""
var _selected_identity_id: String = ""
var _max_visible_options: int = MAX_VISIBLE_OPTIONS


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.create()
	_build_background()
	_build_layout()
	_catalog = IdentityCatalog.load_default()
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()
	_show_category_page()


## 当前流程页面，供调试或后续扩展查询。
func get_current_page() -> Page:
	return _current_page


func _build_background() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color("#1e2835"))
	gradient.set_color(1, Color("#080b0f"))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)

	var background := TextureRect.new()
	background.name = "Background"
	background.texture = texture
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_full_rect(background)
	add_child(background)

	# 中央暖光：让独立界面有中世纪厅堂的氛围，而不是主菜单的同色底。
	var glow_gradient := Gradient.new()
	glow_gradient.set_color(0, Color(0.72, 0.56, 0.28, 0.16))
	glow_gradient.set_color(1, Color(0.72, 0.56, 0.28, 0.0))
	var glow_texture := GradientTexture2D.new()
	glow_texture.gradient = glow_gradient
	glow_texture.fill = GradientTexture2D.FILL_RADIAL
	glow_texture.fill_from = Vector2(0.5, 0.42)
	glow_texture.fill_to = Vector2(1.0, 1.0)
	var glow := TextureRect.new()
	glow.name = "CenterGlow"
	glow.texture = glow_texture
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_full_rect(glow)
	add_child(glow)

	var top_line := ColorRect.new()
	top_line.name = "TopGoldLine"
	top_line.color = Color(0.88, 0.71, 0.42, 0.32)
	top_line.anchor_right = 1.0
	top_line.offset_bottom = 2.0
	top_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_line)

	var bottom_line := ColorRect.new()
	bottom_line.name = "BottomGoldLine"
	bottom_line.color = Color(0.88, 0.71, 0.42, 0.18)
	bottom_line.anchor_top = 1.0
	bottom_line.anchor_right = 1.0
	bottom_line.anchor_bottom = 1.0
	bottom_line.offset_top = -2.0
	bottom_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_line)


func _build_layout() -> void:
	_content_margin = MarginContainer.new()
	_content_margin.name = "ContentMargin"
	_set_full_rect(_content_margin)
	add_child(_content_margin)

	var content := VBoxContainer.new()
	content.name = "ContentColumn"
	content.add_theme_constant_override("separation", 0)
	_content_margin.add_child(content)

	_build_category_page(content)
	_build_identity_page(content)
	_build_confirm_page(content)


func _build_category_page(parent: VBoxContainer) -> void:
	_category_page = VBoxContainer.new()
	_category_page.name = "CategoryPage"
	_category_page.add_theme_constant_override("separation", 16)
	_category_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(_category_page)

	var top_spacer := Control.new()
	top_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_category_page.add_child(top_spacer)

	var title := _make_semibold_label("你的身份是？", 38, GOLD)
	title.name = "CategoryTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_category_page.add_child(title)

	var description := _make_label(
		"你将以怎样的身份踏入这个纷乱的世界？你的出身或许决定了你的起点，但未必决定你的终点。",
		18
	)
	description.name = "CategoryDescription"
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size = Vector2(0.0, 78.0)
	description.add_theme_color_override("font_color", TEXT_PRIMARY)
	description.add_theme_constant_override("line_spacing", 6)
	_category_page.add_child(description)

	_category_buttons = VBoxContainer.new()
	_category_buttons.name = "CategoryButtonList"
	_category_buttons.add_theme_constant_override("separation", 14)
	_category_page.add_child(_category_buttons)

	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_category_page.add_child(bottom_spacer)

	_category_status_label = _make_label("", 15)
	_category_status_label.name = "CategoryStatusLabel"
	_category_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_category_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_category_status_label.add_theme_color_override("font_color", GOLD)
	_category_page.add_child(_category_status_label)

	var back_button := _make_button("返回主菜单", "IdentityCancelButton", 46.0)
	_style_secondary_button(back_button)
	back_button.pressed.connect(_on_cancel_pressed)
	_category_page.add_child(back_button)


func _build_identity_page(parent: VBoxContainer) -> void:
	_identity_page = VBoxContainer.new()
	_identity_page.name = "IdentityPage"
	_identity_page.add_theme_constant_override("separation", 12)
	_identity_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_identity_page.visible = false
	parent.add_child(_identity_page)

	# 上下弹性留白让身份内容整体居中；故事区按内容/最小高度收缩。
	var top_spacer := Control.new()
	top_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_identity_page.add_child(top_spacer)

	_identity_page_title = _make_semibold_label("", 30, GOLD)
	_identity_page_title.name = "IdentityPageTitle"
	_identity_page_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_identity_page.add_child(_identity_page_title)

	_story_panel = PanelContainer.new()
	_story_panel.name = "StoryPanel"
	_story_panel.custom_minimum_size = Vector2(0.0, 170.0)
	_story_panel.size_flags_vertical = Control.SIZE_FILL
	_story_panel.add_theme_stylebox_override("panel", _make_panel_style())
	_identity_page.add_child(_story_panel)

	var story_box := VBoxContainer.new()
	story_box.name = "StoryBox"
	story_box.add_theme_constant_override("separation", 10)
	_story_panel.add_child(story_box)

	_story_title_label = _make_semibold_label("", 21, GOLD)
	_story_title_label.name = "StoryTitle"
	_story_title_label.visible = false
	story_box.add_child(_story_title_label)

	_story_label = _make_label(STORY_PLACEHOLDER, 17)
	_story_label.name = "StoryLabel"
	_story_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_story_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_story_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_story_label.add_theme_color_override("font_color", TEXT_MUTED)
	_story_label.add_theme_constant_override("line_spacing", 8)
	story_box.add_child(_story_label)

	_selection_label = _make_label(NO_SELECTION_TEXT, 15)
	_selection_label.name = "SelectionLabel"
	_selection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_selection_label.add_theme_color_override("font_color", TEXT_MUTED)
	_identity_page.add_child(_selection_label)

	# 仅选项区域滚动；身份数量增加时页面其余部分保持稳定。
	_identity_options_scroll = ScrollContainer.new()
	_identity_options_scroll.name = "IdentityOptionScroll"
	_identity_options_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_identity_options_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_identity_options_scroll.size_flags_vertical = Control.SIZE_FILL
	_identity_page.add_child(_identity_options_scroll)

	_identity_buttons = VBoxContainer.new()
	_identity_buttons.name = "IdentityOptionList"
	_identity_buttons.add_theme_constant_override("separation", OPTION_SEPARATION)
	_identity_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_identity_options_scroll.add_child(_identity_buttons)

	# 二级没有“完成选择”等中间按钮：点击具体身份立即进入最终确认。
	var back_button := _make_button("返回", "IdentityBackButton", 46.0)
	_style_secondary_button(back_button)
	back_button.pressed.connect(_on_identity_back_pressed)
	_identity_page.add_child(back_button)

	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_identity_page.add_child(bottom_spacer)


func _build_confirm_page(parent: VBoxContainer) -> void:
	_confirm_page = VBoxContainer.new()
	_confirm_page.name = "ConfirmPage"
	_confirm_page.add_theme_constant_override("separation", 16)
	_confirm_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_confirm_page.visible = false
	parent.add_child(_confirm_page)

	var top_spacer := Control.new()
	top_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_confirm_page.add_child(top_spacer)

	var title := _make_semibold_label("确认你的身份", 36, GOLD)
	title.name = "ConfirmTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_page.add_child(title)

	var hint := _make_label("请确认你的选择", 18)
	hint.name = "ConfirmHint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", TEXT_MUTED)
	_confirm_page.add_child(hint)

	var path_panel := PanelContainer.new()
	path_panel.name = "ConfirmPathPanel"
	path_panel.custom_minimum_size = Vector2(0.0, 150.0)
	path_panel.add_theme_stylebox_override("panel", _make_panel_style())
	_confirm_page.add_child(path_panel)

	_confirm_path_label = _make_semibold_label("", 26, GOLD)
	_confirm_path_label.name = "ConfirmPathLabel"
	_confirm_path_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_path_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_confirm_path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_path_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	path_panel.add_child(_confirm_path_label)

	_confirm_status_label = _make_label("", 15)
	_confirm_status_label.name = "ConfirmStatusLabel"
	_confirm_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_status_label.add_theme_color_override("font_color", GOLD)
	_confirm_page.add_child(_confirm_status_label)

	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_confirm_page.add_child(bottom_spacer)

	# 最终确认页按钮纵向排列，避免与身份选项混淆。
	var return_button := _make_button("返回修改", "ReturnModifyButton", 48.0)
	_style_secondary_button(return_button)
	return_button.pressed.connect(_on_return_modify_pressed)
	_confirm_page.add_child(return_button)

	var final_button := _make_button("最终确认", "FinalConfirmButton", 54.0)
	_style_primary_button(final_button)
	final_button.pressed.connect(_on_final_confirm_pressed)
	_confirm_page.add_child(final_button)


func _apply_responsive_layout() -> void:
	if _content_margin == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	# 矮窗口放宽内容列，减少故事文本换行，避免底部按钮被挤出屏幕。
	var width_ratio: float = 0.34 if viewport_size.y >= 800.0 else 0.42
	var target_width: float = clampf(
		viewport_size.x * width_ratio, CONTENT_MIN_WIDTH, CONTENT_MAX_WIDTH
	)
	var side_margin: int = maxi(24, int((viewport_size.x - target_width) * 0.5))
	var vertical_margin: int = 48
	if viewport_size.y < 760.0:
		vertical_margin = 28
	elif viewport_size.y < 800.0:
		vertical_margin = 32
	_content_margin.add_theme_constant_override("margin_left", side_margin)
	_content_margin.add_theme_constant_override("margin_right", side_margin)
	_content_margin.add_theme_constant_override("margin_top", vertical_margin)
	_content_margin.add_theme_constant_override("margin_bottom", vertical_margin)

	# 矮窗口下压缩故事区并减少可见身份行数，保证底部按钮不被裁切。
	if _story_panel != null:
		_story_panel.custom_minimum_size.y = clampf(
			viewport_size.y * 0.20, 110.0, 220.0
		)
	var rows: int = 2 if viewport_size.y < 760.0 else MAX_VISIBLE_OPTIONS
	if rows != _max_visible_options:
		_max_visible_options = rows
		_update_identity_options_height()


func _show_category_page() -> void:
	_current_page = Page.CATEGORY
	_category_page.visible = true
	_identity_page.visible = false
	_confirm_page.visible = false
	_refresh_category_buttons()


func _refresh_category_buttons() -> void:
	for child: Node in _category_buttons.get_children():
		_category_buttons.remove_child(child)
		child.queue_free()
	_category_button_group = ButtonGroup.new()
	_category_status_label.text = ""

	if _catalog == null:
		_category_status_label.text = "身份配置加载失败，请查看日志。"
		return
	if not _catalog.has_selectable_identities():
		_category_status_label.text = "没有可用的身份配置，请查看日志。"
		return

	for category: IdentityCategoryDefinition in _catalog.get_enabled_categories():
		var button := _make_button(
			category.display_name,
			"CategoryButton_%s" % category.category_id,
			58.0
		)
		button.toggle_mode = true
		button.button_group = _category_button_group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_option_button(button)
		button.pressed.connect(_on_category_pressed.bind(category.category_id))
		_category_buttons.add_child(button)
		if category.category_id == _selected_category_id:
			button.set_pressed_no_signal(true)


func _show_identity_page() -> void:
	if _catalog == null:
		_show_category_page()
		return
	var category := _catalog.get_category(_selected_category_id)
	if category == null or not category.enabled:
		_selected_category_id = ""
		_show_category_page()
		return

	var identity := _catalog.get_identity(_selected_identity_id)
	if identity == null or not identity.enabled \
			or identity.category_id != _selected_category_id:
		_selected_identity_id = ""

	_current_page = Page.IDENTITY
	_identity_page_title.text = "%s身份选择" % category.display_name
	_rebuild_identity_buttons()
	if _selected_identity_id.is_empty():
		_reset_identity_detail()
	else:
		_apply_identity_selection(identity)

	_category_page.visible = false
	_identity_page.visible = true
	_confirm_page.visible = false


func _rebuild_identity_buttons() -> void:
	for child: Node in _identity_buttons.get_children():
		_identity_buttons.remove_child(child)
		child.queue_free()
	_identity_button_group = ButtonGroup.new()

	var identities: Array[IdentityDefinition] = (
		_catalog.get_enabled_identities(_selected_category_id)
		if _catalog != null else []
	)
	for identity: IdentityDefinition in identities:
		var button := _make_button(
			identity.display_name,
			"IdentityButton_%s" % identity.identity_id,
			52.0
		)
		button.toggle_mode = true
		button.button_group = _identity_button_group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_option_button(button)
		button.toggled.connect(_on_identity_toggled.bind(identity))
		_identity_buttons.add_child(button)
		if identity.identity_id == _selected_identity_id:
			button.set_pressed_no_signal(true)

	_update_identity_options_height()


func _update_identity_options_height() -> void:
	var count: int = _identity_buttons.get_child_count()
	var visible_rows: int = clampi(count, 1, _max_visible_options)
	_identity_options_scroll.custom_minimum_size.y = (
		visible_rows * BUTTON_HEIGHT
			+ maxi(0, visible_rows - 1) * OPTION_SEPARATION
	)
	_identity_options_scroll.visible = count > 0


func _on_category_pressed(category_id: String) -> void:
	var category := _catalog.get_category(category_id) if _catalog != null else null
	if category == null or not category.enabled:
		return
	# 切换类别时清除旧类别下已不适用/可能不适用的具体身份；
	# 再次进入同一类别则保留此前选择。
	if category_id != _selected_category_id:
		_selected_identity_id = ""
	_selected_category_id = category_id
	_show_identity_page()


func _on_identity_toggled(toggled_on: bool, identity: IdentityDefinition) -> void:
	if not toggled_on:
		return
	# 点击具体身份即完成本阶段选择，不再有额外的确认按钮。
	_apply_identity_selection(identity)
	_show_confirm_page()


func _apply_identity_selection(identity: IdentityDefinition) -> void:
	_selected_identity_id = identity.identity_id
	_story_title_label.text = identity.display_name
	_story_title_label.visible = true
	_story_label.text = identity.description
	_story_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	_selection_label.text = "当前选择：%s" % identity.display_name
	_selection_label.add_theme_color_override("font_color", GOLD)
	_update_identity_button_colors(identity.identity_id)


func _reset_identity_detail() -> void:
	_story_title_label.text = ""
	_story_title_label.visible = false
	_story_label.text = STORY_PLACEHOLDER
	_story_label.add_theme_color_override("font_color", TEXT_MUTED)
	_selection_label.text = NO_SELECTION_TEXT
	_selection_label.add_theme_color_override("font_color", TEXT_MUTED)
	_update_identity_button_colors("")


func _update_identity_button_colors(selected_identity_id: String) -> void:
	var selected_name := "IdentityButton_%s" % selected_identity_id
	for child: Node in _identity_buttons.get_children():
		var button := child as Button
		if button == null:
			continue
		var is_selected: bool = button.name == selected_name
		button.add_theme_color_override(
			"font_color", GOLD if is_selected else TEXT_PRIMARY
		)
		button.add_theme_color_override(
			"font_hover_color", GOLD if is_selected else Color("#ffffff")
		)


func _show_confirm_page() -> void:
	if not _has_valid_selection():
		return
	_current_page = Page.CONFIRM
	_confirm_path_label.text = " → ".join(
		PackedStringArray(_build_selection_path_parts())
	)
	_confirm_status_label.text = ""
	_category_page.visible = false
	_identity_page.visible = false
	_confirm_page.visible = true


## 当前完整选择路径（显示名称）。未来增加“特殊出身”等层级时，
## 在这里按顺序追加即可，确认页只消费完整路径。
func _build_selection_path_parts() -> Array[String]:
	var parts: Array[String] = []
	if _catalog == null:
		return parts
	var category := _catalog.get_category(_selected_category_id)
	if category != null:
		parts.append(category.display_name)
	var identity := _catalog.get_identity(_selected_identity_id)
	if identity != null:
		parts.append(identity.display_name)
	return parts


func _has_valid_selection() -> bool:
	if _catalog == null:
		return false
	var category := _catalog.get_category(_selected_category_id)
	var identity := _catalog.get_identity(_selected_identity_id)
	return category != null and category.enabled \
		and identity != null and identity.enabled \
		and identity.category_id == category.category_id


func _on_identity_back_pressed() -> void:
	_show_category_page()


func _on_return_modify_pressed() -> void:
	# 返回一级类别页；已选类别与身份保留，重新进入同一类别时可继续修改。
	_show_category_page()


func _on_final_confirm_pressed() -> void:
	if not _has_valid_selection():
		return
	if not GameManager.start_new_game(_selected_identity_id, _selected_category_id):
		_confirm_status_label.text = "新游戏创建失败，请查看日志。"


func _on_cancel_pressed() -> void:
	var error: Error = SceneManager.change_scene(SceneManager.MAIN_MENU_SCENE)
	if error != OK:
		_category_status_label.text = "无法返回主菜单，请查看日志。"


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.10, 0.14, 0.88)
	style.border_color = Color(0.30, 0.38, 0.47, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	return style


func _style_option_button(button: Button) -> void:
	button.add_theme_stylebox_override(
		"normal", _make_button_style(Color("#151c25"), Color("#39485a"), 1)
	)
	button.add_theme_stylebox_override(
		"hover", _make_button_style(Color("#1e2935"), GOLD, 1)
	)
	button.add_theme_stylebox_override(
		"pressed", _make_button_style(Color("#302714"), GOLD, 2)
	)
	button.add_theme_stylebox_override(
		"disabled", _make_button_style(Color("#10151b"), Color("#252e37"), 1)
	)
	button.add_theme_color_override("font_color", TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", Color("#ffffff"))
	button.add_theme_color_override("font_pressed_color", GOLD)
	button.add_theme_color_override("font_hover_pressed_color", GOLD)
	button.add_theme_color_override("font_disabled_color", TEXT_DISABLED)
	button.add_theme_font_size_override("font_size", 20)


func _style_primary_button(button: Button) -> void:
	_style_option_button(button)
	button.add_theme_stylebox_override(
		"normal", _make_button_style(Color("#241d12"), GOLD, 1)
	)
	button.add_theme_stylebox_override(
		"hover", _make_button_style(Color("#332917"), GOLD, 2)
	)
	button.add_theme_stylebox_override(
		"pressed", _make_button_style(Color("#3c3018"), GOLD, 2)
	)
	button.add_theme_color_override("font_color", GOLD)
	button.add_theme_color_override("font_hover_color", Color("#f4d79a"))
	button.add_theme_color_override("font_pressed_color", Color("#f4d79a"))


func _style_secondary_button(button: Button) -> void:
	_style_option_button(button)
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_stylebox_override(
		"normal", _make_button_style(Color(0.08, 0.11, 0.15, 0.7), Color("#3b4654"), 1)
	)
	button.add_theme_stylebox_override(
		"hover", _make_button_style(Color("#1a232d"), Color("#8a97a6"), 1)
	)
	button.add_theme_color_override("font_color", TEXT_MUTED)
	button.add_theme_color_override("font_hover_color", TEXT_PRIMARY)


func _make_button_style(bg: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(4)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


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


func _make_semibold_label(text: String, font_size: int, color: Color) -> Label:
	var label := _make_label(text, font_size)
	label.add_theme_color_override("font_color", color)
	# 系统字体无独立粗体字重，用 FontVariation 加粗到半粗体。
	var semibold := FontVariation.new()
	semibold.base_font = UiTheme.create().default_font
	semibold.variation_embolden = 0.6
	label.add_theme_font_override("font", semibold)
	return label


func _make_button(text: String, node_name: String, min_height: float) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(0.0, min_height)
	button.focus_mode = Control.FOCUS_NONE
	return button
