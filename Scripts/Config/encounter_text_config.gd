class_name EncounterTextConfig
extends Resource
## 大地图遭遇对话文本配置。
##
## 键结构：reason_texts[reason_key][party_kind_key]。
## reason_key 来自 EncounterManager.reason_key()，部队类型键来自 PartyData.get_kind_key()。
## UI 只读取本配置，不在脚本里写死任何遭遇对白。

## 最终回退文本；任何键缺失时使用。
@export var fallback_text: String = "对方部队拦住了你的去路。"

@export var reason_texts: Dictionary = {
	"PASSIVE_ENCOUNTER": {
		"PLAYER": "你的部队在路边停了下来。",
		"FAMILY": "家族的巡逻队与你擦肩而过。",
		"MERCHANT": "商队与你偶然相遇，领头人向你点头致意。",
		"BANDIT": "几名强盗在路边打量着你的队伍。",
		"GUARD": "治安巡逻队从远处经过，警惕地看了你一眼。",
		"GENERIC": "双方在大路上偶然相遇。",
	},
	"PLAYER_INITIATED": {
		"PLAYER": "你的部队停了下来。",
		"FAMILY": "家族的骑士勒住马，询问你为何靠近。",
		"MERCHANT": "商队放慢脚步，领头人客气地与你打招呼。",
		"BANDIT": "强盗们停下脚步，手按在武器上盯着你。",
		"GUARD": "巡逻队拦住你，要求说明来意。",
		"GENERIC": "双方在路边停了下来，气氛有些微妙。",
	},
	"ENEMY_PURSUIT": {
		"PLAYER": "敌军追上了你！",
		"FAMILY": "家族的骑兵追上了你，将你团团围住。",
		"MERCHANT": "商队护卫追上了你，要求你立刻停下。",
		"BANDIT": "前面的家伙，留下你的财物！",
		"GUARD": "巡逻队追上了你，喝令你放下武器。",
		"GENERIC": "敌军追上了你，拦住了你的去路！",
	},
	"OTHER": {
		"PLAYER": "你的部队停了下来。",
		"FAMILY": "家族的骑士拦住了你。",
		"MERCHANT": "商队停了下来。",
		"BANDIT": "强盗拦住了你的去路。",
		"GUARD": "巡逻队拦住了你。",
		"GENERIC": "对方部队拦住了你的去路。",
	},
}


func get_text(reason_key: String, kind_key: String) -> String:
	var by_reason: Variant = reason_texts.get(reason_key)
	if by_reason is Dictionary:
		var texts: Dictionary = by_reason
		var value: Variant = texts.get(kind_key)
		if value is String and not (value as String).is_empty():
			return value
		value = texts.get("GENERIC")
		if value is String and not (value as String).is_empty():
			return value
	return fallback_text


static func create_default() -> EncounterTextConfig:
	return EncounterTextConfig.new()
