extends Node
## 阶段 12 每日补给测试：
## - 士兵每天 1 面包、每匹马每天 1 草料（含已装备与背包马）；
## - 只在 WorldTime 跨日结算，同一天不会重复扣粮；
## - 一次性跨多天会按天补算；
## - 库存不足时只扣到 0，记录缺口，不产生负数；
## - 玩家与 NPC 使用同一套规则，但玩家读取 PlayerProfile，NPC 读取 PartyData。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/UnitTests/supply_manager_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"
const MOUNT_PATH: String = "res://Data/Equipment/mount_horse_01.tres"
const MOUNT_ID: String = "mount_horse_01"
const BREAD_ID: String = "bread"
const FODDER_ID: String = "fodder"
const SECONDS_PER_DAY: float = 144.0

var _failed: bool = false
var _units: UnitManager = null
var _parties: PartyManager = null
var _profile: PlayerProfile = null
var _supply: SupplyManager = null
var _player_party: PartyData = null


func _ready() -> void:
	await _run()
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	if _failed:
		push_error("[supply] 测试失败")
		get_tree().quit(1)
	else:
		print("[supply] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	if not _setup_fixture():
		return
	_test_status_and_daily_consumption()
	_test_no_duplicate_settlement_same_day()
	_test_multi_day_catch_up()
	_test_shortage_never_negative()
	_test_npc_holder_and_purchase_needs()


func _setup_fixture() -> bool:
	var ids := IdGenerator.new()
	_units = UnitManager.new()
	_units.setup(ids)
	_parties = PartyManager.new()
	_parties.setup(_units, ids)
	_profile = PlayerProfile.new()
	_supply = SupplyManager.new()

	var militia := load(MILITIA_PATH) as UnitConfig
	var mount := load(MOUNT_PATH) as EquipmentConfig
	_check(militia != null and mount != null, "加载兵种与马匹配置")
	if militia == null or mount == null:
		return false
	_units.register_equipment_config(mount)

	_player_party = _parties.create_party(
		"FACTION_PLAYER", Vector2.ZERO, "玩家部队", PartyData.PartyKind.PLAYER
	)
	if _player_party == null:
		_check(false, "创建玩家部队")
		return false
	_player_party.control_type = PartyData.ControlType.PLAYER
	for i: int in range(2):
		var unit := _units.create_unit(militia, "FACTION_PLAYER")
		_check(unit != null, "创建玩家士兵 %d" % (i + 1))
		if unit == null:
			return false
		_check(_parties.add_member(_player_party.party_id, unit.unit_id), "士兵加入部队")

	# 一匹已装备 + 一匹背包，验证草料按“全部马匹”计算。
	_profile.add_item(MOUNT_ID, 2)
	_check(
		_units.equip_mount(
			_player_party.member_unit_ids[0], MOUNT_ID, _profile
		),
		"第一名士兵装备一匹马"
	)
	_supply.setup(_parties, _units, _profile, _player_party.party_id)
	TimeManager.restore_world_time(0.0, TimeManager.SPEED_NORMAL)
	_supply.reset_settlement_day(0)
	return true


func _test_status_and_daily_consumption() -> void:
	_check(_supply.get_member_count(_player_party) == 2, "部队有效成员为 2")
	_check(_supply.get_equipped_mount_count(_player_party) == 1, "已装备 1 匹马")
	_check(_supply.get_total_mount_count(_player_party) == 2, "部队共有 2 匹马（含背包）")

	_profile.add_item(BREAD_ID, 10)
	_profile.add_item(FODDER_ID, 5)
	var status := _supply.get_status(_player_party)
	_check(status["daily_bread_consumption"] == 2, "每日消耗 2 份面包")
	_check(status["daily_fodder_consumption"] == 2, "每日消耗 2 份草料")
	_check(is_equal_approx(status["food_days_remaining"], 5.0), "面包可支撑 5 天")
	_check(is_equal_approx(status["fodder_days_remaining"], 2.5), "草料可支撑 2.5 天")

	_supply.update_daily()
	_check(_profile.get_item_count(BREAD_ID) == 10, "同一天开始时不立即扣粮")
	_check(_profile.get_item_count(FODDER_ID) == 5, "草料同样未扣")

	_advance_days(1)
	_supply.update_daily()
	_check(_profile.get_item_count(BREAD_ID) == 8, "跨日后扣除 2 份面包")
	_check(_profile.get_item_count(FODDER_ID) == 3, "跨日后扣除 2 份草料")
	_check(_profile.get_item_count(BREAD_ID) >= 0, "面包数量不为负")


func _test_no_duplicate_settlement_same_day() -> void:
	var bread_before: int = _profile.get_item_count(BREAD_ID)
	var fodder_before: int = _profile.get_item_count(FODDER_ID)
	_supply.update_daily()
	_supply.update_daily()
	_check(_profile.get_item_count(BREAD_ID) == bread_before, "同一天多次 tick 不重复扣面包")
	_check(_profile.get_item_count(FODDER_ID) == fodder_before, "同一天多次 tick 不重复扣草料")


func _test_multi_day_catch_up() -> void:
	_profile.add_item(BREAD_ID, 20)
	_profile.add_item(FODDER_ID, 20)
	var bread_before: int = _profile.get_item_count(BREAD_ID)
	var fodder_before: int = _profile.get_item_count(FODDER_ID)
	_advance_days(3)
	_supply.update_daily()
	_check(
		_profile.get_item_count(BREAD_ID) == bread_before - 6,
		"一次跨 3 天补算 3 天面包"
	)
	_check(
		_profile.get_item_count(FODDER_ID) == fodder_before - 6,
		"一次跨 3 天补算 3 天草料"
	)


func _test_shortage_never_negative() -> void:
	# 把草料清空后跨日：草料保持 0，并记录缺口。
	var fodder: int = _profile.get_item_count(FODDER_ID)
	if fodder > 0:
		_profile.remove_item(FODDER_ID, fodder)
	_profile.add_item(BREAD_ID, 10)
	_advance_days(1)
	var result := _supply.settle_party(_player_party)
	_check(_profile.get_item_count(FODDER_ID) == 0, "缺草料时库存停在 0，不会变成负数")
	_check(int(result["fodder_shortage"]) == 2, "记录 2 份草料缺口")
	_check(_player_party.supply_fodder_shortage == 2, "缺口写入 PartyData 供 UI/AI 查询")
	_check(_profile.get_item_count(BREAD_ID) >= 0, "面包数量仍非负")


func _test_npc_holder_and_purchase_needs() -> void:
	var militia := load(MILITIA_PATH) as UnitConfig
	var npc := _parties.create_party(
		"FACTION_LOCAL", Vector2.ZERO, "NPC 部队", PartyData.PartyKind.GENERIC
	)
	_check(npc != null, "创建 NPC 部队")
	if npc == null:
		return
	for i: int in range(2):
		var unit := _units.create_unit(militia, "FACTION_LOCAL")
		if unit != null:
			_parties.add_member(npc.party_id, unit.unit_id)
	npc.add_item(MOUNT_ID, 1)
	_check(
		_units.equip_mount(npc.member_unit_ids[0], MOUNT_ID, npc),
		"NPC 士兵装备马匹"
	)
	npc.add_item(BREAD_ID, 4)
	npc.add_item(FODDER_ID, 1)
	npc.gold = 0

	var player_bread_before: int = _profile.get_item_count(BREAD_ID)
	var result := _supply.settle_party(npc)
	_check(_supply.get_holder(npc) == npc, "NPC 补给从 PartyData 背包扣除")
	_check(npc.get_item_count(BREAD_ID) == 2, "NPC 扣除 2 份面包")
	_check(npc.get_item_count(FODDER_ID) == 0, "NPC 草料扣到 0")
	_check(int(result["fodder_shortage"]) == 1, "NPC 记录 1 份草料缺口")
	_check(
		_profile.get_item_count(BREAD_ID) == player_bread_before,
		"NPC 结算不消耗玩家背包"
	)

	var needs := _supply.get_purchase_needs(npc)
	_check(int(needs.get(BREAD_ID, 0)) == 12, "目标储备 7 天，需补 12 份面包")
	_check(int(needs.get(FODDER_ID, 0)) == 7, "目标储备 7 天，需补 7 份草料")
	_check(_supply.has_low_supply(npc), "低补给状态可被 AI 查询")


func _advance_days(days: int) -> void:
	TimeManager.restore_world_time(
		TimeManager.world_elapsed_seconds + SECONDS_PER_DAY * float(days),
		TimeManager.SPEED_NORMAL
	)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[supply] OK: %s" % message)
	else:
		_failed = true
		push_error("[supply] FAIL: %s" % message)
