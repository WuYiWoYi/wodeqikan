extends Node
## 主菜单 UI 冒烟测试：检查按钮与读取/设置面板可打开关闭。
## 不点击 New Game，避免测试节点被场景切换释放。

var _failed: bool = false


func _ready() -> void:
	await _run()
	if _failed:
		push_error("[menu-ui] 测试失败")
		get_tree().quit(1)
	else:
		print("[menu-ui] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	var theme := UiTheme.create()
	_check(theme.default_font != null, "UI 主题包含默认字体")
	if theme.default_font != null:
		_check(theme.default_font.has_char("玩".unicode_at(0)), "默认字体包含中文字形")

	var packed := load("res://Scenes/MainMenu/main_menu.tscn") as PackedScene
	var menu := packed.instantiate()
	add_child(menu)
	await get_tree().process_frame

	_check(menu.find_child("NewGameButton", true, false) != null, "新游戏按钮存在")
	var continue_button := menu.find_child("ContinueButton", true, false) as Button
	_check(continue_button != null, "继续游戏按钮存在")
	if continue_button != null:
		_check(
			continue_button.disabled == SaveManager.get_latest_save_slot().is_empty(),
			"继续按钮状态与有效存档一致"
		)
	_check(menu.find_child("LoadGameButton", true, false) != null, "读取存档按钮存在")
	_check(menu.find_child("SettingsButton", true, false) != null, "设置按钮存在")
	_check(menu.find_child("QuitButton", true, false) != null, "退出按钮存在")

	var load_button := menu.find_child("LoadGameButton", true, false) as Button
	var load_panel := menu.find_child("LoadPanel", true, false) as PanelContainer
	_check(load_button != null and load_panel != null, "读取面板已生成")
	if load_button != null and load_panel != null:
		load_button.pressed.emit()
		await get_tree().process_frame
		_check(load_panel.visible, "读取面板可打开")
		var back_button := menu.find_child("LoadBackButton", true, false) as Button
		if back_button != null:
			back_button.pressed.emit()
			await get_tree().process_frame
		_check(not load_panel.visible, "读取面板可关闭")

	var settings_button := menu.find_child("SettingsButton", true, false) as Button
	var settings_panel := menu.find_child("SettingsPanel", true, false) as PanelContainer
	_check(settings_button != null and settings_panel != null, "设置占位面板已生成")
	if settings_button != null and settings_panel != null:
		settings_button.pressed.emit()
		await get_tree().process_frame
		_check(settings_panel.visible, "设置面板可打开")
		var close_button := menu.find_child("SettingsCloseButton", true, false) as Button
		if close_button != null:
			close_button.pressed.emit()
			await get_tree().process_frame
		_check(not settings_panel.visible, "设置面板可关闭")

	menu.free()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[menu-ui] OK: %s" % message)
	else:
		_failed = true
		push_error("[menu-ui] FAIL: %s" % message)
