class_name FactionManager
extends RefCounted
## 阵营注册与关系查询的唯一入口。
##
## 阵营静态关系每次重建；玩家主动宣战产生的持续敌对关系随存档保存。
## AI 只能通过本类判断敌对/友好，不允许各自硬编码阵营列表。

enum Relation {
	FRIENDLY,
	NEUTRAL,
	HOSTILE,
}

## 以玩家为中心的阵营关系（大地图表现与交互统一使用）。
enum PlayerRelation {
	ALLIED,
	NEUTRAL,
	HOSTILE,
}

const PLAYER_FACTION_ID: String = "FACTION_PLAYER"
const MERCHANT_FACTION_ID: String = "FACTION_MERCHANT"
const BANDIT_FACTION_ID: String = "FACTION_BANDIT"
const GUARD_FACTION_ID: String = "FACTION_GUARD"
const LOCAL_FACTION_ID: String = "FACTION_LOCAL"

## { faction_id: display_name }
var _display_names: Dictionary = {}
## { "A|B": Relation }，键按字典序排列，保证关系对称。
var _relations: Dictionary = {}
## 家族之间的显式关系；当前主要由王国战争推导，保留扩展入口。
var _house_relations: Dictionary = {}
## 玩家主动宣战产生的个人敌对关系；随存档保存（SaveData.factions）。
## 玩家未加入王国时也能保持王国层面的敌对，不依赖玩家所属王国。
var _player_hostile_house_ids: Array[String] = []
var _player_hostile_kingdom_ids: Array[String] = []

## 政治关系查询所需的只读引用；不保存数据副本。
var _party_manager: PartyManager = null
var _noble_manager: NobleManager = null
var _house_manager: HouseManager = null
var _kingdom_manager: KingdomManager = null
var _settlement_manager: SettlementManager = null


## `party_manager` 只用于部队级关系查询（政治身份回退）。
## 生产环境由 `setup_political()` 注入完整政治实体；独立测试可只传部队仓储。
func setup_defaults(party_manager: PartyManager = null) -> void:
	_display_names.clear()
	_relations.clear()
	_house_relations.clear()
	_player_hostile_house_ids.clear()
	_player_hostile_kingdom_ids.clear()
	if party_manager != null:
		_party_manager = party_manager

	register_faction(PLAYER_FACTION_ID, "玩家")
	register_faction(MERCHANT_FACTION_ID, "商队")
	register_faction(BANDIT_FACTION_ID, "强盗")
	register_faction(GUARD_FACTION_ID, "治安队")
	register_faction(LOCAL_FACTION_ID, "本地势力")

	set_relation(PLAYER_FACTION_ID, MERCHANT_FACTION_ID, Relation.NEUTRAL)
	set_relation(PLAYER_FACTION_ID, BANDIT_FACTION_ID, Relation.HOSTILE)
	set_relation(PLAYER_FACTION_ID, GUARD_FACTION_ID, Relation.NEUTRAL)
	set_relation(MERCHANT_FACTION_ID, BANDIT_FACTION_ID, Relation.HOSTILE)
	set_relation(MERCHANT_FACTION_ID, GUARD_FACTION_ID, Relation.FRIENDLY)
	set_relation(BANDIT_FACTION_ID, GUARD_FACTION_ID, Relation.HOSTILE)


## 接入政治实体后，FactionManager 成为家族/王国关系的统一查询入口。
## AI、遭遇、战斗与 UI 不得绕过本类自行解析王国敌对关系。
func setup_political(
	party_manager: PartyManager,
	noble_manager: NobleManager,
	house_manager: HouseManager,
	kingdom_manager: KingdomManager,
	settlement_manager: SettlementManager = null
) -> void:
	_party_manager = party_manager
	_noble_manager = noble_manager
	_house_manager = house_manager
	_kingdom_manager = kingdom_manager
	_settlement_manager = settlement_manager


func register_faction(faction_id: String, display_name: String) -> bool:
	if faction_id.strip_edges().is_empty():
		return false
	if _display_names.has(faction_id):
		push_error("阵营重复注册，拒绝覆盖: %s" % faction_id)
		return false
	_display_names[faction_id] = display_name if not display_name.is_empty() else faction_id
	return true


## 注册/覆盖两个阵营之间的关系。同一阵营始终为友好，不写入表。
func set_relation(a: String, b: String, relation: Relation) -> bool:
	if a.strip_edges().is_empty() or b.strip_edges().is_empty() or a == b:
		return false
	_relations[_relation_key(a, b)] = relation
	return true


func get_relation(a: String, b: String) -> Relation:
	if a == b:
		return Relation.FRIENDLY
	if a.is_empty() or b.is_empty():
		return Relation.NEUTRAL
	var value: Variant = _relations.get(_relation_key(a, b))
	if value is int:
		return int(value) as Relation
	return Relation.NEUTRAL


func is_hostile(a: String, b: String) -> bool:
	return get_relation(a, b) == Relation.HOSTILE


func is_friendly(a: String, b: String) -> bool:
	return get_relation(a, b) == Relation.FRIENDLY


func is_neutral(a: String, b: String) -> bool:
	return get_relation(a, b) == Relation.NEUTRAL


## 为家族显式设置关系（未来外交接口预留）；同家族始终友好，不写入表。
func set_house_relation(a: String, b: String, relation: Relation) -> bool:
	if a.strip_edges().is_empty() or b.strip_edges().is_empty() or a == b:
		return false
	_house_relations[_relation_key(a, b)] = relation
	return true


## 部队所属家族：优先读取指挥贵族的家族，其次回退到 PartyData.family_id。
## 该函数只查询，不修改任何数据。
func get_party_house_id(party_id: String) -> String:
	if _party_manager == null or party_id.is_empty():
		return ""
	var party := _party_manager.get_party(party_id)
	if party == null:
		return ""
	if _noble_manager != null and not party.leader_noble_id.is_empty():
		var noble := _noble_manager.get_noble(party.leader_noble_id)
		if noble != null and not noble.house_id.is_empty():
			return noble.house_id
	if not party.family_id.is_empty() and _house_manager != null:
		# PartyData.family_id 是视觉家族 ID；通过 banner_id 映射到政治家族。
		if _house_manager.has_house(party.family_id):
			return party.family_id
		var house := _house_manager.get_house_by_banner_id(party.family_id)
		if house != null:
			return house.house_id
	return ""


## 家族之间的政治关系：
## - 同家族、同王国友好；
## - 不同王国按王国战争关系决定；
## - 玩家家族按玩家阵营关系判定，未参战时默认中立；
## - 独立家族默认中立，可被显式关系覆盖。
func get_house_relation(a: String, b: String) -> Relation:
	if a == b:
		return Relation.FRIENDLY
	if a.is_empty() or b.is_empty():
		return Relation.NEUTRAL
	var explicit: Variant = _house_relations.get(_relation_key(a, b))
	if explicit is int:
		return int(explicit) as Relation

	var house_a := _house_manager.get_house(a) if _house_manager != null else null
	var house_b := _house_manager.get_house(b) if _house_manager != null else null
	if house_a == null or house_b == null:
		return Relation.NEUTRAL
	if house_a.is_player_house:
		return _player_relation_to_relation(get_player_relation_for_house(b))
	if house_b.is_player_house:
		return _player_relation_to_relation(get_player_relation_for_house(a))
	if not house_a.kingdom_id.is_empty() and house_a.kingdom_id == house_b.kingdom_id:
		return Relation.FRIENDLY
	if not house_a.kingdom_id.is_empty() and not house_b.kingdom_id.is_empty():
		if _kingdom_manager != null \
				and _kingdom_manager.are_at_war(house_a.kingdom_id, house_b.kingdom_id):
			return Relation.HOSTILE
		return Relation.NEUTRAL
	return Relation.NEUTRAL


## 以玩家为中心的家族关系。所有大地图阵营表现与交互都调用本接口，
## 不允许 UI/AI 自行解析玩家家族、所属王国或宣战记录。
## - 玩家家族本身：同阵营；
## - 玩家所属王国及其成员家族：同阵营；
## - 玩家所属王国的敌对王国成员家族：敌对；
## - 玩家主动宣战记录：敌对（无王国时也能生效）；
## - 其余：中立。
func get_player_relation_for_house(house_id: String) -> PlayerRelation:
	if house_id.is_empty() or _house_manager == null:
		return PlayerRelation.NEUTRAL
	var player_house := _get_player_house()
	if player_house == null:
		return PlayerRelation.NEUTRAL
	if house_id == player_house.house_id:
		return PlayerRelation.ALLIED
	var target := _house_manager.get_house(house_id)
	if target == null:
		return PlayerRelation.NEUTRAL

	var player_kingdom_id: String = player_house.kingdom_id
	# 加入目标王国后，同王国成员一律同阵营；旧个人宣战不覆盖入籍结果。
	if not player_kingdom_id.is_empty() and target.kingdom_id == player_kingdom_id:
		return PlayerRelation.ALLIED

	# 玩家主动攻击产生的个人敌对关系；优先于普通王国关系。
	if _player_hostile_house_ids.has(house_id):
		return PlayerRelation.HOSTILE
	if not target.kingdom_id.is_empty() \
			and _player_hostile_kingdom_ids.has(target.kingdom_id):
		return PlayerRelation.HOSTILE

	if player_kingdom_id.is_empty():
		# 未加入王国：不从目标家族所属王国的外交关系推导同阵营。
		return PlayerRelation.NEUTRAL
	if not target.kingdom_id.is_empty() and _kingdom_manager != null \
			and _kingdom_manager.are_at_war(player_kingdom_id, target.kingdom_id):
		return PlayerRelation.HOSTILE
	return PlayerRelation.NEUTRAL


## 部队与玩家的阵营关系。有政治家族时以家族关系为准；
## 无家族部队（商队、强盗、治安队）回退到阵营关系。
func get_player_relation_for_party(party_id: String) -> PlayerRelation:
	if party_id.is_empty() or _party_manager == null:
		return PlayerRelation.NEUTRAL
	var party := _party_manager.get_party(party_id)
	if party == null:
		return PlayerRelation.NEUTRAL
	var house_id := get_party_house_id(party_id)
	if not house_id.is_empty():
		return get_player_relation_for_house(house_id)
	match get_relation(PLAYER_FACTION_ID, party.faction_id):
		Relation.FRIENDLY:
			return PlayerRelation.ALLIED
		Relation.HOSTILE:
			return PlayerRelation.HOSTILE
		_:
			return PlayerRelation.NEUTRAL


## 地点与玩家的阵营关系。权威归属只读取 owner_house_id；
## 无家族归属的地点保持中立，不从视觉旗帜或个人身份推导。
func get_player_relation_for_settlement(settlement_id: String) -> PlayerRelation:
	if settlement_id.is_empty() or _settlement_manager == null:
		return PlayerRelation.NEUTRAL
	var settlement := _settlement_manager.get_settlement(settlement_id)
	if settlement == null or settlement.owner_house_id.is_empty():
		return PlayerRelation.NEUTRAL
	return get_player_relation_for_house(settlement.owner_house_id)


## 王国与玩家的阵营关系。玩家未加入王国时，只有主动宣战记录会产生敌对。
func get_player_relation_for_kingdom(kingdom_id: String) -> PlayerRelation:
	if kingdom_id.is_empty():
		return PlayerRelation.NEUTRAL
	var player_house := _get_player_house()
	if player_house == null:
		return PlayerRelation.NEUTRAL
	if not player_house.kingdom_id.is_empty() \
			and kingdom_id == player_house.kingdom_id:
		return PlayerRelation.ALLIED
	if _player_hostile_kingdom_ids.has(kingdom_id):
		return PlayerRelation.HOSTILE
	if player_house.kingdom_id.is_empty():
		return PlayerRelation.NEUTRAL
	if _kingdom_manager != null \
			and _kingdom_manager.are_at_war(player_house.kingdom_id, kingdom_id):
		return PlayerRelation.HOSTILE
	return PlayerRelation.NEUTRAL


## 玩家主动攻击某支部队：按目标家族与其所属王国建立持续敌对关系。
## 无政治家族的部队（强盗/商队等）不产生宣战。
func declare_player_hostility_against_party(party_id: String) -> bool:
	var house_id := get_party_house_id(party_id)
	if house_id.is_empty():
		return false
	return declare_player_hostility_against_house(house_id)


## 玩家主动攻击某个家族：目标家族敌对；若目标属于王国，则该王国及其所有
## 成员家族一同敌对。玩家未加入王国时仍然生效（记录在玩家个人宣战表）。
## 玩家自己的王国不宣战；重复宣战幂等。
func declare_player_hostility_against_house(house_id: String) -> bool:
	if house_id.is_empty() or _house_manager == null:
		return false
	var player_house := _get_player_house()
	var target := _house_manager.get_house(house_id)
	if player_house == null or target == null:
		return false
	if target.is_player_house or target.house_id == player_house.house_id:
		return false
	if not player_house.kingdom_id.is_empty() \
			and target.kingdom_id == player_house.kingdom_id:
		# 不对玩家自己的王国宣战；该家族本身已属同阵营。
		return false

	var changed: bool = false
	if not _player_hostile_house_ids.has(house_id):
		_player_hostile_house_ids.append(house_id)
		changed = true
	if not target.kingdom_id.is_empty():
		if not _player_hostile_kingdom_ids.has(target.kingdom_id):
			_player_hostile_kingdom_ids.append(target.kingdom_id)
			changed = true
		# 玩家已有王国时，同时建立正式的王国战争关系，
		# 让 NPC 对玩家的敌对行为与王国政治保持一致。
		if not player_house.kingdom_id.is_empty() and _kingdom_manager != null:
			_kingdom_manager.declare_war(player_house.kingdom_id, target.kingdom_id)
	if changed:
		EventBus.faction_relations_changed.emit()
	return true


## 清空玩家主动宣战记录（读档/新世界由外部显式调用）。
func clear_player_hostilities() -> void:
	_player_hostile_house_ids.clear()
	_player_hostile_kingdom_ids.clear()


func to_dict() -> Dictionary:
	return {
		"player_hostile_house_ids": _player_hostile_house_ids.duplicate(),
		"player_hostile_kingdom_ids": _player_hostile_kingdom_ids.duplicate(),
	}


## 旧存档没有 factions 字段时保持空表；未知 ID 由关系查询自然忽略。
func load_from_dict(payload: Dictionary) -> void:
	clear_player_hostilities()
	if payload.is_empty():
		return
	_read_id_list(payload.get("player_hostile_house_ids", []), _player_hostile_house_ids)
	_read_id_list(payload.get("player_hostile_kingdom_ids", []), _player_hostile_kingdom_ids)


func get_player_hostile_house_ids() -> Array[String]:
	return _player_hostile_house_ids.duplicate()


func get_player_hostile_kingdom_ids() -> Array[String]:
	return _player_hostile_kingdom_ids.duplicate()


func are_houses_hostile(a: String, b: String) -> bool:
	return get_house_relation(a, b) == Relation.HOSTILE


## 家族当前敌对的所有王国。
## - 属于王国的家族：直接使用王国战争关系（权威且对称）；
## - 独立家族：只有一个王国的任一成员家族与其存在显式敌对关系时才算敌对。
## UI 与百科只调用本接口，不自行解析 enemy_kingdom_ids 或关系表。
func get_hostile_kingdoms_for_house(house_id: String) -> Array[KingdomData]:
	var result: Array[KingdomData] = []
	if _house_manager == null or _kingdom_manager == null:
		return result
	var house := _house_manager.get_house(house_id)
	if house == null:
		return result
	if not house.kingdom_id.is_empty():
		return _kingdom_manager.get_enemy_kingdoms(house.kingdom_id)
	for kingdom: KingdomData in _kingdom_manager.get_all_kingdoms():
		if _is_house_hostile_to_kingdom(house_id, kingdom.kingdom_id):
			result.append(kingdom)
	return result


## 与指定王国敌对的所有独立家族（不属于任何王国）。
## 当前战争关系不会自动把独立家族卷入；只有显式家族关系会产生结果。
func get_hostile_independent_houses_for_kingdom(
	kingdom_id: String
) -> Array[HouseData]:
	var result: Array[HouseData] = []
	if _house_manager == null or _kingdom_manager == null:
		return result
	if _kingdom_manager.get_kingdom(kingdom_id) == null:
		return result
	for candidate: HouseData in _house_manager.get_all_houses():
		if candidate == null or not candidate.kingdom_id.is_empty():
			continue
		if _is_house_hostile_to_kingdom(candidate.house_id, kingdom_id):
			result.append(candidate)
	result.sort_custom(func(a: HouseData, b: HouseData) -> bool:
		return a.house_id < b.house_id
	)
	return result


## 与指定家族敌对的其他独立家族。
## 使用统一家族关系表；同家族/同王国默认友好，玩家家族默认中立。
func get_hostile_independent_houses_for_house(
	house_id: String
) -> Array[HouseData]:
	var result: Array[HouseData] = []
	if _house_manager == null:
		return result
	if _house_manager.get_house(house_id) == null:
		return result
	for candidate: HouseData in _house_manager.get_all_houses():
		if candidate == null or not candidate.kingdom_id.is_empty():
			continue
		if candidate.house_id == house_id:
			continue
		if get_house_relation(house_id, candidate.house_id) == Relation.HOSTILE:
			result.append(candidate)
	result.sort_custom(func(a: HouseData, b: HouseData) -> bool:
		return a.house_id < b.house_id
	)
	return result


## 独立家族是否与某王国敌对：只检查显式家族关系。
func _is_house_hostile_to_kingdom(house_id: String, kingdom_id: String) -> bool:
	if _kingdom_manager == null or house_id.is_empty() or kingdom_id.is_empty():
		return false
	for member: HouseData in _kingdom_manager.get_all_houses_of_kingdom(kingdom_id):
		if member != null and get_house_relation(house_id, member.house_id) == Relation.HOSTILE:
			return true
	return false


## 部队级统一关系查询。拥有有效家族时走家族/王国政治关系，
## 无家族部队（商队、强盗、治安队等）继续使用原有阵营关系。
##
## 强盗与任何政治家族贵族部队一律敌对：不论爵位、家族或王国归属。
## 该规则先于普通政治关系解析，避免没有显式关系的家族骑士被误判为中立。
func get_party_relation(a_party_id: String, b_party_id: String) -> Relation:
	if a_party_id == b_party_id:
		return Relation.FRIENDLY
	if _party_manager == null:
		return Relation.NEUTRAL
	var party_a := _party_manager.get_party(a_party_id)
	var party_b := _party_manager.get_party(b_party_id)
	if party_a == null or party_b == null:
		return Relation.NEUTRAL
	var house_a := get_party_house_id(a_party_id)
	var house_b := get_party_house_id(b_party_id)
	if _is_bandit_party(party_a) and _is_noble_party(party_b, house_b):
		return Relation.HOSTILE
	if _is_bandit_party(party_b) and _is_noble_party(party_a, house_a):
		return Relation.HOSTILE
	if not house_a.is_empty() and not house_b.is_empty():
		return get_house_relation(house_a, house_b)
	return get_relation(party_a.faction_id, party_b.faction_id)


## 强盗身份只读取明确的类型/阵营数据，不通过部队名称猜测。
func _is_bandit_party(party: PartyData) -> bool:
	if party == null:
		return false
	return party.party_kind == PartyData.PartyKind.BANDIT \
		or party.faction_id == BANDIT_FACTION_ID


## 政治家族贵族部队：家族骑士、王国贵族与玩家家族部队都算。
## 有有效政治家族即可；只有部队类型 FAMILY 时也视为贵族部队。
func _is_noble_party(party: PartyData, house_id: String) -> bool:
	if party == null:
		return false
	if not house_id.is_empty():
		return true
	if party.party_kind == PartyData.PartyKind.FAMILY:
		return true
	return not party.family_id.is_empty() and _house_manager != null


func is_party_hostile(a_party_id: String, b_party_id: String) -> bool:
	return get_party_relation(a_party_id, b_party_id) == Relation.HOSTILE


func is_party_friendly(a_party_id: String, b_party_id: String) -> bool:
	return get_party_relation(a_party_id, b_party_id) == Relation.FRIENDLY


func is_party_neutral(a_party_id: String, b_party_id: String) -> bool:
	return get_party_relation(a_party_id, b_party_id) == Relation.NEUTRAL


func get_display_name(faction_id: String) -> String:
	if faction_id.is_empty():
		return "未知"
	return str(_display_names.get(faction_id, faction_id))


func relation_text(relation: Relation) -> String:
	match relation:
		Relation.FRIENDLY:
			return "友好"
		Relation.HOSTILE:
			return "敌对"
		_:
			return "中立"


## 玩家家族。优先使用 is_player_house 标记，避免依赖外部传入的玩家 ID。
func _get_player_house() -> HouseData:
	if _house_manager == null:
		return null
	return _house_manager.get_player_house()


func _player_relation_to_relation(relation: PlayerRelation) -> Relation:
	match relation:
		PlayerRelation.ALLIED:
			return Relation.FRIENDLY
		PlayerRelation.HOSTILE:
			return Relation.HOSTILE
		_:
			return Relation.NEUTRAL


## 把存档中的 ID 数组读入目标数组；重复与空值忽略。
func _read_id_list(values: Variant, target: Array[String]) -> void:
	if not values is Array:
		return
	for value: Variant in values:
		var id: String = str(value)
		if id.is_empty() or target.has(id):
			continue
		target.append(id)


func _relation_key(a: String, b: String) -> String:
	if a <= b:
		return "%s|%s" % [a, b]
	return "%s|%s" % [b, a]
