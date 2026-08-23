@tool
extends EditorPlugin

# ============================================================
#  >>> 用户可配置区域 <<<
# ============================================================
# 书签关键词（支持多个）
const BOOKMARK_KEYWORDS = ["bookmark", "DO"]

# 行注释前缀（支持 #）
const COMMENT_PREFIXES = ["#"]

# 按钮固定高度（像素）
const BUTTON_HEIGHT = 30

# 停靠面板标题
const DOCK_TITLE = "标记跳转"

# 按钮间距（水平）和行间距
const BUTTON_SEPARATION = 8
const LINE_SEPARATION = 6

# 按钮样式颜色（可微调）
const BORDER_COLOR = Color(0.6, 0.6, 0.6, 0.8)
const BG_COLOR = Color(0.15, 0.15, 0.15, 0.4)
const HOVER_BORDER = Color(0.8, 0.8, 0.9, 1.0)
const HOVER_BG = Color(0.25, 0.25, 0.3, 0.6)
const PRESSED_BORDER = Color(0.4, 0.6, 1.0, 0.9)
const PRESSED_BG = Color(0.1, 0.2, 0.4, 0.7)
const CORNER_RADIUS = 4
# ============================================================

var dock: EditorDock
var bookmarks_panel: PanelContainer
var scroll_container: ScrollContainer
var button_flow: FlowContainer

var current_script: Script = null
var current_editor: ScriptEditorBase = null
var current_base_editor: CodeEdit = null

var bookmark_regex: RegEx


func _enter_tree():
	# 动态构建正则表达式（使用字符串 join 方法）
	var prefix_str = "(" + "|".join(COMMENT_PREFIXES) + ")"
	var keywords_str = "(" + "|".join(BOOKMARK_KEYWORDS) + ")"
	var pattern = "^\\s*" + prefix_str + "\\s*" + keywords_str + "\\s*:\\s*(.+)$"
	bookmark_regex = RegEx.new()
	bookmark_regex.compile(pattern)

	# 创建停靠面板
	dock = EditorDock.new()
	dock.title = DOCK_TITLE
	dock.default_slot = EditorDock.DOCK_SLOT_BOTTOM

	bookmarks_panel = PanelContainer.new()
	bookmarks_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bookmarks_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	bookmarks_panel.add_child(scroll_container)

	button_flow = FlowContainer.new()
	button_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_flow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button_flow.alignment = FlowContainer.ALIGNMENT_BEGIN
	button_flow.add_theme_constant_override("separation", BUTTON_SEPARATION)
	button_flow.add_theme_constant_override("line_separation", LINE_SEPARATION)
	scroll_container.add_child(button_flow)

	dock.add_child(bookmarks_panel)
	add_dock(dock)

	var script_editor = get_editor_interface().get_script_editor()
	script_editor.editor_script_changed.connect(_on_script_changed)

	call_deferred("_initialize_current_script")


func _initialize_current_script():
	var script_editor = get_editor_interface().get_script_editor()
	_on_script_changed(script_editor.get_current_script())


func _exit_tree():
	var script_editor = get_editor_interface().get_script_editor()
	if script_editor.editor_script_changed.is_connected(_on_script_changed):
		script_editor.editor_script_changed.disconnect(_on_script_changed)

	if current_base_editor and current_base_editor.text_changed.is_connected(_on_text_changed):
		current_base_editor.text_changed.disconnect(_on_text_changed)

	remove_dock(dock)
	dock.queue_free()
	dock = null


func _on_script_changed(script: Script):
	if current_base_editor and current_base_editor.text_changed.is_connected(_on_text_changed):
		current_base_editor.text_changed.disconnect(_on_text_changed)
	current_base_editor = null

	current_script = script
	var script_editor = get_editor_interface().get_script_editor()
	current_editor = script_editor.get_current_editor()

	if current_editor:
		var base = current_editor.get_base_editor()
		if base:
			current_base_editor = base
			if not current_base_editor.text_changed.is_connected(_on_text_changed):
				current_base_editor.text_changed.connect(_on_text_changed)
			_update_bookmarks()
		else:
			call_deferred("_delayed_update")
	else:
		_update_bookmarks()


func _delayed_update():
	if current_editor:
		var base = current_editor.get_base_editor()
		if base:
			current_base_editor = base
			if not current_base_editor.text_changed.is_connected(_on_text_changed):
				current_base_editor.text_changed.connect(_on_text_changed)
			_update_bookmarks()


func _on_text_changed():
	_update_bookmarks()


func _create_styled_button(text: String, line: int) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.tooltip_text = "跳转到第 %d 行" % line
	btn.flat = false
	btn.connect("pressed", Callable(self, "_on_bookmark_pressed").bind(line))

	btn.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var style = StyleBoxFlat.new()
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = BORDER_COLOR
	style.bg_color = BG_COLOR
	style.corner_radius_top_left = CORNER_RADIUS
	style.corner_radius_top_right = CORNER_RADIUS
	style.corner_radius_bottom_left = CORNER_RADIUS
	style.corner_radius_bottom_right = CORNER_RADIUS
	btn.add_theme_stylebox_override("normal", style)

	var hover_style = style.duplicate()
	hover_style.border_color = HOVER_BORDER
	hover_style.bg_color = HOVER_BG
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style = style.duplicate()
	pressed_style.border_color = PRESSED_BORDER
	pressed_style.bg_color = PRESSED_BG
	btn.add_theme_stylebox_override("pressed", pressed_style)

	return btn


func _update_bookmarks():
	for child in button_flow.get_children():
		button_flow.remove_child(child)
		child.free()

	if not current_base_editor:
		return

	var source = current_base_editor.text
	if source.is_empty():
		return

	var lines = source.split("\n")
	var bookmarks = []

	for i in range(lines.size()):
		var result = bookmark_regex.search(lines[i])
		if result:
			var text = result.get_string(3).strip_edges()  # 捕获组3 = 冒号后的内容
			if not text.is_empty():
				bookmarks.append({"line": i + 1, "text": text})

	for bm in bookmarks:
		var btn = _create_styled_button(bm.text, bm.line)
		button_flow.add_child(btn)

	bookmarks_panel.queue_redraw()
	button_flow.queue_sort()


func _on_bookmark_pressed(line: int):
	var editor = get_editor_interface().get_script_editor().get_current_editor()
	if editor:
		var base = editor.get_base_editor()
		if base:
			base.set_caret_line(line - 1)
			base.center_viewport_to_caret()
