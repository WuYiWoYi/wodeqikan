# 俘虏恢复与玩家被俘系统

**核心逻辑：** `Scripts/Core/World/captivity_manager.gd`
**配置：** `Scripts/Config/captivity_config.gd`、`Data/Combat/captivity_config.tres`
**数据：** `UnitData.prisoner_owner_party_id`、`PartyData.prisoner_unit_ids`、`SaveData.captivity`
**UI：** `Scripts/UI/WorldMap/world_map.gd`（左侧被俘面板、顶栏 HP、镜头跟随）
**状态：** 战败被俘、俘虏按小时恢复、满血逃脱、2 游戏小时保护期、存档往返已实现；无赎金谈判/押送路线/多个玩家角色

---

## 1. 职责与数据所有权

| 数据 | 唯一写入者 | 读取方 |
|---|---|---|
| 玩家被俘标记、押送部队 ID | `CaptivityManager` | 大地图 UI、AI/遭遇保护查询、存档 |
| 俘虏恢复计时、逃脱判定计时、保护截止时间 | `CaptivityManager` | 存档、测试、UI 只读 |
| 俘虏归属 `UnitData.prisoner_owner_party_id` | `PartyManager.add_prisoner/remove_prisoner` | 战斗、部队面板、CaptivityManager |
| 俘虏列表 `PartyData.prisoner_unit_ids` | `PartyManager` | 部队面板、恢复结算 |
| 玩家角色 `status` / `current_hp` / 装备 | `BattleManager`（战斗写回）、`CaptivityManager`（恢复/逃脱） | 部队面板、顶栏 HP、存档 |
| 治疗速度 / 逃脱概率与间隔 / 保护时长 | `CaptivityConfig`（Resource） | `CaptivityManager` |

规则：

- 玩家角色是否被俘**只以实际俘虏归属为准**；`CaptivityManager.player_captive` 是派生状态，读档后由 `sync_player_capture()` 重新校正。
- 玩家部队 ID 始终保留，作为身份锚点。被俘期间玩家部队被禁用而不是删除，逃脱时复用同一 `party_id`，不创建第二支玩家部队。
- 世界时间只由 `TimeManager` 推进；本系统不自行累计时间、不使用 `Engine.time_scale`。

## 2. 战斗战败与被俘

1. 玩家所在侧明确战败（`ATTACKER_VICTORY` / `DEFENDER_VICTORY` 中玩家侧失败）时，`BattleManager._decide_wounded_outcomes()` 把玩家角色的战斗状态标记为伤兵，而不是永久死亡。
2. 战斗结算沿用既有俘虏池：玩家角色作为真实 `UnitData` 进入胜利方俘虏列表，`prisoner_owner_party_id` 指向押送部队；HP / 等级 / 经验 / 装备 / 外观全部保留。
3. `EventBus.battle_finished` 后，`WorldContext._on_battle_finished()`：
   - `_cleanup_defeated_parties()` 移除已无任何成员的非玩家部队；
   - `captivity_manager.sync_player_capture()` 根据实际归属进入被俘状态。
4. 被俘时禁用玩家原部队：`battle_state = DISABLED`，清空移动/目标/跟随/攻击意图/战斗响应；玩家不能再下达移动或战斗指令。
5. 撤退、中止、平局不产生被俘；玩家角色已经永久死亡时遵循既有死亡规则。

## 3. 俘虏恢复

- 所有部队的 `prisoner_unit_ids` 按游戏小时恢复 HP，包含被俘玩家；与伤兵治疗名额完全分离。
- 结算入口：`CaptivityManager.on_world_tick()`，由 `WorldSimulation` 的 WorldTime tick 调用。
- 每个整游戏小时，**每名俘虏各自**恢复 `prisoner_healing_per_hour` 点 HP，不与其他俘虏共享点数，也不按列表顺序排队。
- 因此被俘玩家的恢复速度与所在部队俘虏人数无关：押送方关押 1 人或 20 人都一样，玩家角色不会被列表靠前的普通俘虏长期挤占。
- `prisoner_healing_last_hour` 记录上次结算小时；读档缺失时以读档时刻为起点，不补发离线治疗。
- 治疗只改 `UnitData.current_hp`，不改变俘虏归属、等级、装备或部队成员关系。

## 4. 逃脱

满足以下条件时由 `CaptivityManager._check_player_escape()` 判定：

- 玩家角色仍是当前押送部队的俘虏；
- `current_hp >= max_hp`；
- 距离上次判定至少 `escape_check_interval_hours` 个游戏小时。

判定使用 `escape_chance`（0–1）。未满血时判定计时跟随当前小时，保证满血后至少经过一个完整间隔才尝试。押送部队消失或俘虏归属被清除时直接视为获释，不进行概率判定。

逃脱成功后：

1. 从押送部队俘虏列表移除玩家角色，清空 `prisoner_owner_party_id`；
2. 满血、`status = ACTIVE`，重新加入原玩家部队并设为领袖；
3. 玩家部队恢复 `AVAILABLE` / `IDLE`，清空旧目标与攻击意图；
4. 在押送部队附近按半径 `42 / 70 / 100 / 140 / 190` 寻找合法落点，避免与其他有成员部队重叠（间距 30），并 clamp 到地图边界内；
5. 进入 `escape_protection_hours` 保护期；不自动恢复被俘前已损失的其他士兵。

## 5. 逃脱保护

- 保护截止时间保存为绝对世界秒 `escape_protection_until`。
- `AIManager` 在选择追击/强盗目标时跳过受保护的玩家部队。
- `EncounterManager.update_encounters()` 在判定 **AI 主动**拦截玩家时跳过受保护目标；玩家主动追击/跟随仍可正常触发遭遇。
- 保护期只约束 AI 主动行为，不阻止玩家移动、招募、交易或进入地点。

## 6. UI

- **左侧被俘面板**：`CaptiveStatusPanel`，显示被俘状态、押送部队名称与玩家 HP；普通状态下隐藏。
- **顶栏 HP**：`PlayerHpLabel` 读取 `WorldContext.get_player_unit()` 的真实 `current_hp / max_hp`，随俘虏恢复与逃脱实时刷新；样式与金币/速度/部队人数一致。
- **镜头**：被俘期间强制跟随押送部队；逃脱后自动回到玩家部队。
- **部队面板**：被俘期间仍可查看，但不能重新获得控制权；大地图隐藏玩家部队战斗图标。
- **时间倍率**：被俘面板不是模态窗口，暂停/1x/2x 切换保持可用。

## 7. 配置

| 字段 | 默认值 | 说明 |
|---|---:|---|
| `prisoner_healing_per_hour` | 5 | 每游戏小时**每名俘虏**恢复的 HP（不共享、不累积溢出） |
| `escape_check_interval_hours` | 1.0 | 满血后逃脱判定间隔（向上取整为小时） |
| `escape_chance` | 0.35 | 每次判定的逃脱概率 |
| `escape_protection_hours` | 2.0 | 逃脱后的 AI 保护时长 |

配置为静态 `.tres`，不进入存档；`CaptivityManager` 读档时使用同一配置，不把数值写入存档。

## 8. 存档

`SaveData.captivity`：

```json
{
  "is_player_captive": true,
  "captor_party_id": "PARTY_000004",
  "prisoner_healing_last_hour": 80,
  "escape_check_last_hour": 81,
  "escape_protection_until": 0.0
}
```

- 玩家角色本身通过既有 `units` 数据保存（HP、装备、俘虏归属）。
- 读档后 `validate_after_load()` 以实际归属校正被俘状态；押送部队不存在时视为获释。
- 旧存档（v9 及更早）缺失 `captivity` 时按未被俘恢复。

## 9. 关键接口

| 接口 | 说明 |
|---|---|
| `setup(unit_manager, party_manager, world_map_manager, config)` | 由 `WorldContext._wire_managers()` 装配 |
| `set_player_party_id(party_id)` | 设置身份锚点部队 |
| `on_world_tick(fixed_delta)` | 仅由 `WorldSimulation` 调用；恢复 + 逃脱判定 |
| `sync_player_capture()` | 战斗结束/读档后以实际俘虏归属同步状态 |
| `is_player_captive()` / `get_captor_party_id()` | 只读查询 |
| `is_player_protected()` / `get_escape_protection_until()` | AI/遭遇保护查询 |
| `heal_party_prisoners(party, points)` | 对单支部队俘虏恢复：每名俘虏各自 `+points`（封顶 `max_hp`），返回实际恢复总量 |
| `escape_player()` / `liberate_player(reason)` | 主动逃脱 / 非主动获释 |
| `to_dict()` / `load_from_dict()` / `validate_after_load()` | 存档往返 |
| `AIManager.set_captivity_manager()` / `EncounterManager.set_captivity_manager()` | 保护期查询接线 |

## 10. 已知限制

- 没有押送路线、赎金谈判、被俘期间的事件选择或越狱道具。
- 只有玩家角色可以触发逃脱判定；普通俘虏只能通过既有释放/出售/赎回流程离开。
- 逃脱后原部队的其他被俘成员不会自动归队，需要后续系统提供赎回/招募。
- 保护期只读取单一截止时间，不支持按 AI 阵营差异化。
