class_name WorldContext
extends Node
## 一局游戏的持久化世界容器。
##
## 生命周期：新游戏/读档时由 GameManager 创建，跨大地图、小场景、战斗场景持续存在；
## 返回主菜单时销毁。场景节点只读取这里的实体数据。

var id_generator: IdGenerator = IdGenerator.new()
var unit_manager: UnitManager = UnitManager.new()
var party_manager: PartyManager = PartyManager.new()
var world_map_manager: WorldMapManager = WorldMapManager.new()
var ai_manager: AIManager = AIManager.new()
var battle_manager: BattleManager = BattleManager.new()
var dialogue_manager: DialogueManager = DialogueManager.new()
var world_simulation: WorldSimulation = WorldSimulation.new()


func _ready() -> void:
	_wire_managers()
	if not TimeManager.world_tick.is_connected(world_simulation.on_world_tick):
		TimeManager.world_tick.connect(world_simulation.on_world_tick)


func _exit_tree() -> void:
	if TimeManager.world_tick.is_connected(world_simulation.on_world_tick):
		TimeManager.world_tick.disconnect(world_simulation.on_world_tick)


func _wire_managers() -> void:
	unit_manager.setup(id_generator)
	party_manager.setup(unit_manager, id_generator)
	world_map_manager.setup(party_manager)
	ai_manager.setup(unit_manager, party_manager)
	battle_manager.setup(unit_manager, party_manager, id_generator)
	world_simulation.bind(unit_manager, party_manager, world_map_manager, ai_manager)
