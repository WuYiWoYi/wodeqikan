# 部队系统

**核心数据：** `Scripts/Entities/Party/party_data.gd`
**核心逻辑：** `Scripts/Core/World/party_manager.gd`
**状态：** 数据、统一控制类型/部队类型标识、成员管理（含转队与读档校验）、四方阵营初始部队、大地图移动/跟随、底部 NPC 遭遇对话、战斗锁定、AI 行为、部队管理面板（查看/上马/下马/晋升/普通士兵换装、士兵与俘虏双列列表、战斗经验文本等级）、金币与工资统计、士兵美术预览、采邑/冒险者/雇佣兵招募成员接入、雇佣兵装备锁定已实现

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
| `leader_noble_id` | String | 指挥该部队的贵族 `NobleData.lord_id`；用于政治关系、增援提示与百科 |
| `leader_lord_id` | String | 旧领主字段，保留用于兼容旧存档；读档时回退到 `leader_noble_id` |
| `world_position` | Vector2 | 大地图坐标（像素） |
| `target_position` | Vector2 | 移动目标 |
| `movement_speed` | float | 原始速度；大地图有效移速 = 原始 × 0.08 |
| `sight_range` | float | 视野半径 |
| `member_unit_ids` | Array[String] | 成员单位 ID |
| `prisoner_unit_ids` | Array[String] | 本部队关押的俘虏 Unit ID；与成员列表互斥，阶段 13 新增 |
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
- 俘虏归属独立于成员关系：`unit.prisoner_owner_party_id == party.party_id ⇔ party.prisoner_unit_ids.has(unit.unit_id)`。
- 任何单位不能同时出现在成员列表与俘虏列表；俘虏同一时间只能有一个关押部队。
- 部队解散时，关押俘虏的 `prisoner_owner_party_id` 清空；俘虏 Unit 保留，不自动转为成员。

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
| `validate_membership_consistency() -> Array[String]` | 双向归属校验（含俘虏冲突），空列表表示通过 |
| `get_prisoner_ids(party_id)` / `get_prisoner_units(party_id)` | 获取俘虏 ID / 数据 |
| `is_prisoner(unit_id)` / `get_prisoner_owner_party_id(unit_id)` | 查询俘虏归属 |
| `add_prisoner(party_id, unit_id) -> bool` | 加入俘虏；校验部队/单位存在、非任何部队成员、未被其他部队关押、非死亡、未出售 |
| `transfer_prisoner(unit_id, target_party_id) -> bool` | 俘虏转押，保持双向一致 |
| `remove_prisoner(party_id, unit_id) -> bool` | 从指定部队的俘虏列表移除并清空归属；Unit 保留 |
| `release_prisoner(unit_id) -> bool` | 按当前归属释放俘虏 |
| `sanitize_prisoner_ownership() -> Array[String]` | 读档后幂等清洗：成员身份优先、去重、清理悬空归属 |
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

大地图移速基准为 30（有效移速）；`PartyData.movement_speed` 保存原始速度，有效移速 = 原始速度 × 0.08（D170）。

| 部队 | 阵营 | 初始位置 | 原始速度 / 有效移速 | AI |
|---|---|---|---:|---|
| 玩家部队 | 玩家 | (760, 620) | 450 / 36 | 玩家控制 |
| 河畔商队 | 商队 | (900, 1500) | 200 / 16.0 | `TRADE_ROUTE` |
| 北境巡逻队 | 治安队 | (2350, 1100) | 300 / 24.0 | `GUARD` |
| 山道强盗 | 强盗 | (1650, 900) | 250 / 20.0 | `BANDIT` |

NPC 原始速度按最初配置统一 ×5/2 换算，保持原相对差异；玩家按需求单列为原始 450（有效 36），不参与 ×5/2 换算。
速度关系：玩家 > 治安队 > 家族骑士 > 强盗 > 商队。
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
  → 打开 PartyPanel（左侧成员列表 + 俘虏列表，条目带缩略图；右侧士兵/俘虏详情）
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
| 俘虏列表 | 当前选中部队的 `PartyData.prisoner_unit_ids`；不混入其他部队或全局俘虏池 |
| 列表缩略图 | 每名成员/俘虏的 `UnitVisual` 在固定 48×56 `SubViewport` 中渲染；无有效单位时绘制默认剪影 |
| 列表条目内容 | 头像缩略图、姓名、战斗经验文本等级、当前/最大生命值；不显示兵种、攻击、内部 ID 等额外文字 |
| 士兵战斗经验 | `CombatExperience.tier_name_for_level(UnitData.level)`；详情与列表共用同一映射 |
| 战斗属性 | `UnitData` 的最终属性缓存（不重新计算） |
| 装备 | `UnitData.equipment` + `EquipmentConfig` |
| 招募信息 | `UnitData.recruit_source` / `recruit_settlement_id` / `joined_at_game_time` |
| 美术预览 | 选中 `UnitData` 的 `faction_id` / `is_mounted` / `equipment`，由 `UnitVisual` 在独立 `SubViewport` 中生成 |

刷新规则：

- 打开面板时刷新一次；点击不同士兵时只更新详情区域。
- 默认选中第一名有效成员；选中项有明显高亮。
- 不提供招募、解雇、转队写操作；所有数据修改仍走管理器接口。
- 阶段 6 起提供有限写操作：
  - 坐骑：从背包马匹中选择并装备，或卸下返还背包（`UnitManager.equip_mount/unequip_mount`）；
  - 晋升：消耗晋升凭证提升兵种 tier（`UnitManager.promote_tier`）；
  - 装备：普通士兵可在“装备管理”中按槽位从玩家背包更换/卸下（`equip_item_from_holder` / `unequip_slot_to_holder`）。
- 士兵详情显示 tier、每日工资、金币与武器/装备槽位。
- 雇佣兵没有装备管理区与坐骑管理区，显示“雇佣兵装备与坐骑由契约固定，无法更换。”；数据层写入接口同样拒绝。
- 俘虏详情只读，隐藏装备、晋升与招募管理区。
- 士兵详情以“战斗经验：新兵”形式显示五个文本等级之一，不显示数值等级、`x / y` 经验进度、进度条或内部 ID；底层经验数据不变。
- 面板整体尺寸为 1280×660；横向优先扩大，为双列条目留出空间，不整体放大字体或其他控件。
- 士兵列表与俘虏列表均使用每行两个条目的 `GridContainer`，条目宽度自动均分；数量不足两个时最后一行允许只有一个条目。
- 每个列表条目只显示头像缩略图、姓名、战斗经验与当前/最大生命值；伤兵通过生命值 0 与颜色提示，不再追加额外状态文字。
- 空部队显示空状态；无效成员引用被跳过，不导致 UI 崩溃。
- 成员列表下方以分隔线与“俘虏列表”标题展示当前部队俘虏；无俘虏时显示空状态文本。成员与俘虏共用同一列表项组件、双列布局、缩略图规则与选中高亮，但俘虏详情只读。
- 缩略图复用 `UnitVisual`（人物/马匹/家族外观/装备），统一缩放、脚底锚点与裁切；不猜测不存在的头像资源路径，不修改源美术。

美术预览规则：

- 详情顶部使用独立 `SubViewport` 显示选中士兵，复用战斗 `UnitVisual`，不创建真实 `UnitData` / `BattleScene` 单位。
- 步兵显示人物影子与步行外观；骑兵显示骑马影子、四条马腿、马身/马鞍，并应用 15 像素上移与 3 像素右移。
- 不显示“美术预览”标题；预览区域尺寸与详情面板总高度不增加，通过提高缩放比例与调整脚底锚点放大图片，保持宽高比例。
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

### 8.1 战败部队清理

- 战斗结束并完成成员/俘虏结算后，`WorldContext._cleanup_defeated_parties()` 检查所有非玩家部队。
- **成员为空**的部队从 `PartyManager` 移除，并清理其他部队对它的 `current_target_id`、`attack_intent`、跟随目标、移动目标与 `focus_party_id`；它不再出现在大地图、遭遇、追击或 AI 目标中。
- 仍有成员的部队保留，包括“只剩伤兵”的部队；这类部队按既有治疗规则恢复，不因战败被删除。
- 玩家部队永远不参与此清理，作为玩家身份锚点保留；玩家角色被俘时由 `CaptivityManager` 禁用并负责后续逃脱/获释。
- 已在战败结算前完成的战斗记录、经验与俘虏分配不受清理影响；胜利方部队不删除。

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
| 移动速度 | 原始值：玩家 450 / 商队 200 / 治安队 300 / 强盗 250；有效移速 = 原始 × 0.08（固定值，公式待扩展） |
| 转队与重复成员防护 | 已实现（D024） |
| 重复部队 ID 防护 | 已实现（D024） |
| 读档成员关系校验 | 已实现（D025） |
| 非跨阵营成员规则 | 已实现；跨阵营流程未实现（KI119） |
| 大地图部队遭遇对话 | 已实现 |
| 战斗锁定 / 解锁 | 已实现 |
| 阵亡成员结算 | 已实现（移除归属并删除 UnitData；全员阵亡→DISABLED；结算后空部队从世界移除） |
| 玩家被俘/逃脱 | 已实现：玩家部队作为身份锚点保留，`CaptivityManager` 禁用/重建控制（见 [Captivity_System.md](Captivity_System.md)） |
| 初始测试兵力 | 玩家 5 民兵 + 6 职业步兵（4 名骑乘）+ 3 弓箭手 + 1 玩家角色（15 人）；其余三方各 3 民兵 + 2 职业步兵 |
| 玩家角色 Unit | 已实现：属于玩家部队、普通 UnitData、可参与战斗 |
| 骑乘成员 | 已实现：普通职业步兵装备马匹；成员关系不变，控制权转移列表显示“骑乘” |
| AI 行为字段与序列化 | 已实现（`ai_type` / `ai_route_index` / 路线 ID） |
| 商队往返 / 治安队巡逻 | 已实现（AIManager，D031） |
| 强盗游荡 / 动态目标评分 / 追击 | 已实现（FactionManager + VisionManager） |
| 治安队拦截 / 保护商队优先 | 已实现 |
| AI 攻击意图 | 已实现（`attack_intent`，不持久化） |
| 玩家部队跟随移动目标 | 已实现（`FOLLOW_PARTY` + 0.5 世界秒刷新） |
| NPC 撤退 / 士气 / 长期情报 | 未实现 |
| 部队管理 UI | 已实现查看（扩大面板、士兵/俘虏双列列表、条目仅头像/姓名/战斗经验/生命值、士兵详情、tier/工资、装备槽位、放大且无标题的 SubViewport 美术预览） |
| 坐骑 UI | 已实现：背包马匹下拉、装备/卸下，库存与装备双向一致 |
| 装备管理 UI | 已实现：普通士兵逐槽位从玩家背包更换/卸下；雇佣兵显示锁定提示并隐藏管理区 |
| 雇佣兵身份与限制 | 已实现：`UnitData.is_mercenary` 持久化，UI 与 `UnitManager` 双重拒绝换装 |
| 晋升 UI | 已实现：显示目标 tier、物品数量与消耗按钮 |
| 工资统计 | 已实现：单兵工资 + 部队每日总额；不自动扣除 |
| 编队 | TODO(阶段6) |
| 拆分/合并 | TODO(阶段7) |

新游戏会通过 `WorldInitializer.create_test_battle_forces()` 配置临时兵力：
- 玩家部队：5 民兵 + 6 职业步兵（其中 4 名装备马匹）+ 3 弓箭手（2 名 `archer_militia` + 1 名 `archer_trained`）+ 1 玩家角色（`player_hero`），共 15 人；弓箭手默认装备 `weapon_bow_01`；
- 商队、治安队、强盗：各 3 民兵 + 2 职业步兵，共 5 人。

人数与兵种分配集中在 `WorldInitializer` 的 `PLAYER_MILITIA_COUNT`、`PLAYER_TRAINED_COUNT`、`PLAYER_MOUNTED_TRAINED_COUNT`、`PLAYER_ARCHER_MILITIA_COUNT`、`PLAYER_ARCHER_TRAINED_COUNT`、`PLAYER_ARCHER_COUNT` 与 `PLAYER_TOTAL_MEMBER_COUNT`；不在多个脚本重复写人数。弓箭手与其他成员一样分配唯一 `unit_id`，写入 `member_unit_ids` 与 `current_party_id`；旧存档不会获得弓箭手（不补兵、不重复生成）。玩家部队在初始化时向 `PlayerProfile` 加入 5 匹测试马匹：4 匹由职业步兵装备，1 匹留在背包用于验收上马/下马（`TEST_MOUNT_STOCK = 骑乘人数 + 1`）。4 名骑乘单位仍是普通 `infantry_trained` 成员，只是 `equipment["MOUNT"]` 存在；不新增骑兵兵种、不改变部队成员关系。阶段 6 同时给予 2 个晋升凭证用于验证晋升流程。单位标记 `recruit_source = "milestone2_test"`，后续由招募系统替换（KI121）。玩家角色是普通 `UnitData`，使用 `is_player_character` 标记身份并属于玩家部队。旧存档若已有成员则不会补兵或重复生成；没有玩家角色时战斗场景退化到第一名存活友军作为控制对象。

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
| 玩家部队 | 玩家 | 15 | 玩家控制 |
| 河畔商队 | 商队 | 5 | 商队往返 |
| 北境巡逻队 | 治安队 | 5 | 守卫/巡逻 |
| 山道强盗 | 强盗 | 5 | 强盗游荡 |
| 巴里骑士 | 本地 | 10 | 专属巡逻 |
| 墨西西骑士 | 本地 | 10 | 专属巡逻 |
| 东路强盗 | 强盗 | 5 | 独立路线 |
| 荒野强盗 | 强盗 | 5 | 独立路线 |

家族骑士编制：1 领袖（三级）+ 1 骑乘侍从（三级）+ 3 骑乘军士（二级）+ 2 军士（二级）+ 3 步兵（一级）。规格表格明细合计为 8，正文与验收要求 10，按验收目标补足 1 名骑乘军士与 1 名步兵，见 D086。

家族骑士使用 `FACTION_LOCAL`，家族身份由 `family_id` 区分；玩家与本地势力保持中立，不新增外交关系。

## 13. 运行时交战冷却、读档清理与领袖校验（阶段 6 后续）

### 13.1 `engagement_cooldown_until`

- `PartyData` 运行时字段（float，默认 0），单位为 `TimeManager.world_elapsed_seconds`。
- 战斗结束后存活部队获得 30 秒冷却；不进入 `to_dict()`/`from_dict()`。
- 由 `BattleManager` 设置，`AIManager` 与 `EncounterManager` 读取。

### 13.2 `sanitize_loaded_runtime_state()`

读档后、成员关系校验前调用，清理不可能成立的状态：

- 清零 `attack_intent`、`focus_party_id`、`engagement_cooldown_until`；
- 无活动战斗会话时 `IN_BATTLE`/`RETURNING` 回落为 `AVAILABLE`（无成员则 `DISABLED`）；
- 清除 `BATTLE` 指令；失效追击目标与 `FOLLOW_PARTY` 指令清除并停止移动。

### 13.3 枚举与领袖校验

- `PartyData.from_dict()` 对 `current_order`、`movement_state`、`battle_state` 做范围校验，非法值回退默认。
- `PartyManager.validate_membership_consistency()` 额外要求：
  - `leader_unit_id` 非空时必须出现在本部队 `member_unit_ids`；
  - 领袖单位必须存在于 `UnitManager`。
- 校验失败仍保留现场并拒绝读档，不静默修正。

## 14. 征召成员接入（阶段 7 新增）

采邑、冒险者与雇佣兵招募不新增部队类型或成员表，仍统一经过现有成员关系：

```text
FiefRecruitmentManager / AdventurerRecruitmentManager / MercenaryManager
  → UnitManager.create_unit()
  → UnitAppearance.ensure_random() / 复制候选人外观
  → PartyManager.add_member(party_id, unit_id)
```

- 玩家部队成员由 `player_party_id` 决定；采邑进入领主 `party_id` 对应的部队（AI 领主同样）。
- 雇佣兵额外写入 `is_mercenary = true`，之后所有装备/坐骑变更都会被 `UnitManager` 拒绝；详见 [Mercenary_System.md](Mercenary_System.md)。
- 加入失败时招募管理器回滚已创建单位，保持 `UnitData` 与 `member_unit_ids` 双向一致。
- 招募单位写入 `recruit_source`、`recruit_settlement_id`、`origin_faction_id`、`joined_at_game_time`，不改变部队 `control_type`、`ai_type` 或路线。
- 部队人数上限目前不限制；工资仍只统计不扣除。
- 候选人本身不是部队成员，只有招募成功后才进入 `PartyManager`。

## 15. 贵族指挥与政治身份（阶段 8 新增）

- `PartyData.leader_noble_id` 指向指挥该部队的贵族；每个贵族最多指挥一支部队。
- 新增 `PartyData.leader_noble_id` 后，政治关系解析顺序：
  1. `leader_noble_id` → `NobleData.house_id` → 家族/王国关系；
  2. 无贵族时，`family_id` → `HouseManager.get_house_by_banner_id()` → 政治家族；
  3. 都没有时回退到 `faction_id`。
- `FactionManager.get_party_relation()` / `is_party_hostile()` / `is_party_friendly()` 统一使用上述顺序，因此同一个 `FACTION_LOCAL` 下的不同家族可以互相敌对或友好。
- 增援提示使用 `leader_noble_id` 查找 `NobleData.display_name` 与 `HouseData.house_name`，再通过 `FamilyConfig.banner_texture_path` 取旗帜。
- 部队悬浮与百科显示贵族名称、爵位与家族；部队本身不复制贵族状态。
- 旧存档缺少 `leader_noble_id` 时读取 `leader_lord_id`，再缺失时政治关系回退到 `family_id` / 阵营。

## 16. 俘虏列表与归属（阶段 13 新增）

- `PartyData.prisoner_unit_ids` 是部队关押俘虏的唯一权威列表；`UnitData.prisoner_owner_party_id` 是反向归属。
- 俘虏是独立 `UnitData`：唯一 ID、不可堆叠、保留等级/装备/属性；不是背包物品，也不进入 `member_unit_ids`。
- 加入/转移/移除只能通过 `PartyManager` 的俘虏 API，禁止 UI 或其他系统直接改数组。
- 俘虏不能战斗、移动、攻击、被治疗或领取工资；`remove_party()` 只清空归属，不删除 Unit。
- `sold_to_settlement_id` 非空的单位已离开玩家控制，`add_prisoner()` 拒绝再次关押；NPC 领主只能由 [Lord_Ransom_System.md](Lord_Ransom_System.md) 通过 `mark_ransomed()` 恢复后重回世界。
- 战斗结算由 `BattleManager` 调用 `add_prisoner()` 写入非玩家胜利方份额；玩家份额在确认后写入。
- 读档流程：
  1. 恢复 `UnitData` 与 `PartyData`；
  2. 调用 `sanitize_prisoner_ownership()`：
     - 若单位同时是成员，以成员身份为准并从俘虏列表移除；
     - 去重；
     - 清空不存在的部队/单位引用；
     - 重复调用结果不变。
- `validate_membership_consistency()` 额外报告：重复俘虏、成员/俘虏冲突、跨部队重复关押、缺失 Unit、归属字段与列表不一致。
- 容量上限、逃跑、忠诚、叛乱与俘虏招募明确未实现（KI530/KI531）。

### 16.1 部队面板俘虏列表（阶段 13 后续）

- 俘虏列表嵌入既有 `PartyPanel` 左栏，位于成员列表下方；不新建独立弹窗，也不改变部队选择入口。
- 列表只读取当前选中玩家部队的 `prisoner_unit_ids`，按数组顺序生成条目；点击与成员列表共用同一选中逻辑，详情区域同步切换。
- 选中俘虏时 `UnitDetailPanel` 标题显示“俘虏详情”，隐藏/禁用装备、晋升、招募等管理区域，并显示“仅可查看”提示；不提供招募、释放或出售操作。
- 列表随部队数据刷新重建；无俘虏时隐藏条目并显示空状态；面板关闭或部队缺失时清空条目引用。
