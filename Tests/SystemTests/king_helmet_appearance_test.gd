extends Node
## 国王身份头盔外观测试。
## 覆盖：统治家族领袖显示国王盔、普通贵族/同家族成员不受影响、
##        家族领袖更替与王国失效后外观恢复、身份覆盖不写入装备/外观数据、
##        没有普通头盔时不会凭空添加国王盔。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/king_helmet_appearance_test.tscn

const UnitVisualScript = preload("res://Scripts/Systems/Combat/unit_visual.gd")
const KING_HELMET_PATH: String = \
	"res://art/正式人物美术/头盔美术/头盔_特殊_国王盔.png"

var _failed: bool = false
var _context: WorldContext = null


func _ready() -> void:
	_run()
	_cleanup()
	if _failed:
		push_error("[king_helmet] 测试失败")
		get_tree().quit(1)
	else:
		print("[king_helmet] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)

	_context = WorldContext.new()
	_context.name = "KingHelmetTestContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return

	# 新世界每个家族只有一名领袖：统治家族“伯克纳骑士”由国王指挥；
	# 巴里骑士是同王国的附庸贵族，可用来模拟统治家族更替。
	var king_party := _find_party(WorldInitializer.BURKNANIA_KNIGHT_PARTY_NAME)
	var lord_party := _find_party(WorldInitializer.BARI_KNIGHT_PARTY_NAME)
	var king_unit := (
		_context.party_manager.get_leader_unit(king_party.party_id)
		if king_party != null else null
	)
	var lord_unit := (
		_context.party_manager.get_leader_unit(lord_party.party_id)
		if lord_party != null else null
	)
	_check(
		king_unit != null and lord_unit != null,
		"找到国王与附庸贵族单位"
	)
	if king_unit == null or lord_unit == null:
		return

	_test_initial_display(king_unit, lord_unit)
	_test_identity_changes(king_unit)
	_test_kingdom_and_ruling_house_changes(king_unit, lord_unit)
	_test_no_helmet_no_override(king_unit)


func _test_initial_display(king_unit: UnitData, lord_unit: UnitData) -> void:
	var noble := _context.noble_manager.get_noble(king_unit.noble_id)
	_check(noble != null and noble.is_king, "国王单位关联具有国王身份")
	_check(
		noble != null and noble.house_id == WorldInitializer.HOUSE_BURKNANIA_ID,
		"国王属于统治家族"
	)
	_check(not king_unit.equipment.has("HEAD"), "国王单位默认未装备 HEAD")

	var king_helmet_before: String = str(
		king_unit.appearance.get("helmet_texture_path", "")
	)
	var appearance_before: Dictionary = king_unit.appearance.duplicate(true)
	var equipment_before: Dictionary = king_unit.equipment.duplicate(true)

	_check(
		not str(king_unit.appearance.get("plume_texture_path", "")).is_empty(),
		"国王原本拥有家族领袖缨饰配置"
	)
	var king_visual = _make_visual(king_unit)
	_check(
		_helmet_resource_path(king_visual) == KING_HELMET_PATH,
		"统治家族领袖显示国王盔"
	)
	_check(
		not king_visual.has_part("Plume"),
		"国王盔显示期间隐藏普通头盔缨饰"
	)

	var lord_visual = _make_visual(lord_unit)
	_check(
		_helmet_resource_path(lord_visual) != KING_HELMET_PATH
			and _helmet_resource_path(lord_visual).contains("头盔_3级"),
		"同王国附庸贵族仍使用普通头盔"
	)

	var member_visual = null
	for unit_id: String in _find_party(
		WorldInitializer.BURKNANIA_KNIGHT_PARTY_NAME
	).member_unit_ids:
		if unit_id == king_unit.unit_id:
			continue
		var member := _context.unit_manager.get_unit(unit_id)
		if member != null:
			member_visual = _make_visual(member)
			break
	_check(member_visual != null, "找到国王部队普通成员")
	if member_visual != null:
		_check(
			_helmet_resource_path(member_visual) != KING_HELMET_PATH,
			"同部队普通成员不会错误显示国王盔"
		)

	# 身份覆盖只影响表现，不写入任何持久化数据。
	_check(king_unit.appearance == appearance_before, "国王外观数据未被改写")
	_check(king_unit.equipment == equipment_before, "国王装备数据未被改写")
	_check(
		str(king_unit.appearance.get("helmet_texture_path", ""))
			== king_helmet_before,
		"原头盔外观路径保持不变"
	)
	_check(
		not str(king_unit.appearance.get("helmet_texture_path", ""))
			.ends_with("国王盔.png"),
		"国王盔没有写入 appearance"
	)

	_free_visual(king_visual)
	_free_visual(lord_visual)
	_free_visual(member_visual)


func _test_identity_changes(king_unit: UnitData) -> void:
	var king_visual = _make_visual(king_unit)
	_check(_helmet_resource_path(king_visual) == KING_HELMET_PATH, "更替前国王显示国王盔")

	# 新世界每个家族只有一名领袖；测试临时创建同家族继承人，
	# 只用于验证外观层对领袖更替的响应，不新增继承玩法。
	var original_leader: String = _context.house_manager.get_house(
		WorldInitializer.HOUSE_BURKNANIA_ID
	).leader_noble_id
	var heir := _context.noble_manager.create_noble(
		"伯克纳测试继承人",
		king_unit.faction_id,
		"",
		WorldInitializer.HOUSE_BURKNANIA_ID,
		NobleData.Rank.BARON,
		false,
		false
	)
	_check(heir != null, "创建临时家族继承人")
	if heir == null:
		_free_visual(king_visual)
		return
	var heir_unit := UnitData.new()
	heir_unit.unit_id = "king_heir_unit"
	heir_unit.noble_id = heir.lord_id
	heir_unit.faction_id = king_unit.faction_id
	heir_unit.appearance = king_unit.appearance.duplicate(true)
	var heir_visual = _make_visual(heir_unit)
	_check(
		_helmet_resource_path(heir_visual) != KING_HELMET_PATH,
		"更替前继承人显示普通头盔"
	)

	_check(
		_context.house_manager.set_leader(
			WorldInitializer.HOUSE_BURKNANIA_ID, heir.lord_id
		),
		"模拟统治家族领袖更替"
	)

	# 已存在的表现节点只需重建即可读取最新身份，不需要重新生成单位。
	king_visual.rebuild()
	heir_visual.rebuild()
	_check(
		_helmet_resource_path(king_visual) != KING_HELMET_PATH
			and _helmet_resource_path(king_visual).contains("头盔_3级"),
		"失去国王身份后恢复普通头盔"
	)
	_check(
		king_visual.has_part("Plume"),
		"失去国王身份后恢复原头盔缨饰"
	)
	_check(
		_helmet_resource_path(heir_visual) == KING_HELMET_PATH,
		"新家族领袖自动切换为国王盔"
	)
	_check(
		not heir_visual.has_part("Plume"),
		"新国王盔显示期间不出现普通缨饰"
	)

	# 恢复初始领袖，验证身份可以双向切换。
	_check(
		_context.house_manager.set_leader(
			WorldInitializer.HOUSE_BURKNANIA_ID, original_leader
		),
		"恢复初始家族领袖"
	)
	king_visual.rebuild()
	heir_visual.rebuild()
	_check(_helmet_resource_path(king_visual) == KING_HELMET_PATH, "恢复后国王再次显示国王盔")
	_check(not king_visual.has_part("Plume"), "恢复国王身份后再次隐藏缨饰")
	_check(
		_helmet_resource_path(heir_visual) != KING_HELMET_PATH,
		"恢复后继承人再次显示普通头盔"
	)

	_free_visual(king_visual)
	_free_visual(heir_visual)


func _test_kingdom_and_ruling_house_changes(
	king_unit: UnitData, vassal_unit: UnitData
) -> void:
	var kingdom := _context.kingdom_manager.get_kingdom(
		WorldInitializer.KINGDOM_BURKNANIA_ID
	)
	var house := _context.house_manager.get_house(
		WorldInitializer.HOUSE_BURKNANIA_ID
	)
	_check(kingdom != null and house != null, "找到伯克纳王国与统治家族")
	if kingdom == null or house == null:
		return

	var king_noble := _context.noble_manager.get_noble(king_unit.noble_id)
	var vassal_noble := _context.noble_manager.get_noble(vassal_unit.noble_id)
	_check(king_noble != null and vassal_noble != null, "找到王国与附庸家族领袖身份")
	if king_noble == null or vassal_noble == null:
		return

	var king_visual = _make_visual(king_unit)
	var vassal_visual = _make_visual(vassal_unit)

	var old_ruling_house: String = kingdom.ruling_house_id
	var old_king_id: String = kingdom.king_noble_id
	var old_active: bool = kingdom.is_active

	# 王国失效：原国王立即回退普通头盔。
	kingdom.is_active = false
	king_visual.rebuild()
	_check(
		_helmet_resource_path(king_visual) != KING_HELMET_PATH,
		"王国失效后原国王恢复普通头盔"
	)
	kingdom.is_active = old_active
	king_visual.rebuild()
	_check(_helmet_resource_path(king_visual) == KING_HELMET_PATH, "王国恢复后国王盔重新出现")

	# 模拟统治家族变化：同王国的巴里家族成为统治家族。
	kingdom.ruling_house_id = WorldInitializer.HOUSE_BARI_ID
	kingdom.king_noble_id = vassal_unit.noble_id
	king_noble.is_king = false
	vassal_noble.is_king = true
	king_visual.rebuild()
	vassal_visual.rebuild()
	_check(
		_helmet_resource_path(king_visual) != KING_HELMET_PATH,
		"失去统治家族地位后原领袖不再显示国王盔"
	)
	_check(
		_helmet_resource_path(vassal_visual) == KING_HELMET_PATH,
		"新统治家族领袖切换为国王盔"
	)

	# 恢复真实政治数据，避免测试残留。
	kingdom.ruling_house_id = old_ruling_house
	kingdom.king_noble_id = old_king_id
	kingdom.is_active = old_active
	king_noble.is_king = true
	vassal_noble.is_king = false
	king_visual.rebuild()
	vassal_visual.rebuild()
	_check(
		_helmet_resource_path(king_visual) == KING_HELMET_PATH
			and _helmet_resource_path(vassal_visual) != KING_HELMET_PATH,
		"恢复政治数据后头盔显示正确"
	)

	_free_visual(king_visual)
	_free_visual(vassal_visual)


func _test_no_helmet_no_override(king_unit: UnitData) -> void:
	# 即使身份是国王，没有普通头盔时也不应凭空添加国王盔。
	var bare := UnitData.new()
	bare.unit_id = "king_without_helmet"
	bare.noble_id = king_unit.noble_id
	bare.faction_id = king_unit.faction_id
	var visual = _make_visual(bare)
	_check(not visual.has_part("Helmet"), "没有普通头盔时不会无条件添加国王盔")
	_free_visual(visual)


func _make_visual(unit: UnitData):
	var visual = UnitVisualScript.new()
	add_child(visual)
	visual.setup(unit)
	return visual


func _helmet_resource_path(visual) -> String:
	var helmet := visual.get_part("Helmet") as Sprite2D
	if helmet == null or helmet.texture == null:
		return ""
	return helmet.texture.resource_path


func _free_visual(visual) -> void:
	if visual != null and is_instance_valid(visual):
		visual.queue_free()


func _find_party(party_name: String) -> PartyData:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party != null and party.party_name == party_name:
			return party
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[king_helmet] OK: %s" % message)
	else:
		_failed = true
		push_error("[king_helmet] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_context):
		_context.queue_free()
