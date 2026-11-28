extends Node
## 阶段 11 市场数据层测试：商品注册、城镇库存、买卖与混合交易、
## 交易失败不修改数据、重复提交防护、NPC 来源不写世界日志与序列化。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/UnitTests/market_manager_test.tscn

const HORSE_PATH: String = "res://Data/Equipment/mount_horse_01.tres"
const SWORD_PATH: String = "res://Data/Equipment/weapon_sword_01.tres"
const TOKEN_PATH: String = "res://Data/Items/promotion_rank_token.tres"
const BREAD_PATH: String = "res://Data/Items/bread.tres"
const FODDER_PATH: String = "res://Data/Items/fodder.tres"
const HORSE_ID: String = "mount_horse_01"
const SWORD_ID: String = "weapon_sword_01"
const TOKEN_ID: String = "promotion_rank_token"
const BREAD_ID: String = "bread"
const FODDER_ID: String = "fodder"

var _failed: bool = false
var _ids: IdGenerator = null
var _units: UnitManager = null
var _items: ItemManager = null
var _settlements: SettlementManager = null
var _log: WorldLogManager = null
var _markets: MarketManager = null
var _profile: PlayerProfile = null
var _town: SettlementData = null
var _village: SettlementData = null
var _castle: SettlementData = null


func _ready() -> void:
	_run()
	if _failed:
		push_error("[market] 测试失败")
		get_tree().quit(1)
	else:
		print("[market] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	if not _setup_fixture():
		_finish()
		return

	_check(_markets.get_stock(_town.settlement_id, HORSE_ID) == 3, "新城镇初始化 3 匹战马")
	_check(_markets.get_market(_village.settlement_id) != null, "村庄拥有补给市场")
	# 村庄初始库存 = 动态上限 × 初始比例 50%：
	# 面包上限 200(特产位) + 100(保底) = 300 → 150；草料 100 + 50 = 150 → 75。
	_check(_markets.get_stock(_village.settlement_id, BREAD_ID) == 150, "村庄初始化面包库存")
	_check(_markets.get_stock(_village.settlement_id, FODDER_ID) == 75, "村庄初始化草料库存")
	_check(_markets.get_stock(_village.settlement_id, HORSE_ID) == 0, "村庄不卖城镇限定马匹")
	_check(_markets.get_market(_castle.settlement_id) == null, "城堡没有市场")
	_check(_markets.get_stock(_town.settlement_id, TOKEN_ID) == 5, "初始化普通物品库存")

	_test_purchase()
	_test_village_supply_trade()
	_test_sale()
	_test_mixed_trade()
	_test_failures_keep_data()
	_test_non_tradeable_and_no_sell_price()
	_test_duplicate_submit()
	_test_npc_trade_does_not_log()
	_test_serialization_and_old_save_fill()

	_finish()


func _test_purchase() -> void:
	_profile.gold = 1000
	var result := _markets.execute_player_trade(
		_town.settlement_id, {HORSE_ID: 1}, {}, _profile, "buy-1"
	)
	_check(bool(result.get("success", false)), "购买普通战马成功")
	_check(_profile.get_item_count(HORSE_ID) == 1, "购买后玩家获得 1 匹战马")
	_check(_markets.get_stock(_town.settlement_id, HORSE_ID) == 2, "购买后市场库存减少 1")
	_check(_profile.gold == 900, "购买支付 100 金币")
	_check(int(result.get("gold_paid", 0)) == 100, "结果记录实际支付")
	_check(_log.get_entry_count() == 1, "玩家购买写入一条世界日志")
	_check(
		_log.get_entries().back().text.contains("购买了普通战马 ×1")
			and _log.get_entries().back().text.contains("支付 100 金币"),
		"购买日志文本包含物品与金币"
	)
	_check(
		_log.get_entries().back().event_type == WorldLogEntry.EventType.PLAYER_TRADE,
		"交易日志使用 PLAYER_TRADE 类型"
	)
	var metadata: Dictionary = _log.get_entries().back().metadata
	_check(metadata.get("settlement_id", "") == _town.settlement_id, "日志保存城镇 ID")
	_check(metadata.get("gold_paid", 0) == 100, "日志保存实际支付金币")
	_check(metadata.get("net_gold", 0) == 100, "日志保存净交易金额")


## 村庄只提供面包/草料；交易仍走同一个 MarketManager 与同一份库存。
func _test_village_supply_trade() -> void:
	_profile.gold = 1000
	var log_before: int = _log.get_entry_count()
	var result := _markets.execute_player_trade(
		_village.settlement_id,
		{BREAD_ID: 10, FODDER_ID: 10},
		{},
		_profile,
		"village-supply-1"
	)
	_check(bool(result.get("success", false)), "村庄可以购买面包与草料")
	_check(_profile.get_item_count(BREAD_ID) == 10, "购买后获得面包")
	_check(_profile.get_item_count(FODDER_ID) == 10, "购买后获得草料")
	_check(_markets.get_stock(_village.settlement_id, BREAD_ID) == 140, "村庄面包库存减少")
	_check(_markets.get_stock(_village.settlement_id, FODDER_ID) == 65, "村庄草料库存减少")
	_check(_profile.gold == 1000.0 - 3.0 - 5.0, "村庄补给按动态单价结算")
	_check(_log.get_entry_count() == log_before + 1, "村庄玩家交易写入世界日志")

	result = _markets.execute_player_trade(
		_village.settlement_id, {}, {BREAD_ID: 4}, _profile, "village-sell-1"
	)
	_check(bool(result.get("success", false)), "村庄可以收购面包")
	_check(_profile.get_item_count(BREAD_ID) == 6, "出售后玩家面包减少")
	_check(_markets.get_stock(_village.settlement_id, BREAD_ID) == 144, "出售后村庄库存恢复")


func _test_sale() -> void:
	var gold_before: int = _profile.gold
	var log_before: int = _log.get_entry_count()
	var result := _markets.execute_player_trade(
		_town.settlement_id, {}, {HORSE_ID: 1}, _profile, "sell-1"
	)
	_check(bool(result.get("success", false)), "出售普通战马成功")
	_check(_profile.get_item_count(HORSE_ID) == 0, "出售后玩家战马归零")
	_check(_markets.get_stock(_town.settlement_id, HORSE_ID) == 3, "出售后市场库存恢复 1")
	_check(_profile.gold == gold_before + 70, "出售获得 70 金币")
	_check(int(result.get("gold_received", 0)) == 70, "结果记录实际获得")
	_check(_log.get_entry_count() == log_before + 1, "玩家出售写入一条世界日志")
	_check(
		_log.get_entries().back().text.contains("出售了普通战马 ×1")
			and _log.get_entries().back().text.contains("获得 70 金币"),
		"出售日志文本包含物品与金币"
	)


func _test_mixed_trade() -> void:
	_profile.add_item(HORSE_ID, 1)
	var gold_before: int = _profile.gold
	var log_before: int = _log.get_entry_count()
	var result := _markets.execute_player_trade(
		_town.settlement_id,
		{HORSE_ID: 2},
		{HORSE_ID: 1},
		_profile,
		"mixed-1"
	)
	_check(bool(result.get("success", false)), "混合购买与出售成功")
	_check(_profile.get_item_count(HORSE_ID) == 2, "混合交易后玩家净增 1 匹战马")
	_check(_markets.get_stock(_town.settlement_id, HORSE_ID) == 2, "混合交易后市场净减 1")
	_check(_profile.gold == gold_before - 130, "混合交易最终支付 130 金币")
	_check(int(result.get("net_gold", 0)) == 130, "混合交易净金额为 130")
	_check(_log.get_entry_count() == log_before + 1, "混合交易写入一条日志")
	_check(
		_log.get_entries().back().text.contains("最终支付 130 金币"),
		"混合日志记录最终支付金额"
	)


func _test_failures_keep_data() -> void:
	var snapshot := _snapshot()
	var gold_before: int = _profile.gold
	var log_before: int = _log.get_entry_count()

	var result := _markets.execute_player_trade(
		_town.settlement_id, {HORSE_ID: 99}, {}, _profile, "fail-stock"
	)
	_check(not bool(result.get("success", true)), "市场库存不足时交易失败")
	_check(snapshot == _snapshot(), "库存不足失败不修改任何数据")

	result = _markets.execute_player_trade(
		_town.settlement_id, {}, {HORSE_ID: 99}, _profile, "fail-items"
	)
	_check(not bool(result.get("success", true)), "玩家物品不足时交易失败")
	_check(snapshot == _snapshot(), "物品不足失败不修改任何数据")

	_profile.gold = 10
	snapshot = _snapshot()
	result = _markets.execute_player_trade(
		_town.settlement_id, {HORSE_ID: 1}, {}, _profile, "fail-gold"
	)
	_check(not bool(result.get("success", true)), "金币不足时交易失败")
	_check(_profile.gold == 10, "金币不足不扣款")
	_check(snapshot == _snapshot(), "金币不足不修改物品或库存")

	result = _markets.execute_player_trade(
		_village.settlement_id, {HORSE_ID: 1}, {}, _profile, "fail-village"
	)
	_check(not bool(result.get("success", true)), "村庄不能交易城镇限定马匹")
	result = _markets.execute_player_trade(
		"SETTLEMENT_MISSING", {HORSE_ID: 1}, {}, _profile, "fail-missing"
	)
	_check(not bool(result.get("success", true)), "不存在的城镇不能交易")

	result = _markets.execute_player_trade(
		_town.settlement_id, {}, {}, _profile, "fail-empty"
	)
	_check(not bool(result.get("success", true)), "空交易失败")
	_check(_log.get_entry_count() == log_before, "所有失败交易都不写日志")
	_profile.gold = gold_before


func _test_non_tradeable_and_no_sell_price() -> void:
	_profile.add_item(SWORD_ID, 1)
	_profile.add_item(TOKEN_ID, 1)
	var snapshot := _snapshot()

	var result := _markets.execute_player_trade(
		_town.settlement_id, {TOKEN_ID: 1}, {}, _profile, "fail-not-tradeable"
	)
	_check(not bool(result.get("success", true)), "is_tradeable=false 的商品不能购买")
	_check(snapshot == _snapshot(), "不可交易商品失败不修改数据")

	result = _markets.execute_player_trade(
		_town.settlement_id, {}, {TOKEN_ID: 1}, _profile, "fail-not-sellable"
	)
	_check(not bool(result.get("success", true)), "不可交易商品不能出售")

	result = _markets.execute_player_trade(
		_town.settlement_id, {}, {SWORD_ID: 1}, _profile, "fail-no-price"
	)
	_check(not bool(result.get("success", true)), "没有收购价的商品不能出售")
	_check(snapshot == _snapshot(), "不可出售判断不修改数据")


func _test_duplicate_submit() -> void:
	_profile.gold = 1000
	var before_stock: int = _markets.get_stock(_town.settlement_id, HORSE_ID)
	var before_count: int = _profile.get_item_count(HORSE_ID)
	var before_gold: int = _profile.gold
	var result := _markets.execute_player_trade(
		_town.settlement_id, {HORSE_ID: 1}, {}, _profile, "duplicate-1"
	)
	_check(bool(result.get("success", false)), "首次提交成功")
	var after_gold: int = _profile.gold
	result = _markets.execute_player_trade(
		_town.settlement_id, {HORSE_ID: 1}, {}, _profile, "duplicate-1"
	)
	_check(not bool(result.get("success", true)), "相同交易 ID 重复提交失败")
	_check(_profile.gold == after_gold, "重复提交不重复扣款")
	_check(
		_profile.get_item_count(HORSE_ID) == before_count + 1,
		"重复提交不重复增加物品"
	)
	_check(
		_markets.get_stock(_town.settlement_id, HORSE_ID) == before_stock - 1,
		"重复提交不重复减少库存"
	)
	_check(before_gold == after_gold + 100, "首次扣款仍正确")


func _test_npc_trade_does_not_log() -> void:
	var log_before: int = _log.get_entry_count()
	var stock_before: int = _markets.get_stock(_town.settlement_id, HORSE_ID)
	var result := _markets.execute_npc_trade(
		_town.settlement_id, {HORSE_ID: 1}, {}, _profile, "npc-1"
	)
	_check(bool(result.get("success", false)), "NPC 来源交易可以结算")
	_check(_log.get_entry_count() == log_before, "NPC 交易不写入玩家世界日志")
	_check(
		_markets.get_stock(_town.settlement_id, HORSE_ID) == stock_before - 1,
		"NPC 交易仍然修改市场库存"
	)


func _test_serialization_and_old_save_fill() -> void:
	var payload: Dictionary = _markets.to_dict()
	var restored := MarketManager.new()
	restored.setup(_settlements, _units, _items, _log)
	_register_goods(restored)
	restored.load_from_dict(payload)
	_check(
		restored.get_stock(_town.settlement_id, HORSE_ID)
			== _markets.get_stock(_town.settlement_id, HORSE_ID),
		"市场库存往返一致"
	)
	var stock_before: int = restored.get_stock(_town.settlement_id, HORSE_ID)
	restored.ensure_markets()
	_check(
		restored.get_stock(_town.settlement_id, HORSE_ID) == stock_before,
		"ensure_markets 不重置已有库存"
	)
	_check(
		restored.get_stock(_town.settlement_id, TOKEN_ID) == 5,
		"旧存档缺失商品时只补初始库存"
	)

	# 旧存档完全没有 markets 字段：按当前配置初始化一次。
	var old_save := MarketManager.new()
	old_save.setup(_settlements, _units, _items, _log)
	_register_goods(old_save)
	old_save.load_from_dict({})
	old_save.ensure_markets()
	_check(
		old_save.get_stock(_town.settlement_id, HORSE_ID) == 3,
		"旧存档缺少市场数据时初始化初始库存"
	)
	_check(
		old_save.get_market(_village.settlement_id) != null,
		"旧存档初始化也会给村庄建补给市场"
	)
	_check(
		old_save.get_stock(_village.settlement_id, HORSE_ID) == 0,
		"旧存档村庄市场不含城镇限定商品"
	)


func _setup_fixture() -> bool:
	_ids = IdGenerator.new()
	_units = UnitManager.new()
	_units.setup(_ids)
	_items = ItemManager.new()
	_settlements = SettlementManager.new()
	_settlements.setup(_ids)
	_log = WorldLogManager.new()
	_profile = PlayerProfile.new()
	_profile.gold = 1000

	var horse := load(HORSE_PATH) as EquipmentConfig
	var sword := load(SWORD_PATH) as EquipmentConfig
	var token := load(TOKEN_PATH) as ItemConfig
	var bread := load(BREAD_PATH) as ItemConfig
	var fodder := load(FODDER_PATH) as ItemConfig
	_check(
		horse != null and sword != null and token != null
			and bread != null and fodder != null,
		"加载商品引用的装备/物品配置"
	)
	if horse == null or sword == null or token == null \
			or bread == null or fodder == null:
		return false
	_units.register_equipment_config(horse)
	_units.register_equipment_config(sword)
	_items.register_item_config(token)
	_items.register_item_config(bread)
	_items.register_item_config(fodder)

	_town = _settlements.create_settlement(
		"测试城镇", SettlementData.SettlementType.TOWN, Vector2(100.0, 100.0)
	)
	_village = _settlements.create_settlement(
		"测试村庄", SettlementData.SettlementType.VILLAGE, Vector2(200.0, 100.0)
	)
	_village.households = 100
	# 测试村庄以面包、草料为主特产，用于验证叠加与动态库存。
	_village.village_specialty_item_ids = [BREAD_ID, FODDER_ID]
	_castle = _settlements.create_settlement(
		"测试城堡", SettlementData.SettlementType.CASTLE, Vector2(300.0, 100.0)
	)
	_markets = MarketManager.new()
	_markets.setup(_settlements, _units, _items, _log)
	if not _register_goods(_markets):
		return false
	_check(_markets.ensure_markets(), "初始化城镇市场")
	return true


func _register_goods(manager: MarketManager) -> bool:
	var horse_goods := MarketGoodsConfig.new()
	horse_goods.item_id = HORSE_ID
	horse_goods.buy_price = 100
	horse_goods.sell_price = 70
	horse_goods.initial_stock = 3
	horse_goods.is_tradeable = true
	if not manager.register_goods_config(horse_goods):
		_check(false, "注册普通战马商品")
		return false

	var token_goods := MarketGoodsConfig.new()
	token_goods.item_id = TOKEN_ID
	token_goods.buy_price = 50
	token_goods.sell_price = 10
	token_goods.initial_stock = 5
	token_goods.is_tradeable = false
	if not manager.register_goods_config(token_goods):
		_check(false, "注册不可交易的晋升凭证")
		return false

	var sword_goods := MarketGoodsConfig.new()
	sword_goods.item_id = SWORD_ID
	sword_goods.buy_price = 200
	sword_goods.sell_price = 0
	sword_goods.initial_stock = 1
	sword_goods.is_tradeable = true
	if not manager.register_goods_config(sword_goods):
		_check(false, "注册无收购价的武器")
		return false

	var bread_goods := MarketGoodsConfig.new()
	bread_goods.item_id = BREAD_ID
	bread_goods.buy_price = 2.0
	bread_goods.sell_price = 1.0
	bread_goods.initial_stock = 50
	bread_goods.scope = MarketGoodsConfig.MarketScope.VILLAGE_AND_TOWN
	bread_goods.batch_purchase_amounts = [10, 50]
	bread_goods.village_buy_base_price = 0.3
	bread_goods.village_scarcity_price_min = 0.3
	bread_goods.village_scarcity_price_max = 1.5
	bread_goods.village_abundance_price_min = 0.1
	bread_goods.village_abundance_price_max = 0.3
	bread_goods.stock_cap_per_100_households = 200
	bread_goods.base_floor_per_100_households = 100
	if not manager.register_goods_config(bread_goods):
		_check(false, "注册村庄面包商品")
		return false

	var fodder_goods := MarketGoodsConfig.new()
	fodder_goods.item_id = FODDER_ID
	fodder_goods.buy_price = 3.0
	fodder_goods.sell_price = 1.0
	fodder_goods.initial_stock = 50
	fodder_goods.scope = MarketGoodsConfig.MarketScope.VILLAGE_AND_TOWN
	fodder_goods.batch_purchase_amounts = [10, 50]
	fodder_goods.village_buy_base_price = 0.5
	fodder_goods.village_scarcity_price_min = 0.5
	fodder_goods.village_scarcity_price_max = 2.0
	fodder_goods.village_abundance_price_min = 0.2
	fodder_goods.village_abundance_price_max = 0.5
	fodder_goods.stock_cap_per_100_households = 100
	fodder_goods.base_floor_per_100_households = 50
	if not manager.register_goods_config(fodder_goods):
		_check(false, "注册村庄草料商品")
		return false
	return true


func _snapshot() -> Dictionary:
	var market := _markets.get_market(_town.settlement_id)
	var mounts: Array[String] = []
	if market != null:
		for instance: MountInstanceData in market.mount_instances:
			if instance != null:
				mounts.append(instance.instance_id)
	return {
		"gold": _profile.gold,
		"inventory": _profile.inventory.duplicate(),
		"counts": _profile.item_counts.duplicate(true),
		"mounts": _mount_ids(_profile.get_all_mount_instances()),
		"stock": market.stock.duplicate(true) if market != null else {},
		"market_mounts": mounts,
	}


func _mount_ids(instances: Array[MountInstanceData]) -> Array[String]:
	var ids: Array[String] = []
	for instance: MountInstanceData in instances:
		if instance != null:
			ids.append(instance.instance_id)
	return ids


func _finish() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[market] OK: %s" % message)
	else:
		_failed = true
		push_error("[market] FAIL: %s" % message)
