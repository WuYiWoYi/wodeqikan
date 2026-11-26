extends Node
## 玩家可操作角色、WASD 移动、鼠标攻击、控制权转移、观战与战败测试。
## 运行：
##   Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/player_control_test.tscn

const HumanVisualScript = preload(
	"res://Scripts/Systems/Combat/human_visual.gd"
)

var _failed: bool = false
var _context: WorldContext = null
var _scene: BattleScene = null
var _session: BattleSession = null
var _player: PartyData = null
var _enemy: PartyData = null
var _hero_id: String = ""
var _hero: UnitController = null


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		push_error("[playercontrol] 测试失败")
		get_tree().quit(1)
	else:
		print("[playercontrol] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)

	_context = WorldContext.new()
	_context.name = "PlayerControlContext"
	add_child(_context)
	_check(WorldInitializer.create_new_world(_context), "初始化世界")

	_player = _context.get_player_party()
	_enemy = _find_party_by_name(WorldInitializer.BANDIT_PARTY_NAME)
	_check(_player != null and _enemy != null, "玩家与敌人部队存在")
	if _player == null or _enemy == null:
		return
	_check(
		_player.member_unit_ids.size() == WorldInitializer.PLAYER_TOTAL_MEMBER_COUNT,
		"玩家部队保持完整编制"
	)

	for unit_id: String in _player.member_unit_ids:
		var unit := _context.unit_manager.get_unit(unit_id)
		if unit != null and unit.is_player_character:
			_hero_id = unit_id
			break
	_check(not _hero_id.is_empty(), "玩家部队存在玩家角色 Unit")

	GameManager.world_context = _context
	GameManager.player_party_id = _context.player_party_id
	_session = _context.battle_manager.start_battle(
		[_player.party_id], [_enemy.party_id], _enemy.world_position
	)
	_check(_session != null, "创建玩家屏幕战斗")
	if _session == null:
		return

	var packed := load("res://Scenes/Battle/battle.tscn") as PackedScene
	_scene = packed.instantiate() as BattleScene
	add_child(_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame

	_check(_scene.get_controlled_unit_id() == _hero_id, "战斗开始时控制玩家角色")
	_hero = _scene.get_controller(_hero_id)
	_check(_hero != null and _hero.is_player_controlled, "玩家角色进入玩家控制模式")

	await _test_movement()
	_test_attack()
	await _test_control_transfer()
	await _test_spectate_and_defeat()


func _test_movement() -> void:
	var unit := _hero.unit_data
	if unit == null:
		return
	# 直线移动。
	var start := _hero.get_position()
	_scene.set_test_player_input(Vector2(1.0, 0.0))
	for i: int in range(6):
		await get_tree().physics_frame
	_scene.set_test_player_input(Vector2.ZERO, false)
	var straight_end := _hero.get_position()
	_check(straight_end.x > start.x, "D 方向向右移动")
	_check(absf(straight_end.y - start.y) < 1.0, "直线移动不产生纵向漂移")
	var straight_distance := start.distance_to(straight_end)
	var max_distance: float = unit.move_speed * 6.0 / 60.0 + 0.5
	_check(straight_distance <= max_distance, "移动速度不超过 Unit move_speed")

	# 斜向移动归一化。
	var diagonal_start := _hero.get_position()
	_scene.set_test_player_input(Vector2(1.0, 1.0))
	for i: int in range(6):
		await get_tree().physics_frame
	_scene.set_test_player_input(Vector2.ZERO, false)
	var diagonal_end := _hero.get_position()
	var diagonal_distance := diagonal_start.distance_to(diagonal_end)
	_check(
		absf(diagonal_distance - straight_distance) < 1.0,
		"斜向移动速度与直线移动一致（已归一化）"
	)
	_check(
		diagonal_end.x > diagonal_start.x and diagonal_end.y > diagonal_start.y,
		"斜向移动同时改变两个方向"
	)


func _test_attack() -> void:
	var enemies := _scene.get_side_controller_count(_scene.get_player_side())
	_check(enemies > 0, "存在玩家侧单位")
	var enemy_controller: UnitController = null
	for unit_id: String in _session.get_side_unit_ids(1):
		var candidate := _scene.get_controller(unit_id)
		if candidate != null and candidate.is_alive():
			enemy_controller = candidate
			break
	_check(enemy_controller != null, "找到可攻击敌人")
	if enemy_controller == null:
		return

	# 自由攻击：范围内没有敌人（或点击空白）也要完整出手并进入冷却。
	var enemy_hp_before_free: int = enemy_controller.state.battle_hp
	_check(
		_scene.try_player_attack_at(Vector2(100.0, 100.0)),
		"玩家点击空白处仍可主动释放攻击"
	)
	_check(_hero.get_attack_cooldown() > 0.0, "自由攻击进入攻击冷却")
	_check(
		_hero.actor != null and _hero.actor.is_attack_animating(),
		"自由攻击播放完整长矛动画"
	)
	_check(_hero.get_last_attack_target_id().is_empty(), "空挥没有虚构攻击目标")
	_check(
		enemy_controller.state.battle_hp == enemy_hp_before_free,
		"空挥不造成伤害"
	)
	_check(
		not _scene.try_player_attack_at(Vector2(100.0, 100.0)),
		"冷却期间连续点击无效"
	)
	_hero.player_tick(_hero.unit_data.attack_interval + 0.01, Vector2.ZERO)

	enemy_controller.state.battle_position = _hero.get_position() + Vector2(20.0, 0.0)
	var hp_before := enemy_controller.state.battle_hp
	var hero_attack := _hero.unit_data.attack
	var hit := _scene.try_player_attack_at(enemy_controller.get_position())
	_check(hit, "玩家左键攻击命中范围内敌人")
	_check(
		enemy_controller.state.battle_hp == hp_before,
		"攻击前摇/戳击未到有效帧时不提前结算伤害"
	)
	_advance_melee_hit(_hero)
	_check(
		enemy_controller.state.battle_hp == hp_before - hero_attack,
		"玩家攻击使用 Unit 最终攻击力"
	)
	_check(
		_hero.get_last_attack_direction().dot(Vector2.RIGHT) > 0.99,
		"玩家攻击方向来自鼠标世界坐标"
	)
	_check(
		_hero.actor != null and _hero.actor.is_attack_animating(),
		"玩家命中时武器攻击动画同时触发"
	)
	var hp_after_first := enemy_controller.state.battle_hp
	var second_hit := _scene.try_player_attack_at(enemy_controller.get_position())
	_check(not second_hit, "攻击间隔内不能重复攻击")
	_check(enemy_controller.state.battle_hp == hp_after_first, "冷却期间不造成伤害")

	_hero.player_tick(_hero.unit_data.attack_interval + 0.01, Vector2.ZERO)
	var third_hit := _scene.try_player_attack_at(enemy_controller.get_position())
	_check(third_hit, "攻击间隔结束后可以再次攻击")
	_check(
		enemy_controller.state.battle_hp == hp_after_first,
		"第二次攻击在有效帧前不提前扣血"
	)
	_advance_melee_hit(_hero)
	_check(
		enemy_controller.state.battle_hp == hp_after_first - hero_attack,
		"第二次攻击同样使用 Unit 攻击力"
	)

	# 玩家角色也使用普通 Unit 的受伤/HP 规则。
	var hero_hp_before := _hero.state.battle_hp
	_hero.apply_damage(5)
	_check(
		_hero.state.battle_hp == hero_hp_before - 5,
		"玩家角色使用普通 Unit 受伤与 HP 规则"
	)


func _test_control_transfer() -> void:
	_hero.apply_damage(9999)
	await _settle_frames(3)
	var panel := _scene.find_child("ControlTransferPanel", true, false) as PanelContainer
	_check(panel != null and panel.visible, "玩家角色被击败后显示控制权转移面板")
	_check(_scene.is_scene_paused(), "控制权转移期间战斗暂停")
	if panel == null or not panel.visible:
		return

	var ally_id := ""
	for unit_id: String in _player.member_unit_ids:
		if unit_id == _hero_id:
			continue
		var controller := _scene.get_controller(unit_id)
		if controller != null and controller.is_alive():
			ally_id = unit_id
			break
	_check(not ally_id.is_empty(), "存在可接管的存活友军")
	if ally_id.is_empty():
		return

	var button := panel.find_child("TakeControl_%s" % ally_id, true, false) as Button
	_check(button != null, "控制权转移面板包含友军接管按钮")

	var has_mounted_candidate: bool = false
	for candidate: Node in panel.find_children("TakeControl_*", "Button", true, false):
		var candidate_button := candidate as Button
		if candidate_button != null and candidate_button.text.contains("骑乘"):
			has_mounted_candidate = true
	_check(has_mounted_candidate, "控制权转移列表区分骑乘士兵")
	if button == null:
		return
	button.pressed.emit()
	await get_tree().physics_frame
	_check(_scene.get_controlled_unit_id() == ally_id, "接管后切换到新单位")
	_check(not _scene.is_scene_paused(), "接管后恢复战斗")
	var new_controller := _scene.get_controller(ally_id)
	_check(new_controller != null and new_controller.is_player_controlled, "新单位进入玩家控制")
	_check(_count_player_controlled() == 1, "同时只有一个玩家控制单位")

	var before := new_controller.get_position()
	var camera_before_transfer := _scene.get_camera_position()
	_scene.set_test_player_input(Vector2(0.0, 1.0))
	for i: int in range(4):
		await get_tree().physics_frame
	_scene.set_test_player_input(Vector2.ZERO, false)
	_check(
		new_controller.get_position().distance_to(before) > 0.1,
		"接管后的单位可以响应玩家移动"
	)
	_check(
		_scene.get_camera_position().distance_to(camera_before_transfer) > 0.1,
		"接管后摄像机自动跟随新的控制单位"
	)

	# 自由视角期间移动输入只作用于镜头，不移动当前控制角色。
	_scene.set_camera_free_mode(true)
	_scene.set_test_free_camera_input(Vector2.RIGHT)
	_scene.set_test_player_input(Vector2.RIGHT)
	for i: int in range(3):
		await get_tree().physics_frame
	_check(
		not new_controller.is_moving(),
		"自由视角下玩家角色不响应移动输入"
	)
	_scene.set_test_player_input(Vector2.ZERO, false)
	_scene.set_test_free_camera_input(Vector2.ZERO, false)
	_scene.set_camera_free_mode(false)

	# 接管后的单位也能使用普通 Unit 攻击规则。
	for unit_id: String in _session.get_side_unit_ids(1):
		var target := _scene.get_controller(unit_id)
		if target == null or not target.is_alive():
			continue
		target.state.battle_position = new_controller.get_position() + Vector2(20.0, 0.0)
		new_controller.player_tick(
			new_controller.unit_data.attack_interval + 0.01, Vector2.ZERO
		)
		var hp_before := target.state.battle_hp
		var hit := _scene.try_player_attack_at(target.get_position())
		_check(hit, "接管后的单位可以攻击敌人")
		_advance_melee_hit(new_controller)
		_check(
			target.state.battle_hp == hp_before - new_controller.unit_data.attack,
			"接管单位的攻击使用自身属性"
		)
		_check(
			new_controller.get_last_attack_direction().dot(Vector2.RIGHT) > 0.99,
			"接管单位的攻击方向正确"
		)
		_check(
			new_controller.actor != null and new_controller.actor.is_attack_animating(),
			"接管单位的攻击动画正常"
		)
		break


func _test_spectate_and_defeat() -> void:
	var current_id := _scene.get_controlled_unit_id()
	var current := _scene.get_controller(current_id)
	if current != null:
		current.apply_damage(9999)
	await _settle_frames(3)
	var panel := _scene.find_child("ControlTransferPanel", true, false) as PanelContainer
	_check(panel != null and panel.visible, "再次失去控制角色后显示转移面板")
	if panel == null or not panel.visible:
		return
	var spectate := panel.find_child("BattleSpectateButton", true, false) as Button
	_check(spectate != null, "面板包含观战按钮")
	if spectate == null:
		return
	spectate.pressed.emit()
	await get_tree().physics_frame
	_check(_scene.is_spectating(), "选择观战后进入观战模式")
	_check(_scene.get_controlled_unit_id().is_empty(), "观战模式没有控制单位")
	_check(not _scene.is_scene_paused(), "观战后战斗继续")
	_check(_count_player_controlled() == 0, "观战模式没有玩家控制单位")

	# 清空玩家侧，触发战败结果。
	var controllers := _scene.get_node("World/Characters").get_child_count()
	_check(controllers > 0, "战场存在表现节点")
	for unit_id: String in _player.member_unit_ids:
		var controller := _scene.get_controller(unit_id)
		if controller != null and controller.is_alive():
			controller.apply_damage(9999)
	await _settle_frames(5)

	var result_panel := _scene.find_child("BattleResultPanel", true, false) as PanelContainer
	var result_label := _scene.find_child("BattleResultLabel", true, false) as Label
	_check(result_panel != null and result_panel.visible, "玩家侧全灭后显示结果面板")
	_check(result_label != null and result_label.text == "战斗失败", "玩家侧全灭判定为失败")
	var summary := _scene.find_child("BattleResultSummaryLabel", true, false) as Label
	var casualties := _scene.find_child("BattleResultCasualtiesLabel", true, false) as Label
	var exp_label := _scene.find_child("BattleResultExpLabel", true, false) as Label
	var reward_label := _scene.find_child("BattleResultRewardLabel", true, false) as Label
	_check(summary != null and not summary.text.is_empty(), "结果面板显示交战方")
	_check(casualties != null and casualties.text.contains("阵亡"), "结果面板显示伤亡")
	_check(exp_label != null and exp_label.text.contains("经验"), "结果面板显示经验")
	_check(reward_label != null and reward_label.text.contains("金币"), "结果面板显示奖励")

	_check(
		_context.battle_manager.finish_battle(
			_session.battle_id, BattleSession.BattleResult.DEFENDER_VICTORY
		),
		"战败结算成功"
	)
	_check(_session.final_result != null, "战败生成统一 BattleResult")
	if _session.final_result != null:
		_check(_session.final_result.player_won == false, "战败不标记玩家获胜")
		# 伤兵系统启用后，战败方部分减员按“伤兵”统计；
		# “全员伤亡”应同时覆盖阵亡与伤兵，且不留下存活者。
		var killed: int = _session.final_result.get_party_casualties(
			_player.party_id
		)
		var wounded: int = _session.final_result.get_party_wounded(
			_player.party_id
		)
		_check(
			killed + wounded == WorldInitializer.PLAYER_TOTAL_MEMBER_COUNT,
			"玩家部队全员伤亡（阵亡 + 伤兵）"
		)
		_check(
			_session.final_result.get_party_survivors(_player.party_id) == 0,
			"玩家部队没有存活者"
		)
		_check(_session.final_result.reward_gold == 0, "战败没有金币奖励")


func _count_player_controlled() -> int:
	var count: int = 0
	for unit_id: String in _session.get_all_unit_ids():
		var controller := _scene.get_controller(unit_id)
		if controller != null and controller.is_player_controlled:
			count += 1
	return count


func _settle_frames(count: int) -> void:
	for i: int in range(count):
		await get_tree().physics_frame


## 伤害现在发生在长矛戳击的有效帧；测试直接推进动画，避免依赖真实帧率。
## 有动画时等待有效帧事件，无动画的纯数据控制器会立即结算，本函数为空操作。
func _advance_melee_hit(controller: UnitController) -> void:
	if controller == null or controller.actor == null:
		return
	controller.actor.advance_attack_animation(
		HumanVisualScript.SPEAR_WINDUP_TIME
	)
	controller.actor.advance_attack_animation(
		HumanVisualScript.SPEAR_THRUST_TIME
	)


func _find_party_by_name(party_name: String) -> PartyData:
	for party: PartyData in _context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[playercontrol] OK: %s" % message)
	else:
		_failed = true
		push_error("[playercontrol] FAIL: %s" % message)


func _cleanup() -> void:
	if _context != null and _context.battle_manager.current_battle != null:
		_context.battle_manager.abort_battle(
			_context.battle_manager.current_battle.battle_id
		)
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	GameManager.player_party_id = ""
	if is_instance_valid(_scene):
		_scene.queue_free()
	if is_instance_valid(_context):
		_context.queue_free()
