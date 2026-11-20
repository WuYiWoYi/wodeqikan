# AI 领主系统

**核心数据：** `Scripts/Entities/Lord/lord_data.gd`
**状态：** 数据骨架完成，决策未实现

---

## 1. 定位

领主是世界中的战略决策主体：

- 拥有性格、目标、关系。
- 通过所属部队执行行动。
- 自己不直接出现在大地图移动逻辑中。

```text
Faction
└── Lord
    └── Party
        └── Unit
```

## 2. LordData

| 字段 | 说明 |
|---|---|
| `lord_id` | `LORD_000001` |
| `display_name` | 显示名 |
| `faction_id` | 所属阵营 |
| `party_id` | 所属部队 |
| `personality_id` | 性格配置 ID（数据驱动） |
| `current_goal` | 长期目标 ID |
| `current_state` | 当前状态 ID |
| `relationships` | 对其他领主的好感度 |
| `is_alive` | 是否存活 |

## 3. 初期决策流程

1. 判断自身部队情况（人数、伤亡、补给）。
2. 判断是否需要招募。
3. 选择附近村庄。
4. 前往村庄并完成招募。
5. 搜索敌对部队。
6. 根据兵力对比决定攻击或撤退。

对应 `LordData.current_goal` 的初期取值：

- `RECRUIT`
- `SEEK_ENEMY`
- `RETREAT`
- `GARRISON`

## 4. 分层决策

```text
LordAI
├── StrategicDecision
│   ├── RecruitmentDecision
│   ├── AttackDecision
│   └── RetreatDecision
└── PartyController
    ├── MoveToTarget
    ├── InteractWithSettlement
    └── ExecuteBattleOrder
```

- 领主层决定“做什么”。
- 部队层决定“怎么去/怎么打”。
- 单位层执行具体行为。

## 5. 频率

- 领主战略决策：每 30 世界秒。
- 部队战术决策：每 1 世界秒。
- 单位行为：物理帧。

`AIManager` 负责分频，不在渲染帧执行。

## 6. 性格与关系

- 性格由 `personality_id` 引用配置，代码不写死“好战/谨慎”分支。
- 性格影响权重：招募倾向、交战兵力比、撤退阈值、关系变化。
- `relationships` 只保存数值，文本/对话由上层解释。
- 阵营关系与个人关系分开：`FactionData.relations` 决定敌对，`LordData.relationships` 决定个人态度。

## 7. 后续扩展

- 领地管理。
- 外交、结盟、宣战。
- 阵营战争。
- 军团调度。
- 领主死亡与继承。
- 玩家招募领主。

## 8. 实现状态

| 项 | 状态 |
|---|---|
| `LordData` 与序列化 | 已实现 |
| 领主仓储 | 未建立（建议阶段 5 增加 `LordManager` 或并入世界上下文） |
| 战略决策 | TODO(阶段5) |
| 性格配置 | TODO(阶段5) |
| 与部队/地点联动 | TODO(阶段5) |

## 9. 待确认

- 领主数据由哪个管理器持有（新增 `LordManager` 还是归入 `WorldContext` 直接管理）。
- 一个领主是否永远只对应一个部队。
- 领主被俘/死亡的处理。
