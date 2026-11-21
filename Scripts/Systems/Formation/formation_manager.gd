class_name FormationManager
extends RefCounted
## 编队子系统：只负责定义阵型与计算相对站位，不负责士兵攻击行为。
##
## 局部坐标约定：+X 为队伍前进方向，+Y 为横向。
## 战斗场景负责把相对站位转换为世界坐标并分配给 UnitController。

enum FormationType {
	NONE,
	INFANTRY_LINE,
	INFANTRY_SQUARE,
	ARCHER_LINE,
	CAVALRY_WEDGE,
	DEPTH,
	LOOSE,
}

const LINE_MAX_COLUMNS: int = 5
const LOOSE_MAX_COLUMNS: int = 4
const LOOSE_SPACING_MULTIPLIER: float = 1.5
const LINE_ROW_FACTOR: float = 0.9


## 返回每个单位的目标站位（局部坐标）。
func compute_slots(
	formation_type: FormationType, unit_count: int, spacing: float
) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if unit_count <= 0:
		return result
	var step: float = maxf(spacing, 1.0)

	match formation_type:
		FormationType.INFANTRY_LINE, FormationType.ARCHER_LINE:
			return _grid_slots(unit_count, step, LINE_MAX_COLUMNS, LINE_ROW_FACTOR)
		FormationType.INFANTRY_SQUARE:
			var square_columns: int = maxi(1, ceili(sqrt(float(unit_count))))
			return _grid_slots(unit_count, step, square_columns, 1.0)
		FormationType.CAVALRY_WEDGE:
			# 第一版用前窄后宽的简化纵列，后续可替换为真正的楔形。
			return _grid_slots(unit_count, step, 2, 1.2)
		FormationType.DEPTH:
			for i: int in range(unit_count):
				result.append(Vector2(-float(i) * step, 0.0))
			return result
		FormationType.LOOSE:
			return _grid_slots(
				unit_count, step * LOOSE_SPACING_MULTIPLIER, LOOSE_MAX_COLUMNS, 1.2
			)
		_:
			return result


func formation_display_name(formation_type: FormationType) -> String:
	match formation_type:
		FormationType.INFANTRY_LINE:
			return "横向队形"
		FormationType.INFANTRY_SQUARE:
			return "方阵"
		FormationType.ARCHER_LINE:
			return "远程横队"
		FormationType.CAVALRY_WEDGE:
			return "骑兵纵队"
		FormationType.DEPTH:
			return "纵深队形"
		FormationType.LOOSE:
			return "松散队形"
		_:
			return "无队形"


func _grid_slots(
	unit_count: int, spacing: float, max_columns: int, row_factor: float
) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var columns: int = clampi(max_columns, 1, unit_count)
	for i: int in range(unit_count):
		var column: int = i % columns
		var row: int = i / columns
		var lateral: float = (
			(float(column) - (float(columns) - 1.0) * 0.5) * spacing
		)
		var depth: float = -float(row) * spacing * row_factor
		result.append(Vector2(depth, lateral))
	return result
