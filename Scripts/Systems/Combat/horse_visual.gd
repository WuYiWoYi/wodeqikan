class_name HorseVisual
extends "res://Scripts/Systems/Combat/part_visual.gd"
## 马匹部件表现：骑马影子、四条独立马腿、马身、马鞍与马头。
##
## 本节点只在骑乘状态可见；步行时整体隐藏。马匹不随人物骑乘偏移移动。
## 马身/马鞍/马头放在独立 rig 中一起起伏；四条腿各自独立运动，影子保持稳定。

const Layers = preload("res://Scripts/Systems/Combat/visual_layers.gd")

const SHADOW_MOUNTED_PATH: String = "res://art/我的骑砍临时美术/骑马的影子.png"

## 动画参数集中配置；人物与马匹共享 UnitVisual 的 run/idle 时间轴。
## 周期与 HumanVisual 保持一致，避免骑手与马身起伏明显脱节。
const IDLE_BOB_AMPLITUDE: float = 0.9
const IDLE_BOB_PERIOD: float = 2.4
## 整体跃动仍为主运动，但降低上下波动，避免骑兵组合起伏过于明显。
const RUN_BOB_AMPLITUDE: float = 4.2
const RUN_BOB_PERIOD: float = 0.50
const IDLE_BODY_PITCH: float = 0.004
## 奔跑时马身随伸展/收缩前后俯仰；负值表示顶部向前（默认朝左）倾斜。
const RUN_BODY_PITCH: float = 0.028
const IDLE_BREATH_SCALE: float = 0.006
## 躯干伸展/压缩适度增强，但保持远低于“橡皮感”的幅度。
const RUN_BODY_STRETCH_X: float = 0.028
const RUN_BODY_SQUASH: float = 0.012
const IDLE_HEAD_SWAY: float = 0.012
const RUN_HEAD_SWAY: float = 0.040
const RUN_HEAD_BOB: float = 0.55
## 跃马式四肢：两只前腿成组向前伸、两只后腿成组向后伸，再同步收缩。
## 组内只保留极小的相位错位，避免看起来完全相同，但不形成人类交替步态。
## 马身整体跃动为主，腿部做适度可见的辅助动作；仍远小于身体主运动。
const IDLE_LEG_AMPLITUDE: float = 0.10
const RUN_FRONT_LEG_REACH_X: float = 0.6
const RUN_BACK_LEG_REACH_X: float = 0.6
const RUN_LEG_LIFT_Y: float = 0.0
const IDLE_LEG_ROTATION: float = 0.010
const RUN_FRONT_LEG_ROTATION: float = 0.020
const RUN_BACK_LEG_ROTATION: float = 0.020
const LEG_GROUP_STAGGER: float = 0.12
## 影子随马身抬升轻微缩小/变淡；幅度克制，不需要新素材或层级变化。
const SHADOW_LIFT_SCALE_FACTOR: float = 0.04
const SHADOW_LIFT_ALPHA_FACTOR: float = 0.15
## 四条马腿的旋转中心相对最初脚底锚点累计向下移动的像素数：
## 3 px + 3 px + 3 px = 9 px。所有腿使用同一规则，可见位置保持不变。
const LEG_PIVOT_DROP_Y: float = 9.0

const FRONT_LEG_PART_NAMES: Array[String] = ["MountLegFront", "MountLegFront2"]
const BACK_LEG_PART_NAMES: Array[String] = ["MountLegBack", "MountLegBack2"]

## 骑乘单位死亡时马匹随骑手一同倒地；只倾斜马身 rig，不重建部件。
const DEATH_COLLAPSE_ANGLE: float = 0.45
const DEATH_COLLAPSE_SINK: float = 5.0
const DEATH_COLLAPSE_SQUASH: float = 0.12

var _body_rig: Node2D = null
var _coat_style_id: String = "brown"
var _saddle_style_id: String = "saddle_01"
var _death_pose_locked: bool = false
var _death_fall_active: bool = false
var _death_fall_time: float = 0.0
var _death_fall_duration: float = 0.55


## 按马匹实例的毛色与马鞍重建部件。只替换贴图路径，动画结构保持不变。
func rebuild(
	coat_style_id: String = "brown",
	saddle_style_id: String = "saddle_01"
) -> void:
	clear_parts()
	_body_rig = null
	_coat_style_id = coat_style_id
	_saddle_style_id = saddle_style_id
	_death_pose_locked = false
	_death_fall_active = false
	_death_fall_time = 0.0
	_death_fall_duration = 0.55
	var paths: Dictionary = MountVisualConfig.get_coat_paths(coat_style_id)
	_add_sprite("MountShadow", SHADOW_MOUNTED_PATH, Layers.MOUNT_SHADOW)

	# HorseBodyRig 是马匹整体运动的变换父节点：马身起伏/俯仰/缩放会同时带动四条腿。
	_body_rig = Node2D.new()
	_body_rig.name = "HorseBodyRig"
	add_child(_body_rig)

	# 四条马腿挂载在 rig 下，先继承马身整体变换，再叠加各自的小幅跃马动作。
	_add_sprite(
		"MountLegFront", str(paths["front_leg_1"]), Layers.MOUNT_LEG_FRONT, _body_rig
	)
	_add_sprite(
		"MountLegFront2", str(paths["front_leg_2"]), Layers.MOUNT_LEG_FRONT_2, _body_rig
	)
	_add_sprite(
		"MountLegBack", str(paths["back_leg_1"]), Layers.MOUNT_LEG_BACK, _body_rig
	)
	_add_sprite(
		"MountLegBack2", str(paths["back_leg_2"]), Layers.MOUNT_LEG_BACK_2, _body_rig
	)
	for leg_name: String in FRONT_LEG_PART_NAMES + BACK_LEG_PART_NAMES:
		lower_part_pivot(leg_name, LEG_PIVOT_DROP_Y)

	_add_sprite("MountBody", str(paths["body"]), Layers.MOUNT_BODY, _body_rig)
	_add_sprite(
		"MountSaddle",
		MountVisualConfig.get_saddle_path(saddle_style_id),
		Layers.MOUNT_SADDLE,
		_body_rig
	)
	_add_sprite("MountHead", str(paths["head"]), Layers.MOUNT_HEAD, _body_rig)


func get_coat_style_id() -> String:
	return _coat_style_id


func get_saddle_style_id() -> String:
	return _saddle_style_id


func update_locomotion(
	idle_time: float, run_time: float, blend: float, _delta: float
) -> void:
	if _body_rig == null or _death_pose_locked:
		return
	var b: float = clampf(blend, 0.0, 1.0)
	var idle_phase: float = TAU * idle_time / IDLE_BOB_PERIOD
	var run_phase: float = TAU * run_time / RUN_BOB_PERIOD

	# 跃马周期：extension = 1 时前腿组前伸、后腿组后伸；-1 时两组收缩。
	var extension: float = sin(run_phase)
	var idle_breath: float = sin(idle_phase) * IDLE_BREATH_SCALE * (1.0 - b)

	# 伸展跃出时马身整体向上（负 Y），收缩落地时向下回落。
	_body_rig.position.y = (
		sin(idle_phase) * IDLE_BOB_AMPLITUDE * (1.0 - b)
		- extension * RUN_BOB_AMPLITUDE * b
	)
	_body_rig.rotation = (
		sin(idle_phase * 0.8) * IDLE_BODY_PITCH * (1.0 - b)
		- extension * RUN_BODY_PITCH * b
	)
	_body_rig.scale = Vector2(
		1.0 + extension * RUN_BODY_STRETCH_X * b - idle_breath * 0.35,
		1.0 - extension * RUN_BODY_SQUASH * b + idle_breath
	)

	# 马匹抬高时影子轻微缩小/变淡，回落时恢复；只改 scale/alpha，不动位置与层级。
	var shadow := get_part("MountShadow")
	if shadow != null:
		var lift_ratio: float = clampf(
			-_body_rig.position.y / RUN_BOB_AMPLITUDE, 0.0, 1.0
		)
		var shadow_scale: float = 1.0 - lift_ratio * SHADOW_LIFT_SCALE_FACTOR
		shadow.scale = Vector2(shadow_scale, shadow_scale)
		var shadow_color := shadow.modulate
		shadow_color.a = 1.0 - lift_ratio * SHADOW_LIFT_ALPHA_FACTOR
		shadow.modulate = shadow_color

	# 马头保留独立于身体的轻微摆动与起伏。
	var head := get_part("MountHead")
	if head != null:
		head.rotation = (
			sin(idle_phase * 0.9) * IDLE_HEAD_SWAY * (1.0 - b)
			+ sin(run_phase * 1.25 + 0.6) * RUN_HEAD_SWAY * b
		)
		head.position.y = sin(run_phase * 1.25 + 0.6) * RUN_HEAD_BOB * b

	# 前腿组与后腿组使用相反相位；组内仅保留很小的错位。
	for i: int in range(FRONT_LEG_PART_NAMES.size()):
		var stagger: float = float(i) * LEG_GROUP_STAGGER
		_apply_leg_pose(
			get_part(FRONT_LEG_PART_NAMES[i]),
			idle_phase + stagger,
			run_phase + stagger,
			RUN_FRONT_LEG_REACH_X,
			RUN_FRONT_LEG_ROTATION,
			b
		)
		_apply_leg_pose(
			get_part(BACK_LEG_PART_NAMES[i]),
			idle_phase + stagger,
			run_phase + PI + stagger,
			RUN_BACK_LEG_REACH_X,
			RUN_BACK_LEG_ROTATION,
			b
		)


## 单条马腿的局部动画：父级 HorseBodyRig 已负责整体跃动/俯仰/缩放，这里只叠加小动作。
## run_wave > 0 时向前/向后伸展（由前后组相位决定），< 0 时收缩。
func _apply_leg_pose(
	leg: Sprite2D,
	idle_phase: float,
	run_phase: float,
	reach_x: float,
	reach_rotation: float,
	blend: float
) -> void:
	if leg == null:
		return
	var idle_wave: float = sin(idle_phase)
	var run_wave: float = sin(run_phase)
	var run_extent: float = run_wave * blend
	leg.position = Vector2(
		-run_extent * reach_x,
		LEG_PIVOT_DROP_Y
			+ idle_wave * IDLE_LEG_AMPLITUDE * (1.0 - blend)
			- maxf(0.0, run_wave) * RUN_LEG_LIFT_Y * blend
	)
	leg.rotation = (
		idle_wave * IDLE_LEG_ROTATION * (1.0 - blend)
		+ run_extent * reach_rotation
	)


## 死亡倒地：马身 rig 随骑手一同倾斜、下沉并轻微压扁。
## 只改变表现变换，不移动 UnitActor 世界坐标（排序基准保持脚底位置）。
func play_death_collapse(duration: float) -> void:
	if _death_pose_locked or _body_rig == null:
		return
	_death_pose_locked = true
	_death_fall_active = true
	_death_fall_time = 0.0
	_death_fall_duration = maxf(duration, 0.001)
	_apply_death_pose(0.0)


func advance_death_animation(delta: float) -> bool:
	if not _death_fall_active or _body_rig == null:
		return true
	_death_fall_time = minf(
		_death_fall_duration, _death_fall_time + maxf(delta, 0.0)
	)
	var t: float = clampf(_death_fall_time / _death_fall_duration, 0.0, 1.0)
	_apply_death_pose(t)
	if t >= 1.0:
		_death_fall_active = false
		return true
	return false


func _apply_death_pose(t: float) -> void:
	if _body_rig == null:
		return
	var eased: float = t * t * (3.0 - 2.0 * t)
	_body_rig.rotation = DEATH_COLLAPSE_ANGLE * eased
	_body_rig.position = Vector2(0.0, DEATH_COLLAPSE_SINK * eased)
	_body_rig.scale = Vector2(1.0, 1.0 - DEATH_COLLAPSE_SQUASH * eased)


func is_death_pose_locked() -> bool:
	return _death_pose_locked


func get_body_rig() -> Node2D:
	return _body_rig


## 当前马身 rig 的垂直偏移；UnitVisual 用它驱动骑手整体跟随。
func get_body_offset_y() -> float:
	return _body_rig.position.y if _body_rig != null else 0.0
