extends Node
## 士兵表现测试：人物/马匹分组、最终层级、影子互斥、骑乘偏移、长矛动画与缺失素材回退。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/unit_visual_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"
const UnitVisualScript = preload("res://Scripts/Systems/Combat/unit_visual.gd")
const UnitActorScript = preload("res://Scripts/Systems/Combat/unit_actor.gd")
const HumanVisualScript = preload("res://Scripts/Systems/Combat/human_visual.gd")
const HorseVisualScript = preload("res://Scripts/Systems/Combat/horse_visual.gd")
const PartVisualScript = preload("res://Scripts/Systems/Combat/part_visual.gd")

var _failed: bool = false


func _ready() -> void:
	_run()
	if _failed:
		push_error("[visual] 测试失败")
		get_tree().quit(1)
	else:
		print("[visual] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	var config: UnitConfig = load(MILITIA_PATH) as UnitConfig
	_check(config != null, "加载民兵配置")
	if config == null:
		return

	var units := UnitManager.new()
	units.setup(IdGenerator.new())
	var foot_unit := units.create_unit(config, "FACTION_PLAYER")
	var enemy_unit := units.create_unit(config, "FACTION_BANDIT")
	_check(foot_unit != null and enemy_unit != null, "创建双方士兵")

	_test_foot_parts(foot_unit)
	_test_mounted_parts(foot_unit)
	_test_locomotion_animation(foot_unit)
	_test_layer_order(foot_unit)
	_test_equipment_visuals(foot_unit)
	_test_faction_tabard(foot_unit, enemy_unit)
	_test_facing(foot_unit)
	_test_spear_animation(foot_unit)
	_test_missing_plume_fallback(foot_unit)
	_test_unit_actor_integration(foot_unit)


func _test_foot_parts(unit: UnitData) -> void:
	var visual = UnitVisualScript.new()
	add_child(visual)
	visual.setup(unit)

	_check(visual.get_human_visual() != null, "创建独立人物表现组")
	_check(visual.get_horse_visual() != null, "创建独立马匹表现组")
	_check(visual.has_part("FootShadow"), "步行单位拥有人物影子")
	_check(visual.get_part("FootShadow").is_visible_in_tree(), "步行时人物影子可见")
	_check(not visual.get_horse_visual().visible, "步行时马匹表现组整体隐藏")
	_check(not visual.get_part("MountShadow").is_visible_in_tree(), "步行时不显示骑马影子")
	_check(visual.has_part("Body") and visual.has_part("Head"), "显示身体与头部")
	_check(visual.has_part("Weapon"), "显示武器")
	_check(visual.has_part("LegLeft") and visual.has_part("LegRight"), "显示双腿")
	_check(not visual.get_human_visual().has_part("MountBody"), "马匹部件不在人物表现组")
	_check(visual.get_horse_visual().has_part("MountBody"), "马身由马匹表现组管理")
	visual.queue_free()


func _test_mounted_parts(unit: UnitData) -> void:
	unit.is_mounted = true
	var visual = UnitVisualScript.new()
	add_child(visual)
	visual.setup(unit)

	_check(visual.get_horse_visual().visible, "骑乘时马匹表现组可见")
	_check(visual.has_part("MountShadow"), "骑乘单位拥有骑马影子")
	_check(visual.get_part("MountShadow").is_visible_in_tree(), "骑乘时骑马影子可见")
	_check(not visual.get_part("FootShadow").visible, "骑乘时人物影子隐藏")
	_check(not visual.get_part("FootShadow").is_visible_in_tree(), "两种影子不同时显示")
	_check(visual.has_part("MountBody"), "骑乘时显示马身")
	_check(visual.has_part("MountHead"), "骑乘时显示马头")
	_check(visual.has_part("MountSaddle"), "骑乘时显示马鞍")
	_check(
		visual.has_part("MountLegBack") and visual.has_part("MountLegBack2")
			and visual.has_part("MountLegFront") and visual.has_part("MountLegFront2"),
		"四条马腿是四个独立部件"
	)
	_check(
		visual.has_part("LegLeft") and visual.has_part("LegRight"),
		"骑乘单位仍创建人体双腿"
	)
	_check(visual.get_part("LegLeft").is_visible_in_tree(), "骑乘时人体左腿仍在场景树中可见")
	_check(visual.get_part("LegRight").is_visible_in_tree(), "骑乘时人体右腿仍在场景树中可见")
	_check(visual.has_part("Body") and visual.has_part("Head") and visual.has_part("Weapon"),
		"骑乘时身体/头部/武器仍显示")
	_check(visual.has_part("Tabard"), "骑乘时仍显示阵营罩袍")
	_check(
		is_equal_approx(visual.get_human_visual().position.y, -15.0),
		"骑乘时人物整体上移 15 像素"
	)
	_check(
		is_zero_approx(visual.get_horse_visual().position.y),
		"马匹不随人物骑乘偏移移动"
	)

	visual.set_mounted(false)
	_check(not visual.get_horse_visual().visible, "卸下马匹后立即隐藏马匹表现组")
	_check(visual.get_part("FootShadow").visible, "卸下马匹后恢复人物影子")
	_check(visual.get_part("MountShadow").is_visible_in_tree() == false,
		"卸下马匹后不再显示骑马影子")
	_check(is_zero_approx(visual.get_human_visual().position.y),
		"卸下马匹后人物偏移恢复为 0")
	visual.queue_free()
	unit.is_mounted = false


func _test_locomotion_animation(unit: UnitData) -> void:
	unit.is_mounted = false
	var visual = UnitVisualScript.new()
	add_child(visual)
	visual.setup(unit)
	var human = visual.get_human_visual()
	var upper = human.get_upper_body()
	var foot_shadow := visual.get_part("FootShadow")
	_check(upper != null, "人物上半身独立节点存在")
	_check(foot_shadow != null, "人物影子存在")

	var leg_left: Sprite2D = human.get_part("LegLeft")
	var leg_right: Sprite2D = human.get_part("LegRight")
	_check_leg_pivot(
		leg_left, HumanVisualScript.LEG_PIVOT_DROP_Y, "人物左腿"
	)
	_check_leg_pivot(
		leg_right, HumanVisualScript.LEG_PIVOT_DROP_Y, "人物右腿"
	)
	_check(leg_left.get_parent() == upper, "人物左腿挂载在身体变换节点下")
	_check(leg_right.get_parent() == upper, "人物右腿挂载在身体变换节点下")

	var head: Sprite2D = human.get_part("Head")
	var max_idle_bob: float = 0.0
	var max_idle_sway: float = 0.0
	var max_idle_head_sway: float = 0.0
	var min_leg_global_y: float = INF
	var max_leg_global_y: float = -INF
	for i: int in range(40):
		visual.update_locomotion(0.05, false)
		max_idle_bob = maxf(max_idle_bob, absf(upper.position.y))
		max_idle_sway = maxf(max_idle_sway, absf(human.get_weapon_sway_target()))
		if head != null:
			max_idle_head_sway = maxf(max_idle_head_sway, absf(head.rotation))
		if leg_left != null:
			min_leg_global_y = minf(min_leg_global_y, leg_left.global_position.y)
			max_leg_global_y = maxf(max_leg_global_y, leg_left.global_position.y)
	_check(max_idle_bob > 0.1, "步兵待机有轻微身体起伏")
	_check(
		max_leg_global_y - min_leg_global_y > 0.3,
		"人物双腿继承身体整体上下起伏"
	)
	_check(max_idle_sway > 0.001, "步兵待机有轻微武器晃动")
	_check(max_idle_head_sway > 0.0005, "步兵待机时头部有独立微摆")
	_check(foot_shadow.position == Vector2.ZERO, "待机动画不移动人物影子")
	human._process(0.05)
	_check(absf(human.get_weapon_sway()) > 0.0001, "待机武器晃动实际作用到枢轴")

	var max_run_bob: float = 0.0
	for i: int in range(60):
		visual.update_locomotion(0.02, true)
		max_run_bob = maxf(max_run_bob, absf(upper.position.y))
	_check(visual.get_locomotion_blend() > 0.9, "移动状态平滑进入跑动")
	_check(max_run_bob > max_idle_bob, "跑动幅度大于待机")

	var max_leg_distance: float = 0.0
	var max_leg_swing_x: float = 0.0
	var max_leg_lift: float = 0.0
	var max_leg_amplitude_error: float = 0.0
	var legs_never_sink: bool = true
	var rest_y: float = HumanVisualScript.LEG_REST_POSITION.y
	for i: int in range(20):
		visual.update_locomotion(0.02, true)
		if leg_left != null and leg_right != null:
			max_leg_distance = maxf(
				max_leg_distance, leg_left.position.distance_to(leg_right.position)
			)
			max_leg_swing_x = maxf(
				max_leg_swing_x,
				maxf(absf(leg_left.position.x), absf(leg_right.position.x))
			)
			max_leg_amplitude_error = maxf(
				max_leg_amplitude_error,
				absf(absf(leg_left.position.x) - absf(leg_right.position.x))
			)
			max_leg_lift = maxf(
				max_leg_lift,
				maxf(rest_y - leg_left.position.y, rest_y - leg_right.position.y)
			)
			# 双腿只在上摆时抬起，任何一帧都不应向下陷入地面。
			legs_never_sink = (
				legs_never_sink
				and leg_left.position.y <= rest_y + 0.001
				and leg_right.position.y <= rest_y + 0.001
			)
	_check(max_leg_distance > 0.1, "跑动时双腿等幅反向交替摆动")
	_check(max_leg_amplitude_error < 0.001, "左右腿局部摆动幅度保持一致")
	_check(
		max_leg_swing_x <= HumanVisualScript.RUN_LEG_SWING_X + 0.01,
		"跑动时腿部水平摆幅进一步收敛"
	)
	_check(
		max_leg_lift <= HumanVisualScript.RUN_LEG_LIFT_Y + 0.01,
		"跑动时抬脚幅度保持克制"
	)
	_check(legs_never_sink, "跑动时双腿不会向下陷入地面")
	_check(foot_shadow.position == Vector2.ZERO, "跑动动画不移动人物影子")

	# 停止移动后双腿自然回到默认位置（包含枢轴下移的基准位置）。
	for i: int in range(20):
		visual.update_locomotion(0.02, false)
	_check(
		leg_left.position.distance_to(HumanVisualScript.LEG_REST_POSITION) < 0.01
			and leg_right.position.distance_to(HumanVisualScript.LEG_REST_POSITION) < 0.01,
		"待机时双腿回到默认位置"
	)

	# 骑乘：人物上移 15，人物与马匹共享运动时间轴，影子稳定。
	unit.is_mounted = true
	var mounted = UnitVisualScript.new()
	add_child(mounted)
	mounted.setup(unit)
	var mounted_human = mounted.get_human_visual()
	var mounted_horse = mounted.get_horse_visual()
	var horse_rig: Node2D = mounted_horse.get_body_rig()
	var horse_leg: Sprite2D = mounted_horse.get_part("MountLegFront")
	var horse_leg2: Sprite2D = mounted_horse.get_part("MountLegFront2")
	var horse_back_leg: Sprite2D = mounted_horse.get_part("MountLegBack")
	var horse_back_leg2: Sprite2D = mounted_horse.get_part("MountLegBack2")
	var mount_shadow: Sprite2D = mounted_horse.get_part("MountShadow")
	var mounted_upper: Node2D = mounted_human.get_upper_body()
	# 骑马朝向偏移：朝左保持 +3；朝右在旧位置基础上再向左 6（净值 -3）。
	# 镜像只改变缩放，不翻转节点坐标，因此必须按朝向分别计算。
	mounted.set_facing(-1.0)
	mounted.update_locomotion(0.0, false)
	_check(
		is_equal_approx(mounted_human.position.x, 3.0),
		"骑马朝左贴图保持 +3 横向偏移"
	)
	mounted.set_facing(1.0)
	mounted.update_locomotion(0.0, false)
	_check(
		is_equal_approx(mounted_human.position.x, -3.0),
		"骑马朝右在旧位置基础上向左调整 6 像素"
	)
	mounted.set_facing(-1.0)
	mounted.update_locomotion(0.0, false)
	_check(
		is_equal_approx(mounted_human.position.x, 3.0),
		"切回朝左恢复原横向偏移"
	)
	_check(is_zero_approx(human.position.x), "未骑马贴图位置不受朝向偏移影响")
	_check_leg_pivot(horse_leg, HorseVisualScript.LEG_PIVOT_DROP_Y, "马前腿1")
	_check_leg_pivot(horse_leg2, HorseVisualScript.LEG_PIVOT_DROP_Y, "马前腿2")
	_check_leg_pivot(horse_back_leg, HorseVisualScript.LEG_PIVOT_DROP_Y, "马后腿1")
	_check_leg_pivot(horse_back_leg2, HorseVisualScript.LEG_PIVOT_DROP_Y, "马后腿2")
	for leg: Sprite2D in [horse_leg, horse_leg2, horse_back_leg, horse_back_leg2]:
		_check(leg.get_parent() == horse_rig, "马腿挂载在马身变换 rig 下")
	var max_horse_idle_bob: float = 0.0
	for i: int in range(30):
		mounted.update_locomotion(0.05, false)
		if horse_rig != null:
			max_horse_idle_bob = maxf(max_horse_idle_bob, absf(horse_rig.position.y))
	_check(max_horse_idle_bob > 0.1, "骑兵待机时马身有轻微起伏")
	_check(
		is_equal_approx(mounted_human.position.y, -15.0 + horse_rig.position.y),
		"骑兵待机时骑手跟随马身垂直偏移"
	)

	var max_horse_bob: float = 0.0
	var max_rider_follow: float = 0.0
	var max_rider_sync_error: float = 0.0
	var max_mounted_upper_bob: float = 0.0
	var max_front_sync_error: float = 0.0
	var max_back_sync_error: float = 0.0
	var max_group_opposition: float = 0.0
	var groups_opposite_seen: bool = false
	var max_horse_leg_offset_y: float = 0.0
	var max_horse_leg_offset_x: float = 0.0
	var min_horse_leg_global_y: float = INF
	var max_horse_leg_global_y: float = -INF
	var min_shadow_scale: float = INF
	var max_shadow_scale: float = -INF
	var min_shadow_alpha: float = INF
	var max_shadow_alpha: float = -INF
	for i: int in range(40):
		mounted.update_locomotion(0.03, true)
		if horse_rig != null:
			max_horse_bob = maxf(max_horse_bob, absf(horse_rig.position.y))
			max_rider_follow = maxf(
				max_rider_follow, absf(mounted_human.position.y + 15.0)
			)
			max_rider_sync_error = maxf(
				max_rider_sync_error,
				absf(mounted_human.position.y + 15.0 - horse_rig.position.y)
			)
		if horse_leg != null:
			min_horse_leg_global_y = minf(
				min_horse_leg_global_y, horse_leg.global_position.y
			)
			max_horse_leg_global_y = maxf(
				max_horse_leg_global_y, horse_leg.global_position.y
			)
		if mounted_upper != null:
			max_mounted_upper_bob = maxf(
				max_mounted_upper_bob, absf(mounted_upper.position.y)
			)
		if mount_shadow != null:
			min_shadow_scale = minf(min_shadow_scale, mount_shadow.scale.x)
			max_shadow_scale = maxf(max_shadow_scale, mount_shadow.scale.x)
			min_shadow_alpha = minf(min_shadow_alpha, mount_shadow.modulate.a)
			max_shadow_alpha = maxf(max_shadow_alpha, mount_shadow.modulate.a)
		if horse_leg != null and horse_leg2 != null \
				and horse_back_leg != null and horse_back_leg2 != null:
			max_front_sync_error = maxf(
				max_front_sync_error,
				absf(horse_leg.position.x - horse_leg2.position.x)
			)
			max_back_sync_error = maxf(
				max_back_sync_error,
				absf(horse_back_leg.position.x - horse_back_leg2.position.x)
			)
			max_group_opposition = maxf(
				max_group_opposition,
				maxf(
					absf(horse_leg.position.x - horse_back_leg.position.x),
					absf(horse_leg.position.x - horse_back_leg2.position.x)
				)
			)
			if horse_leg.position.x * horse_back_leg.position.x < -0.01:
				groups_opposite_seen = true
			for leg: Sprite2D in [horse_leg, horse_leg2, horse_back_leg, horse_back_leg2]:
				max_horse_leg_offset_y = maxf(
					max_horse_leg_offset_y,
					absf(leg.position.y - HorseVisualScript.LEG_PIVOT_DROP_Y)
				)
				max_horse_leg_offset_x = maxf(
					max_horse_leg_offset_x, absf(leg.position.x)
				)
	_check(max_rider_follow > 2.0, "骑手随马身整体上下运动且覆盖主要跃动幅度")
	_check(max_rider_sync_error < 0.001, "骑手与马身保持稳定相对位置")
	_check(max_mounted_upper_bob <= 0.6, "骑手上半身不再叠加过大的独立起伏")
	_check(max_horse_bob > 3.5, "骑兵移动时马身整体仍有明显跃动")
	_check(max_horse_bob < 5.0, "骑兵整体上下波动已降低")
	_check(max_front_sync_error < 1.0, "两只前腿成组同步伸展")
	_check(max_back_sync_error < 1.0, "两只后腿成组同步伸展")
	_check(max_group_opposition > 0.2, "前腿组与后腿组形成反向伸展/收缩")
	_check(groups_opposite_seen, "前腿组与后腿组伸展方向相反")
	_check(max_horse_leg_offset_y <= 0.5, "马腿上下位移保持克制")
	_check(
		max_horse_leg_offset_x <= HorseVisualScript.RUN_FRONT_LEG_REACH_X + 0.01,
		"马腿局部伸展幅度保持在配置上限内"
	)
	_check(max_horse_leg_offset_x >= 0.45, "马腿局部动作比上一版更明显")
	_check(
		max_horse_leg_global_y - min_horse_leg_global_y > 2.0,
		"四条马腿继承马身整体跃动"
	)
	_check(
		min_shadow_scale < 0.995 and max_shadow_scale <= 1.0001,
		"马匹抬高时影子轻微缩小、回落时恢复"
	)
	_check(
		min_shadow_alpha < 0.99 and max_shadow_alpha <= 1.0001,
		"马匹抬高时影子轻微变淡、回落时恢复"
	)
	_check(mount_shadow != null and mount_shadow.position == Vector2.ZERO,
		"影子动画不移动骑马影子位置")

	# 停止移动后马腿回到稳定待机姿态。
	for i: int in range(20):
		mounted.update_locomotion(0.05, false)
	_check(
		absf(horse_leg.position.x) < 0.01 and absf(horse_back_leg.position.x) < 0.01,
		"待机时马腿回到稳定位置，不再播放跃马动作"
	)

	# 攻击优先：攻击期间武器由攻击动画控制，不应用待机/跑动晃动。
	mounted.play_attack_animation(Vector2.RIGHT)
	mounted.update_locomotion(0.03, true)
	mounted.advance_animation(HumanVisualScript.SPEAR_WINDUP_TIME)
	var pivot: Node2D = mounted.get_weapon_pivot()
	var target_rotation: float = mounted.get_attack_target_rotation()
	_check(
		pivot != null and absf(angle_difference(pivot.rotation, target_rotation)) < 0.001,
		"攻击动画优先于待机/跑动武器晃动"
	)
	mounted.queue_free()
	visual.queue_free()
	unit.is_mounted = false


func _test_layer_order(unit: UnitData) -> void:
	unit.is_mounted = true
	var visual = UnitVisualScript.new()
	add_child(visual)
	visual.setup(unit)

	var human = visual.get_human_visual()
	human.set_left_hand_weapon_texture(HumanVisualScript.HEAD_PATH)
	human.set_helmet_texture(HumanVisualScript.HEAD_PATH)
	var weapon_z: int = visual.get_part_effective_z("Weapon")
	var horse_head_z: int = visual.get_part_effective_z("MountHead")
	var head_z: int = visual.get_part_effective_z("Head")
	var helmet_z: int = visual.get_part_effective_z("Helmet")
	var left_hand_z: int = visual.get_part_effective_z("LeftHandWeapon")
	var body_z: int = visual.get_part_effective_z("Body")
	var right_leg_z: int = visual.get_part_effective_z("LegRight")
	var saddle_z: int = visual.get_part_effective_z("MountSaddle")
	var horse_body_z: int = visual.get_part_effective_z("MountBody")
	var left_leg_z: int = visual.get_part_effective_z("LegLeft")
	var horse_leg_z: int = visual.get_part_effective_z("MountLegFront")
	var shadow_z: int = visual.get_part_effective_z("MountShadow")

	_check(weapon_z > horse_head_z, "右手武器在马头之前")
	_check(left_hand_z < horse_head_z, "左手武器层级低于马头")
	_check(left_hand_z < head_z, "左手武器不遮挡人头")
	_check(horse_head_z > head_z, "马头在人头之前")
	_check(helmet_z > head_z, "头盔显示在人头之前")
	_check(visual.has_part("Head") and visual.has_part("Helmet"),
		"人物头部与头盔是独立部件且同时存在")
	_check(head_z > body_z, "人头在人身体之前")
	_check(body_z > right_leg_z, "人身体在人右腿之前")
	_check(right_leg_z > saddle_z, "人右腿在马鞍之前")
	_check(saddle_z > horse_leg_z, "马鞍在马腿之前")
	_check(horse_leg_z > horse_body_z, "四条马腿显示在马身之前")
	_check(horse_body_z > left_leg_z, "马身在人左腿之前")
	_check(left_leg_z > shadow_z, "人左腿在影子之前")
	_check(horse_leg_z > shadow_z, "马腿在影子之前")
	_check(visual.get_part_effective_z("Tabard") > body_z, "罩袍层紧贴人身体前方")
	visual.queue_free()
	unit.is_mounted = false


func _test_equipment_visuals(unit: UnitData) -> void:
	var equipment_before: Dictionary = unit.equipment.duplicate(true)
	unit.equipment["HEAD"] = "test_helmet"
	unit.equipment["OFFHAND"] = "test_shield"

	var helmet := EquipmentConfig.new()
	helmet.equipment_id = "test_helmet"
	helmet.display_name = "测试头盔"
	helmet.slot = EquipmentConfig.Slot.HEAD
	helmet.visual_texture_path = HumanVisualScript.HEAD_PATH

	var shield := EquipmentConfig.new()
	shield.equipment_id = "test_shield"
	shield.display_name = "测试盾牌"
	shield.slot = EquipmentConfig.Slot.OFFHAND
	shield.visual_texture_path = HumanVisualScript.HEAD_PATH
	# 配置覆盖层级也必须低于马头，同时验证视觉层级来自 EquipmentConfig。
	shield.visual_layer = -25

	var visual = UnitVisualScript.new()
	add_child(visual)
	visual.setup(unit, {"HEAD": helmet, "OFFHAND": shield})
	var human = visual.get_human_visual()
	_check(visual.has_part("Head"), "装备头盔时人物头部仍然存在")
	_check(visual.has_part("Helmet"), "装备头盔时生成独立头盔部件")
	_check(visual.has_part("LeftHandWeapon"), "装备副手时生成独立左手武器部件")
	_check(
		visual.get_part_effective_z("Helmet")
		> visual.get_part_effective_z("Head"),
		"头盔层级在人头之前"
	)
	_check(
		visual.get_part_effective_z("LeftHandWeapon")
		< visual.get_part_effective_z("MountHead"),
		"左手武器配置层级低于马头"
	)
	_check(
		visual.get_part_effective_z("LeftHandWeapon") == -25,
		"左手武器层级使用 EquipmentConfig 覆盖值"
	)
	_check(
		visual.has_part("Weapon")
		and visual.get_part_effective_z("Weapon")
		> visual.get_part_effective_z("MountHead"),
		"右手长矛保持原有高层级"
	)
	var head_part: Sprite2D = human.get_part("Head")
	var helmet_part: Sprite2D = human.get_part("Helmet")
	for i: int in range(4):
		visual.update_locomotion(0.05, false)
	_check(
		head_part != null and helmet_part != null
		and is_equal_approx(head_part.rotation, helmet_part.rotation),
		"头部与头盔保持相同朝向/微摆"
	)

	# 卸下头盔后只保留人物头部；副手不受影响。
	unit.equipment.erase("HEAD")
	visual.setup(unit, {"OFFHAND": shield})
	_check(visual.has_part("Head"), "卸下头盔后人物头部仍显示")
	_check(not visual.has_part("Helmet"), "卸下头盔后隐藏头盔部件")
	_check(visual.has_part("LeftHandWeapon"), "卸下头盔不影响左手武器")

	# 卸下副手后恢复默认长矛与头部。
	unit.equipment.erase("OFFHAND")
	visual.setup(unit)
	_check(not visual.has_part("LeftHandWeapon"), "卸下副手后移除左手武器")
	_check(visual.has_part("Weapon"), "卸下副手后右手武器仍为默认长矛")
	_check(visual.has_part("Head") and visual.has_part("Weapon"), "默认外观恢复成功")

	unit.equipment = equipment_before
	visual.queue_free()


func _test_faction_tabard(player_unit: UnitData, enemy_unit: UnitData) -> void:
	var player_visual = UnitVisualScript.new()
	add_child(player_visual)
	player_visual.setup(player_unit)
	var enemy_visual = UnitVisualScript.new()
	add_child(enemy_visual)
	enemy_visual.setup(enemy_unit)

	_check(
		player_visual.get_faction_color() != enemy_visual.get_faction_color(),
		"不同阵营使用不同罩袍颜色"
	)
	var player_tabard := player_visual.get_part("Tabard")
	var enemy_tabard := enemy_visual.get_part("Tabard")
	_check(player_tabard != null and enemy_tabard != null, "罩袍层作为独立部件存在")
	if player_tabard != null:
		var material := player_tabard.material as ShaderMaterial
		_check(material != null, "罩袍使用独立着色材质")
		if material != null:
			_check(
				material.get_shader_parameter("faction_color")
					== player_visual.get_faction_color(),
				"罩袍材质使用当前阵营颜色"
			)
	player_visual.queue_free()
	enemy_visual.queue_free()


func _test_facing(unit: UnitData) -> void:
	var visual = UnitVisualScript.new()
	add_child(visual)
	visual.setup(unit)
	var human = visual.get_human_visual()
	var horse = visual.get_horse_visual()
	_check(is_zero_approx(human.scale.x - 1.0), "默认朝左不镜像")
	visual.set_facing(1.0)
	_check(is_equal_approx(human.scale.x, -1.0), "朝右时人物整体镜像")
	_check(is_equal_approx(horse.scale.x, -1.0), "朝右时马匹整体镜像")
	_check(not visual.get_part("Body").flip_h, "朝向使用整体镜像而不是逐部件 flip_h")
	visual.set_facing(-1.0)
	_check(is_zero_approx(human.scale.x - 1.0), "恢复朝左")
	_check(is_zero_approx(horse.scale.x - 1.0), "马匹恢复朝左")
	visual.queue_free()


func _test_spear_animation(unit: UnitData) -> void:
	var visual = UnitVisualScript.new()
	add_child(visual)
	visual.setup(unit)
	var pivot: Node2D = visual.get_weapon_pivot()
	_check(pivot != null, "长矛存在独立旋转枢轴")
	if pivot == null:
		return
	_check(
		pivot.position == HumanVisualScript.BODY_WEAPON_ANCHOR,
		"长矛枢轴对齐配置的身体锚点"
	)
	var anchor_before: Vector2 = pivot.position
	_check(is_zero_approx(pivot.rotation), "待机时长矛竖直")

	visual.play_attack_animation()
	_check(visual.is_attack_animating(), "攻击触发长矛动画")
	visual.advance_animation(HumanVisualScript.SPEAR_WINDUP_TIME)
	_check(
		is_equal_approx(pivot.rotation, HumanVisualScript.SPEAR_ATTACK_ROTATION),
		"旋转到横向攻击姿态"
	)
	_check(
		pivot.position.x > anchor_before.x + 1.0,
		"朝左攻击前摇时先向右后移"
	)
	_check(pivot.rotation < 0.0, "朝左时逆时针旋转")

	visual.advance_animation(HumanVisualScript.SPEAR_THRUST_TIME)
	_check(
		pivot.position.x < anchor_before.x - 1.0,
		"戳击时沿攻击方向快速前伸"
	)
	# 保持时间默认 4 秒；至少 3 秒内必须维持戳击姿态。
	visual.advance_animation(3.0)
	_check(
		is_equal_approx(pivot.rotation, HumanVisualScript.SPEAR_ATTACK_ROTATION),
		"刺击后至少 3 秒保持攻击姿态"
	)
	_check(
		pivot.position.x < anchor_before.x - 1.0,
		"保持阶段长矛维持向前伸出的姿态"
	)
	visual.advance_animation(HumanVisualScript.SPEAR_POST_ATTACK_HOLD_TIME - 3.0)
	_check(
		is_equal_approx(pivot.rotation, HumanVisualScript.SPEAR_ATTACK_ROTATION),
		"保持时间结束前仍为攻击姿态"
	)
	visual.advance_animation(HumanVisualScript.SPEAR_RECOVER_TIME)
	_check(is_zero_approx(pivot.rotation), "攻击结束后平滑恢复竖直")
	_check(pivot.position.distance_to(anchor_before) < 0.01, "恢复阶段长矛回到握持锚点")
	_check(not visual.is_attack_animating(), "动画回到待机状态")

	# 连续攻击：动画中途再次触发不应被阻止，也不改变枢轴。
	visual.play_attack_animation()
	visual.advance_animation(HumanVisualScript.SPEAR_WINDUP_TIME * 0.5)
	var half_rotation: float = pivot.rotation
	visual.play_attack_animation()
	_check(visual.is_attack_animating(), "连续攻击可以重新触发动画")
	visual.advance_animation(HumanVisualScript.SPEAR_WINDUP_TIME)
	_check(
		is_equal_approx(pivot.rotation, HumanVisualScript.SPEAR_ATTACK_ROTATION),
		"连续攻击仍能到达攻击姿态"
	)
	_check(
		pivot.position.x > anchor_before.x + 1.0,
		"连续攻击重新执行前摇后移"
	)
	_check(half_rotation < 0.0, "中途触发前的旋转已生效")

	# 攻击后保持姿态期间再次攻击：立即衔接新动作，不被旧的恢复计时拉回竖直。
	visual.play_attack_animation()
	visual.advance_animation(HumanVisualScript.SPEAR_WINDUP_TIME)
	visual.advance_animation(HumanVisualScript.SPEAR_THRUST_TIME)
	visual.advance_animation(1.0)
	var held_rotation: float = pivot.rotation
	var held_position: Vector2 = pivot.position
	visual.play_attack_animation(Vector2.UP)
	visual.advance_animation(HumanVisualScript.SPEAR_WINDUP_TIME)
	_check(held_rotation < 0.0, "保持姿态期间长矛仍指向攻击方向")
	_check(held_position.x < anchor_before.x - 1.0, "保持姿态期间维持前伸位置")
	_check(is_zero_approx(pivot.rotation), "保持姿态期间再次攻击立即进入新一轮方向")
	_check(
		pivot.position.y > anchor_before.y + 1.0,
		"向上攻击的前摇先向下后移"
	)

	# 360°方向：动画目标角度必须与世界攻击方向一致（含整体镜像）。
	_check_attack_direction(visual, -1.0, Vector2.UP, 0.0, "向上攻击角度")
	_check_attack_direction(visual, -1.0, Vector2.DOWN, PI, "向下攻击角度")
	_check_attack_direction(visual, -1.0, Vector2.RIGHT, PI * 0.5, "朝左站立向右攻击")
	_check_attack_direction(visual, 1.0, Vector2.RIGHT, -PI * 0.5, "朝右站立向右攻击")
	_check_attack_direction(visual, 1.0, Vector2.LEFT, PI * 0.5, "朝右站立向左攻击")
	_check_attack_direction(
		visual, 1.0, Vector2(1.0, -1.0).normalized(), -PI * 0.25, "右上斜向攻击"
	)
	_check_attack_direction(
		visual, -1.0, Vector2(-1.0, 1.0).normalized(), -PI * 0.75, "左下斜向攻击"
	)
	visual.queue_free()


func _test_missing_plume_fallback(unit: UnitData) -> void:
	var visual = UnitVisualScript.new()
	add_child(visual)
	visual.setup(unit)
	_check(not visual.has_part("Plume"), "缺少缨饰素材时不显示缨饰")
	visual.set_plume_texture("res://art/我的骑砍临时美术/不存在的缨饰.png")
	_check(not visual.has_part("Plume"), "缨饰路径无效时安全回退")
	visual.queue_free()


func _test_unit_actor_integration(unit: UnitData) -> void:
	var max_hp_before: int = unit.max_hp
	var attack_before: int = unit.attack
	var speed_before: float = unit.move_speed
	var range_before: float = unit.attack_range

	var state := BattleUnitState.new()
	state.unit_id = unit.unit_id
	state.party_id = "PARTY_TEST"
	state.battle_hp = unit.current_hp
	state.alive = true
	state.battle_position = Vector2(100.0, 100.0)
	var actor = UnitActorScript.new()
	add_child(actor)
	actor.setup(unit, state, true)

	_check(actor.visual != null, "UnitActor 使用部件表现节点")
	if actor.visual != null:
		_check(actor.visual.has_part("Body"), "UnitActor 生成身体部件")
		_check(actor.visual.has_part("Head"), "UnitActor 生成头部部件")
		var pivot: Node2D = actor.visual.get_weapon_pivot()
		_check(pivot != null, "UnitActor 攻击使用长矛枢轴")
		if pivot != null:
			actor.play_attack()
			_check(actor.visual.is_attack_animating(), "UnitActor.play_attack 触发长矛动画")
			actor.visual.advance_animation(HumanVisualScript.SPEAR_WINDUP_TIME)
			_check(
				is_equal_approx(pivot.rotation, HumanVisualScript.SPEAR_ATTACK_ROTATION),
				"UnitActor 攻击动画到达横向姿态"
			)
	var name_label: Label = actor.get_name_label()
	var health_bar: UnitHealthBar = actor.get_health_bar()
	_check(name_label != null and health_bar != null, "名称与生命条是独立 UI 节点")
	_check(name_label != health_bar, "生命条不替代名称 Label")
	_check(not actor.is_name_visible(), "普通士兵默认隐藏头顶名称")
	actor.set_process(false)
	actor._process(0.016)
	_check(not health_bar.is_bar_visible(), "满血时隐藏生命条")

	actor.set_controlled(true)
	_check(actor.is_name_visible(), "玩家当前控制单位显示头顶名称")
	state.battle_hp = maxi(1, unit.max_hp - 1)
	actor._process(0.016)
	_check(health_bar.is_bar_visible(), "受伤后显示生命条")
	_check(actor.is_name_visible(), "控制单位受伤后名称仍显示")

	state.battle_hp = unit.max_hp
	actor._process(0.016)
	_check(not health_bar.is_bar_visible(), "恢复满血后重新隐藏生命条")
	_check(actor.is_name_visible(), "控制单位恢复满血后名称仍显示")

	# 名称与控制权联动；隐藏名称不能连带隐藏生命条。
	state.battle_hp = maxi(1, unit.max_hp - 1)
	actor._process(0.016)
	actor.set_controlled(false)
	_check(not actor.is_name_visible(), "切换控制后原单位隐藏头顶名称")
	_check(health_bar.is_bar_visible(), "隐藏名称不影响受伤生命条")
	actor.set_controlled(true)
	_check(actor.is_name_visible(), "重新取得控制后名称恢复显示")
	state.battle_hp = unit.max_hp
	actor._process(0.016)

	state.alive = false
	actor._process(0.016)
	_check(not health_bar.is_bar_visible(), "死亡状态不显示无效生命条")
	state.alive = true
	state.battle_hp = unit.max_hp
	actor._process(0.016)

	var name_offset: Vector2 = name_label.global_position - actor.global_position
	state.battle_position += Vector2(12.0, -4.0)
	actor._process(0.016)
	_check(
		(name_label.global_position - actor.global_position).distance_to(name_offset) < 0.001,
		"名称跟随单位移动且无额外偏移"
	)
	_check(
		(health_bar.global_position - actor.global_position).distance_to(
			Vector2(0.0, UnitHealthBar.BAR_TOP)
		) < 0.001,
		"生命条保持独立的固定头顶偏移"
	)
	# 清空这次位置变化造成的视觉跑动缓冲，避免干扰后续移动状态测试。
	for i: int in range(10):
		actor._process(0.05)
	_check(not actor.is_visual_moving(), "名称/生命条测试后恢复待机状态")

	# 移动状态缓冲：实际位移驱动待机/跑动，停止后经过短暂缓冲回到待机。
	actor.set_process(false)
	actor._process(0.016)
	_check(not actor.is_visual_moving(), "静止单位处于视觉待机状态")
	state.battle_position += Vector2(10.0, 0.0)
	actor._process(0.016)
	_check(actor.is_visual_moving(), "实际位移触发视觉跑动状态")
	for i: int in range(10):
		actor._process(0.05)
	_check(not actor.is_visual_moving(), "停止移动后经过缓冲恢复待机")

	_check(unit.max_hp == max_hp_before, "表现层不修改最大 HP")
	_check(unit.attack == attack_before, "表现层不修改攻击力")
	_check(is_equal_approx(unit.move_speed, speed_before), "表现层不修改移动速度")
	_check(is_equal_approx(unit.attack_range, range_before), "表现层不修改攻击距离")
	actor.queue_free()


## 验证腿部枢轴：基础位置补回 drop_y、可见贴图位置不变、旋转中心实际下移。
func _check_leg_pivot(leg: Sprite2D, drop_y: float, label: String) -> void:
	if leg == null or leg.texture == null:
		_check(false, "%s 枢轴检查所需部件/贴图存在" % label)
		return
	var texture_origin := Vector2(
		-float(leg.texture.get_width()) * 0.5,
		-(float(leg.texture.get_height()) - PartVisualScript.DEFAULT_ANCHOR_MARGIN)
	)
	_check(is_equal_approx(leg.position.x, 0.0), "%s 基础位置水平不变" % label)
	_check(is_equal_approx(leg.position.y, drop_y), "%s 基础位置补偿枢轴下移" % label)
	_check(
		(leg.position + leg.offset).distance_to(texture_origin) < 0.001,
		"%s 可见贴图位置保持不变" % label
	)
	_check(
		is_equal_approx(leg.offset.y, texture_origin.y - drop_y),
		"%s 旋转中心下移 %d px" % [label, int(drop_y)]
	)


func _check_attack_direction(
	visual: Node,
	facing: float,
	direction: Vector2,
	expected_rotation: float,
	label: String
) -> void:
	visual.set_facing(facing)
	visual.play_attack_animation(direction)
	visual.advance_animation(HumanVisualScript.SPEAR_WINDUP_TIME)
	var pivot: Node2D = visual.get_weapon_pivot()
	_check(
		pivot != null and absf(angle_difference(pivot.rotation, expected_rotation)) < 0.001,
		"%s 与攻击方向一致" % label
	)
	if pivot != null:
		var local_direction := Vector2(sin(expected_rotation), -cos(expected_rotation))
		var expected_position := (
			HumanVisualScript.BODY_WEAPON_ANCHOR
			- local_direction * HumanVisualScript.SPEAR_WINDUP_BACK_DISTANCE
		)
		_check(
			pivot.position.distance_to(expected_position) < 0.01,
			"%s 的前摇后移方向正确" % label
		)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[visual] OK: %s" % message)
	else:
		_failed = true
		push_error("[visual] FAIL: %s" % message)
