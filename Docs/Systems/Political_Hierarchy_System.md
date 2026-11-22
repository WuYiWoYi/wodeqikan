# 贵族 / 家族 / 王国体系

**状态：** 阶段 8 已交付
**相关代码：** `Scripts/Entities/Noble/`、`Scripts/Entities/House/`、`Scripts/Entities/Kingdom/`、`Scripts/Core/World/noble_manager.gd`、`house_manager.gd`、`kingdom_manager.gd`、`faction_manager.gd`、`world_initializer.gd`
**存档：** Schema v5（`nobles` / `houses` / `kingdoms`，保留 `lords` 兼容副本）

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

- `SettlementData.owner_house_id` / `owner_noble_id` / `family_id` 表达所有权。
- 仅村庄可征召采邑。
- `FiefRecruitmentManager.can_recruit()` 授权条件：
  - `settlement.owner_noble_id == lord_id`，或
  - 请求者是 `owner_house_id` 家族的领袖。
- 地点面板与头人对话共用该授权结果。

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
- 新增家族时若不配置旗帜，关系解析会回退到阵营关系。

## 8. 初始世界

| 王国 | 统治家族 | 国王 | 附庸 | 封地 |
|---|---|---|---|---|
| 伯克纳尼亚王国 `KINGDOM_BURKNANIA` | `HOUSE_BURKNANIA` | 伯克纳国王 | 墨西西家族 | 伯克纳尼亚（城镇）、伯克纳（村庄）、墨西西两处 |
| 奥林王国 `KINGDOM_OLIN` | `HOUSE_OLIN` | 奥林国王 | 巴里家族 | 奥林德斯堡（城堡）、奥林（村庄）、巴里两处 |

- 两王国处于战争状态。
- 玩家属于 `HOUSE_PLAYER`，骑士爵位，独立且中立。
- 每个国王、普通贵族、家族领袖均拥有独立部队。

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
- 宣战/议和/停战与战争胜负。
- 附庸叛离、家族外交与关系 UI。
- 玩家晋升爵位或成为国王的流程。
- 绕过 `kill_noble()` 的外部修改不会触发选举。
