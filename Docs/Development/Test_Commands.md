# 测试运行命令（参考）

**用途：** 只在实际运行测试时读取。测试文件清单以 `Tests/` 目录为准，本文件不维护逐测试清单，避免与工程不同步。

**默认策略：** 按 L1–L4 影响范围选择最小测试集，见 [03_Design_Conventions.md §10](../03_Design_Conventions.md#10-测试规范)。不要默认运行全部测试。

## 运行单个测试

```bash
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/UnitTests/<name>.tscn
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/<name>.tscn
```

## 枚举当前测试入口

```bash
find Tests/UnitTests Tests/SystemTests -name "*.tscn" | sort
```

## 无头导入 / 资源刷新

```bash
Godot_v4.6.1-stable_win64.exe --headless --path . --import
```

## 跨进程存档测试

先保存再退出，然后在新进程中读取：

```bash
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/milestone1_restart_test.tscn -- save
Godot_v4.6.1-stable_win64.exe --headless --path . res://Tests/SystemTests/milestone1_restart_test.tscn -- load
```

## 手动视觉验收（非 headless）

用于动画、布局、旗帜可读性等无法仅靠数值断言确认的项目；截图输出到 `user://`。

```bash
Godot_v4.6.1-stable_win64.exe --path . res://Tests/_debug/visual_probe.tscn
Godot_v4.6.1-stable_win64.exe --path . res://Tests/_debug/locomotion_probe.tscn
Godot_v4.6.1-stable_win64.exe --path . res://Tests/_debug/party_preview_probe.tscn
Godot_v4.6.1-stable_win64.exe --path . res://Tests/_debug/main_menu_probe.tscn
Godot_v4.6.1-stable_win64.exe --path . res://Tests/_debug/identity_select_probe.tscn
Godot_v4.6.1-stable_win64.exe --path . res://Tests/_debug/sort_probe.tscn
```

`sort_probe` 用真实骑乘/步兵模型做像素级遮挡对比：`banded`（角色 z 波段）应 0 处穿插，`legacy`（所有角色 z=0）可复现旧问题；输出 `user://sort_probe*.png`。

## 说明

- 测试文件名会随阶段增减；以 `Tests/` 下实际文件为准。
- 新增测试应放在 `Tests/UnitTests/`（纯数据/逻辑）或 `Tests/SystemTests/`（跨系统/场景流程）。
- 已知既有失败：`Tests/UnitTests/supply_manager_test.tscn` 的“NPC 记录 1 份草料缺口”断言（KI534）；运行相关改动时注意区分。
