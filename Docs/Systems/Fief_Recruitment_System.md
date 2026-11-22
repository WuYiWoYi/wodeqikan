# 采邑征召系统

**核心逻辑：** `Scripts/Core/World/fief_recruitment_manager.gd`
**数据：** `Scripts/Entities/Settlement/settlement_data.gd`
**配置：** `Scripts/Config/settlement_economy_config.gd`、`Data/Settlements/settlement_economy_config.tres`
**状态：** 阶段 7 第一步已实现：封地归属校验、每村储备/补充、成组征召、原子回滚、玩家 UI 与 AI 领主共用。

---

## 1. 定位与边界

采邑征召是“领主从自己的村庄获得一组成建制士兵”的唯一入口：

```text
玩家地点面板 / 村庄头人对话 / AI 领主抵达
        ↓
FiefRecruitmentManager.recruit_group(settlement_id, lord_id)
        ↓
UnitManager.create_unit + PartyManager.add_member
        ↓
EventBus.fief_recruited
        ↓
WorldLogManager / WorldMap 浮动提示（只读订阅）
```

- 阶段 8 起授权条件：`SettlementData.owner_noble_id == lord_id`，或请求者是 `owner_house_id` 家族的领袖；`faction_id` 与视觉 `family_id` 不参与权限判断。`owner_lord_id` 作为兼容副本同步。
- 只有村庄有采邑储备；城镇/城堡容量为 0。
- 管理器不操作 UI、场景节点或部队图标；UI 只调用接口并读取 `last_error`。
- 生成的 6 名单位全部进入 `UnitManager`，并通过 `PartyManager.add_member()` 加入领主部队。

## 2. 数据字段

`SettlementData` 中与采邑相关的持久化字段：

| 字段 | 说明 |
|---|---|
| `owner_noble_id` | 封地归属贵族；空字符串表示无主 |
| `owner_house_id` | 归属政治家族；家族领袖也可授权征召 |
| `owner_lord_id` | 兼容副本；与 `owner_noble_id` 同步 |
| `fief_recruitment_stock` | 当前可征召组数 |
| `fief_recruitment_capacity` | 储备上限；读档/配置变化时按 `fief_max_stock` 修正 |
| `fief_recruitment_elapsed` | 距离下一组补充的累计世界秒 |
| `population` / `prosperity` | 征召成本与补充周期的影响因子 |
| `tax_base` / `tax_income_per_day` | 统一税收计算的输入与缓存结果 |

## 3. 一组采邑的固定编制

| 单位 | 配置 | 人数 | 骑乘 |
|---|---|---|---|
| 骑马扈从 | `infantry_veteran` | 1 | 是 |
| 骑马军士 | `infantry_trained` | 1 | 是 |
| 军士 | `infantry_trained` | 1 | 否 |
| 步兵 | `infantry_militia` | 2 | 否 |
| 弓箭手 | `archer_militia` | 1 | 否 |

- 合计 6 人，与 `SettlementEconomyConfig.fief_group_size` 一致；配置不一致时直接拒绝，不产生部分单位。
- 骑乘通过 `UnitManager.equip_item(unit_id, "mount_horse_01")` 写入真实 `MOUNT` 装备，不修改玩家背包，也不新增骑兵 `config_id`。
- 每名单位写入 `recruit_source = "fief_recruitment"`、`recruit_settlement_id`、`origin_faction_id` 与 `joined_at_game_time`。
- 外观由 `UnitAppearance.ensure_random()` 按兵种等级与村庄家族生成并写入 `UnitData.appearance`。

## 4. 征召流程与原子性

`recruit_group()` 按以下顺序执行：

1. `can_recruit()` 校验：村庄存在且为村庄、贵族存在且存活、`owner_noble_id` 匹配或请求者为 `owner_house_id` 家族领袖、储备 > 0、部队存在且 `is_available_for_world()`。
2. 校验编制人数与配置一致。
3. 依次创建 6 个单位、写入招募来源、生成外观、装备马匹、加入部队。
4. 全部成功后一次性扣除储备、人口、繁荣度，重置补充计时并重算税收缓存。
5. 发出 `EventBus.fief_recruited(party_id, settlement_id, 1, is_player_recruiter)`。

任何一步失败：

- 已创建的单位先从部队移除，再从 `UnitManager` 删除；
- 储备、人口、繁荣度、计时均不扣除；
- `last_error` 给出可展示原因；
- 不发出事件，不写日志。

## 5. 储备补充

- `FiefRecruitmentManager.tick(world_delta)` 只由 `WorldSimulation` 调用；暂停时 WorldTime 不推进，因此不补充。
- 储备已满时 `fief_recruitment_elapsed` 归零。
- 否则累计世界秒，达到 `get_refill_interval()` 后增加 1 组；一次 tick 最多补齐到上限（循环带 64 次保护）。
- 补充周期：

```text
interval = refill_base_interval
         × clamp(refill_population_reference / max(population, 1), min, max)
         × clamp(refill_prosperity_reference / max(prosperity, 1), min, max)
```

默认基础周期 144 世界秒；人口/繁荣度越低，补充越慢。

## 6. 人口、繁荣度与税收

- 成功征召一组：`population -= fief_population_cost`（默认 4），`prosperity -= fief_prosperity_cost`（默认 2），均按配置下限 clamp。
- 税收统一由 `TaxCalculator.compute_daily_tax(population, prosperity, tax_base)` 计算，结果缓存到 `tax_income_per_day`。
- UI 不得自行拼公式，只读取缓存值或调用 `FiefRecruitmentManager.get_tax_income()`。
- 当前只统计与展示税收，不按日扣除金币。

## 7. 玩家入口

两个入口共用同一业务接口：

| 入口 | 节点/方法 | 条件 |
|---|---|---|
| 大地图地点面板 | `SettlementRecruitFiefButton` → `_on_settlement_recruit_pressed()` | 地点为玩家自有村庄；储备 > 0 时按钮可用 |
| 村庄头人对话 | 选项 action `recruit_fief` → `_execute_dialogue_action()` | 玩家自有村庄且有储备时才追加选项 |

- 成功后刷新地点面板/对话与村庄日志；失败显示 `last_error`。
- `EventBus.fief_recruited` 由大地图订阅，在征召者部队图标上方显示“招募了 N 组采邑”，由 `WorldLogManager` 写入世界日志。
- 重复点击由储备与部队可用性校验兜底，不会重复结算。

## 8. AI 领主

- `AIManager` 在战略决策分频中检查非玩家、存活领主：部队人数低于 `ai_lord_recruit_threshold`（默认 12）时，寻找最近的、自己拥有的、有储备的村庄。
- 找到后设置 `LordData.current_state = "RECRUITING"` 与 `current_target_settlement_id`，部队前往该村。
- 抵达后调用同一个 `recruit_group()`；成功或失败都清除 `RECRUITING` 状态，恢复普通 AI。
- `RECRUITING` 期间部队战术 AI 跳过，避免巡逻/追击覆盖征召目标。
- AI 征召同样消耗储备、人口、繁荣度，并写世界日志；日志按事件事实生成，不重复记录。

## 9. 持久化

- `SettlementData.to_dict()/from_dict()` 保存 `owner_noble_id` / `owner_house_id` / `owner_lord_id`、储备/容量/计时、人口/繁荣度、税收缓存与冒险者候选人。
- 存档 Schema v4 新增顶层 `lords`；Schema v5 继续保留并由 `nobles` 同源提供贵族数据。读档先恢复领主/贵族，再恢复地点，随后调用 `initialize_settlement(settlement)` 修正边界但不覆盖储备与计时。
- 读档校验：每个非空 `owner_noble_id` 必须指向存在的贵族，`owner_house_id` 必须存在且与贵族家族一致；玩家贵族必须存在且 `is_player_lord == true`；失败则拒绝加载，不自动改写存档。
- 当前配置参数（周期、成本、编制、上限）是静态资源，不进入存档。

## 10. 测试

- `Tests/SystemTests/fief_adventurer_system_test.tscn`：归属校验、6 人编制与马匹、储备/人口/繁荣度/税收、失败回滚、日志、AI 征召、存档往返。
- `Tests/SystemTests/fief_adventurer_ui_test.tscn`：地图面板入口、村庄对话入口、按钮状态、浮动提示、非自有封地隐藏。

## 11. 未实现

- 征召过程没有时间消耗、排队、工资预付或人口恢复。
- 城镇/城堡没有采邑征召。
- 领主死亡、封地继承、封地转让与战争占领未实现。
- 储备补充与人口/繁荣度变化只在征召时修改，尚无每日经济模拟。
