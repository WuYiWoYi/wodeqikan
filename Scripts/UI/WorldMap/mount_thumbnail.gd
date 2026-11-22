class_name MountThumbnail
extends Control
## 交易列表中的马匹缩略图。
##
## 复用 MountVisualConfig 的毛色/马鞍贴图与 HorseVisual 的部件叠放顺序，
## 只把 48×96 的马匹画布等比缩放进固定方形区域，不另建一套马匹美术。
## 这里只绘制静态待机姿态，不包含战斗动画。

const CANVAS_SIZE: Vector2 = Vector2(48.0, 96.0)

var coat_style_id: String = "brown"
var saddle_style_id: String = "saddle_01"

var _textures: Array[Texture2D] = []


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(queue_redraw)


## 设置要展示的马匹外观；缺少贴图时由 MountVisualConfig 回退到棕马/基础马鞍。
func setup(p_coat_style_id: String, p_saddle_style_id: String) -> void:
	coat_style_id = p_coat_style_id
	saddle_style_id = p_saddle_style_id
	_reload_textures()
	queue_redraw()


func setup_from_instance(instance: MountInstanceData) -> void:
	if instance == null:
		setup("brown", "saddle_01")
		return
	setup(instance.coat_style_id, instance.saddle_style_id)


func _reload_textures() -> void:
	_textures.clear()
	var paths: Dictionary = MountVisualConfig.get_coat_paths(coat_style_id)
	# 与 HorseVisual.rebuild 的叠放顺序一致：腿 → 身体 → 马鞍 → 马头。
	for key: String in [
		"front_leg_1", "front_leg_2", "back_leg_1", "back_leg_2",
		"body",
	]:
		_append_texture(str(paths.get(key, "")))
	_append_texture(MountVisualConfig.get_saddle_path(saddle_style_id))
	_append_texture(str(paths.get("head", "")))


func _append_texture(path: String) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var texture := load(path) as Texture2D
	if texture != null:
		_textures.append(texture)


func _draw() -> void:
	var box: Vector2 = size
	if box.x <= 0.0 or box.y <= 0.0:
		return
	var scale_factor: float = minf(box.x / CANVAS_SIZE.x, box.y / CANVAS_SIZE.y)
	var draw_size: Vector2 = CANVAS_SIZE * scale_factor
	var origin: Vector2 = (box - draw_size) * 0.5
	var target := Rect2(origin, draw_size)
	for texture: Texture2D in _textures:
		draw_texture_rect(texture, target, false)
