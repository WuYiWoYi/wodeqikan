# 对话系统

**核心逻辑：** `Scripts/Systems/Dialogue/dialogue_manager.gd`
**状态：** 会话骨架完成，数据与 UI 未实现

---

## 1. 使用范围

大地图与小场景共用同一套对话系统。

触发方式：

| 场景 | 触发 |
|---|---|
| 大地图 | 接近 NPC、接近其他部队、地点交互 |
| 小场景 | 角色接近 NPC、点击交互 |

## 2. 数据模型

对话是由节点组成的图：

```text
DialogueGraph
├── dialogue_id
├── entry_node_id
└── nodes: { node_id: DialogueNode }
```

单个节点：

| 字段 | 说明 |
|---|---|
| `node_id` | 节点 ID |
| `speaker_id` | 说话者 ID（领主/单位/地点） |
| `text` | 对话文本 |
| `choices` | 选项列表 |
| `next_node_id` | 无选项时的下一节点 |
| `conditions` | 显示/跳转条件 |
| `effects` | 选择后执行的效果 |

选项：

- `text`
- `next_node_id`
- `conditions`
- `effects`

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
| `start_dialogue(dialogue_id, start_node_id)` | 开始会话 |
| `choose(choice_index)` | 选择选项并跳转 |
| `end_dialogue()` | 结束会话 |
| `active_dialogue_id` | 当前对话 |
| `current_node_id` | 当前节点 |

职责：

- 加载对话配置。
- 计算当前可用选项。
- 执行条件与效果。
- 维护会话状态。

不负责：UI 排版、字体、立绘。

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

- 静态对话图使用 `Resource`：后续增加 `DialogueGraphConfig` 与 `DialogueNodeConfig`，放在 `Data/Dialogues/`。
- 对话进度与已选分支属于运行时状态，保存在 `SaveData.world_state` 或任务数据中。
- 对话节点不保存场景节点引用。

## 7. UI

- 显示说话者、文本、选项。
- 选项不可用时显示原因（好感不足、条件不满足）。
- 键盘和鼠标都可操作。
- 对话 UI 不直接执行效果，只把选择交给 `DialogueManager`。

## 8. 实现状态

| 项 | 状态 |
|---|---|
| `DialogueManager` 会话骨架 | 已实现 |
| 对话数据 Resource | TODO(阶段5) |
| 条件/效果命令表 | TODO(阶段5) |
| 对话 UI | TODO(阶段5) |
| 大地图/小场景触发 | TODO(阶段5) |

## 9. 待确认

- 对话图的编辑器工作流（手写 `.tres` 还是外部工具导出）。
- 是否支持本地化 key。
- 条件/效果的完整清单。
