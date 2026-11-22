extends Node
## 阶段 12 NPC 补给采购 AI 测试：
## - 补给不足时选择最近的村庄/城镇市场，城堡永远不是候选；
## - 使用部队自有金币与 MarketManager 统一交易，最多补到 7 天储备；
## - 采购成功只广播一次事件，不写玩家世界日志；
## - 战斗中的部队不触发补给采购。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/ai_supply_purchase_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"
const BREAD_PATH: String = "res://Data/Items/bread.tres"
const FODDER_PATH: String = "res://Data/Items/fodder.tres"
const BREAD_GOODS_PATH: String = "res://Data/Market/bread_goods.tres"
const FODDER_GOODS_PATH: String = "res://Data/Market/fodder_goods.tres"

var _failed: bool = false
var _units: UnitManager = null
var _parties: PartyManager = null
var _settlements: SettlementManager = null
var _items: ItemManager = null
var _log: WorldLogManager = null
var _market: MarketManager = null
var _supply: SupplyManager = null
var _map: WorldMapManager = null
var _ai: AIManager = null
var _profile: PlayerProfile = null
var _village: SettlementData = null
var _town: SettlementData = null
var _castle: SettlementData = null
var _party: PartyData = null
var _purchase_events: int = 0
var _last_bread: int = 0


func _ready() -> void:
	_run()
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	if _failed:
		push_error("[ai-supply] 测试失败")
		get_tree().quit(1)
	else:
		print("[ai-supply] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.restore_world_time(0.0, TimeManager.SPEED_NORMAL)
	if not _setup_fixture():
		return
	EventBus.npc_supply_purchased.connect(_on_npc_supply_purchased)
	_test_chooses_market_not_castle()
	_test_purchase_uses_party_gold_and_stock()
	_test_battle_blocks_supply_purchase()
	_test_town_fallback()
	EventBus.npc_supply_purchased.disconnect(_on_npc_supply_purchased)


func _setup_fixture() -> bool:
	var ids := IdGenerator.new()
	_units = UnitManager.new()
	_units.setup(ids)
	_parties = PartyManager.new()
	_parties.setup(_units, ids)
	_settlements = SettlementManager.new()
	_settlements.setup(ids)
	_items = ItemManager.new()
	_log = WorldLogManager.new()
	_market = MarketManager.new()
	_market.setup(_settlements, _units, _items, _log)
	_supply = SupplyManager.new()
	_profile = PlayerProfile.new()
	_map = WorldMapManager.new()
	_map.setup(_parties)
	_map.world_bounds = Rect2(Vector2.ZERO, Vector2(1000.0, 1000.0))
	_ai = AIManager.new()

	var militia := load(MILITIA_PATH) as UnitConfig
	if militia == null:
		_check(false, "加载兵种配置")
		return false
	for path: String in [BREAD_PATH, FODDER_PATH]:
		var item := load(path) as ItemConfig
		if item == null or not _items.register_item_config(item):
			_check(false, "注册补给物品配置: %s" % path)
			return false
	for path: String in [BREAD_GOODS_PATH, FODDER_GOODS_PATH]:
		var goods := load(path) as MarketGoodsConfig
		if goods == null or not _market.register_goods_config(goods):
			_check(false, "注册市场补给商品: %s" % path)
			return false

	_village = _settlements.create_settlement(
		"测试村庄", SettlementData.SettlementType.VILLAGE, Vector2(100.0, 100.0)
	)
	_town = _settlements.create_settlement(
		"测试城镇", SettlementData.SettlementType.TOWN, Vector2(500.0, 100.0)
	)
	# 城堡更近，但没有市场，不能被选为补给目标。
	_castle = _settlements.create_settlement(
		"测试城堡", SettlementData.SettlementType.CASTLE, Vector2(92.0, 100.0)
	)
	if _village == null or _town == null or _castle == null:
		_check(false, "创建村庄/城镇/城堡")
		return false
	_check(_market.ensure_markets(), "初始化村庄与城镇市场")

	_party = _parties.create_party(
		"FACTION_LOCAL", Vector2(90.0, 100.0), "补给测试部队",
		PartyData.PartyKind.GENERIC
	)
	if _party == null:
		_check(false, "创建 NPC 部队")
		return false
	for i: int in range(2):
		var unit := _units.create_unit(militia, "FACTION_LOCAL")
		if unit == null or not _parties.add_member(_party.party_id, unit.unit_id):
			_check(false, "创建并加入 NPC 士兵")
			return false
	_party.gold = 100
	_supply.setup(_parties, _units, _profile, "")
	_ai.setup(
		_units,
		_parties,
		_map,
		_settlements,
		null,
		null,
		null,
		null,
		null,
		null,
		_supply,
		_market
	)
	return true


func _test_chooses_market_not_castle() -> void:
	_ai.tick(AIManager.PARTY_DECISION_INTERVAL)
	_check(_party.supply_purchase_active, "补给不足时启动采购任务")
	_check(
		_party.target_position.is_equal_approx(_village.world_position),
		"选择最近的村庄市场，而不是更近的城堡"
	)
	_check(
		_party.supply_purchase_settlement_id == _village.settlement_id,
		"采购目标记录为村庄市场"
	)
	_check(_party.gold == 100, "前往市场途中不扣款")


func _test_purchase_uses_party_gold_and_stock() -> void:
	var log_before: int = _log.get_entry_count()
	var stock_before: int = _market.get_stock(_village.settlement_id, "bread")
	_party.world_position = _village.world_position
	_party.target_position = _village.world_position
	_party.movement_state = PartyData.MovementState.IDLE
	_ai.tick(AIManager.PARTY_DECISION_INTERVAL)

	_check(_party.get_item_count("bread") == 14, "NPC 按 7 天储备购买 14 份面包")
	_check(_party.gold == 72, "采购从 NPC 自有金币扣除")
	_check(
		_market.get_stock(_village.settlement_id, "bread") == stock_before - 14,
		"采购减少村庄市场库存"
	)
	_check(not _party.supply_purchase_active, "采购完成后结束采购任务")
	_check(_purchase_events == 1 and _last_bread == 14, "只广播一次补给采购事件")
	_check(_log.get_entry_count() == log_before, "NPC 采购不写玩家世界日志")


func _test_battle_blocks_supply_purchase() -> void:
	_party.remove_item("bread", _party.get_item_count("bread"))
	_party.supply_purchase_retry_after = 0.0
	_party.battle_state = PartyData.BattleState.IN_BATTLE
	_party.supply_purchase_active = false
	_party.supply_purchase_settlement_id = ""
	_party.target_position = Vector2.ZERO
	_ai.tick(AIManager.PARTY_DECISION_INTERVAL)
	_check(not _party.supply_purchase_active, "战斗中的部队不启动补给采购")
	_check(_party.target_position == Vector2.ZERO, "战斗中的部队移动目标不被补给覆盖")
	_party.battle_state = PartyData.BattleState.AVAILABLE
	_party.supply_purchase_retry_after = 0.0


func _test_town_fallback() -> void:
	# 村庄补给卖光后，AI 应改选更远的城镇。
	_market.set_stock(_village.settlement_id, "bread", 0)
	_party.remove_item("bread", _party.get_item_count("bread"))
	_party.supply_purchase_active = false
	_party.supply_purchase_settlement_id = ""
	_party.supply_purchase_retry_after = 0.0
	_party.world_position = Vector2(90.0, 100.0)
	_ai.tick(AIManager.PARTY_DECISION_INTERVAL)
	_check(
		_party.supply_purchase_settlement_id == _town.settlement_id,
		"村庄没有库存时改选城镇市场"
	)
	_party.world_position = _town.world_position
	_party.target_position = _town.world_position
	_party.movement_state = PartyData.MovementState.IDLE
	_ai.tick(AIManager.PARTY_DECISION_INTERVAL)
	_check(_party.get_item_count("bread") > 0, "在城镇市场完成补给采购")
	_check(_purchase_events == 2, "第二次采购再广播一次事件")


func _on_npc_supply_purchased(
	_party_id: String, bread_count: int, _fodder_count: int
) -> void:
	_purchase_events += 1
	_last_bread = bread_count


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[ai-supply] OK: %s" % message)
	else:
		_failed = true
		push_error("[ai-supply] FAIL: %s" % message)
