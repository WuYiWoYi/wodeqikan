# 变更日志

只记录重要变更、架构调整和接口变化。日常小改动由 Git 历史承担。

---

## 2026-11-20 · V0.3 架构基线

### 新增

- 建立 `Docs/` 项目记忆文档体系：总索引、核心架构、路线、规范、系统文档、开发状态。
- 建立工程目录骨架：`Scripts/`、`Scenes/`、`Data/`、`Tests/`。
- 注册 5 个 Autoload：`EventBus`、`TimeManager`、`SaveManager`、`SceneManager`、`GameManager`。
- 实现 `TimeManager` 固定步长世界 tick（0.1 秒，单帧最多 10 tick）。
- 实现 JSON 存档基础读写与槽位列表接口。
- 定义核心实体数据类：`UnitData`、`PartyData`、`LordData`、`SettlementData`、`FactionData`。
- 定义静态配置类：`UnitConfig`、`EquipmentConfig`、`FactionConfig`。
- 建立 `WorldContext` + `WorldSimulation` 世界会话结构。
- 建立 `BattleSession` / `BattleUnitState` / `BattleManager` 战斗会话骨架。
- 建立冒烟测试并通过全部检查。

### 决策

- 大地图采用俯视平面；小场景采用横版侧视 + 纵深移动。
- 静态配置使用 `Resource`，运行时实体使用 `RefCounted`，存档使用 JSON。
- 用 `WorldContext` + `WorldSimulation` 替代源规划中的单一 `WorldManager`。
- 暂停使用“原因栈”，而不是单一布尔值。
- 不使用 `Engine.time_scale` 或 `get_tree().paused` 实现游戏暂停。

### 未决

- 离屏 AI 对 AI 战斗是否自动结算，见 `Development/Known_Issues.md`。
- 大地图坐标尺度、缩放与地图尺寸未定。
- 渲染器是否从 Forward+ 切换到 Compatibility 待性能验证。

### 来源

- 基于《2D 中世纪沙盒战略游戏核心架构设计与开发规划 V0.2》。
