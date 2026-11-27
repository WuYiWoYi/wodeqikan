class_name WorldMapEncyclopedia
extends Control
## 大地图百科覆盖层：一级分类（王国/家族/地点）→ 条目列表 → 二级详情。
## 只读取 WorldContext 的政治与地点权威数据；不复制、不修改任何实体。
## 面板显隐由本组件负责，暂停原因由大地图覆盖层登记簿持有。

signal closed

const MapUiKitScript = preload("res://Scripts/UI/WorldMap/map_ui_kit.gd")
const TextureRegion = preload("res://Scripts/Core/World/texture_region_utils.gd")

var _context: WorldContext = null
var _dim: ColorRect = null
var _panel: PanelContainer = null
var _title: Label = null
var _subtitle: Label = null
var _list: VBoxContainer = null
var _back_button: Button = null
var _view: String = "home"
var _kingdom_id: String = ""
var _house_id: String = ""
var _settlement_id: String = ""
var _history: Array[Dictionary] = []
var _signature: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	MapUiKitScript.set_full_rect(self)
	_build()


func setup(context: WorldContext) -> void:
	_context = context


func get_panel() -> Control:
	return _panel


func is_open() -> bool:
	return _panel != null and _panel.visible


func open() -> void:
	if _panel == null or _context == null:
		return
	_view = "home"
	_kingdom_id = ""
	_house_id = ""
	_settlement_id = ""
	_history.clear()
	_signature = ""
	_panel.visible = true
	_dim.visible = true
	_refresh(true)


func close() -> void:
	if not is_open():
		return
	_panel.visible = false
	_dim.visible = false
	closed.emit()


## 打开期间每帧调用；数据未变化时签名相同，不重建列表。
func refresh_if_needed() -> void:
	if is_open():
		_refresh(false)


func _build() -> void:
	_dim = ColorRect.new()
	_dim.name = "EncyclopediaDim"
	_dim.color = Color(0.0, 0.0, 0.0, 0.55)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	MapUiKitScript.set_full_rect(_dim)
	add_child(_dim)

	_panel = PanelContainer.new()
	_panel.name = "EncyclopediaPanel"
	_panel.visible = false
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -420.0
	_panel.offset_top = -320.0
	_panel.offset_right = 420.0
	_panel.offset_bottom = 320.0
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)

	_title = MapUiKitScript.make_label("百科", 24)
	_title.name = "EncyclopediaTitle"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)

	var close_button := MapUiKitScript.make_button("关闭", "EncyclopediaCloseButton")
	close_button.pressed.connect(close)
	header.add_child(close_button)

	_subtitle = MapUiKitScript.make_label("", 14)
	_subtitle.name = "EncyclopediaSubtitle"
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_subtitle)

	_back_button = MapUiKitScript.make_button("返回", "EncyclopediaBackButton")
	_back_button.visible = false
	_back_button.pressed.connect(_on_back_pressed)
	column.add_child(_back_button)

	var scroll := ScrollContainer.new()
	scroll.name = "EncyclopediaScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_list = VBoxContainer.new()
	_list.name = "EncyclopediaList"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)


func _on_back_pressed() -> void:
	if _history.is_empty():
		_view = "home"
		_kingdom_id = ""
		_house_id = ""
		_settlement_id = ""
	else:
		var previous: Dictionary = _history.pop_back()
		_view = str(previous.get("view", "home"))
		_kingdom_id = str(previous.get("kingdom_id", ""))
		_house_id = str(previous.get("house_id", ""))
		_settlement_id = str(previous.get("settlement_id", ""))
	_refresh(true)


func _navigate(
	view: String,
	kingdom_id: String = "",
	house_id: String = "",
	settlement_id: String = ""
) -> void:
	_history.append({
		"view": _view,
		"kingdom_id": _kingdom_id,
		"house_id": _house_id,
		"settlement_id": _settlement_id,
	})
	_view = view
	_kingdom_id = kingdom_id
	_house_id = house_id
	_settlement_id = settlement_id
	_refresh(true)


func _on_category_pressed(view: String) -> void:
	_navigate(view)


func _on_kingdom_pressed(kingdom_id: String) -> void:
	_navigate("kingdom", kingdom_id, "")


func _on_house_pressed(house_id: String) -> void:
	_navigate("house", "", house_id)


func _on_settlement_pressed(settlement_id: String) -> void:
	_navigate("settlement", "", "", settlement_id)


func _refresh(force: bool) -> void:
	if _context == null or _panel == null:
		return
	if not _panel.visible and not force:
		return
	var signature := _build_signature()
	if not force and signature == _signature:
		return
	_signature = signature
	_back_button.visible = not _history.is_empty()
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	match _view:
		"kingdom":
			_build_kingdom(_kingdom_id)
		"house":
			_build_house(_house_id)
		"settlement":
			_build_settlement(_settlement_id)
		"kingdoms":
			_build_kingdom_list()
		"houses":
			_build_house_list()
		"locations":
			_build_location_list()
		_:
			_build_home()


func _build_signature() -> String:
	var parts: Array[String] = [
		_view, _kingdom_id, _house_id, _settlement_id,
	]
	for kingdom: KingdomData in _context.kingdom_manager.get_all_kingdoms():
		parts.append("kingdom:%s;%s;%s;%s;%s" % [
			kingdom.kingdom_id, kingdom.kingdom_name,
			kingdom.ruling_house_id, kingdom.king_noble_id,
			",".join(PackedStringArray(kingdom.enemy_kingdom_ids)),
		])
	for house: HouseData in _context.house_manager.get_all_houses():
		parts.append("house:%s;%s;%s;%s;%s" % [
			house.house_id, house.house_name,
			house.leader_noble_id, house.kingdom_id, house.banner_id,
		])
		for noble: NobleData in _context.house_manager.get_house_nobles(
			house.house_id, true
		):
			parts.append("noble:%s;%s;%s;%s;%s" % [
				noble.lord_id, noble.display_name, str(noble.alive),
				str(noble.rank), noble.party_id,
			])
		for settlement: SettlementData in _context.house_manager.get_house_settlements(
			house.house_id
		):
			parts.append("house_settlement:%s;%s" % [
				settlement.settlement_id, settlement.owner_noble_id
			])
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		parts.append("settlement:%s;%s;%d;%s;%s;%s;%d;%d;%d;%d" % [
			settlement.settlement_id, settlement.display_name,
			int(settlement.settlement_type), settlement.owner_noble_id,
			settlement.owner_house_id, settlement.family_id,
			settlement.population, settlement.prosperity,
			settlement.tax_income_per_day, settlement.fief_recruitment_stock,
		])
	return "|".join(PackedStringArray(parts))


# ---------------------------------------------------------------------------
# 百科一级分类
# ---------------------------------------------------------------------------


func _build_home() -> void:
	_title.text = "百科"
	_subtitle.text = "一级：选择王国、家族或地点分类，再查看对应条目。"
	_add_label("一级分类", 18)
	_add_category_button(
		"王国（%d）" % _context.kingdom_manager.get_all_kingdoms().size(),
		"EncyclopediaCategory_Kingdoms",
		"kingdoms"
	)
	_add_category_button(
		"家族（%d）" % _context.house_manager.get_all_houses().size(),
		"EncyclopediaCategory_Houses",
		"houses"
	)
	_add_category_button(
		"地点（%d）" % _context.settlement_manager.get_all_settlements().size(),
		"EncyclopediaCategory_Locations",
		"locations"
	)


func _add_category_button(
	text: String, node_name: String, view: String
) -> void:
	var button := MapUiKitScript.make_button(text, node_name)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0.0, 48.0)
	button.add_theme_font_size_override("font_size", 17)
	button.pressed.connect(_on_category_pressed.bind(view))
	_list.add_child(button)


func _build_kingdom_list() -> void:
	_title.text = "百科 · 王国"
	_subtitle.text = "一级分类：王国条目。点击王国查看详情。"
	var kingdoms := _context.kingdom_manager.get_all_kingdoms()
	if kingdoms.is_empty():
		_add_label("世界上尚未建立王国。", 14)
	for kingdom: KingdomData in kingdoms:
		var ruling := _context.kingdom_manager.get_ruling_house(kingdom.kingdom_id)
		var king := _context.kingdom_manager.get_king(kingdom.kingdom_id)
		var relation_text := _kingdom_relation(kingdom)
		var war_text := _war_text(kingdom)
		var fief_count: int = _context.kingdom_manager.get_kingdom_settlements(
			kingdom.kingdom_id
		).size()
		var text: String = "%s\n统治家族：%s · 国王：%s\n附庸家族：%d · 封地：%d · 对玩家：%s · %s" % [
			kingdom.kingdom_name,
			ruling.house_name if ruling != null else "无",
			king.display_name if king != null else "无",
			kingdom.vassal_house_ids.size(),
			fief_count,
			relation_text,
			war_text,
		]
		var button := MapUiKitScript.make_button(
			text, "EncyclopediaKingdom_%s" % kingdom.kingdom_id
		)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_kingdom_pressed.bind(kingdom.kingdom_id))
		_list.add_child(button)


func _build_house_list() -> void:
	_title.text = "百科 · 家族"
	_subtitle.text = "一级分类：家族条目。点击家族查看详情。"
	var houses: Array[HouseData] = _context.house_manager.get_all_houses()
	houses.sort_custom(func(a: HouseData, b: HouseData) -> bool:
		if a.house_name == b.house_name:
			return a.house_id < b.house_id
		return a.house_name < b.house_name
	)
	if houses.is_empty():
		_add_label("世界上尚未建立家族。", 14)
	for house: HouseData in houses:
		var kingdom := _context.kingdom_manager.get_kingdom_for_house(house.house_id)
		var suffix: String = (
			"所属王国：%s" % kingdom.kingdom_name if kingdom != null else "独立家族"
		)
		_add_house_row(
			house, "%s · 对玩家：%s" % [suffix, _house_relation(house.house_id)]
		)


func _build_location_list() -> void:
	_title.text = "百科 · 地点"
	_subtitle.text = "一级分类：地点条目。点击地点查看详情。"
	var settlements: Array[SettlementData] = (
		_context.settlement_manager.get_all_settlements()
	)
	settlements.sort_custom(func(a: SettlementData, b: SettlementData) -> bool:
		if a.display_name == b.display_name:
			return a.settlement_id < b.settlement_id
		return a.display_name < b.display_name
	)
	if settlements.is_empty():
		_add_label("世界上尚未建立地点。", 14)
	for settlement: SettlementData in settlements:
		var button := MapUiKitScript.make_button(
			"%s（%s）· %s" % [
				settlement.display_name,
				MapUiKitScript.settlement_type_text(settlement.settlement_type),
				_settlement_owner_text(settlement),
			],
			"EncyclopediaSettlement_%s" % settlement.settlement_id
		)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(
			_on_settlement_pressed.bind(settlement.settlement_id)
		)
		_list.add_child(button)


# ---------------------------------------------------------------------------
# 百科二级详情
# ---------------------------------------------------------------------------


func _build_kingdom(kingdom_id: String) -> void:
	var kingdom := _context.kingdom_manager.get_kingdom(kingdom_id)
	if kingdom == null:
		_title.text = "百科 · 王国"
		_subtitle.text = "王国数据已失效。"
		return
	_title.text = "百科 · %s" % kingdom.kingdom_name
	_subtitle.text = "二级：王国详情。统治家族、附庸、封地与敌对势力。%s" \
		% _war_text(kingdom)
	var ruling := _context.kingdom_manager.get_ruling_house(kingdom_id)
	var king := _context.kingdom_manager.get_king(kingdom_id)
	if ruling != null:
		_add_label("统治家族", 18)
		_add_house_row(ruling, "国王：%s" % (king.display_name if king != null else "无"))
		var others: Array[NobleData] = []
		for noble: NobleData in _context.house_manager.get_house_nobles(
			ruling.house_id, true
		):
			if king == null or noble.lord_id != king.lord_id:
				others.append(noble)
		if not others.is_empty():
			_add_label("其他贵族", 15)
			for noble: NobleData in others:
				_add_label("· " + _noble_text(noble), 13)

	var vassals := _context.kingdom_manager.get_vassal_houses(kingdom_id)
	_add_label("附庸家族（%d）" % vassals.size(), 18)
	if vassals.is_empty():
		_add_label("无附庸家族。", 13)
	for house: HouseData in vassals:
		_add_house_row(
			house, "对玩家：%s" % _house_relation(house.house_id)
		)

	_add_label("封地（按家族分组）", 18)
	for house: HouseData in _context.kingdom_manager.get_all_houses_of_kingdom(kingdom_id):
		var settlements := _context.house_manager.get_house_settlements(house.house_id)
		_add_label("%s · %d 处" % [house.house_name, settlements.size()], 15)
		if settlements.is_empty():
			_add_label("  （暂无封地）", 13)
		for settlement: SettlementData in settlements:
			_add_label("  · " + _settlement_text(settlement), 13)

	_add_hostility_section(kingdom_id, "")


func _build_house(house_id: String) -> void:
	var house := _context.house_manager.get_house(house_id)
	if house == null:
		_title.text = "百科 · 家族"
		_subtitle.text = "家族数据已失效。"
		return
	var kingdom := _context.kingdom_manager.get_kingdom_for_house(house.house_id)
	_title.text = "百科 · %s" % house.house_name
	_subtitle.text = "二级：家族详情。%s" % (
		"所属王国：%s" % kingdom.kingdom_name if kingdom != null else "独立家族"
	)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	header.add_child(make_house_badge(house))
	var leader := _context.house_manager.get_house_leader(house.house_id)
	header.add_child(MapUiKitScript.make_label(
		"领袖：%s（%s）" % [
			leader.display_name if leader != null else "无",
			leader.get_rank_text() if leader != null else "—",
		],
		15
	))
	_list.add_child(header)

	var nobles := _context.house_manager.get_house_nobles(house.house_id, true)
	_add_label("贵族（%d）" % nobles.size(), 18)
	for noble: NobleData in nobles:
		_add_label("· " + _noble_text(noble), 13)

	var settlements := _context.house_manager.get_house_settlements(house.house_id)
	_add_label("封地（%d）" % settlements.size(), 18)
	if settlements.is_empty():
		_add_label("暂无封地。", 13)
	for settlement: SettlementData in settlements:
		_add_label("· " + _settlement_text(settlement), 13)

	_add_hostility_section("", house_id)


func _build_settlement(settlement_id: String) -> void:
	var settlement := _context.settlement_manager.get_settlement(settlement_id)
	if settlement == null:
		_title.text = "百科 · 地点"
		_subtitle.text = "地点数据已失效。"
		return
	_title.text = "百科 · %s" % settlement.display_name
	_subtitle.text = "二级：地点详情。%s" \
		% MapUiKitScript.settlement_type_text(settlement.settlement_type)
	_add_label("类型：%s" % MapUiKitScript.settlement_type_text(
		settlement.settlement_type
	), 15)
	_add_label("所有者：%s" % _settlement_owner_text(
		settlement
	), 15)

	var owner_house := _context.house_manager.get_house(settlement.owner_house_id) \
		if not settlement.owner_house_id.is_empty() else null
	if owner_house != null:
		_add_label("所属家族", 18)
		_add_house_row(owner_house, "地点所有者")
		var kingdom := _context.kingdom_manager.get_kingdom_for_house(
			owner_house.house_id
		)
		if kingdom != null:
			_add_label("所属王国", 18)
			var kingdom_button := MapUiKitScript.make_button(
				kingdom.kingdom_name,
				"EncyclopediaKingdom_%s" % kingdom.kingdom_id
			)
			kingdom_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			kingdom_button.pressed.connect(
				_on_kingdom_pressed.bind(kingdom.kingdom_id)
			)
			_list.add_child(kingdom_button)

	_add_label("地点数据", 18)
	_add_label("人口：%d" % settlement.population, 14)
	_add_label("繁荣度：%d" % settlement.prosperity, 14)
	_add_label("预计每日税收：%d" % settlement.tax_income_per_day, 14)
	if settlement.settlement_type == SettlementData.SettlementType.VILLAGE:
		_add_label("采邑储备：%d / %d 组" % [
			settlement.fief_recruitment_stock,
			settlement.fief_recruitment_capacity,
		], 14)
	else:
		_add_label("采邑储备：不适用", 14)


## 王国或家族详情的统一敌对势力区块。kingdom_id 与 house_id 二选一。
func _add_hostility_section(kingdom_id: String, house_id: String) -> void:
	if _context.faction_manager == null:
		return
	_add_label("敌对势力", 18)
	var enemy_kingdoms: Array[KingdomData] = []
	var enemy_houses: Array[HouseData] = []
	if not kingdom_id.is_empty():
		enemy_kingdoms = _context.kingdom_manager.get_enemy_kingdoms(kingdom_id)
		enemy_houses = _context.faction_manager.get_hostile_independent_houses_for_kingdom(
			kingdom_id
		)
	else:
		enemy_kingdoms = _context.faction_manager.get_hostile_kingdoms_for_house(house_id)
		enemy_houses = _context.faction_manager.get_hostile_independent_houses_for_house(
			house_id
		)

	_add_label("敌对王国（%d）" % enemy_kingdoms.size(), 15)
	if enemy_kingdoms.is_empty():
		_add_label("没有敌对王国。", 13)
	for enemy: KingdomData in enemy_kingdoms:
		var button := MapUiKitScript.make_button(
			enemy.kingdom_name, "EncyclopediaEnemyKingdom_%s" % enemy.kingdom_id
		)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(
			_on_kingdom_pressed.bind(enemy.kingdom_id)
		)
		_list.add_child(button)

	_add_label("敌对独立家族（%d）" % enemy_houses.size(), 15)
	if enemy_houses.is_empty():
		_add_label("没有敌对独立家族。", 13)
	for house: HouseData in enemy_houses:
		_add_house_row(house, "敌对独立家族")


func _add_label(text: String, font_size: int) -> Label:
	var label := MapUiKitScript.make_label(text, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_child(label)
	return label


func _add_house_row(house: HouseData, suffix: String) -> void:
	if house == null:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(make_house_badge(house))
	var button := MapUiKitScript.make_button(
		"%s%s" % [house.house_name, "" if suffix.is_empty() else " · " + suffix],
		"EncyclopediaHouse_%s" % house.house_id
	)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_on_house_pressed.bind(house.house_id))
	row.add_child(button)
	_list.add_child(row)


## 有家族旗帜时显示真实徽章；没有配置时使用统一占位徽章。
## 公开给大地图门面，供既有测试按家族数据直接验证。
func make_house_badge(house: HouseData) -> Control:
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(34.0, 34.0)
	var family := _context.family_registry.get_config(house.banner_id) \
		if _context != null and _context.family_registry != null \
		and house != null else null
	if family != null and not family.banner_texture_path.is_empty() \
			and ResourceLoader.exists(family.banner_texture_path):
		var texture_rect := TextureRect.new()
		texture_rect.texture = TextureRegion.get_trimmed_texture(
			load(family.banner_texture_path) as Texture2D
		)
		texture_rect.custom_minimum_size = Vector2(30.0, 30.0)
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		holder.add_child(texture_rect)
	else:
		var placeholder := PanelContainer.new()
		placeholder.name = "HouseBadgePlaceholder"
		placeholder.custom_minimum_size = Vector2(30.0, 30.0)
		var label := MapUiKitScript.make_label("徽", 14)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		placeholder.add_child(label)
		holder.add_child(placeholder)
	return holder


func _noble_text(noble: NobleData) -> String:
	var markers: Array[String] = []
	if noble.is_king:
		markers.append("国王")
	if noble.is_house_leader:
		markers.append("家族领袖")
	if not noble.alive:
		markers.append("已故")
	var marker_text: String = "" if markers.is_empty() \
		else "（%s）" % "、".join(PackedStringArray(markers))
	var party := _context.party_manager.get_party(noble.party_id) \
		if _context.party_manager != null else null
	var party_text: String = party.party_name if party != null else "无部队"
	return "%s%s · %s · %s" % [
		noble.display_name, marker_text, noble.get_rank_text(), party_text
	]


func _settlement_text(settlement: SettlementData) -> String:
	return "%s（%s）· 所有者：%s" % [
		settlement.display_name,
		MapUiKitScript.settlement_type_text(settlement.settlement_type),
		_settlement_owner_text(settlement),
	]


## 地点所有者显示名：优先个人贵族，其次家族，最后视觉家族配置。
func _settlement_owner_text(settlement: SettlementData) -> String:
	if settlement == null:
		return "无主"
	if not settlement.owner_noble_id.is_empty() \
			and _context.noble_manager != null:
		var owner := _context.noble_manager.get_noble(settlement.owner_noble_id)
		if owner != null:
			return owner.display_name
	if not settlement.owner_house_id.is_empty() \
			and _context.house_manager != null:
		var house := _context.house_manager.get_house(settlement.owner_house_id)
		if house != null:
			return house.house_name
	if not settlement.family_id.is_empty() \
			and _context.family_registry != null:
		var family := _context.family_registry.get_config(settlement.family_id)
		if family != null:
			return family.display_name
	return "无主"


func _house_relation(house_id: String) -> String:
	if _context == null or _context.player_house_id.is_empty():
		return "中立"
	return _context.faction_manager.relation_text(
		_context.faction_manager.get_house_relation(_context.player_house_id, house_id)
	)


func _kingdom_relation(kingdom: KingdomData) -> String:
	if kingdom == null or kingdom.ruling_house_id.is_empty():
		return "中立"
	return _house_relation(kingdom.ruling_house_id)


func _war_text(kingdom: KingdomData) -> String:
	if kingdom == null:
		return "和平"
	var enemies := _context.kingdom_manager.get_enemy_kingdoms(kingdom.kingdom_id)
	if enemies.is_empty():
		return "和平"
	var names: Array[String] = []
	for enemy: KingdomData in enemies:
		names.append(enemy.kingdom_name)
	return "交战中：%s" % "、".join(PackedStringArray(names))
