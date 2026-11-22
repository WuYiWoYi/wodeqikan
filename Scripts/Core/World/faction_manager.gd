class_name FactionManager
extends RefCounted
## 阵营注册与关系查询的唯一入口。
##
## 关系是静态规则，不进入存档；新游戏与读档都会重新建立默认关系。
## AI 只能通过本类判断敌对/友好，不允许各自硬编码阵营列表。

enum Relation {
	FRIENDLY,
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

## 政治关系查询所需的只读引用；不保存数据副本。
var _party_manager: PartyManager = null
var _noble_manager: NobleManager = null
var _house_manager: HouseManager = null
var _kingdom_manager: KingdomManager = null


## `party_manager` 只用于部队级关系查询（政治身份回退）。
## 生产环境由 `setup_political()` 注入完整政治实体；独立测试可只传部队仓储。
func setup_defaults(party_manager: PartyManager = null) -> void:
	_display_names.clear()
	_relations.clear()
	_house_relations.clear()
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
	kingdom_manager: KingdomManager
) -> void:
	_party_manager = party_manager
	_noble_manager = noble_manager
	_house_manager = house_manager
	_kingdom_manager = kingdom_manager


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
## - 玩家家族与任何王国默认中立，不自动卷入战争；
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
	if house_a.is_player_house or house_b.is_player_house:
		return Relation.NEUTRAL
	if not house_a.kingdom_id.is_empty() and house_a.kingdom_id == house_b.kingdom_id:
		return Relation.FRIENDLY
	if not house_a.kingdom_id.is_empty() and not house_b.kingdom_id.is_empty():
		if _kingdom_manager != null \
				and _kingdom_manager.are_at_war(house_a.kingdom_id, house_b.kingdom_id):
			return Relation.HOSTILE
		return Relation.NEUTRAL
	return Relation.NEUTRAL


func are_houses_hostile(a: String, b: String) -> bool:
	return get_house_relation(a, b) == Relation.HOSTILE


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


func _relation_key(a: String, b: String) -> String:
	if a <= b:
		return "%s|%s" % [a, b]
	return "%s|%s" % [b, a]
