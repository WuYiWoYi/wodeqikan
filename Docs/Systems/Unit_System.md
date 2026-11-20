# 士兵与角色系统

**核心数据：** `Scripts/Entities/Unit/unit_data.gd`、`Scripts/Config/unit_config.gd`
**核心逻辑：** `Scripts/Core/World/unit_manager.gd`、`Scripts/Core/Gameplay/stat_calculator.gd`
**状态：** 数据层完成（创建、查询、删除约束、属性初始化、存档）；表现与控制未实现

---

## 1. 设计目标

- 玩家角色、普通士兵、AI 士兵共用同一套 `UnitData` 与基础表现架构。
- 玩家与 AI 的差异只在“输入来源”和“决策来源”。
- 数据与场景节点分离：单位消失时，`UnitData` 仍然存在。

## 2. UnitData

| 字段 | 类型 | 说明 | 权威写入者 |
|---|---|---|---|
| `unit_id` | String | 唯一 ID，`UNIT_000001` | `UnitManager` |
| `config_id` | String | 兵种配置 ID | `UnitManager` |
| `display_name` | String | 显示名 | `UnitManager` |
| `level` / `exp` | int | 等级与经验 | `UnitManager` |
| `max_hp` / `current_hp` | int | 生命值 | `UnitManager`；战斗期间由 `BattleManager` |
| `attack` | int | 攻击力缓存 | `StatCalculator` 经 `UnitManager` |
| `attack_interval` | float | 攻击间隔（秒） | 配置 + 加成 |
| `move_speed` | float | 小场景移动速度（像素/秒） | 配置 + 加成 |
| `attack_range` | float | 攻击距离（像素） | 配置 + 加成 |
| `faction_id` | String | 所属阵营 | `UnitManager` |
| `current_party_id` | String | 当前所属部队 | `PartyManager` |
| `equipment` | Dictionary | 装备槽位 → 装备 ID | `UnitManager` |
| `is_mounted` | bool | 是否骑兵 | 配置 |
| `joined_at_game_time` | float | 加入队伍的世界时间 | `PartyManager` |
| `recruit_source` | String | 招募方式（村庄/任务等） | `PartyManager` |
| `recruit_settlement_id` | String | 招募地点 ID | `PartyManager` |
| `origin_faction_id` | String | 原始阵营 | `UnitManager` |

## 3. 静态配置与运行时实例

- `UnitConfig`（`.tres`）：兵种模板，只读。
- `UnitData`（`RefCounted`）：单个士兵的持久化状态。
- `UnitData.config_id` 只引用配置，不复制整份配置。
- 最终属性 = 等级基础属性 + 装备加成 + 其他加成。
- 最终属性可以缓存在 `UnitData` 中，但必须能通过 `StatCalculator` 重算。
- 不允许把最终属性写回 `UnitConfig`。

### 3.1 示例兵种（数据层验证用）

| 文件 | `config_id` | 名称 | HP | 攻击 | 攻击间隔 | 移速 | 射程 |
|---|---|---|---|---|---|---|---|
| `Data/Units/infantry_militia.tres` | `infantry_militia` | 民兵 | 30 | 5 | 1.2 | 60 | 20 |
| `Data/Units/infantry_trained.tres` | `infantry_trained` | 职业步兵 | 45 | 8 | 1.0 | 55 | 20 |

### 3.2 当前属性初始化规则（Milestone 2 Step 1）

`StatCalculator` 是运行时属性的唯一计算入口：

- `compute_final_stats(unit, config)` 返回 `max_hp` / `attack` / `attack_interval` / `move_speed` / `attack_range`。
- 当前直接取 `UnitConfig` 的 `base_*` 静态值；等级成长与装备加成尚未实现（KI120）。
- `apply_to_unit(unit, config)` 写入属性缓存，只对 `current_hp` 做上限 clamp，不重置当前生命。
- `UnitManager.create_unit()` 调用 `apply_to_unit()` 后显式设置 `current_hp = max_hp`，并清空 `current_party_id`。

### 3.3 UnitManager 数据安全规则

- 每个 `UnitData` 是独立实例，ID 由 `IdGenerator` 生成。
- `add_unit()` 遇到已存在 ID 时拒绝注册并返回空字符串，不覆盖原单位。
- `remove_unit()` 在 `current_party_id` 非空时拒绝删除；必须先经 `PartyManager.remove_member()`。
- `remove_unit()` 成功返回 `true`，单位不存在或仍被部队引用返回 `false`。
- `load_from_dict()` 遇到重复单位 ID 时报告错误并跳过后续记录，避免静默覆盖。
- 单位归属只由 `PartyManager` 写入；`UnitManager` 不修改 `PartyData`。

## 4. 表现层

### 4.1 节点结构

```text
Unit (Node2D)
├── UnitController
├── UnitVisual
│   ├── Shadow
│   ├── HorseVisual            # 骑兵
│   │   ├── HorseHead
│   │   ├── HorseBody
│   │   ├── HorseLegs
│   │   └── Saddle
│   └── HumanVisual            # 步行/骑乘共用人体
│       ├── LeftFoot
│       ├── Body
│       ├── FactionCloak
│       ├── Head
│       ├── Helmet
│       ├── HelmetDecoration
│       ├── RightHandWeapon
│       └── LeftHandWeapon
└── AnimationController
```

- 实际绘制顺序允许通过 `z_index` 调整。
- 骑马与步行使用不同的美术组合；人体部件复用。
- 不要求所有部件都有独立动画；初期可做整体摆动 + 武器挥动 + 腿部交替。
- 临时美术当前位于 `art/我的骑砍临时美术/`，接入时不直接引用临时路径，应在 `Assets/` 下建立正式资源后再绑定。

### 4.2 视角与朝向

- 小场景为横版侧视 + 纵深移动，单位可在 XY 平面移动。
- 按 `position.y` 进行 Y 排序，形成前后遮挡。
- 默认朝左。
- 目标在右侧时，翻转 `UnitVisual.scale.x = -1`（或水平翻转 Sprite），攻击方向只分左右。
- 目标在左侧时，恢复正方向。
- 纵向移动不改变朝向。

### 4.3 阴影

- 阴影独立于单位身体，跟随地面位置。
- 骑马与步行使用不同阴影素材。
- 阴影不参与攻击判定。

## 5. UnitController

### 5.1 状态机

```text
Idle
├── Accelerating
│   └── Moving
│       ├── Decelerating → Idle
│       ├── Attacking → Idle/Accelerating
│       └── Hurt → Idle
└── Dead
```

- 骑兵与步兵共用状态机，通过移动参数区分。
- `Hurt` 只做短暂硬直，不改变归属。
- `Dead` 后停止 AI、关闭碰撞，等待战斗结算移除。

### 5.2 移动

- 使用 `CharacterBody2D` 或等价 2D 物理节点。
- 加速度、减速度、最大速度来自单位属性或配置。
- 纵轴移动速度可以低于横轴（横版纵深常见），初期可保持相同，后续再调。
- 不直接读取世界 tick；小场景使用 `_physics_process`。

### 5.3 攻击流程

```text
1. 检测攻击范围内敌人
2. 有多个目标时随机选择
3. 检查攻击 CD
4. 播放攻击动画
5. 造成伤害
6. 进入下一次 CD
```

- 攻击方向由目标相对位置决定，只分左右。
- 攻击期间可以保持移动或短暂停步，具体在阶段 3 确定。
- 伤害结算写 `BattleUnitState`，不直接写 `UnitData`。

### 5.4 受击与死亡

- 受击进入短硬直，播放受击反馈。
- HP 归零 → `Dead`，记录死亡，等待 `BattleManager` 结算。
- 非战斗场景（如村庄）不应发生战斗死亡。

## 6. 玩家与 AI 共用

| 项目 | 玩家 | AI |
|---|---|---|
| 数据 | `UnitData` | `UnitData` |
| 表现 | `UnitVisual` | `UnitVisual` |
| 移动/攻击 | `UnitController` | `UnitController` |
| 决策 | 玩家输入 / 指令 | `UnitAI` |
| 队伍归属 | `PartyManager` | `PartyManager` |

## 7. 更新频率

| 内容 | 频率 |
|---|---|
| 单位移动、攻击、动画 | 小场景物理帧 |
| 最终属性重算 | 等级/装备变化时 |
| 世界侧单位数据 | 不参与世界 tick，除非在战斗结算中 |

## 8. 实现状态

| 项 | 状态 |
|---|---|
| `UnitData` 与序列化 | 已实现 |
| `UnitConfig` | 已实现 |
| 两种示例兵种 `.tres` | 已实现 |
| `UnitManager` 生成单位 | 已实现：独立实例、唯一 ID、满血出生 |
| 重复 ID 防护 | 已实现：`add_unit` 拒绝覆盖，读档跳过重复并报错 |
| 删除归属约束 | 已实现：已归属单位禁止直接删除 |
| `StatCalculator` | 基础实现：复制配置属性；等级成长/装备加成 TODO(阶段3) |
| 成员归属 | 由 `PartyManager` 维护，见 [Party_System.md](Party_System.md) |
| `UnitController` | TODO(阶段3) |
| 部件视觉与动画 | TODO(阶段3) |
| 攻击/受击/死亡 | TODO(阶段3) |
| 初始世界/招募生成士兵 | TODO(阶段3) |

## 9. 待确认

- 攻击距离是圆形判定还是左右矩形判定。
- 纵向移动速度是否低于横向。
- 单位碰撞层与阵营过滤的具体配置。
- 大量单位时是否使用对象池。
- 等级成长公式与装备加成上限（KI120）。
- 跨阵营招募、俘虏与叛变的单位归属规则（KI119）。
- `joined_at_game_time` / 招募来源字段的实际写入时机。
