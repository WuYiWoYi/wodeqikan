# 我的骑砍 · 项目总索引

**文档版本：** V0.36（2026-11-24 记忆整理）
**引擎：** Godot 4.6.1 / GDScript
**当前阶段：** 阶段 13 及后续优化已完成（五级经验、俘虏价格、领主赎回）
**入口：** 每次任务先读仓库根目录 [CLAUDE.md](../CLAUDE.md)（核心记忆）；本文件是稳定事实与文档索引。
**源规划：** [2D 中世纪沙盒战略游戏核心架构设计与开发规划 V0.2](../md/2D%20中世纪沙盒战略游戏核心架构设计与开发规划.md)（只读）

---

## 1. 项目一句话

一款纯 2D 的中世纪沙盒战略游戏：玩家在大地图上带兵、战斗、经营关系，而世界在玩家不操作时也持续运转。

## 2. 已确认的基础决策

| 项目 | 决策 |
|---|---|
| 大地图视角 | 俯视平面，部队在 XY 平面移动 |
| 小场景视角 | 横版侧视 + 纵深移动（Y 轴表示前后），按 Y 排序 |
| 攻击朝向 | 武器攻击判定支持 360°；人物贴图仍左右镜像，默认朝左 |
| 静态配置 | Godot `Resource`（`Data/**/*.tres`） |
| 运行时实体 | `RefCounted` 纯数据类（`UnitData`、`PartyData` 等） |
| 存档 | JSON，带 `schema_version`（当前 v10），只保存持久化数据 |
| 世界时间 | 固定步长 0.1 秒，由 `TimeManager` 统一推进 |
| 全局单例 | 仅 5 个 Autoload：`EventBus`、`TimeManager`、`SaveManager`、`SceneManager`、`GameManager` |
| 代码规范 | 静态类型 GDScript；标识符英文，注释与文档中文 |
| 版本管理 | Git，私有远程 [WuYiWoYi/wodeqikan](https://github.com/WuYiWoYi/wodeqikan) |

> 已确认规则与“暂定/待确认”规则的区分、冲突判断顺序见 [CLAUDE.md](../CLAUDE.md) 第 5 节。

## 3. 架构速览

```text
Autoload（全局，仅 5 个）
├── EventBus        事实广播
├── TimeManager     WorldTime 固定步长 tick / 暂停栈
├── SaveManager     JSON 存档读写
├── SceneManager    表现场景切换
└── GameManager     会话状态、WorldContext 生命周期

WorldContext（一局游戏，跨场景常驻；持有全部世界管理器）
└── WorldSimulation（只消费 world_tick，按固定顺序推进世界）

表现层（Scenes / UI / UnitVisual / 大地图图标）
└── 只读 WorldContext 数据，通过 EventBus 监听事实，不回写权威数据
```

管理器职责、依赖方向、数据权威、更新管线与事件契约见 [01_Core_Architecture.md](01_Core_Architecture.md)。本文件不复制管理器清单，避免两处失同步。

## 4. 文档地图

### 核心与规范

| 文档 | 读取级别 | 职责 |
|---|---|---|
| [../CLAUDE.md](../CLAUDE.md) | 每次任务 | 核心记忆：硬约束、读取流程、冲突规则、文档更新规则 |
| `00_Project_Index.md`（本文件） | 需要时 | 稳定基础决策、文档导航 |
| [01_Core_Architecture.md](01_Core_Architecture.md) | 架构相关任务 | 分层、依赖方向、更新管线、数据权威、事件契约 |
| [03_Design_Conventions.md](03_Design_Conventions.md) | 编写/修改代码或文档时 | 命名、GDScript、数据、场景、UI、AI、测试规范 |

### 系统专题（按任务选读，不必全读）

| 领域 | 文档 |
|---|---|
| 世界、时间、场景 | [World_Map_System.md](Systems/World_Map_System.md)、[Time_System.md](Systems/Time_System.md)、[Scene_System.md](Systems/Scene_System.md) |
| 单位、部队、雇佣兵 | [Unit_System.md](Systems/Unit_System.md)、[Party_System.md](Systems/Party_System.md)、[Mercenary_System.md](Systems/Mercenary_System.md) |
| 战斗、伤兵/俘虏、玩家被俘、领主赎回 | [Combat_System.md](Systems/Combat_System.md)、[Wounded_Prisoner_System.md](Systems/Wounded_Prisoner_System.md)、[Captivity_System.md](Systems/Captivity_System.md)、[Lord_Ransom_System.md](Systems/Lord_Ransom_System.md) |
| AI、政治层级、领主 | [AI_System.md](Systems/AI_System.md)、[Political_Hierarchy_System.md](Systems/Political_Hierarchy_System.md)、[Lord_System.md](Systems/Lord_System.md) |
| 地点、村庄、封地、冒险者 | [Settlement_System.md](Systems/Settlement_System.md)、[Village_System.md](Systems/Village_System.md)、[Fief_Recruitment_System.md](Systems/Fief_Recruitment_System.md)、[Adventurer_Recruitment_System.md](Systems/Adventurer_Recruitment_System.md) |
| 经济、马匹、补给 | [Inventory_Economy_System.md](Systems/Inventory_Economy_System.md)、[Mount_System.md](Systems/Mount_System.md)、[Supply_System.md](Systems/Supply_System.md) |
| 对话、日志、百科、存档 | [Dialogue_System.md](Systems/Dialogue_System.md)、[World_Log_System.md](Systems/World_Log_System.md)、[Encyclopedia_System.md](Systems/Encyclopedia_System.md)、[Save_System.md](Systems/Save_System.md) |

### 开发状态与历史

| 文档 | 读取级别 | 职责 |
|---|---|---|
| [Development/Current_Status.md](Development/Current_Status.md) | 依赖当前进度时 | 当前阶段、已实现/未实现、下一步、当前风险、测试状态 |
| [Development/Known_Issues.md](Development/Known_Issues.md) | 评估限制/风险时 | 未决问题、实现缺口、技术风险、已解决索引 |
| [Development/Technical_Decisions.md](Development/Technical_Decisions.md) | 需要设计原因时（按 D 编号检索） | 技术决策记录（ADR） |
| [Development/Test_Commands.md](Development/Test_Commands.md) | 运行测试时 | 单测/系统测试/跨进程/视觉探针命令 |
| [02_Development_Roadmap.md](02_Development_Roadmap.md) | 规划/验收时（非默认） | 阶段目标、历史任务与验收记录；当前缺口以 `Current_Status` 为准 |
| [04_Change_Log.md](04_Change_Log.md) | 追溯变更时（非默认） | 重要变更历史 |
| [Archive/Status_History.md](Archive/Status_History.md) | 追溯阶段细节时（非默认） | 阶段 1–13 的详细实现、测试清单与手动验收步骤 |

## 5. 每次开发的标准流程

1. 读 [CLAUDE.md](../CLAUDE.md)；用第 4 节表格选 1–2 份专题文档。
2. 若任务依赖当前进度，读 `Current_Status.md`；若涉及已知限制，读 `Known_Issues.md`。
3. 只读直接相关代码 3–5 个，必要时做一轮精确符号搜索；确认改动范围后停止探索。
4. 写出本次改动的接口、数据结构与验收方式，并按 L1–L4 说明将运行和明确不运行的测试。
5. 实施后更新对应系统文档；状态变化覆盖更新 `Current_Status.md`，重要变更追加到 `04_Change_Log.md`；最后检查本索引与链接。

规则：禁止不同 Markdown 文件长期保存互相矛盾的设计。冲突处理见 [CLAUDE.md](../CLAUDE.md) 第 5 节。

## 6. 当前状态

- 当前阶段：阶段 13 及后续地图操作/雇佣兵美术与独立招募/装备管理/招募经济/战败清理/玩家被俘与逃脱已完成；存档 Schema v10。
- 已实现能力、明确未做项、当前风险与测试状态的**唯一权威位置**是 [Development/Current_Status.md](Development/Current_Status.md)；本索引不维护状态快照，避免与状态文档失同步。

## 7. 文档权威性

- `Docs/` 是唯一持续维护、作为开发依据的文档体系；`md/` 下的 V0.2 规划保持只读。
- 当前实现状态以 `Docs/Development/Current_Status.md` 为准；历史细节以 `Docs/04_Change_Log.md` 与 `Docs/Archive/` 为准。
- 如果源规划与 `Docs/` 冲突：先找出原设计意图，再在 `Technical_Decisions.md` 记录变更原因，最后同步修改相关文档与代码。
- 文档之间的冲突判断顺序与状态标记见 [CLAUDE.md](../CLAUDE.md) 第 5 节。

## 8. 常用命令

```bash
# 无头导入
Godot_v4.6.1-stable_win64.exe --headless --path . --import

# 运行单个测试（测试清单以 Tests/ 目录为准）
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/<name>.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/<name>.tscn
```

跨进程存档、手动视觉探针与测试枚举命令见 [Development/Test_Commands.md](Development/Test_Commands.md)。
