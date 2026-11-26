extends Node
## 近战攻击时序与受击反馈测试：
## 前摇无伤害、戳击有效帧结算一次、未命中无反馈、受击打断、
## 僵直期间禁止移动/攻击、连续受击刷新、死亡优先、白闪与受击动作。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/melee_attack_timing_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"
const HumanVisualScript = preload(
	"res://Scripts/Systems/Combat/human_visual.gd"
)

var _failed: bool = false
var _config: UnitConfig = null
var _units: UnitManager = null
## 事件记录：验证“攻击开始”与“真实伤害”是分离的两个时点。
var _attack_started_ids: Array[String] = []
var _hit_records: Array[Dictionary] = []
var _staggered_ids: Array[String] = []


func _ready() -> void:
	EventBus.unit_attack_started.connect(_on_attack_started)
	EventBus.unit_hit.connect(_on_unit_hit)
	EventBus.unit_staggered.connect(_on_unit_staggered)
	_run()
	_cleanup()
	if _failed:
		push_error("[melee] 测试失败")
		get_tree().quit(1)
	else:
		print("[melee] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	_config = load(MILITIA_PATH) as UnitConfig
	_check(_config != null, "加载民兵配置")
	if _config == null:
		return
	_units = UnitManager.new()
	_units.setup(IdGenerator.new())

	_test_hit_frame_timing_and_single_resolution()
	_test_missed_attack_no_feedback()
	_test_free_swing_no_damage()
	_test_interrupt_before_hit_frame()
	_test_interrupt_after_hit_frame()
	_test_stagger_blocks_action()
	_test_consecutive_hits_refresh()
	_test_death_overrides_stagger()
	_test_mounted_flash_and_material_isolation()
	_test_hit_reaction_direction()
	_test_event_contract()


## 1. 前摇/戳击前半不扣血；有效帧只结算一次；攻击间隔与伤害沿用既有规则。
func _test_hit_frame_timing_and_single_resolution() -> void:
	_reset_events()
	var attacker := _spawn("FACTION_PLAYER", 0, Vector2(500.0, 500.0), true)
	attacker.set_player_controlled(true)
	var target := _spawn("FACTION_ENEMY", 1, Vector2(530.0, 500.0), true)
	var hp_before: int = target.state.battle_hp

	_check(
		attacker.player_attack_at(target.get_position(), [target]),
		"攻击动作成功释放"
	)
	_check(target.state.battle_hp == hp_before, "攻击开始瞬间不扣血")
	_check(attacker.has_pending_attack(), "攻击进入有效帧待结算状态")
	_check(
		attacker.get_pending_attack_target_id() == target.unit_id,
		"待结算攻击锁存目标"
	)
	_check(
		attacker.actor != null and attacker.actor.is_attack_animating(),
		"攻击动画已开始播放"
	)
	_check(_hit_records.is_empty(), "尚未到达有效帧，不广播命中事件")
	_check(
		is_equal_approx(
			attacker.get_attack_cooldown(), attacker.unit_data.attack_interval
		),
		"攻击间隔在出手瞬间进入冷却（数值不变）"
	)

	attacker.actor.advance_attack_animation(HumanVisualScript.SPEAR_WINDUP_TIME)
	_check(target.state.battle_hp == hp_before, "前摇阶段不造成伤害")
	_check(attacker.has_pending_attack(), "前摇阶段仍等待有效帧")

	attacker.actor.advance_attack_animation(
		HumanVisualScript.SPEAR_THRUST_TIME * 0.5
	)
	_check(target.state.battle_hp == hp_before, "戳击前半段不造成伤害")
	_check(_hit_records.is_empty(), "有效帧前保持零命中事件")

	var expected_damage: int = attacker.get_attack_damage()
	attacker.actor.advance_attack_animation(
		HumanVisualScript.SPEAR_THRUST_TIME * 0.5 + 0.001
	)
	_check(
		target.state.battle_hp == hp_before - expected_damage,
		"有效帧按既有攻击力结算一次伤害"
	)
	_check(not attacker.has_pending_attack(), "结算后清除待结算状态")
	_check(
		attacker.get_last_attack_target_id() == target.unit_id,
		"命中后记录实际攻击目标"
	)
	_check(target.is_staggered(), "真实伤害后目标进入受击僵直")
	_check(
		is_equal_approx(target.get_stagger_remaining(), UnitController.STAGGER_DURATION),
		"僵直使用统一时长"
	)
	_check(
		target.actor != null and target.actor.is_hit_flashing(),
		"真实伤害触发白闪"
	)
	_check(
		target.actor.visual.is_hit_reacting(),
		"真实伤害触发受击动作"
	)
	_check(_hit_count_for(target.unit_id) == 1, "一次攻击只广播一次命中")

	# 继续推进完整动画：保持、恢复、回到待机，均不能再次结算。
	var hp_after_hit: int = target.state.battle_hp
	for i: int in range(10):
		attacker.actor.advance_attack_animation(0.5)
	_check(target.state.battle_hp == hp_after_hit, "后续动画推进不产生重复伤害")
	_check(_hit_count_for(target.unit_id) == 1, "整次攻击只结算一次伤害")
	_check(
		not attacker.actor.is_attack_animating(),
		"完整动画结束后回到待机"
	)


## 2. 目标离开有效区域时未命中：无伤害、无白闪、无僵直。
func _test_missed_attack_no_feedback() -> void:
	_reset_events()
	var attacker := _spawn("FACTION_PLAYER", 0, Vector2(300.0, 300.0), true)
	attacker.set_player_controlled(true)
	var target := _spawn("FACTION_ENEMY", 1, Vector2(330.0, 300.0), true)
	var hp_before: int = target.state.battle_hp

	_check(
		attacker.player_attack_at(target.get_position(), [target]),
		"目标在范围内时正常出手"
	)
	# 有效帧前目标移出攻击矩形。
	target.state.battle_position = Vector2(700.0, 700.0)
	_advance_to_hit_frame(attacker)

	_check(target.state.battle_hp == hp_before, "有效帧失效时未造成伤害")
	_check(not target.is_staggered(), "未命中不触发僵直")
	_check(
		target.actor != null and not target.actor.is_hit_flashing(),
		"未命中不触发白闪"
	)
	_check(
		target.actor != null and not target.actor.visual.is_hit_reacting(),
		"未命中不播放受击动作"
	)
	_check(
		attacker.get_last_attack_target_id().is_empty(),
		"未命中不记录攻击目标"
	)
	_check(_hit_records.is_empty(), "未命中不广播命中事件")
	_check(_attack_started_ids.has(attacker.unit_id), "空挥同样会广播攻击开始")


## 3. 空挥：完整动作与冷却，不产生待结算伤害。
func _test_free_swing_no_damage() -> void:
	_reset_events()
	var attacker := _spawn("FACTION_PLAYER", 0, Vector2(300.0, 550.0), true)
	attacker.set_player_controlled(true)

	_check(
		attacker.player_attack_at(Vector2(900.0, 100.0), []),
		"没有敌人时仍可主动空挥"
	)
	_check(not attacker.has_pending_attack(), "空挥不创建待结算伤害")
	_check(
		attacker.actor != null and attacker.actor.is_attack_animating(),
		"空挥播放完整攻击动画"
	)
	_check(
		is_equal_approx(
			attacker.get_attack_cooldown(), attacker.unit_data.attack_interval
		),
		"空挥同样进入攻击冷却"
	)
	attacker.actor.advance_attack_animation(1.0)
	_check(_hit_records.is_empty(), "空挥不产生命中事件")
	_check(attacker.get_last_attack_target_id().is_empty(), "空挥没有虚构目标")


## 4. 有效帧前受击：攻击被打断，无伤害，攻击表现取消。
func _test_interrupt_before_hit_frame() -> void:
	_reset_events()
	var attacker := _spawn("FACTION_PLAYER", 0, Vector2(200.0, 200.0), true)
	attacker.set_player_controlled(true)
	var target := _spawn("FACTION_ENEMY", 1, Vector2(230.0, 200.0), true)
	var striker := _spawn("FACTION_ENEMY", 1, Vector2(150.0, 200.0), false)
	var hp_before: int = target.state.battle_hp

	_check(
		attacker.player_attack_at(target.get_position(), [target]),
		"攻击正常开始"
	)
	attacker.actor.advance_attack_animation(HumanVisualScript.SPEAR_WINDUP_TIME * 0.5)
	attacker.apply_damage(1, striker, Vector2.RIGHT)

	_check(attacker.is_staggered(), "前摇受击进入僵直")
	_check(not attacker.has_pending_attack(), "前摇受击取消待结算攻击")
	_check(
		attacker.actor != null and not attacker.actor.is_attack_animating(),
		"前摇受击取消攻击动画"
	)
	_check(
		attacker.get_last_attack_target_id().is_empty(),
		"被打断的攻击不记录目标"
	)

	attacker.actor.advance_attack_animation(1.0)
	_check(target.state.battle_hp == hp_before, "被打断的攻击不造成伤害")
	_check(_hit_count_for(target.unit_id) == 0, "被打断的攻击不广播命中")
	_check(not target.is_staggered(), "目标未受击，不进入僵直")


## 5. 有效帧后受击：已成立伤害不可撤销。
func _test_interrupt_after_hit_frame() -> void:
	_reset_events()
	var attacker := _spawn("FACTION_PLAYER", 0, Vector2(400.0, 200.0), true)
	attacker.set_player_controlled(true)
	var target := _spawn("FACTION_ENEMY", 1, Vector2(430.0, 200.0), true)
	var striker := _spawn("FACTION_ENEMY", 1, Vector2(350.0, 200.0), false)
	var hp_before: int = target.state.battle_hp

	_check(
		attacker.player_attack_at(target.get_position(), [target]),
		"攻击正常开始"
	)
	_advance_to_hit_frame(attacker)
	var hp_after_hit: int = target.state.battle_hp
	_check(hp_after_hit < hp_before, "有效帧伤害已成立")

	attacker.apply_damage(1, striker, Vector2.RIGHT)
	_check(attacker.is_staggered(), "有效帧后受击仍进入僵直")
	_check(target.state.battle_hp == hp_after_hit, "已成立伤害不因后续受击撤销")
	_check(_hit_count_for(target.unit_id) == 1, "已成立命中只记录一次")


## 6. 僵直期间停止移动、不能启动新攻击；结束后恢复且不修改基础属性。
func _test_stagger_blocks_action() -> void:
	_reset_events()
	var player := _spawn("FACTION_PLAYER", 0, Vector2(500.0, 500.0), true)
	player.set_player_controlled(true)
	var enemy := _spawn("FACTION_ENEMY", 1, Vector2(530.0, 500.0), true)
	var attacker_side := _spawn("FACTION_ENEMY", 1, Vector2(450.0, 500.0), false)
	var attack_before: int = player.unit_data.attack
	var speed_before: float = player.unit_data.move_speed
	var max_hp_before: int = player.unit_data.max_hp

	player.apply_damage(1, attacker_side, Vector2.RIGHT)
	_check(player.is_staggered(), "受击后进入僵直")
	_check(
		player.get_ai_state() == UnitController.AIState.STAGGERED,
		"僵直使用独立行为状态"
	)
	var position_before: Vector2 = player.get_position()
	player.player_tick(0.05, Vector2.RIGHT)
	_check(player.get_position() == position_before, "僵直期间不响应移动输入")
	_check(not player.is_moving(), "僵直期间移动状态为否")
	_check(
		not player.player_attack_at(enemy.get_position(), [enemy]),
		"僵直期间不能启动新的攻击"
	)
	_check(
		player.get_stagger_remaining() < UnitController.STAGGER_DURATION,
		"僵直计时随 tick 正常递减"
	)

	player.player_tick(UnitController.STAGGER_DURATION + 0.01, Vector2.ZERO)
	_check(not player.is_staggered(), "僵直结束后恢复")
	_check(
		player.get_ai_state() != UnitController.AIState.STAGGERED,
		"僵直结束后退出僵直状态"
	)
	_check(player.get_position() == position_before, "僵直结束不会产生额外位移")

	player.player_tick(0.1, Vector2.RIGHT)
	_check(player.get_position().x > position_before.x, "僵直结束后恢复移动")
	var enemy_hp: int = enemy.state.battle_hp
	_check(
		player.player_attack_at(enemy.get_position(), [enemy]),
		"僵直结束后可以再次攻击"
	)
	_advance_to_hit_frame(player)
	_check(enemy.state.battle_hp < enemy_hp, "恢复后的攻击正常结算")

	_check(player.unit_data.attack == attack_before, "僵直不修改攻击力")
	_check(
		is_equal_approx(player.unit_data.move_speed, speed_before),
		"僵直不修改移动速度"
	)
	_check(player.unit_data.max_hp == max_hp_before, "僵直不修改最大 HP")


## 7. 连续受击只刷新僵直计时，不无限叠加；两次受击均重新白闪。
func _test_consecutive_hits_refresh() -> void:
	_reset_events()
	var target := _spawn("FACTION_ENEMY", 1, Vector2(600.0, 600.0), true)
	var striker := _spawn("FACTION_PLAYER", 0, Vector2(560.0, 600.0), false)

	target.apply_damage(1, striker, Vector2.RIGHT)
	_check(target.is_staggered(), "第一次受击进入僵直")
	target.tick(0.1, [])
	var remaining_before: float = target.get_stagger_remaining()
	_check(remaining_before < UnitController.STAGGER_DURATION, "僵直计时开始递减")

	target.apply_damage(1, striker, Vector2.RIGHT)
	_check(
		is_equal_approx(target.get_stagger_remaining(), UnitController.STAGGER_DURATION),
		"连续受击刷新到统一时长而不是叠加"
	)
	_check(
		target.actor != null
			and is_equal_approx(target.actor.visual.get_hit_flash_strength(), 1.0),
		"连续受击重新触发白闪"
	)

	target.tick(0.2, [])
	_check(target.is_staggered(), "刷新后的僵直仍在生效")
	target.tick(0.1, [])
	_check(not target.is_staggered(), "僵直结束后可以正常行动")


## 8. 死亡优先级高于受击：致命伤害不进入僵直/受击动作。
func _test_death_overrides_stagger() -> void:
	_reset_events()
	var target := _spawn("FACTION_ENEMY", 1, Vector2(700.0, 400.0), true, false, 10)
	var striker := _spawn("FACTION_PLAYER", 0, Vector2(660.0, 400.0), false)

	target.apply_damage(9999, striker, Vector2.RIGHT)
	_check(not target.is_alive(), "致命伤害使单位死亡")
	_check(not target.is_staggered(), "死亡单位不进入僵直")
	_check(
		is_zero_approx(target.get_stagger_remaining()),
		"死亡时清空僵直计时"
	)
	_check(
		target.actor != null and not target.actor.is_hit_flashing(),
		"死亡不播放受击白闪"
	)
	_check(
		target.actor != null and not target.actor.visual.is_hit_reacting(),
		"死亡不播放受击动作"
	)
	var record := _last_hit_record_for(target.unit_id)
	_check(
		not record.is_empty() and bool(record.get("killed", false)),
		"致命伤害的命中事件标记 killed"
	)


## 9. 骑马白闪覆盖人物与马匹；材质实例按角色隔离，影子不受白闪影响。
func _test_mounted_flash_and_material_isolation() -> void:
	_reset_events()
	var rider := _spawn("FACTION_ENEMY", 1, Vector2(600.0, 300.0), true, true)
	var other_rider := _spawn("FACTION_ENEMY", 1, Vector2(660.0, 300.0), true, true)
	var striker := _spawn("FACTION_PLAYER", 0, Vector2(560.0, 300.0), false)

	_check(
		rider.actor != null and rider.actor.visual.is_mounted_visual(),
		"测试单位处于骑乘表现"
	)
	rider.apply_damage(1, striker, Vector2.RIGHT)
	_check(
		rider.actor != null and is_equal_approx(
			rider.actor.visual.get_hit_flash_strength(), 1.0
		),
		"受击白闪强度为 1"
	)

	var body: Sprite2D = rider.actor.visual.get_part("Body")
	var head: Sprite2D = rider.actor.visual.get_part("Head")
	var weapon: Sprite2D = rider.actor.visual.get_part("Weapon")
	var tabard: Sprite2D = rider.actor.visual.get_part("Tabard")
	var mount_body: Sprite2D = rider.actor.visual.get_part("MountBody")
	var mount_head: Sprite2D = rider.actor.visual.get_part("MountHead")
	var foot_shadow: Sprite2D = rider.actor.visual.get_part("FootShadow")
	var mount_shadow: Sprite2D = rider.actor.visual.get_part("MountShadow")

	_check(
		body != null and mount_body != null and head != null and mount_head != null,
		"人物与马匹部件同时存在"
	)
	_check(_flash_of(body) == 1.0, "人物身体受击白闪")
	_check(_flash_of(head) == 1.0, "人物头部受击白闪")
	_check(_flash_of(weapon) == 1.0, "武器受击白闪")
	_check(_flash_of(mount_body) == 1.0, "马身受击白闪")
	_check(_flash_of(mount_head) == 1.0, "马头受击白闪")
	_check(_flash_of(tabard) == 1.0, "阵营罩袍同步白闪")
	_check(
		body != null and mount_body != null and body.material == mount_body.material,
		"同一角色的全部部件共用材质实例"
	)
	_check(
		tabard != null and (tabard.material as ShaderMaterial) != null
			and bool(
				(tabard.material as ShaderMaterial).get_shader_parameter(
					"use_faction_color"
				)
			),
		"罩袍保留阵营着色材质"
	)
	_check(
		foot_shadow != null and not (foot_shadow.material is ShaderMaterial),
		"人物影子不参与白闪"
	)
	_check(
		mount_shadow != null and not (mount_shadow.material is ShaderMaterial),
		"马匹影子不参与白闪"
	)

	var other_body: Sprite2D = other_rider.actor.visual.get_part("Body")
	_check(
		body != null and other_body != null and body.material != other_body.material,
		"不同角色的白闪材质实例互不共享"
	)
	_check(_flash_of(other_body) == 0.0, "其他角色不会同步白闪")

	# 连续受击：白闪重新拉满，不残留到其他状态。
	rider.apply_damage(1, striker, Vector2.RIGHT)
	_check(
		rider.actor != null
			and is_equal_approx(rider.actor.visual.get_hit_flash_strength(), 1.0),
		"连续受击重新拉满白闪"
	)

	# 白闪自然回落后恢复原色，但材质/贴图结构不变。
	rider.actor._process(UnitActor.HIT_FLASH_DURATION * 0.5)
	_check(
		rider.actor.is_hit_flashing(),
		"白闪在持续时间内逐渐回落"
	)
	rider.actor._process(UnitActor.HIT_FLASH_DURATION)
	_check(not rider.actor.is_hit_flashing(), "白闪结束后恢复")
	_check(rider.actor.visual.get_hit_flash_strength() == 0.0, "白闪强度归零")
	_check(_flash_of(body) == 0.0, "人物恢复原色")
	_check(_flash_of(mount_body) == 0.0, "马匹恢复原色")
	_check(_flash_of(tabard) == 0.0, "罩袍恢复阵营色")
	_check(
		body != null and body.modulate == Color.WHITE,
		"白闪不永久修改贴图颜色"
	)


## 10. 受击动作按朝向换算到局部坐标，结束后回到基准姿态。
func _test_hit_reaction_direction() -> void:
	var unit := _spawn("FACTION_ENEMY", 1, Vector2(800.0, 300.0), true)
	var visual: Node2D = unit.actor.visual
	var upper: Node2D = visual.get_human_visual().get_upper_body()
	_check(upper != null, "人物上半身变换节点存在")

	visual.set_facing(-1.0)
	visual.play_hit_reaction(Vector2.RIGHT)
	_check(
		visual.get_hit_reaction_local_direction().x < -0.5,
		"朝左受击时局部偏移向左"
	)
	visual.update_locomotion(0.01, false)
	_check(upper.position.x < -1.0, "受击动作实际作用于身体节点")

	var reaction_x: float = upper.position.x
	visual.update_locomotion(0.02, false)
	_check(
		upper.position.x > reaction_x,
		"受击动作随时间衰减"
	)
	for i: int in range(15):
		visual.update_locomotion(0.02, false)
	_check(not visual.is_hit_reacting(), "受击动作结束后自动恢复")
	_check(absf(upper.position.x) < 0.001, "受击动作不残留横向偏移")

	visual.set_facing(1.0)
	_check(
		is_equal_approx(visual.get_human_visual().scale.x, -1.0),
		"朝右时人物整体镜像"
	)
	visual.play_hit_reaction(Vector2.RIGHT)
	_check(
		visual.get_hit_reaction_local_direction().x > 0.5,
		"朝右受击时局部偏移方向随镜像翻转"
	)
	visual.update_locomotion(0.01, false)
	_check(upper.position.x > 1.0, "朝右受击动作作用于身体节点")
	visual.reset_hit_reaction()
	visual.update_locomotion(0.01, false)
	_check(not visual.is_hit_reacting(), "重置受击动作生效")


## 11. 事件契约：攻击开始 / 真实命中 / 僵直分别在不同时点广播。
func _test_event_contract() -> void:
	_reset_events()
	var attacker := _spawn("FACTION_PLAYER", 0, Vector2(900.0, 500.0), true)
	attacker.set_player_controlled(true)
	var target := _spawn("FACTION_ENEMY", 1, Vector2(930.0, 500.0), true)
	var expected_damage: int = attacker.get_attack_damage()

	_check(
		attacker.player_attack_at(target.get_position(), [target]),
		"事件测试攻击开始"
	)
	_check(
		_attack_started_ids.has(attacker.unit_id),
		"攻击开始时广播 unit_attack_started"
	)
	_check(_hit_records.is_empty(), "攻击开始时没有 unit_hit")
	_check(_staggered_ids.is_empty(), "攻击开始时没有 unit_staggered")

	_advance_to_hit_frame(attacker)
	var record := _last_hit_record_for(target.unit_id)
	_check(not record.is_empty(), "有效帧广播 unit_hit")
	_check(
		str(record.get("attacker", "")) == attacker.unit_id,
		"unit_hit 携带实际攻击者"
	)
	_check(
		int(record.get("damage", 0)) == expected_damage,
		"unit_hit 的伤害与既有攻击力一致"
	)
	_check(not bool(record.get("killed", true)), "未致命命中标记 killed=false")
	_check(_staggered_ids.has(target.unit_id), "真实伤害后广播 unit_staggered")


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------


func _spawn(
	faction: String,
	side_index: int,
	position: Vector2,
	with_actor: bool,
	mounted: bool = false,
	hp: int = 200
) -> UnitController:
	var unit: UnitData = _units.create_unit(_config, faction)
	unit.max_hp = hp
	unit.current_hp = hp
	unit.attack_interval = 1.0
	unit.is_mounted = mounted
	if mounted:
		unit.equipment["MOUNT"] = "mount_horse_01"

	var state := BattleUnitState.new()
	state.unit_id = unit.unit_id
	state.party_id = "PARTY_TEST"
	state.battle_hp = hp
	state.alive = true
	state.battle_position = position

	var actor: UnitActor = null
	if with_actor:
		actor = UnitActor.new()
		add_child(actor)
		actor.setup(unit, state, side_index == 0)
		# 测试通过 advance_attack_animation 手动推进，关闭自动帧推进。
		actor.set_process(false)
		var human: Node2D = actor.visual.get_human_visual()
		if human != null:
			human.set_process(false)
		var horse: Node2D = actor.visual.get_horse_visual()
		if horse != null:
			horse.set_process(false)

	var controller := UnitController.new()
	controller.setup(
		unit, state, side_index == 0, actor, Rect2(0.0, 0.0, 1200.0, 800.0)
	)
	controller.side_index = side_index
	return controller


## 精确推进到有效帧：前摇结束 + 戳击越过 SPEAR_HIT_FRAME_RATIO。
func _advance_to_hit_frame(controller: UnitController) -> void:
	if controller == null or controller.actor == null:
		return
	controller.actor.advance_attack_animation(HumanVisualScript.SPEAR_WINDUP_TIME)
	controller.actor.advance_attack_animation(
		HumanVisualScript.SPEAR_THRUST_TIME * HumanVisualScript.SPEAR_HIT_FRAME_RATIO + 0.001
	)


func _flash_of(sprite: Sprite2D) -> float:
	if sprite == null:
		return -1.0
	var material := sprite.material as ShaderMaterial
	if material == null:
		return -1.0
	return float(material.get_shader_parameter("flash_amount"))


func _hit_count_for(unit_id: String) -> int:
	var count: int = 0
	for record: Dictionary in _hit_records:
		if str(record.get("unit_id", "")) == unit_id:
			count += 1
	return count


func _last_hit_record_for(unit_id: String) -> Dictionary:
	for i: int in range(_hit_records.size() - 1, -1, -1):
		if str(_hit_records[i].get("unit_id", "")) == unit_id:
			return _hit_records[i]
	return {}


func _reset_events() -> void:
	_attack_started_ids.clear()
	_hit_records.clear()
	_staggered_ids.clear()


func _on_attack_started(unit_id: String, _party_id: String) -> void:
	_attack_started_ids.append(unit_id)


func _on_unit_hit(
	unit_id: String,
	_party_id: String,
	attacker_unit_id: String,
	damage: int,
	killed: bool
) -> void:
	_hit_records.append({
		"unit_id": unit_id,
		"attacker": attacker_unit_id,
		"damage": damage,
		"killed": killed,
	})


func _on_unit_staggered(unit_id: String, _party_id: String, _duration: float) -> void:
	_staggered_ids.append(unit_id)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[melee] OK: %s" % message)
	else:
		_failed = true
		push_error("[melee] FAIL: %s" % message)


func _cleanup() -> void:
	if EventBus.unit_attack_started.is_connected(_on_attack_started):
		EventBus.unit_attack_started.disconnect(_on_attack_started)
	if EventBus.unit_hit.is_connected(_on_unit_hit):
		EventBus.unit_hit.disconnect(_on_unit_hit)
	if EventBus.unit_staggered.is_connected(_on_unit_staggered):
		EventBus.unit_staggered.disconnect(_on_unit_staggered)
