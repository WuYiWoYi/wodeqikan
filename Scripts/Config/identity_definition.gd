class_name IdentityDefinition
extends Resource
## 新游戏身份静态配置（Data/Identity/Identities/*.tres）。
##
## 只描述身份本身，不保存玩家的选择结果，也不包含任何初始化数值。
## 新增身份只需新增一个 .tres，无需修改身份选择 UI。

@export_category("Identity")
## 唯一身份标识，不依赖显示名称；未来初始化按此 ID 分派。
@export var identity_id: String = ""
@export var display_name: String = ""
## 关联 IdentityCategoryDefinition.category_id，用于展示贵族/平民类型。
@export var category_id: String = ""
## 关联 CultureDefinition.culture_id；身份选择按文化过滤。
@export var culture_id: String = ""

@export_category("Description")
## 身份选择界面展示的背景故事。
@export_multiline var description: String = ""
## 身份加成预览行；未确定的条目使用“待设定”占位，不自行补充数值。
@export var bonus_lines: PackedStringArray = PackedStringArray()

@export_category("New Game Initialization")
## 正式大地图 WorldMapDefinition 的地点 key；新游戏出生点绑定到该地点附近。
## 必须指向实际存在的地点，禁止用显示名称或描述文本模糊匹配。
@export var spawn_location_id: String = ""
## 开局所属视觉家族（FamilyConfig.family_id）；空表示不拥有家族。
@export var family_id: String = ""
## 是否接入家族功能系统。平民身份为 false，不创建玩家家族/贵族记录。
@export var family_system_enabled: bool = false
## 开局是否直接成为所属家族领袖；例如瓦伊拉家族领袖。
@export var starts_as_house_leader: bool = false
## 所属家族是否保持独立：为 true 时不加入任何王国，即使该家族原本是某王国的统治家族。
## 独立家族身份（瓦伊拉家族领袖）必须为 true，避免被错误同步为王国国王。
@export var independent_house: bool = false
## 开局贵族爵位（NobleData.Rank：1 骑士、2 男爵、3 公爵）。
## 平民或非贵族身份为 0，不创建贵族记录。
@export var starting_rank: int = 0

@export_category("Ordering")
## 同一文化、同一身份类型内的显示顺序，升序。
@export var sort_order: int = 0
## 关闭后不会出现在身份选择界面，但仍保留配置。
@export var enabled: bool = true


func validate() -> bool:
	if identity_id.strip_edges().is_empty() \
			or display_name.strip_edges().is_empty() \
			or category_id.strip_edges().is_empty() \
			or culture_id.strip_edges().is_empty() \
			or spawn_location_id.strip_edges().is_empty():
		return false
	# 接入家族系统的身份必须显式绑定旗帜家族与爵位；
	# 平民身份不创建家族/贵族，因此 family_id 与 starting_rank 保持空/0。
	if family_system_enabled:
		if family_id.strip_edges().is_empty() or starting_rank <= 0:
			return false
		# 独立家族必须由本家族领袖开局，否则无法脱离所属王国。
		return not independent_house or starts_as_house_leader
	return family_id.strip_edges().is_empty() and starting_rank == 0 \
		and not independent_house and not starts_as_house_leader
