class_name MoveTargetGuide
extends Node2D
## 玩家在大地图上的移动目标标记与动态虚线寻路线。
##
## 纯表现节点：只读取调用方传入的世界坐标，不修改任何移动数据。
## 节点自身固定在世界原点，绘制内容使用世界坐标，因此镜头移动/缩放后
## 标记与连线始终贴合地图；虚线长度、线宽与动画速度按镜头缩放换算，
## 保持稳定的屏幕视觉尺寸与滚动速度。

## 目标标记（屏幕像素基准，绘制时除以镜头缩放）。
const MARKER_RADIUS: float = 13.0
const MARKER_RING_WIDTH: float = 2.0
const MARKER_CORE_RADIUS: float = 4.0
## 外圈呼吸动画的周期与最大扩散倍数。
const MARKER_PULSE_PERIOD: float = 1.6
const MARKER_PULSE_SCALE: float = 0.55

## 虚线（屏幕像素基准）。
const DASH_LENGTH: float = 12.0
const DASH_GAP: float = 8.0
const DASH_LINE_WIDTH: float = 2.0
## 虚线沿行进方向滚动的屏幕速度（像素/秒）。
const DASH_SCROLL_SPEED: float = 46.0

const MARKER_COLOR: Color = Color("#f4d27a")
const MARKER_OUTLINE_COLOR: Color = Color(0.22, 0.16, 0.05, 0.85)
const MARKER_FILL_COLOR: Color = Color(0.98, 0.86, 0.44, 0.28)
const LINE_COLOR: Color = Color(0.95, 0.82, 0.42, 0.9)

var _active: bool = false
var _start: Vector2 = Vector2.ZERO
var _target: Vector2 = Vector2.ZERO
var _zoom: float = 1.0
var _elapsed: float = 0.0


func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	queue_redraw()


## 更新连线起点、目标点与当前镜头缩放；可每帧重复调用。
## 虚线动画时间轴不会因重复调用而重置。
func set_guide(start: Vector2, target: Vector2, camera_zoom: float) -> void:
	_start = start
	_target = target
	_zoom = maxf(camera_zoom, 0.01)
	_active = true
	queue_redraw()


## 清除标记与连线；重复调用无副作用。
func clear() -> void:
	if not _active:
		return
	_active = false
	_elapsed = 0.0
	queue_redraw()


func is_active() -> bool:
	return _active


func get_start_position() -> Vector2:
	return _start


func get_target_position() -> Vector2:
	return _target


func _draw() -> void:
	if not _active:
		return
	var zoom: float = maxf(_zoom, 0.01)
	var pattern: float = (DASH_LENGTH + DASH_GAP) / zoom

	var direction: Vector2 = _target - _start
	var length: float = direction.length()
	if length > 0.01:
		var unit: Vector2 = direction / length
		var dash: float = DASH_LENGTH / zoom
		var gap: float = DASH_GAP / zoom
		var width: float = DASH_LINE_WIDTH / zoom
		# 虚线沿起点 → 目标点方向滚动；偏移量按屏幕速度换算为世界单位。
		var offset: float = fmod(_elapsed * DASH_SCROLL_SPEED / zoom, pattern)
		var cursor: float = offset - pattern
		while cursor < length:
			var seg_start: float = maxf(cursor, 0.0)
			var seg_end: float = minf(cursor + dash, length)
			if seg_end > seg_start:
				draw_line(
					_start + unit * seg_start,
					_start + unit * seg_end,
					LINE_COLOR,
					width,
					true
				)
			cursor += dash + gap

	_draw_marker(zoom)


## 目标点标记：外圈呼吸扩散 + 实心圆环 + 中心点，与地点/部队图标区分。
func _draw_marker(zoom: float) -> void:
	var radius: float = MARKER_RADIUS / zoom
	var pulse: float = 0.5 + 0.5 * sin(TAU * _elapsed / MARKER_PULSE_PERIOD)
	var pulse_radius: float = radius * (1.0 + MARKER_PULSE_SCALE * pulse)
	draw_circle(
		_target,
		pulse_radius,
		Color(MARKER_COLOR, 0.16 * (1.0 - pulse))
	)
	draw_circle(_target, radius, MARKER_FILL_COLOR)
	draw_arc(
		_target,
		radius,
		0.0,
		TAU,
		32,
		MARKER_OUTLINE_COLOR,
		(MARKER_RING_WIDTH + 1.0) / zoom,
		true
	)
	draw_arc(
		_target,
		radius,
		0.0,
		TAU,
		32,
		MARKER_COLOR,
		MARKER_RING_WIDTH / zoom,
		true
	)
	draw_circle(_target, MARKER_CORE_RADIUS / zoom, MARKER_COLOR)
