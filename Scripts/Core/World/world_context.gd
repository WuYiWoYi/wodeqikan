class_name WorldContext
extends Node
## 一局游戏的持久化世界容器。
##
## 生命周期：新游戏/读档时由 GameManager 创建，跨大地图、小场景、战斗场景持续存在；
## 返回主菜单时销毁。场景节点只读取这里的实体数据。

const DEFAULT_WORLD_SIZE: Vector2 = Vector2(3000.0, 2000.0)
const UNIT_CONFIG_DIR: String = "res://Data/Units"
const EQUIPMENT_CONFIG_DIR: String = "res://Data/Equipment"
const ITEM_CONFIG_DIR: String = "res://Data/Items"
const FAMILY_CONFIG_DIR: String = "res://Data/Families"
const APPEARANCE_CONFIG_PATH: String = "res://Data/Appearance/appearance_config.tres"
const SETTLEMENT_ECONOMY_CONFIG_PATH: String = \
	"res://Data/Settlements/settlement_economy_config.tres"

var id_generator: IdGenerator = IdGenerator.new()
var unit_manager: UnitManager = UnitManager.new()
var item_manager: ItemManager = ItemManager.new()
var party_manager: PartyManager = PartyManager.new()
var settlement_manager: SettlementManager = SettlementManager.new()
var faction_manager: FactionManager = FactionManager.new()
## 家族静态配置只影响外观，不参与外交/存档。
var family_registry: FamilyRegistry = FamilyRegistry.new()
## 士兵外观随机池；只读静态资源，不进入存档。
var appearance_config: AppearanceConfig = null
## 封地经济/征召/冒险者刷新参数；只读静态资源，不进入存档。
var economy_config: SettlementEconomyConfig = null
var lord_manager: LordManager = LordManager.new()
var fief_recruitment_manager: FiefRecruitmentManager = FiefRecruitmentManager.new()
var adventurer_recruitment_manager: AdventurerRecruitmentManager = \
	AdventurerRecruitmentManager.new()
var vision_manager: VisionManager = VisionManager.new()
var world_map_manager: WorldMapManager = WorldMapManager.new()
var encounter_manager: EncounterManager = EncounterManager.new()
var world_log_manager: WorldLogManager = WorldLogManager.new()
var ai_manager: AIManager = AIManager.new()
var battle_manager: BattleManager = BattleManager.new()
var dialogue_manager: DialogueManager = DialogueManager.new()
var world_simulation: WorldSimulation = WorldSimulation.new()

var world_id: String = ""
var world_created_at: String = ""
var world_size: Vector2 = DEFAULT_WORLD_SIZE
var player_party_id: String = ""
## 玩家领主身份（封地所有权）与玩家角色 UnitData 是两个独立 ID。
var player_lord_id: String = ""
var player_unit_id: String = ""
var player_profile: PlayerProfile = PlayerProfile.new()

var _static_configs_registered: bool = false


func _ready() -> void:
	_wire_managers()
	register_static_configs()
	if not TimeManager.world_tick.is_connected(world_simulation.on_world_tick):
		TimeManager.world_tick.connect(world_simulation.on_world_tick)


func _exit_tree() -> void:
	world_log_manager.dispose()
	if TimeManager.world_tick.is_connected(world_simulation.on_world_tick):
		TimeManager.world_tick.disconnect(world_simulation.on_world_tick)


func get_player_party() -> PartyData:
	return party_manager.get_party(player_party_id)


func get_player_lord() -> LordData:
	var lord: LordData = lord_manager.get_lord(player_lord_id)
	if lord != null:
		return lord
	return lord_manager.get_player_lord()


func get_player_unit() -> UnitData:
	var unit := unit_manager.get_unit(player_unit_id)
	if unit != null:
		return unit
	var party := get_player_party()
	if party == null:
		return null
	for unit_id: String in party.member_unit_ids:
		var member := unit_manager.get_unit(unit_id)
		if member != null and member.is_player_character:
			return member
	return null


func is_valid_world() -> bool:
	if world_id.is_empty():
		return false
	if player_party_id.is_empty() or party_manager.get_party(player_party_id) == null:
		return false
	if settlement_manager.get_all_settlements().is_empty():
		return false
	return true


## 封地所有权与玩家身份的一致性校验；读档失败时不改写存档数据。
func validate_world_ownership() -> Array[String]:
	var errors: Array[String] = []
	for settlement: SettlementData in settlement_manager.get_all_settlements():
		if settlement == null or settlement.owner_lord_id.is_empty():
			continue
		if lord_manager.get_lord(settlement.owner_lord_id) == null:
			errors.append(
				"地点 %s 引用了不存在的领主 %s"
				% [settlement.settlement_id, settlement.owner_lord_id]
			)
	if not player_lord_id.is_empty():
		var player_lord: LordData = lord_manager.get_lord(player_lord_id)
		if player_lord == null or not player_lord.is_player_lord:
			errors.append("玩家领主 ID %s 无效" % player_lord_id)
	return errors


## 聚合当前世界的权威数据。表现节点和 UI 状态不进入存档。
func to_save_data() -> SaveData:
	var save := SaveData.new()
	save.world_id = world_id
	save.world_created_at = world_created_at
	save.world_size = world_size
	save.world_elapsed_seconds = TimeManager.world_elapsed_seconds
	save.world_base_speed = TimeManager.get_base_world_speed()
	save.id_counters = id_generator.to_dict()
	save.player_party_id = player_party_id
	save.player = {
		"party_id": player_party_id,
		"player_lord_id": player_lord_id,
		"player_unit_id": player_unit_id,
		"gold": player_profile.gold,
		"inventory": player_profile.inventory.duplicate(),
		"inventory_counts": player_profile.item_counts.duplicate(),
	}
	save.world_state = {}
	save.scene_state = {}
	save.world_log = world_log_manager.to_dict()
	save.units = unit_manager.to_dict()
	save.parties = party_manager.to_dict()
	save.settlements = settlement_manager.to_dict()
	save.lords = lord_manager.to_dict()
	save.factions = {}
	save.quests = {}
	return save


## 从存档恢复权威数据。调用前 WorldContext 必须已经加入场景树并完成 manager 装配。
func load_from_save_data(save: SaveData) -> bool:
	if save == null:
		return false

	world_id = save.world_id
	world_created_at = save.world_created_at
	world_size = save.world_size if save.world_size != Vector2.ZERO else DEFAULT_WORLD_SIZE
	player_party_id = save.player_party_id
	if player_party_id.is_empty():
		player_party_id = str(save.player.get("party_id", ""))
	player_lord_id = str(save.player.get("player_lord_id", ""))
	player_unit_id = str(save.player.get("player_unit_id", ""))
	# 原地更新，保持 BattleManager 持有的 profile 引用一致。
	var loaded_profile: PlayerProfile = PlayerProfile.from_dict(save.player)
	player_profile.gold = loaded_profile.gold
	player_profile.inventory = loaded_profile.inventory
	player_profile.item_counts = loaded_profile.item_counts
	ai_manager.player_party_id = player_party_id
	battle_manager.player_party_id = player_party_id

	id_generator.restore_from(save.id_counters)
	unit_manager.load_from_dict(save.units)
	party_manager.load_from_dict(save.parties)
	# 旧存档没有 control_type / party_kind / banner_texture_path：
	# 按 player_party_id、阵营、家族与 AI 类型补齐安全默认值。
	party_manager.apply_runtime_defaults(player_party_id)
	# 存档不保存活动战斗会话：清理读档后不可能成立的战斗/追逐状态。
	var sanitize_notes: Array[String] = party_manager.sanitize_loaded_runtime_state()
	for message: String in sanitize_notes:
		print("[WorldContext] %s" % message)
	lord_manager.load_from_dict(save.lords)
	settlement_manager.load_from_dict(save.settlements)
	world_log_manager.load_from_dict(save.world_log)
	world_map_manager.world_bounds = Rect2(Vector2.ZERO, world_size)

	# 旧存档没有领主数据时，至少恢复玩家领主身份；不伪造封地归属。
	var player_lord: LordData = lord_manager.get_lord(player_lord_id)
	if player_lord == null:
		player_lord = lord_manager.get_player_lord()
	if player_lord == null and party_manager.get_party(player_party_id) != null:
		player_lord = lord_manager.create_lord(
			"玩家领主", party_manager.get_party(player_party_id).faction_id,
			player_party_id, true
		)
	player_lord_id = player_lord.lord_id if player_lord != null else ""
	if player_unit_id.is_empty():
		var player_unit: UnitData = get_player_unit()
		player_unit_id = player_unit.unit_id if player_unit != null else ""
	adventurer_recruitment_manager.player_party_id = player_party_id

	# 采邑容量/税收与候选人生成都来自同一经济配置；读档只修正边界，
	# 不覆盖存档中的储备与刷新计时。
	for settlement: SettlementData in settlement_manager.get_all_settlements():
		fief_recruitment_manager.initialize_settlement(settlement)
		adventurer_recruitment_manager.initialize_settlement(settlement, false)

	# 读档以当前静态配置、持久化等级与装备为准重算最终属性；
	# 无效装备引用会在 UnitManager 中报告并清理，不会静默生成错误属性。
	var stat_errors: Array[String] = unit_manager.recalculate_all_stats()
	for message: String in stat_errors:
		push_error("[WorldContext] %s" % message)

	# 两个仓储分别反序列化成功，不代表双向归属一致；恢复完成后统一校验。
	# 校验失败时不自动改写存档数据，保留现场并拒绝加载。
	var membership_errors: Array[String] = party_manager.validate_membership_consistency()
	if not membership_errors.is_empty():
		for message: String in membership_errors:
			push_error("[WorldContext] 士兵-部队成员关系校验失败: %s" % message)
		return false

	# 领主与部队、封地与领主的双向引用必须一致；坏档不自动改写。
	var lord_errors: Array[String] = lord_manager.validate(party_manager)
	if not lord_errors.is_empty():
		for message: String in lord_errors:
			push_error("[WorldContext] 领主数据校验失败: %s" % message)
		return false
	var ownership_errors: Array[String] = validate_world_ownership()
	if not ownership_errors.is_empty():
		for message: String in ownership_errors:
			push_error("[WorldContext] 封地所有权校验失败: %s" % message)
		return false

	return is_valid_world()


## 注册 Data/Units 与 Data/Equipment 下的全部静态模板。
## 新游戏与读档都依赖这里完成注册；重复调用是幂等的。
func register_static_configs() -> bool:
	if _static_configs_registered:
		return true

	var success: bool = true
	for path: String in _list_resource_paths(UNIT_CONFIG_DIR):
		var unit_config := load(path) as UnitConfig
		if unit_config == null:
			push_error("无法加载兵种配置: %s" % path)
			success = false
			continue
		if not unit_manager.register_unit_config(unit_config):
			push_error("兵种配置注册失败: %s" % path)
			success = false

	for path: String in _list_resource_paths(EQUIPMENT_CONFIG_DIR):
		var equipment_config := load(path) as EquipmentConfig
		if equipment_config == null:
			push_error("无法加载装备配置: %s" % path)
			success = false
			continue
		if not unit_manager.register_equipment_config(equipment_config):
			push_error("装备配置注册失败: %s" % path)
			success = false

	for path: String in _list_resource_paths(ITEM_CONFIG_DIR):
		var item_config := load(path) as ItemConfig
		if item_config == null:
			push_error("无法加载物品配置: %s" % path)
			success = false
			continue
		if not item_manager.register_item_config(item_config):
			push_error("物品配置注册失败: %s" % path)
			success = false

	for path: String in _list_resource_paths(FAMILY_CONFIG_DIR):
		var family_config := load(path) as FamilyConfig
		if family_config == null:
			push_error("无法加载家族配置: %s" % path)
			success = false
			continue
		if not family_registry.register_config(family_config):
			push_error("家族配置注册失败: %s" % path)
			success = false

	appearance_config = load(APPEARANCE_CONFIG_PATH) as AppearanceConfig
	if appearance_config == null:
		push_error("无法加载外观配置: %s" % APPEARANCE_CONFIG_PATH)
		success = false
	fief_recruitment_manager.set_appearance_config(appearance_config)
	adventurer_recruitment_manager.set_appearance_config(appearance_config)

	_static_configs_registered = success
	return success


static func _list_resource_paths(directory: String) -> Array[String]:
	var paths: Array[String] = []
	var dir: DirAccess = DirAccess.open(directory)
	if dir == null:
		push_warning("静态配置目录不存在: %s" % directory)
		return paths
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			paths.append(directory.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()
	if paths.is_empty():
		push_warning("静态配置目录中没有 .tres: %s" % directory)
	return paths


func _wire_managers() -> void:
	if economy_config == null:
		economy_config = load(SETTLEMENT_ECONOMY_CONFIG_PATH) as SettlementEconomyConfig
		if economy_config == null:
			push_warning(
				"无法加载封地经济配置，使用脚本默认值: %s"
				% SETTLEMENT_ECONOMY_CONFIG_PATH
			)
			economy_config = SettlementEconomyConfig.new()
	economy_config.sanitize()

	unit_manager.setup(id_generator)
	party_manager.setup(unit_manager, id_generator)
	settlement_manager.setup(id_generator)
	lord_manager.setup(id_generator, party_manager)
	faction_manager.setup_defaults()
	vision_manager.setup(party_manager, faction_manager, unit_manager)
	world_map_manager.setup(party_manager, vision_manager)
	battle_manager.setup(
		unit_manager, party_manager, id_generator, faction_manager, player_profile
	)
	encounter_manager.setup(
		party_manager, faction_manager, battle_manager, world_map_manager
	)
	world_log_manager.setup(battle_manager, party_manager, settlement_manager)
	fief_recruitment_manager.setup(
		unit_manager,
		party_manager,
		settlement_manager,
		lord_manager,
		family_registry,
		economy_config
	)
	adventurer_recruitment_manager.setup(
		unit_manager,
		party_manager,
		settlement_manager,
		id_generator,
		family_registry,
		economy_config
	)
	ai_manager.setup(
		unit_manager,
		party_manager,
		world_map_manager,
		settlement_manager,
		faction_manager,
		vision_manager,
		battle_manager,
		lord_manager,
		fief_recruitment_manager,
		economy_config
	)
	world_simulation.bind(
		unit_manager,
		party_manager,
		world_map_manager,
		ai_manager,
		battle_manager,
		encounter_manager,
		fief_recruitment_manager,
		adventurer_recruitment_manager
	)
