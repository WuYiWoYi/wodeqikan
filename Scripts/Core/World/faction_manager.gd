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


func setup_defaults() -> void:
	_display_names.clear()
	_relations.clear()

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
