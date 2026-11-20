# 战斗系统

**核心数据：** `Scripts/Systems/Combat/battle_session.gd`、`battle_unit_state.gd`
**核心逻辑：** `Scripts/Systems/Combat/battle_manager.gd`
**场景与表现：** `Scripts/UI/Battle/battle_scene.gd`、`Scripts/Systems/Combat/unit_actor.gd`、`unit_controller.gd`
**状态：** 最小实时战斗闭环已实现（大地图遭遇 → 对话 → 战斗 → 结算 → 返回）；援军、离屏结算与复杂战术未实现

> 本文是项目实际的战斗系统文档。任务书中提到的 `Battle_System.md` 与本文对应，未另建重复文档。

---

## 1. 设计目标

- 每次战斗创建独立 `BattleSession`。
- 战斗临时数据与长期实体数据分离。
- 战斗期间 HP 以 `BattleUnitState` 为唯一权威，结束时统一写回 `UnitData`。
- 战斗场景只读取 `UnitData` 静态属性，不修改部队成员关系。
- 结算由 `BattleManager` 统一执行，场景控制器不得直接改世界数据。

## 2. 数据模型

### BattleSession

| 字段 | 说明 |
|---|---|
| `battle_id` | 战斗 ID，`BATTLE_000001` |
| `world_position` | 战斗发生位置 |
| `attacker_party_ids` / `defender_party_ids` | 进攻方 / 防守方部队 ID |
| `reinforcement_party_ids` | 援军部队 ID（阶段 6） |
| `attacker_unit_ids` / `defender_unit_ids` | 双方参战单位 ID，顺序与生成顺序一致 |
| `attacker_faction_id` / `defender_faction_id` | 双方阵营 |
| `unit_states` | `unit_id → BattleUnitState` |
| `status` | PREPARING / ACTIVE / ENDED |
| `result` | UNDECIDED / 攻击方胜 / 防守方胜 / 平局 / 中止 |

辅助方法：`get_unit_state()`、`is_party_involved()`、`is_attacker_party()`、`get_party_unit_ids()`、`get_all_unit_ids()`。

### BattleUnitState

| 字段 | 说明 |
|---|---|
| `unit_id` | 对应 `UnitData` |
| `party_id` | 所属部队 |
| `battle_hp` | 战斗期间 HP，唯一权威 |
| `alive` | 是否存活 |
| `battle_position` | 战斗场景内位置 |

## 3. 进入战斗

```text
大地图接近 AI 部队
  → 部队对话面板（push_pause ui_panel）
  → 玩家选择“发起战斗”
      → BattleManager.start_battle(attacker_ids, defender_ids, position)
          ├── 校验双方部队存在、ID 不重复、阵营不同
          ├── 校验部队 battle_state == AVAILABLE
          ├── 为每个存活成员创建 BattleUnitState（battle_hp = current_hp）
          ├── 双方都没有存活士兵则失败
          ├── 参战部队 battle_state = IN_BATTLE
          ├── 停止参战部队大地图移动
          ├── push_pause(battle)
          └── EventBus.battle_started
      → 场景控制器 SceneManager.change_scene(BattleScene)
```

`start_battle()` 不切换场景、不修改单位 HP 与成员关系；失败时返回 `null`，不改变任何部队或时间状态。

### 3.1 大地图交互

- 玩家进入 AI 部队 40 像素范围后自动打开 `PartyDialoguePanel`（同一时间只有一个实例）。
- 面板显示部队名称、阵营、`member_unit_ids.size()` 兵力。
- 离开：关闭面板并移除 `ui_panel` 暂停，恢复此前基础倍率。
- 发起战斗：创建会话后先压入 `battle` 暂停，再移除 `ui_panel`，随后切换场景。
- 空部队（例如被击溃）不再触发交互；玩家或敌方无兵时战斗按钮禁用。
- 交互检测使用“上一帧位置 → 当前位置”线段，避免高倍速穿过目标。

## 4. 战斗场景

```text
BattleScene (Node2D)
├── World
│   └── Characters (Node2D, y_sort_enabled)
├── Camera2D
└── UI (CanvasLayer)
    ├── TopBar（战斗信息、双方存活数）
    ├── BattleHintLabel
    ├── BattleResultDim
    └── BattleResultPanel（结果 + 返回大地图）
```

### 4.1 士兵生成

- 从 `BattleSession.attacker_unit_ids` / `defender_unit_ids` 读取单位。
- 每个幸存单位创建一个 `UnitActor`，节点名 `UnitActor_<unit_id>`，并关联对应 `BattleUnitState`。
- 进攻方在左侧、防守方在右侧，2 列纵深，横向 54 / 纵向 64 像素间距，避免重叠。
- 视觉用程序绘制占位图形：玩家蓝色、敌方红色，包含血条与单位名称。
- 战斗场景不直接修改 `PartyData.member_unit_ids` 或 `UnitData.current_hp`。

### 4.2 UnitController

每个 `UnitActor` 配套一个 `UnitController`（RefCounted，由场景逐帧驱动）：

- 属性全部来自 `UnitData`：`move_speed`、`attack_range`、`attack`、`attack_interval`。
- 自动索敌：在 1000 像素内选择最近的存活敌人，目标死亡后重新选择。
- 目标在攻击范围（`attack_range + 8` 容差）内时按 `attack_interval` 攻击。
- 玩家左键点击地面：所有存活己方士兵移动到目标点附近；手动移动期间不主动攻击，到达后恢复自动索敌。
- 敌方没有手动命令，始终自动接近并攻击。
- 伤害只写 `BattleUnitState.battle_hp`；HP 归零后 `alive = false`，停止移动、攻击和受伤。
- 死亡表现节点由场景移除，`BattleUnitState` 保留到结算。

## 5. 数据权威

| 数据 | 战斗期间 | 战斗结束后 |
|---|---|---|
| HP | `BattleUnitState.battle_hp` | `BattleManager` 写回 `UnitData.current_hp` |
| 位置（战斗内） | `BattleUnitState.battle_position` | 丢弃 |
| 大地图位置 | `PartyData.world_position` | 不变 |
| 部队状态 | `PartyData.battle_state` | 解锁为 `AVAILABLE` |
| 成员关系 | 不修改 | 阵亡单位移除，存活单位保留 |
| 经验/死亡 | 只记录 `alive` | `BattleManager` 统一结算 |

禁止 `WorldSimulation` 与 `BattleScene` 同时修改同一单位的战斗 HP。

## 6. 战斗结束与结算

### 6.1 胜负条件

- 防守方全部死亡 → `ATTACKER_VICTORY`（玩家胜利）。
- 进攻方全部死亡 → `DEFENDER_VICTORY`（玩家失败）。
- 双方同时为 0 → `DRAW`。
- 场景显示结果面板；玩家点击“返回大地图”后才执行结算。

### 6.2 结算顺序

1. 校验 `current_battle` 与 `battle_id`，防止重复结算。
2. 对每个 `BattleUnitState`：
   - 存活：`UnitData.current_hp = battle_hp`（clamp 到 `[0, max_hp]`）。
   - 阵亡：`current_hp = 0`，经 `PartyManager.remove_member()` 清空归属，再 `UnitManager.remove_unit()` 删除数据，广播 `unit_died`。
3. 解锁双方部队，清空当前命令。
4. 清理 `BattleSession`（`current_battle = null`）。
5. 移除 `battle` 暂停原因，恢复此前世界时间状态。
6. 广播 `battle_finished`。
7. 场景控制器切换回大地图。

阵亡单位不会以“0 HP 但仍属于部队”的形式残留；存活单位保留原 `unit_id` 与成员关系。

### 6.3 防守方全灭后的部队

- 部队本身保留在大地图，但成员为空。
- 空部队不再触发交互，避免战斗结束后立即重复弹出对话。
- 战利品、俘虏与部队解散规则留待后续阶段。

## 7. 战斗期间的世界与存档

- 屏幕内战斗压入 `battle` 暂停原因，WorldTime = 0；战斗场景用物理帧独立推进。
- `WorldContext` 在战斗期间保持存在，参战部队锁定。
- `GameManager.save_game()` 在 `current_battle != null` 时返回 `ERR_BUSY`，禁止战斗中存档。
- `BattleSession` 不进入存档；不改变存档 Schema。

## 8. 援军（TODO 阶段 6）

```text
其他部队进入战斗区域
  → 检查距离 / 阵营 / 支援条件
  → BattleManager.add_reinforcement(party_id, battle_id)
      ├── 部队锁定
      ├── 生成 BattleUnitState
      ├── 加入 session
      └── 通知 BattleScene 生成援军单位
```

当前 `add_reinforcement()` 返回 `false`。

## 9. 离屏战斗（待确认）

玩家未参与的 AI 对 AI 战斗尚未实现。建议后续自动结算，不加载 `BattleScene`，使用 `TimeManager.set_battle_mode(true)` 的 0.5 倍速覆盖继续推进世界；该方案仍待确认。

## 10. 实现状态

| 项 | 状态 |
|---|---|
| `BattleSession` / `BattleUnitState` | 已实现 |
| `BattleManager.start_battle` | 已实现（校验、锁定、会话） |
| `BattleManager.finish_battle` | 已实现（HP 写回、阵亡移除、解锁、防重复） |
| 大地图部队对话 UI | 已实现 |
| 战斗场景与士兵生成 | 已实现（占位图形） |
| 玩家点击移动命令 | 已实现 |
| 自动索敌 / 移动 / 攻击 / 死亡 | 已实现 |
| 单场战斗禁止存档 | 已实现 |
| 援军 | TODO(阶段6) |
| 离屏 AI 对 AI 结算 | 未实现 |
| 阵型、骑兵冲锋、远程弹道、士气 | 未实现 |

## 11. 待确认

- 屏幕内战斗 WorldTime 采用 0（当前）还是 0.5（D008 初版方案）。
- 玩家战败后的处理（逃脱 / 被俘 / 损失）。
- 战斗胜负条件是否加入撤退与时间限制。
- 援军加入距离与最大参战人数。
- 阵亡单位是否永久删除，或转为伤兵/俘虏数据。
