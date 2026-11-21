extends Node
## 临时调试：真实渲染战斗场景并保存截图，用于确认士兵贴图是否可见。
## 运行（非 headless）：
##   Godot_v4.6.1-stable_win64.exe --path . res://Tests/_debug/visual_probe.tscn

const SHOT_PATH: String = "user://visual_probe_battle.png"


func _ready() -> void:
	TimeManager.start_session()
	TimeManager.clear_pauses()
	TimeManager.set_base_world_speed(TimeManager.SPEED_NORMAL)

	var context := WorldContext.new()
	context.name = "VisualProbeContext"
	add_child(context)
	if not WorldInitializer.create_new_world(context):
		push_error("visual probe: 世界初始化失败")
		get_tree().quit(1)
		return

	var player := context.get_player_party()
	var enemy := _find_party(context, WorldInitializer.TEST_ENEMY_PARTY_NAME)
	if player == null or enemy == null:
		push_error("visual probe: 找不到测试部队")
		get_tree().quit(1)
		return

	GameManager.world_context = context
	GameManager.player_party_id = context.player_party_id
	var session := context.battle_manager.start_battle(
		[player.party_id], [enemy.party_id], enemy.world_position
	)
	if session == null:
		push_error("visual probe: 战斗创建失败")
		get_tree().quit(1)
		return

	var packed := load("res://Scenes/Battle/battle.tscn") as PackedScene
	var battle := packed.instantiate()
	add_child(battle)
	await get_tree().process_frame
	await get_tree().process_frame
	for i: int in range(12):
		await get_tree().physics_frame

	var mounted_visual: Node2D = null
	var characters := battle.get_node_or_null("World/Characters")
	if characters != null:
		for child: Node in characters.get_children():
			var actor := child as UnitActor
			if actor == null or actor.unit_data == null or not actor.unit_data.is_mounted:
				continue
			mounted_visual = actor.visual
			print("PROBE mounted actor=%s z=%s visual_visible=%s actor_scale=%s visual_scale=%s" % [
				actor.name, actor.z_index, actor.visual.visible,
				actor.scale, actor.visual.scale
			])
			print("  human_offset_y=%s horse_visible=%s" % [
				actor.visual.get_human_visual().position.y,
				actor.visual.get_horse_visual().visible,
			])
			for part_name: Variant in actor.visual.get_parts():
				var sprite: Sprite2D = actor.visual.get_part(str(part_name))
				if sprite != null:
					print("  part=%s z=%s effective_z=%s visible_in_tree=%s offset=%s" % [
						part_name, sprite.z_index,
						actor.visual.get_part_effective_z(str(part_name)),
						sprite.is_visible_in_tree(), sprite.offset
					])
			break

	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(SHOT_PATH)
	var error := image.save_png(path)
	print("visual probe shot: %s (error=%s)" % [path, error])

	# 近距离截图：确认人体双腿、马身/马鞍遮挡与朝向。
	var camera := battle.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.position = Vector2(420.0, 360.0)
		camera.zoom = Vector2(2.4, 2.4)
	for i: int in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var close_image := get_viewport().get_texture().get_image()
	var close_path := ProjectSettings.globalize_path("user://visual_probe_close.png")
	var close_error := close_image.save_png(close_path)
	print("visual probe close shot: %s (error=%s)" % [close_path, close_error])

	# 移动验证：玩家角色向右移动后截图，确认部件跟随且朝向翻转。
	var hero_id: String = str(battle.get_controlled_unit_id())
	var hero: UnitController = battle.get_controller(hero_id)
	var hero_actor := battle.get_node("World/Characters").get_node_or_null(
		"UnitActor_%s" % hero_id
	) as UnitActor
	if hero != null:
		var before_move: Vector2 = hero.get_position()
		battle.set_test_player_input(Vector2.RIGHT)
		for i: int in range(20):
			await get_tree().physics_frame
		battle.set_test_player_input(Vector2.ZERO, false)
		print("PROBE move delta=%s" % before_move.distance_to(hero.get_position()))
		if hero_actor != null and hero_actor.visual != null:
			print("PROBE facing human_scale_x=%s horse_scale_x=%s" % [
				hero_actor.visual.get_human_visual().scale.x,
				hero_actor.visual.get_horse_visual().scale.x,
			])
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			ProjectSettings.globalize_path("user://visual_probe_move.png")
		)

	# 攻击验证：把一个敌人放到玩家角色旁边并触发攻击，截图攻击闪光。
	if hero != null and not session.defender_unit_ids.is_empty():
		var enemy_controller: UnitController = battle.get_controller(
			session.defender_unit_ids[0]
		)
		if enemy_controller != null and enemy_controller.is_alive():
			enemy_controller.state.battle_position = hero.get_position() + Vector2(30.0, 0.0)
			var enemy_hp_before: int = enemy_controller.state.battle_hp
			var hit: bool = battle.try_player_attack_at(enemy_controller.get_position())
			print("PROBE attack hit=%s hp_before=%s hp_after=%s dir=%s target=%s" % [
				hit,
				enemy_hp_before,
				enemy_controller.state.battle_hp,
				hero.get_last_attack_direction(),
				hero.get_last_attack_target_id(),
			])
			# 前摇：长矛先向攻击反方向轻微后移。
			await get_tree().create_timer(0.07).timeout
			if hero_actor != null and hero_actor.visual != null:
				var weapon: Sprite2D = hero_actor.visual.get_part("Weapon")
				var pivot: Node2D = hero_actor.visual.get_weapon_pivot()
				print("PROBE windup weapon_modulate=%s pivot_pos=%s rotation=%s" % [
					weapon.modulate if weapon != null else Color.WHITE,
					pivot.position if pivot != null else Vector2.ZERO,
					pivot.rotation if pivot != null else 0.0,
				])
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
				ProjectSettings.globalize_path("user://visual_probe_attack_windup.png")
			)

			# 戳击完成：长矛沿攻击方向快速前伸。
			await get_tree().create_timer(0.22).timeout
			if hero_actor != null and hero_actor.visual != null:
				var thrust_pivot: Node2D = hero_actor.visual.get_weapon_pivot()
				print("PROBE thrust pivot_pos=%s rotation=%s" % [
					thrust_pivot.position if thrust_pivot != null else Vector2.ZERO,
					thrust_pivot.rotation if thrust_pivot != null else 0.0,
				])
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
				ProjectSettings.globalize_path("user://visual_probe_attack_thrust.png")
			)
			# 攻击后保持阶段：默认 4 秒内长矛应维持攻击姿态。
			await get_tree().create_timer(1.0).timeout
			if hero_actor != null and hero_actor.visual != null:
				var hold_pivot: Node2D = hero_actor.visual.get_weapon_pivot()
				print("PROBE hold rotation=%s animating=%s" % [
					hold_pivot.rotation if hold_pivot != null else 0.0,
					hero_actor.visual.is_attack_animating(),
				])
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
				ProjectSettings.globalize_path("user://visual_probe_hold.png")
			)

			# 等待恢复阶段结束，确认长矛重新竖直。
			await get_tree().create_timer(3.5).timeout
			if hero_actor != null and hero_actor.visual != null:
				var pivot: Node2D = hero_actor.visual.get_weapon_pivot()
				print("PROBE recover rotation=%s animating=%s" % [
					pivot.rotation if pivot != null else 0.0,
					hero_actor.visual.is_attack_animating(),
				])
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
				ProjectSettings.globalize_path("user://visual_probe_recover.png")
			)

			# 朝左攻击验证：默认朝左时矛尖必须指向左侧。
			var left_enemy: UnitController = null
			for unit_id: String in session.defender_unit_ids:
				var candidate: UnitController = battle.get_controller(unit_id)
				if candidate != null and candidate.is_alive():
					left_enemy = candidate
					break
			if left_enemy != null:
				left_enemy.state.battle_position = hero.get_position() + Vector2(-30.0, 0.0)
				await get_tree().create_timer(0.1).timeout
				var left_hp_before: int = left_enemy.state.battle_hp
				var left_hit: bool = battle.try_player_attack_at(left_enemy.get_position())
				await get_tree().create_timer(0.30).timeout
				if hero_actor != null and hero_actor.visual != null:
					var pivot: Node2D = hero_actor.visual.get_weapon_pivot()
					print("PROBE left attack hit=%s hp_before=%s hp_after=%s dir=%s human_scale_x=%s rotation=%s" % [
						left_hit,
						left_hp_before,
						left_enemy.state.battle_hp,
						hero.get_last_attack_direction(),
						hero_actor.visual.get_human_visual().scale.x,
						pivot.rotation if pivot != null else 0.0,
					])
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(
					ProjectSettings.globalize_path("user://visual_probe_attack_left.png")
				)

			# 向上/向下攻击：验证竖直方向的武器动画。
			await get_tree().create_timer(0.9).timeout
			var vertical_enemy: UnitController = _find_alive_defender(battle, session)
			if vertical_enemy != null:
				vertical_enemy.state.battle_position = hero.get_position() + Vector2(0.0, -30.0)
				var up_hp_before: int = vertical_enemy.state.battle_hp
				var up_hit: bool = battle.try_player_attack_at(vertical_enemy.get_position())
				await get_tree().create_timer(0.30).timeout
				var up_pivot: Node2D = hero_actor.visual.get_weapon_pivot() if (
					hero_actor != null and hero_actor.visual != null
				) else null
				print("PROBE up attack hit=%s hp_before=%s hp_after=%s dir=%s rotation=%s" % [
					up_hit,
					up_hp_before,
					vertical_enemy.state.battle_hp,
					hero.get_last_attack_direction(),
					up_pivot.rotation if up_pivot != null else 0.0,
				])
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(
					ProjectSettings.globalize_path("user://visual_probe_attack_up.png")
				)

				await get_tree().create_timer(0.9).timeout
				var down_enemy: UnitController = vertical_enemy
				if not down_enemy.is_alive():
					down_enemy = _find_alive_defender(battle, session)
				if down_enemy != null:
					down_enemy.state.battle_position = hero.get_position() + Vector2(0.0, 30.0)
					var down_hp_before: int = down_enemy.state.battle_hp
					var down_hit: bool = battle.try_player_attack_at(down_enemy.get_position())
					await get_tree().create_timer(0.30).timeout
					var down_pivot: Node2D = hero_actor.visual.get_weapon_pivot() if (
						hero_actor != null and hero_actor.visual != null
					) else null
					print("PROBE down attack hit=%s hp_before=%s hp_after=%s dir=%s rotation=%s" % [
						down_hit,
						down_hp_before,
						down_enemy.state.battle_hp,
						hero.get_last_attack_direction(),
						down_pivot.rotation if down_pivot != null else 0.0,
					])
					await RenderingServer.frame_post_draw
					get_viewport().get_texture().get_image().save_png(
						ProjectSettings.globalize_path("user://visual_probe_attack_down.png")
					)

	# 隐藏马匹部件，确认人体双腿确实存在且未被主动隐藏。
	if mounted_visual != null:
		for part_name: String in [
			"MountLegBack", "MountLegBack2", "MountLegFront", "MountLegFront2",
			"MountBody", "MountHead", "MountSaddle"
		]:
			var part: Sprite2D = mounted_visual.get_part(part_name)
			if part != null:
				part.visible = false
		for i: int in range(3):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var legs_image := get_viewport().get_texture().get_image()
		var legs_path := ProjectSettings.globalize_path("user://visual_probe_legs_only.png")
		var legs_error := legs_image.save_png(legs_path)
		print("visual probe legs shot: %s (error=%s)" % [legs_path, legs_error])

	# 结果面板 1920×1080 布局截图。
	for unit_id: String in session.defender_unit_ids:
		var defender_state := session.get_unit_state(unit_id)
		if defender_state != null:
			defender_state.battle_hp = 0
			defender_state.alive = false
	for i: int in range(3):
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("user://visual_probe_result.png")
	)

	if context.battle_manager.current_battle == session:
		context.battle_manager.abort_battle(session.battle_id)
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	GameManager.world_context = null
	get_tree().quit(0)


func _find_alive_defender(battle: Node, session: BattleSession) -> UnitController:
	for unit_id: String in session.defender_unit_ids:
		var controller: UnitController = battle.get_controller(unit_id)
		if controller != null and controller.is_alive():
			return controller
	return null


func _find_party(context: WorldContext, party_name: String) -> PartyData:
	for party: PartyData in context.party_manager.get_all_parties():
		if party.party_name == party_name:
			return party
	return null
