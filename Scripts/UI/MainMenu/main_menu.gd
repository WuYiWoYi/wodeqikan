extends Control
## 主菜单占位。UI 只发起意图，不直接修改游戏数据。

func _ready() -> void:
	# TODO(阶段1)：构建 新游戏 / 继续 / 读取 / 设置 / 退出。
	pass


func _on_new_game_pressed() -> void:
	GameManager.start_new_game()


func _on_continue_pressed() -> void:
	# TODO(阶段0)：读取最近存档。
	push_warning("继续游戏尚未实现")


func _on_quit_pressed() -> void:
	GameManager.quit_game()
