# 对话系统

**核心逻辑：** `Scripts/Systems/Dialogue/dialogue_manager.gd`
**数据配置：** `Scripts/Systems/Dialogue/dialogue_data.gd`、`Data/Dialogues/*.tres`
**状态：** 数据驱动单节点对话、村庄对话框与选项跳转已实现；条件/效果、复杂对话树与大地图通用对话 UI 未实现

---

## 1. 使用范围

大地图与小场景共用同一套对话系统。

触发方式：

| 场景 | 触发 |
|---|---|
| 大地图 | 接近 NPC、接近其他部队、地点交互 |
| 小场景 | 角色接近 NPC、点击交互 |

## 2. 数据模型（当前实现）

对话由节点组成，节点可包含多个选项：

```text
DialogueData (Resource)
├── dialogue_id
├── speaker_name
├── start_node_id
└── nodes: { node_id: { "text": String, "choices": Array[Dictionary] } }
```

单个选项：

| 字段 | 说明 |
|---|---|
| `text` | 显示文本 |
| `next_node_id` | 下一个节点；空字符串表示结束对话 |

当前规则：

- 对话配置使用 `DialogueData` 资源，放在 `Data/Dialogues/`。
- 每个节点保存完整文本与选项列表；UI 只渲染 `DialogueManager` 提供的数据，不硬编码文本。
- 文本支持由场景替换的占位符，例如 `{village_name}`。
- 目标节点不存在时结束对话，避免 UI 卡死。
- 条件、效果、好感度与任务跳转尚未接入；后续可在选项字典中扩展，而不改 UI 基本结构。

## 3. 条件与效果

条件示例：

- 阵营关系 >= 某值。
- 领主好感度 >= 某值。
- 玩家拥有某物品/士兵。
- 任务状态。
- 世界时间。

效果示例：

- 改变好感度。
- 触发任务。
- 招募单位。
- 给予物品。
- 改变阵营关系。
- 开始战斗。

规则：

- 条件与效果使用**受控命令表**（白名单），禁止 `Expression` / `eval` 任意执行。
- 命令注册在统一位置，新增命令必须更新本文件。
- 效果只通过管理器接口修改数据，不直接改场景节点。
- 所有条件/效果失败都要记录原因，不能静默跳过。

## 4. DialogueManager

| 方法/字段 | 说明 |
|---|---|
| `start_dialogue(data: DialogueData, start_node_id = "")` | 开始会话；校验资源与起始节点 |
| `get_speaker_name()` / `get_current_text()` / `get_choices()` | 供 UI 读取当前节点 |
| `choose(index) -> bool` | 选择选项；返回 true 表示仍在对话，false 表示结束或无效 |
| `end_dialogue()` | 结束会话并清空当前节点 |
| `is_active()` | 是否处于对话中 |
| `active_dialogue_id` / `current_node_id` | 当前对话与节点 |

职责：

- 校验并维护 `DialogueData` 会话状态。
- 提供当前文本与选项。
- 执行选项跳转；空目标或缺失目标结束对话。

不负责：UI 排版、字体、立绘、条件/效果计算（尚未实现）。

## 5. 时间规则

| 场景 | WorldTime | SceneTime |
|---|---:|---:|
| 大地图对话 | 0 | 无 |
| 小场景普通探索对话 | 0 | 1.0 |
| 小场景战斗对话 | 不支持 | — |

- 大地图对话开始时压入 `world_dialogue` 暂停原因，结束时移除。
- 小场景对话保持 `small_scene` 暂停，SceneTime 正常。
- UI 动画使用真实时间。

## 6. 数据存储

- 静态对话使用 `DialogueData` `Resource`，放在 `Data/Dialogues/`；当前示例为 `village_elder.tres`。
- 对话进度与已选分支属于运行时状态，不进入存档；本阶段的村庄对话每次从起始节点开始。
- 对话节点不保存场景节点引用。
- 后续若需要跨场景对话进度，再写入 `SaveData.world_state` 或任务数据。

## 7. UI

- 显示说话者、文本、选项。
- 选项不可用时显示原因（好感不足、条件不满足）。
- 键盘和鼠标都可操作。
- 对话 UI 不直接执行效果，只把选择交给 `DialogueManager`。

## 8. 实现状态

| 项 | 状态 |
|---|---|
| `DialogueManager` 会话与节点跳转 | 已实现 |
| `DialogueData` 数据 Resource | 已实现 |
| 村庄对话 UI（屏幕下方） | 已实现：NPC 名称、文本、数据驱动选项 |
| 村庄头人触发与距离校验 | 已实现 |
| 条件/效果命令表 | 未实现 |
| 复杂对话树、多选项分支 | 数据结构可扩展，当前只有单选项 |
| 大地图通用对话 UI | 未实现（大地图部队遭遇仍使用专用面板） |

## 9. 待确认

- 对话图的编辑器工作流（手写 `.tres` 还是外部工具导出）。
- 是否支持本地化 key。
- 条件/效果的完整清单。
