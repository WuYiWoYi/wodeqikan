# 当前开发状态

**更新日期：** 2026-11-21
**当前阶段：** 阶段 6 后续 · 弓箭手与远程箭矢完成
**整体状态：** 三级弓箭手接入现有 UnitData/UnitController；弓与箭临时美术、抛物线箭矢、高度命中与自然射失完成；AI 与玩家共用固定终点发射入口和 3 秒冷却；新游戏玩家部队扩编到 15 人（含 3 名弓箭手）；远程与近战/存档相关测试通过

---

## 1. 阶段状态

| 阶段 | 状态 | 说明 |
|---|---|---|
| 0 工程基础架构 | 完成 | Autoload、数据层、主菜单、存档闭环 |
| 1 大地图基础 | 完成 | Milestone 1 全部功能已实现 |
| 2 世界模拟 | 部分完成 | 固定 tick / 直线移动 / NPC 商队与巡逻已实现；视野、敌对追击、AI 对 AI 遭遇待开发 |
| 3 士兵与部队 | 部分完成 | 等级/经验/装备/马匹骑乘/最终属性/部队查看面板/人物马匹分组/长矛动画/美术预览完成；招募、正式美术未开始 |
| 4 基础战斗 | 部分完成 | 双方/多方实时战斗、统一攻击判定、多人围攻、离屏自动结算、中途加入、玩家角色、基础队形、控制权转移、结果/经验/奖励已实现；高级指挥/士气/正式动画未开始 |
| 5 战斗结算与战后处理 | 完成 | BattleResult、玩家角色、队形/避让、控制权转移、经验/奖励、撤退、结果面板、返回大地图 |
| 5 后续优化 | 完成 | 统一攻击判定、多人围攻、AI 接近/攻击、临时部件美术、骑乘系统与测试部队 |
| 5 移动/动画/碰撞/全向攻击 | 完成 | 马腿层级、待机/移动动画、战斗降速、初始部署、1920×1080、武器射程、实体碰撞、360°矩形攻击 |
| 5 动作表现与攻击体验 | 完成 | 协调步态、马匹整体动态、自由空挥、长矛攻击后保持、骑乘战斗加速、部署距离进一步增加 |
| 5 待机与动作表现二次优化 | 完成 | 克制腿幅、部队 UI 待机动画、跃马式前后腿分组、长矛前摇与戳击 |
| 5 腿部旋转中心修正 | 完成 | 人物双腿与四条马腿旋转中心统一下移 3 px，可见位置与动作关系不变 |
| 5 腿部幅度与战马整体跃动 | 完成 | 马腿枢轴累计 6 px、马腿收敛；马身整体跃动增强、骑手跟随；步兵腿幅进一步降低 |
| 5 腿部挂载与局部动画 | 完成 | 双腿挂载到身体变换节点、人马腿再下移 3 px（实际累计人物 6 / 马腿 9）、局部动作进一步收敛 |
| 5 骑兵动画与影子优化 | 完成 | 马腿局部动作适度增大、骑兵整体起伏降低、骑马影子随跃动轻微缩放/变淡 |
| 5（原路线图）AI 领主与交互 | 未开始 | 数据层已具备 |
| 6 村庄场景、交互与部队管理 | 完成 | 村庄小场景、对话、追逐保护、背包/马匹、金币/工资、三级兵种/晋升、世界日历、大地图部队 UI |
| 6 大地图战斗与小地图视角 | 完成 | 统一摄像机/自由视角、按小时离屏结算、追击接触修复、战斗单标记与多方汇总 UI |
| 6 世界日志、美术层级与战斗表现 | 完成 | 左下角世界日志、左右手独立层级、头部/头盔分离、中立部队不自动打断、满血隐藏生命条 |
| 6 后续 · 统一部队架构与遭遇交互 | 完成 | 统一 Party 控制类型/类型标识、底部 NPC 遭遇对话、领袖头像/默认剪影、遭遇原因、ENEMY_PURSUIT 禁止离开、旧存档安全推断 |
| 6 后续 · 村庄表现/玩家扩编/战斗集群 | 完成 | 部队标记恢复原尺寸、村庄圆形标记放大、名称位于上方、玩家 12 人、初始部署距离 1100、半场列阵/接敌放松/目标分流/局部避让 |
| 6 后续 · 大地图表现/AI 恢复/存档/战斗 UI | 完成 | 村庄原始美术 + 徽章名称组合、AI 战后恢复与冷却、Schema v3 世界日志与读档清理、胜利 3 秒延迟、按 side_index 分列、左 Alt 详细悬浮 |
| 6 后续 · 弓箭手与远程箭矢 | 完成 | 三级弓箭手、弓/箭临时美术、固定终点抛物线箭矢、高度命中与自然射失、远程 AI、玩家射箭、3 秒冷却、新游戏 3 名弓箭手与存档 |
| 6（原路线图）援军与高级战斗 | 未开始 | 并入后续高级战斗阶段 |
| 7 沙盒扩展 | 未开始 | — |

## 2. Milestone 1 已完成内容

### 世界与数据

- `WorldInitializer`：新游戏生成世界 ID、3000×2000 地图、玩家部队、2 支 NPC 部队、4 个地点。
- `SettlementManager`：地点数据仓储与序列化，已接入 `WorldContext`。
- `WorldContext`：新增 `to_save_data()` / `load_from_save_data()`，聚合与恢复世界状态。
- `SaveData`：Schema v2，新增世界 ID、创建时间、世界尺寸、玩家部队 ID。
- `SaveManager`：临时文件 + 校验 + `.bak` 备份替换；存档头信息、排序、最近有效存档查询。
- `TimeManager`：新增 `get_base_world_speed()`、`restore_world_time()`。
- `GameManager`：新游戏、读档、Continue、保存、同步销毁旧世界。

### 大地图

- 3000×2000 手绘式背景：草地、网格、道路、河流、边界。
- 玩家部队 + 2 支 NPC 部队图标，4 个地点图标（村庄/城堡）。
- 点击地图设置目标，直线移动，2 像素到达阈值，地图边界 clamp。
- 摄像机跟随、方向键平移、滚轮缩放。
- 图标读取数据并插值，不写回权威数据。

### 时间与交互

- 暂停 / 1x / 2x 时间按钮，UI 显示世界时间与倍率。
- 新游戏默认暂停；读档恢复存档中的基础倍率。
- 地点 40 像素交互半径，带路径段检测，避免高倍速穿过地点时漏判。
- 到达地点自动停止、暂停并打开面板；离开后仍保持暂停。
- 保存面板打开时使用暂停原因栈，关闭后恢复原倍率。

### 主菜单

- 新游戏、继续、读取存档、设置占位、退出。
- Continue 自动选择最近有效存档，无存档时禁用。
- 读取列表显示存档名与保存时间，支持双击读取。
- 设置占位面板。

### 版本管理

- 私有远程：<https://github.com/WuYiWoYi/wodeqikan>
- 当前工作区包含 Milestone 1 改动（尚未提交，等待确认）。

## 3. Milestone 2 Step 1 已完成内容

### 士兵配置与创建

- `Data/Units/infantry_militia.tres`（民兵）与 `Data/Units/infantry_trained.tres`（职业步兵）。
- `UnitManager.create_unit()` 按配置生成独立 `UnitData`；ID 由 `IdGenerator` 生成，两次创建互不相同。
- `StatCalculator` 成为属性初始化的唯一入口：当前复制配置基础属性，保留等级与装备扩展点。
- 出生时 `current_party_id` 为空，`current_hp = max_hp`；多个士兵不共享运行时状态。

### 成员关系

- `PartyManager.add_member()` 支持转队：先从所有其他部队移除，再加入目标部队；一个单位最多属于一支部队。
- 重复加入同一部队不会产生重复成员；转队操作在全部校验通过后一次性修改，避免半转移状态。
- `transfer_member()` 与 `add_member()` 共用同一套底层规则。
- 本阶段要求单位与部队 `faction_id` 一致，拒绝跨阵营加入。
- `remove_member()` 只清空归属，不删除 `UnitData`。
- `remove_party()` 清空所有成员归属，单位保留在 `UnitManager`。

### 数据安全

- `UnitManager.add_unit()` / `PartyManager.add_party()` 拒绝覆盖已存在 ID，失败时原实体不变。
- `UnitManager.remove_unit()` 拒绝删除仍属于部队的单位。
- `PartyManager.validate_membership_consistency()` 校验四类关系：成员存在、部队存在、唯一归属、双向一致。
- `WorldContext.load_from_save_data()` 在恢复两个仓储后统一校验；失败时 `push_error` 并返回 `false`，不自动改写存档。

### 测试

- 新增 `Tests/UnitTests/` 四个测试：`unit_manager_test`、`party_manager_test`、`stat_calculator_test`、`unit_party_serialization_test`。
- 序列化测试覆盖 5 名士兵、Party A/B、移除与转队、保存/读取、二次往返、读档后继续转队、损坏引用拒绝加载。

## 4. Milestone 2 Step 2 已完成内容

### 大地图遭遇与对话

- 玩家进入 AI 部队 40 像素范围触发 `PartyDialoguePanel`，使用路径段检测避免高倍速穿过。
- 面板显示部队名称、阵营、`member_unit_ids.size()` 兵力。
- “离开”关闭面板并恢复此前世界时间状态；“发起战斗”创建战斗会话并进入战斗场景。
- 同一时间只有一个对话面板；空部队不触发交互；任一方无兵时战斗按钮禁用。
- 新游戏通过 `WorldInitializer.create_test_battle_forces()` 给玩家和“河畔商队”各生成 3 民兵 + 2 职业步兵，单位标记 `recruit_source = "milestone2_test"`。

### 战斗场景与士兵

- `BattleSession` 新增双方 `unit_id` 列表与阵营字段。
- `BattleManager.start_battle()` 校验部队、阵营、可用性与存活士兵，生成 `BattleUnitState`，锁定部队并压入 `battle` 暂停。
- `BattleScene` 根据会话生成士兵；节点名 `UnitActor_<unit_id>`，玩家蓝色、敌方红色，位置按 2 列阵型分开。（当时为 10 人；后续玩家部队扩为 7 人，见 8.1）
- `UnitActor` 程序绘制身体、朝向武器、血条与名称；不修改 `UnitData`。（后续已由 `UnitVisual` 部件表现替换，见 8.1）
- 每个士兵由 `UnitController` 驱动，属性全部读取 `UnitData`。

### 实时战斗

- 自动索敌最近敌人；目标死亡后重新选择。
- 进入 `attack_range + 8` 后按 `attack_interval` 攻击，伤害写入 `BattleUnitState.battle_hp`。（后续统一为 `CombatRules` 的身体边缘距离，见 8.1）
- 玩家左键点击地面命令所有存活己方士兵移动；手动移动期间不主动攻击，到达后恢复自动索敌。
- 敌方自动接近并攻击；HP 归零后停止移动、攻击与受伤，表现节点移除。
- 一方全灭或双方全灭时显示胜利/失败/平局结果面板。

### 结算与返回

- 玩家点击“返回大地图”后 `BattleManager.finish_battle()` 统一结算。
- 存活士兵写回剩余 HP；阵亡士兵清空归属、删除 `UnitData` 并广播 `unit_died`。
- 参战部队结算：存活部队恢复 `AVAILABLE`，全员阵亡部队置为 `DISABLED`；清理 `BattleSession`；移除 `battle` 暂停，恢复此前世界时间状态。
- 重复结算被拒绝；战斗期间 `GameManager.save_game()` 返回 `ERR_BUSY`。
- 返回大地图后可继续移动、保存和读档；空敌方部队不再触发对话。

## 5. 阶段 2 · Step 2 已完成内容

### NPC 自主移动

- `PartyData` 新增 `ai_type`、`ai_route_index`、`ai_route_settlement_ids`，旧存档缺失字段使用安全默认值。
- 河畔商队 `TRADE_ROUTE`：在巴里与墨西西之间循环往返，路线使用 stable `settlement_id`，坐标来自 `SettlementManager`。
- 北境巡逻队 `PATROL`：按 `(2200,500) → (2600,900) → (2400,1500) → (1900,1200)` 循环。
- `AIManager` 每 1 世界秒决策；跳过玩家、非 `AVAILABLE`、正在移动的部队；只通过 `WorldMapManager.set_party_target()` 下达目标。
- 到达路线点后，下一次决策推进路线索引；移动仍由 `WorldSimulation` 固定 tick 驱动。
- 全员阵亡的部队结算为 `DISABLED`，停止 AI 与世界模拟。

### 玩家速度与输入

- 新游戏玩家移动速度 150；NPC 保持 220；旧存档保留原有速度。
- 顶部主键区数字键 `1` / `2` / `3`：暂停 / 1x / 2x；小键盘与 echo 不触发。
- 保存面板、地点面板、部队对话打开时，快捷键与地图点击均被屏蔽。
- 玩家点击有效地图并成功设置移动目标后，基础倍率自动切为 1x；不清除任何暂停原因。
- 时间按钮与快捷键复用 `_set_world_speed()`，避免两套逻辑。

### 测试

- 新增 `ai_manager_test`：商队往返、巡逻循环、玩家/战斗/NONE 跳过、边界限制、AI 字段序列化。
- 新增 `world_map_input_test`：数字键、UI 暂停保护、点击倍率、真实 WorldTime tick 下的 NPC 移动。

## 6. 阶段 3 · Step 3 已完成内容

### 士兵成长与装备

- `UnitConfig` 增加等级上限、经验需求与每级成长参数；民兵与职业步兵使用不同成长曲线。
- `UnitManager.add_exp()` 支持一次增加触发多级升级；满级后停止升级并清空经验。
- 士兵创建时生成独立名称（如“民兵 01”），名称随存档保存；旧存档缺失名称时回填兵种模板名称。
- `EquipmentConfig` 统一使用槽位字符串（`WEAPON` / `OFFHAND` / `HEAD` / `BODY` / `MOUNT`），每个槽位最多一件。
- `UnitManager.equip_item()` / `unequip_slot()` 完成合法性校验、同槽位替换与属性重算；失败不产生部分修改。
- 五个示例装备位于 `Data/Equipment/`，仅用于数据层验证。

### 最终属性与 HP 安全

- `StatCalculator` 公式：兵种基础值 + (等级 - 1) × 每级成长 + 装备加成。
- 最终攻击间隔仍只取兵种基础值；本次不接入百分比或攻击间隔装备加成。
- 升级、装备、卸下装备都会立即重算最终属性。
- 重算只对 `current_hp` 做上限 clamp；升级不自动回血，卸下装备导致上限降低时才截断当前 HP。
- 只有创建新单位会设置为满血。

### 静态配置注册与读档

- `WorldContext._ready()` 扫描 `Data/Units` 与 `Data/Equipment` 并注册到 `UnitManager`；重复 ID 拒绝覆盖。
- 读档后按当前配置、持久化等级与装备重算全部士兵属性，再对当前 HP 做上限修正。
- 无效装备引用报告错误并清理；兵种配置缺失时保留缓存属性作为降级结果。
- 未新增持久化字段，存档 Schema 仍为 v2。

### 部队管理面板

- 大地图顶部新增“部队”按钮，打开玩家部队管理面板。
- 左侧成员列表按 `PartyData.member_unit_ids` 顺序显示姓名、兵种、等级、HP、攻击；默认选中第一名有效成员。
- 右侧详情显示身份、等级、经验进度、当前/最大 HP、攻击、攻击间隔、移速、射程、五个装备槽位与招募信息。
- 空装备槽显示“无”；不显示项目尚未实现的防御/护甲属性。
- 打开面板压入 `ui_panel` 暂停原因，关闭只移除本面板原因，基础倍率保持不变。
- 面板只读，所有写操作仍通过管理器接口；无效成员引用不会导致 UI 崩溃。
- 装备更换、招募、解雇、转队暂未提供 UI（KI327）。

### 测试

- 新增 `party_panel_test`：入口按钮、概览、成员列表、默认选中、详情切换、装备显示、无效成员引用、关闭后的暂停恢复与其他暂停原因保护。
- 扩展 `stat_calculator_test`：等级成长、装备叠加、无效装备、HP 安全规则。
- 扩展 `unit_manager_test`：配置注册、重复拒绝、默认装备、经验升级、多级升级、满级、装备替换/卸下、HP 不重置。
- 扩展 `unit_party_serialization_test`：不同等级/经验/装备/当前 HP 往返、读档重算、旧存档缺失字段、无效装备清理。

## 7. 阶段 4 · 大地图阵营生态与动态遭遇

### Step 0：移动体验调整

- 商队、治安队速度从 220 降为 110；强盗新增速度 135；玩家保持 150。
- 后续 AI 优化将速度关系调整为治安队 120 > 强盗 100 > 商队 80，玩家仍为 150。
- 速度只改初始化参数，不在移动函数中额外缩放。
- 玩家点击移动中的有效部队进入 `FOLLOW_PARTY`，每 0.5 世界秒读取目标最新位置。
- 追上目标（14 像素）、进入战斗或失效时自动取消跟随；主动点击的跟随不因目标离开视野中断（D088）。
- 普通地图点击、时间倍率与 UI 输入屏蔽规则保持不变。

### Step 5：阵营关系与视野

- 新增 `FactionManager`：玩家 / 商队 / 强盗 / 治安队 / 本地势力。
- 默认关系：
  - 玩家-商队中立、玩家-强盗敌对、玩家-治安队中立；
  - 商队-治安队友好、商队-强盗敌对、强盗-治安队敌对；
  - 同阵营友好；未知组合中立。
- 新增 `VisionManager`：距离检测、可见敌对/友方/中立列表、最近敌对目标、`can_see()`。
- `DISABLED` / `IN_BATTLE` 观察者不会主动发现目标；空部队与不可用部队不会被选为目标。
- AI 只使用 `FactionManager` 与 `VisionManager`，不各自维护敌人识别逻辑。

### Step 6：强盗 AI

- 新增强盗阵营与“山道强盗”测试部队。
- 目标优先级：商队 → 治安队 → 玩家 → 其他敌对；同优先级取最近。
- 发现目标后持续更新目标位置并追击；后续由 `EncounterManager` 统一以 50 世界单位判定遭遇。
- 目标离开视野、被删除或进入战斗后清除 `current_target_id`。
- 无目标时沿 `ai_route_settlement_ids` 路线游荡。
- 战斗期间 `IN_BATTLE`，停止大地图移动和常规 AI。

### Step 7：治安队 AI

- 北境巡逻队改为治安队阵营，保留原有四点巡逻。
- 优先拦截“正在追击商队”的强盗，其次追击最近的可见强盗。
- 目标消失或失去视野后放弃追击，恢复原巡逻路线。
- 不会攻击商队或其他友军。
- 附近存在可加入的离屏战斗时，优先接近并加入。

### Step 8：多方战斗

- `BattleSession` 新增 `BattleParticipant`、`side_party_ids` / `side_unit_ids`、`winning_side_index`、`offscreen`、`paused_world`、`player_involved`。
- `BattleManager.start_battle_by_sides()` 支持任意战斗侧；原有双方 `start_battle()` 保持兼容。
- `get_join_side()` 按阵营关系决定加入哪一侧；与所有现有侧敌对时建立独立第三方；无敌对关系时拒绝加入。
- `try_join_battle()` / `add_reinforcement()` 完成距离、可用性、重复参战校验。
- 离屏战斗 10 世界秒后自动结算；期间世界继续运行，第三方可加入。（后续已由 8.10 与 D079 改为每游戏小时结算）
- 玩家进入离屏战斗交互范围时先弹出“加入/离开”面板；加入后转换为屏幕战斗并进入 `BattleScene`，离开则 NPC 战斗继续。
- 玩家被敌对 AI 主动拦截时先进入遭遇对话；选择战斗后创建屏幕战斗并切换场景。
- BattleScene 按战斗侧生成士兵、构建敌人列表；同侧不互相攻击，玩家输入作用于实际所在侧。
- 结算按战斗侧统计存活单位，统一写回 HP、移除阵亡、解锁/禁用全部参战部队。

### AI 遭遇行为优化

- **统一遭遇判定**：新增 `EncounterManager`，在移动后、AI 前执行遭遇与中途参战检测。
  - 双方有效、非 DISABLED、阵营敌对、距离 <= 50；
  - 至少一方的 `attack_intent` 明确指向对方（`current_target_id` 匹配）。
  - 所有 AI 类型共用；AI 不再自行判断距离或创建战斗。
- **攻击意图**：`PartyData.attack_intent` 为运行时字段，不进入存档。
  - 强盗追击、治安队拦截时置 true；普通巡逻/移动/玩家跟随为 false。
  - 目标离开视野、进入战斗或遭遇触发后清除。
- **修复追逐无法交战**：商队继续移动时，只要距离进入 50，追击方即可触发离屏战斗，不要求目标停下。
- **速度关系**：治安队 120 > 强盗 100 > 商队 80；玩家 150。旧存档速度不被重置。
- **强盗动态目标评分**：
  - `评分 = 类型基础分 - 距离 × 0.1`；商队 300 / 治安队 200 / 玩家 100 / 其他 50。
  - 新目标评分至少高出 30 才切换，避免频繁横跳。
  - 当前目标失效/离开视野时立即重新选择；追逐玩家时出现商队会重新评估。
- **玩家遭遇对话**：
  - 敌对 AI 主动追击玩家且距离 <= 50 时，停止双方、清除追击、记录唯一 `encounter_id`。
  - 压入独立 `encounter_dialogue` 暂停原因，弹出对话；只提供“战斗”选项。
  - 对话期间 WorldSimulation 跳过 AI，防止重复创建战斗。
  - 选择战斗后创建屏幕战斗、移除遭遇暂停、保留基础倍率并进入 `BattleScene`。
  - 取消/异常退出只清理本次暂停与待处理遭遇。
- **玩家接近进行中的 NPC 战斗**：
  - `EncounterManager.update_player_battle_interaction()` 检测玩家进入 55 世界单位。
  - 停止玩家、记录唯一 `interaction_id` / `battle_id`，WorldMap 压入 `battle_encounter_dialogue`。
  - 面板显示交战方与持续时间，提供“加入战斗”与“离开”。
  - 加入：加入已有 BattleSession，不创建重复战斗；离开：NPC 战斗继续。
  - 离开后在 90 世界单位退出范围内不再重复弹出；离开范围后可重新触发。
  - 战斗结束、ID 变化、玩家已参战或异常关闭时自动清理面板与暂停。

### 测试

- 新增 `faction_vision_test`：阵营关系组合、对称性、视野内/外、敌对/友方/中立筛选、失效观察者与目标。
- 新增 `multi_party_battle_test`：双方回归、友军加入、独立第三方、中立拒绝、距离/重复校验、多方离屏结算、BattleScene 多侧生成与胜负。
- 新增 `ai_encounter_flow_test`：玩家加入离屏战斗、`battle_started` 自动进入战斗场景。
- 新增 `player_encounter_test`：无敌意不触发、遭遇暂停栈、对话内容、战斗/撤退选项、防重复、异常清理、进入战斗场景。
- 新增 `player_battle_interaction_test`：接近离屏战斗面板、加入已有战斗、离开后不重复、离开范围可重触发、战斗结束/异常清理、基础倍率与其他暂停保护。
- 扩展 `ai_manager_test`：强盗动态评分与切换阈值、攻击意图、单方/双方意图遭遇、友方不遭遇、失去视野、离屏战斗、治安队威胁优先/恢复巡逻/加入战斗。
- 扩展 `world_map_input_test`：治安队 120 / 强盗 100 / 商队 80、跟随开始/更新/追上/离开视野/目标战斗/新指令取消、点击移动与静止部队分流。

## 8. 阶段 5 · 战斗结算与战后处理

### Step 1：统一战斗结果

- 新增 `BattleResultData`：战斗 ID、获胜/失败/撤退侧、参战部队快照、各部队阵亡/存活、经验明细、金币/战利品、结束原因、玩家参与/获胜、结算时间与 `finalized`。
- 屏幕、离屏、玩家中途加入统一使用 `BattleManager.finish_battle()` 生成最终结果。
- `BattleScene` 使用 `apply = false` 的结果预览显示结果面板；返回大地图时执行最终结算。
- 战斗按战斗侧统计存活；一支部队全灭但同侧仍有部队时继续战斗；只剩一个有效战斗侧才结束。
- 同一场战斗只能结算一次，重复调用不会重复发经验/奖励。

### Step 2：玩家可操作角色

- 新增 `Data/Units/player_hero.tres`：HP 80 / 攻击 10 / 间隔 0.8 / 射程 30 / 移速 75。
- 玩家角色是普通 `UnitData`，使用 `is_player_character` 标记身份，属于玩家部队，参与存档。
- 新游戏玩家部队：3 民兵 + 3 名装备马匹的职业步兵 + 1 玩家角色（7 人；本阶段新增 2 名骑乘测试单位，见 8.1）。
- 战斗场景优先控制玩家角色；旧存档没有玩家角色时退化到第一名存活友军。
- WASD 移动，斜向归一化；速度读取 UnitData.move_speed。
- 鼠标左键攻击点击位置附近、且在攻击范围内的敌对单位；伤害/间隔/射程全部来自 UnitData。
- 攻击尝试进入冷却，不能快速点击绕过；玩家角色使用普通受伤/HP 规则。
- 玩家角色获得攻击闪光与金色控制圈；后续接入与普通士兵相同的 `UnitVisual` 部件表现。

### Step 3：队形与局部避让

- `FormationManager` 实现三种基础队形：
  - `INFANTRY_LINE`：横向展开，超过 5 列自动增加纵深；
  - `DEPTH`：单列纵深；
  - `LOOSE`：更大间距的松散网格；
  - 另保留方阵/弓手线/骑兵纵队接口。
- `BattleScene` 每 0.4 秒按部队刷新队形槽位：
  - 两军在中点附近列阵；
  - 同侧多支部队使用 lane 分区，避免全部聚集；
  - 阵亡单位不再占用槽位，存活单位重新分配。
- `UnitController` 使用队形槽位 + 局部分离力；进入攻击范围后停止推进并攻击。
- 邻居缓存每 0.3 秒构建一次，避免每个单位每帧遍历全场。
- 预留 `set_party_move_order()` / `set_party_formation()` 键盘部队指令接口。

### Step 4：控制权转移与观战

- 玩家控制单位被击败后停止输入，战斗场景本地暂停。
- 若同侧仍有存活友军，弹出控制权转移面板：姓名/兵种/等级/剩余 HP，可选择接管或观战。
- 接管只切换 `is_player_controlled` 与当前控制 ID，不复制单位、不重置 HP/经验/装备/冷却。
- 同一时间只有一个玩家控制单位。
- 观战后所有单位由 AI 控制，WASD/左键失效。
- 无存活友军时直接进入战败流程。

### Step 5：伤亡与经验

- 复用现有 `BattleUnitState` → `UnitData` 结算；阵亡单位移除归属并删除数据，存活单位写回 HP。
- 经验规则：存活 +10；获胜侧存活单位再 +20；阵亡 0；中止不发放；撤退仅基础经验。
- 通过 `UnitManager.add_exp()` 处理升级，`StatCalculator` 自动重算属性；当前 HP 不被升级重置。
- 同一战斗只发一次；中途加入按实际参战存活单位发放；离屏转屏幕不重复。

### Step 6：撤退、战败与结果面板

- 战斗场景新增“撤退”按钮：玩家侧主动撤退，显示“已撤退”，返回时按 `RETREATED` 结算。
- 撤退不会被记录为全员阵亡，存活单位写回 HP，不发胜利奖励。
- 结果面板显示：胜利/失败/平局/已撤退、各战斗侧名称、我方/敌方存活与阵亡、经验、金币与战利品。
- 玩家角色被击败但友军存活时不会直接判负；控制权转移后继续战斗。

### Step 7：战后奖励

- 仅玩家参与且玩家所在侧获胜时发奖励。
- 金币 = 50 + 敌方阵亡人数 × 5。
- 战利品从阵亡敌方单位装备中取最多 3 件唯一装备 ID。
- 奖励写入 `PlayerProfile.gold` / `inventory`，随 `player` 字典存档。
- NPC 对 NPC 离屏战斗不发玩家奖励，但参战 NPC 正常获得经验。
- 同一战斗只发一次。

### Step 8：结束与返回大地图

- `finish_battle()` 统一执行结果、经验、奖励、伤亡、部队解锁、暂停恢复与会话清理。
- 结果面板与返回大地图流程保持 `battle` 暂停，直到返回时结算。
- 控制权转移使用场景本地暂停，不使用 `get_tree().paused` / `Engine.time_scale`。
- 返回大地图后无残留 BattleSession、无残留暂停原因，大地图继续运行。
- 玩家档案与士兵经验/等级随存档保存；不改变 Schema 版本。

### 测试

- 新增 `formation_manager_test`：横队/纵深/松散/方阵站位、列数自动扩展。
- 新增 `battle_result_test`：胜负、伤亡、经验升级、金币/战利品、撤退、多方、离屏、中途加入、重复结算保护。
- 新增 `player_character_data_test`：玩家角色创建、身份持久化、玩家档案往返。
- 新增 `player_control_test`：WASD/斜向、攻击/冷却、受伤、控制权转移、观战、战败与结果面板。
- 新增 `battle_formation_test`：队形槽位、同队间距、多友军 lane 分区、阵亡重分配。
- 新增 `battle_side_result_test`：一支部队全灭但同侧存活时战斗继续；侧全灭后失败。
- 新增 `battle_retreat_test`：撤退按钮、结果面板、存活写回与无奖励。

## 8.1 阶段 5 后续优化

### 攻击判定

- 新增 `CombatRules`：存活、敌对、攻击者冷却、射程统一判断；玩家与 AI 共用。
- 有效射程 = `UnitData.attack_range + BODY_RADIUS × 2`（身体边缘距离）。
- 攻击冷却、当前目标、移动状态属于攻击者；不存在目标级攻击锁，多名单位可同时攻击同一目标并分别结算伤害。
- 玩家左键没有有效目标时不消耗冷却、不播放攻击；一次攻击只伤害一个目标。
- AI 状态：`SEEK / APPROACH / ATTACK`；射程外沿目标外围进攻点接近，进入射程后攻击，目标离开射程重新追击，目标死亡重新搜索。
- 攻击为即时命中，没有攻击前摇/受击硬直；受击表现不会阻塞其他攻击者。

### 临时美术与部件层级

- 新增 `PartVisual` / `HumanVisual` / `HorseVisual`：人物与马匹贴图分开管理，由 `UnitVisual` 统一组合。
- `VisualLayers` 集中定义最终前→后层级：武器 → 马头 → 缨饰 → 人头 → 人身体/罩袍 → 人右腿 → 马鞍/马身 → 人左腿 → 四条独立马腿 → 影子。
- 人体双腿始终创建；骑乘时由马身/马鞍按层级自然遮挡，不以 `visible = false` 隐藏。
- 人物影子/骑马影子互斥；步行显示人物影子，骑乘显示骑马影子。
- 骑乘时 `HumanVisual.position.y = -15`；马匹与 `UnitActor` 世界坐标不变。切换使用 `set_mounted()`，不重建节点。
- 长矛：48×96 素材，自身枢轴左下 `(24,18)`，身体锚点 `(33,18)` 映射到当前 48×96 画布 `(9,-14)`；攻击从竖直逆时针旋转到横向戳击（`-PI/2`），准备 0.10s、保持 0.12s、延迟 0.20s、恢复 0.20s；朝右由整体镜像指向目标。伤害仍即时结算。
- 修复：`UnitActor.z_index = 200`，高于战场背景；此前部件的相对负 z 被背景整张盖住，导致只剩血条/名称/选中圈。
- 阵营罩袍使用 `Shaders/faction_tabard.gdshader` 着色身体贴图蓝色区域；不同阵营颜色不同，不复制整套贴图。
- 当前没有独立缨饰/独立罩袍素材；`Plume` 插槽为空，缺失素材安全回退。
- 表现层不修改 UnitData、碰撞、攻击、移速或射程；玩家角色与普通士兵共用同一架构。

### 部队面板美术预览

- `UnitDetailPanel` 顶部新增独立 `SubViewport` 预览，复用 `UnitVisual`。
- 根据选中 `UnitData` 的真实阵营/骑乘状态显示步兵或骑兵外观；骑兵应用 15 像素上移与马匹部件。
- 预览不创建真实单位、不参与 AI/碰撞/攻击/移动，不修改 UnitData、库存或存档。
- 切换成员时复用同一预览节点并重建部件；旧部件释放，不累积节点。

### 骑兵系统

- 骑兵不是独立 `UnitConfig`：普通士兵装备 `MOUNT` 后即为骑乘状态。
- `UnitManager.equip_mount()` 从玩家物品栏消耗 1 匹马；`unequip_mount()` 返还；库存不足/重复装备失败且不改数据。
- `PlayerProfile` 新增物品数量（`inventory_counts`），`inventory` 列表保持兼容。
- `mount_horse_01` 当前移速 +25；`is_mounted` 由 MOUNT 装备派生。
- `StatCalculator.compute_effective_attack(unit, is_moving)`：骑乘移动时按最终移速增加攻击，`clamp(floor((move_speed - 60) × 0.1), 0, 5)`；停止移动归零，步兵为 0。
- 旧存档缺少 MOUNT/`inventory_counts` 时按步兵与 1 件物品兼容，不升级 Schema。
- 新游戏玩家部队 7 人：3 民兵 + 3 名骑乘职业步兵 + 玩家角色；测试马匹库存 3，全部消耗（本阶段新增 2 名骑乘测试单位）。
- 控制权转移列表与部队详情显示“骑乘”；骑乘单位与其他成员一样参与队形、战斗、经验和结算。

### 测试

- 新增 `combat_attack_rules_test`：三人围攻同一目标、玩家被围攻反击、步兵/骑兵混合攻击、独立冷却、单次单目标、玩家空点击不耗冷却、AI 射程/状态切换、骑乘移动加成与停止归零。
- 新增 `mounted_unit_test`：马匹库存消耗/返还、库存不足、重复装备、MOUNT 派生状态、骑乘属性、旧存档兼容、新游戏部队组成、存档往返。
- 新增 `unit_visual_test`：人物/马匹分组、最终层级、人体双腿保留、四条独立马腿、影子互斥、15 像素骑乘偏移、整体朝向、长矛枢轴/攻击/恢复动画、缺失缨饰回退、属性不变、UnitActor 集成。
- 扩展 `party_panel_test`：7 名成员、步兵/骑兵预览同步、预览不创建真实单位/不消耗马匹/不修改装备。
- 扩展 `battle_scene_test`、`player_control_test`、`battle_formation_test`、`milestone2_flow_test`、`party_dialogue_test`、`player_character_data_test`、`battle_retreat_test`、`battle_side_result_test`、`ai_encounter_flow_test` 覆盖 7 人玩家部队与 3 名骑乘单位。
- 扩展 `mounted_unit_test`：新游戏 7 人、3 名骑乘、马匹库存 3→0、读档一致。

## 8.2 阶段 5 · 移动/动画/碰撞/全向攻击优化

### 美术层级与动画

- `VisualLayers` 把四条独立马腿移到马身体之前：人右腿 → 马鞍 → 马腿 → 马身体 → 人左腿；其他部件层级不变。
- 步兵/骑兵待机与移动动画：
  - 人物 `UpperBody` 起伏/轻微倾斜；武器独立摇摆；跑动时双腿交替；
  - 马匹 `HorseBodyRig` 起伏、马头摆动、四条马腿独立相位运动；
  - 人物/马匹共享时间轴，影子稳定；
  - 实际位移速度 8 px/s 阈值、0.12s 状态缓冲、0.18s 混合；攻击动画优先。
- 长矛 360°方向旋转：攻击方向由攻击逻辑给出，人物整体镜像保证左右/斜向矛尖指向；伤害仍即时。

### 战斗移动与部署

- `BATTLE_MOVE_SPEED_MULTIPLIER = 0.6`：民兵 60→36、职业步兵 55→33、玩家角色 75→45；骑乘 +25 后 51/48/60。
- 大地图 `PartyData.movement_speed` 不受影响。
- `SPAWN_MARGIN_X = 220`（旧 300），双方质心间距约 786（旧约 680）；所有单位在战场边界内。
- 战斗相机 2 倍整数缩放、向下偏移 30；显示 960×540 战场区域。

### 1920×1080 显示

- `project.godot`：Viewport/窗口 1920×1080，Stretch 关闭，Aspect keep。
- 战斗相机 2 倍，大地图相机默认 1.5 倍；UI 位于 CanvasLayer，原生 1920×1080 布局。
- 实际截图验收：战斗、主菜单、部队管理面板、结果面板均无裁切；像素士兵在战斗中为整数 2 倍放大。

### 攻击系统

- 玩家攻击方向来自鼠标世界坐标；AI 方向来自攻击者→目标。
- `CombatRules` 使用 360°定向矩形：
  - 前向长度 = `attack_range + 26 + 6`；横向半宽 22；
  - 背后/宽度外/长度外目标排除；单次最多命中一个目标。
- 武器决定攻击距离：`EquipmentConfig.weapon_attack_range` 覆盖单位基础射程；`weapon_sword_01` 当前 14，默认长矛使用 UnitConfig（民兵 20 → 前向 52）。
- 玩家无有效目标不耗冷却、不播放有效攻击动画；命中时伤害与武器动画方向一致。
- 攻击方向/目标在开始时锁定，动画期间人物朝向锁定；AI 使用同一武器动画接口。

### 实体碰撞

- `UnitController.MIN_BODY_DISTANCE = 28`，每次 tick/player_tick 做 2 次最小间距推开。
- 与局部避让协同；死亡单位不参与；碰撞不改变伤害/攻击范围/队形目标。
- 多次测试验证友军/敌军/敌我重叠被推开，死亡单位不再阻挡。

### 测试

- 新增/扩展 `combat_attack_rules_test`：定向矩形、背后/横向/超距排除、玩家四方向、矩形内单目标、武器距离变化、实体碰撞。
- 扩展 `unit_visual_test`：待机/跑动、武器摇摆、双腿交替、马身/四腿动画、影子稳定、360°攻击方向、攻击优先。
- 扩展 `battle_scene_test`：初始部署距离、边界、2 倍相机、1920×1080 设置。
- 扩展 `stat_calculator_test`：武器射程覆盖与切换。
- 实际截图：`visual_probe_battle/close/move/attack_left/attack_up/attack_down/recover`、`visual_probe_party_foot/mounted`、`visual_probe_main_menu`、`visual_probe_result`。

## 8.3 阶段 5 · 战斗动作表现与攻击操作体验优化

> 本节记录第一轮参数；腿部振幅、马腿分组与长矛前后摇已在 8.4 二次优化中调整，以 8.4 为准。

### 步兵步态

- 左右腿改为同一振幅、相反相位的水平步态：`RUN_LEG_SWING_X = 4.0`、`RUN_LEG_LIFT_Y = 1.8`、`RUN_LEG_ROTATION = 0.10`。
- 只有前摆腿抬起并轻微旋转，后摆腿保持接地；不再出现一腿大幅上下、另一腿几乎不动或陷入地面的“瘸腿”效果。
- 待机时双腿平滑回到默认位置；影子、部件层级、骑乘显示与武器动画不受影响。

### 马匹动画

- 主要动态转移到马身整体：跑动起伏 `4.5`、周期 `0.50s`（与人物同步）、前后俯仰 `0.022 rad`、压缩/伸展 `0.018`。
- 四条马腿保留 0 / π / π/2 / 3π/2 相位差，但上下位移降至 `0.55 px`，改为轻微水平位移（`1.8 px`）+ 旋转（`0.06 rad`）。
- 马头保留独立摆动与起伏（`RUN_HEAD_SWAY = 0.05`、`RUN_HEAD_BOB = 0.8`）。
- 待机时马身轻微呼吸、马头小幅摆动，马腿位移仅 `0.10 px`，不会出现奔跑动作。
- 人物与马匹周期同步；骑乘人物仍保持 15 像素上移，锚点关系不变。

### 玩家自由攻击

- 鼠标左键无论攻击方向矩形内是否有敌人，都会播放完整长矛动画并进入 `attack_interval` 冷却。
- 有敌人时按 360°定向矩形选择一个目标造成伤害；没有敌人时伤害为 0，`get_last_attack_target_id()` 为空。
- `player_attack_at()` / `try_player_attack_at()` 的返回值改为“攻击动作是否释放”；冷却期间点击仍返回 false。
- AI 的目标锁定、接近与攻击流程不变。

### 长矛攻击后保持

- 动画阶段：准备 `0.10s` → 戳击 `0.12s` → 保持 `4.0s` → 平滑恢复 `0.35s`。
- 保持时间集中在 `HumanVisual.SPEAR_POST_ATTACK_HOLD_TIME`，可按 3–5 秒调整；`SPEAR_POST_ATTACK_DELAY` 保留为同义别名。
- 连续攻击在保持阶段立即重新触发并重置计时；移动/待机动画不会覆盖长矛主角度。
- 只有准备/戳击阶段锁定朝向，保持阶段允许移动和转身。

### 骑乘战斗速度

- 步兵保持 `BATTLE_MOVE_SPEED_MULTIPLIER = 0.6`。
- 新增 `BATTLE_MOUNTED_MOVE_SPEED_MULTIPLIER = 0.84`：民兵 85→71.4、职业步兵 80→67.2、玩家角色 100→84。
- 不修改 `UnitData.move_speed`、坐骑装备加成、骑乘冲锋加成或大地图 `PartyData.movement_speed`。

### 初始部署距离

- `BattleScene.SPAWN_MARGIN_X` 从 `220` 调整为 `160`，双方质心间距约 `906`（上一版约 786）。
- 所有单位仍在 1280×720 战场内；阵营内部队形、多部队 Party Lane 与 FormationManager 均未修改。

### 测试与截图

- 自动化通过：`unit_visual_test`、`combat_attack_rules_test`、`unit_controller_test`、`battle_scene_test`、`battle_formation_test`、`player_control_test`、`mounted_unit_test`。
- 非 headless 截图：`visual_probe_close/move/hold/recover/attack_left/attack_up/attack_down/legs_only`。
- 新增 `Tests/_debug/locomotion_probe`：以 5 倍比例输出步兵/骑兵跑步四相位与待机截图，便于人工检查腿部、马身与马腿动画。

### 未解决

- 仍为程序化 Sprite 动画，没有正式逐帧/骨骼动画。
- 空挥也会消耗冷却，这是有意的操作节奏；如果后续希望“空挥不耗冷却”，需要单独设计。
- 攻击后保持 4 秒是当前手感值，仍可能按正式美术继续调整。
- 马匹身体压缩/俯仰与骑手身体的相对关系仍靠周期同步，不是完整骑乘骨骼绑定。

## 8.4 阶段 5 · 士兵待机与战斗动作表现二次优化

> 本节记录上一轮参数；腿幅、马腿枢轴与马身跃动已在 8.6 中进一步调整，以 8.6 为准。

### 步兵腿部收敛

- 腿部参数从 `4.0 / 1.8 / 0.10` 降为 `RUN_LEG_SWING_X=1.5`、`RUN_LEG_LIFT_Y=0.6`、`RUN_LEG_ROTATION=0.04`。
- 保留左右腿等幅、反相运动与前摆抬起/后摆接地；腿部只作为辅助表现，身体起伏/倾斜仍是主要动态。
- 待机时双腿平滑回到默认位置，不播放跑步动画。

### 士兵待机动画与 UI 预览

- 步兵待机保留身体起伏 `0.8`、倾斜 `0.008 rad`、武器晃动 `0.02 rad`，新增头部独立微摆 `0.015 rad`。
- 骑兵待机沿用马身呼吸/重心变化、马头摆动与骑手同步；马腿基本静止。
- `UnitDetailPanel._process()` 直接调用 `UnitVisual.update_locomotion(delta, false)`，复用战斗动画逻辑：
  - 切换预览单位时调用 `reset_locomotion()`；
  - 面板不可见或没有预览单位时直接返回；
  - 步兵预览播放人物待机，骑兵预览播放马匹/骑手待机；
  - 不创建真实 UnitData、不参与战斗/AI，不累积预览节点。

### 跃马式马腿

- 两只前腿（`MountLegFront` / `MountLegFront2`）同组同相，两只后腿（`MountLegBack` / `MountLegBack2`）同组同相。
- 前腿组与后腿组相差 π：前腿向前伸时后腿向后伸，随后两组同步收缩；组内仅保留 `0.12 rad` 错位。
- 前后伸展 `3.5 px`、旋转 `0.09 rad`，上下位移仅 `0.25 px`；不再使用四条腿各自独立的正弦步态。
- 马身随伸展/收缩起伏 `4.5`、俯仰 `0.022 rad`、横向拉伸 `2%`、纵向压缩 `0.8%`；马头独立摆动。
- 停止移动后通过 `0.18s` 混合平滑回到待机，马腿前后位移归零。

### 长矛前摇与戳击

- 动画阶段：前摇 `0.14s` → 戳击 `0.14s` → 保持 `4.0s` → 恢复 `0.35s`。
- 前摇沿攻击方向反方向后移 `2.5 px`；戳击沿攻击方向前伸 `6.0 px`；由局部攻击方向计算，支持上下左右与斜向。
- 保持阶段同时维持攻击角度与前伸位置；恢复阶段位置与角度一起平滑回到 `BODY_WEAPON_ANCHOR`。
- 连续攻击重新开始前摇/戳击并重置保持时间；移动/待机不覆盖武器主角度。
- 伤害仍在攻击触发时即时结算；没有把伤害延后到戳击阶段，因此不存在前摇期间目标死亡/攻击者死亡导致的中断、无效伤害或重复结算。

### 测试与截图

- 自动化通过：`unit_visual_test`、`combat_attack_rules_test`、`unit_controller_test`、`battle_scene_test`、`party_panel_test`、`player_control_test`、`mounted_unit_test`。
- 非 headless：
  - `locomotion/run_1..4.png`：步兵移动与战马跃马四相位；
  - `locomotion/idle.png`：步兵/骑兵待机；
  - `visual_probe_attack_windup/thrust.png`、`visual_probe_hold.png`、`visual_probe_recover.png`：长矛前摇、戳击、保持、恢复；
  - `visual_probe_party_foot.png` / `visual_probe_party_foot_idle.png`、`visual_probe_party_mounted.png` / `visual_probe_party_mounted_idle.png`：部队 UI 待机动画前后对比。

### 未解决

- 仍为程序化 Sprite 动画，没有骨骼/逐帧资源。
- 长矛伤害仍即时结算；视觉前摇不代表伤害前摇。
- 马匹前后腿分组通过位移/旋转模拟，不是真实马匹生物力学；组内错位固定为 `0.12 rad`。
- UI 预览每次只推进当前选中单位；关闭面板后不再推进待机动画。

## 8.5 阶段 5 · 人物与战马腿部旋转中心修正

> 本节记录上一轮 3 px 修正；马腿枢轴已在 8.6 中累计调整为 6 px，人物腿仍为 3 px。

### 旋转机制

- 腿部由 `PartVisual._add_sprite()` 创建为 `Sprite2D`：`centered = false`、`offset = -anchor`。
- 默认锚点为脚底中心 `(w/2, h-4)`；Sprite 的节点原点就是旋转中心。
- 新增 `PartVisual.lower_part_pivot(part_name, drop_y)`：`offset.y -= drop_y`，同时 `position.y += drop_y`。
  - 贴图在画面中的可见位置保持不变；
  - 节点原点（旋转中心）在素材坐标中下移，实际旋转轴心向下移动。

### 最终偏移值

| 部件 | `LEG_PIVOT_DROP_Y` | 基础位置 | 结果 |
|---|---:|---|---|
| `LegLeft` / `LegRight` | 3.0 px | `(0, 3)` | 左右腿规则一致，可见位置不变 |
| `MountLegFront` / `MountLegFront2` | 3.0 px | y=3，x 由动画决定 | 前腿组规则一致 |
| `MountLegBack` / `MountLegBack2` | 3.0 px | y=3，x 由动画决定 | 后腿组规则一致 |

### 保持不变

- 人物腿部动画幅度、周期、等幅反相关系。
- 马腿前后成组、组内 `0.12 rad` 错位、前后伸展 `3.5 px`、旋转 `0.09 rad`、上下位移 `0.25 px`。
- 人物/马匹其他部件锚点、层级、骑乘 15 px 偏移、状态切换与 SubViewport 预览架构。
- 战斗规则、单位属性、装备与存档。

### 测试与截图

- `unit_visual_test` 新增断言：两条人物腿与四条马腿的基础位置补偿 3 px、贴图可见位置不变、`offset.y` 下移 3 px。
- `party_panel_test` 通过，确认部队 UI 步兵/骑兵预览动画未受影响。
- `locomotion_probe` 重新输出 `run_1..4` 与 `idle`：待机贴图位置与修正前一致，移动时腿部围绕更低轴心摆动。
- `party_preview_probe` 重新输出部队 UI 步兵/骑兵待机截图，无节点或状态异常。

### 未解决

- 仍是 Sprite2D 程序化旋转，没有骨骼/逐帧动画。
- 旋转中心偏移为全局固定 3 px；若正式素材替换，需要在 `PartVisual` 创建时重新核对锚点。

## 8.6 阶段 5 · 人马腿部动画幅度与战马整体跃动优化

> 本节记录上一轮参数；腿部挂载、Pivot 与局部动作已在 8.7 中进一步调整，以 8.7 为准。

### 马腿旋转中心

- `HorseVisual.LEG_PIVOT_DROP_Y` 从 `3.0` 调整为 `6.0`（累计：上一轮 3 px + 本轮新增 3 px）。
- 四条马腿统一调用 `lower_part_pivot(..., 6.0)`：`offset.y -= 6`、基础位置 y `+= 6`，贴图可见位置不变。
- 人物腿部旋转中心保持上一轮的 3 px，不再调整。

### 马腿动作收敛

| 参数 | 上一版 | 当前 |
|---|---:|---:|
| 前后腿水平伸展 | 3.5 px | 1.5 px |
| 腿部旋转 | 0.09 rad | 0.04 rad |
| 腿部上下位移 | 0.25 px | 0.10 px |
| 组内相位错位 | 0.12 rad | 0.12 rad（保留） |

- 前腿组同组同相、后腿组同组同相、前后组相差 π 的关系不变。
- 马腿只作为辅助表现，不再承担主要奔跑动态。

### 马身整体跃动

- 跑动起伏从 `4.5` 提高到 `5.6`（约 +24%）。
- 伸展阶段（`extension = 1`）马身整体向上，收缩阶段向下回落。
- 前后俯仰 `0.022 → 0.028 rad`；横向拉伸 `2% → 2.8%`；纵向压缩 `0.8% → 1.2%`。
- 马头独立摆动 `0.05 → 0.04 rad`、独立起伏 `0.8 → 0.55 px`，不超过身体整体运动；待机呼吸/摆头保留。
- 骑手跟随：
  - `UnitVisual` 先更新 `HorseVisual`，再读取 `get_body_offset_y()`；
  - 骑乘人物整体 `y = -15 + 马身偏移`；
  - 人物上半身独立起伏缩减为原来的 `20%`（`MOUNTED_RIDER_BOB_SCALE = 0.2`），避免双重弹跳；
  - 骑手不跟随马身缩放/俯仰，只跟随主要垂直跃动。

### 步兵腿部

| 参数 | 上一版 | 当前 |
|---|---:|---:|
| `RUN_LEG_SWING_X` | 1.5 px | 0.8 px |
| `RUN_LEG_LIFT_Y` | 0.6 px | 0.25 px |
| `RUN_LEG_ROTATION` | 0.04 rad | 0.02 rad |

- 左右腿保持等幅、反相；身体起伏/倾斜继续作为主要移动表现。

### 测试与截图

- 自动化通过：`unit_visual_test`、`mounted_unit_test`、`party_panel_test`。
- 新增/更新断言：
  - 马腿基础位置 y=6、贴图可见位置不变、`offset.y` 下移 6 px；
  - 骑手整体跟随马身、同步误差 `< 0.001`、跟随幅度覆盖主要跃动；
  - 骑手上半身独立起伏不超过 `0.6 px`；
  - 部队 UI 骑兵预览的骑手跟随马身。
- 非 headless：`locomotion/run_1..4` 与 `idle`、`visual_probe_party_foot*` / `mounted*` 重新渲染检查。

### 未解决

- 仍为程序化 Sprite 动画，没有骨骼/逐帧资源。
- 骑手只跟随马身垂直偏移，不跟随马身俯仰与缩放；当前幅度内相对位移很小。
- 6 px 枢轴偏移基于当前 48×96 素材，正式美术替换时需要重新校准。

## 8.7 阶段 5 · 人马腿部挂载关系与局部动画优化

> 本节记录上一轮参数；马腿局部幅度、骑兵整体起伏与影子响应已在 8.8 中调整，以 8.8 为准。

### 真实挂载关系

- 人物：
  - `UpperBody` 先创建，左右腿作为其子节点创建并应用 Pivot；
  - 腿部自动继承 `UpperBody` 的上下起伏、轻微倾斜与骑乘人物整体位移；
  - 腿部自身只叠加局部步态。
- 马匹：
  - `HorseBodyRig` 先创建，四条马腿作为其子节点创建并应用 Pivot；
  - 马腿自动继承马身的整体跃动、俯仰与缩放；
  - 马腿自身只叠加前/后组局部伸展与旋转。
- 两个父节点 `z_index = 0`，因此 `VisualLayers` 的最终遮挡顺序不变；影子仍保持在父级之外，不参与身体跃动。
- 每帧由父级设置整体变换，再设置腿部局部变换；所有值都是基于基准的绝对赋值，不做 Transform 累加，不会长期漂移。

### Pivot 实际修正

开发前核对代码后确认：

- 人物腿此前只实际应用过一轮 3 px（不是两轮）。
- 马腿此前已累计 6 px（3 + 3）。

因此本轮按“当前基础上再下移 3 px”执行：

| 部位 | 本轮前 | 本轮后 | 相对最初累计 |
|---|---:|---:|---:|
| 人物左右腿 | 3 px | 6 px | 6 px |
| 四条马腿 | 6 px | 9 px | 9 px |

- 通过 `PartVisual.lower_part_pivot()` 统一处理；`offset.y` 与基础位置补偿后，贴图可见位置不变。
- 没有重复应用本轮 3 px：`rebuild()` 只按累计常量调用一次。

### 局部动画参数

| 参数 | 上一版 | 当前 |
|---|---:|---:|
| 人物 `RUN_LEG_SWING_X` | 0.8 px | 0.2 px |
| 人物 `RUN_LEG_LIFT_Y` | 0.25 px | 0 px |
| 人物 `RUN_LEG_ROTATION` | 0.02 rad | 0.005 rad |
| 马腿前后伸展 | 1.5 px | 0.25 px |
| 马腿旋转 | 0.04 rad | 0.01 rad |
| 马腿上下位移 | 0.10 px | 0 px |

- 人物左右腿保持等幅、反相。
- 马腿保持前腿组/后腿组相反相位与 `0.12 rad` 组内错位。
- 马身整体跃动仍是主运动；骑手继续跟随马身垂直偏移。

### 测试与截图

- 自动化通过：`unit_visual_test`、`mounted_unit_test`、`party_panel_test`。
- 新增/更新断言：
  - 人物双腿父节点为 `UpperBody`，马腿父节点为 `HorseBodyRig`；
  - 人物腿部 `global_position` 随身体起伏变化；
  - 马腿 `global_position` 随马身跃动变化；
  - 人体腿部枢轴 6 px、马腿枢轴 9 px，贴图可见位置不变；
  - 局部摆动幅度上限与左右腿等幅关系。
- 非 headless：`locomotion/run_1..4` 与 `idle`、`visual_probe_party_foot*` / `mounted*` 重新渲染，检查身体与腿部是否作为整体运动。

### 未解决

- 仍为程序化 Sprite 动画，没有骨骼/逐帧资源。
- 骑手只跟随马身垂直偏移，不跟随马身俯仰/缩放。
- Pivot 偏移依赖当前 48×96 素材，正式美术替换时需要重新校准。

## 8.8 阶段 5 · 骑兵动画幅度调整与影子优化

### 马腿局部动作

| 参数 | 上一版 | 当前 |
|---|---:|---:|
| 前后腿水平伸展 | 0.25 px | 0.6 px |
| 腿部旋转 | 0.01 rad | 0.02 rad |
| 腿部上下位移 | 0 px | 0 px |

- 前腿组同组同相、后腿组同组同相、前后组相差 π 的关系不变。
- 马腿仍挂载在 `HorseBodyRig` 下，先继承身体整体变换，再叠加局部动作。

### 骑兵整体上下波动

- `RUN_BOB_AMPLITUDE`：`5.6 → 4.2`。
- 保留马身伸展/收缩、俯仰 `0.028 rad`、拉伸 `2.8%`、压缩 `1.2%`。
- 骑手继续跟随马身垂直偏移（`-15 + body offset`），没有脱节或双重弹跳。

### 骑马影子

- 不改变影子资源、层级与位置。
- 以马身当前垂直偏移计算 `lift_ratio = clamp(-body_y / RUN_BOB_AMPLITUDE, 0, 1)`。
- 抬高时：
  - `scale = 1 - lift_ratio × 0.04`（最多缩小 4%）；
  - `modulate.a = 1 - lift_ratio × 0.15`（最多变淡 15%）。
- 回落时恢复 `scale = 1`、`alpha = 1`；由平滑的 body offset 驱动，不产生跳动/闪烁。
- 影子位置保持 `Vector2.ZERO`，不参与身体变换或位移。

### 保持不变

- 人物腿部局部参数（`0.2 px / 0 px / 0.005 rad`）、枢轴 6 px。
- 马腿枢轴 9 px。
- 人物/马匹挂载关系、美术层级、骑手跟随、待机/攻击动画、部队 UI 预览架构。
- 战斗规则、单位属性、移动速度与存档。

### 测试与截图

- 自动化通过：`unit_visual_test`、`mounted_unit_test`、`party_panel_test`。
- 新增断言：
  - 骑兵整体起伏上限已降低；
  - 马腿局部伸展达到 `≥ 0.45 px`，比上一版更明显；
  - 影子抬高时缩小/变淡，回落时恢复；
  - 影子位置不变。
- 非 headless：`locomotion/run_1..4`、`idle`、`visual_probe_party_foot*` / `mounted*` 重新渲染检查。

### 未解决

- 影子只有缩放/透明度响应，没有轮廓形态变化。
- 仍为程序化 Sprite 动画，没有骨骼/逐帧资源。

## 8.9 阶段 6 · 村庄场景、交互与部队管理系统

### 村庄小场景

- `SettlementData.scene_path`：三个初始村庄均关联 `res://Scenes/Village/village.tscn`；城镇/城堡为空。
- 大地图地点面板对村庄增加“进入村庄”；`WorldMap.enter_village()` 校验类型与场景、记录进入前倍率、压入 `small_scene`、释放 `ui_panel` 后切换场景。
- 返回大地图时写入 `GameManager.pending_settlement_latch_id`，新大地图实例消费并记录当前村口村庄；地点面板不再自动打开，必须由玩家主动点击地点。
- `VillageScene` 只读取 `WorldContext`：玩家角色直接复用 `UnitData` / `UnitVisual`；村庄头人使用运行时 `UnitData`（不注册进 `UnitManager`）。
- 进入村庄调用 `UnitVisual.set_weapon_visible(false)`，只隐藏本次场景的武器 Sprite，不修改 `UnitData.equipment`。
- 村庄移动 WASD，速度 = `UnitData.move_speed × 2.0`；固定 1920×1080 场景与相机。
- 可活动区域 `(110, 300, 1700, 700)`；越界超过 8 px 开始 5 秒倒计时，回到区域内取消，连续越界 5 秒返回大地图。
- 村庄头人：点击半径 46 px、交互距离 130 px；距离不足不打开对话；对话期间禁止移动。
- 对话 UI 固定在屏幕下方，显示 NPC 名称、文本和选项；数据来自 `Data/Dialogues/village_elder.tres`，文本支持 `{village_name}`。
- 当前只有一个选项“谢谢你，我要走了”；选择后关闭对话并恢复移动。

### 大地图遭遇与部队 UI

- `PartyData.focus_party_id`（运行时）记录玩家主动追逐/接近目标：
  - 有效目标（移动中或静止）进入 `FOLLOW_PARTY`；仅战斗中/失效/空部队退回普通 `MOVE`（D088）；
  - 焦点非空时跳过无关部队普通对话与“接近离屏战斗”面板；地点面板始终只由点击打开；
  - 敌对 AI 主动追击玩家的遭遇不受影响，可以打断玩家行动；
  - 到达、停止或目标失效后清理焦点，恢复原交互。
- `PartyIcon` 不再显示部队名称，只显示 `member_unit_ids.size()`；人数变化同步刷新。
- 新增 `PartyHoverPanel`：鼠标悬浮 30 px 内显示部队名称与成员构成；按兵种 + 骑乘状态合并，玩家角色单独显示；面板 `mouse_filter = IGNORE`，不拦截地图操作。
- 大地图顶栏只显示“年月日 + 时间段 + 倍率”，不再显示小时/分钟。

### 世界时间

- 新游戏从 1103 年 1 月 1 日 00:00（深夜）开始。
- 1x：现实 6 秒 = 1 游戏小时，144 秒 = 1 游戏日；2x 翻倍，暂停停止。
- 简化历法：每月 30 天、每年 12 个月；日期全部由 `world_elapsed_seconds` 换算。
- 时间段集中配置：清晨 5–7、上午 7–12、下午 12–17、黄昏 17–19、夜晚 19–23，其余深夜。

### 背包、金币与工资

- 共享背包仍为 `PlayerProfile`；新增 `ItemConfig` / `ItemManager` 管理 `Data/Items/` 消耗品。
- `add_gold()` 只接受正数；`can_afford()` / `spend_gold()` 防止金币为负。
- 马匹从背包装备/卸下，数量扣除与返还；`is_mounted` 仍由 MOUNT 派生。
- 三级兵种：民兵 10/50、职业步兵 20/100、小贵族 25/180；工资 2/5/10。
- `UnitData.wage` 持久化；旧存档缺失时按当前 tier 配置补全；上下马不改变工资。
- `PartyManager.get_total_wage()` 统计部队每日工资；部队面板显示金币与总额。
- 晋升：`UnitManager.promote_tier()` 消耗 `promotion_rank_token`，保留等级/经验/装备/骑乘，切换 tier 与工资并重算属性。
- 部队面板新增坐骑下拉、装备/卸下、晋升按钮与状态提示。

### 测试与结果

- 新增 `unit_tier_wage_test`：三级配置、工资、上下马、晋升成功/失败/回滚、旧存档工资迁移、金币、存档往返。
- 新增 `time_calendar_test`：起点、6 秒/小时、144 秒/天、30 天/月、360 天/年、时间段、1x/2x/暂停。
- 新增 `village_scene_test`：玩家权威数据、无武器表现、距离交互、对话关闭与移动、越界倒计时/取消/返回请求。
- 新增 `village_flow_test`：New Game → 大地图 → 村庄 → 对话 → 越界 5 秒 → 大地图 → 主菜单。
- 新增 `world_map_milestone6_test`：日期/时间段、人数图标、悬浮构成、人数更新、追逐保护与主动交互恢复。
- 新增 `party_economy_ui_test`：金币/工资显示、上马/下马、晋升 UI 与工资总额更新。
- 受属性调整影响，更新 `unit_manager_test`、`stat_calculator_test`、`unit_party_serialization_test`、`mounted_unit_test`、`battle_result_test`、`party_panel_test`、`combat_attack_rules_test`、`unit_controller_test`、`battle_manager_test`。
- 回归通过：士兵/部队/战斗/遭遇/大地图/存档/流程测试（详见第 9 节本次执行记录）。

### 明确未实现

- 村庄商店、招募、任务、好感度与声望。
- 城镇/城堡独立小场景；村庄碰撞、城门与出口通道。
- 工资定期扣除、士气、逃兵。
- 背包容量/重量、完整物品栏 UI、装备商店。
- 复杂对话树、条件/效果命令表。
- 完整经济循环、动态物价与晋升凭证正式来源。

## 8.10 阶段 6 · 大地图战斗与小地图视角优化

### 小场景摄像机

- 新增 `Scripts/Systems/Scene/scene_camera_rig.gd`，村庄与战斗共用：
  - 统一视野 `VIEW_SIZE = 960×540`；1920×1080 下 2 倍缩放；其他分辨率按相同世界区域换算。
  - 默认平滑跟随当前玩家控制单位；战斗控制权转移后自动跟随新单位；观战保持当前位置。
  - `F` 切换自由视角；WASD/方向键移动镜头，不移动角色；切回跟随时重新定位。
  - 跟随/自由模式都限制在村庄 `1920×1080` 或战场 `1280×720` 边界内；场景小于视野时居中。
  - 每个小场景只保留一个活动 `Camera2D`。
- 村庄摄像机从固定整图视角改为跟随玩家；战斗摄像机保持 2 倍整数像素缩放。

### AI 对 AI 离屏战斗

- 现有实现没有创建独立小地图战斗场景，而是使用 `BattleSession` 数据模拟；本阶段继续沿用并替换结算模型。
- 新增 `OffscreenBattleConfig`（`Data/Combat/offscreen_battle_default.tres`）与 `OffscreenBattleResolver`。
- 每 1 个游戏小时（6 世界秒）结算一次伤亡：
  - 单兵战力 = 攻击、最大生命、tier、骑乘状态、剩余生命比例综合；
  - 战斗侧压力 = 敌方总战力 / 双方总战力；
  - 伤亡比例 = 基础比例 × 压力系数 × ±30% 随机波动；
  - 小数伤亡累计，低战力单位更易阵亡；
  - 伤亡不超过存活人数，HP 不为负；
  - 阵亡单位立即从部队成员列表移除，UnitData 保留到最终结算。
- 一方全灭、平局或 48 小时上限时统一 `finish_battle()`：写回 HP、移除阵亡、经验/奖励、解锁部队，禁止重复结算。
- 玩家可在世界时间推进中观察战斗人数变化，并在结束前加入；加入后转换为屏幕战斗，保留已有伤亡与剩余 HP，不再执行离屏小时结算。
- 每次小时结算广播 `battle_participants_updated`。

### 追击接触修复

- `EncounterManager` 的遭遇意图新增“玩家主动追击”：`player.focus_party_id == 对方 party_id`。
- 双方敌对且距离 <= 50 时，即使目标同向移动，也立即触发一次接触；不要求目标停下。
- 接触后立即停止双方、清除移动目标/跟随/焦点/攻击意图；随后通过 `encounter_dialogue` 暂停世界并显示面板。
- 遭遇面板新增“撤退”：清理待处理遭遇、恢复基础倍率、记录 90 世界单位拒绝锁；双方保留停止位置，AI 可继续行动。
- 拒绝锁范围内同一敌人不重复触发；离开范围后可再次触发；异常关闭只清理本次暂停。

### 大地图战斗 UI

- 新增 `BattleMarker`：每场 `BattleSession` 只创建一个标记，位于 `session.world_position`。
- 战斗期间隐藏参战部队 `PartyIcon`，未参战部队保持显示；战斗结束恢复。
- 新增 `BattleSummaryPanel`：
  - 按 `side_index` 分组，同侧多支部队并列；不同侧之间显示分隔线；
  - 每支部队按兵种 + 骑乘状态汇总存活人数；
  - 支持动态新增第三方；
  - 每次小时结算、加入、结束自动刷新；
  - 只读 `BattleSession` / `BattleUnitState`，不修改数据。

### 测试

- 新增 `small_scene_camera_test`：统一视野、跟随、自由视角、边界、切回跟随、村庄实际场景。
- 新增 `offscreen_battle_hourly_test`：1 小时门槛、双方伤亡、tier 影响、人数不为负、玩家加入保留伤亡、转换后停止离屏结算、全灭结束。
- 新增 `player_pursuit_encounter_test`：同向追击接触、停止与清除目标、暂停/面板、撤退、拒绝锁、重新触发与进入战斗。
- 新增 `world_map_battle_marker_test`：单标记、图标隐藏、按战斗侧汇总、小时伤亡刷新、新部队加入、结束恢复。
- 更新 `battle_scene_test` 统一视野断言、`player_control_test` 摄像机跟随/自由视角断言、`player_encounter_test` 战斗/撤退按钮；旧离屏结算测试改为按小时推进。

## 8.11 阶段 6 · 世界日志、美术层级与战斗表现优化

### 世界日志

- 新增 `WorldLogEntry`（事件类型 / 世界时间 / 时间文本 / 显示文本 / 元数据）与 `WorldLogManager`。
- `WorldLogManager` 监听 EventBus 事实生成日志：
  - 战斗开始与结束（胜负/平局/撤退/中止）；
  - 被消灭部队；
  - 玩家遭遇；
  - 进入/离开村庄。
- `add_event()` 提供其他世界事件扩展接口；最多保留 100 条，超出移除最早记录。
- 新增 `EventBus.settlement_entered` / `settlement_exited`，由大地图与村庄场景在场景切换成功后广播。
- 大地图左下角新增固定 `WorldLogPanel`：世界日志标题、时间 + 文本、滚动区域、自动滚动到最新。
- 面板使用 `MOUSE_FILTER_PASS`，不永久吞掉地图点击；日志文本不拦截输入。
- `to_dict/from_dict` 已实现，作为后续存档持久化预留；本阶段不写入存档。

### 角色美术

- `VisualLayers` 拆分左右手武器层级：
  - 右手武器 `RIGHT_HAND_WEAPON = -10`（保留 `WEAPON` 别名）；
  - 左手武器 `LEFT_HAND_WEAPON = -45`，低于马头，避免骑兵盾牌遮挡马头。
- 新增独立 `LeftHandWeaponPivot`；右手长矛枢轴、动画、位置与旋转中心不变。
- 人物 `Head` 与装备 `Helmet` 分离：
  - 头盔位于人头之前、缨饰之后；
  - 未装备头盔时只显示 Head；
  - 头盔是独立 Sprite2D，不替代头部节点。
- `EquipmentConfig` 新增 `visual_texture_path` / `visual_layer` / `visual_anchor`；
  - `UnitVisual.setup(unit, {slot_name: EquipmentConfig})` 按装备槽注入视觉；
  - BattleScene、VillageScene、部队预览均已传入当前装备视觉配置。
- 当前无正式头盔/盾牌贴图，路径为空时安全跳过；接口已完成。

### 大地图遭遇

- `_check_party_interaction()` 不再按距离扫描全部中立/友方部队；只有 `focus_party_id` 指向的主动点击目标才打开普通对话。
- 普通寻路、追击目标途中路过中立或无关部队不会弹窗或暂停。
- `_update_focus_state()` 在到达目标附近时保留焦点，供主动对话打开；远离/失效后清除。
- `EncounterManager` 自动遭遇仍要求阵营敌对 + 实际追击关系：
  - 敌对 AI `attack_intent` 指向玩家并追上；
  - 或玩家主动点击并追击敌对目标（显式交互）；
  - 无关敌对部队仅靠近不会打断玩家。
- 同一追击关系只触发一次；撤退与 90 世界单位拒绝锁保持不变。

### 战斗单位 UI

- `UnitActor` 拆分独立 `UnitHealthBar` 与 `NameLabel`。
- 满血或死亡时隐藏生命条；受伤后显示；恢复满血后重新隐藏。
- 头顶名称只对玩家当前控制的单位显示；普通士兵（含友军/敌军）隐藏名称，控制权转移时即时更新。
- 名称与生命条独立控制，隐藏名称不影响生命条显隐。
- 满血判定使用实际 HP / 最大 HP 与浮点容差；不再在 `UnitActor._draw()` 中绘制血条。

### 测试

- 新增 `world_log_manager_test`：事件类型、战斗/胜负/消灭/遭遇/地点文本、扩展事件、上限与序列化。
- 新增 `world_log_ui_test`：左下角固定面板、事件自动刷新、滚动、地图移动不受阻挡。
- 新增 `neutral_party_interaction_test`：路过中立不弹窗、追击不被无关目标打断、主动点击对话、AI 追击遭遇与防重复。
- 扩展 `unit_visual_test`：左右手层级、头部/头盔独立、装备视觉注入、名称/生命条独立、满血隐藏、普通士兵名称隐藏与控制权切换。
- 更新 `party_dialogue_test`、`world_map_input_test`、`world_map_milestone6_test`、`milestone2_flow_test` 以匹配“主动点击后才自动对话”。

## 8.12 阶段 6 · 家族领袖、NPC 部队与地图表现系统

**状态：** 完成（2026-11-21）

### 家族与外观

- 新增 `FamilyConfig` / `FamilyRegistry` / `Data/Families/*.tres`：巴里家族、墨西西家族；包含旗帜、主/副色、主/副罩袍、领袖缨饰与家族长矛。
- 新增 `AppearanceConfig` / `Data/Appearance/appearance_config.tres`：1/2/3 级头盔池与罩袍概率。
- `UnitData` 新增 `family_id`、`appearance`；`UnitAppearance` 在创建时一次性生成并持久化最终资源路径。
- 头盔按 `tier` 随机；罩袍主/副概率 20% / 50% / 100%；三级与领袖始终主罩袍；无副罩袍回退主罩袍。
- 领袖显示家族缨饰；家族长矛为可选表现；装备 `HEAD` / `WEAPON` 视觉优先。
- `UnitVisual` / `HumanVisual` 只消费结果，不硬编码家族规则。

### 部队、领袖与地点

- 新增两支家族骑士：巴里骑士、墨西西骑士，各 10 人，`FACTION_LOCAL`，专属巡逻点，由现有 `AIManager` 控制。
  编制：1 领袖（三级）+ 1 骑乘侍从（三级）+ 3 骑乘军士（二级）+ 2 军士（二级）+ 3 步兵（一级）。
- 新增两支强盗：东路强盗、荒野强盗；独立出生点、路线与部队 ID。
- `PartyData` 新增 `family_id`、`leader_unit_id`、`ai_patrol_points`；`PartyManager.get_leader_unit()`。
- 玩家身份、当前控制、部队领袖、部队归属保持四个独立概念；玩家部队领袖指向 `player_hero`。
- 村庄重命名为巴里、墨西西，并记录 `family_id`；北境村、灰石城堡不变。
- 新增 `world_log` 不受影响；读档不重复生成新部队。

### 地图表现与速度

- `PartyIcon` 改为圆形标记，家族旗帜等比缩放放入圆内；尺寸/边框/旗帜/人数位置由 `PartyMarkerStyle` 集中配置。
- 地点名称迁移到固定屏幕 UI 层 `SettlementNameTag`，名称左侧显示圆形家族旗帜；文字不随相机缩放，标签不拦截鼠标。
- `WorldMapManager` 统一将大地图实际速度乘以 0.5；`PartyData.movement_speed` 与战斗移动速度不变。

### 测试

- 新增 `family_appearance_test`：家族配置、两村改名、两队 10 人编制、领袖/成员关系、外观池与概率、装备优先级、序列化、旧存档默认值、统一速度倍率。
- 更新：`milestone1_test`、`milestone1_restart_test`、`milestone2_flow_test`、`unit_party_serialization_test`、`world_map_milestone6_test`。
- 通过：`family_appearance_test`、`unit_visual_test`、`milestone1_test`、`milestone1_restart_test`（save/load）、`milestone2_flow_test`、`world_map_input_test`、`world_map_milestone6_test`、`party_dialogue_test`、`neutral_party_interaction_test`、`ai_manager_test`、`unit_party_serialization_test`。
- 未执行无关的全量测试；未做非 headless 截图验收。

### 明确未实现

- 家族外交/战争、领袖关系/任务、招募 UI、玩家家族创建/编辑、家族盾牌、家族领地。
- NPC 领袖管理 UI、家族旗帜资源缺失时的专属阵营旗帜美术（当前使用颜色回退）。

## 8.13 阶段 6 后续 · 统一大地图部队架构与遭遇交互

### 部队架构

- `PartyData` 新增持久化字段 `control_type`（PLAYER / AI）、`party_kind`（GENERIC / PLAYER / FAMILY / MERCHANT / BANDIT / GUARD）与 `banner_texture_path`。
- 玩家、家族、盗贼、商队、治安队继续共用 `PartyData` / `PartyManager` / `WorldMapManager` / `AIManager` / `BattleManager`；未新增任何按类型拆分的管理器或标记节点。
- `AIManager` 只调度 `control_type == AI` 的部队；`party_kind` 不参与移动、成员、战斗、结算流程。
- 普通 NPC 部队在初始化时设置 `leader_unit_id`，领袖名称沿用部队名。
- 旧存档缺失新字段时由 `PartyManager.apply_runtime_defaults()` 按 `player_party_id`、阵营、家族与 `ai_type` 推断；不修改成员、位置、路线或已有明确类型。

### 大地图标记

- `PartyMarkerStyle` 标准半径 18 → 26，边框 3、旗帜最大边长 56、阴影与人数位置同步放大（该尺寸已在 8.14 恢复为 18/30；村庄标记改为独立放大）。
- 所有部队共用 `PartyIcon`；旗帜优先 `PartyData.banner_texture_path`，为空回退家族旗帜；无家族色时按阵营读取回退色。
- `map_flag_circle.gdshader` 新增 `uv_radius`，旗帜可大于内径并在边框内缘裁掉四角，不覆盖外圈边框。

### 遭遇 UI 与规则

- `PartyDialoguePanel` 与 `PlayerEncounterPanel` 迁移到屏幕下方：左侧领袖头像/剪影，右侧姓名、阵营、兵力、对白与选项。
- `EncounterPortrait` 复用 `UnitVisual`；无有效领袖时绘制安全默认头肩剪影。
- `EncounterManager` 记录 `EncounterReason`：`PASSIVE_ENCOUNTER` / `PLAYER_INITIATED` / `ENEMY_PURSUIT` / `OTHER`。
- `ENEMY_PURSUIT`（敌对 AI 主动追击并成功拦截）隐藏并禁用离开选项，`decline_player_encounter()` 同步拒绝；玩家主动接近仍保留离开。
- 对白来自 `EncounterTextConfig`（`Data/Encounters/encounter_text_config.tres`），按遭遇原因与部队类型选择，UI 不硬编码文本。

### 测试

- 新增 `party_architecture_test`：统一字段、类型/控制权、NPC 领袖、序列化往返、旧存档默认值与类型推断、读档不重置位置/成员/领袖。
- 新增 `encounter_dialogue_ui_test`：统一标记尺寸、底部布局、领袖头像、无领袖默认剪影、敌对追击无离开、玩家主动接近保留离开、配置文本。
- 更新：`player_encounter_test`（ENEMY_PURSUIT 选项与布局）、`neutral_party_interaction_test`（敌对追击禁离开、普通对话底部布局）。
- 通过：`party_architecture_test`、`encounter_dialogue_ui_test`、`player_encounter_test`、`neutral_party_interaction_test`、`player_pursuit_encounter_test`、`party_dialogue_test`、`party_manager_test`、`unit_party_serialization_test`、`ai_manager_test`、`ai_encounter_flow_test`、`world_map_milestone6_test`、`world_map_input_test`、`milestone1_test`、`milestone2_flow_test`。
- 未执行无关的全量测试；未做非 headless 截图验收。

### 明确未实现

- 完整 NPC 对话树、好感度、家族外交与联盟。
- 交涉/缴赎等额外遭遇选项；当前只保留战斗与按原因生成的离开规则。
- 遭遇 UI 的复杂动画与配音。

## 8.14 阶段 6 后续 · 村庄表现、玩家扩编与小地图战斗集群

### 大地图村庄与部队标记

- `PartyMarkerStyle` 恢复半径 18、边框 2、旗帜 30、人数偏移 24；所有部队类型重新使用扩编前尺寸。
- `SettlementIcon` 只对村庄使用放大圆形标记：半径 32、旗帜 76，旗帜超出内径部分由 `map_flag_circle.gdshader` 裁剪；城堡保持原建筑绘制。
- 村庄点击继续由 `SETTLEMENT_CLICK_RADIUS = 45` 判定，不随绘制尺寸改变。
- `SettlementNameTag` 改为纯文本、水平居中，位于圆形标记正上方；间距由标记半径 × 相机缩放 + 10 屏幕像素计算，文字尺寸固定，标签不拦截鼠标。
- 每个名称标签仍按 `settlement_id` 独立创建，同名村庄不会合并。

### 玩家初始部队

- 新游戏玩家部队扩编为 12 人：1 玩家角色 + 5 民兵 + 6 职业步兵，其中前 4 名职业步兵装备马匹。
- 人数与骑乘数量集中在 `WorldInitializer.PLAYER_MILITIA_COUNT`、`PLAYER_TRAINED_COUNT`、`PLAYER_MOUNTED_TRAINED_COUNT`、`PLAYER_TOTAL_MEMBER_COUNT`。
- 所有新增成员继续经 `UnitManager.create_unit`、`PartyManager.add_member` 与统一外观初始化；不新增骑兵兵种。
- 马匹库存为 5：4 匹装备、1 匹留在背包；旧存档已有成员时不补兵、不重复生成。

### 小地图战斗部署与集群

- `BattleScene.SPAWN_MARGIN_X` 调整为 90，`INITIAL_DEPLOYMENT_DISTANCE = 1100`；双方阵线分居左右，质心距离约 1040，全部位于 1280×720 内。
- `_update_formations()` 改为双方各自半场列阵：阵线中心为己方质心向前推进，双方前排保留 `SIDE_LINE_GAP = 90`，不再共享中点。
- 双方质心距离 ≤ `CONTACT_DISTANCE = 220` 后队形间距 × 1.35 放松；步行间距 40、骑乘 56。
- `BattleScene` 每 0.3 秒统计每个战斗侧的目标占用；`UnitController` 按“距离 + 占用惩罚”选择目标，已进入攻击范围时不重新索敌。
- 接近目标时远距离参考队形槽位方向，距离 ≤ 140 后按当前包围角度接近并带 ±10 切向偏移；友军分离半径 44、敌军 34。
- 未新增单位移动管理器，继续复用 `FormationManager` 与 BattleScene 周期缓存。

### 测试

- 新增 `player_party_expansion_test`：12 人编制、完整 UnitData、兵种/骑乘数量、领袖、马匹库存、存档往返不丢失或重复生成。
- 新增 `battle_cluster_test`：初始部署距离、边界、双方半场槽位、接近/接敌后无严重重叠、局部拥挤上限、目标分流与纵深分布。
- 更新：`world_map_milestone6_test`（村庄标记尺寸/旗帜/名称上方）、大量玩家兵力断言改用 `PLAYER_TOTAL_MEMBER_COUNT`、`mounted_unit_test` 与 `unit_tier_wage_test` 的编制派生值。
- 通过：`player_party_expansion_test`、`battle_cluster_test`、`battle_scene_test`、`battle_formation_test`、`battle_retreat_test`、`battle_side_result_test`、`milestone2_flow_test`、`party_panel_test`、`party_dialogue_test`、`player_control_test`、`world_map_milestone6_test`、`encounter_dialogue_ui_test`、`player_encounter_test`、`neutral_party_interaction_test`、`player_pursuit_encounter_test`、`ai_encounter_flow_test`、`milestone1_test`、`milestone1_flow_test`、`world_map_input_test`、`village_flow_test`、`village_scene_test`、`party_architecture_test`、`unit_party_serialization_test`、`ai_manager_test`、`faction_vision_test`、`world_map_battle_marker_test`、`world_log_ui_test`、`mounted_unit_test`、`unit_tier_wage_test`、`player_character_data_test`、`unit_controller_test`、`formation_manager_test`。
- 未执行无关的全量测试；未做非 headless 战斗观感/截图验收。

### 明确未实现

- 显式攻击槽位分配、等待/换位策略、寻路与复杂军事战术。
- 阵型编辑 UI 与完整战术指挥。
- 集群参数仍为集中常量，需实机观察后微调（KI404）。

## 8.15 战斗占用提示修复

### 问题

- `BattleManager` 全局只允许一场战斗。NPC 对 NPC 的离屏战斗进行时，玩家与无关部队发起战斗会被 `start_battle` 拒绝。
- 普通部队对话只知道“双方有兵/同阵营”，没有读取 `current_battle`，因此按钮仍可点击，点击后只显示笼统的“无法开始战斗”，真实原因仅在控制台警告中。

### 修复

- `_open_party_dialogue()` 会读取当前战斗：
  - 点击方是当前战斗参战方且 `can_party_join(玩家)` 成立 → 按钮文本改为“加入战斗”；
  - 点击方与当前战斗无关 → 禁用按钮并显示“世界上已有另一场战斗正在进行，暂时无法另开战场”；
  - 点击方属于当前战斗但玩家无法加入 → 显示“对方正在战斗中，靠近战场后可加入战斗”或“对方正在战斗中，暂时无法开战”。
- 目标 `IN_BATTLE` / `RETURNING` / `DISABLED` 和玩家自身不可参战时显示对应状态，不再复用同一句模糊提示。
- `begin_battle_with_party()` 增加同样的分支；即使绕过按钮直接调用，也会拒绝并在面板内写明原因。
- 加入路径复用 `BattleManager.try_join_battle()`，不新建战斗；成功后的暂停顺序仍为“先压入 battle，再移除 ui_panel”。
- `BattleManager` 的“一场战斗”规则未改变；本修复只解决提示与入口问题。

### 测试

- 新增 `battle_occupancy_ui_test`：离屏战斗占用时独立部队按钮禁用且原因明确；绕过按钮直接调用同样被拒绝；参战方按钮变为“加入战斗”，加入后复用同一会话并切换为屏幕战斗。
- 回归通过：`party_dialogue_test`、`encounter_dialogue_ui_test`、`world_map_milestone6_test`、`player_encounter_test`、`ai_encounter_flow_test`。

## 8.16 阶段 6 后续 · 大地图表现、AI 战后恢复、存档与战斗 UI

### 村庄与名称

- `SettlementIcon` 恢复原始村庄/城堡世界美术，仅负责世界层绘制；位置、缩放与点击判定不变。
- `SettlementNameTag` 改为固定 240×36 的屏幕层组合：左侧圆形家族徽章 + 右侧名称，整体位于地点美术上方并水平居中。
- 徽章读取 `SettlementData.family_id` 对应的 `FamilyConfig`；无家族地点隐藏徽章。名称与徽章都不拦截鼠标。

### AI 战后恢复

- `PartyData.engagement_cooldown_until` 为运行时字段：战斗结束后的存活部队获得 30 世界秒冷却，期间不重新追击、不响应/创建战斗。
- `BattleManager._unlock_session_parties()` 只清理战斗目标、攻击意图、焦点与指令，不把移动目标重置到当前位置。
- `AIManager` 的强盗/治安队冷却结束后恢复游荡或巡逻；`EncounterManager` 跳过冷却中的敌对组合，避免同一对手逐 tick 重复开战。
- 两方与多方战斗共用同一解锁流程；结算后 `current_battle` 清空，战斗标记与汇总列同步清理。

### 存档持久化

- `SaveData.CURRENT_SCHEMA_VERSION` 升级为 3，新增 `world_log`；`WorldContext` 保存/恢复世界日志。
- 读档时 `PartyManager.sanitize_loaded_runtime_state()` 清理运行时字段：`attack_intent`、`focus_party_id`、战斗冷却；无活动战斗时 `IN_BATTLE`/`RETURNING` 回落为 `AVAILABLE`（无成员则 `DISABLED`）；失效追击目标与 `FOLLOW_PARTY` 指令被清除。
- `PartyData.from_dict()` 对战斗/移动/指令枚举做范围校验；`validate_membership_consistency()` 增加领袖必须属于本部队且单位存在的校验。
- 战斗会话仍不写入存档；保存期间有活动战斗仍被 `GameManager.save_game()` 拒绝。

### 战斗结果与汇总 UI

- 玩家获胜时结算数据立即生成，结果面板延迟 `VICTORY_RESULT_DELAY = 3.0` 物理秒展示；失败、撤退、平局保持即时。
- 计时只使用战斗场景 `_physics_process(delta)`，不使用世界时间；场景退出时随节点销毁安全取消；`_result_shown` 防止重复展示。
- 大地图战斗汇总改为 `HBoxContainer` 多列：每个 `side_index` 一列，同侧部队在列内纵向排列，第三侧起自动扩展列与面板宽度；战斗结束移除所有列。

### 悬浮信息

- 默认只显示部队名称；按住左 Alt 时显示总人数、按兵种/骑乘分组的构成。
- `world_map._input()` 集中处理左 Alt 的按下/松开与 echo，右 Alt 不触发；不标记事件已处理，不影响点击与数字键。
- 模式切换立即重建当前悬浮面板，无需移动鼠标；松开左 Alt 立即恢复简单模式。

### 测试

- 新增 `save_persistence_test`：世界/时间/地点/部队/士兵/经济/世界日志往返、战后状态、失效战斗清理、领袖校验。
- 新增 `battle_result_delay_test`：胜利延迟、数据立即生成、失败即时、延迟期间退出、无重复展示。
- 更新 `world_map_battle_marker_test`（三方战斗三列与结束清理）、`world_map_milestone6_test`（村庄原始美术、徽章位置/家族、左 Alt 输入）、`battle_scene_test`/`milestone2_flow_test`/`multi_party_battle_test`（测试内关闭胜利延迟）。
- 回归通过：`party_manager_test`、`unit_party_serialization_test`、`party_architecture_test`、`family_appearance_test`、`world_log_manager_test`、`battle_manager_test`、`battle_result_test`、`ai_manager_test`、`offscreen_battle_hourly_test`、`ai_encounter_flow_test`、`player_encounter_test`、`player_pursuit_encounter_test`、`encounter_dialogue_ui_test`、`world_map_input_test`、`world_log_ui_test`、`party_panel_test`、`neutral_party_interaction_test`、`battle_scene_test`、`milestone2_flow_test`、`battle_side_result_test`、`battle_retreat_test`、`player_control_test`、`multi_party_battle_test`、`milestone1_restart_test`（save/load 两进程）。

### 明确未实现

- 活动战斗会话不进入存档；读档只保证不出现永久战斗状态，不恢复战斗中的临时 HP/位置。
- 胜利延迟期间不能跳过；左 Alt 详细模式没有触屏/手柄入口。
- 仍不支持并行战斗；仍是单一 `current_battle`。

## 8.17 阶段 6 后续 · 弓箭手与远程箭矢

### 数据与配置

- 新增三级弓箭手 `archer_militia` / `archer_trained` / `archer_veteran`，基础攻击/生命 10/50、20/100、25/180，工资 2/5/10，晋升链路完整。
- 弓箭手复用 `UnitData`、`UnitManager`、`UnitActor`、`UnitController`；没有独立 ArcherActor。
- 新增 `weapon_bow_01`：WEAPON、`attack_type = RANGED`、射程 360、攻击间隔固定 3 秒、箭速 480、抛物线高度 70。
- `UnitConfig.body_height`（默认 48）与 `UnitData` 派生字段 `attack_type` / `body_height` / `projectile_*` 接入 `StatCalculator` 与存档。
- 攻击方式由武器决定，`UnitData.is_ranged_attacker()` 是战斗层唯一分支入口。

### 表现

- 弓 48×48、默认朝左，握把旋转中心 `(27,36)`（对应素材左下角 `(27,12)`）；拉弓 0.18s、撒放 0.08s、恢复 0.30s。
- 箭 48×48、箭头朝上；飞行旋转取地面速度与高度变化合成的视觉速度，箭头始终指向飞行方向。
- 箭矢节点位置始终是地面投影并参与 `Characters` YSort；视觉高度只偏移子 Sprite，不改变前后排序。
- 近战长矛与其他武器路径未改变。

### 箭矢与命中

- 发射时冻结目标地面坐标，`P(t)=P0+(P1-P0)t`；视觉高度 `h(t)=launch·(1-t)+4H·t(1-t)`，显示为 `P+(0,-h)`。
- 命中条件：地面距离 ≤ 18、高度 ≤ 目标 `body_height`、目标存活且敌对；每支箭最多结算一次伤害。
- 移动目标会因固定终点与飞行时间自然射失，没有随机命中率；头顶掠过的箭矢不造成伤害。
- 箭矢在命中、抵达终点或超过 3 秒后销毁；飞行状态不进入存档。

### AI 与玩家

- `UnitController._tick_ranged`：射程内站定射击；射程外接近到 0.82 倍射程；敌人近于 110 时后撤；目标失效后同一 tick 重选。
- 队形槽位分配把近战排前、远程排后，弓箭手优先进入后列。
- AI 与玩家共用 `_fire_ranged_at`；玩家鼠标世界坐标由 `get_global_mouse_position()` 转换后交给 `try_player_attack_at()`。
- 发射成功立即进入 3 秒冷却，动画与冷却独立；接管弓箭手不继承原单位冷却，控制权切换不复制单位或重置 HP。

### 初始部队与存档

- 新游戏玩家部队 15 人：5 民兵 + 6 职业步兵（4 骑乘）+ 2 一级弓 + 1 二级弓 + 1 玩家角色；弓箭手拥有完整 UnitData、弓装备与唯一 ID。
- 旧存档不补兵、不重复生成，也不会额外发放弓箭手。
- `UnitData` 持久化攻击方式/身高/弹道参数与弓装备；飞行箭矢与冷却不入档。

### 测试

- 新增 `archer_battle_test`：配置/装备属性、弓锚点与动画、抛物线/地面深度、静止命中、移动目标射失、头顶掠过、死亡目标、每箭单次伤害、AI 发射/冷却/接近/后撤、玩家固定终点、初始 3 名弓箭手与存档往返。
- 新增 `archer_scene_test`：真实战斗场景注入 ProjectileManager、接管弓箭手、鼠标世界坐标入口、3 秒冷却、箭矢命中与冷却拒绝。
- 回归通过：`battle_scene_test`、`combat_attack_rules_test`、`battle_formation_test`、`player_control_test`、`battle_retreat_test`、`battle_side_result_test`、`milestone2_flow_test`、`save_persistence_test`、`battle_result_delay_test`、`player_party_expansion_test`、`unit_tier_wage_test`、`unit_visual_test`。

### 明确未实现

- 弩、投石索、穿透、AOE、弹药、蓄力、爆头、风力、箭矢回收与完整音效。
- 移动目标预判、齐射/集火、独立弓手线与战术保护。
- 正式弓/箭美术与瞄准指示线。

## 9. 自动化验收

### 测试套件

| 测试 | 覆盖 |
|---|---|
| `Tests/UnitTests/unit_manager_test.tscn` | 配置注册与重复拒绝、创建、独立名称/实例、默认装备、经验升级、多级升级、满级、装备替换/卸下、属性重算、删除归属约束 |
| `Tests/UnitTests/party_manager_test.tscn` | 成员增删、重复加入、转队、阵营拒绝、重复部队 ID、解散、双向一致性校验 |
| `Tests/UnitTests/stat_calculator_test.tscn` | 两种兵种基础属性、等级成长、装备叠加、武器攻击距离覆盖/切换、无效装备、属性写入、HP clamp 与不自动回血 |
| `Tests/UnitTests/unit_party_serialization_test.tscn` | 5 名士兵与多部队存档往返、等级/经验/装备/当前 HP 恢复、读档重算、旧存档缺失字段、无效装备清理、继续转队、损坏引用拒绝加载 |
| `Tests/SystemTests/party_panel_test.tscn` | 大地图部队按钮、面板打开/关闭、概览、完整初始成员列表、详情属性、装备槽位、步兵/骑兵 SubViewport 美术预览、预览只读、暂停原因栈 |
| `Tests/UnitTests/faction_vision_test.tscn` | 阵营关系组合与对称性、视野发现/离开、敌友中立筛选、失效观察者与目标 |
| `Tests/UnitTests/multi_party_battle_test.tscn` | 双方回归、友军加入、独立第三方、中立拒绝、距离/重复校验、多方离屏结算、多侧战斗场景 |
| `Tests/SystemTests/ai_encounter_flow_test.tscn` | 玩家加入离屏战斗、玩家实际战斗侧、`battle_started` 自动进入战斗场景 |
| `Tests/SystemTests/player_encounter_test.tscn` | 敌对 AI 主动拦截玩家、ENEMY_PURSUIT 原因、底部布局与领袖头像、无离开选项、暂停原因栈、防重复、异常清理、进入战斗场景 |
| `Tests/SystemTests/world_map_milestone6_test.tscn` | 村庄原始美术/位置/缩放、固定尺寸徽章+名称组合、徽章读取家族、无家族隐藏、左 Alt 输入切换、简单/详细悬浮 |
| `Tests/UnitTests/party_architecture_test.tscn` | 统一 Party 字段、控制类型/部队类型、NPC 领袖、序列化往返、旧存档默认值与类型推断、读档不重置位置/成员 |
| `Tests/SystemTests/encounter_dialogue_ui_test.tscn` | 部队标记恢复原尺寸、底部 NPC 对话、领袖头像/默认剪影、敌对追击无离开、玩家主动接近保留离开、配置文本 |
| `Tests/SystemTests/player_party_expansion_test.tscn` | 玩家 15 人编制（含 3 名弓箭手）、完整 UnitData、兵种/骑乘数量、领袖、马匹库存、存档往返不丢失或重复生成 |
| `Tests/SystemTests/battle_cluster_test.tscn` | 初始部署距离、战场边界、双方半场列阵、接近/接敌后无严重重叠、局部拥挤上限、目标分流、纵深分布 |
| `Tests/SystemTests/battle_occupancy_ui_test.tscn` | 已有战斗时独立部队禁止另开战场、原因文本、绕过按钮拒绝、参战方“加入战斗”复用同一会话 |
| `Tests/SystemTests/player_battle_interaction_test.tscn` | 接近离屏战斗加入/离开面板、加入已有战斗、离开拒绝与重触发、战斗结束/异常清理、暂停与倍率保护 |
| `Tests/UnitTests/unit_controller_test.tscn` | 接近、攻击间隔、伤害、死亡、重新索敌、手动移动、5v5 自动战斗收敛 |
| `Tests/UnitTests/combat_attack_rules_test.tscn` | 三人围攻、被围攻反击、独立冷却、360°定向矩形、背后/横向/超距排除、玩家四方向、单次单目标、武器距离变化、实体碰撞、骑乘移动加成 |
| `Tests/UnitTests/mounted_unit_test.tscn` | 马匹库存消耗/返还、库存不足、重复装备、MOUNT 派生状态、骑乘属性、旧存档、新游戏 12 人/4 骑乘、存档往返 |
| `Tests/UnitTests/unit_visual_test.tscn` | 人物/马匹分组、层级（左右手武器、头部/头盔、马腿在马身之前）、人体双腿、四腿独立、影子互斥、15 像素偏移、待机/跑动动画、武器摇摆、马匹动画、360°攻击方向、长矛枢轴、装备视觉注入、缺失缨饰回退、UnitActor 名称/生命条集成与名称控制权联动 |
| `Tests/UnitTests/formation_manager_test.tscn` | 横向/纵深/松散/方阵站位、列数自动扩展、间距 |
| `Tests/UnitTests/battle_result_test.tscn` | 胜负/伤亡/经验升级/金币/战利品/撤退/多方/离屏/中途加入/重复结算保护 |
| `Tests/UnitTests/player_character_data_test.tscn` | 玩家角色创建、身份持久化、玩家档案金币/物品往返 |
| `Tests/UnitTests/battle_manager_test.tscn` | 开始校验、锁定、玩家战败结算、剩余 HP 写回、重复结算拒绝 |
| `Tests/UnitTests/ai_manager_test.tscn` | 商队往返、治安队巡逻、玩家/战斗/NONE 跳过、强盗动态评分/切换阈值/追击/失去视野、攻击意图、单方/双方意图遭遇、友方不遭遇、治安队拦截/恢复巡逻、离屏遭遇与中途加入、AI 字段序列化 |
| `Tests/SystemTests/party_dialogue_test.tscn` | 接近 AI 部队、对话内容、暂停恢复、重复 UI、战斗准备、战斗中禁存档 |
| `Tests/SystemTests/world_map_input_test.tscn` | 数字键 1/2/3、小键盘/echo、UI 屏蔽、点击切 1x、真实 tick 下 NPC 移动 |
| `Tests/SystemTests/battle_scene_test.tscn` | 全部参战士兵生成（玩家 15 + 敌方 5）、唯一 unit_id、初始部署距离、边界、2 倍相机、1920×1080 设置、部件 z/贴图、骑乘保留人腿、实时伤害、死亡移除、胜利、结算与存档 |
| `Tests/SystemTests/archer_battle_test.tscn` | 三级弓配置/属性、弓锚点与拉弓动画、抛物线/地面深度、静止命中、移动目标射失、头顶掠过、死亡目标、每箭单次伤害、远程 AI/冷却/接近/后撤、玩家固定终点、初始 3 名弓箭手与存档往返 |
| `Tests/SystemTests/archer_scene_test.tscn` | 真实战斗场景 ProjectileManager 注入、接管弓箭手、鼠标世界坐标射击入口、3 秒冷却、箭矢伤害与冷却拒绝 |
| `Tests/SystemTests/player_control_test.tscn` | 玩家角色控制、WASD/斜向、左键攻击/冷却、受伤、控制权转移、观战、战败结果 |
| `Tests/SystemTests/battle_formation_test.tscn` | 队形槽位、同队间距、多友军 lane 分区、阵亡后重分配 |
| `Tests/SystemTests/battle_side_result_test.tscn` | 同侧一支部队全灭但仍有友军时战斗继续；侧全灭后失败 |
| `Tests/SystemTests/battle_retreat_test.tscn` | 撤退按钮、结果面板、存活写回、无奖励、会话清理 |
| `Tests/SystemTests/milestone2_flow_test.tscn` | 大地图 → 对话 → 战斗 → 返回 → HP/成员结算 → 保存/读档全流程 |
| `Tests/SystemTests/skeleton_smoke_test.tscn` | 原有 18 项：时间 tick、实体序列化、存档往返、WorldContext 装配 |
| `Tests/SystemTests/milestone1_test.tscn` | 世界初始化、移动、边界、存档/读档、NPC/地点恢复、ID 恢复、读档后移动、损坏存档、地点交互、时间暂停、保存面板 |
| `Tests/SystemTests/milestone1_flow_test.tscn` | New Game → WorldMap → 移动 → 保存 → 主菜单 → Load/Continue → WorldMap；Autoload 与旧场景残留检查 |
| `Tests/SystemTests/main_menu_ui_test.tscn` | 主菜单按钮、读取面板、设置占位面板 |
| `Tests/SystemTests/milestone1_restart_test.tscn` | 两次独立 Godot 进程：保存退出 → 新进程读档，校验位置/时间/倍率/实体/ID |
| `Tests/UnitTests/unit_tier_wage_test.tscn` | 三级基础属性、工资、上下马、晋升成功/失败/回滚、旧存档工资迁移、金币与存档 |
| `Tests/UnitTests/time_calendar_test.tscn` | 1103-01-01、6 秒/小时、144 秒/天、30 天/月、360 天/年、时间段、1x/2x/暂停 |
| `Tests/SystemTests/village_scene_test.tscn` | 玩家权威数据、无武器表现、距离交互、对话关闭/移动、越界倒计时 |
| `Tests/SystemTests/village_flow_test.tscn` | 新游戏 → 大地图 → 村庄 → 对话 → 越界返回 → 主菜单 |
| `Tests/SystemTests/world_map_milestone6_test.tscn` | 日期 UI、人数图标、悬浮构成、追逐保护、主动交互恢复 |
| `Tests/SystemTests/party_economy_ui_test.tscn` | 金币/工资显示、上马/下马、晋升按钮与工资总额更新 |
| `Tests/UnitTests/offscreen_battle_hourly_test.tscn` | 离屏战斗 1 小时门槛、双方伤亡、tier 影响、小数累计、玩家加入保留伤亡、转换后停止结算、全灭结束 |
| `Tests/SystemTests/small_scene_camera_test.tscn` | 统一视野、跟随、自由视角、边界限制、切回跟随、村庄摄像机 |
| `Tests/SystemTests/player_pursuit_encounter_test.tscn` | 同向追击接触、停止/清目标、暂停与面板、撤退、拒绝锁、重新触发、进入战斗 |
| `Tests/SystemTests/world_map_battle_marker_test.tscn` | 单战斗标记、参战图标隐藏、按 side_index 分列汇总、小时伤亡刷新、同侧加入、三方三列、结束清理 |
| `Tests/SystemTests/save_persistence_test.tscn` | Schema v3、世界日志往返、世界/地点/部队/士兵/经济恢复、战后成员与 HP、失效战斗状态清理、领袖校验 |
| `Tests/SystemTests/battle_result_delay_test.tscn` | 胜利数据立即生成、面板约 3 秒延迟、失败即时、延迟期间退出取消、无重复展示 |
| `Tests/UnitTests/world_log_manager_test.tscn` | 战斗/胜负/消灭/遭遇/地点事件文本、扩展事件、100 条上限、序列化预留 |
| `Tests/SystemTests/world_log_ui_test.tscn` | 左下角日志面板、自动刷新、滚动区域、不阻挡地图移动 |
| `Tests/SystemTests/neutral_party_interaction_test.tscn` | 路过中立不弹窗、追击不被无关目标打断、主动点击对话、AI 追击遭遇、防重复 |

### 运行命令

```bash
Godot_v4.6.1-stable_win64.exe --headless --path . --import
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/unit_manager_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/party_manager_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/stat_calculator_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/unit_party_serialization_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/unit_controller_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/combat_attack_rules_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/mounted_unit_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/unit_visual_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/formation_manager_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/battle_result_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/player_character_data_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/battle_manager_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/ai_manager_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/faction_vision_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/multi_party_battle_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/party_panel_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/ai_encounter_flow_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/player_encounter_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/player_battle_interaction_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/party_dialogue_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/world_map_input_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/battle_scene_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/player_control_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/battle_formation_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/battle_side_result_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/battle_retreat_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/milestone2_flow_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/skeleton_smoke_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/milestone1_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/milestone1_flow_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/main_menu_ui_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/milestone1_restart_test.tscn -- save
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/milestone1_restart_test.tscn -- load

# 阶段 6 新增
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/unit_tier_wage_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/time_calendar_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/village_scene_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/village_flow_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/world_map_milestone6_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/party_economy_ui_test.tscn

# 阶段 6 大地图战斗与小地图视角优化
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/offscreen_battle_hourly_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/small_scene_camera_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/player_pursuit_encounter_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/world_map_battle_marker_test.tscn

# 阶段 6 世界日志、美术层级与战斗表现
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/world_log_manager_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/world_log_ui_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/neutral_party_interaction_test.tscn

# 阶段 6 后续：大地图表现、AI 战后恢复、存档与战斗 UI
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/save_persistence_test.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/battle_result_delay_test.tscn

# 手动视觉验收（非 headless，打开窗口并保存截图到 user://）
Godot_v4.6.1-stable_win64.exe --path . res://Tests/_debug/visual_probe.tscn
Godot_v4.6.1-stable_win64.exe --path . res://Tests/_debug/party_preview_probe.tscn
Godot_v4.6.1-stable_win64.exe --path . res://Tests/_debug/main_menu_probe.tscn
```

本次实际执行（阶段 6 村庄/交互/部队管理）：新增 `unit_tier_wage_test`、`time_calendar_test`、`village_scene_test`、`village_flow_test`、`world_map_milestone6_test`、`party_economy_ui_test` 全部通过；更新并回归 `unit_manager_test`、`stat_calculator_test`、`unit_party_serialization_test`、`mounted_unit_test`、`battle_result_test`、`party_panel_test`、`combat_attack_rules_test`、`unit_controller_test`、`battle_manager_test`、`battle_scene_test`、`player_control_test`、`battle_formation_test`、`battle_side_result_test`、`battle_retreat_test`、`ai_manager_test`、`faction_vision_test`、`multi_party_battle_test`、`party_dialogue_test`、`player_encounter_test`、`player_battle_interaction_test`、`ai_encounter_flow_test`、`world_map_input_test`、`milestone2_flow_test`、`skeleton_smoke_test`、`milestone1_test`、`milestone1_flow_test`、`main_menu_ui_test`，全部通过。未执行非 headless 村庄截图与跨进程重启测试。未改变存档 Schema；新增字段均使用安全默认值。

本次实际执行（阶段 6 大地图战斗与小地图视角）：新增 `offscreen_battle_hourly_test`、`small_scene_camera_test`、`player_pursuit_encounter_test`、`world_map_battle_marker_test` 全部通过；更新并回归 `multi_party_battle_test`、`battle_result_test`、`ai_manager_test`、`battle_scene_test`、`player_control_test`、`player_encounter_test`、`player_battle_interaction_test`、`world_map_milestone6_test`、`world_map_input_test`、`party_dialogue_test`、`village_scene_test`、`village_flow_test`、`milestone2_flow_test`，全部通过。未执行非 headless 视觉截图与跨进程重启测试。未改变存档 Schema；摄像机、离屏战斗与战斗 UI 状态均为运行时数据。

本次实际执行（阶段 6 世界日志/美术层级/战斗表现）：新增 `world_log_manager_test`、`world_log_ui_test`、`neutral_party_interaction_test` 全部通过；扩展 `unit_visual_test` 通过；更新并回归 `party_dialogue_test`、`world_map_input_test`、`world_map_milestone6_test`、`milestone2_flow_test`、`battle_scene_test`、`player_control_test`、`party_panel_test`、`village_scene_test`、`village_flow_test`、`player_encounter_test`、`player_battle_interaction_test`、`player_pursuit_encounter_test`、`ai_encounter_flow_test`、`battle_retreat_test`、`world_map_battle_marker_test`、`multi_party_battle_test`、`offscreen_battle_hourly_test`，全部通过。未执行非 headless 视觉截图与跨进程重启测试。未改变存档 Schema；日志历史本阶段不持久化。

本次实际执行（阶段 6 地点点击交互与战斗名称显隐）：`unit_visual_test`、`world_map_milestone6_test`、`world_map_input_test`、`party_dialogue_test`、`village_flow_test`、`milestone1_test`、`battle_scene_test`、`neutral_party_interaction_test` 全部通过。覆盖点击地点才打开面板、路过/追击不弹窗、普通士兵隐藏名称、控制单位保留名称、名称与生命条独立显隐。未改变存档 Schema。

本次实际执行（阶段 6 家族领袖/NPC 部队/地图表现）：新增 `family_appearance_test` 全部通过；更新后通过 `unit_visual_test`、`milestone1_test`、`milestone1_restart_test`（save/load 两阶段）、`milestone2_flow_test`、`world_map_input_test`、`world_map_milestone6_test`、`party_dialogue_test`、`neutral_party_interaction_test`、`ai_manager_test`、`unit_party_serialization_test`。覆盖家族配置/外观池与概率/装备优先级/两村改名/两队 10 人编制/领袖与序列化/旧存档默认值/圆形旗帜标记/固定屏幕地点名称/统一 0.5 速度。未执行无关全量测试与非 headless 截图。

本次实际执行（战斗占用提示修复）：新增 `battle_occupancy_ui_test` 全部通过；回归通过 `party_dialogue_test`、`encounter_dialogue_ui_test`、`world_map_milestone6_test`、`player_encounter_test`、`ai_encounter_flow_test`。覆盖离屏战斗占用时的禁用与原因文本、绕过按钮直接拒绝、参战方加入已有战斗。未改变存档 Schema；未修改 BattleManager 单一战斗会话规则。

本次实际执行（阶段 6 后续：大地图表现/AI 恢复/存档/战斗 UI）：新增 `save_persistence_test`、`battle_result_delay_test` 全部通过；更新后通过 `world_map_milestone6_test`、`world_map_battle_marker_test`、`battle_scene_test`、`milestone2_flow_test`、`multi_party_battle_test`；回归通过 `party_manager_test`、`unit_party_serialization_test`、`party_architecture_test`、`family_appearance_test`、`world_log_manager_test`、`battle_manager_test`、`battle_result_test`、`ai_manager_test`、`offscreen_battle_hourly_test`、`ai_encounter_flow_test`、`player_encounter_test`、`player_pursuit_encounter_test`、`encounter_dialogue_ui_test`、`world_map_input_test`、`world_log_ui_test`、`party_panel_test`、`neutral_party_interaction_test`、`battle_side_result_test`、`battle_retreat_test`、`player_control_test`、`milestone1_restart_test`（save/load 两进程）。存档 Schema 升至 v3；仅执行自动测试，未做非 headless 视觉验收。

### 手动验证步骤

1. 启动游戏，进入主菜单。
2. New Game → 大地图默认暂停；玩家部队 15 名成员（含 4 名骑乘职业步兵与 3 名弓箭手），数据速度 150（大地图实际 75）。
3. 按 `2` 进入 1x，观察河畔商队向巴里移动、北境巡逻队向第一个巡逻点移动；按 `1` / `3` 验证暂停与二倍速。
4. 点击地图移动玩家部队；若点击前为 2x，应自动切回 1x；观察玩家速度明显慢于 NPC。
5. 持续运行一段时间，确认商队到达巴里后转向墨西西，巡逻队按四点顺序循环；确认巴里/墨西西骑士沿各自专属巡逻点移动。
6. 主动点击“河畔商队”并接近后打开部队对话。
7. 确认面板显示部队名称、阵营“商队”、兵力 5；点击离开，确认世界恢复暂停前倍率。
8. 再次接近并点击“发起战斗”，进入战斗场景；确认玩家 12 名士兵（含 4 名骑乘）、敌方 5 名士兵、双方分居战场两侧、玩家角色带金色控制圈、阵营罩袍区分、位置不重叠。
9. 使用 WASD 移动玩家角色，验证四方向与斜向速度一致；鼠标左键攻击范围内敌人，确认伤害/攻击间隔来自 Unit。
10. 消灭全部敌人后查看结果面板（胜负、伤亡、经验、金币/战利品），点击“返回大地图”，确认部队解锁、存活士兵保留 HP、阵亡敌人变为 DISABLED。
11. 检查保存面板打开时数字键与地图点击均被屏蔽。
12. 保存并读取，确认 NPC 路线进度、目标、移动状态与玩家速度正确恢复。
13. 在大地图顶部点击“部队”，确认面板打开且世界暂停、基础倍率不变。
14. 检查部队名称、阵营、人数（12）、移速、状态；左侧 12 名士兵各显示一次，默认选中第一名；右侧美术预览随选中切换。
15. 点击不同士兵，确认右侧姓名、兵种、等级、经验、HP、攻击、攻击间隔、移速、射程与装备槽位正确切换；空槽显示“无”。
16. 关闭面板，确认恢复打开前的时间倍率；若存在其他暂停原因，关闭后仍保持暂停。
17. 通过数据层（或后续装备 UI）给士兵装备铁剑后重新打开面板，确认攻击与装备槽位更新；保存并读档后确认等级、经验、装备、当前 HP 与最终属性一致。
18. 点击移动或静止的商队/家族骑士，确认玩家部队持续跟随（目标离开视野也不中断）；追上目标、目标进入战斗或失效后跟随自动取消。
19. 观察山道强盗游荡；当商队进入视野后，强盗应追击并在接近后触发离屏战斗，世界时间继续推进。
20. 让治安队接近商队-强盗战斗，确认治安队加入商队一方；再让玩家部队接近战场，确认进入战斗场景且玩家位于正确战斗侧。
21. 在战斗场景确认同侧士兵不互相攻击、第三方拥有独立战斗侧；战斗结束后所有参战部队解除锁定。
22. 离屏战斗进行期间尝试保存，确认返回 `ERR_BUSY`；战斗结束后可正常保存。
23. 观察强盗追击移动中的商队：即使商队继续移动，双方接近到遭遇距离后也应触发战斗，不再无限追逐。
24. 强盗追击玩家时，在距离约 50 处停下并弹出遭遇对话；确认对话显示强盗名称、阵营、兵力与“留下财物”描述。
25. 确认遭遇对话提供“战斗”与“撤退”按钮；对话期间世界暂停，撤退后恢复基础倍率并记录拒绝锁，离开 90 世界单位后可再次触发。
26. 点击“战斗”进入战斗场景；确认玩家与强盗处于不同战斗侧，战斗结束后双方状态正确。
27. 让强盗先追逐玩家，再让商队进入视野；强盗应重新评估并优先切换商队（评分差距足够时）。
28. 让商队与强盗在玩家附近发生离屏战斗，玩家接近到交互范围：世界暂停并弹出“遭遇战”面板，显示交战方与持续时间。
29. 选择“离开”：面板关闭、世界恢复原倍率、NPC 战斗继续；玩家留在原地，不自动重复弹出。
30. 离开交互范围后再次接近，面板应重新出现；选择“加入战斗”后进入已有战斗场景，而不是创建新战斗。
31. 在面板打开期间结束 NPC 战斗或异常关闭面板，确认暂停原因被清理，其他暂停原因与原基础倍率不受影响。
32. 在战斗中确认玩家角色金圈与“控制：玩家角色”标签；WASD 移动与斜向速度一致。
33. 左键点击范围内敌人，确认伤害、攻击间隔与攻击距离来自 Unit；快速点击不能绕过冷却。
34. 让玩家角色被击败，确认控制权转移面板出现、战斗暂停；选择存活友军接管，确认可继续移动/攻击。
35. 再次让当前控制单位被击败并选择“观战”，确认战斗继续且 WASD/左键失效；清空玩家侧后显示战败结果。
36. 观察双方单位不再全部堆叠：前排接敌、后排保持纵深；多支友军部队使用不同 lane 区域。
37. 点击“撤退”，确认结果显示“已撤退”、存活士兵保留、没有胜利奖励。
38. 胜利后确认结果面板显示我方/敌方伤亡、玩家经验、金币与战利品；返回大地图后保存/读档，金币与经验保留。
39. 制造“同侧一支部队全灭但另一支友军存活”的情况，确认战斗不提前结束；同侧全部失去战斗能力后才失败。
40. 返回大地图后确认没有残留战斗会话或暂停原因，大地图可以继续移动、时间推进与保存。
41. 观察步兵移动：左右腿等幅反向交替、前摆腿抬起、后摆腿接地，停止后双腿回到默认位置。
42. 观察骑兵移动：马身整体起伏/俯仰更明显、马腿位移克制、马头独立摆动；待机时马腿基本静止；骑手与马身起伏同步。
43. 站在完全没有敌人的区域连续点击鼠标左键：角色按攻击间隔向鼠标方向空挥，播放完整动画但不造成伤害；冷却期间点击无效。
44. 攻击后观察长矛保持倾斜约 4 秒，再平滑回到竖直；保持期间移动/待机不会拉直长矛；保持期间再次攻击会立即衔接并重置计时。
45. 同等级步兵与骑乘单位直线移动对比，骑乘应明显更快；步兵速度与大地图部队速度不变。进入战斗确认双方初始间隔比上一版更远、阵型不出界。
46. 观察步兵移动：腿部水平摆幅与抬脚幅度明显收敛，身体起伏仍是主要动态，双腿仍协调交替；停止后双腿复位。
47. 打开部队面板：步兵预览有轻微身体/头部/武器待机动作；选择骑乘士兵后，马身与骑手同步起伏；关闭面板后预览停止推进。
48. 观察战马移动：两只前腿一起向前伸、两只后腿一起向后伸，随后两组同步收缩；不再出现左右腿交替走路。
49. 向任意方向攻击：长矛先沿反方向轻微后移，再快速向攻击方向前伸；空挥也播放完整动作。
50. 确认长矛戳击后保持约 4 秒，再平滑回到竖直；连续攻击立即重新开始前摇并重置保持时间。
51. 观察步兵跑动：左右腿围绕下移 3 px 的新旋转中心摆动，待机贴图位置与修正前一致，不出现整体上下漂移。
52. 观察骑乘单位跑动：四条马腿的伸展/收缩和前后分组关系保持不变，腿部与马身连接更自然。
53. 打开部队面板，确认步兵与骑乘预览的腿部待机表现与战斗场景一致。
54. 观察战马跑动：马身整体明显上下跃动、俯仰与伸展/收缩成为主运动，四条腿只做小幅辅助伸展；前腿组/后腿组关系仍保持。
55. 观察骑乘单位：马身上升/回落时骑手同步上下移动，骑手与马身没有明显脱节，也没有额外的双重弹跳。
56. 观察步兵跑动：腿部水平摆动、抬脚与旋转进一步降低，身体起伏仍是主要动态；待机时双腿复位。
57. 检查部队 UI 的步兵/骑兵预览，待机动画与战斗场景一致，切换单位不累积节点。
58. 观察步兵身体上下起伏/倾斜时，双腿随身体整体移动，而不是留在原地或独立漂移；腿部自身只剩极小摆动。
59. 观察战马跃动时，四条马腿随马身整体升降/俯仰/缩放；前后腿组的跃马关系仍保留，马腿自身动作很小。
60. 确认骑手继续跟随马身整体垂直运动，腿部挂载调整没有破坏待机、攻击动画、美术层级或部队 UI 预览。
61. 观察骑兵跑动：马腿局部伸展比上一版更明显，但仍远小于马身整体跃动；前腿组/后腿组关系保持。
62. 比较骑兵整体上下幅度：比上一版更低，但仍保留必要跃动感；骑手与马身保持整体协调。
63. 观察骑马影子：马匹抬高时影子轻微缩小/变淡，回落时恢复；影子没有明显跳动、闪烁或位置漂移。
64. 进入大地图，确认左下角显示“世界日志”面板；触发一场 AI 对 AI 战斗，日志应出现战斗开始、胜负与被消灭部队；进入/离开村庄后出现对应日志；历史条目可滚动查看。
65. 普通寻路或追击目标时路过中立/无关部队，不应自动暂停或弹窗；主动点击中立部队并接近后才打开对话；敌对 AI 实际追上玩家时正常弹出遭遇。
66. 进入战斗，普通士兵不显示头顶名称与满血生命条；玩家当前控制角色保留头顶名称；受伤士兵出现生命条，恢复满血后重新隐藏；切换控制后名称显示随控制权更新。
67. 数据层给头盔/盾牌配置 `visual_texture_path` 后，确认头盔与头部同时显示、左手武器位于马头之后；卸下后头部仍显示，右手长矛动画不变。
68. 大地图上确认玩家、家族、强盗、商队标记保持原有小尺寸，村庄圆形标记明显更大且旗帜被边框裁剪；村庄名称在标记正上方。
69. 被盗贼主动追上时，底部遭遇对话显示领袖头像/名称与威胁对白，且没有离开选项；玩家主动点击敌对部队时仍可离开。
70. 清空某支部队的 `leader_unit_id` 后触发遭遇，确认显示默认剪影与部队名，UI 不报错。
71. 新游戏部队面板确认玩家 15 人（5 民兵、6 职业步兵、3 弓箭手、1 玩家角色），其中 4 名职业步兵显示骑马；背包剩 1 匹马。
72. 小地图战斗开始时确认双方位于战场两侧，有明显接近距离；步兵与骑兵都能正常接敌。
73. 接敌后观察 1–2 分钟，确认士兵不再全部叠在一点，后排不会全部挤到前排，骑兵有更大活动空间。
74. 多方战斗/中途加入时确认各战斗侧保持自己的集群，不混成一个点；单位不越出战场边界或卡死。

## 10. 下一步任务

1. 村庄正式内容：商店、招募、任务、好感度、村庄头人作息与多选项对话。
2. 城镇/城堡独立小场景；村庄碰撞、城门与出口通道。
3. 工资定期扣除、士气、逃兵与经济循环；晋升凭证正式来源。
4. 完整背包/物品栏 UI、装备更换、商店与交易。
5. 大地图寻路、地形阻挡、道路加成与速度系数；战斗寻路与更复杂队形。
6. 强盗营地、强盗经济、装备获取与招募系统。
7. 正式士兵美术；继续补受击动画、受击硬直与独立缨饰/罩袍贴图；步兵/马匹步态待正式美术替换。
8. 招募系统替换 `milestone2_test` 临时兵力，处理旧存档补员。
9. 高级战斗指挥：玩家选择加入方、键盘部队指令 UI、士气与多部队协同。
10. 玩家角色永久阵亡后的复活/继承/重开流程；玩家战败的逃脱/被俘处理。
11. 存档：Schema v1 → v2 完整迁移、自动存档、其他跨实体引用校验。
12. AI 主动撤退、追击撤退方、俘虏与伤兵规则。
13. 离屏战斗的伤兵/俘虏、士气、撤退与更长时间平衡；随机种子纳入存档。
14. 目标周围显式攻击槽位分配、位置不足时的等待/换位；AI 骑兵不停步攻击与冲锋加成。
15. 小场景高级镜头：缩放、边缘拖动、手柄/Input Map、战斗标记点击与单部队详情。
16. 大地图战斗观察体验：远离战场时的小地图指示、战斗标记点击交互与旁观模式。
17. 世界日志持久化、类型过滤、点击跳转与完整事件覆盖。
18. 正式头盔/左手武器素材与装备差异化外观；生命条样式与战斗 UI 缩放。

## 11. 当前风险

- 离屏战斗已改为按游戏小时、战力/等级/骑乘/剩余生命与随机波动结算；但仍是只产生阵亡的数据模型，没有伤兵、士气或撤退；48 小时上限会按剩余战力强制判胜。
- 玩家接近离屏战斗时已改为“加入/离开”面板；加入后的战斗侧仍按阵营关系自动确定，不能手动选择。
- 玩家离开后停在原地，不自动恢复原移动指令（符合需求 5.4）。
- 战斗交互面板只提供加入/离开，不提供旁观或谈判。
- 强盗与治安队没有营地、补给、工资或经济系统，仅作为大地图 AI 势力。
- 商队路线、强盗游荡点与治安队巡逻点仍为代码配置，修改需改初始化代码/常量（KI128）。
- 大地图采用直线移动，无寻路与地形阻挡；NPC 可能穿过河流/建筑。
- 战斗 AI 已有基础队形/局部避让与射程外接近逻辑，但无寻路与显式攻击槽位，多单位仍可能局部拥挤。
- 玩家战败后部队变为 DISABLED，尚无逃脱/被俘/重开流程。
- 被击溃的敌方部队保留为 DISABLED 图标，仅禁止交互与 AI。
- 临时测试兵力会进入新存档；新游戏共 4 支部队、20 名士兵；旧存档读档后可能无兵可战。
- 旧存档保留原阵营 ID 与原速度；新游戏使用新阵营与 80/120/100 速度。
- 遭遇对话已区分来源：`ENEMY_PURSUIT` 只提供战斗；`PLAYER_INITIATED`/普通敌对遭遇保留离开。仍不能谈判或缴赎；离开后记录 90 世界单位拒绝锁，但该锁与玩家追击焦点均不持久化。
- 攻击意图、遭遇原因与待处理遭遇不持久化，读档后由 AI 重新建立。
- 旧存档部队的 `control_type`/`party_kind` 按玩家 ID、家族、阵营与 `ai_type` 推断；自定义阵营可能归为 `GENERIC`，但不会影响移动、成员或战斗流程。
- 玩家角色永久阵亡后没有复活/继承流程；后续战斗会退化到第一名存活友军作为控制对象。
- 撤退目前主要由玩家 UI 发起；AI 战斗侧没有主动撤退决策，`retreat_side()` 已预留接口。
- 队形/避让是局部算法，没有寻路与地形阻挡；狭窄地形或大量单位仍可能拥挤。
- 战后经验/奖励在点击“返回大地图”时最终结算；结果面板显示的是同源预览。
- 奖励只有金币与装备 ID，尚无物品栏/装备商店 UI 与经济系统。
- 攻击已有攻击闪光、长矛 360°旋转与攻击后 4 秒保持，但伤害仍即时命中；没有伤害前摇、受击硬直与受击动画。
- 长矛枢轴按当前 48×96 临时素材映射；设计稿人物身体为 96×32，正式素材替换时需要重新核对枢轴。
- 四条马腿仍是独立贴图，已挂载在马身 rig 下并继承整体跃动，但仍是程序化局部动作；没有骨骼/正式逐帧动画。骑手只跟随马身垂直偏移，不跟随马身俯仰/缩放，不是完整骑乘绑定。骑马影子仅有缩放/透明度响应，没有轮廓形态变化。
- 目标周围没有显式攻击槽位分配，单位很多时仍可能因局部避让而拥挤（KI348）。
- 战斗集群参数（初始距离、队形间距、接敌放松、分离半径、目标占用惩罚）目前为集中常量，仅通过自动化位置断言验证，仍需实机观察微调（KI404）。
- 弓箭手已接入远程 AI、玩家射箭与 3 秒冷却；但仍无弹药、穿透、溅射、爆头、箭矢回收、移动目标预判与齐射/集火，命中只做每帧地面距离 + 身高检测，无线段扫掠（KI423/KI424/KI426）。
- 弓与箭均为临时 48×48 美术；握把锚点 `(27,36)` 按临时素材校准，正式素材替换时需重新核对；玩家没有瞄准指示线（KI425/KI428）。
- 弓箭手队形只依赖“近战排前、远程排后”的槽位排序，没有独立 `ARCHER_LINE`、护卫阵型或接敌后自动后撤的战术协同（KI427）。
- 玩家扩编（含 3 名弓箭手）只作用于新游戏；已有成员的旧存档保持原人数与位置，不会自动补员（KI405）。
- 村庄名称位置按标记半径 × 相机缩放计算，使用固定 32 半径；若未来村庄标记改为可配置尺寸，需要同步读取配置而不是硬编码。
- `art/正式人物美术/` 已提供巴里/墨西西两家族独立的罩袍、缨饰、旗帜与长矛；普通无家族士兵仍使用身体贴图蓝色区域着色，缨饰插槽为空（KI349）。
- 没有骑乘/卸下马匹 UI，也没有物品数量 UI（KI350/KI351）。
- 部队预览固定 1.6 倍缩放，尚未根据装备切换不同武器/护甲外观；预览背景与布局仍为临时方案。
- 实体碰撞是“最小间距推开”，不是物理刚体；没有寻路/地形阻挡，大量单位拥挤时仍可能反复调整。
- 360°攻击矩形宽度半宽 22、前向加成 6 为当前手感值；正式武器种类增多后需要按武器配置矩形形状。
- 玩家攻击已有方向性前摇/戳击与 4 秒保持，但伤害仍在攻击触发时即时结算；自由空挥也消耗冷却，尚未实现受击硬直或戳击命中判定。
- 1920×1080 下 UI 使用原生像素字号；主菜单/部队面板可读但相对较小，后续可做 UI 缩放主题。
- 大地图相机默认 1.5 倍，世界地图图标/道路表现需要继续按正式美术校准。
- 村庄与战斗共用 960×540 视野；自由视角仅支持 WASD/方向键移动，无缩放、边缘拖动或手柄，`F` 为硬编码快捷键（KI402）。
- 战斗期间参战部队图标隐藏，只能查看战斗侧汇总，无法悬浮单支部队或点击标记查看详情（KI403/KI405）。
- 世界日志只在运行时保留，未写入存档；无按类型过滤、点击跳转与触屏滚动入口（KI407–KI409）。
- 已提供 1/2/3 级正式头盔并接入外观随机；左手盾牌仍无正式贴图，`LeftHandWeapon` 部件与 `EquipmentConfig` 视觉字段保持就绪（KI406）。
- 普通部队对话现在只对主动点击目标自动打开；玩家若只是路过中立部队，需要主动点击才能交互。这是有意设计。
- AI 进入射程后停步攻击，因此 AI 骑兵通常不会触发移动攻击加成（KI352）。
- 数字键 1/2/3 为硬编码，尚未迁移到 Input Map。
- 渲染器仍为 Forward+，2D 项目是否需要切 Compatibility 待验证。
- `LordData` / `FactionData` 尚无仓储管理器；阵营关系当前由 `FactionManager` 代码默认值维护。
- 美术资源仍在 `art/` 下按来源分目录，尚未整理为统一 `Assets/` 正式目录；地图与图标仍为程序绘制，士兵已接入 `art/` 临时部件、正式头盔与两家族服装。
- 士兵等级成长与装备属性已生效，但装备无法通过 UI 更换；装备只能由代码调用 `equip_item()` 获得（KI327）。
- 战斗存活/获胜经验已接入；击杀、助攻与最后一击奖励仍未实现（KI328）。
- 装备职业限制字段已预留但未校验（KI329）。
- 单位-部队归属已校验；地点、领主等其他引用尚未统一校验。
- 跨阵营收编、俘虏、叛变与雇佣兵规则未实现，当前直接拒绝阵营不一致。
- 战斗与战斗侧不进入存档；离屏战斗期间禁止保存。

- 村庄没有碰撞/城门，离开完全依赖可活动区域倒计时；玩家可穿过房屋与栅栏（KI390）。
- 城镇/城堡尚无独立小场景（KI391）。
- 晋升凭证只有新游戏测试库存，没有正式获取途径（KI392）。
- 工资只统计与展示，不自动扣除；士气、逃兵与经济循环未实现（KI393）。
- 世界日历为每月 30 天的简化历法，未实现真实月份/闰年/季节（KI396）。
- 村庄头人固定站位，没有作息、任务、好感度或交易（KI397）。
- 村庄对话当前只有单选项（KI398）。
- 战斗属性整体上调（三级 10/50、20/100、25/180）后，既有战斗节奏与离屏结算仍按旧测试基线校准；后续需要按新数值重新平衡战斗时长与奖励（KI330 相关）。
- 大地图悬浮面板只支持鼠标，触屏/手柄没有等价入口（KI394）。
- 追逐焦点不持久化，读档后需要玩家重新点击目标才会恢复自动交互保护（KI395）。
- 读档没有校验“背包马匹 + 已装备 MOUNT”的数量守恒；正常管理器/UI 流程保持一致，手工损坏存档可能重复（KI399）。

## 12. 快速文件索引

| 想了解 | 看这里 |
|---|---|
| 全局结构 | `Docs/01_Core_Architecture.md` |
| 下一步做什么 | `Docs/02_Development_Roadmap.md` |
| 为什么这样设计 | `Docs/Development/Technical_Decisions.md` |
| 还有什么坑 | `Docs/Development/Known_Issues.md` |
| 士兵数据与属性 | `Docs/Systems/Unit_System.md` |
| 部队与成员关系 | `Docs/Systems/Party_System.md` |
| NPC 商队与巡逻 AI | `Docs/Systems/AI_System.md` |
| 战斗流程与结算 | `Docs/Systems/Combat_System.md` |
| 时间规则 | `Docs/Systems/Time_System.md` |
| 大地图 | `Docs/Systems/World_Map_System.md` |
| 地点 | `Docs/Systems/Settlement_System.md` |
| 村庄小场景 | `Docs/Systems/Village_System.md` |
| 背包/金币/工资/晋升 | `Docs/Systems/Inventory_Economy_System.md` |
| 存档结构 | `Docs/Systems/Save_System.md` |
