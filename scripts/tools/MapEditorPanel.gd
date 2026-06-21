## MapEditorPanel.gd
## Standalone map authoring panel for generating compiled server map JSON files.
extends Control

const DEFAULT_SAVE_PATH: String = "res://resources/maps/custom_map.json"
const DEFAULT_GRID_W: int = 12
const DEFAULT_GRID_H: int = 8
const MIN_GRID_W: int = 8
const MIN_GRID_H: int = 4
const MAX_GRID_W: int = 96
const MAX_GRID_H: int = 48
const MAP_MARGIN_X: float = 12.0
const MAP_TOP_Y: float = 82.0
const MAP_BOTTOM_MARGIN: float = 12.0
const EDGE_PICK_EPSILON: float = 0.22

enum PaintMode {
	WALL,
	BARRICADE,
	LADDER,
	ERASE,
}

var _mode: PaintMode = PaintMode.WALL
var _save_path: String = DEFAULT_SAVE_PATH
var _grid_w: int = DEFAULT_GRID_W
var _grid_h: int = DEFAULT_GRID_H

## key "x1,y1,z1|x2,y2,z2" -> Dictionary {wall,barricade,ladder}
var _boundaries: Dictionary = {}

var _mode_select: OptionButton
var _path_edit: LineEdit
var _width_spin: SpinBox
var _height_spin: SpinBox
var _status_label: Label

func _ready() -> void:
	_build_toolbar()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _build_toolbar() -> void:
	var toolbar := VBoxContainer.new()
	toolbar.position = Vector2(12.0, 10.0)
	toolbar.add_theme_constant_override("separation", 6)
	add_child(toolbar)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	toolbar.add_child(row1)

	var lbl := Label.new()
	lbl.text = "Mode:"
	row1.add_child(lbl)

	_mode_select = OptionButton.new()
	_mode_select.add_item("Wall")
	_mode_select.add_item("Barricade")
	_mode_select.add_item("Ladder")
	_mode_select.add_item("Erase")
	_mode_select.select(0)
	_mode_select.item_selected.connect(_on_mode_selected)
	row1.add_child(_mode_select)

	var btn_save := Button.new()
	btn_save.text = "Save"
	btn_save.pressed.connect(_save_map)
	row1.add_child(btn_save)

	var btn_load := Button.new()
	btn_load.text = "Load"
	btn_load.pressed.connect(_load_map)
	row1.add_child(btn_load)

	var btn_clear := Button.new()
	btn_clear.text = "Clear"
	btn_clear.pressed.connect(_clear_map)
	row1.add_child(btn_clear)

	var row_dims := HBoxContainer.new()
	row_dims.add_theme_constant_override("separation", 8)
	toolbar.add_child(row_dims)

	var lbl_w := Label.new()
	lbl_w.text = "Width:"
	row_dims.add_child(lbl_w)

	_width_spin = SpinBox.new()
	_width_spin.min_value = MIN_GRID_W
	_width_spin.max_value = MAX_GRID_W
	_width_spin.step = 1
	_width_spin.value = _grid_w
	_width_spin.custom_minimum_size = Vector2(72.0, 0.0)
	_width_spin.value_changed.connect(_on_grid_width_changed)
	row_dims.add_child(_width_spin)

	var lbl_h := Label.new()
	lbl_h.text = "Height:"
	row_dims.add_child(lbl_h)

	_height_spin = SpinBox.new()
	_height_spin.min_value = MIN_GRID_H
	_height_spin.max_value = MAX_GRID_H
	_height_spin.step = 1
	_height_spin.value = _grid_h
	_height_spin.custom_minimum_size = Vector2(72.0, 0.0)
	_height_spin.value_changed.connect(_on_grid_height_changed)
	row_dims.add_child(_height_spin)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	toolbar.add_child(row2)

	var path_lbl := Label.new()
	path_lbl.text = "Map file:"
	row2.add_child(path_lbl)

	_path_edit = LineEdit.new()
	_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_edit.text = DEFAULT_SAVE_PATH
	_path_edit.text_changed.connect(_on_path_changed)
	row2.add_child(_path_edit)

	_status_label = Label.new()
	_status_label.text = "Click boundary lines between cells to paint."
	_status_label.position = Vector2(12.0, 58.0)
	add_child(_status_label)

func _draw() -> void:
	_draw_grid()
	_draw_boundaries()

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return

	var picked: Dictionary = _pick_boundary_from_point(mb.position)
	if picked.is_empty():
		return

	var a: Vector3i = picked["a"]
	var b: Vector3i = picked["b"]
	_toggle_boundary(a, b)
	queue_redraw()

func _draw_grid() -> void:
	var map_rect: Rect2 = _get_map_rect()
	var cell: float = _get_cell_size(map_rect)
	draw_rect(map_rect, Color(0.08, 0.09, 0.10), true)

	for x in range(_grid_w + 1):
		var p1 := map_rect.position + Vector2(x * cell, 0.0)
		var p2 := map_rect.position + Vector2(x * cell, map_rect.size.y)
		draw_line(p1, p2, Color(0.32, 0.33, 0.35), 1.0)
	for y in range(_grid_h + 1):
		var p1 := map_rect.position + Vector2(0.0, y * cell)
		var p2 := map_rect.position + Vector2(map_rect.size.x, y * cell)
		draw_line(p1, p2, Color(0.32, 0.33, 0.35), 1.0)

func _draw_boundaries() -> void:
	for key in _boundaries:
		var bd: Dictionary = _boundaries[key]
		var parts: PackedStringArray = String(key).split("|")
		if parts.size() != 2:
			continue
		var a: Vector3i = _vec_from_key(parts[0])
		var b: Vector3i = _vec_from_key(parts[1])
		var color: Color = Color(1.0, 1.0, 1.0)
		if bd.get("wall", false):
			color = Color(0.95, 0.95, 0.95)
		elif bd.get("barricade", false):
			color = Color(0.95, 0.72, 0.16)
		elif bd.get("ladder", false):
			color = Color(0.35, 0.95, 0.35)
		var p := _edge_points(a, b)
		draw_line(p[0], p[1], color, 4.0)

func _pick_boundary_from_point(pos: Vector2) -> Dictionary:
	var map_rect: Rect2 = _get_map_rect()
	var cell: float = _get_cell_size(map_rect)
	var local: Vector2 = pos - map_rect.position
	if local.x < 0.0 or local.y < 0.0:
		return {}
	if local.x > map_rect.size.x or local.y > map_rect.size.y:
		return {}

	var fx: float = local.x / cell
	var fy: float = local.y / cell

	var vx: int = int(roundf(fx))
	var vy: int = int(floor(fy))
	var dist_v: float = abs(fx - float(vx))

	var hy: int = int(roundf(fy))
	var hx: int = int(floor(fx))
	var dist_h: float = abs(fy - float(hy))

	if dist_v <= dist_h and dist_v <= EDGE_PICK_EPSILON:
		if vx <= 0 or vx >= _grid_w:
			return {}
		if vy < 0 or vy >= _grid_h:
			return {}
		return {"a": Vector3i(vx - 1, vy, 0), "b": Vector3i(vx, vy, 0)}

	if dist_h <= EDGE_PICK_EPSILON:
		if hy <= 0 or hy >= _grid_h:
			return {}
		if hx < 0 or hx >= _grid_w:
			return {}
		return {"a": Vector3i(hx, hy - 1, 0), "b": Vector3i(hx, hy, 0)}

	return {}

func _toggle_boundary(a: Vector3i, b: Vector3i) -> void:
	var key: String = _make_key(a, b)
	if _mode == PaintMode.ERASE:
		_boundaries.erase(key)
		_status_label.text = "Erased boundary %s" % key
		return

	var bd: Dictionary = _boundaries.get(key, {
		"wall": false,
		"barricade": false,
		"ladder": false,
	})

	match _mode:
		PaintMode.WALL:
			var next_wall: bool = not bool(bd.get("wall", false))
			bd["wall"] = next_wall
			bd["barricade"] = false
			bd["ladder"] = false
		PaintMode.BARRICADE:
			var next_barricade: bool = not bool(bd.get("barricade", false))
			bd["barricade"] = next_barricade
			bd["wall"] = false
			bd["ladder"] = false
		PaintMode.LADDER:
			var next_ladder: bool = not bool(bd.get("ladder", false))
			bd["ladder"] = next_ladder
			bd["wall"] = false
			bd["barricade"] = false
		_:
			pass

	if not bd["wall"] and not bd["barricade"] and not bd["ladder"]:
		_boundaries.erase(key)
		_status_label.text = "Cleared boundary %s" % key
	else:
		_boundaries[key] = bd
		_status_label.text = "Updated boundary %s" % key

func _clear_map() -> void:
	_boundaries.clear()
	queue_redraw()
	_status_label.text = "Map cleared."

func _save_map() -> void:
	var data: Dictionary = {
		"width": _grid_w,
		"height": _grid_h,
		"boundaries": [],
	}
	for key in _boundaries:
		var bd: Dictionary = _boundaries[key]
		if not bd.get("wall", false) and not bd.get("barricade", false) and not bd.get("ladder", false):
			continue
		var parts: PackedStringArray = String(key).split("|")
		if parts.size() != 2:
			continue
		data["boundaries"].append({
			"a": _dict_from_vec(_vec_from_key(parts[0])),
			"b": _dict_from_vec(_vec_from_key(parts[1])),
			"wall": bool(bd.get("wall", false)),
			"barricade": bool(bd.get("barricade", false)),
			"ladder": bool(bd.get("ladder", false)),
		})
	var f: FileAccess = FileAccess.open(_save_path, FileAccess.WRITE)
	if f == null:
		_status_label.text = "Failed to save map. Ensure path is writable in editor."
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	_status_label.text = "Saved map to %s" % _save_path

func _load_map() -> void:
	if not FileAccess.file_exists(_save_path):
		_boundaries.clear()
		queue_redraw()
		_status_label.text = "No map file found at %s" % _save_path
		return

	var f: FileAccess = FileAccess.open(_save_path, FileAccess.READ)
	if f == null:
		_status_label.text = "Failed to read map file."
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		_status_label.text = "Invalid map JSON."
		return

	_grid_w = clampi(int(parsed.get("width", DEFAULT_GRID_W)), MIN_GRID_W, MAX_GRID_W)
	_grid_h = clampi(int(parsed.get("height", DEFAULT_GRID_H)), MIN_GRID_H, MAX_GRID_H)
	if _width_spin:
		_width_spin.value = _grid_w
	if _height_spin:
		_height_spin.value = _grid_h

	_boundaries.clear()
	for raw_b in parsed.get("boundaries", []):
		if not (raw_b is Dictionary):
			continue
		var b: Dictionary = raw_b as Dictionary
		var a_dict: Dictionary = b.get("a", {})
		var c_dict: Dictionary = b.get("b", {})
		var a: Vector3i = Vector3i(int(a_dict.get("x", 0)), int(a_dict.get("y", 0)), int(a_dict.get("z", 0)))
		var c: Vector3i = Vector3i(int(c_dict.get("x", 0)), int(c_dict.get("y", 0)), int(c_dict.get("z", 0)))
		if not _is_inside_grid(a) or not _is_inside_grid(c):
			continue
		var key: String = _make_key(a, c)
		_boundaries[key] = {
			"wall": bool(b.get("wall", false)),
			"barricade": bool(b.get("barricade", false)),
			"ladder": bool(b.get("ladder", false)),
		}
	queue_redraw()
	_status_label.text = "Loaded map from %s" % _save_path

func _on_mode_selected(idx: int) -> void:
	_mode = idx as PaintMode

func _on_path_changed(new_text: String) -> void:
	_save_path = new_text.strip_edges()
	if _save_path == "":
		_save_path = DEFAULT_SAVE_PATH

func _on_grid_width_changed(value: float) -> void:
	_grid_w = int(value)
	_prune_boundaries_to_grid()
	queue_redraw()
	_status_label.text = "Grid resized to %dx%d" % [_grid_w, _grid_h]

func _on_grid_height_changed(value: float) -> void:
	_grid_h = int(value)
	_prune_boundaries_to_grid()
	queue_redraw()
	_status_label.text = "Grid resized to %dx%d" % [_grid_w, _grid_h]

func _is_inside_grid(v: Vector3i) -> bool:
	return v.x >= 0 and v.x < _grid_w and v.y >= 0 and v.y < _grid_h and v.z == 0

func _prune_boundaries_to_grid() -> void:
	var to_remove: Array = []
	for key in _boundaries:
		var parts: PackedStringArray = String(key).split("|")
		if parts.size() != 2:
			to_remove.append(key)
			continue
		var a: Vector3i = _vec_from_key(parts[0])
		var b: Vector3i = _vec_from_key(parts[1])
		if not _is_inside_grid(a) or not _is_inside_grid(b):
			to_remove.append(key)
	for key in to_remove:
		_boundaries.erase(key)

func _make_key(a: Vector3i, b: Vector3i) -> String:
	var sa: String = "%d,%d,%d" % [a.x, a.y, a.z]
	var sb: String = "%d,%d,%d" % [b.x, b.y, b.z]
	return (sa + "|" + sb) if sa < sb else (sb + "|" + sa)

func _vec_from_key(s: String) -> Vector3i:
	var p: PackedStringArray = s.split(",")
	if p.size() < 3:
		return Vector3i.ZERO
	return Vector3i(int(p[0]), int(p[1]), int(p[2]))

func _dict_from_vec(v: Vector3i) -> Dictionary:
	return {"x": v.x, "y": v.y, "z": v.z}

func _edge_points(a: Vector3i, b: Vector3i) -> Array[Vector2]:
	var map_rect: Rect2 = _get_map_rect()
	var cell: float = _get_cell_size(map_rect)
	if a.x != b.x:
		var x_edge: float = float(maxi(a.x, b.x))
		var y0: float = float(a.y)
		var p1 := map_rect.position + Vector2(x_edge * cell, y0 * cell)
		var p2 := map_rect.position + Vector2(x_edge * cell, (y0 + 1.0) * cell)
		return [p1, p2]
	var y_edge: float = float(maxi(a.y, b.y))
	var x0: float = float(a.x)
	var q1 := map_rect.position + Vector2(x0 * cell, y_edge * cell)
	var q2 := map_rect.position + Vector2((x0 + 1.0) * cell, y_edge * cell)
	return [q1, q2]

func _get_map_rect() -> Rect2:
	var vp_size: Vector2 = get_viewport_rect().size
	var avail_w: float = maxf(80.0, vp_size.x - MAP_MARGIN_X * 2.0)
	var avail_h: float = maxf(80.0, vp_size.y - MAP_TOP_Y - MAP_BOTTOM_MARGIN)
	var cell: float = minf(avail_w / float(_grid_w), avail_h / float(_grid_h))
	cell = maxf(2.0, cell)
	var draw_size := Vector2(cell * _grid_w, cell * _grid_h)
	var origin := Vector2(
		MAP_MARGIN_X + (avail_w - draw_size.x) * 0.5,
		MAP_TOP_Y + (avail_h - draw_size.y) * 0.5)
	return Rect2(origin, draw_size)

func _get_cell_size(map_rect: Rect2) -> float:
	return map_rect.size.x / float(maxi(1, _grid_w))
