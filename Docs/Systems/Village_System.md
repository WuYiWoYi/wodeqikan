# 村庄小场景系统

**场景：** `Scenes/Village/village.tscn`
**控制器：** `Scripts/UI/Village/village_scene.gd`
**状态：** 进入/离开、玩家表现、村庄头人、数据驱动对话、越界倒计时、冒险者候选人、采邑对话入口与共享日志面板已实现；商店、任务、城镇/城堡小场景未实现

---

## 1. 目标与边界

- 大地图上的村庄可以进入独立小场景，但初期的三个村庄共用同一个基础模板。
- 村庄是和平场景：不生成敌对部队，不触发战斗，不修改玩家部队、装备或存档。
- 玩家角色复用 `UnitData` / `UnitVisual`，不存在第二套角色系统。
- 场景切换只改变表现；`WorldContext` 跨场景常驻，玩家部队权威数据不变。

## 2. 地点与场景关联

`SettlementData.scene_path` 保存该地点对应的小场景路径：

| 地点类型 | 当前 `scene_path` |
|---|---|
| 村庄 | `res://Scenes/Village/village.tscn` |
| 城镇 / 城堡 | 空字符串（暂未实现小场景） |

- 新游戏由 `WorldInitializer` 为三个村庄写入默认模板路径。
- 旧存档缺少 `scene_path` 时默认为空；大地图对村庄回退到 `SceneManager.VILLAGE_SCENE`。
- 后续可逐村替换为不同布局/美术场景，不需要修改 `SettlementData` 结构。

## 3. 进入与返回

### 3.1 进入

```text
玩家接近村庄 → 地点面板
  → 点击“进入村庄”
  → WorldMap.enter_village(settlement_id)
      ├── 校验地点类型为 VILLAGE、场景存在
      ├── GameManager.current_settlement_id = settlement_id
      ├── 记录 GameManager.small_scene_return_base_speed
      ├── push_pause(small_scene)
      ├── pop_pause(ui_panel)
      └── SceneManager.change_scene(village.scene_path)
```

- 进入前先压入 `small_scene`，再释放地点面板的 `ui_panel`，避免切换期间世界恢复推进。
- 场景加载失败时回滚暂停状态并重新显示地点面板。
- 进入村庄不复制、不重建玩家部队数据。
- 场景切换成功后广播 `EventBus.settlement_entered`，供世界日志记录。

### 3.2 返回

```text
玩家连续越界 5 秒
  → VillageScene._request_exit()
      ├── 关闭对话（若有）
      ├── GameManager.pending_settlement_latch_id = 当前村庄
      ├── 恢复进入前的大地图基础倍率
      ├── pop_pause(small_scene)
      └── SceneManager.change_scene(WorldMap)
```

- 返回后玩家部队仍站在村口。大地图读取并消费 `pending_settlement_latch_id`，记录当前村口村庄供地点面板使用；不会自动重开地点面板，需玩家主动点击地点。
- 返回后不自动恢复移动指令；玩家需要重新点击地图或选择时间倍率。
- 场景切换成功后广播 `EventBus.settlement_exited`，供世界日志记录。

### 3.3 运行时字段

`GameManager` 中以下字段仅运行时使用，不进入存档：

| 字段 | 说明 |
|---|---|
| `current_settlement_id` | 当前进入的村庄 ID |
| `pending_settlement_latch_id` | 返回大地图后记录当前村口村庄，大地图不再自动打开地点面板 |
| `small_scene_return_base_speed` | 进入前的大地图基础倍率 |

## 4. 玩家角色表现

- 村庄从玩家部队中优先选择 `is_player_character` 的单位；旧存档没有玩家角色时退化到第一名成员。
- 玩家表现节点直接使用 `UnitVisual.setup(UnitData)`，位置由场景控制器维护。
- 进入村庄时调用 `UnitVisual.set_weapon_visible(false)`：
  - 只隐藏本次场景的武器 Sprite；
  - **不修改** `UnitData.equipment`，不删除武器，不影响存档；
  - 返回大地图或进入战斗后由正常表现流程重新显示。
- 场景内移动使用 WASD，速度为 `UnitData.move_speed × 2.0`；倍率是村庄表现参数，不写回单位数据。
- 玩家位置限制在整个 1920×1080 场景内；可活动区域另行定义。

### 4.1 摄像机

- 村庄与战斗共用 `SceneCameraRig`，统一视野基准为 960×540 世界单位（1920×1080 下 2 倍缩放）。
- 默认平滑跟随玩家角色；镜头受 1920×1080 场景边界限制。
- `F` 切换自由视角；WASD/方向键移动镜头，玩家角色保持不动。
- 切回跟随模式时镜头立即重新定位到玩家。
- 摄像机只影响表现，不修改玩家位置、`UnitData` 或存档。

## 5. 村庄头人 NPC

- 村庄头人使用运行时 `UnitData`（不注册进 `UnitManager`）与同一 `UnitVisual`。
- 单独的固定场景位置，独立名称标签。
- 交互条件：
  - 鼠标左键点击 NPC（点击半径 46 像素）；
  - 玩家与 NPC 中心距离 <= 130 像素。
- 距离不足时点击不会打开对话，只显示“距离太远”提示。
- 对话期间玩家移动被禁用，防止误操作。
- 本阶段没有巡逻、日程、任务、好感度或交易。

### 5.1 冒险者候选人 NPC（阶段 7 新增）

- 每个 `AdventurerCandidateData` 在村庄生成一个运行时 NPC 表现，位置来自 `candidate.world_position`，外观来自持久化 `appearance`。
- 候选 NPC 与头人共用 `UnitVisual` 和距离规则：点击半径 46 像素、玩家距离 <= 130 像素。
- 点击后打开底部对话，选项 action 为 `recruit_adventurer`；显示候选人姓名与 1 金币费用。
- 招募成功后关闭对话、刷新“已招募”标签；已招募候选人在玩家离开村庄前仍保留。
- 已招募候选人再次对话不再提供招募选项；离开村庄时清理候选人记录，真实单位保留。
- 候选 NPC 只是表现，不是 `UnitData`，不进入 UnitManager / PartyManager。
- 详细数据与刷新规则见 [Adventurer_Recruitment_System.md](Adventurer_Recruitment_System.md)。

## 6. 对话

- 对话配置：`Data/Dialogues/village_elder.tres`（`DialogueData`）。
- 界面固定在屏幕下方：
  - NPC 名称；
  - 对话文本；
  - 数据驱动选项列表。
- 基础选项“谢谢你，我要走了”始终存在，选择后关闭对话并恢复移动。
- 玩家自有且有采邑储备时追加“征召一组采邑”，action 为 `recruit_fief`，调用 `FiefRecruitmentManager.recruit_group()`。
- 文本支持 `{village_name}` 占位符，由村庄场景替换为当前地点名称。
- 对话期间压入 `world_dialogue` 暂停原因；关闭时成对移除。村庄本身仍由 `small_scene` 暂停世界。
- 详细数据模型见 [Dialogue_System.md](Dialogue_System.md)。

## 7. 可活动区域与越界倒计时

| 常量 | 当前值 | 说明 |
|---|---:|---|
| `PLAYABLE_RECT` | `(110, 300, 1700, 700)` | 村庄可活动区域 |
| `EXIT_TOLERANCE` | `8 px` | 必须越界超过该距离才开始倒计时，抑制边界抖动 |
| `EXIT_COUNTDOWN_SECONDS` | `5.0` | 连续越界时间 |

规则：

- 玩家走出可活动区域超过容差 → 开始倒计时并显示剩余时间。
- 玩家回到可活动区域内 → 立即取消倒计时并隐藏提示。
- 连续越界 5 秒 → 自动返回大地图。
- 只根据玩家位置判断，不依赖物理碰撞；本阶段没有城门、出口或通道。

## 8. 时间规则

| 状态 | WorldTime | SceneTime |
|---|---:|---:|
| 村庄探索 | 0（`small_scene`） | 1.0 |
| 村庄对话 | 0（`small_scene` + `world_dialogue`） | 1.0 |

- 场景物理帧正常推进，因此玩家、NPC 与待机动画不依赖 `TimeManager.world_tick`。
- 世界 tick 在村庄期间停止，返回后恢复进入前的基础倍率。

## 9. 测试接口

`VillageScene` 提供以下稳定接口供自动化测试使用：

| 接口 | 用途 |
|---|---|
| `set_test_input(direction, active)` | 模拟 WASD |
| `set_player_position(position)` | 放置玩家 |
| `get_player_position()` / `get_elder_position()` | 查询位置 |
| `try_interact_with_elder()` | 按距离规则尝试交互 |
| `is_dialogue_open()` | 对话状态 |
| `get_exit_countdown()` | 越界计时 |
| `set_auto_return_enabled(enabled)` | 测试时关闭真实场景切换 |
| `advance_exit_countdown(delta)` | 手动推进倒计时 |
| `is_returning_to_world()` | 是否已触发返回 |
| `get_player_visual()` | 检查武器显隐与权威数据引用 |
| `get_candidate_count()` | 当前候选 NPC 表现数量 |
| `get_candidate_visual(candidate_id)` | 查询候选人表现节点 |
| `get_candidate_position(candidate_id)` | 查询候选人生成位置 |
| `try_interact_with_candidate(candidate_id)` | 按距离规则尝试与候选人对话 |
| `get_world_log_panel()` | 查询村庄共享日志面板 |
| `get_camera_rig()` / `is_camera_free_mode()` | 检查摄像机跟随/自由状态 |
| `set_camera_free_mode(active)` | 切换跟随/自由视角 |
| `set_test_free_camera_input(direction, active)` | 模拟自由视角移动 |
| `get_camera_position()` | 查询镜头位置 |

## 10. 实现状态

| 项 | 状态 |
|---|---|
| 村庄独立场景与场景路径 | 已实现 |
| 大地图进入村庄 | 已实现（地点面板“进入村庄”） |
| 返回大地图与地点交互锁 | 已实现 |
| 玩家角色复用 UnitData/UnitVisual | 已实现 |
| 进入村庄隐藏武器表现 | 已实现，不修改装备数据 |
| 村庄头人 NPC 与距离交互 | 已实现 |
| 屏幕下方数据驱动对话 | 已实现（单选项） |
| 越界 5 秒倒计时/取消/返回 | 已实现 |
| 摄像机跟随 / 自由视角 / 边界 | 已实现（与战斗共用 `SceneCameraRig`） |
| 冒险者候选人 NPC 与 1 金币招募 | 已实现（阶段 7） |
| 玩家自有封地采邑征召对话 | 已实现（与大地图共用 `FiefRecruitmentManager`） |
| 村庄右上角共享世界日志面板 | 已实现 |
| 村庄商店、普通兵员招募、任务、好感度 | 未实现 |
| 城镇/城堡独立小场景 | 未实现 |
| 村庄碰撞、城门、出口通道 | 未实现 |

## 11. 家族与地点名称的表现边界（阶段 6 新增）

- 村庄小场景不读取 `SettlementData.family_id`，也不显示家族旗帜；家族旗帜只用于大地图固定屏幕名称标签。
- 村庄名称、对话与场景加载仍以 `SettlementData.settlement_id` / `display_name` 为数据来源。
- 巴里、墨西西只改变地点显示名与家族归属，不改变村庄场景路径、进入/返回流程或村庄头人。

## 12. 候选人生命周期与日志（阶段 7 新增）

```text
进入村庄
  → 读取 SettlementData.adventurer_candidates 生成 NPC
  → 点击候选人 → 对话（recruit_adventurer）
  → AdventurerRecruitmentManager.recruit_candidate()
  → 创建真实 UnitData + PartyManager.add_member + 扣 1 金币
  → 候选人状态 RECRUITED_PENDING_DEPARTURE（仍在场景中标记“已招募”）
  → 离开村庄 _request_exit()
  → cleanup_departed_candidates() 移除候选人记录
  → 真实单位保留在玩家部队
```

- 再次进入村庄只显示仍为 `AVAILABLE` 的候选人，不会重复显示或重复招募。
- 村庄右上角 `WorldLogPanel` 与大地图共享 `WorldLogManager`，可立即看到采邑/冒险者招募日志。
- 日志面板只读，不改变候选人状态或世界数据。
