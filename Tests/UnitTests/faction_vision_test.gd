extends Node
## FactionManager 关系与 VisionManager 视野发现测试。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/faction_vision_test.tscn

const MILITIA_PATH: String = "res://Data/Units/infantry_militia.tres"

var _failed: bool = false
var _units: UnitManager = null
var _parties: PartyManager = null
var _factions: FactionManager = null
var _vision: VisionManager = null
var _militia: UnitConfig = null


func _ready() -> void:
	_run()
	if _failed:
		push_error("[faction] 测试失败")
		get_tree().quit(1)
	else:
		print("[faction] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	_militia = load(MILITIA_PATH) as UnitConfig
	_check(_militia != null, "加载民兵配置")
	if _militia == null:
		return

	var ids := IdGenerator.new()
	_units = UnitManager.new()
	_units.setup(ids)
	_parties = PartyManager.new()
	_parties.setup(_units, ids)
	_factions = FactionManager.new()
	_factions.setup_defaults(_parties)
	_vision = VisionManager.new()
	_vision.setup(_parties, _factions, _units)

	_test_relations()
	_test_visibility()


func _test_relations() -> void:
	_check(
		_factions.get_relation(
			FactionManager.PLAYER_FACTION_ID, FactionManager.MERCHANT_FACTION_ID
		) == FactionManager.Relation.NEUTRAL,
		"玩家-商队为中立"
	)
	_check(
		_factions.get_relation(
			FactionManager.PLAYER_FACTION_ID, FactionManager.BANDIT_FACTION_ID
		) == FactionManager.Relation.HOSTILE,
		"玩家-强盗为敌对"
	)
	_check(
		_factions.get_relation(
			FactionManager.PLAYER_FACTION_ID, FactionManager.GUARD_FACTION_ID
		) == FactionManager.Relation.NEUTRAL,
		"玩家-治安队为中立"
	)
	_check(
		_factions.get_relation(
			FactionManager.MERCHANT_FACTION_ID, FactionManager.GUARD_FACTION_ID
		) == FactionManager.Relation.FRIENDLY,
		"商队-治安队为友好"
	)
	_check(
		_factions.is_hostile(
			FactionManager.MERCHANT_FACTION_ID, FactionManager.BANDIT_FACTION_ID
		),
		"商队-强盗为敌对"
	)
	_check(
		_factions.is_hostile(
			FactionManager.BANDIT_FACTION_ID, FactionManager.GUARD_FACTION_ID
		),
		"强盗-治安队为敌对"
	)
	_check(
		_factions.is_hostile(
			FactionManager.GUARD_FACTION_ID, FactionManager.BANDIT_FACTION_ID
		),
		"阵营关系对称"
	)
	_check(
		_factions.is_friendly(
			FactionManager.BANDIT_FACTION_ID, FactionManager.BANDIT_FACTION_ID
		),
		"同阵营为友好"
	)
	_check(
		_factions.is_neutral("FACTION_UNKNOWN_A", "FACTION_UNKNOWN_B"),
		"未知阵营默认中立"
	)
	_check(
		_factions.get_display_name(FactionManager.BANDIT_FACTION_ID) == "强盗",
		"阵营显示名正确"
	)


func _test_visibility() -> void:
	var player := _make_party(
		FactionManager.PLAYER_FACTION_ID, Vector2(100.0, 100.0), "玩家", 300.0
	)
	var merchant := _make_party(
		FactionManager.MERCHANT_FACTION_ID, Vector2(300.0, 100.0), "商队", 200.0
	)
	var bandit := _make_party(
		FactionManager.BANDIT_FACTION_ID, Vector2(200.0, 100.0), "强盗", 200.0
	)
	var guard := _make_party(
		FactionManager.GUARD_FACTION_ID, Vector2(200.0, 250.0), "治安队", 200.0
	)
	var far_bandit := _make_party(
		FactionManager.BANDIT_FACTION_ID, Vector2(1000.0, 1000.0), "远方强盗", 200.0
	)

	var visible := _vision.get_visible_parties(player.party_id)
	_check(visible.size() == 3, "视野内发现 3 支部队")
	_check(not visible.has(player), "视野不包含自身")
	_check(not visible.has(far_bandit), "视野外部队不可见")
	_check(_vision.can_see(player.party_id, merchant.party_id), "商队可见")
	_check(not _vision.can_see(player.party_id, far_bandit.party_id), "远方强盗不可见")

	var hostiles := _vision.get_visible_hostile_parties(player.party_id)
	_check(hostiles.size() == 1 and hostiles[0] == bandit, "敌对目标筛选正确")
	var neutrals := _vision.get_visible_neutral_parties(player.party_id)
	_check(neutrals.size() == 2, "中立目标筛选正确")
	var friendlies := _vision.get_visible_friendly_parties(merchant.party_id)
	_check(friendlies.size() == 1 and friendlies[0] == guard, "友方目标筛选正确")
	_check(
		_vision.get_nearest_visible_hostile(player.party_id) == bandit,
		"最近敌对目标正确"
	)

	# 目标离开视野。
	bandit.world_position = Vector2(500.0, 100.0)
	_check(not _vision.can_see(player.party_id, bandit.party_id), "离开视野后不可见")
	_check(
		_vision.get_visible_hostile_parties(player.party_id).is_empty(),
		"离开视野后敌对列表为空"
	)

	# 失效观察者不主动发现目标。
	player.battle_state = PartyData.BattleState.DISABLED
	_check(_vision.get_visible_parties(player.party_id).is_empty(), "失效部队不能发现目标")
	player.battle_state = PartyData.BattleState.AVAILABLE

	# 失效目标与空部队不可被发现。
	merchant.battle_state = PartyData.BattleState.IN_BATTLE
	_check(not _vision.can_see(player.party_id, merchant.party_id), "战斗中的部队不可发现")
	merchant.battle_state = PartyData.BattleState.AVAILABLE
	guard.member_unit_ids.clear()
	_check(not _vision.can_see(player.party_id, guard.party_id), "空部队不可被发现")


func _make_party(
	faction_id: String, position: Vector2, party_name: String, sight: float
) -> PartyData:
	var party := _parties.create_party(faction_id, position, party_name)
	party.sight_range = sight
	var unit := _units.create_unit(_militia, faction_id)
	_parties.add_member(party.party_id, unit.unit_id)
	return party


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[faction] OK: %s" % message)
	else:
		_failed = true
		push_error("[faction] FAIL: %s" % message)
