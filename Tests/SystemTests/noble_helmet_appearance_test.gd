extends Node
## 贵族文化专属头盔测试。
## 覆盖：多拉曼贵族使用专属头盔且隐藏缨饰、国王盔优先、其他文化贵族不受影响、
##        多拉曼普通士兵不命中贵族规则、2 级头盔池不再包含/生成样式 5、
##        覆盖只影响表现层，不改写外观或装备数据。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://Tests/SystemTests/noble_helmet_appearance_test.tscn

const UnitVisualScript = preload("res://Scripts/Systems/Combat/unit_visual.gd")
const DORAMAN_HELMET_PATH: String = \
	"res://art/正式人物美术/头盔美术/头盔_3级_多拉曼盔.png"
const TIER2_STYLE5_SUFFIX: String = "头盔_2级_样式5.png"

var _failed: bool = false
var _context: WorldContext = null


func _ready() -> void:
	_run()
	_cleanup()
	if _failed:
		push_error("[noble_helmet] 测试失败")
		get_tree().quit(1)
	else:
		print("[noble_helmet] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_PAUSED)

	_context = WorldContext.new()
	_context.name = "NobleHelmetTestContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")
	if not _context.is_valid_world():
		return

	_test_tier2_pool()
	_test_doraman_noble()
	_test_non_doraman_noble()
	_test_doraman_soldier()
	_test_player_noble()
	_test_king_precedence()


## 2 级样式 5 只从随机池移除，不删除资源文件。
func _test_tier2_pool() -> void:
	var pool: Array[String] = _context.appearance_config.tier2_helmet_texture_paths
	_check(pool.size() == 4, "2 级头盔池保留 4 个有效样式")
	var has_style5: bool = false
	for path: String in pool:
		if path.ends_with(TIER2_STYLE5_SUFFIX):
			has_style5 = true
	_check(not has_style5, "2 级头盔池不再包含样式 5")

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261127
	var generated_style5: bool = false
	var generated_outside_pool: bool = false
	for i: int in range(500):
		var path: String = _context.appearance_config.pick_helmet_texture_path(2, rng)
		if path.ends_with(TIER2_STYLE5_SUFFIX):
			generated_style5 = true
		if not pool.has(path):
			generated_outside_pool = true
	_check(not generated_style5, "500 次随机均不再生成 2 级样式 5")
	_check(not generated_outside_pool, "随机结果只来自当前有效样式池")


## 多拉曼贵族：伯克纳王国的附庸巴里家族领袖。
func _test_doraman_noble() -> void:
	var party := _find_party(WorldInitializer.BARI_KNIGHT_PARTY_NAME)
	var noble_unit := _leader_unit(party)
	_check(noble_unit != null, "找到多拉曼贵族单位")
	if noble_unit == null:
		return

	var appearance_before: Dictionary = noble_unit.appearance.duplicate(true)
	var equipment_before: Dictionary = noble_unit.equipment.duplicate(true)
	var visual = _make_visual(noble_unit)
	_check(
		_helmet_resource_path(visual) == DORAMAN_HELMET_PATH,
		"多拉曼贵族使用 3 级多拉曼盔"
	)
	_check(not visual.has_part("Plume"), "多拉曼贵族不再显示原头盔缨饰")
	_check(
		not str(noble_unit.appearance.get("helmet_texture_path", "")).ends_with(
			"多拉曼盔.png"
		),
		"专属头盔没有写入 appearance"
	)
	_check(noble_unit.appearance == appearance_before, "多拉曼贵族外观数据未被改写")
	_check(noble_unit.equipment == equipment_before, "多拉曼贵族装备数据未被改写")

	# 朝向只翻转表现节点，不切换或丢失专属头盔贴图。
	visual.set_facing(1.0)
	_check(_helmet_resource_path(visual) == DORAMAN_HELMET_PATH,
		"向右朝向仍使用多拉曼盔")
	visual.set_facing(-1.0)
	_check(_helmet_resource_path(visual) == DORAMAN_HELMET_PATH,
		"向左朝向仍使用多拉曼盔")
	_free_visual(visual)


## 其他文化贵族保持原规则：洛里斯（墨西西）与布吉多（丁达尼）各取一名附庸领袖。
## 不使用各王国统治家族，避免国王盔优先干扰文化头盔断言。
func _test_non_doraman_noble() -> void:
	for entry: Array in [
		[WorldInitializer.MOXIXI_KNIGHT_PARTY_NAME, "洛里斯"],
		["丁达尼骑士", "布吉多"],
	]:
		var party_name: String = entry[0]
		var culture_name: String = entry[1]
		var noble_unit := _leader_unit(_find_party(party_name))
		_check(noble_unit != null, "找到%s贵族单位" % culture_name)
		if noble_unit == null:
			continue

		var visual = _make_visual(noble_unit)
		var helmet_path: String = _helmet_resource_path(visual)
		_check(
			helmet_path != DORAMAN_HELMET_PATH and helmet_path.contains("头盔_3级"),
			"%s贵族仍使用普通 3 级头盔" % culture_name
		)
		_check(visual.has_part("Plume"), "%s贵族保留原头盔缨饰" % culture_name)
		_free_visual(visual)


## 多拉曼普通士兵（同部队三级骑乘侍从）不受贵族规则影响。
func _test_doraman_soldier() -> void:
	var party := _find_party(WorldInitializer.BURKNANIA_KNIGHT_PARTY_NAME)
	_check(party != null, "找到伯克纳家族部队")
	if party == null:
		return
	var soldier: UnitData = null
	for unit_id: String in party.member_unit_ids:
		var unit := _context.unit_manager.get_unit(unit_id)
		if unit == null or unit.unit_id == party.leader_unit_id:
			continue
		if not unit.noble_id.is_empty():
			continue
		if _unit_tier(unit) == 3:
			soldier = unit
			break
	_check(soldier != null, "找到多拉曼三级普通士兵")
	if soldier == null:
		return
	var visual = _make_visual(soldier)
	_check(
		_helmet_resource_path(visual) != DORAMAN_HELMET_PATH,
		"多拉曼普通士兵不显示贵族专属头盔"
	)
	_check(soldier.noble_id.is_empty(), "普通士兵没有贵族身份")
	_free_visual(visual)


## 玩家默认身份（埃克托家族次子）是多拉曼贵族，同样使用专属头盔。
func _test_player_noble() -> void:
	var player_party := _context.get_player_party()
	var player_unit := _leader_unit(player_party)
	_check(player_unit != null and player_unit.is_player_character,
		"找到玩家角色")
	if player_unit == null:
		return
	_check(
		_context.get_noble_culture_id(player_unit) == "CULTURE_DORAMAN",
		"玩家贵族文化来自身份选择"
	)
	var visual = _make_visual(player_unit)
	_check(
		_helmet_resource_path(visual) == DORAMAN_HELMET_PATH,
		"多拉曼玩家贵族使用多拉曼盔"
	)
	_check(not visual.has_part("Plume"), "多拉曼玩家贵族不显示缨饰")
	_free_visual(visual)


## 国王身份优先于文化贵族盔；隐藏国王身份后回退到多拉曼盔。
func _test_king_precedence() -> void:
	var party := _find_party(WorldInitializer.BURKNANIA_KNIGHT_PARTY_NAME)
	var king_unit := _leader_unit(party)
	_check(king_unit != null, "找到国王单位")
	if king_unit == null:
		return
	var visual = _make_visual(king_unit)
	_check(
		_helmet_resource_path(visual).ends_with("国王盔.png"),
		"多拉曼出身的国王仍优先显示国王盔"
	)
	_check(not visual.has_part("Plume"), "国王盔显示期间隐藏缨饰")

	var noble := _context.noble_manager.get_noble(king_unit.noble_id)
	if noble != null:
		noble.is_king = false
		visual.rebuild()
		_check(
			_helmet_resource_path(visual) == DORAMAN_HELMET_PATH,
			"失去国王身份后回退为多拉曼贵族盔"
		)
		noble.is_king = true
		visual.rebuild()
		_check(
			_helmet_resource_path(visual).ends_with("国王盔.png"),
			"恢复国王身份后重新显示国王盔"
		)
	_free_visual(visual)


func _leader_unit(party: PartyData) -> UnitData:
	if party == null:
		return null
	return _context.party_manager.get_leader_unit(party.party_id)


func _unit_tier(unit: UnitData) -> int:
	var config := _context.unit_manager.get_unit_config(unit.config_id)
	return config.tier if config != null else 0


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
		print("[noble_helmet] OK: %s" % message)
	else:
		_failed = true
		push_error("[noble_helmet] FAIL: %s" % message)


func _cleanup() -> void:
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_context):
		_context.queue_free()
