# 核心架构

**文档版本：** V0.5
**状态：** 阶段 7 第一步已实现并通过全量自动化测试

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
    ├── ItemManager（消耗品静态配置）             │
    ├── MarketManager（村庄/城镇市场与交易）       │
    ├── SupplyManager（每日补给结算）              │
    ├── WoundedHealingManager（伤兵小时治疗）      │
    ├── PrisonerTradeManager（酒馆出售俘虏）       │
    ├── PartyManager                              │
    ├── SettlementManager                         │
    ├── NobleManager（贵族，继承 LordManager）     │
    ├── HouseManager（家族）                       │
    ├── KingdomManager（王国）                     │
    ├── LordManager（领主/封地归属，兼容入口）      │
    ├── FiefRecruitmentManager（采邑征召）         │
    ├── AdventurerRecruitmentManager（候选人）     │
    ├── FactionManager（阵营关系）                 │
    ├── FamilyRegistry（家族视觉配置，只读）        │
    ├── SettlementEconomyConfig（经济参数，只读）   │
    ├── VisionManager（视野查询）                  │
    ├── WorldMapManager（移动/跟随）               │
    ├── EncounterManager（统一遭遇/中途参战）      │
    ├── WorldLogManager（世界事件日志）             │
    ├── AIManager                                 │
    ├── BattleManager                             │
    ├── DialogueManager                           │
    ├── PlayerProfile（金币/物品，随存档）         │
    └── WorldSimulation ←──────────────────────────┘
```

### 3.1 为什么把 WorldManager 拆成 WorldContext + WorldSimulation

源规划中的 `WorldManager` 同时承担“容器”和“调度”两件事。本项目拆成：

- `WorldContext`：数据与管理器的生命周期容器，不写玩法逻辑；
- `WorldSimulation`：只消费 `world_tick`，按固定顺序推进世界数据。

这样大地图场景未加载时，只要世界时间未被暂停，`WorldSimulation` 仍可运行。屏幕内战斗会压入 `battle` 暂停原因冻结世界；NPC 对 NPC 的离屏战斗保持世界正常运行，由 `BattleManager.tick()` 每游戏小时结算一次伤亡，期间允许第三方加入。世界可同时存在多场 AI 离屏战斗，`BattleManager` 用 `active_battles` / `party_battle_lookup` 独立管理；`current_battle` 仅表示玩家当前屏幕战斗。

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
| `UnitManager` | `UnitData` 增删查、按配置生成单位、等级/装备/坐骑/晋升/属性重算 | 单位 AI、场景表现 |
| `ItemManager` | `ItemConfig` 静态注册与查询（消耗品/杂物） | 持有数量、玩家背包写操作 |
| `MarketManager` | 村庄/城镇商品注册、独立库存、马匹实例交易、交易校验与原子结算、市场库存序列化 | 持有玩家背包/金币、操作 UI、决定是否采购（AI 决策） |
| `SupplyManager` | 按 `TimeManager` 日边界统一结算玩家/NPC 面包与草料、剩余天数与采购需求查询 | 市场交易、价格计算、路线决策、UI |
| `WoundedHealingManager` | 按 `WorldTime` 整小时生成治疗点、按成员顺序治疗、恢复伤兵状态与仅伤兵部队 | 战斗内 HP、补给、工资、UI |
| `PrisonerTradeManager` | 城镇酒馆出售俘虏的校验、集中定价、原子结算与售出状态写入 | 直接修改 Unit 状态、UI 预览逻辑 |
| `BattleManager`（阶段 13 扩展） | 负伤判定、俘虏池构建、最大余数分配、玩家份额挂起与原子提交 | UI 直接写入俘虏归属 |
| `PartyManager` | `PartyData` 增删查、成员关系维护、工资汇总 | 部队 AI |
| `SettlementManager` | `SettlementData` 增删查、场景路径与序列化 | 地点图标、交互面板 |
| `LordManager` | `LordData` 增删查、玩家领主查询、部队引用校验、序列化 | AI 决策、封地分配、UI |
| `NobleManager` | `NobleData` 增删查、爵位/宗主/领袖/国王校验、独立部队绑定、领袖死亡选举 | 家族/王国聚合决策、UI |
| `HouseManager` | `HouseData` 增删查、领袖/贵族/封地成员关系、家族按旗帜映射 | 王国战争决策、UI |
| `KingdomManager` | `KingdomData` 增删查、统治家族/国王/附庸、敌对关系、战争传播 | 外交 UI、战役指挥 |
| `FactionManager` | 阵营与政治身份的统一关系查询（敌对/友好/中立） | 修改家族/王国数据 |
| `FiefRecruitmentManager` | 封地归属校验、采邑储备/补充、成组征召、资源成本、税收缓存 | UI、场景节点、世界日志 |
| `AdventurerRecruitmentManager` | 村庄候选人池、刷新、1 金币招募、离开清理 | UI、场景节点、AI |
| `SettlementEconomyConfig` | 采邑/税收/候选人参数（只读） | 单个地点运行时状态 |
| `FamilyRegistry` | `FamilyConfig` 只读注册与查询（旗帜/罩袍/缨饰） | 外交、成员关系、战斗；家族不进入存档 |
| `AppearanceConfig` | 士兵外观随机池（等级头盔、罩袍概率） | 运行时单位状态；选择结果写入 `UnitData.appearance` |
| `DialogueManager` | `DialogueData` 会话与节点跳转 | UI 排版、条件/效果 |
| `PlayerProfile` | 金币、物品数量（玩家部队共享背包） | 场景节点、装备槽位；装备写操作仍经 `UnitManager` |
| `WorldMapManager` | 部队坐标、目标、移动、跟随 | 图标节点、UI、遭遇判定 |
| `EncounterManager` | 统一遭遇判定、玩家追击/被动拦截、战斗创建/加入委托 | 场景表现、UI 排版 |
| `WorldLogManager` | 监听事件、生成受限日志历史、序列化预留 | 修改战斗/部队、操作 UI |
| `AIManager` | 三层决策调度 | 直接改场景、UI |
| `BattleManager` | 多场 `BattleSession` 注册表、部队唯一参战归属、锁定、独立推进与结算 | 直接修改大地图节点；把 `current_battle` 当作世界唯一战斗 |
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
│           ├── WorldMapManager.update_visibility（视野由 VisionManager 提供）
│           ├── FiefRecruitmentManager.tick（采邑储备补充）
│           ├── AdventurerRecruitmentManager.tick（候选人刷新）
│           ├── EncounterManager 遭遇检测 / 中途参战
│           └── AIManager.tick（按内部分频；待处理遭遇/交互时跳过）
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
| `UnitData` 身份、等级、经验、工资、装备、归属 | `UnitManager` / `PartyManager` | 招募、升级、晋升、转队、上下马都走管理器 |
| `UnitData.current_hp`（非战斗） | `UnitManager`（战斗结算时由 `BattleManager`） | 战斗期间不得由世界侧修改 |
| 玩家金币 / 物品数量 | `PlayerProfile`（经 `UnitManager` 装备/晋升接口配合扣减） | 场景与 UI 不得直接改字段 |
| `SettlementData.scene_path` | `WorldInitializer` / 存档恢复 | 场景只读取，不修改地点数据 |
| `PartyData.world_position`、`target_position`、移动状态 | `WorldMapManager` | 其他系统只读 |
| `PartyData.member_unit_ids` | `PartyManager` | 与 `UnitData.current_party_id` 双向一致 |
| `PartyData.battle_state` | `BattleManager` | 锁定/解锁；全员阵亡→DISABLED |
| `PartyData.control_type` / `party_kind` | `WorldInitializer` / 存档恢复（`PartyManager.apply_runtime_defaults()`） | 运行时只读；AI 调度只看 `control_type`，表现与配置按 `party_kind` 取 |
| `PartyData.ai_type` / `ai_route_settlement_ids` | `WorldInitializer` | 运行时只读，不靠部队名称判断行为 |
| `PartyData.ai_route_index` | `AIManager` | 到达路线点后推进下一步索引 |
| 遭遇原因与待处理遭遇 | `EncounterManager` | UI 只读 `get_pending_encounter_reason()`，离场规则由 `can_leave_encounter()` 统一判定 |
| `LordData` 目标与状态 | `AIManager` / 领主 AI | 通过明确方法 |
| `SettlementData.owner_lord_id` | `WorldInitializer` / 存档恢复 / 未来的领地系统 | UI 与征召只读 |
| `SettlementData` 采邑储备/计时、人口/繁荣度、税收缓存 | `FiefRecruitmentManager` | 征召与 `WorldSimulation` 调用；UI 只读 |
| `SettlementData.adventurer_candidates` / 刷新计时 | `AdventurerRecruitmentManager` | 村庄表现只读；离开时清理 |
| 封地征召/候选人招募权限 | `FiefRecruitmentManager` / `AdventurerRecruitmentManager` | 场景与 UI 只调用接口 |
| `SettlementData` 驻军 | `SettlementManager` / 未来的战斗系统 | 地点交互只读 |
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
  │     ├── 玩家领主 / NPC 领主 / 家族归属
  │     └── 五个初始地点（含玩家村庄“青禾村”）
  └── SceneManager.change_scene(WorldMap)
```

读档使用同一条恢复路径：

```text
Continue / Load Game
  → SaveManager.load_game(slot)
  → GameManager 创建新的 WorldContext
  → WorldContext.load_from_save_data(save)
      ├── 恢复 IdGenerator 计数
      ├── 恢复 Unit / Party / Lord / Settlement / WorldLog
      ├── 恢复世界 ID、尺寸、玩家部队、玩家领主与玩家角色 ID
      ├── 修正采邑/候选人边界并重算属性与税收
      └── 校验成员关系、领主引用与封地所有权
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
大地图接近 AI 部队
  → 部队对话面板（push_pause ui_panel）
  → 玩家选择“发起战斗”
      → BattleManager.start_battle()
          ├── 创建 BattleSession（battle_id）
          ├── 校验双方部队与存活士兵；每支部队不得已在其他战斗中
          ├── 写入 active_battles 与 party_battle_lookup
          ├── 参战部队 battle_state = IN_BATTLE
          ├── 生成 BattleUnitState（battle_hp = current_hp）
          └── 玩家参与时 current_battle = session 且 push_pause(battle)
      → 场景控制器 SceneManager.change_scene(BattleScene)
  → 战斗结束
      → 场景控制器调用 BattleManager.finish_battle(battle_id, result)
          ├── 写回本场存活 HP
          ├── 移除本场阵亡单位的部队归属并删除 UnitData
          ├── 解锁本场参战部队
          ├── 只从 active_battles / party_battle_lookup 移除本场
          ├── 若为玩家屏幕战斗则清理 current_battle
          └── 玩家屏幕战斗时 pop_pause(battle)
      → 场景控制器 SceneManager.change_scene(WorldMap)
```

`WorldContext` 和 `WorldSimulation` 在战斗期间保持存在；屏幕内战斗通过 `battle` 暂停原因冻结世界模拟，战斗场景使用自身物理帧推进。AI 离屏战斗不暂停世界，也不写入 `current_battle`；它们与玩家屏幕战斗可同时存在，结束一场只清理自身。场景切换由场景控制器负责，`BattleManager` 只处理数据、推进与结算。

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
| `settlement_entered` | `settlement_id`, `party_id` | `WorldMap` | 世界日志 |
| `settlement_exited` | `settlement_id`, `party_id` | `VillageScene` | 世界日志 |
| `battle_started` | `battle_id` | `BattleManager` | UI、场景控制器、音频 |
| `battle_finished` | `battle_id`, `result` | `BattleManager` | UI、世界模拟 |
| `battle_participant_joined` | `battle_id`, `party_id`, `side_index` | `BattleManager` | UI、统计、后续战斗场景 |
| `party_reinforced` | `battle_id`, `party_id`, `noble_id`, `side_index` | `BattleManager`（`try_join_battle` / `add_reinforcement`） | 战斗场景增援表现、日志、统计 |
| `battle_participants_updated` | `battle_id` | `BattleManager` | 大地图战斗标记/汇总 UI |
| `entry_added`（WorldLogManager 自定义信号） | `WorldLogEntry` | `WorldLogManager` | 大地图世界日志面板 |
| `player_encounter_requested` | `encounter_id`, `attacker_party_id`, `target_party_id` | `EncounterManager` | WorldMap 强制遭遇对话 |
| `player_battle_interaction_requested` | `interaction_id`, `battle_id` | `EncounterManager` | WorldMap 加入/离开面板 |
| `unit_died` | `unit_id`, `party_id` | `BattleManager` / `UnitManager` | UI、统计 |
| `party_supply_changed` | `party_id`, `is_food_low`, `is_fodder_low` | `SupplyManager` | 大地图 UI、提示 |
| `npc_supply_purchased` | `party_id`, `bread_count`, `fodder_count` | `AIManager`（经 `MarketManager` 成功后） | 大地图部队图标浮字 |

规则：

- 新增信号必须同步更新本表。
- 事件参数使用 ID 或基础类型，不传节点。
- 不要用 `EventBus` 让 A 系统请求 B 系统执行动作。
- 高频事件（每个 tick 的位置变化）要么按需节流，要么由表现层轮询数据。

## 10. ID 与持久化

- 所有持久化实体必须有唯一 ID：`UNIT_000001`、`PARTY_000001`、`LORD_000001`、`SETTLEMENT_000001`、`FACTION_000001`。
- 政治实体使用固定语义 ID：`HOUSE_*`、`KINGDOM_*`；视觉家族配置使用 `FAMILY_*`，两者通过 `HouseData.banner_id` 映射。
- ID 只能由 `IdGenerator` 生成；计数器随存档保存，永不复用。固定 ID 由初始化器显式注册，重复注册必须拒绝。
- 马匹是独立实例：`MountInstanceData.instance_id` 全局唯一；旧存档迁移使用确定性 seed，保证重复读档不增殖、外观不漂移。
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
