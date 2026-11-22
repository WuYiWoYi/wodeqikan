class_name WorldSimulation
extends RefCounted
## 世界模拟调度器：只消费 TimeManager 的固定步长 tick，按固定顺序推进数据。
##
## 本类不依赖场景节点，因此大地图场景未加载时世界仍然可以运行。

var _unit_manager: UnitManager = null
var _party_manager: PartyManager = null
var _world_map_manager: WorldMapManager = null
var _ai_manager: AIManager = null
var _battle_manager: BattleManager = null
var _encounter_manager: EncounterManager = null
var _fief_recruitment_manager: FiefRecruitmentManager = null
var _adventurer_recruitment_manager: AdventurerRecruitmentManager = null
## 阶段 12：每日补给消耗必须由统一的 SupplyManager 在 WorldTime 日边界结算。
var _supply_manager: SupplyManager = null


func bind(
	unit_manager: UnitManager,
	party_manager: PartyManager,
	world_map_manager: WorldMapManager,
	ai_manager: AIManager,
	battle_manager: BattleManager = null,
	encounter_manager: EncounterManager = null,
	fief_recruitment_manager: FiefRecruitmentManager = null,
	adventurer_recruitment_manager: AdventurerRecruitmentManager = null,
	supply_manager: SupplyManager = null
) -> void:
	_unit_manager = unit_manager
	_party_manager = party_manager
	_world_map_manager = world_map_manager
	_ai_manager = ai_manager
	_battle_manager = battle_manager
	_encounter_manager = encounter_manager
	_fief_recruitment_manager = fief_recruitment_manager
	_adventurer_recruitment_manager = adventurer_recruitment_manager
	_supply_manager = supply_manager


func on_world_tick(fixed_delta: float) -> void:
	if _party_manager == null or _world_map_manager == null or _ai_manager == null:
		return

	# 离屏战斗计时：世界保持运行，允许第三方接近并中途加入。
	if _battle_manager != null:
		_battle_manager.tick(fixed_delta)

	# 固定顺序：移动 -> 视野/遭遇 -> AI 决策 -> 地点模拟（阶段 5 接入）。
	_world_map_manager.update_party_movement(fixed_delta)
	_world_map_manager.update_visibility()

	# 封地经济与候选人刷新只依赖 WorldTime；遭遇弹窗期间暂停时不会推进。
	if _fief_recruitment_manager != null:
		_fief_recruitment_manager.tick(fixed_delta)
	if _adventurer_recruitment_manager != null:
		_adventurer_recruitment_manager.tick(fixed_delta)

	# 补给只在 WorldTime 跨日时结算；暂停不调用 tick，2 倍速也只会按日推进。
	# 放在 AI 之前，保证 NPC 决策看到的是当天结算后的补给状态。
	if _supply_manager != null:
		_supply_manager.update_daily()

	if _encounter_manager != null:
		_encounter_manager.update_encounters()
		_encounter_manager.update_player_battle_interaction()
		# 玩家遭遇/中途参战交互已触发时，本 tick 不再执行 AI。
		if _encounter_manager.has_pending_player_encounter() \
				or _encounter_manager.has_pending_battle_interaction():
			return
	_ai_manager.tick(fixed_delta)
