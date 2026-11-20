# 变更日志

只记录重要变更、架构调整和接口变化。日常小改动由 Git 历史承担。

---

## 2026-11-20 · Milestone 2 Step 2 大地图遭遇与首次实战

### 新增

- `PartyDialoguePanel`：显示部队名称、阵营、兵力，提供离开/发起战斗。
- `Scenes/Battle/battle.tscn` 与 `BattleScene`：战场、士兵生成、玩家点击命令、结果面板。
- `UnitActor`：程序绘制士兵、阵营颜色、朝向、血条与名称。
- `UnitController`：自动索敌、移动、攻击、受伤、死亡与手动移动命令。
- `BattleSession` 新增双方 `unit_id` 列表与阵营字段。
- `WorldInitializer.create_test_battle_forces()`：玩家与河畔商队各 3 民兵 + 2 职业步兵。
- 测试：`unit_controller_test`、`battle_manager_test`、`party_dialogue_test`、`battle_scene_test`、`milestone2_flow_test`。

### 变更

- `BattleManager.start_battle()`：校验部队、阵营、可用性与存活士兵，生成 `BattleUnitState`，锁定部队并压入 `battle` 暂停。
- `BattleManager.finish_battle()`：写回存活 HP，移除阵亡单位并删除 `UnitData`，解锁部队，清理会话，防止重复结算。
- `GameManager` 新增 `PAUSE_REASON_BATTLE`；战斗期间 `save_game()` 返回 `ERR_BUSY`。
- 屏幕内战斗 WorldTime 改为 0（暂停原因栈），`set_battle_mode(0.5)` 保留给未来离屏战斗。
- 大地图新增部队遭遇检测与对话 UI；离开后恢复此前时间状态。
- `unit_party_serialization_test` 开始时清理新游戏预置的测试士兵。

### 决策

- D027：战斗会话、场景与结算职责分离。
- D028：屏幕内战斗暂停世界时间，替代 D008 的屏幕内 0.5 倍速方案。
- D029：阵亡单位移除归属并删除数据；存活单位写回剩余 HP。
- D030：初始测试兵力为临时调试配置，后续由招募系统替换。

### 验证

- Step 1 四个单元测试、`unit_controller_test`、`battle_manager_test`、`party_dialogue_test`、`battle_scene_test`、`milestone2_flow_test` 全部通过。
- `skeleton_smoke_test`、`milestone1_test`、`milestone1_flow_test` 回归通过。
- 未修改存档 Schema；测试存档已清理。

---

## 2026-11-20 · Milestone 2 Step 1 士兵数据层

### 新增

- `Data/Units/infantry_militia.tres`（民兵）与 `infantry_trained.tres`（职业步兵）兵种配置。
- `StatCalculator` 基础实现：`compute_final_stats()` / `apply_to_unit()` 统一初始化 `max_hp`、`attack`、`attack_interval`、`move_speed`、`attack_range`。
- `PartyManager.transfer_member()`：转队接口，与 `add_member()` 共用底层规则。
- `PartyManager.validate_membership_consistency()`：校验成员存在、部队存在、唯一归属与双向一致。
- `Tests/UnitTests/`：`unit_manager_test`、`party_manager_test`、`stat_calculator_test`、`unit_party_serialization_test`。

### 变更

- `UnitManager.create_unit()` 通过 `StatCalculator` 初始化属性，出生满血并清空归属。
- `UnitManager.remove_unit()`、`PartyManager.remove_party()` 改为返回 `bool`。
- `UnitManager.add_unit()` / `PartyManager.add_party()` 拒绝重复 ID，失败时原实体不变。
- `PartyManager.add_member()` 支持原子转队：先从所有其他部队移除，再写入目标部队；要求阵营一致。
- `remove_member()` 只清空归属，不删除 `UnitData`；`remove_party()` 清空成员归属并保留单位。
- `WorldContext.load_from_save_data()` 在两个仓储恢复后校验成员关系，失败时报告错误并拒绝加载。
- `load_from_dict()` 遇到重复实体 ID 时报错并跳过，不再静默覆盖。

### 修复

- 一个士兵可能同时存在于两支部队成员列表（D024）。
- 重复实体 ID 静默覆盖（D024）。
- 删除已归属士兵后产生悬空成员引用（D024）。
- 读档后缺少士兵-部队关系校验（D025）。

### 验证

- 4 个新增单元测试全部通过。
- `skeleton_smoke_test`、`milestone1_test` 回归通过。
- 未修改存档 Schema；测试存档已清理。

---

## 2026-11-20 · 测试范围控制规范

### 变更

- 引入 L1–L4 测试分级：局部、关联、集成、全量。
- 默认只运行验证本次修改的最小测试集；公共接口/核心数据/跨系统改动扩大范围；重大重构与里程碑才运行全量。
- 开发前必须说明改动文件、涉及系统、接口影响、将执行与不执行的测试；完成后汇报测试结果与未验证风险。
- 更新 `Docs/03_Design_Conventions.md`、`Docs/00_Project_Index.md`、`Docs/02_Development_Roadmap.md`。

---

## 2026-11-20 · V0.4 Milestone 1 完成

### 新增

- `WorldInitializer`：生成世界 ID、3000×2000 地图、玩家部队、2 支 NPC 部队、4 个地点。
- `SettlementManager`：地点仓储、创建、查询、序列化，接入 `WorldContext`。
- `SaveData` Schema v2：世界 ID、创建时间、世界尺寸、玩家部队 ID。
- `SaveManager`：临时文件 + 校验 + `.bak` 备份替换；存档头、列表、最近有效存档。
- `WorldContext.to_save_data()` / `load_from_save_data()`。
- `GameManager.save_game()` / `continue_game()` / 完整读档流程。
- `TimeManager.get_base_world_speed()` / `restore_world_time()`。
- 大地图场景：草地/道路/河流背景、部队/地点图标、摄像机跟随/平移/缩放。
- 主菜单：新游戏、继续、读取列表、设置占位、退出。
- 大地图 UI：世界时间、暂停/1x/2x、玩家坐标、保存面板、返回主菜单。
- 地点交互：40 像素触发、线段检测、到达停止、暂停、离开仍暂停。
- `UiTheme`：中文字体主题，覆盖 UI 与地图图标标签。
- 测试：`milestone1_test.tscn`、`milestone1_flow_test.tscn`、`main_menu_ui_test.tscn`、`milestone1_restart_test.tscn`（跨进程存档）。

### 变更

- `WorldMapManager.update_party_movement()` 实现直线移动、到达判定、边界 clamp。
- `PartyIcon` / `SettlementIcon` / `MapBackground` 程序绘制表现。
- 主菜单与大地图 UI 改为程序化构建，关键控件使用稳定名称。
- 初始实体 ID 使用 `WORLD_000001` / `PARTY_000001` / `SETTLEMENT_000001`，而非需求示例中的 `settlement_001`（D019）。

### 验证

- 原有 18 项冒烟测试通过。
- Milestone 1 数据/UI 测试、端到端流程测试、主菜单 UI 测试全部通过。
- 主场景无头启动无解析错误与运行时报错。
- 测试存档已清理，`user://saves/` 无残留。

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

### 版本管理

- 初始化本地 Git 仓库，默认分支 `main`。
- 创建私有远程仓库并推送首个提交：<https://github.com/WuYiWoYi/wodeqikan>。
- 仓库级代理配置为 `http://127.0.0.1:10808`。

### 未决

- 离屏 AI 对 AI 战斗是否自动结算，见 `Development/Known_Issues.md`。
- 大地图坐标尺度、缩放与地图尺寸未定。
- 渲染器是否从 Forward+ 切换到 Compatibility 待性能验证。

### 来源

- 基于《2D 中世纪沙盒战略游戏核心架构设计与开发规划 V0.2》。
