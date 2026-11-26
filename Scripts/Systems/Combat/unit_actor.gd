class_name UnitActor
extends Node2D
## 战斗场景中的单个士兵表现节点。
##
## 只读取 UnitData 的静态属性与 BattleUnitState 的战斗状态，不修改 UnitData。
## 士兵外观由 UnitVisual 组合临时素材；本节点只负责选中圈、血条与名称。
## 死亡后本节点先保留为尸体播放倒地/留存/淡出，再自行清理；
## 权威状态仍保留在 BattleSession 中等待结算。

const UnitVisualScript = preload("res://Scripts/Systems/Combat/unit_visual.gd")

const SELECTION_RADIUS: float = 20.0
const SELECTION_RADIUS_MOUNTED: float = 27.0

## 角色整体动态排序：战场按实时 Y 计算每个角色的排序名次，本节点获得
## `rank × SORT_Z_STRIDE` 的 z 波段；人物/马匹/武器等部件仍使用相对负 z，
## 因此同一个角色的所有非影子部件始终整体位于其他角色之上或之下。
##
## 仅靠 YSort 不足：部件相对负 z 不同，会在不同角色之间形成不同的绝对 z，
## 后排角色的武器（-10）可能压过前排角色的身体（-80）。CanvasGroup 也不能
## 隔离子级 z，因此显式给角色根节点分层。实际 canvas z =
## Characters.z + 本节点 z + 部件相对 z。
const ACTOR_Z_INDEX: int = 0
## 相邻角色 z 波段间隔。必须大于角色内部非影子层级的跨度
## （RIGHT_HAND_WEAPON = -10 到 LEG_LEFT = -80，跨度 70），
## 才能保证前排最低的部件仍高于后排最高的部件。
const SORT_Z_STRIDE: int = 72
## Characters.z = 200，部件最高相对 z = -10，引擎 z 上限 4096：
## 200 + rank × 72 - 10 ≤ 4096 ⇒ rank ≤ 54。超出时钳制并告警。
const SORT_Z_MAX_RANK: int = 54

## 实际位移速度高于阈值视为跑动；停止后保留短暂缓冲，避免待机/跑动抖动。
const MOVE_SPEED_THRESHOLD: float = 8.0
const MOVE_STATE_BUFFER: float = 0.12

## 受击白闪持续时间：开始时全白，随后线性回落。
const HIT_FLASH_DURATION: float = 0.12

## 尸体表现状态机。死亡数据状态（BattleUnitState.alive）与视觉留存状态分离：
## 尸体仍可见时，单位已经不可战斗、不参与 AI、不改变胜负结算。
enum CorpseState {
	NONE,
	FALLING,
	LINGERING,
	FADING,
}

var unit_data: UnitData = null
var battle_state: BattleUnitState = null
var is_player_side: bool = false
var is_controlled: bool = false
var visual: Node2D = null
## 由战斗场景注入的倒地/留存/淡出时长；为空时使用 CorpseConfig 默认值。
var corpse_config: CorpseConfig = null

var _facing: float = -1.0
var _name_label: Label = null
var _health_bar: UnitHealthBar = null
var _attack_flash: float = 0.0
var _visual_moving: bool = false
var _move_buffer: float = 0.0
var _hit_flash_remaining: float = 0.0
## 当前排序名次；0 为最靠后。只由战斗场景按实时 Y 写入。
var _sort_rank: int = 0
## 尸体表现状态与计时；不影响 BattleUnitState 或战斗结算。
var _corpse_state: CorpseState = CorpseState.NONE
var _corpse_timer: float = 0.0
## 由 UnitController 注入：动画到达有效命中帧时回调。
var attack_hit_callback: Callable = Callable()
## 独立的影子根节点：所有士兵影子统一位于角色层之下的 Shadow 层，
## 避免角色按 Y 排序后，前排影子覆盖后排身体。
var _shadow_root: Node2D = null


func setup(
	data: UnitData,
	state: BattleUnitState,
	player_side: bool,
	equipment_configs: Dictionary = {},
	shadow_parent: Node2D = null,
	corpse: CorpseConfig = null
) -> void:
	unit_data = data
	battle_state = state
	is_player_side = player_side
	corpse_config = corpse
	name = "UnitActor_%s" % data.unit_id
	position = state.battle_position
	z_index = ACTOR_Z_INDEX

	if shadow_parent != null and is_instance_valid(shadow_parent):
		_shadow_root = Node2D.new()
		_shadow_root.name = "UnitShadow_%s" % data.unit_id
		_shadow_root.position = position
		shadow_parent.add_child(_shadow_root)

	# UnitVisual 仍是一个完整子树；跨角色顺序由本节点的 z 波段决定，
	# 内部部件继续使用 VisualLayers 的相对 z。
	visual = UnitVisualScript.new()
	visual.name = "Visual"
	add_child(visual)
	if _shadow_root != null:
		visual.set_shadow_layer(_shadow_root)
	visual.setup(data, equipment_configs)
	if visual.has_signal("attack_hit_frame"):
		var handler := Callable(self, "_on_visual_attack_hit_frame")
		if not visual.is_connected("attack_hit_frame", handler):
			visual.connect("attack_hit_frame", handler)
	if _shadow_root != null:
		_shadow_root.scale.x = _facing

	_create_label()
	_create_health_bar()
	queue_redraw()


func _process(delta: float) -> void:
	if battle_state == null:
		return
	# 尸体阶段独立推进：不再同步战斗位置、不再播放移动/受击/攻击表现。
	if _corpse_state != CorpseState.NONE:
		_tick_corpse(delta)
		return

	var new_position: Vector2 = battle_state.battle_position
	var moved_distance: float = position.distance_to(new_position)
	var speed: float = moved_distance / maxf(delta, 0.0001)
	position = new_position
	if _shadow_root != null and is_instance_valid(_shadow_root):
		_shadow_root.position = position

	if speed >= MOVE_SPEED_THRESHOLD:
		_visual_moving = true
		_move_buffer = MOVE_STATE_BUFFER
	else:
		_move_buffer = maxf(0.0, _move_buffer - delta)
		if _move_buffer <= 0.0:
			_visual_moving = false

	if is_instance_valid(visual):
		# 支持战斗中装备/卸下马匹后立即切换步兵/骑兵表现，不重建节点。
		if unit_data != null and visual.is_mounted_visual() != unit_data.is_mounted:
			visual.set_mounted(unit_data.is_mounted)
		visual.update_locomotion(delta, _visual_moving)

	if _attack_flash > 0.0:
		_attack_flash = maxf(0.0, _attack_flash - delta)
		if _attack_flash <= 0.0 and is_instance_valid(visual):
			visual.set_attack_flash(false)
	if _hit_flash_remaining > 0.0:
		_hit_flash_remaining = maxf(0.0, _hit_flash_remaining - delta)
		if is_instance_valid(visual):
			visual.set_hit_flash_strength(
				_hit_flash_remaining / HIT_FLASH_DURATION
			)
	if _health_bar != null and unit_data != null:
		_health_bar.update_health(
			battle_state.battle_hp, unit_data.max_hp, battle_state.alive
		)
	queue_redraw()


func set_controlled(value: bool) -> void:
	if is_controlled != value:
		is_controlled = value
		queue_redraw()
	_update_name_visibility()


## 普通士兵隐藏头顶名称；只有玩家当前控制的单位显示名称。
func _update_name_visibility() -> void:
	if _name_label != null:
		_name_label.visible = is_controlled


## 返回是否成功播放攻击动画；没有动画节点/武器枢轴时返回 false，
## UnitController 据此回退为立即结算（纯数据测试等无表现场景）。
func play_attack(direction: Vector2 = Vector2.LEFT) -> bool:
	_attack_flash = 0.18
	var started: bool = false
	if is_instance_valid(visual):
		visual.set_attack_flash(true)
		started = bool(visual.play_attack_animation(direction))
	queue_redraw()
	return started


## 弓箭攻击表现：拉弓/放箭；箭矢与伤害由 UnitController / ProjectileManager 负责。
func play_ranged_attack(direction: Vector2 = Vector2.LEFT) -> void:
	_attack_flash = 0.0
	if is_instance_valid(visual):
		visual.play_ranged_attack_animation(direction)
		visual.set_attack_flash(true)
	queue_redraw()


## 受击反馈：白闪 + 受击动作 + 取消当前攻击表现。
## 只由真实伤害结算调用；未命中/0 伤害不会触发。
func play_hit_feedback(direction: Vector2 = Vector2.ZERO) -> void:
	_hit_flash_remaining = HIT_FLASH_DURATION
	_attack_flash = 0.0
	if is_instance_valid(visual):
		visual.set_attack_flash(false)
		visual.set_hit_flash_strength(1.0)
		visual.cancel_attack_animation()
		visual.play_hit_reaction(direction)
	queue_redraw()


func is_hit_flashing() -> bool:
	return _hit_flash_remaining > 0.0


## 供测试/调试确定性推进攻击动画；正式运行由 HumanVisual._process 推进。
func advance_attack_animation(delta: float) -> void:
	if is_instance_valid(visual):
		visual.advance_animation(delta)


func _on_visual_attack_hit_frame() -> void:
	if attack_hit_callback.is_valid():
		attack_hit_callback.call()


## 当前右手武器枢轴的世界坐标；弓的发射位置从这里取样。
## 没有武器枢轴时返回 Vector2.INF，调用方使用单位地面坐标作为回退。
func get_weapon_pivot_global_position() -> Vector2:
	if is_instance_valid(visual):
		var pivot: Node2D = visual.get_weapon_pivot()
		if pivot != null:
			return pivot.global_position
	return Vector2.INF


func is_attack_animating() -> bool:
	return is_instance_valid(visual) and visual.is_attack_animating()


## 仅挥动/刺出阶段锁定朝向，攻击后的长矛保持姿态不阻止移动转身。
func is_attack_pose_locked() -> bool:
	return is_instance_valid(visual) and visual.is_attack_pose_locked()


func is_visual_moving() -> bool:
	return _visual_moving


func set_facing(direction_x: float) -> void:
	if absf(direction_x) < 0.01:
		return
	var new_facing: float = 1.0 if direction_x > 0.0 else -1.0
	if not is_equal_approx(new_facing, _facing):
		_facing = new_facing
		if is_instance_valid(visual):
			visual.set_facing(_facing)
		if _shadow_root != null and is_instance_valid(_shadow_root):
			_shadow_root.scale.x = _facing
		queue_redraw()


## 开始死亡表现：倒地 → 留存 → 淡出 → 移除视觉对象。
## 只改变表现层；战斗数据、胜负与结算在此之前已由 BattleManager 处理。
func play_death() -> void:
	if _corpse_state != CorpseState.NONE:
		return
	_corpse_state = CorpseState.FALLING
	_corpse_timer = 0.0
	# 冻结在死亡位置：排序基准仍为脚底世界坐标，倒地旋转不会改变排序。
	if battle_state != null:
		position = battle_state.battle_position
	_attack_flash = 0.0
	_hit_flash_remaining = 0.0
	_visual_moving = false
	_move_buffer = 0.0
	# 尸体不再显示选中圈、名称与生命条。
	set_controlled(false)
	if _health_bar != null and unit_data != null:
		_health_bar.update_health(0, unit_data.max_hp, false)
	if is_instance_valid(visual):
		visual.set_attack_flash(false)
		visual.set_hit_flash_strength(0.0)
		visual.play_death_fall(_get_corpse_fall_duration())
	queue_redraw()


func _tick_corpse(delta: float) -> void:
	var step: float = maxf(0.0, delta)
	_corpse_timer += step
	match _corpse_state:
		CorpseState.FALLING:
			var finished: bool = (
				not is_instance_valid(visual) or visual.advance_death_animation(step)
			)
			if finished:
				_corpse_state = CorpseState.LINGERING
				_corpse_timer = 0.0
		CorpseState.LINGERING:
			if _corpse_timer >= _get_corpse_linger_duration():
				_corpse_state = CorpseState.FADING
				_corpse_timer = 0.0
				if is_instance_valid(visual):
					visual.capture_corpse_shadow_alpha()
		CorpseState.FADING:
			var fade_duration: float = _get_corpse_fade_duration()
			var fade_t: float = (
				1.0 if fade_duration <= 0.0
				else clampf(_corpse_timer / fade_duration, 0.0, 1.0)
			)
			if is_instance_valid(visual):
				visual.set_corpse_alpha(1.0 - fade_t)
			if fade_t >= 1.0:
				# 影子在 _exit_tree 中随视觉对象一起清理，不会残留。
				queue_free()


func _get_corpse_fall_duration() -> float:
	if corpse_config != null:
		return maxf(0.0, corpse_config.fall_duration)
	return CorpseConfig.DEFAULT_FALL_DURATION


func _get_corpse_linger_duration() -> float:
	if corpse_config != null:
		return maxf(0.0, corpse_config.linger_duration)
	return CorpseConfig.DEFAULT_LINGER_DURATION


func _get_corpse_fade_duration() -> float:
	if corpse_config != null:
		return maxf(0.0, corpse_config.fade_duration)
	return CorpseConfig.DEFAULT_FADE_DURATION


func get_corpse_state() -> CorpseState:
	return _corpse_state


## 死亡表现已开始（倒地/留存/淡出任一阶段）。
func is_corpse_sequence_active() -> bool:
	return _corpse_state != CorpseState.NONE


func is_corpse_visible() -> bool:
	if _corpse_state == CorpseState.NONE:
		return false
	if _corpse_state != CorpseState.FADING:
		return true
	return is_instance_valid(visual) and visual.get_corpse_alpha() > 0.0


func get_corpse_alpha() -> float:
	if not is_instance_valid(visual):
		return 0.0
	return visual.get_corpse_alpha()


## 由战斗场景按实时 Y 排序后写入名次。所有非影子部件随根节点整体移动，
## 因此不会出现部分贴图提前/滞后切换层级。
func apply_sort_rank(rank: int) -> void:
	var clamped_rank: int = clampi(rank, 0, SORT_Z_MAX_RANK)
	if rank > SORT_Z_MAX_RANK and rank == SORT_Z_MAX_RANK + 1:
		push_warning(
			"战斗角色数量超过整体排序名次上限 %d，多余单位共用最后层级"
			% (SORT_Z_MAX_RANK + 1)
		)
	_sort_rank = clamped_rank
	var target_z: int = _sort_rank * SORT_Z_STRIDE
	if z_index != target_z:
		z_index = target_z


func get_sort_rank() -> int:
	return _sort_rank


## 部件最终相对角色层（Characters）的 z；用于测试与调试。
## 影子位于独立层，不参与该计算。
func get_part_canvas_z(part_name: String) -> int:
	var unit_visual := visual as UnitVisual
	if unit_visual == null:
		return z_index
	return z_index + unit_visual.get_part_effective_z(part_name)


func _exit_tree() -> void:
	# 影子属于独立层级，必须随士兵表现节点一起清理，避免残留。
	if _shadow_root != null and is_instance_valid(_shadow_root):
		_shadow_root.queue_free()
		_shadow_root = null


func get_shadow_root() -> Node2D:
	return _shadow_root


func _draw() -> void:
	if unit_data == null or battle_state == null:
		return

	if is_controlled:
		var radius: float = (
			SELECTION_RADIUS_MOUNTED if unit_data.is_mounted else SELECTION_RADIUS
		)
		draw_arc(
			Vector2.ZERO,
			radius,
			0.0,
			TAU,
			32,
			Color("#ffd75e"),
			2.5,
			true
		)

	# 倒地尸体保留完整姿态，不再叠画死亡叉号；叉号只用于尚未开始尸体表现的异常状态。
	if not battle_state.alive and _corpse_state == CorpseState.NONE:
		draw_line(Vector2(-10.0, -10.0), Vector2(10.0, 10.0), Color(0.0, 0.0, 0.0, 0.7), 2.5)


func _create_health_bar() -> void:
	_health_bar = UnitHealthBar.new()
	_health_bar.name = "HealthBar"
	_health_bar.setup(unit_data.max_hp if unit_data != null else 1)
	add_child(_health_bar)


func get_health_bar() -> UnitHealthBar:
	return _health_bar


func get_name_label() -> Label:
	return _name_label


func is_name_visible() -> bool:
	return _name_label != null and _name_label.visible


func _create_label() -> void:
	_name_label = Label.new()
	_name_label.name = "NameLabel"
	_name_label.text = unit_data.display_name
	# 默认隐藏；由 set_controlled() 按当前控制权切换，不影响生命条。
	_name_label.visible = is_controlled
	_name_label.position = Vector2(-50.0, -70.0)
	_name_label.size = Vector2(100.0, 18.0)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.theme = UiTheme.create()
	_name_label.add_theme_font_size_override("font_size", 11)
	_name_label.add_theme_color_override("font_color", Color.WHITE)
	_name_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_name_label)
