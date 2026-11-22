# 百科系统

**状态：** 阶段 8 已交付
**相关代码：** `Scripts/UI/WorldMap/world_map.gd`
**数据来源：** `KingdomManager`、`HouseManager`、`NobleManager`、`SettlementManager`、`FactionManager`、`FamilyRegistry`

---

## 1. 入口与显示

- 大地图顶栏新增“百科”按钮（节点名 `EncyclopediaButton`）。
- 点击后显示屏幕空间遮罩 `EncyclopediaDim` 与面板 `EncyclopediaPanel`。
- 打开时压入 `ui_panel` 暂停原因；不暂停相机、不重置相机位置。
- 关闭后移除该暂停原因，恢复关闭前的世界倍率与相机位置。
- 百科可见时，大地图输入被屏蔽（与队伍面板、地点面板一致）。

## 2. 导航

```text
一级：王国列表
  └── 点击王国 → 二级：王国详情
        └── 点击附庸家族 → 三级：家族详情
              └── 返回 → 二级
                    └── 返回 → 一级
```

- `EncyclopediaBackButton` 仅在一级隐藏。
- `EncyclopediaCloseButton` 始终可关闭面板。
- 列表使用 `ScrollContainer` + `VBoxContainer`（`EncyclopediaScroll` / `EncyclopediaList`）。

## 3. 各级内容

### 一级：王国列表

每个王国一个按钮（`EncyclopediaKingdom_<kingdom_id>`），显示：

- 王国名称。
- 统治家族名称与徽章。
- 国王名称。
- 附庸家族数量。
- 封地总数（包含附庸封地）。
- 玩家与该王国的关系（中立/敌对/友好）。
- 战争状态（交战中/和平）。

### 二级：王国详情

- 统治家族名称、徽章、领袖。
- 国王。
- 其他贵族（名称/爵位/部队/存活）。
- 可点击的附庸家族按钮（`EncyclopediaHouse_<house_id>`）。
- 按家族分组的封地列表（名称/类型/所有者）。

### 三级：家族详情

- 家族名称、徽章。
- 所属王国。
- 领袖。
- 贵族列表：名称/爵位/是否领袖/是否国王/部队/存活状态（已故）。
- 封地列表：名称/类型/所有者。

## 4. 徽章

- 优先使用 `FamilyConfig.banner_texture_path` 对应的纹理。
- 缺失或加载失败时显示占位徽章 `HouseBadgePlaceholder`，不报错。
- 徽章为屏幕空间固定尺寸，不随相机缩放。

## 5. 动态刷新

- 面板打开时，`_refresh_encyclopedia_if_needed()` 在 `_process` 中比较数据签名。
- 签名包含王国/家族的领袖、国王、贵族存活、封地归属等关键字段。
- 数据变化时重建当前层级列表，滚动位置尽量保持。
- 无变化时不重建，避免每帧创建节点。

## 6. 暂停规则

- 打开：`TimeManager.push_pause(PAUSE_REASON_UI_PANEL)`。
- 关闭：`TimeManager.pop_pause(PAUSE_REASON_UI_PANEL)`。
- 不改变 `base_world_speed`，因此关闭后恢复原倍率。
- 与部队面板/地点面板共用暂停原因栈；不会重复压栈。

## 7. 数据权威

百科只读管理器数据，不直接修改：

- 不写贵族/家族/王国。
- 不分配封地。
- 不改变玩家部队或阵营。
- 不推进世界时间。

所有显示文本由当前管理器状态生成，因此贵族死亡、战争状态变化、封地易主会自然反映。

## 8. 未实现

- 搜索、排序、筛选。
- 人物/部队详情页与跨层级跳转。
- 战争历史、封地历史与事件时间线。
- 手柄/触屏导航与快捷键。
- 地图标记与百科条目联动。
