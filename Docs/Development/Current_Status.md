# 当前开发状态

**更新日期：** 2026-11-20
**当前阶段：** 阶段 0（工程基础架构）
**整体状态：** 文档与工程骨架完成并验证，阶段 0 剩余启动/读档流程

---

## 1. 阶段状态

| 阶段 | 状态 | 说明 |
|---|---|---|
| 0 工程基础架构 | 进行中 | 骨架与核心时间器完成，主菜单/读档流程未完成 |
| 1 大地图基础 | 未开始 | 场景为空场景 |
| 2 世界模拟 | 未开始 | 移动/视野为 TODO |
| 3 士兵与部队 | 未开始 | 数据层已具备 |
| 4 基础战斗 | 未开始 | 会话数据结构已具备 |
| 5 AI 领主与交互 | 未开始 | 数据层已具备 |
| 6 援军与高级战斗 | 未开始 | 编队接口为空 |
| 7 沙盒扩展 | 未开始 | — |

## 2. 已完成内容

### 文档

- `Docs/00_Project_Index.md`：总索引
- `Docs/01_Core_Architecture.md`：核心架构
- `Docs/02_Development_Roadmap.md`：开发路线
- `Docs/03_Design_Conventions.md`：设计规范
- `Docs/04_Change_Log.md`：变更日志
- 11 份系统文档
- 3 份开发状态文档

### 工程

- `project.godot`：注册 5 个 Autoload，主场景指向主菜单占位。
- `Scripts/Autoload/`
  - `event_bus.gd`：核心事实信号
  - `time_manager.gd`：0.1 秒固定步长、暂停原因栈、战斗覆盖
  - `save_manager.gd`：JSON 存档读写、槽位列表/删除
  - `scene_manager.gd`：场景切换
  - `game_manager.gd`：游戏状态与 `WorldContext` 生命周期
- `Scripts/Core/`
  - `Entity/id_generator.gd`
  - `Save/save_data.gd`
  - `World/world_context.gd`、`world_simulation.gd`、`unit_manager.gd`、`party_manager.gd`
  - `Gameplay/stat_calculator.gd`（TODO）
- `Scripts/Config/`：`UnitConfig`、`EquipmentConfig`、`FactionConfig`
- `Scripts/Entities/`：`UnitData`、`PartyData`、`LordData`、`SettlementData`、`FactionData`
- `Scripts/Systems/`：`WorldMapManager`、`BattleManager`、`BattleSession`、`BattleUnitState`、`AIManager`、`FormationManager`、`DialogueManager`
- `Scenes/`：6 个场景占位文件
- `Data/`、`Tests/`：目录与 `.gitkeep`

### 版本管理

- 本地 Git 仓库，分支 `main`。
- 私有远程：<https://github.com/WuYiWoYi/wodeqikan>
- 首个提交：`ea99719`（架构文档与工程骨架）。

## 3. 验证记录

命令：

```bash
Godot_v4.6.1-stable_win64.exe --headless --path . --import
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/skeleton_smoke_test.tscn
```

结果：18 项检查全部通过，包括：

- `WorldContext` 装配 `UnitManager` / `PartyManager`
- 配置生成单位、ID 格式、出生 HP
- 创建部队、加入成员、双向归属一致
- `UnitData` / `PartyData` 序列化往返
- 存档写入、读取、单位/部队/时间字段一致
- 0.5 秒内产生 5 次世界 tick

主场景无头启动无解析错误与运行时报错。

## 4. 下一步任务（按顺序）

1. 主菜单按钮与新游戏入口接通。
2. 实现 `WorldContext ↔ SaveData` 聚合和恢复。
3. 读档流程与版本检查接入 `GameManager`。
4. 会话销毁清理检查（暂停原因、信号、场景）。
5. 输入映射：暂停、正常、二倍速。
6. 进入阶段 1：大地图背景、玩家部队、点击移动、时间 UI。

## 5. 当前风险

- 离屏 AI 对 AI 战斗处理方式未定，会影响阶段 2/4 的世界模拟设计。
- 大地图坐标尺度未定，阶段 1 前必须确定。
- 渲染器仍为 Forward+，2D 项目是否需要切 Compatibility 待验证。
- `LordData` / `SettlementData` / `FactionData` 尚无仓储管理器。

## 6. 快速文件索引

| 想了解 | 看这里 |
|---|---|
| 全局结构 | `Docs/01_Core_Architecture.md` |
| 下一步做什么 | `Docs/02_Development_Roadmap.md` |
| 为什么这样设计 | `Docs/Development/Technical_Decisions.md` |
| 还有什么坑 | `Docs/Development/Known_Issues.md` |
| 时间规则 | `Docs/Systems/Time_System.md` |
| 战斗流程 | `Docs/Systems/Combat_System.md` |
| 存档结构 | `Docs/Systems/Save_System.md` |
