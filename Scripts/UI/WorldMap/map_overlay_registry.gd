class_name MapOverlayRegistry
extends RefCounted
## 大地图覆盖层登记簿。
##
## 只做两件事：
## 1. 记录覆盖层控件，判断当前是否有阻塞输入的模态覆盖层；
## 2. 为每个覆盖层保管一个暂停原因（acquire/release 幂等）。
## 不创建 UI、不读写世界数据；控件显隐仍由各面板自己负责。

var _entries: Dictionary = {}


## pause_reason 为空时只登记可见性，不参与暂停。
## ignored_when_ignoring_settlement=true 对应“建筑面板打开时仍允许其他覆盖层”。
func register_overlay(
	id: String,
	node: Control,
	pause_reason: StringName = &"",
	ignored_when_ignoring_settlement: bool = false
) -> void:
	_entries[id] = {
		"node": node,
		"pause_reason": pause_reason,
		"ignore_settlement_exempt": ignored_when_ignoring_settlement,
		"pause_held": false,
	}


## 幂等：同一覆盖层重复打开不会重复压入暂停原因。
func acquire_pause(id: String) -> void:
	var entry: Dictionary = _entries.get(id, {})
	if entry.is_empty() or bool(entry["pause_held"]):
		return
	var reason: StringName = entry["pause_reason"]
	if reason.is_empty():
		return
	TimeManager.push_pause(reason)
	entry["pause_held"] = true


## 幂等：未持有暂停原因时不做任何操作，不会误弹其他覆盖层的暂停。
func release_pause(id: String) -> void:
	var entry: Dictionary = _entries.get(id, {})
	if entry.is_empty() or not bool(entry["pause_held"]):
		return
	var reason: StringName = entry["pause_reason"]
	entry["pause_held"] = false
	if not reason.is_empty():
		TimeManager.pop_pause(reason)


## 场景退出时的兜底：释放本场景持有的全部覆盖层暂停。
func release_all() -> void:
	for id: String in _entries:
		release_pause(id)


## 是否有可见的模态覆盖层。ignore_settlement=true 时忽略地点面板，
## 用于“建筑面板打开时仍允许百科/部队/背包/事件入口”的权限判断。
func has_blocking_overlay(ignore_settlement: bool = false) -> bool:
	for entry: Dictionary in _entries.values():
		var node := entry["node"] as Control
		if node == null or not is_instance_valid(node) or not node.visible:
			continue
		if ignore_settlement and bool(entry["ignore_settlement_exempt"]):
			continue
		return true
	return false
