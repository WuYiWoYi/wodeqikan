class_name WorldInitializer
extends RefCounted
## 新游戏世界初始化：按大地图定义生成地点、六方势力、家族与部队。
##
## 布局唯一依据是 Data/WorldMap/world_map_definition.tres；本文件只负责
## 把定义转换成现有实体。政治归属不按地图位置推断：
## - 六方势力的统治者/附庸关系由 _kingdom_specs() 显式声明；
## - 地点所有权只保留旧世界已确认的归属（伯克纳、巴里、墨西西、奥林、玩家），
##   新地点默认无主；
## - 地图旗帜展示使用地点定义中的 family_id（视觉身份），与所有权分离。

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
const FAMILY_ODESTER_ID: String = "FAMILY_ODESTER"
const FAMILY_EKTOR_ID: String = "FAMILY_EKTOR"
const FAMILY_BAFLE_ID: String = "FAMILY_BAFLE"
const FAMILY_FRANI_ID: String = "FAMILY_FRANI"
const FAMILY_DINDANI_ID: String = "FAMILY_DINDANI"
const FAMILY_KONLIA_ID: String = "FAMILY_KONLIA"
const FAMILY_MIQIQI_ID: String = "FAMILY_MIQIQI"
const FAMILY_VAILA_ID: String = "FAMILY_VAILA"
const FAMILY_LORIAK_ID: String = "FAMILY_LORIAK"
const FAMILY_ROSVIK_ID: String = "FAMILY_ROSVIK"
const FAMILY_TAINA_ID: String = "FAMILY_TAINA"
const FAMILY_VALEMON_ID: String = "FAMILY_VALEMON"
const FAMILY_KRIKA_ID: String = "FAMILY_KRIKA"

const HOUSE_PLAYER_ID: String = "HOUSE_PLAYER"
const HOUSE_BARI_ID: String = "HOUSE_BARI"
const HOUSE_MOXIXI_ID: String = "HOUSE_MOXIXI"
const HOUSE_BURKNANIA_ID: String = "HOUSE_BURKNANIA"
const HOUSE_OLIN_ID: String = "HOUSE_OLIN"
const HOUSE_ODESTER_ID: String = "HOUSE_ODESTER"
const HOUSE_EKTOR_ID: String = "HOUSE_EKTOR"
const HOUSE_BAFLE_ID: String = "HOUSE_BAFLE"
const HOUSE_FRANI_ID: String = "HOUSE_FRANI"
const HOUSE_DINDANI_ID: String = "HOUSE_DINDANI"
const HOUSE_KONLIA_ID: String = "HOUSE_KONLIA"
const HOUSE_MIQIQI_ID: String = "HOUSE_MIQIQI"
const HOUSE_VAILA_ID: String = "HOUSE_VAILA"
const HOUSE_LORIAK_ID: String = "HOUSE_LORIAK"
const HOUSE_ROSVIK_ID: String = "HOUSE_ROSVIK"
const HOUSE_TAINA_ID: String = "HOUSE_TAINA"
const HOUSE_VALEMON_ID: String = "HOUSE_VALEMON"
const HOUSE_KRIKA_ID: String = "HOUSE_KRIKA"

const KINGDOM_BURKNANIA_ID: String = "KINGDOM_BURKNANIA"
const KINGDOM_OLIN_ID: String = "KINGDOM_OLIN"
const KINGDOM_FRANI_ID: String = "KINGDOM_FRANI"
const KINGDOM_VAILA_ID: String = "KINGDOM_VAILA"
const KINGDOM_LORIAK_ID: String = "KINGDOM_LORIAK"
const KINGDOM_TAINA_ID: String = "KINGDOM_TAINA"
const KINGDOM_VALEMON_ID: String = "KINGDOM_VALEMON"

const PLAYER_HOUSE_NAME: String = "玩家家族"
const BARI_HOUSE_NAME: String = "巴里家族"
const MOXIXI_HOUSE_NAME: String = "墨西西家族"
const BURKNANIA_HOUSE_NAME: String = "伯克纳家族"
const OLIN_HOUSE_NAME: String = "奥林家族"
const ODESTER_HOUSE_NAME: String = "奥德斯特家族"
const EKTOR_HOUSE_NAME: String = "埃克托家族"
const BAFLE_HOUSE_NAME: String = "巴夫勒家族"
const FRANI_HOUSE_NAME: String = "弗拉尼家族"
const DINDANI_HOUSE_NAME: String = "丁达尼家族"
const KONLIA_HOUSE_NAME: String = "康利亚家族"
const MIQIQI_HOUSE_NAME: String = "米奇奇家族"
const VAILA_HOUSE_NAME: String = "瓦伊拉家族"
const LORIAK_HOUSE_NAME: String = "洛里亚克家族"
const ROSVIK_HOUSE_NAME: String = "罗斯维克家族"
const TAINA_HOUSE_NAME: String = "泰纳家族"
const VALEMON_HOUSE_NAME: String = "瓦勒蒙家族"
const KRIKA_HOUSE_NAME: String = "克里卡家族"

const BURKNANIA_KINGDOM_NAME: String = "伯克纳王国"
const OLIN_KINGDOM_NAME: String = "奥林王国"
const FRANI_KINGDOM_NAME: String = "弗拉尼王国"
const VAILA_KINGDOM_NAME: String = "瓦伊拉伯国"
const LORIAK_KINGDOM_NAME: String = "洛里亚克王国"
const TAINA_KINGDOM_NAME: String = "泰纳伯公国"
const VALEMON_KINGDOM_NAME: String = "瓦勒蒙联盟"

const PEOPLE_DORAMAN: String = "多拉曼人"
const PEOPLE_BUJIDUO: String = "布吉多人"
const PEOPLE_LORIS: String = "洛里斯人"
const PEOPLE_MONGKA: String = "蒙卡人"

const BURKNANIA_KINGDOM_COLOR: Color = Color(0.62, 0.16, 0.16)
const OLIN_KINGDOM_COLOR: Color = Color(0.72, 0.55, 0.22)
const FRANI_KINGDOM_COLOR: Color = Color(0.13, 0.25, 0.75)
const VAILA_KINGDOM_COLOR: Color = Color(0.25, 0.38, 0.88)
const LORIAK_KINGDOM_COLOR: Color = Color(0.72, 0.55, 0.22)
const TAINA_KINGDOM_COLOR: Color = Color(0.78, 0.35, 0.12)
const VALEMON_KINGDOM_COLOR: Color = Color(0.0, 0.50, 0.0)

## 旧世界常量保留给现有调用方；新世界位置以 WorldMapDefinition 为准。
const PLAYER_START_POSITION: Vector2 = Vector2(760.0, 620.0)
const PLAYER_SIGHT_RANGE: float = 300.0

const PLAYER_STARTING_GOLD: int = 10000

## 大地图移速基准由玩家等效 20 调整为 30：NPC 部队原有配置统一 ×5/2，
## 保持商队 < 强盗 < 家族骑士 < 巡逻队的相对差异。
## 有效移速 = 原始速度 × WorldMapManager.WORLD_MAP_SPEED_SCALE(0.08)。
const MOVE_SPEED_RESCALE: float = 5.0 / 2.0
## 玩家按需求单列为等效 36（450 × 0.08），不按 5/2 换算为 30。
const PLAYER_MOVE_SPEED: float = 450.0
const MERCHANT_MOVE_SPEED: float = 80.0 * MOVE_SPEED_RESCALE
const GUARD_MOVE_SPEED: float = 120.0 * MOVE_SPEED_RESCALE
const BANDIT_MOVE_SPEED: float = 100.0 * MOVE_SPEED_RESCALE
const FAMILY_KNIGHT_MOVE_SPEED: float = 110.0 * MOVE_SPEED_RESCALE
const NPC_SIGHT_RANGE: float = 250.0
const GUARD_SIGHT_RANGE: float = 300.0
const BANDIT_SIGHT_RANGE: float = 320.0
const FAMILY_KNIGHT_SIGHT_RANGE: float = 300.0

const TEST_FORCE_SOURCE: String = "milestone2_test"
const MILITIA_CONFIG_PATH: String = "res://Data/Units/infantry_militia.tres"
const TRAINED_CONFIG_PATH: String = "res://Data/Units/infantry_trained.tres"
const VETERAN_CONFIG_PATH: String = "res://Data/Units/infantry_veteran.tres"
const ARCHER_MILITIA_CONFIG_PATH: String = "res://Data/Units/archer_militia.tres"
const ARCHER_TRAINED_CONFIG_PATH: String = "res://Data/Units/archer_trained.tres"
const PLAYER_HERO_CONFIG_PATH: String = "res://Data/Units/player_hero.tres"
const TEST_MILITIA_COUNT: int = 3
const TEST_TRAINED_COUNT: int = 2

const PLAYER_MILITIA_COUNT: int = 5
const PLAYER_TRAINED_COUNT: int = 6
const PLAYER_MOUNTED_TRAINED_COUNT: int = 4
const PLAYER_ARCHER_MILITIA_COUNT: int = 2
const PLAYER_ARCHER_TRAINED_COUNT: int = 1
const PLAYER_ARCHER_COUNT: int = (
	PLAYER_ARCHER_MILITIA_COUNT + PLAYER_ARCHER_TRAINED_COUNT
)
const PLAYER_TOTAL_MEMBER_COUNT: int = (
	PLAYER_MILITIA_COUNT + PLAYER_TRAINED_COUNT + PLAYER_ARCHER_COUNT + 1
)

const PLAYER_STARTING_SUPPLY_DAYS: int = 7
const NPC_STARTING_SUPPLY_DAYS: int = 2
const NPC_STARTING_GOLD: int = 300

const TEST_MOUNT_ID: String = "mount_horse_01"
const TEST_MOUNT_STOCK: int = PLAYER_MOUNTED_TRAINED_COUNT + 1
const TEST_PROMOTION_ITEM_ID: String = "promotion_rank_token"
const TEST_PROMOTION_ITEM_STOCK: int = 2

const TEST_ENEMY_PARTY_NAME: String = "河畔商队"
const BANDIT_PARTY_NAME: String = "山道强盗"
const EAST_BANDIT_PARTY_NAME: String = "东路强盗"
const WASTE_BANDIT_PARTY_NAME: String = "荒野强盗"

const BARI_VILLAGE_NAME: String = "巴里"
const MOXIXI_VILLAGE_NAME: String = "墨西西"

const BARI_KNIGHT_PARTY_NAME: String = "巴里骑士"
const MOXIXI_KNIGHT_PARTY_NAME: String = "墨西西骑士"
const BARI_KNIGHT_LEADER_NAME: String = "埃尔韦·德·巴里"
const MOXIXI_KNIGHT_LEADER_NAME: String = "墨西西里曼"
const PLAYER_LORD_NAME: String = "玩家领主"
const BARI_LORD_NAME: String = "埃尔韦·德·巴里"
const MOXIXI_LORD_NAME: String = "墨西西里曼"

const BURKNANIA_TOWN_NAME: String = "伯克纳尼亚"
const BURKNA_VILLAGE_NAME: String = "伯克纳"
const OLIN_CASTLE_NAME: String = "奥林德斯堡"
const OLIN_VILLAGE_NAME: String = "奥林"
const BURKNANIA_TOWN_POSITION: Vector2 = Vector2(2900.0, 750.0)
const BURKNA_VILLAGE_POSITION: Vector2 = Vector2(3200.0, 1000.0)
const OLIN_CASTLE_POSITION: Vector2 = Vector2(2950.0, 1850.0)
const OLIN_VILLAGE_POSITION: Vector2 = Vector2(3250.0, 2050.0)

const BARI_VILLAGE_POSITION: Vector2 = Vector2(2600.0, 2100.0)
const MOXIXI_VILLAGE_POSITION: Vector2 = Vector2(2500.0, 700.0)
const GREY_CASTLE_POSITION: Vector2 = Vector2(2900.0, 2350.0)

const BURKNANIA_KING_NAME: String = "奥东·德·伯克纳"
const BURKNANIA_LORD_NAME: String = "奥东·德·伯克纳"
const OLIN_KING_NAME: String = "卡斯泰尔"
const OLIN_LORD_NAME: String = "卡斯泰尔"
const BURKNANIA_KING_PARTY_NAME: String = "伯克纳王室卫队"
const BURKNANIA_KNIGHT_PARTY_NAME: String = "伯克纳骑士"
const OLIN_KING_PARTY_NAME: String = "奥林王室卫队"
const OLIN_KNIGHT_PARTY_NAME: String = "奥林骑士"

const FRANI_KING_NAME: String = "奥利维耶"
const VAILA_KING_NAME: String = "瓦尔登"
const LORIAK_KING_NAME: String = "菲利普"
const TAINA_KING_NAME: String = "贝洛夫"
const VALEMON_KING_NAME: String = "卢卡"

const FAMILY_LEADER_COUNT: int = 1
const FAMILY_MOUNTED_SQUIRE_COUNT: int = 1
const FAMILY_MOUNTED_SERGEANT_COUNT: int = 3
const FAMILY_SERGEANT_COUNT: int = 2
const FAMILY_INFANTRY_COUNT: int = 3
const FAMILY_TOTAL_MEMBER_COUNT: int = 10

const DEFAULT_VILLAGE_SCENE_PATH: String = "res://Scenes/Village/village.tscn"

## 玩家出生点相对身份绑定地点的偏移（世界像素），随后统一收敛到可通行点。
const IDENTITY_SPAWN_OFFSET: Vector2 = Vector2(0.0, 140.0)
## 直接调用 create_new_world() 未传身份时的默认正式身份（仅测试/兼容入口）。
const DEFAULT_IDENTITY_ID: String = "IDENTITY_EKTOR_SECOND_SON"
## 家族部队出生点相对家族驻地地点的偏移。
const FAMILY_PARTY_OFFSET: Vector2 = Vector2(0.0, 96.0)
## 同一家族多名贵族各自部队的错位，避免所有部队重叠在同一坐标。
const FAMILY_NOBLE_PARTY_OFFSETS: Array[Vector2] = [
	Vector2(0.0, 0.0),
	Vector2(90.0, 0.0),
	Vector2(-90.0, 0.0),
	Vector2(0.0, 90.0),
]
const FAMILY_PATROL_RADIUS: float = 200.0


## 返回是否创建成功。
static func create_new_world(
	context: WorldContext, identity: IdentityDefinition = null
) -> bool:
	if context == null:
		return false
	if identity == null:
		identity = _load_default_identity()
	if identity == null or not identity.validate():
		push_error("新游戏身份配置无效，无法创建世界")
		return false

	context.world_id = context.id_generator.next_id(IdGenerator.WORLD)
	context.world_created_at = Time.get_datetime_string_from_system()
	context.world_size = WorldContext.DEFAULT_WORLD_SIZE
	if not context.setup_world_terrain(context.world_size):
		push_error("大地图地形装配失败，无法创建新世界")
		return false
	var definition: WorldMapDefinition = context.world_map_definition
	if definition == null:
		push_error("缺少大地图定义，无法创建新世界")
		return false
	if definition.get_settlement_definition(identity.spawn_location_id).is_empty():
		push_error(
			"身份 %s 的出生地点不存在: %s"
			% [identity.identity_id, identity.spawn_location_id]
		)
		return false

	# 家族先于贵族/封地建立，避免初始化过程中出现悬空 house_id。
	# 玩家不再拥有独立测试家族：贵族身份复用正式家族，平民不创建家族。
	for spec: Dictionary in _family_specs():
		var house := context.house_manager.register_house(
			str(spec["house_id"]),
			str(spec["house_name"]),
			str(spec["family_id"])
		)
		if house == null:
			push_error("初始家族注册失败: %s" % str(spec["house_id"]))
			return false

	# 基础 NPC 部队：商队与三支强盗。位置围绕对应地点生成。
	var merchant_party := context.party_manager.create_party(
		MERCHANT_FACTION_ID,
		definition.get_settlement_world_position("bari"),
		TEST_ENEMY_PARTY_NAME,
		PartyData.PartyKind.MERCHANT
	)
	if merchant_party != null:
		merchant_party.movement_speed = MERCHANT_MOVE_SPEED
		merchant_party.sight_range = NPC_SIGHT_RANGE

	var bandit_party := _create_bandit(
		context, BANDIT_PARTY_NAME,
		definition.get_settlement_world_position("dindani") + Vector2(0.0, -110.0)
	)
	var east_bandits := _create_bandit(
		context, EAST_BANDIT_PARTY_NAME,
		definition.get_settlement_world_position("lidon") + Vector2(0.0, 110.0)
	)
	var waste_bandits := _create_bandit(
		context, WASTE_BANDIT_PARTY_NAME,
		definition.get_settlement_world_position("frani") + Vector2(0.0, -120.0)
	)

	# 每个家族按显式配置生成全部指定贵族；每位贵族独立指挥一支家族部队。
	# 家族领袖只由 nobles 中 leader=true 的成员担任。若玩家身份直接接管该家族，
	# 配置中的原领袖仍作为普通成员存在，随后由玩家接管领袖标记。
	var family_leader_nobles: Dictionary = {}
	for spec: Dictionary in _family_specs():
		var family_id: String = str(spec["family_id"])
		var house_id: String = str(spec["house_id"])
		var short_name: String = str(spec["short_name"])
		var seat_position := definition.get_settlement_world_position(
			str(spec["seat_key"])
		)
		var player_takes_house: bool = identity.family_system_enabled \
			and identity.starts_as_house_leader and identity.family_id == family_id
		var noble_specs: Array = spec["nobles"] as Array
		for index: int in range(noble_specs.size()):
			var noble_spec: Dictionary = noble_specs[index] as Dictionary
			var noble_name: String = str(noble_spec["name"])
			var configured_leader: bool = bool(noble_spec.get("leader", false))
			var is_house_leader: bool = configured_leader and not player_takes_house
			var party_name: String = "%s骑士" % short_name if configured_leader \
				else "%s骑士" % noble_name
			var party := _create_family_party(
				context,
				family_id,
				party_name,
				_noble_party_position(context, seat_position, index)
			)
			if party == null:
				push_error("家族部队创建失败: %s/%s" % [family_id, noble_name])
				return false
			var rank_value: int = int(
				noble_spec.get("rank", int(NobleData.Rank.KNIGHT))
			)
			var noble: NobleData = context.noble_manager.create_noble(
				noble_name,
				LOCAL_FACTION_ID,
				party.party_id,
				house_id,
				rank_value as NobleData.Rank,
				false,
				is_house_leader
			)
			if noble == null:
				push_error("贵族创建失败: %s" % noble_name)
				return false
			party.leader_noble_id = noble.lord_id
			if is_house_leader:
				family_leader_nobles[family_id] = noble
			_set_patrol_route(
				party,
				_patrol_points_around(context, party.world_position)
			)

	# 玩家部队与身份：身份配置是出生位置、家族、爵位的唯一权威来源。
	var player_start := _safe_position(
		context,
		definition.get_settlement_world_position(identity.spawn_location_id)
			+ IDENTITY_SPAWN_OFFSET
	)
	var player_party := context.party_manager.create_party(
		PLAYER_FACTION_ID,
		player_start,
		"玩家部队",
		PartyData.PartyKind.PLAYER
	)
	if player_party == null:
		return false
	player_party.control_type = PartyData.ControlType.PLAYER
	player_party.movement_speed = PLAYER_MOVE_SPEED
	player_party.sight_range = PLAYER_SIGHT_RANGE
	context.player_party_id = player_party.party_id
	context.ai_manager.player_party_id = player_party.party_id
	context.battle_manager.player_party_id = player_party.party_id
	context.adventurer_recruitment_manager.player_party_id = player_party.party_id
	context.mercenary_manager.set_player_party_id(player_party.party_id)
	context.captivity_manager.set_player_party_id(player_party.party_id)

	context.player_identity_id = identity.identity_id
	context.player_identity_category_id = identity.category_id
	context.player_culture_id = identity.culture_id
	context.player_identity_name = identity.display_name

	if identity.family_system_enabled:
		var player_house_id: String = _house_id_for_family(identity.family_id)
		var player_house := context.house_manager.get_house(player_house_id)
		if player_house == null:
			push_error("身份家族不存在: %s" % identity.family_id)
			return false
		# 玩家加入正式家族后，该家族承担玩家家族职责；不创建第二份家族数据。
		player_house.is_player_house = true
		context.player_house_id = player_house_id
		player_party.family_id = identity.family_id
		var player_noble: NobleData = context.noble_manager.create_noble(
			identity.display_name,
			PLAYER_FACTION_ID,
			player_party.party_id,
			player_house_id,
			_rank_from_identity(identity),
			true,
			identity.starts_as_house_leader
		)
		if player_noble == null:
			push_error("玩家贵族身份创建失败")
			return false
		context.player_lord_id = player_noble.lord_id
		player_party.leader_noble_id = player_noble.lord_id
		if identity.starts_as_house_leader:
			# 接管统治家族时，王国注册必须使用玩家作为国王；
			# 独立家族身份会在王国注册阶段跳过该家族，玩家保持家族领袖而非国王。
			family_leader_nobles[identity.family_id] = player_noble
		# 玩家效忠关系与全部 NPC 成员一起在王国建立后统一写入。

	# 地点：名称/类型/坐标/视觉家族全部来自地图定义。
	var settlements_by_key: Dictionary = {}
	for value: Dictionary in definition.get_world_settlements():
		var key: String = str(value.get("key", ""))
		var settlement_type: int = int(value.get("type", 0))
		var economy := _settlement_economy(key, settlement_type)
		var settlement := _create_settlement(
			context,
			str(value.get("name", "")),
			settlement_type as SettlementData.SettlementType,
			value.get("world_position", Vector2.ZERO),
			economy.x,
			economy.y
		)
		if settlement == null:
			push_error("地点创建失败: %s" % key)
			return false
		settlement.family_id = str(value.get("family", ""))
		if settlement_type == SettlementData.SettlementType.VILLAGE:
			settlement.scene_path = DEFAULT_VILLAGE_SCENE_PATH
		settlements_by_key[key] = settlement

	# 封地所有权全部由家族配置显式给出；地图定义未列出的地点保持无主。
	# family_id（旗帜）与 owner_house_id（政治归属）仍是两个字段，
	# 但本次配置下领地旗帜与所有者一致，均来自同一份地图定义。
	for spec: Dictionary in _family_specs():
		var owner_house_id: String = str(spec["house_id"])
		for settlement_key: String in spec["settlements"] as Array:
			var settlement := settlements_by_key.get(settlement_key) as SettlementData
			if settlement == null:
				push_error("领地配置引用不存在的地点: %s" % settlement_key)
				return false
			_assign_owner(settlement, owner_house_id)

	# 六方势力：统治者 + 明确列出的附庸家族 + 民族。初始全部和平，
	# 不根据地图位置推断战争或领土。
	for spec: Dictionary in _kingdom_specs():
		var ruler_family: String = str(spec["ruler_family"])
		# 独立家族身份接管统治家族时不建立该王国：玩家明确选择不依附任何国家，
		# 家族保持独立，不能因旧地图配置被同步成国王。
		if identity.independent_house and identity.family_id == ruler_family:
			continue
		var king: NobleData = family_leader_nobles.get(ruler_family) as NobleData
		var house := context.house_manager.get_house(str(spec["ruler_house"]))
		if king == null or house == null:
			push_error("王国统治家族或国王缺失: %s" % str(spec["kingdom_id"]))
			return false
		var kingdom := context.kingdom_manager.register_kingdom(
			str(spec["kingdom_id"]),
			str(spec["kingdom_name"]),
			str(spec["ruler_house"]),
			king.lord_id,
			spec["color"] as Color
		)
		if kingdom == null:
			push_error("王国注册失败: %s" % str(spec["kingdom_id"]))
			return false
		kingdom.people_name = str(spec["people_name"])
		for vassal_family: String in spec["vassal_families"] as Array:
			var vassal_house_id: String = _house_id_for_family(vassal_family)
			if not context.kingdom_manager.add_vassal_house(
				kingdom.kingdom_id, vassal_house_id
			):
				push_error(
					"附庸家族加入王国失败: %s -> %s"
					% [vassal_family, kingdom.kingdom_id]
				)
				return false

	# 全部贵族与王国就位后统一写入效忠关系：
	# 家族普通成员效忠本家族领袖，附庸家族领袖效忠国王，国王无上级。
	_assign_lieges(context, family_leader_nobles)

	context.house_manager.refresh_settlement_links()

	# 商队与强盗路线在全部地点建立后写入；只使用稳定 settlement_id。
	_settlement_route(
		merchant_party, settlements_by_key, ["bari", "moxixi"]
	)
	if merchant_party != null:
		merchant_party.world_position = _settlement_position(
			settlements_by_key, "bari"
		)
		merchant_party.target_position = merchant_party.world_position
		merchant_party.movement_state = PartyData.MovementState.IDLE
		merchant_party.ai_type = PartyData.PartyAIType.TRADE_ROUTE
		merchant_party.ai_route_index = 0
	_set_bandit_route(bandit_party, settlements_by_key, ["dindani", "ogavina"])
	_set_bandit_route(east_bandits, settlements_by_key, ["berk_nania", "lidon"])
	_set_bandit_route(waste_bandits, settlements_by_key, ["moxixi", "frani"])

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
	# 部队领袖单位与贵族身份使用稳定 ID 绑定，俘虏售价/赎回都依赖它。
	if not bind_lord_unit_identities(context):
		push_error("部队领袖与贵族身份绑定失败")
		return false
	if not initialize_fief_economy(context):
		push_error("封地经济初始化失败")
		return false
	if not context.market_manager.ensure_markets():
		push_error("城镇市场初始化失败")
		return false
	# 雇佣兵池在所有城镇与酒馆归属建立后首次生成；读档不经过这里。
	context.mercenary_manager.initialize_world(true)

	return context.is_valid_world()


## 未显式传入身份时的正式默认身份；只用于兼容旧测试入口，正式新游戏始终传入选择结果。
static func _load_default_identity() -> IdentityDefinition:
	var catalog := IdentityCatalog.load_default()
	if catalog == null:
		return null
	return catalog.get_identity(DEFAULT_IDENTITY_ID)


## 身份配置的爵位按 NobleData.Rank 有效范围收敛，避免坏配置生成非法贵族。
static func _rank_from_identity(identity: IdentityDefinition) -> NobleData.Rank:
	var rank_value: int = clampi(
		identity.starting_rank,
		int(NobleData.Rank.KNIGHT),
		int(NobleData.Rank.DUKE)
	)
	return rank_value as NobleData.Rank


## 六方势力定义。只声明文档明确要求的统治者/附庸/民族，不推断领土。
static func _kingdom_specs() -> Array[Dictionary]:
	return [
		{
			"kingdom_id": KINGDOM_BURKNANIA_ID,
			"kingdom_name": BURKNANIA_KINGDOM_NAME,
			"people_name": PEOPLE_DORAMAN,
			"ruler_family": FAMILY_BURKNANIA_ID,
			"ruler_house": HOUSE_BURKNANIA_ID,
			"color": BURKNANIA_KINGDOM_COLOR,
			"vassal_families": [
				FAMILY_ODESTER_ID,
				FAMILY_EKTOR_ID,
				FAMILY_BAFLE_ID,
				FAMILY_BARI_ID,
			],
		},
		{
			"kingdom_id": KINGDOM_FRANI_ID,
			"kingdom_name": FRANI_KINGDOM_NAME,
			"people_name": PEOPLE_BUJIDUO,
			"ruler_family": FAMILY_FRANI_ID,
			"ruler_house": HOUSE_FRANI_ID,
			"color": FRANI_KINGDOM_COLOR,
			"vassal_families": [
				FAMILY_DINDANI_ID,
				FAMILY_KONLIA_ID,
				FAMILY_MIQIQI_ID,
			],
		},
		{
			"kingdom_id": KINGDOM_VAILA_ID,
			"kingdom_name": VAILA_KINGDOM_NAME,
			"people_name": PEOPLE_BUJIDUO,
			"ruler_family": FAMILY_VAILA_ID,
			"ruler_house": HOUSE_VAILA_ID,
			"color": VAILA_KINGDOM_COLOR,
			"vassal_families": [],
		},
		{
			"kingdom_id": KINGDOM_LORIAK_ID,
			"kingdom_name": LORIAK_KINGDOM_NAME,
			"people_name": PEOPLE_LORIS,
			"ruler_family": FAMILY_LORIAK_ID,
			"ruler_house": HOUSE_LORIAK_ID,
			"color": LORIAK_KINGDOM_COLOR,
			"vassal_families": [
				FAMILY_OLIN_ID,
				FAMILY_MOXIXI_ID,
				FAMILY_ROSVIK_ID,
			],
		},
		{
			"kingdom_id": KINGDOM_TAINA_ID,
			"kingdom_name": TAINA_KINGDOM_NAME,
			"people_name": PEOPLE_MONGKA,
			"ruler_family": FAMILY_TAINA_ID,
			"ruler_house": HOUSE_TAINA_ID,
			"color": TAINA_KINGDOM_COLOR,
			"vassal_families": [],
		},
		{
			"kingdom_id": KINGDOM_VALEMON_ID,
			"kingdom_name": VALEMON_KINGDOM_NAME,
			"people_name": PEOPLE_MONGKA,
			"ruler_family": FAMILY_VALEMON_ID,
			"ruler_house": HOUSE_VALEMON_ID,
			"color": VALEMON_KINGDOM_COLOR,
			"vassal_families": [FAMILY_KRIKA_ID],
		},
	]


## 17 个 NPC 家族的完整初始配置：家族 ID、名称、驻地、全部指定贵族与领地。
## 贵族名单、爵位与领地归属是本次需求文档的最终依据；顺序稳定，便于测试与读档。
## 每个家族恰有一名 leader=true 的领袖（玩家接管领袖时该成员降为普通成员）。
static func _family_specs() -> Array[Dictionary]:
	return [
		{
			"family_id": FAMILY_BURKNANIA_ID, "house_id": HOUSE_BURKNANIA_ID,
			"house_name": BURKNANIA_HOUSE_NAME, "short_name": "伯克纳",
			"seat_key": "berk_nania",
			"nobles": [
				{"name": "奥东·德·伯克纳", "rank": NobleData.Rank.DUKE, "leader": true},
				{"name": "坦雷德·德·伯克纳", "rank": NobleData.Rank.BARON},
				{"name": "福克尔·德·伯克纳", "rank": NobleData.Rank.KNIGHT},
				{"name": "迪博·德·伯克纳", "rank": NobleData.Rank.KNIGHT},
			],
			"settlements": ["berk_nania", "berk_na", "lidon", "duofer", "grey_fort"],
		},
		{
			"family_id": FAMILY_ODESTER_ID, "house_id": HOUSE_ODESTER_ID,
			"house_name": ODESTER_HOUSE_NAME, "short_name": "奥德斯特",
			"seat_key": "odester",
			"nobles": [
				{"name": "罗杰·德·奥德斯特", "rank": NobleData.Rank.BARON, "leader": true},
				{"name": "于格·德·奥德斯特", "rank": NobleData.Rank.KNIGHT},
				{"name": "理查·德·奥德斯特", "rank": NobleData.Rank.KNIGHT},
			],
			"settlements": ["odester_castle", "odester", "osway"],
		},
		{
			"family_id": FAMILY_EKTOR_ID, "house_id": HOUSE_EKTOR_ID,
			"house_name": EKTOR_HOUSE_NAME, "short_name": "埃克托",
			"seat_key": "ektor_town",
			"nobles": [
				{"name": "阿莫里·德·埃克托", "rank": NobleData.Rank.DUKE, "leader": true},
				{"name": "雷诺·德·埃克托", "rank": NobleData.Rank.BARON},
				{"name": "杰弗里·德·埃克托", "rank": NobleData.Rank.KNIGHT},
				{"name": "阿马里·德·埃克托", "rank": NobleData.Rank.KNIGHT},
			],
			"settlements": [
				"ektor_town", "ektor_village", "ogavina",
				"kasman_fort", "kasman", "sagatos",
			],
		},
		{
			"family_id": FAMILY_BAFLE_ID, "house_id": HOUSE_BAFLE_ID,
			"house_name": BAFLE_HOUSE_NAME, "short_name": "巴夫勒",
			"seat_key": "bafleborg",
			"nobles": [
				{"name": "威廉·德·巴夫勒", "rank": NobleData.Rank.BARON, "leader": true},
				{"name": "罗贝尔·德·巴夫勒", "rank": NobleData.Rank.KNIGHT},
			],
			"settlements": ["bafleborg", "bafle"],
		},
		{
			"family_id": FAMILY_BARI_ID, "house_id": HOUSE_BARI_ID,
			"house_name": BARI_HOUSE_NAME, "short_name": "巴里",
			"seat_key": "bari",
			"nobles": [
				{"name": "埃尔韦·德·巴里", "rank": NobleData.Rank.BARON, "leader": true},
				{"name": "吉尔·德·巴里", "rank": NobleData.Rank.KNIGHT},
				{"name": "伊夫·德·巴里", "rank": NobleData.Rank.KNIGHT},
			],
			"settlements": ["doro", "bari_fort", "bari"],
		},
		{
			"family_id": FAMILY_FRANI_ID, "house_id": HOUSE_FRANI_ID,
			"house_name": FRANI_HOUSE_NAME, "short_name": "弗拉尼",
			"seat_key": "frania",
			"nobles": [
				{"name": "奥利维耶", "rank": NobleData.Rank.DUKE, "leader": true},
				{"name": "埃利亚斯", "rank": NobleData.Rank.BARON},
				{"name": "塞普兰", "rank": NobleData.Rank.KNIGHT},
				{"name": "瓦尔萨", "rank": NobleData.Rank.KNIGHT},
			],
			"settlements": ["frania", "frani", "aderida", "kao_castle", "kao"],
		},
		{
			"family_id": FAMILY_DINDANI_ID, "house_id": HOUSE_DINDANI_ID,
			"house_name": DINDANI_HOUSE_NAME, "short_name": "丁达尼",
			"seat_key": "dindani",
			"nobles": [
				{"name": "康拉", "rank": NobleData.Rank.BARON, "leader": true},
				{"name": "戈弗雷", "rank": NobleData.Rank.KNIGHT},
			],
			"settlements": ["dindani_castle", "dindani"],
		},
		{
			"family_id": FAMILY_KONLIA_ID, "house_id": HOUSE_KONLIA_ID,
			"house_name": KONLIA_HOUSE_NAME, "short_name": "康利亚",
			"seat_key": "konlia",
			"nobles": [
				{"name": "圣维克", "rank": NobleData.Rank.BARON, "leader": true},
				{"name": "阿斯塔尔", "rank": NobleData.Rank.KNIGHT},
			],
			"settlements": ["konlia_castle", "konlia"],
		},
		{
			"family_id": FAMILY_MIQIQI_ID, "house_id": HOUSE_MIQIQI_ID,
			"house_name": MIQIQI_HOUSE_NAME, "short_name": "米奇奇",
			"seat_key": "michi",
			"nobles": [
				{"name": "休", "rank": NobleData.Rank.BARON, "leader": true},
				{"name": "曼", "rank": NobleData.Rank.KNIGHT},
				{"name": "雷", "rank": NobleData.Rank.KNIGHT},
			],
			"settlements": ["michinia", "michi", "laris"],
		},
		{
			"family_id": FAMILY_VAILA_ID, "house_id": HOUSE_VAILA_ID,
			"house_name": VAILA_HOUSE_NAME, "short_name": "瓦伊拉",
			"seat_key": "vaila",
			"nobles": [
				{"name": "瓦尔登", "rank": NobleData.Rank.BARON, "leader": true},
				{"name": "林登", "rank": NobleData.Rank.KNIGHT},
			],
			"settlements": ["vaila_castle", "vaila"],
		},
		{
			"family_id": FAMILY_LORIAK_ID, "house_id": HOUSE_LORIAK_ID,
			"house_name": LORIAK_HOUSE_NAME, "short_name": "洛里亚克",
			"seat_key": "loriaknia",
			"nobles": [
				{"name": "菲利普", "rank": NobleData.Rank.DUKE, "leader": true},
				{"name": "蒙特雷", "rank": NobleData.Rank.BARON},
				{"name": "阿诺", "rank": NobleData.Rank.KNIGHT},
				{"name": "维朗", "rank": NobleData.Rank.KNIGHT},
			],
			"settlements": [
				"loriaknia", "loriak", "os", "bunis_fort", "bunis", "fava",
			],
		},
		{
			"family_id": FAMILY_OLIN_ID, "house_id": HOUSE_OLIN_ID,
			"house_name": OLIN_HOUSE_NAME, "short_name": "奥林",
			"seat_key": "olin",
			"nobles": [
				{"name": "卡斯泰尔", "rank": NobleData.Rank.BARON, "leader": true},
				{"name": "纳瓦尔", "rank": NobleData.Rank.KNIGHT},
			],
			"settlements": ["olindesburg", "olin"],
		},
		{
			"family_id": FAMILY_MOXIXI_ID, "house_id": HOUSE_MOXIXI_ID,
			"house_name": MOXIXI_HOUSE_NAME, "short_name": "墨西西",
			"seat_key": "moxixi",
			"nobles": [
				{"name": "墨西西里曼", "rank": NobleData.Rank.BARON, "leader": true},
				{"name": "墨西西维克", "rank": NobleData.Rank.KNIGHT},
			],
			"settlements": ["moxixi_castle", "moxixi"],
		},
		{
			"family_id": FAMILY_ROSVIK_ID, "house_id": HOUSE_ROSVIK_ID,
			"house_name": ROSVIK_HOUSE_NAME, "short_name": "罗斯维克",
			"seat_key": "rosvik",
			"nobles": [
				{"name": "蒙塞尔", "rank": NobleData.Rank.DUKE, "leader": true},
				{"name": "迪纳", "rank": NobleData.Rank.KNIGHT},
				{"name": "巴特", "rank": NobleData.Rank.KNIGHT},
				{"name": "雷斯", "rank": NobleData.Rank.KNIGHT},
			],
			"settlements": ["rosviknia", "rosvik", "brachy", "riban"],
		},
		{
			"family_id": FAMILY_TAINA_ID, "house_id": HOUSE_TAINA_ID,
			"house_name": TAINA_HOUSE_NAME, "short_name": "泰纳",
			"seat_key": "tainania",
			"nobles": [
				{"name": "贝洛夫", "rank": NobleData.Rank.DUKE, "leader": true},
				{"name": "米尔斯克", "rank": NobleData.Rank.BARON},
				{"name": "切尔诺夫", "rank": NobleData.Rank.KNIGHT},
				{"name": "拉多维奇", "rank": NobleData.Rank.KNIGHT},
			],
			"settlements": [
				"tainania", "taina", "borvalas", "betenu_castle", "betenu",
			],
		},
		{
			"family_id": FAMILY_VALEMON_ID, "house_id": HOUSE_VALEMON_ID,
			"house_name": VALEMON_HOUSE_NAME, "short_name": "瓦勒蒙",
			"seat_key": "valemonia",
			"nobles": [
				{"name": "卢卡", "rank": NobleData.Rank.BARON, "leader": true},
				{"name": "霍拉", "rank": NobleData.Rank.BARON},
				{"name": "索博尔", "rank": NobleData.Rank.KNIGHT},
				{"name": "巴尔科", "rank": NobleData.Rank.KNIGHT},
			],
			"settlements": [
				"valemonia", "valemon", "sados", "achia_fort", "achi",
			],
		},
		{
			"family_id": FAMILY_KRIKA_ID, "house_id": HOUSE_KRIKA_ID,
			"house_name": KRIKA_HOUSE_NAME, "short_name": "克里卡",
			"seat_key": "krika",
			"nobles": [
				{"name": "杜布拉", "rank": NobleData.Rank.BARON, "leader": true},
				{"name": "切尔维", "rank": NobleData.Rank.KNIGHT},
			],
			"settlements": ["krika_fort", "krika"],
		},
	]


## 同一家族的多名贵族围绕驻地错位出生，并统一收敛到可通行点。
static func _noble_party_position(
	context: WorldContext, seat_position: Vector2, index: int
) -> Vector2:
	var offset := FAMILY_NOBLE_PARTY_OFFSETS[
		index % FAMILY_NOBLE_PARTY_OFFSETS.size()
	]
	return _safe_position(context, seat_position + FAMILY_PARTY_OFFSET + offset)


## 写入贵族效忠链：普通成员效忠本家族领袖，附庸家族领袖效忠国王。
## 玩家贵族若只是家族成员，同样通过本函数效忠家族领袖。
static func _assign_lieges(
	context: WorldContext, leader_nobles: Dictionary
) -> void:
	if context == null or context.noble_manager == null:
		return
	for spec: Dictionary in _family_specs():
		var house_id: String = str(spec["house_id"])
		var leader: NobleData = leader_nobles.get(
			str(spec["family_id"])
		) as NobleData
		if leader == null:
			continue
		for noble: NobleData in context.noble_manager.get_nobles_of_house(house_id):
			if noble == null or noble.lord_id == leader.lord_id:
				continue
			context.noble_manager.set_liege(noble.lord_id, leader.lord_id)
	for kingdom_spec: Dictionary in _kingdom_specs():
		var king: NobleData = leader_nobles.get(
			str(kingdom_spec["ruler_family"])
		) as NobleData
		if king == null:
			continue
		for vassal_family: String in kingdom_spec["vassal_families"] as Array:
			var vassal_leader: NobleData = leader_nobles.get(
				vassal_family
			) as NobleData
			if vassal_leader != null:
				context.noble_manager.set_liege(
					vassal_leader.lord_id, king.lord_id
				)


static func _house_id_for_family(family_id: String) -> String:
	for spec: Dictionary in _family_specs():
		if str(spec["family_id"]) == family_id:
			return str(spec["house_id"])
	return ""


## 把每支 NPC 部队的领袖单位与指挥贵族绑定。
## 只用稳定 ID（party.leader_noble_id / leader_unit_id），不依赖名称或节点。
static func bind_lord_unit_identities(context: WorldContext) -> bool:
	if context == null:
		return false
	for party: PartyData in context.party_manager.get_all_parties():
		if party == null or party.is_player_controlled() \
				or party.leader_noble_id.is_empty():
			continue
		var leader := context.unit_manager.get_unit(party.leader_unit_id)
		if leader == null or leader.is_player_character:
			continue
		leader.noble_id = party.leader_noble_id
		if leader.family_id.is_empty():
			leader.family_id = party.family_id
	return true


## 赎回后复用原部队：把领主放回领袖位置，并按家族骑士编制补齐士兵。
## 不删除幸存成员，也不创建第二支同贵族部队；调用方负责重置位置/AI 状态。
static func restore_lord_party(
	context: WorldContext,
	party: PartyData,
	noble: NobleData,
	leader_unit: UnitData
) -> bool:
	if context == null or party == null or noble == null or leader_unit == null:
		return false
	var militia: UnitConfig = load(MILITIA_CONFIG_PATH) as UnitConfig
	var trained: UnitConfig = load(TRAINED_CONFIG_PATH) as UnitConfig
	var veteran: UnitConfig = load(VETERAN_CONFIG_PATH) as UnitConfig
	if militia == null or trained == null or veteran == null:
		push_error("赎回部队配置加载失败")
		return false

	# 领主必须重新成为该部队成员，并占据领袖位置。
	if leader_unit.current_party_id != party.party_id:
		if not leader_unit.current_party_id.is_empty():
			context.party_manager.remove_member(
				leader_unit.current_party_id, leader_unit.unit_id
			)
		if not party.member_unit_ids.has(leader_unit.unit_id) \
				and not context.party_manager.add_member(
					party.party_id, leader_unit.unit_id
				):
			push_error("赎回领主无法重新加入部队: %s" % leader_unit.unit_id)
			return false
	leader_unit.noble_id = noble.lord_id
	party.leader_unit_id = leader_unit.unit_id
	party.leader_noble_id = noble.lord_id
	if party.family_id.is_empty():
		var house := context.house_manager.get_house(noble.house_id)
		if house != null:
			party.family_id = house.banner_id

	var family := context.family_registry.get_config(party.family_id)
	var existing: Dictionary = {}
	for unit_id: String in party.member_unit_ids:
		if unit_id == leader_unit.unit_id:
			continue
		var unit := context.unit_manager.get_unit(unit_id)
		if unit == null:
			continue
		var key: String = _roster_key(unit.config_id, unit.is_mounted)
		existing[key] = int(existing.get(key, 0)) + 1

	var roster: Array[Dictionary] = [
		{"config": veteran, "mounted": true, "count": FAMILY_MOUNTED_SQUIRE_COUNT},
		{"config": trained, "mounted": true, "count": FAMILY_MOUNTED_SERGEANT_COUNT},
		{"config": trained, "mounted": false, "count": FAMILY_SERGEANT_COUNT},
		{"config": militia, "mounted": false, "count": FAMILY_INFANTRY_COUNT},
	]
	for entry: Dictionary in roster:
		var config := entry["config"] as UnitConfig
		var mounted: bool = bool(entry["mounted"])
		var key: String = _roster_key(config.config_id, mounted)
		var have: int = int(existing.get(key, 0))
		var need: int = maxi(0, int(entry["count"]) - have)
		for i: int in range(need):
			if _create_world_unit(
				context, party, config, family, "", 0, false, mounted
			) == null:
				return false
	return true


static func _roster_key(config_id: String, mounted: bool) -> String:
	return "%s|%d" % [config_id, 1 if mounted else 0]


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


## 调试用测试兵力：玩家部队、家族骑士与普通 NPC 部队统一按类型填充。
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

	for party: PartyData in context.party_manager.get_all_parties():
		if party == null or party.party_id == context.player_party_id:
			continue
		if party.party_kind == PartyData.PartyKind.FAMILY:
			var family := context.family_registry.get_config(party.family_id)
			if family == null:
				push_error("测试兵力缺少家族配置: %s" % party.family_id)
				return false
			var leader_noble := context.noble_manager.get_noble(party.leader_noble_id)
			var leader_name: String = leader_noble.display_name \
				if leader_noble != null else party.party_name
			if not _populate_family_party(
				context, party, family, leader_name, militia, trained, veteran
			):
				return false
		else:
			if not _populate_test_party(context, party, militia, trained):
				return false
	_seed_party_supplies(context)
	return true


## 新世界补给初始值。玩家与 NPC 使用完全相同的物品字段与每日消耗规则，
## 区别只在数量：玩家 7 天、NPC 2 天，NPC 随后会自行前往市场补到 7 天。
static func _seed_party_supplies(context: WorldContext) -> void:
	if context == null or context.supply_manager == null:
		return
	context.supply_manager.set_player_party_id(context.player_party_id)
	context.supply_manager.reset_settlement_day()
	for party: PartyData in context.party_manager.get_all_parties():
		if party == null:
			continue
		if party.is_player_controlled() or party.party_id == context.player_party_id:
			var player_members: int = context.supply_manager.get_member_count(party)
			var player_mounts: int = context.supply_manager.get_total_mount_count(party)
			if player_members > 0 \
					and context.player_profile.get_item_count(SupplyManager.BREAD_ID) <= 0:
				context.player_profile.add_item(
					SupplyManager.BREAD_ID,
					player_members * PLAYER_STARTING_SUPPLY_DAYS
				)
			if player_mounts > 0 \
					and context.player_profile.get_item_count(SupplyManager.FODDER_ID) <= 0:
				context.player_profile.add_item(
					SupplyManager.FODDER_ID,
					player_mounts * PLAYER_STARTING_SUPPLY_DAYS
				)
			continue
		# 强盗没有稳定经济，不初始化市场补给；其余 NPC 部队与玩家共用规则。
		if party.party_kind == PartyData.PartyKind.BANDIT:
			continue
		var members: int = context.supply_manager.get_member_count(party)
		var mounts: int = context.supply_manager.get_total_mount_count(party)
		if members > 0 and party.get_item_count(SupplyManager.BREAD_ID) <= 0:
			party.add_item(
				SupplyManager.BREAD_ID, members * NPC_STARTING_SUPPLY_DAYS
			)
		if mounts > 0 and party.get_item_count(SupplyManager.FODDER_ID) <= 0:
			party.add_item(
				SupplyManager.FODDER_ID, mounts * NPC_STARTING_SUPPLY_DAYS
			)
		if party.gold <= 0:
			party.gold = NPC_STARTING_GOLD


## 玩家部队：5 民兵 + 6 职业步兵（前 4 名骑乘）+ 3 弓箭手
## + 玩家角色（最后加入，保持 UI 默认选中民兵）。
static func _populate_player_party(
	context: WorldContext, party: PartyData, militia: UnitConfig, trained: UnitConfig
) -> bool:
	if not party.member_unit_ids.is_empty():
		return true
	# 新游戏给玩家一笔可支撑初期市场交易的启动资金；已有存档不经过这里。
	if context.player_profile.gold < PLAYER_STARTING_GOLD:
		context.player_profile.add_gold(
			PLAYER_STARTING_GOLD - context.player_profile.gold
		)
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

	# 玩家外观家族来自身份绑定；平民不拥有家族，使用无家族外观。
	var player_family: FamilyConfig = null
	if not party.family_id.is_empty():
		player_family = context.family_registry.get_config(party.family_id)
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


static func _create_bandit(
	context: WorldContext, party_name: String, desired_position: Vector2
) -> PartyData:
	var party := context.party_manager.create_party(
		BANDIT_FACTION_ID,
		_safe_position(context, desired_position),
		party_name,
		PartyData.PartyKind.BANDIT
	)
	if party == null:
		return null
	party.movement_speed = BANDIT_MOVE_SPEED
	party.sight_range = BANDIT_SIGHT_RANGE
	return party


## 统一写入封地的家族所有权；不修改 family_id（视觉旗帜）。
## 领地只归属于家族，不再写入任何个人所有者字段。
static func _assign_owner(
	settlement: SettlementData, house_id: String
) -> void:
	if settlement == null:
		return
	settlement.owner_house_id = house_id


static func _settlement_route(
	party: PartyData, settlements_by_key: Dictionary, keys: Array
) -> void:
	if party == null:
		return
	var route: Array[String] = []
	for key: String in keys:
		var settlement := settlements_by_key.get(key) as SettlementData
		if settlement != null:
			route.append(settlement.settlement_id)
	party.ai_route_settlement_ids = route


static func _set_bandit_route(
	party: PartyData, settlements_by_key: Dictionary, keys: Array
) -> void:
	if party == null:
		return
	_settlement_route(party, settlements_by_key, keys)
	party.ai_type = PartyData.PartyAIType.BANDIT
	party.ai_route_index = 0
	party.target_position = party.world_position
	party.movement_state = PartyData.MovementState.IDLE


static func _settlement_position(
	settlements_by_key: Dictionary, key: String
) -> Vector2:
	var settlement := settlements_by_key.get(key) as SettlementData
	return settlement.world_position if settlement != null else Vector2.ZERO


static func _set_patrol_route(party: PartyData, points: Array[Vector2]) -> void:
	if party == null:
		return
	party.ai_type = PartyData.PartyAIType.PATROL
	party.ai_route_index = 0
	party.ai_patrol_points = points


## 围绕驻地生成 4 个巡逻点；全部收敛到可通行区域，避免巡逻进山/入湖。
static func _patrol_points_around(
	context: WorldContext, center: Vector2
) -> Array[Vector2]:
	var offsets: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(FAMILY_PATROL_RADIUS, FAMILY_PATROL_RADIUS * 0.6),
		Vector2(-FAMILY_PATROL_RADIUS * 0.8, FAMILY_PATROL_RADIUS * 0.8),
		Vector2(FAMILY_PATROL_RADIUS * 0.5, -FAMILY_PATROL_RADIUS),
	]
	var result: Array[Vector2] = []
	for offset: Vector2 in offsets:
		result.append(_safe_position(context, center + offset))
	return result


static func _safe_position(context: WorldContext, desired: Vector2) -> Vector2:
	if context != null and context.world_terrain != null:
		return context.world_terrain.nearest_passable_point(desired)
	var world_size: Vector2 = context.world_size if context != null \
		else WorldContext.DEFAULT_WORLD_SIZE
	var margin := Vector2(40.0, 40.0)
	return Vector2(
		clampf(desired.x, margin.x, world_size.x - margin.x),
		clampf(desired.y, margin.y, world_size.y - margin.y)
	)


## 地点人口/繁荣按类型给固定区间，并用 key 的稳定权重做轻微差异；
## 不使用随机数，保证每次新游戏同一地点数值一致。
static func _settlement_economy(key: String, settlement_type: int) -> Vector2i:
	var weight: int = _stable_weight(key)
	match settlement_type:
		SettlementData.SettlementType.TOWN:
			return Vector2i(220 + weight % 61, 60 + weight % 21)
		SettlementData.SettlementType.CASTLE:
			return Vector2i(0, 55 + weight % 26)
		_:
			return Vector2i(80 + weight % 71, 30 + weight % 21)


static func _stable_weight(value: String) -> int:
	var total: int = 0
	for index: int in range(value.length()):
		total += value.unicode_at(index) * (index + 1)
	return total


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
