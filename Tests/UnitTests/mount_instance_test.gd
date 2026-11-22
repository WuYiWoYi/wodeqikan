extends Node
## 阶段 12 马匹个体化测试：
## - 每匹马拥有唯一 instance_id 与稳定外观；
## - 马匹不进入堆叠数量；
## - 旧存档数量迁移是确定性的、不会重复增殖；
## - 玩家背包、装备槽与市场库存都能完整序列化。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/UnitTests/mount_instance_test.tscn

const MOUNT_PATH: String = "res://Data/Equipment/mount_horse_01.tres"
const MOUNT_ID: String = "mount_horse_01"

var _failed: bool = false


func _ready() -> void:
	_setup_registry()
	_run()
	if _failed:
		push_error("[mount-instance] 测试失败")
		get_tree().quit(1)
	else:
		print("[mount-instance] 全部通过")
		get_tree().quit(0)


func _setup_registry() -> void:
	var units := UnitManager.new()
	units.setup(IdGenerator.new())
	var mount := load(MOUNT_PATH) as EquipmentConfig
	_check(mount != null, "加载马匹配置")
	if mount != null:
		_check(units.register_equipment_config(mount), "注册马匹装备到静态注册表")


func _run() -> void:
	_test_random_instance()
	_test_inventory_no_stacking()
	_test_inventory_round_trip()
	_test_legacy_migration_is_stable()
	_test_market_migration_and_round_trip()
	_test_unit_mount_serialization()


func _test_random_instance() -> void:
	var first := MountInstanceData.create_random(MOUNT_ID)
	var second := MountInstanceData.create_random(MOUNT_ID)
	_check(first != null and second != null, "创建两匹马实例")
	if first == null or second == null:
		return
	_check(not first.instance_id.is_empty(), "实例拥有 instance_id")
	_check(first.instance_id != second.instance_id, "两次创建实例 ID 不重复")
	_check(first.equipment_id == MOUNT_ID, "实例保存装备 ID")
	_check(MountInstanceData.COAT_IDS.has(first.coat_style_id), "毛色来自固定集合")
	_check(MountInstanceData.SADDLE_IDS.has(first.saddle_style_id), "马鞍来自固定集合")
	_check(not first.appearance_text().is_empty(), "外观文本可用于 UI 显示")
	_check(MountInstanceData.is_mount_item(MOUNT_ID), "静态注册表识别马匹装备")
	_check(not MountInstanceData.is_mount_item("bread"), "普通物品不会被当成马匹")


func _test_inventory_no_stacking() -> void:
	var inventory := InventoryData.new()
	_check(inventory.add_item(MOUNT_ID, 3), "背包一次加入 3 匹马")
	_check(inventory.get_mount_count(MOUNT_ID) == 3, "马匹按实例计数")
	_check(not inventory.stackable_counts.has(MOUNT_ID), "马匹不写入堆叠数量")
	_check(inventory.get_all_mount_instances().size() == 3, "背包保存 3 个独立实例")
	var ids: Dictionary = {}
	for instance: MountInstanceData in inventory.get_all_mount_instances():
		ids[instance.instance_id] = true
	_check(ids.size() == 3, "3 匹马实例 ID 各不相同")
	_check(inventory.remove_item(MOUNT_ID, 2), "按数量移除马匹")
	_check(inventory.get_mount_count(MOUNT_ID) == 1, "移除后剩余 1 个实例")


func _test_inventory_round_trip() -> void:
	var inventory := InventoryData.new()
	inventory.add_item(MOUNT_ID, 2)
	var first: MountInstanceData = inventory.mount_instances[0]
	var second: MountInstanceData = inventory.mount_instances[1]
	var payload := inventory.to_dict()
	var restored := InventoryData.from_dict(payload)
	_check(restored.get_mount_count(MOUNT_ID) == 2, "背包往返后马匹数量一致")
	_check(
		not restored.stackable_counts.has(MOUNT_ID),
		"背包往返后不会把马匹写回堆叠数量"
	)
	var restored_instance := restored.get_mount_instance(first.instance_id)
	_check(restored_instance != null, "背包往返后保留实例 ID")
	if restored_instance != null:
		_check(
			restored_instance.coat_style_id == first.coat_style_id
				and restored_instance.saddle_style_id == first.saddle_style_id,
			"背包往返后外观保持不变"
		)
	_check(
		restored.get_mount_instance(second.instance_id) != null,
		"第二匹马实例也保留"
	)


func _test_legacy_migration_is_stable() -> void:
	var legacy_payload := {
		"gold": 0,
		"inventory": [MOUNT_ID],
		"inventory_counts": {MOUNT_ID: 2},
	}
	var first_load := PlayerProfile.from_dict(legacy_payload)
	var second_load := PlayerProfile.from_dict(legacy_payload)
	_check(first_load.get_item_count(MOUNT_ID) == 2, "旧存档 2 匹马迁移为 2 个实例")
	_check(not first_load.item_counts.has(MOUNT_ID), "迁移后不再保留马匹堆叠计数")
	_check(
		_mount_ids(first_load.get_all_mount_instances())
			== _mount_ids(second_load.get_all_mount_instances()),
		"重复读取旧存档不会改变马匹实例 ID（不会凭空增殖）"
	)

	var round_trip := PlayerProfile.from_dict(first_load.to_dict())
	_check(round_trip.get_item_count(MOUNT_ID) == 2, "迁移后再次存档/读档数量不变")
	_check(
		_mount_ids(round_trip.get_all_mount_instances())
			== _mount_ids(first_load.get_all_mount_instances()),
		"迁移后的实例 ID 在后续存档中保持稳定"
	)


func _test_market_migration_and_round_trip() -> void:
	var legacy_payload := {
		"settlement_id": "TOWN_TEST",
		"stock": {MOUNT_ID: 2, "bread": 5},
	}
	var market := MarketData.from_dict(legacy_payload)
	_check(market.get_mount_count(MOUNT_ID) == 2, "旧市场马匹数量迁移为 2 个实例")
	_check(not market.stock.has(MOUNT_ID), "市场堆叠库存中不再保存马匹")
	_check(market.get_stock("bread") == 5, "普通商品库存保持不变")
	_check(market.is_initialized(MOUNT_ID), "迁移出的马匹商品标记为已初始化")

	var restored := MarketData.from_dict(market.to_dict())
	_check(
		_market_ids(restored.mount_instances) == _market_ids(market.mount_instances),
		"市场马匹实例往返稳定"
	)

	var sold := market.to_dict()
	sold["mount_instances"] = []
	sold["initialized_items"] = {MOUNT_ID: true}
	var sold_market := MarketData.from_dict(sold)
	_check(sold_market.get_stock(MOUNT_ID) == 0, "卖光的市场库存读档后保持为 0")


func _test_unit_mount_serialization() -> void:
	var instance := MountInstanceData.create_random(MOUNT_ID)
	var unit := UnitData.new()
	unit.unit_id = "UNIT_MOUNT_TEST"
	unit.config_id = "infantry_militia"
	unit.equipment = {"MOUNT": MOUNT_ID}
	unit.is_mounted = true
	unit.set_mount_instance_data(instance)
	var restored := UnitData.from_dict(unit.to_dict())
	_check(restored.is_mounted, "单位读档后保持骑乘")
	var restored_mount := restored.get_mount_instance_data()
	_check(restored_mount != null, "单位读档后保留坐骑实例")
	if restored_mount != null:
		_check(
			restored_mount.instance_id == instance.instance_id
				and restored_mount.coat_style_id == instance.coat_style_id
				and restored_mount.saddle_style_id == instance.saddle_style_id,
			"单位坐骑实例 ID 与外观往返一致"
		)


func _mount_ids(instances: Array[MountInstanceData]) -> Array[String]:
	var ids: Array[String] = []
	for instance: MountInstanceData in instances:
		if instance != null:
			ids.append(instance.instance_id)
	ids.sort()
	return ids


func _market_ids(instances: Array[MountInstanceData]) -> Array[String]:
	return _mount_ids(instances)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[mount-instance] OK: %s" % message)
	else:
		_failed = true
		push_error("[mount-instance] FAIL: %s" % message)
