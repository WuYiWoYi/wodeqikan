extends Node
## 统一大地图部队架构测试。
## 覆盖：所有部队共用 PartyData 基础字段、类型/控制权区分、领袖数据、
## 存档往返、旧存档缺失新字段时的安全默认值与类型推断。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/party_architecture_test.tscn

var _failed: bool = false


func _ready() -> void:
	_run()
	if _failed:
		push_error("[partyarch] 测试失败")
		get_tree().quit(1)
	else:
		print("[partyarch] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	var context := WorldContext.new()
	context.name = "PartyArchitectureContext"
	add_child(context)
	_check(WorldInitializer.create_new_world(context), "初始化世界")
	if not context.is_valid_world():
		return

	var player := context.get_player_party()
	var merchant := _find_party(context, WorldInitializer.TEST_ENEMY_PARTY_NAME)
	var guard := _find_party(context, WorldInitializer.GUARD_PARTY_NAME)
	var bandit := _find_party(context, WorldInitializer.BANDIT_PARTY_NAME)
	var knights := _find_party(context, WorldInitializer.BARI_KNIGHT_PARTY_NAME)
	_check(
		player != null and merchant != null and guard != null
		and bandit != null and knights != null,
		"玩家/商队/治安队/强盗/家族部队均存在"
	)
	if player == null or merchant == null or guard == null \
			or bandit == null or knights == null:
		return

	_check_unified_party(context, player, "玩家部队")
	_check_unified_party(context, merchant, "商队")
	_check_unified_party(context, guard, "治安队")
	_check_unified_party(context, bandit, "强盗")
	_check_unified_party(context, knights, "家族部队")

	_check(
		player.control_type == PartyData.ControlType.PLAYER
		and player.party_kind == PartyData.PartyKind.PLAYER,
		"玩家部队使用 PLAYER 控制类型与类型标识"
	)
	_check(
		merchant.control_type == PartyData.ControlType.AI
		and merchant.party_kind == PartyData.PartyKind.MERCHANT,
		"商队使用统一 Party 结构 + AI 控制"
	)
	_check(
		bandit.party_kind == PartyData.PartyKind.BANDIT,
		"强盗通过 party_kind 区分行为配置"
	)
	_check(
		knights.party_kind == PartyData.PartyKind.FAMILY
		and not knights.family_id.is_empty(),
		"家族部队同时拥有家族归属，结构与其他部队一致"
	)
	_check(
		knights.family_id == WorldInitializer.FAMILY_BARI_ID
		and knights.faction_id == WorldInitializer.LOCAL_FACTION_ID,
		"同一支部队同时拥有家族归属与阵营归属，两者字段独立"
	)

	# 序列化往返：新增字段不丢失。
	var payload: Dictionary = bandit.to_dict()
	var restored_bandit := PartyData.from_dict(payload)
	_check(restored_bandit.party_kind == PartyData.PartyKind.BANDIT,
		"往返后保留部队类型")
	_check(restored_bandit.control_type == PartyData.ControlType.AI,
		"往返后保留控制类型")
	_check(restored_bandit.leader_unit_id == bandit.leader_unit_id,
		"往返后保留领袖 ID")
	_check(restored_bandit.faction_id == bandit.faction_id
		and restored_bandit.family_id == bandit.family_id,
		"往返后保留阵营与家族归属")
	_check(restored_bandit.banner_texture_path == bandit.banner_texture_path,
		"往返后保留部队旗帜路径")

	# 旧存档缺失新字段：使用安全默认值，再按现有数据推断。
	var legacy_payload: Dictionary = payload.duplicate(true)
	legacy_payload.erase("control_type")
	legacy_payload.erase("party_kind")
	legacy_payload.erase("banner_texture_path")
	var legacy_bandit := PartyData.from_dict(legacy_payload)
	_check(legacy_bandit.control_type == PartyData.ControlType.AI,
		"旧存档控制类型默认为 AI")
	_check(legacy_bandit.party_kind == PartyData.PartyKind.GENERIC,
		"旧存档部队类型默认为 GENERIC")
	_check(legacy_bandit.banner_texture_path.is_empty(),
		"旧存档旗帜路径默认为空")
	legacy_bandit.apply_runtime_defaults(player.party_id)
	_check(legacy_bandit.party_kind == PartyData.PartyKind.BANDIT,
		"旧存档按阵营推断为强盗部队")

	var legacy_player := PartyData.from_dict(player.to_dict().duplicate(true))
	legacy_player.control_type = PartyData.ControlType.AI
	legacy_player.party_kind = PartyData.PartyKind.GENERIC
	legacy_player.apply_runtime_defaults(player.party_id)
	_check(
		legacy_player.control_type == PartyData.ControlType.PLAYER
		and legacy_player.party_kind == PartyData.PartyKind.PLAYER,
		"旧存档按 player_party_id 恢复玩家控制权"
	)

	# 完整读档：删除旧存档中的新字段后，位置/成员/领袖保持不变。
	var save := context.to_save_data()
	var bandit_saved: Dictionary = (save.parties[bandit.party_id] as Dictionary).duplicate(true)
	bandit_saved.erase("control_type")
	bandit_saved.erase("party_kind")
	bandit_saved.erase("banner_texture_path")
	save.parties[bandit.party_id] = bandit_saved
	var player_saved: Dictionary = (save.parties[player.party_id] as Dictionary).duplicate(true)
	player_saved.erase("control_type")
	player_saved.erase("party_kind")
	save.parties[player.party_id] = player_saved

	var loaded := WorldContext.new()
	loaded.name = "PartyArchitectureLoadedContext"
	add_child(loaded)
	_check(loaded.load_from_save_data(save), "旧存档格式仍可加载")
	var loaded_bandit := loaded.party_manager.get_party(bandit.party_id)
	var loaded_player := loaded.party_manager.get_party(player.party_id)
	_check(loaded_bandit != null and loaded_player != null, "读档后部队存在")
	if loaded_bandit != null and loaded_player != null:
		_check(loaded_bandit.party_kind == PartyData.PartyKind.BANDIT,
			"读档后补齐强盗类型")
		_check(loaded_bandit.control_type == PartyData.ControlType.AI,
			"读档后非玩家部队控制类型为 AI")
		_check(loaded_bandit.world_position == bandit.world_position,
			"读档不重置部队位置")
		_check(loaded_bandit.member_unit_ids == bandit.member_unit_ids,
			"读档不重置部队成员")
		_check(loaded_bandit.leader_unit_id == bandit.leader_unit_id,
			"读档保留领袖关系")
		_check(loaded_player.control_type == PartyData.ControlType.PLAYER,
			"读档恢复玩家控制类型")
		_check(loaded_player.party_kind == PartyData.PartyKind.PLAYER,
			"读档恢复玩家部队类型")

	context.queue_free()
	loaded.queue_free()


func _check_unified_party(context: WorldContext, party: PartyData, label: String) -> void:
	_check(not party.party_id.is_empty(), "%s 拥有独立 Party ID" % label)
	_check(not party.member_unit_ids.is_empty(), "%s 拥有成员 Unit ID 列表" % label)
	_check(party.movement_speed > 0.0, "%s 拥有移动速度" % label)
	_check(not party.faction_id.is_empty(), "%s 拥有阵营 ID" % label)
	_check(not party.leader_unit_id.is_empty(), "%s 拥有领袖 Unit ID" % label)
	var leader := context.party_manager.get_leader_unit(party.party_id)
	_check(leader != null, "%s 的领袖可在 PartyManager 中解析" % label)
	_check(party.member_unit_ids.has(party.leader_unit_id),
		"%s 的领袖属于该部队成员" % label)
	_check(party.battle_state == PartyData.BattleState.AVAILABLE,
		"%s 使用统一的部队状态字段" % label)
	_check(party.movement_state == PartyData.MovementState.IDLE
		and party.target_position == party.world_position,
		"%s 使用统一的目标/路线字段" % label)


func _find_party(context: WorldContext, party_name: String) -> PartyData:
	for party: PartyData in context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[partyarch] OK: %s" % message)
	else:
		_failed = true
		push_error("[partyarch] FAIL: %s" % message)
