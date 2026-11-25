# 冒险者招募系统

**核心逻辑：** `Scripts/Core/World/adventurer_recruitment_manager.gd`
**候选数据：** `Scripts/Entities/Settlement/adventurer_candidate_data.gd`
**配置：** `Scripts/Config/recruitment_config.gd`、`Data/Recruitment/recruitment_config.tres`、`Data/Settlements/settlement_economy_config.tres`
**状态：** 已实现：每村普通候选人池、世界时间刷新、村庄 NPC 对话按 tier 支付金币招募、离开村庄清理；贵族冒险者特殊候选人；玩家/NPC 共用招募流程与大地图提示。

---

## 1. 定位与边界

冒险者是村庄里的独立可招募 NPC，与采邑征召的区别：

| 项 | 采邑征召 | 冒险者招募 |
|---|---|---|
| 来源 | 领主自有封地储备 | 村庄候选人池 |
| 一次获得 | 固定 6 人成组 | 1 人 |
| 费用 | 储备 + 人口 + 繁荣度 | 按候选人 tier：Tier1 = 5 金币，Tier3 = 400 金币 |
| 入口 | 地图面板 / 头人对话 | 点击候选人 NPC 对话 |
| 目标部队 | 领主部队（玩家或 AI） | 玩家部队或领主自有村庄的 NPC 部队 |
| 上限 | 每村储备 4 组 | 每村最多 5 名普通候选人；另加 1 名贵族冒险者 |

- 候选人拥有独立 `UnitData` 身份快照，但未招募前不注册进 `UnitManager` 仓储，也不属于任何部队。
- 只有招募成功后才把单位注册进 `UnitManager`，并通过 `PartyManager.add_member()` 加入目标部队。
- 贵族冒险者是候选人的特殊类型：固定 1 名、三级士兵、自带真实马匹实例；不是独立系统。
- 管理器不创建场景节点；村庄场景只读取候选人数据生成 NPC 表现。

## 2. 候选数据

`AdventurerCandidateData`：

| 字段 | 说明 |
|---|---|
| `candidate_id` | `CANDIDATE_000001`，由 `IdGenerator` 生成 |
| `display_name` | 持久化随机姓名 |
| `settlement_id` | 所属村庄 |
| `unit_config_id` | 招募后使用的兵种配置（普通默认 `infantry_militia`；贵族为 `infantry_veteran`） |
| `is_noble` | 是否为贵族冒险者；默认 false，不占用普通候选人上限 |
| `world_position` | 村庄小场景内的固定候选位置 |
| `status` | `AVAILABLE` / `RECRUITED_PENDING_DEPARTURE` |
| `unit_id` | 候选人独立单位身份 ID；招募后关联真实单位 |
| `unit_data` | 候选人独立 UnitData 完整快照（含装备、骑乘关系、外观） |
| `mount_instance` | 贵族自备战马的真实 `MountInstanceData` 字典；普通候选人为空 |
| `appearance` | 创建时一次性生成的外观字典，招募后原样复制给真实单位 |

`is_available()` 只在 `AVAILABLE` 状态下返回 true。
`get_mount_instance_data()` 返回贵族携带的真实马匹实例（优先 `mount_instance`，旧档回退 `unit_data.mount_instance`）。

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

### 3.1 贵族冒险者

- 每村最多 1 名，保存在 `SettlementData.noble_adventurer_candidate`，不加入普通 `adventurer_candidates` 数组，因此不占 5 名普通候选人上限，也不影响普通刷新数量。
- 只有村庄 `has_owner()` 时生成；`noble_adventurer_spawned` 记录“该村已生成过”。无主村庄之后获得归属时由世界 tick 补生成。
- 兵种固定读取 `noble_adventurer_unit_config_id`（默认 `infantry_veteran`，tier 3），初始战斗经验固定为 2 级（普通士兵）；招募价 400，日薪 7。
- 贵族不是雇佣兵（`is_mercenary = false`），招募后可以正常更换装备与坐骑。
- 通过 `UnitManager.create_detached_unit()` 创建独立身份，再以 `UnitManager.equip_detached_mount()` 装备 `MountInstanceData.create_random(fief_mount_equipment_id)` 的真实战马；单位保持 `is_mounted = true` 与 `equipment["MOUNT"]` 关系。
- 招募后 `noble_adventurer_candidate` 记录离开清理时置空，`noble_adventurer_spawned` 保持 true，读档不会重新生成。
- 普通候选人刷新逻辑完全不感知贵族字段。

## 4. 招募流程与回滚

`recruit_candidate(settlement_id, candidate_id, profile, recruiter_lord_id = "")`：

1. 校验村庄、候选人存在、`AVAILABLE`、玩家档案有效。
2. 贵族候选人额外校验 `is_noble_recruit_authorized(settlement, recruiter_lord_id)`：直接复用 `FiefRecruitmentManager.is_authorized_owner()`；明确 `owner_noble_id` 时只认该贵族，未指定时认所有者家族领袖。
3. 校验金币 >= `RecruitmentConfig.get_civilian_recruit_cost(candidate.tier)`：Tier1 = 5，Tier3 = 400。
4. 校验玩家部队存在且 `is_available_for_world()`。
5. 读取候选人兵种配置；优先使用候选人独立 `unit_data` 快照转化为真实单位，旧档缺失时新建。贵族保留三级属性与战马实例。
6. 加入玩家部队。
7. 扣除金币。
8. 写入 `recruit_source = "adventurer_recruitment"`、村庄 ID、阵营与加入时间。
9. 候选人状态改为 `RECRUITED_PENDING_DEPARTURE`，记录 `unit_id`。
10. 发出 `EventBus.adventurers_recruited(party_id, settlement_id, counts, total, true)`。

NPC 领主招募普通冒险者：

`recruit_normal_candidates_for_party(settlement_id, party_id, recruiter_lord_id)` 返回 `{success, total, counts}`：

- 复用同一所有权授权与 `_recruit_candidate_into_party()` 单位/扣金币/入队流程，payer 为目标 `PartyData`。
- 只招募 `is_noble == false` 的 `AVAILABLE` 候选人；金币不足时停止，不留部分失败状态。
- 每招募一人立即从 `settlement.adventurer_candidates` 移除，避免重复招募。
- 成功后发出同一条 `EventBus.adventurers_recruited(..., false)`；大地图据此显示与采邑征召一致的浮动提示。
- 贵族冒险者不在此接口内；NPC 不会招募贵族。

失败处理：

- 加入部队失败或扣金币失败时，移除并删除刚创建的单位，不扣金币、不改变候选人状态；
- 重复招募同一候选人返回 false，不产生第二个单位；
- 金币不足不扣款；
- 非村庄拥有者招募贵族或通过 NPC 接口招募普通冒险者都会被拒绝，并写入 `last_error`。

## 5. 离开村庄与清理

- 已招募候选人在玩家离开村庄前仍保留在 `adventurer_candidates` 中，场景中显示“已招募”标记，避免对话中途消失。
- `VillageScene._request_exit()` 调用 `cleanup_departed_candidates(settlement_id)`：
  - 只移除 `RECRUITED_PENDING_DEPARTURE` 的候选人记录；
  - 贵族候选人为 `noble_adventurer_candidate` 时置空该字段，不重置 `noble_adventurer_spawned`；
  - 真实 `UnitData` 不受影响；
  - 重复调用幂等。
- 再次进入村庄时，已招募候选人的记录已被清理，不会重复显示，也不会重复招募；贵族不会重新生成。

## 6. 村庄表现与对话

- 每个可招募候选人生成一个运行时 NPC 表现节点，位置来自 `candidate.world_position`，外观来自持久化 `appearance`。
- 表现节点与名称标签必须使用 `candidate.world_position`（为空时按 `CANDIDATE_POSITIONS` 回退）；不得使用村庄场景根节点的 `position`，否则所有候选人会叠在世界原点、正常镜头内不可见。
- 村庄场景只读取候选人数据生成表现，不在打开界面时生成新候选人；重复进入村庄不会重复创建。
- 点击半径与头人一致：鼠标点击候选 NPC 且玩家距离 <= 130 像素才打开对话。
- 对话选项 action 为 `recruit_adventurer`；显示费用与候选人姓名。
- 招募成功后关闭对话并刷新候选 NPC 的“已招募”标签；失败显示 `last_error`。
- 已招募候选人再次对话不再提供招募选项。
- `EventBus.adventurer_recruited` 由 `WorldLogManager` 写成“你在{村庄}招募了冒险者{姓名}。”。
- 村庄右上角复用大地图的 `WorldLogPanel`，与大地图共享同一份日志历史。

### 6.1 贵族冒险者表现

- 人物与普通候选人分开保存表现节点：`_noble_visual`、`_noble_mount_visual`、`_noble_label`，不改变 `get_candidate_count()` 等普通候选人接口。
- 人物使用临时 `UnitData` 并把表现层 `is_mounted` 设为 false，按步行显示；不修改候选人快照或真实单位数据。
- 战马是独立 `HorseVisual` 节点，位置为 `NOBLE_CANDIDATE_POSITION + NOBLE_MOUNT_VISUAL_OFFSET`，使用候选人真实马匹实例的毛色/马鞍重建，人物与马匹位置不重叠。
- 名称标签显示“姓名（贵族·3级）”；招募后显示“已招募”。
- 与贵族对话始终可查看；仅当 `is_noble_recruit_authorized()` 通过时才提供招募选项，否则显示“只有村庄拥有者可以招募”。
- 权限每次打开对话时实时读取当前村庄所有权，所有权变更后立即生效。

## 7. 持久化

- 候选人的 ID、姓名、村庄、兵种、位置、状态、关联单位 ID 与外观全部通过 `SettlementData.to_dict()/from_dict()` 往返。
- `adventurer_refresh_elapsed` 随地点保存；读档保留已累计时间。
- 读档不重新生成候选人，只修正边界与刷新计时。
- 旧存档没有候选人字段时按空列表恢复；下一次世界 tick 按刷新规则补充。
- 新游戏/读档的初始补齐只由 `WorldInitializer` 与 `WorldContext` 明确调用，避免读档重复生成。
- 阶段 13 起候选人快照随存档保存；读档先 `ensure_candidate_identities()` 补旧档缺失快照，再恢复候选人数，保证同一候选人不会生成第二个 Unit。
- `SettlementData` 新增 `noble_adventurer_candidate` 与 `noble_adventurer_spawned`；旧存档缺少字段时按 `null` / `candidate != null` 恢复，因此不会重复生成或丢失已招募标记。
- 贵族候选人的 `is_noble`、三级 `unit_config_id`、`unit_data`、`mount_instance`、招募状态都随存档往返；读档不会为同一候选人再创建第二匹马或第二个单位。

## 8. 测试

- `Tests/SystemTests/fief_adventurer_system_test.tscn`：Tier1 = 5 / Tier3 = 400 金币扣款、只生成 1 个单位、姓名/外观持久化、重复招募拒绝、离开清理幂等、刷新上限、日志。
- `Tests/SystemTests/fief_adventurer_ui_test.tscn`：村庄候选 NPC、距离交互、对话按钮、已招募标记、离开清理、日志面板。
- `Tests/SystemTests/stage13_village_candidates_test.tscn`：初始候选人数量/上限、独立 Unit 身份、村庄归属、不重复、招募后进入玩家部队、存档往返。
- `Tests/SystemTests/noble_adventurer_recruitment_test.tscn`：贵族三级身份/真实战马、所有权拒绝、招募合并与防重复、清理后不复活、存档往返、村庄步行人物+独立战马、NPC 普通冒险者招募与事件。

## 9. 未实现

- 普通候选人仍统一使用配置的 `infantry_militia`，没有独立职业与成长路线。
- 没有好感度、谈判、拒绝、离村倒计时或候选人自行离开。
- 贵族冒险者只有固定 1 种三级配置；未实现按村庄文化/家族选择兵种。
- NPC 领主不会招募贵族冒险者，只招募普通候选人。
- 候选人外观池与姓名为运行时随机，未接入名字生成配置资源。
