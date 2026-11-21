# 我的骑砍 · 项目总索引

**文档版本：** V0.20（阶段 6：小地图摄像机、按小时离屏战斗、追击接触与战斗 UI）
**更新日期：** 2026-11-21
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
| 攻击朝向 | 武器攻击判定支持 360°；人物贴图仍左右镜像，默认朝左 |
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
├── ItemManager      消耗品/杂物静态配置
├── PartyManager
├── SettlementManager
├── FactionManager   阵营关系
├── VisionManager    视野查询
├── WorldMapManager  移动/跟随
├── EncounterManager 统一遭遇/中途参战
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
| [Systems/Village_System.md](Systems/Village_System.md) | 村庄场景、NPC、对话 UI、越界返回 |
| [Systems/Inventory_Economy_System.md](Systems/Inventory_Economy_System.md) | 背包、马匹、金币、工资、三级兵种与晋升 |
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
6. 按改动影响确定测试级别（L1–L4），明确将执行和明确不执行的测试。

开发后：

1. 更新 `Current_Status.md`。
2. 更新对应系统文档（接口、字段、流程、未实现项）。
3. 记录重要架构变化与技术决策。
4. 更新 `Known_Issues.md` 与 `04_Change_Log.md`。
5. 检查本索引的导航是否需要调整。
6. 汇报实际执行的测试、结果与未验证的关联风险。

规则：禁止让不同 Markdown 文件长期保存互相矛盾的设计。冲突处理见 [01_Core_Architecture.md](01_Core_Architecture.md) 第 12 节。

## 6. 当前状态快照

- 阶段 0：完成。
- 阶段 1（Milestone 1）：完成。主菜单、初始世界、大地图移动、时间控制、地点交互、保存/读取闭环已实现。
- 阶段 2：部分完成。世界固定 tick、直线移动、NPC 商队往返与巡逻循环、视野/追击/遭遇、玩家时间快捷键已实现；更大规模空间索引待开发。
- 阶段 3：部分完成。士兵数据层、属性重算、装备/马匹、部队查看 UI、临时部件美术已实现；招募与正式美术未开始。
- 阶段 4：部分完成。双方/多方实时战斗、按小时离屏结算、中途加入、玩家角色、控制权转移、基础队形、结果/经验/奖励已实现；高级指挥/士气/正式动画未开始。
- 阶段 5（战斗结算与战后处理）：完成。统一 BattleResult、玩家角色、攻击判定/多人围攻、临时部件美术、骑乘系统、控制权转移、经验/奖励、撤退与返回大地图均已自动化验证。
- 阶段 6（合并原阶段 6/7）：村庄小场景与交互、追逐焦点保护、背包/马匹、金币与工资、三级兵种/晋升、世界日历与大地图部队 UI 已实现；城镇/城堡小场景、商店、招募、工资扣除未实现。
- 阶段 5（原路线图 AI 领主）、阶段 7：未开始。
- 阶段 5（动作表现与攻击体验）：完成。协调步兵步态、马匹整体动态、玩家自由空挥、长矛攻击后保持 4 秒、骑乘战斗速度 0.84、部署间距约 906 已自动化与动画截图验证。
- 阶段 5（待机与动作表现二次优化）：完成。克制腿幅、部队 UI 待机动画、跃马式前后腿分组、长矛方向性前摇/戳击已自动化与真实渲染验证。
- 最近验证：克制步态/跃马动画、UI 待机动画、长矛前摇/戳击/保持、自由攻击、骑乘战斗速度、战斗结算与 Milestone 2 全流程全部通过。
- 2026-11-21 修复：士兵部件被战场背景整体覆盖导致完全不可见；`UnitActor` 提升到背景之上，骑乘保留人体双腿并由马身/马鞍按层级遮挡。
- 2026-11-21 优化：人物/马匹分组 + `VisualLayers` 最终层级、骑乘 15 像素偏移、四条独立马腿、影子互斥、长矛枢轴/攻击/恢复动画、部队面板 SubViewport 预览；玩家部队改为 7 人（3 名骑乘职业步兵）。
- 2026-11-21 优化：马腿移到马身之前；步兵/骑兵待机/移动动画；战斗移动 ×0.6、部署边距 220；1920×1080 原生显示 + 战斗相机 2 倍；武器决定攻击距离；360°定向矩形攻击（单次单目标）；最小间距实体碰撞。
- 2026-11-21 优化：步兵等幅反相步态；马身主导的跑步动态与克制马腿；玩家无敌人也可自由出矛；攻击后长矛保持 4 秒再恢复；骑乘战斗速度 0.84；部署边距 160（质心间距约 906）。
- 2026-11-21 优化：步兵腿幅降至 1.5/0.6/0.04；部队 UI 复用 UnitVisual 播放步兵/骑兵待机；马腿改为前后成组跃马；长矛增加方向性后移前摇与 6 px 前伸戳击。
- 2026-11-21 阶段 6：村庄进入/对话/越界返回；大地图追逐不被打断；部队图标只显示人数与悬浮构成；三级兵种（10/50、20/100、25/180）、工资、金币、背包马匹上下马、消耗凭证晋升；世界时间从 1103-01-01 起，6 秒 = 1 小时，显示年月日 + 时间段。
- 2026-11-21 阶段 6（大地图战斗与小地图视角）：村庄/战斗共用 `SceneCameraRig`（960×540 统一视野、跟随、F 自由视角、边界）；离屏 AI 战斗每游戏小时按战力/等级/骑乘/剩余生命与随机波动结算；玩家追击同向目标可在 50 世界单位内接触且不回弹；同场战斗合并为单标记并按 `side_index` 分组汇总；遭遇面板提供战斗/撤退。

详见 [Development/Current_Status.md](Development/Current_Status.md)。

## 7. 文档权威性

- `Docs/` 是唯一持续维护、作为开发依据的文档体系。
- `md/` 下的 V0.2 规划文档是原始需求来源，保持只读；新的实现细节以 `Docs/` 为准。
- 如果两者冲突：先找出原设计意图，再在 `Technical_Decisions.md` 记录变更原因，最后同步修改相关文档。

## 8. 常用命令

```bash
# 无头导入
Godot_v4.6.1-stable_win64.exe --headless --path . --import

# 士兵/部队数据层单元测试
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/unit_manager_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/party_manager_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/stat_calculator_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/unit_party_serialization_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/unit_controller_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/combat_attack_rules_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/mounted_unit_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/unit_visual_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/formation_manager_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/battle_result_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/player_character_data_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/battle_manager_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/ai_manager_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/faction_vision_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/multi_party_battle_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/unit_tier_wage_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/time_calendar_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/offscreen_battle_hourly_test.tscn

# 系统测试套件
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/skeleton_smoke_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/milestone1_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/milestone1_flow_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/party_panel_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/ai_encounter_flow_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/player_encounter_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/player_battle_interaction_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/party_dialogue_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/world_map_input_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/battle_scene_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/player_control_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/battle_formation_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/battle_side_result_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/battle_retreat_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/milestone2_flow_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/main_menu_ui_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/village_scene_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/village_flow_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/world_map_milestone6_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/party_economy_ui_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/small_scene_camera_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/player_pursuit_encounter_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/world_map_battle_marker_test.tscn

# 跨进程存档：先保存退出，再新进程读取
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/milestone1_restart_test.tscn -- save
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/milestone1_restart_test.tscn -- load

# 手动视觉验收（非 headless，打开战斗窗口并保存截图到 user://）
Godot_v4.6.1-stable_win64.exe --path . res://Tests/_debug/visual_probe.tscn
Godot_v4.6.1-stable_win64.exe --path . res://Tests/_debug/party_preview_probe.tscn
Godot_v4.6.1-stable_win64.exe --path . res://Tests/_debug/main_menu_probe.tscn
```
