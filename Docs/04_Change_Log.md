# 变更日志

只记录重要变更、架构调整和接口变化。日常小改动由 Git 历史承担。

---

## 2026-11-21 · 阶段 6 大地图战斗与小地图视角优化

### 新增

- `Scripts/Systems/Scene/scene_camera_rig.gd`：村庄与战斗共用摄像机；统一视野 `960×540`、跟随当前控制角色、`F` 自由视角、边界限制。
- `OffscreenBattleConfig` + `OffscreenBattleResolver` + `Data/Combat/offscreen_battle_default.tres`：离屏战斗按游戏小时结算战力/等级/骑乘/剩余生命与随机伤亡。
- `BattleMarker`：同一场 `BattleSession` 只显示一个战斗标记；战斗期间隐藏参战部队图标。
- `BattleSummaryPanel`：按 `side_index` 分组、同侧多部队并列、兵种/骑乘合并人数、伤亡实时刷新。
- `EventBus.battle_participants_updated`：每次离屏小时结算后通知 UI。
- 测试：`offscreen_battle_hourly_test`、`small_scene_camera_test`、`player_pursuit_encounter_test`、`world_map_battle_marker_test`。

### 变更

- 离屏战斗从“10 世界秒后一次性确定性结算”改为“每 1 游戏小时结算一次，最多 48 小时”；玩家加入保留已有伤亡与 HP，转换后不再进行离屏结算。
- `EncounterManager` 的遭遇意图增加玩家主动追击（`focus_party_id`）；同向移动目标也能在 50 世界单位内接触，接触后立即停止双方并清除旧目标，修复回弹/无法开战。
- 玩家遭遇面板新增“撤退”；撤退后恢复基础倍率并记录 90 世界单位拒绝锁，双方保留停止位置。
- 村庄摄像机从固定整图改为与战斗一致的跟随/自由视角；战斗摄像机保持 2 倍整数像素缩放。
- `battle_scene_test` 改为验证统一视野缩放；`player_control_test` 增加摄像机跟随与自由视角断言；`player_encounter_test` 更新为战斗/撤退两个选项。
- 未改变存档 Schema；摄像机、离屏计时、玩家追击焦点与战斗汇总均为运行时数据。

### 决策

- D078：村庄与战斗共用 `SceneCameraRig` 与统一视野。
- D079：离屏战斗按游戏小时结算伤亡。
- D080：玩家追击意图参与统一遭遇判定，遭遇面板提供撤退。
- D081：大地图同场战斗合并为一个标记与按战斗侧分组的汇总面板。

### 验证

- 新增测试全部通过：`offscreen_battle_hourly_test`、`small_scene_camera_test`、`player_pursuit_encounter_test`、`world_map_battle_marker_test`。
- 回归通过：`multi_party_battle_test`、`battle_result_test`、`ai_manager_test`、`battle_scene_test`、`player_control_test`、`player_encounter_test`、`player_battle_interaction_test`、`world_map_milestone6_test`、`world_map_input_test`、`party_dialogue_test`、`village_scene_test`、`village_flow_test`、`milestone2_flow_test`。
- 未执行非 headless 视觉截图与跨进程重启测试。
- 明确未实现：自由视角缩放/边缘拖动/手柄、伤兵/俘虏/士气、战斗标记点击详情与旁观模式。

---

## 2026-11-21 · 阶段 6 村庄场景、交互与部队管理

### 新增

- 村庄小场景 `Scenes/Village/village.tscn` + `Scripts/UI/Village/village_scene.gd`：玩家复用 `UnitData`/`UnitVisual`，村庄头人、距离交互、屏幕下方对话、5 秒越界倒计时与返回大地图。
- `SettlementData.scene_path`：村庄关联小场景；大地图地点面板增加“进入村庄”。
- `WorldMap.enter_village()`、`GameManager.current_settlement_id` / `pending_settlement_latch_id` / `small_scene_return_base_speed`：进入/返回及一次性地点交互锁。
- `UnitVisual.set_weapon_visible()` / `HumanVisual.set_weapon_visible()`：村庄仅隐藏武器表现，不修改装备数据。
- `DialogueData` + `DialogueManager` 数据驱动会话；`Data/Dialogues/village_elder.tres`。
- `PartyData.focus_party_id`：玩家追逐焦点；追逐中跳过村庄/无关部队/离屏战斗自动交互，敌对 AI 主动追击仍可遭遇。
- `PartyIcon` 只显示人数；`PartyHoverPanel` 显示部队名称与兵种/骑乘合并构成，不拦截地图操作。
- `ItemConfig` + `ItemManager`（`Data/Items/`）；晋升凭证 `promotion_rank_token`。
- `PlayerProfile.can_afford()` / `spend_gold()`；`PartyManager.get_total_wage()`。
- `UnitConfig.tier` / `daily_wage` / `promotion_*`；`UnitData.wage`；`UnitManager.promote_tier()`。
- 三级兵种配置：民兵 10/50、职业步兵 20/100、新增小贵族 25/180；工资 2/5/10。
- 部队面板：金币/工资、tier、坐骑下拉与装备/卸下、晋升按钮。
- 世界日历：1103-01-01 起点、6 秒 = 1 小时、144 秒 = 1 天、30 天/月、12 月/年、时间段；大地图显示年月日 + 时间段。
- 测试：`unit_tier_wage_test`、`time_calendar_test`、`village_scene_test`、`village_flow_test`、`world_map_milestone6_test`、`party_economy_ui_test`。

### 变更

- 新游戏玩家部队仍为 7 人；测试马匹库存 3 → 4（1 匹留在背包）；新增 2 个晋升凭证测试库存。
- 大地图地点自动交互在玩家追逐目标时跳过；返回村庄后使用一次性锁避免立即重开。
- 大地图时间 UI 从“第 N 天 HH:MM:SS”改为“年月日 + 时间段”。
- 部队图标去掉名称标签，只显示人数；悬浮面板负责简要构成。
- 三级基础属性调整导致 `unit_manager_test`、`stat_calculator_test`、`unit_party_serialization_test`、`mounted_unit_test`、`battle_result_test`、`party_panel_test`、`combat_attack_rules_test`、`unit_controller_test`、`battle_manager_test` 的预期数值同步更新。
- 未改变存档 Schema；`wage` / `scene_path` / `inventory_counts` 均为带安全默认值的增量字段。

### 决策

- D071：三级兵种与经验等级分离，工资绑定兵种等级。
- D072：晋升通过配置链路 + 消耗品，保留等级/经验/装备。
- D073：玩家追逐焦点抑制无关自动交互。
- D074：村庄作为只读小场景，进入/返回使用暂停栈与一次性交互锁。
- D075：世界日历由累计秒数换算，采用 30 天简化历法。
- D076：部队图标只显示人数，悬浮面板负责详情。
- D077：新游戏测试库存调整为 4 匹马与 2 个晋升凭证。

### 验证

- 新增测试全部通过：`unit_tier_wage_test`、`time_calendar_test`、`village_scene_test`、`village_flow_test`、`world_map_milestone6_test`、`party_economy_ui_test`。
- 回归通过：`unit_manager_test`、`stat_calculator_test`、`unit_party_serialization_test`、`mounted_unit_test`、`battle_result_test`、`party_panel_test`、`combat_attack_rules_test`、`unit_controller_test`、`battle_manager_test`、`battle_scene_test`、`player_control_test`、`battle_formation_test`、`battle_side_result_test`、`battle_retreat_test`、`ai_manager_test`、`faction_vision_test`、`multi_party_battle_test`、`party_dialogue_test`、`player_encounter_test`、`player_battle_interaction_test`、`ai_encounter_flow_test`、`world_map_input_test`、`milestone2_flow_test`、`skeleton_smoke_test`、`milestone1_test`、`milestone1_flow_test`、`main_menu_ui_test`。
- 未执行非 headless 村庄截图与跨进程重启测试。
- 明确未实现：村庄商店/招募/任务/好感度、城镇/城堡小场景、工资扣除、完整背包 UI、复杂对话树、正式美术。

---

## 2026-11-21 · 骑兵动画幅度调整与影子优化

### 变更

- 马腿局部动作：前后伸展 `0.25 → 0.6 px`、旋转 `0.01 → 0.02 rad`、上下位移保持 `0 px`；前/后腿组关系与 `0.12 rad` 错位不变。
- 骑兵整体跑动起伏：`RUN_BOB_AMPLITUDE 5.6 → 4.2`；马身俯仰、拉伸/压缩、骑手跟随与腿部挂载关系不变。
- 骑马影子：新增基于马身垂直偏移的平滑响应；抬高时最多缩小 `4%`、变淡 `15%`，回落时恢复；位置、资源与层级不变。
- 人物腿部局部参数、人物/马腿 Pivot、战斗规则、单位属性与存档均未修改。

### 验证

- 自动化通过：`unit_visual_test`、`mounted_unit_test`、`party_panel_test`。
- 新增断言：骑兵整体起伏上限降低；马腿局部伸展 ≥ `0.45 px`；影子抬高时缩小/变淡、回落恢复；影子位置不变。
- 非 headless：`locomotion/run_1..4` / `idle`、`visual_probe_party_foot*` / `mounted*` 重新渲染检查。

---

## 2026-11-21 · 人马腿部挂载关系与局部动画优化

### 变更

- 人物双腿从 `HumanVisual` 直接子节点改为 `UpperBody` 的子节点；马腿从 `HorseVisual` 直接子节点改为 `HorseBodyRig` 的子节点。
- 两个父节点 `z_index = 0`，`VisualLayers` 的最终遮挡关系保持不变；影子仍不参与身体变换。
- 每帧先设置父级整体变换，再设置腿部局部变换；不做 Transform 累加。
- 人物腿部旋转中心：实际历史为 3 px，本轮再 +3 px → `LEG_PIVOT_DROP_Y = 6.0`。
- 马腿旋转中心：实际历史为 6 px，本轮再 +3 px → `LEG_PIVOT_DROP_Y = 9.0`。
- 人物局部步态：`0.2 px / 0 px / 0.005 rad`。
- 马腿局部动作：前后伸展 `0.25 px`、旋转 `0.01 rad`、上下位移 `0 px`；前/后组关系与 `0.12 rad` 错位保留。
- 腿部挂载调整不改变人物/马匹其他锚点、骑手跟随、攻击动画或 UI 预览架构。

### 验证

- 自动化通过：`unit_visual_test`、`mounted_unit_test`、`party_panel_test`。
- 新增断言：人物双腿父节点为 `UpperBody`、马腿父节点为 `HorseBodyRig`；人物/马腿 global position 随身体整体运动；枢轴 6/9 px 与可见位置不变；局部摆幅上限。
- 非 headless：`locomotion/run_1..4` / `idle`、`visual_probe_party_foot*` / `mounted*` 重新渲染。
- 未改变存档 Schema、战斗规则、单位属性、装备或部件层级。

---

## 2026-11-21 · 人马腿部动画幅度与战马整体跃动优化

### 变更

- 马腿旋转中心：`HorseVisual.LEG_PIVOT_DROP_Y 3.0 → 6.0`（累计，含上一轮 3 px）；`offset.y` 与基础位置按 6 px 补偿，可见位置不变。
- 马腿幅度：前后伸展 `3.5 → 1.5 px`、旋转 `0.09 → 0.04 rad`、上下位移 `0.25 → 0.10 px`；组内 `0.12 rad` 错位保留。
- 马身整体跃动：跑动起伏 `4.5 → 5.6`（约 +24%），伸展阶段向上、收缩阶段向下；俯仰 `0.022 → 0.028 rad`，横向拉伸 `2% → 2.8%`，纵向压缩 `0.8% → 1.2%`。
- 马头：独立摆动 `0.05 → 0.04 rad`、独立起伏 `0.8 → 0.55 px`。
- 骑手跟随：`UnitVisual` 先更新马匹，再把 `get_body_offset_y()` 传给 `HumanVisual`；骑乘人物整体 y = -15 + 马身偏移，上半身独立起伏缩为 20%。
- 步兵腿部：`RUN_LEG_SWING_X 1.5 → 0.8`、`RUN_LEG_LIFT_Y 0.6 → 0.25`、`RUN_LEG_ROTATION 0.04 → 0.02`。

### 验证

- 自动化通过：`unit_visual_test`、`mounted_unit_test`、`party_panel_test`。
- 新增断言：马腿枢轴 6 px 与可见位置不变；骑手跟随马身、同步误差 `< 0.001`；骑手上半身独立起伏不超过 `0.6 px`；UI 骑兵预览骑手跟随。
- 非 headless：`locomotion/run_1..4` / `idle`、`visual_probe_party_foot*` / `mounted*` 重新渲染检查。
- 未改变存档 Schema、战斗规则、单位属性、装备或部件层级。

---

## 2026-11-21 · 人物与战马腿部旋转中心修正

### 变更

- `PartVisual` 新增 `lower_part_pivot(part_name, drop_y)`：`offset.y -= drop_y`、`position.y += drop_y`，使旋转中心在素材坐标中下移而贴图可见位置不变。
- 人物左右腿：`LEG_PIVOT_DROP_Y = 3.0`，`LEG_REST_POSITION = (0, 3)`；左右腿使用相同规则。
- 四条马腿：`LEG_PIVOT_DROP_Y = 3.0`，全部腿使用相同规则；`_apply_leg_pose()` 以 y=3 作为动画基准。
- 未修改腿部动画幅度、周期、相位、马腿前后分组、伸展距离、旋转角度、上下位移、其他部件锚点、层级或骑乘偏移。

### 验证

- `unit_visual_test`：新增人物左右腿与四条马腿的枢轴断言，验证基础位置补偿 3 px、贴图可见位置不变、`offset.y` 下移 3 px。
- `party_panel_test`：通过，部队 UI 步兵/骑兵预览动画正常。
- 非 headless：`locomotion/run_1..4` / `idle`、`visual_probe_party_foot*` / `mounted*` 重新渲染。
- 未改变存档 Schema、战斗规则或单位属性。

---

## 2026-11-21 · 士兵待机与战斗动作表现二次优化

### 新增

- 部队 UI 预览待机动画：`UnitDetailPanel._process()` 复用 `UnitVisual.update_locomotion(delta, false)`；步兵播放人物待机，骑兵播放马匹/骑手待机；面板不可见时不推进，切换单位时 `reset_locomotion()`。
- 步兵待机头部独立微摆 `IDLE_HEAD_SWAY = 0.015`（跑动 `0.006`）。
- 战马跃马式四肢：两只前腿成组前伸、两只后腿成组后伸，随后同步收缩；组内错位 `0.12 rad`。
- 长矛方向性前摇/戳击：前摇沿攻击反方向后移 `2.5 px`，戳击沿攻击方向前伸 `6.0 px`；保持/恢复沿用 4 秒/0.35 秒。

### 变更

- 步兵腿部振幅：`RUN_LEG_SWING_X 4.0→1.5`、`RUN_LEG_LIFT_Y 1.8→0.6`、`RUN_LEG_ROTATION 0.10→0.04`；等幅反相关系不变。
- 马腿不再使用 0 / π / π/2 / 3π/2 的独立正弦；改为前腿组/后腿组相反相位，前后伸展 `3.5 px`、旋转 `0.09 rad`、上下位移 `0.25 px`。
- 马身增加伸展/收缩：跑动起伏 `4.5`、俯仰 `0.022 rad`、横向拉伸 `2%`、纵向压缩 `0.8%`。
- 长矛时间：前摇 `0.10→0.14s`、戳击 `0.12→0.14s`；戳击阶段从旋转保持改为位置前伸，保持阶段同时维持角度与位置。
- 伤害仍即时结算；没有将伤害延后到戳击阶段。

### 决策

- D067：待机动画复用、跃马式马腿与长矛前后摇。

### 验证

- 自动化通过：`unit_visual_test`、`combat_attack_rules_test`、`unit_controller_test`、`battle_scene_test`、`party_panel_test`、`player_control_test`、`mounted_unit_test`。
- 非 headless：`locomotion/run_1..4` / `idle`、`visual_probe_attack_windup/thrust/hold/recover`、`visual_probe_party_foot*` / `mounted*`。
- 未改变存档 Schema、战斗规则、单位属性或装备数据。

---

## 2026-11-21 · 战斗动作表现与攻击操作体验优化

### 新增

- 玩家自由攻击：左键在无敌人/空白处也会播放完整长矛动画并进入冷却，有有效目标时才结算伤害；`player_attack_at()` 返回值改为“攻击动作是否释放”。
- 长矛攻击后保持 `4.0s`（`SPEAR_POST_ATTACK_HOLD_TIME`，可按 3–5 秒配置），再以 `0.35s` 平滑恢复；连续攻击立即重新开始并重置保持时间。
- 骑乘战斗速度系数 `BATTLE_MOUNTED_MOVE_SPEED_MULTIPLIER = 0.84`：民兵 85→71.4、职业步兵 80→67.2、玩家角色 100→84；步兵仍为 0.6，大地图速度不变。
- `is_attack_pose_locked()`：只有旋转准备/戳击阶段锁定朝向，保持/恢复阶段允许移动与转身。
- `Tests/_debug/locomotion_probe`：5 倍比例输出步兵/骑兵跑步四相位与待机截图，用于人工检查动画。

### 变更

- 步兵双腿：改为等幅反相水平步态（`RUN_LEG_SWING_X=4.0`、`RUN_LEG_LIFT_Y=1.8`、`RUN_LEG_ROTATION=0.10`）；前摆腿抬起、后摆腿接地，待机平滑复位。
- 马匹：跑动身体起伏 `2.8→4.5`、周期 `0.48→0.50` 与人物同步；新增俯仰 `0.022 rad` 与压缩/伸展 `0.018`；马腿上下位移 `2.2→0.55`，改为水平 `1.8 px` + 旋转 `0.06 rad`；待机马腿位移降至 `0.10 px`。
- 初始部署边距 `SPAWN_MARGIN_X 220→160`，双方质心间距约 `786→906`；不改变队形结构与 Party Lane。
- `_unhandled_input` 不再拒绝战场边界外的鼠标点击，边界外点击按鼠标方向空挥。
- 玩家攻击动画期间朝向锁定缩小到挥动/刺出阶段。

### 决策

- D062：玩家攻击动作与命中判定解耦（自由攻击）。
- D063：长矛攻击后保持姿态并延迟恢复。
- D064：动画由马身整体动态与协调步态驱动。
- D065：骑乘战斗速度使用独立系数。
- D066：初始部署边距进一步缩短到 160。

### 验证

- 自动化通过：`unit_visual_test`、`combat_attack_rules_test`、`unit_controller_test`、`battle_scene_test`、`battle_formation_test`、`player_control_test`、`mounted_unit_test`。
- 非 headless 截图：`visual_probe_close/move/hold/recover/attack_left/attack_up/attack_down/legs_only`；`locomotion/run_1..4` 与 `idle`。
- 未改变存档 Schema；未修改 UnitConfig、坐骑装备加成、战斗结算或大地图速度。

---

## 2026-11-21 · 战斗移动、动画、实体碰撞与 360°攻击优化

### 新增

- 步兵/骑兵待机与移动动画：人物上半身起伏/倾斜、武器摇摆、双腿交替；马身/马头/四条马腿独立动画；影子稳定；实际位移驱动 + 0.12s 缓冲 + 0.18s 混合。
- 360°定向矩形攻击：鼠标/目标方向、旋转矩形、背后/横向/长度外排除、单次单目标。
- 武器攻击距离：`EquipmentConfig.weapon_attack_range`；`weapon_sword_01` 设为 14，默认长矛使用 UnitConfig。
- 实体碰撞：`MIN_BODY_DISTANCE=28` 的最小间距推开，与局部避让协同。
- 战斗移动速度系数 `0.6`；初始部署边距 `220`。
- 项目显示 1920×1080；战斗相机 2 倍整数缩放、向下偏移 30；大地图相机默认 1.5 倍。
- 玩家攻击方向来自鼠标世界坐标；攻击方向/目标锁定，武器动画与伤害同向。
- 测试：定向矩形、玩家四方向、武器距离、碰撞、待机/跑动/马匹动画、部署/相机/分辨率。

### 变更

- `VisualLayers`：四条马腿移到马身体之前（马鞍 -69、马腿 -71、马身 -72、人左腿 -80）。
- `HumanVisual` 拆出 `UpperBody`；`HorseVisual` 拆出 `HorseBodyRig`；四腿各自运动。
- 长矛动画从固定横向戳击升级为任意方向旋转；朝右由整体镜像保持矛尖方向。
- 玩家/AI 共用 `CombatRules` 矩形判定与 `UnitActor.play_attack(direction)`。
- 战斗移动速度：民兵 36 / 职业步兵 33 / 玩家角色 45；骑乘 51/48/60。大地图速度不变。
- 攻击动画与伤害独立：无有效目标不耗冷却/不播有效攻击；命中时两者同向。
- 显示：Viewport/窗口 1920×1080，Stretch 关闭；UI 原生 1920 布局。

### 决策

- D057：四条马腿显示在马身体之前。
- D058：待机/移动动画由实际位移驱动，人物/马匹 rig 分离，影子稳定。
- D059：战斗降速、部署距离与 1920×1080 显示方案。
- D060：武器攻击距离 + 360°定向矩形 + 单次单目标。
- D061：实体碰撞采用最小间距推开 + 局部避让。

### 验证

- 自动化通过：`unit_visual_test`、`combat_attack_rules_test`、`unit_controller_test`、`stat_calculator_test`、`mounted_unit_test`、`unit_manager_test`、`unit_party_serialization_test`、`battle_manager_test`、`formation_manager_test`、`battle_scene_test`、`battle_formation_test`、`player_control_test`、`party_panel_test`、`milestone2_flow_test`、`party_dialogue_test`、`player_character_data_test`、`battle_retreat_test`、`battle_side_result_test`、`ai_encounter_flow_test`、`ai_manager_test`、`faction_vision_test`、`player_encounter_test`、`player_battle_interaction_test`、`world_map_input_test`、`skeleton_smoke_test`、`milestone1_test`。
- 非 headless 实际截图：战斗/近距离、左右/上下攻击、恢复、主菜单、部队面板、结果面板；1920×1080 无裁切，士兵 2 倍整数像素放大。
- 未改变存档 Schema；未修改 BattleResult/经验/奖励/马匹库存规则。

---

## 2026-11-21 · 士兵层级、长矛动画与部队预览优化

### 新增

- `PartVisual`：通用部件贴图/Sprite2D 管理、整体朝向、缺失素材一次性警告。
- `HumanVisual`：人物影子、双腿、身体、罩袍、头部、缨饰、长矛枢轴与攻击动画。
- `HorseVisual`：骑马影子、四条独立马腿、马身、马鞍、马头。
- `VisualLayers`：跨人物/马匹组的最终 z 层级集中配置。
- 长矛四阶段动画：旋转准备 0.10s、戳击保持 0.12s、攻击后延迟 0.20s、恢复 0.20s；攻击角度 `-PI/2`。
- `UnitDetailPanel` 美术预览：独立 `SubViewport`，复用 `UnitVisual`，按真实 UnitData 显示步兵/骑兵外观。
- 玩家部队新增 2 名骑乘测试士兵（共 3 名骑乘职业步兵；玩家部队 7 人）。
- 测试：`unit_visual_test` 扩展；`party_panel_test` 增加预览；多个系统测试更新为 7 人/12 人计数。

### 变更

- 最终层级：武器 → 马头 → 缨饰 → 人头 → 人身体/罩袍 → 人右腿 → 马鞍/马身 → 人左腿 → 四条马腿 → 影子。
- 人物与马匹分组管理；人体双腿始终创建，马身/马鞍按层级自然遮挡。
- 骑乘时人物整体上移 15 像素；马匹与 UnitActor 世界坐标不变。
- 人物影子/骑马影子互斥；四条马腿为独立 Sprite2D。
- 长矛枢轴：48×96 素材左下角 `(24,18)`；身体锚点 `(33,18)` 映射到当前 48×96 画布 `(9,-14)`。
- 朝右时使用人物/马匹整体镜像，长矛动画指向目标；伤害仍即时结算。
- 新游戏马匹库存改为 3，全部由 3 名职业步兵装备，库存剩 0。

### 决策

- D052：人物/马匹分组 + VisualLayers 最终层级。
- D053：骑乘人物整体上移 15 像素。
- D054：长矛独立枢轴与四阶段动画。
- D055：SubViewport 部队预览复用 UnitVisual。
- D056：玩家部队 3 名骑乘测试单位。

### 验证

- 自动化测试通过：`unit_visual_test`、`combat_attack_rules_test`、`mounted_unit_test`、`unit_controller_test`、`battle_scene_test`、`battle_formation_test`、`player_control_test`、`party_panel_test`、`player_character_data_test`、`milestone2_flow_test`、`party_dialogue_test`、`battle_retreat_test`、`battle_side_result_test`、`ai_encounter_flow_test`、`unit_manager_test`、`unit_party_serialization_test`、`battle_manager_test`、`ai_manager_test`、`faction_vision_test`、`player_encounter_test`、`player_battle_interaction_test`、`world_map_input_test`、`skeleton_smoke_test`、`milestone1_test`。
- 非 headless 实际截图检查：
  - `visual_probe_battle/close/move/attack/attack_left/recover/legs_only`：层级、朝向、骑乘偏移、长矛横向戳击/恢复。
  - `visual_probe_party_foot/mounted`：部队详情步兵/骑兵预览。
- 未执行主菜单 UI 与跨进程重启测试（本次未触及）。
- 未改变存档 Schema；玩家部队成员数变化会随存档正常保存/读取。

---

## 2026-11-21 · 士兵美术显示与骑乘层级修复

### 根因

- `UnitVisual` 的 Sprite2D 使用相对负 `z_index`（-100～-8），而 `UnitActor.z_index` 为 0。
- `BattleScene._draw()` 在根节点 z=0 绘制整张战场背景，导致所有士兵部件落到背景之后被完全覆盖。
- `UnitActor._draw()` 的血条、名称（子节点）与选中圈在 z=0 之上，因此出现“只有 UI、没有士兵本体”的现象。
- 实际非 headless 渲染截图已复现并确认；提升 `UnitActor.z_index` 后恢复。

### 修复

- `UnitActor` 新增 `ACTOR_Z_INDEX = 200`；部件实际 canvas z = `200 + 部件相对 z`，全部高于背景。
- `UnitVisual` 层级集中配置；人体双腿始终创建，不再因骑乘状态隐藏。
- 骑乘层级调整为：影子 → 马腿 → 人体双腿 → 马身 → 马头 → 马鞍 → 身体 → 罩袍 → 武器 → 头部 → 缨饰；马身/马鞍自然遮挡人体双腿。
- 部件 Sprite2D 固定最近邻采样，像素画缩放保持清晰。
- 增加一次性资源加载失败日志（同一部件/路径只警告一次）；单个部件失败只跳过该部件。

### 验证

- 实际运行 `Tests/_debug/visual_probe.tscn`（非 headless）并检查截图：
  - 普通步兵、骑乘士兵、玩家角色均显示身体/头部/武器/影子/血条/名称/选中圈。
  - 骑乘单位保留人体双腿；隐藏马匹部件时双腿完整显示，证明没有被主动隐藏。
  - 玩家向右移动 23.75 像素，部件保持跟随；`Body` / `Head` 的 `flip_h = true`。
  - 玩家攻击命中，武器进入攻击闪光。
  - 不同阵营罩袍着色生效（玩家蓝色、商队金色），黑色描边与白色十字保留。
- 自动化测试通过：`unit_visual_test`、`battle_scene_test`、`unit_controller_test`、`mounted_unit_test`、`battle_formation_test`。
- 新增回归检查：`battle_scene_test` 验证每个士兵的身体/头部已加载、部件实际 z 高于背景、骑乘单位同时具有马匹部件与人体双腿。
- 未重复执行存档、战斗结算和大地图全量回归。

### 决策与问题

- D051：UnitActor 必须高于战场背景；人体双腿始终存在，马匹通过层级自然遮挡。
- KI358（士兵贴图完全不可见）与 KI359（骑乘隐藏人腿）已解决。
- KI349（独立缨饰/独立罩袍贴图缺失）仍保留；本次未虚构素材。

---

## 2026-11-21 · 阶段 5 后续优化：攻击判定、临时美术与骑兵系统

### 新增

- `CombatRules`：玩家与 AI 共用的攻击有效性入口（存活/敌对/冷却/射程）。
- `UnitVisual`：基于 `art/我的骑砍临时美术/` 实际 PNG 的可组合部件表现；步行/骑乘切换、阵营罩袍层、朝向翻转、攻击闪光与缺失素材回退。
- `Shaders/faction_tabard.gdshader`：临时阵营罩袍着色（只替换身体贴图的蓝色罩袍区域）。
- `UnitController.AIState`：SEEK / APPROACH / ATTACK；外围进攻点与目标失效重新索敌。
- `UnitManager.equip_mount()` / `unequip_mount()`：马匹库存消耗与返还。
- `PlayerProfile.get_item_count()` / `add_item(id, count)` / `remove_item(id, count)` 与 `inventory_counts`。
- `StatCalculator.compute_move_attack_bonus()` / `compute_effective_attack()`：骑乘移动攻击加成。
- 测试：`combat_attack_rules_test`、`mounted_unit_test`、`unit_visual_test`。

### 变更

- 攻击冷却、目标与移动状态明确属于攻击者；移除目标级攻击锁/受击阻塞，多名单位可同时攻击同一目标。
- 玩家左键攻击没有有效目标时不再消耗冷却、不播放攻击动作。
- 攻击距离统一为 `UnitData.attack_range + 2 × BODY_RADIUS`；玩家与 AI 不再分别硬编码。
- AI 在射程外继续接近，进入射程后停止移动并攻击；目标离开射程后重新追击。
- 新游戏玩家部队：3 民兵 + 1 名装备马匹的职业步兵 + 1 玩家角色（仍为 5 人）；测试马匹库存 2，消耗 1。
- `is_mounted` 改为 MOUNT 装备的派生状态；`UnitConfig.is_mounted` 仅保留兼容提示。
- 骑乘队形间距从 34 加宽到 46；局部避让半径调整为 38。
- 玩家角色与普通士兵共用 `UnitVisual` 部件架构。
- 部队面板/控制权转移列表显示“骑乘”。

### 决策

- D045：攻击冷却属于攻击者，允许多人围攻。
- D046：玩家与 AI 共用统一攻击有效性。
- D047：骑兵是 MOUNT 装备状态，不是独立兵种 ID。
- D048：骑乘属性由 StatCalculator 统一计算。
- D049：部件化临时美术与阵营罩袍着色。
- D050：物品数量采用增量字段兼容旧存档。

### 验证

- 实际执行并通过：`combat_attack_rules_test`、`mounted_unit_test`、`unit_visual_test`、`unit_controller_test`、`stat_calculator_test`、`unit_manager_test`、`unit_party_serialization_test`、`player_character_data_test`、`party_panel_test`、`battle_scene_test`、`player_control_test`、`battle_formation_test`、`milestone2_flow_test`、`battle_result_test`、`multi_party_battle_test`、`battle_retreat_test`、`battle_side_result_test`、`ai_manager_test`、`faction_vision_test`、`party_manager_test`、`formation_manager_test`、`battle_manager_test`、`milestone1_test`、`skeleton_smoke_test`。
- 未执行主菜单 UI、大地图输入/对话/遭遇交互与 Milestone 1 跨进程重启测试（本次未触及这些路径）。
- 未升级存档 Schema；旧存档缺少 MOUNT/`inventory_counts` 时按步兵与 1 件物品兼容。
- `art/` 没有独立缨饰与独立罩袍贴图；已记录 KI349，罩袍暂用身体贴图蓝色区域着色。
- 项目没有独立 `Equipment_System.md`；装备与马匹规则更新在 `Docs/Systems/Unit_System.md`，未新建重复文档。

---

## 2026-11-21 · 阶段 5 战斗结算与战后处理

### 新增

- `BattleResultData`：统一战斗结果（胜负/失败/撤退侧、参战快照、伤亡/存活、经验、金币/战利品、结束原因、finalized）。
- `PlayerProfile`：金币与物品栏，存于 `player` 字典。
- `Data/Units/player_hero.tres` 与 `UnitConfig/UnitData.is_player_character`。
- 玩家角色控制：WASD、斜向归一化、鼠标左键攻击、攻击冷却、金色控制圈与攻击闪光。
- 控制权转移面板：接管存活友军或观战；场景本地暂停。
- `FormationManager`：横向/纵深/松散/方阵站位。
- `BattleScene` 队形槽位、party lane、周期邻居缓存；`UnitController` 局部避让。
- 玩家侧撤退按钮与 `RETREATED` 结果。
- 战后经验/金币/装备战利品结算。
- 结果面板：多侧名称、伤亡/存活、经验、金币/战利品。
- 测试：`formation_manager_test`、`battle_result_test`、`player_character_data_test`、`player_control_test`、`battle_formation_test`、`battle_side_result_test`、`battle_retreat_test`。

### 变更

- 新游戏玩家部队：3 民兵 + 1 职业步兵 + 1 玩家角色（共 5 人）。
- `BattleManager.finish_battle()` 先生成/应用经验与奖励，再写回 HP、移除阵亡、解锁部队。
- 屏幕/离屏/中途加入共用同一结算入口；同一战斗只结算一次。
- `BattleScene` 按战斗侧统计存活；一支部队全灭但同侧仍有友军时继续。
- 玩家角色被击败只影响当前控制，不直接判负；可接管或观战。
- 玩家输入只控制单个单位；旧 `command_player_units()` 保留为调试入口。
- 玩家档案金币/物品与玩家角色身份进入存档；未升级 Schema。
- 结果面板显示预览；点击返回大地图时执行最终结算。

### 决策

- D041：玩家角色是普通 Unit，控制权与身份分离。
- D042：部队槽位 + 单位局部避让。
- D043：统一 BattleResultData 与战后结算。
- D044：玩家档案与奖励写入 player 字典。

### 验证

- 实际执行并通过：`formation_manager_test`、`battle_result_test`、`player_character_data_test`、`player_control_test`、`battle_formation_test`、`battle_side_result_test`、`battle_retreat_test`、`unit_controller_test`、`battle_manager_test`、`battle_scene_test`、`milestone2_flow_test`、`party_panel_test`、`unit_party_serialization_test`、`unit_manager_test`、`stat_calculator_test`、`skeleton_smoke_test`、`milestone1_test`、`milestone1_flow_test`、`milestone1_restart_test`（save + load）、`ai_manager_test`、`ai_encounter_flow_test`、`player_encounter_test`、`player_battle_interaction_test`、`party_dialogue_test`、`world_map_input_test`、`faction_vision_test`、`multi_party_battle_test`。
- 未执行 `main_menu_ui_test`（本次未改主菜单）。
- 未改变存档 Schema；旧存档缺少 `is_player_character` / 玩家金币 / 物品时使用安全默认值。

---

## 2026-11-21 · 阶段 4 AI 遭遇与玩家中途参战交互完善

### 新增

- `EncounterManager`：统一负责 AI 遭遇判定、玩家中途参战检测、停止部队与战斗创建/加入委托。
- `EncounterManager.update_player_battle_interaction()`：玩家接近进行中的离屏战斗时生成交互请求。
- 交互距离常量：`AI_ENCOUNTER_RADIUS = 50`、`BATTLE_INTERACTION_RADIUS = 55`、`BATTLE_INTERACTION_EXIT_RADIUS = 90`。
- `EventBus.player_battle_interaction_requested(interaction_id, battle_id)`。
- `GameManager.PAUSE_REASON_BATTLE_INTERACTION = &"battle_encounter_dialogue"`。
- WorldMap `BattleInteractionPanel`：显示交战方与持续时间，提供“加入战斗/离开”。
- `EncounterManager.decline_battle_interaction()` 与拒绝记录，避免离开后原地重复弹窗。
- 测试：`player_battle_interaction_test`。

### 变更

- 原先 `WorldMapManager` 中的遭遇检测迁移到 `EncounterManager`；WorldMapManager 只保留移动、跟随与边界。
- `WorldSimulation` 顺序为移动 → 统一遭遇 → 玩家中途参战检测 → AI；存在待处理交互时跳过该 tick 的 AI。
- 移除玩家接近离屏战斗时自动加入的逻辑，改为先暂停并弹出加入/离开面板。
- 加入：`try_join_battle()` 加入已有 BattleSession，不创建重复战斗；离开：NPC 战斗继续，玩家停在原地。
- `ai_encounter_flow_test` 更新为：接近离屏战斗先看到交互面板，点击“加入战斗”后进入已有战斗。
- 战斗结束、战斗 ID 变化、玩家已参战或异常关闭时自动关闭面板并清理 `battle_encounter_dialogue`。
- 不改变存档 Schema；攻击意图、交互 ID 与拒绝记录均为运行时状态。

### 决策

- D040：新增 `EncounterManager`，区分强制遭遇与玩家中途参战；D038 的实现位置迁移到新管理器。

### 验证

- 实际执行并通过：`player_battle_interaction_test`、`ai_encounter_flow_test`、`ai_manager_test`、`faction_vision_test`、`multi_party_battle_test`、`world_map_input_test`、`player_encounter_test`、`battle_manager_test`、`battle_scene_test`、`party_dialogue_test`、`milestone2_flow_test`、`milestone1_test`、`skeleton_smoke_test`。
- 未执行 `unit_controller_test`、`main_menu_ui_test`。

---

## 2026-11-21 · 阶段 4 AI 遭遇行为优化

### 新增

- `PartyData.attack_intent`：运行时攻击/拦截意图，不进入存档。
- `WorldMapManager.update_encounters()`：统一大地图遭遇判定，距离 `AI_ENCOUNTER_RADIUS = 50`（后续迁移到 `EncounterManager`，见顶部条目）。
- `WorldMapManager` 待处理玩家遭遇（唯一 `encounter_id`）、`has_pending_player_encounter()` / `clear_pending_player_encounter()`。
- `EventBus.player_encounter_requested(encounter_id, attacker_party_id, target_party_id)`。
- `GameManager.PAUSE_REASON_ENCOUNTER_DIALOGUE = &"encounter_dialogue"`。
- WorldMap `PlayerEncounterPanel`：敌对部队名称、阵营、兵力、遭遇描述与唯一“战斗”按钮。
- `WorldMap.cancel_player_encounter()`：异常关闭时清理自身暂停与待处理遭遇。
- 测试：`player_encounter_test`；扩展 `ai_manager_test`、`world_map_input_test`。

### 变更

- 遭遇判定从 AIManager 的“距离 24 直接开战”改为 WorldMapManager 统一判定：
  - 双方有效、阵营敌对、距离 <= 50、至少一方攻击意图指向对方；
  - AI 对 AI 创建/加入离屏战斗；玩家被主动拦截进入遭遇对话。
- `WorldSimulation` 顺序为移动 → 遭遇 → AI；存在待处理玩家遭遇时跳过该 tick 的 AI。
- AI 不再直接为玩家目标创建屏幕战斗；改为遭遇对话后由玩家选择战斗。
- 强盗目标选择改为动态评分：商队 300 / 治安队 200 / 玩家 100 / 其他 50，减距离 ×0.1；切换阈值 30。
- 追逐玩家时若出现评分明显更高的商队，会重新评估并切换。
- NPC 速度：治安队 120、强盗 100、商队 80；玩家 150。旧存档速度不被重置。
- 战斗场景仍按战斗侧处理；遭遇对话不创建战斗，直到玩家选择“战斗”。

### 决策

- D038：大地图遭遇由 `WorldMapManager` 统一判定，AI 只维护攻击意图。
- D039：强盗动态目标评分、切换阈值与玩家遭遇对话。

### 验证

- 实际执行并通过：`ai_manager_test`、`ai_encounter_flow_test`、`faction_vision_test`、`multi_party_battle_test`、`world_map_input_test`、`player_encounter_test`、`battle_manager_test`、`battle_scene_test`、`party_dialogue_test`、`milestone2_flow_test`、`milestone1_test`。
- 实现阶段另验证：`party_panel_test`、`stat_calculator_test`、`unit_manager_test`、`party_manager_test`、`unit_party_serialization_test`、`skeleton_smoke_test`、`milestone1_flow_test`、`milestone1_restart_test`（save + load）。
- 未执行 `unit_controller_test`、`main_menu_ui_test`。
- 未改变存档 Schema；攻击意图与遭遇状态为临时运行时数据。

---

## 2026-11-21 · 阶段 4 大地图阵营生态与动态遭遇

### 新增

- `FactionManager`：玩家 / 商队 / 强盗 / 治安队 / 本地势力注册与友好/中立/敌对查询。
- `VisionManager`：距离视野、可见部队列表、敌对/友方/中立筛选、最近敌对目标、`can_see()`。
- `PartyAIType.BANDIT` / `GUARD`；`OrderType.FOLLOW_PARTY`。
- “山道强盗”测试部队与强盗游荡路线。
- 强盗 AI：目标优先级、持续追击、失去视野后清除目标并恢复游荡。
- 治安队 AI：优先拦截威胁商队的强盗、恢复巡逻、响应附近战斗。
- `BattleParticipant` 与多战斗侧数据结构；`BattleSession` 增加 `participants` / `side_*` / `winning_side_index` / `offscreen` / `paused_world` / `player_involved`。
- `BattleManager.start_battle_by_sides()`、`get_join_side()`、`try_join_battle()`、`tick()`、`resolve_current_battle_now()`。
- 离屏 AI 对 AI 自动结算（10 世界秒）与第三方中途加入。
- 玩家接近离屏战斗自动加入并进入 `BattleScene`；`battle_started` 信号自动切换场景（后续改为加入/离开面板，见顶部条目）。
- 玩家部队跟随移动目标（0.5 世界秒刷新）。
- `EventBus.battle_participant_joined`。
- 测试：`faction_vision_test`、`multi_party_battle_test`、`ai_encounter_flow_test`；扩展 `ai_manager_test`、`world_map_input_test`。

### 变更

- 商队、治安队速度 220 → 110；强盗 135；玩家保持 150。
- 新游戏阵营划分：玩家 / 河畔商队（商队）/ 北境巡逻队（治安队）/ 山道强盗（强盗）；地点仍为本地势力。
- 玩家点击移动中的有效部队进入跟随；静止部队仍为普通移动。
- 敌对部队不再弹出对话，由 AI 主动追击并触发战斗。
- `BattleScene` 按战斗侧生成单位与敌人列表，玩家输入作用于实际所在侧；结果按获胜侧显示。
- `BattleManager.finish_battle` 解锁全部参战部队；离屏战斗不压入/移除 `battle` 暂停。
- `WorldContext` 装配 `FactionManager` / `VisionManager`；`WorldSimulation` 每 tick 推进离屏战斗计时。

### 决策

- D035：阵营关系与视野查询集中到公共管理器。
- D036：多战斗侧、离屏自动结算与中途加入。
- D037：玩家跟随使用 `FOLLOW_PARTY` + 0.5 世界秒刷新。

### 验证

- 实际执行并通过：`faction_vision_test`、`ai_manager_test`、`multi_party_battle_test`、`ai_encounter_flow_test`、`world_map_input_test`、`party_dialogue_test`、`battle_manager_test`、`battle_scene_test`、`milestone2_flow_test`、`party_panel_test`、`stat_calculator_test`、`unit_manager_test`、`party_manager_test`、`unit_party_serialization_test`、`skeleton_smoke_test`、`milestone1_test`、`milestone1_flow_test`、`milestone1_restart_test`（save + load）。
- 未执行 `unit_controller_test`、`main_menu_ui_test`。
- 未改变存档 Schema；`ai_type` / `current_order` 仅扩展枚举值，`current_target_id` / `current_order` 继续保存跟随与追击状态。

---

## 2026-11-21 · 阶段 3 Step 3 士兵成长、装备属性与部队管理面板

### 新增

- `UnitConfig` 等级成长字段：`max_level` / `base_exp_to_next_level` / `exp_growth_per_level` / `hp_per_level` / `attack_per_level` / `move_speed_per_level` / `attack_range_per_level`；新增 `exp_to_next_level()`。
- `EquipmentConfig` 校验、槽位字符串映射、显示名与属性加成文本。
- `Data/Equipment/` 五个示例装备：铁剑、木盾、铁盔、皮甲、普通战马。
- `UnitManager` 配置注册/查询、`add_exp()`、`get_exp_to_next_level()`、`equip_item()`、`unequip_slot()`、`recalculate_stats()`、`recalculate_all_stats()`。
- 士兵独立名称：创建时生成“兵种名 + 两位编号”，名称随存档保存。
- `PartyPanel` / `PartyMemberItem` / `UnitDetailPanel`：大地图部队管理面板。
- 大地图顶部“部队”按钮。
- 测试：`party_panel_test`；扩展 `stat_calculator_test`、`unit_manager_test`、`unit_party_serialization_test`。

### 变更

- `StatCalculator` 从“复制兵种基础属性”升级为完整公式：基础值 + 等级成长 + 装备加成；`current_hp` 只做上限 clamp。
- `UnitManager.create_unit()` 复制并校验默认装备、初始化等级/经验、生成独立名称。
- `WorldContext._ready()` 扫描 `Data/Units` 与 `Data/Equipment` 注册静态配置；读档后调用 `recalculate_all_stats()`。
- 读档缺失名称时回填兵种模板名称；无效装备引用报告并清理。
- 部队管理面板打开时压入 `ui_panel` 暂停原因，关闭时只移除本面板原因；基础倍率保持不变。
- 大地图交互检测与输入屏蔽包含部队管理面板。
- 职业步兵成长参数高于民兵（每级 +6 HP / +2 攻击）。

### 决策

- D033：等级成长与装备加成统一由 `StatCalculator` 计算，配置注册在 `UnitManager`。
- D034：部队管理面板只读，使用 `ui_panel` 暂停原因栈。

### 验证

- 实际执行并通过：`stat_calculator_test`、`unit_manager_test`、`unit_party_serialization_test`、`party_panel_test`、`world_map_input_test`、`party_dialogue_test`、`milestone2_flow_test`、`milestone1_test`、`milestone1_restart_test`（save/load 两阶段）。
- 未改变存档 Schema；旧存档缺失等级/经验/装备/名称时使用安全默认值。
- 未执行无关的 `unit_controller_test` / `battle_scene_test` / `ai_manager_test`（本次未改其接口语义）。

---

## 2026-11-21 · 阶段 2 Step 2 NPC 自主巡逻与大地图输入优化

### 新增

- `PartyData.PartyAIType`：`NONE` / `TRADE_ROUTE` / `PATROL`。
- `PartyData.ai_type`、`ai_route_index`、`ai_route_settlement_ids`，参与序列化并兼容旧存档。
- `AIManager` 商队往返、巡逻循环、玩家/战斗/失效部队跳过。
- `ai_manager_test`：商队/巡逻循环、跳过规则、边界、AI 字段序列化。
- `world_map_input_test`：数字键、UI 屏蔽、点击切 1x、真实 tick 下 NPC 移动。

### 变更

- 河畔商队通过 stable `settlement_id` 在橡木村与河畔村之间循环。
- 北境巡逻队按四个固定点循环，`ai_route_index` 保存进度。
- 新游戏玩家速度从 300 调整为 150；NPC 保持 220。
- 顶部主键区 `1` / `2` / `3` 对应暂停 / 1x / 2x；小键盘与 echo 不触发。
- 玩家点击有效地图并成功设置目标后，基础倍率自动切为 1x。
- 保存面板、地点面板、部队对话打开时屏蔽快捷键与地图点击。
- 全员阵亡的部队在战斗结算后设为 `DISABLED`，停止 AI 与世界模拟。
- 时间按钮与快捷键统一走 `_set_world_speed()`。

### 决策

- D031：NPC 大地图 AI 状态存放在 `PartyData`；路线使用 stable ID。
- D032：时间快捷键与点击恢复 1x 只修改基础倍率，不清除暂停原因。

### 验证

- `ai_manager_test`、`world_map_input_test`、`party_dialogue_test` 通过。
- `unit_party_serialization_test`、`battle_manager_test`、`battle_scene_test`、`milestone2_flow_test`、`skeleton_smoke_test`、`milestone1_test`、`milestone1_flow_test` 回归通过。
- 未改变存档 Schema；旧存档缺失 AI 字段时默认为无 AI。

---

## 2026-11-20 · Milestone 2 Step 2 大地图遭遇与首次实战

### 新增

- `PartyDialoguePanel`：显示部队名称、阵营、兵力，提供离开/发起战斗。
- `Scenes/Battle/battle.tscn` 与 `BattleScene`：战场、士兵生成、玩家点击命令、结果面板。
- `UnitActor`：程序绘制士兵、阵营颜色、朝向、血条与名称。
- `UnitController`：自动索敌、移动、攻击、受伤、死亡与手动移动命令。
- `BattleSession` 新增双方 `unit_id` 列表与阵营字段。
- `WorldInitializer.create_test_battle_forces()`：玩家与河畔商队各 3 民兵 + 2 职业步兵。
- 测试：`unit_controller_test`、`battle_manager_test`、`party_dialogue_test`、`battle_scene_test`、`milestone2_flow_test`。

### 变更

- `BattleManager.start_battle()`：校验部队、阵营、可用性与存活士兵，生成 `BattleUnitState`，锁定部队并压入 `battle` 暂停。
- `BattleManager.finish_battle()`：写回存活 HP，移除阵亡单位并删除 `UnitData`，解锁部队，清理会话，防止重复结算。
- `GameManager` 新增 `PAUSE_REASON_BATTLE`；战斗期间 `save_game()` 返回 `ERR_BUSY`。
- 屏幕内战斗 WorldTime 改为 0（暂停原因栈），`set_battle_mode(0.5)` 保留给未来离屏战斗。
- 大地图新增部队遭遇检测与对话 UI；离开后恢复此前时间状态。
- `unit_party_serialization_test` 开始时清理新游戏预置的测试士兵。

### 决策

- D027：战斗会话、场景与结算职责分离。
- D028：屏幕内战斗暂停世界时间，替代 D008 的屏幕内 0.5 倍速方案。
- D029：阵亡单位移除归属并删除数据；存活单位写回剩余 HP。
- D030：初始测试兵力为临时调试配置，后续由招募系统替换。

### 验证

- Step 1 四个单元测试、`unit_controller_test`、`battle_manager_test`、`party_dialogue_test`、`battle_scene_test`、`milestone2_flow_test` 全部通过。
- `skeleton_smoke_test`、`milestone1_test`、`milestone1_flow_test` 回归通过。
- 未修改存档 Schema；测试存档已清理。

---

## 2026-11-20 · Milestone 2 Step 1 士兵数据层

### 新增

- `Data/Units/infantry_militia.tres`（民兵）与 `infantry_trained.tres`（职业步兵）兵种配置。
- `StatCalculator` 基础实现：`compute_final_stats()` / `apply_to_unit()` 统一初始化 `max_hp`、`attack`、`attack_interval`、`move_speed`、`attack_range`。
- `PartyManager.transfer_member()`：转队接口，与 `add_member()` 共用底层规则。
- `PartyManager.validate_membership_consistency()`：校验成员存在、部队存在、唯一归属与双向一致。
- `Tests/UnitTests/`：`unit_manager_test`、`party_manager_test`、`stat_calculator_test`、`unit_party_serialization_test`。

### 变更

- `UnitManager.create_unit()` 通过 `StatCalculator` 初始化属性，出生满血并清空归属。
- `UnitManager.remove_unit()`、`PartyManager.remove_party()` 改为返回 `bool`。
- `UnitManager.add_unit()` / `PartyManager.add_party()` 拒绝重复 ID，失败时原实体不变。
- `PartyManager.add_member()` 支持原子转队：先从所有其他部队移除，再写入目标部队；要求阵营一致。
- `remove_member()` 只清空归属，不删除 `UnitData`；`remove_party()` 清空成员归属并保留单位。
- `WorldContext.load_from_save_data()` 在两个仓储恢复后校验成员关系，失败时报告错误并拒绝加载。
- `load_from_dict()` 遇到重复实体 ID 时报错并跳过，不再静默覆盖。

### 修复

- 一个士兵可能同时存在于两支部队成员列表（D024）。
- 重复实体 ID 静默覆盖（D024）。
- 删除已归属士兵后产生悬空成员引用（D024）。
- 读档后缺少士兵-部队关系校验（D025）。

### 验证

- 4 个新增单元测试全部通过。
- `skeleton_smoke_test`、`milestone1_test` 回归通过。
- 未修改存档 Schema；测试存档已清理。

---

## 2026-11-20 · 测试范围控制规范

### 变更

- 引入 L1–L4 测试分级：局部、关联、集成、全量。
- 默认只运行验证本次修改的最小测试集；公共接口/核心数据/跨系统改动扩大范围；重大重构与里程碑才运行全量。
- 开发前必须说明改动文件、涉及系统、接口影响、将执行与不执行的测试；完成后汇报测试结果与未验证风险。
- 更新 `Docs/03_Design_Conventions.md`、`Docs/00_Project_Index.md`、`Docs/02_Development_Roadmap.md`。

---

## 2026-11-20 · V0.4 Milestone 1 完成

### 新增

- `WorldInitializer`：生成世界 ID、3000×2000 地图、玩家部队、2 支 NPC 部队、4 个地点。
- `SettlementManager`：地点仓储、创建、查询、序列化，接入 `WorldContext`。
- `SaveData` Schema v2：世界 ID、创建时间、世界尺寸、玩家部队 ID。
- `SaveManager`：临时文件 + 校验 + `.bak` 备份替换；存档头、列表、最近有效存档。
- `WorldContext.to_save_data()` / `load_from_save_data()`。
- `GameManager.save_game()` / `continue_game()` / 完整读档流程。
- `TimeManager.get_base_world_speed()` / `restore_world_time()`。
- 大地图场景：草地/道路/河流背景、部队/地点图标、摄像机跟随/平移/缩放。
- 主菜单：新游戏、继续、读取列表、设置占位、退出。
- 大地图 UI：世界时间、暂停/1x/2x、玩家坐标、保存面板、返回主菜单。
- 地点交互：40 像素触发、线段检测、到达停止、暂停、离开仍暂停。
- `UiTheme`：中文字体主题，覆盖 UI 与地图图标标签。
- 测试：`milestone1_test.tscn`、`milestone1_flow_test.tscn`、`main_menu_ui_test.tscn`、`milestone1_restart_test.tscn`（跨进程存档）。

### 变更

- `WorldMapManager.update_party_movement()` 实现直线移动、到达判定、边界 clamp。
- `PartyIcon` / `SettlementIcon` / `MapBackground` 程序绘制表现。
- 主菜单与大地图 UI 改为程序化构建，关键控件使用稳定名称。
- 初始实体 ID 使用 `WORLD_000001` / `PARTY_000001` / `SETTLEMENT_000001`，而非需求示例中的 `settlement_001`（D019）。

### 验证

- 原有 18 项冒烟测试通过。
- Milestone 1 数据/UI 测试、端到端流程测试、主菜单 UI 测试全部通过。
- 主场景无头启动无解析错误与运行时报错。
- 测试存档已清理，`user://saves/` 无残留。

---

## 2026-11-20 · V0.3 架构基线

### 新增

- 建立 `Docs/` 项目记忆文档体系：总索引、核心架构、路线、规范、系统文档、开发状态。
- 建立工程目录骨架：`Scripts/`、`Scenes/`、`Data/`、`Tests/`。
- 注册 5 个 Autoload：`EventBus`、`TimeManager`、`SaveManager`、`SceneManager`、`GameManager`。
- 实现 `TimeManager` 固定步长世界 tick（0.1 秒，单帧最多 10 tick）。
- 实现 JSON 存档基础读写与槽位列表接口。
- 定义核心实体数据类：`UnitData`、`PartyData`、`LordData`、`SettlementData`、`FactionData`。
- 定义静态配置类：`UnitConfig`、`EquipmentConfig`、`FactionConfig`。
- 建立 `WorldContext` + `WorldSimulation` 世界会话结构。
- 建立 `BattleSession` / `BattleUnitState` / `BattleManager` 战斗会话骨架。
- 建立冒烟测试并通过全部检查。

### 决策

- 大地图采用俯视平面；小场景采用横版侧视 + 纵深移动。
- 静态配置使用 `Resource`，运行时实体使用 `RefCounted`，存档使用 JSON。
- 用 `WorldContext` + `WorldSimulation` 替代源规划中的单一 `WorldManager`。
- 暂停使用“原因栈”，而不是单一布尔值。
- 不使用 `Engine.time_scale` 或 `get_tree().paused` 实现游戏暂停。

### 版本管理

- 初始化本地 Git 仓库，默认分支 `main`。
- 创建私有远程仓库并推送首个提交：<https://github.com/WuYiWoYi/wodeqikan>。
- 仓库级代理配置为 `http://127.0.0.1:10808`。

### 未决

- 离屏 AI 对 AI 战斗是否自动结算，见 `Development/Known_Issues.md`。
- 大地图坐标尺度、缩放与地图尺寸未定。
- 渲染器是否从 Forward+ 切换到 Compatibility 待性能验证。

### 来源

- 基于《2D 中世纪沙盒战略游戏核心架构设计与开发规划 V0.2》。
