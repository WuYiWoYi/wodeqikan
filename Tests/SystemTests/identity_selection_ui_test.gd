extends Node
## 新游戏文化/身份选择全屏流程测试：
## 主菜单跳转、文化层默认选中与悬浮预览、身份层默认选中、确认才推进、
## 退回保留选择、最终路线预览、结果传递、以及瓦伊拉家族独立美术资源。
##
## 场景切换只释放 current_scene；测试节点作为 root 的普通子节点保留。

var _failed: bool = false
var _menu: Control = null
var _screen: Control = null


func _ready() -> void:
	get_tree().current_scene = null
	await get_tree().process_frame
	await _run()
	await _cleanup()
	if _failed:
		push_error("[identity-ui] 测试失败")
		get_tree().quit(1)
	else:
		print("[identity-ui] 全部通过")
		get_tree().quit(0)


func _run() -> void:
	_check_catalog()
	_check_vaila_assets()

	var packed := load("res://Scenes/MainMenu/main_menu.tscn") as PackedScene
	_check(packed != null, "主菜单场景可加载")
	if packed == null:
		return
	_menu = packed.instantiate() as Control
	get_tree().root.add_child(_menu)
	get_tree().current_scene = _menu
	await get_tree().process_frame

	var new_game_button := _menu.find_child("NewGameButton", true, false) as Button
	_check(new_game_button != null, "新游戏按钮存在")
	if new_game_button == null:
		return
	new_game_button.pressed.emit()
	await _wait_scene_change()

	_check(not is_instance_valid(_menu), "主菜单已释放，选择界面为独立场景")
	_screen = get_tree().current_scene as Control
	_check(_screen != null and _screen.name == "IdentitySelect", "进入全屏选择场景")
	if _screen == null:
		return
	_check(_is_full_screen(_screen), "选择界面覆盖整个窗口")
	_check(GameManager.world_context == null, "进入选择界面不创建世界")

	# ---------- 文化层 ----------
	_check_page("CulturePage")
	var doraman := _button("CultureOption_CULTURE_DORAMAN")
	var bugido := _button("CultureOption_CULTURE_BUGIDO")
	var lorris := _button("CultureOption_CULTURE_LORRIS")
	_check(doraman != null and doraman.text == "多拉曼人", "文化列表显示多拉曼人")
	_check(bugido != null and bugido.text == "布吉多人", "文化列表显示布吉多人")
	_check(lorris != null and lorris.text == "洛里斯人", "文化列表显示洛里斯人")
	if doraman == null or bugido == null or lorris == null:
		return
	await get_tree().process_frame
	_check(doraman.get_parent() is VBoxContainer, "文化选项使用纵向容器")
	_check(
		doraman.position.y < bugido.position.y
			and bugido.position.y < lorris.position.y,
		"文化选项按顺序上下排列"
	)

	_check(doraman.button_pressed, "默认选中第一个文化：多拉曼人")
	_check(_label("CultureDetailTitle").text == "多拉曼人", "左侧默认展示多拉曼人")
	_check(
		_label("CultureDescriptionLabel").text.contains("天生的冒险者"),
		"左侧展示多拉曼文化背景"
	)
	var culture_bonus := _node("CultureBonusList")
	_check(
		culture_bonus != null and culture_bonus.get_child_count() == 3,
		"多拉曼展示三条文化天赋"
	)
	_check(
		_bonus_texts("CultureBonusList").has("统治的据点采邑恢复速度 +20%"),
		"文化天赋内容正确"
	)
	_check_route("多拉曼人", "身份：待选择")

	# 悬浮只预览左侧，不改变选中项和路线。
	bugido.mouse_entered.emit()
	await get_tree().process_frame
	_check(_label("CultureDetailTitle").text == "布吉多人", "悬浮文化即时更新左侧")
	_check(
		_label("CultureDescriptionLabel").text.contains("这片土地的所有者"),
		"悬浮文化展示对应背景"
	)
	_check(
		_bonus_texts("CultureBonusList").has("城堡驻军薪资 -20%"),
		"悬浮展示布吉多已确定天赋"
	)
	_check(
		_bonus_texts("CultureBonusList").any(func(text: String) -> bool:
			return text.contains("待设定")),
		"布吉多未确定天赋使用占位"
	)
	_check(doraman.button_pressed and not bugido.button_pressed, "悬浮不改变已选文化")
	_check_route("多拉曼人", "身份：待选择")
	bugido.mouse_exited.emit()
	await get_tree().process_frame
	_check(_label("CultureDetailTitle").text == "多拉曼人", "悬浮离开后恢复已选文化")

	# 点击只选定，不跳转。
	bugido.pressed.emit()
	await get_tree().process_frame
	_check(bugido.button_pressed and not doraman.button_pressed, "点击选中布吉多人")
	_check(_label("CultureDetailTitle").text == "布吉多人", "点击更新左侧详情")
	_check_page("CulturePage")
	_check_route("布吉多人", "身份：待选择")

	var confirm_button := _button("ConfirmButton")
	var back_button := _button("BackButton")
	_check(confirm_button != null and confirm_button.text == "确认文化", "文化层确认按钮")
	_check(back_button != null and back_button.text == "返回主菜单", "文化层退回主菜单")
	if confirm_button == null or back_button == null:
		return

	# 文化层退回主菜单；重新进入应从默认文化开始。
	back_button.pressed.emit()
	await _wait_scene_change()
	_check(
		get_tree().current_scene != null
			and get_tree().current_scene.name == "MainMenu",
		"文化层可退回主菜单"
	)
	var menu_again := get_tree().current_scene as Control
	var new_game_again := menu_again.find_child(
		"NewGameButton", true, false
	) as Button
	if new_game_again != null:
		new_game_again.pressed.emit()
		await _wait_scene_change()
	_screen = get_tree().current_scene as Control
	_check(
		_screen != null and _screen.name == "IdentitySelect",
		"可重新进入选择界面"
	)
	if _screen == null:
		return
	_check(_button("CultureOption_CULTURE_DORAMAN").button_pressed, "重新进入默认选中多拉曼人")
	_check_route("多拉曼人", "身份：待选择")

	# 选择布吉多并确认，进入身份层。
	_button("CultureOption_CULTURE_BUGIDO").pressed.emit()
	await get_tree().process_frame
	_button("ConfirmButton").pressed.emit()
	await get_tree().process_frame

	# ---------- 身份层 ----------
	_check_page("IdentityPage")
	_check(_button("ConfirmButton").text == "确认身份", "身份层确认按钮")
	_check(_button("BackButton").text == "退回", "身份层退回按钮")

	var knight := _button("IdentityOption_IDENTITY_DINDANI_KNIGHT")
	var merchant := _button("IdentityOption_IDENTITY_FRANI_MERCHANT")
	_check(knight != null and knight.text == "丁达尼家族骑士", "布吉多显示贵族路线")
	_check(merchant != null and merchant.text == "弗拉尼的商人", "布吉多显示平民路线")
	_check(
		_button("IdentityOption_IDENTITY_EKTOR_SECOND_SON") == null,
		"布吉多页不显示其他文化身份"
	)
	if knight == null or merchant == null:
		return
	await get_tree().process_frame
	_check(knight.get_parent() is VBoxContainer, "身份选项使用纵向容器")
	_check(knight.position.y < merchant.position.y, "贵族与平民上下排列")

	_check(knight.button_pressed, "默认选中第一个身份：丁达尼家族骑士")
	_check(_label("IdentityDetailTitle").text == "丁达尼家族骑士", "左侧默认展示第一个身份")
	_check(_label("IdentityDetailType").text.contains("贵族"), "左侧展示身份类型")
	_check(
		_label("IdentityDescriptionLabel").text.contains("最古老的血脉"),
		"左侧展示身份背景"
	)
	_check(
		_bonus_texts("IdentityBonusList").any(func(text: String) -> bool:
			return text.contains("待设定")),
		"未提供身份加成时展示占位"
	)
	_check_route("布吉多人", "丁达尼家族骑士")
	_check_route("布吉多人", "贵族")

	# 悬浮平民路线只预览，不改变选中与路线。
	merchant.mouse_entered.emit()
	await get_tree().process_frame
	_check(_label("IdentityDetailTitle").text == "弗拉尼的商人", "悬浮身份即时更新左侧")
	_check(_label("IdentityDetailType").text.contains("平民"), "悬浮展示身份类型")
	_check(
		_label("IdentityDescriptionLabel").text.contains("市集上做生意"),
		"悬浮展示对应背景"
	)
	_check(knight.button_pressed and not merchant.button_pressed, "悬浮不改变已选身份")
	_check_route("布吉多人", "丁达尼家族骑士")
	merchant.mouse_exited.emit()
	await get_tree().process_frame
	_check(_label("IdentityDetailTitle").text == "丁达尼家族骑士", "悬浮离开后恢复已选身份")

	# 点击只选定，不跳转。
	var slot_before := SaveManager.get_latest_save_slot()
	merchant.pressed.emit()
	await get_tree().process_frame
	_check(merchant.button_pressed and not knight.button_pressed, "点击选中平民身份")
	_check(_label("IdentityDetailTitle").text == "弗拉尼的商人", "点击更新左侧详情")
	_check(_label("IdentityDetailType").text.contains("平民"), "点击后类型为平民")
	_check_page("IdentityPage")
	_check_route("布吉多人", "弗拉尼的商人")
	_check_route("布吉多人", "平民")
	_check(GameManager.world_context == null, "身份层不创建世界")
	_check(SaveManager.get_latest_save_slot() == slot_before, "身份层不创建存档")

	# 确认身份进入最终路线预览。
	_button("ConfirmButton").pressed.emit()
	await get_tree().process_frame
	_check_page("PreviewPage")
	_check(_button("ConfirmButton").text == "开始游戏", "预览层确认按钮为开始游戏")
	_check(_button("BackButton").text == "退回", "预览层提供退回")
	var preview_route := _label("PreviewRouteLabel")
	_check(
		preview_route.text.contains("布吉多人")
			and preview_route.text.contains("平民")
			and preview_route.text.contains("弗拉尼的商人"),
		"最终路线预览完整显示文化与身份"
	)
	_check(GameManager.world_context == null, "预览层不创建世界")
	_check(SaveManager.get_latest_save_slot() == slot_before, "预览层不创建存档")

	# 退回身份层，保留已选身份。
	_button("BackButton").pressed.emit()
	await get_tree().process_frame
	_check_page("IdentityPage")
	_check(_button("IdentityOption_IDENTITY_FRANI_MERCHANT").button_pressed, "退回保留已选身份")
	_check(_label("IdentityDetailTitle").text == "弗拉尼的商人", "退回恢复身份详情")

	# 退回文化层，保留已选文化，并保留路线中的身份。
	_button("BackButton").pressed.emit()
	await get_tree().process_frame
	_check_page("CulturePage")
	_check(_button("CultureOption_CULTURE_BUGIDO").button_pressed, "退回保留已选文化")
	_check_route("布吉多人", "弗拉尼的商人")

	# 再次确认，身份选择保留。
	_button("ConfirmButton").pressed.emit()
	await get_tree().process_frame
	_check_page("IdentityPage")
	_check(_button("IdentityOption_IDENTITY_FRANI_MERCHANT").button_pressed, "重新进入保留原身份")
	_button("ConfirmButton").pressed.emit()
	await get_tree().process_frame
	_check_page("PreviewPage")

	# 只有预览层确认才创建世界并进入大地图。
	_button("ConfirmButton").pressed.emit()
	await _wait_scene_change()

	_check(
		GameManager.player_identity_id == "IDENTITY_FRANI_MERCHANT",
		"确认传递身份 ID"
	)
	_check(
		GameManager.player_identity_category_id == "COMMONER",
		"确认传递身份类别 ID"
	)
	_check(
		GameManager.player_culture_id == "CULTURE_BUGIDO",
		"确认传递文化 ID"
	)
	_check(GameManager.world_context != null, "开始游戏后创建世界")
	_check(
		get_tree().current_scene != null
			and get_tree().current_scene.name == "WorldMap",
		"开始游戏后进入现有大地图流程"
	)


func _check_catalog() -> void:
	var catalog := IdentityCatalog.load_default()
	_check(catalog != null, "文化/身份配置可加载")
	if catalog == null:
		return

	var cultures: Array = catalog.get_enabled_cultures()
	_check(cultures.size() == 3, "默认有三个文化")
	if cultures.size() == 3:
		var first: Variant = cultures[0]
		var second: Variant = cultures[1]
		var third: Variant = cultures[2]
		_check(
			first.culture_id == "CULTURE_DORAMAN"
				and first.display_name == "多拉曼人",
			"多拉曼按 sort_order 排首位"
		)
		_check(second.culture_id == "CULTURE_BUGIDO", "布吉多排第二位")
		_check(third.culture_id == "CULTURE_LORRIS", "洛里斯排第三位")
		for value: Variant in cultures:
			_check(
				not str(value.description).strip_edges().is_empty(),
				"文化 %s 包含背景描述" % str(value.culture_id)
			)
			_check(
				not value.talent_lines.is_empty(),
				"文化 %s 包含天赋展示行" % str(value.culture_id)
			)

	var doraman: Array = catalog.get_enabled_identities_for_culture(
		"CULTURE_DORAMAN"
	)
	var bugido: Array = catalog.get_enabled_identities_for_culture("CULTURE_BUGIDO")
	var lorris: Array = catalog.get_enabled_identities_for_culture("CULTURE_LORRIS")
	_check(doraman.size() == 2, "多拉曼有两个身份路线")
	_check(bugido.size() == 2, "布吉多有两个身份路线")
	_check(lorris.size() == 2, "洛里斯有两个身份路线")
	if not bugido.is_empty():
		_check(
			bugido[0].category_id == "NOBLE"
				and bugido[1].category_id == "COMMONER",
			"每个文化先贵族后平民"
		)
	for group: Array in [doraman, bugido, lorris]:
		for value: Variant in group:
			_check(
				not str(value.description).strip_edges().is_empty(),
				"身份 %s 包含背景故事" % str(value.identity_id)
			)
			_check(
				not value.bonus_lines.is_empty(),
				"身份 %s 包含加成展示行" % str(value.identity_id)
			)


func _check_vaila_assets() -> void:
	var vaila := load("res://Data/Families/family_vaila.tres") as FamilyConfig
	var player := load("res://Data/Families/family_player.tres") as FamilyConfig
	_check(vaila != null, "瓦伊拉家族配置可加载")
	if vaila == null:
		return

	var paths: Array[String] = [
		vaila.banner_texture_path,
		vaila.tabard_primary_texture_path,
		vaila.tabard_secondary_texture_path,
		vaila.leader_plume_texture_path,
		vaila.spear_texture_path,
	]
	for path: String in paths:
		_check(not path.is_empty(), "瓦伊拉家族美术路径已配置")
		if path.is_empty():
			continue
		var absolute_path: String = ProjectSettings.globalize_path(path)
		_check(FileAccess.file_exists(absolute_path), "瓦伊拉美术文件存在: %s" % path)
		var image := Image.new()
		_check(image.load(absolute_path) == OK, "瓦伊拉美术可解码: %s" % path)

	if player != null:
		_check(
			vaila.banner_texture_path != player.banner_texture_path,
			"瓦伊拉旗帜不复用玩家资源"
		)
		_check(
			vaila.tabard_primary_texture_path != player.tabard_primary_texture_path,
			"瓦伊拉罩袍不复用玩家资源"
		)
		_check(
			vaila.banner_texture_path.contains("瓦伊拉家族风格美术"),
			"瓦伊拉旗帜位于家族美术目录"
		)


func _check_page(page_name: String) -> void:
	var culture_page := _node("CulturePage") as Control
	var identity_page := _node("IdentityPage") as Control
	var preview_page := _node("PreviewPage") as Control
	_check(
		culture_page != null and identity_page != null and preview_page != null,
		"三个流程页面都存在"
	)
	if culture_page == null or identity_page == null or preview_page == null:
		return
	_check(
		culture_page.visible == (page_name == "CulturePage")
			and identity_page.visible == (page_name == "IdentityPage")
			and preview_page.visible == (page_name == "PreviewPage"),
		"当前显示页面为 %s" % page_name
	)


func _check_route(required_culture: String, required_detail: String) -> void:
	var route := _label("RouteLabel")
	_check(
		route.text.contains(required_culture) and route.text.contains(required_detail),
		"路线预览包含 %s / %s" % [required_culture, required_detail]
	)


func _bonus_texts(list_name: String) -> Array[String]:
	var result: Array[String] = []
	var list := _node(list_name)
	if list == null:
		return result
	for child: Node in list.get_children():
		var label := child as Label
		if label != null:
			result.append(label.text.trim_prefix("· "))
	return result


func _node(node_name: String) -> Node:
	return _screen.find_child(node_name, true, false)


func _button(node_name: String) -> Button:
	return _node(node_name) as Button


func _label(node_name: String) -> Label:
	return _node(node_name) as Label


func _is_full_screen(screen: Control) -> bool:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	return is_equal_approx(screen.size.x, viewport_size.x) \
		and is_equal_approx(screen.size.y, viewport_size.y)


func _wait_scene_change() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


func _cleanup() -> void:
	GameManager.enter_main_menu()
	if is_instance_valid(_menu):
		_menu.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[identity-ui] OK: %s" % message)
	else:
		_failed = true
		push_error("[identity-ui] FAIL: %s" % message)
