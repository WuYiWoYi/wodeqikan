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

const FAMILY_BARI_ID: String = "FAMILY_BARI"
const FAMILY_MOXIXI_ID: String = "FAMILY_MOXIXI"
const FAMILY_PLAYER_ID: String = "FAMILY_PLAYER"
const FAMILY_BURKNANIA_ID: String = "FAMILY_BURKNANIA"
const FAMILY_OLIN_ID: String = "FAMILY_OLIN"

## 政治层级固定 ID：家族 → 王国。只在新世界初始化时写入，读档不会重建。
const HOUSE_PLAYER_ID: String = "HOUSE_PLAYER"
const HOUSE_BARI_ID: String = "HOUSE_BARI"
const HOUSE_MOXIXI_ID: String = "HOUSE_MOXIXI"
const HOUSE_BURKNANIA_ID: String = "HOUSE_BURKNANIA"
const HOUSE_OLIN_ID: String = "HOUSE_OLIN"
const KINGDOM_BURKNANIA_ID: String = "KINGDOM_BURKNANIA"
const KINGDOM_OLIN_ID: String = "KINGDOM_OLIN"

const PLAYER_HOUSE_NAME: String = "玩家家族"
const BARI_HOUSE_NAME: String = "巴里家族"
const MOXIXI_HOUSE_NAME: String = "墨西西家族"
const BURKNANIA_HOUSE_NAME: String = "伯克纳家族"
const OLIN_HOUSE_NAME: String = "奥林家族"
const BURKNANIA_KINGDOM_NAME: String = "伯克纳尼亚王国"
const OLIN_KINGDOM_NAME: String = "奥林王国"
const BURKNANIA_KINGDOM_COLOR: Color = Color(0.62, 0.16, 0.16)
const OLIN_KINGDOM_COLOR: Color = Color(0.72, 0.55, 0.22)

const PLAYER_START_POSITION: Vector2 = Vector2(760.0, 620.0)
const PLAYER_MOVE_SPEED: float = 150.0
const PLAYER_SIGHT_RANGE: float = 300.0

## 阶段 4 优化的 NPC 速度关系：治安队 > 强盗 > 商队。
## 旧存档通过 PartyData.movement_speed 保留原速度，不会在这里被重置。
const MERCHANT_MOVE_SPEED: float = 80.0
const GUARD_MOVE_SPEED: float = 120.0
const BANDIT_MOVE_SPEED: float = 100.0
const FAMILY_KNIGHT_MOVE_SPEED: float = 110.0
const NPC_SIGHT_RANGE: float = 250.0
const GUARD_SIGHT_RANGE: float = 300.0
const BANDIT_SIGHT_RANGE: float = 320.0
const FAMILY_KNIGHT_SIGHT_RANGE: float = 300.0

## 临时测试兵力。后续由招募/部队初始化系统替换。
const TEST_FORCE_SOURCE: String = "milestone2_test"
const MILITIA_CONFIG_PATH: String = "res://Data/Units/infantry_militia.tres"
const TRAINED_CONFIG_PATH: String = "res://Data/Units/infantry_trained.tres"
const VETERAN_CONFIG_PATH: String = "res://Data/Units/infantry_veteran.tres"
const ARCHER_MILITIA_CONFIG_PATH: String = "res://Data/Units/archer_militia.tres"
const ARCHER_TRAINED_CONFIG_PATH: String = "res://Data/Units/archer_trained.tres"
const PLAYER_HERO_CONFIG_PATH: String = "res://Data/Units/player_hero.tres"
const TEST_MILITIA_COUNT: int = 3
const TEST_TRAINED_COUNT: int = 2
## 玩家部队：5 民兵 + 6 职业步兵（其中 4 名骑乘）+ 3 弓箭手 + 1 玩家角色 = 15 人。
## 只复用现有兵种配置；弓箭手使用一级/二级配置，不新增骑兵 UnitConfig。
const PLAYER_MILITIA_COUNT: int = 5
const PLAYER_TRAINED_COUNT: int = 6
const PLAYER_MOUNTED_TRAINED_COUNT: int = 4
## 初始 3 名弓箭手：2 名一级 + 1 名二级，优先复用现有一级/二级配置。
const PLAYER_ARCHER_MILITIA_COUNT: int = 2
const PLAYER_ARCHER_TRAINED_COUNT: int = 1
const PLAYER_ARCHER_COUNT: int = (
	PLAYER_ARCHER_MILITIA_COUNT + PLAYER_ARCHER_TRAINED_COUNT
)
const PLAYER_TOTAL_MEMBER_COUNT: int = (
	PLAYER_MILITIA_COUNT + PLAYER_TRAINED_COUNT + PLAYER_ARCHER_COUNT + 1
)
const TEST_MOUNT_ID: String = "mount_horse_01"
## 4 匹装备给骑乘职业步兵，额外 1 匹留在背包，便于验证“上马/下马”。
const TEST_MOUNT_STOCK: int = PLAYER_MOUNTED_TRAINED_COUNT + 1
const TEST_PROMOTION_ITEM_ID: String = "promotion_rank_token"
## 临时测试库存，便于验证晋升流程；正式获取途径后续实现。
const TEST_PROMOTION_ITEM_STOCK: int = 2
const TEST_ENEMY_PARTY_NAME: String = "河畔商队"
const GUARD_PARTY_NAME: String = "北境巡逻队"
const BANDIT_PARTY_NAME: String = "山道强盗"
const EAST_BANDIT_PARTY_NAME: String = "东路强盗"
const WASTE_BANDIT_PARTY_NAME: String = "荒野强盗"

const BARI_VILLAGE_NAME: String = "巴里"
const MOXIXI_VILLAGE_NAME: String = "墨西西"
const PLAYER_VILLAGE_NAME: String = "青禾村"
## 玩家村庄保持中立，位于两王国区域之间的西侧缓冲地带。
const PLAYER_VILLAGE_POSITION: Vector2 = Vector2(1600.0, 1500.0)
const BARI_KNIGHT_PARTY_NAME: String = "巴里骑士"
const MOXIXI_KNIGHT_PARTY_NAME: String = "墨西西骑士"
const BARI_KNIGHT_LEADER_NAME: String = "巴里骑士"
const MOXIXI_KNIGHT_LEADER_NAME: String = "墨西西骑士"
const PLAYER_LORD_NAME: String = "玩家领主"
const BARI_LORD_NAME: String = "巴里领主"
const MOXIXI_LORD_NAME: String = "墨西西领主"

## 新政治区域按王国聚集：伯克纳尼亚在北侧，奥林在南侧，
## 同家族封地保持较近距离，两个王国之间留出可辨认的势力间隔。
const BURKNANIA_TOWN_NAME: String = "伯克纳尼亚"
const BURKNA_VILLAGE_NAME: String = "伯克纳"
const OLIN_CASTLE_NAME: String = "奥林德斯堡"
const OLIN_VILLAGE_NAME: String = "奥林"
const BURKNANIA_TOWN_POSITION: Vector2 = Vector2(2900.0, 750.0)
const BURKNA_VILLAGE_POSITION: Vector2 = Vector2(3200.0, 1000.0)
const OLIN_CASTLE_POSITION: Vector2 = Vector2(2950.0, 1850.0)
const OLIN_VILLAGE_POSITION: Vector2 = Vector2(3250.0, 2050.0)

## 旧家族封地重新归入各自王国区域：墨西西靠近伯克纳尼亚，巴里靠近奥林。
const BARI_VILLAGE_POSITION: Vector2 = Vector2(2600.0, 2100.0)
const MOXIXI_VILLAGE_POSITION: Vector2 = Vector2(2500.0, 700.0)
const NORTH_VILLAGE_POSITION: Vector2 = Vector2(2250.0, 1000.0)
const GREY_CASTLE_POSITION: Vector2 = Vector2(2900.0, 2350.0)

const BURKNANIA_KING_NAME: String = "伯克纳国王"
const BURKNANIA_LORD_NAME: String = "伯克纳领主"
const OLIN_KING_NAME: String = "奥林国王"
const OLIN_LORD_NAME: String = "奥林领主"
const BURKNANIA_KING_PARTY_NAME: String = "伯克纳王室卫队"
const BURKNANIA_KNIGHT_PARTY_NAME: String = "伯克纳骑士"
const OLIN_KING_PARTY_NAME: String = "奥林王室卫队"
const OLIN_KNIGHT_PARTY_NAME: String = "奥林骑士"

## 家族骑士编制（每队）：
## 1 领袖（三级）+ 1 骑乘侍从（三级）+ 3 骑乘军士（二级）
## + 2 军士（二级）+ 3 步兵（一级）= 10 人。
## 规格表格明细合计为 8 人，但正文与验收均要求 10 人；
## 这里按验收目标补足 1 名骑乘军士和 1 名步兵。
const FAMILY_LEADER_COUNT: int = 1
const FAMILY_MOUNTED_SQUIRE_COUNT: int = 1
const FAMILY_MOUNTED_SERGEANT_COUNT: int = 3
const FAMILY_SERGEANT_COUNT: int = 2
const FAMILY_INFANTRY_COUNT: int = 3
const FAMILY_TOTAL_MEMBER_COUNT: int = 10

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

	# 家族先于贵族/封地建立，避免初始化过程中出现悬空 house_id。
	var player_house := context.house_manager.register_house(
		HOUSE_PLAYER_ID, PLAYER_HOUSE_NAME, FAMILY_PLAYER_ID, true
	)
	var bari_house := context.house_manager.register_house(
		HOUSE_BARI_ID, BARI_HOUSE_NAME, FAMILY_BARI_ID
	)
	var moxixi_house := context.house_manager.register_house(
		HOUSE_MOXIXI_ID, MOXIXI_HOUSE_NAME, FAMILY_MOXIXI_ID
	)
	var burknania_house := context.house_manager.register_house(
		HOUSE_BURKNANIA_ID, BURKNANIA_HOUSE_NAME, FAMILY_BURKNANIA_ID
	)
	var olin_house := context.house_manager.register_house(
		HOUSE_OLIN_ID, OLIN_HOUSE_NAME, FAMILY_OLIN_ID
	)
	if player_house == null or bari_house == null or moxixi_house == null \
			or burknania_house == null or olin_house == null:
		push_error("初始家族注册失败")
		return false
	context.player_house_id = player_house.house_id

	var player_party := context.party_manager.create_party(
		PLAYER_FACTION_ID,
		PLAYER_START_POSITION,
		"玩家部队",
		PartyData.PartyKind.PLAYER
	)
	if player_party == null:
		return false
	player_party.control_type = PartyData.ControlType.PLAYER
	player_party.movement_speed = PLAYER_MOVE_SPEED
	player_party.sight_range = PLAYER_SIGHT_RANGE
	player_party.family_id = FAMILY_PLAYER_ID
	context.player_party_id = player_party.party_id
	context.ai_manager.player_party_id = player_party.party_id
	context.battle_manager.player_party_id = player_party.party_id
	context.adventurer_recruitment_manager.player_party_id = player_party.party_id

	# 玩家是家族中的一名骑士贵族，与玩家角色 UnitData 分离；
	# 封地所有权只认 noble_id/owner_house_id，不依赖玩家角色单位。
	var player_noble: NobleData = context.noble_manager.create_noble(
		PLAYER_LORD_NAME,
		PLAYER_FACTION_ID,
		player_party.party_id,
		HOUSE_PLAYER_ID,
		NobleData.Rank.KNIGHT,
		true,
		true
	)
	if player_noble == null:
		return false
	context.player_lord_id = player_noble.lord_id
	player_party.leader_noble_id = player_noble.lord_id

	var merchant_party := context.party_manager.create_party(
		MERCHANT_FACTION_ID,
		Vector2(900.0, 1500.0),
		TEST_ENEMY_PARTY_NAME,
		PartyData.PartyKind.MERCHANT
	)
	if merchant_party != null:
		merchant_party.movement_speed = MERCHANT_MOVE_SPEED
		merchant_party.sight_range = NPC_SIGHT_RANGE

	var guard_party := context.party_manager.create_party(
		GUARD_FACTION_ID,
		Vector2(2350.0, 1100.0),
		GUARD_PARTY_NAME,
		PartyData.PartyKind.GUARD
	)
	if guard_party != null:
		guard_party.movement_speed = GUARD_MOVE_SPEED
		guard_party.sight_range = GUARD_SIGHT_RANGE

	var bandit_party := context.party_manager.create_party(
		BANDIT_FACTION_ID,
		Vector2(1650.0, 900.0),
		BANDIT_PARTY_NAME,
		PartyData.PartyKind.BANDIT
	)
	if bandit_party != null:
		bandit_party.movement_speed = BANDIT_MOVE_SPEED
		bandit_party.sight_range = BANDIT_SIGHT_RANGE

	# 两支 NPC 家族骑士部队：使用现有阵营/部队/AI 架构，
	# 通过 PartyData.family_id 与专属巡逻点区分，不新增特殊地图逻辑。
	var bari_knights := context.party_manager.create_party(
		LOCAL_FACTION_ID,
		Vector2(2550.0, 2150.0),
		BARI_KNIGHT_PARTY_NAME,
		PartyData.PartyKind.FAMILY
	)
	if bari_knights != null:
		bari_knights.family_id = FAMILY_BARI_ID
		bari_knights.movement_speed = FAMILY_KNIGHT_MOVE_SPEED
		bari_knights.sight_range = FAMILY_KNIGHT_SIGHT_RANGE

	var moxixi_knights := context.party_manager.create_party(
		LOCAL_FACTION_ID,
		Vector2(2400.0, 850.0),
		MOXIXI_KNIGHT_PARTY_NAME,
		PartyData.PartyKind.FAMILY
	)
	if moxixi_knights != null:
		moxixi_knights.family_id = FAMILY_MOXIXI_ID
		moxixi_knights.movement_speed = FAMILY_KNIGHT_MOVE_SPEED
		moxixi_knights.sight_range = FAMILY_KNIGHT_SIGHT_RANGE

	# 两名 NPC 家族领袖各自独立指挥自己的骑士部队；封地归属在村庄创建后写入。
	var bari_lord: NobleData = null
	var moxixi_lord: NobleData = null
	if bari_knights != null:
		bari_lord = context.noble_manager.create_noble(
			BARI_LORD_NAME,
			LOCAL_FACTION_ID,
			bari_knights.party_id,
			HOUSE_BARI_ID,
			NobleData.Rank.BARON,
			false,
			true
		)
		if bari_lord != null:
			bari_knights.leader_noble_id = bari_lord.lord_id
	if moxixi_knights != null:
		moxixi_lord = context.noble_manager.create_noble(
			MOXIXI_LORD_NAME,
			LOCAL_FACTION_ID,
			moxixi_knights.party_id,
			HOUSE_MOXIXI_ID,
			NobleData.Rank.BARON,
			false,
			true
		)
		if moxixi_lord != null:
			moxixi_knights.leader_noble_id = moxixi_lord.lord_id

	# 两支新强盗部队：沿用现有 BANDIT 阵营与 AI，只是拥有独立 ID、出生点和路线。
	var east_bandits := context.party_manager.create_party(
		BANDIT_FACTION_ID,
		Vector2(950.0, 1250.0),
		EAST_BANDIT_PARTY_NAME,
		PartyData.PartyKind.BANDIT
	)
	if east_bandits != null:
		east_bandits.movement_speed = BANDIT_MOVE_SPEED
		east_bandits.sight_range = BANDIT_SIGHT_RANGE

	var waste_bandits := context.party_manager.create_party(
		BANDIT_FACTION_ID,
		Vector2(2500.0, 1500.0),
		WASTE_BANDIT_PARTY_NAME,
		PartyData.PartyKind.BANDIT
	)
	if waste_bandits != null:
		waste_bandits.movement_speed = BANDIT_MOVE_SPEED
		waste_bandits.sight_range = BANDIT_SIGHT_RANGE

	# 两个新王国的国王与普通贵族各自独立指挥一支部队；
	# 家族/王国关系在部队和贵族建立后统一写入。
	var burknania_king_party := _create_family_party(
		context, FAMILY_BURKNANIA_ID,
		BURKNANIA_KING_PARTY_NAME, Vector2(2850.0, 650.0)
	)
	var burknania_knight_party := _create_family_party(
		context, FAMILY_BURKNANIA_ID,
		BURKNANIA_KNIGHT_PARTY_NAME, Vector2(3200.0, 1050.0)
	)
	var olin_king_party := _create_family_party(
		context, FAMILY_OLIN_ID,
		OLIN_KING_PARTY_NAME, Vector2(2950.0, 1800.0)
	)
	var olin_knight_party := _create_family_party(
		context, FAMILY_OLIN_ID,
		OLIN_KNIGHT_PARTY_NAME, Vector2(3250.0, 2100.0)
	)
	if burknania_king_party == null or burknania_knight_party == null \
			or olin_king_party == null or olin_knight_party == null:
		push_error("新王国部队创建失败")
		return false

	var burknania_king: NobleData = context.noble_manager.create_noble(
		BURKNANIA_KING_NAME,
		LOCAL_FACTION_ID,
		burknania_king_party.party_id,
		HOUSE_BURKNANIA_ID,
		NobleData.Rank.DUKE,
		false,
		true
	)
	var burknania_lord: NobleData = context.noble_manager.create_noble(
		BURKNANIA_LORD_NAME,
		LOCAL_FACTION_ID,
		burknania_knight_party.party_id,
		HOUSE_BURKNANIA_ID,
		NobleData.Rank.KNIGHT
	)
	var olin_king: NobleData = context.noble_manager.create_noble(
		OLIN_KING_NAME,
		LOCAL_FACTION_ID,
		olin_king_party.party_id,
		HOUSE_OLIN_ID,
		NobleData.Rank.DUKE,
		false,
		true
	)
	var olin_lord: NobleData = context.noble_manager.create_noble(
		OLIN_LORD_NAME,
		LOCAL_FACTION_ID,
		olin_knight_party.party_id,
		HOUSE_OLIN_ID,
		NobleData.Rank.KNIGHT
	)
	if burknania_king == null or burknania_lord == null \
			or olin_king == null or olin_lord == null:
		push_error("新王国贵族创建失败")
		return false
	burknania_king_party.leader_noble_id = burknania_king.lord_id
	burknania_knight_party.leader_noble_id = burknania_lord.lord_id
	olin_king_party.leader_noble_id = olin_king.lord_id
	olin_knight_party.leader_noble_id = olin_lord.lord_id

	var bari_village := _create_settlement(
		context, BARI_VILLAGE_NAME, SettlementData.SettlementType.VILLAGE,
		BARI_VILLAGE_POSITION, 120, 40
	)
	var moxixi_village := _create_settlement(
		context, MOXIXI_VILLAGE_NAME, SettlementData.SettlementType.VILLAGE,
		MOXIXI_VILLAGE_POSITION, 96, 35
	)
	var north_village := _create_settlement(
		context, "北境村", SettlementData.SettlementType.VILLAGE,
		NORTH_VILLAGE_POSITION, 80, 30
	)
	var grey_castle := _create_settlement(
		context, "灰石城堡", SettlementData.SettlementType.CASTLE,
		GREY_CASTLE_POSITION, 0, 60
	)
	# 玩家封地放在已有地点之后创建，保持“第一个村庄”等旧流程稳定。
	var player_village := _create_settlement(
		context,
		PLAYER_VILLAGE_NAME,
		SettlementData.SettlementType.VILLAGE,
		PLAYER_VILLAGE_POSITION,
		110,
		38,
		PLAYER_FACTION_ID
	)
	# 新王国的城镇/城堡与其近邻村庄；距离旧区域足够远，避免地图图标重叠。
	var burknania_town := _create_settlement(
		context, BURKNANIA_TOWN_NAME, SettlementData.SettlementType.TOWN,
		BURKNANIA_TOWN_POSITION, 240, 72
	)
	var burkna_village := _create_settlement(
		context, BURKNA_VILLAGE_NAME, SettlementData.SettlementType.VILLAGE,
		BURKNA_VILLAGE_POSITION, 130, 42
	)
	var olin_castle := _create_settlement(
		context, OLIN_CASTLE_NAME, SettlementData.SettlementType.CASTLE,
		OLIN_CASTLE_POSITION, 0, 78
	)
	var olin_village := _create_settlement(
		context, OLIN_VILLAGE_NAME, SettlementData.SettlementType.VILLAGE,
		OLIN_VILLAGE_POSITION, 140, 46
	)

	for village: SettlementData in [
		bari_village, moxixi_village, north_village, player_village,
		burkna_village, olin_village
	]:
		if village != null:
			village.scene_path = DEFAULT_VILLAGE_SCENE_PATH
	# 所有地点都必须有家族所有者；贵族所有者可选，但必须属于该家族。
	_assign_settlement_owner(
		bari_village, FAMILY_BARI_ID, HOUSE_BARI_ID, bari_lord
	)
	_assign_settlement_owner(
		moxixi_village, FAMILY_MOXIXI_ID, HOUSE_MOXIXI_ID, moxixi_lord
	)
	_assign_settlement_owner(
		north_village, FAMILY_MOXIXI_ID, HOUSE_MOXIXI_ID, moxixi_lord
	)
	_assign_settlement_owner(
		grey_castle, FAMILY_BARI_ID, HOUSE_BARI_ID, bari_lord
	)
	_assign_settlement_owner(
		player_village, FAMILY_PLAYER_ID, HOUSE_PLAYER_ID, player_noble
	)
	_assign_settlement_owner(
		burknania_town, FAMILY_BURKNANIA_ID, HOUSE_BURKNANIA_ID, burknania_king
	)
	_assign_settlement_owner(
		burkna_village, FAMILY_BURKNANIA_ID, HOUSE_BURKNANIA_ID, burknania_lord
	)
	_assign_settlement_owner(
		olin_castle, FAMILY_OLIN_ID, HOUSE_OLIN_ID, olin_king
	)
	_assign_settlement_owner(
		olin_village, FAMILY_OLIN_ID, HOUSE_OLIN_ID, olin_lord
	)

	if merchant_party != null and bari_village != null and moxixi_village != null:
		# 商队从巴里路线起点出发，首次决策后前往墨西西。
		merchant_party.world_position = bari_village.world_position
		merchant_party.target_position = merchant_party.world_position
		merchant_party.movement_state = PartyData.MovementState.IDLE
		merchant_party.ai_type = PartyData.PartyAIType.TRADE_ROUTE
		merchant_party.ai_route_index = 0
		merchant_party.ai_route_settlement_ids = [
			bari_village.settlement_id,
			moxixi_village.settlement_id,
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

	if bari_knights != null:
		bari_knights.ai_type = PartyData.PartyAIType.PATROL
		bari_knights.ai_route_index = 0
		bari_knights.ai_patrol_points = [
			Vector2(2550.0, 2150.0),
			Vector2(2700.0, 2250.0),
			Vector2(2800.0, 2400.0),
			Vector2(2500.0, 2300.0),
		]
	if moxixi_knights != null:
		moxixi_knights.ai_type = PartyData.PartyAIType.PATROL
		moxixi_knights.ai_route_index = 0
		moxixi_knights.ai_patrol_points = [
			Vector2(2400.0, 850.0),
			Vector2(2500.0, 950.0),
			Vector2(2300.0, 1050.0),
			Vector2(2250.0, 900.0),
		]
	_set_patrol_route(
		burknania_king_party,
		[
			Vector2(2850.0, 650.0),
			Vector2(3000.0, 550.0),
			Vector2(3100.0, 750.0),
			Vector2(2900.0, 850.0),
		]
	)
	_set_patrol_route(
		burknania_knight_party,
		[
			Vector2(3200.0, 1050.0),
			Vector2(3350.0, 950.0),
			Vector2(3300.0, 1150.0),
			Vector2(3100.0, 1100.0),
		]
	)
	_set_patrol_route(
		olin_king_party,
		[
			Vector2(2950.0, 1800.0),
			Vector2(3100.0, 1750.0),
			Vector2(3150.0, 1950.0),
			Vector2(2900.0, 1950.0),
		]
	)
	_set_patrol_route(
		olin_knight_party,
		[
			Vector2(3250.0, 2100.0),
			Vector2(3400.0, 2050.0),
			Vector2(3350.0, 2250.0),
			Vector2(3150.0, 2200.0),
		]
	)

	if east_bandits != null:
		east_bandits.ai_type = PartyData.PartyAIType.BANDIT
		east_bandits.ai_route_index = 0
		east_bandits.target_position = east_bandits.world_position
		east_bandits.movement_state = PartyData.MovementState.IDLE
		if bari_village != null and grey_castle != null:
			east_bandits.ai_route_settlement_ids = [
				bari_village.settlement_id,
				grey_castle.settlement_id,
			]
	if waste_bandits != null:
		waste_bandits.ai_type = PartyData.PartyAIType.BANDIT
		waste_bandits.ai_route_index = 0
		waste_bandits.target_position = waste_bandits.world_position
		waste_bandits.movement_state = PartyData.MovementState.IDLE
		if north_village != null and grey_castle != null:
			waste_bandits.ai_route_settlement_ids = [
				north_village.settlement_id,
				grey_castle.settlement_id,
			]

	# 王国：伯克纳统治伯克纳家族并吸纳墨西西；奥林统治奥林家族并吸纳巴里。
	# 初始两王国互相敌对；玩家家族不属于任何王国，保持中立。
	var burknania_kingdom := context.kingdom_manager.register_kingdom(
		KINGDOM_BURKNANIA_ID,
		BURKNANIA_KINGDOM_NAME,
		HOUSE_BURKNANIA_ID,
		burknania_king.lord_id,
		BURKNANIA_KINGDOM_COLOR
	)
	var olin_kingdom := context.kingdom_manager.register_kingdom(
		KINGDOM_OLIN_ID,
		OLIN_KINGDOM_NAME,
		HOUSE_OLIN_ID,
		olin_king.lord_id,
		OLIN_KINGDOM_COLOR
	)
	if burknania_kingdom == null or olin_kingdom == null:
		push_error("初始王国注册失败")
		return false
	if not context.kingdom_manager.add_vassal_house(KINGDOM_BURKNANIA_ID, HOUSE_MOXIXI_ID):
		push_error("墨西西家族加入伯克纳王国失败")
		return false
	if not context.kingdom_manager.add_vassal_house(KINGDOM_OLIN_ID, HOUSE_BARI_ID):
		push_error("巴里家族加入奥林王国失败")
		return false
	context.kingdom_manager.declare_war(KINGDOM_BURKNANIA_ID, KINGDOM_OLIN_ID)

	# 上下级关系：普通贵族与附庸家族领袖效忠各自王国的国王。
	context.noble_manager.set_liege(burknania_lord.lord_id, burknania_king.lord_id)
	context.noble_manager.set_liege(olin_lord.lord_id, olin_king.lord_id)
	context.noble_manager.set_liege(moxixi_lord.lord_id, burknania_king.lord_id)
	context.noble_manager.set_liege(bari_lord.lord_id, olin_king.lord_id)

	context.house_manager.refresh_settlement_links()

	var political_errors: Array[String] = []
	political_errors.append_array(context.noble_manager.validate(context.party_manager))
	political_errors.append_array(context.house_manager.validate())
	political_errors.append_array(context.kingdom_manager.validate())
	political_errors.append_array(context.validate_world_ownership())
	if not political_errors.is_empty():
		for error_text: String in political_errors:
			push_error("初始政治数据错误: %s" % error_text)
		return false

	if not create_test_battle_forces(context):
		push_error("初始测试兵力生成失败")
		return false
	if not initialize_fief_economy(context):
		push_error("封地经济初始化失败")
		return false

	return context.is_valid_world()


## 新游戏封地经济：所有村庄获得采邑储备、税收缓存与初始冒险者候选人。
static func initialize_fief_economy(context: WorldContext) -> bool:
	if context == null:
		return false
	for settlement: SettlementData in context.settlement_manager.get_all_settlements():
		if settlement == null:
			continue
		if settlement.settlement_type == SettlementData.SettlementType.VILLAGE:
			context.fief_recruitment_manager.initialize_settlement(settlement, true)
			context.adventurer_recruitment_manager.initialize_settlement(settlement, true)
		else:
			settlement.fief_recruitment_capacity = 0
			settlement.fief_recruitment_stock = 0
			context.fief_recruitment_manager.clamp_settlement(settlement)
	return true


## 调试用测试兵力：玩家 5 民兵 + 6 职业步兵（4 名骑乘）+ 玩家角色；其余三方各 3 民兵 + 2 职业步兵。
## 复用已有 AI 部队，不额外创建部队；单位标记 recruit_source 便于识别和清理。
static func create_test_battle_forces(context: WorldContext) -> bool:
	if context == null:
		return false
	var militia: UnitConfig = load(MILITIA_CONFIG_PATH) as UnitConfig
	var trained: UnitConfig = load(TRAINED_CONFIG_PATH) as UnitConfig
	var veteran: UnitConfig = load(VETERAN_CONFIG_PATH) as UnitConfig
	if militia == null or trained == null or veteran == null:
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
		EAST_BANDIT_PARTY_NAME,
		WASTE_BANDIT_PARTY_NAME,
	]
	for party_name: String in required_names:
		var party := _find_party_by_name(context, party_name)
		if party == null:
			push_error("测试兵力找不到部队: %s" % party_name)
			return false
		if not _populate_test_party(context, party, militia, trained):
			return false

	var bari_knights := _find_party_by_name(context, BARI_KNIGHT_PARTY_NAME)
	var moxixi_knights := _find_party_by_name(context, MOXIXI_KNIGHT_PARTY_NAME)
	if bari_knights == null or moxixi_knights == null:
		push_error("测试兵力缺少家族骑士部队")
		return false
	if not _populate_family_party(
		context,
		bari_knights,
		context.family_registry.get_config(FAMILY_BARI_ID),
		BARI_KNIGHT_LEADER_NAME,
		militia,
		trained,
		veteran
	):
		return false
	if not _populate_family_party(
		context,
		moxixi_knights,
		context.family_registry.get_config(FAMILY_MOXIXI_ID),
		MOXIXI_KNIGHT_LEADER_NAME,
		militia,
		trained,
		veteran
	):
		return false

	# 新王国四支部队沿用同一家族骑士编制与外观配置。
	var new_family_parties: Array[Dictionary] = [
		{
			"party_name": BURKNANIA_KING_PARTY_NAME,
			"family_id": FAMILY_BURKNANIA_ID,
			"leader_name": BURKNANIA_KING_NAME,
		},
		{
			"party_name": BURKNANIA_KNIGHT_PARTY_NAME,
			"family_id": FAMILY_BURKNANIA_ID,
			"leader_name": BURKNANIA_LORD_NAME,
		},
		{
			"party_name": OLIN_KING_PARTY_NAME,
			"family_id": FAMILY_OLIN_ID,
			"leader_name": OLIN_KING_NAME,
		},
		{
			"party_name": OLIN_KNIGHT_PARTY_NAME,
			"family_id": FAMILY_OLIN_ID,
			"leader_name": OLIN_LORD_NAME,
		},
	]
	for entry: Dictionary in new_family_parties:
		var party := _find_party_by_name(context, str(entry["party_name"]))
		if party == null:
			push_error("测试兵力找不到部队: %s" % str(entry["party_name"]))
			return false
		var family := context.family_registry.get_config(str(entry["family_id"]))
		if family == null:
			push_error("测试兵力缺少家族配置: %s" % str(entry["family_id"]))
			return false
		if not _populate_family_party(
			context,
			party,
			family,
			str(entry["leader_name"]),
			militia,
			trained,
			veteran
		):
			return false
	return true


static func _find_party_by_name(context: WorldContext, party_name: String) -> PartyData:
	for party: PartyData in context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


## 玩家部队：5 民兵 + 6 职业步兵（前 4 名骑乘）+ 3 弓箭手
## + 玩家角色（最后加入，保持 UI 默认选中民兵）。
static func _populate_player_party(
	context: WorldContext, party: PartyData, militia: UnitConfig, trained: UnitConfig
) -> bool:
	if not party.member_unit_ids.is_empty():
		return true
	var hero_config: UnitConfig = load(PLAYER_HERO_CONFIG_PATH) as UnitConfig
	var archer_militia: UnitConfig = load(ARCHER_MILITIA_CONFIG_PATH) as UnitConfig
	var archer_trained: UnitConfig = load(ARCHER_TRAINED_CONFIG_PATH) as UnitConfig
	if hero_config == null:
		push_error("玩家角色配置加载失败: %s" % PLAYER_HERO_CONFIG_PATH)
		return false
	if archer_militia == null or archer_trained == null:
		push_error("玩家弓箭手配置加载失败")
		return false

	var configs: Array[UnitConfig] = []
	for i: int in range(PLAYER_MILITIA_COUNT):
		configs.append(militia)
	for i: int in range(PLAYER_TRAINED_COUNT):
		configs.append(trained)
	for i: int in range(PLAYER_ARCHER_MILITIA_COUNT):
		configs.append(archer_militia)
	for i: int in range(PLAYER_ARCHER_TRAINED_COUNT):
		configs.append(archer_trained)
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

	var player_family := context.family_registry.get_config(FAMILY_PLAYER_ID)
	var mounted_count: int = 0
	for config: UnitConfig in configs:
		var family: FamilyConfig = player_family if config.is_player_character else null
		var unit := _create_world_unit(
			context,
			party,
			config,
			family,
			"",
			0,
			config.is_player_character
		)
		if unit == null:
			return false

		# 玩家角色是“身份”，由 is_player_character 表示；当前控制权仍由
		# BattleScene 在运行时决定。玩家部队的领袖也通过统一字段记录。
		if unit.is_player_character:
			party.leader_unit_id = unit.unit_id
			context.player_unit_id = unit.unit_id

		# 前 4 名职业步兵装备马匹；其余职业步兵保持步战，不新增骑兵兵种。
		if config.config_id == trained.config_id \
				and mounted_count < PLAYER_MOUNTED_TRAINED_COUNT:
			if not context.unit_manager.equip_mount(
				unit.unit_id, TEST_MOUNT_ID, context.player_profile
			):
				push_error("玩家测试骑兵装备马匹失败: %s" % unit.unit_id)
				return false
			mounted_count += 1

	if mounted_count < PLAYER_MOUNTED_TRAINED_COUNT:
		push_error(
			"玩家部队骑乘测试单位不足: %d/%d"
			% [mounted_count, PLAYER_MOUNTED_TRAINED_COUNT]
		)
		return false
	if party.member_unit_ids.size() != PLAYER_TOTAL_MEMBER_COUNT:
		push_error(
			"玩家部队人数异常: %d/%d"
			% [party.member_unit_ids.size(), PLAYER_TOTAL_MEMBER_COUNT]
		)
		return false
	return true


static func _populate_test_party(
	context: WorldContext,
	party: PartyData,
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

	# 普通 NPC 部队同样通过 leader_unit_id 拥有领袖；
	# 领袖名称沿用部队名，供遭遇对话显示。旧存档没有该字段时 UI 使用默认剪影。
	var leader: UnitData = null
	for index: int in range(configs.size()):
		var is_leader: bool = index == 0
		var unit := _create_world_unit(
			context,
			party,
			configs[index],
			null,
			party.party_name if is_leader else "",
			0,
			is_leader
		)
		if unit == null:
			return false
		if is_leader:
			leader = unit
	if leader != null and party.leader_unit_id.is_empty():
		party.leader_unit_id = leader.unit_id
	return true


## 家族骑士编制：领袖 + 骑乘侍从 + 骑乘军士 + 步战军士 + 步兵。
static func _populate_family_party(
	context: WorldContext,
	party: PartyData,
	family: FamilyConfig,
	leader_name: String,
	militia: UnitConfig,
	trained: UnitConfig,
	veteran: UnitConfig
) -> bool:
	if not party.member_unit_ids.is_empty():
		return true

	# 领袖：三级兵种，初始等级 3；家族领袖是部队 leader_unit_id，
	# 但玩家身份/当前控制权不由此字段推导。
	var leader := _create_world_unit(
		context, party, veteran, family, leader_name, 3, true, true
	)
	if leader == null:
		return false
	party.leader_unit_id = leader.unit_id

	# 1 名骑乘侍从（三级）。
	for i: int in range(FAMILY_MOUNTED_SQUIRE_COUNT):
		if _create_world_unit(
			context, party, veteran, family, "", 0, false, true
		) == null:
			return false

	# 3 名骑乘军士（二级）。
	for i: int in range(FAMILY_MOUNTED_SERGEANT_COUNT):
		if _create_world_unit(
			context, party, trained, family, "", 0, false, true
		) == null:
			return false

	# 2 名步战军士（二级）。
	for i: int in range(FAMILY_SERGEANT_COUNT):
		if _create_world_unit(
			context, party, trained, family, "", 0, false, false
		) == null:
			return false

	# 3 名步兵（一级）。
	for i: int in range(FAMILY_INFANTRY_COUNT):
		if _create_world_unit(
			context, party, militia, family, "", 0, false, false
		) == null:
			return false

	if party.member_unit_ids.size() != FAMILY_TOTAL_MEMBER_COUNT:
		push_error(
			"家族部队 %s 人数异常: %d/%d"
			% [party.party_name, party.member_unit_ids.size(), FAMILY_TOTAL_MEMBER_COUNT]
		)
		return false
	return true


## 创建单位、生成一次性外观、加入部队；可选骑乘。
## 所有世界初始单位都经过本入口，确保外观选择与人口/归属一致。
static func _create_world_unit(
	context: WorldContext,
	party: PartyData,
	config: UnitConfig,
	family: FamilyConfig,
	display_name: String,
	level: int,
	is_leader: bool,
	mounted: bool = false
) -> UnitData:
	var unit := context.unit_manager.create_unit(
		config, party.faction_id, display_name, level
	)
	if unit == null:
		return null
	unit.recruit_source = TEST_FORCE_SOURCE
	unit.origin_faction_id = party.faction_id
	UnitAppearance.ensure_random(
		unit, config, family, context.appearance_config, is_leader
	)
	if not context.party_manager.add_member(party.party_id, unit.unit_id):
		push_error("测试单位无法加入部队: %s" % party.party_id)
		return null
	if mounted and not context.unit_manager.equip_item(unit.unit_id, TEST_MOUNT_ID):
		push_error("测试骑兵装备马匹失败: %s" % unit.unit_id)
		return null
	return unit


## 创建一支家族骑士部队；指挥贵族稍后再绑定到 leader_noble_id。
static func _create_family_party(
	context: WorldContext,
	family_id: String,
	party_name: String,
	world_position: Vector2
) -> PartyData:
	var party := context.party_manager.create_party(
		LOCAL_FACTION_ID, world_position, party_name, PartyData.PartyKind.FAMILY
	)
	if party == null:
		return null
	party.family_id = family_id
	party.movement_speed = FAMILY_KNIGHT_MOVE_SPEED
	party.sight_range = FAMILY_KNIGHT_SIGHT_RANGE
	return party


## 统一写入封地的视觉家族与政治所有权，避免家族/贵族字段不一致。
static func _assign_settlement_owner(
	settlement: SettlementData,
	family_id: String,
	house_id: String,
	noble: NobleData
) -> void:
	if settlement == null:
		return
	settlement.family_id = family_id
	settlement.owner_house_id = house_id
	settlement.owner_noble_id = noble.lord_id if noble != null else ""


static func _set_patrol_route(party: PartyData, points: Array[Vector2]) -> void:
	if party == null:
		return
	party.ai_type = PartyData.PartyAIType.PATROL
	party.ai_route_index = 0
	party.ai_patrol_points = points


static func _create_settlement(
	context: WorldContext,
	display_name: String,
	settlement_type: SettlementData.SettlementType,
	world_position: Vector2,
	population: int,
	prosperity: int,
	faction_id: String = LOCAL_FACTION_ID
) -> SettlementData:
	return context.settlement_manager.create_settlement(
		display_name,
		settlement_type,
		world_position,
		faction_id,
		population,
		prosperity
	)
