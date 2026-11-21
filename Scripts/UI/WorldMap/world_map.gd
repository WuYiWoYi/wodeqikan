extends Node2D
## 大地图场景控制器。
##
## 只读取 WorldContext 的权威数据并生成表现节点；
## 移动、时间、存档操作全部通过管理器/GameManager 接口完成。

const PARTY_INTERACTION_RADIUS: float = 40.0
const PARTY_INTERACTION_EXIT_RADIUS: float = 64.0
## 点击部队图标的判定半径（世界像素）。
const PARTY_CLICK_RADIUS: float = 26.0
## 点击地点的判定半径（世界像素）；地点面板只由主动点击打开。
const SETTLEMENT_CLICK_RADIUS: float = 45.0
## 鼠标悬浮部队图标的判定半径；略大于点击半径便于触发。
const PARTY_HOVER_RADIUS: float = 30.0
const HOVER_PANEL_WIDTH: float = 320.0
const HOVER_PANEL_LINE_HEIGHT: float = 22.0
const BATTLE_SUMMARY_WIDTH: float = 360.0
const BATTLE_SUMMARY_SEPARATOR: String = "────────────"
const WORLD_LOG_WIDTH: float = 460.0
const WORLD_LOG_HEIGHT: float = 220.0
const CAMERA_FOLLOW_SPEED: float = 8.0
const CAMERA_PAN_SPEED: float = 650.0
const CAMERA_ZOOM_MIN: float = 0.5
const CAMERA_ZOOM_MAX: float = 2.0
## 1920×1080 下保持与旧 1152×648 接近的大地图视野/图标比例。
const CAMERA_DEFAULT_ZOOM: float = 1.5
## 圆形部队标记样式集中配置。
const PARTY_MARKER_STYLE_PATH: String = "res://Data/WorldMap/party_marker_style.tres"
## 遭遇对话文本配置；缺失时使用脚本默认文本，不把对白写死在 UI 中。
const ENCOUNTER_TEXT_CONFIG_PATH: String = "res://Data/Encounters/encounter_text_config.tres"
## 底部 NPC 对话面板尺寸与边距（1920×1080 设计分辨率）。
const NPC_DIALOGUE_PANEL_WIDTH: float = 960.0
const NPC_DIALOGUE_PANEL_HEIGHT: float = 290.0
const NPC_DIALOGUE_BOTTOM_MARGIN: float = 48.0
const NPC_DIALOGUE_PORTRAIT_SIZE := Vector2(180.0, 220.0)
## 固定屏幕地点名称与圆形标记顶部之间的屏幕间距（像素）。
const SETTLEMENT_NAME_GAP_ABOVE_MARKER: float = 10.0

@onready var map_background: MapBackground = $MapBackground
@onready var world_entities: Node2D = $WorldEntities
@onready var camera: Camera2D = $Camera2D

var _context: WorldContext = null
var _player_party: PartyData = null
var _player_icon: PartyIcon = null
var _camera_offset := Vector2.ZERO
var _last_player_position := Vector2.ZERO
var _settlement_latch_id: String = ""

var _ui_root: Control = null
var _world_time_label: Label = null
var _player_info_label: Label = null
var _pause_button: Button = null
var _speed_one_button: Button = null
var _speed_two_button: Button = null
var _time_buttons: Array[Button] = []

var _settlement_panel: PanelContainer = null
var _settlement_name_label: Label = null
var _settlement_type_label: Label = null
var _settlement_enter_button: Button = null
var _settlement_pause_active: bool = false
var _settlement_entry_pending: bool = false

var _party_panel: PanelContainer = null
var _party_name_label: Label = null
var _party_faction_label: Label = null
var _party_troop_label: Label = null
var _party_status_label: Label = null
var _party_fight_button: Button = null
var _party_pause_active: bool = false
var _party_latch_id: String = ""
var _battle_transition_started: bool = false

var _party_manage_panel: PartyPanel = null
var _party_manage_pause_active: bool = false

var _encounter_panel: PanelContainer = null
var _encounter_portrait: EncounterPortrait = null
var _encounter_name_label: Label = null
var _encounter_faction_label: Label = null
var _encounter_troop_label: Label = null
var _encounter_description_label: Label = null
var _encounter_status_label: Label = null
var _encounter_fight_button: Button = null
var _encounter_leave_button: Button = null
var _encounter_pause_active: bool = false
var _encounter_id: String = ""
## 本次遭遇是否允许离开；ENEMY_PURSUIT 时为 false。
var _encounter_leave_allowed: bool = true
var _encounter_text_config: EncounterTextConfig = null

## 普通部队对话（玩家主动接近）同样使用底部 NPC 对话布局。
var _party_portrait: EncounterPortrait = null
var _party_dialogue_label: Label = null

var _battle_interaction_panel: PanelContainer = null
var _battle_interaction_summary_label: Label = null
var _battle_interaction_status_label: Label = null
var _battle_join_button: Button = null
var _battle_leave_button: Button = null
var _battle_interaction_pause_active: bool = false
var _battle_interaction_id: String = ""
var _battle_interaction_battle_id: String = ""

var _hover_panel: PanelContainer = null
var _hover_content: VBoxContainer = null
var _hover_party_id: String = ""
var _hover_signature: String = ""

## 同一场战斗只显示一个标记；参战部队图标暂时隐藏。
var _party_icons: Dictionary = {}
## 部队圆形标记样式；缺失资源时使用脚本默认值。
var _party_marker_style: PartyMarkerStyle = null
## 固定屏幕层的地点名称标签：{ settlement_id: SettlementNameTag }。
var _settlement_name_layer: Control = null
var _settlement_name_tags: Dictionary = {}
var _battle_marker: BattleMarker = null
var _battle_marker_id: String = ""
var _battle_summary_panel: PanelContainer = null
var _battle_summary_title: Label = null
var _battle_summary_content: VBoxContainer = null
var _battle_summary_text: String = ""
var _battle_summary_signature: String = ""

## 固定在大地图左下角的世界日志面板。
var _world_log_panel: PanelContainer = null
var _world_log_scroll: ScrollContainer = null
var _world_log_content: VBoxContainer = null

var _save_dim: ColorRect = null
var _save_panel: PanelContainer = null
var _save_name_edit: LineEdit = null
var _save_status_label: Label = null
var _save_list: ItemList = null
var _save_pause_active: bool = false


func _ready() -> void:
	_context = GameManager.world_context
	if _context == null or not _context.is_valid_world():
		push_error("大地图场景缺少有效的 WorldContext")
		call_deferred("_return_to_main_menu")
		return

	_player_party = _context.get_player_party()
	if _player_party == null:
		push_error("大地图场景找不到玩家部队")
		call_deferred("_return_to_main_menu")
		return

	map_background.set_world_size(_context.world_size)
	_context.world_map_manager.world_bounds = Rect2(Vector2.ZERO, _context.world_size)

	# 从小场景返回时记录当前站在村口的村庄，供地点面板的进入按钮使用；
	# 地点面板不再因为玩家靠近而自动打开，只有主动点击才会显示。
	_settlement_latch_id = GameManager.pending_settlement_latch_id
	GameManager.pending_settlement_latch_id = ""

	_build_ui()
	_build_world_entities()
	_build_settlement_name_tags()
	_connect_time_signals()
	if not EventBus.battle_started.is_connected(_on_battle_started):
		EventBus.battle_started.connect(_on_battle_started)
	if not EventBus.player_encounter_requested.is_connected(_on_player_encounter_requested):
		EventBus.player_encounter_requested.connect(_on_player_encounter_requested)
	if not EventBus.player_battle_interaction_requested.is_connected(
		_on_player_battle_interaction_requested
	):
		EventBus.player_battle_interaction_requested.connect(
			_on_player_battle_interaction_requested
		)
	if not EventBus.battle_participants_updated.is_connected(
		_on_battle_participants_updated
	):
		EventBus.battle_participants_updated.connect(_on_battle_participants_updated)
	if _context.world_log_manager != null \
			and not _context.world_log_manager.entry_added.is_connected(
				_on_world_log_entry_added
			):
		_context.world_log_manager.entry_added.connect(_on_world_log_entry_added)

	camera.position = _player_party.world_position
	_set_camera_zoom(CAMERA_DEFAULT_ZOOM)
	_last_player_position = _player_party.world_position
	_update_time_ui()
	_update_player_info()
	_rebuild_world_log()

	# 若世界 tick 在大地图加载前已产生待处理遭遇，补一次 UI 呈现。
	var pending: Dictionary = _context.encounter_manager.get_pending_player_encounter()
	if not pending.is_empty():
		call_deferred(
			"_on_player_encounter_requested",
			str(pending.get("encounter_id", "")),
			str(pending.get("attacker_party_id", "")),
			str(pending.get("target_party_id", ""))
		)
	var pending_interaction: Dictionary = (
		_context.encounter_manager.get_pending_battle_interaction()
	)
	if not pending_interaction.is_empty():
		call_deferred(
			"_on_player_battle_interaction_requested",
			str(pending_interaction.get("interaction_id", "")),
			str(pending_interaction.get("battle_id", ""))
		)


func _exit_tree() -> void:
	# 场景异常退出时清理本次交互暂停，避免世界永久暂停。
	if _encounter_pause_active:
		TimeManager.pop_pause(GameManager.PAUSE_REASON_ENCOUNTER_DIALOGUE)
		_encounter_pause_active = false
	if _battle_interaction_pause_active:
		TimeManager.pop_pause(GameManager.PAUSE_REASON_BATTLE_INTERACTION)
		_battle_interaction_pause_active = false
	if _context != null:
		_context.encounter_manager.clear_pending_player_encounter()
		_context.encounter_manager.clear_pending_battle_interaction()
		_context.encounter_manager.clear_battle_interaction_latch()


func _process(delta: float) -> void:
	if _player_party == null:
		return

	_update_camera(delta)
	_update_settlement_name_tags()
	_update_player_info()
	_update_battle_display()
	_update_focus_state()
	_validate_battle_interaction()
	_check_party_interaction()
	_update_party_hover()
	_last_player_position = _player_party.world_position


func _unhandled_input(event: InputEvent) -> void:
	if _context == null or _player_party == null \
			or _battle_transition_started or _is_input_blocked():
		return

	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			match key_event.keycode:
				KEY_1:
					_set_world_speed(TimeManager.SPEED_PAUSED)
					get_viewport().set_input_as_handled()
					return
				KEY_2:
					_set_world_speed(TimeManager.SPEED_NORMAL)
					get_viewport().set_input_as_handled()
					return
				KEY_3:
					_set_world_speed(TimeManager.SPEED_DOUBLE)
					get_viewport().set_input_as_handled()
					return
				_:
					pass

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			handle_left_click(get_global_mouse_position())
			get_viewport().set_input_as_handled()
			return

		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_camera_zoom(camera.zoom.x * 1.1)
			get_viewport().set_input_as_handled()
			return

		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_camera_zoom(camera.zoom.x / 1.1)
			get_viewport().set_input_as_handled()
			return


## 鼠标左键统一入口：地点点击优先打开交互面板，其次才是部队指令与移动。
## 地点面板不会由玩家移动或路径接近自动打开。
func handle_left_click(world_position: Vector2) -> bool:
	if _context == null or _player_party == null \
			or _battle_transition_started or _is_input_blocked():
		return false

	var clicked_party := _find_party_at(world_position)
	var clicked_settlement := _find_settlement_at(world_position)
	if clicked_settlement != null:
		# 地点与部队重叠时，以点击位置更近的对象为准。
		var settlement_distance := world_position.distance_to(
			clicked_settlement.world_position
		)
		# 玩家自己的图标不参与地点优先级比较，避免站在地点上时无法点击地点。
		var party_distance: float = INF
		if clicked_party != null \
				and clicked_party.party_id != _context.player_party_id:
			party_distance = world_position.distance_to(clicked_party.world_position)
		if party_distance >= settlement_distance:
			_open_settlement(clicked_settlement)
			return true

	if clicked_party != null \
			and clicked_party.party_id != _context.player_party_id \
			and request_party_command(clicked_party.party_id):
		return true
	return request_player_move(world_position)


## 设置玩家移动目标；成功时把基础倍率切回 1x。
## 只改基础倍率，不清除任何暂停原因；失败时完全不改变时间状态。
func request_player_move(target: Vector2) -> bool:
	if _context == null or _player_party == null \
			or _battle_transition_started or _is_input_blocked():
		return false
	if not Rect2(Vector2.ZERO, _context.world_size).has_point(target):
		return false
	if not _context.world_map_manager.set_party_target(_context.player_party_id, target):
		return false

	# 普通地图移动取消“主动追逐”语义。
	_player_party.focus_party_id = ""
	_camera_offset = Vector2.ZERO
	_set_world_speed(TimeManager.SPEED_NORMAL)
	return true


## 让玩家部队持续跟随目标部队；失败时不改变当前指令。
func request_player_follow(target_party_id: String) -> bool:
	if _context == null or _player_party == null \
			or _battle_transition_started or _is_input_blocked():
		return false
	if not _context.world_map_manager.set_party_follow(
		_context.player_party_id, target_party_id
	):
		return false

	_player_party.focus_party_id = target_party_id
	_camera_offset = Vector2.ZERO
	_set_world_speed(TimeManager.SPEED_NORMAL)
	return true


## 点击部队时：有效部队一律进入主动跟随。
## 静止部队也可能在玩家接近途中开始巡逻，只记录当前位置会让追击丢失目标；
## 跟随同时覆盖远距离点击（目标不在视野内）的情况。
func request_party_command(target_party_id: String) -> bool:
	if _context == null or _player_party == null or target_party_id.is_empty():
		return false
	if target_party_id == _context.player_party_id:
		return false
	var target := _context.party_manager.get_party(target_party_id)
	if target == null:
		return false

	var can_follow: bool = (
		target.is_available_for_world()
		and not target.member_unit_ids.is_empty()
	)
	if can_follow and request_player_follow(target_party_id):
		return true
	if request_player_move(target.world_position):
		# 战斗中/失效部队无法跟随，只前往其当前位置。
		_player_party.focus_party_id = target_party_id
		return true
	return false


## 清理失效或已经远离的追逐焦点。
## 到达主动点击的部队附近时保留焦点，用于只对该目标打开对话。
func _update_focus_state() -> void:
	if _player_party.focus_party_id.is_empty():
		return
	var focus := _context.party_manager.get_party(_player_party.focus_party_id)
	if focus == null \
			or focus.party_id == _context.player_party_id \
			or focus.member_unit_ids.is_empty() \
			or not focus.is_available_for_world():
		_player_party.focus_party_id = ""
		return
	if _battle_transition_started:
		_player_party.focus_party_id = ""
		return
	# 移动停止后不要立刻清除焦点：主动点击部队后会在到达/靠近时据此打开对话。
	# 只有目标已经不在有效交互距离内时才结束追逐语义。
	if _player_party.movement_state != PartyData.MovementState.MOVING \
			and _player_party.world_position.distance_to(focus.world_position) \
			> PARTY_INTERACTION_RADIUS:
		_player_party.focus_party_id = ""


func _is_focusing_party() -> bool:
	return _player_party != null and not _player_party.focus_party_id.is_empty()


func _find_party_at(world_position: Vector2) -> PartyData:
	return _find_party_within(world_position, PARTY_CLICK_RADIUS)


## 返回点击位置附近最近的地点；只用于主动点击判定，不做逐帧自动检测。
func _find_settlement_at(world_position: Vector2) -> SettlementData:
	if _context == null:
		return null
	var nearest: SettlementData = null
	var nearest_distance: float = SETTLEMENT_CLICK_RADIUS
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement == null:
			continue
		var distance := settlement.world_position.distance_to(world_position)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest = settlement
	return nearest


func _find_party_within(world_position: Vector2, radius: float) -> PartyData:
	if _context == null or radius <= 0.0:
		return null
	var nearest: PartyData = null
	var nearest_distance: float = radius
	for party: PartyData in _context.party_manager.get_all_parties():
		if party == null:
			continue
		var distance := party.world_position.distance_to(world_position)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest = party
	return nearest


func _build_world_entities() -> void:
	for child: Node in world_entities.get_children():
		world_entities.remove_child(child)
		child.queue_free()
	_party_icons.clear()

	for party: PartyData in _context.party_manager.get_all_parties():
		var party_icon: PartyIcon = PartyIcon.new()
		party_icon.name = "PartyIcon_%s" % party.party_id
		world_entities.add_child(party_icon)
		var family := _get_family_config(party.family_id)
		# 旗帜优先使用部队自身数据，其次家族旗帜；颜色同理。
		var banner_path: String = party.banner_texture_path
		if banner_path.is_empty() and family != null:
			banner_path = family.banner_texture_path
		party_icon.setup(
			party,
			party.party_id == _context.player_party_id,
			_load_texture(banner_path),
			family.primary_color if family != null else Color(0.0, 0.0, 0.0, 0.0),
			_get_party_marker_style()
		)
		_party_icons[party.party_id] = party_icon
		if party.party_id == _context.player_party_id:
			_player_icon = party_icon

	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		var settlement_icon: SettlementIcon = SettlementIcon.new()
		settlement_icon.name = "SettlementIcon_%s" % settlement.settlement_id
		world_entities.add_child(settlement_icon)
		var family := _get_family_config(settlement.family_id)
		settlement_icon.setup(
			settlement,
			family,
			_load_texture(family.banner_texture_path if family != null else "")
		)

	world_entities.y_sort_enabled = true


func _get_family_config(family_id: String) -> FamilyConfig:
	if _context == null or family_id.is_empty():
		return null
	return _context.family_registry.get_config(family_id)


func _load_texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _get_party_marker_style() -> PartyMarkerStyle:
	if _party_marker_style == null:
		if ResourceLoader.exists(PARTY_MARKER_STYLE_PATH):
			_party_marker_style = load(PARTY_MARKER_STYLE_PATH) as PartyMarkerStyle
		if _party_marker_style == null:
			_party_marker_style = PartyMarkerStyle.create_default()
	return _party_marker_style


## 地点名称位于固定屏幕 UI 层；世界坐标每帧转换为屏幕坐标，
## 因而文字大小不受相机缩放影响，但位置仍跟随建筑。
func _build_settlement_name_tags() -> void:
	if _ui_root == null or _context == null:
		return
	_settlement_name_layer = Control.new()
	_settlement_name_layer.name = "SettlementNameLayer"
	_settlement_name_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_full_rect(_settlement_name_layer)
	_ui_root.add_child(_settlement_name_layer)
	_settlement_name_tags.clear()

	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		var tag := SettlementNameTag.new()
		tag.name = "SettlementNameTag_%s" % settlement.settlement_id
		_settlement_name_layer.add_child(tag)
		tag.setup(settlement)
		_settlement_name_tags[settlement.settlement_id] = tag
	# 名称层放在 UI 最底层，避免覆盖地点/部队/日志面板。
	_ui_root.move_child(_settlement_name_layer, 0)
	_update_settlement_name_tags()


func _update_settlement_name_tags() -> void:
	if _settlement_name_layer == null or camera == null \
			or _context == null:
		return
	var canvas_transform := get_viewport().get_canvas_transform()
	var visible_rect := get_viewport_rect().grow(80.0)
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		var tag := _settlement_name_tags.get(
			settlement.settlement_id
		) as SettlementNameTag
		if tag == null:
			continue
		var screen_position: Vector2 = (
			canvas_transform * settlement.world_position
		)
		# 名称始终位于圆形标记正上方；半径按相机缩放换算，
		# 文字本身保持固定屏幕尺寸。
		var marker_radius: float = SettlementIcon.get_name_anchor_radius(
			settlement.settlement_type
		)
		var anchor := screen_position - Vector2(
			0.0,
			marker_radius * camera.zoom.y + SETTLEMENT_NAME_GAP_ABOVE_MARKER
		)
		tag.visible = visible_rect.has_point(screen_position)
		tag.set_screen_position(anchor)


func get_settlement_name_tag(settlement_id: String) -> SettlementNameTag:
	return _settlement_name_tags.get(settlement_id) as SettlementNameTag


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "UI"
	add_child(canvas)

	_ui_root = Control.new()
	_ui_root.name = "WorldMapUI"
	_ui_root.theme = UiTheme.create()
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_full_rect(_ui_root)
	canvas.add_child(_ui_root)

	_build_top_bar()
	_build_bottom_bar()
	_build_settlement_panel()
	_build_party_dialogue_panel()
	_build_player_encounter_panel()
	_build_battle_interaction_panel()
	_build_party_manage_panel()
	_build_party_hover_panel()
	_build_battle_summary_panel()
	_build_world_log_panel()
	_build_save_panel()


func _build_top_bar() -> void:
	var top_bar := PanelContainer.new()
	top_bar.name = "TopBar"
	top_bar.anchor_right = 1.0
	top_bar.offset_bottom = 48.0
	_ui_root.add_child(top_bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	top_bar.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	_world_time_label = _make_label("世界时间", 15)
	_world_time_label.custom_minimum_size = Vector2(400.0, 0.0)
	row.add_child(_world_time_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_pause_button = _make_button("暂停", "PauseButton")
	_pause_button.tooltip_text = "暂停（快捷键 1）"
	_pause_button.toggle_mode = true
	_pause_button.pressed.connect(_on_pause_pressed)
	row.add_child(_pause_button)
	_time_buttons.append(_pause_button)

	_speed_one_button = _make_button("1x", "SpeedOneButton")
	_speed_one_button.tooltip_text = "1 倍速（快捷键 2）"
	_speed_one_button.toggle_mode = true
	_speed_one_button.pressed.connect(_on_speed_one_pressed)
	row.add_child(_speed_one_button)
	_time_buttons.append(_speed_one_button)

	_speed_two_button = _make_button("2x", "SpeedTwoButton")
	_speed_two_button.tooltip_text = "2 倍速（快捷键 3）"
	_speed_two_button.toggle_mode = true
	_speed_two_button.pressed.connect(_on_speed_two_pressed)
	row.add_child(_speed_two_button)
	_time_buttons.append(_speed_two_button)

	var party_button := _make_button("部队", "PartyButton")
	party_button.tooltip_text = "查看玩家部队与士兵详情"
	party_button.pressed.connect(_on_party_manage_pressed)
	row.add_child(party_button)

	var save_button := _make_button("保存", "SaveButton")
	save_button.pressed.connect(_on_save_pressed)
	row.add_child(save_button)

	var menu_button := _make_button("主菜单", "MainMenuButton")
	menu_button.pressed.connect(_on_main_menu_pressed)
	row.add_child(menu_button)


func _build_bottom_bar() -> void:
	var bottom_bar := PanelContainer.new()
	bottom_bar.name = "BottomBar"
	bottom_bar.anchor_top = 1.0
	bottom_bar.anchor_right = 1.0
	bottom_bar.anchor_bottom = 1.0
	bottom_bar.offset_top = -38.0
	_ui_root.add_child(bottom_bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	bottom_bar.add_child(margin)

	_player_info_label = _make_label("玩家部队", 14)
	margin.add_child(_player_info_label)


func _build_settlement_panel() -> void:
	_settlement_panel = PanelContainer.new()
	_settlement_panel.name = "SettlementPanel"
	_settlement_panel.visible = false
	_settlement_panel.anchor_top = 0.5
	_settlement_panel.anchor_bottom = 0.5
	_settlement_panel.offset_left = 20.0
	_settlement_panel.offset_top = -110.0
	_settlement_panel.offset_right = 340.0
	_settlement_panel.offset_bottom = 110.0
	_ui_root.add_child(_settlement_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_settlement_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	_settlement_name_label = _make_label("", 24)
	_settlement_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_settlement_name_label)

	_settlement_type_label = _make_label("", 16)
	_settlement_type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_settlement_type_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	_settlement_enter_button = _make_button("进入村庄", "SettlementEnterButton")
	_settlement_enter_button.custom_minimum_size = Vector2(0.0, 36.0)
	_settlement_enter_button.visible = false
	_settlement_enter_button.pressed.connect(_on_settlement_enter_pressed)
	column.add_child(_settlement_enter_button)

	var leave_button := _make_button("离开地点", "SettlementLeaveButton")
	leave_button.custom_minimum_size = Vector2(0.0, 36.0)
	leave_button.pressed.connect(_on_settlement_leave_pressed)
	column.add_child(leave_button)


func _build_party_dialogue_panel() -> void:
	_party_panel = PanelContainer.new()
	_party_panel.name = "PartyDialoguePanel"
	_party_panel.visible = false
	_apply_bottom_dialogue_layout(_party_panel)
	_ui_root.add_child(_party_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_party_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	margin.add_child(row)

	_party_portrait = EncounterPortrait.new()
	_party_portrait.name = "PartyPortrait"
	_party_portrait.custom_minimum_size = NPC_DIALOGUE_PORTRAIT_SIZE
	_party_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_party_portrait.setup(_context.unit_manager)
	row.add_child(_party_portrait)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)

	_party_name_label = _make_label("", 24)
	_party_name_label.name = "PartyNameLabel"
	column.add_child(_party_name_label)

	_party_faction_label = _make_label("", 15)
	_party_faction_label.name = "PartyFactionLabel"
	column.add_child(_party_faction_label)

	_party_troop_label = _make_label("", 15)
	_party_troop_label.name = "PartyTroopLabel"
	column.add_child(_party_troop_label)

	_party_dialogue_label = _make_label("", 16)
	_party_dialogue_label.name = "PartyDialogueTextLabel"
	_party_dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_party_dialogue_label.custom_minimum_size = Vector2(0.0, 52.0)
	column.add_child(_party_dialogue_label)

	_party_status_label = _make_label("", 13)
	_party_status_label.name = "PartyDialogueStatus"
	_party_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_party_status_label.custom_minimum_size = Vector2(0.0, 30.0)
	column.add_child(_party_status_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)

	_party_fight_button = _make_button("发起战斗", "PartyFightButton")
	_party_fight_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_party_fight_button.custom_minimum_size = Vector2(0.0, 38.0)
	_party_fight_button.pressed.connect(_on_party_fight_pressed)
	buttons.add_child(_party_fight_button)

	var leave_button := _make_button("离开", "PartyLeaveButton")
	leave_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leave_button.custom_minimum_size = Vector2(0.0, 38.0)
	leave_button.pressed.connect(_on_party_leave_pressed)
	buttons.add_child(leave_button)


func _build_battle_interaction_panel() -> void:
	_battle_interaction_panel = PanelContainer.new()
	_battle_interaction_panel.name = "BattleInteractionPanel"
	_battle_interaction_panel.visible = false
	_battle_interaction_panel.anchor_top = 0.5
	_battle_interaction_panel.anchor_bottom = 0.5
	_battle_interaction_panel.offset_left = 20.0
	_battle_interaction_panel.offset_top = -150.0
	_battle_interaction_panel.offset_right = 400.0
	_battle_interaction_panel.offset_bottom = 150.0
	_ui_root.add_child(_battle_interaction_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_battle_interaction_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := _make_label("遭遇战", 24)
	title.name = "BattleInteractionTitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	_battle_interaction_summary_label = _make_label("", 15)
	_battle_interaction_summary_label.name = "BattleInteractionSummaryLabel"
	_battle_interaction_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_battle_interaction_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_battle_interaction_summary_label.custom_minimum_size = Vector2(0.0, 86.0)
	column.add_child(_battle_interaction_summary_label)

	_battle_interaction_status_label = _make_label("", 13)
	_battle_interaction_status_label.name = "BattleInteractionStatusLabel"
	_battle_interaction_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_battle_interaction_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_battle_interaction_status_label.custom_minimum_size = Vector2(0.0, 32.0)
	column.add_child(_battle_interaction_status_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)

	_battle_join_button = _make_button("加入战斗", "BattleJoinButton")
	_battle_join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_battle_join_button.custom_minimum_size = Vector2(0.0, 42.0)
	_battle_join_button.pressed.connect(_on_battle_join_pressed)
	buttons.add_child(_battle_join_button)

	_battle_leave_button = _make_button("离开", "BattleLeaveButton")
	_battle_leave_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_battle_leave_button.custom_minimum_size = Vector2(0.0, 42.0)
	_battle_leave_button.pressed.connect(_on_battle_leave_pressed)
	buttons.add_child(_battle_leave_button)


## 屏幕下方的 NPC 遭遇对话：左侧领袖头像/剪影，右侧姓名、对白与动态选项。
func _build_player_encounter_panel() -> void:
	_encounter_panel = PanelContainer.new()
	_encounter_panel.name = "PlayerEncounterPanel"
	_encounter_panel.visible = false
	_apply_bottom_dialogue_layout(_encounter_panel)
	_ui_root.add_child(_encounter_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_encounter_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	margin.add_child(row)

	_encounter_portrait = EncounterPortrait.new()
	_encounter_portrait.name = "EncounterPortrait"
	_encounter_portrait.custom_minimum_size = NPC_DIALOGUE_PORTRAIT_SIZE
	_encounter_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_encounter_portrait.setup(_context.unit_manager)
	row.add_child(_encounter_portrait)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)

	_encounter_name_label = _make_label("", 24)
	_encounter_name_label.name = "EncounterPartyNameLabel"
	column.add_child(_encounter_name_label)

	_encounter_faction_label = _make_label("", 15)
	_encounter_faction_label.name = "EncounterFactionLabel"
	column.add_child(_encounter_faction_label)

	_encounter_troop_label = _make_label("", 15)
	_encounter_troop_label.name = "EncounterTroopLabel"
	column.add_child(_encounter_troop_label)

	_encounter_description_label = _make_label("", 17)
	_encounter_description_label.name = "EncounterDescriptionLabel"
	_encounter_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_encounter_description_label.custom_minimum_size = Vector2(0.0, 58.0)
	column.add_child(_encounter_description_label)

	_encounter_status_label = _make_label("", 13)
	_encounter_status_label.name = "EncounterStatusLabel"
	_encounter_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_encounter_status_label.custom_minimum_size = Vector2(0.0, 28.0)
	column.add_child(_encounter_status_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	var buttons := HBoxContainer.new()
	buttons.name = "EncounterOptions"
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)

	_encounter_fight_button = _make_button("战斗", "EncounterFightButton")
	_encounter_fight_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_encounter_fight_button.custom_minimum_size = Vector2(0.0, 44.0)
	_encounter_fight_button.pressed.connect(_on_encounter_fight_pressed)
	buttons.add_child(_encounter_fight_button)

	_encounter_leave_button = _make_button("撤退", "EncounterLeaveButton")
	_encounter_leave_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_encounter_leave_button.custom_minimum_size = Vector2(0.0, 44.0)
	_encounter_leave_button.pressed.connect(_on_encounter_leave_pressed)
	buttons.add_child(_encounter_leave_button)


## 将所有遭遇/部队对话面板统一锚定在屏幕下方。
func _apply_bottom_dialogue_layout(panel: PanelContainer) -> void:
	panel.anchor_left = 0.5
	panel.anchor_top = 1.0
	panel.anchor_right = 0.5
	panel.anchor_bottom = 1.0
	panel.offset_left = -NPC_DIALOGUE_PANEL_WIDTH * 0.5
	panel.offset_right = NPC_DIALOGUE_PANEL_WIDTH * 0.5
	panel.offset_top = -NPC_DIALOGUE_BOTTOM_MARGIN - NPC_DIALOGUE_PANEL_HEIGHT
	panel.offset_bottom = -NPC_DIALOGUE_BOTTOM_MARGIN


func _on_player_encounter_requested(
	encounter_id: String, attacker_party_id: String, target_party_id: String
) -> void:
	if _context == null or _player_party == null or _encounter_panel == null:
		if _context != null:
			_context.encounter_manager.clear_pending_player_encounter()
		return
	if target_party_id != _context.player_party_id:
		_context.encounter_manager.clear_pending_player_encounter()
		return
	if _battle_transition_started or _encounter_panel.visible:
		return
	var pending_encounter: Dictionary = (
		_context.encounter_manager.get_pending_player_encounter()
	)
	if pending_encounter.is_empty() \
			or str(pending_encounter.get("encounter_id", "")) != encounter_id:
		return
	if _context.battle_manager.current_battle != null:
		_context.encounter_manager.clear_pending_player_encounter()
		return
	if _save_panel.visible or _settlement_panel.visible \
			or _party_panel.visible or _party_manage_panel.visible \
			or _battle_interaction_panel.visible:
		_context.encounter_manager.clear_pending_player_encounter()
		return

	var attacker := _context.party_manager.get_party(attacker_party_id)
	if attacker == null or attacker.member_unit_ids.is_empty():
		_context.encounter_manager.clear_pending_player_encounter()
		return

	_encounter_id = encounter_id
	# 双方在 WorldMapManager 中已停止；这里再确保一次，并清除攻击意图。
	# 待处理遭遇存在期间 WorldSimulation 不执行 AI，旧追击指令不会覆盖当前状态。
	_context.world_map_manager.stop_party(_context.player_party_id)
	_context.world_map_manager.stop_party(attacker_party_id)
	attacker.attack_intent = false

	var reason := int(pending_encounter.get(
		"reason", EncounterManager.EncounterReason.OTHER
	)) as EncounterManager.EncounterReason
	_encounter_leave_allowed = EncounterManager.can_leave_encounter(reason)
	var leader := _context.party_manager.get_leader_unit(attacker_party_id)
	_encounter_name_label.text = _party_leader_name(attacker, leader)
	_encounter_faction_label.text = "阵营：%s" % _faction_display_name(attacker.faction_id)
	_encounter_troop_label.text = "兵力：%d" % attacker.member_unit_ids.size()
	_encounter_description_label.text = _encounter_dialogue_text(reason, attacker)
	_encounter_status_label.text = ""
	if _encounter_portrait != null:
		_encounter_portrait.show_leader(leader)
	# 敌对部队主动追击并成功拦截时，只保留战斗等敌对处理选项。
	# 隐藏并禁用离开按钮，避免通过等价按钮绕过拦截规则。
	_encounter_leave_button.visible = _encounter_leave_allowed
	_encounter_leave_button.disabled = not _encounter_leave_allowed
	_encounter_fight_button.disabled = attacker.member_unit_ids.is_empty() \
		or _player_party.member_unit_ids.is_empty()
	_encounter_panel.visible = true

	if not _encounter_pause_active:
		TimeManager.push_pause(GameManager.PAUSE_REASON_ENCOUNTER_DIALOGUE)
		_encounter_pause_active = true
	_set_time_buttons_enabled(false)
	_update_time_ui()


## 清理异常关闭的遭遇对话；不改变基础世界倍率。
func cancel_player_encounter() -> void:
	if _encounter_panel != null:
		_encounter_panel.visible = false
	if _encounter_portrait != null:
		_encounter_portrait.clear()
	if _encounter_pause_active:
		TimeManager.pop_pause(GameManager.PAUSE_REASON_ENCOUNTER_DIALOGUE)
		_encounter_pause_active = false
	if _context != null:
		_context.encounter_manager.clear_pending_player_encounter()
	_encounter_id = ""
	_encounter_leave_allowed = true
	_set_time_buttons_enabled(true)
	_update_time_ui()


func _on_encounter_fight_pressed() -> void:
	if _context == null or _player_party == null or _encounter_panel == null:
		return
	if not _encounter_panel.visible:
		return

	var pending: Dictionary = _context.encounter_manager.get_pending_player_encounter()
	if pending.is_empty() or str(pending.get("encounter_id", "")) != _encounter_id:
		cancel_player_encounter()
		return
	var attacker := _context.party_manager.get_party(
		str(pending.get("attacker_party_id", ""))
	)
	if attacker == null or not attacker.is_available_for_world() \
			or attacker.member_unit_ids.is_empty():
		_encounter_status_label.text = "对方已经离开"
		cancel_player_encounter()
		return
	if _player_party.member_unit_ids.is_empty():
		_encounter_status_label.text = "玩家部队没有可战士兵"
		cancel_player_encounter()
		return

	var midpoint := (_player_party.world_position + attacker.world_position) * 0.5
	# 先置位，避免 battle_started 信号重复触发场景切换。
	_battle_transition_started = true
	var session := _context.battle_manager.start_battle(
		[_context.player_party_id], [attacker.party_id], midpoint, false
	)
	if session == null:
		_battle_transition_started = false
		_encounter_status_label.text = "无法开始战斗"
		return

	var error: Error = SceneManager.change_scene(SceneManager.BATTLE_SCENE)
	if error != OK:
		# 战斗场景加载失败：中止战斗，保留遭遇对话与暂停，允许玩家重试。
		_context.battle_manager.abort_battle(session.battle_id)
		_battle_transition_started = false
		_encounter_status_label.text = "战斗场景加载失败"
		return

	_context.encounter_manager.clear_pending_player_encounter()
	_encounter_id = ""
	_encounter_panel.visible = false
	if _encounter_pause_active:
		TimeManager.pop_pause(GameManager.PAUSE_REASON_ENCOUNTER_DIALOGUE)
		_encounter_pause_active = false


## 玩家选择撤退：清理待处理遭遇与暂停，记录拒绝触发范围；
## 双方保持当前停止位置，世界恢复原基础倍率，AI 可在下一次决策继续行动。
## 敌对追击拦截（ENEMY_PURSUIT）不允许直接离开，即使按钮被程序化触发也会被拒绝。
func _on_encounter_leave_pressed() -> void:
	if _context == null or _encounter_panel == null or not _encounter_panel.visible:
		return
	if not _encounter_leave_allowed:
		return
	var pending: Dictionary = _context.encounter_manager.get_pending_player_encounter()
	var attacker_id: String = str(pending.get("attacker_party_id", ""))
	_encounter_panel.visible = false
	_encounter_id = ""
	if _encounter_pause_active:
		TimeManager.pop_pause(GameManager.PAUSE_REASON_ENCOUNTER_DIALOGUE)
		_encounter_pause_active = false
	_context.encounter_manager.decline_player_encounter(attacker_id)
	_set_time_buttons_enabled(true)
	_update_time_ui()


func _encounter_text() -> EncounterTextConfig:
	if _encounter_text_config == null:
		if ResourceLoader.exists(ENCOUNTER_TEXT_CONFIG_PATH):
			_encounter_text_config = load(
				ENCOUNTER_TEXT_CONFIG_PATH
			) as EncounterTextConfig
		if _encounter_text_config == null:
			_encounter_text_config = EncounterTextConfig.create_default()
	return _encounter_text_config


## 对白只来自配置：reason（为何遭遇）× 部队类型（谁在说话）。
func _encounter_dialogue_text(
	reason: EncounterManager.EncounterReason, party: PartyData
) -> String:
	var kind_key: String = party.get_kind_key() if party != null else "GENERIC"
	return _encounter_text().get_text(
		EncounterManager.reason_key(reason), kind_key
	)


func _party_leader(party: PartyData) -> UnitData:
	if party == null or _context == null:
		return null
	return _context.party_manager.get_leader_unit(party.party_id)


## 显示领袖名称；没有领袖数据时回退到部队名，避免空标题。
func _party_leader_name(party: PartyData, leader: UnitData = null) -> String:
	if leader != null and not leader.display_name.strip_edges().is_empty():
		return leader.display_name
	return party.party_name if party != null else "未知部队"


func _build_party_manage_panel() -> void:
	_party_manage_panel = PartyPanel.new()
	_party_manage_panel.name = "PartyPanel"
	_party_manage_panel.visible = false
	_party_manage_panel.closed.connect(_on_party_manage_closed)
	_ui_root.add_child(_party_manage_panel)
	_party_manage_panel.setup(_context)


## 打开玩家部队管理面板；失败返回 false 且不改变时间状态。
func open_party_panel() -> bool:
	if _context == null or _player_party == null:
		return false
	if _battle_transition_started or _party_manage_panel == null:
		return false
	if _party_manage_panel.visible:
		return false
	if _save_panel.visible or _settlement_panel.visible or _party_panel.visible:
		return false
	if not _player_party.is_available_for_world():
		push_warning("当前部队状态不可用，无法打开部队面板")
		return false

	TimeManager.push_pause(GameManager.PAUSE_REASON_UI_PANEL)
	_party_manage_pause_active = true
	_party_manage_panel.open()
	_set_time_buttons_enabled(false)
	_update_time_ui()
	return true


func close_party_panel() -> void:
	if _party_manage_panel == null or not _party_manage_panel.visible:
		return
	_party_manage_panel.close()


func _on_party_manage_pressed() -> void:
	open_party_panel()


func _on_party_manage_closed() -> void:
	if _party_manage_pause_active:
		TimeManager.pop_pause(GameManager.PAUSE_REASON_UI_PANEL)
		_party_manage_pause_active = false
	_set_time_buttons_enabled(true)
	_update_time_ui()


# ---------------------------------------------------------------------------
# 部队悬浮信息
# ---------------------------------------------------------------------------


func _build_party_hover_panel() -> void:
	_hover_panel = PanelContainer.new()
	_hover_panel.name = "PartyHoverPanel"
	_hover_panel.visible = false
	_hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_panel.custom_minimum_size = Vector2(HOVER_PANEL_WIDTH, 0.0)
	_ui_root.add_child(_hover_panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_hover_panel.add_child(margin)

	_hover_content = VBoxContainer.new()
	_hover_content.name = "PartyHoverContent"
	_hover_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_content.add_theme_constant_override("separation", 2)
	margin.add_child(_hover_content)


## 同场战斗的唯一汇总面板：按战斗侧分组，同侧多支部队并列展示。
func _build_battle_summary_panel() -> void:
	_battle_summary_panel = PanelContainer.new()
	_battle_summary_panel.name = "BattleSummaryPanel"
	_battle_summary_panel.visible = false
	_battle_summary_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_battle_summary_panel.custom_minimum_size = Vector2(BATTLE_SUMMARY_WIDTH, 0.0)
	_ui_root.add_child(_battle_summary_panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_battle_summary_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)

	_battle_summary_title = _make_label("战斗", 17)
	_battle_summary_title.name = "BattleSummaryTitle"
	_battle_summary_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_battle_summary_title)

	var separator := HSeparator.new()
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(separator)

	_battle_summary_content = VBoxContainer.new()
	_battle_summary_content.name = "BattleSummaryContent"
	_battle_summary_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_battle_summary_content.add_theme_constant_override("separation", 1)
	column.add_child(_battle_summary_content)


## 固定在大地图屏幕左下角的世界日志；内容只读 WorldLogManager。
func _build_world_log_panel() -> void:
	_world_log_panel = PanelContainer.new()
	_world_log_panel.name = "WorldLogPanel"
	_world_log_panel.anchor_left = 0.0
	_world_log_panel.anchor_top = 1.0
	_world_log_panel.anchor_right = 0.0
	_world_log_panel.anchor_bottom = 1.0
	_world_log_panel.offset_left = 12.0
	_world_log_panel.offset_right = 12.0 + WORLD_LOG_WIDTH
	_world_log_panel.offset_top = -54.0 - WORLD_LOG_HEIGHT
	_world_log_panel.offset_bottom = -54.0
	# PASS：滚动区域仍可滚轮查看历史，未处理的鼠标点击不会被面板永久吞掉。
	_world_log_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_ui_root.add_child(_world_log_panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_world_log_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)

	var title := _make_label("世界日志", 16)
	title.name = "WorldLogTitle"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)

	var separator := HSeparator.new()
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(separator)

	_world_log_scroll = ScrollContainer.new()
	_world_log_scroll.name = "WorldLogScroll"
	_world_log_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_world_log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_world_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_world_log_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	column.add_child(_world_log_scroll)

	_world_log_content = VBoxContainer.new()
	_world_log_content.name = "WorldLogContent"
	_world_log_content.mouse_filter = Control.MOUSE_FILTER_PASS
	_world_log_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_world_log_content.add_theme_constant_override("separation", 3)
	_world_log_scroll.add_child(_world_log_content)


func _rebuild_world_log() -> void:
	if _world_log_content == null or _context == null:
		return
	for child: Node in _world_log_content.get_children():
		_world_log_content.remove_child(child)
		child.queue_free()

	var entries := _context.world_log_manager.get_entries()
	if entries.is_empty():
		var empty := _make_label("暂无世界事件", 12)
		empty.name = "WorldLogEmpty"
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		empty.modulate = Color(0.82, 0.82, 0.78)
		_world_log_content.add_child(empty)
		return

	for index: int in range(entries.size()):
		var entry: WorldLogEntry = entries[index]
		var line: String = entry.text
		if not entry.time_text.is_empty():
			line = "%s  %s" % [entry.time_text, entry.text]
		var label := _make_label(line, 12)
		label.name = "WorldLogEntry_%d" % index
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.custom_minimum_size = Vector2(WORLD_LOG_WIDTH - 56.0, 0.0)
		_world_log_content.add_child(label)

	call_deferred("_scroll_world_log_to_bottom")


func _scroll_world_log_to_bottom() -> void:
	if _world_log_scroll == null:
		return
	var scroll_bar := _world_log_scroll.get_v_scroll_bar()
	if scroll_bar != null:
		_world_log_scroll.scroll_vertical = int(scroll_bar.max_value)


func _on_world_log_entry_added(_entry: WorldLogEntry) -> void:
	_rebuild_world_log()


func get_world_log_text() -> String:
	var lines: Array[String] = []
	if _context != null:
		for entry: WorldLogEntry in _context.world_log_manager.get_entries():
			lines.append(entry.text)
	return "\n".join(lines)


func get_world_log_entry_count() -> int:
	return _context.world_log_manager.get_entry_count() if _context != null else 0


func is_world_log_visible() -> bool:
	return _world_log_panel != null and _world_log_panel.visible


func _update_party_hover() -> void:
	if _hover_panel == null:
		return
	if _context == null or _player_party == null or _battle_transition_started \
			or _is_input_blocked():
		_hide_party_hover()
		return
	_apply_party_hover(get_global_mouse_position())


## 供输入与自动化测试共用：在给定世界坐标上显示对应部队的悬浮面板。
func _apply_party_hover(world_position: Vector2) -> void:
	var party := _find_party_within(world_position, PARTY_HOVER_RADIUS)
	if party == null:
		_hide_party_hover()
		return
	# 参战部队已经合并到战斗标记，不再显示原图标悬浮信息。
	var active_battle := _context.battle_manager.current_battle
	if active_battle != null and active_battle.is_party_involved(party.party_id):
		_hide_party_hover()
		return
	var signature: String = _party_composition_signature(party)
	if party.party_id != _hover_party_id or signature != _hover_signature:
		_hover_party_id = party.party_id
		_hover_signature = signature
		_rebuild_party_hover(party)
	_position_party_hover(get_viewport().get_mouse_position())


func _hide_party_hover() -> void:
	_hover_party_id = ""
	_hover_signature = ""
	if _hover_panel != null:
		_hover_panel.visible = false


## 成员构成变化时刷新悬浮面板；只比较兵种/骑乘/身份，不读取完整属性。
func _party_composition_signature(party: PartyData) -> String:
	var parts: Array[String] = []
	for unit_id: String in party.member_unit_ids:
		var unit := _context.unit_manager.get_unit(unit_id)
		if unit == null:
			parts.append("%s:missing" % unit_id)
			continue
		parts.append("%s:%s:%s" % [
			unit.config_id,
			"m" if unit.is_mounted else "f",
			"p" if unit.is_player_character else "n",
		])
	return "|".join(parts)


func _rebuild_party_hover(party: PartyData) -> void:
	if _hover_panel == null or _hover_content == null or party == null:
		return
	for child: Node in _hover_content.get_children():
		_hover_content.remove_child(child)
		child.queue_free()

	var title := _make_label(party.party_name, 17)
	title.name = "PartyHoverName"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_content.add_child(title)
	var separator := HSeparator.new()
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_content.add_child(separator)

	var lines: Array[String] = _party_composition_lines(party)
	if lines.is_empty():
		lines.append("无成员")
	for line: String in lines:
		var label := _make_label(line, 14)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hover_content.add_child(label)

	var height: float = 58.0 + float(lines.size()) * HOVER_PANEL_LINE_HEIGHT
	_hover_panel.custom_minimum_size = Vector2(HOVER_PANEL_WIDTH, height)
	_hover_panel.size = Vector2(HOVER_PANEL_WIDTH, height)
	_hover_panel.visible = true


## 按兵种与骑乘状态合并成员构成；玩家角色单独显示。
func _party_composition_lines(party: PartyData) -> Array[String]:
	var groups: Dictionary = {}
	var player_count: int = 0
	for unit_id: String in party.member_unit_ids:
		var unit := _context.unit_manager.get_unit(unit_id)
		if unit == null:
			continue
		if unit.is_player_character:
			player_count += 1
			continue
		var config := _context.unit_manager.get_unit_config(unit.config_id)
		var unit_class_name: String = (
			config.display_name if config != null else unit.config_id
		)
		var label: String = ("骑马" if unit.is_mounted else "") + unit_class_name
		groups[label] = int(groups.get(label, 0)) + 1

	var keys: Array[String] = []
	for key: Variant in groups.keys():
		keys.append(str(key))
	keys.sort()
	var lines: Array[String] = []
	for key: String in keys:
		lines.append("• %s（%d）" % [key, int(groups[key])])
	if player_count > 0:
		lines.append("• 玩家角色（%d）" % player_count)
	return lines


# ---------------------------------------------------------------------------
# 大地图战斗标记与汇总 UI
# ---------------------------------------------------------------------------


func _update_battle_display() -> void:
	if _context == null:
		return
	var battle := _context.battle_manager.current_battle
	if battle == null:
		_clear_battle_display()
		return
	_ensure_battle_marker(battle)
	_update_battle_participant_icons(battle)
	_refresh_battle_summary(battle)


func _ensure_battle_marker(battle: BattleSession) -> void:
	if _battle_marker == null or _battle_marker_id != battle.battle_id:
		if _battle_marker != null and is_instance_valid(_battle_marker):
			_battle_marker.queue_free()
		_battle_marker = BattleMarker.new()
		world_entities.add_child(_battle_marker)
		_battle_marker.setup(battle.battle_id, battle.world_position)
		_battle_marker_id = battle.battle_id
	else:
		_battle_marker.set_battle_position(battle.world_position)
	_battle_marker.set_alive_count(_count_battle_alive(battle))


## 同一场战斗的参战部队只保留战斗标记，不再显示各自的部队图标。
func _update_battle_participant_icons(battle: BattleSession) -> void:
	for party_id_value: Variant in _party_icons.keys():
		var party_id: String = str(party_id_value)
		var icon := _party_icons.get(party_id) as PartyIcon
		if icon == null or not is_instance_valid(icon):
			continue
		icon.visible = not battle.is_party_involved(party_id)


func _clear_battle_display() -> void:
	if _battle_marker != null and is_instance_valid(_battle_marker):
		_battle_marker.queue_free()
	_battle_marker = null
	_battle_marker_id = ""
	for party_id_value: Variant in _party_icons.keys():
		var icon := _party_icons.get(party_id_value) as PartyIcon
		if icon != null and is_instance_valid(icon):
			icon.visible = true
	if _battle_summary_panel != null:
		_battle_summary_panel.visible = false
	_battle_summary_signature = ""
	_battle_summary_text = ""


func _refresh_battle_summary(battle: BattleSession) -> void:
	if _battle_summary_panel == null:
		return
	var lines := _build_battle_summary_lines(battle)
	var text: String = "\n".join(lines)
	if text != _battle_summary_signature:
		_battle_summary_signature = text
		_battle_summary_text = text
		_rebuild_battle_summary(lines)
	_battle_summary_title.text = "战斗 · 已交战 %d 小时 · 存活 %d" % [
		battle.offscreen_settlements_done,
		_count_battle_alive(battle),
	]

	var show_panel: bool = not _is_input_blocked() and not _battle_transition_started
	if show_panel:
		show_panel = _position_battle_summary()
	_battle_summary_panel.visible = show_panel


func _rebuild_battle_summary(lines: Array[String]) -> void:
	if _battle_summary_content == null:
		return
	for child: Node in _battle_summary_content.get_children():
		_battle_summary_content.remove_child(child)
		child.queue_free()

	for line: String in lines:
		if line == BATTLE_SUMMARY_SEPARATOR:
			var separator := HSeparator.new()
			separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_battle_summary_content.add_child(separator)
			continue
		var is_composition: bool = line.begins_with("  ")
		var label := _make_label(line, 14 if is_composition else 15)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not is_composition:
			label.add_theme_color_override("font_color", Color("#f0d8a0"))
		_battle_summary_content.add_child(label)

	var height: float = 66.0 + float(lines.size()) * 20.0
	_battle_summary_panel.custom_minimum_size = Vector2(BATTLE_SUMMARY_WIDTH, height)


## 按 BattleSession 的 side_index 分组，不使用阵营代替战斗侧。
func _build_battle_summary_lines(battle: BattleSession) -> Array[String]:
	var lines: Array[String] = []
	var sides := battle.get_side_indices()
	for side_position: int in range(sides.size()):
		var side_index: int = sides[side_position]
		for party_id: String in battle.get_side_party_ids(side_index):
			var party := _context.party_manager.get_party(party_id)
			lines.append(party.party_name if party != null else party_id)
			var composition := _battle_party_composition(battle, party_id)
			if composition.is_empty():
				lines.append("  无存活人员")
			else:
				for entry: String in composition:
					lines.append("  • %s" % entry)
		if side_position < sides.size() - 1:
			lines.append(BATTLE_SUMMARY_SEPARATOR)
	return lines


## 只统计 BattleUnitState 中仍存活的人员；UI 不修改战斗数据。
func _battle_party_composition(
	battle: BattleSession, party_id: String
) -> Array[String]:
	var groups: Dictionary = {}
	var player_count: int = 0
	for unit_id: String in battle.get_party_unit_ids(party_id):
		var state := battle.get_unit_state(unit_id)
		if state == null or not state.alive or state.battle_hp <= 0:
			continue
		var unit := _context.unit_manager.get_unit(unit_id)
		if unit == null:
			continue
		if unit.is_player_character:
			player_count += 1
			continue
		var config := _context.unit_manager.get_unit_config(unit.config_id)
		var unit_name: String = config.display_name if config != null else unit.config_id
		var label: String = ("骑马" if unit.is_mounted else "") + unit_name
		groups[label] = int(groups.get(label, 0)) + 1

	var keys: Array[String] = []
	for key: Variant in groups.keys():
		keys.append(str(key))
	keys.sort()
	var result: Array[String] = []
	for key: String in keys:
		result.append("%s（%d）" % [key, int(groups[key])])
	if player_count > 0:
		result.append("玩家角色（%d）" % player_count)
	return result


func _count_battle_alive(battle: BattleSession) -> int:
	if battle == null:
		return 0
	var count: int = 0
	for side_index: int in battle.get_side_indices():
		for unit_id: String in battle.get_side_unit_ids(side_index):
			var state := battle.get_unit_state(unit_id)
			if state != null and state.alive and state.battle_hp > 0:
				count += 1
	return count


func _position_battle_summary() -> bool:
	if _battle_marker == null or not is_instance_valid(_battle_marker) \
			or _battle_summary_panel == null:
		return false
	var screen_position: Vector2 = (
		_battle_marker.get_global_transform_with_canvas().origin
	)
	var viewport_size := get_viewport_rect().size
	var offscreen_margin: float = 60.0
	if screen_position.x < -offscreen_margin \
			or screen_position.y < -offscreen_margin \
			or screen_position.x > viewport_size.x + offscreen_margin \
			or screen_position.y > viewport_size.y + offscreen_margin:
		return false
	var panel_size := Vector2(
		BATTLE_SUMMARY_WIDTH,
		maxf(_battle_summary_panel.custom_minimum_size.y, 60.0)
	)
	var desired := screen_position + Vector2(26.0, 26.0)
	desired.x = clampf(desired.x, 8.0, maxf(8.0, viewport_size.x - panel_size.x - 8.0))
	desired.y = clampf(desired.y, 56.0, maxf(56.0, viewport_size.y - panel_size.y - 8.0))
	_battle_summary_panel.position = desired
	return true


func get_battle_marker() -> BattleMarker:
	return _battle_marker


func get_battle_summary_text() -> String:
	return _battle_summary_text


func is_battle_summary_visible() -> bool:
	return _battle_summary_panel != null and _battle_summary_panel.visible


func _position_party_hover(screen_position: Vector2) -> void:
	if _hover_panel == null:
		return
	var viewport_size := get_viewport_rect().size
	var panel_size := Vector2(
		HOVER_PANEL_WIDTH, maxf(_hover_panel.custom_minimum_size.y, 60.0)
	)
	var desired := screen_position + Vector2(20.0, 20.0)
	desired.x = clampf(desired.x, 8.0, maxf(8.0, viewport_size.x - panel_size.x - 8.0))
	desired.y = clampf(desired.y, 8.0, maxf(8.0, viewport_size.y - panel_size.y - 8.0))
	_hover_panel.position = desired


## 测试接口：返回悬浮面板当前文本。
func get_hover_panel_text() -> String:
	if _hover_content == null:
		return ""
	var lines: Array[String] = []
	for child: Node in _hover_content.get_children():
		var label := child as Label
		if label != null:
			lines.append(label.text)
	return "\n".join(lines)


func get_hover_party_id() -> String:
	return _hover_party_id


func get_settlement_latch_id() -> String:
	return _settlement_latch_id


func apply_hover_for_test(world_position: Vector2) -> void:
	_apply_party_hover(world_position)


func clear_hover_for_test() -> void:
	_hide_party_hover()


func is_hover_panel_visible() -> bool:
	return _hover_panel != null and _hover_panel.visible


func _build_save_panel() -> void:
	_save_dim = ColorRect.new()
	_save_dim.name = "SaveDim"
	_save_dim.color = Color(0.0, 0.0, 0.0, 0.45)
	_save_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_save_dim.visible = false
	_set_full_rect(_save_dim)
	_ui_root.add_child(_save_dim)

	_save_panel = PanelContainer.new()
	_save_panel.name = "SavePanel"
	_save_panel.visible = false
	_save_panel.anchor_left = 0.5
	_save_panel.anchor_top = 0.5
	_save_panel.anchor_right = 0.5
	_save_panel.anchor_bottom = 0.5
	_save_panel.offset_left = -250.0
	_save_panel.offset_top = -230.0
	_save_panel.offset_right = 250.0
	_save_panel.offset_bottom = 230.0
	_ui_root.add_child(_save_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_save_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var title := _make_label("保存游戏", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	column.add_child(_make_label("存档名称", 14))
	_save_name_edit = LineEdit.new()
	_save_name_edit.name = "SaveNameEdit"
	_save_name_edit.placeholder_text = "例如 save_1"
	_save_name_edit.text = "save_1"
	column.add_child(_save_name_edit)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)

	var save_button := _make_button("保存", "ConfirmSaveButton")
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.pressed.connect(_on_confirm_save_pressed)
	buttons.add_child(save_button)

	var back_button := _make_button("返回", "CloseSaveButton")
	back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_button.pressed.connect(_on_close_save_pressed)
	buttons.add_child(back_button)

	_save_status_label = _make_label("", 14)
	_save_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_save_status_label.custom_minimum_size = Vector2(0.0, 40.0)
	column.add_child(_save_status_label)

	column.add_child(_make_label("已有存档", 14))
	_save_list = ItemList.new()
	_save_list.name = "SaveList"
	_save_list.custom_minimum_size = Vector2(0.0, 170.0)
	_save_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_save_list.item_selected.connect(_on_save_list_item_selected)
	column.add_child(_save_list)


func _connect_time_signals() -> void:
	if not TimeManager.world_speed_changed.is_connected(_on_world_speed_changed):
		TimeManager.world_speed_changed.connect(_on_world_speed_changed)
	if not TimeManager.world_time_changed.is_connected(_on_world_time_changed):
		TimeManager.world_time_changed.connect(_on_world_time_changed)


func _update_camera(delta: float) -> void:
	if not _is_input_blocked():
		var pan := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if pan != Vector2.ZERO:
			_camera_offset += pan * CAMERA_PAN_SPEED * delta / camera.zoom.x

	var desired := _player_party.world_position + _camera_offset
	var viewport_size := get_viewport_rect().size
	var half_view := viewport_size / (2.0 * camera.zoom.x)
	var world_size := _context.world_size

	if world_size.x > half_view.x * 2.0:
		desired.x = clampf(desired.x, half_view.x, world_size.x - half_view.x)
	else:
		desired.x = world_size.x * 0.5
	if world_size.y > half_view.y * 2.0:
		desired.y = clampf(desired.y, half_view.y, world_size.y - half_view.y)
	else:
		desired.y = world_size.y * 0.5

	var weight: float = 1.0 - exp(-CAMERA_FOLLOW_SPEED * delta)
	camera.position = camera.position.lerp(desired, weight)


func _set_camera_zoom(value: float) -> void:
	var zoom_value: float = clampf(value, CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX)
	camera.zoom = Vector2(zoom_value, zoom_value)


## 只由玩家主动点击地点调用；设置当前地点并打开面板。
func _open_settlement(settlement: SettlementData) -> void:
	_settlement_latch_id = settlement.settlement_id
	_player_party.focus_party_id = ""
	_context.world_map_manager.stop_party(_context.player_party_id)
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	TimeManager.push_pause(GameManager.PAUSE_REASON_UI_PANEL)
	_settlement_pause_active = true

	_settlement_name_label.text = settlement.display_name
	_settlement_type_label.text = _settlement_type_text(settlement.settlement_type)
	var is_village: bool = (
		settlement.settlement_type == SettlementData.SettlementType.VILLAGE
	)
	_settlement_enter_button.visible = is_village
	_settlement_enter_button.disabled = not is_village
	_settlement_panel.visible = true
	_set_time_buttons_enabled(false)
	_update_time_ui()


func _on_settlement_leave_pressed() -> void:
	_settlement_panel.visible = false
	if _settlement_pause_active:
		TimeManager.pop_pause(GameManager.PAUSE_REASON_UI_PANEL)
		_settlement_pause_active = false
	# 不恢复时间：离开地点后仍保持暂停，玩家需主动选择 1x / 2x。
	_set_time_buttons_enabled(true)
	_update_time_ui()


func _on_settlement_enter_pressed() -> void:
	if _settlement_latch_id.is_empty():
		return
	enter_village(_settlement_latch_id)


## 进入村庄小场景。只切换表现场景，不复制或修改玩家部队权威数据。
func enter_village(settlement_id: String) -> bool:
	if _context == null or _settlement_entry_pending:
		return false
	var settlement := _context.settlement_manager.get_settlement(settlement_id)
	if settlement == null \
			or settlement.settlement_type != SettlementData.SettlementType.VILLAGE:
		return false
	var scene_path: String = settlement.scene_path
	if scene_path.is_empty():
		scene_path = SceneManager.VILLAGE_SCENE
	if not ResourceLoader.exists(scene_path):
		push_error("村庄场景不存在: %s" % scene_path)
		return false

	_settlement_entry_pending = true
	GameManager.current_settlement_id = settlement_id
	GameManager.small_scene_return_base_speed = TimeManager.get_base_world_speed()

	# 先压入 small_scene 暂停，再释放地点面板暂停，保证切换期间世界不恢复运行。
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	TimeManager.push_pause(GameManager.PAUSE_REASON_SMALL_SCENE)
	_settlement_panel.visible = false
	if _settlement_pause_active:
		TimeManager.pop_pause(GameManager.PAUSE_REASON_UI_PANEL)
		_settlement_pause_active = false

	var error: Error = SceneManager.change_scene(scene_path)
	if error != OK:
		TimeManager.pop_pause(GameManager.PAUSE_REASON_SMALL_SCENE)
		TimeManager.push_pause(GameManager.PAUSE_REASON_UI_PANEL)
		_settlement_pause_active = true
		_settlement_panel.visible = true
		_settlement_entry_pending = false
		push_error("无法进入村庄场景（错误码 %s）" % error)
		return false

	_settlement_entry_pending = false
	EventBus.settlement_entered.emit(settlement_id, _context.player_party_id)
	return true


func _check_party_interaction() -> void:
	if _battle_transition_started or _context == null or _player_party == null:
		return
	if _save_panel.visible or _settlement_panel.visible or _party_panel.visible \
			or _party_manage_panel.visible or _encounter_panel.visible \
			or _battle_interaction_panel.visible:
		return

	if _party_latch_id.is_empty():
		# 只有玩家主动点击过的目标才允许自动打开普通部队对话。
		# 普通寻路或追击途中路过的中立/无关部队不再按距离强制弹窗。
		if not _is_focusing_party():
			return
		var focus := _context.party_manager.get_party(_player_party.focus_party_id)
		if focus == null or focus.party_id == _context.player_party_id:
			_player_party.focus_party_id = ""
			return
		if focus.member_unit_ids.is_empty() or not focus.is_available_for_world():
			_player_party.focus_party_id = ""
			return
		# 敌对目标由 EncounterManager 的主动遭遇流程处理，不在普通对话入口开战。
		if _context.faction_manager.is_hostile(
			_player_party.faction_id, focus.faction_id
		):
			return
		var closest := Geometry2D.get_closest_point_to_segment(
			focus.world_position, _last_player_position, _player_party.world_position
		)
		if closest.distance_to(focus.world_position) <= PARTY_INTERACTION_RADIUS:
			_open_party_dialogue(focus)
	else:
		var active := _context.party_manager.get_party(_party_latch_id)
		if active == null \
				or _player_party.world_position.distance_to(active.world_position) \
				> PARTY_INTERACTION_EXIT_RADIUS:
			_party_latch_id = ""


## 离屏战斗期间玩家接近战场时，按阵营关系自动加入并切换到战斗场景。
## 玩家接近进行中的离屏战斗交互面板。
func _on_player_battle_interaction_requested(
	interaction_id: String, battle_id: String
) -> void:
	if _context == null or _player_party == null or _battle_interaction_panel == null:
		if _context != null:
			_context.encounter_manager.clear_pending_battle_interaction()
		return
	if _battle_interaction_panel.visible:
		return
	var pending_interaction: Dictionary = (
		_context.encounter_manager.get_pending_battle_interaction()
	)
	if pending_interaction.is_empty() \
			or str(pending_interaction.get("interaction_id", "")) != interaction_id:
		return
	if _battle_transition_started or _encounter_panel.visible \
			or _save_panel.visible or _settlement_panel.visible \
			or _party_panel.visible or _party_manage_panel.visible:
		_context.encounter_manager.clear_pending_battle_interaction()
		return

	var battle := _context.battle_manager.current_battle
	if battle == null or battle.battle_id != battle_id or not battle.offscreen \
			or battle.is_party_involved(_context.player_party_id):
		_context.encounter_manager.clear_pending_battle_interaction()
		return
	if not _player_party.is_available_for_world() \
			or _player_party.member_unit_ids.is_empty():
		_context.encounter_manager.clear_pending_battle_interaction()
		return
	if _context.battle_manager.get_join_side(_context.player_party_id) < 0:
		_context.encounter_manager.clear_pending_battle_interaction()
		return

	_battle_interaction_id = interaction_id
	_battle_interaction_battle_id = battle_id
	_context.world_map_manager.stop_party(_context.player_party_id)
	_battle_interaction_summary_label.text = _battle_interaction_summary(battle)
	_battle_interaction_status_label.text = ""
	_battle_interaction_panel.visible = true

	if not _battle_interaction_pause_active:
		TimeManager.push_pause(GameManager.PAUSE_REASON_BATTLE_INTERACTION)
		_battle_interaction_pause_active = true
	_set_time_buttons_enabled(false)
	_update_time_ui()


func _on_battle_join_pressed() -> void:
	if _context == null or _player_party == null or _battle_interaction_panel == null:
		return
	if not _battle_interaction_panel.visible:
		return
	var pending: Dictionary = _context.encounter_manager.get_pending_battle_interaction()
	if pending.is_empty() \
			or str(pending.get("interaction_id", "")) != _battle_interaction_id:
		cancel_battle_interaction()
		return

	var battle_id: String = str(pending.get("battle_id", ""))
	var battle := _context.battle_manager.current_battle
	if battle == null or battle.battle_id != battle_id or not battle.offscreen \
			or battle.is_party_involved(_context.player_party_id):
		_battle_interaction_status_label.text = "战斗已经结束"
		cancel_battle_interaction()
		return
	if not _player_party.is_available_for_world() \
			or _player_party.member_unit_ids.is_empty():
		_battle_interaction_status_label.text = "玩家部队无法参战"
		cancel_battle_interaction()
		return

	_context.world_map_manager.stop_party(_context.player_party_id)
	# 先置位，避免其他流程在场景切换前重复触发。
	_battle_transition_started = true
	if not _context.battle_manager.try_join_battle(_context.player_party_id):
		_battle_transition_started = false
		_battle_interaction_status_label.text = "无法加入该战斗"
		return

	var error: Error = SceneManager.change_scene(SceneManager.BATTLE_SCENE)
	if error != OK:
		_context.battle_manager.abort_battle(battle_id)
		_battle_transition_started = false
		_battle_interaction_status_label.text = "战斗场景加载失败"
		cancel_battle_interaction()
		return

	_context.encounter_manager.clear_pending_battle_interaction()
	_battle_interaction_id = ""
	_battle_interaction_battle_id = ""
	_battle_interaction_panel.visible = false
	if _battle_interaction_pause_active:
		TimeManager.pop_pause(GameManager.PAUSE_REASON_BATTLE_INTERACTION)
		_battle_interaction_pause_active = false


func _on_battle_leave_pressed() -> void:
	if _context == null or _battle_interaction_panel == null:
		return
	if not _battle_interaction_panel.visible:
		return
	var pending: Dictionary = _context.encounter_manager.get_pending_battle_interaction()
	var battle_id: String = str(pending.get("battle_id", _battle_interaction_battle_id))

	_battle_interaction_panel.visible = false
	if _battle_interaction_pause_active:
		TimeManager.pop_pause(GameManager.PAUSE_REASON_BATTLE_INTERACTION)
		_battle_interaction_pause_active = false
	if not battle_id.is_empty():
		# 记录拒绝，避免玩家停留在交互范围内时反复弹出。
		_context.encounter_manager.decline_battle_interaction(battle_id)
	else:
		_context.encounter_manager.clear_pending_battle_interaction()
	_battle_interaction_id = ""
	_battle_interaction_battle_id = ""
	_set_time_buttons_enabled(true)
	_update_time_ui()


## 对话/战斗状态变化时关闭面板，清理本次交互暂停与待处理请求。
func cancel_battle_interaction() -> void:
	if _battle_interaction_panel != null:
		_battle_interaction_panel.visible = false
	if _battle_interaction_pause_active:
		TimeManager.pop_pause(GameManager.PAUSE_REASON_BATTLE_INTERACTION)
		_battle_interaction_pause_active = false
	if _context != null:
		_context.encounter_manager.clear_pending_battle_interaction()
	_battle_interaction_id = ""
	_battle_interaction_battle_id = ""
	_set_time_buttons_enabled(true)
	_update_time_ui()


## 面板打开期间检查战斗是否仍然有效；无效时关闭并清理暂停。
func _validate_battle_interaction() -> void:
	if _battle_interaction_panel == null or not _battle_interaction_panel.visible:
		return
	if _context == null:
		return
	var pending: Dictionary = _context.encounter_manager.get_pending_battle_interaction()
	if pending.is_empty():
		cancel_battle_interaction()
		return
	var battle := _context.battle_manager.current_battle
	if battle == null or battle.battle_id != str(pending.get("battle_id", "")) \
			or not battle.offscreen:
		cancel_battle_interaction()
		return
	if battle.is_party_involved(_context.player_party_id):
		cancel_battle_interaction()


func _battle_interaction_summary(battle: BattleSession) -> String:
	if battle == null:
		return "战斗信息不可用"
	var side_texts: Array[String] = []
	for side_index: int in battle.get_side_indices():
		var names: Array[String] = []
		for party_id: String in battle.get_side_party_ids(side_index):
			var party := _context.party_manager.get_party(party_id)
			if party != null:
				names.append(party.party_name)
		if names.is_empty():
			names.append("未知部队")
		side_texts.append("、".join(names))
	return "交战方：%s\n已持续：%.1f 秒" % [
		"  VS  ".join(side_texts), battle.elapsed_world_seconds
	]


func _on_battle_participants_updated(_battle_id: String) -> void:
	_update_battle_display()


func _on_battle_started(_battle_id: String) -> void:
	if _battle_transition_started or _context == null:
		return
	var battle := _context.battle_manager.current_battle
	if battle == null or battle.offscreen or not battle.player_involved:
		return
	_battle_transition_started = true
	call_deferred("_enter_battle_scene")


func _enter_battle_scene() -> void:
	var error: Error = SceneManager.change_scene(SceneManager.BATTLE_SCENE)
	if error == OK:
		return
	if _context != null and _context.battle_manager.current_battle != null:
		_context.battle_manager.abort_battle(_context.battle_manager.current_battle.battle_id)
	_battle_transition_started = false
	push_error("无法进入战斗场景（错误码 %s）" % error)


func _open_party_dialogue(party: PartyData) -> void:
	if _party_panel.visible or party == null:
		return
	if party.party_id == _context.player_party_id:
		return

	_party_latch_id = party.party_id
	_battle_transition_started = false
	_player_party.focus_party_id = ""
	_context.world_map_manager.stop_party(_context.player_party_id)

	if not _party_pause_active:
		TimeManager.push_pause(GameManager.PAUSE_REASON_UI_PANEL)
		_party_pause_active = true

	var leader := _party_leader(party)
	_party_name_label.text = _party_leader_name(party, leader)
	_party_faction_label.text = "阵营：%s" % _faction_display_name(party.faction_id)
	_party_troop_label.text = "兵力：%d" % party.member_unit_ids.size()
	_party_dialogue_label.text = _encounter_dialogue_text(
		EncounterManager.EncounterReason.PLAYER_INITIATED, party
	)
	if _party_portrait != null:
		_party_portrait.show_leader(leader)
	_party_status_label.text = ""
	var active_battle := _context.battle_manager.current_battle
	# 已有战斗时：点击参战方且玩家可加入 → 改为“加入战斗”；
	# 其余情况不允许另开战场，并在面板内说明真实原因。
	var can_join_active: bool = active_battle != null \
		and active_battle.is_party_involved(party.party_id) \
		and _context.battle_manager.can_party_join(_context.player_party_id)
	# 加入友军正在进行的战斗是协战，不算“同阵营开战”。
	var same_faction: bool = party.faction_id == _player_party.faction_id \
		and not can_join_active
	var battle_block: String = ""
	if active_battle != null and not can_join_active:
		battle_block = _active_battle_block_reason(party)
	var unavailable_reason: String = ""
	if not can_join_active:
		unavailable_reason = _party_unavailable_reason(party)
	if not _player_party.is_available_for_world():
		unavailable_reason = "玩家部队当前无法参战"

	_party_fight_button.text = "加入战斗" if can_join_active else "发起战斗"
	_party_fight_button.disabled = (
		same_faction
		or party.member_unit_ids.is_empty()
		or _player_party.member_unit_ids.is_empty()
		or not battle_block.is_empty()
		or not unavailable_reason.is_empty()
	)
	if same_faction:
		_party_status_label.text = "同一阵营无法开战"
	elif not battle_block.is_empty():
		_party_status_label.text = battle_block
	elif not unavailable_reason.is_empty():
		_party_status_label.text = unavailable_reason
	elif _party_fight_button.disabled:
		_party_status_label.text = "双方都需要至少一名士兵才能开战"

	_party_panel.visible = true
	_set_time_buttons_enabled(false)
	_update_time_ui()


func _on_party_leave_pressed() -> void:
	_close_party_dialogue()
	_set_time_buttons_enabled(true)
	_update_time_ui()


func _close_party_dialogue() -> void:
	_party_panel.visible = false
	if _party_portrait != null:
		_party_portrait.clear()
	if _party_pause_active:
		TimeManager.pop_pause(GameManager.PAUSE_REASON_UI_PANEL)
		_party_pause_active = false


## 当前已有战斗时，返回禁止另开战场的说明；空字符串表示可以正常开始/加入。
## BattleManager 全局只允许一场战斗，离屏 NPC 战斗同样会占用该槽位。
func _active_battle_block_reason(enemy: PartyData) -> String:
	var battle := _context.battle_manager.current_battle if _context != null else null
	if battle == null:
		return ""
	if enemy == null or not battle.is_party_involved(enemy.party_id):
		return "世界上已有另一场战斗正在进行，暂时无法另开战场"
	if _context.battle_manager.get_join_side(_context.player_party_id) < 0:
		return "对方正在战斗中，暂时无法开战"
	return "对方正在战斗中，靠近战场后可加入战斗"


## 目标部队当前是否无法作为新的独立战斗对手；返回空字符串表示可用。
func _party_unavailable_reason(party: PartyData) -> String:
	if party == null:
		return "对方已经离开"
	match party.battle_state:
		PartyData.BattleState.DISABLED:
			return "该部队已无法参战"
		PartyData.BattleState.IN_BATTLE:
			return "对方正在战斗中"
		PartyData.BattleState.RETURNING:
			return "对方正在返回途中"
		_:
			return ""


## 加入当前战斗；成功后由调用方切换到战斗场景。
func _join_active_battle(battle: BattleSession) -> BattleSession:
	if battle == null or _context == null or _player_party == null:
		return null
	_context.world_map_manager.stop_party(_context.player_party_id)
	_battle_transition_started = true
	if not _context.battle_manager.try_join_battle(_context.player_party_id):
		_battle_transition_started = false
		_party_status_label.text = "无法加入该战斗"
		return null
	# try_join_battle 已压入战斗暂停；随后再释放对话暂停，避免中间帧恢复世界时间。
	if _party_pause_active:
		TimeManager.pop_pause(GameManager.PAUSE_REASON_UI_PANEL)
		_party_pause_active = false
	_party_panel.visible = false
	return _context.battle_manager.current_battle


## 只创建/加入战斗会话并锁定部队，不切换场景；供 UI 与自动化测试共用。
func begin_battle_with_party() -> BattleSession:
	if _battle_transition_started or _context == null or _player_party == null:
		return null
	var enemy := _context.party_manager.get_party(_party_latch_id)
	if enemy == null or enemy.party_id == _context.player_party_id:
		return null
	if not _player_party.is_available_for_world() \
			or _player_party.member_unit_ids.is_empty():
		_party_status_label.text = "玩家部队当前无法参战"
		return null

	# 全局已有战斗：参战方允许加入；其它情况明确拒绝并说明原因。
	# 加入友军战斗属于协战，因此先于“同阵营”检查。
	var active_battle := _context.battle_manager.current_battle
	var can_join_active: bool = active_battle != null \
		and active_battle.is_party_involved(enemy.party_id) \
		and _context.battle_manager.can_party_join(_context.player_party_id)
	if enemy.faction_id == _player_party.faction_id and not can_join_active:
		_party_status_label.text = "同一阵营无法开战"
		return null
	if active_battle != null:
		if can_join_active:
			return _join_active_battle(active_battle)
		_party_status_label.text = _active_battle_block_reason(enemy)
		return null

	var unavailable_reason := _party_unavailable_reason(enemy)
	if not unavailable_reason.is_empty():
		_party_status_label.text = unavailable_reason
		return null
	if enemy.member_unit_ids.is_empty():
		_party_status_label.text = "双方都需要至少一名士兵才能开战"
		return null

	var attacker_ids: Array[String] = [_context.player_party_id]
	var defender_ids: Array[String] = [enemy.party_id]
	# 先置位，避免 battle_started 信号再次触发场景切换。
	_battle_transition_started = true
	var session := _context.battle_manager.start_battle(
		attacker_ids, defender_ids, enemy.world_position
	)
	if session == null:
		_battle_transition_started = false
		_party_status_label.text = "无法开始战斗"
		return null

	# 先由 start_battle 压入战斗暂停，再释放对话暂停，避免中间帧恢复世界时间。
	if _party_pause_active:
		TimeManager.pop_pause(GameManager.PAUSE_REASON_UI_PANEL)
		_party_pause_active = false
	_party_panel.visible = false
	return session


func _on_party_fight_pressed() -> void:
	var session := begin_battle_with_party()
	if session == null:
		return

	var error: Error = SceneManager.change_scene(SceneManager.BATTLE_SCENE)
	if error != OK:
		_context.battle_manager.finish_battle(
			session.battle_id, BattleSession.BattleResult.ABORTED
		)
		_battle_transition_started = false
		TimeManager.push_pause(GameManager.PAUSE_REASON_UI_PANEL)
		_party_pause_active = true
		_party_panel.visible = true
		_party_status_label.text = "战斗场景加载失败"
		_set_time_buttons_enabled(false)
		_update_time_ui()


func _set_world_speed(speed: float) -> void:
	TimeManager.set_base_world_speed(speed)
	_update_time_ui()


func _on_pause_pressed() -> void:
	_set_world_speed(TimeManager.SPEED_PAUSED)


func _on_speed_one_pressed() -> void:
	_set_world_speed(TimeManager.SPEED_NORMAL)


func _on_speed_two_pressed() -> void:
	_set_world_speed(TimeManager.SPEED_DOUBLE)


func _on_save_pressed() -> void:
	if _settlement_panel.visible:
		return
	_save_panel.visible = true
	_save_dim.visible = true
	TimeManager.push_pause(GameManager.PAUSE_REASON_UI_PANEL)
	_save_pause_active = true
	_set_time_buttons_enabled(false)
	_save_status_label.text = ""
	_save_name_edit.text = _default_slot_name()
	_refresh_save_list()
	_update_time_ui()


func _on_close_save_pressed() -> void:
	_save_panel.visible = false
	_save_dim.visible = false
	if _save_pause_active:
		TimeManager.pop_pause(GameManager.PAUSE_REASON_UI_PANEL)
		_save_pause_active = false
	_set_time_buttons_enabled(true)
	_update_time_ui()


func _on_confirm_save_pressed() -> void:
	var slot_name := _save_name_edit.text.strip_edges()
	if slot_name.is_empty():
		_save_status_label.text = "请输入存档名称"
		return

	var error: Error = GameManager.save_game(slot_name)
	if error == OK:
		_save_status_label.text = "保存成功：%s" % slot_name
		_refresh_save_list()
	else:
		_save_status_label.text = "保存失败（错误码 %s）" % error


func _on_save_list_item_selected(index: int) -> void:
	var slot_name: Variant = _save_list.get_item_metadata(index)
	if slot_name is String:
		_save_name_edit.text = slot_name


func _refresh_save_list() -> void:
	_save_list.clear()
	for info: Dictionary in SaveManager.list_save_infos():
		if not bool(info.get("valid", false)):
			continue
		var saved_at := str(info.get("saved_at", "未知时间")).replace("T", " ")
		var index: int = _save_list.add_item("%s    %s" % [str(info.get("slot", "")), saved_at])
		_save_list.set_item_metadata(index, str(info.get("slot", "")))


func _on_main_menu_pressed() -> void:
	GameManager.enter_main_menu()


func _on_world_speed_changed(_effective_scale: float) -> void:
	_update_time_ui()


func _on_world_time_changed(_total_seconds: float) -> void:
	_update_time_ui()


func _update_time_ui() -> void:
	if _world_time_label == null:
		return
	var effective := TimeManager.get_effective_world_scale()
	var speed_text := "暂停"
	if is_equal_approx(effective, TimeManager.SPEED_NORMAL):
		speed_text = "1x"
	elif is_equal_approx(effective, TimeManager.SPEED_DOUBLE):
		speed_text = "2x"

	_world_time_label.text = "世界时间：%s    倍率：%s" % [
		TimeManager.get_world_time_text(), speed_text
	]

	if _pause_button != null:
		_pause_button.button_pressed = is_zero_approx(effective)
		_speed_one_button.button_pressed = is_equal_approx(effective, TimeManager.SPEED_NORMAL)
		_speed_two_button.button_pressed = is_equal_approx(effective, TimeManager.SPEED_DOUBLE)


func _update_player_info() -> void:
	if _player_info_label == null or _player_party == null:
		return
	var state_text: String = "待命"
	if _player_party.current_order == PartyData.OrderType.FOLLOW_PARTY:
		var target := _context.party_manager.get_party(_player_party.current_target_id)
		state_text = "跟随中：%s" % (target.party_name if target != null else "目标消失")
	elif _player_party.movement_state == PartyData.MovementState.MOVING:
		state_text = "移动中"
	_player_info_label.text = "%s    坐标 (%d, %d)    状态：%s" % [
		_player_party.party_name,
		int(round(_player_party.world_position.x)),
		int(round(_player_party.world_position.y)),
		state_text,
	]


func _set_time_buttons_enabled(enabled: bool) -> void:
	for button: Button in _time_buttons:
		button.disabled = not enabled


func _is_input_blocked() -> bool:
	return _save_panel != null and (
		_save_panel.visible
		or _settlement_panel.visible
		or _party_panel.visible
		or (_party_manage_panel != null and _party_manage_panel.visible)
		or (_encounter_panel != null and _encounter_panel.visible)
		or (_battle_interaction_panel != null and _battle_interaction_panel.visible)
	)


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


func _make_button(text: String, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(64.0, 30.0)
	button.focus_mode = Control.FOCUS_NONE
	return button


func _settlement_type_text(type: SettlementData.SettlementType) -> String:
	match type:
		SettlementData.SettlementType.CASTLE:
			return "城堡"
		SettlementData.SettlementType.TOWN:
			return "城镇"
		_:
			return "村庄"


func _faction_display_name(faction_id: String) -> String:
	if _context != null:
		return _context.faction_manager.get_display_name(faction_id)
	return faction_id if not faction_id.is_empty() else "未知"


func _default_slot_name() -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	return "save_%s" % stamp


func _return_to_main_menu() -> void:
	GameManager.enter_main_menu()
