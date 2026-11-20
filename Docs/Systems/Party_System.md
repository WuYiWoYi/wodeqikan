# 部队系统

**核心数据：** `Scripts/Entities/Party/party_data.gd`
**核心逻辑：** `Scripts/Core/World/party_manager.gd`
**状态：** 数据、成员管理（含转队与读档校验）、初始部队与大地图移动已实现；部队 AI/UI 未实现

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
- 部队解散时，成员 `current_party_id` 清空，`UnitData` 保留。
- 一个单位最多属于一支部队：加入新部队前先从所有其他部队移除。
- 重复加入同一部队不产生重复成员。
- 本阶段要求单位与部队 `faction_id` 相等；跨阵营加入被拒绝。
- 转队在全部校验通过后一次性修改两个方向，避免只移除旧归属的半转移状态。
- 新增部队时不允许覆盖已存在的 `party_id`；读档遇到重复 ID 报错并跳过。
- 读档后由 `validate_membership_consistency()` 校验双向归属，见第 4.1 节。

## 4. PartyManager API

| 方法 | 说明 |
|---|---|
| `setup(unit_manager, id_generator)` | 装配 |
| `create_party(faction_id, position, name)` | 创建部队 |
| `add_party(party) -> String` | 加入仓储；重复 ID 拒绝并返回空字符串 |
| `get_party(party_id)` / `has_party(party_id)` | 查询 |
| `remove_party(party_id) -> bool` | 解散，清空成员与悬空归属，单位保留 |
| `add_member(party_id, unit_id) -> bool` | 加入或转队；校验存在性与阵营，失败不改数据 |
| `transfer_member(unit_id, target_party_id) -> bool` | 转队，内部复用 `add_member` |
| `remove_member(party_id, unit_id) -> bool` | 移除成员并清空归属；单位保留 |
| `get_member_ids(party_id)` / `get_units_of_party(party_id)` | 获取成员 ID / 数据 |
| `validate_membership_consistency() -> Array[String]` | 双向归属校验，空列表表示通过 |
| `to_dict()` / `load_from_dict()` | 存档序列化；读档重复 ID 报错并跳过 |

### 4.1 读档成员关系校验

`WorldContext.load_from_save_data()` 在 `UnitManager` 与 `PartyManager` 都恢复完成后调用
`validate_membership_consistency()`，检查：

1. 每个成员 ID 都能找到对应 `UnitData`。
2. 每个非空 `current_party_id` 都能找到对应 `PartyData`。
3. 一个单位最多出现在一支部队的成员列表中（同一列表内也不得重复）。
4. `UnitData.current_party_id` 与 `PartyData.member_unit_ids` 双向一致。

失败处理：逐条 `push_error` 后返回 `false`，拒绝进入游戏；不自动修复或改写存档数据（D025）。

## 5. 移动速度

Milestone 1 使用简单固定值：

| 部队 | 初始位置 | 速度（像素/游戏秒） |
|---|---|---|
| 玩家部队 | (760, 620) | 300 |
| 河畔商队 | (900, 1500) | 220 |
| 北境巡逻队 | (2350, 1100) | 220 |

后续考虑：

- 部队最慢成员。
- 骑兵比例。
- 负重。
- 地形。
- 道路。
- 坐骑。

公式在阶段 2 确定，并写入本文件。

## 6. 部队管理 UI（TODO 阶段 3）

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
| 创建部队 | 已实现 |
| 初始玩家/NPC 部队 | 已实现 |
| 大地图直线移动 | 已实现 |
| 移动速度公式 | 固定值（阶段 2 再扩展） |
| 转队与重复成员防护 | 已实现（D024） |
| 重复部队 ID 防护 | 已实现（D024） |
| 读档成员关系校验 | 已实现（D025） |
| 非跨阵营成员规则 | 已实现；跨阵营流程未实现（KI119） |
| 部队 AI | 未实现（阶段 2/5） |
| 部队管理 UI | TODO(阶段3) |
| 编队 | TODO(阶段6) |
| 拆分/合并 | TODO(阶段7) |

初始玩家/NPC 部队目前仍不生成真实士兵成员（`member_unit_ids` 为空）；士兵数据层与成员管理已可用，招募/初始化流程留待后续（KI115）。

## 11. 待确认

- 玩家部队上限与部队规模上限。
- 跨阵营招募、俘虏、叛变与雇佣兵的归属变更流程（KI119）。
- 军团系统是否在阶段 7 前提供最小接口。
- 移动速度公式与负重/骑兵比例的关系。
