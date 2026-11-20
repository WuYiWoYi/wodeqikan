# AI 系统

**核心调度：** `Scripts/Systems/AI/ai_manager.gd`
**状态：** 调度骨架完成，决策未实现

---

## 1. 分层

| 层级 | 决策者 | 频率 | 输出 |
|---|---|---|---|
| 单位实时行为 | `UnitAI` | 小场景物理帧 | 移动、攻击、防御、撤退 |
| 部队战术 | `PartyAI` | 1 世界秒 | 移动、攻击、防守、撤退命令 |
| 领主战略 | `LordAI` | 30 世界秒 | 招募、参战、撤退、驻防 |

原则：

- 高层下达命令，低层负责执行。
- AI 不直接操作场景节点与 UI。
- AI 只通过管理器接口修改数据。
- 不同层级使用不同更新频率，禁止每帧全量扫描。

## 2. 单位 AI

初期 FSM：

```text
Idle
├── Move
├── Attack
├── Defend
└── Retreat
```

后续扩展：Shield、Pursue、Protect、FormationMove、Charge。

### 目标选择

- 只在攻击范围/感知范围内选择敌人。
- 多目标时随机或按威胁值选择（阶段 3 先随机）。
- 阵营敌对关系来自 `FactionData.relations`。
- 玩家单位与 AI 单位共用 `UnitController`，AI 只替换决策输入。

## 3. 部队 AI

```text
PartyAI
├── FormationManager
├── MovementOrder
├── AttackOrder
├── DefendOrder
└── RetreatOrder
```

职责：

- 根据敌我兵力、距离、地形（后续）选择战术。
- 调用 `WorldMapManager` 设置移动目标。
- 进入战斗后向单位 AI 下达编队与攻击命令。
- 不直接修改单位位置或攻击状态。

## 4. 领主 AI

- 通过 `LordData.current_goal` / `current_state` 表达长期目标。
- 决策读部队与地点数据，产出命令。
- 决策节奏远低于部队 AI，避免大量领主同时计算。

详见 [Lord_System.md](Lord_System.md)。

## 5. 调度与性能

`AIManager` 使用时间累加器分频：

```text
每世界 tick:
    party_timer += 0.1
    lord_timer  += 0.1

    party_timer >= 1.0  → 部队战术决策，取模
    lord_timer  >= 30.0 → 领主战略决策，取模
```

- 卡顿后不补跑错过的时间桶，避免集中决策。
- 初期可接受 O(n²) 距离检查；部队数量上升后引入空间网格。
- 视野、遭遇与 AI 共享空间查询结果。
- AI 决策不得在 `_process` 中执行全量扫描。

## 6. 数据驱动参数

AI 参数应可配置：

- 决策间隔。
- 视野与感知范围。
- 攻击/撤退兵力比。
- 招募阈值。
- 性格权重。

初期可以放在常量或配置资源中，但不得散落在多个脚本。

## 7. 随机性

- 使用统一随机源，避免不可复现。
- 后续将随机种子写入存档，保证读档后行为可复现。
- 测试中固定种子。

## 8. 实现状态

| 项 | 状态 |
|---|---|
| `AIManager` 分频调度 | 已实现 |
| `UnitAI` | TODO(阶段3/4) |
| `PartyAI` | TODO(阶段4/5) |
| `LordAI` | TODO(阶段5) |
| 空间查询 | TODO(阶段2) |
| 统一随机源 | TODO(阶段3) |

## 9. 待确认

- 部队 AI 是否需要“性格”影响。
- AI 对 AI 遭遇是否进入战斗场景（见 `Known_Issues.md`）。
- 大规模部队数量目标（决定空间索引与 LOD 策略）。
