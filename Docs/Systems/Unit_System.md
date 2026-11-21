# 士兵与角色系统

**核心数据：** `Scripts/Entities/Unit/unit_data.gd`、`Scripts/Config/unit_config.gd`
**核心逻辑：** `Scripts/Core/World/unit_manager.gd`、`Scripts/Core/Gameplay/stat_calculator.gd`
**战斗表现：** `Scripts/Systems/Combat/unit_actor.gd`、`unit_controller.gd`
**状态：** 数据层、三级兵种与工资、等级成长、消耗物品晋升、武器攻击距离、马匹骑乘状态、部队查看 UI 待机动画、克制步兵步态、跃马式马腿动画、自由攻击、360°攻击、长矛前后摇与攻击后保持、实体碰撞与临时部件美术完成；招募、装备获取、正式美术与复杂状态机未实现

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
| `display_name` | String | 士兵实例名称（兵种名 + 编号，如“民兵 01”） | `UnitManager` |
| `level` / `exp` | int | 经验等级与经验，持久化 | `UnitManager.add_exp()` |
| `wage` | int | 每日工资，持久化；创建时来自兵种等级，晋升时切换；上下马不变 | `UnitManager` |
| `max_hp` / `current_hp` | int | 生命值 | `UnitManager`（重算时只 clamp）；战斗期间由 `BattleManager` |
| `attack` | int | 攻击力缓存 | `StatCalculator` 经 `UnitManager` |
| `attack_interval` | float | 攻击间隔（秒） | 配置 |
| `move_speed` | float | 小场景移动速度（像素/秒） | 配置 + 等级成长 + 装备 |
| `attack_range` | float | 攻击距离（像素） | 配置 + 等级成长 + 装备 |
| `faction_id` | String | 所属阵营 | `UnitManager` |
| `current_party_id` | String | 当前所属部队 | `PartyManager` |
| `equipment` | Dictionary | 槽位字符串（`WEAPON` 等）→ 装备 ID | `UnitManager.equip_item()` / `unequip_slot()` |
| `is_mounted` | bool | 是否处于骑乘状态；由 `equipment` 是否存在 `MOUNT` 派生，不是独立兵种 | `UnitManager`（装备/重算时同步） |
| `is_player_character` | bool | 玩家角色身份（持久化）；与控制权无关 | 配置 / `UnitManager` |
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

### 3.1 三级兵种与示例配置

士兵按训练程度分为三级，与是否骑马无关：

| tier | 定位 | 基础攻击 | 基础生命 | 每日工资 |
|---:|---|---:|---:|---:|
| 1 | 一般部队 | 10 | 50 | 2 |
| 2 | 受过训练的军士 | 20 | 100 | 5 |
| 3 | 训练有素的小贵族 | 25 | 180 | 10 |

| 文件 | `config_id` | 名称 | tier | HP | 攻击 | 攻击间隔 | 移速 | 射程 | 工资 |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| `Data/Units/infantry_militia.tres` | `infantry_militia` | 民兵 | 1 | 50 | 10 | 1.2 | 60 | 20 | 2 |
| `Data/Units/infantry_trained.tres` | `infantry_trained` | 职业步兵 | 2 | 100 | 20 | 1.0 | 55 | 20 | 5 |
| `Data/Units/infantry_veteran.tres` | `infantry_veteran` | 小贵族 | 3 | 180 | 25 | 1.0 | 55 | 20 | 10 |
| `Data/Units/player_hero.tres` | `player_hero` | 玩家角色 | 1 | 80 | 10 | 0.8 | 75 | 30 | 0 |

- `tier` 与 `level` 是两个维度：tier 决定基础值与工资，level 决定经验成长。
- 骑马只改变 MOUNT 装备状态与移速/移动攻击加成，不改变 tier、基础 HP、基础攻击或工资。
- 晋升链路：民兵 → 职业步兵 → 小贵族；晋升字段见 `UnitConfig.promotion_*`。

### 3.1.1 玩家角色

- 玩家角色是一个普通 `UnitData`，由 `UnitConfig.is_player_character` 标记身份。
- 与普通士兵共用 `UnitManager`、`StatCalculator`、等级/经验、装备、HP 与战斗伤害规则。
- `is_player_character` 持久化；旧存档缺失时默认 false。
- “玩家角色身份”与“当前控制权”分离：
  - 身份由 `is_player_character` 表示；
  - 当前控制权由 `BattleScene._controlled_unit_id` 运行时表示，可切换到其他存活友军。
- 新游戏玩家部队：3 民兵 + 3 名装备马匹的职业步兵 + 1 玩家角色，共 7 人；玩家角色最后加入。3 名骑乘单位中 2 名为本阶段新增的测试骑兵。
- 骑乘职业步兵仍然使用 `infantry_trained` 配置，不新增骑兵 `config_id`；其 `is_mounted` 只表示 MOUNT 装备状态。
- `UnitController` 同时支持 AI 与玩家控制模式；玩家控制不影响 UnitData 本身。

### 3.2 最终属性计算（阶段 3 Step 3）

`StatCalculator` 是运行时属性的唯一计算入口：

```text
最终 HP / 攻击 / 移速 =
    兵种基础值
    + (当前等级 - 1) × 每级成长值
    + 所有已装备物品的对应加成

基础射程 =
    若 WEAPON 装备的 weapon_attack_range > 0：
        武器攻击距离
    否则：兵种 attack_range
最终射程 = 基础射程 + 等级成长 + 所有装备 attack_range_bonus

最终攻击间隔 = 兵种基础攻击间隔（本次不接入装备或百分比加成）

骑乘移动攻击加成 =
    若 is_mounted 且正在移动：
        clamp(floor((最终 move_speed - 60) × 0.1), 0, 5)
    否则 0

单次攻击力 = max(1, attack + 骑乘移动攻击加成)
```

- 加成集中配置在 `StatCalculator`：`MOUNT_CHARGE_SPEED_THRESHOLD = 60`、`MOUNT_CHARGE_ATTACK_PER_SPEED = 0.1`、`MOUNT_CHARGE_MAX_BONUS = 5`。
- 使用 `UnitData.move_speed`（已包含装备与等级成长）而不是重新读取配置基础值。
- 停止移动时调用方传 `is_moving = false`，加成立即为 0；步兵即使移动也永远为 0。
- `compute_effective_attack(unit, is_moving)` 是玩家与 AI 共用的攻击力入口。

- `compute_final_stats(unit, config, equipment_configs = {})`：
  - `equipment_configs` 为 `{ equipment_id: EquipmentConfig }`，由 `UnitManager` 传入。
  - 等级被钳制在 `1..max_level`，超过上限的旧存档等级不会继续放大属性。
  - 缺失或槽位不匹配的装备被忽略；`UnitManager` 会在重算前上报并清理无效引用。
- `apply_to_unit(unit, config, equipment_configs = {})` 写入属性缓存，只对 `current_hp` 做上限 clamp，不重置当前生命。
- `UnitManager.create_unit()` 调用 `apply_to_unit()` 后显式设置 `current_hp = max_hp`，并清空 `current_party_id`。

HP 安全规则：

| 场景 | 结果 |
|---|---|
| 当前 HP 20 / 上限 30，升级后上限 35 | 当前 HP 仍为 20 |
| 当前 HP 38 / 上限 40，卸下装备后上限 30 | 当前 HP clamp 为 30 |
| 新建单位 | 显式设置为满血（唯一会自动回满的入口） |

### 3.3 等级成长配置

`UnitConfig` 新增（只读模板，不保存单个士兵状态）：

| 字段 | 默认 | 说明 |
|---|---:|---|
| `max_level` | 10 | 最高等级 |
| `base_exp_to_next_level` | 100 | 1 级升 2 级所需经验 |
| `exp_growth_per_level` | 50 | 每级增加的经验需求 |
| `hp_per_level` | 5 | 每级最大 HP 成长 |
| `attack_per_level` | 1 | 每级攻击成长 |
| `move_speed_per_level` | 0 | 每级移速成长 |
| `attack_range_per_level` | 0 | 每级射程成长 |

升级所需经验：

```text
exp_to_next_level(level) = base_exp_to_next_level
                         + (level - 1) × exp_growth_per_level
```

民兵示例（tier 1：HP 50 / 攻击 10，每级 +5 / +1）：

| 等级 | HP | 攻击 |
|---|---:|---:|
| 1 | 50 | 10 |
| 2 | 55 | 11 |
| 3 | 60 | 12 |
| 5 | 70 | 14 |
| 10 | 95 | 19 |

职业步兵（tier 2：HP 100 / 攻击 20，每级 +8 / +2）：

| 等级 | HP | 攻击 |
|---|---:|---:|
| 1 | 100 | 20 |
| 3 | 116 | 24 |
| 10 | 172 | 38 |

小贵族（tier 3：HP 180 / 攻击 25，每级 +10 / +3）：

| 等级 | HP | 攻击 |
|---|---:|---:|
| 1 | 180 | 25 |
| 3 | 200 | 31 |
| 10 | 270 | 52 |

- 经验成长与 tier 基础值分离；升级只按 `hp_per_level` / `attack_per_level` 增加。
- 晋升时保留 `level` / `exp`，切换配置后按新 tier 的基础值与成长重算。

### 3.4 经验与升级规则

- 统一入口：`UnitManager.add_exp(unit_id, amount) -> bool`。
- 单位不存在、`amount <= 0`、兵种配置未注册或已满级时返回 `false`，不修改数据。
- 一次增加可触发多次升级，逐级扣除经验。
- 达到 `max_level` 后停止升级，经验归零，不再累积无效经验。
- 升级后自动重算最终属性；当前 HP 保留绝对值，不自动回满。
- 战斗存活/获胜经验已接入；击杀、助攻与最后一击奖励未实现（KI328）。

### 3.5 装备规则

- 槽位：`WEAPON` / `OFFHAND` / `HEAD` / `BODY` / `MOUNT`，每个槽位最多一件。
- `UnitData.equipment` 的键统一为槽位字符串，值为 `EquipmentConfig.equipment_id`。
- 空槽位不存在于字典中，不保存空字符串。
- WEAPON 可配置 `weapon_attack_range`；>0 时覆盖 UnitConfig 基础攻击距离，0 表示不覆盖。
- 装备操作必须先通过：单位存在、装备配置已注册、槽位合法、槽位与配置匹配。
- 同槽位装备直接替换；任意校验失败不产生部分修改。
- `default_equipment` 在创建单位时逐条校验，非法条目报告错误并丢弃，不进入 `UnitData`。
- 数据层使用 `equip_item()` / `unequip_slot()`；阶段 6 起部队面板提供 MOUNT 上下马与晋升，其他装备槽位的更换 UI 尚未实现（KI327）。
- 本次不实现品质、耐久、随机词条、职业限制与装备获取（商店/掉落）。

示例装备（`Data/Equipment/*.tres`，仅数据层测试）：

| ID | 名称 | 槽位 | 加成 |
|---|---|---|---|
| `weapon_sword_01` | 铁剑 | WEAPON | 攻击 +2；攻击距离 14 |
| `shield_wood_01` | 木盾 | OFFHAND | 最大 HP +5 |
| `helmet_iron_01` | 铁盔 | HEAD | 最大 HP +3 |
| `armor_leather_01` | 皮甲 | BODY | 最大 HP +8 |
| `mount_horse_01` | 普通战马 | MOUNT | 移速 +25 |

### 3.5.1 马匹与骑乘状态

- **骑兵不是独立兵种。** 普通士兵装备 `MOUNT` 后进入骑乘状态；卸下后恢复步兵状态。
- `is_mounted` 由 `UnitData.equipment["MOUNT"]` 派生，不允许与装备数据不一致。`UnitConfig.is_mounted` 仅保留为旧数据提示，不能单独创建骑兵。
- 经济路径：`UnitManager.equip_mount(unit_id, equipment_id, profile)` 从 `PlayerProfile` 消耗 1 匹马；`unequip_mount(unit_id, profile)` 把马匹返还库存。
- 库存不足、装备不是 MOUNT、单位已装备同一匹马时失败且不修改数据；替换坐骑时旧坐骑返还库存。
- 同一匹马以库存数量表示，装备时会从库存扣除，因此不会被多个单位同时使用。
- 数据层 `equip_item()` / `unequip_slot()` 仍可操作 MOUNT 槽（测试/内部使用），同样会同步 `is_mounted`。
- 骑乘不改变 tier、工资、职业、等级、经验、身份、基础 HP 与基础攻击；移速和移动攻击加成由 `StatCalculator` 统一计算。
- 旧存档没有 MOUNT 装备时，即使 `is_mounted` 标记为 true 也按步兵处理。
- 当前没有马匹品质、耐久、品种、冲锋方向/碰撞与骑枪机制。

### 3.6 静态配置注册

- `WorldContext.register_static_configs()` 扫描 `Data/Units/`、`Data/Equipment/` 与 `Data/Items/` 下的 `.tres`。
- 新游戏与读档都在 `WorldContext._ready()` 完成注册；重复调用幂等。
- `UnitManager.register_unit_config()` / `register_equipment_config()` 使用 ID 唯一索引，重复 ID 拒绝覆盖。
- Resource 不进入存档，也不在属性计算时反复从磁盘加载。
- `StatCalculator` 不直接访问资源、场景节点或 UI。

### 3.7 UnitManager 数据接口

| 接口 | 作用 |
|---|---|
| `get_unit(unit_id)` | 查询单位 |
| `get_all_units()` | 查询全部单位 |
| `get_unit_config(config_id)` | 查询兵种配置 |
| `get_equipment_config(equipment_id)` | 查询装备配置 |
| `add_exp(unit_id, amount)` | 增加经验并处理升级 |
| `equip_item(unit_id, equipment_id)` | 装备物品（同槽位替换），同步骑乘状态 |
| `unequip_slot(unit_id, slot)` | 卸下指定槽位装备，同步骑乘状态 |
| `equip_mount(unit_id, equipment_id, profile)` | 从物品栏消耗 1 匹马并装备到 MOUNT |
| `unequip_mount(unit_id, profile)` | 卸下 MOUNT 并把马匹返还物品栏 |
| `promote_tier(unit_id, profile)` | 消耗晋升物品，切换更高 tier 配置；保留等级/经验/装备 |
| `recalculate_stats(unit_id)` | 重算最终属性，只 clamp 当前 HP |
| `recalculate_all_stats()` | 读档后重算全部单位，返回失败描述 |
| `get_exp_to_next_level(unit_id)` | 查询升级所需经验（供 UI 使用） |

### 3.8 UnitManager 数据安全规则

- 每个 `UnitData` 是独立实例，ID 由 `IdGenerator` 生成。
- `add_unit()` 遇到已存在 ID 时拒绝注册并返回空字符串，不覆盖原单位。
- `remove_unit()` 在 `current_party_id` 非空时拒绝删除；必须先经 `PartyManager.remove_member()`。
- `remove_unit()` 成功返回 `true`，单位不存在或仍被部队引用返回 `false`。
- `load_from_dict()` 遇到重复单位 ID 时报告错误并跳过后续记录，避免静默覆盖。
- 单位归属只由 `PartyManager` 写入；`UnitManager` 不修改 `PartyData`。

## 4. 表现层

### 4.1 当前实现：人物/马匹分组 + 统一组合

战斗场景使用 `art/我的骑砍临时美术/` 中实际存在的 48×96 PNG 部件，尚未替换为正式美术：

| 节点/类 | 职责 |
|---|---|
| `PartVisual`（Node2D） | 通用部件管理：贴图加载、Sprite2D 创建、命名、整体朝向、缺失素材一次性警告 |
| `HumanVisual`（PartVisual） | 人物影子、左右腿、身体、罩袍、头部、缨饰、长矛枢轴与攻击动画 |
| `HorseVisual`（PartVisual） | 骑马影子、四条独立马腿、马身、马鞍、马头 |
| `UnitVisual`（Node2D） | 统一组合 HumanVisual + HorseVisual，读取 UnitData 的阵营与骑乘状态 |
| `VisualLayers` | 跨人物/马匹组的最终 z 层级集中配置 |
| `UnitActor`（Node2D） | 持有 UnitVisual，绘制血条、名称、控制金圈与攻击闪光 |
| `UnitController`（RefCounted） | AI 移动/索敌/攻击，或玩家 WASD/左键控制；队形槽位、局部避让、受伤与死亡 |

- 人物与马匹贴图分别管理，但两个组都是 `UnitVisual` 的直接子节点（z_index = 0），因此 `VisualLayers` 的相对 z 可以跨组形成最终遮挡。
- `UnitActor.z_index = 200`，高于战场背景；部件使用相对负 z，实际 canvas z = `200 + 部件 z`。这是避免“只有血条/名称/选中圈、没有士兵本体”的关键。
- 人体双腿始终创建，不因骑乘状态隐藏或删除；骑乘时由马身/马鞍按层级自然遮挡。
- 四条马腿是四个独立 Sprite2D（马前腿 1/2、马后退 1/2），可独立调整。
- 人物影子/骑马影子互斥：步行显示 `FootShadow`，骑乘显示 `MountShadow`；马匹表现组整体按骑乘状态显隐。
- 当前 `art/` 没有独立缨饰/独立罩袍贴图。罩袍层复用身体贴图的蓝色区域，由 `Shaders/faction_tabard.gdshader` 按阵营着色；`Plume` 保留独立插槽，路径为空或素材缺失时不显示。
- 任何部件缺失都只跳过该 Sprite2D；同一部件/路径只警告一次，不影响其他部件、单位创建、属性、碰撞、攻击范围与移动。
- `UnitActor` 不修改 `UnitData.current_hp`，只读取静态属性与 `BattleUnitState.battle_hp`。
- 死亡时 `UnitActor` 被场景移除，`BattleUnitState` 保留到 `BattleManager` 结算。

### 4.2 最终可见性层级

`VisualLayers` 按“越靠前数值越大”集中定义，人物/马匹组共用：

| 顺序（前→后） | 部件 | z |
|---:|---|---:|
| 1 | 武器（长矛枢轴） | -10 |
| 2 | 马头 | -20 |
| 3 | 缨饰（有素材时） | -30 |
| 4 | 人头部 | -40 |
| 5 | 人身体 | -50 |
| 5.1 | 阵营罩袍层（紧贴身体前方） | -49 |
| 6 | 人右腿 | -60 |
| 7 | 马鞍 | -69 |
| 8 | 四条马腿（独立，位于马身之前） | -71 |
| 9 | 马身体 | -72 |
| 10 | 人左腿 | -80 |
| 11 | 人物影子 / 骑马影子（互斥） | -99 |

```text
UnitActor (Node2D)
├── UnitVisual (Node2D)
│   ├── HumanVisual (Node2D, 骑乘时 position.y = -15)
│   │   ├── FootShadow
│   │   ├── LegLeft / LegRight
│   │   └── UpperBody (Node2D, 待机/跑动起伏与轻微倾斜)
│   │       ├── Body
│   │       ├── Tabard
│   │       ├── WeaponPivot → Weapon
│   │       ├── Head
│   │       └── Plume（素材存在时）
│   └── HorseVisual (Node2D, 仅骑乘时 visible)
│       ├── MountShadow
│       ├── MountLegFront / MountLegFront2
│       ├── MountLegBack / MountLegBack2
│       └── HorseBodyRig (Node2D, 马身/马鞍/马头一起起伏)
│           ├── MountBody
│           ├── MountSaddle
│           └── MountHead
└── NameLabel
```

- 本阶段按需求把四条马腿移到马身体之前；马鞍保持原层级，人马其他部件关系不变。
- 马鞍与罩袍未在设计表单列：马鞍在马腿/马身之前，罩袍紧贴人身体前方。
- 血条与控制圈由 `UnitActor` 绘制在所有部件之上。

### 4.3 骑乘偏移

- 骑乘时 `HumanVisual.position.y = -15`，人物身体、头部、双腿、武器、缨饰和人物影子整体上移。
- `HorseVisual.position.y` 保持 0；马匹不随人物偏移移动。
- `UnitActor` 的世界坐标、碰撞、攻击距离、移动和队形位置完全不变。
- 步行时人物偏移恢复为 0，马匹组隐藏，人物影子显示。
- 状态切换由 `UnitVisual.set_mounted()` 原地更新显隐和偏移，不重建节点，避免跳位/闪烁。
- `UnitActor` 每帧对比 `UnitData.is_mounted` 与表现状态；装备/卸下马匹后自动切换，战斗中不会残留马匹组或错误偏移。

### 4.3.1 待机/跑动动画

`UnitActor` 根据**实际位移速度**判断视觉状态：

- 速度达到 `8 px/s` 进入跑动；停止后保留 `0.12s` 缓冲再回待机。
- `UnitVisual` 维护共享的 idle/run 时间轴，并以 `0.18s` 平滑混合，避免待机/跑动瞬间切换。
- 人物：
  - `UpperBody` 独立节点负责身体/头部/罩袍/武器的起伏与轻微倾斜；
  - 待机起伏幅度 `0.8`、周期 `2.4s`；跑动幅度 `2.2`、周期 `0.5s`；
  - 头部跟随身体，并有独立微摆：待机 `0.015 rad`、跑动 `0.006 rad`；
  - 武器独立摇摆：待机 `0.02 rad`、跑动 `0.055 rad`；
  - 双腿挂载在 `UpperBody` 下，先继承身体整体位移/旋转，再叠加自身局部步态；不再作为与身体并列的独立动画层。
  - 跑动时左右腿使用同一振幅、相反相位的水平步态（`RUN_LEG_SWING_X = 0.2 px`，相位差 π），抬脚 `RUN_LEG_LIFT_Y = 0 px`、局部旋转 `0.005 rad`；腿部只保留极小辅助动作。
  - 腿部旋转中心累计向下移动 `LEG_PIVOT_DROP_Y = 6.0 px`：实际历史只应用过上一轮 3 px，本轮再 +3 px，因此实际累计为 6 px 而非 9 px。`PartVisual.lower_part_pivot()` 将 Sprite `offset.y` 减少 6、节点基础位置 y 增加 6，可见位置保持不变；动画位置以 `LEG_REST_POSITION = (0, 6)` 为基准；
  - 待机时双腿平滑回到默认位置；人物影子不参与动画。
- 马匹（整体跃动为主，跃马式四肢辅助）：
  - `HorseBodyRig` 负责马身/马鞍/马头一起起伏；待机幅度 `0.9`、周期 `2.4s`；跑动幅度 `4.2`（由 `5.6` 下调，保留跃动但降低整体上下波动）、周期 `0.50s`；
  - 伸展阶段马身整体向上跃起，收缩阶段向下回落；同时产生前后俯仰 `0.028 rad`、横向拉伸 `2.8%`、纵向压缩 `1.2%`，避免橡皮式过度缩放；
  - 四条马腿挂载在 `HorseBodyRig` 下，先继承马身的整体跃动/俯仰/缩放，再叠加组内局部动作；
  - 两只前腿作为一组同步向前伸展，两只后腿作为一组同步向后伸展；随后两组同时收缩。组内保留 `0.12 rad` 极小错位；
  - 马腿局部前后伸展 `0.6 px`、旋转 `0.02 rad`，上下位移 `0 px`；比上一版更明显，但仍只做辅助表现；待机时前后位移归零；
  - 四条马腿的旋转中心累计向下移动 `LEG_PIVOT_DROP_Y = 9.0 px`（3 px + 3 px + 3 px），左右前腿规则一致、左右后腿规则一致；动画位置以 y=9 为基准，可见位置不变；
  - 马头随身体起伏，独立摆动 `0.040 rad`、独立起伏 `0.55 px`，不超过身体整体运动；待机保留原有呼吸与摆头；
  - 骑马影子：不改变资源、层级与位置；马身抬高时按抬升比例轻微缩小（最多 `4%`）并变淡（最多 `15%`），回落时恢复。使用平滑的 body offset 驱动，不产生跳动/闪烁。
  - 人物与马匹周期同步，骑手整体跟随马身垂直偏移。
- 挂载关系：人物双腿是 `UpperBody` 的子节点，马腿是 `HorseBodyRig` 的子节点；两个父节点 `z_index = 0`，因此现有 `VisualLayers` 的最终遮挡关系不变。每帧先设置父级整体变换，再设置腿部局部变换，不做 Transform 累加。
- 骑手跟随：`UnitVisual` 先推进 `HorseVisual`，再把 `get_body_offset_y()` 传给 `HumanVisual.update_locomotion()`；骑乘人物整体 `y = -15 + 马身偏移`，上半身只保留 `20%` 的独立起伏，避免双重弹跳。骑手不跟随马身的缩放/俯仰，只跟随主要垂直跃动。
- 攻击优先：前摇/戳击阶段由攻击动画控制武器旋转与前后位移；攻击后的保持阶段也不应用待机/跑动主角度，只允许在恢复完成后回到轻微摇摆。
- 人物与马匹使用同一共享时间轴，骑乘时动作协调。

### 4.4 视角、朝向与长矛旋转

- 小场景为横版侧视 + 纵深移动，按 `position.y` 进行 Y 排序。
- 默认朝左；朝右时对 `HumanVisual` / `HorseVisual` 整体设置 `scale.x = -1`，不是逐 Sprite 翻转，保证部件相对位置和武器枢轴不偏移。
- 长矛实际贴图为 48×96，设计原点左下角：
  - 长矛自身枢轴 `(24,18)` → 素材左上角坐标 `(24,78)`。
  - 设计稿身体锚点 `(33,18)`（左下角原点）映射到当前 48×96 身体画布：`(33-24, 78-92) = (9,-14)`。
  - `HumanVisual` 用独立的 `WeaponPivot` 放在 `(9,-14)`；长矛 Sprite 的 `offset = (-24,-78)`，使枢轴像素正好落在枢轴节点原点。
  - 枢轴与长矛都在 HumanVisual 内，骑乘 15 像素偏移同时作用于两者，相对锚点不变。
- 长矛动画参数集中在 `HumanVisual`：
  - 待机角度 `0`；攻击目标角度由 `UnitController` 提供的世界攻击方向换算到人物局部：
    - 朝左基准下左 `-PI/2`、右 `+PI/2`、上 `0`、下 `PI`，斜向按 `atan2(local.x, -local.y)` 计算。
    - 朝右时人物整体 `scale.x = -1`，局部方向先镜像，旋转后矛尖仍指向世界攻击方向。
  - 前摇 `0.14s`：沿攻击方向的反方向后移 `2.5 px`，同时旋转到攻击角度（例如向左攻击先向右后移）；
  - 戳击 `0.14s`：沿攻击方向前伸 `6.0 px`；任意 360°方向（含斜向）都由局部攻击方向计算前后位移；
  - 攻击后保持 `4.0s`（`SPEAR_POST_ATTACK_HOLD_TIME`，配置范围 3–5 秒）→ 平滑恢复 `0.35s`，位置与旋转同时回到握持锚点；
  - 只有前摇/戳击阶段锁定人物朝向；攻击后保持阶段允许移动与转身，移动动画不会覆盖长矛主角度或前伸位置。
- 伤害仍即时结算；动画不产生伤害、不改变冷却、攻击范围或攻击力。
- 连续攻击可在动画任意阶段（包括保持阶段）重新触发；新攻击立即衔接并重新计算保持时间，不要求先回到竖直。
- 当前没有受击硬直、正式命中动画与正式资源；腿部行走动画为程序化步态。

### 4.5 大地图部队预览

`UnitDetailPanel` 在士兵详情中增加独立 `SubViewport` 预览：

- 复用 `UnitVisual`，按选中 `UnitData` 的真实骑乘状态与阵营生成外观。
- 预览不创建 `UnitData`、不进入 BattleScene、不参与 AI/碰撞/攻击/移动，不修改装备、HP、库存或存档。
- `SubViewport` 透明背景 + 面板背景；选中士兵切换时复用同一个预览节点并重建部件，旧部件由 `clear_parts()` 释放。
- 步兵显示人物影子；骑兵显示骑马影子、四条马腿、马身/马鞍与上移 15 像素的人物。
- `UnitDetailPanel._process()` 直接调用同一个 `UnitVisual.update_locomotion(delta, false)`，复用战斗待机动画；不建立第二套 UI 动画系统。
- 切换预览对象时调用 `UnitVisual.reset_locomotion()`，从干净的待机相位开始；面板不可见时提前返回，不推进高频动画更新。
- `SubViewport` 使用 `UPDATE_WHEN_VISIBLE`；反复切换只重建部件，不累积预览节点。

### 4.6 阴影

- 阴影独立于单位身体，跟随地面位置。
- 步行使用人物影子，骑乘使用骑马影子；两者互斥。
- 阴影不参与攻击判定。

## 5. UnitController

### 5.0 当前实现

- AI 每 `0.3` 秒重新评估目标（1000 像素内）；已在有效攻击区域内时不因重新索敌打断攻击。
- AI 行为状态：`SEEK`（无目标）→ `APPROACH`（区域外继续接近）→ `ATTACK`（区域内，冷却中保持位置）；目标死亡/失效回到 `SEEK`。
- 攻击有效性统一由 `CombatRules` 判断：存活、敌对战斗侧、冷却结束、目标在**沿攻击方向旋转的矩形**内。
  - 矩形前向长度 = 最终 `attack_range` + 2×身体半径(26) + 武器向前加成(6)；横向半宽 22。
  - 攻击者背后的目标永远排除；矩形外的目标不被命中。
  - 玩家攻击方向来自鼠标世界坐标；AI 方向来自攻击者→当前目标。
- 每次攻击最多命中一个目标；矩形内多个目标由玩家按点击位置、AI 按当前目标选择一个。
- 伤害 = `StatCalculator.compute_effective_attack(unit, is_moving)`，包含骑乘移动加成；只写入选中目标 `BattleUnitState.battle_hp`。
- 攻击冷却属于攻击者。多名单位可以同时攻击同一目标，伤害逐次独立结算；受击状态不阻塞其他攻击者。
- 玩家左键攻击是自由攻击：无论矩形内是否有敌人，都播放完整长矛动画并进入冷却；只有选中有效目标时才结算伤害。空挥记录空目标，不虚构目标。
- 战斗移动速度：步兵 = `UnitData.move_speed × 0.6`（民兵 36 / 职业步兵 33 / 玩家角色 45）；骑乘使用 `BATTLE_MOUNTED_MOVE_SPEED_MULTIPLIER = 0.84`（民兵 71.4 / 职业步兵 67.2 / 玩家角色 84）。大地图部队速度不受影响。
- 实体碰撞：与 `nearby_controllers` 保持最小中心间距 `28`；作为最后空间约束，与局部避让协同。死亡单位不参与碰撞。
- HP 归零后停止移动、攻击与受伤；场景移除表现节点。
- `command_player_units()` 仅保留为旧测试/调试入口。
- 攻击仍为即时命中；长矛旋转动画是纯视觉表现，不是伤害前摇。尚未实现受击硬直、正式命中动画、寻路与显式攻击槽位分配。

### 5.1 规划状态机

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
1. 通过 CombatRules 检查存活、敌对、冷却与射程
2. AI 取当前目标；玩家取点击位置附近最近的有效敌人（一次只取一个）
3. 校验通过后立即结算伤害
4. 播放攻击闪光
5. 攻击者进入 attack_interval 冷却
```

- 攻击方向：玩家来自鼠标世界坐标，AI 来自攻击者→目标，支持 360°与斜向。
- 当前是即时命中：视觉上有前摇/戳击位移，但伤害与目标校验仍在攻击触发时完成，不会对已死亡/离开射程的目标造成伤害，也不存在前摇中断/重复结算问题。
- 伤害结算写 `BattleUnitState`，不直接写 `UnitData`。
- 受击表现与伤害结算分离；当前没有受击硬直或目标级受击锁。

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
| `UnitConfig` | 已实现：tier、工资、晋升链路 |
| 三种示例兵种 `.tres` | 已实现：民兵 / 职业步兵 / 小贵族 |
| 三级兵种基础属性 | 已实现：10/50、20/100、25/180 |
| 士兵工资 | 已实现：配置 + `UnitData.wage` + 部队总额；不自动扣除 |
| 消耗物品晋升 | 已实现：`promote_tier()` + 部队面板按钮 |
| `UnitManager` 生成单位 | 已实现：独立实例、唯一 ID、满血出生 |
| 重复 ID 防护 | 已实现：`add_unit` 拒绝覆盖，读档跳过重复并报错 |
| 删除归属约束 | 已实现：已归属单位禁止直接删除 |
| `StatCalculator` | 已实现：兵种基础 + 等级成长 + 装备加成，HP 安全 clamp；骑乘移动攻击加成 |
| 等级与经验 | 已实现：`add_exp` 多级升级、满级停止、持久化 |
| 装备配置与槽位 | 已实现：5 个槽位、注册/查询、装备/卸下、默认装备校验 |
| 马匹库存与骑乘 | 已实现：`equip_mount` 消耗、`unequip_mount` 返还、库存不足失败、MOUNT 派生 `is_mounted` |
| 骑兵兵种 ID | 不新增；普通兵种 + MOUNT 装备 |
| 配置注册 | 已实现：`WorldContext` 扫描 `Data/Units` 与 `Data/Equipment` |
| 部队管理 UI | 已实现查看 + 上马/下马 + 晋升，见 [Party_System.md](Party_System.md) |
| 完整装备更换 UI | 未实现（KI327）；当前只提供 MOUNT 与晋升操作 |
| 战斗经验来源 | 已实现：战斗存活/获胜经验，经 `add_exp()` 升级 |
| 成员归属 | 由 `PartyManager` 维护，见 [Party_System.md](Party_System.md) |
| `UnitActor` | 已实现：`UnitVisual` 部件、血条、名称、玩家控制金圈、攻击闪光；`z_index = 200` 高于战场背景 |
| `PartVisual` / `HumanVisual` / `HorseVisual` | 已实现：人物与马匹分组管理；`VisualLayers` 统一最终层级；人体双腿始终创建 |
| `UnitVisual` | 已实现：临时 PNG 组合、骑乘 15 像素偏移、影子互斥、四条独立马腿、阵营罩袍着色、整体朝向、缺失素材回退 |
| 长矛枢轴/动画 | 已实现：48×96 素材、枢轴 (24,18)、360°方向旋转、前后摇位移、4 秒保持、平滑恢复；伤害仍即时 |
| 步兵/骑兵待机与移动动画 | 已实现：双腿挂载并继承身体整体运动；马身整体跃动（幅度已下调）为主、马腿局部动作适度增大、骑手跟随；骑马影子随抬升轻微缩小/变淡；人物腿枢轴 6 px、马腿枢轴 9 px |
| 部队 UI 预览动画 | 已实现：复用 UnitVisual.update_locomotion，步兵/骑兵分别播放待机动画，不可见时停止更新 |
| 360°定向矩形攻击 | 已实现：鼠标/目标方向、旋转矩形、背后排除、单次单目标 |
| 武器决定攻击距离 | 已实现：`EquipmentConfig.weapon_attack_range` 覆盖单位基础射程，空手/默认长矛使用 UnitConfig |
| 实体碰撞 | 已实现：最小中心间距 28 + 局部避让；死亡单位不阻挡 |
| 部队面板美术预览 | 已实现：SubViewport 复用 UnitVisual，按真实 UnitData 生成步兵/骑兵外观 |
| `UnitController` | 已实现 AI 与玩家双模式、统一攻击规则、攻击冷却、队形槽位与局部避让 |
| 多人围攻 / 独立冷却 | 已实现；攻击者拥有冷却与目标，无目标级攻击锁 |
| WASD 移动 / 左键攻击 | 已实现；斜向归一化、攻击间隔与范围校验；空点击不消耗冷却 |
| AI 搜索/接近/攻击/重新索敌 | 已实现（`AIState`）；射程外不空刀，外围进攻点分散站位 |
| 玩家角色身份 | 已实现 `is_player_character`，参与存档 |
| 控制权切换 / 观战 | 已实现，见 [Combat_System.md](Combat_System.md) |
| 部件视觉与动画 | 临时部件、待机/跑动动画、长矛 360°攻击/恢复动画已接入；受击动画与正式资源 TODO |
| 受击硬直 / 命中动画 | 未实现（KI124）；长矛动画不改变即时命中规则 |
| 初始世界/招募生成士兵 | 已用临时测试兵力打通；玩家部队含 3 名骑乘测试士兵（本阶段新增 2 名）；招募系统 TODO |

## 9. 待确认

- 攻击距离现为 360°定向矩形：前向 `attack_range + 26 + 6`，横向半宽 22；后续可按武器配置不同矩形宽度/形状。
- 战斗移动速度：步兵 `0.6`、骑乘 `0.84`；初始部署边距 `160`。后续仍可能按兵种/武器继续平衡。
- 实体碰撞为“最小间距推开”而非物理刚体；后续可在不破坏队形/攻击判定的前提下替换为物理层。
- 待机/跑动动画的幅度、周期、武器摇摆、马身压缩与跃马四肢伸展仍需实际手感微调。
- 纵向移动速度是否低于横向。
- 单位碰撞层与阵营过滤的具体配置。
- 大量单位时是否使用对象池。
- 各兵种成长曲线的最终平衡值；是否引入百分比加成与攻击间隔装备加成。
- 跨阵营招募、俘虏与叛变的单位归属规则（KI119）。
- `joined_at_game_time` / 招募来源字段的实际写入时机。
- 伤害公式（当前直接使用 `attack`，无防御/护甲）。
- 阵亡单位永久删除是否合适，何时引入伤兵/俘虏数据。
- 马匹品质/耐久/品种、骑枪冲锋与移动攻击加成的最终平衡值。
- 独立缨饰与独立阵营罩袍贴图的来源；当前使用身体贴图蓝色区域着色。
- 设计稿人物身体为 96×32，当前临时素材实际为 48×96；长矛枢轴按实际素材映射为画布 `(9,-14)`，后续正式素材需重新核对锚点。
- 长矛前摇/戳击/保持/恢复时长、位移距离与最终美术的平衡；马腿已改为前后成组跃马，但仍非骨骼/逐帧动画。
- 部队预览区域尺寸、缩放与装备差异化外观（当前所有武器都显示长矛占位）。
- 玩家移动命令是否改为选中单位、阵型站位或拖拽框选。
