extends Node2D
## 临时排序验证：后排角色武器 z=-10 与“前排角色身体 z=-50”交叉时，
## 角色整体 z 波段是否能让前排整体压住后排。需要窗口渲染，不能 headless。
## 运行：Godot_v4.6.1-stable_win64_console.exe --path . res://Tests/_debug/sort_probe.tscn

const BODY_SIZE := Vector2(40.0, 80.0)
const WEAPON_SIZE := Vector2(120.0, 10.0)

var _texture: Texture2D = null


func _ready() -> void:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	_texture = ImageTexture.create_from_image(image)
	var root := Node2D.new()
	root.y_sort_enabled = true
	add_child(root)
	# 左侧：按 UnitActor 的方式给角色根节点分配整体 z 波段。
	_build_pair(root, 300.0, true)
	# 右侧：所有角色根节点 z=0，作为可复现旧问题的对照。
	_build_pair(root, 900.0, false)

	for i: int in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var viewport_image := get_viewport().get_texture().get_image()
	viewport_image.save_png("user://sort_probe.png")
	var banded := _hex(viewport_image, 300, 338)
	var legacy := _hex(viewport_image, 900, 338)
	print("[probe] banded P1=", banded, " legacy P1=", legacy)
	var proxy_ok: bool = banded == "ff0000" and legacy == "0000ff"
	var banded_violations: int = await _actual_actor_overlap_violations(
		root, 400.0, true
	)
	var legacy_violations: int = await _actual_actor_overlap_violations(
		root, 1200.0, false
	)
	print(
		"[probe] actual actor overlap violations banded=", banded_violations,
		" legacy=", legacy_violations
	)
	print("[probe] saved ", ProjectSettings.globalize_path("user://sort_probe.png"))
	var ok: bool = (
		proxy_ok and banded_violations == 0 and legacy_violations > 0
	)
	print("[probe] ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)


## 用真实 UnitActor（前排骑乘、后排步兵，20 像素前后重叠）比较“仅前排”与
## “前后排同时可见”两张画面：前排不透明像素处若被后排改变，即为跨角色穿插。
func _actual_actor_overlap_violations(
	root: Node2D, center_x: float, banded: bool
) -> int:
	var config := load("res://Data/Units/infantry_militia.tres") as UnitConfig
	if config == null:
		return 1
	var units := UnitManager.new()
	units.setup(IdGenerator.new())
	var front := _spawn_real_actor(
		root, units, config, Vector2(center_x, 560.0), true, 1 if banded else 0
	)
	var rear := _spawn_real_actor(
		root, units, config, Vector2(center_x, 540.0), false, 0
	)
	if front == null or rear == null:
		return 1
	front.visible = false
	rear.visible = false
	for i: int in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var empty := get_viewport().get_texture().get_image()
	front.visible = true
	for i: int in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var front_only := get_viewport().get_texture().get_image()
	rear.visible = true
	for i: int in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var both := get_viewport().get_texture().get_image()
	front_only.save_png("user://sort_probe_front_only.png")
	both.save_png("user://sort_probe_both.png")

	var violations: int = 0
	var covered: int = 0
	for y: int in range(380, 620):
		for px: int in range(int(center_x) - 120, int(center_x) + 120):
			var front_color := front_only.get_pixel(px, y)
			if front_color.is_equal_approx(empty.get_pixel(px, y)):
				continue
			covered += 1
			var both_color := both.get_pixel(px, y)
			if not both_color.is_equal_approx(front_color):
				violations += 1
	print("[probe] front silhouette pixels=", covered)
	return violations


func _spawn_real_actor(
	root: Node2D,
	units: UnitManager,
	config: UnitConfig,
	spawn_position: Vector2,
	mounted: bool,
	rank: int
) -> UnitActor:
	var unit: UnitData = units.create_unit(config, "FACTION_ENEMY")
	unit.is_mounted = mounted
	var state := BattleUnitState.new()
	state.unit_id = unit.unit_id
	state.party_id = "PARTY_PROBE"
	state.battle_hp = unit.max_hp
	state.alive = true
	state.battle_position = spawn_position
	var actor := UnitActor.new()
	root.add_child(actor)
	actor.setup(unit, state, false)
	actor.apply_sort_rank(rank)
	actor.set_process(false)
	if actor.visual != null and actor.visual.get_human_visual() != null:
		actor.visual.get_human_visual().set_process(false)
	return actor


func _build_pair(parent: Node2D, x: float, banded: bool) -> void:
	var front := Node2D.new()
	front.position = Vector2(x, 400.0)
	front.z_index = 72 if banded else 0
	parent.add_child(front)
	var back := Node2D.new()
	back.position = Vector2(x, 380.0)
	back.z_index = 0
	parent.add_child(back)
	_add_rect(front, Vector2(-20.0, -80.0), BODY_SIZE, -50, Color.RED)
	_add_rect(back, Vector2(-20.0, -80.0), BODY_SIZE, -50, Color.BLUE)
	# 后排角色的武器 z 更高（-10），与“前排角色身体 z=-50”交叉。
	_add_rect(back, Vector2(-60.0, -45.0), WEAPON_SIZE, -10, Color.BLUE)


func _add_rect(
	parent: Node, pos: Vector2, size: Vector2, z: int, color: Color
) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = _texture
	sprite.centered = false
	sprite.position = pos
	sprite.scale = size / 4.0
	sprite.z_index = z
	sprite.modulate = color
	parent.add_child(sprite)


func _hex(image: Image, x: int, y: int) -> String:
	var color := image.get_pixel(x, y)
	return color.to_html(false)
