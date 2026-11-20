# 设计与代码规范

**文档版本：** V0.3
**适用范围：** 所有 GDScript、场景、数据资源与 Markdown 文档

---

## 1. 语言与命名

| 对象 | 规范 | 示例 |
|---|---|---|
| 文档、注释 | 中文 | `## 部队移动` |
| 类名 | PascalCase | `UnitData`、`BattleManager` |
| 文件名 | snake_case | `unit_data.gd`、`world_map_manager.gd` |
| 变量/函数 | snake_case | `current_party_id`、`update_party_movement()` |
| 常量 | UPPER_SNAKE_CASE | `WORLD_TICK_INTERVAL` |
| 私有成员 | 前置下划线 | `_pause_reasons` |
| 信号 | snake_case，过去式/事实式 | `party_position_changed` |
| 节点名 | PascalCase | `UnitVisual`、`RightHandWeapon` |
| 场景文件 | snake_case | `world_map.tscn` |
| 实体 ID | `<PREFIX>_<6 位序号>` | `UNIT_000001` |
| 配置 ID | UPPER_SNAKE 或 `<类型>_<名称>` | `INFANTRY_RECRUIT` |
| JSON 字段 | snake_case | `world_position` |

Autoload 脚本**不使用** `class_name`，否则会与全局单例名冲突。

## 2. GDScript 规范

- 强制静态类型：变量、参数、返回值都写类型；集合使用 `Array[String]` 等。
- 一个文件一个 `class_name` 类；Autoload 除外。
- 使用 Godot 默认缩进（Tab），不用空格混排。
- 优先使用 `@export` 暴露配置，不在脚本里写死数值。
- 节点访问避免长路径；后期使用 `%UniqueName` 或 `@export_node_path`。
- 场景间通信只用 `EventBus` 事实、管理器方法和显式注入，不用 `get_node("/root/...")`。
- 信号名表达“已经发生的事”，不表达命令；命令使用方法。
- 禁止 `Engine.time_scale` 与 `get_tree().paused` 作为游戏暂停手段。
- 空实现与未完成逻辑必须写 `TODO(阶段N)`，并同步到 `Known_Issues.md`。
- 不吞错误：资源加载、存档 I/O、配置校验失败必须 `push_error` 或返回明确错误码。

## 3. 数据规范

### 3.1 数据分三类

| 类型 | 实现 | 位置 | 示例 |
|---|---|---|---|
| 静态配置 | `Resource` 子类 + `.tres` | `Scripts/Config/`、`Data/` | `UnitConfig`、`EquipmentConfig` |
| 运行时实体 | `RefCounted` 纯数据类 | `Scripts/Entities/` | `UnitData`、`PartyData` |
| 存档 | JSON（`SaveData`） | `user://saves/` | 槽位文件 |

### 3.2 运行时数据类规则

- 只保存数据，不持有场景节点、管理器、UI 引用。
- 必须提供 `to_dict()` 与静态 `from_dict()`。
- `from_dict()` 必须对缺失字段给出安全默认值。
- 枚举以 `int` 序列化；`Vector2` 以 `[x, y]`；`Color` 以 HTML 字符串。
- 派生属性（最终攻击力等）可以缓存，但必须可重算，不能成为唯一真实来源。
- 新增持久化字段时，同步评估存档兼容性。

### 3.3 单写者

每个权威字段只能有一个写入者，见 [01_Core_Architecture.md](01_Core_Architecture.md) 第 7 节。新增字段先声明写入者。

### 3.4 ID

- 只通过 `IdGenerator.next_id()` 生成。
- 计数器随存档保存；读档后恢复，保证不复用。
- 禁止用节点名、路径、数组下标或时间戳代替实体 ID。

## 4. 场景规范

### 4.1 小场景根结构

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

- 场景根节点不保存跨场景数据。
- `SceneController` 只管理本场景的生成、交互和局部状态。
- 场景退出前，必须把需要保留的变化写回管理器。

### 4.2 横版带纵深的绘制

- 战斗场景中的单位按 `world_position.y` 做 Y 排序（`y_sort_enabled`）。
- 单位内部部件用 `z_index` 调整前后关系：阴影 < 马/身体 < 武器 < 头盔装饰。
- 单位默认朝左；目标在右侧时翻转 `UnitVisual.scale.x`，不复制一套美术资源。
- 相机跟随玩家单位，不直接修改世界数据。

### 4.3 大地图表现

- 图标位置来自 `PartyData.world_position`。
- 表现层可以在 `_process` 中插值平滑，但不得回写 `PartyData`。
- 图标是 `PartyData` 的展示载体，不是实体本身。

## 5. 时间规范

| 时间域 | 驱动 | 倍率 |
|---|---|---|
| WorldTime | `TimeManager.world_tick`，0.1 秒固定步长 | 0 / 1 / 2，战斗覆盖 0.5 |
| SceneTime | 场景 `_physics_process` | 固定 1.0 |
| UITime | 真实帧时间 | 不受游戏暂停影响 |

- 暂停必须通过 `TimeManager.push_pause/pop_pause`。
- 大地图时间按钮只能调用 `TimeManager.set_base_world_speed`。
- 战斗时间覆盖只能由 `BattleManager` 调用 `set_battle_mode`。
- UI 动画、加载动画使用真实时间，不读世界倍率。

## 6. UI 规范

- UI 只展示数据、收集输入、发起意图。
- UI 不结算游戏规则，不直接修改实体字段。
- 打开需要暂停的界面前，由发起方压入暂停原因；关闭时移除。
- UI 通过 `EventBus` 监听事实，通过管理器方法执行命令。
- 交互面板的“关闭/离开”必须保证暂停原因成对移除。

## 7. AI 规范

- 三层频率：单位实时、部队 1 世界秒、领主 30 世界秒。
- 不在渲染帧扫描全部实体。
- AI 只下达命令或调用管理器接口，不直接操作场景节点与 UI。
- 玩家单位与 AI 单位共用数据结构和控制逻辑，差异只在输入来源与决策来源。
- 需要随机时使用统一随机源（后续引入 `RandomNumberGenerator` 并纳入存档），避免不可复现。

## 8. 资源与目录

- 静态配置放 `Data/`，脚本放 `Scripts/`，场景放 `Scenes/`，测试放 `Tests/`。
- 临时美术当前位于 `art/`；正式接入时再迁入 `Assets/Characters` 等目录，不提前搬动。
- 不为了目录好看而把强相关代码拆成大量小文件。
- 空目录用 `.gitkeep` 保留。

## 9. 文档规范

- 系统接口变更：修改对应 `Docs/Systems/*.md`。
- 架构变更：修改 `01_Core_Architecture.md` 并新增 ADR。
- 进度变更：修改 `Development/Current_Status.md`。
- 未决问题：写入 `Development/Known_Issues.md`，不要只留在代码注释里。
- 所有重要变更：写入 `04_Change_Log.md`。
- 文档之间不得长期保留互相矛盾的规则。

## 10. 测试规范

- 纯数据逻辑优先写单元测试（序列化、属性计算、ID 生成）。
- 跨系统流程写系统测试（时间 tick、存档往返、世界上下文装配）。
- 现有冒烟入口：`Tests/SystemTests/skeleton_smoke_test.tscn`。
- 新增系统至少提供一种可重复执行的验证方式。
