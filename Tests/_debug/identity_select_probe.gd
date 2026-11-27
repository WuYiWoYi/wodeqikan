extends Node
## 手动视觉验收：文化选择、身份选择与最终路线预览截图。
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

	await _capture("identity_probe_culture.png")

	var bugido := screen.find_child(
		"CultureOption_CULTURE_BUGIDO", true, false
	) as Button
	bugido.mouse_entered.emit()
	for i: int in range(3):
		await get_tree().process_frame
	await _capture("identity_probe_culture_hover.png")
	bugido.mouse_exited.emit()
	bugido.pressed.emit()
	for i: int in range(3):
		await get_tree().process_frame
	await _capture("identity_probe_culture_selected.png")

	var confirm := screen.find_child("ConfirmButton", true, false) as Button
	confirm.pressed.emit()
	for i: int in range(4):
		await get_tree().process_frame
	await _capture("identity_probe_identity.png")

	var merchant := screen.find_child(
		"IdentityOption_IDENTITY_FRANI_MERCHANT", true, false
	) as Button
	merchant.pressed.emit()
	for i: int in range(3):
		await get_tree().process_frame
	confirm = screen.find_child("ConfirmButton", true, false) as Button
	confirm.pressed.emit()
	for i: int in range(4):
		await get_tree().process_frame
	await _capture("identity_probe_preview.png")

	get_window().size = Vector2i(1280, 720)
	for i: int in range(6):
		await get_tree().process_frame
	var back := screen.find_child("BackButton", true, false) as Button
	back.pressed.emit()
	for i: int in range(4):
		await get_tree().process_frame
	await _capture("identity_probe_identity_small.png")

	print("identity probe screenshots saved to user://")
	get_tree().quit(0)


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("user://%s" % file_name))
