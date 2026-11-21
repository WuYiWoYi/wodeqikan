# 世界日志系统

**核心数据：** `Scripts/Entities/Log/world_log_entry.gd`
**核心管理：** `Scripts/Core/World/world_log_manager.gd`
**UI：** `Scripts/UI/WorldMap/world_map.gd`（左下角 `WorldLogPanel`）
**状态：** 数据生成、事件类型、时间、数量上限、左下角面板、滚动与自动刷新已实现；完整历史持久化未接入存档

---

## 1. 职责边界

```text
EventBus / 管理器事实
        ↓
WorldLogManager（格式化、限长、序列化预留）
        ↓ entry_added
WorldMap WorldLogPanel（只读展示、滚动）
```

- 业务脚本不直接操作日志面板。
- `WorldLogManager` 只监听已经发生的事实，不创建战斗、不修改部队或地点。
- UI 只读取 `WorldLogEntry`，不修改日志数据。
- 日志历史保存在 `WorldContext.world_log_manager` 中，跨大地图/村庄场景存在。

## 2. 数据模型

### WorldLogEntry

| 字段 | 说明 |
|---|---|
| `event_type` | `OTHER` / `BATTLE_STARTED` / `BATTLE_FINISHED` / `PARTY_ELIMINATED` / `PLAYER_ENCOUNTER` / `SETTLEMENT_ENTERED` / `SETTLEMENT_EXITED` |
| `world_time_seconds` | 事件发生时的世界累计秒数 |
| `time_text` | 生成时保存的世界时间文本（日期 + 时间段） |
| `text` | 显示文本 |
| `metadata` | 可选扩展数据（battle_id、party_id、settlement_id 等） |

- `to_dict()` / `from_dict()` 已实现，供后续持久化使用。
- 本阶段日志不进入 `SaveData`；读档后历史日志为空。

### WorldLogManager

- `MAX_ENTRIES = 100`；超出时移除最早条目，避免长期运行无限增长。
- `add_event(type, text, metadata)` 是其他世界事件的统一扩展入口。
- `entry_added` 信号用于 UI 自动刷新。
- `to_dict()` / `load_from_dict()` 为存档接入预留；当前不修改存档 Schema。

## 3. 事件来源与文本

| 来源 | 事件类型 | 示例 |
|---|---|---|
| `EventBus.battle_started` | `BATTLE_STARTED` | 「A 部队 与 B 部队 发生了战斗。」 |
| `EventBus.battle_finished` | `BATTLE_FINISHED` | 「A 部队 击败了 B 部队。」「……平局结束。」「……撤退了。」 |
| `battle_finished` 结果中阵亡全部成员的部队 | `PARTY_ELIMINATED` | 「B 部队 已被消灭。」 |
| `EventBus.player_encounter_requested` | `PLAYER_ENCOUNTER` | 「玩家部队 与 A 部队 发生了遭遇。」 |
| `EventBus.settlement_entered` | `SETTLEMENT_ENTERED` | 「玩家进入了巴里。」 |
| `EventBus.settlement_exited` | `SETTLEMENT_EXITED` | 「玩家离开了巴里。」 |
| `WorldLogManager.add_event()` | `OTHER` 或扩展类型 | 预留任务、经济、外交等事件 |

- 战斗开始按 `BattleSession.side_index` 组合双方名称；多方战斗会列出全部战斗侧。
- 战斗结束使用 `BattleResultData` 的获胜/失败侧与撤退侧生成文本。
- 同一场战斗的每个被消灭部队只记录一次。

## 4. 大地图日志面板

- `WorldLogPanel` 固定在屏幕左下角（`CanvasLayer` UI），不随地图摄像机移动。
- 标题「世界日志」+ `ScrollContainer` + `VBoxContainer`。
- 新日志从 `entry_added` 信号进入，自动重建条目并滚动到最新事件。
- 历史条目超过面板高度时可滚动查看。
- 面板与滚动区域使用 `MOUSE_FILTER_PASS`，避免永久吞掉地图点击；日志标签本身不拦截输入。
- 面板不显示时数据仍保留在 `WorldLogManager` 中；重新进入大地图会按当前历史重建。

## 5. 持久化预留

- `WorldLogEntry` 与 `WorldLogManager` 均提供 `to_dict/from_dict`。
- 后续接入存档时，建议保存最近 `MAX_ENTRIES` 条；不保存 UI 滚动位置或节点。
- 当前不在 `WorldContext.to_save_data()` 中写入日志，不改变 Schema。

## 6. 测试

- `Tests/UnitTests/world_log_manager_test.tscn`：事件类型、战斗/胜负/消灭/遭遇/地点文本、扩展事件、数量上限、序列化。
- `Tests/SystemTests/world_log_ui_test.tscn`：左下角固定面板、自动刷新、滚动区域、不阻挡地图移动。

## 7. 未实现

- 日志持久化到存档。
- 按事件类型过滤、折叠与未读计数。
- 点击日志跳转到部队/地点。
- 战报详情与更长历史。
