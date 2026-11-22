# 部队补给系统

**核心逻辑：** `Scripts/Core/World/supply_manager.gd`
**调度入口：** `Scripts/Core/World/world_simulation.gd`（`WorldTime` 日边界）
**数据持有：** 玩家 = `PlayerProfile`；NPC = `PartyData.inventory_data`
**状态：** 每日面包/草料消耗、玩家与 NPC 统一结算、缺口记录、采购需求查询已实现

---

## 1. 职责边界

| 负责 | 不负责 |
|---|---|
| 统计士兵与马匹每日需求 | 市场定价与库存 |
| 按游戏日边界扣除补给 | 决定“去哪里买、买多少” |
| 记录缺口（不会产生负数） | 修改部队移动目标 |
| 提供剩余天数与目标储备需求量 | UI 表现 |

`AIManager` 只使用 `SupplyManager` 的查询结果，再调用 `MarketManager` 完成采购；
`SupplyManager` 不包含任何市场或路线逻辑。

## 2. 消耗规则

| 对象 | 每日消耗 |
|---|---|
| 存活士兵（`current_hp > 0`） | 1 面包 |
| 已装备坐骑 + 背包中的独立马匹实例 | 1 草料 |
| 市场中待售马匹 | 不消耗 |

- 玩家部队的物品从 `PlayerProfile` 扣除；
- NPC 部队从自己的 `PartyData` 背包扣除；
- 双方使用完全相同的字段、消耗量与缺口规则。

库存不足时：

```text
消耗量 = min(需求量, 当前库存)
库存   = max(0, 库存 - 消耗量)
缺口   = 需求量 - 消耗量
```

缺口写入 `PartyData.supply_bread_shortage` / `supply_fodder_shortage`，供 UI 与 AI 查询。

## 3. 时间驱动

`WorldSimulation.on_world_tick()` 每 tick 调用 `SupplyManager.update_daily()`：

- 读取 `TimeManager.get_date_parts()["total_days"]`；
- 与 `last_settled_day` 比较，只有跨日才结算；
- 暂停时 `world_tick` 不发出，因此不会消耗；
- 2 倍速只改变到达日边界的现实时间，不会重复结算；
- 一次跨越多个游戏日时按天补算（有上限保护）；
- 同一天多次 tick 不会重复扣粮。

`last_settled_day` 随存档保存。读档后：

- 有记录：从记录日继续；
- 旧存档无记录：以存档时刻所在游戏日作为起点，避免读档立即扣粮或重复扣同一天。

## 4. 关键查询

| 接口 | 说明 |
|---|---|
| `get_status(party)` | 面包/草料数量、每日需求、剩余天数、低补给标记、上次缺口 |
| `has_low_supply(party)` | 剩余天数 ≤ 3 天（或需求为 0 时不算低） |
| `get_purchase_needs(party)` | 补到 7 天储备所需数量 |
| `settle_party(party)` | 单支部队结算一次（测试/特殊流程） |

`EventBus.party_supply_changed` 只在低补给状态切换时广播，避免每 tick 刷提示。

## 5. NPC 采购

`AIManager` 在每个 1 秒战术周期检查：

1. 非玩家、非强盗、有成员、未在战斗/追击/战后冷却；
2. `SupplyManager.has_low_supply()` 为真；
3. 在村庄/城镇（绝不选城堡）中找最近且仍有对应库存的市场；
4. 用部队自有金币购买，最多补到 7 天储备；
5. 通过 `MarketManager.execute_npc_trade()` 结算；
6. 成功后广播一次 `EventBus.npc_supply_purchased`，大地图在部队图标上方浮字。

NPC 采购不写玩家世界日志；只有玩家来源的交易产生 `PLAYER_TRADE` 日志。

## 6. 新世界初始补给

- 玩家：7 天份面包/草料；
- NPC：2 天份，并给予少量起始资金；
- 强盗不初始化市场补给；
- 旧存档升级 v6 时，只为完全没有补给记录的部队补 3 天起步物资，已管理过补给的部队不补发。

## 7. 边界

- 补给消耗只能在 `SupplyManager` 中发生，其他系统不得自行按天扣物品。
- 市场库存变化必须经过 `MarketManager`，AI 不直接改 `MarketData`。
- 马匹是否消耗草料只看“是否属于部队”，不看是否在场景中骑乘。
