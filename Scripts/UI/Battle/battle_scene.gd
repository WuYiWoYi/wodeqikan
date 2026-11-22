class_name BattleScene
extends Node2D
## 战斗场景控制器：读取 BattleSession，生成 UnitActor，驱动实时战斗与结果返回。
##
## 只读取 UnitData 的静态属性，伤害写入 BattleUnitState；
## 战斗结算统一由 BattleManager.finish_battle() 执行。

const ProjectileManagerScript = preload(
	"res://Scripts/Systems/Combat/projectile_manager.gd"
)

## 有效战场面积约为旧 1280×720 的 2 倍（1800×1024 ≈ 1.999 倍）。
## 士兵像素尺寸、动画比例与相机视野（960×540）保持不变，扩大的只是可移动区域。
const BATTLEFIELD_WIDTH: float = 1800.0
const BATTLEFIELD_HEIGHT: float = 1024.0
const BATTLEFIELD_SIZE := Vector2(BATTLEFIELD_WIDTH, BATTLEFIELD_HEIGHT)
## 初始部署参数：双方分别部署在左右两侧，阵线间距由 INITIAL_ARMY_DISTANCE 控制。
## 所有屏幕战斗创建入口（玩家遭遇、AI 遭遇、多方中途加入）共用这一组参数，
## 不允许在其它脚本中写死另一套初始距离。
const INITIAL_ARMY_DISTANCE: float = 1580.0
const SPAWN_MARGIN_X: float = (
	(BATTLEFIELD_WIDTH - INITIAL_ARMY_DISTANCE) * 0.5
)
const INITIAL_DEPLOYMENT_DISTANCE: float = BATTLEFIELD_WIDTH - SPAWN_MARGIN_X * 2.0
const SPAWN_SPACING_X: float = 54.0
const SPAWN_SPACING_Y: float = 64.0

## 与村庄共用 SceneCameraRig.VIEW_SIZE（1920×1080 下为 2 倍缩放 / 960×540 区域）。
## 相机略向下偏移以显示底部地面。
const BATTLE_CAMERA_Y_OFFSET: float = 30.0

## 玩家获胜后结算面板的展示延迟（物理时间）。结算数据立即计算，只延迟 UI 展示。
const VICTORY_RESULT_DELAY: float = 3.0

## 增援部署：在当前阵线后方生成，避免与已参战单位重叠。
const REINFORCEMENT_REAR_DISTANCE: float = 240.0
const REINFORCEMENT_MIN_SPACING: float = 38.0
const REINFORCEMENT_PROMPT_DURATION: float = 2.8

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
## 临时箭矢的唯一创建/推进入口；箭矢节点挂在 Characters 下参与 YSort。
var _projectile_manager: Variant = null

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
## 结果面板已展示（防止延迟期间或重复调用重复弹出）。
var _result_shown: bool = false
## 玩家胜利时的延迟展示状态；用物理帧 delta 计时，不使用 WorldTime。
var _result_pending: bool = false
var _result_delay_remaining: float = 0.0
var _result_delay_enabled: bool = true

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

## 增援提示：队列逐条展示，不暂停战斗、不拦截输入。
var _reinforcement_panel: PanelContainer = null
var _reinforcement_badge: TextureRect = null
var _reinforcement_label: Label = null
var _reinforcement_queue: Array[Dictionary] = []
var _reinforcement_remaining: float = 0.0
## 已收到但尚未生成控制器的增援数；此间不判定战斗结束。
var _pending_reinforcement_spawns: int = 0


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
	_setup_projectiles()
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

	# 增援可能在屏幕战斗进行中随时加入；表现层只追加新单位，不改既有状态。
	if not EventBus.battle_participant_joined.is_connected(_on_battle_participant_joined):
		EventBus.battle_participant_joined.connect(_on_battle_participant_joined)
	if not EventBus.party_reinforced.is_connected(_on_party_reinforced):
		EventBus.party_reinforced.connect(_on_party_reinforced)

	queue_redraw()


func _process(delta: float) -> void:
	_tick_reinforcement_prompt(delta)


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
	if _session == null or _scene_paused:
		return
	if _result_pending:
		_tick_result_delay(delta)
		return
	if _battle_over:
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

	# 单位完成本帧移动/射击后再推进箭矢，命中检测使用最新地面坐标。
	if _projectile_manager != null:
		_projectile_manager.advance(delta)

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


func get_projectile_manager() -> Variant:
	return _projectile_manager


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
			# 近战单位占用前排槽位，远程单位排到后排，避免弓箭手被顶到阵线最前。
			var ordered := _order_controllers_for_slots(controllers)
			var formation_type: FormationManager.FormationType = (
				_party_formations.get(party_id, _default_formation)
				as FormationManager.FormationType
			)
			var spacing: float = FORMATION_SPACING
			for controller: UnitController in ordered:
				if controller.unit_data != null and controller.unit_data.is_mounted:
					spacing = FORMATION_SPACING_MOUNTED
					break
			if loose_spacing:
				spacing *= CONTACT_SPACING_MULTIPLIER
			var slots := _formation_manager.compute_slots(
				formation_type, ordered.size(), spacing
			)
			var lane: float = (
				(float(party_index) - (float(party_count) - 1.0) * 0.5)
				* PARTY_LANE_SPACING
			)
			var center: Vector2 = line_center + right * lane
			if _party_move_orders.has(party_id):
				center = _party_move_orders[party_id] as Vector2
			var count: int = mini(ordered.size(), slots.size())
			for i: int in range(count):
				var local := slots[i]
				var world_slot := center + forward * local.x + right * local.y
				ordered[i].set_formation_slot(world_slot)


## 保持近战/远程各自原有相对顺序；远程追加在末尾，占据队形后排槽位。
func _order_controllers_for_slots(
	controllers: Array[UnitController]
) -> Array[UnitController]:
	var melee: Array[UnitController] = []
	var ranged: Array[UnitController] = []
	for controller: UnitController in controllers:
		if controller.is_ranged_unit():
			ranged.append(controller)
		else:
			melee.append(controller)
	melee.append_array(ranged)
	return melee


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

	var hint := _make_label("WASD 移动 · 鼠标左键攻击/射箭", 14)
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

	_build_reinforcement_prompt()

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


# ---------------------------------------------------------------------------
# 增援：表现层追加单位与提示
# ---------------------------------------------------------------------------


func _build_reinforcement_prompt() -> void:
	_reinforcement_panel = PanelContainer.new()
	_reinforcement_panel.name = "ReinforcementPromptPanel"
	_reinforcement_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reinforcement_panel.anchor_left = 0.5
	_reinforcement_panel.anchor_right = 0.5
	_reinforcement_panel.offset_left = -320.0
	_reinforcement_panel.offset_right = 320.0
	_reinforcement_panel.offset_top = 54.0
	_reinforcement_panel.offset_bottom = 104.0
	_reinforcement_panel.visible = false
	_ui_root.add_child(_reinforcement_panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_reinforcement_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	_reinforcement_badge = TextureRect.new()
	_reinforcement_badge.name = "ReinforcementBannerBadge"
	_reinforcement_badge.custom_minimum_size = Vector2(32.0, 32.0)
	_reinforcement_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_reinforcement_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_reinforcement_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reinforcement_badge.visible = false
	row.add_child(_reinforcement_badge)

	_reinforcement_label = _make_label("", 16)
	_reinforcement_label.name = "ReinforcementPromptLabel"
	_reinforcement_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reinforcement_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_reinforcement_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reinforcement_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_reinforcement_label)


func _on_battle_participant_joined(
	battle_id: String, party_id: String, side_index: int
) -> void:
	if _session == null or battle_id != _session.battle_id or _battle_over:
		return
	if _session.get_party_unit_ids(party_id).is_empty():
		return
	_pending_reinforcement_spawns += 1
	call_deferred("_spawn_reinforcement_party", party_id, side_index)


## 只有加入玩家所在战斗侧的 NPC 部队才提示，避免玩家自己或敌军增援刷屏。
func _on_party_reinforced(
	battle_id: String, party_id: String, noble_id: String, side_index: int
) -> void:
	if _session == null or battle_id != _session.battle_id or _battle_over:
		return
	if _context == null or party_id == _context.player_party_id:
		return
	if side_index != _player_side:
		return
	_queue_reinforcement_message(_build_reinforcement_message(party_id, noble_id))


func _build_reinforcement_message(party_id: String, noble_id: String) -> Dictionary:
	var party := _context.party_manager.get_party(party_id)
	var noble: NobleData = null
	if _context.noble_manager != null and not noble_id.is_empty():
		noble = _context.noble_manager.get_noble(noble_id)
	var display_name: String = ""
	if noble != null:
		display_name = noble.display_name
	elif party != null and not party.party_name.is_empty():
		# 无贵族部队使用真实部队名，不猜测或拼接未配置的称呼。
		display_name = party.party_name
	else:
		display_name = "友军"

	var house_name: String = ""
	var banner: Texture2D = null
	if noble != null and _context.house_manager != null \
			and not noble.house_id.is_empty():
		var house := _context.house_manager.get_house(noble.house_id)
		if house != null:
			house_name = house.house_name
			var family := _context.family_registry.get_config(house.banner_id) \
				if _context.family_registry != null else null
			if family != null and not family.banner_texture_path.is_empty() \
					and ResourceLoader.exists(family.banner_texture_path):
				banner = load(family.banner_texture_path) as Texture2D

	var text: String = ""
	if banner != null and not house_name.is_empty():
		text = "是%s的旗帜，%s带部队来增援我们了！" % [house_name, display_name]
	else:
		text = "%s带部队来增援我们了！" % display_name
	return {"text": text, "banner": banner}


func _queue_reinforcement_message(message: Dictionary) -> void:
	if message.is_empty():
		return
	_reinforcement_queue.append(message)
	if _reinforcement_panel != null and not _reinforcement_panel.visible:
		_show_next_reinforcement_message()


func _show_next_reinforcement_message() -> void:
	if _battle_over or _reinforcement_panel == null or _reinforcement_queue.is_empty():
		return
	var message: Dictionary = _reinforcement_queue.pop_front()
	_reinforcement_label.text = str(message.get("text", ""))
	var banner := message.get("banner") as Texture2D
	_reinforcement_badge.texture = banner
	_reinforcement_badge.visible = banner != null
	_reinforcement_panel.visible = true
	_reinforcement_panel.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_reinforcement_panel, "modulate:a", 1.0, 0.2)
	_reinforcement_remaining = REINFORCEMENT_PROMPT_DURATION


func _tick_reinforcement_prompt(delta: float) -> void:
	if _reinforcement_panel == null:
		return
	if _battle_over:
		_reinforcement_panel.visible = false
		_reinforcement_queue.clear()
		return
	if not _reinforcement_panel.visible:
		if not _reinforcement_queue.is_empty():
			_show_next_reinforcement_message()
		return
	_reinforcement_remaining = maxf(0.0, _reinforcement_remaining - delta)
	if _reinforcement_remaining <= 0.0:
		_reinforcement_panel.visible = false


## 把新参战部队的单位追加到既有战斗侧；不触碰其他控制器、冷却或战斗状态。
func _spawn_reinforcement_party(party_id: String, side_index: int) -> void:
	_pending_reinforcement_spawns = maxi(0, _pending_reinforcement_spawns - 1)
	if _battle_over or _session == null or _context == null:
		return
	if not _session.is_party_involved(party_id):
		return
	_ensure_side_registered()
	var unit_ids: Array[String] = _session.get_party_unit_ids(party_id)
	if unit_ids.is_empty():
		return

	var origin := _reinforcement_rear_position(side_index)
	var away := _reinforcement_away_direction(side_index)
	var controllers := _side_controllers.get(side_index, []) as Array[UnitController]
	var spawned: int = 0
	for unit_id: String in unit_ids:
		if _controllers.has(unit_id):
			continue
		var spawn_pos := _find_free_reinforcement_position(origin, away)
		var controller := _create_unit_controller(unit_id, side_index, spawn_pos)
		if controller == null:
			continue
		if _projectile_manager != null:
			controller.set_projectile_manager(_projectile_manager)
		controllers.append(controller)
		spawned += 1
	if spawned == 0:
		return
	_side_controllers[side_index] = controllers
	_rebuild_enemy_controller_lists()
	_update_alive_label()
	_refresh_neighbor_cache()
	_refresh_target_claims()


func _ensure_side_registered() -> void:
	_side_order = _session.get_side_indices()
	for side: int in _side_order:
		if not _side_controllers.has(side):
			_side_controllers[side] = [] as Array[UnitController]
	_rebuild_enemy_controller_lists()


func _rebuild_enemy_controller_lists() -> void:
	_enemy_controllers_by_side.clear()
	for side_index: int in _side_order:
		var enemies: Array[UnitController] = []
		for other_side: int in _side_order:
			if other_side == side_index:
				continue
			enemies.append_array(
				_side_controllers.get(other_side, []) as Array[UnitController]
			)
		_enemy_controllers_by_side[side_index] = enemies


## 增援的“己方后方”以该战斗侧的初始部署区域为基准，
## 而不是当前友军质心：友军即使已经推进到战场中心，增援仍从后方进入。
func _reinforcement_rear_position(side_index: int) -> Vector2:
	return _side_anchor(side_index)


## 背离战场中心 / 敌方初始区域的方向。
## 两方与多方战斗都依据该侧的区域锚点，而不是固定 side_index 左右规则；
## 只有动态新增、没有固定锚点的战斗侧才回退到当前质心差。
func _reinforcement_away_direction(side_index: int) -> Vector2:
	var anchor := _side_anchor(side_index)
	var direction := anchor - BATTLEFIELD_SIZE * 0.5
	if direction.length_squared() >= 0.0001:
		return direction.normalized()

	var own := _alive_controllers_on_side(side_index)
	var own_center: Vector2 = _centroid(own) if not own.is_empty() else anchor
	var enemy_side := _nearest_enemy_side(side_index)
	var enemy := _alive_controllers_on_side(enemy_side) if enemy_side >= 0 \
		else [] as Array[UnitController]
	direction = own_center - (
		_centroid(enemy) if not enemy.is_empty() else BATTLEFIELD_SIZE * 0.5
	)
	if direction.length_squared() < 0.0001:
		direction = Vector2.LEFT if side_index == 1 else Vector2.RIGHT
	return direction.normalized()


func _find_free_reinforcement_position(
	origin: Vector2, away: Vector2
) -> Vector2:
	var right := Vector2(-away.y, away.x)
	# 后方基准点必须落在战场内；后续排数向战场中心方向展开。
	var rear := (origin + away * REINFORCEMENT_REAR_DISTANCE).clamp(
		Vector2(40.0, 60.0),
		BATTLEFIELD_SIZE - Vector2(40.0, 60.0)
	)
	var inward := -away
	var columns: int = 3
	for attempt: int in range(96):
		@warning_ignore("integer_division")
		var row: int = attempt / columns
		var column: int = attempt % columns
		var point: Vector2 = rear \
			+ right * ((float(column) - 1.0) * SPAWN_SPACING_X) \
			+ inward * float(row) * SPAWN_SPACING_Y
		point.x = clampf(point.x, 40.0, BATTLEFIELD_SIZE.x - 40.0)
		point.y = clampf(point.y, 60.0, BATTLEFIELD_SIZE.y - 60.0)
		# 增援不得越过战场中心进入敌方半场，即使后方网格已经排满。
		if (point - BATTLEFIELD_SIZE * 0.5).dot(away) < 0.0:
			continue
		if _is_spawn_point_free(point):
			return point

	# 3 列网格在己方半场排满（多方战斗的下/上侧尤其明显）时，
	# 退化为己方半场内的均匀扫描，优先选择间距足够的点。
	# 绝不直接返回已占用的 rear 基准点，避免增援重叠生成。
	return _find_spare_reinforcement_point(away, rear)


## 在背离战场中心的一侧扫描空闲点；优先满足最小间距，
## 全部被占满时返回间距最大的点，仍保证位于战场边界与己方半场。
func _find_spare_reinforcement_point(away: Vector2, fallback: Vector2) -> Vector2:
	var center := BATTLEFIELD_SIZE * 0.5
	var min_point := Vector2(40.0, 60.0)
	var max_point := BATTLEFIELD_SIZE - Vector2(40.0, 60.0)
	var step := REINFORCEMENT_MIN_SPACING
	var best := fallback
	var best_clearance: float = -1.0
	var y: float = min_point.y
	while y <= max_point.y:
		var x: float = min_point.x
		while x <= max_point.x:
			var point := Vector2(x, y)
			if (point - center).dot(away) >= 0.0:
				var clearance := _spawn_clearance(point)
				if clearance >= REINFORCEMENT_MIN_SPACING:
					return point
				if clearance > best_clearance:
					best_clearance = clearance
					best = point
			x += step
		y += step
	return best


## 候选点到最近存活单位的距离；没有单位时返回 INF。
func _spawn_clearance(point: Vector2) -> float:
	var clearance: float = INF
	for value: Variant in _controllers.values():
		var controller := value as UnitController
		if controller == null or not controller.is_alive():
			continue
		clearance = minf(
			clearance, controller.get_position().distance_to(point)
		)
	return clearance


func _is_spawn_point_free(point: Vector2) -> bool:
	for value: Variant in _controllers.values():
		var controller := value as UnitController
		if controller == null or not controller.is_alive():
			continue
		if controller.get_position().distance_to(point) < REINFORCEMENT_MIN_SPACING:
			return false
	return true


## 所有战斗单位共享一个发射物管理器；远程单位只通过它生成临时箭矢。
func _setup_projectiles() -> void:
	_projectile_manager = ProjectileManagerScript.new()
	_projectile_manager.setup(characters)
	for side_index: int in _side_order:
		var controllers := _side_controllers.get(
			side_index, []
		) as Array[UnitController]
		for controller: UnitController in controllers:
			controller.set_projectile_manager(_projectile_manager)


func _clear_projectiles() -> void:
	if _projectile_manager != null:
		_projectile_manager.clear()


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
		var spawn_pos := _spawn_position(
			i, total, side_index, _side_order.size()
		)
		var controller := _create_unit_controller(unit_id, side_index, spawn_pos)
		if controller != null:
			controllers.append(controller)


## 创建单个单位的表现与控制器。初始部署与增援共用，保证属性/装备一致。
func _create_unit_controller(
	unit_id: String, side_index: int, spawn_pos: Vector2
) -> UnitController:
	var unit := _context.unit_manager.get_unit(unit_id)
	var state := _session.get_unit_state(unit_id)
	if unit == null or state == null:
		push_warning("战斗场景跳过无效单位: %s" % unit_id)
		return null
	# 玩家加入前已经发生的离屏伤亡不应在屏幕战斗中重新生成。
	if not state.alive or state.battle_hp <= 0:
		return null
	if _controllers.has(unit_id):
		return _controllers.get(unit_id) as UnitController

	var player_side: bool = side_index == _player_side
	state.battle_position = spawn_pos
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
	return controller


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
			return Vector2(center.x, BATTLEFIELD_SIZE.y - BATTLEFIELD_SIZE.y * 0.22)
		3:
			return Vector2(center.x, BATTLEFIELD_SIZE.y * 0.22)
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
	if _pending_reinforcement_spawns > 0:
		return
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
	_prepare_result(true)


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
	_prepare_result(false)


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


## 结算数据立即计算；只有玩家获胜的结果面板展示延迟。
## 失败、撤退与平局保持原有即时展示。
func _prepare_result(allow_victory_delay: bool) -> void:
	_result_data = _battle_manager.build_battle_result(_session, int(_result))
	if allow_victory_delay and _result_delay_enabled and _is_player_victory():
		_result_pending = true
		_result_delay_remaining = VICTORY_RESULT_DELAY
		return
	_show_result()


func _is_player_victory() -> bool:
	return (
		_result != BattleSession.BattleResult.RETREATED
		and _winning_side >= 0
		and _winning_side == _player_side
	)


## 使用物理帧时间推进延迟；场景退出时节点销毁，计时自然取消。
func _tick_result_delay(delta: float) -> void:
	_result_delay_remaining -= delta
	if _result_delay_remaining > 0.0:
		return
	_result_pending = false
	_result_delay_remaining = 0.0
	_show_result()


## 测试钩子：关闭/开启玩家胜利的展示延迟。
func set_result_delay_enabled(enabled: bool) -> void:
	_result_delay_enabled = enabled


## 测试钩子：立即结束延迟并展示结果面板。
func skip_result_delay() -> void:
	if not _result_pending:
		return
	_result_pending = false
	_result_delay_remaining = 0.0
	_show_result()


func is_result_pending() -> bool:
	return _result_pending


func get_result_delay_remaining() -> float:
	return _result_delay_remaining


## 结果数据在胜负判定时立即生成；延迟只影响面板展示。
func get_result_data() -> BattleResultData:
	return _result_data


func _show_result() -> void:
	if _result_shown:
		return
	_result_shown = true
	_result_pending = false
	_clear_projectiles()
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
