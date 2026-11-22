# 领主系统

**核心数据：** `Scripts/Entities/Lord/lord_data.gd`
**核心仓储：** `Scripts/Core/World/lord_manager.gd`
**状态：** 阶段 7 第一步已实现：领主数据/仓储/存档、玩家领主身份、封地归属、AI 领主前往自有村庄征召。

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

## 2. 身份分离

以下四个身份互不替代：

| 身份 | 表示 | 说明 |
|---|---|---|
| 玩家 | `PartyData.control_type == PLAYER` | 控制权层 |
| 玩家领主 | `LordData.is_player_lord == true` | 封地所有权/战略身份 |
| 玩家角色 | `UnitData.is_player_character == true` | 可被控制的单个单位 |
| 部队领袖 | `PartyData.leader_unit_id` | 部队内的代表单位 |

- `WorldContext.player_lord_id` 指向玩家领主。
- `WorldContext.player_unit_id` 指向玩家角色单位。
- 玩家领主的 `party_id` 指向玩家部队；玩家领主死亡不等于玩家角色死亡。
- 旧存档没有领主数据时，读档只为玩家部队补一个玩家领主身份，不伪造封地归属。

## 3. LordData

| 字段 | 说明 |
|---|---|
| `lord_id` | `LORD_000001` |
| `display_name` | 显示名 |
| `faction_id` | 所属阵营 |
| `party_id` | 所属部队；一个领主最多一支部队 |
| `is_player_lord` | 是否为玩家领主 |
| `personality_id` | 性格配置 ID（数据驱动） |
| `current_goal` | 长期目标 ID |
| `current_state` | 当前状态 ID；阶段 7 AI 使用 `RECRUITING` |
| `current_target_settlement_id` | 当前战略目标地点 |
| `relationships` | 对其他领主的好感度 |
| `is_alive` | 是否存活 |

`to_dict()` / `from_dict()` 持久化全部字段；缺失字段使用安全默认值。

## 4. LordManager

`WorldContext` 持有唯一 `LordManager`：

- `create_lord(display_name, faction_id, party_id, is_player_lord)`：创建并注册领主。
- `add_lord()` / `get_lord()` / `get_all_lords()` / `remove_lord()`。
- `get_player_lord()`：按 `is_player_lord` 查找。
- `validate(party_manager)`：校验领主引用的部队存在、一个部队最多一个领主、玩家领主唯一。
- `to_dict()` / `load_from_dict()`：存档往返；读档后修正 ID 计数器。
- 不负责 AI 决策、封地分配或 UI。

## 5. 封地归属

- `SettlementData.owner_lord_id` 是封地归属的唯一权威字段。
- 归属判断只看 `owner_lord_id`，不看 `faction_id` 或 `family_id`。
- `WorldContext.validate_world_ownership()` 校验每个非空归属都能找到领主，并校验玩家领主身份。
- 新游戏初始封地：
  - 巴里 → 巴里家族领主；
  - 墨西西 → 墨西西家族领主；
  - 青禾村 → 玩家领主；
  - 其他地点无主或保持原配置。
- 当前没有封地转让、继承、战争占领或领主死亡处理。

## 6. AI 领主征召

`AIManager` 以低于部队战术 AI 的频率执行领主战略决策：

1. 跳过玩家领主、死亡领主和无部队领主。
2. 若部队人数低于 `ai_lord_recruit_threshold`（默认 12），查找最近的、自己拥有的、有采邑储备的村庄。
3. 设置 `current_state = "RECRUITING"`、`current_target_settlement_id`，部队移动到村庄。
4. 抵达后调用 `FiefRecruitmentManager.recruit_group()`。
5. 无论成功失败，清除征召状态与目标，恢复普通 AI。

- `RECRUITING` 期间该部队的战术 AI 跳过，避免巡逻/追击覆盖征召目标。
- 征召成功的事实通过 `EventBus.fief_recruited` 进入世界日志。
- 详细流程见 [Fief_Recruitment_System.md](Fief_Recruitment_System.md)。

## 7. 分层决策

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

当前只实现征召决策；攻击/撤退仍由既有部队 AI 完成。

## 8. 频率

- 领主战略决策：每 30 世界秒（`AIManager` 分频）。
- 部队战术决策：每 1 世界秒。
- 单位行为：物理帧。

`AIManager` 负责分频，不在渲染帧执行。

## 9. 性格与关系

- 性格由 `personality_id` 引用配置，代码不写死“好战/谨慎”分支。
- 性格影响权重：招募倾向、交战兵力比、撤退阈值、关系变化。
- `relationships` 只保存数值，文本/对话由上层解释。
- 阵营关系与个人关系分开：`FactionData.relations` 决定敌对，`LordData.relationships` 决定个人态度。
- 当前性格与关系尚未参与征召阈值计算。

## 10. 持久化与校验

- 存档 Schema v4 新增顶层 `lords`；`WorldContext.to_save_data()` 写入 `lord_manager.to_dict()`。
- `player` 字典保存 `player_lord_id` 与 `player_unit_id`。
- 读档顺序：单位 → 部队 → 运行时默认值 → 领主 → 地点 → 世界日志。
- 领主校验失败或封地引用悬空时拒绝读档，不自动改写存档。
- 旧存档缺少 `lords` 时创建玩家领主；不补 NPC 领主，也不改地点归属。

## 11. 实现状态

| 项 | 状态 |
|---|---|
| `LordData` 与序列化 | 已实现 |
| `LordManager` 仓储 | 已实现 |
| 玩家领主 / 玩家角色分离 | 已实现 |
| 封地归属 `owner_lord_id` | 已实现 |
| 读档所有权校验 | 已实现 |
| AI 领主前往自有封地征召 | 已实现 |
| 战略攻击/撤退决策 | TODO |
| 性格配置与关系权重 | TODO |
| 领主死亡/继承/封地转让 | TODO |
| 玩家招募领主 | TODO |

## 12. 待确认

- 一个领主是否永远只对应一个部队。
- 领主被俘/死亡的处理。
- 领主人格、目标与关系的配置资源格式。
- 封地税收是否进入领主个人金库。
