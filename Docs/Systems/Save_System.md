# 存档系统

**核心脚本：** `Scripts/Autoload/save_manager.gd`、`Scripts/Core/Save/save_data.gd`
**状态：** 保存/读取闭环、成员关系校验、士兵成长/装备/骑乘/工资恢复、伤兵与俘虏归属、玩家档案与物品数量、地点场景路径、AI/跟随字段兼容、领主/封地/采邑/冒险者、贵族/家族/王国、村庄/城镇市场库存、马匹个体、NPC 背包与金币、补给结算日与治疗结算小时持久化已实现；Schema v7

---

## 1. 目标

- 只保存持久化数据，不保存场景节点。
- 使用唯一 ID 关联实体。
- 存档具备版本号，支持未来迁移。
- 使用 JSON，保持可读、可调试。
- 写入失败不能破坏已有有效存档。

## 2. 存档位置与格式

```text
user://saves/<slot>.json
```

Windows 下实际路径为 Godot 的 `user://` 目录，不在项目资源目录内。

## 3. Schema v7

```json
{
  "schema_version": 7,
  "project_version": "0.2.0",
  "saved_at": "2026-11-22T22:30:00",
  "world": {
    "world_id": "WORLD_000001",
    "created_at": "2026-11-20T22:00:00",
    "size": [5000.0, 3000.0]
  },
  "time": {
    "world_elapsed_seconds": 1234.5,
    "world_base_speed": 1.0,
    "supply_last_settled_day": 8,
    "healing_last_settled_hour": 80
  },
  "id_counters": {
    "WORLD": 1, "UNIT": 5, "PARTY": 4, "SETTLEMENT": 5,
    "LORD": 3, "CANDIDATE": 2
  },
  "player": {
    "party_id": "PARTY_000001",
    "player_lord_id": "LORD_000001",
    "player_unit_id": "UNIT_000005",
    "gold": 120,
    "inventory": ["weapon_sword_01", "bread"],
    "inventory_counts": { "weapon_sword_01": 1, "bread": 14 },
    "mount_instances": [
      { "instance_id": "MOUNT_000001", "equipment_id": "mount_horse_01",
        "coat_style_id": "brown", "saddle_style_id": "saddle_03", "display_name": "" }
    ]
  },
  "world_state": {},
  "scene_state": {},
  "world_log": { "entries": [] },
  "units": { "UNIT_000001": { } },
  "parties": { "PARTY_000001": { } },
  "lords": { "LORD_000001": { } },
  "nobles": { "LORD_000001": { } },
  "houses": { "HOUSE_PLAYER": { } },
  "kingdoms": { "KINGDOM_BURKNANIA": { } },
  "settlements": { "SETTLEMENT_000001": { } },
  "markets": {
    "SETTLEMENT_000006": {
      "settlement_id": "SETTLEMENT_000006",
      "stock": { "bread": 50, "fodder": 50 },
      "mount_instances": [],
      "initialized_items": ["bread", "fodder", "mount_horse_01"]
    }
  },
  "factions": {},
  "quests": {}
}
```

| 字段 | 说明 |
|---|---|
| `schema_version` | 存档结构版本；小于等于 0 或高于当前版本直接拒绝 |
| `project_version` | 游戏版本，用于问题定位 |
| `saved_at` | 保存时间（真实时间，可排序） |
| `world` | 世界 ID、创建时间、世界尺寸 |
| `time` | 世界累计时间、基础倍率、`supply_last_settled_day`（上次补给结算日）与 `healing_last_settled_hour`（上次伤兵治疗结算小时）；缺失时分别取存档时刻所在日/小时，避免读档立即重复结算 |
| `id_counters` | 各 ID 前缀的当前计数 |
| `player` | 玩家部队 ID、玩家领主 ID、玩家角色单位 ID、金币与物品栏；`inventory` 为物品 ID 列表，`inventory_counts` 为可堆叠数量，`mount_instances` 为马匹实例数组；旧存档缺失 `inventory_counts` 时每个条目按 1 件处理 |
| `world_state` | 世界级标记（预留） |
| `scene_state` | 局部状态（初期不使用） |
| `world_log` | 最近 20 条世界日志；缺失时为空历史，超过 20 条时读档立即裁剪 |
| `markets` | 村庄/城镇市场 `{ settlement_id: { settlement_id, stock, mount_instances, initialized_items } }`；缺失时按商品配置初始化，已有库存/实例不重置 |
| `lords` | 领主表 `{ lord_id: LordData }`；Schema v4 新增，v5 继续保留为兼容副本 |
| `nobles` | 贵族表 `{ noble_id: NobleData }`；Schema v5 新增 |
| `houses` | 家族表 `{ house_id: HouseData }`；Schema v5 新增，含 `banner_id` 映射 |
| `kingdoms` | 王国表 `{ kingdom_id: KingdomData }`；Schema v5 新增 |
| 各实体表 | `{ 实体 ID: 实体数据 }` |

`units` 与 `parties` 以实体 ID 为键；`PartyData.member_unit_ids` 保存成员 ID 列表，`PartyData.prisoner_unit_ids` 保存本部队关押的俘虏 ID 列表（v7）。
士兵数据层已接入，`units` 可以为空（没有士兵的部队仍然是合法状态），也可以包含任意数量的独立士兵。

士兵持久化字段（沿用 v2，未新增 Schema）：

| 字段 | 说明 |
|---|---|
| `unit_id` / `config_id` / `display_name` | 身份与实例名称 |
| `is_player_character` | 玩家角色身份；旧存档缺失时默认 false |
| `level` / `exp` | 经验等级与经验 |
| `wage` | 每日工资；旧存档缺失时用 -1 哨兵，读档重算按当前兵种等级配置补全 |
| `equipment` | 槽位字符串 → 装备 ID；`MOUNT` 存在即骑乘 |
| `is_mounted` | 骑乘状态缓存；读档时由 `equipment` 的 `MOUNT` 槽重新派生，旧存档缺失或没有 MOUNT 时按步兵处理 |
| `current_hp` | 当前生命；读档保留 |
| `status` | `ACTIVE` / `WOUNDED` / `DEAD`；缺失或越界时按 HP 推断，不默认为死亡 |
| `prisoner_owner_party_id` | 俘虏归属部队 ID；缺失时为空 |
| `sold_to_settlement_id` | 已出售地点 ID；缺失时为空 |
| `max_hp` / `attack` / `attack_interval` / `move_speed` / `attack_range` | 最终属性缓存；读档后按配置重算覆盖 |
| `faction_id` / `current_party_id` | 阵营与归属 |
| 招募来源字段 | `joined_at_game_time` / `recruit_source` / `recruit_settlement_id` / `origin_faction_id` |

`UnitConfig` / `EquipmentConfig` / `ItemConfig` 是静态模板，不进入存档；读档时由 `WorldContext.register_static_configs()` 从 `Data/Units`、`Data/Equipment`、`Data/Items` 重新注册。

`SettlementData` 新增 `scene_path` 字段（村庄小场景路径），旧存档缺失时为空；大地图对村庄回退到默认模板。该字段为增量字段，不升级 Schema。

## 4. 序列化规则

- 实体类提供 `to_dict()` / 静态 `from_dict()`。
- `Vector2` → `[x, y]`；`Color` → HTML 字符串；枚举 → `int`。
- 缺失字段使用安全默认值。
- `PartyData` 自 2026-11-21 起包含 `ai_type` / `ai_route_index` / `ai_route_settlement_ids` / `sight_range`；旧存档缺失时使用安全默认值，不升级 Schema。
- 阶段 4 仅扩展枚举值（`BANDIT` / `GUARD`、`FOLLOW_PARTY`），没有新增持久化字段；`current_order` 与 `current_target_id` 继续保存跟随指令。
- `PartyData.attack_intent`、待处理遭遇、遭遇/交互 ID、战斗拒绝记录与暂停原因都是运行时状态，不进入存档；读档后 AI 会在下一次决策重新建立攻击意图。
- `FactionManager` 的关系表是静态规则，不进入存档；新游戏与读档都会重建默认关系。
- `PlayerProfile`（金币 / 物品列表 / 可堆叠数量 / 马匹实例）存放在 `player` 字典中；`WorldContext` 在保存/读档时同步。
- 玩家与 NPC 背包使用同一结构：`inventory_counts` 只含可堆叠物品，`mount_instances` 逐匹保存马匹；旧存档只有 `inventory` 时每个条目按 1 件恢复，马匹数量确定性迁移为实例（D146）。
- 马匹装备保存在 `UnitData.equipment["MOUNT"]` 与 `UnitData.mount_instance`。读档重算时 `is_mounted` 由 MOUNT 装备重新派生，不信任旧存档中单独的 `is_mounted` 标记；只有装备 ID 而无实例的旧单位按 `unit_id + equipment_id` 确定性补建实例；没有 MOUNT 的旧单位按步兵恢复。
- NPC 部队的 `PartyData.gold` 与 `inventory_counts` / `mount_instances` 随部队一起保存，供补给采购使用。
- `supply_last_settled_day` 保存在 `time` 下；旧存档缺失时以 `world_elapsed_seconds` 所在游戏日为起点，避免读档立即扣粮。
- `healing_last_settled_hour` 保存在 `time` 下；旧存档缺失时以 `world_elapsed_seconds` 所在游戏小时为起点，避免读档补算或重复治疗。
- 伤兵 `status = WOUNDED` 与 HP=0 一起恢复；俘虏的 `prisoner_owner_party_id` 与部队 `prisoner_unit_ids` 双向保存。读档后 `sanitize_prisoner_ownership()` 以成员身份优先、去重并清理悬空归属，反复读档不增殖。
- 战斗中的 `BattleSession`、`BattleResultData`、控制权、当前 SceneTime 与战后临时状态不进入存档。
- 战斗经验/奖励在结算时写入 `UnitData.exp` / `PlayerProfile`，随之后的存档保存；不会保存“待领取奖励”。
- 新增字段均使用安全默认值，未升级 Schema。
- 不保存场景节点、节点路径、资源实例引用。
- 存档聚合由 `WorldContext.to_save_data()` 完成。
- 存档恢复由 `WorldContext.load_from_save_data()` 完成。

## 5. 保存流程

```text
UI 点击保存
  → GameManager.save_game(slot)
      ├── 校验 WorldContext 有效
      └── WorldContext.to_save_data()
            ├── 世界 ID / 尺寸 / 创建时间
            ├── TimeManager 世界时间与基础倍率
            ├── IdGenerator 计数
            ├── 玩家部队 ID
            ├── UnitManager / PartyManager / SettlementManager
            └── 其他实体表
  → SaveManager.save_game(slot, save_data)
      ├── 写入 <slot>.json.tmp
      ├── 读取并校验临时 JSON 与版本
      ├── 旧存档重命名为 <slot>.json.bak
      ├── 临时文件替换为正式文件
      └── 删除备份
```

失败时返回明确错误码，UI 显示失败提示；旧存档在替换成功前不会被覆盖。

## 6. 读取流程

```text
Continue / Load Game
  → SaveManager.load_game(slot)
      ├── 读取 JSON
      ├── 校验 schema_version
      └── SaveData.from_dict()
  → GameManager.load_game()
      ├── 销毁旧 WorldContext
      ├── TimeManager.start_session()
      ├── 创建新 WorldContext
      ├── WorldContext.load_from_save_data()
      │     ├── 恢复 IdGenerator 计数
      │     ├── 恢复 Unit / Party / Settlement
      │     ├── 校验士兵-部队双向归属（失败则返回 false）
      │     ├── 恢复世界 ID / 尺寸 / 玩家部队
      │     └── 重建地图边界
      ├── TimeManager.restore_world_time()
      └── 进入 WorldMap
```

Continue 与 Load Game 调用同一个 `GameManager.load_game(slot)`，没有第二套恢复逻辑。

跨进程验证由 `milestone1_restart_test.tscn` 完成：一次进程保存并退出，另一次进程读取并校验位置、时间、倍率、实体数量与 ID。

### 6.1 士兵属性恢复规则

读档以当前静态配置为准，不把存档中的最终属性缓存当成唯一权威：

```text
1. UnitManager.load_from_dict() 恢复身份、等级、经验、装备、current_hp
2. WorldContext 调用 recalculate_all_stats()
3. 按 UnitConfig（当前等级成长）+ EquipmentConfig 重算最终属性
4. current_hp 只做上限 clamp，不自动回满
```

- 旧存档缺少 `display_name` / `level` / `exp` / `equipment` 时使用安全默认值；名称缺失时回填兵种模板名称。
- 骑乘状态不单独信任 `is_mounted`：读档重算后由 `equipment["MOUNT"]` 派生；缺少 MOUNT 时恢复为步兵，但等级/经验/身份/HP 不变。
- 装备 ID 无效或槽位不匹配时：`push_error` 报告、从装备字典中清理，不参与属性计算；读档继续。
- 兵种配置未注册时：报告错误，保留存档中的属性缓存作为降级结果，不阻止读档。
- 等级超过 `max_level` 时按 `max_level` 计算成长。

本次未新增持久化字段，因此没有升级 Schema。

## 7. Continue 与存档列表

- `SaveManager.get_save_info(slot)`：读取存档头（时间、版本、世界 ID、是否有效），不反序列化全部实体。
- `SaveManager.list_save_infos()`：按 `saved_at` 倒序返回可解析的存档头。
- `SaveManager.get_latest_save_slot()`：返回最新有效存档，供 Continue 使用。
- 主菜单 Load Game 列表显示存档名与保存时间。
- 只有 `valid == true` 的存档会出现在列表中。
- 损坏 JSON 不会进入有效存档列表。

## 8. 存档限制

- 战斗中禁止保存：`GameManager.save_game()` 在 `world_context.battle_manager.has_any_active_battles()` 为真时返回 `ERR_BUSY`；该规则覆盖玩家屏幕战斗和所有 NPC 对 NPC 的离屏战斗，避免静默丢失进行中的战斗。
- `BattleSession` / `BattleUnitState` / `BattleParticipant` 不进入存档；战斗期间不序列化实时 HP、位置、战斗侧与索敌目标。
- 离屏战斗是临时世界状态，读档后不会恢复；读档统一回到大地图。
- 暂停原因不存档；读档后由新的进入状态建立。
- 世界日志历史自 Schema v3 起进入存档，只保存最近 20 条；读档超过 20 条时立即裁剪；UI 滚动位置不保存。
- 村庄/城镇市场库存与马匹实例保存在 `markets`；旧存档缺失时由 `MarketManager.ensure_markets()` 初始化一次，已有库存与 `initialized_items` 不重置。
- 补给结算日 `supply_last_settled_day` 随 `time` 保存；读档后从该日继续，不会重复结算同一天。
- 读档统一回到大地图，不恢复小场景或战斗。
- 当前不支持 Schema v1 的完整恢复（旧存档缺少 `world_id`，会被判定为无效）。

## 9. 版本与迁移

- `schema_version` 每次结构不兼容变更时加 1。
- 当前版本 7；`SaveData.from_dict()` 接受 1..7。
- v3 → v4 新增 `lords` 与 `player.player_lord_id` / `player.player_unit_id`；旧存档缺失时由 `WorldContext` 补玩家领主身份，不伪造封地归属。
- v4 → v5 新增 `nobles` / `houses` / `kingdoms` 与地点 `owner_house_id` / `owner_noble_id`；旧存档缺失时由 `lords`、`family_id` 与 `banner_id` 补建最小政治视图，并通过固定 ID 去重。
- v5 → v6 新增马匹实例、NPC 背包与金币、市场马匹实例/`initialized_items`、`supply_last_settled_day`；读取 v5 及更早存档时执行一次补给初始化（只补完全没有任何补给记录的部队）与确定性马匹迁移。
- v6 → v7 新增伤兵状态、俘虏归属与列表、`healing_last_settled_hour`、村庄候选人字段；读取 v6 及更早存档时补安全默认值并执行一次俘虏归属清洗。
- 读取旧版本时执行迁移；`SaveData.from_dict()` 已保留 v1 → v2 入口，但完整字段迁移尚未完成。
- 读取高于当前版本的存档直接拒绝。
- 迁移逻辑集中在 `SaveData.from_dict()`，禁止散落。

## 10. 数据校验

当前已校验：

- `WorldContext.is_valid_world()`：世界 ID、玩家部队、地点数量。
- 存档版本范围。
- 临时文件 JSON 可解析且版本一致。
- 损坏存档不进入有效列表。
- 士兵-部队成员关系（`PartyManager.validate_membership_consistency()`）：
  - 成员 ID 都能找到 `UnitData`；
  - 非空 `current_party_id` 都能找到 `PartyData`；
  - 一个士兵最多属于一支部队；
  - `current_party_id` 与成员列表双向一致；
  - 同一部队成员列表内无重复项。
- 士兵装备引用：读档重算时检查装备 ID 存在且槽位匹配；无效引用报告并清理（不降级为错误属性）。
- 领主数据（`LordManager.validate()`）：
  - `party_id` 非空时必须指向存在的部队；
  - 同一部队最多一个领主；
  - 玩家领主最多一个且 `is_player_lord == true`。
- 封地所有权（`WorldContext.validate_world_ownership()`）：
  - 每个非空 `owner_noble_id` 必须指向存在的贵族；`owner_house_id` 必须存在且与贵族家族一致；
  - `owner_lord_id` 兼容字段与 `owner_noble_id` 一致；
  - `player_lord_id` 非空时必须存在且为玩家贵族。
- 政治层级（`NobleManager` / `HouseManager` / `KingdomManager`）：
  - 贵族/家族/王国 ID 唯一；
  - 宗主、家族、王国引用存在；宗主链无循环、无自指；
  - `is_house_leader` / `is_king` 与领袖/国王字段一致；
  - 一个家族最多属于一个王国；
  - 领袖/国王必须存活，否则标记待定。

校验失败处理：逐条 `push_error`，`load_from_save_data()` 返回 `false`，不自动修复或改写存档（D025）。

后续补充：

- 所有实体 ID 在各自仓储内唯一（读档已对重复 ID 报错并跳过）。
- 引用的阵营/地点/领主存在（统一跨实体校验入口待建立）。
- 玩家部队位置在世界边界内。

## 11. 实现状态

| 项 | 状态 |
|---|---|
| `SaveData` Schema v7 | 已实现 |
| JSON 写入/读取 | 已实现 |
| 临时文件 + 备份替换 | 已实现 |
| 槽位列表/删除 | 已实现 |
| 存档头/最新存档查询 | 已实现 |
| 聚合 `WorldContext → SaveData` | 已实现 |
| 恢复 `SaveData → WorldContext` | 已实现 |
| 版本检查 | 已实现 |
| 士兵-部队成员关系校验 | 已实现（D025） |
| 士兵等级/经验/装备往返 | 已实现（沿用现有字段） |
| 马匹装备 / 骑乘状态往返 | 已实现：MOUNT 随装备保存，`is_mounted` 读档重算派生；旧存档按步兵兼容 |
| 玩家物品数量 `inventory_counts` | 已实现：增量字段，旧存档每个条目按 1 件恢复，无 Schema 升级 |
| 村庄/城镇市场库存 `markets` | 已实现：按地点恢复，含马匹实例与 `initialized_items` |
| 马匹独立实例 `mount_instances` | 已实现（v6）；旧档数量确定性迁移 |
| NPC 背包与金币 | 已实现（v6）；随 `parties` 保存 |
| 补给结算日 `supply_last_settled_day` | 已实现（v6） |
| 伤兵状态与 HP | 已实现（v7）：`status` / `current_hp` 一并恢复 |
| 俘虏归属与列表 | 已实现（v7）：`prisoner_owner_party_id` ↔ `prisoner_unit_ids`，读档幂等清洗 |
| 已售出状态 `sold_to_settlement_id` | 已实现（v7） |
| 治疗结算小时 `healing_last_settled_hour` | 已实现（v7）；读档不补算 |
| 村庄初始候选人 | 已实现（v7）；随候选数据表保存 |
| 士兵工资 `wage` | 已实现：增量字段，旧存档缺失时按当前兵种配置补全 |
| 地点小场景路径 `SettlementData.scene_path` | 已实现：增量字段，旧存档为空并回退默认村庄模板 |
| 物品配置 `ItemConfig` | 已实现：静态注册，不进入存档 |
| 读档属性重算与 HP 修正 | 已实现（D033）；包含骑乘移速与移动攻击加成 |
| 强盗/治安队 AI 枚举兼容 | 已实现（枚举扩展，无 Schema 升级） |
| 跟随指令往返 | 已实现（`current_order` / `current_target_id`） |
| 攻击意图 / 遭遇临时状态 | 不持久化（读档后由 AI 重新建立） |
| 玩家角色身份 `is_player_character` | 已实现（旧存档默认 false） |
| 玩家金币 / 物品栏 | 已实现（`player` 字典，旧存档默认空） |
| 战斗结果 / 控制权 / 待领取奖励 | 不持久化；结算后直接写回单位与玩家档案 |
| 领主表 `lords` / 玩家领主 ID | 已实现（Schema v4，旧存档补玩家领主） |
| 封地归属 `owner_lord_id` | 已实现（读档校验领主存在） |
| 采邑储备/补充计时/人口/繁荣度/税收缓存 | 已实现（随地点保存） |
| 冒险者候选人与刷新计时 | 已实现（随地点保存，含外观） |
| 战斗中禁止保存 | 已实现（`ERR_BUSY`，含离屏战斗） |
| v1 → v2 完整迁移 | 未完成 |
| 自动存档 | 未实现 |
| 其他跨实体引用校验 | 未实现（KI117） |

## 12. 待确认

- 自动存档频率与触发点。
- 多存档槽 UI 排序规则（当前按 `saved_at` 倒序）。
- 是否压缩/加密存档。
- 战斗、对话、场景切换中的保存限制。

## 13. 阶段 6 家族/外观增量字段（Schema 仍为 v2）

本阶段字段均为“存在则读取、缺失则安全默认”的增量字段，不提升 Schema 版本，也不需要迁移：

| 实体 | 新增字段 | 默认值 |
|---|---|---|
| `UnitData` | `family_id` | `""` |
| `UnitData` | `appearance` | `{}` |
| `PartyData` | `family_id` | `""` |
| `PartyData` | `leader_unit_id` | `""` |
| `PartyData` | `ai_patrol_points` | `[]` |
| `SettlementData` | `family_id` | `""` |

- `appearance` 内全部是字符串/整数，可直接 JSON 序列化；不保存 `Resource`、`Texture2D` 或 `Color` 对象。
- 旧存档单位没有外观时保持原有阵营外观，不会在读档时重新随机。
- 新游戏由 `WorldInitializer` 生成外观；读档路径不生成新部队，因此不会重复创建家族/新强盗。
- 家族与外观静态配置（`Data/Families`、`Data/Appearance`）不进入存档。

## 14. 统一部队架构增量字段（Schema 仍为 v2）

| 实体 | 新增字段 | 默认值 | 旧存档处理 |
|---|---|---|---|
| `PartyData` | `control_type` | `AI`（玩家为 `PLAYER`） | 按 `player_party_id` 推断，不覆盖已有值 |
| `PartyData` | `party_kind` | `GENERIC` | 按玩家 ID、家族、阵营、`ai_type` 推断 |
| `PartyData` | `banner_texture_path` | `""` | 空值回退家族旗帜/样式默认 |

- 读取顺序：`PartyManager.load_from_dict()` → `PartyManager.apply_runtime_defaults(player_party_id)` → 地点/引用校验。
- 推断只补类型/控制权字段，不修改成员、位置、路线、路线索引、领袖或战斗状态。
- `attack_intent`、`current_target_id`、`focus_party_id` 与待处理遭遇仍不存档。
- 静态遭遇对白配置 `Data/Encounters/encounter_text_config.tres` 不进入存档。

## 15. 玩家初始部队扩编（Schema 仍为 v2）

- 新游戏玩家部队为 15 人（1 玩家角色 + 5 民兵 + 6 职业步兵，其中 4 名骑乘 + 3 弓箭手）；成员数据仍走现有 `UnitData` / `PartyData` 序列化，不新增 Schema 字段。
- `WorldInitializer._populate_player_party()` 在 `party.member_unit_ids` 非空时直接返回；旧存档读档不会补兵或重复生成。
- 旧存档保留原人数、位置、装备和成员关系；扩编仅作用于新游戏。

## 16. Schema v3 与世界日志（阶段 6 后续）

- `SaveData.CURRENT_SCHEMA_VERSION = 3`；新增顶层 `world_log`，内容为 `{"entries": [...]}`。
- `WorldContext.to_save_data()` 写入 `world_log_manager.to_dict()`；`load_from_save_data()` 调用 `load_from_dict()` 恢复。
- 日志条目包含事件类型、世界时间、显示文本与元数据；上限仍为 100 条。
- 不要求兼容 Schema v2；`SaveData.from_dict()` 仍接受 1..3，v1 → v2 的浅迁移入口保留。

### 16.1 读档状态清理

`WorldContext.load_from_save_data()` 在 `apply_runtime_defaults()` 之后调用 `PartyManager.sanitize_loaded_runtime_state()`：

| 情况 | 处理 |
|---|---|
| `battle_state == IN_BATTLE / RETURNING` 且无活动战斗 | 无成员 → `DISABLED`；否则 `AVAILABLE` |
| `attack_intent` / `focus_party_id` / `engagement_cooldown_until` | 清零 |
| `current_order == BATTLE` | 改为 `NONE` |
| `current_target_id` 指向不存在部队 | 清空；`FOLLOW_PARTY` 指令清除，移动停止 |
| 领袖不属于本部队或单位不存在 | 成员关系校验失败，拒绝读档 |

### 16.2 仍不持久化

- 活动 `BattleSession`（`active_battles` 中任意一场，含 AI 离屏战斗）；有战斗时 `GameManager.save_game()` 直接拒绝。
- 战斗中的临时 `BattleUnitState`、站位、追逐焦点与遭遇拒绝锁。
- 静态家族/外观/遭遇对白配置。

## 17. 弓箭手与远程派生字段（Schema 仍为 v3）

- 弓箭手没有独立实体或存档类型：`unit_id`、`config_id`、等级/经验/属性、装备、部队归属与控制权状态全部走现有 `UnitData` / `PartyData` 序列化。
- `UnitData.to_dict()` / `from_dict()` 持久化 `attack_type`、`body_height`、`projectile_texture_path`、`projectile_speed`、`projectile_arc_height`；旧存档缺失时使用安全默认值（近战、48 身高、默认弹道参数），读档后由 `UnitManager.recalculate_all_stats()` 按当前武器配置重算校正。
- 弓装备本身以 `equipment["WEAPON"] = "weapon_bow_01"` 保存，不复制武器 Resource。
- 飞行中的 `ArrowProjectile`、`ProjectileManager` 与攻击冷却均为战斗场景瞬时状态，不进入存档；战斗中禁止保存。
- 新游戏只在 `party.member_unit_ids` 为空时创建 3 名弓箭手；读档不会补兵、不会重复生成，也不向已有存档额外发放弓箭手。
- 阵亡弓箭手与其他阵亡成员一样由战斗结算移出部队，读档不会恢复。

## 18. Schema v4：领主、封地与冒险者（阶段 7）

### 18.1 新增/扩展字段

| 位置 | 字段 | 说明 |
|---|---|---|
| 顶层 | `lords` | `{ lord_id: LordData }` |
| `player` | `player_lord_id` | 玩家领主 ID；与玩家角色分离 |
| `player` | `player_unit_id` | 玩家角色单位 ID |
| `SettlementData` | `owner_lord_id` | 封地归属领主 |
| `SettlementData` | `population` / `prosperity` | 采邑成本与补充周期因子 |
| `SettlementData` | `tax_base` / `tax_income_per_day` | 税收基数与缓存 |
| `SettlementData` | `fief_recruitment_stock/capacity/elapsed` | 采邑储备与补充计时 |
| `SettlementData` | `adventurer_candidates` | 候选人数组（含外观、状态、关联单位） |
| `SettlementData` | `adventurer_refresh_elapsed` | 候选人刷新计时 |
| `LordData` | `is_player_lord` / `current_target_settlement_id` | 玩家身份与战略目标 |

### 18.2 读档顺序与兼容

1. 单位 → 部队 → `apply_runtime_defaults()` → 运行时状态清理。
2. `lord_manager.load_from_dict(save.lords)`。
3. `settlement_manager.load_from_dict(save.settlements)`。
4. 旧存档缺少玩家领主时补建；不伪造地点归属。
5. 对每个地点调用采邑/候选人 `initialize_settlement()`：修正容量/边界，保留存档中的储备与计时。
6. 重算单位属性与税收缓存。
7. 成员关系校验 → 领主校验 → 封地所有权校验；任一失败拒绝读档。

### 18.3 不持久化

- AI 的 `RECRUITING` 状态与移动目标是运行时战略状态，读档后由 `AIManager` 重新决策。
- 候选人被招募但尚未离开村庄的状态可以持久化（`RECRUITED_PENDING_DEPARTURE`）；如果存档发生在离开村庄前，读档后仍会显示“已招募”记录，离开时再清理。
- 征集过程中的临时创建单位若事务失败会被立即回滚，不会进入存档。
- 静态经济配置 `Data/Settlements/settlement_economy_config.tres` 不进入存档。

## 19. Schema v5：贵族、家族与王国（阶段 8）

### 19.1 新增字段

| 位置 | 字段 | 说明 |
|---|---|---|
| 顶层 | `nobles` | `{ noble_id: NobleData }`；贵族、爵位、宗主、领袖/国王、部队与存活 |
| 顶层 | `houses` | `{ house_id: HouseData }`；领袖、贵族、封地、王国、宗主、`banner_id`、玩家家族 |
| 顶层 | `kingdoms` | `{ kingdom_id: KingdomData }`；统治家族、国王、附庸、敌对、颜色、活动 |
| `SettlementData` | `owner_house_id` | 政治家族归属 |
| `SettlementData` | `owner_noble_id` | 贵族归属；与 `owner_lord_id` 同步 |
| `PartyData` | `leader_noble_id` | 指挥该部队的贵族 |
| 世界 | `world.size` | 新游戏为 5000×3000 |

### 19.2 读档顺序与兼容

1. 单位 → 部队 → `apply_runtime_defaults()`。
2. `house_manager.load_from_dict(save.houses)`。
3. `noble_manager.load_from_dict(save.nobles)`；`lord_manager` 指向同一实例。
4. `kingdom_manager.load_from_dict(save.kingdoms)`。
5. 旧存档只有 `lords` 且无政治表时，按旧领主补建最小家族/贵族视图，不伪造王国。
6. 地点 `owner_house_id` / `owner_noble_id` 缺失时由 `family_id` → `banner_id` 解析现有家族；旧 `owner_lord_id` 同步到 `owner_noble_id`。
7. 校验贵族/家族/王国引用、循环、爵位、领袖/国王标记与封地归属；失败拒绝读档。
8. 重建部队 → 贵族 → 家族 → 王国的链接，并刷新地块归属。

### 19.3 不持久化

- 战斗中的增援标记（`is_reinforcement` 等）属于 `BattleUnitState` 运行时字段，不进入存档；战斗进行中禁止保存。
- 百科面板层级、滚动位置、选中王国/家族均为 UI 状态。
- 增援提示队列与淡入淡出计时不持久化。
- 固定 ID 家族/王国（`HOUSE_*`、`KINGDOM_*`）由初始化器显式注册，不消耗 `IdGenerator` 计数。

## 20. Schema v6：马匹个体、NPC 补给与市场扩展（阶段 12）

### 20.1 新增/扩展字段

| 位置 | 字段 | 说明 |
|---|---|---|
| `time` | `supply_last_settled_day` | 上次补给结算的游戏日；-1/缺失表示尚未结算 |
| `player` | `mount_instances` | 玩家背包中的马匹实例数组 |
| `player` | `inventory_counts` | 只保存可堆叠物品；马匹不再写入 |
| `PartyData` | `inventory_counts` / `mount_instances` | NPC 自有背包 |
| `PartyData` | `gold` | NPC 自有金币，补给采购使用 |
| `PartyData` | `supply_bread_shortage` / `supply_fodder_shortage` | 上次结算缺口（只读展示） |
| `markets` | `mount_instances` | 市场待售马匹实例 |
| `markets` | `initialized_items` | 已初始化商品，防止售罄后补满 |
| `UnitData` | `mount_instance` | 已装备马匹实例（外观随实例） |

### 20.2 读档顺序与兼容

1. 恢复单位与部队，包括 NPC 金币、背包与马匹实例。
2. `MarketManager.ensure_markets()` 按地点补齐缺失商品，保留已有库存/实例/`initialized_items`。
3. `schema_version < 6` 时执行一次 `_migrate_party_supplies()`：只为完全没有补给记录的部队补起步物资与少量金币，已管理过补给的部队不补发。
4. 解析 `supply_last_settled_day`；缺失时使用 `world_elapsed_seconds` 所在游戏日。
5. `SupplyManager.set_player_party_id()` 后从该日继续，避免读档立即扣粮或重复扣同一天。
6. 旧档马匹数量（玩家、市场、单位装备）使用 `create_deterministic()` 迁移，反复读取结果一致。

### 20.3 不持久化

- 未确认的交易预览（`TradeSession`）不进入存档。
- NPC 采购的临时目标、重试计时与采购状态为运行时字段，读档后由 `AIManager` 重新决策。
- 低补给提示浮字、`EventBus` 订阅关系与暂停原因不持久化。

## 21. Schema v7：伤兵、俘虏与治疗进度（阶段 13）

### 21.1 新增/扩展字段

| 位置 | 字段 | 说明 |
|---|---|---|
| `UnitData` | `status` | `ACTIVE` / `WOUNDED` / `DEAD`；伤兵 HP=0 且保留成员身份 |
| `UnitData` | `prisoner_owner_party_id` | 俘虏归属部队；与 `current_party_id` 互斥 |
| `UnitData` | `sold_to_settlement_id` | 已出售地点；非空表示退出玩家控制 |
| `PartyData` | `prisoner_unit_ids` | 本部队关押的俘虏 ID 列表；读档去重 |
| `time` | `healing_last_settled_hour` | 上次伤兵治疗结算的游戏小时；-1/缺失表示尚未结算 |
| 村庄候选数据 | 身份/归属/状态 | 初始候选人与刷新候选共用现有字段，v7 存档完整保留 |

### 21.2 读档顺序与兼容

1. 恢复 `UnitData`，读取 `status` / `current_hp` / 俘虏与售出字段；缺失字段按 HP 与空字符串补齐。
2. 恢复 `PartyData`，包括 `member_unit_ids` 与 `prisoner_unit_ids`；重复 ID 去重。
3. 调用 `PartyManager.sanitize_prisoner_ownership()`：
   - 同时是成员的单位以成员身份为准，从俘虏列表移除；
   - 清理不存在单位/部队的引用；
   - 同一单位被多个部队关押时保留稳定顺序中的第一个；
   - 重复调用结果一致。
4. 解析 `healing_last_settled_hour`；缺失时使用 `world_elapsed_seconds` 所在游戏小时，不补算离线小时。
5. 恢复村庄候选人并校验其归属村庄存在；不重新随机生成，避免读档增殖。
6. `schema_version < 7` 时只补默认值，不重建任何 Unit，不重复发放俘虏。

### 21.3 不持久化

- `BattleSession`、`BattleResultData`、待玩家确认的俘虏挂起记录与结算预览属于运行时状态；任何战斗期间禁止存档（KI533）。
- `PrisonerSelectionPanel` / `TavernPanel` 的预览选择、UI 层级与暂停原因为运行时状态。
- `WoundedConfig` / `HealingConfig` / `PrisonerPriceConfig` 是静态 `.tres` 配置，不进入存档。
