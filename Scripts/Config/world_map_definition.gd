class_name WorldMapDefinition
extends Resource
## 大地图静态定义（Data/WorldMap/world_map_definition.tres）。
##
## 只保存参考图像的像素级布局与换算比例，不保存运行时地点/部队状态。
## 世界坐标 = 参考像素坐标 × reference_scale；所有地点、边界、湖泊、
## 山脉与道路都使用同一套换算，避免多套坐标并存。
##
## 本资源是地图重建的唯一布局依据；运行时由 WorldContext 读取，
## WorldTerrain 据此建立不可通行区域，WorldInitializer 据此生成地点。

## 参考图像像素 → 世界坐标比例。5 表示 1 参考像素 = 5 世界像素。
@export var reference_scale: float = 5.0
## 参考图像尺寸（像素）。世界尺寸 = reference_size * reference_scale。
@export var reference_size: Vector2 = Vector2(1556.0, 1323.0)

## 地图外边界（参考像素，首尾不重复；运行时按闭合多边形处理）。
@export var boundary_points: PackedVector2Array = PackedVector2Array()
## 中央湖泊（参考像素，闭合多边形）。
@export var lake_points: PackedVector2Array = PackedVector2Array()
## 山脉椭圆：center(Vector2 参考像素)、semi_major、semi_minor、angle_deg。
@export var mountains: Array[Dictionary] = []

## 地点：key、name、type（SettlementData.SettlementType）、
## px（参考像素坐标）、family（视觉家族配置 ID，可为空）。
## 政治所有权不在这里配置；只有 WorldInitializer 明确指定的旧归属才写入。
@export var settlements: Array[Dictionary] = []
## 道路：每条为 PackedStringArray([起点 key, 终点 key])。
@export var roads: Array[PackedStringArray] = []

## 时间标定：参考图中最近的两个地点距离（像素）与期望旅行时间（游戏小时）。
@export var calibration_reference_distance: float = 86.2
## 1x 下 1 游戏小时 = 2 世界秒；移速基准调整为 30、玩家为 36 后，
## 最近地点对行程约 5.8 游戏小时。
@export var calibration_travel_hours: float = 5.8
## 大地图统一移动系数。由标定计算得出，供 WorldMapManager 与文档引用。
@export var world_map_speed_scale: float = 0.08


## 世界坐标尺寸（由参考尺寸与比例计算，不单独保存，避免不一致）。
func get_world_size() -> Vector2:
	return reference_size * reference_scale


func to_world(reference_position: Vector2) -> Vector2:
	return reference_position * reference_scale


func to_reference(world_position: Vector2) -> Vector2:
	if reference_scale <= 0.0:
		return world_position
	return world_position / reference_scale


func get_world_boundary() -> PackedVector2Array:
	return _scale_points(boundary_points)


func get_world_lake() -> PackedVector2Array:
	return _scale_points(lake_points)


## 世界坐标山脉：center/semi_major/semi_minor 已乘比例，angle_deg 不变。
func get_world_mountains() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for mountain: Dictionary in mountains:
		var center_value: Variant = mountain.get("center", Vector2.ZERO)
		var center: Vector2 = center_value if center_value is Vector2 else Vector2.ZERO
		result.append({
			"center": to_world(center),
			"semi_major": float(mountain.get("semi_major", 0.0)) * reference_scale,
			"semi_minor": float(mountain.get("semi_minor", 0.0)) * reference_scale,
			"angle_deg": float(mountain.get("angle_deg", 0.0)),
		})
	return result


## 地点定义的世界坐标副本，保留 key/name/type/family 字段。
func get_world_settlements() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Dictionary in settlements:
		var px_value: Variant = value.get("px", Vector2.ZERO)
		var px: Vector2 = px_value if px_value is Vector2 else Vector2.ZERO
		result.append({
			"key": str(value.get("key", "")),
			"name": str(value.get("name", "")),
			"type": int(value.get("type", 0)),
			"world_position": to_world(px),
			"px": px,
			"family": str(value.get("family", "")),
		})
	return result


func get_settlement_definition(key: String) -> Dictionary:
	for value: Dictionary in settlements:
		if str(value.get("key", "")) == key:
			return value
	return {}


func get_settlement_world_position(key: String) -> Vector2:
	var value := get_settlement_definition(key)
	if value.is_empty():
		return Vector2.ZERO
	var px_value: Variant = value.get("px", Vector2.ZERO)
	var px: Vector2 = px_value if px_value is Vector2 else Vector2.ZERO
	return to_world(px)


## 道路端点解析为世界坐标折线（端点必须是已定义地点）。
func get_world_roads() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for road: PackedStringArray in roads:
		if road.size() < 2:
			continue
		var from_key: String = road[0]
		var to_key: String = road[1]
		if get_settlement_definition(from_key).is_empty() \
				or get_settlement_definition(to_key).is_empty():
			continue
		result.append({
			"from_key": from_key,
			"to_key": to_key,
			"from": get_settlement_world_position(from_key),
			"to": get_settlement_world_position(to_key),
		})
	return result


func _scale_points(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(points.size())
	for index: int in range(points.size()):
		result[index] = to_world(points[index])
	return result
