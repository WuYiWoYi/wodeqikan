# 世界日志系统

**核心数据：** `Scripts/Entities/Log/world_log_entry.gd`
**核心管理：** `Scripts/Core/World/world_log_manager.gd`
**UI：** `Scripts/UI/WorldMap/world_log_panel.gd`（大地图左下角 / 村庄右上角共用）
**状态：** 数据生成、事件类型、时间、数量上限（20 条）、共享面板、滚动、自动刷新、大地图默认折叠/点击展开、村庄/城镇玩家交易日志与存档恢复已实现；NPC 补给采购只显示部队浮字，不写日志

---

## 1. 职责边界

```text
EventBus / 管理器事实
        ↓
WorldLogManager（格式化、限长、序列化预留）
        ↓ entry_added
WorldMap / Village WorldLogPanel（只读展示、滚动）
```

- 业务脚本不直接操作日志面板。
- `WorldLogManager` 只监听已经发生的事实，不创建战斗、不修改部队或地点。
- UI 只读取 `WorldLogEntry`，不修改日志数据。
- 日志历史保存在 `WorldContext.world_log_manager` 中，跨大地图/村庄场景存在。

## 2. 数据模型

### WorldLogEntry

| 字段 | 说明 |
|---|---|
| `event_type` | `OTHER` / `BATTLE_STARTED` / `BATTLE_FINISHED` / `PARTY_ELIMINATED` / `PLAYER_ENCOUNTER` / `SETTLEMENT_ENTERED` / `SETTLEMENT_EXITED` / `FIEF_RECRUITED` / `ADVENTURER_RECRUITED` / `NOBLE_DIED` / `HOUSE_LEADER_CHANGED` / `KINGDOM_PENDING` / `PLAYER_TRADE` |
| `world_time_seconds` | 事件发生时的世界累计秒数 |
| `time_text` | 生成时保存的世界时间文本（日期 + 时间段） |
| `text` | 显示文本 |
| `metadata` | 可选扩展数据（battle_id、party_id、settlement_id 等） |

- `to_dict()` / `from_dict()` 已实现；日志通过 `SaveData.world_log` 持久化（Schema v3 起）。
- 读档后恢复最近最多 20 条历史；UI 滚动位置不保存。

### WorldLogManager

- `MAX_ENTRIES = 20`；底层、`to_dict()` 与 `load_from_dict()` 都按该上限裁剪，UI 只读取处理后的数据。
- 新日志进入后若超过 20 条，从最早记录开始删除；不采用“底层无限保存、只限制 UI”的做法。
- `add_event(type, text, metadata)` 是其他世界事件的统一扩展入口。
- `entry_added` 信号用于 UI 自动刷新。
- `to_dict()` / `load_from_dict()` 由 `WorldContext` 在保存/读档时调用。

## 3. 事件来源与文本

| 来源 | 事件类型 | 示例 |
|---|---|---|
| `EventBus.battle_started` | `BATTLE_STARTED` | 「A 部队 与 B 部队 发生了战斗。」 |
| `EventBus.battle_finished` | `BATTLE_FINISHED` | 「A 部队 击败了 B 部队。」「……平局结束。」「……撤退了。」 |
| `battle_finished` 结果中阵亡全部成员的部队 | `PARTY_ELIMINATED` | 「B 部队 已被消灭。」 |
| `EventBus.player_encounter_requested` | `PLAYER_ENCOUNTER` | 「玩家部队 与 A 部队 发生了遭遇。」 |
| `EventBus.settlement_entered` | `SETTLEMENT_ENTERED` | 「玩家进入了巴里。」 |
| `EventBus.settlement_exited` | `SETTLEMENT_EXITED` | 「玩家离开了巴里。」 |
| `EventBus.fief_recruited` | `FIEF_RECRUITED` | 「巴里骑士 在巴里征召了 1 组采邑。」「你在埃克托村征召了 1 组采邑。」 |
| `EventBus.adventurer_recruited` | `ADVENTURER_RECRUITED` | 「你在埃克托村招募了冒险者阿拉丁。」 |
| `MarketManager.execute_player_trade()` | `PLAYER_TRADE` | 「你在伯克纳尼亚交易市场购买了普通战马 ×1，支付 100 金币。」“你在巴里购买了面包 ×10，支付 20 金币。” |
| `EventBus.npc_supply_purchased` | 不写日志 | 大地图在部队图标上方显示「补给 面包+X 草料+Y」 |
| `WorldLogManager.add_event()` | `OTHER` 或扩展类型 | 预留任务、经济、外交等事件 |

- 战斗开始按 `BattleSession.side_index` 组合双方名称；多方战斗会列出全部战斗侧。
- 世界可同时存在多场战斗：`_on_battle_started(battle_id)` 必须通过 `BattleManager.get_battle(battle_id)` 关联本场会话，不得读取 `current_battle`。
- 战斗结束使用该场 `BattleResultData` 的获胜/失败侧与撤退侧生成文本；`_battle_sessions` 按 `battle_id` 独立保存与清理。
- 每场战斗的开始、结束与每个被消灭部队只记录一次；一场战斗的开始/结束不会关联到另一场。
- 玩家交易只在 `MarketManager` 成功提交后写入；`metadata` 保存 `settlement_id`、`purchased_items`、`sold_items`、`purchase_total`、`sale_total`、`gold_paid`、`gold_received` 与 `net_gold`。
- 玩家在村庄购买面包/草料与在城镇交易市场买卖使用同一条 `PLAYER_TRADE` 日志路径，文本按地点与商品生成。
- 交易来源由 `MarketManager.TradeSource` 区分：`PLAYER` 写入本日志；`NPC` 交易不写入世界日志。阶段 12 起 NPC 补给采购成功后只广播 `EventBus.npc_supply_purchased`，由大地图在对应部队图标上方显示一次浮字。

## 4. 大地图 / 村庄日志面板

`WorldLogPanel` 是独立共享组件，大地图与村庄场景各自实例化，读取同一个 `WorldLogManager`。

- 大地图固定在屏幕左下角；村庄固定在右上角（`CanvasLayer` UI），不随摄像机移动。
- 标题「世界日志」+ `ScrollContainer` + `VBoxContainer`。
- 新日志从 `entry_added` 信号进入，自动重建条目并滚动到最新事件。
- 历史条目超过面板高度时可滚动查看。
- 村庄实例与滚动区域使用 `MOUSE_FILTER_PASS`，日志标签不拦截输入；大地图折叠/展开态的输入策略见 4.1。
- 面板不显示时数据仍保留在 `WorldLogManager` 中；重新进入大地图会按当前历史重建。

### 4.1 大地图折叠态（2026-11-27）

- 大地图实例调用 `WorldLogPanel.set_collapsible(true)`，默认折叠；村庄实例保持完整面板。
- 折叠态只显示最新一条事件文本 `WorldLogCollapsedText`；隐藏 Panel 底板、标题、分隔线、滚动区域与滚动条。
- 折叠时面板 `mouse_filter = IGNORE`，不拦截地图点击；可展开区域只有事件文本自身的屏幕矩形，空白区域不参与交互。
- 点击事件文本展开完整面板；展开态 `mouse_filter = STOP`，面板自身区域内的点击与滚动不再落到地图。
- 日志展开后，点击其矩形之外任意位置（地图或其他 UI）都会折叠。折叠/展开判断在 `WorldMap._input`/`_unhandled_input` 中完成，不改变其他交互本身。
- 折叠状态不属于永久状态；事件新增只更新文本与历史，不改变当前展开/折叠状态。
- 折叠/展开不销毁任何节点；`WorldLogEntry_*`、标题与滚动区域始终存在，仅切换可见性。

## 5. 持久化

- Schema v3 起 `SaveData.world_log` 保存 `world_log_manager.to_dict()`。
- 只保存最近 `MAX_ENTRIES`（20）条；不保存 UI 滚动位置、节点或未读状态。
- 读档数据超过 20 条时立即裁剪为最新 20 条；保存时也只写入最新 20 条。
- `WorldContext.load_from_save_data()` 在恢复地点后调用 `world_log_manager.load_from_dict()`。
- 旧存档缺少 `world_log` 时历史为空，不阻止读档。

## 6. 测试

- `Tests/UnitTests/world_log_manager_test.tscn`：事件类型、战斗/胜负/消灭/遭遇/地点/征召/冒险者文本、扩展事件、20 条上限/第 21 条淘汰/100 条读档裁剪、`PLAYER_TRADE` 序列化。
- `Tests/SystemTests/world_log_ui_test.tscn`：左下角固定面板、自动刷新、滚动区域、20 条显示上限、不阻挡地图移动；默认折叠只显示最新事件、点击文本展开、点击其他区域折叠、折叠面板不拦截输入。
- `Tests/UnitTests/market_manager_test.tscn`：玩家交易写日志、失败不写日志、NPC 来源不写日志。
- `Tests/SystemTests/town_market_ui_test.tscn`：成功确认后新增一条交易日志。
- `Tests/SystemTests/fief_adventurer_system_test.tscn`：采邑/冒险者日志文本与去重。
- `Tests/SystemTests/fief_adventurer_ui_test.tscn`：村庄共享日志面板。

## 7. 未实现

- 按事件类型过滤、折叠与未读计数。
- 点击日志跳转到部队/地点。
- 战报详情与更长历史。
