extends Node
## 村庄经济系统测试（动态库存 / 价格 / 每日补货 / 牲畜实例 / 宰杀）：
## - 动态库存上限只由户数与商品配置决定；
## - 面包、草料基础保底与特产上限独立叠加；
## - 库存比例决定村庄采购价，价格平滑且不越界；
## - 每日 00:00 按动态上限的 25% 补货，同日不重复，旧存档不补发历史；
## - 被破坏村庄停止补货但保留库存；
## - 猪按独立实例交易，猪特产村庄同时生产肉；
## - 宰杀猪/马获得 20 单位肉；
## - 金币使用小数并随存档往返。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/UnitTests/village_stock_test.tscn

const BREAD_ID: String = "bread"
const FODDER_ID: String = "fodder"
const PIG_ID: String = "pig"
const MEAT_ID: String = "meat"
const SALT_ID: String = "salt"
const HORSE_ID: String = "mount_horse_01"
const SECONDS_PER_DAY: float = 48.0

const BREAD_ITEM_PATH: String = "res://Data/Items/bread.tres"
const FODDER_ITEM_PATH: String = "res://Data/Items/fodder.tres"
const PIG_ITEM_PATH: String = "res://Data/Items/pig.tres"
const MEAT_ITEM_PATH: String = "res://Data/Items/meat.tres"
const SALT_ITEM_PATH: String = "res://Data/Items/salt.tres"
const HORSE_PATH: String = "res://Data/Equipment/mount_horse_01.tres"

var _failed: bool = false
var _ids: IdGenerator = null
var _units: UnitManager = null
var _items: ItemManager = null
var _settlements: SettlementManager = null
var _log: WorldLogManager = null
var _markets: MarketManager = null
var _slaughter: SlaughterManager = null
var _profile: PlayerProfile = null
var _village: SettlementData = null
var _town: SettlementData = null


func _ready() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	if not _setup_fixture():
		_finish()
		push_error("[village-stock] 测试前置失败")
		get_tree().quit(1)
		return
	_test_initial_stock_and_caps()
	_test_household_scaling()
	_test_specialty_stacking()
	_test_price_by_stock_ratio()
	_test_salt_config_is_followed()
	_test_float_purchase()
	_test_daily_production()
	_test_old_save_first_tick()
	_test_destroyed_village()
	_test_sell_never_exceeds_max()
	_test_pig_instances_and_slaughter()
	_test_horse_slaughter()
	_test_serialization()
	_finish()
	if _failed:
		push_error("[village-stock] 测试失败")
		get_tree().quit(1)
	else:
		print("[village-stock] 全部通过")
		get_tree().quit(0)


func _setup_fixture() -> bool:
	_ids = IdGenerator.new()
	_units = UnitManager.new()
	_units.setup(_ids)
	_items = ItemManager.new()
	_settlements = SettlementManager.new()
	_settlements.setup(_ids)
	_log = WorldLogManager.new()
	_profile = PlayerProfile.new()
	_profile.gold = 10000.0

	var horse := load(HORSE_PATH) as EquipmentConfig
	var bread := load(BREAD_ITEM_PATH) as ItemConfig
	var fodder := load(FODDER_ITEM_PATH) as ItemConfig
	var pig := load(PIG_ITEM_PATH) as ItemConfig
	var meat := load(MEAT_ITEM_PATH) as ItemConfig
	var salt := load(SALT_ITEM_PATH) as ItemConfig
	_check(
		horse != null and bread != null and fodder != null \
			and pig != null and meat != null and salt != null,
		"加载测试所需的装备/物品配置"
	)
	if horse == null or bread == null or fodder == null \
			or pig == null or meat == null or salt == null:
		return false
	_units.register_equipment_config(horse)
	for item: ItemConfig in [bread, fodder, pig, meat, salt]:
		_items.register_item_config(item)

	_village = _settlements.create_settlement(
		"测试村庄",
		SettlementData.SettlementType.VILLAGE,
		Vector2(100.0, 100.0)
	)
	_village.households = 100
	_village.map_key = "test_village"
	_village.village_specialty_item_ids = [BREAD_ID]
	_town = _settlements.create_settlement(
		"测试城镇",
		SettlementData.SettlementType.TOWN,
		Vector2(200.0, 100.0)
	)

	_markets = MarketManager.new()
	_markets.setup(_settlements, _units, _items, _log)
	_slaughter = SlaughterManager.new()
	_slaughter.setup(_items)
	if not _register_goods(_markets):
		return false
	_check(_markets.ensure_markets(), "初始化村庄与城镇市场")
	TimeManager.restore_world_time(0.0, TimeManager.SPEED_NORMAL)
	return true


func _register_goods(manager: MarketManager) -> bool:
	if not manager.register_goods_config(_make_goods(
		BREAD_ID, 2.0, 0.15, 0.3, 0.3, 1.5, 0.1, 0.3, 200, 100
	)):
		_check(false, "注册面包商品")
		return false
	if not manager.register_goods_config(_make_goods(
		FODDER_ID, 3.0, 0.25, 0.5, 0.5, 2.0, 0.2, 0.5, 100, 50
	)):
		_check(false, "注册草料商品")
		return false
	if not manager.register_goods_config(_make_goods(
		PIG_ID, 20.0, 7.5, 15.0, 15.0, 22.0, 8.0, 15.0, 20, 0
	)):
		_check(false, "注册猪商品")
		return false
	var meat_goods := _make_goods(
		MEAT_ID, 3.0, 1.0, 2.0, 2.0, 5.0, 1.0, 2.0, 50, 0
	)
	if not manager.register_goods_config(meat_goods):
		_check(false, "注册肉商品")
		return false
	if not manager.register_goods_config(_make_goods(
		SALT_ID, 2.0, 0.5, 1.0, 0.5, 1.0, 1.0, 2.0, 100, 0
	)):
		_check(false, "注册盐商品")
		return false
	var pig_goods := manager.get_goods_config(PIG_ID)
	if pig_goods == null:
		return false
	pig_goods.associated_item_id = MEAT_ID
	# 非堆叠商品由 ItemConfig 注册状态决定实例化，这里同步商品配置。
	pig_goods.is_stackable = false
	return true


func _make_goods(
	item_id: String,
	town_buy: float,
	sell: float,
	base: float,
	scarcity_min: float,
	scarcity_max: float,
	abundance_min: float,
	abundance_max: float,
	cap_per_100: int,
	base_floor: int
) -> MarketGoodsConfig:
	var config := MarketGoodsConfig.new()
	config.item_id = item_id
	config.buy_price = town_buy
	config.sell_price = sell
	config.initial_stock = 20
	config.is_tradeable = true
	config.scope = MarketGoodsConfig.MarketScope.VILLAGE_ONLY
	config.is_stackable = item_id != PIG_ID
	config.village_buy_base_price = base
	config.village_scarcity_price_min = scarcity_min
	config.village_scarcity_price_max = scarcity_max
	config.village_abundance_price_min = abundance_min
	config.village_abundance_price_max = abundance_max
	config.stock_cap_per_100_households = cap_per_100
	config.base_floor_per_100_households = base_floor
	config.village_initial_stock_ratio = 0.5
	config.daily_refill_ratio = 0.25
	return config


# ---------------------------------------------------------------------------
# 库存上限与初始库存
# ---------------------------------------------------------------------------


func _test_initial_stock_and_caps() -> void:
	_check(
		_markets.get_village_stock_max(_village.settlement_id, BREAD_ID) == 300,
		"100 户面包特产村庄：面包上限 = 保底 100 + 特产 200"
	)
	_check(
		_markets.get_village_stock_max(_village.settlement_id, FODDER_ID) == 50,
		"100 户非草料特产村庄：草料上限 = 保底 50"
	)
	_check(
		_markets.get_stock(_village.settlement_id, BREAD_ID) == 150,
		"村庄初始库存 = 动态上限 × 50%"
	)
	_check(
		_markets.get_stock(_village.settlement_id, FODDER_ID) == 25,
		"非特产保底草料同样按比例初始化"
	)
	_check(
		_markets.get_village_stock_max(_town.settlement_id, BREAD_ID) == 0,
		"城镇不参与村庄动态库存"
	)


func _test_household_scaling() -> void:
	var stock_before: int = _markets.get_stock(_village.settlement_id, BREAD_ID)
	_village.households = 200
	_check(
		_markets.get_village_stock_max(_village.settlement_id, BREAD_ID) == 600,
		"200 户面包特产村庄：面包上限 600"
	)
	_check(
		_markets.get_village_stock_max(_village.settlement_id, FODDER_ID) == 100,
		"200 户村庄：草料保底上限 100"
	)
	_check(
		_markets.get_stock(_village.settlement_id, BREAD_ID) == stock_before,
		"户数变化只重算上限，不重置库存"
	)
	_village.households = 100


func _test_specialty_stacking() -> void:
	_village.village_specialty_item_ids = [BREAD_ID, FODDER_ID]
	_check(
		_markets.get_village_stock_max(_village.settlement_id, FODDER_ID) == 150,
		"草料特产：保底 50 + 特产 100 = 150"
	)
	_check(
		_markets.get_village_stock_max(_village.settlement_id, BREAD_ID) == 300,
		"面包特产：保底 100 + 特产 200 = 300"
	)
	_village.village_specialty_item_ids = [BREAD_ID]


# ---------------------------------------------------------------------------
# 价格
# ---------------------------------------------------------------------------


func _test_price_by_stock_ratio() -> void:
	# 面包上限 300：0% → 1.5；40% → 0.3；100% → 0.1。
	_markets.get_market(_village.settlement_id).set_stock(BREAD_ID, 0)
	_check(
		is_equal_approx(_markets.get_buy_price(_village.settlement_id, BREAD_ID), 1.5),
		"库存 0% 时面包价格到达紧缺区间高价端 1.5"
	)
	_markets.get_market(_village.settlement_id).set_stock(BREAD_ID, 120)
	_check(
		is_equal_approx(_markets.get_buy_price(_village.settlement_id, BREAD_ID), 0.3),
		"库存 40% 时面包价格回到标准价 0.3"
	)
	_markets.get_market(_village.settlement_id).set_stock(BREAD_ID, 300)
	_check(
		is_equal_approx(_markets.get_buy_price(_village.settlement_id, BREAD_ID), 0.1),
		"库存 100% 时面包价格到达富足区间低价端 0.1"
	)
	# 库存比例相同、户数不同时，价格只由比例决定。
	_markets.get_market(_village.settlement_id).set_stock(BREAD_ID, 150)
	var price_100: float = _markets.get_buy_price(
		_village.settlement_id, BREAD_ID
	)
	_village.households = 200
	_markets.get_market(_village.settlement_id).set_stock(BREAD_ID, 300)
	var price_200: float = _markets.get_buy_price(
		_village.settlement_id, BREAD_ID
	)
	_check(
		is_equal_approx(price_100, price_200),
		"价格按库存比例而非绝对库存计算"
	)
	_village.households = 100


func _test_salt_config_is_followed() -> void:
	_set_specialty([SALT_ID])
	var market := _markets.get_market(_village.settlement_id)
	# 盐：紧缺区间 0.5-1，标准价 1，富足区间 1-2。
	market.set_stock(SALT_ID, 0)
	_check(
		is_equal_approx(_markets.get_buy_price(_village.settlement_id, SALT_ID), 1.0),
		"盐库存 0% 时取配置紧缺高价端 1.0"
	)
	market.set_stock(SALT_ID, 40)
	_check(
		is_equal_approx(_markets.get_buy_price(_village.settlement_id, SALT_ID), 0.5),
		"盐库存 40% 时取配置紧缺低价端 0.5（不擅自高于标准价）"
	)
	market.set_stock(SALT_ID, 70)
	_check(
		is_equal_approx(_markets.get_buy_price(_village.settlement_id, SALT_ID), 2.0),
		"盐库存 70% 时按配置进入富足高价端 2.0"
	)
	_set_specialty([BREAD_ID])


func _test_float_purchase() -> void:
	# 面包上限 300，库存 100 → 比例 1/3 → 单价 0.5。
	_set_specialty([BREAD_ID])
	var market := _markets.get_market(_village.settlement_id)
	market.set_stock(BREAD_ID, 100)
	_profile.gold = 100.0
	var result := _markets.execute_player_trade(
		_village.settlement_id, {BREAD_ID: 10}, {}, _profile, "float-bread"
	)
	_check(bool(result.get("success", false)), "面包交易成功")
	_check(
		is_equal_approx(float(result.get("purchase_total", 0.0)), 5.0),
		"10 × 0.5 = 5.0，交易总额保留小数"
	)
	_check(
		is_equal_approx(_profile.gold, 95.0),
		"金币余额按小数扣除，不错误取整"
	)
	_check(
		_markets.get_stock(_village.settlement_id, BREAD_ID) == 90,
		"购买后库存按整数减少"
	)


# ---------------------------------------------------------------------------
# 每日补货
# ---------------------------------------------------------------------------


func _test_daily_production() -> void:
	_set_specialty([BREAD_ID])
	var market := _markets.get_market(_village.settlement_id)
	market.set_stock(BREAD_ID, 100)
	market.set_stock(FODDER_ID, 25)
	market.daily_production_day = -1
	TimeManager.restore_world_time(0.0, TimeManager.SPEED_NORMAL)
	_markets.settle_village_daily_production()
	_check(
		_markets.get_stock(_village.settlement_id, BREAD_ID) == 100,
		"首日初始化补货日期，不立即产出"
	)

	TimeManager.restore_world_time(SECONDS_PER_DAY, TimeManager.SPEED_NORMAL)
	_markets.settle_village_daily_production()
	_check(
		_markets.get_stock(_village.settlement_id, BREAD_ID) == 175,
		"跨日补货 = 上限 300 × 25% = 75"
	)
	_check(
		_markets.get_stock(_village.settlement_id, FODDER_ID) == 38,
		"草料补货 = ceil(50 × 25%) = 13"
	)
	_markets.settle_village_daily_production()
	_check(
		_markets.get_stock(_village.settlement_id, BREAD_ID) == 175,
		"同一游戏日不重复补货"
	)

	TimeManager.restore_world_time(SECONDS_PER_DAY * 2.0, TimeManager.SPEED_NORMAL)
	_markets.settle_village_daily_production()
	_check(
		_markets.get_stock(_village.settlement_id, BREAD_ID) == 250,
		"第二日继续补 75，库存 250"
	)
	TimeManager.restore_world_time(SECONDS_PER_DAY * 3.0, TimeManager.SPEED_NORMAL)
	_markets.settle_village_daily_production()
	_check(
		_markets.get_stock(_village.settlement_id, BREAD_ID) == 300,
		"补货量超过剩余空间时只补到上限"
	)
	TimeManager.restore_world_time(SECONDS_PER_DAY * 4.0, TimeManager.SPEED_NORMAL)
	_markets.settle_village_daily_production()
	_check(
		_markets.get_stock(_village.settlement_id, BREAD_ID) == 300,
		"达到上限后不再补货"
	)


func _test_old_save_first_tick() -> void:
	_set_specialty([BREAD_ID])
	var payload: Dictionary = _markets.get_market(_village.settlement_id).to_dict()
	payload.erase("daily_production_day")
	var legacy := MarketData.from_dict(payload)
	_check(legacy.daily_production_day == -1, "旧存档缺少补货日期时保持未初始化")

	_markets.load_from_dict({
		"markets": {
			_village.settlement_id: payload,
			_town.settlement_id: _markets.get_market(_town.settlement_id).to_dict(),
		},
	})
	var market := _markets.get_market(_village.settlement_id)
	market.set_stock(BREAD_ID, 0)
	TimeManager.restore_world_time(SECONDS_PER_DAY * 50.0, TimeManager.SPEED_NORMAL)
	_markets.settle_village_daily_production()
	_check(
		_markets.get_stock(_village.settlement_id, BREAD_ID) == 0,
		"旧存档读档后的首个 tick 不补发历史产出"
	)
	_check(market.daily_production_day == 50, "旧存档以读档当天作为补货起点")

	TimeManager.restore_world_time(SECONDS_PER_DAY * 51.0, TimeManager.SPEED_NORMAL)
	_markets.settle_village_daily_production()
	_check(
		_markets.get_stock(_village.settlement_id, BREAD_ID) == 75,
		"旧存档从下一天开始按 25% 上限补货"
	)


func _test_destroyed_village() -> void:
	_set_specialty([BREAD_ID])
	var market := _markets.get_market(_village.settlement_id)
	market.daily_production_day = 60
	market.set_stock(BREAD_ID, 40)
	_village.set_destroyed(true)
	_check(_village.is_destroyed(), "村庄可进入被破坏状态")
	TimeManager.restore_world_time(SECONDS_PER_DAY * 61.0, TimeManager.SPEED_NORMAL)
	_markets.settle_village_daily_production()
	_check(
		_markets.get_stock(_village.settlement_id, BREAD_ID) == 40,
		"被破坏村庄停止补货"
	)
	_check(
		_markets.add_village_stock(_village.settlement_id, BREAD_ID, 10) == 0,
		"被破坏村庄拒绝程序化增加库存"
	)
	_check(
		_markets.get_stock(_village.settlement_id, BREAD_ID) == 40,
		"被破坏村庄保留现有库存，不清空"
	)
	_village.set_destroyed(false)


func _test_sell_never_exceeds_max() -> void:
	_set_specialty([BREAD_ID])
	var market := _markets.get_market(_village.settlement_id)
	market.set_stock(BREAD_ID, 300)
	_profile.add_item(BREAD_ID, 10)
	var gold_before: float = _profile.gold
	var result := _markets.execute_player_trade(
		_village.settlement_id, {}, {BREAD_ID: 10}, _profile, "sell-over-max"
	)
	_check(bool(result.get("success", false)), "达到上限时仍可完成出售结算")
	_check(
		_markets.get_stock(_village.settlement_id, BREAD_ID) == 300,
		"出售给村庄的库存不会突破上限"
	)
	_check(
		is_equal_approx(_profile.gold, gold_before + 10.0 * 0.15),
		"玩家按小数收购价获得金币"
	)


# ---------------------------------------------------------------------------
# 猪、肉与宰杀
# ---------------------------------------------------------------------------


func _test_pig_instances_and_slaughter() -> void:
	_set_specialty([PIG_ID])
	_check(
		_markets.ensure_markets(),
		"切换到猪特产后补齐猪与肉的市场库存"
	)
	var market := _markets.get_market(_village.settlement_id)
	var pig_instances := market.get_item_instances(PIG_ID)
	for instance: ItemInstanceData in pig_instances:
		market.remove_item_instance(instance.instance_id)
	for index: int in range(10):
		market.add_item_instance(ItemInstanceData.create_random(PIG_ID))
	_check(market.get_stock(PIG_ID) == 10, "猪以独立实例计数")

	_profile.gold = 10000.0
	var result := _markets.execute_player_trade(
		_village.settlement_id, {PIG_ID: 2}, {}, _profile, "buy-pigs"
	)
	_check(bool(result.get("success", false)), "按数量购买猪会转换为具体实例")
	_check(_profile.get_item_instance_count(PIG_ID) == 2, "玩家获得 2 头猪实例")
	_check(market.get_stock(PIG_ID) == 8, "村庄猪库存减少 2")

	var player_pigs: Array[ItemInstanceData] = _profile.get_item_instances(PIG_ID)
	_check(player_pigs.size() == 2, "玩家背包中的猪是独立实例")
	var instance_id: String = player_pigs[0].instance_id
	result = _markets.execute_player_trade(
		_village.settlement_id,
		{},
		{},
		_profile,
		"sell-pig-instance",
		[],
		[],
		[],
		[instance_id]
	)
	_check(bool(result.get("success", false)), "按实例 ID 出售猪成功")
	_check(market.get_stock(PIG_ID) == 9, "出售后村庄猪库存恢复 1")
	_check(_profile.get_item_instance_count(PIG_ID) == 1, "玩家剩余 1 头猪")

	result = _markets.execute_player_trade(
		_village.settlement_id, {PIG_ID: 1}, {}, _profile, "buy-pig-again"
	)
	_check(bool(result.get("success", false)), "再次购买 1 头猪成功")
	_check(_profile.get_item_instance_count(PIG_ID) == 2, "玩家重新拥有 2 头猪")

	_check(
		_markets.get_village_stock_max(_village.settlement_id, MEAT_ID) == 50,
		"猪特产村庄的肉上限按肉配置独立计算"
	)
	market.set_stock(MEAT_ID, 0)
	market.daily_production_day = 69
	TimeManager.restore_world_time(SECONDS_PER_DAY * 70.0, TimeManager.SPEED_NORMAL)
	_markets.settle_village_daily_production()
	_check(
		_markets.get_stock(_village.settlement_id, PIG_ID) > 8,
		"猪特产村庄每日补充猪实例"
	)
	_check(
		_markets.get_stock(_village.settlement_id, MEAT_ID) == 13,
		"关联产出肉按肉上限的 25% 独立补货"
	)

	var meat_before: int = _profile.get_item_count(MEAT_ID)
	result = _slaughter.slaughter(_profile, PIG_ID)
	_check(bool(result.get("success", false)), "玩家可以宰杀猪")
	_check(
		_profile.get_item_instance_count(PIG_ID) == 1,
		"宰杀后对应猪实例被移除"
	)
	_check(
		_profile.get_item_count(MEAT_ID) == meat_before + 20,
		"宰杀猪获得 20 单位肉"
	)
	result = _slaughter.slaughter(_profile, PIG_ID)
	_check(bool(result.get("success", false)), "可以继续宰杀剩余猪")
	result = _slaughter.slaughter(_profile, PIG_ID)
	_check(not bool(result.get("success", true)), "没有猪时宰杀失败")
	_set_specialty([BREAD_ID])


func _test_horse_slaughter() -> void:
	_profile.add_item(HORSE_ID, 1)
	_check(_profile.get_mount_count(HORSE_ID) == 1, "玩家获得 1 匹马实例")
	var meat_before: int = _profile.get_item_count(MEAT_ID)
	var result := _slaughter.slaughter(_profile, HORSE_ID)
	_check(bool(result.get("success", false)), "玩家可以宰杀马")
	_check(_profile.get_mount_count(HORSE_ID) == 0, "宰杀后马实例被移除")
	_check(
		_profile.get_item_count(MEAT_ID) == meat_before + 20,
		"宰杀马获得 20 单位肉"
	)


# ---------------------------------------------------------------------------
# 序列化
# ---------------------------------------------------------------------------


func _test_serialization() -> void:
	_set_specialty([PIG_ID])
	var market := _markets.get_market(_village.settlement_id)
	market.daily_production_day = 7
	market.set_stock(MEAT_ID, 12)
	for index: int in range(3):
		market.add_item_instance(ItemInstanceData.create_random(PIG_ID))
	var pig_count: int = market.get_item_instance_count(PIG_ID)

	var restored := MarketData.from_dict(market.to_dict())
	_check(restored.get_stock(MEAT_ID) == 12, "市场肉库存往返一致")
	_check(
		restored.get_item_instance_count(PIG_ID) == pig_count,
		"市场猪实例往返一致"
	)
	_check(restored.daily_production_day == 7, "补货日期往返一致")

	_profile.gold = 12.34
	var profile_restored := PlayerProfile.from_dict(_profile.to_dict())
	_check(
		is_equal_approx(profile_restored.gold, 12.34),
		"玩家小数金币往返一致"
	)
	_check(
		profile_restored.get_item_instance_count(PIG_ID)
			== _profile.get_item_instance_count(PIG_ID),
		"玩家猪实例往返一致"
	)

	_village.set_destroyed(true)
	_village.village_specialty_item_ids = [PIG_ID]
	var settlement := SettlementData.from_dict(_village.to_dict())
	_check(settlement.households == 100, "村庄户数写入存档")
	_check(settlement.map_key == "test_village", "村庄稳定 key 写入存档")
	_check(settlement.is_village_specialty(PIG_ID), "村庄特产写入存档")
	_check(settlement.is_destroyed(), "村庄破坏状态写入存档")
	_village.set_destroyed(false)
	_village.village_specialty_item_ids = [BREAD_ID]


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------


func _set_specialty(item_ids: Array[String]) -> void:
	_village.village_specialty_item_ids.clear()
	for item_id: String in item_ids:
		_village.village_specialty_item_ids.append(item_id)


func _finish() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[village-stock] OK: %s" % message)
	else:
		_failed = true
		push_error("[village-stock] FAIL: %s" % message)
