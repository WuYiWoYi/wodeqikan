# 大地图系统

**所属层：** 玩法逻辑 / 表现
**核心脚本：** `Scripts/Systems/WorldMap/world_map_manager.gd`、`Scripts/UI/WorldMap/world_map.gd`
**场景：** `Scenes/WorldMap/world_map.tscn`
**状态：** 基础移动、NPC 自主商队/巡逻/强盗/治安队、部队跟随、视野查询、地点交互与村庄入口、遭遇与战斗交接、玩家追击接触、追逐焦点保护、人数图标与悬浮信息、日期/时间段 UI、单战斗标记与多方战斗汇总已实现

---

## 1. 职责

- 维护大地图坐标系与世界边界。
- 处理部队的目标设置、移动推进、跟随与到达判定。
- 向表现层提供可读取的部队位置。

不负责：图标节点、UI、战斗、AI 决策、视野关系判定（由 `VisionManager` 提供）、路径规划（初期）。

相关公共系统：

- `FactionManager`：阵营注册与友好/中立/敌对查询的唯一入口。
- `VisionManager`：基于 `PartyData.sight_range` 的可见部队查询唯一入口。
- `EncounterManager`：统一遭遇判定、玩家中途参战交互与战斗创建/加入委托。
- `AIManager`：只使用上述查询结果选择目标，不重复实现阵营、视野或遭遇逻辑。

## 2. 坐标与单位

| 项 | 规则 |
|---|---|
| 坐标系 | 2D 世界坐标，原点左上，+X 向右，+Y 向下 |
| 位置字段 | `PartyData.world_position`、`target_position`，单位：像素 |
| 速度 | `PartyData.movement_speed`，单位：像素 / 游戏秒 |
| 地图边界 | `WorldMapManager.world_bounds: Rect2` |
| 存档格式 | `Vector2` 序列化为 `[x, y]` |

Milestone 1 地图固定为 3000×2000。摄像机支持跟随、方向键平移和滚轮缩放（0.5x–2x）；缩放只改变表现层，数据坐标不变。1920×1080 下默认缩放为 1.5x，保持与旧 1152×648 接近的大地图视野；UI 位于 CanvasLayer，不受相机缩放影响。

## 3. 部队移动

### 3.1 目标设置

```text
玩家点击地图
  → 大地图输入控制器
  → WorldMapManager.set_party_target(party_id, world_position)
      ├── 校验部队存在且 battle_state == AVAILABLE
      ├── 将目标点限制在地图边界内
      ├── target_position = 目标
      ├── current_order = MOVE
      └── movement_state = MOVING
```

AI 部队由 `AIManager` 调用同一接口设置目标，不直接改字段：

- 商队：`TRADE_ROUTE`，在橡木村与河畔村之间往返；
- 治安队：`GUARD`，无威胁时按四个固定巡逻点循环，发现强盗后追击/拦截；
- 强盗：`BANDIT`，无目标时沿配置路线游荡，发现敌对目标后追击；
- AI 每 1 世界秒决策一次；移动仍由 `WorldMapManager` 执行。

### 3.1.1 玩家速度、输入与跟随

- 新游戏玩家部队移动速度：150 像素/游戏秒。
- 治安队：120 像素/游戏秒；强盗：100；商队：80。速度关系为治安队 > 强盗 > 商队。
- 旧存档通过 `PartyData.movement_speed` 保留原速度，读档不会按新常量重置。
- 顶部数字键 `1` / `2` / `3` 分别暂停 / 1x / 2x；小键盘不响应，echo 不重复触发。
- UI 面板打开时快捷键和地图点击都被屏蔽。
- 玩家点击地图成功设置目标后，基础倍率自动切为 1x；不清除任何暂停原因。
- 点击地图外区域或部队不可用时，不改变时间倍率。

玩家点击其他部队：

| 点击目标 | 行为 |
|---|---|
| 移动中的有效部队 | `FOLLOW_PARTY`：记录目标 `party_id`，持续更新目标位置 |
| 静止的有效部队 | 普通 `MOVE`，前往其当前位置 |
| 战斗中 / 失效 / 空部队 | 普通 `MOVE` 到其当前位置，不进入跟随 |

跟随规则：

```text
set_party_follow(follower, target)
  → 校验双方可用、目标有存活成员、目标在 follower.sight_range 内
  → current_order = FOLLOW_PARTY
  → current_target_id = target_party_id

每 0.5 世界秒（WorldTime tick 内）刷新：
  → 目标不存在/不可用/空/进入战斗 → 取消跟随
  → 目标离开观察者视野         → 取消跟随
  → 与目标距离 <= 14 像素       → 视为追上，取消跟随
  → 否则 target_position = 目标最新位置

普通移动指令会覆盖 FOLLOW_PARTY 并清除 current_target_id。
```

- 跟随更新只在 `WorldSimulation.on_world_tick` 中执行；世界暂停时不会刷新或移动。
- `current_order` 与 `current_target_id` 已在存档中，读档后可继续跟随；目标失效时自动清理。
- 不直接修改位置，也不每帧重新寻路。

### 3.1.2 追逐焦点与自动交互保护

玩家点击部队后，`PartyData.focus_party_id` 记录当前主动追逐/接近目标：

- 移动中目标：`FOLLOW_PARTY`，持续跟随；
- 静止目标：普通 `MOVE` 到其当前位置；
- 普通地图点击、停止移动、目标失效或到达后清理焦点。

焦点非空期间：

- 路过村庄不自动打开地点面板；
- 路过其他无关部队不打开部队对话，不打断当前追逐；
- 不因接近 NPC 离屏战斗而弹出加入/离开面板；
- **敌对 AI 主动追击玩家**的遭遇仍按原有规则触发，可以打断玩家行动。

到达目标后焦点清除，下一帧恢复原有的主动接近对话/地点交互。
焦点是运行时字段，不进入存档。

### 3.2 推进

- 只有 `WorldSimulation.on_world_tick` 调用 `update_party_movement(fixed_delta)`。
- 直线移动，不做寻路。
- 到达阈值 2 像素；到达后精确对齐目标，置 `IDLE`，清理 `current_order`。
- 每 tick 移动距离 = `movement_speed * fixed_delta`。
- 大地图暂停或倍率变化时，tick 本身被 `TimeManager` 控制，移动逻辑不感知倍率。
- 目标点和每 tick 的下一位置都经过地图边界 clamp。

### 3.3 玩家操作与摄像机

- 鼠标左键点击地图 → `set_party_target()`。
- 方向键平移摄像机；滚轮缩放；摄像机平滑跟随玩家。
- 点击移动时会清除摄像机手动偏移，重新跟随玩家。
- 地图点击在 `_unhandled_input` 中处理，UI 面板会拦截自己的区域。

### 3.4 战斗锁定

`battle_state != AVAILABLE` 的部队：

- 不接受新目标；
- 不推进位置；
- 图标仍可显示，但进入战斗/返回中的状态由 UI 表现。

## 4. 表现同步

```text
WorldSimulation 更新 PartyData.world_position
  → EventBus.party_position_changed(party_id)
  → 大地图图标读取最新坐标
  → _process 中插值到显示位置（只写视觉）
```

- 表现层允许插值，禁止把插值后的坐标写回 `PartyData`。
- 图标不保存权威坐标；场景重载时从数据重建。
- 图标节点是 `PartyData` 的展示载体，不是实体本身。
- 当前实现中 `PartyIcon._process` 每帧把显示位置 lerp 到 `PartyData.world_position`。
- 部队图标只显示当前人数，不再显示部队名称；人数变化时同步更新 `CountLabel`。

### 4.1 鼠标悬浮信息

鼠标悬浮在部队图标 30 像素范围内时显示简易面板：

- 部队名称；
- 成员构成按“兵种 + 骑乘状态”合并计数，例如“骑马职业步兵（3）”“民兵（3）”；
- 玩家角色单独显示为“玩家角色（1）”；
- 鼠标离开图标后关闭；
- 面板及子控件 `mouse_filter = IGNORE`，不拦截地图点击、移动或时间按钮；
- 面板打开期间如果弹出保存/地点/部队等模态 UI，悬浮面板自动隐藏；
- 成员构成变化时通过轻量签名比较刷新，不在每帧重建节点。

### 4.2 战斗中图标与战斗标记

当 `BattleManager.current_battle` 非空时：

- 同一场 `BattleSession` 的所有参战部队只显示一个 `BattleMarker`，位置为 `session.world_position`；
- 参战部队原有 `PartyIcon` 暂时隐藏，未参战部队保持正常显示；
- 战斗标记下方显示总存活人数；
- 屏幕空间显示 `BattleSummaryPanel`，按 `side_index` 分组：
  - 同一战斗侧的多个部队并列展示，不使用阵营代替战斗侧；
  - 每支部队先列出名称，再按兵种 + 骑乘状态合并存活人数，例如「民兵（3）」「骑马职业步兵（2）」；
  - 不同战斗侧之间显示分隔线；
  - 只读取 `BattleUnitState`，不修改战斗或部队数据；
- 每次离屏小时结算、部队加入或战斗结束时，面板文本与人数自动刷新；
- 战斗结束后移除标记、清空汇总并恢复所有普通部队图标。

### 4.3 时间显示

- 顶栏只显示年月日 + 时间段，不显示小时/分钟，例如“世界时间：1103 年 1 月 1 日 深夜”。
- 时间段文字来自 `TimeManager.get_time_period()`；具体区间集中配置。
- 倍率仍显示暂停 / 1x / 2x。

## 5. 地点交互（Milestone 1）

地点交互由大地图场景控制器检测，不属于移动逻辑：

```text
每帧检查玩家部队
  → 用“上一帧位置到当前位置”的线段与地点做最近点距离
  → 距离 <= 40 像素：停止部队、时间设为暂停、打开面板
  → 面板关闭后保持暂停
  → 玩家离开 64 像素后解除触发锁
```

- 使用线段检测是为了避免 2x 速度下一 tick 跨过地点。
- 停止移动通过 `WorldMapManager.stop_party()`，不直接改字段。
- 打开面板压入 `ui_panel` 暂停原因，并设置基础倍率为 0。
- 离开面板只移除暂停原因，不恢复基础倍率；玩家需主动选择 1x / 2x。
- 当前只有玩家部队触发地点交互；NPC 不触发。
- 玩家正在主动追逐部队（`focus_party_id` 非空）时跳过地点自动交互，避免打断追逐。
- 村庄面板提供“进入村庄”：`WorldMap.enter_village()` 校验 `scene_path`、压入 `small_scene`、释放 `ui_panel` 并切换场景。
- 从小场景返回时，`GameManager.pending_settlement_latch_id` 作为一次性地点交互锁，玩家离开 64 像素后才重新允许自动打开。

## 6. 视野

**状态：** 已实现（`VisionManager`，阶段 4 Step 5）。

规则：

- 每个部队有圆形视野 `PartyData.sight_range`；由 `WorldInitializer` 按兵种配置。
- 两部队距离 `<= 观察者视野半径` 判定为发现；每次查询即时计算，不维护长期记忆。
- 观察者必须 `AVAILABLE` 且有存活士兵；`DISABLED` / `IN_BATTLE` 部队不主动发现目标。
- 目标必须可用、有存活士兵且不是空部队。
- 查询入口：
  - `get_visible_parties()`
  - `get_visible_hostile_parties()` / `get_visible_friendly_parties()` / `get_visible_neutral_parties()`
  - `can_see()`、`get_nearest_visible_hostile()`、`get_distance()`
- 目标离开视野后 `can_see()` 立即为 false；AI 与跟随逻辑负责清除过时目标。
- 不做地形/建筑遮挡、战争迷雾或情报记忆。

## 7. 遭遇与战斗交接

**状态：** 玩家对话遭遇、AI 主动追击、离屏战斗、玩家中途加入已实现。

### 7.1 玩家与中立/友好部队

```text
每帧检查玩家部队
  → 用“上一帧位置到当前位置”的线段与非玩家、非空、可用部队做最近点距离
  → 敌对阵营跳过（由 AI 直接发起战斗）
  → 距离 <= 40 像素：停止玩家部队、打开 PartyDialoguePanel、压入 ui_panel 暂停
  → 离开面板：移除暂停原因，恢复此前基础倍率
  → 发起战斗：
      → BattleManager.start_battle([玩家], [敌方], 位置)
      → 先压入 battle 暂停，再释放 ui_panel
      → SceneManager.change_scene(BattleScene)
```

### 7.2 AI 主动遭遇

- 强盗/治安队通过 `VisionManager` 发现敌对目标，`AIManager` 持续更新目标位置并追击，设置 `PartyData.attack_intent`。
- `EncounterManager.update_encounters()` 是唯一遭遇判定入口（距离 50）：
  - 双方有效、阵营敌对、距离 <= `AI_ENCOUNTER_RADIUS (50)`；
  - 满足以下任一意图条件：
    - 至少一方的 `attack_intent` 明确指向对方（`current_target_id` 匹配）；
    - 玩家主动点击并持续追击该敌对部队（`player.focus_party_id == 对方 party_id`）。
- 玩家追击的接触在移动之后、AI 之前判定；即使目标继续同向移动，也会在有效距离内一次性触发，不要求目标停下。
- 接触成立后立即清除双方移动目标、追击指令、`focus_party_id` 与攻击意图，随后暂停时间并弹出战斗选择界面；不会继续推挤、回弹或重复创建战斗。
- 满足条件后：
  - 双方都未参战 → `BattleManager.start_battle(..., offscreen = true)`；
  - 一方已在离屏战斗 → 检查另一方是否可以加入；
  - 玩家被主动拦截 → 停止双方并进入遭遇对话，不直接创建战斗。
- 普通巡逻/普通移动没有攻击意图，不会因为接近而触发战斗。
- NPC 对 NPC：世界不暂停，每 1 个游戏小时结算一次伤亡，直到一方全灭/平局/48 小时上限；期间第三方可加入。
- 战斗期间参战部队 `IN_BATTLE`，不移动、不执行 AI。

### 7.3 玩家被主动拦截的遭遇对话

```text
敌对 AI 追击玩家（attack_intent + current_target_id = 玩家）
  → 距离 <= 50
  → EncounterManager 停止双方、清除追逐
  → 记录 encounter_id / attacker / target
  → EventBus.player_encounter_requested
  → WorldMap 压入 encounter_dialogue 暂停
  → 显示敌对部队名称、阵营、兵力、遭遇描述
  → [战斗] / [撤退] 两个选项
  → 战斗：创建屏幕战斗，移除 encounter_dialogue，切换 BattleScene
  → 撤退：关闭面板、清理待处理遭遇并记录拒绝锁
```

- 撤退后双方保持停止位置，世界恢复原基础倍率；AI 可在下一次决策继续行动，不会永久停止。
- 在离开 `ENCOUNTER_DECLINE_EXIT_RADIUS (90)` 之前，同一敌对部队不会重复触发遭遇；离开范围后可再次触发。
- 遭遇对话只移除自身的 `encounter_dialogue` 暂停原因；基础倍率不变，其他暂停原因不受影响。
- 待处理遭遇非空时不会重复触发；WorldSimulation 在该 tick 跳过 AI。
- 对话异常退出或场景销毁时清理暂停与待处理遭遇，避免世界永久暂停。
- 玩家主动接近敌对 AI、或 AI 正在追击其他目标时不会触发该对话。

### 7.4 玩家接近进行中的离屏战斗

```text
玩家进入离屏战斗交互范围 BATTLE_INTERACTION_RADIUS (55)
  → 玩家未参战、未 DISABLED、可以加入该战斗
  → EncounterManager 停止玩家、记录 interaction_id / battle_id
  → EventBus.player_battle_interaction_requested
  → WorldMap 压入 battle_encounter_dialogue 暂停
  → 显示“遭遇战”面板：交战方、持续时间、[加入战斗] / [离开]
```

加入：

- 移除 `battle_encounter_dialogue`；
- `BattleManager.try_join_battle(player_party_id)` 加入已有 BattleSession；
- 战斗转换为屏幕战斗，保留 `battle` 暂停；
- WorldMap 切换 `BattleScene`，玩家输入作用于实际加入的战斗侧；
- 不会创建重复战斗。

离开：

- 移除 `battle_encounter_dialogue`；
- 玩家不参战，保持在当前位置，不恢复原移动指令；
- 记录 `_declined_battle_id`，玩家仍在 `BATTLE_INTERACTION_EXIT_RADIUS (90)` 内不会重复弹出；
- NPC 战斗继续按离屏规则运行。

保护：

- 同一时间只允许一个战斗交互面板；
- 离开交互范围后再次接近可以重新触发；
- 战斗在面板打开期间结束、战斗 ID 变化或玩家已参战 → 自动关闭面板并清理暂停；
- 面板/场景异常关闭只清理 `battle_encounter_dialogue`，不影响其他暂停原因与基础倍率。

规则：

- 同一时间只有一个对话面板；离开 64 像素后才会再次触发。
- 空部队（被击溃）不再触发交互。
- 同阵营部队不能开战；任一方无兵时战斗按钮禁用。
- 战斗触发后，参战部队立即锁定，不能同时在大地图移动。
- 世界模拟层的 AI 决策可在任意时刻发起离屏战斗。

## 8. 扩展方向

- 路径规划与寻路网格。
- 地形速度系数、道路加成、河流/山脉阻挡。
- 地图边界形状（非矩形）。
- 镜头滚动与缩放。
- 多选部队与军团移动。
- 视野遮挡与探测。

## 9. 实现状态

| 项 | 状态 |
|---|---|
| `world_bounds` 与目标 clamp | 已实现 |
| `set_party_target` | 已实现 |
| `update_party_movement` | 已实现（直线/到达/边界） |
| `stop_party` | 已实现 |
| `update_visibility` | 保留空实现；实际查询由 `VisionManager` 提供 |
| NPC 商队往返 / 治安队巡逻 | 已实现（AIManager） |
| 强盗游荡 / 动态目标评分 / 追击 | 已实现（AIManager + VisionManager） |
| 治安队发现/拦截强盗 | 已实现（威胁商队优先） |
| 玩家接近中立部队对话 | 已实现（场景侧检测 + 对话） |
| 统一 AI 遭遇判定 | 已实现（`WorldMapManager`，距离 50，攻击意图） |
| 玩家被主动拦截遭遇对话 | 已实现（`encounter_dialogue`，战斗/撤退） |
| AI 对 AI 离屏战斗 | 已实现（每游戏小时结算伤亡，最多 48 小时） |
| 玩家追击同向移动敌军 | 已实现（`focus_party_id` 作为追击意图，接触后立即停止） |
| 玩家接近离屏战斗交互 | 已实现（加入/离开面板，独立暂停原因） |
| 同一战斗单标记 + 多方汇总 UI | 已实现（按 `side_index` 分组，实时人数） |
| 玩家中途加入离屏战斗 | 已实现（加入已有战斗，不重复创建） |
| `battle_started` 自动进入战斗场景 | 已实现（玩家参与时） |
| 玩家部队跟随目标部队 | 已实现（0.5 世界秒刷新） |
| 时间快捷键 1/2/3 | 已实现（顶部主键区） |
| 点击地图后切 1x | 已实现（不清除暂停原因） |
| 表现层图标 | 已实现（程序绘制） |
| 摄像机跟随/平移/缩放 | 已实现 |
| 地点交互 | 已实现（场景侧检测） |
| 追逐焦点保护 | 已实现（`focus_party_id`；村庄/无关部队/离屏战斗不打断） |
| 村庄入口 | 已实现（进入村庄 + 返回锁） |
| 部队图标人数 | 已实现（去掉名称，只显示人数） |
| 鼠标悬浮信息 | 已实现（名称 + 兵种/骑乘合并统计，不拦截点击） |
| 世界时间 UI | 已实现（年月日 + 时间段） |

## 10. 待确认

- 遭遇阈值是否按双方视野决定（当前统一固定 50 世界单位）。
- 离屏自动战斗的时长、平衡与随机性。
- 玩家加入离屏战斗时是否允许手动选择战斗侧（当前按阵营关系自动确定）。
- 战斗交互面板是否扩展“观察/离开并继续移动”等选项。
- 遭遇对话是否继续扩展谈判/缴赎等选项（当前已提供战斗与撤退）。
- 地点交互检测是否迁移到世界模拟层（当前在场景控制器）。
- 路径规划、地形阻挡与道路加成的具体规则。
