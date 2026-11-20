# 当前开发状态

**更新日期：** 2026-11-20
**当前阶段：** Milestone 2 Step 2 完成（大地图遭遇 + 最小实时战斗闭环）
**整体状态：** 玩家可从大地图接近 AI 部队、对话、进入战斗、实时交战、结算并返回大地图；正式美术与复杂战术未开始

---

## 1. 阶段状态

| 阶段 | 状态 | 说明 |
|---|---|---|
| 0 工程基础架构 | 完成 | Autoload、数据层、主菜单、存档闭环 |
| 1 大地图基础 | 完成 | Milestone 1 全部功能已实现 |
| 2 世界模拟 | 部分完成 | 固定 tick / 直线移动已实现；视野、遭遇、NPC AI 待开发 |
| 3 士兵与部队 | 部分完成 | 数据层 + 最小战斗表现与 UnitController；正式美术/阵型未开始 |
| 4 基础战斗 | 部分完成 | 最小实时战斗闭环：遭遇、对话、生成、战斗、结算、返回；援军/离屏结算未开始 |
| 5 AI 领主与交互 | 未开始 | 数据层已具备 |
| 6 援军与高级战斗 | 未开始 | 编队接口为空 |
| 7 沙盒扩展 | 未开始 | — |

## 2. Milestone 1 已完成内容

### 世界与数据

- `WorldInitializer`：新游戏生成世界 ID、3000×2000 地图、玩家部队、2 支 NPC 部队、4 个地点。
- `SettlementManager`：地点数据仓储与序列化，已接入 `WorldContext`。
- `WorldContext`：新增 `to_save_data()` / `load_from_save_data()`，聚合与恢复世界状态。
- `SaveData`：Schema v2，新增世界 ID、创建时间、世界尺寸、玩家部队 ID。
- `SaveManager`：临时文件 + 校验 + `.bak` 备份替换；存档头信息、排序、最近有效存档查询。
- `TimeManager`：新增 `get_base_world_speed()`、`restore_world_time()`。
- `GameManager`：新游戏、读档、Continue、保存、同步销毁旧世界。

### 大地图

- 3000×2000 手绘式背景：草地、网格、道路、河流、边界。
- 玩家部队 + 2 支 NPC 部队图标，4 个地点图标（村庄/城堡）。
- 点击地图设置目标，直线移动，2 像素到达阈值，地图边界 clamp。
- 摄像机跟随、方向键平移、滚轮缩放。
- 图标读取数据并插值，不写回权威数据。

### 时间与交互

- 暂停 / 1x / 2x 时间按钮，UI 显示世界时间与倍率。
- 新游戏默认暂停；读档恢复存档中的基础倍率。
- 地点 40 像素交互半径，带路径段检测，避免高倍速穿过地点时漏判。
- 到达地点自动停止、暂停并打开面板；离开后仍保持暂停。
- 保存面板打开时使用暂停原因栈，关闭后恢复原倍率。

### 主菜单

- 新游戏、继续、读取存档、设置占位、退出。
- Continue 自动选择最近有效存档，无存档时禁用。
- 读取列表显示存档名与保存时间，支持双击读取。
- 设置占位面板。

### 版本管理

- 私有远程：<https://github.com/WuYiWoYi/wodeqikan>
- 当前工作区包含 Milestone 1 改动（尚未提交，等待确认）。

## 3. Milestone 2 Step 1 已完成内容

### 士兵配置与创建

- `Data/Units/infantry_militia.tres`（民兵）与 `Data/Units/infantry_trained.tres`（职业步兵）。
- `UnitManager.create_unit()` 按配置生成独立 `UnitData`；ID 由 `IdGenerator` 生成，两次创建互不相同。
- `StatCalculator` 成为属性初始化的唯一入口：当前复制配置基础属性，保留等级与装备扩展点。
- 出生时 `current_party_id` 为空，`current_hp = max_hp`；多个士兵不共享运行时状态。

### 成员关系

- `PartyManager.add_member()` 支持转队：先从所有其他部队移除，再加入目标部队；一个单位最多属于一支部队。
- 重复加入同一部队不会产生重复成员；转队操作在全部校验通过后一次性修改，避免半转移状态。
- `transfer_member()` 与 `add_member()` 共用同一套底层规则。
- 本阶段要求单位与部队 `faction_id` 一致，拒绝跨阵营加入。
- `remove_member()` 只清空归属，不删除 `UnitData`。
- `remove_party()` 清空所有成员归属，单位保留在 `UnitManager`。

### 数据安全

- `UnitManager.add_unit()` / `PartyManager.add_party()` 拒绝覆盖已存在 ID，失败时原实体不变。
- `UnitManager.remove_unit()` 拒绝删除仍属于部队的单位。
- `PartyManager.validate_membership_consistency()` 校验四类关系：成员存在、部队存在、唯一归属、双向一致。
- `WorldContext.load_from_save_data()` 在恢复两个仓储后统一校验；失败时 `push_error` 并返回 `false`，不自动改写存档。

### 测试

- 新增 `Tests/UnitTests/` 四个测试：`unit_manager_test`、`party_manager_test`、`stat_calculator_test`、`unit_party_serialization_test`。
- 序列化测试覆盖 5 名士兵、Party A/B、移除与转队、保存/读取、二次往返、读档后继续转队、损坏引用拒绝加载。

## 4. Milestone 2 Step 2 已完成内容

### 大地图遭遇与对话

- 玩家进入 AI 部队 40 像素范围触发 `PartyDialoguePanel`，使用路径段检测避免高倍速穿过。
- 面板显示部队名称、阵营、`member_unit_ids.size()` 兵力。
- “离开”关闭面板并恢复此前世界时间状态；“发起战斗”创建战斗会话并进入战斗场景。
- 同一时间只有一个对话面板；空部队不触发交互；任一方无兵时战斗按钮禁用。
- 新游戏通过 `WorldInitializer.create_test_battle_forces()` 给玩家和“河畔商队”各生成 3 民兵 + 2 职业步兵，单位标记 `recruit_source = "milestone2_test"`。

### 战斗场景与士兵

- `BattleSession` 新增双方 `unit_id` 列表与阵营字段。
- `BattleManager.start_battle()` 校验部队、阵营、可用性与存活士兵，生成 `BattleUnitState`，锁定部队并压入 `battle` 暂停。
- `BattleScene` 根据会话生成 10 名士兵；节点名 `UnitActor_<unit_id>`，玩家蓝色、敌方红色，位置按 2 列阵型分开。
- `UnitActor` 程序绘制身体、朝向武器、血条与名称；不修改 `UnitData`。
- 每个士兵由 `UnitController` 驱动，属性全部读取 `UnitData`。

### 实时战斗

- 自动索敌最近敌人；目标死亡后重新选择。
- 进入 `attack_range + 8` 后按 `attack_interval` 攻击，伤害写入 `BattleUnitState.battle_hp`。
- 玩家左键点击地面命令所有存活己方士兵移动；手动移动期间不主动攻击，到达后恢复自动索敌。
- 敌方自动接近并攻击；HP 归零后停止移动、攻击与受伤，表现节点移除。
- 一方全灭或双方全灭时显示胜利/失败/平局结果面板。

### 结算与返回

- 玩家点击“返回大地图”后 `BattleManager.finish_battle()` 统一结算。
- 存活士兵写回剩余 HP；阵亡士兵清空归属、删除 `UnitData` 并广播 `unit_died`。
- 参战部队解锁；`BattleSession` 清理；移除 `battle` 暂停，恢复此前世界时间状态。
- 重复结算被拒绝；战斗期间 `GameManager.save_game()` 返回 `ERR_BUSY`。
- 返回大地图后可继续移动、保存和读档；空敌方部队不再触发对话。

## 5. 自动化验收

### 测试套件

| 测试 | 覆盖 |
|---|---|
| `Tests/UnitTests/unit_manager_test.tscn` | 创建、独立实例、不同兵种属性、满血初始化、无效配置、重复 ID、删除归属约束 |
| `Tests/UnitTests/party_manager_test.tscn` | 成员增删、重复加入、转队、阵营拒绝、重复部队 ID、解散、双向一致性校验 |
| `Tests/UnitTests/stat_calculator_test.tscn` | 两种兵种属性、属性写入、HP clamp、空输入 |
| `Tests/UnitTests/unit_party_serialization_test.tscn` | 5 名士兵与多部队存档往返、成员关系恢复、继续转队、二次往返、损坏引用拒绝加载 |
| `Tests/UnitTests/unit_controller_test.tscn` | 接近、攻击间隔、伤害、死亡、重新索敌、手动移动、5v5 自动战斗收敛 |
| `Tests/UnitTests/battle_manager_test.tscn` | 开始校验、锁定、玩家战败结算、剩余 HP 写回、重复结算拒绝 |
| `Tests/SystemTests/party_dialogue_test.tscn` | 接近 AI 部队、对话内容、暂停恢复、重复 UI、战斗准备、战斗中禁存档 |
| `Tests/SystemTests/battle_scene_test.tscn` | 10 名士兵生成、唯一 unit_id、阵营/间距、实时伤害、死亡移除、胜利、结算与存档 |
| `Tests/SystemTests/milestone2_flow_test.tscn` | 大地图 → 对话 → 战斗 → 返回 → HP/成员结算 → 保存/读档全流程 |
| `Tests/SystemTests/skeleton_smoke_test.tscn` | 原有 18 项：时间 tick、实体序列化、存档往返、WorldContext 装配 |
| `Tests/SystemTests/milestone1_test.tscn` | 世界初始化、移动、边界、存档/读档、NPC/地点恢复、ID 恢复、读档后移动、损坏存档、地点交互、时间暂停、保存面板 |
| `Tests/SystemTests/milestone1_flow_test.tscn` | New Game → WorldMap → 移动 → 保存 → 主菜单 → Load/Continue → WorldMap；Autoload 与旧场景残留检查 |
| `Tests/SystemTests/main_menu_ui_test.tscn` | 主菜单按钮、读取面板、设置占位面板 |
| `Tests/SystemTests/milestone1_restart_test.tscn` | 两次独立 Godot 进程：保存退出 → 新进程读档，校验位置/时间/倍率/实体/ID |

### 运行命令

```bash
Godot_v4.6.1-stable_win64.exe --headless --path . --import
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/unit_manager_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/party_manager_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/stat_calculator_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/unit_party_serialization_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/unit_controller_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/battle_manager_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/party_dialogue_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/battle_scene_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/milestone2_flow_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/skeleton_smoke_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/milestone1_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/milestone1_flow_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/main_menu_ui_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/milestone1_restart_test.tscn -- save
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/milestone1_restart_test.tscn -- load
```

本次实际执行：Step 1 的 4 个单元测试、`unit_controller_test`、`battle_manager_test`、`party_dialogue_test`、`battle_scene_test`、`milestone2_flow_test`、`skeleton_smoke_test`、`milestone1_test`、`milestone1_flow_test`，以及跨进程 `milestone1_restart_test` 的 save/load 两阶段，全部通过。未执行主菜单 UI 测试。测试存档已清理；未改变存档 Schema。

### 手动验证步骤

1. 启动游戏，进入主菜单。
2. New Game → 大地图默认暂停；玩家部队应显示 5 名成员。
3. 点击地图移动玩家部队；切换 1x / 2x 观察速度变化。
4. 移动至“河畔商队”（地图下方，约 900,1500），接近后自动打开部队对话。
5. 确认面板显示部队名称、阵营“本地势力”、兵力 5；点击离开，确认世界恢复暂停前倍率。
6. 再次接近并点击“发起战斗”，进入战斗场景；确认双方各 5 名士兵、蓝红阵营区分、位置不重叠。
7. 左键点击地面命令己方士兵移动；观察双方自动接近、攻击、血条下降与死亡移除。
8. 消灭全部敌人后点击“返回大地图”，确认部队解锁、存活士兵保留 HP、阵亡敌人被移除。
9. 打开保存面板保存，返回主菜单并读取，确认士兵数量、HP 与成员关系正确。
10. 重复进入战斗与返回，确认不会残留旧场景、旧对话或重复结算。

## 6. 下一步任务

1. 阶段 3 表现层后续：正式士兵美术、攻击/受击动画、阵型站位。
2. 招募系统：替换 `milestone2_test` 临时兵力，处理旧存档补员。
3. 战斗 AI：寻路、阵型、撤退与士气；玩家选中/框选单位。
4. 玩家战败处理：逃脱、被俘或重新开局。
5. 阶段 2：视野、遭遇检测、NPC 自主目标与简单 AI。
6. 存档：Schema v1 → v2 完整迁移策略、其他跨实体引用校验、自动存档。
7. 部队管理面板：显示成员、属性与编队入口。

## 7. 当前风险

- 离屏 AI 对 AI 战斗处理方式未定；屏幕内战斗目前暂停世界，0.5 倍速覆盖未使用。
- NPC 部队尚无自主行为，遭遇依赖玩家主动接近。
- 战斗 AI 无寻路与阵型，多单位可能重叠。
- 玩家战败后部队可为空，尚无逃脱/被俘/重开流程。
- 被击溃的敌方部队保留为空部队图标，仅禁止交互。
- 临时测试兵力会进入新存档；旧存档读档后可能无兵可战。
- 大地图采用直线移动，无寻路与地形阻挡。
- 渲染器仍为 Forward+，2D 项目是否需要切 Compatibility 待验证。
- `LordData` / `FactionData` 尚无仓储管理器。
- 项目尚无正式美术资源目录；地图、图标与士兵目前为程序绘制。
- `StatCalculator` 目前只复制兵种基础属性，等级与装备尚不生效。
- 单位-部队归属已校验；阵营、地点、领主等其他引用尚未统一校验。
- 跨阵营收编、俘虏、叛变与雇佣兵规则未实现，当前直接拒绝阵营不一致。

## 8. 快速文件索引

| 想了解 | 看这里 |
|---|---|
| 全局结构 | `Docs/01_Core_Architecture.md` |
| 下一步做什么 | `Docs/02_Development_Roadmap.md` |
| 为什么这样设计 | `Docs/Development/Technical_Decisions.md` |
| 还有什么坑 | `Docs/Development/Known_Issues.md` |
| 士兵数据与属性 | `Docs/Systems/Unit_System.md` |
| 部队与成员关系 | `Docs/Systems/Party_System.md` |
| 战斗流程与结算 | `Docs/Systems/Combat_System.md` |
| 时间规则 | `Docs/Systems/Time_System.md` |
| 大地图 | `Docs/Systems/World_Map_System.md` |
| 地点 | `Docs/Systems/Settlement_System.md` |
| 存档结构 | `Docs/Systems/Save_System.md` |
