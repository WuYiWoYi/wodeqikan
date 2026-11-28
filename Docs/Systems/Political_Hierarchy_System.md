# 贵族 / 家族 / 王国体系

**状态：** 阶段 8 已交付；2026-11-27 补全为六方势力（统治家族 + 附庸家族 + 民族），并改为家族独占领地所有权、17 家族 51 名指定贵族
**相关代码：** `Scripts/Entities/Noble/`、`Scripts/Entities/House/`、`Scripts/Entities/Kingdom/`、`Scripts/Core/World/noble_manager.gd`、`house_manager.gd`、`kingdom_manager.gd`、`faction_manager.gd`、`world_initializer.gd`
**存档：** Schema v11（政治字段自 v5 起为 `nobles` / `houses` / `kingdoms`，保留 `lords` 兼容副本；v10 追加 `people_name` 等可选字段；v11 为金币与村庄经济字段）

---

## 1. 层级

```text
王国 KingdomData
├── 统治家族 id（ruling_house_id）
├── 国王 noble id（king_noble_id）
├── 附庸家族 id 列表（vassal_house_ids）
└── 敌对王国 id 列表（enemy_kingdom_ids）

家族 HouseData
├── 领袖 noble id（leader_noble_id）
├── 贵族 id 列表（noble_ids）
├── 封地 id 列表（fief_ids）
├── 所属王国 id（kingdom_id）
├── 宗主家族 id（overlord_house_id）
├── 旗帜/视觉家族 id（banner_id）
└── 玩家家族标记（is_player_house）

贵族 NobleData（extends LordData）
├── 名称、family/house、爵位 rank
├── 宗主 noble id（liege_noble_id）
├── 家族领袖标记 is_house_leader
├── 国王标记 is_king
├── 指挥部队 party_id
└── 存活 is_alive
```

每个贵族独立指挥一支部队；附庸家族保留自己的领袖、贵族、部队与封地。

## 2. 爵位

| 值 | 名称 | 说明 |
|---|---|---|
| 1 | `KNIGHT` | 骑士；玩家初始爵位 |
| 2 | `BARON` | 男爵；巴里/墨西西等家族领袖 |
| 3 | `DUKE` | 公爵 |

## 3. 校验规则

`NobleData.validate()` / `HouseData.validate()` / `KingdomData.validate()` 与初始化器共同保证：

- ID 唯一；引用对象存在。
- 贵族不得以自己为宗主；宗主链不得成环。
- `is_house_leader` 必须与家族 `leader_noble_id` 一致。
- `is_king` 必须与王国 `king_noble_id` 一致。
- 一个家族最多属于一个王国。
- 家族/王国的领袖/国王必须存活；否则进入待定状态。

初始化失败（缺引用、重复 ID、归属不一致）会阻止新游戏创建。

## 4. 领袖死亡与选举

- 通过 `NobleManager.kill_noble(lord_id)` 标记死亡。
- 若死者是家族领袖：在存活贵族中按 **爵位降序 → 稳定 ID 升序** 选举新领袖，并更新 `is_house_leader`。
- 若死者是国王：先重选家族领袖，再将该领袖设为王国国王，并同步 `is_king`。
- 没有可选举贵族时：家族 `pending_leader = true`；王国 `pending_king = true`，不崩溃、不自动灭国。
- 直接修改 `is_alive` 绕过 `kill_noble()` 不会触发选举（见 Known_Issues）。

## 5. 封地与征召

- `SettlementData.owner_house_id` 是政治所有权的唯一字段；`family_id` 只决定地点旗帜，不参与授权。个人所有者字段已删除。
- 初始世界由 `_family_specs()` 显式配置 17 家族的 59 处领地；塞洛斯要塞、巴达洛斯要塞无主。重建地图不按位置推断所有权。
- 家族领袖、男爵、骑士或称号变化都不改变所有权；所有权只随 `owner_house_id` 变化。
- 仅村庄可征召采邑。
- `FiefRecruitmentManager.is_authorized_owner(settlement, lord_id)` 是唯一授权判断，条件：
  - 请求者是存活贵族，且 `noble.house_id == settlement.owner_house_id`。
  - 同家族全部成员（领袖、男爵、骑士、普通成员）权限一致，没有个人所有者旁路。
- `can_recruit()` 先调用该授权判断；地点面板、事件中心与头人对话共用同一结果，不各自复制规则。
- 贵族冒险者招募也调用同一 `is_authorized_owner()`，不另写贵族权限规则；所有权变更立即影响下一次招募判断。
- 家族面板复用 `HouseManager.get_house_nobles()` 与 `SettlementData.owner_house_id` 实时读取部队和封地，不建立第二套家族成员或封地缓存。

## 6. 关系与战争

`FactionManager` 提供统一查询：

| 方法 | 说明 |
|---|---|
| `get_party_relation(a, b)` | 两支部队的关系 |
| `get_house_relation(a, b)` | 两个家族的关系 |
| `are_houses_hostile(a, b)` | 家族是否敌对 |
| `is_party_hostile(a, b)` | 部队是否敌对 |
| `is_party_friendly(a, b)` | 部队是否友好 |
| `is_party_neutral(a, b)` | 部队是否中立 |
| `get_hostile_kingdoms_for_house(house_id)` | 某家族（含其所属王国）的敌对王国列表 |
| `get_hostile_independent_houses_for_kingdom(kingdom_id)` | 与某王国敌对的独立家族列表 |
| `get_hostile_independent_houses_for_house(house_id)` | 与某家族敌对的独立家族列表 |

敌对聚合查询只组合上述统一关系判定，不维护第二套敌对数据：

- 属于王国的家族，其敌对王国来自 `KingdomManager.get_enemy_kingdoms(kingdom_id)`。
- 独立家族按 `get_house_relation()` 逐一检查王国成员家族，只有明确敌对才计入。
- 结果按 ID 稳定排序，供百科等只读 UI 使用。

优先级：

1. 双方都有政治家族：以家族/王国关系为准。
2. 一方或双方无家族：回退到阵营关系。
3. 玩家未加入王国时默认中立；只有显式设置敌对方时才会敌对。贵族身份可能因所属家族而自动与王国同阵营。
4. 王国开战会把敌对关系传播到双方所有成员家族。

部队的政治身份解析：

- `PartyData.leader_noble_id` → `NobleData.house_id`。
- 若无贵族，则通过 `PartyData.family_id` → `HouseManager.get_house_by_banner_id()` 映射视觉家族到政治家族。
- 都没有时使用 `PartyData.faction_id`。

### 6.1 以玩家为中心的阵营关系（2026-11-27）

`FactionManager` 新增统一接口，返回 `PlayerRelation.ALLIED / NEUTRAL / HOSTILE`：

| 方法 | 说明 |
|---|---|
| `get_player_relation_for_house(house_id)` | 家族与玩家的关系 |
| `get_player_relation_for_party(party_id)` | 部队与玩家的关系 |
| `get_player_relation_for_settlement(settlement_id)` | 地点与玩家的关系（权威归属 `owner_house_id`） |
| `get_player_relation_for_kingdom(kingdom_id)` | 王国与玩家的关系 |

判定顺序：

1. 玩家家族本身 → 同阵营。
2. 玩家主动宣战记录（家族或王国）→ 敌对。该记录优先于王国关系。
3. 玩家未加入王国 → 其余目标中立，不从其他王国外交推导同阵营。
4. 目标家族与玩家所属王国相同 → 同阵营。
5. 玩家所属王国与目标家族王国处于战争 → 敌对。
6. 其余中立。

- `get_house_relation()` 在任一方是玩家家族时改为委托上述接口，因此 AI、遭遇、战斗与百科自动获得同一结果。
- 玩家本人部队仍为 `PartyData.player_party_id` 特判；玩家所属家族、加入的王国与当前政治身份是三个不同概念，不互相替代。
- 玩家是国王属于“玩家家族所属王国”的特例：其成员家族与建筑通过王国归属判定为同阵营，不通过玩家个人家族 ID 推导。
- 身份配置决定玩家开局政治归属：`identity.family_id` → `HOUSE_*`，王国由 `HouseData.kingdom_id` 推导。`identity.independent_house = true` 时初始化跳过该家族对应的王国注册，家族保持 `kingdom_id` 为空，玩家只是家族领袖。
- 文化、出生地点、地点视觉旗帜 `family_id`、建筑/部队显示名称都不参与阵营判定；无政治家族或无归属时默认中立，不默认绿色。
- 地点阵营只认 `owner_house_id`；无主地点保持中立，即使其视觉旗帜属于某家族或王国。

### 6.2 玩家主动攻击宣战

- 玩家主动攻击入口 `WorldMap.begin_battle_with_party()` 成功创建战斗后调用 `FactionManager.declare_player_hostility_against_party(target_party_id)`。
- 加入友军既有战斗不是主动攻击，不触发宣战。
- 目标无政治家族（强盗、商队等）不产生家族/王国宣战，继续使用原阵营关系。
- 目标属于王国 A：玩家与目标家族敌对，同时记录王国 A 为玩家敌对王国；王国 A 所有成员家族与所属建筑敌对。玩家自身无需拥有王国。
- 目标为独立家族：只有该家族敌对，不扩展到其他家族，不产生王国宣战。
- 玩家已有王国且目标属于其他王国时，同时调用 `KingdomManager.declare_war()` 建立正式王国战争；双方王国成员家族按既有规则互相敌对。
- 玩家主动宣战记录由 `FactionManager.to_dict()` / `load_from_dict()` 保存到 `SaveData.factions` 的 `player_hostile_house_ids` / `player_hostile_kingdom_ids`（增量字段，缺失时为空，不升级 Schema）。
- 关系变化后广播 `EventBus.faction_relations_changed`；大地图据此刷新部队外环与建筑名称底板，不每帧重算政治关系。
- 当前尚未实现玩家加入/退出王国、成为国王的运行时流程；这些流程落地时需广播同一事件以刷新 UI。

## 7. 视觉家族与政治家族

- `FAMILY_*` 是 `FamilyConfig` 的视觉配置 ID（旗帜、罩袍、缨饰、长矛）。
- `HOUSE_*` 是政治实体 ID。
- `HouseData.banner_id` 保存对应的 `FAMILY_*`。
- 读档迁移通过 `banner_id` 把旧存档中的 `FAMILY_*` 解析为现有 `HOUSE_*`，避免重复创建家族。
- 地点旗帜取自 `SettlementData.family_id`，政治归属只取自 `owner_house_id`；两者可以不同。例：灰石堡垒旗帜为伯克纳家族（`FAMILY_BURKNANIA`），所有权属于巴里家族。
- 新增家族时若不配置旗帜，关系解析会回退到阵营关系。

## 8. 初始世界（六方势力，2026-11-27）

| 王国 | 民族 | 统治家族 | 统治者 | 附庸家族 |
|---|---|---|---|---|
| 伯克纳王国 `KINGDOM_BURKNANIA` | 多拉曼人 | `HOUSE_BURKNANIA` | 奥东·德·伯克纳 | 奥德斯特、埃克托、巴夫勒、巴里 |
| 弗拉尼王国 `KINGDOM_FRANI` | 布吉多人 | `HOUSE_FRANI` | 奥利维耶 | 丁达尼、康利亚、米奇奇 |
| 洛里亚克王国 `KINGDOM_LORIAK` | 洛里斯人 | `HOUSE_LORIAK` | 菲利普 | 奥林、墨西西、罗斯维克 |
| 泰纳伯公国 `KINGDOM_TAINA` | 蒙卡人 | `HOUSE_TAINA` | 贝洛夫 | 无 |
| 瓦勒蒙联盟 `KINGDOM_VALEMON` | 蒙卡人 | `HOUSE_VALEMON` | 卢卡 | 克里卡 |
| 瓦伊拉伯国 `KINGDOM_VAILA` | 布吉多人 | `HOUSE_VAILA` | 瓦尔登 | 无 |

- 初始六方全部和平，`enemy_kingdom_ids` 为空；战争只由显式 `declare_war()` 产生，并传播到双方成员家族。
- 统治者的展示称号统一为“国王/统治者”，不按公国/联盟/伯国改写；爵位字段仍按配置保留（伯克纳/弗拉尼/洛里亚克/泰纳为 `DUKE`，瓦伊拉/瓦勒蒙为 `BARON`）。
- 当前共 17 个正式家族、51 名 NPC 贵族、56 支部队（51 名贵族各 1 支 + 玩家 + 商队 + 3 支强盗）；默认贵族身份（埃克托次子）下为 52 名贵族、56 支部队。
- 每位 NPC 贵族独立指挥一支家族部队（`<简称>骑士`，非领袖使用 `<贵族名>骑士`），不再是一个家族仅一名贵族。
- 初始 59 处地点有家族所有者，塞洛斯要塞、巴达洛斯要塞无主；所有权只由 `owner_house_id` 表达，家族领袖、爵位与称号变化不影响所有权。
- 不创建 `HOUSE_PLAYER`。贵族身份复用正式家族（埃克托/丁达尼/瓦伊拉）并创建玩家贵族；平民身份不创建贵族记录，`get_player_house()` / `get_player_noble()` 返回 `null`。
- 贵族身份若 `starts_as_house_leader`，玩家接管家族领袖；`independent_house = false` 时同时成为该王国国王，`true` 时跳过该王国注册、家族保持独立（瓦伊拉领袖：世界为 5 个王国 + 独立瓦伊拉家族）。否则保留原 NPC 领袖并让玩家效忠。
- 重建地图的位置、旗帜、民族与附庸名称不会自动生成封地、战争或外交关系；所有所有权均来自 `_family_specs()` 的 Settlement ID → 家族 ID 配置。

## 9. 持久化

Schema v5 新增：

- `nobles: { noble_id: {...} }`
- `houses: { house_id: {...} }`
- `kingdoms: { kingdom_id: {...} }`

玩家个人宣战记录从 2026-11-27 起写入既有的 `factions` 容器：

- `factions.player_hostile_house_ids`：玩家主动攻击后保持敌对的家族 ID。
- `factions.player_hostile_kingdom_ids`：玩家个人宣战的王国 ID。
- 旧存档缺失该容器时视为空表；静态阵营关系与默认外交仍由各管理器重建。

保留 `lords` 作为兼容副本，`lord_manager` 与 `noble_manager` 指向同一实例。读档会：

1. 恢复政治实体。
2. 校验引用/循环/归属。
3. 通过 `banner_id` 解析家族。
4. 重建部队、封地与关系链接。

## 10. 未实现

- 领地转让/继承。
- 战争胜负结算与完整外交 UI；`KingdomManager.declare_war()` / `end_war()` 只切换敌对关系并传播到成员家族。
- 附庸叛离、家族外交与关系 UI。
- 玩家晋升爵位或成为国王的流程。
- 绕过 `kill_noble()` 的外部修改不会触发选举。
