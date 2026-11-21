extends Node
## 手动视觉验收：打开大地图部队面板，截图步兵/骑兵的美术预览。
## 运行（非 headless）：
##   Godot_v4.6.1-stable_win64.exe --path . res://Tests/_debug/party_preview_probe.tscn


func _ready() -> void:
	await _run()
	GameManager.enter_main_menu()
	TimeManager.stop_session()
	TimeManager.clear_pauses()
	get_tree().quit(0)


func _run() -> void:
	get_tree().current_scene = null
	await get_tree().process_frame
	TimeManager.clear_pauses()
	TimeManager.stop_session()
	if not GameManager.start_new_game():
		push_error("party preview probe: 新游戏启动失败")
		return
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var world_map := get_tree().current_scene
	if world_map == null:
		push_error("party preview probe: 当前场景为空")
		return
	var party_button := world_map.find_child("PartyButton", true, false) as Button
	if party_button == null:
		push_error("party preview probe: 找不到部队按钮")
		return
	party_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var panel := world_map.find_child("PartyPanel", true, false)
	var preview := world_map.find_child("PreviewUnitVisual", true, false)
	if panel == null or preview == null:
		push_error("party preview probe: 找不到面板或预览")
		return
	print("PREVIEW foot unit=%s horse_visible=%s human_offset_y=%s" % [
		preview.unit_data.unit_id if preview.unit_data != null else "",
		preview.get_horse_visual().visible,
		preview.get_human_visual().position.y,
	])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("user://visual_probe_party_foot.png")
	)
	var foot_upper: Node2D = preview.get_human_visual().get_upper_body()
	print("PREVIEW foot idle body_y=%s body_rotation=%s" % [
		foot_upper.position.y if foot_upper != null else 0.0,
		foot_upper.rotation if foot_upper != null else 0.0,
	])
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("user://visual_probe_party_foot_idle.png")
	)
	print("PREVIEW foot idle later body_y=%s body_rotation=%s" % [
		foot_upper.position.y if foot_upper != null else 0.0,
		foot_upper.rotation if foot_upper != null else 0.0,
	])

	var context := GameManager.world_context
	var player := context.get_player_party()
	var mounted_id: String = ""
	for unit_id: String in player.member_unit_ids:
		var unit := context.unit_manager.get_unit(unit_id)
		if unit != null and unit.is_mounted:
			mounted_id = unit_id
			break
	if mounted_id.is_empty():
		push_error("party preview probe: 找不到骑乘士兵")
		return
	var item := panel.find_child("MemberItem_%s" % mounted_id, true, false) as PartyMemberItem
	if item == null:
		push_error("party preview probe: 找不到骑兵列表项")
		return
	item.pressed.emit()
	for i: int in range(4):
		await get_tree().process_frame
	print("PREVIEW mounted unit=%s horse_visible=%s human_offset_y=%s mount_body=%s foot_shadow_visible=%s" % [
		preview.unit_data.unit_id if preview.unit_data != null else "",
		preview.get_horse_visual().visible,
		preview.get_human_visual().position.y,
		preview.get_part("MountBody").is_visible_in_tree(),
		preview.get_part("FootShadow").is_visible_in_tree(),
	])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("user://visual_probe_party_mounted.png")
	)
	var horse_rig: Node2D = preview.get_horse_visual().get_body_rig()
	print("PREVIEW mounted idle body_y=%s rotation=%s" % [
		horse_rig.position.y if horse_rig != null else 0.0,
		horse_rig.rotation if horse_rig != null else 0.0,
	])
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("user://visual_probe_party_mounted_idle.png")
	)
	print("PREVIEW mounted idle later body_y=%s rotation=%s" % [
		horse_rig.position.y if horse_rig != null else 0.0,
		horse_rig.rotation if horse_rig != null else 0.0,
	])
