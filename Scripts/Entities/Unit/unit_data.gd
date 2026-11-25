class_name UnitData
extends RefCounted
## 单个士兵/角色的持久化运行时数据。
##
## 权威数据：身份、等级、经验、装备、归属、招募来源。
## 派生数据：max_hp / attack 等最终属性，由 StatCalculator 依据配置与装备重算。
## current_hp 在非战斗状态下由世界侧写入；战斗期间以 BattleUnitState 为准。

## 单位生命周期状态。伤兵保留身份与部队归属，永久死亡才会被移出部队。
enum Status {
	ACTIVE,
	WOUNDED,
	DEAD,
}

var unit_id: String = ""
var config_id: String = ""
var display_name: String = ""
## 显式状态；current_hp <= 0 且仍留在部队中时必须是 WOUNDED。
var status: Status = Status.ACTIVE

var level: int = 1
var exp: int = 0
## 每日工资。创建时来自兵种等级配置；晋升时切换到新等级工资。
## 骑马/下马不改变该值。旧存档缺失时用 -1 表示“按当前配置补全”。
var wage: int = 0

var max_hp: int = 1
var current_hp: int = 1
var attack: int = 0
var attack_interval: float = 1.0
var move_speed: float = 60.0
var attack_range: float = 20.0
## 由当前 WEAPON 装备派生：0 = 近战，1 = 远程。不通过兵种名称判断。
var attack_type: int = EquipmentConfig.AttackType.MELEE
## 远程命中判定使用的身体有效高度；骑乘时由 StatCalculator 追加坐骑高度。
var body_height: float = 48.0
## 远程武器发射物表现参数；近战单位保持默认值且不会被使用。
var projectile_texture_path: String = ""
var projectile_speed: float = 480.0
var projectile_arc_height: float = 70.0

var faction_id: String = ""
## 家族身份（持久化）。空字符串表示无家族，使用阵营色/默认外观。
var family_id: String = ""
## NPC 领主身份（持久化，NobleData.lord_id）。仅家族领袖单位在创建时写入；
## 空字符串表示普通士兵。俘虏售价与家族赎回都通过该稳定 ID 关联，不依赖名称。
var noble_id: String = ""
var current_party_id: String = ""
## 阶段 13：俘虏归属。非空表示该单位被对应部队关押，不能同时作为成员。
## 只有 PartyManager 的俘虏接口可以修改该字段。
var prisoner_owner_party_id: String = ""
## 已出售给城镇时的记录；非空表示该单位已离开玩家/部队控制。
var sold_to_settlement_id: String = ""
var equipment: Dictionary = {}
## 单位当前坐骑的独立实例外观（阶段 12）。
## 与 equipment["MOUNT"] 的基础装备 ID 分离；卸下时原样返还背包。
var mount_instance: Dictionary = {}
var is_mounted: bool = false
## 玩家角色身份（持久化）；当前由谁控制由 BattleScene 运行时决定。
var is_player_character: bool = false
## 创建时一次性生成并持久化的外观选择。
## 键：family_id / tabard_variant / tabard_texture_path / tabard_color /
##     helmet_texture_path / plume_texture_path / spear_texture_path。
## 旧存档缺失时为空字典，回退到原有阵营外观。
var appearance: Dictionary = {}

## 招募来源信息（游戏内时间、方式、地点、原阵营）。
var joined_at_game_time: float = 0.0
var recruit_source: String = ""
var recruit_settlement_id: String = ""
var origin_faction_id: String = ""

## 酒馆雇佣兵身份（持久化）。这是装备/坐骑管理权限的唯一判定依据，
## 不通过兵种名称或 tier 推断。旧存档缺失时由 recruit_source 回填。
const MERCENARY_RECRUIT_SOURCE: String = "tavern_mercenary"
var is_mercenary: bool = false


func is_alive() -> bool:
	return status != Status.DEAD and current_hp > 0


## 是否允许玩家在士兵详情中更换装备/马匹。
## 雇佣兵由契约固定装备，不允许个体化更换；普通招募与采邑征召允许。
func can_manage_equipment() -> bool:
	return not is_mercenary


func is_wounded() -> bool:
	return status == Status.WOUNDED


func is_dead() -> bool:
	return status == Status.DEAD


## 是否为某支部队持有的俘虏。
func is_prisoner() -> bool:
	return not prisoner_owner_party_id.is_empty()


## 是否具有 NPC 领主身份（家族领袖单位）。
func is_noble_lord() -> bool:
	return not noble_id.is_empty()


## 家族赎回成功：清空俘虏/出售状态，恢复为可正常活动的单位。
## 这是赎回流程释放领主的唯一写入入口；调用方随后负责重建部队。
func mark_ransomed() -> void:
	prisoner_owner_party_id = ""
	current_party_id = ""
	sold_to_settlement_id = ""
	status = Status.ACTIVE
	current_hp = maxi(1, max_hp)


## 标记为俘虏。归属填写部队 ID；空字符串表示战后待分配俘虏。
func mark_prisoner(owner_party_id: String = "") -> void:
	prisoner_owner_party_id = owner_party_id
	current_party_id = ""
	if status == Status.ACTIVE:
		status = Status.WOUNDED


## 解除俘虏归属（释放/出售前由 PartyManager 统一调用）。
func clear_prisoner_ownership() -> void:
	prisoner_owner_party_id = ""


## 出售给城镇：离开所有部队与俘虏列表，保留 Unit 身份与数据。
func mark_sold(settlement_id: String) -> void:
	prisoner_owner_party_id = ""
	current_party_id = ""
	sold_to_settlement_id = settlement_id


## 战斗结算：负伤但保留单位身份与部队归属。HP 必须为 0。
func mark_wounded() -> void:
	status = Status.WOUNDED
	current_hp = 0


## 主动标为永久死亡；实际移除由 BattleManager/UnitManager 负责。
func mark_dead() -> void:
	status = Status.DEAD
	current_hp = 0


## 当前装备的武器是否为远程武器。攻击行为入口统一读取该派生值。
func is_ranged_attacker() -> bool:
	return attack_type == EquipmentConfig.AttackType.RANGED


func clamp_hp() -> void:
	current_hp = clampi(current_hp, 0, maxi(max_hp, 0))
	# HP 重新变为有效值（治疗/读档修正）时自动恢复为正常状态；
	# 负伤只能由战斗结算显式写入，避免 UI 或属性重算误判。
	if current_hp > 0 and status == Status.WOUNDED:
		status = Status.ACTIVE


## 当前坐骑的实例数据；没有 MOUNT 装备或数据缺失时返回 null。
func get_mount_instance_data() -> MountInstanceData:
	if mount_instance.is_empty():
		return null
	return MountInstanceData.from_dict(mount_instance)


func set_mount_instance_data(instance: MountInstanceData) -> void:
	mount_instance = instance.to_dict() if instance != null else {}


func to_dict() -> Dictionary:
	return {
		"unit_id": unit_id,
		"config_id": config_id,
		"display_name": display_name,
		"status": int(status),
		"level": level,
		"exp": exp,
		"wage": wage,
		"max_hp": max_hp,
		"current_hp": current_hp,
		"attack": attack,
		"attack_interval": attack_interval,
		"move_speed": move_speed,
		"attack_range": attack_range,
		"attack_type": attack_type,
		"body_height": body_height,
		"projectile_texture_path": projectile_texture_path,
		"projectile_speed": projectile_speed,
		"projectile_arc_height": projectile_arc_height,
		"faction_id": faction_id,
		"family_id": family_id,
		"noble_id": noble_id,
		"current_party_id": current_party_id,
		"prisoner_owner_party_id": prisoner_owner_party_id,
		"sold_to_settlement_id": sold_to_settlement_id,
		"equipment": equipment.duplicate(true),
		"mount_instance": mount_instance.duplicate(true),
		"is_mounted": is_mounted,
		"is_player_character": is_player_character,
		"appearance": appearance.duplicate(true),
		"joined_at_game_time": joined_at_game_time,
		"recruit_source": recruit_source,
		"recruit_settlement_id": recruit_settlement_id,
		"origin_faction_id": origin_faction_id,
		"is_mercenary": is_mercenary,
	}


static func from_dict(data: Dictionary) -> UnitData:
	var unit := UnitData.new()
	unit.unit_id = str(data.get("unit_id", ""))
	unit.config_id = str(data.get("config_id", ""))
	unit.display_name = str(data.get("display_name", ""))
	# 旧存档没有 status：先默认正常，读完全部 HP 字段后再归一化；
	# HP=0 且未标记死亡的单位按伤兵恢复，避免读档误删仍在部队中的单位。
	var status_value: int = int(data.get("status", Status.ACTIVE))
	if status_value < Status.ACTIVE or status_value > Status.DEAD:
		status_value = Status.ACTIVE
	unit.status = status_value as Status
	unit.level = int(data.get("level", 1))
	unit.exp = int(data.get("exp", 0))
	# 旧存档没有 wage：保留 -1 哨兵，UnitManager 重算时按配置补全。
	unit.wage = int(data.get("wage", -1))
	unit.max_hp = int(data.get("max_hp", 1))
	unit.current_hp = int(data.get("current_hp", unit.max_hp))
	unit.attack = int(data.get("attack", 0))
	unit.attack_interval = float(data.get("attack_interval", 1.0))
	unit.move_speed = float(data.get("move_speed", 60.0))
	unit.attack_range = float(data.get("attack_range", 20.0))
	# 以下字段是旧存档没有的派生缓存；读档后由 UnitManager 按装备重算。
	unit.attack_type = int(data.get("attack_type", EquipmentConfig.AttackType.MELEE))
	unit.body_height = maxf(1.0, float(data.get("body_height", 48.0)))
	unit.projectile_texture_path = str(data.get("projectile_texture_path", ""))
	unit.projectile_speed = maxf(1.0, float(data.get("projectile_speed", 480.0)))
	unit.projectile_arc_height = maxf(
		0.0, float(data.get("projectile_arc_height", 70.0))
	)
	unit.faction_id = str(data.get("faction_id", ""))
	unit.family_id = str(data.get("family_id", ""))
	# 旧存档没有领主身份；读档后由 WorldContext 按部队领袖关系回填。
	unit.noble_id = str(data.get("noble_id", ""))
	unit.current_party_id = str(data.get("current_party_id", ""))
	# 阶段 13：旧存档没有俘虏/出售字段，默认普通归属。
	unit.prisoner_owner_party_id = str(data.get("prisoner_owner_party_id", ""))
	unit.sold_to_settlement_id = str(data.get("sold_to_settlement_id", ""))
	unit.is_player_character = bool(data.get("is_player_character", false))

	# 外观字段是阶段 6 追加的可选数据；旧存档没有时保持空字典。
	var appearance_value: Variant = data.get("appearance", {})
	if appearance_value is Dictionary:
		unit.appearance = (appearance_value as Dictionary).duplicate(true)
	unit.joined_at_game_time = float(data.get("joined_at_game_time", 0.0))
	unit.recruit_source = str(data.get("recruit_source", ""))
	unit.recruit_settlement_id = str(data.get("recruit_settlement_id", ""))
	unit.origin_faction_id = str(data.get("origin_faction_id", ""))
	# 旧存档没有独立雇佣兵标记：按持久化的招募来源回填，避免权限丢失。
	unit.is_mercenary = bool(data.get(
		"is_mercenary", unit.recruit_source == MERCENARY_RECRUIT_SOURCE
	))

	var equipment_value: Variant = data.get("equipment", {})
	if equipment_value is Dictionary:
		unit.equipment = (equipment_value as Dictionary).duplicate(true)

	# 骑乘状态由 MOUNT 装备槽推导，不信任旧存档中的 is_mounted 标记。
	# 旧存档既没有 MOUNT 装备也没有马匹字段时，单位按步兵处理。
	var mount_slot: String = EquipmentConfig.SLOT_NAMES[EquipmentConfig.Slot.MOUNT]
	unit.is_mounted = unit.equipment.has(mount_slot)

	# 阶段 12：为已装备坐骑补齐独立外观实例。旧存档没有实例时使用
	# 单位 ID 生成确定性外观，反复读档不会刷新为新的随机马匹。
	var instance_value: Variant = data.get("mount_instance", {})
	if instance_value is Dictionary and not (instance_value as Dictionary).is_empty():
		unit.mount_instance = (instance_value as Dictionary).duplicate(true)
	if unit.is_mounted:
		var mount_id: String = str(unit.equipment.get(mount_slot, ""))
		var instance := MountInstanceData.from_dict(unit.mount_instance)
		if instance.equipment_id != mount_id:
			instance = MountInstanceData.create_deterministic(
				mount_id, "unit|%s|%s" % [unit.unit_id, mount_id]
			)
		unit.mount_instance = instance.to_dict()
	else:
		unit.mount_instance = {}

	unit.clamp_hp()
	# 显式状态与 HP 必须一致：未死亡的 0 HP 单位视为伤兵。
	if unit.status == Status.ACTIVE and unit.current_hp <= 0:
		unit.status = Status.WOUNDED
	return unit
