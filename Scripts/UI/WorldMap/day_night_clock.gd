extends Control
## 顶栏正中的昼夜美术窗口。
##
## 只表现 TimeManager 的世界累计时间，不推进时间、不自行累计偏移：
## - 原始美术 `UI_昼夜` 为 96×48，左半 48×48 白天、右半 48×48 黑夜；
## - 以 96 像素为一个循环周期重复绘制，窗口固定为单个 48×48 区域的正方形；
## - 12:00 显示白天，18:00 处于交接，次日 00:00 显示黑夜，06:00 再次交接。
## 世界暂停时时间不再变化，滚动位置自然停住；倍速与读档都由世界时间直接决定。

const DAY_NIGHT_TEXTURE: Texture2D = preload(
	"res://art/我的骑砍临时美术/正式美术_其他/UI美术/UI_昼夜.png"
)
## 单块昼夜美术的边长（白天块与黑夜块均为 48×48）。
const TILE_SIZE: float = 48.0
## 横向共两块美术，一个完整循环的长度。
const CYCLE_TILE_COUNT: float = 2.0
## 正午 12:00 在一天中的比例。
const NOON_DAY_FRACTION: float = 0.5

var _scroll_phase: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	resized.connect(queue_redraw)
	queue_redraw()


## 唯一输入：世界累计秒数。位置完全由该值换算，不做逐帧累加。
func set_world_seconds(total_seconds: float) -> void:
	var day_length: float = (
		TimeManager.HOURS_PER_DAY * TimeManager.REAL_SECONDS_PER_GAME_HOUR
	)
	var day_fraction: float = fposmod(total_seconds / day_length, 1.0)
	set_scroll_phase(day_fraction - NOON_DAY_FRACTION)


## 滚动相位：0 = 正午显示完整白天，0.5 = 午夜显示完整黑夜。
func set_scroll_phase(phase: float) -> void:
	var wrapped: float = fposmod(phase, 1.0)
	if is_equal_approx(wrapped, _scroll_phase):
		return
	_scroll_phase = wrapped
	queue_redraw()


func get_scroll_phase() -> float:
	return _scroll_phase


## 当前美术相对窗口左缘的纹理偏移（0~96 像素），供测试与排查使用。
func get_texture_offset_pixels() -> float:
	return _scroll_phase * TILE_SIZE * CYCLE_TILE_COUNT


func _draw() -> void:
	var side: float = minf(size.x, size.y)
	if side <= 0.0:
		return
	var pixel_scale: float = side / TILE_SIZE
	var copy_width: float = TILE_SIZE * CYCLE_TILE_COUNT * pixel_scale
	var offset: float = _scroll_phase * copy_width
	var destination := Rect2(0.0, 0.0, copy_width, side)
	# 以 96 像素周期重复绘制；相位 0~1 时最多需要两份即可覆盖窗口。
	var x: float = -offset
	while x < side - 0.01:
		destination.position.x = x
		draw_texture_rect(DAY_NIGHT_TEXTURE, destination, false)
		x += copy_width
