# 大地图系统

**所属层：** 玩法逻辑 / 表现
**核心脚本：** `Scripts/Systems/WorldMap/world_map_manager.gd`、`Scripts/UI/WorldMap/world_map.gd`
**场景：** `Scenes/WorldMap/world_map.tscn`
**状态：** 基础移动、NPC 自主商队/巡逻/强盗/治安队、统一 Party 数据、恢复原尺寸的圆形部队标记、放大的村庄圆形标记与位于上方的固定屏幕名称、部队跟随、视野查询、地点交互与村庄入口、底部 NPC 遭遇对话（领袖头像/对白/动态选项）、遭遇原因与敌对追击禁离开、玩家追击接触、追逐焦点保护、人数图标与悬浮信息、日期/时间段 UI、按战斗 ID 独立的多战斗标记与多方战斗汇总、世界日志面板、封地信息与采邑征召入口、部队浮动提示、5000×3000 地图与城镇图标、百科入口、阶段 9 地点区域化布局与部队内部旗帜放大已实现

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

阶段 8 起世界地图固定为 5000×3000（原 3000×2000）。摄像机支持跟随、方向键平移和滚轮缩放（0.5x–2x）；缩放只改变表现层，数据坐标不变。1920×1080 下默认缩放为 1.5x；UI 位于 CanvasLayer，不受相机缩放影响。

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

- 商队：`TRADE_ROUTE`，在巴里与墨西西之间往返；
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
| 有效部队（移动中或静止） | `FOLLOW_PARTY`：记录目标 `party_id`，持续更新目标位置 |
| 战斗中 / 失效 / 空部队 | 普通 `MOVE` 到其当前位置，不进入跟随 |

跟随规则：

```text
set_party_follow(follower, target)
  → 校验双方可用、目标有存活成员
  → current_order = FOLLOW_PARTY
  → current_target_id = target_party_id

每 0.5 世界秒（WorldTime tick 内）刷新：
  → 目标不存在/不可用/空/进入战斗 → 取消跟随
  → 与目标距离 <= 14 像素           → 视为追上，取消跟随
  → 否则 target_position = 目标最新位置

普通移动指令会覆盖 FOLLOW_PARTY 并清除 current_target_id。
```

- 跟随只由玩家主动点击部队图标触发。地图图标始终可见，因此不要求目标处于 `sight_range` 内，也不因目标离开视野而取消。否则远距离点击巡逻部队只会走向点击瞬间的旧坐标，目标继续巡逻后玩家停在原地，永远无法接触中立家族骑士等不会主动接近玩家的部队。
- 静止部队同样进入跟随：目标在玩家接近途中开始巡逻时仍能继续追赶。
- `VisionManager` 的视野规则继续约束 AI 选择目标，不改变 AI 行为。

- 跟随更新只在 `WorldSimulation.on_world_tick` 中执行；世界暂停时不会刷新或移动。
- `current_order` 与 `current_target_id` 已在存档中，读档后可继续跟随；目标失效时自动清理。
- 不直接修改位置，也不每帧重新寻路。

### 3.1.2 追逐焦点与自动交互保护

玩家点击部队后，`PartyData.focus_party_id` 记录当前主动追逐/接近目标：

- 有效的移动中或静止目标：`FOLLOW_PARTY`，持续跟随其最新位置；
- 只有战斗中/失效/空部队退回普通 `MOVE`；
- 普通地图点击、目标失效或到达后清理焦点。
- 中立部队（家族骑士、商队、治安队）不会主动接近玩家，必须由玩家点击图标发起接近。

焦点非空期间：

- 路过村庄不自动打开地点面板；
- 路过其他无关部队不打开部队对话，不打断当前追逐；
- 不因接近 NPC 离屏战斗而弹出加入/离开面板；
- **敌对 AI 主动追击玩家**的遭遇仍按原有规则触发，可以打断玩家行动。

到达目标后焦点清除；普通部队对话仍只对主动点击的目标打开，地点面板仍必须由鼠标点击地点打开。
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

> 阶段 6 后续改为默认只显示名称，按住左 Alt 展开详细构成，见 12.2。

鼠标悬浮在部队图标 30 像素范围内时显示简易面板：

- 部队名称；
- 成员构成按“兵种 + 骑乘状态”合并计数，例如“骑马职业步兵（3）”“民兵（3）”；
- 玩家角色单独显示为“玩家角色（1）”；
- 鼠标离开图标后关闭；
- 面板及子控件 `mouse_filter = IGNORE`，不拦截地图点击、移动或时间按钮；
- 面板打开期间如果弹出保存/地点/部队等模态 UI，悬浮面板自动隐藏；
- 成员构成变化时通过轻量签名比较刷新，不在每帧重建节点。

### 4.2 战斗中图标与战斗标记

大地图按 `battle_id` 独立管理每场战斗的标记：`_battle_markers: { battle_id: BattleMarker }`。

- 每场进行中的 `BattleSession` 各自显示一个 `BattleMarker`，位置为该场 `session.world_position`；
- 每次刷新读取 `BattleManager.get_active_battles()`：为新战斗创建标记、更新现有标记位置与存活人数、删除已结束战斗的标记；删除一场不清理其他标记；
- 参战部队原有 `PartyIcon` 按“是否参与任意进行中战斗”隐藏；未参战部队保持正常显示；
- 一场战斗结束时只恢复该场仍存活部队的图标，其他战斗的参战图标保持隐藏；
- 战斗标记下方显示该场战斗自己的总存活人数；
- 屏幕空间显示单个 `BattleSummaryPanel`，目标为 `current_battle`，否则为战斗 ID 最小的一场：
  - 每次显示只对应一场战斗的数据，不得把战斗 A 的参战信息显示到战斗 B；
  - 按 `side_index` 分组；同一战斗侧的多个部队并列展示，不使用阵营代替战斗侧；
  - 每支部队先列出名称，再按兵种 + 骑乘状态合并存活人数，例如「民兵（3）」「骑马职业步兵（2）」；
  - 不同战斗侧之间显示分隔线；
  - 只读取 `BattleUnitState`，不修改战斗或部队数据；
- 每次离屏小时结算、部队加入或战斗结束时，标记与汇总自动刷新；
- 无进行中的战斗时移除全部标记、清空汇总并恢复所有普通部队图标。
- 测试接口：`get_battle_marker()`（汇总目标标记）、`get_battle_marker_for(battle_id)`、`get_battle_marker_count()`。

### 4.3 世界日志面板

- 大地图左下角固定显示共享 `WorldLogPanel`，位于底部信息栏上方，不随摄像机移动；村庄右上角复用同一组件。
- 面板只读取 `WorldContext.world_log_manager` 的 `WorldLogEntry` 列表：
  - 标题「世界日志」；
  - 时间 + 事件文本；
  - `ScrollContainer` 支持历史记录滚动；
  - 新事件通过 `entry_added` 自动刷新并滚动到最新。
- 面板与滚动区域使用 `MOUSE_FILTER_PASS`，日志文本不拦截输入，不影响地图点击和移动。
- 详细事件来源、上限与存档恢复见 [World_Log_System.md](World_Log_System.md)。

### 4.4 时间显示

- 顶栏只显示年月日 + 时间段，不显示小时/分钟，例如“世界时间：1103 年 1 月 1 日 深夜”。
- 时间段文字来自 `TimeManager.get_time_period()`；具体区间集中配置。
- 倍率仍显示暂停 / 1x / 2x。

## 5. 地点交互（Milestone 1，阶段 7 修订）

点击地点 = 设置移动目标；到达地点 = 停止、暂停、打开面板。两者严格分离：

```text
左键点击地图
  → 点击位置 <= 45 像素内存在地点
      ├── 玩家与地点距离 <= 40：直接停止、暂停、打开面板
      └── 否则：
          ├── 记录 _pending_settlement_interaction_id
          ├── WorldMapManager.set_party_target(玩家, 地点坐标)
          ├── 清除追逐焦点与跟随指令
          ├── 基础倍率切回 1x
          └── 不打开面板、不压入 ui_panel
  → 世界继续运行，玩家部队自动移动
  → _process 检测 pending：
      地点存在 + 玩家可用 + 已停止 + 距离 <= 40 + 移动目标仍指向该地点
      → 清空 pending → _open_settlement()
      → stop_party + 基础倍率 0 + push_pause(ui_panel) + 显示面板
  → 面板关闭后保持暂停
```

- `_open_settlement()` 仍负责停止部队、暂停世界与显示面板；只有到达检测或已在地点附近时调用。
- `_pending_settlement_interaction_id` 仅属于大地图运行时状态，不进入存档。
- 玩家正常寻路、追击部队或路过任何村庄/城镇/城堡时，不会创建 pending，也不会暂停或打开地点面板。
- 点击地点与其图标附近的部队重叠时，以点击位置更近的对象为准。
- 点击普通地图位置、点击部队、点击另一个地点、外部停止、进入战斗或离开大地图时清除 pending；点击另一个地点直接替换目标 ID。
- 已停止但离目标超过 40 像素时取消本次交互，不打开面板。
- 打开面板压入 `ui_panel` 暂停原因，并设置基础倍率为 0。
- 离开面板只移除暂停原因，不恢复基础倍率；玩家需主动选择 1x / 2x。
- 村庄面板提供“进入村庄”：`WorldMap.enter_village()` 校验 `scene_path`、压入 `small_scene`、释放 `ui_panel` 并切换场景。
- 从小场景返回时，`GameManager.pending_settlement_latch_id` 记录当前村口村庄，供地点面板的进入按钮使用；返回后不会自动打开面板，也不会残留 pending。
- 城镇/城堡与村庄共用同一套点击、移动、到达规则；只有村庄显示“进入村庄”按钮。

### 5.1 封地信息与采邑征召（阶段 7 新增）

地点面板读取 `SettlementData` 与 `LordManager`，只读显示：

| 节点 | 内容 |
|---|---|
| `SettlementOwnerLabel` | 归属领主显示名；无主时显示“无主” |
| `SettlementFamilyLabel` | 家族显示名 |
| `SettlementPopulationLabel` | 人口 |
| `SettlementProsperityLabel` | 繁荣度 |
| `SettlementTaxLabel` | `tax_income_per_day`（统一由 `TaxCalculator` 计算） |
| `SettlementFiefLabel` | 采邑储备/上限与补充状态 |
| `SettlementRecruitStatusLabel` | 上次征召结果或失败原因 |
| `SettlementRecruitFiefButton` | 仅在玩家自有村庄显示；储备为 0 时禁用 |

- 点击按钮调用 `FiefRecruitmentManager.recruit_group(settlement_id, player_lord_id)`；UI 不计算编制、成本或周期。
- 成功后 `EventBus.fief_recruited` 触发玩家部队图标 `show_floating_text("招募了N组采邑")`，并刷新面板。
- 非自有村庄隐藏按钮，不显示不可用入口。
- 详细规则见 [Fief_Recruitment_System.md](Fief_Recruitment_System.md)。

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
- 目标离开视野后 `can_see()` 立即为 false；AI 负责清除过时的追击目标。玩家主动点击的 `FOLLOW_PARTY` 不受视野限制（D088）。
- 不做地形/建筑遮挡、战争迷雾或情报记忆。

## 7. 遭遇与战斗交接

**状态：** 玩家对话遭遇、AI 主动追击、离屏战斗、玩家中途加入已实现。

### 7.1 玩家与中立/友好部队

```text
每帧检查玩家主动点击/接近的目标（focus_party_id）
  → 仅在 focus_party_id 指向该部队时检查
  → 用“上一帧位置到当前位置”的线段做最近点距离
  → 敌对阵营跳过（由主动遭遇流程处理）
  → 距离 <= 40 像素：停止玩家部队、打开 PartyDialoguePanel、压入 ui_panel 暂停
  → 离开面板：移除暂停原因，恢复此前基础倍率
  → 目标部队不在任何战斗中、玩家也不在战斗中：
      → BattleManager.start_battle([玩家], [敌方], 位置)
      → 先压入 battle 暂停，再释放 ui_panel
      → SceneManager.change_scene(BattleScene)
  → 目标部队正在某场离屏战斗、玩家可加入：
      → 按钮变为“加入战斗”
      → BattleManager.try_join_battle(玩家, 目标 battle_id)
      → 复用同一场战斗并切换 BattleScene
  → 目标部队正在屏幕战斗、玩家已在战斗、或无法加入：
      → 禁用战斗按钮并说明本场战斗的真实原因
          “对方正在屏幕战斗中，暂时无法开战”
          “对方正在战斗中，靠近战场后可加入战斗”
          “玩家部队当前正在战斗中”
```

世界其他位置存在战斗不会阻塞玩家与无关部队开战。

- 普通寻路、追击其他目标时路过中立/友方部队不会自动打开对话。
- 玩家点击部队后 `focus_party_id` 指向该部队；只有该目标会触发普通对话。
- 目标被击溃、进入战斗、离开交互范围或玩家改为普通移动后清除焦点。
- 普通部队对话只读取**被点击部队自己所在的那场战斗**（`get_battle_for_party()`）；不得使用 `current_battle` 猜测，也不得因世界其他战斗而禁用按钮。
- 目标 `IN_BATTLE` / `RETURNING` / `DISABLED` 时分别显示“对方正在战斗中”“对方正在返回途中”“该部队已无法参战”。

### 7.2 AI 主动遭遇

- 强盗/治安队通过 `VisionManager` 发现敌对目标，`AIManager` 持续更新目标位置并追击，设置 `PartyData.attack_intent`。
- `EncounterManager.update_encounters()` 是唯一遭遇判定入口（距离 50）：
  - 双方有效、阵营敌对、距离 <= `AI_ENCOUNTER_RADIUS (50)`；
  - 满足以下任一意图条件：
    - 至少一方的 `attack_intent` 明确指向对方（`current_target_id` 匹配）；
    - 玩家主动点击并持续追击该敌对部队（`player.focus_party_id == 对方 party_id`）。
- 玩家追击的接触在移动之后、AI 之前判定；即使目标继续同向移动，也会在有效距离内一次性触发，不要求目标停下。
- 接触成立后立即清除双方移动目标、追击指令、`focus_party_id` 与攻击意图，随后暂停时间并弹出底部遭遇对话；不会继续推挤、回弹或重复创建战斗。
- 遭遇创建时记录实际原因：`ENEMY_PURSUIT`（敌对 AI 主动追击成功）、`PLAYER_INITIATED`（玩家主动接近/追击）、`PASSIVE_ENCOUNTER` 与 `OTHER`（预留）。原因决定对话文本与可用选项。
- 满足条件后：
  - 双方都未参战 → `BattleManager.start_battle(..., offscreen = true)` 创建新的独立战斗；
  - 一方已在离屏战斗、另一方空闲 → 用该方自己的 `battle_id` 检查并加入；
  - 双方已分别处于不同战斗 → 跳过本次遭遇，禁止合并会话或让一方同时参战；
  - 双方已在同一场战斗 → 不重复创建或加入；
  - 玩家被主动拦截 → 停止双方并进入遭遇对话，不直接创建战斗。
- 世界其他位置已有的战斗不阻塞新遭遇；每支部队只受自己所在战斗限制。
- 普通巡逻/普通移动没有攻击意图，不会因为接近而触发战斗。
- 中立部队与玩家、或与无关敌对部队的距离接近，不会自动暂停或弹窗；必须通过 `FactionManager` 敌对判定和实际追击关系。
- 玩家追击目标 A 时，路过无关敌对部队 B 不会被打断；只有 B 自己的 `attack_intent` 指向玩家并实际追上时才会触发 AI 主动遭遇。
- 玩家主动点击并追击敌对目标是显式交互入口，不依赖目标反过来追击；普通距离接近不会触发。
- 同一追击关系只允许触发一次有效遭遇；接触后双方停止，待处理遭遇与拒绝锁避免重复触发。
- NPC 对 NPC：世界不暂停，每 1 个游戏小时结算一次伤亡，直到一方全灭/平局/48 小时上限；期间第三方可加入。
- 战斗期间参战部队 `IN_BATTLE`，不移动、不执行 AI。

### 7.3 底部 NPC 遭遇对话

```text
遭遇成立
  → EncounterManager 停止双方、清除追逐
  → 记录 encounter_id / attacker_party_id / target_party_id / reason
  → EventBus.player_encounter_requested
  → WorldMap 压入 encounter_dialogue 暂停
  → 底部 PlayerEncounterPanel
      ├── 左侧 EncounterPortrait：对方领袖 UnitVisual（无领袖时默认剪影）
      ├── 领袖名称、阵营、兵力
      ├── EncounterDescriptionLabel：EncounterTextConfig 按 reason × party_kind 取文本
      └── 动态选项
  → 战斗：创建屏幕战斗，移除 encounter_dialogue，切换 BattleScene
  → 撤退：仅 PLAYER_INITIATED / PASSIVE / OTHER 可用
```

- UI 锚定屏幕下方（约 960×290），左侧头像、右侧对白与选项；不遮挡顶部时间栏与左下世界日志。
- 领袖头像复用 `UnitVisual`，不复制角色美术系统；`PartyManager.get_leader_unit()` 无有效领袖时使用 `EncounterPortrait` 的默认头肩剪影。
- 对话文本集中在 `Data/Encounters/encounter_text_config.tres`（`EncounterTextConfig`），UI 不硬编码对白。
- `ENEMY_PURSUIT`（敌对 AI 主动追击并成功拦截）不显示离开选项，并禁用等价离开入口；只保留战斗等敌对处理。
- 玩家主动接近、普通相遇仍保留原有离开规则；不能仅凭“双方敌对”禁止离开。
- 撤退后双方保持停止位置，世界恢复原基础倍率；AI 可在下一次决策继续行动，不会永久停止。
- 在离开 `ENCOUNTER_DECLINE_EXIT_RADIUS (90)` 之前，同一敌对部队不会重复触发遭遇；离开范围后可再次触发。
- 遭遇对话只移除自身的 `encounter_dialogue` 暂停原因；基础倍率不变，其他暂停原因不受影响。
- 待处理遭遇非空时不会重复触发；WorldSimulation 在该 tick 跳过 AI，旧追击指令不会覆盖当前状态。
- 对话异常退出或场景销毁时清理暂停与待处理遭遇，避免世界永久暂停。
- 玩家主动接近敌对 AI 时记录为 `PLAYER_INITIATED`，与 `ENEMY_PURSUIT` 使用不同文本与选项规则。

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
| 玩家接近中立部队对话 | 已实现（底部 NPC 对话 + 领袖头像） |
| 统一 AI 遭遇判定 | 已实现（`EncounterManager`，距离 50，攻击意图） |
| 遭遇原因与选项规则 | 已实现（ENEMY_PURSUIT 不允许离开；PLAYER_INITIATED 保留离开） |
| 玩家被主动拦截遭遇对话 | 已实现（`encounter_dialogue`，底部对白 + 动态选项） |
| 统一圆形部队标记 | 已实现（所有部队共用 PartyIcon/PartyMarkerStyle/圆形旗帜遮罩，恢复原尺寸 18/30） |
| 村庄圆形标记与名称 | 已实现（村庄单独放大 32/76，城堡不变；名称固定在标记正上方） |
| AI 对 AI 离屏战斗 | 已实现（每游戏小时结算伤亡，最多 48 小时） |
| 玩家追击同向移动敌军 | 已实现（`focus_party_id` 作为追击意图，接触后立即停止） |
| 玩家接近离屏战斗交互 | 已实现（加入/离开面板，独立暂停原因） |
| 多战斗标记 + 多方汇总 UI | 已实现（按 `battle_id` 独立标记，按 `side_index` 分组，实时人数） |
| 玩家中途加入离屏战斗 | 已实现（加入已有战斗，不重复创建） |
| `battle_started` 自动进入战斗场景 | 已实现（玩家参与时） |
| 玩家部队跟随目标部队 | 已实现（0.5 世界秒刷新） |
| 时间快捷键 1/2/3 | 已实现（顶部主键区） |
| 点击地图后切 1x | 已实现（不清除暂停原因） |
| 表现层图标 | 已实现（程序绘制） |
| 摄像机跟随/平移/缩放 | 已实现 |
| 地点交互 | 已实现（点击设置移动目标，到达后打开；路过不触发） |
| 追逐焦点保护 | 已实现（`focus_party_id`；无关部队/离屏战斗不打断） |
| 村庄入口 | 已实现（点击地点面板进入村庄） |
| 部队图标人数 | 已实现（去掉名称，只显示人数） |
| 鼠标悬浮信息 | 已实现（名称 + 兵种/骑乘合并统计，不拦截点击） |
| 世界时间 UI | 已实现（年月日 + 时间段） |
| 左下角世界日志 | 已实现（`WorldLogManager` + 滚动面板，与村庄共享） |
| 地点封地信息 | 已实现（领主/家族/人口/繁荣度/税收/采邑储备） |
| 采邑征召入口 | 已实现（仅玩家自有村庄；调用统一管理器） |
| 部队上方浮动提示 | 已实现（`PartyIcon.show_floating_text`，成功后显示“招募了N组采邑”） |
| 中立/无关部队不自动弹窗 | 已实现（只对主动点击目标打开普通对话） |
| AI 主动追击才自动遭遇 | 已实现（实际追击关系 + 敌对判定 + 单次触发） |

## 10. 待确认

- 遭遇阈值是否按双方视野决定（当前统一固定 50 世界单位）。
- 离屏自动战斗的时长、平衡与随机性。
- 玩家加入离屏战斗时是否允许手动选择战斗侧（当前按阵营关系自动确定）。
- 战斗交互面板是否扩展“观察/离开并继续移动”等选项。
- 遭遇对话是否继续扩展谈判/缴赎等选项（当前为战斗 + 按原因动态生成的离开选项；ENEMY_PURSUIT 不允许离开）。
- 地点到达是否需要在移动中途显示目标高亮或路径指示（当前只显示普通移动）。
- 路径规划、地形阻挡与道路加成的具体规则。

## 11. 圆形部队标记、村庄标记与统一速度（阶段 6 新增）

### 11.1 圆形部队标记（恢复原尺寸）

- `PartyIcon` 是所有部队类型唯一的圆形标记组件：圆形底盘、边框、旗帜、下方人数。
- 尺寸、边框、旗帜最大边长、人数偏移与阵营回退色集中在 `PartyMarkerStyle`（`Data/WorldMap/party_marker_style.tres`）。
- 标准半径 18、边框 2、旗帜最大边长 38、人数偏移 24；圆形底盘与人数偏移保持原尺寸，阶段 9 仅放大内部旗帜（见 14.2）。
- 旗帜来自 `PartyData.banner_texture_path`，为空时回退 `FamilyConfig.banner_texture_path`；无家族色时按阵营读取回退色。
- `map_flag_circle.gdshader` 的 `uv_radius` 仍按实际半径计算；未来单独调整部队标记时无需改绘制代码。
- 玩家、家族、商队、强盗、治安队使用同一节点与同一套绘制逻辑；玩家标记额外显示外圈高亮。
- 人数徽标与悬浮面板逻辑保持不变；图标仍不显示部队名称。

### 11.2 村庄圆形标记（放大）

- `SettlementIcon` 按 `SettlementType` 区分表现：村庄使用放大的圆形标记，城堡保留原建筑绘制，不直接放大所有建筑。
- 村庄标记半径 `32`、边框 `3`、旗帜最大边长 `76`；旗帜大于内径，由圆形边框裁掉四角。
- 旗帜来自 `SettlementData.family_id`；无家族或资源缺失时绘制默认旗帜与回退色。
- 点击判定仍由 `WorldMap.SETTLEMENT_CLICK_RADIUS = 45` 与世界坐标距离决定，不随绘制尺寸改变。

### 11.3 固定屏幕地点名称

> 阶段 6 后续已改为原始村庄美术 + 徽章/名称组合，见第 12 节。

- `SettlementIcon` 不再创建 `NameLabel`；`SettlementNameTag` 只显示文本。
- `SettlementNameTag` 位于大地图固定 UI 层，每帧跟随地点世界坐标转换后的屏幕位置；文字大小不受缩放影响。
- 名称水平居中，整体位于圆形标记正上方；间距 = 标记半径 × 相机缩放 + 10 屏幕像素，不会显示在标记下方。
- 每个标签按 `SettlementData.settlement_id` 独立创建；同名村庄不会合并。
- 名称标签完全不拦截鼠标，不影响地图点击、地点点击或部队悬浮。

### 11.4 统一大地图速度倍率

- `WorldMapManager.WORLD_MAP_SPEED_SCALE = 0.5`。
- 所有部队（玩家、商队、巡逻、强盗、家族骑士）都经过 `update_party_movement()`，在该唯一入口乘一次 0.5。
- `PartyData.movement_speed` 继续保存原始基础速度，不写回、不重复减半。
- 小地图/战斗中的 `UnitData.move_speed` 与 `StatCalculator` 不受影响。
- 旧存档部队读取原始速度后同样按统一倍率移动。

### 11.5 新部队

- 两支家族骑士：巴里骑士、墨西西骑士，`FACTION_LOCAL`，各自 `family_id`，专属巡逻点。
- 两支新强盗：东路强盗、荒野强盗，沿用 BANDIT 阵营与 AI，拥有独立出生点与路线。
- `WorldInitializer` 只在新游戏创建时生成；读档不调用初始化，不会重复生成。

## 12. 地点原始美术、徽章名称组合与悬浮 Alt（阶段 6 后续）

### 12.1 三个独立元素

| 元素 | 层级 | 职责 |
|---|---|---|
| `SettlementIcon` | 世界层（`world_entities`） | 原始村庄/城堡美术；位置、缩放、点击判定不变 |
| `SettlementNameTag` | 屏幕 UI 层（`SettlementNameLayer`） | 固定 240×36 的徽章 + 名称组合 |
| `SettlementNameTag.FamilyBadge` | 名称组合内部 | 左侧圆形家族徽章，颜色来自 `FamilyConfig` |

- 世界层不再绘制圆形村庄标记或旗帜，也不再携带名称。
- 名称组合整体位于地点世界坐标转换后的屏幕位置上方，按 `SettlementIcon.get_name_anchor_radius()` × 相机缩放 + 10 屏幕像素定位。
- 徽章读取 `SettlementData.family_id`；无家族隐藏徽章，只显示名称。
- 名称组合与徽章均为 `MOUSE_FILTER_IGNORE`。

### 12.2 悬浮信息简单/详细模式

- 默认：只显示部队名称。
- 按住左 Alt：增加“总人数”与按兵种/骑乘分组的构成（玩家角色单独统计）。
- 输入集中在 `world_map._input()`：只响应 `KEY_ALT` 且 `location != KEY_LOCATION_RIGHT`；忽略 echo，不标记事件已处理。
- 模式改变时立即重建当前悬浮面板并重新定位，不需要移动鼠标；松开左 Alt 立即恢复简单模式。
- 测试钩子：`set_alt_detail_active()`、`is_alt_detail_active()`。

### 12.3 战斗汇总按战斗侧分列

- `BattleSummaryContent` 为 `HBoxContainer`；每个 `side_index` 生成一列 `VBoxContainer`。
- 列头为“战斗侧 N”；同侧部队在列内纵向排列，伤亡实时刷新。
- 第三侧起自动增加列，面板宽度按列数扩展；战斗结束移除所有列并清空文本。
- 汇总面板一次只展示一场战斗：优先玩家 `current_battle`，否则取战斗 ID 最小的一场；切换目标时整列重建，禁止混用两场战斗的数据。
- 提供 `get_battle_summary_column_count()` 与 `get_battle_summary_side_indices()` 供自动化验证。

## 13. 世界扩建、地点层级与百科（阶段 8）

### 13.1 地图与区域

- `WorldContext.DEFAULT_WORLD_SIZE = Vector2(5000, 3000)`。
- 阶段 8 新增伯克纳尼亚与奥林两个王国区域，阶段 9 重新聚类全部地点（见 14.1）。
- `map_background.gd` 为每个地点绘制清空区，并绘制道路：青禾村通向两王国，各王国区域内部互相连通。
- 新地点与旧地点不重叠；所有地点 ID 唯一。

### 13.2 地点层级与所有权

| 类型 | 等级 | 绘制 | 是否可征召 |
|---|---|---|---|
| `VILLAGE` | 1 | 土墙 + 红屋顶 + 门洞 | 是 |
| `CASTLE` | 2 | 石墙 + 双塔 + 旗帜 | 否 |
| `TOWN` | 3 | 更大石墙 + 双屋顶 + 侧塔 | 否 |

- `SettlementIcon` 新增 `_draw_town()` 与 `TOWN_NAME_ANCHOR_RADIUS = 44`。
- 新地点通过 `owner_house_id` / `owner_noble_id` / `family_id` 归属家族。
- 地点面板显示政治所有者家族/王国，并按 `owner_noble_id` 或家族领袖判断征召授权。

### 13.3 百科入口

- 顶栏 `百科` 按钮（`EncyclopediaButton`）打开屏幕空间百科面板。
- 打开/关闭遵循 `ui_panel` 暂停原因栈，不改变相机。
- 详细规则见 [Encyclopedia_System.md](Encyclopedia_System.md)。

### 13.4 悬浮政治信息

- 部队悬浮签名包含 `leader_noble_id` 与 `family_id`。
- 悬浮详细模式追加 `PartyHoverPolitics`：贵族名称、爵位、家族。
- 底部玩家信息追加“身份：家族 · 爵位”。

## 14. 地点区域化布局与部队旗帜放大（阶段 9）

### 14.1 地点布局

阶段 9 只调整坐标与表现，不改变地点 ID、名称、类型、归属、家族、交互配置或村庄征召；世界尺寸仍为 5000×3000。

| 区域 | 地点 | 坐标 |
|---|---|---|
| 伯克纳尼亚王国（上部） | 墨西西（村庄） | (2500, 700) |
| | 伯克纳尼亚（城镇） | (2900, 750) |
| | 北境村（村庄） | (2250, 1000) |
| | 伯克纳（村庄） | (3200, 1000) |
| 中立缓冲（西侧中部） | 青禾村（玩家村庄） | (1600, 1500) |
| 奥林王国（下部） | 奥林德斯堡（城堡） | (2950, 1850) |
| | 奥林（村庄） | (3250, 2050) |
| | 巴里（村庄） | (2600, 2100) |
| | 灰石城堡（城堡） | (2900, 2350) |

布局约束（由 `world_map_layout_test` 验证）：

- 同王国地点最大两两距离 ≤ 1100；两王国质心间距 600–1800，保留势力间隔。
- 巴里家族封地（巴里/灰石城堡）与墨西西家族封地（墨西西/北境村）各自跨度 ≤ 500，并靠近所属王国区域。
- 任意两个地点间距 ≥ 250，避免图标、名称标签与点击判定互相干扰。
- 全部地点距地图边界 ≥ 120，摄像机 0.5x–2x 下均可到达；点击判定仍使用 `SETTLEMENT_CLICK_RADIUS = 45` 世界像素，不随布局改变。

家族骑士、国王卫队与巡逻点同步移动到对应区域；AI 行为类型和巡逻规则不变。`map_background.gd` 的清空区与道路使用同一组坐标。

### 14.2 部队内部旗帜放大

- `PartyMarkerStyle.flag_max_size` 由 30 调整为 38；`marker_radius` 仍为 18，`border_width` 仍为 2。
- 家族旗帜贴图为 48×48 画布，有效像素约 30×36；38 使等比缩放后的有效旗帜接近内圆（半径 16），同时保持原画布纵横比并居中。
- 旗帜仍由 `map_flag_circle.gdshader` 圆形遮罩裁剪；`get_flag_clip_uv_radius()` 按实际半径计算，圆形底盘、边框、点击/悬浮区域、地图位置与移动动画均不变。
- 无旗帜纹理时的回退三角形仍限制在内圆内（半宽不超过 `inner_radius * 0.62`），不会因旗帜放大而越出圆形。

## 15. 行动悬浮、战斗摘要、自由镜头与攻击确认（阶段 10）

### 15.1 部队悬浮“行动：XXX”

- `PartyHoverPanel` 新增 `PartyHoverActivity` 行，每次悬浮时从 `PartyData` 运行时字段推导，UI 只读。
- 优先级与文本：
  - `battle_response_id` 有效 → `行动：正在前往战场`；
  - 领主 `RECRUITING` 或前往征召地点 → `行动：正在前往征召：<地点>`；
  - 攻击意图/追击焦点 → `行动：正在追击：<部队>`；
  - `FOLLOW_PARTY` 且目标敌对 → 追击，否则 `行动：正在跟随：<部队>`；
  - 移动中前往地点 → `行动：正在前往：<地点>`；
  - `PATROL` 移动/静止 → `行动：正在前往巡逻区域` / `行动：正在附近巡逻`；
  - 其余 → `行动：暂无行动`。
- 意图变化后再次悬浮立即刷新；Alt 仍展开兵种构成，展开/收起不修改 AI 或部队状态。
- 名称缺失时回退为通用文本，不报错。

### 15.2 AI 对 AI 战斗摘要仅悬浮显示

- 战斗摘要面板默认隐藏；鼠标悬浮对应 `BattleMarker` 时显示该战斗按 `side_index` 分列的部队与兵种汇总。
- 悬浮另一场战斗时切换摘要；离开标记或战斗结束立即清空/隐藏。
- 面板不拦截地图点击、拖动与快捷键；战斗标记仍负责参战部队图标隐藏与汇总入口。

### 15.3 WASD 自由镜头

- 相机模式分为 `FOLLOW_PLAYER` 与 `FREE_CAMERA`；WASD 或方向键平移时进入自由镜头。
- 平移速度按当前缩放换算为世界距离，并 clamp 到世界边界，避免移出地图。
- 新的玩家移动指令、点击跟随玩家或重新锁定玩家时切回 `FOLLOW_PLAYER`。
- 缩放与数字键 1/2/3 行为不变；UI 面板打开时 WASD 被屏蔽。
- 战斗场景相机不受影响；镜头模式为运行时状态，不进入存档（KI515）。

### 15.4 玩家主动攻击二次确认

- 玩家点击敌对部队“发起战斗”时只打开确认面板，文本包含目标部队名，不立即创建战斗。
- 取消关闭确认并返回原对话，不改变世界时间、暂停倍率、部队状态或战斗注册表。
- 确认时重新校验玩家/目标有效性、战斗占用、关系与距离；条件失效则显示原因并关闭确认。
- 加入友军既有战斗显示“加入战斗”，不弹主动攻击确认。
- 所有创建/加入仍走 `BattleManager` 统一入口，重复确认不会产生第二场战斗。

### 15.5 部队旗帜进一步放大

- `PartyMarkerStyle.flag_max_size` 38 → 44；`marker_radius` 18、`border_width` 2 不变。
- 仍按贴图画布等比缩放并居中，圆形遮罩裁剪四角；点击/悬浮判定、人数显示与移动动画不变。
- 视觉可读性与边框比例需非 headless 人工验收（KI516）。
