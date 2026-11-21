# 部队系统

**核心数据：** `Scripts/Entities/Party/party_data.gd`
**核心逻辑：** `Scripts/Core/World/party_manager.gd`
**状态：** 数据、统一控制类型/部队类型标识、成员管理（含转队与读档校验）、四方阵营初始部队、大地图移动/跟随、底部 NPC 遭遇对话、战斗锁定、AI 行为、部队管理面板（查看/上马/下马/晋升）、金币与工资统计、士兵美术预览已实现

---

## 1. 职责

- 部队是大地图的基本移动实体。
- 一个部队由多个 `UnitData` 组成。
- 维护成员关系、战斗状态、当前命令。
- 为 UI 与 AI 提供部队数据。

不负责：具体移动计算（`WorldMapManager`）、部队 AI（`AIManager`）、单位战斗行为（`UnitController`）。

## 2. PartyData

| 字段 | 类型 | 说明 |
|---|---|---|
| `party_id` | String | 唯一 ID，`PARTY_000001` |
| `party_name` | String | 显示名 |
| `faction_id` | String | 所属阵营 |
| `family_id` | String | 所属家族；可为空，只影响表现，不代表阵营关系 |
| `control_type` | enum | PLAYER / AI；决定由玩家输入还是 AIManager 下达指令 |
| `party_kind` | enum | GENERIC / PLAYER / FAMILY / MERCHANT / BANDIT / GUARD；只用于配置、表现与对话文本 |
| `banner_texture_path` | String | 部队旗帜贴图；为空时回退家族旗帜 |
| `leader_unit_id` | String | 部队领袖的 `UnitData.unit_id`；玩家部队、家族部队与普通 NPC 均可拥有 |
| `leader_lord_id` | String | 旧领主字段，保留用于兼容旧存档，不参与逻辑 |
| `world_position` | Vector2 | 大地图坐标（像素） |
| `target_position` | Vector2 | 移动目标 |
| `movement_speed` | float | 像素 / 游戏秒 |
| `sight_range` | float | 视野半径 |
| `member_unit_ids` | Array[String] | 成员单位 ID |
| `current_order` | enum | NONE / MOVE / HOLD / INTERACT / BATTLE / FOLLOW_PARTY |
| `current_target_id` | String | 跟随/追击目标部队 ID；战斗中也会被清空 |
| `movement_state` | enum | IDLE / MOVING |
| `battle_state` | enum | AVAILABLE / IN_BATTLE / RETURNING / DISABLED |
| `ai_type` | enum | NONE / TRADE_ROUTE / PATROL / BANDIT / GUARD |
| `ai_route_index` | int | 下一步要前往的路线点索引 |
| `ai_route_settlement_ids` | Array[String] | 商队路线 / 强盗游荡点的 stable `settlement_id` 列表 |
| `ai_patrol_points` | Array[Vector2] | 部队专属巡逻点；为空时使用 AIManager 全局路线 |
| `attack_intent` | bool | 运行时攻击/拦截意图，不进入存档；由 AIManager 维护 |
| `focus_party_id` | String | 玩家主动追逐/接近的目标部队；运行时，不进入存档 |

### 2.1 统一部队架构

玩家部队、家族部队、盗贼部队、商队与治安队共用同一个 `PartyData` / `PartyManager`：
ID、成员、位置、速度、阵营、家族、旗帜、状态、路线、控制类型与领袖字段全部一致。
类型差异只通过数据表达：

- `control_type = PLAYER`：玩家输入；AIManager 跳过该部队。
- `ai_type`：商队路线、巡逻、强盗追击、治安拦截等行为差异的唯一 AI 入口。
- `party_kind`：只供初始配置、表现与遭遇文本选择，不参与移动/战斗/结算分支。
- `family_id` 与 `faction_id` 相互独立，可同时存在。

禁止为某一类部队新增独立的数据结构、成员管理器、移动入口或地图标记节点。
`PartyData.apply_runtime_defaults()` 在读档后补齐旧存档缺失的控制类型与部队类型；
玩家控制权始终以 `WorldContext.player_party_id` 为准。

AI 字段规则：

- `ai_type` / `ai_route_settlement_ids` 由 `WorldInitializer` 初始化；`ai_route_index` 由 `AIManager` 在到达路线点后推进。
- 三者参与 `to_dict()` / `from_dict()`；旧存档缺失时默认为 `NONE` / `0` / 空数组。
- 巡逻点由 `AIManager.PATROL_POINTS` 提供，不写入每个 `PartyData`，只持久化巡逻进度。
- 不允许通过 `party_name` 判断 AI 行为。

## 3. 成员关系不变量

始终满足：

```text
unit.current_party_id == party.party_id
⇔
party.member_unit_ids.has(unit.unit_id)
```

维护规则：

- 加入/离开部队只能通过 `PartyManager.add_member()` / `remove_member()`。
- 不允许其他系统直接 append/erase `member_unit_ids`。
- 单位转队时 `unit_id` 不变，只改归属。
- 部队解散时，成员 `current_party_id` 清空，`UnitData` 保留。
- 一个单位最多属于一支部队：加入新部队前先从所有其他部队移除。
- 重复加入同一部队不产生重复成员。
- 本阶段要求单位与部队 `faction_id` 相等；跨阵营加入被拒绝。
- 转队在全部校验通过后一次性修改两个方向，避免只移除旧归属的半转移状态。
- 新增部队时不允许覆盖已存在的 `party_id`；读档遇到重复 ID 报错并跳过。
- 读档后由 `validate_membership_consistency()` 校验双向归属，见第 4.1 节。
- 战斗期间参战部队 `battle_state = IN_BATTLE`，并停止大地图移动；结算后解锁。
- 阵亡单位由 `BattleManager` 经 `PartyManager.remove_member()` 移除，再从 `UnitManager` 删除；存活单位保留成员关系。
- 部队全员阵亡后 `PartyData` 保留但成员为空，`battle_state = DISABLED`；空部队不再触发大地图交互，也不执行 AI。
- 大地图 AI 只处理非玩家、`AVAILABLE` 且未在移动的部队；行为类型来自 `ai_type`。

## 4. PartyManager API

| 方法 | 说明 |
|---|---|
| `setup(unit_manager, id_generator)` | 装配 |
| `create_party(faction_id, position, name, party_kind)` | 创建部队；类型默认 GENERIC |
| `add_party(party) -> String` | 加入仓储；重复 ID 拒绝并返回空字符串 |
| `get_party(party_id)` / `has_party(party_id)` | 查询 |
| `remove_party(party_id) -> bool` | 解散，清空成员与悬空归属，单位保留 |
| `add_member(party_id, unit_id) -> bool` | 加入或转队；校验存在性与阵营，失败不改数据 |
| `transfer_member(unit_id, target_party_id) -> bool` | 转队，内部复用 `add_member` |
| `remove_member(party_id, unit_id) -> bool` | 移除成员并清空归属；单位保留 |
| `get_member_ids(party_id)` / `get_units_of_party(party_id)` | 获取成员 ID / 数据 |
| `get_total_wage(party_id) -> int` | 汇总成员每日工资；只统计与展示，不自动扣除 |
| `validate_membership_consistency() -> Array[String]` | 双向归属校验，空列表表示通过 |
| `to_dict()` / `load_from_dict()` | 存档序列化；读档重复 ID 报错并跳过 |
| `apply_runtime_defaults(player_party_id)` | 读档后补齐控制类型/部队类型；不修改成员、位置或路线 |

### 4.1 读档成员关系校验

`WorldContext.load_from_save_data()` 在 `UnitManager` 与 `PartyManager` 都恢复完成后调用
`validate_membership_consistency()`，检查：

1. 每个成员 ID 都能找到对应 `UnitData`。
2. 每个非空 `current_party_id` 都能找到对应 `PartyData`。
3. 一个单位最多出现在一支部队的成员列表中（同一列表内也不得重复）。
4. `UnitData.current_party_id` 与 `PartyData.member_unit_ids` 双向一致。

失败处理：逐条 `push_error` 后返回 `false`，拒绝进入游戏；不自动修复或改写存档数据（D025）。

## 5. 移动速度

Milestone 1 使用简单固定值：

| 部队 | 阵营 | 初始位置 | 速度（像素/游戏秒） | AI |
|---|---|---|---:|---|
| 玩家部队 | 玩家 | (760, 620) | 150 | 玩家控制 |
| 河畔商队 | 商队 | (900, 1500) | 80 | `TRADE_ROUTE` |
| 北境巡逻队 | 治安队 | (2350, 1100) | 120 | `GUARD` |
| 山道强盗 | 强盗 | (1650, 900) | 100 | `BANDIT` |

速度关系：治安队（120）> 强盗（100）> 商队（80），玩家保持 150。
旧存档通过 `PartyData.movement_speed` 保留原速度；新常量只用于新游戏初始化。

战斗场景的 `UnitController.BATTLE_MOVE_SPEED_MULTIPLIER = 0.6` 只作用于士兵战斗移动，不修改 `PartyData.movement_speed`，因此大地图部队移动速度与本次战斗降速相互独立。

玩家点击有效部队（移动中或静止）会进入 `FOLLOW_PARTY`，每 0.5 世界秒读取目标最新位置；
目标进入战斗或消失时自动取消跟随。主动点击的追击不因目标离开视野而中断（D088）。

`attack_intent` 只在强盗/治安队明确追击某个敌对目标时置为 true；
普通巡逻、普通移动、玩家跟随都不会设置该字段。大地图遭遇判定使用
`attack_intent + current_target_id` 确认攻击意图是否指向对方。

后续考虑：

- 部队最慢成员。
- 骑兵比例。
- 负重。
- 地形。
- 道路。
- 坐骑。

公式在阶段 2 确定，并写入本文件。

## 6. 大地图部队 UI

### 6.1 遭遇对话（已实现）

```text
玩家进入 AI 部队 40 像素范围（必须是玩家主动点击/追击的目标）
  → 停止玩家部队移动
  → push_pause(ui_panel)
  → 打开底部 PartyDialoguePanel
      ├── 左侧：对方领袖头像/剪影（复用 UnitVisual）
      ├── 部队/领袖名称
      ├── 阵营
      ├── 兵力 = member_unit_ids.size()
      ├── 对话文本（EncounterTextConfig，按原因 × party_kind 取）
      └── [发起战斗] / [离开]
  → 离开：关闭面板、pop_pause，恢复此前基础倍率
  → 发起战斗：BattleManager.start_battle() → 切换 BattleScene
```

- 同一时间只存在一个对话面板；重复帧不会重复创建。
- 离开范围（64 像素）后才会再次触发，避免关闭后立即重开。
- 对方或玩家没有士兵时，“发起战斗”按钮禁用。
- 被击溃的空部队不再触发交互。
- 敌对阵营（如强盗）不打开普通对话；AI 主动追击玩家时使用独立的底部“遭遇对话”。
- 面板位于屏幕下方，左侧头像 + 右侧对白与动态选项；不再使用右侧信息面板布局。
- 玩家主动追逐/接近某支部队时，`focus_party_id` 非空：路过村庄和其他部队不会自动打开面板，避免打断追逐；到达目标或停止移动后清理，恢复原有交互。
- 普通对话与遭遇对话使用不同的暂停原因（`ui_panel` / `encounter_dialogue`），互不清理。
- 玩家接近离屏战斗时会先看到“加入/离开”面板，规则见 [World_Map_System.md](World_Map_System.md)。

### 6.2 部队管理面板（阶段 3 实现，阶段 6 扩展经济操作）

```text
点击大地图顶部“部队”按钮
  → 校验 WorldContext / 玩家部队 / 战斗状态
  → push_pause(ui_panel)
  → 打开 PartyPanel（左侧成员列表 + 右侧士兵详情）
  → 关闭：隐藏面板、pop_pause(ui_panel)，恢复此前基础倍率
```

入口规则：

- 按钮 `PartyButton` 始终显示在大地图顶部栏。
- 只打开玩家自己的部队，不提供 NPC 部队入口。
- 玩家部队不存在、世界无效或部队处于 `IN_BATTLE` 等不可用状态时拒绝打开。
- 保存面板、地点面板或部队遭遇对话打开时不重复打开。

数据来源（只读）：

| UI 区域 | 数据来源 |
|---|---|
| 部队名称 / 阵营 / 人数 / 移速 / 状态 | `PartyData` |
| 金币 / 每日工资总额 | `PlayerProfile.gold` / `PartyManager.get_total_wage()` |
| 移动状态与目标 | `PartyData.movement_state` / `target_position` / `current_target_id` |
| 成员列表 | `PartyData.member_unit_ids` 顺序，经 `UnitManager` 查询；跳过不存在与重复项 |
| 士兵身份 / 等级 / 经验 | `UnitData` + `UnitConfig` |
| 战斗属性 | `UnitData` 的最终属性缓存（不重新计算） |
| 装备 | `UnitData.equipment` + `EquipmentConfig` |
| 招募信息 | `UnitData.recruit_source` / `recruit_settlement_id` / `joined_at_game_time` |
| 美术预览 | 选中 `UnitData` 的 `faction_id` / `is_mounted` / `equipment`，由 `UnitVisual` 在独立 `SubViewport` 中生成 |

刷新规则：

- 打开面板时刷新一次；点击不同士兵时只更新详情区域。
- 默认选中第一名有效成员；选中项有明显高亮。
- 不提供招募、解雇、转队写操作；所有数据修改仍走管理器接口。
- 阶段 6 起提供两类有限写操作：
  - 坐骑：从背包马匹中选择并装备，或卸下返还背包（`UnitManager.equip_mount/unequip_mount`）；
  - 晋升：消耗晋升凭证提升兵种 tier（`UnitManager.promote_tier`）。
- 士兵详情显示 tier、每日工资、金币与武器/装备槽位；完整装备更换 UI 仍未实现（KI327）。
- 空部队显示空状态；无效成员引用被跳过，不导致 UI 崩溃。

美术预览规则：

- 详情顶部使用独立 `SubViewport` 显示选中士兵，复用战斗 `UnitVisual`，不创建真实 `UnitData` / `BattleScene` 单位。
- 步兵显示人物影子与步行外观；骑兵显示骑马影子、四条马腿、马身/马鞍，并应用 15 像素人物上移。
- 预览只读 `UnitData`，不参与 AI、碰撞、攻击、移动、装备或库存；不修改存档。
- 切换成员时复用同一预览节点并重建部件，旧部件释放；不会累积显示节点。

暂停规则：

- 使用 `TimeManager.push_pause(GameManager.PAUSE_REASON_UI_PANEL)`，不修改基础倍率。
- 关闭时只移除本面板压入的暂停原因，不清空其他原因。
- 禁止使用 `get_tree().paused`、`Engine.time_scale` 或 `clear_pauses()`。

## 7. 编队接口

编队是独立子系统：

- 定义阵型类型、成员、站位。
- 预留步兵方阵、步兵线阵、弓箭手线阵、骑兵阵型。
- `FormationManager.compute_slots()` 返回相对站位。
- 编队不负责攻击行为；单位 AI 负责执行。

详见 `Scripts/Systems/Formation/formation_manager.gd`。

## 8. 战斗状态

| 状态 | 含义 | 大地图行为 |
|---|---|---|
| `AVAILABLE` | 可用 | 可移动、可被选为目标 |
| `IN_BATTLE` | 战斗中 | 锁定，不移动 |
| `RETURNING` | 战后返回 | 暂不接新命令 |
| `DISABLED` | 失效 | 不参与世界模拟，AI 停止；全员阵亡结算后进入该状态 |

状态由 `BattleManager` 写入，其他系统只读。

## 9. 扩展方向

- 部队拆分/合并。
- 军团组织与部队支援关系。
- 部队士气、补给、负重。
- 玩家多部队管理。
- 部队命名与编制模板。

## 10. 实现状态

| 项 | 状态 |
|---|---|
| `PartyData` 与序列化 | 已实现 |
| 成员增删与双向一致 | 已实现 |
| 创建部队 | 已实现 |
| 初始玩家/NPC 部队 | 已实现 |
| 大地图直线移动 | 已实现 |
| 移动速度 | 玩家 150 / 商队 80 / 治安队 120 / 强盗 100（固定值，公式待扩展） |
| 转队与重复成员防护 | 已实现（D024） |
| 重复部队 ID 防护 | 已实现（D024） |
| 读档成员关系校验 | 已实现（D025） |
| 非跨阵营成员规则 | 已实现；跨阵营流程未实现（KI119） |
| 大地图部队遭遇对话 | 已实现 |
| 战斗锁定 / 解锁 | 已实现 |
| 阵亡成员结算 | 已实现（移除归属并删除 UnitData；全员阵亡→DISABLED） |
| 初始测试兵力 | 玩家 5 民兵 + 6 职业步兵（4 名骑乘）+ 1 玩家角色（12 人）；其余三方各 3 民兵 + 2 职业步兵 |
| 玩家角色 Unit | 已实现：属于玩家部队、普通 UnitData、可参与战斗 |
| 骑乘成员 | 已实现：普通职业步兵装备马匹；成员关系不变，控制权转移列表显示“骑乘” |
| AI 行为字段与序列化 | 已实现（`ai_type` / `ai_route_index` / 路线 ID） |
| 商队往返 / 治安队巡逻 | 已实现（AIManager，D031） |
| 强盗游荡 / 动态目标评分 / 追击 | 已实现（FactionManager + VisionManager） |
| 治安队拦截 / 保护商队优先 | 已实现 |
| AI 攻击意图 | 已实现（`attack_intent`，不持久化） |
| 玩家部队跟随移动目标 | 已实现（`FOLLOW_PARTY` + 0.5 世界秒刷新） |
| NPC 撤退 / 士气 / 长期情报 | 未实现 |
| 部队管理 UI | 已实现查看（概览、金币/工资、成员列表、士兵详情、tier/工资、装备槽位、SubViewport 美术预览） |
| 坐骑 UI | 已实现：背包马匹下拉、装备/卸下，库存与装备双向一致 |
| 晋升 UI | 已实现：显示目标 tier、物品数量与消耗按钮 |
| 工资统计 | 已实现：单兵工资 + 部队每日总额；不自动扣除 |
| 编队 | TODO(阶段6) |
| 拆分/合并 | TODO(阶段7) |

新游戏会通过 `WorldInitializer.create_test_battle_forces()` 配置临时兵力：
- 玩家部队：5 民兵 + 6 职业步兵（其中 4 名装备马匹）+ 1 玩家角色（`player_hero`），共 12 人；
- 商队、治安队、强盗：各 3 民兵 + 2 职业步兵，共 5 人。

人数与兵种分配集中在 `WorldInitializer` 的 `PLAYER_MILITIA_COUNT`、`PLAYER_TRAINED_COUNT`、`PLAYER_MOUNTED_TRAINED_COUNT` 与 `PLAYER_TOTAL_MEMBER_COUNT`；不在多个脚本重复写人数。玩家部队在初始化时向 `PlayerProfile` 加入 5 匹测试马匹：4 匹由职业步兵装备，1 匹留在背包用于验收上马/下马（`TEST_MOUNT_STOCK = 骑乘人数 + 1`）。4 名骑乘单位仍是普通 `infantry_trained` 成员，只是 `equipment["MOUNT"]` 存在；不新增骑兵兵种、不改变部队成员关系。阶段 6 同时给予 2 个晋升凭证用于验证晋升流程。单位标记 `recruit_source = "milestone2_test"`，后续由招募系统替换（KI121）。玩家角色是普通 `UnitData`，使用 `is_player_character` 标记身份并属于玩家部队。旧存档若已有成员则不会补兵或重复生成；没有玩家角色时战斗场景退化到第一名存活友军作为控制对象。

阵营关系由 `FactionManager` 统一维护（玩家-商队中立、玩家-强盗敌对、玩家-治安队中立、商队-治安队友好、商队-强盗敌对、强盗-治安队敌对）；部队实例只保存 `faction_id`，不保存关系表。

## 11. 待确认

- 玩家部队上限与部队规模上限。
- 跨阵营招募、俘虏、叛变与雇佣兵的归属变更流程（KI119）。
- 军团系统是否在阶段 7 前提供最小接口。
- 移动速度公式与负重/骑兵比例的关系。
- 战败后玩家部队全灭的处理（逃跑 / 被俘 / 重新开局）；当前会变为 DISABLED。
- 击败的敌方部队当前保留为 DISABLED 空部队，是否解散或移除待定（KI126）。
- 商队路线与巡逻点是否迁移到 `.tres` 配置资源（KI128）。

## 12. 领袖、家族与专属巡逻（阶段 6 新增）

### 12.1 新增持久化字段

| 字段 | 类型 | 说明 |
|---|---|---|
| `family_id` | `String` | 所属家族；只影响表现，不影响阵营关系 |
| `leader_unit_id` | `String` | 当前领袖的 `UnitData.unit_id` |
| `ai_patrol_points` | `Array[Vector2]` | 部队专属巡逻点；为空时使用 `AIManager.PATROL_POINTS` |

`PartyManager` 新增：

- `get_leader_unit(party_id)`：领袖必须是当前成员，否则返回 `null`；
- `is_party_leader(unit_id)`；
- `remove_member()` 移除领袖时同步清空 `leader_unit_id`，避免悬空引用。

### 12.2 四种身份分离

- 玩家身份：`UnitData.is_player_character`，持久化。
- 当前控制：`UnitActor.is_controlled` / `BattleScene` 运行时状态，不进入存档。
- 部队领袖：`PartyData.leader_unit_id`，玩家与 NPC 家族骑士共用。
- 部队归属：`UnitData.current_party_id` 与 `PartyData.member_unit_ids` 双向一致，仍由 `PartyManager` 单写。

玩家部队的领袖指向 `player_hero`；NPC 家族骑士的领袖指向各自家族骑士单位。`AIManager` 通过现有部队 AI 控制 NPC 家族骑士，不需要额外的 `LeaderManager`。

### 12.3 新游戏初始部队

| 部队 | 阵营 | 人数 | AI |
|---|---|---|---|
| 玩家部队 | 玩家 | 12 | 玩家控制 |
| 河畔商队 | 商队 | 5 | 商队往返 |
| 北境巡逻队 | 治安队 | 5 | 守卫/巡逻 |
| 山道强盗 | 强盗 | 5 | 强盗游荡 |
| 巴里骑士 | 本地 | 10 | 专属巡逻 |
| 墨西西骑士 | 本地 | 10 | 专属巡逻 |
| 东路强盗 | 强盗 | 5 | 独立路线 |
| 荒野强盗 | 强盗 | 5 | 独立路线 |

家族骑士编制：1 领袖（三级）+ 1 骑乘侍从（三级）+ 3 骑乘军士（二级）+ 2 军士（二级）+ 3 步兵（一级）。规格表格明细合计为 8，正文与验收要求 10，按验收目标补足 1 名骑乘军士与 1 名步兵，见 D086。

家族骑士使用 `FACTION_LOCAL`，家族身份由 `family_id` 区分；玩家与本地势力保持中立，不新增外交关系。
