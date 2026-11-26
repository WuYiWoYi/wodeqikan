class_name UnitController
extends RefCounted
## 单个士兵的战斗行为控制：AI、玩家控制、移动、索敌、攻击、受伤与死亡。
##
## 属性全部来自 UnitData；战斗位置与 HP 写入 BattleUnitState。
## 本类不读取或修改 UnitData.current_hp，结算由 BattleManager 统一完成。
## 队形槽位与邻居缓存由 BattleScene 周期性写入，避免每个单位每帧扫描全场。
##
## 攻击规则：
## - 攻击冷却、当前目标、移动状态都属于攻击者自身，不存在目标级全局锁；
## - 任意数量的攻击者可以同时攻击同一目标，伤害逐次独立结算；
## - 玩家与 AI 都通过 CombatRules 判断射程、敌对、冷却与目标有效性。

const RETARGET_INTERVAL: float = 0.3
const ARRIVAL_RADIUS: float = 4.0
const AUTO_ACQUIRE_RANGE: float = 1000.0
## 友军间距略大于实体最小间距，形成前后层次；敌军之间只避免严重重叠。
const SEPARATION_RADIUS: float = 44.0
const ENEMY_SEPARATION_RADIUS: float = 34.0
const SEPARATION_STRENGTH: float = 0.75
const PLAYER_SEPARATION_STRENGTH: float = 0.3
const ENEMY_SEPARATION_MULTIPLIER: float = 0.5
const FORMATION_SLOT_EPSILON: float = 6.0
## 目标分配：同一敌人已被多名友军攻击时，后来者倾向于选择其他目标。
const TARGET_CLAIM_PENALTY: float = 90.0
## 接近目标时，超过该距离才参考队形槽位方向；近距离按当前包围角度接近，
## 避免后排单位绕到目标另一侧、与前排挤在同一点。
const CLOSE_APPROACH_RANGE: float = 140.0
const TARGET_APPROACH_LATERAL: float = 10.0

## 远程单位行为参数。
## 敌人进入该距离后优先后撤，避免弓箭手被近战单位贴脸。
const RANGED_MIN_RANGE: float = 110.0
## 超出射程时，向敌人接近到射程的这个比例处，而不是一直贴近。
const RANGED_STANDOFF_FACTOR: float = 0.82
## 没有 WeaponPivot 时的箭矢发射高度回退值。
const RANGED_FALLBACK_LAUNCH_HEIGHT: float = 20.0

## 战斗场景移动速度系数；只影响战斗，不影响大地图 PartyData.movement_speed。
## 步兵保持原值：民兵 60→36、职业步兵 55→33、玩家角色 75→45。
## 骑乘单位使用独立战斗系数，放大坐骑的机动优势：
## 民兵 85→71.4、职业步兵 80→67.2、玩家角色 100→84。
const BATTLE_MOVE_SPEED_MULTIPLIER: float = 0.6
const BATTLE_MOUNTED_MOVE_SPEED_MULTIPLIER: float = 0.84

## 实体碰撞的最后空间约束：单位中心间距小于该值时互相推开。
## 局部避让（Separation）仍负责主动移动调整。
const MIN_BODY_DISTANCE: float = 28.0

## 战斗经验：每次对敌方造成有效伤害 +1，完成击杀额外 +10。
## 按“有效伤害事件”计数，不按伤害数值；0 伤害/未命中不发放。
const EXP_PER_DAMAGE: int = 1
const EXP_PER_KILL: int = 10

## 受击僵直：统一时长，连续受击只刷新到该值，不做加法叠加。
## 不按武器/兵种/等级区分，后续平衡调整只需改这里。
const STAGGER_DURATION: float = 0.24
## 攻击动画有效帧事件丢失时的安全上限；超过该时间取消待结算攻击，
## 避免动画被重建/中断后永久挂起。正常风车+戳击约 0.28 秒。
const PENDING_ATTACK_TIMEOUT: float = 0.6

## 使用 preload 常量而不是全局类名，保证新脚本首次导入前也能通过编译。
const CombatRulesScript = preload("res://Scripts/Systems/Combat/combat_rules.gd")

## AI 对外可观察的行为状态；复用同一套 tick 流程，不另建状态机。
enum AIState {
	SEEK,
	APPROACH,
	ATTACK,
	STAGGERED,
}

var unit_id: String = ""
var party_id: String = ""
var side_index: int = 0
var is_player_side: bool = false
var is_player_controlled: bool = false
var actor: UnitActor = null
var unit_data: UnitData = null
var state: BattleUnitState = null
var battle_bounds: Rect2 = Rect2()

## 由 BattleScene 周期刷新。
var formation_slot: Vector2 = Vector2.ZERO
var has_formation_slot: bool = false
var nearby_controllers: Array[UnitController] = []
## 由 BattleScene 周期刷新：本战斗侧每个敌人当前被多少友军选为目标。
var target_claim_counts: Dictionary = {}
## 由 BattleScene 注入；远程单位发射箭矢的唯一入口。
var _projectile_manager: Variant = null
## 由 BattleScene 注入：(attacker_unit_id, exp_amount) -> void。
## 未注入时不发放经验（纯数据测试/无世界上下文场景）。
var experience_callback: Callable = Callable()

var _attack_cooldown: float = 0.0
var _retarget_timer: float = 0.0
var _target: UnitController = null
var _manual_move_target := Vector2.ZERO
var _has_manual_move: bool = false
var _alive: bool = true
var _is_moving: bool = false
var _ai_state: AIState = AIState.SEEK
var _last_attack_direction: Vector2 = Vector2.LEFT
var _last_attack_target_id: String = ""

## 受击僵直剩余时间；连续受击刷新到 STAGGER_DURATION，不做叠加。
var _stagger_remaining: float = 0.0
## 近战攻击的有效帧待结算状态。攻击开始时锁存目标/方向/伤害，
## 动画到达有效帧后重新校验并结算；被打断/死亡时取消。
var _has_pending_attack: bool = false
var _pending_attack_target: UnitController = null
var _pending_attack_direction: Vector2 = Vector2.ZERO
var _pending_attack_damage: int = 0
var _pending_attack_elapsed: float = 0.0


func setup(
	data: UnitData,
	battle_state: BattleUnitState,
	player_side: bool,
	actor_node: UnitActor,
	bounds: Rect2
) -> void:
	unit_data = data
	state = battle_state
	is_player_side = player_side
	actor = actor_node
	battle_bounds = bounds
	unit_id = state.unit_id
	party_id = state.party_id
	_alive = state.alive and state.battle_hp > 0
	# 有表现节点时由动画有效帧事件触发伤害；纯数据场景没有动画，
	# 攻击开始后立即走同一条结算路径（_start_melee_attack 内回退）。
	if actor != null and is_instance_valid(actor):
		actor.attack_hit_callback = Callable(self, "_on_attack_hit_frame")


func is_alive() -> bool:
	return (
		_alive
		and state != null
		and state.alive
		and state.battle_hp > 0
	)


func get_position() -> Vector2:
	return state.battle_position if state != null else Vector2.ZERO


func get_attack_cooldown() -> float:
	return _attack_cooldown


func is_moving() -> bool:
	return _is_moving


func get_ai_state() -> AIState:
	return _ai_state


func get_target_unit_id() -> String:
	return _target.unit_id if _target != null else ""


## 受击僵直是否生效；死亡单位不再视为僵直（死亡优先级更高）。
func is_staggered() -> bool:
	return is_alive() and _stagger_remaining > 0.0


func get_stagger_remaining() -> float:
	if not is_alive():
		return 0.0
	return _stagger_remaining


## 是否存在等待有效帧结算的近战攻击；供调试与测试观察。
func has_pending_attack() -> bool:
	return _has_pending_attack


func get_pending_attack_target_id() -> String:
	if not _has_pending_attack or _pending_attack_target == null:
		return ""
	return _pending_attack_target.unit_id


func set_target_claim_counts(counts: Dictionary) -> void:
	target_claim_counts = counts


func set_projectile_manager(manager: Variant) -> void:
	_projectile_manager = manager


## 当前武器是否为远程武器。来源是 UnitData 的装备派生值，不是 config 名称。
func is_ranged_unit() -> bool:
	return unit_data != null and unit_data.is_ranged_attacker()


# ---------------------------------------------------------------------------
# 统一攻击判断
# ---------------------------------------------------------------------------


## 攻击矩形的前向长度（含身体尺寸与武器向前加成）。
func get_attack_center_range() -> float:
	return CombatRulesScript.attack_center_range(unit_data)


## 战斗场景内的实际移动速度系数。步兵与骑乘各有一个集中配置值，
## 不在装备或世界地图层额外叠加倍率。
func get_battle_speed_multiplier() -> float:
	if unit_data != null and unit_data.is_mounted:
		return BATTLE_MOUNTED_MOVE_SPEED_MULTIPLIER
	return BATTLE_MOVE_SPEED_MULTIPLIER


func get_battle_move_speed() -> float:
	if unit_data == null:
		return 0.0
	return unit_data.move_speed * get_battle_speed_multiplier()


func is_target_in_attack_range(target: UnitController) -> bool:
	return CombatRulesScript.is_in_attack_range(self, target)


func can_attack_target(target: UnitController) -> bool:
	return CombatRulesScript.can_attack(self, target)


func get_ranged_attack_range() -> float:
	return CombatRulesScript.ranged_attack_range(unit_data)


func is_target_in_ranged_range(target: UnitController) -> bool:
	return CombatRulesScript.is_in_ranged_range(self, target)


func can_ranged_attack_target(target: UnitController) -> bool:
	return CombatRulesScript.can_ranged_attack(self, target)


## 箭矢起点：地面坐标 + 弓枢轴的视觉高度。高度只用于表现，不改变地面坐标。
func get_ranged_launch_info() -> Dictionary:
	var ground: Vector2 = get_position()
	var height: float = RANGED_FALLBACK_LAUNCH_HEIGHT
	if actor != null and is_instance_valid(actor):
		var bow_position: Vector2 = actor.get_weapon_pivot_global_position()
		if is_finite(bow_position.x) and is_finite(bow_position.y):
			height = clampf(ground.y - bow_position.y, 8.0, 56.0)
	return {"ground": ground, "height": height}


func get_last_attack_direction() -> Vector2:
	return _last_attack_direction


func get_last_attack_target_id() -> String:
	return _last_attack_target_id


## 本次攻击的伤害（基础攻击 + 骑乘移动加成）。
func get_attack_damage() -> int:
	return CombatRulesScript.compute_attack_damage(self)


func has_move_command() -> bool:
	return _has_manual_move


func set_player_controlled(value: bool) -> void:
	is_player_controlled = value
	_target = null
	_has_manual_move = false
	_retarget_timer = 0.0
	_is_moving = false
	_ai_state = AIState.SEEK


func set_formation_slot(slot: Vector2) -> void:
	if has_formation_slot and formation_slot.distance_to(slot) < FORMATION_SLOT_EPSILON:
		return
	formation_slot = slot
	has_formation_slot = true


## 兼容旧测试/调试的整队移动命令；会设置手动移动目标。
func command_move(target: Vector2) -> void:
	if not is_alive():
		return
	_manual_move_target = _clamp_to_bounds(target)
	_has_manual_move = true
	_target = null


## AI 行为：搜索/接近/攻击。
## 进入有效射程后停止移动并攻击；目标失效或离开射程后重新追击。
func tick(delta: float, enemies: Array[UnitController]) -> void:
	if is_player_controlled:
		return
	if not is_alive():
		return
	if state.battle_hp <= 0:
		_die()
		return

	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_tick_pending_attack(delta)
	_is_moving = false
	_resolve_spatial_overlap()

	# 受击僵直：短暂停止正常移动与索敌/攻击，保留当前目标和手动命令。
	if _stagger_remaining > 0.0:
		_stagger_remaining = maxf(0.0, _stagger_remaining - delta)
		_ai_state = AIState.STAGGERED
		if _stagger_remaining <= 0.0:
			_ai_state = AIState.SEEK
		return

	if _has_manual_move:
		_ai_state = AIState.APPROACH
		if _move_toward(_manual_move_target, delta):
			_has_manual_move = false
		return

	# 远程单位使用独立的射程/站位/发射流程，但冷却、索敌和伤害入口与近战一致。
	if is_ranged_unit():
		_tick_ranged(delta, enemies)
		return

	_retarget_timer -= delta
	if _target == null or not _target.is_alive():
		_target = _find_best_enemy(enemies)
		_retarget_timer = RETARGET_INTERVAL
	elif _retarget_timer <= 0.0:
		# 已经在射程内时不换目标，避免攻击前一刻被重新索敌打断。
		if not is_target_in_attack_range(_target):
			_target = _find_best_enemy(enemies)
		_retarget_timer = RETARGET_INTERVAL

	if _target == null:
		_ai_state = AIState.SEEK
		if has_formation_slot:
			_move_toward(formation_slot, delta)
		return

	if can_attack_target(_target):
		_ai_state = AIState.ATTACK
		_execute_attack(_target)
		return

	if is_target_in_attack_range(_target):
		# 冷却未结束：保持攻击位置，不再向目标中心挤压。
		_ai_state = AIState.ATTACK
		_face_towards(_target.get_position())
		return

	# 不在射程内：沿目标外围的进攻点推进，避免全部挤向同一个坐标。
	_ai_state = AIState.APPROACH
	_move_toward(_attack_approach_position(_target), delta)


## 弓箭手 AI：射程内站定射击，射程外接近，敌人贴脸时后撤。
## 每次射击只把目标“当前地面坐标”交给箭矢；飞行期间不追踪目标。
func _tick_ranged(delta: float, enemies: Array[UnitController]) -> void:
	_retarget_timer -= delta
	if _target == null or not _target.is_alive():
		_target = _find_best_enemy(enemies)
		_retarget_timer = RETARGET_INTERVAL
	elif _retarget_timer <= 0.0:
		# 已在射程内时不换目标，避免射击前一刻被重新索敌打断。
		if not is_target_in_ranged_range(_target):
			_target = _find_best_enemy(enemies)
		_retarget_timer = RETARGET_INTERVAL

	if _target == null:
		_ai_state = AIState.SEEK
		if has_formation_slot:
			_move_toward(formation_slot, delta)
		return

	var target_position: Vector2 = _target.get_position()
	var distance: float = state.battle_position.distance_to(target_position)
	var attack_range: float = get_ranged_attack_range()
	_face_towards(target_position)

	if distance <= attack_range:
		_ai_state = AIState.ATTACK
		if _attack_cooldown <= 0.0:
			_fire_ranged_at(target_position, enemies)
	else:
		_ai_state = AIState.APPROACH
		_move_toward(_ranged_standoff_position(target_position), delta)

	# 敌人贴脸：即使刚完成一次射击也优先拉开距离，避免弓箭手原地近战。
	if distance < RANGED_MIN_RANGE:
		var away: Vector2 = state.battle_position - target_position
		if away.length_squared() < 0.0001:
			away = Vector2.LEFT
		_move_toward_direction(
			away.normalized(), delta, PLAYER_SEPARATION_STRENGTH
		)
		_face_towards(target_position)
		_ai_state = AIState.APPROACH


## 射程外时的接近点：停在射程的 82% 处，优先沿队形槽位方向展开。
func _ranged_standoff_position(target_position: Vector2) -> Vector2:
	var desired_distance: float = maxf(
		RANGED_MIN_RANGE + 10.0, get_ranged_attack_range() * RANGED_STANDOFF_FACTOR
	)
	var direction_from_target: Vector2 = state.battle_position - target_position
	if has_formation_slot:
		var slot_direction: Vector2 = formation_slot - target_position
		if slot_direction.length_squared() > 1.0:
			direction_from_target = slot_direction
	if direction_from_target.length_squared() <= 0.0001:
		direction_from_target = Vector2.LEFT
	return target_position + direction_from_target.normalized() * desired_distance


## 玩家控制：WASD 方向移动；direction 由 BattleScene 归一化。
func player_tick(delta: float, direction: Vector2) -> void:
	if not is_player_controlled or not is_alive():
		return
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_tick_pending_attack(delta)
	_is_moving = false
	_resolve_spatial_overlap()

	# 受击僵直期间不响应移动与手动移动命令；输入不会被缓存，结束需重新按键。
	if _stagger_remaining > 0.0:
		_stagger_remaining = maxf(0.0, _stagger_remaining - delta)
		_ai_state = AIState.STAGGERED
		if _stagger_remaining <= 0.0:
			_ai_state = AIState.SEEK
		return

	if direction.length_squared() > 0.0001:
		_has_manual_move = false
		_target = null
		_move_toward_direction(
			direction.normalized(), delta, PLAYER_SEPARATION_STRENGTH
		)
		return

	# 兼容整队命令/旧测试：无玩家方向输入时执行手动移动。
	if _has_manual_move:
		if _move_toward(_manual_move_target, delta):
			_has_manual_move = false


## 玩家左键攻击。
## 鼠标世界坐标决定 360°攻击方向；无论是否命中，都会播放完整攻击动画并进入冷却。
## 只选择该方向矩形内的一个敌人造成伤害；没有敌人时只播放空挥动作。
## 返回值表示本次攻击动作是否成功释放（不是是否命中）。
func player_attack_at(
	target_position: Vector2, enemies: Array[UnitController]
) -> bool:
	if not is_player_controlled or not is_alive():
		return false
	# 僵直期间不能启动新的攻击动作。
	if is_staggered():
		return false
	if _attack_cooldown > 0.0:
		return false

	# 玩家弓箭：鼠标世界坐标就是本次射击的固定地面目标，不在这里挑选/锁定敌人。
	# AI 弓箭手也走同一个 _fire_ranged_at 入口。
	if is_ranged_unit():
		return _fire_ranged_at(target_position, enemies)

	var direction: Vector2 = target_position - state.battle_position
	if direction.length_squared() < 0.0001:
		direction = Vector2.LEFT
	direction = direction.normalized()

	var hit_target := _pick_player_attack_target(target_position, direction, enemies)
	if hit_target != null:
		return _execute_attack(hit_target, direction)

	# 空挥：没有有效目标也正常出手。伤害为 0，但动画与冷却完整生效。
	_start_free_attack(direction)
	return true


## 结算一次真实伤害。source 是实际攻击者，用于发放战斗经验；
## hit_direction 为攻击者→受击者的命中方向（可省略，回退为双方位置差）。
## 目标已经死亡时不再重复扣血或重复判定击杀。
## 受击白闪/受击动作/僵直只在本函数确认实际扣血后触发。
func apply_damage(
	amount: int,
	source: UnitController = null,
	hit_direction: Vector2 = Vector2.ZERO
) -> void:
	if not is_alive():
		return
	var applied: int = maxi(0, amount)
	if applied <= 0:
		return
	state.battle_hp = maxi(0, state.battle_hp - applied)
	var killed: bool = state.battle_hp <= 0
	if source != null and source != self:
		source._grant_damage_experience(killed)

	var attacker_id: String = source.unit_id if source != null else ""
	EventBus.unit_hit.emit(unit_id, party_id, attacker_id, applied, killed)
	if killed:
		# 死亡优先级高于受击状态：不进入僵直/受击动作流程。
		_die()
		return

	var resolved_direction: Vector2 = hit_direction
	if resolved_direction.length_squared() < 0.0001 and source != null:
		resolved_direction = state.battle_position - source.get_position()
	_begin_stagger(resolved_direction)


## 给攻击者发放伤害/击杀经验；同一目标的死亡只会在 HP 首次归零时判定一次。
func _grant_damage_experience(killed: bool) -> void:
	if not experience_callback.is_valid():
		return
	var amount: int = EXP_PER_DAMAGE + (EXP_PER_KILL if killed else 0)
	experience_callback.call(unit_id, amount)


## 进入/刷新受击僵直。连续受击只把计时重置为 STAGGER_DURATION，不累加；
## 保留当前战斗目标与手动移动命令，僵直结束后继续原有行为。
func _begin_stagger(hit_direction: Vector2) -> void:
	_stagger_remaining = STAGGER_DURATION
	# 受击打断尚未到达有效帧的攻击动作，表示层同时取消攻击姿态。
	_cancel_pending_attack()
	_is_moving = false
	_ai_state = AIState.STAGGERED
	if actor != null and is_instance_valid(actor):
		actor.play_hit_feedback(hit_direction)
	EventBus.unit_staggered.emit(unit_id, party_id, STAGGER_DURATION)


## 动画有效帧回调：动画层只负责发出事件，伤害结算仍由本控制器完成。
func _on_attack_hit_frame() -> void:
	_resolve_pending_attack()


## 在有效帧结算一次近战攻击。目标可能已经移动/死亡，因此必须重新校验现有规则；
## 校验不通过则本次攻击落空，不触发任何受击反馈。
func _resolve_pending_attack() -> bool:
	if not _has_pending_attack:
		return false
	var target: UnitController = _pending_attack_target
	var direction: Vector2 = _pending_attack_direction
	var damage: int = _pending_attack_damage
	# 先清除待结算状态，保证同一戳击最多结算一次，后续中断不会撤销已成立伤害。
	_cancel_pending_attack()
	if target == null or not CombatRulesScript.is_attack_frame_valid(
		self, target, direction
	):
		return false
	_last_attack_target_id = target.unit_id
	target.apply_damage(damage, self, direction)
	return true


## 攻击动画被重建/中断时的安全取消；正常有效帧会在此之前清除待结算状态。
func _tick_pending_attack(delta: float) -> void:
	if not _has_pending_attack:
		return
	_pending_attack_elapsed += maxf(0.0, delta)
	if actor == null or not is_instance_valid(actor) \
			or not actor.is_attack_animating():
		_cancel_pending_attack()
		return
	if _pending_attack_elapsed >= PENDING_ATTACK_TIMEOUT:
		_cancel_pending_attack()


func _cancel_pending_attack() -> void:
	_has_pending_attack = false
	_pending_attack_target = null
	_pending_attack_direction = Vector2.ZERO
	_pending_attack_damage = 0
	_pending_attack_elapsed = 0.0


func _die() -> void:
	state.battle_hp = 0
	state.alive = false
	_alive = false
	is_player_controlled = false
	_target = null
	_has_manual_move = false
	_is_moving = false
	_ai_state = AIState.SEEK
	_stagger_remaining = 0.0
	# 死亡时取消尚未到达有效帧的攻击，避免死亡后补结算伤害。
	_cancel_pending_attack()


# ---------------------------------------------------------------------------
# 攻击执行
# ---------------------------------------------------------------------------


## 玩家点击选目标：只在方向矩形内筛选，优先取离点击位置最近的有效敌人。
func _pick_player_attack_target(
	target_position: Vector2, direction: Vector2, enemies: Array[UnitController]
) -> UnitController:
	var best_target: UnitController = null
	var best_click_distance: float = INF
	var best_forward_distance: float = INF
	for enemy: UnitController in enemies:
		if not CombatRulesScript.can_attack_with_direction(self, enemy, direction):
			continue
		var click_distance: float = enemy.get_position().distance_to(target_position)
		var forward_distance: float = (
			enemy.get_position() - state.battle_position
		).dot(direction)
		var better_click: bool = click_distance < best_click_distance - 0.01
		var tied_click: bool = is_equal_approx(click_distance, best_click_distance)
		if better_click or (tied_click and forward_distance < best_forward_distance):
			best_target = enemy
			best_click_distance = click_distance
			best_forward_distance = forward_distance
	return best_target


## 一次攻击只命中一个目标。攻击开始时锁定方向/目标/伤害与冷却，
## 实际伤害在动画有效帧回调中重新校验后结算。
func _execute_attack(target: UnitController, direction: Vector2 = Vector2.ZERO) -> bool:
	if target == null:
		return false
	var attack_direction: Vector2 = direction
	if attack_direction.length_squared() < 0.0001:
		attack_direction = target.get_position() - state.battle_position
	if attack_direction.length_squared() < 0.0001:
		attack_direction = Vector2.LEFT
	attack_direction = attack_direction.normalized()

	if not CombatRulesScript.can_attack_with_direction(self, target, attack_direction):
		return false

	_start_melee_attack(target, attack_direction)
	return true


## 开始一次有目标的近战攻击：锁存目标/方向/伤害，进入冷却并播放动画。
## 动画有效帧到达前被打断（受击/死亡）则不结算；到达后伤害立即成立且不可撤销。
func _start_melee_attack(target: UnitController, direction: Vector2) -> void:
	_cancel_pending_attack()
	_face_attack_direction(direction)
	_attack_cooldown = maxf(0.05, unit_data.attack_interval)
	_last_attack_direction = direction
	_last_attack_target_id = ""
	_has_pending_attack = true
	_pending_attack_target = target
	_pending_attack_direction = direction
	# 伤害在出手瞬间按当时状态计算（含骑乘移动加成），与既有数值规则一致。
	_pending_attack_damage = get_attack_damage()
	_pending_attack_elapsed = 0.0
	EventBus.unit_attack_started.emit(unit_id, party_id)
	if not _play_attack(direction):
		# 没有动画可等待时走同一条结算路径，保持纯数据场景行为。
		_resolve_pending_attack()


## 空挥：播放完整攻击动作与冷却，但不创建可结算伤害。
func _start_free_attack(direction: Vector2) -> void:
	_cancel_pending_attack()
	_face_attack_direction(direction)
	_attack_cooldown = maxf(0.05, unit_data.attack_interval)
	_last_attack_direction = direction
	_last_attack_target_id = ""
	EventBus.unit_attack_started.emit(unit_id, party_id)
	_play_attack(direction)


## 玩家与 AI 共用的唯一弓箭发射入口。
## 无论箭矢最终是否命中，成功发射即进入攻击冷却；冷却从发射瞬间开始。
func _fire_ranged_at(
	ground_target: Vector2, enemies: Array[UnitController]
) -> bool:
	if not is_alive() or unit_data == null or not is_ranged_unit():
		return false
	if _attack_cooldown > 0.0:
		return false

	var direction: Vector2 = ground_target - state.battle_position
	if direction.length_squared() < 0.0001:
		direction = Vector2.LEFT
	direction = direction.normalized()
	_face_attack_direction(direction)

	var launched: bool = false
	if _projectile_manager != null:
		launched = bool(_projectile_manager.spawn_arrow(
			self,
			ground_target,
			enemies,
			get_attack_damage(),
			unit_data.projectile_texture_path,
			unit_data.projectile_speed,
			unit_data.projectile_arc_height
		))
	# 没有发射物管理器（例如纯数据测试）时仍完成一次攻击动作与冷却，
	# 但不伪造命中；正式战斗始终由 BattleScene 注入 ProjectileManager。
	_attack_cooldown = maxf(0.05, unit_data.attack_interval)
	_last_attack_direction = direction
	_last_attack_target_id = (
		_target.unit_id if _target != null and _target.is_alive() else ""
	)
	_play_ranged_attack(direction)
	return launched or _projectile_manager == null


## 目标外围的进攻点：保持攻击距离，并从自己队形槽位所在方向靠近，
## 让多名单位自然分散在目标周围而不是全部挤到中心点。
func _attack_approach_position(target: UnitController) -> Vector2:
	var target_position := target.get_position()
	var desired_distance: float = maxf(
		ARRIVAL_RADIUS, get_attack_center_range() - ARRIVAL_RADIUS
	)
	var direction_from_target := state.battle_position - target_position
	var distance_to_target: float = direction_from_target.length()
	# 远距离按队形槽位方向接近；进入近距离后按自身当前包围角度接近，
	# 让同一目标周围的士兵保持分散，而不是全部换到同一条槽位线。
	if has_formation_slot and distance_to_target > CLOSE_APPROACH_RANGE:
		var slot_direction := formation_slot - target_position
		if slot_direction.length_squared() > 1.0:
			direction_from_target = slot_direction
	if direction_from_target.length_squared() <= 0.0001:
		direction_from_target = Vector2.LEFT
	var approach_direction := direction_from_target.normalized()
	# 同向接近时给不同单位一个很小的切向偏移，避免多个单位落到同一点。
	var tangent := Vector2(-approach_direction.y, approach_direction.x)
	var lateral: float = float(posmod(unit_id.hash(), 21) - 10) \
		/ 10.0 * TARGET_APPROACH_LATERAL
	return target_position + approach_direction * desired_distance + tangent * lateral


# ---------------------------------------------------------------------------
# 移动
# ---------------------------------------------------------------------------


## 返回是否已到达目标点。
func _move_toward(
	target: Vector2, delta: float, separation_strength: float = SEPARATION_STRENGTH
) -> bool:
	var to_target := target - state.battle_position
	var distance := to_target.length()
	if distance <= ARRIVAL_RADIUS:
		return true
	var desired := to_target.normalized()
	var separation := _compute_separation()
	if separation.length_squared() > 0.0001:
		desired = (desired + separation * separation_strength).normalized()
	_move_toward_direction(desired, delta, 0.0, distance)
	return false


func _move_toward_direction(
	direction: Vector2, delta: float, separation_strength: float,
	max_distance: float = INF
) -> void:
	if direction.length_squared() <= 0.0001:
		return
	var move_direction := direction.normalized()
	if separation_strength > 0.0:
		var separation := _compute_separation()
		if separation.length_squared() > 0.0001:
			move_direction = (
				move_direction + separation * separation_strength
			).normalized()
	var step: float = minf(
		unit_data.move_speed * get_battle_speed_multiplier() * delta, max_distance
	)
	if step <= 0.0:
		return
	var previous_position: Vector2 = state.battle_position
	state.battle_position = _clamp_to_bounds(
		state.battle_position + move_direction * step
	)
	# 被战场边界或极端夹取挡住时不算实际移动，避免白嫖骑乘移动加成。
	_is_moving = previous_position.distance_squared_to(state.battle_position) > 0.0001
	_face_towards(state.battle_position + move_direction)


func _compute_separation() -> Vector2:
	if nearby_controllers.is_empty():
		return Vector2.ZERO
	var push := Vector2.ZERO
	for other: UnitController in nearby_controllers:
		if other == null or other == self or not other.is_alive():
			continue
		var friendly: bool = other.side_index == side_index
		var radius: float = SEPARATION_RADIUS if friendly else ENEMY_SEPARATION_RADIUS
		var offset := state.battle_position - other.get_position()
		var distance := offset.length()
		if distance >= radius:
			continue
		if distance <= 0.001:
			offset = Vector2(0.5, 0.5)
			distance = offset.length()
		var weight: float = 1.0 - distance / radius
		var side_multiplier: float = 1.0 if friendly else ENEMY_SEPARATION_MULTIPLIER
		push += offset.normalized() * weight * side_multiplier
	return push.limit_length(1.0)


func _face_towards(target: Vector2) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	# 只在挥动/刺出阶段锁定朝向；攻击后的长矛保持姿态不阻止移动转身。
	if actor.is_attack_pose_locked():
		return
	actor.set_facing(target.x - state.battle_position.x)


## 攻击方向决定人物左右朝向；竖直攻击保持当前朝向。
func _face_attack_direction(direction: Vector2) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	if absf(direction.x) > 0.01:
		actor.set_facing(direction.x)


func _play_attack(direction: Vector2) -> bool:
	if actor != null and is_instance_valid(actor):
		return bool(actor.play_attack(direction))
	return false


func _play_ranged_attack(direction: Vector2) -> void:
	if actor != null and is_instance_valid(actor):
		actor.play_ranged_attack(direction)


## 实体碰撞的最后空间约束：与附近存活单位保持最小中心间距。
## 与局部避让协同，不改变伤害/攻击判定。
func _resolve_spatial_overlap() -> void:
	if nearby_controllers.is_empty():
		return
	for _iteration: int in range(2):
		var moved_any: bool = false
		for other: UnitController in nearby_controllers:
			if other == null or other == self or not other.is_alive():
				continue
			var offset: Vector2 = state.battle_position - other.get_position()
			var distance: float = offset.length()
			if distance >= MIN_BODY_DISTANCE:
				continue
			if distance <= 0.001:
				offset = Vector2.RIGHT if unit_id > other.unit_id else Vector2.LEFT
				distance = 1.0
			var push: float = (MIN_BODY_DISTANCE - distance) * 0.5
			state.battle_position = _clamp_to_bounds(
				state.battle_position + offset.normalized() * push
			)
			moved_any = true
		if not moved_any:
			break


## 目标评分：距离 + 已被友军占用惩罚。允许多名士兵攻击同一敌人，
## 但当附近存在其他合适目标时，后来者会自然分流，避免全体追同一个点。
func _find_best_enemy(enemies: Array[UnitController]) -> UnitController:
	var best: UnitController = null
	var best_score: float = INF
	for enemy: UnitController in enemies:
		if enemy == null or not enemy.is_alive():
			continue
		var distance := state.battle_position.distance_to(enemy.get_position())
		if distance > AUTO_ACQUIRE_RANGE:
			continue
		var claim_count: int = int(target_claim_counts.get(enemy.unit_id, 0))
		# 自己当前目标不计入“其他友军占用”，减少无意义的来回切换。
		if _target != null and _target.unit_id == enemy.unit_id:
			claim_count = maxi(0, claim_count - 1)
		var score: float = distance + float(claim_count) * TARGET_CLAIM_PENALTY
		if score < best_score:
			best_score = score
			best = enemy
	return best


func _clamp_to_bounds(position: Vector2) -> Vector2:
	if battle_bounds.size == Vector2.ZERO:
		return position
	var clamped := position
	clamped.x = clampf(clamped.x, battle_bounds.position.x, battle_bounds.end.x)
	clamped.y = clampf(clamped.y, battle_bounds.position.y, battle_bounds.end.y)
	return clamped
