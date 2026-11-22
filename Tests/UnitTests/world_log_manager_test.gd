extends Node
## 世界日志数据层测试：事件类型、战斗/遭遇/地点文本、数量上限与序列化预留。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/world_log_manager_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"

var _failed: bool = false
var _ids: IdGenerator = null
var _units: UnitManager = null
var _parties: PartyManager = null
var _settlements: SettlementManager = null
var _factions: FactionManager = null
var _battle: BattleManager = null
var _log: WorldLogManager = null


func _ready() -> void:
	_run()
	_cleanup()
	if _failed:
		push_error("[worldlog] 测试失败")
		get_tree().quit(1)
	else:
		print("[worldlog] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	var militia := load(MILITIA_PATH) as UnitConfig
	_check(militia != null, "加载民兵配置")
	if militia == null:
		return

	_setup_fixture()
	var player := _make_party(
		FactionManager.PLAYER_FACTION_ID, militia, 2, "玩家部队"
	)
	var merchant := _make_party(
		FactionManager.MERCHANT_FACTION_ID, militia, 2, "测试商队"
	)
	var bandit := _make_party(
		FactionManager.BANDIT_FACTION_ID, militia, 2, "测试强盗"
	)
	_battle.player_party_id = player.party_id

	var session := _battle.start_battle(
		[merchant.party_id], [bandit.party_id], Vector2(1000.0, 1000.0), true
	)
	_check(session != null, "创建测试战斗")
	if session == null:
		return

	var entries := _log.get_entries()
	_check(entries.size() == 1, "战斗开始生成一条日志")
	if not entries.is_empty():
		_check(
			entries[0].event_type == WorldLogEntry.EventType.BATTLE_STARTED,
			"日志记录战斗开始事件类型"
		)
		_check(
			entries[0].text.contains("测试商队")
			and entries[0].text.contains("测试强盗")
			and entries[0].text.contains("发生了战斗"),
			"战斗开始日志包含双方名称"
		)
		_check(not entries[0].time_text.is_empty(), "日志记录世界时间文本")

	for unit_id: String in session.get_side_unit_ids(1):
		var state := session.get_unit_state(unit_id)
		state.battle_hp = 0
		state.alive = false
	_check(
		_battle.finish_battle(
			session.battle_id, BattleSession.BattleResult.ATTACKER_VICTORY
		),
		"结算测试战斗"
	)
	var text := _all_text()
	_check(text.contains("测试商队 击败了 测试强盗"), "生成战斗胜负日志")
	_check(text.contains("测试强盗 已被消灭"), "生成部队被消灭日志")
	_check(_log.get_entry_count() >= 3, "战斗结束追加胜负与被消灭日志")

	EventBus.player_encounter_requested.emit(
		"TEST_ENCOUNTER", bandit.party_id, player.party_id
	)
	_check(_all_text().contains("玩家部队 与 测试强盗 发生了遭遇"), "生成玩家遭遇日志")

	var village := _settlements.create_settlement(
		"测试村", SettlementData.SettlementType.VILLAGE, Vector2(500.0, 500.0)
	)
	EventBus.settlement_entered.emit(village.settlement_id, player.party_id)
	EventBus.settlement_exited.emit(village.settlement_id, player.party_id)
	text = _all_text()
	_check(text.contains("玩家进入了测试村"), "生成进入村庄日志")
	_check(text.contains("玩家离开了测试村"), "生成离开村庄日志")

	var custom := _log.add_event(
		WorldLogEntry.EventType.OTHER, "预留世界事件", {"test": true}
	)
	_check(custom != null and custom.text == "预留世界事件", "支持其他重要事件扩展接口")
	_check(custom.metadata.get("test", false), "扩展事件可携带元数据")

	var serialized := _log.to_dict()
	var restored := WorldLogManager.new()
	restored.load_from_dict(serialized)
	_check(
		restored.get_entry_count() == _log.get_entry_count(),
		"日志序列化后条目数量一致"
	)
	_check(
		restored.get_entries().back().text == custom.text,
		"日志序列化保留最新条目"
	)

	_log.clear()
	for i: int in range(WorldLogManager.MAX_ENTRIES + 20):
		_log.add_event(WorldLogEntry.EventType.OTHER, "上限事件 %d" % i)
	_check(_log.get_entry_count() == WorldLogManager.MAX_ENTRIES, "日志数量受上限约束")
	_check(
		_log.get_entries()[0].text == "上限事件 20",
		"超出上限时移除最早日志"
	)
	_check(
		_log.get_entries().back().text
			== "上限事件 %d" % (WorldLogManager.MAX_ENTRIES + 19),
		"最新日志仍在末尾"
	)
	_check(WorldLogManager.MAX_ENTRIES == 20, "世界日志上限固定为 20 条")
	var serialized_cap: Dictionary = _log.to_dict()
	_check(
		(serialized_cap.get("entries", []) as Array).size() <= 20,
		"保存时最多只写入 20 条日志"
	)

	# 历史存档可能包含超过 20 条：读档时必须立刻清理旧记录。
	var oversized: Dictionary = {"entries": []}
	for i: int in range(100):
		var entry := WorldLogEntry.new()
		entry.text = "历史日志 %d" % i
		entry.world_time_seconds = float(i)
		(oversized["entries"] as Array).append(entry.to_dict())
	_log.load_from_dict(oversized)
	_check(_log.get_entry_count() == 20, "读档后只保留最新 20 条")
	_check(_log.get_entries()[0].text == "历史日志 80", "读档清理最早的历史日志")
	_check(_log.get_entries().back().text == "历史日志 99", "读档保留最新历史日志")

	var trade_entry := _log.add_event(
		WorldLogEntry.EventType.PLAYER_TRADE, "玩家交易日志"
	)
	_check(trade_entry != null, "PLAYER_TRADE 事件可以写入")
	_check(_log.get_entry_count() == 20, "新增交易日志后仍保持 20 条上限")
	var trade_serialized := _log.to_dict()
	var trade_restored := WorldLogManager.new()
	trade_restored.load_from_dict(trade_serialized)
	_check(
		trade_restored.get_entries().back().event_type
			== WorldLogEntry.EventType.PLAYER_TRADE,
		"PLAYER_TRADE 事件类型可以序列化恢复"
	)
	_check(
		trade_restored.get_entries().back().text == "玩家交易日志",
		"交易日志文本可以序列化恢复"
	)


func _setup_fixture() -> void:
	_ids = IdGenerator.new()
	_units = UnitManager.new()
	_units.setup(_ids)
	_parties = PartyManager.new()
	_parties.setup(_units, _ids)
	_settlements = SettlementManager.new()
	_settlements.setup(_ids)
	_factions = FactionManager.new()
	_factions.setup_defaults()
	_battle = BattleManager.new()
	_battle.setup(_units, _parties, _ids, _factions)
	_log = WorldLogManager.new()
	_log.setup(_battle, _parties, _settlements)


func _make_party(
	faction_id: String, config: UnitConfig, count: int, party_name: String
) -> PartyData:
	var party := _parties.create_party(faction_id, Vector2(1000.0, 1000.0), party_name)
	for i: int in range(count):
		var unit := _units.create_unit(config, faction_id)
		_parties.add_member(party.party_id, unit.unit_id)
	return party


func _all_text() -> String:
	var lines: Array[String] = []
	for entry: WorldLogEntry in _log.get_entries():
		lines.append(entry.text)
	return "\n".join(lines)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[worldlog] OK: %s" % message)
	else:
		_failed = true
		push_error("[worldlog] FAIL: %s" % message)


func _cleanup() -> void:
	if _battle != null and _battle.current_battle != null:
		_battle.finish_battle(
			_battle.current_battle.battle_id, BattleSession.BattleResult.ABORTED
		)
	if _log != null:
		_log.dispose()
	TimeManager.stop_session()
	TimeManager.clear_pauses()
