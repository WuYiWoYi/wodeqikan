# 背包、金币与士兵经济系统

**核心数据：** `Scripts/Core/World/player_profile.gd`、`Scripts/Entities/Unit/unit_data.gd`、`Scripts/Config/unit_config.gd`
**核心逻辑：** `Scripts/Core/World/unit_manager.gd`、`Scripts/Core/World/party_manager.gd`、`Scripts/Core/World/item_manager.gd`
**状态：** 基础背包、马匹上/下马、金币增减、工资统计、三级兵种与晋升已实现；工资扣除、商店、招募、物品栏完整 UI 未实现

---

## 1. 背包（玩家部队共享）

背包由 `PlayerProfile` 表示，属于玩家部队整体，不区分单个士兵：

| 字段 | 说明 |
|---|---|
| `gold` | 金币，整数，不低于 0 |
| `inventory` | 出现过的物品 ID 列表（兼容旧存档） |
| `item_counts` | `{ item_id: count }`，数量为 0 时清理 |

物品 ID 可以来自：

- `EquipmentConfig`（`Data/Equipment/`）：可装备到士兵槽位的物品，包括 `MOUNT` 马匹；
- `ItemConfig`（`Data/Items/`）：消耗品/杂物，例如晋升凭证。

本阶段不做容量、重量、负重与堆叠上限。

### 1.1 物品配置

新增 `ItemConfig`：

| 字段 | 说明 |
|---|---|
| `item_id` | 唯一 ID |
| `display_name` | 显示名称 |
| `description` | 描述 |
| `item_type` | `CONSUMABLE` / `MISC` |

`ItemManager` 由 `WorldContext` 持有，启动时扫描 `Data/Items/` 注册；重复 ID 拒绝覆盖。`PlayerProfile` 仍然是持有数量的唯一来源。

### 1.2 金币接口

| 接口 | 规则 |
|---|---|
| `add_gold(amount)` | 只接受正数；结果不低于 0 |
| `can_afford(amount)` | 余额是否足够 |
| `spend_gold(amount)` | 数量 <= 0 或余额不足返回 false，不修改金币 |

金币随 `player` 字典保存/读取。本阶段没有新增金币来源、商店或交易；战斗胜利奖励仍按 `BattleManager` 原规则发放。

## 2. 马匹与骑乘

- 马匹使用 `EquipmentConfig` 的 `MOUNT` 槽位；不是独立兵种。
- 背包中的马匹由 `PlayerProfile.item_counts` 记录数量。
- `UnitManager.equip_mount(unit_id, equipment_id, profile)`：
  - 校验单位、装备、槽位、库存；
  - 从背包扣除 1 匹；
  - 写入 `UnitData.equipment["MOUNT"]`；
  - 重算属性；失败时回滚库存。
- `UnitManager.unequip_mount(unit_id, profile)`：
  - 清空 MOUNT 槽；
  - 把马匹返还背包；
  - 重算属性。
- `is_mounted` 始终由 MOUNT 装备派生，不单独信任字段。
- 替换坐骑时旧坐骑返还背包。
- 同一匹马在数量层面只有一份，不会同时存在于背包与两名士兵身上。
- 骑乘不改变兵种等级、基础攻击、基础生命或工资；移速加成仍由 `EquipmentConfig.move_speed_bonus` 提供。
- UI：部队面板士兵详情提供“装备坐骑/卸下坐骑”与背包马匹下拉框，所有写操作经过 `UnitManager`。

## 3. 三级兵种与工资

### 3.1 等级（tier）与等级（level）区分

- `UnitConfig.tier`：兵种等级，1 / 2 / 3，与是否骑马无关。
- `UnitData.level`：经验等级，1..max_level，继续通过经验提升。
- 骑马只改变 `is_mounted` 与装备属性，不改变 `tier`。

| tier | 定位 | 基础攻击 | 基础生命 | 每日工资 |
|---:|---|---:|---:|---:|
| 1 | 一般部队 | 10 | 50 | 2 |
| 2 | 受过训练的军士 | 20 | 100 | 5 |
| 3 | 训练有素的小贵族 | 25 | 180 | 10 |

示例配置：

| 配置 | tier | 名称 | 基础 HP | 基础攻击 | 每级成长 HP/攻击 |
|---|---:|---|---:|---:|---|
| `infantry_militia` | 1 | 民兵 | 50 | 10 | +5 / +1 |
| `infantry_trained` | 2 | 职业步兵 | 100 | 20 | +8 / +2 |
| `infantry_veteran` | 3 | 小贵族 | 180 | 25 | +10 / +3 |

- 最终属性仍由 `StatCalculator` 计算：`tier 基础值 + (level-1) × 每级成长 + 装备加成`。
- 经验成长与 tier 基础值分离；升级后重算，`current_hp` 只做上限 clamp。

### 3.2 工资

- `UnitConfig.daily_wage`：该兵种等级的每日工资。
- `UnitData.wage`：持久化到士兵本身；创建时来自配置，晋升时切换到新 tier 工资。
- 上下马不改变工资。
- `PartyManager.get_total_wage(party_id)` 汇总当前所有成员的工资；无效成员引用被跳过。
- 部队面板显示金币与部队每日工资总额；士兵详情显示单个士兵工资。
- 本阶段不执行定期扣除，不因工资不足触发离队或士气变化。

## 4. 晋升（消耗品）

- `UnitConfig` 晋升字段：
  - `promotion_item_id`：消耗品 ID；
  - `promotion_item_cost`：消耗数量；
  - `promotion_target_config_id`：目标兵种配置。
- 晋升链路：民兵 → 职业步兵 → 小贵族；小贵族为最高 tier。
- `UnitManager.promote_tier(unit_id, profile)`：
  1. 校验单位、当前配置、目标配置与 tier 递增；
  2. 从背包扣除晋升物品；
  3. 切换 `config_id`；
  4. 保留 `level` / `exp` / 装备 / 骑乘状态；
  5. 切换工资到目标 tier；
  6. 通过 `StatCalculator` 重算最终属性。
- 物品不足、目标配置缺失、已最高 tier 时失败，且不消耗物品、不修改单位。
- `level` 在新配置的 `max_level` 内钳制；满级时经验清空，规则与 `add_exp()` 一致。
- `display_name` 若为“原兵种名 + 编号”格式，则替换前缀为“新兵种名 + 原编号”，保持个体编号不变。
- 晋升凭证 `promotion_rank_token` 使用 `ItemConfig`；没有装备外观。
- 新游戏暂时给予 2 个晋升凭证用于验收；正式获取途径后续实现。

## 5. 存档兼容

| 字段 | 旧存档处理 |
|---|---|
| `player.inventory_counts` | 缺失时 `inventory` 每项按 1 件 |
| `UnitData.wage` | 缺失时使用 -1 哨兵；读档重算时按当前 tier 配置补全 |
| `UnitData.equipment["MOUNT"]` | 缺失时按步兵处理 |
| `SettlementData.scene_path` | 缺失时为空；村庄回退到默认场景 |
| `ItemConfig` / `UnitConfig` | 静态模板不进入存档，启动时重新注册 |

未升级存档 Schema。

## 6. 实现状态

| 项 | 状态 |
|---|---|
| 共享背包与物品数量 | 已实现 |
| `ItemConfig` / `ItemManager` | 已实现（`Data/Items/`） |
| 马匹进入背包/装备/卸下 | 已实现 |
| 同一匹马不重复/不丢失 | 已实现（数量扣除与返还） |
| 金币增加/扣除/保存 | 已实现 |
| 三级兵种基础属性 | 已实现 |
| 经验成长 | 已实现（沿用 `add_exp`） |
| 消耗物品晋升 | 已实现（数据层 + 部队面板按钮） |
| 士兵工资与部队总额 | 已实现（统计/显示，不扣除） |
| 工资定期扣除 | 未实现 |
| 商店、交易、招募、负重 | 未实现 |
| 物品栏完整 UI | 未实现（部队面板只展示可选马匹与晋升物品数量） |
