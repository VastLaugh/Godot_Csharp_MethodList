@tool
extends EditorPlugin

# ============================================================
#  >>> USER CONFIGURABLE REGION <<<
# ============================================================
# Fixed button height (pixels)
const BUTTON_HEIGHT = 26

# Dock panel title
const DOCK_TITLE = "C# Methods"

# Vertical separation between lines
const LINE_SEPARATION = 1

# The exact curly bracket nesting depth where methods reside.
# Depth 1 = Directly inside the first outer curly bracket block (e.g., a top-level Class).
const TARGET_DEPTH = 1

# Button style colors (flat style matching the native editor)
const BORDER_COLOR = Color(0, 0, 0, 0) # No border by default
const BG_COLOR = Color(0, 0, 0, 0)     # Transparent by default
const HOVER_BORDER = Color(1, 1, 1, 0.05)
const HOVER_BG = Color(1, 1, 1, 0.08)
const PRESSED_BORDER = Color(1, 1, 1, 0.1)
const PRESSED_BG = Color(1, 1, 1, 0.15)
const TEXT_COLOR = Color(0.85, 0.85, 0.85, 1.0)
const HOVER_TEXT_COLOR = Color(1.0, 1.0, 1.0, 1.0)
const CORNER_RADIUS = 2
# ============================================================

var dock: EditorDock
var bookmarks_panel: PanelContainer
var scroll_container: ScrollContainer
var button_list: VBoxContainer

var current_script: Script = null
var current_editor: ScriptEditorBase = null
var current_base_editor: CodeEdit = null

var method_regex: RegEx


func _enter_tree():
	# Regex pattern updated to match C# method signatures up to the opening parenthesis,
	# allowing multi-line/new-line delineated arguments to be properly detected.
	var pattern = "(?:public|private|protected|internal|protected internal|private protected)?\\s*(?:static|virtual|override|abstract|async|unsafe)?\\s*(?:[a-zA-Z0-9_\\[\\]<>]+)\\s+([a-zA-Z0-9_]+)\\s*\\("
	method_regex = RegEx.new()
	method_regex.compile(pattern)

	# Create dock panel
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

	# Initialize vertical list container
	button_list = VBoxContainer.new()
	button_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button_list.add_theme_constant_override("separation", LINE_SEPARATION)
	scroll_container.add_child(button_list)

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
	
	# Guard clause: Verify that the current script exists and is a C# script (.cs)
	if not current_script or current_script.resource_path.get_extension().to_lower() != "cs":
		_clear_list()
		return

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
		_clear_list()


func _delayed_update():
	# Re-verify the current script extension before processing deferred updates
	if not current_script or current_script.resource_path.get_extension().to_lower() != "cs":
		_clear_list()
		return

	if current_editor:
		var base = current_editor.get_base_editor()
		if base:
			current_base_editor = base
			if not current_base_editor.text_changed.is_connected(_on_text_changed):
				current_base_editor.text_changed.connect(_on_text_changed)
			_update_bookmarks()


func _on_text_changed():
	_update_bookmarks()


func _clear_list():
	for child in button_list.get_children():
		button_list.remove_child(child)
		child.free()
	bookmarks_panel.queue_redraw()


func _create_styled_button(text: String, line: int) -> Button:
	var btn = Button.new()
	btn.text = " Line %d:  %s" % [line, text]
	btn.tooltip_text = "Jump to line %d" % line
	btn.flat = true 
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT 
	btn.clip_text = true 
	btn.connect("pressed", Callable(self, "_on_bookmark_pressed").bind(line))

	btn.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL 

	btn.add_theme_color_override("font_color", TEXT_COLOR)
	btn.add_theme_color_override("font_hover_color", HOVER_TEXT_COLOR)
	btn.add_theme_color_override("font_focus_color", HOVER_TEXT_COLOR)
	btn.add_theme_color_override("font_pressed_color", HOVER_TEXT_COLOR)

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
	
	style.content_margin_left = 6
	style.content_margin_right = 6
	
	btn.add_theme_stylebox_override("normal", style)

	var hover_style = style.duplicate()
	hover_style.border_color = HOVER_BORDER
	hover_style.bg_color = HOVER_BG
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("focus", hover_style) 

	var pressed_style = style.duplicate()
	pressed_style.border_color = PRESSED_BORDER
	pressed_style.bg_color = PRESSED_BG
	btn.add_theme_stylebox_override("pressed", pressed_style)

	return btn


func _on_bookmark_pressed(line: int):
	if current_base_editor:
		current_base_editor.set_caret_line(line - 1)
		current_base_editor.grab_focus()


func _update_bookmarks():
	_clear_list()

	if not current_base_editor:
		return

	var source = current_base_editor.text
	if source.is_empty():
		return

	var lines = source.split("\n")
	var bookmarks = []
	
	var current_brace_depth = 0
	var keywords = ["if", "for", "foreach", "while", "switch", "using", "catch"]

	for i in range(lines.size()):
		var raw_line = lines[i]
		
		# Build a clean line char-by-char, ignoring text inside string literals 
		# and ignoring everything after an actual comment starts.
		var clean_line = ""
		var inside_string = false
		var escaped = false
		
		var j = 0
		while j < raw_line.length():
			var char = raw_line[j]
			
			if escaped:
				escaped = false
				j += 1
				continue
				
			if char == "\\":
				escaped = true
				j += 1
				continue
				
			if char == "\"":
				inside_string = not inside_string
				clean_line += char
				j += 1
				continue
				
			if not inside_string:
				# Look ahead for a single line comment //
				if char == "/" and j + 1 < raw_line.length() and raw_line[j + 1] == "/":
					break # Halt parsing this line; the rest is a comment
				
				# Keep tracked structural braces
				if char == "{" or char == "}":
					clean_line += char
				elif char.is_empty() or char == " " or char == "\t" or char.is_valid_identifier() or char in ["(", ")", "<", ">", "[", "]", ",", ";", "*"]:
					# Keep normal coding characters for method regex signature matching
					clean_line += char
			else:
				# While inside a string, we strip out structural characters 
				# so that "res://..." or text brackets don't trigger brace tracking.
				if char != "{" and char != "}":
					clean_line += " " # Replace string content with padding space
			j += 1

		# 2. Check if a method signature starts. 
		# We check if it matches while *strictly* at the target brace depth level.
		if current_brace_depth == TARGET_DEPTH:
			var result = method_regex.search(clean_line)
			if result:
				var method_name = result.get_string(1).strip_edges()
				if not method_name.is_empty() and not method_name in keywords:
					bookmarks.append({"line": i + 1, "text": method_name})

		# 3. Track depth brackets across lines to evaluate the current scope
		for char in clean_line:
			if char == "{":
				current_brace_depth += 1
			elif char == "}":
				current_brace_depth = max(0, current_brace_depth - 1)

	for bm in bookmarks:
		var btn = _create_styled_button(bm.text, bm.line)
		button_list.add_child(btn)

	bookmarks_panel.queue_redraw()
