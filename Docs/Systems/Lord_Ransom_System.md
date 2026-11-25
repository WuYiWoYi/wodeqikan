# NPC 领主赎回系统

**核心逻辑：** `Scripts/Core/World/lord_ransom_manager.gd`
**配置：** `Scripts/Config/lord_ransom_config.gd`、`Data/Lords/lord_ransom_config.tres`
**事件聚合：** `Scripts/Core/World/event_center.gd`
**UI：** `Scripts/UI/WorldMap/event_feed.gd`、`Scripts/UI/WorldMap/event_detail_dialog.gd`
**状态：** 出售后赎回、领主仍被玩家关押时的家族赎买、世界时间等待、接受/拒绝/取消、失效处理、领主重回世界、右侧事件框与提醒、详情弹窗、存档恢复已实现

---

## 1. 职责

- 记录两种 NPC 领主赎买生命周期：
  - **SOLD**：玩家把领主出售给城镇酒馆后的家族赎回（12–48 游戏小时）；
  - **CAPTIVE**：领主仍关押在玩家部队中时的家族赎买（3–12 游戏小时）。
- 用世界游戏时间推进等待，到期后生成一次性家族请求。
- 接受请求时再次校验世界状态，支付赎金并把领主及其部队放回世界。
- 向事件中心提供只读的 `RANSOM` 事件；不直接操作 UI 节点。
- 关押期记录始终与玩家真实俘虏列表同步：出售、释放或转移后事件立即失效。

不负责：俘虏定价与出售结算（[Wounded_Prisoner_System.md](Wounded_Prisoner_System.md)）、贵族/家族数据维护（[Political_Hierarchy_System.md](Political_Hierarchy_System.md)）、事件面板布局（[World_Map_System.md](World_Map_System.md)）。

## 1.1 两种来源的区别

| 来源 | 触发 | 等待（世界时间） | 拒绝/取消 | 接受 |
|---|---|---|---|---|
| `SOLD` | 领主已被出售到城镇 | 12–48 小时 | “取消”只关界面，事件保留 | 支付赎金并放回世界 |
| `CAPTIVE` | 领主仍在玩家俘虏队伍中 | 3–12 小时 | “拒绝”结束事件，领主继续被关押 | 支付赎金、移出俘虏列表并放回世界 |

- 同一领主的两种来源互斥：出售会先结束关押期记录，关押中的领主不能再次出售前的旧事件继续领取。
- 两种等待都使用 `TimeManager` 世界累计时间，暂停时不推进。

## 2. 状态与数据

### 2.1 状态

| 内部 `Status` | 值 | 外部 `get_lord_state()` | 含义 |
|---|---|---|---|
| `WAITING` | 0 | `WAITING` | 已出售或已被关押，等待家族决定是否赎人 |
| `REQUESTED` | 1 | `REQUESTED` | 请求已生成，可接受；出售可取消，关押期可拒绝 |
| `ACCEPTED` | 2 | `ACCEPTED` | 已支付赎金并放回世界（出售流程保留终态） |
| `INVALID` | 3 | `INVALID` | 出售流程终止，不再产生事件 |
| `DECLINED` | 4 | `DECLINED` | 关押期请求被拒绝，同一关押周期不再请求 |

- 没有记录时 `get_lord_state()` 返回 `ACTIVE`。
- 同一贵族在同一来源下最多保留一条记录；出售与关押期记录分开去重。
- 再次出售同一贵族会重置该贵族的 `SOLD` 记录为新等待周期。
- 关押期记录在领主进入玩家俘虏列表后的下一次世界 tick 登记；
  接受或关押结束时直接移除，下一次被俘会建立新的独立周期。
- `ACCEPTED` / `INVALID` / `DECLINED` 不产生事件；重复接受返回失败且不再次支付。

### 2.2 记录字段

`LordRansomManager._records` 以 `ransom_id` 为键，记录随存档保存：

| 字段 | 说明 |
|---|---|
| `ransom_id` | `IdGenerator.RANSOM` 生成的稳定 ID；事件 ID 为 `ransom:<ransom_id>` |
| `source` | `SOLD`（出售后赎回）或 `CAPTIVE`（玩家关押期赎买）；旧档缺失时按 `SOLD` |
| `noble_id` | 稳定贵族 ID，不用显示名 |
| `noble_unit_id` | 领主单位 ID，用于恢复与校验 |
| `house_id` / `house_name` | 请求家族；名称只用于展示 |
| `lord_name` | 领主显示名，只用于展示 |
| `party_id` / `party_name` | 出售/关押时的原部队快照，用于找回原部队 |
| `sold_settlement_id` | 出售地点；`SOLD` 记录必须与单位当前 `sold_to_settlement_id` 一致 |
| `sold_world_seconds` | 出售时的世界累计秒数；`CAPTIVE` 为 -1 |
| `captured_world_seconds` | 登记玩家关押时的世界累计秒数；`SOLD` 为 -1 |
| `due_world_seconds` | 等待到期的世界累计秒数 |
| `ransom_gold` | 请求生成时一次性确定的赎金；生成后不再变化 |
| `status` | `Status` 枚举 |
| `requested_world_seconds` | 请求生成时间；未生成为 -1 |
| `accepted_world_seconds` | 接受时间；未接受为 -1 |
| `declined_world_seconds` | 关押期拒绝时间；未拒绝为 -1 |
| `paid_gold` | 实际支付给玩家的赎金 |
| `invalid_reason` | 稳定错误键，用于日志与调试 |

## 3. 生命周期

```text
SOLD：玩家在城镇酒馆出售带 noble_id 的领主
  → PrisonerTradeManager.mark_sold()
  → LordRansomManager.on_lord_sold()          WAITING（12–48 小时）
  → 世界时间达到 due_world_seconds
  → tick() 生成请求                            REQUESTED
  → 接受：支付一次赎金，领主回到世界            ACCEPTED
  → 取消：关闭界面，事件保留                    REQUESTED
  → 状态被外部改变 / 家族或据点消失             INVALID

CAPTIVE：领主进入玩家俘虏队伍
  → 下一次 tick 同步俘虏列表                    WAITING（3–12 小时）
  → 世界时间达到 due_world_seconds
  → tick() 生成赎买请求                         REQUESTED
  → 接受：支付一次赎金、移出俘虏列表并放回世界  记录移除
  → 拒绝：事件结束，领主继续被关押              DECLINED
  → 出售/释放/转移/状态改变                    记录移除，事件立即消失
```

### 3.1 出售登记

- `PrisonerTradeManager` 完成原子出售后，对 `is_noble_lord()` 的单位调用 `on_lord_sold(unit, settlement_id)`。
- 普通士兵不进入本流程。
- 出售当下只登记等待，**不立即生成事件**。
- 等待小时数在 `[wait_hours_min, wait_hours_max]` 中随机；到期时间 =
  当前世界累计秒数 + 等待小时 × `TimeManager.REAL_SECONDS_PER_GAME_HOUR`。
- 暂停时 `WorldSimulation` 不推进，等待不会缩短；1x/2x 都按游戏小时结算。

### 3.1.1 关押登记

- `tick()` 每次先调用 `_sync_captive_records()`，扫描玩家部队的 `prisoner_unit_ids`。
- 发现尚未登记且具有 `noble_id` 的领主时创建 `CAPTIVE` 记录：
  等待小时数在 `[captive_wait_hours_min, captive_wait_hours_max]`（默认 3–12）中随机。
- 同一关押周期只登记一次；`WAITING/REQUESTED/DECLINED` 记录都会阻止重复登记。
- 领主离开玩家俘虏列表（出售、释放、转移或状态改变）后，记录在同步阶段直接移除；
  下一次被俘会建立新的独立周期。
- 关押登记时间取自首次同步到的世界累计秒数，随后写入 `captured_world_seconds`。

### 3.2 请求生成

- `LordRansomManager.tick()` 由 `WorldSimulation` 每世界 tick 调用，并由读取接口兜底调用。
- 仅当记录为 `WAITING`、当前状态校验通过且 `now >= due_world_seconds` 时生成一次请求。
- 赎金在生成时随机确定并写入 `ransom_gold`，最小值为配置下限，且至少 101 金币；生成后固定。
- `CAPTIVE` 记录若暂时找不到家族据点，会继续保持等待而不是生成无法释放领主的请求。
- 请求生成写入世界日志；同一记录不会重复生成请求。

### 3.3 接受

`accept_ransom(ransom_id)` 按来源分支，但都遵循“重新校验 → 先写终态 → 支付一次”：

1. 记录存在且状态为 `REQUESTED`；
2. 重新执行对应来源的完整资格校验；失败则按规则失效并返回 `{success:false, reason}`；
3. 先把记录写为 `ACCEPTED` 并记录 `paid_gold`，防止重复点击二次支付；
4. `unit.mark_ransomed()` 清除出售/俘虏状态；
5. 向 `PlayerProfile` 增加一次赎金；
6. 找回或重建领主部队，把领主放回世界；
7. 写入世界日志。

`CAPTIVE` 分支在第 4 步前必须先成功调用
`PartyManager.remove_prisoner(player_party_id, unit_id)`；移除失败则不支付并保留请求。
接受成功后直接移除该关押期记录，使同一周期不能再次领取。

返回 `{ success, gold, reason }`。重复接受返回失败，金币不变。

### 3.4 取消与拒绝

- **SOLD**：`decline_ransom(ransom_id)` 只确认记录仍为 `REQUESTED`。
  关闭弹窗不改变记录、不释放领主、不支付金币；事件继续保留。
- **CAPTIVE**：`reject_captive_ransom(ransom_id)` 把记录写为 `DECLINED` 并立即结束事件；
  领主继续留在玩家俘虏队伍中，不支付金币，同一关押周期不再生成请求。
  拒绝后仍可正常前往城镇出售该领主。
- 忽略事件不会暂停世界，也不阻止其他玩法。

## 4. 资格校验

每次读取事件、tick 和接受前都从当前实体数据重新校验，不信任 UI 缓存：

`SOLD` 记录（`_check_record`）：

| 条件 | 失败键 |
|---|---|
| 单位仍存在 | `lord_missing` |
| 单位仍具有 NPC 领主身份 | `lord_identity_missing` |
| 单位不是任何部队的俘虏 | `lord_is_captive` |
| `sold_to_settlement_id` 与记录一致且非空 | `sold_state_changed` |
| 单位没有回到部队 | `lord_in_party` |
| 贵族存在且存活 | `noble_missing` |
| 贵族家族存在 | `house_missing` |
| 家族有可用据点（生成/接受请求时） | `no_friendly_settlement` |

`CAPTIVE` 记录（`_check_captive_record`）：

| 条件 | 失败键 |
|---|---|
| 单位、贵族、家族与玩家部队存在 | `manager_missing` / `lord_missing` / `noble_missing` / `house_missing` |
| 单位仍具有 NPC 领主身份 | `lord_identity_missing` |
| 单位未被出售 | `sold_state_changed` |
| `prisoner_owner_party_id == 玩家部队 ID` | `lord_not_prisoner` |
| 玩家部队 `prisoner_unit_ids` 仍包含该单位 | `lord_not_prisoner` |
| 单位没有回到部队 | `lord_in_party` |
| 家族有可用据点（接受请求时） | `no_friendly_settlement` |

- `SOLD` 失败标记 `INVALID`；`CAPTIVE` 失败直接移除记录，事件立即从事件中心和右侧事件框消失。
- 若事件在详情弹窗打开期间失效，弹窗在下一帧刷新时自动关闭，接受按钮不再生效。
- 领主在事件待处理期间被再次出售、重新关押、释放或转移时，下一次校验立即失效，不能领取赎金。
- 关押期同步优先于事件展示：玩家出售或释放领主的同一帧之后，旧赎买事件不会再被读取到。

## 5. 领主重回世界

### 5.1 据点选择

- 优先选择该领主本人拥有的家族封地。
- 否则选择家族任意封地（按 `settlement_id` 稳定排序）。
- 仅在异常恢复（家族/据点缺失）时允许退回任意地点（按 `settlement_id` 稳定排序）。
- 找不到据点时不伪造位置，流程失效。

### 5.2 部队复用

恢复顺序：

1. 贵族当前 `party_id` 指向的非玩家部队；
2. 任意 `leader_noble_id == noble_id` 的非玩家部队；
3. 记录中的 `party_id` 快照；
4. 都没有时才创建新的 `FAMILY` 部队。

- 绝不创建第二支由同一贵族指挥的部队；旧的无主/失效部队优先复用。
- 复用后清除移动、战斗、追击、攻击意图与遭遇响应的运行时状态。
- AI 类型为 `NONE` 时恢复为 `PATROL`；缺少巡逻点时在据点附近生成稳定巡逻点。
- `WorldInitializer.restore_lord_party()` 把领主放回领袖位置，并按家族模板补充士兵：
  1 名老兵骑乘、3 名训练骑乘、2 名训练步兵、3 名民兵；已存在的相同 `config_id + 骑乘` 单位不重复添加。
- `PartyData.leader_noble_id` 与 `NobleData.party_id` 保持双向一致。

## 6. 失效与异常恢复

- `house_missing` / `no_friendly_settlement`：标记 `INVALID`，并尽量清除出售状态、把领主放回任意可用地点，避免永久卡在“已出售”。
- 其他失效（单位、贵族、身份或出售状态改变）：只标记 `INVALID`，不支付金币、不重建部队。
- 失效记录保留在存档中作为历史，不再生成事件。
- 恢复失败时 `push_error` 报告，不静默吞掉。

## 7. 事件中心与 UI

### 7.1 事件数据

`EventCenter.get_events()` 追加 `_collect_ransom_events()`，每条事件包含：

| 字段 | 说明 |
|---|---|
| `event_id` | `ransom:<ransom_id>` |
| `type` / `type_text` | `RANSOM` / `赎回` |
| `tag` | `赎回`（`SOLD`）或 `赎买`（`CAPTIVE`），供事件框标签使用 |
| `source` | `SOLD` / `CAPTIVE` |
| `title` | `家族赎回请求`（`SOLD`）或 `家族赎买请求`（`CAPTIVE`） |
| `detail` | 含领主、关押地点/玩家俘虏队伍、家族、赎金与操作说明 |
| `actionable` / `action_type` | `true` / `RANSOM` |
| `ransom_id` / `noble_id` / `house_id` | 稳定 ID |
| `house_name` / `lord_name` / `gold` | 展示与结算数值 |
| `due_world_seconds` | 到期时间，只读 |
| `decline_label` | `取消`（`SOLD`）或 `拒绝`（`CAPTIVE`） |
| `decline_ends_event` | `false`（`SOLD`，取消只关界面）或 `true`（`CAPTIVE`） |

- 事件只来自当前有效的 `REQUESTED` 记录；已完成、已失效、已拒绝、仍在等待的记录不显示。
- 事件中心只读，不创建、不修改、不保存事件副本。

### 7.2 右侧事件框与待处理提醒

- `EventFeed` 固定在大地图右侧，垂直排列可滚动条目。
- 没有可操作事件时隐藏；有时显示事件类型标签、标题、领主/家族与赎金摘要。
- 条目按钮名称为 `EventFeedItem_<消毒后的 event_id>`，供测试定位。
- 显示与滚动不暂停世界时间。
- 点击事件发出 `event_selected(event_id)`，由大地图打开详情弹窗。
- `EventReminder` 是右侧居中的小型提醒，只显示“有新的事件待处理（N）”：
  - 可见性完全由 `EventCenter.get_actionable_events()` 的数量决定；
  - 没有可操作事件时隐藏，有事件时持续显示，不因玩家忽略而消失；
  - 不暂停世界、不拦截地图操作；
  - 点击时若只有一条事件则直接打开详情，多条时打开事件中心；
  - 不维护独立事件状态，不重复创建提醒。

### 7.3 详情弹窗

- `EventDetailDialog` 读取事件中心当前事件；事件无效时不打开。
- 显示标题、领主、家族、赎金、正文与状态提示。
- “接受”调用 `LordRansomManager.accept_ransom()`。
- `SOLD` 的“取消”只关闭弹窗；`CAPTIVE` 的“拒绝”调用 `reject_captive_ransom()` 并结束事件。
- 按钮文案与是否结束事件由事件字段 `decline_label` / `decline_ends_event` 决定。
- 弹窗打开时压入暂停原因，关闭时成对释放；同一原因按引用计数。
- 每帧调用 `refresh_if_needed()` 重新校验；事件失效时立即关闭并刷新事件框。
- 接受前管理器再次校验领主仍是玩家俘虏；UI 只发起意图，不直接修改单位、贵族或金币。

## 8. 存档

- `WorldContext.to_save_data()` 写入 `ransoms = lord_ransom_manager.to_dict()`。
- `load_from_save_data()` 在政治数据恢复后调用 `load_from_dict()`。
- 读档校验：
  - `ransom_id` / `noble_id` / `noble_unit_id` 缺失的记录丢弃；
  - 非法状态 clamp 到枚举范围；`source` 非法时回退 `SOLD`（兼容旧档）；
  - 同一贵族在同一来源下只保留最近一条；
  - `SOLD` 等待/请求记录重新校验，失效记录不再生成事件；
  - `CAPTIVE` 记录重新校验玩家俘虏列表；已出售/释放的旧请求直接丢弃。
- 世界时间、到期时间、来源与赎金随档恢复；读档不会立即重复生成请求。
- 已完成/已失效/已拒绝记录写入存档后不会重新出现。
- 详细 Schema 字段见 [Save_System.md](Save_System.md) 第 22 节。

## 9. 配置

| 配置 | 字段 | 默认值 | 说明 |
|---|---|---|---|
| `LordRansomConfig` | `enabled` | `true` | 关闭后出售/关押领主都不启动赎回流程 |
| `LordRansomConfig` | `wait_hours_min` / `wait_hours_max` | `12` / `48` | 出售后的等待游戏小时，自动修正为 min ≤ max |
| `LordRansomConfig` | `captive_wait_hours_min` / `captive_wait_hours_max` | `3` / `12` | 玩家关押期间的等待游戏小时，自动修正为 min ≤ max |
| `LordRansomConfig` | `ransom_gold_min` / `ransom_gold_max` | `150` / `400` | 两种来源共用的赎金范围，自动修正为 ≥ 101 且 min ≤ max |
| `PrisonerPriceConfig` | `lord_price` | `100` | 出售领主时玩家获得的金币，与赎金独立 |

- 静态 `.tres` 配置不进入存档。
- UI 与管理器都通过配置取值，禁止写死等待时间或赎金。

## 10. 不变量

- 每个贵族在同一来源下最多一条记录、最多一支由其指挥的部队。
- 同一领主同一时间最多一条 `REQUESTED` 事件；出售与关押来源互斥。
- `ransom_id` 只由 `IdGenerator` 生成，随存档保存，永不复用。
- 事件 ID 只由 `ransom_id` 派生，不依赖数组下标或显示名。
- 接受只支付一次；终态/已移除记录不能再次参与事件。
- 只有当前世界状态仍满足条件的事件可显示、可领取。
- 关押期拒绝只结束当前请求，不阻止之后出售该领主。
- `LordRansomManager` 是赎买记录的唯一写者；EventCenter、EventReminder 与 UI 只读。
- 暂停、忽略事件或关闭事件框不改变等待进度。

## 11. 实现状态

| 项 | 状态 |
|---|---|
| 出售登记与 12–48 小时世界时间等待 | 已实现 |
| 玩家关押期登记与 3–12 小时赎买请求 | 已实现 |
| 请求生成与固定赎金 | 已实现 |
| 接受/取消（出售）与接受/拒绝（关押） | 已实现 |
| 重复接受、重复请求与重复结算防护 | 已实现 |
| 资格校验与立即失效（出售/释放/转移） | 已实现 |
| 领主部队复用/重建与 AI 恢复 | 已实现 |
| 家族/据点缺失的异常恢复 | 已实现（关押期无据点时继续等待） |
| 右侧事件框与待处理提醒 | 已实现（无事件时隐藏，提醒不暂停世界） |
| 详情弹窗与失效自动关闭 | 已实现 |
| 存档/读档与去重（含来源与关押时间） | 已实现（v8 新增记录，当前 Schema v10 保持不变） |
| 多家族竞价、赎金谈判、拒绝后的冷却 | 未实现 |
| 领主人质期间的外交影响 | 未实现 |

## 12. 相关文档

- [Wounded_Prisoner_System.md](Wounded_Prisoner_System.md)：出售价格与俘虏归属。
- [Political_Hierarchy_System.md](Political_Hierarchy_System.md)：贵族、家族与封地。
- [World_Map_System.md](World_Map_System.md)：事件框、详情弹窗与大地图 UI。
- [Save_System.md](Save_System.md)：当前 Schema v10 与 `ransoms`。
- [Time_System.md](Time_System.md)：世界累计时间与暂停。
