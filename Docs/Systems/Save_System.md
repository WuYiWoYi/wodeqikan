# 存档系统

**核心脚本：** `Scripts/Autoload/save_manager.gd`、`Scripts/Core/Save/save_data.gd`
**状态：** 保存/读取闭环、成员关系校验、士兵成长/装备/骑乘/工资恢复、玩家档案与物品数量、地点场景路径、AI/跟随字段兼容已实现；Schema 仍为 v2

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

## 3. Schema v2

```json
{
  "schema_version": 2,
  "project_version": "0.2.0",
  "saved_at": "2026-11-20T22:30:00",
  "world": {
    "world_id": "WORLD_000001",
    "created_at": "2026-11-20T22:00:00",
    "size": [3000.0, 2000.0]
  },
  "time": {
    "world_elapsed_seconds": 1234.5,
    "world_base_speed": 1.0
  },
  "id_counters": { "WORLD": 1, "UNIT": 5, "PARTY": 4, "SETTLEMENT": 4 },
  "player": {
    "party_id": "PARTY_000001",
    "gold": 120,
    "inventory": ["weapon_sword_01", "mount_horse_01"],
    "inventory_counts": { "weapon_sword_01": 1, "mount_horse_01": 1 }
  },
  "world_state": {},
  "scene_state": {},
  "units": { "UNIT_000001": { } },
  "parties": { "PARTY_000001": { } },
  "lords": {},
  "settlements": { "SETTLEMENT_000001": { } },
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
| `time` | 世界累计时间与基础倍率 |
| `id_counters` | 各 ID 前缀的当前计数 |
| `player` | 玩家部队 ID、金币与物品栏；`inventory` 为物品 ID 列表，`inventory_counts` 为数量字典；旧存档缺失 `inventory_counts` 时每个条目按 1 件处理 |
| `world_state` | 世界级标记（预留） |
| `scene_state` | 局部状态（初期不使用） |
| 各实体表 | `{ 实体 ID: 实体数据 }` |

`units` 与 `parties` 以实体 ID 为键；`PartyData.member_unit_ids` 保存成员 ID 列表。
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
- `PlayerProfile`（金币 / 物品列表 / 物品数量）存放在 `player` 字典中；`WorldContext` 在保存/读档时同步。
- `inventory_counts` 是向后兼容的增量字段：旧存档只有 `inventory` 时，每个物品按 1 件恢复；没有升级 Schema。
- 马匹装备保存在 `UnitData.equipment["MOUNT"]`。读档重算时 `is_mounted` 由 MOUNT 装备重新派生，不信任旧存档中单独的 `is_mounted` 标记；没有 MOUNT 的旧单位按步兵恢复。
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

- 战斗中禁止保存：`GameManager.save_game()` 在 `world_context.battle_manager.current_battle != null` 时返回 `ERR_BUSY`；该规则同样覆盖 NPC 对 NPC 的离屏战斗。
- `BattleSession` / `BattleUnitState` / `BattleParticipant` 不进入存档；战斗期间不序列化实时 HP、位置、战斗侧与索敌目标。
- 离屏战斗是临时世界状态，读档后不会恢复；读档统一回到大地图。
- 暂停原因不存档；读档后由新的进入状态建立。
- 读档统一回到大地图，不恢复小场景或战斗。
- 当前不支持 Schema v1 的完整恢复（旧存档缺少 `world_id`，会被判定为无效）。

## 9. 版本与迁移

- `schema_version` 每次结构不兼容变更时加 1。
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

校验失败处理：逐条 `push_error`，`load_from_save_data()` 返回 `false`，不自动修复或改写存档（D025）。

后续补充：

- 所有实体 ID 在各自仓储内唯一（读档已对重复 ID 报错并跳过）。
- 引用的阵营/地点/领主存在（统一跨实体校验入口待建立）。
- 玩家部队位置在世界边界内。

## 11. 实现状态

| 项 | 状态 |
|---|---|
| `SaveData` Schema v2 | 已实现 |
| JSON 写入/读取 | 已实现 |
| 临时文件 + 备份替换 | 已实现 |
| 槽位列表/删除 | 已实现 |
| 存档头/最新存档查询 | 已实现 |
| 聚合 `WorldContext → SaveData` | 已实现 |
| 恢复 `SaveData → WorldContext` | 已实现 |
| 版本检查 | 已实现 |
| 士兵-部队成员关系校验 | 已实现（D025） |
| 士兵等级/经验/装备往返 | 已实现（沿用 Schema v2） |
| 马匹装备 / 骑乘状态往返 | 已实现：MOUNT 随装备保存，`is_mounted` 读档重算派生；旧存档按步兵兼容 |
| 玩家物品数量 `inventory_counts` | 已实现：增量字段，旧存档每个条目按 1 件恢复，无 Schema 升级 |
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
| 战斗中禁止保存 | 已实现（`ERR_BUSY`，含离屏战斗） |
| v1 → v2 完整迁移 | 未完成 |
| 自动存档 | 未实现 |
| 其他跨实体引用校验 | 未实现（KI117） |

## 12. 待确认

- 自动存档频率与触发点。
- 多存档槽 UI 排序规则（当前按 `saved_at` 倒序）。
- 是否压缩/加密存档。
- 战斗、对话、场景切换中的保存限制。
