class_name SettlementIcon
extends Node2D
## 大地图地点图标。只读取 SettlementData，不修改权威数据。
##
## 村庄与城堡保留原有建筑绘制；家族徽章与名称属于独立屏幕 UI
## （SettlementNameTag），不在世界层绘制，也不随相机缩放改变尺寸。

## 地点名称组合位于原有美术正上方时的屏幕锚点半径（世界像素）。
const VILLAGE_NAME_ANCHOR_RADIUS: float = 28.0
const CASTLE_NAME_ANCHOR_RADIUS: float = 40.0
const TOWN_NAME_ANCHOR_RADIUS: float = 44.0
## 鼠标悬浮白色描边：略粗，沿建筑原有几何边缘绘制在填充层之下。
const HOVER_OUTLINE_WIDTH: float = 5.0
const HOVER_OUTLINE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.95)

var settlement: SettlementData = null
var _hovered: bool = false


func setup(data: SettlementData) -> void:
	settlement = data
	position = data.world_position if data != null else Vector2.ZERO
	queue_redraw()


## 仅切换悬浮白色描边；不改变建筑几何、名称、徽章或点击区域。
func set_hovered(value: bool) -> void:
	if _hovered == value:
		return
	_hovered = value
	queue_redraw()


func is_hovered() -> bool:
	return _hovered


## 名称层使用：返回原有建筑顶部到名称组合底部的视觉半径。
static func get_name_anchor_radius(
	settlement_type: SettlementData.SettlementType
) -> float:
	if settlement_type == SettlementData.SettlementType.CASTLE:
		return CASTLE_NAME_ANCHOR_RADIUS
	if settlement_type == SettlementData.SettlementType.TOWN:
		return TOWN_NAME_ANCHOR_RADIUS
	return VILLAGE_NAME_ANCHOR_RADIUS


func _draw() -> void:
	if settlement == null:
		return

	draw_circle(Vector2(0.0, 8.0), 15.0, Color(0.0, 0.0, 0.0, 0.22))
	# 先画更粗的白色描边，再由建筑填充覆盖内侧一半，留下轮廓外侧的白色光晕。
	if _hovered:
		_draw_hover_outline()
	match settlement.settlement_type:
		SettlementData.SettlementType.CASTLE:
			_draw_castle()
		SettlementData.SettlementType.TOWN:
			_draw_town()
		_:
			_draw_village()


## 与下方建筑绘制使用同一套几何；只描边不填充。
func _draw_hover_outline() -> void:
	match settlement.settlement_type:
		SettlementData.SettlementType.CASTLE:
			_outline_rect(Rect2(-20.0, -10.0, 40.0, 24.0))
			_outline_rect(Rect2(-24.0, -24.0, 10.0, 16.0))
			_outline_rect(Rect2(14.0, -24.0, 10.0, 16.0))
		SettlementData.SettlementType.TOWN:
			_outline_rect(Rect2(-24.0, -8.0, 48.0, 22.0))
			_outline_rect(Rect2(-31.0, -18.0, 7.0, 14.0))
			_outline_rect(Rect2(24.0, -18.0, 7.0, 14.0))
			_outline_polygon(PackedVector2Array([
				Vector2(-28.0, -8.0), Vector2(-12.0, -30.0), Vector2(4.0, -8.0)
			]))
			_outline_polygon(PackedVector2Array([
				Vector2(-2.0, -8.0), Vector2(14.0, -26.0), Vector2(30.0, -8.0)
			]))
		_:
			_outline_rect(Rect2(-16.0, -4.0, 32.0, 18.0))
			_outline_polygon(PackedVector2Array([
				Vector2(-21.0, -4.0), Vector2(0.0, -24.0), Vector2(21.0, -4.0)
			]))


func _outline_rect(rect: Rect2) -> void:
	_outline_polygon(PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]))


func _outline_polygon(points: PackedVector2Array) -> void:
	var count: int = points.size()
	if count < 2:
		return
	for i: int in range(count):
		var start: Vector2 = points[i]
		var end: Vector2 = points[(i + 1) % count]
		draw_line(start, end, HOVER_OUTLINE_COLOR, HOVER_OUTLINE_WIDTH, true)
		# 圆点补足折线拐角，保证描边连续。
		draw_circle(start, HOVER_OUTLINE_WIDTH * 0.5, HOVER_OUTLINE_COLOR)


## 修改前的村庄美术：土墙 + 红屋顶 + 门洞，保持不变。
func _draw_village() -> void:
	var wall := Color("#8a6a43")
	var roof := Color("#a24d3c")
	draw_rect(Rect2(-16.0, -4.0, 32.0, 18.0), wall, true)
	var roof_points := PackedVector2Array([
		Vector2(-21.0, -4.0),
		Vector2(0.0, -24.0),
		Vector2(21.0, -4.0),
	])
	draw_colored_polygon(roof_points, roof)
	draw_rect(Rect2(-5.0, 4.0, 10.0, 10.0), Color("#4a3020"), true)


## 城镇：比村庄更大的石墙聚落，双塔与多屋顶，便于与村庄/城堡区分。
func _draw_town() -> void:
	var wall := Color("#9a835c")
	var roof := Color("#9d4a3a")
	var dark := Color("#4a3a28")
	draw_rect(Rect2(-24.0, -8.0, 48.0, 22.0), wall, true)
	draw_rect(Rect2(-24.0, -8.0, 48.0, 5.0), dark, true)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-28.0, -8.0), Vector2(-12.0, -30.0), Vector2(4.0, -8.0)
		]),
		roof
	)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-2.0, -8.0), Vector2(14.0, -26.0), Vector2(30.0, -8.0)
		]),
		roof.lightened(0.08)
	)
	draw_rect(Rect2(-4.0, 4.0, 11.0, 10.0), dark, true)
	draw_rect(Rect2(-31.0, -18.0, 7.0, 14.0), wall, true)
	draw_rect(Rect2(24.0, -18.0, 7.0, 14.0), wall, true)


func _draw_castle() -> void:
	var stone := Color("#8f9196")
	var dark := Color("#5a5d63")
	draw_rect(Rect2(-20.0, -10.0, 40.0, 24.0), stone, true)
	draw_rect(Rect2(-20.0, -10.0, 10.0, 24.0), dark, true)
	draw_rect(Rect2(10.0, -10.0, 10.0, 24.0), dark, true)
	draw_rect(Rect2(-24.0, -24.0, 10.0, 16.0), stone, true)
	draw_rect(Rect2(14.0, -24.0, 10.0, 16.0), stone, true)
	draw_rect(Rect2(-5.0, 2.0, 10.0, 12.0), Color("#303238"), true)
	draw_line(Vector2(0.0, -24.0), Vector2(0.0, -38.0), Color("#3b2a1a"), 2.0, true)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(0.0, -38.0),
			Vector2(12.0, -34.0),
			Vector2(0.0, -30.0),
		]),
		Color("#b94b42")
	)
