# 变更日志

**读取级别：** 历史记录，默认不读；只在追溯“何时改了什么”时按日期/阶段检索。

只记录重要变更、架构调整和接口变化。日常小改动由 Git 历史承担。当前实现状态以 [Development/Current_Status.md](Development/Current_Status.md) 为准；阶段内的详细实现与测试清单见 [Archive/Status_History.md](Archive/Status_History.md)。

---

## 2026-11-27 · 大地图日志折叠、玩家宣战与阵营视觉反馈

### 变更

- `WorldLogPanel` 新增可选折叠态：大地图默认只显示最新事件文本，隐藏底板/标题/滚动条；点击文本展开，点击其他区域折叠；村庄共享面板保持完整显示。折叠态面板不拦截地图输入，展开态拦截自身区域。
- `FactionManager` 新增以玩家为中心的统一关系接口 `PlayerRelation`（`get_player_relation_for_house/party/settlement/kingdom`）与 `declare_player_hostility_against_party/house`；玩家家族关系委托该接口，AI/遭遇/战斗/百科自动获得同一结果。
- 玩家主动攻击成功创建战斗后触发宣战：目标家族敌对；目标属于王国时整个王国及其成员家族、建筑敌对；玩家未加入王国也生效。玩家已有王国时同步建立正式王国战争。
- 个人宣战记录保存到已有 `SaveData.factions`（`player_hostile_house_ids` / `player_hostile_kingdom_ids`），增量字段、不升级 Schema。
- 新增 `EventBus.faction_relations_changed`；`KingdomManager` 在宣战/停战/附庸变化时广播，大地图据此批量刷新。
- `PartyIcon` 增加持续阵营外环：玩家蓝、同阵营绿、敌对红、中立无；沿用原蓝色外环的半径/线宽/正圆绘制，不影响尺寸、旗帜、悬浮与点击。
- `SettlementNameTag` 增加阵营底板颜色：同阵营绿色半透明、敌对红色半透明、中立保持黑色半透明；不改变底板尺寸、透明度基准、文字与建筑美术。

### 验证

- 已运行并通过：`player_faction_relation_ui_test`（新增）、`world_log_ui_test`、`faction_vision_test`、`faction_bandit_hostility_test`、`political_hierarchy_test`、`party_attack_confirmation_test`、`party_dialogue_test`、`world_map_milestone6_test`、`stage13_world_map_ui_test`、`ai_encounter_flow_test`。

### 文档

- `World_Log_System.md`、`Political_Hierarchy_System.md`、`World_Map_System.md`、`01_Core_Architecture.md` 事件契约同步更新。

---

## 2026-11-27 · 大地图 UI 架构审查第一轮：覆盖层登记簿、百科与存档拆出

### 变更

- `world_map.gd` 移除 11 个 `_xxx_pause_active` 布尔与 28 处手动 `pop_pause` 调用，改为 `MapOverlayRegistry` 统一登记覆盖层可见性与暂停原因；`_has_open_modal` 改为登记簿查询，`_exit_tree` 统一 `release_all()`。
- 新增 `Scripts/UI/WorldMap/map_overlay_registry.gd`、`map_ui_kit.gd`、`world_map_encyclopedia.gd`、`world_map_save_panel.gd`。
- 百科与存档面板的实现迁入独立组件；`EncyclopediaPanel`、`SavePanel` 等节点名与根公开方法保持兼容，测试未改。
- `world_map.gd` 5562 → 4762 行；未改变存档结构、世界数据权威、UI 布局与交互规则。

### 验证

- 已运行并通过：`world_map_input_test`、`world_map_layout_test`、`world_map_battle_marker_test`、`world_map_move_target_test`、`world_map_milestone6_test`、`family_panel_ui_test`、`event_center_test`、`lord_ransom_test`、`settlement_interaction_test`、`party_dialogue_test`、`party_attack_confirmation_test`、`player_encounter_test`、`neutral_party_interaction_test`、`party_intent_hover_test`、`battle_occupancy_ui_test`、`stage13_world_map_ui_test`、`stage13_tavern_test`、`town_market_ui_test`、`party_economy_ui_test`、`world_log_ui_test`、`captivity_escape_test`、`fief_adventurer_ui_test`、`player_battle_interaction_test`、`encyclopedia_ui_test`、`main_map_info_test`、`milestone1_test`。
- 已知既有失败（与本次无关）：`party_panel_test` 断言玩家移速字符串 “150”，当前初始化为 450。

### 文档

- `Encyclopedia_System.md`、`World_Map_System.md`、`Scene_System.md` 更新代码位置；新增 D173。

---

## 2026-11-27 · 部队旗帜最长边 60 → 48

### 变更

- `PartyMarkerStyle.flag_max_size` 60 → 48：有效旗帜（30×36）等比放大到最长边 48，精灵实际尺寸 40×48（缩放 4/3）。
- 旗帜圆形遮罩仍取黑色描边内缘 16.25；局部半径随精灵缩放自动换算（12.1875），正圆、同心、无溢出等规则不变。
- `marker_radius` 18、`border_width` 2、`outline_width` 2.5、点击/悬浮区域与交互均未改变。
- `stage13_world_map_ui_test` 按需求断言 `flag_max_size == 48`；`encounter_dialogue_ui_test` 的放大上限恢复为 `marker_radius * 3.0`。

### 验证

- 已运行并通过：`stage13_world_map_ui_test`、`encounter_dialogue_ui_test`。

---

## 2026-11-27 · 修复部队标记圆形失真（AtlasTexture 图集 UV 导致旗帜遮罩变椭圆）

### 根因

- 旗帜遮罩 shader 把 canvas `UV` 当作有效贴图的 0–1 使用，但裁切后的旗帜是 `AtlasTexture`，`UV` 实际是整张图集的归一化坐标（实测 48×48 图集、30×36 有效区域：u≈0.188–0.813，v≈0.125–0.875）。
- 遮罩因此不再是半径 16.25 的正圆，而是约 52×43 世界像素的椭圆：横向覆盖整个黑色描边并溢出 36 像素圆形标记，视觉上表现为“圆形被拉伸/标记变成椭圆”。圆形底盘与描边本身一直由 `draw_circle`/`draw_arc` 在局部坐标绘制，没有被非等比缩放。

### 变更

- `map_flag_circle.gdshader` 新增 `use_local_circle` 模式：`vertex()` 用 `varying vec2 local_position` 传出画布局部像素坐标，`fragment()` 按显式 `circle_center` / `circle_radius` 裁剪；保留默认 UV 模式供地点徽章等既有调用。
- `PartyIcon` 的旗帜遮罩改用局部正圆模式：`circle_center = (0, 0)`，`circle_radius = get_flag_clip_radius() / flag_sprite.scale.x`；缩放后世界半径严格等于黑色描边内缘 16.25，与主体、黑色描边、玩家外圈、白色悬浮描边共用同一局部坐标系与圆心。
- 移除仅供旧 UV 模式使用的 `PartyMarkerStyle.get_flag_clip_uv_radius()`；`flag_max_size 60`、`outline_width 2.5`、`marker_radius 18`、点击/悬浮半径与交互逻辑均未改变。
- `stage13_world_map_ui_test` 改为断言局部正圆参数、遮罩世界半径、节点/父节点无非等比缩放，并补充 0.5x/1x/2x 相机缩放等比与半径基准检查。

### 决策

- D172：部队旗帜遮罩改用局部像素正圆；地点徽章同类问题记录为 KI546，本次不修改。

### 验证

- 窗口化像素探针（真实渲染 `PartyIcon`，透明背景，临时脚本已删除）：
  - 黑色描边包围盒：0.5x = 18×18、1x = 38×38、2x = 76×76，宽高比均为 1.000。
  - 1x 悬浮：黑色描边 38×38、白色悬浮描边 50×50，均为正圆且同心；白色描边外径约 25.8 世界像素。
  - 复现旧 UV 模式：不透明内容延伸到约 26 世界像素，黑色描边被旗帜覆盖，确认旧实现为椭圆溢出。
- 已运行并通过：`stage13_world_map_ui_test`、`encounter_dialogue_ui_test`、`main_map_info_test`、`world_map_layout_test`。
- 未修改建筑徽章，其同类图集 UV 遮罩问题记录为 KI546。

---

## 2026-11-27 · 部队旗帜放大与黑色描边向内加粗

### 变更

- `PartyMarkerStyle.flag_max_size` 52 → 60：部队圆形标记内部旗帜按裁切后有效贴图最长边等比放大，保持原始宽高比；不修改源美术文件。
- 旗帜圆形遮罩改裁到黑色描边内缘：新增 `get_flag_clip_radius()`（优先 `get_outline_outer_radius() - outline_width`，当前 16.25），`get_flag_clip_uv_radius()` 由其换算；旗帜填满圆内有效区域但不覆盖黑色描边。无描边时回退原边框内缘。
- 基础黑色描边 1.5 → 2.5，绘制圆心改为 `get_outline_outer_radius() - outline_width * 0.5`：外缘保持加粗前的 18.75（`marker_radius + BASELINE_OUTLINE_WIDTH * 0.5`），加粗只向圆内扩展；新增 `get_outline_outer_radius()` / `get_outline_inner_radius()` 作为统一几何入口。
- `marker_radius` 18、`border_width` 2、图标位置、点击半径 26、悬浮半径 30 与白色悬浮描边（3 像素，外侧 4 像素）均未改变；建筑与无关 UI 未修改。
- 无旗帜纹理的回退三角形改用 `get_flag_clip_radius()` 限制半宽。
- 测试：`stage13_world_map_ui_test` 新增外缘固定 / 向内加粗 / 旗帜裁剪不超过描边内缘 / 实际旗帜精灵等比与遮罩参数断言；`encounter_dialogue_ui_test` 的旗帜放大上限由 `marker_radius * 3.0` 放宽到 `* 3.5`（圆形底盘半径另有独立断言）。

### 决策

- D171：旗帜裁剪绑定黑色描边内缘，描边只向内加粗。

### 验证

- 已运行并通过：`stage13_world_map_ui_test`、`encounter_dialogue_ui_test`、`main_map_info_test`、`world_map_layout_test`。
- 未运行全项目测试，未做非 headless 视觉验收（旗帜放大观感与描边粗细仍需人工确认）。

---

## 2026-11-27 · 顶栏信息图标 2 倍、移速基准 30 与部队/建筑悬浮描边

### 变更

- 顶栏金币/移速/人数图标由 20×20 放大到 40×40，仍保持等比缩放与最近邻采样；文本字号不变，图标与数值间距 4→6，左侧区域加宽到 360，避免挤压时间与右侧入口。
- 大地图移速基准由 20 调整为 30：全体部队当前速度 ×1.5，NPC 原始速度统一 ×5/2（商队 200、巡逻 300、强盗 250、家族骑士 275），玩家单列为原始 450 / 有效 36；排序与统一倍率 0.08 不变。
- 部队圆形标记增加 1.5 像素黑色圆形基础描边；新增 `PartyIcon.set_hovered()` 切换 3 像素白色悬浮描边，位于基础描边外侧，两者同时保留。
- 建筑新增 `SettlementIcon.set_hovered()`：沿村庄/城镇/城堡原有几何边缘绘制 5 像素白色描边，不影响名称、家族徽章、布局与点击进入。
- 新增 `WorldMap._update_hover_outline()` 统一识别悬浮目标（部队优先，同一时刻只高亮一个），并用 `_settlement_icons` 注册地点图标；鼠标离开、模态 UI 或战斗切换时立即清除。
- `WorldMapDefinition.calibration_travel_hours` 由 8.6 改为 5.8；最近地点对行程约 5.8 游戏小时（现实约 11.5 秒）。旧存档仍按存档中的原始 `movement_speed` 读取。

### 验证

- 已运行并通过：`main_map_info_test`（三个图标 40×40、等比/最近邻、顶栏 1280/1920 不重叠、顶栏移速 36.0）、`stage13_world_map_ui_test`（黑色基础描边细于白色悬浮描边、部队/村庄/城堡悬浮与清除、单一目标、部队优先、缩放命中与点击判定不变）、`ai_manager_test`、`world_map_layout_test`（行程 5.76 游戏小时）、`world_map_move_target_test`、`world_map_input_test`（玩家原始 450）、`player_pursuit_encounter_test`、`milestone1_test`、`family_appearance_test`。

---

## 2026-11-27 · 全体部队移速基准由 12 调整为 20

### 变更

- 大地图移速基准由玩家等效 12 调整为 20。NPC 部队原有 `movement_speed` 统一乘以 5/3：商队 80→约 133.3、巡逻 120→200、强盗 100→约 166.7、家族骑士 110→约 183.3；商队 < 强盗 < 家族骑士 < 巡逻队的相对差异与排序不变。
- 玩家按需求单列：`PLAYER_MOVE_SPEED` 150→300，有效移速 12→24，不参与 5/3 换算。
- `WorldMapManager.WORLD_MAP_SPEED_SCALE` 保持 0.08；`PartyData.movement_speed` 仍保存原始速度，有效移速 = 原始速度 × 0.08。战斗/小场景 `UnitData.move_speed`、`StatCalculator`、时间流速、AI 与寻路算法均未修改。
- `WorldMapDefinition.calibration_travel_hours` 由 17.3 改为 8.6；最近地点对行程约 8.6 游戏小时（现实约 17.3 秒）。
- 旧存档按存档中的原始 `movement_speed` 读取，不按新常量重置。

### 验证

- 已运行并通过：`ai_manager_test`（速度常量与 AI 追击/巡逻/战斗行为）、`world_map_layout_test`（最近地点对行程约 8.65 游戏小时、统一倍率 0.08）、`world_map_move_target_test`、`world_map_input_test`（玩家 300 / NPC 换算后的原始速度）、`main_map_info_test`（顶栏显示 24.0 与 ALT 明细）、`player_pursuit_encounter_test`（追击接触）、`milestone1_test`（100 像素移动到达）、`family_appearance_test`（有效移速 = 原始 × 0.08）、`stage13_world_map_ui_test`（商队有效移速 10.7）、`world_map_milestone6_test`。

---

## 2026-11-27 · 大世界时间流速调整为 2 现实秒 = 1 游戏小时

### 变更

- `TimeManager.REAL_SECONDS_PER_GAME_HOUR` 由 6.0 改为 2.0；`GAME_MINUTES_PER_ELAPSED_SECOND` 由 10.0 改为 30.0。1x 下现实 2 秒 = 1 游戏小时、48 秒 = 1 游戏日；2x 仍按现有倍率翻倍，暂停仍为 0。
- 只改统一换算常量；`world_elapsed_seconds` 的 0.1 秒固定步长、暂停原因栈、倍率定义、日期/时间段显示、部队移动速度、经济系统均未修改。
- 直接依赖“1 游戏小时 = N 世界秒”的重复常量同步为 2：`CaptivityManager.SECONDS_PER_GAME_HOUR`、`WoundedHealingManager.SECONDS_PER_GAME_HOUR`、`OffscreenBattleConfig.settlement_interval_world_seconds`（默认值与 `Data/Combat/offscreen_battle_default.tres`）。
- 移动速度未改，最近地点对的现实行程不变（约 34.6 秒），游戏内行程由约 6 游戏小时变为约 17.3 游戏小时；`WorldMapDefinition.calibration_travel_hours` 同步为 17.3。
- 测试中的 6 秒/144 秒假定同步更新：`time_calendar_test`、`supply_manager_test`、`wounded_healing_test`、`offscreen_battle_hourly_test`、`world_map_layout_test`、`captivity_escape_test`。
- 跨读档仍只保存 `world_elapsed_seconds` 与倍率，日期/昼夜位置由新比例重新换算，不新增持久化字段。

### 验证

- 已运行并通过：`time_calendar_test`（含现实 1x/暂停/2x 累积实测）、`main_map_info_test`（昼夜 UI 与新比例同步、暂停/2 倍速/读档）、`world_map_layout_test`、`wounded_healing_test`、`offscreen_battle_hourly_test`、`captivity_escape_test`、`world_map_milestone6_test`、`stage13_world_map_ui_test`、`lord_ransom_test`、`mercenary_system_test`、`wounded_system_test`。
- `supply_manager_test` 仅保留既有 KI534 失败（“NPC 记录 1 份草料缺口”）；本次时间换算相关断言（跨日、跨 3 天补算）全部通过。

---

## 2026-11-27 · 顶栏昼夜滚动窗口

### 变更

- 新增 `Scripts/UI/WorldMap/day_night_clock.gd`：正方形 `Control` 遮罩（36×36，`clip_contents`），复用 `UI_昼夜.png`（96×48），以 96 像素为周期重复绘制；48→36 等比缩放、最近邻采样。
- `world_map.gd::_build_top_bar()` 在顶栏精确水平中心创建 `DayNightClock`；`WorldTimeLabel` 改为右对齐并紧贴窗口左侧，左右区域原有元素与功能不变。
- 映射唯一由 `TimeManager.world_elapsed_seconds` 换算：相位 = `fposmod(秒 / 144 - 0.5, 1)`；12:00 偏移 0、18:00 偏移 24、次日 00:00 偏移 48、06:00 偏移 72、次日 12:00 折回 0。`_update_time_ui()` 在世界时间/倍率变化与读档恢复后刷新。
- 不新增时间系统、不修改时间流速、不使用现实时间计时器；暂停时世界时间不变，窗口自然停住。
- `Docs/Systems/World_Map_System.md` 新增 4.5 节并更新 18.1 顶栏布局。

### 验证

- 已运行并通过：`main_map_info_test`（昼夜窗口正方形/居中/裁切/最近邻、12:00/18:00/00:00/06:00/次日 12:00、跨午夜连续、暂停停住、2 倍速同步、读档立即更新，以及原有顶栏与建筑面板权限用例）。

---

## 2026-11-27 · 大地图陆地/海洋/湖泊地表配色

### 变更

- `MapBackground` 新地图绘制改为三区地表：整块世界先铺海洋蓝（`#5a8fae`），再用 `WorldMapDefinition` 边界多边形覆盖草地绿（`#a8c483`），最后绘制比海洋更深的湖泊蓝（`#3c7396`）；海岸线深绿（`#2f7a4a`）、湖岸线深蓝（`#2a5675`）。
- 陆地网格纹理改为按边界多边形裁切后绘制（`Geometry2D.intersect_polyline_with_polygon`），只在陆地内部出现；海洋保持简洁。网格线段按定义/世界尺寸缓存。
- 道路颜色由浅灰调深（`#7a7469`），山脉填充/描边略微加深，保证在绿色陆地上仍清晰可辨。
- 旧存档尺寸不匹配时继续绘制原矩形草地、河流与道路，不改变旧地图观感。
- 只改绘制层：地图边界、湖泊多边形、地点坐标、道路连接、地形不可通行判定、移动与相机逻辑均未修改。

### 验证

- 已运行并通过：`world_map_layout_test`（尺寸/边界/湖泊/山脉不可通行、道路与时间标定）、`stage13_world_map_ui_test`（大地图场景加载、图标/旗帜/移速 UI）。
- 非 headless 临时探针截图核对：陆地、海洋、湖泊颜色像素分别为 `#a8c483`、`#5a8fae`、`#3c7396`；海岸线清晰、海洋无网格渗透；探针运行后已删除。

---

## 2026-11-27 · 大地图重建、六方势力与旗帜命名

### 变更

- 新增 `Data/WorldMap/world_map_definition.tres` 与 `Scripts/Config/world_map_definition.gd`：以参考图 1556×1323 为唯一依据，`reference_scale = 5` 推导 7780×6615 世界；保存 63 个地点（38 村庄/8 城镇/17 城堡）、46 条显式道路、46 点不规则边界、11 点湖泊、5 座旋转椭圆山脉、时间标定参数。
- 新增 `Scripts/Systems/WorldMap/world_terrain.gd`：40 像素 `AStarGrid2D`；边界外、湖泊、山脉不可通行（含 6 像素边距）；目标收敛、折线路径、直线通路检测、缓存与路径平滑。玩家与 NPC 共用。
- `WorldMapManager`：绑定地形后沿 A* 折线移动，终点变化超过 32 像素重算；无路时原地停止；`WORLD_MAP_SPEED_SCALE` 由 0.5 改为 0.08；旧存档/测试世界保持直线移动。
- `WorldContext`：`DEFAULT_WORLD_SIZE = 7780×6615`；按世界尺寸装配 `WorldTerrain`，尺寸与定义不一致时回退矩形边界；存档继续保存 `world_size`。
- `MapBackground`：新地图绘制浅色底、网格、绿色不规则边界与浅绿填充、灰色虚线道路、蓝色描边湖泊、灰色椭圆山脉；道路经 A* 绕行；旧尺寸继续走旧矩形草地/河流/道路绘制。
- `WorldInitializer`：地点与家族驻地按定义参考坐标生成；六方势力统治者/附庸/民族显式声明；每个 NPC 家族一名贵族、一支 `<简称>骑士` 部队；保留旧世界 9 处地点所有权，其余无主；征召/巡逻点/商队路线改用新坐标与最近可通行点。
- `KingdomData` 新增可选 `people_name`，仅读档缺失时为空，向后兼容。
- 旗帜资源统一为 `<家族>旗帜16_16.png`；新增 16 个家族的旗帜/罩袍/盾牌/缨饰/长矛正式美术目录；删除伯克纳旧 `Sprite-0002.png` 并改为 `伯克纳旗帜16_16.png`；修复伯克纳与克里卡旗帜引用；瓦伊拉暂无专属旗帜。

### 验证

- 重写 `world_map_layout_test`：世界尺寸、63 地点唯一/间距≥250/边界内且避开地形、46 道路端点有效、边界/湖泊/山脉不可通行、山脉绕行、无障碍直线、最近地点对约 6 小时、六方势力/18 家族/18 贵族/23 部队/9 处所有权、旗帜资源与命名。
- 已运行并通过：`world_map_layout_test`、`milestone1_test`、`milestone1_flow_test`、`political_hierarchy_test`、`faction_bandit_hostility_test`、`encyclopedia_ui_test`、`king_helmet_appearance_test`、`family_appearance_test`、`settlement_interaction_test`、`world_map_milestone6_test`、`main_map_info_test`、`world_map_move_target_test`、`battle_reinforcement_test`、`battle_side_result_test`、`encounter_dialogue_ui_test`、`ai_manager_test`、`ai_supply_purchase_test`、`player_pursuit_encounter_test`、`wounded_system_test`、`lord_ransom_test`、`mercenary_system_test`。

### 未决

- 道路移动加成、地图/地点实际观感的人工验收、瓦伊拉专属旗帜、塞洛斯要塞与巴达洛斯要塞旗帜。

---

## 2026-11-26 · 角色整体动态排序修正（替代 CanvasGroup 方案）

### 根因

- 画布 `z_index` 是全局排序键：同一角色内部部件使用不同负 z（右手武器 -10、身体 -50、左腿 -80），不同角色的部件会按绝对 z 交错，后排角色的武器可以压过前排角色的身体。
- YSort 只在相同 z 的节点之间按 Y 排序，无法覆盖不同相对 z 的部件；`CanvasGroup` 的子节点仍按各自 z 进入全局 z 分层，实测不能把整个角色合成一个排序单位（窗口像素探针：旧方案仍为后排武器盖住前排身体）。

### 变更

- `UnitActor`：移除 `VisualRoot` CanvasGroup，`UnitVisual` 恢复为角色根节点的直接子节点；新增 `apply_sort_rank()`、`get_sort_rank()`、`get_part_canvas_z()` 与 `SORT_Z_STRIDE = 72` / `SORT_Z_MAX_RANK = 54`。角色根节点按名次获得 `rank × 72` 的 z 波段，内部 `VisualLayers` 相对 z 完全不变。
- `BattleScene`：新增 `_update_character_sorting()`，每物理帧收集 `World/Characters` 下全部 `UnitActor`（含尸体），按权威 `BattleUnitState.battle_position.y` 升序排名；相同 Y 使用稳定节点名打破平局；初始生成与增援加入后立即重排。尸体位置冻结，但仍持续参与排序。
- 波段间隔 72 大于内部非影子层级跨度 70，保证“前排最低部件 > 后排最高部件”；不修改任何单件武器/装备的层级，也不新增逐 Sprite 排序逻辑。
- 正常移动、攻击、受击、倒地、尸体留存与淡出期间只有角色根节点 z 整体变化；淡出透明度仍只作用于完整角色子树，影子继续使用 `World/Shadows` 独立层。
- 测试：更新 `battle_corpse_visual_test`（前后/骑乘/尸体全部非影子部件两两层级断言、交叉移动翻转、波段间隔大于内部跨度、内部层级不变），并新增窗口像素探针 `Tests/_debug/sort_probe.tscn`：用真实骑乘/步兵模型比较“仅前排”和“前后同时可见”的画面，波段方案 0 处穿插，旧方案可复现 93 处穿插。

### 验证

- 已运行并通过：`battle_corpse_visual_test`（93 条断言）。
- 窗口像素探针 `sort_probe`：PASS（banded violations = 0，legacy violations = 93）。
- 已运行并通过：`battle_scene_test`、`player_control_test`、`milestone2_flow_test`、`melee_attack_timing_test`、`archer_scene_test`、`archer_battle_test`、`battle_reinforcement_test`、`battle_cluster_test`、`battle_formation_test`、`battle_result_delay_test`、`battle_retreat_test`。
- 既有失败（与本次无关）：`unit_visual_test` 的 4 条马前腿2/后腿2 idle 枢轴精确位置断言。

---

## 2026-11-26 · 死亡倒地尸体表现与完整角色动态层级

### 变更

- `UnitActor`：新增独立表现状态机 `CorpseState`（`NONE / FALLING / LINGERING / FADING`）。`play_death()` 不再立即 `queue_free`，而是播放倒地 → 留存 → 淡出后再清理；尸体期间 `_process` 只推进尸体计时，不接收移动/攻击/AI 状态；角色位置在死亡瞬间冻结，名称、生命条、选中圈隐藏，死亡叉号不再叠画在尸体上。
- `HumanVisual`：新增 `play_death_fall()` / `advance_death_animation()`，锁定死亡姿态并在 `UpperBody` 上平滑旋转/下沉；倒地期间取消攻击、受击动作与白闪，待机/跑动/受击动画不再覆盖。
- `HorseVisual`：新增 `play_death_collapse()` / `advance_death_animation()`，马身 rig 随骑手一同旋转、下沉并轻微压扁。
- `UnitVisual`：新增 `play_death_fall()`、`advance_death_animation()`、`capture_corpse_shadow_alpha()`、`set_corpse_alpha()`；淡出通过 `modulate.a` 覆盖完整视觉子树（人物、装备、武器、盾牌、马匹），独立影子按记录的基础透明度同步乘算，不使用共享材质。
- 新增 `CorpseConfig` Resource（`Data/Combat/corpse_config.tres`），集中提供倒地/留存/淡出时长；战斗场景加载一次并注入所有 `UnitActor`，避免多处硬编码。
- 完整角色动态排序：~~每个 `UnitActor` 新增 `VisualRoot`（`CanvasGroup`，z_index = 0）包裹整个 `UnitVisual` 子树，使人物、武器、装备与马匹作为一个原子绘制项按角色脚底 Y 参与 `World/Characters` 的动态排序~~。**（已过时：CanvasGroup 不会隔离子级 z，像素探针仍可复现后排武器压过前排身体；见上一条「角色整体动态排序修正」。）**
- `BattleScene`：加载尸体配置并传入 `UnitActor.setup()`；死亡处理仍只调用 `play_death()` 并从 `_actors` 移除，`get_actor_count()` 不含尸体，结算逻辑不变。
- 测试：新增 `battle_corpse_visual_test`（倒地持续且区别于受击、留存/淡出时长由配置驱动、淡出覆盖人物/武器/马匹/影子、清理无残留、尸体参与排序且位置稳定、尸体不参与战斗、结算不受影响、骑乘尸体、内部层级保持、朝向镜像、受击对照）。

### 验证

- 已运行并通过：`battle_corpse_visual_test`（88 条断言）、`battle_scene_test`、`player_control_test`、`milestone2_flow_test`、`melee_attack_timing_test`、`archer_scene_test`、`archer_battle_test`、`battle_reinforcement_test`、`battle_cluster_test`、`battle_formation_test`、`battle_result_delay_test`、`battle_retreat_test`。
- 既有失败（与本次无关）：`unit_visual_test` 的 4 条马前腿2/后腿2 idle 枢轴精确位置断言。
- 未验证：无头环境无法确认倒地重量感与淡出视觉效果；角色整体排序已由窗口像素探针验证，但正式战斗观感仍需人工验收。退出时 `resources still in use` 与既有战斗场景测试一致，仍为已知既有告警。

---

## 2026-11-26 · 近战攻击有效帧与受击反馈

### 变更

- `HumanVisual`：戳击阶段进度达到 `SPEAR_HIT_FRAME_RATIO = 0.6` 时发出一次 `attack_hit_frame`；新增受击动作（`UpperBody` 后仰/倾斜，按朝向镜像换算）、`cancel_attack_animation()` 与 `get_melee_hit_frame_time()`。
- `UnitVisual` / `UnitActor`：转发有效帧事件；`UnitActor` 新增 `play_hit_feedback()`、白闪强度衰减与 `attack_hit_callback`；`play_attack()` 返回是否成功启动动画。
- `UnitController`：近战攻击改为“出手时锁存目标/方向/伤害并进入冷却 → 有效帧回调中经 `CombatRules.is_attack_frame_valid()` 重新校验 → `apply_damage()` 结算”。每次攻击最多结算一次；有效帧前受击/死亡取消待结算攻击，有效帧后伤害不撤销；`PENDING_ATTACK_TIMEOUT = 0.6s` 兜底。
- 新增受击僵直 `STAGGER_DURATION = 0.24s` 与 `AIState.STAGGERED`：停止移动、不能启动新攻击，连续受击刷新不叠加，死亡优先；不修改基础属性。
- `apply_damage(amount, source, hit_direction)` 新增受击方向参数；只在真实扣血后触发白闪/受击动作/僵直。
- `Shaders/faction_tabard.gdshader` 扩展为统一士兵材质（`use_faction_color`、`flash_amount`）；每个 `UnitVisual` 使用独立材质实例，罩袍保留阵营材质并同步白闪，影子不参与。
- `EventBus` 新增 `unit_attack_started`、`unit_hit`、`unit_staggered`。
- 测试：新增 `melee_attack_timing_test`（前摇/戳击前半无伤害、有效帧一次结算、未命中无反馈、有效帧前后打断、僵直、连续受击、死亡优先、骑马白闪与材质隔离、受击方向、事件契约）；`battle_scene_test` / `milestone2_flow_test` / `player_control_test` 改为手动推进到有效帧；`combat_attack_rules_test` 适配受击僵直。

### 验证

- 已运行并通过：`melee_attack_timing_test`、`battle_scene_test`、`milestone2_flow_test`、`player_control_test`、`combat_attack_rules_test`、`unit_controller_test`、`archer_battle_test`、`archer_scene_test`、`battle_reinforcement_test`、`battle_formation_test`、`battle_cluster_test`、`battle_retreat_test`。
- 既有失败（与本次无关）：`unit_visual_test` 的 4 条马前腿2/后腿2 idle 枢轴精确位置断言；`battle_side_result_test` 的「玩家部队全员伤亡」与 `wounded_system_test` 的「玩家角色保持永久死亡规则」仍按玩家被俘规则接入前的语义校验。

---

## 2026-11-26 · 身份选择取消「完成选择」按钮

### 变更

- 删除二级身份页的 `CompleteSelectionButton` 及其点击处理；二级页只保留「返回」。
- 点击任意具体身份按钮立即进入最终确认页，不再经过任何中间确认按钮；流程改为：类别 → 具体身份 → 最终确认 → 开始游戏。
- 确认页「返回修改」改为回到一级类别页；类别与身份选择保留，再次点击具体身份直接重新进入确认页。
- 测试与探针同步：`identity_selection_ui_test` 新增「无完成选择/确认选择/下一步按钮」断言并改为即时确认流程；`identity_select_probe` 点击身份后直接截取确认页。

### 验证

- 已运行并通过：`identity_selection_ui_test`、`main_menu_ui_test`、`milestone1_flow_test`。
- 已运行非 headless `identity_select_probe`，检查 1920×1080 的类别/身份/确认页与 1280×720 的二级页截图：二级页无「完成选择」或「下一步」，只有身份按钮与「返回」。

---

## 2026-11-26 · 身份选择全屏化与最终确认

### 新增

- `Scenes/Identity/identity_select.tscn` + `Scripts/UI/Identity/identity_select.gd`：独立全屏身份选择场景，包含渐变/暖光背景、独立按钮样式、一级纵向类别、二级纵向身份与可滚动选项区。
- 最终确认页：按真实选择状态生成「类别 → 身份」完整路径，提供「返回修改」与「最终确认」两个纵向按钮。
- `SceneManager.IDENTITY_SELECT_SCENE`。
- 测试：重写 `identity_selection_ui_test` 覆盖全屏场景、纵向布局、确认路径与最终提交流程。

### 变更

- 主菜单「新游戏」不再在主菜单内弹出覆盖面板，而是切换场景；主菜单场景被释放，身份选择完全全屏独立。
- 删除 `Scripts/UI/MainMenu/identity_select_panel.gd`；`main_menu.gd` 只负责切换场景。
- ~~二级页「确认身份」拆分为「完成选择」与最终确认页的「最终确认」；「完成选择」只进入确认页，不创建世界或存档。~~（已被同日「身份选择取消完成选择按钮」取代：点击身份直接进入确认页。）
- 返回上下文：最终确认返回二级页并保留身份；二级返回一级时保留类别高亮，再次进入同一类别恢复身份；切换类别才清除具体身份。
- 确认路径改为由选择状态动态生成，为未来多层选择预留追加点。
- 身份 ID / 类别 ID 的会话级传递与「不改变初始化数据」保持不变，Schema 仍为 v10。

### 验证

- 已运行并通过：`identity_selection_ui_test`、`main_menu_ui_test`、`milestone1_flow_test`。
- 已运行非 headless `identity_select_probe`，检查 1920×1080 与 1280×720 下的一级/二级/确认页截图：全屏无主菜单残留、选项纵向、底部按钮未被裁切。

---

## 2026-11-26 · 新游戏身份选择

### 新增

- `IdentityDefinition`、`IdentityCategoryDefinition`（`Scripts/Config/`）与 `Data/Identity/Categories/*.tres`、`Data/Identity/Identities/*.tres`：类别/身份 ID、名称、背景故事、排序、启用开关。
- `IdentityCatalog`（`Scripts/Config/identity_catalog.gd`）：只读扫描默认目录注册配置，校验重复 ID、缺失类别与非法字段。
- `IdentitySelectPanel`（`Scripts/UI/MainMenu/identity_select_panel.gd`）：一级类别 + 二级身份的覆盖式选择面板，配置驱动生成按钮。
- `GameManager.player_identity_id` / `player_identity_category_id`：会话级身份选择结果；`start_new_game()` 新增两个可选参数。
- 测试：`identity_selection_ui_test`。

### 变更

- 主菜单「新游戏」不再直接调用 `GameManager.start_new_game()`，先进入身份选择；确认后才创建世界并进入大地图。
- 一级/二级返回、类别切换均清空具体身份选择；确认前不创建 `WorldContext`、不写存档。
- 身份选择不改变金币、装备、士兵、出生点或任何初始化数据，也不新增存档字段；`schema_version` 保持 v10。

### 验证

- 已运行并通过：`identity_selection_ui_test`、`main_menu_ui_test`。
- 未执行非 headless 视觉验收；故事区排版与长文本换行需人工确认。

---

## 2026-11-25 · 雇佣兵美术、独立招募、战败清理与玩家被俘

### 新增

- `CaptivityConfig`（`Scripts/Config/captivity_config.gd` + `Data/Combat/captivity_config.tres`）：俘虏每小时恢复点数、逃脱判定间隔/概率、逃脱保护时长。
- `CaptivityManager`（`Scripts/Core/World/captivity_manager.gd`）：玩家被俘状态、押送部队、俘虏按小时恢复、满血逃脱判定、逃脱落点、保护期、存档往返。
- `MercenaryRecruitPanel`（`Scripts/UI/WorldMap/mercenary_recruit_panel.gd`）：独立招募窗口，左侧列表 + 右侧复用 `UnitVisual` 的真实预览；预览单位 `create_detached_unit` 不进入仓储/部队。
- 大地图 `CaptiveStatusPanel`、`CaptiveTitleLabel`、`CaptiveCaptorLabel`、`CaptiveHpLabel`、`PlayerHpLabel`。
- `MercenaryData.appearance`：按 `mercenary_id` 稳定生成并持久化的外观快照。
- `AppearanceConfig` 雇佣兵字段：`mercenary_tier2_tabard_texture_path`、`mercenary_tier3_tabard_texture_path`、`mercenary_plume_config_ids`、`mercenary_plume_texture_path`。
- 测试：`captivity_escape_test`；扩展 `mercenary_system_test`、`stage13_tavern_test`。

### 变更

- 雇佣兵按 Tier 使用 `2级雇佣兵罩袍.png` / `3级雇佣兵罩袍.png`；固定 `tabard_variant = MERCENARY`、空 `family_id`、无家族长矛；仅 `mercenary_rogue_knight` 获得 `无赖骑士缨饰.png`。
- 酒馆“招募雇佣兵”不再嵌入地点面板，改为隐藏地点面板后打开独立界面；关闭后恢复城镇信息面板。价格、经验、坐骑与工资规则不变。
- 战斗结算完成后，`WorldContext` 移除无任何成员的非玩家部队，并清理目标/跟随/攻击意图引用；只剩伤兵的部队保留；玩家部队不删除。
- 玩家侧战败时，玩家角色不再按永久死亡处理，而是成为胜利方真实俘虏；原部队禁用但保留，镜头跟随押送部队，部队面板只读。
- 所有俘虏（含玩家）按世界时间独立恢复 HP，不占用伤兵治疗名额；玩家满血后按配置进行逃脱判定，成功后重建只含玩家角色的部队，并获得 2 游戏小时 AI 主动攻击豁免。
- 顶栏显示真实玩家角色 `current_hp/max_hp`；被俘/恢复/逃脱后实时刷新。
- `AIManager` 与 `EncounterManager` 接入 `CaptivityManager`，保护期内跳过 AI 主动攻击；玩家主动追击仍允许。
- `SaveData` 升至 v10，新增 `captivity`；`MercenaryData` 新增 `appearance`。

### 验证

- 已运行并通过：`captivity_escape_test`、`mercenary_system_test`、`stage13_tavern_test`、`milestone2_flow_test`、`battle_scene_test`、`player_control_test`、`save_persistence_test`、`save_migration_test`、`lord_ransom_test`、`political_hierarchy_test`。
- 未执行非 headless 视觉验收；雇佣兵预览排版、被俘面板与顶栏 HP 的实际观感需人工确认。

---

## 2026-11-25 · 地图操作、雇佣兵、装备管理与招募经济

### 新增

- `RecruitmentConfig`（`Scripts/Config/recruitment_config.gd` + `Data/Recruitment/recruitment_config.tres`）：普通招募价格、雇佣兵基础价/经验加价/坐骑加价、雇佣兵日薪来源、池增长/容量/流转/旅行、类型权重、NPC 招募参数。
- `MercenaryData`（`Scripts/Entities/Mercenary/mercenary_data.gd`）：全局雇佣兵记录与 `WAITING` / `STATIONED` / `TRAVELING` 状态。
- `MercenaryManager`（`Scripts/Core/World/mercenary_manager.gd`）：全局池初始化、每 12 世界小时增长、每酒馆 7 人容量、24 小时流转、2 小时旅行、酒馆分配、玩家与 NPC 原子招募、存档往返。
- `Data/Units/mercenary_archer.tres`、`mercenary_sergeant.tres`、`mercenary_mounted_sergeant.tres`、`mercenary_rogue_knight.tres`：Tier2/3 四类雇佣兵；无赖骑士无坐骑。
- `UnitData.is_mercenary` 与 `UnitData.can_manage_equipment()`；旧档按 `recruit_source == "tavern_mercenary"` 回填。
- `EventBus.party_arrived(party_id)`、`EventBus.mercenary_recruited(...)`。
- 大地图 `WorldPausedTip`：有效倍率为 0 时显示琥珀色“已暂停”。
- 酒馆“招募雇佣兵”列表与原子招募按钮；部队详情“装备管理”区、雇佣兵锁定提示。
- 测试：`mercenary_system_test`；扩展 `world_map_input_test`、`party_panel_test`、`stage13_tavern_test`。

### 变更

- 大地图左键改为单击/双击判定（0.28 秒、18 像素）：单击 1x、双击 2x，双击只下达一次移动/跟随；UI 控件点击不进入地图输入。
- 玩家部队真正到达移动/跟随目标时自动暂停；NPC 到达、移动途中、重新下达指令后的旧目标均不触发。
- 部队详情对普通士兵开放逐槽位换装/卸下；雇佣兵隐藏装备与坐骑管理，`UnitManager` 全部装备写入口拒绝雇佣兵。
- 普通招募统一价格：Tier1 = 5、Tier3 = 400；贵族冒险者初始战斗经验固定为 2 级。
- 工资调整为 Tier1/2/3 = 1/3/7；雇佣兵 Tier2 日薪 4、无赖骑士 9；经验与坐骑不改工资。
- 新游戏玩家金币 500 → 10000；旧存档不变、不补发。
- `WorldContext` 装配 `RecruitmentConfig` 与 `MercenaryManager`；`WorldSimulation` 每 tick 推进雇佣兵池；`SaveData` 升至 v9，新增 `mercenaries` 与 `UnitData.is_mercenary`。

### 验证

- 已运行并通过：`mercenary_system_test`、`world_map_input_test`、`party_panel_test`、`stage13_tavern_test`、`save_persistence_test`、`save_migration_test`、`unit_tier_wage_test`、`party_economy_ui_test`、`lord_ransom_test`、`political_hierarchy_test`、`fief_adventurer_system_test`、`fief_adventurer_ui_test`、`noble_adventurer_recruitment_test`、`main_map_info_test`、`unit_manager_test`、`unit_party_serialization_test`、`mount_instance_test`、`mounted_unit_test`、`ai_manager_test`、`player_party_expansion_test`、`world_map_move_target_test`、`world_map_layout_test`、`town_market_ui_test`、`event_center_test`、`stage13_prisoner_test`、`milestone1_restart_test`、`stage13_world_map_ui_test`、`world_map_milestone6_test`、`settlement_interaction_test`、`main_menu_ui_test`。
- 修复既有测试偏差：`player_control_test` 改为校验“阵亡 + 伤兵 = 全员且无存活者”；`milestone2_flow_test` 补上攻击确认与战后俘虏选择（不接收）流程。两项均已运行通过。
- 同时修复 `WorldMap._update_time_ui()` 在场景退出后收到速度信号时访问 viewport 的报错。
- 未执行非 headless 视觉验收；暂停提示、酒馆列表与装备管理区排版需人工确认。

---

## 2026-11-24 · 国王盔缨饰、酒馆独立出售与关押期赎买

### 新增

- `LordRansomConfig.captive_wait_hours_min` / `captive_wait_hours_max`（默认 3 / 12）：领主仍被玩家关押时的家族赎买等待。
- `LordRansomManager` 的 `CAPTIVE` 记录来源：扫描玩家俘虏列表登记 3–12 世界小时等待，生成 `家族赎买请求` 事件。
- `LordRansomManager.reject_captive_ransom()`：拒绝当前关押期请求，事件结束、领主继续被关押；同一关押周期不再请求。
- `EventReminder`（`Scripts/UI/WorldMap/event_reminder.gd`）：大地图右侧小型待处理提醒，只读取事件中心可操作事件数量。
- `TavernPanel.open_sale()` / `sell_requested`：嵌入酒馆点击出售时请求打开独立出售窗口。
- 测试：`lord_ransom_test` 扩展关押期接受/拒绝/出售失效/详情二次校验/存档往返/提醒；`stage13_tavern_test` 更新独立出售流程。

### 变更

- 国王盔生效时 `UnitVisual` 不创建 `Plume` 部件；身份失效后重建即恢复原缨饰，不修改外观/装备/存档数据。
- 出售俘虏改为独立 `PrisonerSalePanel`（同一 `TavernPanel` 类的独立窗口），不再嵌套在城镇左侧面板；关闭后恢复城镇信息，暂停原因不变。
- `EventDetailDialog` 根据事件 `decline_label` / `decline_ends_event` 显示“取消”或“拒绝”；关押期拒绝会结束事件。
- `EventFeed` 使用事件 `tag` 区分 `[赎回]` 与 `[赎买]`。
- 赎买/赎回事件来源互斥：出售先移除关押期记录，关押期校验要求领主仍在玩家俘虏列表；出售/释放/转移后旧事件立即消失。
- 存档 `ransoms` 新增 `source`、`captured_world_seconds`、`declined_world_seconds` 兼容字段，仍为 Schema v8；旧档缺失 `source` 按 `SOLD`。

### 验证

- 已运行并通过：`king_helmet_appearance_test`、`lord_ransom_test`、`stage13_tavern_test`、`main_map_info_test`。
- 未执行非 headless 视觉验收；独立出售窗口与右侧提醒的实际排版需人工确认。

---

## 2026-11-24 · 国王身份头盔与顶栏图标化

### 新增

- `AppearanceConfig.king_helmet_texture_path`：国王盔外观覆盖资源路径（`头盔_特殊_国王盔.png`）。
- `UnitAppearance.configure_king_helmet_override()` / `clear_king_helmet_override()` / `get_king_helmet_texture_path()`：表现层只读身份覆盖注册与查询。
- `WorldContext.is_king_unit()` / `is_king_noble()`：复用 `NobleData.is_king`、`HouseData.leader_noble_id`、`KingdomData.ruling_house_id` / `king_noble_id` / `is_active` 判断国王身份。
- 测试：`king_helmet_appearance_test`。

### 变更

- `UnitVisual` 头盔表现新增身份覆盖：仅在原本会显示头盔时替换为国王盔；不写入 `appearance`、装备、背包或存档，身份失效后重建即恢复。
- 大地图顶栏金币、移速改为“图标 + 数值”，新增部队人数条目；三者统一 20×20 图标、字号 15、间距与对齐。
- 顶栏悬浮事件改挂条目容器，图标与数值共同触发；新增部队人数悬浮明细（可战斗人数 / 伤员 / 俘虏）。
- 部队人数统计只读玩家部队成员与 `prisoner_unit_ids`，不新增缓存；`main_map_info_test` 同步更新。

### 验证

- 已运行并通过：`king_helmet_appearance_test`、`main_map_info_test`、`family_appearance_test`。
- 未执行非 headless 视觉验收；图标排版与国王盔观感目前由节点/贴图路径断言覆盖。

---

## 2026-11-24 · 贵族冒险者、NPC 冒险者招募与家族面板

### 新增

- `SettlementData.noble_adventurer_candidate` / `noble_adventurer_spawned`：每村 1 名贵族冒险者，独立于普通候选人上限。
- `AdventurerCandidateData.is_noble` / `mount_instance` / `unit_data`：贵族类型、自备战马实例与独立单位快照。
- `AdventurerRecruitmentManager.ensure_noble_candidate()`、`is_noble_recruit_authorized()`、`recruit_normal_candidates_for_party()` 与共享 `_recruit_candidate_into_party()`。
- `UnitManager.equip_detached_mount()`：为未注册候选人单位装备真实马匹实例。
- `EventBus.adventurers_recruited`：玩家/NPC 招募成功事实，携带按兵种数量。
- `Scripts/UI/WorldMap/family_panel.gd`（`FamilyPanel`）：家族入口、部队页、封地页、封地点击定位。
- `SettlementEconomyConfig.noble_adventurer_unit_config_id`（默认 `infantry_veteran`）。
- 测试：`noble_adventurer_recruitment_test`、`family_panel_ui_test`。

### 变更

- 贵族冒险者由 `FiefRecruitmentManager.is_authorized_owner()` 判断招募权限；所有权变更立即生效，非拥有者只能查看。
- 村庄场景将贵族人物按步行呈现，并单独生成 `HorseVisual`；不修改权威 `UnitData` 的骑乘关系，普通候选人接口与数量不变。
- `AIManager` 在采邑储备为 0 时转入 `ADVENTURER_RECRUIT`，通过统一管理器招募普通候选人；贵族不参与 NPC 招募。
- 大地图复用 `PartyIcon.show_floating_text()` 显示冒险者招募结果。
- 顶栏新增 `FamilyButton`，家族面板沿用 `PAUSE_REASON_UI_PANEL` 与现有暂停计数；部队/封地数据每次刷新从权威管理器实时读取。
- 存档新增兼容字段，不改变顶层结构，仍为 Schema v8；旧档不会重复生成贵族或战马。

### 验证

- 已运行并通过：`noble_adventurer_recruitment_test`、`family_panel_ui_test`、`fief_adventurer_system_test`、`fief_adventurer_ui_test`、`stage13_village_candidates_test`。
- 未执行非 headless 视觉验收；贵族人物/战马布局目前由位置与节点断言覆盖。

## 2026-11-24 · 五级战斗经验、俘虏价格与 NPC 领主赎回

### 新增

- `CombatExperience` 五级制：新兵 / 普通士兵 / 老兵 / 精锐 / 百战精锐，升级阈值 100/300/500/1000，累计最大 HP 加成 +0/+5/+15/+30/+50。
- 战斗经验来源：近战与远程有效伤害 +1，击杀额外 +10；未命中、0 伤害、目标已死亡不发放。
- `Scripts/Core/World/lord_ransom_manager.gd`（`LordRansomManager`）：出售登记、世界时间等待、赎回请求、接受/取消、失效恢复、存档。
- `Scripts/Config/lord_ransom_config.gd` 与 `Data/Lords/lord_ransom_config.tres`：等待 12–48 游戏小时、赎金 150–400 金币。
- `Scripts/UI/WorldMap/event_feed.gd`（`EventFeed`）与 `event_detail_dialog.gd`（`EventDetailDialog`）：大地图右侧纵向事件框与可操作事件详情。
- `EventCenter` 增加 `RANSOM` 类型与 `get_actionable_events()` / `get_event()`。
- `IdGenerator.RANSOM`；`UnitData.noble_id` 与 `mark_ransomed()`；`PartyData.leader_noble_id` 回填。
- 测试：`combat_experience_award_test`、`lord_ransom_test`、`save_migration_test`。

### 变更

- 俘虏价格改为按兵种 `UnitConfig.tier`：一级 5、二级 20、三级 60；NPC 领主统一 100，不按经验等级。
- `PrisonerTradeManager` 出售领主后调用 `LordRansomManager.on_lord_sold()`；`PartyManager.add_prisoner()` 拒绝已售出单位。
- 战斗伤害结算统一在 `UnitController.apply_damage()` 写经验；箭矢经同一回调，击杀经验只发给实际完成击杀者。
- `StatCalculator` 在最终属性中叠加等级 HP 加成；`UnitConfig` 每级成长归零，避免重复叠加。
- 存档升级到 Schema v8：`ransoms`、`UnitData.noble_id`、旧 1–10 级按 `ceil(old/2)` 折算并保留溢出经验。
- 大地图事件中心聚合赎回事件；右侧事件框显示可操作事件，无事件时隐藏；事件框本身不暂停世界。

### 修复

- 同一敌人死亡后继续受到伤害不再重复发放击杀经验。
- 事件待处理期间领主被再次出售或重新关押时，事件立即失效、弹窗自动关闭且不可领取。
- 家族或据点消失时，赎回流程终止并尽量让领主回到世界，避免永久停留在已出售状态。

### 验证

- 已运行并通过：`combat_experience_award_test`、`lord_ransom_test`、`save_migration_test`、`combat_experience_test`、`stat_calculator_test`、`unit_manager_test`、`unit_party_serialization_test`、`unit_tier_wage_test`、`stage13_tavern_test`、`save_persistence_test`、`political_hierarchy_test`、`event_center_test`。
- `unit_visual_test` 的马腿枢轴/贴图可见性断言仍失败，与本次改动无关。

---

## 2026-11-22 · 主界面信息栏、事件中心与百科重构

### 新增

- `Scripts/Core/World/event_center.gd`（`EventCenter`）：只读事件聚合层，确定性事件 ID，聚合封地/补给/伤兵/冒险者状态；任务入口保留但当前为空。
- `Scripts/UI/WorldMap/event_center_panel.gd`（`EventCenterPanel`）：左侧分组事件列表 + 右侧详情，按签名刷新。
- `WorldContext.get_player_owned_settlements()` / `get_daily_balance_preview()`：复用授权与工资/税收缓存的只读查询。
- `WorldMapManager.get_movement_speed_breakdown()`：基于实际有效移速的移速分解接口。
- `FactionManager.get_hostile_kingdoms_for_house()` / `get_hostile_independent_houses_for_kingdom()` / `get_hostile_independent_houses_for_house()`：统一敌对势力聚合查询。
- `FiefRecruitmentManager.is_authorized_owner()`：征召授权唯一判断，供事件中心与 UI 复用。
- 测试：`main_map_info_test`、`event_center_test`；`time_calendar_test` 增加暂停计数嵌套断言。

### 变更

- 大地图顶栏改为 `TopBarLeft` / `TopBarCenter` / `TopBarRight`：世界时间水平居中，左侧显示金币与部队移速，右侧入口使用紧凑尺寸。
- 金币/移速悬浮支持普通简述与按住 ALT 明细；ALT 松开恢复简述，移出关闭。金币明细复用 `WorldContext.get_daily_balance_preview()`，移速明细复用 `get_movement_speed_breakdown()`。
- 建筑信息面板打开时，百科/部队/背包/事件中心等普通入口仍可使用；世界时间控制（按钮与快捷键）继续禁用。关闭覆盖层后地点面板、世界暂停与时间按钮禁用状态保持不变。
- 百科改为“一级分类（王国/家族/地点）→ 条目列表 → 二级详情”，不再在一级混入具体王国详情；王国与家族详情增加敌对王国/敌对独立家族区块与空状态，条目可跳转。
- `TimeManager.push_pause/pop_pause` 改为按原因引用计数，支持地点面板与百科/背包/部队等嵌套界面而不提前恢复世界时间。

### 修复

- 关闭嵌套 UI 时同一 `ui_panel` 暂停原因被提前释放，导致建筑面板仍打开但世界恢复运行的问题。
- 百科敌对势力直接读取统一关系查询，不再由 UI 维护第二套敌我判断。

### 验证

- 已运行并通过：`main_map_info_test`、`event_center_test`、`encyclopedia_ui_test`、`time_calendar_test`、`settlement_interaction_test`、`stage13_world_map_ui_test`、`party_panel_test`、`fief_adventurer_ui_test`。

---

## 2026-11-22 · 骑马朝向偏移、大地图目标虚线、村庄候选人可见性修复

### 新增

- 大地图玩家移动目标标记与动态虚线：`Scripts/Systems/WorldMap/move_target_guide.gd`（`MoveTargetGuide`），由 `world_map.gd` 创建并驱动。
- `Tests/SystemTests/world_map_move_target_test`：目标设置/更新、起点跟随、停止清理、镜头平移缩放不改变世界坐标、单标记节点。

### 变更

- 骑马人物贴图：朝左保持 `+3` 横向偏移；朝右在此基础上再向左 `6` 像素（净值 `-3`）。偏移按朝向在 `HumanVisual` 内统一计算，镜像只改 `scale.x`，不重复叠加。
- 大地图移动目标虚线读取既有 `PartyData` 移动状态与 `target_position`，不新增第二套移动数据；`FOLLOW_PARTY` 时终点取被跟随部队最新位置。

### 修复

- 村庄冒险者候选人 NPC 与名称标签误用场景根节点 `position`，导致全部叠在世界原点、镜头内不可见；改为使用 `candidate.world_position`。
- `Tests/SystemTests/fief_adventurer_ui_test` 增加候选人位置与互不重叠断言；`Tests/UnitTests/unit_visual_test` 增加左右朝向偏移断言。

### 验证

- 已运行 `unit_visual_test`、`world_map_move_target_test`、`fief_adventurer_ui_test`、`stage13_village_candidates_test`、`world_map_input_test`、`settlement_interaction_test`。
- 新断言全部通过；`unit_visual_test` 仍存在与本次无关的既有马腿枢轴断言失败（马前腿2/马后腿2）。

---

## 2026-11-22 · 部队面板双列布局与战斗经验文本等级

### 新增

- `CombatExperience`：战斗经验五级文本映射（新兵 / 一般士兵 / 老兵 / 精锐 / 百战精锐）与属性加成扩展入口。
- `Tests/UnitTests/combat_experience_test`：等级映射、边界与加成接口测试。

### 变更

- 部队管理面板扩大到 1280×660；士兵列表与俘虏列表改为每行两个条目的双列布局。
- 列表条目精简为头像缩略图、姓名、战斗经验与当前/最大生命值。
- 士兵详情移除“美术预览”标题、内部 ID、数值等级与经验进度条；预览图片在原有视口内放大，详情面板总高度不增加。
- 骑乘人物贴图在原有 15 像素上移基础上再向右移动 3 像素；马匹位置与步行状态不变。
- `StatCalculator.compute_final_stats()` 统一叠加战斗经验属性加成；当前五级加成为空，不改变现有数值。

### 接口

- `CombatExperience.TIER_NAMES` / `TIER_MIN_LEVELS` / `TIER_STAT_BONUSES`。
- `CombatExperience.tier_name_for_level()` / `stat_bonuses_for_level()` / `apply_stat_bonuses()`。

### 验证

- 已运行 `combat_experience_test`、`party_panel_test`、`party_economy_ui_test`、`stage13_prisoner_ui_flow_test`、`wounded_system_test`，均通过。
- 非 headless 截图确认：双列列表、详情无 ID/无预览标题、美术预览放大、骑乘预览右移。

### 未决

- 五个战斗经验级别对应的具体攻击力/生命值加成数值未确认，仅预留接口。

---

## 2026-11-22 · 大地图 UI、部队面板与小地图战斗视觉优化

### 新增

- `TextureRegionUtils`：按 PNG 非透明像素边界裁切贴图的运行时工具，带结果缓存。
- `PartyUnitThumbnail`：部队面板列表项的 48×56 `SubViewport` 士兵缩略图，复用 `UnitVisual`，无单位时绘制默认剪影。
- `SettlementTavernHost` 与酒馆内嵌模式：城镇酒馆内容复用原地点面板。
- 部队面板俘虏列表：位于成员列表下方，点击进入只读俘虏详情。

### 变更

- 地点名称标签圆形徽章恢复完整绘制：`CLIP_CHILDREN_AND_DRAW` 同时绘制底盘并裁剪旗帜；圆形遮罩支持宽高比。
- 地点徽章、部队标记、停留旗帜条、百科房屋徽章、战斗增援旗帜改用裁切后的有效区域缩放，视觉尺寸统一。
- 城镇酒馆不再打开二级弹窗；返回酒馆/离开地点/进入村庄时清理酒馆状态。
- 战斗场景改为统一伪 Z：`World/Characters` 的 YSort 负责士兵前后顺序，士兵根节点 `z_index = 0`。
- 所有士兵影子移入 `World/Shadows`（z_index = 100），始终位于全部士兵主体之下；影子动画仍由 `HumanVisual`/`HorseVisual` 驱动。
- 部队面板成员条目增加缩略图，成员与俘虏共用同一列表项与选中逻辑。

### 决策

- D158：战斗伪 Z 由 YSort 统一排序，影子独立置于角色层之下。
- D159：透明边距运行时裁切与酒馆内嵌地点面板。

### 验证

- 已运行 `battle_scene_test`、`archer_battle_test`、`unit_visual_test`、`party_panel_test`、`stage13_prisoner_ui_flow_test`、`stage13_tavern_test`、`stage13_world_map_ui_test`、`world_map_milestone6_test`，均通过。
- 非 headless 截图确认：地点圆形徽章恢复、旗帜有效区域放大、部队面板缩略图/俘虏列表、酒馆内嵌布局、战斗 Y 排序与阴影层。

---

## 2026-11-22 · 阶段 13：大地图部队展示、伤兵恢复与俘虏系统

### 新增

- `WoundedConfig`（`Data/Combat/wounded_config.tres`）：按 tier 集中配置负伤概率，默认 1/2/3 级 = 50%/60%/80%，可整体禁用。
- `HealingConfig`（`Data/Combat/healing_config.tres`）：每游戏小时基础治疗点与预留药物加成。
- `PrisonerPriceConfig`（`Data/Settlements/prisoner_price_config.tres`）：按单位等级集中配置俘虏售价，默认 10/20/30 金币。
- `WoundedHealingManager`：按 `WorldTime` 整小时结算的伤兵顺序治疗管理器，接入 `WorldContext` 与 `WorldSimulation`。
- `PrisonerTradeManager`：城镇酒馆出售俘虏的原子业务入口，校验、去重、结算与售出状态写入。
- `SettlementStationedBar`：地点下方停留部队家族旗帜条；无圆形底盘、自动换行、地点间隔离。
- `PrisonerSelectionPanel`：战后俘虏选择界面（左待接收/右已有，支持转移、撤回、重置，确认才提交）。
- `TavernPanel`：城镇酒馆菜单、出售俘虏双栏界面、雇佣兵信息占位与离开。
- `UnitData` 新增 `Status.WOUNDED`、`prisoner_owner_party_id`、`sold_to_settlement_id` 及对应状态方法。
- `PartyData.prisoner_unit_ids` 与 `PartyManager` 俘虏 API（添加/转移/移除/释放、一致性校验与幂等清洗）。
- `BattleResultData` 新增 `prisoner_pool`、`prisoner_allocations`、`participant_unit_counts`、`player_prisoners_committed`、`prisoner_allocation_degraded`。
- `BattleManager` 新增负伤判定、最大余数分配、待玩家确认份额、原子提交/回滚与未接收俘虏释放。
- `SaveData` v7：伤兵状态/HP、俘虏归属与列表、`healing_last_settled_hour`、村庄候选人字段。
- 测试：`wounded_system_test`、`wounded_healing_test`、`stage13_village_candidates_test`、`stage13_world_map_ui_test`、`stage13_prisoner_test`、`stage13_prisoner_ui_flow_test`、`stage13_tavern_test`。

### 变更

- 战斗结算把“HP≤0 即永久死亡”改为“按 tier 概率负伤，否则永久死亡”；玩家角色仍永久死亡。
- 伤兵保留原部队成员身份和数据，HP=0，不能参战/移动/攻击；治疗满血后自动恢复 `ACTIVE`。
- 战败方伤兵进入俘虏池；胜利方按实际参战单位数（含增援，非存活数）分配，玩家份额需在战后界面确认。
- 地点标记优先显示家族旗帜；家族归属变化时刷新，无家族时保留原建筑美术。
- 停留在地点交互范围内的部队隐藏圆形标记，改在地点下方显示家族旗帜条；离开/解散/转移/摧毁后恢复。
- 玩家 UI 与悬浮提示统一显示最终移动速度，静止时也显示。
- 村庄初始化时生成初始冒险者，复用既有候选人数据与招募流程。
- 城镇地点面板新增酒馆入口；出售俘虏价格不再散落在 UI 中。
- 存档 Schema 6 → 7；v6 及更早存档读取时执行幂等默认值与俘虏归属清洗。

### 决策

- D152：负伤概率只由 `WoundedConfig` 提供，战斗结算统一读取 tier 概率。
- D153：伤兵治疗只由 `WorldTime` 整小时边界驱动，暂停不推进，治疗点按成员顺序消耗并允许溢出。
- D154：俘虏池只取战败方伤兵；胜利方份额按实际参战单位数用最大余数法分配，平局按稳定 party_id。
- D155：玩家俘虏份额先挂起，确认时原子提交；取消/未接收单位释放并移出世界。
- D156：俘虏价格集中配置；酒馆出售必须一次性原子结算，售出单位进入 `sold_to_settlement_id` 非玩家状态。
- D157：存档 Schema v7 与伤兵/俘虏/治疗进度迁移；读档清洗保证成员与俘虏互斥、无重复 Unit。

### 验证

- 已运行本阶段相关测试：`wounded_system_test`、`wounded_healing_test`、`stage13_village_candidates_test`、`stage13_world_map_ui_test`、`stage13_prisoner_test`、`stage13_prisoner_ui_flow_test`、`stage13_tavern_test`，以及战斗结算、存档、政治层级、市场与部队架构回归套件，均通过。
- 已修复 `TradeSession.get_sale_counts()` 买卖方向相反导致村庄出售被当成购买的既有缺陷。
- `supply_manager_test` 仍有一条与阶段 13 无关的 NPC 草料缺口断言失败，记录于 `Known_Issues.md`。
- 未改变无关的战斗/移动/AI 架构。

---

## 2026-11-22 · 阶段 12：马匹个体、补给消耗与村庄/城镇交易

### 新增

- `MountInstanceData`：马匹独立实例（`instance_id` / `equipment_id` / `coat_style_id` / `saddle_style_id` / `display_name`），创建时随机外观并随存档持久化。
- `MountVisualConfig`：毛色（黑/白/棕）与 8 种马鞍贴图的唯一映射。
- `MountThumbnail`：交易列表中的马匹缩略图，复用 48×96 马匹画布等比缩放。
- `bread` / `fodder` 的 `ItemConfig` 与市场商品配置，支持 10 / 50 批量购买。
- `SupplyManager`：按游戏日边界结算玩家与 NPC 的面包/草料消耗、缺口记录、剩余天数与采购需求查询。
- `TradeSession`：市场打开期间的预览状态、左右直接移动、快照重置、总额计算与确认提交。
- `AIManager` NPC 补给采购：低补给时前往有库存的村庄/城镇，用自有金币补至 7 天储备。
- `EventBus.party_supply_changed`、`EventBus.npc_supply_purchased`。
- 村庄大地图“购买补给”入口与村长对话入口。
- `SaveData` v6：`supply_last_settled_day`、市场马匹实例与 NPC 背包/金币持久化。
- 测试：`mount_instance_test`、`supply_manager_test`、`ai_supply_purchase_test`；扩展 `market_manager_test`、`town_market_ui_test`。

### 变更

- `InventoryData` 统一玩家与 NPC 背包：可堆叠物品存 `stackable_counts`，马匹存 `mount_instances`；旧数量确定性迁移为实例。
- 马匹装备/卸下改为实例级接口；卸下返还同一实例与外观。
- 交易 UI 改为“左市场/右玩家”直接移动，不再使用独立购物车；“重置交易”恢复打开时快照。
- 市场地点范围由“仅城镇”扩展为“村庄（面包/草料）+ 城镇（面包/草料/马匹）”，城堡仍无市场。
- 每行加入最左侧物品图标；马匹逐匹展示与买卖。
- `WorldSimulation` 在每次世界 tick 调用 `SupplyManager.update_daily()`，位于 AI 决策之前。
- 新世界自动补给：玩家 7 天份，NPC 2 天份并给予起始资金；强盗除外。
- 存档 Schema 5 → 6；v5 及更早存档读取时执行一次补给初始化。

### 决策

- D146：普通消耗品堆叠，马匹一律独立实例。
- D147：交易预览按快照差值计算，重置恢复快照而非反向重放。
- D148：补给消耗只在 `SupplyManager`、按 `WorldTime` 日边界结算。
- D149：村庄与城镇共用 `MarketManager`，城堡不设市场。
- D150：NPC 补给采购由 `AIManager` 决策、`MarketManager` 结算，不写玩家世界日志。
- D151：存档 Schema v6 与旧档补给/马匹迁移。

### 验证

- 新增与扩展测试已写入；本轮未找到可执行的 Godot 二进制，未实际运行，需编辑器重新导入后执行。
- 测试范围按改动影响限定在交易、马匹、补给与存档相关套件。
- 未改变战斗、外交与招募核心规则。

---

## 2026-11-22 · 阶段 11：玩家背包 UI 与城镇交易市场系统

### 新增

- `MarketGoodsConfig`（`Data/Market/mount_horse_01_goods.tres`）：普通战马买入 100 / 卖出 70 / 初始库存 3。
- `MarketData`：每个城镇独立的库存字典。
- `MarketManager`：商品注册、城镇市场初始化、交易校验、原子提交/回滚、交易 ID 去重、库存序列化；接入 `WorldContext`。
- `InventoryPanel`：大地图只读背包 UI，显示金币、物品名称/类型/数量与描述。
- `MarketPanel`：左市场/右背包双栏交易界面，含购买/出售预览、实时金额、确认/取消与错误提示。
- `SaveData.markets`：城镇市场库存存档字段（向后兼容，未提升 Schema）。
- `WorldLogEntry.EventType.PLAYER_TRADE`：玩家交易日志。
- `Tests/UnitTests/market_manager_test.tscn`、`Tests/SystemTests/town_market_ui_test.tscn`。

### 变更

- `WorldLogManager.MAX_ENTRIES` 100 → 20；新增、读档、保存与 UI 显示统一按 20 条裁剪。
- 地点面板新增 `SettlementMarketButton`；仅 `SettlementType.TOWN` 显示，村庄/城堡不显示。
- 市场打开时隐藏地点面板并沿用同一 `ui_panel` 暂停原因；取消/关闭恢复地点面板，不恢复 1x/2x。
- 大地图顶栏新增“背包”按钮；打开/关闭成对维护 `ui_panel` 暂停原因。
- 新游戏玩家初始金币 500（读档以存档为准）。
- 交易成功后同步刷新背包面板数据与世界日志。

### 决策

- D143：交易预览与权威数据分离。
- D144：`MarketManager` 是交易唯一业务入口。
- D145：玩家交易写世界日志，NPC 交易不写。

### 验证

- 新增 `market_manager_test`、`town_market_ui_test` 全部通过。
- 扩展并通过：`world_log_manager_test`、`world_log_ui_test`、`save_persistence_test`。
- 回归通过：`settlement_interaction_test`、`player_character_data_test`。
- 未执行全项目战斗/AI/外交套件；未改变存档 Schema。

---

## 2026-11-22 · 阶段 10：战后追击、AI 助攻、增援部署与大地图交互完善

### 新增

- `faction_bandit_hostility_test`：强盗对国王、骑士、独立家族与玩家家族敌对；同家族/同王国友好；商队中立/治安队友好；改名后仍按类型判定。
- `party_intent_hover_test`：悬浮“行动：XXX”覆盖待命、巡逻、前往地点、追击、跟随、战场响应、征召，意图变化自动刷新，Alt 构成展开只读。
- `party_attack_confirmation_test`：主动攻击二次确认、取消零副作用、确认重校验、重复入口只建一场战斗、加入友军不弹确认。
- `WorldMapManager` 相机 `FOLLOW_PLAYER` / `FREE_CAMERA` 模式；`PartyHoverActivity` 行；战斗摘要悬浮查询与显示接口。
- `BattleManager.get_join_side()` 全侧检查与拒绝第三侧；`WorldMapManager` 攻击确认面板与统一 `begin_battle_with_party` 入口。

### 变更

- `EncounterManager.update_encounters()` 不再要求双方 `MOVING`；只按有效性、敌对关系、遭遇距离与攻击/追击意图判定。
- 玩家追击使用 `focus_party_id` + `FOLLOW_PARTY`；目标移动、转向或进入离屏战斗时保留焦点并等待，战斗结束后恢复。
- 战后冷却继续由 `BattleManager` 写入，冷却期间 AI 恢复路线/巡逻，到期后重新评估；不再永久卡死或连续开战。
- `FactionManager.get_party_relation()` 增加强盗对任何政治家族贵族（含玩家家族）一律 `HOSTILE`。
- `VisionManager` 支持 `include_in_battle` 查询；`AIManager` 要求实际看见参战方且进入接近半径才响应，并保持响应目标避免抖动。
- AI 助攻加入必须“恰好一个敌对侧 + 至少一个非敌对侧”；与所有侧敌对/全中立拒绝，不自动创建第三战斗侧；商队不响应。
- 增援后方由“当前友军质心”改为“该战斗侧初始锚点”；网格排满时在己方半场均匀扫描选择最远合法点，保证不重叠/不越界。
- 部队悬浮新增行动意图行；战斗摘要面板默认隐藏、仅悬浮对应 `BattleMarker` 时显示；WASD 进入自由镜头并按缩放换算速度、限制边界。
- 玩家主动攻击先弹二次确认；取消无副作用；确认重校验；重复确认不产生第二场战斗；加入友军不弹确认。
- `PartyMarkerStyle.flag_max_size` 38 → 44；圆形底盘、边框、点击/悬浮区域、人数显示与动画不变。

### 决策

- D131：遭遇检测与移动状态解耦，追击关系跨战斗保持。
- D132：战后冷却统一由 `BattleManager` 写入并在到期后重新评估。
- D133：玩家追击焦点在目标战斗期间保留。
- D134：强盗敌对关系统一在 `FactionManager` 解析。
- D135：AI 战场助攻以视野发现参战方为门槛。
- D136：助攻检查全部战斗侧，不自动创建第三侧。
- D137：增援按初始战斗侧锚点部署，网格排满时半场扫描。
- D138：悬浮行动文本由运行时字段派生，UI 只读。
- D139：AI 对 AI 战斗摘要仅在悬浮战斗标记时显示。
- D140：大地图相机区分跟随玩家与自由镜头。
- D141：玩家主动攻击统一二次确认并重新校验。
- D142：部队内部旗帜进一步放大到 44 像素。

### 验证

- 新增 `faction_bandit_hostility_test`、`party_intent_hover_test`、`party_attack_confirmation_test` 全部通过。
- 扩展并通过：`ai_encounter_flow_test`、`player_pursuit_encounter_test`、`battle_reinforcement_test`、`world_map_battle_marker_test`、`world_map_input_test`。
- 回归通过：`multi_party_battle_test`、`ai_manager_test`、`battle_scene_test`、`battle_cluster_test`、`save_persistence_test`、`milestone1_test`、`settlement_interaction_test`。
- 按增量要求先跑最小相关测试，再执行相关回归链；未执行全项目套件，未做非 headless 视觉验收。未改变存档 Schema。

---

## 2026-11-22 · 阶段 9：大地图地点区域化布局与部队内部旗帜放大

### 新增

- `world_map_layout_test`：9 地点、世界尺寸、名称唯一、边界余量、最小间距、家族跨度、王国跨度与质心间隔、家族靠近所属王国、圆形半径与旗帜尺寸。
- `WorldInitializer` 新增地点坐标常量：`BARI_VILLAGE_POSITION`、`MOXIXI_VILLAGE_POSITION`、`NORTH_VILLAGE_POSITION`、`GREY_CASTLE_POSITION`、`BURKNANIA_TOWN_POSITION`、`BURKNA_VILLAGE_POSITION`、`OLIN_CASTLE_POSITION`、`OLIN_VILLAGE_POSITION`。

### 变更

- 9 个地点按王国/家族重新聚类：
  - 伯克纳尼亚王国（上部）：墨西西 (2500, 700)、伯克纳尼亚 (2900, 750)、北境村 (2250, 1000)、伯克纳 (3200, 1000)；
  - 奥林王国（下部）：奥林德斯堡 (2950, 1850)、奥林 (3250, 2050)、巴里 (2600, 2100)、灰石城堡 (2900, 2350)；
  - 青禾村 (1600, 1500) 位于两区域之间的西侧中立缓冲带。
- 家族骑士、国王卫队与巡逻点同步移动到对应区域；AI 行为类型与巡逻规则不变。
- `map_background.gd` 清空区与道路改用同一组坐标。
- `PartyMarkerStyle.flag_max_size` 30 → 38；`marker_radius` 18、`border_width` 2、底盘、边框、点击/悬浮区域、地图位置与移动动画不变。
- 无旗帜纹理时的回退三角形限制在 `inner_radius * 0.62` 内。
- `encounter_dialogue_ui_test` 标记断言更新；`milestone1_test` 改为从 `WorldInitializer.BARI_VILLAGE_NAME` 动态读取巴里位置。

### 决策

- D128：保持 5000×3000 世界尺寸不变，通过坐标聚类缩短距离，避免波及世界边界、摄像机与存档尺寸。
- D129：地点 ID、名称、类型、归属与交互配置完全不变，只换坐标；旧存档仍保留自身坐标。
- D130：旗帜按贴图画布等比缩放并居中，尺寸参数化在 `PartyMarkerStyle`，圆形遮罩按实际半径裁剪。

### 验证

- 新增 `world_map_layout_test` 通过。
- 更新后通过：`milestone1_test`、`encounter_dialogue_ui_test`。
- 回归通过：`world_map_milestone6_test`、`settlement_interaction_test`、`fief_adventurer_system_test`、`world_map_input_test`。
- 按需求只运行布局/地点/图标相关测试，未执行全项目套件；未做非 headless 视觉验收。

---

## 2026-11-22 · 阶段 8：战场扩建、增援表现、贵族王国体系、世界地图扩建与百科

### 新增

- `NobleData` / `NobleManager`：贵族 ID、名称、家族、爵位（Knight/Baron/Duke）、宗主、领袖/国王标记、独立部队、存活状态；引用与循环校验、领袖死亡选举与待定状态。
- `HouseData` / `HouseManager`：领袖、贵族、封地、王国、宗主家族、旗帜 ID、玩家家族标记；视觉家族 → 政治家族 `banner_id` 映射。
- `KingdomData` / `KingdomManager`：统治家族、国王、附庸家族、敌对王国、颜色、活动状态；战争传播到成员家族。
- `EventBus.party_reinforced(battle_id, party_id, noble_id, side_index)`。
- `FactionManager.get_party_relation()`、`get_house_relation()`、`are_houses_hostile()` 统一关系查询。
- `Data/Families/family_burknania.tres`、`family_olin.tres`。
- 大地图顶栏“百科”入口与三级屏幕面板（王国列表 / 王国详情 / 家族详情）。
- 测试：`political_hierarchy_test`、`battle_reinforcement_test`、`encyclopedia_ui_test`。

### 变更

- 战场 1800×1024，初始部署距离 1580、边距 110；`battlefield_width/height`、`initial_army_distance`、`deployment_margin` 参数化。
- 新遭遇与增援分流：增援加入既有 `BattleSession`，在战斗中心后方 240 像素、3 列网格展开，不重叠、不重置既有单位与冷却。
- `BattleParticipant` / `BattleUnitState` 新增 `is_reinforcement`、`reinforcement_battle_id`、`reinforcement_arrival_time`。
- 仅 NPC 加入玩家战斗侧时显示增援提示；有旗帜显示家族旗帜文本 + 徽章，无旗帜显示纯文本；消息排队、不暂停。
- 世界尺寸 3000×2000 → 5000×3000；新增伯克纳尼亚（城镇+村庄）与奥林（城堡+村庄），墨西西附庸伯克纳尼亚、巴里附庸奥林，两王国交战，玩家中立。
- 地点层级：村庄 1 级、城堡 2 级、城镇 3 级；仅村庄可征召；新地点全部归属家族。
- 封地征召授权改为 `owner_noble_id` 本人或家族领袖。
- 存档 Schema v4 → v5：新增 `nobles`、`houses`、`kingdoms`，保留 `lords` 兼容；读档不重复创建家族。
- 地点图标新增城镇绘制；地图背景扩展清空区与道路。

### 决策

- D121：政治身份（家族/王国）优先于阵营，阵营作为无家族部队的回退。
- D122：`NobleData extends LordData`、`NobleManager extends LordManager`，`lord_manager` 指向同一实例，保持旧接口与存档兼容。
- D123：视觉家族 `FAMILY_*` 与政治家族 `HOUSE_*` 分离，通过 `HouseData.banner_id` 映射。
- D124：增援只加入既有会话，不新建战斗；侧别由统一关系查询决定。
- D125：领袖死亡按爵位降序、稳定 ID 升序选举；无候选时标记待定而非崩溃。
- D126：百科读取真实管理器，签名轮询刷新，打开暂停世界但不重置相机。
- D127：Schema v5 持久化政治层级并校验引用。

### 验证

- 新增 `political_hierarchy_test`、`battle_reinforcement_test`、`encyclopedia_ui_test` 通过。
- 更新后通过：`milestone1_test`、`milestone1_restart_test`（save/load 两阶段）、`family_appearance_test`、`battle_scene_test`、`save_persistence_test`、`unit_party_serialization_test`、`battle_cluster_test`。
- 修复 `FactionManager` 独立测试夹具：`setup_defaults(party_manager)` 允许只注入部队仓储并回退到阵营关系；`faction_vision_test`、`ai_manager_test`、`battle_result_test`、`multi_party_battle_test`、`offscreen_battle_hourly_test` 恢复通过。
- 全量 `Tests/SystemTests` + `Tests/UnitTests`（60 个场景，另含跨进程 save/load）通过。
- 仅执行 headless 自动测试，未做非 headless 视觉验收。

---

## 2026-11-22 · 修复：多场并行战斗与 AI 离屏战斗自动结束

### 变更

- `BattleManager` 改为多战斗注册表：`active_battles: { battle_id: BattleSession }`、`party_battle_lookup: { party_id: battle_id }`。
- `current_battle` 仅表示玩家当前屏幕战斗；AI 离屏战斗不再写入该字段。
- 新增 `get_battle()`、`get_battle_for_party()`、`get_active_battles()`、`has_any_active_battles()`。
- `start_battle_by_sides()` 删除“已有战斗即拒绝”的全局限制；只拒绝参战部队自身不可用或已参加其他战斗。玩家仍最多一场屏幕战斗。
- `finish_battle(battle_id, result)` 按 ID 只结算/解锁/清理本场；结束 AI 战斗不触碰玩家战斗或其他 AI 战斗。
- `tick()` 复制有效战斗快照后逐场推进；每场离屏战斗使用独立 `OffscreenBattleResolver` 与随机序列。
- 加入接口显式传 `battle_id`：`get_join_side()`、`can_party_join()`、`try_join_battle()`、`add_reinforcement()`。
- `OffscreenBattleResolver.count_living_sides()` 只统计至少有一名存活单位的战斗侧；一方全灭立即结束，双方全灭按平局。
- `EncounterManager` 按双方各自所属战斗创建/加入/跳过，禁止合并不同战斗；玩家只加入实际接近且最近的战斗。
- `AIManager._try_respond_to_battle()` 遍历全部离屏战斗，选择可加入且距离最近的一场。
- 大地图改为 `_battle_markers: { battle_id: BattleMarker }`；参战图标按“是否参与任意进行中战斗”隐藏，结束一场只恢复该场图标。
- `WorldLogManager` 按 `battle_id` 关联日志；`GameManager.save_game()` 使用 `has_any_active_battles()`。
- 暂停规则不变：AI 离屏战斗不暂停世界；玩家屏幕战斗压入 `battle`；结束 AI 战斗不改变其他暂停原因。

### 测试

- 扩展 `battle_manager_test`、`offscreen_battle_hourly_test`、`multi_party_battle_test`、`ai_manager_test`、`world_map_battle_marker_test`，覆盖两场并行战斗、同一 tick 独立推进、0 人战斗侧不计入、一方/双方全灭、双战斗标记与独立图标恢复。
- 更新 `battle_occupancy_ui_test`：其他战斗不再阻塞无关部队开战。
- 回归通过玩家战斗、场景切换、存档校验与世界日志相关测试。战斗会话仍不进入存档；进行中战斗会阻止保存。

---

## 2026-11-22 · 修复：恢复“先移动到地点、到达后再交互”

### 变更

- `WorldMap.handle_left_click()` 点击地点不再直接调用 `_open_settlement()`，改为 `_request_settlement_interaction()`。
- 新增运行时状态 `_pending_settlement_interaction_id`：记录玩家主动点击、正在前往的地点，不进入存档。
- 新增 `SETTLEMENT_INTERACTION_RADIUS = 40.0` 与 `_check_pending_settlement_interaction()`：
  - 远距离点击：设置 `WorldMapManager.set_party_target()`，基础倍率切回 1x，清除追逐/跟随，不暂停、不弹面板。
  - 已在 40 像素内：允许直接打开面板。
  - 到达检测：pending 有效、玩家可用、移动已停止、距离 ≤ 40、移动目标仍指向该地点，才消费 pending 并调用 `_open_settlement()`。
- 普通地图点击、点击部队、切换地点目标、外部停止、进入战斗或离开大地图时清除 pending；点击另一个地点直接替换目标 ID。
- `_open_settlement()` 仍统一负责停止部队、基础倍率 0、`ui_panel` 暂停与面板显示。
- 不改 `WorldMapManager` 移动/到达逻辑，不改 NPC AI、遭遇与追逐规则。

### 测试

- 修改 `world_map_milestone6_test` 中错误的“点击即打开”期望为真实移动到达流程。
- 新增 `settlement_interaction_test`：远距离点击、到达、路过、追逐、指令覆盖、切换地点、已在地点附近、中途停止、城堡/城镇、面板内容。
- `village_flow_test` 增加“从村庄返回不残留 pending、不自动重开面板”断言。
- 通过：`world_map_milestone6_test`、`settlement_interaction_test`、`world_map_input_test`、`village_flow_test`。

---

## 2026-11-22 · 阶段 7 第一步：封地所有权、采邑征召与村庄冒险者

### 新增

- `LordData` / `LordManager`：领主 ID、名称、阵营、部队、玩家领主标记、战略状态/目标、关系与存活状态；`validate()` 校验部队引用与唯一性。
- `SettlementData` 扩展：`owner_lord_id`、`population`、`prosperity`、`tax_base`、`tax_income_per_day`、`fief_recruitment_stock/capacity/elapsed`、`adventurer_candidates`、`adventurer_refresh_elapsed`。
- `SettlementEconomyConfig`（`Data/Settlements/settlement_economy_config.tres`）：采邑编制/储备/成本/周期、冒险者上限/刷新/费用、税收基数与 AI 阈值。
- `TaxCalculator.compute_daily_tax()`：统一税收公式。
- `FiefRecruitmentManager`：归属校验、储备补充、6 人成组征召、真实马匹装备、资源扣除与原子回滚。
- `AdventurerRecruitmentManager`：每村候选人池、持久化姓名/位置/外观、世界时间刷新、1 金币招募、离开清理。
- `AdventurerCandidateData`：`AVAILABLE` / `RECRUITED_PENDING_DEPARTURE` 状态机。
- `WorldLogPanel`：从大地图抽出的共享日志组件，村庄右上角复用。
- `EventBus.fief_recruited` / `adventurer_recruited` 与 `WorldLogEntry` 新事件类型。
- `Data/Families/family_player.tres`、玩家村庄“青禾村”、`PartyIcon.show_floating_text()`。
- `fief_adventurer_system_test`、`fief_adventurer_ui_test`。

### 变更

- 新游戏新增玩家领主与 NPC 家族领主，地点归属通过 `owner_lord_id` 表达；地点数量 4 → 5。
- `player_hero.tres` 改为三级：180 HP、25 攻击、0 工资；玩家角色使用玩家家族外观。
- 玩家地点面板新增领主/家族/人口/繁荣度/税收/采邑储备与征召按钮；村庄头人对话新增采邑征召选项。
- `AIManager` 新增领主征召决策：低于 12 人时前往最近自有村庄征召一组，`RECRUITING` 期间跳过战术 AI。
- `WorldSimulation` 在移动/视野后推进采邑与候选人计时。
- 存档 Schema v3 → v4：新增 `lords`、玩家领主/角色 ID、封地与候选人字段；读档新增所有权校验。
- `StatCalculator.STAT_KEYS` 补齐远程/身高派生字段。

### 决策

- D108：`owner_lord_id` 为封地归属唯一权威，玩家领主与玩家角色分离。
- D109：税收统一由 `TaxCalculator` 计算。
- D110：采邑成组征召全有或全无。
- D111：冒险者候选人状态机与外观持久化。
- D112：AI 领主征召使用 `RECRUITING` 协作状态。
- D113：Schema v4 持久化领主/封地/候选人并校验所有权。

### 验证

- 全量 `Tests/SystemTests` 与 `Tests/UnitTests` 通过，包含新增 `fief_adventurer_system_test`、`fief_adventurer_ui_test`。
- 更新期望后通过：`party_economy_ui_test`（49/57）、`milestone1_test`（13 实体）、`family_appearance_test`（3 家族）、`stat_calculator_test`、`unit_party_serialization_test`。
- 仅执行 headless 自动测试，未做非 headless 视觉验收。

---

## 2026-11-21 · 阶段 6 后续：弓箭手与远程箭矢

### 新增

- `EquipmentConfig.attack_type`（`MELEE` / `RANGED`）、`attack_interval_override`、`projectile_texture_path`、`projectile_speed`、`projectile_arc_height`、`is_ranged_weapon()`。
- `UnitConfig.body_height`；`UnitData` 派生字段 `attack_type`、`body_height`、`projectile_*` 与 `is_ranged_attacker()`，随存档往返。
- 三级弓箭手配置 `Data/Units/archer_militia.tres` / `archer_trained.tres` / `archer_veteran.tres`（10/50、20/100、25/180）。
- 弓装备 `Data/Equipment/weapon_bow_01.tres`：射程 360、攻击间隔 3 秒、临时弓/箭美术、握把锚点 `(27,36)`。
- `ArrowProjectile`：地面投影 + 抛物线视觉高度、固定终点、地面半径/身高命中、每箭最多一次伤害。
- `ProjectileManager`：创建/推进/清理箭矢，注入全部 `UnitController`。
- `CombatRules.ranged_attack_range()` / `is_in_ranged_range()` / `can_ranged_attack()`。
- `UnitController._tick_ranged()` 与 `_fire_ranged_at()`：远程 AI（接近/站定/后撤/换目标）与玩家共用发射入口。
- `HumanVisual.play_ranged_attack_animation()`：拉弓 0.18s / 撒放 0.08s / 恢复 0.30s。
- `archer_battle_test`、`archer_scene_test`。

### 变更

- `StatCalculator` 从 WEAPON 派生攻击方式、攻击间隔与弹道参数，并按骑乘叠加身高。
- `BattleScene` 创建并推进 `ProjectileManager`；队形槽位分配将近战排前、远程排后；左键提示改为“攻击/射箭”。
- `WorldInitializer` 新游戏玩家部队扩编到 15 人：5 民兵 + 6 职业步兵（4 骑乘）+ 2 一级弓 + 1 二级弓 + 1 玩家角色。
- 玩家接管弓箭手后使用弓的 3 秒冷却，不继承原控制单位冷却。
- `player_party_expansion_test`、`unit_tier_wage_test` 更新到 15 人编制与新增工资。

### 决策

- D103：攻击方式由武器派生，不按兵种名分支。
- D104：箭矢地面投影与视觉高度分离，高度不参与 Y 排序。
- D105：固定终点 + 身高判定，无随机命中率，每箭最多一次伤害。
- D106：AI/玩家共用发射入口，冷却绑定发射者。
- D107：远程单位优先分配后排队形槽位。

### 验证

- 通过：`archer_battle_test`、`archer_scene_test`、`battle_scene_test`、`combat_attack_rules_test`、`battle_formation_test`、`player_control_test`、`battle_retreat_test`、`battle_side_result_test`、`milestone2_flow_test`、`save_persistence_test`、`battle_result_delay_test`、`player_party_expansion_test`、`unit_tier_wage_test`、`unit_visual_test`。
- 未执行与经济/大地图无关且不受本次改动影响的全量套件。

---

## 2026-11-21 · 阶段 6 后续：大地图表现、AI 战后恢复、存档与战斗 UI

### 新增

- `PartyData.engagement_cooldown_until`：战斗结束后的运行时交战冷却（30 世界秒，不进入存档）。
- `PartyManager.sanitize_loaded_runtime_state()`：读档清理攻击意图、焦点、冷却、失效战斗/追击状态。
- `SaveData.world_log` 与 Schema v3：世界日志进入存档。
- `BattleScene.VICTORY_RESULT_DELAY = 3.0` 与结果延迟状态；测试钩子 `set_result_delay_enabled()`、`skip_result_delay()`、`get_result_data()`。
- 大地图战斗汇总按 `side_index` 多列显示；`get_battle_summary_column_count()` / `get_battle_summary_side_indices()`。
- 悬浮信息左 Alt 详细模式与测试钩子 `set_alt_detail_active()` / `is_alt_detail_active()`。
- `save_persistence_test`、`battle_result_delay_test`。

### 变更

- `SettlementIcon` 恢复原始村庄/城堡世界美术；名称与家族徽章迁移到 `SettlementNameTag` 的固定 240×36 组合（徽章在左）。
- `BattleManager._unlock_session_parties()` 不再把存活部队移动目标重置到当前位置；清除战斗指令并施加交战冷却。
- `AIManager` 强盗/治安队在冷却期间恢复游荡/巡逻；`EncounterManager` 跳过冷却中的敌对组合。
- `WorldContext` 保存/恢复世界日志，并在读档后执行运行时清理与领袖/成员校验。
- `PartyData.from_dict()` 增加枚举范围校验；`validate_membership_consistency()` 校验领袖归属。
- 胜利结果面板延迟展示；失败、撤退、平局保持即时。
- 战斗汇总按战斗侧分列，第三侧自动扩列；战斗结束移除列。
- 悬浮默认为名称，按住左 Alt 显示总人数与兵种/骑乘构成。

### 决策

- D097：村庄美术与名称/徽章分层。
- D098：战后冷却而非重置移动目标。
- D099：Schema v3 世界日志与读档清理。
- D100：胜利面板物理时间延迟、数据即时。
- D101：汇总按 side_index 分列。
- D102：左 Alt 悬浮输入集中在 `world_map._input()`。

### 验证

- 通过：`save_persistence_test`、`battle_result_delay_test`、`world_map_milestone6_test`、`world_map_battle_marker_test`、`battle_scene_test`、`milestone2_flow_test`、`multi_party_battle_test`、`milestone1_restart_test`（save/load）及相关单元/系统回归。
- 存档 Schema：v2 → v3（新增 `world_log`，不要求旧档兼容）。

---

## 2026-11-21 · 修复：已有战斗时普通部队对话显示真实原因

### 新增

- 普通部队对话在已有战斗时区分三种情况：参战方可加入、参战方但无法加入、与当前战斗无关。
- 新增 `battle_occupancy_ui_test`：禁用原因、绕过按钮拒绝、参战方加入已有战斗。

### 变更

- `_open_party_dialogue()` 读取 `BattleManager.current_battle`：可加入时按钮变为“加入战斗”，否则禁用并显示具体原因。
- `begin_battle_with_party()` 使用同一套判断；已有战斗且无法加入时不再显示笼统的“无法开始战斗”。
- 目标 `IN_BATTLE` / `RETURNING` / `DISABLED` 与玩家自身不可参战分别显示对应状态。
- 加入路径复用 `try_join_battle()`，不新建战斗；暂停顺序保持“先 battle，后 ui_panel”。

### 决策

- D096：保留单一战斗会话规则，只修复入口判断与提示。

### 验证

- 通过：`battle_occupancy_ui_test`、`party_dialogue_test`、`encounter_dialogue_ui_test`、`world_map_milestone6_test`、`player_encounter_test`、`ai_encounter_flow_test`。
- 未改变存档 Schema 或战斗结算逻辑。

---

## 2026-11-21 · 阶段 6 后续：村庄标记、玩家扩编与小地图战斗集群优化

### 新增

- 玩家初始部队扩编为 12 人：1 玩家角色 + 5 民兵 + 6 职业步兵（4 名骑乘）；人数集中在 `WorldInitializer` 常量。
- `SettlementIcon` 村庄圆形标记：半径 32、旗帜最大边长 76，旗帜按圆形边框裁剪；城堡保留原建筑绘制。
- 村庄名称固定显示在圆形标记正上方，使用独立屏幕 UI 层，文字尺寸不随相机缩放。
- `BattleScene.INITIAL_DEPLOYMENT_DISTANCE = 1100`，双方初始阵线分居左右两侧。
- `UnitController` 目标占用统计与“距离 + 占用惩罚”目标选择；近距离包围角度与切向偏移。
- 测试 `player_party_expansion_test`、`battle_cluster_test`。

### 变更

- `PartyMarkerStyle` 恢复扩编前尺寸：半径 18、边框 2、旗帜 30、人数偏移 24；所有部队类型共用。
- `BattleScene` 队形改为双方半场列阵：前排保留 `SIDE_LINE_GAP = 90`，接敌距离 220 内队形放松。
- 队形间距调整为步行 40、骑乘 56；邻居半径 56；友军分离半径 44、敌军 34。
- 村庄名称不再带左侧小旗帜；旗帜改由放大的村庄圆形标记显示。
- `SettlementNameTag.set_screen_position()` 改为以标记上方锚点定位，标签整体位于标记上方。
- 更新大量玩家人数硬编码测试为 `WorldInitializer.PLAYER_TOTAL_MEMBER_COUNT`。

### 决策

- D092：恢复部队标记原尺寸，村庄使用独立放大标记。
- D093：玩家初始部队扩编为 12 人并集中配置。
- D094：屏幕战斗初始部署统一拉开距离。
- D095：半场列阵 + 目标占用 + 局部分离优化集群。

### 验证

- 通过：`player_party_expansion_test`、`battle_cluster_test`、`battle_scene_test`、`battle_formation_test`。
- 通过：`battle_retreat_test`、`battle_side_result_test`、`milestone2_flow_test`、`party_panel_test`、`party_dialogue_test`、`player_control_test`。
- 通过：`world_map_milestone6_test`、`encounter_dialogue_ui_test`、`player_encounter_test`、`neutral_party_interaction_test`、`player_pursuit_encounter_test`、`ai_encounter_flow_test`。
- 通过：`milestone1_test`、`milestone1_flow_test`、`world_map_input_test`、`village_flow_test`、`village_scene_test`、`party_architecture_test`、`unit_party_serialization_test`、`ai_manager_test`、`faction_vision_test`、`world_map_battle_marker_test`、`world_log_ui_test`、`mounted_unit_test`、`unit_tier_wage_test`、`player_character_data_test`、`unit_controller_test`、`formation_manager_test`。
- 未改变存档 Schema；玩家扩编只影响新游戏，旧存档不补兵。

---

## 2026-11-21 · 阶段 6 后续：统一部队架构、底部遭遇对话与敌对追击拦截

### 新增

- `PartyData.control_type`（PLAYER / AI）、`party_kind`（GENERIC / PLAYER / FAMILY / MERCHANT / BANDIT / GUARD）与 `banner_texture_path`，均进入存档并提供旧存档安全默认值。
- `PartyData.apply_runtime_defaults()` / `PartyManager.apply_runtime_defaults()`：读档后按 `player_party_id`、阵营、家族与 `ai_type` 补齐类型；不修改成员、位置或路线。
- `EncounterManager.EncounterReason`：`PASSIVE_ENCOUNTER` / `PLAYER_INITIATED` / `ENEMY_PURSUIT` / `OTHER`；待处理遭遇记录实际原因。
- `EncounterManager.can_leave_encounter()`：仅 `ENEMY_PURSUIT` 禁止离开；`decline_player_encounter()` 同步拒绝该类遭遇。
- `EncounterTextConfig` + `Data/Encounters/encounter_text_config.tres`：按遭遇原因与部队类型配置对白，UI 不再硬编码文本。
- `EncounterPortrait`：复用 `UnitVisual` 的领袖头像/剪影组件；无有效领袖时绘制默认头肩剪影。
- 普通 NPC 部队在初始化时获得 `leader_unit_id`，领袖名称沿用部队名。
- 测试 `party_architecture_test`、`encounter_dialogue_ui_test`。

### 变更

- 圆形部队标记标准半径 18 → 26，旗帜最大边长 30 → 56，边框/阴影/人数位置同步放大。
- `map_flag_circle.gdshader` 新增 `uv_radius`，旗帜可大于内径并在边框内缘裁剪，不再覆盖外圈边框。
- `PartyIcon` 无家族色时按 `PartyMarkerStyle.faction_colors` 读取阵营回退色；玩家、家族、商队、强盗、治安队共用同一标记组件。
- `PartyDialoguePanel` 与 `PlayerEncounterPanel` 从屏幕右侧迁移到屏幕下方，改为“左侧领袖头像 + 右侧姓名/对白/选项”的 NPC 对话布局。
- 敌对 AI 主动追击并成功追上玩家（`ENEMY_PURSUIT`）时不再显示离开按钮；玩家主动接近（`PLAYER_INITIATED`）仍保留离开选项。
- `AIManager` 按 `control_type == PLAYER` 跳过玩家部队，保留 `player_party_id` 作为旧数据回退。
- 更新 `player_encounter_test`、`neutral_party_interaction_test` 的选项与面板布局预期。

### 决策

- D089：统一 Party 控制类型、部队类型标识与旧存档推断。
- D090：遭遇原因驱动底部 NPC 对话与离开选项。
- D091：统一放大圆形标记与圆形旗帜遮罩半径参数。

### 验证

- 通过：`party_architecture_test`、`encounter_dialogue_ui_test`。
- 通过：`player_encounter_test`、`neutral_party_interaction_test`、`player_pursuit_encounter_test`、`party_dialogue_test`。
- 通过：`party_manager_test`、`unit_party_serialization_test`、`ai_manager_test`、`ai_encounter_flow_test`。
- 通过：`world_map_milestone6_test`、`world_map_input_test`、`milestone1_test`、`milestone2_flow_test`。
- 未改变存档 Schema 版本；新增字段均有安全默认值。

---

## 2026-11-21 · 修复中立家族骑士无法被玩家接近与交战

### 变更

- 玩家点击有效部队（移动中或静止）统一进入 `FOLLOW_PARTY`，不再因点击瞬间目标静止而只记录一次性坐标。
- 玩家主动点击的跟随不再要求目标在 `sight_range` 内，也不再因目标离开视野而取消；目标进入战斗、失效或距离 <= 14 像素时仍正常结束。
- 修复「远距离点击巡逻中的巴里/墨西西骑士 → 玩家走向旧坐标 → 骑士继续移动 → 焦点清除 → 永远无法开战」的问题。家族骑士为中立方，不会主动接近玩家，必须由玩家点击追击。
- `VisionManager` 只继续约束 AI 选敌，AI 行为不变。
- 同步更新 `world_map_input_test` 中“离开视野取消跟随”“静止部队普通移动”的旧预期。

### 决策

- D088：玩家点击部队一律主动跟随且不因离开视野中断，修订 D037、D073。

### 验证

- 通过：`world_map_input_test`、`party_dialogue_test`。
- 临时诊断验证：近距离点击静止的巴里骑士、远距离（视野外）点击巡逻中的墨西西骑士，均能持续追至 40 像素内打开部队对话，“发起战斗”可用；诊断脚本已删除。
- 未改变存档 Schema；未修改移动速度、战斗规则或阵营关系。

---

## 2026-11-21 · 阶段 6 家族领袖、NPC 部队与地图表现系统

### 新增

- `FamilyConfig` + `FamilyRegistry` + `Data/Families/*.tres`：巴里家族、墨西西家族，含旗帜、主/副色、主/副罩袍、领袖缨饰与家族长矛。
- `AppearanceConfig` + `Data/Appearance/appearance_config.tres`：1/2/3 级头盔池、罩袍主/副概率。
- `UnitAppearance`：创建时一次性生成头盔/罩袍/缨饰/长矛选择并写入 `UnitData.appearance`。
- `PartyMarkerStyle` + `Data/WorldMap/party_marker_style.tres`：圆形部队标记的尺寸、边框、旗帜缩放与人数位置集中配置。
- `SettlementNameTag`：固定屏幕地点名称层，名称左侧显示圆形家族旗帜。
- 两支家族骑士：巴里骑士、墨西西骑士（各 10 人，`FACTION_LOCAL`，专属巡逻）。
- 两支新强盗：东路强盗、荒野强盗（独立出生点与路线）。
- 测试 `family_appearance_test`。

### 变更

- `UnitData` 增加 `family_id` / `appearance`；`PartyData` 增加 `family_id` / `leader_unit_id` / `ai_patrol_points`；`SettlementData` 增加 `family_id`。
- `PartyManager` 增加 `get_leader_unit()` / `is_party_leader()`；移除领袖成员时清空 `leader_unit_id`。
- 玩家身份、当前控制、部队领袖、部队归属保持四个独立概念；玩家部队领袖指向 `player_hero`。
- 村庄「橡木村」「河畔村」重命名为「巴里」「墨西西」，并分别归属两个家族。
- `PartyIcon` 改为圆形标记，家族旗帜等比缩放放入圆内；人数与悬浮面板保持。
- 地点名称迁移到固定屏幕 UI 层，不再随相机缩放，也不参与点击判定。
- `WorldMapManager.update_party_movement()` 统一将大地图实际速度乘以 0.5；不修改 `PartyData.movement_speed` 或战斗移动速度。
- `AIManager` 支持部队专属巡逻点；家族骑士与全局巡逻队互不共享路线。
- 新游戏部队数从 4 增至 8：玩家、商队、治安队、3 支强盗、2 支家族骑士。
- 更新 `milestone1_test`、`milestone1_restart_test`、`milestone2_flow_test`、`unit_party_serialization_test`、`world_map_milestone6_test` 的数量、名称与速度预期。
- 未改变存档 Schema；新增字段均为带安全默认值的增量字段。

### 决策

- D086：家族仅承担视觉身份，领袖复用 `PartyData.leader_unit_id` 与现有 `UnitData`，不新增 LeaderManager。
- D087：大地图速度在统一移动入口乘一次 0.5；地点名称使用固定屏幕 UI 层。

### 验证

- 新增 `family_appearance_test` 全部通过：家族配置、改名村庄、两队 10 人编制、领袖/成员、头盔池、罩袍概率、装备优先级、序列化、旧存档默认值、速度倍率。
- 回归通过：`unit_visual_test`、`milestone1_test`、`milestone1_restart_test`（save/load）、`milestone2_flow_test`、`world_map_input_test`、`world_map_milestone6_test`、`party_dialogue_test`、`neutral_party_interaction_test`、`ai_manager_test`、`unit_party_serialization_test`。
- 未执行与本改动无关的全量测试；未做非 headless 截图验收。
- 明确未实现：家族外交/战争、领袖关系/任务、招募 UI、玩家家族创建/编辑、家族盾牌、家族领地、NPC 领袖管理 UI。

---

## 2026-11-21 · 阶段 6 地点点击交互与战斗名称显隐修复

### 变更

- 大地图地点交互改为**仅由鼠标左键点击地点触发**：点击 45 像素内的村庄/城镇/城堡打开地点面板；正常移动、追击或路过任何地点不再暂停、弹窗或打断行动。
- 新增 `WorldMap.handle_left_click()` 统一左键入口：地点点击优先，其次部队指令/地图移动；地点与部队重叠时按点击位置更近者判定。
- 移除 `WorldMap._check_settlement_interaction()` 的逐帧线段距离检测及相关 `INTERACTION_RADIUS` / `INTERACTION_EXIT_RADIUS` 常量。
- `GameManager.pending_settlement_latch_id` 返回大地图后仅记录当前村口村庄；不再用于自动打开面板。
- `UnitActor.NameLabel` 改为只对玩家当前控制的单位显示；普通士兵（含友军/敌军）默认隐藏，`set_controlled()` 在控制权转移时即时同步。
- 名称与生命条独立控制：隐藏名称不影响受伤生命条显示与满血隐藏规则。
- 更新 `milestone1_test`、`world_map_milestone6_test`、`unit_visual_test` 以覆盖点击打开、路过不弹窗及名称/生命条独立显隐。

### 验证

- 通过：`unit_visual_test`、`world_map_milestone6_test`、`world_map_input_test`、`party_dialogue_test`、`village_flow_test`、`milestone1_test`（地点面板已改为主动点击入口）、`battle_scene_test`、`neutral_party_interaction_test`。
- 未改变存档 Schema；地点面板、部队遭遇、追击与村庄进入流程保持原有数据与暂停语义。

---

## 2026-11-21 · 阶段 6 世界日志、美术层级与战斗表现优化

### 新增

- `WorldLogEntry` + `WorldLogManager`：监听战斗/遭遇/地点事实，生成带类型、世界时间与文本的日志；最多 100 条；预留 `to_dict/from_dict`。
- `EventBus.settlement_entered` / `settlement_exited`：玩家实际进入/离开村庄的事实。
- 大地图左下角 `WorldLogPanel`：固定 UI、滚动历史、自动刷新、`MOUSE_FILTER_PASS` 不阻挡地图操作。
- `UnitHealthBar`：独立头顶生命条；满血/死亡隐藏，受伤显示，恢复满血重新隐藏。
- `VisualLayers.RIGHT_HAND_WEAPON` / `LEFT_HAND_WEAPON` / `HELMET`：左右手武器与头盔独立层级。
- `HumanVisual` 左手武器枢轴、头盔部件、装备视觉注入接口。
- `EquipmentConfig.visual_texture_path` / `visual_layer` / `visual_anchor`。
- 测试：`world_log_manager_test`、`world_log_ui_test`、`neutral_party_interaction_test`；扩展 `unit_visual_test`。

### 变更

- 普通大地图对话只对 `focus_party_id` 的主动点击目标打开；普通寻路/追击路过中立或无关部队不再自动弹窗或暂停。
- 敌对 AI 自动遭遇仅在实际追击并追上玩家时触发；玩家主动点击追击属于显式交互入口，仍可接触。
- 左手武器层级 `-45`，低于马头 `-20`；右手长矛保持 `-10` 及原攻击动画。
- 人物 `Head` 与 `Helmet` 分离；当前无正式头盔/盾牌贴图，路径为空时安全跳过。
- `UnitActor` 名称与生命条拆为独立节点；不再在 `_draw()` 中绘制血条。
- 更新 `party_dialogue_test`、`world_map_input_test`、`world_map_milestone6_test`、`milestone2_flow_test` 以模拟主动点击动作。
- 未改变存档 Schema；日志历史不写入存档。

### 决策

- D082：世界日志由 `WorldLogManager` 监听事实并生成。
- D083：左右手武器独立层级与头部/头盔分离。
- D084：只有实际追击关系才触发自动遭遇。
- D085：单位名称与生命条使用独立节点。

### 验证

- 新增测试全部通过：`world_log_manager_test`、`world_log_ui_test`、`neutral_party_interaction_test`。
- 扩展 `unit_visual_test` 通过：左右手层级、头部/头盔独立、装备视觉注入、名称/生命条独立与满血隐藏。
- 回归通过：`party_dialogue_test`、`world_map_input_test`、`world_map_milestone6_test`、`milestone2_flow_test`、`battle_scene_test`、`player_control_test`、`party_panel_test`、`village_scene_test`、`village_flow_test`、`player_encounter_test`、`player_battle_interaction_test`、`player_pursuit_encounter_test`、`ai_encounter_flow_test`、`battle_retreat_test`、`world_map_battle_marker_test`、`multi_party_battle_test`、`offscreen_battle_hourly_test`。
- 未执行非 headless 视觉截图与跨进程重启测试。
- 明确未实现：日志存档/过滤/点击跳转、正式头盔与盾牌贴图、生命条样式主题。

---

## 2026-11-21 · 阶段 6 大地图战斗与小地图视角优化

### 新增

- `Scripts/Systems/Scene/scene_camera_rig.gd`：村庄与战斗共用摄像机；统一视野 `960×540`、跟随当前控制角色、`F` 自由视角、边界限制。
- `OffscreenBattleConfig` + `OffscreenBattleResolver` + `Data/Combat/offscreen_battle_default.tres`：离屏战斗按游戏小时结算战力/等级/骑乘/剩余生命与随机伤亡。
- `BattleMarker`：同一场 `BattleSession` 只显示一个战斗标记；战斗期间隐藏参战部队图标。
- `BattleSummaryPanel`：按 `side_index` 分组、同侧多部队并列、兵种/骑乘合并人数、伤亡实时刷新。
- `EventBus.battle_participants_updated`：每次离屏小时结算后通知 UI。
- 测试：`offscreen_battle_hourly_test`、`small_scene_camera_test`、`player_pursuit_encounter_test`、`world_map_battle_marker_test`。

### 变更

- 离屏战斗从“10 世界秒后一次性确定性结算”改为“每 1 游戏小时结算一次，最多 48 小时”；玩家加入保留已有伤亡与 HP，转换后不再进行离屏结算。
- `EncounterManager` 的遭遇意图增加玩家主动追击（`focus_party_id`）；同向移动目标也能在 50 世界单位内接触，接触后立即停止双方并清除旧目标，修复回弹/无法开战。
- 玩家遭遇面板新增“撤退”；撤退后恢复基础倍率并记录 90 世界单位拒绝锁，双方保留停止位置。
- 村庄摄像机从固定整图改为与战斗一致的跟随/自由视角；战斗摄像机保持 2 倍整数像素缩放。
- `battle_scene_test` 改为验证统一视野缩放；`player_control_test` 增加摄像机跟随与自由视角断言；`player_encounter_test` 更新为战斗/撤退两个选项。
- 未改变存档 Schema；摄像机、离屏计时、玩家追击焦点与战斗汇总均为运行时数据。

### 决策

- D078：村庄与战斗共用 `SceneCameraRig` 与统一视野。
- D079：离屏战斗按游戏小时结算伤亡。
- D080：玩家追击意图参与统一遭遇判定，遭遇面板提供撤退。
- D081：大地图同场战斗合并为一个标记与按战斗侧分组的汇总面板。

### 验证

- 新增测试全部通过：`offscreen_battle_hourly_test`、`small_scene_camera_test`、`player_pursuit_encounter_test`、`world_map_battle_marker_test`。
- 回归通过：`multi_party_battle_test`、`battle_result_test`、`ai_manager_test`、`battle_scene_test`、`player_control_test`、`player_encounter_test`、`player_battle_interaction_test`、`world_map_milestone6_test`、`world_map_input_test`、`party_dialogue_test`、`village_scene_test`、`village_flow_test`、`milestone2_flow_test`。
- 未执行非 headless 视觉截图与跨进程重启测试。
- 明确未实现：自由视角缩放/边缘拖动/手柄、伤兵/俘虏/士气、战斗标记点击详情与旁观模式。

---

## 2026-11-21 · 阶段 6 村庄场景、交互与部队管理

### 新增

- 村庄小场景 `Scenes/Village/village.tscn` + `Scripts/UI/Village/village_scene.gd`：玩家复用 `UnitData`/`UnitVisual`，村庄头人、距离交互、屏幕下方对话、5 秒越界倒计时与返回大地图。
- `SettlementData.scene_path`：村庄关联小场景；大地图地点面板增加“进入村庄”。
- `WorldMap.enter_village()`、`GameManager.current_settlement_id` / `pending_settlement_latch_id` / `small_scene_return_base_speed`：进入/返回及一次性地点交互锁。
- `UnitVisual.set_weapon_visible()` / `HumanVisual.set_weapon_visible()`：村庄仅隐藏武器表现，不修改装备数据。
- `DialogueData` + `DialogueManager` 数据驱动会话；`Data/Dialogues/village_elder.tres`。
- `PartyData.focus_party_id`：玩家追逐焦点；追逐中跳过村庄/无关部队/离屏战斗自动交互，敌对 AI 主动追击仍可遭遇。
- `PartyIcon` 只显示人数；`PartyHoverPanel` 显示部队名称与兵种/骑乘合并构成，不拦截地图操作。
- `ItemConfig` + `ItemManager`（`Data/Items/`）；晋升凭证 `promotion_rank_token`。
- `PlayerProfile.can_afford()` / `spend_gold()`；`PartyManager.get_total_wage()`。
- `UnitConfig.tier` / `daily_wage` / `promotion_*`；`UnitData.wage`；`UnitManager.promote_tier()`。
- 三级兵种配置：民兵 10/50、职业步兵 20/100、新增小贵族 25/180；工资 2/5/10。
- 部队面板：金币/工资、tier、坐骑下拉与装备/卸下、晋升按钮。
- 世界日历：1103-01-01 起点、6 秒 = 1 小时、144 秒 = 1 天、30 天/月、12 月/年、时间段；大地图显示年月日 + 时间段。
- 测试：`unit_tier_wage_test`、`time_calendar_test`、`village_scene_test`、`village_flow_test`、`world_map_milestone6_test`、`party_economy_ui_test`。

### 变更

- 新游戏玩家部队仍为 7 人；测试马匹库存 3 → 4（1 匹留在背包）；新增 2 个晋升凭证测试库存。
- 大地图地点自动交互在玩家追逐目标时跳过；返回村庄后使用一次性锁避免立即重开。
- 大地图时间 UI 从“第 N 天 HH:MM:SS”改为“年月日 + 时间段”。
- 部队图标去掉名称标签，只显示人数；悬浮面板负责简要构成。
- 三级基础属性调整导致 `unit_manager_test`、`stat_calculator_test`、`unit_party_serialization_test`、`mounted_unit_test`、`battle_result_test`、`party_panel_test`、`combat_attack_rules_test`、`unit_controller_test`、`battle_manager_test` 的预期数值同步更新。
- 未改变存档 Schema；`wage` / `scene_path` / `inventory_counts` 均为带安全默认值的增量字段。

### 决策

- D071：三级兵种与经验等级分离，工资绑定兵种等级。
- D072：晋升通过配置链路 + 消耗品，保留等级/经验/装备。
- D073：玩家追逐焦点抑制无关自动交互。
- D074：村庄作为只读小场景，进入/返回使用暂停栈与一次性交互锁。
- D075：世界日历由累计秒数换算，采用 30 天简化历法。
- D076：部队图标只显示人数，悬浮面板负责详情。
- D077：新游戏测试库存调整为 4 匹马与 2 个晋升凭证。

### 验证

- 新增测试全部通过：`unit_tier_wage_test`、`time_calendar_test`、`village_scene_test`、`village_flow_test`、`world_map_milestone6_test`、`party_economy_ui_test`。
- 回归通过：`unit_manager_test`、`stat_calculator_test`、`unit_party_serialization_test`、`mounted_unit_test`、`battle_result_test`、`party_panel_test`、`combat_attack_rules_test`、`unit_controller_test`、`battle_manager_test`、`battle_scene_test`、`player_control_test`、`battle_formation_test`、`battle_side_result_test`、`battle_retreat_test`、`ai_manager_test`、`faction_vision_test`、`multi_party_battle_test`、`party_dialogue_test`、`player_encounter_test`、`player_battle_interaction_test`、`ai_encounter_flow_test`、`world_map_input_test`、`milestone2_flow_test`、`skeleton_smoke_test`、`milestone1_test`、`milestone1_flow_test`、`main_menu_ui_test`。
- 未执行非 headless 村庄截图与跨进程重启测试。
- 明确未实现：村庄商店/招募/任务/好感度、城镇/城堡小场景、工资扣除、完整背包 UI、复杂对话树、正式美术。

---

## 2026-11-21 · 骑兵动画幅度调整与影子优化

### 变更

- 马腿局部动作：前后伸展 `0.25 → 0.6 px`、旋转 `0.01 → 0.02 rad`、上下位移保持 `0 px`；前/后腿组关系与 `0.12 rad` 错位不变。
- 骑兵整体跑动起伏：`RUN_BOB_AMPLITUDE 5.6 → 4.2`；马身俯仰、拉伸/压缩、骑手跟随与腿部挂载关系不变。
- 骑马影子：新增基于马身垂直偏移的平滑响应；抬高时最多缩小 `4%`、变淡 `15%`，回落时恢复；位置、资源与层级不变。
- 人物腿部局部参数、人物/马腿 Pivot、战斗规则、单位属性与存档均未修改。

### 验证

- 自动化通过：`unit_visual_test`、`mounted_unit_test`、`party_panel_test`。
- 新增断言：骑兵整体起伏上限降低；马腿局部伸展 ≥ `0.45 px`；影子抬高时缩小/变淡、回落恢复；影子位置不变。
- 非 headless：`locomotion/run_1..4` / `idle`、`visual_probe_party_foot*` / `mounted*` 重新渲染检查。

---

## 2026-11-21 · 人马腿部挂载关系与局部动画优化

### 变更

- 人物双腿从 `HumanVisual` 直接子节点改为 `UpperBody` 的子节点；马腿从 `HorseVisual` 直接子节点改为 `HorseBodyRig` 的子节点。
- 两个父节点 `z_index = 0`，`VisualLayers` 的最终遮挡关系保持不变；影子仍不参与身体变换。
- 每帧先设置父级整体变换，再设置腿部局部变换；不做 Transform 累加。
- 人物腿部旋转中心：实际历史为 3 px，本轮再 +3 px → `LEG_PIVOT_DROP_Y = 6.0`。
- 马腿旋转中心：实际历史为 6 px，本轮再 +3 px → `LEG_PIVOT_DROP_Y = 9.0`。
- 人物局部步态：`0.2 px / 0 px / 0.005 rad`。
- 马腿局部动作：前后伸展 `0.25 px`、旋转 `0.01 rad`、上下位移 `0 px`；前/后组关系与 `0.12 rad` 错位保留。
- 腿部挂载调整不改变人物/马匹其他锚点、骑手跟随、攻击动画或 UI 预览架构。

### 验证

- 自动化通过：`unit_visual_test`、`mounted_unit_test`、`party_panel_test`。
- 新增断言：人物双腿父节点为 `UpperBody`、马腿父节点为 `HorseBodyRig`；人物/马腿 global position 随身体整体运动；枢轴 6/9 px 与可见位置不变；局部摆幅上限。
- 非 headless：`locomotion/run_1..4` / `idle`、`visual_probe_party_foot*` / `mounted*` 重新渲染。
- 未改变存档 Schema、战斗规则、单位属性、装备或部件层级。

---

## 2026-11-21 · 人马腿部动画幅度与战马整体跃动优化

### 变更

- 马腿旋转中心：`HorseVisual.LEG_PIVOT_DROP_Y 3.0 → 6.0`（累计，含上一轮 3 px）；`offset.y` 与基础位置按 6 px 补偿，可见位置不变。
- 马腿幅度：前后伸展 `3.5 → 1.5 px`、旋转 `0.09 → 0.04 rad`、上下位移 `0.25 → 0.10 px`；组内 `0.12 rad` 错位保留。
- 马身整体跃动：跑动起伏 `4.5 → 5.6`（约 +24%），伸展阶段向上、收缩阶段向下；俯仰 `0.022 → 0.028 rad`，横向拉伸 `2% → 2.8%`，纵向压缩 `0.8% → 1.2%`。
- 马头：独立摆动 `0.05 → 0.04 rad`、独立起伏 `0.8 → 0.55 px`。
- 骑手跟随：`UnitVisual` 先更新马匹，再把 `get_body_offset_y()` 传给 `HumanVisual`；骑乘人物整体 y = -15 + 马身偏移，上半身独立起伏缩为 20%。
- 步兵腿部：`RUN_LEG_SWING_X 1.5 → 0.8`、`RUN_LEG_LIFT_Y 0.6 → 0.25`、`RUN_LEG_ROTATION 0.04 → 0.02`。

### 验证

- 自动化通过：`unit_visual_test`、`mounted_unit_test`、`party_panel_test`。
- 新增断言：马腿枢轴 6 px 与可见位置不变；骑手跟随马身、同步误差 `< 0.001`；骑手上半身独立起伏不超过 `0.6 px`；UI 骑兵预览骑手跟随。
- 非 headless：`locomotion/run_1..4` / `idle`、`visual_probe_party_foot*` / `mounted*` 重新渲染检查。
- 未改变存档 Schema、战斗规则、单位属性、装备或部件层级。

---

## 2026-11-21 · 人物与战马腿部旋转中心修正

### 变更

- `PartVisual` 新增 `lower_part_pivot(part_name, drop_y)`：`offset.y -= drop_y`、`position.y += drop_y`，使旋转中心在素材坐标中下移而贴图可见位置不变。
- 人物左右腿：`LEG_PIVOT_DROP_Y = 3.0`，`LEG_REST_POSITION = (0, 3)`；左右腿使用相同规则。
- 四条马腿：`LEG_PIVOT_DROP_Y = 3.0`，全部腿使用相同规则；`_apply_leg_pose()` 以 y=3 作为动画基准。
- 未修改腿部动画幅度、周期、相位、马腿前后分组、伸展距离、旋转角度、上下位移、其他部件锚点、层级或骑乘偏移。

### 验证

- `unit_visual_test`：新增人物左右腿与四条马腿的枢轴断言，验证基础位置补偿 3 px、贴图可见位置不变、`offset.y` 下移 3 px。
- `party_panel_test`：通过，部队 UI 步兵/骑兵预览动画正常。
- 非 headless：`locomotion/run_1..4` / `idle`、`visual_probe_party_foot*` / `mounted*` 重新渲染。
- 未改变存档 Schema、战斗规则或单位属性。

---

## 2026-11-21 · 士兵待机与战斗动作表现二次优化

### 新增

- 部队 UI 预览待机动画：`UnitDetailPanel._process()` 复用 `UnitVisual.update_locomotion(delta, false)`；步兵播放人物待机，骑兵播放马匹/骑手待机；面板不可见时不推进，切换单位时 `reset_locomotion()`。
- 步兵待机头部独立微摆 `IDLE_HEAD_SWAY = 0.015`（跑动 `0.006`）。
- 战马跃马式四肢：两只前腿成组前伸、两只后腿成组后伸，随后同步收缩；组内错位 `0.12 rad`。
- 长矛方向性前摇/戳击：前摇沿攻击反方向后移 `2.5 px`，戳击沿攻击方向前伸 `6.0 px`；保持/恢复沿用 4 秒/0.35 秒。

### 变更

- 步兵腿部振幅：`RUN_LEG_SWING_X 4.0→1.5`、`RUN_LEG_LIFT_Y 1.8→0.6`、`RUN_LEG_ROTATION 0.10→0.04`；等幅反相关系不变。
- 马腿不再使用 0 / π / π/2 / 3π/2 的独立正弦；改为前腿组/后腿组相反相位，前后伸展 `3.5 px`、旋转 `0.09 rad`、上下位移 `0.25 px`。
- 马身增加伸展/收缩：跑动起伏 `4.5`、俯仰 `0.022 rad`、横向拉伸 `2%`、纵向压缩 `0.8%`。
- 长矛时间：前摇 `0.10→0.14s`、戳击 `0.12→0.14s`；戳击阶段从旋转保持改为位置前伸，保持阶段同时维持角度与位置。
- 伤害仍即时结算；没有将伤害延后到戳击阶段。

### 决策

- D067：待机动画复用、跃马式马腿与长矛前后摇。

### 验证

- 自动化通过：`unit_visual_test`、`combat_attack_rules_test`、`unit_controller_test`、`battle_scene_test`、`party_panel_test`、`player_control_test`、`mounted_unit_test`。
- 非 headless：`locomotion/run_1..4` / `idle`、`visual_probe_attack_windup/thrust/hold/recover`、`visual_probe_party_foot*` / `mounted*`。
- 未改变存档 Schema、战斗规则、单位属性或装备数据。

---

## 2026-11-21 · 战斗动作表现与攻击操作体验优化

### 新增

- 玩家自由攻击：左键在无敌人/空白处也会播放完整长矛动画并进入冷却，有有效目标时才结算伤害；`player_attack_at()` 返回值改为“攻击动作是否释放”。
- 长矛攻击后保持 `4.0s`（`SPEAR_POST_ATTACK_HOLD_TIME`，可按 3–5 秒配置），再以 `0.35s` 平滑恢复；连续攻击立即重新开始并重置保持时间。
- 骑乘战斗速度系数 `BATTLE_MOUNTED_MOVE_SPEED_MULTIPLIER = 0.84`：民兵 85→71.4、职业步兵 80→67.2、玩家角色 100→84；步兵仍为 0.6，大地图速度不变。
- `is_attack_pose_locked()`：只有旋转准备/戳击阶段锁定朝向，保持/恢复阶段允许移动与转身。
- `Tests/_debug/locomotion_probe`：5 倍比例输出步兵/骑兵跑步四相位与待机截图，用于人工检查动画。

### 变更

- 步兵双腿：改为等幅反相水平步态（`RUN_LEG_SWING_X=4.0`、`RUN_LEG_LIFT_Y=1.8`、`RUN_LEG_ROTATION=0.10`）；前摆腿抬起、后摆腿接地，待机平滑复位。
- 马匹：跑动身体起伏 `2.8→4.5`、周期 `0.48→0.50` 与人物同步；新增俯仰 `0.022 rad` 与压缩/伸展 `0.018`；马腿上下位移 `2.2→0.55`，改为水平 `1.8 px` + 旋转 `0.06 rad`；待机马腿位移降至 `0.10 px`。
- 初始部署边距 `SPAWN_MARGIN_X 220→160`，双方质心间距约 `786→906`；不改变队形结构与 Party Lane。
- `_unhandled_input` 不再拒绝战场边界外的鼠标点击，边界外点击按鼠标方向空挥。
- 玩家攻击动画期间朝向锁定缩小到挥动/刺出阶段。

### 决策

- D062：玩家攻击动作与命中判定解耦（自由攻击）。
- D063：长矛攻击后保持姿态并延迟恢复。
- D064：动画由马身整体动态与协调步态驱动。
- D065：骑乘战斗速度使用独立系数。
- D066：初始部署边距进一步缩短到 160。

### 验证

- 自动化通过：`unit_visual_test`、`combat_attack_rules_test`、`unit_controller_test`、`battle_scene_test`、`battle_formation_test`、`player_control_test`、`mounted_unit_test`。
- 非 headless 截图：`visual_probe_close/move/hold/recover/attack_left/attack_up/attack_down/legs_only`；`locomotion/run_1..4` 与 `idle`。
- 未改变存档 Schema；未修改 UnitConfig、坐骑装备加成、战斗结算或大地图速度。

---

## 2026-11-21 · 战斗移动、动画、实体碰撞与 360°攻击优化

### 新增

- 步兵/骑兵待机与移动动画：人物上半身起伏/倾斜、武器摇摆、双腿交替；马身/马头/四条马腿独立动画；影子稳定；实际位移驱动 + 0.12s 缓冲 + 0.18s 混合。
- 360°定向矩形攻击：鼠标/目标方向、旋转矩形、背后/横向/长度外排除、单次单目标。
- 武器攻击距离：`EquipmentConfig.weapon_attack_range`；`weapon_sword_01` 设为 14，默认长矛使用 UnitConfig。
- 实体碰撞：`MIN_BODY_DISTANCE=28` 的最小间距推开，与局部避让协同。
- 战斗移动速度系数 `0.6`；初始部署边距 `220`。
- 项目显示 1920×1080；战斗相机 2 倍整数缩放、向下偏移 30；大地图相机默认 1.5 倍。
- 玩家攻击方向来自鼠标世界坐标；攻击方向/目标锁定，武器动画与伤害同向。
- 测试：定向矩形、玩家四方向、武器距离、碰撞、待机/跑动/马匹动画、部署/相机/分辨率。

### 变更

- `VisualLayers`：四条马腿移到马身体之前（马鞍 -69、马腿 -71、马身 -72、人左腿 -80）。
- `HumanVisual` 拆出 `UpperBody`；`HorseVisual` 拆出 `HorseBodyRig`；四腿各自运动。
- 长矛动画从固定横向戳击升级为任意方向旋转；朝右由整体镜像保持矛尖方向。
- 玩家/AI 共用 `CombatRules` 矩形判定与 `UnitActor.play_attack(direction)`。
- 战斗移动速度：民兵 36 / 职业步兵 33 / 玩家角色 45；骑乘 51/48/60。大地图速度不变。
- 攻击动画与伤害独立：无有效目标不耗冷却/不播有效攻击；命中时两者同向。
- 显示：Viewport/窗口 1920×1080，Stretch 关闭；UI 原生 1920 布局。

### 决策

- D057：四条马腿显示在马身体之前。
- D058：待机/移动动画由实际位移驱动，人物/马匹 rig 分离，影子稳定。
- D059：战斗降速、部署距离与 1920×1080 显示方案。
- D060：武器攻击距离 + 360°定向矩形 + 单次单目标。
- D061：实体碰撞采用最小间距推开 + 局部避让。

### 验证

- 自动化通过：`unit_visual_test`、`combat_attack_rules_test`、`unit_controller_test`、`stat_calculator_test`、`mounted_unit_test`、`unit_manager_test`、`unit_party_serialization_test`、`battle_manager_test`、`formation_manager_test`、`battle_scene_test`、`battle_formation_test`、`player_control_test`、`party_panel_test`、`milestone2_flow_test`、`party_dialogue_test`、`player_character_data_test`、`battle_retreat_test`、`battle_side_result_test`、`ai_encounter_flow_test`、`ai_manager_test`、`faction_vision_test`、`player_encounter_test`、`player_battle_interaction_test`、`world_map_input_test`、`skeleton_smoke_test`、`milestone1_test`。
- 非 headless 实际截图：战斗/近距离、左右/上下攻击、恢复、主菜单、部队面板、结果面板；1920×1080 无裁切，士兵 2 倍整数像素放大。
- 未改变存档 Schema；未修改 BattleResult/经验/奖励/马匹库存规则。

---

## 2026-11-21 · 士兵层级、长矛动画与部队预览优化

### 新增

- `PartVisual`：通用部件贴图/Sprite2D 管理、整体朝向、缺失素材一次性警告。
- `HumanVisual`：人物影子、双腿、身体、罩袍、头部、缨饰、长矛枢轴与攻击动画。
- `HorseVisual`：骑马影子、四条独立马腿、马身、马鞍、马头。
- `VisualLayers`：跨人物/马匹组的最终 z 层级集中配置。
- 长矛四阶段动画：旋转准备 0.10s、戳击保持 0.12s、攻击后延迟 0.20s、恢复 0.20s；攻击角度 `-PI/2`。
- `UnitDetailPanel` 美术预览：独立 `SubViewport`，复用 `UnitVisual`，按真实 UnitData 显示步兵/骑兵外观。
- 玩家部队新增 2 名骑乘测试士兵（共 3 名骑乘职业步兵；玩家部队 7 人）。
- 测试：`unit_visual_test` 扩展；`party_panel_test` 增加预览；多个系统测试更新为 7 人/12 人计数。

### 变更

- 最终层级：武器 → 马头 → 缨饰 → 人头 → 人身体/罩袍 → 人右腿 → 马鞍/马身 → 人左腿 → 四条马腿 → 影子。
- 人物与马匹分组管理；人体双腿始终创建，马身/马鞍按层级自然遮挡。
- 骑乘时人物整体上移 15 像素；马匹与 UnitActor 世界坐标不变。
- 人物影子/骑马影子互斥；四条马腿为独立 Sprite2D。
- 长矛枢轴：48×96 素材左下角 `(24,18)`；身体锚点 `(33,18)` 映射到当前 48×96 画布 `(9,-14)`。
- 朝右时使用人物/马匹整体镜像，长矛动画指向目标；伤害仍即时结算。
- 新游戏马匹库存改为 3，全部由 3 名职业步兵装备，库存剩 0。

### 决策

- D052：人物/马匹分组 + VisualLayers 最终层级。
- D053：骑乘人物整体上移 15 像素。
- D054：长矛独立枢轴与四阶段动画。
- D055：SubViewport 部队预览复用 UnitVisual。
- D056：玩家部队 3 名骑乘测试单位。

### 验证

- 自动化测试通过：`unit_visual_test`、`combat_attack_rules_test`、`mounted_unit_test`、`unit_controller_test`、`battle_scene_test`、`battle_formation_test`、`player_control_test`、`party_panel_test`、`player_character_data_test`、`milestone2_flow_test`、`party_dialogue_test`、`battle_retreat_test`、`battle_side_result_test`、`ai_encounter_flow_test`、`unit_manager_test`、`unit_party_serialization_test`、`battle_manager_test`、`ai_manager_test`、`faction_vision_test`、`player_encounter_test`、`player_battle_interaction_test`、`world_map_input_test`、`skeleton_smoke_test`、`milestone1_test`。
- 非 headless 实际截图检查：
  - `visual_probe_battle/close/move/attack/attack_left/recover/legs_only`：层级、朝向、骑乘偏移、长矛横向戳击/恢复。
  - `visual_probe_party_foot/mounted`：部队详情步兵/骑兵预览。
- 未执行主菜单 UI 与跨进程重启测试（本次未触及）。
- 未改变存档 Schema；玩家部队成员数变化会随存档正常保存/读取。

---

## 2026-11-21 · 士兵美术显示与骑乘层级修复

### 根因

- `UnitVisual` 的 Sprite2D 使用相对负 `z_index`（-100～-8），而 `UnitActor.z_index` 为 0。
- `BattleScene._draw()` 在根节点 z=0 绘制整张战场背景，导致所有士兵部件落到背景之后被完全覆盖。
- `UnitActor._draw()` 的血条、名称（子节点）与选中圈在 z=0 之上，因此出现“只有 UI、没有士兵本体”的现象。
- 实际非 headless 渲染截图已复现并确认；提升 `UnitActor.z_index` 后恢复。

### 修复

- `UnitActor` 新增 `ACTOR_Z_INDEX = 200`；部件实际 canvas z = `200 + 部件相对 z`，全部高于背景。
- `UnitVisual` 层级集中配置；人体双腿始终创建，不再因骑乘状态隐藏。
- 骑乘层级调整为：影子 → 马腿 → 人体双腿 → 马身 → 马头 → 马鞍 → 身体 → 罩袍 → 武器 → 头部 → 缨饰；马身/马鞍自然遮挡人体双腿。
- 部件 Sprite2D 固定最近邻采样，像素画缩放保持清晰。
- 增加一次性资源加载失败日志（同一部件/路径只警告一次）；单个部件失败只跳过该部件。

### 验证

- 实际运行 `Tests/_debug/visual_probe.tscn`（非 headless）并检查截图：
  - 普通步兵、骑乘士兵、玩家角色均显示身体/头部/武器/影子/血条/名称/选中圈。
  - 骑乘单位保留人体双腿；隐藏马匹部件时双腿完整显示，证明没有被主动隐藏。
  - 玩家向右移动 23.75 像素，部件保持跟随；`Body` / `Head` 的 `flip_h = true`。
  - 玩家攻击命中，武器进入攻击闪光。
  - 不同阵营罩袍着色生效（玩家蓝色、商队金色），黑色描边与白色十字保留。
- 自动化测试通过：`unit_visual_test`、`battle_scene_test`、`unit_controller_test`、`mounted_unit_test`、`battle_formation_test`。
- 新增回归检查：`battle_scene_test` 验证每个士兵的身体/头部已加载、部件实际 z 高于背景、骑乘单位同时具有马匹部件与人体双腿。
- 未重复执行存档、战斗结算和大地图全量回归。

### 决策与问题

- D051：UnitActor 必须高于战场背景；人体双腿始终存在，马匹通过层级自然遮挡。
- KI358（士兵贴图完全不可见）与 KI359（骑乘隐藏人腿）已解决。
- KI349（独立缨饰/独立罩袍贴图缺失）仍保留；本次未虚构素材。

---

## 2026-11-21 · 阶段 5 后续优化：攻击判定、临时美术与骑兵系统

### 新增

- `CombatRules`：玩家与 AI 共用的攻击有效性入口（存活/敌对/冷却/射程）。
- `UnitVisual`：基于 `art/我的骑砍临时美术/` 实际 PNG 的可组合部件表现；步行/骑乘切换、阵营罩袍层、朝向翻转、攻击闪光与缺失素材回退。
- `Shaders/faction_tabard.gdshader`：临时阵营罩袍着色（只替换身体贴图的蓝色罩袍区域）。
- `UnitController.AIState`：SEEK / APPROACH / ATTACK；外围进攻点与目标失效重新索敌。
- `UnitManager.equip_mount()` / `unequip_mount()`：马匹库存消耗与返还。
- `PlayerProfile.get_item_count()` / `add_item(id, count)` / `remove_item(id, count)` 与 `inventory_counts`。
- `StatCalculator.compute_move_attack_bonus()` / `compute_effective_attack()`：骑乘移动攻击加成。
- 测试：`combat_attack_rules_test`、`mounted_unit_test`、`unit_visual_test`。

### 变更

- 攻击冷却、目标与移动状态明确属于攻击者；移除目标级攻击锁/受击阻塞，多名单位可同时攻击同一目标。
- 玩家左键攻击没有有效目标时不再消耗冷却、不播放攻击动作。
- 攻击距离统一为 `UnitData.attack_range + 2 × BODY_RADIUS`；玩家与 AI 不再分别硬编码。
- AI 在射程外继续接近，进入射程后停止移动并攻击；目标离开射程后重新追击。
- 新游戏玩家部队：3 民兵 + 1 名装备马匹的职业步兵 + 1 玩家角色（仍为 5 人）；测试马匹库存 2，消耗 1。
- `is_mounted` 改为 MOUNT 装备的派生状态；`UnitConfig.is_mounted` 仅保留兼容提示。
- 骑乘队形间距从 34 加宽到 46；局部避让半径调整为 38。
- 玩家角色与普通士兵共用 `UnitVisual` 部件架构。
- 部队面板/控制权转移列表显示“骑乘”。

### 决策

- D045：攻击冷却属于攻击者，允许多人围攻。
- D046：玩家与 AI 共用统一攻击有效性。
- D047：骑兵是 MOUNT 装备状态，不是独立兵种 ID。
- D048：骑乘属性由 StatCalculator 统一计算。
- D049：部件化临时美术与阵营罩袍着色。
- D050：物品数量采用增量字段兼容旧存档。

### 验证

- 实际执行并通过：`combat_attack_rules_test`、`mounted_unit_test`、`unit_visual_test`、`unit_controller_test`、`stat_calculator_test`、`unit_manager_test`、`unit_party_serialization_test`、`player_character_data_test`、`party_panel_test`、`battle_scene_test`、`player_control_test`、`battle_formation_test`、`milestone2_flow_test`、`battle_result_test`、`multi_party_battle_test`、`battle_retreat_test`、`battle_side_result_test`、`ai_manager_test`、`faction_vision_test`、`party_manager_test`、`formation_manager_test`、`battle_manager_test`、`milestone1_test`、`skeleton_smoke_test`。
- 未执行主菜单 UI、大地图输入/对话/遭遇交互与 Milestone 1 跨进程重启测试（本次未触及这些路径）。
- 未升级存档 Schema；旧存档缺少 MOUNT/`inventory_counts` 时按步兵与 1 件物品兼容。
- `art/` 没有独立缨饰与独立罩袍贴图；已记录 KI349，罩袍暂用身体贴图蓝色区域着色。
- 项目没有独立 `Equipment_System.md`；装备与马匹规则更新在 `Docs/Systems/Unit_System.md`，未新建重复文档。

---

## 2026-11-21 · 阶段 5 战斗结算与战后处理

### 新增

- `BattleResultData`：统一战斗结果（胜负/失败/撤退侧、参战快照、伤亡/存活、经验、金币/战利品、结束原因、finalized）。
- `PlayerProfile`：金币与物品栏，存于 `player` 字典。
- `Data/Units/player_hero.tres` 与 `UnitConfig/UnitData.is_player_character`。
- 玩家角色控制：WASD、斜向归一化、鼠标左键攻击、攻击冷却、金色控制圈与攻击闪光。
- 控制权转移面板：接管存活友军或观战；场景本地暂停。
- `FormationManager`：横向/纵深/松散/方阵站位。
- `BattleScene` 队形槽位、party lane、周期邻居缓存；`UnitController` 局部避让。
- 玩家侧撤退按钮与 `RETREATED` 结果。
- 战后经验/金币/装备战利品结算。
- 结果面板：多侧名称、伤亡/存活、经验、金币/战利品。
- 测试：`formation_manager_test`、`battle_result_test`、`player_character_data_test`、`player_control_test`、`battle_formation_test`、`battle_side_result_test`、`battle_retreat_test`。

### 变更

- 新游戏玩家部队：3 民兵 + 1 职业步兵 + 1 玩家角色（共 5 人）。
- `BattleManager.finish_battle()` 先生成/应用经验与奖励，再写回 HP、移除阵亡、解锁部队。
- 屏幕/离屏/中途加入共用同一结算入口；同一战斗只结算一次。
- `BattleScene` 按战斗侧统计存活；一支部队全灭但同侧仍有友军时继续。
- 玩家角色被击败只影响当前控制，不直接判负；可接管或观战。
- 玩家输入只控制单个单位；旧 `command_player_units()` 保留为调试入口。
- 玩家档案金币/物品与玩家角色身份进入存档；未升级 Schema。
- 结果面板显示预览；点击返回大地图时执行最终结算。

### 决策

- D041：玩家角色是普通 Unit，控制权与身份分离。
- D042：部队槽位 + 单位局部避让。
- D043：统一 BattleResultData 与战后结算。
- D044：玩家档案与奖励写入 player 字典。

### 验证

- 实际执行并通过：`formation_manager_test`、`battle_result_test`、`player_character_data_test`、`player_control_test`、`battle_formation_test`、`battle_side_result_test`、`battle_retreat_test`、`unit_controller_test`、`battle_manager_test`、`battle_scene_test`、`milestone2_flow_test`、`party_panel_test`、`unit_party_serialization_test`、`unit_manager_test`、`stat_calculator_test`、`skeleton_smoke_test`、`milestone1_test`、`milestone1_flow_test`、`milestone1_restart_test`（save + load）、`ai_manager_test`、`ai_encounter_flow_test`、`player_encounter_test`、`player_battle_interaction_test`、`party_dialogue_test`、`world_map_input_test`、`faction_vision_test`、`multi_party_battle_test`。
- 未执行 `main_menu_ui_test`（本次未改主菜单）。
- 未改变存档 Schema；旧存档缺少 `is_player_character` / 玩家金币 / 物品时使用安全默认值。

---

## 2026-11-21 · 阶段 4 AI 遭遇与玩家中途参战交互完善

### 新增

- `EncounterManager`：统一负责 AI 遭遇判定、玩家中途参战检测、停止部队与战斗创建/加入委托。
- `EncounterManager.update_player_battle_interaction()`：玩家接近进行中的离屏战斗时生成交互请求。
- 交互距离常量：`AI_ENCOUNTER_RADIUS = 50`、`BATTLE_INTERACTION_RADIUS = 55`、`BATTLE_INTERACTION_EXIT_RADIUS = 90`。
- `EventBus.player_battle_interaction_requested(interaction_id, battle_id)`。
- `GameManager.PAUSE_REASON_BATTLE_INTERACTION = &"battle_encounter_dialogue"`。
- WorldMap `BattleInteractionPanel`：显示交战方与持续时间，提供“加入战斗/离开”。
- `EncounterManager.decline_battle_interaction()` 与拒绝记录，避免离开后原地重复弹窗。
- 测试：`player_battle_interaction_test`。

### 变更

- 原先 `WorldMapManager` 中的遭遇检测迁移到 `EncounterManager`；WorldMapManager 只保留移动、跟随与边界。
- `WorldSimulation` 顺序为移动 → 统一遭遇 → 玩家中途参战检测 → AI；存在待处理交互时跳过该 tick 的 AI。
- 移除玩家接近离屏战斗时自动加入的逻辑，改为先暂停并弹出加入/离开面板。
- 加入：`try_join_battle()` 加入已有 BattleSession，不创建重复战斗；离开：NPC 战斗继续，玩家停在原地。
- `ai_encounter_flow_test` 更新为：接近离屏战斗先看到交互面板，点击“加入战斗”后进入已有战斗。
- 战斗结束、战斗 ID 变化、玩家已参战或异常关闭时自动关闭面板并清理 `battle_encounter_dialogue`。
- 不改变存档 Schema；攻击意图、交互 ID 与拒绝记录均为运行时状态。

### 决策

- D040：新增 `EncounterManager`，区分强制遭遇与玩家中途参战；D038 的实现位置迁移到新管理器。

### 验证

- 实际执行并通过：`player_battle_interaction_test`、`ai_encounter_flow_test`、`ai_manager_test`、`faction_vision_test`、`multi_party_battle_test`、`world_map_input_test`、`player_encounter_test`、`battle_manager_test`、`battle_scene_test`、`party_dialogue_test`、`milestone2_flow_test`、`milestone1_test`、`skeleton_smoke_test`。
- 未执行 `unit_controller_test`、`main_menu_ui_test`。

---

## 2026-11-21 · 阶段 4 AI 遭遇行为优化

### 新增

- `PartyData.attack_intent`：运行时攻击/拦截意图，不进入存档。
- `WorldMapManager.update_encounters()`：统一大地图遭遇判定，距离 `AI_ENCOUNTER_RADIUS = 50`（后续迁移到 `EncounterManager`，见顶部条目）。
- `WorldMapManager` 待处理玩家遭遇（唯一 `encounter_id`）、`has_pending_player_encounter()` / `clear_pending_player_encounter()`。
- `EventBus.player_encounter_requested(encounter_id, attacker_party_id, target_party_id)`。
- `GameManager.PAUSE_REASON_ENCOUNTER_DIALOGUE = &"encounter_dialogue"`。
- WorldMap `PlayerEncounterPanel`：敌对部队名称、阵营、兵力、遭遇描述与唯一“战斗”按钮。
- `WorldMap.cancel_player_encounter()`：异常关闭时清理自身暂停与待处理遭遇。
- 测试：`player_encounter_test`；扩展 `ai_manager_test`、`world_map_input_test`。

### 变更

- 遭遇判定从 AIManager 的“距离 24 直接开战”改为 WorldMapManager 统一判定：
  - 双方有效、阵营敌对、距离 <= 50、至少一方攻击意图指向对方；
  - AI 对 AI 创建/加入离屏战斗；玩家被主动拦截进入遭遇对话。
- `WorldSimulation` 顺序为移动 → 遭遇 → AI；存在待处理玩家遭遇时跳过该 tick 的 AI。
- AI 不再直接为玩家目标创建屏幕战斗；改为遭遇对话后由玩家选择战斗。
- 强盗目标选择改为动态评分：商队 300 / 治安队 200 / 玩家 100 / 其他 50，减距离 ×0.1；切换阈值 30。
- 追逐玩家时若出现评分明显更高的商队，会重新评估并切换。
- NPC 速度：治安队 120、强盗 100、商队 80；玩家 150。旧存档速度不被重置。
- 战斗场景仍按战斗侧处理；遭遇对话不创建战斗，直到玩家选择“战斗”。

### 决策

- D038：大地图遭遇由 `WorldMapManager` 统一判定，AI 只维护攻击意图。
- D039：强盗动态目标评分、切换阈值与玩家遭遇对话。

### 验证

- 实际执行并通过：`ai_manager_test`、`ai_encounter_flow_test`、`faction_vision_test`、`multi_party_battle_test`、`world_map_input_test`、`player_encounter_test`、`battle_manager_test`、`battle_scene_test`、`party_dialogue_test`、`milestone2_flow_test`、`milestone1_test`。
- 实现阶段另验证：`party_panel_test`、`stat_calculator_test`、`unit_manager_test`、`party_manager_test`、`unit_party_serialization_test`、`skeleton_smoke_test`、`milestone1_flow_test`、`milestone1_restart_test`（save + load）。
- 未执行 `unit_controller_test`、`main_menu_ui_test`。
- 未改变存档 Schema；攻击意图与遭遇状态为临时运行时数据。

---

## 2026-11-21 · 阶段 4 大地图阵营生态与动态遭遇

### 新增

- `FactionManager`：玩家 / 商队 / 强盗 / 治安队 / 本地势力注册与友好/中立/敌对查询。
- `VisionManager`：距离视野、可见部队列表、敌对/友方/中立筛选、最近敌对目标、`can_see()`。
- `PartyAIType.BANDIT` / `GUARD`；`OrderType.FOLLOW_PARTY`。
- “山道强盗”测试部队与强盗游荡路线。
- 强盗 AI：目标优先级、持续追击、失去视野后清除目标并恢复游荡。
- 治安队 AI：优先拦截威胁商队的强盗、恢复巡逻、响应附近战斗。
- `BattleParticipant` 与多战斗侧数据结构；`BattleSession` 增加 `participants` / `side_*` / `winning_side_index` / `offscreen` / `paused_world` / `player_involved`。
- `BattleManager.start_battle_by_sides()`、`get_join_side()`、`try_join_battle()`、`tick()`、`resolve_current_battle_now()`。
- 离屏 AI 对 AI 自动结算（10 世界秒）与第三方中途加入。
- 玩家接近离屏战斗自动加入并进入 `BattleScene`；`battle_started` 信号自动切换场景（后续改为加入/离开面板，见顶部条目）。
- 玩家部队跟随移动目标（0.5 世界秒刷新）。
- `EventBus.battle_participant_joined`。
- 测试：`faction_vision_test`、`multi_party_battle_test`、`ai_encounter_flow_test`；扩展 `ai_manager_test`、`world_map_input_test`。

### 变更

- 商队、治安队速度 220 → 110；强盗 135；玩家保持 150。
- 新游戏阵营划分：玩家 / 河畔商队（商队）/ 北境巡逻队（治安队）/ 山道强盗（强盗）；地点仍为本地势力。
- 玩家点击移动中的有效部队进入跟随；静止部队仍为普通移动。
- 敌对部队不再弹出对话，由 AI 主动追击并触发战斗。
- `BattleScene` 按战斗侧生成单位与敌人列表，玩家输入作用于实际所在侧；结果按获胜侧显示。
- `BattleManager.finish_battle` 解锁全部参战部队；离屏战斗不压入/移除 `battle` 暂停。
- `WorldContext` 装配 `FactionManager` / `VisionManager`；`WorldSimulation` 每 tick 推进离屏战斗计时。

### 决策

- D035：阵营关系与视野查询集中到公共管理器。
- D036：多战斗侧、离屏自动结算与中途加入。
- D037：玩家跟随使用 `FOLLOW_PARTY` + 0.5 世界秒刷新。

### 验证

- 实际执行并通过：`faction_vision_test`、`ai_manager_test`、`multi_party_battle_test`、`ai_encounter_flow_test`、`world_map_input_test`、`party_dialogue_test`、`battle_manager_test`、`battle_scene_test`、`milestone2_flow_test`、`party_panel_test`、`stat_calculator_test`、`unit_manager_test`、`party_manager_test`、`unit_party_serialization_test`、`skeleton_smoke_test`、`milestone1_test`、`milestone1_flow_test`、`milestone1_restart_test`（save + load）。
- 未执行 `unit_controller_test`、`main_menu_ui_test`。
- 未改变存档 Schema；`ai_type` / `current_order` 仅扩展枚举值，`current_target_id` / `current_order` 继续保存跟随与追击状态。

---

## 2026-11-21 · 阶段 3 Step 3 士兵成长、装备属性与部队管理面板

### 新增

- `UnitConfig` 等级成长字段：`max_level` / `base_exp_to_next_level` / `exp_growth_per_level` / `hp_per_level` / `attack_per_level` / `move_speed_per_level` / `attack_range_per_level`；新增 `exp_to_next_level()`。
- `EquipmentConfig` 校验、槽位字符串映射、显示名与属性加成文本。
- `Data/Equipment/` 五个示例装备：铁剑、木盾、铁盔、皮甲、普通战马。
- `UnitManager` 配置注册/查询、`add_exp()`、`get_exp_to_next_level()`、`equip_item()`、`unequip_slot()`、`recalculate_stats()`、`recalculate_all_stats()`。
- 士兵独立名称：创建时生成“兵种名 + 两位编号”，名称随存档保存。
- `PartyPanel` / `PartyMemberItem` / `UnitDetailPanel`：大地图部队管理面板。
- 大地图顶部“部队”按钮。
- 测试：`party_panel_test`；扩展 `stat_calculator_test`、`unit_manager_test`、`unit_party_serialization_test`。

### 变更

- `StatCalculator` 从“复制兵种基础属性”升级为完整公式：基础值 + 等级成长 + 装备加成；`current_hp` 只做上限 clamp。
- `UnitManager.create_unit()` 复制并校验默认装备、初始化等级/经验、生成独立名称。
- `WorldContext._ready()` 扫描 `Data/Units` 与 `Data/Equipment` 注册静态配置；读档后调用 `recalculate_all_stats()`。
- 读档缺失名称时回填兵种模板名称；无效装备引用报告并清理。
- 部队管理面板打开时压入 `ui_panel` 暂停原因，关闭时只移除本面板原因；基础倍率保持不变。
- 大地图交互检测与输入屏蔽包含部队管理面板。
- 职业步兵成长参数高于民兵（每级 +6 HP / +2 攻击）。

### 决策

- D033：等级成长与装备加成统一由 `StatCalculator` 计算，配置注册在 `UnitManager`。
- D034：部队管理面板只读，使用 `ui_panel` 暂停原因栈。

### 验证

- 实际执行并通过：`stat_calculator_test`、`unit_manager_test`、`unit_party_serialization_test`、`party_panel_test`、`world_map_input_test`、`party_dialogue_test`、`milestone2_flow_test`、`milestone1_test`、`milestone1_restart_test`（save/load 两阶段）。
- 未改变存档 Schema；旧存档缺失等级/经验/装备/名称时使用安全默认值。
- 未执行无关的 `unit_controller_test` / `battle_scene_test` / `ai_manager_test`（本次未改其接口语义）。

---

## 2026-11-21 · 阶段 2 Step 2 NPC 自主巡逻与大地图输入优化

### 新增

- `PartyData.PartyAIType`：`NONE` / `TRADE_ROUTE` / `PATROL`。
- `PartyData.ai_type`、`ai_route_index`、`ai_route_settlement_ids`，参与序列化并兼容旧存档。
- `AIManager` 商队往返、巡逻循环、玩家/战斗/失效部队跳过。
- `ai_manager_test`：商队/巡逻循环、跳过规则、边界、AI 字段序列化。
- `world_map_input_test`：数字键、UI 屏蔽、点击切 1x、真实 tick 下 NPC 移动。

### 变更

- 河畔商队通过 stable `settlement_id` 在橡木村与河畔村之间循环。
- 北境巡逻队按四个固定点循环，`ai_route_index` 保存进度。
- 新游戏玩家速度从 300 调整为 150；NPC 保持 220。
- 顶部主键区 `1` / `2` / `3` 对应暂停 / 1x / 2x；小键盘与 echo 不触发。
- 玩家点击有效地图并成功设置目标后，基础倍率自动切为 1x。
- 保存面板、地点面板、部队对话打开时屏蔽快捷键与地图点击。
- 全员阵亡的部队在战斗结算后设为 `DISABLED`，停止 AI 与世界模拟。
- 时间按钮与快捷键统一走 `_set_world_speed()`。

### 决策

- D031：NPC 大地图 AI 状态存放在 `PartyData`；路线使用 stable ID。
- D032：时间快捷键与点击恢复 1x 只修改基础倍率，不清除暂停原因。

### 验证

- `ai_manager_test`、`world_map_input_test`、`party_dialogue_test` 通过。
- `unit_party_serialization_test`、`battle_manager_test`、`battle_scene_test`、`milestone2_flow_test`、`skeleton_smoke_test`、`milestone1_test`、`milestone1_flow_test` 回归通过。
- 未改变存档 Schema；旧存档缺失 AI 字段时默认为无 AI。

---

## 2026-11-20 · Milestone 2 Step 2 大地图遭遇与首次实战

### 新增

- `PartyDialoguePanel`：显示部队名称、阵营、兵力，提供离开/发起战斗。
- `Scenes/Battle/battle.tscn` 与 `BattleScene`：战场、士兵生成、玩家点击命令、结果面板。
- `UnitActor`：程序绘制士兵、阵营颜色、朝向、血条与名称。
- `UnitController`：自动索敌、移动、攻击、受伤、死亡与手动移动命令。
- `BattleSession` 新增双方 `unit_id` 列表与阵营字段。
- `WorldInitializer.create_test_battle_forces()`：玩家与河畔商队各 3 民兵 + 2 职业步兵。
- 测试：`unit_controller_test`、`battle_manager_test`、`party_dialogue_test`、`battle_scene_test`、`milestone2_flow_test`。

### 变更

- `BattleManager.start_battle()`：校验部队、阵营、可用性与存活士兵，生成 `BattleUnitState`，锁定部队并压入 `battle` 暂停。
- `BattleManager.finish_battle()`：写回存活 HP，移除阵亡单位并删除 `UnitData`，解锁部队，清理会话，防止重复结算。
- `GameManager` 新增 `PAUSE_REASON_BATTLE`；战斗期间 `save_game()` 返回 `ERR_BUSY`。
- 屏幕内战斗 WorldTime 改为 0（暂停原因栈），`set_battle_mode(0.5)` 保留给未来离屏战斗。
- 大地图新增部队遭遇检测与对话 UI；离开后恢复此前时间状态。
- `unit_party_serialization_test` 开始时清理新游戏预置的测试士兵。

### 决策

- D027：战斗会话、场景与结算职责分离。
- D028：屏幕内战斗暂停世界时间，替代 D008 的屏幕内 0.5 倍速方案。
- D029：阵亡单位移除归属并删除数据；存活单位写回剩余 HP。
- D030：初始测试兵力为临时调试配置，后续由招募系统替换。

### 验证

- Step 1 四个单元测试、`unit_controller_test`、`battle_manager_test`、`party_dialogue_test`、`battle_scene_test`、`milestone2_flow_test` 全部通过。
- `skeleton_smoke_test`、`milestone1_test`、`milestone1_flow_test` 回归通过。
- 未修改存档 Schema；测试存档已清理。

---

## 2026-11-20 · Milestone 2 Step 1 士兵数据层

### 新增

- `Data/Units/infantry_militia.tres`（民兵）与 `infantry_trained.tres`（职业步兵）兵种配置。
- `StatCalculator` 基础实现：`compute_final_stats()` / `apply_to_unit()` 统一初始化 `max_hp`、`attack`、`attack_interval`、`move_speed`、`attack_range`。
- `PartyManager.transfer_member()`：转队接口，与 `add_member()` 共用底层规则。
- `PartyManager.validate_membership_consistency()`：校验成员存在、部队存在、唯一归属与双向一致。
- `Tests/UnitTests/`：`unit_manager_test`、`party_manager_test`、`stat_calculator_test`、`unit_party_serialization_test`。

### 变更

- `UnitManager.create_unit()` 通过 `StatCalculator` 初始化属性，出生满血并清空归属。
- `UnitManager.remove_unit()`、`PartyManager.remove_party()` 改为返回 `bool`。
- `UnitManager.add_unit()` / `PartyManager.add_party()` 拒绝重复 ID，失败时原实体不变。
- `PartyManager.add_member()` 支持原子转队：先从所有其他部队移除，再写入目标部队；要求阵营一致。
- `remove_member()` 只清空归属，不删除 `UnitData`；`remove_party()` 清空成员归属并保留单位。
- `WorldContext.load_from_save_data()` 在两个仓储恢复后校验成员关系，失败时报告错误并拒绝加载。
- `load_from_dict()` 遇到重复实体 ID 时报错并跳过，不再静默覆盖。

### 修复

- 一个士兵可能同时存在于两支部队成员列表（D024）。
- 重复实体 ID 静默覆盖（D024）。
- 删除已归属士兵后产生悬空成员引用（D024）。
- 读档后缺少士兵-部队关系校验（D025）。

### 验证

- 4 个新增单元测试全部通过。
- `skeleton_smoke_test`、`milestone1_test` 回归通过。
- 未修改存档 Schema；测试存档已清理。

---

## 2026-11-20 · 测试范围控制规范

### 变更

- 引入 L1–L4 测试分级：局部、关联、集成、全量。
- 默认只运行验证本次修改的最小测试集；公共接口/核心数据/跨系统改动扩大范围；重大重构与里程碑才运行全量。
- 开发前必须说明改动文件、涉及系统、接口影响、将执行与不执行的测试；完成后汇报测试结果与未验证风险。
- 更新 `Docs/03_Design_Conventions.md`、`Docs/00_Project_Index.md`、`Docs/02_Development_Roadmap.md`。

---

## 2026-11-20 · V0.4 Milestone 1 完成

### 新增

- `WorldInitializer`：生成世界 ID、3000×2000 地图、玩家部队、2 支 NPC 部队、4 个地点。
- `SettlementManager`：地点仓储、创建、查询、序列化，接入 `WorldContext`。
- `SaveData` Schema v2：世界 ID、创建时间、世界尺寸、玩家部队 ID。
- `SaveManager`：临时文件 + 校验 + `.bak` 备份替换；存档头、列表、最近有效存档。
- `WorldContext.to_save_data()` / `load_from_save_data()`。
- `GameManager.save_game()` / `continue_game()` / 完整读档流程。
- `TimeManager.get_base_world_speed()` / `restore_world_time()`。
- 大地图场景：草地/道路/河流背景、部队/地点图标、摄像机跟随/平移/缩放。
- 主菜单：新游戏、继续、读取列表、设置占位、退出。
- 大地图 UI：世界时间、暂停/1x/2x、玩家坐标、保存面板、返回主菜单。
- 地点交互：40 像素触发、线段检测、到达停止、暂停、离开仍暂停。
- `UiTheme`：中文字体主题，覆盖 UI 与地图图标标签。
- 测试：`milestone1_test.tscn`、`milestone1_flow_test.tscn`、`main_menu_ui_test.tscn`、`milestone1_restart_test.tscn`（跨进程存档）。

### 变更

- `WorldMapManager.update_party_movement()` 实现直线移动、到达判定、边界 clamp。
- `PartyIcon` / `SettlementIcon` / `MapBackground` 程序绘制表现。
- 主菜单与大地图 UI 改为程序化构建，关键控件使用稳定名称。
- 初始实体 ID 使用 `WORLD_000001` / `PARTY_000001` / `SETTLEMENT_000001`，而非需求示例中的 `settlement_001`（D019）。

### 验证

- 原有 18 项冒烟测试通过。
- Milestone 1 数据/UI 测试、端到端流程测试、主菜单 UI 测试全部通过。
- 主场景无头启动无解析错误与运行时报错。
- 测试存档已清理，`user://saves/` 无残留。

---

## 2026-11-20 · V0.3 架构基线

### 新增

- 建立 `Docs/` 项目记忆文档体系：总索引、核心架构、路线、规范、系统文档、开发状态。
- 建立工程目录骨架：`Scripts/`、`Scenes/`、`Data/`、`Tests/`。
- 注册 5 个 Autoload：`EventBus`、`TimeManager`、`SaveManager`、`SceneManager`、`GameManager`。
- 实现 `TimeManager` 固定步长世界 tick（0.1 秒，单帧最多 10 tick）。
- 实现 JSON 存档基础读写与槽位列表接口。
- 定义核心实体数据类：`UnitData`、`PartyData`、`LordData`、`SettlementData`、`FactionData`。
- 定义静态配置类：`UnitConfig`、`EquipmentConfig`、`FactionConfig`。
- 建立 `WorldContext` + `WorldSimulation` 世界会话结构。
- 建立 `BattleSession` / `BattleUnitState` / `BattleManager` 战斗会话骨架。
- 建立冒烟测试并通过全部检查。

### 决策

- 大地图采用俯视平面；小场景采用横版侧视 + 纵深移动。
- 静态配置使用 `Resource`，运行时实体使用 `RefCounted`，存档使用 JSON。
- 用 `WorldContext` + `WorldSimulation` 替代源规划中的单一 `WorldManager`。
- 暂停使用“原因栈”，而不是单一布尔值。
- 不使用 `Engine.time_scale` 或 `get_tree().paused` 实现游戏暂停。

### 版本管理

- 初始化本地 Git 仓库，默认分支 `main`。
- 创建私有远程仓库并推送首个提交：<https://github.com/WuYiWoYi/wodeqikan>。
- 仓库级代理配置为 `http://127.0.0.1:10808`。

### 未决

- 离屏 AI 对 AI 战斗是否自动结算，见 `Development/Known_Issues.md`。
- 大地图坐标尺度、缩放与地图尺寸未定。
- 渲染器是否从 Forward+ 切换到 Compatibility 待性能验证。

### 来源

- 基于《2D 中世纪沙盒战略游戏核心架构设计与开发规划 V0.2》。
