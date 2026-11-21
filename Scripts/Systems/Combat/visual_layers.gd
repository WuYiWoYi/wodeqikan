class_name VisualLayers
extends RefCounted
## 士兵部件最终可见性层级（数值越大越靠前）。
##
## 人物与马匹分别由 HumanVisual / HorseVisual 管理，但两者都是 UnitVisual
## 的直接子组（z_index = 0），因此这里的相对 z 值可以跨组统一排序。
## 实际 canvas z = UnitActor.z_index + UnitVisual.z_index + 部件 z。
##
## 基础顺序：右手武器 → 马头 → 缨饰 → 头盔 → 人头 → 左手武器
## → 人身体 → 人右腿 → 马鞍 → 四条马腿 → 马身体 → 人左腿 → 影子。
## 左右手武器使用独立层级：左手武器必须位于马头之后，避免遮挡马头。
## 头盔位于人头之前；未装备头盔时只显示人头。

## 右手武器保持原有层级（长矛）。
const RIGHT_HAND_WEAPON: int = -10
## 兼容旧名称：现有长矛与测试继续引用 WEAPON。
const WEAPON: int = RIGHT_HAND_WEAPON
const MOUNT_HEAD: int = -20
const PLUME: int = -30
## 头盔位于人头之前、缨饰之后。
const HELMET: int = -35
const HEAD: int = -40
## 左手武器位于马头之后，同时位于人头/身体之前，避免骑兵遮住马头。
const LEFT_HAND_WEAPON: int = -45
const TABARD: int = -49
const BODY: int = -50
const LEG_RIGHT: int = -60
const MOUNT_SADDLE: int = -69
const LEG_LEFT: int = -80

## 四条马腿独立贴图，全部位于马身体之前、马鞍/人右腿之后；
## 四条腿使用同一 z 值，先后由树顺序决定（需求不强制固定顺序）。
const MOUNT_LEG_FRONT: int = -71
const MOUNT_LEG_FRONT_2: int = -71
const MOUNT_LEG_BACK: int = -71
const MOUNT_LEG_BACK_2: int = -71
## 马身体放在马腿之后、人左腿之前；其他部件层级不变。
const MOUNT_BODY: int = -72

const FOOT_SHADOW: int = -99
const MOUNT_SHADOW: int = -99
