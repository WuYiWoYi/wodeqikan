class_name EventCenter
extends RefCounted
## 主界面事件中心的数据接入层。
##
## 只聚合现有系统的待处理状态，不生成任务、不写权威数据、不保存独立事件副本。
## 事件 ID 由“类型 + 来源 ID”确定性生成，因此反复打开界面不会重复创建事件。
## 当前项目尚无任务系统：QUEST 类型保留统一入口，读取结果为空，
## 后续任务系统接入时只需在此处补充读取，不改变 UI 契约。

const TYPE_QUEST: String = "QUEST"
const TYPE_FIEF: String = "FIEF"
const TYPE_SUPPLY: String = "SUPPLY"
const TYPE_WOUNDED: String = "WOUNDED"
const TYPE_ADVENTURER: String = "ADVENTURER"
## 可由玩家直接处理的赎回请求；由 LordRansomManager 的当前状态推导。
const TYPE_RANSOM: String = "RANSOM"

const TYPE_TEXT: Dictionary = {
	TYPE_QUEST: "任务",
	TYPE_FIEF: "封地",
	TYPE_SUPPLY: "补给",
	TYPE_WOUNDED: "伤兵",
	TYPE_ADVENTURER: "冒险者",
	TYPE_RANSOM: "赎回",
}

## 只读访问 WorldContext；不声明具体类型以避免 WorldContext ↔ EventCenter 循环引用。
var _context = null


func setup(context) -> void:
	_context = context


## 返回当前全部事件。数组每次重新构建，调用方不得缓存为权威数据。
func get_events() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if _context == null:
		return events
	events.append_array(_collect_quest_events())
	events.append_array(_collect_fief_events())
	events.append_array(_collect_supply_events())
	events.append_array(_collect_wounded_events())
	events.append_array(_collect_adventurer_events())
	events.append_array(_collect_ransom_events())
	return events


## 右侧事件框只展示玩家可直接操作的事件；普通提示仍留在事件中心。
func get_actionable_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in get_events():
		if bool(event.get("actionable", false)):
			result.append(event)
	return result


func get_event(event_id: String) -> Dictionary:
	for event: Dictionary in get_events():
		if str(event.get("event_id", "")) == event_id:
			return event
	return {}


func get_events_of_type(type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in get_events():
		if str(event.get("type", "")) == type:
			result.append(event)
	return result


func get_type_text(type: String) -> String:
	return str(TYPE_TEXT.get(type, "事件"))


## 当前没有任务系统；保留统一查询入口，避免 UI 直接依赖某个未来实现。
func _collect_quest_events() -> Array[Dictionary]:
	var empty: Array[Dictionary] = []
	return empty


## 玩家拥有的村庄中，仍有可征召采邑的村庄。
func _collect_fief_events() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var lord: NobleData = _context.get_player_lord()
	var manager: FiefRecruitmentManager = _context.fief_recruitment_manager
	if lord == null or manager == null:
		return events
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement == null \
				or settlement.settlement_type != SettlementData.SettlementType.VILLAGE:
			continue
		if settlement.fief_recruitment_stock <= 0:
			continue
		if not manager.is_authorized_owner(settlement, lord.lord_id):
			continue
		events.append({
			"event_id": "fief:%s" % settlement.settlement_id,
			"type": TYPE_FIEF,
			"type_text": get_type_text(TYPE_FIEF),
			"title": "可征召采邑：%s" % settlement.display_name,
			"detail": (
				"村庄：%s\n可征召：%d 组（每组 6 人，容量 %d 组）\n"
				+ "人口：%d · 繁荣度：%d\n前往该村庄打开地点面板即可征召。"
			) % [
				settlement.display_name,
				settlement.fief_recruitment_stock,
				settlement.fief_recruitment_capacity,
				settlement.population,
				settlement.prosperity,
			],
		})
	return events


## 玩家部队补给不足时产生一条事件；普通状态不占用事件列表。
func _collect_supply_events() -> Array[Dictionary]:
	var party: PartyData = _context.get_player_party()
	if party == null or _context.supply_manager == null:
		var empty: Array[Dictionary] = []
		return empty
	var status: Dictionary = _context.supply_manager.get_status(party)
	var low: bool = bool(status.get("is_food_low", false)) \
		or bool(status.get("is_fodder_low", false)) \
		or int(status.get("bread_shortage", 0)) > 0 \
		or int(status.get("fodder_shortage", 0)) > 0
	if not low:
		var empty: Array[Dictionary] = []
		return empty
	var daily_fodder: int = int(status.get("daily_fodder_consumption", 0))
	var fodder_days: String = "无需草料" if daily_fodder <= 0 else "%.1f 天" % float(
		status.get("fodder_days_remaining", 0.0)
	)
	return [{
		"event_id": "supply:player",
		"type": TYPE_SUPPLY,
		"type_text": get_type_text(TYPE_SUPPLY),
		"title": "补给不足",
		"detail": (
			"面包：%d（约 %.1f 天）\n草料：%d（约 %s）\n"
			+ "每日消耗：面包 %d / 草料 %d\n请前往村庄或城镇市场购买补给。"
		) % [
			int(status.get("bread_count", 0)),
			float(status.get("food_days_remaining", 0.0)),
			int(status.get("fodder_count", 0)),
			fodder_days,
			int(status.get("daily_bread_consumption", 0)),
			daily_fodder,
		],
	}]


func _collect_wounded_events() -> Array[Dictionary]:
	var party: PartyData = _context.get_player_party()
	if party == null or _context.unit_manager == null:
		var empty: Array[Dictionary] = []
		return empty
	var wounded_count: int = 0
	for unit_id: String in party.member_unit_ids:
		var unit: UnitData = _context.unit_manager.get_unit(unit_id)
		if unit != null and unit.is_wounded():
			wounded_count += 1
	if wounded_count <= 0:
		var empty: Array[Dictionary] = []
		return empty
	var healing: int = 0
	if _context.wounded_healing_manager != null:
		healing = _context.wounded_healing_manager.get_healing_per_hour()
	return [{
		"event_id": "wounded:player",
		"type": TYPE_WOUNDED,
		"type_text": get_type_text(TYPE_WOUNDED),
		"title": "伤兵正在恢复（%d）" % wounded_count,
		"detail": (
			"当前有 %d 名士兵负伤。\n每小时恢复 %d 点生命，"
			+ "按部队成员顺序依次治疗。\n保持世界时间运行即可继续恢复。"
		) % [wounded_count, healing],
	}]


## 家族赎回事件：只聚合 LordRansomManager 中当前仍有效、可操作的请求。
## 已接受/已失效的记录在管理器侧立即失效，本方法不会返回旧副本。
func _collect_ransom_events() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if _context == null or _context.lord_ransom_manager == null:
		return events
	for raw: Dictionary in _context.lord_ransom_manager.get_active_events():
		var event: Dictionary = raw.duplicate(true)
		event["type"] = TYPE_RANSOM
		event["type_text"] = get_type_text(TYPE_RANSOM)
		events.append(event)
	return events


## 每个仍有可用候选人的村庄产生一条事件，避免为同一候选人重复生成条目。
func _collect_adventurer_events() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement == null \
				or settlement.settlement_type != SettlementData.SettlementType.VILLAGE:
			continue
		var candidates: Array[AdventurerCandidateData] = (
			settlement.get_available_candidates()
		)
		if candidates.is_empty():
			continue
		var names: Array[String] = []
		for candidate: AdventurerCandidateData in candidates:
			if candidate != null and not candidate.display_name.is_empty():
				names.append(candidate.display_name)
		var name_text: String = "、".join(PackedStringArray(names)) if not names.is_empty() \
			else "未知候选人"
		events.append({
			"event_id": "adventurer:%s" % settlement.settlement_id,
			"type": TYPE_ADVENTURER,
			"type_text": get_type_text(TYPE_ADVENTURER),
			"title": "可招募冒险者：%s（%d）" % [
				settlement.display_name, candidates.size()
			],
			"detail": (
				"村庄：%s\n候选人：%s\n可进入村庄与冒险者交谈并支付金币招募。"
			) % [settlement.display_name, name_text],
		})
	return events
