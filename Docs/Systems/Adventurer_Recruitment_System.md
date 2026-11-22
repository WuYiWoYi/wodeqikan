# 冒险者招募系统

**核心逻辑：** `Scripts/Core/World/adventurer_recruitment_manager.gd`
**候选数据：** `Scripts/Entities/Settlement/adventurer_candidate_data.gd`
**配置：** `Data/Settlements/settlement_economy_config.tres`
**状态：** 阶段 7 第一步已实现：每村候选人池、世界时间刷新、村庄 NPC 对话支付 1 金币招募、离开村庄清理。

---

## 1. 定位与边界

冒险者是村庄里的独立可招募 NPC，与采邑征召的区别：

| 项 | 采邑征召 | 冒险者招募 |
|---|---|---|
| 来源 | 领主自有封地储备 | 村庄候选人池 |
| 一次获得 | 固定 6 人成组 | 1 人 |
| 费用 | 储备 + 人口 + 繁荣度 | 1 金币 |
| 入口 | 地图面板 / 头人对话 | 点击候选人 NPC 对话 |
| 目标部队 | 领主部队（玩家或 AI） | 玩家部队 |
| 上限 | 每村储备 4 组 | 每村最多 5 名候选人 |

- 候选人本身不是 `UnitData`，不进入 `UnitManager`、`PartyManager` 或部队成员列表。
- 只有支付成功后才调用 `UnitManager.create_unit()` 创建真实单位，并通过 `PartyManager.add_member()` 加入玩家部队。
- 管理器不创建场景节点；村庄场景只读取候选人数据生成 NPC 表现。

## 2. 候选数据

`AdventurerCandidateData`：

| 字段 | 说明 |
|---|---|
| `candidate_id` | `CANDIDATE_000001`，由 `IdGenerator` 生成 |
| `display_name` | 持久化随机姓名 |
| `settlement_id` | 所属村庄 |
| `unit_config_id` | 招募后使用的兵种配置（默认 `infantry_militia`） |
| `world_position` | 村庄小场景内的固定候选位置 |
| `status` | `AVAILABLE` / `RECRUITED_PENDING_DEPARTURE` |
| `unit_id` | 招募成功后关联的真实单位 ID |
| `appearance` | 创建时一次性生成的外观字典，招募后原样复制给真实单位 |

`is_available()` 只在 `AVAILABLE` 状态下返回 true。

## 3. 候选人池与刷新

- 新游戏每个符合条件的村庄初始生成 `adventurer_initial_count`（默认 2，上限 `adventurer_max_candidates`）名候选人。
- 阶段 13 起每个候选人拥有独立 Unit 身份：`candidate.unit_data` 保存完整快照，`candidate.unit_id` 关联快照 ID；候选人归村庄候选数据所有，不进入任何部队。
- 快照通过 `UnitManager.create_unit` 同源的创建逻辑生成（默认 tier 1 步兵），不是 UI 假数据；招募成功时把快照原样转为玩家部队成员，并沿用等级/装备/外观。
- `initialize_settlement(fill_initial)` 先幂等补齐已有候选人身份，再按数量补足初始人数；读档时 `fill_initial=false`，不会重复生成或重复创建身份。
- `AdventurerRecruitmentManager.tick(world_delta)` 只由 `WorldSimulation` 调用：
  - 只处理村庄；
  - 当前候选人数达到 `adventurer_max_candidates`（默认 5）时计时归零；
  - 否则累计世界秒，每达到 `adventurer_refresh_interval`（默认 144 世界秒）生成 1 名，带 16 次循环保护；
  - 暂停时 WorldTime 不推进，因此不刷新。
- 姓名从 `NAME_POOL` 随机，同名时追加序号；位置从 `CANDIDATE_POSITIONS` 中选未被占用的点。
- 生成时用临时 `UnitData` 调用 `UnitAppearance` 生成外观，只保存外观字典，不注册临时单位。

## 4. 招募流程与回滚

`recruit_candidate(settlement_id, candidate_id, profile)`：

1. 校验村庄、候选人存在、`AVAILABLE`、玩家档案有效。
2. 校验金币 >= `adventurer_recruit_cost`（默认 1）。
3. 校验玩家部队存在且 `is_available_for_world()`。
4. 读取候选人兵种配置，创建真实单位，复制候选人姓名与外观。
5. 加入玩家部队。
6. 扣除金币。
7. 写入 `recruit_source = "adventurer_recruitment"`、村庄 ID、阵营与加入时间。
8. 候选人状态改为 `RECRUITED_PENDING_DEPARTURE`，记录 `unit_id`。
9. 发出 `EventBus.adventurer_recruited(settlement_id, unit_id, unit_name)`。

失败处理：

- 加入部队失败或扣金币失败时，移除并删除刚创建的单位，不扣金币、不改变候选人状态；
- 重复招募同一候选人返回 false，不产生第二个单位；
- 金币不足不扣款。

## 5. 离开村庄与清理

- 已招募候选人在玩家离开村庄前仍保留在 `adventurer_candidates` 中，场景中显示“已招募”标记，避免对话中途消失。
- `VillageScene._request_exit()` 调用 `cleanup_departed_candidates(settlement_id)`：
  - 只移除 `RECRUITED_PENDING_DEPARTURE` 的候选人记录；
  - 真实 `UnitData` 不受影响；
  - 重复调用幂等。
- 再次进入村庄时，已招募候选人的记录已被清理，不会重复显示，也不会重复招募。

## 6. 村庄表现与对话

- 每个可招募候选人生成一个运行时 NPC 表现节点，位置来自 `candidate.world_position`，外观来自持久化 `appearance`。
- 点击半径与头人一致：鼠标点击候选 NPC 且玩家距离 <= 130 像素才打开对话。
- 对话选项 action 为 `recruit_adventurer`；显示费用与候选人姓名。
- 招募成功后关闭对话并刷新候选 NPC 的“已招募”标签；失败显示 `last_error`。
- 已招募候选人再次对话不再提供招募选项。
- `EventBus.adventurer_recruited` 由 `WorldLogManager` 写成“你在{村庄}招募了冒险者{姓名}。”。
- 村庄右上角复用大地图的 `WorldLogPanel`，与大地图共享同一份日志历史。

## 7. 持久化

- 候选人的 ID、姓名、村庄、兵种、位置、状态、关联单位 ID 与外观全部通过 `SettlementData.to_dict()/from_dict()` 往返。
- `adventurer_refresh_elapsed` 随地点保存；读档保留已累计时间。
- 读档不重新生成候选人，只修正边界与刷新计时。
- 旧存档没有候选人字段时按空列表恢复；下一次世界 tick 按刷新规则补充。
- 新游戏/读档的初始补齐只由 `WorldInitializer` 与 `WorldContext` 明确调用，避免读档重复生成。
- 阶段 13 起候选人快照随存档保存；读档先 `ensure_candidate_identities()` 补旧档缺失快照，再恢复候选人数，保证同一候选人不会生成第二个 Unit。

## 8. 测试

- `Tests/SystemTests/fief_adventurer_system_test.tscn`：1 金币扣款、只生成 1 个单位、姓名/外观持久化、重复招募拒绝、离开清理幂等、刷新上限、日志。
- `Tests/SystemTests/fief_adventurer_ui_test.tscn`：村庄候选 NPC、距离交互、对话按钮、已招募标记、离开清理、日志面板。
- `Tests/SystemTests/stage13_village_candidates_test.tscn`：初始候选人数量/上限、独立 Unit 身份、村庄归属、不重复、招募后进入玩家部队、存档往返。

## 9. 未实现

- 候选人没有独立职业、属性成长、装备或初始等级；当前统一使用配置的 `infantry_militia`。
- 没有好感度、谈判、拒绝、离村倒计时或候选人自行离开。
- 招募只针对玩家部队；AI 不使用冒险者池。
- 候选人外观池与姓名为运行时随机，未接入名字生成配置资源。
