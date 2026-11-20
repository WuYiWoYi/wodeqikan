class_name WorldContext
extends Node
## 一局游戏的持久化世界容器。
##
## 生命周期：新游戏/读档时由 GameManager 创建，跨大地图、小场景、战斗场景持续存在；
## 返回主菜单时销毁。场景节点只读取这里的实体数据。

const DEFAULT_WORLD_SIZE: Vector2 = Vector2(3000.0, 2000.0)

var id_generator: IdGenerator = IdGenerator.new()
var unit_manager: UnitManager = UnitManager.new()
var party_manager: PartyManager = PartyManager.new()
var settlement_manager: SettlementManager = SettlementManager.new()
var world_map_manager: WorldMapManager = WorldMapManager.new()
var ai_manager: AIManager = AIManager.new()
var battle_manager: BattleManager = BattleManager.new()
var dialogue_manager: DialogueManager = DialogueManager.new()
var world_simulation: WorldSimulation = WorldSimulation.new()

var world_id: String = ""
var world_created_at: String = ""
var world_size: Vector2 = DEFAULT_WORLD_SIZE
var player_party_id: String = ""


func _ready() -> void:
	_wire_managers()
	if not TimeManager.world_tick.is_connected(world_simulation.on_world_tick):
		TimeManager.world_tick.connect(world_simulation.on_world_tick)


func _exit_tree() -> void:
	if TimeManager.world_tick.is_connected(world_simulation.on_world_tick):
		TimeManager.world_tick.disconnect(world_simulation.on_world_tick)


func get_player_party() -> PartyData:
	return party_manager.get_party(player_party_id)


func is_valid_world() -> bool:
	if world_id.is_empty():
		return false
	if player_party_id.is_empty() or party_manager.get_party(player_party_id) == null:
		return false
	if settlement_manager.get_all_settlements().is_empty():
		return false
	return true


## 聚合当前世界的权威数据。表现节点和 UI 状态不进入存档。
func to_save_data() -> SaveData:
	var save := SaveData.new()
	save.world_id = world_id
	save.world_created_at = world_created_at
	save.world_size = world_size
	save.world_elapsed_seconds = TimeManager.world_elapsed_seconds
	save.world_base_speed = TimeManager.get_base_world_speed()
	save.id_counters = id_generator.to_dict()
	save.player_party_id = player_party_id
	save.player = {"party_id": player_party_id}
	save.world_state = {}
	save.scene_state = {}
	save.units = unit_manager.to_dict()
	save.parties = party_manager.to_dict()
	save.settlements = settlement_manager.to_dict()
	save.lords = {}
	save.factions = {}
	save.quests = {}
	return save


## 从存档恢复权威数据。调用前 WorldContext 必须已经加入场景树并完成 manager 装配。
func load_from_save_data(save: SaveData) -> bool:
	if save == null:
		return false

	world_id = save.world_id
	world_created_at = save.world_created_at
	world_size = save.world_size if save.world_size != Vector2.ZERO else DEFAULT_WORLD_SIZE
	player_party_id = save.player_party_id
	if player_party_id.is_empty():
		player_party_id = str(save.player.get("party_id", ""))

	id_generator.restore_from(save.id_counters)
	unit_manager.load_from_dict(save.units)
	party_manager.load_from_dict(save.parties)
	settlement_manager.load_from_dict(save.settlements)
	world_map_manager.world_bounds = Rect2(Vector2.ZERO, world_size)

	# 两个仓储分别反序列化成功，不代表双向归属一致；恢复完成后统一校验。
	# 校验失败时不自动改写存档数据，保留现场并拒绝加载。
	var membership_errors: Array[String] = party_manager.validate_membership_consistency()
	if not membership_errors.is_empty():
		for message: String in membership_errors:
			push_error("[WorldContext] 士兵-部队成员关系校验失败: %s" % message)
		return false

	return is_valid_world()


func _wire_managers() -> void:
	unit_manager.setup(id_generator)
	party_manager.setup(unit_manager, id_generator)
	settlement_manager.setup(id_generator)
	world_map_manager.setup(party_manager)
	ai_manager.setup(unit_manager, party_manager)
	battle_manager.setup(unit_manager, party_manager, id_generator)
	world_simulation.bind(unit_manager, party_manager, world_map_manager, ai_manager)
