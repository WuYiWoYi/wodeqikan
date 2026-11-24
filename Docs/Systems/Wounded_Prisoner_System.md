# 伤兵、治疗与俘虏系统

**核心数据：** `Scripts/Entities/Unit/unit_data.gd`、`Scripts/Entities/Party/party_data.gd`
**核心逻辑：** `Scripts/Core/World/wounded_healing_manager.gd`、`Scripts/Core/World/party_manager.gd`、`Scripts/Systems/Combat/battle_manager.gd`、`Scripts/Core/World/prisoner_trade_manager.gd`
**配置：** `Data/Combat/wounded_config.tres`、`Data/Combat/healing_config.tres`、`Data/Settlements/prisoner_price_config.tres`
**UI：** `Scripts/UI/Battle/prisoner_selection_panel.gd`、`Scripts/UI/WorldMap/tavern_panel.gd`
**状态：** 战斗负伤判定、WorldTime 顺序治疗、战后俘虏池分配、玩家接收、城镇酒馆出售与按兵种 tier 定价已实现；药物、俘虏容量/逃跑/招募与买家经济未实现

---

## 1. 职责

- 战斗结算时决定 HP≤0 单位的去留：伤兵或永久死亡。
- 按游戏时间治疗伤兵，恢复其成员身份与可战斗状态。
- 把战败方伤兵转化为俘虏，并按实际参战单位数分配给胜利方。
- 为玩家提供战后接收与城镇出售俘虏的界面和原子业务入口。

不负责：伤口恶化/感染、药物技能、俘虏逃跑/忠诚、容量上限、城镇买家经济、俘虏招募。

## 2. 伤兵

### 2.1 判定

- 在 `BattleManager.build_battle_result()` 中，统计伤亡前对每个 HP≤0 单位执行一次判定。
- 概率来自 `WoundedConfig.tier_wounded_chances`：
  - tier 1：50%
  - tier 2：60%
  - tier 3：80%
  - 越界 tier 取边界值；`enabled = false` 时全部永久死亡。
- 玩家角色（`is_player_character`）不参与判定，保留永久死亡。
- 判定结果写入 `BattleUnitState.wounded`，`wounded_decided` 保证预览与最终结算不会重复掷骰。

### 2.2 状态与数据

- 伤兵调用 `UnitData.mark_wounded()`：`status = WOUNDED`，`current_hp = 0`。
- 伤兵保留：
  - 原 `unit_id`、`config_id`、名称与玩家角色身份；
  - 等级、经验、工资、装备、外观；
  - 原部队成员身份与成员列表顺序。
- 伤兵不能战斗、移动、攻击；战斗开始只取 `ACTIVE` 成员。
- 伤兵仍计入部队人数与工资总额；不是死亡，不触发 `unit_died`。
- 伤兵不获得战斗经验，也不进入战利品掉落。

### 2.3 恢复到正常

- 治疗使 `current_hp > 0` 后，`clamp_hp()` 把 `WOUNDED` 改回 `ACTIVE`。
- 只有伤兵的部队在结算后被置为 `DISABLED`；出现可行动成员后自动恢复 `AVAILABLE` 并广播 `party_battle_state_changed`。

## 3. 顺序治疗

### 3.1 治疗点

```text
每游戏小时治疗点 = base_healing_per_hour + medicine_healing_bonus
```

- `HealingConfig` 默认 `base = 1`、`medicine = 0`（预留药物技能）。
- 治疗点只由 `WoundedHealingManager` 生成，不散落在 UI 或补给系统。

### 3.2 结算规则

- 仅由 `WorldTime` 驱动：`WorldSimulation` 每 tick 调用 `WoundedHealingManager.tick()`。
- 暂停时 `WorldSimulation` 不收到推进，因此不治疗。
- 1x 与 2x 都以“游戏小时”结算，每游戏小时获得相同点数。
- 跨多小时会按 `hours * per_hour` 一次性补发；同一小时不会重复结算。
- 首次运行或旧存档缺失结算点时，只记录当前小时，不补发历史治疗。
- 玩家与 NPC 部队统一生效；已移除/解散的部队不在 `PartyManager` 中，不治疗。
- 战斗中（`party.battle_state == IN_BATTLE`）跳过，HP 权威属于 `BattleUnitState`。

### 3.3 顺序与溢出

- 按 `PartyData.member_unit_ids` 顺序遍历成员。
- 对每个未满血成员补 HP：先补满当前伤兵，剩余点数才流向下一名。
- 所有成员满血后剩余点数直接丢弃（不累计到下一小时）。
- 例：A 98/100、B 90/100，治疗 12 点 → A +2、B +10。
- 返回值 `{ points_used, healed_unit_ids }` 供测试与后续日志使用。

### 3.4 存档

- `SaveData.time.healing_last_settled_hour` 保存上次结算小时。
- 读档后由 `restore_settled_hour(saved_hour, world_elapsed_seconds)` 恢复；缺失时以存档时刻所在小时为起点，读档不补算。
- 治疗进度不包含逐单位状态，伤兵 HP 本身随 `UnitData` 保存。

## 4. 俘虏池与分配

### 4.1 俘虏池

- 战斗胜利成立（非中止/撤退/平局）时构建。
- 池 = 战败侧所有 `wounded == true` 的单位，按稳定顺序排序。
- 永久死亡单位不进入池；玩家角色不会成为俘虏。
- 俘虏是独立 `UnitData`：唯一 ID、不可堆叠、保留等级/装备/属性，不是背包物品。

### 4.2 分配算法

```text
N_i = 第 i 个胜利方部队的实际参战单位数
N   = 所有胜利方参战单位数之和
share_i = floor(P * N_i / N)
```

- 参战数来自 `BattleSession` 的参战/增援单位，每单位只计一次，**不是存活数**。
- 先取整，再按余数降序补齐；余数相同按稳定 `party_id` 升序。
- 份额之和恒等于俘虏池大小 `P`。
- 单胜利方获得全部；`N = 0` 时第一支稳定排序的胜利方获得全部，并标记 `prisoner_allocation_degraded`。
- 个体按稳定顺序分配，不依赖 Dictionary 遍历顺序。

### 4.3 接收

| 胜利方 | 行为 |
|---|---|
| 非玩家 | `_claim_battle_prisoners()` 立即调用 `PartyManager.add_prisoner()` |
| 玩家 | 份额挂起在 `_pending_prisoner_settlements[battle_id]`，等待战后 UI 确认 |

- `commit_player_prisoners(battle_id, accepted)`：
  1. 归一化并去重接受列表；
  2. 校验每个单位在玩家份额内、非任何部队成员、未被其他部队关押、非死亡；
  3. 全部通过后逐个 `add_prisoner()`，任一失败回滚；
  4. 未接收单位由 `_release_unclaimed_prisoner()` 清除归属并从 `UnitManager` 删除；
  5. 写入 `player_prisoners_committed = true`、移除挂起记录；重复提交返回 false。
- 失败方、无俘虏或玩家无份额时不显示选择界面。

## 5. 战后俘虏选择 UI

- `BattleScene` 在原有结果面板确认后检查 `has_pending_prisoner_selection()`。
- 有玩家份额时显示 `PrisonerSelectionPanel`，不立即切换场景：
  - 左栏：本场分配给玩家的俘虏；
  - 右栏：玩家当前已有俘虏（只读）+ 已选择接收的俘虏；
  - 支持点击转移、撤回与重置；
  - 确认前不修改任何真实 `UnitData` 或 `PartyData`。
- 确认后由 `BattleScene` 调用 `commit_player_prisoners()`，随后返回大地图。
- 选择界面压入 `prisoner_selection` 暂停原因，结束或确认后成对释放。

## 6. 城镇酒馆出售

### 6.1 入口

- 只有 `SettlementType.TOWN` 的地点面板显示 `SettlementTavernButton`。
- 打开 `TavernPanel` 后隐藏地点面板，保持同一个 `PAUSE_REASON_UI_PANEL`。
- 菜单：出售俘虏、查看雇佣兵信息（占位）、离开酒馆。

### 6.2 出售界面

- 左栏：当前城镇买家中的待售俘虏；
- 右栏：玩家俘虏列表；
- 右侧行“卖出”、左侧行“撤回”；“重置出售”恢复打开时快照；
- 只有“确认出售”调用 `PrisonerTradeManager.sell_prisoners()`。

### 6.3 价格与结算

- 普通士兵按 **兵种等级 `UnitConfig.tier`** 定价，不按战斗经验 `UnitData.level` 定价：
  - 一级 5 金币、二级 20 金币、三级 60 金币；超出配置范围取边界价格。
- 具有 NPC 领主身份（`UnitData.noble_id` 非空）的俘虏统一 100 金币，与其部队人数、家族地位和经验等级无关。
- 不考虑装备与伤势；经验等级不参与定价。
- 所有出售入口（酒馆预览、确认结算）都必须通过 `PrisonerTradeManager.get_sell_price()` / `PrisonerPriceConfig`，UI 不得写死价格。
- `sell_prisoners(party_id, unit_ids, settlement_id)`：
  1. 校验部队与地点存在、地点为城镇；
  2. 校验每个单位存在、由该部队关押、非成员、价格 > 0；
  3. 去重；
  4. 一次性增加金币、`remove_prisoner()` 并 `mark_sold(settlement_id)`；
  5. 失败时不做任何部分结算。
- 售出单位退出玩家控制与俘虏列表，保留 `sold_to_settlement_id`；普通士兵不再参与战斗、治疗、工资或后续买卖。
- NPC 领主售出后额外交给 `LordRansomManager.on_lord_sold()` 登记赎回等待；具体生命周期见 [Lord_Ransom_System.md](Lord_Ransom_System.md)。

## 7. 数据不变量

- 成员关系：

```text
unit.current_party_id == party.party_id
⇔ party.member_unit_ids.has(unit.unit_id)
```

- 俘虏关系：

```text
unit.prisoner_owner_party_id == party.party_id
⇔ party.prisoner_unit_ids.has(unit.unit_id)
```

- 成员与俘虏互斥：`add_member()` 拒绝俘虏/已售出单位，`add_prisoner()` 拒绝成员。
- 俘虏最多属于一个关押部队；转移保持双向一致。
- 已售出单位不能重新成为成员或俘虏；NPC 领主只能通过家族赎回流程恢复活动状态（`mark_ransomed()` 清除出售/俘虏状态后重建部队）。
- 读档调用 `sanitize_prisoner_ownership()` 幂等清洗，成员身份优先。

## 8. 配置

| 配置 | 字段 | 默认值 |
|---|---|---|
| `WoundedConfig` | `enabled` | `true` |
| `WoundedConfig` | `tier_wounded_chances` | `[0.5, 0.6, 0.8]` |
| `HealingConfig` | `base_healing_per_hour` | `1` |
| `HealingConfig` | `medicine_healing_bonus` | `0` |
| `PrisonerPriceConfig` | `tier_prices` | `[5, 20, 60]`（按兵种 tier） |
| `PrisonerPriceConfig` | `lord_price` | `100`（NPC 领主统一价） |

配置均为只读 `.tres`，由 `WorldContext` 加载；UI 不得写死概率、治疗量或价格。

## 9. 实现状态

| 项 | 状态 |
|---|---|
| 战斗负伤判定 | 已实现（按 tier 概率，玩家除外） |
| 伤兵身份/数据保留 | 已实现 |
| WorldTime 顺序治疗 | 已实现（溢出、跨小时、暂停、1x/2x） |
| 伤兵存档与续算 | 已实现（v7） |
| 俘虏池/最大余数分配 | 已实现 |
| 玩家战后选择与原子提交 | 已实现 |
| 城镇酒馆出售 | 已实现（城镇限定、原子结算） |
| 兵种 tier 定价 | 已实现：5 / 20 / 60 |
| NPC 领主出售 | 已实现：统一 100 金币并启动赎回等待 |
| 雇佣兵信息 | 占位 |
| 药物技能/治疗物品 | 未实现（预留配置） |
| 俘虏容量/逃跑/守卫/招募 | 未实现 |
| 装备/状态/经验定价 | 明确未实现 |

## 10. 相关文档

- [Unit_System.md](Unit_System.md)：`Status` 与 Unit 字段。
- [Party_System.md](Party_System.md)：俘虏列表与归属 API。
- [Combat_System.md](Combat_System.md)：结算顺序与负伤判定。
- [Settlement_System.md](Settlement_System.md)：城镇酒馆入口。
- [Save_System.md](Save_System.md)：Schema v8 字段与迁移。
- [Lord_Ransom_System.md](Lord_Ransom_System.md)：NPC 领主出售后的赎回流程。
- [Time_System.md](Time_System.md)：WorldTime 与游戏小时。
