# AI 系统

**核心调度：** `Scripts/Systems/AI/ai_manager.gd`
**状态：** 商队/巡逻、强盗动态目标评分、治安队拦截、统一大地图遭遇、遭遇原因与选项规则、底部 NPC 遭遇对话、离屏多方战斗、领主前往自有封地征召已实现；复杂领主战略与战术未实现

---

## 1. 分层

| 层级 | 决策者 | 频率 | 输出 |
|---|---|---|---|
| 单位实时行为 | `UnitAI` | 小场景物理帧 | 移动、攻击、防御、撤退 |
| 部队战术 | `PartyAI` | 1 世界秒 | 移动、攻击、防守、撤退命令 |
| 领主战略 | `LordAI` | 30 世界秒 | 招募、参战、撤退、驻防 |

原则：

- 高层下达命令，低层负责执行。
- AI 不直接操作场景节点与 UI。
- AI 只通过管理器接口修改数据。
- 不同层级使用不同更新频率，禁止每帧全量扫描。
- 部队层只调度 `control_type == AI` 的部队；玩家部队不因为没有 NPC AI 而脱离 Party 系统。
- 部队差异来自 `ai_type`（行为策略）与 `party_kind`（配置/表现），不按部队类型复制移动、成员或战斗流程。

## 2. 单位 AI

初期 FSM：

```text
Idle
├── Move
├── Attack
├── Defend
└── Retreat
```

后续扩展：Shield、Pursue、Protect、FormationMove、Charge。

### 目标选择

- 只在攻击范围/感知范围内选择敌人。
- 多目标时随机或按威胁值选择（阶段 3 先随机）。
- 大地图敌对关系来自 `FactionManager`；战斗场景按 `BattleSession` 的战斗侧划分敌我。
- 玩家单位与 AI 单位共用 `UnitController`，AI 只替换决策输入。

### 2.1 战斗控制模式与队形

- `UnitController` 有两种模式：
  - AI：搜索目标 → 接近 → 攻击 → 目标失效后重新搜索；
  - 玩家控制：WASD 移动 + 左键攻击，不执行 AI。
- AI 状态对外暴露为 `AIState.SEEK / APPROACH / ATTACK`：
  - `SEEK`：没有有效目标；有队形槽位时向槽位移动；
  - `APPROACH`：目标在攻击矩形外，沿“目标外围 + 自身槽位方向”的进攻点接近；
  - `ATTACK`：目标在有效攻击矩形内；冷却结束立即攻击，冷却中保持位置。
- “重新选择目标”是一次状态转换动作：目标死亡/失效时在同一 tick 重新执行搜索；没有新目标则进入 `SEEK`。不额外维护第四种持续状态。
- **360°定向矩形判定与玩家共用 `CombatRules`**：AI 方向取攻击者→目标；目标必须在矩形前向长度/横向宽度内。AI 不会在区域外执行攻击；目标离开区域后自动回到 `APPROACH`。
- 每次攻击最多命中一个目标；AI 的当前目标作为唯一候选，其他目标不受伤害。
- 攻击动画方向与伤害方向一致；攻击开始后锁定方向/目标，动画期间不因目标移动而突然转向。
- 战斗移动速度使用与玩家相同的 `× 0.6` 系数；实体碰撞最小间距 28 与局部避让协同，AI 被挤开后继续向队形/攻击位置移动。
- AI 在区域外不会停在自己的队形槽位上无限空刀：进攻点位于目标外围，而不是只依赖两军质心中点。
- 同一时间只有 `BattleScene._controlled_unit_id` 对应一个玩家控制单位；其余友军继续 AI。
- 玩家角色被击败后，控制权可转移给其他存活友军或进入观战；观战时所有单位由 AI 控制。
- 队形槽位仍由 `BattleScene` 周期性分配：
  - 队形由 `FormationManager` 计算（LINE / DEPTH / LOOSE）；
  - 同侧多支部队使用 party lane 分区；
  - 存在骑乘单位时队形间距加宽；
  - 单位层只做局部分离与向进攻点/槽位移动。
- 邻居查询由 `BattleScene` 每 0.3 秒构建局部缓存，避免每个单位每帧遍历全场。
- 部队移动目标可通过 `BattleScene.set_party_move_order()` 覆盖，为后续键盘指挥预留。
- 当前 AI 没有寻路、地形阻挡、显式攻击槽位分配、复杂包围与士气。

### 2.2 远程单位 AI（阶段 6 后续）

`UnitController.tick()` 对 `UnitData.is_ranged_attacker()` 为真的单位进入 `_tick_ranged`，其余保持近战流程：

- **射程**：使用 `UnitData.attack_range`，弓配置为 360；射程独立于近战攻击矩形，判定为双方地面中心距离 ≤ 射程。
- **射程内**：站定并面向目标，冷却结束立即发射；冷却中保持位置，不冲入近战。
- **射程外**：向目标外围的站定点移动，站定距离 = 射程 × `RANGED_STANDOFF_FACTOR(0.82)`，避免贴脸。
- **敌方过近**：距离 < `RANGED_MIN_RANGE = 110` 时后撤，同时保持面向目标，避免被近战单位贴身。
- **换目标**：目标死亡/失效时在同一 tick 重新索敌；新的有效目标必须在射程内才会立即开火。
- **发射**：与玩家共用 `_fire_ranged_at`，冻结目标当前地面坐标后生成箭矢；发射后进入 `attack_interval`（弓为 3 秒）冷却。
- **队形**：`BattleScene` 分配槽位时把远程单位排在队形后列，AI 因此更倾向在己方后排活动。
- 当前没有提前量计算、弹道预判、齐射/集火指令、弹药管理或“无箭线时停火”策略。

## 3. 部队 AI

### 3.1 当前实现（大地图固定路线）

`AIManager._tick_party_tactical()` 每 1 世界秒执行一次，遍历部队：

- 跳过玩家控制部队（`control_type == PLAYER`，旧数据回退 `player_party_id`）。
- 跳过 `battle_state != AVAILABLE` 的部队（战斗中 / 返回中 / 失效）。
- `TRADE_ROUTE` / `PATROL` 在移动中跳过，避免重复写入相同目标；
  `BANDIT` / `GUARD` 在移动中仍会更新追击目标或响应附近战斗。
- 按 `PartyData.ai_type` 分派，不通过部队名称判断行为。

| 类型 | 行为 |
|---|---|
| `NONE` | 不自动移动 |
| `TRADE_ROUTE` | 按 `ai_route_settlement_ids` 中的地点 ID 往返 |
| `PATROL` | 按 `AIManager.PATROL_POINTS` 的固定四点多点循环 |
| `BANDIT` | 视野内选择敌对目标追击；无目标时沿路线游荡 |
| `GUARD` | 优先拦截威胁友军的强盗，其次追击视野内强盗；无目标时巡逻 |

`ai_route_index` 表示“下一步要前往的路线点索引”。到达当前路线点后，在下一次 1 秒决策推进到下一个点并下达新目标；最后一站回到索引 0。

### 3.1.1 阵营与视野公共系统

- `FactionManager` 是唯一关系查询入口：
  - 默认阵营：玩家 / 商队 / 强盗 / 治安队 / 本地势力。
  - 阶段 8 起，部队关系优先按政治身份解析：`leader_noble_id` → 家族 → 王国；无家族时回退阵营。
  - 关系：友好、中立、敌对；同阵营且无政治冲突时友好；未知组合默认中立。
  - `is_party_hostile()` / `is_party_friendly()` / `is_party_neutral()` 供 AI、视野与遭遇统一使用；`is_hostile()` 保留阵营级查询。
  - 玩家家族默认中立；王国开战会传播到双方成员家族。
- `VisionManager` 是唯一视野查询入口：
  - 距离 `<= observer.sight_range` 即可见；
  - 观察者必须 `AVAILABLE` 且有存活士兵；
  - 目标必须可用、有存活士兵；空部队和 `IN_BATTLE` 部队不可被选为目标；
  - 提供可见全部/敌对/友方/中立列表与最近敌对目标。
- AI 不维护独立的敌人识别逻辑，也不直接遍历、硬编码阵营 ID。
- 视野是即时查询；目标离开视野后，AI 在下一次决策清除 `current_target_id`。

### 3.2 商队往返

- 路线由 `WorldInitializer` 在新建世界时写入 `oak_village.settlement_id` 与 `riverside_village.settlement_id`。
- 新游戏时商队初始化在 `(900,1500)`，`ai_route_index = 0`；首次决策前往巴里 `(2600,2100)`，之后在巴里与墨西西 `(2500,700)` 之间持续往返（阶段 9 布局坐标）。
- `AIManager` 通过 `SettlementManager.get_settlement(id)` 读取真实地点坐标，不使用数组下标或硬编码坐标。
- 两个地点之间持续循环，无额外等待。
- 路线地点缺失时停止该部队的移动并输出警告。

### 3.3 巡逻循环

- 巡逻点为 `AIManager.PATROL_POINTS`：
  `(2200,500) → (2600,900) → (2400,1500) → (1900,1200) → (2200,500)`。
- 到达目标后按顺序前进，不随机改变目标。
- 目标仍由 `WorldMapManager.set_party_target()` 进行地图边界限制。

### 3.4 职责边界

- `AIManager` 只选择目标、决定是否接近战斗、维护 `PartyData.attack_intent` 并调用 `WorldMapManager.set_party_target()`。
- `WorldMapManager` 负责移动、到达判定、边界与位置写入。
- `EncounterManager` 负责统一遭遇判定、玩家中途参战交互、战斗创建/加入委托与状态清理。
- `BattleManager` 负责战斗创建、加入与重复参战保护。
- AI 不直接修改 `PartyData.world_position`，不创建/操作地图图标。
- 移动与 AI 决策都使用 `WorldSimulation` 的固定 tick；顺序为移动 → 遭遇判定 → AI。
- 全员阵亡的部队在战斗结算后变为 `DISABLED`，AI 不再处理。

### 3.4.1 统一大地图遭遇判定

`EncounterManager.update_encounters()` 是唯一的大地图遭遇入口：

```text
双方有效、非 DISABLED、成员非空
且阵营敌对
且距离 <= AI_ENCOUNTER_RADIUS (50)
且满足任一意图条件：
    A. 至少一方的攻击意图明确指向对方：
       attack_intent == true 且 current_target_id == 对方 party_id
    B. 玩家主动追击该敌对部队：
       player.focus_party_id == 对方 party_id
```

- `attack_intent` 是运行时字段，不进入存档。
- 普通巡逻 / 普通移动 / 玩家跟随不会设置 AI 攻击意图；但玩家主动点击敌对部队后，`focus_party_id` 作为玩家侧的显式交互意图参与同一遭遇判定。
- 玩家追击同向移动目标时，只要双方进入 50 世界单位即触发一次接触；接触后双方立即停止，不要求目标先停下，也不继续互相推挤。
- 中立部队或与玩家无关的敌对部队仅靠近不会触发自动遭遇；自动打断必须满足“追击者的 `attack_intent` 指向玩家，并且实际追上”或“玩家主动点击并追击该目标”。
- 玩家追击 A 时路过无关敌对 B 不会被打断；B 只有在自己的攻击目标明确为玩家时才会拦截。
- 同一追击关系只触发一次；接触后清除攻击意图、移动目标与焦点。
- 强盗追击、治安队拦截会设置攻击意图。
- 满足条件后（世界可同时存在多场战斗，只检查这对部队自身所属战斗）：
  - 双方都未参战 → `BattleManager.start_battle(..., offscreen = true)` 创建新的独立战斗；
  - 一方已在离屏战斗、另一方空闲 → `try_join_battle(空闲方, 该方 battle_id)`；
  - 双方已分别处于不同战斗 → 跳过本次遭遇，不合并会话，也不让任何一方同时参战；
  - 玩家被敌对 AI 主动拦截 → 停止双方、清除意图、记录待处理遭遇并请求 WorldMap 弹出遭遇对话；
  - 双方已在同一战斗 → 不重复创建或加入。
- 遭遇距离 50 统一用于 AI 对 AI 与玩家被拦截；不在 AI 代码中各自维护。
- 玩家主动接近非敌对 AI 不会触发遭遇对话；玩家主动追击敌对 AI 时，使用同一底部遭遇界面（`PLAYER_INITIATED`，保留战斗 / 离开）。
- 离开后记录拒绝锁，离开 90 世界单位前不会重复触发同一场遭遇；世界恢复基础倍率，双方保留停止位置，AI 下一次决策可继续行动。
- 只有 `ENEMY_PURSUIT`（敌对 AI 主动追击并成功拦截）禁止离开；普通敌对遭遇与玩家主动接触沿用原规则。

### 3.4.2 玩家主动追逐时的自动交互抑制

- `PartyData.focus_party_id` 标记玩家主动追逐/接近的目标部队（运行时，不存档）。
- 焦点非空时：
  - WorldMap 跳过村庄地点自动面板；
  - 跳过无关部队的普通对话；
  - `EncounterManager.update_player_battle_interaction()` 跳过“接近离屏战斗”的加入/离开面板，避免打断追逐；
- **不抑制** `update_encounters()`：敌对 AI 主动追击玩家且攻击意图指向玩家时，仍按原规则触发遭遇，可以打断玩家行动。
- 普通寻路或追击其他目标时，路过的中立/无关部队不会打开普通对话；只有 `focus_party_id` 指向的部队才会打开主动对话。
- 焦点在主动点击目标附近保留到对话打开；目标失效、进入战斗或远离交互范围后清除。
- AI 的目标选择与攻击意图逻辑本身不因玩家追逐而改变。

### 3.5 强盗 AI

```text
每 1 世界秒：
  1. 附近有可加入的离屏战斗 → 先接近/加入
  2. 重新评估目标评分（当前目标有效时也重新计算）
  3. 若新目标评分 >= 当前目标评分 + 30 → 切换；否则保留当前目标
  4. 追击目标：更新位置、设置 attack_intent
  5. 没有目标 → 沿 ai_route_settlement_ids 路线游荡
```

目标评分：

```text
最终评分 = 基础优先级分 - 距离 × 0.1
商队 300 / 治安队 200 / 玩家 100 / 其他敌对 50
切换阈值 30（新目标必须明显更优）
```

- 所有目标必须可见、有效、阵营敌对；评分与阈值是 `AIManager` 常量。
- 目标离开视野、被删除、进入战斗或变为空部队时立即清除，再重新选择。
- 追击只更新目标点，真正遭遇由 `EncounterManager.update_encounters()` 统一处理。
- 强盗不会攻击中立或友方部队；敌对关系完全来自 `FactionManager`。
- 进入战斗后 `battle_state = IN_BATTLE`，AI 与世界移动均跳过。

### 3.6 治安队 AI

```text
每 1 世界秒：
  1. 附近有可加入的离屏战斗 → 先接近/加入
  2. 查找可见敌对部队中“正在追击友军（商队）”的强盗 → 优先拦截
  3. 否则沿用现有追击目标，或选择最近的可见敌对部队
  4. 设置 attack_intent，交由 EncounterManager 统一遭遇判定
  5. 没有目标 → 恢复 PATROL_POINTS 巡逻
```

- 治安队与商队友好，与强盗敌对；不会攻击商队或其他友军。
- 威胁判定读取强盗的 `current_target_id`，若目标是治安队的友军阵营则优先。
- 目标消失或失去视野后放弃追击并恢复原巡逻路线。
- 战斗结束后部队解锁；若仍有存活成员则恢复 `AVAILABLE`，下一次决策重新扫描威胁。

### 3.7 离屏战斗与第三方响应

- NPC 对 NPC 战斗使用 `offscreen = true`：不暂停世界，每 1 个游戏小时（6 世界秒）结算一次伤亡，直到一方全灭、平局或达到 48 小时安全上限。
- 战斗期间参战部队锁定，其他 AI 仍正常决策。
- 世界可同时存在多场 AI 离屏战斗，互不阻塞；一场战斗不会阻止其他位置发生新战斗。
- 强盗/治安队会遍历全部有效离屏战斗，在 `BATTLE_APPROACH_RADIUS = 700` 内选择可加入且距离最近的一场接近；
  实际加入由 `EncounterManager.update_encounters()` 统一判定与执行，AI 不调用 `try_join_battle()`。
- 已处于战斗中的部队不参与响应，也不会覆盖或合并其他战斗会话。
- 是否可加入、加入哪一侧由 `BattleManager.get_join_side(party_id, battle_id)` 基于 `FactionManager` 决定：
  - 与某侧无敌对、与另一侧有敌对 → 加入该侧；
  - 与所有现有侧敌对 → 建立独立第三方；
  - 与任何一方都无敌对 → 不加入。
- 玩家接近可加入的离屏战斗时，EncounterManager 生成交互请求，WorldMap 弹出“加入/离开”面板；加入后才切换战斗场景。

### 3.8 玩家被主动拦截

当具有攻击玩家意图的敌对 AI 与玩家距离 <= 50 时：

1. `WorldMapManager` 停止双方、清除追逐与攻击意图。
2. 记录唯一 `encounter_id` 与双方 party_id，若已有待处理遭遇则不再触发。
3. 广播 `EventBus.player_encounter_requested`。
4. WorldMap 压入 `encounter_dialogue` 暂停原因，在屏幕下方显示 NPC 对话式遭遇 UI：
   - 领袖头像/默认剪影、领袖名称、阵营、兵力与配置对白；
   - 记录 `EncounterReason = ENEMY_PURSUIT`；
   - 只提供“战斗”，不显示离开/撤退选项。
5. 玩家选择战斗：
   - `BattleManager.start_battle([玩家], [敌对部队], 位置, offscreen = false)`；
   - 移除 `encounter_dialogue`，保留 `battle` 暂停；
   - 切换 `BattleScene`。
6. 敌对追击遭遇不允许直接离开：`WorldMap` 隐藏并禁用离开按钮，`EncounterManager.decline_player_encounter()` 同样拒绝清理；玩家只能进入战斗。
7. 对话异常关闭时，WorldMap 清理自身暂停原因与待处理遭遇，不触碰其他暂停原因。

玩家接近一场正在进行的离屏 NPC 战斗时，由 `EncounterManager.update_player_battle_interaction()` 生成“加入/离开”交互请求；具体 UI 与暂停由 WorldMap 处理。

- 玩家主动接近敌对 AI、或敌对 AI 正在追击其他目标时，不会弹出该对话。
- 其他敌对势力复用同一流程，仅描述文本按阵营区分。
- 遭遇期间 WorldSimulation 跳过 AI，避免重复创建战斗。

### 3.9 仍未实现

- 威胁值、撤退、士气、外交与长期情报记忆。
- 寻路、地形避障、道路加成。
- 领主战略 AI 与招募/驻军决策。
- 离屏战斗的伤兵、士气与更复杂战术；当前为阵亡 + 随机波动。

## 4. 领主 AI

- 通过 `LordData.current_goal` / `current_state` 表达长期目标。
- 决策读部队与地点数据，产出命令。
- 决策节奏远低于部队 AI，避免大量领主同时计算。

### 4.1 领主征召决策（阶段 7 实现）

`AIManager._tick_lord_strategic()` 对每个非玩家、存活的领主：

1. 取领主 `party_id` 对应的部队；无效或不可用则跳过。
2. 部队人数低于 `SettlementEconomyConfig.ai_lord_recruit_threshold`（默认 12）时，查找最近的、`owner_lord_id` 为自己的、采邑储备 > 0 的村庄。
3. 设置 `LordData.current_state = "RECRUITING"` 与 `current_target_settlement_id`，让部队移动到该村。
4. 抵达后调用 `FiefRecruitmentManager.recruit_group()`；无论成功失败都清除征召状态和目标。
5. `RECRUITING` 期间 `_tick_party_tactical()` 跳过该部队，避免巡逻/追击覆盖征召目标。

- 征召使用与玩家完全相同的管理器接口和资源扣除。
- 成功事实通过 `EventBus.fief_recruited` 进入世界日志；AIManager 不直接写日志。
- 找不到自有封地、储备为 0 或部队不可用时不做任何修改，下一次分频重新判断。

详见 [Lord_System.md](Lord_System.md) 与 [Fief_Recruitment_System.md](Fief_Recruitment_System.md)。

## 5. 调度与性能

`AIManager` 使用时间累加器分频：

```text
每世界 tick:
    party_timer += 0.1
    lord_timer  += 0.1

    party_timer >= 1.0  → 部队战术决策，取模
    lord_timer  >= 30.0 → 领主战略决策，取模
```

- 卡顿后不补跑错过的时间桶，避免集中决策。
- 初期可接受 O(n²) 距离检查；部队数量上升后引入空间网格。
- 视野、遭遇与 AI 共享空间查询结果。
- AI 决策不得在 `_process` 中执行全量扫描。

## 6. 数据驱动参数

AI 参数应可配置：

- 决策间隔。
- 视野与感知范围。
- 攻击/撤退兵力比。
- 招募阈值。
- 性格权重。

初期可以放在常量或配置资源中，但不得散落在多个脚本。

## 7. 随机性

- 使用统一随机源，避免不可复现。
- 后续将随机种子写入存档，保证读档后行为可复现。
- 测试中固定种子。

## 8. 实现状态

| 项 | 状态 |
|---|---|
| `AIManager` 分频调度 | 已实现 |
| 商队固定路线往返 | 已实现 |
| 治安队巡逻循环 | 已实现 |
| 玩家/战斗/失效部队跳过 | 已实现 |
| `FactionManager` 关系查询 | 已实现 |
| `VisionManager` 视野发现 | 已实现 |
| 强盗游荡 / 动态目标评分 / 追击 | 已实现（300/200/100，切换阈值 30） |
| 治安队拦截 / 保护商队优先 | 已实现 |
| 目标离开视野后清除 | 已实现 |
| 统一遭遇判定 / 攻击意图 | 已实现（`EncounterManager`，距离 50） |
| 玩家接近离屏战斗交互 | 已实现（加入/离开，独立暂停原因） |
| AI 对 AI 离屏战斗 | 已实现（每游戏小时结算伤亡，最多 48 小时） |
| 第三方响应 / 中途加入 | 已实现 |
| 玩家被主动拦截遭遇对话 | 已实现（底部 NPC 对话、领袖头像、`ENEMY_PURSUIT` 禁止离开） |
| 玩家主动追击接触 | 已实现（`focus_party_id` 作为显式交互意图，`PLAYER_INITIATED` 保留离开） |
| 中立/无关部队不自动打断 | 已实现（普通对话只对主动点击目标；自动遭遇需实际追击关系） |
| `UnitAI` | AI/玩家双模式、360°定向矩形、单次单目标、搜索/接近/攻击状态、外围进攻点、降速、实体碰撞、队形槽位与局部避让已实现；复杂战术/寻路 TODO |
| 远程单位 AI | 已实现：射程内站定射击、射程外接近、过近后撤、换目标、独立 3 秒冷却；无预判/齐射/弹药 |
| `LordAI` | 部分实现：自有封地征召（低于人数阈值 → 前往村庄 → 招募一组）；战略攻击/撤退/性格权重 TODO |
| 空间查询 | TODO(阶段2) |
| 统一随机源 | TODO(阶段3) |

## 9. 待确认

- 部队 AI 是否需要“性格”影响。
- 离屏战斗的伤兵/俘虏、士气与长期平衡；当前已有按小时战力结算与随机波动。
- 大规模部队数量目标（决定空间索引与 LOD 策略）。
- 商队路线、巡逻点与强盗游荡点是否迁移到 `.tres` 配置资源（KI128）。
- NPC 追击玩家的遭遇阈值是否应按双方视野动态调整。

## 10. 专属巡逻点与家族骑士（阶段 6 新增）

- `PartyData.ai_patrol_points` 持久化每支部队的巡逻点数组。
- `AIManager._update_patrol_party()` 优先使用部队专属路线；为空时回退全局 `PATROL_POINTS`。
- 巴里骑士、墨西西骑士以 `PATROL` 类型围绕各自村庄巡逻，并由现有 `AIManager` 控制；不新增 NPC 管理 UI 或特殊地图逻辑。
- 东路强盗、荒野强盗沿用 `BANDIT` AI，只通过独立 `ai_route_settlement_ids` 与出生点区分。
- 家族不参与敌对判定：家族骑士属于 `FACTION_LOCAL`，与玩家中立；家族 `family_id` 仅由表现层读取。
- 大地图速度倍率在 `WorldMapManager` 统一应用，AI 仍按原始 `movement_speed` 做速度关系比较。

## 11. 战后交战冷却与恢复（阶段 6 后续）

- `PartyData.engagement_cooldown_until` 为运行时世界时间截止点，由 `BattleManager._unlock_session_parties()` 设置。
- `AIManager._is_in_post_battle_cooldown()` 在冷却期间：
  - 强盗：清除攻击意图与追击目标，恢复游荡路线；
  - 治安队：清除攻击意图与追击目标，恢复巡逻；
  - `_try_respond_to_battle()` 直接返回 false，不接近附近战斗。
- `EncounterManager.update_encounters()` 跳过任一方处于冷却的敌对组合，避免接触距离内逐 tick 重新开战。
- 冷却不写入存档；读档统一清零，AI 按当前世界状态重新决策。

## 12. 战后追击、强盗敌对与视野助攻（阶段 10）

### 12.1 追击与遭遇不再依赖移动状态

- `EncounterManager.update_encounters()` 只要求双方有效、关系敌对、距离进入遭遇半径，并且攻击意图或追击焦点成立；`MOVING` 不再是必要条件。
- 目标停下、转向或被其他战斗锁定时，AI 保留攻击意图与追击目标；战后冷却期间先脱离接触，冷却结束后重新评估。
- 玩家追击使用 `focus_party_id` + `FOLLOW_PARTY`；目标进入离屏战斗时 `WorldMapManager` 保留焦点并原地等待，战后自动恢复（详见 `World_Map_System.md`）。

### 12.2 强盗与贵族敌对

- 关系解析统一在 `FactionManager.get_party_relation()`：强盗（`party_kind == BANDIT` 或强盗阵营）对任何政治家族贵族（独立家族、统治家族、附庸家族、玩家家族）一律 `HOSTILE`。
- 不依赖名称；同家族/同王国、王国战争、商队中立与治安队友好规则不变。
- 因此强盗 AI 会将国王卫队、家族骑士、玩家部队都视为可追击目标；玩家家族也永久敌对（暂无外交/招安，KI511）。

### 12.3 视野门槛的战场助攻

- `VisionManager` 提供 `include_in_battle` 查询，使观察者能在 `sight_range` 内“看见”正在离屏战斗的参战方。
- `AIManager._try_respond_to_battle()` 仅在满足以下条件时响应：
  - 通过视野发现该战斗，且至少看见一名参战方；
  - 自身与战斗位置进入 `BATTLE_APPROACH_RADIUS`；
  - `BattleManager.get_join_side()` 返回有效侧。
- 发现后写入 `battle_response_id/until`，保持约 15 秒接近目标，避免视野抖动导致反复放弃。
- 商队不响应；家族骑士/卫队、强盗、治安队可以响应。
- 实际加入统一经 `EncounterManager`/`BattleManager`，复用既有 `BattleSession`，不新建战斗。

### 12.4 加入规则检查全部战斗侧

- 必须恰好存在一个与自身敌对的侧，且至少存在一个与自身非敌对的侧，才加入该非敌对侧。
- 与所有侧敌对时 `get_join_side()` 返回 -1，不自动生成第三战斗侧；全中立同样拒绝。
- 已处于其他战斗中的部队拒绝加入。
- 三方及以上多方战斗只能通过显式多方入口创建，不由助攻自动产生。

### 12.5 冷却与恢复

- 战后冷却仍由 `BattleManager` 统一设置；冷却期间 AI 恢复路线/巡逻或保持追击等待，任务层不反复发起遭遇。
- 冷却结束后强盗重新评分并追击，玩家追击也重新触发遭遇。
- 多场并行战斗结束后，幸存者统一回到 `AVAILABLE` 并由下一次 AI tick 恢复移动。
