# 新游戏身份选择

**核心脚本：** `Scripts/UI/Identity/identity_select.gd`
**场景：** `Scenes/Identity/identity_select.tscn`（独立全屏场景）
**配置：** `Scripts/Config/identity_catalog.gd`、`Data/Identity/Categories/*.tres`、`Data/Identity/Identities/*.tres`
**状态：** 已实现全屏两级选择、纵向选项、点击身份即进入最终确认页与结果传递；尚未实现身份差异化初始化。

---

## 1. 范围与硬边界

- 主菜单「新游戏」通过 `SceneManager` 切到独立全屏身份选择场景，主菜单场景被释放，不存在附着弹窗或局部面板。
- 一级类别、二级身份、最终确认三个页面都在同一身份选择场景内完成。
- 最终确认前不创建 `WorldContext`、不启动世界时间、不写存档。
- 只有最终确认页的「最终确认」会调用 `GameManager.start_new_game(identity_id, category_id)`。
- 当前身份只影响「选择结果」本身，不改变金币、装备、士兵、出生点或任何其他初始数据。
- 身份选择结果**不进入存档**，读档不恢复；身份差异化初始化与存档字段属于后续阶段。

## 2. 流程

```text
主菜单「新游戏」
└── SceneManager -> IdentitySelect（独立全屏场景）
    ├── 一级：身份类别（纵向按钮）
    │   ├── 返回主菜单（切换回 MainMenu）
    │   └── 选择类别
    │       └── 二级：具体身份（纵向、可滚动按钮）
    │           ├── 返回一级（保留类别与身份状态）
    │           └── 点击身份 → 最终确认页（展示完整路径）
    │               ├── 返回修改（回到一级类别页，保留状态）
    │               └── 最终确认
    │                   └── GameManager.start_new_game(identity_id, category_id)
    │                       └── 现有新游戏初始化与进入大地图
```

- 一级与二级都不能直接创建世界或存档。
- 点击任意具体身份**立即进入最终确认页**，不存在「完成选择」「确认选择」「下一步」等中间按钮。
- 「最终确认」是正式提交身份选择结果的唯一入口。
- 返回修改回到一级类别页（当前类别保持高亮）；再次进入同一类别恢复此前身份选择，再次点击具体身份直接重新进入确认页；切换到其他类别时清除具体身份。

## 3. 配置

### 3.1 类别：`IdentityCategoryDefinition`

`Data/Identity/Categories/*.tres`，每个类别一个资源。

| 字段 | 说明 |
|---|---|
| `category_id` | 唯一类别 ID，例如 `NOBLE`、`COMMONER` |
| `display_name` | 一级按钮、二级标题与确认路径中的名称 |
| `sort_order` | 一级界面升序顺序 |
| `enabled` | 关闭后不显示，但配置可保留 |

### 3.2 身份：`IdentityDefinition`

`Data/Identity/Identities/*.tres`，每个身份一个资源。

| 字段 | 说明 |
|---|---|
| `identity_id` | 唯一身份 ID，不依赖显示名称 |
| `display_name` | 二级按钮与确认路径中的名称 |
| `category_id` | 关联的类别 ID |
| `description` | 二级界面展示的背景故事 |
| `sort_order` | 同类别内升序顺序 |
| `enabled` | 关闭后不显示 |

### 3.3 注册表：`IdentityCatalog`

`IdentityCatalog.load_default()` 扫描两个默认目录并注册配置：

- 类别 ID 重复、身份 ID 重复、身份引用不存在的类别、字段缺失、资源加载失败都会 `push_error` 并让加载失败。
- 只读静态配置，不进入存档；UI 不直接读文件。
- `get_enabled_categories()`、`get_enabled_identities(category_id)` 只返回启用项并按 `sort_order` 排序。
- 新增类别/身份只需增加 `.tres`，无需改 UI；一级按钮、二级按钮、标题与确认路径都由配置生成。

## 4. 全屏场景结构

`Scenes/Identity/identity_select.tscn` 根节点为全屏 `Control`，由脚本程序化构建：

```text
IdentitySelect (Control，全屏)
├── Background (TextureRect，纵向渐变)
├── CenterGlow (TextureRect，径向暖光)
├── TopGoldLine / BottomGoldLine (ColorRect)
└── ContentMargin (MarginContainer，按窗口宽度计算左右留白)
    └── ContentColumn (VBoxContainer)
        ├── CategoryPage
        │   ├── CategoryTitle
        │   ├── CategoryDescription
        │   ├── CategoryButtonList (纵向类别按钮)
        │   ├── CategoryStatusLabel
        │   └── IdentityCancelButton
        ├── IdentityPage
        │   ├── IdentityPageTitle
        │   ├── StoryPanel (StoryTitle + StoryLabel)
        │   ├── SelectionLabel
        │   ├── IdentityOptionScroll (ScrollContainer)
        │   │   └── IdentityOptionList (纵向身份按钮)
        │   └── IdentityFooter
        │       └── IdentityBackButton（二级唯一按钮，无完成选择）
        └── ConfirmPage
            ├── ConfirmTitle
            ├── ConfirmHint
            ├── ConfirmPathPanel -> ConfirmPathLabel
            ├── ConfirmStatusLabel
            ├── ReturnModifyButton
            └── FinalConfirmButton
```

- 背景、暖光、金线、局部按钮样式均在本场景内定义，不修改共享 `UiTheme`。
- 内容列最大宽度 640，左右留白按窗口宽度计算；文字自动换行。
- 一级与二级选项均为 `VBoxContainer` 纵向排列，不允许横向并排。
- 二级选项放在 `ScrollContainer` 中，最多显示 3 行；身份数量增加时只滚动选项区域，页面其余部分保持稳定。
- 确认页按钮纵向排列（「返回修改」「最终确认」）。
- 选中按钮使用按下样式（金色边框/底色）、金色文字，并在 `SelectionLabel` 显示「当前选择：名称」；返回与重新进入时按状态恢复。

## 5. 状态管理

| 状态 | 字段 | 规则 |
|---|---|---|
| 当前页面 | `_current_page` | `CATEGORY` / `IDENTITY` / `CONFIRM` |
| 已选类别 | `_selected_category_id` | 返回一级时保留；切换类别时更新 |
| 已选身份 | `_selected_identity_id` | 点击身份即写入并进入确认页；返回修改/返回一级时保留；切换到不同类别时清空 |
| 完整路径 | `_build_selection_path_parts()` | 依次收集类别、身份显示名称，用 `→` 连接 |

- 再次进入同一类别时按 `_selected_identity_id` 恢复按钮选中状态与故事文本。
- 确认页每次进入都根据当前状态重新生成路径，因此返回修改后的改动会同步。
- `_build_selection_path_parts()` 预留给未来多层选择：新增层级时按顺序追加显示名称，确认页无需重新设计。

## 6. 结果传递与数据归属

| 数据 | 写入者 | 生命周期 |
|---|---|---|
| `GameManager.player_identity_id` | `GameManager.start_new_game()` | 会话级；返回主菜单/读档/新游戏重建时清空 |
| `GameManager.player_identity_category_id` | `GameManager.start_new_game()` | 同上 |

- 身份选择场景只在最终确认时调用 `GameManager.start_new_game(identity_id, category_id)`。
- `start_new_game()` 保留无参默认值，旧调用方不受影响。
- 未来的身份差异化初始化应读取这两个字段；当前 `WorldInitializer` 不读取，也不产生任何差异。
- 不为身份新增存档字段，`schema_version` 不变。

## 7. 测试

- `Tests/SystemTests/identity_selection_ui_test.tscn`：主菜单释放与全屏场景进入、全屏尺寸、一级/二级纵向布局、故事切换、选中状态、点击身份立即进入确认页、不存在「完成选择/确认选择/下一步」中间按钮、确认路径与同步更新、返回修改回到一级并保留状态、切换类别清空状态、最终确认前无世界/无存档、最终确认后 ID 传递并进入 WorldMap。
- `Tests/_debug/identity_select_probe.tscn`：非 headless 截图验收，覆盖一级、二级、最终确认页及 1280×720 小窗口布局。

## 8. 扩展方向

- 身份差异化初始化（金币、装备、兵力、出生点、领主/家族身份）。
- 身份选择结果入档与读档恢复。
- 类别/身份的图标、背景图与更丰富的美术表现。
- 多层选择（特殊出身等）：追加配置层与路径段，沿用同一确认页。
