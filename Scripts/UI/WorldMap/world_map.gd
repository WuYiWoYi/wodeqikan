extends Node2D
## 大地图场景控制器。
##
## 只读取 WorldContext 的权威数据并生成表现节点；
## 移动、时间、存档操作全部通过管理器/GameManager 接口完成。

const TextureRegion = preload("res://Scripts/Core/World/texture_region_utils.gd")
const MoveTargetGuideScript = preload("res://Scripts/Systems/WorldMap/move_target_guide.gd")
const EventCenterPanelScript = preload("res://Scripts/UI/WorldMap/event_center_panel.gd")
const FamilyPanelScript = preload("res://Scripts/UI/WorldMap/family_panel.gd")
const EventFeedScript = preload("res://Scripts/UI/WorldMap/event_feed.gd")
const EventDetailDialogScript = preload("res://Scripts/UI/WorldMap/event_detail_dialog.gd")
const EventReminderScript = preload("res://Scripts/UI/WorldMap/event_reminder.gd")
const DayNightClockScript = preload("res://Scripts/UI/WorldMap/day_night_clock.gd")
const MapOverlayRegistryScript = preload("res://Scripts/UI/WorldMap/map_overlay_registry.gd")
const MapUiKitScript = preload("res://Scripts/UI/WorldMap/map_ui_kit.gd")
const WorldMapSavePanelScript = preload(
	"res://Scripts/UI/WorldMap/world_map_save_panel.gd"
)
const WorldMapEncyclopediaScript = preload(
	"res://Scripts/UI/WorldMap/world_map_encyclopedia.gd"
)

const PARTY_INTERACTION_RADIUS: float = 40.0
const PARTY_INTERACTION_EXIT_RADIUS: float = 64.0
## 点击部队图标的判定半径（世界像素）。
const PARTY_CLICK_RADIUS: float = 26.0
## 点击地点的判定半径（世界像素）；点击只设置前往目标，不代表已经抵达。
const SETTLEMENT_CLICK_RADIUS: float = 45.0
## 玩家部队到达地点、允许打开面板的交互半径（世界像素）。
const SETTLEMENT_INTERACTION_RADIUS: float = 40.0
## 鼠标悬浮部队图标的判定半径；略大于点击半径便于触发。
const PARTY_HOVER_RADIUS: float = 30.0
const HOVER_PANEL_WIDTH: float = 320.0
const HOVER_PANEL_LINE_HEIGHT: float = 22.0
const BATTLE_SUMMARY_WIDTH: float = 360.0
## 每个战斗侧一列；出现第三侧时面板横向扩展。
const BATTLE_SUMMARY_COLUMN_WIDTH: float = 168.0
const BATTLE_SUMMARY_COLUMN_GAP: int = 14
## 鼠标与战斗标记中心的悬浮判定半径（世界像素）；与标记视觉半径解耦。
const BATTLE_MARKER_HOVER_RADIUS: float = 34.0
const BATTLE_SUMMARY_SEPARATOR: String = "────────────"
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
## 部队与建筑的实际距离小于该值时视为“停留在地点上”。
## 只比较当前位置，不读取移动目标；移动中的部队不算停留。
const STATIONED_PARTY_RADIUS: float = 26.0
## 停留部队旗帜条与建筑美术之间的屏幕间距。
const STATIONED_BAR_GAP: float = 8.0

## 地图单击/双击判定窗口与位置容差；双击只下达一次移动指令并直接切 2 倍速。
const MAP_CLICK_DOUBLE_WINDOW: float = 0.28
const MAP_CLICK_DOUBLE_DISTANCE: float = 18.0

## 顶栏金币/移速/部队人数使用同一套图标 + 数值表现。
const TOP_INFO_ICON_GOLD_PATH: String = \
	"res://art/我的骑砍临时美术/正式美术_其他/UI美术/UI_金币.png"
const TOP_INFO_ICON_SPEED_PATH: String = \
	"res://art/我的骑砍临时美术/正式美术_其他/UI美术/UI_移速.png"
const TOP_INFO_ICON_TROOP_PATH: String = \
	"res://art/我的骑砍临时美术/正式美术_其他/UI美术/UI_人数.png"
## 金币/移速/人数图标统一放大到 2 倍（20→40）；文本字号与数值不变。
const TOP_INFO_ICON_SIZE := Vector2(40.0, 40.0)
const TOP_INFO_ICON_TEXT_GAP: int = 6
## 顶栏正中的昼夜窗口边长；取顶栏内容高度（48 - 上下 6 边距）以保持正方形。
const TOP_BAR_CLOCK_SIZE: float = 36.0
## 昼夜窗口与世界时间文本之间的间距。
const TOP_BAR_CLOCK_TEXT_GAP: float = 6.0

## 大地图镜头模式：默认平滑跟随玩家；按 WASD 后自由移动，直到玩家重新下达移动/跟随指令。
enum CameraMode {
	FOLLOW_PLAYER,
	FREE_CAMERA,
}

@onready var map_background: MapBackground = $MapBackground
@onready var world_entities: Node2D = $WorldEntities
@onready var camera: Camera2D = $Camera2D

var _context: WorldContext = null
var _player_party: PartyData = null
var _player_icon: PartyIcon = null
## 移动目标点标记与动态虚线；只表现 PartyData.target_position，不参与移动结算。
var _move_target_guide: MoveTargetGuideScript = null
var _camera_mode: CameraMode = CameraMode.FOLLOW_PLAYER
var _last_player_position := Vector2.ZERO
var _settlement_latch_id: String = ""
## 玩家主动点击、正在前往的地点；仅大地图运行时状态，不进入存档。
var _pending_settlement_interaction_id: String = ""
## 地图左键双击判定：第一次点击先等待窗口结束，再按单击执行。
var _pending_map_click_timer: float = -1.0
var _pending_map_click_position: Vector2 = Vector2.ZERO

var _ui_root: Control = null
## 覆盖层可见性与暂停登记；面板显隐仍由各自控制。
var _overlays = MapOverlayRegistryScript.new()
var _world_time_label: Label = null
## 顶栏正中的昼夜窗口；位置只由 TimeManager 的世界累计时间换算。
var _day_night_clock = null
## 世界时间为 0（基础暂停或任意 UI 暂停）时显示的琥珀色提示。
var _pause_tip_label: Label = null
var _money_label: Label = null
var _party_speed_label: Label = null
## 顶栏部队人数；与底部部队对话面板的 `_party_troop_label` 相互独立。
var _top_party_troop_label: Label = null
var _player_info_label: Label = null
var _pause_button: Button = null
var _speed_one_button: Button = null
var _speed_two_button: Button = null
var _time_buttons: Array[Button] = []

## 顶部信息栏的自定义悬浮提示；Alt 按住时展示完整构成。
var _top_info_tooltip: PanelContainer = null
var _top_info_content: VBoxContainer = null
var _top_info_hover_kind: String = ""
var _top_info_signature: String = ""

## 主界面事件中心：只读聚合任务/待处理事项。
var _event_center_panel = null
## 家族面板：只读展示玩家家族贵族与封地，不建立独立政治数据。
var _family_panel = null

## 右侧可操作事件框与详情弹窗；只展示 EventCenter 当前有效事件。
var _event_feed = null
## 右侧小型待处理提醒；只反映事件中心当前可操作事件数量。
var _event_reminder = null
var _event_detail_dialog = null
## 独立出售俘虏覆盖层；复用 TavernPanel 的出售逻辑，不嵌套在城镇面板中。
var _prisoner_sale_panel = null

var _settlement_panel: PanelContainer = null
## 地点面板内部的两种内容视图：城镇信息与酒馆内容在同一窗口内切换。
var _settlement_info_view: VBoxContainer = null
var _settlement_tavern_host: Control = null
var _settlement_name_label: Label = null
var _settlement_type_label: Label = null
var _settlement_owner_label: Label = null
var _settlement_family_label: Label = null
var _settlement_population_label: Label = null
var _settlement_prosperity_label: Label = null
var _settlement_tax_label: Label = null
var _settlement_fief_label: Label = null
var _settlement_recruit_button: Button = null
var _settlement_recruit_status_label: Label = null
var _settlement_enter_button: Button = null
var _settlement_market_button: Button = null
var _settlement_tavern_button: Button = null
var _settlement_entry_pending: bool = false

var _party_panel: PanelContainer = null
var _party_name_label: Label = null
var _party_faction_label: Label = null
var _party_troop_label: Label = null
var _party_status_label: Label = null
var _party_fight_button: Button = null
var _party_latch_id: String = ""
## 当前对话的“发起战斗”实际会加入已有友军战斗，而不是主动攻击。
var _party_fight_joins_battle: bool = false
var _battle_transition_started: bool = false

## 玩家主动攻击前的二次确认；取消不产生任何战斗副作用。
var _attack_confirm_panel: PanelContainer = null
var _attack_confirm_label: Label = null
var _attack_confirm_target_id: String = ""
var _attack_confirm_in_progress: bool = false

var _party_manage_panel: PartyPanel = null

## 玩家背包（只读）与城镇交易市场；都由大地图统一管理暂停原因。
var _inventory_panel: InventoryPanel = null
var _market_panel: MarketPanel = null
## 阶段 13：城镇酒馆二级界面。
var _tavern_panel: TavernPanel = null
## 独立的雇佣兵招募界面（酒馆入口发起意图后由大地图打开）。
var _mercenary_recruit_panel: MercenaryRecruitPanel = null
## 玩家被俘状态栏与顶栏生命值；只读取 CaptivityManager 与真实 UnitData。
var _captive_panel: PanelContainer = null
var _captive_title_label: Label = null
var _captive_captor_label: Label = null
var _captive_hp_label: Label = null
var _player_hp_label: Label = null

var _encounter_panel: PanelContainer = null
var _encounter_portrait: EncounterPortrait = null
var _encounter_name_label: Label = null
var _encounter_faction_label: Label = null
var _encounter_troop_label: Label = null
var _encounter_description_label: Label = null
var _encounter_status_label: Label = null
var _encounter_fight_button: Button = null
var _encounter_leave_button: Button = null
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
var _battle_interaction_id: String = ""
var _battle_interaction_battle_id: String = ""

var _hover_panel: PanelContainer = null
var _hover_content: VBoxContainer = null
var _hover_party_id: String = ""
var _hover_signature: String = ""
## 按住左 Alt 时悬浮面板显示详细构成；默认只显示部队名称。
var _alt_detail_active: bool = false

## 同一场战斗只显示一个标记；参战部队图标暂时隐藏。
var _party_icons: Dictionary = {}
## 地点图标：{ settlement_id: SettlementIcon }，供悬浮描边统一切换。
var _settlement_icons: Dictionary = {}
## 当前悬浮描边目标；同一时刻最多一个部队或一个建筑。
var _hover_outline_party_id: String = ""
var _hover_outline_settlement_id: String = ""
## 部队圆形标记样式；缺失资源时使用脚本默认值。
var _party_marker_style: PartyMarkerStyle = null
## 固定屏幕层的地点名称标签：{ settlement_id: SettlementNameTag }。
var _settlement_name_layer: Control = null
var _settlement_name_tags: Dictionary = {}
## 地点下方的停留部队旗帜条：{ settlement_id: SettlementStationedBar }。
var _stationed_bars: Dictionary = {}
## 本帧停留在建筑上的部队：{ party_id: settlement_id }。用于隐藏普通圆形图标。
var _stationed_party_ids: Dictionary = {}
## 每场战斗独立的标记：{ battle_id: BattleMarker }。
var _battle_markers: Dictionary = {}
var _battle_summary_panel: PanelContainer = null
var _battle_summary_title: Label = null
var _battle_summary_content: HBoxContainer = null
var _battle_summary_text: String = ""
var _battle_summary_signature: String = ""
## 当前鼠标悬浮的战斗；只有悬浮时才显示该场战斗信息面板。
var _hovered_battle_id: String = ""
## 测试是否允许由真实鼠标位置自动触发战斗悬浮；生产环境保持 true。
var _battle_mouse_hover_enabled: bool = true

## 固定在大地图左下角的世界日志面板；与村庄共用同一组件。
var _world_log_panel: WorldLogPanel = null

## 存档覆盖层：面板显隐与槽位列表由组件负责，写盘仍走 GameManager。
var _save_panel = null

## 百科覆盖层：只读取政治管理器，不复制静态数据。
var _encyclopedia_panel = null


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
	# 布局定义与地形由 WorldContext 统一装载；旧存档尺寸不匹配时背景层
	# 会自动回退到旧草地绘制，地点坐标仍按存档恢复。
	map_background.set_map_definition(
		_context.world_map_definition, _context.world_terrain
	)
	_context.world_map_manager.world_bounds = Rect2(Vector2.ZERO, _context.world_size)

	# 从小场景返回时记录当前站在村口的村庄，供地点面板的进入按钮使用；
	# 地点面板不再因为玩家靠近而自动打开，只有主动点击才会显示。
	_settlement_latch_id = GameManager.pending_settlement_latch_id
	GameManager.pending_settlement_latch_id = ""

	_build_ui()
	_register_overlays()
	_build_world_entities()
	_build_move_target_guide()
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
	if not EventBus.fief_recruited.is_connected(_on_fief_recruited):
		EventBus.fief_recruited.connect(_on_fief_recruited)
	if not EventBus.adventurers_recruited.is_connected(_on_adventurers_recruited):
		EventBus.adventurers_recruited.connect(_on_adventurers_recruited)
	if not EventBus.npc_supply_purchased.is_connected(_on_npc_supply_purchased):
		EventBus.npc_supply_purchased.connect(_on_npc_supply_purchased)
	if not EventBus.faction_relations_changed.is_connected(_on_faction_relations_changed):
		EventBus.faction_relations_changed.connect(_on_faction_relations_changed)
	if not EventBus.party_arrived.is_connected(_on_party_arrived):
		EventBus.party_arrived.connect(_on_party_arrived)

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
	# 离开大地图时取消未完成的地点交互，避免返回后误弹面板。
	_pending_settlement_interaction_id = ""
	# 场景异常退出时清理本次交互暂停，避免世界永久暂停。
	_overlays.release_all()
	if _context != null:
		_context.encounter_manager.clear_pending_player_encounter()
		_context.encounter_manager.clear_pending_battle_interaction()
		_context.encounter_manager.clear_battle_interaction_latch()


func _process(delta: float) -> void:
	if _player_party == null:
		return

	_update_pending_map_click(delta)
	_update_camera(delta)
	_update_move_target_guide()
	_update_settlement_name_tags()
	# 先计算停留部队，再更新战斗/图标显示，保证同一支部队不会同时出现在两处。
	_update_stationed_parties()
	_update_player_info()
	_update_top_info()
	_update_captive_ui()
	_update_battle_display()
	_update_focus_state()
	_validate_battle_interaction()
	_check_pending_settlement_interaction()
	_check_party_interaction()
	_update_party_hover()
	_update_hover_outline()
	_refresh_encyclopedia_if_needed()
	_refresh_event_center_if_needed()
	_refresh_family_panel_if_needed()
	_refresh_event_feed_if_needed()
	_last_player_position = _player_party.world_position


## 集中处理左 Alt 的按住/松开，不标记事件已处理，不影响点击与快捷键。
func _input(event: InputEvent) -> void:
	# 日志展开后，点击其矩形之外的任何位置都恢复折叠；不消费事件，
	# 因此其他 UI/地图仍按原样处理本次点击。
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT \
				and _world_log_panel != null \
				and _world_log_panel.is_collapsible() \
				and _world_log_panel.is_expanded() \
				and not _world_log_panel.get_global_rect().has_point(
					mouse_event.position
				):
			_world_log_panel.collapse()
		return
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if key_event.keycode != KEY_ALT and key_event.physical_keycode != KEY_ALT:
		return
	# 只响应左 Alt；右 Alt（含 AltGr）不切换详细模式。
	if key_event.location == KEY_LOCATION_RIGHT:
		return
	if key_event.pressed:
		if not key_event.echo:
			set_alt_detail_active(true)
	else:
		set_alt_detail_active(false)


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
			# 折叠日志只显示事件文本；点击文本区域展开完整面板，且不触发地图移动。
			if _world_log_panel != null and _world_log_panel.is_collapsed() \
					and _world_log_panel.get_collapsed_interaction_rect().has_point(
						mouse_event.position
					):
				_world_log_panel.expand()
				get_viewport().set_input_as_handled()
				return
			_queue_map_click(get_global_mouse_position())
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


## 鼠标左键输入入口：第一次点击延迟到双击窗口结束后按单击执行；
## 窗口内同位置再次点击视为双击，只下达一次移动并直接切 2 倍速。
func _queue_map_click(world_position: Vector2) -> void:
	if _pending_map_click_timer > 0.0:
		if _pending_map_click_position.distance_to(world_position) \
				<= MAP_CLICK_DOUBLE_DISTANCE:
			_pending_map_click_timer = -1.0
			_execute_map_click(world_position, TimeManager.SPEED_DOUBLE)
			return
		# 第二次点击位置不同：先补发第一次单击，再开始新的判定窗口。
		var first_position := _pending_map_click_position
		_pending_map_click_timer = -1.0
		_execute_map_click(first_position, TimeManager.SPEED_NORMAL)
	_pending_map_click_position = world_position
	_pending_map_click_timer = MAP_CLICK_DOUBLE_WINDOW


func _execute_map_click(world_position: Vector2, speed: float) -> void:
	handle_left_click(world_position, speed)


## 双击窗口结束时才把第一次点击按单击执行；期间打开面板则直接丢弃。
func _update_pending_map_click(delta: float) -> void:
	if _pending_map_click_timer < 0.0:
		return
	_pending_map_click_timer -= delta
	if _pending_map_click_timer >= 0.0:
		return
	var click_position := _pending_map_click_position
	_pending_map_click_timer = -1.0
	if _is_input_blocked() or _battle_transition_started:
		return
	_execute_map_click(click_position, TimeManager.SPEED_NORMAL)


## 鼠标左键统一入口：点击地点表示“前往该地点”，到达后才打开面板。
## 地点面板不会由普通移动、追逐或路径经过自动打开。
## speed_override < 0 时保持旧行为（移动成功切 1x），供测试直接调用。
func handle_left_click(
	world_position: Vector2, speed_override: float = -1.0
) -> bool:
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
			if _request_settlement_interaction(
				clicked_settlement, speed_override
			):
				return true

	if clicked_party != null \
			and clicked_party.party_id != _context.player_party_id \
			and request_party_command(clicked_party.party_id, speed_override):
		return true
	return request_player_move(world_position, speed_override)


## 点击地点：已在交互半径内则直接打开；否则记录待交互地点并开始移动。
## 移动途中绝不打开面板或压入 ui_panel 暂停。
func _request_settlement_interaction(
	settlement: SettlementData, speed_override: float = -1.0
) -> bool:
	if _context == null or _player_party == null or settlement == null:
		return false
	if _battle_transition_started or _is_input_blocked():
		return false
	var target := _context.settlement_manager.get_settlement(settlement.settlement_id)
	if target == null:
		return false

	var distance: float = _player_party.world_position.distance_to(
		target.world_position
	)
	if distance <= SETTLEMENT_INTERACTION_RADIUS:
		_pending_settlement_interaction_id = ""
		_open_settlement(target)
		return true

	if not _player_party.is_available_for_world():
		return false
	# 点击另一个地点时直接替换待交互目标，不留下空档状态。
	_pending_settlement_interaction_id = ""
	if not request_player_move(target.world_position, speed_override):
		return false
	_pending_settlement_interaction_id = target.settlement_id
	return true


## 地图点击速度：未指定时保持旧的单机 1x 行为；双击显式传 2x。
func _resolve_click_speed(speed_override: float) -> float:
	if is_equal_approx(speed_override, TimeManager.SPEED_PAUSED) \
			or is_equal_approx(speed_override, TimeManager.SPEED_NORMAL) \
			or is_equal_approx(speed_override, TimeManager.SPEED_DOUBLE):
		return speed_override
	return TimeManager.SPEED_NORMAL


## 设置玩家移动目标；成功时把基础倍率切回 1x。
## 只改基础倍率，不清除任何暂停原因；失败时完全不改变时间状态。
func request_player_move(
	target: Vector2, speed_override: float = -1.0
) -> bool:
	if _context == null or _player_party == null \
			or _battle_transition_started or _is_input_blocked():
		return false
	if not Rect2(Vector2.ZERO, _context.world_size).has_point(target):
		return false
	if not _context.world_map_manager.set_party_target(_context.player_party_id, target):
		return false

	# 普通地图移动取消“主动追逐”语义与旧的地点待交互状态。
	_player_party.focus_party_id = ""
	_pending_settlement_interaction_id = ""
	# 玩家重新下达地图移动指令后，镜头恢复跟随玩家部队。
	_camera_mode = CameraMode.FOLLOW_PLAYER
	_set_world_speed(_resolve_click_speed(speed_override))
	return true


## 让玩家部队持续跟随目标部队；失败时不改变当前指令。
func request_player_follow(
	target_party_id: String, speed_override: float = -1.0
) -> bool:
	if _context == null or _player_party == null \
			or _battle_transition_started or _is_input_blocked():
		return false
	if not _context.world_map_manager.set_party_follow(
		_context.player_party_id, target_party_id
	):
		return false

	_player_party.focus_party_id = target_party_id
	_pending_settlement_interaction_id = ""
	# 点击部队开始跟随时同样退出自由镜头，重新跟随玩家部队。
	_camera_mode = CameraMode.FOLLOW_PLAYER
	_set_world_speed(_resolve_click_speed(speed_override))
	return true


## 点击部队时：有效部队一律进入主动跟随。
## 静止部队也可能在玩家接近途中开始巡逻，只记录当前位置会让追击丢失目标；
## 跟随同时覆盖远距离点击（目标不在视野内）的情况。
func request_party_command(
	target_party_id: String, speed_override: float = -1.0
) -> bool:
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
	if can_follow and request_player_follow(target_party_id, speed_override):
		return true
	if request_player_move(target.world_position, speed_override):
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
			or focus.member_unit_ids.is_empty():
		_player_party.focus_party_id = ""
		return
	# 目标正在离屏战斗中：保留焦点并等待战斗结束，不能把追击关系清掉。
	if not focus.is_available_for_world():
		if focus.battle_state == PartyData.BattleState.IN_BATTLE:
			return
		_player_party.focus_party_id = ""
		return
	if _battle_transition_started:
		_player_party.focus_party_id = ""
		return
	# 移动停止后不要立刻清除焦点：主动点击部队后会在到达/靠近时据此打开对话。
	# 交互距离与统一遭遇半径保持一致，避免停在 45 像素时焦点被提前清除。
	if _player_party.movement_state != PartyData.MovementState.MOVING \
			and _player_party.world_position.distance_to(focus.world_position) \
			> EncounterManager.AI_ENCOUNTER_RADIUS + 4.0:
		_player_party.focus_party_id = ""


func _is_focusing_party() -> bool:
	return _player_party != null and not _player_party.focus_party_id.is_empty()


func _find_party_at(world_position: Vector2) -> PartyData:
	var party := _find_party_within(world_position, PARTY_CLICK_RADIUS)
	# 停留部队的圆形图标已隐藏，点击时让位给建筑本身。
	if party != null and _stationed_party_ids.has(party.party_id):
		return null
	return party


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
	_settlement_icons.clear()
	_hover_outline_party_id = ""
	_hover_outline_settlement_id = ""

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
	_refresh_party_relations()

	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		var settlement_icon: SettlementIcon = SettlementIcon.new()
		settlement_icon.name = "SettlementIcon_%s" % settlement.settlement_id
		world_entities.add_child(settlement_icon)
		# 世界层只绘制地点原有美术；家族徽章属于屏幕名称组合。
		settlement_icon.setup(settlement)
		_settlement_icons[settlement.settlement_id] = settlement_icon

	world_entities.y_sort_enabled = true


## 目标标记与虚线独立于 y 排序的部队/地点层，始终绘制在地图内容之上。
func _build_move_target_guide() -> void:
	_move_target_guide = MoveTargetGuideScript.new()
	_move_target_guide.name = "MoveTargetGuide"
	_move_target_guide.z_index = 20
	add_child(_move_target_guide)


## 只读取玩家现有移动状态，不新增第二套移动目标数据。
## MOVING 时显示；抵达（IDLE）、停止、战斗切换或部队不可用时清除。
func _update_move_target_guide() -> void:
	if _move_target_guide == null:
		return
	if _context == null or _player_party == null \
			or _battle_transition_started \
			or _player_party.movement_state != PartyData.MovementState.MOVING \
			or not _player_party.is_available_for_world():
		_move_target_guide.clear()
		return
	var start: Vector2 = _player_party.world_position
	# 连线起点贴合实际显示的部队图标，避免图标插值滞后造成脱节。
	if _player_icon != null and is_instance_valid(_player_icon):
		start = _player_icon.position
	_move_target_guide.set_guide(
		start, _resolve_move_guide_target(), camera.zoom.x
	)


## 普通移动直接使用 target_position；跟随部队时终点取目标的最新位置。
func _resolve_move_guide_target() -> Vector2:
	if _player_party.current_order == PartyData.OrderType.FOLLOW_PARTY \
			and not _player_party.current_target_id.is_empty():
		var focus := _context.party_manager.get_party(
			_player_party.current_target_id
		)
		if focus != null:
			return focus.world_position
	return _player_party.target_position


## 供自动化测试读取目标标记表现节点；正常运行时不使用。
func get_move_target_guide() -> MoveTargetGuideScript:
	return _move_target_guide


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


## 玩家阵营关系变化后统一刷新大地图表现。
## 关系本身由 FactionManager 维护；这里只重新读取并写入图标/名称标签。
func _refresh_faction_visuals() -> void:
	_refresh_party_relations()
	_refresh_settlement_relations()


func _refresh_party_relations() -> void:
	if _context == null:
		return
	for party_id: Variant in _party_icons:
		var icon := _party_icons.get(party_id) as PartyIcon
		if icon == null or not is_instance_valid(icon):
			continue
		icon.set_player_relation(
			_context.faction_manager.get_player_relation_for_party(str(party_id))
		)


func _refresh_settlement_relations() -> void:
	if _context == null:
		return
	for settlement_id: Variant in _settlement_name_tags:
		var tag := _settlement_name_tags.get(settlement_id) as SettlementNameTag
		if tag == null or not is_instance_valid(tag):
			continue
		tag.set_player_relation(
			_context.faction_manager.get_player_relation_for_settlement(
				str(settlement_id)
			)
		)


func _on_faction_relations_changed() -> void:
	_refresh_faction_visuals()
	if _family_panel != null and _family_panel.visible:
		_family_panel.refresh()


## 供自动化测试/调试读取当前关系对应的大地图表现。
func get_party_player_relation(party_id: String) -> int:
	if _context == null:
		return FactionManager.PlayerRelation.NEUTRAL
	return _context.faction_manager.get_player_relation_for_party(party_id)


func get_settlement_player_relation(settlement_id: String) -> int:
	if _context == null:
		return FactionManager.PlayerRelation.NEUTRAL
	return _context.faction_manager.get_player_relation_for_settlement(settlement_id)


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
	_stationed_bars.clear()
	_stationed_party_ids.clear()

	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		var tag := SettlementNameTag.new()
		tag.name = "SettlementNameTag_%s" % settlement.settlement_id
		_settlement_name_layer.add_child(tag)
		# 徽章读取地点实际家族归属；无家族时仅显示名称。
		tag.setup(
			settlement,
			_get_family_config(settlement.family_id),
			_get_specialty_icon_path(settlement)
		)
		_settlement_name_tags[settlement.settlement_id] = tag

		# 每个地点独立的停留部队旗帜条；初始为空且隐藏。
		var bar := SettlementStationedBar.new()
		bar.name = "StationedPartyBar_%s" % settlement.settlement_id
		_settlement_name_layer.add_child(bar)
		_stationed_bars[settlement.settlement_id] = bar
	# 名称层放在 UI 最底层，避免覆盖地点/部队/日志面板。
	_ui_root.move_child(_settlement_name_layer, 0)
	_refresh_settlement_relations()
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
		# 建筑所属家族或村庄特产变化时重建，避免继续显示旧旗帜/图标。
		var specialty_icon_path: String = _get_specialty_icon_path(settlement)
		if tag.get_bound_family_id() != settlement.family_id \
				or tag.get_specialty_icon_path() != specialty_icon_path:
			tag.setup(
				settlement,
				_get_family_config(settlement.family_id),
				specialty_icon_path
			)
		# 名称文本/徽章尺寸变化后同步半透明底板。
		tag.update_background_layout()
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


## 村庄特产图标路径来自商品配置；城镇/城堡或没有特产时返回空字符串。
func _get_specialty_icon_path(settlement: SettlementData) -> String:
	if settlement == null or _context == null \
			or _context.market_manager == null:
		return ""
	if settlement.settlement_type != SettlementData.SettlementType.VILLAGE:
		return ""
	for item_id: String in settlement.village_specialty_item_ids:
		var path: String = _context.market_manager.get_item_icon_path(item_id)
		if not path.is_empty() and ResourceLoader.exists(path):
			return path
	return ""


## 每帧重新计算“停留在地点上”的部队。
## 判定只看部队当前世界坐标与建筑的距离；移动中的部队不算停留。
## 停留部队隐藏普通圆形图标，改为在对应建筑下方显示家族旗帜。
func _update_stationed_parties() -> void:
	_stationed_party_ids.clear()
	if _context == null or _settlement_name_layer == null:
		return

	var groups: Dictionary = {}
	# 按 party_id 稳定排序，保证旗帜顺序可复现，不依赖字典遍历顺序。
	var parties: Array[PartyData] = []
	for party: PartyData in _context.party_manager.get_all_parties():
		if party != null:
			parties.append(party)
	parties.sort_custom(
		func(a: PartyData, b: PartyData) -> bool:
			return a.party_id < b.party_id
	)

	for party: PartyData in parties:
		if not _is_party_stationed(party):
			continue
		var settlement := _find_stationed_settlement(party.world_position)
		if settlement == null:
			continue
		_stationed_party_ids[party.party_id] = settlement.settlement_id
		if not groups.has(settlement.settlement_id):
			groups[settlement.settlement_id] = []
		(groups[settlement.settlement_id] as Array).append(
			_build_stationed_banner_entry(party)
		)

	var canvas_transform := get_viewport().get_canvas_transform()
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		var bar := _stationed_bars.get(settlement.settlement_id) as SettlementStationedBar
		if bar == null:
			continue
		var entries: Array[Dictionary] = []
		if groups.has(settlement.settlement_id):
			for entry: Variant in groups[settlement.settlement_id]:
				entries.append(entry as Dictionary)
		bar.set_entries(entries)
		if entries.is_empty():
			bar.visible = false
			continue
		var screen_position: Vector2 = (
			canvas_transform * settlement.world_position
		)
		var marker_radius: float = SettlementIcon.get_name_anchor_radius(
			settlement.settlement_type
		) * camera.zoom.y
		bar.position = screen_position + Vector2(
			-bar.size.x * 0.5, marker_radius + STATIONED_BAR_GAP
		)
		# 可见性只由“是否有停留部队”决定；离开屏幕的旗帜由引擎自然裁掉。
		bar.visible = true


## 停留判定：成员非空、未参与战斗、当前不在移动、且坐标贴近某个建筑。
func _is_party_stationed(party: PartyData) -> bool:
	if party == null or party.member_unit_ids.is_empty():
		return false
	if party.movement_state == PartyData.MovementState.MOVING:
		return false
	if not party.is_available_for_world():
		return false
	if _context == null or _context.battle_manager == null:
		return false
	if _context.battle_manager.get_battle_for_party(party.party_id) != null:
		return false
	return _find_stationed_settlement(party.world_position) != null


func _find_stationed_settlement(world_position: Vector2) -> SettlementData:
	if _context == null:
		return null
	var nearest: SettlementData = null
	var nearest_distance: float = STATIONED_PARTY_RADIUS
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement == null:
			continue
		var distance := settlement.world_position.distance_to(world_position)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest = settlement
	return nearest


## 停留部队旗帜只读取部队/家族数据，不生成圆形底盘。
func _build_stationed_banner_entry(party: PartyData) -> Dictionary:
	var family := _get_family_config(party.family_id)
	var texture_path: String = party.banner_texture_path
	if texture_path.is_empty() and family != null:
		texture_path = family.banner_texture_path
	var color: Color = Color("#7a4a42")
	if family != null:
		color = family.primary_color
	else:
		color = _get_party_marker_style().get_faction_color(
			party.faction_id, color
		)
	return {
		"party_id": party.party_id,
		"display_name": party.party_name,
		"texture": _load_texture(texture_path),
		"texture_path": texture_path,
		"color": color,
	}


func get_stationed_bar(settlement_id: String) -> SettlementStationedBar:
	return _stationed_bars.get(settlement_id) as SettlementStationedBar


func get_stationed_settlement_id(party_id: String) -> String:
	return str(_stationed_party_ids.get(party_id, ""))


func is_party_stationed(party_id: String) -> bool:
	return _stationed_party_ids.has(party_id)


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
	_build_pause_tip()
	_build_bottom_bar()
	_build_captive_panel()
	_build_settlement_panel()
	_build_party_dialogue_panel()
	_build_attack_confirm_panel()
	_build_player_encounter_panel()
	_build_battle_interaction_panel()
	_build_party_manage_panel()
	_build_party_hover_panel()
	_build_battle_summary_panel()
	_build_world_log_panel()
	_build_inventory_panel()
	_build_save_panel()
	_build_encyclopedia_panel()
	_build_event_center_panel()
	_build_family_panel()
	_build_event_feed()
	_build_event_reminder()
	# 市场是覆盖层，最后加入以保证显示在地点/背包面板之上。
	_build_market_panel()
	_build_tavern_panel()
	# 详情弹窗必须位于所有普通面板之上。
	_build_event_detail_dialog()
	# 顶部悬浮提示必须位于所有面板之上，避免被覆盖层遮住。
	_build_top_info_tooltip()


## 覆盖层登记：显隐仍由各面板控制，这里统一输入阻塞与暂停计数。
## 市场/出售/雇佣兵招募覆盖在地点面板之上，不单独持有暂停原因。
func _register_overlays() -> void:
	_overlays.register_overlay(
		"save", _save_panel.get_panel(), GameManager.PAUSE_REASON_UI_PANEL
	)
	_overlays.register_overlay(
		"settlement", _settlement_panel, GameManager.PAUSE_REASON_UI_PANEL, true
	)
	_overlays.register_overlay(
		"party_dialogue", _party_panel, GameManager.PAUSE_REASON_UI_PANEL
	)
	_overlays.register_overlay(
		"party_manage", _party_manage_panel, GameManager.PAUSE_REASON_UI_PANEL
	)
	_overlays.register_overlay(
		"inventory", _inventory_panel, GameManager.PAUSE_REASON_UI_PANEL
	)
	_overlays.register_overlay(
		"encounter", _encounter_panel, GameManager.PAUSE_REASON_ENCOUNTER_DIALOGUE
	)
	_overlays.register_overlay(
		"battle_interaction",
		_battle_interaction_panel,
		GameManager.PAUSE_REASON_BATTLE_INTERACTION
	)
	_overlays.register_overlay("attack_confirm", _attack_confirm_panel)
	_overlays.register_overlay(
		"encyclopedia", _encyclopedia_panel.get_panel(), GameManager.PAUSE_REASON_UI_PANEL
	)
	_overlays.register_overlay(
		"event_center", _event_center_panel, GameManager.PAUSE_REASON_UI_PANEL
	)
	_overlays.register_overlay(
		"family", _family_panel, GameManager.PAUSE_REASON_UI_PANEL
	)
	_overlays.register_overlay(
		"event_detail", _event_detail_dialog, GameManager.PAUSE_REASON_UI_PANEL
	)
	_overlays.register_overlay("market", _market_panel)
	_overlays.register_overlay("prisoner_sale", _prisoner_sale_panel)
	_overlays.register_overlay("mercenary_recruit", _mercenary_recruit_panel)


## 暂停提示只读取 TimeManager 的实际有效倍率；基础暂停与 UI 暂停都会显示。
func _build_pause_tip() -> void:
	_pause_tip_label = _make_label("已暂停", 18)
	_pause_tip_label.name = "WorldPausedTip"
	_pause_tip_label.anchor_left = 0.5
	_pause_tip_label.anchor_right = 0.5
	_pause_tip_label.offset_left = -140.0
	_pause_tip_label.offset_right = 140.0
	_pause_tip_label.offset_top = 52.0
	_pause_tip_label.offset_bottom = 82.0
	_pause_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 琥珀色 #D97706，加描边保证浅色地图上仍清晰可读。
	_pause_tip_label.add_theme_color_override("font_color", Color("#D97706"))
	_pause_tip_label.add_theme_color_override("font_outline_color", Color(0.16, 0.10, 0.02, 0.9))
	_pause_tip_label.add_theme_constant_override("outline_size", 4)
	# 系统字体无独立粗体字重，用 FontVariation 加粗到半粗体。
	var semibold := FontVariation.new()
	semibold.base_font = UiTheme.create().default_font
	semibold.variation_embolden = 0.6
	_pause_tip_label.add_theme_font_override("font", semibold)
	_pause_tip_label.visible = false
	_ui_root.add_child(_pause_tip_label)


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

	# 左/中/右三个独立锚定区：时间始终位于屏幕水平中心，
	# 不会被左右新增的金币、移速或功能按钮推离中心。
	var content := Control.new()
	content.name = "TopBarContent"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(content)

	var left := HBoxContainer.new()
	left.name = "TopBarLeft"
	left.anchor_bottom = 1.0
	# 图标放大后为三个条目与生命值文本预留更宽的区域，避免挤压。
	left.offset_right = 360.0
	left.alignment = BoxContainer.ALIGNMENT_BEGIN
	left.add_theme_constant_override("separation", 12)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(left)

	_money_label = _add_top_info_entry(
		left, TOP_INFO_ICON_GOLD_PATH, "MoneyLabel", "0"
	)
	_party_speed_label = _add_top_info_entry(
		left, TOP_INFO_ICON_SPEED_PATH, "PartySpeedLabel", "0.0"
	)
	_top_party_troop_label = _add_top_info_entry(
		left, TOP_INFO_ICON_TROOP_PATH, "PartySizeLabel", "0"
	)
	# 生命值没有专属图标：使用同一字体/行高的纯文本条目，
	# 数值始终来自当前玩家角色的真实 UnitData。
	_player_hp_label = _make_label("0/0", 15)
	_player_hp_label.name = "PlayerHpLabel"
	_player_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	left.add_child(_player_hp_label)

	# 昼夜窗口占据屏幕水平中心；世界时间文本改为紧贴其左侧，
	# 保证正方形窗口本身精确居中，同时不与其他顶栏元素重叠。
	var center := HBoxContainer.new()
	center.name = "TopBarCenter"
	center.anchor_left = 0.5
	center.anchor_right = 0.5
	center.anchor_bottom = 1.0
	center.offset_left = -340.0
	center.offset_right = -TOP_BAR_CLOCK_SIZE * 0.5 - TOP_BAR_CLOCK_TEXT_GAP
	center.alignment = BoxContainer.ALIGNMENT_END
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(center)

	_world_time_label = _make_label("世界时间", 15)
	_world_time_label.name = "WorldTimeLabel"
	_world_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	center.add_child(_world_time_label)

	_day_night_clock = DayNightClockScript.new()
	_day_night_clock.name = "DayNightClock"
	_day_night_clock.anchor_left = 0.5
	_day_night_clock.anchor_right = 0.5
	_day_night_clock.anchor_top = 0.5
	_day_night_clock.anchor_bottom = 0.5
	_day_night_clock.offset_left = -TOP_BAR_CLOCK_SIZE * 0.5
	_day_night_clock.offset_right = TOP_BAR_CLOCK_SIZE * 0.5
	_day_night_clock.offset_top = -TOP_BAR_CLOCK_SIZE * 0.5
	_day_night_clock.offset_bottom = TOP_BAR_CLOCK_SIZE * 0.5
	content.add_child(_day_night_clock)

	var right := HBoxContainer.new()
	right.name = "TopBarRight"
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.anchor_bottom = 1.0
	right.offset_left = -512.0
	right.alignment = BoxContainer.ALIGNMENT_END
	right.add_theme_constant_override("separation", 4)
	content.add_child(right)

	_pause_button = _make_top_bar_button("暂停", "PauseButton")
	_pause_button.tooltip_text = "暂停（快捷键 1）"
	_pause_button.toggle_mode = true
	_pause_button.pressed.connect(_on_pause_pressed)
	right.add_child(_pause_button)
	_time_buttons.append(_pause_button)

	_speed_one_button = _make_top_bar_button("1x", "SpeedOneButton")
	_speed_one_button.tooltip_text = "1 倍速（快捷键 2）"
	_speed_one_button.toggle_mode = true
	_speed_one_button.pressed.connect(_on_speed_one_pressed)
	right.add_child(_speed_one_button)
	_time_buttons.append(_speed_one_button)

	_speed_two_button = _make_top_bar_button("2x", "SpeedTwoButton")
	_speed_two_button.tooltip_text = "2 倍速（快捷键 3）"
	_speed_two_button.toggle_mode = true
	_speed_two_button.pressed.connect(_on_speed_two_pressed)
	right.add_child(_speed_two_button)
	_time_buttons.append(_speed_two_button)

	var event_button := _make_top_bar_button("事件", "EventCenterButton")
	event_button.tooltip_text = "查看已接取任务与待处理事项"
	event_button.pressed.connect(_on_event_center_pressed)
	right.add_child(event_button)

	var party_button := _make_top_bar_button("部队", "PartyButton")
	party_button.tooltip_text = "查看玩家部队与士兵详情"
	party_button.pressed.connect(_on_party_manage_pressed)
	right.add_child(party_button)

	var family_button := _make_top_bar_button("家族", "FamilyButton")
	family_button.tooltip_text = "查看家族贵族与封地"
	family_button.pressed.connect(_on_family_pressed)
	right.add_child(family_button)

	var inventory_button := _make_top_bar_button("背包", "InventoryButton")
	inventory_button.tooltip_text = "查看玩家金币与持有物品"
	inventory_button.pressed.connect(_on_inventory_pressed)
	right.add_child(inventory_button)

	var encyclopedia_button := _make_top_bar_button("百科", "EncyclopediaButton")
	encyclopedia_button.tooltip_text = "查看王国、家族、地点与敌对势力"
	encyclopedia_button.pressed.connect(_on_encyclopedia_pressed)
	right.add_child(encyclopedia_button)

	var save_button := _make_top_bar_button("保存", "SaveButton")
	save_button.pressed.connect(_on_save_pressed)
	right.add_child(save_button)

	var menu_button := _make_top_bar_button("主菜单", "MainMenuButton")
	menu_button.pressed.connect(_on_main_menu_pressed)
	right.add_child(menu_button)


# ---------------------------------------------------------------------------
# 主界面事件中心
# ---------------------------------------------------------------------------


func _build_event_center_panel() -> void:
	_event_center_panel = EventCenterPanelScript.new()
	_event_center_panel.name = "EventCenterOverlay"
	_event_center_panel.visible = false
	_event_center_panel.closed.connect(_on_event_center_closed)
	_ui_root.add_child(_event_center_panel)
	_event_center_panel.setup(_context)


func open_event_center() -> bool:
	if _context == null or _event_center_panel == null:
		return false
	if _event_center_panel.visible or _battle_transition_started:
		return false
	# 建筑信息面板打开时仍允许查看事件；时间控制保持禁用。
	if _has_open_modal(true):
		return false
	_overlays.acquire_pause("event_center")
	_event_center_panel.open()
	_set_time_buttons_enabled(false)
	_update_time_ui()
	return true


func close_event_center() -> void:
	if _event_center_panel != null and _event_center_panel.visible:
		_event_center_panel.close()


func _on_event_center_pressed() -> void:
	open_event_center()


func _on_event_center_closed() -> void:
	_overlays.release_pause("event_center")
	_refresh_time_buttons()
	_update_time_ui()


func _refresh_event_center_if_needed() -> void:
	if _event_center_panel != null and _event_center_panel.visible:
		_event_center_panel.refresh_if_needed()


func get_event_center_panel():
	return _event_center_panel


# ---------------------------------------------------------------------------
# 家族管理面板
# ---------------------------------------------------------------------------


func _build_family_panel() -> void:
	_family_panel = FamilyPanelScript.new()
	_family_panel.name = "FamilyOverlay"
	_family_panel.visible = false
	_family_panel.closed.connect(_on_family_closed)
	_family_panel.settlement_selected.connect(_on_family_settlement_selected)
	_ui_root.add_child(_family_panel)
	_family_panel.setup(_context)


func open_family_panel() -> bool:
	if _context == null or _family_panel == null:
		return false
	if _family_panel.visible or _battle_transition_started:
		return false
	if _has_open_modal(true):
		return false
	_overlays.acquire_pause("family")
	_family_panel.open()
	_set_time_buttons_enabled(false)
	_update_time_ui()
	return true


func close_family_panel() -> void:
	if _family_panel != null and _family_panel.visible:
		_family_panel.close()


func _on_family_pressed() -> void:
	open_family_panel()


func _on_family_closed() -> void:
	_overlays.release_pause("family")
	_refresh_time_buttons()
	_update_time_ui()


func _on_family_settlement_selected(settlement_id: String) -> void:
	if focus_settlement_on_map(settlement_id):
		close_family_panel()


func _refresh_family_panel_if_needed() -> void:
	if _family_panel != null and _family_panel.visible:
		_family_panel.refresh_if_needed()


func get_family_panel():
	return _family_panel


## 把镜头定位到地点；复用大地图自由镜头与边界限制，不改变玩家部队。
func focus_settlement_on_map(settlement_id: String) -> bool:
	if _context == null or settlement_id.is_empty():
		return false
	var settlement := _context.settlement_manager.get_settlement(settlement_id)
	if settlement == null:
		return false
	_camera_mode = CameraMode.FREE_CAMERA
	camera.position = _clamp_camera_position(settlement.world_position)
	return true


# ---------------------------------------------------------------------------
# 右侧可操作事件框与详情弹窗
# ---------------------------------------------------------------------------


func _build_event_feed() -> void:
	_event_feed = EventFeedScript.new()
	_event_feed.name = "EventFeed"
	_event_feed.visible = false
	_event_feed.event_selected.connect(_on_event_feed_selected)
	_ui_root.add_child(_event_feed)
	_event_feed.setup(_context)


## 右侧小型提醒：只展示“是否存在待处理事件”，不复制事件数据。
func _build_event_reminder() -> void:
	_event_reminder = EventReminderScript.new()
	_event_reminder.name = "EventReminder"
	_event_reminder.visible = false
	_event_reminder.open_requested.connect(_on_event_reminder_pressed)
	_ui_root.add_child(_event_reminder)
	_event_reminder.setup(_context)


func _build_event_detail_dialog() -> void:
	_event_detail_dialog = EventDetailDialogScript.new()
	_event_detail_dialog.name = "EventDetailOverlay"
	_event_detail_dialog.visible = false
	_event_detail_dialog.closed.connect(_on_event_detail_closed)
	_ui_root.add_child(_event_detail_dialog)
	_event_detail_dialog.setup(_context)


func get_event_feed():
	return _event_feed


func get_event_reminder():
	return _event_reminder


func get_event_detail_dialog():
	return _event_detail_dialog


## 点击提醒：唯一事件直接打开详情，多条时进入事件中心，均由现有事件数据驱动。
func _on_event_reminder_pressed() -> void:
	if _context == null:
		return
	var events: Array[Dictionary] = _context.event_center.get_actionable_events()
	if events.is_empty():
		return
	if events.size() == 1:
		_on_event_feed_selected(str(events[0].get("event_id", "")))
		return
	open_event_center()


func _on_event_feed_selected(event_id: String) -> void:
	if _context == null or _event_detail_dialog == null:
		return
	if _battle_transition_started or _has_open_modal(true):
		return
	if not _event_detail_dialog.open(event_id):
		return
	_overlays.acquire_pause("event_detail")
	_set_time_buttons_enabled(false)
	_update_time_ui()


func _on_event_detail_closed() -> void:
	_overlays.release_pause("event_detail")
	_refresh_time_buttons()
	_update_time_ui()
	if _event_feed != null:
		_event_feed.refresh(true)


func _refresh_event_feed_if_needed() -> void:
	if _event_feed != null:
		_event_feed.refresh_if_needed()
	if _event_reminder != null:
		_event_reminder.refresh_if_needed()
	if _event_detail_dialog != null:
		_event_detail_dialog.refresh_if_needed()


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


## 左侧被俘状态栏：只展示 CaptivityManager/UnitData 的只读状态。
## 不属于模态面板，不暂停世界，时间倍率切换仍然可用。
func _build_captive_panel() -> void:
	_captive_panel = PanelContainer.new()
	_captive_panel.name = "CaptiveStatusPanel"
	_captive_panel.visible = false
	_captive_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_captive_panel.anchor_top = 0.5
	_captive_panel.anchor_bottom = 0.5
	_captive_panel.offset_left = 20.0
	_captive_panel.offset_top = -120.0
	_captive_panel.offset_right = 360.0
	_captive_panel.offset_bottom = 120.0
	_ui_root.add_child(_captive_panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_captive_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	_captive_title_label = _make_label("被俘", 22)
	_captive_title_label.name = "CaptiveTitleLabel"
	_captive_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_captive_title_label)

	column.add_child(HSeparator.new())

	_captive_captor_label = _make_label("", 14)
	_captive_captor_label.name = "CaptiveCaptorLabel"
	_captive_captor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_captive_captor_label)

	_captive_hp_label = _make_label("", 14)
	_captive_hp_label.name = "CaptiveHpLabel"
	column.add_child(_captive_hp_label)

	var tip := _make_label("生命值按世界时间恢复；满血后将定期尝试逃脱。", 12)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.modulate = Color(1.0, 0.86, 0.55)
	column.add_child(tip)


func _build_settlement_panel() -> void:
	_settlement_panel = PanelContainer.new()
	_settlement_panel.name = "SettlementPanel"
	_settlement_panel.visible = false
	_settlement_panel.anchor_top = 0.5
	_settlement_panel.anchor_bottom = 0.5
	_settlement_panel.offset_left = 20.0
	_settlement_panel.offset_top = -250.0
	_settlement_panel.offset_right = 380.0
	_settlement_panel.offset_bottom = 250.0
	_ui_root.add_child(_settlement_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_settlement_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "SettlementInfoView"
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	_settlement_info_view = column

	# 酒馆内容与城镇信息共用同一个 PanelContainer；切换时只改可见性，
	# 不改变窗口位置、尺寸，也不创建第二个弹窗。
	_settlement_tavern_host = Control.new()
	_settlement_tavern_host.name = "SettlementTavernHost"
	_settlement_tavern_host.visible = false
	_settlement_tavern_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_settlement_tavern_host)

	_settlement_name_label = _make_label("", 24)
	_settlement_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_settlement_name_label)

	_settlement_type_label = _make_label("", 16)
	_settlement_type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_settlement_type_label)

	column.add_child(HSeparator.new())

	_settlement_owner_label = _make_label("", 15)
	_settlement_owner_label.name = "SettlementOwnerLabel"
	column.add_child(_settlement_owner_label)

	_settlement_family_label = _make_label("", 15)
	_settlement_family_label.name = "SettlementFamilyLabel"
	column.add_child(_settlement_family_label)

	_settlement_population_label = _make_label("", 15)
	_settlement_population_label.name = "SettlementPopulationLabel"
	column.add_child(_settlement_population_label)

	_settlement_prosperity_label = _make_label("", 15)
	_settlement_prosperity_label.name = "SettlementProsperityLabel"
	column.add_child(_settlement_prosperity_label)

	_settlement_tax_label = _make_label("", 15)
	_settlement_tax_label.name = "SettlementTaxLabel"
	column.add_child(_settlement_tax_label)

	_settlement_fief_label = _make_label("", 15)
	_settlement_fief_label.name = "SettlementFiefLabel"
	column.add_child(_settlement_fief_label)

	_settlement_recruit_status_label = _make_label("", 13)
	_settlement_recruit_status_label.name = "SettlementRecruitStatusLabel"
	_settlement_recruit_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_settlement_recruit_status_label.modulate = Color(1.0, 0.86, 0.55)
	column.add_child(_settlement_recruit_status_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	_settlement_recruit_button = _make_button(
		"征召采邑", "SettlementRecruitFiefButton"
	)
	_settlement_recruit_button.visible = false
	_settlement_recruit_button.custom_minimum_size = Vector2(0.0, 36.0)
	_settlement_recruit_button.pressed.connect(_on_settlement_recruit_pressed)
	column.add_child(_settlement_recruit_button)

	_settlement_market_button = _make_button("交易市场", "SettlementMarketButton")
	_settlement_market_button.custom_minimum_size = Vector2(0.0, 36.0)
	_settlement_market_button.visible = false
	_settlement_market_button.pressed.connect(_on_settlement_market_pressed)
	column.add_child(_settlement_market_button)

	_settlement_tavern_button = _make_button("进入酒馆", "SettlementTavernButton")
	_settlement_tavern_button.custom_minimum_size = Vector2(0.0, 36.0)
	_settlement_tavern_button.visible = false
	_settlement_tavern_button.pressed.connect(_on_settlement_tavern_pressed)
	column.add_child(_settlement_tavern_button)

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


## 主动攻击二次确认：叠加在部队对话之上，取消后直接回到原对话面板。
func _build_attack_confirm_panel() -> void:
	_attack_confirm_panel = PanelContainer.new()
	_attack_confirm_panel.name = "AttackConfirmPanel"
	_attack_confirm_panel.visible = false
	_attack_confirm_panel.anchor_left = 0.5
	_attack_confirm_panel.anchor_top = 0.5
	_attack_confirm_panel.anchor_right = 0.5
	_attack_confirm_panel.anchor_bottom = 0.5
	_attack_confirm_panel.offset_left = -280.0
	_attack_confirm_panel.offset_top = -110.0
	_attack_confirm_panel.offset_right = 280.0
	_attack_confirm_panel.offset_bottom = 110.0
	_attack_confirm_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui_root.add_child(_attack_confirm_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_attack_confirm_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	_attack_confirm_label = _make_label("", 20)
	_attack_confirm_label.name = "AttackConfirmLabel"
	_attack_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_attack_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_attack_confirm_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_attack_confirm_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	column.add_child(_attack_confirm_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)

	var confirm_button := _make_button("确认攻击", "ConfirmAttackButton")
	confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_button.custom_minimum_size = Vector2(0.0, 40.0)
	confirm_button.pressed.connect(_on_attack_confirm_pressed)
	buttons.add_child(confirm_button)

	var cancel_button := _make_button("取消", "CancelAttackButton")
	cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_button.custom_minimum_size = Vector2(0.0, 40.0)
	cancel_button.pressed.connect(_on_attack_cancel_pressed)
	buttons.add_child(cancel_button)


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
	if _context.battle_manager.get_battle_for_party(_context.player_party_id) != null:
		_context.encounter_manager.clear_pending_player_encounter()
		return
	if _has_open_modal(false):
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

	_overlays.acquire_pause("encounter")
	_set_time_buttons_enabled(false)
	_update_time_ui()


## 清理异常关闭的遭遇对话；不改变基础世界倍率。
func cancel_player_encounter() -> void:
	if _encounter_panel != null:
		_encounter_panel.visible = false
	if _encounter_portrait != null:
		_encounter_portrait.clear()
	_overlays.release_pause("encounter")
	if _context != null:
		_context.encounter_manager.clear_pending_player_encounter()
	_encounter_id = ""
	_encounter_leave_allowed = true
	_refresh_time_buttons()
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
	_overlays.release_pause("encounter")


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
	_overlays.release_pause("encounter")
	_context.encounter_manager.decline_player_encounter(attacker_id)
	_refresh_time_buttons()
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
	# 地点面板打开时仍允许查看部队；世界时间控制仍由独立权限关闭。
	if _has_open_modal(true):
		return false
	# 被俘期间允许只读查看部队面板，但面板不具备夺取/恢复控制的能力。
	var captive: bool = _context.captivity_manager.is_player_captive()
	if not _player_party.is_available_for_world() and not captive:
		push_warning("当前部队状态不可用，无法打开部队面板")
		return false

	_overlays.acquire_pause("party_manage")
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
	_overlays.release_pause("party_manage")
	_refresh_time_buttons()
	_update_time_ui()


# ---------------------------------------------------------------------------
# 玩家背包
# ---------------------------------------------------------------------------


func _build_inventory_panel() -> void:
	_inventory_panel = InventoryPanel.new()
	_inventory_panel.name = "InventoryPanel"
	_inventory_panel.visible = false
	_inventory_panel.closed.connect(_on_inventory_closed)
	_ui_root.add_child(_inventory_panel)
	_inventory_panel.setup(_context)


## 打开只读背包面板；失败返回 false 且不改变时间状态。
func open_inventory() -> bool:
	if _context == null or _inventory_panel == null:
		return false
	if _inventory_panel.visible or _battle_transition_started:
		return false
	# 地点面板打开时仍允许打开背包；只有其他覆盖层会互相阻塞。
	if _has_open_modal(true):
		return false
	_overlays.acquire_pause("inventory")
	_inventory_panel.open()
	_set_time_buttons_enabled(false)
	_update_time_ui()
	return true


func close_inventory() -> void:
	if _inventory_panel != null and _inventory_panel.visible:
		_inventory_panel.close()


func _on_inventory_pressed() -> void:
	open_inventory()


func _on_inventory_closed() -> void:
	_overlays.release_pause("inventory")
	_refresh_time_buttons()
	_update_time_ui()


# ---------------------------------------------------------------------------
# 城镇交易市场
# ---------------------------------------------------------------------------


func _build_market_panel() -> void:
	_market_panel = MarketPanel.new()
	_market_panel.name = "MarketPanel"
	_market_panel.visible = false
	_market_panel.closed.connect(_on_market_closed)
	_market_panel.traded.connect(_on_market_traded)
	_ui_root.add_child(_market_panel)
	_market_panel.setup(_context)


func get_market_panel() -> MarketPanel:
	return _market_panel


# ---------------------------------------------------------------------------
# 城镇酒馆（阶段 13）
# ---------------------------------------------------------------------------


func _build_tavern_panel() -> void:
	if _settlement_tavern_host == null:
		return
	_tavern_panel = TavernPanel.new()
	_tavern_panel.name = "TavernPanel"
	_tavern_panel.visible = false
	_tavern_panel.closed.connect(_on_tavern_closed)
	_tavern_panel.sell_requested.connect(_on_tavern_sell_requested)
	_tavern_panel.mercenary_recruit_requested.connect(
		_on_tavern_mercenary_recruit_requested
	)
	_settlement_tavern_host.add_child(_tavern_panel)
	# 嵌入城镇信息面板；不创建遮罩或独立二级窗口。
	_tavern_panel.setup(_context, true)

	# 独立出售界面：独立遮罩 + 窗口，复用同一套出售业务与视图。
	_prisoner_sale_panel = TavernPanel.new()
	_prisoner_sale_panel.name = "PrisonerSalePanel"
	_prisoner_sale_panel.visible = false
	_prisoner_sale_panel.closed.connect(_on_prisoner_sale_closed)
	_prisoner_sale_panel.prisoners_sold.connect(_on_prisoner_sale_completed)
	_ui_root.add_child(_prisoner_sale_panel)
	_prisoner_sale_panel.setup(_context, false)

	# 独立雇佣兵招募界面：列表、详情与 UnitVisual 预览都来自真实数据。
	_mercenary_recruit_panel = MercenaryRecruitPanel.new()
	_mercenary_recruit_panel.name = "MercenaryRecruitPanel"
	_mercenary_recruit_panel.visible = false
	_mercenary_recruit_panel.closed.connect(_on_mercenary_recruit_closed)
	_ui_root.add_child(_mercenary_recruit_panel)
	_mercenary_recruit_panel.setup(_context)


func get_tavern_panel() -> TavernPanel:
	return _tavern_panel


func get_prisoner_sale_panel() -> TavernPanel:
	return _prisoner_sale_panel


func get_mercenary_recruit_panel() -> MercenaryRecruitPanel:
	return _mercenary_recruit_panel


## 嵌入酒馆的雇佣兵入口只发起意图：隐藏城镇面板并打开独立招募界面，
## 暂停原因仍由地点面板持有。
func _on_tavern_mercenary_recruit_requested(settlement_id: String) -> void:
	if _context == null or _mercenary_recruit_panel == null:
		return
	var settlement := _context.settlement_manager.get_settlement(settlement_id)
	if settlement == null:
		return
	if _tavern_panel != null:
		_tavern_panel.reset()
	_show_settlement_info_view()
	_settlement_panel.visible = false
	if not _mercenary_recruit_panel.open(settlement):
		_settlement_panel.visible = true
		_show_settlement_info_view()
		return
	_set_time_buttons_enabled(false)
	_update_time_ui()


func _on_mercenary_recruit_closed() -> void:
	if _context == null:
		return
	var settlement := _context.settlement_manager.get_settlement(_settlement_latch_id)
	if settlement == null:
		_overlays.release_pause("settlement")
		_refresh_time_buttons()
		_update_time_ui()
		return
	_show_settlement_info_view()
	_settlement_panel.visible = true
	_refresh_settlement_info(settlement)
	_set_time_buttons_enabled(false)
	_update_time_ui()


## 嵌入酒馆只负责发起意图：隐藏城镇面板并打开独立出售界面。
## 暂停原因仍由地点面板持有，关闭出售界面后回到城镇信息。
func _on_tavern_sell_requested(settlement_id: String) -> void:
	if _context == null or _prisoner_sale_panel == null:
		return
	var settlement := _context.settlement_manager.get_settlement(settlement_id)
	if settlement == null:
		return
	if _tavern_panel != null:
		_tavern_panel.reset()
	_show_settlement_info_view()
	_settlement_panel.visible = false
	if not _prisoner_sale_panel.open_sale(settlement):
		_settlement_panel.visible = true
		_show_settlement_info_view()
		return
	_set_time_buttons_enabled(false)
	_update_time_ui()


func _on_prisoner_sale_closed() -> void:
	if _inventory_panel != null:
		_inventory_panel.refresh()
	if _context == null:
		return
	var settlement := _context.settlement_manager.get_settlement(_settlement_latch_id)
	if settlement == null:
		_overlays.release_pause("settlement")
		_refresh_time_buttons()
		_update_time_ui()
		return
	_show_settlement_info_view()
	_settlement_panel.visible = true
	_refresh_settlement_info(settlement)
	_set_time_buttons_enabled(false)
	_update_time_ui()


func _on_prisoner_sale_completed(_result: Dictionary) -> void:
	# 出售已由 PrisonerTradeManager 原子结算；这里只刷新只读显示。
	if _inventory_panel != null:
		_inventory_panel.refresh()


func _on_settlement_tavern_pressed() -> void:
	if _context == null or _tavern_panel == null:
		return
	var settlement := _context.settlement_manager.get_settlement(
		_settlement_latch_id
	)
	if settlement == null or settlement.settlement_type != SettlementData.SettlementType.TOWN:
		return
	if not _tavern_panel.open(settlement):
		return
	# 同一地点面板内切换内容：保留原窗口位置/尺寸与 ui_panel 暂停原因。
	_settlement_info_view.visible = false
	_settlement_tavern_host.visible = true
	_tavern_panel.visible = true


## 离开酒馆：原面板直接切回城镇信息，世界保持暂停。
func _on_tavern_closed() -> void:
	if _inventory_panel != null:
		_inventory_panel.refresh()
	if _context == null:
		return
	var settlement := _context.settlement_manager.get_settlement(
		_settlement_latch_id
	)
	_show_settlement_info_view()
	if settlement != null:
		_refresh_settlement_info(settlement)


func _show_settlement_info_view() -> void:
	if _settlement_tavern_host != null:
		_settlement_tavern_host.visible = false
	if _settlement_info_view != null:
		_settlement_info_view.visible = true


func _on_settlement_market_pressed() -> void:
	if _context == null or _market_panel == null:
		return
	var settlement := _context.settlement_manager.get_settlement(
		_settlement_latch_id
	)
	if settlement == null \
			or not _context.market_manager.is_market_settlement(settlement):
		return
	if _context.market_manager.get_market(settlement.settlement_id) == null:
		_context.market_manager.ensure_markets()
	if _context.market_manager.get_market(settlement.settlement_id) == null:
		_settlement_recruit_status_label.text = "该地点暂无可用市场。"
		return
	if not _market_panel.open(settlement):
		return
	# 市场覆盖地点面板，但沿用同一个 ui_panel 暂停原因；关闭后恢复面板。
	_settlement_panel.visible = false
	_overlays.acquire_pause("settlement")


## 关闭市场：清空交易预览，恢复地点面板，并保持世界暂停。
func _on_market_closed() -> void:
	if _inventory_panel != null:
		_inventory_panel.refresh()
	if _context == null:
		return
	var settlement := _context.settlement_manager.get_settlement(
		_settlement_latch_id
	)
	if settlement != null:
		_settlement_panel.visible = true
		_refresh_settlement_info(settlement)
		return
	# 地点已不存在时安全释放暂停原因，避免永久锁住时间。
	_settlement_panel.visible = false
	_overlays.release_pause("settlement")
	_refresh_time_buttons()
	_update_time_ui()


## 交易成功后同步刷新只读背包面板（面板可能正被其他窗口覆盖）。
func _on_market_traded(_result: Dictionary) -> void:
	if _inventory_panel != null:
		_inventory_panel.refresh()


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

	# 每个 side_index 一列；同侧多支部队在列内纵向排列。
	_battle_summary_content = HBoxContainer.new()
	_battle_summary_content.name = "BattleSummaryContent"
	_battle_summary_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_battle_summary_content.add_theme_constant_override(
		"separation", BATTLE_SUMMARY_COLUMN_GAP
	)
	column.add_child(_battle_summary_content)


## 固定在大地图屏幕左下角的世界日志；内容只读 WorldLogManager。
func _build_world_log_panel() -> void:
	_world_log_panel = WorldLogPanel.new()
	_ui_root.add_child(_world_log_panel)
	_world_log_panel.setup(_context.world_log_manager)
	# 大地图默认只显示最新事件文本；点击展开完整历史。
	_world_log_panel.set_collapsible(true)


func expand_world_log() -> void:
	if _world_log_panel != null:
		_world_log_panel.expand()


func collapse_world_log() -> void:
	if _world_log_panel != null:
		_world_log_panel.collapse()


func is_world_log_expanded() -> bool:
	return _world_log_panel != null and _world_log_panel.is_expanded()


func get_world_log_panel() -> WorldLogPanel:
	return _world_log_panel


func _rebuild_world_log() -> void:
	if _world_log_panel != null:
		_world_log_panel.rebuild()


func get_world_log_text() -> String:
	return _world_log_panel.get_log_text() if _world_log_panel != null else ""


func get_world_log_entry_count() -> int:
	return _world_log_panel.get_entry_count() if _world_log_panel != null else 0


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
	if party == null or _stationed_party_ids.has(party.party_id):
		_hide_party_hover()
		return
	# 参战部队已经合并到战斗标记，不再显示原图标悬浮信息。
	if _context.battle_manager.get_battle_for_party(party.party_id) != null:
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


## 鼠标悬浮描边：与悬浮面板共用目标识别规则，部队优先于建筑；
## 同一时刻只高亮一个目标，离开后立即清除。
func _update_hover_outline() -> void:
	if _context == null or _player_party == null or _battle_transition_started \
			or _is_input_blocked():
		_set_hover_outline("", "")
		return
	_apply_hover_outline_at(get_global_mouse_position())


func _apply_hover_outline_at(world_position: Vector2) -> void:
	var party := _find_party_within(world_position, PARTY_HOVER_RADIUS)
	if party != null and not _stationed_party_ids.has(party.party_id) \
			and _context.battle_manager.get_battle_for_party(party.party_id) == null:
		_set_hover_outline(party.party_id, "")
		return
	var settlement := _find_settlement_at(world_position)
	_set_hover_outline("", settlement.settlement_id if settlement != null else "")


## 只切换描边状态，不改变图标尺寸、位置、绘制层级或点击判定。
func _set_hover_outline(party_id: String, settlement_id: String) -> void:
	if _hover_outline_party_id != party_id:
		var old_party_icon := _party_icons.get(_hover_outline_party_id) as PartyIcon
		if is_instance_valid(old_party_icon):
			old_party_icon.set_hovered(false)
		_hover_outline_party_id = party_id
		var new_party_icon := _party_icons.get(party_id) as PartyIcon
		if is_instance_valid(new_party_icon):
			new_party_icon.set_hovered(true)

	if _hover_outline_settlement_id != settlement_id:
		var old_settlement_icon := _settlement_icons.get(
			_hover_outline_settlement_id
		) as SettlementIcon
		if is_instance_valid(old_settlement_icon):
			old_settlement_icon.set_hovered(false)
		_hover_outline_settlement_id = settlement_id
		var new_settlement_icon := _settlement_icons.get(
			settlement_id
		) as SettlementIcon
		if is_instance_valid(new_settlement_icon):
			new_settlement_icon.set_hovered(true)


## 切换详细模式；鼠标不移动也立即刷新当前悬浮面板。
func set_alt_detail_active(active: bool) -> void:
	if _alt_detail_active == active:
		return
	_alt_detail_active = active
	# 顶部金钱/移速悬浮提示与部队图标悬浮共用同一个 Alt 状态。
	if not _top_info_hover_kind.is_empty():
		_refresh_top_info_tooltip()
	if _hover_party_id.is_empty() or _context == null:
		return
	var party := _context.party_manager.get_party(_hover_party_id)
	if party == null:
		_hide_party_hover()
		return
	_hover_signature = _party_composition_signature(party)
	_rebuild_party_hover(party)
	_position_party_hover(get_viewport().get_mouse_position())


func is_alt_detail_active() -> bool:
	return _alt_detail_active


## 成员构成与行动意图变化时刷新悬浮面板；只比较兵种/骑乘/身份和意图文本。
## 模式前缀保证按住/松开 Alt 时无需移动鼠标也会重建面板。
func _party_composition_signature(party: PartyData) -> String:
	var parts: Array[String] = [
		"D" if _alt_detail_active else "S",
		_party_activity_text(party),
		party.leader_noble_id,
		party.family_id,
		# 速度变化（例如换乘/配置调整）时也刷新悬浮面板。
		"%.1f" % _get_party_speed(party),
	]
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


## 把部队当前权威运行时字段翻译为可读行动意图。
## 只读取 PartyData / LordData / SettlementData，不修改任何 AI 状态。
func _party_activity_text(party: PartyData) -> String:
	if party == null or _context == null:
		return "暂无行动"

	# 领主战略征召优先于普通巡逻/路线，读取 LordData 的现有状态。
	if _context.lord_manager != null:
		var lord: LordData = _context.lord_manager.get_lord_by_party_id(
			party.party_id
		)
		if lord != null and lord.current_state == "RECRUITING":
			var settlement_id: String = lord.current_target_settlement_id
			var settlement := _context.settlement_manager.get_settlement(
				settlement_id
			) if not settlement_id.is_empty() else null
			if settlement != null:
				return "正在前往征召：%s" % settlement.display_name
			return "正在前往征召"

	# AI 已通过视野发现战场并开始接近。
	if not party.battle_response_id.is_empty():
		if _context.battle_manager != null \
				and _context.battle_manager.get_battle(party.battle_response_id) != null:
			return "正在前往战场"

	var target := _context.party_manager.get_party(party.current_target_id) \
		if not party.current_target_id.is_empty() else null

	# 追击：攻击意图明确指向当前目标。
	if party.attack_intent and target != null:
		return "正在追击：%s" % target.party_name

	# 玩家点击部队后的持续跟随；对敌对目标仍按追击显示。
	if party.current_order == PartyData.OrderType.FOLLOW_PARTY:
		if target != null:
			var pursuing: bool = _context.faction_manager != null \
				and _context.faction_manager.is_party_hostile(
					party.party_id, target.party_id
				)
			return "%s：%s" % [
				"正在追击" if pursuing else "正在跟随", target.party_name
			]
		return "正在跟随目标"

	if party.movement_state == PartyData.MovementState.MOVING:
		var destination := _settlement_at_position(party.target_position)
		if destination != null:
			return "正在前往：%s" % destination.display_name
		match party.ai_type:
			PartyData.PartyAIType.PATROL, PartyData.PartyAIType.GUARD:
				return "正在前往巡逻区域"
			PartyData.PartyAIType.BANDIT:
				return "正在前往巡逻区域"
			_:
				return "正在前往目的地"

	match party.ai_type:
		PartyData.PartyAIType.PATROL, PartyData.PartyAIType.GUARD:
			return "正在附近巡逻"
		_:
			return "暂无行动"


## target_position 落在某个地点上时返回该地点；用于把移动意图显示成具体地名。
func _settlement_at_position(world_position: Vector2) -> SettlementData:
	if _context == null:
		return null
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement != null \
				and settlement.world_position.distance_to(world_position) <= 2.0:
			return settlement
	return null


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

	var height: float = 58.0

	# 所有部队（玩家与 NPC）都显示统一的最终移动速度；停止时同样保留。
	var speed_label := _make_label(
		"移动速度：%.1f" % _get_party_speed(party), 14
	)
	speed_label.name = "PartyHoverSpeed"
	speed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_content.add_child(speed_label)
	height += HOVER_PANEL_LINE_HEIGHT
	# 指挥贵族与家族归属始终显示；构成详情仍只在按住 Alt 时展开。
	var leader_noble := _context.noble_manager.get_noble(party.leader_noble_id) \
		if _context.noble_manager != null and not party.leader_noble_id.is_empty() \
		else null
	if leader_noble != null:
		var house := _context.house_manager.get_house(leader_noble.house_id) \
			if _context.house_manager != null else null
		var politics := "%s · %s" % [
			leader_noble.display_name, leader_noble.get_rank_text()
		]
		if house != null:
			politics += " · %s" % house.house_name
		var politics_label := _make_label(politics, 13)
		politics_label.name = "PartyHoverPolitics"
		politics_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hover_content.add_child(politics_label)
		height += HOVER_PANEL_LINE_HEIGHT

	# 行动意图由现有 AI/移动字段推导，UI 只读取展示，不修改行为。
	var activity_label := _make_label(
		"行动：%s" % _party_activity_text(party), 14
	)
	activity_label.name = "PartyHoverActivity"
	activity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_content.add_child(activity_label)
	height += HOVER_PANEL_LINE_HEIGHT

	# 默认只显示名称；按住左 Alt 才展开总人数与兵种构成。
	if _alt_detail_active:
		var separator := HSeparator.new()
		separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hover_content.add_child(separator)

		var lines: Array[String] = ["总人数：%d" % party.member_unit_ids.size()]
		var composition := _party_composition_lines(party)
		if composition.is_empty():
			composition.append("无成员")
		lines.append_array(composition)
		for line: String in lines:
			var label := _make_label(line, 14)
			label.name = "PartyHoverDetail"
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_hover_content.add_child(label)
		height += float(lines.size() + 1) * HOVER_PANEL_LINE_HEIGHT

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
	var battles: Array[BattleSession] = _context.battle_manager.get_active_battles()
	var active_ids: Dictionary = {}
	for battle: BattleSession in battles:
		active_ids[battle.battle_id] = true
		_ensure_battle_marker(battle)

	# 只删除已经结束或不存在的战斗标记，不影响其他战斗。
	for battle_id_value: Variant in _battle_markers.keys():
		var battle_id: String = str(battle_id_value)
		if active_ids.has(battle_id):
			continue
		var stale := _battle_markers.get(battle_id) as BattleMarker
		if stale != null and is_instance_valid(stale):
			stale.queue_free()
		_battle_markers.erase(battle_id)

	_update_battle_participant_icons(battles)
	# 战斗信息面板不再自动常驻，只由鼠标悬浮对应战斗标记触发。
	if not _battle_mouse_hover_enabled or _is_input_blocked() \
			or _battle_transition_started:
		_hide_battle_hover()
	else:
		_apply_battle_hover(get_global_mouse_position(), battles)


## 供输入与自动化测试共用：在给定世界坐标上检测并显示对应战斗信息。
func _apply_battle_hover(
	world_position: Vector2, battles: Array[BattleSession] = []
) -> void:
	var battle := _find_battle_at(world_position, battles)
	if battle == null:
		_hide_battle_hover()
		return
	_hovered_battle_id = battle.battle_id
	_refresh_battle_summary(battle)


## 同时命中多个标记时选择距离鼠标最近的一场。
func _find_battle_at(
	world_position: Vector2, battles: Array[BattleSession] = []
) -> BattleSession:
	var candidates: Array[BattleSession] = battles
	if candidates.is_empty() and _context != null:
		candidates = _context.battle_manager.get_active_battles()
	var best: BattleSession = null
	var best_distance: float = BATTLE_MARKER_HOVER_RADIUS
	for battle: BattleSession in candidates:
		if battle == null:
			continue
		var distance := world_position.distance_to(battle.world_position)
		if distance <= best_distance:
			best_distance = distance
			best = battle
	return best


func _hide_battle_hover() -> void:
	var already_hidden: bool = _hovered_battle_id.is_empty() \
		and (_battle_summary_panel == null or not _battle_summary_panel.visible) \
		and _battle_summary_text.is_empty()
	if already_hidden:
		return
	_hovered_battle_id = ""
	_refresh_battle_summary(null)


## 测试入口：不依赖真实鼠标位置，直接悬浮某场战斗。
func apply_battle_hover_for_test(world_position: Vector2) -> void:
	_apply_battle_hover(world_position)


func clear_battle_hover_for_test() -> void:
	_hide_battle_hover()


## 测试入口：关闭真实鼠标自动悬浮，避免无显示器/固定鼠标位置造成非确定性。
func set_battle_mouse_hover_for_test(enabled: bool) -> void:
	_battle_mouse_hover_enabled = enabled
	if not enabled:
		_hide_battle_hover()


func get_hovered_battle_id() -> String:
	return _hovered_battle_id


## 汇总面板一次只展示一场战斗：优先玩家屏幕战斗，否则取战斗 ID 最小的一场。
## 该函数仅保留给旧测试/兼容入口，不再驱动悬浮显示。
func _get_primary_battle(battles: Array[BattleSession] = []) -> BattleSession:
	if _context == null:
		return null
	if _context.battle_manager.current_battle != null:
		return _context.battle_manager.current_battle
	var active: Array[BattleSession] = battles
	if active.is_empty():
		active = _context.battle_manager.get_active_battles()
	return active[0] if not active.is_empty() else null


func _ensure_battle_marker(battle: BattleSession) -> void:
	var marker := _battle_markers.get(battle.battle_id) as BattleMarker
	if marker == null or not is_instance_valid(marker):
		marker = BattleMarker.new()
		world_entities.add_child(marker)
		marker.setup(battle.battle_id, battle.world_position)
		_battle_markers[battle.battle_id] = marker
	else:
		marker.set_battle_position(battle.world_position)
	marker.set_alive_count(_count_battle_alive(battle))


## 每场战斗只隐藏自己参战部队的图标；未参战部队始终显示。
## 停留在地点上的部队同时隐藏普通图标，避免与地点下方旗帜重复显示。
func _update_battle_participant_icons(battles: Array[BattleSession]) -> void:
	for party_id_value: Variant in _party_icons.keys():
		var party_id: String = str(party_id_value)
		var icon := _party_icons.get(party_id) as PartyIcon
		if icon == null or not is_instance_valid(icon):
			continue
		# 部队被消灭/解散后清理遗留图标，避免继续显示已不存在的部队。
		if _context.party_manager.get_party(party_id) == null:
			_party_icons.erase(party_id)
			icon.queue_free()
			continue
		# 被俘期间玩家原部队不在地图上显示；逃脱后位置更新并自动恢复。
		if party_id == _context.player_party_id \
				and _context.captivity_manager.is_player_captive():
			icon.visible = false
			continue
		var involved_in_battle: bool = false
		for battle: BattleSession in battles:
			if battle.is_party_involved(party_id):
				involved_in_battle = true
				break
		icon.visible = not involved_in_battle \
			and not _stationed_party_ids.has(party_id)


func _refresh_battle_summary(battle: BattleSession) -> void:
	if _battle_summary_panel == null:
		return
	if battle == null:
		_battle_summary_panel.visible = false
		if _battle_summary_content != null:
			for child: Node in _battle_summary_content.get_children():
				_battle_summary_content.remove_child(child)
				child.queue_free()
		_battle_summary_signature = ""
		_battle_summary_text = ""
		return
	var lines := _build_battle_summary_lines(battle)
	var text: String = "\n".join(lines)
	if text != _battle_summary_signature:
		_battle_summary_signature = text
		_battle_summary_text = text
		_rebuild_battle_summary(battle)
	_battle_summary_title.text = "战斗 · 已交战 %d 小时 · 存活 %d" % [
		battle.offscreen_settlements_done,
		_count_battle_alive(battle),
	]

	var show_panel: bool = not _is_input_blocked() and not _battle_transition_started
	if show_panel:
		show_panel = _position_battle_summary(battle)
	_battle_summary_panel.visible = show_panel


## 按 side_index 建列；列内再按该战斗侧的参战部队纵向排列。
func _rebuild_battle_summary(battle: BattleSession) -> void:
	if _battle_summary_content == null or battle == null:
		return
	for child: Node in _battle_summary_content.get_children():
		_battle_summary_content.remove_child(child)
		child.queue_free()

	var sides := battle.get_side_indices()
	var max_lines: int = 1
	for side_position: int in range(sides.size()):
		var side_index: int = sides[side_position]
		var column := VBoxContainer.new()
		column.name = "BattleSummarySide_%d" % side_index
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.custom_minimum_size = Vector2(BATTLE_SUMMARY_COLUMN_WIDTH, 0.0)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 1)
		_battle_summary_content.add_child(column)

		var header := _make_label("战斗侧 %d" % (side_position + 1), 14)
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.add_theme_color_override("font_color", Color("#f0d8a0"))
		column.add_child(header)
		var line_count: int = 1

		var party_ids: Array[String] = battle.get_side_party_ids(side_index)
		for party_position: int in range(party_ids.size()):
			var party_id: String = party_ids[party_position]
			var party := _context.party_manager.get_party(party_id)
			var party_label := _make_label(
				party.party_name if party != null else party_id, 15
			)
			party_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if party_position > 0:
				party_label.add_theme_color_override("font_color", Color("#cfe0f0"))
			column.add_child(party_label)
			line_count += 1

			var composition := _battle_party_composition(battle, party_id)
			if composition.is_empty():
				composition.append("无存活人员")
			for entry: String in composition:
				var entry_label := _make_label("  • %s" % entry, 14)
				entry_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
				column.add_child(entry_label)
				line_count += 1

		max_lines = maxi(max_lines, line_count)

	var side_count: int = maxi(1, sides.size())
	var width: float = maxf(
		BATTLE_SUMMARY_WIDTH,
		float(side_count) * BATTLE_SUMMARY_COLUMN_WIDTH
		+ float(maxi(0, side_count - 1) * BATTLE_SUMMARY_COLUMN_GAP)
		+ 28.0
	)
	var height: float = 66.0 + float(max_lines) * 20.0
	_battle_summary_panel.custom_minimum_size = Vector2(width, height)


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


func _position_battle_summary(battle: BattleSession) -> bool:
	if battle == null or _battle_summary_panel == null:
		return false
	var marker := _battle_markers.get(battle.battle_id) as BattleMarker
	if marker == null or not is_instance_valid(marker):
		return false
	var screen_position: Vector2 = marker.get_global_transform_with_canvas().origin
	var viewport_size := get_viewport_rect().size
	var offscreen_margin: float = 60.0
	if screen_position.x < -offscreen_margin \
			or screen_position.y < -offscreen_margin \
			or screen_position.x > viewport_size.x + offscreen_margin \
			or screen_position.y > viewport_size.y + offscreen_margin:
		return false
	var panel_size := Vector2(
		maxf(_battle_summary_panel.custom_minimum_size.x, BATTLE_SUMMARY_WIDTH),
		maxf(_battle_summary_panel.custom_minimum_size.y, 60.0)
	)
	var desired := screen_position + Vector2(26.0, 26.0)
	desired.x = clampf(desired.x, 8.0, maxf(8.0, viewport_size.x - panel_size.x - 8.0))
	desired.y = clampf(desired.y, 56.0, maxf(56.0, viewport_size.y - panel_size.y - 8.0))
	_battle_summary_panel.position = desired
	return true


## 汇总面板当前目标战斗的战斗标记（兼容旧测试入口）。
func get_battle_marker() -> BattleMarker:
	var battle := _get_primary_battle()
	if battle == null:
		return null
	return _battle_markers.get(battle.battle_id) as BattleMarker


func get_battle_marker_count() -> int:
	return _battle_markers.size()


func get_battle_marker_for(battle_id: String) -> BattleMarker:
	return _battle_markers.get(battle_id) as BattleMarker


func get_battle_summary_text() -> String:
	return _battle_summary_text


## 当前汇总面板按 side_index 生成的列数；供 UI 测试核对多侧动态分列。
func get_battle_summary_column_count() -> int:
	if _battle_summary_content == null:
		return 0
	var count: int = 0
	for child: Node in _battle_summary_content.get_children():
		if child is VBoxContainer:
			count += 1
	return count


## 返回每一列对应的 side_index（按 BattleSession.get_side_indices() 顺序）。
func get_battle_summary_side_indices() -> Array[int]:
	var result: Array[int] = []
	if _battle_summary_content == null:
		return result
	for child: Node in _battle_summary_content.get_children():
		if not child is VBoxContainer:
			continue
		var column := child as VBoxContainer
		var suffix: String = column.name.trim_prefix("BattleSummarySide_")
		result.append(int(suffix))
	return result


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


## 测试与调试用：当前正在前往、尚未抵达的地点 ID。
func get_pending_settlement_interaction_id() -> String:
	return _pending_settlement_interaction_id


func apply_hover_for_test(world_position: Vector2) -> void:
	_apply_party_hover(world_position)


func clear_hover_for_test() -> void:
	_hide_party_hover()


## 测试接口：按世界坐标执行一次悬浮描边目标识别。
func apply_hover_outline_for_test(world_position: Vector2) -> void:
	_apply_hover_outline_at(world_position)


func clear_hover_outline_for_test() -> void:
	_set_hover_outline("", "")


func get_hover_outline_party_id() -> String:
	return _hover_outline_party_id


func get_hover_outline_settlement_id() -> String:
	return _hover_outline_settlement_id


func get_settlement_icon(settlement_id: String) -> SettlementIcon:
	return _settlement_icons.get(settlement_id) as SettlementIcon


func is_hover_panel_visible() -> bool:
	return _hover_panel != null and _hover_panel.visible


func _build_save_panel() -> void:
	_save_panel = WorldMapSavePanelScript.new()
	_save_panel.name = "SaveOverlay"
	_save_panel.closed.connect(_on_save_closed)
	_ui_root.add_child(_save_panel)


# ---------------------------------------------------------------------------
# 百科：王国 → 家族 → 贵族/封地
# ---------------------------------------------------------------------------


func _build_encyclopedia_panel() -> void:
	_encyclopedia_panel = WorldMapEncyclopediaScript.new()
	_encyclopedia_panel.name = "EncyclopediaOverlay"
	_encyclopedia_panel.setup(_context)
	_encyclopedia_panel.closed.connect(_on_encyclopedia_closed)
	_ui_root.add_child(_encyclopedia_panel)


func _on_encyclopedia_pressed() -> void:
	if _encyclopedia_panel == null or _encyclopedia_panel.is_open():
		return
	# 建筑信息面板打开时仍可查看百科；其他覆盖层会互相阻塞。
	if _has_open_modal(true):
		return
	_encyclopedia_panel.open()
	_overlays.acquire_pause("encyclopedia")
	_set_time_buttons_enabled(false)
	_update_time_ui()


func _on_close_encyclopedia_pressed() -> void:
	if _encyclopedia_panel == null:
		return
	_encyclopedia_panel.close()


func _on_encyclopedia_closed() -> void:
	_overlays.release_pause("encyclopedia")
	_refresh_time_buttons()
	_update_time_ui()


func _refresh_encyclopedia_if_needed() -> void:
	if _encyclopedia_panel != null:
		_encyclopedia_panel.refresh_if_needed()


## 门面：既有测试按家族数据直接验证徽章生成。
func _make_house_badge(house: HouseData) -> Control:
	if _encyclopedia_panel == null:
		return null
	return _encyclopedia_panel.make_house_badge(house)


func _connect_time_signals() -> void:
	if not TimeManager.world_speed_changed.is_connected(_on_world_speed_changed):
		TimeManager.world_speed_changed.connect(_on_world_speed_changed)
	if not TimeManager.world_time_changed.is_connected(_on_world_time_changed):
		TimeManager.world_time_changed.connect(_on_world_time_changed)
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_update_time_ui):
		viewport.size_changed.connect(_update_time_ui)


func _update_camera(delta: float) -> void:
	# WASD / 方向键：自由平移。UI 打开或战斗切换期间不响应。
	_apply_camera_input(delta, _read_camera_pan_input())

	var captive: bool = _context != null \
		and _context.captivity_manager.is_player_captive()
	# 被俘期间镜头必须跟随押送部队，不允许停留在自由视角。
	if _camera_mode != CameraMode.FOLLOW_PLAYER and not captive:
		# 自由镜头保持当前位置，只受地图边界限制；玩家部队继续移动也不会拉回。
		camera.position = _clamp_camera_position(camera.position)
		return

	var focus_position: Vector2 = _player_party.world_position
	if captive:
		# 被俘期间镜头跟随押送部队；逃脱后这里自动回到玩家部队。
		var captor := _context.party_manager.get_party(
			_context.captivity_manager.get_captor_party_id()
		)
		if captor != null:
			focus_position = captor.world_position
	var desired := _clamp_camera_position(focus_position)
	var weight: float = 1.0 - exp(-CAMERA_FOLLOW_SPEED * delta)
	camera.position = camera.position.lerp(desired, weight)


## 读取键盘平移输入。WASD 与方向键等价；W 向上、A 向左、S 向下、D 向右。
func _read_camera_pan_input() -> Vector2:
	var pan := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if Input.is_physical_key_pressed(KEY_W):
		pan.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		pan.y += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		pan.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		pan.x += 1.0
	return pan.limit_length(1.0)


## 把平移输入应用到镜头；返回是否实际移动。
## 归一化后按当前缩放换算，保证放大/缩小后屏幕上的平移速度接近。
func _apply_camera_input(delta: float, pan: Vector2) -> bool:
	if _context == null or _player_party == null or pan == Vector2.ZERO:
		return false
	if _is_input_blocked() or _battle_transition_started:
		return false
	pan_camera(pan, delta)
	return true


## 进入自由镜头并平移。public，供输入与自动化测试共用方向/速度验证。
func pan_camera(direction: Vector2, delta: float) -> void:
	if _context == null or direction == Vector2.ZERO or delta <= 0.0:
		return
	_camera_mode = CameraMode.FREE_CAMERA
	var zoom_scale: float = maxf(camera.zoom.x, 0.01)
	var step: Vector2 = direction.normalized() * CAMERA_PAN_SPEED * delta / zoom_scale
	camera.position = _clamp_camera_position(camera.position + step)


func is_free_camera() -> bool:
	return _camera_mode == CameraMode.FREE_CAMERA


func get_camera_mode_name() -> String:
	return "FREE_CAMERA" if _camera_mode == CameraMode.FREE_CAMERA \
		else "FOLLOW_PLAYER"


## 镜头中心限制在地图边界内；地图小于视野时居中显示。
func _clamp_camera_position(desired: Vector2) -> Vector2:
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
	return desired


func _set_camera_zoom(value: float) -> void:
	var zoom_value: float = clampf(value, CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX)
	camera.zoom = Vector2(zoom_value, zoom_value)


## 只由玩家主动点击地点调用；设置当前地点并打开面板。
func _open_settlement(settlement: SettlementData) -> void:
	_pending_settlement_interaction_id = ""
	_settlement_latch_id = settlement.settlement_id
	_player_party.focus_party_id = ""
	_context.world_map_manager.stop_party(_context.player_party_id)
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	_overlays.acquire_pause("settlement")

	_settlement_name_label.text = settlement.display_name
	_settlement_type_label.text = _settlement_type_text(settlement.settlement_type)
	var is_village: bool = (
		settlement.settlement_type == SettlementData.SettlementType.VILLAGE
	)
	var is_town: bool = (
		settlement.settlement_type == SettlementData.SettlementType.TOWN
	)
	_settlement_enter_button.visible = is_village
	_settlement_enter_button.disabled = not is_village
	# 村庄入口是“购买补给”，城镇入口是“交易市场”；城堡没有市场。
	var has_market: bool = is_village or is_town
	_settlement_market_button.visible = has_market
	_settlement_market_button.disabled = not has_market
	_settlement_market_button.text = "购买补给" if is_village else "交易市场"
	# 酒馆只存在于城镇。
	_settlement_tavern_button.visible = is_town
	_settlement_tavern_button.disabled = not is_town
	if _tavern_panel != null:
		# 打开/切换地点时清理上一次酒馆状态，避免残留出售预览或视图。
		_tavern_panel.reset()
	if _prisoner_sale_panel != null and _prisoner_sale_panel.visible:
		_prisoner_sale_panel.reset()
	if _mercenary_recruit_panel != null and _mercenary_recruit_panel.visible:
		_mercenary_recruit_panel.reset()
	_show_settlement_info_view()
	_refresh_settlement_info(settlement)
	_settlement_recruit_status_label.text = ""
	_settlement_panel.visible = true
	_set_time_buttons_enabled(false)
	_update_time_ui()


## 地点面板只读权威数据；采邑按钮仅对“玩家拥有的村庄”显示。
func _refresh_settlement_info(settlement: SettlementData) -> void:
	if settlement == null:
		return
	# 领地所有权属于家族：面板只显示家族名称，不显示个人贵族。
	var owner_house := _context.house_manager.get_house(
		settlement.owner_house_id
	) if _context.house_manager != null else null
	var owner_name: String = owner_house.house_name if owner_house != null else "无主"
	_settlement_owner_label.text = "所有者：%s" % owner_name
	var family_name: String = "无"
	if owner_house != null:
		family_name = owner_house.house_name
		var kingdom := _context.kingdom_manager.get_kingdom_for_house(
			owner_house.house_id
		)
		if kingdom != null:
			family_name += "（%s）" % kingdom.kingdom_name
	elif not settlement.family_id.is_empty():
		var family := _context.family_registry.get_config(settlement.family_id)
		family_name = family.display_name if family != null else settlement.family_id
	_settlement_family_label.text = "家族：%s" % family_name
	_settlement_population_label.text = "人口：%d" % settlement.population
	_settlement_prosperity_label.text = "繁荣度：%d" % settlement.prosperity
	_settlement_tax_label.text = "预计每日税收：%d" % settlement.tax_income_per_day
	var is_village: bool = (
		settlement.settlement_type == SettlementData.SettlementType.VILLAGE
	)
	var is_town: bool = (
		settlement.settlement_type == SettlementData.SettlementType.TOWN
	)
	# 市场只通过地点类型判断：村庄只卖补给，城镇另有马匹；城堡没有市场。
	var has_market: bool = is_village or is_town
	_settlement_market_button.visible = has_market
	_settlement_market_button.disabled = not has_market
	_settlement_market_button.text = "购买补给" if is_village else "交易市场"
	if is_village:
		_settlement_fief_label.text = "采邑储备：%d / %d 组" % [
			settlement.fief_recruitment_stock,
			settlement.fief_recruitment_capacity,
		]
	else:
		_settlement_fief_label.text = "采邑储备：不适用"

	var player_lord: LordData = _context.get_player_lord()
	# 授权完全复用封地管理器的家族所有权判断，UI 不复制规则。
	var owns: bool = is_village and player_lord != null \
		and _context.fief_recruitment_manager != null \
		and _context.fief_recruitment_manager.is_authorized_owner(
			settlement, player_lord.lord_id
		)
	_settlement_recruit_button.visible = owns
	_settlement_recruit_button.disabled = not owns \
		or settlement.fief_recruitment_stock <= 0
	_settlement_recruit_button.text = "征召 1 组采邑（6 人，剩 %d 组）" \
		% settlement.fief_recruitment_stock


func _on_settlement_recruit_pressed() -> void:
	var settlement := _context.settlement_manager.get_settlement(
		_settlement_latch_id
	)
	if settlement == null:
		return
	var player_lord: LordData = _context.get_player_lord()
	if player_lord == null:
		_settlement_recruit_status_label.text = "没有有效的玩家领主身份"
		return
	var success: bool = _context.fief_recruitment_manager.recruit_group(
		settlement.settlement_id, player_lord.lord_id
	)
	if success:
		_settlement_recruit_status_label.text = "已征召 1 组采邑，共 6 人。"
	else:
		_settlement_recruit_status_label.text = \
			_context.fief_recruitment_manager.last_error
	# 无论成功失败都以当前权威数据刷新，重复点击不会产生额外单位。
	_refresh_settlement_info(settlement)


func _on_settlement_leave_pressed() -> void:
	# 市场打开时正常流程不可见地点面板；这里兜底，避免残留覆盖层。
	if _market_panel != null and _market_panel.visible:
		_market_panel.close()
	if _tavern_panel != null:
		_tavern_panel.reset()
	if _prisoner_sale_panel != null and _prisoner_sale_panel.visible:
		_prisoner_sale_panel.reset()
	if _mercenary_recruit_panel != null and _mercenary_recruit_panel.visible:
		_mercenary_recruit_panel.reset()
	_show_settlement_info_view()
	_settlement_panel.visible = false
	_overlays.release_pause("settlement")
	# 不恢复时间：离开地点后仍保持暂停，玩家需主动选择 1x / 2x。
	_refresh_time_buttons()
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
	_pending_settlement_interaction_id = ""
	GameManager.current_settlement_id = settlement_id
	GameManager.small_scene_return_base_speed = TimeManager.get_base_world_speed()

	# 先压入 small_scene 暂停，再释放地点面板暂停，保证切换期间世界不恢复运行。
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)
	TimeManager.push_pause(GameManager.PAUSE_REASON_SMALL_SCENE)
	if _tavern_panel != null:
		_tavern_panel.reset()
	if _prisoner_sale_panel != null and _prisoner_sale_panel.visible:
		_prisoner_sale_panel.reset()
	if _mercenary_recruit_panel != null and _mercenary_recruit_panel.visible:
		_mercenary_recruit_panel.reset()
	_show_settlement_info_view()
	_settlement_panel.visible = false
	_overlays.release_pause("settlement")

	var error: Error = SceneManager.change_scene(scene_path)
	if error != OK:
		TimeManager.pop_pause(GameManager.PAUSE_REASON_SMALL_SCENE)
		_overlays.acquire_pause("settlement")
		_settlement_panel.visible = true
		_settlement_entry_pending = false
		push_error("无法进入村庄场景（错误码 %s）" % error)
		return false

	_settlement_entry_pending = false
	EventBus.settlement_entered.emit(settlement_id, _context.player_party_id)
	return true


## 只有玩家主动点击地点后创建的 pending 状态才会在真正抵达时打开面板。
## 普通移动、追逐或途径村庄不会创建该状态。
func _check_pending_settlement_interaction() -> void:
	if _pending_settlement_interaction_id.is_empty():
		return
	if _context == null or _player_party == null or _battle_transition_started:
		_pending_settlement_interaction_id = ""
		return
	var settlement := _context.settlement_manager.get_settlement(
		_pending_settlement_interaction_id
	)
	if settlement == null or not _player_party.is_available_for_world():
		_pending_settlement_interaction_id = ""
		return
	# 其他面板（存档/部队/遭遇等）打开时不消费 pending，避免误触发。
	if _is_input_blocked():
		return

	var distance: float = _player_party.world_position.distance_to(
		settlement.world_position
	)
	# 移动目标仍必须是该地点；被其他系统改写目标后不得继续等待。
	var target_matches: bool = (
		_player_party.target_position.distance_to(settlement.world_position)
		<= SETTLEMENT_INTERACTION_RADIUS
	)
	if _player_party.movement_state == PartyData.MovementState.MOVING:
		if not target_matches:
			_pending_settlement_interaction_id = ""
		return

	if distance <= SETTLEMENT_INTERACTION_RADIUS and target_matches:
		_pending_settlement_interaction_id = ""
		_open_settlement(settlement)
		return
	# 已停止但不在目标地点附近：取消本次地点交互。
	_pending_settlement_interaction_id = ""


func _check_party_interaction() -> void:
	if _battle_transition_started or _context == null or _player_party == null:
		return
	if _has_open_modal(false):
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
		if focus.member_unit_ids.is_empty():
			_player_party.focus_party_id = ""
			return
		# 目标正在战斗：追击关系保留，等战斗结束后重新判断，不打开普通对话。
		if not focus.is_available_for_world():
			if focus.battle_state != PartyData.BattleState.IN_BATTLE:
				_player_party.focus_party_id = ""
			return
		# 敌对目标由 EncounterManager 的主动遭遇流程处理，不在普通对话入口开战。
		if _context.faction_manager.is_party_hostile(
			_player_party.party_id, focus.party_id
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
			or _save_panel.is_open() or _settlement_panel.visible \
			or _party_panel.visible or _party_manage_panel.visible \
			or (_encyclopedia_panel != null and _encyclopedia_panel.is_open()):
		_context.encounter_manager.clear_pending_battle_interaction()
		return

	var battle: BattleSession = _context.battle_manager.get_battle(battle_id)
	if battle == null or not battle.offscreen \
			or battle.is_party_involved(_context.player_party_id):
		_context.encounter_manager.clear_pending_battle_interaction()
		return
	if not _player_party.is_available_for_world() \
			or _player_party.member_unit_ids.is_empty():
		_context.encounter_manager.clear_pending_battle_interaction()
		return
	if _context.battle_manager.get_join_side(
		_context.player_party_id, battle_id
	) < 0:
		_context.encounter_manager.clear_pending_battle_interaction()
		return

	_battle_interaction_id = interaction_id
	_battle_interaction_battle_id = battle_id
	_context.world_map_manager.stop_party(_context.player_party_id)
	_battle_interaction_summary_label.text = _battle_interaction_summary(battle)
	_battle_interaction_status_label.text = ""
	_battle_interaction_panel.visible = true

	_overlays.acquire_pause("battle_interaction")
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
	var battle: BattleSession = _context.battle_manager.get_battle(battle_id)
	if battle == null or not battle.offscreen \
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
	if not _context.battle_manager.try_join_battle(
		_context.player_party_id, battle_id
	):
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
	_overlays.release_pause("battle_interaction")


func _on_battle_leave_pressed() -> void:
	if _context == null or _battle_interaction_panel == null:
		return
	if not _battle_interaction_panel.visible:
		return
	var pending: Dictionary = _context.encounter_manager.get_pending_battle_interaction()
	var battle_id: String = str(pending.get("battle_id", _battle_interaction_battle_id))

	_battle_interaction_panel.visible = false
	_overlays.release_pause("battle_interaction")
	if not battle_id.is_empty():
		# 记录拒绝，避免玩家停留在交互范围内时反复弹出。
		_context.encounter_manager.decline_battle_interaction(battle_id)
	else:
		_context.encounter_manager.clear_pending_battle_interaction()
	_battle_interaction_id = ""
	_battle_interaction_battle_id = ""
	_refresh_time_buttons()
	_update_time_ui()


## 对话/战斗状态变化时关闭面板，清理本次交互暂停与待处理请求。
func cancel_battle_interaction() -> void:
	if _battle_interaction_panel != null:
		_battle_interaction_panel.visible = false
	_overlays.release_pause("battle_interaction")
	if _context != null:
		_context.encounter_manager.clear_pending_battle_interaction()
	_battle_interaction_id = ""
	_battle_interaction_battle_id = ""
	_refresh_time_buttons()
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
	var battle: BattleSession = _context.battle_manager.get_battle(
		str(pending.get("battle_id", ""))
	)
	if battle == null or not battle.offscreen:
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


## 封地征召成功：在对应部队图标上方浮出提示；日志由 WorldLogManager 独立处理。
func _on_fief_recruited(
	recruiter_party_id: String,
	_settlement_id: String,
	groups: int,
	_is_player_recruiter: bool
) -> void:
	var icon := _party_icons.get(recruiter_party_id) as PartyIcon
	if icon == null or not is_instance_valid(icon):
		return
	icon.show_floating_text("招募了%d组采邑" % maxi(1, groups))


## 玩家或 NPC 在村庄招募冒险者成功：复用部队图标浮动提示。
## 文本由实际招募到的兵种与数量生成，不在 UI 内推断招募结果。
func _on_adventurers_recruited(
	party_id: String,
	_settlement_id: String,
	counts: Dictionary,
	_total: int,
	_is_player_recruiter: bool
) -> void:
	var icon := _party_icons.get(party_id) as PartyIcon
	if icon == null or not is_instance_valid(icon):
		return
	var parts: Array[String] = []
	for config_id_value: Variant in counts:
		var count: int = int(counts[config_id_value])
		if count <= 0:
			continue
		var config_id: String = str(config_id_value)
		var config: UnitConfig = _context.unit_manager.get_unit_config(config_id) \
			if _context != null else null
		var unit_name: String = config.display_name if config != null else config_id
		parts.append("%d 个%s" % [count, unit_name])
	if parts.is_empty():
		return
	icon.show_floating_text("招募了%s" % "、".join(parts))


## NPC 补给采购成功：在部队图标上方浮出一次简要提示，不写玩家世界日志。
func _on_npc_supply_purchased(
	party_id: String, bread_count: int, fodder_count: int
) -> void:
	var icon := _party_icons.get(party_id) as PartyIcon
	if icon == null or not is_instance_valid(icon):
		return
	var parts: Array[String] = []
	if bread_count > 0:
		parts.append("面包+%d" % bread_count)
	if fodder_count > 0:
		parts.append("草料+%d" % fodder_count)
	if parts.is_empty():
		return
	icon.show_floating_text("补给 %s" % " ".join(parts))


func get_party_icon(party_id: String) -> PartyIcon:
	return _party_icons.get(party_id) as PartyIcon


func _on_battle_started(battle_id: String) -> void:
	if _battle_transition_started or _context == null:
		return
	var battle: BattleSession = _context.battle_manager.get_battle(battle_id)
	if battle == null or battle.offscreen or not battle.player_involved:
		return
	_pending_settlement_interaction_id = ""
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
	_hide_attack_confirm()
	_attack_confirm_target_id = ""
	_player_party.focus_party_id = ""
	_context.world_map_manager.stop_party(_context.player_party_id)

	_overlays.acquire_pause("party_dialogue")

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
	# 只针对“被点击部队所在的那一场战斗”判断加入；
	# 世界上其他位置的战斗不影响本次对话。
	var target_battle: BattleSession = _context.battle_manager.get_battle_for_party(
		party.party_id
	)
	var player_battle: BattleSession = _context.battle_manager.get_battle_for_party(
		_context.player_party_id
	)
	var can_join_active: bool = target_battle != null and target_battle.offscreen \
		and _context.battle_manager.can_party_join(
			_context.player_party_id, target_battle.battle_id
		)
	# 加入友军正在进行的战斗是协战，不算“同阵营开战”。
	var same_faction: bool = party.faction_id == _player_party.faction_id \
		and not can_join_active
	var battle_block: String = ""
	if player_battle != null and not can_join_active:
		battle_block = "玩家部队当前正在战斗中"
	elif target_battle != null and not can_join_active:
		battle_block = _active_battle_block_reason(party)
	var unavailable_reason: String = ""
	if not can_join_active and player_battle == null:
		unavailable_reason = _party_unavailable_reason(party)
	if not _player_party.is_available_for_world():
		unavailable_reason = "玩家部队当前无法参战"

	_party_fight_joins_battle = can_join_active
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
	_refresh_time_buttons()
	_update_time_ui()


func _close_party_dialogue() -> void:
	_party_panel.visible = false
	_hide_attack_confirm()
	_attack_confirm_target_id = ""
	_attack_confirm_in_progress = false
	if _party_portrait != null:
		_party_portrait.clear()
	_overlays.release_pause("party_dialogue")


## 目标部队所在战斗无法加入时返回原因；空字符串表示可以正常开始/加入。
## 只检查目标部队自己参与的那场战斗，世界其他战斗不会阻塞本次开战。
func _active_battle_block_reason(enemy: PartyData) -> String:
	if _context == null or enemy == null:
		return ""
	var battle: BattleSession = _context.battle_manager.get_battle_for_party(
		enemy.party_id
	)
	if battle == null:
		return ""
	if _context.battle_manager.get_battle_for_party(_context.player_party_id) != null:
		return "玩家部队当前正在战斗中"
	if not battle.offscreen:
		return "对方正在屏幕战斗中，暂时无法开战"
	if _context.battle_manager.get_join_side(
		_context.player_party_id, battle.battle_id
	) < 0:
		return "对方正在战斗中，靠近战场后可加入战斗"
	return ""


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
	if not _context.battle_manager.try_join_battle(
		_context.player_party_id, battle.battle_id
	):
		_battle_transition_started = false
		_party_status_label.text = "无法加入该战斗"
		return null
	# try_join_battle 已压入战斗暂停；随后再释放对话暂停，避免中间帧恢复世界时间。
	_overlays.release_pause("party_dialogue")
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

	# 玩家已在战斗中时不能再开新战斗。
	var player_battle: BattleSession = _context.battle_manager.get_battle_for_party(
		_context.player_party_id
	)
	if player_battle != null:
		_party_status_label.text = "玩家部队当前正在战斗中"
		return null

	# 目标部队所在战斗：允许加入该场；其他位置的战斗不阻塞开战。
	# 加入友军战斗属于协战，因此先于“同阵营”检查。
	var target_battle: BattleSession = _context.battle_manager.get_battle_for_party(
		enemy.party_id
	)
	var can_join_active: bool = target_battle != null and target_battle.offscreen \
		and _context.battle_manager.can_party_join(
			_context.player_party_id, target_battle.battle_id
		)
	if enemy.faction_id == _player_party.faction_id and not can_join_active:
		_party_status_label.text = "同一阵营无法开战"
		return null
	if target_battle != null:
		if can_join_active:
			return _join_active_battle(target_battle)
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

	# 玩家主动攻击已成功创建战斗：按目标家族与所属王国建立持续敌对关系。
	# 关系维护与派生全部由 FactionManager 负责，UI 不解读政治数据。
	_context.faction_manager.declare_player_hostility_against_party(enemy.party_id)

	# 先由 start_battle 压入战斗暂停，再释放对话暂停，避免中间帧恢复世界时间。
	_overlays.release_pause("party_dialogue")
	_party_panel.visible = false
	return session


func _on_party_fight_pressed() -> void:
	if _attack_confirm_in_progress:
		return
	# 加入友军正在进行的战斗属于协战，不是主动攻击，不弹确认。
	if _party_fight_joins_battle:
		_execute_party_fight()
		return
	_show_attack_confirm()


## 显示主动攻击确认；目标名称来自当前交互部队，取消不会修改任何状态。
func _show_attack_confirm() -> void:
	if _context == null or _attack_confirm_panel == null:
		return
	var enemy := _context.party_manager.get_party(_party_latch_id)
	if enemy == null or enemy.party_id == _context.player_party_id:
		return
	_attack_confirm_target_id = enemy.party_id
	_attack_confirm_label.text = "是否确定向 %s 发起攻击？" % enemy.party_name
	_attack_confirm_panel.visible = true


func _hide_attack_confirm() -> void:
	if _attack_confirm_panel != null:
		_attack_confirm_panel.visible = false


func _on_attack_cancel_pressed() -> void:
	_hide_attack_confirm()
	_attack_confirm_target_id = ""
	_attack_confirm_in_progress = false
	# 返回原部队交互面板；双方状态、HP、成员与阵营关系均未改变。
	if _party_status_label != null:
		_party_status_label.text = ""


func _on_attack_confirm_pressed() -> void:
	if _attack_confirm_in_progress or _attack_confirm_target_id.is_empty():
		return
	var enemy := _context.party_manager.get_party(_attack_confirm_target_id) \
		if _context != null else null
	var invalid_reason := _attack_confirmation_block_reason(enemy)
	if not invalid_reason.is_empty():
		_hide_attack_confirm()
		_party_status_label.text = invalid_reason
		return
	# 立即隐藏并置位，防止连续点击确认创建两场战斗。
	_attack_confirm_in_progress = true
	_hide_attack_confirm()
	var session := begin_battle_with_party()
	if session == null:
		_attack_confirm_in_progress = false
		_attack_confirm_target_id = ""
		return
	_attack_confirm_in_progress = false
	_attack_confirm_target_id = ""
	_enter_battle_after_confirmed_attack(session)


## 确认时重新校验所有可能已经变化的条件，不依赖打开面板时的旧状态。
func _attack_confirmation_block_reason(enemy: PartyData) -> String:
	if _context == null or _player_party == null:
		return "当前无法发起攻击"
	if _battle_transition_started:
		return "战斗正在切换中"
	if enemy == null:
		return "对方已经离开"
	if enemy.party_id == _context.player_party_id:
		return "无法攻击自己的部队"
	if not _player_party.is_available_for_world():
		return "玩家部队当前无法参战"
	if _player_party.member_unit_ids.is_empty():
		return "玩家部队需要至少一名士兵"
	if _context.battle_manager.get_battle_for_party(_context.player_party_id) != null:
		return "玩家部队当前正在战斗中"
	if not enemy.is_available_for_world():
		return _party_unavailable_reason(enemy)
	if enemy.member_unit_ids.is_empty():
		return "对方已经没有可参战士兵"
	if _context.battle_manager.get_battle_for_party(enemy.party_id) != null:
		return "对方正在战斗中，暂时无法发起攻击"
	if _context.faction_manager.is_party_friendly(
		_context.player_party_id, enemy.party_id
	):
		return "对方已成为友军，无法发起攻击"
	return ""


## 主动攻击确认通过后的统一入口：创建/加入战斗并切换场景。
func _execute_party_fight() -> void:
	var session := begin_battle_with_party()
	if session == null:
		return
	_enter_battle_after_confirmed_attack(session)


func _enter_battle_after_confirmed_attack(session: BattleSession) -> void:
	var error: Error = SceneManager.change_scene(SceneManager.BATTLE_SCENE)
	if error != OK:
		_context.battle_manager.finish_battle(
			session.battle_id, BattleSession.BattleResult.ABORTED
		)
		_battle_transition_started = false
		_overlays.acquire_pause("party_dialogue")
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
	if _save_panel.is_open() or _has_open_modal(true):
		return
	_save_panel.open()
	_overlays.acquire_pause("save")
	_set_time_buttons_enabled(false)
	_update_time_ui()


func _on_save_closed() -> void:
	_overlays.release_pause("save")
	_refresh_time_buttons()
	_update_time_ui()


func _on_main_menu_pressed() -> void:
	GameManager.enter_main_menu()


func _on_world_speed_changed(_effective_scale: float) -> void:
	_update_time_ui()


func _on_world_time_changed(_total_seconds: float) -> void:
	_update_time_ui()


## 只有玩家部队真正到达当前移动/跟随目标时自动暂停；NPC 到达不触发。
## 重新下达指令后旧目标不会产生 party_arrived，因此无需额外失效判断。
func _on_party_arrived(party_id: String) -> void:
	if _context == null or _player_party == null \
			or party_id != _context.player_party_id:
		return
	if _battle_transition_started:
		return
	_set_world_speed(TimeManager.SPEED_PAUSED)


func _update_time_ui() -> void:
	if _world_time_label == null:
		return
	# 昼夜窗口只读取世界累计时间；暂停时该值不变，滚动也随之停止。
	if _day_night_clock != null:
		_day_night_clock.set_world_seconds(TimeManager.world_elapsed_seconds)
	var effective := TimeManager.get_effective_world_scale()
	var speed_text := "暂停"
	if is_equal_approx(effective, TimeManager.SPEED_NORMAL):
		speed_text = "1x"
	elif is_equal_approx(effective, TimeManager.SPEED_DOUBLE):
		speed_text = "2x"

	# 窄窗口下缩小居中时间字号，避免与右侧紧凑入口重叠；
	# 时间与倍率文本保持完整，按钮仍显示当前状态。
	# 场景退出时仍可能收到速度变化信号，此时没有可用 viewport。
	var wide_layout: bool = true
	if is_inside_tree():
		wide_layout = get_viewport_rect().size.x >= 1400.0
	_world_time_label.add_theme_font_size_override("font_size", 15 if wide_layout else 11)
	_world_time_label.text = "世界时间：%s    倍率：%s" % [
		TimeManager.get_world_time_text(), speed_text
	]

	if _pause_tip_label != null:
		_pause_tip_label.visible = is_zero_approx(effective)

	if _pause_button != null:
		_pause_button.button_pressed = is_zero_approx(effective)
		_speed_one_button.button_pressed = is_equal_approx(effective, TimeManager.SPEED_NORMAL)
		_speed_two_button.button_pressed = is_equal_approx(effective, TimeManager.SPEED_DOUBLE)


## 大地图最终移动速度的唯一读取入口：调用 WorldMapManager 的统一计算，
## UI 不自行根据成员/坐骑/装备重算。显示格式与悬浮面板保持一致。
func _get_party_speed(party: PartyData) -> float:
	if party == null or _context == null or _context.world_map_manager == null:
		return 0.0
	return _context.world_map_manager.get_effective_movement_speed(party)


func _update_player_info() -> void:
	if _player_info_label == null or _player_party == null:
		return
	var state_text: String = "待命"
	if _context.captivity_manager.is_player_captive():
		state_text = "被俘中"
	elif _player_party.current_order == PartyData.OrderType.FOLLOW_PARTY:
		var target := _context.party_manager.get_party(_player_party.current_target_id)
		state_text = "跟随中：%s" % (target.party_name if target != null else "目标消失")
	elif _player_party.movement_state == PartyData.MovementState.MOVING:
		state_text = "移动中"
	var identity_text: String = ""
	var player_noble := _context.get_player_noble() if _context != null else null
	if player_noble != null:
		var house_name: String = "独立"
		if _context.house_manager != null:
			var house := _context.house_manager.get_house(player_noble.house_id)
			if house != null:
				house_name = house.house_name
		identity_text = "    身份：%s · %s" % [house_name, player_noble.get_rank_text()]
	elif _context != null and not _context.player_identity_name.is_empty():
		# 平民身份没有家族，但身份选择结果仍需在大地图可见。
		identity_text = "    身份：%s（无家族）" % _context.player_identity_name
	_player_info_label.text = "%s    移动速度：%.1f    坐标 (%d, %d)    状态：%s%s" % [
		_player_party.party_name,
		_get_party_speed(_player_party),
		int(round(_player_party.world_position.x)),
		int(round(_player_party.world_position.y)),
		state_text,
		identity_text,
	]


## 左侧被俘栏只展示状态：押送部队、玩家角色 HP 与恢复说明。
## 数据全部来自 CaptivityManager/UnitData，UI 不参与治疗或逃脱结算。
func _update_captive_ui() -> void:
	if _captive_panel == null or _context == null:
		return
	var captive: bool = _context.captivity_manager.is_player_captive()
	_captive_panel.visible = captive
	if not captive:
		return
	var captor := _context.party_manager.get_party(
		_context.captivity_manager.get_captor_party_id()
	)
	_captive_captor_label.text = "押送部队：%s" % (
		captor.party_name if captor != null else "未知"
	)
	var unit := _context.get_player_unit()
	if unit != null:
		_captive_hp_label.text = "生命：%d / %d" % [unit.current_hp, unit.max_hp]
	else:
		_captive_hp_label.text = "生命：未知"


# ---------------------------------------------------------------------------
# 顶部信息栏：金钱、部队移速与 Alt 详细提示
# ---------------------------------------------------------------------------


func _build_top_info_tooltip() -> void:
	_top_info_tooltip = PanelContainer.new()
	_top_info_tooltip.name = "TopInfoTooltip"
	_top_info_tooltip.visible = false
	_top_info_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_info_tooltip.custom_minimum_size = Vector2(340.0, 0.0)
	_ui_root.add_child(_top_info_tooltip)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_top_info_tooltip.add_child(margin)

	_top_info_content = VBoxContainer.new()
	_top_info_content.name = "TopInfoTooltipContent"
	_top_info_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_info_content.add_theme_constant_override("separation", 3)
	margin.add_child(_top_info_content)


## 图标与数值同属一个条目；悬浮事件挂在条目容器上，两者共同触发提示。
func _add_top_info_entry(
	parent: Control, icon_path: String, node_name: String, initial_text: String
) -> Label:
	var entry := HBoxContainer.new()
	entry.name = "%sEntry" % node_name
	entry.mouse_filter = Control.MOUSE_FILTER_STOP
	entry.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	entry.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	entry.add_theme_constant_override("separation", TOP_INFO_ICON_TEXT_GAP)
	parent.add_child(entry)

	var icon := TextureRect.new()
	icon.name = "%sIcon" % node_name
	icon.custom_minimum_size = TOP_INFO_ICON_SIZE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path) as Texture2D
	entry.add_child(icon)

	var label := _make_label(initial_text, 15)
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	entry.add_child(label)

	entry.mouse_entered.connect(_on_top_info_hover.bind(node_name, true))
	entry.mouse_exited.connect(_on_top_info_hover.bind(node_name, false))
	return label


func _on_top_info_hover(kind: String, entered: bool) -> void:
	if entered:
		_top_info_hover_kind = kind
		_top_info_signature = ""
		_refresh_top_info_tooltip()
		_position_top_info_tooltip(get_viewport().get_mouse_position())
		return
	if _top_info_hover_kind == kind:
		_hide_top_info_tooltip()


func _hide_top_info_tooltip() -> void:
	_top_info_hover_kind = ""
	_top_info_signature = ""
	if _top_info_tooltip != null:
		_top_info_tooltip.visible = false


## 每帧同步金币/移速/部队人数；数据变化时顶部悬浮提示也随之更新。
func _update_top_info() -> void:
	if _context == null or _player_party == null:
		return
	if _money_label != null:
		_money_label.text = GoldUtils.format(float(_context.player_profile.gold))
	if _party_speed_label != null:
		_party_speed_label.text = "%.1f" % _get_party_speed(_player_party)
	if _top_party_troop_label != null:
		_top_party_troop_label.text = str(_get_party_troop_counts()["total"])
	if _player_hp_label != null:
		# 顶栏生命值始终读取“当前玩家角色”的真实 UnitData；
		# 被俘治疗与逃脱后都会在下一帧自动反映。
		var unit := _context.get_player_unit()
		_player_hp_label.text = "生命 %d/%d" % [
			unit.current_hp, unit.max_hp
		] if unit != null else "生命 —"
	if _top_info_hover_kind.is_empty():
		return
	_refresh_top_info_tooltip()
	if _top_info_tooltip != null and _top_info_tooltip.visible:
		_position_top_info_tooltip(get_viewport().get_mouse_position())


func _refresh_top_info_tooltip() -> void:
	if _top_info_tooltip == null or _top_info_content == null:
		return
	if _top_info_hover_kind.is_empty() or _context == null or _player_party == null:
		_hide_top_info_tooltip()
		return

	var lines: Array[String] = []
	match _top_info_hover_kind:
		"MoneyLabel":
			lines = _top_info_money_lines()
		"PartySpeedLabel":
			lines = _top_info_speed_lines()
		"PartySizeLabel":
			lines = _top_info_troop_lines()
		_:
			_hide_top_info_tooltip()
			return

	var signature: String = "%s|%s|%s" % [
		"ALT" if _alt_detail_active else "NORMAL",
		_top_info_hover_kind,
		"\n".join(PackedStringArray(lines)),
	]
	if signature == _top_info_signature:
		_top_info_tooltip.visible = true
		return
	_top_info_signature = signature

	for child: Node in _top_info_content.get_children():
		_top_info_content.remove_child(child)
		child.queue_free()
	for line: String in lines:
		var label := _make_label(line, 14)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_top_info_content.add_child(label)

	var height: float = maxf(
		60.0, float(lines.size()) * 21.0 + 20.0
	)
	_top_info_tooltip.custom_minimum_size = Vector2(340.0, height)
	_top_info_tooltip.size = Vector2(340.0, height)
	_top_info_tooltip.visible = true


func _top_info_money_lines() -> Array[String]:
	var lines: Array[String] = []
	var preview: Dictionary = _context.get_daily_balance_preview()
	var net: int = int(preview.get("net", 0))
	if not _alt_detail_active:
		lines.append("预计每日收入：%s" % _format_signed_amount(net))
		return lines

	lines.append("每日收支")
	lines.append("总计 %s" % _format_signed_amount(net))
	lines.append("────────────────")
	var items: Array = preview.get("items", [])
	if items.is_empty():
		lines.append("暂无预计收支项目。")
		return lines
	for item_value: Variant in items:
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value
		lines.append("%s    %s" % [
			str(item.get("label", "未知项目")),
			_format_signed_amount(int(item.get("amount", 0))),
		])
	return lines


func _top_info_speed_lines() -> Array[String]:
	var lines: Array[String] = []
	var breakdown: Dictionary = _context.world_map_manager.get_movement_speed_breakdown(
		_player_party
	)
	var effective: float = float(breakdown.get("effective", 0.0))
	if not _alt_detail_active:
		lines.append("当前部队移速：%.1f" % effective)
		return lines

	lines.append("部队移速：%.1f" % effective)
	lines.append("────────────────")
	var items: Array = breakdown.get("items", [])
	for item_value: Variant in items:
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value
		lines.append("%s：%s" % [
			str(item.get("label", "未知因素")),
			str(item.get("display", "0")),
		])
	lines.append("最终移速：%.1f" % effective)
	return lines


## 玩家部队人数统计：可战斗 / 伤员 / 俘虏互斥，不把伤兵或俘虏算作可战斗。
## 总人数 = 可战斗 + 伤员（已永久死亡的单位不属于当前部队）。
func _get_party_troop_counts() -> Dictionary:
	var combat: int = 0
	var wounded: int = 0
	if _context != null and _player_party != null:
		for unit_id: String in _player_party.member_unit_ids:
			var unit := _context.unit_manager.get_unit(unit_id)
			if unit == null:
				continue
			if unit.is_wounded():
				wounded += 1
			elif unit.is_alive():
				combat += 1
	var prisoners: int = (
		_player_party.prisoner_unit_ids.size() if _player_party != null else 0
	)
	return {
		"combat": combat,
		"wounded": wounded,
		"prisoners": prisoners,
		"total": combat + wounded,
	}


func _top_info_troop_lines() -> Array[String]:
	var counts: Dictionary = _get_party_troop_counts()
	var lines: Array[String] = []
	lines.append("部队")
	lines.append("")
	lines.append("可战斗人数 %d" % int(counts.get("combat", 0)))
	lines.append("")
	lines.append("伤员 %d" % int(counts.get("wounded", 0)))
	lines.append("")
	lines.append("俘虏 %d" % int(counts.get("prisoners", 0)))
	return lines


func _format_signed_amount(amount: int) -> String:
	return "+%d" % amount if amount >= 0 else "-%d" % absi(amount)


func _position_top_info_tooltip(screen_position: Vector2) -> void:
	if _top_info_tooltip == null:
		return
	var viewport_size := get_viewport_rect().size
	var panel_size := Vector2(
		340.0, maxf(_top_info_tooltip.custom_minimum_size.y, 60.0)
	)
	var desired := screen_position + Vector2(18.0, 22.0)
	desired.x = clampf(
		desired.x, 8.0, maxf(8.0, viewport_size.x - panel_size.x - 8.0)
	)
	desired.y = clampf(
		desired.y, 8.0, maxf(8.0, viewport_size.y - panel_size.y - 8.0)
	)
	_top_info_tooltip.position = desired


## 测试接口：返回顶部信息提示当前文本。
func get_top_info_tooltip_text() -> String:
	if _top_info_content == null:
		return ""
	var lines: Array[String] = []
	for child: Node in _top_info_content.get_children():
		var label := child as Label
		if label != null:
			lines.append(label.text)
	return "\n".join(PackedStringArray(lines))


func is_top_info_tooltip_visible() -> bool:
	return _top_info_tooltip != null and _top_info_tooltip.visible


func set_top_info_hover_for_test(kind: String, entered: bool) -> void:
	_on_top_info_hover(kind, entered)


func _set_time_buttons_enabled(enabled: bool) -> void:
	for button: Button in _time_buttons:
		button.disabled = not enabled


func _is_input_blocked() -> bool:
	return _has_open_modal(false)


## 是否有模态覆盖层。ignore_settlement=true 用于“建筑信息面板打开时仍允许
## 使用百科/部队/背包/事件等功能入口”，但不影响时间控制权限。
func _has_open_modal(ignore_settlement: bool = false) -> bool:
	return _overlays.has_blocking_overlay(ignore_settlement)


## 世界时间控制独立于普通 UI 权限：建筑信息面板或任何覆盖层打开时都禁用。
func _refresh_time_buttons() -> void:
	if _time_buttons.is_empty():
		return
	_set_time_buttons_enabled(not _has_open_modal(false))


func _set_full_rect(control: Control) -> void:
	MapUiKitScript.set_full_rect(control)


func _make_label(text: String, font_size: int) -> Label:
	return MapUiKitScript.make_label(text, font_size)


func _make_button(text: String, node_name: String) -> Button:
	return MapUiKitScript.make_button(text, node_name)


## 顶栏入口数量多且要与居中的世界时间并存，使用更紧凑的尺寸，
## 避免在 1280 宽度下挤压中间时间区域。
func _make_top_bar_button(text: String, node_name: String) -> Button:
	var button := _make_button(text, node_name)
	button.custom_minimum_size = Vector2(52.0, 30.0)
	button.add_theme_font_size_override("font_size", 13)
	return button


func _settlement_type_text(type: SettlementData.SettlementType) -> String:
	return MapUiKitScript.settlement_type_text(type)


func _faction_display_name(faction_id: String) -> String:
	if _context != null:
		return _context.faction_manager.get_display_name(faction_id)
	return faction_id if not faction_id.is_empty() else "未知"


func _return_to_main_menu() -> void:
	GameManager.enter_main_menu()
