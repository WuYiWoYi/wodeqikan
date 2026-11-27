# 时间系统

**核心脚本：** `Scripts/Autoload/time_manager.gd`
**状态：** 核心循环、暂停栈、统一游戏日历（1103-01-01 起，2 秒 = 1 小时、48 秒 = 1 日）、日期/时间段 UI、读档时间恢复、战斗暂停已实现

---

## 1. 三个时间域

| 时间域 | 用途 | 驱动 | 倍率 |
|---|---|---|---|
| WorldTime | 大地图世界模拟 | `TimeManager._process` 累积固定步长 | 0 / 1 / 2；屏幕内战斗暂停为 0 |
| SceneTime | 小场景 / 战斗场景角色与物理 | 场景 `_physics_process` | 固定 1.0 |
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

### 2.2 战斗暂停

屏幕内战斗期间 WorldTime 为 0。由 `BattleManager` 使用暂停原因栈实现：

```gdscript
TimeManager.push_pause(GameManager.PAUSE_REASON_BATTLE)  # 战斗开始
TimeManager.pop_pause(GameManager.PAUSE_REASON_BATTLE)   # 战斗结束
```

`TimeManager.set_battle_mode(true/false)` 仍保留 0.5 倍速覆盖能力；当前屏幕内战斗与离屏战斗都不使用它。离屏战斗保持世界正常速度，只由 `BattleManager.tick()` 按累计世界时间触发小时结算。

### 2.3 暂停原因栈

暂停不是布尔值，而是原因集合：

```gdscript
TimeManager.push_pause(&"ui_panel")
TimeManager.push_pause(&"world_dialogue")
TimeManager.pop_pause(&"ui_panel")
```

- 任一原因存在 → 有效倍率 0。
- 同一原因按引用计数嵌套：每次 `push_pause` 计数 +1，每次 `pop_pause` 计数 -1，计数归零才移除该原因。
  因此“地点面板 + 百科/背包/部队”这类叠加界面关闭内层时不会提前恢复世界时间。
- `pop_pause` 遇到计数为 0 的原因时静默忽略，不产生负计数。
- 已定义原因：`main_menu`、`loading`、`ui_panel`、`world_dialogue`、`small_scene`、`battle`。
- 新增原因写在这里，并在使用方保证成对释放。
- 进入战斗时先压入 `battle`，再释放对话的 `ui_panel`，保证切换期间世界不恢复运行。

### 2.4 有效倍率计算顺序

```text
if 暂停原因非空:            0
elif 基础倍率 == 0:         0
elif 战斗模式:              0.5
else:                       基础倍率（1 或 2）
```

含义：暂停原因优先级最高；`battle_mode` 能覆盖 1 倍和 2 倍，但不能覆盖显式暂停。当前屏幕内战斗通过 `battle` 暂停原因直接停住世界，`battle_mode` 暂未使用。

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

## 4. 游戏内时间与日历

- `world_elapsed_seconds` 仍是唯一权威时间；年月日、小时、时间段都由它换算，任何系统不得自行累计日期。
- 1x 速度下：
  - 现实 2 秒 = 1 游戏小时；
  - 现实 48 秒 = 1 游戏日；
  - 2x 时按倍率翻倍，暂停时停止。
- 统一换算常量：`TimeManager.REAL_SECONDS_PER_GAME_HOUR = 2.0`、`GAME_MINUTES_PER_ELAPSED_SECOND = 30.0`。其他系统不得自行定义不同的“秒→游戏小时”比例；`CaptivityManager` 与 `WoundedHealingManager` 的本地 `SECONDS_PER_GAME_HOUR` 必须与该常量保持一致。
- 新游戏从 **公元 1103 年 1 月 1 日 00:00** 开始（显示时间段为“深夜”）。
- 本阶段采用简化历法：每月 30 天、每年 12 个月，共 360 天。
- 大地图只显示年月日与时间段，不显示小时/分钟：
  - 时间段集中配置在 `TimeManager.TIME_PERIODS`；
  - 未命中区间时使用 `DEFAULT_TIME_PERIOD = "深夜"`。

| 时间段 | 小时区间 |
|---|---|
| 清晨 | 05:00–07:00 |
| 上午 | 07:00–12:00 |
| 下午 | 12:00–17:00 |
| 黄昏 | 17:00–19:00 |
| 夜晚 | 19:00–23:00 |
| 深夜 | 23:00–05:00 |

- 读档通过 `restore_world_time(seconds, base_speed)` 恢复累计时间和基础倍率；日期自动由累计时间换算。

### 4.1 新游戏与读档的初始时间状态

- 新游戏：`start_session()` 后设置基础倍率 0，默认暂停。
- 读档：`start_session()` 后恢复存档中的 `world_elapsed_seconds` 与 `world_base_speed`。
- 读档会清除旧暂停原因；不恢复存档时的临时暂停原因。

### 4.2 小时边界驱动的世界结算（阶段 13）

- `WoundedHealingManager` 使用与日历相同的换算：`floor(world_elapsed_seconds / 6.0)` 得到累计游戏小时。
- 每次世界 tick 检查是否跨过新的整小时；跨过 `n` 小时则一次性结算 `n * healing_per_hour` 点治疗。
- 暂停时世界 tick 不推进，治疗也不推进；1x/2x 都按游戏小时获得相同治疗量。
- `last_settled_hour` 持久化在 `time.healing_last_settled_hour`；读档缺失时以存档时刻所在小时为起点，不补算离线时间。
- 该规则同样适用于 `SupplyManager` 的日边界结算与离屏战斗的小时结算：统一以 `world_elapsed_seconds` 换算，不由场景或 UI 自行累计。

## 5. 状态与规则

| 状态 | WorldTime | SceneTime | 实现方式 |
|---|---:|---:|---|
| 主菜单 | 0 | 无 | `stop_session` + `main_menu` 暂停 |
| 大地图正常 | 1.0 | 无 | 基础倍率 1 |
| 大地图暂停 | 0 | 无 | 基础倍率 0 |
| 大地图二倍速 | 2.0 | 无 | 基础倍率 2 |
| 部队管理面板 | 0 | 无 | `ui_panel` 暂停 |
| 地点交互面板 | 0 | 无 | 基础倍率 0 + `ui_panel` 暂停；离开后仍为 0 |
| 大地图保存面板 | 0 | 无 | `ui_panel` 暂停；关闭后恢复原基础倍率 |
| 大地图部队对话 | 0 | 无 | `ui_panel` 暂停；离开后恢复原基础倍率 |
| 大地图对话 | 0 | 无 | `world_dialogue` 暂停 |
| 小场景普通探索 | 0 | 1.0 | `small_scene` 暂停 |
| 小场景对话 | 0 | 1.0 | 保持 `small_scene` |
| 屏幕内战斗 | 0 | 1.0 | `battle` 暂停；战斗场景使用物理帧推进 |
| 离屏 AI 对 AI 战斗 | 正常 | 无 | 世界继续运行；每游戏小时结算一次伤亡 |

注意：源规划中“小场景对话时世界仍以 0.5 倍速运行”的描述与上表不一致。当前采用上表（小场景探索/对话 WorldTime = 0），后续若需要修改，必须同步更新本表与 `Technical_Decisions.md`。

## 6. API

| 方法/属性 | 说明 |
|---|---|
| `start_session()` | 开始新会话，重置时间 |
| `stop_session()` | 停止世界 tick |
| `reset_session()` | 清零累计时间、倍率、暂停 |
| `set_base_world_speed(speed)` | 0 / 1 / 2 |
| `get_base_world_speed()` | 当前基础倍率（不受暂停原因影响） |
| `restore_world_time(seconds, base_speed)` | 读档恢复累计时间与基础倍率 |
| `set_battle_mode(active)` | 历史 0.5 倍速覆盖接口，当前屏幕/离屏战斗均未使用 |
| `push_pause(reason)` / `pop_pause(reason)` | 暂停原因栈 |
| `clear_pauses()` | 清理所有暂停 |
| `has_pause_reason(reason)` | 查询某暂停原因是否存在 |
| `get_effective_world_scale()` | 当前有效倍率 |
| `get_date_parts(total_seconds = -1)` | 返回 year/month/day/hour/minute/total_hours/total_days |
| `get_date_text(total_seconds = -1)` | “1103 年 1 月 1 日” |
| `get_time_period(total_seconds = -1)` | “清晨 / 上午 / … / 深夜” |
| `get_world_time_text(total_seconds = -1)` | 日期 + 时间段 |
| `world_elapsed_seconds` | 世界累计秒数 |
| `world_tick` 信号 | 固定步长 tick |
| `world_time_changed` 信号 | 世界累计时间变化 |

## 7. 存档字段

- `time.world_elapsed_seconds`
- `time.world_base_speed`
- `time.supply_last_settled_day`（补给结算）
- `time.healing_last_settled_hour`（伤兵治疗结算）

暂停原因不存档；读档后由进入状态重新建立。保存面板打开时的暂停原因不会写入基础倍率。

## 8. 实现状态

| 项 | 状态 |
|---|---|
| 固定步长累积 | 已实现 |
| 暂停原因栈 | 已实现 |
| 战斗暂停（`battle`） | 已实现，屏幕内战斗 WorldTime = 0 |
| 离屏战斗小时结算 | 已实现，世界继续运行；每 2 世界秒 = 1 游戏小时 |
| 战斗 0.5 倍速覆盖 | 接口保留，未使用；离屏战斗保持正常世界倍率 |
| 读档时间恢复 | 已实现 |
| UI 时间显示/按钮 | 已实现（暂停 / 1x / 2x） |
| 游戏内日期 | 已实现：1103-01-01 起、30 天/月、12 月/年；大地图显示年月日 + 时间段 |
| 时间段 | 已实现：清晨 / 上午 / 下午 / 黄昏 / 夜晚 / 深夜，集中配置 |
| 日期驱动 | 统一由 `world_elapsed_seconds` 换算；没有系统自行累计日期 |
| 伤兵治疗小时结算 | 已实现：整小时边界、暂停不推进、1x/2x 一致、读档不补算（`WoundedHealingManager`） |

## 9. 待确认

- 屏幕内战斗是否应改为 0.5 倍速（当前按 0 处理，见 D028）。
- 小场景对话期间世界是否应保持 0.5 倍速（当前按 0 处理）。
- 是否需要“快进到指定时间”功能（等待、训练）。
- 真实月历/闰年与季节系统；当前为每月 30 天的简化日历。
