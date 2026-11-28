# 背包、金币与士兵经济系统

**核心数据：** `Scripts/Entities/Item/inventory_data.gd`、`Scripts/Core/World/player_profile.gd`、`Scripts/Entities/Item/mount_instance_data.gd`
**核心逻辑：** `Scripts/Core/World/unit_manager.gd`、`Scripts/Core/World/party_manager.gd`、`Scripts/Core/World/item_manager.gd`、`Scripts/Core/World/market_manager.gd`、`Scripts/Entities/Trade/trade_session.gd`
**状态：** 统一背包、独立马匹/猪实例、小数金币、工资统计、三级兵种与晋升、封地税收缓存、招募费用、完整背包 UI、村庄/城镇双栏交易、村庄特产与动态库存/按库存比例定价/每日补货、牲畜宰杀与 NPC 补给采购已实现；工资扣除尚未执行

---

## 1. 背包（玩家部队共享）

背包由 `PlayerProfile` 表示，属于玩家部队整体，不区分单个士兵。实际存储委托给 `InventoryData`，NPC 部队的 `PartyData` 使用同一个类，避免两套背包规则：

| 字段 | 说明 |
|---|---|
| `gold` | 金币，浮点数，不低于 0，统一保留两位小数（玩家为 `PlayerProfile.gold`，NPC 为 `PartyData.gold`） |
| `inventory` | 出现过的物品 ID 列表（兼容旧存档/UI 枚举） |
| `stackable_counts` / `item_counts` | `{ item_id: count }`，只保存可堆叠物品，数量为整数 |
| `mount_instances` | `Array[MountInstanceData]`，每匹马独立保存 |
| `item_instances` | `Array[ItemInstanceData]`，猪等非堆叠普通物品逐件保存 |

物品 ID 可以来自：

- `EquipmentConfig`（`Data/Equipment/`）：可装备到士兵槽位的物品；`MOUNT` 槽自动视为不可堆叠马匹；
- `ItemConfig`（`Data/Items/`）：消耗品/杂物，例如面包、草料、晋升凭证。

堆叠与个体规则：

- 面包、草料、肉、鱼、木材、铁、盐、晋升凭证按数量堆叠；
- 马匹永远独立实例，不使用 `item_counts`；
- 猪同样不可堆叠，每头使用独立 `ItemInstanceData`；买卖与宰杀都按具体实例处理；
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
| `add_gold(amount)` | 只接受正数；经 `GoldUtils.normalize` 保留两位小数，结果不低于 0 |
| `can_afford(amount)` | 余额是否足够；使用 `EPSILON` 抵消浮点误差 |
| `spend_gold(amount)` | 数量 <= 0 或余额不足返回 false，不修改金币 |

- 金币是浮点数，允许 0.3 / 0.5 这类价格与余额；物品数量仍是整数。
- 所有金币写入（交易、工资扣除预览、存档、读档）统一经过 `GoldUtils.normalize()`，比较经过 `GoldUtils.can_afford()`；UI 显示统一用 `GoldUtils.format()`，整数不显示小数、小数最多两位并去掉末尾 0。
- 交易总额逐项按小数单价累加，最终净额再归一化；不得在中途截断为整数。
- 金币随 `player` 字典保存/读取（JSON 数字，v11 起明确支持小数）。战斗胜利奖励仍按 `BattleManager` 原规则发放；阶段 11 起市场是玩家金币的另一个明确来源/去向，统一由 `MarketManager` 结算。

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
| 1 | 一般部队 | 10 | 50 | 1 |
| 2 | 受过训练的军士 | 20 | 100 | 3 |
| 3 | 训练有素的小贵族 | 25 | 180 | 7 |

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
- 普通招募统一价格由 `RecruitmentConfig` 提供：Tier1 = 5 金币，Tier3（贵族冒险者）= 400 金币；从招募者金币扣除，失败不扣款。
- 采邑征召：不消耗金币，消耗村庄 `fief_recruitment_stock` 1 组、人口、繁荣度；马匹由配置直接装备，不消耗玩家背包。
- 采邑征召士兵的日薪按 tier 使用 UnitConfig：Tier1 / 2 / 3 = 1 / 3 / 7。
- 新游戏玩家金币为 10000；只影响新游戏，旧存档不补发、不重复发放。
- 工资仍只统计，不因征召或税收自动扣除。

### 4.1.2 雇佣兵价格与工资

- 雇佣兵招募价由 `RecruitmentConfig` 统一计算：Tier2 35、Tier3 80；战斗经验加价 2/3/4 级 = +0/+10/+30；骑乘再加 +30。
- 雇佣兵日薪来自 `UnitConfig.daily_wage`：Tier2 = 4，无赖骑士（Tier3）= 9。
- 经验与坐骑加成只影响招募价，不影响日薪。
- 城镇酒馆招募与 NPC 领主招募都调用同一价格计算和原子结算；详见 [Mercenary_System.md](Mercenary_System.md)。

## 4.1.1 每日收支预览（阶段 13 后续）

- `WorldContext.get_daily_balance_preview()` 提供只读预览，供顶栏金币悬浮使用。
- 收入项来自玩家授权封地的 `SettlementData.tax_income_per_day` 缓存；支出项来自
  `PartyManager.get_total_wage(player_party_id)`。
- 返回 `income_total`、`expense_total`、`net` 与逐项 `items`（标签 + 带符号金额）。
- 该接口只汇总现有缓存，不新增经济公式，也不实际扣除金币；工资与税收的定期结算仍为未实现项。

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
- 背包面板唯一的写操作是牲畜宰杀（见 4.2.1）；上/下马、晋升仍分别经过 `UnitManager.equip_mount()` / `unequip_mount()` / `promote_tier()`。

### 4.2.1 牲畜宰杀（2026-11-28 新增）

- 入口：背包面板选中猪或马时的“宰杀”按钮；是否可宰杀由 `SlaughterManager.can_slaughter(item_id)` 判断。
- 唯一业务入口：`SlaughterManager.slaughter(holder, item_id)`，由 `WorldContext` 装配，UI 只发起意图。
- 规则：
  1. 只接受猪与马；猪必须是不可堆叠的 `ItemInstanceData`。
  2. 从背包移除该具体实例（`take_item_instance` / `take_mount_instance`），增加 20 单位 `meat`。
  3. 增加肉失败时恢复被移除的牲畜实例，避免凭空消失。
  4. 操作不可撤回；同一实例只能宰杀一次，不会重复产出肉。
- 确认文本固定为：“宰杀该牲畜后，将永久失去该牲畜，并获得20单位肉。该操作无法撤回，是否继续？”按钮为“确认宰杀”/“取消”。
- 宰杀不新增持久化字段：牲畜来自背包实例，肉进入可堆叠背包数量，均随现有存档结构保存。

## 4.3 村庄/城镇交易市场（阶段 11 新增，阶段 12 扩展）

### 地点范围

| 地点类型 | 可售商品 | 入口 |
|---|---|---|
| 村庄 `VILLAGE` | 基础保底：面包、草料；本村特产（马、猪、鱼、铁、盐、木材等）；猪特产同时提供肉 | 大地图“购买补给”；村长对话“购买补给（面包、草料）” |
| 城镇 `TOWN` | 面包、草料、马匹（按 `scope` 配置） | 大地图“交易市场” |
| 城堡 `CASTLE` | 无市场 | 不显示入口，`is_market_settlement()` 返回 false |

村庄的商品不是按 `scope` 过滤，而是按“基础保底 + 本村特产 + 特产关联产出”判断（见 4.4）；因此即使商品配置为 `TOWN_ONLY`，只要它是某村特产，该村也会出售。

- 村庄与城镇共用同一套 `MarketManager`、`MarketData` 与结算规则；两个入口打开的是同一份库存。
- 村庄场景与大地图面板共享库存，任一入口交易后另一入口读到的是结算后的数量。
- 市场库存按地点独立保存，重启或读档后不会重置；城堡永远没有市场数据。

### 数据与职责

| 对象 | 文件 | 职责 |
|---|---|---|
| `MarketGoodsConfig` | `Scripts/Config/market_goods_config.gd` | 商品静态配置：`item_id` / `buy_price` / `sell_price` / `initial_stock` / `is_tradeable` / `scope` / `is_stackable` / `batch_purchase_amounts` / 村庄价格区间 / 村庄库存字段；完整字段见第 4.4 节 |
| `MarketData` | `Scripts/Entities/Settlement/market_data.gd` | 单个地点库存：可堆叠 `stock`、逐匹 `mount_instances`、逐件 `item_instances`（猪）、`initialized_items`、`daily_production_day` |
| `MarketManager` | `Scripts/Core/World/market_manager.gd` | 商品注册、地点校验、库存初始化、原子结算、序列化 |
| `TradeSession` | `Scripts/Entities/Trade/trade_session.gd` | 单次打开市场的预览状态、重置、确认与总额计算 |
| `MarketPanel` | `Scripts/UI/WorldMap/market_panel.gd` | 双栏交易 UI、图标、批量按钮、确认/取消/重置 |

- 商品配置位于 `Data/Market/`，启动时注册；`item_id` 必须关联已注册的 `EquipmentConfig` 或 `ItemConfig`，不按名称匹配。
- `scope` 控制城镇商品（村庄与城镇 / 仅城镇）；村庄商品改由“基础保底 + 特产 + 关联产出”决定（见 4.4），市场面板统一调用 `is_goods_available_at()`。
- 当前商品配置共 9 种：`bread`、`fodder`、`wood`、`pig`、`meat`、`fish`、`iron`、`salt`、`mount_horse_01`。城镇单价与收购价仍来自 `buy_price` / `sell_price`；村庄单价按库存比例在 `village_*` 区间内插值（见 4.4）。
- 村庄初始库存 = `floor(动态上限 × village_initial_stock_ratio)`（当前 0.5），不再使用“目标库存”或户数系数；城镇仍用 `initial_stock`。
- `ensure_markets()` 读档时只补充缺失地点或缺失商品，不重置已有库存；卖光的商品不会被补满。

### 交易交互（阶段 12）

- 左侧为市场、右侧为玩家；点击市场行中的物品直接进入右侧预览，点击玩家行中的物品直接回到左侧，不经过独立购物车。
- 马匹与猪逐件显示：每件一个行与一个按钮，绑定 `instance_id`，买卖移动的是具体实例（马匹外观随实例走）。
- 可堆叠商品提供批量购买按钮（`ItemConfig.batch_purchase_amounts`，当前为 10 / 50）；马匹与猪没有批量按钮。
- 每行最左侧固定显示图标：普通物品使用 `ItemConfig.icon_texture_path`，商品配置可用 `icon_texture_path` 覆盖（马匹没有普通 `ItemConfig`，由商品配置提供），仍缺失时使用 `MountThumbnail` 或占位。图标框固定 40×40、等比缩放，不挤压文字与按钮。
- 金币、单价与总额全部按小数显示（`GoldUtils.format`），购买/出售按钮在金币不足时拒绝。
- “重置交易”把预览恢复到本次打开市场时的快照（不是反向重放），可直接从任意中间状态复位。
- “取消”关闭面板并丢弃全部预览；“确认交易”才调用结算。未确认的预览不写入任何权威数据，也不会进入存档。

### 交易规则

- 预览由 `TradeSession` 按“与打开时快照的差值”计算购买量/出售量与总额；同一物品的买入与卖出互相抵消。
- 确认交易调用 `MarketManager.execute_trade()`（玩家入口封装为 `execute_player_trade()`）：
  1. 校验地点存在且为村庄/城镇、市场存在；
  2. 校验商品可交易、购买价/收购价有效、商品属于该地点范围；
  3. 校验市场库存、玩家背包数量、马匹实例与普通商品实例（猪）归属；
  4. 计算 `购买总额 - 出售总额`（小数），按净额校验金币；
  5. 保存持有者与市场快照，统一提交背包、马匹实例、商品实例、市场库存与金币；任一步失败回滚；
  6. 玩家交易成功后写入一条 `PLAYER_TRADE` 世界日志。
- `execute_player_trade()` / `execute_npc_trade()` 同时接受 `purchase_item_instance_ids` / `sale_item_instance_ids`；旧式按 `{ item_id: 数量 }` 传猪或马时，管理器会转换为具体实例 ID，保证不可堆叠商品不会被拆成数量。
- 同一次提交使用唯一 `trade_id`；同一非空 ID 只能成功结算一次，防止重复扣款。
- 市场库存、背包、马匹/商品实例与金币始终由各自唯一数据源持有；交易是它们唯一的一致性变更入口。
- 返回结果包含 `purchase_total` / `sale_total` / `net_gold` / `gold_paid` / `gold_received`（`float`）以及 `purchased_item_instance_ids` / `sold_item_instance_ids`。

### 日志来源区分

- `MarketManager.TradeSource.PLAYER`：成功交易写入 `PLAYER_TRADE` 世界日志。
- `MarketManager.TradeSource.NPC`：阶段 12 起由 `AIManager` 的补给采购调用；成功交易只更新库存/金币，并广播 `EventBus.npc_supply_purchased`，不写玩家世界日志。

## 4.4 村庄特产、动态库存、每日补货与价格（2026-11-28 升级）

### 范围与数据归属

- 只对 `VILLAGE` 生效；`TOWN` 保持静态初始库存与“卖光后不补货”，`CASTLE` 仍然没有市场。
- 库存由 `MarketData.stock`（可堆叠）与 `MarketData.mount_instances` / `item_instances`（马、猪）唯一持有；`MarketManager` 是唯一写入者，交易 UI 只读取并调用交易接口。
- 商品价格区间、每百户库存上限、基础保底、初始比例、每日补货比例、关联产出与图标属于 `MarketGoodsConfig`；村庄户数、特产、稳定 `map_key` 与经济状态属于 `SettlementData`。任何一方都不把派生值写回另一实体。
- 所有产出只由 `WorldSimulation` 在 `world_tick` 中调用 `MarketManager.tick_village_stock()`；暂停时没有 tick，因此不会补货。交易 UI 打开时按现行规则暂停世界时间，不会额外冻结或重置补货日期。

### 配置字段

| `MarketGoodsConfig` 字段 | 含义 |
|---|---|
| `village_buy_base_price` | 村庄标准价（库存处于正常区间时的基准价）；`<= 0` 时回退 `buy_price` |
| `village_scarcity_price_min/max` | 紧缺区间价格上下限；库存趋近 0 时取 `max` |
| `village_abundance_price_min/max` | 富足区间价格上下限；库存接近上限时取 `min` |
| `town_scarcity_price_min/max` | 城镇紧缺价格区间（预留；城镇本阶段不参与动态库存） |
| `stock_cap_per_100_households` | 每 100 户的特产库存上限；`<= 0` 表示该商品不作为特产产出 |
| `base_floor_per_100_households` | 每 100 户的基础保底上限；面包 100、草料 50，所有村庄通用 |
| `village_initial_stock_ratio` | 新村庄初始库存占动态上限的比例（当前 0.5） |
| `daily_refill_ratio` | 每日 00:00 补货量占动态上限的比例（当前 0.25） |
| `associated_item_id` | 关联产出；猪 → 肉。空字符串表示无关联 |
| `icon_texture_path` | 大地图特产图标；为空时回退 `ItemConfig.icon_texture_path` |

### 特产数据

- `Data/Settlements/village_specialties.tres`（`VillageSpecialtyConfig`）按大地图稳定 `map_key` 配置 35 个村庄的特产：马、面包、草料、猪、鱼、铁、盐、木材中的一种。
- 三个平行数组 `settlement_keys` / `display_names` / `specialty_item_ids` 一一对应；`households` 为可选户数覆盖，当前为空，村庄户数仍沿用 `SettlementData.households`（旧数据以 `population` 占位）。
- 当前配置覆盖 35 个村庄；现有地图中未列入配置的村庄（奥林）不产特产，只出售基础面包/草料。
- 新游戏：`WorldInitializer` 创建地点时通过 `apply_to_settlement(settlement, map_key)` 写入特产与可选户数。
- 旧存档：`WorldContext.load_from_save_data()` 在恢复地点后调用 `apply_defaults()`；`map_key` 缺失时按建筑显示名回退，已有特产列表视为权威，不覆盖。
- 村庄商品范围 = 所有 `base_floor_per_100_households > 0` 的基础物资 + 本村特产 + 特产的 `associated_item_id`。因此特产为猪的村庄同时出售肉；商品自身的 `scope` 不限制村庄（马配置为 `TOWN_ONLY` 仍可作为村庄特产）。

### 动态上限与初始库存

- `动态上限 = floor((基础保底每百户 + 特产每百户) × 户数 ÷ 100)`。
- “特产每百户”只在该商品是本村特产或是本村特产的关联产出时计入；否则只计基础保底（面包 100、草料 50）。
- 不设独立的“目标库存”；上限就是唯一容量，玩家交易不会改变上限，户数或配置变化只重算上限、不清空现有库存。
- 新游戏初始库存 = `floor(动态上限 × village_initial_stock_ratio)`；旧存档已有库存原样保留，只补缺失商品。

### 每日 00:00 补货

- 以 `TimeManager.total_days` 跨日为触发点，每个村庄市场每天只结算一次。
- 补货量 = `ceil(动态上限 × daily_refill_ratio)`（默认 25%），至少 1，且不超过剩余空间；可堆叠商品增加数量，猪/马逐件创建新实例。
- 时间加速只影响跨日速度，不会让同一天重复补货；暂停期间不结算；一次跨越多个游戏日会逐日补算（上限 3650 天，防异常时间）。
- 新市场或旧存档缺少 `daily_production_day` 时，以读档后首个 tick 所在游戏日为起点，不补发历史产出。
- 被破坏村庄（`SettlementData.economic_state == DESTROYED`）跳过补货，但保留现有库存；恢复 `NORMAL` 后从当天重新计日。

### 村庄价格

- 村庄购买价只由“当前库存 ÷ 动态上限”决定，不做随机波动；库存越低价格越高，库存越高价格越低。
- 分段平滑插值（边界为占上限比例）：

| 库存比例 | 价格 |
|---|---|
| 0% → 40% | 从 `scarcity_max` 线性降到 `scarcity_min` |
| 40% → 55% | 从 `scarcity_min` 平滑升到 `village_buy_base_price` |
| 55% → 70% | 从标准价平滑升到 `abundance_max` |
| 70% → 100% | 从 `abundance_max` 线性降到 `abundance_min` |

- 插值结果再钳制到配置区间内，并归一化为至少 0.01、两位小数。
- 严格遵循配置，即使数值反直觉：盐的紧缺区间为 0.5–1、标准价 1、富足区间 1–2，因此 0% 库存时为 1.0、40% 时为 0.5、70% 时为 2.0、100% 时为 1.0。
- 城镇购买价仍取静态 `buy_price`；所有地点收购价取静态 `sell_price`。UI 只调用 `MarketManager.get_buy_price()` / `get_sell_price()`。

### 当前商品数值

| 商品 | 村庄标准价 | 紧缺区间 | 富足区间 | 城镇紧缺区间 | 特产每百户上限 | 基础保底每百户 |
|---|---:|---|---|---|---:|---:|
| 面包 `bread` | 0.3 | 0.3–1.5 | 0.1–0.3 | 0.3–1.5 | 200 | 100 |
| 草料 `fodder` | 0.5 | 0.5–2 | 0.2–0.5 | 0.5–2 | 100 | 50 |
| 木材 `wood` | 0.5 | 0.5–3 | 0.3–0.5 | 0.5–4 | 100 | 0 |
| 猪 `pig` | 15 | 15–22 | 8–15 | 15–30 | 20 | 0 |
| 肉 `meat` | 2 | 2–5 | 1–2 | 2–5 | 50 | 0 |
| 鱼 `fish` | 0.3 | 0.3–1.2 | 0.1–0.3 | 0.3–1.2 | 200 | 0 |
| 铁 `iron` | 5 | 5–10 | 3–5 | 5–15 | 50 | 0 |
| 盐 `salt` | 1 | 0.5–1 | 1–2 | 1–3 | 100 | 0 |
| 马 `mount_horse_01` | 150 | 150–300 | 60–150 | 150–400 | 10 | 0 |

- 户数为 100 的村庄：面包上限 300（基础 100 + 特产 200）、草料上限 150；非特产村庄的面包/草料上限分别为 100 / 50。

### 猪与关联产出

- 猪不可堆叠，每头是独立 `ItemInstanceData`，市场与背包都按实例买卖；马保持 `MountInstanceData`。
- 猪特产村庄同时出售肉：肉有独立的库存、上限、价格与每日补货，不因买卖猪自动增加。
- 肉只能通过猪特产产出进入市场；宰杀玩家自己的猪或马额外获得 20 单位肉（见 4.2.1）。

### 交易与村庄库存

- 玩家购买只受实际库存限制；库存不足时不能购买超过实际数量的商品。
- 玩家出售可堆叠商品给村庄时，超出动态上限的部分不进入村庄库存，玩家仍按原规则获得该笔出售的金币。
- 猪/马等实例商品在村庄库存已满时拒绝出售（交易整体失败、不移动实例），避免不可堆叠个体被静默丢弃。
- 村庄库存、背包实例与金币始终由各自唯一数据源持有；交易是它们唯一的一致性变更入口。

### 大地图特产图标

- 村庄名称标签右侧显示本村特产图标（18×18，沿用名称行的 8 像素间距），只在 UI 层添加，不写入地点或存档。
- 图标是独立 `TextureRect`，`mouse_filter` 忽略点击，不阻挡名称标签/家族旗帜的交互。
- 名称与家族旗帜的中心位置保持不变：加入图标时在左侧补等宽占位，避免整行右移。
- 显示优先级：商品配置 `icon_texture_path` → 物品 `ItemConfig.icon_texture_path`；城镇、城堡或无匹配图标时不显示。

### 查询与接口

| 接口 | 用途 |
|---|---|
| `get_village_stock(settlement_id, item_id)` | 当前库存 |
| `get_village_stock_max(...)` | 动态上限（`get_village_stock_target` 保留为同值别名） |
| `get_village_households(settlement_id)` | 户数 |
| `get_village_specialty_item_ids(...)` / `is_village_specialty(...)` | 特产查询 |
| `calculate_daily_production_amount(stock_max, current, ratio)` | 每日补货量 |
| `get_village_stock_configs(settlement_id)` | 参与村庄库存机制的商品 |
| `add_village_stock(...)` / `remove_village_stock(...)` | 受上限约束的库存增减 |
| `tick_village_stock(fixed_delta)` | 世界 tick 入口（只保留每日补货） |

### 扩展钩子

- `SettlementData.EconomicState` 当前只有 `NORMAL` / `DESTROYED`；破坏后停止产出、保留库存。
- 繁荣度、人口增长、城镇供需、贸易路线、商队与税收结算尚未接入本模型，后续可在现有配置与接口上扩展，不需要重写交易或存档结构。

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
| `SaveData.markets[settlement_id].item_instances` | 逐件恢复猪；缺失时为空 |
| `player.mount_instances` / `PartyData.mount_instances` | 旧档数量迁移为独立实例，反复读取结果一致 |
| `player.item_instances` / `PartyData.item_instances` | 猪等非堆叠物品实例；缺失时为空 |
| `UnitData.mount_instance` | 缺失时按 `unit_id + equipment_id` 确定性生成外观 |
| `markets[].initialized_items` | 缺失时视为已初始化，避免读档补满已售罄商品 |
| `markets[].daily_production_day` | 缺失时保持 -1，读档后首个 tick 以当前游戏日为起点，不补发历史产出 |
| `settlements[].households` | 缺失时以 `population` 作为占位默认值 |
| `settlements[].map_key` | 缺失时按建筑显示名回退到特产配置；仍为空则无特产 |
| `settlements[].village_specialty_item_ids` | 缺失时由 `VillageSpecialtyConfig` 按 `map_key` / 名称补齐；已有列表权威 |
| `settlements[].economic_state` | 缺失时为 `NORMAL`（未破坏） |
| `player.gold` / `PartyData.gold` | 旧整数金币直接读为浮点；写入统一两位小数 |
| `SaveData.supply_last_settled_day` | 缺失（v5 及更早）时以存档时刻所在游戏日为起点 |

当前存档 Schema 为 v11（金币改为小数、市场新增 `item_instances`、地点新增 `map_key` / `economic_state`）；v10 及更早存档读取时补安全默认值，不重建世界、不重置已有库存（详见 `Save_System.md`）。

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
| 每日收支预览 | 已实现（`WorldContext.get_daily_balance_preview`，复用工资与税收缓存，不结算） |
| 普通招募金币 | 已实现（Tier1 = 5，Tier3 = 400，失败回滚） |
| 雇佣兵招募与日薪 | 已实现（统一配置：35/80 + 经验/坐骑加价；日薪 4/9） |
| 新游戏初始金币 | 已实现（10000，仅新游戏） |
| 采邑征召资源成本 | 已实现（储备/人口/繁荣度） |
| 完整玩家背包 UI | 已实现（阶段 11，只读） |
| 村庄/城镇双栏交易市场 | 已实现（阶段 12：左右直接移动、重置、图标、批量） |
| 市场库存独立存档/恢复 | 已实现（`SaveData.markets`，含马匹实例、猪实例、`initialized_items`、每日补货日期） |
| 村庄动态库存上限 | 已实现（`floor((基础保底 + 特产) × 户数 ÷ 100)`；面包/草料全村庄保底） |
| 村庄每日 00:00 补货 | 已实现（上限 25%，至少 1，单日一次，跨日补算，暂停与破坏村庄不补） |
| 村庄特产配置 | 已实现（`Data/Settlements/village_specialties.tres`，35 个村庄；旧档按 `map_key` / 名称回填） |
| 村庄按库存比例定价 | 已实现（四段平滑插值，钳制配置区间，不随机） |
| 猪/马非堆叠实例交易 | 已实现（`ItemInstanceData` / `MountInstanceData`，逐件买卖） |
| 猪特产关联肉 | 已实现（猪商品配置 `associated_item_id = "meat"`，肉独立库存/价格/补货） |
| 牲畜宰杀（20 肉） | 已实现（`SlaughterManager` + 背包确认弹窗） |
| 小数金币与统一显示 | 已实现（`GoldUtils`；存档、交易、UI 一致） |
| 村庄破坏状态 | 已实现（`EconomicState`；停止产出、保留库存；无破坏入口 UI） |
| 大地图村庄特产图标 | 已实现（名称右侧 UI 图标，不挡点击、不移动名称/旗帜） |
| 玩家交易世界日志 | 已实现（`PLAYER_TRADE`，最多 20 条；金额按小数格式化） |
| NPC 补给采购 | 已实现（阶段 12，`AIManager` + `execute_npc_trade()`，不写玩家日志） |
| 每日面包/草料消耗 | 已实现（`SupplyManager`，见 `Supply_System.md`） |
| 普通兵员招募、负重、拖拽交易 | 未实现 |
