class_name TextureRegionUtils
extends RefCounted
## 贴图有效区域工具：计算 PNG 非透明像素范围，并按需生成 AtlasTexture。
##
## 用途：家族旗帜/徽章 PNG 画布四周常带透明留白，直接按原始尺寸缩放会让
## 实际美术显得过小，且不同旗帜的透明边距不同会导致视觉大小不一致。
## 本工具只做只读计算与运行时裁切，不修改源美术文件。
##
## 注意：AtlasTexture 的 region 使用贴图像素坐标；裁切后纹理尺寸即有效区域，
## Sprite2D/TextureRect 的等比缩放与圆形遮罩都基于该尺寸计算。

static var _used_rect_cache: Dictionary = {}
static var _trimmed_texture_cache: Dictionary = {}


## 返回贴图非透明像素范围；无有效像素或读取失败时回退到整张贴图。
static func get_used_rect(texture: Texture2D) -> Rect2i:
	if texture == null:
		return Rect2i()
	var key: String = _texture_key(texture)
	if _used_rect_cache.has(key):
		return _used_rect_cache[key] as Rect2i

	var full := Rect2i(Vector2i.ZERO, Vector2i(texture.get_size()))
	var result := full
	var image := texture.get_image()
	if image != null:
		var used := image.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			result = used
	_used_rect_cache[key] = result
	return result


## 返回去掉透明边距后的纹理；没有透明边距时直接返回原纹理。
## 同一贴图会复用同一个 AtlasTexture，避免列表/名称层每帧重复创建资源。
static func get_trimmed_texture(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var key: String = _texture_key(texture)
	if _trimmed_texture_cache.has(key):
		return _trimmed_texture_cache[key] as Texture2D

	var used := get_used_rect(texture)
	var full := Rect2i(Vector2i.ZERO, Vector2i(texture.get_size()))
	var result: Texture2D = texture
	if used.size.x > 0 and used.size.y > 0 and used != full:
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(used)
		result = atlas
	_trimmed_texture_cache[key] = result
	return result


## 有效区域的像素尺寸；无贴图时返回零。
static func get_effective_size(texture: Texture2D) -> Vector2:
	if texture == null:
		return Vector2.ZERO
	return Vector2(get_used_rect(texture).size)


## 清空缓存；只用于测试或资源热重载。
static func clear_cache() -> void:
	_used_rect_cache.clear()
	_trimmed_texture_cache.clear()


static func _texture_key(texture: Texture2D) -> String:
	if not texture.resource_path.is_empty():
		return texture.resource_path
	return "instance:%d" % texture.get_instance_id()
