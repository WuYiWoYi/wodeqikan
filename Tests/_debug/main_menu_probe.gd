extends Node
## 手动视觉验收：1920×1080 主菜单布局截图。
## 运行（非 headless）：
##   Godot_v4.6.1-stable_win64.exe --path . res://Tests/_debug/main_menu_probe.tscn


func _ready() -> void:
	get_tree().current_scene = null
	await get_tree().process_frame
	var packed := load("res://Scenes/MainMenu/main_menu.tscn") as PackedScene
	var menu := packed.instantiate()
	add_child(menu)
	for i: int in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	print("MAIN MENU viewport=%s setting=%s" % [
		get_viewport().size,
		ProjectSettings.get_setting("display/window/size/viewport_width"),
	])
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("user://visual_probe_main_menu.png")
	)
	get_tree().quit(0)
