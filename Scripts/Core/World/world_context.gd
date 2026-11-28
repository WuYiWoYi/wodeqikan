class_name WorldContext
extends Node
## 一局游戏的持久化世界容器。
##
## 生命周期：新游戏/读档时由 GameManager 创建，跨大地图、小场景、战斗场景持续存在；
## 返回主菜单时销毁。场景节点只读取这里的实体数据。

## 大地图按参考图像 1556×1323 像素、1 像素 = 5 世界像素重建。
## 旧存档仍保存 5000×3000：WorldContext 只在尺寸与地图定义一致时
## 装配地形，旧存档继续使用矩形边界与直线移动，避免强制迁移。
const DEFAULT_WORLD_SIZE: Vector2 = Vector2(7780.0, 6615.0)
const WORLD_MAP_DEFINITION_PATH: String = \
	"res://Data/WorldMap/world_map_definition.tres"
const UNIT_CONFIG_DIR: String = "res://Data/Units"
const EQUIPMENT_CONFIG_DIR: String = "res://Data/Equipment"
const ITEM_CONFIG_DIR: String = "res://Data/Items"
const MARKET_GOODS_CONFIG_DIR: String = "res://Data/Market"
const FAMILY_CONFIG_DIR: String = "res://Data/Families"
const APPEARANCE_CONFIG_PATH: String = "res://Data/Appearance/appearance_config.tres"
const SETTLEMENT_ECONOMY_CONFIG_PATH: String = \
	"res://Data/Settlements/settlement_economy_config.tres"
const VILLAGE_SPECIALTY_CONFIG_PATH: String = \
	"res://Data/Settlements/village_specialties.tres"
const RECRUITMENT_CONFIG_PATH: String = \
	"res://Data/Recruitment/recruitment_config.tres"
## 旧存档升级 v6 时，为完全没有补给数据的部队补几天起步物资与少量资金。
const MIGRATION_SUPPLY_DAYS: int = 3
const MIGRATION_NPC_GOLD: int = 200

var id_generator: IdGenerator = IdGenerator.new()
var unit_manager: UnitManager = UnitManager.new()
var item_manager: ItemManager = ItemManager.new()
## 村庄/城镇市场库存与交易业务；玩家背包仍由 player_profile 唯一持有。
var market_manager: MarketManager = MarketManager.new()
## 阶段 12：所有部队每日补给消耗的唯一结算入口。
var supply_manager: SupplyManager = SupplyManager.new()
## 阶段 13：伤兵按 WorldTime 整小时顺序恢复的唯一结算入口。
var wounded_healing_manager: WoundedHealingManager = WoundedHealingManager.new()
## 阶段 13：俘虏出售统一业务入口（价格集中配置、原子结算）。
var prisoner_trade_manager: PrisonerTradeManager = PrisonerTradeManager.new()
## 牲畜宰杀统一业务入口：只处理猪/马 → 肉，UI 不直接增删背包。
var slaughter_manager: SlaughterManager = SlaughterManager.new()
## NPC 领主出售后的家族赎回生命周期（等待 → 请求 → 接受/取消）。
var lord_ransom_manager: LordRansomManager = LordRansomManager.new()
## 事件中心脚本用 preload 引用，避免新增 class_name 尚未进入编辑器缓存时无法解析。
const EventCenterScript = preload("res://Scripts/Core/World/event_center.gd")
var party_manager: PartyManager = PartyManager.new()
var settlement_manager: SettlementManager = SettlementManager.new()
var faction_manager: FactionManager = FactionManager.new()
## 家族静态配置只影响外观，不参与外交/存档。
var family_registry: FamilyRegistry = FamilyRegistry.new()
## 士兵外观随机池；只读静态资源，不进入存档。
var appearance_config: AppearanceConfig = null
## 封地经济/征召/冒险者刷新参数；只读静态资源，不进入存档。
var economy_config: SettlementEconomyConfig = null
## 村庄特产静态配置；只读，不进入存档（存档只保存地点自身的特产字段）。
var village_specialty_config: VillageSpecialtyConfig = null
## 统一招募价格与雇佣兵世界刷新参数；只读静态资源，不进入存档。
var recruitment_config: RecruitmentConfig = null
## 贵族/家族/王国是本阶段的政治实体层级；lord_manager 指向同一个 NobleManager，
## 用于兼容封地所有权与既有 AI 接口。
var noble_manager: NobleManager = NobleManager.new()
var house_manager: HouseManager = HouseManager.new()
var kingdom_manager: KingdomManager = KingdomManager.new()
var lord_manager: LordManager = null
var fief_recruitment_manager: FiefRecruitmentManager = FiefRecruitmentManager.new()
var adventurer_recruitment_manager: AdventurerRecruitmentManager = \
	AdventurerRecruitmentManager.new()
## 全地图雇佣兵池的唯一所有者：生成、酒馆分配、流动、玩家/NPC 招募与存档。
var mercenary_manager: MercenaryManager = MercenaryManager.new()
## 俘虏恢复与玩家被俘/逃脱：世界 tick 驱动的唯一结算入口。
var captivity_manager: CaptivityManager = CaptivityManager.new()
var vision_manager: VisionManager = VisionManager.new()
var world_map_manager: WorldMapManager = WorldMapManager.new()
var encounter_manager: EncounterManager = EncounterManager.new()
var world_log_manager: WorldLogManager = WorldLogManager.new()
var ai_manager: AIManager = AIManager.new()
var battle_manager: BattleManager = BattleManager.new()
var dialogue_manager: DialogueManager = DialogueManager.new()
## 事件中心是只读聚合层：事件由现有系统状态实时推导，不保存独立副本。
var event_center = EventCenterScript.new()
var world_simulation: WorldSimulation = WorldSimulation.new()

var world_id: String = ""
var world_created_at: String = ""
var world_size: Vector2 = DEFAULT_WORLD_SIZE
## 地图布局静态定义；只读，不进入存档。
var world_map_definition: WorldMapDefinition = null
## 边界/湖泊/山脉寻路；仅新地图尺寸启用，旧存档为 null。
var world_terrain: WorldTerrain = null
var player_party_id: String = ""
## 玩家领主身份（封地所有权）与玩家角色 UnitData 是两个独立 ID。
var player_lord_id: String = ""
## 玩家所属家族；玩家本质上是贵族家族体系中的一员。
## 平民身份为空：玩家身份与家族归属分离，不创建临时家族。
var player_house_id: String = ""
## 新游戏身份选择结果；平民身份没有家族，但仍保留身份 ID/类型/文化。
var player_identity_id: String = ""
var player_identity_category_id: String = ""
var player_culture_id: String = ""
## 身份显示名只用于 UI；从身份配置解析，不参与规则判断。
var player_identity_name: String = ""
var player_unit_id: String = ""
var player_profile: PlayerProfile = PlayerProfile.new()

var _static_configs_registered: bool = false


func _ready() -> void:
	_wire_managers()
	register_static_configs()
	_load_world_map_definition()
	_register_king_appearance_override()
	_register_noble_appearance_override()
	if not TimeManager.world_tick.is_connected(world_simulation.on_world_tick):
		TimeManager.world_tick.connect(world_simulation.on_world_tick)
	if not EventBus.battle_finished.is_connected(_on_battle_finished):
		EventBus.battle_finished.connect(_on_battle_finished)


func _exit_tree() -> void:
	UnitAppearance.clear_king_helmet_override(self)
	UnitAppearance.clear_noble_helmet_override(self)
	world_log_manager.dispose()
	if TimeManager.world_tick.is_connected(world_simulation.on_world_tick):
		TimeManager.world_tick.disconnect(world_simulation.on_world_tick)
	if EventBus.battle_finished.is_connected(_on_battle_finished):
		EventBus.battle_finished.disconnect(_on_battle_finished)


func _load_world_map_definition() -> void:
	if world_map_definition != null:
		return
	if not ResourceLoader.exists(WORLD_MAP_DEFINITION_PATH):
		push_warning("大地图定义不存在: %s" % WORLD_MAP_DEFINITION_PATH)
		return
	world_map_definition = load(WORLD_MAP_DEFINITION_PATH) as WorldMapDefinition
	if world_map_definition == null:
		push_error("无法加载大地图定义: %s" % WORLD_MAP_DEFINITION_PATH)


## 按世界尺寸装配地形。只有新地图尺寸才启用真实边界/湖泊/山脉寻路；
## 旧存档尺寸不匹配时回退到矩形边界与直线移动，不重写任何存档数据。
func setup_world_terrain(target_world_size: Vector2) -> bool:
	_load_world_map_definition()
	world_map_manager.world_bounds = Rect2(Vector2.ZERO, target_world_size)
	if world_map_definition == null \
			or target_world_size != world_map_definition.get_world_size():
		world_terrain = null
		world_map_manager.bind_terrain(null)
		return false
	if world_terrain == null:
		world_terrain = WorldTerrain.new()
		if not world_terrain.build(world_map_definition):
			push_error("大地图地形构建失败")
			world_terrain = null
			world_map_manager.bind_terrain(null)
			return false
	world_map_manager.bind_terrain(world_terrain)
	return true


## 国王盔覆盖只依赖静态外观配置与当前政治身份，由本世界显式注册。
func _register_king_appearance_override() -> void:
	var texture_path: String = appearance_config.king_helmet_texture_path \
		if appearance_config != null else ""
	UnitAppearance.configure_king_helmet_override(
		self, texture_path, Callable(self, "is_king_unit")
	)


## 贵族文化头盔覆盖：静态配置给出“文化 → 贴图”，本世界提供只读文化解析。
func _register_noble_appearance_override() -> void:
	var texture_paths: Dictionary = (
		appearance_config.noble_culture_helmet_texture_paths
		if appearance_config != null else {}
	)
	UnitAppearance.configure_noble_helmet_override(
		self, texture_paths, Callable(self, "get_noble_culture_id")
	)


## 贵族判定：NPC 领袖单位由 noble_id 标记；玩家角色由玩家贵族记录承担。
func is_noble_unit(unit: UnitData) -> bool:
	if unit == null:
		return false
	if not unit.noble_id.is_empty():
		return noble_manager.get_noble(unit.noble_id) != null
	return unit.is_player_character and not player_lord_id.is_empty()


## 贵族文化：玩家角色优先使用身份保存的文化；其他贵族读取家族静态 culture_id。
## 非贵族单位一律返回空，避免普通士兵命中贵族专属头盔。
func get_noble_culture_id(unit: UnitData) -> String:
	if not is_noble_unit(unit):
		return ""
	if unit.is_player_character and not player_culture_id.is_empty():
		return player_culture_id
	var family_id: String = unit.family_id
	if family_id.is_empty() and not unit.noble_id.is_empty():
		var noble: NobleData = noble_manager.get_noble(unit.noble_id)
		if noble != null:
			var house := house_manager.get_house(noble.house_id)
			if house != null:
				family_id = house.banner_id
	if family_id.is_empty():
		return ""
	var family := family_registry.get_config(family_id)
	return family.culture_id if family != null else ""


## 单位当前是否具有国王身份。只读取现有政治数据，不修改任何状态：
## 家族领袖 + 王国统治家族 + 国王标记 + 王国仍有效。
func is_king_unit(unit: UnitData) -> bool:
	if unit == null:
		return false
	var noble_id: String = unit.noble_id
	# 玩家角色单位本身没有 noble_id；身份统一由玩家贵族承担。
	if noble_id.is_empty() and unit.is_player_character:
		noble_id = player_lord_id
	return is_king_noble(noble_id)


func is_king_noble(noble_id: String) -> bool:
	if noble_id.is_empty():
		return false
	var noble := noble_manager.get_noble(noble_id)
	if noble == null or not noble.alive or not noble.is_king:
		return false
	if noble.house_id.is_empty():
		return false
	var house := house_manager.get_house(noble.house_id)
	if house == null or house.leader_noble_id != noble_id:
		return false
	var kingdom := kingdom_manager.get_kingdom_for_house(house.house_id)
	if kingdom == null or not kingdom.is_active:
		return false
	return kingdom.ruling_house_id == house.house_id \
		and kingdom.king_noble_id == noble_id


func get_player_party() -> PartyData:
	return party_manager.get_party(player_party_id)


func get_player_lord() -> LordData:
	var noble := get_player_noble()
	return noble


func get_player_noble() -> NobleData:
	var noble: NobleData = noble_manager.get_noble(player_lord_id)
	if noble != null:
		return noble
	return noble_manager.get_player_noble()


func get_player_house() -> HouseData:
	var noble := get_player_noble()
	if noble != null and not noble.house_id.is_empty():
		return house_manager.get_house(noble.house_id)
	return house_manager.get_player_house()


## 平民身份：身份选择明确为 COMMONER，不创建家族/贵族记录。
## 旧存档没有身份字段时返回 false，保持旧的玩家贵族恢复逻辑。
func is_player_commoner() -> bool:
	return player_identity_category_id == "COMMONER"


func get_player_identity_name() -> String:
	return player_identity_name


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


## 玩家当前拥有的全部封地。所有权规则与征召授权共用同一判断：
## 玩家贵族所属家族等于领地 owner_house_id 即视为家族领地。
func get_player_owned_settlements() -> Array[SettlementData]:
	var result: Array[SettlementData] = []
	var noble := get_player_noble()
	if noble == null:
		return result
	for settlement: SettlementData in settlement_manager.get_all_settlements():
		if settlement == null:
			continue
		if fief_recruitment_manager.is_authorized_owner(settlement, noble.lord_id):
			result.append(settlement)
	return result


## 下一游戏日的预计收支预览。只复用现有税收缓存与工资统计，不执行结算。
## items 中收入为正、支出为负；顺序为支出在前、收入在后。
func get_daily_balance_preview() -> Dictionary:
	var items: Array[Dictionary] = []
	var expense_total: int = 0
	var income_total: int = 0

	var wage: int = party_manager.get_total_wage(player_party_id) \
		if not player_party_id.is_empty() else 0
	if wage > 0:
		items.append({"label": "部队工资", "amount": -wage})
		expense_total += wage

	for settlement: SettlementData in get_player_owned_settlements():
		if settlement.tax_income_per_day <= 0:
			continue
		items.append({
			"label": "%s税收" % settlement.display_name,
			"amount": settlement.tax_income_per_day,
		})
		income_total += settlement.tax_income_per_day

	return {
		"income_total": income_total,
		"expense_total": expense_total,
		"net": income_total - expense_total,
		"items": items,
	}


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
		if settlement == null:
			continue
		# 领地只校验家族所有权；个人所有者字段不再参与现行数据。
		if not settlement.owner_house_id.is_empty():
			if house_manager.get_house(settlement.owner_house_id) == null:
				errors.append(
					"地点 %s 引用了不存在的家族 %s"
					% [settlement.settlement_id, settlement.owner_house_id]
				)
	if not player_lord_id.is_empty():
		var player_noble: NobleData = noble_manager.get_noble(player_lord_id)
		if player_noble == null or not player_noble.is_player_lord:
			errors.append("玩家贵族 ID %s 无效" % player_lord_id)
	if not player_house_id.is_empty():
		var player_house := house_manager.get_house(player_house_id)
		if player_house == null or not player_house.is_player_house:
			errors.append("玩家家族 ID %s 无效" % player_house_id)
	# 部队→贵族→家族链路必须一致，不允许悬空引用。
	for party: PartyData in party_manager.get_all_parties():
		if party == null or party.leader_noble_id.is_empty():
			continue
		var leader := noble_manager.get_noble(party.leader_noble_id)
		if leader == null:
			errors.append(
				"部队 %s 引用了不存在的贵族 %s"
				% [party.party_id, party.leader_noble_id]
			)
		elif leader.party_id != party.party_id:
			errors.append(
				"部队 %s 与贵族 %s 的指挥关系不一致"
				% [party.party_id, party.leader_noble_id]
			)
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
		"player_noble_id": player_lord_id,
		"player_house_id": player_house_id,
		"player_unit_id": player_unit_id,
		# 身份选择结果（增量可选字段）：旧存档缺失时为空，沿用旧恢复逻辑。
		"identity_id": player_identity_id,
		"identity_category_id": player_identity_category_id,
		"culture_id": player_culture_id,
		"identity_name": player_identity_name,
	}
	# 金币、堆叠物品与独立马匹实例都由 PlayerProfile 统一序列化。
	var profile_payload: Dictionary = player_profile.to_dict()
	for key: Variant in profile_payload:
		save.player[key] = profile_payload[key]
	save.supply_last_settled_day = supply_manager.last_settled_day
	save.healing_last_settled_hour = wounded_healing_manager.last_settled_hour
	save.world_state = {}
	save.scene_state = {}
	save.world_log = world_log_manager.to_dict()
	save.units = unit_manager.to_dict()
	save.parties = party_manager.to_dict()
	save.settlements = settlement_manager.to_dict()
	save.markets = market_manager.to_dict()
	save.ransoms = lord_ransom_manager.to_dict()
	save.mercenaries = mercenary_manager.to_dict()
	save.captivity = captivity_manager.to_dict()
	save.nobles = noble_manager.to_dict()
	# v4 兼容字段：旧读取方仍然可以只读 lords，但内容已经是完整贵族数据。
	save.lords = save.nobles.duplicate(true)
	save.houses = house_manager.to_dict()
	save.kingdoms = kingdom_manager.to_dict()
	# 玩家主动宣战产生的个人敌对关系；静态阵营关系仍由 FactionManager 重建。
	save.factions = faction_manager.to_dict()
	save.quests = {}
	return save


## 战斗结算完成后的世界侧收尾：
## 1. 移除已无任何成员的部队（仅剩伤兵的部队保留，等待治疗恢复）；
## 2. 清理其他部队指向被消灭部队的目标/追随引用；
## 3. 以“玩家角色是否被关押”同步被俘状态。
func _on_battle_finished(_battle_id: String, _result: int) -> void:
	_cleanup_defeated_parties()
	captivity_manager.sync_player_capture()


func _cleanup_defeated_parties() -> void:
	var destroyed: Dictionary = {}
	for party: PartyData in party_manager.get_all_parties():
		if party == null or party.party_id == player_party_id:
			continue
		# 仍有成员（包括伤兵）的部队按既有规则继续存在。
		if not party.member_unit_ids.is_empty():
			continue
		destroyed[party.party_id] = true
	if destroyed.is_empty():
		return

	for party_id_value: Variant in destroyed:
		var party_id: String = str(party_id_value)
		var party := party_manager.get_party(party_id)
		if party == null:
			continue
		var prisoner_ids: Array[String] = party.prisoner_unit_ids.duplicate()
		for unit_id: String in prisoner_ids:
			var unit := unit_manager.get_unit(unit_id)
			# 玩家俘虏由 CaptivityManager 负责获释/重建部队；
			# 这里只解除归属，绝不删除玩家角色。
			if unit != null and unit.is_player_character:
				party_manager.remove_prisoner(party_id, unit_id)
			else:
				_release_destroyed_party_prisoner(unit_id)
		# 整支部队覆灭时，其指挥贵族不再拥有可用部队；
		# 贵族是否死亡由既有贵族/赎买流程决定，清理本身不改写存活状态。
		if not party.leader_noble_id.is_empty():
			var noble := noble_manager.get_noble(party.leader_noble_id)
			if noble != null and not noble.is_player_lord \
					and noble.party_id == party.party_id:
				noble.party_id = ""
		party_manager.remove_party(party_id)

	_clear_destroyed_party_references(destroyed)


func _release_destroyed_party_prisoner(unit_id: String) -> void:
	var unit := unit_manager.get_unit(unit_id)
	if unit == null:
		return
	unit.clear_prisoner_ownership()
	if not unit.current_party_id.is_empty():
		party_manager.remove_member(unit.current_party_id, unit_id)
	unit_manager.remove_unit(unit_id)


## 其他部队不得继续追击/跟随已不存在的部队。
func _clear_destroyed_party_references(destroyed: Dictionary) -> void:
	for party: PartyData in party_manager.get_all_parties():
		if party == null:
			continue
		if destroyed.has(party.current_target_id):
			party.current_target_id = ""
			party.attack_intent = false
			if party.current_order == PartyData.OrderType.FOLLOW_PARTY:
				party.current_order = PartyData.OrderType.NONE
				party.movement_state = PartyData.MovementState.IDLE
				party.target_position = party.world_position
		if destroyed.has(party.focus_party_id):
			party.focus_party_id = ""


## 旧存档迁移：只给完全没有补给记录的部队补起始物资，避免开局立即全员缺粮。
## 已有任意物品或金币的部队视为玩家/NPC 自己管理过补给，不再补发。
func _migrate_party_supplies() -> void:
	var player_party := party_manager.get_party(player_party_id)
	if player_party != null:
		var player_members: int = supply_manager.get_member_count(player_party)
		if player_members > 0 \
				and player_profile.get_item_count(SupplyManager.BREAD_ID) <= 0:
			player_profile.add_item(
				SupplyManager.BREAD_ID, player_members * MIGRATION_SUPPLY_DAYS
			)
		var player_mounts: int = supply_manager.get_total_mount_count(player_party)
		if player_mounts > 0 \
				and player_profile.get_item_count(SupplyManager.FODDER_ID) <= 0:
			player_profile.add_item(
				SupplyManager.FODDER_ID, player_mounts * MIGRATION_SUPPLY_DAYS
			)

	for party: PartyData in party_manager.get_all_parties():
		if party == null or party.is_player_controlled() \
				or party.party_id == player_party_id:
			continue
		# 强盗没有稳定经济来源，不补发补给与资金。
		if party.party_kind == PartyData.PartyKind.BANDIT:
			continue
		if not party.inventory_data.stackable_counts.is_empty() or party.gold > 0:
			continue
		var members: int = maxi(1, party.member_unit_ids.size())
		party.add_item(
			SupplyManager.BREAD_ID, members * MIGRATION_SUPPLY_DAYS
		)
		var mounts: int = supply_manager.get_total_mount_count(party)
		if mounts > 0:
			party.add_item(
				SupplyManager.FODDER_ID, mounts * MIGRATION_SUPPLY_DAYS
			)
		party.gold = MIGRATION_NPC_GOLD


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
	player_lord_id = str(
		save.player.get("player_noble_id", save.player.get("player_lord_id", ""))
	)
	player_house_id = str(save.player.get("player_house_id", ""))
	player_identity_id = str(save.player.get("identity_id", ""))
	player_identity_category_id = str(save.player.get("identity_category_id", ""))
	player_culture_id = str(save.player.get("culture_id", ""))
	player_identity_name = str(save.player.get("identity_name", ""))
	player_unit_id = str(save.player.get("player_unit_id", ""))
	# 原地更新，保持 BattleManager 持有的 profile 引用一致。
	var loaded_profile: PlayerProfile = PlayerProfile.from_dict(save.player)
	player_profile.restore_from(loaded_profile)
	ai_manager.player_party_id = player_party_id
	supply_manager.set_player_party_id(player_party_id)
	battle_manager.player_party_id = player_party_id
	captivity_manager.set_player_party_id(player_party_id)

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
	# 阶段 13：俘虏与成员互斥；旧存档没有俘虏字段，校正为幂等操作。
	var prisoner_notes: Array[String] = party_manager.sanitize_prisoner_ownership()
	for message: String in prisoner_notes:
		print("[WorldContext] %s" % message)
	# v5 读取 nobles；v4 存档没有 nobles 时回退到 lords。
	var noble_payload: Dictionary = save.nobles if not save.nobles.is_empty() \
		else save.lords
	noble_manager.load_from_dict(noble_payload)
	settlement_manager.load_from_dict(save.settlements)
	# 旧存档没有 map_key / 特产 / 户数：按稳定 key 或名称补齐，不覆盖已有值。
	if village_specialty_config != null:
		for settlement: SettlementData in settlement_manager.get_all_settlements():
			village_specialty_config.apply_defaults(settlement)
	# 市场库存按村庄/城镇独立恢复；旧存档缺失时 ensure_markets() 只补初始库存。
	market_manager.load_from_dict(save.markets)
	if not market_manager.ensure_markets():
		push_error("[WorldContext] 村庄/城镇市场库存初始化失败")
	# 补给结算日按存档恢复；旧存档没有该字段时以存档时刻所在游戏日为起点，
	# 避免读档后立刻重复扣粮，也不会把读档前已结算的那一天再扣一次。
	var settled_day: int = save.supply_last_settled_day
	if settled_day < 0:
		settled_day = int(TimeManager.get_date_parts(
			save.world_elapsed_seconds
		)["total_days"])
	supply_manager.last_settled_day = settled_day
	# 伤兵治疗按游戏小时结算；旧存档没有记录时以存档时刻为起点。
	wounded_healing_manager.restore_settled_hour(
		save.healing_last_settled_hour, save.world_elapsed_seconds
	)
	# v6 之前没有 NPC 背包/资金与玩家补给；只在升级旧存档时补一次。
	if save.schema_version < 6:
		_migrate_party_supplies()
	house_manager.load_from_dict(save.houses)
	kingdom_manager.load_from_dict(save.kingdoms)
	# v10 之前没有该字段：视为玩家没有个人宣战记录，保持空表。
	faction_manager.load_from_dict(save.factions)
	world_log_manager.load_from_dict(save.world_log)
	# 新地图尺寸装配真实地形；旧存档尺寸回退到矩形边界与直线移动。
	setup_world_terrain(world_size)

	# v4 -> v5：补齐缺失的家族、贵族归属、部队指挥关系与领袖。
	_migrate_political_data()
	# 旧存档没有 UnitData.noble_id，但部队领袖关系是稳定的；读档后回填。
	_backfill_noble_unit_ids()
	# v8：赎回记录在实体/家族恢复后载入，失效记录不会重新生成事件。
	lord_ransom_manager.load_from_dict(save.ransoms)
	# v10：俘虏恢复/逃脱计时与保护期按存档恢复；玩家被俘状态在全部实体
	# 恢复并校验后再以实际归属为准做一次校正。
	captivity_manager.load_from_dict(save.captivity, save.world_elapsed_seconds)

	# 旧存档没有贵族数据时，至少恢复玩家贵族身份；不伪造封地归属。
	# 平民新存档（带身份字段）明确不创建贵族，读档不得补成贵族。
	var player_noble: NobleData = noble_manager.get_noble(player_lord_id)
	if player_noble == null:
		player_noble = noble_manager.get_player_noble()
	if player_noble == null and not is_player_commoner() \
			and party_manager.get_party(player_party_id) != null:
		var player_house := get_player_house()
		player_noble = noble_manager.create_noble(
			"玩家领主",
			party_manager.get_party(player_party_id).faction_id,
			player_party_id,
			player_house.house_id if player_house != null else player_house_id,
			NobleData.Rank.KNIGHT,
			true,
			player_house != null and not player_house.has_leader()
		)
	player_lord_id = player_noble.lord_id if player_noble != null else ""
	player_house_id = player_noble.house_id if player_noble != null else player_house_id
	if not player_house_id.is_empty():
		var loaded_player_house := house_manager.get_house(player_house_id)
		if loaded_player_house != null:
			loaded_player_house.is_player_house = true
	if player_unit_id.is_empty():
		var player_unit: UnitData = get_player_unit()
		player_unit_id = player_unit.unit_id if player_unit != null else ""
	adventurer_recruitment_manager.player_party_id = player_party_id
	mercenary_manager.set_player_party_id(player_party_id)
	house_manager.refresh_settlement_links()

	# 雇佣兵池在城镇与部队恢复后载入；旧存档没有该字段时只初始化一次，
	# 已初始化存档不会重复生成或重复发放。
	mercenary_manager.load_from_dict(save.mercenaries)
	if not mercenary_manager.is_initialized():
		mercenary_manager.initialize_world(true)

	# 采邑容量/税收与候选人生成都来自同一经济配置；读档只修正边界，
	# 不覆盖存档中的储备与刷新计时。
	for settlement: SettlementData in settlement_manager.get_all_settlements():
		fief_recruitment_manager.initialize_settlement(settlement)
		adventurer_recruitment_manager.initialize_settlement(settlement, false)

	# 读档以当前静态配置、持久化等级与装备为准重算最终属性；
	# 无效装备引用会在 UnitManager 中报告并清理，不会静默生成错误属性。
	# 先校正五级制经验/等级，确保旧存档不会卡在无效等级。
	unit_manager.normalize_combat_progression()
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

	# 俘虏/逃脱状态不信任过期引用：押送部队不存在时自动获释并重建玩家部队。
	captivity_manager.validate_after_load()
	return is_valid_world()


## 旧存档缺少 UnitData.noble_id 时，按部队领袖关系回填。
## 玩家部队/玩家角色不参与 NPC 领主身份，避免玩家角色被当作可赎回领主。
func _backfill_noble_unit_ids() -> void:
	for party: PartyData in party_manager.get_all_parties():
		if party == null or party.is_player_controlled():
			continue
		var leader := unit_manager.get_unit(party.leader_unit_id)
		if leader == null or leader.is_player_character:
			continue
		if party.leader_noble_id.is_empty() and not leader.noble_id.is_empty():
			party.leader_noble_id = leader.noble_id
		elif not party.leader_noble_id.is_empty() and leader.noble_id.is_empty():
			leader.noble_id = party.leader_noble_id


## v4 -> v5 兼容迁移：旧存档只有领主与 family_id，没有独立家族/贵族层级。
## 只补齐可从现有数据确定的关系，不伪造王国、爵位或封地归属。
func _migrate_political_data() -> void:
	var family_ids: Array[String] = []
	for party: PartyData in party_manager.get_all_parties():
		if party != null and not party.family_id.is_empty() \
				and not family_ids.has(party.family_id):
			family_ids.append(party.family_id)
	for settlement: SettlementData in settlement_manager.get_all_settlements():
		if settlement == null:
			continue
		for family_id: String in [settlement.family_id, settlement.owner_house_id]:
			if not family_id.is_empty() and not family_ids.has(family_id):
				family_ids.append(family_id)
	for noble: NobleData in noble_manager.get_all_nobles():
		if not noble.house_id.is_empty() and not family_ids.has(noble.house_id):
			family_ids.append(noble.house_id)

	for family_id: String in family_ids:
		if _resolve_house_id_for_family(family_id).is_empty():
			var family := family_registry.get_config(family_id)
			var house_name: String = family.display_name if family != null else family_id
			var is_player_house: bool = family_id == player_house_id
			for party: PartyData in party_manager.get_all_parties():
				if party != null and party.is_player_controlled() \
						and party.family_id == family_id:
					is_player_house = true
					break
			# 旧存档没有独立家族数据时，才以视觉家族 ID 创建家族。
			house_manager.register_house(
				family_id, house_name, family_id, is_player_house
			)

	for noble: NobleData in noble_manager.get_all_nobles():
		if noble.house_id.is_empty():
			var party := party_manager.get_party(noble.party_id)
			if party != null and not party.family_id.is_empty():
				var house_id := _resolve_house_id_for_family(party.family_id)
				if not house_id.is_empty():
					house_manager.attach_noble(house_id, noble)
		else:
			var house := house_manager.get_house(noble.house_id)
			if house != null and not house.noble_ids.has(noble.lord_id):
				house.noble_ids.append(noble.lord_id)

	for party: PartyData in party_manager.get_all_parties():
		if party == null:
			continue
		if party.leader_noble_id.is_empty():
			var party_noble := noble_manager.get_noble_by_party_id(party.party_id)
			if party_noble != null:
				party.leader_noble_id = party_noble.lord_id
		if not party.leader_noble_id.is_empty():
			var leader := noble_manager.get_noble(party.leader_noble_id)
			if leader != null:
				leader.party_id = party.party_id

	for house: HouseData in house_manager.get_all_houses():
		house_manager.ensure_leader(house.house_id)

	for settlement: SettlementData in settlement_manager.get_all_settlements():
		if settlement == null:
			continue
		# 旧存档个人所有者 → 家族所有权；迁移后清空私有输入字段。
		if not settlement._legacy_owner_noble_id.is_empty():
			var legacy_owner := noble_manager.get_noble(
				settlement._legacy_owner_noble_id
			)
			if legacy_owner != null and settlement.owner_house_id.is_empty():
				settlement.owner_house_id = legacy_owner.house_id
			settlement._legacy_owner_noble_id = ""
		# 更早的存档完全没有所有权字段时，才以视觉家族兜底；
		# 新游戏/新存档的无主地点（family_id 为空）不会被补写。
		if settlement.owner_house_id.is_empty() \
				and not settlement.family_id.is_empty():
			settlement.owner_house_id = _resolve_house_id_for_family(
				settlement.family_id
			)
	house_manager.refresh_settlement_links()


## 视觉家族 ID（FamilyRegistry.family_id）→ 政治家族 ID。
## 优先直接匹配 house_id，其次通过 banner_id 映射。
func _resolve_house_id_for_family(family_id: String) -> String:
	if family_id.is_empty() or house_manager == null:
		return ""
	if house_manager.has_house(family_id):
		return family_id
	var house := house_manager.get_house_by_banner_id(family_id)
	return house.house_id if house != null else ""


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

	# 市场商品必须在装备/物品配置之后注册，才能校验 item_id 引用。
	for path: String in _list_resource_paths(MARKET_GOODS_CONFIG_DIR):
		var goods_config := load(path) as MarketGoodsConfig
		if goods_config == null:
			push_error("无法加载市场商品配置: %s" % path)
			success = false
			continue
		if not market_manager.register_goods_config(goods_config):
			push_error("市场商品配置注册失败: %s" % path)
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

	village_specialty_config = load(
		VILLAGE_SPECIALTY_CONFIG_PATH
	) as VillageSpecialtyConfig
	if village_specialty_config == null:
		push_warning(
			"无法加载村庄特产配置，村庄将没有特产: %s"
			% VILLAGE_SPECIALTY_CONFIG_PATH
		)

	appearance_config = load(APPEARANCE_CONFIG_PATH) as AppearanceConfig
	if appearance_config == null:
		push_error("无法加载外观配置: %s" % APPEARANCE_CONFIG_PATH)
		success = false
	fief_recruitment_manager.set_appearance_config(appearance_config)
	adventurer_recruitment_manager.set_appearance_config(appearance_config)
	mercenary_manager.set_appearance_config(appearance_config)

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

	if recruitment_config == null:
		recruitment_config = load(RECRUITMENT_CONFIG_PATH) as RecruitmentConfig
		if recruitment_config == null:
			push_warning(
				"无法加载招募配置，使用脚本默认值: %s" % RECRUITMENT_CONFIG_PATH
			)
			recruitment_config = RecruitmentConfig.new()
	recruitment_config.sanitize()

	unit_manager.setup(id_generator)
	party_manager.setup(unit_manager, id_generator)
	settlement_manager.setup(id_generator)
	# 政治层级：贵族 → 家族 → 王国；lord_manager 与 noble_manager 共用同一仓储。
	noble_manager.setup(id_generator, party_manager)
	lord_manager = noble_manager
	house_manager.setup(id_generator, noble_manager, settlement_manager)
	kingdom_manager.setup(id_generator, house_manager, noble_manager)
	noble_manager.setup_political(house_manager, kingdom_manager)
	house_manager.setup_political(kingdom_manager)
	faction_manager.setup_defaults()
	faction_manager.setup_political(
		party_manager,
		noble_manager,
		house_manager,
		kingdom_manager,
		settlement_manager
	)
	vision_manager.setup(party_manager, faction_manager, unit_manager)
	world_map_manager.setup(party_manager, vision_manager)
	battle_manager.setup(
		unit_manager, party_manager, id_generator, faction_manager, player_profile
	)
	# 负伤概率来自集中配置；缺失时保持关闭（阵亡即永久死亡），不散落硬编码。
	if ResourceLoader.exists(BattleManager.WOUNDED_CONFIG_PATH):
		var wounded_config := load(
			BattleManager.WOUNDED_CONFIG_PATH
		) as WoundedConfig
		if wounded_config != null:
			battle_manager.set_wounded_config(wounded_config)
	encounter_manager.setup(
		party_manager, faction_manager, battle_manager, world_map_manager
	)
	world_log_manager.setup(battle_manager, party_manager, settlement_manager)
	# 市场交易是玩家物品/金币变动的唯一业务入口；日志只记录玩家来源交易。
	market_manager.setup(
		settlement_manager, unit_manager, item_manager, world_log_manager
	)
	slaughter_manager.setup(item_manager)
	# 玩家补给使用 PlayerProfile，NPC 使用自己的 PartyData 背包；规则完全一致。
	supply_manager.setup(
		party_manager, unit_manager, player_profile, player_party_id
	)
	wounded_healing_manager.setup(party_manager, unit_manager)
	# 俘虏恢复与玩家逃脱独立于伤兵治疗，只按 WorldTime 推进。
	captivity_manager.setup(unit_manager, party_manager, world_map_manager)
	captivity_manager.set_player_party_id(player_party_id)
	ai_manager.set_captivity_manager(captivity_manager)
	encounter_manager.set_captivity_manager(captivity_manager)
	# 赎回流程只登记出售后的等待与请求；实际出售仍由 PrisonerTradeManager 原子完成。
	lord_ransom_manager.setup(
		self,
		unit_manager,
		party_manager,
		noble_manager,
		house_manager,
		settlement_manager,
		id_generator,
		player_profile,
		world_log_manager
	)
	prisoner_trade_manager.setup(
		party_manager, unit_manager, player_profile, null, lord_ransom_manager
	)
	# 世界日志在所有管理者装配后接入，避免初始化阶段产生不完整日志。
	noble_manager.setup_political(house_manager, kingdom_manager, world_log_manager)
	house_manager.setup_political(kingdom_manager, world_log_manager)
	kingdom_manager.set_world_log_manager(world_log_manager)
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
		economy_config,
		fief_recruitment_manager,
		recruitment_config
	)
	mercenary_manager.setup(
		unit_manager,
		party_manager,
		settlement_manager,
		noble_manager,
		id_generator,
		recruitment_config,
		family_registry,
		appearance_config
	)
	mercenary_manager.set_player_party_id(player_party_id)
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
		economy_config,
		supply_manager,
		market_manager,
		adventurer_recruitment_manager
	)
	world_simulation.bind(
		unit_manager,
		party_manager,
		world_map_manager,
		ai_manager,
		battle_manager,
		encounter_manager,
		fief_recruitment_manager,
		adventurer_recruitment_manager,
		supply_manager,
		wounded_healing_manager,
		lord_ransom_manager,
		mercenary_manager,
		captivity_manager,
		market_manager
	)
	event_center.setup(self)
