class_name UiTheme
extends RefCounted
## 共享 UI 主题：优先使用系统中文字体，避免 CJK 缺字。

static var _cached_theme: Theme = null


static func create() -> Theme:
	if _cached_theme != null:
		return _cached_theme
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"Microsoft YaHei UI",
		"Microsoft YaHei",
		"SimHei",
		"Noto Sans CJK SC",
		"Noto Sans",
	])
	theme.default_font = font
	theme.default_font_size = 16
	_cached_theme = theme
	return _cached_theme
