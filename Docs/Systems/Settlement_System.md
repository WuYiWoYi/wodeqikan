# 村庄、城镇与城堡系统

**核心数据：** `Scripts/Entities/Settlement/settlement_data.gd`
**状态：** 数据骨架完成，交互未实现

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

## 2. 地点交互

```text
玩家到达地点
  → 触发地点交互
  → TimeManager.push_pause(&"ui_panel")
  → 打开左侧大型交互面板
  → 显示名称、类型、归属、人口、繁荣度、可用操作
  → 初期只有“离开”
```

关闭面板：

1. 移除 `ui_panel` 暂停原因。
2. 返回大地图。
3. 保持暂停状态，等待玩家下一次操作。

注意：源规划要求“离开后保持暂停，玩家再次操作后恢复移动”，因此关闭面板不能自动恢复 1 倍速。

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
| 地点仓储 | 未建立（建议阶段 2/5 增加 `SettlementManager`） |
| 大地图标记 | TODO(阶段1) |
| 交互面板 | TODO(阶段1) |
| 小场景进入 | TODO(阶段5) |
| 驻军与归属 | TODO(阶段5/7) |
| 地点模拟 | TODO(阶段7) |

## 8. 待确认

- 地点数据由 `WorldContext` 直接持有还是新增 `SettlementManager`。
- 村庄/城镇/城堡是否共用同一交互面板。
- 初期“离开后保持暂停”的具体恢复触发方式。
