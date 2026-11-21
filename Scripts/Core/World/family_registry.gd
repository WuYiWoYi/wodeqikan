class_name FamilyRegistry
extends RefCounted
## 家族静态配置注册表。
##
## 家族不是阵营（FactionManager）也不是部队（PartyManager）：
## - 阵营决定外交与敌对；
## - 部队决定大地图移动与战斗参与；
## - 家族只决定旗帜、罩袍、缨饰与长矛等视觉身份。
## 本类只读注册 Data/Families/*.tres，不进入存档。

var _configs: Dictionary = {}


func register_config(config: FamilyConfig) -> bool:
	if config == null or not config.validate():
		return false
	if _configs.has(config.family_id):
		push_error("家族配置重复注册，拒绝覆盖: %s" % config.family_id)
		return false
	_configs[config.family_id] = config
	return true


func get_config(family_id: String) -> FamilyConfig:
	return _configs.get(family_id) as FamilyConfig


func has_config(family_id: String) -> bool:
	return _configs.has(family_id)


func get_all_configs() -> Array[FamilyConfig]:
	var result: Array[FamilyConfig] = []
	for value: Variant in _configs.values():
		var config := value as FamilyConfig
		if config != null:
			result.append(config)
	return result


func clear() -> void:
	_configs.clear()
