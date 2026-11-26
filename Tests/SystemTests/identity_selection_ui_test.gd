extends Node
## 新游戏身份选择全屏流程测试：
## 主菜单跳转、全屏独立场景、纵向布局、选中状态、最终确认路径与提交。
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

	var packed := load("res://Scenes/MainMenu/main_menu.tscn") as PackedScene
	_check(packed != null, "主菜单场景可加载")
	if packed == null:
		return
	_menu = packed.instantiate() as Control
	get_tree().root.add_child(_menu)
	get_tree().current_scene = _menu
	await get_tree().process_frame

	var slot_before := SaveManager.get_latest_save_slot()
	var new_game_button := _menu.find_child("NewGameButton", true, false) as Button
	_check(new_game_button != null, "新游戏按钮存在")
	if new_game_button == null:
		return
	new_game_button.pressed.emit()
	await _wait_scene_change()

	_check(not is_instance_valid(_menu), "主菜单已释放，身份界面为独立场景")
	_screen = get_tree().current_scene as Control
	_check(_screen != null and _screen.name == "IdentitySelect", "进入全屏身份选择场景")
	if _screen == null:
		return
	_check(_screen.find_child("Background", true, false) != null, "身份界面拥有独立背景")
	_check(_is_full_screen(_screen), "身份界面覆盖整个窗口")

	var category_page := _screen.find_child("CategoryPage", true, false) as Control
	var identity_page := _screen.find_child("IdentityPage", true, false) as Control
	var confirm_page := _screen.find_child("ConfirmPage", true, false) as Control
	_check(
		category_page != null and category_page.visible
			and identity_page != null and not identity_page.visible
			and confirm_page != null and not confirm_page.visible,
		"首先显示一级类别页"
	)
	_check(GameManager.world_context == null, "进入身份界面不创建世界")

	var noble_button := _screen.find_child("CategoryButton_NOBLE", true, false) as Button
	var commoner_button := _screen.find_child(
		"CategoryButton_COMMONER", true, false
	) as Button
	_check(noble_button != null and noble_button.text == "贵族", "一级显示贵族")
	_check(commoner_button != null and commoner_button.text == "平民", "一级显示平民")
	if category_page == null or identity_page == null or confirm_page == null \
			or noble_button == null or commoner_button == null:
		return
	await get_tree().process_frame
	_check(noble_button.get_parent() is VBoxContainer, "类别选项使用纵向容器")
	_check(
		noble_button.position.y < commoner_button.position.y,
		"贵族与平民上下排列"
	)
	_check(
		is_equal_approx(noble_button.position.x, commoner_button.position.x),
		"类别选项保持同一列"
	)

	# 一级返回主菜单，再重新进入，验证全屏场景可正常往返且从干净状态开始。
	var cancel_button := _screen.find_child(
		"IdentityCancelButton", true, false
	) as Button
	_check(cancel_button != null, "一级提供返回主菜单按钮")
	if cancel_button != null:
		cancel_button.pressed.emit()
		await _wait_scene_change()
		_check(
			get_tree().current_scene != null
				and get_tree().current_scene.name == "MainMenu",
			"一级可返回主菜单"
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
			"可重新进入身份选择场景"
		)
		if _screen == null:
			return
		category_page = _screen.find_child("CategoryPage", true, false) as Control
		identity_page = _screen.find_child("IdentityPage", true, false) as Control
		confirm_page = _screen.find_child("ConfirmPage", true, false) as Control
		noble_button = _screen.find_child(
			"CategoryButton_NOBLE", true, false
		) as Button
		commoner_button = _screen.find_child(
			"CategoryButton_COMMONER", true, false
		) as Button
		await get_tree().process_frame
		_check(
			not noble_button.button_pressed and not commoner_button.button_pressed,
			"重新进入后不保留旧类别选择"
		)

	noble_button.pressed.emit()
	await get_tree().process_frame
	_check(not category_page.visible and identity_page.visible, "选择贵族进入二级页")
	var page_title := _screen.find_child("IdentityPageTitle", true, false) as Label
	_check(
		page_title != null and page_title.text.contains("贵族"),
		"二级页标题匹配类别"
	)

	var second_son := _screen.find_child(
		"IdentityButton_NOBLE_SECOND_SON", true, false
	) as Button
	var expedition := _screen.find_child(
		"IdentityButton_EXPEDITION_LEADER", true, false
	) as Button
	_check(
		second_son != null and second_son.text == "没落贵族的次子",
		"贵族显示没落贵族的次子"
	)
	_check(
		expedition != null and expedition.text == "远征军领队",
		"贵族显示远征军领队"
	)
	_check(
		_screen.find_child("IdentityButton_ADVENTURER", true, false) == null,
		"贵族页不显示平民身份"
	)
	var option_scroll := _screen.find_child(
		"IdentityOptionScroll", true, false
	) as ScrollContainer
	_check(
		option_scroll != null and option_scroll.get_parent() == identity_page,
		"身份选项区域位于二级页并可滚动"
	)
	if second_son == null or expedition == null:
		return
	await get_tree().process_frame
	_check(second_son.get_parent() is VBoxContainer, "身份选项使用纵向容器")
	_check(
		second_son.position.y < expedition.position.y,
		"贵族身份选项上下排列"
	)
	_check(
		is_equal_approx(second_son.position.x, expedition.position.x),
		"身份选项保持同一列"
	)

	var story := _screen.find_child("StoryLabel", true, false) as Label
	var story_title := _screen.find_child("StoryTitle", true, false) as Label
	var selection_label := _screen.find_child("SelectionLabel", true, false) as Label
	_check(
		story != null and story.text == "从下方选择一个身份，查看他的来历。",
		"未选择时显示占位故事"
	)
	_check(story_title != null and not story_title.visible, "未选择时不显示身份标题")
	_check(
		_screen.find_child("CompleteSelectionButton", true, false) == null,
		"二级没有完成选择按钮"
	)
	_check(
		_find_button_by_text(_screen, "完成选择") == null
			and _find_button_by_text(_screen, "确认选择") == null
			and _find_button_by_text(_screen, "下一步") == null,
		"不存在额外的中间操作按钮"
	)
	if story == null or story_title == null or selection_label == null:
		return

	# 点击具体身份立即进入最终确认，没有中间按钮。
	second_son.button_pressed = true
	await get_tree().process_frame
	_check(confirm_page.visible and not identity_page.visible, "点击身份立即进入最终确认页")
	var path_label := _screen.find_child("ConfirmPathLabel", true, false) as Label
	_check(path_label != null, "确认页包含路径展示")
	if path_label != null:
		_check(
			path_label.text.contains("贵族") and path_label.text.contains("没落贵族的次子")
				and path_label.text.contains("→"),
			"确认页展示完整选择路径"
		)
	_check(second_son.button_pressed, "身份按钮保持选中状态")
	_check(story.text.contains("城堡还在"), "选中身份的背景故事已更新")
	_check(
		story_title.visible and story_title.text == "没落贵族的次子",
		"故事区标题显示身份名称"
	)
	_check(
		selection_label.text.contains("没落贵族的次子"),
		"当前选择明确可见"
	)
	_check(GameManager.world_context == null, "进入确认页不创建世界")
	_check(SaveManager.get_latest_save_slot() == slot_before, "进入确认页不创建存档")

	# 返回修改回到一级类别页，并保留已有选择。
	var return_modify := _screen.find_child(
		"ReturnModifyButton", true, false
	) as Button
	_check(return_modify != null, "确认页提供返回修改")
	if return_modify != null:
		return_modify.pressed.emit()
		await get_tree().process_frame
	_check(category_page.visible and not identity_page.visible, "返回修改回到一级类别页")
	var noble_again := _screen.find_child(
		"CategoryButton_NOBLE", true, false
	) as Button
	_check(noble_again != null and noble_again.button_pressed, "返回修改保留类别状态")
	if noble_again != null:
		noble_again.pressed.emit()
		await get_tree().process_frame
	_check(identity_page.visible, "可重新进入贵族身份列表")
	var second_son_restored := _screen.find_child(
		"IdentityButton_NOBLE_SECOND_SON", true, false
	) as Button
	_check(
		second_son_restored != null and second_son_restored.button_pressed,
		"重新进入时恢复已选身份"
	)
	_check(story.text.contains("城堡还在"), "恢复已选身份的背景故事")
	_check(
		_screen.find_child("CompleteSelectionButton", true, false) == null,
		"二级仍没有完成选择按钮"
	)

	# 二级返回一级；再次点击其他身份立即重新进入确认页。
	var back_button := _screen.find_child(
		"IdentityBackButton", true, false
	) as Button
	_check(back_button != null, "二级提供返回按钮")
	if back_button != null:
		back_button.pressed.emit()
		await get_tree().process_frame
	_check(category_page.visible and not identity_page.visible, "二级可返回一级")
	noble_again = _screen.find_child("CategoryButton_NOBLE", true, false) as Button
	_check(noble_again != null and noble_again.button_pressed, "返回一级后保留类别状态")
	if noble_again != null:
		noble_again.pressed.emit()
		await get_tree().process_frame
	var expedition_again := _screen.find_child(
		"IdentityButton_EXPEDITION_LEADER", true, false
	) as Button
	_check(expedition_again != null, "贵族身份列表仍可用")
	if expedition_again == null:
		return
	expedition_again.button_pressed = true
	await get_tree().process_frame
	_check(confirm_page.visible and not identity_page.visible, "点击其他身份立即重新进入确认页")
	_check(path_label.text.contains("远征军领队"), "确认路径切换到新身份")
	_check(not path_label.text.contains("次子"), "确认路径不保留旧身份")

	# 返回修改后再改回另一身份，确认路径同步。
	return_modify.pressed.emit()
	await get_tree().process_frame
	_check(category_page.visible, "返回修改再次回到一级")
	noble_again = _screen.find_child("CategoryButton_NOBLE", true, false) as Button
	noble_again.pressed.emit()
	await get_tree().process_frame
	second_son = _screen.find_child(
		"IdentityButton_NOBLE_SECOND_SON", true, false
	) as Button
	second_son.button_pressed = true
	await get_tree().process_frame
	_check(path_label.text.contains("没落贵族的次子"), "修改身份后确认路径同步")
	_check(not path_label.text.contains("远征军领队"), "确认路径不保留上一身份")

	# 返回修改 -> 切换类别 -> 旧身份清空。
	return_modify.pressed.emit()
	await get_tree().process_frame
	commoner_button = _screen.find_child(
		"CategoryButton_COMMONER", true, false
	) as Button
	commoner_button.pressed.emit()
	await get_tree().process_frame
	_check(identity_page.visible, "进入平民二级页")
	_check(
		_screen.find_child("IdentityButton_NOBLE_SECOND_SON", true, false) == null,
		"切换类别不显示旧类别身份"
	)
	_check(
		_screen.find_child("IdentityButton_ADVENTURER", true, false) != null
			and _screen.find_child("IdentityButton_MERCHANT", true, false) != null
			and _screen.find_child("IdentityButton_BLACKSMITH", true, false) != null,
		"平民显示冒险家、商人、铁匠"
	)
	_check(selection_label.text.contains("未选择"), "切换类别后选择状态清空")
	_check(
		_screen.find_child("CompleteSelectionButton", true, false) == null,
		"平民页也没有完成选择按钮"
	)

	# 点击商人立即进入确认页。
	var merchant := _screen.find_child(
		"IdentityButton_MERCHANT", true, false
	) as Button
	merchant.button_pressed = true
	await get_tree().process_frame
	_check(confirm_page.visible and not identity_page.visible, "点击商人立即进入最终确认")
	_check(path_label.text.contains("平民") and path_label.text.contains("商人"), "确认路径为平民 → 商人")
	_check(story.text.contains("独轮车"), "商人背景故事已更新")
	_check(SaveManager.get_latest_save_slot() == slot_before, "最终确认前不创建存档")
	_check(GameManager.world_context == null, "最终确认前不初始化世界")
	_check(get_tree().current_scene == _screen, "点击身份后仍停留在身份选择场景")

	# 只有最终确认才提交选择并进入新游戏流程。
	var final_button := _screen.find_child(
		"FinalConfirmButton", true, false
	) as Button
	_check(final_button != null, "确认页提供最终确认按钮")
	if final_button != null:
		final_button.pressed.emit()
		await _wait_scene_change()

	_check(GameManager.player_identity_id == "MERCHANT", "最终确认传递身份 ID")
	_check(
		GameManager.player_identity_category_id == "COMMONER",
		"最终确认传递类别 ID"
	)
	_check(GameManager.world_context != null, "最终确认后创建世界")
	_check(get_tree().current_scene != null, "最终确认后存在当前场景")
	if get_tree().current_scene != null:
		_check(
			get_tree().current_scene.name == "WorldMap",
			"最终确认后进入现有新游戏流程"
		)


func _check_catalog() -> void:
	var catalog := IdentityCatalog.load_default()
	_check(catalog != null, "身份配置可加载")
	if catalog == null:
		return

	var categories := catalog.get_enabled_categories()
	_check(categories.size() == 2, "默认有两个身份类别")
	if categories.size() == 2:
		_check(
			categories[0].category_id == "NOBLE"
				and categories[0].display_name == "贵族",
			"贵族类别按 sort_order 排首位"
		)
		_check(
			categories[1].category_id == "COMMONER"
				and categories[1].display_name == "平民",
			"平民类别排第二位"
		)

	var nobles := catalog.get_enabled_identities("NOBLE")
	_check(nobles.size() == 2, "贵族类别有两个身份")
	if nobles.size() == 2:
		_check(
			nobles[0].identity_id == "NOBLE_SECOND_SON"
				and nobles[1].identity_id == "EXPEDITION_LEADER",
			"贵族身份按 sort_order 排序"
		)

	var commoners := catalog.get_enabled_identities("COMMONER")
	_check(commoners.size() == 3, "平民类别有三个身份")
	if commoners.size() == 3:
		_check(
			commoners[0].identity_id == "ADVENTURER"
				and commoners[1].identity_id == "MERCHANT"
				and commoners[2].identity_id == "BLACKSMITH",
			"平民身份按 sort_order 排序"
		)

	var all_identities: Array[IdentityDefinition] = []
	all_identities.append_array(nobles)
	all_identities.append_array(commoners)
	for identity: IdentityDefinition in all_identities:
		_check(
			not identity.description.strip_edges().is_empty(),
			"身份 %s 包含背景故事" % identity.identity_id
		)


func _find_button_by_text(root: Node, button_text: String) -> Button:
	for node: Node in root.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == button_text:
			return button
	return null


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
