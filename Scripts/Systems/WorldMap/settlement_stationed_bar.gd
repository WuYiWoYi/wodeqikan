class_name SettlementStationedBar
extends Control
## 地点下方“停留部队”旗帜条。
##
## 每支停留在地点上的部队用一个家族旗帜表示，不绘制圆形底盘；
## 多支部队从左到右排列，超过一行宽度后换行，不同地点各自独立。
## 只负责表现，不读取/修改任何权威数据；纹理与颜色由 WorldMap 转入。

const TextureRegion = preload("res://Scripts/Core/World/texture_region_utils.gd")

const BANNER_SIZE: Vector2 = Vector2(26.0, 32.0)
const BANNER_GAP: float = 4.0
const ROW_GAP: float = 4.0
## 单行最大宽度；超出后自动换行。
const MAX_ROW_WIDTH: float = 200.0
const BACK_COLOR: Color = Color(0.05, 0.06, 0.08, 0.72)
const BORDER_COLOR: Color = Color(0.86, 0.82, 0.70, 0.85)
## 旗帜在单个徽章内的留白，保证边框可见。
const FLAG_INSET: float = 3.0

## 每个条目：{ party_id: String, texture: Texture2D, texture_path: String, color: Color }。
var _entries: Array[Dictionary] = []
var _signature: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## 更新旗帜列表；内容与顺序未变化时不重建。
func set_entries(entries: Array[Dictionary]) -> void:
	var signature: String = _build_signature(entries)
	if signature == _signature:
		return
	_signature = signature
	_entries = entries
	_recompute_size()
	queue_redraw()
	visible = not _entries.is_empty()


func get_banner_count() -> int:
	return _entries.size()


func get_banner_party_ids() -> Array[String]:
	var ids: Array[String] = []
	for entry: Dictionary in _entries:
		ids.append(str(entry.get("party_id", "")))
	return ids


func get_signature() -> String:
	return _signature


func is_empty() -> bool:
	return _entries.is_empty()


## 每行可容纳的旗帜数量；至少 1，避免宽度异常时除零。
func get_per_row_count() -> int:
	return maxi(
		1,
		int(floor((MAX_ROW_WIDTH + BANNER_GAP) / (BANNER_SIZE.x + BANNER_GAP)))
	)


func _build_signature(entries: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for entry: Dictionary in entries:
		var color := entry.get("color", Color.WHITE) as Color
		parts.append("%s|%s|%s|%s" % [
			str(entry.get("party_id", "")),
			str(entry.get("texture_path", "")),
			color.to_html(),
			str(entry.get("display_name", "")),
		])
	return ";".join(parts)


func _recompute_size() -> void:
	var count: int = _entries.size()
	if count <= 0:
		size = Vector2.ZERO
		return
	var per_row: int = get_per_row_count()
	var rows: int = int(ceil(float(count) / float(per_row)))
	var columns: int = mini(count, per_row)
	size = Vector2(
		columns * BANNER_SIZE.x + maxf(0.0, columns - 1) * BANNER_GAP,
		rows * BANNER_SIZE.y + maxf(0.0, rows - 1) * ROW_GAP
	)


func _draw() -> void:
	if _entries.is_empty():
		return
	var per_row: int = get_per_row_count()
	for index: int in range(_entries.size()):
		var entry: Dictionary = _entries[index]
		var row: int = index / per_row
		var column: int = index % per_row
		var row_start: int = row * per_row
		var row_count: int = mini(per_row, _entries.size() - row_start)
		var row_width: float = (
			row_count * BANNER_SIZE.x + maxf(0.0, row_count - 1) * BANNER_GAP
		)
		var origin := Vector2(
			(size.x - row_width) * 0.5 + column * (BANNER_SIZE.x + BANNER_GAP),
			row * (BANNER_SIZE.y + ROW_GAP)
		)
		var rect := Rect2(origin, BANNER_SIZE)

		draw_rect(rect, BACK_COLOR, true)
		var frame_color := entry.get("color", BORDER_COLOR) as Color
		frame_color.a = 0.9
		draw_rect(rect, frame_color, false, 1.0)

		var texture := entry.get("texture") as Texture2D
		if texture == null:
			continue
		# 透明留白不参与排版：裁切到非透明像素区域后等比放入徽章内边距。
		texture = TextureRegion.get_trimmed_texture(texture)
		# 旗帜保持原始宽高比，放在徽章内边距以内；不做圆形裁剪。
		var inner_size := BANNER_SIZE - Vector2(FLAG_INSET, FLAG_INSET) * 2.0
		var texture_size := texture.get_size()
		var factor: float = minf(
			inner_size.x / maxf(1.0, texture_size.x),
			inner_size.y / maxf(1.0, texture_size.y)
		)
		var flag_size := texture_size * factor
		var flag_rect := Rect2(
			origin + (BANNER_SIZE - flag_size) * 0.5, flag_size
		)
		draw_texture_rect(texture, flag_rect, false)
