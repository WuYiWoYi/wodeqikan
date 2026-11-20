# 大地图系统

**所属层：** 玩法逻辑 / 表现
**核心脚本：** `Scripts/Systems/WorldMap/world_map_manager.gd`、`Scripts/UI/WorldMap/world_map.gd`
**场景：** `Scenes/WorldMap/world_map.tscn`
**状态：** Milestone 1 基础移动与地点交互已实现

---

## 1. 职责

- 维护大地图坐标系与世界边界。
- 处理部队的目标设置、移动推进与到达判定。
- 计算部队视野与遭遇检测。
- 向表现层提供可读取的部队位置。

不负责：图标节点、UI、战斗、AI 决策、路径规划（初期）。

## 2. 坐标与单位

| 项 | 规则 |
|---|---|
| 坐标系 | 2D 世界坐标，原点左上，+X 向右，+Y 向下 |
| 位置字段 | `PartyData.world_position`、`target_position`，单位：像素 |
| 速度 | `PartyData.movement_speed`，单位：像素 / 游戏秒 |
| 地图边界 | `WorldMapManager.world_bounds: Rect2` |
| 存档格式 | `Vector2` 序列化为 `[x, y]` |

Milestone 1 地图固定为 3000×2000。摄像机支持跟随、方向键平移和滚轮缩放（0.5x–2x）；缩放只改变表现层，数据坐标不变。

## 3. 部队移动

### 3.1 目标设置

```text
玩家点击地图
  → 大地图输入控制器
  → WorldMapManager.set_party_target(party_id, world_position)
      ├── 校验部队存在且 battle_state == AVAILABLE
      ├── 将目标点限制在地图边界内
      ├── target_position = 目标
      ├── current_order = MOVE
      └── movement_state = MOVING
```

AI 部队由 `AIManager` 调用同一接口设置目标，不直接改字段。

### 3.2 推进

- 只有 `WorldSimulation.on_world_tick` 调用 `update_party_movement(fixed_delta)`。
- 直线移动，不做寻路。
- 到达阈值 2 像素；到达后精确对齐目标，置 `IDLE`，清理 `current_order`。
- 每 tick 移动距离 = `movement_speed * fixed_delta`。
- 大地图暂停或倍率变化时，tick 本身被 `TimeManager` 控制，移动逻辑不感知倍率。
- 目标点和每 tick 的下一位置都经过地图边界 clamp。

### 3.3 玩家操作与摄像机

- 鼠标左键点击地图 → `set_party_target()`。
- 方向键平移摄像机；滚轮缩放；摄像机平滑跟随玩家。
- 点击移动时会清除摄像机手动偏移，重新跟随玩家。
- 地图点击在 `_unhandled_input` 中处理，UI 面板会拦截自己的区域。

### 3.4 战斗锁定

`battle_state != AVAILABLE` 的部队：

- 不接受新目标；
- 不推进位置；
- 图标仍可显示，但进入战斗/返回中的状态由 UI 表现。

## 4. 表现同步

```text
WorldSimulation 更新 PartyData.world_position
  → EventBus.party_position_changed(party_id)
  → 大地图图标读取最新坐标
  → _process 中插值到显示位置（只写视觉）
```

- 表现层允许插值，禁止把插值后的坐标写回 `PartyData`。
- 图标不保存权威坐标；场景重载时从数据重建。
- 图标节点是 `PartyData` 的展示载体，不是实体本身。
- 当前实现中 `PartyIcon._process` 每帧把显示位置 lerp 到 `PartyData.world_position`。

## 5. 地点交互（Milestone 1）

地点交互由大地图场景控制器检测，不属于移动逻辑：

```text
每帧检查玩家部队
  → 用“上一帧位置到当前位置”的线段与地点做最近点距离
  → 距离 <= 40 像素：停止部队、时间设为暂停、打开面板
  → 面板关闭后保持暂停
  → 玩家离开 64 像素后解除触发锁
```

- 使用线段检测是为了避免 2x 速度下一 tick 跨过地点。
- 停止移动通过 `WorldMapManager.stop_party()`，不直接改字段。
- 打开面板压入 `ui_panel` 暂停原因，并设置基础倍率为 0。
- 离开面板只移除暂停原因，不恢复基础倍率；玩家需主动选择 1x / 2x。
- 当前只有玩家部队触发地点交互；NPC 不触发。

## 6. 视野

**状态：** TODO(阶段 2)，Milestone 1 未实现。

初期规则：

- 每个部队有圆形视野 `sight_range`。
- 两部队距离 `<= 视野半径` 判定为发现。
- 每 0.1 秒世界 tick 更新一次，不在渲染帧扫描。
- 需要维护：
  - 当前可见部队集合；
  - 新发现事件；
  - 离开视野事件。

初期只保证玩家部队的可见集合正确；AI 的视野用于目标选择，可在阶段 5 完善。

后续扩展：遮挡、夜间、天气、侦察兵加成、地形。

## 7. 遭遇与战斗交接

**状态：** TODO(阶段 2/4)，Milestone 1 未实现。

```text
双方距离 <= 遭遇阈值
  → 判断阵营关系
  → 触发遭遇事件
  → BattleManager.start_battle(...)
```

需要明确：

- 玩家参与的遭遇 → 加载 `BattleScene`。
- AI 对 AI 的遭遇 → 初期策略见 `Development/Known_Issues.md`（倾向自动结算，尚未最终确认）。
- 战斗触发后，双方部队立即锁定，不能同时在大地图移动。

## 8. 扩展方向

- 路径规划与寻路网格。
- 地形速度系数、道路加成、河流/山脉阻挡。
- 地图边界形状（非矩形）。
- 镜头滚动与缩放。
- 多选部队与军团移动。
- 视野遮挡与探测。

## 9. 实现状态

| 项 | 状态 |
|---|---|
| `world_bounds` 与目标 clamp | 已实现 |
| `set_party_target` | 已实现 |
| `update_party_movement` | 已实现（直线/到达/边界） |
| `stop_party` | 已实现 |
| `update_visibility` | TODO(阶段2) |
| 遭遇检测 | TODO(阶段2/4) |
| 表现层图标 | 已实现（程序绘制） |
| 摄像机跟随/平移/缩放 | 已实现 |
| 地点交互 | 已实现（场景侧检测） |

## 10. 待确认

- 遭遇阈值是否按双方视野决定。
- AI 对 AI 战斗的处理方式（自动结算或跳过）。
- 地点交互检测是否迁移到世界模拟层（当前在场景控制器）。
- 路径规划、地形阻挡与道路加成的具体规则。
