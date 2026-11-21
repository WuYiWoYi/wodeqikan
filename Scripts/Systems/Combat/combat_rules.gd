class_name CombatRules
extends RefCounted
## 战斗攻击有效性判断的唯一入口。
##
## 玩家与 AI 使用同一套 360°定向矩形判定：
## - 攻击者中心为矩形起点；
## - 沿攻击方向延伸 attack_range + 身体直径 + WEAPON_FORWARD_BONUS；
## - 横向半宽由 ATTACK_HALF_WIDTH 控制；
## - 只检测攻击者前方，背后的目标永远不被命中。
## 每次攻击最多命中一个目标；目标选择由 UnitController 完成。
##
## 参数使用无类型引用，避免 UnitController <-> CombatRules 的类循环依赖。

const BODY_RADIUS: float = 13.0
## 武器向前的额外有效判定距离（相对旧圆形射程）。
const WEAPON_FORWARD_BONUS: float = 6.0
## 定向矩形横向半宽。
const ATTACK_HALF_WIDTH: float = 22.0


## 定向攻击矩形从前向中心延伸的长度。
static func attack_forward_length(attacker_unit_data: UnitData) -> float:
	if attacker_unit_data == null:
		return 0.0
	return (
		maxf(0.0, attacker_unit_data.attack_range)
		+ BODY_RADIUS * 2.0
		+ WEAPON_FORWARD_BONUS
	)


## 兼容旧调用：AI 接近/测试使用的最大前向距离。
static func attack_center_range(attacker_unit_data: UnitData) -> float:
	return attack_forward_length(attacker_unit_data)


## 两个单位是否敌对。当前以战斗侧区分，友军之间永不敌对。
static func is_hostile(attacker: Variant, target: Variant) -> bool:
	if attacker == null or target == null:
		return false
	return int(attacker.side_index) != int(target.side_index)


## 目标是否位于以 direction 为轴的定向矩形内。
## direction 不必预先归一化；背后（forward < 0）直接排除。
static func is_in_attack_area(
	attacker: Variant, target: Variant, direction: Vector2
) -> bool:
	if attacker == null or target == null:
		return false
	if attacker.unit_data == null or attacker.state == null or target.state == null:
		return false
	if direction.length_squared() < 0.0001:
		return false
	var dir: Vector2 = direction.normalized()
	var to_target: Vector2 = target.get_position() - attacker.get_position()
	var forward: float = to_target.dot(dir)
	if forward < 0.0:
		return false
	var lateral: float = absf(to_target.cross(dir))
	return (
		forward <= attack_forward_length(attacker.unit_data)
		and lateral <= ATTACK_HALF_WIDTH
	)


## 目标是否在“攻击者指向目标”的方向上（AI/兼容入口）。
static func is_in_attack_range(attacker: Variant, target: Variant) -> bool:
	if attacker == null or target == null:
		return false
	var direction: Vector2 = target.get_position() - attacker.get_position()
	if direction.length_squared() < 0.0001:
		direction = Vector2.LEFT
	return is_in_attack_area(attacker, target, direction)


## 统一攻击有效性：存活、敌对、冷却结束、目标在指定方向的矩形内。
## 注意：允许多个攻击者同时攻击同一目标；本判断不维护任何目标级锁。
static func can_attack_with_direction(
	attacker: Variant, target: Variant, direction: Vector2
) -> bool:
	if attacker == null or target == null:
		return false
	if not attacker.is_alive() or not target.is_alive():
		return false
	if not is_hostile(attacker, target):
		return false
	if float(attacker.get_attack_cooldown()) > 0.0:
		return false
	return is_in_attack_area(attacker, target, direction)


## 使用“攻击者→目标”方向的有效性判断（AI/旧接口）。
static func can_attack(attacker: Variant, target: Variant) -> bool:
	if attacker == null or target == null:
		return false
	var direction: Vector2 = target.get_position() - attacker.get_position()
	return can_attack_with_direction(attacker, target, direction)


## 单次有效攻击的伤害。骑乘移动加成由 StatCalculator 统一提供。
static func compute_attack_damage(attacker: Variant) -> int:
	if attacker == null or attacker.unit_data == null:
		return 0
	return maxi(
		1,
		StatCalculator.compute_effective_attack(
			attacker.unit_data, bool(attacker.is_moving())
		)
	)
