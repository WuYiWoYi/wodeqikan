# 我的骑砍 · 开发入口（核心记忆）

> 本文件是每次任务默认读取的**核心记忆**。它只保留项目身份、硬约束、读取规则与文档导航；具体系统规则在 `Docs/Systems/`，易变状态在 `Docs/Development/Current_Status.md`，历史在 `Docs/Archive/` 与 `Docs/04_Change_Log.md`。
> 最后整理：2026-11-22（阶段 13 完成后）。本文件不替代代码；实现是否存在以当前工程为准。

## 1. 项目身份

- 纯 2D 中世纪沙盒战略游戏：玩家在大地图带兵、战斗、经营关系，世界在玩家不操作时也持续运转。
- 引擎：Godot 4.6.1 / GDScript；主场景 `Scenes/MainMenu/main_menu.tscn`。
- 仓库：`https://github.com/WuYiWoYi/wodeqikan`（私有）。
- 语言：标识符英文，注释、文档、UI 文本中文。
- 源规划：`md/2D 中世纪沙盒战略游戏核心架构设计与开发规划.md`，**只读**，仅作需求来源；实现细节以 `Docs/` 为准。

## 2. 硬约束（跨任务）

1. **仅 5 个 Autoload**：`EventBus`、`TimeManager`、`SaveManager`、`SceneManager`、`GameManager`。其他管理器一律由 `WorldContext` 装配，不得新增 Autoload。
2. **数据与表现分离**：运行时实体是 `RefCounted` 纯数据（`Scripts/Entities/`）；场景节点只做表现，不得成为权威数据源，也不得回写世界数据。
3. **单一写者**：每个权威字段只有一个写入者；新增字段先声明“谁写、通过哪个接口写”。权威表见 `Docs/01_Core_Architecture.md` 第 7 节。
4. **时间只由 `TimeManager` 推进**：世界逻辑只认 `world_tick`；暂停只用 `push_pause/pop_pause`；禁止 `Engine.time_scale` 与 `get_tree().paused`。小场景/战斗使用 `SceneTime`。
5. **UI 只展示与发起意图**，不结算规则、不直接改实体字段。
6. **实体 ID 只由 `IdGenerator` 生成**，计数器随存档保存，永不复用；禁止用节点名、数组下标或时间戳代替。
7. **存档=JSON + `schema_version`**，只保存持久化数据，不保存节点；新增持久化字段必须评估迁移。
8. **引用与访问**：管理器通过 `WorldContext` 显式装配；禁止 `get_node("/root/...")`、跨场景节点路径通信、`EventBus` 请求-响应。
9. **静态配置用 `Resource`/`.tres`**（`Data/`），不把数值写死在脚本里。
10. **不修改 `md/` 源规划**；不把其他项目（塔防、卡牌等）的记忆或规范混入本项目。

## 3. 默认读取流程（最小上下文）

1. 读本文件。
2. 用第 4 节表格判断涉及的系统，**只读对应专题文档 1–2 份**。
3. 只有任务依赖“当前进度/已有实现/下一步”时，才读 `Docs/Development/Current_Status.md`。
4. 需要“为什么这样设计”时，按 D 编号查 `Docs/Development/Technical_Decisions.md`；需要历史时查 `Docs/04_Change_Log.md` 或 `Docs/Archive/`。
5. 只读直接相关代码 3–5 个文件；必要时做一轮精确符号搜索。
6. 能确定改动范围、接口与验收方式后立即停止探索并开始实施。

**默认预算：** 核心记忆 1 份 + 专题 1–2 份 + 直接相关代码 3–5 个 + 一轮精确搜索。超出时说明原因。

**只有以下情况才扩大读取：**

- 需求确实跨多个系统；
- 公共接口、数据所有权或调用时序不明确；
- 当前实现与专题文档冲突；
- 涉及存档结构、核心状态流转或公共架构；
- 已读文件无法可靠判断。

**禁止：** 每次读全部 `Docs/`、扫描整个 `Scripts/`/`Scenes/`/`Data/`、重复读本轮未变化的文件、把历史文档当作当前实现、为“证明理解”输出冗长阅读清单。

## 4. 任务 → 必读专题

| 任务涉及 | 读取 |
|---|---|
| 单位、属性、等级/经验、装备、晋升、伤兵/俘虏状态 | `Docs/Systems/Unit_System.md` |
| 部队成员、控制类型、编队、部队 UI、遭遇对话 | `Docs/Systems/Party_System.md` |
| 战斗流程、攻击判定、队形、增援、离屏结算、BattleResult | `Docs/Systems/Combat_System.md` |
| 伤兵判定/治疗、俘虏分配/出售、酒馆 | `Docs/Systems/Wounded_Prisoner_System.md` |
| 大地图移动、视野、标记、跟随、相机、地点交互 | `Docs/Systems/World_Map_System.md` |
| AI 决策、路线、追击、支援、NPC 补给采购 | `Docs/Systems/AI_System.md` |
| 时间、暂停栈、日历、倍率 | `Docs/Systems/Time_System.md` |
| 场景切换、小场景相机、村庄场景 | `Docs/Systems/Scene_System.md`、`Village_System.md` |
| 地点数据、城镇/城堡、市场/酒馆入口 | `Docs/Systems/Settlement_System.md` |
| 背包、金币、工资、交易、村庄/城镇市场 | `Docs/Systems/Inventory_Economy_System.md` |
| 马匹实例、外观、装备/卸下 | `Docs/Systems/Mount_System.md` |
| 每日面包/草料、补给缺口、NPC 采购 | `Docs/Systems/Supply_System.md` |
| 封地、采邑征召、税收缓存、冒险者候选人 | `Docs/Systems/Fief_Recruitment_System.md`、`Adventurer_Recruitment_System.md` |
| 贵族/家族/王国、关系、选举、战争传播 | `Docs/Systems/Political_Hierarchy_System.md`、`Lord_System.md` |
| 世界日志 | `Docs/Systems/World_Log_System.md` |
| 百科 | `Docs/Systems/Encyclopedia_System.md` |
| 存档结构、Schema、迁移 | `Docs/Systems/Save_System.md` |
| 对话数据与跳转 | `Docs/Systems/Dialogue_System.md` |
| 代码/命名/数据/场景/测试规范 | `Docs/03_Design_Conventions.md` |
| 当前进度、已实现/未实现、下一步 | `Docs/Development/Current_Status.md` |
| 未决问题、已知限制、待决策 | `Docs/Development/Known_Issues.md` |
| 阶段规划与历史验收记录（**仅在规划/验收时读**） | `Docs/02_Development_Roadmap.md` |
| 架构原则、依赖方向、数据权威、事件契约 | `Docs/01_Core_Architecture.md` |
| 稳定事实与文档总索引 | `Docs/00_Project_Index.md` |

> 专有名词以代码与系统文档为准；不要在核心记忆中维护每个系统的字段清单。

## 5. 冲突与时效规则

判断优先级从高到低：

1. 用户在当前任务中明确提出的最新要求；
2. 用户此前明确确认且仍有效的设计规则；
3. 当前工程代码、场景、Resource 反映的实际实现；
4. 最新且明确标注状态的项目文档；
5. 较早的记忆摘要、历史需求和讨论记录；
6. AI 过去提出但未被用户确认的建议。

补充规则：

- “设计目标”不等于“已经实现”；“文档写了”不等于“代码已实现”。
- “代码当前如此”也不自动代表用户最终认可；发现实现与已确认规则不一致时，指出差异，不擅自改设计。
- 无法判定的新旧冲突：保留两种说法并标记 `待确认`，不要自行合并或裁决。
- 内容状态标记统一使用：`已确认`、`暂定`、`待确认`、`已过时`。
- 已过时内容应修订或明确标为失效；禁止只追加新说法而留下旧说法误导。

## 6. 文档更新规则

只有满足以下条件之一才更新长期记忆：

- 用户明确确认了一项长期设计规则；
- 新增或调整了稳定的系统职责、数据所有权或公共接口；
- 发现具有复发风险、值得长期提醒的技术陷阱；
- 项目阶段或实现状态发生了对后续任务有价值的变化。

更新时：

1. 优先修改原有条目，不追加重复内容；同一规则只保留一个权威位置，其他文档用链接引用。
2. `Current_Status.md` 采用**覆盖式**更新；`04_Change_Log.md` 与 `Archive/` 采用**追加式**记录。
3. 一次性调试结果、临时数值试验、未确认建议不进入长期记忆。
4. 过时内容修订或标记失效；不保留互相矛盾的现行规则。
5. 更新后检查索引、相对链接、文件名与锚点是否仍正确。
6. 不为一次小改动更新所有记忆文件。

## 7. 测试

- 按改动影响选择 L1–L4，默认只运行能验证本次修改的最小测试集；局部失败后再扩大范围。
- 开发前说明：改动文件、涉及系统、接口影响、将运行与明确不运行的测试。
- 完成后说明：完成内容、修改文件、实际执行的测试、结果、未验证的关联风险。
- 完整分级规则见 `Docs/03_Design_Conventions.md` 第 10 节；运行命令见 `Docs/Development/Test_Commands.md`。

## 8. 文档分层与权威

| 层 | 文件 | 何时读 |
|---|---|---|
| 核心记忆 | `CLAUDE.md`（本文件） | 每次任务 |
| 稳定事实/索引 | `Docs/00_Project_Index.md` | 需要基础决策或文档导航时 |
| 架构 | `Docs/01_Core_Architecture.md` | 改动架构、数据归属、事件、生命周期时 |
| 专题 | `Docs/Systems/*.md` | 按第 4 节选择 |
| 当前状态 | `Docs/Development/Current_Status.md` | 依赖当前进度时 |
| 未决问题 | `Docs/Development/Known_Issues.md` | 评估限制/风险时 |
| 决策记录 | `Docs/Development/Technical_Decisions.md` | 按 D 编号检索，不顺序通读 |
| 历史 | `Docs/04_Change_Log.md`、`Docs/Archive/` | 追溯时读取，默认不读 |
| 规划 | `Docs/02_Development_Roadmap.md` | 规划/验收时读取；其中“剩余任务”可能过时 |
| 源需求 | `md/*.md` | 只读，仅在需要原始意图时读 |

**权威性：** `Docs/` 是持续维护的开发依据；`md/` 是只读源规划。冲突处理顺序见第 5 节；记录架构变更原因时写 `Technical_Decisions.md`。
