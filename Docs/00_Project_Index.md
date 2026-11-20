# 我的骑砍 · 项目总索引

**文档版本：** V0.3（架构基线）
**更新日期：** 2026-11-20
**引擎：** Godot 4.6.1 / GDScript
**源规划：** [2D 中世纪沙盒战略游戏核心架构设计与开发规划 V0.2](../md/2D%20中世纪沙盒战略游戏核心架构设计与开发规划.md)

---

## 1. 项目一句话

一款纯 2D 的中世纪沙盒战略游戏：玩家在大地图上带兵、战斗、经营关系，而世界在玩家不操作时也持续运转。

## 2. 已确认的基础决策

| 项目 | 决策 |
|---|---|
| 大地图视角 | 俯视平面，部队在 XY 平面移动 |
| 小场景视角 | 横版侧视 + 纵深移动（Y 轴表示前后），按 Y 排序 |
| 攻击朝向 | 仅左右两个方向，默认朝左 |
| 静态配置 | Godot `Resource`（`Data/**/*.tres`） |
| 运行时实体 | `RefCounted` 纯数据类（`UnitData`、`PartyData` 等） |
| 存档 | JSON，带 `schema_version`，只保存持久化数据 |
| 世界时间 | 固定步长 0.1 秒，由 `TimeManager` 统一推进 |
| 全局单例 | 仅 5 个 Autoload：`EventBus`、`TimeManager`、`SaveManager`、`SceneManager`、`GameManager` |
| 代码规范 | 静态类型 GDScript；标识符英文，注释与文档中文 |
| 版本管理 | Git，私有远程 [WuYiWoYi/wodeqikan](https://github.com/WuYiWoYi/wodeqikan) |

## 3. 架构速览

```text
Autoload（全局）
├── EventBus        事实广播
├── TimeManager     WorldTime 固定步长 tick
├── SaveManager     JSON 存档读写
├── SceneManager    表现场景切换
└── GameManager     会话状态、WorldContext 生命周期

WorldContext（一局游戏，跨场景常驻）
├── IdGenerator
├── UnitManager
├── PartyManager
├── WorldMapManager
├── AIManager
├── BattleManager
├── DialogueManager
└── WorldSimulation  ← 消费 TimeManager.world_tick
```

完整依赖与写权限见 [01_Core_Architecture.md](01_Core_Architecture.md)。

## 4. 文档地图

### 顶层文档

| 文档 | 职责 |
|---|---|
| [01_Core_Architecture.md](01_Core_Architecture.md) | 分层、依赖方向、更新管线、数据权威、事件契约 |
| [02_Development_Roadmap.md](02_Development_Roadmap.md) | 阶段 0–7 的任务、依赖与验收标准 |
| [03_Design_Conventions.md](03_Design_Conventions.md) | 命名、代码、数据、场景、文档规范 |
| [04_Change_Log.md](04_Change_Log.md) | 重要变更历史 |

### 系统文档

| 文档 | 职责 |
|---|---|
| [Systems/World_Map_System.md](Systems/World_Map_System.md) | 大地图坐标、移动、视野、遭遇 |
| [Systems/Time_System.md](Systems/Time_System.md) | 时间域、倍率、暂停栈、固定步长 |
| [Systems/Scene_System.md](Systems/Scene_System.md) | 大小场景切换与场景职责 |
| [Systems/Unit_System.md](Systems/Unit_System.md) | UnitData、表现层级、UnitController、攻击 |
| [Systems/Party_System.md](Systems/Party_System.md) | 部队数据、成员关系、编队接口 |
| [Systems/Combat_System.md](Systems/Combat_System.md) | BattleSession、援军、战斗结算 |
| [Systems/AI_System.md](Systems/AI_System.md) | 单位/部队/领主三层 AI 与调度频率 |
| [Systems/Lord_System.md](Systems/Lord_System.md) | AI 领主数据与战略决策 |
| [Systems/Settlement_System.md](Systems/Settlement_System.md) | 村庄/城镇/城堡数据与交互 |
| [Systems/Dialogue_System.md](Systems/Dialogue_System.md) | 对话数据、条件、效果与时间规则 |
| [Systems/Save_System.md](Systems/Save_System.md) | 存档结构、版本、迁移与限制 |

### 开发状态文档

| 文档 | 职责 |
|---|---|
| [Development/Current_Status.md](Development/Current_Status.md) | 当前实际进度 |
| [Development/Technical_Decisions.md](Development/Technical_Decisions.md) | 技术决策记录（ADR） |
| [Development/Known_Issues.md](Development/Known_Issues.md) | 已知问题与待确认事项 |

## 5. 每次开发的标准流程

开发前：

1. 阅读本索引，确认版本与当前阶段。
2. 阅读 `Development/Current_Status.md` 和 `Development/Known_Issues.md`。
3. 阅读任务对应的系统文档。
4. 检查相关代码与 `Technical_Decisions.md`。
5. 写出本次改动的接口、数据结构与验收方式，再动手。

开发后：

1. 更新 `Current_Status.md`。
2. 更新对应系统文档（接口、字段、流程、未实现项）。
3. 记录重要架构变化与技术决策。
4. 更新 `Known_Issues.md` 与 `04_Change_Log.md`。
5. 检查本索引的导航是否需要调整。

规则：禁止让不同 Markdown 文件长期保存互相矛盾的设计。冲突处理见 [01_Core_Architecture.md](01_Core_Architecture.md) 第 12 节。

## 6. 当前状态快照

- 阶段 0：进行中。文档体系、目录骨架、5 个 Autoload 骨架、实体数据类、JSON 存档基础接口已完成。
- 阶段 1–7：未开始。
- 最近验证：`Tests/SystemTests/skeleton_smoke_test.tscn` 全部通过（时间 tick、实体序列化、存档往返、WorldContext 装配）。
- 下一步：完成主菜单启动流程、WorldContext ↔ SaveData 聚合、读档重建。

详见 [Development/Current_Status.md](Development/Current_Status.md)。

## 7. 文档权威性

- `Docs/` 是唯一持续维护、作为开发依据的文档体系。
- `md/` 下的 V0.2 规划文档是原始需求来源，保持只读；新的实现细节以 `Docs/` 为准。
- 如果两者冲突：先找出原设计意图，再在 `Technical_Decisions.md` 记录变更原因，最后同步修改相关文档。

## 8. 常用命令

```bash
# 无头导入
Godot_v4.6.1-stable_win64.exe --headless --path . --import

# 冒烟测试
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/skeleton_smoke_test.tscn
```
