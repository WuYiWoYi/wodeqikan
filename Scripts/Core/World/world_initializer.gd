class_name WorldInitializer
extends RefCounted
## Milestone 1 的世界初始化数据。
##
## 只填充 WorldContext 中的权威数据；不创建任何场景节点。

const PLAYER_FACTION_ID: String = "FACTION_PLAYER"
const LOCAL_FACTION_ID: String = "FACTION_LOCAL"
const MERCHANT_FACTION_ID: String = "FACTION_MERCHANT"
const BANDIT_FACTION_ID: String = "FACTION_BANDIT"
const GUARD_FACTION_ID: String = "FACTION_GUARD"

const PLAYER_START_POSITION: Vector2 = Vector2(760.0, 620.0)
const PLAYER_MOVE_SPEED: float = 150.0
const PLAYER_SIGHT_RANGE: float = 300.0

## 阶段 4 优化的 NPC 速度关系：治安队 > 强盗 > 商队。
## 旧存档通过 PartyData.movement_speed 保留原速度，不会在这里被重置。
const MERCHANT_MOVE_SPEED: float = 80.0
const GUARD_MOVE_SPEED: float = 120.0
const BANDIT_MOVE_SPEED: float = 100.0
const NPC_SIGHT_RANGE: float = 250.0
const GUARD_SIGHT_RANGE: float = 300.0
const BANDIT_SIGHT_RANGE: float = 320.0

## 临时测试兵力。后续由招募/部队初始化系统替换。
const TEST_FORCE_SOURCE: String = "milestone2_test"
const MILITIA_CONFIG_PATH: String = "res://Data/Units/infantry_militia.tres"
const TRAINED_CONFIG_PATH: String = "res://Data/Units/infantry_trained.tres"
const PLAYER_HERO_CONFIG_PATH: String = "res://Data/Units/player_hero.tres"
const TEST_MILITIA_COUNT: int = 3
const TEST_TRAINED_COUNT: int = 2
## 玩家部队：3 民兵 + 3 职业步兵（全部装备马匹）+ 1 玩家角色。
## 相比上一阶段新增 2 名骑乘测试士兵；不新增骑兵兵种 ID。
const PLAYER_TRAINED_COUNT: int = 3
const TEST_MOUNT_ID: String = "mount_horse_01"
## 3 匹装备给测试骑兵，额外 1 匹留在背包，便于验证“上马/下马”。
const TEST_MOUNT_STOCK: int = PLAYER_TRAINED_COUNT + 1
const TEST_PROMOTION_ITEM_ID: String = "promotion_rank_token"
## 临时测试库存，便于验证晋升流程；正式获取途径后续实现。
const TEST_PROMOTION_ITEM_STOCK: int = 2
const TEST_ENEMY_PARTY_NAME: String = "河畔商队"
const GUARD_PARTY_NAME: String = "北境巡逻队"
const BANDIT_PARTY_NAME: String = "山道强盗"

## 初期所有村庄共用同一基础模板；每个 SettlementData 单独保存 scene_path，
## 后续可逐村替换为不同场景。
const DEFAULT_VILLAGE_SCENE_PATH: String = "res://Scenes/Village/village.tscn"


## 返回是否创建成功。
static func create_new_world(context: WorldContext) -> bool:
	if context == null:
		return false

	context.world_id = context.id_generator.next_id(IdGenerator.WORLD)
	context.world_created_at = Time.get_datetime_string_from_system()
	context.world_size = WorldContext.DEFAULT_WORLD_SIZE
	context.world_map_manager.world_bounds = Rect2(Vector2.ZERO, context.world_size)

	var player_party := context.party_manager.create_party(
		PLAYER_FACTION_ID, PLAYER_START_POSITION, "玩家部队"
	)
	if player_party == null:
		return false
	player_party.movement_speed = PLAYER_MOVE_SPEED
	player_party.sight_range = PLAYER_SIGHT_RANGE
	context.player_party_id = player_party.party_id
	context.ai_manager.player_party_id = player_party.party_id
	context.battle_manager.player_party_id = player_party.party_id

	var merchant_party := context.party_manager.create_party(
		MERCHANT_FACTION_ID, Vector2(900.0, 1500.0), TEST_ENEMY_PARTY_NAME
	)
	if merchant_party != null:
		merchant_party.movement_speed = MERCHANT_MOVE_SPEED
		merchant_party.sight_range = NPC_SIGHT_RANGE

	var guard_party := context.party_manager.create_party(
		GUARD_FACTION_ID, Vector2(2350.0, 1100.0), GUARD_PARTY_NAME
	)
	if guard_party != null:
		guard_party.movement_speed = GUARD_MOVE_SPEED
		guard_party.sight_range = GUARD_SIGHT_RANGE

	var bandit_party := context.party_manager.create_party(
		BANDIT_FACTION_ID, Vector2(1650.0, 900.0), BANDIT_PARTY_NAME
	)
	if bandit_party != null:
		bandit_party.movement_speed = BANDIT_MOVE_SPEED
		bandit_party.sight_range = BANDIT_SIGHT_RANGE

	var oak_village := _create_settlement(
		context, "橡木村", SettlementData.SettlementType.VILLAGE, Vector2(500.0, 500.0), 120, 40
	)
	var riverside_village := _create_settlement(
		context, "河畔村", SettlementData.SettlementType.VILLAGE, Vector2(1200.0, 900.0), 96, 35
	)
	var north_village := _create_settlement(
		context, "北境村", SettlementData.SettlementType.VILLAGE, Vector2(2200.0, 500.0), 80, 30
	)
	var grey_castle := _create_settlement(
		context, "灰石城堡", SettlementData.SettlementType.CASTLE, Vector2(1800.0, 1300.0), 0, 60
	)
	for village: SettlementData in [oak_village, riverside_village, north_village]:
		if village != null:
			village.scene_path = DEFAULT_VILLAGE_SCENE_PATH

	if merchant_party != null and oak_village != null and riverside_village != null:
		# 商队从橡木村路线起点出发，首次决策后前往河畔村。
		merchant_party.world_position = oak_village.world_position
		merchant_party.target_position = merchant_party.world_position
		merchant_party.movement_state = PartyData.MovementState.IDLE
		merchant_party.ai_type = PartyData.PartyAIType.TRADE_ROUTE
		merchant_party.ai_route_index = 0
		merchant_party.ai_route_settlement_ids = [
			oak_village.settlement_id,
			riverside_village.settlement_id,
		]
	if guard_party != null:
		guard_party.ai_type = PartyData.PartyAIType.GUARD
		guard_party.ai_route_index = 0
	if bandit_party != null:
		bandit_party.ai_type = PartyData.PartyAIType.BANDIT
		bandit_party.ai_route_index = 0
		bandit_party.target_position = bandit_party.world_position
		bandit_party.movement_state = PartyData.MovementState.IDLE
		if grey_castle != null and north_village != null:
			bandit_party.ai_route_settlement_ids = [
				grey_castle.settlement_id,
				north_village.settlement_id,
			]

	if not create_test_battle_forces(context):
		push_error("初始测试兵力生成失败")
		return false

	return context.is_valid_world()


## 调试用测试兵力：玩家 3 民兵 + 3 骑乘职业步兵 + 玩家角色；其余三方各 3 民兵 + 2 职业步兵。
## 复用已有 AI 部队，不额外创建部队；单位标记 recruit_source 便于识别和清理。
static func create_test_battle_forces(context: WorldContext) -> bool:
	if context == null:
		return false
	var militia: UnitConfig = load(MILITIA_CONFIG_PATH) as UnitConfig
	var trained: UnitConfig = load(TRAINED_CONFIG_PATH) as UnitConfig
	if militia == null or trained == null:
		push_error("测试兵力配置加载失败")
		return false

	var player_party := context.get_player_party()
	if player_party == null:
		push_error("测试兵力缺少玩家部队")
		return false
	if not _populate_player_party(context, player_party, militia, trained):
		return false

	var required_names: Array[String] = [
		TEST_ENEMY_PARTY_NAME,
		GUARD_PARTY_NAME,
		BANDIT_PARTY_NAME,
	]
	for party_name: String in required_names:
		var party := _find_party_by_name(context, party_name)
		if party == null:
			push_error("测试兵力找不到部队: %s" % party_name)
			return false
		if not _populate_test_party(
			context, party, party.faction_id, militia, trained
		):
			return false
	return true


static func _find_party_by_name(context: WorldContext, party_name: String) -> PartyData:
	for party: PartyData in context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


## 玩家部队：3 民兵 + 3 职业步兵（全部骑乘）+ 玩家角色（最后加入，保持 UI 默认选中民兵）。
static func _populate_player_party(
	context: WorldContext, party: PartyData, militia: UnitConfig, trained: UnitConfig
) -> bool:
	if not party.member_unit_ids.is_empty():
		return true
	var hero_config: UnitConfig = load(PLAYER_HERO_CONFIG_PATH) as UnitConfig
	if hero_config == null:
		push_error("玩家角色配置加载失败: %s" % PLAYER_HERO_CONFIG_PATH)
		return false

	var configs: Array[UnitConfig] = []
	for i: int in range(TEST_MILITIA_COUNT):
		configs.append(militia)
	for i: int in range(PLAYER_TRAINED_COUNT):
		configs.append(trained)
	configs.append(hero_config)

	# 测试用马匹/晋升物品库存：新游戏补齐到实际需要的数量，不修改正式经济系统。
	var current_mounts: int = context.player_profile.get_item_count(TEST_MOUNT_ID)
	if current_mounts < TEST_MOUNT_STOCK:
		context.player_profile.add_item(TEST_MOUNT_ID, TEST_MOUNT_STOCK - current_mounts)
	var current_tokens: int = context.player_profile.get_item_count(TEST_PROMOTION_ITEM_ID)
	if current_tokens < TEST_PROMOTION_ITEM_STOCK:
		context.player_profile.add_item(
			TEST_PROMOTION_ITEM_ID, TEST_PROMOTION_ITEM_STOCK - current_tokens
		)

	var mounted_count: int = 0
	for config: UnitConfig in configs:
		var unit := context.unit_manager.create_unit(config, PLAYER_FACTION_ID)
		if unit == null:
			return false
		unit.recruit_source = TEST_FORCE_SOURCE
		unit.origin_faction_id = PLAYER_FACTION_ID
		if not context.party_manager.add_member(party.party_id, unit.unit_id):
			push_error("玩家单位无法加入部队: %s" % party.party_id)
			return false

		# 所有玩家职业步兵都装备马匹：形成 3 名骑乘测试士兵，不新增骑兵兵种。
		if config.config_id == trained.config_id:
			if not context.unit_manager.equip_mount(
				unit.unit_id, TEST_MOUNT_ID, context.player_profile
			):
				push_error("玩家测试骑兵装备马匹失败: %s" % unit.unit_id)
				return false
			mounted_count += 1

	if mounted_count < PLAYER_TRAINED_COUNT:
		push_error(
			"玩家部队骑乘测试单位不足: %d/%d"
			% [mounted_count, PLAYER_TRAINED_COUNT]
		)
		return false
	return true


static func _populate_test_party(
	context: WorldContext,
	party: PartyData,
	faction_id: String,
	militia: UnitConfig,
	trained: UnitConfig
) -> bool:
	if not party.member_unit_ids.is_empty():
		return true

	var configs: Array[UnitConfig] = []
	for i: int in range(TEST_MILITIA_COUNT):
		configs.append(militia)
	for i: int in range(TEST_TRAINED_COUNT):
		configs.append(trained)

	for config: UnitConfig in configs:
		var unit := context.unit_manager.create_unit(config, faction_id)
		if unit == null:
			return false
		unit.recruit_source = TEST_FORCE_SOURCE
		unit.origin_faction_id = faction_id
		if not context.party_manager.add_member(party.party_id, unit.unit_id):
			push_error("测试单位无法加入部队: %s" % party.party_id)
			return false
	return true


static func _create_settlement(
	context: WorldContext,
	display_name: String,
	settlement_type: SettlementData.SettlementType,
	world_position: Vector2,
	population: int,
	prosperity: int
) -> SettlementData:
	return context.settlement_manager.create_settlement(
		display_name,
		settlement_type,
		world_position,
		LOCAL_FACTION_ID,
		population,
		prosperity
	)
