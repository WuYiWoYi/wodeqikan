extends Node
## 战斗死亡倒地、尸体留存/淡出与角色完整动态层级测试。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/battle_corpse_visual_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"
const HumanVisualScript = preload(
	"res://Scripts/Systems/Combat/human_visual.gd"
)
const VisualLayersScript = preload(
	"res://Scripts/Systems/Combat/visual_layers.gd"
)

var _failed: bool = false
var _context: WorldContext = null
var _battle_scene: Node2D = null
var _session: BattleSession = null
var _config: UnitConfig = null
var _units: UnitManager = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[corpse] 测试失败")
		get_tree().quit(1)
	else:
		print("[corpse] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	_config = load(MILITIA_PATH) as UnitConfig
	_units = UnitManager.new()
	_units.setup(IdGenerator.new())
	_check(_config != null, "加载民兵配置")
	if _config == null:
		return

	await _test_battle_corpse_lifecycle()
	_test_mounted_corpse_and_layering()
	_test_death_pose_vs_hit_reaction()
	_test_character_sort_bands()


# ---------------------------------------------------------------------------
# 战斗场景中的完整流程：死亡 → 倒地 → 留存 → 淡出 → 清理
# ---------------------------------------------------------------------------


func _test_battle_corpse_lifecycle() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)

	_context = WorldContext.new()
	_context.name = "CorpseTestContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	_context.battle_manager.set_wounded_config(null)
	var player := _context.get_player_party()
	var enemy := _find_party_by_name(WorldInitializer.TEST_ENEMY_PARTY_NAME)
	_check(player != null and enemy != null, "双方部队存在")
	if player == null or enemy == null:
		return

	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id
	_session = _context.battle_manager.start_battle(
		[player.party_id], [enemy.party_id], enemy.world_position
	)
	_check(_session != null, "创建战斗会话")
	if _session == null:
		return

	var packed := load("res://Scenes/Battle/battle.tscn") as PackedScene
	_battle_scene = packed.instantiate() as Node2D
	add_child(_battle_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	_battle_scene.set_result_delay_enabled(false)

	# 场景 _ready 后替换共享配置值，所有已生成单位引用同一资源。
	var corpse_config: CorpseConfig = _battle_scene.get_corpse_config()
	_check(corpse_config != null, "战斗场景加载尸体配置")
	if corpse_config == null:
		return
	corpse_config.fall_duration = 0.2
	corpse_config.linger_duration = 0.3
	corpse_config.fade_duration = 0.2

	var characters := _battle_scene.get_node("World/Characters") as Node2D
	var shadows := _battle_scene.get_node("World/Shadows") as Node2D
	_check(characters.y_sort_enabled, "角色层使用 Y 轴动态排序")

	var defender_id: String = _session.defender_unit_ids[0]
	var defender: UnitController = _battle_scene.get_controller(defender_id)
	_check(defender != null, "找到测试敌人")
	if defender == null:
		return
	var actor_count_before: int = _battle_scene.get_actor_count()
	var death_position: Vector2 = defender.get_position()

	# 直接结算致命伤害，再同步驱动场景的死亡处理（不依赖真实帧率）。
	defender.apply_damage(9999)
	_battle_scene._process_deaths()
	_check(not defender.is_alive(), "生命值归零后进入死亡数据状态")
	_check(
		_battle_scene.get_actor_count() == actor_count_before - 1,
		"死亡单位不再计入可战斗表现数量"
	)
	_check(defender.actor == null, "死亡后控制器与表现节点解除关联")

	var corpse := characters.get_node_or_null(
		"UnitActor_%s" % defender_id
	) as UnitActor
	_check(corpse != null, "死亡单位表现节点仍保留为尸体")
	if corpse == null:
		return
	corpse.set_process(false)
	var human: Node2D = corpse.visual.get_human_visual()
	if human != null:
		human.set_process(false)

	_check(
		corpse.get_corpse_state() == UnitActor.CorpseState.FALLING,
		"死亡后进入倒地阶段"
	)
	_check(corpse.is_corpse_sequence_active(), "尸体表现序列已开始")
	_check(corpse.get_parent() == characters, "尸体仍留在角色层参与排序")
	_check(corpse.position.distance_to(death_position) < 0.01, "尸体留在死亡位置")
	_check(
		corpse.z_index == corpse.get_sort_rank() * UnitActor.SORT_Z_STRIDE,
		"尸体仍使用角色整体排序波段"
	)
	_check(
		not corpse.is_name_visible()
			and not corpse.get_health_bar().is_bar_visible(),
		"尸体隐藏名称与生命条"
	)
	_check(
		corpse.visual.get_parent() == corpse,
		"完整角色视觉仍挂在同一个角色节点下"
	)
	_check(
		corpse.is_ancestor_of(corpse.visual),
		"人物、装备与马匹同属一个角色排序单元"
	)

	# 尸体仍在 Characters 中参与整体排序：与任一存活角色的全部非影子部件
	# 必须保持同一前后关系，不允许单个武器跨角色穿插。
	_battle_scene._update_character_sorting()
	var sort_reference_actor := characters.get_node_or_null(
		"UnitActor_%s" % _session.attacker_unit_ids[0]
	) as UnitActor
	if sort_reference_actor != null:
		var corpse_behind: bool = (
			corpse.battle_state.battle_position.y
			< sort_reference_actor.battle_state.battle_position.y
		)
		var corpse_ordered: bool = (
			_all_parts_above(sort_reference_actor, corpse)
			if corpse_behind
			else _all_parts_above(corpse, sort_reference_actor)
		)
		_check(corpse_ordered, "尸体与存活角色保持完整非影子层级关系")
	_check(
		corpse.get_sort_rank() >= 0
			and corpse.get_sort_rank() <= UnitActor.SORT_Z_MAX_RANK,
		"尸体排序名次在有效波段内"
	)

	# 交叉移动：使用战斗场景的真实排序入口，验证名次随 Y 更新且整体翻转。
	var move_a := characters.get_node_or_null(
		"UnitActor_%s" % _session.attacker_unit_ids[0]
	) as UnitActor
	var move_b := characters.get_node_or_null(
		"UnitActor_%s" % _session.attacker_unit_ids[1]
	) as UnitActor
	if move_a != null and move_b != null:
		var saved_a: Vector2 = move_a.battle_state.battle_position
		var saved_b: Vector2 = move_b.battle_state.battle_position
		move_a.battle_state.battle_position.y = saved_b.y + 40.0
		move_b.battle_state.battle_position.y = saved_a.y - 40.0
		_battle_scene._update_character_sorting()
		_check(
			_all_parts_above(move_a, move_b),
			"交叉移动后前排角色全部非影子贴图整体在上"
		)
		var swapped_a_y: float = move_a.battle_state.battle_position.y
		move_a.battle_state.battle_position.y = move_b.battle_state.battle_position.y
		move_b.battle_state.battle_position.y = swapped_a_y
		_battle_scene._update_character_sorting()
		_check(
			_all_parts_above(move_b, move_a),
			"交叉移动互换后整体层级同步反转"
		)
		move_a.battle_state.battle_position = saved_a
		move_b.battle_state.battle_position = saved_b
		_battle_scene._update_character_sorting()

	# 倒地：持续旋转与下沉，明显区别于受击后仰（受击倾角上限约 0.09）。
	var upper_body: Node2D = null
	if human != null:
		upper_body = human.get_upper_body()
	var rotation_before: float = upper_body.rotation if upper_body != null else 0.0
	corpse._process(corpse_config.fall_duration * 0.5)
	var mid_rotation: float = upper_body.rotation if upper_body != null else 0.0
	_check(
		corpse.get_corpse_state() == UnitActor.CorpseState.FALLING,
		"倒地动画持续时间内保持倒地阶段"
	)
	_check(
		mid_rotation > rotation_before + 0.2,
		"倒地过程中身体持续旋转"
	)
	_check(
		mid_rotation > HumanVisualScript.HIT_REACTION_TILT * 2.0,
		"倒地动作明显区别于普通受击后仰"
	)
	_check(
		upper_body != null and upper_body.position.y > 0.1,
		"倒地过程中身体重心下沉"
	)
	_check(
		corpse.get_corpse_alpha() == 1.0,
		"倒地与留存阶段尸体完全不透明"
	)

	corpse._process(corpse_config.fall_duration)
	_check(
		corpse.get_corpse_state() == UnitActor.CorpseState.LINGERING,
		"倒地完成后尸体进入留存阶段"
	)
	var fallen_rotation: float = upper_body.rotation if upper_body != null else 0.0
	_check(
		is_equal_approx(fallen_rotation, HumanVisualScript.DEATH_FALL_ANGLE),
		"倒地完成后保持最终倒地姿态"
	)
	_check(
		corpse.position.distance_to(death_position) < 0.01,
		"倒地旋转不改变角色排序基准位置"
	)

	# 留存阶段不淡出；到期后开始淡出。
	corpse._process(corpse_config.linger_duration * 0.5)
	_check(corpse.get_corpse_alpha() == 1.0, "留存时间内尸体保持完全可见")
	corpse._process(corpse_config.linger_duration)
	_check(
		corpse.get_corpse_state() == UnitActor.CorpseState.FADING,
		"留存时间结束后进入淡出阶段"
	)
	_check(
		is_equal_approx(upper_body.rotation, fallen_rotation),
		"淡出期间不重新播放倒地动画"
	)

	corpse._process(corpse_config.fade_duration * 0.5)
	var half_alpha: float = corpse.get_corpse_alpha()
	_check(
		half_alpha > 0.2 and half_alpha < 0.8,
		"淡出过程中透明度平滑降低"
	)
	_check(
		is_equal_approx(corpse.visual.modulate.a, half_alpha),
		"淡出统一作用于完整角色视觉子树"
	)
	var living_actor := characters.get_node_or_null(
		"UnitActor_%s" % _session.attacker_unit_ids[0]
	) as UnitActor
	_check(
		living_actor != null
			and is_equal_approx(living_actor.visual.modulate.a, 1.0),
		"尸体淡出不通过共享材质影响其他角色"
	)
	var weapon: Sprite2D = corpse.visual.get_part("Weapon")
	_check(
		weapon != null and corpse.is_ancestor_of(weapon),
		"武器与人物同属一个角色排序单元，随尸体一起淡出"
	)
	_check(
		corpse.visual.get_part("Body") != null
			and corpse.is_ancestor_of(corpse.visual.get_part("Body")),
		"身体与装备同属一个角色排序单元"
	)
	_check(
		corpse.get_corpse_state() == UnitActor.CorpseState.FADING,
		"淡出期间保持尸体状态"
	)
	_check(
		corpse.is_corpse_visible(),
		"淡出未完成时尸体仍然可见"
	)

	var shadow_root: Node2D = corpse.get_shadow_root()
	_check(shadow_root != null, "尸体拥有独立影子节点")
	corpse._process(corpse_config.fade_duration)
	_check(
		corpse.is_queued_for_deletion(),
		"淡出完成后移除尸体视觉对象"
	)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not is_instance_valid(corpse), "尸体节点已正确清理")
	_check(
		shadow_root == null or not is_instance_valid(shadow_root),
		"尸体影子随视觉对象一起清理"
	)
	_check(
		characters.get_node_or_null("UnitActor_%s" % defender_id) == null,
		"角色层不残留尸体节点"
	)
	_check(
		shadows.get_node_or_null("UnitShadow_%s" % defender_id) == null,
		"影子层不残留尸体影子"
	)
	_check(
		_session.get_unit_state(defender_id).alive == false,
		"尸体清理不影响战斗数据状态"
	)
	_check(
		_battle_scene.get_actor_count() == actor_count_before - 1,
		"尸体清理不改变可战斗单位统计"
	)

	# 结算不受尸体表现影响。
	for unit_id: String in _session.defender_unit_ids:
		var state := _session.get_unit_state(unit_id)
		if state != null:
			state.battle_hp = 0
			state.alive = false
	await get_tree().physics_frame
	await get_tree().physics_frame
	var result_panel := _battle_scene.find_child(
		"BattleResultPanel", true, false
	) as PanelContainer
	_check(result_panel != null and result_panel.visible, "尸体表现不影响胜利结算")
	_check(
		_context.battle_manager.finish_battle(
			_session.battle_id, BattleSession.BattleResult.ATTACKER_VICTORY
		),
		"尸体存在时仍可正常结算"
	)
	_check(_context.battle_manager.current_battle == null, "结算后清理战斗会话")


# ---------------------------------------------------------------------------
# 骑乘尸体与内部图层
# ---------------------------------------------------------------------------


func _test_mounted_corpse_and_layering() -> void:
	var shadow_parent := Node2D.new()
	shadow_parent.name = "StandaloneShadows"
	add_child(shadow_parent)
	var actor := _spawn_standalone_actor(
		Vector2(400.0, 400.0), true, shadow_parent
	)
	_check(actor != null, "创建骑乘测试单位")
	if actor == null:
		return
	actor.set_process(false)
	var visual: Node2D = actor.visual
	var human: Node2D = visual.get_human_visual()
	var horse: Node2D = visual.get_horse_visual()
	human.set_process(false)
	_check(visual.is_mounted_visual(), "测试单位处于骑乘表现")

	# 内部层级在死亡前后保持一致。
	var layers_before := _capture_layer_order(visual)
	actor.play_death()
	_check(actor.is_corpse_sequence_active(), "骑乘单位进入死亡表现")
	_check(human.is_death_pose_locked(), "人物进入倒地姿态")
	_check(horse.is_death_pose_locked(), "马匹进入倒地姿态")
	actor._process(0.6)

	var upper_body: Node2D = human.get_upper_body()
	_check(
		is_equal_approx(upper_body.rotation, HumanVisualScript.DEATH_FALL_ANGLE),
		"骑手完成倒地旋转"
	)
	var horse_rig: Node2D = horse.get_body_rig()
	_check(
		horse_rig != null and horse_rig.rotation > 0.2,
		"马匹随骑手一同倒地"
	)
	_check(
		horse_rig != null and horse_rig.scale.y < 1.0,
		"马匹倒地时轻微压扁"
	)
	_check(
		actor.get_corpse_state() == UnitActor.CorpseState.LINGERING,
		"骑乘尸体倒地完成后进入留存"
	)
	_check(
		_capture_layer_order(visual) == layers_before,
		"倒地不破坏人物/马匹/武器内部层级"
	)

	# 淡出覆盖人物、马匹、武器与影子。
	var shadow_root: Node2D = actor.get_shadow_root()
	var shadow_sprite: Sprite2D = null
	if shadow_root != null:
		for child: Node in shadow_root.get_children():
			shadow_sprite = child as Sprite2D
			if shadow_sprite != null:
				break
	var shadow_alpha_before: float = (
		shadow_sprite.modulate.a if shadow_sprite != null else 1.0
	)
	actor._process(6.0 + 0.01)
	_check(
		actor.get_corpse_state() == UnitActor.CorpseState.FADING,
		"骑乘尸体进入淡出阶段"
	)
	actor._process(0.1)
	_check(
		actor.get_corpse_alpha() > 0.2 and actor.get_corpse_alpha() < 0.8,
		"骑乘尸体整体透明度平滑降低"
	)
	_check(
		visual.get_part("MountBody") != null
			and actor.is_ancestor_of(visual.get_part("MountBody")),
		"马匹与骑手同属一个角色排序单元"
	)
	_check(
		visual.get_part("Weapon") != null
			and actor.is_ancestor_of(visual.get_part("Weapon")),
		"武器随完整角色视觉一起淡出"
	)
	if shadow_sprite != null:
		_check(
			shadow_sprite.modulate.a < shadow_alpha_before,
			"尸体淡出同时覆盖独立影子"
		)
	_check(
		actor.get_corpse_state() == UnitActor.CorpseState.FADING,
		"淡出过程中尸体状态保持稳定"
	)
	actor.queue_free()
	shadow_parent.queue_free()


# ---------------------------------------------------------------------------
# 倒地姿态与受击动作的区分、朝向
# ---------------------------------------------------------------------------


func _test_death_pose_vs_hit_reaction() -> void:
	var hit_actor := _spawn_standalone_actor(Vector2(200.0, 300.0), false, null)
	var death_actor := _spawn_standalone_actor(Vector2(600.0, 300.0), false, null)
	_check(hit_actor != null and death_actor != null, "创建受击/死亡对照单位")
	if hit_actor == null or death_actor == null:
		return
	for actor: UnitActor in [hit_actor, death_actor]:
		actor.set_process(false)
		actor.visual.get_human_visual().set_process(false)

	# 普通受击：位置短促偏移，倾角很小，且自动恢复。
	hit_actor.visual.play_hit_reaction(Vector2.RIGHT)
	_check(hit_actor.visual.is_hit_reacting(), "普通受击播放受击动作")
	hit_actor.visual.update_locomotion(0.01, false)
	var hit_upper: Node2D = hit_actor.visual.get_human_visual().get_upper_body()
	_check(
		absf(hit_upper.rotation) <= HumanVisualScript.HIT_REACTION_TILT + 0.001,
		"受击动作倾角保持在轻微范围"
	)
	_check(not hit_actor.is_corpse_sequence_active(), "普通受击不会进入死亡表现")

	# 死亡：大幅度倒地并永久保持。
	death_actor.play_death()
	death_actor._process(0.6)
	var death_upper: Node2D = death_actor.visual.get_human_visual().get_upper_body()
	_check(
		death_upper.rotation > HumanVisualScript.DEATH_FALL_ANGLE - 0.001,
		"死亡倒地达到明显大于受击的倾角"
	)
	_check(
		not death_actor.visual.is_hit_reacting(),
		"死亡倒地不复用受击动作"
	)
	_check(
		death_actor.visual.get_human_visual().is_death_pose_locked(),
		"倒地姿态已锁定，不会被待机/受击覆盖"
	)
	death_actor.visual.update_locomotion(1.0, true)
	_check(
		is_equal_approx(death_upper.rotation, HumanVisualScript.DEATH_FALL_ANGLE),
		"倒地后普通动画不再覆盖尸体姿态"
	)

	# 朝向：人物镜像决定倒向背后，倒地姿态本身保持稳定。
	var left_actor := _spawn_standalone_actor(Vector2(900.0, 300.0), false, null)
	var right_actor := _spawn_standalone_actor(Vector2(1100.0, 300.0), false, null)
	if left_actor != null and right_actor != null:
		left_actor.set_process(false)
		right_actor.set_process(false)
		left_actor.set_facing(-1.0)
		right_actor.set_facing(1.0)
		left_actor.play_death()
		right_actor.play_death()
		left_actor._process(0.6)
		right_actor._process(0.6)
		var left_human: Node2D = left_actor.visual.get_human_visual()
		var right_human: Node2D = right_actor.visual.get_human_visual()
		_check(
			is_equal_approx(left_human.scale.x, 1.0)
				and is_equal_approx(right_human.scale.x, -1.0),
			"不同朝向使用镜像表现"
		)
		_check(
			is_equal_approx(
				left_human.get_upper_body().rotation,
				right_human.get_upper_body().rotation
			),
			"倒地姿态按朝向镜像后视觉上倒向角色背后"
		)
		left_actor.queue_free()
		right_actor.queue_free()

	hit_actor.queue_free()
	death_actor.queue_free()


# ---------------------------------------------------------------------------
# 角色完整动态层级
# ---------------------------------------------------------------------------


func _test_character_sort_bands() -> void:
	var rear := _spawn_standalone_actor(Vector2(300.0, 500.0), true, null)
	var middle := _spawn_standalone_actor(Vector2(300.0, 520.0), false, null)
	var front := _spawn_standalone_actor(Vector2(300.0, 540.0), true, null)
	_check(
		rear != null and middle != null and front != null,
		"创建前中后三个测试角色"
	)
	if rear == null or middle == null or front == null:
		return
	var actors: Array[UnitActor] = [rear, middle, front]
	for actor: UnitActor in actors:
		actor.set_process(false)

	# 每个角色的全部部件都在自己的根节点之下，不存在脱离角色排序的武器节点。
	var all_parts_inside: bool = true
	for actor: UnitActor in actors:
		for part_name: String in _non_shadow_part_names(actor):
			var part: Sprite2D = actor.visual.get_part(part_name)
			if part == null or not actor.is_ancestor_of(part):
				all_parts_inside = false
	_check(all_parts_inside, "所有非影子部件都随角色整体排序")

	# 波段间隔必须大于角色内部层级跨度，否则前排最低部件仍可能低于后排最高部件。
	var span: int = _internal_layer_span(front)
	_check(
		UnitActor.SORT_Z_STRIDE > span,
		"角色波段间隔大于内部层级跨度（%d > %d）"
			% [UnitActor.SORT_Z_STRIDE, span]
	)

	rear.apply_sort_rank(0)
	middle.apply_sort_rank(1)
	front.apply_sort_rank(2)
	_check(
		front.z_index > middle.z_index and middle.z_index > rear.z_index,
		"角色根节点获得互不重叠的整体层级"
	)
	_check(
		_all_parts_above(front, middle)
			and _all_parts_above(front, rear)
			and _all_parts_above(middle, rear),
		"前排角色的全部非影子贴图高于后排角色"
	)
	_check(
		not _all_parts_above(rear, middle)
			and not _all_parts_above(middle, front),
		"反向遮挡关系与角色名次严格对应"
	)

	# 内部层级保持原设计：倒置名次不会改变角色内部遮挡。
	var layers := _capture_layer_order(front.visual)
	_check(
		int(layers.get("Weapon", 0)) == VisualLayersScript.RIGHT_HAND_WEAPON,
		"右手武器保持原内部层级"
	)
	_check(
		int(layers.get("MountHead", 0)) > int(layers.get("Head", 0)),
		"马头仍位于人头之前"
	)
	_check(
		int(layers.get("Body", 0)) > int(layers.get("LegLeft", 0)),
		"身体仍位于左腿之前"
	)
	_check(
		int(layers.get("Weapon", 0)) > int(layers.get("MountHead", 0)),
		"武器仍位于马头之前"
	)

	# 交叉移动：名次互换后整体遮挡关系同步反转，不出现部分贴图滞后。
	rear.apply_sort_rank(2)
	middle.apply_sort_rank(1)
	front.apply_sort_rank(0)
	_check(
		_all_parts_above(rear, middle) and _all_parts_above(middle, front),
		"名次互换后整体层级同步反转"
	)
	_check(
		not _all_parts_above(front, middle),
		"反转后前排角色不再压过新前排"
	)

	# 尸体仍参与整体排序，倒地姿态不改变外部层级关系。
	rear.apply_sort_rank(0)
	middle.apply_sort_rank(1)
	front.apply_sort_rank(2)
	front.play_death()
	front._process(0.6)
	_check(
		front.get_corpse_state() == UnitActor.CorpseState.LINGERING,
		"测试角色进入尸体留存"
	)
	_check(
		_all_parts_above(front, middle) and _all_parts_above(front, rear),
		"倒地尸体仍保持完整角色整体层级"
	)
	_check(
		front.position == Vector2(300.0, 540.0),
		"倒地不改变角色排序基准位置"
	)

	for actor: UnitActor in actors:
		actor.queue_free()


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------


## 角色完整排序单元内的全部非影子部件名。影子按需求使用独立排序，不参与比较。
func _non_shadow_part_names(actor: UnitActor) -> Array[String]:
	var result: Array[String] = []
	if actor == null or actor.visual == null:
		return result
	var visual := actor.visual as UnitVisual
	if visual == null:
		return result
	for part_name_value: Variant in visual.get_parts().keys():
		var part_name: String = str(part_name_value)
		if part_name == "FootShadow" or part_name == "MountShadow":
			continue
		result.append(part_name)
	return result


## above 的每一个非影子部件都必须高于 below 的每一个非影子部件。
func _all_parts_above(above: UnitActor, below: UnitActor) -> bool:
	var above_parts := _non_shadow_part_names(above)
	var below_parts := _non_shadow_part_names(below)
	if above_parts.is_empty() or below_parts.is_empty():
		return false
	for above_part: String in above_parts:
		for below_part: String in below_parts:
			if (
				above.get_part_canvas_z(above_part)
				<= below.get_part_canvas_z(below_part)
			):
				return false
	return true


func _internal_layer_span(actor: UnitActor) -> int:
	var min_z: int = 99999
	var max_z: int = -99999
	for part_name: String in _non_shadow_part_names(actor):
		var part_z: int = actor.visual.get_part_effective_z(part_name)
		min_z = mini(min_z, part_z)
		max_z = maxi(max_z, part_z)
	return max_z - min_z


func _spawn_standalone_actor(
	position: Vector2,
	mounted: bool,
	shadow_parent: Node2D
) -> UnitActor:
	var unit: UnitData = _units.create_unit(_config, "FACTION_ENEMY")
	unit.max_hp = 200
	unit.current_hp = 200
	unit.is_mounted = mounted
	var state := BattleUnitState.new()
	state.unit_id = unit.unit_id
	state.party_id = "PARTY_TEST"
	state.battle_hp = 200
	state.alive = true
	state.battle_position = position

	var actor := UnitActor.new()
	add_child(actor)
	actor.setup(unit, state, false, {}, shadow_parent, _make_test_corpse_config())
	return actor


func _make_test_corpse_config() -> CorpseConfig:
	var config := CorpseConfig.new()
	config.fall_duration = 0.55
	config.linger_duration = 0.3
	config.fade_duration = 0.2
	return config


## 读取关键部件的相对层级，用于验证倒地前后内部遮挡关系不变。
func _capture_layer_order(visual: Node2D) -> Dictionary:
	var layers: Dictionary = {}
	for part_name: String in [
		"Weapon", "MountHead", "Head", "Tabard", "Body",
		"LegRight", "LegLeft", "MountBody", "FootShadow", "MountShadow"
	]:
		if visual.has_part(part_name):
			layers[part_name] = visual.get_part_effective_z(part_name)
	return layers


func _find_party_by_name(party_name: String) -> PartyData:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[corpse] OK: %s" % message)
	else:
		_failed = true
		push_error("[corpse] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_battle_scene):
		_battle_scene.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
