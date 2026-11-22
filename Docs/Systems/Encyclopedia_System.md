# 百科系统

**状态：** 阶段 13 后重构（一级分类 + 二级详情 + 敌对势力）
**相关代码：** `Scripts/UI/WorldMap/world_map.gd`
**数据来源：** `KingdomManager`、`HouseManager`、`NobleManager`、`SettlementManager`、`FactionManager`、`FamilyRegistry`

---

## 1. 入口与显示

- 大地图顶栏“百科”按钮（节点名 `EncyclopediaButton`）。
- 点击后显示屏幕空间遮罩 `EncyclopediaDim` 与面板 `EncyclopediaPanel`。
- 打开时压入 `ui_panel` 暂停原因；不暂停相机、不重置相机位置。
- 关闭后移除该暂停原因，恢复关闭前的世界倍率与相机位置。
- 建筑信息面板打开时仍可打开百科；百科与其他覆盖层（部队、背包、事件、保存等）互相阻塞。
- 百科打开期间世界时间控制按钮禁用，地图输入被屏蔽。

## 2. 导航

```text
一级：分类（王国 / 家族 / 地点）
  └── 点击分类 → 条目列表
        └── 点击条目 → 二级：详情
              └── 返回 → 条目列表
                    └── 返回 → 一级分类
```

- 一级只显示分类入口，不显示任何具体王国/家族/地点详情。
- `EncyclopediaBackButton` 在历史为空（一级）时隐藏，其余层级可见。
- `EncyclopediaCloseButton` 始终可关闭面板。
- 列表使用 `ScrollContainer` + `VBoxContainer`（`EncyclopediaScroll` / `EncyclopediaList`）。
- 详情页中的可跳转条目（王国、家族）会压入历史，允许继续跳转后逐级返回。

## 3. 各级内容

### 一级：分类

三个同级分类按钮：

- `EncyclopediaCategory_Kingdoms`：王国（数量）。
- `EncyclopediaCategory_Houses`：家族（数量）。
- `EncyclopediaCategory_Locations`：地点（数量）。

### 二级：条目列表

**王国列表**（`EncyclopediaKingdom_<kingdom_id>`）显示王国名称、统治家族、国王、附庸家族数量、封地总数、对玩家关系、战争状态。

**家族列表**（`EncyclopediaHouse_<house_id>`）显示家族名称、徽章、所属王国或“独立家族”、对玩家关系。

**地点列表**（`EncyclopediaSettlement_<settlement_id>`）显示地点名称、类型、所有者。

### 二级：王国详情

- 统治家族（徽章、名称、领袖/国王）。
- 其他贵族（名称/爵位/部队/存活）。
- 可点击的附庸家族（`EncyclopediaHouse_<house_id>`）。
- 按家族分组的封地列表（名称/类型/所有者）。
- “敌对势力”区块：敌对王国（`EncyclopediaEnemyKingdom_<kingdom_id>`）与敌对独立家族。

### 二级：家族详情

- 家族名称、徽章、所属王国或“独立家族”。
- 领袖。
- 贵族列表：名称/爵位/是否领袖/是否国王/部队/存活状态（已故）。
- 封地列表：名称/类型/所有者。
- “敌对势力”区块：敌对王国（可跳转）与敌对独立家族（可跳转）。

### 二级：地点详情

- 类型、所有者（贵族 → 家族 → 视觉家族 → 无主）。
- 所属家族（可跳转）与所属王国（可跳转）。
- 人口、繁荣度、预计每日税收。
- 村庄显示采邑储备；城镇/城堡显示“不适用”。
- 不新增地点属性或玩法。

## 4. 敌对势力数据

- 王国详情：敌对王国来自 `KingdomManager.get_enemy_kingdoms()`；敌对独立家族来自
  `FactionManager.get_hostile_independent_houses_for_kingdom()`。
- 家族详情：敌对王国来自 `FactionManager.get_hostile_kingdoms_for_house()`；敌对独立家族来自
  `FactionManager.get_hostile_independent_houses_for_house()`。
- 关系判定统一走 `FactionManager.get_house_relation()` 与王国成员关系，百科 UI 不维护独立敌对表。
- 无敌对项时显示明确空状态；友好/中立势力不会被误列为敌对。

## 5. 徽章

- 优先使用 `FamilyConfig.banner_texture_path` 对应的纹理。
- 缺失或加载失败时显示占位徽章 `HouseBadgePlaceholder`，不报错。
- 徽章为屏幕空间固定尺寸，不随相机缩放。

## 6. 动态刷新

- 面板打开时，`_refresh_encyclopedia_if_needed()` 在 `_process` 中比较数据签名。
- 签名包含当前视图、选中的王国/家族/地点 ID，以及王国/家族/贵族存活/封地归属等关键字段。
- 数据变化时重建当前页面；敌对关系、贵族死亡、封地易主会自然反映。
- 无变化时不重建，避免每帧创建节点。

## 7. 暂停规则

- 打开：`TimeManager.push_pause(PAUSE_REASON_UI_PANEL)`。
- 关闭：`TimeManager.pop_pause(PAUSE_REASON_UI_PANEL)`。
- `push_pause/pop_pause` 按原因计数，支持嵌套；关闭百科不会提前解除仍在打开的建筑/部队面板暂停。
- 不改变 `base_world_speed`，因此关闭后恢复原倍率。

## 8. 数据权威

百科只读管理器数据，不直接修改：

- 不写贵族/家族/王国。
- 不分配封地。
- 不改变玩家部队或阵营。
- 不推进世界时间。

## 9. 未实现

- 搜索、排序、筛选。
- 人物/部队详情页。
- 战争历史、封地历史与事件时间线。
- 手柄/触屏导航与快捷键。
- 地图标记与百科条目联动。
