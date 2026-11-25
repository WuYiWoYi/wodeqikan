# 马匹个体系统

**核心数据：** `Scripts/Entities/Item/mount_instance_data.gd`、`Scripts/Entities/Item/inventory_data.gd`
**外观配置：** `Scripts/Config/mount_visual_config.gd`、`Scripts/Systems/Combat/horse_visual.gd`
**交易/装备：** `Scripts/Core/World/market_manager.gd`、`Scripts/Entities/Trade/trade_session.gd`、`Scripts/Core/World/unit_manager.gd`
**状态：** 独立实例、随机外观、装备/卸下、市场逐匹买卖、存档与旧档迁移已实现

---

## 1. 为什么马匹不再按数量堆叠

马匹拥有毛色、马鞍与个体 ID，若继续使用 `{ item_id: count }`：

- 出售/装备时无法确定具体是哪一匹马；
- 读档后外观可能重新随机，玩家看到“换了匹马”；
- 多匹马进入市场后无法逐匹展示与交易。

因此普通补给、凭证等仍按数量堆叠；**所有 MOUNT 槽装备自动视为不可堆叠物品**，由 `InventoryData.mount_instances` 保存。

## 2. MountInstanceData

| 字段 | 说明 |
|---|---|
| `instance_id` | 全局唯一实例 ID |
| `equipment_id` | 指向 `EquipmentConfig`（MOUNT 槽） |
| `coat_style_id` | `black` / `white` / `brown` |
| `saddle_style_id` | `saddle_01` … `saddle_08` |
| `display_name` | 可选个体名，只影响显示 |

规则：

- 随机外观只在**创建实例时**发生一次；之后随存档持久化。
- `EquipmentConfig.validate()` 在 MOUNT 槽时调用 `MountInstanceData.register_mount_item()`。
  背包、市场与旧档迁移都通过这一静态注册表判断“这是不是马”，不需要再维护第二份 ID 列表。
- `sanitize()` 修复缺失/非法外观：未知毛色回退棕马，未知马鞍回退 1 号。

## 3. 存储与守恒

`InventoryData` 同时被 `PlayerProfile` 与 `PartyData` 使用：

```text
stackable_counts: { item_id: count }   # 面包/草料/凭证
mount_instances:  Array[MountInstanceData]
inventory:        Array[String]        # 兼容 UI/旧存档的“出现过的 ID”
```

- `add_item(MOUNT_ID, n)` 生成 n 个独立实例，绝不写入 `stackable_counts`。
- `remove_item(MOUNT_ID, n)` 从实例列表移除 n 匹。
- 装备/卸下使用 `UnitManager.equip_mount_instance()` / `unequip_mount()`：
  从持有者移除实例 → 写入 `UnitData.mount_instance`；卸下时原样返还。
- 村庄贵族冒险者在招募前使用 `UnitManager.equip_detached_mount()` 装备自带实例；该接口只接受未注册单位，招募后仍走正式装备接口。
- 交易使用实例 ID 列表移动：市场与玩家背包之间不会复制、不会丢失。

## 4. 外观

`MountVisualConfig` 是毛色/马鞍贴图的唯一映射：

- `get_coat_paths(coat)` 返回头、身体、四条腿；
- `get_saddle_path(saddle)` 返回鞍具；
- 资源缺失时统一回退棕马/1 号马鞍。

`HorseVisual.rebuild(coat, saddle)` 只替换贴图，保留原有 `HorseBodyRig`、四条腿、层级与移动动画。
`UnitVisual` 从 `UnitData.mount_instance` 读取外观，所以同一兵种的不同马匹可以显示不同毛色/马鞍。

交易列表中的 `MountThumbnail` 复用同一份 `MountVisualConfig` 路径，按 48×96 画布等比缩放进固定图标框，不另建一套马匹美术。

## 5. 市场

- 城镇市场可为每匹马生成独立库存实例；
- 市场/玩家列表逐匹显示，按钮绑定 `instance_id`；
- 旧接口按 `{ mount_id: count }` 买卖时，`MarketManager` 自动转换为具体实例 ID；
- 市场记录 `initialized_items`，避免卖光后读档又被补满。

## 6. 存档与迁移

- `PlayerProfile.to_dict()` 保存 `inventory_counts` 与 `mount_instances`。
- `PartyData` 以相同结构保存 NPC 背包。
- `UnitData` 保存 `mount_instance`；旧档缺少时按 `unit_id + equipment_id` 确定性生成。
- 旧档把马匹存在数量中：
  - 玩家背包 → `InventoryData._migrate_legacy_mount_counts()`；
  - 市场库存 → `MarketData.from_dict()`；
  - 都使用 `create_deterministic(equipment_id, seed)`，同一旧档反复读取得到相同实例 ID 与外观，不会增殖。

## 7. 边界

- 马匹属性仍来自 `EquipmentConfig`，实例不复制属性。
- `SupplyManager` 只统计“已装备 + 背包”的马匹；市场中待售马匹不消耗草料。
- 不允许 UI 直接改 `mount_instances`；装备、交易、迁移都走管理器/数据类接口。
