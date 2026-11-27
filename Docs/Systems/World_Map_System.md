# 大地图系统

**所属层：** 玩法逻辑 / 表现
**核心脚本：** `Scripts/Systems/WorldMap/world_map_manager.gd`、`Scripts/UI/WorldMap/world_map.gd`
**大地图 UI 组件：** `map_overlay_registry.gd`（覆盖层登记与暂停计数）、`world_map_encyclopedia.gd`（百科）、`world_map_save_panel.gd`（存档）、`map_ui_kit.gd`（控件辅助）；由 `world_map.gd` 装配，控件名称与根公开方法保持兼容。
**场景：** `Scenes/WorldMap/world_map.tscn`
**状态：** 基础移动、NPC 自主商队/巡逻/强盗/治安队、统一 Party 数据、恢复原尺寸的圆形部队标记、放大的村庄圆形标记与位于上方的固定屏幕名称、部队跟随、视野查询、地点交互与村庄入口、底部 NPC 遭遇对话（领袖头像/对白/动态选项）、遭遇原因与敌对追击禁离开、玩家追击接触、追逐焦点保护、人数图标与悬浮信息、日期/时间段 UI、顶栏昼夜滚动窗口、按战斗 ID 独立的多战斗标记与多方战斗汇总、世界日志面板、封地信息与采邑征召入口、部队浮动提示、`WorldMapDefinition` 驱动的 7780×6615 重建地图（不规则边界/湖泊/山脉/道路、绿陆/蓝海/深蓝湖地表配色）与城镇图标、百科入口、地点区域化布局与部队内部旗帜放大、阶段 13 地点家族旗帜与停留部队旗帜条、统一最终移动速度显示、玩家移动目标标记与动态虚线、右侧纵向事件框与可操作事件详情弹窗、家族入口与家族面板、冒险者招募浮动提示、顶栏信息图标 2 倍放大、部队黑色基础描边与部队/建筑悬浮白色描边、玩家阵营部队绿/红外环与建筑名称绿/红半透明底板已实现

---

## 1. 职责

- 维护大地图坐标系与世界边界。
- 处理部队的目标设置、移动推进、跟随与到达判定。
- 向表现层提供可读取的部队位置。

不负责：图标节点、UI、战斗、AI 决策、视野关系判定（由 `VisionManager` 提供）、地形可通行性与路径求解（由 `WorldTerrain` 提供）。

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
| 速度 | `PartyData.movement_speed`（原始速度）；有效移速 = 原始 × 0.08，单位：世界像素 / 游戏秒 |
| 地图范围 | `WorldContext.world_size`；`WorldMapManager.world_bounds` 为同尺寸的矩形外框，仅用于传送/极端坐标兜底 |
| 可通行区域 | `WorldTerrain`：不规则边界内、湖泊与山脉之外（含 6 像素安全边距） |
| 存档格式 | `Vector2` 序列化为 `[x, y]`；`world_size` 随存档保存 |

新世界尺寸为 7780×6615（`WorldContext.DEFAULT_WORLD_SIZE`），由 `Data/WorldMap/world_map_definition.tres` 的参考尺寸 1556×1323 按 `reference_scale = 5` 推导。地图几何、地点参考坐标、道路与山脉全部保存在该 Resource 中；`WorldMapDefinition` 只做参考坐标 → 世界坐标换算，不保存运行时状态。旧存档的 `world_size`（如 5000×3000）继续按存档值读取，尺寸与定义不一致时不启用新地形，回退为矩形边界与直线移动（见第 20 节）。

摄像机支持跟随、方向键/WASD 平移和滚轮缩放（0.5x–2x）；缩放只改变表现层，数据坐标不变。1920×1080 下默认缩放为 1.5x；UI 位于 CanvasLayer，不受相机缩放影响。

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
- 治安队：`GUARD`，无威胁时按围绕驻地的四个 `ai_patrol_points` 循环，发现强盗后追击/拦截；
- 强盗：`BANDIT`，无目标时沿配置路线游荡，发现敌对目标后追击；
- AI 每 1 世界秒决策一次；移动仍由 `WorldMapManager` 执行。

### 3.1.1 玩家速度、输入与跟随

- 新游戏玩家部队移动速度：原始 450，有效 36 世界像素/游戏秒（×0.08）。
- 治安队：原始 300（有效 24）；强盗：250（有效 20）；商队：200（有效 16）。速度关系为治安队 > 强盗 > 商队。
- 旧存档通过 `PartyData.movement_speed` 保留原速度，读档不会按新常量重置。
- 顶部数字键 `1` / `2` / `3` 分别暂停 / 1x / 2x；小键盘不响应，echo 不重复触发。
- UI 面板打开时快捷键和地图点击都被屏蔽；地图点击只经 `_unhandled_input`，UI 控件自行消费的点击不会落到地图。
- 地图左键采用单击/双击判定：第一次点击先等待 `MAP_CLICK_DOUBLE_WINDOW`（0.28 秒）；
  - 窗口内、`MAP_CLICK_DOUBLE_DISTANCE`（18 像素）内再次点击：视为双击，只下达一次移动/跟随指令，并把基础倍率切为 2x；
  - 窗口内点击不同位置：先补发第一次单击，再开始新的判定窗口；
  - 窗口结束仍未双击：按单击执行，成功后基础倍率切为 1x；
  - 两种操作都不清除任何暂停原因；窗口期间打开面板或进入战斗转换时，待处理单击直接丢弃。
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

### 3.1.3 玩家到达自动暂停

- `WorldMapManager` 在部队真正到达移动/跟随目标时广播 `EventBus.party_arrived(party_id)`；该信号只表示“到达事实”，不直接修改时间。
- `WorldMap` 只对玩家部队响应：把基础倍率设为暂停（`SPEED_PAUSED`）。NPC 到达不会暂停世界。
- 只在到达时暂停，不会在设置目标或移动途中暂停。
- 重新下达移动/跟随指令后，旧目标不再产生到达事件，因此不会误触发暂停；到达地点后仍按第 5 节打开地点面板。
- 暂停原因栈中的其他暂停保持不变；玩家从暂停/1x/2x 任一状态出发，到达后都进入暂停。

### 3.1.4 暂停提示

- 顶栏下方居中显示琥珀色（`#D97706`）半粗体 `WorldPausedTip`（文本“已暂停”），带深色描边保证浅色地图可读。
- 可见性直接读取 `TimeManager.get_effective_world_scale()`：实际有效倍率为 0 时显示，任意暂停原因（基础暂停、UI 面板、遭遇对话、战斗等）都算；恢复 1x/2x 后隐藏。
- 提示只读，不提供按钮，不改变时间状态。

### 3.2 推进

- 只有 `WorldSimulation.on_world_tick` 调用 `update_party_movement(fixed_delta)`。
- 已绑定 `WorldTerrain`（新地图）时沿 A* 折线逐段移动；直线本身可通行时折线只有首尾两点，表现与旧版直线移动一致。
- 路径按 `PATH_REFRESH_DISTANCE = 32` 世界像素的终点变化重新求解；路径是运行时缓存，不进入存档。
- 目标点位于湖泊/山脉/边界外时，先收敛到最近可通行点；完全无路可走时原地停止，绝不退化为穿山直线。
- 到达阈值 2 像素；到达后精确对齐目标，置 `IDLE`，清理 `current_order`。
- 每 tick 移动距离 = `get_effective_movement_speed(party) * fixed_delta`，即 `movement_speed * WORLD_MAP_SPEED_SCALE * fixed_delta`。
- 大地图暂停或倍率变化时，tick 本身被 `TimeManager` 控制，移动逻辑不感知倍率。
- 未绑定地形的旧存档/测试世界保持直线移动，目标点和每 tick 的下一位置经过矩形 `world_bounds` clamp。

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

### 3.5 目标点标记与动态虚线（纯表现）

实现：`Scripts/Systems/WorldMap/move_target_guide.gd`（`MoveTargetGuide`），由 `world_map.gd` 的 `MoveTargetGuide` 子节点承载。

- 不新增移动状态：只读取 `PartyData.target_position`、`current_order`、`movement_state` 与 `current_target_id`。
- `movement_state == MOVING` 时显示；抵达（`IDLE`）、`stop_party()`、战斗切换或部队不可用时清除。
- 普通移动的终点为 `target_position`；`FOLLOW_PARTY` 时终点取被跟随部队的最新位置。
- 连线起点使用玩家图标的显示位置（`_player_icon.position`），因此与图标插值同步；目标点保持世界坐标。
- 节点固定在世界原点，绘制使用世界坐标，镜头平移/缩放不会改变目标点数据坐标。
- 虚线、线宽、标记半径与滚动速度按 `camera.zoom` 换算，保持稳定的屏幕视觉尺寸与速度。
- 反复点击地图只更新同一个表现节点，不累积旧标记。

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
- 悬浮部队或建筑时同时显示白色描边，见 11.6；
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
- 顶栏水平中心是昼夜窗口 `DayNightClock`；世界时间文本紧贴其左侧显示，金币与移速在左侧独立显示，见 18.1–18.3。
- 倍率仍显示暂停 / 1x / 2x。

### 4.5 顶栏昼夜窗口

- 组件：`Scripts/UI/WorldMap/day_night_clock.gd`，在 `world_map.gd::_build_top_bar()` 中创建为 `DayNightClock`。
- 美术：直接复用 `UI_昼夜.png`（96×48，左半 48×48 白天、右半 48×48 黑夜），不修改原始文件。
- 遮罩：`Control` 正方形窗口，边长 36（顶栏 48 高、上下边距 6 后的内容高度），`clip_contents = true` 裁切越界美术；美术按 48→36 等比缩放，不拉伸变形，最近邻采样。
- 循环：以 96 像素为周期重复绘制纹理；相位 0~1 时最多两份即可覆盖窗口，离开左侧的美术从右侧立即接续，无空白与跳变。
- 时间映射：相位 = `fposmod(世界累计秒 / 48 - 0.5, 1)`（1x 下 48 世界秒 = 1 游戏日），等价于一天中从正午起算的比例。
  - 12:00 → 纹理偏移 0，完整白天；
  - 18:00 → 偏移 24，昼夜交接；
  - 次日 00:00 → 偏移 48，完整黑夜；
  - 06:00 → 偏移 72，夜昼交接；
  - 次日 12:00 → 偏移 96 折回 0，循环闭合。
- 驱动：`_update_time_ui()` 在 `world_time_changed` / `world_speed_changed` 时调用 `DayNightClock.set_world_seconds(TimeManager.world_elapsed_seconds)`；不逐帧累加、不使用现实时间计时器。暂停时世界累计秒不变，窗口自然停住；倍速与读档由同一值直接换算。
- 测试接口：`get_scroll_phase()`、`get_texture_offset_pixels()`，供 `main_map_info_test` 校验各时刻、跨午夜、暂停、倍速与读档位置。

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
          ├── 基础倍率按地图点击规则切为 1x / 2x
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
- 玩家或 NPC 成功招募冒险者时，`EventBus.adventurers_recruited` 复用同一 `PartyIcon.show_floating_text()` 显示“招募了 N 个兵种”；文本由实际兵种与数量生成，只显示成功结果。
- 详细规则见 [Fief_Recruitment_System.md](Fief_Recruitment_System.md) 与 [Adventurer_Recruitment_System.md](Adventurer_Recruitment_System.md)。

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

- 地形速度系数与道路加成（当前道路只影响绘制，不改变移动速度）。
- 多选部队与军团移动。
- 视野遮挡与探测。
- 动态地形或可破坏障碍。

## 9. 实现状态

| 项 | 状态 |
|---|---|
| `world_bounds` 与目标 clamp | 已实现（矩形兜底；新地图实际由 `WorldTerrain` 约束） |
| `set_party_target` | 已实现 |
| `update_party_movement` | 已实现（A* 折线/到达/不可通行收敛） |
| 不规则地图边界、湖泊、山脉不可通行 | 已实现（`WorldTerrain`，玩家与 NPC 共用） |
| 显式灰色虚线道路 | 已实现（`WorldMapDefinition.roads`，绘制时经 A* 绕行） |
| 旧存档矩形地图兼容 | 已实现（尺寸不匹配时回退直线移动与旧绘制） |
| `stop_party` | 已实现 |
| `update_visibility` | 保留空实现；实际查询由 `VisionManager` 提供 |
| NPC 商队往返 / 治安队巡逻 | 已实现（AIManager） |
| 强盗游荡 / 动态目标评分 / 追击 | 已实现（AIManager + VisionManager） |
| 治安队发现/拦截强盗 | 已实现（威胁商队优先） |
| 玩家接近中立部队对话 | 已实现（底部 NPC 对话 + 领袖头像） |
| 统一 AI 遭遇判定 | 已实现（`EncounterManager`，距离 50，攻击意图） |
| 遭遇原因与选项规则 | 已实现（ENEMY_PURSUIT 不允许离开；PLAYER_INITIATED 保留离开） |
| 玩家被主动拦截遭遇对话 | 已实现（`encounter_dialogue`，底部对白 + 动态选项） |
| 统一圆形部队标记 | 已实现（所有部队共用 PartyIcon/PartyMarkerStyle/圆形旗帜遮罩，半径 18、旗帜最大边长 48） |
| 村庄圆形标记与名称 | 已实现（村庄单独放大 32/76，城堡不变；名称固定在标记正上方） |
| AI 对 AI 离屏战斗 | 已实现（每游戏小时结算伤亡，最多 48 小时） |
| 玩家追击同向移动敌军 | 已实现（`focus_party_id` 作为追击意图，接触后立即停止） |
| 玩家接近离屏战斗交互 | 已实现（加入/离开面板，独立暂停原因） |
| 多战斗标记 + 多方汇总 UI | 已实现（按 `battle_id` 独立标记，按 `side_index` 分组，实时人数） |
| 玩家中途加入离屏战斗 | 已实现（加入已有战斗，不重复创建） |
| `battle_started` 自动进入战斗场景 | 已实现（玩家参与时） |
| 玩家部队跟随目标部队 | 已实现（0.5 世界秒刷新） |
| 时间快捷键 1/2/3 | 已实现（顶部主键区） |
| 地图单击 / 双击 | 已实现（单击 1x、双击 2x，双击只下达一次指令） |
| 点击地图后切 1x | 已实现（不清除暂停原因） |
| 玩家到达自动暂停 / 已暂停提示 | 已实现（只响应玩家到达；提示读取有效倍率） |
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
| 部队上方浮动提示 | 已实现（`PartyIcon.show_floating_text`，成功后显示“招募了N组采邑”或“招募了N个兵种”） |
| 家族入口与面板 | 已实现（顶栏 `FamilyButton`；部队/封地实时只读，点击封地定位） |
| 中立/无关部队不自动弹窗 | 已实现（只对主动点击目标打开普通对话） |
| AI 主动追击才自动遭遇 | 已实现（实际追击关系 + 敌对判定 + 单次触发） |

## 10. 待确认

- 遭遇阈值是否按双方视野决定（当前统一固定 50 世界单位）。
- 离屏自动战斗的时长、平衡与随机性。
- 玩家加入离屏战斗时是否允许手动选择战斗侧（当前按阵营关系自动确定）。
- 战斗交互面板是否扩展“观察/离开并继续移动”等选项。
- 遭遇对话是否继续扩展谈判/缴赎等选项（当前为战斗 + 按原因动态生成的离开选项；ENEMY_PURSUIT 不允许离开）。
- 地点到达是否需要在移动中途显示目标高亮或路径指示（当前只显示普通移动）。
- 道路是否应提供移动速度加成（当前只影响绘制与路线观感）。

## 11. 圆形部队标记、村庄标记与统一速度（阶段 6 新增）

### 11.1 圆形部队标记（恢复原尺寸）

- `PartyIcon` 是所有部队类型唯一的圆形标记组件：圆形底盘、边框、旗帜、下方人数。
- 尺寸、边框、旗帜最大边长、人数偏移与阵营回退色集中在 `PartyMarkerStyle`（`Data/WorldMap/party_marker_style.tres`）。
- 标准半径 18、边框 2、旗帜最大边长 48（阶段 6 为 30，阶段 9 放大到 38，后续调到 44、52、60，最终调回 48）、人数偏移 24；圆形底盘与人数偏移保持原尺寸。
- 旗帜来自 `PartyData.banner_texture_path`，为空时回退 `FamilyConfig.banner_texture_path`；无家族色时按阵营读取回退色。
- 旗帜遮罩半径 = `PartyMarkerStyle.get_flag_clip_radius()` = 黑色描边内缘（`get_outline_outer_radius() - outline_width`，当前 16.25）；`PartyIcon` 将其除以旗帜精灵缩放后交给 shader 的局部像素正圆模式。旗帜因此填满圆内有效区域，但任何放大都不会盖住黑色描边。
- 玩家、家族、商队、强盗、治安队使用同一节点与同一套绘制逻辑；玩家标记额外显示外圈高亮。
- 基础黑色描边由 `PartyMarkerStyle.outline_color/outline_width` 控制（当前黑色 / 2.5）：外缘锁定为加粗前位置 `get_outline_outer_radius() = marker_radius + 0.75 = 18.75`，加粗部分全部向圆内扩展（内缘 16.25）；不改变标记最外侧轮廓、整体视觉尺寸、地图位置、点击或悬浮判定。
- 悬浮白色描边由 `hover_outline_*` 控制（当前白色 / 3.0，位于基础描边外侧 4.0）；悬浮时与黑色基础描边同时保留，由 `WorldMap._update_hover_outline()` 统一切换。
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

### 11.4 统一大地图速度倍率与移速基准

- `WorldMapManager.WORLD_MAP_SPEED_SCALE = 0.08`（2026-11-27 大地图重建后，配合放大 5 倍的世界坐标与行程标定；同日时间流速改为 1x 下 2 世界秒 = 1 游戏小时）。
- 所有部队（玩家、商队、巡逻、强盗、家族骑士）都经过 `update_party_movement()`，在该唯一入口乘一次 0.08。
- `PartyData.movement_speed` 保存原始基础速度，不写回、不重复缩放；有效移速 = 原始速度 × 0.08。
- 2026-11-27 移速基准由 20 调整为 30：全体部队当前速度 ×1.5；NPC 原始速度统一 ×5/2（相对最初配置：商队 80→200、巡逻 120→300、强盗 100→250、家族骑士 110→275），相对差异与排序保持不变。
- 玩家按需求单列：原始速度 300→450，有效移速 24→36，不参与 ×5/2 换算。
- 小地图/战斗中的 `UnitData.move_speed` 与 `StatCalculator` 不受影响。
- 旧存档部队读取原有 `movement_speed` 后按当前统一倍率移动，不按新常量重置。

### 11.5 新部队

- 每个 NPC 家族一支骑士部队（`<家族简称>骑士`，如巴里骑士、墨西西骑士、伯克纳骑士），由该家族领袖指挥；当前共 18 支。六方势力的统治者家族部队名称见 `Political_Hierarchy_System.md`。
- 两支强盗：东路强盗、荒野强盗，沿用 BANDIT 阵营与 AI，拥有独立出生点与路线。
- `WorldInitializer` 只在新游戏创建时生成；读档不调用初始化，不会重复生成。

### 11.6 悬浮描边（部队与建筑）

- 鼠标悬浮目标由 `WorldMap._update_hover_outline()` 每帧统一识别：先用 `_find_party_within(PARTY_HOVER_RADIUS = 30)`，无部队时再用 `_find_settlement_at()`（`SETTLEMENT_CLICK_RADIUS = 45`）；同一时刻最多高亮一个目标，部队优先于建筑。
- 部队：`PartyIcon.set_hovered(true)` 只增加白色描边，不改变位置、尺寸、绘制层级或点击判定；基础黑色描边保留。
- 建筑：`SettlementIcon.set_hovered(true)` 沿村庄/城镇/城堡原有几何边缘绘制 5 像素白色描边，再由建筑填充覆盖内侧一半；不改变名称标签、家族徽章、布局与点击进入功能。
- 鼠标离开目标、打开模态 UI 或战斗切换时立即清除；描边使用世界坐标绘制，随地图缩放与移动自然同步。
- 部队图标注册在 `_party_icons`，地点图标注册在 `_settlement_icons`；`_set_hover_outline()` 负责清除旧目标并设置新目标，避免多个无关目标同时高亮。

### 11.7 圆形几何一致性与图集 UV 陷阱（2026-11-27 修复）

- 圆形主体、黑色描边、玩家外圈与悬浮白色描边全部在 `PartyIcon` 的局部坐标中用 `draw_circle` / `draw_arc` 绘制；相机缩放由 `_set_camera_zoom()` 始终设置 `Vector2(z, z)`，`WorldEntities` 与图标节点没有附加缩放，因此 0.5x / 1x / 2x 下均保持正圆且同心。
- 旗帜遮罩使用 `map_flag_circle.gdshader` 的 `use_local_circle` 模式：`vertex()` 通过 `varying vec2 local_position` 传入画布局部像素坐标，`fragment()` 按 `circle_center = (0, 0)` 与 `circle_radius = get_flag_clip_radius() / sprite.scale` 裁剪。遮罩与主体/描边共用同一圆心和半径基准，与旗帜宽高比、父节点缩放无关。
- 根因：`TextureRegion.get_trimmed_texture()` 返回 `AtlasTexture`；canvas shader 的 `UV` 是**整张图集**坐标（实测旗帜图集归一化范围约 u=0.188–0.813、v=0.125–0.875），不是有效贴图的 0–1。旧实现直接按 `UV - 0.5` 计算圆形遮罩，把遮罩拉伸成椭圆并放大到约 52×43 世界像素，覆盖黑色描边并溢出圆形标记。修复后旗帜严格限制在半径 16.25 的正圆内。
- shader 保留原 UV 模式（默认 `use_local_circle = false`）供地点家族徽章等既有调用；本次未修改建筑徽章（KI546）。

## 12. 地点原始美术、徽章名称组合与悬浮 Alt（阶段 6 后续）

### 12.1 三个独立元素

| 元素 | 层级 | 职责 |
|---|---|---|
| `SettlementIcon` | 世界层（`world_entities`） | 原始村庄/城镇/城堡美术，统一按 `BUILDING_ART_SCALE = 1.5` 放大绘制；节点位置、节点缩放与点击判定不变 |
| `SettlementNameTag` | 屏幕 UI 层（`SettlementNameLayer`） | 固定 240×36 的徽章 + 名称组合 |
| `SettlementNameTag.FamilyBadge` | 名称组合内部 | 左侧圆形家族徽章，颜色来自 `FamilyConfig` |

- 世界层不再绘制圆形村庄标记或旗帜，也不再携带名称。
- 名称组合整体位于地点世界坐标转换后的屏幕位置上方，按 `SettlementIcon.get_name_anchor_radius()` × 相机缩放 + 10 屏幕像素定位。
- 建筑美术放大 1.5 倍只作用于 `SettlementIcon` 自身绘制几何（含地面阴影与悬浮描边轮廓），贴图/名称底板/家族徽章/交互提示等 UI 尺寸不变；描边线宽保持 5 像素。名称锚点半径同步 ×1.5，保证名称仍贴在放大后的建筑顶部上方。
- 建筑世界坐标、节点 `scale`、点击/悬浮判定半径与所有权逻辑均不变。
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

- 当前 `WorldContext.DEFAULT_WORLD_SIZE = Vector2(7780, 6615)`；阶段 8 时期的 5000×3000 仅作为旧存档尺寸保留兼容。
- 阶段 8 新增伯克纳尼亚与奥林两个王国区域，阶段 9 重新聚类全部地点；2026-11-27 大地图重建后，地点布局与势力范围以 `WorldMapDefinition` 为准（见第 20 节）。
- 新地图由 `map_background.gd` 按定义绘制不规则边界、灰色虚线道路、湖泊与山脉；旧存档尺寸不匹配时继续绘制旧矩形草地、河流与道路。
- 新地点与旧地点不重叠；所有地点 ID 唯一。

### 13.2 地点层级与所有权

| 类型 | 等级 | 绘制 | 是否可征召 |
|---|---|---|---|
| `VILLAGE` | 1 | 土墙 + 红屋顶 + 门洞 | 是 |
| `CASTLE` | 2 | 石墙 + 双塔 + 旗帜 | 否 |
| `TOWN` | 3 | 更大石墙 + 双屋顶 + 侧塔 | 否 |

- `SettlementIcon` 新增 `_draw_town()` 与 `TOWN_NAME_ANCHOR_RADIUS = 44`。
- 新地点通过 `owner_house_id` 归属家族；`family_id` 只决定视觉旗帜。
- 地点面板显示所有者家族/王国，并按请求者家族是否等于 `owner_house_id` 判断征召授权。

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

> **已过时（2026-11-27）：** 本节的 5000×3000 世界与 9 个地点坐标已被大地图重建取代。当前世界尺寸、61 个地点坐标、道路与地形以 `Data/WorldMap/world_map_definition.tres` 为准，详见第 20 节。下表仅保留作阶段 9 历史记录，不再代表当前实现。

阶段 9 只调整坐标与表现，不改变地点 ID、名称、类型、归属、家族、交互配置或村庄征召；当时世界尺寸为 5000×3000。

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

阶段 9 当时的布局约束（已随大地图重建失效，仅作历史记录）：

- 同王国地点最大两两距离 ≤ 1100；两王国质心间距 600–1800，保留势力间隔。
- 巴里家族封地（巴里/灰石城堡）与墨西西家族封地（墨西西/北境村）各自跨度 ≤ 500，并靠近所属王国区域。
- 任意两个地点间距 ≥ 250，避免图标、名称标签与点击判定互相干扰。
- 全部地点距地图边界 ≥ 120，摄像机 0.5x–2x 下均可到达；点击判定仍使用 `SETTLEMENT_CLICK_RADIUS = 45` 世界像素，不随布局改变。

家族骑士、国王卫队与巡逻点同步移动到对应区域；AI 行为类型和巡逻规则不变。`map_background.gd` 的清空区与道路使用同一组坐标。

### 14.2 部队内部旗帜放大

- `PartyMarkerStyle.flag_max_size` 由 30 调整为 38；`marker_radius` 仍为 18，`border_width` 仍为 2。
- 家族旗帜贴图为 48×48 画布，有效像素约 30×36；38 使等比缩放后的有效旗帜接近内圆（半径 16），同时保持原画布纵横比并居中。
- 旗帜仍由 `map_flag_circle.gdshader` 圆形遮罩裁剪（当前实现见 11.7）；圆形底盘、边框、点击/悬浮区域、地图位置与移动动画均不变。
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

- `PartyMarkerStyle.flag_max_size` 38 → 44 → 52 → 60 → 48（最终）；`marker_radius` 18、`border_width` 2 不变。当前值以 `Data/WorldMap/party_marker_style.tres` 为准。
- 仍按贴图画布等比缩放并居中，圆形遮罩裁剪四角；点击/悬浮判定、人数显示与移动动画不变。
- 旗帜遮罩改裁到黑色描边内缘（半径 16.25），黑色描边由 1.5 加粗到 2.5 且只向圆内扩展；描边外缘保持 18.75，标记最外侧轮廓与整体视觉尺寸不变。
- 视觉可读性与边框比例需非 headless 人工验收（KI516）。

## 16. 地点家族旗帜与停留部队旗帜条（阶段 13）

### 16.1 地点标记家族旗帜

- `SettlementNameTag` 的圆形徽章优先读取 `SettlementData.family_id` 对应的 `FamilyConfig`：存在家族时显示家族旗帜与主色。
- 地点没有家族归属时，继续使用原有建筑美术与名称，不生成空白徽章。
- 每帧检查 `tag.get_bound_family_id()` 与当前 `settlement.family_id`，归属变化后重建徽章，避免继续显示旧家族旗帜。
- 名称标签整体忽略鼠标；底板只包裹“徽章 + 名称”内容，尺寸随内容变化，不改变地点点击/悬浮判定。
- 圆形徽章使用 `CLIP_CHILDREN_AND_DRAW`：父节点自身的圆形底盘与边框必须绘制，同时把旗帜裁进圆内；使用 `CLIP_CHILDREN_ONLY` 会隐藏底盘，只剩图标与名称。

### 16.2 地点下方停留部队旗帜条

- `SettlementStationedBar` 位于地点名称层，按地点独立创建、独立显隐。
- 每支停留部队显示一个家族旗帜徽章，**不绘制圆形底盘**；多个旗帜从左到右排列，单行超过 `MAX_ROW_WIDTH` 后自动换行并居中。
- 停留判定只看**当前世界坐标**与建筑距离（`STATIONED_PARTY_RADIUS`），不看移动目标；移动中、战斗中、无成员或不可用部队不算停留。
- 停留部队从大地图普通圆形标记中隐藏，旗帜条出现；离开范围、解散、转移、被摧毁或恢复可移动后，圆形标记恢复、旗帜条对应条目移除。
- 多支部队按 `party_id` 稳定排序，保证旗帜顺序可复现；不同地点的旗帜条互不合并。
- 旗帜纹理优先取 `PartyData.banner_texture_path`，否则回退家族旗帜；缺失纹理时回退为颜色/默认图形。
- 只读表现层：`WorldMap` 每帧根据 `PartyManager` 与 `BattleManager` 数据重建条目，不修改权威部队状态。

### 16.3 旗帜非透明区域裁切（阶段 13 后续）

- 地点家族徽章、部队圆形标记、停留部队旗帜条、百科房屋徽章与战斗增援旗帜统一通过 `TextureRegionUtils.get_trimmed_texture()` 在运行时按 PNG 非透明像素边界裁切，不改动源美术。
- 旗帜缩放、圆形遮罩与布局尺寸基于裁切后的有效区域计算；`map_flag_circle.gdshader` 的 `uv_aspect` 按有效宽高比设置，保证圆形徽章不变形、不丢边缘像素。
- 裁切结果按资源路径缓存；同一贴图只在首次使用时计算一次。

### 16.4 城镇酒馆与独立出售界面（阶段 13 后续）

- 酒馆菜单嵌入原 `SettlementPanel` 的 `SettlementTavernHost`，切换时只改变 `SettlementInfoView` 与酒馆内容的可见性；窗口位置、尺寸与 `ui_panel` 暂停原因保持不变。
- 嵌入的 `TavernPanel` 只负责菜单与意图转发；点击“招募雇佣兵”发出 `mercenary_recruit_requested`，点击“出售俘虏”发出 `sell_requested`，都不在城镇面板内部展开子视图。
- `WorldMap` 收到雇佣兵请求后隐藏城镇面板，打开独立的 `MercenaryRecruitPanel`（列表 + 真实 `UnitVisual` 预览）；关闭后恢复城镇信息面板，不重新嵌入酒馆。
- `WorldMap` 收到请求后隐藏城镇面板，打开独立的 `PrisonerSalePanel`（`TavernPanel` 的独立窗口 + 遮罩，`open_sale()` 直接进入出售视图）。
- 独立界面复用同一套俘虏列表、价格和 `PrisonerTradeManager` 结算；关闭后恢复城镇信息面板并刷新金币/背包显示，世界保持暂停。
- 关闭地点、进入村庄或切换地点时调用两个面板的 `reset()` 清理出售预览与选中状态；`reset()` 不广播 `closed`，避免收尾阶段误切视图。

## 17. 统一最终移动速度显示（阶段 13）

- `WorldMapManager.get_effective_movement_speed(party)` 是大地图最终速度的唯一读取入口，返回 `party.movement_speed * WORLD_MAP_SPEED_SCALE`。
- 玩家信息栏与所有部队（玩家/NPC）的悬浮面板都调用该入口，显示格式统一为 `移动速度：%.1f`。
- 显示与实际移动使用同一数据来源；部队停止、待命或战斗中仍显示当前最终速度，不显示 0 或隐藏该行。
- 悬浮内容为只读，不修改移动速度、装备或 AI 状态；速度相关配置变化后悬浮面板自动刷新。
- 新节点名：悬浮行 `PartyHoverSpeed`，供自动化测试读取。

## 18. 顶栏金币/移速、事件中心与建筑面板权限（阶段 13 后续）

### 18.1 顶栏布局

- 顶栏内容分为 `TopBarLeft`、`TopBarCenter`、`TopBarRight` 三个锚定区域。
- `DayNightClock` 固定在顶栏精确水平中心（36×36）；`WorldTimeLabel` 位于 `TopBarCenter` 内、右对齐并紧贴昼夜窗口左侧，左右区域新增内容不会推离中心。
- 左侧显示三个“图标 + 数值”条目：`MoneyLabel`（金币）、`PartySpeedLabel`（部队移速）、`PartySizeLabel`（部队人数），以及纯文本 `PlayerHpLabel`（当前控制角色的 `current_hp/max_hp`）；右侧保留暂停/1x/2x/事件/部队/家族/背包/百科/保存/主菜单。
- 每个条目由 `<标签名>Entry` 容器、`<标签名>Icon` 与 `<标签名>` 数值标签组成，图标统一 40×40（原 20×20 的 2 倍，等比缩放）、字号 15、条目间距 12、图标与数值间距 6；左侧区域加宽到 360，避免挤压时间与右侧入口。
- 数值不再带“金币：/部队移速：/部队人数：”文字前缀，只显示数量。
- 顶栏入口使用紧凑尺寸（52×30、字号 13），在 1280 宽度下不与中间时间区域重叠。
- 视口宽度小于 1400 时，居中时间文本降到字号 11；时间与倍率文本保持完整。视口尺寸变化通过 `size_changed` 立即重排。

### 18.2 金币、移速与部队人数实时显示

- 金币每帧读取 `PlayerProfile.gold`；购买、征召、工资与税收变化后下一帧更新。
- 移速每帧调用 `WorldMapManager.get_effective_movement_speed(party)`，与其他悬浮/移动结算共用同一入口。
- 部队人数每帧统计玩家部队成员：`可战斗`（`UnitData.is_alive()`）+ `伤员`（`UnitData.is_wounded()`）；永久死亡与俘虏不计入。
- 生命值每帧读取 `WorldContext.get_player_unit()` 的真实 `UnitData`，显示 `生命 <current>/<max>`；被俘恢复与逃脱后同一帧刷新，不读取 UI 缓存或占位值。
- 使用图标：`UI_金币.png`、`UI_移速.png`、`UI_人数.png`，路径集中在 `world_map.gd` 顶部常量；HP 使用同字号纯文本。

### 18.3 悬浮提示与 ALT 明细

- 悬浮事件挂在每个 `<标签名>Entry` 容器上，图标与数值子节点忽略鼠标；移入图标或数值任意位置都显示同一提示，移出条目关闭。
- 悬浮金币简述显示 `预计每日收入：<带符号净额>`；数据来自 `WorldContext.get_daily_balance_preview()`。
- `get_daily_balance_preview()` 复用现有缓存：`PartyManager.get_total_wage()` 与玩家封地 `SettlementData.tax_income_per_day`，不另写经济公式。
- 按住 ALT 时切换为明细：`每日收支`、`总计`、逐项 `标签 + 带符号金额`；无项目时显示空状态。
- 悬浮移速简述显示 `当前部队移速：%.1f`；ALT 明细来自 `WorldMapManager.get_movement_speed_breakdown(party)`，包含基础移速、大地图移动系数与最终移速，最终值复用实际有效移速。
- 悬浮部队人数显示标题 `部队`，随后为 `可战斗人数`、`伤员`、`俘虏`；数据分别来自成员真实状态与 `PartyData.prisoner_unit_ids`，互不重复统计。
- ALT 松开立即恢复简述；鼠标移出关闭提示。ALT 处理集中在 `world_map._input()`，与地点悬浮 Alt 共用 `set_alt_detail_active()`。

### 18.4 主界面事件中心

- 顶栏 `EventCenterButton` 打开 `EventCenterOverlay`（`EventCenterPanel`）。
- `WorldContext.event_center` 是只读聚合层，事件来自现有系统状态：
  - 任务：当前无任务系统，保留 `QUEST` 入口并返回空；
  - 封地：玩家授权封地且采邑储备 > 0；
  - 补给：玩家部队面包/草料不足；
  - 伤兵：玩家部队存在伤兵；
  - 冒险者：村庄存在可招募候选人；
  - 赎回：`LordRansomManager` 中存在当前有效的家族赎回请求。
- 事件 ID 按“类型:来源 ID”确定性生成，重复打开不会创建重复事件；状态消失后事件自动从列表移除。
- 左侧按“已接取任务 / 待处理事项”分组，右侧显示与所选事件同源详情；面板不生成、不结算、不保存事件副本。

### 18.5 建筑信息面板打开时的 UI 权限

- 建筑信息面板（地点面板）打开时，仍可使用百科、部队、家族、背包、事件中心等普通功能入口。
- 这些入口使用 `_has_open_modal(true)` 判断，忽略地点面板自身的阻塞；其他覆盖层之间仍互相阻塞。
- 世界时间控制使用 `_has_open_modal(false)`：地点面板或任意覆盖层打开时，暂停/1x/2x 按钮与快捷键均不可用。
- 关闭百科/部队/背包/事件后，地点面板保持打开、世界保持暂停、时间按钮保持禁用；离开地点后按钮恢复可用。
- `TimeManager.push_pause/pop_pause` 按暂停原因计数，嵌套界面关闭不会提前恢复世界时间。

### 18.6 右侧纵向事件框与详情弹窗（阶段 13 后续）

- `EventFeed` 固定在大地图右侧（宽 280、上偏移 60、最大高度 430），纵向可滚动。
- 只展示 `EventCenter.get_actionable_events()`；当前可操作事件为家族赎回/赎买请求，后续类型可复用同一入口。
- 有事件时显示“待处理事件”、数量与条目摘要（`[赎回]` 或 `[赎买]` + 标题 / 领主 · 家族 · 赎金）；没有可操作事件时整体隐藏，不占地图空间。
- 事件框出现在顶栏下方，避开右侧顶栏按钮与地点面板；显示与滚动不暂停世界时间。
- 点击条目发出 `event_selected(event_id)`，由 `WorldMap` 打开 `EventDetailDialog`；事件框本身不结算规则。
- `EventReminder` 是右侧居中的小型提醒，只显示“有新的事件待处理（N）”：
  - 可见性与数量来自同一个 `EventCenter.get_actionable_events()`；
  - 有事件时持续显示，玩家忽略时不会消失，也不暂停世界；
  - 点击时唯一事件直接打开详情，多条事件打开事件中心；
  - 不创建第二套事件数据，不重复触发提醒。
- 详情弹窗显示标题、领主、家族、赎金与正文；出售赎回提供“取消/接受赎金”，关押期赎买提供“拒绝/接受赎金”。
- “取消”只关闭弹窗；“拒绝”调用 `LordRansomManager.reject_captive_ransom()` 结束当前事件。
- 弹窗打开时压入暂停原因并禁用时间控制；每帧重新读取事件中心，事件失效时立即关闭，事件框与提醒同一帧刷新。
- 弹窗、事件框与提醒都只读取当前世界状态，不缓存创建时的事件副本。

### 18.7 家族入口与家族面板

- 顶栏 `FamilyButton` 打开 `FamilyOverlay`（`FamilyPanel`），与事件中心一样是屏幕空间覆盖层。
- 打开时压入 `GameManager.PAUSE_REASON_UI_PANEL` 并禁用时间控制；关闭或点击封地后弹出同一暂停原因，恢复原时间倍率，不修改时间逻辑。
- 面板标题显示玩家家族名；没有家族时显示“暂无家族”与空状态。
- 部队页（默认）：每次刷新从 `HouseManager.get_house_nobles()` 读取家族存活/死亡贵族，排除玩家本人；状态按实时单位与部队数据推导为正常/被俘/战斗中/已阵亡；被俘或无部队时显示“暂无部队”，不展示过期部队信息。
- 封地页：按村庄/城镇/城堡分组，数据来自 `SettlementData.owner_house_id == 玩家家族`；不包含其他家族或盟友的封地，所有权变更后下一帧刷新。
- 点击封地条目调用 `focus_settlement_on_map()`：进入自由镜头并对准该地点，同时关闭面板；不修改地点数据。
- 面板只读实时实体状态，不在 UI 内缓存成员或封地列表；详细字段来源见 [Political_Hierarchy_System.md](Political_Hierarchy_System.md)。

## 19. 玩家被俘状态与镜头（2026-11-25）

### 19.1 左侧被俘面板

- 节点：`CaptiveStatusPanel`（PanelContainer），包含 `CaptiveTitleLabel`、`CaptiveCaptorLabel`、`CaptiveHpLabel` 与提示文本。
- 可见性只读取 `WorldContext.captivity_manager.is_player_captive()`；普通状态隐藏，不占地图空间。
- 押送部队名称来自 `captivity_manager.get_captor_party_id()` → `PartyManager.get_party()`；HP 来自真实玩家 `UnitData`。
- 面板不是模态窗口，不压入暂停原因；被俘期间暂停/1x/2x 仍可切换。

### 19.2 镜头与地图表现

- 被俘期间 `_update_camera()` 强制跟随押送部队，忽略自由镜头；逃脱后 `is_player_captive()` 为 false，镜头自动回到玩家部队。
- 玩家部队战斗图标在被俘期间隐藏；押送部队正常显示。
- 玩家部队处于 `DISABLED`，但 `open_party_panel()` 允许在被俘时查看，面板只读，不能重新获得控制权。
- `_update_player_info()` 在玩家状态栏显示“被俘中”。

### 19.3 输入与 UI 权限

- 被俘时玩家不能在大地图下达移动/攻击指令；`_has_open_modal()` 不因被俘面板而阻塞普通入口。
- 部队/家族/背包/百科/事件中心等普通入口保持可用；时间按钮只在真正的模态面板打开时禁用。
- 所有显示只读取 `CaptivityManager` 与实体数据，不在 UI 内结算恢复或逃脱。

## 20. 大地图重建与地形寻路（2026-11-27）

### 20.1 唯一数据源

| 内容 | 位置 |
|---|---|
| 参考图尺寸与缩放 | `Data/WorldMap/world_map_definition.tres`：`reference_size = (1556, 1323)`、`reference_scale = 5.0` |
| 世界尺寸 | `WorldMapDefinition.get_world_size()` = 7780×6615；`WorldContext.DEFAULT_WORLD_SIZE` 与之一致 |
| 地点（61 个） | `settlements`：`key`、中文名、类型、参考像素坐标、视觉家族 |
| 道路（46 条） | `roads`：只保存显式端点对；不自动补边 |
| 不规则边界（46 点） | `boundary_points` |
| 湖泊（11 点） | `lake_points` |
| 山脉（5 座） | `mountains`：中心、长短半轴、旋转角 |
| 时间标定 | `calibration_reference_distance = 86.2`、`calibration_travel_hours = 5.8`（1x 下 2 世界秒/游戏小时、移速基准 30）、`world_map_speed_scale = 0.08` |

- 参考图像素坐标乘 `reference_scale` 得到世界坐标；`WorldMapDefinition` 只做换算，场景与运行时实体不保存参考图坐标。
- 世界坐标画布足够容纳全部地点与标签；不再使用阶段 9 的 5000×3000 坐标表。
- 61 个地点 = 36 村庄 + 8 城镇 + 17 城堡；地点 ID 由 `IdGenerator` 生成，存档持久化。

### 20.2 地区构成

- 地图按参考图分为西北、东北、中部、西南、东南与东南岛链等区域；六方势力分别为伯克纳王国、弗拉尼王国、洛里亚克王国、泰纳伯公国、瓦勒蒙联盟与瓦伊拉伯国。
- 地点视觉旗帜由 `WorldMapDefinition.settlements[].family` → `FamilyConfig` 决定；政治所有权只由 `SettlementData.owner_house_id` 决定，两者刻意分离（例如灰石堡垒旗帜为伯克纳家族，所有权属于巴里家族）。
- 重建不从地图位置推断封地、战争或外交关系；59 处所有权全部来自 `WorldInitializer._family_specs()` 的显式 Settlement ID → 家族 ID 配置，塞洛斯要塞、巴达洛斯要塞无主。

### 20.3 地形与不可通行

- `WorldTerrain` 用 40×40 世界像素的 `AStarGrid2D` 网格回答“是否可通行”和“两点折线路径”。
- 不可通行：绿线边界外、湖泊内、山脉椭圆内；湖泊/山脉额外 6 像素安全边距。
- 玩家与 NPC 共用 `WorldMapManager` + `WorldTerrain`，不存在只限制玩家的特判。
- 目标落在不可通行区域时收敛到最近可通行点；没有可行路线时原地停止并清除移动状态，不退化为穿山直线。
- 地图绘制 `map_background.gd` 只读定义：整块世界先铺蓝色海洋（`#5a8fae`），边界多边形填充草地绿（`#a8c483`）并绘制深绿海岸线；陆地网格纹理经多边形裁切，只出现在陆地内部；湖泊填充比海洋更深的蓝色（`#3c7396`）；道路为深灰虚线，山脉为灰色椭圆。道路绘制同样经 A* 绕行。
- 海洋即 `WorldTerrain` 的边界外区域，湖泊即湖泊多边形，两者仍由既有地形判定限制通行；地表配色不参与、也不改变通行规则。

### 20.4 道路与时间标定

- 道路只来自 `roads` 的 46 条显式连接；59 个地点参与道路网络，塞洛斯要塞与巴达洛斯要塞没有显式道路，保持参考图状态。
- 最近地点对的世界距离约 415 像素；玩家实际速度 = 450 × 0.08 = 36 世界像素/游戏秒；1x 下 1 游戏小时 = 2 世界秒，因此约 5.8 游戏小时（现实约 11.5 秒）。移动速度未随时间流速调整。
- 道路当前不提供速度加成，只作为地图连接与视觉依据。

### 20.5 校验

`Tests/SystemTests/world_map_layout_test.gd` 自动验证：

- 世界尺寸 7780×6615、边界 ≥ 40 点、湖泊 ≥ 6 点、山脉 5 座、道路 46 条；
- 61 个地点名称/坐标唯一，全部位于边界内且不在湖泊/山脉中，任意两点间距 ≥ 250 世界像素；
- 边界外、湖泊中心、每座山脉中心均不可通行；目标收敛到可通行点；
- 穿越山脉的路线会绕行且全程可通行，无障碍路线保持两点直线；
- 最近地点对行程 5.77±0.6 游戏小时（现实约 11.5 秒），`WORLD_MAP_SPEED_SCALE == 0.08`；
- 17 个正式家族、6 王国、51 名 NPC 贵族（默认贵族身份下 52 名）、56 支部队、59 处家族所有权；六方势力名称/民族/统治家族/附庸正确且初始无战争；
- 地点引用到的家族旗帜资源存在，克里卡与伯克纳旗帜命名/引用正确。

### 20.6 旧存档兼容

- 读档以存档中的 `world_size` 为准；尺寸与当前定义不一致时不构建 `WorldTerrain`，`WorldMapManager` 回退为矩形 `world_bounds` clamp 与直线移动。
- `map_background.gd` 在尺寸不匹配时继续绘制旧矩形草地、河流与道路，避免旧地点坐标与新地形错位。
- 不重写旧存档的地点坐标、所有权或 `world_size`；迁移只在新开游戏时使用新定义。

## 21. 玩家阵营视觉反馈（2026-11-27）

### 21.1 部队持续阵营外环

- `PartyIcon` 通过 `set_player_relation(FactionManager.PlayerRelation)` 接收关系；不在图标内判断政治数据。
- 玩家本人部队：沿用原有蓝色外环（`PartyMarkerStyle.player_ring_color`），即使玩家加入王国也不被绿色覆盖。
- 同阵营：`allied_ring_color` 绿色；敌对：`hostile_ring_color` 红色；中立：不绘制阵营外环。
- 外环与原有蓝色外环共用同一绘制路径：半径 `marker_radius + 3`、线宽 2.5、`draw_arc` 正圆。不改变标记半径、旗帜缩放、人数位置、黑色基础描边、悬浮白色描边或点击/悬浮判定。
- 外环位于圆形主体外缘，不遮挡旗帜；悬浮只叠加原有白色描边，不删除阵营外环。

### 21.2 建筑名称底板颜色

- `SettlementNameTag.set_player_relation()` 只替换 `SettlementNameBackground` 的 `StyleBoxFlat.bg_color`。
- 中立：原 `BACKGROUND_COLOR`（黑色半透明）；同阵营：`ALLIED_BACKGROUND_COLOR` 绿色半透明；敌对：`HOSTILE_BACKGROUND_COLOR` 红色半透明。
- 透明度、圆角、边框、底板尺寸、徽章、名称字体/位置/布局与建筑美术均不变。
- 地点政治归属仍以 `SettlementData.owner_house_id` 判定，视觉旗帜 `family_id` 不参与阵营关系。

### 21.3 刷新机制

- `WorldMap` 在创建图标/名称标签时各读取一次关系。
- 订阅 `EventBus.faction_relations_changed` 后刷新全部部队与建筑，不每帧计算完整政治关系。
- 事件来源：玩家主动宣战、`KingdomManager.declare_war()/end_war()`、家族加入/离开王国。
- `_refresh_faction_visuals()` 是唯一的批量刷新入口；新增关系变化来源时应广播同一事件，而不是让 UI 自行推导。

### 21.4 测试

`Tests/SystemTests/player_faction_relation_ui_test.tscn` 覆盖：

- 初始玩家自有建筑绿色、中立建筑黑色、玩家蓝色外环、中立部队无外环；
- 玩家无王国时攻击王国 A 家族 → 家族及王国成员全部敌对、建筑红色、其他王国中立；
- 攻击独立家族 → 仅该家族敌对，不产生王国宣战；
- 玩家加入王国 → 同王国部队/建筑绿色，玩家蓝色外环保持；
- 王国战争 → 敌国成员部队红色；
- 主动攻击入口触发宣战与王国战争；
- 个人宣战记录随 `SaveData` JSON 往返恢复。
