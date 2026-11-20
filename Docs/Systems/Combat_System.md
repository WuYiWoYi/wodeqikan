# 战斗系统

**核心数据：** `Scripts/Systems/Combat/battle_session.gd`、`battle_unit_state.gd`
**核心逻辑：** `Scripts/Systems/Combat/battle_manager.gd`
**状态：** 会话骨架完成，流程未实现

---

## 1. 设计目标

- 每次战斗创建独立 `BattleSession`。
- 战斗临时数据与长期实体数据分离。
- 战斗期间世界继续运行（WorldTime = 0.5）。
- 战斗结算由 `BattleManager` 统一执行。

## 2. BattleSession

| 字段 | 说明 |
|---|---|
| `battle_id` | 战斗 ID |
| `world_position` | 战斗发生位置 |
| `attacker_party_ids` | 进攻方部队 |
| `defender_party_ids` | 防守方部队 |
| `reinforcement_party_ids` | 援军部队 |
| `unit_states` | `unit_id → BattleUnitState` |
| `status` | PREPARING / ACTIVE / ENDED |
| `result` | UNDECIDED / 攻击方胜 / 防守方胜 / 平局 / 中止 |

### BattleUnitState

- `unit_id`、`party_id`
- `battle_hp`
- `alive`
- `battle_position`

战斗期间，单位的临时 HP 与位置以 `BattleUnitState` 为唯一权威。

## 3. 战斗初始化

```text
大地图遭遇
  → 阵营关系与遭遇条件判定
  → BattleManager.start_battle(attacker_ids, defender_ids, position)
      ├── 创建 BattleSession
      ├── 校验参战部队可用
      ├── 部队 battle_state = IN_BATTLE
      ├── 为每个参战单位创建 BattleUnitState（battle_hp = current_hp）
      ├── TimeManager.set_battle_mode(true)
      ├── EventBus.battle_started
      └── SceneManager.change_scene(BattleScene)
  → BattleScene 读取 session 生成单位
```

## 4. 战斗期间的世界

- WorldTime = 0.5，`WorldSimulation` 继续推进。
- 其他 NPC 部队继续移动。
- AI 继续决策。
- 参战部队锁定，不能在大地图移动。
- 参战单位的世界数据（`UnitData.current_hp`）不被世界侧修改。

## 5. 数据权威

| 数据 | 战斗期间 | 战斗结束后 |
|---|---|---|
| HP | `BattleUnitState.battle_hp` | `BattleManager` 写回 `UnitData.current_hp` |
| 位置（战斗内） | `BattleUnitState.battle_position` | 丢弃 |
| 大地图位置 | `PartyData.world_position` | 不变，或按战后规则调整 |
| 部队状态 | `PartyData.battle_state` | 解锁为 `AVAILABLE` |
| 经验/死亡 | 战斗中记录 | `BattleManager` 统一结算 |

禁止 `WorldSimulation` 与 `BattleScene` 同时修改同一单位的战斗 HP。

## 6. 援军

```text
其他部队进入战斗区域
  → 检查距离
  → 判断阵营
  → 判断支援条件
  → BattleManager.add_reinforcement(party_id, battle_id)
      ├── 部队锁定
      ├── 生成 BattleUnitState
      ├── 加入 session
      └── 通知 BattleScene 生成援军单位
```

敌我双方使用同一机制。

## 7. 战斗结算顺序

1. 汇总所有 `BattleUnitState`。
2. 写回剩余 HP。
3. 记录死亡单位。
4. 更新经验。
5. 更新 `PartyData.member_unit_ids` 与 `UnitData.current_party_id`。
6. 记录战斗结果。
7. 解锁参战部队。
8. 清理 `BattleSession`。
9. 关闭战斗时间覆盖。
10. 切换回大地图。

结算必须由 `BattleManager` 执行，场景控制器不得自行改世界数据。

## 8. 战斗期间存档

初期禁止战斗期间存档，避免序列化大量实时状态。

- 存档入口需要检查 `BattleManager.current_battle == null`。
- 如果后续支持，必须为 `BattleSession` 增加完整 `to_dict/from_dict`，并纳入版本迁移。

## 9. 战斗场景结构

```text
BattleScene (Node2D)
├── World
│   ├── Environment
│   ├── Characters
│   └── Interactables
├── Camera2D
├── SceneController
└── SceneUI
```

- 单位按 Y 排序。
- 战斗场景从 `BattleSession` 读取参战单位。
- 战斗结束后由 `BattleManager` 切回大地图。

## 10. 离屏战斗（待确认）

源规划未明确“玩家未参与的 AI 对 AI 战斗”如何处理。

当前建议（尚未最终确认）：

- 玩家参与的遭遇 → 加载 `BattleScene`。
- 玩家未参与的遭遇 → `BattleManager` 自动结算，不加载场景。
- 自动结算只产出战果、伤亡和部队状态，不模拟具体单位行为。

该策略会显著影响世界模拟性能与 AI 设计，必须在阶段 4 前确定，记录到 `Technical_Decisions.md`。

## 11. 实现状态

| 项 | 状态 |
|---|---|
| `BattleSession` / `BattleUnitState` | 已实现数据结构 |
| `BattleManager` 接口 | 骨架 |
| 战斗初始化 | TODO(阶段4) |
| 战斗场景 | 空场景 |
| 援军 | TODO(阶段6) |
| 结算 | TODO(阶段4) |
| 离屏结算 | 未定 |

## 12. 待确认

- AI 对 AI 战斗结算方式。
- 战斗胜负条件（全灭/撤退/时间）。
- 玩家战败后的处理（被俘/逃脱/损失）。
- 援军加入距离与最大参战人数。
