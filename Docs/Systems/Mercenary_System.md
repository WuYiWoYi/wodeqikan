# 雇佣兵系统

**核心数据：** `Scripts/Entities/Mercenary/mercenary_data.gd`、`UnitData.is_mercenary`
**核心逻辑：** `Scripts/Core/World/mercenary_manager.gd`
**配置：** `Scripts/Config/recruitment_config.gd`、`Data/Recruitment/recruitment_config.tres`
**兵种配置：** `Data/Units/mercenary_*.tres`
**UI：** `Scripts/UI/WorldMap/mercenary_recruit_panel.gd`（独立招募界面与 UnitVisual 预览）、`Scripts/UI/WorldMap/tavern_panel.gd`（入口）、`Scripts/UI/Party/unit_detail_panel.gd`（装备锁定提示）
**状态：** 全局雇佣兵池、独立招募界面、等级罩袍/专属缨饰、四类雇佣兵、NPC 领主招募与存档往返已实现；无独立雇佣兵营地/合同期限/解雇流程

---

## 1. 职责与数据所有权

| 数据 | 唯一写入者 | 读取方 |
|---|---|---|
| 全局雇佣兵记录 `MercenaryData` | `MercenaryManager` | 酒馆 UI、存档、NPC 招募 |
| 雇佣兵单位 `UnitData.is_mercenary` | `MercenaryManager` 创建时写入 | `UnitManager` 装备校验、部队详情 UI |
| 招募价格 / 日薪 / 池参数 | `RecruitmentConfig`（Resource） | `MercenaryManager`、酒馆 UI |
| 兵种基础数值与 `daily_wage` | `UnitConfig`（`.tres`） | `UnitManager`、`MercenaryManager` |
| 雇佣兵是否入队 | `PartyManager.add_member` | 部队面板、战斗 |
| 雇佣兵外观快照 `MercenaryData.appearance` | `MercenaryManager`（按稳定 `mercenary_id` 生成并持久化） | 酒馆预览、招募单位、存档 |

- 雇佣兵池独立于酒馆场景：每个 `MercenaryData` 是一条全局记录，同一时刻只能处于一个状态（`WAITING` / `STATIONED` / `TRAVELING`）。
- 一个雇佣兵只属于一个城镇酒馆；招募成功后记录从池中删除，不会重新出现。
- 雇佣兵身份使用显式字段 `UnitData.is_mercenary`，不根据名称或兵种配置推断。旧存档缺少该字段时按 `recruit_source` 回填。
- 外观同样由显式雇佣兵身份决定：`UnitAppearance.build_appearance(..., is_mercenary = true)`，不使用家族罩袍或家族长矛。

## 2. 雇佣兵类型

| 配置 ID | 名称 | tier | 类型 | 初始坐骑 | 日薪 |
|---|---|---:|---|---|---:|
| `mercenary_archer` | 雇佣弓箭手 | 2 | 远程步兵 | 无 | 4 |
| `mercenary_sergeant` | 雇佣军士 | 2 | 近战步兵 | 无 | 4 |
| `mercenary_mounted_sergeant` | 雇佣骑马军士 | 2 | 骑兵 | 有 | 4 |
| `mercenary_rogue_knight` | 无赖骑士 | 3 | 近战步兵 | **无** | 9 |

- 雇佣兵只使用 tier 2 / 3；不生成 tier 1。
- `mounted` 由兵种配置的默认装备是否包含 `MOUNT` 槽派生；无赖骑士没有坐骑，也没有坐骑价格加成。
- 雇佣兵的 `display_name` 使用兵种配置名称，外观由 `MercenaryManager` 按外部配置生成。

### 2.1 雇佣兵外观

| 规则 | 配置/字段 |
|---|---|
| Tier 2 使用 `2级雇佣兵罩袍.png` | `AppearanceConfig.mercenary_tier2_tabard_texture_path` |
| Tier 3 使用 `3级雇佣兵罩袍.png` | `AppearanceConfig.mercenary_tier3_tabard_texture_path` |
| 罩袍变体固定为 `MERCENARY`，不写 `family_id`，不使用家族颜色 | `UnitAppearance.build_appearance()` |
| 不使用家族长矛外观 | `spear_texture_path = ""` |
| 无赖骑士获得专属缨饰 | `mercenary_plume_config_ids = ["mercenary_rogue_knight"]` + `mercenary_plume_texture_path` |
| 其他雇佣兵无缨饰 | `plume_texture_path = ""` |

- 外观在雇佣兵进入池时按 `mercenary_id` 的稳定种子生成，保存到 `MercenaryData.appearance`；酒馆预览与招募后的 `UnitData.appearance` 完全一致，打开多次不会重新随机。
- 旧存档记录缺失外观时由 `get_mercenary_appearance()` 重建一次并写回该记录。

## 3. 价格与工资

| 项目 | 规则 |
|---|---|
| tier 2 基础招募价 | 35 金币 |
| tier 3 基础招募价 | 80 金币 |
| 战斗经验加价 | 2 级 +0、3 级 +10、4 级 +30（按 `level - 2` 累计） |
| 坐骑加价 | 仅 `mounted == true` 时 +30 金币 |
| 日薪 | 来自 `UnitConfig.daily_wage`；经验与坐骑都不改变工资 |

- 统一入口：`RecruitmentConfig.get_mercenary_recruit_cost(tier, level, mounted)`。
- 初始战斗经验从 `[2, 3, 4]` 中按权重 `[0.55, 0.30, 0.15]` 抽取；**不会**生成新兵（1 级）或百战精锐（5 级）。
- 经验只影响招募价，不影响工资、属性或已有战斗经验系统。
- 招募成功后雇佣兵保留池中记录的战斗经验等级与经验值。

## 4. 城镇酒馆招募（玩家）

- 入口：城镇地点面板 → 酒馆 → “招募雇佣兵”。村庄与城堡没有酒馆入口。
- 点击入口后**不嵌套在城镇面板内**：`WorldMap` 隐藏地点面板与嵌入酒馆，打开独立的 `MercenaryRecruitPanel`；关闭后恢复城镇信息面板。
- 列表来源：`MercenaryManager.get_stationed_mercenaries(settlement_id)`。UI 不保存第二份雇佣兵数据。
- 左侧列表每行显示：名称、Tier、骑马/步行、战斗经验文本。
- 右侧详情显示：兵种类型、Tier、战斗经验、骑马状态、招募价、日薪，以及复用 `UnitVisual` 的真实单位预览（装备、罩袍、头盔、缨饰、武器、马匹）。
- 预览单位由 `UnitManager.create_detached_unit()` 创建，不注册进 `UnitManager`、不属于任何部队，因此不会生成可被招募/移动/存档的重复实体。
- 招募按钮在以下情况禁用：玩家部队当前不可用、金币不足。成功招募后列表刷新并保留“已招募”反馈。
- 点击招募调用 `recruit_mercenary_for_player(mercenary_id, settlement_id, profile, party_id)`，统一校验：
  1. 雇佣兵仍在池中且驻留于该城镇；
  2. 地点仍是城镇酒馆；
  3. 玩家部队存在且可接受新成员；
  4. 玩家金币足够。
- 成功时原子完成：创建真实 `UnitData` → 加入玩家部队 → 扣除金币 → 删除池记录 → 用待分配雇佣兵补位 → 广播 `EventBus.mercenary_recruited`。任一步失败都会回滚，不扣金币、不产生单位、不改变池。
- 招募后的雇佣兵不会再回到池中。

## 5. 全局雇佣兵池

### 5.1 初始与增长

- 新游戏初始化时生成 `mercenary_initial_count`（默认 10）名雇佣兵；读档恢复存档中的池，不重复生成。
- 每经过 `mercenary_growth_interval_hours`（默认 12 游戏小时）新增 1 名。
- 新增记录先进入 `WAITING`，随后由 `_assign_all_waiting()` 分配到有空位的城镇酒馆。

### 5.2 酒馆容量与流转

- 每个城镇酒馆容量 `mercenary_tavern_capacity`（默认 7）；计数包含已驻留和正在前往该城镇的记录。
- 所有酒馆都满时，新雇佣兵保持 `WAITING`，**不丢失、不重复**；空位出现后立即补位。
- 每经过 `mercenary_flow_interval_hours`（默认 24 游戏小时），按 `mercenary_flow_chance`（默认 0.25）尝试让驻留雇佣兵前往另一个有空位的城镇，途中状态为 `TRAVELING`，耗时 `mercenary_travel_hours`（默认 2 游戏小时）。
- 抵达时若目标酒馆已满，则回到 `WAITING` 并重新分配；不会出现同一雇佣兵同时驻留两个酒馆。
- 流转只在数据层完成；大地图上不为雇佣兵绘制图标。

### 5.3 类型分布

- 类型 ID 与权重由 `RecruitmentConfig.mercenary_type_ids` / `mercenary_type_weights` 配置，默认 3:3:2:1。
- 雇佣兵数量、经验与类型都在 `MercenaryManager` 内生成，酒馆不能自行创建雇佣兵。

## 6. NPC 领主招募

- 使用与玩家相同的池、价格、工资和原子招募入口 `recruit_mercenary_for_party`。
- 低优先级：每 `npc_mercenary_recruit_interval_hours`（默认 6 游戏小时）检查一次，按 `npc_mercenary_recruit_chance`（默认 0.25）决定是否尝试。
- 条件：存活的非玩家贵族、部队可用且人数低于 `npc_mercenary_party_size_threshold`（默认 18）、位于某城镇 `npc_mercenary_town_radius`（默认 40）范围内、该酒馆有驻留雇佣兵。
- 支付前要求金币至少为“价格 + `npc_mercenary_gold_reserve`（默认 50）”。
- 每次检查最多招募 `npc_mercenary_recruit_max_per_check`（默认 1）名。
- 玩家正在查看的酒馆会被跳过，避免与玩家争抢同一列表。

## 7. 装备与坐骑限制

- `UnitData.can_manage_equipment()` 对雇佣兵返回 `false`。
- `UnitManager` 的 `equip_item`、`unequip_slot`、`equip_mount_instance`、`unequip_mount`、`equip_item_from_holder`、`unequip_slot_to_holder` 统一拒绝雇佣兵并给出 warning。
- 部队详情面板对雇佣兵隐藏“装备管理”和“坐骑管理”，显示“雇佣兵装备与坐骑由契约固定，无法更换。”。
- 限制只针对雇佣兵；普通招募士兵与封地征召士兵仍可更换装备与坐骑。
- 雇佣兵已有的默认装备、属性与战斗表现不受限制影响。

## 8. 存档

- Schema v9 新增 `mercenaries`：
  - `initialized`：是否已完成首次生成；
  - `growth_elapsed` / `flow_elapsed` / `npc_recruit_elapsed`：各自计时器；
  - `records`：每个雇佣兵的 `mercenary_id`、`config_id`、`display_name`、`tier`、`level`、`exp`、`mounted`、`state`、`settlement_id`、`destination_settlement_id`、`travel_remaining`、`spawned_at`、`appearance`。
- `appearance` 为 v10 追加的持久化快照；旧记录缺失时按 `mercenary_id` 稳定重建，保证预览与招募一致。
- 读档时去重 `mercenary_id`；无效配置、无效城镇或超容量记录回退为 `WAITING` 并重新分配。
- v8 及更早存档没有 `mercenaries`：读档后在 `WorldContext` 中执行一次初始生成（`initialize_world(true)`），之后 `initialized = true`，不会重复补发。
- 已招募的雇佣兵只作为普通 `UnitData` 保存在 `units` 中，不从存档重新进入池。

## 9. 关键接口

| 接口 | 说明 |
|---|---|
| `initialize_world(seed_initial)` | 新游戏/旧档首次生成；幂等 |
| `tick(world_delta)` | 增长、流转、NPC 招募；由 `WorldSimulation` 每 tick 调用 |
| `get_stationed_mercenaries(settlement_id)` | 酒馆列表唯一来源 |
| `get_mercenary_appearance(mercenary)` | 预览/招募共用的持久化外观快照；缺失时重建 |
| `get_recruit_price(mercenary)` / `get_daily_wage(mercenary)` | UI 展示用统一计算 |
| `set_player_viewing_tavern(settlement_id)` | 标记玩家当前酒馆，NPC 跳过 |
| `recruit_mercenary_for_player(...)` | 玩家原子招募 |
| `recruit_mercenary_for_party(...)` | NPC/测试原子招募 |
| `to_dict()` / `load_from_dict(payload)` | 存档往返 |

## 10. 已知限制

- 只有城镇提供酒馆；当前初始化世界的默认城镇数量有限，雇佣兵池在一座城镇内即可达到容量上限，其余保持在 `WAITING`。
- 雇佣兵没有合同期限、解雇、士气或忠诚；不会主动离开部队。
- 流转不经过大地图移动结算，只按世界时间推进；没有雇佣兵图标或旅途事件。
- NPC 招募是简化策略，不评估部队构成或战斗需求。
- 装备锁定是系统规则，暂不提供“违反契约”的额外代价。
