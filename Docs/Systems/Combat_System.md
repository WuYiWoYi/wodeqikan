# 战斗系统

**核心数据：** `Scripts/Systems/Combat/battle_session.gd`、`battle_unit_state.gd`
**核心逻辑：** `Scripts/Systems/Combat/battle_manager.gd`
**场景与表现：** `Scripts/UI/Battle/battle_scene.gd`、`Scripts/Systems/Combat/unit_actor.gd`、`unit_controller.gd`
**状态：** 双方/多方实时战斗、多场 AI 离屏战斗并行、按游戏小时结算的离屏战斗、1800×1024 战场与参数化部署、增援加入既有会话与后方展开、增援提示、360°定向矩形攻击、玩家自由攻击、武器决定攻击距离、实体碰撞、统一攻击规则、多人围攻、控制权转移与观战、双方半场列阵/接敌放松/目标分流/局部避让、克制步态/待机动画、跃马式马腿动画、长矛前后摇与攻击后保持、长矛有效帧伤害结算、受击白闪/受击动作/短暂僵直、统一攻击/命中/僵直事件、骑乘战斗加速、左右手武器独立层级、人物头部/头盔分离、满血隐藏生命条、1920×1080 显示、统一 BattleResult、有效伤害/击杀经验与战后经验奖励、撤退、按 tier 负伤判定、俘虏池分配与玩家战后接收已实现；复杂战术指挥、显式攻击槽位、士气未实现

> 本文是项目实际的战斗系统文档。任务书中提到的 `Battle_System.md` 与本文对应，未另建重复文档。

---

## 1. 设计目标

- 每次战斗创建独立 `BattleSession`。
- 战斗临时数据与长期实体数据分离。
- 战斗期间 HP 以 `BattleUnitState` 为唯一权威，结束时统一写回 `UnitData`。
- 战斗场景只读取 `UnitData` 静态属性，不修改部队成员关系。
- 结算由 `BattleManager` 统一执行，场景控制器不得直接改世界数据。
- 玩家角色就是普通 `Unit`，玩家控制只是 `UnitController` 的一种运行模式。
- 部队是战斗集群的组织单位：队形槽位由场景按部队分配，单位只负责局部移动与避让。
- 屏幕战斗、离屏战斗与中途加入共用 `BattleResultData`、伤亡、经验与奖励结算。

## 2. 数据模型

### BattleSession

| 字段 | 说明 |
|---|---|
| `battle_id` | 战斗 ID，`BATTLE_000001` |
| `world_position` | 战斗发生位置 |
| `participants` | `party_id → BattleParticipant` |
| `side_party_ids` / `side_unit_ids` | `side_index → 部队/单位 ID` |
| `attacker_party_ids` / `defender_party_ids` | 兼容字段：side 0 / side 1 |
| `attacker_unit_ids` / `defender_unit_ids` | 兼容字段：side 0 / side 1 的单位 |
| `attacker_faction_id` / `defender_faction_id` | 兼容字段：前两个战斗侧的阵营 |
| `unit_states` | `unit_id → BattleUnitState` |
| `status` | PREPARING / ACTIVE / ENDED |
| `result` | UNDECIDED / 攻击方胜 / 防守方胜 / 平局 / 中止 / 其他侧胜利 / 撤退 |
| `winning_side_index` | 获胜战斗侧；-1 表示平局/撤退/未定 |
| `final_result` | 结算后的 `BattleResultData`；非 null 表示已结算且不可再次修改 |
| `retreated_side_indices` | 主动撤退的战斗侧 |
| `offscreen` | 是否为离屏自动结算战斗 |
| `paused_world` | 本场战斗是否压入了 `battle` 暂停 |
| `player_involved` | 玩家是否为参战方 |
| `elapsed_world_seconds` | 离屏战斗已持续的世界时间 |
| `offscreen_settlement_accumulator` | 距离下一次整小时结算的累计世界秒 |
| `offscreen_settlements_done` | 已完成的离屏小时结算次数 |
| `offscreen_casualty_credit` | `side_index → 小数伤亡累计`，用于避免固定人数损失 |

辅助方法：`get_unit_state()`、`is_party_involved()`、`is_attacker_party()`、`get_party_unit_ids()`、`get_all_unit_ids()`、`get_side_of_party()`、`get_side_indices()`、`get_side_party_ids()`、`get_side_unit_ids()`、`get_opposing_party_ids()`。

### BattleParticipant

| 字段 | 说明 |
|---|---|
| `party_id` | 参战部队 ID |
| `faction_id` | 参战时的阵营 |
| `side_index` | 所属战斗侧；同侧为友军 |
| `joined_at_world_seconds` | 加入时的战斗计时 |
| `status` | ACTIVE / DEFEATED / WITHDRAWN |

`side_index` 相同的部队不会互相攻击；不同战斗侧互为敌人。旧双方流程固定 side 0 = attacker、side 1 = defender，因此原有 API 与测试保持兼容。

### BattleUnitState

| 字段 | 说明 |
|---|---|
| `unit_id` | 对应 `UnitData` |
| `party_id` | 所属部队 |
| `battle_hp` | 战斗期间 HP，唯一权威 |
| `alive` | 是否存活 |
| `battle_position` | 战斗场景内位置 |

### BattleResultData

`Scripts/Systems/Combat/battle_result_data.gd`，屏幕/离屏/中途加入共用的最终（或结果面板预览）结果：

| 字段 | 说明 |
|---|---|
| `battle_id` | 战斗 ID |
| `result_code` | 对应 `BattleSession.BattleResult` 的整数值 |
| `winning_side_index` / `losing_side_indices` | 获胜/失败战斗侧 |
| `retreated_side_indices` | 主动撤退侧 |
| `player_side_index` / `player_won` | 玩家所在侧与是否获胜 |
| `participants` | 参战部队快照（party/faction/side/status） |
| `casualties` / `survivors` | 各部队阵亡/存活人数 |
| `exp_gained_by_unit` / `exp_gained_by_party` / `player_exp_gained` | 经验结算明细 |
| `reward_gold` / `reward_items` | 金币与装备战利品 |
| `end_reason` | ANNIHILATION / RETREAT / DRAW / ABORTED |
| `player_involved` / `result_time` / `finalized` | 参与标记、结算时间与最终标记 |

- `finalized` 只在 `finish_battle()` 中置为 true；之后不得修改。
- 结果面板使用 `apply = false` 的预览；点击返回大地图时执行最终结算。

### BattleManager 多战斗注册表

`BattleManager` 管理世界上所有进行中的战斗，而不是单一全局会话：

| 字段 | 说明 |
|---|---|
| `active_battles` | `battle_id → BattleSession`，所有进行中的战斗 |
| `party_battle_lookup` | `party_id → battle_id`，每支部队当前所属战斗 |
| `current_battle` | **仅玩家当前屏幕战斗**；AI 离屏战斗不写入此字段 |

查询接口：

- `get_battle(battle_id)`：按 ID 获取进行中的战斗，已结束返回 `null`。
- `get_battle_for_party(party_id)`：查询部队正在参与的战斗。
- `get_active_battles()`：全部进行中战斗快照（按 `battle_id` 排序）。
- `has_any_active_battles()`：世界上是否存在任意战斗。

约束：

- 世界可同时存在任意多场 AI 离屏战斗，互不阻塞。
- 每支部队同一时间最多参与一场战斗。
- 玩家同一时间最多参与一场屏幕战斗。
- `current_battle` 不再承担“世界唯一战斗”的职责；任何“世界上是否还有战斗”的判断必须使用 `has_any_active_battles()`。

## 3. 进入战斗

```text
大地图接近中立/友好 AI 部队
  → 部队对话面板（push_pause ui_panel）
  → 玩家选择“发起战斗”
      → BattleManager.start_battle(attacker_ids, defender_ids, position)
          ├── 校验部队存在、ID 不重复
          ├── 校验每个战斗侧的部队可用且阵营不敌对
          ├── 为每个存活成员创建 BattleUnitState（battle_hp = current_hp）
          ├── 任一方没有存活士兵则失败
          ├── 参战部队 battle_state = IN_BATTLE
          ├── 停止参战部队大地图移动
          ├── 玩家参与：push_pause(battle)
          └── EventBus.battle_started
      → 场景控制器 SceneManager.change_scene(BattleScene)
```

`start_battle()` 保留双方兼容签名；`start_battle_by_sides(sides, position, offscreen)` 支持任意数量的战斗侧。失败时返回 `null`，不改变任何部队或时间状态。

### 3.0 玩家被敌对 AI 主动拦截

```text
敌对 AI 追击玩家（攻击意图明确指向玩家）
  → EncounterManager 判定距离 <= 50
  → 停止双方、记录待处理遭遇
  → WorldMap 压入 encounter_dialogue 暂停并在屏幕下方显示 NPC 对话
  → 记录 EncounterReason = ENEMY_PURSUIT，只提供“战斗”
  → 玩家选择“战斗”
  → BattleManager.start_battle([玩家], [敌对部队], 位置, offscreen = false)
  → 移除 encounter_dialogue；保留 battle 暂停
  → EventBus.battle_started → WorldMap 切换 BattleScene
```

- `ENEMY_PURSUIT` 不提供离开/撤退：UI 隐藏并禁用按钮，`EncounterManager.decline_player_encounter()` 同样拒绝。
- 玩家主动接近敌对 AI（`PLAYER_INITIATED`）复用同一底部对话，但保留离开选项；普通敌对遭遇沿用原规则（D090）。
- 离开后记录 90 世界单位拒绝锁，双方保留停止位置（D080）。
- 对话打开时不改变基础倍率，关闭或进入战斗时只移除 `encounter_dialogue`。
- 同一待处理遭遇不会重复触发；对话期间 WorldSimulation 跳过 AI。

- `offscreen = false`：屏幕战斗，暂停世界，等待 `BattleScene`。
- `offscreen = true`：NPC 对 NPC 的离屏战斗，不暂停世界，每游戏小时结算一次伤亡。
- 玩家参与的离屏战斗会被强制转换为屏幕战斗。
- 世界可同时存在多场战斗；每支部队同一时间只能参与一场战斗，已参战部队不能加入其他战斗。
- 同一位置/部队自身可用性才是否决创建的理由；世界其他战斗不会阻塞新战斗。
- 玩家屏幕战斗仍然只有一场，并由 `current_battle` 表示。

### 3.1 大地图交互

- 玩家进入 AI 部队 40 像素范围后自动打开 `PartyDialoguePanel`（同一时间只有一个实例）。
- 面板显示部队名称、阵营、`member_unit_ids.size()` 兵力。
- 离开：关闭面板并移除 `ui_panel` 暂停，恢复此前基础倍率。
- 发起战斗：创建会话后先压入 `battle` 暂停，再移除 `ui_panel`，随后切换场景。
- 对话只检查**被点击部队自己所在的那场战斗**，世界其他战斗不会阻塞本次开战：
  - 点击方正在某场离屏战斗且玩家可加入 → 按钮变为“加入战斗”，调用 `try_join_battle(party_id, battle_id)` 复用同一场战斗；
  - 点击方正在屏幕战斗中 → 显示“对方正在屏幕战斗中，暂时无法开战”；
  - 点击方正在离屏战斗中但玩家无法加入 → 显示“对方正在战斗中，靠近战场后可加入战斗”；
  - 点击方不在任何战斗中，且玩家也不在战斗中 → 正常“发起战斗”，创建新的独立会话；
  - 玩家自身已在战斗中 → 显示“玩家部队当前正在战斗中”并禁用按钮；
  - 对方 `IN_BATTLE` / `RETURNING` / `DISABLED` → 显示对应状态说明。
- 空部队（例如被击溃）不再触发交互；玩家或敌方无兵时战斗按钮禁用。
- 交互检测使用“上一帧位置 → 当前位置”线段，避免高倍速穿过目标。

## 4. 战斗场景

```text
BattleScene (Node2D)
├── World
│   └── Characters (Node2D, y_sort_enabled)
├── Camera2D
└── UI (CanvasLayer)
    ├── TopBar（战斗信息、双方存活数）
    ├── BattleHintLabel
    ├── BattleResultDim
    └── BattleResultPanel（结果 + 返回大地图）
```

### 4.1 士兵生成与控制

- 按 `BattleSession.get_side_indices()` 读取全部战斗侧及其单位。
- 每个幸存单位创建一个 `UnitActor`，节点名 `UnitActor_<unit_id>`，并关联对应 `BattleUnitState`。
- 双方战斗保持进攻方左侧、防守方右侧；多方战斗把额外战斗侧放在战场上下区域，避免重叠。
- 每个 `UnitController` 只接收其他战斗侧的控制器作为敌人；同侧单位不会互相攻击。
- 战斗开始后，玩家侧优先选择 `UnitData.is_player_character == true` 的单位作为当前控制对象；旧存档没有玩家角色时退化到第一名存活友军。
- 只有当前控制单位使用玩家输入；其他友军继续 AI。
- 玩家角色被击败后弹出控制权转移面板，可接管任意存活友军或进入观战。
- `command_player_units()` 保留为旧测试/调试用的整队移动入口，正式输入不再调用它。
- 表现由 `UnitActor` + `UnitVisual` 组成；`UnitVisual` 统一组合 `HumanVisual`（人物）与 `HorseVisual`（马匹），两类贴图分别管理。
- 士兵内部层级集中在 `VisualLayers`，前→后为：右手武器 → 马头 → 缨饰 → 头盔 → 人头 → 左手武器 → 人身体/罩袍 → 人右腿 → 马鞍 → 四条独立马腿 → 马身体 → 人左腿。影子不属于该内部序列，由战斗场景统一放到角色层之下。
  - 右手武器保持原 `-10` 层级；左手武器为独立 `-45` 层级，低于马头、不遮挡马头。
  - 头盔为独立 `-35` 层级，位于人头之前、缨饰之后；未装备头盔时只显示人头。
  - 四条马腿仍在马身体之前。
- 头顶 UI 拆分为独立节点：
  - `NameLabel` 只对玩家当前控制的单位显示；普通士兵（含友军与敌军）隐藏名称，控制权转移时立即同步。
  - `UnitHealthBar` 作为独立子节点，满血或死亡时隐藏；受伤后显示；恢复满血后重新隐藏。
  - 血量显示使用实际当前 HP / 最大 HP，带浮点容差；名称与生命条独立控制，隐藏名称不影响生命条。
- 选中圈仍由 `UnitActor` 绘制在部件之上。
- 人体双腿始终创建，骑乘时不隐藏；四个马腿是独立 Sprite2D。
- 人物影子与骑马影子互斥：步行显示人物影子，骑乘显示骑马影子；马匹表现组整体按骑乘状态显隐。
- 战斗场景把每名士兵的影子 Sprite 从 `UnitVisual` 子树移到 `World/Shadows`（z_index = 100），`World/Characters` 为 z_index = 200；因此任何影子都不会覆盖任何士兵的身体、武器或头部。影子仍由 `HumanVisual`/`HorseVisual` 原有代码驱动动画，仅父节点改变；`UnitActor` 每帧同步影子根节点位置，退出场景时一并清理。
- 骑乘时 `HumanVisual.position.y = -15`，人物整体上移 15 像素；`HorseVisual` 与 `UnitActor` 世界坐标不变，碰撞/攻击/移动/队形不受影响。
- 步兵/骑兵拥有独立待机与移动动画：
  - 步兵双腿挂载在人物身体变换节点下，先继承身体整体位移/旋转，再叠加极小的局部步态（`RUN_LEG_SWING_X=0.2`、`RUN_LEG_LIFT_Y=0`、`RUN_LEG_ROTATION=0.005`）；身体起伏/倾斜是主要动态。
  - 待机时身体轻微起伏、头部独立微摆、武器轻微晃动；影子保持稳定。
  - 马匹移动改为跃马式：两只前腿成组向前伸、两只后腿成组向后伸，随后两组同步收缩；组内只保留 `0.12 rad` 的极小错位，不再使用人类式左右交替步态。
  - 四条马腿挂载在马身 rig 下，先继承马身整体跃动/俯仰/缩放，再叠加 `0.6 px` 伸展与 `0.02 rad` 局部旋转；上下位移为 `0`。
  - 马身随伸展/收缩上下起伏、前后俯仰并轻微拉伸/压缩；马头独立摆动；马身整体跃动仍是主要动态，跑动起伏已下调到 `4.2`。
  - 骑马影子位置与层级不变；马匹抬高时按比例轻微缩小（最多 4%）并变淡（最多 15%），回落时恢复。
  - 人物与马匹周期同步（待机 2.4s、跑动 0.50s），影子稳定。动画由实际位移速度驱动（8 px/s 阈值、0.12s 缓冲、0.18s 混合），攻击动画优先。
- 长矛攻击阶段：前摇 `0.14s`（沿攻击反方向后移 `2.5 px` 并旋转到攻击方向）→ 戳击 `0.14s`（沿攻击方向前伸 `6.0 px`）→ 保持 `4.0s`（`SPEAR_POST_ATTACK_HOLD_TIME`，可按 3–5 秒调整）→ 平滑恢复 `0.35s`。连续攻击会立即重新开始并重置保持时间；保持期间移动/待机不会覆盖长矛角度或前伸位置。
- 伤害在戳击阶段的有效帧结算：`HumanVisual` 在戳击进度达到 `SPEAR_HIT_FRAME_RATIO = 0.6` 时发出一次 `attack_hit_frame`，经 `UnitVisual`/`UnitActor` 转发给 `UnitController`。前摇与戳击前半段只播放动画，不产生伤害；每次攻击动画最多发出一次有效帧事件。
- 有效帧到达时 `UnitController` 重新校验存活、敌对与目标是否仍在锁定方向的攻击矩形内；目标已移动/死亡/离开矩形则本次落空，不触发白闪、受击动作或僵直。冷却、攻击力、攻击范围与间隔仍沿用既有规则，冷却在出手瞬间进入。
- 受击白闪、受击动作与僵直只由 `UnitController.apply_damage()` 在实际扣血后触发；未命中、0 伤害、目标已死亡都不会触发。有效帧前受击/死亡会取消待结算攻击（无伤害）；有效帧后伤害已成立，后续中断不会撤销。
- 阵营外观通过独立罩袍层区分：现有占位身体贴图的蓝色罩袍区域由 `Shaders/faction_tabard.gdshader` 按阵营着色，黑色描边与白色十字保留；没有为每个阵营复制整套士兵贴图。
- 长矛使用独立枢轴（48×96 素材，左下角 `(24,18)`；当前 48×96 身体映射到画布 `(9,-14)`）。攻击方向由攻击逻辑给出，长矛旋转到对应世界方向；朝右时由人物整体镜像指向目标。动画只负责时序与有效帧事件，伤害由 `UnitController` 在回调中结算。
- 伪 Z 排序：`World/Characters` 保留 z_index = 200，但角色之间的顺序不再依赖 YSort 或 CanvasGroup，而由 `BattleScene` 每物理帧按 `BattleUnitState.battle_position.y` 排序全部角色（含尸体），把名次写入 `UnitActor.z_index = rank × SORT_Z_STRIDE`。`UnitActor` 的所有非影子部件仍按 `VisualLayers` 的相对负 z 排列，同一角色的完整视觉因此整体位于其他角色之上或之下。仅靠 YSort 或 CanvasGroup 不足：部件相对负 z 不同，会在不同角色之间形成不同的绝对层级，CanvasGroup 也不会隔离子级 z。实际画布层级 = `Characters.z + UnitActor.z + 部件相对 z`；影子仍由独立的 `World/Shadows` 层负责。
- 当前 `art/` 没有独立缨饰素材，`UnitVisual` 保留 `Plume` 部件插槽，素材缺失时直接跳过。
- 缺少任何素材时只跳过对应部件，单位仍会正常生成，不影响属性、碰撞、攻击范围与移动。

### 4.1.1 完整角色动态层级与死亡尸体表现（已确认）

**完整角色动态层级**

- 每个 `UnitActor` 仍是完整视觉单元：`UnitVisual` 及其全部人物、头盔、缨饰、罩袍、双腿、左右手武器、盾牌、马匹与马匹部件都在同一个角色根节点下。
- `BattleScene` 在 `_physics_process` 中收集 `World/Characters` 的全部 `UnitActor`（含尸体），按权威 `BattleUnitState.battle_position.y`（尸体使用冻结位置）升序排列；相同 Y 用稳定节点名打破平局，避免每帧交换名次。
- 名次 `rank` 从 0（最后排）开始，写入 `UnitActor.z_index = rank × SORT_Z_STRIDE`。`SORT_Z_STRIDE = 72` 大于角色内部非影子层级跨度 70（`RIGHT_HAND_WEAPON = -10` 到 `LEG_LEFT = -80`），因此前一名角色的最低部件仍高于后一名角色的最高部件。
- 内部遮挡关系保持不变：右手武器 → 马头 → 头盔/缨饰 → 人头 → 左手武器 → 身体/罩袍 → 马鞍 → 马腿 → 马身 → 左腿。不为单件武器/盾牌单独排序，也不通过固定某张贴图的 z 值修补遮挡。
- 角色移动、转身、受击、倒地、尸体留存与淡出期间，只有角色根节点的 z 波段整体移动；排序基准始终是角色脚底世界坐标，倒地姿态与淡出不改变名次或内部层级。
- 名次上限为 54（受引擎 z 范围与 `Characters.z = 200` 限制）；超出时钳制并在首次越界时告警，避免静默产生交叉层级。
- 影子仍位于 `World/Shadows`（z_index = 100），不参与角色整体排序，也不会随尸体淡出而影响其他角色。
- 验证：`battle_corpse_visual_test` 对每个角色的全部非影子部件做两两比较；窗口探针 `Tests/_debug/sort_probe.tscn` 用真实骑乘/步兵模型做像素级遮挡对比（波段方案 0 处穿插，旧方案可复现穿插）。

**死亡表现状态机**

- 死亡数据状态（`BattleUnitState.alive = false`）与尸体视觉状态分离：`UnitActor.CorpseState` 仅表示表现，取值为 `NONE / FALLING / LINGERING / FADING`。
- 战斗场景在处理死亡时调用 `UnitActor.play_death()`，同时从可战斗表现集合 `_actors` 移除该单位；尸体不再计入 `get_actor_count()`，不再接受移动/攻击/AI 驱动，也不改变胜负判定与结算。
- 倒地：`HumanVisual` 锁死死亡姿态，`UpperBody` 在 `fall_duration` 内平滑旋转约 `1.25 rad` 并下沉 `2 px`；骑乘时 `HorseVisual` 的马身 rig 同步旋转约 `0.45 rad`、下沉 `5 px` 并轻微压扁。倒地中取消攻击、受击动作与白闪，普通待机/跑动/受击动画不再覆盖该姿态。
- 朝向：倒地姿态与人物镜像方向组合，视觉上始终倒向角色背后，不改变角色碰撞、位置或朝向数据。
- 留存：倒地完成后保持最终倒地姿态，位置冻结在死亡位置，尸体继续留在 `World/Characters` 中按脚底 Y 参与角色整体排序。
- 淡出：`UnitVisual.modulate.a` 统一作用于完整视觉子树（人物、装备、武器、盾牌、马匹与马匹部件），因此不会出现只淡出身体而武器/马匹残留；独立影子按记录的基础透明度同步乘算。材质实例仍按角色独立，不使用共享材质。
- 清理：淡出结束后 `queue_free()` 整个 `UnitActor`，`_exit_tree()` 一并清理独立影子；不重复播放倒地，不残留节点或跨角色引用。
- 尸体期间恢复/受击/攻击入口全部不生效；死亡优先级仍高于受击与僵直。
- 时长统一由 `CorpseConfig`（`Data/Combat/corpse_config.tres`）提供：`fall_duration`、`linger_duration`、`fade_duration`；战斗场景加载一次并注入所有 `UnitActor`，测试可注入缩短配置。

### 4.2 UnitController

每个 `UnitActor` 配套一个 `UnitController`（RefCounted，由场景逐帧驱动）：

- 属性全部来自 `UnitData`：`move_speed`、`attack_range`、`attack`、`attack_interval`。
- 阶段 6 起兵种基础属性按三级体系配置（10/50、20/100、25/180），战斗代码不硬编码数值；骑马不改变 tier 或基础属性。
- 攻击冷却 `_attack_cooldown`、当前目标 `_target`、移动状态 `_is_moving` 都属于攻击者自身；不存在目标级全局攻击锁。
- AI 模式：搜索目标 → 接近 → 攻击 → 目标失效后重新搜索。AI 状态枚举 `AIState.SEEK / APPROACH / ATTACK / STAGGERED` 对外可查询；`STAGGERED` 追加在末尾，旧枚举值不变。
  - 目标超出有效攻击区域时沿目标外围持续接近，不会在远距离执行攻击。
  - 进入区域且冷却结束时攻击；冷却未结束时保持位置。
  - 目标离开区域重新追击；目标死亡或失效后重新选择。
- 玩家模式（`player_tick`）：
  - WASD 方向移动，斜向输入归一化；
  - 不执行 AI 索敌与自主移动；
  - 鼠标左键 `player_attack_at()` 用鼠标世界坐标确定 360°攻击方向，只选择该方向矩形内的一个敌人；
  - 自由攻击：没有有效目标时也会播放完整攻击动画并进入 `attack_interval` 冷却，只是不造成伤害；返回值表示“攻击动作是否释放”，命中情况由 `get_last_attack_target_id()` 区分；
  - 冷却期间点击不释放动作；无敌人时仍按正常攻击间隔出手。
- 一次攻击只命中一个目标；伤害只写选中目标 `BattleUnitState.battle_hp`；HP 归零后 `alive = false`。
- 攻击开始后锁存本次方向、目标与伤害，进入冷却并播放动画；实际扣血在有效帧回调中重新校验后执行，每次攻击最多结算一次。只有前摇/戳击阶段锁定人物朝向，攻击后保持阶段允许移动与转身。
- 受击僵直（`STAGGER_DURATION = 0.24s`，统一配置，不按武器/兵种/等级区分）：真实扣血后进入 `AIState.STAGGERED`，期间停止移动、不能启动新攻击，保留当前目标与手动移动命令；连续受击只把计时刷新到该值，不做加法叠加；结束后恢复原有行为。僵直不修改攻击力、移动速度、最大 HP 等基础属性。
- 死亡优先级高于受击：致命伤害直接走 `_die()`，不进入僵直/受击动作，并清空僵直计时与待结算攻击。多个攻击者仍可在同一帧内分别对同一目标造成伤害，不存在目标级锁。
- 受击反馈只由真实伤害触发：白闪（人物与马匹全部可见部件、罩袍同步，持续 `0.12s` 线性回落）、短促后仰受击动作（`0.18s`，按朝向换算到局部坐标）、僵直。未命中/0 伤害不触发任何受击反馈。
- 玩家控制权切换只改变 `is_player_controlled` 与当前控制 ID，不复制单位、不重置 HP/经验/装备/冷却。
- 战斗移动速度：步兵 = `UnitData.move_speed × 0.6`；骑乘 = `UnitData.move_speed × 0.84`，集中在 `UnitController` 的两个常量中。玩家/AI 共用，大地图部队速度与 UnitData 本身不受影响。
- 实体碰撞与局部避让共同解决重叠：最小中心间距 `28`，死亡单位不参与。

### 4.2.1 统一攻击有效性（`CombatRules`）

玩家与 AI 必须共用 `Scripts/Systems/Combat/combat_rules.gd`，不得各自硬编码距离：

```text
攻击有效 ⇔ 攻击者存活
        ∧ 目标存活
        ∧ 双方属于不同战斗侧
        ∧ 攻击者冷却结束
        ∧ 目标在沿攻击方向旋转的矩形内

矩形长度 = 最终 attack_range + 2 × BODY_RADIUS(26) + WEAPON_FORWARD_BONUS(6)
矩形横向半宽 = 22
前向投影 < 0 的目标（背后）永远排除
```

- `attack_range` 使用 `UnitData` 的最终属性；如果装备了 `weapon_attack_range > 0` 的 WEAPON，则以武器距离覆盖单位基础距离，其他装备的 `attack_range_bonus` 继续叠加。
- 默认长矛/空手使用 UnitConfig 的 `attack_range`；`weapon_sword_01` 当前配置为 14。
- 攻击矩形按方向旋转，不是完整圆形；一次攻击最多命中一个目标。
- `CombatRules` 只决定“是否命中/造成伤害”，不阻止玩家释放攻击动作：玩家空挥仍然播放动画与冷却。
- 玩家方向来自鼠标世界坐标；AI 方向来自攻击者→目标。背向矩形/横向宽度外/前向长度外的目标不会被命中。
- 玩家与 AI 的武器动画使用同一锁定方向；伤害只在该方向动作的有效帧结算，不受动画外观/UI 结束时间影响。
- 多名友军可以同时攻击同一敌人；攻击冷却只属于攻击者，不存在目标级锁。
- 骑乘移动攻击加成由 `StatCalculator.compute_effective_attack()` 统一提供。

### 4.2.2 攻击有效帧与受击反馈（已确认）

**攻击时序**

```text
待机 → 前摇 WINDUP → 攻击动作 THRUST（进度 0.6 为有效帧）→ 保持 POST_DELAY → 恢复 RECOVER → 待机
```

- `HumanVisual.advance_animation()` 在 `THRUST` 阶段越过 `SPEAR_HIT_FRAME_RATIO` 时发出 `attack_hit_frame`，每次攻击只发一次；`UnitVisual`/`UnitActor` 只做转发。
- `UnitController._start_melee_attack()` 在出手瞬间锁存目标/方向/伤害、进入冷却并广播 `EventBus.unit_attack_started`；随后等待动画有效帧。
- `UnitController._on_attack_hit_frame()` → `_resolve_pending_attack()`：先清除待结算状态（保证最多一次），再用 `CombatRules.is_attack_frame_valid()` 重新校验存活、敌对与目标是否仍在锁定方向的矩形内。校验通过才调用目标 `apply_damage()`；不通过则本次落空。
- 没有动画节点/武器枢轴时（纯数据测试、无表现场景），`play_attack()` 返回 false，立即走同一结算路径，保持旧行为。
- 安全上限：动画被重建/中断后若迟迟没有有效帧，`PENDING_ATTACK_TIMEOUT = 0.6s` 超时取消待结算攻击，避免永久挂起。
- 打断规则：有效帧前受击/死亡 → 取消待结算攻击与攻击表现，无伤害；有效帧后伤害已写入，不受后续中断影响（不撤销）。
- 远程攻击（弓箭）沿用箭矢命中流程，不进入近战有效帧路径。

**受击反馈**

- 只在 `apply_damage()` 实际扣除 HP 后触发，顺序：扣血 → 广播 `unit_hit` → 死亡则 `_die()` 并结束；存活则进入僵直并广播 `unit_staggered`。
- 白闪：`UnitVisual` 为每个角色创建独立 `ShaderMaterial`（`Shaders/faction_tabard.gdshader`，`use_faction_color=false` + `flash_amount`），绑定到人物与马匹全部可见部件；阵营罩袍保留自己的材质实例并同步 `flash_amount`；影子部件不参与白闪。材质实例不跨角色共享，连续受击只重置强度，不残留。
- 受击动作：`HumanVisual` 对 `UpperBody` 施加短促后仰位移/倾斜，方向 = 受击方向的反方向，并按人物镜像换算到局部坐标；每帧先按待机/跑动重算基准位置，再叠加受击偏移，因此结束后自动恢复，不会残留图层错位。
- 僵直：`UnitController.tick()/player_tick()` 在计时结束前直接返回，不响应移动/索敌/攻击；`player_attack_at()` 在僵直期间返回 false。保留 `_target` 与手动移动命令，结束后继续。
- 事件契约：`unit_attack_started`（出手瞬间，含空挥）、`unit_hit`（真实扣血后，含伤害与 killed）、`unit_staggered`（僵直刷新时）。未命中/0 伤害不广播 `unit_hit`。

### 4.3 队形与局部避让

- `FormationManager` 负责局部坐标队形槽位：
  - `INFANTRY_LINE`：横向展开，超过 5 列自动增加纵深层数；
  - `DEPTH`：单列纵深；
  - `LOOSE`：更大间距的松散网格；
  - `INFANTRY_SQUARE` / `ARCHER_LINE` / `CAVALRY_WEDGE` 保留扩展。
- `BattleScene` 每 0.4 世界/物理秒刷新队形：
  - 按战斗侧计算最近敌方侧与双方质心；
  - 双方各自在自己的半场列阵：阵线中心 = 己方质心 + 前进方向 × 推进量，双方前排之间保留 `SIDE_LINE_GAP = 90`，不再共用中点坐标；
  - 双方质心距离 ≤ `CONTACT_DISTANCE = 220` 后视为接敌，队形间距 × `CONTACT_SPACING_MULTIPLIER = 1.35` 自动放松；
  - 同一侧的多支部队使用 `PARTY_LANE_SPACING = 170` 分配独立 lane；
  - 为每个单位写入 `UnitController.formation_slot`。
  - 槽位分配前按近战/远程排序：远程单位排在队形后列，避免弓箭手站到第一排；排序只改变槽位分配顺序，不改变单位数据。
- `BattleScene` 每 0.3 秒构建局部邻居缓存（`NEIGHBOR_RADIUS = 56`），避免每个单位逐帧遍历全场。
- 同一周期统计每个战斗侧的目标占用（`_refresh_target_claims`），只遍历己方控制器。
- 队形间距按部队内是否有骑乘单位选择：步行 `40`，存在骑乘单位时 `56`，避免马匹部件明显重叠。
- `UnitController` 移动时叠加分离力（Separation）：友军半径 `44`、敌军半径 `34`，并保持向队形槽位的凝聚力。
- 目标选择使用“距离 + 友军占用惩罚”：同一敌人已有较多友军选择时，后来者会转向其他合适目标；已进入攻击范围的单位不重新索敌。
- 未进入射程时，远距离按队形槽位方向接近；距离 ≤ `CLOSE_APPROACH_RANGE = 140` 后按自身当前包围角度接近，并带少量切向偏移，让同一目标周围的士兵保持分散。
- 目标周围位置不足时，局部避让会让单位互相推开；当前没有显式的“攻击槽位等待/重新分配”，也没有寻路、地形阻挡与复杂包围/冲锋战术。
- 未来键盘部队指令接口：`set_party_move_order()` / `clear_party_move_order()` / `set_party_formation()`。

### 4.3.1 移动速度、初始部署与实体碰撞

- 战斗移动速度系数集中在 `UnitController`：
  - 步兵 `BATTLE_MOVE_SPEED_MULTIPLIER = 0.6`：民兵 60→36；职业步兵 55→33；玩家角色 75→45（保持不变）；
  - 骑乘 `BATTLE_MOUNTED_MOVE_SPEED_MULTIPLIER = 0.84`：民兵 85→71.4；职业步兵 80→67.2；玩家角色 100→84；
  - 只影响战斗场景，不修改 UnitConfig 或 `UnitData.move_speed`，也不影响大地图 `PartyData.movement_speed`。
- 战场有效区域为 `BATTLEFIELD_WIDTH = 1800` × `BATTLEFIELD_HEIGHT = 1024`（约旧 1280×720 的 2 倍）；士兵像素、动画比例与相机 960×540 视野不变。
- 初始部署集中参数化：`INITIAL_ARMY_DISTANCE = 1580`、`SPAWN_MARGIN_X = (1800 - 1580) / 2 = 110`、`INITIAL_DEPLOYMENT_DISTANCE = 1580`；多侧部署复用同一套常量，不改变双方内部阵型与 Party Lane。
- 实体碰撞：
  - `UnitController.MIN_BODY_DISTANCE = 28`，在 tick/player_tick 开始处执行 2 次最小间距推开；
  - 与局部避让（Separation）协同；局部避让负责提前调整方向，硬间距作为最后空间约束；
  - 死亡单位跳过，不阻挡其他单位；碰撞不改变伤害、攻击范围或队形目标。
- 屏幕显示：项目窗口/Viewport 1920×1080，Stretch 关闭（原生像素）；战斗相机通过 `SceneCameraRig` 使用统一视野基准 `960×540`（1920×1080 下为 2 倍缩放），并向下偏移 30；大地图相机默认 1.5 倍。
- 战斗摄像机默认平滑跟随当前玩家控制单位；切换控制权后自动跟随新单位；观战时保持当前位置。`F` 切换自由视角，WASD/方向键移动镜头，自由视角不移动角色；镜头受战场 `1800×1024` 边界限制。

### 4.4 玩家角色与当前控制权

区分两个概念：

- **玩家角色身份**：`UnitData.is_player_character`，持久化，表示新游戏创建的主角 Unit。
- **当前控制权**：`BattleScene._controlled_unit_id`，运行时状态，可切换到任意存活友军。

初始控制：

1. 在玩家侧寻找存活且 `is_player_character == true` 的单位。
2. 找不到时退化到玩家侧第一名存活单位（兼容旧存档）。

玩家角色被击败：

1. 停止玩家输入与自主攻击/移动。
2. 战斗场景本地暂停（`_scene_paused`），不触碰 TimeManager。
3. 若同侧还有存活友军，弹出控制权转移面板：
   - 显示姓名 / 兵种 / 等级 / 剩余 HP；
   - 选择一名友军接管，或进入观战。
4. 接管只切换 `is_player_controlled` 与当前控制 ID；不复制数据、不重置 HP/经验/装备/冷却。
5. 若没有存活友军，进入观战/战败流程，由战斗侧胜负判定结算。
6. 观战模式下所有单位由 AI 控制，WASD 与左键不再生效。

控制权不改变阵营、所属部队与 UnitData 身份；同一时间只有一个 `is_player_controlled` 单位。

## 5. 数据权威

| 数据 | 战斗期间 | 战斗结束后 |
|---|---|---|
| HP | `BattleUnitState.battle_hp` | `BattleManager` 写回 `UnitData.current_hp` |
| 位置（战斗内） | `BattleUnitState.battle_position` | 丢弃 |
| 大地图位置 | `PartyData.world_position` | 不变 |
| 部队状态 | `PartyData.battle_state` | 解锁为 `AVAILABLE` |
| 成员关系 | 不修改 | 阵亡单位移除，存活单位保留 |
| 经验/死亡 | 只记录 `alive` | `BattleManager` 统一结算 |

禁止 `WorldSimulation` 与 `BattleScene` 同时修改同一单位的战斗 HP。

## 6. 战斗结束与结算

### 6.1 胜负条件

- 按战斗侧统计存活单位：只剩 side 0 → `ATTACKER_VICTORY`，只剩 side 1 → `DEFENDER_VICTORY`。
- 只剩其他战斗侧 → `SIDE_VICTORY`，`winning_side_index` 记录实际获胜侧。
- 所有侧都无存活单位 → `DRAW`。
- 玩家主动撤退 → `RETREATED`，不视为全员阵亡。
- 玩家角色被击败但同侧仍有友军时，战斗继续；只有玩家所在侧全部失去战斗能力才判定失败。
- 场景根据玩家所在侧显示“胜利/失败/平局/已撤退”，不假设玩家固定为 attacker。
- 场景显示结果面板；玩家点击“返回大地图”时执行最终结算。

### 6.2 结算顺序

1. 通过 `get_battle(battle_id)` 从 `active_battles` 取会话，防止无效 ID 和重复结算。
2. 对每个 HP≤0 的非玩家单位执行一次负伤判定（见第 16 节），结果写入 `BattleUnitState.wounded` 与 `wounded_decided`；预览与最终结算共用，不重复掷骰。
3. 根据结果确定获胜/失败侧，生成 `BattleResultData`（预览或最终）。
4. 基于战斗中的 `BattleUnitState` 统计各部队永久阵亡/伤兵/存活。
5. 结算经验：仅存活单位获得基础经验 + 获胜侧额外经验；伤兵与阵亡均为 0；通过 `UnitManager.add_exp()` 升级。
6. 结算奖励：仅玩家参与且玩家所在侧获胜时，生成金币/装备战利品并写入 `PlayerProfile`；伤兵保留装备，不进入战利品。
7. 若胜利成立，构建俘虏池（战败方伤兵）并按实际参战单位数分配（见第 17 节）。
8. 对每个 `BattleUnitState`：
   - 存活：`UnitData.current_hp = battle_hp`（clamp 到 `[0, max_hp]`），状态恢复 `ACTIVE`。
   - 伤兵：`mark_wounded()`，HP=0，保留原部队成员身份、等级、装备与经验。
   - 永久阵亡：`mark_dead()`，经 `PartyManager.remove_member()` 清空归属，再 `UnitManager.remove_unit()` 删除数据，广播 `unit_died`。
9. 领取俘虏：非玩家胜利方立即写入 `PartyManager.add_prisoner()`；玩家份额挂起，等待战后选择界面确认。
10. 解锁部队：有可行动成员的恢复为 `AVAILABLE`；只有伤兵的部队保留成员但暂停移动/AI，等待治疗；全员永久阵亡的置为 `DISABLED`。
11. 将 `BattleResultData` 标记为 finalized，保存到 `session.final_result`；从 `active_battles` 与 `party_battle_lookup` 中只移除本场战斗，若它是玩家屏幕战斗再清理 `current_battle`。
12. 移除 `battle` 暂停原因，恢复此前世界时间状态；广播 `battle_finished`。
13. 场景控制器切换回大地图；若玩家有未确认俘虏份额，先显示 `PrisonerSelectionPanel`。

阵亡单位不会以“0 HP 但仍属于部队”的形式残留；伤兵以 `WOUNDED` 状态保留；存活与伤兵都保留原 `unit_id` 与成员关系。
同一场战斗只能结算一次，重复调用不会再次发经验、奖励或俘虏。

### 6.3 经验与奖励规则

| 项目 | 规则 |
|---|---|
| 战斗内有效伤害 | 实际攻击者本人 +1/次（HP 实际减少） |
| 战斗内击杀 | 实际攻击者本人额外 +10（该次合计 +11） |
| 未命中 / 0 伤害 / 目标已死亡 | 0 |
| 存活经验 | 参战且存活：+10 |
| 获胜额外经验 | 获胜侧存活单位再 +20 |
| 阵亡/伤兵经验 | 0 |
| 中止战斗 | 不发放经验 |
| 撤退 | 存活单位仅获得基础经验，无获胜奖励 |
| 金币 | 玩家参与且获胜：50 + 敌方阵亡人数 × 5 |
| 战利品 | 从永久阵亡敌方单位装备中取最多 3 件唯一装备 ID；伤兵不参与掉落 |
| 玩家未参与 | NPC 对 NPC 战斗只发经验，不发玩家奖励 |

- 战斗内伤害经验在 `UnitController.apply_damage(amount, source)` 现场写入，近战与远程共用；经验属于实际攻击者，不属于部队或攻击发起侧。
- 目标死亡后再次受到伤害会被拒绝，因此同一敌人的击杀经验最多发放一次。
- 战斗结束的存活/获胜经验仍按原规则通过 `UnitManager.add_exp()` 结算；两段经验都进入同一五级经验体系。
- 经验与奖励集中配置在 `BattleManager` 常量中；同一场战斗只应用一次。

### 6.4 防守方全灭后的部队

- 战斗结算先按既有规则得到空部队；随后 `EventBus.battle_finished` 触发 `WorldContext._cleanup_defeated_parties()`。
- **没有任何成员**的非玩家部队从 `PartyManager` 移除，不再出现在大地图、移动、遭遇、追击或 AI 目标中；其他部队指向它的目标/跟随/战斗响应引用同时清空。
- 仍有成员（包括只有伤兵）的部队保留，等待伤兵治疗恢复；不为“失败”本身删除部队。
- 玩家部队不参与此清理，始终作为身份锚点保留；玩家角色被俘时由 [Captivity_System.md](Captivity_System.md) 接管。
- 撤退单位不会从部队中移除；其 `BattleParticipant.status = WITHDRAWN`，结算后仍为存活成员。

### 6.5 撤退与结果面板

- `BattleScene` 为玩家提供“撤退”按钮：标记玩家侧撤退、停止战斗推进、显示“已撤退”结果。
- 返回大地图时调用 `finish_battle(RETREATED)`：存活单位写回 HP，不产生阵亡，不发胜利奖励。
- `BattleManager.retreat_side(side_index)` 供未来 AI/指令复用；离屏战斗会立即结算为 RETREATED。
- 结果面板显示：胜利/失败/平局/已撤退、各战斗侧名称、我方与敌方存活/阵亡、玩家经验、金币与战利品。
- 结果面板适配多方战斗，按战斗侧逐行展示。
- 玩家角色被击败但友军存活时先进入控制权转移/观战，不会直接判负。

## 7. 战斗期间的世界与存档

- 屏幕内战斗压入 `battle` 暂停原因，WorldTime = 0；战斗场景用物理帧独立推进。
- 玩家遭遇对话使用独立的 `encounter_dialogue` 暂停原因；进入战斗后移除，战斗暂停接管。
- `WorldContext` 在战斗期间保持存在，参战部队锁定。
- `GameManager.save_game()` 在 `has_any_active_battles()` 为真时返回 `ERR_BUSY`，禁止任意战斗（包括 AI 离屏战斗）期间存档，避免静默丢失进行中的战斗。
- `BattleSession` 不进入存档；不改变存档 Schema。

## 8. 中途加入

```text
其他部队进入战斗区域
  → 检查距离 <= JOIN_RADIUS(60) 且部队可用、未参战、有存活士兵
  → get_join_side(party_id, battle_id) 根据 FactionManager 关系选择战斗侧
      ├── 对某侧所有成员均无敌对关系，且对另一侧存在敌对 → 加入该侧
      ├── 对现有所有侧都敌对 → 新建独立战斗侧
      └── 与任何一方都没有敌对关系 → 不加入
  → try_join_battle(party_id, battle_id)
      ├── 部队锁定为 IN_BATTLE
      ├── 为存活成员创建 BattleUnitState
      ├── 加入 participants / side_unit_ids
      ├── 玩家加入时转换为屏幕战斗（暂停世界；由加入/离开交互面板触发）
      └── EventBus.battle_participant_joined
```

- `BattleManager.add_reinforcement(party_id, battle_id)` 复用 `try_join_battle()`。
- 加入接口必须显式传入 `battle_id`，禁止在多场战斗环境下通过 `current_battle` 猜测目标战斗。
- 同一部队不能同时参与两场战斗：`party_battle_lookup` 与 `get_battle_for_party()` 是唯一归属判断。
- AI 的 `_try_respond_to_battle()` 遍历全部离屏战斗，选择可加入且距离最近的一场接近，实际加入仍由 EncounterManager 处理。
- EncounterManager 的两支部队若已分别处于不同战斗，不会合并会话，也不会让任何一方同时参战。
- 侧别统一由 `FactionManager.is_party_hostile()` / `is_party_friendly()` 按政治身份（贵族 → 家族 → 王国）判定；无家族部队回退到阵营关系。

### 8.1 增援（阶段 8）

- 新遭遇使用 `start_battle_by_sides()` 新建 `BattleSession`；增援使用 `try_join_battle()` / `add_reinforcement()` 加入**既有** `BattleSession`，不新建会话。
- 增援参与者写入：
  - `BattleParticipant.is_reinforcement = true`
  - `reinforcement_battle_id = session.battle_id`
  - `reinforcement_arrival_time = TimeManager.world_elapsed_seconds`
- `_add_party_units()` 把上述字段复制到每个 `BattleUnitState`，便于表现层区分初始部署与增援。
- 广播 `EventBus.battle_participant_joined`（通用）与 `EventBus.party_reinforced(battle_id, party_id, noble_id, side_index)`（增援专用）。
- 战斗场景收到 `party_reinforced` 后：
  1. 确保该战斗侧已注册；
  2. 从战场中心指向远离方向，在阵线后方 `REINFORCEMENT_REAR_DISTANCE = 240` 处生成；
  3. 使用 3 列网格 + 最多 96 次尝试寻找空位，间距 `REINFORCEMENT_MIN_SPACING = 38`，并 clamp 在战场内；
  4. 只创建新的 `UnitActor` / `UnitController`，不移动、不重置既有单位，不改变攻击冷却与战斗进度。
- 若增援部队加入玩家所在战斗侧，且不是玩家部队，战斗场景在顶部中央显示增援提示：
  - 有家族旗帜：徽章 + “是XXX的旗帜，AAA带部队来增援我们了！”
  - 无旗帜：纯文本 “AAA带部队来增援我们了！”
  - 提示排队、逐条淡入淡出（`REINFORCEMENT_PROMPT_DURATION = 2.8` 秒），不暂停、不阻塞操作。
- 敌方加入、玩家部队自身加入都不显示提示。
- 存在待生成增援时，战斗场景暂缓 `_check_battle_end()`，避免在增援单位生成前误判结束。

## 9. 离屏战斗（按游戏小时结算）

玩家未参与的 NPC 对 NPC 战斗不创建小地图场景，使用 `BattleSession` + `BattleUnitState` 数据模拟：

- `start_battle(..., offscreen = true)` 不压入 `battle` 暂停，世界继续推进。
- `WorldSimulation.on_world_tick` 调用 `BattleManager.tick(delta)`；它先复制全部有效战斗快照，再逐场推进。
- 每场离屏战斗各自累计世界时间，满 1 个游戏小时
  （`OffscreenBattleConfig.settlement_interval_world_seconds = 6` 世界秒）后执行一次伤亡结算。
- 只有 `offscreen == true` 的战斗会推进小时结算；屏幕战斗期间世界暂停，其结算由 BattleScene 驱动。
- 某场战斗结束并删除后，本次 tick 继续处理其他战斗，不提前退出。
- 每场离屏战斗拥有独立 `OffscreenBattleResolver` 与随机序列；一场战斗的创建、结算或结束不会改变其他战斗的随机状态。固定 `random_seed` 时仍可稳定复现。
- 每次结算都写入 `BattleUnitState`；阵亡单位立即从 `PartyData.member_unit_ids` 移除，但 `UnitData` 保留到最终结算，避免提前丢失战利品与阵亡事件；最终统一走 `finish_battle()` 写回、删除阵亡单位、发放经验/奖励并解锁部队。
- 同一场战斗只结算一次；达到一方全灭、平局或 48 小时安全上限时结束。
- 战斗期间参战部队锁定在大地图上，第三方可以接近并中途加入。
- 玩家靠近可加入的离屏战斗时，先弹出“加入/离开”交互面板：
  - 加入：`try_join_battle()` 加入已有战斗，`offscreen` 切换为 false，保留已发生的伤亡与剩余 HP，进入 `BattleScene`；
  - 离开：不参战，NPC 战斗继续，玩家停留在当前位置。
- 玩家加入后 `BattleManager.tick()` 立即跳过该会话，不会重复结算当前小时。
- 玩家被主动拦截时先进入强制遭遇对话；选择战斗后创建屏幕战斗并由 WorldMap 切换场景。
- `battle_started` 信号仍用于其他屏幕战斗入口的自动场景切换；`battle_participants_updated` 在每次小时结算后广播，供大地图战斗面板刷新人数。

### 9.1 小时伤亡公式

公式集中在 `Scripts/Systems/Combat/offscreen_battle_resolver.gd`，参数在
`Scripts/Config/offscreen_battle_config.gd` 与 `Data/Combat/offscreen_battle_default.tres`：

```text
单兵战力 = (攻击 × attack_power_weight + 最大生命 × hp_power_weight)
          × (1 + (tier - 1) × tier_power_bonus_per_level)
          × (骑乘 ? 1 + mounted_power_bonus : 1)
          × 剩余生命比例

战斗侧战力 = 该侧全部存活单位战力之和
敌方压力比 = 敌方总战力 / (己方总战力 + 敌方总战力)

每小时伤亡比例 = 基础伤亡比例 × clamp(敌方压力比 × pressure_scale,
                                        min_pressure_factor,
                                        max_pressure_factor)
                 × 随机波动
```

- 伤亡按小数累计（`offscreen_casualty_credit`），小部队不会每小时固定损失同一数量。
- 战力较低的单位更可能被选中阵亡；等级、生命、骑乘状态与剩余战力都会影响结果。
- 随机波动默认 ±30%；相同配置可以通过 `random_seed` 复现。
- 多战斗侧时，敌方压力来自所有其他战斗侧的战力之和。
- 伤亡数不会超过该侧当前存活人数，HP 不会降为负数。

### 9.2 结束与结果

- 每次小时结算后检查存活战斗侧。存活侧只统计至少拥有一名 `alive == true` 且 `battle_hp > 0` 单位的战斗侧，0 人战斗侧不计入：
  - 只剩一个侧 → 该侧获胜，立即结束；
  - 所有侧均无存活单位 → 平局，立即结束；
  - 多于一个侧存活 → 继续战斗；
  - 达到 `max_settlement_hours`（默认 48）仍有多侧存活 → 比较剩余总战力，最高者获胜；并列则平局。
- 不得要求双方都全灭才结束；一方全灭即按上述规则立即结算。
- 结束统一调用 `finish_battle()`，生成 `BattleResultData`，写回存活 HP、移除阵亡单位、发放经验与玩家奖励（仅玩家参与且获胜）。
- 离屏战斗的胜负侧索引仍然写入 `winning_side_index`；0/1 使用旧 `ATTACKER_VICTORY` / `DEFENDER_VICTORY`，其他侧使用 `SIDE_VICTORY`。

## 10. 实现状态

| 项 | 状态 |
|---|---|
| `BattleSession` / `BattleUnitState` | 已实现 |
| `BattleParticipant` / 多战斗侧数据 | 已实现 |
| `BattleManager.start_battle` | 已实现（校验、锁定、会话，支持 offscreen） |
| `BattleManager.start_battle_by_sides` | 已实现（任意战斗侧） |
| `BattleManager.finish_battle` | 已实现（BattleResult、HP 写回、阵亡移除、经验/奖励、解锁、防重复） |
| `BattleResultData` 统一结果 | 已实现（胜负/伤亡/经验/奖励/结束原因/finalized） |
| 玩家角色 Unit | 已实现（`player_hero`，普通 UnitData/StatCalculator/装备） |
| 统一攻击有效性 `CombatRules` | 已实现（存活/敌对/冷却/射程统一判断） |
| 多人围攻同一目标 | 已实现（攻击冷却属于攻击者，无目标级攻击锁） |
| WASD 移动 / 鼠标攻击 | 已实现（斜向归一化、自由空挥、攻击间隔、360°方向矩形与阵营校验） |
| AI 搜索/接近/攻击/重新索敌 | 已实现（`AIState`，方向矩形外不攻击，外围进攻点分散站位） |
| 武器攻击距离 | 已实现（WEAPON.weapon_attack_range 覆盖单位基础射程；长矛前向 +6） |
| 单次攻击单目标 | 已实现（矩形内只选一个；其他目标不受伤） |
| 实体碰撞 | 已实现（最小中心间距 28 + 局部避让；死亡单位不阻挡） |
| 战斗降速 / 初始部署 | 已实现（步兵 0.6、骑乘 0.84；战场 1800×1024、阵线间距 1580、边距 110） |
| 1920×1080 / 战斗相机 | 已实现（原生 Viewport；战斗相机 2 倍缩放） |
| 步兵/骑兵待机/移动动画 | 已实现（腿部挂载身体并继承整体变换；马身整体跃动为主且幅度下调、马腿辅助动作适度增大；骑马影子随抬升轻微缩小/变淡） |
| 控制权转移 / 观战 | 已实现（存活友军列表、本地 SceneTime 暂停；列表区分骑乘） |
| 基础队形 / 局部避让 | 已实现（LINE/DEPTH/LOOSE，双方半场列阵 + 接敌放松 + separation + 周期邻居缓存；骑乘加宽间距） |
| 目标分流 / 接敌站位 | 已实现（目标占用惩罚 + 近距离包围角度 + 切向偏移；无显式攻击槽位分配） |
| 临时部件美术 / 阵营罩袍 | 已实现（`UnitVisual` + 实际 PNG；罩袍着色器；缺少缨饰素材时安全回退） |
| 人物/马匹分组与最终层级 | 已实现（PartVisual/HumanVisual/HorseVisual + VisualLayers） |
| 骑乘 15 像素偏移 | 已实现（仅 HumanVisual 上移；马匹与 UnitActor 不变） |
| 长矛攻击/保持/恢复动画 | 已实现（0.14s 前摇后移、0.14s 方向戳击、360°方向、保持 4 秒、0.35 秒恢复） |
| 攻击有效帧伤害 | 已实现（戳击进度 0.6 发出一次 `attack_hit_frame`；前摇/戳击前半无伤害；有效帧重新校验；每次攻击最多结算一次） |
| 受击白闪 | 已实现（每角色独立材质实例，覆盖人物/马匹/武器/罩袍，影子不含；0.12s 回落，不跨角色共享） |
| 受击动作 | 已实现（`UpperBody` 短促后仰，按朝向镜像换算，0.18s 后自动恢复，不残留偏移） |
| 受击僵直 | 已实现（0.24s 统一时长；停止移动、不能启动新攻击；连续受击刷新不叠加；死亡优先） |
| 攻击/命中/僵直事件 | 已实现（`unit_attack_started` / `unit_hit` / `unit_staggered`，复用 EventBus） |
| 完整角色动态层级 | 已实现（`BattleScene` 每物理帧按脚底 Y 排序全部角色并写入 `UnitActor` z 波段；内部 `VisualLayers` 相对层级不变；不按单件武器排序；CanvasGroup 方案已验证无效并移除） |
| 死亡倒地 / 尸体留存 / 淡出 | 已实现（`FALLING → LINGERING → FADING → queue_free`；`CorpseConfig` 统一时长；尸体留在 Characters 参与 Y 排序） |
| 尸体完整图层淡出 | 已实现（`modulate.a` 覆盖人物/装备/武器/马匹；独立影子基础透明度同步；材质实例不共享） |
| 人物/骑马影子互斥 | 已实现（按骑乘状态切换） |
| 多支友军参战分区 | 已实现（party lane） |
| 撤退 / 结果面板 | 已实现（撤退按钮、RETREATED、伤亡/经验/奖励展示） |
| 战后经验 / 金币 / 战利品 | 已实现（仅玩家获胜；写入 PlayerProfile） |
| 中途加入 / 独立第三方 | 已实现（关系判定 + 距离校验） |
| 增援加入既有战斗 | 已实现（`try_join_battle` / `add_reinforcement`，不新建会话） |
| 增援逐单位标记 | 已实现（`is_reinforcement` / `reinforcement_battle_id` / `reinforcement_arrival_time`） |
| 增援后方展开 | 已实现（后方 240 像素、3 列网格、间距 38、边界 clamp、不重叠） |
| 增援提示与旗帜 | 已实现（仅玩家侧 NPC；家族文本 + 徽章或纯文本；排队淡入淡出、不暂停） |
| `party_reinforced` 事件 | 已实现（`battle_id`, `party_id`, `noble_id`, `side_index`） |
| 大地图部队对话 UI | 已实现（中立/友好部队） |
| 玩家被主动拦截遭遇对话 | 已实现（底部 NPC 对话、领袖头像、`ENEMY_PURSUIT` 禁止离开） |
| 统一大地图遭遇距离 | 已实现（50，`EncounterManager`） |
| 玩家接近离屏战斗加入/离开 | 已实现（`battle_encounter_dialogue`） |
| 战斗场景与士兵生成 | 已实现（UnitVisual 临时部件，支持多侧） |
| 玩家单角色控制 | 已实现（其余友军 AI） |
| 同侧不互相攻击 | 已实现（按战斗侧构建敌人列表） |
| 自动索敌 / 移动 / 攻击 / 死亡 | 已实现 |
| 战斗中禁止存档 | 已实现（检查全部进行中战斗，含 AI 离屏战斗） |
| 多场战斗并行 | 已实现（`active_battles` / `party_battle_lookup`；AI 离屏战斗互不阻塞，玩家屏幕战斗仍只有一场） |
| 离屏 AI 对 AI 按小时结算 | 已实现（每游戏小时伤亡、战力/等级/骑乘/随机、48 小时上限；每场独立 Resolver） |
| 一方全灭立即结束 | 已实现（存活侧只统计有存活单位的战斗侧，0 人不计入） |
| 大地图多战斗标记 | 已实现（按 `battle_id` 独立创建/更新/删除，参战图标只按自身战斗隐藏） |
| 战斗摄像机跟随/自由视角 | 已实现（共享 `SceneCameraRig`，F 切换，战场边界） |
| 左右手武器独立层级 | 已实现（右手 -10 / 左手 -45，左手低于马头） |
| 人物头部与头盔分离 | 已实现（独立 Head / Helmet 部件；装备视觉按 `EquipmentConfig` 注入） |
| 满血隐藏生命条 | 已实现（独立 `UnitHealthBar`；名称只对当前控制单位显示，与生命条独立） |
| 玩家中途加入离屏战斗 | 已实现 |
| 弓箭手 / 远程射程 | 已实现（武器 `attack_type = RANGED`、`weapon_attack_range` 覆盖、`CombatRules` 圆形远程判定） |
| 箭矢弹道 | 已实现（`ArrowProjectile` + `ProjectileManager`；地面投影 + 抛物线视觉高度；终点冻结） |
| 高度命中 / 射失 | 已实现（地面半径 18 + 身高判定；移动目标自然射失，每箭最多一次伤害） |
| 远程 AI | 已实现（射程内站定、射程外接近、过近后撤、目标失效重选、后排队形槽位） |
| 玩家射箭 | 已实现（鼠标世界坐标、与 AI 共用发射入口、独立 3 秒冷却） |
| 复杂阵型、骑兵冲锋、士气 | 未实现 |

## 11. 待确认

- 屏幕内战斗 WorldTime 采用 0（当前）还是 0.5（D008 初版方案）。
- 玩家战败后的处理（逃脱 / 被俘 / 损失）。
- 战斗胜负条件是否加入撤退与时间限制。
- 离屏战斗的长期平衡、伤兵/俘虏与士气；当前只有阵亡，没有伤兵。
- 最大参战部队/战斗侧数量与同屏单位上限。
- 遭遇对话是否扩展谈判、逃跑、缴赎等选项（当前明确不做）。
- 玩家角色永久阵亡后的复活/继承/重开流程尚未设计。
- AI 主动撤退、追击撤退方与俘虏规则。
- 队形参数（间距、lane、转向）的平衡与更复杂战术队形。
- 目标周围攻击槽位的显式分配与“位置不足时等待”策略（当前靠外围进攻点 + 局部避让）。
- 长矛有效帧比例（0.6）、受击僵直时长（0.24s）、白闪时长（0.12s）与受击动作幅度的手感平衡；这些参数集中在 `HumanVisual` / `UnitController`，可单独调整。
- 受击位移未实现（当前只有身体后仰，不改变战斗位置）；武器轨迹与命中音效资源未实现，`unit_attack_started` / `unit_hit` 已可作为触发点。
- 长矛前摇/戳击/保持/恢复时长、待机/跑动幅度与最终美术的平衡；马腿已改为前后成组跃马，但仍为程序化 Sprite 动画，不是骨骼/逐帧动画。
- 尸体表现时长与倒地幅度仍为暂定值：默认倒地 `0.55s`、留存 `6.0s`、淡出 `1.2s`，倒地角度与下沉量在 `HumanVisual` / `HorseVisual` 中集中配置；需在实际画面中确认重量感、留存节奏与淡出观感。
- 尸体是否需要在留存期响应鼠标悬停/点击（当前完全不参与战斗与选择，选中圈、名称、生命条均隐藏）。
- `EquipmentConfig.visual_layer` 若配置到内部波段之外（当前应为 -80…-10，数据均使用 0 表示默认），会破坏角色整体 z 波段；同屏角色超过 55 时也需要压缩内部层级跨度或拆分绘制。
- `art/` 已提供 1/2/3 级独立头盔并被外观随机使用；左手武器（盾牌）仍缺正式贴图，`LeftHandWeapon` 插槽与 `EquipmentConfig` 视觉字段已就绪，填入素材后即可显示。
- 部队面板预览的尺寸、缩放与装备差异化外观。
- `art/正式人物美术/` 已提供巴里/墨西西家族独立缨饰、罩袍、旗帜与长矛；无家族普通士兵仍使用身体贴图蓝色区域着色，缨饰部件为空。
- 战利品/装备物品栏 UI 与经济系统。
- 阵亡单位是否永久删除，或转为伤兵/俘虏数据。

## 12. 家族外观与战斗数据隔离（阶段 6 新增）

- 家族罩袍、领袖缨饰、等级头盔与家族长矛都是 `UnitVisual` 表现层数据，不参与 `BattleUnitState`、`StatCalculator` 或伤害计算。
- 装备 `HEAD` / `WEAPON` 的视觉路径优先于外观随机结果；装备数据本身不变。
- 玩家身份（`is_player_character`）、当前控制权（`UnitActor.is_controlled`）与部队领袖（`PartyData.leader_unit_id`）在战斗场景中继续保持分离。
- NPC 家族骑士由 `AIManager` 控制部队移动；进入战斗后仍按现有 `BattleScene` 单位 AI 运行，不需要特殊分支。
- 外观选择随 `UnitData` 持久化，战斗前后不重新随机。

## 13. 战斗结果延迟与战后恢复（阶段 6 后续）

### 13.1 胜利结果面板延迟

- 胜负判定时立即 `build_battle_result(..., apply=false)` 生成结果数据。
- 仅玩家获胜进入 `VICTORY_RESULT_DELAY = 3.0` 秒延迟；失败、撤退、平局立即展示。
- 计时使用 `BattleScene._physics_process(delta)`，不使用世界时间；场景退出即取消。
- `_result_shown` 防止重复展示；测试可用 `set_result_delay_enabled(false)` / `skip_result_delay()`。

### 13.2 战后部队解锁

- `BattleManager._unlock_session_parties()` 对存活部队：
  - 设置 `engagement_cooldown_until = 世界时间 + 30`（运行时字段，不入档）；
  - 清除 `current_target_id`、`current_order`、`attack_intent`、`focus_party_id`；
  - **不**把 `target_position` 重置为当前位置。
- 无成员部队置为 `DISABLED`。
- 两方与多方战斗共用该流程；结算后清空 `current_battle`，大地图标记与汇总列随之清理。

## 14. 弓箭手与远程箭矢（阶段 6 后续）

### 14.1 单位与判定入口

- 远程单位仍是普通 `UnitController`；`is_ranged_unit()` 只读取 `UnitData.is_ranged_attacker()`，不做兵种名/class 分支。
- 远程射程取 `UnitData.attack_range`，由 `weapon_bow_01.weapon_attack_range = 360` 覆盖基础值；`CombatRules` 新增：

```text
ranged_attack_range(unit)      → 最终 attack_range
is_in_ranged_range(a, b)       → 两个地面中心的距离 ≤ 远程射程（圆形，不是 360°近战矩形）
can_ranged_attack(a, b)        → 攻击者存活 ∧ 目标存活 ∧ 敌对 ∧ 冷却结束 ∧ 在射程内
```

- 近战仍走 4.2.1 的定向矩形；两套判定互不替代，单位按武器类型进入对应分支。
- AI 与玩家共用 `UnitController._fire_ranged_at(ground_target, enemies)`：冻结终点、取 `get_attack_damage()`、请求 `ProjectileManager` 生成箭矢、进入攻击冷却、播放远程动画。
- AI 的 `tick()` 对远程单位进入 `_tick_ranged`：射程内站定射击；射程外接近到目标外围（`RANGED_STANDOFF_FACTOR = 0.82` 射程）；敌人近于 `RANGED_MIN_RANGE = 110` 时后撤并面向目标；目标失效后在同一 tick 重新索敌。
- 玩家射箭入口仍是 `BattleScene.try_player_attack_at(world_pos)`；鼠标屏幕坐标在 `_unhandled_input` 中经 `get_global_mouse_position()` 转为战场世界坐标，不直接使用屏幕像素。
- 控制权切换只改变输入归属；新接管的弓箭手使用自身 `attack_interval = 3.0`，不继承原控制单位的冷却。

### 14.2 箭矢实体与飞行

- `ArrowProjectile`（`Node2D`，挂在 `Characters` 下）由 `ProjectileManager` 创建与推进；`BattleScene._physics_process(delta)` 在控制器 tick 之后调用 `advance(delta)`。
- 节点 `position` 是**地面投影**，只用于 Y 排序与地面距离判定；视觉 Sprite 是子节点，按当前高度向上偏移。高度不参与 `position`，因此不会影响 Y 排序。
- 地面位置线性插值：`P(t) = P0 + (P1 - P0) · t`，`t = elapsed / duration`，`duration = ground_distance / projectile_speed`。
- 高度曲线：`h(t) = launch_height · (1 - t) + 4 · arc_height · t · (1 - t)`；发射高度来自射手 `get_ranged_launch_info()`（默认 20），视觉位置为 `P_visual = P_ground + (0, -h)`。
- 箭矢旋转取视觉速度向量（地面速度 + 垂直高度变化）的角度 `+ PI/2`，使箭尖朝飞行方向；素材原始箭头朝上。
- 终点在发射瞬间冻结；目标之后移动不会更新终点，因此产生自然射失，不使用随机命中率。
- 箭矢 `z_index = UnitActor.ACTOR_Z_INDEX`（0），不参与 `UnitActor` 的角色整体 z 波段；仍按地面投影位置绘制，没有独立的高空层。
- 生命期结束条件：命中一个有效目标、`t >= 1` 落地、或超过 `MAX_FLIGHT_TIME = 3.0` 秒。每支箭最多结算一次伤害。

### 14.3 高度命中与伤害

```text
命中 ⇔ 地面距离 ≤ HIT_GROUND_RADIUS(18)
     ∧ 当前高度 ≤ 目标 unit_data.body_height
     ∧ 目标存活
     ∧ 目标属于其他战斗侧（与射手敌对）
```

- 敌人从箭下经过但视觉高度高于其身高 → 不受伤（“从头顶飞过”）。
- 目标已死亡、失效或同侧 → 不结算伤害；箭矢继续飞行直至落地。
- 伤害通过既有 `BattleUnitState` 伤害入口写入，与近战一致；不直接写 `UnitData`。
- 受击判定使用单位身高而不是固定点，骑乘单位身高由 `StatCalculator` 加上骑乘加成。

### 14.4 表现

- 弓使用 `art/我的骑砍临时美术/武器弓临时.png`（48×48，默认朝左）；装备锚点 `visual_anchor = (27,36)`，对应素材左下角 `(27,12)`，旋转中心在握把处。
- `HumanVisual.play_ranged_attack_animation()`：拉弓 0.18s（手部后移 `4px`）、撒放 0.08s（前移 `2px`）、恢复 0.30s；攻击方向通过弓默认朝左的基准角换算，人物整体镜像仍由朝向控制。
- 动画与冷却独立：动画只表现拉弓/撒放，冷却在箭矢发射成功时立即开始，固定 3 秒。
- 长矛/近战武器路径不受影响；只有装备了远程 WEAPON 的单位进入远程动画与发射流程。

### 14.5 明确不做

- 弩、投石索、穿透、溅射/AOE、弹药数量、蓄力、爆头/暴击、风力、箭矢回收与完整音效。

## 15. 增援按初始侧部署与统一战斗入口（阶段 10）

### 15.1 初始侧锚点

- 每个战斗侧拥有初始区域锚点（side0 左、side1 右、side2 下、side3 上），由战场几何与创建顺序决定。
- 增援的“后方”方向 = 该侧锚点 − 战场中心；部署点位于己方初始区域之后，而不是当前友军质心之后。
- 两方战斗与三方/四方战斗使用同一规则，因此混战、伤亡或友军位置变化不会改变增援方向。

### 15.2 网格与备用扫描

- 保留 3 列网格、局部避让与 `REINFORCEMENT_MIN_SPACING`。
- 网格点被占满时，在己方半场按最小间距均匀扫描，选择离所有存活单位最远的合法点；绝不返回已占用的基准点。
- 生成点必须位于战场边界内、己方半场，且与存活单位保持最小间距；不会落入混战中心或敌方阵线。

### 15.3 既有单位不受影响

- 增援只加入既有 `BattleSession`，不新建战斗。
- 既有单位的控制器、位置、HP、攻击冷却、队形槽位与战斗侧索引保持不变。
- 逐单位生成后仍写入 `BattleParticipant`/`BattleUnitState`，并进入既有战斗结算。

### 15.4 统一加入入口与第三侧规则

- 玩家与 AI 的创建/加入都经 `BattleManager`；`get_join_side()` 检查全部战斗侧。
- 只有“恰好一个敌对侧 + 至少一个非敌对侧”才允许加入；与所有侧敌对或全中立时拒绝，不自动创建第三侧。
- 三方以上多方战斗仍通过显式多方入口创建，不由助攻或中途加入自动产生。

### 15.5 战斗摘要与确认

- 大地图战斗摘要只在悬浮对应 `BattleMarker` 时显示，按 `side_index` 分列部队与兵种；离开或结束即隐藏。
- 玩家主动攻击先经过二次确认；确认时重校验有效性、占用、关系与距离，取消零副作用，重复确认不产生第二场战斗。
- 加入友军既有战斗不弹攻击确认。

## 16. 战斗负伤判定（阶段 13）

### 16.1 配置

- `WoundedConfig`（`Data/Combat/wounded_config.tres`）是唯一概率来源：
  - `tier_wounded_chances[0..2]` 默认 `[0.5, 0.6, 0.8]`；
  - `enabled=false` 时所有 HP≤0 单位永久死亡；
  - `get_wounded_chance(tier)` 对越界 tier 取边界值，并 clamp 到 `[0,1]`。
- `BattleManager.set_wounded_config()` 注入并 `sanitize()`；`_wounded_rng` 使用固定初始种子，测试可通过 `set_wounded_rng_seed()` 复现。

### 16.2 判定时机与顺序

- `build_battle_result()` 在统计伤亡前调用 `_decide_wounded_outcomes(session)`。
- 只处理 `wounded_decided == false` 且 `alive == false` 或 `battle_hp <= 0` 的单位。
- 玩家角色（`is_player_character`）不掷骰：
  - 玩家所在侧明确战败时标记为伤兵，进入俘虏池并可被胜利方关押（见 [Captivity_System.md](Captivity_System.md)）；
  - 玩家获胜但角色 HP≤0、撤退/中止/平局或角色已经永久死亡时，遵循既有死亡规则。
- 其他单位有 Unit 且配置启用时按 `UnitConfig.tier` 取概率；否则永久死亡。
- 结果写回 `BattleUnitState.wounded`；预览与最终结算共享，不会二次随机。

### 16.3 写回与后续

- `_settle_session()`：
  - 伤兵调用 `UnitData.mark_wounded()`，HP=0，并防御性确保仍属于 `state.party_id`；
  - 永久死亡调用 `mark_dead()` 后移除成员并删除 Unit；
  - 存活写回 HP 并恢复 `ACTIVE`。
- `BattleResultData.wounded[party_id]` 与 `casualties`/`survivors` 分开统计。
- 伤兵不获得经验、不进入战利品、不生成可战斗控制器；只含伤兵的部队暂停大地图移动/AI。
- 离屏战斗仍按小时移除 0 HP 单位；最终结算时伤兵会补回原部队，再进入俘虏池（KI401）。

## 17. 俘虏分配与玩家接收（阶段 13）

### 17.1 俘虏池

- 仅在胜利成立（非中止/撤退/平局）时构建。
- 池 = 战败侧所有 `BattleUnitState.wounded == true` 的单位，按稳定顺序（side/party/unit ID）排序。
- 永久死亡单位不进入池；玩家侧战败时玩家角色会进入池，并被胜利方作为真实俘虏关押。

### 17.2 分配算法

```text
share_i = floor(P * N_i / N)
```

- `P` = 俘虏池大小；`N_i` = 第 i 个胜利方部队**实际参战单位数**（含中途加入与增援，每单位只计一次，不使用存活数）；`N` = 胜利方参战总数。
- 先取整，再按余数降序补足；余数相同按稳定 `party_id` 升序。
- 份额之和恒等于 `P`；单胜利方获得全部；`N=0` 时走显式回退并标记 `prisoner_allocation_degraded`。
- 个体按稳定顺序分配；不依赖 Dictionary 遍历顺序。

### 17.3 接收与确认

- 非玩家胜利方：`_claim_battle_prisoners()` 立即 `add_prisoner()`。
- 玩家胜利方：份额保存在 `_pending_prisoner_settlements[battle_id]`，通过 `has_pending_prisoner_selection()` / `get_pending_player_prisoners()` 查询。
- `commit_player_prisoners(battle_id, accepted)`：
  1. 归一化并去重接受列表；
  2. 校验每个单位在份额内、非成员、未被其他部队关押、非死亡；
  3. 全部通过后逐个 `add_prisoner()`，任一失败回滚；
  4. 未接收单位经 `_release_unclaimed_prisoner()` 清除归属并从 `UnitManager` 删除；
  5. 写入 `player_prisoners_committed = true` 并移除挂起记录；重复提交返回 false。
- `PrisonerSelectionPanel` 只维护预览：左侧为可分俘虏，右侧为玩家已有俘虏；支持转移、撤回与重置，确认只发出信号，由 `BattleScene` 调用管理器提交。
- 失败方、无俘虏或玩家无份额时不显示选择界面，直接返回大地图。
- 玩家角色被胜利方接收后，`CaptivityManager.sync_player_capture()` 进入被俘状态：原部队禁用但保留，镜头跟随押送部队，后续按俘虏恢复/逃脱规则处理。详见 [Captivity_System.md](Captivity_System.md)。
- 详细数据关系见 [Party_System.md](Party_System.md) 第 16 节与 [Wounded_Prisoner_System.md](Wounded_Prisoner_System.md)。
