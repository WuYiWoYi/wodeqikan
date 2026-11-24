class_name UnitConfig
extends Resource
## 兵种静态配置（Data/Units/*.tres）。
##
## 只定义“兵种模板”，不保存单个士兵的运行时状态。
## 运行时 UnitData 通过 config_id 引用本配置。

enum UnitClass {
	INFANTRY,
	RANGED,
	CAVALRY,
}

@export_category("Identity")
@export var config_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var unit_class: UnitClass = UnitClass.INFANTRY
## 兼容旧数据的外观提示；运行时骑乘状态只由 UnitData.equipment 的 MOUNT 槽决定。
## 不能通过本字段创建独立骑兵兵种。
@export var is_mounted: bool = false
## 玩家角色身份；与“当前控制权”无关。旧存档缺失时默认 false。
@export var is_player_character: bool = false

@export_category("Tier")
## 兵种等级：1 一般部队 / 2 受过训练的军士 / 3 训练有素的小贵族等。
## 与“等级（level）”和“是否骑马”都无关：骑马不会改变 tier。
@export var tier: int = 1

@export_category("Base Stats")
@export var base_level: int = 1
@export var base_max_hp: int = 50
@export var base_attack: int = 10
@export var attack_interval: float = 1.0
@export var attack_range: float = 20.0
@export var move_speed: float = 60.0
## 单位身体有效高度（像素），用于远程箭矢的高度命中判定。
## 骑乘时由 StatCalculator 统一追加坐骑高度，不在兵种配置中重复设置。
@export var body_height: float = 48.0

@export_category("Economy")
## 每名士兵的每日工资；由该兵种等级决定，骑马/下马不变。
## 0 表示不领取工资（例如玩家角色）。
@export var daily_wage: int = 0

@export_category("Promotion")
## 消耗型晋升物品。三者同时为空表示已处于最高兵种等级。
## 晋升保留 level / exp，切换 config_id 后按新等级配置重算属性。
@export var promotion_item_id: String = ""
@export var promotion_item_cost: int = 1
@export var promotion_target_config_id: String = ""

@export_category("Progression")
## 战斗经验等级从 1 开始，最高为 CombatExperience.MAX_LEVEL（当前 5）。
## 经验门槛由 CombatExperience 集中维护（100/300/500/1000），不再按配置递增。
@export var max_level: int = 5
## 旧字段保留用于兼容旧 .tres 与校验；实际升级门槛以 CombatExperience 为准。
@export var base_exp_to_next_level: int = 100
@export var exp_growth_per_level: int = 0

@export_category("Level Growth")
## 经验等级带来的额外成长；当前只由 CombatExperience 提供生命值加成，
## 因此这些字段默认 0，避免同一等级同时叠加两套生命值成长。
@export var hp_per_level: int = 0
@export var attack_per_level: int = 0
@export var move_speed_per_level: float = 0.0
@export var attack_range_per_level: float = 0.0

@export_category("Visual / Economy")
@export var visual_scene_path: String = ""
@export var recruit_cost: int = 0
@export var default_equipment: Dictionary = {}


## 从当前等级升到下一级所需经验。
## 门槛统一由 CombatExperience 提供；达到最高等级后返回 0。
## base_exp_to_next_level / exp_growth_per_level 仅为旧资源兼容保留。
func exp_to_next_level(current_level: int) -> int:
	var level: int = clampi(current_level, 1, maxi(max_level, 1))
	if level >= maxi(max_level, 1):
		return 0
	return CombatExperience.exp_to_next_level(level)


func get_class_display_name() -> String:
	match unit_class:
		UnitClass.RANGED:
			return "远程"
		UnitClass.CAVALRY:
			return "骑兵"
		_:
			return "步兵"


## 兵种等级的可读名称。集中在这里，避免 UI 各自硬编码。
static func tier_display_name(value: int) -> String:
	match value:
		1:
			return "一级（一般部队）"
		2:
			return "二级（军士）"
		3:
			return "三级（小贵族）"
		_:
			return "未知等级"


func get_tier_display_name() -> String:
	return tier_display_name(tier)


## 是否为最高兵种等级（没有晋升目标）。
func is_max_tier() -> bool:
	return promotion_target_config_id.strip_edges().is_empty()


func validate() -> bool:
	if config_id.strip_edges().is_empty():
		push_error("UnitConfig 缺少 config_id: %s" % resource_path)
		return false
	if display_name.strip_edges().is_empty():
		push_error("UnitConfig 缺少 display_name: %s" % resource_path)
		return false
	if base_max_hp <= 0 or base_attack <= 0:
		push_error("UnitConfig 基础属性非法: %s" % config_id)
		return false
	if base_level < 1 or base_level > max_level:
		push_error("UnitConfig 等级配置非法: %s（base_level=%s, max_level=%s）"
			% [config_id, base_level, max_level])
		return false
	if max_level < 1:
		push_error("UnitConfig max_level 必须大于等于 1: %s" % config_id)
		return false
	if base_exp_to_next_level < 1 or exp_growth_per_level < 0:
		push_error("UnitConfig 经验配置非法: %s" % config_id)
		return false
	if hp_per_level < 0 or attack_per_level < 0:
		push_error("UnitConfig 等级成长配置非法: %s" % config_id)
		return false
	if move_speed_per_level < 0.0 or attack_range_per_level < 0.0:
		push_error("UnitConfig 等级成长配置非法: %s" % config_id)
		return false
	if body_height <= 0.0:
		push_error("UnitConfig 身体高度必须大于 0: %s（body_height=%s）"
			% [config_id, body_height])
		return false
	if tier < 1 or tier > 3:
		push_error("UnitConfig 兵种等级必须在 1..3: %s（tier=%s）" % [config_id, tier])
		return false
	if daily_wage < 0:
		push_error("UnitConfig 工资不能为负数: %s" % config_id)
		return false
	var has_promotion_item: bool = not promotion_item_id.strip_edges().is_empty()
	var has_promotion_target: bool = not promotion_target_config_id.strip_edges().is_empty()
	if has_promotion_item != has_promotion_target:
		push_error(
			"UnitConfig 晋升配置不完整：物品与目标兵种必须同时设置: %s" % config_id
		)
		return false
	if has_promotion_item and promotion_item_cost < 1:
		push_error("UnitConfig 晋升物品数量必须大于等于 1: %s" % config_id)
		return false
	return true
