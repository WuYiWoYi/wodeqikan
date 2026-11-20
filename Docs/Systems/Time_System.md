# 时间系统

**核心脚本：** `Scripts/Autoload/time_manager.gd`
**状态：** 核心循环已实现

---

## 1. 三个时间域

| 时间域 | 用途 | 驱动 | 倍率 |
|---|---|---|---|
| WorldTime | 大地图世界模拟 | `TimeManager._process` 累积固定步长 | 0 / 1 / 2，战斗覆盖 0.5 |
| SceneTime | 小场景角色与物理 | 场景 `_physics_process` | 固定 1.0 |
| UITime | UI 动画、加载动画 | 真实帧时间 | 不受游戏暂停影响 |

禁止用 `Engine.time_scale` 缩放全局时间，也禁止用 `get_tree().paused` 实现游戏暂停。原因：

- 全局缩放会同时影响 UI 和动画；
- 世界模拟需要固定步长，不能依赖渲染帧；
- 暂停需要区分“世界暂停”和“UI 暂停”。

## 2. 倍率规则

### 2.1 基础倍率

| 状态 | 基础倍率 |
|---|---:|
| 玩家暂停 | 0 |
| 正常 | 1.0 |
| 二倍速 | 2.0 |

由 `TimeManager.set_base_world_speed()` 设置，只允许 0 / 1 / 2。

### 2.2 战斗覆盖

战斗期间 WorldTime 为 0.5。由 `BattleManager` 调用：

```gdscript
TimeManager.set_battle_mode(true)   # 战斗开始
TimeManager.set_battle_mode(false)  # 战斗结束
```

### 2.3 暂停原因栈

暂停不是布尔值，而是原因集合：

```gdscript
TimeManager.push_pause(&"ui_panel")
TimeManager.push_pause(&"world_dialogue")
TimeManager.pop_pause(&"ui_panel")
```

- 任一原因存在 → 有效倍率 0。
- 同一原因重复 push 只记一次；pop 必须成对。
- 已定义原因：`main_menu`、`loading`、`ui_panel`、`world_dialogue`、`small_scene`。
- 新增原因写在这里，并在使用方保证成对释放。

### 2.4 有效倍率计算顺序

```text
if 暂停原因非空:            0
elif 基础倍率 == 0:         0
elif 战斗模式:              0.5
else:                       基础倍率（1 或 2）
```

含义：玩家显式暂停优先级最高；战斗覆盖 1 倍和 2 倍，但不能覆盖显式暂停。

## 3. 固定步长世界模拟

```text
每帧（真实 delta）：
    scaled_delta = delta * 有效倍率
    accumulator += scaled_delta

    当 accumulator >= 0.1 且本帧 tick 数 < 10：
        accumulator -= 0.1
        world_elapsed_seconds += 0.1
        emit world_tick(0.1)
```

规则：

- 世界模拟固定 0.1 秒一次，即每秒最多 10 次。
- 单帧最多补 10 个 tick；超过则丢弃累积时间，防止卡顿后的“死亡螺旋”。
- 渲染帧率与世界 tick 完全解耦。
- 禁止在每个渲染帧执行全量 AI 决策。

## 4. 游戏内时间

- `world_elapsed_seconds` 保存世界累计游戏秒数。
- 阶段 1 之后再增加“游戏内日期”换算（年/月/日/时）。
- 招募时间等记录统一使用世界累计时间，不混用真实时间。

## 5. 状态与规则

| 状态 | WorldTime | SceneTime | 实现方式 |
|---|---:|---:|---|
| 主菜单 | 0 | 无 | `stop_session` + `main_menu` 暂停 |
| 大地图正常 | 1.0 | 无 | 基础倍率 1 |
| 大地图暂停 | 0 | 无 | 基础倍率 0 |
| 大地图二倍速 | 2.0 | 无 | 基础倍率 2 |
| 部队管理面板 | 0 | 无 | `ui_panel` 暂停 |
| 地点交互面板 | 0 | 无 | `ui_panel` 暂停 |
| 大地图对话 | 0 | 无 | `world_dialogue` 暂停 |
| 小场景普通探索 | 0 | 1.0 | `small_scene` 暂停 |
| 小场景对话 | 0 | 1.0 | 保持 `small_scene` |
| 小场景战斗 | 0.5 | 1.0 | `battle_mode` |

注意：源规划中“小场景对话时世界仍以 0.5 倍速运行”的描述与上表不一致。当前采用上表（小场景探索/对话 WorldTime = 0），后续若需要修改，必须同步更新本表与 `Technical_Decisions.md`。

## 6. API

| 方法/属性 | 说明 |
|---|---|
| `start_session()` | 开始新会话，重置时间 |
| `stop_session()` | 停止世界 tick |
| `reset_session()` | 清零累计时间、倍率、暂停 |
| `set_base_world_speed(speed)` | 0 / 1 / 2 |
| `set_battle_mode(active)` | 战斗时间覆盖 |
| `push_pause(reason)` / `pop_pause(reason)` | 暂停原因栈 |
| `clear_pauses()` | 清理所有暂停 |
| `get_effective_world_scale()` | 当前有效倍率 |
| `world_elapsed_seconds` | 世界累计秒数 |
| `world_tick` 信号 | 固定步长 tick |
| `world_time_changed` 信号 | 世界累计时间变化 |

## 7. 存档字段

- `time.world_elapsed_seconds`
- `time.world_base_speed`

暂停原因不存档；读档后由进入状态重新建立。

## 8. 实现状态

| 项 | 状态 |
|---|---|
| 固定步长累积 | 已实现 |
| 暂停原因栈 | 已实现 |
| 战斗覆盖 | 已实现 |
| 游戏内日期 | TODO(阶段1/2) |
| UI 时间按钮 | TODO(阶段1) |

## 9. 待确认

- 小场景对话期间世界是否应保持 0.5 倍速（当前按 0 处理）。
- 是否需要“快进到指定时间”功能（等待、训练）。
