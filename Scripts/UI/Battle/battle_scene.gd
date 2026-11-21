class_name BattleScene
extends Node2D
## 战斗场景控制器：读取 BattleSession，生成 UnitActor，驱动实时战斗与结果返回。
##
## 只读取 UnitData 的静态属性，伤害写入 BattleUnitState；
## 战斗结算统一由 BattleManager.finish_battle() 执行。

const BATTLEFIELD_SIZE := Vector2(1280.0, 720.0)
## 初始部署：双方靠近左右边界，阵线间距约 1100（含列间距后质心约 1040）。
## 这是屏幕战斗唯一的初始距离参数；所有创建入口（玩家遭遇、AI 遭遇、
## 多方中途加入）都经过 BattleScene，不会各自写不同距离。
const SPAWN_MARGIN_X: float = 90.0
const INITIAL_DEPLOYMENT_DISTANCE: float = BATTLEFIELD_SIZE.x - SPAWN_MARGIN_X * 2.0
const SPAWN_SPACING_X: float = 54.0
const SPAWN_SPACING_Y: float = 64.0

## 与村庄共用 SceneCameraRig.VIEW_SIZE（1920×1080 下为 2 倍缩放 / 960×540 区域）。
## 相机略向下偏移以显示底部地面。
const BATTLE_CAMERA_Y_OFFSET: float = 30.0

## 集群/队形参数集中配置。
const FORMATION_REFRESH_INTERVAL: float = 0.4
const NEIGHBOR_REFRESH_INTERVAL: float = 0.3
const NEIGHBOR_RADIUS: float = 56.0
const FORMATION_SPACING: float = 40.0
## 骑乘单位连人带马更宽，队形槽位需要更大间距。
const FORMATION_SPACING_MOUNTED: float = 56.0
const PARTY_LANE_SPACING: float = 170.0
## 接敌前两军前排槽位之间保留的空隙；双方各自在自己的半场列阵。
const SIDE_LINE_GAP: float = 90.0
## 双方质心接近到该距离后视为已接敌，队形自动放松。
const CONTACT_DISTANCE: float = 220.0
const CONTACT_SPACING_MULTIPLIER: float = 1.35

@onready var characters: Node2D = $World/Characters
@onready var camera: Camera2D = $Camera2D

var _context: WorldContext = null
var _battle_manager: BattleManager = null
var _session: BattleSession = null
var _formation_manager: FormationManager = FormationManager.new()
var _camera_rig: SceneCameraRig = null

## unit_id -> UnitActor / UnitController
var _actors: Dictionary = {}
var _controllers: Dictionary = {}
## side_index -> Array[UnitController]
var _side_controllers: Dictionary = {}
## side_index -> 其他战斗侧的控制器列表
var _enemy_controllers_by_side: Dictionary = {}
var _side_order: Array[int] = []
var _player_side: int = 0
var _winning_side: int = -1
var _handled_deaths: Dictionary = {}

var _formation_timer: float = 0.0
var _neighbor_timer: float = 0.0
var _default_formation: FormationManager.FormationType = (
	FormationManager.FormationType.INFANTRY_LINE
)
## party_id -> FormationType
var _party_formations: Dictionary = {}
## party_id -> 世界坐标移动目标；为未来键盘部队指令预留。
var _party_move_orders: Dictionary = {}

var _controlled_unit_id: String = ""
var _controlled_controller: UnitController = null
var _spectating: bool = false
var _scene_paused: bool = false
var _control_transfer_handled: bool = false
var _test_input_override := Vector2.ZERO
var _has_test_input_override: bool = false

var _battle_over: bool = false
var _returned: bool = false
var _result: BattleSession.BattleResult = BattleSession.BattleResult.UNDECIDED
var _result_data: BattleResultData = null

var _ui_root: Control = null
var _info_label: Label = null
var _alive_label: Label = null
var _control_label: Label = null
var _retreat_button: Button = null
var _result_dim: ColorRect = null
var _result_panel: PanelContainer = null
var _result_label: Label = null
var _result_summary_label: Label = null
var _result_casualties_label: Label = null
var _result_exp_label: Label = null
var _result_reward_label: Label = null
var _return_button: Button = null

var _control_dim: ColorRect = null
var _control_panel: PanelContainer = null
var _control_list: VBoxContainer = null
var _control_status_label: Label = null
var _spectate_button: Button = null


func _ready() -> void:
	_context = GameManager.world_context
	if _context == null:
		push_error("战斗场景缺少 WorldContext")
		call_deferred("_abort_to_world_map")
		return

	_battle_manager = _context.battle_manager
	_session = _battle_manager.current_battle
	if _session == null:
		push_error("战斗场景缺少 BattleSession")
		call_deferred("_abort_to_world_map")
		return

	_session.status = BattleSession.Status.ACTIVE
	_player_side = _resolve_player_side()
	_build_ui()
	_spawn_units()
	_assign_initial_control()
	_update_formations()
	_refresh_neighbor_cache()
	_refresh_target_claims()

	_camera_rig = SceneCameraRig.new()
	_camera_rig.setup(
		camera,
		Rect2(Vector2.ZERO, BATTLEFIELD_SIZE),
		Vector2(0.0, BATTLE_CAMERA_Y_OFFSET)
	)
	_camera_rig.snap_to(_get_camera_follow_position())
	camera.enabled = true
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, BATTLEFIELD_SIZE), Color("#4b5f3a"), true)
	draw_rect(
		Rect2(0.0, BATTLEFIELD_SIZE.y - 90.0, BATTLEFIELD_SIZE.x, 90.0),
		Color("#5a4a35"),
		true
	)
	var grid_color := Color(0.0, 0.0, 0.0, 0.08)
	for x: int in range(0, int(BATTLEFIELD_SIZE.x) + 1, 80):
		draw_line(Vector2(float(x), 0.0), Vector2(float(x), BATTLEFIELD_SIZE.y), grid_color, 1.0)
	for y: int in range(0, int(BATTLEFIELD_SIZE.y) + 1, 80):
		draw_line(Vector2(0.0, float(y)), Vector2(BATTLEFIELD_SIZE.x, float(y)), grid_color, 1.0)
	draw_line(
		Vector2(BATTLEFIELD_SIZE.x * 0.5, 0.0),
		Vector2(BATTLEFIELD_SIZE.x * 0.5, BATTLEFIELD_SIZE.y),
		Color(1.0, 1.0, 1.0, 0.08),
		2.0
	)


func _physics_process(delta: float) -> void:
	if _session == null or _battle_over or _scene_paused:
		return

	_formation_timer += delta
	if _formation_timer >= FORMATION_REFRESH_INTERVAL:
		_formation_timer = fmod(_formation_timer, FORMATION_REFRESH_INTERVAL)
		_update_formations()

	_neighbor_timer += delta
	if _neighbor_timer >= NEIGHBOR_REFRESH_INTERVAL:
		_neighbor_timer = fmod(_neighbor_timer, NEIGHBOR_REFRESH_INTERVAL)
		_refresh_neighbor_cache()
		_refresh_target_claims()

	if _camera_rig != null:
		_camera_rig.update(
			delta,
			_get_camera_follow_position(),
			_is_camera_follow_active(),
			true
		)
	var player_input := _read_player_input()
	for side_index: int in _side_order:
		var enemies := _enemy_controllers_by_side.get(
			side_index, []
		) as Array[UnitController]
		var controllers := _side_controllers.get(
			side_index, []
		) as Array[UnitController]
		for controller: UnitController in controllers:
			if controller == _controlled_controller:
				controller.player_tick(delta, player_input)
			else:
				controller.tick(delta, enemies)

	_process_deaths()
	var paused_for_transfer := _handle_controlled_unit_death()
	_update_alive_label()
	if not paused_for_transfer:
		_check_battle_end()


func _unhandled_input(event: InputEvent) -> void:
	if _battle_over or _scene_paused:
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F:
			toggle_camera_free_mode()
			get_viewport().set_input_as_handled()
			return
	# 观战允许自由视角，但不允许玩家攻击。
	if _spectating:
		return
	if _camera_rig != null and _camera_rig.is_free_mode():
		return
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	# 允许朝任意鼠标世界坐标出手；边界外点击也按鼠标方向空挥。
	var target := get_global_mouse_position()
	try_player_attack_at(target)
	get_viewport().set_input_as_handled()


## 玩家左键攻击入口；供输入与自动化测试共用。
## 返回 true 表示已释放攻击动作（可能命中，也可能是无敌人的空挥）。
func try_player_attack_at(target_position: Vector2) -> bool:
	if _controlled_controller == null or not _controlled_controller.is_alive():
		return false
	var enemies := _enemy_controllers_by_side.get(
		_player_side, []
	) as Array[UnitController]
	return _controlled_controller.player_attack_at(target_position, enemies)


## 测试钩子：模拟 WASD 输入；direction 会自动归一化。
func set_test_player_input(direction: Vector2, active: bool = true) -> void:
	_test_input_override = direction.limit_length(1.0)
	_has_test_input_override = active


func get_controlled_unit_id() -> String:
	return _controlled_unit_id


func get_camera_rig() -> SceneCameraRig:
	return _camera_rig


func toggle_camera_free_mode() -> bool:
	if _camera_rig == null:
		return false
	return _camera_rig.toggle_free_mode()


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


## 摄像机的跟随目标始终是当前玩家控制单位；观战时保持当前位置。
func _get_camera_follow_position() -> Vector2:
	if _controlled_controller != null:
		return _controlled_controller.get_position()
	return Vector2(
		BATTLEFIELD_SIZE.x * 0.5,
		BATTLEFIELD_SIZE.y * 0.5
	)


func _is_camera_follow_active() -> bool:
	return _controlled_controller != null and _controlled_controller.is_alive()


func is_spectating() -> bool:
	return _spectating


func is_scene_paused() -> bool:
	return _scene_paused


## 兼容旧测试/调试：命令所有存活己方士兵移动到目标点附近。
## 正式玩家操作使用 WASD + 左键，不再调用本方法。
func command_player_units(target: Vector2) -> void:
	var alive: Array[UnitController] = []
	var controller_list := _side_controllers.get(_player_side, []) as Array[UnitController]
	for controller: UnitController in controller_list:
		if controller.is_alive():
			alive.append(controller)

	var columns: int = 2
	var rows: int = maxi(1, ceili(float(alive.size()) / float(columns)))
	for i: int in range(alive.size()):
		var row: int = i / columns
		var column: int = i % columns
		var offset := Vector2(
			(float(column) - 0.5) * 28.0,
			(float(row) - (float(rows) - 1.0) * 0.5) * 28.0
		)
		alive[i].command_move(target + offset)


func get_session() -> BattleSession:
	return _session


func get_actor_count() -> int:
	return _actors.size()


func get_controller(unit_id: String) -> UnitController:
	return _controllers.get(unit_id) as UnitController


func get_player_side() -> int:
	return _player_side


func get_side_controller_count(side_index: int) -> int:
	var controllers := _side_controllers.get(side_index, []) as Array[UnitController]
	return controllers.size()


func get_controller_count_alive(side_index: int) -> int:
	return _count_side_alive(side_index)


func get_enemy_controller_count(side_index: int) -> int:
	var enemies := _enemy_controllers_by_side.get(side_index, []) as Array[UnitController]
	return enemies.size()


## 为未来键盘部队指令预留：设置指定部队的队形类型。
func set_party_formation(
	party_id: String, formation_type: FormationManager.FormationType
) -> void:
	_party_formations[party_id] = formation_type


func set_default_formation(formation_type: FormationManager.FormationType) -> void:
	_default_formation = formation_type


## 未来键盘部队指令入口：让指定部队移动到世界坐标并保持队形。
func set_party_move_order(party_id: String, target: Vector2) -> bool:
	if _session == null or not _session.is_party_involved(party_id):
		return false
	_party_move_orders[party_id] = target
	_formation_timer = FORMATION_REFRESH_INTERVAL
	return true


func clear_party_move_order(party_id: String) -> void:
	_party_move_orders.erase(party_id)


func _read_player_input() -> Vector2:
	# 自由视角下 WASD/方向键只移动镜头，不移动当前控制角色。
	if _camera_rig != null and _camera_rig.is_free_mode():
		return Vector2.ZERO
	if _has_test_input_override:
		return _test_input_override
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


func _assign_initial_control() -> void:
	var candidates := _alive_controllers_on_side(_player_side)
	var selected: UnitController = null
	for controller: UnitController in candidates:
		if controller.unit_data != null and controller.unit_data.is_player_character:
			selected = controller
			break
	if selected == null and not candidates.is_empty():
		# 旧存档可能没有玩家角色；退化到第一名存活友军。
		selected = candidates[0]
	if selected == null:
		_set_controlled_controller(null)
		return
	_set_controlled_controller(selected)


func _set_controlled_controller(controller: UnitController) -> void:
	for side_index: int in _side_order:
		var controllers := _side_controllers.get(
			side_index, []
		) as Array[UnitController]
		for other: UnitController in controllers:
			if other == null:
				continue
			if other.is_player_controlled:
				other.set_player_controlled(false)
			if other.actor != null and is_instance_valid(other.actor):
				other.actor.set_controlled(false)

	if controller == null:
		_controlled_unit_id = ""
		_controlled_controller = null
		_spectating = true
		_update_alive_label()
		return

	_spectating = false
	_controlled_controller = controller
	_controlled_unit_id = controller.unit_id
	controller.set_player_controlled(true)
	if controller.actor != null and is_instance_valid(controller.actor):
		controller.actor.set_controlled(true)
	_update_alive_label()


func _handle_controlled_unit_death() -> bool:
	if _spectating or _control_transfer_handled or _controlled_controller == null:
		return false
	if _controlled_controller.is_alive():
		return false

	_control_transfer_handled = true
	var dead_controller := _controlled_controller
	dead_controller.set_player_controlled(false)
	if dead_controller.actor != null and is_instance_valid(dead_controller.actor):
		dead_controller.actor.set_controlled(false)
	var dead_unit_id := _controlled_unit_id
	_controlled_unit_id = ""
	_controlled_controller = null

	var allies: Array[UnitController] = []
	for controller: UnitController in _alive_controllers_on_side(_player_side):
		if controller.unit_id != dead_unit_id:
			allies.append(controller)
	if allies.is_empty():
		# 没有可接管友军：进入观战/战败流程，由 _check_battle_end 判定。
		_spectating = true
		_update_alive_label()
		return false

	_show_control_transfer(allies)
	_scene_paused = true
	return true


func _show_control_transfer(allies: Array[UnitController]) -> void:
	for child: Node in _control_list.get_children():
		_control_list.remove_child(child)
		child.queue_free()

	for controller: UnitController in allies:
		var config := _context.unit_manager.get_unit_config(
			controller.unit_data.config_id
		)
		var class_text: String = config.display_name if config != null \
			else controller.unit_data.config_id
		var mounted_text: String = " · 骑乘" if controller.unit_data.is_mounted else ""
		var text := "%s · %s%s · Lv.%d · HP %d/%d" % [
			controller.unit_data.display_name,
			class_text,
			mounted_text,
			controller.unit_data.level,
			controller.state.battle_hp,
			controller.unit_data.max_hp,
		]
		var button := _make_button(text, "TakeControl_%s" % controller.unit_id)
		button.custom_minimum_size = Vector2(0.0, 38.0)
		button.pressed.connect(_on_take_control.bind(controller.unit_id))
		_control_list.add_child(button)

	_control_status_label.text = ""
	_control_dim.visible = true
	_control_panel.visible = true


func _on_take_control(unit_id: String) -> void:
	var controller := _controllers.get(unit_id) as UnitController
	if controller == null or not controller.is_alive():
		_control_status_label.text = "该单位已经无法战斗"
		return
	_set_controlled_controller(controller)
	_control_dim.visible = false
	_control_panel.visible = false
	_scene_paused = false
	_control_transfer_handled = false


func _on_spectate_pressed() -> void:
	_set_controlled_controller(null)
	_control_dim.visible = false
	_control_panel.visible = false
	_scene_paused = false
	_control_transfer_handled = false


func _alive_controllers_on_side(side_index: int) -> Array[UnitController]:
	var result: Array[UnitController] = []
	var controllers := _side_controllers.get(
		side_index, []
	) as Array[UnitController]
	for controller: UnitController in controllers:
		if controller != null and controller.is_alive():
			result.append(controller)
	return result


func _alive_controllers_of_party(party_id: String) -> Array[UnitController]:
	var result: Array[UnitController] = []
	for unit_id: String in _session.get_party_unit_ids(party_id):
		var controller := _controllers.get(unit_id) as UnitController
		if controller != null and controller.is_alive():
			result.append(controller)
	return result


func _centroid(controllers: Array[UnitController]) -> Vector2:
	if controllers.is_empty():
		return Vector2.ZERO
	var total := Vector2.ZERO
	for controller: UnitController in controllers:
		total += controller.get_position()
	return total / float(controllers.size())


func _nearest_enemy_side(side_index: int) -> int:
	var own_controllers := _alive_controllers_on_side(side_index)
	if own_controllers.is_empty():
		return -1
	var own_centroid := _centroid(own_controllers)
	var best_side: int = -1
	var best_distance: float = INF
	for other_side: int in _side_order:
		if other_side == side_index:
			continue
		var enemy_controllers := _alive_controllers_on_side(other_side)
		if enemy_controllers.is_empty():
			continue
		var distance := own_centroid.distance_to(_centroid(enemy_controllers))
		if distance < best_distance:
			best_distance = distance
			best_side = other_side
	return best_side


## 周期计算每个部队的队形槽位；多支部队使用横向 lane 分区。
func _update_formations() -> void:
	if _session == null:
		return
	for side_index: int in _side_order:
		var own_controllers := _alive_controllers_on_side(side_index)
		if own_controllers.is_empty():
			continue
		var enemy_side := _nearest_enemy_side(side_index)
		if enemy_side < 0:
			continue
		var enemy_controllers := _alive_controllers_on_side(enemy_side)
		if enemy_controllers.is_empty():
			continue

		var own_centroid := _centroid(own_controllers)
		var enemy_centroid := _centroid(enemy_controllers)
		var line_distance := own_centroid.distance_to(enemy_centroid)
		var forward := enemy_centroid - own_centroid
		if forward.length_squared() < 0.0001:
			forward = Vector2.RIGHT if side_index < enemy_side else Vector2.LEFT
		forward = forward.normalized()
		var right := Vector2(-forward.y, forward.x)
		# 双方各自在自己的半场列阵：推进到距敌方阵线约 SIDE_LINE_GAP 处，
		# 而不是让两侧共用中点坐标。接敌后队形自动放松。
		var advance: float = maxf(
			0.0, minf(line_distance * 0.45, line_distance * 0.5 - SIDE_LINE_GAP * 0.5)
		)
		var line_center := own_centroid + forward * advance
		var loose_spacing: bool = line_distance <= CONTACT_DISTANCE

		var party_ids: Array[String] = []
		for party_id: String in _session.get_side_party_ids(side_index):
			if not _alive_controllers_of_party(party_id).is_empty():
				party_ids.append(party_id)
		var party_count: int = party_ids.size()
		if party_count == 0:
			continue

		for party_index: int in range(party_count):
			var party_id: String = party_ids[party_index]
			var controllers := _alive_controllers_of_party(party_id)
			if controllers.is_empty():
				continue
			var formation_type: FormationManager.FormationType = (
				_party_formations.get(party_id, _default_formation)
				as FormationManager.FormationType
			)
			var spacing: float = FORMATION_SPACING
			for controller: UnitController in controllers:
				if controller.unit_data != null and controller.unit_data.is_mounted:
					spacing = FORMATION_SPACING_MOUNTED
					break
			if loose_spacing:
				spacing *= CONTACT_SPACING_MULTIPLIER
			var slots := _formation_manager.compute_slots(
				formation_type, controllers.size(), spacing
			)
			var lane: float = (
				(float(party_index) - (float(party_count) - 1.0) * 0.5)
				* PARTY_LANE_SPACING
			)
			var center: Vector2 = line_center + right * lane
			if _party_move_orders.has(party_id):
				center = _party_move_orders[party_id] as Vector2
			var count: int = mini(controllers.size(), slots.size())
			for i: int in range(count):
				var local := slots[i]
				var world_slot := center + forward * local.x + right * local.y
				controllers[i].set_formation_slot(world_slot)


## 周期性构建局部邻居缓存；避免每个单位每帧遍历全场。
func _refresh_neighbor_cache() -> void:
	var all_controllers: Array[UnitController] = []
	for side_index: int in _side_order:
		var controllers := _side_controllers.get(
			side_index, []
		) as Array[UnitController]
		all_controllers.append_array(controllers)

	for controller: UnitController in all_controllers:
		controller.nearby_controllers.clear()

	for i: int in range(all_controllers.size()):
		var a := all_controllers[i]
		if a == null:
			continue
		for j: int in range(i + 1, all_controllers.size()):
			var b := all_controllers[j]
			if b == null:
				continue
			if a.get_position().distance_to(b.get_position()) <= NEIGHBOR_RADIUS:
				a.nearby_controllers.append(b)
				b.nearby_controllers.append(a)


## 周期统计每个战斗侧的目标占用情况，供 UnitController 分散选择目标。
## 只遍历己方控制器，不按单位扫描全场，开销与邻居缓存同阶。
func _refresh_target_claims() -> void:
	for side_index: int in _side_order:
		var controllers := _side_controllers.get(
			side_index, []
		) as Array[UnitController]
		var counts: Dictionary = {}
		for controller: UnitController in controllers:
			if controller == null or not controller.is_alive():
				continue
			var target_id: String = controller.get_target_unit_id()
			if target_id.is_empty():
				continue
			counts[target_id] = int(counts.get(target_id, 0)) + 1
		for controller: UnitController in controllers:
			if controller != null:
				controller.set_target_claim_counts(counts)


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "UI"
	add_child(canvas)

	_ui_root = Control.new()
	_ui_root.name = "BattleUI"
	_ui_root.theme = UiTheme.create()
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_full_rect(_ui_root)
	canvas.add_child(_ui_root)

	var top_bar := PanelContainer.new()
	top_bar.name = "TopBar"
	top_bar.anchor_right = 1.0
	top_bar.offset_bottom = 46.0
	_ui_root.add_child(top_bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	top_bar.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	_info_label = _make_label("战斗", 17)
	_info_label.name = "BattleInfoLabel"
	_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_info_label)

	_control_label = _make_label("", 14)
	_control_label.name = "BattleControlLabel"
	row.add_child(_control_label)

	_alive_label = _make_label("", 16)
	_alive_label.name = "BattleAliveLabel"
	row.add_child(_alive_label)

	_retreat_button = _make_button("撤退", "BattleRetreatButton")
	_retreat_button.tooltip_text = "主动撤退并结束战斗"
	_retreat_button.pressed.connect(_on_retreat_pressed)
	row.add_child(_retreat_button)

	var hint := _make_label("WASD 移动 · 鼠标左键攻击", 14)
	hint.name = "BattleHintLabel"
	hint.anchor_left = 0.0
	hint.anchor_top = 1.0
	hint.anchor_right = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_top = -34.0
	hint.offset_bottom = -8.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color("#f3ead6"))
	hint.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	hint.add_theme_constant_override("shadow_offset_x", 1)
	hint.add_theme_constant_override("shadow_offset_y", 1)
	_ui_root.add_child(hint)

	_result_dim = ColorRect.new()
	_result_dim.name = "BattleResultDim"
	_result_dim.color = Color(0.0, 0.0, 0.0, 0.5)
	_result_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_dim.visible = false
	_set_full_rect(_result_dim)
	_ui_root.add_child(_result_dim)

	_result_panel = PanelContainer.new()
	_result_panel.name = "BattleResultPanel"
	_result_panel.visible = false
	_result_panel.anchor_left = 0.5
	_result_panel.anchor_top = 0.5
	_result_panel.anchor_right = 0.5
	_result_panel.anchor_bottom = 0.5
	_result_panel.offset_left = -280.0
	_result_panel.offset_top = -230.0
	_result_panel.offset_right = 280.0
	_result_panel.offset_bottom = 230.0
	_ui_root.add_child(_result_panel)

	var panel_margin := MarginContainer.new()
	panel_margin.add_theme_constant_override("margin_left", 22)
	panel_margin.add_theme_constant_override("margin_right", 22)
	panel_margin.add_theme_constant_override("margin_top", 20)
	panel_margin.add_theme_constant_override("margin_bottom", 20)
	_result_panel.add_child(panel_margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel_margin.add_child(column)

	_result_label = _make_label("", 26)
	_result_label.name = "BattleResultLabel"
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_result_label)

	_result_summary_label = _make_label("", 14)
	_result_summary_label.name = "BattleResultSummaryLabel"
	_result_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_result_summary_label)

	_result_casualties_label = _make_label("", 14)
	_result_casualties_label.name = "BattleResultCasualtiesLabel"
	_result_casualties_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_casualties_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_result_casualties_label)

	_result_exp_label = _make_label("", 14)
	_result_exp_label.name = "BattleResultExpLabel"
	_result_exp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_result_exp_label)

	_result_reward_label = _make_label("", 14)
	_result_reward_label.name = "BattleResultRewardLabel"
	_result_reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_result_reward_label)

	_return_button = _make_button("返回大地图", "BattleReturnButton")
	_return_button.custom_minimum_size = Vector2(0.0, 42.0)
	_return_button.pressed.connect(_on_return_pressed)
	column.add_child(_return_button)

	_build_control_transfer_ui()


func _build_control_transfer_ui() -> void:
	_control_dim = ColorRect.new()
	_control_dim.name = "ControlTransferDim"
	_control_dim.color = Color(0.0, 0.0, 0.0, 0.55)
	_control_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_control_dim.visible = false
	_set_full_rect(_control_dim)
	_ui_root.add_child(_control_dim)

	_control_panel = PanelContainer.new()
	_control_panel.name = "ControlTransferPanel"
	_control_panel.visible = false
	_control_panel.anchor_left = 0.5
	_control_panel.anchor_top = 0.5
	_control_panel.anchor_right = 0.5
	_control_panel.anchor_bottom = 0.5
	_control_panel.offset_left = -280.0
	_control_panel.offset_top = -250.0
	_control_panel.offset_right = 280.0
	_control_panel.offset_bottom = 250.0
	_ui_root.add_child(_control_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_control_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := _make_label("玩家角色已失去战斗能力", 24)
	title.name = "ControlTransferTitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var subtitle := _make_label("选择一名存活友军接管，或进入观战。", 14)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 250.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	_control_list = VBoxContainer.new()
	_control_list.name = "ControlTransferList"
	_control_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_control_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_control_list)

	_control_status_label = _make_label("", 13)
	_control_status_label.name = "ControlTransferStatusLabel"
	_control_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_control_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_control_status_label)

	_spectate_button = _make_button("观战", "BattleSpectateButton")
	_spectate_button.custom_minimum_size = Vector2(0.0, 40.0)
	_spectate_button.pressed.connect(_on_spectate_pressed)
	column.add_child(_spectate_button)


func _spawn_units() -> void:
	_side_order = _session.get_side_indices()
	for side_index: int in _side_order:
		_side_controllers[side_index] = [] as Array[UnitController]
		_spawn_side(side_index)

	for side_index: int in _side_order:
		var enemies: Array[UnitController] = []
		for other_side: int in _side_order:
			if other_side == side_index:
				continue
			enemies.append_array(_side_controllers[other_side] as Array[UnitController])
		_enemy_controllers_by_side[side_index] = enemies

	_update_alive_label()


func _spawn_side(side_index: int) -> void:
	var unit_ids: Array[String] = _session.get_side_unit_ids(side_index)
	var total: int = unit_ids.size()
	var controllers := _side_controllers[side_index] as Array[UnitController]
	for i: int in range(total):
		var unit_id: String = unit_ids[i]
		var unit := _context.unit_manager.get_unit(unit_id)
		var state := _session.get_unit_state(unit_id)
		if unit == null or state == null:
			push_warning("战斗场景跳过无效单位: %s" % unit_id)
			continue
		# 玩家加入前已经发生的离屏伤亡不应在屏幕战斗中重新生成。
		if not state.alive or state.battle_hp <= 0:
			continue

		var player_side: bool = side_index == _player_side
		state.battle_position = _spawn_position(
			i, total, side_index, _side_order.size()
		)
		var actor := UnitActor.new()
		characters.add_child(actor)
		actor.setup(
			unit, state, player_side, _visual_equipment_configs(unit)
		)

		var controller := UnitController.new()
		controller.setup(unit, state, player_side, actor, Rect2(Vector2.ZERO, BATTLEFIELD_SIZE))
		controller.side_index = side_index

		_actors[unit_id] = actor
		_controllers[unit_id] = controller
		controllers.append(controller)


## 为 UnitVisual 提供当前装备槽位的视觉配置；缺失配置时保持默认长矛/头部。
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


func _spawn_position(
	index: int, total: int, side_index: int, side_count: int
) -> Vector2:
	var columns: int = 2
	var rows: int = maxi(1, ceili(float(total) / float(columns)))
	var row: int = index / columns
	var column: int = index % columns

	if side_count <= 2:
		var is_attacker: bool = side_index == 0
		var direction: float = 1.0 if is_attacker else -1.0
		var base_x: float = SPAWN_MARGIN_X if is_attacker else BATTLEFIELD_SIZE.x - SPAWN_MARGIN_X
		var x: float = base_x + direction * float(column) * SPAWN_SPACING_X
		var y: float = BATTLEFIELD_SIZE.y * 0.5 \
			+ (float(row) - (float(rows) - 1.0) * 0.5) * SPAWN_SPACING_Y
		return Vector2(x, y)

	# 多方战斗：围绕战场中心分配区域，避免与左右两侧重叠。
	var anchor := _side_anchor(side_index)
	var spread_x: float = (float(column) - 0.5) * SPAWN_SPACING_X
	var spread_y: float = (float(row) - (float(rows) - 1.0) * 0.5) * SPAWN_SPACING_Y
	return Vector2(anchor.x + spread_x, anchor.y + spread_y)


func _side_anchor(side_index: int) -> Vector2:
	var center := BATTLEFIELD_SIZE * 0.5
	match side_index:
		0:
			return Vector2(SPAWN_MARGIN_X, center.y)
		1:
			return Vector2(BATTLEFIELD_SIZE.x - SPAWN_MARGIN_X, center.y)
		2:
			return Vector2(center.x, BATTLEFIELD_SIZE.y - 160.0)
		3:
			return Vector2(center.x, 160.0)
		_:
			return center


func _process_deaths() -> void:
	for side_index: int in _side_order:
		var controllers := _side_controllers.get(side_index, []) as Array[UnitController]
		for controller: UnitController in controllers:
			_handle_controller_death(controller)


func _handle_controller_death(controller: UnitController) -> void:
	if controller == null or controller.is_alive():
		return
	if _handled_deaths.has(controller.unit_id):
		return
	_handled_deaths[controller.unit_id] = true

	var actor := _actors.get(controller.unit_id) as UnitActor
	if is_instance_valid(actor):
		actor.play_death()
	_actors.erase(controller.unit_id)
	controller.actor = null


func _update_alive_label() -> void:
	if _alive_label == null:
		return
	var player_alive := _count_side_alive(_player_side)
	var enemy_alive: int = 0
	for side_index: int in _side_order:
		if side_index != _player_side:
			enemy_alive += _count_side_alive(side_index)
	_alive_label.text = "我方：%d    敌方：%d" % [player_alive, enemy_alive]
	if _control_label != null:
		if _spectating:
			_control_label.text = "观战中"
		elif _controlled_controller != null and _controlled_controller.is_alive():
			_control_label.text = "控制：%s" % (
				_controlled_controller.unit_data.display_name
			)
		else:
			_control_label.text = ""


func _count_side_alive(side_index: int) -> int:
	var controllers := _side_controllers.get(side_index, []) as Array[UnitController]
	var count: int = 0
	for controller: UnitController in controllers:
		if controller.is_alive():
			count += 1
	return count


func _count_alive(controllers: Array[UnitController]) -> int:
	var count: int = 0
	for controller: UnitController in controllers:
		if controller.is_alive():
			count += 1
	return count


func _check_battle_end() -> void:
	var alive_sides: Array[int] = []
	for side_index: int in _side_order:
		if _count_side_alive(side_index) > 0:
			alive_sides.append(side_index)
	if alive_sides.size() > 1:
		return

	_battle_over = true
	_winning_side = -1 if alive_sides.is_empty() else alive_sides[0]
	_session.winning_side_index = _winning_side
	_result = _result_for_winning_side(_winning_side)
	if _retreat_button != null:
		_retreat_button.disabled = true
	_show_result()


func _on_retreat_pressed() -> void:
	if _battle_over or _scene_paused or _session == null:
		return
	if not _battle_manager.retreat_side(_player_side):
		return
	_battle_over = true
	_winning_side = -1
	_session.winning_side_index = -1
	_result = BattleSession.BattleResult.RETREATED
	if _retreat_button != null:
		_retreat_button.disabled = true
	_show_result()


func _result_for_winning_side(winning_side: int) -> BattleSession.BattleResult:
	if winning_side < 0:
		return BattleSession.BattleResult.DRAW
	if winning_side == 0:
		return BattleSession.BattleResult.ATTACKER_VICTORY
	if winning_side == 1:
		return BattleSession.BattleResult.DEFENDER_VICTORY
	return BattleSession.BattleResult.SIDE_VICTORY


func _resolve_player_side() -> int:
	var player_id: String = GameManager.player_party_id
	if player_id.is_empty() and _context != null:
		player_id = _context.player_party_id
	var side_index: int = _session.get_side_of_party(player_id)
	return side_index if side_index >= 0 else 0


func _show_result() -> void:
	# 结果面板优先于控制权转移面板。
	_scene_paused = false
	if _control_dim != null:
		_control_dim.visible = false
	if _control_panel != null:
		_control_panel.visible = false

	_result_dim.visible = true
	_result_panel.visible = true
	if _result == BattleSession.BattleResult.RETREATED:
		_result_label.text = "已撤退"
	elif _winning_side < 0:
		_result_label.text = "平局"
	elif _winning_side == _player_side:
		_result_label.text = "战斗胜利"
	else:
		_result_label.text = "战斗失败"

	_result_data = _battle_manager.build_battle_result(_session, int(_result))
	_refresh_result_labels()
	_update_alive_label()


func _refresh_result_labels() -> void:
	if _result_data == null:
		return
	_result_summary_label.text = _build_result_summary()
	_result_casualties_label.text = _build_casualties_summary()
	_result_exp_label.text = "获得经验：+%d" % _result_data.player_exp_gained
	var reward_lines: Array[String] = []
	reward_lines.append("获得金币：%d" % _result_data.reward_gold)
	if _result_data.reward_items.is_empty():
		reward_lines.append("战利品：无")
	else:
		reward_lines.append("战利品：%s" % "、".join(_result_data.reward_items))
	_result_reward_label.text = "\n".join(reward_lines)


func _build_result_summary() -> String:
	if _result_data == null:
		return ""
	var lines: Array[String] = []
	for side_index: int in _side_order:
		var names := _side_display_names(side_index)
		var tag := "参战方"
		if side_index == _result_data.winning_side_index:
			tag = "胜利方"
		elif _result_data.retreated_side_indices.has(side_index):
			tag = "撤退方"
		lines.append("%s：%s" % [tag, names])
	return "\n".join(lines)


func _build_casualties_summary() -> String:
	if _result_data == null:
		return ""
	var lines: Array[String] = []
	lines.append("我方：存活 %d / 阵亡 %d" % [
		_result_data.get_side_survivors(_player_side),
		_result_data.get_side_casualties(_player_side),
	])
	for side_index: int in _side_order:
		if side_index == _player_side:
			continue
		lines.append("敌方（%s）：存活 %d / 阵亡 %d" % [
			_side_display_names(side_index),
			_result_data.get_side_survivors(side_index),
			_result_data.get_side_casualties(side_index),
		])
	return "\n".join(lines)


func _side_display_names(side_index: int) -> String:
	var names: Array[String] = []
	if _session == null:
		return "未知"
	for party_id: String in _session.get_side_party_ids(side_index):
		var party := _context.party_manager.get_party(party_id)
		names.append(party.party_name if party != null else party_id)
	return "、".join(names) if not names.is_empty() else "未知"


func _on_return_pressed() -> void:
	if _returned:
		return
	_returned = true
	_return_button.disabled = true

	if _battle_manager != null and _session != null \
			and _battle_manager.current_battle == _session:
		if not _battle_manager.finish_battle(_session.battle_id, int(_result)):
			push_error("战斗结算失败")

	var error: Error = SceneManager.change_scene(SceneManager.WORLD_MAP_SCENE)
	if error != OK:
		push_error("无法返回大地图（错误码 %s）" % error)


func _abort_to_world_map() -> void:
	if _battle_manager != null and _session != null:
		_battle_manager.abort_battle(_session.battle_id)
	SceneManager.change_scene(SceneManager.WORLD_MAP_SCENE)


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
	button.custom_minimum_size = Vector2(0.0, 36.0)
	button.focus_mode = Control.FOCUS_NONE
	return button
