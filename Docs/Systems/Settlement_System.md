# 村庄、城镇与城堡系统

**核心数据：** `Scripts/Entities/Settlement/settlement_data.gd`
**核心逻辑：** `Scripts/Core/World/settlement_manager.gd`
**状态：** 数据仓储、地图图标、基础交互面板、村庄小场景入口、封地归属、采邑储备、冒险者候选人、村庄/城镇市场入口与城镇酒馆入口已实现

---

## 1. SettlementData

| 字段 | 说明 |
|---|---|
| `settlement_id` | `SETTLEMENT_000001` |
| `display_name` | 显示名 |
| `settlement_type` | VILLAGE / TOWN / CASTLE |
| `world_position` | 大地图坐标（像素） |
| `faction_id` | 所属阵营 |
| `family_id` | 视觉家族 `FAMILY_*`；用于徽章、名称与外观 |
| `owner_house_id` | 政治家族 `HOUSE_*`；封地归属与征召授权的唯一权威，空字符串表示无主 |
| `scene_path` | 该地点小场景路径；旧存档/城镇/城堡为空 |
| `population` | 人口；采邑征召成本与补充周期因子 |
| `prosperity` | 繁荣度；采邑征召成本与补充周期因子 |
| `tax_base` | 税收基数，默认来自经济配置 |
| `tax_income_per_day` | `TaxCalculator` 计算后的每日税收缓存 |
| `fief_recruitment_stock` | 当前可征召采邑组数 |
| `fief_recruitment_capacity` | 采邑储备上限；城镇/城堡为 0 |
| `fief_recruitment_elapsed` | 距离下一组储备补充的累计世界秒 |
| `adventurer_candidates` | 村庄冒险者候选人列表 |
| `adventurer_refresh_elapsed` | 距离下一名候选人的累计世界秒 |
| `garrison_unit_ids` | 驻军单位 ID |
| `is_under_siege` | 是否被围城 |

初期只需要基础信息，其他字段逐步增加。

### 1.1 SettlementManager

`SettlementManager` 由 `WorldContext` 持有，职责：

- 依据 `IdGenerator` 创建地点，ID 格式 `SETTLEMENT_000001`。
- 按 ID 查询/删除地点。
- `to_dict()` / `load_from_dict()` 存档序列化。
- 不负责地图图标、交互面板或地点模拟。

初始地点以 `Data/WorldMap/world_map_definition.tres` 为唯一来源：当前共 61 个（36 村庄、8 城镇、17 城堡），坐标由参考图像素 × 5 得到。地点 ID 由 `IdGenerator` 按创建顺序生成，不在文档中固定。

只有以下 7 个地点保留旧世界已确认的所有权，其余 54 个无主；重建地图不按位置补写归属：

| 名称 | 类型 | 世界坐标 | 旗帜家族 `family_id` | 政治归属 `owner_house_id` |
|---|---|---|---|---|
| 巴里 | 村庄 | (3606, 2286) | `FAMILY_BARI` | `HOUSE_BARI` |
| 灰石堡垒 | 城堡 | (3865, 944) | `FAMILY_BURKNANIA` | `HOUSE_BARI` |
| 墨西西 | 村庄 | (5247.5, 4949) | `FAMILY_MOXIXI` | `HOUSE_MOXIXI` |
| 伯克纳尼亚 | 城镇 | (1944, 607.5) | `FAMILY_BURKNANIA` | `HOUSE_BURKNANIA` |
| 伯克纳 | 村庄 | (2463, 973.5) | `FAMILY_BURKNANIA` | `HOUSE_BURKNANIA` |
| 奥林德斯堡 | 城堡 | (4817.5, 4233) | `FAMILY_OLIN` | `HOUSE_OLIN` |
| 奥林 | 村庄 | (5439, 4386) | `FAMILY_OLIN` | `HOUSE_OLIN` |

- 灰石堡垒体现“旗帜家族 ≠ 政治归属”：视觉旗帜来自伯克纳家族，所有权属于巴里家族。
- 地点最短间距 ≥ 250 世界像素；全部位于不规则边界内且不在湖泊/山脉中。名称标签在默认 1.5x 缩放下不重叠，最小 0.5x 下可能重叠（KI545）。
- 旧存档保留原坐标与原所有权，不迁移到新布局。

## 2. 地点交互

```text
玩家左键点击地点（点击判定半径 45）
  ├── 玩家与地点距离 <= 40（交互半径）
  │     → WorldMapManager.stop_party(玩家)
  │     → TimeManager.set_base_world_speed(0)
  │     → TimeManager.push_pause(&"ui_panel")
  │     → 立即打开左侧交互面板
  └── 否则：
        → 记录待交互地点 ID
        → WorldMapManager.set_party_target(玩家, 地点坐标)
        → 基础倍率切回 1x，世界继续运行
        → 玩家部队自动移动
        → 到达交互半径且移动停止后：
              → 清空待交互 ID
              → stop_party + 基础倍率 0 + push_pause(ui_panel)
              → 打开左侧交互面板
  → 显示名称、类型
  → 村庄：显示“进入村庄” + “购买补给” + “离开地点”
  → 城镇：显示“交易市场” + “离开地点”
  → 城堡：只显示“离开地点”
```

触发检测位于大地图场景控制器：

- 点击地点只代表“前往该地点”；远距离点击不会立即打开面板、停止部队或暂停世界。
- 只有玩家主动点击地点才创建待交互状态；普通移动、追击、跟随或路过不会创建，也不会自动触发。
- 已在地点 40 像素交互半径内时允许直接打开面板，不执行无意义移动。
- 点击普通地图位置、点击部队、点击另一个地点或外部停止时，旧待交互状态会被清除或替换；不会在未来误弹面板。
- 面板打开期间时间为 0。
- 关闭面板时移除 `ui_panel`，但基础倍率保持 0。
- 玩家必须主动选择 1x / 2x 才会继续世界推进。
- 点击另一个地点会替换待交互目标；到达后只打开最终目标的面板。
- 待交互地点 ID 是大地图运行时状态，不进入存档。

Milestone 1 只做基础面板；阶段 6 起村庄面板增加进入小场景入口；阶段 7 起所有地点统一采用“点击设置目标、到达后打开”的规则。

## 3. 后续交互

- 招募士兵。
- 城堡驻军与围城。
- 接取任务。
- NPC 对话。
- 进入实际小场景（Village/Town/Castle）。
- 城堡驻军管理。
- 地点归属变更。

每项功能都必须：

- 通过明确的管理器接口修改数据；
- 在打开面板时正确压入暂停原因；
- 在离开时成对移除；
- 更新本文件与存档结构。

## 4. 进入小场景（阶段 6 已实现）

```text
交互面板选择“进入村庄”
  → WorldMap.enter_village(settlement_id)
      ├── 校验 settlement_type == VILLAGE 与 scene_path 存在
      ├── 记录 current_settlement_id / 进入前基础倍率
      ├── push_pause(small_scene) → pop_pause(ui_panel)
      └── SceneManager.change_scene(scene_path)
  → VillageScene：WorldTime = 0，SceneTime = 1.0
```

- 三个村庄当前共用 `res://Scenes/Village/village.tscn`；每个 `SettlementData.scene_path` 独立保存，后续可逐村替换。
- 返回大地图时恢复进入前基础倍率，并写入一次性地点交互锁，避免玩家站在村口时立即重开面板。
- 城镇/城堡尚未接入小场景。

详见 [Village_System.md](Village_System.md)。

## 5. 驻军

- `garrison_unit_ids` 与 `PartyManager` 的成员关系类似，但驻军不随部队移动。
- 驻军单位仍使用 `UnitData`，`current_party_id` 为空。
- 驻军加入/离开必须统一经过未来的 `SettlementManager` 或明确接口。
- 城堡攻防阶段再实现战斗与归属变更。

## 6. 地点模拟

当前只实现与征召直接相关的时序：

- `FiefRecruitmentManager.tick()`：按人口/繁荣度调整的周期补充采邑储备。
- `AdventurerRecruitmentManager.tick()`：按固定周期向村庄候选人池补充冒险者。
- 两者都只由 `WorldSimulation` 调用，暂停时不推进。

仍不模拟：

- 人口自然增长/减少。
- 繁荣度自然变化。
- 每日税收实际扣除。
- 驻军补充、被围城、归属变更。

后续由 `WorldSimulation` 按较低频率推进时，频率必须低于世界 tick（例如每游戏日一次），不得每 0.1 秒计算。

## 7. 实现状态

| 项 | 状态 |
|---|---|
| `SettlementData` 与序列化 | 已实现 |
| `SettlementManager` | 已实现并接入 `WorldContext` |
| 大地图标记 | 已实现（程序绘制村庄/城堡/城镇） |
| 交互面板 | 已实现（名称/类型/离开；村庄提供进入与购买补给，城镇提供交易市场） |
| 触发停止与暂停 | 已实现 |
| 村庄小场景进入/返回 | 已实现（scene_path + small_scene 暂停 + 返回锁） |
| 村庄购买补给入口 | 已实现（大地图按钮 + 村长对话，面包/草料） |
| 市场入口 | 已实现（村庄与城镇显示，城堡不显示；按地点类型判断，名称不参与） |
| 村庄/城镇市场库存 | 已实现（`MarketManager`，按地点独立存档；城堡无市场） |
| 城镇/城堡小场景 | 未实现 |
| 封地归属 `owner_house_id` | 已实现（2026-11-27 起只归属家族；读档校验家族存在） |
| 地点层级 1/2/3 与仅村庄征召 | 已实现（阶段 8） |
| 采邑储备/补充/税收缓存 | 已实现（`FiefRecruitmentManager`） |
| 冒险者候选人 | 已实现（`AdventurerRecruitmentManager`） |
| 驻军 | 未实现 |
| 人口/繁荣度自然变化与每日税收扣除 | 未实现 |

## 8. 待确认

- 村庄/城镇/城堡是否共用同一交互面板（当前共用）。
- 地点交互检测是否迁移到世界模拟层。
- 进入小场景后返回大地图时的精确时间恢复规则。

## 9. 家族归属与固定屏幕名称（阶段 6 新增）

- `SettlementData.family_id`：地点所属家族，持久化；只决定地图名称旁的家族旗帜，不改变 `faction_id` 或外交。
- 新游戏地点坐标见第 1.1 节当前表；巴里、墨西西、灰石堡垒等全部由 `WorldMapDefinition` 提供，不再在 `Settlement` 文档或脚本中维护旧坐标。
- 地点名称不再由 `SettlementIcon` 在世界空间绘制；改为固定屏幕 UI 层 `SettlementNameTag`：
  - 每帧用 `get_viewport().get_canvas_transform() * settlement.world_position` 更新位置；
  - 字体与标签尺寸不随相机缩放；
  - 名称左侧绘制圆形家族旗帜，旗帜等比缩放；
  - 整个标签 `MOUSE_FILTER_IGNORE`，不参与地点点击、选择或悬浮判定。
- 地点点击判定仍使用 `SettlementData.world_position` 与固定世界像素半径，不依赖名称标签。

## 10. 封地归属、税收与征召入口（阶段 7 新增）

- 现行规则：`owner_house_id` 是封地归属的唯一权威；`family_id` 仅用于视觉家族，`faction_id` 不参与权限判断。没有个人所有者字段，也没有兼容副本。
- 地点面板读取并显示：
  - 名称、类型；
  - 所有者家族显示名（无主时显示“无主”）；
  - 家族显示名；
  - 人口、繁荣度；
  - `TaxCalculator` 计算后的每日税收缓存；
  - 采邑储备与补充状态。
- 只要玩家贵族所属家族等于 `owner_house_id` 即可显示“征召采邑”按钮；家族领袖、男爵、骑士与普通成员一致。按钮在储备为 0 或地点非村庄时禁用。
- 村庄头人对话只在玩家家族拥有该村庄且有储备时追加同一征召动作。
- 两个入口都调用 `FiefRecruitmentManager.recruit_group()`，UI 不计算编制、成本或周期。
- 税收公式、人口/繁荣度成本和储备补充参数集中在 `SettlementEconomyConfig`；UI 与 `SettlementData` 不重复实现。
- 读档时每个非空 `owner_house_id` 必须指向存在的家族；旧存档个人所有者由 `WorldContext` 解析为贵族所属家族后清空。
- 详细流程见 [Fief_Recruitment_System.md](Fief_Recruitment_System.md)，候选人见 [Adventurer_Recruitment_System.md](Adventurer_Recruitment_System.md)。

## 11. 村庄/城镇市场入口（阶段 11 新增，阶段 12 扩展）

- 入口按钮：`SettlementMarketButton`，按 `MarketManager.is_market_settlement()` 判断，即村庄与城镇显示，城堡不显示；不通过地点名称判断。
- 按钮文本：村庄为“购买补给”，城镇为“交易市场”。
- 村庄另有村长对话入口“购买补给（面包、草料）”，与大地图按钮共用同一库存与结算入口。
- 点击入口：
  1. 重新读取 `_settlement_latch_id` 对应地点并校验地点类型；
  2. 确认 `MarketManager` 已为该地点初始化库存，缺失时调用 `ensure_markets()`；
  3. 打开独立 `MarketPanel`，隐藏地点面板；
  4. 继续持有同一个 `PAUSE_REASON_UI_PANEL` 暂停原因，世界保持暂停。
- 市场关闭/取消后恢复地点面板，不擅自恢复 1x/2x；只有玩家离开地点时才成对释放 `ui_panel`。
- 市场面板是屏幕覆盖层，不切换 Town 场景；`Scenes/Town/town.tscn` 仍保持空场景占位。
- 村庄市场出售面包/草料，城镇市场额外出售马匹；库存按地点独立持久化，卖光后读档不会补满。
- 市场库存与交易规则见 [Inventory_Economy_System.md](Inventory_Economy_System.md) 第 4.3 节。

## 12. 城镇酒馆入口（阶段 13 新增）

- 地点面板新增按钮 `SettlementTavernButton`：仅 `SettlementType.TOWN` 可见，村庄与城堡隐藏并禁用。
- 点击后打开 `TavernPanel` 并隐藏地点面板，继续持有一个 `PAUSE_REASON_UI_PANEL`；关闭酒馆时恢复地点面板或成对释放暂停原因。
- 酒馆菜单：
  - “出售俘虏”：进入左买家（当前城镇）/右玩家俘虏的双栏界面；
  - “招募雇佣兵”：列出当前酒馆驻留雇佣兵（名称/类型/tier/战斗经验/价格/日薪）并执行原子招募，详见 [Mercenary_System.md](Mercenary_System.md)；
  - “离开酒馆”：返回地点面板。
- 出售界面逐名显示俘虏名称、等级与身份；右侧行操作“卖出”，左侧行操作“撤回”；“重置出售”恢复打开时快照；只有“确认出售”调用 `PrisonerTradeManager.sell_prisoners()` 一次性原子结算。
- 售价只取 `PrisonerPriceConfig`（按兵种 tier：一级 5、二级 20、三级 60；NPC 领主统一 100），UI 不写死价格，也不按装备、伤势或经验等级改价。
- 成功出售后金币进入 `PlayerProfile`，Unit 退出玩家控制并写入 `sold_to_settlement_id`；失败不改任何金币或归属。
- 详细规则见 [Wounded_Prisoner_System.md](Wounded_Prisoner_System.md)。
