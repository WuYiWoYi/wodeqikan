class_name MountVisualConfig
extends RefCounted
## 马匹外观集中配置：毛色 ID → 部件贴图，马鞍 ID → 鞍具贴图。
##
## HorseVisual、交易缩略图与测试共用这一份路径表；
## 资源缺失时统一回退到棕马与 1 号马鞍，不在调用方各写一套判断。

const ART_DIR: String = "res://art/正式人物美术/马匹美术/"
const SHADOW_PATH: String = "res://art/我的骑砍临时美术/骑马的影子.png"

## 键必须是字符串字面量：const 初始化不能依赖其他 class_name 的常量表达式。
const COAT_FILES: Dictionary = {
	"black": {
		"head": "黑马马头.png",
		"body": "黑马马身体.png",
		"front_leg_1": "黑马马前腿1.png",
		"front_leg_2": "黑马马前腿2.png",
		"back_leg_1": "黑马马后腿1.png",
		"back_leg_2": "黑马马后腿2.png",
	},
	"white": {
		"head": "白马马头.png",
		"body": "白马马身体.png",
		"front_leg_1": "白马马前腿1.png",
		"front_leg_2": "白马马前腿2.png",
		"back_leg_1": "白马马后腿1.png",
		"back_leg_2": "白马马后腿2.png",
	},
	"brown": {
		"head": "棕马马头.png",
		"body": "棕马马身体.png",
		"front_leg_1": "棕马马前腿1.png",
		"front_leg_2": "棕马马前腿2.png",
		"back_leg_1": "棕马马后腿1.png",
		"back_leg_2": "棕马马后腿2.png",
	},
}

const SADDLE_FILES: Dictionary = {
	"saddle_01": "马鞍1.png",
	"saddle_02": "马鞍2.png",
	"saddle_03": "马鞍3.png",
	"saddle_04": "马鞍4.png",
	"saddle_05": "马鞍5.png",
	"saddle_06": "马鞍6.png",
	"saddle_07": "马鞍7.png",
	"saddle_08": "马鞍8.png",
}


## 返回指定毛色的完整部件路径；未知毛色或任一资源缺失时回退棕马。
static func get_coat_paths(coat_style_id: String) -> Dictionary:
	var files: Dictionary = COAT_FILES.get(coat_style_id, {})
	if files.is_empty() or not _paths_exist(files):
		files = COAT_FILES[MountInstanceData.DEFAULT_COAT]
	return {
		"head": ART_DIR + str(files["head"]),
		"body": ART_DIR + str(files["body"]),
		"front_leg_1": ART_DIR + str(files["front_leg_1"]),
		"front_leg_2": ART_DIR + str(files["front_leg_2"]),
		"back_leg_1": ART_DIR + str(files["back_leg_1"]),
		"back_leg_2": ART_DIR + str(files["back_leg_2"]),
	}


static func get_saddle_path(saddle_style_id: String) -> String:
	var file_name: String = str(SADDLE_FILES.get(
		saddle_style_id, SADDLE_FILES[MountInstanceData.DEFAULT_SADDLE]
	))
	var path: String = ART_DIR + file_name
	if not ResourceLoader.exists(path):
		path = ART_DIR + str(SADDLE_FILES[MountInstanceData.DEFAULT_SADDLE])
	return path


static func _paths_exist(files: Dictionary) -> bool:
	for key: Variant in files.keys():
		if not ResourceLoader.exists(ART_DIR + str(files[key])):
			return false
	return true
