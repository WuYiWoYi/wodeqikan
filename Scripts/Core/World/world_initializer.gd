class_name WorldInitializer
extends RefCounted
## Milestone 1 的世界初始化数据。
##
## 只填充 WorldContext 中的权威数据；不创建任何场景节点。

const PLAYER_FACTION_ID: String = "FACTION_PLAYER"
const LOCAL_FACTION_ID: String = "FACTION_LOCAL"

const PLAYER_START_POSITION: Vector2 = Vector2(760.0, 620.0)
const PLAYER_MOVE_SPEED: float = 300.0
const PLAYER_SIGHT_RANGE: float = 300.0

const NPC_MOVE_SPEED: float = 220.0
const NPC_SIGHT_RANGE: float = 250.0

## Milestone 2 临时测试兵力。后续由招募/部队初始化系统替换。
const TEST_FORCE_SOURCE: String = "milestone2_test"
const MILITIA_CONFIG_PATH: String = "res://Data/Units/infantry_militia.tres"
const TRAINED_CONFIG_PATH: String = "res://Data/Units/infantry_trained.tres"
const TEST_MILITIA_COUNT: int = 3
const TEST_TRAINED_COUNT: int = 2
const TEST_ENEMY_PARTY_NAME: String = "河畔商队"


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

	var npc_one := context.party_manager.create_party(
		LOCAL_FACTION_ID, Vector2(900.0, 1500.0), "河畔商队"
	)
	if npc_one != null:
		npc_one.movement_speed = NPC_MOVE_SPEED
		npc_one.sight_range = NPC_SIGHT_RANGE

	var npc_two := context.party_manager.create_party(
		LOCAL_FACTION_ID, Vector2(2350.0, 1100.0), "北境巡逻队"
	)
	if npc_two != null:
		npc_two.movement_speed = NPC_MOVE_SPEED
		npc_two.sight_range = NPC_SIGHT_RANGE

	_create_settlement(
		context, "橡木村", SettlementData.SettlementType.VILLAGE, Vector2(500.0, 500.0), 120, 40
	)
	_create_settlement(
		context, "河畔村", SettlementData.SettlementType.VILLAGE, Vector2(1200.0, 900.0), 96, 35
	)
	_create_settlement(
		context, "北境村", SettlementData.SettlementType.VILLAGE, Vector2(2200.0, 500.0), 80, 30
	)
	_create_settlement(
		context, "灰石城堡", SettlementData.SettlementType.CASTLE, Vector2(1800.0, 1300.0), 0, 60
	)

	if not create_test_battle_forces(context):
		push_error("初始测试兵力生成失败")
		return false

	return context.is_valid_world()


## 调试用测试兵力：玩家 3 民兵 + 2 职业步兵，河畔商队同样配置。
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
	if not _populate_test_party(
		context, player_party, PLAYER_FACTION_ID, militia, trained
	):
		return false

	var enemy_party: PartyData = null
	for party: PartyData in context.party_manager.get_all_parties():
		if party.party_name == TEST_ENEMY_PARTY_NAME:
			enemy_party = party
			break
	if enemy_party == null:
		push_error("测试兵力找不到敌方部队: %s" % TEST_ENEMY_PARTY_NAME)
		return false
	return _populate_test_party(
		context, enemy_party, enemy_party.faction_id, militia, trained
	)


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
) -> void:
	context.settlement_manager.create_settlement(
		display_name,
		settlement_type,
		world_position,
		LOCAL_FACTION_ID,
		population,
		prosperity
	)
