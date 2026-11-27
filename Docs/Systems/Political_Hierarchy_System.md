# 贵族 / 家族 / 王国体系

**状态：** 阶段 8 已交付；2026-11-27 补全为六方势力（统治家族 + 附庸家族 + 民族）
**相关代码：** `Scripts/Entities/Noble/`、`Scripts/Entities/House/`、`Scripts/Entities/Kingdom/`、`Scripts/Core/World/noble_manager.gd`、`house_manager.gd`、`kingdom_manager.gd`、`faction_manager.gd`、`world_initializer.gd`
**存档：** Schema v10（政治字段自 v5 起为 `nobles` / `houses` / `kingdoms`，保留 `lords` 兼容副本；v10 追加 `people_name` 等可选字段）

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

- `SettlementData.owner_house_id` / `owner_noble_id` 表达政治所有权；`family_id` 只决定地点旗帜，不参与授权。
- 初始世界只有 9 处地点有明确所有者：巴里、灰石堡垒、墨西西、北境村、伯克纳尼亚、伯克纳、奥林德斯堡、奥林、青禾村；其余地点无主。重建地图不按位置补写所有权。
- 仅村庄可征召采邑。
- `FiefRecruitmentManager.is_authorized_owner(settlement, lord_id)` 是唯一授权判断，条件：
  - `settlement.owner_noble_id == lord_id`，或
  - 请求者是 `owner_house_id` 家族的领袖。
- `can_recruit()` 先调用该授权判断；地点面板、事件中心与头人对话共用同一结果，不各自复制规则。
- 贵族冒险者招募也调用同一 `is_authorized_owner()`，不另写贵族权限规则；所有权变更立即影响下一次招募判断。
- 家族面板复用 `HouseManager.get_house_nobles()` 与 `SettlementData.owner_house_id` / `owner_noble_id` 实时读取部队和封地，不建立第二套家族成员或封地缓存。

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
3. 玩家家族默认中立；只有显式设置敌对方时才会敌对。
4. 王国开战会把敌对关系传播到双方所有成员家族。

部队的政治身份解析：

- `PartyData.leader_noble_id` → `NobleData.house_id`。
- 若无贵族，则通过 `PartyData.family_id` → `HouseManager.get_house_by_banner_id()` 映射视觉家族到政治家族。
- 都没有时使用 `PartyData.faction_id`。

## 7. 视觉家族与政治家族

- `FAMILY_*` 是 `FamilyConfig` 的视觉配置 ID（旗帜、罩袍、缨饰、长矛）。
- `HOUSE_*` 是政治实体 ID。
- `HouseData.banner_id` 保存对应的 `FAMILY_*`。
- 读档迁移通过 `banner_id` 把旧存档中的 `FAMILY_*` 解析为现有 `HOUSE_*`，避免重复创建家族。
- 地点旗帜取自 `SettlementData.family_id`，政治归属取自 `owner_house_id` / `owner_noble_id`；两者可以不同。例：灰石堡垒旗帜为伯克纳家族（`FAMILY_BURKNANIA`），所有权属于巴里家族。
- 新增家族时若不配置旗帜，关系解析会回退到阵营关系。

## 8. 初始世界（六方势力，2026-11-27）

| 王国 | 民族 | 统治家族 | 统治者 | 附庸家族 |
|---|---|---|---|---|
| 伯克纳王国 `KINGDOM_BURKNANIA` | 多拉曼人 | `HOUSE_BURKNANIA` | 伯克纳国王 | 奥德斯特、埃克托、巴夫勒、巴里 |
| 弗拉尼伯国 `KINGDOM_FRANI` | 布吉多人 | `HOUSE_FRANI` | 弗拉尼伯爵 | 丁达尼、康利亚、米奇奇 |
| 瓦伊拉王国 `KINGDOM_VAILA` | 布吉多人 | `HOUSE_VAILA` | 瓦伊拉国王 | 无 |
| 洛里亚克王国 `KINGDOM_LORIAK` | 洛里斯人 | `HOUSE_LORIAK` | 洛里亚克国王 | 奥林、墨西西、罗斯维克 |
| 泰纳公国 `KINGDOM_TAINA` | 蒙卡人 | `HOUSE_TAINA` | 泰纳公爵 | 无 |
| 瓦勒蒙联盟 `KINGDOM_VALEMON` | 蒙卡人 | `HOUSE_VALEMON` | 瓦勒蒙盟主 | 克里卡 |

- 初始六方全部和平，`enemy_kingdom_ids` 为空；战争只由显式 `declare_war()` 产生，并传播到双方成员家族。
- 当前共 18 个家族（17 个 NPC 家族 + 玩家家族）、18 名贵族（每 NPC 家族一名领袖 + 玩家贵族）、23 支部队。
- 每个 NPC 家族恰好一名贵族、一支由该贵族指挥的家族骑士部队（`<简称>骑士`）；统治家族的领袖为国王/公爵/盟主，非统治家族领袖为 `<简称>领主`。
- 玩家属于 `HOUSE_PLAYER`，骑士爵位，独立且中立。
- 旧世界确认的 9 处封地所有权保留；重建地图的位置、旗帜、民族与附庸名称不会自动生成封地、战争或外交关系。

## 9. 持久化

Schema v5 新增：

- `nobles: { noble_id: {...} }`
- `houses: { house_id: {...} }`
- `kingdoms: { kingdom_id: {...} }`

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
