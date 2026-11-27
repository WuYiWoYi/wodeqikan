# 新游戏文化与身份选择

**核心脚本：** `Scripts/UI/Identity/identity_select.gd`
**场景：** `Scenes/Identity/identity_select.tscn`（独立全屏场景）
**配置：** `Scripts/Config/identity_catalog.gd`、`culture_definition.gd`、`identity_definition.gd`、
`identity_visual_config.gd`、`Data/Cultures/*.tres`、`Data/Identity/Categories/*.tres`、
`Data/Identity/Identities/*.tres`、`Data/Identity/identity_visual_config.tres`
**状态：** 已实现文化选择 → 身份选择 → 最终路线预览三级全屏流程，并将所选身份接入实际开局：出生地点、玩家家族/贵族、家族领袖/国王、平民无家族。文化天赋与身份加成仍只做展示。

---

## 1. 范围与硬边界

- 主菜单「新游戏」通过 `SceneManager` 切到独立全屏选择场景，主菜单场景被释放，不存在附着弹窗或局部面板。
- 三级流程全部在同一场景内完成；进入预览并确认前不创建 `WorldContext`、不启动世界时间、不写存档。
- 只有最终路线预览页的「开始游戏」会调用 `GameManager.start_new_game(identity_id, category_id, culture_id)`。
- 文化天赋与身份加成**仅用于界面展示**；不修改采邑恢复、部队上限、工资或驻军薪资。
- 身份选择结果决定实际开局数据：出生地点、玩家家族、贵族爵位、家族领袖/国王、平民是否启用家族系统。
- 身份字段随 `WorldContext` 进入存档（可选字段），读档时恢复；不新增 Schema 版本。
- 不修改战斗与家族核心架构；贵族身份复用现有家族/贵族系统，不为平民伪造贵族记录。

## 2. 流程

```text
主菜单「新游戏」
└── SceneManager -> IdentitySelect（独立全屏场景）
    ├── 文化选择
    │   ├── 默认选中第一个文化
    │   ├── 悬浮预览左侧描述，点击只选定
    │   ├── 退回 -> 主菜单（不启动游戏）
    │   └── 确认文化
    │       └── 身份选择（默认选中该文化第一个身份）
    │           ├── 悬浮预览左侧描述，点击只选定
    │           ├── 退回 -> 文化选择（保留文化与身份）
    │           └── 确认身份
    │               └── 最终身份路线预览
    │                   ├── 退回 -> 身份选择（保留身份）
    │                   └── 开始游戏
    │                       └── GameManager.start_new_game(...)
    │                           └── 现有新游戏初始化与进入大地图
```

- 点击选项**不自动进入下一层**；只有底部确认按钮推进流程。
- 每一级进入时都存在默认选中项，不存在空选择或确认按钮不可用状态。
- 文化层退回主菜单；身份层/预览层退回上一级，不会一次退出整个流程。

## 3. 配置

### 3.1 文化：`CultureDefinition`

`Data/Cultures/*.tres`，每个文化一个资源。

| 字段 | 说明 |
|---|---|
| `culture_id` | 唯一文化 ID，例如 `CULTURE_DORAMAN` |
| `display_name` | 文化选项与路线预览中的名称 |
| `description` | 文化层左侧背景介绍，支持多段换行 |
| `talent_lines` | 文化天赋展示行；未确定项使用「待设定」占位 |
| `sort_order` | 文化列表升序顺序 |
| `enabled` | 关闭后不显示，但配置保留 |

### 3.2 身份类型：`IdentityCategoryDefinition`

`Data/Identity/Categories/*.tres`。当前为「贵族」「平民」，只作为身份类型名称与排序依据。

| 字段 | 说明 |
|---|---|
| `category_id` | `NOBLE` / `COMMONER` |
| `display_name` | 左侧「身份类型」与路线预览中的类型名称 |
| `sort_order` | 同文化内的身份类型顺序（贵族 0、平民 1） |
| `enabled` | 关闭后不显示 |

### 3.3 身份：`IdentityDefinition`

`Data/Identity/Identities/*.tres`，每个身份一个资源。

| 字段 | 说明 |
|---|---|
| `identity_id` | 唯一身份 ID，不依赖显示名称 |
| `display_name` | 身份选项与路线预览中的名称 |
| `category_id` | 关联的身份类型 |
| `culture_id` | 关联的文化；身份层按文化过滤 |
| `description` | 身份背景故事，支持多段换行 |
| `bonus_lines` | 身份加成展示行；未确定项使用「待设定」占位 |
| `sort_order` | 同文化内的显示顺序 |
| `enabled` | 关闭后不显示 |
| `spawn_location_id` | 开局出生点绑定的大地图地点 key（必填） |
| `family_id` | 视觉/政治家族 ID（`FAMILY_*`）；贵族身份必填，平民留空 |
| `family_system_enabled` | 是否启用家族/贵族系统；贵族 `true`，平民 `false` |
| `starts_as_house_leader` | 开局是否接管该家族领袖；瓦伊拉领袖为 `true` |
| `independent_house` | 家族是否保持独立、不建立/加入任何王国；瓦伊拉领袖为 `true` |
| `starting_rank` | `NobleData.Rank` 数值；启用家族系统时必须 > 0 |

- `validate()` 要求身份 ID、显示名、类型、文化、出生点非空；启用家族系统时家族 ID 与爵位必须有效，关闭时两者必须为空。
- `independent_house = true` 时必须同时 `family_system_enabled = true` 且 `starts_as_house_leader = true`，否则无法脱离所属王国。
- 所属王国不单独配置，由 `family_id` 对应 `HouseData.kingdom_id` 推导；独立家族推导结果为空。
- 平民身份即使配置了 `family_id` 也视为无效配置（`validate()` 返回 `false`）。

### 3.4 六个正式身份

| 身份 | 类型 | 出生点 key | 家族 | 王国 | 爵位 | 家族领袖 |
|---|---|---|---|---|---|---|
| 埃克托家族的次子 | 贵族 | `ektor_town` | `FAMILY_EKTOR` → `HOUSE_EKTOR` | 伯克纳 | KNIGHT | 否（效忠原领袖） |
| 多拉曼佣兵 | 平民 | `bafleborg` | 无 | 无 | 无 | 否 |
| 丁达尼家族骑士 | 贵族 | `dindani_castle` | `FAMILY_DINDANI` → `HOUSE_DINDANI` | 弗拉尼 | KNIGHT | 否 |
| 弗拉尼的商人 | 平民 | `frania` | 无 | 无 | 无 | 否 |
| 瓦伊拉家族领袖 | 贵族 | `vaila_castle` | `FAMILY_VAILA` → `HOUSE_VAILA` | 无（独立家族） | DUKE | 是 |
| 无赖骑士 | 平民 | `rosviknia` | 无 | 无 | 无 | 否 |

### 3.5 详情贴图映射：`IdentityVisualConfig`

`Data/Identity/identity_visual_config.tres`，独立于文化/身份定义管理左侧详情贴图。

| 字段 | 说明 |
|---|---|
| `culture_textures` | 键为 `culture_id`，值为 `Texture2D` |
| `identity_textures` | 键为 `identity_id`，值为 `Texture2D` |

- UI 通过 `IdentityVisualConfig.load_default()` 读取映射，不硬编码贴图路径。
- 未配置或贴图为空的条目由 UI 隐藏整块立绘区域，不显示占位文本、空白框或背景。
- 新增文化/身份贴图只需在映射资源中增加条目，无需修改 UI。
- 当前三个文化已配置 `Art/我的骑砍临时美术/正式美术_其他/UI美术/UI身份选择标签贴图/` 下的贴图；身份贴图已接入「埃克托家族次子」，其余身份尚未提供，无资源时隐藏。

### 3.6 注册表：`IdentityCatalog`

`IdentityCatalog.load_default()` 扫描 `Data/Cultures`、`Data/Identity/Categories`、`Data/Identity/Identities`：

- 文化 ID 重复、身份 ID 重复、身份引用不存在的文化/类别、资源加载失败都会 `push_error` 并让加载失败。
- 只读静态配置，不进入存档；UI 不直接读文件。
- `get_enabled_cultures()` 返回启用文化并按 `sort_order` 排序。
- `get_enabled_identities_for_culture(culture_id)` 只返回该文化的启用身份，先按身份类型 `sort_order`、再按身份 `sort_order` 排序。
- 新增文化/身份只需增加 `.tres`，无需改 UI。
- 文化配置字段通过 `Resource` 动态读取，不依赖新 `class_name` 的全局类缓存；新增文化资源后无需先修改代码。

## 4. 全屏场景结构

`Scenes/Identity/identity_select.tscn` 根节点为全屏 `Control`，由脚本程序化构建：

```text
IdentitySelect (Control，全屏)
├── Background / CenterGlow / TopGoldLine / BottomGoldLine
└── ContentMargin (MarginContainer，按窗口宽度计算留白)
    └── ContentColumn (VBoxContainer)
        ├── Header (HeaderTitle + HeaderSubtitle)
        ├── CulturePage (HBoxContainer)
        │   ├── CultureDetailPanel（标题 / 类型 / 描述滚动区 + 右下角贴图 / 独立天赋面板）
        │   └── CultureSelectionPanel（纵向文化选项 / 提示）
        ├── IdentityPage (HBoxContainer)
        │   ├── IdentityDetailPanel（标题 / 身份类型 / 描述滚动区 + 右下角贴图 / 独立加成面板）
        │   └── IdentitySelectionPanel（纵向身份选项 / 提示）
        ├── PreviewPage (PanelContainer，居中显示完整路线)
        ├── RoutePanel（底部「最终身份路线」实时预览）
        └── Footer（BackButton / ConfirmButton）
```

- 背景、暖光、金线与按钮样式均在本场景内定义，不修改共享 `UiTheme`。
- 左侧详情与右侧选项为左右分区；左侧描述在独立 `ScrollContainer` 内滚动，加成区为独立面板。
- 右侧选项纵向排列在 `ScrollContainer` 中；数量增加时只滚动选项区域。
- 预览页隐藏左右选项区与底部路线条，居中展示完整三级路线。

### 4.1 左侧详情

- 文化层：文化名称、类型「文化」、背景描述、文化天赋。
- 身份层：身份名称、「身份类型：贵族/平民」、背景描述、身份加成。
- 未确定天赋/加成使用「待设定」占位文本并以弱化颜色显示。
- 加成行数变化时列表自适应高度。
- 描述区右下角、加成栏上方固定展示当前文化/身份贴图；贴图为独立节点，不随描述滚动。
- 描述滚动区预留贴图宽度，长文本在贴图左侧换行滚动，不会与贴图重叠；悬浮预览时贴图同步切换，离开后恢复已选项。
- 立绘区域无背景底色、边框与装饰轮廓，贴图直接融入左侧描述区；展示范围约为原尺寸的 1.5 倍（宽 198、高 156–252）。
- 贴图按可用区域等比例缩放并水平/垂直居中（`STRETCH_KEEP_ASPECT_CENTERED` + `EXPAND_IGNORE_SIZE`）：超尺寸自动缩小，小图放大到展示区上限，始终保持原始比例且不裁剪主体。
- 无贴图时整块立绘区域隐藏（不显示「暂无立绘」、空白框或背景），不影响描述文本、加成栏与交互；窗口变矮时降低最大高度。

### 4.2 右侧选项

- 文化层：三个文化按钮。
- 身份层：当前文化对应的贵族/平民两条身份路线。
- 选中项使用金色边框、金色文字与按下底色；悬浮项使用金色边框但不改变选中状态。
- 选项按钮只显示名称，身份类型由左侧详情与路线预览展示。

## 5. 交互规则

| 操作 | 行为 |
|---|---|
| 进入任意一级 | 默认选中列表第一个选项；左侧展示其描述与加成；路线预览同步更新 |
| 悬浮选项 | 左侧临时展示该选项内容；不改变选中项、不改变层级、不改变路线预览 |
| 悬浮离开 | 左侧恢复当前已选选项 |
| 点击选项 | 只更新选中项、左侧详情与路线预览；不进入下一层 |
| 确认（文化层） | 进入身份层；切换过文化时旧身份清空，否则保留原身份 |
| 确认（身份层） | 进入最终路线预览 |
| 确认（预览层） | 调用现有新游戏初始化并进入大地图 |
| 退回（文化层） | 返回主菜单，关闭选择界面，不启动游戏 |
| 退回（身份层） | 返回文化层，保留文化与身份 |
| 退回（预览层） | 返回身份层，保留身份 |

## 6. 路线预览

底部 `RoutePanel` 在文化与身份层持续可见，预览页居中放大显示同一内容：

```text
布吉多人
  └── 平民
       └── 弗拉尼的商人
```

- 尚未选择身份时显示：

```text
多拉曼人
  └── 身份：待选择
```

- 路线始终由当前 `_selected_culture_id` / `_selected_identity_id` 生成，不允许与实际选择不一致。
- 返回上一级时保留选择，因此路线继续展示已选身份。

## 7. 状态管理

| 状态 | 字段 | 规则 |
|---|---|---|
| 当前页面 | `_current_page` | `CULTURE` / `IDENTITY` / `PREVIEW` |
| 已选文化 | `_selected_culture_id` | 返回文化层时保留；切换文化时更新 |
| 已选身份 | `_selected_identity_id` | 切换文化时若不属于新文化则清空；返回各级时保留 |
| 悬浮文化/身份 | `_hovered_culture_id` / `_hovered_identity_id` | 只影响左侧详情，离开后清空并恢复已选项 |
| 路线文本 | `_build_route_text()` | 文化 → 身份类型 → 身份名称 |

- 确认按钮的可用性由当前层选择状态决定；默认选择保证进入每层时始终可用。
- 预览页的确认按钮文案为「开始游戏」，是唯一提交入口。

## 8. 结果传递与实际开局

### 8.1 调用链

```text
选择场景「开始游戏」
└── GameManager.start_new_game(identity_id, category_id, culture_id)
    ├── IdentityCatalog.load_default().get_identity(identity_id)
    ├── 校验 category_id / culture_id 与身份配置一致
    ├── 写入 GameManager 会话字段
    └── WorldInitializer.create_new_world(context, identity)
        ├── 校验 spawn_location_id 存在
        ├── 在出生点附近生成玩家部队
        ├── 写入 context 身份字段
        └── 贵族：绑定正式家族并创建玩家贵族
            平民：不创建家族/贵族记录
```

- `identity_id` 为空时回退 `WorldInitializer.DEFAULT_IDENTITY_ID`（`IDENTITY_EKTOR_SECOND_SON`），保证旧调用方与测试仍得到有效世界。
- `category_id` / `culture_id` 为空时不额外校验；非空且与身份配置不一致时报错，避免 UI 选择与实际身份错位。
- 选择场景只在最终预览页调用 `start_new_game`；其他入口（旧测试、调试）可只传 `identity_id`。

### 8.2 数据写入者

| 数据 | 写入者 | 说明 |
|---|---|---|
| `GameManager.player_identity_id/category_id/culture_id` | `GameManager.start_new_game()` / `load_game()` / `enter_game_world()` | 会话镜像，来自身份或 `WorldContext` |
| `WorldContext.player_identity_id` | `WorldInitializer.create_new_world()` / `load_from_save_data()` | 权威会话身份 ID |
| `WorldContext.player_identity_category_id` | 同上 | `NOBLE` / `COMMONER` |
| `WorldContext.player_culture_id` | 同上 | 文化 ID |
| `WorldContext.player_identity_name` | 同上 | 身份显示名，用于玩家贵族名与 UI |
| `WorldContext.player_house_id` | `WorldInitializer` / 读档 | 贵族身份为正式家族；平民为空 |
| `WorldContext.player_lord_id` | `WorldInitializer` / 读档 | 贵族身份为新建玩家贵族；平民为空 |
| 玩家部队 `family_id` | `WorldInitializer` | 贵族身份 = 身份 `family_id`；平民为空 |

- 玩家贵族使用身份显示名，`is_player_lord = true`；`rank` 来自 `starting_rank`，`is_house_leader` 来自 `starts_as_house_leader`。
- `starts_as_house_leader = false` 时，玩家贵族效忠原家族领袖；`true` 时接管家族领袖。
- `independent_house = false` 且接管的家族是某王国统治家族时，`KingdomManager` 同步玩家为该国国王。
- `independent_house = true` 时跳过该王国的注册：家族保持 `kingdom_id` 为空，玩家只是家族领袖而非国王，世界王国数相应少 1（瓦伊拉领袖为 5 个王国）。
- 平民不创建 `NobleData`；`get_player_house()` / `get_player_noble()` 返回 `null`，家族 UI 显示空状态而不是伪造家族。

### 8.3 存档

- `WorldContext.to_save_data().player` 追加可选字段 `identity_id`、`identity_category_id`、`culture_id`、`identity_name`。
- 读档恢复上述字段；旧存档缺少这些字段时保持为空，不影响加载。
- `schema_version` 保持 v10：字段为可选追加，不改变既有结构语义。

## 9. 瓦伊拉家族美术资源

- `Data/Families/family_vaila.tres` 引用 `Art/正式人物美术/瓦伊拉家族风格美术/` 下的独立资源：
  - `瓦伊拉旗帜16_16.png`
  - `瓦伊拉风格罩袍_主.png` / `瓦伊拉风格罩袍_副.png`
  - `瓦伊拉风格缨饰.png`
  - `瓦伊拉风格长矛.png`
  - `瓦伊拉风格盾牌.png`
- 资源复制自当前玩家家族风格，但与 `family_player.tres` 分开存放、独立命名，不引用或覆盖玩家资源。
- 目录、命名与加载方式沿用现有 `FamilyConfig` 与 `FamilyRegistry`；家族注册表自动扫描 `Data/Families`，无需额外注册。
- 「瓦伊拉家族领袖」身份已接入实际开局：玩家接管 `HOUSE_VAILA` 领袖，家族保持独立、不建立 `KINGDOM_VAILA`，玩家不是国王。

## 10. 测试

- `Tests/SystemTests/identity_selection_ui_test.tscn`：配置加载（三文化、每文化两身份、先贵族后平民）、详情贴图映射加载、埃克托家族次子立绘映射、文化贴图随默认选中/悬浮/离开切换、无身份贴图时隐藏整块立绘区域且无占位节点、立绘无背景与边框、展示尺寸约为原来的 1.5 倍、贴图位于加成栏上方且不与描述文本重叠、保持比例与居中缩放、1280×720 布局、主菜单释放与全屏场景、文化层默认选中与悬浮预览、点击不跳转、确认进入身份层、身份层默认选中、悬浮不改变选中、确认进入预览、三级退回保留选择、路线预览完整、确认前无世界/无存档、确认后传递三个 ID 并进入 WorldMap、瓦伊拉美术文件存在且可解码、与玩家资源路径不同。
- `Tests/SystemTests/identity_startup_test.tscn`：六个正式身份的配置校验、出生点距离与可通行、贵族/平民绑定、玩家爵位/效忠/家族领袖、瓦伊拉玩家保持独立家族领袖（不建立王国）、平民无家族/无贵族记录、青禾村/北境村/北境巡逻队已移除、17 个正式家族、身份字段存档往返、平民读档不被补成贵族。
- `Tests/SystemTests/identity_faction_relation_test.tscn`：六个身份的开局阵营关系（家族→王国→战争→中立）、文化不参与判定、瓦伊拉独立家族不卷入他国战争、大地图部队外环与建筑底板统一读取 `FactionManager`。
- `Tests/_debug/identity_select_probe.tscn`：非 headless 视觉验收，覆盖文化层、悬浮、选中、身份层、路线预览与 1280×720 小窗口布局。

## 11. 扩展方向

- 文化与身份加成接入实际游戏系统（部队上限、薪资、采邑恢复等）。
- 身份差异化初始资源（金币、装备、兵力模板）。
- 平民晋升/加入家族的长期路径（当前平民身份不启用家族系统）。
- 继续为其他身份补充专属立绘，并在 `identity_visual_config.tres` 中扩展更多文化/身份贴图。
