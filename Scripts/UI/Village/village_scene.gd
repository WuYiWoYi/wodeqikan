class_name VillageScene
extends Node2D
## 村庄小场景控制器。
##
## 只读取 WorldContext 的权威数据；玩家角色复用 UnitData / UnitVisual，
## 不创建第二套角色系统，也不修改玩家装备、部队或存档。
## 本阶段村庄为和平场景：没有敌对部队、没有战斗、没有招募与商店。

signal exit_requested

const UnitVisualScript = preload("res://Scripts/Systems/Combat/unit_visual.gd")
const HorseVisualScript = preload("res://Scripts/Systems/Combat/horse_visual.gd")

const WORLD_SIZE := Vector2(1920.0, 1080.0)
## 可活动区域。走出该区域会开始返回大地图的倒计时。
const PLAYABLE_RECT := Rect2(110.0, 300.0, 1700.0, 700.0)
const PLAYER_START_POSITION := Vector2(960.0, 860.0)
const ELDER_POSITION := Vector2(1260.0, 560.0)
const ELDER_NAME: String = "村庄头人"
const ELDER_CLICK_RADIUS: float = 46.0
const CANDIDATE_CLICK_RADIUS: float = 46.0
const INTERACT_DISTANCE: float = 130.0
## 场景内移动表现速度倍率；不修改 UnitData.move_speed。
const VILLAGE_MOVE_SPEED_MULTIPLIER: float = 2.0

const EXIT_COUNTDOWN_SECONDS: float = 5.0
## 越界容差：必须离开可活动区域 8 px 才开始倒计时，避免边界抖动。
const EXIT_TOLERANCE: float = 8.0

const VILLAGE_ELDER_DIALOGUE_PATH: String = "res://Data/Dialogues/village_elder.tres"
const WORLD_MAP_SCENE: String = "res://Scenes/WorldMap/world_map.tscn"

var _context: WorldContext = null
var _settlement: SettlementData = null
var _player_unit: UnitData = null
var _player_visual: UnitVisual = null
var _npc_visual: UnitVisual = null
var _npc_unit_data: UnitData = null
## 候选人表现：{ candidate_id: UnitVisual } / { candidate_id: Label }。
var _candidate_visuals: Dictionary = {}
var _candidate_labels: Dictionary = {}
## 贵族冒险者单独保存表现：人物按步行呈现，战马是独立场景对象。
## 权威单位数据仍保留骑乘关系，本场景不修改 UnitData / MountInstanceData。
var _noble_candidate: AdventurerCandidateData = null
var _noble_visual: UnitVisual = null
var _noble_mount_visual: HorseVisual = null
var _noble_label: Label = null
var _camera: Camera2D = null
var _camera_rig: SceneCameraRig = null

var _player_position := PLAYER_START_POSITION
var _moving: bool = false
var _facing: float = 1.0
var _dialogue_open: bool = false
var _dialogue_pause_active: bool = false
var _exit_timer: float = 0.0
var _returning: bool = false
var _auto_return_enabled: bool = true

var _test_input := Vector2.ZERO
var _has_test_input: bool = false

var _ui_root: Control = null
var _village_label: Label = null
var _hint_label: Label = null
var _status_label: Label = null
var _exit_panel: PanelContainer = null
var _exit_label: Label = null

var _dialogue_panel: PanelContainer = null
var _dialogue_speaker_label: Label = null
var _dialogue_text_label: Label = null
var _dialogue_choices: VBoxContainer = null

## 与大地图共用的世界日志面板。
var _world_log_panel: WorldLogPanel = null
## 与大地图完全相同的市场组件：村庄只提供面包/草料，库存与 WorldContext 共享。
var _market_panel: MarketPanel = null
var _market_pause_active: bool = false


func _ready() -> void:
	_context = GameManager.world_context
	if _context == null:
		push_error("村庄场景缺少 WorldContext")
		call_deferred("_abort_to_world_map")
		return

	_settlement = _resolve_settlement()
	_player_unit = _resolve_player_unit()
	if _player_unit == null:
		push_error("村庄场景找不到玩家角色")
		call_deferred("_abort_to_world_map")
		return

	_build_camera()
	_build_actor_visuals()
	_build_adventurer_candidates()
	_build_ui()
	_update_header()
	queue_redraw()


func _exit_tree() -> void:
	# 异常退出时清理本次场景的暂停，避免世界永久暂停。
	if _dialogue_pause_active:
		TimeManager.pop_pause(GameManager.PAUSE_REASON_WORLD_DIALOGUE)
		_dialogue_pause_active = false
	if _market_pause_active:
		TimeManager.pop_pause(GameManager.PAUSE_REASON_UI_PANEL)
		_market_pause_active = false
	TimeManager.pop_pause(GameManager.PAUSE_REASON_SMALL_SCENE)


# ---------------------------------------------------------------------------
# 场景搭建
# ---------------------------------------------------------------------------


func _resolve_settlement() -> SettlementData:
	var settlement_id: String = GameManager.current_settlement_id
	if not settlement_id.is_empty():
		var settlement := _context.settlement_manager.get_settlement(settlement_id)
		if settlement != null \
				and settlement.settlement_type == SettlementData.SettlementType.VILLAGE:
			return settlement
	# 直接启动场景时退化到第一个村庄，避免测试/调试时立即退出。
	for candidate: SettlementData in _context.settlement_manager.get_all_settlements():
		if candidate.settlement_type == SettlementData.SettlementType.VILLAGE:
			return candidate
	return null


## 优先玩家角色；旧存档没有玩家角色时退化到第一名成员。
func _resolve_player_unit() -> UnitData:
	var party := _context.get_player_party()
	if party == null:
		return null
	for unit_id: String in party.member_unit_ids:
		var unit := _context.unit_manager.get_unit(unit_id)
		if unit != null and unit.is_player_character:
			return unit
	for unit_id: String in party.member_unit_ids:
		var unit := _context.unit_manager.get_unit(unit_id)
		if unit != null:
			return unit
	return null


func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "Camera2D"
	_camera.enabled = true
	add_child(_camera)
	_camera.make_current()

	# 与战斗场景共用同一套视野基准与边界规则。
	_camera_rig = SceneCameraRig.new()
	_camera_rig.setup(_camera, Rect2(Vector2.ZERO, WORLD_SIZE))
	_camera_rig.snap_to(_player_position)


func _build_actor_visuals() -> void:
	_player_visual = UnitVisualScript.new()
	_player_visual.name = "PlayerVisual"
	_player_visual.position = _player_position
	_player_visual.z_index = 100
	add_child(_player_visual)
	_player_visual.setup(_player_unit, _visual_equipment_configs(_player_unit))
	# 只隐藏本次场景的武器表现；UnitData.equipment 不修改。
	_player_visual.set_weapon_visible(false)
	_player_visual.set_facing(_facing)
	_player_visual.reset_locomotion()

	# 村庄头人使用运行时 UnitData 与同一 UnitVisual，但不注册进 UnitManager。
	_npc_unit_data = UnitData.new()
	_npc_unit_data.unit_id = "village_elder"
	_npc_unit_data.display_name = ELDER_NAME
	_npc_unit_data.faction_id = "FACTION_LOCAL"
	_npc_unit_data.is_player_character = false

	_npc_visual = UnitVisualScript.new()
	_npc_visual.name = "VillageElderVisual"
	_npc_visual.position = ELDER_POSITION
	_npc_visual.z_index = 100
	add_child(_npc_visual)
	_npc_visual.setup(_npc_unit_data)
	_npc_visual.set_facing(-1.0)
	_npc_visual.reset_locomotion()

	var npc_label := _make_label(ELDER_NAME, 14)
	npc_label.name = "VillageElderNameLabel"
	npc_label.position = ELDER_POSITION + Vector2(-60.0, -78.0)
	npc_label.size = Vector2(120.0, 20.0)
	npc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	npc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(npc_label)


## 从权威候选人数据生成村庄 NPC 表现；不创建 UnitManager 单位。
func _build_adventurer_candidates() -> void:
	if _settlement == null or _context == null:
		return
	for candidate: AdventurerCandidateData in _settlement.adventurer_candidates:
		if candidate == null:
			continue
		var spawn_position: Vector2 = candidate.world_position
		if spawn_position == Vector2.ZERO:
			spawn_position = AdventurerRecruitmentManager.CANDIDATE_POSITIONS[
				_candidate_visuals.size()
				% AdventurerRecruitmentManager.CANDIDATE_POSITIONS.size()
			]
		var unit := UnitData.new()
		unit.unit_id = candidate.candidate_id
		unit.config_id = candidate.unit_config_id
		unit.display_name = candidate.display_name
		unit.faction_id = _settlement.faction_id
		unit.appearance = candidate.appearance.duplicate(true)
		unit.family_id = str(candidate.appearance.get("family_id", ""))

		var visual := UnitVisualScript.new()
		visual.name = "AdventurerCandidateVisual_%s" % candidate.candidate_id
		# 必须使用候选人数据中的候选位置；节点自身的 position 是村庄根节点坐标。
		visual.position = spawn_position
		visual.z_index = 100
		add_child(visual)
		visual.setup(unit)
		visual.set_facing(-1.0)
		visual.reset_locomotion()
		_candidate_visuals[candidate.candidate_id] = visual

		var label := _make_label("", 14)
		label.name = "AdventurerCandidateName_%s" % candidate.candidate_id
		label.position = spawn_position + Vector2(-70.0, -78.0)
		label.size = Vector2(140.0, 20.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(label)
		_candidate_labels[candidate.candidate_id] = label
		_refresh_candidate_label(candidate)

	_build_noble_candidate()


## 贵族冒险者表现：人物按步行呈现，战马作为独立节点显示在人物左侧。
## 只复制候选人的外观字段到临时 UnitData，不注册单位、不改骑乘数据。
func _build_noble_candidate() -> void:
	if _settlement == null:
		return
	_noble_candidate = _settlement.get_noble_adventurer_candidate()
	if _noble_candidate == null:
		return

	var spawn_position: Vector2 = _noble_candidate.world_position
	if spawn_position == Vector2.ZERO:
		spawn_position = AdventurerRecruitmentManager.NOBLE_CANDIDATE_POSITION

	var unit := UnitData.new()
	unit.unit_id = _noble_candidate.candidate_id
	unit.config_id = _noble_candidate.unit_config_id
	unit.display_name = _noble_candidate.display_name
	unit.faction_id = _settlement.faction_id
	unit.appearance = _noble_candidate.appearance.duplicate(true)
	unit.family_id = str(unit.appearance.get("family_id", ""))
	# 表现层强制步行；真实 UnitData 上的骑乘关系保持不变。
	unit.is_mounted = false

	_noble_visual = UnitVisualScript.new()
	_noble_visual.name = "NobleAdventurerVisual_%s" % _noble_candidate.candidate_id
	_noble_visual.position = spawn_position
	_noble_visual.z_index = 100
	add_child(_noble_visual)
	_noble_visual.setup(unit)
	_noble_visual.set_facing(-1.0)
	_noble_visual.reset_locomotion()

	var mount: MountInstanceData = _noble_candidate.get_mount_instance_data()
	_noble_mount_visual = HorseVisualScript.new()
	_noble_mount_visual.name = "NobleAdventurerHorse"
	_noble_mount_visual.position = spawn_position \
		+ AdventurerRecruitmentManager.NOBLE_MOUNT_VISUAL_OFFSET
	_noble_mount_visual.z_index = 99
	add_child(_noble_mount_visual)
	_noble_mount_visual.rebuild(
		mount.coat_style_id if mount != null else "brown",
		mount.saddle_style_id if mount != null else "saddle_01"
	)
	_noble_mount_visual.set_facing(-1.0)

	_noble_label = _make_label("", 14)
	_noble_label.name = "NobleAdventurerName_%s" % _noble_candidate.candidate_id
	_noble_label.position = spawn_position + Vector2(-80.0, -82.0)
	_noble_label.size = Vector2(160.0, 20.0)
	_noble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_noble_label)
	_refresh_noble_label()


func _refresh_noble_label() -> void:
	if _noble_label == null or _noble_candidate == null:
		return
	_noble_label.text = "%s（贵族·3级）" % _noble_candidate.display_name
	if not _noble_candidate.is_available():
		_noble_label.text = "%s（已招募）" % _noble_candidate.display_name


func _refresh_candidate_label(candidate: AdventurerCandidateData) -> void:
	if candidate == null:
		return
	if candidate.is_noble:
		_refresh_noble_label()
		return
	var label := _candidate_labels.get(candidate.candidate_id) as Label
	if label == null:
		return
	label.text = candidate.display_name
	if not candidate.is_available():
		label.text = "%s（已招募）" % candidate.display_name


func _visual_equipment_configs(unit: UnitData) -> Dictionary:
	var configs: Dictionary = {}
	if unit == null or _context == null:
		return configs
	for slot_key_value: Variant in unit.equipment.keys():
		var slot_key: String = str(slot_key_value)
		var equipment_id: String = str(unit.equipment.get(slot_key_value, ""))
		var equipment := _context.unit_manager.get_equipment_config(equipment_id)
		if equipment != null:
			configs[slot_key] = equipment
	return configs


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "UI"
	add_child(canvas)

	_ui_root = Control.new()
	_ui_root.name = "VillageUI"
	_ui_root.theme = UiTheme.create()
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_full_rect(_ui_root)
	canvas.add_child(_ui_root)

	_build_header()
	_build_exit_countdown()
	_build_world_log_panel()
	_build_dialogue_panel()
	_build_market_panel()


## 村庄与大地图共用同一个 MarketPanel；打开时沿用 UI 面板暂停原因。
func _build_market_panel() -> void:
	_market_panel = MarketPanel.new()
	_market_panel.name = "VillageMarketPanel"
	_market_panel.visible = false
	_market_panel.closed.connect(_on_market_closed)
	_market_panel.traded.connect(_on_market_traded)
	_ui_root.add_child(_market_panel)
	_market_panel.setup(_context)


func _open_village_market() -> void:
	if _settlement == null or _market_panel == null:
		return
	if not _market_panel.open(_settlement):
		_status_label.text = "该村庄暂无可用补给市场。"
		return
	if not _market_pause_active:
		TimeManager.push_pause(GameManager.PAUSE_REASON_UI_PANEL)
		_market_pause_active = true
	_moving = false
	_player_visual.update_locomotion(0.0, false)


func _on_market_closed() -> void:
	if _market_pause_active:
		TimeManager.pop_pause(GameManager.PAUSE_REASON_UI_PANEL)
		_market_pause_active = false


func _on_market_traded(_result: Dictionary) -> void:
	_status_label.text = "补给交易已完成。"


func _is_market_open() -> bool:
	return _market_panel != null and _market_panel.visible


func get_market_panel() -> MarketPanel:
	return _market_panel


## 与大地图共用同一世界日志组件；村庄放在右上角避免遮挡底部对话。
func _build_world_log_panel() -> void:
	_world_log_panel = WorldLogPanel.new()
	_ui_root.add_child(_world_log_panel)
	_world_log_panel.anchor_left = 1.0
	_world_log_panel.anchor_right = 1.0
	_world_log_panel.offset_left = -WorldLogPanel.PANEL_WIDTH - 12.0
	_world_log_panel.offset_right = -12.0
	_world_log_panel.offset_top = 112.0
	_world_log_panel.offset_bottom = 112.0 + WorldLogPanel.PANEL_HEIGHT
	_world_log_panel.setup(_context.world_log_manager)


func _build_header() -> void:
	var panel := PanelContainer.new()
	panel.name = "VillageHeader"
	panel.position = Vector2(18.0, 14.0)
	panel.custom_minimum_size = Vector2(560.0, 84.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)

	_village_label = _make_label("", 20)
	_village_label.name = "VillageNameLabel"
	column.add_child(_village_label)

	_hint_label = _make_label(
		"WASD 移动　左键点击头人或冒险者交谈　F 自由视角", 14
	)
	_hint_label.name = "VillageHintLabel"
	_hint_label.modulate = Color(0.92, 0.9, 0.82)
	column.add_child(_hint_label)

	_status_label = _make_label("", 13)
	_status_label.name = "VillageStatusLabel"
	_status_label.modulate = Color(1.0, 0.86, 0.55)
	column.add_child(_status_label)


func _build_exit_countdown() -> void:
	_exit_panel = PanelContainer.new()
	_exit_panel.name = "VillageExitPanel"
	_exit_panel.visible = false
	_exit_panel.anchor_left = 0.5
	_exit_panel.anchor_right = 0.5
	_exit_panel.anchor_top = 1.0
	_exit_panel.anchor_bottom = 1.0
	_exit_panel.offset_left = -230.0
	_exit_panel.offset_right = 230.0
	_exit_panel.offset_top = -360.0
	_exit_panel.offset_bottom = -300.0
	_exit_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(_exit_panel)

	_exit_label = _make_label("", 20)
	_exit_label.name = "VillageExitLabel"
	_exit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_exit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_exit_label.modulate = Color(1.0, 0.72, 0.6)
	_exit_panel.add_child(_exit_label)


func _build_dialogue_panel() -> void:
	_dialogue_panel = PanelContainer.new()
	_dialogue_panel.name = "VillageDialoguePanel"
	_dialogue_panel.visible = false
	_dialogue_panel.anchor_left = 0.5
	_dialogue_panel.anchor_right = 0.5
	_dialogue_panel.anchor_top = 1.0
	_dialogue_panel.anchor_bottom = 1.0
	_dialogue_panel.offset_left = -620.0
	_dialogue_panel.offset_right = 620.0
	_dialogue_panel.offset_top = -300.0
	_dialogue_panel.offset_bottom = -24.0
	_ui_root.add_child(_dialogue_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_dialogue_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	_dialogue_speaker_label = _make_label("", 22)
	_dialogue_speaker_label.name = "VillageDialogueSpeakerLabel"
	column.add_child(_dialogue_speaker_label)

	_dialogue_text_label = _make_label("", 17)
	_dialogue_text_label.name = "VillageDialogueTextLabel"
	_dialogue_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialogue_text_label.custom_minimum_size = Vector2(0.0, 96.0)
	column.add_child(_dialogue_text_label)

	column.add_child(HSeparator.new())

	_dialogue_choices = VBoxContainer.new()
	_dialogue_choices.name = "VillageDialogueChoices"
	_dialogue_choices.add_theme_constant_override("separation", 6)
	column.add_child(_dialogue_choices)


# ---------------------------------------------------------------------------
# 每帧更新
# ---------------------------------------------------------------------------


func _physics_process(delta: float) -> void:
	if _returning:
		return

	var camera_free: bool = _camera_rig != null and _camera_rig.is_free_mode()
	# 自由视角下 WASD/方向键只移动摄像机，不改变玩家角色位置。
	var input := Vector2.ZERO if camera_free else _read_input()
	_moving = input != Vector2.ZERO and not _dialogue_open \
		and not _is_market_open() and not camera_free
	if _moving:
		var speed: float = maxf(_player_unit.move_speed, 1.0) \
			* VILLAGE_MOVE_SPEED_MULTIPLIER
		_player_position += input * speed * delta
		_player_position.x = clampf(_player_position.x, 0.0, WORLD_SIZE.x)
		_player_position.y = clampf(_player_position.y, 0.0, WORLD_SIZE.y)
		if absf(input.x) > 0.01:
			_facing = 1.0 if input.x > 0.0 else -1.0
			_player_visual.set_facing(_facing)
		_player_visual.position = _player_position

	if is_instance_valid(_player_visual):
		_player_visual.update_locomotion(delta, _moving)
	if is_instance_valid(_npc_visual):
		_npc_visual.update_locomotion(delta, false)
	for value: Variant in _candidate_visuals.values():
		var visual := value as UnitVisual
		if visual != null and is_instance_valid(visual):
			visual.update_locomotion(delta, false)
	if is_instance_valid(_noble_visual):
		_noble_visual.update_locomotion(delta, false)
	if is_instance_valid(_noble_mount_visual):
		# 独立战马使用同一条 idle 时间轴；人物数据不变。
		_noble_mount_visual.update_locomotion(0.0, 0.0, 0.0, delta)
	if _camera_rig != null:
		_camera_rig.update(delta, _player_position, true, not _dialogue_open)

	_update_exit_state(delta)
	_update_interaction_hint()


func _read_input() -> Vector2:
	if _has_test_input:
		return _test_input
	var direction := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A):
		direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		direction.x += 1.0
	if Input.is_physical_key_pressed(KEY_W):
		direction.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		direction.y += 1.0
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	return direction


func _update_interaction_hint() -> void:
	if _status_label == null or _dialogue_open:
		return
	var near_candidate: bool = false
	if _settlement != null:
		for candidate: AdventurerCandidateData in _settlement.get_all_adventurer_candidates():
			if candidate == null:
				continue
			if _player_position.distance_to(_find_candidate_position(candidate)) \
					<= INTERACT_DISTANCE:
				near_candidate = true
				break
	var distance := _player_position.distance_to(ELDER_POSITION)
	if distance <= INTERACT_DISTANCE:
		_hint_label.text = "左键点击村庄头人交谈"
	elif near_candidate:
		_hint_label.text = "左键点击冒险者交谈"
	else:
		_hint_label.text = "WASD 移动　走近头人或冒险者后可以交谈"


func _update_exit_state(delta: float) -> void:
	if _returning:
		return
	var outside: bool = not PLAYABLE_RECT.grow(EXIT_TOLERANCE).has_point(_player_position)
	if not outside:
		if _exit_timer > 0.0:
			_exit_timer = 0.0
			_exit_panel.visible = false
		return

	_exit_timer += delta
	_exit_panel.visible = true
	var remaining: float = maxf(0.0, EXIT_COUNTDOWN_SECONDS - _exit_timer)
	_exit_label.text = "离开村庄：%.1f 秒" % remaining
	if _exit_timer >= EXIT_COUNTDOWN_SECONDS:
		_request_exit()


# ---------------------------------------------------------------------------
# 交互
# ---------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if _returning or _dialogue_open or _is_market_open():
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F:
			toggle_camera_free_mode()
			get_viewport().set_input_as_handled()
			return
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	var mouse_world := get_global_mouse_position()
	var candidate := _find_candidate_at(mouse_world)
	if candidate != null:
		get_viewport().set_input_as_handled()
		try_interact_with_candidate(candidate.candidate_id)
		return
	if mouse_world.distance_to(ELDER_POSITION) > ELDER_CLICK_RADIUS:
		return
	get_viewport().set_input_as_handled()
	try_interact_with_elder()


func _find_candidate_at(world_position: Vector2) -> AdventurerCandidateData:
	if _settlement == null:
		return null
	var nearest: AdventurerCandidateData = null
	var nearest_distance: float = CANDIDATE_CLICK_RADIUS
	for candidate: AdventurerCandidateData in _settlement.get_all_adventurer_candidates():
		if candidate == null:
			continue
		var candidate_position := _find_candidate_position(candidate)
		var distance := world_position.distance_to(candidate_position)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest = candidate
	return nearest


func _find_candidate_position(candidate: AdventurerCandidateData) -> Vector2:
	if candidate == null:
		return Vector2.ZERO
	if candidate.is_noble:
		if is_instance_valid(_noble_visual):
			return _noble_visual.position
		return candidate.world_position
	var visual := _candidate_visuals.get(candidate.candidate_id) as UnitVisual
	if visual != null and is_instance_valid(visual):
		return visual.position
	return candidate.world_position


## 与冒险者候选人交互。距离不足时不打开对话。
func try_interact_with_candidate(candidate_id: String) -> bool:
	if _returning or _dialogue_open or _is_market_open() or _settlement == null:
		return false
	var candidate := _settlement.get_candidate(candidate_id)
	if candidate == null:
		return false
	if _player_position.distance_to(_find_candidate_position(candidate)) \
			> INTERACT_DISTANCE:
		_status_label.text = "距离太远，走近冒险者后再交谈"
		return false
	return _open_candidate_dialogue(candidate)


func _open_candidate_dialogue(candidate: AdventurerCandidateData) -> bool:
	if candidate == null:
		return false
	var data := DialogueData.new()
	data.dialogue_id = "adventurer_%s" % candidate.candidate_id
	data.speaker_name = candidate.display_name
	data.start_node_id = "start"
	var available: bool = candidate.is_available()
	var authorized: bool = true
	var text: String = ""
	var choices: Array = []
	if candidate.is_noble:
		var player_lord_id: String = _player_lord_id()
		authorized = _context.adventurer_recruitment_manager \
			.is_noble_recruit_authorized(_settlement, player_lord_id)
		if not available:
			text = "我已经加入你的队伍，我的战马也会随行。"
		elif authorized:
			text = "我是%s的贵族冒险者，带着自己的战马。付我 1 金币，" \
				% get_village_name()
			text += "我与战马一同加入你的队伍。"
		else:
			text = "我是%s的贵族冒险者，只效忠于这座村庄的拥有者。" \
				% get_village_name()
			text += "\n只有村庄拥有者可以招募。"
		if available and authorized:
			choices.append({
				"text": "招募贵族冒险者（1 金币，含战马）",
				"next_node_id": "",
				"action": "recruit_adventurer",
				"candidate_id": candidate.candidate_id,
			})
		elif available and not authorized:
			choices.append({
				"text": "只有村庄拥有者可以招募",
				"next_node_id": "",
			})
	else:
		if available:
			text = "我听说%s需要人手。付我 1 金币，我就加入你的队伍。" \
				% get_village_name()
			choices.append({
				"text": "招募他（1 金币）",
				"next_node_id": "",
				"action": "recruit_adventurer",
				"candidate_id": candidate.candidate_id,
			})
		else:
			text = "我已经加入你的队伍，等你离开%s时一起走。" % get_village_name()
	choices.append({"text": "暂时不了", "next_node_id": ""})
	data.nodes = {
		"start": {
			"text": text,
			"choices": choices,
		}
	}
	if not _context.dialogue_manager.start_dialogue(data):
		_status_label.text = "无法开始对话"
		return false
	_show_dialogue()
	return true


## 与村庄头人交互。距离不足时不打开对话，返回 false。
func try_interact_with_elder() -> bool:
	if _returning or _dialogue_open or _is_market_open():
		return false
	if _player_position.distance_to(ELDER_POSITION) > INTERACT_DISTANCE:
		_status_label.text = "距离太远，走近村庄头人后再交谈"
		return false
	return _open_dialogue()


func _open_dialogue() -> bool:
	var data := load(VILLAGE_ELDER_DIALOGUE_PATH) as DialogueData
	if data == null:
		push_error("村庄对话配置加载失败: %s" % VILLAGE_ELDER_DIALOGUE_PATH)
		_status_label.text = "对话配置缺失"
		return false
	# 头人对话始终提供“购买补给”；玩家拥有该村时额外提供采邑征召。
	data = _build_elder_dialogue(data)
	if not _context.dialogue_manager.start_dialogue(data):
		_status_label.text = "无法开始对话"
		return false
	_show_dialogue()
	return true


## 在基础对话上追加运行时选项；其余对话内容仍来自数据配置。
func _build_elder_dialogue(base: DialogueData) -> DialogueData:
	var data := DialogueData.new()
	data.dialogue_id = base.dialogue_id
	data.speaker_name = base.speaker_name
	data.start_node_id = base.start_node_id
	data.nodes = base.nodes.duplicate(true)
	var start_node: Dictionary = data.get_node_data(data.start_node_id)
	var choices_value: Variant = start_node.get("choices", [])
	var choices: Array = (choices_value as Array).duplicate(true) \
		if choices_value is Array else []
	choices.append({
		"text": "购买补给（面包、草料）",
		"next_node_id": "",
		"action": "open_market",
	})
	if _can_player_recruit_fief():
		choices.append({
			"text": "征召 1 组采邑（6 人，剩余 %d 组）"
				% _settlement.fief_recruitment_stock,
			"next_node_id": "",
			"action": "recruit_fief",
		})
	start_node["choices"] = choices
	data.nodes[data.start_node_id] = start_node
	return data


func _player_lord_id() -> String:
	if _context == null:
		return ""
	var player_lord: LordData = _context.get_player_lord()
	return player_lord.lord_id if player_lord != null else ""


func _can_player_recruit_fief() -> bool:
	if _settlement == null or _context == null:
		return false
	if _settlement.settlement_type != SettlementData.SettlementType.VILLAGE:
		return false
	if _settlement.fief_recruitment_stock <= 0:
		return false
	var player_lord: LordData = _context.get_player_lord()
	return player_lord != null \
		and _settlement.owner_lord_id == player_lord.lord_id


func _show_dialogue() -> void:
	_dialogue_open = true
	_moving = false
	_player_visual.update_locomotion(0.0, false)
	_dialogue_panel.visible = true
	if not _dialogue_pause_active:
		TimeManager.push_pause(GameManager.PAUSE_REASON_WORLD_DIALOGUE)
		_dialogue_pause_active = true
	_refresh_dialogue_ui()


func _refresh_dialogue_ui() -> void:
	_dialogue_speaker_label.text = _context.dialogue_manager.get_speaker_name()
	var text: String = _context.dialogue_manager.get_current_text()
	text = text.replace("{village_name}", get_village_name())
	_dialogue_text_label.text = text

	for child: Node in _dialogue_choices.get_children():
		_dialogue_choices.remove_child(child)
		child.queue_free()

	var choices: Array = _context.dialogue_manager.get_choices()
	for index: int in range(choices.size()):
		var choice: Variant = choices[index]
		if not choice is Dictionary:
			continue
		var button := Button.new()
		button.name = "VillageDialogueChoice_%d" % index
		button.text = str((choice as Dictionary).get("text", "……"))
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0.0, 40.0)
		button.pressed.connect(_on_dialogue_choice.bind(index))
		_dialogue_choices.add_child(button)


func _on_dialogue_choice(index: int) -> void:
	if not _dialogue_open:
		return
	var choices: Array = _context.dialogue_manager.get_choices()
	var action_message: String = ""
	if index >= 0 and index < choices.size() and choices[index] is Dictionary:
		var choice: Dictionary = choices[index]
		var action: String = str(choice.get("action", ""))
		if not action.is_empty():
			action_message = _execute_dialogue_action(action, choice)
			_close_dialogue()
			if not action_message.is_empty():
				_status_label.text = action_message
			return
	if _context.dialogue_manager.choose(index):
		_refresh_dialogue_ui()
		return
	_close_dialogue()


## 对话选项只触发统一业务接口，不直接创建单位或修改地点数据。
func _execute_dialogue_action(action: String, choice: Dictionary) -> String:
	match action:
		"recruit_adventurer":
			var candidate_id: String = str(choice.get("candidate_id", ""))
			var success: bool = _context.adventurer_recruitment_manager.recruit_candidate(
				_settlement.settlement_id,
				candidate_id,
				_context.player_profile,
				_player_lord_id()
			)
			if success:
				var candidate: AdventurerCandidateData = _settlement.get_candidate(
					candidate_id
				)
				_refresh_candidate_label(candidate)
				if candidate != null and candidate.is_noble:
					return "贵族冒险者与战马已加入你的队伍。"
				return "冒险者已加入你的队伍。"
			return _context.adventurer_recruitment_manager.last_error
		"open_market":
			# 等当前对话完全关闭后再打开市场，避免暂停原因与输入状态互相覆盖。
			call_deferred("_open_village_market")
			return ""
		"recruit_fief":
			var player_lord: LordData = _context.get_player_lord()
			if player_lord == null:
				return "没有有效的玩家领主身份"
			var recruited: bool = _context.fief_recruitment_manager.recruit_group(
				_settlement.settlement_id, player_lord.lord_id
			)
			if recruited:
				return "已征召 1 组采邑，共 6 人。"
			return _context.fief_recruitment_manager.last_error
		_:
			return ""


## 关闭对话界面并恢复玩家移动。
func _close_dialogue() -> void:
	_dialogue_open = false
	_dialogue_panel.visible = false
	_status_label.text = ""
	_context.dialogue_manager.end_dialogue()
	if _dialogue_pause_active:
		TimeManager.pop_pause(GameManager.PAUSE_REASON_WORLD_DIALOGUE)
		_dialogue_pause_active = false


# ---------------------------------------------------------------------------
# 返回大地图
# ---------------------------------------------------------------------------


func _request_exit() -> void:
	if _returning:
		return
	_returning = true
	_exit_panel.visible = false
	exit_requested.emit()

	if _dialogue_open:
		_close_dialogue()
	var settlement_id: String = _settlement.settlement_id if _settlement != null else ""
	# 离开村庄后清理本次已招募的候选人记录；已加入部队的单位不受影响。
	if not settlement_id.is_empty():
		_context.adventurer_recruitment_manager.cleanup_departed_candidates(
			settlement_id
		)
	if not _auto_return_enabled:
		return
	GameManager.pending_settlement_latch_id = settlement_id
	TimeManager.set_base_world_speed(GameManager.small_scene_return_base_speed)
	TimeManager.pop_pause(GameManager.PAUSE_REASON_SMALL_SCENE)
	var error: Error = SceneManager.change_scene(WORLD_MAP_SCENE)
	if error != OK:
		push_error("无法返回大地图（错误码 %s）" % error)
		TimeManager.push_pause(GameManager.PAUSE_REASON_SMALL_SCENE)
		_returning = false
		return
	EventBus.settlement_exited.emit(settlement_id, _context.player_party_id)


func _abort_to_world_map() -> void:
	TimeManager.pop_pause(GameManager.PAUSE_REASON_SMALL_SCENE)
	SceneManager.change_scene(WORLD_MAP_SCENE)


# ---------------------------------------------------------------------------
# 绘制
# ---------------------------------------------------------------------------


func _draw() -> void:
	# 草地与远景。
	draw_rect(Rect2(Vector2.ZERO, WORLD_SIZE), Color("#4f6b3d"), true)
	draw_rect(Rect2(0.0, 0.0, WORLD_SIZE.x, 230.0), Color("#5b7a48"), true)
	draw_rect(Rect2(0.0, 0.0, WORLD_SIZE.x, 80.0), Color("#6f8f5c"), true)

	# 道路。
	var path_color := Color("#8a7550")
	draw_rect(Rect2(0.0, 760.0, WORLD_SIZE.x, 92.0), path_color, true)
	draw_rect(Rect2(930.0, 520.0, 70.0, 260.0), path_color, true)
	draw_line(Vector2(0.0, 768.0), Vector2(WORLD_SIZE.x, 768.0), Color(0, 0, 0, 0.12), 3.0)

	# 房屋。
	_draw_house(Vector2(600.0, 470.0), Color("#c9b48a"), Color("#8a4a38"))
	_draw_house(Vector2(1550.0, 500.0), Color("#c2ab7f"), Color("#7c4033"))
	_draw_house(Vector2(880.0, 380.0), Color("#bfa87e"), Color("#7f4736"))

	# 栅栏与树。
	_draw_fence(Vector2(180.0, 700.0), 15)
	for tree_position: Vector2 in [
		Vector2(260.0, 420.0), Vector2(1720.0, 360.0),
		Vector2(420.0, 940.0), Vector2(1500.0, 930.0),
	]:
		_draw_tree(tree_position)

	# 可活动区域边界（轻微提示，不是硬墙）。
	draw_rect(PLAYABLE_RECT, Color(1.0, 1.0, 1.0, 0.06), false, 2.0)


func _draw_house(origin: Vector2, wall: Color, roof: Color) -> void:
	draw_rect(Rect2(origin.x - 80.0, origin.y - 70.0, 160.0, 110.0), wall, true)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(origin.x - 100.0, origin.y - 70.0),
			Vector2(origin.x, origin.y - 150.0),
			Vector2(origin.x + 100.0, origin.y - 70.0),
		]),
		roof
	)
	draw_rect(Rect2(origin.x - 18.0, origin.y - 10.0, 36.0, 50.0), Color("#4a3322"), true)
	draw_rect(Rect2(origin.x + 44.0, origin.y - 48.0, 24.0, 22.0), Color("#3f4850"), true)


func _draw_fence(origin: Vector2, segments: int) -> void:
	var wood := Color("#6f5637")
	for index: int in range(segments):
		var x: float = origin.x + float(index) * 46.0
		draw_line(Vector2(x, origin.y), Vector2(x, origin.y - 46.0), wood, 3.0)
	draw_line(origin, Vector2(origin.x + float(segments) * 46.0, origin.y), wood, 2.0)
	draw_line(
		origin + Vector2(0.0, -28.0),
		Vector2(origin.x + float(segments) * 46.0, origin.y - 28.0),
		wood,
		2.0
	)


func _draw_tree(tree_position: Vector2) -> void:
	draw_rect(
		Rect2(tree_position.x - 8.0, tree_position.y - 60.0, 16.0, 64.0),
		Color("#5a4029"),
		true
	)
	draw_circle(tree_position + Vector2(0.0, -84.0), 46.0, Color("#3f6a34"))
	draw_circle(tree_position + Vector2(-18.0, -66.0), 30.0, Color("#4b7a3d"))
	draw_circle(tree_position + Vector2(22.0, -70.0), 28.0, Color("#46743a"))


# ---------------------------------------------------------------------------
# 测试与查询接口
# ---------------------------------------------------------------------------


func set_test_input(direction: Vector2, active: bool = true) -> void:
	_test_input = direction.limit_length(1.0)
	_has_test_input = active


func set_player_position(value: Vector2) -> void:
	_player_position = value
	if is_instance_valid(_player_visual):
		_player_visual.position = value


func get_player_position() -> Vector2:
	return _player_position


func get_elder_position() -> Vector2:
	return ELDER_POSITION


func get_candidate_count() -> int:
	return _candidate_visuals.size()


func get_candidate_visual(candidate_id: String) -> UnitVisual:
	return _candidate_visuals.get(candidate_id) as UnitVisual


func get_candidate_position(candidate_id: String) -> Vector2:
	var visual := get_candidate_visual(candidate_id)
	return visual.position if visual != null else Vector2.ZERO


## 贵族冒险者表现只在村庄场景存在；普通候选人的既有计数/查找接口不变。
func get_noble_candidate_visual() -> UnitVisual:
	return _noble_visual


func get_noble_mount_visual() -> HorseVisual:
	return _noble_mount_visual


func get_noble_candidate_position() -> Vector2:
	return _noble_visual.position if is_instance_valid(_noble_visual) else Vector2.ZERO


func get_world_log_panel() -> WorldLogPanel:
	return _world_log_panel


func get_village_name() -> String:
	if _settlement != null:
		return _settlement.display_name
	return "村庄"


func is_dialogue_open() -> bool:
	return _dialogue_open


func get_exit_countdown() -> float:
	return _exit_timer


func is_returning_to_world() -> bool:
	return _returning


## 自动化测试可关闭真实场景切换，只验证倒计时结束事件。
func set_auto_return_enabled(enabled: bool) -> void:
	_auto_return_enabled = enabled


func advance_exit_countdown(delta: float) -> void:
	_update_exit_state(delta)


func get_player_visual() -> UnitVisual:
	return _player_visual


func get_dialogue_panel() -> PanelContainer:
	return _dialogue_panel


func get_camera_rig() -> SceneCameraRig:
	return _camera_rig


func toggle_camera_free_mode() -> bool:
	if _camera_rig == null:
		return false
	var active: bool = _camera_rig.toggle_free_mode()
	_moving = false
	if is_instance_valid(_player_visual):
		_player_visual.update_locomotion(0.0, false)
	if _status_label != null:
		_status_label.text = (
			"摄像机：自由视角（WASD / 方向键移动，F 切回跟随）"
			if active else ""
		)
	return active


func set_camera_free_mode(active: bool) -> void:
	if _camera_rig != null:
		_camera_rig.set_free_mode(active)


func is_camera_free_mode() -> bool:
	return _camera_rig != null and _camera_rig.is_free_mode()


func get_camera_position() -> Vector2:
	return _camera_rig.get_camera_position() if _camera_rig != null else Vector2.ZERO


func set_test_free_camera_input(direction: Vector2, active: bool = true) -> void:
	if _camera_rig != null:
		_camera_rig.set_test_free_input(direction, active)


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------


func _update_header() -> void:
	_village_label.text = "村庄：%s" % get_village_name()


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
