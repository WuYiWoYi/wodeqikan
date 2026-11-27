extends Control
## 新游戏文化/身份选择全屏界面。
##
## 由主菜单通过 SceneManager 切换进入，主菜单场景已被释放，因此本界面是
## 独立全屏场景而不是附着弹窗。流程：文化选择 → 身份选择 → 最终路线预览。
## 只有预览页的确认会调用 GameManager.start_new_game()；此前不创建存档、不建世界。
##
## 交互约定：
## - 每一级默认选中第一个选项，不存在空选择。
## - 悬浮右侧选项只预览左侧描述，不改变已选项、不切换层级。
## - 点击选项只选定，必须点击确认按钮才进入下一层。
## - 底部路线预览随选择实时更新。

enum Page {
	CULTURE,
	IDENTITY,
	PREVIEW,
}

const GOLD: Color = Color("#E0B66A")
const TEXT_PRIMARY: Color = Color("#e8eef4")
const TEXT_MUTED: Color = Color("#9fb0c2")
const TEXT_DISABLED: Color = Color("#5f6b78")
const CONTENT_MIN_WIDTH: float = 720.0
const CONTENT_MAX_WIDTH: float = 1180.0
const SELECTION_MIN_WIDTH: float = 280.0
const SELECTION_MAX_WIDTH: float = 380.0
const OPTION_HEIGHT: float = 56.0
const OPTION_SEPARATION: int = 10
const PLACEHOLDER_HINT: String = "待设定"
const ROUTE_PENDING_TEXT: String = "身份：待选择"


class DetailView:
	var title: Label = null
	var type_label: Label = null
	var description: Label = null
	var bonus_title: Label = null
	var bonus_list: VBoxContainer = null


class SelectionView:
	var panel: PanelContainer = null
	var title: Label = null
	var scroll: ScrollContainer = null
	var list: VBoxContainer = null
	var hint: Label = null


var _catalog: IdentityCatalog = null

var _content_margin: MarginContainer = null
var _header_title: Label = null
var _header_subtitle: Label = null

var _culture_page: HBoxContainer = null
var _identity_page: HBoxContainer = null
var _preview_page: PanelContainer = null
var _preview_route_label: Label = null

var _culture_detail: DetailView = null
var _identity_detail: DetailView = null
var _culture_selection: SelectionView = null
var _identity_selection: SelectionView = null

var _route_panel: PanelContainer = null
var _route_label: Label = null
var _back_button: Button = null
var _confirm_button: Button = null

var _current_page: Page = Page.CULTURE
var _selected_culture_id: String = ""
var _selected_identity_id: String = ""
var _hovered_culture_id: String = ""
var _hovered_identity_id: String = ""
var _culture_button_group: ButtonGroup = null
var _identity_button_group: ButtonGroup = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.create()
	_build_background()
	_build_layout()
	_catalog = IdentityCatalog.load_default()
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()
	_enter_culture_page()


## 当前流程页面，供调试或测试查询。
func get_current_page() -> Page:
	return _current_page


func get_selected_culture_id() -> String:
	return _selected_culture_id


func get_selected_identity_id() -> String:
	return _selected_identity_id


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

	var root := VBoxContainer.new()
	root.name = "ContentColumn"
	root.add_theme_constant_override("separation", 12)
	_content_margin.add_child(root)

	var header := VBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 2)
	root.add_child(header)

	_header_title = _make_semibold_label("", 30, GOLD)
	_header_title.name = "HeaderTitle"
	header.add_child(_header_title)

	_header_subtitle = _make_label("", 15)
	_header_subtitle.name = "HeaderSubtitle"
	_header_subtitle.add_theme_color_override("font_color", TEXT_MUTED)
	_header_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(_header_subtitle)

	_culture_page = _build_choice_page("Culture", root)
	_identity_page = _build_choice_page("Identity", root)
	_culture_page.visible = false
	_identity_page.visible = false
	_build_preview_page(root)
	_build_route_panel(root)
	_build_footer(root)


func _build_choice_page(prefix: String, parent: VBoxContainer) -> HBoxContainer:
	var page := HBoxContainer.new()
	page.name = prefix + "Page"
	page.add_theme_constant_override("separation", 16)
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(page)

	var detail := _build_detail_view(prefix, page)
	var selection := _build_selection_view(prefix, page)
	if prefix == "Culture":
		_culture_detail = detail
		_culture_selection = selection
	else:
		_identity_detail = detail
		_identity_selection = selection
	return page


func _build_detail_view(prefix: String, parent: HBoxContainer) -> DetailView:
	var view := DetailView.new()

	var panel := PanelContainer.new()
	panel.name = prefix + "DetailPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.6
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	parent.add_child(panel)

	var column := VBoxContainer.new()
	column.name = "DetailColumn"
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	view.title = _make_semibold_label("", 25, GOLD)
	view.title.name = prefix + "DetailTitle"
	view.title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(view.title)

	view.type_label = _make_label("", 14)
	view.type_label.name = prefix + "DetailType"
	view.type_label.add_theme_color_override("font_color", TEXT_MUTED)
	column.add_child(view.type_label)

	# 长背景文本在独立区域内滚动；加成面板固定在滚动区下方，始终可见。
	var scroll := ScrollContainer.new()
	scroll.name = prefix + "DetailScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	view.description = _make_label("", 16)
	view.description.name = prefix + "DescriptionLabel"
	view.description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	view.description.add_theme_color_override("font_color", TEXT_PRIMARY)
	view.description.add_theme_constant_override("line_spacing", 8)
	view.description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(view.description)

	# 加成使用独立面板，与背景描述区分层级。
	var bonus_panel := PanelContainer.new()
	bonus_panel.name = prefix + "BonusPanel"
	bonus_panel.add_theme_stylebox_override("panel", _make_bonus_style())
	column.add_child(bonus_panel)

	var bonus_box := VBoxContainer.new()
	bonus_box.name = "BonusBox"
	bonus_box.add_theme_constant_override("separation", 6)
	bonus_panel.add_child(bonus_box)

	view.bonus_title = _make_semibold_label("", 17, GOLD)
	view.bonus_title.name = prefix + "BonusTitle"
	bonus_box.add_child(view.bonus_title)

	view.bonus_list = VBoxContainer.new()
	view.bonus_list.name = prefix + "BonusList"
	view.bonus_list.add_theme_constant_override("separation", 4)
	bonus_box.add_child(view.bonus_list)

	return view


func _build_selection_view(prefix: String, parent: HBoxContainer) -> SelectionView:
	var view := SelectionView.new()

	view.panel = PanelContainer.new()
	view.panel.name = prefix + "SelectionPanel"
	view.panel.custom_minimum_size = Vector2(SELECTION_MIN_WIDTH, 0.0)
	view.panel.size_flags_horizontal = Control.SIZE_FILL
	view.panel.size_flags_stretch_ratio = 0.85
	view.panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.panel.add_theme_stylebox_override("panel", _make_panel_style())
	parent.add_child(view.panel)

	var column := VBoxContainer.new()
	column.name = "SelectionColumn"
	column.add_theme_constant_override("separation", 10)
	view.panel.add_child(column)

	view.title = _make_semibold_label("", 18, GOLD)
	view.title.name = prefix + "SelectionTitle"
	column.add_child(view.title)

	view.scroll = ScrollContainer.new()
	view.scroll.name = prefix + "OptionScroll"
	view.scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	view.scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	view.scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(view.scroll)

	view.list = VBoxContainer.new()
	view.list.name = prefix + "OptionList"
	view.list.add_theme_constant_override("separation", OPTION_SEPARATION)
	view.list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.scroll.add_child(view.list)

	view.hint = _make_label("点击选项选定，确认后进入下一层。", 13)
	view.hint.name = prefix + "SelectionHint"
	view.hint.add_theme_color_override("font_color", TEXT_MUTED)
	view.hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(view.hint)

	return view


func _build_preview_page(parent: VBoxContainer) -> void:
	_preview_page = PanelContainer.new()
	_preview_page.name = "PreviewPage"
	_preview_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_page.add_theme_stylebox_override("panel", _make_panel_style())
	_preview_page.visible = false
	parent.add_child(_preview_page)

	var center := VBoxContainer.new()
	center.name = "PreviewCenter"
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 18)
	_preview_page.add_child(center)

	var caption := _make_label("你的最终身份路线", 15)
	caption.name = "PreviewCaption"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_color_override("font_color", TEXT_MUTED)
	center.add_child(caption)

	# 路线按行左对齐，再用 CenterContainer 居中整块，保留树形缩进。
	var route_center := CenterContainer.new()
	route_center.name = "PreviewRouteCenter"
	route_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_child(route_center)

	_preview_route_label = _make_semibold_label("", 28, GOLD)
	_preview_route_label.name = "PreviewRouteLabel"
	_preview_route_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_preview_route_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_preview_route_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_preview_route_label.add_theme_constant_override("line_spacing", 10)
	route_center.add_child(_preview_route_label)

	var hint := _make_label("确认后，你将以这个身份踏入世界。", 15)
	hint.name = "PreviewHint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", TEXT_MUTED)
	center.add_child(hint)


func _build_route_panel(parent: VBoxContainer) -> void:
	_route_panel = PanelContainer.new()
	_route_panel.name = "RoutePanel"
	_route_panel.custom_minimum_size = Vector2(0.0, 92.0)
	_route_panel.add_theme_stylebox_override("panel", _make_panel_style())
	parent.add_child(_route_panel)

	var column := VBoxContainer.new()
	column.name = "RouteColumn"
	column.add_theme_constant_override("separation", 4)
	_route_panel.add_child(column)

	var caption := _make_label("最终身份路线", 13)
	caption.name = "RouteCaption"
	caption.add_theme_color_override("font_color", TEXT_MUTED)
	column.add_child(caption)

	_route_label = _make_label("", 16)
	_route_label.name = "RouteLabel"
	_route_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	_route_label.add_theme_constant_override("line_spacing", 4)
	column.add_child(_route_label)


func _build_footer(parent: VBoxContainer) -> void:
	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", 16)
	parent.add_child(footer)

	_back_button = _make_button("返回主菜单", "BackButton", 46.0)
	_back_button.custom_minimum_size.x = 160.0
	_style_secondary_button(_back_button)
	_back_button.pressed.connect(_on_back_pressed)
	footer.add_child(_back_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	_confirm_button = _make_button("确认文化", "ConfirmButton", 46.0)
	_confirm_button.custom_minimum_size.x = 180.0
	_style_primary_button(_confirm_button)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	footer.add_child(_confirm_button)


func _apply_responsive_layout() -> void:
	if _content_margin == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var target_width: float = clampf(
		viewport_size.x * 0.9, CONTENT_MIN_WIDTH, CONTENT_MAX_WIDTH
	)
	var side_margin: int = maxi(24, int((viewport_size.x - target_width) * 0.5))
	var vertical_margin: int = 28
	if viewport_size.y < 760.0:
		vertical_margin = 20
	_content_margin.add_theme_constant_override("margin_left", side_margin)
	_content_margin.add_theme_constant_override("margin_right", side_margin)
	_content_margin.add_theme_constant_override("margin_top", vertical_margin)
	_content_margin.add_theme_constant_override("margin_bottom", vertical_margin)

	var selection_width: float = clampf(
		viewport_size.x * 0.24, SELECTION_MIN_WIDTH, SELECTION_MAX_WIDTH
	)
	if _culture_selection != null:
		_culture_selection.panel.custom_minimum_size.x = selection_width
	if _identity_selection != null:
		_identity_selection.panel.custom_minimum_size.x = selection_width


func _enter_culture_page() -> void:
	_hovered_culture_id = ""
	_hovered_identity_id = ""

	var cultures: Array = []
	if _catalog != null:
		cultures = _catalog.get_enabled_cultures()

	if cultures.is_empty():
		_selected_culture_id = ""
		_rebuild_culture_buttons()
		_refresh_culture_detail("")
		_show_page(Page.CULTURE)
		_refresh_route()
		return

	if not _culture_exists(cultures, _selected_culture_id):
		var first_culture: Variant = cultures[0]
		_selected_culture_id = str(first_culture.culture_id)

	# 文化切换后，旧文化下的身份不再适用。
	var identity := _catalog.get_identity(_selected_identity_id)
	if identity != null and identity.culture_id != _selected_culture_id:
		_selected_identity_id = ""

	_rebuild_culture_buttons()
	_refresh_culture_detail(_selected_culture_id)
	_show_page(Page.CULTURE)
	_refresh_route()


func _enter_identity_page() -> void:
	_hovered_culture_id = ""
	_hovered_identity_id = ""

	if _catalog == null:
		_enter_culture_page()
		return
	var culture: Variant = _catalog.get_culture(_selected_culture_id)
	if culture == null or not culture.enabled:
		_enter_culture_page()
		return

	var identities: Array = _catalog.get_enabled_identities_for_culture(
		_selected_culture_id
	)
	if identities.is_empty():
		_enter_culture_page()
		return

	if not _identity_exists(identities, _selected_identity_id):
		_selected_identity_id = identities[0].identity_id

	_rebuild_identity_buttons()
	_refresh_identity_detail(_selected_identity_id)
	_show_page(Page.IDENTITY)
	_refresh_route()


func _enter_preview_page() -> void:
	if not _has_valid_selection():
		return
	_hovered_culture_id = ""
	_hovered_identity_id = ""
	_show_page(Page.PREVIEW)
	_refresh_route()


func _show_page(page: Page) -> void:
	_current_page = page
	_culture_page.visible = page == Page.CULTURE
	_identity_page.visible = page == Page.IDENTITY
	_preview_page.visible = page == Page.PREVIEW
	_route_panel.visible = page != Page.PREVIEW
	_update_header()
	_update_footer()


func _update_header() -> void:
	match _current_page:
		Page.CULTURE:
			_header_title.text = "选择你的文化"
			_header_subtitle.text = "你的文化决定了你的出身、传统与看待世界的方式。"
		Page.IDENTITY:
			var culture: Variant = null
			if _catalog != null:
				culture = _catalog.get_culture(_selected_culture_id)
			var culture_name: String = culture.display_name if culture != null else ""
			_header_title.text = "选择你的身份"
			_header_subtitle.text = "在%s的土地上，你将如何开始？" % culture_name
		Page.PREVIEW:
			_header_title.text = "确认你的出身"
			_header_subtitle.text = "这是你即将踏上的道路。"


func _update_footer() -> void:
	match _current_page:
		Page.CULTURE:
			_back_button.text = "返回主菜单"
			_confirm_button.text = "确认文化"
			_confirm_button.disabled = _selected_culture_id.is_empty()
		Page.IDENTITY:
			_back_button.text = "退回"
			_confirm_button.text = "确认身份"
			_confirm_button.disabled = _selected_identity_id.is_empty()
		Page.PREVIEW:
			_back_button.text = "退回"
			_confirm_button.text = "开始游戏"
			_confirm_button.disabled = not _has_valid_selection()


func _rebuild_culture_buttons() -> void:
	_clear_children(_culture_selection.list)
	_culture_button_group = ButtonGroup.new()
	if _catalog == null:
		_culture_selection.title.text = "文化"
		_culture_selection.hint.text = "文化配置加载失败，请查看日志。"
		return

	var cultures: Array = _catalog.get_enabled_cultures()
	_culture_selection.title.text = "可用文化"
	_culture_selection.hint.text = "点击选项选定，确认后进入身份选择。"
	for value: Variant in cultures:
		var culture: Variant = value
		if culture == null:
			continue
		var button := _make_option_button(
			culture.display_name,
			"CultureOption_%s" % culture.culture_id,
			_culture_button_group
		)
		button.pressed.connect(_on_culture_option_pressed.bind(culture.culture_id))
		button.mouse_entered.connect(_on_culture_option_hovered.bind(culture.culture_id))
		button.mouse_exited.connect(_on_culture_option_unhovered.bind(culture.culture_id))
		_culture_selection.list.add_child(button)
		if culture.culture_id == _selected_culture_id:
			button.set_pressed_no_signal(true)


func _rebuild_identity_buttons() -> void:
	_clear_children(_identity_selection.list)
	_identity_button_group = ButtonGroup.new()
	if _catalog == null:
		_identity_selection.title.text = "身份"
		_identity_selection.hint.text = "身份配置加载失败，请查看日志。"
		return

	var identities: Array = _catalog.get_enabled_identities_for_culture(
		_selected_culture_id
	)
	_identity_selection.title.text = "可选身份"
	_identity_selection.hint.text = "点击选项选定，确认后查看最终路线。"
	for identity in identities:
		var button := _make_option_button(
			identity.display_name,
			"IdentityOption_%s" % identity.identity_id,
			_identity_button_group
		)
		button.pressed.connect(_on_identity_option_pressed.bind(identity.identity_id))
		button.mouse_entered.connect(
			_on_identity_option_hovered.bind(identity.identity_id)
		)
		button.mouse_exited.connect(
			_on_identity_option_unhovered.bind(identity.identity_id)
		)
		_identity_selection.list.add_child(button)
		if identity.identity_id == _selected_identity_id:
			button.set_pressed_no_signal(true)


func _refresh_culture_detail(culture_id: String) -> void:
	var culture: Variant = null
	if _catalog != null:
		culture = _catalog.get_culture(culture_id)
	if culture == null:
		_culture_detail.title.text = "尚未选择文化"
		_culture_detail.type_label.text = "文化"
		_culture_detail.description.text = "文化配置不可用，请查看日志。"
		_culture_detail.bonus_title.text = "文化天赋"
		_fill_bonus_list(_culture_detail.bonus_list, PackedStringArray([PLACEHOLDER_HINT]))
		return
	_culture_detail.title.text = culture.display_name
	_culture_detail.type_label.text = "文化"
	_culture_detail.description.text = culture.description
	_culture_detail.bonus_title.text = "文化天赋"
	_fill_bonus_list(_culture_detail.bonus_list, culture.talent_lines)


func _refresh_identity_detail(identity_id: String) -> void:
	var identity: IdentityDefinition = null
	if _catalog != null:
		identity = _catalog.get_identity(identity_id)
	if identity == null:
		_identity_detail.title.text = "尚未选择身份"
		_identity_detail.type_label.text = "身份类型：待选择"
		_identity_detail.description.text = "从右侧选择一个身份，查看他的来历。"
		_identity_detail.bonus_title.text = "身份加成"
		_fill_bonus_list(_identity_detail.bonus_list, PackedStringArray([PLACEHOLDER_HINT]))
		return

	var category := _catalog.get_category(identity.category_id)
	var type_name: String = category.display_name if category != null else "身份"
	_identity_detail.title.text = identity.display_name
	_identity_detail.type_label.text = "身份类型：%s" % type_name
	_identity_detail.description.text = identity.description
	_identity_detail.bonus_title.text = "身份加成"
	_fill_bonus_list(_identity_detail.bonus_list, identity.bonus_lines)


func _fill_bonus_list(list: VBoxContainer, lines: PackedStringArray) -> void:
	_clear_children(list)
	if lines.is_empty():
		_add_bonus_line(list, PLACEHOLDER_HINT, true)
		return
	for line: String in lines:
		_add_bonus_line(list, line, line.contains(PLACEHOLDER_HINT))


func _add_bonus_line(list: VBoxContainer, text: String, is_placeholder: bool) -> void:
	var label := _make_label("· %s" % text, 15)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override(
		"font_color", TEXT_MUTED if is_placeholder else TEXT_PRIMARY
	)
	list.add_child(label)


func _refresh_route() -> void:
	var route_text: String = _build_route_text()
	_route_label.text = route_text
	_preview_route_label.text = route_text


func _build_route_text() -> String:
	var culture: Variant = null
	if _catalog != null:
		culture = _catalog.get_culture(_selected_culture_id)
	if culture == null:
		return "尚未选择文化"

	var lines: Array[String] = [culture.display_name]
	var identity := _catalog.get_identity(_selected_identity_id)
	if identity != null and identity.enabled \
			and identity.culture_id == culture.culture_id:
		var category := _catalog.get_category(identity.category_id)
		var type_name: String = category.display_name if category != null else "身份"
		lines.append("  └── %s" % type_name)
		lines.append("       └── %s" % identity.display_name)
	else:
		lines.append("  └── %s" % ROUTE_PENDING_TEXT)
	return "\n".join(lines)


func _on_culture_option_pressed(culture_id: String) -> void:
	if _catalog == null:
		return
	var culture: Variant = _catalog.get_culture(culture_id)
	if culture == null or not culture.enabled:
		return
	if culture_id != _selected_culture_id:
		_selected_culture_id = culture_id
		var identity := _catalog.get_identity(_selected_identity_id)
		if identity != null and identity.culture_id != culture_id:
			_selected_identity_id = ""
	_hovered_culture_id = ""
	_sync_option_pressed(_culture_selection.list, "CultureOption_%s" % culture_id)
	_refresh_culture_detail(culture_id)
	_refresh_route()
	_update_footer()


func _on_identity_option_pressed(identity_id: String) -> void:
	if _catalog == null:
		return
	var identity := _catalog.get_identity(identity_id)
	if identity == null or not identity.enabled \
			or identity.culture_id != _selected_culture_id:
		return
	_selected_identity_id = identity_id
	_hovered_identity_id = ""
	_sync_option_pressed(_identity_selection.list, "IdentityOption_%s" % identity_id)
	_refresh_identity_detail(identity_id)
	_refresh_route()
	_update_footer()


func _on_culture_option_hovered(culture_id: String) -> void:
	if _current_page != Page.CULTURE:
		return
	_hovered_culture_id = culture_id
	_refresh_culture_detail(culture_id)


func _on_culture_option_unhovered(culture_id: String) -> void:
	if _hovered_culture_id != culture_id:
		return
	_hovered_culture_id = ""
	_refresh_culture_detail(_selected_culture_id)


func _on_identity_option_hovered(identity_id: String) -> void:
	if _current_page != Page.IDENTITY:
		return
	_hovered_identity_id = identity_id
	_refresh_identity_detail(identity_id)


func _on_identity_option_unhovered(identity_id: String) -> void:
	if _hovered_identity_id != identity_id:
		return
	_hovered_identity_id = ""
	_refresh_identity_detail(_selected_identity_id)


func _on_back_pressed() -> void:
	match _current_page:
		Page.CULTURE:
			var error: Error = SceneManager.change_scene(SceneManager.MAIN_MENU_SCENE)
			if error != OK:
				_header_subtitle.text = "无法返回主菜单，请查看日志。"
		Page.IDENTITY:
			_enter_culture_page()
		Page.PREVIEW:
			_enter_identity_page()


func _on_confirm_pressed() -> void:
	match _current_page:
		Page.CULTURE:
			_enter_identity_page()
		Page.IDENTITY:
			_enter_preview_page()
		Page.PREVIEW:
			_final_confirm()


func _final_confirm() -> void:
	if not _has_valid_selection():
		return
	var identity := _catalog.get_identity(_selected_identity_id)
	if identity == null:
		return
	if not GameManager.start_new_game(
		identity.identity_id, identity.category_id, identity.culture_id
	):
		_header_subtitle.text = "新游戏创建失败，请查看日志。"


func _has_valid_selection() -> bool:
	if _catalog == null:
		return false
	var culture: Variant = _catalog.get_culture(_selected_culture_id)
	var identity := _catalog.get_identity(_selected_identity_id)
	return culture != null and culture.enabled \
		and identity != null and identity.enabled \
		and identity.culture_id == culture.culture_id


func _culture_exists(cultures: Array, culture_id: String) -> bool:
	for value: Variant in cultures:
		var culture: Variant = value
		if culture != null and str(culture.culture_id) == culture_id:
			return true
	return false


func _identity_exists(identities: Array, identity_id: String) -> bool:
	for value: Variant in identities:
		var identity: Variant = value
		if identity != null and str(identity.identity_id) == identity_id:
			return true
	return false


func _sync_option_pressed(list: VBoxContainer, selected_node_name: String) -> void:
	for child: Node in list.get_children():
		var button := child as Button
		if button != null:
			button.set_pressed_no_signal(button.name == selected_node_name)


func _make_option_button(
		text: String, node_name: String, group: ButtonGroup
	) -> Button:
	var button := _make_button(text, node_name, OPTION_HEIGHT)
	button.toggle_mode = true
	button.button_group = group
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_option_button(button)
	return button


func _clear_children(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


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


func _make_bonus_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.13, 0.18, 0.92)
	style.border_color = Color(0.72, 0.56, 0.28, 0.55)
	style.border_width_left = 3
	style.set_corner_radius_all(4)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
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
	button.add_theme_font_size_override("font_size", 19)


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
