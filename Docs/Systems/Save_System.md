# 存档系统

**核心脚本：** `Scripts/Autoload/save_manager.gd`、`Scripts/Core/Save/save_data.gd`
**状态：** JSON 读写基础接口已实现，聚合与恢复未完成

---

## 1. 目标

- 只保存持久化数据，不保存场景节点。
- 使用唯一 ID 关联实体。
- 存档具备版本号，支持未来迁移。
- 初期使用 JSON，保持可读、可调试。

## 2. 存档位置与格式

```text
user://saves/<slot>.json
```

Windows 下实际路径由 Godot 的 `user://` 决定。

## 3. Schema v1

```json
{
  "schema_version": 1,
  "project_version": "0.1.0",
  "saved_at": "2026-11-20T12:00:00",
  "time": {
    "world_elapsed_seconds": 1234.5,
    "world_base_speed": 1.0
  },
  "id_counters": { "UNIT": 12, "PARTY": 3, "LORD": 2 },
  "player": {},
  "world_state": {},
  "scene_state": {},
  "units": { "UNIT_000001": { } },
  "parties": { "PARTY_000001": { } },
  "lords": { "LORD_000001": { } },
  "settlements": { "SETTLEMENT_000001": { } },
  "factions": { "FACTION_000001": { } },
  "quests": {}
}
```

字段说明：

| 字段 | 说明 |
|---|---|
| `schema_version` | 存档结构版本；读取高于当前版本的存档直接拒绝 |
| `project_version` | 游戏版本，用于问题定位 |
| `saved_at` | 保存时间（真实时间） |
| `time` | 世界累计时间与基础倍率 |
| `id_counters` | 各 ID 前缀的当前计数 |
| `player` | 玩家档案、玩家部队 ID、位置等 |
| `world_state` | 世界级标记（已发现地点、全局事件等） |
| `scene_state` | 需要恢复的局部状态（初期可不使用） |
| 各实体表 | `{ 实体 ID: 实体数据 }` |

## 4. 序列化规则

- 实体类提供 `to_dict()` / 静态 `from_dict()`。
- `Vector2` → `[x, y]`。
- `Color` → HTML 字符串（含 alpha）。
- 枚举 → `int`。
- 缺失字段使用安全默认值。
- 新增字段时评估旧存档兼容性。
- 不保存场景节点、节点路径、资源实例引用。

## 5. 保存流程

```text
玩家请求保存
  → 校验是否允许保存（安全状态、非战斗）
  → 从 WorldContext 聚合 SaveData：
      ├── TimeManager.world_elapsed_seconds
      ├── IdGenerator.to_dict()
      ├── UnitManager.to_dict()
      ├── PartyManager.to_dict()
      ├── Lord / Settlement / Faction 数据
      └── 玩家档案
  → SaveManager.save_game(slot, save_data)
```

注意：聚合逻辑目前未实现。建议在阶段 0 后半段由 `GameManager` 或独立的 `SaveCollector` 完成，`SaveManager` 只负责 I/O。

## 6. 读取流程

```text
请求读档
  → SaveManager.load_game(slot)
  → 校验 schema_version
  → 执行数据迁移（如有）
  → GameManager 创建新的 WorldContext
  → 恢复 IdGenerator 计数
  → 恢复各实体仓储
  → 恢复 TimeManager 时间与倍率
  → 进入大地图
```

当前只实现了 JSON 读取与 `SaveData` 结构，恢复流程未实现。

## 7. 存档限制

- 初期只允许在安全状态（大地图、非战斗、非对话）存档。
- 战斗中不支持存档；避免序列化 `BattleSession` 实时状态。
- 暂停原因不存档，读档后重新建立。
- 读档统一回到大地图，不恢复小场景。

## 8. 版本与迁移

- `schema_version` 每次结构不兼容变更时加 1。
- 读取旧版本时执行迁移函数，迁移后再进入游戏。
- 读取新版本（高于当前）时拒绝并提示。
- 迁移逻辑集中在 `SaveData.from_dict()` 或独立迁移模块，禁止散落。

## 9. 数据校验

保存前建议校验：

- 每个 `UnitData.current_party_id` 与所属 `PartyData.member_unit_ids` 一致。
- 所有 ID 非空且唯一。
- 引用的 `faction_id`、`settlement_id`、`lord_id` 存在。
- 时间与数值非负。
- 玩家部队存在。

读取后同样校验，失败时记录错误并可回退到安全状态。

## 10. 实现状态

| 项 | 状态 |
|---|---|
| `SaveData` 结构 | 已实现 |
| JSON 写入/读取 | 已实现 |
| 槽位列表/删除 | 已实现 |
| 版本检查 | 已实现（拒绝高版本） |
| 聚合 `WorldContext → SaveData` | TODO(阶段0) |
| 恢复 `SaveData → WorldContext` | TODO(阶段0) |
| 数据迁移 | TODO |
| 原子写入 | TODO |
| 校验 | TODO(阶段0+) |

## 11. 待确认

- 自动存档频率与触发点。
- 多存档槽 UI 与排序规则。
- 是否压缩/加密。
- 原子写入在 Windows 下的实现方式。
