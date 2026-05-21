## TestMatchScene.gd
## Client-side test match view.
##
## Renders the 8×8 grid map and all characters as placeholder rectangles
## using _draw(), and hosts a right-side HUD (built programmatically from
## Control nodes inside a CanvasLayer) that shows the turn order, HP bars,
## phase-sensitive action buttons, and an event log.
##
## Communicates with the server exclusively via the `action_submitted` signal,
## which Main.gd forwards over the network with rpc_id().
extends Node2D

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted whenever the player submits an action.
signal action_submitted(action: Dictionary)

# ---------------------------------------------------------------------------
# Visual constants
# ---------------------------------------------------------------------------

const TILE_SIZE     : int   = 64    # pixels per grid tile
const CHAR_PAD      : int   = 6     # padding around the character square inside a tile
const HP_BAR_H      : int   = 5     # height of each HP-segment bar in pixels
const HP_BAR_MARGIN : int   = 2     # gap between character square bottom and HP bar top

## Top-left pixel of the map on screen.
const MAP_OFFSET := Vector2(20.0, 20.0)

# Tile / map colours
const C_TILE         := Color(0.18, 0.18, 0.21)
const C_TILE_BORDER  := Color(0.30, 0.30, 0.34)
const C_HOVER        := Color(1.00, 1.00, 1.00, 0.10)
const C_SEL_MOVE     := Color(0.20, 0.90, 0.20, 0.22)
const C_SEL_ATTACK   := Color(0.95, 0.20, 0.20, 0.28)

# Boundary colours
const C_WALL         := Color(0.08, 0.05, 0.04)
const C_BARRICADE    := Color(0.90, 0.70, 0.10)
const C_LADDER       := Color(0.65, 0.40, 0.10)

# Character colours
const C_TEAM_A       := Color(0.25, 0.45, 1.00)   # blue
const C_TEAM_B       := Color(1.00, 0.25, 0.25)   # red
const C_KNOCKED      := Color(0.45, 0.45, 0.45)
const C_DEAD         := Color(0.10, 0.10, 0.10)
const C_ACTIVE_RING  := Color(1.00, 0.92, 0.10)   # yellow ring for active char
const C_CROUCHED     := Color(0.80, 0.80, 0.10, 0.50)  # yellow tint overlay

# HP bar colours
const C_HP_FULL      := Color(0.15, 0.85, 0.15)
const C_HP_LOW       := Color(0.90, 0.10, 0.10)
const C_HP_BG        := Color(0.15, 0.08, 0.08)
const C_HP_DISABLED  := Color(0.20, 0.20, 0.20, 0.50)
const C_HP_BORDER    := Color(0.50, 0.50, 0.50)

# ---------------------------------------------------------------------------
# State (driven entirely by server snapshots)
# ---------------------------------------------------------------------------

var _state     : Dictionary = {}
var _input_mode: String     = "none"  # "none" | "select_move" | "select_attack"
var _hovered   : Vector2i   = Vector2i(-1, -1)

# ---------------------------------------------------------------------------
# UI node references (built in _ready)
# ---------------------------------------------------------------------------

var _lbl_round    : Label
var _lbl_active   : Label
var _lbl_phase    : Label
var _hbox_hp      : HBoxContainer
var _vbox_order   : VBoxContainer
var _hbox_btns    : HBoxContainer
var _grid_facing  : GridContainer
var _rtl_log      : RichTextLabel
var _scroll_log   : ScrollContainer

# Derived layout values (computed once from TILE_SIZE)
var _map_px_wide  : float
var _panel_x      : float

# ---------------------------------------------------------------------------
# _ready — build the UI
# ---------------------------------------------------------------------------

func _ready() -> void:
	_map_px_wide = MAP_OFFSET.x + TILE_SIZE * 8.0
	_panel_x     = _map_px_wide + 16.0
	_build_ui()

func _build_ui() -> void:
	var ui_layer := CanvasLayer.new()
	add_child(ui_layer)

	var panel_w : float = 1280.0 - _panel_x - 8.0
	var panel_h : float = 700.0

	# Outer panel ─────────────────────────────────────────────────────────
	var panel := PanelContainer.new()
	panel.position = Vector2(_panel_x, 10.0)
	panel.size     = Vector2(panel_w, panel_h)
	ui_layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# Round / status ───────────────────────────────────────────────────────
	_lbl_round = Label.new()
	_lbl_round.text = "Connecting to server…"
	vbox.add_child(_lbl_round)

	# Active character ────────────────────────────────────────────────────
	_lbl_active = Label.new()
	_lbl_active.text = "Active: —"
	vbox.add_child(_lbl_active)

	_lbl_phase = Label.new()
	_lbl_phase.text = "Phase: —"
	vbox.add_child(_lbl_phase)

	# HP bars for active character ─────────────────────────────────────────
	var lbl_hp := Label.new()
	lbl_hp.text = "HP (active character):"
	vbox.add_child(lbl_hp)

	_hbox_hp = HBoxContainer.new()
	_hbox_hp.add_theme_constant_override("separation", 3)
	vbox.add_child(_hbox_hp)

	vbox.add_child(HSeparator.new())

	# Turn order ──────────────────────────────────────────────────────────
	var lbl_order := Label.new()
	lbl_order.text = "Turn Order:"
	vbox.add_child(lbl_order)

	_vbox_order = VBoxContainer.new()
	_vbox_order.add_theme_constant_override("separation", 2)
	vbox.add_child(_vbox_order)

	vbox.add_child(HSeparator.new())

	# Action buttons ──────────────────────────────────────────────────────
	_hbox_btns = HBoxContainer.new()
	_hbox_btns.add_theme_constant_override("separation", 4)
	vbox.add_child(_hbox_btns)

	# Facing grid (3×3, hidden unless phase == "pending_rotation") ─────────
	_grid_facing = GridContainer.new()
	_grid_facing.columns = 3
	_grid_facing.add_theme_constant_override("h_separation", 3)
	_grid_facing.add_theme_constant_override("v_separation", 3)
	_grid_facing.visible = false
	# Directions in reading order: NW(7) N(0) NE(1) / W(6) · E(2) / SW(5) S(4) SE(3)
	var facing_entries: Array = [
		["NW", 7], ["N", 0], ["NE", 1],
		["W",  6], ["·", -1], ["E", 2],
		["SW", 5], ["S", 4], ["SE", 3],
	]
	for entry in facing_entries:
		if entry[1] == -1:
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(42.0, 30.0)
			_grid_facing.add_child(spacer)
		else:
			var btn := Button.new()
			btn.text = entry[0]
			btn.custom_minimum_size = Vector2(42.0, 30.0)
			btn.pressed.connect(_on_facing_pressed.bind(entry[1]))
			_grid_facing.add_child(btn)
	vbox.add_child(_grid_facing)

	vbox.add_child(HSeparator.new())

	# Event log ────────────────────────────────────────────────────────────
	var lbl_log := Label.new()
	lbl_log.text = "Event Log:"
	vbox.add_child(lbl_log)

	_scroll_log = ScrollContainer.new()
	_scroll_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_log.custom_minimum_size = Vector2(0.0, 160.0)
	vbox.add_child(_scroll_log)

	_rtl_log = RichTextLabel.new()
	_rtl_log.bbcode_enabled = true
	_rtl_log.fit_content = true
	_rtl_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rtl_log.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_scroll_log.add_child(_rtl_log)

	# Legend label below map (drawn via _draw, but add a static Control too) ─
	var lbl_legend := Label.new()
	lbl_legend.position = Vector2(MAP_OFFSET.x, MAP_OFFSET.y + TILE_SIZE * 8.0 + 6.0)
	lbl_legend.text = (
		"■ Blue = Team A   ■ Red = Team B   ▣ Yellow border = Active\n"
		+ "▬ Dark = Wall   ▬ Gold = Barricade   X = Knocked down"
	)
	lbl_legend.add_theme_font_size_override("font_size", 11)
	ui_layer.add_child(lbl_legend)

# ---------------------------------------------------------------------------
# Public API (called by Main.gd via RPC dispatch)
# ---------------------------------------------------------------------------

## Receives a full state snapshot from the server and refreshes everything.
func apply_state(state: Dictionary) -> void:
	_state = state
	_update_ui()
	queue_redraw()

## Appends a message to the event log and auto-scrolls.
func log_event(message: String) -> void:
	if not _rtl_log:
		return
	_rtl_log.append_text("\n" + message)
	# Defer scroll so the layout has updated.
	call_deferred("_scroll_to_bottom")

func _scroll_to_bottom() -> void:
	if _scroll_log:
		_scroll_log.scroll_vertical = int(_scroll_log.get_v_scroll_bar().max_value)

# ---------------------------------------------------------------------------
# UI update helpers
# ---------------------------------------------------------------------------

func _update_ui() -> void:
	var phase    : String = _state.get("phase", "none")
	var round_n  : int    = _state.get("round", 0)
	var active_id: String = _state.get("active_char", "")

	_lbl_round.text = "Round: %d" % round_n

	var active_char: Dictionary = _find_char_dict(active_id)
	if active_char.is_empty():
		_lbl_active.text = "Active: —"
	else:
		var team_tag: String = "A" if active_char["player_id"] == "player_a" else "B"
		_lbl_active.text = "Active: %s [Team %s]" % [active_char["name"], team_tag]

	_lbl_phase.text = "Phase: %s" % phase

	_rebuild_hp_bars(active_char)
	_rebuild_turn_order()
	_rebuild_buttons(phase)

func _rebuild_hp_bars(char_dict: Dictionary) -> void:
	for c in _hbox_hp.get_children():
		c.queue_free()
	if char_dict.is_empty():
		return
	var segs     : Array = char_dict.get("hp_segments",  [])
	var seg_maxs : Array = char_dict.get("hp_seg_max",   [])
	var disabled : Array = char_dict.get("hp_disabled",  [])
	for i in segs.size():
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(58.0, 20.0)
		bar.max_value = seg_maxs[i] if i < seg_maxs.size() else 1.0
		bar.value     = segs[i] if segs[i] > 0.0 else 0.0
		if i < disabled.size() and disabled[i]:
			bar.value    = 0.0
			bar.modulate = Color(0.35, 0.35, 0.35)
		_hbox_hp.add_child(bar)

func _rebuild_turn_order() -> void:
	for c in _vbox_order.get_children():
		c.queue_free()
	var turn_order : Array  = _state.get("turn_order",  [])
	var active_id  : String = _state.get("active_char", "")
	for char_id in turn_order:
		var cd: Dictionary = _find_char_dict(char_id)
		if cd.is_empty():
			continue
		var lbl := Label.new()
		var prefix: String = "▶ " if char_id == active_id else "  "
		var team_ch: String = "A" if cd["player_id"] == "player_a" else "B"
		lbl.text = "%s%s [%s]" % [prefix, cd["name"], team_ch]
		lbl.add_theme_font_size_override("font_size", 12)
		match int(cd["state"]):
			CharacterData.StateFlag.KNOCKED_DOWN:
				lbl.modulate = Color(0.55, 0.55, 0.55)
			CharacterData.StateFlag.DEAD:
				lbl.modulate = Color(0.28, 0.28, 0.28)
		_vbox_order.add_child(lbl)

func _rebuild_buttons(phase: String) -> void:
	for c in _hbox_btns.get_children():
		c.queue_free()
	_grid_facing.visible = false

	match phase:
		"beginning":
			_add_btn("Skip",    _on_skip_beginning)
			_add_btn("Move…",   _on_move_mode)
			_add_btn("Stand Up",_on_stand_up)
			_add_btn("End Turn",_on_end_turn)
		"pending_rotation":
			_grid_facing.visible = true
		"main":
			_add_btn("Attack…", _on_attack_mode)
			_add_btn("Skip Main",_on_skip_main)
			_add_btn("End Turn", _on_end_turn)
		"ending":
			_add_btn("Crouch",  _on_crouch)
			_add_btn("Stand Up",_on_stand_up)
			_add_btn("End Turn",_on_end_turn)
		_:
			_add_btn("End Turn",_on_end_turn)

	if _input_mode != "none":
		_add_btn("Cancel", _on_cancel)

func _add_btn(label: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.pressed.connect(callback)
	_hbox_btns.add_child(btn)

# ---------------------------------------------------------------------------
# Button callbacks
# ---------------------------------------------------------------------------

func _on_skip_beginning() -> void:
	_submit({"type": "skip_beginning", "char_id": _active_id()})

func _on_move_mode() -> void:
	_input_mode = "select_move"
	_rebuild_buttons(_state.get("phase", ""))
	queue_redraw()

func _on_attack_mode() -> void:
	_input_mode = "select_attack"
	_rebuild_buttons(_state.get("phase", ""))
	queue_redraw()

func _on_stand_up() -> void:
	_submit({"type": "stand_up", "char_id": _active_id()})

func _on_end_turn() -> void:
	_submit({"type": "end_turn", "char_id": _active_id()})

func _on_skip_main() -> void:
	_submit({"type": "skip_main", "char_id": _active_id()})

func _on_crouch() -> void:
	_submit({"type": "crouch", "char_id": _active_id()})

func _on_cancel() -> void:
	_input_mode = "none"
	_rebuild_buttons(_state.get("phase", ""))
	queue_redraw()

func _on_facing_pressed(direction: int) -> void:
	_submit({"type": "facing", "char_id": _active_id(), "direction": direction})

func _submit(action: Dictionary) -> void:
	emit_signal("action_submitted", action)

func _active_id() -> String:
	return _state.get("active_char", "")

# ---------------------------------------------------------------------------
# Input (tile / character clicks for move / attack selection)
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# Hover tracking
	if event is InputEventMouseMotion:
		var tile := _screen_to_tile((event as InputEventMouseMotion).position)
		if tile != _hovered:
			_hovered = tile
			queue_redraw()
		return

	# Left click
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return

	var tile := _screen_to_tile(mb.position)
	if tile.x < 0 or tile.y < 0:
		return

	var aid := _active_id()
	match _input_mode:
		"select_move":
			_input_mode = "none"
			_submit({"type": "move", "char_id": aid,
					 "dest": {"x": tile.x, "y": tile.y, "z": 0}})
			_rebuild_buttons(_state.get("phase", ""))
			queue_redraw()
		"select_attack":
			var target_id := _char_id_at_tile(tile)
			if not target_id.is_empty():
				_input_mode = "none"
				_submit({"type": "attack", "char_id": aid, "target_id": target_id})
				_rebuild_buttons(_state.get("phase", ""))
				queue_redraw()

# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	if _state.is_empty():
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(20.0, 40.0), "Waiting for server…",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		return

	var map_d     : Dictionary = _state.get("map", {})
	var tiles     : Array      = map_d.get("tiles", [])
	var boundaries: Array      = map_d.get("boundaries", [])
	var chars     : Array      = _state.get("characters", [])
	var active_id : String     = _state.get("active_char", "")

	# --- Draw tiles ──────────────────────────────────────────────────────
	for t in tiles:
		var tpos := _tile_pos(t["x"], t["y"])
		var rect  := Rect2(tpos, Vector2(TILE_SIZE, TILE_SIZE))
		draw_rect(rect, C_TILE, true)
		draw_rect(rect, C_TILE_BORDER, false, 1.0)

		# Hover highlight
		if _hovered.x == t["x"] and _hovered.y == t["y"]:
			draw_rect(rect, C_HOVER, true)

		# Selection mode tint
		if _input_mode == "select_move":
			draw_rect(rect, C_SEL_MOVE, true)
		elif _input_mode == "select_attack":
			# Highlight tiles occupied by enemy characters
			for cd in chars:
				var cp: Dictionary = cd["pos"]
				if cp["x"] == t["x"] and cp["y"] == t["y"]:
					var ap_id: Dictionary = _find_char_dict(active_id)
					var active_player: String = ap_id.get("player_id", "")
					if cd["player_id"] != active_player:
						draw_rect(rect, C_SEL_ATTACK, true)

	# --- Draw boundaries ─────────────────────────────────────────────────
	for bd in boundaries:
		_draw_boundary(bd)

	# --- Draw characters ─────────────────────────────────────────────────
	for cd in chars:
		_draw_character(cd, active_id)

func _draw_boundary(bd: Dictionary) -> void:
	var a  := bd["a"]
	var b  := bd["b"]
	var dx := b["x"] - a["x"]
	var dy := b["y"] - a["y"]

	# Only cardinal boundaries get drawn.
	if abs(dx) + abs(dy) != 1:
		return

	var color : Color
	var width : float
	if bd.get("wall", false):
		color = C_WALL
		width = 6.0
	elif bd.get("barricade", false):
		color = C_BARRICADE
		width = 4.0
	elif bd.get("ladder", false):
		color = C_LADDER
		width = 3.0
	else:
		return

	# Derive the two screen points of the shared edge.
	var origin := _tile_pos(a["x"], a["y"])
	var p1     : Vector2
	var p2     : Vector2

	if dx == 1:          # b is to the right
		p1 = origin + Vector2(TILE_SIZE, 0)
		p2 = origin + Vector2(TILE_SIZE, TILE_SIZE)
	elif dx == -1:       # b is to the left
		p1 = origin
		p2 = origin + Vector2(0, TILE_SIZE)
	elif dy == 1:        # b is below
		p1 = origin + Vector2(0, TILE_SIZE)
		p2 = origin + Vector2(TILE_SIZE, TILE_SIZE)
	elif dy == -1:       # b is above
		p1 = origin
		p2 = origin + Vector2(TILE_SIZE, 0)
	else:
		return

	draw_line(p1, p2, color, width)

func _draw_character(cd: Dictionary, active_id: String) -> void:
	var state_int : int        = int(cd["state"])
	var pos       : Dictionary = cd["pos"]
	var char_id   : String     = cd["id"]
	var player_id : String     = cd["player_id"]

	var tile_origin := _tile_pos(pos["x"], pos["y"])

	# Character square rect (padded inside tile; hp bar lives at bottom of tile)
	var sq_top  : float = float(CHAR_PAD)
	var sq_left : float = float(CHAR_PAD)
	var sq_w    : float = float(TILE_SIZE - CHAR_PAD * 2)
	var sq_h    : float = float(TILE_SIZE - CHAR_PAD * 2 - HP_BAR_H - HP_BAR_MARGIN)
	var sq_rect := Rect2(tile_origin + Vector2(sq_left, sq_top), Vector2(sq_w, sq_h))

	# Fill colour
	var fill : Color
	match state_int:
		CharacterData.StateFlag.DEAD:
			fill = C_DEAD
		CharacterData.StateFlag.KNOCKED_DOWN:
			fill = C_KNOCKED
		_:
			fill = C_TEAM_A if player_id == "player_a" else C_TEAM_B

	draw_rect(sq_rect, fill, true)

	# Active character: bright ring
	if char_id == active_id:
		draw_rect(sq_rect, C_ACTIVE_RING, false, 2.5)
	else:
		draw_rect(sq_rect, fill.lightened(0.25), false, 1.0)

	# Knocked-down X
	if state_int == CharacterData.StateFlag.KNOCKED_DOWN:
		draw_line(sq_rect.position, sq_rect.end, Color.WHITE, 2.0)
		draw_line(sq_rect.position + Vector2(sq_w, 0), sq_rect.position + Vector2(0, sq_h), Color.WHITE, 2.0)

	# Crouched tint
	if cd.get("is_crouched", false):
		draw_rect(sq_rect, C_CROUCHED, true)

	# Character initial label (first letter of name)
	var font     := ThemeDB.fallback_font
	var fsize    : int = 13
	var label    : String = cd["name"].substr(0, 1).to_upper()
	var text_pos : Vector2 = sq_rect.get_center() + Vector2(-fsize * 0.3, fsize * 0.4)
	draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color.WHITE)

	# HP bars
	_draw_hp_bars(cd, tile_origin)

func _draw_hp_bars(cd: Dictionary, tile_origin: Vector2) -> void:
	var segs     : Array = cd.get("hp_segments", [])
	var seg_maxs : Array = cd.get("hp_seg_max",  [])
	var disabled : Array = cd.get("hp_disabled", [])

	if segs.is_empty():
		return

	var total_max : float = 0.0
	for m in seg_maxs:
		total_max += float(m)
	if total_max <= 0.0:
		return

	var bar_x     : float = tile_origin.x + float(CHAR_PAD)
	var bar_y     : float = tile_origin.y + float(TILE_SIZE) - float(HP_BAR_H) - float(HP_BAR_MARGIN)
	var bar_total : float = float(TILE_SIZE - CHAR_PAD * 2)
	var gap       : float = 1.0

	var seg_x_offset : float = 0.0
	for i in segs.size():
		var sm : float = float(seg_maxs[i]) if i < seg_maxs.size() else 0.0
		var sw : float = bar_total * (sm / total_max) - gap

		var seg_rect_bg := Rect2(bar_x + seg_x_offset, bar_y, sw, float(HP_BAR_H))

		if i < disabled.size() and disabled[i]:
			draw_rect(seg_rect_bg, C_HP_DISABLED, true)
		else:
			draw_rect(seg_rect_bg, C_HP_BG, true)
			var fill_frac : float = (float(segs[i]) / sm) if sm > 0.0 else 0.0
			if fill_frac > 0.0:
				var fill_rect := Rect2(bar_x + seg_x_offset, bar_y, sw * fill_frac, float(HP_BAR_H))
				var hp_color  : Color = C_HP_FULL.lerp(C_HP_LOW, 1.0 - fill_frac)
				draw_rect(fill_rect, hp_color, true)

		draw_rect(seg_rect_bg, C_HP_BORDER, false, 0.8)
		seg_x_offset += sw + gap

# ---------------------------------------------------------------------------
# Coordinate helpers
# ---------------------------------------------------------------------------

func _tile_pos(tx: int, ty: int) -> Vector2:
	return MAP_OFFSET + Vector2(float(tx * TILE_SIZE), float(ty * TILE_SIZE))

func _screen_to_tile(screen_pos: Vector2) -> Vector2i:
	var rel := screen_pos - MAP_OFFSET
	if rel.x < 0 or rel.y < 0:
		return Vector2i(-1, -1)
	var tx : int = int(rel.x / TILE_SIZE)
	var ty : int = int(rel.y / TILE_SIZE)
	# Validate against known tiles
	var tiles : Array = _state.get("map", {}).get("tiles", [])
	for t in tiles:
		if t["x"] == tx and t["y"] == ty:
			return Vector2i(tx, ty)
	return Vector2i(-1, -1)

# ---------------------------------------------------------------------------
# Lookup helpers
# ---------------------------------------------------------------------------

func _find_char_dict(char_id: String) -> Dictionary:
	for cd in _state.get("characters", []):
		if cd["id"] == char_id:
			return cd
	return {}

func _char_id_at_tile(tile: Vector2i) -> String:
	for cd in _state.get("characters", []):
		var p: Dictionary = cd["pos"]
		if p["x"] == tile.x and p["y"] == tile.y:
			return cd["id"]
	return ""
