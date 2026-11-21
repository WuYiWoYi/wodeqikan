# 村庄、城镇与城堡系统

**核心数据：** `Scripts/Entities/Settlement/settlement_data.gd`
**核心逻辑：** `Scripts/Core/World/settlement_manager.gd`
**状态：** 数据仓储、地图图标、基础交互面板与村庄小场景入口已实现

---

## 1. SettlementData

| 字段 | 说明 |
|---|---|
| `settlement_id` | `SETTLEMENT_000001` |
| `display_name` | 显示名 |
| `settlement_type` | VILLAGE / TOWN / CASTLE |
| `world_position` | 大地图坐标（像素） |
| `faction_id` | 所属阵营 |
| `owner_lord_id` | 归属领主 |
| `scene_path` | 该地点小场景路径；旧存档/城镇/城堡为空 |
| `population` | 人口 |
| `prosperity` | 繁荣度 |
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

| ID | 名称 | 类型 | 坐标 |
|---|---|---|---|
| `SETTLEMENT_000001` | 巴里 | 村庄 | (500, 500) |
| `SETTLEMENT_000002` | 墨西西 | 村庄 | (1200, 900) |
| `SETTLEMENT_000003` | 北境村 | 村庄 | (2200, 500) |
| `SETTLEMENT_000004` | 灰石城堡 | 城堡 | (1800, 1300) |

## 2. 地点交互

```text
玩家部队移动到地点 40 像素范围内
  → WorldMapManager.stop_party(玩家)
  → TimeManager.set_base_world_speed(0)
  → TimeManager.push_pause(&"ui_panel")
  → 打开左侧交互面板
  → 显示名称、类型
  → 村庄：显示“进入村庄” + “离开地点”
  → 城镇/城堡：只显示“离开地点”
```

触发检测位于大地图场景控制器：

- 只有玩家用鼠标左键点击地点（判定半径 45 像素）才打开面板；移动到附近或路过不会自动触发。
- 面板打开期间时间为 0。
- 关闭面板时移除 `ui_panel`，但基础倍率保持 0。
- 玩家必须主动选择 1x / 2x 才会继续世界推进。
- 点击其他地点会切换当前地点面板；玩家离开后不会自动重开。

Milestone 1 只做基础面板；阶段 6 起村庄面板增加进入小场景入口，城镇/城堡仍只做基础面板。

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

初期不做经济与人口模拟。

后续由 `WorldSimulation` 按较低频率推进：

- 人口增长/减少。
- 繁荣度变化。
- 驻军补充。
- 被围城状态。
- 归属变更。

频率必须低于世界 tick（例如每游戏日一次），不得每 0.1 秒计算。

## 7. 实现状态

| 项 | 状态 |
|---|---|
| `SettlementData` 与序列化 | 已实现 |
| `SettlementManager` | 已实现并接入 `WorldContext` |
| 大地图标记 | 已实现（程序绘制村庄/城堡） |
| 交互面板 | 已实现（名称/类型/离开；村庄额外提供进入） |
| 触发停止与暂停 | 已实现 |
| 村庄小场景进入/返回 | 已实现（scene_path + small_scene 暂停 + 返回锁） |
| 城镇/城堡小场景 | 未实现 |
| 驻军与归属 | TODO(阶段5/7) |
| 地点模拟 | TODO(阶段7) |

## 8. 待确认

- 村庄/城镇/城堡是否共用同一交互面板（当前共用）。
- 地点交互检测是否迁移到世界模拟层。
- 进入小场景后返回大地图时的精确时间恢复规则。

## 9. 家族归属与固定屏幕名称（阶段 6 新增）

- `SettlementData.family_id`：地点所属家族，持久化；只决定地图名称旁的家族旗帜，不改变 `faction_id` 或外交。
- 新游戏地点：
  - 巴里（村庄，位置 `(500,500)`，家族 `FAMILY_BARI`）；
  - 墨西西（村庄，位置 `(1200,900)`，家族 `FAMILY_MOXIXI`）；
  - 北境村、灰石城堡保持不变。
- 地点名称不再由 `SettlementIcon` 在世界空间绘制；改为固定屏幕 UI 层 `SettlementNameTag`：
  - 每帧用 `get_viewport().get_canvas_transform() * settlement.world_position` 更新位置；
  - 字体与标签尺寸不随相机缩放；
  - 名称左侧绘制圆形家族旗帜，旗帜等比缩放；
  - 整个标签 `MOUSE_FILTER_IGNORE`，不参与地点点击、选择或悬浮判定。
- 地点点击判定仍使用 `SettlementData.world_position` 与固定世界像素半径，不依赖名称标签。
