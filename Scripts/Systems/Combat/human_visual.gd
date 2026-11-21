class_name HumanVisual
extends "res://Scripts/Systems/Combat/part_visual.gd"
## 人物部件表现：身体、头部、双腿、罩袍、影子与长矛。
##
## 骑乘时本节点整体上移 15 像素；马匹部件由 HorseVisual 独立管理，不随此偏移。
## 长矛使用独立旋转枢轴；伤害与冷却仍由 CombatRules / UnitController 负责，
## 本类只播放视觉动画，不产生任何伤害事件。

const Layers = preload("res://Scripts/Systems/Combat/visual_layers.gd")

const ART_DIR: String = "res://art/我的骑砍临时美术/"
const SHADOW_FOOT_PATH: String = ART_DIR + "人影子.png"
const BODY_PATH: String = ART_DIR + "角色身体临时.png"
const HEAD_PATH: String = ART_DIR + "角色头部临时.png"
const LEG_LEFT_PATH: String = ART_DIR + "角色左腿临时.png"
const LEG_RIGHT_PATH: String = ART_DIR + "角色右腿临时.png"
const WEAPON_SPEAR_PATH: String = ART_DIR + "武器长矛临时.png"
const TABARD_SHADER_PATH: String = "res://Shaders/faction_tabard.gdshader"
const PLUME_TEXTURE_PATH: String = ""
const PLUME_PART_NAME: String = "Plume"

## 骑乘时人物整体相对原始位置向上移动 15 像素；马匹不移动，UnitActor 世界坐标不变。
const MOUNTED_CHARACTER_OFFSET_Y: float = -15.0
## 骑乘时人物整体已跟随马身上下运动，上半身只保留少量独立起伏，避免双重弹跳。
const MOUNTED_RIDER_BOB_SCALE: float = 0.2

## 长矛实际贴图为 48×96，设计坐标原点为左下角。
const SPEAR_TEXTURE_SIZE := Vector2(48.0, 96.0)
const SPEAR_PIVOT_FROM_BOTTOM_LEFT := Vector2(24.0, 18.0)
## 设计稿中人物身体上的锚点（96×32、左下角原点），保留为参考值。
const BODY_WEAPON_ANCHOR_DESIGN := Vector2(33.0, 18.0)
## 当前 48×96 临时身体贴图中的握持点。
## 设计稿身体锚点 (33,18)（左下角原点）→ 素材左上角 (33,78)
## → 以脚底中心为原点的画布坐标 (33-24, 78-92) = (9,-14)。
const BODY_WEAPON_ANCHOR := Vector2(9.0, -14.0)

## 长矛动画参数集中配置。
const SPEAR_IDLE_ROTATION: float = 0.0
## Godot 2D 的 Y 轴向下，负角度在视觉上是逆时针；朝左时矛尖指向左侧。
const SPEAR_ATTACK_ROTATION: float = -PI * 0.5
## 前摇：沿攻击方向的反方向轻微后移，并旋转到攻击角度。
const SPEAR_WINDUP_TIME: float = 0.14
const SPEAR_WINDUP_BACK_DISTANCE: float = 2.5
## 戳击：沿攻击方向快速伸出。
const SPEAR_THRUST_TIME: float = 0.14
const SPEAR_THRUST_FORWARD_DISTANCE: float = 6.0
## 兼容旧名称：旧测试/探针仍用该常量表示戳击阶段时长。
const SPEAR_THRUST_HOLD_TIME: float = SPEAR_THRUST_TIME
## 刺击结束后继续保持攻击姿态的等待时间（秒）。
## 需求范围 3–5 秒；集中在这里调整，默认 4 秒。
const SPEAR_POST_ATTACK_HOLD_TIME: float = 4.0
## 兼容旧名称：现在表示攻击后的完整保持时间。
const SPEAR_POST_ATTACK_DELAY: float = SPEAR_POST_ATTACK_HOLD_TIME
const SPEAR_RECOVER_TIME: float = 0.35

const WEAPON_FLASH_COLOR: Color = Color(1.7, 1.35, 0.55)
const WEAPON_NORMAL_COLOR: Color = Color.WHITE

## 待机/跑动动画参数集中配置。
const IDLE_BOB_AMPLITUDE: float = 0.8
const IDLE_BOB_PERIOD: float = 2.4
const RUN_BOB_AMPLITUDE: float = 2.2
const RUN_BOB_PERIOD: float = 0.50
const IDLE_TILT_AMPLITUDE: float = 0.008
const RUN_TILT_AMPLITUDE: float = 0.018
const IDLE_SWAY_AMPLITUDE: float = 0.020
const RUN_SWAY_AMPLITUDE: float = 0.055
## 待机时头部独立微摆；跑动时也保留极小幅度，避免头部完全僵死。
const IDLE_HEAD_SWAY: float = 0.015
const RUN_HEAD_SWAY: float = 0.006
## 双腿步态集中参数。向前/后摆动使用水平位移，抬脚使用向下的负 Y；
## 两条腿共享同一振幅与相位差（PI），只让领先腿抬起，避免一条腿“陷入地面”。
## 腿部只作为辅助表现，振幅刻意保持克制，避免抢过身体动作的视觉注意力。
const RUN_LEG_SWING_X: float = 0.2
const RUN_LEG_LIFT_Y: float = 0.0
const RUN_LEG_ROTATION: float = 0.005
## 腿部旋转中心相对最初脚底锚点累计向下移动的像素数：
## 上一轮 3 px + 本轮 3 px = 6 px（实际历史校验后只应用过一轮 3 px）。
## 精灵 offset 下移同样数值、节点基础位置补回，可见位置保持不变。
const LEG_PIVOT_DROP_Y: float = 6.0
const LEG_REST_POSITION := Vector2(0.0, LEG_PIVOT_DROP_Y)
const SWAY_FOLLOW_RATE: float = 4.0

enum AnimationPhase {
	IDLE,
	WINDUP,
	THRUST,
	POST_DELAY,
	RECOVER,
}

var _weapon_pivot: Node2D = null
var _upper_body: Node2D = null
var _mounted: bool = false
var _plume_texture_path: String = PLUME_TEXTURE_PATH
var _attack_phase: AnimationPhase = AnimationPhase.IDLE
var _phase_time: float = 0.0
var _windup_start_rotation: float = 0.0
var _windup_start_position: Vector2 = Vector2.ZERO
var _attack_target_rotation: float = SPEAR_ATTACK_ROTATION
var _weapon_back_offset: Vector2 = Vector2.ZERO
var _weapon_forward_offset: Vector2 = Vector2.ZERO
var _weapon_sway_target: float = 0.0
var _weapon_sway_current: float = 0.0


func rebuild(faction_color: Color, plume_texture_path: String = PLUME_TEXTURE_PATH) -> void:
	_plume_texture_path = plume_texture_path
	clear_parts()
	_weapon_pivot = null
	_upper_body = null
	_attack_phase = AnimationPhase.IDLE
	_phase_time = 0.0
	_windup_start_position = Vector2.ZERO
	_weapon_back_offset = Vector2.ZERO
	_weapon_forward_offset = Vector2.ZERO
	_weapon_sway_target = 0.0
	_weapon_sway_current = 0.0

	_add_sprite("FootShadow", SHADOW_FOOT_PATH, Layers.FOOT_SHADOW)

	# UpperBody 是人物整体运动的变换父节点：身体起伏/倾斜会同时带动双腿。
	_upper_body = Node2D.new()
	_upper_body.name = "UpperBody"
	add_child(_upper_body)

	# 双腿挂载在 UpperBody 下，先继承身体整体变换，再叠加自身小幅步态。
	_add_sprite("LegLeft", LEG_LEFT_PATH, Layers.LEG_LEFT, _upper_body)
	_add_sprite("LegRight", LEG_RIGHT_PATH, Layers.LEG_RIGHT, _upper_body)
	# 左右腿使用相同规则：旋转中心累计下移 6 px，可见位置不变。
	lower_part_pivot("LegLeft", LEG_PIVOT_DROP_Y)
	lower_part_pivot("LegRight", LEG_PIVOT_DROP_Y)

	_add_sprite("Body", BODY_PATH, Layers.BODY, _upper_body)
	_add_tabard(faction_color, _upper_body)

	# 武器枢轴：矛身绕该点旋转，枢轴位置与人物身体固定对齐。
	_weapon_pivot = Node2D.new()
	_weapon_pivot.name = "WeaponPivot"
	_weapon_pivot.position = BODY_WEAPON_ANCHOR
	_weapon_pivot.z_index = Layers.WEAPON
	_upper_body.add_child(_weapon_pivot)
	var spear_anchor := Vector2(
		SPEAR_PIVOT_FROM_BOTTOM_LEFT.x,
		SPEAR_TEXTURE_SIZE.y - SPEAR_PIVOT_FROM_BOTTOM_LEFT.y
	)
	_add_sprite("Weapon", WEAPON_SPEAR_PATH, 0, _weapon_pivot, spear_anchor)

	_add_sprite("Head", HEAD_PATH, Layers.HEAD, _upper_body)
	if not _plume_texture_path.is_empty():
		_add_sprite(PLUME_PART_NAME, _plume_texture_path, Layers.PLUME, _upper_body)

	set_mounted(_mounted)
	set_process(true)


## 骑乘时人物整体上移；影子互斥。可重复调用，切换时不重建节点。
func set_mounted(mounted: bool) -> void:
	_mounted = mounted
	position.y = MOUNTED_CHARACTER_OFFSET_Y if mounted else 0.0
	var foot_shadow := get_part("FootShadow")
	if foot_shadow != null:
		foot_shadow.visible = not mounted


func is_mounted_visual() -> bool:
	return _mounted


## 仅隐藏/显示武器表现；不修改 UnitData 的装备数据。
## 村庄场景用它在本次场景中显示“未持武器”的玩家。
func set_weapon_visible(value: bool) -> void:
	if _weapon_pivot == null:
		return
	_weapon_pivot.visible = value


func is_weapon_visible() -> bool:
	return _weapon_pivot != null and _weapon_pivot.visible


## 由 UnitVisual 统一驱动的待机/跑动动画。
## idle_time/run_time 是共享时间轴，blend 在 0（待机）和 1（跑动）之间平滑过渡。
## rider_offset_y 为骑乘时马身 rig 的当前垂直偏移；人物整体跟随它移动。
func update_locomotion(
	idle_time: float,
	run_time: float,
	blend: float,
	_delta: float,
	rider_offset_y: float = 0.0
) -> void:
	if _upper_body == null:
		return
	# 骑乘时整个人物视觉跟随马身；非骑乘时恢复为 0。
	position.y = (
		MOUNTED_CHARACTER_OFFSET_Y + rider_offset_y if _mounted else 0.0
	)

	var b: float = clampf(blend, 0.0, 1.0)
	var idle_phase: float = TAU * idle_time / IDLE_BOB_PERIOD
	var run_phase: float = TAU * run_time / RUN_BOB_PERIOD

	var bob: float = (
		sin(idle_phase) * IDLE_BOB_AMPLITUDE * (1.0 - b)
		+ sin(run_phase) * RUN_BOB_AMPLITUDE * b
	)
	if _mounted:
		bob *= MOUNTED_RIDER_BOB_SCALE
	_upper_body.position.y = bob
	_upper_body.rotation = (
		sin(idle_phase * 0.8) * IDLE_TILT_AMPLITUDE * (1.0 - b)
		+ sin(run_phase) * RUN_TILT_AMPLITUDE * b
	)

	# 头部跟随身体，同时保留极小幅度的独立摆动；待机时也不完全静止。
	var head := get_part("Head")
	if head != null:
		head.rotation = (
			sin(idle_phase * 0.75) * IDLE_HEAD_SWAY * (1.0 - b)
			+ sin(run_phase * 1.4 + 0.4) * RUN_HEAD_SWAY * b
		)

	# 左右腿使用同一振幅、相反相位的步态：一腿前摆时另一腿后摆。
	# 只有向前摆动的腿轻微抬起，另一条腿保持接地，避免出现“瘸腿”或陷地。
	var leg_swing: float = sin(run_phase) * b
	_apply_leg_pose(get_part("LegLeft"), leg_swing)
	_apply_leg_pose(get_part("LegRight"), -leg_swing)

	_weapon_sway_target = (
		sin(idle_phase * 0.9) * IDLE_SWAY_AMPLITUDE * (1.0 - b)
		+ sin(run_phase * 1.1) * RUN_SWAY_AMPLITUDE * b
	)


## swing > 0 表示该腿向前摆动：水平位移取负（本体朝左），同时抬脚并轻微旋转。
func _apply_leg_pose(leg: Sprite2D, swing: float) -> void:
	if leg == null:
		return
	# 以旋转中心下移后的基准位置为原点叠加动画；父级 UpperBody 负责身体整体变换。
	leg.position = LEG_REST_POSITION + Vector2(
		-swing * RUN_LEG_SWING_X,
		-maxf(0.0, swing) * RUN_LEG_LIFT_Y
	)
	leg.rotation = swing * RUN_LEG_ROTATION


func get_upper_body() -> Node2D:
	return _upper_body


func get_weapon_sway() -> float:
	return _weapon_sway_current


func get_weapon_sway_target() -> float:
	return _weapon_sway_target


func set_attack_flash(active: bool) -> void:
	var weapon := get_part("Weapon")
	if weapon == null:
		return
	weapon.modulate = WEAPON_FLASH_COLOR if active else WEAPON_NORMAL_COLOR


## 攻击时触发长矛动画；direction 是世界方向，动画会换算到人物局部并考虑整体镜像。
## 不阻止伤害、不改变冷却，也不重复触发任何伤害。
func play_attack_animation(direction: Vector2 = Vector2.LEFT) -> void:
	if _weapon_pivot == null:
		return
	# 人物组朝右时 scale.x = -1；局部方向需要先镜像，旋转后再由组镜像回世界方向。
	var facing_scale: float = -1.0 if scale.x < 0.0 else 1.0
	var local_direction := Vector2(direction.x * facing_scale, direction.y)
	if local_direction.length_squared() < 0.0001:
		local_direction = Vector2(0.0, -1.0)
	local_direction = local_direction.normalized()
	_attack_target_rotation = atan2(local_direction.x, -local_direction.y)
	# 由目标旋转反推出长矛的局部指向，前摇/戳击沿该轴做方向性位移。
	var spear_direction := Vector2(
		sin(_attack_target_rotation), -cos(_attack_target_rotation)
	)
	_weapon_back_offset = -spear_direction * SPEAR_WINDUP_BACK_DISTANCE
	_weapon_forward_offset = spear_direction * SPEAR_THRUST_FORWARD_DISTANCE
	_windup_start_rotation = _weapon_pivot.rotation
	_windup_start_position = _weapon_pivot.position
	_weapon_sway_current = 0.0
	_attack_phase = AnimationPhase.WINDUP
	_phase_time = 0.0
	set_process(true)


## 供测试/调试确定性推进动画；_process 也会调用。
func advance_animation(delta: float) -> void:
	if _weapon_pivot == null or _attack_phase == AnimationPhase.IDLE:
		return
	_phase_time += delta
	match _attack_phase:
		AnimationPhase.WINDUP:
			var windup_t: float = clampf(_phase_time / SPEAR_WINDUP_TIME, 0.0, 1.0)
			var windup_ease: float = _ease(windup_t)
			_weapon_pivot.rotation = lerp_angle(
				_windup_start_rotation,
				_attack_target_rotation,
				windup_ease
			)
			_weapon_pivot.position = _windup_start_position.lerp(
				BODY_WEAPON_ANCHOR + _weapon_back_offset, windup_ease
			)
			if windup_t >= 1.0:
				_weapon_pivot.rotation = _attack_target_rotation
				_weapon_pivot.position = BODY_WEAPON_ANCHOR + _weapon_back_offset
				_attack_phase = AnimationPhase.THRUST
				_phase_time = 0.0
		AnimationPhase.THRUST:
			var thrust_t: float = clampf(_phase_time / SPEAR_THRUST_TIME, 0.0, 1.0)
			var thrust_ease: float = _ease(thrust_t)
			_weapon_pivot.rotation = _attack_target_rotation
			_weapon_pivot.position = (
				(BODY_WEAPON_ANCHOR + _weapon_back_offset).lerp(
					BODY_WEAPON_ANCHOR + _weapon_forward_offset, thrust_ease
				)
			)
			if thrust_t >= 1.0:
				_weapon_pivot.position = BODY_WEAPON_ANCHOR + _weapon_forward_offset
				_attack_phase = AnimationPhase.POST_DELAY
				_phase_time = 0.0
		AnimationPhase.POST_DELAY:
			# 保持攻击后的持握姿态；移动/待机动画不会覆盖这里的角度与位移。
			_weapon_pivot.rotation = _attack_target_rotation
			_weapon_pivot.position = BODY_WEAPON_ANCHOR + _weapon_forward_offset
			if _phase_time >= SPEAR_POST_ATTACK_HOLD_TIME:
				_attack_phase = AnimationPhase.RECOVER
				_phase_time = 0.0
		AnimationPhase.RECOVER:
			var recover_t: float = clampf(_phase_time / SPEAR_RECOVER_TIME, 0.0, 1.0)
			var recover_ease: float = _ease(recover_t)
			_weapon_pivot.rotation = lerp_angle(
				_attack_target_rotation,
				SPEAR_IDLE_ROTATION,
				recover_ease
			)
			_weapon_pivot.position = (
				(BODY_WEAPON_ANCHOR + _weapon_forward_offset).lerp(
					BODY_WEAPON_ANCHOR, recover_ease
				)
			)
			if recover_t >= 1.0:
				_weapon_pivot.rotation = SPEAR_IDLE_ROTATION
				_weapon_pivot.position = BODY_WEAPON_ANCHOR
				_attack_phase = AnimationPhase.IDLE
				_phase_time = 0.0
				_weapon_sway_current = 0.0


func _process(delta: float) -> void:
	if _attack_phase != AnimationPhase.IDLE:
		advance_animation(delta)
	elif _weapon_pivot != null:
		# 攻击优先；非攻击时才追踪待机/跑动的武器晃动目标。
		_weapon_sway_current = move_toward(
			_weapon_sway_current, _weapon_sway_target, delta * SWAY_FOLLOW_RATE
		)
		_weapon_pivot.rotation = _weapon_sway_current


func get_weapon_pivot() -> Node2D:
	return _weapon_pivot


func get_weapon_rotation() -> float:
	return _weapon_pivot.rotation if _weapon_pivot != null else 0.0


func get_attack_target_rotation() -> float:
	return _attack_target_rotation


func get_attack_phase() -> AnimationPhase:
	return _attack_phase


func is_attack_animating() -> bool:
	return _attack_phase != AnimationPhase.IDLE


## 只有真正挥动/刺出的阶段锁定朝向；攻击后保持姿态期间允许角色转身移动。
func is_attack_pose_locked() -> bool:
	return (
		_attack_phase == AnimationPhase.WINDUP
		or _attack_phase == AnimationPhase.THRUST
	)


func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _add_tabard(faction_color: Color, parent: Node) -> void:
	var tabard := _add_sprite("Tabard", BODY_PATH, Layers.TABARD, parent)
	if tabard == null:
		return

	var shader: Shader = null
	if ResourceLoader.exists(TABARD_SHADER_PATH):
		shader = load(TABARD_SHADER_PATH) as Shader
	if shader == null:
		tabard.modulate = faction_color
		return

	var tabard_material := ShaderMaterial.new()
	tabard_material.shader = shader
	tabard_material.set_shader_parameter("faction_color", faction_color)
	tabard.material = tabard_material
