class_name AIManager
extends RefCounted
## AI 决策调度器。
##
## 三层决策频率：
## - 单位实时行为：小场景物理帧，由 UnitController/UnitAI 自行处理；
## - 部队战术决策：每个 PARTY_DECISION_INTERVAL 世界秒；
## - 领主战略决策：每个 LORD_DECISION_INTERVAL 世界秒。
##
## 部队层行为：
## - TRADE_ROUTE：按 stable settlement_id 往返；
## - PATROL：固定巡逻点循环；
## - BANDIT：视野内寻找敌对目标并追击，找不到时沿路线游荡；
## - GUARD：优先拦截威胁友军（商队）的强盗，其次处理视野内强盗，否则巡逻。
##
## 敌对判断只来自 FactionManager，目标发现只来自 VisionManager；
## 决策只通过 WorldMapManager 下达目标，不直接修改位置。

const PARTY_DECISION_INTERVAL: float = 1.0
const LORD_DECISION_INTERVAL: float = 30.0

## 到达判定容差。WorldMapManager 到达时会把位置精确设为目标点。
const AI_ARRIVAL_RADIUS: float = 4.0
## 发现离屏战斗后开始接近的范围。
const BATTLE_APPROACH_RADIUS: float = 700.0
## 已经看见战场并开始接近后，失去视野仍保持目标的时间（世界秒）。
## 防止部队在“发现/失去视野”之间每个决策周期来回抖动。
const BATTLE_RESPONSE_HOLD_SECONDS: float = 15.0
## 补给采购失败或暂时没有目标后的重试间隔，避免每 tick 扫描所有地点。
const SUPPLY_RETRY_SECONDS: float = 20.0

## 强盗目标评分：最终评分 = 基础优先级分 - 距离 × 权重。
const BANDIT_TARGET_SCORE_MERCHANT: float = 300.0
const BANDIT_TARGET_SCORE_GUARD: float = 200.0
const BANDIT_TARGET_SCORE_PLAYER: float = 100.0
const BANDIT_TARGET_SCORE_OTHER: float = 50.0
const BANDIT_TARGET_DISTANCE_WEIGHT: float = 0.1
## 新目标至少高出该分数才主动切换，避免在相近目标间反复横跳。
const BANDIT_TARGET_SWITCH_MARGIN: float = 30.0

## 北境巡逻队的固定巡逻点，按数组顺序循环。
const PATROL_POINTS: Array[Vector2] = [
	Vector2(2200.0, 500.0),
	Vector2(2600.0, 900.0),
	Vector2(2400.0, 1500.0),
	Vector2(1900.0, 1200.0),
]

var player_party_id: String = ""

var _unit_manager: UnitManager = null
var _party_manager: PartyManager = null
var _world_map_manager: WorldMapManager = null
var _settlement_manager: SettlementManager = null
var _faction_manager: FactionManager = null
var _vision_manager: VisionManager = null
var _battle_manager: BattleManager = null
var _lord_manager: LordManager = null
var _fief_recruitment_manager: FiefRecruitmentManager = null
## NPC 领主在自有村庄招募普通冒险者的统一业务入口（与玩家共用同一管理器）。
var _adventurer_recruitment_manager: AdventurerRecruitmentManager = null
var _economy_config: SettlementEconomyConfig = null
## 阶段 12：补给需求查询与市场采购都走既有统一系统，AI 只负责决策与移动。
var _supply_manager: SupplyManager = null
var _market_manager: MarketManager = null
var _party_timer: float = 0.0
var _lord_timer: float = 0.0


func setup(
	unit_manager: UnitManager,
	party_manager: PartyManager,
	world_map_manager: WorldMapManager,
	settlement_manager: SettlementManager,
	faction_manager: FactionManager = null,
	vision_manager: VisionManager = null,
	battle_manager: BattleManager = null,
	lord_manager: LordManager = null,
	fief_recruitment_manager: FiefRecruitmentManager = null,
	economy_config: SettlementEconomyConfig = null,
	supply_manager: SupplyManager = null,
	market_manager: MarketManager = null,
	adventurer_recruitment_manager: AdventurerRecruitmentManager = null
) -> void:
	_unit_manager = unit_manager
	_party_manager = party_manager
	_world_map_manager = world_map_manager
	_settlement_manager = settlement_manager
	_faction_manager = faction_manager
	_vision_manager = vision_manager
	_battle_manager = battle_manager
	_lord_manager = lord_manager
	_fief_recruitment_manager = fief_recruitment_manager
	_economy_config = economy_config if economy_config != null \
		else SettlementEconomyConfig.new()
	_economy_config.sanitize()
	_supply_manager = supply_manager
	_market_manager = market_manager
	_adventurer_recruitment_manager = adventurer_recruitment_manager


func tick(world_delta: float) -> void:
	if _party_manager == null:
		return

	_party_timer += world_delta
	_lord_timer += world_delta

	if _party_timer >= PARTY_DECISION_INTERVAL:
		# 不补跑错过的时间桶，避免卡顿后集中决策。
		_party_timer = fmod(_party_timer, PARTY_DECISION_INTERVAL)
		_tick_party_tactical()

	if _lord_timer >= LORD_DECISION_INTERVAL:
		_lord_timer = fmod(_lord_timer, LORD_DECISION_INTERVAL)
		_tick_lord_strategic()


func _tick_party_tactical() -> void:
	if _party_manager == null or _world_map_manager == null:
		return

	for party: PartyData in _party_manager.get_all_parties():
		# 玩家控制权由 PartyData.control_type 表达；player_party_id 保留为旧数据回退。
		if party == null or party.is_player_controlled() \
				or party.party_id == player_party_id:
			continue
		if not party.is_available_for_world():
			continue
		# 领主正在执行封地征召时，普通巡逻/路线 AI 不得覆盖移动目标。
		if _is_lord_recruiting(party.party_id):
			continue
		# 补给采购是普通行为：战斗中/追击中不触发，也不会覆盖封地征召。
		if _try_handle_supply_purchase(party):
			continue

		match party.ai_type:
			PartyData.PartyAIType.TRADE_ROUTE:
				if party.movement_state == PartyData.MovementState.MOVING:
					continue
				_update_trade_route_party(party)
			PartyData.PartyAIType.PATROL:
				if party.movement_state == PartyData.MovementState.MOVING:
					continue
				_update_patrol_party(party)
			PartyData.PartyAIType.BANDIT:
				_update_bandit_party(party)
			PartyData.PartyAIType.GUARD:
				_update_guard_party(party)
			_:
				pass


# ---------------------------------------------------------------------------
# 敌对 AI
# ---------------------------------------------------------------------------


func _update_bandit_party(party: PartyData) -> void:
	# 刚结束战斗：先脱离接触并恢复游荡，不立即追回同一目标。
	if _is_in_post_battle_cooldown(party):
		_clear_battle_response(party)
		party.attack_intent = false
		party.current_target_id = ""
		_update_bandit_route(party)
		return
	# 附近有可加入的战斗时优先响应，再考虑自己的追击目标。
	if _try_respond_to_battle(party):
		_clear_chase_intent(party)
		return

	var had_target: bool = not party.current_target_id.is_empty()
	var current_target := _resolve_chase_target(party)
	var best_target := _select_bandit_target(party)
	var target := _choose_bandit_target(party, current_target, best_target)

	if target != null:
		_chase_target(party, target)
		return

	party.attack_intent = false
	if had_target:
		# 刚失去目标：立即覆盖旧的追击移动。
		_update_bandit_route(party)
	elif party.movement_state != PartyData.MovementState.MOVING:
		_update_bandit_route(party)


func _update_guard_party(party: PartyData) -> void:
	# 刚结束战斗：先脱离接触并恢复巡逻，不立即追回同一目标。
	if _is_in_post_battle_cooldown(party):
		_clear_battle_response(party)
		party.attack_intent = false
		party.current_target_id = ""
		_update_patrol_party(party)
		return
	if _try_respond_to_battle(party):
		_clear_chase_intent(party)
		return

	var had_target: bool = not party.current_target_id.is_empty()
	var target := _find_bandit_threatening_friendly(party)
	if target == null:
		target = _resolve_chase_target(party)
	if target == null and _vision_manager != null:
		target = _vision_manager.get_nearest_visible_hostile(party.party_id)

	if target != null:
		_chase_target(party, target)
		return

	party.attack_intent = false
	if had_target:
		_update_patrol_party(party)
	elif party.movement_state != PartyData.MovementState.MOVING:
		_update_patrol_party(party)


## 目标离开视野、被删除或进入战斗后清除追击目标。
func _resolve_chase_target(party: PartyData) -> PartyData:
	if _vision_manager == null or party.current_target_id.is_empty():
		return null
	var target := _party_manager.get_party(party.current_target_id)
	if target == null or not _vision_manager.can_see(party.party_id, target.party_id):
		party.current_target_id = ""
		party.attack_intent = false
		return null
	return target


func _select_bandit_target(party: PartyData) -> PartyData:
	if _vision_manager == null:
		return null
	var candidates := _vision_manager.get_visible_hostile_parties(party.party_id)
	var best: PartyData = null
	var best_score: float = -INF
	for candidate: PartyData in candidates:
		var score := _score_bandit_target(party, candidate)
		if score > best_score:
			best_score = score
			best = candidate
	return best


## 结合类型优先级与距离评分；分差不足切换阈值时保留当前目标。
func _choose_bandit_target(
	party: PartyData, current_target: PartyData, best_target: PartyData
) -> PartyData:
	if best_target == null:
		return null
	if current_target == null or best_target == current_target:
		return best_target
	var current_score := _score_bandit_target(party, current_target)
	var best_score := _score_bandit_target(party, best_target)
	if best_score >= current_score + BANDIT_TARGET_SWITCH_MARGIN:
		return best_target
	return current_target


func _score_bandit_target(party: PartyData, target: PartyData) -> float:
	var base_score: float = BANDIT_TARGET_SCORE_OTHER
	if _faction_manager != null:
		match target.faction_id:
			FactionManager.MERCHANT_FACTION_ID:
				base_score = BANDIT_TARGET_SCORE_MERCHANT
			FactionManager.GUARD_FACTION_ID:
				base_score = BANDIT_TARGET_SCORE_GUARD
			FactionManager.PLAYER_FACTION_ID:
				base_score = BANDIT_TARGET_SCORE_PLAYER
			_:
				base_score = BANDIT_TARGET_SCORE_OTHER
	var distance := party.world_position.distance_to(target.world_position)
	return base_score - distance * BANDIT_TARGET_DISTANCE_WEIGHT


## 治安队优先处理“正在追击友军（商队）”的强盗。
func _find_bandit_threatening_friendly(guard: PartyData) -> PartyData:
	if _vision_manager == null or _faction_manager == null:
		return null
	var hostiles := _vision_manager.get_visible_hostile_parties(guard.party_id)
	var best: PartyData = null
	var best_distance: float = INF
	for hostile: PartyData in hostiles:
		if hostile.current_target_id.is_empty():
			continue
		var victim := _party_manager.get_party(hostile.current_target_id)
		if victim == null or victim.party_id == guard.party_id:
			continue
		if not _faction_manager.is_party_friendly(guard.party_id, victim.party_id):
			continue
		var distance := guard.world_position.distance_to(hostile.world_position)
		if distance < best_distance:
			best_distance = distance
			best = hostile
	return best


## 只负责追击移动与攻击意图；实际遭遇判定由 EncounterManager.update_encounters() 统一处理。
func _chase_target(party: PartyData, target: PartyData) -> void:
	party.current_target_id = target.party_id
	party.attack_intent = true
	_world_map_manager.set_party_target(party.party_id, target.world_position)


## 响应附近正在进行的离屏战斗：只负责发现、判断与接近；
## 实际加入仍由 EncounterManager 与 BattleManager 统一完成。
##
## 关键约束：
## 1. 只能通过 VisionManager 发现参战方，不能仅凭与战场中心距离就“知道”战斗；
## 2. 阵营关系全部交给 BattleManager.get_join_side()，本类不复制关系算法；
## 3. 看见后保持一段时间的接近目标，避免丢失视野时来回抖动。
func _try_respond_to_battle(party: PartyData) -> bool:
	if party == null or _world_map_manager == null:
		return false
	if _is_in_post_battle_cooldown(party):
		_clear_battle_response(party)
		return false
	if _battle_manager == null or _vision_manager == null:
		return false
	# 已参战部队不再响应其他战场。
	if _battle_manager.get_battle_for_party(party.party_id) != null:
		_clear_battle_response(party)
		return false

	var visible_ids: Dictionary = _visible_party_ids_including_battles(party)

	# 已发现并开始接近：在保持时间内即使暂时看不见也继续前往。
	if not party.battle_response_id.is_empty():
		var held := _battle_manager.get_battle(party.battle_response_id)
		if held != null and held.offscreen \
				and _battle_manager.get_join_side(party.party_id, held.battle_id) >= 0:
			if _battle_has_visible_participant(held, visible_ids):
				party.battle_response_until = TimeManager.world_elapsed_seconds \
					+ BATTLE_RESPONSE_HOLD_SECONDS
			if party.battle_response_until > TimeManager.world_elapsed_seconds:
				_world_map_manager.set_party_target(party.party_id, held.world_position)
				return true
		_clear_battle_response(party)

	# 新发现：必须实际看见至少一名参战部队。
	var target: BattleSession = null
	var best_distance: float = INF
	for battle: BattleSession in _battle_manager.get_active_battles():
		if not battle.offscreen:
			continue
		if _battle_manager.get_join_side(party.party_id, battle.battle_id) < 0:
			continue
		var distance: float = party.world_position.distance_to(battle.world_position)
		if distance > BATTLE_APPROACH_RADIUS:
			continue
		if not _battle_has_visible_participant(battle, visible_ids):
			continue
		if distance < best_distance:
			best_distance = distance
			target = battle
	if target == null:
		_clear_battle_response(party)
		return false

	party.battle_response_id = target.battle_id
	party.battle_response_until = TimeManager.world_elapsed_seconds \
		+ BATTLE_RESPONSE_HOLD_SECONDS
	_world_map_manager.set_party_target(party.party_id, target.world_position)
	return true


## 视野查询必须包含正在战斗的参战方；否则永远无法“看见战斗”。
func _visible_party_ids_including_battles(party: PartyData) -> Dictionary:
	var ids: Dictionary = {}
	if _vision_manager == null:
		return ids
	for visible: PartyData in _vision_manager.get_visible_parties(party.party_id, true):
		if visible != null:
			ids[visible.party_id] = true
	return ids


func _battle_has_visible_participant(
	battle: BattleSession, visible_ids: Dictionary
) -> bool:
	if battle == null:
		return false
	for party_id: String in battle.get_all_party_ids():
		if visible_ids.has(party_id):
			return true
	return false


## 开始响应战场时清除旧的追击意图，避免“正在追 A 却去战场”的状态冲突。
func _clear_chase_intent(party: PartyData) -> void:
	party.attack_intent = false
	party.current_target_id = ""


func _clear_battle_response(party: PartyData) -> void:
	if party == null:
		return
	party.battle_response_id = ""
	party.battle_response_until = 0.0


# ---------------------------------------------------------------------------
# 补给采购
# ---------------------------------------------------------------------------


## NPC 部队在补给不足时前往最近的村庄/城镇采购。
## 返回 true 表示本 tick 的移动目标已由补给逻辑接管，应跳过普通路线 AI。
## 战斗中、追击中与战后冷却期间不触发，避免打断战斗。
func _try_handle_supply_purchase(party: PartyData) -> bool:
	if _supply_manager == null or _market_manager == null \
			or _world_map_manager == null or party == null:
		return false
	# 强盗没有稳定经济来源，不参与补给采购；其余 NPC 部队与玩家共用规则。
	if party.party_kind == PartyData.PartyKind.BANDIT:
		return false
	if party.member_unit_ids.is_empty():
		return false
	if party.battle_state != PartyData.BattleState.AVAILABLE:
		return false
	if party.attack_intent or not party.battle_response_id.is_empty():
		return false
	if _battle_manager != null \
			and _battle_manager.get_battle_for_party(party.party_id) != null:
		return false
	if _is_in_post_battle_cooldown(party):
		return false
	if party.supply_purchase_retry_after > TimeManager.world_elapsed_seconds:
		return false

	# 只有真正进入低补给（剩余天数 <= LOW_SUPPLY_DAYS）才跑一趟，
	# 采购量再按 7 天储备计算；否则 5~6 天的部队会无谓往返。
	if not _supply_manager.has_low_supply(party):
		_clear_supply_purchase(party)
		return false
	var needs: Dictionary = _supply_manager.get_purchase_needs(party)
	if needs.is_empty():
		_clear_supply_purchase(party)
		return false
	if party.gold <= 0:
		# 没钱时不再每 tick 扫描市场；保留低补给状态供 UI 显示。
		_clear_supply_purchase(party)
		party.supply_purchase_retry_after = TimeManager.world_elapsed_seconds \
			+ SUPPLY_RETRY_SECONDS
		return false

	var target: SettlementData = _resolve_supply_target(party, needs)
	if target == null:
		_clear_supply_purchase(party)
		party.supply_purchase_retry_after = TimeManager.world_elapsed_seconds \
			+ SUPPLY_RETRY_SECONDS
		return false

	party.supply_purchase_active = true
	party.supply_purchase_settlement_id = target.settlement_id
	if party.world_position.distance_to(target.world_position) > AI_ARRIVAL_RADIUS:
		_world_map_manager.set_party_target(party.party_id, target.world_position)
		return true

	# 到达市场：采购一次并结束本次任务；不足的部分留到下次判断。
	_execute_supply_purchase(party, target, needs)
	_clear_supply_purchase(party)
	party.supply_purchase_retry_after = TimeManager.world_elapsed_seconds \
		+ SUPPLY_RETRY_SECONDS
	return true


## 优先保持已选定的采购目标；目标失效或库存耗尽时再找最近的可用村庄/城镇。
func _resolve_supply_target(
	party: PartyData,
	needs: Dictionary
) -> SettlementData:
	if party.supply_purchase_active \
			and not party.supply_purchase_settlement_id.is_empty():
		var kept := _settlement_manager.get_settlement(
			party.supply_purchase_settlement_id
		) if _settlement_manager != null else null
		if kept != null and _can_buy_supply_at(kept, needs, party):
			return kept
	if _settlement_manager == null:
		return null
	var nearest: SettlementData = null
	var nearest_distance: float = INF
	for settlement: SettlementData in _settlement_manager.get_all_settlements():
		if not _can_buy_supply_at(settlement, needs, party):
			continue
		var distance: float = party.world_position.distance_to(
			settlement.world_position
		)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = settlement
	return nearest


## 村庄与城镇都可以补给；城堡永远不在候选列表里。
func _can_buy_supply_at(
	settlement: SettlementData,
	needs: Dictionary,
	party: PartyData
) -> bool:
	if settlement == null or _market_manager == null:
		return false
	if settlement.settlement_type != SettlementData.SettlementType.VILLAGE \
			and settlement.settlement_type != SettlementData.SettlementType.TOWN:
		return false
	var market := _market_manager.get_market(settlement.settlement_id)
	if market == null:
		return false
	for item_id_value: Variant in needs:
		var item_id: String = str(item_id_value)
		var config := _market_manager.get_goods_config(item_id)
		if config == null or not config.can_buy():
			continue
		if not config.is_available_at(settlement.settlement_type):
			continue
		if market.get_stock(item_id) <= 0:
			continue
		if config.buy_price > party.gold:
			continue
		return true
	return false


## 按“剩余天数更少”的优先级购买，最多补到 SupplyManager 给出的目标储备。
## 采购只通过 MarketManager.execute_npc_trade，不写玩家世界日志。
func _execute_supply_purchase(
	party: PartyData,
	settlement: SettlementData,
	needs: Dictionary
) -> bool:
	var market := _market_manager.get_market(settlement.settlement_id)
	if market == null:
		return false
	var status: Dictionary = _supply_manager.get_status(party)
	var item_ids: Array[String] = []
	for key: Variant in needs:
		item_ids.append(str(key))
	item_ids.sort_custom(func(a: String, b: String) -> bool:
		return _supply_days(status, a) < _supply_days(status, b)
	)

	var purchases: Dictionary = {}
	var remaining_gold: int = party.gold
	for item_id: String in item_ids:
		var config := _market_manager.get_goods_config(item_id)
		if config == null or not config.can_buy() \
				or not config.is_available_at(settlement.settlement_type):
			continue
		if config.buy_price <= 0:
			continue
		var affordable: int = int(
			floor(float(remaining_gold) / float(config.buy_price))
		)
		var quantity: int = mini(
			int(needs[item_id]),
			mini(market.get_stock(item_id), affordable)
		)
		if quantity <= 0:
			continue
		purchases[item_id] = quantity
		remaining_gold -= quantity * config.buy_price
	if purchases.is_empty():
		return false

	var result: Dictionary = _market_manager.execute_npc_trade(
		settlement.settlement_id,
		purchases,
		{},
		party,
		"npc_supply_%s_%d" % [party.party_id, Time.get_ticks_usec()]
	)
	if not bool(result.get("success", false)):
		return false
	var bread_bought: int = int(purchases.get(SupplyManager.BREAD_ID, 0))
	var fodder_bought: int = int(purchases.get(SupplyManager.FODDER_ID, 0))
	EventBus.npc_supply_purchased.emit(
		party.party_id, bread_bought, fodder_bought
	)
	return true


func _supply_days(status: Dictionary, item_id: String) -> float:
	if item_id == SupplyManager.BREAD_ID:
		return float(status.get("food_days_remaining", SupplyManager.NO_CONSUMPTION_DAYS))
	if item_id == SupplyManager.FODDER_ID:
		return float(status.get("fodder_days_remaining", SupplyManager.NO_CONSUMPTION_DAYS))
	return SupplyManager.NO_CONSUMPTION_DAYS


func _clear_supply_purchase(party: PartyData) -> void:
	if party == null:
		return
	party.supply_purchase_active = false
	party.supply_purchase_settlement_id = ""


# ---------------------------------------------------------------------------
# 路线行为
# ---------------------------------------------------------------------------


func _update_trade_route_party(party: PartyData) -> void:
	if _settlement_manager == null or party.ai_route_settlement_ids.size() < 2:
		return

	var route_size: int = party.ai_route_settlement_ids.size()
	var index: int = _wrapped_index(party.ai_route_index, route_size)
	if party.ai_route_index != index:
		party.ai_route_index = index

	var target := _settlement_manager.get_settlement(
		party.ai_route_settlement_ids[index]
	)
	if target == null:
		push_warning(
			"商队路线地点不存在: %s（部队 %s）"
			% [party.ai_route_settlement_ids[index], party.party_id]
		)
		return

	if party.world_position.distance_to(target.world_position) <= AI_ARRIVAL_RADIUS:
		index = (index + 1) % route_size
		party.ai_route_index = index
		target = _settlement_manager.get_settlement(
			party.ai_route_settlement_ids[index]
		)
		if target == null:
			push_warning(
				"商队路线地点不存在: %s（部队 %s）"
				% [party.ai_route_settlement_ids[index], party.party_id]
			)
			return

	_world_map_manager.set_party_target(party.party_id, target.world_position)


func _update_bandit_route(party: PartyData) -> void:
	# 强盗没有独立营地系统，复用已有的路线地点数据作为游荡区域。
	_update_trade_route_party(party)


func _update_patrol_party(party: PartyData) -> void:
	# 家族骑士与治安队等巡逻部队同样可以通过视野发现战场并前往协助。
	if _try_respond_to_battle(party):
		_clear_chase_intent(party)
		return
	# 部队可以携带自己的巡逻路线（家族骑士、特殊守卫）；
	# 没有专属路线时继续使用全局默认巡逻点。
	var points: Array[Vector2] = (
		party.ai_patrol_points if not party.ai_patrol_points.is_empty()
		else PATROL_POINTS
	)
	var route_size: int = points.size()
	if route_size == 0:
		return

	var index: int = _wrapped_index(party.ai_route_index, route_size)
	if party.ai_route_index != index:
		party.ai_route_index = index

	var target: Vector2 = points[index]
	if party.world_position.distance_to(target) <= AI_ARRIVAL_RADIUS:
		index = (index + 1) % route_size
		party.ai_route_index = index
		target = points[index]

	_world_map_manager.set_party_target(party.party_id, target)


## 领主战略层：人数低于阈值时，优先前往自己的封地征召一组采邑；
## 封地没有储备时，退而前往自有村庄招募普通冒险者。
## 普通巡逻/路线 AI 在 current_state == RECRUITING 期间被跳过，避免覆盖目标。
func _tick_lord_strategic() -> void:
	if _lord_manager == null or _party_manager == null \
			or _world_map_manager == null or _settlement_manager == null:
		return
	if _fief_recruitment_manager == null \
			and _adventurer_recruitment_manager == null:
		return

	for lord: LordData in _lord_manager.get_all_lords():
		if lord == null or not lord.is_alive or lord.is_player_lord:
			continue
		var party := _party_manager.get_party(lord.party_id)
		if party == null or not party.is_available_for_world():
			continue

		if party.member_unit_ids.size() >= _economy_config.ai_lord_recruit_threshold:
			_clear_lord_recruit_state(lord)
			continue

		var target: SettlementData = _find_owned_recruit_settlement(lord, party)
		if target != null:
			_advance_lord_recruit(lord, party, target, "FIEF_RECRUIT")
			continue

		var adventurer_target: SettlementData = \
			_find_owned_adventurer_settlement(lord, party)
		if adventurer_target == null:
			_clear_lord_recruit_state(lord)
			continue
		_advance_lord_recruit(
			lord, party, adventurer_target, "ADVENTURER_RECRUIT"
		)


## 推进一次领主征召目标：先记录状态并移动；到达后只尝试一次，
## 成功/失败都退出征召状态，恢复普通 AI。
func _advance_lord_recruit(
	lord: LordData,
	party: PartyData,
	target: SettlementData,
	goal: String
) -> void:
	lord.current_state = "RECRUITING"
	lord.current_goal = goal
	lord.current_target_settlement_id = target.settlement_id

	if party.world_position.distance_to(target.world_position) > AI_ARRIVAL_RADIUS:
		_world_map_manager.set_party_target(party.party_id, target.world_position)
		return

	if goal == "FIEF_RECRUIT":
		if _fief_recruitment_manager != null:
			_fief_recruitment_manager.recruit_group(
				target.settlement_id, lord.lord_id
			)
	elif _adventurer_recruitment_manager != null:
		_adventurer_recruitment_manager.recruit_normal_candidates_for_party(
			target.settlement_id, party.party_id, lord.lord_id
		)
	_clear_lord_recruit_state(lord)


func _find_owned_recruit_settlement(
	lord: LordData, party: PartyData
) -> SettlementData:
	if _settlement_manager == null or _fief_recruitment_manager == null:
		return null
	var nearest: SettlementData = null
	var nearest_distance: float = INF
	for settlement: SettlementData in _settlement_manager.get_all_settlements():
		if settlement == null \
				or settlement.settlement_type != SettlementData.SettlementType.VILLAGE:
			continue
		if settlement.owner_lord_id != lord.lord_id:
			continue
		if settlement.fief_recruitment_stock <= 0:
			continue
		var distance := party.world_position.distance_to(settlement.world_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = settlement
	return nearest


## 自有村庄中仍有普通冒险者候选人、且部队至少付得起一名招募费用的最近村庄。
## 所有权复用封地系统的统一授权规则，不按场景进入状态或名字推断。
func _find_owned_adventurer_settlement(
	lord: LordData, party: PartyData
) -> SettlementData:
	if _settlement_manager == null or _adventurer_recruitment_manager == null:
		return null
	if _economy_config == null \
			or not party.can_afford(_economy_config.adventurer_recruit_cost):
		return null
	var nearest: SettlementData = null
	var nearest_distance: float = INF
	for settlement: SettlementData in _settlement_manager.get_all_settlements():
		if settlement == null \
				or settlement.settlement_type != SettlementData.SettlementType.VILLAGE:
			continue
		if not _is_lord_authorized_owner(settlement, lord):
			continue
		if not _has_available_normal_candidate(settlement):
			continue
		var distance := party.world_position.distance_to(settlement.world_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = settlement
	return nearest


func _is_lord_authorized_owner(settlement: SettlementData, lord: LordData) -> bool:
	if _fief_recruitment_manager != null:
		return _fief_recruitment_manager.is_authorized_owner(
			settlement, lord.lord_id
		)
	return settlement.owner_lord_id == lord.lord_id


func _has_available_normal_candidate(settlement: SettlementData) -> bool:
	for candidate: AdventurerCandidateData in settlement.get_available_candidates():
		if candidate != null and not candidate.is_noble:
			return true
	return false


func _clear_lord_recruit_state(lord: LordData) -> void:
	if lord == null:
		return
	if lord.current_state == "RECRUITING" \
			or lord.current_goal == "FIEF_RECRUIT" \
			or lord.current_goal == "ADVENTURER_RECRUIT":
		lord.current_state = "IDLE"
		lord.current_goal = ""
		lord.current_target_settlement_id = ""


func _is_lord_recruiting(party_id: String) -> bool:
	if _lord_manager == null or party_id.is_empty():
		return false
	var lord: LordData = _lord_manager.get_lord_by_party_id(party_id)
	return lord != null and lord.current_state == "RECRUITING"


func _wrapped_index(index: int, size: int) -> int:
	return ((index % size) + size) % size


## 战斗刚结束时，存活部队在短时间内不得重新追击/参战。
func _is_in_post_battle_cooldown(party: PartyData) -> bool:
	if party == null:
		return false
	return party.engagement_cooldown_until > TimeManager.world_elapsed_seconds
