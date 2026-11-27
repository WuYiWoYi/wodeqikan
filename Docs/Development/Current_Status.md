# 当前开发状态

**更新日期：** 2026-11-27
**当前阶段：** 大地图重建、六方势力补全、旗帜资源命名修复、顶栏信息图标放大、部队/建筑悬浮描边、全体部队移速基准调整与部队标记圆形失真修复已完成；此前的身份选择、雇佣兵美术/独立招募、战败清理、玩家被俘与逃脱保持有效
**整体状态：** 阶段 0–14 及 2026-11-27 大地图重建均已交付；阶段 2/3/4/7 的长期路线仍有明确未做项。存档 Schema v10（政治数据新增可选 `people_name`，旧档缺失时为空，不单独升版）；本次地图重建复用现有地点/存档结构，不新增持久化字段。
**最近变更：** 以参考图 1556×1323 为唯一布局依据，按 5 倍重建 7780×6615 世界：63 个地点、46 条显式道路、46 点不规则边界、11 点湖泊、5 座山脉；`WorldMapDefinition` 保存几何与参考坐标，`WorldTerrain` 用 40 像素 A* 网格提供可通行性与绕行，玩家与 NPC 共用；最近地点对约 5.8 游戏小时（按当前 1x 下 2 秒/小时；现实约 11.5 秒，玩家 450×0.08 = 36 像素/秒）。六方势力（伯克纳、弗拉尼、瓦伊拉、洛里亚克、泰纳、瓦勒蒙）及附庸/民族补齐，初始全部和平；保留旧世界 9 处地点所有权，不按地图位置推断封地。17 个 NPC 家族旗帜统一为 `<家族>旗帜16_16.png`，修复伯克纳与克里卡引用；瓦伊拉暂无专属旗帜美术。旧存档尺寸不匹配时回退矩形边界与直线移动。顶栏水平中心新增 36×36 昼夜滚动窗口：复用 `UI_昼夜` 96×48 美术，按世界累计时间以 96 像素周期循环滚动，12:00 白天、18:00 交接、00:00 黑夜、06:00 夜昼交接，暂停/倍速/读档由同一世界时间换算。大世界时间流速由 1x 下 6 现实秒/游戏小时调整为 2 现实秒/游戏小时（48 秒/日）：只改 `TimeManager` 统一换算常量，暂停栈、0/1/2 倍率定义、移动速度与经济系统未改；离屏战斗与伤兵/俘虏的本地小时常量同步为 2 秒。大地图移速基准为 30（由 20 再 ×1.5）：NPC 原始速度统一 ×5/2（商队 200、巡逻 300、强盗 250、家族骑士 275，保持相对差异与排序），玩家单列为原始 450 / 有效 36；`WORLD_MAP_SPEED_SCALE` 仍为 0.08，战斗/小场景移速与时间流速未改。顶栏金币/移速/人数图标由 20×20 放大到 40×40（等比、间距 6）；部队圆形标记的旗帜最大边长定为 48 并裁到黑色描边内缘，黑色基础描边由 1.5 加粗到 2.5 且只向圆内扩展（外缘保持 18.75，整体尺寸不变）；旗帜遮罩改为局部像素正圆模式，修复 `AtlasTexture` 图集 UV 导致的椭圆失真，0.5x/1x/2x 下主体、黑色描边、旗帜裁剪与白色悬浮描边均保持正圆同心；鼠标悬浮部队或建筑时由 `_update_hover_outline()` 统一切换 3/5 像素白色描边，同一时刻只高亮一个目标。
**读取提示：** 只有任务涉及“当前进度、已有实现、下一步”时才读本文件。系统规则读 `Docs/Systems/*.md`；历史细节读 [Archive/Status_History.md](../Archive/Status_History.md) 或 [04_Change_Log.md](../04_Change_Log.md)。

**状态标记：**

- `已实现`：代码当前存在，且至少有自动化测试或系统文档支撑。
- `部分实现`：主链路可用，但存在明确缺口。
- `未实现`：只有设计、占位或接口。
- `已确认 / 暂定 / 待确认`：只用于设计规则；本文件不把“代码当前如此”自动写成用户已确认。

> 本页是**当前状态快照**，采用覆盖式更新。阶段实现细节、历史测试清单与手动验收步骤已归档，不在此累积。

---

## 1. 阶段状态

| 阶段 | 状态 | 当前说明 |
|---|---|---|
| 0 工程基础架构 | 已实现 | 5 个 Autoload、数据层、主菜单、存档闭环 |
| 1 大地图基础 | 已实现 | Milestone 1 全部功能 |
| 2 世界模拟 | 部分实现 | NPC 商队/巡逻、强盗/治安队 AI、视野、追击、遭遇、离屏战斗已实现；空间索引与路线/巡逻点 `.tres` 配置未做 |
| 3 士兵与部队 | 部分实现 | 数据层、三级兵种、等级/经验、装备/骑乘、部队面板、外观动画、普通士兵换装、雇佣兵装备锁定已实现；正式美术未做 |
| 4 基础战斗 | 部分实现 | 实时/多方战斗、离屏小时结算、中途加入、增援、队形、结算已实现；士气、高级指挥、寻路、AI 撤退未做 |
| 5 战斗结算与表现 | 已实现 | BattleResult、玩家角色、攻击规则、骑乘、动画、撤退、奖励、控制权转移 |
| 6 村庄/经济/大地图 | 已实现 | 村庄小场景、对话、背包/金币/工资统计、三级兵种/晋升、世界日历、世界日志、弓箭手、大地图交互 |
| 7 封地与政治经济 | 部分实现 | 封地所有权、采邑征召、普通/贵族冒险者招募、NPC 冒险者招募、家族面板、人口/税收缓存、贵族/家族/王国已实现；任务、训练、外交、城堡攻防、领地转让、军团、世界战争未做 |
| 8 战场/增援/政治/地图/百科 | 已实现 | 1800×1024 战场、增援、Noble/House/Kingdom、三级百科、Schema v5（旧 5000×3000 地图已被 2026-11-27 重建取代） |
| 9 地点布局与旗帜 | 已实现 | 部队内部旗帜放大；旧 9 地点布局已被 2026-11-27 大地图重建取代 |
| 10 战后追击/AI 助攻/大地图交互 | 已实现 | 战后冷却与追击恢复、AI 加入既有战斗、增援部署、行动意图悬浮、二次确认 |
| 11 背包与城镇市场 | 已实现 | 只读背包 UI、城镇市场、原子交易、交易日志、20 条日志上限 |
| 12 马匹/补给/村庄市场 | 已实现 | 马匹独立实例、面包/草料、每日补给、NPC 采购、村庄市场、Schema v6 |
| 13 伤兵/俘虏/大地图展示 | 已实现 | 家族旗帜与停留部队旗帜条、伤兵判定与顺序治疗、俘虏分配/接收、酒馆出售、Schema v7 |
| 13 后续：主界面信息与百科 | 已实现 | 顶栏金币/移速与 ALT 明细、建筑面板 UI 权限、事件中心（只读聚合）、百科分类/详情/敌对势力、暂停计数 |
| 13 后续：经验/价格/赎回 | 已实现 | 五级战斗经验与 HP 成长、兵种 tier 定价、NPC 领主出售与家族赎回、右侧事件框/详情弹窗、Schema v8 |
| 13 后续：贵族/NPC 招募/家族 | 已实现 | 贵族冒险者（三级 + 战马）、拥有者权限、NPC 普通冒险者招募、冒险者招募浮动提示、家族面板部队/封地与定位 |
| 13 后续：国王盔/顶栏图标 | 已实现 | 国王身份头盔外观覆盖与动态回退、国王盔期间隐藏缨饰、顶栏金币/移速/部队人数图标数值、部队人数悬浮明细 |
| 13 后续：酒馆/关押期赎买/提醒 | 已实现 | 独立出售俘虏界面、玩家关押期 3–12 小时家族赎买、拒绝与自动失效、原有 12–48 小时出售赎回、右侧待处理提醒 |
| 14 地图操作/雇佣兵/经济 | 已实现 | 单击 1x / 双击 2x、到达自动暂停与暂停提示、酒馆雇佣兵招募、全局雇佣兵池、雇佣兵装备锁定、普通士兵换装、统一招募价格/工资/初始金币、Schema v9 |
| 14 后续：雇佣兵美术/战败/被俘 | 已实现 | Tier 罩袍与无赖骑士缨饰、独立招募 UI 与真实预览、战败空部队清理、玩家被俘、俘虏恢复、逃脱与 2 小时保护、顶栏 HP/被俘面板、Schema v10 |
| 14 后续：新游戏身份选择 | 已实现 | 独立全屏场景、两级纵向选择与滚动、点击身份即进入最终确认（无中间按钮）、动态路径展示、返回修改回一级并保留状态、最终确认前不初始化世界；无身份差异化初始化 |
| 15 大地图重建/势力/旗帜（2026-11-27） | 已实现 | 7780×6615 定义驱动地图、63 地点、46 道路、不规则边界/湖泊/山脉不可通行与 A* 绕行、旧存档回退；六方势力与附庸/民族；17 家族旗帜命名统一 |
| 15 后续：顶栏昼夜窗口（2026-11-27） | 已实现 | 顶栏正中 36×36 正方形遮罩；`UI_昼夜` 96×48 周期滚动；12:00/18:00/00:00/06:00 映射；暂停、倍速、跨午夜与读档同步 |
| 15 后续：时间流速 2 秒/小时（2026-11-27） | 已实现 | 1x 下 2 现实秒 = 1 游戏小时、48 秒/日；只改统一换算常量，暂停/倍速/移动/经济不变；离屏战斗与伤兵/俘虏小时常量同步 |

## 2. 已实现能力（按系统）

- **世界与时间**：`WorldContext` + `WorldSimulation`；`WorldTime` 固定 0.1 秒 tick；暂停原因按引用计数嵌套；世界从 1103-01-01 起，1x 为 2 秒/游戏小时（48 秒/游戏日）；`WorldMapDefinition` 驱动的 7780×6615 大地图、63 个地点、46 条道路与真实地形；旧存档按原 `world_size` 回退矩形地图。详见 [Time_System.md](../Systems/Time_System.md)、[World_Map_System.md](../Systems/World_Map_System.md)。
- **单位与部队**：`UnitData`/`PartyData` 纯数据；三级兵种（10/50、20/100、25/180）；五级战斗经验（新兵…百战精锐，阈值 100/300/500/1000，累计 HP +0/+5/+15/+30/+50）与等级独立于 tier；装备/马匹骑乘；玩家角色是普通 Unit；新游戏玩家部队 15 人（含 3 名弓箭手、4 名骑乘）；部队管理面板提供士兵/俘虏双列列表、战斗经验文本等级、坐骑与晋升操作，普通士兵可逐槽位换装，雇佣兵显示锁定提示且数据层拒绝换装；国王身份使用独立国王盔外观覆盖，不写入装备或存档。详见 [Unit_System.md](../Systems/Unit_System.md)、[Party_System.md](../Systems/Party_System.md)、[Mercenary_System.md](../Systems/Mercenary_System.md)。
- **战斗**：`BattleSession` 多战斗注册表；屏幕战斗与离屏 AI 战斗并行；离屏战斗每游戏小时结算；增援加入既有会话；1800×1024 战场；360°定向矩形攻击、多人围攻、实体最小间距；长矛近战在戳击有效帧结算伤害（每次攻击最多一次，前摇/戳击前半无伤害），受击白闪/受击动作/0.24s 僵直，统一 `unit_attack_started`/`unit_hit`/`unit_staggered` 事件；阵亡后先倒地再按 `CorpseConfig` 留存/淡出，尸体不参与战斗与结算；每个角色按脚底 Y 获得唯一 z 波段（`rank × 72`），全部非影子部件随角色整体排序，内部部件层级保持；有效伤害 +1 经验、击杀额外 +10；统一 `BattleResultData`；玩家撤退、控制权转移、经验/金币/战利品；按 tier 负伤、俘虏池分配；玩家侧战败时角色进入俘虏池；结算后无成员部队从世界移除，只剩伤兵的部队保留。详见 [Combat_System.md](../Systems/Combat_System.md)、[Wounded_Prisoner_System.md](../Systems/Wounded_Prisoner_System.md)。
- **大地图与 AI**：定义驱动地图、A* 折线移动（无障碍时保持直线）、边界/湖泊/山脉不可通行、跟随、视野、统一遭遇判定、玩家追击接触、战后冷却；玩家移动目标标记与动态虚线；商队/治安队/强盗/家族骑士 AI；多战斗标记与按 `side_index` 汇总；地点家族旗帜与停留部队旗帜条；WASD 自由镜头；左 Alt 详细悬浮；顶栏中央昼夜滚动窗口、紧贴其左侧的世界时间、金币/移速/部队人数图标数值与 ALT 明细；事件中心与家族入口；右侧事件框、小型待处理提醒与详情弹窗；建筑面板打开时仍可打开百科/部队/家族/背包/事件但禁用时间控制；采邑与冒险者招募统一浮动提示。详见 [World_Map_System.md](../Systems/World_Map_System.md)、[AI_System.md](../Systems/AI_System.md)。
- **经济与补给**：玩家/共享背包、金币、三级工资（1/3/7，**不自动扣除**）；每日收支预览复用工资与税收缓存（不结算）；马匹独立实例与逐匹交易；村庄（面包/草料）与城镇（含马匹）市场；每日补给结算与 NPC 低补给采购；城镇酒馆菜单嵌入地点面板，出售俘虏打开独立界面；俘虏价格按兵种 tier（5/20/60）与 NPC 领主统一价（100）；普通招募 Tier1 = 5、Tier3 = 400，采邑征召不耗金币；雇佣兵 Tier2 基础 35 / Tier3 80，经验加价 +0/+10/+30，坐骑 +30，日薪 4/9；新游戏初始金币 10000。价格唯一来源为 `RecruitmentConfig`，工资唯一来源为 `UnitConfig`。详见 [Inventory_Economy_System.md](../Systems/Inventory_Economy_System.md)、[Mercenary_System.md](../Systems/Mercenary_System.md)、[Mount_System.md](../Systems/Mount_System.md)、[Supply_System.md](../Systems/Supply_System.md)、[Wounded_Prisoner_System.md](../Systems/Wounded_Prisoner_System.md)。
- **政治与封地**：Noble/House/Kingdom 层级、领袖死亡选举、战争传播、统一关系查询与敌对势力聚合查询、强盗对所有政治家族敌对；封地所有权、统一征召授权 `is_authorized_owner()`、采邑储备/成组征召、村庄普通与贵族冒险者候选人、NPC 普通冒险者招募、税收缓存（**只缓存不结算**）；大地图家族面板只读展示家族贵族与封地。详见 [Political_Hierarchy_System.md](../Systems/Political_Hierarchy_System.md)、[Fief_Recruitment_System.md](../Systems/Fief_Recruitment_System.md)、[Adventurer_Recruitment_System.md](../Systems/Adventurer_Recruitment_System.md)。
- **雇佣兵**：独立于酒馆场景的全局池（初始 10、每 12 世界小时 +1、每酒馆容量 7、24 小时流转、2 小时旅行）；四类 Tier2/3 雇佣兵；独立招募界面左侧列表、右侧真实 `UnitVisual` 预览（装备/罩袍/头盔/缨饰/武器/马匹），预览单位不进入仓储；Tier2/3 使用等级罩袍，无赖骑士获得专属缨饰且雇佣兵不使用家族长矛；NPC 领主按低优先级检查、同价同薪招募；已招募雇佣兵显式标记并禁止换装。详见 [Mercenary_System.md](../Systems/Mercenary_System.md)。
- **玩家被俘与逃脱**：玩家侧战败后角色成为胜利方真实俘虏，HP/装备/数据保留，原部队禁用但保留为身份锚点；被俘期间镜头跟随押送方，左侧面板显示押送部队与 HP，部队面板只读、时间倍率仍可切换；所有俘虏按游戏小时独立恢复；满血后按配置间隔/概率逃脱，在押送方附近合法位置重建只含玩家的部队，并获得 2 游戏小时 AI 主动攻击豁免；顶栏 HP 实时读取真实 UnitData。详见 [Captivity_System.md](../Systems/Captivity_System.md)、[World_Map_System.md](../Systems/World_Map_System.md)、[AI_System.md](../Systems/AI_System.md)。
- **地点与村庄**：村庄小场景、头人对话、越界倒计时、采邑/候选人入口；贵族冒险者以步行人物+独立战马呈现，普通人选不受影响；城镇市场与酒馆；城镇/城堡仍无独立小场景。详见 [Village_System.md](../Systems/Village_System.md)、[Settlement_System.md](../Systems/Settlement_System.md)。
- **存档**：JSON + `schema_version`（当前 v10）、临时文件 + 校验 + `.bak` 替换、跨进程读写；保存五级经验/等级折算、领主身份、赎回记录、全局雇佣兵池/外观快照与 `is_mercenary` 身份、玩家被俘状态/恢复与逃脱计时/保护期；战斗会话与待确认俘虏份额不进入存档。详见 [Save_System.md](../Systems/Save_System.md)。
- **赎回与事件 UI**：NPC 领主出售后按世界时间等待 12–48 小时，生成可接受/取消的家族赎回请求；领主仍被玩家关押时按 3–12 小时生成可接受/拒绝的赎买请求。两种流程共用管理器与事件中心，但来源互斥、等待与拒绝规则不同。接受支付一次赎金并复用/重建领主部队；关押期请求在领主被出售、释放或转移后立即失效。大地图右侧纵向事件框与小型待处理提醒都只读取事件中心；详情弹窗逐帧校验，失效即关闭。详见 [Lord_Ransom_System.md](../Systems/Lord_Ransom_System.md)、[World_Map_System.md](../Systems/World_Map_System.md)。
- **新游戏身份选择**：主菜单「新游戏」通过 `SceneManager` 切换到独立全屏场景 `Scenes/Identity/identity_select.tscn`，主菜单场景被释放；一级按配置纵向生成贵族/平民，二级按类别纵向生成身份按钮（超过 3 个时只滚动选项区）并在上方展示背景故事，使用 `ButtonGroup`、金色边框与「当前选择」标签明确选中状态；点击任意具体身份立即进入最终确认页，没有「完成选择」等中间按钮；确认页按真实状态生成「类别 → 身份」路径，「返回修改」回到一级类别页并保留类别/身份；只有「最终确认」调用 `GameManager.start_new_game()` 并传递身份 ID/类别 ID，此前不创建 `WorldContext`、不启动世界时间、不写存档，当前不改变世界初始化数据。详见 [Identity_Selection_System.md](../Systems/Identity_Selection_System.md)。
- **UI/日志/百科**：世界日志最多 20 条并随 v3 起入档；百科改为一级分类（王国/家族/地点）→ 条目列表 → 二级详情，并显示敌对王国/敌对独立家族；事件中心聚合封地/补给/伤兵/冒险者/赎回等现有状态，任务栏暂为空；家族面板按队伍/封地只读展示并支持点击定位；大地图日期/时间段、地点面板、部队面板（成员/俘虏列表与缩略图）、背包、市场、内嵌酒馆菜单与独立出售窗口等程序化 UI。大地图左键单击/双击判定、玩家到达自动暂停与“已暂停”提示也已接入。详见 [World_Log_System.md](../Systems/World_Log_System.md)、[Encyclopedia_System.md](../Systems/Encyclopedia_System.md)。

## 3. 当前明确未实现 / 下一步

按优先级排列；判断“是否已经做了”仍须核对当前代码。

1. **阶段 7 剩余**：任务系统、训练、外交、城堡攻防、领地转让/继承、军团指挥、世界战争。
2. **经济闭环**：每日税收入账、工资定期扣除、人口/繁荣度自然变化、士气/逃兵、晋升凭证正式来源。
3. **村庄正式内容**：商店、头人作息、任务与好感度、多分支对话（普通兵员已通过冒险者招募接入）。
4. **城镇/城堡小场景**；村庄碰撞、城门与出口通道。
5. **装备与物品**：装备商店/获取途径、物品使用、战利品入包（普通士兵换装 UI 已实现）。
6. **寻路与地形**：大地图地形阻挡与绕行已完成；仍需做道路移动加成；战斗寻路、更复杂阵型与冲锋。
7. **招募与旧档**：用正式招募替换临时测试兵力；旧存档补员策略。
8. **正式美术与动画**：士兵/马匹正式素材、头盔/盾牌/缨饰/罩袍、弓与箭、地图与地点图标；受击与死亡已有程序化表现，正式逐帧/骨骼动画未做。
9. **高级战斗**：玩家手动选择加入方、键盘部队指令、士气、多部队协同、AI 撤退；玩家被俘/逃脱已实现，永久死亡后的重开/继承流程仍未做。
10. **存档后续**：自动存档、v1→v2 完整迁移、跨实体引用统一校验、随机种子入档。
11. **离屏战斗平衡**：伤兵/俘虏、士气、撤退、更长时限；小时中间态展示。
12. **输入与 UI 适配**：Input Map、手柄/触屏入口、UI 缩放主题、小场景镜头缩放/边缘拖动。
13. **政治/外交 UI**：宣战/议和、战争胜负与停战、附庸叛离、领地转让/继承。
14. **百科/日志/小地图**：百科搜索/排序/筛选（分类与详情跳转已实现）、日志过滤/点击定位、远离战场的小地图指示。

## 4. 当前风险与已知限制

> 只列仍然存在、会影响后续决策的限制；完整编号与处理状态见 [Known_Issues.md](Known_Issues.md)。

- `supply_manager_test` 有 1 条与本阶段无关的既有失败；阶段 13 未修改该测试或补给规则（KI534）。
- 离屏战斗只产生阵亡，小时中间态没有“伤兵”展示；48 小时上限按剩余战力强制判胜，没有士气/撤退（KI400/KI401）。
- 玩家加入离屏战斗后仍按阵营关系自动选边，不能手动选择加入方（KI331）。
- 大地图已有地形寻路，但道路不提供速度加成，路径缓存不持久化；战斗仍无寻路/地形阻挡，战斗单位在狭窄处可能拥挤（KI111/KI123/KI341）。
- 目标周围没有显式攻击槽位分配；大规模混战时仍可能在单一目标周围拥挤（KI348）。
- 玩家被俘/逃脱已实现，但只有玩家角色参与逃脱判定；原部队其他被俘成员不会自动归队，押送路线、赎金谈判与越狱道具未做。玩家角色永久阵亡后仍无复活/继承（KI122/KI339）。
- 大量美术仍为临时素材：头盔/盾牌贴图缺失、缨饰为空、弓/箭与部分地图图标为临时美术、马腿与长矛枢轴依赖当前素材尺寸（KI106/KI349/KI406/KI428/KI361/KI362/KI372/KI383）。
- 新游戏仍使用临时测试兵力；旧存档不会自动补员或扩编（KI121/KI127/KI405）。
- 经济未闭环：工资只统计不扣除、税收只缓存不入账、市场价格/库存固定、无供需波动（KI393/KI430/KI522）。
- 跨实体引用尚未统一校验：阵营、AI 路线、马匹实例唯一性等仍可能悬空（KI117/KI399/KI429）。
- 部分运行时状态不持久化：玩家追击焦点、战后冷却、遭遇拒绝锁、攻击意图、活动战斗会话、待确认俘虏份额（KI336/KI417/KI510/KI533）。
- 输入仍以鼠标与硬编码 WASD/数字键为主；触屏/手柄入口不足，部分确认面板没有键盘焦点（KI103/KI394/KI402/KI409/KI514/KI515）。
- 1920×1080 下 UI 使用原生像素字号，相对偏小，尚无缩放主题（KI370）。
- 63 地点布局、52 像素部队旗帜与重建地图美术仅通过自动化尺寸/数据断言验证，实际观感需非 headless 人工验收；瓦伊拉家族暂无专属旗帜，塞洛斯要塞与巴达洛斯要塞无旗帜（KI509/KI516）。
- 视觉家族 `FAMILY_*` 与政治家族 `HOUSE_*` 依赖 `banner_id` 映射，新家族漏配会回退到阵营关系（KI505）。
- 俘虏没有容量上限、守卫/忠诚、主动释放；售价按兵种 tier 与领主统一价（不按经验），城镇买家仍无经济模型（KI530/KI531/KI532）。
- 领主赎买/赎回是单一家族的固定请求：无多家族竞价、赎金谈判、额外拒绝冷却或外交影响；关押期拒绝后仅同一关押周期不再请求，接受后按现有家族模板补兵。关押登记在下一次世界 tick 完成，不是捕获瞬间的独立事件回调。
- NPC 补给采购不预留库存；多名 NPC 同时到达时按顺序扣减（KI527）。
- 贵族冒险者固定为三级 `infantry_veteran`，不做按家族/村庄的兵种或装备差异化；NPC 只招募普通冒险者，不招募贵族。
- 家族面板是只读入口，不包含成员调动、封地授予/转让、婚姻、继承或外交操作；贵族与战马分离表现仅通过 headless 尺寸/数据断言验证，实际观感需人工验收。
- 马匹实例只区分外观，不影响速度/属性/价格（KI525）。
- 雇佣兵池只有城镇酒馆可承载；当前默认世界城镇数量有限，多数雇佣兵会留在 `WAITING` 或被限制在容量上限；流转与 NPC 招募只按世界时间推进，没有大地图图标或合同期限。
- 雇佣兵装备锁定是系统规则，没有违约、解雇或合同谈判；NPC 招募不评估部队构成。
- 普通招募价格按 tier（5/400），Tier2 普通候选人的价格未定义（当前候选人生成不使用 Tier2）。
- 日历为每月 30 天的简化历法，无真实月份/闰年/季节（KI396）。
- 尚无任务系统：事件中心“已接取任务”始终为空，待处理事项只来自现有系统实时状态（KI517）。
- 事件中心不保存历史或“已处理”状态；条件消失后条目直接移除（KI518）。
- 移速 ALT 明细目前只有基础移速与大地图系数，移动结算尚无动态加成/惩罚（KI519）。
- 近战受击反馈当前只有白闪、身体后仰与僵直：没有受击位移、武器轨迹、命中音效资源；有效帧比例/僵直时长/白闪时长需结合实际观感继续调整。
- 死亡倒地/尸体留存/淡出已通过自动化状态与层级断言，但倒地重量感与淡出视觉效果无法在 headless 下验证；默认时长（倒地 0.55s / 留存 6.0s / 淡出 1.2s）仍为暂定平衡值。角色整体排序已用窗口像素探针验证无穿插，仍需在正式战斗中人工确认观感；排序名次上限 55，同屏角色更多时需压缩内部层级跨度或拆分绘制。退出时 `resources still in use` 告警与既有战斗场景测试一致。

## 5. 测试与验收

- **阶段 13 测试记录**：新增 `wounded_system_test`、`wounded_healing_test`、`stage13_village_candidates_test`、`stage13_world_map_ui_test`、`stage13_prisoner_test`、`stage13_prisoner_ui_flow_test`、`stage13_tavern_test`；相关回归测试已通过。
- **阶段 13 后续测试（2026-11-22）**：新增 `main_map_info_test`（顶栏金币/移速、普通/ALT 悬浮、建筑面板 UI 权限）、`event_center_test`（数据层、列表/详情、刷新、去重）；重写 `encyclopedia_ui_test`（一级分类/二级详情/敌对势力/动态刷新）；`time_calendar_test` 增加暂停计数嵌套断言。已运行并通过：上述测试，以及 `settlement_interaction_test`、`stage13_world_map_ui_test`、`party_panel_test`、`fief_adventurer_ui_test`。
- **经验/价格/赎回测试（2026-11-24）**：新增 `combat_experience_award_test`（伤害 +1、击杀 +11、无效伤害不发经验、只发给实际攻击者）、`lord_ransom_test`（出售等待/事件/接受一次/取消保留/失效关闭/部队重建/存档往返/异常恢复）、`save_migration_test`（v7→v8 等级折算、v8 不重复折算、缺失 `ransoms`）；更新 `combat_experience_test`、`stat_calculator_test`、`unit_manager_test`、`unit_party_serialization_test`、`unit_tier_wage_test`、`stage13_tavern_test`、`save_persistence_test`、`political_hierarchy_test`。上述测试已运行并通过。
- **贵族/NPC/家族测试（2026-11-24）**：新增 `noble_adventurer_recruitment_test`（贵族三级身份与真实战马、拥有者拒绝/允许、合并招募、防重复、不复活、存档往返、村庄步行人物+独立战马、NPC 普通冒险者招募与事件）、`family_panel_ui_test`（家族入口/暂停、默认部队页与空状态、玩家排除、正常/被俘/阵亡状态、真实部队摘要、封地分组与实时归属、点击定位）。已运行并通过：上述测试、`fief_adventurer_system_test`、`fief_adventurer_ui_test`、`stage13_village_candidates_test`。
- **国王盔/顶栏图标测试（2026-11-24）**：新增 `king_helmet_appearance_test`（统治家族领袖显示国王盔、国王盔期间隐藏缨饰、身份失效后恢复普通头盔与缨饰、同家族贵族/普通成员不显示、领袖更替与王国失效/统治家族变化后重建回退、数据未被改写、无普通头盔时不添加）；更新 `main_map_info_test`（金币/移速去文字前缀、三组图标+数值、部队人数实时统计与可战斗/伤员/俘虏悬浮、图标与数值共用条目悬浮）。已运行并通过：上述测试、`family_appearance_test`。
- **酒馆/关押期赎买/提醒测试（2026-11-24）**：更新 `stage13_tavern_test`（出售俘虏打开独立界面、城镇面板隐藏、关闭后回到城镇信息、不发生重复结算、原有酒馆入口仍可用）；更新 `lord_ransom_test`（关押期 3–12 小时请求、来源标签、接受一次并移出俘虏列表、拒绝结束事件且领主继续被关押、拒绝后仍可出售、出售后关押请求立即失效、详情打开期间状态变化后不能结算、关押期存档往返、右侧提醒随事件增减）。已运行并通过：上述测试、`king_helmet_appearance_test`、`main_map_info_test`。
- **地图/雇佣兵/经济测试（2026-11-25）**：新增 `mercenary_system_test`（初始池/类型/经验/价格、玩家招募与装备锁、失败回滚、增长与容量、NPC 低优先级、流转、存档往返、旧档初始化）；更新 `world_map_input_test`（单击/双击、到达自动暂停、暂停提示）、`party_panel_test`（普通士兵换装、雇佣兵锁定与数据层拒绝）、`stage13_tavern_test`（酒馆雇佣兵列表与原子招募）、`fief_adventurer_system_test` / `noble_adventurer_recruitment_test`（统一价格、Tier3 初始 2 级、AI 预算）、`save_migration_test` / `save_persistence_test` / `unit_tier_wage_test` / `party_economy_ui_test` / `lord_ransom_test` / `political_hierarchy_test`（Schema v9、工资 1/3/7、初始金币）。已运行并通过：上述测试，以及 `unit_manager_test`、`unit_party_serialization_test`、`mount_instance_test`、`mounted_unit_test`、`ai_manager_test`、`player_party_expansion_test`、`world_map_move_target_test`、`world_map_layout_test`、`town_market_ui_test`、`event_center_test`、`stage13_prisoner_test`、`milestone1_restart_test`、`stage13_world_map_ui_test`、`world_map_milestone6_test`、`settlement_interaction_test`、`main_menu_ui_test`、`fief_adventurer_ui_test`、`main_map_info_test`。
- **已修复的既有测试偏差（2026-11-25）**：`player_control_test` 的“玩家部队全员伤亡”改为校验“阵亡 + 伤兵 = 全员且存活者为 0”，与伤兵系统一致；`milestone2_flow_test` 补上攻击确认面板与战后俘虏选择（确认不接收）流程，再进入战斗与返回大地图。
- **雇佣兵美术/被俘测试（2026-11-25）**：新增 `captivity_escape_test`（战败被俘、装备/HP 保留、原部队禁用、押送方接收、被俘 UI/顶栏 HP/时间权限、俘虏小时恢复、存档往返、满血逃脱、单成员部队重建、落点距离/边界、2 小时保护、保护期后 AI 恢复拦截）；更新 `mercenary_system_test`（Tier 罩袍、无家族长矛、无赖骑士专属缨饰、预览/招募外观一致）、`stage13_tavern_test`（独立招募界面、真实预览、原子招募、关闭恢复）、`milestone2_flow_test` / `battle_scene_test` / `save_persistence_test`（战败空部队移除）、`save_migration_test` / `save_persistence_test` / `lord_ransom_test` / `political_hierarchy_test`（Schema v10）。已运行并通过上述测试，以及 `player_control_test`、`stage13_prisoner_test`、`world_map_input_test`、`main_map_info_test`、`stage13_world_map_ui_test`、`ai_encounter_flow_test`、`player_encounter_test`。
- **新游戏身份选择测试（2026-11-26）**：新增 `identity_selection_ui_test`（主菜单释放与全屏场景进入、全屏尺寸、一/二级纵向布局、故事切换、选中状态、点击身份立即进入确认页、不存在「完成选择/确认选择/下一步」中间按钮、动态路径与修改同步、返回修改回一级并保留状态、切换类别清空、最终确认前无世界/无存档、最终确认 ID 传递并进入 WorldMap）。已运行并通过：`identity_selection_ui_test`、`main_menu_ui_test`、`milestone1_flow_test`。已运行 `identity_select_probe` 并检查 1920×1080 与 1280×720 截图，二级页只有身份按钮与「返回」，布局无裁切。
- **近战有效帧/受击反馈测试（2026-11-26）**：新增 `melee_attack_timing_test`（前摇/戳击前半无伤害、有效帧一次结算、目标移出范围无白闪/僵直、有效帧前打断无伤害且取消动画、有效帧后伤害不撤销、僵直禁止移动/攻击并恢复、连续受击刷新不叠加、死亡优先、骑马白闪覆盖人马且材质按角色隔离、受击方向随朝向镜像、事件时序）；更新 `battle_scene_test` / `milestone2_flow_test` / `player_control_test`（手动推进到有效帧）、`combat_attack_rules_test`（僵直后反击）。已运行并通过：上述测试、`unit_controller_test`、`archer_battle_test`、`archer_scene_test`、`battle_reinforcement_test`、`battle_formation_test`、`battle_cluster_test`、`battle_retreat_test`。
- **死亡尸体/动态层级测试（2026-11-26）**：新增 `battle_corpse_visual_test`（倒地持续且明显区别于受击、留存/淡出由 `CorpseConfig` 驱动、淡出覆盖人物/武器/马匹/影子、清理无节点与影子残留、尸体留在 Characters 且位置稳定、尸体与存活角色全部非影子部件保持整体层级、前中后角色两两层级、骑乘与步兵、交叉移动翻转、波段间隔大于内部跨度、尸体不参与战斗与统计、胜利结算不受影响、朝向镜像、受击对照）；已运行并通过上述测试，以及 `battle_scene_test`、`player_control_test`、`milestone2_flow_test`、`melee_attack_timing_test`、`archer_scene_test`、`archer_battle_test`、`battle_reinforcement_test`、`battle_cluster_test`、`battle_formation_test`、`battle_result_delay_test`、`battle_retreat_test`。窗口像素探针 `Tests/_debug/sort_probe.tscn` 用真实骑乘/步兵模型验证：整体排序 0 处穿插，旧方案可复现 93 处。
- **大地图重建测试（2026-11-27）**：重写并运行 `world_map_layout_test`（7780×6615、63 地点唯一/间距 ≥250/边界内且避开地形、46 道路端点有效、边界/湖泊/山脉不可通行、山脉绕行、无障碍直线、最近地点对 6.0±0.5 小时、0.08 系数、六方势力/18 家族/18 贵族/23 部队/9 处所有权、旗帜资源与命名）。同时回归并通过：`milestone1_test`、`milestone1_flow_test`、`political_hierarchy_test`、`faction_bandit_hostility_test`、`encyclopedia_ui_test`、`king_helmet_appearance_test`、`family_appearance_test`、`settlement_interaction_test`、`world_map_milestone6_test`、`main_map_info_test`、`world_map_move_target_test`、`battle_reinforcement_test`、`battle_side_result_test`、`encounter_dialogue_ui_test`、`ai_manager_test`、`ai_supply_purchase_test`、`player_pursuit_encounter_test`、`wounded_system_test`、`lord_ransom_test`、`mercenary_system_test`。上述测试全部通过；退出时 `resources still in use` 为既有无害告警。
- **时间流速 2 秒/小时测试（2026-11-27）**：更新 `time_calendar_test`（2 秒/小时、48 秒/日、现实 1x/暂停/2x 累积实测）、`supply_manager_test`（48 秒/日）、`wounded_healing_test`、`offscreen_battle_hourly_test`、`world_map_layout_test`（行程 18 游戏小时）、`captivity_escape_test`（真实推进 1 个游戏小时）。已运行并通过：上述测试、`main_map_info_test`（昼夜 UI 同世界时间）、`world_map_milestone6_test`、`stage13_world_map_ui_test`、`lord_ransom_test`、`mercenary_system_test`、`wounded_system_test`；`supply_manager_test` 仅保留 KI534 既有失败。
- **已知失败**：`Tests/UnitTests/supply_manager_test.tscn` 的“NPC 记录 1 份草料缺口”断言未通过，原因与阶段 13 无关（KI534）。`Tests/UnitTests/unit_visual_test.tscn` 的马腿枢轴/贴图可见性断言仍失败。两项本轮均未修改。
- **未完成的验收**：非 headless 视觉验收（地点布局、44 像素旗帜、动画观感）尚未记录。
- **测试策略**：默认只运行验证本次修改的最小测试集（L1–L4），规则见 [03_Design_Conventions.md §10](../03_Design_Conventions.md#10-测试规范)。运行命令见 [Test_Commands.md](Test_Commands.md)。

## 6. 历史与查阅

| 想了解 | 看这里 |
|---|---|
| 各阶段的实现细节、历史测试清单、手动验收步骤 | [Archive/Status_History.md](../Archive/Status_History.md) |
| 每次重要变更的摘要 | [04_Change_Log.md](../04_Change_Log.md) |
| 为什么这样设计 | [Technical_Decisions.md](Technical_Decisions.md)（按 D 编号检索） |
| 还有哪些未决问题 | [Known_Issues.md](Known_Issues.md) |
| 阶段规划与历史验收记录 | [02_Development_Roadmap.md](../02_Development_Roadmap.md)（规划时读取） |
