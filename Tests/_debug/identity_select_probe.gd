extends Node
## 手动视觉验收：身份选择全屏一级、二级、最终确认页截图。
## 运行（非 headless）：
##   Godot_v4.6.1-stable_win64.exe --path . res://Tests/_debug/identity_select_probe.tscn


func _ready() -> void:
	get_tree().current_scene = null
	await get_tree().process_frame
	var packed := load("res://Scenes/Identity/identity_select.tscn") as PackedScene
	var screen := packed.instantiate() as Control
	get_tree().root.add_child(screen)
	get_tree().current_scene = screen
	for i: int in range(5):
		await get_tree().process_frame

	await _capture("identity_probe_category.png")

	var noble := screen.find_child("CategoryButton_NOBLE", true, false) as Button
	noble.pressed.emit()
	for i: int in range(4):
		await get_tree().process_frame
	await _capture("identity_probe_identity.png")

	# 点击具体身份后应立即进入最终确认，不再有“完成选择”按钮。
	var second_son := screen.find_child(
		"IdentityButton_NOBLE_SECOND_SON", true, false
	) as Button
	second_son.button_pressed = true
	for i: int in range(4):
		await get_tree().process_frame
	await _capture("identity_probe_confirm.png")

	get_window().size = Vector2i(1280, 720)
	for i: int in range(6):
		await get_tree().process_frame
	var return_modify := screen.find_child(
		"ReturnModifyButton", true, false
	) as Button
	return_modify.pressed.emit()
	for i: int in range(4):
		await get_tree().process_frame
	noble = screen.find_child("CategoryButton_NOBLE", true, false) as Button
	noble.pressed.emit()
	for i: int in range(4):
		await get_tree().process_frame
	await _capture("identity_probe_identity_small.png")

	print("identity probe screenshots saved to user://")
	get_tree().quit(0)


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("user://%s" % file_name))
