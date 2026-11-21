class_name SettlementIcon
extends Node2D
## 大地图地点图标。只读取 SettlementData，不修改权威数据。
##
## 村庄与城堡保留原有建筑绘制；家族徽章与名称属于独立屏幕 UI
## （SettlementNameTag），不在世界层绘制，也不随相机缩放改变尺寸。

## 地点名称组合位于原有美术正上方时的屏幕锚点半径（世界像素）。
const VILLAGE_NAME_ANCHOR_RADIUS: float = 28.0
const CASTLE_NAME_ANCHOR_RADIUS: float = 40.0

var settlement: SettlementData = null


func setup(data: SettlementData) -> void:
	settlement = data
	position = data.world_position if data != null else Vector2.ZERO
	queue_redraw()


## 名称层使用：返回原有建筑顶部到名称组合底部的视觉半径。
static func get_name_anchor_radius(
	settlement_type: SettlementData.SettlementType
) -> float:
	if settlement_type == SettlementData.SettlementType.CASTLE:
		return CASTLE_NAME_ANCHOR_RADIUS
	return VILLAGE_NAME_ANCHOR_RADIUS


func _draw() -> void:
	if settlement == null:
		return

	draw_circle(Vector2(0.0, 8.0), 15.0, Color(0.0, 0.0, 0.0, 0.22))
	if settlement.settlement_type == SettlementData.SettlementType.CASTLE:
		_draw_castle()
	else:
		_draw_village()


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
