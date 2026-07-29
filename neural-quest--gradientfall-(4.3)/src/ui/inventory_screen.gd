class_name InventoryScreen
extends CanvasLayer
## Kern's pack — Phase 1 milestone 10 (inventory / items / Tokens).
##
## Opens on `inventory` (I / gamepad Select), pauses the world, and lists what
## GameState is holding, joined against ContentDB for the authored name, rarity,
## value, and flavor text. Category tabs appear only for categories actually in
## the pack, so it reads clean with four turnips and still reads clean with two
## hundred entries. Healing consumables can be used straight from here.
##
## Built entirely in code (project convention — no .tscn UI, nothing to import),
## styled from ItemStyle so the pack, the HUD toasts, and the world pickups all
## agree about what "rare" looks like.
##
## The vendor half of this milestone is deliberately absent: buying and selling
## needs the Bootstrap dialogue UI from the town milestone, and lands with it.
##
## GDD §10 visible surface: UNSEEN until a live Godot session lays eyes on it.

const PANEL_SIZE: Vector2 = Vector2(940.0, 560.0)
const LIST_WIDTH: float = 360.0
const TAB_ALL: String = "all"

const COL_PANEL: Color = Color(0.09, 0.10, 0.14, 0.96)
const COL_INSET: Color = Color(0.13, 0.15, 0.20, 0.92)
const COL_EDGE: Color = Color(0.55, 0.62, 0.78, 0.35)
const COL_TEXT: Color = Color(0.88, 0.91, 0.96)
const COL_DIM: Color = Color(0.62, 0.67, 0.76)
const COL_TOKEN: Color = Color(1.0, 0.82, 0.35)
const COL_SELECTED: Color = Color(0.30, 0.42, 0.62, 0.85)

var _root: Control
var _tokens_label: Label
var _tab_bar: HBoxContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _detail_name: Label
var _detail_meta: Label
var _detail_body: Label
var _detail_effect: Label
var _detail_note: Label
var _empty_label: Label

var _open: bool = false
var _category: String = TAB_ALL
## Row dictionaries: { "entry": Dictionary, "count": int, "button": Button }
var _rows: Array[Dictionary] = []
var _tabs: Array[String] = []
var _selected: int = -1


func _ready() -> void:
	InputSetup.ensure()  # idempotent; the pack may exist before Kern spawns
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS  # must run while it holds the pause
	_build_ui()
	_root.visible = false
	EventBus.tokens_changed.connect(_on_tokens_changed)


func is_open() -> bool:
	return _open


# --- Input -------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"inventory"):
		_toggle()
		get_viewport().set_input_as_handled()
		return
	if not _open:
		return
	if event.is_action_pressed(&"ui_cancel"):
		close()
	elif event.is_action_pressed(&"ui_down"):
		_move_selection(1)
	elif event.is_action_pressed(&"ui_up"):
		_move_selection(-1)
	elif event.is_action_pressed(&"ui_right"):
		_cycle_category(1)
	elif event.is_action_pressed(&"ui_left"):
		_cycle_category(-1)
	elif event.is_action_pressed(&"ui_accept"):
		_use_selected()
	else:
		return
	get_viewport().set_input_as_handled()


func _toggle() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	if _open:
		return
	_open = true
	_category = TAB_ALL
	_rebuild()
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Contents ----------------------------------------------------------------

func _rebuild() -> void:
	var held: Array[Dictionary] = _held_entries()
	_rebuild_tabs(held)
	var shown: Array[Dictionary] = []
	for row: Dictionary in held:
		if _category == TAB_ALL or ItemStyle.category_of(row["entry"]) == _category:
			shown.append(row)
	shown.sort_custom(_sort_rows)
	_fill_list(shown)
	_update_tokens()
	_select(0 if not shown.is_empty() else -1)


## GameState holds ids and counts; ContentDB holds everything else. An id with
## no approved entry still lists (a save can outlive a content edit) — it just
## shows as an unknown oddment rather than vanishing silently.
func _held_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in GameState.inventory.keys():
		var count: int = int(GameState.inventory[id])
		if count <= 0:
			continue
		var entry: Dictionary = ContentDB.get_entry("items", id)
		if entry.is_empty():
			entry = {"id": id, "name": id, "category": "", "rarity": "common",
				"value": 0, "description": "An oddment the archive has no record of."}
		out.append({"entry": entry, "count": count, "button": null})
	return out


func _sort_rows(a: Dictionary, b: Dictionary) -> bool:
	return ItemStyle.sort_entries(a["entry"], b["entry"])


func _rebuild_tabs(held: Array[Dictionary]) -> void:
	var present: Array[String] = []
	for row: Dictionary in held:
		var cat: String = ItemStyle.category_of(row["entry"])
		if not cat.is_empty() and not present.has(cat):
			present.append(cat)
	_tabs.clear()
	_tabs.append(TAB_ALL)
	for cat: String in ItemStyle.CATEGORY_ORDER:
		if present.has(cat):
			_tabs.append(cat)
	if not _tabs.has(_category):
		_category = TAB_ALL

	_clear(_tab_bar)
	for cat: String in _tabs:
		var b: Button = Button.new()
		b.text = "All" if cat == TAB_ALL else str(ItemStyle.CATEGORY_LABEL.get(cat, cat))
		b.focus_mode = Control.FOCUS_NONE
		b.flat = true
		b.add_theme_color_override(&"font_color", COL_TEXT if cat == _category else COL_DIM)
		b.add_theme_font_size_override(&"font_size", 17)
		b.pressed.connect(_on_tab_pressed.bind(cat))
		_tab_bar.add_child(b)


## queue_free() alone leaves the old children in the container for the rest of
## the frame, which would double the list on every rebuild — detach first.
func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _fill_list(shown: Array[Dictionary]) -> void:
	_clear(_list)
	_rows = shown
	_empty_label.visible = shown.is_empty()
	for i: int in _rows.size():
		var row: Dictionary = _rows[i]
		var entry: Dictionary = row["entry"]
		var b: Button = Button.new()
		b.text = "%s   ×%d" % [
			ItemStyle.display_name(str(entry.get("id", "")), entry), int(row["count"]),
		]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0.0, 34.0)
		b.add_theme_color_override(&"font_color", ItemStyle.rarity_color(entry))
		b.add_theme_color_override(&"font_hover_color", ItemStyle.rarity_color(entry))
		b.add_theme_color_override(&"font_pressed_color", COL_TEXT)
		b.add_theme_font_size_override(&"font_size", 18)
		b.add_theme_stylebox_override(&"pressed", _row_box(COL_SELECTED))
		b.pressed.connect(_on_row_pressed.bind(i))
		_list.add_child(b)
		row["button"] = b


func _on_tab_pressed(cat: String) -> void:
	_category = cat
	_rebuild()


func _on_row_pressed(index: int) -> void:
	# A second press on the highlighted row uses it — click-click to drink.
	if index == _selected:
		_use_selected()
	else:
		_select(index)


func _cycle_category(step: int) -> void:
	if _tabs.size() <= 1:
		return
	var i: int = _tabs.find(_category)
	_category = _tabs[wrapi(i + step, 0, _tabs.size())]
	_rebuild()


func _move_selection(step: int) -> void:
	if _rows.is_empty():
		return
	_select(wrapi(_selected + step, 0, _rows.size()))


func _select(index: int) -> void:
	_selected = index
	for i: int in _rows.size():
		var b: Button = _rows[i]["button"]
		if b == null:
			continue
		var fill: Color = COL_SELECTED if i == index else Color(0.0, 0.0, 0.0, 0.0)
		b.add_theme_stylebox_override(&"normal", _row_box(fill))
		b.add_theme_stylebox_override(&"hover", _row_box(fill.lerp(COL_SELECTED, 0.45)))
	if index < 0 or index >= _rows.size():
		_show_detail({}, 0)
		return
	var row: Dictionary = _rows[index]
	_show_detail(row["entry"], int(row["count"]))
	var button: Button = row["button"]
	if button != null and _scroll != null:
		_scroll.ensure_control_visible(button)


func _show_detail(entry: Dictionary, count: int) -> void:
	_detail_note.text = ""
	if entry.is_empty():
		_detail_name.text = ""
		_detail_meta.text = ""
		_detail_body.text = ""
		_detail_effect.text = ""
		return
	_detail_name.text = ItemStyle.display_name(str(entry.get("id", "")), entry)
	_detail_name.add_theme_color_override(&"font_color", ItemStyle.rarity_color(entry))
	_detail_meta.text = "%s · %s · %d Tokens each · %d held" % [
		ItemStyle.category_label(entry), ItemStyle.rarity_label(entry),
		int(entry.get("value", 0)), count,
	]
	_detail_body.text = str(entry.get("description", ""))
	if ItemStyle.is_usable(entry):
		_detail_effect.text = "Restores %s hearts.        [Enter] Use" % _hearts_text(ItemStyle.heal_amount(entry))
		_detail_effect.add_theme_color_override(&"font_color", Color(0.60, 0.90, 0.66))
	elif bool(entry.get("craftable", false)):
		_detail_effect.text = "Can be made from a recipe — the crafting bench comes later."
		_detail_effect.add_theme_color_override(&"font_color", COL_DIM)
	else:
		_detail_effect.text = "Nothing to do with it yet. Somebody will want it."
		_detail_effect.add_theme_color_override(&"font_color", COL_DIM)


func _hearts_text(amount: float) -> String:
	return "%.1f" % amount if not is_equal_approx(amount, roundf(amount)) else "%d" % int(amount)


# --- Using an item -----------------------------------------------------------

func _use_selected() -> void:
	if _selected < 0 or _selected >= _rows.size():
		return
	var entry: Dictionary = _rows[_selected]["entry"]
	var item_id: String = str(entry.get("id", ""))
	if not ItemStyle.is_usable(entry):
		_note("That isn't something Kern can use out here.")
		return
	var player: Node = get_tree().get_first_node_in_group(&"player")
	if player == null or not player.has_method(&"heal_hearts"):
		_note("Kern isn't here to use it.")
		return
	var amount: float = ItemStyle.heal_amount(entry)
	if not bool(player.heal_hearts(amount)):
		_note("Kern is already at full hearts.")
		return
	if not GameState.remove_item(item_id, 1):
		return
	var used_name: String = ItemStyle.display_name(item_id, entry)
	var kept: int = _selected
	_rebuild()
	_select(mini(kept, _rows.size() - 1))
	_note("%s — %s hearts restored." % [used_name, _hearts_text(amount)])


func _note(text: String) -> void:
	_detail_note.text = text


func _on_tokens_changed(_new_total: int) -> void:
	_update_tokens()


func _update_tokens() -> void:
	if _tokens_label != null:
		_tokens_label.text = "%d Tokens" % GameState.tokens


# --- Code-built layout -------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "PackRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow clicks meant for the world
	add_child(_root)

	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.05, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = PANEL_SIZE
	panel.add_theme_stylebox_override(&"panel", _box(COL_PANEL, 1.5, 10.0))
	center.add_child(panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	panel.add_child(column)

	column.add_child(_build_header())
	column.add_child(HSeparator.new())
	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override(&"separation", 6)
	column.add_child(_tab_bar)
	column.add_child(_build_body())
	column.add_child(HSeparator.new())
	column.add_child(_build_footer())


func _build_header() -> Control:
	var header: HBoxContainer = HBoxContainer.new()
	var title: Label = _label("PACK", 26, COL_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_tokens_label = _label("0 Tokens", 22, COL_TOKEN)
	_tokens_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_tokens_label)
	return header


func _build_body() -> Control:
	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 14)

	var left: PanelContainer = PanelContainer.new()
	left.custom_minimum_size = Vector2(LIST_WIDTH, 0.0)
	left.add_theme_stylebox_override(&"panel", _box(COL_INSET, 1.0, 8.0))
	body.add_child(left)

	var left_column: VBoxContainer = VBoxContainer.new()
	left.add_child(left_column)
	_empty_label = _label(
		"Your pack is empty.\n\nThe meadow is full of things worth picking up — walk over anything that glows.",
		17, COL_DIM
	)
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_column.add_child(_empty_label)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_column.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 2)
	_scroll.add_child(_list)

	var right: PanelContainer = PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_stylebox_override(&"panel", _box(COL_INSET, 1.0, 8.0))
	body.add_child(right)

	var detail: VBoxContainer = VBoxContainer.new()
	detail.add_theme_constant_override(&"separation", 12)
	right.add_child(detail)
	_detail_name = _label("", 24, COL_TEXT)
	detail.add_child(_detail_name)
	_detail_meta = _label("", 16, COL_DIM)
	detail.add_child(_detail_meta)
	_detail_body = _label("", 18, COL_TEXT)
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(_detail_body)
	_detail_effect = _label("", 17, COL_DIM)
	_detail_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_detail_effect)
	_detail_note = _label("", 17, COL_TOKEN)
	_detail_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_detail_note)
	return body


func _build_footer() -> Control:
	return _label(
		"↑↓ select    ←→ category    Enter / A use    I or Esc close",
		15, COL_DIM
	)


func _label(text: String, size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	return l


## A list row's highlight: same shape as the panels, far tighter padding.
func _row_box(fill: Color) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	return sb


func _box(fill: Color, border: float, radius: float) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(radius))
	sb.set_content_margin_all(14.0)
	if border > 0.0:
		sb.set_border_width_all(int(border))
		sb.border_color = COL_EDGE
	return sb
