# 村庄、城镇与城堡系统

**核心数据：** `Scripts/Entities/Settlement/settlement_data.gd`
**核心逻辑：** `Scripts/Core/World/settlement_manager.gd`
**状态：** 数据仓储、地图图标与基础交互面板已实现

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
| `SETTLEMENT_000001` | 橡木村 | 村庄 | (500, 500) |
| `SETTLEMENT_000002` | 河畔村 | 村庄 | (1200, 900) |
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
  → 初期只有“离开”
```

触发检测位于大地图场景控制器：

- 使用“上一帧位置到当前位置”的线段与地点求最近距离，避免 2x 下跨过地点。
- 面板打开期间时间为 0。
- 关闭面板时移除 `ui_panel`，但基础倍率保持 0。
- 玩家必须主动选择 1x / 2x 才会继续世界推进。
- 玩家离开地点 64 像素后解除触发锁，之后再次接近可重新打开。

Milestone 1 只做基础面板，不实现村庄内部功能。

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

## 4. 进入小场景

```text
交互面板选择“进入村庄”
  → 记录返回信息
  → 切换 VillageScene
  → WorldTime = 0（small_scene 暂停）
  → SceneTime = 1.0
```

离开小场景回到大地图时，恢复进入前的时间状态。

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
| 交互面板 | 已实现（名称/类型/离开） |
| 触发停止与暂停 | 已实现 |
| 小场景进入 | TODO(阶段5) |
| 驻军与归属 | TODO(阶段5/7) |
| 地点模拟 | TODO(阶段7) |

## 8. 待确认

- 村庄/城镇/城堡是否共用同一交互面板（当前共用）。
- 地点交互检测是否迁移到世界模拟层。
- 进入小场景后返回大地图时的精确时间恢复规则。
