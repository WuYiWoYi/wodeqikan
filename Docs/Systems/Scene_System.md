# 场景系统

**核心脚本：** `Scripts/Autoload/scene_manager.gd`
**状态：** MainMenu、WorldMap、Battle、Village 已实现；Town/Castle 仍为占位；村庄与战斗共用摄像机视野/跟随/自由视角

---

## 1. 场景分类

| 场景 | 路径 | 用途 |
|---|---|---|
| MainMenu | `res://Scenes/MainMenu/main_menu.tscn` | 新游戏、读档、设置、退出 |
| WorldMap | `res://Scenes/WorldMap/world_map.tscn` | 战略层世界模拟与部队操作 |
| Battle | `res://Scenes/Battle/battle.tscn` | 实时战斗 |
| Village | `res://Scenes/Village/village.tscn` | 村庄探索与交互 |
| Town | `res://Scenes/Town/town.tscn` | 城镇探索与交互 |
| Castle | `res://Scenes/Castle/castle.tscn` | 城堡探索与交互 |

所有小场景统一使用 2D 横版侧视 + 纵深移动。

## 2. 职责划分

| 对象 | 负责 | 不负责 |
|---|---|---|
| `SceneManager` | 路径常量、场景切换、当前场景记录 | 世界数据、场景内容 |
| `GameManager` | 决定何时切换、创建/销毁 `WorldContext` | 节点生成细节 |
| `SceneController` | 生成本场景表现、局部交互 | 长期保存世界数据 |
| 场景节点 | 表现与输入 | 权威数据 |

## 3. 根结构

```text
GameplayScene (Node2D)
├── World
│   ├── Environment
│   ├── Characters
│   └── Interactables
├── Camera2D
├── SceneController
└── SceneUI (CanvasLayer)
```

Milestone 1 大地图实际结构：

```text
WorldMap (Node2D)
├── MapBackground (Node2D，程序绘制)
├── WorldEntities (Node2D，Y 排序)
│   ├── PartyIcon_*
│   └── SettlementIcon_*
├── Camera2D
└── UI (CanvasLayer，由脚本构建)
    └── WorldMapUI
```

大地图 UI 通过 `world_map.gd` 程序化构建，关键控件设置稳定名称以便测试。UI 根节点 `mouse_filter = IGNORE`，地图点击由 `_unhandled_input` 接收。

阶段 6 村庄实际结构：

```text
Village (Node2D，village_scene.gd)
├── Camera2D（SceneCameraRig：跟随玩家 / 自由视角）
├── PlayerVisual (UnitVisual，复用玩家 UnitData)
├── VillageElderVisual (UnitVisual，运行时 NPC 数据)
├── VillageElderNameLabel
└── UI (CanvasLayer，由脚本构建)
    ├── 村庄名称/提示
    ├── 越界倒计时
    └── 数据驱动对话面板
```

村庄场景由 `WorldMap.enter_village()` 通过 `SettlementData.scene_path` 进入；离开时恢复大地图基础倍率并写入一次性地点交互锁。

## 4. 生命周期

### 4.1 进入小场景

1. 记录来源（大地图位置、返回方式）。
2. 压入 `small_scene` 暂停原因（WorldTime = 0）。
3. 切换场景。
4. 场景控制器从 `WorldContext` 读取地点、部队、NPC 数据。
5. 生成表现节点，绑定局部逻辑。
6. `SceneTime` 在 `_physics_process` 中正常推进。

### 4.2 离开小场景

1. 收集本场景需要保留的变化（例：地点状态、NPC 状态）。
2. 通过管理器接口写回数据。
3. 释放表现节点。
4. 移除 `small_scene` 暂停原因。
5. 返回大地图，恢复进入前的时间倍率。

进入前的大地图倍率由 `GameManager` 保存/恢复，不由场景自己决定。

Milestone 1 已验证：

- New Game 创建 `WorldContext` 后进入 WorldMap。
- 返回主菜单会销毁 `WorldContext`，不残留旧场景节点。
- 读档会重建 `WorldContext` 并进入 WorldMap。
- 场景切换不会重复创建 Autoload。

### 4.3 场景切换与 WorldContext

- `WorldContext` 不随场景切换销毁。
- 场景切换期间世界 tick 可以继续（战斗场景），也可以暂停（小场景探索）。
- 任何场景都不得创建自己的 `WorldContext`。

## 5. 大地图与战斗

战斗场景是特殊小场景：

- 由 `BattleManager` 创建 `BattleSession` 后进入。
- 场景控制器只读取 `BattleSession` 和参战部队数据。
- 战斗临时 HP、位置、行为写 `BattleSession`，不写 `UnitData`。
- 战斗结束后由 `BattleManager` 统一结算并返回大地图。

详见 [Combat_System.md](Combat_System.md)。

### 5.1 小场景摄像机（`SceneCameraRig`）

村庄与战斗共用 `Scripts/Systems/Scene/scene_camera_rig.gd`：

| 项 | 规则 |
|---|---|
| 统一视野 | `VIEW_SIZE = 960×540` 世界单位；1920×1080 下缩放 2 倍 |
| 其他分辨率 | `min(viewport.x / 960, viewport.y / 540)`，至少保留统一视野区域 |
| 默认模式 | 平滑跟随当前玩家控制角色 |
| 战斗控制权切换 | 自动跟随新控制单位；观战时保持当前位置 |
| 自由视角 | `F` 切换；WASD / 方向键移动镜头，不移动角色 |
| 切回跟随 | 立即重新定位到当前跟随目标 |
| 边界 | 跟随与自由模式均限制在场景/战场边界内；场景小于视野时居中 |

- 每个小场景只有一个 `Camera2D`；`SceneCameraRig` 只操作它，不创建额外摄像机。
- 自由视角在战斗/村庄中只改变镜头位置，不写入 `UnitData`、`PartyData` 或战斗位置。

## 6. 时间规则

| 场景 | WorldTime | SceneTime |
|---|---:|---:|
| 主菜单 | 0 | 无 |
| 大地图 | 由 `TimeManager` 基础倍率决定 | 无 |
| 小场景探索 | 0 | 1.0 |
| 小场景对话 | 0 | 1.0 |
| 屏幕内战斗 | 0（`battle` 暂停） | 1.0 |

## 7. 场景状态与存档

- 场景节点不进入存档。
- 需要恢复的局部状态写入 `SaveData.scene_state` 或对应实体数据。
- 例如：玩家进入村庄时的位置可以不做精确恢复，但地点归属、NPC 状态必须保存。
- 初期读档统一回到大地图，不恢复小场景。

## 8. 实现状态

| 项 | 状态 |
|---|---|
| 场景路径常量 | 已实现 |
| `change_scene` | 已实现（无过渡动画） |
| MainMenu | 已实现（新游戏/继续/读取/设置/退出） |
| WorldMap | 已实现（地图/图标/时间/交互/保存/追逐焦点/悬浮信息） |
| Village | 已实现（玩家、村庄头人、对话、越界倒计时） |
| Town / Castle | 空场景占位 |
| BattleScene | 已实现 |
| 小场景统一摄像机 | 已实现（跟随 / 自由视角 / 边界 / 统一视野） |
| 加载画面/过渡 | TODO |
| 异步加载 | TODO |

## 9. 扩展方向

- 异步加载与进度条。
- 场景切换淡入淡出。
- 小场景内返回大地图的统一入口。
- 场景对象池（大量单位时）。
- 大地图 UI 迁移为可编辑场景（当前为程序化构建）。
