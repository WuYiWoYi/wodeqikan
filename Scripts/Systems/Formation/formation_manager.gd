class_name FormationManager
extends RefCounted
## 编队子系统：只负责定义阵型与计算站位，不负责士兵攻击行为。

enum FormationType {
	NONE,
	INFANTRY_LINE,
	INFANTRY_SQUARE,
	ARCHER_LINE,
	CAVALRY_WEDGE,
}


## 返回每个单位的目标站位（相对编队中心）。
func compute_slots(
	_formation_type: FormationType, _unit_count: int, _spacing: float
) -> Array[Vector2]:
	# TODO(阶段6)：实现方阵、线阵、弓手线与骑兵楔形站位。
	return []
