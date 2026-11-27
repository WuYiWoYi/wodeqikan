extends Node
## 阶段 6 家族、外观、领袖与统一速度测试。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/family_appearance_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"
const TRAINED_PATH: String = "res://Data/Units/infantry_trained.tres"
const VETERAN_PATH: String = "res://Data/Units/infantry_veteran.tres"
const UnitVisualScript = preload("res://Scripts/Systems/Combat/unit_visual.gd")
const HumanVisualScript = preload("res://Scripts/Systems/Combat/human_visual.gd")

var _failed: bool = false
var _context: WorldContext = null


func _ready() -> void:
	_run()
	_cleanup()
	if _failed:
		push_error("[family] 测试失败")
		get_tree().quit(1)
	else:
		print("[family] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)

	_context = WorldContext.new()
	_context.name = "FamilyAppearanceTestContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return

	_test_family_configs()
	_test_named_villages()
	_test_family_parties()
	_test_player_leader()
	_test_appearance_rules()
	_test_family_visuals()
	_test_tabard_probabilities()
	_test_serialization_roundtrip()
	_test_old_save_defaults()
	_test_unified_world_map_speed()


func _test_family_configs() -> void:
	_check(_context.family_registry.get_all_configs().size() == 18, "注册十八个家族")
	var bari := _context.family_registry.get_config(WorldInitializer.FAMILY_BARI_ID)
	var moxixi := _context.family_registry.get_config(
		WorldInitializer.FAMILY_MOXIXI_ID
	)
	_check(bari != null and not bari.banner_texture_path.is_empty(),
		"巴里家族配置包含旗帜")
	_check(moxixi != null and not moxixi.tabard_primary_texture_path.is_empty(),
		"墨西西家族配置包含主罩袍")
	_check(_context.appearance_config != null, "加载外观随机池配置")
	if _context.appearance_config == null:
		return
	_check(
		_context.appearance_config.tier1_helmet_texture_paths.size() == 1
			and _context.appearance_config.tier2_helmet_texture_paths.size() == 5
			and _context.appearance_config.tier3_helmet_texture_paths.size() == 5,
		"头盔池按 1/2/3 级分别配置"
	)


func _test_named_villages() -> void:
	var bari := _find_settlement("巴里")
	var moxixi := _find_settlement("墨西西")
	_check(bari != null and bari.family_id == WorldInitializer.FAMILY_BARI_ID,
		"巴里地点属于巴里家族")
	_check(moxixi != null and moxixi.family_id == WorldInitializer.FAMILY_MOXIXI_ID,
		"墨西西地点属于墨西西家族")
	_check(_find_settlement("橡木村") == null, "旧村庄名已替换")
	_check(_find_settlement("河畔村") == null, "旧河畔村名已替换")


func _test_family_parties() -> void:
	for entry: Array in [
		[WorldInitializer.BARI_KNIGHT_PARTY_NAME, WorldInitializer.BARI_LORD_NAME],
		[WorldInitializer.MOXIXI_KNIGHT_PARTY_NAME, WorldInitializer.MOXIXI_LORD_NAME],
	]:
		var party_name: String = entry[0]
		var leader_name: String = entry[1]
		var party := _find_party(party_name)
		_check(party != null, "创建家族骑士部队：%s" % party_name)
		if party == null:
			continue
		_check(party.member_unit_ids.size() == 10, "家族骑士人数为 10")
		_check(not party.family_id.is_empty(), "家族骑士记录 family_id")
		_check(not party.leader_unit_id.is_empty(), "家族骑士记录领袖 unit_id")
		_check(party.ai_type == PartyData.PartyAIType.PATROL,
			"家族骑士由 AIManager 巡逻控制")
		_check(party.ai_patrol_points.size() == 4, "家族骑士拥有独立巡逻路线")

		var leader := _context.party_manager.get_leader_unit(party.party_id)
		_check(leader != null, "家族领袖是部队成员")
		if leader != null:
			_check(leader.display_name == leader_name, "领袖名称正确")
			_check(leader.family_id == party.family_id, "领袖记录家族")
			_check(leader.is_mounted, "家族领袖骑乘")
			_check(_config_tier(leader) == 3, "家族领袖为三级兵种")
			_check(leader.appearance.get("tabard_variant", "") == "PRIMARY",
				"领袖始终使用主罩袍")
			_check(
				not str(leader.appearance.get("plume_texture_path", "")).is_empty(),
				"只有领袖拥有家族缨饰"
			)

		var tier3: int = 0
		var tier2: int = 0
		var tier1: int = 0
		var mounted: int = 0
		for unit: UnitData in _context.party_manager.get_units_of_party(party.party_id):
			match _config_tier(unit):
				1:
					tier1 += 1
				2:
					tier2 += 1
				3:
					tier3 += 1
			if unit.is_mounted:
				mounted += 1
			_check(unit.family_id == party.family_id, "成员记录家族")
			_check(not unit.appearance.is_empty(), "成员外观已一次性生成")
			_check(
				not str(unit.appearance.get("helmet_texture_path", "")).is_empty(),
				"成员拥有等级头盔"
			)
			_check(
				str(unit.appearance.get("spear_texture_path", "")).ends_with(
					"长矛.png"
				),
				"成员使用家族长矛表现"
			)
			if unit.unit_id != party.leader_unit_id:
				_check(
					str(unit.appearance.get("plume_texture_path", "")).is_empty(),
					"非领袖不显示家族缨饰"
				)
		_check(tier3 == 2, "编制：2 名三级（领袖 + 骑乘侍从）")
		_check(tier2 == 5, "编制：5 名二级")
		_check(tier1 == 3, "编制：3 名一级")
		_check(mounted == 5, "编制：5 名骑乘单位")


func _test_player_leader() -> void:
	var player_party := _context.get_player_party()
	var leader := _context.party_manager.get_leader_unit(player_party.party_id)
	_check(leader != null and leader.is_player_character,
		"玩家部队领袖是玩家角色")
	_check(
		leader != null and player_party.leader_unit_id == leader.unit_id,
		"玩家身份与部队领袖字段分离但指向正确"
	)
	# 当前控制权仍是运行时概念，数据层不因“领袖”自动改变控制标记。
	_check(leader != null and not leader.appearance.is_empty(),
		"玩家角色同样获得一次性外观")
	_check(leader != null and not leader.is_mounted, "玩家角色初始不骑乘")


func _test_appearance_rules() -> void:
	var family := _context.family_registry.get_config(WorldInitializer.FAMILY_BARI_ID)
	var tier1_config := load(MILITIA_PATH) as UnitConfig
	var tier2_config := load(TRAINED_PATH) as UnitConfig
	var tier3_config := load(VETERAN_PATH) as UnitConfig
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261121

	for pair: Array in [
		[tier1_config, 1],
		[tier2_config, 2],
		[tier3_config, 3],
	]:
		var unit_config := pair[0] as UnitConfig
		var tier := int(pair[1])
		var unit := UnitData.new()
		UnitAppearance.ensure_random(
			unit, unit_config, family, _context.appearance_config, false, rng
		)
		var helmet: String = str(unit.appearance.get("helmet_texture_path", ""))
		_check(
			_context.appearance_config.get_helmet_texture_paths(tier).has(helmet),
			"%d 级兵使用对应等级头盔池" % tier
		)
		_check(unit.family_id == WorldInitializer.FAMILY_BARI_ID,
			"外观生成同时写入家族 ID")

	# 已生成的外观不会被刷新重随机。
	var fixed_unit := UnitData.new()
	UnitAppearance.ensure_random(
		fixed_unit, tier2_config, family, _context.appearance_config, false, rng
	)
	fixed_unit.appearance["helmet_texture_path"] = "sentinel_helmet.png"
	UnitAppearance.ensure_random(
		fixed_unit, tier2_config, family, _context.appearance_config, false, rng
	)
	_check(
		fixed_unit.appearance.get("helmet_texture_path") == "sentinel_helmet.png",
		"外观一次性生成，不因刷新重随机"
	)

	# 未配置副罩袍时回退主罩袍。
	var primary_only := FamilyConfig.new()
	primary_only.family_id = "FAMILY_TEST"
	primary_only.display_name = "测试家族"
	primary_only.tabard_primary_texture_path = "primary.png"
	var fallback_unit := UnitData.new()
	UnitAppearance.ensure_random(
		fallback_unit, tier1_config, primary_only,
		_context.appearance_config, false, rng
	)
	_check(
		fallback_unit.appearance.get("tabard_variant") == "PRIMARY"
			and fallback_unit.appearance.get("tabard_texture_path") == "primary.png",
		"缺少副罩袍时使用主罩袍"
	)


func _test_family_visuals() -> void:
	var party := _find_party(WorldInitializer.BARI_KNIGHT_PARTY_NAME)
	if party == null:
		return
	var leader := _context.party_manager.get_leader_unit(party.party_id)
	if leader == null:
		return

	var visual = UnitVisualScript.new()
	add_child(visual)
	visual.setup(leader)
	var tabard := visual.get_part("Tabard") as Sprite2D
	_check(
		tabard != null and tabard.texture != null
			and tabard.texture.resource_path.ends_with("巴里风格罩袍_主.png"),
		"家族领袖使用主罩袍贴图"
	)
	_check(visual.has_part("Plume"), "家族领袖显示家族缨饰")
	var helmet := visual.get_part("Helmet") as Sprite2D
	_check(
		helmet != null and helmet.texture != null
			and helmet.texture.resource_path.contains("头盔_3级"),
		"三级领袖使用三级头盔贴图"
	)
	var weapon := visual.get_part("Weapon") as Sprite2D
	_check(
		weapon != null and weapon.texture != null
			and weapon.texture.resource_path.ends_with("巴里风格长矛.png"),
		"无武器装备时使用家族长矛表现"
	)

	# 装备 HEAD 时优先级高于随机外观头盔。
	var equipment_before: Dictionary = leader.equipment.duplicate(true)
	leader.equipment["HEAD"] = "test_head"
	var head_config := EquipmentConfig.new()
	head_config.equipment_id = "test_head"
	head_config.slot = EquipmentConfig.Slot.HEAD
	head_config.visual_texture_path = HumanVisualScript.HEAD_PATH
	visual.set_equipment_configs({"HEAD": head_config})
	helmet = visual.get_part("Helmet") as Sprite2D
	_check(
		helmet != null and helmet.texture != null
			and helmet.texture.resource_path == HumanVisualScript.HEAD_PATH,
		"装备头盔优先于外观随机头盔"
	)
	leader.equipment = equipment_before
	visual.setup(leader)
	visual.queue_free()


func _test_tabard_probabilities() -> void:
	var family := _context.family_registry.get_config(WorldInitializer.FAMILY_BARI_ID)
	var militia := load(MILITIA_PATH) as UnitConfig
	var trained := load(TRAINED_PATH) as UnitConfig
	var veteran := load(VETERAN_PATH) as UnitConfig
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242

	var tier1_primary: int = _count_primary(
		family, militia, 400, false, rng
	)
	var tier2_primary: int = _count_primary(
		family, trained, 400, false, rng
	)
	var tier3_primary: int = _count_primary(
		family, veteran, 400, false, rng
	)
	_check(tier1_primary >= 50 and tier1_primary <= 110,
		"一级兵主罩袍概率约 20%%（实际 %d/400）" % tier1_primary)
	_check(tier2_primary >= 150 and tier2_primary <= 250,
		"二级兵主罩袍概率约 50%%（实际 %d/400）" % tier2_primary)
	_check(tier3_primary == 400, "三级兵始终使用主罩袍")
	_check(_count_primary(family, militia, 100, true, rng) == 100,
		"领袖始终使用主罩袍")


func _count_primary(
	family: FamilyConfig,
	unit_config: UnitConfig,
	count: int,
	is_leader: bool,
	rng: RandomNumberGenerator
) -> int:
	var primary: int = 0
	for i: int in range(count):
		var unit := UnitData.new()
		UnitAppearance.ensure_random(
			unit, unit_config, family, _context.appearance_config, is_leader, rng
		)
		if unit.appearance.get("tabard_variant") == "PRIMARY":
			primary += 1
	return primary


func _test_serialization_roundtrip() -> void:
	var party := _find_party(WorldInitializer.MOXIXI_KNIGHT_PARTY_NAME)
	if party == null:
		_check(false, "序列化测试找不到家族部队")
		return
	var leader := _context.party_manager.get_leader_unit(party.party_id)
	if leader == null:
		_check(false, "序列化测试找不到领袖")
		return
	var party_payload := party.to_dict()
	var restored_party := PartyData.from_dict(party_payload)
	_check(restored_party.family_id == party.family_id, "部队家族 ID 可持久化")
	_check(restored_party.leader_unit_id == party.leader_unit_id,
		"部队领袖关系可持久化")
	_check(restored_party.ai_patrol_points == party.ai_patrol_points,
		"专属巡逻点可持久化")

	var unit_payload := leader.to_dict()
	var restored_unit := UnitData.from_dict(unit_payload)
	_check(restored_unit.family_id == leader.family_id, "单位家族 ID 可持久化")
	_check(restored_unit.appearance == leader.appearance, "外观选择可持久化")

	# 完整世界读档不重复生成新部队，并恢复领袖与外观。
	var save := _context.to_save_data()
	var loaded := WorldContext.new()
	loaded.name = "FamilyReloadContext"
	add_child(loaded)
	_check(loaded.load_from_save_data(save), "完整存档可恢复")
	_check(
		loaded.party_manager.get_all_parties().size()
		== _context.party_manager.get_all_parties().size(),
		"读档不重复生成新家族/强盗部队"
	)
	var loaded_party := _find_party_in(loaded, WorldInitializer.MOXIXI_KNIGHT_PARTY_NAME)
	_check(loaded_party != null and loaded_party.member_unit_ids.size() == 10,
		"读档后家族部队人数保持 10")
	if loaded_party != null:
		var loaded_leader := loaded.party_manager.get_leader_unit(loaded_party.party_id)
		_check(
			loaded_leader != null and loaded_leader.appearance == leader.appearance,
			"读档后领袖外观选择恢复"
		)
	loaded.queue_free()


func _test_old_save_defaults() -> void:
	var old_unit := UnitData.from_dict({"unit_id": "U1", "config_id": "infantry_militia"})
	_check(old_unit.family_id.is_empty() and old_unit.appearance.is_empty(),
		"旧存档单位缺失家族/外观时使用安全默认值")
	var old_party := PartyData.from_dict({"party_id": "P1", "party_name": "旧部队"})
	_check(old_party.family_id.is_empty() and old_party.leader_unit_id.is_empty(),
		"旧存档部队缺失家族/领袖时使用安全默认值")
	_check(old_party.ai_patrol_points.is_empty(), "旧存档缺失专属巡逻点时为空")
	var old_settlement := SettlementData.from_dict({"settlement_id": "S1"})
	_check(old_settlement.family_id.is_empty(), "旧存档地点缺失家族时为空")


func _test_unified_world_map_speed() -> void:
	var player := _context.get_player_party()
	var unit_before := _context.party_manager.get_units_of_party(
		player.party_id
	)[0]
	var unit_speed_before := unit_before.move_speed
	player.world_position = Vector2(900.0, 900.0)
	player.target_position = player.world_position + Vector2(200.0, 0.0)
	player.movement_state = PartyData.MovementState.MOVING
	player.current_order = PartyData.OrderType.MOVE
	_context.world_map_manager.update_party_movement(1.0)
	_check(
		is_equal_approx(player.world_position.x, 900.0 + player.movement_speed * 0.08),
		"大地图实际移动速度统一为数据速度的 0.08 倍"
	)
	_check(
		is_equal_approx(player.movement_speed, WorldInitializer.PLAYER_MOVE_SPEED),
		"不直接改写 PartyData.movement_speed，避免重复减半"
	)
	_check(
		is_equal_approx(unit_before.move_speed, unit_speed_before),
		"小地图/战斗单位移动速度不受大地图倍率影响"
	)


func _config_tier(unit: UnitData) -> int:
	var config := _context.unit_manager.get_unit_config(unit.config_id)
	return config.tier if config != null else 0


func _find_party(party_name: String) -> PartyData:
	return _find_party_in(_context, party_name)


func _find_party_in(context: WorldContext, party_name: String) -> PartyData:
	for party: PartyData in context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _find_settlement(display_name: String) -> SettlementData:
	for settlement: SettlementData in _context.settlement_manager.get_all_settlements():
		if settlement.display_name == display_name:
			return settlement
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[family] OK: %s" % message)
	else:
		_failed = true
		push_error("[family] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_context):
		_context.queue_free()
