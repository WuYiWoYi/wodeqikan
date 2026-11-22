# 背包、金币与士兵经济系统

**核心数据：** `Scripts/Entities/Item/inventory_data.gd`、`Scripts/Core/World/player_profile.gd`、`Scripts/Entities/Item/mount_instance_data.gd`
**核心逻辑：** `Scripts/Core/World/unit_manager.gd`、`Scripts/Core/World/party_manager.gd`、`Scripts/Core/World/item_manager.gd`、`Scripts/Core/World/market_manager.gd`、`Scripts/Entities/Trade/trade_session.gd`
**状态：** 统一背包、独立马匹实例、金币增减、工资统计、三级兵种与晋升、封地税收缓存、招募费用、完整背包 UI、村庄/城镇双栏交易与 NPC 补给采购已实现；工资扣除尚未执行

---

## 1. 背包（玩家部队共享）

背包由 `PlayerProfile` 表示，属于玩家部队整体，不区分单个士兵。实际存储委托给 `InventoryData`，NPC 部队的 `PartyData` 使用同一个类，避免两套背包规则：

| 字段 | 说明 |
|---|---|
| `gold` | 金币，整数，不低于 0（玩家为 `PlayerProfile.gold`，NPC 为 `PartyData.gold`） |
| `inventory` | 出现过的物品 ID 列表（兼容旧存档/UI 枚举） |
| `stackable_counts` / `item_counts` | `{ item_id: count }`，只保存可堆叠物品 |
| `mount_instances` | `Array[MountInstanceData]`，每匹马独立保存 |

物品 ID 可以来自：

- `EquipmentConfig`（`Data/Equipment/`）：可装备到士兵槽位的物品；`MOUNT` 槽自动视为不可堆叠马匹；
- `ItemConfig`（`Data/Items/`）：消耗品/杂物，例如面包、草料、晋升凭证。

堆叠与个体规则：

- 面包、草料、晋升凭证按数量堆叠；
- 马匹永远独立实例，不使用 `item_counts`；
- 旧存档中的马匹数量会在首次读取时确定性迁移为实例（详见 `Mount_System.md`）。

本阶段不做容量、重量、负重与堆叠上限。

### 1.1 物品配置

新增 `ItemConfig`：

| 字段 | 说明 |
|---|---|
| `item_id` | 唯一 ID |
| `display_name` | 显示名称 |
| `description` | 描述 |
| `item_type` | `CONSUMABLE` / `MISC` |
| `icon_texture_path` | 交易/背包行最左侧图标；空字符串使用占位图标 |
| `is_stackable` | 是否按数量堆叠 |
| `batch_purchase_amounts` | 市场批量购买按钮数量，例如 `[10, 50]` |

`ItemManager` 由 `WorldContext` 持有，启动时扫描 `Data/Items/` 注册；重复 ID 拒绝覆盖。`PlayerProfile` 仍然是玩家持有数量的唯一来源，NPC 则为各自的 `PartyData`。

### 1.2 金币接口

| 接口 | 规则 |
|---|---|
| `add_gold(amount)` | 只接受正数；结果不低于 0 |
| `can_afford(amount)` | 余额是否足够 |
| `spend_gold(amount)` | 数量 <= 0 或余额不足返回 false，不修改金币 |

金币随 `player` 字典保存/读取。战斗胜利奖励仍按 `BattleManager` 原规则发放；阶段 11 起城镇市场是玩家金币的另一个明确来源/去向，统一由 `MarketManager` 结算。

## 2. 马匹与骑乘

- 马匹使用 `EquipmentConfig` 的 `MOUNT` 槽位；不是独立兵种。
- 背包中的马匹由 `InventoryData.mount_instances` 逐匹保存，拥有独立 `instance_id`、毛色与马鞍。
- `UnitManager.equip_mount_instance(unit_id, instance_id, holder)`：
  - 校验单位、实例、MOUNT 槽；
  - 从持有者背包移除该实例；
  - 写入 `UnitData.equipment["MOUNT"]` 与 `UnitData.mount_instance`；
  - 重算属性；失败时把实例放回。
- `UnitManager.equip_mount(unit_id, equipment_id, holder)` 是兼容接口：按装备 ID 取第一匹匹配的马。
- `UnitManager.unequip_mount(unit_id, holder)`：
  - 清空 MOUNT 槽；
  - 把**同一匹马实例**（含外观）返还背包；
  - 重算属性。
- `is_mounted` 始终由 MOUNT 装备派生，不单独信任字段。
- 替换坐骑时旧坐骑实例返还背包，外观不变。
- 同一匹马实例只有一份，不会同时存在于背包与两名士兵身上。
- 骑乘不改变兵种等级、基础攻击、基础生命或工资；移速加成仍由 `EquipmentConfig.move_speed_bonus` 提供。
- UI：部队面板士兵详情逐匹列出背包马匹与外观，所有写操作经过 `UnitManager`。
- 外观与市场规则详见 `Mount_System.md`。

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

## 4.1 封地税收与招募费用（阶段 7 新增）

- 每日税收统一由 `TaxCalculator.compute_daily_tax(population, prosperity, tax_base)` 计算；UI 不实现第二套公式。
- `SettlementData.tax_income_per_day` 是缓存值，读档与征召后重算。
- 当前只展示税收，不按日把金币加入 `PlayerProfile`，也不从封地扣除。
- 冒险者招募：固定 `adventurer_recruit_cost`（默认 1）金币，从玩家金币扣除；失败不扣款。
- 采邑征召：不消耗金币，消耗村庄 `fief_recruitment_stock` 1 组、人口、繁荣度；马匹由配置直接装备，不消耗玩家背包。
- 工资仍只统计，不因征召或税收自动扣除。

## 4.2 玩家背包 UI（阶段 11 新增）

- 入口：大地图顶栏“背包”按钮（`InventoryButton`）。
- 实现：`Scripts/UI/Party/inventory_panel.gd`（`InventoryPanel`）。
- 只读展示 `PlayerProfile`：
  - 当前金币；
  - 物品名称、类型、持有数量；
  - 选中物品的描述（装备显示槽位与属性加成，普通物品显示 `ItemConfig.description`）。
- 同 ID 物品合并为一个条目；数量为 0 的物品不显示。
- 未注册的物品 ID 使用“未知物品（ID）”回退，不导致 UI 崩溃。
- 排序按显示名、再按物品 ID，刷新后顺序稳定。
- 打开时压入 `PAUSE_REASON_UI_PANEL`，关闭时成对释放；不恢复 1x/2x 基础倍率。
- 背包面板不提供任何写操作；上/下马、晋升仍分别经过 `UnitManager.equip_mount()` / `unequip_mount()` / `promote_tier()`。

## 4.3 村庄/城镇交易市场（阶段 11 新增，阶段 12 扩展）

### 地点范围

| 地点类型 | 可售商品 | 入口 |
|---|---|---|
| 村庄 `VILLAGE` | 面包、草料 | 大地图“购买补给”；村长对话“购买补给（面包、草料）” |
| 城镇 `TOWN` | 面包、草料、马匹 | 大地图“交易市场” |
| 城堡 `CASTLE` | 无市场 | 不显示入口，`is_market_settlement()` 返回 false |

- 村庄与城镇共用同一套 `MarketManager`、`MarketData` 与结算规则；两个入口打开的是同一份库存。
- 村庄场景与大地图面板共享库存，任一入口交易后另一入口读到的是结算后的数量。
- 市场库存按地点独立保存，重启或读档后不会重置；城堡永远没有市场数据。

### 数据与职责

| 对象 | 文件 | 职责 |
|---|---|---|
| `MarketGoodsConfig` | `Scripts/Config/market_goods_config.gd` | 商品静态配置：`item_id` / `buy_price` / `sell_price` / `initial_stock` / `is_tradeable` / `scope` / `is_stackable` / `batch_purchase_amounts` |
| `MarketData` | `Scripts/Entities/Settlement/market_data.gd` | 单个地点库存：可堆叠 `stock`、逐匹 `mount_instances`、`initialized_items` |
| `MarketManager` | `Scripts/Core/World/market_manager.gd` | 商品注册、地点校验、库存初始化、原子结算、序列化 |
| `TradeSession` | `Scripts/Entities/Trade/trade_session.gd` | 单次打开市场的预览状态、重置、确认与总额计算 |
| `MarketPanel` | `Scripts/UI/WorldMap/market_panel.gd` | 双栏交易 UI、图标、批量按钮、确认/取消/重置 |

- 商品配置位于 `Data/Market/`，启动时注册；`item_id` 必须关联已注册的 `EquipmentConfig` 或 `ItemConfig`，不按名称匹配。
- `scope` 控制商品出现的地点：村庄与城镇 / 仅城镇；市场面板按地点过滤商品。
- 当前商品：`bread`（买 2 / 卖 1，初始 50）、`fodder`（买 3 / 卖 1，初始 50）、`mount_horse_01`（买 100 / 卖 70，初始 3，仅城镇）。
- `ensure_markets()` 读档时只补充缺失地点或缺失商品，不重置已有库存；卖光的商品不会被补满。

### 交易交互（阶段 12）

- 左侧为市场、右侧为玩家；点击市场行中的物品直接进入右侧预览，点击玩家行中的物品直接回到左侧，不经过独立购物车。
- 马匹逐匹显示：每匹马一个行与一个按钮，绑定 `instance_id`，买卖移动的是具体实例（外观随实例走）。
- 可堆叠商品提供批量购买按钮（`ItemConfig.batch_purchase_amounts`，当前为 10 / 50）；马匹没有批量按钮。
- 每行最左侧固定显示图标：普通物品使用 `ItemConfig.icon_texture_path`，马匹使用 `MountThumbnail` 复用现有马匹贴图。图标框固定 40×40、等比缩放，不挤压文字与按钮；缺少贴图时显示占位。
- “重置交易”把预览恢复到本次打开市场时的快照（不是反向重放），可直接从任意中间状态复位。
- “取消”关闭面板并丢弃全部预览；“确认交易”才调用结算。未确认的预览不写入任何权威数据，也不会进入存档。

### 交易规则

- 预览由 `TradeSession` 按“与打开时快照的差值”计算购买量/出售量与总额；同一物品的买入与卖出互相抵消。
- 确认交易调用 `MarketManager.execute_trade()`（玩家入口封装为 `execute_player_trade()`）：
  1. 校验地点存在且为村庄/城镇、市场存在；
  2. 校验商品可交易、购买价/收购价有效、商品属于该地点范围；
  3. 校验市场库存、玩家背包数量与马匹实例归属；
  4. 计算 `购买总额 - 出售总额`，按净额校验金币；
  5. 保存持有者与市场快照，统一提交背包、马匹实例、市场库存与金币；任一步失败回滚；
  6. 玩家交易成功后写入一条 `PLAYER_TRADE` 世界日志。
- 同一次提交使用唯一 `trade_id`；同一非空 ID 只能成功结算一次，防止重复扣款。
- 市场库存、背包、马匹实例与金币始终由各自唯一数据源持有；交易是它们唯一的一致性变更入口。

### 日志来源区分

- `MarketManager.TradeSource.PLAYER`：成功交易写入 `PLAYER_TRADE` 世界日志。
- `MarketManager.TradeSource.NPC`：阶段 12 起由 `AIManager` 的补给采购调用；成功交易只更新库存/金币，并广播 `EventBus.npc_supply_purchased`，不写玩家世界日志。

## 5. 存档兼容

| 字段 | 旧存档处理 |
|---|---|
| `player.inventory_counts` | 缺失时 `inventory` 每项按 1 件 |
| `UnitData.wage` | 缺失时使用 -1 哨兵；读档重算时按当前 tier 配置补全 |
| `UnitData.equipment["MOUNT"]` | 缺失时按步兵处理 |
| `SettlementData.scene_path` | 缺失时为空；村庄回退到默认场景 |
| `ItemConfig` / `UnitConfig` | 静态模板不进入存档，启动时重新注册 |
| `markets` | 缺失时按当前 `MarketGoodsConfig` 初始化为一次 |
| `SaveData.markets[settlement_id].stock` | 已有库存原样恢复；新商品只补初始值 |
| `SaveData.markets[settlement_id].mount_instances` | 逐匹恢复；旧档数量按确定性实例迁移 |
| `player.mount_instances` / `PartyData.mount_instances` | 旧档数量迁移为独立实例，反复读取结果一致 |
| `UnitData.mount_instance` | 缺失时按 `unit_id + equipment_id` 确定性生成外观 |
| `markets[].initialized_items` | 缺失时视为已初始化，避免读档补满已售罄商品 |
| `SaveData.supply_last_settled_day` | 缺失（v5 及更早）时以存档时刻所在游戏日为起点 |

阶段 12 起存档 Schema 为 v6；v5 及更早存档在读取时执行一次补给初始化（详见 `Save_System.md`、`Supply_System.md`）。

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
| 封地税收缓存 | 已实现（统一 `TaxCalculator`，只展示不扣除） |
| 冒险者金币招募 | 已实现（1 金币，失败回滚） |
| 采邑征召资源成本 | 已实现（储备/人口/繁荣度） |
| 完整玩家背包 UI | 已实现（阶段 11，只读） |
| 村庄/城镇双栏交易市场 | 已实现（阶段 12：左右直接移动、重置、图标、批量） |
| 市场库存独立存档/恢复 | 已实现（`SaveData.markets`，含马匹实例与 `initialized_items`） |
| 玩家交易世界日志 | 已实现（`PLAYER_TRADE`，最多 20 条） |
| NPC 补给采购 | 已实现（阶段 12，`AIManager` + `execute_npc_trade()`，不写玩家日志） |
| 每日面包/草料消耗 | 已实现（`SupplyManager`，见 `Supply_System.md`） |
| 普通兵员招募、负重、拖拽交易 | 未实现 |
