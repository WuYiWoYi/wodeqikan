# 部队系统

**核心数据：** `Scripts/Entities/Party/party_data.gd`
**核心逻辑：** `Scripts/Core/World/party_manager.gd`
**状态：** 数据与成员管理已实现，移动/AI/UI 未实现

---

## 1. 职责

- 部队是大地图的基本移动实体。
- 一个部队由多个 `UnitData` 组成。
- 维护成员关系、战斗状态、当前命令。
- 为 UI 与 AI 提供部队数据。

不负责：具体移动计算（`WorldMapManager`）、部队 AI（`AIManager`）、单位战斗行为（`UnitController`）。

## 2. PartyData

| 字段 | 类型 | 说明 |
|---|---|---|
| `party_id` | String | 唯一 ID，`PARTY_000001` |
| `party_name` | String | 显示名 |
| `faction_id` | String | 所属阵营 |
| `leader_lord_id` | String | 领主 ID（玩家部队可为空） |
| `world_position` | Vector2 | 大地图坐标（像素） |
| `target_position` | Vector2 | 移动目标 |
| `movement_speed` | float | 像素 / 游戏秒 |
| `sight_range` | float | 视野半径 |
| `member_unit_ids` | Array[String] | 成员单位 ID |
| `current_order` | enum | NONE / MOVE / HOLD / INTERACT / BATTLE |
| `current_target_id` | String | 交互或战斗目标 ID |
| `movement_state` | enum | IDLE / MOVING |
| `battle_state` | enum | AVAILABLE / IN_BATTLE / RETURNING / DISABLED |

## 3. 成员关系不变量

始终满足：

```text
unit.current_party_id == party.party_id
⇔
party.member_unit_ids.has(unit.unit_id)
```

维护规则：

- 加入/离开部队只能通过 `PartyManager.add_member()` / `remove_member()`。
- 不允许其他系统直接 append/erase `member_unit_ids`。
- 单位转队时 `unit_id` 不变，只改归属。
- 部队解散时，成员 `current_party_id` 清空。

## 4. PartyManager API

| 方法 | 说明 |
|---|---|
| `setup(unit_manager, id_generator)` | 装配 |
| `create_party(faction_id, position, name)` | 创建部队 |
| `add_party(party)` | 加入仓储 |
| `get_party(party_id)` | 查询 |
| `remove_party(party_id)` | 解散并清理成员归属 |
| `add_member(party_id, unit_id)` | 加入成员 |
| `remove_member(party_id, unit_id)` | 移除成员 |
| `get_units_of_party(party_id)` | 获取成员数据 |
| `to_dict()` / `load_from_dict()` | 存档序列化 |

## 5. 移动速度

初期使用简单值：`PartyData.movement_speed`。

后续考虑：

- 部队最慢成员。
- 骑兵比例。
- 负重。
- 地形。
- 道路。
- 坐骑。

公式在阶段 2 确定，并写入本文件。

## 6. 部队管理 UI

```text
点击大地图部队按钮
  → 压入 ui_panel 暂停
  → 打开部队管理面板
  → 显示全部成员、属性、编队
  → 关闭面板时移除暂停原因
```

- 面板读取 `PartyManager`，不直接改数据。
- 人员编队操作通过 `FormationManager` 或后续 `PartyManager` 接口执行。

## 7. 编队接口

编队是独立子系统：

- 定义阵型类型、成员、站位。
- 预留步兵方阵、步兵线阵、弓箭手线阵、骑兵阵型。
- `FormationManager.compute_slots()` 返回相对站位。
- 编队不负责攻击行为；单位 AI 负责执行。

详见 `Scripts/Systems/Formation/formation_manager.gd`。

## 8. 战斗状态

| 状态 | 含义 | 大地图行为 |
|---|---|---|
| `AVAILABLE` | 可用 | 可移动、可被选为目标 |
| `IN_BATTLE` | 战斗中 | 锁定，不移动 |
| `RETURNING` | 战后返回 | 暂不接新命令 |
| `DISABLED` | 失效 | 不参与世界模拟 |

状态由 `BattleManager` 写入，其他系统只读。

## 9. 扩展方向

- 部队拆分/合并。
- 军团组织与部队支援关系。
- 部队士气、补给、负重。
- 玩家多部队管理。
- 部队命名与编制模板。

## 10. 实现状态

| 项 | 状态 |
|---|---|
| `PartyData` 与序列化 | 已实现 |
| 成员增删与双向一致 | 已实现 |
| 创建部队 | 已实现基础版 |
| 移动速度公式 | TODO(阶段2) |
| 部队管理 UI | TODO(阶段3) |
| 编队 | TODO(阶段6) |
| 拆分/合并 | TODO(阶段7) |

## 11. 待确认

- 玩家部队上限与部队规模上限。
- 部队解散时单位的去向（回城/消失/加入其他部队）。
- 军团系统是否在阶段 7 前提供最小接口。
