# 村庄、城镇与城堡系统

**核心数据：** `Scripts/Entities/Settlement/settlement_data.gd`
**核心逻辑：** `Scripts/Core/World/settlement_manager.gd`
**状态：** 数据仓储、地图图标、基础交互面板、村庄小场景入口、封地归属、采邑储备与冒险者候选人已实现

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
| `owner_house_id` | 政治家族 `HOUSE_*`；封地归属与征召授权 |
| `owner_noble_id` | 归属贵族；可独立于家族领袖 |
| `owner_lord_id` | 兼容字段；阶段 8 起与 `owner_noble_id` 同步 |
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

Milestone 1 初始地点（名称与坐标按需求，ID 使用项目统一生成格式）：

| ID | 名称 | 类型 | 坐标 | 家族 | 初始领主 |
|---|---|---|---|---|---|
| `SETTLEMENT_000001` | 巴里 | 村庄 | (2600, 2100) | 巴里家族 | 巴里家族领主 |
| `SETTLEMENT_000002` | 墨西西 | 村庄 | (2500, 700) | 墨西西家族 | 墨西西家族领主 |
| `SETTLEMENT_000003` | 北境村 | 村庄 | (2250, 1000) | 墨西西家族 | 墨西西家族领主（阶段 8 起有主） |
| `SETTLEMENT_000004` | 灰石城堡 | 城堡 | (2900, 2350) | 巴里家族 | 巴里家族领主（阶段 8 起有主） |
| `SETTLEMENT_000005` | 青禾村 | 村庄 | (1600, 1500) | 玩家家族 | 玩家贵族 |
| `SETTLEMENT_000006` | 伯克纳尼亚 | 城镇 | (2900, 750) | 伯克纳家族 | 伯克纳国王 |
| `SETTLEMENT_000007` | 伯克纳 | 村庄 | (3200, 1000) | 伯克纳家族 | 伯克纳领主 |
| `SETTLEMENT_000008` | 奥林德斯堡 | 城堡 | (2950, 1850) | 奥林家族 | 奥林国王 |
| `SETTLEMENT_000009` | 奥林 | 村庄 | (3250, 2050) | 奥林家族 | 奥林领主 |

阶段 8 起 9 个地点全部归属家族；北境村与灰石城堡不再无主。

阶段 9 重新排列全部地点坐标（ID、名称、类型、归属均不变）：伯克纳尼亚王国聚在 y≈700–1000 的上部区域，奥林王国聚在 y≈1850–2350 的下部区域，青禾村作为玩家中立村庄位于两区域之间的西侧。地点最短间距约 360 世界像素，仍满足 240 屏幕像素名称标签在 1.5x 默认缩放下的可视间距。

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
  → 村庄：显示“进入村庄” + “离开地点”
  → 城镇/城堡：只显示“离开地点”
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
- 交易。
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
| 交互面板 | 已实现（名称/类型/离开；村庄额外提供进入） |
| 触发停止与暂停 | 已实现 |
| 村庄小场景进入/返回 | 已实现（scene_path + small_scene 暂停 + 返回锁） |
| 城镇/城堡小场景 | 未实现 |
| 封地归属 `owner_noble_id` / `owner_house_id` | 已实现（阶段 8；读档校验贵族与家族存在且一致） |
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
- 新游戏地点：
  - 巴里（村庄，位置 `(2600,2100)`，家族 `FAMILY_BARI`）；
  - 墨西西（村庄，位置 `(2500,700)`，家族 `FAMILY_MOXIXI`）；
  - 北境村、灰石城堡位置见上表（阶段 9 调整）。
- 地点名称不再由 `SettlementIcon` 在世界空间绘制；改为固定屏幕 UI 层 `SettlementNameTag`：
  - 每帧用 `get_viewport().get_canvas_transform() * settlement.world_position` 更新位置；
  - 字体与标签尺寸不随相机缩放；
  - 名称左侧绘制圆形家族旗帜，旗帜等比缩放；
  - 整个标签 `MOUSE_FILTER_IGNORE`，不参与地点点击、选择或悬浮判定。
- 地点点击判定仍使用 `SettlementData.world_position` 与固定世界像素半径，不依赖名称标签。

## 10. 封地归属、税收与征召入口（阶段 7 新增）

- 阶段 8 起 `owner_noble_id` 与 `owner_house_id` 是封地归属的权威；`family_id` 仅用于视觉家族，`faction_id` 不参与权限判断。`owner_lord_id` 作为兼容副本同步维护。
- 地点面板读取并显示：
  - 名称、类型；
  - 归属领主显示名（无主时显示“无主”）；
  - 家族显示名；
  - 人口、繁荣度；
  - `TaxCalculator` 计算后的每日税收缓存；
  - 采邑储备与补充状态。
- 只有玩家自有村庄（`owner_noble_id == 玩家贵族`）显示“征召采邑”按钮；家族领袖也可征召本家族村庄。按钮在储备为 0 或地点非村庄时禁用。
- 村庄头人对话只在玩家自有村庄且有储备时追加同一征召动作。
- 两个入口都调用 `FiefRecruitmentManager.recruit_group()`，UI 不计算编制、成本或周期。
- 税收公式、人口/繁荣度成本和储备补充参数集中在 `SettlementEconomyConfig`；UI 与 `SettlementData` 不重复实现。
- 读档时每个非空 `owner_noble_id` 必须指向存在的贵族，`owner_house_id` 必须存在且与贵族的家族一致；否则拒绝加载。旧存档仅有 `owner_lord_id` 时同步迁移。
- 详细流程见 [Fief_Recruitment_System.md](Fief_Recruitment_System.md)，候选人见 [Adventurer_Recruitment_System.md](Adventurer_Recruitment_System.md)。
