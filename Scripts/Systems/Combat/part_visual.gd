class_name PartVisual
extends Node2D
## 部件贴图管理基类：负责加载、创建、命名、朝向与缺失素材回退。
##
## 人物与马匹的具体部件由 HumanVisual / HorseVisual 分别构建；
## 本类不关心骑乘状态、属性或战斗逻辑，只提供稳定的 Sprite2D 管理。
## 默认锚点为“脚底中心”：48×96 素材底部预留 4 像素阴影边距。

const DEFAULT_ANCHOR_MARGIN: float = 4.0

var _sprites: Dictionary = {}
var _facing: float = -1.0

## 同一部件/路径只警告一次，避免大量单位重复刷日志。
static var _logged_missing_parts: Dictionary = {}


## 创建部件并注册。parent 默认为自身；可传入旋转枢轴等中间节点。
## anchor_pixels 为素材左上角坐标系中的锚点；默认脚底中心。
func _add_sprite(
	part_name: String,
	texture_path: String,
	z_index_value: int,
	parent: Node = null,
	anchor_pixels: Vector2 = Vector2(-1.0, -1.0)
) -> Sprite2D:
	if texture_path.is_empty():
		return null
	if not ResourceLoader.exists(texture_path):
		_warn_missing_part(part_name, texture_path, "资源不存在")
		return null

	var texture := load(texture_path) as Texture2D
	if texture == null:
		_warn_missing_part(part_name, texture_path, "加载结果不是 Texture2D")
		return null

	var anchor := anchor_pixels
	if anchor.x < 0.0 or anchor.y < 0.0:
		anchor = Vector2(
			float(texture.get_width()) * 0.5,
			float(texture.get_height()) - DEFAULT_ANCHOR_MARGIN
		)

	var sprite := Sprite2D.new()
	sprite.name = "Part_%s" % part_name
	sprite.texture = texture
	sprite.centered = false
	sprite.offset = -anchor
	# 临时素材是像素画，固定最近邻采样，避免缩放后糊边。
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = z_index_value
	(parent if parent != null else self).add_child(sprite)
	_sprites[part_name] = sprite
	return sprite


func get_part(part_name: String) -> Sprite2D:
	var sprite := _sprites.get(part_name) as Sprite2D
	return sprite if is_instance_valid(sprite) else null


## 移除单个部件 Sprite；不影响旋转枢轴或其他部件。
func remove_part(part_name: String) -> void:
	var sprite := get_part(part_name)
	_sprites.erase(part_name)
	if sprite == null:
		return
	var parent := sprite.get_parent()
	if parent != null:
		parent.remove_child(sprite)
	sprite.queue_free()


## 将部件旋转中心相对当前锚点向下移动 drop_y 像素。
## 同时把节点位置补回 drop_y，使精灵在画面中的可见位置保持不变；
## 只是旋转轴心在素材坐标中下移，动画代码必须把 drop_y 作为基础位置叠加。
func lower_part_pivot(part_name: String, drop_y: float) -> void:
	var sprite := get_part(part_name)
	if sprite == null:
		return
	sprite.offset.y -= drop_y
	sprite.position.y += drop_y


func has_part(part_name: String) -> bool:
	return get_part(part_name) != null


func get_parts() -> Dictionary:
	return _sprites.duplicate()


## 部件相对于本组根节点的有效 z（包含武器枢轴等中间节点）。
func get_part_effective_z(part_name: String) -> int:
	var sprite := get_part(part_name)
	if sprite == null:
		return 0
	var total: int = sprite.z_index
	var node: Node = sprite.get_parent()
	while node != null and node != self:
		if node is CanvasItem:
			total += (node as CanvasItem).z_index
		node = node.get_parent()
	return total


## 默认朝左；朝右时整体水平镜像。整体镜像保证部件相对位置和旋转枢轴不偏移。
func set_facing(direction_x: float) -> void:
	if absf(direction_x) < 0.01:
		return
	var new_facing: float = 1.0 if direction_x > 0.0 else -1.0
	if is_equal_approx(new_facing, _facing):
		return
	_facing = new_facing
	# _facing 是方向符号（-1 左 / +1 右）；朝右时整体镜像到 scale.x = -1。
	scale.x = -_facing


func get_facing() -> float:
	return _facing


func clear_parts() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_sprites.clear()


func _warn_missing_part(part_name: String, texture_path: String, reason: String) -> void:
	var key: String = "%s|%s" % [part_name, texture_path]
	if _logged_missing_parts.has(key):
		return
	_logged_missing_parts[key] = true
	push_warning(
		"UnitVisual 部件不可用 [%s] %s：%s；仅跳过该部件"
		% [part_name, texture_path, reason]
	)
