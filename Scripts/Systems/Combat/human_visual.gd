class_name HumanVisual
extends "res://Scripts/Systems/Combat/part_visual.gd"
## 人物部件表现：身体、头部、双腿、罩袍、影子与长矛。
##
## 骑乘时本节点整体上移 15 像素；马匹部件由 HorseVisual 独立管理，不随此偏移。
## 长矛使用独立旋转枢轴；伤害与冷却仍由 CombatRules / UnitController 负责，
## 本类只播放视觉动画，不产生任何伤害事件。

const Layers = preload("res://Scripts/Systems/Combat/visual_layers.gd")

## 近战攻击进入有效命中帧时发出；每次攻击动画只发出一次。
## 本类只负责动画时序与事件，实际伤害由 UnitController 在事件回调中结算。
signal attack_hit_frame()

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
## 骑乘时人物贴图在上移基础上再向右偏移 3 像素（默认朝左）；只影响骑马状态，
## 马匹自身位置、步行状态与士兵世界坐标均不变。
const MOUNTED_CHARACTER_OFFSET_X: float = 3.0
## 骑乘且朝右时，在默认偏移基础上再向左修正 6 像素。
## 朝右会镜像人物的父节点，但节点 position 不会随 scale 翻转，因此必须按朝向
## 单独给出 X 偏移；净值 = 3 - 6 = -3，避免在镜像后重复叠加导致更大偏移。
const MOUNTED_CHARACTER_RIGHT_EXTRA_X: float = -6.0
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
## 左手武器枢轴；右侧对称位置，用于盾牌等副手装备。
const LEFT_HAND_WEAPON_ANCHOR := Vector2(-9.0, -14.0)

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
## 有效命中帧位于戳击阶段的这个比例处；伤害只在越过该帧后结算。
## 前摇与戳击前半段只播放动画，不产生任何伤害。
const SPEAR_HIT_FRAME_RATIO: float = 0.6
## 兼容旧名称：旧测试/探针仍用该常量表示戳击阶段时长。
const SPEAR_THRUST_HOLD_TIME: float = SPEAR_THRUST_TIME
## 刺击结束后继续保持攻击姿态的等待时间（秒）。
## 需求范围 3–5 秒；集中在这里调整，默认 4 秒。
const SPEAR_POST_ATTACK_HOLD_TIME: float = 4.0
## 兼容旧名称：现在表示攻击后的完整保持时间。
const SPEAR_POST_ATTACK_DELAY: float = SPEAR_POST_ATTACK_HOLD_TIME
const SPEAR_RECOVER_TIME: float = 0.35

## 弓箭动画参数。弓默认朝左，旋转 0 时箭矢沿人物左前方射出。
## 伤害/冷却仍由 UnitController 负责，本动画只表现拉弓与放箭。
const BOW_DRAW_TIME: float = 0.18
const BOW_RELEASE_TIME: float = 0.08
const BOW_RECOVER_TIME: float = 0.30
const BOW_DRAW_BACK_DISTANCE: float = 4.0
const BOW_RELEASE_FORWARD_DISTANCE: float = 2.0
const BOW_IDLE_ROTATION: float = 0.0

const WEAPON_FLASH_COLOR: Color = Color(1.7, 1.35, 0.55)
const WEAPON_NORMAL_COLOR: Color = Color.WHITE

## 受击动作：身体短暂向受击方向后仰。只作用于 UpperBody 变换，
## 人物、头盔、双腿、武器作为整体一起偏移，不产生图层错位。
const HIT_REACTION_TIME: float = 0.18
const HIT_REACTION_OFFSET: float = 4.0
const HIT_REACTION_TILT: float = 0.09

## 倒地动画：死亡后身体绕脚底枢轴向后倒下，倒地姿态永久保留。
## UpperBody 的局部正向旋转在人物镜像后视觉上始终朝“背后”倒，
## 因此无需按朝向切换符号，只需保证人物 scale.x 已按朝向设置。
const DEATH_FALL_ANGLE: float = 1.25
## 倒地过程中身体向后方/下方沉降的距离，避免看起来像原地旋转。
const DEATH_FALL_SINK: float = 2.0

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
	RANGED_DRAW,
	RANGED_RELEASE,
	RANGED_RECOVER,
}

var _weapon_pivot: Node2D = null
var _left_hand_weapon_pivot: Node2D = null
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
## 本次攻击是否已经发出有效命中帧；在新攻击开始时重置，防止重复伤害判定。
var _hit_frame_emitted: bool = false
## 受击动作剩余时间与局部击退方向（已按人物朝向换算到镜像前的局部坐标）。
var _hit_time_left: float = 0.0
var _hit_local_direction: Vector2 = Vector2.ZERO
## 阵营罩袍材质；用于受击白闪参数同步。家族罩袍/缺失 shader 时为 null。
var _tabard_material: ShaderMaterial = null
## 倒地姿态：一旦死亡即锁定，普通待机/跑动/受击动画不再覆盖。
var _death_pose_locked: bool = false
var _death_fall_active: bool = false
var _death_fall_time: float = 0.0
var _death_fall_duration: float = 0.55


func rebuild(
	faction_color: Color,
	plume_texture_path: String = PLUME_TEXTURE_PATH,
	tabard_texture_path: String = ""
) -> void:
	_plume_texture_path = plume_texture_path
	clear_parts()
	_weapon_pivot = null
	_left_hand_weapon_pivot = null
	_upper_body = null
	_attack_phase = AnimationPhase.IDLE
	_phase_time = 0.0
	_windup_start_position = Vector2.ZERO
	_weapon_back_offset = Vector2.ZERO
	_weapon_forward_offset = Vector2.ZERO
	_weapon_sway_target = 0.0
	_weapon_sway_current = 0.0
	_hit_frame_emitted = false
	_hit_time_left = 0.0
	_hit_local_direction = Vector2.ZERO
	_tabard_material = null
	_death_pose_locked = false
	_death_fall_active = false
	_death_fall_time = 0.0
	_death_fall_duration = 0.55

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
	_add_tabard(faction_color, _upper_body, tabard_texture_path)

	# 武器枢轴：矛身绕该点旋转，枢轴位置与人物身体固定对齐。
	_weapon_pivot = Node2D.new()
	_weapon_pivot.name = "WeaponPivot"
	_weapon_pivot.position = BODY_WEAPON_ANCHOR
	_weapon_pivot.z_index = Layers.RIGHT_HAND_WEAPON
	_upper_body.add_child(_weapon_pivot)
	var spear_anchor := Vector2(
		SPEAR_PIVOT_FROM_BOTTOM_LEFT.x,
		SPEAR_TEXTURE_SIZE.y - SPEAR_PIVOT_FROM_BOTTOM_LEFT.y
	)
	_add_sprite("Weapon", WEAPON_SPEAR_PATH, 0, _weapon_pivot, spear_anchor)

	# 左手武器使用独立枢轴与独立层级；默认没有贴图，等待装备配置注入。
	_left_hand_weapon_pivot = Node2D.new()
	_left_hand_weapon_pivot.name = "LeftHandWeaponPivot"
	_left_hand_weapon_pivot.position = LEFT_HAND_WEAPON_ANCHOR
	_left_hand_weapon_pivot.z_index = Layers.LEFT_HAND_WEAPON
	_upper_body.add_child(_left_hand_weapon_pivot)

	_add_sprite("Head", HEAD_PATH, Layers.HEAD, _upper_body)
	if not _plume_texture_path.is_empty():
		_add_sprite(PLUME_PART_NAME, _plume_texture_path, Layers.PLUME, _upper_body)

	set_mounted(_mounted)
	set_process(true)


## 骑乘时人物整体上移并向右偏移；影子互斥。可重复调用，切换时不重建节点。
func set_mounted(mounted: bool) -> void:
	_mounted = mounted
	_apply_mounted_position()
	var foot_shadow := get_part("FootShadow")
	if foot_shadow != null:
		foot_shadow.visible = not mounted


## 骑乘时的基础偏移：朝左为 +3，朝右在此基础上再向左 6 px。
## 只影响人物自身，马匹与士兵世界坐标不动。
func _mounted_offset() -> Vector2:
	if not _mounted:
		return Vector2.ZERO
	var offset_x: float = MOUNTED_CHARACTER_OFFSET_X
	if _facing > 0.0:
		offset_x += MOUNTED_CHARACTER_RIGHT_EXTRA_X
	return Vector2(offset_x, MOUNTED_CHARACTER_OFFSET_Y)


## 重新应用骑乘偏移；rider_offset_y 用于跟随马身上下运动。
func _apply_mounted_position(rider_offset_y: float = 0.0) -> void:
	var offset := _mounted_offset()
	position = Vector2(offset.x, offset.y + rider_offset_y)


## 朝向切换时需要同步更新骑乘偏移：镜像只改变 scale.x，不会翻转节点 position。
func set_facing(direction_x: float) -> void:
	var previous_facing: float = _facing
	super.set_facing(direction_x)
	if not is_equal_approx(previous_facing, _facing):
		_apply_mounted_position()


func is_mounted_visual() -> bool:
	return _mounted


## 仅隐藏/显示武器表现；不修改 UnitData 的装备数据。
## 村庄场景用它在本次场景中显示“未持武器”的玩家。
func set_weapon_visible(value: bool) -> void:
	if _weapon_pivot != null:
		_weapon_pivot.visible = value
	if _left_hand_weapon_pivot != null:
		_left_hand_weapon_pivot.visible = value


func is_weapon_visible() -> bool:
	return _weapon_pivot != null and _weapon_pivot.visible


## 右手武器贴图/层级覆盖；空路径恢复默认长矛。攻击动画仍使用同一枢轴。
func set_right_hand_weapon_texture(
	texture_path: String,
	layer_override: int = 0,
	anchor_pixels: Vector2 = Vector2(-1.0, -1.0)
) -> bool:
	if _weapon_pivot == null:
		return false
	remove_part("Weapon")
	var resolved_path: String = (
		texture_path if not texture_path.is_empty() else WEAPON_SPEAR_PATH
	)
	var resolved_layer: int = (
		layer_override if layer_override != 0 else Layers.RIGHT_HAND_WEAPON
	)
	_weapon_pivot.z_index = resolved_layer
	var resolved_anchor := anchor_pixels
	if resolved_anchor.x < 0.0 or resolved_anchor.y < 0.0:
		resolved_anchor = Vector2(
			SPEAR_PIVOT_FROM_BOTTOM_LEFT.x,
			SPEAR_TEXTURE_SIZE.y - SPEAR_PIVOT_FROM_BOTTOM_LEFT.y
		)
	var created := _add_sprite(
		"Weapon", resolved_path, 0, _weapon_pivot, resolved_anchor
	)
	if created != null:
		return true
	# 自定义武器素材缺失时回退到默认长矛，避免单位完全失去右手武器。
	_weapon_pivot.z_index = Layers.RIGHT_HAND_WEAPON
	var fallback_anchor := Vector2(
		SPEAR_PIVOT_FROM_BOTTOM_LEFT.x,
		SPEAR_TEXTURE_SIZE.y - SPEAR_PIVOT_FROM_BOTTOM_LEFT.y
	)
	return _add_sprite(
		"Weapon", WEAPON_SPEAR_PATH, 0, _weapon_pivot, fallback_anchor
	) != null


## 左手武器；默认层级低于马头。空路径表示不显示。
func set_left_hand_weapon_texture(
	texture_path: String,
	layer_override: int = 0,
	anchor_pixels: Vector2 = Vector2(-1.0, -1.0)
) -> bool:
	remove_part("LeftHandWeapon")
	if _left_hand_weapon_pivot == null or texture_path.is_empty():
		return false
	_left_hand_weapon_pivot.z_index = (
		layer_override if layer_override != 0 else Layers.LEFT_HAND_WEAPON
	)
	return _add_sprite(
		"LeftHandWeapon", texture_path, 0, _left_hand_weapon_pivot, anchor_pixels
	) != null


func clear_left_hand_weapon() -> void:
	remove_part("LeftHandWeapon")


## 头盔是独立装备部件；人物头部始终保留，不会被头盔替代。
func set_helmet_texture(
	texture_path: String,
	layer_override: int = 0,
	anchor_pixels: Vector2 = Vector2(-1.0, -1.0)
) -> bool:
	remove_part("Helmet")
	if texture_path.is_empty() or _upper_body == null:
		return false
	var layer: int = layer_override if layer_override != 0 else Layers.HELMET
	return _add_sprite("Helmet", texture_path, layer, _upper_body, anchor_pixels) != null


func clear_helmet() -> void:
	remove_part("Helmet")


func has_left_hand_weapon() -> bool:
	return has_part("LeftHandWeapon")


func has_helmet() -> bool:
	return has_part("Helmet")


func has_head() -> bool:
	return has_part("Head")


func get_left_hand_weapon_pivot() -> Node2D:
	return _left_hand_weapon_pivot


## 由 UnitVisual 统一驱动的待机/跑动动画。
## idle_time/run_time 是共享时间轴，blend 在 0（待机）和 1（跑动）之间平滑过渡。
## rider_offset_y 为骑乘时马身 rig 的当前垂直偏移；人物整体跟随它移动。
func update_locomotion(
	idle_time: float,
	run_time: float,
	blend: float,
	delta: float,
	rider_offset_y: float = 0.0
) -> void:
	if _upper_body == null:
		return
	# 死亡倒地姿态一旦锁定，待机/跑动/受击都不再覆盖尸体姿态。
	if _death_pose_locked:
		return
	# 骑乘时整个人物视觉跟随马身；非骑乘时恢复为原始位置。
	# 朝右的额外水平修正统一由 _mounted_offset() 处理，避免叠加偏移。
	_apply_mounted_position(rider_offset_y)

	var b: float = clampf(blend, 0.0, 1.0)
	var idle_phase: float = TAU * idle_time / IDLE_BOB_PERIOD
	var run_phase: float = TAU * run_time / RUN_BOB_PERIOD

	var bob: float = (
		sin(idle_phase) * IDLE_BOB_AMPLITUDE * (1.0 - b)
		+ sin(run_phase) * RUN_BOB_AMPLITUDE * b
	)
	if _mounted:
		bob *= MOUNTED_RIDER_BOB_SCALE
	# 每帧从基准位置重新计算，确保受击偏移不会残留到下一帧。
	_upper_body.position = Vector2(0.0, bob)
	_upper_body.rotation = (
		sin(idle_phase * 0.8) * IDLE_TILT_AMPLITUDE * (1.0 - b)
		+ sin(run_phase) * RUN_TILT_AMPLITUDE * b
	)
	_apply_hit_reaction(delta)

	# 头部跟随身体，同时保留极小幅度的独立摆动；头盔与头部同步旋转。
	var head_sway: float = (
		sin(idle_phase * 0.75) * IDLE_HEAD_SWAY * (1.0 - b)
		+ sin(run_phase * 1.4 + 0.4) * RUN_HEAD_SWAY * b
	)
	var head := get_part("Head")
	if head != null:
		head.rotation = head_sway
	var helmet := get_part("Helmet")
	if helmet != null:
		helmet.rotation = head_sway

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


## 受击动作：world_direction 为攻击命中方向（攻击者→受击者）。
## 身体向相反方向短暂后仰；方向会按人物当前镜像换算到局部坐标。
func play_hit_reaction(world_direction: Vector2) -> void:
	var knockback: Vector2 = -world_direction
	if knockback.length_squared() < 0.0001:
		knockback = Vector2.RIGHT
	knockback = knockback.normalized()
	var facing_scale: float = -1.0 if scale.x < 0.0 else 1.0
	_hit_local_direction = Vector2(knockback.x * facing_scale, knockback.y)
	_hit_time_left = HIT_REACTION_TIME


## 每帧叠加受击偏移；正常待机/跑动姿态已在调用前重新计算，因此不会残留。
func _apply_hit_reaction(delta: float) -> void:
	if _hit_time_left <= 0.0:
		return
	_hit_time_left = maxf(0.0, _hit_time_left - maxf(0.0, delta))
	var strength: float = _hit_time_left / HIT_REACTION_TIME
	_upper_body.position += (
		_hit_local_direction * HIT_REACTION_OFFSET * strength
	)
	_upper_body.rotation += (
		_hit_local_direction.x * HIT_REACTION_TILT * strength
	)
	if _hit_time_left <= 0.0:
		_hit_local_direction = Vector2.ZERO


func get_hit_reaction_local_direction() -> Vector2:
	return _hit_local_direction


func is_hit_reacting() -> bool:
	return _hit_time_left > 0.0


## 清理受击动作状态；用于 UI 预览等需要干净姿态的场景。
func reset_hit_reaction() -> void:
	_hit_time_left = 0.0
	_hit_local_direction = Vector2.ZERO


## 受击打断当前攻击表现：武器立即回到待机姿态，避免继续显示未成立的攻击。
## 已经结算的伤害不受影响；未到有效帧的伤害由 UnitController 取消。
func cancel_attack_animation() -> void:
	_attack_phase = AnimationPhase.IDLE
	_phase_time = 0.0
	_hit_frame_emitted = false
	_weapon_sway_current = 0.0
	if _weapon_pivot != null:
		_weapon_pivot.rotation = SPEAR_IDLE_ROTATION
		_weapon_pivot.position = BODY_WEAPON_ANCHOR


func get_melee_hit_frame_time() -> float:
	return SPEAR_WINDUP_TIME + SPEAR_THRUST_TIME * SPEAR_HIT_FRAME_RATIO


# ---------------------------------------------------------------------------
# 死亡倒地
# ---------------------------------------------------------------------------


## 开始倒地：锁定死亡姿态并取消攻击/受击表现。
## duration 由 CorpseConfig 统一提供，表现层不自行决定留存/淡出时长。
func play_death_fall(duration: float) -> void:
	if _death_pose_locked or _upper_body == null:
		return
	_death_pose_locked = true
	_death_fall_active = true
	_death_fall_time = 0.0
	_death_fall_duration = maxf(duration, 0.001)
	reset_hit_reaction()
	cancel_attack_animation()
	set_attack_flash(false)
	_apply_death_pose(0.0)


## 推进倒地动画；返回倒地是否已完成。完成后姿态保持在最后一帧。
func advance_death_animation(delta: float) -> bool:
	if not _death_fall_active:
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
	if _upper_body == null:
		return
	var eased: float = _ease(clampf(t, 0.0, 1.0))
	_upper_body.rotation = DEATH_FALL_ANGLE * eased
	_upper_body.position = Vector2(0.0, DEATH_FALL_SINK * eased)


func is_death_fall_active() -> bool:
	return _death_fall_active


func is_death_pose_locked() -> bool:
	return _death_pose_locked


func get_death_fall_progress() -> float:
	if _death_fall_duration <= 0.0:
		return 1.0
	return clampf(_death_fall_time / _death_fall_duration, 0.0, 1.0)


func get_tabard_material() -> ShaderMaterial:
	return _tabard_material


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
## 返回是否成功启动动画；有效命中帧由 advance_animation 在戳击阶段发出。
func play_attack_animation(direction: Vector2 = Vector2.LEFT) -> bool:
	if _weapon_pivot == null:
		return false
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
	_hit_frame_emitted = false
	_attack_phase = AnimationPhase.WINDUP
	_phase_time = 0.0
	set_process(true)
	return true


## 弓箭攻击动画：拉弓 -> 放箭 -> 恢复。只播放表现，不生成箭矢或结算伤害。
## direction 为世界方向；弓素材默认朝左，因此目标角度按“左方向”换算。
func play_ranged_attack_animation(direction: Vector2 = Vector2.LEFT) -> void:
	if _weapon_pivot == null:
		return
	var facing_scale: float = -1.0 if scale.x < 0.0 else 1.0
	var local_direction := Vector2(direction.x * facing_scale, direction.y)
	if local_direction.length_squared() < 0.0001:
		local_direction = Vector2.LEFT
	local_direction = local_direction.normalized()
	# 旋转 0 时弓的射击方向为左；目标旋转 = 目标方向角 - 左方向角。
	_attack_target_rotation = local_direction.angle() - PI
	var shot_direction := Vector2.LEFT.rotated(_attack_target_rotation)
	_weapon_back_offset = -shot_direction * BOW_DRAW_BACK_DISTANCE
	_weapon_forward_offset = shot_direction * BOW_RELEASE_FORWARD_DISTANCE
	_windup_start_rotation = _weapon_pivot.rotation
	_windup_start_position = _weapon_pivot.position
	_weapon_sway_current = 0.0
	_hit_frame_emitted = false
	_attack_phase = AnimationPhase.RANGED_DRAW
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
			# 有效命中帧：戳击越过该比例后才允许结算一次伤害。
			if not _hit_frame_emitted and thrust_t >= SPEAR_HIT_FRAME_RATIO:
				_hit_frame_emitted = true
				attack_hit_frame.emit()
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
		AnimationPhase.RANGED_DRAW:
			var draw_t: float = clampf(_phase_time / BOW_DRAW_TIME, 0.0, 1.0)
			var draw_ease: float = _ease(draw_t)
			_weapon_pivot.rotation = lerp_angle(
				_windup_start_rotation, _attack_target_rotation, draw_ease
			)
			_weapon_pivot.position = _windup_start_position.lerp(
				BODY_WEAPON_ANCHOR + _weapon_back_offset, draw_ease
			)
			if draw_t >= 1.0:
				_attack_phase = AnimationPhase.RANGED_RELEASE
				_phase_time = 0.0
		AnimationPhase.RANGED_RELEASE:
			var release_t: float = clampf(_phase_time / BOW_RELEASE_TIME, 0.0, 1.0)
			var release_ease: float = _ease(release_t)
			_weapon_pivot.rotation = _attack_target_rotation
			_weapon_pivot.position = (
				(BODY_WEAPON_ANCHOR + _weapon_back_offset).lerp(
					BODY_WEAPON_ANCHOR + _weapon_forward_offset, release_ease
				)
			)
			if release_t >= 1.0:
				_attack_phase = AnimationPhase.RANGED_RECOVER
				_phase_time = 0.0
		AnimationPhase.RANGED_RECOVER:
			var bow_recover_t: float = clampf(
				_phase_time / BOW_RECOVER_TIME, 0.0, 1.0
			)
			var bow_recover_ease: float = _ease(bow_recover_t)
			_weapon_pivot.rotation = lerp_angle(
				_attack_target_rotation, BOW_IDLE_ROTATION, bow_recover_ease
			)
			_weapon_pivot.position = (
				(BODY_WEAPON_ANCHOR + _weapon_forward_offset).lerp(
					BODY_WEAPON_ANCHOR, bow_recover_ease
				)
			)
			if bow_recover_t >= 1.0:
				_weapon_pivot.rotation = BOW_IDLE_ROTATION
				_weapon_pivot.position = BODY_WEAPON_ANCHOR
				_attack_phase = AnimationPhase.IDLE
				_phase_time = 0.0
				_weapon_sway_current = 0.0


func _process(delta: float) -> void:
	if _death_pose_locked:
		return
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
		or _attack_phase == AnimationPhase.RANGED_DRAW
		or _attack_phase == AnimationPhase.RANGED_RELEASE
	)


func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _add_tabard(
	faction_color: Color, parent: Node, tabard_texture_path: String = ""
) -> void:
	# 家族罩袍是完整贴图，直接叠在身体前方；没有家族贴图时继续使用
	# 临时身体贴图 + 阵营色着色，保持原有普通士兵外观。
	if not tabard_texture_path.is_empty():
		var family_tabard := _add_sprite(
			"Tabard", tabard_texture_path, Layers.TABARD, parent
		)
		if family_tabard != null:
			return

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
	tabard_material.set_shader_parameter("use_faction_color", true)
	tabard_material.set_shader_parameter("faction_color", faction_color)
	tabard_material.set_shader_parameter("flash_amount", 0.0)
	tabard.material = tabard_material
	_tabard_material = tabard_material
