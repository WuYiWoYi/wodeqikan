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

	return context.is_valid_world()


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
