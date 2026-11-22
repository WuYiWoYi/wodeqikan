class_name NobleData
extends LordData
## 贵族的持久化运行时数据。
##
## 贵族是家族体系中的个人身份：拥有爵位、所属家族、上级贵族与独立部队。
## 继承 LordData 以保持旧存档、封地所有权与 AI 战略字段兼容：
## - lord_id 仍是持久化主键；noble_id 是同一字段的语义别名；
## - is_player_lord 表示玩家贵族身份；is_player 是语义别名；
## - 爵位与国王身份分开：is_king 不是第四个普通爵位。
##
## 本阶段只建立关系与查询接口，不实现爵位晋升、授封和完整继承。

## 三级爵位；数值只表示等级高低，不包含国王。
enum Rank {
	KNIGHT = 1,
	BARON = 2,
	DUKE = 3,
}

## HouseData.house_id；空字符串表示无家族（通常只用于旧存档兜底）。
var house_id: String = ""
var rank: Rank = Rank.KNIGHT
## 直接上级贵族 ID；空字符串表示没有上级。
var liege_noble_id: String = ""
var is_house_leader: bool = false
## 当前是否拥有王国统治者身份。必须由 KingdomManager 维护。
var is_king: bool = false


## noble_id 与 lord_id 指向同一持久化主键，避免新旧字段长期并存。
var noble_id: String:
	get:
		return lord_id
	set(value):
		lord_id = value


## alive 与 is_alive 指向同一状态。
var alive: bool:
	get:
		return is_alive
	set(value):
		is_alive = value


var is_player: bool:
	get:
		return is_player_lord
	set(value):
		is_player_lord = value


func get_rank() -> Rank:
	return rank


static func rank_text(value: Rank) -> String:
	match value:
		Rank.DUKE:
			return "公爵"
		Rank.BARON:
			return "男爵"
		_:
			return "骑士"


func get_rank_text() -> String:
	return rank_text(rank)


func has_house() -> bool:
	return not house_id.strip_edges().is_empty()


func has_liege() -> bool:
	return not liege_noble_id.strip_edges().is_empty()


func to_dict() -> Dictionary:
	var payload: Dictionary = super.to_dict()
	payload["noble_id"] = lord_id
	payload["house_id"] = house_id
	payload["rank"] = int(rank)
	payload["liege_noble_id"] = liege_noble_id
	payload["is_house_leader"] = is_house_leader
	payload["is_king"] = is_king
	payload["alive"] = is_alive
	payload["is_player"] = is_player_lord
	return payload


static func from_dict(data: Dictionary) -> NobleData:
	var noble := NobleData.new()
	noble.lord_id = str(data.get("noble_id", data.get("lord_id", "")))
	noble.display_name = str(data.get("display_name", ""))
	noble.faction_id = str(data.get("faction_id", ""))
	noble.party_id = str(data.get("party_id", ""))
	noble.is_player_lord = bool(
		data.get("is_player", data.get("is_player_lord", false))
	)
	noble.personality_id = str(data.get("personality_id", ""))
	noble.current_goal = str(data.get("current_goal", ""))
	noble.current_state = str(data.get("current_state", ""))
	noble.current_target_settlement_id = str(
		data.get("current_target_settlement_id", "")
	)
	noble.is_alive = bool(data.get("alive", data.get("is_alive", true)))
	noble.house_id = str(data.get("house_id", ""))
	noble.liege_noble_id = str(data.get("liege_noble_id", ""))
	noble.is_house_leader = bool(data.get("is_house_leader", false))
	noble.is_king = bool(data.get("is_king", false))

	var rank_value: int = int(data.get("rank", int(Rank.KNIGHT)))
	if rank_value < int(Rank.KNIGHT) or rank_value > int(Rank.DUKE):
		rank_value = int(Rank.KNIGHT)
	noble.rank = rank_value as Rank

	var relationships_value: Variant = data.get("relationships", {})
	if relationships_value is Dictionary:
		noble.relationships = (relationships_value as Dictionary).duplicate(true)
	return noble
