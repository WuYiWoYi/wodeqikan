# 核心架构

**文档版本：** V0.4
**状态：** Milestone 1 已实现并通过端到端测试

本文定义全局结构、依赖方向与写权限。各系统的细节见 `Systems/`。

---

## 1. 架构原则与落地方式

| 原则 | 落地方式 |
|---|---|
| 大世界与小场景分离 | `WorldContext` 持有世界数据；场景只做表现 |
| 数据与表现分离 | 实体数据全部是 `RefCounted`，场景节点不得成为权威数据源 |
| 玩家与 AI 共用基础架构 | 玩家单位与 AI 单位共用 `UnitData`、`UnitController`、`UnitAI` |
| 统一时间管理 | 只有 `TimeManager` 推进 WorldTime；其他系统不得自建倍率 |
| 模块化低耦合 | 管理器只通过数据和明确接口通信，禁止跨层直接改字段 |
| 数据驱动 | 兵种、装备、阵营等静态数据使用 `Resource` 配置 |
| 长期扩展 | ID、存档字段、管理器接口预留扩展位；初期功能可以少，结构不能锁死 |

## 2. 分层

| 层 | 内容 | 可依赖 |
|---|---|---|
| 全局管理层 | `GameManager`、`TimeManager`、`SceneManager`、`SaveManager`、`EventBus` | 核心数据、管理器接口 |
| 世界会话层 | `WorldContext`、`WorldSimulation` | 数据实体、世界管理器 |
| 数据实体层 | `UnitData`、`PartyData`、`LordData`、`SettlementData`、`FactionData` | 仅 Godot 基础类型 |
| 玩法逻辑层 | `UnitManager`、`PartyManager`、`WorldMapManager`、`AIManager`、`BattleManager`、`FormationManager`、`DialogueManager` | 数据实体、事件总线 |
| 表现层 | 各 `Scene`、`UnitVisual`、大地图图标 | 只读数据、事件总线、UI 接口 |
| UI 层 | 菜单、部队面板、对话、地点面板 | `GameManager`、系统方法、事件总线 |

数据实体层不得反向依赖任何管理器或场景节点。

## 3. 运行时拓扑

```text
GameManager (Autoload)
├── TimeManager (Autoload) ── world_tick(0.1s) ──┐
├── SceneManager (Autoload)                       │
├── SaveManager (Autoload)                        │
├── EventBus (Autoload)                           │
└── WorldContext (Node，会话级，跨场景常驻)         │
    ├── IdGenerator                               │
    ├── UnitManager                               │
    ├── PartyManager                              │
    ├── SettlementManager                         │
    ├── WorldMapManager                           │
    ├── AIManager                                 │
    ├── BattleManager                             │
    ├── DialogueManager                           │
    └── WorldSimulation ←──────────────────────────┘
```

### 3.1 为什么把 WorldManager 拆成 WorldContext + WorldSimulation

源规划中的 `WorldManager` 同时承担“容器”和“调度”两件事。本项目拆成：

- `WorldContext`：数据与管理器的生命周期容器，不写玩法逻辑；
- `WorldSimulation`：只消费 `world_tick`，按固定顺序推进世界数据。

这样大地图场景未加载时（例如玩家正在战斗），世界模拟仍然可以照常运行。

### 3.2 全局单例约束

只允许 5 个 Autoload：

| 名称 | 脚本 | 约束 |
|---|---|---|
| `EventBus` | `Scripts/Autoload/event_bus.gd` | 只广播事实，不存业务状态 |
| `TimeManager` | `Scripts/Autoload/time_manager.gd` | 只懂时间，不懂士兵/部队 |
| `SaveManager` | `Scripts/Autoload/save_manager.gd` | 只做 JSON I/O，不修改世界 |
| `SceneManager` | `Scripts/Autoload/scene_manager.gd` | 只切换场景，不拿世界数据 |
| `GameManager` | `Scripts/Autoload/game_manager.gd` | 会话状态与生命周期 |

`UnitManager`、`PartyManager`、`AIManager`、`BattleManager` 等一律由 `WorldContext` 创建，不得新增 Autoload。

## 4. 管理器职责边界

| 管理器 | 负责 | 不负责 |
|---|---|---|
| `GameManager` | 游戏状态、创建/销毁 `WorldContext`、读档入口 | 具体玩法、场景内逻辑 |
| `TimeManager` | 世界倍率、暂停栈、固定步长 tick、游戏累计时间 | 任何实体逻辑 |
| `SceneManager` | 场景路径与切换 | 世界数据、节点内容 |
| `SaveManager` | JSON 文件读写、槽位列表 | 聚合存档、修改实体 |
| `EventBus` | 事实通知 | 请求-响应、业务决策 |
| `WorldContext` | 装配并持有管理器 | 帧循环、玩法决策 |
| `WorldSimulation` | 固定顺序推进世界 | 渲染、UI |
| `UnitManager` | `UnitData` 增删查、按配置生成单位 | 单位 AI、场景表现 |
| `PartyManager` | `PartyData` 增删查、成员关系维护 | 部队 AI |
| `SettlementManager` | `SettlementData` 增删查、序列化 | 地点图标、交互面板 |
| `WorldMapManager` | 部队坐标、目标、移动、视野 | 图标节点、UI |
| `AIManager` | 三层决策调度 | 直接改场景、UI |
| `BattleManager` | `BattleSession`、部队锁定、结算 | 直接修改大地图节点 |
| `DialogueManager` | 对话会话与节点跳转 | UI 排版 |
| `FormationManager` | 阵型定义与站位计算 | 单位攻击行为 |

## 5. 依赖方向

允许：

```text
UI → GameManager / 系统接口 / EventBus
Scene → WorldContext（只读）/ EventBus
SceneController → BattleManager / DialogueManager（通过明确方法）
Manager → Data
WorldSimulation → Manager
Manager → EventBus（只发事实）
```

禁止：

- `UnitData` 引用管理器、场景节点或 UI。
- UI 直接修改 `UnitData` / `PartyData` 字段。
- 场景节点直接改世界数据。场景只修改自己的本地表现状态。
- `AIManager` 直接操作 UI 或场景节点。
- `BattleManager` 直接找大地图节点并改坐标。
- 管理器之间新增隐式全局引用；依赖通过 `WorldContext` 显式装配。
- 使用 `get_node("/root/...")` 或跨场景节点路径通信。

## 6. 更新管线

```text
每一帧（真实时间）
├── TimeManager._process
│   └── 累积 WorldTime，每满 0.1 秒发出 world_tick
│       └── WorldSimulation.on_world_tick
│           ├── WorldMapManager.update_party_movement
│           ├── WorldMapManager.update_visibility / 遭遇检测
│           └── AIManager.tick（按内部分频）
│
├── WorldMapScene._process
│   └── 读取 PartyData，插值更新图标位置（只写表现）
│
├── BattleScene._physics_process
│   └── UnitController / UnitAI / BattleSession 临时状态
│
├── 小场景其他 Scene._physics_process
│   └── 场景内角色移动、交互
│
└── UI._process
    └── 使用真实帧时间，不受世界暂停影响
```

关键规则：

- 世界逻辑只认 `world_tick`，不认渲染帧。
- 表现可以每帧插值，但不得回写权威数据。
- `SceneTime` 不使用 `TimeManager` 的世界倍率。
- 不用 `Engine.time_scale`，不用 `get_tree().paused` 做游戏暂停。

详见 [Systems/Time_System.md](Systems/Time_System.md)。

## 7. 数据权威与单写者

| 数据 | 唯一写入者 | 备注 |
|---|---|---|
| `UnitData` 身份、等级、经验、装备、归属 | `UnitManager` / `PartyManager` | 招募、升级、转队都走管理器 |
| `UnitData.current_hp`（非战斗） | `UnitManager`（战斗结算时由 `BattleManager`） | 战斗期间不得由世界侧修改 |
| `PartyData.world_position`、`target_position`、移动状态 | `WorldMapManager` | 其他系统只读 |
| `PartyData.member_unit_ids` | `PartyManager` | 与 `UnitData.current_party_id` 双向一致 |
| `PartyData.battle_state` | `BattleManager` | 锁定/解锁 |
| `LordData` 目标与状态 | `AIManager` / 领主 AI | 通过明确方法 |
| `SettlementData` 归属、驻军 | `SettlementManager` / 未来的战斗系统 | 地点交互只读 |
| 世界时间、倍率 | `TimeManager` | 其他系统只能请求 |
| 战斗临时状态 | `BattleSession` | 结算后写回 `UnitData` |

任何新系统都必须先声明：它写哪些字段、通过谁写。禁止两个系统同时写同一权威字段。

## 8. 场景生命周期

### 8.1 新游戏

```text
MainMenu → GameManager.start_new_game()
  ├── 清理旧 WorldContext
  ├── TimeManager.start_session()（默认暂停 0 倍速）
  ├── 创建 WorldContext（装配管理器）
  ├── WorldInitializer.create_new_world()
  │     ├── 生成 WORLD ID、世界尺寸
  │     ├── 玩家部队 + 两支 NPC 部队
  │     └── 四个初始地点
  └── SceneManager.change_scene(WorldMap)
```

读档使用同一条恢复路径：

```text
Continue / Load Game
  → SaveManager.load_game(slot)
  → GameManager 创建新的 WorldContext
  → WorldContext.load_from_save_data(save)
      ├── 恢复 IdGenerator 计数
      ├── 恢复 Unit / Party / Settlement
      └── 恢复世界 ID、尺寸、玩家部队
  → TimeManager.restore_world_time(时间, 基础倍率)
  → SceneManager.change_scene(WorldMap)
```

### 8.2 大地图 ↔ 小场景

进入小场景：

1. `GameManager` 或场景控制器记录来源与返回方式。
2. 设置 `SceneTime` 运行；按规则压入暂停原因 `small_scene`，使 WorldTime 为 0。
3. `SceneManager` 切换到目标场景。
4. 场景从 `WorldContext` 读取实体数据生成表现节点。

离开小场景：

1. 收集需要保留的局部数据并写回对应管理器。
2. 释放场景表现节点。
3. 移除暂停原因。
4. 返回大地图并恢复时间规则。

### 8.3 大地图 ↔ 战斗

```text
大地图遭遇
  → BattleManager.start_battle()
      ├── 创建 BattleSession
      ├── 参战部队 battle_state = IN_BATTLE
      ├── 生成 BattleUnitState
      ├── TimeManager.set_battle_mode(true)（WorldTime = 0.5）
      └── SceneManager.change_scene(BattleScene)
  → 战斗结束
      → BattleManager.finish_battle()
          ├── 写回 HP / 死亡 / 经验 / 成员关系
          ├── 解锁参战部队
          ├── TimeManager.set_battle_mode(false)
          └── SceneManager.change_scene(WorldMap)
```

`WorldContext` 和 `WorldSimulation` 在战斗期间保持存在并继续运行。

### 8.4 返回主菜单

`GameManager.enter_main_menu()`：

1. 销毁 `WorldContext`。
2. 停止世界时间，清空暂停原因。
3. 切换主菜单场景。

## 9. 事件契约

`EventBus` 只广播已经发生的事实。命令一律走管理器方法。

| 信号 | 参数 | 触发者 | 典型订阅者 |
|---|---|---|---|
| `game_state_changed` | `int`（`GameManager.GameState`） | `GameManager` | UI、场景控制器 |
| `game_session_started` | 无 | `GameManager` | 音频、统计、场景 |
| `game_session_ended` | 无 | `GameManager` | 清理方 |
| `party_position_changed` | `party_id` | `WorldMapManager` | 大地图图标 |
| `party_battle_state_changed` | `party_id`, `battle_state` | `BattleManager` | 大地图图标、UI |
| `settlement_interaction_requested` | `settlement_id` | 大地图输入/交互 | 地点面板 |
| `battle_started` | `battle_id` | `BattleManager` | UI、音频 |
| `battle_finished` | `battle_id`, `result` | `BattleManager` | UI、世界模拟 |
| `unit_died` | `unit_id`, `party_id` | `BattleManager` / `UnitManager` | UI、统计 |

规则：

- 新增信号必须同步更新本表。
- 事件参数使用 ID 或基础类型，不传节点。
- 不要用 `EventBus` 让 A 系统请求 B 系统执行动作。
- 高频事件（每个 tick 的位置变化）要么按需节流，要么由表现层轮询数据。

## 10. ID 与持久化

- 所有持久化实体必须有唯一 ID：`UNIT_000001`、`PARTY_000001`、`LORD_000001`、`SETTLEMENT_000001`、`FACTION_000001`。
- ID 只能由 `IdGenerator` 生成；计数器随存档保存，永不复用。
- ID 不得依赖节点名、节点路径或数组下标。
- 数据类必须提供 `to_dict()` / `from_dict()`；字段名使用 snake_case。
- 存档只保存数据，不保存节点。详见 [Systems/Save_System.md](Systems/Save_System.md)。

## 11. 新增系统的接入检查表

1. 它属于哪一层？写哪些权威字段？
2. 是否需要 `WorldContext` 持有？是否真的需要 Autoload？
3. 输入来自哪里，输出去哪里？是否通过明确接口？
4. 它在 `world_tick`、物理帧、UI 帧中的哪一种频率运行？
5. 数据是否可序列化？是否需要 ID？
6. 场景未加载时它是否仍应运行？
7. 需要新增哪些 `EventBus` 事实？
8. 文档、当前状态、已知问题是否同步更新？

## 12. 文档冲突处理

1. 找出原设计与原因。
2. 明确本次变更动机与影响面。
3. 在 `Development/Technical_Decisions.md` 新增或更新决策记录。
4. 修改所有相关系统文档与代码。
5. 标记或删除失效规则，禁止长期并存。
6. 更新 `04_Change_Log.md`。

## 13. 与源规划 V0.2 的差异

| 源规划 | 本项目实现 | 原因 |
|---|---|---|
| `WorldManager` | `WorldContext` + `WorldSimulation` | 分离生命周期容器与 tick 调度 |
| 未明确视角 | 大地图俯视 + 小场景横版带纵深 | 匹配左右攻击与部件美术，同时支持阵型 |
| 未明确数据方案 | Resource + RefCounted + JSON | 编辑器可编辑、运行时轻量、存档透明 |
| `BattleManager` 独立于世界 | 由 `WorldContext` 持有 | 战斗需要读世界数据并在战斗后写回 |
| Autoload 5 个 | 保持不变 | 已足够，避免全局依赖膨胀 |
