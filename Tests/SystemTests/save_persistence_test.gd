extends Node
## 阶段 6 存档完整性测试。
## 覆盖：世界/时间/地点/部队/士兵/经济/世界日志往返；战后存活部队状态；
## 读档清理失效战斗状态；领袖与成员关系校验。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/save_persistence_test.tscn

const TEST_SLOT: String = "__save_persistence__"
const SAVED_TIME: float = 4321.0
const SAVED_PLAYER_POSITION: Vector2 = Vector2(740.0, 610.0)

var _failed: bool = false


func _ready() -> void:
	await _run()
	SaveManager.delete_save(TEST_SLOT)
	if _failed:
		push_error("[save] 测试失败")
		get_tree().quit(1)
	else:
		print("[save] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.restore_world_time(SAVED_TIME, TimeManager.SPEED_DOUBLE)

	var context := WorldContext.new()
	context.name = "SavePersistenceContext"
	add_child(context)
	_check(WorldInitializer.create_new_world(context), "初始化世界")
	if not context.is_valid_world():
		return
	_check(SaveData.CURRENT_SCHEMA_VERSION == 3, "存档 Schema 版本为 3")

	var player := context.get_player_party()
	var bandit := _find_party_by_ai(context, PartyData.PartyAIType.BANDIT)
	var merchant := _find_party_by_kind(context, PartyData.PartyKind.MERCHANT)
	_check(player != null and bandit != null and merchant != null, "找到玩家/强盗/商队")
	if player == null or bandit == null or merchant == null:
		return

	# --- 玩家位置、经济与成员变化 ---
	player.world_position = SAVED_PLAYER_POSITION
	player.target_position = SAVED_PLAYER_POSITION
	player.movement_state = PartyData.MovementState.IDLE
	context.player_profile.gold += 321
	_check(context.player_profile.add_item("weapon_sword_01", 2), "玩家获得物品")

	var removed_member_id: String = player.member_unit_ids[0]
	_check(
		context.party_manager.remove_member(player.party_id, removed_member_id),
		"移除一名玩家部队成员"
	)

	var veteran_id: String = player.member_unit_ids[0]
	var veteran := context.unit_manager.get_unit(veteran_id)
	_check(veteran != null, "取得用于成长测试的成员")
	if veteran != null:
		_check(context.unit_manager.add_exp(veteran_id, 250), "成员获得经验")
		_check(veteran.level > 1, "成员升级")
		_check(context.unit_manager.equip_item(veteran_id, "weapon_sword_01"), "成员装备武器")
		veteran.current_hp = maxi(1, veteran.current_hp - 3)

	var saved_merchant_route: Array[String] = merchant.ai_route_settlement_ids.duplicate()
	var saved_merchant_route_index: int = merchant.ai_route_index
	var saved_merchant_banner: String = merchant.banner_texture_path
	var saved_merchant_kind: int = int(merchant.party_kind)
	var saved_merchant_leader: String = merchant.leader_unit_id
	var saved_merchant_position: Vector2 = merchant.world_position

	var family_settlement := _find_family_settlement(context)
	_check(family_settlement != null, "找到带家族的地点")
	var saved_settlement_position: Vector2 = Vector2.ZERO
	var saved_settlement_family: String = ""
	if family_settlement != null:
		saved_settlement_position = family_settlement.world_position
		saved_settlement_family = family_settlement.family_id

	# --- 战后状态：玩家侧伤亡 + 强盗全灭 ---
	var session := context.battle_manager.start_battle(
		[player.party_id],
		[bandit.party_id],
		player.world_position + Vector2(10.0, 0.0),
		true
	)
	_check(session != null, "创建战后存档用的战斗")
	if session == null:
		return
	var player_casualty: String = ""
	var survivor_id: String = ""
	for unit_id: String in session.get_party_unit_ids(player.party_id):
		if unit_id == veteran_id:
			continue
		if player_casualty.is_empty():
			player_casualty = unit_id
		elif survivor_id.is_empty():
			survivor_id = unit_id
	var casualty_state := session.get_unit_state(player_casualty)
	if casualty_state != null:
		casualty_state.battle_hp = 0
		casualty_state.alive = false
	var survivor_state := session.get_unit_state(survivor_id)
	if survivor_state != null:
		survivor_state.battle_hp = 17
	for unit_id: String in session.get_party_unit_ids(bandit.party_id):
		var state := session.get_unit_state(unit_id)
		if state != null:
			state.battle_hp = 0
			state.alive = false
	_check(
		context.battle_manager.finish_battle(
			session.battle_id, BattleSession.BattleResult.ATTACKER_VICTORY
		),
		"战斗结算成功"
	)
	_check(context.battle_manager.current_battle == null, "战斗结束后清理会话")
	_check(
		context.world_log_manager.get_entry_count() > 0,
		"战斗事实写入世界日志"
	)

	var log_count_before_save: int = context.world_log_manager.get_entry_count()
	var player_members_after_battle: int = player.member_unit_ids.size()
	var saved_gold: int = context.player_profile.gold
	var saved_inventory: Array[String] = context.player_profile.inventory.duplicate()
	var saved_counts: Dictionary = context.player_profile.item_counts.duplicate(true)
	var saved_veteran_hp: int = veteran.current_hp if veteran != null else 0
	var saved_veteran_level: int = veteran.level if veteran != null else 0
	var saved_veteran_appearance: Dictionary = (
		veteran.appearance.duplicate(true) if veteran != null else {}
	)

	# --- 保存并读取 ---
	var save := context.to_save_data()
	_check(save.schema_version == int(SaveData.CURRENT_SCHEMA_VERSION), "存档写入当前 Schema")
	_check(
		not (save.world_log.get("entries", []) as Array).is_empty(),
		"存档包含世界日志"
	)
	_check(SaveManager.save_game(TEST_SLOT, save) == OK, "保存成功")
	var loaded := SaveManager.load_game(TEST_SLOT)
	_check(loaded != null, "读取成功")
	if loaded == null:
		return
	_check(loaded.schema_version == 3, "读回的 Schema 为 3")

	var restored := WorldContext.new()
	restored.name = "SavePersistenceRestoredContext"
	add_child(restored)
	_check(restored.load_from_save_data(loaded), "恢复世界")
	if not restored.is_valid_world():
		return

	_check(restored.world_id == context.world_id, "恢复世界 ID")
	_check(restored.world_size == context.world_size, "恢复世界尺寸")
	_check(
		is_equal_approx(TimeManager.world_elapsed_seconds, SAVED_TIME),
		"恢复世界时间"
	)
	_check(
		is_equal_approx(TimeManager.get_base_world_speed(), TimeManager.SPEED_DOUBLE),
		"恢复世界倍率"
	)

	var restored_player := restored.get_player_party()
	_check(restored_player != null, "恢复玩家部队")
	if restored_player != null:
		_check(
			restored_player.world_position == SAVED_PLAYER_POSITION,
			"恢复玩家位置"
		)
		_check(
			restored_player.member_unit_ids.size() == player_members_after_battle,
			"恢复玩家部队成员数量"
		)
		_check(
			not restored_player.member_unit_ids.has(removed_member_id),
			"恢复后仍保持成员移除结果"
		)
		_check(
			restored_player.member_unit_ids.has(survivor_id),
			"战后存活成员保留"
		)
		_check(
			restored_player.leader_unit_id.is_empty()
			or restored_player.member_unit_ids.has(restored_player.leader_unit_id),
			"恢复后玩家领袖属于本部队"
		)
		_check(not restored_player.attack_intent, "读档清除攻击意图")
		_check(restored_player.focus_party_id.is_empty(), "读档清除追击焦点")
		_check(
			restored_player.engagement_cooldown_until == 0.0,
			"战斗冷却不进入存档"
		)

	_check(restored.player_profile.gold == saved_gold, "恢复金币")
	_check(restored.player_profile.inventory == saved_inventory, "恢复物品列表")
	_check(restored.player_profile.item_counts == saved_counts, "恢复物品数量")

	var restored_survivor := restored.unit_manager.get_unit(survivor_id)
	_check(restored_survivor != null, "恢复战后存活单位")
	if restored_survivor != null:
		_check(restored_survivor.current_hp == 17, "恢复战斗剩余 HP")

	var restored_veteran := restored.unit_manager.get_unit(veteran_id)
	_check(restored_veteran != null, "恢复成长成员")
	if restored_veteran != null:
		_check(restored_veteran.level == saved_veteran_level, "恢复成员等级")
		_check(restored_veteran.current_hp == saved_veteran_hp, "恢复成员当前 HP")
		_check(
			restored_veteran.equipment.get("WEAPON", "") == "weapon_sword_01",
			"恢复成员装备"
		)
		_check(
			UnitAppearance.get_texture_path(restored_veteran, "helmet_texture_path")
			== str(saved_veteran_appearance.get("helmet_texture_path", "")),
			"恢复成员头盔外观"
		)
		_check(
			UnitAppearance.get_tabard_variant(restored_veteran)
			== str(saved_veteran_appearance.get("tabard_variant", "")),
			"恢复成员罩袍外观"
		)
		_check(
			UnitAppearance.get_texture_path(restored_veteran, "spear_texture_path")
			== str(saved_veteran_appearance.get("spear_texture_path", "")),
			"恢复成员长矛外观"
		)
		_check(
			int(restored_veteran.appearance.get("version", 0)) == UnitAppearance.VERSION,
			"恢复成员外观版本"
		)

	var restored_merchant := restored.party_manager.get_party(merchant.party_id)
	_check(restored_merchant != null, "恢复商队")
	if restored_merchant != null:
		_check(
			restored_merchant.ai_route_settlement_ids == saved_merchant_route,
			"恢复商队路线"
		)
		_check(
			restored_merchant.ai_route_index == saved_merchant_route_index,
			"恢复商队路线进度"
		)
		_check(restored_merchant.banner_texture_path == saved_merchant_banner, "恢复部队旗帜")
		_check(int(restored_merchant.party_kind) == saved_merchant_kind, "恢复部队类型")
		_check(
			restored_merchant.world_position == saved_merchant_position,
			"恢复 NPC 部队位置"
		)
		_check(
			restored_merchant.leader_unit_id == saved_merchant_leader
			or restored_merchant.member_unit_ids.has(restored_merchant.leader_unit_id),
			"恢复后 NPC 领袖有效"
		)

	var restored_bandit := restored.party_manager.get_party(bandit.party_id)
	_check(restored_bandit != null, "恢复被消灭部队记录")
	if restored_bandit != null:
		_check(
			restored_bandit.battle_state == PartyData.BattleState.DISABLED,
			"全灭部队读档后为 DISABLED"
		)

	for party: PartyData in restored.party_manager.get_all_parties():
		_check(
			party.battle_state != PartyData.BattleState.IN_BATTLE
			and party.battle_state != PartyData.BattleState.RETURNING,
			"读档后部队不处于活动战斗状态: %s" % party.party_id
		)

	_check(
		restored.world_log_manager.get_entry_count() == log_count_before_save,
		"恢复世界日志条目"
	)
	_check(
		restored.world_log_manager.get_entries().back().text
		== context.world_log_manager.get_entries().back().text,
		"恢复最后一条世界日志文本"
	)

	if family_settlement != null:
		var restored_settlement := restored.settlement_manager.get_settlement(
			family_settlement.settlement_id
		)
		_check(restored_settlement != null, "恢复地点")
		if restored_settlement != null:
			_check(
				restored_settlement.world_position == saved_settlement_position,
				"恢复地点位置"
			)
			_check(
				restored_settlement.family_id == saved_settlement_family,
				"恢复地点家族"
			)
			_check(
				restored_settlement.display_name == family_settlement.display_name,
				"恢复地点名称"
			)

	_check_sanitize_invalid_battle_state(loaded)
	_check_leader_validation(loaded, merchant.party_id)

	context.queue_free()
	restored.queue_free()


## 存档中的 IN_BATTLE 与指向不存在部队的追击目标必须在读档时清理。
func _check_sanitize_invalid_battle_state(source: SaveData) -> void:
	var payload := _copy_save(source)
	var party_id: String = source.player_party_id
	var party_payload: Dictionary = (payload.parties[party_id] as Dictionary).duplicate(true)
	party_payload["battle_state"] = int(PartyData.BattleState.IN_BATTLE)
	party_payload["current_order"] = int(PartyData.OrderType.FOLLOW_PARTY)
	party_payload["current_target_id"] = "PARTY_999999"
	party_payload["movement_state"] = int(PartyData.MovementState.MOVING)
	party_payload["target_position"] = [100.0, 200.0]
	payload.parties[party_id] = party_payload

	var context := WorldContext.new()
	context.name = "SaveSanitizeContext"
	add_child(context)
	_check(context.load_from_save_data(payload), "失效战斗状态不阻止读档")
	var party := context.party_manager.get_party(party_id)
	_check(party != null, "恢复被清理的部队")
	if party != null:
		_check(
			party.battle_state == PartyData.BattleState.AVAILABLE,
			"IN_BATTLE 在读档后回落为 AVAILABLE"
		)
		_check(party.current_target_id.is_empty(), "失效追击目标被清除")
		_check(
			party.current_order == PartyData.OrderType.NONE,
			"失效 FOLLOW_PARTY 指令被清除"
		)
		_check(
			party.movement_state == PartyData.MovementState.IDLE,
			"失效追击的移动状态被停止"
		)
	context.queue_free()


## 领袖不属于本部队时拒绝读档，并报告错误。
func _check_leader_validation(source: SaveData, party_id: String) -> void:
	var payload := _copy_save(source)
	var party_payload: Dictionary = (payload.parties[party_id] as Dictionary).duplicate(true)
	party_payload["leader_unit_id"] = "UNIT_999999"
	payload.parties[party_id] = party_payload

	var context := WorldContext.new()
	context.name = "SaveLeaderValidationContext"
	add_child(context)
	_check(
		not context.load_from_save_data(payload),
		"领袖不属于本部队时拒绝读档"
	)
	context.queue_free()


func _copy_save(source: SaveData) -> SaveData:
	var copy := SaveData.new()
	copy.schema_version = source.schema_version
	copy.project_version = source.project_version
	copy.world_id = source.world_id
	copy.world_created_at = source.world_created_at
	copy.world_size = source.world_size
	copy.world_elapsed_seconds = source.world_elapsed_seconds
	copy.world_base_speed = source.world_base_speed
	copy.id_counters = source.id_counters.duplicate(true)
	copy.player_party_id = source.player_party_id
	copy.player = source.player.duplicate(true)
	copy.world_state = source.world_state.duplicate(true)
	copy.scene_state = source.scene_state.duplicate(true)
	copy.world_log = source.world_log.duplicate(true)
	copy.units = source.units.duplicate(true)
	copy.parties = source.parties.duplicate(true)
	copy.lords = source.lords.duplicate(true)
	copy.settlements = source.settlements.duplicate(true)
	copy.factions = source.factions.duplicate(true)
	copy.quests = source.quests.duplicate(true)
	return copy


func _find_party_by_ai(context: WorldContext, ai_type: PartyData.PartyAIType) -> PartyData:
	for party: PartyData in context.party_manager.get_all_parties():
		if party.ai_type == ai_type:
			return party
	return null


func _find_party_by_kind(context: WorldContext, kind: PartyData.PartyKind) -> PartyData:
	for party: PartyData in context.party_manager.get_all_parties():
		if party.party_kind == kind:
			return party
	return null


func _find_family_settlement(context: WorldContext) -> SettlementData:
	for settlement: SettlementData in context.settlement_manager.get_all_settlements():
		if not settlement.family_id.is_empty():
			return settlement
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[save] OK: %s" % message)
	else:
		_failed = true
		push_error("[save] FAIL: %s" % message)
